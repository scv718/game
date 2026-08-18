extends ResourceNode
class_name WorldTree

enum State { MATURE, STUMP }

@export var regrow_time: float = 20.0

var state: State = State.MATURE
var _regrow_timer: SceneTreeTimer = null

@onready var _canopy: Polygon2D = $Canopy
@onready var _trunk_visual: Polygon2D = $TrunkVisual
@onready var _stump_visual: Polygon2D = $StumpVisual


func _on_depleted() -> void:
	state = State.STUMP
	_canopy.visible = false
	_trunk_visual.visible = false
	_stump_visual.visible = true
	if _regrow_timer != null or not is_inside_tree():
		return
	_regrow_timer = get_tree().create_timer(regrow_time)
	_regrow_timer.timeout.connect(_regrow)


func _regrow() -> void:
	_regrow_timer = null
	if not is_inside_tree() or state != State.STUMP:
		return
	current_amount = max_amount
	state = State.MATURE
	_canopy.visible = true
	_trunk_visual.visible = true
	_stump_visual.visible = false