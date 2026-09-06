extends Control
class_name MoraleUI

## TASK-023-3 Morale UI.
## 현재 사기(current morale), 주요 기여자(major contributor), 전역 공격 보너스(bonus)
## 를 표시한다. 데이터는 MoraleSystem3D(그룹 "morale_system")의 MoraleState /
## MoraleBonusHook에서 읽는다.
##
## HUMAN_CHECK 관점:
##   - 강한 동료를 지키는 가치가 보이도록 총 사기와 최고 기여자를 함께 보여준다.
##   - 수치가 과도하게 복잡하지 않도록 소수 첫째 자리까지 + 기여자 상위 3명만 표시한다.
##   - 사망 충격(보너스 감소)이 보이도록 bonus multiplier를 함께 표시한다.

@onready var _morale_label: Label = %MoraleValue
@onready var _contributors_label: Label = %MajorContributors
@onready var _bonus_label: Label = %BonusValue
@onready var _title: Label = $MoralePanel/Title
@onready var _morale_caption: Label = $MoralePanel/MoraleRow/MoraleCaption
@onready var _bonus_caption: Label = $MoralePanel/BonusRow/BonusCaption
@onready var _contributors_caption: Label = $MoralePanel/ContributorsCaption

var _system: Node = null


func _ready() -> void:
	add_to_group("morale_ui")
	GameSettings.language_changed.connect(_on_language_changed)
	_on_language_changed(GameSettings.locale)
	_system = get_tree().get_first_node_in_group("morale_system")
	if _system == null:
		# main_3d.tscn에서 MoraleUI(HUD)가 MoraleSystem3D보다 먼저 _ready에
		# 도달하므로, 시스템이 그룹에 합류한 뒤 지연 조회로 연결한다.
		_system_ready.call_deferred()
		return
	_connect_system()
	_refresh()


func _system_ready() -> void:
	_system = get_tree().get_first_node_in_group("morale_system")
	if _system == null or not is_instance_valid(_system):
		return
	_connect_system()
	_refresh()


func _connect_system() -> void:
	if _system != null and _system.has_signal("changed") \
			and not _system.changed.is_connected(_refresh):
		_system.changed.connect(_refresh)


func _refresh() -> void:
	_system = get_tree().get_first_node_in_group("morale_system")
	if _system == null or not is_instance_valid(_system):
		return
	var st: MoraleState = _system.state
	var hook: MoraleBonusHook = _system.bonus_hook
	if st == null or hook == null:
		return
	var total: float = st.get_total_morale()
	_morale_label.text = "%.1f" % total
	var mult: float = hook.get_attack_multiplier()
	var pct: int = roundi((mult - 1.0) * 100.0)
	_bonus_label.text = "+%d%%" % pct if pct > 0 else "0%"
	var lines: Array[String] = []
	for c in st.get_major_contributors(3):
		lines.append("%s Lv.%d (+%.1f)" % [c.display_name, c.level, st.contribution_of(c)])
	if lines.is_empty():
		lines.append("강한 동료 없음" if GameSettings.locale == "ko" else "No strong allies")
	_contributors_label.text = "\n".join(lines)


func _on_language_changed(_locale: String) -> void:
	var korean := GameSettings.locale == "ko"
	_title.text = "사기" if korean else "Morale"
	_morale_caption.text = "현재:" if korean else "Current:"
	_bonus_caption.text = "공격 보너스:" if korean else "Attack bonus:"
	_contributors_caption.text = "주요 동료:" if korean else "Key allies:"
	_refresh()
