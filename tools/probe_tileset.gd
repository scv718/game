extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock1.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock2.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock3.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Rocks/Rock4.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe1.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe2.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe3.png",
		"res://assets/tiny_swords/Tiny Swords (Free Pack)/Terrain/Decorations/Bushes/Bushe4.png",
	]
	for p in paths:
		var img := (load(p) as Texture2D).get_image()
		print(p.rsplit("/", true, 1)[-1] + " used=" + str(img.get_used_rect()))
	quit()