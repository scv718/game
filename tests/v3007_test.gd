extends SceneTree

const TEST_MERCENARY_ACTOR_3D := "res://scripts/mercenary_actor_3d.gd"
const TEST_MERCENARY_DATA := "res://scripts/mercenary_data.gd"

const REQUIRED_AUTOLOADS := [
	"VillageResources", "GameTime", "WorkerRoster", "MercenaryRoster",
	"FirstEncounterSpawner", "DeathLedger", "ExplorationManager",
]

var _frames := 0
var _failed := false

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_run_load_checks()
	elif _frames == 12:
		_run_runtime_checks()
		_finish()
		return true
	elif _frames > 600:
		print("V3007_RESULT=TIMEOUT")
		quit(1)
		return true
	return false


func _run_load_checks() -> void:
	# Check if MercenaryActor3D exists and can be loaded
	var script: Script = load(TEST_MERCENARY_ACTOR_3D)
	_check(script != null, "MercenaryActor3D script loads")
	
	# Check if MercenaryData exists and can be loaded
	script = load(TEST_MERCENARY_DATA)
	_check(script != null, "MercenaryData script loads")
	
	# Check autoloads
	for autoload_name in REQUIRED_AUTOLOADS:
		_check(root.get_node_or_null(autoload_name) != null,
			"critical autoload available: %s" % autoload_name)


func _run_runtime_checks() -> void:
	# Verify that MercenaryActor3D has skill definition and methods
	var mercenary_script = load(TEST_MERCENARY_ACTOR_3D)
	if mercenary_script == null:
		_check(false, "MercenaryActor3D script loads")
		return
		
	var instance: Node = mercenary_script.new()
	if instance == null:
		_check(false, "MercenaryActor3D can be instantiated")
		return
	
	# Check that SKILLS constant exists
	_check(mercenary_script.has_constant("SKILLS"), "MercenaryActor3D has SKILLS constant")
	
	# Check that skill loadout exists
	_check(mercenary_script.has_variable("_skill_loadout"), "MercenaryActor3D has skill loadout")
	
	# Check that initialize_skill method exists
	_check(mercenary_script.has_method("initialize_skill"), "MercenaryActor3D has initialize_skill method")
	
	# Check that execute_skill method exists
	_check(mercenary_script.has_method("execute_skill"), "MercenaryActor3D has execute_skill method")
	
	# Check that _in_range method exists
	_check(mercenary_script.has_method("_in_range"), "MercenaryActor3D has _in_range method")
	
	# Check that _process method exists (for skill cooldowns)
	_check(mercenary_script.has_method("_process"), "MercenaryActor3D has _process method")
	
	# Verify SKILLS content
	if mercenary_script.has_constant("SKILLS"):
		var skills = mercenary_script.get_constant("SKILLS")
		_check(skills != null, "SKILLS constant is not null")
		
		# Check that basic_attack skill exists with correct properties
		_check(skills.has("basic_attack"), "basic_attack skill exists")
		if skills.has("basic_attack"):
			var basic_attack = skills["basic_attack"]
			_check(basic_attack != null, "basic_attack skill is not null")
			_check(basic_attack.has("name"), "basic_attack has name")
			_check(basic_attack.has("cooldown"), "basic_attack has cooldown")
			_check(basic_attack.has("range"), "basic_attack has range")
			_check(basic_attack.has("target_type"), "basic_attack has target_type")
			_check(basic_attack.has("effect"), "basic_attack has effect")
			_check(basic_attack.has("damage"), "basic_attack has damage")
		
		# Check that shield_bash skill exists with correct properties
		_check(skills.has("shield_bash"), "shield_bash skill exists")
		if skills.has("shield_bash"):
			var shield_bash = skills["shield_bash"]
			_check(shield_bash != null, "shield_bash skill is not null")
			_check(shield_bash.has("name"), "shield_bash has name")
			_check(shield_bash.has("cooldown"), "shield_bash has cooldown")
			_check(shield_bash.has("range"), "shield_bash has range")
			_check(shield_bash.has("target_type"), "shield_bash has target_type")
			_check(shield_bash.has("effect"), "shield_bash has effect")
			_check(shield_bash.has("duration"), "shield_bash has duration")
	
	# Check that skill loadout contains correct skills
	if mercenary_script.has_variable("_skill_loadout"):
		var loadout = instance.get("_skill_loadout") if instance != null else null
		_check(loadout != null, "Skill loadout is initialized")
		if loadout != null:
			_check(loadout.has("basic_attack"), "Skill loadout contains basic_attack")
			_check(loadout.has("shield_bash"), "Skill loadout contains shield_bash")
	
	instance.free()


func _finish() -> void:
	print("V3007_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)