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
	var vr = root.get_node_or_null("VillageResources")
	_check(vr != null, "autoload available: VillageResources")
	
	if vr != null:
		# Test gold initialization
		var initial_gold = vr.call("get_amount", "gold")
		_check(initial_gold == 100, "initial gold amount is correct")
		
		# Test that new methods exist
		_check(vr.has_method("buy_resource"), "has buy_resource method")
		_check(vr.has_method("sell_resource"), "has sell_resource method")
		_check(vr.has_method("get_resource_price"), "has get_resource_price method")
	
	print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)