extends SceneTree

## TASK-008-1 맵 골격 + TASK-008-2 Tiny Swords terrain/도로/자연 배치 생성기.
## scenes/world.tscn 을 128x128 논리 타일의 유한 수제 오버월드로 재생성한다.
## 실행: Godot --headless --path . --script res://tools/generate_world_map.gd
## (생성 결과는 scenes/world.tscn 에 저장되며, 레이아웃 정의는 scripts/world_map.gd 참고)

const GRASS_TEXTURE := "res://assets/tiny_swords/generated/grass_tile.png"
const PATH_TEXTURE := "res://assets/tiny_swords/generated/path_tile.png"
const TREE_SCENE := "res://scenes/tree.tscn"
const DEPOSIT_SCENE := "res://scenes/stone_deposit.tscn"
const DECORATION_SCENE := "res://scenes/decoration.tscn"
const CORE_SCENE := "res://scenes/core_building.tscn"
const WORLD_MAP_SCRIPT := "res://scripts/world_map.gd"
const OUT_PATH := "res://scenes/world.tscn"

const WALL_THICKNESS := 64.0

const AXIS_MIDPOINTS := {
	"north": Vector2(0, -540.0),
	"south": Vector2(0, 540.0),
	"east": Vector2(540.0, 0),
	"west": Vector2(-540.0, 0),
}

# 중앙 핵심 마을 5개 건물 (TASK-011-1 / TASK-012-1 재배치 좌표).
const CORE_BUILDINGS := {
	"Keep": {"pos": Vector2(0, -150), "core_type": "keep"},
	"Tavern": {"pos": Vector2(-150, -60), "core_type": "tavern"},
	"Inn": {"pos": Vector2(150, -60), "core_type": "inn"},
	"Grocery": {"pos": Vector2(-145, 120), "core_type": "grocery"},
	"EquipmentShop": {"pos": Vector2(145, 120), "core_type": "equipment"},
}


func _initialize() -> void:
	var wm_script: GDScript = load(WORLD_MAP_SCRIPT)
	var tile_size: int = wm_script.TILE_SIZE
	var map_tiles: int = wm_script.MAP_TILES
	var half: int = map_tiles / 2
	var cell_min := -half
	var cell_max := half - 1
	var world_size: int = map_tiles * tile_size
	var world_half: int = world_size / 2

	var world := Node2D.new()
	world.name = "World"
	world.set_script(load("res://scripts/world.gd"))

	var wm: Node = wm_script.new()
	world.add_child(_make_floor(tile_size, cell_min, cell_max, wm))
	world.add_child(_make_layout(wm_script))
	_add_walls(world, world_size, world_half)
	_add_entities(world, wm_script)
	wm.free()

	var nav := NavigationRegion2D.new()
	nav.name = "NavigationRegion2D"
	world.add_child(nav)

	_set_owner_recursive(world, world)

	var packed := PackedScene.new()
	var perr := packed.pack(world)
	if perr != OK:
		push_error("pack failed: %d" % perr)
		quit(1)
		return
	var serr := ResourceSaver.save(packed, OUT_PATH)
	if serr != OK:
		push_error("save failed: %d" % serr)
		quit(1)
		return
	print("WROTE " + OUT_PATH + " cells=" + str(map_tiles * map_tiles) + " size=" + str(world_size))
	world.free()
	quit()


func _make_floor(tile_size: int, cell_min: int, cell_max: int, wm: Node) -> TileMapLayer:
	var floor := TileMapLayer.new()
	floor.name = "Floor"
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)

	var src_grass := TileSetAtlasSource.new()
	src_grass.texture = load(GRASS_TEXTURE)
	src_grass.texture_region_size = Vector2i(tile_size, tile_size)
	src_grass.create_tile(Vector2i(0, 0))
	ts.add_source(src_grass, 0)

	var src_path := TileSetAtlasSource.new()
	src_path.texture = load(PATH_TEXTURE)
	src_path.texture_region_size = Vector2i(tile_size, tile_size)
	src_path.create_tile(Vector2i(0, 0))
	ts.add_source(src_path, 1)

	floor.tile_set = ts

	for y in range(cell_min, cell_max + 1):
		for x in range(cell_min, cell_max + 1):
			var pos := Vector2(x * tile_size + tile_size * 0.5, y * tile_size + tile_size * 0.5)
			var src_id := 0
			if wm.is_on_any_path(pos):
				src_id = 1
			floor.set_cell(Vector2i(x, y), src_id, Vector2i(0, 0))
	return floor


func _make_layout(wm_script: GDScript) -> Node2D:
	var layout := Node2D.new()
	layout.name = "MapLayout"
	layout.set_script(load(WORLD_MAP_SCRIPT))

	var center := Marker2D.new()
	center.name = "SettlementCenter"
	layout.add_child(center)

	for dir in wm_script.GATE_ANCHORS:
		var m := Marker2D.new()
		m.name = "GateAnchor_" + dir.to_upper()
		m.position = wm_script.GATE_ANCHORS[dir]
		layout.add_child(m)

	for name in wm_script.SPAWN_CANDIDATES:
		var m := Marker2D.new()
		m.name = "SpawnCandidate_" + name.to_upper()
		m.position = wm_script.SPAWN_CANDIDATES[name]
		layout.add_child(m)

	# TASK-012-6 Approach Route 참고 Marker (비기능). 각 방향 접근로 중앙/끝 지점에 배치.
	for dir in wm_script.APPROACH_ROUTES:
		var poly: Array = wm_script.APPROACH_ROUTES[dir]
		var mid: Vector2 = poly[poly.size() / 2] if poly.size() > 1 else poly[0]
		var mr := Marker2D.new()
		mr.name = "ApproachRoute_" + dir.to_upper()
		mr.position = mid
		layout.add_child(mr)

	for dir in AXIS_MIDPOINTS:
		var m := Marker2D.new()
		m.name = "Axis_" + dir.to_upper()
		m.position = AXIS_MIDPOINTS[dir]
		layout.add_child(m)

	# TASK-012-3 Gate Corridor / Combat Field / Rally Space 참고 Marker (비기능).
	for dir in wm_script.GATE_CORRIDORS:
		var rect: Rect2 = wm_script.GATE_CORRIDORS[dir]
		var m := Marker2D.new()
		m.name = "GateCorridor_" + dir.to_upper()
		m.position = rect.position + rect.size * 0.5
		layout.add_child(m)

	for dir in wm_script.COMBAT_FIELDS:
		var rect: Rect2 = wm_script.COMBAT_FIELDS[dir]
		var m := Marker2D.new()
		m.name = "CombatField_" + dir.to_upper()
		m.position = rect.position + rect.size * 0.5
		layout.add_child(m)

	for dir in wm_script.RALLY_SPACES:
		var rect: Rect2 = wm_script.RALLY_SPACES[dir]
		var m := Marker2D.new()
		m.name = "RallySpace_" + dir.to_upper()
		m.position = rect.position + rect.size * 0.5
		layout.add_child(m)

	# TASK-012-5 미래 콘텐츠 슬롯 참고 Marker (비기능).
	var agri: Rect2 = wm_script.SOUTH_AGRICULTURE_ZONE
	var agri_m := Marker2D.new()
	agri_m.name = "SouthAgricultureZone"
	agri_m.position = agri.position + agri.size * 0.5
	layout.add_child(agri_m)

	var dungeon_m := Marker2D.new()
	dungeon_m.name = "NeDungeonCandidate"
	dungeon_m.position = wm_script.NE_DUNGEON_CANDIDATE
	layout.add_child(dungeon_m)

	for id in wm_script.OUTER_WILD_SLOTS:
		var slot: Rect2 = wm_script.OUTER_WILD_SLOTS[id]
		var m2 := Marker2D.new()
		m2.name = "OuterWild_" + id.to_upper()
		m2.position = slot.position + slot.size * 0.5
		layout.add_child(m2)

	return layout


func _add_walls(world: Node2D, world_size: int, world_half: int) -> void:
	world.add_child(_make_wall("BoundaryWall_North", Vector2(0, -world_half), Vector2(world_size, WALL_THICKNESS)))
	world.add_child(_make_wall("BoundaryWall_South", Vector2(0, world_half), Vector2(world_size, WALL_THICKNESS)))
	world.add_child(_make_wall("BoundaryWall_East", Vector2(world_half, 0), Vector2(WALL_THICKNESS, world_size)))
	world.add_child(_make_wall("BoundaryWall_West", Vector2(-world_half, 0), Vector2(WALL_THICKNESS, world_size)))


func _make_wall(wall_name: String, pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = pos
	wall.collision_layer = 4
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	return wall


func _add_entities(world: Node2D, wm_script: GDScript) -> void:
	var starter_trees: Array = wm_script.STARTER_TREES
	for i in starter_trees.size():
		var tree: Node = (load(TREE_SCENE) as PackedScene).instantiate()
		tree.name = "Tree%d" % (i + 1)
		tree.position = starter_trees[i]
		world.add_child(tree)

	var idx := 4
	for cluster in wm_script.FOREST_CLUSTERS:
		for tree_pos in cluster["trees"]:
			var tree: Node = (load(TREE_SCENE) as PackedScene).instantiate()
			tree.name = "ForestTree%d" % idx
			tree.position = tree_pos
			world.add_child(tree)
			idx += 1

	var deposit: Node = (load(DEPOSIT_SCENE) as PackedScene).instantiate()
	deposit.name = "StoneDeposit"
	deposit.position = wm_script.STONE_ZONE["deposit_pos"]
	world.add_child(deposit)

	for name in CORE_BUILDINGS:
		var core: Node = (load(CORE_SCENE) as PackedScene).instantiate()
		core.name = name
		core.position = CORE_BUILDINGS[name]["pos"]
		core.core_type = CORE_BUILDINGS[name]["core_type"]
		world.add_child(core)

	var deco_idx := 0
	for deco in wm_script.DECORATIONS:
		var node: Node = (load(DECORATION_SCENE) as PackedScene).instantiate()
		node.name = "Deco%d" % deco_idx
		node.position = deco["pos"]
		node.setup(String(deco["type"]), float(deco["scale"]))
		world.add_child(node)
		deco_idx += 1


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path == "":
			_set_owner_recursive(child, owner)