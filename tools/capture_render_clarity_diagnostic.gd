extends SceneTree

var main: Node
var controller: Node
var camera: Camera3D
var frame := 0
var material_overrides: Array[Dictionary] = []
var ground_material: StandardMaterial3D

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	main = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _save(name: String) -> void:
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(ProjectSettings.globalize_path("res://test_results/" + name))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 12:
		controller = get_first_node_in_group("camera_controller_3d")
		camera = controller.get_camera()
		controller.set_process(false)
		controller.position = Vector3(3, WorldCoords3D.GROUND_Y, 0)
		camera.size = 70.0
	if frame == 18:
		_save("clarity_01_baseline.png")
		root.set("scaling_3d_scale", 1.0)
	if frame == 24:
		_save("clarity_02_scale_1.png")
		root.set("msaa_3d", 0)
		root.set("screen_space_aa", 0)
		root.set("use_taa", false)
	if frame == 30:
		_save("clarity_03_aa_off.png")
		root.set("anisotropic_filtering_level", 4)
	if frame == 36:
		_save("clarity_04_anisotropic_16x.png")
		root.set("texture_mipmap_bias", -0.5)
	if frame == 42:
		_save("clarity_05_mip_bias_minus_05.png")
		root.set("anisotropic_filtering_level", 2)
		root.set("texture_mipmap_bias", 0.0)
	if frame == 48:
		_save("clarity_06_filter_linear_mipmaps.png")
		_set_world_texture_filter(BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	if frame == 54:
		_save("clarity_07_filter_linear_no_mipmaps.png")
		_restore_world_texture_filters()
		ground_material = _find_ground_material(main)
	if frame == 60:
		_save("clarity_08_ground_uv4.png")
		if ground_material != null:
			ground_material.uv1_scale = Vector3(16.0, 16.0, 16.0)
	if frame == 66:
		_save("clarity_09_ground_uv16.png")
		if ground_material != null:
			ground_material.uv1_scale = Vector3(4.0, 4.0, 4.0)
		root.set("anisotropic_filtering_level", 4)
		_set_world_texture_filter(BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
	if frame == 72:
		_save("clarity_10_material_anisotropic_16x.png")
		_restore_world_texture_filters()
		quit(0)
		return true
	return false


func _set_world_texture_filter(filter: BaseMaterial3D.TextureFilter) -> void:
	material_overrides.clear()
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.name != "GroundVisual":
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface_index in mesh_instance.mesh.get_surface_count():
					var source: Material = mesh_instance.get_active_material(surface_index)
					if source is BaseMaterial3D and (source as BaseMaterial3D).albedo_texture != null:
						material_overrides.append({
							"mesh": mesh_instance,
							"surface": surface_index,
							"original": mesh_instance.get_surface_override_material(surface_index),
						})
						var comparison := source.duplicate() as BaseMaterial3D
						comparison.texture_filter = filter
						mesh_instance.set_surface_override_material(surface_index, comparison)
		stack.append_array(node.get_children())


func _restore_world_texture_filters() -> void:
	for entry in material_overrides:
		(entry.mesh as MeshInstance3D).set_surface_override_material(entry.surface, entry.original)
	material_overrides.clear()


func _find_ground_material(node: Node) -> StandardMaterial3D:
	if node is MeshInstance3D and node.name == "GroundVisual":
		var material := (node as MeshInstance3D).material_override
		if material is StandardMaterial3D:
			return material as StandardMaterial3D
	for child in node.get_children():
		var found := _find_ground_material(child)
		if found != null:
			return found
	return null
