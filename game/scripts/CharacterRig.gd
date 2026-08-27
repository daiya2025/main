class_name CharacterRig
extends Object
## プレイヤーキャラクターの構築。優先順:
##   1. assets/characters/player.glb        (ユーザー差し替え。フォトスキャン等)
##   2. assets/characters/godette/          (Godot TPSデモ: 約39k頂点 + 4K PBR + 55アニメ, CC-BY 3.0)
##   3. assets/characters/mannequiny/       (GDQuest: リグ + 10アニメ, CC-BY 4.0)
##   4. HumanBuilder のパラメトリック人体    (完全フォールバック)
## 返り値: {root, anim(AnimationPlayer|null), map(状態→アニメ名), joints, kind}

const CUSTOM_GLB := "res://assets/characters/player.glb"
const GODETTE_GLB := "res://assets/characters/godette/godette.glb"
const GODETTE_TEX := "res://assets/characters/godette/textures/"
const MANNEQUIN_GLB := "res://assets/characters/mannequiny/mannequiny.glb"


static func build() -> Dictionary:
	var rig := {}
	if ResourceLoader.exists(CUSTOM_GLB):
		rig = _build_gltf(CUSTOM_GLB, "custom")
	if rig.is_empty() and ResourceLoader.exists(GODETTE_GLB):
		rig = _build_gltf(GODETTE_GLB, "godette")
	if rig.is_empty() and ResourceLoader.exists(MANNEQUIN_GLB):
		rig = _build_gltf(MANNEQUIN_GLB, "mannequiny")
	if rig.is_empty():
		var human := HumanBuilder.build()
		rig = {"root": human["root"], "anim": null, "map": {},
				"joints": human["joints"], "kind": "parametric"}
	print("[Character] リグ: ", rig["kind"])
	return rig


static func _build_gltf(path: String, kind: String) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var inst := scene.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return {}

	# glTF は -Z が正面。ゲーム側の「+Z 前」規約に合わせて180°回すラッパーを挟む
	var root := Node3D.new()
	root.name = "CharacterRig"
	var facing := Node3D.new()
	facing.name = "Facing"
	facing.rotation.y = PI
	facing.add_child(inst)
	root.add_child(facing)

	_normalize_height(inst as Node3D, facing)

	if kind == "godette":
		_apply_godette_materials(inst)

	var anim := _find_anim_player(inst)
	var map := {}
	if anim:
		_make_cycles_loop(anim)
		map = _map_animations(anim, kind)

	for mi in _meshes(inst):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return {"root": root, "anim": anim, "map": map, "joints": {}, "kind": kind}


## 身長を約1.8mに正規化し、足元を y=0 に合わせる
static func _normalize_height(model: Node3D, wrapper: Node3D) -> void:
	var aabb := _combined_aabb(model)
	if aabb.size.y <= 0.01:
		return
	var s := 1.8 / aabb.size.y
	if s < 0.5 or s > 2.0:
		wrapper.scale = Vector3.ONE * s
	else:
		s = 1.0
	wrapper.position.y = -aabb.position.y * s


static func _combined_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = _rel_transform(mi, node) * mi.get_aabb()
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)
	return aabb


static func _rel_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


## Godette の glb はテクスチャ非内蔵のため、TPSデモ相当の PBR マテリアルをコードで構築する
static func _apply_godette_materials(inst: Node) -> void:
	var albedo := _tex(GODETTE_TEX + "player_robot_albedo.png")
	var orm := _tex(GODETTE_TEX + "player_robot_orm.png")
	var normal := _tex(GODETTE_TEX + "player_robot_normal.png")
	var emissive := _tex(GODETTE_TEX + "player_robot_emissive.png")

	var body := StandardMaterial3D.new()
	body.resource_name = "playerobot"
	if albedo:
		body.albedo_texture = albedo
	body.metallic = 1.0
	if orm:
		body.metallic_texture = orm
		body.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		body.roughness_texture = orm
		body.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		body.ao_enabled = true
		body.ao_texture = orm
		body.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if normal:
		body.normal_enabled = true
		body.normal_texture = normal
	if emissive:
		body.emission_enabled = true
		body.emission = Color.BLACK  # 発光はテクスチャが加算で担う (白だと全身が光る)
		body.emission_texture = emissive
		body.emission_energy_multiplier = 4.0
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var emitter := StandardMaterial3D.new()
	emitter.resource_name = "robotemitter"
	emitter.albedo_color = Color(0.196, 0.388, 0.639)
	emitter.roughness = 0.1
	emitter.emission_enabled = true
	emitter.emission = Color(0.196, 0.388, 0.639)
	emitter.emission_energy_multiplier = 6.2

	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			if "emitter" in mat_name:
				mi.set_surface_override_material(i, emitter)
			else:
				mi.set_surface_override_material(i, body)


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


## "-cycle" 系 / ループすべきアニメにループ設定を入れる
static func _make_cycles_loop(anim: AnimationPlayer) -> void:
	for anim_name in anim.get_animation_list():
		var low := String(anim_name).to_lower()
		if "cycle" in low or "idle" in low or "run" in low or "walk" in low or low in ["dash"]:
			var a := anim.get_animation(anim_name)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR


static func _map_animations(anim: AnimationPlayer, kind: String) -> Dictionary:
	match kind:
		"godette":
			return {
				"idle": "Idle-cycle", "walk": "walking_nogun-cycle", "run": "running_nogun-cycle",
				"jump_up": "jump_1_up", "jump_air": "jump_3_midair-cycle",
				"land": "jump_5_hardlanding", "attack": ["Cannon_Charge", "flinch1"],
				"combat_idle": "Idlecombat-cycle",
			}
		"mannequiny":
			return {
				"idle": "idle", "walk": "run", "run": "run",
				"jump_up": "air_jump", "jump_air": "air_jump", "land": "air_land",
				"attack": ["fight_punch", "fight_kick"], "combat_idle": "fight_idle",
			}
	# カスタム glb: 名前のあいまい一致
	var names := anim.get_animation_list()
	var map := {}
	var wanted := {
		"idle": ["idle", "stand"], "walk": ["walk"], "run": ["run", "sprint", "jog"],
		"jump_up": ["jump"], "jump_air": ["fall", "air", "jump"], "land": ["land"],
	}
	for key in wanted:
		for anim_name in names:
			var low := String(anim_name).to_lower()
			for kw in wanted[key]:
				if kw in low:
					map[key] = anim_name
					break
			if map.has(key):
				break
	var attacks := []
	for anim_name in names:
		var low := String(anim_name).to_lower()
		if "attack" in low or "punch" in low or "kick" in low or "slash" in low:
			attacks.append(anim_name)
	if not attacks.is_empty():
		map["attack"] = attacks
	if not map.has("walk") and map.has("run"):
		map["walk"] = map["run"]
	return map


static func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _meshes(c)
	return out
