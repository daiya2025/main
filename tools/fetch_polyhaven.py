#!/usr/bin/env python3
"""Poly Haven asset fetcher for DIGIHARIMAN - ORANGE PROTOCOL.

Pulls photogrammetry-scanned models (trees, rocks, props), PBR surface
textures and HDRI skies from the official Poly Haven API
(https://api.polyhaven.com) into ``assets/polyhaven/`` and writes the
``manifest.json`` that ``src/core/asset_library.gd`` reads at runtime.

Everything on Poly Haven is CC0, so the downloaded files can ship with the
game as-is. A CREDITS.md is still written because crediting the scanners is
the decent thing to do.

Usage
-----
    python tools/fetch_polyhaven.py                      # curated set, 2K
    python tools/fetch_polyhaven.py --res 4k             # 4K maps
    python tools/fetch_polyhaven.py --res 8k --jobs 12   # everything, big
    python tools/fetch_polyhaven.py --list textures      # browse the library
    python tools/fetch_polyhaven.py --add rock_face_03 --add mossy_forest

Only the Python standard library is used, and HTTPS_PROXY / HTTP_PROXY are
honoured automatically.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.polyhaven.com"
USER_AGENT = "DIGIHARIMAN-OrangeProtocol/1.0 (Godot asset fetcher)"

# --------------------------------------------------------------------------
# Curated set. These slugs mirror src/core/asset_library.gd so the roles the
# world builders ask for resolve to real photoscans.
# --------------------------------------------------------------------------

CURATED_TEXTURES = [
    # ground / nature
    "rocky_terrain_02", "aerial_rocks_02", "forest_leaves_02", "brown_mud_leaves_01",
    "gravel_floor", "rock_face_03", "coast_sand_rocks_02", "leafy_grass",
    # city surfaces
    "asphalt_02", "concrete_wall_008", "concrete_floor_worn_001", "red_brick_03",
    "roof_09", "floor_tiles_06", "metal_plate", "rusty_metal_02",
    # detail / props
    "wood_planks_dirt", "bark_brown_02", "scuffed_metal", "painted_concrete_02",
]

CURATED_HDRIS = [
    "kloppenheim_02_puresky",          # low sun, strong orange key light
    "syferfontein_18d_clear_puresky",  # clear golden hour
    "kloofendal_48d_partly_cloudy_puresky",
    "dikhololo_night",                 # night fight scenes
    "studio_small_09",                 # character look-dev
]

CURATED_MODELS = [
    "tree_small_02", "dead_tree_trunk", "fern_02",
    "rock_boulder_dry", "boulder_01", "rocks_ground_01",
    "concrete_barrier", "wooden_crate_02",
]

# Poly Haven map keys -> our normalised manifest keys. Checked case-insensitively.
MAP_ALIASES = {
    "diffuse": "diffuse",
    "diff": "diffuse",
    "albedo": "diffuse",
    "col": "diffuse",
    "nor_gl": "normal",
    "nor_dx": "normal_dx",
    "normal": "normal",
    "rough": "rough",
    "roughness": "rough",
    "ao": "ao",
    "displacement": "disp",
    "disp": "disp",
    "height": "disp",
    "arm": "arm",
    "metal": "metal",
    "metallic": "metal",
    "spec": "spec",
    "bump": "bump",
    "translucent": "translucent",
    "emission": "emission",
}

PREFERRED_TEXTURE_FORMATS = ["jpg", "png", "exr"]
PREFERRED_HDRI_FORMATS = ["hdr", "exr"]
RES_FALLBACK = ["8k", "4k", "2k", "1k"]


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

def http_get(url: str, retries: int = 4, timeout: int = 60) -> bytes:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
            last = exc
            wait = 2 ** attempt
            print(f"    ! {type(exc).__name__} on {url} — retry in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"giving up on {url}: {last}")


def api_json(path: str):
    return json.loads(http_get(f"{API}/{path.lstrip('/')}").decode("utf-8"))


def download(url: str, dest: str, expect_md5: str | None = None) -> bool:
    """Returns True when a new file was written, False when the cache was valid."""
    if os.path.exists(dest) and expect_md5:
        if file_md5(dest) == expect_md5:
            return False
    elif os.path.exists(dest) and os.path.getsize(dest) > 0 and not expect_md5:
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    data = http_get(url)
    tmp = dest + ".part"
    with open(tmp, "wb") as handle:
        handle.write(data)
    if expect_md5:
        got = hashlib.md5(data).hexdigest()
        if got != expect_md5:
            os.remove(tmp)
            raise RuntimeError(f"md5 mismatch for {url}: {got} != {expect_md5}")
    shutil.move(tmp, dest)
    return True


def file_md5(path: str) -> str:
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --------------------------------------------------------------------------
# File-tree walking
# --------------------------------------------------------------------------

def pick_resolution(node: dict, wanted: str) -> tuple[str, dict] | None:
    if wanted in node:
        return wanted, node[wanted]
    order = RES_FALLBACK[RES_FALLBACK.index(wanted):] if wanted in RES_FALLBACK else RES_FALLBACK
    for res in order + list(reversed(RES_FALLBACK)):
        if res in node:
            return res, node[res]
    keys = [k for k in node if isinstance(node[k], dict)]
    return (keys[0], node[keys[0]]) if keys else None


def pick_format(node: dict, preferred: list[str]) -> dict | None:
    for fmt in preferred:
        entry = node.get(fmt)
        if isinstance(entry, dict) and "url" in entry:
            return entry
    for value in node.values():
        if isinstance(value, dict) and "url" in value:
            return value
    return None


# --------------------------------------------------------------------------
# Per-type fetchers
# --------------------------------------------------------------------------

def fetch_texture(slug: str, files: dict, res: str, out_root: str, jobs_out: list) -> dict:
    entry: dict[str, str] = {"slug": slug, "kind": "texture"}
    folder = os.path.join(out_root, "textures", slug)
    for raw_key, node in files.items():
        key = MAP_ALIASES.get(raw_key.lower())
        if key is None or not isinstance(node, dict):
            continue
        picked = pick_resolution(node, res)
        if picked is None:
            continue
        res_used, fmt_node = picked
        file_entry = pick_format(fmt_node, PREFERRED_TEXTURE_FORMATS)
        if file_entry is None:
            continue
        ext = os.path.splitext(urllib.parse.urlparse(file_entry["url"]).path)[1] or ".jpg"
        dest = os.path.join(folder, f"{slug}_{key}_{res_used}{ext}")
        jobs_out.append((file_entry["url"], dest, file_entry.get("md5")))
        entry[key] = to_res_path(dest)
    # normal_dx is only a fallback for the OpenGL-convention map
    if "normal" not in entry and "normal_dx" in entry:
        entry["normal"] = entry["normal_dx"]
    return entry


def fetch_hdri(slug: str, files: dict, res: str, out_root: str, jobs_out: list) -> str | None:
    node = files.get("hdri")
    if not isinstance(node, dict):
        return None
    picked = pick_resolution(node, res)
    if picked is None:
        return None
    res_used, fmt_node = picked
    file_entry = pick_format(fmt_node, PREFERRED_HDRI_FORMATS)
    if file_entry is None:
        return None
    ext = os.path.splitext(urllib.parse.urlparse(file_entry["url"]).path)[1] or ".hdr"
    dest = os.path.join(out_root, "hdris", f"{slug}_{res_used}{ext}")
    jobs_out.append((file_entry["url"], dest, file_entry.get("md5")))
    return to_res_path(dest)


def fetch_model(slug: str, files: dict, res: str, out_root: str, jobs_out: list) -> dict | None:
    node = files.get("gltf")
    if not isinstance(node, dict):
        return None
    picked = pick_resolution(node, res)
    if picked is None:
        return None
    _res_used, fmt_node = picked
    gltf = fmt_node.get("gltf")
    if not isinstance(gltf, dict) or "url" not in gltf:
        return None
    folder = os.path.join(out_root, "models", slug)
    main_name = os.path.basename(urllib.parse.urlparse(gltf["url"]).path)
    main_dest = os.path.join(folder, main_name)
    jobs_out.append((gltf["url"], main_dest, gltf.get("md5")))
    # .bin buffers and the texture set the glTF references, relative paths kept
    for rel, sub in (gltf.get("include") or {}).items():
        if not isinstance(sub, dict) or "url" not in sub:
            continue
        safe_rel = rel.replace("\\", "/").lstrip("/")
        jobs_out.append((sub["url"], os.path.join(folder, safe_rel), sub.get("md5")))
    return {"slug": slug, "kind": "model", "scene": to_res_path(main_dest)}


def to_res_path(path: str) -> str:
    norm = path.replace("\\", "/")
    idx = norm.find("assets/")
    return "res://" + norm[idx:] if idx >= 0 else norm


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

def run(args: argparse.Namespace) -> int:
    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)

    if args.list:
        assets = api_json(f"assets?t={args.list}")
        for slug in sorted(assets):
            info = assets[slug]
            print(f"{slug:44s} {info.get('name', '')}  [{', '.join(info.get('categories', []))}]")
        print(f"\n{len(assets)} {args.list} available on Poly Haven.")
        return 0

    manifest_path = os.path.join(out_root, "manifest.json")
    manifest = {"version": 1, "resolution": args.res, "textures": {}, "hdris": {}, "models": {}}
    if os.path.exists(manifest_path) and not args.fresh:
        try:
            manifest.update(json.load(open(manifest_path, encoding="utf-8")))
            manifest["resolution"] = args.res
        except (json.JSONDecodeError, OSError):
            pass

    textures = list(CURATED_TEXTURES) if "textures" in args.sets else []
    hdris = list(CURATED_HDRIS) if "hdris" in args.sets else []
    models = list(CURATED_MODELS) if "models" in args.sets else []

    if args.add:
        print(f"Resolving {len(args.add)} extra slug(s) against the API index...")
        index = {}
        for kind in ("textures", "hdris", "models"):
            try:
                index[kind] = api_json(f"assets?t={kind}")
            except RuntimeError as exc:
                print(f"  ! could not index {kind}: {exc}", file=sys.stderr)
                index[kind] = {}
        for slug in args.add:
            for kind, bucket in (("textures", textures), ("hdris", hdris), ("models", models)):
                if slug in index.get(kind, {}) and slug not in bucket:
                    bucket.append(slug)
                    print(f"  + {slug} ({kind})")
                    break
            else:
                print(f"  ? {slug} not found on Poly Haven — skipped", file=sys.stderr)

    jobs: list[tuple[str, str, str | None]] = []
    credits: list[tuple[str, str, str]] = []

    plan = [("textures", textures), ("hdris", hdris), ("models", models)]
    for kind, slugs in plan:
        for slug in slugs:
            print(f"[{kind}] {slug}")
            try:
                files = api_json(f"files/{slug}")
            except RuntimeError as exc:
                print(f"  ! {exc}", file=sys.stderr)
                continue
            if kind == "textures":
                entry = fetch_texture(slug, files, args.res, out_root, jobs)
                if len(entry) > 2:
                    manifest["textures"][slug] = entry
            elif kind == "hdris":
                path = fetch_hdri(slug, files, args.res, out_root, jobs)
                if path:
                    manifest["hdris"][slug] = path
            else:
                entry = fetch_model(slug, files, args.res, out_root, jobs)
                if entry:
                    manifest["models"][slug] = entry
            try:
                info = api_json(f"info/{slug}")
                authors = ", ".join((info.get("authors") or {}).keys())
                credits.append((slug, info.get("name", slug), authors))
            except RuntimeError:
                credits.append((slug, slug, "Poly Haven"))

    if not jobs:
        print("Nothing to download. Is the network reachable?", file=sys.stderr)
        return 1

    total_new = 0
    print(f"\nDownloading {len(jobs)} file(s) with {args.jobs} workers ...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(download, url, dest, md5): dest for url, dest, md5 in jobs}
        done = 0
        for future in concurrent.futures.as_completed(futures):
            dest = futures[future]
            done += 1
            try:
                fresh = future.result()
                total_new += 1 if fresh else 0
                state = "new " if fresh else "have"
            except Exception as exc:  # noqa: BLE001 - report and keep going
                state = "FAIL"
                print(f"  ! {dest}: {exc}", file=sys.stderr)
            print(f"  [{done:3d}/{len(jobs)}] {state} {os.path.relpath(dest, out_root)}")

    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent="\t", ensure_ascii=False, sort_keys=True)

    with open(os.path.join(out_root, "CREDITS.md"), "w", encoding="utf-8") as handle:
        handle.write("# Poly Haven assets\n\n")
        handle.write("All assets below are CC0 from https://polyhaven.com and were fetched\n")
        handle.write("automatically by `tools/fetch_polyhaven.py`.\n\n")
        handle.write("| Slug | Name | Author(s) |\n|---|---|---|\n")
        for slug, name, authors in sorted(credits):
            handle.write(f"| `{slug}` | {name} | {authors} |\n")

    print(f"\nDone. {total_new} new file(s). Manifest: {manifest_path}")
    print("Open the project in Godot once so the new files are imported,")
    print("then press 'Tune imports' in the Poly Haven dock (normal-map flags, roughness limiting).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--res", default="2k", choices=["1k", "2k", "4k", "8k"],
                        help="texture / HDRI resolution (default 2k; use 4k on the RTX 5080 rig)")
    parser.add_argument("--out", default=os.path.join("assets", "polyhaven"), help="output folder")
    parser.add_argument("--sets", default="textures,hdris,models",
                        help="comma list of textures,hdris,models")
    parser.add_argument("--add", action="append", default=[], help="extra Poly Haven slug (repeatable)")
    parser.add_argument("--jobs", type=int, default=8, help="parallel downloads")
    parser.add_argument("--list", choices=["textures", "hdris", "models"],
                        help="print the available assets of a type and exit")
    parser.add_argument("--fresh", action="store_true", help="ignore an existing manifest")
    args = parser.parse_args()
    args.sets = [s.strip() for s in args.sets.split(",") if s.strip()]
    try:
        return run(args)
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
