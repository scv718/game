extends SceneTree

var _frame := 0
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		var main: Node = root.get_node("Main")
		var placement: Node = main.get_node("BuildingPlacement")
		var hud: Node = main.get_node("HUD")
		var resources: Node = root.get_node("VillageResources")
		var deposits := get_nodes_in_group("stone_deposits")
		var deposit: Node = deposits[0] if deposits.size() > 0 else null

		_check(deposit != null, "world has StoneDeposit for placement tests")
		if deposit == null:
			_finish()
			return true

		_check(placement._building_type == "lumberyard", "placement defaults to lumberyard")
		placement._set_building_type("quarry")
		_check(placement._building_type == "quarry", "building type switches to quarry")
		_check(hud.build_label.text.begins_with("Quarry"), "HUD build label shows Quarry hint (%s)" % hud.build_label.text)

		resources._amounts["wood"] = 0
		placement._try_place_quarry_at(deposit.global_position)
		_check(get_nodes_in_group("quarries").size() == 0, "no quarry built without enough wood")
		_check(resources.get_amount("wood") == 0, "wood unchanged when cost not affordable")

		resources._amounts["wood"] = 20
		var wood_before: int = resources.get_amount("wood")
		placement._try_place_quarry_at(Vector2(100, 100))
		_check(get_nodes_in_group("quarries").size() == 0, "quarry denied outside deposit area")
		_check(resources.get_amount("wood") == wood_before, "wood not deducted outside deposit")

		placement._try_place_quarry_at(deposit.global_position + Vector2(8, 8))
		_check(get_nodes_in_group("quarries").size() == 1, "quarry built on valid deposit")
		_check(resources.get_amount("wood") == wood_before - 10, "wood deducted exactly once (-10)")
		_check(deposit.is_occupied(), "deposit occupied after quarry built")
		var quarry: Node = get_nodes_in_group("quarries")[0]
		_check(quarry.get_deposit() == deposit, "quarry linked to deposit")
		_check(quarry.global_position.distance_to(deposit.global_position) < 1.0, "quarry placed at deposit position")
		_check(quarry.is_in_group("buildings"), "quarry is a Building")

		placement._try_place_quarry_at(deposit.global_position)
		_check(get_nodes_in_group("quarries").size() == 1, "second quarry on same deposit denied")
		_check(resources.get_amount("wood") == wood_before - 10, "no extra wood cost on denied second quarry")
		_check(is_instance_valid(quarry), "first quarry still exists after denied second")

		placement._set_building_type("lumberyard")
		resources._amounts["wood"] = 10
		var ly_count := get_nodes_in_group("lumberyards").size()
		var spot := Vector2(500, 300)
		if placement._is_valid_position(spot):
			placement._try_place_at(spot)
			_check(get_nodes_in_group("lumberyards").size() == ly_count + 1, "lumberyard placement still works after quarry mode")
			_check(resources.get_amount("wood") == 0, "lumberyard cost deducted once")
		else:
			print("SKIP: lumberyard spot (%s) collides in test world, skipping lumberyard regression check" % str(spot))

		_finish()
		return true
	if _frame > 25000:
		print("TASK0072_RESULT=TIMEOUT")
		quit()
		return true
	return false


func _finish() -> void:
	print("TASK0072_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
