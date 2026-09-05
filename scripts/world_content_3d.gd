extends Node3D
class_name WorldContent3D

## TASK-3D-INT-001-2 3D Main World gameplay content 조립.
## 기존 world.tscn이 scene으로 가지고 있던 자원 content(Tree x60 + StoneDeposit)를
## WorldMap 상수(읽기 전용 참조)에서 결정적으로 생성하는 신규 파일이다.
## 기존 2D world.tscn / tree.tscn / stone_deposit.tscn은 LOCK 12에 따라 무수정.
##
## - 배치 좌표는 전부 기존 world.tscn과 동일 논리 좌표다. 2D world.tscn의 Tree는
##   STARTER_TREES 3그루 + FOREST_CLUSTERS(starter/large/sparse) 57그루 = 60그루이고,
##   StoneDeposit은 STONE_ZONE.deposit_pos다. XZ 해석은 WorldCoords3D.to_world_xz
##   단일 소스만 사용한다(좌표 관례 LOCK).
## - 생성 순서가 결정적이라(RNG 없음) 반복 실행에서 동일한 월드가 만들어진다.
##   개체 비주얼 variation은 각 scene 스크립트(tree_3d.gd의 hash 기반 흔들기) 소유다.
## - spawn 대상은 RES 도메인의 3D scene 그대로다(tree_3d.tscn = Area3D +
##   TrunkBlock, stone_deposit_3d.tscn = Node3D + Block). group("resource_nodes_3d" /
##   "stone_deposits_3d")와 depletion/regrow/occupy 규약은 RES 소유 계약을 무수정
##   소비한다. 장식(decoration/terrain dressing)은 VIS-002 소유로 여기서 만들지 않는다.
## - 핵심 건물 5종/MapLayout은 main_3d.tscn 쪽 wiring(spawner/roster가 world 루트의
##   직접 자식 "Keep"/"MapLayout"을 조회하므로)으로 두고, 이 노드는 수식 content만
##   담당한다.

const TREE_SCENE := preload("res://scenes/tree_3d.tscn")
const STONE_DEPOSIT_SCENE := preload("res://scenes/stone_deposit_3d.tscn")
const VILLAGE_COMPOSITION_SCRIPT := preload("res://scripts/village_composition_3d.gd")

var _spawned := false
@export var grass_only := false


func _ready() -> void:
	# 중복 실행 방지(씬 재진입/테스트에서의 이중 add_child 대비). 멱등.
	if _spawned:
		return
	_spawned = true
	# 실제 런타임에서도 placeholder GroundVisual에 stylized 잔디 톤을 입힌다.
	# (캡처 도구만 톤을 입혀 실제 게임이 흰 필드로 보이던 문제 해결 - VIS-001-5 계약
	# apply_ground_tone 재사용. 이 노드의 parent가 world3d.tscn World3D 루트다.)
	var composition: Node = VILLAGE_COMPOSITION_SCRIPT.new()
	composition.apply_ground_tone(get_parent())
	composition.spawn_distant_portal(self, Vector3(-175.0, 0.0, 0.0))
	composition.free()
	if grass_only:
		return
	_spawn_starter_trees()
	_spawn_forest_clusters()
	_spawn_stone_deposit()


func get_tree_count() -> int:
	var n := 0
	for child in get_children():
		if child is WorldTree3D:
			n += 1
	return n


func get_stone_deposit() -> StoneDeposit3D:
	for child in get_children():
		if child is StoneDeposit3D:
			return child
	return null


func _spawn_starter_trees() -> void:
	for logical in WorldMap.STARTER_TREES:
		_spawn_tree(logical)


func _spawn_forest_clusters() -> void:
	for cluster in WorldMap.FOREST_CLUSTERS:
		for logical in cluster.get("trees", []):
			_spawn_tree(logical)


func _spawn_stone_deposit() -> void:
	var deposit := STONE_DEPOSIT_SCENE.instantiate() as StoneDeposit3D
	# WorldMap.STONE_ZONE.deposit_pos(읽기 전용 상수). world_map.gd의
	# get_stone_deposit_pos()와 동일 조회다(instance helper가 아닌 상수 직접 참조).
	var logical: Vector2 = Vector2(WorldMap.STONE_ZONE.get("deposit_pos", Vector2.ZERO))
	deposit.position = WorldCoords3D.to_world_xz(logical)
	add_child(deposit)


func _spawn_tree(logical: Vector2) -> void:
	var tree := TREE_SCENE.instantiate() as WorldTree3D
	tree.position = WorldCoords3D.to_world_xz(logical)
	add_child(tree)


