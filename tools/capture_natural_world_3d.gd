extends SceneTree

const VIEWS := [
	["world_overview", Vector3(0,0,0), 450.0],
	["world_clearing", Vector3(0,0,0), 150.0],
	["world_river", Vector3(117,0,20), 130.0],
	["world_forest", Vector3(15,0,-142), 120.0],
	["world_portal_horizon", Vector3(-160,0,-65), 160.0],
	["world_corruption", Vector3(-160,0,15), 150.0],
]
var main: Node
var controller: Node3D
var camera: Camera3D
var frames:=0
var view:=0

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	root.size=Vector2i(1600,900)
	main=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(main)
	if get_first_node_in_group("natural_world_3d")==null:
		push_error("Natural world failed to initialize; refusing misleading captures")
		quit(1)
		return
	controller=main.get_node("CameraController3D")
	camera=controller.get_camera()
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.set_process_unhandled_input(false)
	_set_view()

func _set_view() -> void:
	controller.position=VIEWS[view][1]
	camera.size=VIEWS[view][2]
	frames=0

func _process(_delta: float) -> bool:
	if camera==null:return false
	frames+=1
	if frames<70:return false
	if DisplayServer.get_name()=="headless":
		push_error("Capture requires the GPU renderer, run without --headless")
		quit(1);return true
	var img:=root.get_texture().get_image()
	if img==null:quit(1);return true
	var path: String="res://test_results/"+VIEWS[view][0]+".png"
	var err:=img.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ",path," result=",err)
	view+=1
	if view==VIEWS.size():quit();return true
	_set_view()
	return false
