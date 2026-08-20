extends SceneTree

## TASK-008-2 장식용 스프라이트 크롭 생성기.
## Tiny Swords 장식 PNG에서 실제 사용 영역만 잘라 generated/ 로 저장한다.
## 실행: Godot --headless --path . --script res://tools/crop_decorations.gd

const OUTFILE_ROCK := "res://assets/tiny_swords/generated/deco_rock1.png"
const OUTFILE_BUSH := "res://assets/tiny_swords/generated/deco_bush1.png"

const ROCK_PATH := "res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock1.png"
const BUSH_PATH := "res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe1.png"

func _initialize() -> void:
	_crop(ROCK_PATH, Rect2(15, 25, 32, 26), OUTFILE_ROCK)
	# Bushe1 의 첫 번째 부시 (x-region 33..94, 세로 33..79)
	_crop(BUSH_PATH, Rect2(33, 33, 62, 46), OUTFILE_BUSH)
	quit()


func _crop(src_path: String, region: Rect2, out_path: String) -> void:
	var src := (load(src_path) as Texture2D).get_image()
	var dst := Image.create(int(region.size.x), int(region.size.y), false, Image.FORMAT_RGBA8)
	dst.blit_rect(src, Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)), Vector2i.ZERO)
	var err := dst.save_png(out_path)
	if err != OK:
		push_error("save failed: %d for %s" % [err, out_path])
		quit(1)
		return
	print("WROTE " + out_path + " size=" + str(dst.get_width()) + "x" + str(dst.get_height()))