extends SceneTree

const DeathRecordScript = preload("res://scripts/death_record.gd")

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	failed = failed or not ok

func _snapshot(uid: String, category: String, ghost := false) -> Dictionary:
	var record = DeathRecordScript.new("")
	record.source_uid = uid
	record.source_kind = DeathRecordScript.SourceKind.ENEMY
	record.category = category
	record.display_name = uid
	record.is_ghost = ghost
	record.death_day = 2
	return record.to_snapshot()

func _run() -> void:
	var ledger := root.get_node("DeathLedger")
	var first = ledger.record_death(_snapshot("task017_dup", "ENEMY"))
	var duplicate = ledger.record_death(_snapshot("task017_dup", "ENEMY"))
	check(first != null and duplicate != null and first.record_id == duplicate.record_id,
		"duplicate lethal callback maps to one identity record")
	check(ledger.get_all_records().size() == 1, "duplicate callback creates no second candidate")
	check(ledger.record_death(_snapshot("task017_unsupported", "ANIMAL")) == null,
		"unsupported unimplemented category is safely skipped")
	check(ledger.record_death(_snapshot("task017_ghost", "ENEMY", true)) == null,
		"ghost death cannot create a recursive candidate")
	print("TASK0172_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
