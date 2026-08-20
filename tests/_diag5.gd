extends SceneTree

var _f := 0

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 8:
		var main: Node = root.get_node("Main")
		var world: Node = main.get_node("World")
		var nav_map: RID = world.get_world_2d().get_navigation_map()
		var start := Vector2(500, 140)
		var candidates := [Vector2(480, 360), Vector2(480, 300), Vector2(500, 260), Vector2(520, 280), Vector2(540, 200), Vector2(480, 340)]
		for c in candidates:
			var cv: Vector2 = c
			var wp: Vector2 = cv + Vector2(-24, 72)
			var p: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, start, wp, true)
			var lenf := 0.0
			for i in range(p.size() - 1):
				lenf += p[i].distance_to(p[i + 1])
			var dist_from_center: float = cv.length()
			print("deposit ", cv, " wp=", wp, " pathlen=", int(lenf), " dist_from_center=", int(dist_from_center))
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
