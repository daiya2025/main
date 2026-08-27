#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""国土交通省 PLATEAU 渋谷区 2025 の 3D都市モデル (CityGML) を取得し、
渋谷駅周辺だけを抽出して Godot 用 OBJ に変換する。

データセット: https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025
(G空間情報センター CKAN API で配布リソースを動的に発見するため、URL変更に強い)

処理の流れ:
  1. CKAN API から CityGML zip のURLを発見してダウンロード (downloads/)
  2. 渋谷駅を中心とした半径内の 3次メッシュコードを計算し、該当する bldg gml と
     外観テクスチャ (appearance) だけを展開
  3. tools/citygml_to_obj.py で OBJ + MTL + テクスチャに変換 → game/assets/city/

使い方 (Windows):
    py -3 tools\\fetch_plateau.py                       # 全自動
    py -3 tools\\fetch_plateau.py --list                # 配布リソース一覧のみ表示
    py -3 tools\\fetch_plateau.py --zip path\\to.zip     # 手動DL済みzipを使う
    py -3 tools\\fetch_plateau.py --radius 500          # 抽出半径[m]
"""

import argparse
import io
import json
import math
import re
import sys
import time
import urllib.request
import urllib.error
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from citygml_to_obj import Transformer, convert_gml  # noqa: E402

CKAN_API = "https://www.geospatial.jp/ckan/api/3/action/package_show?id="
DATASET_ID = "plateau-13113-shibuya-ku-2025"
# 渋谷スクランブル交差点 (ハチ公前)
DEFAULT_CENTER = (35.6595, 139.7005)

REPO_ROOT = Path(__file__).resolve().parent.parent
DOWNLOADS = REPO_ROOT / "downloads"
CITY_OUT = REPO_ROOT / "game" / "assets" / "city"
UA = {"User-Agent": "shibuya-rift-plateau-fetcher/1.0"}


# ---------------------------------------------------------------- 地域メッシュ

def mesh3_code(lat: float, lon: float) -> str:
    """緯度経度 → 3次メッシュコード (8桁, JIS X 0410)。"""
    p = int(lat * 1.5)
    a = lat * 1.5 - p
    q = int(a * 8)
    b = a * 8 - q
    r = int(b * 10)
    u = int(lon - 100)
    c = lon - 100 - u
    v = int(c * 8)
    d = c * 8 - v
    w = int(d * 10)
    return f"{p:02d}{u:02d}{q}{v}{r}{w}"


def mesh3_codes_in_radius(lat0: float, lon0: float, radius_m: float) -> set[str]:
    """中心から半径内に (少しでも) かかる3次メッシュのコード集合。"""
    m_lat = 111132.0
    m_lon = 111320.0 * math.cos(math.radians(lat0))
    dlat = radius_m / m_lat
    dlon = radius_m / m_lon
    step_lat = (2.0 / 3.0) / 8.0 / 10.0   # 3次メッシュの緯度幅
    step_lon = 1.0 / 8.0 / 10.0           # 3次メッシュの経度幅
    codes = set()
    lat = lat0 - dlat - step_lat
    while lat <= lat0 + dlat + step_lat:
        lon = lon0 - dlon - step_lon
        while lon <= lon0 + dlon + step_lon:
            codes.add(mesh3_code(lat, lon))
            lon += step_lon * 0.9
        lat += step_lat * 0.9
    return codes


def code_matches(file_code: str, allowed: set[str]) -> bool:
    """gmlファイル名のメッシュコード (6〜10桁想定) と許可集合の前方一致判定。"""
    for a in allowed:
        if file_code.startswith(a) or a.startswith(file_code):
            return True
    return False


# ---------------------------------------------------------------- CKAN / ダウンロード

def fetch_json(url: str):
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"  [retry {i + 1}] {e}")
            time.sleep(2 ** i)
    return None


def list_resources(dataset_id: str):
    data = fetch_json(CKAN_API + dataset_id)
    if not data or not data.get("success"):
        return []
    return data["result"]["resources"]


def pick_citygml_resource(resources: list) -> dict | None:
    def score(r):
        text = f"{r.get('name', '')} {r.get('url', '')} {r.get('format', '')}".lower()
        s = 0
        if "citygml" in text:
            s += 100
        if text.strip().endswith(".zip") or "zip" in (r.get("format") or "").lower():
            s += 10
        if "3dtiles" in text or "3d tiles" in text or "mvt" in text:
            s -= 50
        return s

    ranked = sorted(resources, key=score, reverse=True)
    if ranked and score(ranked[0]) >= 100:
        return ranked[0]
    return None


def download_file(url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        req = urllib.request.Request(url, method="HEAD", headers=UA)
        with urllib.request.urlopen(req, timeout=60) as r:
            remote_size = int(r.headers.get("Content-Length") or 0)
    except Exception:  # noqa: BLE001
        remote_size = 0
    if dest.exists() and remote_size and dest.stat().st_size == remote_size:
        print(f"  [skip] ダウンロード済み: {dest.name} ({remote_size / 1e6:.0f} MB)")
        return True
    print(f"  ダウンロード開始: {url}")
    print(f"  (CityGML一式は数GBある場合があります。中断しても再実行で続きから確認します)")
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=1800) as r, open(dest, "wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                got = 0
                t0 = time.time()
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    got += len(chunk)
                    if total and time.time() - t0 > 1:
                        t0 = time.time()
                        print(f"\r  [{got * 100 // total:3d}%] {got / 1e6:.0f}/{total / 1e6:.0f} MB",
                              end="", flush=True)
            print(f"\r  [done] {dest.name}")
            return True
        except Exception as e:  # noqa: BLE001
            print(f"\n  [retry {i + 1}] {e}")
            time.sleep(2 ** i)
    return False


# ---------------------------------------------------------------- zip 展開

MESH_RE = re.compile(r"^(\d{6,10})_")


def iter_zip_layers(zpath: Path):
    """zip本体と、内側に入れ子になったzipを順に返す (1階層のみ)。"""
    outer = zipfile.ZipFile(zpath)
    yield outer, zpath.name
    for name in outer.namelist():
        if name.lower().endswith(".zip"):
            try:
                data = outer.read(name)
                yield zipfile.ZipFile(io.BytesIO(data)), name
            except Exception as e:  # noqa: BLE001
                print(f"  [warn] 内包zip {name} を開けません: {e}")


def extract_target_gmls(zpath: Path, allowed: set[str], work_dir: Path) -> list[Path]:
    """対象メッシュの bldg gml と appearance フォルダを work_dir に展開。"""
    work_dir.mkdir(parents=True, exist_ok=True)
    extracted: list[Path] = []
    for zf, zname in iter_zip_layers(zpath):
        names = zf.namelist()
        gmls = []
        for name in names:
            low = name.lower()
            if "/bldg/" not in low.replace("\\", "/") or not low.endswith(".gml"):
                continue
            m = MESH_RE.match(Path(name).name)
            if not m or not code_matches(m.group(1), allowed):
                continue
            gmls.append(name)
        if not gmls:
            continue
        print(f"  {zname}: 対象 gml {len(gmls)} 件")
        for gname in gmls:
            base = Path(gname).name
            dest = work_dir / base
            with zf.open(gname) as src, open(dest, "wb") as out:
                out.write(src.read())
            extracted.append(dest)
            # 同じフォルダ配下の appearance (テクスチャ) も展開
            gdir = str(Path(gname).parent).replace("\\", "/")
            stem = Path(gname).stem
            for name in names:
                norm = name.replace("\\", "/")
                if not norm.startswith(gdir + "/"):
                    continue
                rel = norm[len(gdir) + 1:]
                if not rel or rel == base or rel.endswith("/"):
                    continue
                first = rel.split("/")[0]
                if stem.split("_")[0] not in first and "appearance" not in first.lower():
                    continue
                target = work_dir / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    with zf.open(name) as src, open(target, "wb") as out:
                        out.write(src.read())
    return extracted


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="PLATEAU 渋谷区 CityGML 取得・変換")
    ap.add_argument("--dataset", default=DATASET_ID)
    ap.add_argument("--center", default=f"{DEFAULT_CENTER[0]},{DEFAULT_CENTER[1]}")
    ap.add_argument("--radius", type=float, default=700.0, help="抽出半径[m] (既定700)")
    ap.add_argument("--list", action="store_true", help="配布リソース一覧を表示して終了")
    ap.add_argument("--resource", type=int, default=None, help="使用するリソース番号 (--list の番号)")
    ap.add_argument("--zip", dest="zip_path", default=None, help="手動DL済み CityGML zip を使う")
    args = ap.parse_args()

    lat0, lon0 = (float(x) for x in args.center.split(","))

    if args.zip_path:
        zpath = Path(args.zip_path)
    else:
        print(f"=== CKAN からデータセット情報を取得: {args.dataset} ===")
        resources = list_resources(args.dataset)
        if not resources:
            print("[FAIL] CKAN API に接続できません。ブラウザで以下から CityGML zip を手動DLし、")
            print(f"       --zip で指定してください: https://www.geospatial.jp/ckan/dataset/{args.dataset}")
            sys.exit(1)
        for i, r in enumerate(resources):
            print(f"  [{i:2d}] {r.get('name', '')} | {r.get('format', '')} | {r.get('url', '')}")
        if args.list:
            return
        res = resources[args.resource] if args.resource is not None else pick_citygml_resource(resources)
        if not res:
            print("[FAIL] CityGML リソースを自動特定できません。--list で確認し --resource N で指定してください。")
            sys.exit(1)
        print(f"\n選択: {res.get('name', '')} ")
        url = res["url"]
        zpath = DOWNLOADS / Path(url.split("?")[0]).name
        if not download_file(url, zpath):
            sys.exit(1)

    print(f"\n=== 対象メッシュ計算 (中心 {lat0},{lon0} 半径 {args.radius}m) ===")
    allowed = mesh3_codes_in_radius(lat0, lon0, args.radius)
    print(f"  3次メッシュ {len(allowed)} 個: {sorted(allowed)}")

    work_dir = DOWNLOADS / "extracted"
    gmls = extract_target_gmls(zpath, allowed, work_dir)
    if not gmls:
        print("[FAIL] 対象メッシュの bldg gml が見つかりません。--radius を広げるか zip 内容を確認してください。")
        sys.exit(1)

    print(f"\n=== CityGML -> OBJ 変換 ({len(gmls)} ファイル) ===")
    tr = Transformer(lat0, lon0)
    CITY_OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for g in sorted(set(gmls)):
        info = convert_gml(g, CITY_OUT, tr, radius_m=args.radius)
        if info:
            entries.append(info)

    manifest = {
        "source": f"PLATEAU {args.dataset} (CC BY 4.0 国土交通省)",
        "center": [lat0, lon0],
        "radius_m": args.radius,
        "files": entries,
        "buildings": sum(e["buildings"] for e in entries),
        "tris": sum(e["tris"] for e in entries),
    }
    (CITY_OUT / "city_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"\n完了: 建物 {manifest['buildings']} 棟 / {manifest['tris']} 三角形 -> game/assets/city/")
    if not entries:
        sys.exit(1)


if __name__ == "__main__":
    main()
