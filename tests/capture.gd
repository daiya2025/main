extends SceneTree
## Loads the game and writes screenshots once the world has settled.
## Doubles as a "does this actually render" check: it runs under a software GL
## rasteriser, so no GPU is required.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --resolution 960x540 --script res://tests/capture.gd

const FIRST_SHOT := 120
const INTERVAL := 30
const COUNT := 3

var frames: int = 0
var shots: int = 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if frames % 20 == 0:
		print("frame %d" % frames)
	if frames < FIRST_SHOT or (frames - FIRST_SHOT) % INTERVAL != 0:
		return false
	var image := root.get_texture().get_image()
	var path := "user://capture_%d.png" % shots
	image.save_png(path)
	print("captured %s (%dx%d)" % [ProjectSettings.globalize_path(path), image.get_width(), image.get_height()])
	shots += 1
	return shots >= COUNT
