# V3 Execution Queue

> Canonical baseline: `main` at `63914f5642d40e73d6cfe3223fefe16d9f0ffa88`
> Runtime: `res://scenes/main_3d.tscn`
> Existing TASK records are preserved under `auto_dev/LEGACY_HISTORY/` and are not executable.

## V3-001 Dungeon Completion & Return Loop
- 상태: QUEUED
- depends_on:
- task_file: auto_dev/tasks/V3-001.md

## V3-002 Current Runtime Asset Bootstrap
- 상태: QUEUED
- depends_on:
- task_file: auto_dev/tasks/V3-002.md

## V3-003 Persistent Game State
- 상태: QUEUED
- depends_on: V3-002
- task_file: auto_dev/tasks/V3-003.md

## V3-004 Production Economy Vertical Slice
- 상태: QUEUED
- depends_on: V3-002
- task_file: auto_dev/tasks/V3-004.md

## V3-005 Food Preparation & Expedition Effect Contract
- 상태: QUEUED
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-005.md

## V3-006 Mercenary Equipment Foundation
- 상태: QUEUED
- depends_on: V3-003
- task_file: auto_dev/tasks/V3-006.md

## V3-007 Mercenary Skill Foundation
- 상태: QUEUED
- depends_on: V3-006
- task_file: auto_dev/tasks/V3-007.md

## V3-008 Ghost Mercenary Combat Identity
- 상태: QUEUED
- depends_on: V3-006,V3-007
- task_file: auto_dev/tasks/V3-008.md

## V3-009 Village Logistics & Capacity
- 상태: QUEUED
- depends_on: V3-004
- task_file: auto_dev/tasks/V3-009.md

## V3-010 Boss Encounter Foundation
- 상태: QUEUED
- depends_on: V3-001,V3-007
- task_file: auto_dev/tasks/V3-010.md

## V3-011 Shop & Trade Foundation
- 상태: QUEUED
- depends_on: V3-003,V3-004
- task_file: auto_dev/tasks/V3-011.md

## V3-012 Quest / Faction Foundation
- 상태: QUEUED
- depends_on: V3-003
- task_file: auto_dev/tasks/V3-012.md

## V3-013 3D Test Contract Cleanup
- 상태: QUEUED
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-013.md

## V3-014 Visual & Content Polish
- 상태: QUEUED
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-014.md

## Execution Contract

Each V3 task uses an isolated worktree, records `baseline_commit`, `source_commit`, `integrated_commit`, `integration_status`, and `depends_on`, and must pass its feature regression plus `tests/baseline_3d_health_test.gd` before DONE. No legacy TASK state is consulted.
