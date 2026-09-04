extends SceneTree

const DeathRecordScript = preload("res://scripts/death_record.gd")

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	failed = failed or not ok

func _run() -> void:
	var ledger := root.get_node_or_null("DeathLedger")
	check(ledger != null, "DeathLedger is the canonical ghost candidate owner")
	var record = DeathRecordScript.new("")
	record.source_uid = "task017_enemy"
	record.source_kind = DeathRecordScript.SourceKind.ENEMY
	record.category = "ENEMY"
	record.display_name = "Fallen Raider"
	record.max_hp = 60
	record.attack_damage = 8
	record.death_day = 1
	var snapshot: Dictionary = record.to_snapshot()
	check(not snapshot.has("current_hp") and not snapshot.has("runtime_actor"),
		"identity snapshot excludes runtime combat state")
	var added = ledger.record_death(snapshot)
	check(added != null and added.source_uid == "task017_enemy",
		"eligible lethal identity becomes a candidate")
	check(ledger.get_pending_records().size() == 1, "candidate remains persistent in ledger")
	print("TASK0171_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
