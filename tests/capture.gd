extends SceneTree
## Loads the game, lets it settle, then writes screenshots and a short report on
## what is actually in the frame. Runs under a software GL rasteriser, so it
## doubles as a "does this render at all" check without a GPU.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script res://tests/capture.gd

const VIEWPORT := Vector2i(800, 450)
const FIRST_SHOT := 26
const INTERVAL := 10
const COUNT := 2

var frames: int = 0
var shots: int = 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")
	# A software rasteriser cannot afford the project's native 1440p.
	root.content_scale_size = VIEWPORT
	root.size = VIEWPORT

func _process(_delta: float) -> bool:
	frames += 1
	if frames % 4 == 0:
		print("frame %d" % frames)
	if frames < FIRST_SHOT or (frames - FIRST_SHOT) % INTERVAL != 0:
		return false
	_report()
	var image := root.get_texture().get_image()
	var path := "user://capture_%d.png" % shots
	image.save_png(path)
	print("captured %s (%dx%d)" % [ProjectSettings.globalize_path(path), image.get_width(), image.get_height()])
	shots += 1
	return shots >= COUNT

## Prints what should be on screen, so an ambiguous image can still be judged.
func _report() -> void:
	var camera := root.get_camera_3d()
	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	if camera == null or player == null:
		print("  report: camera=%s player=%s" % [camera, player])
		return
	var to_player: Vector3 = player.global_position - camera.global_position
	var forward := -camera.global_transform.basis.z
	print("  camera %s  player %s  distance %.2f  in front: %s" % [
		camera.global_position.snapped(Vector3.ONE * 0.01),
		player.global_position.snapped(Vector3.ONE * 0.01),
		to_player.length(), forward.dot(to_player.normalized()) > 0.0])
	for skeleton in player.find_children("*", "Skeleton3D", true, false):
		for mi: MeshInstance3D in (skeleton as Node).find_children("*", "MeshInstance3D", false, false):
			var screen := camera.unproject_position(mi.get_global_transform() * mi.get_aabb().get_center())
			print("    %-6s visible=%s screen=%s" % [mi.name, mi.is_visible_in_tree(), screen.snapped(Vector2.ONE)])
	print("  enemies alive: %d" % root.get_tree().get_nodes_in_group("enemy").size())
