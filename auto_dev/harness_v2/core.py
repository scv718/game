"""Harness V2 deterministic gates.

The module contains policy and Git operations only. Model execution remains
owned by the existing V1 runner; V2 consumes its attempt result and makes the
provenance/integration decision deterministically.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from typing import Iterable, Optional


class Lifecycle(str, Enum):
    WORKTREE_CREATED = "WORKTREE_CREATED"
    ENV_BOOTSTRAPPED = "ENV_BOOTSTRAPPED"
    BASELINE_HEALTHY = "BASELINE_HEALTHY"
    IMPLEMENT = "IMPLEMENT"
    SOURCE_VALIDATED = "SOURCE_VALIDATED"
    SOURCE_COMMITTED = "SOURCE_COMMITTED"
    WAIT_INTEGRATION = "WAIT_INTEGRATION"
    INTEGRATING = "INTEGRATING"
    INTEGRATED = "INTEGRATED"
    REGRESSION_PASS = "REGRESSION_PASS"
    DONE = "DONE"
    INTEGRATION_CONFLICT = "INTEGRATION_CONFLICT"
    CANONICAL_REVIEW_REQUIRED = "CANONICAL_REVIEW_REQUIRED"


@dataclass
class TaskState:
    task_id: str
    status: str = Lifecycle.WORKTREE_CREATED.value
    baseline_commit: str = ""
    source_branch: str = ""
    source_worktree: str = ""
    source_commit: str = ""
    integration_status: str = ""
    integrated_commit: str = ""
    depends_on: list[str] = field(default_factory=list)
    source_validation_result: str = ""
    integration_validation_result: str = ""
    attempt_id: str = ""
    failure_class: str = ""
    last_error: str = ""
    history: list[str] = field(default_factory=list)

    def set(self, status: Lifecycle | str, **fields):
        self.status = status.value if isinstance(status, Lifecycle) else str(status)
        if not self.history or self.history[-1] != self.status:
            self.history.append(self.status)
        for key, value in fields.items():
            if not hasattr(self, key):
                raise ValueError("unknown task state field: {}".format(key))
            setattr(self, key, value)
        return self

    def can_done(self) -> bool:
        return bool(
            self.source_validation_result == "PASS"
            and self.source_commit
            and self.integration_status == Lifecycle.INTEGRATED.value
            and self.integrated_commit
            and self.integration_validation_result == "PASS"
        )


class V2StateStore:
    """Atomic JSON state store; Git hashes are durable checkpoint anchors."""

    def __init__(self, path: str):
        self.path = Path(path)

    def load(self) -> dict:
        if not self.path.exists():
            return {"version": 2, "integration_baseline_commit": "", "tasks": {}}
        with self.path.open(encoding="utf-8") as fh:
            value = json.load(fh)
        if not isinstance(value, dict) or not isinstance(value.get("tasks", {}), dict):
            raise ValueError("invalid V2 state file: {}".format(self.path))
        return value

    def save(self, state: dict):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix=self.path.name + ".", suffix=".tmp",
                                    dir=str(self.path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(state, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
            os.replace(temp, self.path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)

    def put_task(self, task: TaskState):
        state = self.load()
        state.setdefault("tasks", {})[task.task_id] = asdict(task)
        self.save(state)

    def get_task(self, task_id: str) -> Optional[TaskState]:
        raw = self.load().get("tasks", {}).get(task_id)
        return TaskState(**raw) if raw else None

    def set_baseline(self, commit: str):
        state = self.load()
        state["integration_baseline_commit"] = commit
        self.save(state)


def git(repo: str, *args: str, timeout: int = 120) -> tuple[int, str, str]:
    proc = subprocess.run(["git", "-C", repo, *args], text=True,
                          capture_output=True, encoding="utf-8", errors="replace",
                          timeout=timeout)
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def git_required(repo: str, *args: str, timeout: int = 120) -> str:
    code, out, err = git(repo, *args, timeout=timeout)
    if code:
        raise RuntimeError("git {} failed: {}".format(" ".join(args), (err or out).strip()))
    return out.strip()


IGNORED_PARTS = ("/.git/", "/.godot/", "/.import/", "/auto_dev/logs/",
                 "/test_results/", "/__pycache__/")
IGNORED_EXTENSIONS = (".pyc", ".pyo", ".import", ".tmp", ".log")


def meaningful_path(path: str) -> bool:
    normalized = "/" + path.replace("\\", "/").lower().lstrip("/") + "/"
    return not any(part in normalized for part in IGNORED_PARTS) and not path.lower().endswith(IGNORED_EXTENSIONS)


def worktree_snapshot(root: str) -> dict[str, str]:
    result = {}
    for path in Path(root).rglob("*"):
        if not path.is_file() or ".git" in path.parts or ".godot" in path.parts:
            continue
        rel = path.relative_to(root).as_posix()
        if meaningful_path(rel):
            result[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def attempt_delta(root: str, before: dict[str, str]) -> list[str]:
    after = worktree_snapshot(root)
    paths = {p for p, digest in after.items() if before.get(p) != digest}
    paths.update(p for p in before if p not in after)
    return sorted(paths)


def changed_status_paths(root: str) -> list[str]:
    raw = git_required(root, "status", "--porcelain=v1")
    result = []
    for line in raw.splitlines():
        if len(line) < 4:
            continue
        path = line[3:].strip().strip('"').replace("\\", "/")
        if " -> " in path:
            path = path.rsplit(" -> ", 1)[1]
        if meaningful_path(path):
            result.append(path)
    return sorted(set(result))


def source_commit(root: str, task: TaskState, before: dict[str, str], summary: str) -> tuple[str, list[str]]:
    """Validate, explicitly stage attempt files, and create deterministic source commit."""
    delta = [p for p in attempt_delta(root, before) if os.path.isfile(os.path.join(root, p))]
    if not delta:
        raise RuntimeError("NO_CODE_DIFF")
    if not all(meaningful_path(p) for p in delta):
        raise RuntimeError("attempt contains non-production artifact")
    code, _, err = git(root, "add", "--", *delta)
    if code:
        raise RuntimeError("source stage failed: {}".format(err.strip()))
    staged = git_required(root, "diff", "--cached", "--name-only").splitlines()
    staged = sorted(set(p.replace("\\", "/") for p in staged))
    if set(staged) != set(delta):
        raise RuntimeError("scope drift: staged files differ from attempt delta")
    message = "task({}): implement {}".format(task.task_id, " ".join(summary.split())[:120])
    git_required(root, "commit", "-m", message)
    commit = git_required(root, "rev-parse", "HEAD")
    remaining_targets = [p for p in delta if changed_status_paths_for_path(root, p)]
    if remaining_targets:
        raise RuntimeError("SOURCE_DELTA_NOT_CLEAN: {}".format(", ".join(remaining_targets)))
    task.set(Lifecycle.SOURCE_COMMITTED, source_commit=commit)
    return commit, delta


def changed_status_paths_for_path(root: str, path: str) -> bool:
    code, out, _ = git(root, "status", "--porcelain=v1", "--", path)
    return code != 0 or bool(out.strip())


def classify_failure(text: str, *, phase: str = "") -> str:
    value = (text or "").lower()
    if "conflict" in value or "merge conflict" in value:
        return "INTEGRATION_CONFLICT"
    if "bootstrap" in value or "import" in value:
        return "BOOTSTRAP_FAILED"
    if "baseline" in value and ("fail" in value or "error" in value):
        return "BASELINE_HEALTH_FAILED"
    if "timeout" in value:
        return "TEST_TIMEOUT"
    if "regression" in value and "fail" in value:
        return "INTEGRATION_TEST_FAILED"
    return "SOURCE_TEST_FAILED" if phase == "source" else "INFRA_ERROR"


@dataclass
class BootstrapResult:
    ok: bool
    phase: str
    exit_code: int
    output: str
    failure_class: str = ""


def run_bootstrap(root: str, godot: str | Iterable[str], health_script: str,
                  bootstrap_command: Optional[Iterable[str]] = None,
                  timeout: int = 900) -> BootstrapResult:
    commands = []
    if bootstrap_command:
        commands.append(("bootstrap", list(bootstrap_command)))
    godot_command = list(godot) if not isinstance(godot, str) else [godot]
    commands.extend([
        ("import", godot_command + ["--headless", "--path", root, "--import"]),
        ("baseline", godot_command + ["--headless", "--path", root, "-s", health_script]),
    ])
    output = []
    for phase, command in commands:
        try:
            proc = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                  encoding="utf-8", errors="replace", timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            text = ((exc.stdout or "") + "\n" + (exc.stderr or ""))
            return BootstrapResult(False, phase, 124, text, "TEST_TIMEOUT")
        text = (proc.stdout or "") + (proc.stderr or "")
        output.append("[{}] exit={}\n{}".format(phase, proc.returncode, text))
        fatal = any(token in text for token in ("Parse Error", "No loader found", "Failed to load",
                                                 "Resource file not found", "Cannot open"))
        marker_ok = phase != "baseline" or "BASELINE_3D_RESULT=PASS" in text
        if proc.returncode != 0 or fatal or not marker_ok:
            return BootstrapResult(False, phase, proc.returncode,
                                   "\n".join(output), classify_failure(text, phase=phase))
    return BootstrapResult(True, "baseline", 0, "\n".join(output))


class IntegrationCoordinator:
    """Single-writer integration queue with conflict preservation."""

    def __init__(self, integration_root: str, store: V2StateStore):
        self.root = integration_root
        self.store = store

    def dependencies_ready(self, task: TaskState) -> bool:
        state = self.store.load().get("tasks", {})
        return all(
            state.get(dep, {}).get("integration_status") == Lifecycle.INTEGRATED.value
            and state.get(dep, {}).get("integrated_commit")
            for dep in task.depends_on
        )

    def integrate(self, task: TaskState, regression_ok: bool = True) -> TaskState:
        if not task.source_commit:
            raise RuntimeError("SOURCE_COMMIT_REQUIRED")
        if not self.dependencies_ready(task):
            task.set(Lifecycle.WAIT_INTEGRATION, integration_status="BLOCKED_DEPENDENCY")
            self.store.put_task(task)
            return task
        if changed_status_paths(self.root):
            raise RuntimeError("INTEGRATION_WORKTREE_DIRTY")
        task.set(Lifecycle.INTEGRATING, integration_status="INTEGRATING")
        self.store.put_task(task)
        code, out, err = git(self.root, "cherry-pick", task.source_commit, timeout=300)
        if code:
            git(self.root, "cherry-pick", "--abort", timeout=60)
            task.set(Lifecycle.INTEGRATION_CONFLICT,
                     integration_status="INTEGRATION_CONFLICT",
                     last_error=(err or out).strip(),
                     failure_class="INTEGRATION_CONFLICT")
            self.store.put_task(task)
            return task
        integrated = git_required(self.root, "rev-parse", "HEAD")
        task.integrated_commit = integrated
        task.integration_status = Lifecycle.INTEGRATED.value
        task.set(Lifecycle.INTEGRATED)
        if not regression_ok:
            task.set(Lifecycle.INTEGRATED, integration_validation_result="FAIL",
                     failure_class="INTEGRATION_TEST_FAILED")
        else:
            task.set(Lifecycle.REGRESSION_PASS, integration_validation_result="PASS")
            task.set(Lifecycle.DONE)
        self.store.put_task(task)
        self.store.set_baseline(integrated)
        return task


class LifecycleController:
    """Small state transition façade used by the supervisor and resume code."""

    def __init__(self, store: V2StateStore):
        self.store = store

    def record(self, task: TaskState, status: Lifecycle | str, **fields) -> TaskState:
        task.set(status, **fields)
        self.store.put_task(task)
        return task

    def worktree_created(self, task: TaskState, baseline: str, branch: str, worktree: str):
        return self.record(task, Lifecycle.WORKTREE_CREATED,
                           baseline_commit=baseline, source_branch=branch,
                           source_worktree=worktree)

    def bootstrap_passed(self, task: TaskState):
        self.record(task, Lifecycle.ENV_BOOTSTRAPPED)
        return self.record(task, Lifecycle.BASELINE_HEALTHY,
                           source_validation_result="PENDING")

    def implementation_started(self, task: TaskState, attempt_id: str):
        return self.record(task, Lifecycle.IMPLEMENT, attempt_id=attempt_id)

    def source_validated(self, task: TaskState):
        return self.record(task, Lifecycle.SOURCE_VALIDATED,
                           source_validation_result="PASS")

    def wait_integration(self, task: TaskState):
        return self.record(task, Lifecycle.WAIT_INTEGRATION,
                           integration_status="WAITING")
