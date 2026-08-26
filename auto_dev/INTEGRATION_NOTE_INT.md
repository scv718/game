# TASK-3D-INT-001-1 INTEGRATION NOTE (Main Scene Wiring / Shared Config)

> 후속 태스크(INT-001-2 Vertical Slice, INT-001-3 2D Cleanup)가 소비할
> Main 3D Runtime 셸과 shared config 결정 사항 요약.
> 병렬 도메인 산출물은 전부 "신규 파일 add_child/instance" 방식으로만 연결했고,
> Foundation/RES/BLD/WRK/CMB/VIS 소유 파일은 한 줄도 수정하지 않았다(LOCK 12).

## 신규 / 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `scenes/main_3d.tscn` | 신규 | 3D Main scene. World3D + NavigationManager3D + Environment3D + CameraController3D + WorldSelection3D + BuildingPlacement3D + MercenaryRoster3D + FirstEncounterSpawner3D + HUD(3D) + WorldMapOverlay |
| `ui/hud_3d.tscn` | 신규 | hud.tscn과 동일 구조의 3D용 HUD. 유일한 차이는 TacticalCommandUI 대신 `tactical_command_ui_3d.tscn` 인스턴스(노드명 TacticalCommandUI3D). hud.gd 스크립트 무수정 재사용 |
| `project.godot` | 수정 | `run/main_scene` → `res://scenes/main_3d.tscn` 1행만 변경 |
| `tests/task3dint0011_test.gd` | 신규 | wiring/shared config/duplicate/phase cycle 회귀(80 assertions headless PASS) |
| `.godot/global_script_class_cache.cfg` | 갱신 | stale cache 복구(`--import` 실행). EnemyActor3D/MercenaryRoster3D 등 최근 class_name이 -s 컴파일에서 resolve되지 않던 문제 해소 |

## Wiring 구조 (main_3d.tscn)

```
Main3D (Node3D)
├── World3D                  scenes/world3d.tscn          (group "world3d")
│   └── NavigationManager3D  scripts/navigation_manager_3d.gd
│       └── NavigationRegion3D  ← 런타임 유일 region(manager가 생성)
├── Environment3D            scenes/environment_3d.tscn   (VIS 인계대로 world 위 add)
├── CameraController3D       scenes/camera_controller_3d.tscn
├── WorldSelection3D         scripts/world_selection_3d.gd, groups=["world_selection"]
├── BuildingPlacement3D      scripts/building_placement_3d.gd (코드에서 양 그룹 등록)
├── MercenaryRoster3D        scripts/mercenary_roster_3d.gd
├── FirstEncounterSpawner3D  scripts/first_encounter_spawner_3d.gd
├── HUD                      ui/hud_3d.tscn               (CanvasLayer layer=10)
└── WorldMapOverlay          ui/world_map_overlay.tscn    (M key, Control 계층 유지)
```

- **NavigationRegion 단일화**: Foundation 정책(001-5)대로 region은 NavigationManager3D가
  생성한다. main_3d에는 region을 scene에 배치하지 않아 트리 내
  NavigationRegion3D가 정확히 1개다. parse root는 manager 부모(World3D 전체)다.
- **WorldSelection3D legacy group**: 스크립트는 "world_selection_3d"만 자체 등록하므로,
  hud.gd의 prompt hook 조회명("world_selection")을 scene 측 group 선언으로 충족시켰다
  (2D main.tscn이 하던 것과 동일한 wiring 계층 처리 — Foundation 스크립트 무수정).
  BuildingPlacement3D는 코드에서 "building_placement"+"building_placement_3d" 양쪽을
  이미 등록하므로 scene 선언 불요였다(BLD 노트 계약 확인).
- **Camera 단일화**: Camera3D는 camera_controller_3d.tscn 1곳뿐이고 `_ready`에서
  make_current() 한다. 트리 내 Camera2D/Node2D는 0개.

## duplicate input owner 제거 — hud_3d.tscn이 필요한 이유

- 기존 `hud.tscn`은 **2D** TacticalCommandUI를 포함하고, 그 스크립트는 `_ready`에서
  2D autoload `MercenaryRoster._on_tactical_command`를 **직접 connect**한다
  (tactical_command_ui.gd:49).
- 3D Main에서 hud.tscn을 그대로 쓰면 NIGHT마다 명령 UI가 2개 뜨고(2D+3D),
  2D UI는 autoload roster(3D 월드 부재로 inert)에게 명령을 날리는 dead input owner가 된다.
- 따라서 INT 소유 범위에서 tactical UI 슬롯만 3D판으로 교체한 hud_3d.tscn을 신설하고
  Main에는 이것을 연결했다. 나머지(recruitment/inn/death ledger)는 차원 중립이라 그대로.
- 결과: "tactical_command_ui"(2D) 그룹 노드 0개, "tactical_command_ui_3d" 1개,
  `command_issued ↔ MercenaryRoster3D._on_tactical_command` guarded connect 1회.

## Shared config 결정

1. **Autoload 7종 전부 유지**(변경 없음): VillageResources / GameTime / WorkerRoster /
   MercenaryRoster / FirstEncounterSpawner / DeathLedger / ExplorationManager.
   - 2D combat autoload(MercenaryRoster, FirstEncounterSpawner)는 `"world"`(2D) 그룹
     lookup으로 guard되어 있어 3D Main에서는 no-op임을 테스트가 고정했다(spawn 0).
     제거는 INT-001-3(2D cleanup) 소유이며 지금은 LOCK 12 유지가 정답.
2. **InputMap 변경 없음**: 3D 조작은 기존 action으로 충분하다.
   WASD pan = move_left/right/up/down, build mode = build(B)+KEY_1..4/R raw keycode,
   zoom/select/cancel = 마우스 휠/클릭 + ui_cancel(내장), world map = world_map(M),
   death ledger = death_ledger(L). 새 action을 만들지 않았다(파편화 방지).
3. **Collision layer 갱신 없음**: CollisionLayers3D 코드 단일 소스가 유일 기준이며
   project.godot layer_names 섹션은 사용하지 않는 기존 관례 유지.
4. **import cache 복구**: 메인 워크트리의 global class cache가 최신 3D class를 몰라
   `-s` 테스트 컴파일이 깨지는 상태였다. `--headless --import` 1회 실행으로
   재해소(오류 0건). 부수로 Godot이 .import 파일들의 EOL만 재기록했는데
   실 content diff 0건 확인 후 working tree 원복했다(관련 없는 파일 무변화 원칙).

## 검증 결과

- `tests/task3dint0011_test.gd` — **80 assertions 전부 PASS**, 연속 재실행 PASS.
  커버: main_scene 3D path 설정, wired resource 11종 존재, InputMap action 8종,
  autoload 7종, wiring 1-owner 그룹 11종, Camera3D/NavigationRegion3D/
  WorldEnvironment/DirectionalLight3D 각 1개, 2D 노드/그룹 잔존 0,
  DAY→NIGHT→DAY cycle(NIGHT encounter 3 spawn → idle 중복 없음 → DAY despawn
  orphan 0, ledger 무기록, time scale 1x 복원, tactical UI 표시/숨김).
- 실행 로그: `test_results/task3dint0011_test_run.txt`, 재실행:
  `test_results/task3dint0011_test_rerun.txt`.
- 프로젝트 부팅: `--headless --quit-after 120`로 run/main_scene 경로 직접 부팅
  ERROR/WARNING 0건 (`test_results/task3dint0011_main_boot_run.txt`).
- import 전수 재검증: `--headless --import` 오류 0건
  (`test_results/task3dint0011_import_run.txt`).
- 회귀 재실행 PASS: smoke(2D reference path), task3d0012(Foundation),
  task3dcmb0012(tactical wiring), task3dbld0014(building regression) — 로그
  `test_results/task3dint0011_rerun_*.txt`.

## 남은 것 (후속 태스크 인계)

- **INT-001-3**: dormant 2D autoload(MercenaryRoster/FirstEncounterSpawner)와
  2D runtime 파일 정리, `scenes/main.tscn` 최종 처리.
- **VIS-002**: ground placeholder 톤/terrain 교체(INTEGRATION_NOTE_VIS §4 인계 항목),
  village composition prototype의 gameplay 통합 여부 판단.

---

# TASK-3D-INT-001-2 INTEGRATION NOTE (Existing Gameplay Vertical Slice 3D)

> 위 INT-001-1 셸 위에서 22단계 vertical slice(게임 시작 → DAY 운영 → 건설/고용/배치/
> 자동 생산 → 고갈/regrowth → NIGHT 전투 지휘 → Death Ledger → DAY 복귀 → 재반복)를
> 실제 Runtime으로 완성한다. 기존 2D scene/script는 한 줄도 수정하지 않았다(LOCK 12).

## 신규 / 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `scripts/world_content_3d.gd` | 신규 | WorldMap 상수(읽기 전용)에서 Tree 60그루(STARTER_TREES 3 + FOREST_CLUSTERS 57) + StoneDeposit 1개를 결정적으로 생성. RNG 없음 |
| `scripts/world_map_layout_3d.gd` | 신규 | MapLayout3D. roster/spawner/overlay가 소비하는 조회 계약(get_rally_space/get_clearing_rect/get_spawn_candidate/get_main_road/get_gate_anchor)을 WorldMap 상수 alias로 제공 |
| `scripts/workplace_3d.gd` | 신규 | 2D workplace.gd의 slot/assign/spawn 규약을 3D로 이전한 중간 클래스(Building3D 상속). workers_changed 신호, _pick_available_worker(XZ 거리), spawn/despawn_actor 계약 |
| `scripts/lumberyard_3d.gd` | 수정 | Building3D 직계 → Workplace3D 상속(2D 계층 Lumberyard→Workplace→Building과 동일). spawn_worker_actor(lumberjack_3d), dual-group("lumberyards"+"lumberyards_3d"), work_radius 프로퍼티명은 WRK duck-typing 계약 |
| `scripts/quarry_3d.gd` | 수정 | 동일한 Workplace3D 상속 + get_work_point_for(배치 index 분배) + dual-group("quarries") |
| `scripts/building_placement_3d.gd` | 수정 | 1행: `sample.work_radius_px` → `sample.work_radius`(위 프로퍼티명 계약 정합) |
| `scripts/world_map_overlay.gd` | 수정 | world lookup에 `/root/Main3D/World3D` fallback, camera rect는 CameraController3D.ground_point_from_screen 4모서리 교차를 logical Rect2로 변환해 표시 |
| `scripts/mercenary_hire_sync_3d.gd` | 신규 | 주점 고용(2D autoload MercenaryRoster) → MercenaryRoster3D 동일 데이터 객체 bridge |
| `scenes/main_3d.tscn` | 수정 | World3D 아래 MapLayout3D(marker 13종) + 핵심 건물 5종(Keep/Tavern/Inn/Grocery/EquipmentShop, world.tscn 논리 좌표의 XZ 변환값) + WorldContent3D + MercenaryHireSync3D wiring |
| `tests/task3dint0012_test.gd` | 신규 | 22단계 시나리오 회귀(98 assertions, 연속 2회 PASS) |
| `tests/task3dbld0012_test.gd` | 수정 | 2 assertion: Lumberyard3D/Quarry3D 직계 부모 단정을 "Workplace3D 경유 Building3D 계층" 단정으로 갱신(의미 보존: Building3D lineage + prompt/marker 계약은 그대로 검증) |

## 설계 결정

1. **content 조립은 코드 생성**: world.tscn의 Marker2D/노드 배치를 복제하는 대신
   WorldMap 상수 단일 소스에서 결정적으로 생성한다(2D/3D layout drift 구조적 차단).
   장식(dressing/decoration)은 VIS-002 소유로 만들지 않았다.
2. **핵심 건물 5종은 main_3d.tscn 배치**: spawner/roster가 world 루트 직계 자식
   "Keep"/MapLayout을 조회하는 CMB 계약을 scene wiring으로 충족.
3. **Workplace3D 중간 클래스 도입**: 여관 UI/WorkerRoster가 요구하는 slot/spawn
   오케스트레이션 계약이 2D에서 Workplace 층에 있었기 때문. BLD-0012의 직계 단정만
   갱신하고 나머지 layer/footprint/prompt/marker 단정은 무수정 통과.
4. **dual-group 등록**: 여관 UI가 조회하는 legacy lookup명("lumberyards"/"quarries")
   을 3D workplace이 겸해 등록한다(3D 월드에는 2D workplace이 없어 오염 없음).
   BuildingPlacement3D의 기존 방식과 동일.

## 테스트 작성 시 발견한 headless 타이밍 규약 (후속 공통)

- **pan_camera는 상대 offset 계약**이다. 절대 목적지 이동 시 현재 pivot과의 delta를
  전달해야 한다. 같은 프레임 내 pan+unproject+클릭 합성 입력은 화면 좌표가 HUD
  Control 위로 떨어지면 GUI가 클릭을 흡수한다(UI click-through 차단이 정상 동작하는
  결과). 테스트는 pivot delta 보정으로 해결했다.
- **시간 의미 예산은 반드시 physics frame 기준**(INTEGRATION_NOTE_WRK 규약 재확인).
  idle frame 예산은 생산 1주기(~400 tick)를 커버하지 못해 오탐을 냈다.

## 검증 결과

- `tests/task3dint0012_test.gd`: **98 assertions 전부 PASS**, 연속 재실행 PASS
  (`test_results/task3dint0012_run7.txt`, `task3dint0012_run8.txt`).
- 회귀 재실행 전부 PASS: smoke(2D reference), task3d0012(Foundation),
  task3dbld0012(placement 계약 — 위 2 assertion 갱신 반영), task3dbld0014(building
  regression), task3dcmb0012/0013(tactical), task3dwrk0012/0013(worker/nav stress),
  task3dres0011/0012(resource).
- 임시 probe 스크립트는 사용 후 전부 삭제했다(운영 규칙 22/23).
