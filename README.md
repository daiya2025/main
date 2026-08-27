# SHIBUYA RIFT — PLATEAU 渋谷駅前 × Godot 4 シネマティック・アクションデモ

渋谷駅上空に「次元の裂け目」が開き、5種のモンスターが街に現れた——。

国土交通省 **PLATEAU の渋谷区 2025 実測3D都市モデル**
([plateau-13113-shibuya-ku-2025](https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025))
の渋谷駅周辺を舞台に、**Poly Haven 公式 API** から自動取得した
HDRI / 写真測量PBR / フォトグラメトリ樹木・岩で画を作る、
Godot 4.4 (Forward+) 製の 3D アクション + 60秒シネマティックデモです。

- 三人称アクション: 雨の渋谷を探索し、モンスター5種と戦う
- `--demo` / Movie Maker モード: 8ショット構成の60秒デモを **MP4 (1080p/4K, 60fps)** に書き出し
- すべての外部アセットは**無くても起動**し、取得すると自動で実データ品質に切り替わる
- 起動ごとに `QualityAudit` が AAA チェックリストで自己採点 (詳細: [docs/QUALITY_LOG.md](docs/QUALITY_LOG.md))

対象環境: **Windows 11 / RAM 64GB / RTX 5080** (RTX 5080 なら全機能を既定値のまま 4K で回せます)

---

## セットアップ (Windows 11)

### 0. 必要ソフト

| ソフト | 入手 |
|---|---|
| Python 3.11+ | https://www.python.org/downloads/ (追加ライブラリ不要・標準ライブラリのみ) |
| Godot 4.4.x (標準版) | https://godotengine.org/download/windows/ |
| ffmpeg (MP4変換用) | `winget install Gyan.FFmpeg` |

### 1. アセット自動取得

```bat
setup_windows.bat
```

これだけで以下が走ります (合計数GBのダウンロード、初回 10〜40分):

1. **Poly Haven** (`tools/fetch_polyhaven.py`) — 公式 API で
   夜/夕/昼の HDRI (4K)、アスファルト・歩道・コンクリート等の PBR 5セット、
   写真測量された樹木4種・岩4種 (glTF) を取得 → `game/assets/polyhaven/`
2. **PLATEAU** (`tools/fetch_plateau.py`) — CKAN API で渋谷区 2025 の CityGML を発見・取得し、
   渋谷スクランブル交差点から半径 700m の建物 (LOD2、外観テクスチャ付き) だけを抽出して
   OBJ に変換 → `game/assets/city/`

個別実行やオプション (`--radius 1000`, `--hdri-res 8k`, `--zip 手動DL済み.zip` など) は
各スクリプトの `--help` を参照。

### 2. ゲーム起動

Godot で `game/project.godot` を開き (初回インポート数分)、**F5**。

| 操作 | キー |
|---|---|
| 移動 / 疾走 / ジャンプ | WASD / Shift / Space |
| カメラ | マウス |
| 攻撃 | 左クリック |
| マウス解放 | Esc |

起動オプション: `--preset=night|dusk|day` (既定 night)、`--demo` (60秒デモ再生)

### 3. 60秒デモ MP4 作成

```bat
py -3 tools\make_demo_mp4.py --godot "C:\path\to\Godot_v4.4.1-stable_win64.exe"
:: 4K で出す場合
py -3 tools\make_demo_mp4.py --godot ... --resolution 3840x2160 --preset night
```

Godot の Movie Maker モードで **60fps 固定・1フレームずつ確定レンダリング**した後、
ffmpeg (x264 CRF16) で `output/shibuya_rift_demo_*.mp4` に変換します。
リアルタイムではないため RTX 5080 でも実時間より長くかかります (1080p で 5〜15分程度)。

---

## 画作りの構成 (AAA チェックリスト)

- **建物**: PLATEAU 実測 LOD2 メッシュ + 外観写真テクスチャ。無地面には
  ワールド座標窓グリッドのファサードシェーダー (夜間ランダム点灯・ちらつき・色調差)
- **質感**: Poly Haven 写真測量 PBR (albedo/normal/rough/AO/disp) をトリプラナー適用。
  路面は fbm 水たまり + 雨滴リップル + SSR の濡れ表現
- **ライティング**: HDRI IBL + SDFGI + SSR + SSAO + SSIL + ボリュメトリックフォグ +
  ACES トーンマップ + ブルーム + 街灯/ネオン数十灯 (クラスタード) + 雨 6000 粒
- **人間**: 関節階層パラメトリック人体 (SSSスキン/布/レザー/異方性ヘア) +
  手続きウォークサイクル。`game/assets/characters/player.glb` を置くと
  フォトスキャン級モデル (Mixamo 等、`walk`/`idle` アニメ付き glb) に自動差し替え
- **モンスター5種**: カゲオニ (黒曜石+マグマ) / ネオンリッパー (玉虫色高速ラプトル) /
  ゲンブ (ルーン石亀) / スクランブラー (半透明浮遊体) / トシクイ (20m級怪獣)。
  全種が専用シェーダー・手続きアニメ・AI・被弾フラッシュ・ディゾルブ消滅を持つ
- **カメラ**: クレーン/ドリー/トラッキング/オービットの8ショット + ショット別 DoF +
  レターボックス + タイトル

## リポジトリ構成

```
tools/    Python パイプライン (PLATEAU取得・CityGML→OBJ・PolyHaven取得・MP4書き出し)
game/     Godot 4.4 プロジェクト (scripts/ shaders/ scenes/)
docs/     QUALITY_LOG.md (自己評価反復ログ) / PIPELINE.md (データフロー)
```

## ライセンス / 出典

- 3D都市モデル: [PLATEAU](https://www.mlit.go.jp/plateau/) 渋谷区 2025 (国土交通省, CC BY 4.0) —
  クレジット表記例「出典: 国土交通省 PLATEAU 3D都市モデル (渋谷区)」
- HDRI / テクスチャ / モデル: [Poly Haven](https://polyhaven.com/) (CC0)
- コード: このリポジトリのコードは自由に利用してください
