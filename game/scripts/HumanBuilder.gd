class_name HumanBuilder
extends Object
## 人間キャラクターの構築。
## 1) res://assets/characters/player.glb があればそれを使用
##    (フォトスキャン/Mixamo 等の AAA モデルの差し込み口。README 参照)
## 2) 無ければ関節階層を持つパラメトリック人体を生成:
##    - SSS スキン / 布 / レザー / 髪 (異方性) のマテリアル分け
##    - 関節ノード (joints) を返し、Player 側が手続きウォークサイクルを駆動する

const CUSTOM_GLB := "res://assets/characters/player.glb"

# 体型パラメータ [m]
const H_PELVIS := 0.98
const TONE_SKIN := Color(0.85, 0.66, 0.55)
const COL_JACKET := Color(0.10, 0.11, 0.14)   # テックウェアジャケット
const COL_SHIRT := Color(0.70, 0.72, 0.75)
const COL_PANTS := Color(0.13, 0.13, 0.15)
const COL_SNEAKER := Color(0.92, 0.92, 0.90)


static func build() -> Dictionary:
	if ResourceLoader.exists(CUSTOM_GLB):
		var scene := load(CUSTOM_GLB) as PackedScene
		if scene:
			var inst := scene.instantiate()
			print("[Human] カスタム glTF モデルを使用: ", CUSTOM_GLB)
			return {"root": inst, "joints": {}, "custom": true}
	return _build_parametric()


static func _joint(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = joint_name
	n.position = pos
	parent.add_child(n)
	return n


static func _build_parametric() -> Dictionary:
	var root := Node3D.new()
	root.name = "Human"
	var joints := {}

	var skin := MatLib.skin(TONE_SKIN)
	var jacket := MatLib.fabric(COL_JACKET, 0.9)
	jacket.clearcoat_enabled = true
	jacket.clearcoat = 0.25
	jacket.clearcoat_roughness = 0.5
	var shirt := MatLib.fabric(COL_SHIRT, 0.98)
	var pants := MatLib.fabric(COL_PANTS, 0.92)
	var shoe := MatLib.leather(COL_SNEAKER)
	var hair_mat := MatLib.hair()

	# ---- 骨盤 / 胴 ----
	var pelvis := _joint(root, "Pelvis", Vector3(0, H_PELVIS, 0))
	joints["pelvis"] = pelvis
	pelvis.add_child(MatLib.mesh_node(MatLib.capsule(0.145, 0.30), pants,
			Vector3(0, 0.02, 0), Vector3(0, 0, 90), "Hips"))

	var spine := _joint(pelvis, "Spine", Vector3(0, 0.12, 0))
	joints["spine"] = spine
	spine.add_child(MatLib.mesh_node(MatLib.capsule(0.150, 0.46), jacket,
			Vector3(0, 0.17, 0), Vector3.ZERO, "Torso"))
	spine.add_child(MatLib.mesh_node(MatLib.capsule(0.118, 0.34), shirt,
			Vector3(0, 0.16, 0.045), Vector3.ZERO, "ShirtFront"))

	var chest := _joint(spine, "Chest", Vector3(0, 0.36, 0))
	joints["chest"] = chest
	chest.add_child(MatLib.mesh_node(MatLib.capsule(0.075, 0.44), jacket,
			Vector3(0, 0.05, 0), Vector3(0, 0, 90), "Shoulders"))
	chest.add_child(MatLib.mesh_node(MatLib.cone(0.052, 0.09, 0.058), skin,
			Vector3(0, 0.115, 0), Vector3.ZERO, "Neck"))

	# ---- 頭部 ----
	var head := _joint(chest, "Head", Vector3(0, 0.175, 0))
	joints["head"] = head
	head.add_child(MatLib.mesh_node(MatLib.sphere(0.104, Vector3(1, 1.18, 1)), skin,
			Vector3(0, 0.075, 0.008), Vector3.ZERO, "Skull"))
	head.add_child(MatLib.mesh_node(MatLib.box(Vector3(0.075, 0.055, 0.06)), skin,
			Vector3(0, 0.012, 0.055), Vector3.ZERO, "Jaw"))
	head.add_child(MatLib.mesh_node(MatLib.cone(0.014, 0.03, 0.008), skin,
			Vector3(0, 0.065, 0.105), Vector3(80, 0, 0), "Nose"))
	# 髪 (前下がりのショート)
	var hair := MatLib.mesh_node(MatLib.sphere(0.112, Vector3(1, 0.95, 1)), hair_mat,
			Vector3(0, 0.115, -0.012), Vector3.ZERO, "Hair")
	hair.scale = Vector3(1.0, 0.72, 1.05)
	head.add_child(hair)
	var fringe := MatLib.mesh_node(MatLib.box(Vector3(0.19, 0.05, 0.05)), hair_mat,
			Vector3(0, 0.135, 0.075), Vector3(12, 0, 0), "Fringe")
	head.add_child(fringe)
	# 目
	for side in [-1.0, 1.0]:
		var sfx := "L" if side < 0 else "R"
		head.add_child(MatLib.mesh_node(MatLib.sphere(0.0155), MatLib.eye(),
				Vector3(side * 0.037, 0.082, 0.086), Vector3.ZERO, "Eye" + sfx))
		var iris := MatLib.mesh_node(MatLib.sphere(0.0075),
				MatLib.fabric(Color(0.15, 0.09, 0.05), 0.2),
				Vector3(side * 0.037, 0.082, 0.100), Vector3.ZERO, "Iris" + sfx)
		head.add_child(iris)
		var brow := MatLib.mesh_node(MatLib.box(Vector3(0.042, 0.008, 0.012)), hair_mat,
				Vector3(side * 0.037, 0.112, 0.092), Vector3(0, 0, side * -6), "Brow" + sfx)
		head.add_child(brow)

	# ---- 腕 ----
	for side in [-1.0, 1.0]:
		var sfx := "l" if side < 0 else "r"
		var shoulder := _joint(chest, "Shoulder_" + sfx, Vector3(side * 0.225, 0.05, 0))
		joints["shoulder_" + sfx] = shoulder
		shoulder.add_child(MatLib.mesh_node(MatLib.capsule(0.049, 0.30), jacket,
				Vector3(0, -0.14, 0), Vector3.ZERO, "UpperArm"))
		var elbow := _joint(shoulder, "Elbow_" + sfx, Vector3(0, -0.29, 0))
		joints["elbow_" + sfx] = elbow
		elbow.add_child(MatLib.mesh_node(MatLib.capsule(0.042, 0.26), jacket,
				Vector3(0, -0.12, 0), Vector3.ZERO, "ForeArm"))
		elbow.add_child(MatLib.mesh_node(MatLib.sphere(0.042, Vector3(1, 1.35, 1)), skin,
				Vector3(0, -0.285, 0.01), Vector3.ZERO, "Hand"))

	# ---- 脚 ----
	for side in [-1.0, 1.0]:
		var sfx := "l" if side < 0 else "r"
		var hip := _joint(pelvis, "Hip_" + sfx, Vector3(side * 0.098, -0.05, 0))
		joints["hip_" + sfx] = hip
		hip.add_child(MatLib.mesh_node(MatLib.capsule(0.074, 0.40), pants,
				Vector3(0, -0.20, 0), Vector3.ZERO, "Thigh"))
		var knee := _joint(hip, "Knee_" + sfx, Vector3(0, -0.43, 0))
		joints["knee_" + sfx] = knee
		knee.add_child(MatLib.mesh_node(MatLib.capsule(0.056, 0.38), pants,
				Vector3(0, -0.19, 0), Vector3.ZERO, "Shin"))
		knee.add_child(MatLib.mesh_node(MatLib.box(Vector3(0.092, 0.065, 0.25)), shoe,
				Vector3(0, -0.425, 0.05), Vector3.ZERO, "Sneaker"))

	# 影を柔らかく受けるための設定
	for mi in _all_meshes(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	return {"root": root, "joints": joints, "custom": false}


static func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _all_meshes(c)
	return out
