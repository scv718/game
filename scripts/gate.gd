extends StaticBody2D
class_name Gate

## TASK-013-3 Gate Placement. 성문 1개는 Wall보다 넓은 footprint를 가진다.
## prototype 기준 3 logical tiles(48px): N/S Gate = 도로를 가로지르는 수평(48x16),
## E/W Gate = 도로를 가로지르는 수직(16x48) orientation.
## static collision(layer 3) + nav obstacle(parse_source_geometry_data)로
## collision/navigation 양쪽에 실제 반영된다.
##
## TASK-013-4 OPEN/CLOSED 상태. 신규 Gate는 CLOSED로 시작한다.
##  - CLOSED: passage collision 활성 + nav 통과 불가.
##  - OPEN: passage collision 비활성 + nav 통과 가능.
## 현재는 Player 상호작용(Interact)으로 prototype toggle하며,
## TASK-015 Command UI가 재사용할 공개 API(is_open/set_open/toggle + signal)를 제공한다.
##
## nav bake는 CollisionShape2D.disabled / collision_layer를 무시하고 physics body의
## shape를 항상 장애물로 파싱하므로, OPEN/CLOSED는 CollisionShape2D 노드의 존재 여부로
## 구분한다(OPEN = shape 제거, CLOSED = shape 재생성). 반복 toggle은 노드 생성/제거와
## debounce nav rebuild만 반복하므로 collision/nav 오류가 누적되지 않는다.
##
## TASK-014-5 Gate Breach: 성문에 prototype 내구도(max_hp)를 두고, CLOSED 성문을 Enemy가
## 공격해 HP 0이 되면 BREACHED(파괴/침입) 상태로 전환해 통로를 영구 개방한다.
##  - OPEN 성문은 Enemy가 공격하지 않고 통과한다(take_damage no-op).
##  - BREACHED 성문은 자동 복구하지 않으며(no auto-recovery), passage가 영구 개방된다.

enum GateState { CLOSED, OPEN, BREACHED }

const HORIZONTAL_SIZE := Vector2(48, 16)
const VERTICAL_SIZE := Vector2(16, 48)

const COLOR_CLOSED := Color(0.42, 0.33, 0.24, 1.0)
const COLOR_OPEN := Color(0.24, 0.22, 0.2, 0.45)
const COLOR_BREACHED := Color(0.15, 0.13, 0.11, 0.3)

## TASK-013-4 공개 API: 상태가 실제로 바뀔 때마다 emit된다 (TASK-015 Command UI 재사용).
signal gate_state_changed(gate: Node, open: bool)

## TASK-014-5: 성문이 파괴(침입)될 때 emit된다.
signal breached(gate: Node)

## TASK-014-5 prototype 내구도. CLOSED 성문에만 적용되며 OPEN 성문은 공격 대상이 아니다.
const DEFAULT_MAX_HP := 200

var direction := "north"
var orientation := "horizontal"
var state: GateState = GateState.CLOSED
var max_hp: int = DEFAULT_MAX_HP
var current_hp: int = DEFAULT_MAX_HP
var _shape_present := true


func _ready() -> void:
	add_to_group("gates")
	current_hp = max_hp
	_apply_footprint()
	_apply_state_visual()
	_apply_passage_collision()


## 배치 시 방향에 맞는 orientation/footprint를 적용한다.
func setup(dir: String) -> void:
	direction = dir
	orientation = "horizontal" if (dir == "north" or dir == "south") else "vertical"
	_apply_footprint()


func get_direction() -> String:
	return direction


func get_orientation() -> String:
	return orientation


func get_footprint_size() -> Vector2:
	return HORIZONTAL_SIZE if orientation == "horizontal" else VERTICAL_SIZE


## TASK-013-4 공개 API: 현재 OPEN 여부. (BREACHED도 통로가 열려 있으므로 true)
func is_open() -> bool:
	return state == GateState.OPEN or state == GateState.BREACHED


func is_closed() -> bool:
	return state == GateState.CLOSED


## TASK-014-5 공개 API: 성문이 파괴/침입되었는지.
func is_breached() -> bool:
	return state == GateState.BREACHED


## TASK-013-4 공개 API: OPEN/CLOSED 설정. 상태가 실제로 바뀔 때만 collision/nav/visual을
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


## TASK-013-4 공개 API: CLOSED로 설정.
func set_closed() -> void:
	set_open(false)


## TASK-013-4 공개 API: OPEN↔CLOSED 반복 토글.
func toggle() -> void:
	set_open(state == GateState.CLOSED)


## TASK-014-5 공개 API: CLOSED 성문에만 피해를 적용한다. OPEN 성문은 공격하지 않고
## 통과하므로 no-op, BREACHED는 이미 파괴되었으므로 no-op. HP 0 이하가 되면
## BREACHED로 전환해 통로를 영구 개방한다(자동 복구 없음).
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
			var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
			if is_instance_valid(col):
				col.free()
	else:
		if not _shape_present:
			_shape_present = true
			var new_shape := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = get_footprint_size()
			new_shape.shape = shape
			new_shape.name = "CollisionShape2D"
			add_child(new_shape)


## passage가 열려 있는(통과 가능한) 상태 여부. OPEN/BREACHED 모두 통로 개방.
func _is_passage_open() -> bool:
	return state == GateState.OPEN or state == GateState.BREACHED


## open/closed/breached visual 구분. collision footprint는 변경하지 않는다.
func _apply_state_visual() -> void:
	var vis := get_node_or_null("Visual") as Polygon2D
	if vis == null:
		return
	var color := COLOR_CLOSED
	if state == GateState.OPEN:
		color = COLOR_OPEN
	elif state == GateState.BREACHED:
		color = COLOR_BREACHED
	vis.color = color


## TASK-013-4: 상태 전환 후 기존 debounce nav rebuild를 사용해
## open/closed에 맞춰 nav obstacle을 갱신한다.
func _request_nav_rebuild() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("rebuild_navigation_debounced"):
		return
	world.rebuild_navigation_debounced()


func _apply_footprint() -> void:
	var size := get_footprint_size()
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		# 씬의 RectangleShape2D sub-resource는 인스턴스끼리 공유되므로,
		# 방향별 footprint를 인스턴스마다 독립 적용하려면 별도 shape를 생성한다.
		var shape := RectangleShape2D.new()
		shape.size = size
		col.shape = shape
	var vis := get_node_or_null("Visual") as Polygon2D
	if vis != null:
		vis.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(size.x, 0.0),
			size,
			Vector2(0.0, size.y),
		])