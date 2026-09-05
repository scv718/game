extends SceneTree

const RENDERER_SCRIPT := preload("res://scripts/building_thumbnail_renderer.gd")
const CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const ASSETS := [
	"House_1_1", "House_1_2", "House_2_1", "House_2_2", "House_2_3",
	"House_3_1", "House_3_2", "House_4_1", "House_4_2",
	"House_5_1", "House_5_2", "House_5_3", "House_6_1", "House_6_2",
	"House_7_1", "House_7_2", "House_7_3", "Church_1", "Church_2",
	"Castle_Wall", "Castle_Entrance", "Castle_Entrance__2",
	"Castle_Tower_1", "Castle_Tower_2", "Castle_Tower_3",
	"Castle_Tower_4", "Castle_Tower_5", "Castle_Tower_6",
	"Castle_Wall_Door", "Castle_Tower_Door",
]
var _failures := 0


func _init() -> void:
	var renderer := RENDERER_SCRIPT.new()
	renderer.configure(CITY)
	get_root().add_child(renderer)
	for asset_name in ASSETS:
		var texture: Texture2D = renderer.get_thumbnail(asset_name)
		_check(texture != null, "%s thumbnail generated" % asset_name)
		if texture != null:
			_check(texture.get_width() == 256 and texture.get_height() == 256,
				"%s thumbnail is 256x256" % asset_name)
	for _i in 2:
		await process_frame
	_check(renderer.cached_thumbnail_count() == ASSETS.size(),
		"all registered assets are cached")
	renderer.free()
	print("BUILDING_THUMBNAIL_RESULT=%s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)
