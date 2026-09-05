extends SceneTree

const CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const OUTPUT_DIR := "res://resources/terrain/cuteskull_ground/"
const SOURCES := [
	"Grass_1", "Grass_2", "Ground_1", "Ground_2", "Ground_3", "City_Ground",
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var city := CITY.instantiate()
	for source_name in SOURCES:
		var source := _find_named(city, source_name)
		var mesh_instance := _first_mesh(source)
		if mesh_instance == null or mesh_instance.mesh == null:
			push_error("Missing mesh for %s" % source_name)
			continue
		var arrays := mesh_instance.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bounds := _uv_bounds(uv)
		var material := mesh_instance.get_active_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null:
			push_error("Missing albedo for %s" % source_name)
			continue
		var atlas := material.albedo_texture.get_image()
		if atlas.is_compressed():
			atlas.decompress()
		var x := clampi(floori(bounds.position.x * atlas.get_width()), 0, atlas.get_width() - 1)
		var y := clampi(floori(bounds.position.y * atlas.get_height()), 0, atlas.get_height() - 1)
		var right := clampi(ceili(bounds.end.x * atlas.get_width()), x + 1, atlas.get_width())
		var bottom := clampi(ceili(bounds.end.y * atlas.get_height()), y + 1, atlas.get_height())
		var crop := atlas.get_region(Rect2i(x, y, right - x, bottom - y))
		var output: String = OUTPUT_DIR + source_name.to_snake_case() + ".png"
		var error: Error = crop.save_png(ProjectSettings.globalize_path(output))
		print("EXTRACT %s texture=%s uv=%s px=%s output=%s error=%s" % [
			source_name, material.albedo_texture.resource_path, bounds,
			Rect2i(x, y, right - x, bottom - y), output, error])
	city.free()
	quit(0)


func _find_named(node: Node, target: String) -> Node:
	if node != null and node.name == target:
		return node
	if node != null:
		for child in node.get_children():
			var found := _find_named(child, target)
			if found != null:
				return found
	return null


func _first_mesh(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _uv_bounds(uv: PackedVector2Array) -> Rect2:
	var min_uv := uv[0]
	var max_uv := uv[0]
	for point in uv:
		min_uv = min_uv.min(point)
		max_uv = max_uv.max(point)
	return Rect2(min_uv, max_uv - min_uv)
