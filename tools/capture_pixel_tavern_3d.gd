extends SceneTree


const OUTPUT_RUNTIME := "res://test_results/pixel_buildings_runtime.png"
const OUTPUT_CATALOG := "res://test_results/pixel_buildings_catalog.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var main: Node3D = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _frame in range(240):
		await process_frame

	var camera_controller: Node3D = main.get_node("CameraController3D")
	camera_controller.position = Vector3.ZERO
	camera_controller.day_zoom = 1.5
	camera_controller._zoom_target = 1.5
	camera_controller.get_camera().size = camera_controller._ortho_size_for_zoom(1.5)

	var placement: Node = main.get_node("BuildingPlacement3D")
	placement._set_building_type("pixel/Keep")
	placement._try_place_at(Vector3.ZERO)
	for _frame in range(10):
		await process_frame
	_save(OUTPUT_RUNTIME)

	placement._toggle_catalog()
	for _frame in range(10):
		await process_frame
	_save(OUTPUT_CATALOG)

	main.queue_free()
	await process_frame
	quit()


func _save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := root.get_texture().get_image().save_png(absolute)
	if error != OK:
		push_error("Screenshot save failed: %s" % error_string(error))
		quit(1)
		return
	print("CAPTURE=", path, " RESULT=", error_string(error))
