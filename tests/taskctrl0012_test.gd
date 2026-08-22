extends SceneTree

## TASK-CTRL-001-2 Mouse World Selection / Interaction 검증.
## 기존 Player InteractArea/E 물리 접근 대신 마우스 클릭 기반으로 건물/시설/성문을
## 선택하고 기존 interact() API(Recruitment/Roster UI 등)를 재사용하는 WorldSelection
## 동작을 검증한다.
##
## 검증 항목:
##  1. WorldSelection 노드/그룹 존재 + Player 근처 없어도 interaction 가능.
##  2. Tavern click → Recruitment UI open.
##  3. Inn click → Roster UI open.
##  4. Keep/Grocery/Equipment click → 선택만(기존 UI 없음).
##  5. 빈 땅 / decoration / 나무(자원 노드) click → interaction 없음, 선택 유지.
##  6. Lumberyard / Quarry click → 선택 가능(interact 안전).
##  7. Gate click → 선택 + OPEN/CLOSED toggle(기존 interaction 정책과 충돌 없음).
##  8. Right Click / ESC → 선택 해제.
##  9. Build mode 활성 → 월드 click 차단(_unhandled_input 경로 포함).
## 10. 모달 UI(Recruitment/Roster) 열림 → 월드 click 차단(UI click-through 없음).
## 11. NIGHT → 건물 click 차단(전술 조작은 Tactical Command UI 담당).
## 12. 회귀: main scene / 5 core buildings / floor / Camera Controller 유지.
##
## 참고: pan/zoom + click의 카메라 기반 screen→world 전체 입력 시뮬레이션은
## TASK-CTRL-001-5 통합 검증에서 다룬다(headless viewport가 64x64로 작아 화면
## 좌표 기반 특정 건물 클릭 시뮬레이션은 여기서 하지 않는다).

enum Phase {
	SETUP,
	SELECT_BUILDINGS,
	GATE_LUMBERYARD,
	GUARDS,
	NIGHT,
	REGRESSION,
	DONE,
}

const TAVERN_POS := Vector2(-126, -48)
const INN_POS := Vector2(126, -48)
const KEEP_POS := Vector2(0, -148)
const GROCERY_POS := Vector2(-122, 116)
const EQUIPMENT_POS := Vector2(122, 116)
const TREE1_POS := Vector2(340, 320)
const DECO0_POS := Vector2(220, 200)
const EMPTY_POS := Vector2(0, 300)
const LUMBERYARD_POS := Vector2(300, 260)
const QUARRY_POS := Vector2(500, 260)
const GATE_POS := Vector2(-528, 0)

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _failed := false

var _main: Node = null
var _world: Node = null
var _selection: Node = null
var _placement: Node = null
var _game_time: Node = null
var _resources: Node = null
var _controller: Node = null

var _tavern: Node = null
var _tavern_interact: Node = null
var _inn_interact: Node = null
var _ui_tavern: Control = null
var _ui_inn: Control = null

var _lumberyard: Node = null
var _quarry: Node = null
var _gate: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0


func _finish() -> void:
	print("TASKCTRL0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _selected() -> Node:
	return _selection.get_selected() as Node if _selection != null else null


func _selected_at(pos: Vector2) -> Node:
	return _selection.select_at_world_position(pos) as Node if _selection != null else null


func _left_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _right_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	return ev


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				_main = root.get_node("Main")
				_world = _main.get_node("World")
				_selection = _main.get_node("WorldSelection")
				_placement = _main.get_node("BuildingPlacement")
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_resources = root.get_node("VillageResources")
				var ctrls := get_nodes_in_group("camera_controller")
				_controller = ctrls[0] if ctrls.size() > 0 else null
				_tavern = _world.get_node("Tavern")
				_tavern_interact = _tavern.get_node("Interact")
				_inn_interact = _world.get_node("Inn").get_node("Interact")
				_ui_tavern = get_first_node_in_group("recruitment_ui") as Control
				_ui_inn = get_first_node_in_group("inn_roster_ui") as Control
				_resources._amounts["wood"] = 10000
				_check(_main != null and _world != null and _selection != null \
					and _placement != null and _game_time != null \
					and _controller != null, "core nodes present")
				_check(_selection != null and _selection.is_in_group("world_selection"), \
					"WorldSelection in world_selection group")
				_check(_selection.has_signal("selection_changed"), "WorldSelection exposes selection_changed")
				_check(get_nodes_in_group("world_selection").size() == 1, \
					"exactly 1 WorldSelection node (%d)" % get_nodes_in_group("world_selection").size())
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
				_check(_ui_tavern.visible == false and _ui_inn.visible == false, \
					"modal UIs closed initially")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.SELECT_BUILDINGS)
		Phase.SELECT_BUILDINGS:
			if _sub == 0:
				var sel: Node = _selected_at(TAVERN_POS)
				_check(sel == _tavern_interact, \
					"tavern click selects tavern Interact (got %s)" % str(sel))
				_check(_selected() == _tavern_interact, "selection holds tavern Interact")
				_check(_ui_tavern.visible, "tavern click opens Recruitment UI")
				_sub = 1
			elif _sub == 1:
				# 모달 UI가 열려 있으면 월드 click 차단 (다른 건물 click 안 됨).
				var blocked: Node = _selected_at(INN_POS)
				_check(blocked == null, "world click blocked while modal UI open")
				_check(_selected() == _tavern_interact, "selection unchanged while modal UI open")
				# Right Click으로 선택 해제.
				_selection._unhandled_input(_right_click_event())
				_check(_selected() == null, "right click clears selection")
				_ui_tavern.close()
				_sub = 2
			elif _sub == 2:
				var sel: Node = _selected_at(INN_POS)
				_check(sel == _inn_interact, "inn click selects inn Interact (got %s)" % str(sel))
				_check(_ui_inn.visible, "inn click opens Roster UI")
				_selection._unhandled_input(_esc_event())
				_check(_selected() == null, "ESC clears selection")
				_ui_inn.close()
				_sub = 3
			elif _sub == 3:
				var keep: Node = _world.get_node("Keep/Interact")
				var keep_sel: Node = _selected_at(KEEP_POS)
				_check(keep_sel == keep, "keep click selects keep Interact (got %s)" % str(keep_sel))
				_check(_ui_tavern.visible == false and _ui_inn.visible == false, \
					"keep click opens no modal UI")
				_sub = 4
			elif _sub == 4:
				var grocery: Node = _world.get_node("Grocery/Interact")
				var equip: Node = _world.get_node("EquipmentShop/Interact")
				_check(_selected_at(GROCERY_POS) == grocery, "grocery click selects grocery Interact")
				_check(_selected_at(EQUIPMENT_POS) == equip, "equipment shop click selects equipment Interact")
				_sub = 5
			elif _sub == 5:
				# 빈 땅 / decoration / 나무(자원 노드) click은 interaction 없음 + 선택 유지.
				var current: Node = _selected()
				_check(_selected_at(EMPTY_POS) == null, "empty ground click does not interact")
				_check(_selected() == current, "empty ground click keeps selection")
				_check(_selected_at(DECO0_POS) == null, "decoration click does not interact")
				_check(_selected() == current, "decoration click keeps selection")
				var tree := _world.get_node("Tree1")
				var tree_amount: int = tree.get("current_amount")
				_check(_selected_at(TREE1_POS) == null, "tree click does not select (worker-only resource)")
				_check(tree.get("current_amount") == tree_amount, \
					"tree click does not gather wood (%d)" % tree.get("current_amount"))
				_check(_selected() == current, "tree click keeps selection")
				_sub = 6
			elif _sub == 6:
				_enter(Phase.GATE_LUMBERYARD)
		Phase.GATE_LUMBERYARD:
			if _sub == 0:
				var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
				_lumberyard = ly_scene.instantiate()
				_lumberyard.name = "TestLumberyard"
				_lumberyard.position = LUMBERYARD_POS
				_world.add_child(_lumberyard)
				var qy_scene: PackedScene = load("res://scenes/quarry.tscn")
				_quarry = qy_scene.instantiate()
				_quarry.name = "TestQuarry"
				_quarry.position = QUARRY_POS
				_world.add_child(_quarry)
				_sub = 1
			elif _sub == 1:
				var ly_interact: Node = _lumberyard.get_node("Interact")
				var qy_interact: Node = _quarry.get_node("Interact")
				_check(_selected_at(LUMBERYARD_POS) == ly_interact, \
					"lumberyard click selects lumberyard Interact")
				_check(_selected_at(QUARRY_POS) == qy_interact, \
					"quarry click selects quarry Interact")
				_check(_ui_tavern.visible == false and _ui_inn.visible == false, \
					"lumberyard/quarry click opens no modal UI")
				_sub = 2
			elif _sub == 2:
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = null
				for g in get_nodes_in_group("gates"):
					if is_instance_valid(g) and (g as Node2D).position.distance_to(GATE_POS) < 1.0:
						_gate = g
						break
				_check(_gate != null, "test west gate placed")
				if _gate != null:
					_check(_gate.is_closed(), "gate starts CLOSED")
				_sub = 3
			elif _sub == 3:
				if _gate == null:
					_enter(Phase.GUARDS)
				else:
					var gate_interact: Node = _gate.get_node("Interact")
					var sel: Node = _selected_at(GATE_POS)
					_check(sel == gate_interact, "gate click selects gate Interact (got %s)" % str(sel))
					_check(_gate.is_open(), "gate click toggles CLOSED -> OPEN")
					_check(_selected() == gate_interact, "gate selection retained")
					_enter(Phase.GUARDS)
		Phase.GUARDS:
			if _sub == 0:
				# Build mode 활성 → 월드 click 차단.
				var before: Node = _selected()
				_placement._set_active(true)
				_check(_selection.can_handle_world_click() == false, \
					"world click disabled while build mode active")
				var sel: Node = _selected_at(TAVERN_POS)
				_check(sel == null, "build mode blocks facility selection")
				_check(_selected() == before, "build mode leaves selection unchanged")
				_check(_ui_tavern.visible == false, "build mode click opens no UI")
				_selection._unhandled_input(_left_click_event())
				_check(_selected() == before, "build mode blocks _unhandled_input left click")
				_check(_ui_tavern.visible == false, "build mode left click opens no UI via input")
				_placement._set_active(false)
				_sub = 1
			elif _sub == 1:
				# 모달 UI open → 월드 click 차단.
				_ui_tavern.open()
				_check(_selection.can_handle_world_click() == false, \
					"world click disabled while modal UI open")
				var sel: Node = _selected_at(INN_POS)
				_check(sel == null, "modal UI blocks world click (no click-through)")
				_selection._unhandled_input(_left_click_event())
				_check(_ui_tavern.visible, "modal UI still open after world click (no click-through)")
				_ui_tavern.close()
				_sub = 2
			elif _sub == 2:
				_enter(Phase.NIGHT)
		Phase.NIGHT:
			if _sub == 0:
				_game_time.advance(2.0)
				_sub = 1
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_selection.can_handle_world_click() == false, \
					"world click disabled at NIGHT (tactical UI owns input)")
				var sel: Node = _selected_at(TAVERN_POS)
				_check(sel == null, "NIGHT building click does not open UI")
				_check(_ui_tavern.visible == false, "NIGHT click leaves recruitment UI closed")
				if _gate != null:
					var gate_open_before: bool = _gate.is_open()
					_check(_selected_at(GATE_POS) == null, "NIGHT gate click does not select")
					_check(_gate.is_open() == gate_open_before, \
						"NIGHT gate click does not toggle gate")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(get_nodes_in_group("world_selection").size() == 1, \
					"WorldSelection still present")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, \
					"world floor intact (128x128)")
				_check(_controller != null and _controller.get_camera() != null, \
					"Camera Controller intact (TASK-CTRL-001-1)")
				_check(get_nodes_in_group("player").size() == 0, \
					"no runtime player Actor (player has no combat method)")
				_selection.clear_selection()
				_check(_selection.get_selected() == null, "clear_selection clears at end")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKCTRL0012_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)