extends SceneTree
## Loads the game, lets it build and settle, then writes screenshots.
## Used for visual verification under a software renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tests/capture.gd

var frames: int = 0
var shots: int = 0
const WARMUP := 260
const INTERVAL := 45
const COUNT := 3

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if frames < WARMUP:
		return false
	if (frames - WARMUP) % INTERVAL == 0:
		var image := root.get_texture().get_image()
		var path := "user://capture_%d.png" % shots
		image.save_png(path)
		print("captured %s (%dx%d) at frame %d" % [ProjectSettings.globalize_path(path), image.get_width(), image.get_height(), frames])
		shots += 1
		if shots >= COUNT:
			return true
	return false
