extends SceneTree

## Deterministic visual QA capture for the authored world composition.
## Example:
## Godot --path . --script res://tools/capture_world.gd -- --output=res://test_results/world.png

var _frames := 0
var _output := "res://test_results/world_visual.png"
var _night := false
var _zoom := 0.9
var _window_size := Vector2i(1840, 1076)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg == "--night":
			_night = true
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--size="):
			var pieces := arg.trim_prefix("--size=").split("x")
			if pieces.size() == 2:
				_window_size = Vector2i(int(pieces[0]), int(pieces[1]))
	root.size = _window_size
	var game_time := root.get_node("GameTime")
	game_time.set_auto_advance(false)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		## TASK-CTRL-001-1: Camera2D는 Player가 아니라 World Camera Controller가 소유한다.
		var ctrls := get_nodes_in_group("camera_controller")
		var controller: Node = ctrls[0] if ctrls.size() > 0 else null
		var camera := controller.get_camera() as Camera2D if controller else null
		if camera != null:
			camera.zoom = Vector2(_zoom, _zoom)
		if _night:
			var game_time := root.get_node("GameTime")
			game_time.advance(game_time.day_duration + 0.01)
	if _frames == 40:
		var absolute := ProjectSettings.globalize_path(_output)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var image := root.get_texture().get_image()
		var error := image.save_png(absolute)
		if error != OK:
			push_error("screenshot save failed: %d" % error)
			quit(1)
			return false
		print("CAPTURED " + absolute + " size=" + str(image.get_size()))
		quit()
	return false
