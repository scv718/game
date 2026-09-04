extends SceneTree

func _init() -> void:
	var root: Node3D = load("res://scripts/fortification_asset_validation_3d.gd").new()
	root.name = "FortificationAssetValidation3D"
	root.set("capture_path", "res://test_results/fortification_raw_gltf_validation.png")
	get_root().add_child(root)
