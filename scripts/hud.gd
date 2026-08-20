extends Control

@onready var wood_label: Label = %WoodLabel
@onready var stone_label: Label = %StoneLabel
@onready var daytime_label: Label = %DayTimeLabel
@onready var interact_label: Label = %InteractLabel
@onready var build_label: Label = %BuildLabel
@onready var feedback_label: Label = %FeedbackLabel

var player: Node
var _feedback_timer: SceneTreeTimer = null
var _current_workplace: Node = null
var _current_interactable: Node = null
var _daytime_timer: SceneTreeTimer = null

const DAYTIME_REFRESH_INTERVAL := 0.25
const BUILD_TYPE_HINTS := {
	"lumberyard": "Lumberyard - Wood 10",
	"quarry": "Quarry (needs Stone Deposit) - Wood 10",
}


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.current_interactable_changed.connect(_on_interactable_changed)
	VillageResources.changed.connect(_on_resources_changed)
	_on_resources_changed("wood", VillageResources.get_amount("wood"))
	_on_resources_changed("stone", VillageResources.get_amount("stone"))
	GameTime.phase_changed.connect(_on_phase_changed)
	_refresh_daytime()
	_schedule_daytime_refresh()
	_on_interactable_changed(player.current_interactable if player else null)
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
	elif resource_id == "stone":
		stone_label.text = "Stone: %d" % VillageResources.get_amount("stone")


func _on_phase_changed(_phase: int, _day_number: int) -> void:
	_refresh_daytime()


func _schedule_daytime_refresh() -> void:
	_daytime_timer = get_tree().create_timer(DAYTIME_REFRESH_INTERVAL)
	_daytime_timer.timeout.connect(_on_daytime_refresh_timeout)


func _on_daytime_refresh_timeout() -> void:
	if not is_inside_tree():
		return
	_refresh_daytime()
	_schedule_daytime_refresh()


func _refresh_daytime() -> void:
	daytime_label.text = "%s %d  %d%%" % [
		GameTime.get_phase_name(),
		GameTime.get_day_number(),
		int(GameTime.get_phase_progress() * 100.0),
	]


func _on_interactable_changed(interactable: Node) -> void:
	_disconnect_workplace()
	_current_interactable = interactable
	if interactable:
		interact_label.text = "E - %s" % interactable.prompt
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
	interact_label.text = "E - %s" % _current_interactable.prompt


func _on_placement_mode_changed(active: bool) -> void:
	build_label.visible = active
	feedback_label.visible = false


func _on_building_type_changed(building_type: String) -> void:
	build_label.text = "%s\n1/2: Select Building / Left Click: Build / ESC: Cancel" \
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