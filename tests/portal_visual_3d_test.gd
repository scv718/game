extends SceneTree

const SCENE := "res://scenes/village_composition_3d.tscn"
var _root: Node3D
var _main: Node
var _frames := 0
var _failed := false


func _initialize() -> void:
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_root)
	_main = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var portal := _root.get_node_or_null("DistantPortal") as Node3D
	_check(portal != null, "distant abyss portal exists")
	_check(_main.get_node_or_null("World3D/WorldContent3D/DistantPortal") != null,
		"distant abyss portal is wired into the canonical main runtime")
	if portal != null:
		_check(portal.get_node_or_null("AbyssCore") != null, "black abyss core exists")
		_check(portal.get_node_or_null("UnstablePurpleHalo") != null,
			"purple unstable halo exists")
		_check(portal.get_node_or_null("RiftDistortionEdge") != null,
			"rift distortion edge exists")
		_check(portal.get_node_or_null("AbyssAmbientLight") != null,
			"portal atmospheric light exists")
		var core := portal.get_node("AbyssCore") as MeshInstance3D
		var box := core.get_aabb()
		_check(box.position.y >= -0.01 and box.end.y > 20.0,
			"core geometry is an above-horizon half disc")
		var has_collision := false
		for child in portal.get_children():
			if child is CollisionObject3D:
				has_collision = true
		_check(not has_collision, "portal remains visual-only without gameplay collision")
	_root.free()
	print("PORTAL_VISUAL_3D_RESULT=%s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		print("FAIL: " + message)
