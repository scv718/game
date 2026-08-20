extends Node2D
class_name Decoration

## TASK-008-2 장식용 오브젝트.
## 순수 시각 전용이다. CollisionShape2D/StaticBody2D를 갖지 않아
## 내비게이션 baking과 건설 배치 판정에 일절 영향을 주지 않는다.
## (역할 규칙: 장식은 절대 이동/건설을 막지 않는다. 막는 역할은 Tree/건물이 담당.)

const ROCK_TEXTURE := preload("res://assets/tiny_swords/generated/deco_rock1.png")
const BUSH_TEXTURE := preload("res://assets/tiny_swords/generated/deco_bush1.png")

var _visual: Sprite2D = null

func _ready() -> void:
	add_to_group("decorations")
	_visual = $Visual
	if _visual.texture == null:
		_visual.texture = ROCK_TEXTURE


func setup(type: String, scale_multiplier: float = 1.0) -> void:
	_visual = $Visual
	if type == "bush":
		_visual.texture = BUSH_TEXTURE
		_visual.offset = Vector2(-31, -23)
	else:
		_visual.texture = ROCK_TEXTURE
		_visual.offset = Vector2(-16, -13)
	_visual.scale = Vector2(scale_multiplier, scale_multiplier)