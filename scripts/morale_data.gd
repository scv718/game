extends RefCounted
class_name MoraleContributor

## TASK-023-1 최소 Morale Contributor 데이터 모델.
## roster identity(mercenary_id) 기준으로 사기 기여자를 snapshot한다. 실제 월드 전투
## Actor(duplicate)가 아니라 고용된 MercenaryData를 반영하므로 같은 id의 contributor는
## 항상 1개다(duplicate count 없음).
## "강한 동료"의 파워 기준은 기존 MercenaryData에 tier/grade가 없으므로 level을
## data-driven power metadata로 사용한다. exact formula는 DESIGN_TUNING.
## Ghost(원본 생존자가 아닌 망령) 기여자는 사기에서 제외한다. 현재 Ghost system이
## 없으므로 기본 false이며 TASK-025에서 is_ghost=true인 기여자를 세지 않도록 준비한다.

var mercenary_id: String = ""
var display_name: String = ""
var level: int = 1
var alive := true
var is_ghost := false


func _init(p_id: String = "") -> void:
	mercenary_id = p_id


## 설계 기반 "강한 동료" 기여 가중치. 정확한 수식은 DESIGN_TUNING.
## 기본 규칙: level 1 기준 1.0, 레벨이 오를수록 기여도 상승(레벨당 level_weight).
static func contribution_from_level(p_level: int, level_weight: float) -> float:
	var lv := maxi(1, p_level)
	return 1.0 + (lv - 1) * level_weight
