extends RefCounted
class_name WorldCoords3D

## TASK-3D-001-2 3D Coordinate Convention / logical grid 변환 유틸리티.
##
## 좌표 정책 (Top-down 3D Direction LOCK):
##   - X = 동(+)/서(-), Z = 남(+)/북(-) 지면 이동 평면, Y = 높이(자유 이동 없음).
##   - 기존 2D 논리 좌표는 +X = 동, +Y = 남(화면 하단)이므로
##     logical (x, y) -> world (x, 0, y) 방향 해석이 그대로 보존된다.
##     즉 2D 북(-Y) = 3D 북(-Z), WEST/NORTH/EAST/SOUTH 역할 변화 없음.
##
## 스케일 규칙:
##   - 월드 크기 확대/축소 금지(LOCK)를 지키기 위해 균일 배율만 사용한다.
##   - PX_TO_UNIT = 0.125 (1 논리 px = 0.125 world unit, 1 논리 타일 16px = 2 unit).
##   - 모든 gameplay 거리는 비율이 보존되며, 절대 감각은 도메인 전환 태스크가
##     이 util의 변환 함수를 통해서만 해석한다(파편적 하드코딩 금지).
##
## bounds 단일 소스:
##   - 기존 BOUNDS_RECT(world_map.gd) / WORLD_BOUNDS(camera_controller.gd) /
##     FALLBACK_BOUNDS_RECT(world.gd) / WORLD_SIZE(world_map_overlay.gd)의
##     4중 정의 drift를 3D에서는 이 클래스 하나로 수렴시킨다.
##   - 2D 상수 자체는 읽기 전용 참조(migration map 운영 규칙 2)이고 수정하지 않는다.

const PX_TO_UNIT := 0.125
const UNIT_PER_PX := 8.0

## 기존 logical grid 의미 보존: TILE_SIZE=16px(grid 1칸) -> 2.0 world unit.
const GRID_CELL_PX := WorldMap.TILE_SIZE
const GRID_CELL_UNITS := GRID_CELL_PX * PX_TO_UNIT
const TILE_SIZE_UNITS := GRID_CELL_UNITS

## 지면 높이. 자유 높이 이동/점프 금지(LOCK)에 따라 ground Y는 항상 0.
const GROUND_Y := 0.0

## 기존 WorldMap.BOUNDS_RECT(-1536,-1536,3072,3072)의 XZ 표현 (= ±192 unit).
const WORLD_HALF_UNITS := WorldMap.WORLD_HALF * PX_TO_UNIT
const WORLD_BOUNDS_XZ := AABB(
	Vector3(-WORLD_HALF_UNITS, GROUND_Y, -WORLD_HALF_UNITS),
	Vector3(WORLD_HALF_UNITS * 2.0, 0.0, WORLD_HALF_UNITS * 2.0))

## 기존 DIRECTION_AXIS/방향 상수와 동일한 방향 해석을 3D XZ로 고정.
const DIRECTION_XZ := {
	"north": Vector3(0.0, 0.0, -1.0),
	"south": Vector3(0.0, 0.0, 1.0),
	"east": Vector3(1.0, 0.0, 0.0),
	"west": Vector3(-1.0, 0.0, 0.0),
}


## logical 2D 좌표 -> 지면(XZ) world 좌표. height는 장식/시각 용도 외 사용 금지.
static func to_world_xz(logical: Vector2, height := GROUND_Y) -> Vector3:
	return Vector3(logical.x * PX_TO_UNIT, height, logical.y * PX_TO_UNIT)


## world 좌표 -> logical 2D 좌표(Y 무시).
static func to_logical(pos: Vector3) -> Vector2:
	return Vector2(pos.x * UNIT_PER_PX, pos.z * UNIT_PER_PX)


## Y를 제거한 지면 투영 좌표.
static func flatten(pos: Vector3) -> Vector3:
	return Vector3(pos.x, GROUND_Y, pos.z)


## gameplay 거리는 항상 XZ 평면 거리로 계산한다(2D distance 의미 보존).
static func distance_xz(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


## 기존 Rect2 zone(clearing/belt/corridor/combat field/rally space 등)을
## 지면 XZ AABB로 변환. min_y/max_y는 시각 볼륨 용도 외에는 기본값 유지.
static func rect_to_aabb(rect: Rect2, min_y := GROUND_Y, max_y := GROUND_Y) -> AABB:
	return AABB(
		Vector3(rect.position.x * PX_TO_UNIT, min_y, rect.position.y * PX_TO_UNIT),
		Vector3(rect.size.x * PX_TO_UNIT, max_y - min_y, rect.size.y * PX_TO_UNIT))


## XZ 평면 포함 여부(Y 무시). Rect2.has_point와 동일한 경계 의미를 유지한다
## (min 경계는 포함, max 경계는 제외) -> 기존 is_in_bounds 판정과 1:1 일치.
static func aabb_contains_xz(box: AABB, pos: Vector3) -> bool:
	return pos.x >= box.position.x and pos.x < box.end.x \
		and pos.z >= box.position.z and pos.z < box.end.z


## logical 폴리라인(road/path waypoint Array[Vector2]) -> world XZ 폴리라인.
static func polyline_to_world(points: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = to_world_xz(points[i])
	return out


## 기존 building grid snap((pos / 16).floor() * 16)과 동일 결과를 world unit로 수행.
## Y는 보존하며 XZ만 스냅한다.
static func snap_xz_to_grid(pos: Vector3) -> Vector3:
	var snapped_x := floorf(pos.x / GRID_CELL_UNITS) * GRID_CELL_UNITS
	var snapped_z := floorf(pos.z / GRID_CELL_UNITS) * GRID_CELL_UNITS
	return Vector3(snapped_x, pos.y, snapped_z)


static func world_bounds_aabb() -> AABB:
	return WORLD_BOUNDS_XZ


static func is_in_bounds_xz(pos: Vector3) -> bool:
	return aabb_contains_xz(WORLD_BOUNDS_XZ, pos)
