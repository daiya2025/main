#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Poly Haven 公式 API から HDRI / PBR テクスチャ / フォトグラメトリモデルを自動取得する。

- HDRI          : 夜 / 夕暮れ / 昼 の3枚 (渋谷の夜景演出がメイン)
- PBRテクスチャ  : アスファルト / 歩道 / コンクリート / 広場 / 土 (Diffuse, Normal, Rough, AO, Displacement)
- モデル        : 写真測量された樹木・岩 (glTF + テクスチャ一式)

取得結果は game/assets/polyhaven/ に保存され、Godot 側が読む manifest.json を生成する。

公式 API ドキュメント: https://redocly.github.io/redoc/?url=https://api.polyhaven.com/api-docs/swagger.json
すべて CC0 ライセンス。

使い方 (Windows):
    py -3 tools\\fetch_polyhaven.py --hdri-res 4k --tex-res 2k --model-res 2k
"""

import argparse
import json
import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

API = "https://api.polyhaven.com"
REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "game" / "assets" / "polyhaven"
UA = {"User-Agent": "shibuya-rift-asset-fetcher/1.0 (Godot game pipeline)"}

# 優先的に使いたい厳選アセットID (存在しなければ動的検索でフォールバック)
CURATED_HDRIS = {
    "night": ["shanghai_bund", "potsdamer_platz", "moonless_golf"],
    "dusk": ["the_sky_is_on_fire", "kiara_1_dawn", "preller_drive"],
    "day": ["kloppenheim_06", "kloppenheim_02", "citrus_orchard_road"],
}
TEXTURE_ROLES = {
    "asphalt": ["asphalt"],
    "sidewalk": ["paving stones", "paving", "sidewalk"],
    "concrete": ["concrete"],
    "plaza": ["cobblestone", "tiles"],
    "soil": ["dirt", "forest ground", "ground", "mud"],
}
MODEL_KINDS = {
    "trees": (["tree", "pine", "oak", "maple", "birch"], 4),
    "rocks": (["rock", "boulder", "stone", "cliff"], 4),
}
MODEL_EXCLUDE = ["christmas", "palm_pot", "plant_pot", "bonsai"]


def api_get(path: str, retries: int = 4):
    url = f"{API}{path}"
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            last = e
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(2**i)
    raise RuntimeError(f"API取得に失敗: {url}: {last}")


def download(url: str, dest: Path, expected_size: int | None = None) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and (expected_size is None or dest.stat().st_size == expected_size):
        print(f"  [skip] {dest.relative_to(REPO_ROOT)}")
        return True
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                got = 0
                while True:
                    chunk = r.read(1 << 18)
                    if not chunk:
                        break
                    f.write(chunk)
                    got += len(chunk)
                    if total:
                        pct = got * 100 // total
                        print(f"\r  [{pct:3d}%] {dest.name}", end="", flush=True)
            print(f"\r  [done] {dest.relative_to(REPO_ROOT)}")
            return True
        except Exception as e:  # noqa: BLE001
            print(f"\n  [retry {i + 1}] {url}: {e}")
            time.sleep(2**i)
    print(f"  [FAIL] {url}")
    return False


def pick_file(files: dict, map_keywords: list[str], res: str, exts=("jpg", "png", "exr", "hdr")):
    """files 構造 (map名 -> 解像度 -> 拡張子 -> {url,size}) からマップを1つ選ぶ。"""
    for key in files:
        low = key.lower()
        if any(kw in low for kw in map_keywords):
            by_res = files[key]
            if not isinstance(by_res, dict):
                continue
            resolutions = [res] + [r for r in ("2k", "4k", "1k", "8k") if r != res]
            for r in resolutions:
                if r in by_res:
                    for ext in exts:
                        if ext in by_res[r]:
                            return by_res[r][ext], key, r
    return None, None, None


def score_asset(asset_id: str, info: dict, keywords: list[str]) -> int:
    hay = " ".join([asset_id.replace("_", " "), info.get("name", "").lower()]
                   + [t.lower() for t in info.get("tags", [])]
                   + [c.lower() for c in info.get("categories", [])])
    s = 0
    for kw in keywords:
        if kw in hay:
            s += 100
    s += min(info.get("download_count", 0) // 1000, 90)
    return s


def fetch_hdris(res: str) -> dict:
    print("\n=== HDRI 取得 ===")
    listing = api_get("/assets?type=hdris") or {}
    result = {}
    for slot, curated in CURATED_HDRIS.items():
        chosen = next((c for c in curated if c in listing), None)
        if chosen is None:
            # 動的フォールバック: カテゴリ検索
            want = {"night": ["night", "urban"], "dusk": ["sunrise-sunset"], "day": ["clear", "urban"]}[slot]
            ranked = sorted(listing.items(),
                            key=lambda kv: score_asset(kv[0], kv[1], want), reverse=True)
            chosen = ranked[0][0] if ranked else None
        if chosen is None:
            continue
        files = api_get(f"/files/{chosen}")
        if not files or "hdri" not in files:
            continue
        entry, _, actual_res = pick_file({"hdri": files["hdri"]}, ["hdri"], res, exts=("hdr", "exr"))
        if not entry:
            continue
        ext = Path(entry["url"]).suffix
        dest = OUT_DIR / "hdris" / f"{chosen}_{actual_res}{ext}"
        if download(entry["url"], dest, entry.get("size")):
            result[slot] = f"res://assets/polyhaven/hdris/{dest.name}"
            print(f"  {slot}: {chosen} ({actual_res})")
    return result


MAP_KEYWORDS = {
    "albedo": ["diffuse", "diff", "color", "albedo"],
    "normal": ["nor_gl"],
    "rough": ["rough"],
    "ao": ["ao"],
    "disp": ["displacement", "disp", "height"],
}


def fetch_textures(res: str) -> dict:
    print("\n=== PBR テクスチャ取得 ===")
    listing = api_get("/assets?type=textures") or {}
    result = {}
    for role, keywords in TEXTURE_ROLES.items():
        ranked = sorted(listing.items(), key=lambda kv: score_asset(kv[0], kv[1], keywords), reverse=True)
        if not ranked or score_asset(*ranked[0], keywords) < 100:
            print(f"  [warn] {role}: 該当なし")
            continue
        asset_id = ranked[0][0]
        files = api_get(f"/files/{asset_id}")
        if not files:
            continue
        maps = {}
        for map_name, kws in MAP_KEYWORDS.items():
            entry, key, actual_res = pick_file(files, kws, res)
            if map_name == "normal" and not entry:  # nor_gl が無ければ nor_dx でも可 (GodotはGL式だが反転で対応可)
                entry, key, actual_res = pick_file(files, ["nor_dx", "normal"], res)
            if entry:
                ext = Path(entry["url"]).suffix
                dest = OUT_DIR / "textures" / role / f"{asset_id}_{map_name}_{actual_res}{ext}"
                if download(entry["url"], dest, entry.get("size")):
                    maps[map_name] = f"res://assets/polyhaven/textures/{role}/{dest.name}"
        if maps.get("albedo"):
            result[role] = {"asset": asset_id, **maps}
            print(f"  {role}: {asset_id} ({len(maps)} maps)")
    return result


def fetch_models(res: str) -> dict:
    print("\n=== フォトグラメトリモデル取得 (樹木・岩) ===")
    listing = api_get("/assets?type=models") or {}
    result = {}
    for kind, (keywords, count) in MODEL_KINDS.items():
        ranked = sorted(listing.items(), key=lambda kv: score_asset(kv[0], kv[1], keywords), reverse=True)
        picked = []
        for asset_id, info in ranked:
            if len(picked) >= count:
                break
            if score_asset(asset_id, info, keywords) < 100:
                break
            if any(x in asset_id for x in MODEL_EXCLUDE):
                continue
            files = api_get(f"/files/{asset_id}")
            if not files or "gltf" not in files:
                continue
            by_res = files["gltf"]
            resolutions = [res] + [r for r in ("2k", "1k", "4k") if r != res]
            entry = None
            for r in resolutions:
                if r in by_res and "gltf" in by_res[r]:
                    entry = by_res[r]["gltf"]
                    break
            if not entry:
                continue
            model_dir = OUT_DIR / "models" / asset_id
            gltf_dest = model_dir / f"{asset_id}.gltf"
            ok = download(entry["url"], gltf_dest, entry.get("size"))
            for rel, sub in (entry.get("include") or {}).items():
                ok = download(sub["url"], model_dir / rel, sub.get("size")) and ok
            if ok:
                picked.append(f"res://assets/polyhaven/models/{asset_id}/{gltf_dest.name}")
                print(f"  {kind}: {asset_id}")
        result[kind] = picked
    return result


def main():
    ap = argparse.ArgumentParser(description="Poly Haven アセット自動取得")
    ap.add_argument("--hdri-res", default="4k", choices=["1k", "2k", "4k", "8k"])
    ap.add_argument("--tex-res", default="2k", choices=["1k", "2k", "4k"])
    ap.add_argument("--model-res", default="2k", choices=["1k", "2k", "4k"])
    ap.add_argument("--skip-models", action="store_true")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generated_by": "tools/fetch_polyhaven.py",
        "license": "CC0 (Poly Haven)",
        "hdris": fetch_hdris(args.hdri_res),
        "textures": fetch_textures(args.tex_res),
        "models": {} if args.skip_models else fetch_models(args.model_res),
    }
    manifest_path = OUT_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nmanifest 書き出し: {manifest_path}")
    n_tex = len(manifest["textures"])
    n_mdl = sum(len(v) for v in manifest["models"].values())
    print(f"HDRI {len(manifest['hdris'])} / テクスチャセット {n_tex} / モデル {n_mdl}")
    if not manifest["hdris"]:
        print("[warn] HDRI が1枚も取得できませんでした。ネットワークを確認して再実行してください。")
        sys.exit(1)


if __name__ == "__main__":
    main()
