extends SceneTree

var _failures := 0


func _init() -> void:
	var packed := load("res://scenes/main_3d.tscn") as PackedScene
	_check(packed != null, "main 3D scene loads")
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	var world := main.get_node_or_null("World3D")
	_check(world != null, "main world remains present")
	_check(main.get_node_or_null("World3D/Keep") == null,
		"automatic Keep is removed from the empty map")
	_check(main.get_node_or_null("World3D/VillageComposition3D") == null,
		"automatic village composition is removed from the empty map")
	_check(main.get_node_or_null("World3D/WorldContent3D").grass_only,
		"world content runs in grass-only mode")
	_check(world.get_node_or_null("GroundVisual") != null,
		"grass ground visual remains")
	main.free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("GRASS_ONLY_WORLD_RESULT=%s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)
