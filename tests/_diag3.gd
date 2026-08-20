extends SceneTree

var _f := 0

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 8:
		var main: Node = root.get_node("Main")
		var world: Node = main.get_node("World")
		var nav_map: RID = world.get_world_2d().get_navigation_map()
		var start := Vector2(500, 140)
		var candidates := [Vector2(480, 360), Vector2(520, 340), Vector2(500, 380), Vector2(560, 360), Vector2(520, 400), Vector2(480, 420)]
		for c in candidates:
			var p: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, start, c, true)
			var lenf := 0.0
			for i in range(p.size() - 1):
				lenf += p[i].distance_to(p[i + 1])
			print("from (500,140) to ", c, ": path nodes=", p.size(), " pathlen=", int(lenf), " straight=", int(start.distance_to(c)))
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
