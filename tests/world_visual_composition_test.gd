extends SceneTree

var _frames := 0
var _failed := false


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true


func _has_collision_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D:
			return true
		if _has_collision_descendant(child):
			return true
	return false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames != 10:
		return false
	var main := root.get_node_or_null("Main")
	var world := main.get_node_or_null("World") if main != null else null
	var layout := world.get_node_or_null("MapLayout") if world != null else null
	var dressing := world.get_node_or_null("WorldDressing") if world != null else null
	var hud := main.get_node_or_null("HUD") if main != null else null
	var spawner := root.get_node_or_null("FirstEncounterSpawner")

	_check(world != null and layout != null, "world and authored map layout load")
	if world == null or layout == null or hud == null or spawner == null:
		print("RESULT: FAIL")
		quit(1)
		return false
	_check(dressing != null and dressing.get("composition_phase") == 5, "final world dressing phase is active")
	_check(dressing != null and not _has_collision_descendant(dressing), "visual dressing is collision-free")
	_check(layout.MAIN_ROAD_HALF == 28.0, "main road visual width is reduced to 56px")
	_check(layout.is_on_village_path(Vector2.ZERO), "central plaza and village paths are authored")
	_check(layout.get_direction_role("west") == "main_threat_portal", "west is the main threat")
	_check(layout.get_direction_role("north") == "secondary_threat_rift", "north is the secondary threat")
	_check(layout.get_direction_role("east") == "royal_road_exit", "east is the Royal Road")
	_check(layout.get_direction_role("south") == "future_event_threat", "south remains a nonfunctional future slot")
	_check(hud is CanvasLayer and hud.get_node_or_null("StatusPanel") != null, "HUD is viewport-fixed with a status panel")
	_check(hud.get_node_or_null("%DayProgressBar") != null, "HUD has day/night progress")
	_check(spawner.get_direction() == "west", "default encounter enters from west")
	_check(not ("east" in spawner.DIRECTIONS) and not ("south" in spawner.DIRECTIONS), "east and south are not enemy spawn directions")

	print("RESULT: " + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return false
