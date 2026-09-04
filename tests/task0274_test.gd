extends SceneTree

func _check(cond, msg):
	if not cond:
		print("FAIL: " + msg)
		return false
	return true

func _ready():
	var all_passed = true
	
	# Check if PopulationConsumption autoload exists
	var pop_consumption_scene = preload("res://src/autoload/population_consumption.tscn")
	all_passed = _check(pop_consumption_scene != null, "PopulationConsumption autoload scene not found") and all_passed
	
	# Check if the scene can be instanced
	var instance = pop_consumption_scene.instantiate()
	all_passed = _check(instance != null, "Failed to instantiate PopulationConsumption scene") and all_passed
	
	# Validate that the class is correctly named
	all_passed = _check(instance.get_class() == "PopulationConsumption", "Class name mismatch for PopulationConsumption") and all_passed
	
	print("TASK-018-2: PopulationConsumption autoload exists - " + ("PASS" if all_passed else "FAIL"))
