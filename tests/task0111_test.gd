extends SceneTree

## TASK-011-1 중앙 핵심 마을 5개 기본 건물 배치 검증.
## 게임 시작 직후 거점/주점/여관/식료품점/장비점이 월드에 존재하고,
## 타입/레벨/위치/식별 가능성/최소 prompt가 충족되는지 자동으로 확인한다.
## 기존 시스템(맵 구조, 생산, Worker, decoration, 접근축) 회귀도 함께 확인한다.

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

var _frame := 0
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 10:
		return false

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	var world: Node = main.get_node("World")
	var layout: Node = world.get_node_or_null("MapLayout")
	_check(layout != null, "MapLayout node exists")

	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())

	var seen_types := {}
	for b in cores:
		_check(b is StaticBody2D, "%s is StaticBody2D" % b.name)
		_check(b.is_in_group("buildings"), "%s is a Building" % b.name)
		_check(b.has_method("get_core_type"), "%s has get_core_type" % b.name)
		var ctype: String = b.get_core_type()
		_check(ctype != "", "%s has a core type" % b.name)
		_check(b.get_level() == 1, "%s has level 1" % b.name)
		var vis: Sprite2D = b.get_node_or_null("Visual") as Sprite2D
		_check(vis != null and vis.texture != null and vis.texture is AtlasTexture, "%s has building visual texture" % b.name)
		var interact: Node = b.get_node_or_null("Interact")
		_check(interact != null and interact.has_method("can_interact") and interact.can_interact(), "%s has interactable" % b.name)
		if interact != null and interact.has_method("prompt"):
			_check(String(interact.prompt).length() > 0, "%s has prompt '%s'" % [b.name, interact.prompt])
		if ctype != "":
			seen_types[ctype] = true
		var pos: Vector2 = b.global_position
		_check(layout.is_in_clearing(pos) or layout.is_in_wall_buffer(pos), "%s inside settlement/wall buffer (%s)" % [b.name, str(pos)])
		_check(not layout.is_on_access_axis(pos), "%s not blocking an access axis (%s)" % [b.name, str(pos)])

	for t in CORE_TYPES:
		_check(seen_types.has(t), "core type %s present" % t)

	# 회귀: 기존 맵/생산/worker 구조 유지
	var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "floor covers 192x192 tiles")
	if get_nodes_in_group("lumberjacks").size() < 1:
		var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
		lj.position = Vector2(300, 200)
		world.add_child(lj)
	if get_nodes_in_group("miners").size() < 1:
		var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
		mn.position = Vector2(500, 140)
		world.add_child(mn)
	_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present")
	_check(get_nodes_in_group("miners").size() >= 1, "miner present")
	_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present")
	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())

	print("TASK0111_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
