extends Node3D
class_name CharacterRig3D

## TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype.
## Quaternius Universal Base Characters + Modular Outfits + Universal Animation
## Library를 gameplay 키로 조립하는 공용 캐릭터 visual/animation 리그다.
##
## - body_key는 VisualAssetCatalog3D.ENTRIES의 humanoid 모델 키다. 실측 결과
##   base character / outfit 완성 세트는 전부 동일한 65본 리그(본 이름 집합
##   일치, auto_dev/VIS_CHARACTER_ANIM_REPORT.md)라 어떤 조합에도 같은 공용
##   애니메이션이 그대로 재생된다. Worker/Mercenary variant는 body_key 교체만으로
##   만들어지며 별도 visual 인스턴스 재생성이 없다.
## - 애니메이션 단일 소스는 VisualAssetCatalog3D.ANIMATION_SETS(action -> 후보)
##   이다. UAL GLB 원본 Animation resource를 변형하지 않기 위해 loop 정책 반영 시
##   duplicate한 사본을 static 캐시로 공유한다(리그 인스턴스 수와 무관 1회 생성).
## - AnimationTree는 사용하지 않는다(요구사항: 필요 이상의 state graph 금지).
##   기능 도메인(WRK/CMB)은 play_action() 호출만으로 상태 훅을 연결하고,
##   재생 실패(false 반환)로 상태 머신이 멈추지 않아야 한다(VIS-002-2 계약).
## - tool attach는 Skeleton3D 아래 BoneAttachment3D(HAND_BONE) 하나다. 도구
##   배율은 catalog의 hand attach scale_hint(attachment_scale_hint_for_key)를
##   따른다. grip 미세 조정은 set_tool_grip_transform()으로 wiring 태스크가
##   한다. 방향 전환은 rig root yaw 회전만으로 처리되며 sprite 개념이 없다.
##
## 소유 경계: 이 스크립트는 visual/animation 조립만 한다. 이동/facing/state
## machine/충돌은 WRK/CMB 도메인 Actor3D 소유이며, 그쪽에서 이 리그를 자식으로
## 둔다(INTEGRATION_NOTE_VIS.md 참조).

## tool attach 대상 손 본. UAL/base/outfit 공용 리그의 오른손.
const HAND_BONE := "hand_r"

## loop 재생 action(idle/walk/work). combat/hit/death는 1회성 재생이다.
const LOOPING_ACTIONS := ["idle", "walk", "work"]

## action 전환 blend 시간(초).
const ACTION_BLEND := 0.25

## 실측 호환이 확인된 humanoid body 키 프리셋(65본 리그 일치, 리포트 참조).
const BODY_BASE_MALE := "human/male_base"
const BODY_BASE_FEMALE := "human/female_base"
const BODY_WORKER_PEASANT_MALE := "outfit/male_peasant_full"
const BODY_WORKER_PEASANT_FEMALE := "outfit/female_peasant_full"
const BODY_MERCENARY_RANGER_MALE := "outfit/male_ranger_full"

## tool grip 기본 transform. bone space에서의 미세 조정은 wiring(VIS-002)이
## set_tool_grip_transform()으로 하며, 이 값은 "손 위에 세워 든" 기본값이다.
const DEFAULT_TOOL_GRIP_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.04, 0.03))

@export var body_key: String = BODY_WORKER_PEASANT_MALE:
	set(value):
		body_key = value
		if is_inside_tree() and is_node_ready():
			_build_body()
@export var tool_key: String = ""
@export var initial_action: String = "idle"

## 공용 Animation 사본 캐시(key: "library::name::loop"). static이라 리그 수와
## 무관하게 1벌만 유지된다. 값은 null일 수도 있다(없는 이름의 실패 확정 캐시).
static var _shared_animations: Dictionary = {}

var _body: Node3D = null
var _skeleton: Skeleton3D = null
var _anim_player: AnimationPlayer = null
var _tool_attachment: BoneAttachment3D = null
var _installed_actions: Dictionary = {}
var _current_action := ""


func _ready() -> void:
	add_to_group("character_rig_3d")
	_build_body()


## body_key 모델을 인스턴스화하고 공용 애니메이션/tool/action을 장착한다.
## 기존 body가 있으면 통째로 교체한다(재생성 없이는 방향 전환만 있다는 요구와
## 무관하게, variant 교체는 명시적 body_key 변경 시에만 일어난다).
func _build_body() -> void:
	var model := VisualAssetCatalog3D.instantiate_model(body_key)
	if model == null:
		return
	for child in get_children():
		child.free()
	_body = null
	_skeleton = null
	_anim_player = null
	_tool_attachment = null
	_current_action = ""
	_body = model
	add_child(_body)
	_skeleton = _find_skeleton(_body)
	if _skeleton == null:
		push_error("CharacterRig3D: body '%s' has no Skeleton3D" % body_key)
		return
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "SharedAnimPlayer"
	_body.add_child(_anim_player)
	_install_shared_animations()
	if not tool_key.is_empty():
		attach_tool(tool_key)
	if not initial_action.is_empty():
		play_action(initial_action)


## VisualAssetCatalog3D.ANIMATION_SETS의 후보를 전부 설치한다. 첫 성공 후보가
## 해당 action의 primary다(나머지는 fallback으로 함께 설치).
func _install_shared_animations() -> void:
	_installed_actions.clear()
	var library := AnimationLibrary.new()
	for action in VisualAssetCatalog3D.animation_actions():
		for candidate in VisualAssetCatalog3D.animations_for_action(action):
			var anim_name: String = candidate["name"]
			if not library.has_animation(anim_name):
				var anim := _shared_animation(candidate["library"], anim_name,
					action in LOOPING_ACTIONS)
				if anim == null:
					continue
				library.add_animation(anim_name, anim)
			if not _installed_actions.has(action):
				_installed_actions[action] = anim_name
	_anim_player.add_animation_library("", library)


## action("idle"/"walk"/"work"/"combat"/"hit"/"death") 재생. 설치된 primary가
## 없으면 false(호출부 상태 머신은 멈추지 않고 다음 상태로 간다).
func play_action(action: String) -> bool:
	if _anim_player == null or not _installed_actions.has(action):
		return false
	_current_action = action
	_anim_player.play(_installed_actions[action], ACTION_BLEND)
	return true


## 현재 action 문자열. 재생 실패/미설치면 빈 문자열.
func current_action() -> String:
	return _current_action


## ANIMATION_SETS 후보가 설치된 실제 animation 이름. 미설치면 빈 문자열.
func installed_animation_name(action: String) -> String:
	return _installed_actions.get(action, "")


func has_action(action: String) -> bool:
	return _installed_actions.has(action)


## tool(catalog key)을 HAND_BONE에 부착한다. 기존 tool은 교체한다.
func attach_tool(catalog_key: String) -> Node3D:
	detach_tool()
	if _skeleton == null or not _skeleton.is_inside_tree():
		push_error("CharacterRig3D: cannot attach tool without a built skeleton")
		return null
	var model := VisualAssetCatalog3D.instantiate_model(catalog_key)
	if model == null:
		return null
	if _skeleton.find_bone(HAND_BONE) < 0:
		push_error("CharacterRig3D: hand bone '%s' missing on '%s'"
			% [HAND_BONE, body_key])
		model.free()
		return null
	_tool_attachment = BoneAttachment3D.new()
	_tool_attachment.name = "ToolAttachment"
	_skeleton.add_child(_tool_attachment)
	_tool_attachment.bone_name = HAND_BONE
	_tool_attachment.add_child(model)
	model.transform = DEFAULT_TOOL_GRIP_TRANSFORM
	var hint := VisualAssetCatalog3D.attachment_scale_hint_for_key(catalog_key)
	model.scale = Vector3.ONE * hint
	return model


func detach_tool() -> void:
	if _tool_attachment != null and is_instance_valid(_tool_attachment):
		_tool_attachment.queue_free()
	_tool_attachment = null


## grip 미세 조정(wiring 태스크용). bone space 기준이다.
func set_tool_grip_transform(grip: Transform3D) -> void:
	if _tool_attachment != null and _tool_attachment.get_child_count() > 0:
		(_tool_attachment.get_child(0) as Node3D).transform = grip


func get_skeleton() -> Skeleton3D:
	return _skeleton


func get_animation_player() -> AnimationPlayer:
	return _anim_player


func get_tool_attachment() -> BoneAttachment3D:
	return _tool_attachment


## UAL GLB 원본에서 Animation을 꺼내 loop 정책만 반영한 사본을 돌려준다.
## 원본 import resource는 변형하지 않는다(공유 캐시 오염 방지). 없는 이름은
## null로 확정 캐시해 반복 탐색이 없다.
static func _shared_animation(library_key: String, anim_name: String, looping: bool) -> Animation:
	var cache_key := "%s::%s::loop=%s" % [library_key, anim_name, looping]
	if _shared_animations.has(cache_key):
		return _shared_animations[cache_key]
	var result: Animation = null
	var source_path := VisualAssetCatalog3D.get_model_path(library_key)
	if source_path.is_empty():
		push_error("CharacterRig3D: unknown animation library key '%s'" % library_key)
	else:
		var source_scene := load(source_path) as PackedScene
		if source_scene == null:
			push_error("CharacterRig3D: failed to load animation library '%s'" % source_path)
		else:
			var instance := source_scene.instantiate()
			var player := _find_animation_player(instance)
			if player != null and player.has_animation(anim_name):
				result = (player.get_animation(anim_name) as Animation).duplicate()
				result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
			instance.free()
	if result == null:
		push_warning("CharacterRig3D: animation '%s' not found in '%s'" % [anim_name, library_key])
	_shared_animations[cache_key] = result
	return result


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
