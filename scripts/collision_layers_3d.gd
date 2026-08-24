extends RefCounted
class_name CollisionLayers3D

## TASK-3D-001-2 공통 3D Collision Layer / Mask 정책 (단일 소스).
##
## 기존 2D 관례를 구조 그대로 유지하면서 카테고리만 세분한다.
##   - 2D: 정적 블로커(건물/벽/문/자원/경계) = layer value 4, Interactable Area2D = 8,
##         Actor(CharacterBody2D) = layer 2 / mask 4 (actor끼리 물리 충돌 없음).
##   - 3D: 아래 표처럼 Building/Wall/Gate/Resource를 분리해 구분 가능하게 하고,
##         선택용 INTERACTABLE은 Area3D 전용 layer로 유지한다.
##
## Layer 배치표 (layer 번호 = bit index + 1):
##   1 GROUND       지면 바닥 + 월드 경계 벽 (World Root 소유)
##   2 BUILDING     핵심 건물 / Lumberyard / Quarry 등 건물 본체
##   3 WALL         Wall segment
##   4 GATE         Gate 본체 (CLOSED/OPEN/BREACHED 상태 전환 대상)
##   5 RESOURCE     Tree trunk / Stone deposit 등 자원 블록
##   6 WORKER       Lumberjack / Miner 등 Worker Actor
##   7 MERCENARY    Mercenary Actor
##   8 ENEMY        Enemy Actor
##   9 INTERACTABLE 마우스 선택/상호작용 Area3D (물리 블록 아님)
##
## Mask 규칙:
##   - 정적 바디(GROUND/BUILDING/WALL/GATE/RESOURCE)는 collision_mask = 0 (수동 블로커).
##   - Actor는 collision_layer = 자기 카테고리 1개, collision_mask = MASK_ACTOR_SOLID.
##     -> 기존 2D와 동일하게 actor끼리 밀어내지 않고, 정적 지형/블록에만 막힌다.
##   - 마우스 selection/probe는 MASK_SELECTION(INTERACTABLE)만 조회한다.
##     Resource는 Worker 전용으로 남겨 Player 마우스 직접 채집을 차단하는
##     기존 world_selection.gd 정책을 그대로 따른다.
##   - BuildingPlacement overlap 검증은 MASK_PLACEMENT_BLOCKERS를 사용한다.
##
## UI(CanvasLayer/Control)는 physics layer와 무관하며 별도 계층으로 유지한다.

const LAYER_GROUND := 1
const LAYER_BUILDING := 2
const LAYER_WALL := 3
const LAYER_GATE := 4
const LAYER_RESOURCE := 5
const LAYER_WORKER := 6
const LAYER_MERCENARY := 7
const LAYER_ENEMY := 8
const LAYER_INTERACTABLE := 9

const GROUND := 1 << (LAYER_GROUND - 1)                # 1
const BUILDING := 1 << (LAYER_BUILDING - 1)            # 2
const WALL := 1 << (LAYER_WALL - 1)                    # 4
const GATE := 1 << (LAYER_GATE - 1)                    # 8
const RESOURCE := 1 << (LAYER_RESOURCE - 1)            # 16
const WORKER := 1 << (LAYER_WORKER - 1)                # 32
const MERCENARY := 1 << (LAYER_MERCENARY - 1)          # 64
const ENEMY := 1 << (LAYER_ENEMY - 1)                  # 128
const INTERACTABLE := 1 << (LAYER_INTERACTABLE - 1)    # 256

## Actor가 실제로 부딪히는 정적 블로커 집합 (지면 + 건물 + 벽 + 문 + 자원).
const MASK_ACTOR_SOLID := GROUND | BUILDING | WALL | GATE | RESOURCE

## 건설 placement 겹침 금지 대상 (지면 자체는 제외 - 어디든 지상에 배치 가능).
const MASK_PLACEMENT_BLOCKERS := BUILDING | WALL | GATE | RESOURCE

## 마우스 선택/interaction probe 전용.
const MASK_SELECTION := INTERACTABLE

## 전투/이동에서 actor 카테고리 전체 조회용 (물리 충돌 마스크 아님, 탐색/query 용도).
const MASK_ACTORS := WORKER | MERCENARY | ENEMY


static func layer_bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)
