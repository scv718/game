# TASK-3D-BLD-001 INTEGRATION NOTE (Building / Placement 3D Migration)

> 후속 도메인(WRK/VIS/INT/CTRL)이 3D Building Runtime을 소비할 때 필요한 계약 요약.
> 기존 2D Building 파일(core_building.gd / building_placement.gd / wall.gd / gate.gd /
> lumberyard.gd / quarry.gd와 대응 scene들)은 LOCK 12에 따라 전부 무수정으로
> 유지되었다. 3D Runtime은 아래 신규 파일로 병행 운영된다.

## 신규 파일

| 파일 | 역할 |
|------|------|
| `scripts/building_3d.gd` | Building3D base(StaticBody3D). Visual slot + 정적 충돌 holder |
| `scripts/core_building_3d.gd` | CoreBuilding3D. 5종 핵심 건물 identity/data(2D와 동일 값) |
| `scripts/core_building_interactable_3d.gd` | 핵심 건물 선택 volume(Interactable3D 상속) |
| `scripts/building_placement_3d.gd` | BuildingPlacement3D. mouse ray -> XZ grid 배치 컨트롤러 |
| `scripts/lumberyard_3d.gd` / `quarry_3d.gd` | Workplace 건물 3D(기존 marker/prompt 계약 유지) |
| `scripts/lumberyard_interactable_3d.gd` / `quarry_interactable_3d.gd` | workplace 선택 volume |
| `scripts/wall_3d.gd` | Wall segment 3D + 인접 link 비주얼(멱등 refresh_visual) |
| `scripts/gate_3d.gd` | Gate 3D + CLOSED/OPEN/BREACHED 상태 머신 |
| `scripts/gate_interactable_3d.gd` | 성문 토글용 Interactable3D |
| `scenes/core_building_3d.tscn` 외 5종 | 건물/wall/gate 3D scene(3D runtime node만 포함) |
| `tools/capture_buildings_3d.gd` | 건물 visual screenshot 캡처(3D판) |
| `tests/task3dbld001{1,2,3,4}_test.gd` | 서브태스크별 회귀 테스트 |

## 도메인 간 계약 (후속 태스크 소비 지점)

1. **Worker(WRK) - Workplace 배정**
   - 그룹 `"lumberyards_3d"` / `"quarries_3d"`로 workplace을 열거한다(2D 그룹과 분리).
   - Quarry3D는 기존과 동일한 marker 노드를 유지한다: `MiningPoint`,
     `WorkPoint`, `WorkPoint2`, `SpawnPoint`(get_node 조회 계약 동일).
   - prompt는 기존 형식 그대로다: `"Workers: 0/2 - Assign Worker"`(lumberyard),
     `"Workers: 0/2 - Assign Miner"`(quarry). Interact로 배정 UI/로직을 연결한다.
   - work radius는 기존 192px를 `192 * WorldCoords3D.PX_TO_UNIT` = 24 unit으로
     환산해 사용한다(placement ghost ring이 동일 상수 소비).

2. **Placement/입력(CTRL/HUD)**
   - 컨트롤러는 `"building_placement"`(기존 2D 조회명)와
     `"building_placement_3d"`(차원 명시 조회명) 양쪽 그룹에 등록된다.
     signal `mode_changed/feedback/building_type_changed`와 `is_active()`도
     2D 계약과 동일하므로 기존 소비자는 무수정으로 동작한다.
   - 키: `B` 토글, `1/2/3/4` 타입(lumberyard/quarry/wall/gate), `R` remove mode,
     `ESC`/우클릭 취소. BUILD_COSTS는 2D와 동일 값(lumberyard/quarry 10, wall 2,
     gate 5 wood). 배치 성공 시 1회 차감, invalid/부족 무차감, remove 전액 환불.
   - **입력 ownership**: build mode 활성 동안 좌/우클릭은 placement가 소유하고
     `set_input_as_handled()`로 막는다. WorldSelection3D는
     `can_handle_world_click()`으로 이를 우회 게이트한다(이중 동작 방지 회귀 고정).
   - 단일 배치 건물(lumberyard/quarry)은 성공 시 mode 자동 종료, wall은 연속
     배치를 위해 mode를 유지한다(TASK-013-1 정책 불변).

3. **Selection/Interaction(Foundation)**
   - 건물 선택은 `Interact` Area3D(INTERACTABLE layer) 경유다. 본체
     (BUILDING/WALL/GATE layer)는 MASK_ACTOR_SOLID/nav 전용이고 선택 광선
     (MASK_SELECTION, areas only)은 본체를 무시한다(2D 관례 회귀 고정).
   - Tavern 클릭 -> `recruitment_ui` group `open()`, Inn 클릭 ->
     `inn_roster_ui` group `open()` 계약은 2D와 동일하다. 나머지 3종은
     prompt-only(빈 interact 결과)다.
   - GateInteractable3D는 상태별 prompt(`"Gate (OPEN) - Toggle"`)를 제공하고
     `interact()`로 OPEN/CLOSED를 토글한다.

4. **Gate 상태 머신(CMB 후속 소비)**
   - 공개 API: `is_open/is_closed/is_breached/set_open/set_closed/toggle/
     take_damage`, signal `gate_state_changed/breached`. 신규 gate는 CLOSED,
     prototype max_hp 200, OPEN 성문은 공격 no-op, BREACHED는 자동 복구 없음
     (재닫기 시도 무시) — 기존 gate.gd 계약 동일.
   - **collision 표현은 shape 노드의 존재 여부**다. nav bake가
     `CollisionShape3D.disabled`/layer를 무기하고 파싱하므로(Foundation policy
     §3) OPEN/BREACHED는 shape free, CLOSED는 footprint shape 재생성으로 구현했다.
     반복 toggle에도 collision/nav 오류가 누적되지 않는다(회귀 고정).
   - footprint: N/S corridor gate는 world X로 길게(논리 48x16px = 6x2 unit),
     E/W는 Z로 길게(2x6). `setup(dir)`가 방향별 collision/visual을 적용하며
     shape/mesh는 인스턴스 독립 리소스다(씬 sub-resource 공유 방지).

5. **Navigation(Foundation)**
   - 배치/철거/gate 상태 전환 모두 `NavigationPolicy3D.request_rebuild_debounced(
     get_tree())` 단일 유입구만 사용한다. 건물 본체/wall/gate(CLOSED)는 bake
     장애물로 편입되고, OPEN/BREACHED passage는 통과 가능하다.
   - 철거는 그룹에서 먼저 제거한 뒤 queue_free한다(제거 직후 neighbor 비주얼/
     nav가 stale 대상을 잡지 않게 하는 순서 계약).

## Visual 슬롯 (VIS 도메인 인계)

- 모든 mesh/Label3D는 `Visual` Node3D 하위에만 존재하고 collision은 전부
  슬롯 밖에 있다. Quaternius 건물 visual 투입 시 슬롯의 mesh만 교체하면 되고
  game logic/충돌/footprint는 무수정이다.
- **gameplay footprint(collision shape)와 visual mesh 크기는 분리된 상수다**
  (예: lumberyard footprint 4x4 unit vs 자유로운 visual mesh). 실물 model 투입
  후에도 footprint collision을 gameplay 단일 소스로 유지할 것.
- placeholder 식별성: core_type별 상이한 albedo 색 + 건물 label NameLabel.
  Gate 상태색은 2D 규약 동일(CLOSED 불투명 갈색 / OPEN 반투명 / BREACHED 더
  투명). 현재 visual은 전부 placeholder primitive다.
- HUMAN_CHECK 자료: `test_results/buildings_3d_preview.png`(zoom 1.0),
  `buildings_3d_preview_far.png`(zoom 0.5). 핵심 5종 + wall 라인 + 북 corridor
  gate 배치. 캡처 도구가 임시 라이트/환경을 스스로 구성한다(VIS가 최종
  environment 소유).

## 검증 결과

- `tests/task3dbld0011_test.gd` — base 계약/identity/선택/정적 충돌/visual slot/
  2D 의존 부재: 전부 PASS.
- `tests/task3dbld0012_test.gd` — snap/pan-zoom 좌표/ghost/validity/cost-refund/
  wall-gate 규칙: 전부 PASS.
- `tests/task3dbld0013_test.gd` — gate 상태 머신/orientation/wall link/
  collision-nav 전환/breach: 전부 PASS.
- `tests/task3dbld0014_test.gd` — 큐 자동검증 10항목(selection/placement/
  invalid/remove-refund/wall/gate/UI interaction/pan-zoom 좌표/3D collision/
  resource overlap)을 하나의 통합 시나리오로 회귀 고정: 83 assertions 전부 PASS.
- 실행 로그: `test_results/task3dbld001{1,2,3,4}_test_run.txt`.
- 남은 것: TASK-3D-BLD-001-4의 HUMAN_CHECK(Top-down 건물 형태 가독성, 지붕이
  클릭/유닛 가독성을 해치지 않는지, footprint 대비 model scale 자연스러움) —
  스크린샷 2장이 1차 자료다. 실물 model 투입은 VIS 태스크에서 진행한다.
