extends SceneTree

## TASK-3D-VIS-001-1 Quatenius 諛섏엯 ?먯뀑 ?뚮뜑 ?꾨━酉?罹≪쿂.
## tools/capture_resources_3d.gd? ?숈씪??理쒖냼 援ъ꽦(world3d + ?꾩떆 議곕챸/?섍꼍,
## camera_controller_3d ?ъ궗???쇰줈 catalog ???紐⑤뜽??諛곗튂??罹≪쿂?쒕떎.
## 誘멸컧 ?먮떒???꾨땲??"import臾쇱씠 ?ㅼ젣濡??띿뒪泥??ъ쭏怨??④퍡 ?뚮뜑?섎뒗媛"??## 利앷굅 ?ъ쭊?대떎(VIS-001-3/-5媛 理쒖쥌 environment/誘멸컧???뚯쑀).
##
## Example:
## Godot --path . --script res://tools/capture_quaternius_preview.gd -- --output=res://test_results/quaternius_import_preview.png

var _frames := 0
var _output := "res://test_results/quaternius_import_preview.png"
var _world: Node3D = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	root.add_child(world_scene)
	_world = world_scene
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	_place_models()


## catalog ?ㅻ쭔 ?ъ슜?댁꽌 ???紐⑤뜽??諛곗튂?쒕떎(Scene -> ?뚯씪 寃쎈줈 吏곸젒 李몄“ ?놁쓬).
func _place_models() -> void:
	var catalog := load("res://scripts/visual_asset_catalog_3d.gd")
	var layout := {
		"tree/common_1": Vector3(-6, 0, -4),
		"tree/pine_2": Vector3(-9, 0, 2),
		"rock/medium_1": Vector3(-4, 0, 3),
		"veg/bush_common": Vector3(-6.5, 0, 1),
		"veg/grass_common_tall": Vector3(-5, 0, -1),
		"bld/wall_plaster_straight": Vector3(2, 0, -2),
		"bld/wall_plaster_window_wide": Vector3(4, 0, -2),
		"bld/wall_plaster_door_flat": Vector3(6, 0, -2),
		"bld/chimney": Vector3(7, 0, -3),
		"prop/barrel": Vector3(2.8, 0, -0.8),
		"prop/crate_wooden": Vector3(7, 0, -0.6),
		"tool/anvil": Vector3(4.6, 0, 0.2),
		"human/male_base": Vector3(0.5, 0, 2),
		"outfit/male_ranger_full": Vector3(2, 0, 2),
	}
	for key in layout:
		var node: Node3D = catalog.instantiate_model(key)
		if node == null:
			push_error("preview model failed to instantiate: %s" % key)
			continue
		node.position = WorldCoords3D.flatten(layout[key])
		_world.add_child(node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		var cam_ctl := root.get_node_or_null("CamController")
		if cam_ctl != null:
			var zoom := 3.0
			cam_ctl.day_zoom = zoom
			cam_ctl._zoom_target = zoom
			cam_ctl.get_camera().size = cam_ctl._ortho_size_for_zoom(zoom)
			cam_ctl.position = Vector3(0.0, 0.0, 0.0)
	if _frames == 45:
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
