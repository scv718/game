extends StaticBody3D
class_name Gate3D

## TASK-3D-BLD-001-2 Gate 3D 최소 배치 표현 + TASK-3D-BLD-001-3 상태 머신.
## 기존 gate.gd(StaticBody2D, TASK-013-3/013-4/014-5)의 배치/상태 계약을 3D로
## 이전한 신규 파일이다. 기존 2D gate.gd / gate.tscn은 LOCK 12에 따라 유지된다.
##
## - N/S Corridor gate는 X로 길게(논리 48x16px = 6x2 unit), E/W는 Z로 길게(2x6).
##   setup(dir)이 footprint collision과 placeholder visual을 해당 방향으로 세운다
##   (기존 4방향/Corridor 의미 불변: 2D 북(-Y) = 3D 북(-Z), N/S gate는 도로를
##   가로지르는 world X축 방향). placement는 add_child 전에 setup을 호출하므로
##   노드 조회는 get_node_or_null로 수행한다(기존 gate.gd _apply_footprint와 동일 구조).
## - 씬의 shape/mesh sub-resource는 인스턴스끼리 공유되므로, 방향별 footprint를
##   인스턴스마다 독립 리소스로 생성해 적용한다(기존 gate.gd 주석과 동일 사유).
## - gameplay footprint(collision box)와 visual mesh 높이는 분리된 상수다.
##
## OPEN/CLOSED/BREACHED 상태 머신(기존 gate.gd 계약 동일). 신규 Gate는 CLOSED로 시작한다.
##  - CLOSED: passage collision 활성 + nav 통과 불가.
##  - OPEN: passage collision 비활성 + nav 통과 가능.
##  - BREACHED: 내구도 소진으로 영구 개방. 자동 복구 없음(no auto-recovery).
## Player 상호작용(Interactable3D toggle)과 Command UI가 재사용할 공개 API
## (is_open/set_open/set_closed/toggle/take_damage + signal)를 제공한다.
##
## nav bake는 CollisionShape3D.disabled / collision_layer를 무시하고 physics body의
## shape를 항상 장애물로 파싱하므로(Foundation policy §3), OPEN/CLOSED는
## CollisionShape3D 노드의 존재 여부로 구분한다(OPEN/BREACHED = shape 제거,
## CLOSED = shape 재생성). 반복 toggle은 노드 생성/제거와 debounced nav rebuild만
## 반복하므로 collision/nav 오류가 누적되지 않는다.
## 상태 전환 후 nav 갱신은 NavigationPolicy3D.request_rebuild_debounced(get_tree())
## 단일 유입구(Foundation convention)로 요청한다.
##
## collision layer는 GATE bit(CollisionLayers3D 단일 소스), mask 0 수동 블로커.
## group은 2D("gates")와 분리된 "gates_3d"를 사용한다.

enum GateState { CLOSED, OPEN, BREACHED }

const HORIZONTAL_SIZE_PX := Vector2(48, 16)
const VERTICAL_SIZE_PX := Vector2(16, 48)

const FOOTPRINT_HEIGHT_UNITS := 2.0
const VISUAL_HEIGHT_UNITS := 1.75

## 기존 gate.gd의 상태별 placeholder 색과 동일 값이다.
const COLOR_CLOSED := Color(0.42, 0.33, 0.24, 1.0)
const COLOR_OPEN := Color(0.24, 0.22, 0.2, 0.45)
const COLOR_BREACHED := Color(0.15, 0.13, 0.11, 0.3)

## 기존 gate.gd와 동일한 공개 signal: 상태가 실제로 바뀔 때마다 emit된다.
signal gate_state_changed(gate: Node, open: bool)

## 성문이 파괴(침입)될 때 emit된다.
signal breached(gate: Node)

## prototype 내구도. CLOSED 성문에만 적용되며 OPEN 성문은 공격 대상이 아니다.
const DEFAULT_MAX_HP := 200

var direction := "north"
var orientation := "horizontal"
var state: GateState = GateState.CLOSED
var max_hp: int = DEFAULT_MAX_HP
var current_hp: int = DEFAULT_MAX_HP
var _shape_present := true


func _ready() -> void:
	add_to_group("gates_3d")
	current_hp = max_hp
	_apply_footprint()
	_apply_state_visual()
	_apply_passage_collision()


## 배치 시 방향에 맞는 orientation/footprint를 적용한다(기존 gate.gd.setup 동일 계약).
func setup(dir: String) -> void:
	direction = dir
	orientation = "horizontal" if (dir == "north" or dir == "south") else "vertical"
	_apply_footprint()


func get_direction() -> String:
	return direction


func get_orientation() -> String:
	return orientation


func get_footprint_size() -> Vector2:
	return HORIZONTAL_SIZE_PX if orientation == "horizontal" else VERTICAL_SIZE_PX


## 공개 API: 현재 OPEN 여부. (BREACHED도 통로가 열려 있으므로 true)
func is_open() -> bool:
	return state == GateState.OPEN or state == GateState.BREACHED


func is_closed() -> bool:
	return state == GateState.CLOSED


## 공개 API: 성문이 파괴/침입되었는지.
func is_breached() -> bool:
	return state == GateState.BREACHED


## 공개 API: OPEN/CLOSED 설정. 상태가 실제로 바뀔 때만 collision/nav/visual을
## 반영하고 gate_state_changed를 emit한다. 같은 상태로 다시 부르면 아무 일도 하지 않는다.
## BREACHED 성문은 자동 복구하지 않으므로 set_open(false)로 다시 닫을 수 없다.
func set_open(open: bool) -> void:
	if state == GateState.BREACHED:
		return
	var target := GateState.OPEN if open else GateState.CLOSED
	if state == target:
		return
	state = target
	_apply_state()
	gate_state_changed.emit(self, is_open())


## 공개 API: CLOSED로 설정.
func set_closed() -> void:
	set_open(false)


## 공개 API: OPEN↔CLOSED 반복 토글.
func toggle() -> void:
	set_open(state == GateState.CLOSED)


## 공개 API: CLOSED 성문에만 피해를 적용한다. OPEN 성문은 공격하지 않고 통과하므로
## no-op, BREACHED는 이미 파괴되었으므로 no-op. HP 0 이하가 되면 BREACHED로 전환해
## 통로를 영구 개방한다(자동 복구 없음).
func take_damage(amount: int) -> void:
	if state != GateState.CLOSED or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	if current_hp <= 0:
		_breach()


func _breach() -> void:
	if state == GateState.BREACHED:
		return
	state = GateState.BREACHED
	current_hp = 0
	_apply_state()
	breached.emit(self)
	gate_state_changed.emit(self, is_open())


func _apply_state() -> void:
	_apply_passage_collision()
	_apply_state_visual()
	_request_nav_rebuild()


## OPEN/BREACHED면 passage collision shape 노드를 제거해 physics/nav에서 모두 빠지게 하고,
## CLOSED면 footprint 크기로 다시 생성한다. 반복 호출은 멱등(idempotent)하다.
func _apply_passage_collision() -> void:
	if _is_passage_open():
		if _shape_present:
			_shape_present = false
			var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
			if is_instance_valid(col):
				col.free()
	else:
		if not _shape_present:
			_shape_present = true
			var new_shape := CollisionShape3D.new()
			new_shape.shape = _build_footprint_shape()
			new_shape.position = Vector3(0.0, FOOTPRINT_HEIGHT_UNITS * 0.5, 0.0)
			new_shape.name = "CollisionShape3D"
			add_child(new_shape)


## passage가 열려 있는(통과 가능한) 상태 여부. OPEN/BREACHED 모두 통로 개방.
func _is_passage_open() -> bool:
	return state == GateState.OPEN or state == GateState.BREACHED


## open/closed/breached visual 구분(기존 gate.gd 색 규약). collision footprint는
## 변경하지 않는다. material_override만 상태 색으로 갱신한다(VIS 슬롯 교체 대비).
func _apply_state_visual() -> void:
	var vis := get_node_or_null("Visual/BodyMesh") as MeshInstance3D
	if vis == null:
		return
	var color := COLOR_CLOSED
	if state == GateState.OPEN:
		color = COLOR_OPEN
	elif state == GateState.BREACHED:
		color = COLOR_BREACHED
	if vis.material_override == null:
		var new_mat := StandardMaterial3D.new()
		new_mat.roughness = 1.0
		vis.material_override = new_mat
	var mat := vis.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA \
		if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED


## 상태 전환 후 Foundation debounce nav rebuild 유입구 하나만 사용해
## open/closed/breached에 맞춰 nav obstacle을 갱신한다.
func _request_nav_rebuild() -> void:
	NavigationPolicy3D.request_rebuild_debounced(get_tree())


func _build_footprint_shape() -> BoxShape3D:
	var half := get_footprint_size() * 0.5 * WorldCoords3D.PX_TO_UNIT
	var shape := BoxShape3D.new()
	shape.size = Vector3(half.x * 2.0, FOOTPRINT_HEIGHT_UNITS, half.y * 2.0)
	return shape


## 배치 시 방향에 맞는 footprint collision/visual을 적용한다. shape/mesh는 인스턴스
## 독립 리소스로 생성한다(씬 sub-resource 공유 문서화 주석 참고).
func _apply_footprint() -> void:
	var half := get_footprint_size() * 0.5 * WorldCoords3D.PX_TO_UNIT
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.shape = _build_footprint_shape()
		col.position = Vector3(0.0, FOOTPRINT_HEIGHT_UNITS * 0.5, 0.0)
	var vis := get_node_or_null("Visual/BodyMesh") as MeshInstance3D
	if vis != null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(half.x * 2.0, VISUAL_HEIGHT_UNITS, half.y * 2.0)
		vis.mesh = mesh
		vis.position.y = VISUAL_HEIGHT_UNITS * 0.5
