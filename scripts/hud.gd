extends CanvasLayer

@onready var wood_label: Label = %WoodLabel
@onready var stone_label: Label = %StoneLabel
@onready var food_label: Label = %FoodLabel
@onready var meal_label: Label = %MealLabel
@onready var daytime_label: Label = %DayTimeLabel
@onready var day_progress_bar: ProgressBar = %DayProgressBar
@onready var interact_label: Label = %InteractLabel
@onready var build_label: Label = %BuildLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var food_warning_label: Label = %FoodWarningLabel
@onready var _compat_wood_label: Label = $WoodLabel
@onready var _compat_stone_label: Label = $StoneLabel
@onready var _compat_food_label: Label = $FoodLabel
@onready var _compat_meal_label: Label = $MealLabel
@onready var _compat_daytime_label: Label = $DayTimeLabel
@onready var threat_label: Label = %ThreatLabel
@onready var threat_direction_label: Label = %ThreatDirectionLabel
@onready var threat_gauge: ProgressBar = %ThreatGauge
@onready var wave_label: Label = %WaveLabel

var _feedback_timer: SceneTreeTimer = null
var _current_workplace: Node = null
var _current_interactable: Node = null
var _daytime_timer: SceneTreeTimer = null

const DAYTIME_REFRESH_INTERVAL := 0.25
const BUILD_TYPE_HINTS := {
	"lumberyard": "Lumberyard - Wood 10",
	"quarry": "Quarry (needs Stone Deposit) - Wood 10",
	"wall": "Wall (16px segment) - Wood 2",
	"gate": "Gate (48px corridor) - Wood 5",
}
## TASK-018-3: shortage/raw-fallback 경고 색. 부족은 선명한 빨강(명확한 경고),
## raw ingredient 소비는 호박색(비효율 소비 안내)으로 구분한다.
const SHORTAGE_WARN_COLOR := Color(1.0, 0.42, 0.35)
const RAW_WARN_COLOR := Color(1.0, 0.72, 0.3)
const THREAT_ALERT_COLOR := Color(0.96, 0.42, 0.36, 1.0)
const THREAT_NORMAL_COLOR := Color(0.78, 0.82, 0.85, 1.0)


func _ready() -> void:
	# TASK-CTRL-001-4: Player proximity prompt 대신 마우스 선택(WorldSelection) 기반
	# interaction prompt로 전환. 선택된 건물/시설의 prompt를 표시한다.
	var selection := get_tree().get_first_node_in_group("world_selection")
	if selection != null and selection.has_signal("selection_changed"):
		selection.selection_changed.connect(_on_interactable_changed)
	VillageResources.changed.connect(_on_resources_changed)
	_on_resources_changed("wood", VillageResources.get_amount("wood"))
	_on_resources_changed("stone", VillageResources.get_amount("stone"))
	_refresh_food_labels()
	# TASK-018-3: 인구 소비 tick 결과로 Food shortage / raw fallback 경고를 갱신.
	var pc := get_tree().root.get_node_or_null("PopulationConsumption")
	if pc != null and pc.has_signal("consumption_tick"):
		pc.consumption_tick.connect(_on_consumption_tick)
		if pc.has_method("get_last_tick"):
			_update_food_warning(pc.get_last_tick())
	GameTime.phase_changed.connect(_on_phase_changed)
	_refresh_daytime()
	ThreatSystem.threat_changed.connect(_on_threat_changed)
	WaveManager.schedule_changed.connect(_on_wave_schedule_changed)
	WaveManager.wave_triggered.connect(_on_wave_triggered)
	_refresh_threat()
	_schedule_daytime_refresh()
	_on_interactable_changed(null)
	var placement: Node = get_tree().get_first_node_in_group("building_placement")
	if placement:
		placement.mode_changed.connect(_on_placement_mode_changed)
		placement.feedback.connect(_on_placement_feedback)
		placement.building_type_changed.connect(_on_building_type_changed)
		_on_placement_mode_changed(placement._active)
		_on_building_type_changed(placement._building_type)


func _on_resources_changed(resource_id: String, _amount: int) -> void:
	if resource_id == "wood":
		wood_label.text = "Wood: %d" % VillageResources.get_amount("wood")
		_compat_wood_label.text = wood_label.text
	elif resource_id == "stone":
		stone_label.text = "Stone: %d" % VillageResources.get_amount("stone")
		_compat_stone_label.text = stone_label.text
	elif _is_food_resource(resource_id):
		_refresh_food_labels()


## TASK-018-3: Food 총재고(FOOD_DEFS 전체 합)를 HUD에 표시한다.
func _food_total() -> int:
	var total := 0
	for food_id in VillageResources.FOOD_DEFS.keys():
		total += VillageResources.get_food(str(food_id))
	for raw_id in CookingRecipes.RAW_EFFICIENCY.keys():
		total += VillageResources.get_amount(str(raw_id))
	return total


func _is_food_resource(resource_id: String) -> bool:
	if VillageResources.is_food(resource_id):
		return true
	if CookingRecipes.get_raw_efficiency(resource_id) > 0.0:
		return true
	for recipe_id in CookingRecipes.get_all_recipe_ids():
		var recipe := CookingRecipes.get_recipe(recipe_id)
		if recipe != null and str(recipe.output) == resource_id:
			return true
	return false


func _meal_total() -> int:
	var total := 0
	for recipe_id in CookingRecipes.get_all_recipe_ids():
		var recipe := CookingRecipes.get_recipe(recipe_id)
		if recipe != null:
			total += VillageResources.get_amount(str(recipe.output))
	return total


func _refresh_food_labels() -> void:
	food_label.text = "Food: %d" % _food_total()
	meal_label.text = "Meal: %d" % _meal_total()
	_compat_food_label.text = food_label.text
	_compat_meal_label.text = meal_label.text


## TASK-018-3: 소비 tick 결과를 Food 경고 라벨에 반영한다.
## SHORTAGE → 붉은 경고(부족량 표기), RAW_FALLBACK → 호박색(비효율 raw 소비 안내),
## OK → 숨김. Label(mouse_filter IGNORE)이라 월드 입력을 차단하지 않는다.
func _on_consumption_tick(result: Dictionary) -> void:
	_update_food_warning(result)


func _update_food_warning(result: Dictionary) -> void:
	var pc := get_tree().root.get_node_or_null("PopulationConsumption")
	if pc == null or result.is_empty():
		food_warning_label.visible = false
		return
	var state := int(result.get("state", pc.TickState.OK))
	if state == pc.TickState.SHORTAGE:
		food_warning_label.text = "Food Shortage: -%d today" \
				% int(result.get("shortage", 0))
		food_warning_label.add_theme_color_override("font_color", SHORTAGE_WARN_COLOR)
		food_warning_label.visible = true
	elif state == pc.TickState.RAW_FALLBACK:
		food_warning_label.text = "Raw ingredients eaten: %d (low efficiency)" \
				% int(result.get("consumed_raw", 0))
		food_warning_label.add_theme_color_override("font_color", RAW_WARN_COLOR)
		food_warning_label.visible = true
	else:
		food_warning_label.visible = false


func _on_phase_changed(_phase: int, _day_number: int) -> void:
	_refresh_daytime()
	_refresh_threat()


func _schedule_daytime_refresh() -> void:
	_daytime_timer = get_tree().create_timer(DAYTIME_REFRESH_INTERVAL)
	_daytime_timer.timeout.connect(_on_daytime_refresh_timeout)


func _on_daytime_refresh_timeout() -> void:
	if not is_inside_tree():
		return
	_refresh_daytime()
	_refresh_threat()
	_schedule_daytime_refresh()


func _refresh_daytime() -> void:
	daytime_label.text = "%s %d  %d%%" % [
		GameTime.get_phase_name(),
		GameTime.get_day_number(),
		int(GameTime.get_phase_progress() * 100.0),
	]
	_compat_daytime_label.text = daytime_label.text
	day_progress_bar.value = GameTime.get_phase_progress() * 100.0


func _on_threat_changed(_current: float, _max_threat: float) -> void:
	_refresh_threat()


func _on_wave_schedule_changed(_nights_until_wave: int, _wave_index: int) -> void:
	_refresh_threat()


func _on_wave_triggered(_wave_index: int, _night_number: int) -> void:
	_refresh_threat()


func _refresh_threat() -> void:
	var ratio: float = ThreatSystem.get_ratio()
	threat_gauge.max_value = 100.0
	threat_gauge.value = ratio * 100.0
	threat_label.text = "Threat %d%%" % int(ratio * 100.0)
	var growing := ThreatSystem.is_auto_growing() and GameTime.get_time_scale() > 0.0
	threat_direction_label.text = "!" if ratio >= 1.0 else ("▲" if growing else "")
	var nights: int = WaveManager.get_nights_until_wave()
	var forced := ratio >= WaveManager.wave_threshold_ratio
	if GameTime.get_phase() == GameTime.Phase.NIGHT and WaveManager.is_wave_night():
		wave_label.text = "WAVE NOW"
		_set_wave_alert(true)
	elif forced or nights <= 0:
		wave_label.text = "WAVE NEXT NIGHT"
		_set_wave_alert(true)
	elif nights == 1:
		wave_label.text = "Wave in 1 night"
		_set_wave_alert(false)
	else:
		wave_label.text = "Wave in %d nights" % nights
		_set_wave_alert(false)


func _set_wave_alert(alert: bool) -> void:
	wave_label.add_theme_color_override("font_color",
		THREAT_ALERT_COLOR if alert else THREAT_NORMAL_COLOR)


func _on_interactable_changed(interactable: Node) -> void:
	_disconnect_workplace()
	_current_interactable = interactable
	if interactable:
		interact_label.text = "Click - %s" % interactable.prompt
		interact_label.visible = true
		var workplace: Node = null
		if interactable.has_method("get_lumberyard"):
			workplace = interactable.get_lumberyard()
		elif interactable.has_method("get_quarry"):
			workplace = interactable.get_quarry()
		if is_instance_valid(workplace) and workplace.has_signal("workers_changed") \
				and not workplace.workers_changed.is_connected(_refresh_interact_label):
			_current_workplace = workplace
			workplace.workers_changed.connect(_refresh_interact_label)
	else:
		interact_label.visible = false


func _disconnect_workplace() -> void:
	if is_instance_valid(_current_workplace) \
			and _current_workplace.workers_changed.is_connected(_refresh_interact_label):
		_current_workplace.workers_changed.disconnect(_refresh_interact_label)
	_current_workplace = null


func _refresh_interact_label(_filled: int = 0, _capacity: int = 0) -> void:
	if not is_instance_valid(_current_interactable):
		return
	interact_label.text = "Click - %s" % _current_interactable.prompt


func _on_placement_mode_changed(active: bool) -> void:
	build_label.visible = active
	feedback_label.visible = false


func _on_building_type_changed(building_type: String) -> void:
	build_label.text = "%s\n1/2/3/4: Select Building / R: Remove / Left Click: Build / ESC: Cancel" \
			% BUILD_TYPE_HINTS.get(building_type, building_type)


func _on_placement_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true
	if _feedback_timer:
		_feedback_timer.timeout.disconnect(_hide_feedback)
	_feedback_timer = get_tree().create_timer(2.0)
	_feedback_timer.timeout.connect(_hide_feedback)


func _hide_feedback() -> void:
	feedback_label.visible = false
