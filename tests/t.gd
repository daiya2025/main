extends SceneTree
## Samples the demo reel inside the real game world for visual verification.
var frames := 0
var started := false
var shot_index := 0
const SAMPLES := [5.0, 36.0, 57.0]

func _initialize() -> void:
	root.content_scale_size = Vector2i(640, 360)
	root.size = Vector2i(640, 360)
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_d: float) -> bool:
	frames += 1
	var main := root.get_node_or_null("Main")
	if main == null or main.get("demo") == null:
		return false
	var demo: Node = main.get("demo")
	if not started:
		if root.get_tree().get_first_node_in_group("player") == null:
			return false
		started = true
		demo.call("start", true)
		set_meta("settle", 0)
		demo.call("seek", SAMPLES[0])
		return false
	var settle := int(get_meta("settle", 0)) + 1
	set_meta("settle", settle)
	if settle % 3 != 0:
		demo.call("seek", SAMPLES[shot_index])
		return false
	var tag := "e%02d" % int(SAMPLES[shot_index])
	root.get_texture().get_image().save_png("user://demo_%s.png" % tag)
	print("shot %s (%s)" % [tag, demo.call("shot_name_at", SAMPLES[shot_index])])
	shot_index += 1
	if shot_index >= SAMPLES.size():
		return true
	demo.call("seek", SAMPLES[shot_index])
	return false
