extends SceneTree
## Front/back legibility check: hero from both sides, a monster head-on, and
## one building with the new relief.
var frames := 0
var camera: Camera3D
var world: Node3D

func _initialize() -> void:
	root.content_scale_size = Vector2i(720, 720)
	root.size = Vector2i(720, 720)
	world = Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.5
	we.environment = env
	world.add_child(we)
	for spec in [
		[Vector3(-32, 35, 0), Color(1.0, 0.92, 0.85), 3.0, true],
		[Vector3(-12, 210, 0), Color(0.8, 0.85, 1.0), 1.2, false],
	]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.shadow_enabled = spec[3]
		world.add_child(l)

	var hero := DigiHariMan.create_node({"quality": 1.0})
	world.add_child(hero)
	var anim := HumanoidAnimator.new(hero.get_child(0) as Skeleton3D)
	anim.ground_raycast = false
	anim.grounded = true
	hero.add_child(anim)
	set_meta("anim", anim)

	var beast := Monster.create_node(Monster.Kind.STALKER, {"quality": 1.0})
	beast.position = Vector3(30, 0, 0)
	world.add_child(beast)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var bld := Building.create_node(rng, Building.Style.PODIUM_TOWER, Vector2(16, 15), 12)
	bld.position = Vector3(-80, 0, 0)
	world.add_child(bld)

	camera = Camera3D.new()
	camera.fov = 32.0
	camera.current = true
	world.add_child(camera)

func _aim(pos: Vector3, target: Vector3) -> void:
	camera.transform = Transform3D.IDENTITY.looking_at(target - pos).translated(pos)

func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png("user://fb_%s.png" % tag)
	print("shot %s" % tag)

func _process(_d: float) -> bool:
	frames += 1
	var anim: HumanoidAnimator = get_meta("anim")
	if anim != null:
		anim.update(1.0 / 60.0)
	if frames == 6:
		_aim(Vector3(30.0, 1.6, 5.2), Vector3(30, 1.2, 0))
	elif frames == 8:
		_shot("beast_front")
		_aim(Vector3(-45.0, 16.0, 52.0), Vector3(-80, 16, 0))
	elif frames == 10:
		_shot("building")
		_aim(Vector3(-0.9, 1.5, -3.4), Vector3(0, 1.05, 0))
	elif frames == 12:
		_shot("hero_back")
		return true
	return false
