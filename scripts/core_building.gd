extends Building
class_name CoreBuilding

## TASK-011-1 중앙 핵심 마을 기본 건물.
## 거점/주점/여관/식료품점/장비점은 시작부터 월드에 존재하는 핵심 업그레이드 건물이다.
## BuildingPlacement로 새로 짓는 대상이 아니며, 이 태스크에서는 배치/식별/최소 prompt만 제공한다.
## 실제 업그레이드 효과/비용 시스템은 구현하지 않는다. level 개념만 1로 유지한다.
## 주점/여관의 고용/Roster 기능은 후속 TASK-011-3/4에서 연결한다.

@export var core_type: String = "tavern"

const CONFIGS := {
	"keep": {
		"label": "거점",
		"texture": "res://assets/tiny_swords/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Castle.png",
		"region": Rect2(4, 41, 312, 208),
		"scale": 0.4,
		"offset": Vector2(-62.4, -83.2),
	},
	"tavern": {
		"label": "주점",
		"texture": "res://assets/tiny_swords/Tiny Swords (Free Pack)/Buildings/Blue Buildings/House1.png",
		"region": Rect2(8, 16, 112, 157),
		"scale": 0.5,
		"offset": Vector2(-28.0, -78.5),
	},
	"inn": {
		"label": "여관",
		"texture": "res://assets/tiny_swords/Tiny Swords (Free Pack)/Buildings/Blue Buildings/House2.png",
		"region": Rect2(0, 23, 128, 155),
		"scale": 0.5,
		"offset": Vector2(-32.0, -77.5),
	},
	"grocery": {
		"label": "식료품점",
		"texture": "res://assets/tiny_swords/Tiny Swords (Free Pack)/Buildings/Blue Buildings/House3.png",
		"region": Rect2(3, 37, 122, 135),
		"scale": 0.5,
		"offset": Vector2(-30.5, -67.5),
	},
	"equipment": {
		"label": "장비점",
		"texture": "res://assets/tiny_swords/Tiny Swords (Free Pack)/Buildings/Blue Buildings/Archery.png",
		"region": Rect2(3, 61, 183, 179),
		"scale": 0.5,
		"offset": Vector2(-45.75, -89.5),
	},
}

@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	super._ready()
	add_to_group("core_buildings")
	_apply_config()


func _apply_config() -> void:
	if _visual == null:
		return
	var cfg: Dictionary = CONFIGS.get(core_type, CONFIGS["tavern"])
	var atlas := AtlasTexture.new()
	atlas.atlas = load(String(cfg["texture"]))
	atlas.region = cfg["region"]
	_visual.texture = atlas
	_visual.scale = Vector2(cfg["scale"], cfg["scale"])
	_visual.position = cfg["offset"]


func get_core_type() -> String:
	return core_type


func get_level() -> int:
	return 1


func get_building_label() -> String:
	return String(CONFIGS.get(core_type, CONFIGS["tavern"])["label"])


func get_interact_prompt() -> String:
	return "%s (Lv.%d)" % [get_building_label(), get_level()]
