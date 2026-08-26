extends SceneTree
## Combat capture: drives the real player through simulated input against a
## spawned Stalker, screenshotting the key beats (run, slash, dash).
var frames := 0
var spawned := false

func _initialize() -> void:
	root.content_scale_size = Vector2i(640, 360)
	root.size = Vector2i(640, 360)
	change_scene_to_file("res://scenes/Main.tscn")

func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png("user://c_%s.png" % tag)
	print("shot %s" % tag)

func _process(_d: float) -> bool:
	frames += 1
	var player := get_first_node_in_group("player") as Player
	if player == null:
		return false
	if not spawned:
		spawned = true
		# One enemy right in front of the hero so the fight starts immediately.
		var agent := MonsterAgent.new()
		agent.setup(Monster.Kind.STALKER)
		agent.target = player
		player.get_parent().add_child(agent)
		agent.global_position = player.global_position + Vector3(0, 0.5, -6.0)
		set_meta("t0", frames)
	var t: int = frames - int(get_meta("t0", 0))
	if t == 2:
		Input.action_press("move_forward")
	elif t == 10:
		_shot("run")
		Input.action_release("move_forward")
		Input.action_press("attack")
	elif t == 12:
		Input.action_release("attack")
	elif t == 17:
		_shot("slash")
		Input.action_press("dash")
	elif t == 19:
		Input.action_release("dash")
	elif t == 24:
		_shot("dash")
		return true
	return false
