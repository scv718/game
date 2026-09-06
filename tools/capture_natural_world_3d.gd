extends SceneTree

const VIEWS := [
	["world_overview", Vector3(0,0,0), 1350.0],
	["world_clearing", Vector3(0,0,0), 440.0],
	["world_river", Vector3(350,0,30), 240.0],
	["world_forest", Vector3(120,0,-450), 250.0],
	["world_portal_horizon", Vector3(-565,0,-220), 260.0],
	["world_corruption", Vector3(-540,0,-80), 440.0],
]
var main: Node
var controller: Node3D
var camera: Camera3D
var frames:=0
var view:=0

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var startup_ms:=Time.get_ticks_msec()
	root.size=Vector2i(1600,900)
	main=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(main)
	print("MAIN_STARTUP_MS=",Time.get_ticks_msec()-startup_ms)
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
	# Overview inspection needs depth on both sides of the pivot. Gameplay
	# projection, zoom limits and orientation are unchanged.
	camera.position=camera.basis*Vector3(0,0,maxf(160.0,camera.size*1.2))
	frames=0

func _process(_delta: float) -> bool:
	if camera==null:return false
	frames+=1
	if frames<(240 if view==0 else 90):return false
	if DisplayServer.get_name()=="headless":
		push_error("Capture requires the GPU renderer, run without --headless")
		quit(1);return true
	var img:=root.get_texture().get_image()
	if img==null:quit(1);return true
	var path: String="res://test_results/"+VIEWS[view][0]+".png"
	var err:=img.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ",path," result=",err)
	print("VIEW_METRICS ",VIEWS[view][0]," fps=",Performance.get_monitor(Performance.TIME_FPS)," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	view+=1
	if view==VIEWS.size():quit();return true
	_set_view()
	return false
