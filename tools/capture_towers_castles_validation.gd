extends SceneTree

func _init() -> void:
	var root: Node3D = load("res://scripts/fortification_asset_validation_3d.gd").new()
	root.name = "TowersCastlesValidation3D"
	root.set("capture_path", "res://test_results/towers_castles_validation.png")
	get_root().add_child(root)
