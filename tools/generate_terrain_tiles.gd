extends SceneTree

## TASK-008-2 지형 타일 생성기.
## grass_tile.png 를 기반으로 동일 픽셀 패턴 + 먼지/흙 색상의 path_tile.png 를 생성한다.
## (Tiny Swords 픽셀 아트 스타일(플랫 컬러 패턴)을 유지하면서 도로/길을 식별 가능하게 만든다.)
## 실행: Godot --headless --path . --script res://tools/generate_terrain_tiles.gd

const GRASS_PATH := "res://assets/tiny_swords/generated/grass_tile.png"
const OUT_PATH := "res://assets/tiny_swords/generated/path_tile.png"

# grass_tile.png 의 3색 팔레트 → dirt 팔레트 매핑 (R,G,B)
const GRASS_TO_DIRT := {
	Vector3i(128, 172, 94): Vector3i(148, 108, 68),
	Vector3i(155, 185, 78): Vector3i(180, 136, 80),
	Vector3i(184, 185, 88): Vector3i(200, 152, 92),
}


func _initialize() -> void:
	var src := (load(GRASS_PATH) as Texture2D).get_image()
	var dst := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			var key := Vector3i(
				int(round(c.r * 255.0)),
				int(round(c.g * 255.0)),
				int(round(c.b * 255.0)))
			var dirt: Vector3i = GRASS_TO_DIRT.get(key, Vector3i(int(c.r * 255), int(c.g * 255), int(c.b * 255)))
			dst.set_pixel(x, y, Color(dirt.x / 255.0, dirt.y / 255.0, dirt.z / 255.0, c.a))
	var err := dst.save_png(OUT_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("WROTE " + OUT_PATH + " size=" + str(dst.get_width()) + "x" + str(dst.get_height()))
	quit()