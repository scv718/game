extends Node
class_name DungeonRuntime

## TASK-027-3 Dungeon Runtime Scene / Actor Lifecycle.
## Dungeon Encounter 최소 Runtime arena(dungeon_arena_3d.tscn)를 진입 시(load) /
## 종료 시(unload) 동적으로 인스턴스화하고, arena에서 Party(MercenaryActor3D)와
## Enemy(EnemyActor3D)를 spawn / cleanup하는 lifecycle controller다.
##
## - 기존 3D Combat Actor(MercenaryActor3D/EnemyActor3D)와 Navigation3D
##   (NavigationManager3D, dungeon arena 내 1 region)를 재사용한다.
## - arena는 dungeon entry 때만 로드되므로 평상시(Overworld DAY/NIGHT) 트리의
##   Foundation 단일 NavigationRegion3D 불변식(정확히 1개)을 깨지 않는다.
## - Party는 persistent Mercenary identity(MercenaryData)로만 spawn하며, spawn 시
##   진행 중인 encounter에 동일 identity actor가 있으면 중복 생성하지 않는다.
## - encounter 종료(end_run) 시 살아 있는 Party를 roster data로 복귀하고 arena를
##   포함한 Runtime node 전체를 queue_free로 정리(cleanup). queue_free 직접 사용이므로
##   die()를 거치지 않아 Death Ledger death를 기록하지 않는다.
## - dungeon scene/arena는 첫 vertical slice 1종만 사용한다. procedural room
##   generator / Player Avatar / 신규 Combat Framework는 구현하지 않는다.
## - Party member id authoritative source는 DungeonPreparationManager preparation과
##   동일한 /root/MercenaryRoster(autoload)다. depart()로 IN_PROGRESS가 된 dungeon만
##   begin_run을 허용한다.

const ARENA_SCENE := "res://scenes/dungeon_arena_3d.tscn"
const MERCENARY_SCENE := "res://scenes/mercenary_3d.tscn"
const ENEMY_SCENE := "res://scenes/enemy_3d.tscn"

## 첫 vertical slice Encounter 정의(encounter_id 기반, data-driven).
## 밸런스 수치는 prototype이며 DESIGN_TUNING.
const ENCOUNTERS := {
	"enc_ruins_gate": {
		"enemies": [
			{"type": "Ruins Guard", "count": 3},
		],
	},
}

## party spawn 행 / enemy spawn 행의 arena local world XZ 기준 위치.
const PARTY_START := Vector3(0, 0, 12)
const ENEMY_START := Vector3(0, 0, -12)
## 같은 행에 겹치지 않도록 결정적 소량 offset.
const SPAWN_SPACING := 2.0

## encounter 진군 라인(encounter rally). 파티가 이 지점을 결집 앵커로 삼고 전진해
## 기존 자동전투 AI로 교전한다(TASK-027-4). ENEMY_START 근처이므로 적이 자동전투
## 획득 범위(MercenaryActor3D.CHASE_RETURN_DISTANCE≈22.5u) 안에 들어온다.
## 새 Defense Zone/전투 런타임을 만들지 않고 기존 defense_point(내부 앵커)만
## 옮기므로 Overworld capture zone/Defense Zone UI와 충돌하지 않는다.
const ENCOUNTER_RALLY := ENEMY_START + Vector3(0, 0, 14)

var _dungeon_id := ""
var _active := false
## 현재 로드된 dungeon arena node(Node3D).
var _arena: Node = null
## party actor: mercenary_id -> MercenaryActor3D
var _party_actors: Dictionary = {}
## enemy actor 목록(EnemyActor3D)
var _enemy_actors: Array[Node] = []
## encounter 종료(end_run) 시 alive 상태로 roster 복귀된 party identity 목록.
var _returned_alive_ids: Array = []

signal encounter_started(dungeon_id: String)
signal encounter_ended(dungeon_id: String)


func _ready() -> void:
	add_to_group("dungeon_runtime")


func is_run_active() -> bool:
	return _active


func get_dungeon_id() -> String:
	return _dungeon_id


func get_arena() -> Node:
	return _arena


## --- encounter lifecycle ---

## dungeon encounter를 시작한다. dungeon arena scene을 로드하고 preparation 파티를
## persistent identity로, dungeon 정의의 encounter_ids를 data-driven으로 Enemy를
## spawn한다. dungeon이 IN_PROGRESS가 아니거나 파티가 비어 있으면 시작하지 않는다.
## clean하게 시작되면 encounter_started를 emit하고 true를 반환한다.
func begin_run(dungeon_id: String) -> bool:
	if _active:
		return false
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		return false
	if dungeon.get_state() != DungeonDefinition.DungeonState.IN_PROGRESS:
		return false
	var prep := DungeonPreparationManager.get_preparation(dungeon_id)
	if prep == null:
		return false
	var member_ids := prep.get_member_ids()
	if member_ids.is_empty():
		return false
	var scene: PackedScene = load(ARENA_SCENE)
	if scene == null:
		return false
	_arena = scene.instantiate()
	add_child(_arena)
	if spawn_party(member_ids) > 0:
		spawn_enemies_for_dungeon(dungeon_id)
	if _party_actors.is_empty():
		# 파티가 전혀 spawn되지 않으면(전원 dead 등) 실패로 간주하고 rollback.
		_cleanup_arena()
		return false
	# TASK-027-4: 파티를 encounter rally로 진군시켜 기존 auto combat으로 교전시킨다.
	_activate_encounter_advance()
	_dungeon_id = dungeon_id
	_active = true
	encounter_started.emit(dungeon_id)
	return true


## encounter를 종료한다. 살아 있는 Party actor의 persistent identity를 roster
## data로 복귀하고(roster는 이미 data를 보유), Runtime Actor를 포함한 dungeon
## arena 전체를 queue_free로 정리한다. queue_free 직접 사용이므로 DeathRecord를
## 만들지 않는다. 반복 호출은 멱등이며, 그동안 정리된 actor 수를 반환한다.
func end_run() -> int:
	if not _active:
		return 0
	var removed := 0
	for member_id in _party_actors.keys():
		var actor: Variant = _party_actors[member_id]
		if actor != null and is_instance_valid(actor):
			if actor.get("alive") != false:
				_returned_alive_ids.append(member_id)
			removed += 1
	_party_actors.clear()
	removed += _enemy_actors.size()
	_enemy_actors.clear()
	_active = false
	_dungeon_id = ""
	_cleanup_arena()
	encounter_ended.emit("")
	return removed


## --- spawn ---

## party member id 목록을 persistent Mercenary identity로 spawn한다. 이미 진행 중인
## encounter에 동일 identity actor가 있으면 중복 spawn하지 않는다. 실제로 spawn된
## actor 수를 반환한다.
func spawn_party(member_ids: Array) -> int:
	if _arena == null or not is_instance_valid(_arena):
		return 0
	var roster: Node = get_node_or_null("/root/MercenaryRoster")
	var scene: PackedScene = load(MERCENARY_SCENE)
	if scene == null:
		return 0
	var spawned := 0
	for i in member_ids.size():
		var member_id: String = str(member_ids[i])
		if _party_actors.has(member_id):
			# 동일 identity 중복 spawn 차단(Overworld/Dungeon 동시 이중 생성 방지).
			continue
		var mercenary: MercenaryData = null
		if roster != null:
			mercenary = roster.get_mercenary(member_id)
		if mercenary == null:
			continue
		if not mercenary.alive:
			# dead member는 spawn하지 않는다.
			continue
		var actor := scene.instantiate() as MercenaryActor3D
		if actor == null:
			continue
		actor.merc_data = mercenary
		actor.position = PARTY_START + _spawn_offset(i)
		actor.defense_point = actor.position
		_arena.add_child(actor)
		# 전투로 사망한 Actor는 추적에서 즉시 제거해 freed reference가 cleanup에
		# 남지 않게 한다(died signal 동기 처리).
		actor.died.connect(_on_party_actor_died.bind(member_id))
		_party_actors[member_id] = actor
		spawned += 1
	return spawned


## dungeon 정의의 encounter_ids를 합쳐 EnemyActor3D를 spawn한다. 실제로 spawn된
## enemy 수를 반환한다. Enemy는 encounter 지점에 HOLD로 서 있고, 진행 중인 Party가
## 공격 range 안으로 오면 기존 자동전투 AI로 교전한다(이동 경로는 TASK-027-4).
func spawn_enemies_for_dungeon(dungeon_id: String) -> int:
	if _arena == null or not is_instance_valid(_arena):
		return 0
	var dungeon := DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		return 0
	var scene: PackedScene = load(ENEMY_SCENE)
	if scene == null:
		return 0
	var idx := 0
	for enemy_desc in _collect_enemies(dungeon.get_encounter_ids()):
		var etype := str(enemy_desc.get("type", "Enemy"))
		for i in int(enemy_desc.get("count", 0)):
			var enemy := scene.instantiate() as EnemyActor3D
			if enemy == null:
				break
			enemy.setup("enc_%s_%d" % [etype, idx], etype, "north")
			enemy.position = ENEMY_START + _spawn_offset(idx)
			_arena.add_child(enemy)
			enemy.died.connect(_on_enemy_died)
			_enemy_actors.append(enemy)
			idx += 1
	return idx


## data-driven encounter 정의를 encounter_id 순서대로 enemy desc 목록으로 합친다.
func _collect_enemies(encounter_ids: Array) -> Array:
	var out: Array = []
	for encounter_id in encounter_ids:
		var conf: Dictionary = ENCOUNTERS.get(str(encounter_id), {})
		for entry in conf.get("enemies", []):
			out.append(entry)
	return out


## --- TASK-027-4: encounter auto combat + tactical commands ---

## encounter 진군 지점(rally)을 반환한다. 파티 auto combat 앵커이자 REGROUP 복귀 지점.
func get_encounter_rally() -> Vector3:
	return ENCOUNTER_RALLY


## dungeon 파티 후퇴 시 모이는 안전 지점(rally). dungeon 진입 행(PARTY_START)을
## Overworld Village/safe rally와 분리해 사용한다(내부 안전 지점, Overworld 충돌 없음).
func get_retreat_safe_rally() -> Vector3:
	return PARTY_START


## begin_run 성공 시 파티를 encounter 진군 상태로 전환한다(TASK-027-4).
## 기존 Mercenary auto combat(획득/추격/공격/death 처리)만으로 교전시키기 위해
## 각 party actor의 defense_point(내부 앵커)를 encounter rally로 옮겨 인접 enemy를
## 획득하게 한다. 새 전투 런타임/Defense Zone은 만들지 않는다. Player는 직접
## target이 되지 않는다(기존 enemies_3d/mercenaries_3d 획득 규칙 유지).
func _activate_encounter_advance() -> void:
	for actor: Variant in _party_actors.values():
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.get("alive") == false:
			continue
		actor.defense_point = ENCOUNTER_RALLY


## dungeon 파티에 전술 명령을 적용한다(TASK-027-4). 기존 TacticalCommandUI.Command를
## 재사용하고 dungeon에서 의미 있는 명령(REGROUP/RETREAT/FOCUS_TARGET)만 처리한다.
## 대상은 dungeon 파티 actor(mercenaries_3d group)뿐이므로 Overworld roster3D/
## TacticalCommandUI 상태와 충돌하지 않는다. 활성 run 중이 아니면 no-op.
func apply_tactical_command(command: int, _arg: Variant = null) -> void:
	if not _active:
		return
	match command:
		TacticalCommandUI.Command.REGROUP:
			for a in _alive_party_actors():
				(a as MercenaryActor3D).regroup()
		TacticalCommandUI.Command.RETREAT:
			var safe := get_retreat_safe_rally()
			for a in _alive_party_actors():
				(a as MercenaryActor3D).retreat(safe)
		TacticalCommandUI.Command.FOCUS_TARGET:
			_toggle_focus_target()


## dungeon 파티의 FOCUS_TARGET 토글. 유효한 살아 있는 enemy가 없으면(freed/death)
## 즉시 clear한다(영구 stale focus 금지). 이미 특정 enemy에 focus 중이면 해제하고,
## 아니면 가장 가까운 살아 있는 enemy에 일괄 focus를 지정한다.
func _toggle_focus_target() -> void:
	var target := _nearest_alive_enemy()
	if target == null:
		for a in _alive_party_actors():
			(a as MercenaryActor3D).clear_focus_target()
		return
	if _any_party_focusing():
		for a in _alive_party_actors():
			(a as MercenaryActor3D).clear_focus_target()
		return
	for a in _alive_party_actors():
		(a as MercenaryActor3D).set_focus_target(target)


## 살아 있는 dungeon 파티 중 하나라도 focus target(enemy)을 보유 중인지.
func _any_party_focusing() -> bool:
	for a in _alive_party_actors():
		if (a as MercenaryActor3D).get_focus_target() != null:
			return true
	return false


## 살아 있는 dungeon 파티 actor 목록 공개 버전(검증용). freed/사망 제외.
func get_alive_party_actor_nodes() -> Array:
	return _alive_party_actors()


## 살아 있는 dungeon 파티 actor 목록(MercenaryActor3D만, freed/사망 제외).
func _alive_party_actors() -> Array:
	var out: Array = []
	for actor: Variant in _party_actors.values():
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.get("alive") == false:
			continue
		if actor is MercenaryActor3D:
			out.append(actor)
	return out


## 살아 있는 enemy 중 가장 가까운 것(없으면 null). freed/사망은 제외한다.
func _nearest_alive_enemy() -> Node:
	var best: Node = null
	var best_dist := INF
	for e in _enemy_actors:
		if e == null or not is_instance_valid(e):
			continue
		if e.get("alive") == false:
			continue
		var d := WorldCoords3D.distance_xz(e.global_position, ENCOUNTER_RALLY)
		if d < best_dist:
			best_dist = d
			best = e
	return best


## --- cleanup helpers ---

## dungeon arena 전체를 queue_free로 정리한다(단일 unload). actor는 arena의 자식이라
## 함께 해제되고, DeathRecord는 만들지 않는다. 파티 spawn rollback/end_run 양쪽에서 사용.
func _cleanup_arena() -> void:
	for member_id in _party_actors.keys():
		var actor: Variant = _party_actors[member_id]
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	_party_actors.clear()
	for e in _enemy_actors:
		if e != null and is_instance_valid(e):
			e.queue_free()
	_enemy_actors.clear()
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null


## --- query (테스트/검증 / 후속 태스크용) ---

## 현재 encounter 중인 party actor 수.
func get_party_count() -> int:
	return _party_actors.size()


## 현재 encounter 중인 enemy actor 수.
func get_enemy_count() -> int:
	var n := 0
	for e in _enemy_actors:
		if is_instance_valid(e):
			n += 1
	return n


## alive 상태의 party actor 수.
func get_alive_party_count() -> int:
	var n := 0
	for actor: Variant in _party_actors.values():
		if actor != null and is_instance_valid(actor) and actor.get("alive") != false:
			n += 1
	return n


## alive 상태의 enemy actor 수.
func get_alive_enemy_count() -> int:
	var n := 0
	for e in _enemy_actors:
		if is_instance_valid(e) and e.get("alive") != false:
			n += 1
	return n


## 특정 identity의 party actor를 반환한다. 없거나 freed면 null.
func get_party_actor(member_id: String) -> Node:
	var actor: Variant = _party_actors.get(member_id)
	if actor != null and is_instance_valid(actor):
		return actor
	return null


## 이 encounter에서 살아서 roster 복귀된 party identity 목록(검증용).
func get_returned_alive_ids() -> Array:
	return _returned_alive_ids


func _spawn_offset(i: int) -> Vector3:
	var col := i % 3 - 1
	var row := i / 3
	return Vector3(col * SPAWN_SPACING, 0.0, row * SPAWN_SPACING)


## 전투로 사망한 party actor를 추적에서 즉시 제거한다(died signal 동기 처리).
func _on_party_actor_died(_actor: Node, member_id: String) -> void:
	_party_actors.erase(member_id)


## 전투로 사망한 enemy actor를 추적에서 즉시 제거한다(died signal 동기 처리).
func _on_enemy_died(enemy: Node) -> void:
	_enemy_actors.erase(enemy)
