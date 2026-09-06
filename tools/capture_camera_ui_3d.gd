extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var main: Node = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(main)
	for _frame in range(240):
		await process_frame
	_save("res://test_results/camera_minimap_runtime.png")
	var options: CanvasLayer = main.get_node("OptionsMenu")
	options.open()
	for _frame in range(5):
		await process_frame
	_save("res://test_results/options_language_runtime.png")
	options.close()
	var map: Node = main.get_node("WorldMapOverlay/Control")
	map.open()
	for _frame in range(5):
		await process_frame
	_save("res://test_results/world_map_expanded_runtime.png")
	map.close()
	main.queue_free()
	await process_frame
	quit()


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE=", path, " RESULT=", error_string(error))
