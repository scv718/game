extends SceneTree

## GPT-3D production layout regression.
## Visual-only assertions: gameplay owners remain the canonical main_3d wiring.

const MAIN_SCENE := "res://scenes/main_3d.tscn"
var _main: Node = null
var _frames := 0
var _failed := false


func _initialize() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	var world := _main.get_node_or_null("World3D")
	var composition := world.get_node_or_null("VillageComposition3D") if world else null
	_check(world != null, "main runtime keeps World3D owner")
	_check(composition != null and composition.is_in_group("village_composition_3d"),
		"main runtime instantiates authored village composition")
	if composition != null:
		for zone in ["village", "forest", "lumberyard", "quarry"]:
			_check(composition.get_zone_root(zone) != null,
				"district '%s' is present" % zone)
		var paths := composition.get_node_or_null("Paths")
		var farm_west_segments := 0
		var farm_east_segments := 0
		if paths != null:
			for path_node in paths.get_children():
				if path_node.name.begins_with("Path_Farm_West_"):
					farm_west_segments += 1
				if path_node.name.begins_with("Path_Farm_East_"):
					farm_east_segments += 1
		_check(farm_west_segments >= 2 and farm_east_segments >= 2,
			"south agriculture branches connect to the road network")
		_check(composition.get_node_or_null("Zone_Village/AgriculturePlot") != null,
			"agriculture plot is readable as a compact south district")
		for fortification in [
			"RawLoafbrrWall_SouthWest", "RawLoafbrrWall_South",
			"RawLoafbrrWall_GateFlankSouth", "RawLoafbrrGate_Arch",
			"RawLoafbrrWall_GateFlankNorth", "RawLoafbrrWall_North",
			"RawLoafbrrWall_NorthEast", "RawCornerTower_South", "RawCornerTower_North",
		]:
			var authored := composition.get_node_or_null(fortification)
			_check(authored != null and authored.get_meta("asset_source", "")
					in ["Loafbrr Castle Wall Kit raw GLTF", "Towers-n-Castles raw GLB"],
				"frontier uses raw imported visual: %s" % fortification)
		_check(composition.get_node_or_null("RawLoafbrrGate_Arch") != null,
			"frontier gate remains a distinct visual landmark")
	for item in [
		{"name": "Keep", "pos": Vector3(0, 0, 0)},
		{"name": "Tavern", "pos": Vector3(-16, 0, -9)},
		{"name": "Inn", "pos": Vector3(16, 0, -9)},
		{"name": "Grocery", "pos": Vector3(-17, 0, 15)},
		{"name": "EquipmentShop", "pos": Vector3(17, 0, 15)},
	]:
		var building := world.get_node_or_null(item["name"])
		_check(building != null and building.position.is_equal_approx(item["pos"]),
			"%s anchors its functional district" % item["name"])
	print("GPT_3D_VILLAGE_LAYOUT_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return true
