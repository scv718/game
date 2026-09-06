extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var settings: Node = root.get_node("GameSettings")
	var original_locale: String = settings.locale
	var original_speed: float = settings.camera_speed_multiplier
	var main: Node = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var camera: Node = main.get_node("CameraController3D")
	_check(camera.min_zoom <= 0.2, "mouse wheel can zoom out to 0.2")
	_check(camera.edge_scroll_direction_for_position(Vector2(1, 360), Vector2(1280, 720)) == Vector2.LEFT,
		"left screen edge pans west only")
	_check(camera.edge_scroll_direction_for_position(Vector2(1279, 360), Vector2(1280, 720)) == Vector2.RIGHT,
		"right screen edge pans east")
	_check(camera.edge_scroll_direction_for_position(Vector2(640, 1), Vector2(1280, 720)) == Vector2.UP,
		"top edge pans north")
	_check(camera.edge_scroll_direction_for_position(Vector2(1279, 719), Vector2(1280, 720)).is_equal_approx(Vector2(1, 1).normalized()),
		"corner edge pan is normalized diagonally")
	var minimap := main.get_node_or_null("HUD/MiniMap3D") as Control
	_check(minimap != null and minimap.visible and minimap.size.x >= 220.0,
		"persistent minimap is visible in HUD")
	var map: Node = main.get_node("WorldMapOverlay/Control")
	map.open()
	await process_frame
	var west: Vector2 = map.world_to_map(Vector2(-WorldCoords3D.WORLD_HALF_UNITS, 0))
	var east: Vector2 = map.world_to_map(Vector2(WorldCoords3D.WORLD_HALF_UNITS, 0))
	_check(west.x >= 0.0 and east.x <= map.size.x and east.x > west.x,
		"expanded 3D world fits inside full map")
	map.close()
	var options: CanvasLayer = main.get_node("OptionsMenu")
	options.open()
	_check(options.is_open() and paused, "ESC options menu can pause gameplay")
	settings.set_camera_speed(1.7)
	_check(is_equal_approx(settings.camera_speed_multiplier, 1.7), "camera speed setting applies")
	settings.set_language("ko")
	_check(options.get_node("Backdrop/Panel/Margin/Column/TitleLabel").text == "옵션",
		"Korean option labels apply immediately")
	_check(main.get_node("HUD/StatusPanel/WoodLabel").text.begins_with("목재"),
		"HUD switches to Korean")
	settings.set_language("en")
	_check(options.get_node("Backdrop/Panel/Margin/Column/TitleLabel").text == "Options",
		"English option labels apply immediately")
	_check(main.get_node("HUD/TacticalCommandUI3D/TacticalPanel/Title").text == "Tactical Command (NIGHT)",
		"English selection translates other gameplay panels")
	options.close()
	_check(not paused, "closing options resumes gameplay")
	settings.set_camera_speed(original_speed)
	settings.set_language(original_locale)
	print("CAMERA_MINIMAP_OPTIONS_3D_RESULT=", "PASS" if failures == 0 else "FAIL")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1
