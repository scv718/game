extends Node3D

@export var capture_path := ""
var _captured := false

const LOAFBRR := "res://assets/LoafbrrAssets/CastleWallKit/gltf/CastleWallsKit.gltf"
const TOWERS := "res://assets/third_party/hakanbacon/towers-n-castles-basics/TowerPackDemo.glb"
const RAW_NAMES := [
	"Courtine_Wall", "Courtine_Door_Arch", "Courtine_Corner_Round",
	"Courtine_Corner_Bevel", "Wall_Slits", "Wall_Door_Arch",
	"Wall_Corner_Square", "Wall_Battlements", "Pillar", "Stairs"
]
const TOWER_NAMES := ["WallCornerTower", "TowerGateTunnel", "WallCornerBalcony", "TowerRoundBase", "WallStairsDoor"]

func _ready() -> void:
	_setup_world()
	var raw := (load(LOAFBRR) as PackedScene).instantiate()
	var tower_pack := (load(TOWERS) as PackedScene).instantiate()
	add_child(raw)
	add_child(tower_pack)
	for child in raw.get_children():
		if child.name in RAW_NAMES:
			var copy := (child as Node3D).duplicate()
			copy.position = Vector3.ZERO
			copy.rotation = Vector3.ZERO
			_spawn_card(copy, Vector3(-18.0 + (RAW_NAMES.find(child.name) % 5) * 9.0, 0.0, -8.0 + int(RAW_NAMES.find(child.name) / 5) * 10.0), "Loafbrr raw: " + child.name)
	for child in tower_pack.get_children():
		if child.name in TOWER_NAMES:
			var copy := (child as Node3D).duplicate()
			copy.position = Vector3.ZERO
			copy.rotation = Vector3.ZERO
			_spawn_card(copy, Vector3(-18.0 + TOWER_NAMES.find(child.name) * 9.0, 0.0, 18.0), "Towers-n-Castles: " + child.name)
	raw.visible = false
	tower_pack.visible = false

func _process(_delta: float) -> void:
	if capture_path == "" or _captured or Engine.get_process_frames() < 10:
		return
	_captured = true
	get_viewport().get_texture().get_image().save_png(capture_path)
	get_tree().quit()

func _spawn_card(model: Node3D, at: Vector3, caption: String) -> void:
	var card := Node3D.new()
	card.name = caption.replace(" ", "_")
	card.position = at
	add_child(card)
	card.add_child(model)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = Color("#f7e7b0")
	label.outline_size = 12
	label.outline_modulate = Color("#171b1f")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 12, 0)
	card.add_child(label)

func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#202732")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b9c7d7")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 50)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#66705e")
	plane.material = mat
	ground.mesh = plane
	ground.position.y = -0.03
	add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 58.0
	camera.position = Vector3(0, 58, 58)
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 2, 4), Vector3.UP)
	camera.current = true
