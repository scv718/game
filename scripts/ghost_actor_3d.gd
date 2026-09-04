extends EnemyActor3D
class_name GhostActor3D

## TASK-017-2/017-3 3D Ghost Actor.
## EnemyActor3D의 이동/교전/Gate/Death Ledger combat foundation을 그대로 재사용하고
## Ghost identity/visual만 추가한 파생 Actor다. LOCK:
##   - Ghost death record는 is_ghost=true로 기록되어 DeathLedger가 신규
##     GhostReturnCandidate 생성을 차단한다(무한 chain 방지).
##   - Player는 절대 target이 되지 않는다(base EnemyActor3D 계약 유지).
##   - Quaternius 원본 캐릭터 visual(CharacterRig3D 공용 리그)을 재사용하되
##     ghost tint/emission/alpha 최소 처리로 원본과 구분한다. readability를 해치는
##     과도한 투명도는 금지(alpha 하한 유지 + outline emission으로 실루엣 보존).
##   - Mercenary Ghost는 원본 class에 해당하는 outfit을, Enemy Ghost는 원본
##     archetype에 해당하는 base body를 사용해 identity가 시각적으로 추적된다.
##   - 이동/사거리 상수는 base EnemyActor3D를 그대로 따른다(밸런스 불변).

## 원본 lethal death의 source_uid(GhostReturnCandidate.source_uid). Ghost의 identity
## 추적과 duplicate spawn 검증용.
var source_uid := ""
## 원본 entity category(MERCENARY/ENEMY) snapshot.
var ghost_kind: int = DeathRecord.SourceKind.MERCENARY
## 원본 lethality 기록의 성장 수준(DeathRecord 스키마에 맞춘 level). base
## EnemyActor3D에는 level이 없으므로 Ghost identity snapshot으로만 보관한다.
var level: int = 1

## Ghost 공용 리그의 body key(원본 entity category에 따라 선택).
const BODY_MERCENARY := "outfit/male_ranger_full"
const BODY_ENEMY := "human/male_base"

## ghost material 처리 파라미터(최소 처리, readability 보존).
const GHOST_ALPHA := 0.82
const GHOST_TINT := Color(0.62, 0.85, 0.95)
const GHOST_EMISSION := Color(0.45, 0.7, 0.85)
const GHOST_EMISSION_ENERGY := 0.9
const BOB_AMPLITUDE := 0.12
const BOB_SPEED := 3.0
const DEATH_FADE_SECONDS := 0.9
const HIT_FLASH_SECONDS := 0.15

var _ghost_rig: CharacterRig3D = null
var _death_started_at := -1.0
var _time := 0.0
## ghost rig이 장착된 body mesh들(hit flash/death fade 대상).
var _rig_meshes: Array[MeshInstance3D] = []


## GhostSpawner3D가 GhostReturnCandidate snapshot으로 정체성/전투 stat을 설정한다.
## p_name은 "Ghost of <원본>" 형태의 ghost 라벨로 표시된다.
## move_speed는 candidate가 logical px/s를 보관하므로 world 단위로 환산해 저장한다
## (EnemyActor3D 저장 규약과 동일, 밸런스 불변).
func setup_ghost(p_id: String, p_name: String, p_direction: String,
		cand: GhostReturnCandidate) -> void:
	enemy_id = p_id
	display_name = p_name
	direction = p_direction
	source_uid = cand.source_uid
	ghost_kind = cand.source_kind
	max_hp = maxi(1, cand.max_hp)
	current_hp = max_hp
	attack_damage = cand.attack_damage
	attack_interval = cand.attack_interval
	move_speed = cand.move_speed * WorldCoords3D.PX_TO_UNIT
	level = cand.level


## Ghost identity debug 접근자.
func get_ghost_source_uid() -> String:
	return source_uid


func get_ghost_kind() -> int:
	return ghost_kind


func get_ghost_rig() -> CharacterRig3D:
	return _ghost_rig


## base EnemyActor3D._ready()가 $Visual/BodyVisual(placeholder capsule)에 대해 동작한
## 뒤, Quaternius 원본 캐릭터 리그를 장착하고 ghost material/tint/emission/alpha를
## 적용한다. 원본 entity category에 따라 body key를 고른다.
func _ready() -> void:
	super()
	_build_ghost_visual()


## 원본 entity category에 맞는 Quaternius 캐릭터 리그를 만들어 ghost 처리한다.
## body key는 identity 추적용이고, 전투 stat은 setup_ghost가 이미 반영했다.
func _build_ghost_visual() -> void:
	var rig := CharacterRig3D.new()
	rig.name = "GhostRig"
	rig.body_key = BODY_MERCENARY if ghost_kind == DeathRecord.SourceKind.MERCENARY \
		else BODY_ENEMY
	_visual.add_child(rig)
	rig.position = Vector3(0.0, 0.0, 0.0)
	_ghost_rig = rig
	# placeholder capsule은 숨기고 Quaternius 리그만 Ghost로 보이게 한다.
	_body_mesh.visible = false
	_apply_ghost_material()
	# Ghost는 float/spirit 느낌의 gentle bob을 준다(가독성을 해치지 않는 범위).
	rig.play_action("idle")


## Ghost rig이 소유한 모든 MeshInstance3D에 ghost material(alpha/tint/emission)을
## 적용한다. 원본 모델 material을 직접 변형하지 않고 duplicate 사본을 쓴다.
func _apply_ghost_material() -> void:
	_rig_meshes.clear()
	_collect_meshes(_ghost_rig, _rig_meshes)
	for mesh in _rig_meshes:
		var count := mesh.mesh.get_surface_count()
		for s in count:
			var mat: Material = mesh.get_active_material(s)
			if mat is StandardMaterial3D:
				var copy: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				copy.albedo_color = Color(
					GHOST_TINT.r, GHOST_TINT.g, GHOST_TINT.b, GHOST_ALPHA)
				copy.roughness = 0.6
				copy.emission_enabled = true
				copy.emission = GHOST_EMISSION
				copy.emission_energy_multiplier = GHOST_EMISSION_ENERGY
				mesh.set_surface_override_material(s, copy)


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


## TASK-017-3: hit flash는 ghost rig body에 emission tint를 잠깐 켠다.
func _apply_hit_visual() -> void:
	_hit_flash_left = HIT_FLASH_SECONDS
	for mesh in _rig_meshes:
		if not is_instance_valid(mesh):
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				sm.emission_enabled = true
				sm.emission = Color(0.95, 0.35, 0.25)


func _tick_hit_flash(delta: float) -> void:
	if _hit_flash_left <= 0.0:
		return
	_hit_flash_left -= delta
	if _hit_flash_left <= 0.0:
		_apply_ghost_material()


## Ghost 사망 처리. base EnemyActor3D.die()와 동일한 record/신호/그룹 계약을 유지하되,
## death 애니메이션 + fade-out을 실제로 재생한 뒤 월드에서 제거한다. cleanup과 동일하게
## queue_free 경로이므로 새 DeathRecord를 만들지 않는다(recursion guard 유지).
func die() -> void:
	if not alive:
		return
	alive = false
	remove_from_group("enemies_3d")
	death_started.emit(self)
	_record_death()
	died.emit(self)
	if _ghost_rig != null and is_instance_valid(_ghost_rig):
		_ghost_rig.play_action("death")
	_death_started_at = _time
	# placeholder capsule은 숨겨 ghost 리그만 보이게 한다.
	_body_mesh.visible = false
	# _process가 death 애니메이션 + fade-out을 진행한 뒤 완료 시점에 제거한다.


## ghost rig에 gentle vertical bob을 주고, 사망 후 death 애니메이션 + fade-out을
## 진행한 뒤 월드에서 제거한다.
func _process(delta: float) -> void:
	_time += delta
	if not alive:
		if _death_started_at < 0.0:
			return
		var elapsed := _time - _death_started_at
		if elapsed >= DEATH_FADE_SECONDS:
			queue_free()
			return
		_apply_fade(1.0 - clampf(elapsed / DEATH_FADE_SECONDS, 0.0, 1.0))
		return
	if _ghost_rig == null or not is_instance_valid(_ghost_rig):
		return
	var bob := sin(_time * BOB_SPEED) * BOB_AMPLITUDE
	_ghost_rig.position.y = bob


## ghost material의 alpha를 모든 rig body에 반영한다(사망 fade-out).
func _apply_fade(alpha: float) -> void:
	for mesh in _rig_meshes:
		if not is_instance_valid(mesh):
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var c := sm.albedo_color
				sm.albedo_color = Color(c.r, c.g, c.b, clampf(GHOST_ALPHA * alpha, 0.0, 1.0))


## Ghost death는 is_ghost=true record로 기록해 DeathLedger가 신규 candidate 생성을
## 차단한다(무한 chain 방지). base EnemyActor3D._record_death는 ENEMY record를 만들므로
## is_ghost만 켠 record로 오버라이드한다. move_speed는 logical px/s로 역환산해 저장해
## DeathRecord 스키마(원본 candidate와 같은 좌표/단위 공간)를 유지한다.
func _record_death() -> void:
	var record := DeathRecord.new("")
	record.source_uid = enemy_id
	record.source_kind = DeathRecord.SourceKind.ENEMY
	record.is_ghost = true
	record.display_name = display_name
	record.class_or_type = "GHOST"
	record.level = level
	record.max_hp = max_hp
	record.attack_damage = attack_damage
	record.attack_interval = attack_interval
	record.move_speed = move_speed / WorldCoords3D.PX_TO_UNIT
	record.death_day = _current_death_day()
	record.death_phase = _current_death_phase()
	record.death_position = WorldCoords3D.to_logical(global_position)
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger != null:
		ledger.record_death(record.to_snapshot())
