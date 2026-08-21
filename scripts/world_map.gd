extends Node2D
class_name WorldMap

## 128x128 finite overworld skeleton layout (TASK-008-1 / TASK-012-2).
## 이 노드는 맵의 공간 구조(중앙 정착지 clearing, Main Road / Secondary Path,
## 성벽 예비 공간, Gate Anchor/Portal-Enemy Spawn 후보)를
## 코드와 씬 양쪽에서 식별 가능하게 유지한다.
## 실제 게임 기능(Gate/Portal/Enemy)은 구현하지 않으며 Marker/metadata만 제공한다.

const TILE_SIZE := 16
const MAP_TILES := 128
const WORLD_SIZE := MAP_TILES * TILE_SIZE  # 2048 px
const WORLD_HALF := WORLD_SIZE / 2         # 1024 px

const BOUNDS_RECT := Rect2(-WORLD_HALF, -WORLD_HALF, WORLD_SIZE, WORLD_SIZE)
const NAV_INSET := 32.0
const NAV_RECT := Rect2(
	-(WORLD_HALF - NAV_INSET),
	-(WORLD_HALF - NAV_INSET),
	WORLD_SIZE - NAV_INSET * 2.0,
	WORLD_SIZE - NAV_INSET * 2.0)

# 중앙 정착지 (건설 가능한 clearing)
const SETTLEMENT_CENTER := Vector2.ZERO
const CLEARING_HALF := Vector2(192, 192)

# 향후 자유 성벽을 둘 수 있도록 정착지 주변에 남겨둔 빈 공간 (clearing 바깥 링)
const WALL_BUFFER_HALF := Vector2(288, 288)

# --- Main Road (TASK-012-2) ---
# 4개 Main Road: 중앙 Core Village 경계(224px)에서 Outer Wild 방향까지 이어지는
# 중심선(centerline) 폴리라인. 반폭 40px = 6 논리 타일(96px, 권장 5~6 타일 준수).
# Defense Belt / Gate Corridor 구간(224~540px)은 직선으로 유지하고,
# 그 바깥에서 각 방향 Portal/Spawn 후보 코너 쪽으로 완만하게 굽혀
# 인공적인 직선 십자형으로 읽히지 않게 한다.
const MAIN_ROAD_HALF := 40.0
const MAIN_ROAD_INNER := 224.0
const AXIS_OUTER := 960.0

const MAIN_ROADS := {
	"north": [
		Vector2(0, -224), Vector2(0, -540), Vector2(-30, -650),
		Vector2(-60, -820), Vector2(-100, -960),
	],
	"south": [
		Vector2(0, 224), Vector2(0, 540), Vector2(30, 650),
		Vector2(60, 820), Vector2(100, 960),
	],
	"east": [
		Vector2(224, 0), Vector2(540, 0), Vector2(650, -30),
		Vector2(820, -60), Vector2(960, -100),
	],
	"west": [
		Vector2(-224, 0), Vector2(-540, 0), Vector2(-650, 30),
		Vector2(-820, 60), Vector2(-960, 100),
	],
}

# --- Secondary Path (TASK-012-2) ---
# 주요 목적지(Starter Forest / Stone Zone / Agriculture / Dungeon Candidate)를
# Main Road 네트워크에 연결하는 좁은 길. 반폭 16px = 2 논리 타일(32px, 권장 2~3 타일).
# 길이 맵 전체를 덮지 않도록 최소한으로 구성한다.
const SECONDARY_PATH_HALF := 16.0

const SECONDARY_PATHS := {
	"starter_forest": [
		Vector2(-224, -40), Vector2(-320, -160), Vector2(-400, -280), Vector2(-430, -340),
	],
	"stone_zone": [
		Vector2(280, 0), Vector2(360, 140), Vector2(440, 280), Vector2(480, 360),
	],
	"south_agriculture": [
		Vector2(0, 380), Vector2(40, 500), Vector2(60, 620),
	],
	"ne_dungeon": [
		Vector2(300, 0), Vector2(460, -200), Vector2(620, -440),
		Vector2(720, -650), Vector2(720, -700),
	],
}

# --- 자원 지역 (TASK-012-4) ---
# 숲 클러스터 정의. 수제 배치, 랜덤 생성 아님.
# 각 항목: { "id", "role", "center", "trees": [Vector2, ...] }
#
# - starter_forest (NW): 초반 직접 벌목 / 첫 Lumberyard 설치 / Worker 자동화 체험.
#   - 중심 (-430, -330) 부근, 약 260x220px 규모.
#   - 마을에 가까운 SE 가장자리는 성기게, 내부(NW)로 갈수록 밀도가 높고
#     내부에도 이동 가능한 틈을 유지한다. Secondary Path(starter_forest)를
#     막지 않도록 경로 중앙선에서 28px 이상 떨어뜨린다.
# - large_forest (SW): 중기 대규모 Wood 생산 지역. 큰 성벽 확장 여부를 고민하게 한다.
#   - 중심 (-600, +470) 부근, 약 350x300px 규모로 starter보다 크다.
#   - Defense Belt(360~520px)를 침범하지 않도록 중심을 충분히 외곽에 둔다.
# - sparse_forest (NE): 탐색 지역 / Dungeon Candidate 주변 자연 지형.
#   - 중심 (+520, -440) 부근. 상대적으로 적고 넓게 분산.
const FOREST_CLUSTERS := [
	{
		"id": "starter_forest",
		"role": "starter",
		"center": Vector2(-430, -330),
		"trees": [
			Vector2(-490, -420), Vector2(-450, -430), Vector2(-520, -390),
			Vector2(-480, -395), Vector2(-535, -350), Vector2(-495, -355),
			Vector2(-460, -380), Vector2(-515, -300), Vector2(-470, -310),
			Vector2(-430, -390), Vector2(-390, -370), Vector2(-445, -290),
			Vector2(-525, -445),
			Vector2(-555, -410), Vector2(-570, -370), Vector2(-545, -320),
			Vector2(-360, -280), Vector2(-310, -290), Vector2(-305, -245),
			Vector2(-350, -335),
		],
	},
	{
		"id": "large_forest",
		"role": "large",
		"center": Vector2(-600, 470),
		"trees": [
			Vector2(-500, 350), Vector2(-560, 345), Vector2(-620, 340),
			Vector2(-680, 345), Vector2(-460, 400), Vector2(-520, 400),
			Vector2(-580, 405), Vector2(-640, 410), Vector2(-740, 420),
			Vector2(-480, 460), Vector2(-540, 470), Vector2(-600, 470),
			Vector2(-660, 465), Vector2(-720, 470), Vector2(-760, 460),
			Vector2(-500, 520), Vector2(-560, 530), Vector2(-620, 530),
			Vector2(-680, 520), Vector2(-520, 580), Vector2(-580, 590),
			Vector2(-640, 585), Vector2(-720, 550), Vector2(-760, 530),
			Vector2(-700, 600), Vector2(-700, 400),
		],
	},
	{
		"id": "sparse_forest",
		"role": "sparse",
		"center": Vector2(520, -440),
		"trees": [
			Vector2(400, -380), Vector2(450, -410), Vector2(470, -440),
			Vector2(520, -450), Vector2(570, -430), Vector2(620, -390),
			Vector2(470, -500), Vector2(530, -520), Vector2(590, -490),
			Vector2(660, -460), Vector2(710, -490),
		],
	},
]

# 초반 직접 벌목/튜토리얼용 소형 나무 그로브 (정착지 동남쪽 인근).
# 대규모 자원은 외곽으로 옮기되(TASK-012-4 원칙), 최초 나무 채집→첫 Lumberyard로 이어지는
# 초반 루프를 위해 소수 나무만 정착지 근처에 남긴다. 3그루뿐이라 Defense Belt를 완전히
# 막지 않으며(TASK-012-3: 소형 starter tree는 belt 허용, corridor/combat/rally만 피함),
# 도로/Secondary Path/중앙 clearing을 막지 않는다.
const STARTER_TREES := [
	Vector2(340, 320),
	Vector2(310, 150),
	Vector2(150, 300),
]

# SE Stone Zone (TASK-012-4): 첫 StoneDeposit + Quarry 확장의 중심.
# 중앙에서 충분히 외곽(거리 ~560px, Defense Belt 360~520px 바깥)에 두어
# 성벽 안/밖 포함 여부를 전략적으로 선택할 수 있게 한다.
# SE Stone Zone의 공간 역할(탐색/확장 대상, 성벽 안/밖 선택)을 유지하면서
# 초반~중반 Quarry 확장의 동선에 맞춰 중심을 (+480,+360) 후보에서 (+500,+260)으로 조정했다.
const STONE_ZONE := {
	"center": Vector2(500, 260),
	"deposit_pos": Vector2(500, 260),
}

# 장식용 오브젝트 (순수 시각 전용, 충돌/내비게이션 영향 없음). 랜덤 배치 아님.
const DECORATIONS := [
	# 근거리 바위 (정착지 주변, 건설 공간은 피함)
	{"type": "rock", "pos": Vector2(220, 200), "scale": 0.8},
	{"type": "rock", "pos": Vector2(-210, 230), "scale": 0.6},
	{"type": "rock", "pos": Vector2(240, -220), "scale": 0.7},
	{"type": "rock", "pos": Vector2(-230, -210), "scale": 0.9},
	# 도로변 덤불 (Main Road 반폭 40px 바깥으로 밀어 도로를 막지 않게 함)
	{"type": "bush", "pos": Vector2(330, 64), "scale": 0.5},
	{"type": "bush", "pos": Vector2(-330, 64), "scale": 0.6},
	{"type": "bush", "pos": Vector2(64, -330), "scale": 0.5},
	{"type": "bush", "pos": Vector2(-64, 330), "scale": 0.5},
	# 야생 바위
	{"type": "rock", "pos": Vector2(700, -350), "scale": 0.8},
	{"type": "rock", "pos": Vector2(-700, 350), "scale": 0.7},
	{"type": "bush", "pos": Vector2(350, -700), "scale": 0.6},
	{"type": "bush", "pos": Vector2(-350, 700), "scale": 0.6},
	# SE Stone Zone 주변 장식 바위 (TASK-012-4). 순수 시각용(충돌 없음)이라
	# Quarry placement를 막지 않는다. StoneDeposit 중심(+500,+260)에서 약 70~100px 거리에 배치.
	{"type": "rock", "pos": Vector2(440, 200), "scale": 0.7},
	{"type": "rock", "pos": Vector2(560, 320), "scale": 0.6},
	{"type": "rock", "pos": Vector2(440, 320), "scale": 0.8},
	{"type": "rock", "pos": Vector2(560, 200), "scale": 0.7},
	{"type": "rock", "pos": Vector2(480, 170), "scale": 0.6},
]

# 향후 Gate Anchor 후보 지점 (비기능 Marker). 맵 가장자리 근처.
const GATE_ANCHORS := {
	"north": Vector2(0, -AXIS_OUTER),
	"south": Vector2(0, AXIS_OUTER),
	"east": Vector2(AXIS_OUTER, 0),
	"west": Vector2(-AXIS_OUTER, 0),
}

# 향후 Portal / Enemy Spawn 후보 지점 (비기능 Marker, TASK-012-6).
# 기존 SpawnCandidate 4곳을 Portal/Wave가 연결될 Outer Wild 후보지로 재배치/정리한다.
# 각 후보는 해당 방향 Main Road 끝단(Outer Wild terminus) 근처의 오프축 위치에 두어,
# Gate 정면의 완전한 직선상(lane map)처럼 보이지 않게 한다.
# 실제 Portal/Enemy spawn 기능은 구현하지 않는다.
const SPAWN_CANDIDATES := {
	"north": Vector2(-140, -900),
	"south": Vector2(120, 900),
	"east": Vector2(900, -120),
	"west": Vector2(-900, 160),
}

# --- TASK-012-6 Approach Route ---
# Portal Candidate → Main Road → Gate Corridor 흐름이 가능하도록,
# 각 후보가 해당 방향 Main Road 끝단(Outer Wild terminus)에 자연스럽게 합류하는
# 접근로(centerline 폴리라인)를 레벨디자인상 확보한다. 반폭 32px(=2 논리 타일).
# 각 후보는 Main Road 정면 직선상이 아니라 오프축에 두어 lane map처럼 보이지 않게 하고,
# 이 접근로로 도로에 합류한다. 실제 Enemy pathfinding/웨이브 로직은 구현하지 않는다.
const APPROACH_ROUTE_HALF := 32.0

const APPROACH_ROUTES := {
	"north": [Vector2(-140, -900), Vector2(-100, -960)],
	"south": [Vector2(120, 900), Vector2(100, 960)],
	"east": [Vector2(900, -120), Vector2(960, -100)],
	"west": [Vector2(-900, 160), Vector2(-960, 100)],
}

# --- TASK-012-5 미래 콘텐츠 슬롯 (레벨디자인상 공간만 확보, 실제 기능 없음) ---
# 이 상수들은 향후 Farm/Herb/Dungeon/이벤트 등이 들어갈 공간을 좌표로 예약한다.
# 실제 시스템(건설/생산/전투/이동 규칙/씬 전환)은 구현하지 않는다.

# South Agriculture Zone: 남쪽 +450~+650px에 걸친 평평한 미래 농업 공간.
# 다른 방향보다 대형 자연 장애물(숲/석재)을 적게 두어 Farm/Herb Field/Greenhouse
# 배치를 위한 충분한 여지를 남긴다. 실제 Farm/Herb 시스템은 구현하지 않는다.
const SOUTH_AGRICULTURE_ZONE := Rect2(-320, 450, 640, 200)

# NE Dungeon Candidate: Player가 향후 직접 발견하러 갈 수 있는 Outer Wild 위치.
# Marker/placeholder(비기능) 수준만 허용. 실제 entrance/combat/씬 전환 금지.
const NE_DUNGEON_CANDIDATE := Vector2(720, -700)

# Outer Wild 미래 콘텐츠 슬롯: 맵 코너를 장식으로 전부 채우지 않고 예약해 둔다.
# 각 슬롯은 참고용 Marker + 범위로 식별 가능. 실제 시스템처럼 동작하지 않는다.
const OUTER_WILD_SLOTS := {
	"nw": Rect2(-930, -930, 160, 160),   # future dungeon/event 후보
	"ne": Rect2(770, -930, 160, 160),    # 첫 Dungeon Candidate 방향(Outer NE)
	"sw": Rect2(-930, 770, 160, 160),    # future event/resource
	"se": Rect2(770, 770, 160, 160),     # future special area
}

# --- Defense Belt / Gate Corridor (TASK-012-3) ---
# 자유 성벽 배치를 위해 확보하는 연속 빈 공간. 중심에서 약 360~520px.
const DEFENSE_BELT_INNER := 360.0
const DEFENSE_BELT_OUTER := 520.0

# Gate Corridor: 각 Main Road를 중심으로 성벽과 도로가 교차할 수 있는 허용 구간.
# Gate를 정확히 한 점에 강제하지 않고, 이 영역 안 어디든 Wall/Gate가 들어갈 수 있게
# 레벨디자인상 확보해 둔다. 실제 Gate 기능/placement validation은 구현하지 않는다.
const GATE_CORRIDORS := {
	"north": Rect2(-48, -540, 96, 190),
	"south": Rect2(-48, 350, 96, 190),
	"west": Rect2(-540, -48, 190, 96),
	"east": Rect2(350, -48, 190, 96),
}

# Gate 바깥 Combat Field: 각 Gate Corridor 외측에 최소 약 200x160 open space.
const COMBAT_FIELDS := {
	"north": Rect2(-100, -700, 200, 160),
	"south": Rect2(-100, 540, 200, 160),
	"west": Rect2(-700, -100, 160, 200),
	"east": Rect2(540, -100, 160, 200),
}

# Gate 안쪽 Rally Space: 각 Gate Corridor 안쪽에 약 120~160px 깊이의 비교적 열린 공간.
const RALLY_SPACES := {
	"north": Rect2(-80, -350, 160, 140),
	"south": Rect2(-80, 210, 160, 140),
	"west": Rect2(-350, -80, 140, 160),
	"east": Rect2(210, -80, 140, 160),
}


func get_bounds_rect() -> Rect2:
	return BOUNDS_RECT


func get_nav_rect() -> Rect2:
	return NAV_RECT


func get_clearing_rect() -> Rect2:
	return Rect2(SETTLEMENT_CENTER - CLEARING_HALF, CLEARING_HALF * 2.0)


func get_wall_buffer_rect() -> Rect2:
	return Rect2(SETTLEMENT_CENTER - WALL_BUFFER_HALF, WALL_BUFFER_HALF * 2.0)


func is_in_clearing(pos: Vector2) -> bool:
	return get_clearing_rect().has_point(pos)


func is_in_wall_buffer(pos: Vector2) -> bool:
	return get_wall_buffer_rect().has_point(pos) and not is_in_clearing(pos)


func is_on_access_axis(pos: Vector2) -> bool:
	for dir in MAIN_ROADS:
		if _dist_to_polyline(pos, MAIN_ROADS[dir]) <= MAIN_ROAD_HALF:
			return true
	return false


func is_on_secondary_path(pos: Vector2) -> bool:
	for id in SECONDARY_PATHS:
		if _dist_to_polyline(pos, SECONDARY_PATHS[id]) <= SECONDARY_PATH_HALF:
			return true
	return false


func is_on_any_path(pos: Vector2) -> bool:
	return is_on_access_axis(pos) or is_on_secondary_path(pos)


func get_main_road(direction: String) -> Array:
	return MAIN_ROADS.get(direction, [])


func get_secondary_path(id: String) -> Array:
	return SECONDARY_PATHS.get(id, [])


func _dist_to_polyline(point: Vector2, poly: Array) -> float:
	if poly.is_empty():
		return INF
	if poly.size() == 1:
		return point.distance_to(poly[0])
	var best := INF
	for i in range(poly.size() - 1):
		best = minf(best, _dist_to_segment(point, poly[i], poly[i + 1]))
	return best


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func is_in_bounds(pos: Vector2) -> bool:
	return BOUNDS_RECT.has_point(pos)


func get_gate_anchor(direction: String) -> Vector2:
	return GATE_ANCHORS.get(direction, SETTLEMENT_CENTER)


func get_gate_anchor_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("GateAnchor_"):
			nodes.append(child)
	return nodes


func get_spawn_candidate_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("SpawnCandidate_"):
			nodes.append(child)
	return nodes


# --- TASK-012-6 Portal Candidate / Approach Route helpers ---

func get_spawn_candidates() -> Dictionary:
	return SPAWN_CANDIDATES


func get_spawn_candidate(direction: String) -> Vector2:
	return SPAWN_CANDIDATES.get(direction, SETTLEMENT_CENTER)


func get_approach_route(direction: String) -> Array:
	return APPROACH_ROUTES.get(direction, [])


func is_on_approach_route(pos: Vector2) -> bool:
	for dir in APPROACH_ROUTES:
		if _dist_to_polyline(pos, APPROACH_ROUTES[dir]) <= APPROACH_ROUTE_HALF:
			return true
	return false


func get_approach_route_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("ApproachRoute_"):
			nodes.append(child)
	return nodes


# --- TASK-012-3 Defense Belt / Gate Corridor helpers ---

func get_defense_belt_inner() -> float:
	return DEFENSE_BELT_INNER


func get_defense_belt_outer() -> float:
	return DEFENSE_BELT_OUTER


func get_gate_corridor(direction: String) -> Rect2:
	return GATE_CORRIDORS.get(direction, Rect2())


func get_combat_field(direction: String) -> Rect2:
	return COMBAT_FIELDS.get(direction, Rect2())


func get_rally_space(direction: String) -> Rect2:
	return RALLY_SPACES.get(direction, Rect2())


func is_in_defense_belt(pos: Vector2) -> bool:
	var d := pos.distance_to(SETTLEMENT_CENTER)
	return d >= DEFENSE_BELT_INNER and d <= DEFENSE_BELT_OUTER


func is_in_gate_corridor(pos: Vector2) -> bool:
	for dir in GATE_CORRIDORS:
		if GATE_CORRIDORS[dir].has_point(pos):
			return true
	return false


## TASK-013-3: 해당 지점이 어느 Gate Corridor에 속하는지 방향을 반환.
## 어떤 corridor에도 없으면 빈 문자열.
func get_gate_corridor_direction(pos: Vector2) -> String:
	for dir in GATE_CORRIDORS:
		if GATE_CORRIDORS[dir].has_point(pos):
			return dir
	return ""


func is_in_combat_field(pos: Vector2) -> bool:
	for dir in COMBAT_FIELDS:
		if COMBAT_FIELDS[dir].has_point(pos):
			return true
	return false


func is_in_rally_space(pos: Vector2) -> bool:
	for dir in RALLY_SPACES:
		if RALLY_SPACES[dir].has_point(pos):
			return true
	return false


func get_gate_corridor_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("GateCorridor_"):
			nodes.append(child)
	return nodes


func get_combat_field_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("CombatField_"):
			nodes.append(child)
	return nodes


func get_rally_space_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("RallySpace_"):
			nodes.append(child)
	return nodes


# --- TASK-012-4 Resource Region helpers ---

func get_forest_clusters() -> Array:
	return FOREST_CLUSTERS


func get_forest_cluster(role: String) -> Dictionary:
	for cluster in FOREST_CLUSTERS:
		if String(cluster.get("role", "")) == role:
			return cluster
	return {}


func get_forest_cluster_trees(role: String) -> Array:
	var cluster := get_forest_cluster(role)
	return cluster.get("trees", [])


func get_starter_trees() -> Array:
	return STARTER_TREES


func get_stone_zone_center() -> Vector2:
	return Vector2(STONE_ZONE.get("center", Vector2.ZERO))


func get_stone_deposit_pos() -> Vector2:
	return Vector2(STONE_ZONE.get("deposit_pos", Vector2.ZERO))


func is_in_defense_belt_near(pos: Vector2, dir: String) -> bool:
	# 방향별 Defense Belt 링 구간만 확인 (테스트/설계 검토용).
	var sector := Vector2.ZERO
	match dir:
		"north":
			sector = Vector2(0, -1)
		"south":
			sector = Vector2(0, 1)
		"west":
			sector = Vector2(-1, 0)
		"east":
			sector = Vector2(1, 0)
	return is_in_defense_belt(pos) and pos.normalized().dot(sector) >= 0.5


# --- TASK-012-5 미래 콘텐츠 슬롯 helpers ---

func get_south_agriculture_zone() -> Rect2:
	return SOUTH_AGRICULTURE_ZONE


func is_in_south_agriculture_zone(pos: Vector2) -> bool:
	return SOUTH_AGRICULTURE_ZONE.has_point(pos)


func get_ne_dungeon_candidate() -> Vector2:
	return NE_DUNGEON_CANDIDATE


func get_outer_wild_slots() -> Dictionary:
	return OUTER_WILD_SLOTS


func get_outer_wild_slot(id: String) -> Rect2:
	return OUTER_WILD_SLOTS.get(id, Rect2())


func is_in_outer_wild_slot(pos: Vector2) -> bool:
	for id in OUTER_WILD_SLOTS:
		if OUTER_WILD_SLOTS[id].has_point(pos):
			return true
	return false


func get_south_agriculture_marker() -> Node:
	return get_node_or_null("SouthAgricultureZone")


func get_ne_dungeon_marker() -> Node:
	return get_node_or_null("NeDungeonCandidate")


func get_outer_wild_markers() -> Array[Node]:
	var nodes: Array[Node] = []
	for child in get_children():
		if child is Marker2D and String(child.name).begins_with("OuterWild_"):
			nodes.append(child)
	return nodes