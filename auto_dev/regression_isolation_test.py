"""Regression tests for WORKTREE_ISOLATION_FAILURE fixes.

Run with: python auto_dev/regression_isolation_test.py
No network, Godot, or real opencode processes are used.

Covers:
  A. run_opencode Popen gets explicit cwd == WORKTREE_DIR (was inherited main cwd).
  B. run_opencode --file attach path lives inside the task worktree, never main.
     (shared D:\\game\\auto_dev\\task_context.md removed; main path leak blocked.)
  C. build_task_file writes per-task context inside worktree; solo(no-group) mode
     writes to temp, never canonical main.
  D. _v2_record_implement_start persists state_v2 with status IMPLEMENT at start
     (early lifecycle instead of only at SOURCE_COMMITTED).
  E. V2StateStore concurrent put_task is serialized without lost updates.
F. AI_TASK_QUEUE.md spec-only: update_queue(runtime status) never edits the queue
     file and routes to state_v2; runtime_status prefers state_v2 over spec.
  G. pick_next_task uses runtime status (state_v2 1st).
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
from pathlib import Path

AUTO_DEV = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AUTO_DEV)

import supervisor  # noqa: E402


def check(name, condition):
    if not condition:
        raise AssertionError("FAIL: " + name)
    print("PASS: " + name)


def make_queue(path: Path):
    path.write_text(
        "## GROUP-TEST\n"
        "### REG-TASK-1\n"
        "- 상태: QUEUED\n"
        "- 피드백: regression task\n"
        "### REG-TASK-2\n"
        "- 상태: QUEUED\n",
        encoding="utf-8",
    )


def base_config(main: Path, logs_dir: str):
    return {
        "project_dir": str(main),
        "queue_file": "AI_TASK_QUEUE.md",
        "log_dir": logs_dir,
        "opencode_exe": "stub",
        "implementer_model": "stub-model",
    }


class _FakeProc:
    """Minimal stand-in for subprocess.Popen used via monkeypatch."""

    def __init__(self, args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.returncode = 0
        self.pid = 12345
        self._stdout = json.dumps({
            "sessionID": "ses-regression",
            "part": {"type": "text", "text": "구현 요약: regression ok",
                     "sessionID": "ses-regression"},
        })

    def communicate(self, timeout=None):
        return self._stdout, ""


def test_c():
    """C + B: build_task_file path rules."""
    with tempfile.TemporaryDirectory(prefix="reg-c-") as temp:
        base = Path(temp)
        main = base / "main"
        wt = base / "worktree"
        wt.mkdir(parents=True)
        main.mkdir(parents=True)
        queue_path = main / "AI_TASK_QUEUE.md"
        make_queue(queue_path)

        saved_wt = supervisor.WORKTREE_DIR
        saved_cfg = supervisor.CONFIG
        try:
            supervisor.CONFIG = base_config(main, str(base / "logs"))
            supervisor.WORKTREE_DIR = str(wt)
            task = {"id": "REG-TASK-1", "title": "reg task", "level": 3, "status": "QUEUED"}
            out = supervisor.build_task_file(task, str(queue_path))
            out_p = Path(out)
            check("C1: lane mode context into worktree",
                  str(out_p).startswith(str(wt)))
            check("C2: context not under canonical main",
                  not str(out_p).startswith(str(main)))
            check("C3: per-task filename", out_p.name == "task_context_REG-TASK-1.md")
            check("C4: queue block content preserved",
                  "REG-TASK-1" in out_p.read_text(encoding="utf-8"))
            rel = os.path.relpath(out, str(wt)).replace("\\", "/")
            check("C5: .md excluded from commit targets (_is_commitable)",
                  supervisor._is_commitable(rel) is False)
        finally:
            supervisor.WORKTREE_DIR = saved_wt
            supervisor.CONFIG = saved_cfg

    with tempfile.TemporaryDirectory(prefix="reg-csolo-") as temp:
        base = Path(temp)
        main = base / "main"
        main.mkdir(parents=True)
        queue_path = main / "AI_TASK_QUEUE.md"
        make_queue(queue_path)
        saved_wt = supervisor.WORKTREE_DIR
        saved_cfg = supervisor.CONFIG
        try:
            supervisor.CONFIG = base_config(main, str(base / "logs"))
            supervisor.WORKTREE_DIR = None
            task = {"id": "REG-TASK-2", "title": "solo task", "level": 3, "status": "QUEUED"}
            out = supervisor.build_task_file(task, str(queue_path))
            check("C6: solo(no-group) mode writes to temp, main stays clean",
                  not str(out).startswith(str(main)))
        finally:
            supervisor.WORKTREE_DIR = saved_wt
            supervisor.CONFIG = saved_cfg


def test_a_and_b():
    """A: run_opencode Popen cwd == WORKTREE_DIR. B: --file is inside worktree."""
    with tempfile.TemporaryDirectory(prefix="reg-ab-") as temp:
        base = Path(temp)
        main = base / "main"
        wt = base / "worktree"
        wt.mkdir(parents=True)
        main.mkdir(parents=True)
        queue_path = main / "AI_TASK_QUEUE.md"
        make_queue(queue_path)

        saved_wt = supervisor.WORKTREE_DIR
        saved_cfg = supervisor.CONFIG
        saved_pop = supervisor.subprocess.Popen
        try:
            supervisor.CONFIG = base_config(main, str(base / "logs")) | {"variant": ""}
            supervisor.WORKTREE_DIR = str(wt)
            task = {"id": "REG-TASK-1", "title": "reg task", "level": 3, "status": "QUEUED"}
            ctx = supervisor.build_task_file(task, str(queue_path))

            captured = {}

            def spy(*args, **kwargs):
                captured["args"] = args[0]
                captured["kwargs"] = kwargs
                return _FakeProc(*args, **kwargs)

            supervisor.subprocess.Popen = spy
            sid, text, err = supervisor.run_opencode(
                "test prompt", "stub-model", extra_args=["--file", ctx], timeout_sec=60)
            check("A1: Popen cwd == WORKTREE_DIR",
                  captured["kwargs"].get("cwd") == str(wt))
            fargs = captured["args"]
            check("A2: --dir is the worktree",
                  "--dir" in fargs and fargs[fargs.index("--dir") + 1] == str(wt))
            check("A3: --file attach path inside worktree",
                  "--file" in fargs and str(fargs[fargs.index("--file") + 1]).startswith(str(wt)))
            check("A4: attach path does not expose canonical main",
                  not str(fargs[fargs.index("--file") + 1]).startswith(str(main)))
            check("A5: stub response parsed (sessionID)", sid == "ses-regression")
            check("A6: success err == ''", err == "")
        finally:
            supervisor.subprocess.Popen = saved_pop
            supervisor.WORKTREE_DIR = saved_wt
            supervisor.CONFIG = saved_cfg


def test_d():
    """D: state_v2 has TaskState from IMPLEMENT start."""
    with tempfile.TemporaryDirectory(prefix="reg-d-") as temp:
        base = Path(temp)
        main = base / "main"
        main.mkdir(parents=True)
        state = base / "state_v2.json"

        saved_cfg = supervisor.CONFIG
        saved_wt = supervisor.WORKTREE_DIR
        saved_state_fn = supervisor._v2_state_path
        try:
            supervisor.CONFIG = base_config(main, str(base / "logs"))
            supervisor.WORKTREE_DIR = str(base / "wt")
            supervisor._v2_state_path = lambda p=state: str(p)
            supervisor._ATTEMPT_START_HEAD = None

            task = {"id": "REG-TASK-1", "title": "reg task", "level": 3,
                    "status": "QUEUED", "depends_on": ""}
            supervisor._v2_record_implement_start(task)

            from harness_v2.core import Lifecycle, V2StateStore
            store = V2StateStore(str(state))
            v2 = store.get_task("REG-TASK-1")
            check("D1: state_v2 records IMPLEMENT",
                  v2 is not None and v2.status == Lifecycle.IMPLEMENT.value)
            check("D2: attempt_id recorded", bool(v2.attempt_id))
            check("D3: history includes IMPLEMENT", Lifecycle.IMPLEMENT.value in v2.history)
        finally:
            supervisor._v2_state_path = saved_state_fn
            supervisor.WORKTREE_DIR = saved_wt
            supervisor.CONFIG = saved_cfg


def test_e():
    """E: V2StateStore concurrent put_task has no lost updates."""
    from harness_v2.core import TaskState, V2StateStore
    with tempfile.TemporaryDirectory(prefix="reg-e-") as temp:
        store = V2StateStore(str(Path(temp) / "state.json"))
        errors = []

        def worker(i):
            try:
                for j in range(5):
                    t = TaskState(f"T{i}_{j}")
                    t.set("IMPLEMENT")
                    store.put_task(t)
            except Exception as exc:
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        check("E1: no exceptions under concurrent writes", not errors)
        state = store.load()
        check("E2: all tasks persisted (no lost updates)",
              len(state["tasks"]) == 6 * 5)


def test_fg():
    """F: queue spec-only (state_v2 sink). G: pick_next_task runtime-based."""
    with tempfile.TemporaryDirectory(prefix="reg-fg-") as temp:
        base = Path(temp)
        main = base / "main"
        wt = base / "worktree"
        wt.mkdir(parents=True)
        main.mkdir(parents=True)
        queue_path = main / "AI_TASK_QUEUE.md"
        make_queue(queue_path)
        state_path = base / "state_v2.json"

        saved_cfg = supervisor.CONFIG
        saved_wt = supervisor.WORKTREE_DIR
        saved_state_fn = supervisor._v2_state_path
        try:
            supervisor.CONFIG = base_config(main, str(base / "logs"))
            supervisor.WORKTREE_DIR = str(wt)
            supervisor._v2_state_path = lambda p=state_path: str(p)

            task = {"id": "REG-TASK-1", "title": "reg task", "level": 3, "status": "QUEUED"}
            before = queue_path.read_bytes()
            supervisor.update_queue([task], str(queue_path), "REG-TASK-1", "IMPLEMENT",
                                    feedback="start")

            check("F1: queue file NOT modified by runtime status write",
                  queue_path.read_bytes() == before)

            from harness_v2.core import Lifecycle, V2StateStore
            store = V2StateStore(str(state_path))
            v2 = store.get_task("REG-TASK-1")
            check("F2: runtime status routed to state_v2 as IMPLEMENT",
                  v2 is not None and v2.status == Lifecycle.IMPLEMENT.value)
            check("F3: feedback preserved in state_v2 last_error",
                  v2.last_error and "start" in v2.last_error)

            supervisor.update_queue([task], str(queue_path), "REG-TASK-1",
                                    "NEEDS_DESIGN", feedback="human")
            v2 = store.get_task("REG-TASK-1")
            check("F4: NEEDS_DESIGN mapped to CANONICAL_REVIEW_REQUIRED",
                  v2.status == Lifecycle.CANONICAL_REVIEW_REQUIRED.value)

            check("F5: runtime_status prefers state_v2 over spec QUEUED",
                  supervisor.runtime_status(task) == "NEEDS_DESIGN")

            no_v2 = {"id": "REG-TASK-2", "title": "no-record", "level": 3, "status": "QUEUED"}
            check("F6: runtime_status falls back to spec when no v2 record",
                  supervisor.runtime_status(no_v2) == "QUEUED")

            done_spec = {"id": "REG-TASK-2", "title": "no-record", "level": 3,
                         "leaf": True, "status": "QUEUED"}
            d = store.get_task("REG-TASK-2")
            if d is None:
                from harness_v2.core import TaskState
                store.put_task(TaskState("REG-TASK-2").set(Lifecycle.DONE))
            check("G1: spec QUEUED task with v2 DONE is not picked",
                  supervisor.pick_next_task([done_spec]) is None)
        finally:
            supervisor._v2_state_path = saved_state_fn
            supervisor.WORKTREE_DIR = saved_wt
            supervisor.CONFIG = saved_cfg


def main():
    test_c()
    test_a_and_b()
    test_d()
    test_e()
    test_fg()
    print("ALL PASS")


if __name__ == "__main__":
    main()