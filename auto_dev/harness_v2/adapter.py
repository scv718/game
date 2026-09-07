"""Production adapter boundary for the existing V1 scheduler.

The adapter is deliberately side-effect free in ``dry_run`` mode. A future
auto_lane entry point should call these functions instead of making DONE or
worktree decisions itself.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

from .core import (IntegrationCoordinator, Lifecycle, TaskState, V2StateStore,
                   changed_status_paths, git, git_required)


@dataclass
class DryRun:
    baseline_commit: str
    baseline_ok: bool
    queue_ok: bool
    ready: list[str]
    blocked: dict[str, str]
    legacy_done_bypass: bool
    coordinator_enabled: bool
    reason: str = ""


def canonical_baseline(repo: str, store: V2StateStore, *, persist: bool = True) -> str:
    """Resolve baseline exclusively from persistent state after validating HEAD."""
    head = git_required(repo, "rev-parse", "HEAD")
    dirty = changed_status_paths(repo)
    state = store.load()
    saved = state.get("integration_baseline_commit", "")
    if dirty:
        raise RuntimeError("BASELINE_REPOSITORY_DIRTY: {}".format(", ".join(dirty[:8])))
    if saved and saved != head:
        raise RuntimeError("BASELINE_MISMATCH: state={} HEAD={}".format(saved, head))
    if persist and not saved:
        store.set_baseline(head)
    return saved or head


def create_task_worktree(repo: str, path: str, branch: str, store: V2StateStore) -> str:
    """Create a new task worktree at the persistent integration baseline only."""
    baseline = canonical_baseline(repo, store)
    if os.path.exists(path):
        raise RuntimeError("STALE_WORKTREE_NOT_REUSED: {}".format(path))
    git_required(repo, "worktree", "add", "-b", branch, path, baseline)
    actual = git_required(path, "rev-parse", "HEAD")
    if actual != baseline:
        raise RuntimeError("WORKTREE_BASELINE_MISMATCH: {} != {}".format(actual, baseline))
    return baseline


def prerequisite_ready(task_id: str, store: V2StateStore) -> tuple[bool, str]:
    raw = store.load().get("tasks", {}).get(task_id, {})
    for dependency in raw.get("depends_on", []):
        dep = store.load().get("tasks", {}).get(dependency, {})
        if dep.get("integration_status") != Lifecycle.INTEGRATED.value:
            return False, "dependency {} not INTEGRATED".format(dependency)
        if not dep.get("integrated_commit"):
            return False, "dependency {} has no integrated_commit".format(dependency)
    return True, ""


def enqueue_integration(task: TaskState, store: V2StateStore):
    if not task.source_commit:
        raise RuntimeError("SOURCE_COMMIT_REQUIRED")
    state = store.load()
    queue = state.setdefault("integration_queue", [])
    if task.task_id not in queue:
        queue.append(task.task_id)
    task.set(Lifecycle.WAIT_INTEGRATION, integration_status="WAITING")
    state.setdefault("tasks", {})[task.task_id] = task.__dict__.copy()
    store.save(state)


def done_allowed(task: TaskState) -> bool:
    """Single completion predicate; source PASS alone can never produce DONE."""
    return task.can_done()


def parse_queue(path: str) -> list[dict]:
    heading = re.compile(r"^#{2,3}\s+((?:TASK|V3)-[A-Z0-9-]+)\b")
    status = re.compile(r"^-\s*상태\s*[:：]\s*(.+?)\s*$")
    result = []
    current = None
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            match = heading.match(line.rstrip())
            if match:
                current = {"task_id": match.group(1), "status": "QUEUED"}
                result.append(current)
                continue
            if current:
                match = status.match(line.rstrip())
                if match:
                    current["status"] = match.group(1).strip().upper()
    return result


def production_dry_run(repo: str, queue_path: str, store: V2StateStore) -> DryRun:
    try:
        baseline = canonical_baseline(repo, store, persist=False)
    except RuntimeError as exc:
        return DryRun("", False, False, [], {}, True, False, str(exc))
    try:
        tasks = parse_queue(queue_path)
    except OSError as exc:
        return DryRun(baseline, True, False, [], {}, True, False, str(exc))
    ready, blocked = [], {}
    for task in tasks:
        if task["status"] not in ("QUEUED", "IMPLEMENT", "REVIEW", "FIX"):
            continue
        ok, reason = prerequisite_ready(task["task_id"], store)
        if ok:
            ready.append(task["task_id"])
        else:
            blocked[task["task_id"]] = reason
    # This adapter has no path that can write DONE without TaskState.can_done.
    return DryRun(baseline, True, True, ready, blocked, False, True)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Harness V2 production dry-run")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--queue", required=True)
    parser.add_argument("--state", required=True)
    args = parser.parse_args(argv)
    result = production_dry_run(args.repo, args.queue, V2StateStore(args.state))
    print(json.dumps(result.__dict__, ensure_ascii=False, indent=2))
    print("HARNESS_V2_DRY_RUN={}".format("PASS" if result.baseline_ok and result.queue_ok and result.coordinator_enabled else "FAIL"))
    return 0 if result.baseline_ok and result.queue_ok and result.coordinator_enabled else 1


if __name__ == "__main__":
    raise SystemExit(main())
