extends Node

signal language_changed(locale: String)
signal camera_speed_changed(multiplier: float)

const SETTINGS_PATH := "user://game_settings.cfg"
const SUPPORTED_LOCALES := ["ko", "en"]

var locale := "ko"
var camera_speed_multiplier := 1.0

const TEXT := {
	"options": {"ko": "옵션", "en": "Options"},
	"resume": {"ko": "게임 계속", "en": "Resume Game"},
	"camera_speed": {"ko": "화면 이동 속도", "en": "Camera Move Speed"},
	"language": {"ko": "언어", "en": "Language"},
	"korean": {"ko": "한국어", "en": "Korean"},
	"english": {"ko": "영어", "en": "English"},
	"controls": {"ko": "화면 가장자리 이동 · 마우스 휠 확대/축소 · ESC 옵션", "en": "Edge scroll · Mouse wheel zoom · ESC options"},
	"minimap": {"ko": "미니맵", "en": "Minimap"},
	"world_map": {"ko": "월드 지도", "en": "World Map"},
	"map_hint": {"ko": "M: 닫기 | ESC: 닫기 | 지역 표식 클릭: 선택 | 노란 선: 현재 화면", "en": "M: Close | ESC: Close | Click region marker: Select | Yellow outline: Camera view"},
	"close_m": {"ko": "닫기 (M)", "en": "Close (M)"},
	"region_none": {"ko": "지역: 선택 없음", "en": "Region: none"},
	"region_click": {"ko": "지도에서 지역 표식을 선택하세요.", "en": "Click a region marker on the map."},
	"explore": {"ko": "탐험", "en": "Explore"},
	"exploring": {"ko": "탐험 중...", "en": "Exploring..."},
	"discovered": {"ko": "발견 완료", "en": "Discovered"},
	"wood": {"ko": "목재", "en": "Wood"},
	"stone": {"ko": "석재", "en": "Stone"},
	"food": {"ko": "식량", "en": "Food"},
	"meal": {"ko": "식사", "en": "Meal"},
	"threat": {"ko": "위협", "en": "Threat"},
	"wave_now": {"ko": "현재 적의 습격!", "en": "WAVE NOW"},
	"wave_next": {"ko": "다음 밤에 습격", "en": "WAVE NEXT NIGHT"},
	"wave_one": {"ko": "1일 밤 후 습격", "en": "Wave in 1 night"},
	"wave_many": {"ko": "%d일 밤 후 습격", "en": "Wave in %d nights"},
	"day": {"ko": "낮", "en": "DAY"},
	"night": {"ko": "밤", "en": "NIGHT"},
	"build_help": {"ko": "1/2/3/4: 건물 선택 / R: 철거 / 좌클릭: 건설 / 우클릭: 취소", "en": "1/2/3/4: Select Building / R: Remove / Left Click: Build / Right Click: Cancel"},
	"catalog_title": {"ko": "건물 카탈로그  •  Cuteskull 에셋", "en": "BUILDING CATALOG  •  Cuteskull Asset Library"},
	"catalog_hint": {"ko": "에셋 선택 • 무료 건설 • R 회전 • 클릭 배치 • 우클릭 취소", "en": "Select an asset • Free build • R rotate • Click place • Right click cancel"},
	"free": {"ko": "무료", "en": "Free"},
	"buildings": {"ko": "건물", "en": "Buildings"},
	"defense": {"ko": "방어", "en": "Defense"},
	"castle_parts": {"ko": "성곽 부품", "en": "Castle Parts"},
	"market_props": {"ko": "시장 / 소품", "en": "Market / Props"},
	"environment": {"ko": "환경", "en": "Environment"},
	"characters": {"ko": "캐릭터", "en": "Characters"},
}

const STATIC_UI_PAIRS := {
	"Tactical Command (NIGHT)": "지휘 명령 (밤)",
	"Defense Zone": "방어 구역", "Command": "명령", "Regroup": "집결",
	"Retreat": "후퇴", "Focus Target": "집중 공격 대상", "Gate": "성문",
	"Tactical Time": "전술 시간", "Death Ledger": "전멸 기록",
	"Fallen records (information only)": "전멸 기록 (정보 확인용)",
	"Close": "닫기", "Tavern - Recruitment": "주점 - 고용",
	"Inn - Workforce Management": "여관 - 인력 관리", "Upgrade": "업그레이드",
	"Dungeon Preparation": "던전 준비", "Close (P)": "닫기 (P)",
	"Tier - | State: - | Encounter: -": "등급 - | 상태: - | 조우: -",
	"Risk: -": "위험도: -", "Expected reward: -": "예상 보상: -",
	"Party members (required min/max from dungeon)": "파티원 (던전별 최소/최대 인원)",
	"Add": "추가", "Food/Supply slot (optional)": "식량/보급 슬롯 (선택)",
	"food id (optional)": "식량 ID (선택)",
	"Potion slots (optional, comma separated)": "물약 슬롯 (선택, 쉼표로 구분)",
	"potion ids (optional)": "물약 ID (선택)",
	"Equipment summary (optional, comma separated)": "장비 목록 (선택, 쉼표로 구분)",
	"equipment summary (optional)": "장비 목록 (선택)",
	"NOT READY": "준비되지 않음", "Depart": "출발",
}


func _ready() -> void:
	_load_settings()
	TranslationServer.set_locale(locale)


func text(key: String, args: Array = []) -> String:
	var entry: Dictionary = TEXT.get(key, {})
	var value := str(entry.get(locale, entry.get("en", key)))
	return value % args if not args.is_empty() else value


func set_language(value: String) -> void:
	if not value in SUPPORTED_LOCALES or value == locale:
		return
	locale = value
	TranslationServer.set_locale(locale)
	_save_settings()
	language_changed.emit(locale)
	apply_to_current_scene()


func set_camera_speed(value: float) -> void:
	var next := clampf(value, 0.5, 3.0)
	if is_equal_approx(next, camera_speed_multiplier):
		return
	camera_speed_multiplier = next
	_save_settings()
	camera_speed_changed.emit(camera_speed_multiplier)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved_locale := str(config.get_value("accessibility", "language", locale))
	if saved_locale in SUPPORTED_LOCALES:
		locale = saved_locale
	camera_speed_multiplier = clampf(float(config.get_value(
		"controls", "camera_speed", camera_speed_multiplier)), 0.5, 3.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("accessibility", "language", locale)
	config.set_value("controls", "camera_speed", camera_speed_multiplier)
	config.save(SETTINGS_PATH)


func apply_to_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		localize_tree(scene)
		return
	# Script-driven tests and capture tools can attach Main3D directly without
	# assigning current_scene; keep language behavior identical in that mode.
	for child in get_tree().root.get_children():
		if child != self:
			localize_tree(child)


func localize_tree(node: Node) -> void:
	if node is Label or node is Button:
		node.text = _localized_static(str(node.text))
	if node is LineEdit:
		node.placeholder_text = _localized_static(str(node.placeholder_text))
	for child in node.get_children():
		localize_tree(child)


func _localized_static(current: String) -> String:
	for english in STATIC_UI_PAIRS:
		var korean: String = STATIC_UI_PAIRS[english]
		if current == english or current == korean:
			return korean if locale == "ko" else english
	return current
