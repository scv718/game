extends SceneTree

const DeathRecordScript = preload("res://scripts/death_record.gd")

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	failed = failed or not ok

func _run() -> void:
	var ledger := root.get_node("DeathLedger")
	var source = DeathRecordScript.new("")
	source.source_uid = "task017_once"
	source.source_kind = DeathRecordScript.SourceKind.MERCENARY
	source.category = "MERCENARY"
	source.display_name = "Returned Once"
	source.death_day = 3
	var candidate = ledger.record_death(source.to_snapshot())
	check(candidate != null and ledger.mark_active(candidate.record_id),
		"candidate transitions PENDING to ACTIVE once")
	check(ledger.resolve(candidate.record_id, 4), "returned identity resolves")
	check(not ledger.mark_pending(candidate.record_id), "resolved identity cannot be queued again")
	var repeated = ledger.record_death(source.to_snapshot())
	check(repeated != null and repeated.record_id == candidate.record_id,
		"later duplicate death callback reuses the resolved identity")
	check(ledger.get_resolved_records().size() == 1 and ledger.get_pending_records().is_empty(),
		"one-return invariant remains exact")
	print("TASK0174_RESULT=" + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
