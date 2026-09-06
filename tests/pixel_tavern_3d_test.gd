extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var tavern_scene := load("res://scenes/pixel_tavern_3d.tscn") as PackedScene
	_check(tavern_scene != null, "pixel tavern scene loads")
	var sample := tavern_scene.instantiate() as StaticBody3D
	var sprite := sample.get_node("Sprite3D") as Sprite3D
	var shape := sample.get_node("CollisionShape3D") as CollisionShape3D
	_check(sprite.texture != null and sprite.texture.get_size() == Vector2(1254, 1254),
		"source PNG imports at original resolution")
	_check(sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
		"pixel art uses nearest texture filtering")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"2.5D tavern faces the gameplay camera")
	_check(shape.shape is BoxShape3D and shape.shape.size == Vector3(17, 4, 10),
		"tavern has independent 3D gameplay footprint")
	sample.free()
	var main: Node = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var placement: Node = main.get_node("BuildingPlacement3D")
	var build_key := InputEventKey.new()
	build_key.physical_keycode = KEY_B
	build_key.pressed = true
	placement._unhandled_input(build_key)
	_check(placement.is_catalog_open(), "B key opens the building catalog")
	placement._toggle_catalog()
	var entry_found := false
	var pixel_names := {}
	for entry in placement.get_building_catalog():
		if entry.category == "Pixel Buildings":
			pixel_names[entry.asset_name] = true
			if entry.asset_name == "Tavern":
				entry_found = entry.complete and entry.cost.wood == 0
	_check(entry_found and pixel_names.has("Blacksmith") and pixel_names.has("Inn") and pixel_names.has("Keep"),
		"pixel building catalog contains all four rotated building sets")
	placement._set_building_type("pixel/Tavern")
	_check(placement._is_valid_position(Vector3.ZERO), "pixel tavern accepts open clearing")
	var front_texture: Texture2D = placement._pixel_texture("Tavern", 0)
	var side_texture: Texture2D = placement._pixel_texture("Tavern", 1)
	_check(front_texture != side_texture, "R rotation selects a different pixel facade")
	placement._try_place_at(Vector3.ZERO)
	await physics_frame
	var placed := get_nodes_in_group("pixel_buildings_3d")
	_check(placed.size() == 1, "catalog placement spawns one pixel tavern")
	_check(not placement._is_valid_position(Vector3.ZERO), "pixel tavern blocks overlapping construction")
	print("PIXEL_TAVERN_3D_RESULT=", "PASS" if failures == 0 else "FAIL")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1
