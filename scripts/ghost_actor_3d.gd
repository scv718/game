extends EnemyActor3D
class_name GhostActor3D

## TASK-025-2 Ghost Actor. 기존 EnemyActor3D의 전투 FSM(이동/교전/Gate Breach)을 그대로
## 재사용하되 다음만 변경한다.
##   - Ghost visual: 반투명/발광 처리로 일반 Enemy와 구분(TASK-017-3 최소 표현).
##   - 원본 identity: setup_ghost로 원본 DeathRecord id / source_uid를 보유한다.
##   - 사망 기록: _record_death를 오버라이드해 신규 DeathRecord를 만들지 않고(재귀 방지)
##     원본 record를 RESOLVED 처리한다. DAY cleanup/despawn은 queue_free 직접 호출이므로
##     record 상태를 바꾸지 않는다.
## 별도 anti-ghost 시스템은 만들지 않으며, Portal/Wave를 제어하지 않는다.

var source_record_id := ""
var source_uid := ""


## Spawn Mix가 identity/기록 링크를 설정한다. add_child 전에 호출되므로 ghost visual은
## _ready(부모 _ready 완료 후)에서 적용한다.
func setup_ghost(p_id: String, p_name: String, p_direction: String, record_id: String, p_source_uid: String) -> void:
	setup(p_id, p_name, p_direction)
	source_record_id = record_id
	source_uid = p_source_uid
	add_to_group("ghosts_3d")


@onready var _identity_label: Label3D = $Visual/IdentityLabel


func _ready() -> void:
	super()
	_apply_ghost_visual()
	_apply_identity_feedback()


## 사망 시 ghosts_3d 그룹에서도 제거한다(부모 die()는 enemies_3d만 제거).
func die() -> void:
	if not alive:
		return
	remove_from_group("ghosts_3d")
	super()


## 일반 Enemy와 즉시 구분되도록 albedo tint + 발광을 적용한다(가독성을 해치지 않는
## 정도). headless dummy renderer에서 투명(shader) 전환으로 인한 renderer 경고를 피하기
## 위해 alpha/transparency 전환은 사용하지 않는다.
func _apply_ghost_visual() -> void:
	var mat := _body_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		sm.albedo_color = Color(0.55, 0.65, 1.0, 1.0)
		sm.emission_enabled = true
		sm.emission = Color(0.4, 0.6, 1.0)
		sm.emission_energy_multiplier = 1.3


## Ghost death는 신규 DeathRecord를 만들지 않고 원본 record를 RESOLVED 처리한다.
## 이로써 Ghost 재귀(무한 재등장)가 원천 차단된다. 원본 record가 없으면 안전 no-op.
func _record_death() -> void:
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger != null and source_record_id != "":
		ledger.resolve(source_record_id, _current_death_day())


## TASK-025-3 Ghost Identity Feedback.
## 원본 DeathRecord를 DeathLedger에서 조회해 반환한다(없으면 null). 복사본이므로
## 외부에서 원본 record 상태를 우회 변경할 수 없다. debug/inspection 목적으로만 사용.
func get_source_record() -> DeathRecord:
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger == null or source_record_id == "":
		return null
	return ledger.get_record(source_record_id)


## TASK-025-3: 원본 identity의 최소 확인 정보(이름/category/origin)를 반환한다.
## origin은 원본 record의 source_uid(고유 개체)와 사망일로 구성해 "이전에 죽었던
## 존재가 돌아왔음"을 debug/inspection으로 연결할 수 있게 한다. 원본 record가 없으면
## 이름/카테고리는 보유 필드로, origin만 비어 있는 정보를 반환한다(안전 no-op 아님).
func get_identity_info() -> Dictionary:
	var info := {
		"name": display_name,
		"category": "",
		"origin": "",
		"source_record_id": source_record_id,
		"source_uid": source_uid,
	}
	var record := get_source_record()
	if record == null:
		return info
	info["name"] = record.display_name if record.display_name != "" else display_name
	info["category"] = record.get_category()
	info["origin"] = "Day %d %s / uid=%s" % [
		record.death_day,
		record.get_death_phase_name(),
		record.source_uid,
	]
	return info


## TASK-025-3: 전투 중 원본 identity가 의미 있는 경우(이름 확인 가능) 컴팩트 nameplate
## Label3D를 갱신한다. 과도한 lore UI를 만들지 않고 이름 한 줄만 표시하며, 원본
## identity가 확인 불가하면 숨긴다. Ghost는 NIGHT 전투에만 존재하므로 nameplate도
## 전투 중에만 노출된다.
func _apply_identity_feedback() -> void:
	var label := _identity_label
	if label == null:
		return
	var info := get_identity_info()
	if info.get("name", "") == "":
		label.visible = false
		return
	label.text = info["name"]
	label.visible = true
