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
		var resources: Node = root.get_node("VillageResources")

		_check(resources != null, "VillageResources autoload present")
		_check(resources.get_amount("stone") == 0, "stone defaults to 0")
		resources.add("stone", 5)
		_check(resources.get_amount("stone") == 5, "stone increases via add (+5)")
		_check(resources.has("stone", 5), "stone has() reflects amount")
		_check(resources.spend("stone", 2), "stone spend succeeds")
		_check(resources.get_amount("stone") == 3, "stone decreases via spend (-2)")
		_check(not resources.spend("stone", 99), "stone spend beyond amount rejected")

		var hud: Node = main.get_node("HUD")
		var stone_label: Label = hud.get_node("%StoneLabel")
		_check(stone_label != null and stone_label.text == "Stone: 3", "HUD stone label updated (%s)" % stone_label.text)
		resources.add("stone", 10)
		_check(stone_label.text == "Stone: 13", "HUD stone label refreshes on change (%s)" % stone_label.text)

		var deposits := get_nodes_in_group("stone_deposits")
		_check(deposits.size() == 1, "world has 1 StoneDeposit (got %d)" % deposits.size())
		var deposit: Node = deposits[0] if deposits.size() > 0 else null
		if deposit != null:
			_check(not deposit.is_occupied(), "deposit starts unoccupied")
			_check(deposit.get_quarry() == null, "deposit has no quarry initially")
			var fake_quarry := Node.new()
			fake_quarry.name = "FakeQuarry"
			main.add_child(fake_quarry)
			_check(deposit.occupy(fake_quarry), "occupy succeeds on unoccupied deposit")
			_check(deposit.is_occupied(), "deposit occupied after occupy")
			_check(deposit.get_quarry() == fake_quarry, "deposit returns linked quarry")
			_check(not deposit.occupy(fake_quarry), "second occupy rejected while occupied")
			deposit.release()
			_check(not deposit.is_occupied(), "deposit unoccupied after release")
			_check(deposit.get_quarry() == null, "quarry cleared after release")
			fake_quarry.queue_free()

		print("TASK0071_RESULT=" + ("FAIL" if _failed else "PASS"))
		quit()
		return true
	if _frame > 25000:
		print("TASK0071_RESULT=TIMEOUT")
		quit()
		return true
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)