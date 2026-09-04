extends SceneTree

const PotionDataScript = preload("res://scripts/potion_data.gd")
const PotionServiceScript = preload("res://scripts/mercenary_potion_service.gd")
const MercenaryDataScript = preload("res://scripts/mercenary_data.gd")
const PreparationScript = preload("res://scripts/dungeon_preparation.gd")
const DeathRecordScript = preload("res://scripts/death_record.gd")
const Mercenary3DScene = preload("res://scenes/mercenary_3d.tscn")

## TASK-027-5 forensic reconstruction test.
## This test exercises the existing Potion contract and the Dungeon preparation
## boundary; it does not introduce a new dungeon effect or Food combat rule.

var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true

func _run() -> void:
	var resources: Node = root.get_node_or_null("VillageResources")
	_check(resources != null, "VillageResources is available")
	if resources == null:
		_finish()
		return

	var service = PotionServiceScript.new(resources)
	var false_case = MercenaryDataScript.new("false", "False", MercenaryDataScript.MercClass.SWORDSMAN)
	false_case.equip_potion("healing_potion", 2)
	resources.add("potion:healing_potion", 2)
	var stock_before: int = resources.get_amount("potion:healing_potion")
	var no_consume := service.auto_consume(false_case, 80, false)
	_check(not no_consume["ok"] and resources.get_amount("potion:healing_potion") == stock_before,
		"condition false consumes zero potions")

	var true_case = MercenaryDataScript.new("true", "True", MercenaryDataScript.MercClass.SWORDSMAN)
	true_case.equip_potion("healing_potion", 2)
	var consumed := service.auto_consume(true_case, 20, false)
	_check(consumed["ok"] and consumed["consumed"] and consumed["new_hp"] == 50,
		"condition true consumes and applies the existing heal once")
	_check(true_case.get_potion_slot_count() == 1 and resources.get_amount("potion:healing_potion") == stock_before - 1,
		"successful consume decrements exactly one slot and one stock")
	var duplicate := service.auto_consume(true_case, int(consumed["new_hp"]), true)
	_check(not duplicate["ok"] and true_case.get_potion_slot_count() == 1 \
			and resources.get_amount("potion:healing_potion") == stock_before - 1,
		"same trigger/frame guard prevents multi-consume")

	var empty_case = MercenaryDataScript.new("empty", "Empty", MercenaryDataScript.MercClass.SWORDSMAN)
	var empty_result := service.auto_consume(empty_case, 1, false)
	_check(not empty_result["ok"], "empty Potion slot is safe")

	var prep = PreparationScript.new("prep")
	prep.set_food_slot("stew")
	prep.set_potion_slots(["healing_potion"])
	_check(prep.get_food_slot() == "stew" and prep.get_potion_slots() == ["healing_potion"],
		"Food preparation and Potion slot remain separate data hooks")
	var prep_snapshot := prep.to_snapshot()
	_check(prep_snapshot["food_slot_id"] == "stew" and prep_snapshot["potion_slot_ids"] == ["healing_potion"],
		"preparation snapshot preserves separate Food/Potion roles")

	var record = DeathRecordScript.new("record")
	record.source_uid = "true"
	record.display_name = "True"
	record.max_hp = 100
	var snapshot := record.to_snapshot()
	_check(not snapshot.has("potion_slot_id") and not snapshot.has("potion_slot_count") \
			and not snapshot.has("current_hp") and not snapshot.has("temporary_buff"),
		"temporary combat Potion state is absent from DeathRecord identity snapshot")

	# Dungeon uses MercenaryActor3D; verify the same service is called by the
	# actual runtime actor, without inventing a second Dungeon potion path.
	var dungeon_merc = MercenaryDataScript.new("dungeon", "Dungeon", MercenaryDataScript.MercClass.SWORDSMAN)
	dungeon_merc.equip_potion("healing_potion", 1)
	resources.add("potion:healing_potion", 1)
	var actor: Node = Mercenary3DScene.instantiate()
	actor.merc_data = dungeon_merc
	root.add_child(actor)
	await process_frame
	actor.current_hp = 20
	actor._tick_auto_potion()
	_check(actor.current_hp == 50 and dungeon_merc.get_potion_slot_count() == 0,
		"Dungeon MercenaryActor3D uses the shared Potion auto-consume hook")
	actor.queue_free()

	_finish()

func _finish() -> void:
	print("TASK0275_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)

