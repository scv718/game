"""Offline adapter checks: clean baseline pass, dirty baseline fail, dependency gate."""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

from harness_v2.adapter import production_dry_run
from harness_v2.core import Lifecycle, TaskState, V2StateStore


def git(root, *args):
    p = subprocess.run(["git", "-C", str(root), *args], text=True,
                       capture_output=True, encoding="utf-8", errors="replace")
    if p.returncode:
        raise AssertionError((p.stdout + p.stderr).strip())
    return p.stdout.strip()


def check(name, value):
    if not value:
        raise AssertionError(name)
    print("PASS: " + name)


def main():
    with tempfile.TemporaryDirectory(prefix="harness-v2-adapter-") as temp:
        root = Path(temp) / "repo"
        root.mkdir()
        git(root, "init", "-b", "main")
        git(root, "config", "user.email", "adapter@example.invalid")
        git(root, "config", "user.name", "Harness V2")
        (root / "AI_TASK_QUEUE.md").write_text("## TASK-A\n- 상태: QUEUED\n## TASK-B\n- 상태: QUEUED\n", encoding="utf-8")
        git(root, "add", "AI_TASK_QUEUE.md")
        git(root, "commit", "-m", "baseline")
        state = V2StateStore(str(Path(temp) / "state.json"))
        baseline = git(root, "rev-parse", "HEAD")
        state.set_baseline(baseline)
        result = production_dry_run(str(root), str(root / "AI_TASK_QUEUE.md"), state)
        check("clean production dry-run passes", result.baseline_ok and result.queue_ok and result.coordinator_enabled)
        check("independent task is READY", result.ready == ["TASK-A", "TASK-B"])
        dependency = TaskState("TASK-B", depends_on=["TASK-A"])
        state.put_task(dependency)
        result = production_dry_run(str(root), str(root / "AI_TASK_QUEUE.md"), state)
        check("unintegrated dependency blocks scheduler", "TASK-B" in result.blocked)
        prerequisite = TaskState("TASK-A", status=Lifecycle.DONE.value,
                                 integration_status=Lifecycle.INTEGRATED.value,
                                 integrated_commit=baseline)
        state.put_task(prerequisite)
        result = production_dry_run(str(root), str(root / "AI_TASK_QUEUE.md"), state)
        check("integrated dependency unlocks scheduler", "TASK-B" in result.ready)
        (root / "dirty.gd").write_text("dirty\n", encoding="utf-8")
        result = production_dry_run(str(root), str(root / "AI_TASK_QUEUE.md"), state)
        check("dirty canonical baseline blocks dry-run", not result.baseline_ok and "DIRTY" in result.reason)
        print("HARNESS_V2_ADAPTER_RESULT=PASS")


if __name__ == "__main__":
    main()
