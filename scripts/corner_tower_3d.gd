extends Node3D
class_name CornerTower3D

const SOURCE := "res://assets/third_party/hakanbacon/towers-n-castles-basics/TowerPackDemo.glb"
const SOURCE_NODE := "WallCornerTower"

func _ready() -> void:
	var pack := (load(SOURCE) as PackedScene).instantiate()
	var source := pack.get_node_or_null(SOURCE_NODE) as MeshInstance3D
	if source == null:
		push_error("CornerTower3D: missing source node %s" % SOURCE_NODE)
		pack.free()
		return
	var model := source.duplicate() as MeshInstance3D
	model.name = "WallCornerTowerRaw"
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	model.set_meta("asset_source", SOURCE)
	model.set_meta("source_node", SOURCE_NODE)
	model.set_meta("kind", "visual_fortification")
	add_child(model)
	pack.free()
