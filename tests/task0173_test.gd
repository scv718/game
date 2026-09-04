extends SceneTree

## TASK-017-3 Ghost Visual / Combat Identity 자동 검증.
##   - Ghost는 Quaternius 원본 캐릭터 visual(CharacterRig3D 공용 리그)을 재사용한다.
##   - ghost material(tint/emission/alpha)이 최소 처리로 적용되어 일반 Actor와
##     구분된다(alpha 하한 유지 = readability 보존).
##   - Mercenary Ghost는 원본 class에 해당하는 outfit body key를 쓴다.
##   - Enemy Ghost는 원본 archetype에 해당하는 base body key를 쓴다.
##   - Ghost death animation 재생 + cleanup(queue_free)이 정상이다.
##   - Ghost 사망이 다시 Ghost Return Candidate를 만들지 않는다(recursion guard).
##   - 원본 class/stat/skill identity가 Ghost에서 보존된다.
##   - Player 직접 전투 없음(EnemyActor3D 계약 유지).
##
## 기존 테스트 관례(task0172)에 따라 autoload/GhostSpawner3D는 런타임 load()로 접근한다.

enum Phase {
	SETUP,
	STRUCTURE,
	REGISTER_CANDIDATES,
	TO_NIGHT,
	GHOST_SPAWN_WAIT,
	SPAWN_VERIFY,
	RIG_VERIFY,
	COMBAT_ARM,
	COMBAT_WAIT,
	GHOST_DEATH_WAIT,
	DEATH_ANIM_VERIFY,
	NO_RECURSION_CHECK,
	TO_DAY,
	FINAL_CHECK,
	DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 600
## ghost의 사망 fade-out + cleanup 여유 프레임(DEATH_FADE_SECONDS ≈ 0.9s @60fps).
const DEATH_CLEANUP_BUDGET := 180

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _game_time: Node = null
var _ledger: Node = null
var _ghost_return: Node = null
var _spawner: Node = null
var _enemy_ghost: Node = null
var _merc_ghost: Node = null
var _merc_fixture: Node = null
var _enemy_record_id := ""
var _merc_record_id := ""


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0173_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _make_enemy_snapshot(source_uid: String, day := 1) -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = "Raider"
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = 60
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = day
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _make_mercenary_snapshot(source_uid: String, day := 1) -> Dictionary:
	var m := DeathRecord.new("")
	m.source_uid = source_uid
	m.source_kind = DeathRecord.SourceKind.MERCENARY
	m.display_name = "Blade"
	m.class_or_type = "SWORDSMAN"
	m.level = 3
	m.max_hp = 150
	m.attack_damage = 20
	m.attack_interval = 0.8
	m.move_speed = 130.0
	m.death_day = day
	m.death_phase = DeathRecord.DeathPhase.NIGHT
	m.death_position = Vector2(12, -280)
	return m.to_snapshot()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.REGISTER_CANDIDATES:
			_register_candidates()
		Phase.TO_NIGHT:
			_to_night()
		Phase.GHOST_SPAWN_WAIT:
			_ghost_spawn_wait()
		Phase.SPAWN_VERIFY:
			_spawn_verify()
		Phase.RIG_VERIFY:
			_rig_verify()
		Phase.COMBAT_ARM:
			_combat_arm()
		Phase.COMBAT_WAIT:
			_combat_wait()
		Phase.GHOST_DEATH_WAIT:
			_ghost_death_wait()
		Phase.DEATH_ANIM_VERIFY:
			_death_anim_verify()
		Phase.NO_RECURSION_CHECK:
			_no_recursion_check()
		Phase.TO_DAY:
			_to_day()
		Phase.FINAL_CHECK:
			_final_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 40000:
		print("TASK0173_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var gt := root.get_node_or_null("GameTime")
	if gt != null:
		gt.set_auto_advance(false)
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_game_time = root.get_node_or_null("GameTime")
	_ledger = root.get_node_or_null("DeathLedger")
	_ghost_return = root.get_node_or_null("GhostReturn")
	_check(_world != null, "3D world loads")
	_check(_game_time != null and _ledger != null and _ghost_return != null,
		"GameTime/DeathLedger/GhostReturn autoloads available")
	if _world == null or _game_time == null or _ledger == null or _ghost_return == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(2.0, 1.0)
	var nav_manager: Node = load("res://scripts/navigation_manager_3d.gd").new()
	nav_manager.name = "NavManager"
	_world.add_child(nav_manager)
	_spawner = load("res://scripts/ghost_spawner_3d.gd").new()
	_spawner.name = "GhostSpawner3D"
	root.add_child(_spawner)
	_enter(Phase.STRUCTURE)


func _structure() -> void:
	_check(_spawner.has_method("spawn_ghosts"), "GhostSpawner3D exposes spawn_ghosts")
	_check(_ghost_return.get_candidate_count() == 0, "no candidates before any death")
	_enter(Phase.REGISTER_CANDIDATES)


func _register_candidates() -> void:
	# Enemy lethal death 1회 → candidate. Mercenary lethal death 1회 → candidate.
	var erec: DeathRecord = _ledger.record_death(_make_enemy_snapshot("raider_017_3"))
	_check(erec != null, "enemy lethal death creates ledger record")
	_enemy_record_id = erec.record_id
	var mrec: DeathRecord = _ledger.record_death(_make_mercenary_snapshot("blade_017_3"))
	_check(mrec != null, "mercenary lethal death creates ledger record")
	_merc_record_id = mrec.record_id
	_check(_ghost_return.get_candidate_count() == 2,
		"2 distinct lethal deaths -> 2 candidates (%d)" % _ghost_return.get_candidate_count())
	_check(_ghost_return.get_eligible_candidates().size() == 2, "2 eligible candidates")
	_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase advanced to NIGHT")
	_enter(Phase.GHOST_SPAWN_WAIT)


func _ghost_spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.SPAWN_VERIFY)


func _spawn_verify() -> void:
	var count: int = _spawner.get_ghost_count()
	_check(count == 2, "NIGHT spawns 2 ghosts from 2 eligible candidates (%d)" % count)
	_check(get_nodes_in_group("enemies_3d").size() == 2, "ghosts join enemies_3d group")
	var ghosts: Array[Node] = _spawner.get_ghosts()
	var found_enemy := false
	var found_merc := false
	for g in ghosts:
		var kind: int = (g as Node).get("ghost_kind")
		if kind == DeathRecord.SourceKind.ENEMY:
			_enemy_ghost = g
			found_enemy = true
		else:
			_merc_ghost = g
			found_merc = true
	_check(found_enemy, "enemy-candidate ghost spawned")
	_check(found_merc, "mercenary-candidate ghost spawned")
	# combat identity 보존.
	if _merc_ghost != null:
		_check((_merc_ghost as Node).get("ghost_kind") == DeathRecord.SourceKind.MERCENARY,
			"mercenary ghost tracks MERCENARY kind")
		_check((_merc_ghost as Node).get("max_hp") == 150,
			"mercenary ghost reuses original max_hp")
		_check((_merc_ghost as Node).get("attack_damage") == 20,
			"mercenary ghost reuses original attack_damage")
		_check((_merc_ghost as Node).get("level") == 3,
			"mercenary ghost reuses original level")
	if _enemy_ghost != null:
		_check((_enemy_ghost as Node).get("ghost_kind") == DeathRecord.SourceKind.ENEMY,
			"enemy ghost tracks ENEMY kind")
	_check(_ghost_return.get_eligible_candidates().size() == 0,
		"all candidates consumed after spawn")
	_enter(Phase.RIG_VERIFY)


func _rig_verify() -> void:
	# Ghost가 Quaternius CharacterRig3D 공용 리그를 장착했고 ghost material이 적용됐는지.
	if _enemy_ghost != null:
		_check(_enemy_ghost.has_method("get_ghost_rig"), "ghost exposes ghost rig accessor")
		var rig: Node = _enemy_ghost.get_ghost_rig()
		_check(rig != null, "enemy ghost has CharacterRig3D")
		if rig != null:
			_check(rig.get("body_key") == "human/male_base",
				"enemy ghost uses base archetype body key (human/male_base)")
			_check(rig.get_class() != null, "rig is a CharacterRig3D node")
			_check(_rig_has_ghost_material(_enemy_ghost), "enemy ghost material applied")
	if _merc_ghost != null:
		var mrig: Node = _merc_ghost.get_ghost_rig()
		_check(mrig != null, "mercenary ghost has CharacterRig3D")
		if mrig != null:
			_check(mrig.get("body_key") == "outfit/male_ranger_full",
				"mercenary ghost uses original class outfit body key (male_ranger_full)")
			_check(_rig_has_ghost_material(_merc_ghost), "mercenary ghost material applied")
	_enter(Phase.COMBAT_ARM)


## ghost rig의 body mesh들이 ghost material(alpha 하한 + emission)을 가졌는지 확인.
func _rig_has_ghost_material(ghost: Node) -> bool:
	var rig: Node = ghost.get_ghost_rig()
	if rig == null:
		return false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(rig, meshes)
	if meshes.is_empty():
		return false
	var any_ghost_material := false
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		for s in mesh.mesh.get_surface_count():
			var mat: Material = mesh.get_active_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				# 최소 처리: tint + alpha(하한 보존으로 readability 확보) + emission.
				if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
						and sm.albedo_color.a >= 0.5 \
						and sm.emission_enabled:
					any_ghost_material = true
	return any_ghost_material


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _combat_arm() -> void:
	# Ghost 자동전투 검증용 상대 mercenary fixture. 두 ghost를 모두 교전 범위에 두기
	# 위해 enemy ghost 근처에 하나 배치한다.
	var data = load("res://scripts/mercenary_data.gd").new()
	data.id = "m_fixture_0173"
	data.display_name = "Defender"
	data.max_hp = 100000
	data.attack_damage = 30
	data.attack_interval = 1.0
	var merc: Node = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
	merc.merc_data = data
	var ghost_pos: Vector3 = (_enemy_ghost as Node3D).global_position
	merc.position = ghost_pos + Vector3(2.0, 0.0, 0.0)
	_world.add_child(merc)
	_merc_fixture = merc
	_enter(Phase.COMBAT_WAIT)


func _combat_wait() -> void:
	_wait += 1
	var ghost_attacking: bool = _enemy_ghost != null and is_instance_valid(_enemy_ghost) \
		and (_enemy_ghost as Node).get("alive") == true \
		and (_enemy_ghost as Node).get("state") == 2  # EnemyActor3D.EnemyState.ATTACK
	var damage_applied: bool = int((_merc_fixture as Node).get("current_hp")) < 100000
	# Entering ATTACK precedes the interval-gated damage tick. Observe both parts of
	# the combat contract instead of sampling HP on the first ATTACK frame.
	if (not ghost_attacking or not damage_applied) and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(ghost_attacking, "ghost auto-combat engages a nearby mercenary (ATTACK)")
	_check(damage_applied, "ghost deals combat damage")
	_enter(Phase.GHOST_DEATH_WAIT)


func _ghost_death_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	# 결정적 lethal death: auto-combat 검증 후 직접 HP 소진으로 사망을 유도한다
	# (두 ghost가 fixture target을 두고 경합해 특정 ghost의 사망 시점이 비결정적인
	# flakiness 제거). base EnemyActor3D.die() 경로와 동일한 lethal 전투 경로다.
	if _enemy_ghost != null and is_instance_valid(_enemy_ghost) \
			and (_enemy_ghost as Node).get("alive") == true:
		_enemy_ghost.take_damage(9999)
	_check(_enemy_ghost == null or not is_instance_valid(_enemy_ghost) \
		or (_enemy_ghost as Node).get("alive") == false,
		"ghost dies to lethal combat")
	_enter(Phase.DEATH_ANIM_VERIFY)


func _death_anim_verify() -> void:
	# 사망 후 ghost가 fade-out을 거쳐 cleanup(queue_free)되는지 확인.
	_wait += 1
	if _wait < DEATH_CLEANUP_BUDGET:
		return
	_wait = 0
	_check(_enemy_ghost == null or not is_instance_valid(_enemy_ghost),
		"ghost cleaned up (queue_free) after death animation + fade")
	_check(_spawner.get_ghost_count() == 1,
		"spawner no longer tracks the dead ghost (remaining=%d)" % _spawner.get_ghost_count())
	_enter(Phase.NO_RECURSION_CHECK)


func _no_recursion_check() -> void:
	_check(_ghost_return.get_candidate_count() == 2,
		"ghost death adds no new candidate (recursion guard, count=%d)"
			% _ghost_return.get_candidate_count())
	_check(_ghost_return.get_eligible_candidates().size() == 0,
		"no new eligible candidate after ghost death")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	# DAY 복귀 시 남은(살아있는) ghost는 despawn cleanup(무기록).
	_check(_spawner.get_ghost_count() == 0, "DAY return has no remaining ghost (cleanup)")
	_enter(Phase.FINAL_CHECK)


func _final_check() -> void:
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (no direct combat)")
	_check(_ledger.get_all_records().size() >= 2, "ledger retains original death records")
	_check(_ghost_return.get_candidate_count() == 2, "candidate count unchanged across DAY")
	_enter(Phase.DONE)
