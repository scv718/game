# TASK-3D-001-2 World3D / Coordinate / Collision Foundation Policy

> 병렬 3D Migration 태스크(RES/BLD/WRK/CMB/VIS)가 공통으로 따르는 좌표/충돌 기준점.
> 단일 소스: `scripts/world_coords_3d.gd`(WorldCoords3D), `scripts/collision_layers_3d.gd`(CollisionLayers3D),
> World Root: `scenes/world3d.tscn` + `scripts/world_root_3d.gd`(WorldRoot3D).
>
> 기존 2D Main World(`scenes/main.tscn`, `scenes/world.tscn`)는 즉시 삭제하지 않고 병행 유지한다(LOCK 12).

---

## 1. Coordinate Convention (WorldCoords3D)

| 항목 | 규칙 |
|------|------|
| 지면 평면 | XZ (X = 동(+)/서(-), Z = 남(+)/북(-)) |
| 높이 | Y. ground Y = `GROUND_Y = 0` 고정, 자유 높이 이동/점프 없음 |
| 방향 보존 | 2D logical (x, y) → world `(x, 0, y)`. 2D 북(-Y) = 3D 북(-Z). WEST/NORTH/EAST/SOUTH 역할 불변 |
| 배율 | `PX_TO_UNIT = 0.125` (1 논리 px = 0.125 unit). 균일 배율만 허용 → 월드 크기/거리 비율 불변 |
| grid | 1 논리 타일(`TILE_SIZE=16px`) = `GRID_CELL_UNITS = 2.0` unit. snap은 `snap_xz_to_grid()` 사용 |
| gameplay 거리 | 항상 `distance_xz()`로 계산 (2D distance 의미 보존, 재밸런스 없음) |

### bounds / region 단일 소스

- 기존 4중 정의(`BOUNDS_RECT` / `WORLD_BOUNDS` / `FALLBACK_BOUNDS_RECT` / `WORLD_SIZE`)의 drift를
  3D에서는 `WORLD_BOUNDS_XZ = AABB(-192..+192 XZ)` 하나로 수렴시킨다.
- 기존 Rect2 zone(clearing / defense belt / gate corridor / combat field / rally space /
  agriculture / outer wild slot)은 `rect_to_aabb(rect)` + `aabb_contains_xz()`로 XZ 해석한다.
- `world_map.gd` 상수는 읽기 전용 참조이며 수정하지 않았다(migration map 운영 규칙 2).
- 폴리라인(road/path waypoint)은 `polyline_to_world()`를 사용한다.

## 2. Collision Layer / Mask Policy (CollisionLayers3D)

기존 2D 관례(정적 블로커 layer value 4 / Interactable Area 8 / Actor layer 2·mask 4)를 구조적으로 유지하면서,
요구사항에 따라 카테고리를 세분해 물리 layer만으로 구분 가능하게 했다.

| Layer # | 이름 | bit value | 용도 |
|---------|------|-----------|------|
| 1 | GROUND | 1 | 지면 바닥 + 월드 경계 벽(World Root 소유) |
| 2 | BUILDING | 2 | 건물 본체(Core/Lumberyard/Quarry 등) |
| 3 | WALL | 4 | Wall segment |
| 4 | GATE | 8 | Gate 본체(상태 전환 collision 토글 대상) |
| 5 | RESOURCE | 16 | Tree trunk / Stone deposit 블록 |
| 6 | WORKER | 32 | Worker Actor |
| 7 | MERCENARY | 64 | Mercenary Actor |
| 8 | ENEMY | 128 | Enemy Actor |
| 9 | INTERACTABLE | 256 | 마우스 선택/상호작용 Area3D 전용 |

Mask 규칙:

- 정적 바디는 `collision_mask = 0`(수동 블로커).
- Actor는 `collision_layer = 자기 bit`, `collision_mask = MASK_ACTOR_SOLID`
  (= GROUND\|BUILDING\|WALL\|GATE\|RESOURCE). 기존 2D와 동일하게 **actor끼리는 물리 충돌하지 않는다**.
- 마우스 selection/probe는 `MASK_SELECTION`(INTERACTABLE)만 조회. Resource는 기존 정책대로
  Worker 전용(마우스 직접 채집 차단).
- placement overlap 검증은 `MASK_PLACEMENT_BLOCKERS`를 사용.
- Gate OPEN/CLOSED/BREACHED의 nav/collision 토글 표현은 BLD 태스크가 GATE layer 위에서 수행.

## 3. World Root (WorldRoot3D)

- `Node3D` root + `Ground`(StaticBody3D): 바닥 BoxShape 1개 + 경계 벽 4개(±192 unit 경계선).
- GroundVisual(PlaneMesh) placeholder — 실제 지형/조명/에셋은 VIS 소유이며 교체 대상.
- physics-heavy terrain 금지 원칙 준수: 전체 collision shape 5개 이하.
- script class 이름은 Godot 내장 resource class `World3D`와의 충돌을 피하기 위해 `WorldRoot3D`.
- group: `"world3d"`(기존 2D `"world"` group과 분리).
- Camera(001-3) / Interaction(001-4) / Navigation(001-5)은 각자 이 Root 위에 자기 파일로 연결.

## 4. UI 분리

- UI는 기존대로 `CanvasLayer` / `Control` 계층이다. CanvasLayer는 3D viewport 렌더 위에 항상 그려지므로
  별도 작업 없이 3D World 위 표시가 유지된다.
- UI는 physics layer/mask와 무관하며, world 입력 ownership 분리는 001-3(UI click-through 차단)에서 다룬다.

## 5. 소유 경계 (이 태스크에서 수정하지 않은 것)

- `main.tscn`, `project.godot`, `world.gd`, `world_map.gd`, 기존 2D scene/script 전부 무수정.
- 신규 파일만 추가: `scripts/world_coords_3d.gd`, `scripts/collision_layers_3d.gd`,
  `scripts/world_root_3d.gd`, `scenes/world3d.tscn`, `tests/task3d0012_test.gd`, 본 문서.
- 테스트는 migration map 운영 규칙 5에 따라 기존 tests를 수정하지 않는 신규 `task3d*` 파일로 추가했다.
