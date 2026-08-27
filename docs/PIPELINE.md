# アセットパイプライン構成

```
┌─────────────────────────────┐   ┌──────────────────────────────┐
│ G空間情報センター CKAN API      │   │ Poly Haven 公式 API           │
│ plateau-13113-shibuya-ku-2025│   │ api.polyhaven.com            │
└──────────┬──────────────────┘   └──────────┬───────────────────┘
           │ fetch_plateau.py                │ fetch_polyhaven.py
           ▼                                 ▼
  CityGML zip (数GB)                HDRI (.hdr 4K) ×3
           │ 渋谷駅中心 半径700m の          PBR テクスチャセット ×5
           │ 3次メッシュだけ選択展開          (albedo/normal/rough/ao/disp)
           ▼                        写真測量 glTF (樹木・岩) ×8
  citygml_to_obj.py                          │
  - LOD2優先 (壁/屋根/接地面)                  │
  - ParameterizedTexture → UV               │
  - JGD2011 → ローカルENU [m]                │
  - 耳刈り三角形分割                          │
           ▼                                 ▼
  game/assets/city/*.obj+mtl+tex    game/assets/polyhaven/ + manifest.json
           └──────────────┬──────────────────┘
                          ▼
                Godot 4.4 (Forward+)
                  Main.gd
                  ├ EnvironmentSetup  … HDRI IBL / SDFGI / SSR / SSAO / SSIL / 霧 / ACES
                  ├ CityLoader        … PLATEAU OBJ 読込 (無ければ手続き都市)
                  ├ CityProps         … 裂け目 / ネオン / 街灯 / 植生散布
                  ├ Player+HumanBuilder … 関節人体 + 手続き歩行 (glb差し替え可)
                  ├ MonsterFactory    … 5種 (専用シェーダー + AI + アニメ)
                  ├ HUD / QualityAudit
                  └ DemoDirector      … 60秒 8ショット
                          │
                          ▼  make_demo_mp4.py
                Movie Maker (--write-movie, 60fps固定)
                          ▼
                  AVI (MJPEG) → ffmpeg (x264 CRF16) → output/shibuya_rift_demo.mp4
```

## 座標系

- CityGML: EPSG:6697 (JGD2011 緯度経度 + 標高)。posList は「緯度 経度 標高」順
- 変換: 原点 = 渋谷スクランブル交差点 (35.6595, 139.7005)、
  緯度経度1度あたりのメートル長 (楕円体近似式) でローカル化
- Godot: +X=東 / +Y=上 / -Z=北

## メッシュコード選択

半径 r の円が触れる JIS X 0410 3次メッシュ (約1.1km×0.9km) を列挙し、
zip 内の `udx/bldg/<meshcode>_bldg_*.gml` をコード前方一致で選択展開する。
外観テクスチャは同フォルダの `*_appearance/` を丸ごと展開し、
OBJ 変換時に参照されたファイルだけ `textures/` へコピーされる。

## フォールバック方針

すべての外部アセットは「無くても起動する」。取得済みなら自動でアップグレードされる。
判定は manifest.json / city_manifest.json の有無のみで、コードの変更は不要。
