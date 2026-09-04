extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	failed = failed or not ok

func _initialize() -> void:
	var packed := load("res://scenes/main_3d.tscn") as PackedScene
	check(packed != null, "canonical 3D main scene loads")
	var main := packed.instantiate() if packed != null else null
	if main != null:
		root.add_child(main)
	check(main != null and main.get_node_or_null("GhostSpawnMix") != null,
		"main scene owns one generalized GhostSpawnMix")
	check(main == null or main.get_node_or_null("GhostSpawner3D") == null,
		"superseded duplicate GhostSpawner owner is absent")
	var ghost_scene := load("res://scenes/ghost_3d.tscn") as PackedScene
	var ghost := ghost_scene.instantiate() if ghost_scene != null else null
	check(ghost != null and ghost.has_method("setup_ghost"), "ghost combat actor scene is instantiable")
	check(get_nodes_in_group("player").is_empty(), "no direct player combat actor exists")
	if ghost != null:
		ghost.free()
	if main != null:
		main.free()
	print("TASK0173_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
