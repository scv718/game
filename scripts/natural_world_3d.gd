extends Node3D
## Fixed environment dressing. All blockers use the existing resource collision
## layer, so placement and the canonical navigation baker see the same geometry.

const CLEARING := Rect2(-62, -60, 124, 120)
const SEED := 731904
var rng := RandomNumberGenerator.new()
var models: Dictionary = {}
var bounds: Dictionary = {}
var forest_count := 0
var terrain_material: ShaderMaterial
var river_collision: SurfaceTool

func _ready() -> void:
	name = "NaturalWorld3D"
	add_to_group("natural_world_3d")
	rng.seed = SEED
	_ground()
	_river()
	_forests()
	_rocklands()
	_corruption()
	_abyss()

func _abyss() -> void:
	var portal := get_parent().get_node("DistantPortal") as Node3D
	for child in portal.get_children(): child.free()
	portal.position=Vector3(-190,0,-70)
	var shader:=Shader.new()
	shader.code="""
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	void fragment(){
	vec2 p=(UV*2.0-1.0);p.y=-p.y;
	float a=atan(p.y,p.x);float r=length(p);
	float warp=sin(a*11.0+TIME*.7)*.012+sin(a*23.0-TIME*1.2)*.008;
	float rim=exp(-abs(r-.65+warp)*100.0);
	float tendril=pow(.5+.5*sin(a*9.0-r*30.0+TIME*1.5),9.0);
	float aura=exp(-abs(r-.69+warp)*13.0)*(.2+tendril*.8);
	float curl=pow(.5+.5*sin(a*5.0-r*24.0+TIME),14.0);
	float inside=(1.0-smoothstep(.3,.64,r))*smoothstep(.26,.58,r)*curl;
	float black=1.0-smoothstep(.635,.665,r+warp);
	float opacity=max(black,clamp(rim+aura*.85,0.0,.9));
	if(opacity<.008)discard;
	vec3 violet=vec3(.33,.018,.63)*(rim*2.7+aura*.85+inside*.32);
	ALBEDO=vec3(.001,.0005,.003)+violet;EMISSION=violet*1.5;ALPHA=opacity;
	}
	"""
	var mat:=ShaderMaterial.new()
	mat.shader=shader
	var quad:=QuadMesh.new()
	quad.size=Vector2(186,186)
	var core:=MeshInstance3D.new()
	core.name="AbyssCore"
	core.mesh=quad
	core.material_override=mat
	core.position.y=-5
	core.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal.add_child(core)
	# Low overlapping rock shoulders conceal the cut at ground level.
	for i in range(29):
		var x:float=-260.0+i*5.0
		_model("rock/medium_%d"%(1+i%3),Vector3(x,0,-69+sin(i*.7)*2),rng.randf_range(6,10))

static func river_x(z: float) -> float:
	return 112.0 + sin(z * 0.016) * 27.0 + sin(z * 0.033 + 0.7) * 9.0

static func river_width(z: float) -> float:
	return 15.0 + 5.0 * sin(z * 0.021 + 1.0)

static func is_ford(z: float) -> bool:
	return absf(z) < 10.0 or absf(z - 116.0) < 9.0

func _ground() -> void:
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode cull_disabled;
	varying vec3 world;
	uniform sampler2D terrain_noise : filter_linear_mipmap, repeat_enable;
	float noise(vec2 p){return texture(terrain_noise,p*.025).r;}
	void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
	void fragment(){
	vec2 p=world.xz;
	float n=noise(p*.045)*.65+noise(p*.12)*.35;
	float fine=noise(p*2.8);
	vec3 grass=mix(vec3(.105,.16,.067),vec3(.31,.34,.14),n);
	grass*=.86+fine*.27;
	float rx=112.0+sin(p.y*.016)*27.0+sin(p.y*.033+.7)*9.0;
	float rw=15.0+5.0*sin(p.y*.021+1.0);
	float bank=1.0-smoothstep(rw*.5+2.0,rw*.5+11.0,abs(p.x-rx)+noise(p*.2)*2.0);
	grass=mix(grass,vec3(.29,.255,.17)*(.8+n*.4),bank*.9);
	float dead=1.0-smoothstep(-170.0,-80.0,p.x+(n-.5)*24.0);
	vec3 ash=mix(vec3(.055,.045,.062),vec3(.17,.145,.155),n);
	ALBEDO=mix(grass,ash,dead);ROUGHNESS=.95;
	}
	"""
	var material := ShaderMaterial.new()
	material.shader = shader
	terrain_material=material
	var noise:=FastNoiseLite.new()
	noise.seed=SEED
	noise.frequency=.018
	var texture:=NoiseTexture2D.new()
	texture.width=512
	texture.height=512
	texture.seamless=true
	texture.noise=noise
	material.set_shader_parameter("terrain_noise",texture)
	var ground := get_parent().get_parent().get_node("GroundVisual") as MeshInstance3D
	ground.visible = false
	# Extend the backdrop beyond all gameplay bounds, hiding the rectangular edge.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800, 1800)
	_mesh("DistantGround", plane, material, Vector3(0, 0, 0))

func _river() -> void:
	river_collision=SurfaceTool.new()
	river_collision.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water := Shader.new()
	water.code = """
	shader_type spatial;
	render_mode cull_disabled;
	varying vec3 world;
	void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
	void fragment(){
	float edge=pow(abs(UV.x*2.0-1.0),7.0);
	float ripple=sin(world.z*1.6+world.x*.6-TIME*1.7)*sin(world.x*3.1+TIME*.6);
	float foam=ripple*.015+edge*.13;
	float ford=1.0-smoothstep(7.0,11.0,abs(world.z));
	ford=max(ford,1.0-smoothstep(6.0,10.0,abs(world.z-116.0)));
	ALBEDO=mix(mix(vec3(.045,.16,.17),vec3(.20,.34,.28),edge),vec3(.24,.30,.23),ford*.7)+foam;
	ROUGHNESS=.3;METALLIC=.16;
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = water
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(160):
		var z := -400.0 + i * 5.0
		var a := Vector3(river_x(z)-river_width(z)*.5, .035, z)
		var b := Vector3(river_x(z)+river_width(z)*.5, .035, z)
		var c := Vector3(river_x(z+5)-river_width(z+5)*.5, .035, z+5)
		var d := Vector3(river_x(z+5)+river_width(z+5)*.5, .035, z+5)
		_triangle(st,a,c,b,Vector2(0,0),Vector2(0,1),Vector2(1,0))
		_triangle(st,b,c,d,Vector2(1,0),Vector2(0,1),Vector2(1,1))
		if absf(z) < 250.0 and not is_ford(z+2.5):
			_river_block(a,b,c,d)
	st.generate_normals()
	_mesh("MeanderingRiver",st.commit(),mat)
	var body:=StaticBody3D.new()
	body.name="RiverBlock"
	body.collision_layer=CollisionLayers3D.RESOURCE
	body.collision_mask=0
	var shape:=CollisionShape3D.new()
	shape.shape=river_collision.commit().create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	for interval in [Vector2(-250,-10),Vector2(10,107),Vector2(125,250)]:
		var obstacle:=NavigationObstacle3D.new()
		obstacle.name="RiverNavigationCut"
		obstacle.avoidance_enabled=false
		obstacle.affect_navigation_mesh=true
		obstacle.carve_navigation_mesh=true
		obstacle.height=8.0
		var left:=PackedVector3Array()
		var right:=PackedVector3Array()
		var steps:=int(ceil((interval.y-interval.x)/3.0))
		for j in range(steps+1):
			var z:=lerpf(interval.x,interval.y,float(j)/steps)
			left.append(Vector3(river_x(z)-river_width(z)*.5-.5,0,z))
			right.append(Vector3(river_x(z)+river_width(z)*.5+.5,0,z))
		right.reverse()
		left.append_array(right)
		obstacle.vertices=left
		add_child(obstacle)
	# Fords are submerged gravel: water remains visible above the crossing.
	for i in range(150):
		var z := rng.randf_range(-280,280)
		if is_ford(z): continue
		var side := -1.0 if i%2==0 else 1.0
		var pos := Vector3(river_x(z)+side*(river_width(z)*.5+rng.randf_range(1.5,5)),0,z)
		_model("rock/medium_1" if i%3==0 else "veg/grass_common_tall",pos,rng.randf_range(.8,2.2))

func _forests() -> void:
	# Authored overlapping groves, with scalloped edges and broad unplanted lanes.
	var groves := [Vector3(-40,0,-135),Vector3(40,0,-165),Vector3(160,0,-150),
		Vector3(205,0,-55),Vector3(205,0,65),Vector3(185,0,185),
		Vector3(65,0,180),Vector3(-30,0,155),Vector3(-85,0,205),
		Vector3(-5,0,-245),Vector3(180,0,-255),Vector3(285,0,80),Vector3(30,0,280)]
	for center in groves:
		for i in range(160):
			var angle := rng.randf()*TAU
			var radius := sqrt(rng.randf())*rng.randf_range(30,54)
			var pos: Vector3 = center+Vector3(cos(angle)*radius,0,sin(angle)*radius*.78)
			if CLEARING.grow(12).has_point(Vector2(pos.x,pos.z)): continue
			if absf(pos.x-river_x(pos.z)) < river_width(pos.z)*.5+8: continue
			var key := "tree/common_%d" % (1+i%5) if i%3!=0 else "tree/pine_%d" % (1+i%2)
			_model(key,pos,rng.randf_range(12.0,20.0))
			forest_count += 1
			if absf(pos.x)<250 and absf(pos.z)<250:
				_block(pos,Vector3(1.4,10,1.4),"ForestTrunk")
			if i%5==0:
				_model("veg/bush_common",pos+Vector3(3,0,1),rng.randf_range(1.5,2.5))

func _rocklands() -> void:
	for center in [Vector3(-78,0,-95),Vector3(46,0,-218),Vector3(228,0,128),
		Vector3(-90,0,245),Vector3(-248,0,-90),Vector3(-255,0,105)]:
		for i in range(20):
			var pos: Vector3 = center+Vector3(rng.randf_range(-25,25),0,rng.randf_range(-20,20))
			var height := rng.randf_range(3.0,11.0)
			_model("rock/medium_%d" % (1+i%3),pos,height)
			if absf(pos.x)<248 and absf(pos.z)<248:
				_block(pos,Vector3(height*.85,height, height*.85),"RockMass")
	# Distant low ridgelines break up the silhouette without changing playable Y=0.
	for i in range(17):
		var angle := TAU*float(i)/17
		var pos := Vector3(cos(angle)*rng.randf_range(455,485),0,sin(angle)*rng.randf_range(455,485))
		_hill(pos,rng.randf_range(65,95),rng.randf_range(16,28),i)

func _hill(pos: Vector3, radius: float, height: float, variant: int) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(12):
		for sector in range(48):
			var points: Array[Vector3]=[]
			for pair in [Vector2(ring,sector),Vector2(ring+1,sector),Vector2(ring,sector+1),Vector2(ring+1,sector+1)]:
				var r:float=pair.x/12.0
				var a:float=pair.y/48.0*TAU
				var outline:=1.0+sin(a*3+variant)*.12+cos(a*5)*.08
				points.append(Vector3(cos(a)*r*radius*outline,pow(1.0-r*r,2)*height,sin(a)*r*radius*.8*outline))
			_triangle(st,points[0],points[1],points[2])
			_triangle(st,points[2],points[1],points[3])
	st.generate_normals()
	_mesh("DistantRidge",st.commit(),terrain_material,pos)

func _river_block(a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
	# Its 3m top intersects the existing placement query (0..4m); the matching
	# NavigationObstacle3D outlines carve the river from the canonical bake.
	var aa:=Vector3(a.x,3,a.z)
	var bb:=Vector3(b.x,3,b.z)
	var cc:=Vector3(c.x,3,c.z)
	var dd:=Vector3(d.x,3,d.z)
	_triangle(river_collision,aa,cc,bb)
	_triangle(river_collision,bb,cc,dd)
	for edge in [[aa,cc],[dd,bb]]:
		var p:Vector3=edge[0]
		var q:Vector3=edge[1]
		_triangle(river_collision,p,q,Vector3(p.x,-1,p.z))
		_triangle(river_collision,q,Vector3(q.x,-1,q.z),Vector3(p.x,-1,p.z))
	if is_ford(a.z-2.5) or a.z<=-245:
		_triangle(river_collision,bb,aa,Vector3(aa.x,-1,aa.z))
		_triangle(river_collision,bb,Vector3(aa.x,-1,aa.z),Vector3(bb.x,-1,bb.z))
	if is_ford(c.z+2.5) or c.z>=250:
		_triangle(river_collision,cc,dd,Vector3(cc.x,-1,cc.z))
		_triangle(river_collision,dd,Vector3(dd.x,-1,dd.z),Vector3(cc.x,-1,cc.z))

func _corruption() -> void:
	for i in range(80):
		var pos := Vector3(rng.randf_range(-240,-105),0,rng.randf_range(-135,135))
		if pos.distance_to(Vector3(-175,0,0))<42: continue
		_model("tree/dead_%d" % (1+i%2),pos,rng.randf_range(5,10))
		if i%3==0: _model("rock/medium_2",pos+Vector3(3,0,2),rng.randf_range(2,5))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(.22,.015,.38)
	mat.emission_enabled = true
	mat.emission = Color(.28,.012,.52)
	mat.emission_energy_multiplier = 1.7
	for i in range(34):
		var pos := Vector3(rng.randf_range(-238,-115),.09,rng.randf_range(-105,105))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(6):
			var next := pos+Vector3(rng.randf_range(2,5),0,rng.randf_range(-3,3))
			_triangle(st,pos,pos+Vector3(0,0,.45),next)
			pos=next
		st.generate_normals()
		_mesh("AbyssFissure",st.commit(),mat)
	# Smoky low ribbons spread out toward the source, leaving the clearing clean.
	var smoke_shader := Shader.new()
	smoke_shader.code = """
	shader_type spatial;
	render_mode unshaded,cull_disabled,depth_draw_never;
	void fragment(){vec2 p=UV*2.0-1.0;float a=1.0-smoothstep(.15,1.0,length(p));
	a*=.55+.25*sin(p.x*11.0+sin(p.y*7.0+TIME*.4));
	ALBEDO=vec3(.025,.009,.035);ALPHA=a*.40;}
	"""
	var smoke := ShaderMaterial.new()
	smoke.shader=smoke_shader
	for i in range(16):
		var quad := QuadMesh.new()
		quad.size=Vector2(rng.randf_range(20,42),rng.randf_range(8,15))
		var m := _mesh("CorruptionMist",quad,smoke,Vector3(rng.randf_range(-220,-130),3,rng.randf_range(-110,95)))
		m.rotation_degrees.x=-35

func _model(key: String, pos: Vector3, height: float) -> Node3D:
	if not models.has(key):
		models[key]=VisualAssetCatalog3D.load_model(key)
		if models[key]==null: return null
		var probe: Node3D=models[key].instantiate()
		bounds[key]=_bounds(probe,Transform3D.IDENTITY)
		probe.free()
	var node: Node3D=models[key].instantiate()
	var box: AABB=bounds[key]
	var factor := height/maxf(box.size.y,.1)
	node.scale=Vector3.ONE*factor
	node.rotation.y=rng.randf()*TAU
	node.position=pos-Vector3(0,box.position.y*factor,0)
	add_child(node)
	return node

func _bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var t := parent_transform
	if node is Node3D: t=t*node.transform
	var result := AABB()
	if node is MeshInstance3D: result=t*node.get_aabb()
	for child in node.get_children():
		var box := _bounds(child,t)
		if box.size!=Vector3.ZERO: result=box if result.size==Vector3.ZERO else result.merge(box)
	return result

func _block(pos: Vector3, size: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name=label
	body.collision_layer=CollisionLayers3D.RESOURCE
	body.collision_mask=0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=size
	shape.shape=box
	shape.position.y=size.y*.5
	body.add_child(shape)
	body.position=pos
	add_child(body)

func _patch(pos: Vector3, radius: Vector2, color: Color, label: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(40):
		var a:=TAU*i/40.0
		var b:=TAU*(i+1)/40.0
		_triangle(st,Vector3.ZERO,Vector3(cos(b)*radius.x,0,sin(b)*radius.y),Vector3(cos(a)*radius.x,0,sin(a)*radius.y))
	st.generate_normals()
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	_mesh(label,st.commit(),mat,pos)

func _mesh(label: String, mesh: Mesh, mat: Material, pos:=Vector3.ZERO) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.name=label
	node.mesh=mesh
	node.material_override=mat
	node.position=pos
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,ua:=Vector2.ZERO,ub:=Vector2.ZERO,uc:=Vector2.ZERO) -> void:
	st.set_uv(ua);st.add_vertex(a)
	st.set_uv(uc);st.add_vertex(c)
	st.set_uv(ub);st.add_vertex(b)
