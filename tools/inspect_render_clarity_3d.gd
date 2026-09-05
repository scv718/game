extends SceneTree

const CITY_SCENE := preload("res://assets/cuteskull-medieval-city/city16.fbx")

func _initialize() -> void:
	var watched := [
		"rendering/scaling_3d/scale",
		"rendering/scaling_3d/mode",
		"rendering/anti_aliasing/quality/msaa_3d",
		"rendering/anti_aliasing/quality/screen_space_aa",
		"rendering/anti_aliasing/quality/use_taa",
		"rendering/textures/default_filters/use_nearest_mipmap_filter",
		"rendering/textures/default_filters/anisotropic_filtering_level",
		"display/window/size/viewport_width",
		"display/window/size/viewport_height",
		"display/window/size/window_width_override",
		"display/window/size/window_height_override",
		"display/window/stretch/mode",
	]
	for key in watched:
		print("SETTING %s=%s explicit=%s" % [key,
			str(ProjectSettings.get_setting(key)), str(ProjectSettings.has_setting(key))])
	print("VIEWPORT size=%s scale3d=%s mode=%s msaa3d=%s ssaa=%s taa=%s mip_bias=%s aniso=%s" % [
		str(root.size), str(root.get("scaling_3d_scale")), str(root.get("scaling_3d_mode")),
		str(root.get("msaa_3d")), str(root.get("screen_space_aa")), str(root.get("use_taa")),
		str(root.get("texture_mipmap_bias")), str(root.get("anisotropic_filtering_level"))])
	_inspect_city_materials()
	quit(0)


func _inspect_city_materials() -> void:
	var city := CITY_SCENE.instantiate()
	for source_name in ["Church_2", "House_3_1", "House_7_1", "House_4_1", "House_5_1", "Ground_1"]:
		var source := _find_named(city, source_name)
		if source == null:
			print("ASSET %s missing" % source_name)
			continue
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(source, meshes)
		for mesh_instance in meshes:
			var mesh := mesh_instance.mesh
			if mesh == null:
				continue
			for surface_index in mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface_index)
				var arrays := mesh.surface_get_arrays(surface_index)
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var uv_bounds := _uv_bounds(uv)
				if material is BaseMaterial3D:
					var base := material as BaseMaterial3D
					var texture := base.albedo_texture
					var texture_size: Vector2i = Vector2i.ZERO if texture == null else texture.get_size()
					var effective := Vector2.ZERO
					if uv_bounds.size() == 4:
						effective = Vector2(texture_size) * Vector2(uv_bounds[2] - uv_bounds[0], uv_bounds[3] - uv_bounds[1])
					print("ASSET %s mesh=%s surface=%d filter=%s texture=%s size=%s uv_bounds=%s effective_bbox_px=%s" % [
						source_name, mesh_instance.name, surface_index, str(base.texture_filter),
						"none" if texture == null else texture.resource_path, str(texture_size), str(uv_bounds), str(effective)])
				else:
					print("ASSET %s mesh=%s surface=%d material=%s uv_bounds=%s" % [
						source_name, mesh_instance.name, surface_index, str(material), str(uv_bounds)])
	city.free()


func _find_named(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, target_name)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


func _uv_bounds(uv: PackedVector2Array) -> PackedFloat32Array:
	if uv.is_empty():
		return PackedFloat32Array()
	var min_uv := uv[0]
	var max_uv := uv[0]
	for point in uv:
		min_uv = min_uv.min(point)
		max_uv = max_uv.max(point)
	return PackedFloat32Array([min_uv.x, min_uv.y, max_uv.x, max_uv.y])
