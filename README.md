# DIGIHARIMAN — ORANGE PROTOCOL

デジハリマンが活躍する 3D アクションゲーム（Godot 4.4 / Forward+）。

黄昏の市街地を舞台に、オレンジのアーマーを纏ったヒーロー **デジハリマン** が
「ノイズ体」と呼ばれるクリーチャーを排除する三人称アクションです。
人体・建築・モンスター・地形のすべてがコードから生成され、質感は Poly Haven の
CC0 フォトスキャン素材（自動取得）と自作 PBR シェーダで作り込まれています。

```
        人間造形    64ボーン / 約 97,000 三角形 / 解剖学ベースの生成 + 顔の彫刻
        建築造形    セットバック・コーニス・屋上設備・内装マッピング窓
      モンスター    3アーキタイプ / 各 約 55,000 三角形 / 四足歩行の手続き型アニメーション
          質感      SSS肌・異方性ヘア・多層アーマー塗装・甲殻の薄膜干渉・濡れアスファルト
      ライティング   HDRI + SDFGI + SSIL + SSR + ボリューメトリックフォグ + ACES
      カメラワーク   スプリングアーム・先読み・トラウマ式シェイク・被写界深度追従
```

---

## 1. 動作環境

| | 推奨（開発ターゲット） | 最低 |
|---|---|---|
| OS | Windows 11 | Windows 10 / Linux / macOS |
| CPU | 8 コア以上 | 4 コア |
| RAM | 64 GB | 16 GB |
| GPU | **GeForce RTX 5080**（Vulkan 1.2+） | Vulkan 対応 GPU 6 GB |
| Godot | **4.4.x**（Forward+） | 4.4 以上 |

RTX 5080 を前提に `ULTRA` プリセットが既定値です。SDFGI 6 カスケード、
SSIL、SSR 96 ステップ、8192px シャドウ、192³ ボリューメトリックフォグ、
MSAA 4x + TAA をすべて有効にした状態でネイティブ 1440p〜4K を想定しています。

---

## 2. クイックスタート

```bash
# 1. Godot 4.4 でプロジェクトを開く
godot --editor --path .

# 2. （任意・強く推奨）Poly Haven からフォトスキャン素材を取得
python tools/fetch_polyhaven.py --res 4k

# 3. エディタで再インポート後、F5 で実行
```

素材を取得しなくてもゲームは起動します。その場合はすべてのマテリアルが
**手続き型 PBR の代替テクスチャ**にフォールバックし、見た目の情報量だけが下がります。

初回起動時はキャラクター・建築・モンスターの生成に十数秒かかります
（ローディング画面に進捗が出ます）。生成結果は `user://cache/` に保存され、
2 回目以降は数ミリ秒で読み込まれます。

---

## 3. 操作方法

| 入力 | 動作 |
|---|---|
| `W` `A` `S` `D` | 移動（カメラ相対） |
| `Shift` | スプリント |
| `Space` | ジャンプ／二段ジャンプ |
| `Ctrl` | 回避ダッシュ（無敵フレームあり） |
| 左クリック | 連続斬撃（3 段コンボ・先行入力対応） |
| 右クリック | エナジーボルト（エナジー消費・ロックオン時は誘導） |
| 中クリック | ロックオン切り替え |
| `P` | フォトモード（ポーズ＋自由飛行カメラ） |
| `H` | HUD 表示切り替え |
| `F1` | 画質プリセット切り替え（ULTRA → HIGH → BALANCED → PERFORMANCE） |
| `Esc` | マウスカーソル解放 |
| `R` | 死亡時のリスタート |

ゲームパッド（左右スティック・A/B/X/Y・L1/R1）にも対応しています。

---

## 4. Poly Haven 自動取得パイプライン

公式 API `https://api.polyhaven.com` から **CC0** の
写真測量モデル（樹木・岩・小物）、PBR サーフェステクスチャ、HDRI を取得します。

### 4-1. エディタ内から（Poly Haven Bridge ドック）

プロジェクトを開くと右下に **Poly Haven** ドックが表示されます。

1. `Resolution` を選択（RTX 5080 なら **4K** が最適。ヒーロー面のみ 8K）
2. `textures` / `hdris` / `models` のチェックを確認
3. 追加したいスラッグがあれば `Extra slugs` にカンマ区切りで入力
4. **Fetch from Poly Haven** を押す

ダウンロード完了後は自動でプロジェクトを再スキャンし、
**Tune imports** が走ります（法線マップ圧縮、ラフネスのミップ制限、
HDRI のロスレス化など、物理的に正しい描画のためのインポート設定）。

### 4-2. コマンドラインから

```bash
python tools/fetch_polyhaven.py                    # 厳選セット・2K
python tools/fetch_polyhaven.py --res 4k --jobs 12 # 4K・12並列
python tools/fetch_polyhaven.py --list textures    # 利用可能な素材一覧
python tools/fetch_polyhaven.py --add mossy_forest --add tree_oak
```

Python 標準ライブラリのみで動作し、`HTTPS_PROXY` を自動的に尊重します。
md5 検証とレジューム（既存ファイルのスキップ）に対応しています。

### 4-3. 取得後の扱い

`assets/polyhaven/manifest.json` が書き出され、`AssetLibrary` が
**ロール名**（`asphalt` / `cliff` / `concrete_wall` …）から実素材を解決します。
`.gitignore` によりダウンロード物はリポジトリに含めません（各自で取得します）。
クレジットは `assets/polyhaven/CREDITS.md` に自動生成されます。

---

## 5. アーキテクチャ

```
project.godot            Forward+ / 8192px シャドウ / SSIL / SDFGI / TAA 設定
scenes/Main.tscn         起動シーン（中身は src/core/main.gd が構築）

src/core/
  main.gd                ゲームディレクタ。ワールド構築とウェーブ進行
  signals.gd             グローバルイベントバス（オートロード）
  settings.gd            設定の永続化（オートロード）
  quality.gd             画質プリセット director（オートロード）
  game.gd                スコア・コンボ・ヒットストップ（オートロード）
  asset_library.gd       Poly Haven ↔ 手続き型 PBR の解決（静的クラス）
  build_cache.gd         生成メッシュのディスクキャッシュ

src/procgen/
  mesh_lib.gd            ロフト／細分割／ラプラシアン平滑化／ノイズ変位／溶接／LOD
  sculpt.gd              フォールオフ・ブラシによる彫刻（ブロブ・クリース・曲げ）
  skinning.gd            カプセル重みによる自動 4 ボーンスキニング
  humanoid.gd            解剖学ベースの人体生成（64 ボーン）
  head_builder.gd        頭蓋・眉弓・眼窩・鼻・口唇・耳の彫刻
  digihariman.gd         主人公のアーマー装着と組み立て
  monster.gd             3 アーキタイプのクリーチャー生成
  building.gd            ファサード文法による建築生成
  flora.gd               再帰分岐の樹木・侵食された岩
  world.gd               街区・街路・広場・小物・植生の配置

src/render/
  materials.gd           全マテリアルのファクトリ（オレンジのパレット定義）
  sky_env.gd             HDRI 空・太陽・フィル・GI・フォグ・グロー・時間帯

src/player/
  player.gd              移動・ダッシュ・3 段コンボ・エナジーボルト・ロックオン
  camera_rig.gd          シネマティックカメラ
  animator.gd            人型の完全手続き型アニメーション（歩容モデル + IK）
  pose_kit.gd            2 ボーン IK・エイム・スプリング
  projectile.gd          エナジーボルト

src/ai/
  monster_agent.gd       敵の状態機械・ステアリング・ダメージ処理
  monster_animator.gd    四足歩行（斜対歩）の手続き型アニメーション

src/fx/vfx.gd            衝撃・斬撃弧・ダッシュ軌跡・オーラ・消滅
src/ui/hud.gd            HUD・ダメージ数値・ローディング・ポストプロセス

shaders/                 12 本の .gdshader（下記 6 章）
addons/polyhaven_bridge/ エディタ用 Poly Haven ドック
tools/fetch_polyhaven.py CLI 版アセットフェッチャ
tests/smoke_test.gd      ヘッドレス検証
tests/capture.gd         ソフトウェアレンダリングでのスクリーンショット撮影
```

### 設計上の要点

- **アニメーションデータを一切持ちません。** 歩行は歩容モデル（スタンス／スイング
  の足先軌道 + 2 ボーン IK）で解き、骨盤の上下動・脊椎の逆回転・腕振り・
  頭部の水平安定（前庭動眼反射）を層として重ねています。
- **リグの静止姿勢は並進のみ**（基底は単位行列）。これによりボーンの向き合わせが
  最短弧回転だけで済み、手続き型アニメーションのコードから補正行列が消えます。
- **アーマーは素体と同じ制御パスからロフト**されるため、必ず身体に沿います。
  スキニングも同じカプセル群を使うので、追加のアタッチメント・リグが不要です。
- **建築の壁 UV はメートル単位**。ファサードシェーダが実寸で階層と窓割りを
  レイアウトできます。
- **窓はジオメトリではなくインテリアマッピング**。接空間で仮想の部屋ボックスと
  レイ交差を取り、視差の正しい室内を描画します。

---

## 6. シェーダ

| ファイル | 内容 |
|---|---|
| `skin.gdshader` | 表面下散乱・二重スペキュラ・毛穴ノーマル・ピーチファズ |
| `eye.gdshader` | 強膜／虹彩繊維／輪部リング／瞳孔／クリアコート角膜 |
| `suit.gdshader` | 技術繊維の織り・再帰反射シーン・オレンジのエナジーライン |
| `armor.gdshader` | メタリックフレーク下地＋着色層＋クリアコート、エッジ摩耗で地金露出 |
| `energy.gdshader` | 加算合成・フレネル・流動ノイズ・深度ソフトフェード |
| `carapace.gdshader` | 甲殻モザイク・薄膜干渉・露出した肉の SSS・発光血管 |
| `terrain.gdshader` | 3 層トライプラナー、高さ加重ブレンド、傾斜岩、水たまり |
| `facade.gdshader` | インテリアマッピング窓・汚れの垂れ・階層レイアウト |
| `road.gdshader` | 摩耗アスファルト・レーンマーキング・轍・濡れ反射 |
| `hair.gdshader` | Kajiya-Kay 風異方性ハイライト・二次ローブ |
| `foliage.gdshader` | 階層的な風（幹の揺れ／枝のしなり／葉のはためき）・透過光 |
| `post_process.gdshader` | 色収差・樽型歪み・ビネット・フィルムグレイン・シャープ・グレーディング |

---

## 7. 画質プリセット

`F1` で循環します。

| プリセット | 想定 | 主な差分 |
|---|---|---|
| **ULTRA** | RTX 5080 / 1440p–4K | SDFGI 6 カスケード・SSIL・SSR 96・MSAA 4x・TAA・8192px 影 |
| HIGH | RTX 4070 級 | SDFGI 4・SSR 48・MSAA 2x・4096px 影 |
| BALANCED | ミドルレンジ | FSR2 77%・SSIL/SSR 無効・影 2 分割 |
| PERFORMANCE | ノート GPU | FSR2 60%・SDFGI 無効・フォグ無効 |

---

## 8. 検証

```bash
# ジオメトリ生成・スキニング・シェーダ・アニメーションの一括検証（GPU 不要）
godot --headless --path . --script res://tests/smoke_test.gd

# Poly Haven のレスポンス解析（ネットワーク不要）
python tools/test_fetch_polyhaven.py

# 実際に描画してスクリーンショットを撮る（ソフトウェア GL でも可）
xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tests/capture.gd

# キャラクター単体を三点照明でポートレート撮影（描画確認が速い）
xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tests/portrait.gd
```

`smoke_test.gd` が検証する内容:

- 12 本のシェーダがエンジンのパーサを通ること（ユニフォーム数で確認）
- メッシュ演算子の不変条件（細分割は 1→4、溶接後の法線、LOD が実際に 5 段生成されること）
- 人体 97,000 三角形 / モンスター各 55,000 三角形の密度
- スキンウェイトが全頂点で正規化されていること
- **歩容が実際に足を動かすこと**（足先移動 0.78 m、腕の振り 0.33 m、
  攻撃時のリーチ 1.10 m、四足の前肢 1.40 m、尻尾の追従 0.20 m）と、
  40 ティックにわたり NaN も破綻もないこと

最後の項目は「クラッシュしない」ではなく「意図した動きをしている」ことの検証です。
ボーン束縛に失敗したアニメータは静止ポーズのまま何も報告しないため、
コードレビューでは見つからず画面でしか気づけません。

### 8-1. Windows 向けビルド

`export_presets.cfg` に **Windows Desktop** プリセットを同梱しています。

```bash
# エディタで一度エクスポートテンプレートを導入したうえで
godot --headless --path . --export-release "Windows Desktop" build/DIGIHARIMAN.exe
```

`tests/` と `tools/` は除外され、S3TC/BPTC テクスチャ圧縮が有効になります。
Poly Haven 素材を先に取得しておけば、そのまま .pck に同梱されます。

---

## 9. 現状の範囲

含まれるもの: ワールド生成、キャラクター／モンスター生成とスキニング、
手続き型アニメーション、戦闘とウェーブ進行、HUD、フォトモード、
Poly Haven 連携、画質プリセット。

**含まれないもの**（意図的に範囲外）:

- **サウンド／BGM** — 音源アセットを同梱していないため未実装です。
  `AudioStreamPlayer3D` を各アクション（着地・斬撃・被弾・消滅）に足す形で
  拡張できるよう、対応するシグナルは `src/core/signals.gd` に出揃っています。
- **セーブデータ** — 設定（`user://digihariman.cfg`）のみ永続化します。
  スコアやウェーブ進行はセッション内のみです。
- **メニュー画面** — 起動即プレイです。`scenes/Main.tscn` の前に
  タイトルシーンを挟む形で追加できます。

---

## 10. ライセンス / クレジット

- コード・生成アセット: このリポジトリのライセンスに従います。
- Poly Haven 素材: **CC0**（https://polyhaven.com）。取得時に
  `assets/polyhaven/CREDITS.md` へスキャン作者のクレジットを自動生成します。
- Godot Engine: MIT License。
