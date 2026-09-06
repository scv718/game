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
	_check(sprite.texture != null and sprite.texture.get_size() == Vector2(1387, 1134),
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
	var entry_found := false
	for entry in placement.get_building_catalog():
		if entry.asset_name == "Tavern_Pixel":
			entry_found = entry.category == "Pixel Buildings" and entry.complete and entry.cost.wood == 0
	_check(entry_found, "Tavern_Pixel is registered as a free complete pixel building")
	placement._set_building_type("pixel/Tavern_Pixel")
	_check(placement._is_valid_position(Vector3.ZERO), "pixel tavern accepts open clearing")
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
