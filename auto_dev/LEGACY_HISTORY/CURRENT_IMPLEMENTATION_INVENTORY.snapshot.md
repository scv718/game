# Current Implementation Inventory

## Audit Baseline

- Repository: `D:\game`
- Branch: `main`
- HEAD: `63914f5642d40e73d6cfe3223fefe16d9f0ffa88`
- Audit date: 2026-09-07 (Asia/Seoul)
- Working tree: clean at audit snapshot
- Runtime entry: `res://scenes/main_3d.tscn` (`project.godot:11-15`)

This inventory is based on current production source, scene wiring, autoloads, and test contents. Historical TASK status and agent reports are not implementation evidence.

## Executive Summary

The current canonical runtime is a 3D/2.5D village-management prototype. The repository still contains a substantial legacy 2D runtime and its tests, but the configured application entry is the 3D main scene. The 3D baseline has a coherent world, camera, selection/placement, worker, mercenary, combat, threat/wave, dungeon-preparation/runtime, ghost, food-consumption, potion, morale, exploration, and audio foundation.

The largest confirmed gaps are persistent game save/load, equipment, skills, quests, factions, shop/economy progression, boss content, and a complete dungeon outcome/reward/return loop. External asset reproducibility is also a release dependency: Tiny Swords and Quaternius runtime files are ignored or externally bootstrapped, while production scripts preload some of those paths.

## Implementation Summary

| Classification | Current findings |
|---|---|
| IMPLEMENTED | 3D entry/world, camera, mouse selection, building placement, resource nodes, worker roster/FSM, mercenary roster/FSM, auto combat, gates/walls, threat/wave, Ghost/Death Ledger, dungeon preparation and encounter skeleton, Food consumption, Potion slot/auto-consume, morale, exploration/map UI, audio foundation |
| PARTIAL | Dungeon progression/reward/return, farm-to-food vertical slice, visual asset delivery, 3D UI/gameplay completeness, portal concept, resident population model |
| STUB | Dungeon reward table data container, equipment preparation summary, portal markers/visual dressing, several future building roles |
| TEST_ONLY | Historical TASK assertions that have no reachable production owner; legacy `smoke_test.gd` contract |
| BROKEN / SUSPICIOUS | Fresh checkout asset closure; legacy smoke test against the configured 3D entry; mixed 2D/3D duplicate runtime surfaces |
| NOT_FOUND | Save/load game state, equipment system, skills, quests, factions, shop/trade, boss system, storage/logistics, healer/repair/training buildings |

## Core Systems

| Feature | Status | Evidence | Tests / notes |
|---|---|---|---|
| 3D game entry | IMPLEMENTED | `project.godot:11-15`; `scenes/main_3d.tscn:24-110` | `tests/baseline_3d_health_test.gd` is the relevant baseline gate |
| Global services | IMPLEMENTED | `project.godot:22-38` registers GameTime, resources, rosters, consumption, DeathLedger, exploration, audio, threat/wave, dungeon services | Autoload existence is explicitly checked by baseline health |
| Day/night | IMPLEMENTED | `scripts/game_time.gd`; consumers in `mercenary_roster_3d.gd`, `first_encounter_spawner_3d.gd`, `population_consumption.gd`, `wave_manager.gd` | Current 3D actors subscribe to phase changes |
| Input | IMPLEMENTED | `project.godot:44-90` defines WASD, E, B, L, M, and P `dungeon_prep` | P binding is physical keycode 80 / unicode 112 |

## Player / Control

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Direct player actor | NOT_FOUND (intentional) | `baseline_3d_health_test.gd` checks empty `player`/`players` groups; `scripts/world_selection_3d.gd` documents player removal | Matches design rule that the player does not fight directly |
| 3D camera pan/zoom | IMPLEMENTED | `scripts/camera_controller_3d.gd:64-112,139-248`; `scenes/main_3d.tscn:78` | Camera is a separate runtime owner |
| Mouse world selection | IMPLEMENTED | `scripts/world_selection_3d.gd:1-137`; `main_3d.tscn:80-81` | Reuses Interactable3D API |
| Building placement input | IMPLEMENTED | `scripts/building_placement_3d.gd:1-39,132-224`; `main_3d.tscn:83-84` | Grid, overlap, cost, catalog, wall/gate placement paths exist |

## World / Map / Visuals

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D world and navigation | IMPLEMENTED | `scenes/world3d.tscn`; `scripts/world_root_3d.gd`; `scripts/world_content_3d.gd:23-90`; `main_3d.tscn:26-74` | Runtime scene contains world content and navigation owner |
| Terrain/village composition | IMPLEMENTED | `scripts/village_composition_3d.gd:1-194`; `scenes/village_composition_3d.tscn` | Current main instantiates the composition through world content |
| 3D asset catalog | PARTIAL | `scripts/visual_asset_catalog_3d.gd:1-44,433-437` | Catalog is production code, but required Quaternius source files are external/ignored and must be bootstrapped |
| Portal | STUB / PARTIAL | `scripts/world_map.gd:213-217,408-433`; visual portal dressing in `village_composition_3d.gd` | Candidate markers/visual language exist; authoritative portal gameplay is not present |

## Resources / Gathering / Workers

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Wood/stone resource ledger | IMPLEMENTED | `scripts/village_resources.gd:28-109` | Shared add/has/spend and food classification API |
| Tree/stone 3D nodes | IMPLEMENTED | `scripts/resource_node_3d.gd`, `tree_3d.gd`, `stone_deposit_3d.gd`; corresponding 3D scenes | Claim/depletion/navigation hooks are present |
| Worker data/roster | IMPLEMENTED | `scripts/worker_data.gd:1-62`; `worker_roster.gd:17-176` | Assignment, actor spawn/despawn, freed-workplace cleanup |
| Lumberjack/miner 3D FSM | IMPLEMENTED | `scripts/lumberjack_3d.gd:1-46`; `miner_3d.gd`; `lumberyard_3d.tscn`, `quarry_3d.tscn` | Full gather/return/deposit structure is present |
| Farm/farmer/herb gathering | PARTIAL | `scripts/farm_3d.gd`, `farmer_3d.gd`, `herb_gatherer_3d.gd`, `crop_node_3d.gd` | Production paths exist, but no complete long-term economy/logistics loop was found |

## Buildings / Village Economy

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D building catalog and placement | IMPLEMENTED | `building_placement_3d.gd:33-109,166-224`; 3D building scenes | Includes farm, lumberyard, quarry, walls, gates and pixel building path |
| Core village buildings | IMPLEMENTED | `core_building_3d.gd`; `scenes/core_building_3d.tscn`; `main_3d.tscn:15,76` | Visual/interaction shell is present |
| Tavern recruitment | IMPLEMENTED | `tavern_recruitment_ui.gd:34-137`; `ui/hud_3d.tscn:236` | Worker and mercenary recruitment calls the two rosters |
| Inn roster/assignment/upgrade | IMPLEMENTED | `inn_roster_ui.gd:40-247`; `inn_capacity.gd`; `ui/hud_3d.tscn:238` | Upgrade cost is documented as display-only; no full economy charge found |
| Food population consumption | IMPLEMENTED | `population_consumption.gd:46-218`; `meal_consumption.gd:99-139`; autoload at `project.godot:29` | Runtime consumption is phase-driven and separate from Potion combat use |
| Cooking | IMPLEMENTED / PARTIAL | `cooking_production.gd:1-103`; `cooking_recipes.gd`; `recipe_data.gd` | Recipe production exists; complete player-facing kitchen/building progression is not established |
| Storage/logistics/trade | NOT_FOUND | No production `save`, `storage`, `logistics`, `trade`, or transport owner found | Resource ledger is in-memory only |

## Mercenaries / Combat / Defense

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Mercenary data/roster | IMPLEMENTED | `mercenary_data.gd:1-93`; `mercenary_roster_3d.gd:44-140,323-414`; `main_3d.tscn:86-90` | Persistent identity data is distinct from transient actor nodes |
| Enemy 3D actor | IMPLEMENTED | `enemy_actor_3d.gd`; `scenes/enemy_3d.tscn` | Auto-target/damage/death path exists |
| Mercenary auto combat | IMPLEMENTED | `mercenary_actor_3d.gd:121-230,303-327`; `scenes/mercenary_3d.tscn` | Target acquisition, chase, attack and death are production paths |
| Tactical commands | IMPLEMENTED | `mercenary_roster_3d.gd:147-186`; `ui/tactical_command_ui_3d.tscn`; HUD inclusion at `ui/hud_3d.tscn:240` | Regroup, retreat, focus, time controls and gate commands are wired |
| Gate/wall defense | IMPLEMENTED | `gate_3d.gd`, `wall_3d.gd`, `gate_interactable_3d.gd`; placement constants in `building_placement_3d.gd` | Runtime 3D scenes exist |
| Threat/wave | IMPLEMENTED | `threat_system.gd:18-140`; `wave_manager.gd:24-213`; autoloads `project.godot:34-35` | Wave scheduling and dungeon-clear bridge API exist |
| Skills/equipment/boss | NOT_FOUND | No production owner/reference for skill trees, equipment stats, or boss encounter was found | Dungeon equipment field is only a summary hook |

## Dungeon

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Dungeon definition/manager | IMPLEMENTED | `dungeon_definition.gd`; `dungeon_manager.gd:72-203`; autoload `project.godot:36` | Definitions, states and reward-table registration exist |
| Preparation UI and manager | IMPLEMENTED | `dungeon_preparation_ui.gd:239-493`; `dungeon_preparation_manager.gd:19-200`; `main_3d.tscn:105` | P input, party, Food, Potion and optional equipment summary hooks are wired |
| Dungeon encounter arena | PARTIAL | `dungeon_runtime.gd:24-123,155-216`; `main_3d.tscn:107-108` | Arena and actors load, spawn and clean up; combat uses existing 3D actors |
| Dungeon tactical commands | IMPLEMENTED | `dungeon_runtime.gd:229-315` | Reuses existing tactical command contract |
| Dungeon completion/reward/return | PARTIAL / STUB | `dungeon_reward_table.gd:1-68`; `dungeon_runtime.gd:126-147`; `wave_manager.gd:173-181` | Data container and clear bridge exist, but a complete outcome detector, reward grant and player-return flow was not found |

## Ghost / Death Ledger

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Death record/ledger | IMPLEMENTED | `death_record.gd:1-95`; `death_ledger.gd:1-100`; autoload `project.godot:31` | Snapshot-oriented identity record and duplicate/ghost guards exist |
| Ghost spawn mix | IMPLEMENTED | `ghost_spawn_mix.gd:19-166`; `first_encounter_spawner_3d.gd` references it; `main_3d.tscn:95-96` | Ghost candidates join the existing NIGHT encounter budget |
| Ghost identity/visual/death behavior | IMPLEMENTED | `ghost_actor_3d.gd:1-101`; `scenes/ghost_3d.tscn` | Ghost death resolves original record and does not create recursive records |
| Ghost skills/modifiers/rewards | NOT_FOUND / PARTIAL | `GAME_DESIGN.md:374-412` describes them, but no corresponding authoritative production system was found | Current implementation is identity/visual/ledger-focused |

## Food / Potion

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Food resource categories | IMPLEMENTED | `village_resources.gd:20-109` | Raw/cooked classification and efficiency API |
| Runtime population food consumption | IMPLEMENTED | `population_consumption.gd:70-218` | Phase-driven resource consumption; separate from combat Potion logic |
| Potion data definitions | IMPLEMENTED | `potion_data.gd:1-87` | Data-driven `healing_potion`, HP-below-ratio trigger |
| Potion slot/auto-consume | IMPLEMENTED | `mercenary_data.gd:36-93`; `mercenary_potion_service.gd:1-84`; `mercenary_actor_3d.gd:376-393` | Separate slot, condition false no consume, one consume guard, empty slot safe |
| Potion crafting | PARTIAL | `potion_craft_service.gd` | Crafting owner exists, but complete player-facing herb-to-potion progression is not wired through a demonstrated 3D gameplay loop |
| Food preparation combat buff | NOT_FOUND / PARTIAL | Food preparation data hooks exist in dungeon preparation, but no authoritative long-term combat buff application was found | Do not infer new Food effects from the design text |

## UI / Persistence

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D HUD | IMPLEMENTED | `ui/hud_3d.tscn`; `scripts/hud.gd:43-296` | Resource, food, threat/wave, selection and placement feedback are wired |
| Map/exploration UI | IMPLEMENTED / PARTIAL | `world_map_overlay.gd`; `exploration_manager.gd`; `scout_dispatch_manager.gd` | Map and exploration service paths exist; full discovery progression remains prototype-level |
| Options/audio settings | IMPLEMENTED | `options_menu.gd`; `game_settings.gd`; `audio_manager.gd`; `project.godot:18-20` | Local config persistence exists for settings/volume |
| Game save/load | NOT_FOUND | Production scripts explicitly document no persistent game Save/Load; no save manager owner found | Audio/settings config persistence is not a game save system |

## Tests

- `tests/baseline_3d_health_test.gd` is the relevant current baseline contract: main scene, required autoloads, data script loading, 3D scene instantiation, camera/navigation/group invariants, and no direct Player actor.
- `tests/dungeon_runtime_integration_test.gd` checks the P input binding, DungeonPreparationUI instantiation, manager-to-runtime signal, and P input reachability.
- `tests/task0491_test.gd` checks the audio bus/playback foundation and its audit document.
- `tests/task0275_test.gd` is aligned with the current Potion/Preparation/DeathRecord boundary and is useful as a focused regression, but its historical TASK label is not provenance by itself.
- `tests/smoke_test.gd` is LEGACY/NOT CURRENT: it instantiates `res://scenes/main.tscn` and expects 2D `Main`, Lumberjack, TileMapLayer, 2D tree groups and 2D textures. It does not validate the configured `main_3d.tscn` runtime.
- The repository contains 162 `SceneTree` test files by static inventory. Many are historical TASK tests; their assertions must be treated as regression evidence only when they exercise reachable current production code.

## Game Design Gap

### Design + implementation substantially present

- Player management rather than direct combat: `GAME_DESIGN.md:48-60`, current 3D baseline player-group checks.
- Day/night separation and automatic night defense: `GAME_DESIGN.md:100-149`, `game_time.gd`, roster/spawner/wave consumers.
- Worker hiring/assignment and automated production: `GAME_DESIGN.md:159-228`, worker roster/FSM and 3D facilities.
- Mercenary roster, automatic combat, tactical commands, Potion condition path: `GAME_DESIGN.md:234-299`, current Mercenary/Potion code.
- Death Ledger/Ghost identity concept: `GAME_DESIGN.md:340-447`, current ledger/ghost production path.

### Design + partial implementation

- Dungeon discovery, preparation, combat, rewards and return: `GAME_DESIGN.md:471-510`; preparation and encounter skeleton exist, but completion/reward/return is incomplete.
- Food preparation and combat effects: `GAME_DESIGN.md:512-556`; resource consumption exists, but preparation-to-runtime effect application is not established.
- Farming, herbal ingredients, cooking, and alchemy: `GAME_DESIGN.md:601-713`; core resource/recipe owners exist, but the complete facility progression is not present.
- Wave/Threat strategic loop: `GAME_DESIGN.md:447-470`; threat/wave owners exist, but broader event/boss content is absent.

### Design exists + production not found

- Equipment, skills, quests, factions, shop/trade, storage/logistics, training, healing, repair, boss encounters, and full persistent game saves.

## Current Playable Flow

Configured runtime starts in `main_3d.tscn`, loads the 3D world/environment/navigation and camera, and exposes mouse selection and B-key building placement. The player can select/interact with the 3D village, place supported buildings, view resources/food/threat/wave state, open recruitment and inn management UI, assign workers, and run worker/resource loops. Hired mercenaries remain data in the roster by day, spawn for night combat, use existing tactical commands, and can be recorded by Death Ledger. The Dungeon preparation UI can be opened with physical P, party/Food/Potion hooks can be set, and a prepared run can instantiate the existing 3D arena/actors.

The legacy 2D flow remains in source and tests, but is not the configured application entry and is not included above as current playable behavior.

## Confirmed Broken / Suspicious

1. Fresh asset closure is not self-contained. `.gitignore:5-11` excludes Tiny Swords and Quaternius source material; current source references include `assets/cuteskull-medieval-city/city16.fbx`, `assets/third_party/quaternius/models/`, and Tiny Swords decoration paths. The repository does contain `tools/download_quaternius_packs.ps1`, `tools/download_tiny_swords.ps1`, and generation tools, so this is an external/bootstrap contract rather than proof that the source assets belong in Git.
2. `tests/smoke_test.gd` validates the old 2D scene (`main.tscn`) while `project.godot` selects `main_3d.tscn`. This is a stale test contract, not evidence that the 3D baseline should be reverted.
3. Both 2D and 3D owners coexist. This is intentional during migration in several files, but any new work should target the 3D entry closure and avoid restoring 2D runtime assumptions.

## New Backlog (V3 Draft)

### P0

- V3-001 Reproducible Runtime Asset Bootstrap: make a fresh checkout deterministically acquire/prepare the required external asset packs and fail with a clear diagnostic when unavailable; validate import and `main_3d` health.
- V3-002 Dungeon Completion Vertical Slice: define the existing encounter's terminal outcome, reward grant, party return, cleanup, and Threat/Wave result reporting without creating a second combat system.

### P1

- V3-003 Persistent Game State: add one authoritative save/load owner for resources, rosters, time, threat/wave, exploration, dungeon state, Death Ledger and supported settings, with a fresh-process regression.
- V3-004 Food Preparation Runtime Contract: connect existing Food preparation data to the confirmed long-term preparation effect boundary, without treating Food as a runtime Potion or inventing effects not specified by design.
- V3-005 Production Economy Loop: complete farm/herb/cooking/potion production and player-facing building progression using the existing VillageResources owner.

### P2

- V3-006 Equipment and Combat Progression: define and implement the currently designed equipment/skill progression against the existing MercenaryData/actor owners.
- V3-007 Village Logistics and Capacity: storage, transport, facility capacity and the remaining production buildings.
- V3-008 Content Expansion: boss, quest, faction, shop/trade and deeper Dungeon content only after the vertical slice is stable.

### P3

- V3-009 Replace legacy smoke contract with a current 3D smoke/interaction contract and archive the old 2D-only assertions.
- V3-010 Visual/content polish and asset catalog expansion after bootstrap and runtime contracts are stable.

## Legacy Task Recommendation

- Archive prior TASK status as `LEGACY_HISTORY`; do not use DONE/FAIL labels as current implementation truth.
- Keep current 3D baseline and focused regression tests as the execution basis.
- Do not delete the legacy 2D source/tests in this audit; remove or archive them only through a separately approved migration task after replacement coverage exists.
- No production code, scene, resource, test, reset, clean, merge, or commit was performed by this audit.
