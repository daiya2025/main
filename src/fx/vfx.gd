class_name VFX
extends RefCounted
## Combat and ambience effects.
##
## Everything is generated: particle materials, gradients and curves are built
## in code so the whole look re-grades from the orange palette in Materials.

static var _cache: Dictionary = {}

static func _gradient(colors: Array, offsets: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex

static func _curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for p in points:
		curve.add_point(Vector2(p[0], p[1]))
	curve.bake()
	var tex := CurveTexture.new()
	tex.curve = curve
	tex.width = 64
	return tex

static func _billboard_material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "bb_%s_%0.1f" % [color.to_html(false), energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without keep_scale a particle billboard ignores its own scale and draws at
	# the source quad's size, which turns a fine spark spray into a wall of
	# squares big enough to hide the character behind it.
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color * energy
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	_cache[key] = mat
	return mat

static func _quad(size: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	return mesh

# ------------------------------------------------------------------ bursts --

## A one-shot impact: hot sparks along the surface normal plus a soft flash.
static func impact(parent: Node, world_pos: Vector3, normal: Vector3, color: Color = Materials.ORANGE_EMISSIVE, scale: float = 1.0) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Impact"
	particles.amount = int(38 * scale * Quality.particle_scale()) + 6
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.09 * scale
	process.direction = normal
	process.spread = 62.0
	process.initial_velocity_min = 3.5 * scale
	process.initial_velocity_max = 11.0 * scale
	process.gravity = Vector3(0, -14.0, 0)
	process.damping_min = 2.0
	process.damping_max = 6.0
	process.scale_min = 0.22 * scale
	process.scale_max = 0.7 * scale
	process.scale_curve = _curve([[0.0, 1.0], [0.35, 0.7], [1.0, 0.0]])
	process.color_ramp = _gradient(
		[Color(1.0, 0.95, 0.75, 1.0), color, color.darkened(0.6) * 0.6, Color(0.2, 0.06, 0.02, 0.0)],
		[0.0, 0.25, 0.7, 1.0])
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 3.0
	particles.process_material = process
	particles.draw_pass_1 = _quad(0.10)
	particles.material_override = _billboard_material(Color.WHITE, 2.2)

	particles.position = world_pos
	particles.top_level = true
	parent.add_child(particles)

	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 9.0 * scale
	flash.omni_range = 5.5 * scale
	flash.position = world_pos
	flash.top_level = true
	parent.add_child(flash)

	var tween := particles.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.22)
	tween.tween_callback(flash.queue_free)
	tween.tween_interval(0.8)
	tween.tween_callback(particles.queue_free)

## The arc a melee swing leaves behind: a thin ring segment that expands and
## fades. Cheap, and far more readable than a particle spray.
static func slash_arc(parent: Node, transform: Transform3D, radius: float = 1.5, color: Color = Materials.ORANGE_EMISSIVE) -> void:
	var arc := MeshInstance3D.new()
	arc.name = "SlashArc"
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.72
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 8
	arc.mesh = mesh
	var mat := Materials.energy(color, 16.0).duplicate() as ShaderMaterial
	mat.set_shader_parameter("alpha_scale", 1.0)
	arc.material_override = mat
	arc.transform = transform
	arc.top_level = true
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(arc)

	var tween := arc.create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3.ONE * 1.65, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(v: float) -> void:
		mat.set_shader_parameter("alpha_scale", v)
		mat.set_shader_parameter("intensity", 16.0 * v), 1.0, 0.0, 0.26)
	tween.chain().tween_callback(arc.queue_free)

## Trailing embers behind a dash.
static func dash_trail(parent: Node3D, color: Color = Materials.ORANGE_EMISSIVE) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "DashTrail"
	particles.amount = int(70 * Quality.particle_scale()) + 10
	particles.lifetime = 0.55
	particles.emitting = false
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.3, 0.85, 0.3)
	process.direction = Vector3(0, 1, 0)
	process.spread = 30.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0, 1.2, 0)
	process.damping_min = 1.5
	process.damping_max = 3.5
	process.scale_min = 0.1
	process.scale_max = 0.36
	process.scale_curve = _curve([[0.0, 0.2], [0.25, 1.0], [1.0, 0.0]])
	process.color_ramp = _gradient(
		[Color(1.0, 0.85, 0.55, 0.9), color, Color(0.35, 0.10, 0.02, 0.0)], [0.0, 0.4, 1.0])
	particles.process_material = process
	particles.draw_pass_1 = _quad(0.12)
	particles.material_override = _billboard_material(Color.WHITE, 1.5)
	parent.add_child(particles)
	return particles

## Steady aura around the hero, intensity driven by the energy meter.
static func aura(parent: Node3D, color: Color = Materials.ORANGE_EMISSIVE) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Aura"
	particles.amount = int(20 * Quality.particle_scale()) + 4
	particles.lifetime = 1.3
	particles.emitting = true
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	# A ring around the silhouette rather than a cloud through it: the aura is
	# meant to read at the edges, not to sit on top of the armour.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3(0, 1, 0)
	process.emission_ring_height = 1.7
	process.emission_ring_radius = 0.52
	process.emission_ring_inner_radius = 0.42
	process.direction = Vector3(0, 1, 0)
	process.spread = 14.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.6
	process.gravity = Vector3(0, 0.5, 0)
	process.scale_min = 0.25
	process.scale_max = 0.8
	process.scale_curve = _curve([[0.0, 0.0], [0.3, 1.0], [1.0, 0.0]])
	process.color_ramp = _gradient(
		[Color(1.0, 0.7, 0.35, 0.0), color, Color(1.0, 0.35, 0.05, 0.0)], [0.0, 0.35, 1.0])
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.9
	particles.process_material = process
	particles.draw_pass_1 = _quad(0.05)
	particles.material_override = _billboard_material(Color.WHITE, 1.1)
	parent.add_child(particles)
	return particles

## Death dissolve: the creature's data unravels upwards.
static func dissolve(parent: Node, world_pos: Vector3, scale: float = 1.0) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Dissolve"
	particles.amount = int(160 * scale * Quality.particle_scale()) + 20
	particles.lifetime = 1.5
	particles.one_shot = true
	particles.explosiveness = 0.75
	particles.emitting = true
	particles.top_level = true
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.9 * scale
	process.direction = Vector3(0, 1, 0)
	process.spread = 45.0
	process.initial_velocity_min = 1.2 * scale
	process.initial_velocity_max = 5.5 * scale
	process.gravity = Vector3(0, 2.2, 0)
	process.damping_min = 0.5
	process.damping_max = 2.0
	process.scale_min = 0.08 * scale
	process.scale_max = 0.42 * scale
	process.scale_curve = _curve([[0.0, 1.0], [0.6, 0.65], [1.0, 0.0]])
	process.color_ramp = _gradient(
		[Color(1.0, 0.9, 0.7, 1.0), Materials.ORANGE_EMISSIVE, Color(0.6, 0.15, 0.35, 0.5), Color(0.1, 0.02, 0.05, 0.0)],
		[0.0, 0.3, 0.72, 1.0])
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 2.2
	particles.process_material = process
	particles.draw_pass_1 = _quad(0.12)
	particles.material_override = _billboard_material(Color.WHITE, 2.0)
	particles.position = world_pos
	parent.add_child(particles)

	var flash := OmniLight3D.new()
	flash.light_color = Materials.ORANGE_EMISSIVE
	flash.light_energy = 14.0 * scale
	flash.omni_range = 11.0 * scale
	flash.position = world_pos
	flash.top_level = true
	parent.add_child(flash)
	var tween := particles.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_callback(flash.queue_free)
	tween.tween_interval(1.6)
	tween.tween_callback(particles.queue_free)
