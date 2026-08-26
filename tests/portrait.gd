extends SceneTree
## Renders DIGIHARIMAN alone under a three-point rig and writes a portrait.
## Much cheaper than capturing the district, so it is the quick way to check
## the character's silhouette, materials and pose.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script res://tests/portrait.gd

const SIZE := Vector2i(720, 720)
const WARMUP := 8

var frames: int = 0
var animator: HumanoidAnimator

func _initialize() -> void:
	root.content_scale_size = SIZE
	root.size = SIZE

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.42, 0.55)
	e.ambient_light_energy = 1.4
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_intensity = 0.5
	env.environment = e
	world.add_child(env)

	# key / fill / rim
	for spec in [
		[Vector3(-35, 35, 0), Color(1.0, 0.92, 0.82), 3.6, true],
		[Vector3(-15, -60, 0), Color(0.55, 0.68, 0.92), 1.1, false],
		[Vector3(-10, 190, 0), Color(1.0, 0.55, 0.25), 2.6, false],
	]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		light.shadow_enabled = spec[3]
		world.add_child(light)

	var hero := DigiHariMan.create_node({"quality": 1.0})
	world.add_child(hero)
	var skeleton := hero.get_child(0) as Skeleton3D
	animator = HumanoidAnimator.new(skeleton)
	animator.ground_raycast = false
	animator.speed = 0.0
	animator.grounded = true
	hero.add_child(animator)

	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	# look_at needs a node inside an active tree, which _initialize predates —
	# build the aim transform directly instead.
	camera.transform = Transform3D.IDENTITY.looking_at(
		Vector3(0, 1.05, 0) - Vector3(1.15, 1.35, 2.55)).translated(Vector3(1.15, 1.35, 2.55))
	world.add_child(camera)

func _process(delta: float) -> bool:
	frames += 1
	if animator != null:
		animator.update(delta)
	if frames < WARMUP:
		return false
	var camera := root.get_camera_3d()
	if camera != null:
		print("  cam pos=%s fwd=%s hero_screen=%s" % [
			camera.global_position.snapped(Vector3.ONE * 0.01),
			(-camera.global_transform.basis.z).snapped(Vector3.ONE * 0.01),
			camera.unproject_position(Vector3(0, 1.05, 0)).snapped(Vector2.ONE)])
	else:
		print("  NO CURRENT CAMERA")
	var image := root.get_texture().get_image()
	image.save_png("user://portrait.png")
	print("portrait saved: %s (%dx%d)" % [
		ProjectSettings.globalize_path("user://portrait.png"), image.get_width(), image.get_height()])
	return true
