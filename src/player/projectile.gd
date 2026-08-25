class_name EnergyBolt
extends Area3D
## DIGIHARIMAN's ranged attack: a bolt of orange energy that leads slightly
## toward the locked-on target so aiming stays generous without feeling automatic.

var velocity := Vector3.FORWARD * 42.0
var damage: float = 34.0
var homing_target: Node3D = null
var homing_strength: float = 3.2
var life: float = 3.2
var radius: float = 0.34

func _init() -> void:
	name = "EnergyBolt"
	collision_layer = 1 << 3          # player_hitbox
	collision_mask = (1 << 2) | 1     # enemies and world
	monitorable = false

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)

	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	core.mesh = mesh
	core.material_override = Materials.energy(Materials.ORANGE_EMISSIVE, 22.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var light := OmniLight3D.new()
	light.light_color = Materials.ORANGE_EMISSIVE
	light.light_energy = 6.5
	light.omni_range = 8.0
	light.light_volumetric_fog_energy = 4.0
	add_child(light)

	var trail := VFX.dash_trail(self, Materials.ORANGE_EMISSIVE)
	trail.emitting = true
	(trail.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.1, 0.1, 0.1)

	body_entered.connect(_on_hit)
	area_entered.connect(_on_area)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_burst(global_position, Vector3.UP)
		return
	if homing_target != null and is_instance_valid(homing_target):
		var desired := (homing_target.global_position + Vector3.UP * 0.9 - global_position).normalized() * velocity.length()
		velocity = velocity.lerp(desired, clampf(homing_strength * delta, 0.0, 1.0))
	global_position += velocity * delta
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)

func _on_hit(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.call("take_damage", damage, global_position, velocity.normalized(), false)
	_burst(global_position, -velocity.normalized())

func _on_area(area: Area3D) -> void:
	var owner_node := area.get_parent()
	if owner_node != null and owner_node.has_method("take_damage"):
		owner_node.call("take_damage", damage, global_position, velocity.normalized(), false)
		_burst(global_position, -velocity.normalized())

func _burst(at: Vector3, normal: Vector3) -> void:
	var parent := get_parent()
	if parent != null:
		VFX.impact(parent, at, normal, Materials.ORANGE_EMISSIVE, 1.2)
	Signals.camera_shake_requested.emit(0.12, 0.15)
	queue_free()
