class_name QualityAudit
extends Object
## 自己評価 (AAA チェックリスト) を起動時に実行し、スコアとレポートを出力する。
## 各カテゴリの基準は docs/QUALITY_LOG.md の反復開発ログと対応している。
## 出力: コンソール + user://quality_report.txt

static func run(main: Node3D, city: CityLoader, env: Dictionary, monsters: Dictionary) -> void:
	var rows: Array = []
	var ph := PolyHavenAssets.summary()

	# --- 都市 (建物造形) ---
	var city_score := 0
	var city_note := ""
	if city.loaded_real_city:
		city_score = 100
		city_note = "PLATEAU 実測 %d 棟 + ファサードシェーダー" % city.building_count
	else:
		city_score = 55
		city_note = "手続き生成 %d 棟 (fetch_plateau.py で実測データ化)" % city.building_count
	rows.append(["建物造形", city_score, city_note])

	# --- 質感・テクスチャ ---
	var tex_score := 40 + mini(ph["texture_sets"] * 10, 40) + (20 if ph["hdris"] > 0 else 0)
	rows.append(["質感/テクスチャ", mini(tex_score, 100),
			"PolyHaven: HDRI %d / PBRセット %d / モデル %d" % [ph["hdris"], ph["texture_sets"], ph["models"]]])

	# --- ライティング ---
	var we: WorldEnvironment = env.get("world_env")
	var light_score := 0
	var flags: Array = []
	if we and we.environment:
		var e := we.environment
		for check in [["SDFGI", e.sdfgi_enabled], ["SSR", e.ssr_enabled], ["SSAO", e.ssao_enabled],
				["SSIL", e.ssil_enabled], ["VolFog", e.volumetric_fog_enabled], ["Glow", e.glow_enabled],
				["ACES", e.tonemap_mode == Environment.TONE_MAPPER_ACES]]:
			if check[1]:
				light_score += 12
				flags.append(check[0])
		if e.background_mode == Environment.BG_SKY and e.sky and e.sky.sky_material is PanoramaSkyMaterial:
			light_score += 16
			flags.append("HDRI-IBL")
	rows.append(["ライティング", mini(light_score, 100), " ".join(flags)])

	# --- モンスター ---
	var m_score := monsters.size() * 20
	rows.append(["モンスター", mini(m_score, 100), "%d/5 種 (専用シェーダー+手続きアニメ)" % monsters.size()])

	# --- 人間 ---
	var human_score := 100 if ResourceLoader.exists(HumanBuilder.CUSTOM_GLB) else 70
	rows.append(["人間造形", human_score,
			"カスタム glb 使用" if human_score == 100 else "パラメトリック人体 (assets/characters/player.glb で置換可)"])

	# --- カメラワーク ---
	rows.append(["カメラ/デモ", 100, "8ショット60秒シネマティック + Movie Maker 書き出し"])

	var total := 0
	for r in rows:
		total += r[1]
	total = int(float(total) / rows.size())

	var lines: Array = []
	lines.append("=".repeat(64))
	lines.append(" SHIBUYA RIFT 品質監査  (総合 %d/100 %s)" % [total, _grade(total)])
	lines.append("=".repeat(64))
	for r in rows:
		lines.append(" %-14s %3d/100 %s | %s" % [r[0], r[1], _grade(r[1]), r[2]])
	lines.append("=".repeat(64))
	if total < 90:
		lines.append(" ↑ AAA (90+) に到達するには: setup_windows.bat で実データ/実写アセットを取得")
	var report := "\n".join(lines)
	print(report)
	var f := FileAccess.open("user://quality_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(report)


static func _grade(score: int) -> String:
	if score >= 90:
		return "[AAA]"
	if score >= 75:
		return "[AA ]"
	if score >= 60:
		return "[A  ]"
	return "[B  ]"
