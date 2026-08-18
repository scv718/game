extends AnimatedSprite2D

const DIRS := ["down", "up", "left", "right"]

@onready var _parent: CharacterBody2D = get_parent() as CharacterBody2D


func _physics_process(_delta: float) -> void:
	var v: Vector2 = _parent.velocity
	if v.length_squared() < 1.0:
		if animation.begins_with("walk_"):
			animation = "idle_" + animation.trim_prefix("walk_")
		return
	var dir: int
	if absf(v.x) >= absf(v.y):
		dir = 3 if v.x > 0.0 else 2
	else:
		dir = 0 if v.y > 0.0 else 1
	var target: String = DIRS[dir] + "_walk"
	if animation != target:
		animation = target