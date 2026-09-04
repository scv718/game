"""Offline synthetic Git E2E for Harness V2.

Run with: python auto_dev/harness_v2_selftest.py
No game files, network, Godot, or auto_lane are used.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from harness_v2.core import (IntegrationCoordinator, Lifecycle, TaskState,
                             LifecycleController, V2StateStore, BootstrapResult,
                             attempt_delta, changed_status_paths, classify_failure,
                             run_bootstrap, source_commit, worktree_snapshot)


def sh(cwd, *args):
    p = subprocess.run(["git", "-C", str(cwd), *args], text=True,
                       capture_output=True, encoding="utf-8", errors="replace")
    if p.returncode:
        raise AssertionError((p.stdout + p.stderr).strip())
    return p.stdout.strip()


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    print("PASS: " + name)


def make_repo(root):
    root.mkdir()
    sh(root, "init", "-b", "main")
    sh(root, "config", "user.email", "harness-v2@example.invalid")
    sh(root, "config", "user.name", "Harness V2")
    (root / "README").write_text("base\n", encoding="utf-8")
    sh(root, "add", "README")
    sh(root, "commit", "-m", "baseline")


def source(root, store, task_id, depends=()):
    wt = root / (task_id.lower().replace("-", "_"))
    sh(root, "worktree", "add", "-b", "source/" + task_id, str(wt), "main")
    before = __import__("harness_v2.core", fromlist=["worktree_snapshot"]).worktree_snapshot(str(wt))
    task = TaskState(task_id, baseline_commit=sh(root, "rev-parse", "main"),
                     source_branch="source/" + task_id, source_worktree=str(wt),
                     depends_on=list(depends), attempt_id="attempt-1")
    (wt / (task_id + ".gd")).write_text("# production\n", encoding="utf-8")
    task.source_validation_result = "PASS"
    source_commit(str(wt), task, before, "synthetic implementation")
    store.put_task(task)
    return task, wt


def main():
    with tempfile.TemporaryDirectory(prefix="harness-v2-") as temp:
        root = Path(temp) / "repo"
        make_repo(root)
        store = V2StateStore(str(root / "state.json"))
        store.set_baseline(sh(root, "rev-parse", "HEAD"))
        integration = root / "integration"
        sh(root, "worktree", "add", "-b", "integration", str(integration), "main")
        coordinator = IntegrationCoordinator(str(integration), store)
        controller = LifecycleController(store)
        lifecycle = TaskState("LIFECYCLE")
        controller.worktree_created(lifecycle, sh(root, "rev-parse", "main"),
                                    "source/LIFECYCLE", str(root / "lifecycle"))
        controller.bootstrap_passed(lifecycle)
        controller.implementation_started(lifecycle, "attempt-lifecycle")
        controller.source_validated(lifecycle)
        controller.wait_integration(lifecycle)
        persisted = store.get_task("LIFECYCLE")
        check("lifecycle and provenance fields persist", persisted.status == Lifecycle.WAIT_INTEGRATION.value)
        check("bootstrap and source lifecycle history persists",
              Lifecycle.ENV_BOOTSTRAPPED.value in persisted.history
              and Lifecycle.SOURCE_VALIDATED.value in persisted.history)

        a, _ = source(root, store, "A")
        check("A source commit recorded", bool(a.source_commit))
        a = coordinator.integrate(a)
        check("independent task reaches DONE", a.status == Lifecycle.DONE.value)
        check("integrated commit recorded", a.integrated_commit == sh(integration, "rev-parse", "HEAD"))

        b, _ = source(root, store, "B")
        c, _ = source(root, store, "C", depends=("B",))
        c = coordinator.integrate(c)
        check("dependent task blocked before prerequisite integration", c.status == Lifecycle.WAIT_INTEGRATION.value)
        b = coordinator.integrate(b)
        c = coordinator.integrate(c)
        check("dependent task unlocks after integration", c.status == Lifecycle.DONE.value)

        d, _ = source(root, store, "D")
        e, _ = source(root, store, "E")
        d = coordinator.integrate(d)
        e = coordinator.integrate(e)
        check("two independent source commits integrate serially", d.status == e.status == Lifecycle.DONE.value)

        preexisting, preexisting_wt = source(root, store, "PREEXISTING")
        # Recreate a source attempt with a dirty file that predates the attempt.
        sh(root, "worktree", "remove", "--force", str(preexisting_wt))
        sh(root, "worktree", "add", "-b", "source/PREEXISTING2", str(preexisting_wt), "main")
        dirty = preexisting_wt / "legacy.gd"
        dirty.write_text("preserve me\n", encoding="utf-8")
        before = worktree_snapshot(str(preexisting_wt))
        task = TaskState("PREEXISTING2", source_validation_result="PASS")
        (preexisting_wt / "new_feature.gd").write_text("new\n", encoding="utf-8")
        source_commit(str(preexisting_wt), task, before, "scoped delta")
        check("pre-existing dirty production is preserved", "legacy.gd" in changed_status_paths(str(preexisting_wt)))
        check("source commit excludes pre-existing dirty file", "legacy.gd" not in sh(preexisting_wt, "show", "--format=", "--name-only", "HEAD"))

        reg, _ = source(root, store, "REGRESSION")
        reg = coordinator.integrate(reg, regression_ok=False)
        check("integration regression failure blocks DONE", reg.status == Lifecycle.INTEGRATED.value and reg.integration_validation_result == "FAIL")

        conflict, conflict_wt = source(root, store, "CONFLICT")
        (integration / "CONFLICT.gd").write_text("integration edit\n", encoding="utf-8")
        sh(integration, "add", "CONFLICT.gd")
        sh(integration, "commit", "-m", "integration edit")
        before = sh(integration, "rev-parse", "HEAD")
        conflict = coordinator.integrate(conflict)
        check("conflict is preserved as explicit state", conflict.status == Lifecycle.INTEGRATION_CONFLICT.value)
        check("conflict leaves integration baseline unchanged", before == sh(integration, "rev-parse", "HEAD"))
        check("conflict source commit remains available", bool(conflict.source_commit))

        # The bootstrap gate is tested with a deterministic fake Godot process.
        fake = root / "fake_godot.py"
        fake.write_text(
            "import sys\n"
            "if '--import' in sys.argv: print('import ok')\n"
            "else: print('BASELINE_3D_RESULT=PASS')\n",
            encoding="utf-8")
        boot = run_bootstrap(str(root), [sys.executable, str(fake)], str(fake))
        check("bootstrap/import/health gate passes", boot.ok and boot.exit_code == 0)
        check("failure classifier separates bootstrap errors", classify_failure("Godot import failed", phase="bootstrap") == "BOOTSTRAP_FAILED")

        orphan, orphan_wt = source(root, store, "ORPHAN")
        check("meaningful source worktree is clean after source commit", not changed_status_paths(str(orphan_wt)))
        # A task without source commit cannot be integrated or marked DONE.
        missing = TaskState("MISSING", source_validation_result="PASS")
        try:
            coordinator.integrate(missing)
            raise AssertionError("missing source commit accepted")
        except RuntimeError as exc:
            check("DONE path rejects missing source commit", str(exc) == "SOURCE_COMMIT_REQUIRED")

        resumed = V2StateStore(str(root / "state.json")).get_task("A")
        check("source/integration state survives supervisor resume", resumed.status == Lifecycle.DONE.value and bool(resumed.integrated_commit))

        print("HARNESS_V2_RESULT=PASS")


if __name__ == "__main__":
    main()
