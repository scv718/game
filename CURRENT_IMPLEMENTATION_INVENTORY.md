# Current Implementation Inventory

## Audit Baseline

- Repository: `D:\game`
- Branch: `main`
- HEAD: `815fbb5e8d7028fe95bf89c991d1ab4b4c60c95e` (V3 batch close: 14/14 DONE)
- Audit date: 2026-09-08 (Asia/Seoul)
- Working tree: clean at audit snapshot
- Runtime entry: `res://scenes/main_3d.tscn` (`project.godot:11-15`)

This inventory is based on current production source, scene wiring, autoloads, and test contents. Historical TASK status and agent reports are not implementation evidence. V3 DONE labels in `auto_dev/state_v2.json` / `auto_dev/runs/integration_done.log` are runtime truth for *workflow* completion; this document classifies what the *source* actually contains.

## Closeout Re-run Evidence (2026-09-08, main @ 815fbb5e)

Headless task regression re-run (`godot --headless -s tests/*.gd`) on the final V3 state:

| Test | Result on main | Note |
|---|---|---|
| `baseline_3d_health_test.gd` | PASS | Canonical gate (last line `BASELINE_3D_RESULT=PASS`) |
| `v3001_test.gd` | PASS | Dungeon death-report contract |
| `v3002_test.gd` | PASS | 3D asset bootstrap/closure contract |
| `v3003_test.gd` | PASS | Wave snapshot/restore contract |
| `v3004_test.gd` | PASS | Economy accessor contract |
| `v3005_test.gd` | PASS | Food expedition bridge contract |
| `v3006_test.gd` | **HANG** | Equipment assertions skipped (`get_mercenary_data` does not exist; unguarded `.call()` → script error → no `quit()` → headless hang) |
| `v3007_test.gd` | **vacuous PASS** | Skill block aborts at invalid `Script.has_constant` call (v3007_test.gd:65) before any skill assertion; no FAIL is recorded |
| `v3008_test.gd` | PASS | Ghost identity preservation contract |
| `v3009_test.gd` | PASS | Village capacity API contract |
| `v3010_test.gd` | PASS | Boss encounter API contract (existence-level) |
| `v3011_test.gd` | **FAIL** | `buy_resource`/`sell_resource`/`get_resource_price` don't exist; gold != 100 |
| `v3012_test.gd` | **FAIL** | `add/get_faction_reputation` expected on WaveManager (exists only as DeathLedger stubs) |
| `v3013_test.gd` | PASS | Current 3D smoke contract (main_3d loads, autoloads, dungeon/prep methods) |
| `v3014_test.gd` | PASS | Death ledger content accessors |

## Executive Summary

The current canonical runtime is a 3D/2.5D village-management prototype with a coherent world, camera, selection/placement, worker, mercenary, combat, threat/wave, dungeon-preparation/runtime, ghost, food/potion, morale, exploration, and audio foundation. The V3 batch added small, contract-level extensions on top of that foundation and a reusable 3D test contract, but did NOT deliver complete gameplay systems for equipment, skills, shop/trade, quest/faction, boss flow, storage/logistics transport, or a full red save/load loop.

Key closeout facts:
- V3 workflow 14/14 DONE and main is fully integrated; the 3D gate `tests/baseline_3d_health_test.gd` passes.
- Several V3 commits are test-only or near-test-only: V3-002 (asset bootstrap contract), V3-006 (equipment), V3-007 (skills), V3-011 (shop/trade), V3-013 (3D contract), and the "production" parts of V3-001/004/008/012/014 are additive, small, mostly defensive methods.
- Three V3 regressions are currently broken on main: `v3006_test.gd` HANGS, `v3011_test.gd` and `v3012_test.gd` FAIL, and `v3007_test.gd` passes vacuously (skill block never executes). Production lacks the equipment/skill/shop/faction APIs these tests require. This is reproducible evidence, not workflow status.
- The largest source-level gaps remain persistent game save/load, equipment, skills, shop/trade, quests/factions, a wired boss encounter, logistics transportation, and a complete dungeon reward/return loop.

## Implementation Summary

| Classification | Current findings |
|---|---|
| IMPLEMENTED | 3D entry/world, camera, mouse selection, building placement, resource nodes, worker roster/FSM, mercenary roster/FSM, auto combat, gates/walls, threat/wave, Ghost/Death Ledger (incl. V3 original-mercenary-identity snapshot), food consumption, potion slot/auto-consume, morale, exploration/map UI, audio foundation; wave/threat snapshot-restore bridge; dungeon death-report helper; **current 3D test contract** (`baseline_3d_health_test.gd` + `tests/v3013_test.gd`) |
| PARTIAL | Dungeon completion/reward/return loop (report_death helper + clear bridge exist; no wired reward grant/player-return flow), farm->food production economy permits (accessor layer added), food expedition bridge (consume 1 unit at start_run, refund at complete_run; no combat-buff boundary), ghost combat identity (data-layer only) |
| STUB | Wave/threat snapshot API; village resource capacity + facility output capacity + transport destination data API (no production callers); boss encounter API + spawn helper (no wired callers); quest/faction placeholder stubs (DeathLedger, `pass`/`0`) |
| TEST_ONLY / BROKEN | `v3006_test.gd` HANG (equipment API absent), `v3011_test.gd` FAIL (shop/trade API absent), `v3012_test.gd` FAIL (faction API on wrong owner), `v3007_test.gd` vacuous PASS (skill block aborts); legacy `smoke_test.gd` stale 2D contract; 162 historical SceneTree tests |
| NOT_FOUND | Full save/load manager, equipment system (weapon/armor/accessory, attack/defense bonuses), skills (SKILLS loadout, initialize/execute), shop/trade (gold, buy/sell/price), quests/factions, wired boss encounter, storage/logistics transport flow |

## Core Systems

| Feature | Status | Evidence | Tests / notes |
|---|---|---|---|
| 3D game entry | IMPLEMENTED | `project.godot:11-15`; `scenes/main_3d.tscn` | `tests/baseline_3d_health_test.gd` is the canonical gate |
| Global services | IMPLEMENTED | `project.godot:22-38` (InnCapacity, VillageResources, GameTime, WorkerRoster, MercenaryRoster, PopulationConsumption, FirstEncounterSpawner, DeathLedger, ExplorationManager, AudioManager, ThreatSystem, WaveManager, DungeonManager, DungeonPreparationManager, GameSettings) | Autoload existence explicitly checked by baseline + v3013 |
| Day/night | IMPLEMENTED | `scripts/game_time.gd`; consumers in mercenary/encounter/consumption/wave | Phase-driven actor subscription |
| Input | IMPLEMENTED | `project.godot:44-90` (WASD, E, B, L, M, P `dungeon_prep`) | P physical keycode 80 |

## Player / Control

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Direct player actor | NOT_FOUND (intentional) | baseline checks empty `player`/`players` groups; `scripts/world_selection_3d.gd` documents player removal | Design rule: player does not fight directly |
| 3D camera pan/zoom | IMPLEMENTED | `scripts/camera_controller_3d.gd`; `main_3d.tscn:78` | Separate runtime owner |
| Mouse world selection | IMPLEMENTED | `scripts/world_selection_3d.gd`; `main_3d.tscn:80-81` | Interactable3D API |
| Building placement input | IMPLEMENTED | `scripts/building_placement_3d.gd`; `main_3d.tscn:83-84` | Grid, overlap, cost, catalog, wall/gate paths |

## World / Map / Visuals

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D world and navigation | IMPLEMENTED | `scenes/world3d.tscn`; `scripts/world_root_3d.gd`, `world_content_3d.gd`; `main_3d.tscn:26-74` | + NavigationRegion owner |
| Terrain/village composition | IMPLEMENTED | `scripts/village_composition_3d.gd`; `scenes/village_composition_3d.tscn` | Instantiated via world content |
| 3D asset catalog | PARTIAL | `scripts/visual_asset_catalog_3d.gd` | Quaternius/Tiny Swords sources external/ignored; `tests/v3002_test.gd` locks the bootstrap/closure contract |
| Portal | STUB / PARTIAL | `scripts/world_map.gd`; visual dressing in `village_composition_3d.gd` | Markers/visual yes; authoritative gameplay no |

## Resources / Gathering / Workers

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Wood/stone resource ledger | IMPLEMENTED | `scripts/village_resources.gd` | add/has/spend + food classification |
| Tree/stone 3D nodes | IMPLEMENTED | `scripts/resource_node_3d.gd`, `tree_3d.gd`, `stone_deposit_3d.gd` | Claim/depletion/navigation hooks |
| Worker data/roster | IMPLEMENTED | `scripts/worker_data.gd`; `worker_roster.gd` | Assignment, actor spawn/despawn, freed-workplace cleanup; V3 `assign_worker()` alias + `get_worker_capacity()` (`InnCapacity`) + `get_current_workers()` |
| Lumberjack/miner 3D FSM | IMPLEMENTED | `lumberjack_3d.gd`, `miner_3d.gd`, `lumberyard_3d.tscn`, `quarry_3d.tscn` | Full gather/return/deposit structure |
| Farm/farmer/herb loop | PARTIAL | `farm_3d.gd`, `farmer_3d.gd`, `herb_gatherer_3d.gd`, `crop_node_3d.gd` | Production owners exist; no complete farm->food economy loop demonstrated; V3-004 added only accessor aliases |
| Village capacity/logistics | STUB | `village_resources.gd`: `_capacities`, `set/get_capacity`, `add_resource_storage`, `get_resource_capacity`, `is_resource_overflowing`, `handle_overflow`, `set/get_facility_output_capacity`, `update_facility_output`, `set/get_transport_destination` | Data/API surface only; no production facility/transport caller found |

## Buildings / Village Economy

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D building catalog and placement | IMPLEMENTED | `building_placement_3d.gd`; 3D building scenes | Farm, lumberyard, quarry, walls, gates |
| Core village buildings | IMPLEMENTED | `core_building_3d.gd`; `scenes/core_building_3d.tscn`; `main_3d.tscn:15,76` | Visual/interaction shell |
| Tavern recruitment | IMPLEMENTED | `tavern_recruitment_ui.gd`; `ui/hud_3d.tscn:236` | Worker + mercenary recruitment |
| Inn roster/assignment/upgrade | IMPLEMENTED | `inn_roster_ui.gd`; `inn_capacity.gd` | Upgrade cost display-only |
| Food population consumption | IMPLEMENTED | `population_consumption.gd`; `meal_consumption.gd` | Phase-driven, separate from potion combat use |
| Cooking | IMPLEMENTED / PARTIAL | `cooking_production.gd`, `cooking_recipes.gd`, `recipe_data.gd` | Recipe production yes; full kitchen progression no |
| Storage/logistics/trade | NOT_FOUND | No production save/storage/transport/trade owner; VillageResources is in-memory only; capacity API unconsumed | V3-011 shop/trade contract FAILs against production |

## Mercenaries / Combat / Defense

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Mercenary data/roster | IMPLEMENTED | `mercenary_data.gd`; `mercenary_roster_3d.gd`; `main_3d.tscn:86-90` | Data vs transient actor separated; roster API is `get_mercenary()` |
| Enemy 3D actor | IMPLEMENTED | `enemy_actor_3d.gd`; `scenes/enemy_3d.tscn` | Auto-target/damage/death |
| Mercenary auto combat | IMPLEMENTED | `mercenary_actor_3d.gd`; `scenes/mercenary_3d.tscn` | Acquire/chase/attack/death |
| Tactical commands | IMPLEMENTED | `mercenary_roster_3d.gd`; `ui/tactical_command_ui_3d.tscn`; HUD | Regroup/retreat/focus/time/gate wired |
| Gate/wall defense | IMPLEMENTED | `gate_3d.gd`, `wall_3d.gd`, `gate_interactable_3d.gd` | Runtime 3D scenes |
| Threat/wave | IMPLEMENTED | `threat_system.gd`; `wave_manager.gd` | Wave scheduling + dungeon-clear bridge; V3 snapshot/restore bridge |
| Equipment system | NOT_FOUND | `mercenary_data.gd` exposes only potion slot (`equip_potion`/`unequip_potion`/`get_potion_slot_*`); no weapon/armor/accessory, no `get_attack_bonus`/`get_defense_bonus`; `v3006_test.gd` HANGS | Equipment summary hook exists only in dungeon preparation |
| Skill system | NOT_FOUND | `mercenary_actor_3d.gd` has no `SKILLS`, `_skill_loadout`, `initialize_skill`, `execute_skill`, `_in_range`; `v3007_test.gd` vacuous PASS (aborts at invalid `has_constant` call) | Skill data/design references only |
| Boss encounter | STUB | `dungeon_manager.gd`: `is_boss_encounter_active`, `start_boss_encounter`(no-op true), `complete_boss_encounter`(no-op true); `dungeon_runtime.gd`: `spawn_boss_for_dungeon` (EnemyActor3D `boss_<id>`), `needs_boss_spawn` | No production caller of any boss function; wave flow not wired |

## Dungeon

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Dungeon definition/manager | IMPLEMENTED | `dungeon_definition.gd`; `dungeon_manager.gd`; autoload | Definitions, states, reward-table registration |
| Preparation UI and manager | IMPLEMENTED | `dungeon_preparation_ui.gd`; `dungeon_preparation_manager.gd`; `main_3d.tscn:105` | P input, party, Food, Potion, equipment summary hooks |
| Dungeon encounter arena | PARTIAL | `dungeon_runtime.gd`; `main_3d.tscn:107-108` | Arena/actors load, spawn, clean up |
| Dungeon tactical commands | IMPLEMENTED | `dungeon_runtime.gd` | Tactical command contract reuse |
| Dungeon completion/reward/return | PARTIAL | `dungeon_reward_table.gd`; `dungeon_manager.gd` (`start/complete/fail_run`, `get_completion_count`); `wave_manager.gd` clear-apply; V3-001 `DeathLedger.report_death()` | Outcome/clear scaffolding + death reporting exist; no wired reward-grant and player-return flow backend; `complete_run` refunds expedition food |

## Ghost / Death Ledger

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Death record/ledger | IMPLEMENTED | `death_record.gd`; `death_ledger.gd`; autoload | Snapshot identity + duplicate/ghost guards; V3 `report_death()`, `get_death_count()`, `get_death_record()` |
| Ghost spawn mix | IMPLEMENTED | `ghost_spawn_mix.gd`; `first_encounter_spawner_3d.gd`; `main_3d.tscn:95-96` | Joins NIGHT encounter budget |
| Ghost identity/death behavior | IMPLEMENTED | `ghost_actor_3d.gd`; `scenes/ghost_3d.tscn` | Death resolves original record; no recursion |
| Ghost identity preservation | PARTIAL | `death_ledger.gd` `_original_mercenary_data` + `get_original_mercenary_data()` for MERCENARY deaths (V3-008) | Original-loadout snapshot kept at data layer; no ghost-combat application of it |
| Ghost skills/modifiers/rewards | NOT_FOUND / PARTIAL | Design text only (`GAME_DESIGN.md:374-412`) | No authoritative production system |

## Food / Potion

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Food resource categories | IMPLEMENTED | `village_resources.gd` | Raw/cooked classification, V3 `get_food_count()` |
| Runtime population food consumption | IMPLEMENTED | `population_consumption.gd` | Phase-driven; separate from Potion |
| Potion data + slot/auto-consume | IMPLEMENTED | `potion_data.gd`; `mercenary_data.gd`; `mercenary_potion_service.gd`; `mercenary_actor_3d.gd` | Condition/consume-guard path |
| Potion crafting | PARTIAL | `potion_craft_service.gd` | Owner exists; not wired to a 3D loop |
| Food expedition effect | STUB / PARTIAL | `dungeon_manager.gd` `start_run` deducts 1 unit of selected food from VillageResources; `complete_run` refunds it (has_method-guarded) | Conditional consume/refund bridge only; the design's preparation-to-combat effect boundary is not implemented |

## UI / Persistence

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| 3D HUD | IMPLEMENTED | `ui/hud_3d.tscn`; `scripts/hud.gd` | Resource/food/threat/wave/selection/placement feedback |
| Map/exploration UI | IMPLEMENTED / PARTIAL | `world_map_overlay.gd`; `exploration_manager.gd`; `scout_dispatch_manager.gd` | Discovery progression prototype-level |
| Options/audio settings | IMPLEMENTED | `options_menu.gd`; `game_settings.gd`; `audio_manager.gd` | Local config persistence only |
| Wave/threat snapshot | PARTIAL | `wave_manager.gd` `get_wave_snapshot()`/`restore_wave_snapshot()`/`get_wave_count()`/`get_threat_level()` (V3-003) | In-memory snapshot/restore bridge over existing to/from_snapshot | 
| Game save/load (full) | NOT_FOUND | No save manager; scripts document no persistent Save/Load | Settings config persistence is not a game save system |
| Shop / Trade | NOT_FOUND | No gold/economy owner, no `buy_resource`/`sell_resource`/`get_resource_price`; `v3011_test.gd` FAILs | V3-011 delivered no production code |
| Quest / Faction | NOT_FOUND | `death_ledger.gd` stubs: `add_faction_reputation` (`pass`), `get_faction_reputation` (returns 0); `v3012_test.gd` FAILs (expects API on WaveManager) | Placeholder only, no quest/faction system |

## Tests

- `tests/baseline_3d_health_test.gd` is the canonical 3D gate (main scene, autoloads, data scripts, 3D instantiation, camera/navigation/player-group invariants). Re-run on closeout: **PASS**.
- `tests/v3013_test.gd` is the current 3D smoke/contract test added by V3-013 (main_3d loads; DungeonManager/DungeonPreparationManager parse; autoload set; dungeon methods). Re-run: **PASS**.
- V3 task regressions: see the Closeout Re-run Evidence table at top. `v3006` (HANG), `v3011`/`v3012` (FAIL), `v3007` (vacuous PASS) are not usable as pass-claims on the current source.
- `tests/smoke_test.gd` is LEGACY/NOT CURRENT (2D `main.tscn` contract). It was not deleted/archived by V3-013 (only `v3013_test.gd` was added).
- Historical TASK tests (~160 files) are regression evidence only when they exercise reachable current production code.

## Game Design Gap

### Design + implementation substantially present

- Player management rather than direct combat (`GAME_DESIGN.md:48-60`).
- Day/night and automatic night defense (`GAME_DESIGN.md:100-149`).
- Worker hiring/assignment and automated production (`GAME_DESIGN.md:159-228`).
- Mercenary roster, tactical commands, Potion condition path (`GAME_DESIGN.md:234-299`).
- Death Ledger/Ghost identity concept (`GAME_DESIGN.md:340-447`).

### Design + thin/partial implementation (V3-cold)

- Dungeon discovery, preparation, combat, rewards and return (`GAME_DESIGN.md:471-510`): scaffolding + death reporting only; reward grant/return not wired.
- Food preparation and expedition effects (`GAME_DESIGN.md:512-556`): consume/refund bridge only; buff boundary absent.
- Farming/cooking/alchemy economy (`GAME_DESIGN.md:601-713`): owners exist; complete facility progression not present.

### Design exists + production not found

- Equipment, skills, quests/factions, shop/trade, storage/logistics, boss encounter flow, full persistent game saves.

## Current Playable Flow

Configured runtime starts in `main_3d.tscn` (3D world/environment/navigation + camera, mouse selection, B-key placement). Player can manage village resources/food/threat/wave, recruit workers/mercenaries, assign workers, run gather loops, open the Dungeon preparation UI (physical P), and instantiate the 3D arena. V3 confirmed/strengthened the 3D entry and test contract but did not change the playable scope materially; equipment/skill/shop/faction/boss/save features are not reachable in play.

Legacy 2D flow remains in source/tests and is not the configured entry.

## Confirmed Broken / Suspicious

1. `tests/v3006_test.gd` HANGS (headless) because it calls the nonexistent `get_mercenary_data` via unguarded `.call()` on MercenaryRoster (v3006_test.gd:28) after its `has_method` probe already failed → script error → `quit()` never runs.
2. `tests/v3007_test.gd` vacuously passes: line 65 calls `Script.has_constant`, which does not exist in GDScript; the script error aborts the whole skill-check block, no assertion executes, `V3007_RESULT=PASS` is printed from an unexercised state.
3. `tests/v3011_test.gd` FAILs on production (no shop/trade API, no gold).
4. `tests/v3012_test.gd` FAILs on production (faction API exists only as DeathLedger stubs, not on WaveManager as the test expects).
5. Boss encounter API (`start/complete_boss_encounter`, `spawn_boss_for_dungeon`) has no production caller.
6. Capacity/transport API (`village_resources.gd`) has no production caller; it is data-only.
7. Fresh asset closure is not self-contained (Quaternius/Tiny Swords external/ignored, bootstrap scripts under `tools/`); `v3002_test.gd` locks the bootstrap contract.
8. `tests/smoke_test.gd` (2D) is stale vs the configured `main_3d.tscn` entry.

## Legacy Task Recommendation

- Archive prior TASK status as `LEGACY_HISTORY`; do not use DONE/FAIL labels as implementation truth.
- Keep the 3D baseline and focused regressions as the execution basis.
- Do not delete legacy 2D source/tests outside a separately approved migration task.
- Future work targeting equipment/skills/shop/faction/boss/save must first repair or replace the broken V3 regressions (`v3006`, `v3007`, `v3011`, `v3012`) so they reflect reachable production APIs.