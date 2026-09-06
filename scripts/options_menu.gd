extends CanvasLayer

@onready var panel: Control = $Backdrop/Panel
@onready var title_label: Label = %TitleLabel
@onready var speed_label: Label = %SpeedLabel
@onready var speed_value: Label = %SpeedValue
@onready var speed_slider: HSlider = %SpeedSlider
@onready var language_label: Label = %LanguageLabel
@onready var language_select: OptionButton = %LanguageSelect
@onready var controls_label: Label = %ControlsLabel
@onready var resume_button: Button = %ResumeButton

var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("blocks_world_input")
	visible = false
	speed_slider.value_changed.connect(_on_speed_changed)
	language_select.item_selected.connect(_on_language_selected)
	resume_button.pressed.connect(close)
	GameSettings.language_changed.connect(_refresh_text)
	_refresh_controls()
	_refresh_text()
	GameSettings.call_deferred("apply_to_current_scene")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
		return
	if _another_modal_is_open():
		return
	open()
	get_viewport().set_input_as_handled()


func open() -> void:
	_was_paused = get_tree().paused
	visible = true
	get_tree().paused = true
	_refresh_controls()
	resume_button.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = _was_paused


func is_open() -> bool:
	return visible


func _another_modal_is_open() -> bool:
	for node in get_tree().get_nodes_in_group("world_map_overlay"):
		if node != self and node.has_method("is_open") and node.is_open():
			return true
	return false


func _refresh_controls() -> void:
	speed_slider.set_value_no_signal(GameSettings.camera_speed_multiplier)
	language_select.select(0 if GameSettings.locale == "ko" else 1)
	_refresh_speed_value(GameSettings.camera_speed_multiplier)


func _refresh_text(_locale: String = "") -> void:
	title_label.text = GameSettings.text("options")
	speed_label.text = GameSettings.text("camera_speed")
	language_label.text = GameSettings.text("language")
	controls_label.text = GameSettings.text("controls")
	resume_button.text = GameSettings.text("resume")
	language_select.set_item_text(0, GameSettings.text("korean"))
	language_select.set_item_text(1, GameSettings.text("english"))
	_refresh_speed_value(GameSettings.camera_speed_multiplier)


func _on_speed_changed(value: float) -> void:
	GameSettings.set_camera_speed(value)
	_refresh_speed_value(value)


func _refresh_speed_value(value: float) -> void:
	speed_value.text = "%d%%" % int(round(value * 100.0))


func _on_language_selected(index: int) -> void:
	GameSettings.set_language("ko" if index == 0 else "en")
