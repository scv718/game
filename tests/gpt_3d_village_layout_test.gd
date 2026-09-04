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
			"CuteskullWall_SouthWest", "CuteskullWall_South",
			"CuteskullWall_GateFlankSouth", "CuteskullMainGate",
			"CuteskullWall_GateFlankNorth", "CuteskullWall_North",
			"CuteskullWall_NorthEast", "CuteskullTower_South", "CuteskullTower_North",
		]:
			var authored := composition.get_node_or_null(fortification)
			_check(authored != null and authored.get_meta("asset_source", "")
					== "Cuteskull city16.fbx",
				"frontier uses coherent Cuteskull visual: %s" % fortification)
		_check(composition.get_node_or_null("CuteskullMainGate") != null,
			"frontier gate remains a distinct visual landmark")
	var buildings: Array[Node3D] = []
	for building_name in ["Keep", "Tavern", "Inn", "Grocery", "EquipmentShop"]:
		var building := world.get_node_or_null(building_name) as Node3D
		_check(building != null, "%s gameplay owner remains present" % building_name)
		if building != null:
			buildings.append(building)
	var keep := world.get_node_or_null("Keep") as Node3D
	if keep != null:
		for building in buildings:
			if building != keep:
				_check(keep.position.distance_to(building.position) >= 10.0,
					"Keep has landmark clearance from %s" % building.name)
	var gate := composition.get_node_or_null("CuteskullMainGate") as Node3D \
		if composition != null else null
	if gate != null:
		for building in buildings:
			_check(gate.position.distance_to(building.position) >= 12.0,
				"gate staging area stays clear of %s" % building.name)
	print("GPT_3D_VILLAGE_LAYOUT_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
	return true
