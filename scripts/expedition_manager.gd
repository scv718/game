extends Node
class_name ExpeditionManager

## TASK-026-2/3 Expedition registry/validation/runtime owner.
## ExpeditionPartyData(순수 데이터)를 expedition_id 기준으로 보관하고,
## 중복 expedition_id 차단, 중복 member 차단, 다른 active Expedition에 편성 중인
## member 차단, 사망/unavailable member 출발 validation 실패를 담당한다(TASK-026-2).
##
## TASK-026-3: 진행 중 Expedition을 GameTime 기준으로 시간 진행시킨다.
## - OUTBOUND → EXPLORING → RETURNING → COMPLETED 전환을 GameTime 배율에 따라 1회씩 처리.
## - frame-rate 독립: advance(seconds)는 초 단위로 누적하며 프레임 수에 의존하지 않는다.
## - 기존 Pause/1x/2x 정책(GameTime.get_time_scale())을 그대로 곱해 적용한다(Pause=0 → 미진행).
## - DAY/NIGHT phase 전환과 무관하게 pure elapsed로 진행하며 phase 전환으로 progress가
##   중복 적용/리셋되지 않는다. status 가드로 전환은 정확히 1회만 발생한다.
## - 이 owner는 절대 Node timer/신호를 개별 expedition에 연결하지 않으며, persistent data에
##   Node reference를 저장하지 않으므로 reload/reconstruction(snapshot 복원 후 register)에 안전하다.
## - destination은 region_id(String) 데이터로만 처리하므로 freed/invalid marker여도 안전하다.
## - 파견 중 member death 처리 구조는 아직 없으므로 결과 연결 없이 귀환 완료만 처리하고
##   `_dispatch_member_survival_hook()`만 제공한다(TASK-026-5에서 확장).
## 범용 Party Framework를 만들지 않고 Expedition 고유 편성/진행 규칙만 보유한다.

signal expedition_created(expedition_id: String)
signal expedition_completed(expedition_id: String)
## 진행 중 status 전환(READY/OUTBOUND/EXPLORING/RETURNING → 다음 status)을 1회씩 발행.
signal expedition_phase_changed(expedition_id: String, from_status: int, to_status: int)

## 구간 소요 시간 미설정(<=0)일 때 사용하는 프로토타입 기본값(초). 밸런스 확정 값이 아니다.
const DEFAULT_PHASE_DURATION := 45.0
## 0으로 나누는 것을 막기 위한 최소 구간 시간(초).
const MIN_PHASE_DURATION := 0.001

var _expeditions: Dictionary = {}
var _auto_advance := true


func _process(delta: float) -> void:
	if _auto_advance:
		advance(delta)


## Expedition 생성. 빈 id와 중복 expedition_id는 거부하고 null을 반환한다.
## member 편성은 add_member()로 진행한다(중복/활성 편성 가드 적용).
func create_expedition(expedition_id: String, destination_region_id: String) -> ExpeditionPartyData:
	if expedition_id.is_empty() or _expeditions.has(expedition_id):
		return null
	var exp := ExpeditionPartyData.new(expedition_id, destination_region_id)
	_expeditions[expedition_id] = exp
	expedition_created.emit(expedition_id)
	return exp


func get_expedition(expedition_id: String) -> ExpeditionPartyData:
	return _expeditions.get(expedition_id)


func get_expeditions() -> Array:
	return _expeditions.values()


## 진행 중(READY/COMPLETED 제외) Expedition 목록.
func get_active_expeditions() -> Array:
	var out: Array = []
	for exp in _expeditions.values():
		if exp.is_active():
			out.append(exp)
	return out


func has_expedition(expedition_id: String) -> bool:
	return _expeditions.has(expedition_id)


## registry에서 expedition을 제거한다. 진행 중(active)이거나 COMPLETED/READY 아닌
## 상태는 거부한다. TASK-026-4에서 실패한 dispatch(start_departure/add_member 실패)의
## 잔여 expedition을 정리하는 최소 cleanup API다. READY 상태만 제거 가능하므로
## 파견 중 member availability/신호와 충돌하지 않는다.
func remove_expedition(expedition_id: String) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null or exp.status != ExpeditionPartyData.Status.READY:
		return false
	_expeditions.erase(expedition_id)
	return true


## 지정 member가 현재 편성된 active Expedition을 조회한다. 없으면 null.
func find_active_expedition_of(member_id: String) -> ExpeditionPartyData:
	for exp in _expeditions.values():
		if exp.is_active() and exp.has_member(member_id):
			return exp
	return null


## 지정 member가 어떤 active Expedition에도 편성되어 있지 않은지.
func is_member_in_active_expedition(member_id: String) -> bool:
	return find_active_expedition_of(member_id) != null


## member 편성 가능 여부. active Expedition에 편성 중이면 false.
## roster가 주어지면 해당 roster에 살아 있는 member인지도 확인한다(roster 미주입 시
## active 편성 여부만 판정 — 순수 데이터 테스트용).
func is_member_available(member_id: String, roster: Node = null) -> bool:
	if member_id.is_empty():
		return false
	if is_member_in_active_expedition(member_id):
		return false
	var r: Node = roster if roster != null else _get_roster()
	if r != null and r.has_method("get_mercenary"):
		var m: Variant = r.call("get_mercenary", member_id)
		if m == null or not bool(m.get("alive")):
			return false
	return true


## member 편성. 같은 Expedition 내 중복과, 다른 active Expedition에 편성 중인 member를
## 거부한다. READY 상태에서만 편성 가능하다(출발 후 편성 변경 금지).
func add_member(expedition_id: String, member_id: String) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null or member_id.is_empty():
		return false
	if exp.status != ExpeditionPartyData.Status.READY:
		return false
	if is_member_in_active_expedition(member_id):
		return false
	return exp.add_member(member_id)


func remove_member(expedition_id: String, member_id: String) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null:
		return false
	return exp.remove_member(member_id)


## 출발 validation. member가 0명이면 실패, 모든 member가 roster에서 alive이고
## 다른 active Expedition에 편성 중이 아니어야 한다.
func validate_departure(expedition_id: String, roster: Node = null) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null:
		return false
	if exp.get_member_count() == 0:
		return false
	for member_id in exp.get_member_ids():
		if not is_member_available(member_id, roster):
			return false
	return true


## READY → OUTBOUND 출발. validation 성공 시에만 출발 시점을 기록하고 진행 상태로
## 전환한다. 실패 시 상태를 바꾸지 않고 false를 반환한다.
func start_departure(expedition_id: String, day: int, time: float,
		roster: Node = null) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null or exp.status != ExpeditionPartyData.Status.READY:
		return false
	if not validate_departure(expedition_id, roster):
		return false
	exp.departure_day = day
	exp.departure_time = time
	exp.progress = 0.0
	exp.phase_started_at = time
	exp.set_status(ExpeditionPartyData.Status.OUTBOUND)
	expedition_phase_changed.emit(
		expedition_id, ExpeditionPartyData.Status.READY, ExpeditionPartyData.Status.OUTBOUND)
	return true


## 진행도 설정(0.0~1.0). 각 구간 진행 규칙 자체는 TASK-026-3 owner가 담당한다.
func set_progress(expedition_id: String, value: float) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null:
		return false
	exp.progress = clampf(value, 0.0, 1.0)
	return true


## 진행 중 Expedition을 COMPLETED로 완료 처리. 완료 후 해당 member는 다시 편성
## 가능(availability 복구)해진다. 이미 COMPLETED/READY면 거부하고 false를 반환해
## repeated complete로 인한 duplicate return을 방지한다.
func complete_expedition(expedition_id: String) -> bool:
	var exp := get_expedition(expedition_id)
	if exp == null or exp.status == ExpeditionPartyData.Status.COMPLETED \
			or exp.status == ExpeditionPartyData.Status.READY:
		return false
	var from_status := exp.status
	exp.progress = 1.0
	exp.set_status(ExpeditionPartyData.Status.COMPLETED)
	expedition_phase_changed.emit(
		expedition_id, from_status, ExpeditionPartyData.Status.COMPLETED)
	expedition_completed.emit(expedition_id)
	return true


## 자동 진행 설정. 테스트/특수 상황에서 끄고 advance()로 직접 제어할 수 있다.
func set_auto_advance(enabled: bool) -> void:
	_auto_advance = enabled


## 이미 구성된 ExpeditionPartyData(snapshot 복원 등)를 registry에 등록한다.
## reload/reconstruction용 진입점. null/빈 id/중복 id는 거부한다.
func register_expedition(exp: ExpeditionPartyData) -> bool:
	if exp == null or exp.expedition_id.is_empty() \
			or _expeditions.has(exp.expedition_id):
		return false
	_expeditions[exp.expedition_id] = exp
	return true


## 진행 중인 Expedition을 GameTime 기준으로 시간 진행한다.
## 전달 받은 초에 GameTime.get_time_scale()(Pause=0/1x/2x)을 곱한다.
## - 대규모 delta(한 프레임에 다수 구간 경과)도 while 루프로 모두 반영해 frame-rate 독립.
## - status 가드로 각 전환은 정확히 1회만 수행되어 DAY/NIGHT 반복에도 duplicate가 없다.
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var scaled := seconds * _get_time_scale()
	if scaled <= 0.0:
		return
	for exp in _expeditions.values():
		if exp.is_active():
			_advance_expedition(exp, scaled)


## 단일 Expedition 진행. 구간 duration을 남은 진행도와 비교해 초과분은 다음 구간으로
## carry한다. 자연 종료: EXPEDITION은 유한 상태머신이라 최대 OUTBOUND→EXPLORING→RETURNING→
## COMPLETED(3회) 전환으로 루프가 종료되므로 무한 루프가 없다.
func _advance_expedition(exp: ExpeditionPartyData, scaled: float) -> void:
	while scaled > 0.0 and exp.is_active():
		var duration := _phase_duration(exp)
		var remaining := maxf(duration * (1.0 - exp.progress), 0.0)
		if scaled < remaining:
			exp.progress = exp.progress + scaled / duration
			scaled = 0.0
		else:
			exp.progress = 1.0
			_transition_phase(exp)
			scaled -= remaining


## 현재 구간 소요 시간(초). 구간별 duration이 설정되지 않았으면 기본값을 쓴다(DESIGN_TUNING).
func _phase_duration(exp: ExpeditionPartyData) -> float:
	var duration := 0.0
	match exp.status:
		ExpeditionPartyData.Status.OUTBOUND:
			duration = exp.outbound_duration
		ExpeditionPartyData.Status.EXPLORING:
			duration = exp.exploration_duration
		ExpeditionPartyData.Status.RETURNING:
			duration = exp.return_duration
		_:
			return DEFAULT_PHASE_DURATION
	if duration <= 0.0:
		return DEFAULT_PHASE_DURATION
	return maxf(duration, MIN_PHASE_DURATION)


## 구간 완료 시 다음 status로 전환하거나 귀환 완료 처리한다.
func _transition_phase(exp: ExpeditionPartyData) -> void:
	match exp.status:
		ExpeditionPartyData.Status.OUTBOUND:
			_enter_phase(exp, ExpeditionPartyData.Status.EXPLORING)
		ExpeditionPartyData.Status.EXPLORING:
			_enter_phase(exp, ExpeditionPartyData.Status.RETURNING)
		ExpeditionPartyData.Status.RETURNING:
			# 귀환 완료. 파견 중 member death 처리 구조가 아직 없으므로 결과/reward 연결 없이
			# COMPLETED만 수행한다(TASK-026-5에서 member 복귀/결과 wiring 확장).
			if _dispatch_member_survival_hook(exp):
				complete_expedition(exp.expedition_id)
		_:
			pass


## 다음 구간 진입(진행도 리셋 + 시작 시점 기록). 전환 신호를 정확히 1회 발행한다.
func _enter_phase(exp: ExpeditionPartyData, next_status: int) -> void:
	var from_status := exp.status
	exp.progress = 0.0
	exp.phase_started_at = _current_game_seconds()
	exp.set_status(next_status)
	expedition_phase_changed.emit(exp.expedition_id, from_status, next_status)


## 파견 중 member death 처리를 위한 hook.
## 아직 member가 파견 중 사망할 수 있는 구조가 없어 임의 death event를 만들지 않고
## 항상 true(전원 생존 가정)를 반환한다. member 전멸/사망 판정 구조가 생기면
## 여기서 RETURNING 완료를 거부하도록 확장한다.
func _dispatch_member_survival_hook(_exp: ExpeditionPartyData) -> bool:
	return true


## GameTime autoload 배율 조회. tree 밖/autoload 부재 시 1x로 가정한다.
func _get_time_scale() -> float:
	var t := get_tree()
	if t == null:
		return 1.0
	var gt := t.root.get_node_or_null("GameTime")
	if gt == null or not gt.has_method("get_time_scale"):
		return 1.0
	return float(gt.get_time_scale())


## 현재 GameTime phase 경과(초)를 구간 시작 시점 기록용으로 조회한다. 정보용 값이며
## 진행도 산정에는 쓰지 않는다(진행은 누적 seconds 기반 → reload에 안전).
func _current_game_seconds() -> float:
	var t := get_tree()
	if t == null:
		return 0.0
	var gt := t.root.get_node_or_null("GameTime")
	if gt == null or not gt.has_method("get_phase_elapsed"):
		return 0.0
	return float(gt.get_phase_elapsed())


## MercenaryRoster autoload 조회. 순수 데이터 테스트처럼 tree 밖이면 null.
func _get_roster() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("MercenaryRoster")
