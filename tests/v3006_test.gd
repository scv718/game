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
    # 절대경로(drive letter) 금지. 프로젝트 루트 기준 상대경로만 사용.
    # autoload 검증은 root.get_node_or_null(...) 사용 (deferred 프레임 이후만 유효).
    # 여기에 태스크 핵심 동작 검증을 최소 1개 이상 추가 (실제 코드 로드/호출).
    # 주의: 존재하지 않는 메서드 직접 호출 금지(위 규칙). has_method()로 가드 후 호출.
    
    var mercenary_roster = root.get_node_or_null("MercenaryRoster")
    _check(mercenary_roster != null, "autoload available: MercenaryRoster")
    
    if mercenary_roster != null:
        _check(mercenary_roster.has_method("get_mercenary_data"), "MercenaryRoster has get_mercenary_data")
        
        # 검증: MercenaryData에 장비 시스템이 추가되었는지 확인
        var data = mercenary_roster.call("get_mercenary_data", "test_id")
        if data != null:
            _check(data.has_method("get_weapon"), "MercenaryData has get_weapon")
            _check(data.has_method("get_armor"), "MercenaryData has get_armor")
            _check(data.has_method("get_accessory"), "MercenaryData has get_accessory")
            _check(data.has_method("equip_weapon"), "MercenaryData has equip_weapon")
            _check(data.has_method("unequip_weapon"), "MercenaryData has unequip_weapon")
            _check(data.has_method("equip_armor"), "MercenaryData has equip_armor")
            _check(data.has_method("unequip_armor"), "MercenaryData has unequip_armor")
            _check(data.has_method("equip_accessory"), "MercenaryData has equip_accessory")
            _check(data.has_method("unequip_accessory"), "MercenaryData has unequip_accessory")
            _check(data.has_method("get_attack_bonus"), "MercenaryData has get_attack_bonus")
            _check(data.has_method("get_defense_bonus"), "MercenaryData has get_defense_bonus")
    
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)