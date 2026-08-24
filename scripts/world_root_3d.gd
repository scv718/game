extends Node3D
class_name WorldRoot3D

## TASK-3D-001-2 World3D Root Foundation.
## 기존 2D world.tscn(world.gd)과 병행 운영되는 신규 Node3D 기반 World Root.
##
## - XZ = 지면 이동 평면, Y = 높이. ground Y = 0 고정(자유 높이 이동/점프 없음).
## - 좌표 변환은 WorldCoords3D, 충돌 layer/mask는 CollisionLayers3D 단일 소스 사용.
## - Ground(StaticBody3D)가 지면 1면 + 경계 벽 4개만 가진다(physics-heavy terrain 금지).
## - Camera3D(001-3), Interaction3D 계약(001-4), Navigation3D(001-5)는
##   각 Foundation 태스크가 이 Root 위에 자기 소유 파일로 연결한다.
## - UI는 CanvasLayer/Control 계층으로 유지되며 이 Root와 physics적으로 분리된다.
## - 기존 2D Main World는 즉시 삭제하지 않고 reference로 유지한다(LOCK 12).
##
## 참고: Godot 내장 resource class `World3D` 와의 충돌을 피하기 위해
## script class 이름은 WorldRoot3D를 사용한다.

const GROUND_Y := WorldCoords3D.GROUND_Y

@onready var _ground: StaticBody3D = $Ground


func _ready() -> void:
	add_to_group("world3d")


## 기존 BOUNDS_RECT(-1536,-1536,3072,3072 px)와 동일 범위의 XZ AABB.
func get_bounds_aabb() -> AABB:
	return WorldCoords3D.world_bounds_aabb()


func is_in_bounds(pos: Vector3) -> bool:
	return WorldCoords3D.is_in_bounds_xz(pos)


func get_ground_body() -> StaticBody3D:
	return _ground


## logical 2D 좌표를 이 월드의 지면 좌표로 변환하는 편의 함수.
func ground_position(logical: Vector2) -> Vector3:
	return WorldCoords3D.to_world_xz(logical)
