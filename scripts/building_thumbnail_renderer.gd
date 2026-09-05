extends Node
class_name BuildingThumbnailRenderer

## Runtime thumbnail renderer for the same extracted Cuteskull nodes used by placement.
## Each asset gets one 256x256 SubViewport rendered once, then its texture is cached.

const SIZE := 256
const MODEL_SCALE := 0.17
const SOURCE_PATH := "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/"

var _city_scene: PackedScene
var _textures: Dictionary = {}
var _viewports: Dictionary = {}


func configure(city_scene: PackedScene) -> void:
	_city_scene = city_scene


func get_thumbnail(asset_name: String) -> Texture2D:
	if _textures.has(asset_name):
		return _textures[asset_name]
	var texture := _create_thumbnail(asset_name)
	if texture == null:
		push_error("BuildingThumbnailRenderer: failed preview for '%s'" % asset_name)
		return null
	_textures[asset_name] = texture
	return texture


func cached_thumbnail_count() -> int:
	return _textures.size()


func has_thumbnail(asset_name: String) -> bool:
	return _textures.has(asset_name)


func _create_thumbnail(asset_name: String) -> Texture2D:
	if _city_scene == null:
		return null
	var source_root := _city_scene.instantiate()
	var source := source_root.get_node_or_null(SOURCE_PATH + asset_name) as Node3D
	if source == null:
		source_root.free()
		return null
	var model := source.duplicate() as Node3D
	model.name = "Thumbnail_%s" % asset_name
	model.scale = Vector3.ONE * MODEL_SCALE
	_normalize(model)
	model.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	source_root.free()

	var viewport := SubViewport.new()
	viewport.name = "ThumbnailViewport_%s" % asset_name
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	add_child(viewport)
	_viewports[asset_name] = viewport

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#263229")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.70)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	viewport.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	viewport.add_child(light)

	var root := Node3D.new()
	root.name = "ThumbnailWorld"
	viewport.add_child(root)
	root.add_child(model)

	var bounds := _visual_aabb(model)
	if bounds.size.length_squared() <= 0.0001:
		push_error("BuildingThumbnailRenderer: empty visual AABB for '%s'" % asset_name)
		return null
	var center := bounds.position + bounds.size * 0.5
	var radius := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(radius * 1.32, 1.0)
	camera.position = center + Vector3(radius * 1.15, radius * 0.95, radius * 1.15)
	camera.look_at_from_position(camera.position, center, Vector3.UP)
	viewport.add_child(camera)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return viewport.get_texture()


func _normalize(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return


func _visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	var bounds := _collect_visual_aabb(root, Transform3D.IDENTITY)
	result = bounds.get("aabb", AABB())
	return result


func _collect_visual_aabb(node: Node, parent_transform: Transform3D) -> Dictionary:
	var result := AABB()
	var has_bounds := false
	var current := parent_transform
	if node is Node3D:
		current = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		for corner in _aabb_corners((node as MeshInstance3D).mesh.get_aabb()):
			var point: Vector3 = current * corner
			if not has_bounds:
				result = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				result = result.expand(point)
	for child in node.get_children():
		var child_bounds := _collect_visual_aabb(child, current)
		if child_bounds.get("valid", false):
			if not has_bounds:
				result = child_bounds.aabb
				has_bounds = true
			else:
				result = result.merge(child_bounds.aabb)
	return {"aabb": result, "valid": has_bounds}


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p, p + Vector3(s.x, 0, 0), p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z), p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z), p + Vector3(0, s.y, s.z), p + s,
	]
