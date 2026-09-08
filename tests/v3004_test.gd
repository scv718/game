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
	# autoload 검증은 root.get_node_or_null(...) 사용 (deferred 프레임 이후만 유효).
	_check(root.get_node_or_null("VillageResources") != null, "autoload available: VillageResources")
	_check(root.get_node_or_null("WorkerRoster") != null, "autoload available: WorkerRoster")
	_check(root.get_node_or_null("DungeonManager") != null, "autoload available: DungeonManager")
	_check(root.get_node_or_null("DeathLedger") != null, "autoload available: DeathLedger")
	
	# 검증: VillageResources has add_food
	var vr = root.get_node_or_null("VillageResources")
	if vr != null:
		_check(vr.has_method("add_food"), "VillageResources has add_food")
		_check(vr.has_method("get_food_count"), "VillageResources has get_food_count")
	
	# 검증: WorkerRoster has assign_worker
	var wr = root.get_node_or_null("WorkerRoster")
	if wr != null:
		_check(wr.has_method("assign_worker"), "WorkerRoster has assign_worker")
	
	# 검증: 실제 코드 동작
	if vr != null and wr != null:
		# Test that we can call the methods without error
		_check(vr.call("add_food", "berry", 5) != null, "VillageResources.add_food works")
		_check(vr.call("get_food_count", "berry") == 5, "VillageResources.get_food_count works")
	
	print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)