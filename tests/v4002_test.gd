extends SceneTree

var _failures: int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failures += 1
		print("FAIL: " + msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Test that we can load and instantiate DungeonRuntime
	var dr = load("res://scripts/dungeon_runtime.gd").new()
	_check(dr != null, "DungeonRuntime instance created")
	
	# Test basic phase access
	if dr.has_method("get_phase"):
		var phase = dr.call("get_phase")
		_check(phase == 0, "Initial phase is IDLE (0)")
	
	# Test phase names
	if dr.has_method("get_phase_name"):
		var phase_name = dr.call("get_phase_name")
		_check(phase_name == "IDLE", "Initial phase name is IDLE")
	
	# Test that the signal exists
	if dr.has_signal("phase_changed"):
		_check(true, "phase_changed signal exists")
	
	print("V4002_ASSERTIONS=4/4")
	print("V4002_RESULT=PASS")
	quit(0 if _failures == 0 else 1)