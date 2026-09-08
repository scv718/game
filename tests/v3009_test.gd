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
    # 검증: autoload 존재 확인 (deferred 프레임 이후)
    _check(root.get_node_or_null("VillageResources") != null, "autoload available: VillageResources")
    _check(root.get_node_or_null("WorkerRoster") != null, "autoload available: WorkerRoster")
    _check(root.get_node_or_null("MercenaryRoster") != null, "autoload available: MercenaryRoster")
    
    # 검증: VillageResources에 capacity 관련 메서드 존재
    var vr = root.get_node_or_null("VillageResources")
    if vr != null:
        _check(vr.has_method("add_resource_storage"), "VillageResources has add_resource_storage")
        _check(vr.has_method("get_resource_capacity"), "VillageResources has get_resource_capacity")
        _check(vr.has_method("is_resource_overflowing"), "VillageResources has is_resource_overflowing")
    
    # 검증: WorkerRoster에 capacity 관련 메서드 존재
    var wr = root.get_node_or_null("WorkerRoster")
    if wr != null:
        _check(wr.has_method("get_worker_capacity"), "WorkerRoster has get_worker_capacity")
        _check(wr.has_method("get_current_workers"), "WorkerRoster has get_current_workers")

    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)