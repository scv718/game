extends SceneTree

const ZOO_SCENE := "res://scenes/castle_wall_asset_zoo_3d.tscn"
var _zoo: Node
var _failed := false


func _initialize() -> void:
	_zoo = (load(ZOO_SCENE) as PackedScene).instantiate()
	root.add_child(_zoo)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true


func _process(_delta: float) -> bool:
	_check(_zoo != null, "asset zoo scene instantiates")
	if _zoo != null:
		_check(_zoo.get_entry_count() == 116,
			"all 116 authored Castle Wall Kit scenes are discovered")
		_check(_zoo.get_page_count() == 4,
			"candidate inventory is split into four readable grid pages")
		for page in _zoo.get_page_count():
			_zoo.build_page(page)
		_check(_zoo.get_node_or_null("AssetPage_04") != null,
			"final inventory page can instantiate")
	print("CASTLE_WALL_ASSET_ZOO_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return true
