extends RefCounted
class_name WorkerData

## TASK-011-2 최소 WorkerData.
## 고용된 주민의 데이터를 월드 Actor와 분리해 보관하는 데이터 클래스.
## 미배치 상태에서는 Roster에만 존재하고 월드 Worker Actor는 존재하지 않는다.
## assignment 상태와 workplace 연결은 WorkerRoster가 관리한다.
## 영구 Save/Load는 구현하지 않으며, 향후 name/level/traits 확장만 염두에 둔다.

enum Job { LUMBERJACK, MINER }

const JOB_NAMES := {
	Job.LUMBERJACK: "LUMBERJACK",
	Job.MINER: "MINER",
}

var id: String = ""
var display_name: String = ""
var job: Job = Job.LUMBERJACK

var _assigned := false
var _workplace: Object = null


func _init(p_id: String = "", p_name: String = "", p_job: Job = Job.LUMBERJACK) -> void:
	id = p_id
	display_name = p_name
	job = p_job


func get_job_name() -> String:
	return JOB_NAMES.get(job, "?")


func is_assigned() -> bool:
	return _assigned and is_instance_valid(_workplace)


func get_workplace() -> Object:
	if is_instance_valid(_workplace):
		return _workplace
	return null


func get_workplace_id() -> String:
	var wp := get_workplace()
	if wp == null:
		return ""
	return str(wp.name)


func _set_assignment(workplace: Object) -> bool:
	if workplace == null or not is_instance_valid(workplace):
		return false
	_assigned = true
	_workplace = workplace
	return true


func _clear_assignment() -> void:
	_assigned = false
	_workplace = null
