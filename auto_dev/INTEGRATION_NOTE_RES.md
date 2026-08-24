# TASK-3D-RES-001 INTEGRATION NOTE (Resource / Gathering 3D Migration)

> 후속 도메인(WRK/BLD/INT)이 3D Resource Runtime을 소비할 때 필요한 계약 요약.
> 기존 2D Resource 파일(resource_node.gd / tree.gd / stone_deposit.gd / tree.tscn /
> stone_deposit.tscn)은 LOCK 12에 따라 전부 무수정으로 유지되었다. 3D Runtime은
> 아래 신규 파일로 병행 운영된다.

## 신규 파일

| 파일 | 역할 |
|------|------|
| `scripts/resource_node_3d.gd` | ResourceNode3D base(Interactable3D 상속). claim/gather 규약 |
| `scripts/tree_3d.gd` | WorldTree3D. MATURE/STUMP/regrow + visual/collision state 일관 |
| `scripts/stone_deposit_3d.gd` | StoneDeposit3D. Quarry occupancy anchor |
| `scenes/tree_3d.tscn` | Tree 3D scene(placeholder primitive visual) |
| `scenes/stone_deposit_3d.tscn` | Stone deposit 3D scene |
| `tools/capture_resources_3d.gd` | 자원 visual screenshot 캡처(3D판) |
| `tests/task3dres0011/0012/0013_test.gd` | 서브태스크별 회귀 테스트 |

## 도메인 간 계약 (후속 태스크 소비 지점)

1. **Worker(WRK) - Tree 탐색/채집**
   - 그룹 `"resource_nodes_3d"`로 자원 노드를 열거하고, `resource_id == "wood"` +
     `can_interact()` + `is_claimed_by_other(self)` 필터는 기존 lumberjack.gd
     `_find_nearest_tree`와 동일 규약을 유지한다.
   - 거리 판정은 `WorldCoords3D.distance_xz`, 접근 위치는 자원 `global_position`
     (지면 접지점, Actor Origin LOCK 준수) 기준으로 한다.
   - claim API: `claim(worker) / release(worker) / is_claimed() /
     is_claimed_by_other(worker)` — 2D와 시맨틱 동일.
   - gather: `interact(worker)` 반환 Dictionary `{"resource_id", "amount"}`를
     `VillageResources.add()`로 반납하는 기존 흐름 유지.

2. **Building(BLD) - Quarry 배치**
   - 그룹 `"stone_deposits_3d"`로 deposit을 조회한다(2D "stone_deposits"와 분리).
   - `occupy(quarry) / release() / is_occupied() / get_quarry()` 규약은 2D와 동일.
   - deposit Block(StaticBody3D, RESOURCE layer)이 MASK_PLACEMENT_BLOCKERS에
     포함되므로 placement overlap 검증은 Foundation mask 정책을 그대로 따른다.

3. **Selection/Interaction(Foundation)**
   - ResourceNode3D는 `is_selectable() == false`로 Worker 전용 정책을 유지한다
     (마우스 직접 채집 차단 - 기존 world_selection.gd allow-list의 hook 대체).
   - root Area3D collision layer는 INTERACTABLE(256)이 아닌 **RESOURCE(16)**다.
     이유: 3D 선택 광선은 최근접 hit 1개만 반환하므로, 자원을 INTERACTABLE에
     올리면 자원에 가려진 건물 선택이 실패하는 2D에는 없던 regression이 생긴다
     (task3dres0011_test가 이 시나리오를 회귀 고정).
   - 자원의 물리 블록(TrunkBlock/Block)은 RESOURCE layer로 MASK_ACTOR_SOLID에
     참여하며, nav bake 장애물로 파싱된다.

4. **Navigation(Foundation 001-5)**
   - 자원 관련 nav rebake 진입점은 `NavigationPolicy3D.request_rebuild_debounced()`
     하나다. 호출 지점: (a) ResourceNode3D._exit_tree(자원 freed), (b) Tree3D
     depletion/regrowth state 전환(충돌 shape 교체).
   - collision 표현은 `collision_shape.disabled` 토글이 아니라 **shape 리소스
     교체**다. bake가 disabled 플래그를 무기하고 파싱하기 때문이다(gate 규약 동일).

## Visual 슬롯 (VIS 도메인 인계)

- Tree/Stone의 mesh는 전부 `Visual` Node3D 하위 MeshInstance3D다. Quaternius
  `Stylized Nature MegaKit` 투입(TASK-3D-VIS-002-1) 시 이 슬롯의 mesh만 교체하면
  되고, game logic/충돌/claim 규약은 무수정이다.
- Tree3D의 제한적 variation(위치 hash 기반 결정적 yaw + uniform scale,
  `variation_enabled/scale_min/scale_max` export)은 Visual child에만 적용되며
  gameplay footprint(TrunkCollision r=0.75 unit = 2D trunk 6px 불변)와 분리되어
  있다. 실물 mesh 투입 후에도 이 분리 계약을 유지할 것.
- stump/regrow 표현도 Visual 하위 가시성 토글이다(StumpVisual).
- 현재 visual은 placeholder primitive(green canopy sphere + brown cylinder /
  gray rock sphere)다. 스크린샷: `test_results/resources_3d_preview.png`(zoom 1.0),
  `resources_3d_preview_far.png`(zoom 0.5). 캡처 도구가 임시 라이트/환경을
  스스로 구성한다(VIS가 최종 environment 소유).

## 검증 결과

- `tests/task3dres0011_test.gd` — base 계약/claim/hit volume/decoration 구분/
  depletion-regrowth state 일관/freed 정리: 전부 PASS.
- `tests/task3dres0012_test.gd` — visual 구조/단순 충돌 shape/식별성/variation
  결정성·범위/footprint 분리: 전부 PASS.
- `tests/task3dres0013_test.gd` — claim/deplete/regrow/stone state/VillageResources
  반영/freed reference/Foundation selection 회귀/2D 의존 부재: 전부 PASS.
- 실행 로그: `test_results/task3dres001{1,2,3}_test_run.txt`.
- 남은 것: TASK-3D-RES-001-2의 HUMAN_CHECK(숲 반복감, 건물/Worker 대비 크기감,
  zoom-out 가독성) — 스크린샷 2장이 3번 항목의 1차 자료다.
