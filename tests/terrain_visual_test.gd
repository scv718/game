extends SceneTree

var failed := false


func _initialize() -> void:
	var packed := load("res://scenes/main_3d.tscn") as PackedScene
	_check(packed != null, "main 3D scene loads")
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var composition := get_first_node_in_group("village_composition_3d")
	_check(composition != null, "village terrain owner is present")
	if composition != null:
		var terrain := composition.get_node_or_null("TerrainVisual")
		_check(terrain != null, "visual terrain is separated from gameplay Ground")
		_check(terrain != null and terrain.get_child_count() >= 18,
			"terrain hierarchy contains layered regional patches")
		for required_name in ["GateStagingWear", "WornVillageCore", "FarmSoilWest",
				"QuarryMutedGround", "BattlefieldDryNear", "PortalCorruptionCore"]:
			_check(terrain != null and terrain.get_node_or_null(required_name) != null,
				"terrain region exists: %s" % required_name)
		var paths := composition.get_node_or_null("Paths")
		var box_road_found := false
		if paths != null:
			for child in paths.get_children():
				if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
					box_road_found = true
		_check(paths != null and paths.get_child_count() >= 20,
			"curved road network includes center and transition layers")
		_check(not box_road_found, "road network uses no BoxMesh strips")
	var world := main.get_node_or_null("World3D")
	var gameplay_ground := world.get_node_or_null("Ground") if world != null else null
	_check(gameplay_ground is StaticBody3D,
		"gameplay collision Ground remains separate and unchanged")
	main.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failed = true
		push_error("FAIL: " + message)


func _finish() -> void:
	print("TERRAIN_VISUAL_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
