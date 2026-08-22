extends SceneTree

var _frames := 0
var _failed := false

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var main: Node = root.get_node("Main")
		_check(main != null, "main.tscn loads")

		# TASK-CTRL-001-4: runtime에 Player Actor가 존재하지 않는다.
		_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")

		var ljs := get_nodes_in_group("lumberjacks")
		_check(ljs.size() >= 1, "lumberjack present")
		if ljs.size() > 0:
			var lj: Node = ljs[0]
			var lvis: AnimatedSprite2D = lj.get_node("Visual")
			var lframes := lvis.sprite_frames
			var names := lframes.get_animation_names()
			_check(names.has("gather"), "lumberjack has gather anim")
			_check(lframes.get_frame_count("gather") == 6, "gather has 6 frames")
			_check(lvis.has_method("is_gathering") == false or lj.has_method("is_gathering"), "lumberjack script has is_gathering")
			var galias := lframes.get_frame_texture("gather", 0)
			_check(galias.region.size.x >= 90.0, "gather frame region ~95px wide (%s)" % str(galias.region))

		var trees := get_nodes_in_group("interactable")
		_check(trees.size() >= 3, "trees present (%d)" % trees.size())
		for t in trees:
			var canopy: Sprite2D = t.get_node_or_null("Canopy/Visual") as Sprite2D
			var stump: Sprite2D = t.get_node_or_null("StumpVisual/Visual") as Sprite2D
			_check(canopy != null and canopy.texture != null and canopy.texture.get_width() > 100, "tree canopy texture big (%s)" % (str(canopy.texture) if canopy else "none"))
			_check(stump != null and stump.texture != null, "stump texture present")
			break

		var world: Node = main.get_node("World")
		var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
		_check(floor_node.get_used_cells().size() > 7000, "floor has grass tiles (%d)" % floor_node.get_used_cells().size())
		var src: TileSetAtlasSource = floor_node.tile_set.get_source(0) as TileSetAtlasSource
		_check(src != null and src.texture != null and src.texture.get_width() == 16, "floor uses 16x16 grass tile texture")
		var td := floor_node.get_cell_tile_data(floor_node.get_used_cells()[0])
		_check(td != null, "floor tile renders tile data")

		# lumberyard texture (via direct instance - none placed at spawn)
		var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
		_check(ly_scene != null, "lumberyard scene loads")
		if ly_scene != null:
			var ly: Node = ly_scene.instantiate()
			main.add_child(ly)
			var vis: Sprite2D = ly.get_node("Visual") as Sprite2D
			_check(vis.texture != null and vis.texture.get_width() > 100, "lumberyard house texture big (%s)" % str(vis.texture))
			ly.queue_free()

		print("SMOKE_RESULT=" + ("FAIL" if _failed else "PASS"))
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var world: Node = scene.get_node("World")
	var lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
	lj.position = Vector2(300, 200)
	world.add_child(lj)
	var mn = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
	mn.position = Vector2(500, 140)
	world.add_child(mn)