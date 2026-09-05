extends SceneTree

const SCENE := "res://scenes/village_composition_3d.tscn"
var _scene_root: Node3D
var _frames := 0
var _failed := false


func _initialize() -> void:
	_scene_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var footprints: Array = []
	for solid in _scene_root.solid_footprints():
		if str(solid.get("key", "")).begins_with("cuteskull/"):
			footprints.append(solid)
	_check(footprints.size() == 11, "all authored house footprints are registered")
	for i in footprints.size():
		for j in range(i + 1, footprints.size()):
			var a: Rect2 = footprints[i].get("rect", Rect2())
			var b: Rect2 = footprints[j].get("rect", Rect2())
			_check(not a.intersects(b, false), "%s does not overlap %s" % [
				footprints[i].get("key", "?"), footprints[j].get("key", "?")])
	_scene_root.free()
	print("VILLAGE_BUILDING_SPACING_RESULT=%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		print("FAIL: " + message)
