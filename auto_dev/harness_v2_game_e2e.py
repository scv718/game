"""Disposable real-game lifecycle check for Harness V2.

This creates two disposable registered worktrees from the current V2 commit,
commits a fixture-only source delta, integrates it, and runs the real Godot
baseline gate. It never touches the canonical main checkout.
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

from harness_v2.core import (IntegrationCoordinator, Lifecycle, LifecycleController,
                             TaskState, V2StateStore, run_bootstrap, source_commit,
                             worktree_snapshot, git_required)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    repo = os.path.abspath(args.repo)
    stamp = "harness-v2-game-e2e"
    source_root = os.path.join(os.path.dirname(repo), stamp + "-source")
    integration_root = os.path.join(os.path.dirname(repo), stamp + "-integration")
    for path, branch in ((source_root, "codex/harness-v2-game-e2e-source"),
                         (integration_root, "codex/harness-v2-game-e2e-integration")):
        if not os.path.isdir(path):
            git_required(repo, "worktree", "add", "-b", branch, path, "HEAD")

    with tempfile.TemporaryDirectory(prefix="harness-v2-game-state-") as state_dir:
        store = V2StateStore(os.path.join(state_dir, "state.json"))
        baseline = git_required(repo, "rev-parse", "HEAD")
        store.set_baseline(baseline)
        task = TaskState("HARNESS-V2-GAME-E2E", baseline_commit=baseline,
                         source_branch="codex/harness-v2-game-e2e-source",
                         source_worktree=source_root, depends_on=[], attempt_id="e2e-1")
        controller = LifecycleController(store)
        controller.worktree_created(task, baseline, task.source_branch, source_root)
        health = run_bootstrap(source_root, args.godot,
                               "res://tests/baseline_3d_health_test.gd", timeout=900)
        if not health.ok:
            print("REAL_GAME_E2E=FAIL")
            print(health.output[-4000:])
            return 1
        controller.bootstrap_passed(task)
        controller.implementation_started(task, task.attempt_id)
        before = worktree_snapshot(source_root)
        fixture = Path(source_root) / "auto_dev" / "harness_v2_e2e_fixture.gd"
        fixture.write_text("extends RefCounted\n\nfunc e2e_marker() -> String:\n    return \"ok-v2\"\n", encoding="utf-8")
        task.source_validation_result = "PASS"
        controller.source_validated(task)
        source_commit(str(source_root), task, before, "disposable game lifecycle fixture")
        controller.wait_integration(task)
        integrated = IntegrationCoordinator(integration_root, store).integrate(task)
        if integrated.status != Lifecycle.DONE.value:
            print("REAL_GAME_E2E=FAIL")
            print("integration status: {}".format(integrated.status))
            return 1
        print("REAL_GAME_E2E=PASS")
        print("SOURCE_COMMIT={}".format(task.source_commit))
        print("INTEGRATED_COMMIT={}".format(task.integrated_commit))
        print("BASELINE_3D_RESULT=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
