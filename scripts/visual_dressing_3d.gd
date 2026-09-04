extends Node3D
class_name VisualDressing3D

## TASK-3D-VIS-002 Visual Dressing Layer for 3D World.
## Adds paths, vegetation, market props, and fences to complement
## the existing tree/stone spawning in WorldContent3D.
## Based on VillageComposition3D patterns but simplified for runtime use.

const PATH_ALBEDO := Color(0.55, 0.46, 0.34)
const PLAZA_ALBEDO := Color(0.61, 0.52, 0.38)
const FENCE_WOOD := Color(0.42, 0.34, 0.26)

var _spawned := false


func _ready() -> void:
	if _spawned:
		return
	_spawned = true
	_spawn_village_paths()
	_spawn_village_props()
	_spawn_fences()


func _spawn_village_paths() -> void:
	# Main paths as flat strips on the ground
	_spawn_path_strip(Vector3(0, 0, -22), Vector3(0, 0, -6), 2.0)  # North approach
	_spawn_path_strip(Vector3(0, 0, 6), Vector3(0, 0, 22), 2.0)    # South approach
	_spawn_path_strip(Vector3(-22, 0, 0), Vector3(-6, 0, 0), 2.0)  # West approach
	_spawn_path_strip(Vector3(6, 0, 0), Vector3(22, 0, 0), 2.0)    # East approach
	# Plaza
	_spawn_plaza(Vector3(0, 0, 0), 6.0)


func _spawn_path_strip(from: Vector3, to: Vector3, width: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.05, (to - from).length())
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = (from + to) / 2.0
	instance.position.y = 0.02
	# Align strip along the path before adding to tree (look_at requires in-tree).
	instance.look_at_from_position(instance.position, to, Vector3.UP)
	# Disable shadows for path strips
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = PATH_ALBEDO
	material.roughness = 1.0
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)


func _spawn_plaza(center: Vector3, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	instance.position.y = 0.02
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = PLAZA_ALBEDO
	material.roughness = 1.0
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)


func _spawn_village_props() -> void:
	# Market area props (near grocery/equipment buildings)
	_spawn_crate(Vector3(-14, 0, 13), 1.0)
	_spawn_crate(Vector3(-13, 0, 14), 0.8)
	_spawn_barrel(Vector3(15, 0, 11), 0.7)
	_spawn_barrel(Vector3(16, 0, 12), 0.6)
	# Bench near tavern
	_spawn_bench(Vector3(-11, 0, 1), 3.0)
	# Signpost near entrance
	_spawn_sign(Vector3(-10, 0, -6), Vector3.FORWARD)


func _spawn_crate(pos: Vector3, scale: float) -> void:
	var model := VisualAssetCatalog3D.instantiate_model("prop/crate_wooden")
	if model == null:
		return
	model.position = pos
	model.scale = Vector3.ONE * scale
	add_child(model)


func _spawn_barrel(pos: Vector3, scale: float) -> void:
	var model := VisualAssetCatalog3D.instantiate_model("prop/barrel")
	if model == null:
		return
	model.position = pos
	model.scale = Vector3.ONE * scale
	add_child(model)


func _spawn_bench(pos: Vector3, width: float) -> void:
	# No bench model in catalog; use a row of crates as a bench substitute
	for i in [-1, 0, 1]:
		var crate := VisualAssetCatalog3D.instantiate_model("prop/crate_wooden")
		if crate == null:
			return
		crate.position = pos + Vector3(i * (width / 3.0), 0, 0)
		crate.scale = Vector3.ONE * 0.5
		add_child(crate)


func _spawn_sign(pos: Vector3, direction: Vector3) -> void:
	# No dedicated sign model; use a stall as market signage
	var model := VisualAssetCatalog3D.instantiate_model("prop/stall_empty")
	if model == null:
		return
	model.position = pos
	model.scale = Vector3.ONE * 0.6
	add_child(model)


func _spawn_fences() -> void:
	# Village perimeter fences (simplified crate lines)
	_spawn_fence_line(Vector3(-18, 0, -12), Vector3(-10, 0, -12), 3)
	_spawn_fence_line(Vector3(10, 0, -12), Vector3(18, 0, -12), 3)
	_spawn_fence_line(Vector3(-17, 0, 17), Vector3(-7, 0, 17), 4)
	_spawn_fence_line(Vector3(7, 0, 17), Vector3(17, 0, 17), 4)


func _spawn_fence_line(from: Vector3, to: Vector3, sections: int) -> void:
	var direction := (to - from).normalized()
	var length := (to - from).length()
	for i in range(sections + 1):
		var pos := from + direction * (length * i / sections)
		_spawn_crate(pos, 0.5)
