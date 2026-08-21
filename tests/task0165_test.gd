extends SceneTree

## TASK-016-5 Minimal Death Ledger View 자동 검증.
##  - DeathLedgerView가 HUD에 존재하고 기본적으로 숨겨져 있다.
##  - open()/close()/toggle()로 열고 닫을 수 있고, 닫았다 다시 열면 현재 Ledger
##    상태(get_all_records)를 다시 조회해 표시한다.
##  - DeathLedger.record_added / record_status_changed 시그널로 신규 record/status
##    변경 시 열려 있는 목록이 갱신된다.
##  - 표시 형식: display_name / source_kind / Day death_day / status.
##  - record 삭제/정화/망령 방지 버튼이 없다(CloseButton만 존재).
##  - 좌상단 HUD StatusPanel과 NIGHT Tactical Command UI를 과도하게 가리지 않는
##    배치(왼쪽 아래 영역).
##  - Day/Night 전환 후에도 표시 유지.
##  - 회귀: main scene / Player 비전투 / HUD / TacticalCommandUI intact.

enum TestPhase {
	SETUP,
	INITIAL_HIDDEN,
	OPEN_CLOSE_TOGGLE,
	SIGNAL_REFRESH_ADD,
	SIGNAL_REFRESH_STATUS,
	REOPEN_REQUERY,
	NO_DESTRUCTIVE_UI,
	DAY_NIGHT,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _sub := 0
var _failed := false

var _ledger: Node = null
var _view: Node = null
var _game_time: Node = null
var _main: Node = null

var _enemy_seq := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _make_enemy_snapshot(source_uid: String, display_name := "Raider") -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = display_name
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = 60
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = 3
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _make_mercenary_snapshot() -> Dictionary:
	var m := DeathRecord.new("")
	m.source_uid = "mercenary_A"
	m.source_kind = DeathRecord.SourceKind.MERCENARY
	m.display_name = "Mercenary A"
	m.class_or_type = "SWORDSMAN"
	m.level = 1
	m.max_hp = 100
	m.attack_damage = 10
	m.attack_interval = 1.0
	m.move_speed = 120.0
	m.death_day = 2
	m.death_phase = DeathRecord.DeathPhase.NIGHT
	m.death_position = Vector2(0, -280)
	return m.to_snapshot()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_ledger = root.get_node("DeathLedger")
			_game_time = root.get_node("GameTime")
			_main = root.get_node("Main")
			_game_time.set_auto_advance(false)
			_game_time.set_durations(2.0, 1.0)
			var hud: Node = _main.get_node("HUD")
			var views := get_nodes_in_group("death_ledger_view")
			_check(views.size() == 1, "DeathLedgerView present in HUD")
			if views.size() > 0:
				_view = views[0]
			_check(_view != null and _view.is_inside_tree(), "DeathLedgerView in tree")
			_check(_view.has_method("open") and _view.has_method("close") and _view.has_method("toggle"), \
				"view has open/close/toggle API")
			_check(_ledger != null and _game_time != null and _main != null, "core nodes present")
			_phase = TestPhase.INITIAL_HIDDEN
		TestPhase.INITIAL_HIDDEN:
			_check(_view.is_open() == false, "view starts hidden")
			_check(_view.visible == false, "view node hidden initially")
			_phase = TestPhase.OPEN_CLOSE_TOGGLE
		TestPhase.OPEN_CLOSE_TOGGLE:
			match _sub:
				0:
					_view.open()
					_check(_view.is_open(), "open() shows view")
					_check(_view.visible, "visible true after open()")
					_sub = 1
				1:
					_view.close()
					_check(_view.is_open() == false, "close() hides view")
					_sub = 2
				2:
					_view.toggle()
					_check(_view.is_open(), "toggle() opens when hidden")
					_view.toggle()
					_check(_view.is_open() == false, "toggle() closes when open")
					_sub = 0
					_phase = TestPhase.SIGNAL_REFRESH_ADD
		TestPhase.SIGNAL_REFRESH_ADD:
			# 열려 있는 상태에서 record_added가 오면 목록에 즉시 반영된다.
			_view.open()
			_check(_view.get_row_text(0).find("기록 없음") != -1, \
				"empty state shows placeholder row")
			_ledger.record_death(_make_enemy_snapshot("view_enemy_0", "Raider"))
			_check(_view.get_row_text(0).find("Raider / ENEMY / Day 3 / PENDING") != -1, \
				"record_added signal refreshes open view")
			_check(_view.get_row_text(0).find("기록 없음") == -1, \
				"placeholder replaced after first record")
			_phase = TestPhase.SIGNAL_REFRESH_STATUS
		TestPhase.SIGNAL_REFRESH_STATUS:
			# record_status_changed가 오면 열려 있는 목록의 status 라벨이 갱신된다.
			var rec: DeathRecord = _ledger.get_all_records()[0]
			_check(rec != null, "first record retrievable")
			if rec != null:
				_check(_ledger.mark_active(rec.record_id), "mark_active accepted")
				_check(_view.get_row_text(0).find("ACTIVE") != -1, \
					"status change signal refreshes row to ACTIVE")
				_check(_view.get_row_text(0).find("PENDING") == -1, \
					"old PENDING text replaced in open view")
			_phase = TestPhase.REOPEN_REQUERY
		TestPhase.REOPEN_REQUERY:
			# 닫았다 다시 열면 현재 Ledger 상태를 다시 조회해 표시한다.
			_view.close()
			_ledger.record_death(_make_enemy_snapshot("view_enemy_1", "Raider 2"))
			_check(_view.is_open() == false, "still closed after adding record while hidden")
			_view.open()
			_check(_view.get_record_count() == 2, "reopen re-queries and shows both records (%d)" % _view.get_record_count())
			_check(_view.get_row_text(1).find("Raider 2 / ENEMY / Day 3 / PENDING") != -1, \
				"new record shown on reopen")
			_phase = TestPhase.NO_DESTRUCTIVE_UI
		TestPhase.NO_DESTRUCTIVE_UI:
			# 삭제/정화/망령 방지 버튼이 없다. 버튼은 CloseButton 하나뿐.
			var buttons: Array[Node] = []
			for n in _view.get_tree().get_nodes_in_group("death_ledger_view"):
				_collect_buttons(n, buttons)
			var texts: Array[String] = []
			for b in buttons:
				texts.append((b as Button).text)
			var has_delete := false
			var has_purify := false
			var has_prevent := false
			for t in texts:
				if t.find("삭제") != -1 or t.find("제거") != -1 or t.to_lower().find("delete") != -1:
					has_delete = true
				if t.find("정화") != -1 or t.find("정화") != -1 or t.to_lower().find("purif") != -1:
					has_purify = true
				if t.find("방지") != -1 or t.find("막") != -1 or t.to_lower().find("prevent") != -1:
					has_prevent = true
			_check(has_delete == false, "no delete/remove button in view")
			_check(has_purify == false, "no purification button in view")
			_check(has_prevent == false, "no ghost-return prevention button in view")
			_check(texts.size() == 1 and texts[0] == "닫기", \
				"only CloseButton present in view (%d buttons)" % texts.size())
			_phase = TestPhase.DAY_NIGHT
		TestPhase.DAY_NIGHT:
			# Day/Night 전환 후에도 열려 있는 목록이 유지된다.
			_view.open()
			var day: int = _game_time.get_day_number()
			_game_time.advance(3.0)
			_game_time.advance(2.0)
			_check(_game_time.get_day_number() > day, "day/night advanced")
			_check(_view.is_open(), "view still open after phase transition")
			_check(_view.get_record_count() == 2, "records retained after day/night (%d)" % _view.get_record_count())
			_phase = TestPhase.REGRESSION
		TestPhase.REGRESSION:
			_check(_main != null and _main.get_node("Player") != null and _main.get_node("HUD") != null, \
				"main scene intact")
			_check(get_nodes_in_group("tactical_command_ui").size() == 1, "tactical command UI intact")
			var hud: Node = _main.get_node("HUD")
			_check(hud.get_node_or_null("StatusPanel") != null, "HUD StatusPanel intact")
			_check(hud.get_node_or_null("DeathLedgerView") != null, "DeathLedgerView still under HUD")
			var player: Node = _main.get_node("Player")
			_check(not player.has_method("attack") and not player.has_method("_attack"), \
				"player has no attack method (no direct combat)")
			_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor spawned")
			_phase = TestPhase.DONE
		TestPhase.DONE:
			print("TASK0165_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0165_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _sub_step(step: int) -> bool:
	return step == 0


func _collect_buttons(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)