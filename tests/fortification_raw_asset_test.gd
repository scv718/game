extends SceneTree

const RAW_PATH := "res://assets/LoafbrrAssets/CastleWallKit/gltf/CastleWallsKit.gltf"
const TOWER_PATH := "res://assets/third_party/hakanbacon/towers-n-castles-basics/TowerPackDemo.glb"
var failed := false

func _initialize() -> void:
	var raw := (load(RAW_PATH) as PackedScene).instantiate()
	var tower := (load(TOWER_PATH) as PackedScene).instantiate()
	_check(raw.get_node_or_null("Courtine_Wall") is MeshInstance3D, "raw GLTF straight wall exists")
	_check(raw.get_node_or_null("Courtine_Door_Arch") is MeshInstance3D, "raw GLTF integrated arch exists")
	_check(raw.get_node_or_null("Courtine_Corner_Round") is MeshInstance3D, "raw GLTF corner exists")
	_check(tower.get_node_or_null("WallCornerTower") is MeshInstance3D, "GLB Corner Tower exists")
	_check(tower.get_node_or_null("TowerGateTunnel") is MeshInstance3D, "GLB gate tunnel candidate exists")
	raw.free()
	tower.free()
	print("FORTIFICATION_RAW_ASSET_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func _check(condition: bool, message: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failed = true
