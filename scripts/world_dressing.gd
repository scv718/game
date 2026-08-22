extends Node2D
class_name WorldDressing

## Collision-free authored composition layer.  It adds regional ground treatment,
## landmark silhouettes and Tiny Swords prop sprites without changing navigation.

@export_range(2, 5) var composition_phase := 5

const BUSH_SHEETS := [
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe1.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe2.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe3.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe4.png",
]
const ROCK_SPRITES := [
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock1.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock2.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock3.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock4.png",
]
const STUMP_SHEETS := [
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Trees/Stump 1.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Trees/Stump 2.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Trees/Stump 3.png",
	"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Trees/Stump 4.png",
]
const WOOD_SPRITE := "res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Wood/Wood Resource/Wood Resource.png"
const HAMMER_SPRITE := "res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Tools/Tool_01.png"
const SICKLE_SPRITE := "res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Resources/Tools/Tool_02.png"

const INK := Color("243044")
const ROAD_EDGE := Color("8f6848")
const ROAD_HIGHLIGHT := Color("d5aa69")
const STONE_DARK := Color("697d78")
const STONE_LIGHT := Color("b7c5a5")
const WOOD_DARK := Color("593c2c")
const WOOD_LIGHT := Color("b67a43")
const BLUE := Color("2d66a3")
const GOLD := Color("e6bb52")
const PURPLE := Color("762b92")
const PURPLE_GLOW := Color("d35cf0")


func _ready() -> void:
	_build_sprite_props()
	queue_redraw()


func _draw() -> void:
	_draw_village_ground()
	if composition_phase >= 3:
		_draw_west_region()
	if composition_phase >= 4:
		_draw_north_region()
		_draw_east_region()
		_draw_south_region()
	if composition_phase >= 5:
		_draw_resource_regions()
	_draw_village_props()
	if composition_phase >= 3:
		_draw_west_props()
	if composition_phase >= 4:
		_draw_north_props()
		_draw_east_props()
		_draw_south_props()


func _draw_village_ground() -> void:
	# Small, readable footpaths.  The TileMap supplies the dirt texture; these edge
	# strokes make junctions and the central square feel deliberately authored.
	var paths := [
		PackedVector2Array([Vector2(0, -220), Vector2(0, -62)]),
		PackedVector2Array([Vector2(0, 82), Vector2(0, 220)]),
		PackedVector2Array([Vector2(-220, 0), Vector2(-72, 12)]),
		PackedVector2Array([Vector2(72, 12), Vector2(220, 0)]),
		PackedVector2Array([Vector2(-104, -44), Vector2(-54, -8)]),
		PackedVector2Array([Vector2(104, -44), Vector2(54, -8)]),
		PackedVector2Array([Vector2(-102, 108), Vector2(-50, 52)]),
		PackedVector2Array([Vector2(102, 108), Vector2(50, 52)]),
	]
	for path in paths:
		draw_polyline(path, ROAD_EDGE, 34.0, false)
		draw_polyline(path, Color("c69b62"), 27.0, false)
	var plaza := PackedVector2Array([
		Vector2(-72, -15), Vector2(-48, -45), Vector2(0, -54), Vector2(52, -43),
		Vector2(76, -8), Vector2(70, 48), Vector2(42, 75), Vector2(-46, 74),
		Vector2(-74, 45),
	])
	draw_colored_polygon(plaza, Color("a9916e"))
	draw_polyline(PackedVector2Array(Array(plaza) + [plaza[0]]), STONE_DARK, 5.0, false)
	# Cobble marks break up the flat plaza without becoming visual noise.
	for y in range(-34, 61, 16):
		for x in range(-52, 57, 18):
			var shift := 8 if int((y + 34) / 16) % 2 != 0 else 0
			var p := Vector2(x + shift, y)
			if (p - Vector2(0, 10)).length() < 60.0:
				draw_line(p, p + Vector2(9, 1), Color("c5b58e"), 2.0)
	# Low garden edging loosely frames the village but leaves every road open.
	_draw_fence(Vector2(-184, -118), Vector2(-108, -118), 3)
	_draw_fence(Vector2(108, -118), Vector2(184, -118), 3)
	_draw_fence(Vector2(-174, 174), Vector2(-72, 174), 4)
	_draw_fence(Vector2(72, 174), Vector2(174, 174), 4)


func _draw_village_props() -> void:
	# Keep banners / sentry stones.
	_draw_banner(Vector2(-45, -176), BLUE)
	_draw_banner(Vector2(45, -176), BLUE)
	_draw_stone_post(Vector2(-58, -128))
	_draw_stone_post(Vector2(58, -128))
	# Tavern: sign, barrels, outdoor bench.
	_draw_sign(Vector2(-104, -68), Vector2(1, 0))
	_draw_barrel(Vector2(-151, -26))
	_draw_barrel(Vector2(-139, -23))
	_draw_bench(Vector2(-118, 6), 34.0)
	# Inn: quiet fenced garden and flowers.
	_draw_bench(Vector2(115, 2), 30.0)
	_draw_flowers(Vector2(152, -12), Color("f2d978"))
	_draw_flowers(Vector2(166, -2), Color("e9798e"))
	# Grocery: supply crates and sacks.
	_draw_crate(Vector2(-146, 132), 13.0)
	_draw_crate(Vector2(-132, 137), 10.0)
	_draw_sack(Vector2(-158, 145))
	# Equipment shop: rack silhouette and target.
	_draw_rack(Vector2(151, 126))
	_draw_target(Vector2(170, 146))
	# Fountain-like center landmark gives the plaza a focal point.
	draw_circle(Vector2(0, 10), 17.0, STONE_DARK)
	draw_circle(Vector2(0, 8), 13.0, Color("6e9ba0"))
	draw_circle(Vector2(0, 8), 8.0, Color("8fc3bd"))
	draw_rect(Rect2(-3, -9, 6, 22), STONE_LIGHT)


func _draw_west_region() -> void:
	var outer := PackedVector2Array([
		Vector2(-1120, -1120), Vector2(-680, -1120), Vector2(-720, -810),
		Vector2(-660, -580), Vector2(-760, -340), Vector2(-720, -140),
		Vector2(-800, 80), Vector2(-720, 350), Vector2(-780, 640),
		Vector2(-690, 880), Vector2(-720, 1120), Vector2(-1120, 1120),
	])
	draw_colored_polygon(outer, Color(0.20, 0.16, 0.20, 0.70))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-800, -840), Vector2(-680, -780), Vector2(-640, -530),
		Vector2(-720, -300), Vector2(-680, -100), Vector2(-740, 100),
		Vector2(-680, 380), Vector2(-730, 660), Vector2(-660, 880),
		Vector2(-770, 960),
	]), Color(0.30, 0.23, 0.22, 0.30))
	# Battlefield stays open and readable, with a scuffed lane rather than a tunnel.
	draw_rect(Rect2(-798, -138, 210, 276), Color(0.34, 0.27, 0.23, 0.72))
	for p in [Vector2(-760, -88), Vector2(-710, 88), Vector2(-664, -66), Vector2(-614, 92)]:
		draw_circle(p, 15.0, Color(0.23, 0.19, 0.19, 0.55))
	# Ruined, slightly crooked approach route from the portal.
	var approach := PackedVector2Array([
		Vector2(-1020, 158), Vector2(-940, 120), Vector2(-870, 132),
		Vector2(-800, 78), Vector2(-730, 54),
	])
	draw_polyline(approach, Color("49383a"), 58.0, false)
	draw_polyline(approach, Color("755548"), 38.0, false)
	# Portal focal point.
	draw_circle(Vector2(-1020, 158), 50.0, Color(0.08, 0.06, 0.12, 0.95))
	draw_arc(Vector2(-1020, 158), 54.0, 0.0, TAU, 32, Color(0.57, 0.15, 0.68, 0.58), 7.0, false)
	draw_arc(Vector2(-1020, 158), 46.0, 0.0, TAU, 32, PURPLE, 9.0, false)
	draw_arc(Vector2(-1020, 158), 32.0, 0.0, TAU, 24, PURPLE_GLOW, 5.0, false)
	draw_circle(Vector2(-1020, 158), 21.0, Color("20162c"))
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var p := Vector2(-1020, 158) + Vector2(cos(a), sin(a)) * 60.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 7), p + Vector2(0, -12), p + Vector2(6, 7)]), Color("3f3346"))


func _draw_west_props() -> void:
	# West gate suggestion and broken defenses.  These are visual-only and leave the
	# tested placement corridor unobstructed.
	_draw_ruined_wall(Vector2(-596, -86), Vector2(-596, -44), 3)
	_draw_ruined_wall(Vector2(-596, 26), Vector2(-596, 68), 3)
	_draw_banner(Vector2(-575, -96), Color("873b43"))
	_draw_broken_cart(Vector2(-846, -8))
	for p in [Vector2(-922, 58), Vector2(-886, 194), Vector2(-824, 176), Vector2(-770, -154)]:
		draw_line(p - Vector2(8, 7), p + Vector2(8, 7), INK, 3.0)
		draw_line(p + Vector2(7, -8), p - Vector2(7, 8), INK, 3.0)


func _draw_north_region() -> void:
	var mountain := PackedVector2Array([
		Vector2(-460, -1120), Vector2(440, -1120), Vector2(370, -940),
		Vector2(250, -820), Vector2(140, -790), Vector2(110, -600),
		Vector2(-110, -600), Vector2(-140, -790), Vector2(-270, -830),
	])
	draw_colored_polygon(mountain, Color(0.34, 0.39, 0.35, 0.46))
	# Smaller rift at the head of the narrow approach.
	draw_arc(Vector2(-160, -1000), 28.0, 0.0, TAU, 20, Color("60306f"), 7.0, false)
	draw_arc(Vector2(-160, -1000), 16.0, 0.0, TAU, 16, Color("bd65d5"), 3.0, false)
	# North battlefield is deliberately open in front of the gate.
	draw_rect(Rect2(-110, -780, 220, 176), Color(0.47, 0.43, 0.33, 0.34))


func _draw_north_props() -> void:
	_draw_stone_gate(Vector2(0, -596), false)
	# Ancient nonfunctional dungeon ruin in the NE.
	_draw_ruined_wall(Vector2(752, -802), Vector2(842, -802), 5)
	_draw_stone_post(Vector2(760, -766))
	_draw_stone_post(Vector2(838, -766))
	draw_arc(Vector2(800, -770), 30.0, PI, TAU, 14, Color("4e4552"), 8.0, false)


func _draw_east_region() -> void:
	# Clean roadside shoulders and evenly spaced cobbles establish the Royal Road.
	draw_line(Vector2(580, -34), Vector2(1120, -125), Color(0.77, 0.68, 0.48, 0.62), 5.0)
	draw_line(Vector2(580, 34), Vector2(1120, -50), Color(0.77, 0.68, 0.48, 0.62), 5.0)
	for i in range(620, 1100, 56):
		var t := float(i - 580) / 540.0
		var p := Vector2(i, lerpf(0.0, -88.0, t))
		draw_circle(p, 4.0, Color("d8c796"))
	# Horizon apron prevents the road from looking abruptly cut off.
	draw_colored_polygon(PackedVector2Array([
		Vector2(1040, -160), Vector2(1140, -175), Vector2(1140, 14), Vector2(1040, -26),
	]), Color(0.70, 0.64, 0.45, 0.30))


func _draw_east_props() -> void:
	_draw_stone_gate(Vector2(596, 0), true)
	for x in [696.0, 850.0, 1000.0]:
		_draw_banner(Vector2(x, -78.0 - (x - 696.0) * 0.16), BLUE)
	_draw_sign(Vector2(832, 38), Vector2(1, -0.18))
	_draw_sentry_box(Vector2(690, 66))


func _draw_south_region() -> void:
	# Future production belt: visible fields and herb rows, no gameplay building.
	draw_rect(Rect2(-360, 510, 250, 170), Color(0.50, 0.54, 0.27, 0.76))
	draw_rect(Rect2(-80, 534, 180, 140), Color(0.38, 0.53, 0.28, 0.70))
	draw_rect(Rect2(138, 504, 220, 180), Color(0.58, 0.48, 0.25, 0.58))
	for x in range(-340, -110, 22):
		draw_line(Vector2(x, 530), Vector2(x + 7, 660), Color("bd9650"), 4.0)
	for y in range(550, 664, 20):
		draw_line(Vector2(-62, y), Vector2(82, y), Color("76a34e"), 4.0)
	for x in range(156, 348, 24):
		draw_line(Vector2(x, 520), Vector2(x - 9, 670), Color("b58b46"), 3.0)


func _draw_south_props() -> void:
	_draw_fence(Vector2(-368, 494), Vector2(-100, 494), 10)
	_draw_fence(Vector2(130, 486), Vector2(366, 486), 9)
	_draw_fence(Vector2(-368, 690), Vector2(-104, 690), 10)
	_draw_fence(Vector2(130, 692), Vector2(366, 692), 9)
	_draw_sign(Vector2(108, 476), Vector2(0.7, 0.7))
	_draw_crate(Vector2(382, 600), 15.0)
	_draw_crate(Vector2(400, 605), 12.0)


func _draw_resource_regions() -> void:
	# Forest floors are tinted differently so the three wood regions read as places.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-670, -580), Vector2(-360, -580), Vector2(-310, -282),
		Vector2(-590, -260), Vector2(-680, -380),
	]), Color(0.18, 0.35, 0.23, 0.13))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-940, 360), Vector2(-460, 360), Vector2(-400, 780),
		Vector2(-900, 780), Vector2(-1040, 590),
	]), Color(0.10, 0.29, 0.20, 0.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(400, -670), Vector2(810, -640), Vector2(860, -380),
		Vector2(470, -350),
	]), Color(0.38, 0.48, 0.29, 0.10))
	# Stone zone uses dry ground chips and clustered scree.
	draw_colored_polygon(PackedVector2Array([
		Vector2(452, 178), Vector2(710, 172), Vector2(760, 414),
		Vector2(488, 450), Vector2(410, 310),
	]), Color(0.50, 0.45, 0.34, 0.38))
	for p in [Vector2(465, 234), Vector2(494, 415), Vector2(540, 200), Vector2(670, 220), Vector2(710, 322), Vector2(622, 430)]:
		draw_circle(p, 4.0, Color("75817b"))


func _build_sprite_props() -> void:
	# Core village actual Tiny Swords props.
	_add_bush(Vector2(-166, -94), 0, 0.34)
	_add_bush(Vector2(164, -96), 1, 0.34)
	_add_bush(Vector2(-176, 166), 2, 0.30)
	_add_bush(Vector2(178, 164), 3, 0.30)
	_add_sprite(WOOD_SPRITE, Vector2(-151, 126), 0.38)
	_add_sprite(HAMMER_SPRITE, Vector2(148, 111), 0.34)
	if composition_phase >= 3:
		for item in [
			[Vector2(-958, 88), 2, 0.55], [Vector2(-900, 222), 0, 0.45],
			[Vector2(-826, -132), 3, 0.52], [Vector2(-750, 156), 1, 0.42],
		]:
			_add_rock(item[0], item[1], item[2])
		for item in [[Vector2(-922, 250), 0], [Vector2(-796, 202), 2], [Vector2(-860, -176), 3]]:
			_add_stump(item[0], item[1], 0.34)
	if composition_phase >= 4:
		# North mountain walls leave a broad vertical combat/readability lane.
		for item in [
			[Vector2(-290, -910), 0, 0.72], [Vector2(-215, -840), 2, 0.62],
			[Vector2(-146, -800), 1, 0.56], [Vector2(140, -802), 3, 0.62],
			[Vector2(214, -860), 0, 0.70], [Vector2(292, -920), 2, 0.78],
			[Vector2(394, -1000), 1, 0.68], [Vector2(-398, -1000), 3, 0.68],
		]:
			_add_rock(item[0], item[1], item[2])
		for p in [Vector2(684, -120), Vector2(774, -148), Vector2(890, -182), Vector2(1010, -204)]:
			_add_bush(p, 0, 0.30)
		_add_sprite(SICKLE_SPRITE, Vector2(86, 590), 0.28)
	if composition_phase >= 5:
		for item in [
			[Vector2(-636, -382), 2, 0.32], [Vector2(-582, -292), 0, 0.30],
			[Vector2(-458, -462), 1, 0.27], [Vector2(-822, 418), 3, 0.36],
			[Vector2(-902, 580), 2, 0.38], [Vector2(-520, 674), 0, 0.34],
			[Vector2(480, -414), 1, 0.28], [Vector2(712, -592), 3, 0.30],
		]:
			_add_bush(item[0], item[1], item[2])
		for item in [
			[Vector2(482, 264), 1, 0.48], [Vector2(512, 398), 3, 0.52],
			[Vector2(654, 208), 0, 0.58], [Vector2(708, 378), 2, 0.50],
			[Vector2(620, 442), 1, 0.42],
		]:
			_add_rock(item[0], item[1], item[2])
		for item in [[Vector2(-614, -508), 1], [Vector2(-712, 620), 3], [Vector2(-480, 614), 0]]:
			_add_stump(item[0], item[1], 0.30)


func _add_bush(pos: Vector2, variant: int, size: float) -> void:
	_add_sprite(BUSH_SHEETS[variant % BUSH_SHEETS.size()], pos, size, Rect2(33, 33, 62, 46))


func _add_rock(pos: Vector2, variant: int, size: float) -> void:
	_add_sprite(ROCK_SPRITES[variant % ROCK_SPRITES.size()], pos, size)


func _add_stump(pos: Vector2, variant: int, size: float) -> void:
	_add_sprite(STUMP_SHEETS[variant % STUMP_SHEETS.size()], pos, size, Rect2(75, 200, 48, 40))


func _add_sprite(path: String, pos: Vector2, size: float, region: Rect2 = Rect2()) -> void:
	var sprite := Sprite2D.new()
	sprite.position = pos
	sprite.scale = Vector2(size, size)
	if region.size != Vector2.ZERO:
		var atlas := AtlasTexture.new()
		atlas.atlas = load(path)
		atlas.region = region
		sprite.texture = atlas
	else:
		sprite.texture = load(path)
	add_child(sprite)


func _draw_fence(a: Vector2, b: Vector2, sections: int) -> void:
	draw_line(a, b, WOOD_DARK, 5.0, false)
	draw_line(a + Vector2(0, -5), b + Vector2(0, -5), WOOD_LIGHT, 3.0, false)
	for i in sections + 1:
		var p := a.lerp(b, float(i) / float(sections))
		draw_line(p + Vector2(0, -10), p + Vector2(0, 7), WOOD_DARK, 5.0, false)
		draw_line(p + Vector2(-1, -9), p + Vector2(-1, 5), WOOD_LIGHT, 2.0, false)


func _draw_banner(pos: Vector2, color: Color) -> void:
	draw_line(pos, pos + Vector2(0, 38), INK, 4.0, false)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(3, 3), pos + Vector2(20, 7), pos + Vector2(17, 23),
		pos + Vector2(10, 19), pos + Vector2(3, 22),
	]), color)
	draw_line(pos + Vector2(5, 8), pos + Vector2(17, 10), GOLD, 2.0, false)


func _draw_sign(pos: Vector2, direction: Vector2) -> void:
	var d := direction.normalized()
	var side := Vector2(-d.y, d.x)
	draw_line(pos, pos + Vector2(0, 27), WOOD_DARK, 4.0, false)
	var c := pos + Vector2(0, 5) + d * 8.0
	var points := PackedVector2Array([c - d * 17.0 - side * 7.0, c + d * 18.0 - side * 7.0, c + d * 24.0, c + d * 18.0 + side * 7.0, c - d * 17.0 + side * 7.0])
	draw_colored_polygon(points, WOOD_LIGHT)
	draw_polyline(PackedVector2Array(Array(points) + [points[0]]), WOOD_DARK, 2.0, false)


func _draw_barrel(pos: Vector2) -> void:
	draw_circle(pos, 7.0, WOOD_DARK)
	draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), WOOD_LIGHT)
	draw_line(pos + Vector2(-6, -3), pos + Vector2(6, -3), INK, 2.0)
	draw_line(pos + Vector2(-6, 4), pos + Vector2(6, 4), INK, 2.0)


func _draw_bench(pos: Vector2, width: float) -> void:
	draw_rect(Rect2(pos - Vector2(width * 0.5, 4), Vector2(width, 7)), WOOD_LIGHT)
	draw_line(pos + Vector2(-width * 0.38, 2), pos + Vector2(-width * 0.38, 10), WOOD_DARK, 3.0)
	draw_line(pos + Vector2(width * 0.38, 2), pos + Vector2(width * 0.38, 10), WOOD_DARK, 3.0)


func _draw_crate(pos: Vector2, size: float) -> void:
	draw_rect(Rect2(pos - Vector2(size * 0.5, size), Vector2(size, size)), WOOD_LIGHT)
	draw_rect(Rect2(pos - Vector2(size * 0.5, size), Vector2(size, size)), WOOD_DARK, false, 2.0)
	draw_line(pos - Vector2(size * 0.4, size * 0.9), pos + Vector2(size * 0.4, -size * 0.1), WOOD_DARK, 2.0)
	draw_line(pos + Vector2(size * 0.4, -size * 0.9), pos - Vector2(size * 0.4, size * 0.1), WOOD_DARK, 2.0)


func _draw_sack(pos: Vector2) -> void:
	draw_circle(pos, 6.0, Color("c6a164"))
	draw_line(pos + Vector2(-3, -7), pos + Vector2(3, -7), WOOD_DARK, 2.0)


func _draw_flowers(pos: Vector2, color: Color) -> void:
	for p in [pos, pos + Vector2(7, 3), pos + Vector2(-5, 5)]:
		draw_line(p, p + Vector2(0, 7), Color("3d7243"), 2.0)
		draw_circle(p, 2.5, color)


func _draw_rack(pos: Vector2) -> void:
	draw_line(pos + Vector2(-12, 10), pos + Vector2(-8, -14), WOOD_DARK, 4.0)
	draw_line(pos + Vector2(12, 10), pos + Vector2(8, -14), WOOD_DARK, 4.0)
	draw_line(pos + Vector2(-10, -7), pos + Vector2(10, -7), WOOD_LIGHT, 4.0)
	for x in [-6.0, 0.0, 6.0]:
		draw_line(pos + Vector2(x, -10), pos + Vector2(x + 2, 6), STONE_LIGHT, 2.0)


func _draw_target(pos: Vector2) -> void:
	draw_line(pos, pos + Vector2(0, 12), WOOD_DARK, 3.0)
	draw_circle(pos + Vector2(0, -5), 8.0, Color("e8dfb1"))
	draw_circle(pos + Vector2(0, -5), 5.0, Color("a63e46"), false, 2.0)
	draw_circle(pos + Vector2(0, -5), 1.5, Color("a63e46"))


func _draw_stone_post(pos: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-7, 10), pos + Vector2(-5, -10), pos + Vector2(4, -14), pos + Vector2(8, 10)]), STONE_DARK)
	draw_line(pos + Vector2(-3, -8), pos + Vector2(3, -10), STONE_LIGHT, 2.0)


func _draw_stone_gate(pos: Vector2, civilized: bool) -> void:
	var c := Color("788d86") if civilized else Color("5c6765")
	for side in [-1.0, 1.0]:
		var p := pos + Vector2(0, side * 47.0) if abs(pos.x) > abs(pos.y) else pos + Vector2(side * 47.0, 0)
		draw_circle(p, 14.0, INK)
		draw_circle(p, 10.0, c)
	if civilized:
		_draw_banner(pos + Vector2(-8, -66), BLUE)


func _draw_ruined_wall(a: Vector2, b: Vector2, stones: int) -> void:
	for i in stones:
		var p := a.lerp(b, float(i) / maxf(float(stones - 1), 1.0))
		draw_rect(Rect2(p - Vector2(7, 5), Vector2(14, 10)), Color("56605e"))
		draw_line(p + Vector2(-5, -3), p + Vector2(4, -3), STONE_LIGHT, 2.0)


func _draw_broken_cart(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(18, 10), Vector2(32, 18)), WOOD_DARK)
	draw_line(pos + Vector2(10, -4), pos + Vector2(36, -18), WOOD_LIGHT, 4.0)
	draw_circle(pos + Vector2(-12, 11), 8.0, INK, false, 3.0)
	draw_circle(pos + Vector2(9, 11), 8.0, INK, false, 3.0)


func _draw_sentry_box(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(13, 20), Vector2(26, 27)), WOOD_DARK)
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-17, -20), pos + Vector2(0, -34), pos + Vector2(17, -20)]), BLUE)
	draw_rect(Rect2(pos - Vector2(6, 12), Vector2(12, 19)), Color("d2ad69"))
