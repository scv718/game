extends SceneTree

var failures:=0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main:=load("res://scenes/main_3d.tscn").instantiate() as Node3D
	root.add_child(main)
	await physics_frame
	await physics_frame
	var nature:=get_first_node_in_group("natural_world_3d")
	_check(nature!=null,"fixed natural environment exists in main")
	var placement:=main.get_node("BuildingPlacement3D")
	placement._building_type="cuteskull/House_1_1"
	for x in [-40.0,-20.0,0.0,20.0,40.0]:
		for z in [-40.0,-20.0,0.0,20.0,40.0]:
			_check(placement._is_valid_position(Vector3(x,0,z)),"clearing accepts House at %s,%s"%[x,z])
	var river_pos:=Vector3(nature.river_x(60.0),0,60)
	_check(not placement._is_valid_position(river_pos),"deep river rejects construction through existing overlap flow")
	var tree:Node3D
	for child in nature.get_children():
		if String(child.name).begins_with("ForestTrunk"):
			tree=child;break
	_check(tree!=null and not placement._is_valid_position(tree.global_position),"forest trunks reject building overlap")
	var nav:=main.get_node("World3D/NavigationManager3D")
	var map:RID=nav.get_navigation_map()
	# The map sync is asynchronous; wait for the baked region rather than assuming
	# two physics frames are sufficient on every machine.
	for attempt in range(100):
		if NavigationServer3D.map_get_closest_point(map,Vector3(55,0,35)).distance_to(Vector3(55,0,35))<1:break
		await create_timer(.1).timeout
	var path:=NavigationServer3D.map_get_path(map,Vector3(0,0,0),Vector3(55,0,35),true)
	_check(not path.is_empty() and path[-1].distance_to(Vector3(55,0,35))<1,"central clearing remains navigable")
	var crossing:=NavigationServer3D.map_get_path(map,Vector3(70,0,0),Vector3(160,0,0),true)
	_check(not crossing.is_empty() and crossing[-1].distance_to(Vector3(160,0,0))<1,"ford connects both river banks")
	_check(NavigationServer3D.map_get_closest_point(map,river_pos).distance_to(river_pos)>3,"deep river excluded from walkable ground")
	placement._try_place_at(Vector3.ZERO)
	await physics_frame
	_check(get_nodes_in_group("buildings_3d").size()==1,"House actually places in main through existing catalog flow")
	placement._building_type="cuteskull/House_1_1"
	_check(not placement._is_valid_position(Vector3.ZERO),"placed House still rejects a second overlapping House")
	placement._toggle_catalog()
	_check(placement.is_catalog_open(),"B-key catalog flow opens")
	placement._toggle_catalog()
	_check(not placement.is_catalog_open(),"catalog closes")
	var portal:=main.get_node_or_null("World3D/WorldContent3D/DistantPortal/AbyssCore") as MeshInstance3D
	_check(portal!=null and portal.material_override is ShaderMaterial,"main uses animated abyss surface")
	_check(main.get_node_or_null("World3D/VillageComposition3D")==null,"no automatic village restored")
	print("NATURAL_WORLD_3D_RESULT=", "PASS" if failures==0 else "FAIL")
	# Let a requested placement nav bake finish before releasing the scene.
	await create_timer(2.0).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)

func _check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failures+=1
