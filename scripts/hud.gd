extends Control

@onready var wood_label: Label = %WoodLabel
@onready var interact_label: Label = %InteractLabel
@onready var build_label: Label = %BuildLabel
@onready var feedback_label: Label = %FeedbackLabel

var player: Node
var _feedback_timer: SceneTreeTimer = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.current_interactable_changed.connect(_on_interactable_changed)
	VillageResources.changed.connect(_on_resources_changed)
	_on_resources_changed("wood", VillageResources.get_amount("wood"))
	_on_interactable_changed(player.current_interactable if player else null)
	var placement: Node = get_tree().get_first_node_in_group("building_placement")
	if placement:
		placement.mode_changed.connect(_on_placement_mode_changed)
		placement.feedback.connect(_on_placement_feedback)
		_on_placement_mode_changed(placement._active)


func _on_resources_changed(resource_id: String, _amount: int) -> void:
	if resource_id == "wood":
		wood_label.text = "Wood: %d" % VillageResources.get_amount("wood")


func _on_interactable_changed(interactable: Node) -> void:
	if interactable:
		interact_label.text = "E - %s" % interactable.prompt
		interact_label.visible = true
	else:
		interact_label.visible = false


func _on_placement_mode_changed(active: bool) -> void:
	build_label.visible = active
	feedback_label.visible = false


func _on_placement_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.visible = true
	if _feedback_timer:
		_feedback_timer.timeout.disconnect(_hide_feedback)
	_feedback_timer = get_tree().create_timer(2.0)
	_feedback_timer.timeout.connect(_hide_feedback)


func _hide_feedback() -> void:
	feedback_label.visible = false