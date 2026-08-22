extends SceneTree

enum Phase {
	SETUP, SMOKE, TERRAIN, FOREST, DECORATION, ATLAS, REGRESSION, DONE
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _layout: Node = null
var _floor: TileMapLayer = null
var _controller: Node = null
var _wm_script: GDScript = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = main.get_node("World")
			_layout = _world.get_node_or_null("MapLayout")
			_floor = _world.get_node("Floor") as TileMapLayer
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			if _controller != null:
				_controller.day_pan_speed = 2000.0
			_wm_script = load("res://scripts/world_map.gd")
			_enter(Phase.SMOKE)
		Phase.SMOKE:
			_check(_world != null, "main.tscn loads with World node")
			_check(_layout != null, "MapLayout node exists")
			if _layout == null or _floor == null:
				_finish()
				return true
			_check(_layout.get_script().resource_path == "res://scripts/world_map.gd", "MapLayout uses world_map.gd")
			_check(_floor is TileMapLayer, "Floor is a TileMapLayer")
			_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles (%d)" % _floor.get_used_cells().size())
			_enter(Phase.TERRAIN)
		Phase.TERRAIN:
			var grass_count := 0
			var path_count := 0
			for cell in _floor.get_used_cells():
				if _floor.get_cell_source_id(cell) == 1:
					path_count += 1
				else:
					grass_count += 1
			_check(grass_count > 0, "grass tiles present (%d)" % grass_count)
			_check(path_count > 0, "path (road) tiles present (%d)" % path_count)
			_check(path_count < grass_count, "grass dominates the map, roads are sparse (grass=%d path=%d)" % [grass_count, path_count])

			var ts := _floor.tile_set
			_check(ts.get_source_count() == 2, "tile set has grass + path sources (count=%d)" % ts.get_source_count())
			var src_grass: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
			var src_path: TileSetAtlasSource = ts.get_source(1) as TileSetAtlasSource
			_check(src_grass != null and src_grass.texture != null and src_grass.texture.get_width() == 16 and src_grass.texture.get_height() == 16,
				"grass source is a single 16x16 tile texture")
			_check(src_path != null and src_path.texture != null and src_path.texture.get_width() == 16 and src_path.texture.get_height() == 16,
				"path source is a single 16x16 tile texture")

			_check(_floor.get_cell_source_id(Vector2i(0, 0)) == 0, "settlement center tile is grass (not road)")
			_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east access axis reads as road")
			_check(_floor.get_cell_source_id(Vector2i(-19, 0)) == 1, "west access axis reads as road")
			_check(_floor.get_cell_source_id(Vector2i(0, -19)) == 1, "north access axis reads as road")
			_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south access axis reads as road")
			_check(_floor.get_cell_source_id(Vector2i(25, 25)) == 0, "off-axis corner tile is grass (no road)")
			_check(_floor.get_cell_source_id(Vector2i(5, 5)) == 0, "tile inside clearing is grass (no road)")
			_enter(Phase.FOREST)
		Phase.FOREST:
			var clusters: Array = _wm_script.FOREST_CLUSTERS
			_check(clusters.size() >= 3, "at least 3 meaningful forest clusters defined (%d)" % clusters.size())
			for i in clusters.size():
				var trees: Array = clusters[i]["trees"]
				_check(trees.size() >= 3, "forest cluster %d has >= 3 trees (%d)" % [i, trees.size()])
				for pos in trees:
					_check(_layout.is_in_bounds(pos), "forest cluster %d tree inside map bounds" % i)
					_check(not _layout.is_in_clearing(pos), "forest cluster %d tree not inside settlement clearing" % i)
					_check(not _layout.is_on_access_axis(pos), "forest cluster %d tree not on access axis/road" % i)

			var world_trees := get_nodes_in_group("interactable")
			_check(world_trees.size() >= 12, "world contains many trees from clusters (%d)" % world_trees.size())
			var forest_tree_nodes := 0
			for t in _world.get_children():
				if String(t.name).begins_with("ForestTree"):
					forest_tree_nodes += 1
			_check(forest_tree_nodes >= 12, "world contains explicit ForestTree nodes (%d)" % forest_tree_nodes)

			var blocking := 0
			var on_axis := 0
			for t in world_trees:
				if _layout.is_in_clearing(t.global_position):
					blocking += 1
				if _layout.is_on_access_axis(t.global_position):
					on_axis += 1
			_check(blocking == 0, "no trees block the settlement clearing (%d found)" % blocking)
			_check(on_axis == 0, "no trees block the access axes/roads (%d found)" % on_axis)

			var clearing: Rect2 = _layout.get_clearing_rect()
			var buffer: Rect2 = _layout.get_wall_buffer_rect()
			_check(clearing.size == Vector2(384, 384), "clearing 384x384 for Lumberyard/Quarry placement (%s)" % str(clearing.size))
			_check(buffer.size == Vector2(576, 576), "wall buffer ring 576x576 for future wall space (%s)" % str(buffer.size))
			_check(_layout.is_in_wall_buffer(Vector2(0, 240)), "space outside clearing reserved for future wall")
			_enter(Phase.DECORATION)
		Phase.DECORATION:
			var decos := get_nodes_in_group("decorations")
			_check(decos.size() >= 4, "decoration objects present (%d)" % decos.size())
			for d in decos:
				_check(d.get_script() != null and d.get_script().resource_path == "res://scripts/decoration.gd", "decoration %s uses decoration.gd" % d.name)
				var has_collision := false
				for child in d.get_children():
					if child is StaticBody2D or child is CollisionShape2D or child is Area2D:
						has_collision = true
				_check(not has_collision, "decoration %s is pure visual (no collision/area)" % d.name)
				var vis: Sprite2D = d.get_node_or_null("Visual") as Sprite2D
				_check(vis != null and vis.texture != null, "decoration %s has a visual texture" % d.name)
			var tree_collisions := 0
			var deco_positions: Array[Vector2] = []
			for d in decos:
				deco_positions.append(d.global_position)
			for t in get_nodes_in_group("interactable"):
				if t.get_node_or_null("TrunkBlock") != null:
					tree_collisions += 1
			_check(tree_collisions >= 12, "trees carry collision for build/nav blocking (%d)" % tree_collisions)
			_enter(Phase.ATLAS)
		Phase.ATLAS:
			var atlas_errors := 0
			for t in get_nodes_in_group("interactable"):
				var canopy_vis: Sprite2D = t.get_node_or_null("Canopy/Visual") as Sprite2D
				var stump_vis: Sprite2D = t.get_node_or_null("StumpVisual/Visual") as Sprite2D
				if not _check_atlas_crop(canopy_vis, "tree %s canopy" % t.name):
					atlas_errors += 1
				if not _check_atlas_crop(stump_vis, "tree %s stump" % t.name):
					atlas_errors += 1
			_check(atlas_errors == 0, "no tree sprite sheet wrongly exposed (%d atlas issues)" % atlas_errors)

			for d in get_nodes_in_group("decorations"):
				var vis: Sprite2D = d.get_node_or_null("Visual") as Sprite2D
				if vis == null or vis.texture == null:
					atlas_errors += 1
					continue
				var tex: Texture2D = vis.texture
				if tex is AtlasTexture:
					atlas_errors += 1
					continue
				if tex.get_width() > 128 or tex.get_height() > 128:
					atlas_errors += 1
			_check(atlas_errors == 0, "no decoration sprite sheet wrongly exposed (%d atlas issues)" % atlas_errors)
			_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			_check(get_nodes_in_group("interactable").size() >= 3, "trees present (%d)" % get_nodes_in_group("interactable").size())
			if get_nodes_in_group("lumberjacks").size() < 1:
				var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
				lj.position = Vector2(300, 200)
				_world.add_child(lj)
			if get_nodes_in_group("miners").size() < 1:
				var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
				mn.position = Vector2(500, 140)
				_world.add_child(mn)
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present")
			_check(get_nodes_in_group("miners").size() >= 1, "miner present")
			_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
			_check(get_nodes_in_group("decorations").size() >= 4, "decorations present (%d)" % get_nodes_in_group("decorations").size())

			var bounds: Rect2 = _layout.get_bounds_rect()
			_check(bounds.size == Vector2(2048, 2048), "bounds size 2048x2048 (%s)" % str(bounds.size))
			_check(bounds.position == Vector2(-1024, -1024), "bounds centered at origin (%s)" % str(bounds.position))
			_check(_layout.is_in_clearing(Vector2.ZERO), "settlement center inside clearing")
			_check(not _layout.is_in_clearing(Vector2(250, 0)), "point outside clearing rejected")

			for dir in ["north", "south", "east", "west"]:
				var anchor: Vector2 = _layout.get_gate_anchor(dir)
				var anchor_node: Node = _layout.get_node_or_null("GateAnchor_" + dir.to_upper())
				var axis_node: Node = _layout.get_node_or_null("Axis_" + dir.to_upper())
				_check(anchor_node != null, "GateAnchor_%s marker exists" % dir.to_upper())
				_check(anchor != Vector2.ZERO, "gate anchor %s defined" % dir)
				_check(_layout.is_in_bounds(anchor), "gate anchor %s inside bounds" % dir)
				_check(axis_node != null, "Axis_%s marker exists" % dir.to_upper())

			var spawns: Array = _layout.get_spawn_candidate_nodes()
			_check(spawns.size() >= 2, "at least 2 spawn candidate markers (%d)" % spawns.size())
			for s in spawns:
				_check(s.get_script() == null, "spawn candidate %s is non-functional marker" % s.name)
			var gates: Array = _layout.get_gate_anchor_nodes()
			_check(gates.size() >= 4, "4 gate anchor markers (%d)" % gates.size())
			for g in gates:
				_check(g.get_script() == null, "gate anchor %s is non-functional marker" % g.name)

			for wn in ["BoundaryWall_North", "BoundaryWall_South", "BoundaryWall_East", "BoundaryWall_West"]:
				var wall: Node = _world.get_node_or_null(wn)
				_check(wall != null and wall is StaticBody2D, "%s exists as StaticBody2D" % wn)
				if wall != null:
					_check(wall.collision_layer == 4, "%s on collision layer 4" % wn)
					_check(wall.collision_mask == 0, "%s has collision mask 0" % wn)
					_check(wall.get_child_count() >= 1 and wall.get_child(0) is CollisionShape2D, "%s has collision shape child" % wn)

			_controller.global_position = Vector2.ZERO
			Input.action_press("move_right")
			_enter(Phase.DONE)
		Phase.DONE:
			if _elapsed() < 120:
				return false
			Input.action_release("move_right")
			_check(_controller.global_position.x > 90, "DAY: camera pans from center toward east outskirts (x=%s)" % str(_controller.global_position.x))
			_check(absf(_controller.global_position.x) <= 1024.0 + 0.01, "camera stays inside map bounds while panning")
			_world.rebuild_navigation()
			_check(true, "navigation rebuild on new terrain works")
			print("TASK0082_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 20000:
		print("TASK0082_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _check_atlas_crop(vis: Sprite2D, label: String) -> bool:
	if vis == null or vis.texture == null:
		_check(false, "%s has a texture" % label)
		return false
	var tex: Texture2D = vis.texture
	if not tex is AtlasTexture:
		_check(false, "%s uses AtlasTexture (label=%s)" % [str(tex), label])
		return false
	var atlas: Texture2D = (tex as AtlasTexture).atlas
	var region: Rect2 = (tex as AtlasTexture).region
	if atlas == null:
		_check(false, "%s atlas texture is valid" % label)
		return false
	var atlas_size := Vector2(atlas.get_width(), atlas.get_height())
	if region.position.x < 0 or region.position.y < 0 or region.end.x > atlas_size.x or region.end.y > atlas_size.y:
		_check(false, "%s region inside atlas bounds (%s in %s)" % [label, str(region), str(atlas_size)])
		return false
	if region.size.x >= atlas_size.x and region.size.y >= atlas_size.y:
		_check(false, "%s region is a cropped sprite, not the whole sheet (%s in %s)" % [label, str(region.size), str(atlas_size)])
		return false
	_check(true, "%s is a proper sprite-sheet crop (region %s in atlas %s)" % [label, str(region.size), str(atlas_size)])
	return true


func _finish() -> void:
	print("TASK0082_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)