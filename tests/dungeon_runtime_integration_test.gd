extends SceneTree

const MAIN_SCENE := "res://scenes/main_3d.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	if not InputMap.has_action("dungeon_prep"):
		failures.append("dungeon_prep InputMap action is missing")
	else:
		var events := InputMap.action_get_events("dungeon_prep")
		if events.size() != 1:
			failures.append("dungeon_prep must have exactly one binding")
		else:
			var key := events[0] as InputEventKey
			if key == null or key.physical_keycode != KEY_P or key.unicode != 112:
				failures.append("dungeon_prep binding is not physical P / unicode 112")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		failures.append("main_3d scene failed to load")
	else:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		var prep_ui := main.get_node_or_null("DungeonPreparationUI/Control")
		if prep_ui == null:
			failures.append("DungeonPreparationUI/Control is not instantiated")
		else:
			var press := InputEventKey.new()
			press.physical_keycode = KEY_P
			press.unicode = 112
			press.pressed = true
			Input.parse_input_event(press)
			await process_frame
			if not prep_ui.is_open():
				failures.append("P input did not open DungeonPreparationUI")
			var release := InputEventKey.new()
			release.physical_keycode = KEY_P
			release.unicode = 112
			release.pressed = false
			Input.parse_input_event(release)

		main.queue_free()

	if failures.is_empty():
		print("DUNGEON_RUNTIME_INTEGRATION_RESULT=PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("DUNGEON_RUNTIME_INTEGRATION_RESULT=FAIL")
		quit(1)
