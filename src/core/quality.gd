extends Node
## Renderer quality director. Autoloaded as `Quality`.
##
## Default target is the user's rig: Windows 11 / 64 GB / RTX 5080, which can
## run every Forward+ feature Godot 4.4 has at native 1440p-4K. Lower presets
## exist so the same build still ships on weaker GPUs.

enum Preset { ULTRA, HIGH, BALANCED, PERFORMANCE }

const PRESETS := {
	Preset.ULTRA: {
		"name": "ULTRA",
		"msaa": Viewport.MSAA_4X,
		"taa": true,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"scaling": 1.0,
		"sdfgi": true,
		"sdfgi_cascades": 6,
		"sdfgi_half_res": false,
		"ssao": true,
		"ssil": true,
		"ssr": true,
		"ssr_steps": 96,
		"volumetric_fog": true,
		"fog_density": 0.028,
		"glow": true,
		"shadow_size": 8192,
		"shadow_splits": 4,
		"shadow_distance": 320.0,
		"foliage_density": 1.0,
		"draw_distance": 900.0,
		"particle_scale": 1.0,
		"reflection_probe_res": 1024,
	},
	Preset.HIGH: {
		"name": "HIGH",
		"msaa": Viewport.MSAA_2X,
		"taa": true,
		"scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR,
		"scaling": 1.0,
		"sdfgi": true,
		"sdfgi_cascades": 4,
		"sdfgi_half_res": false,
		"ssao": true,
		"ssil": true,
		"ssr": true,
		"ssr_steps": 48,
		"volumetric_fog": true,
		"fog_density": 0.024,
		"glow": true,
		"shadow_size": 4096,
		"shadow_splits": 3,
		"shadow_distance": 220.0,
		"foliage_density": 0.75,
		"draw_distance": 700.0,
		"particle_scale": 0.8,
		"reflection_probe_res": 512,
	},
	Preset.BALANCED: {
		"name": "BALANCED",
		"msaa": Viewport.MSAA_2X,
		"taa": true,
		"scaling_mode": Viewport.SCALING_3D_MODE_FSR2,
		"scaling": 0.77,
		"sdfgi": true,
		"sdfgi_cascades": 4,
		"sdfgi_half_res": true,
		"ssao": true,
		"ssil": false,
		"ssr": false,
		"ssr_steps": 24,
		"volumetric_fog": true,
		"fog_density": 0.02,
		"glow": true,
		"shadow_size": 4096,
		"shadow_splits": 2,
		"shadow_distance": 160.0,
		"foliage_density": 0.5,
		"draw_distance": 520.0,
		"particle_scale": 0.6,
		"reflection_probe_res": 256,
	},
	Preset.PERFORMANCE: {
		"name": "PERFORMANCE",
		"msaa": Viewport.MSAA_DISABLED,
		"taa": false,
		"scaling_mode": Viewport.SCALING_3D_MODE_FSR2,
		"scaling": 0.6,
		"sdfgi": false,
		"sdfgi_cascades": 2,
		"sdfgi_half_res": true,
		"ssao": true,
		"ssil": false,
		"ssr": false,
		"ssr_steps": 8,
		"volumetric_fog": false,
		"fog_density": 0.015,
		"glow": true,
		"shadow_size": 2048,
		"shadow_splits": 2,
		"shadow_distance": 110.0,
		"foliage_density": 0.3,
		"draw_distance": 380.0,
		"particle_scale": 0.4,
		"reflection_probe_res": 128,
	},
}

var current: Preset = Preset.ULTRA
var config: Dictionary = PRESETS[Preset.ULTRA]

## Nodes that want to react to a preset switch register here.
var _environment: Environment = null
var _sun: DirectionalLight3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved := String(Settings.get_value("quality_preset", "ULTRA"))
	for key in PRESETS.keys():
		if PRESETS[key]["name"] == saved:
			current = key
	config = PRESETS[current]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quality_cycle"):
		cycle()

func cycle() -> void:
	var keys := PRESETS.keys()
	var idx := keys.find(current)
	apply_preset(keys[(idx + 1) % keys.size()])

func register_environment(env: Environment, sun: DirectionalLight3D) -> void:
	_environment = env
	_sun = sun
	_apply_to_nodes()

func apply_preset(preset: Preset) -> void:
	current = preset
	config = PRESETS[preset]
	Settings.set_value("quality_preset", config["name"])
	_apply_to_nodes()
	Signals.quality_changed.emit(String(config["name"]))
	Signals.toast.emit("画質プリセット: %s" % config["name"], 2.0)

func _apply_to_nodes() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = config["msaa"]
		vp.use_taa = config["taa"]
		vp.scaling_3d_mode = config["scaling_mode"]
		vp.scaling_3d_scale = config["scaling"]
		vp.fsr_sharpness = 0.25
		vp.use_debanding = true
		vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	if is_instance_valid(_environment):
		var env := _environment
		env.sdfgi_enabled = config["sdfgi"]
		env.sdfgi_cascades = int(config["sdfgi_cascades"])
		env.sdfgi_use_occlusion = true
		env.ssao_enabled = config["ssao"]
		env.ssil_enabled = config["ssil"]
		env.ssr_enabled = config["ssr"]
		env.ssr_max_steps = int(config["ssr_steps"])
		env.volumetric_fog_enabled = config["volumetric_fog"]
		env.volumetric_fog_density = float(config["fog_density"])
		env.glow_enabled = config["glow"]
	if is_instance_valid(_sun):
		_sun.directional_shadow_max_distance = float(config["shadow_distance"])
		_sun.directional_shadow_mode = (
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(config["shadow_splits"]) >= 4
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		)

func foliage_density() -> float:
	return float(config["foliage_density"])

func draw_distance() -> float:
	return float(config["draw_distance"])

func particle_scale() -> float:
	return float(config["particle_scale"])
