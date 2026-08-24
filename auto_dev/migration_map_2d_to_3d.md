# TASK-3D-001-1 Current 2D Runtime Audit / Migration Map

> 감사 기준: 실제 코드 reference 검색(grep 전수) + 스크립트 44개 전수 리딩.
> 대상: `scripts/*.gd` 44종, `scenes/*.tscn` 15종, `ui/*.tscn` 6종, `project.godot`,
> `tools/*.gd`, `tests/*.gd`. 문서(AI_TASK_QUEUE.md 등)만으로 판단하지 않음.
>
> 이 문서는 audit-only 산출물이다. 코드 수정은 포함하지 않는다.

---

## 0. 확인 대상별 감사 결과 요약 (확인 대상 15항목)

| # | 확인 대상 | 실제 위치 | 2D 의존 판정 |
|---|-----------|-----------|--------------|
| 1 | Main World Scene | `scenes/main.tscn`(Node2D root), `scenes/world.tscn`(Node2D + TileMapLayer + NavigationRegion2D + StaticBody2D 경계벽 4개 + MapLayout Marker2D 35개) | 3D 변환 필요 |
| 2 | Camera2D / camera controller | `scripts/camera_controller.gd`(Node2D, 자식 Camera2D, zoom Vector2 lerp), `scenes/camera_controller.tscn` | 3D 변환 필요 |
| 3 | Mouse selection / interaction | `scripts/world_selection.gd`(`PhysicsPointQueryParameters2D`, `get_global_mouse_position`, `get_world_2d().direct_space_state`), `scripts/interactable.gd`(Area2D base) | 3D 변환 필요(base 계약만 Foundation 소유) |
| 4 | BuildingPlacement | `scripts/building_placement.gd`(get_global_mouse_position 9곳(:79,81,83,85,87,96,119,132,145), PhysicsShapeQueryParameters2D 3곳, Polygon2D/Line2D ghost, GRID_SIZE=16 snap) | 3D 변환 필요 |
| 5 | Resource Node | `scripts/resource_node.gd`(extends Interactable=Area2D), `scripts/tree.gd`(Polygon2D visual), `scripts/stone_deposit.gd`(자식 StaticBody2D Block), `scenes/tree.tscn`, `scenes/stone_deposit.tscn` | 3D 변환 필요(claim/regrow 로직은 유지) |
| 6 | Worker / Lumberjack / Miner | `scripts/lumberjack.gd`, `scripts/miner.gd`(CharacterBody2D + NavigationAgent2D + move_and_slide), `scripts/character_visual.gd`(AnimatedSprite2D 4방향 anim), `scripts/workplace.gd`/`lumberyard.gd`/`quarry.gd`(SpawnPoint/WorkPoint/DepositPoint = Marker2D Node2D 조회), `scenes/lumberjack.tscn`, `scenes/miner.tscn` | 3D 변환 필요(FSM/생산 규칙 유지) |
| 7 | NavigationRegion2D / NavigationAgent2D / nav rebuild | bake: `scripts/world.gd:39-49`(NavigationServer2D.parse/bake, agent_radius 8). agent: lumberjack/miner/mercenary/enemy `$NavigationAgent2D`. rebuild 호출부: `building_placement.gd`(배치/철거 후), `resource_node.gd:58-61`(_exit_tree debounce), `gate.gd:184-188`(상태 전환) | 3D 변환 필요(rebuild 진입점 계약은 Foundation 001-5가 정의) |
| 8 | Wall / Gate collision/navigation | `scripts/wall.gd`(StaticBody2D, Geometry2D.merge_polygons 인접 비주얼), `scripts/gate.gd`(StaticBody2D, **CollisionShape2D 노드 존재 여부 = nav 장애물 의미**(gate.gd:16-19, 146-161)), `scenes/wall.tscn`, `scenes/gate.tscn` | 3D 변환 필요(CLOSED/OPEN/BREACHED 상태 머신/API 유지) |
| 9 | Mercenary / Enemy | `scripts/mercenary_actor.gd`, `scripts/enemy_actor.gd`(CharacterBody2D + NavigationAgent2D, global_position 거리 계산 전반), `scenes/mercenary.tscn`, `scenes/enemy.tscn` | 3D 변환 필요 |
| 10 | Tactical command world reference | `scripts/mercenary_roster.gd`:400-409(`get_camera_2d().get_canvas_transform().affine_inverse()` screen→world), :301-317(rally point = MapLayout Rect2 center/marker), `scripts/tactical_command_ui.gd`(Control 전용, Gate Node 참조만 전달 — world 좌표 없음) | roster 일부 3D 변환, UI 자체는 유지 |
| 11 | World bounds | `scripts/world_map.gd:15`(BOUNDS_RECT Rect2 -1536,-1536,3072,3072), `scripts/camera_controller.gd:34`(동일 값 중복 정의), `scenes/world.tscn` BoundaryWall_N/S/E/W(StaticBody2D 3072 길이 shape), `scripts/world_map_overlay.gd:20-21`(WORLD_SIZE 3072 하드코딩 중복) | 좌표 변환 필요 + **값 4중 정의 = drift 위험** |
| 12 | Spawn / Region / landmark coordinate | `scripts/world_map.gd` 전역 상수(MAIN_ROADS/VILLAGE_PATHS/SECONDARY_PATHS/FOREST_CLUSTERS/STARTER_TREES/STONE_ZONE/GATE_ANCHORS/SPAWN_CANDIDATES/APPROACH_ROUTES/GATE_CORRIDORS/COMBAT_FIELDS/RALLY_SPACES/OUTER_WILD_SLOTS — 전부 Vector2/Rect2), `scenes/world.tscn` MapLayout Marker2D 35개, `scripts/first_encounter_spawner.gd:146-176`(road waypoint + village core Vector2) | 논리 좌표 데이터 유지 + XZ 해석 전환 필요 |
| 13 | Day/Night visual hooks | 현재 **시각 hook 없음**(CanvasModulate/Light2D/modulate 사용처 0건 — grep 확인). 유일한 시각 분기 = `camera_controller.gd:16-17,96-98`(day_zoom/night_zoom) + `GameTime.phase_changed` 구독자(hud/camera_controller/first_encounter_spawner/mercenary_roster) | hook 신호 자체는 neutral. 3D lighting은 VIS 신규 영역 |
| 14 | Death Ledger Actor reference 경계 | `scripts/death_record.gd`:106-126(snapshot에 **Node reference 없음**, Vector2 death_position만 포함), `scripts/death_ledger.gd`(snapshot 저장 전용), 기록 생산 지점: `mercenary_actor.gd:260` / `enemy_actor.gd:126`(global_position snapshot) | **경계 이미 깨끗함**. 좌표 관례만 결정하면 유지 가능 |
| 15 | UI world position 사용 지점 | (a) `world_selection.gd:36` (b) `building_placement.gd:79,81,83,85,87,96,119,132,145` (c) `mercenary_roster.gd:400-409` (d) `world_map_overlay.gd:185-218`(world_to_map/map_to_world), :238-251(camera viewport rect). `hud.gd`/`tactical_command_ui.gd`/`tavern_recruitment_ui.gd`/`inn_roster_ui.gd`/`death_ledger_view.gd` — world 좌표 미사용(전수 확인) | (a)(b)(c)(d)만 3D 변환 대상 |

---

## 산출물 1. 2D 전용 의존 목록 (파일 → 2D 의존 상세)

### A. Script

| 파일 | 2D 전용 의존 (line 근거) |
|------|--------------------------|
| `scripts/world.gd` | extends Node2D, NavigationRegion2D(:6), NavigationServer2D parse/bake(:43,48), NavigationPolygon/NavigationMeshSourceGeometryData2D(:40-41), Rect2 bounds(:3,44), PackedVector2Array outline(:52-59) |
| `scripts/camera_controller.gd` | extends Node2D, Camera2D(:38,43,106), zoom Vector2 lerp(:53-56), WORLD_BOUNDS Rect2(:34), pan clamp(:76-79) |
| `scripts/world_selection.gd` | extends Node2D, PhysicsPointQueryParameters2D + intersect_point(:87-92), get_world_2d().direct_space_state(:86), get_global_mouse_position(:36), INTERACT_COLLISION_LAYER bit mask(:20) |
| `scripts/building_placement.gd` | extends Node2D, get_global_mouse_position 9곳(:79,81,83,85,87,96,119,132,145), PhysicsShapeQueryParameters2D + intersect_shape(:235-239,246-251,277-282), ghost Polygon2D/Line2D(:34-37,153-178), Transform2D(:237,249,280), GRID_SIZE=16/BUILDING_SIZE=32/WALL_FOOTPRINT=16/GATE 사이즈 px 상수(:13-19) |
| `scripts/interactable.gd` | extends Area2D(class_name Interactable — 전체 selection 계약의 뿌리) |
| `scripts/resource_node.gd` | Interactable(Area2D) 상속, _exit_tree → world.rebuild_navigation_debounced(:58-61) |
| `scripts/tree.gd` | $Canopy/$TrunkVisual/$StumpVisual Polygon2D(:11-13) |
| `scripts/stone_deposit.gd` | extends Node2D, 그룹 "stone_deposits"(scene 내 자식 StaticBody2D Block) |
| `scripts/decoration.gd` | extends Node2D, Sprite2D + texture offset(:12-28) — 순수 시각 |
| `scripts/workplace.gd` | Building(StaticBody2D) 상속, _pick_available_worker Node2D cast + distance_squared_to(:107-120), spawn 위치 = SpawnPoint(Node2D) |
| `scripts/lumberyard.gd` | Workplace 상속, SpawnPoint Node2D global_position(:31-32) |
| `scripts/quarry.gd` | Workplace 상속, WorkPoint/WorkPoint2 Marker2D(:37), SpawnPoint(:56) |
| `scripts/lumberjack.gd` | CharacterBody2D(:1), NavigationAgent2D(:43), move_and_slide/is_on_wall(:151,300), NavigationServer2D.map_get_path(:279), TREE_APPROACH_DISTANCE px(:15) |
| `scripts/miner.gd` | CharacterBody2D(:1), NavigationAgent2D(:29), move_and_slide(:76,105) |
| `scripts/character_visual.gd` | extends AnimatedSprite2D, 부모 CharacterBody2D velocity 4방향 매핑(:5-25) |
| `scripts/wall.gd` | StaticBody2D(:1), Polygon2D Visual(:40), Geometry2D.merge_polygons(:59), FOOTPRINT=16px grid neighbor 판정(:23-33) |
| `scripts/gate.gd` | StaticBody2D(:1), CollisionShape2D 생성/제거로 nav 장애물 토글(:146-161), Polygon2D Visual(:171,200), footprint Vector2(48,16)/(16,48)(:28-29) |
| `scripts/mercenary_actor.gd` | CharacterBody2D(:1), NavigationAgent2D(:59), global_position 거리 기반 range/chase/stuck 전반(:281-330), defense_point/retreat_point Vector2(:43,49) |
| `scripts/enemy_actor.gd` | CharacterBody2D(:1), NavigationAgent2D(:50), waypoint Array[Vector2] route(:41,70-79), GATE_ATTACK_RANGE px(:27) |
| `scripts/first_encounter_spawner.gd` | spawn_point/waypoints/core 전부 Vector2(:80-97,146-176), DIRECTION_AXIS Vector2(:17-22), _spawn_offset px grid(:173-176) |
| `scripts/mercenary_roster.gd` | `_mouse_world_position` get_camera_2d + canvas_transform.affine_inverse(:400-409), FOCUS_PICK_RADIUS px(:16), rally point Rect2.get_center()(301-317) |
| `scripts/world_map.gd` | extends Node2D, 전체 상수가 Vector2/Rect2 px 좌표(TILE_SIZE=16/MAP_TILES=192/:10-13), Marker2D child 조회(:392-609), NAV_RECT(:17-21) |
| `scripts/world_dressing.gd` | extends Node2D, draw_* 2D canvas API 전면(:49-663), Sprite2D props(:544-555) — 2D 전용 드레싱 레이어 |
| `scripts/world_map_overlay.gd` | Control UI이나 world 좌표계 2D 고정: world_to_map/map_to_world(:185-218), cam.zoom/global_position viewport rect(:238-251) |
| `scripts/hud.gd` | CanvasLayer — world 좌표 없음. **유지**(placement group hook만 존재) |

### B. Scene

| Scene | 2D 노드 구성 |
|-------|---------------|
| `scenes/main.tscn` | Node2D root + World/HUD/CameraController/WorldSelection/BuildingPlacement/WorldMapOverlay |
| `scenes/world.tscn` | Node2D root, TileMapLayer Floor(grass/path TileSet), NavigationRegion2D, StaticBody2D BoundaryWall x4(CollisionShape2D), Area2D Tree x60, Node2D StoneDeposit, StaticBody2D 핵심건물 x5(Keep/Tavern/Inn/Grocery/EquipmentShop), Decoration x17, MapLayout Marker2D x35 |
| `scenes/tree.tscn` | Area2D root + Polygon2D Canopy/Trunk/Stump + Sprite2D + 자식 StaticBody2D TrunkBlock(CollisionShape2D) |
| `scenes/stone_deposit.tscn` | Node2D + Sprite2D RockVisual + 자식 StaticBody2D Block(CollisionShape2D) |
| `scenes/core_building.tscn` | StaticBody2D + CollisionShape2D + Sprite2D Visual + Area2D Interact |
| `scenes/lumberyard.tscn` | StaticBody2D + CollisionShape2D + Sprite2D + Marker2D DepositPoint/SpawnPoint + Area2D Interact |
| `scenes/quarry.tscn` | StaticBody2D + CollisionShape2D + Sprite2D + Marker2D MiningPoint/WorkPoint/WorkPoint2/SpawnPoint + Area2D Interact |
| `scenes/wall.tscn` | StaticBody2D + CollisionShape2D + Polygon2D Visual |
| `scenes/gate.tscn` | StaticBody2D + CollisionShape2D + Polygon2D Visual + Area2D Interact |
| `scenes/lumberjack.tscn` | CharacterBody2D + CollisionShape2D + AnimatedSprite2D Visual + Label StateLabel + NavigationAgent2D |
| `scenes/miner.tscn` | CharacterBody2D + CollisionShape2D + AnimatedSprite2D + Label + NavigationAgent2D |
| `scenes/mercenary.tscn` | CharacterBody2D + CollisionShape2D + AnimatedSprite2D + NavigationAgent2D |
| `scenes/enemy.tscn` | CharacterBody2D + CollisionShape2D + AnimatedSprite2D + NavigationAgent2D |
| `scenes/decoration.tscn` | Node2D + Sprite2D |
| `scenes/camera_controller.tscn` | Node2D + Camera2D |
| `ui/hud.tscn` | CanvasLayer — 유지(UI는 3D 전환 대상 아님, LOCK 12) |
| `ui/world_map_overlay.tscn` | CanvasLayer + Control — 유지하되 내부 world 좌표 해석만 수정 |
| `ui/tactical_command_ui.tscn`, `ui/tavern_recruitment_ui.tscn`, `ui/inn_roster_ui.tscn`, `ui/death_ledger_view.tscn` | Control — 유지 |

### C. Tools / Tests

| 파일 | 비고 |
|------|------|
| `tools/generate_world_map.gd` | world.tscn 생성기(Marker2D/CollisionShape2D/NavigationRegion2D 생성). 2D 전용 — 이식하지 않고 migration 후 폐기 예정으로 기록 |
| `tools/capture_world.gd` | Camera2D 스크린샷 캡처 도구(:36-39). 3D에서 별도 캡처 경로 필요(VIS 담당) |
| `tests/task0073_test.gd`(MiningPoint Marker2D 단정 :126), `task0081/0082/0085/0124_test.gd`(CollisionShape2D/StaticBody2D/Area2D 단정), `task0103/0105/0117/0127/0128/0151/0158_test.gd`(Camera2D 단정), `task0115_test.gd`(NavigationAgent2D 단정 :194), `smoke_test.gd`/`task0156_test.gd`(AnimatedSprite2D Visual 단정), `world_visual_composition_test.gd` | 2D 타입 단정 포함 → 3D 회귀는 **기존 파일 수정 대신 신규 `*_test_3d` 계열로 추가** 권장(공유 충돌 회피) |

---

## 산출물 2. 그대로 유지 가능한 순수 game/data logic 목록

dimension-neutral. 3D 전환 시 로직 변경 불요(좌표 관례만 Foundation 정책 따름).

| 파일 | 근거 |
|------|------|
| `scripts/village_resources.gd` | 순수 Dictionary/Signal 자원 저장소. Node2D/physics 불사 |
| `scripts/game_time.gd` | DAY/NIGHT phase/day number/time_scale 순수 상태 + advance. 렌더링 무관 |
| `scripts/worker_data.gd` | RefCounted 주민 데이터(id/name/job/assignment). Object ref만 보유 |
| `scripts/worker_roster.gd` | assign/unassign/actor lifecycle 오케스트레이션. Actor 생성은 workplace.spawn_worker_actor 위임 → 차원 무관 인터페이스 |
| `scripts/mercenary_data.gd` | RefCounted 용병 데이터(HP/damage/defense_zone) |
| `scripts/death_record.gd` | RefCounted snapshot. Node reference 없음(주석 명시 :4-9). Vector2 death_position만 Foundation 좌표 관례 지정 필요 |
| `scripts/death_ledger.gd` | autoload 순수 snapshot 저장소(duplicate/ghost guard 포함) |
| `scripts/death_ledger_view.gd` + `ui/death_ledger_view.tscn` | Control UI. Ledger 조회만 수행 |
| `scripts/exploration_region.gd` | RefCounted region 데이터(world_position/region_bounds — 좌표 관례 지정 필요, 로직 무관) |
| `scripts/exploration_manager.gd` | autoload 탐사 진행도 관리. WorldMap.NE_DUNGEON_CANDIDATE 상수 참조만 |
| `scripts/tactical_command_ui.gd` + `ui/tactical_command_ui.tscn` | Control. 명령 enum + command_issued signal 방출만. world 좌표 없음(Gate Node 참조 전달) |
| `scripts/tavern_recruitment_ui.gd` + `ui/tavern_recruitment_ui.tscn` | Control. world 좌표 미사용 |
| `scripts/inn_roster_ui.gd` + `ui/inn_roster_ui.tscn` | Control. world 좌표 미사용 |
| `scripts/hud.gd` + `ui/hud.tscn` | CanvasLayer. group/signal hook만 사용 |
| `scripts/gate_interactable.gd`, `scripts/lumberyard_interactable.gd`, `scripts/quarry_interactable.gd`, `scripts/core_building_interactable.gd` | **내용은 neutral**(prompt 갱신/토글/UI open). 단 Interactable(Area2D) 상속이라 base 교체 필요 → 산출물 3의 "경계 파일"로 분류 |
| `scripts/resource_node.gd`의 claim/release/interact 반환 Dictionary 규약, `scripts/lumberjack.gd`/`miner.gd`의 FSM 전이·생산량·despawn 규약, `scripts/gate.gd`의 CLOSED/OPEN/BREACHED API, `scripts/workplace.gd`의 slot/assign 규약 | 로직 자체는 유지 대상(이동/충돌 표현만 교체) |

---

## 산출물 3. 3D 변환이 필요한 Scene/Script 목록

### Foundation (TASK-3D-001-2 ~ 001-5) — 신규 생성 원칙

- `world.tscn`/`main.tscn` 즉시 삭제 금지(LOCK 12). 3D World Root는 **신규 scene/script**로 병행 운영.
- `scripts/world.gd`의 nav rebuild 진입점(`rebuild_navigation`, `rebuild_navigation_debounced`)은 001-5 Navigation3D convention이 동등 API로 대체. 호출부 3곳(building_placement/resource_node/gate)은 각 도메인 전환 시 연결 변경.
- `scripts/interactable.gd`(Area2D) → 001-4 Interaction3D 계약이 base 제공. 기존 4개 interactable 서브클래스는 re-base만.

### 도메인별 변환 대상 (파일 수준 경계)

| Domain | Script (2D → 3D) | Scene (2D → 3D) |
|--------|------------------|------------------|
| World/Core | `world.gd`, `camera_controller.gd`(+`camera_controller.tscn`) | `world.tscn`, `main.tscn`(Integration에서 wiring) |
| Selection/Interaction | `world_selection.gd`, `interactable.gd`(base), `gate_interactable.gd`, `core_building_interactable.gd`, `lumberyard_interactable.gd`, `quarry_interactable.gd` | 각 건물 scene의 Interact Area2D → Area3D |
| Building | `building.gd`, `core_building.gd`, `building_placement.gd`, `wall.gd`, `gate.gd`, `workplace.gd`(spawn point 조회부) | `core_building.tscn`, `lumberyard.tscn`, `quarry.tscn`, `wall.tscn`, `gate.tscn` |
| Resource | `resource_node.gd`, `tree.gd`, `stone_deposit.gd` | `tree.tscn`, `stone_deposit.tscn` |
| Worker | `lumberjack.gd`, `miner.gd`, `lumberyard.gd`/`quarry.gd`(Actor spawn부), `character_visual.gd` | `lumberjack.tscn`, `miner.tscn` |
| Combat | `mercenary_actor.gd`, `enemy_actor.gd`, `first_encounter_spawner.gd`, `mercenary_roster.gd`(:400-409 mouse→world, :89-107 spawn부) | `mercenary.tscn`, `enemy.tscn` |
| Map/Layout | `world_map.gd`(Node2D/Marker2D 표현 → XZ 변환. 상수 데이터는 보존) | `world.tscn` MapLayout Marker2D 35개 |
| Visual | `world_dressing.gd`(draw_* 전면), `decoration.gd` | `decoration.tscn` |
| Overlay | `world_map_overlay.gd`(world_to_map/map_to_world 카메라 rect만 수정, UI 구조 유지) | — |

### 좌표 관례 결정이 필요한 공통 지점 (001-2 산출)

1. `TILE_SIZE=16`/`GRID_SIZE=16`/`MAP_TILES=192`/`WORLD_SIZE=3072`(world_map.gd:10-13, building_placement.gd:13) → 3D world unit 변환 상수.
2. `BOUNDS_RECT`(world_map.gd:15) vs `WORLD_BOUNDS`(camera_controller.gd:34) vs `FALLBACK_BOUNDS_RECT`(world.gd:3) vs `WORLD_SIZE`(world_map_overlay.gd:20) — **같은 값의 4중 정의**. 3D에서는 단일 소스로 수렴 권장.
3. Rect2 기반 zone(clearing/belt/corridor/combat field/rally space/agriculture/outer wild) → XZ 평면 사각형 매핑.
4. `death_record.death_position: Vector2`, `exploration_region.world_position: Vector2` → XZ 관례 확정(Vector3 또는 Vector2(x,z)).

---

## 산출물 4. 공유 파일 목록 (병렬 작업 충돌 위험)

| 파일 | 위험 내용 | 충돌 예상 조합 |
|------|-----------|----------------|
| `scenes/world.tscn` | 모든 도메인의 배치 parent + nav region 소유 | RES/BLD/WRK/CMB/VIS 전원 (단, 큐 규칙상 "Main World Scene 직접 수정 금지" — INT-001만 허용) |
| `scripts/world_map.gd` | 모든 도메인이 상수/helper 조회(belt, corridor, rally space, road, forest, deposit) | RES(forest/deposit) + BLD(corridor) + CMB(combat/rally/spawn) + WRK(work_radius) + VIS(landmark) |
| `scripts/world.gd` | nav rebuild 진입점 — BLD(place/remove/gate)와 RES(depleted tree)가 호출, WRK/CMB가 결과에 의존 | BLD + RES + Foundation(001-5) |
| `scripts/interactable.gd` + 4개 서브클래스 | base 클래스 교체 시 전 건물/자원 선택 계약 동반 변경 | Foundation(001-4) + BLD + RES |
| `scripts/building_placement.gd` | BLD 전용이지만 world.rebuild_navigation 호출 + WorldSelection과 build-mode 게이트(`is_active`) 공유 | BLD ↔ Foundation(selection) |
| `scripts/mercenary_roster.gd` | CMB 소유이나 autoload로 TacticalCommandUI가 직접 connect(tactical_command_ui.gd:49) | CMB + UI wiring(INT) |
| `project.godot` | autoload 목록/렌더러 설정. 3D 전환 시 renderer/신규 autoload 반영 필요 | INT-001 단독 수정 원칙 |
| `scripts/world_map_overlay.gd` | WORLD_SIZE 3072 하드코딩 + camera viewport rect — Foundation 좌표 상수와 동기화 필요 | INT + Foundation(001-2/001-3) |
| `scripts/camera_controller.gd` | DAY/NIGHT zoom policy를 CMB tactical camera가 재사용(큐 요구사항) | Foundation(001-3) + CMB |
| `tests/*.gd` | 다수 파일이 2D 타입 단정. 여러 세션이 동시에 같은 테스트를 수정하면 충돌 | 전 도메인 — **도메인별 신규 테스트 파일 추가로 회피** |
| `AI_TASK_QUEUE.md` | 상태 갱신 경합 | 세션별 자기 태스크 항목만 수정 |

---

## 산출물 5. 병렬 태스크별 파일 ownership 초안

원칙: (O)=소유(수정/생성 주체), (R)=읽기 전용 참조, (-)=접근 금지.
"Main World Scene 직접 수정 금지" 큐 규칙을 그대로 존중한다.

| 파일/영역 | 001-2 World3D | 001-3 Cam3D | 001-4 Interact | 001-5 Nav3D | RES | BLD | WRK | CMB | VIS | INT |
|-----------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 신규 3D world root scene/script | O | R | R | R | R | R | R | R | R | O(wiring) |
| 좌표 변환 상수/util(신규) | O | R | R | R | R | R | R | R | R | R |
| camera 3D controller(신규) | - | O | R(mouse ray) | - | - | - | - | R(policy) | R | R |
| interaction 계약(신규) | - | R | O | - | R | R | - | R | - | R |
| navigation convention(신규) | R(bounds) | - | - | O | R | R | R | R | - | R |
| `world.gd`(2D nav) | R | - | - | R(대체 설계) | R | R | R | R | - | O(교체) |
| `interactable.gd` + 서브클래스 re-base | - | - | O(base) | - | R(RES분) | R(BLD분) | - | - | - | R |
| `resource_node.gd`, `tree.*`, `stone_deposit.*` | - | - | R | - | O | - | R(claim API) | - | R(visual slot) | R |
| `building.gd`, `core_building.*`, `building_placement.gd`, `wall.*`, `gate.*` | R(bounds/mask) | R | R | R(nav policy) | - | O | - | R(gate API) | R(visual slot) | R |
| `workplace.gd`, `lumberyard.*`, `quarry.*`(spawn point) | - | - | - | - | R | O(scene) | O(actor spawn) | - | R | R |
| `lumberjack.*`, `miner.*`, `character_visual.gd` | - | - | - | R(convention) | R(tree API) | - | O | - | R(animation) | R |
| `mercenary_actor.*`, `enemy.*`, `first_encounter_spawner.gd`, `mercenary_roster.gd` | R(spawn coord) | R(cam policy) | R(focus pick) | R | - | R(gate) | - | O | R(animation) | R |
| `tactical_command_ui.*` | - | - | - | - | - | - | - | O(wiring만) | - | R |
| `world_map.gd` | R(XZ 관례 정의 근거) | R | - | R(nav rect) | R | R | R | R | R | O(필요 시 표현 계층만) |
| `world_dressing.gd`, `decoration.*`, asset catalog | - | - | - | - | - | - | - | - | O | R |
| `world_map_overlay.gd` | R(상수) | R(camera rect) | - | - | - | - | - | - | - | O(좌표 갱신) |
| `hud.gd` + `ui/*`(tavern/inn/death_ledger/tactical tscn) | - | - | - | - | - | - | - | - | - | 유지(원칙적으로 무수정) |
| `main.tscn` / `project.godot` | - | - | - | - | - | - | - | - | - | O |
| `village_resources.gd`, `game_time.gd`, `worker_data.gd`, `worker_roster.gd`, `mercenary_data.gd`, `death_record.gd`, `death_ledger.gd`, `exploration_region.gd`, `exploration_manager.gd` | - | - | - | - | R | R | R | R | - | - (**무수정**) |
| `tests/*` 기존 파일 | R | R | R | R | R | R | R | R | R | O(최종 회귀) — 도메인은 신규 3D 테스트 파일만 추가 |

### 충돌 최소화 운영 규칙 (완료조건 2번 대응)

1. `world.tscn`, `main.tscn`, `project.godot` — PARALLEL-WAVE-3D-A 기간 편집 금지(큐 LOCK 준수).
2. `world_map.gd` 상수는 읽기 전용. XZ 변환은 Foundation이 만드는 별도 util에서 수행.
3. `world.gd` nav rebuild API 시그니처는 001-5가 먼저 확정하고, BLD/RES는 자기 전환 태스크에서 호출부만 교체.
4. `interactable.gd` re-base는 001-4 계약 확정 이후 각 도메인이 "자기 파일만" 수행.
5. 테스트는 기존 `tests/task*.gd`를 고치지 않고 `tests/task3d*_test.gd` 계열로 추가.

### 완료조건 대조

- [x] 2D → 3D Migration 경계가 파일 수준으로 기록됨 — 산출물 1/3의 파일별 표.
- [x] 병렬 작업 충돌 위험 파일 식별됨 — 산출물 4 + 운영 규칙.
- [x] 구현 전 reference 누락 없음 — scripts 44/44, scenes 15/15, ui 6/6, autoloads 7/7 전수 확인. 확인 대상 15항목 모두 section 0에서 근거 line과 함께 추적.
