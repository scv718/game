extends SceneTree

var _frame := 0
var _pf := 0
var _placement: Node = null
var _controller: Node = null
var _world: Node = null
var _did := false
var _did2 := false

func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	if not _did:
		_did = true
		_placement = root.get_node("Main").get_node("BuildingPlacement")
		_controller = get_nodes_in_group("camera_controller")[0]
		_world = root.get_node("Main").get_node("World")
		var vp := root.get_viewport()
		print("viewport size=", vp.get_visible_rect().size, " mouse=", vp.get_mouse_position())
		print("canvas_transform=", vp.get_canvas_transform())
		var gmp0: Vector2 = _placement.get_global_mouse_position()
		print("gmp at camera(0,0): ", gmp0)
		_controller.global_position = Vector2(96, -64)
		print("gmp after pan (same frame): ", _placement.get_global_mouse_position())
		print("camera pos: ", _controller.global_position)
		return false
	if not _did2 and _frame > 12:
		_did2 = true
		print("gmp after pan (next frame): ", _placement.get_global_mouse_position())
		print("canvas_transform after pan: ", root.get_viewport().get_canvas_transform())
		# barrier test
		root.get_node("VillageResources")._amounts["wood"] = 10000
		for x in range(32, 128, 16):
			_placement._try_place_wall_at(Vector2(x, -200))
		print("walls count: ", get_nodes_in_group("walls").size())
		for n in get_nodes_in_group("walls"):
			print("  wall at ", (n as Node2D).position)
		_pf = 0
		return false
	if _pf >= 30:
		var direct := (Vector2(56, -170) - Vector2(56, -230)).length()
		var pl := _path_len(Vector2(56, -170), Vector2(56, -230))
		print("direct=", direct, " path=", pl)
		quit()
		return true
	return false

func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)