extends SceneTree

var _failed := false

func _initialize() -> void:
	var scene := load("res://scenes/cuteskull_asset_zoo_3d.tscn") as PackedScene
	if scene == null:
		_failed = true
		print("FAIL: CuteskullAssetZoo3D scene loads")
	else:
		var instance := scene.instantiate()
		root.add_child(instance)
		await process_frame
		print("PASS: CuteskullAssetZoo3D scene loads and instantiates")
		for page in range(1, 5):
			instance.set_page(page)
			if instance.candidate_count() == 0:
				_failed = true
				print("FAIL: zoo page %d has no resolved imported nodes" % page)
			else:
				print("PASS: zoo page %d builds %d imported city16.fbx candidates" %
					[page, instance.candidate_count()])
		instance.free()
	print("CUTESKULL_ASSET_ZOO_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
