# Canonical local runtime bootstrap

The production code baseline is the tracked 3D runtime rooted at
`res://scenes/main_3d.tscn`. The legacy `tests/smoke_test.gd` exercises the old
2D runtime and is not the canonical baseline gate.

## Tiny Swords external dependency

Tiny Swords raw files are intentionally excluded by `.gitignore` because the
pack must not be redistributed from this repository. Populate the local
`assets/tiny_swords/` directory with the checked-in bootstrap:

```powershell
pwsh -File tools/download_tiny_swords.ps1
```

Then reproduce the checked-in-code-derived images:

```powershell
godot --headless --path . --script tools/generate_terrain_tiles.gd
godot --headless --path . --script tools/crop_decorations.gd
```

Do not commit the raw pack, `assets/tiny_swords/generated/`, `.godot/`, or
`*.import` cache files. For the 2026-09-04 recovery, the official downloader was
not re-run because an already licensed local copy existed in `D:/game`; hashes
were compared across the main, visual, building, worker, combat, and f-ghost
worktrees before it was used as a runtime-only bootstrap source. The generation
commands above were run and returned exit 0.

## Godot import and health gate

Run a bounded Godot 4.7.1 import before direct `--script` tests in a fresh
worktree so the global script class cache and imported resources exist:

```powershell
godot --headless --path . --import
godot --headless --path . --script tests/baseline_3d_health_test.gd
```

The health gate is successful only when the process exits 0, stdout contains
`BASELINE_3D_RESULT=PASS`, and stderr contains no parser, resource, or import
errors.
