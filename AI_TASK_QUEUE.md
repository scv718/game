# Execution Queue (V3 / V4)

> Canonical baseline: `main` at `815fbb5e8d7028fe95bf89c991d1ab4b4c60c95e`
> Runtime: `res://scenes/main_3d.tscn`
> V3-001~V3-014: 모든 태스크 DONE (runtime truth는 `auto_dev/state_v2.json` 및 `auto_dev/runs/integration_done.log`가 authoritative)
> Existing TASK records are preserved under `auto_dev/LEGACY_HISTORY/` and are not executable.

## V3-001 Dungeon Completion & Return Loop
- 상태: DONE
- depends_on:
- task_file: auto_dev/tasks/V3-001.md
- source_commit: 979df79190bb21da7edbe1f9e47ea3f3df8162ce
- integrated_commit: 26ba6e765fbc00af629689a32d0d68928a42f78b
- integration_validation: PASS

## V3-002 Current Runtime Asset Bootstrap
- 상태: DONE
- depends_on:
- task_file: auto_dev/tasks/V3-002.md
- source_commit: 9b544523aa264866cce9d8e42243201117c7b01f
- integrated_commit: a8217bce3c7adecb9d38da47f6471fa913ce11fb
- integration_validation: PASS

## V3-003 Persistent Game State
- 상태: DONE
- depends_on: V3-002
- task_file: auto_dev/tasks/V3-003.md
- source_commit: a694abd5524fd754eecf0524f8bc575efefbcb06
- integrated_commit: 5a24809d8215f1727ecdd697cb278f7b77f349c4
- integration_validation: PASS

## V3-004 Production Economy Vertical Slice
- 상태: DONE
- depends_on: V3-002
- task_file: auto_dev/tasks/V3-004.md
- source_commit: db4bb9afdb4cd45377d019977e2196c4d0333b5c
- integrated_commit: 7044da3a3b4a2ce5041c392450f36b787964ea58
- integration_validation: PASS

## V3-005 Food Preparation & Expedition Effect Contract
- 상태: DONE
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-005.md
- source_commit: 9e4c2afb34995856feed755f9b8e229f7436c2a0
- integrated_commit: e45fd6d806f6b4c0a619858754ef1dda7128ea03
- integration_validation: PASS

## V3-006 Mercenary Equipment Foundation
- 상태: DONE
- depends_on: V3-003
- task_file: auto_dev/tasks/V3-006.md
- source_commit: 6181ac9f0908d84d5edf9a7c7efa75863998609c
- integrated_commit: 0354e3644292a5c20a6b0804622290586b35e69f
- integration_validation: PASS

## V3-007 Mercenary Skill Foundation
- 상태: DONE
- depends_on: V3-006
- task_file: auto_dev/tasks/V3-007.md
- source_commit: 6c4f4c17dc0ede2d532a6e524f389f41e8522be6
- integrated_commit: 3d6487d156348910d4a63f6a20ddd68fd1429cea
- integration_validation: PASS

## V3-008 Ghost Mercenary Combat Identity
- 상태: DONE
- depends_on: V3-006,V3-007
- task_file: auto_dev/tasks/V3-008.md
- source_commit: 6e397ba25864170a5cfff574e63d09cc3308be28
- integrated_commit: 97046d84aaed0805114c5bd4e461090b705bb154
- integration_validation: PASS

## V3-009 Village Logistics & Capacity
- 상태: DONE
- depends_on: V3-004
- task_file: auto_dev/tasks/V3-009.md
- source_commit: f4cb2f989aeadd160493885fb5eff90294d9c67b
- integrated_commit: 1a422b80a8e399b7640fd74de9c80b00d995e874
- integration_validation: PASS

## V3-010 Boss Encounter Foundation
- 상태: DONE
- depends_on: V3-001,V3-007
- task_file: auto_dev/tasks/V3-010.md
- source_commit: 783ef744f4c2c24ac095f7a65e61e58b3b96b218
- integrated_commit: 863e641898f98890316a57a071f14290aa5943c9
- integration_validation: PASS

## V3-011 Shop & Trade Foundation
- 상태: DONE
- depends_on: V3-003,V3-004
- task_file: auto_dev/tasks/V3-011.md
- source_commit: bf092db3f002f57c9dc47cd527feebed098cf81f
- integrated_commit: 3798c733f58582ecfc4eed53f04cccf895ee71d4
- integration_validation: PASS

## V3-012 Quest / Faction Foundation
- 상태: DONE
- depends_on: V3-003
- task_file: auto_dev/tasks/V3-012.md
- source_commit: ca9a8c46f0e765c60963b38f598aa440d566e18e
- integrated_commit: b94e5ed0167c22a4767a45e8825db093b58bfab2
- integration_validation: PASS

## V3-013 3D Test Contract Cleanup
- 상태: DONE
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-013.md
- source_commit: eb9b398f13c9d812ca2cc60262accc408df170d6
- integrated_commit: da17b637e8837afe6438978b47816f9192d283eb
- integration_validation: PASS

## V3-014 Visual & Content Polish
- 상태: DONE
- depends_on: V3-001,V3-004
- task_file: auto_dev/tasks/V3-014.md
- source_commit: 5a1f9256a173448b8bccf544f2a697e3f5c37f24
- integrated_commit: 815fbb5e8d7028fe95bf89c991d1ab4b4c60c95e
- integration_validation: PASS

## V4-001 NE Ruins Discovery → Dungeon Preparation/Entry Gating
- 상태: QUEUED
- depends_on:
- task_file: auto_dev/tasks/V4-001.md
- source_commit:
- integrated_commit:
- integration_validation:

## V4-002 Dungeon Runtime Run Phase Machine
- 상태: QUEUED
- depends_on: V4-001
- task_file: auto_dev/tasks/V4-002.md
- source_commit:
- integrated_commit:
- integration_validation:

## V4-003 Exact Dungeon Combat Outcome (Victory / Defeat)
- 상태: QUEUED
- depends_on: V4-002
- task_file: auto_dev/tasks/V4-003.md
- source_commit:
- integrated_commit:
- integration_validation:

## V4-004 Dungeon Reward, Threat Reporting, Return Loop
- 상태: QUEUED
- depends_on: V4-003
- task_file: auto_dev/tasks/V4-004.md
- source_commit:
- integrated_commit:
- integration_validation:

## Execution Contract

Each V3/V4 task uses an isolated worktree, records `baseline_commit`, `source_commit`, `integrated_commit`, `integration_status`, and `depends_on`, and must pass its feature test plus `tests/baseline_3d_health_test.gd` before DONE. V4 tests gate on fail‑closed headless markers (`<TASK>_ASSERTIONS=<actual>/<expected>` + `<TASK>_RESULT=PASS`). No legacy TASK state is consulted. Runtime truth for task status is `auto_dev/state_v2.json` (authoritative) cross-checked by `auto_dev/runs/integration_done.log`; this queue file is the human-readable mirror.