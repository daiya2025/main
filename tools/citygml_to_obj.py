#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PLATEAU CityGML (建築物 bldg) を Godot が読める OBJ + MTL + テクスチャに変換する。

対応:
- LOD2 (boundedBy の Wall/Roof/Ground/ClosureSurface, テクスチャ付き) を優先、無ければ LOD1 Solid
- app:ParameterizedTexture による外観テクスチャ (UV) を OBJ の vt として出力
- EPSG:6697 (JGD2011 緯度経度 + 標高) → 指定原点中心のローカル ENU 座標 [m]
  Godot 座標系: +X=東, +Y=上, +Z=南 (北= -Z)
- 任意多角形の耳刈り (ear clipping) 三角形分割

単体でも使える:
    py -3 tools\\citygml_to_obj.py input.gml --center 35.6595,139.7005 --out game/assets/city
"""

import argparse
import json
import math
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

WALL_TYPES = {"WallSurface", "OuterCeilingSurface", "ClosureSurface"}
ROOF_TYPES = {"RoofSurface"}
GROUND_TYPES = {"GroundSurface", "OuterFloorSurface"}


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def meters_per_degree(lat_deg: float) -> tuple[float, float]:
    """緯度・経度1度あたりのメートル (楕円体近似)。"""
    p = math.radians(lat_deg)
    m_lat = 111132.954 - 559.822 * math.cos(2 * p) + 1.175 * math.cos(4 * p)
    m_lon = 111412.84 * math.cos(p) - 93.5 * math.cos(3 * p) + 0.118 * math.cos(5 * p)
    return m_lat, m_lon


class Transformer:
    def __init__(self, lat0: float, lon0: float, h0: float = 0.0):
        self.lat0, self.lon0, self.h0 = lat0, lon0, h0
        self.m_lat, self.m_lon = meters_per_degree(lat0)

    def to_local(self, lat: float, lon: float, h: float) -> tuple[float, float, float]:
        x = (lon - self.lon0) * self.m_lon          # 東 = +X
        z = -(lat - self.lat0) * self.m_lat         # 北 = -Z
        y = h - self.h0
        return x, y, z


# ---------------------------------------------------------------- 三角形分割

def newell_normal(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1, z1 = pts[i]
        x2, y2, z2 = pts[(i + 1) % n]
        nx += (y1 - y2) * (z1 + z2)
        ny += (z1 - z2) * (x1 + x2)
        nz += (x1 - x2) * (y1 + y2)
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (nx / length, ny / length, nz / length)


def project_2d(pts, normal):
    ax, ay, az = (abs(normal[0]), abs(normal[1]), abs(normal[2]))
    if ax >= ay and ax >= az:
        uv = [(p[1], p[2]) for p in pts]
        flip = normal[0] < 0
    elif ay >= ax and ay >= az:
        uv = [(p[2], p[0]) for p in pts]
        flip = normal[1] < 0
    else:
        uv = [(p[0], p[1]) for p in pts]
        flip = normal[2] < 0
    if flip:
        uv = [(-u, v) for u, v in uv]
    return uv


def triangulate(pts3d) -> list[tuple[int, int, int]]:
    """耳刈り。返り値は元頂点インデックスの三角形リスト。"""
    n = len(pts3d)
    if n < 3:
        return []
    if n == 3:
        return [(0, 1, 2)]
    normal = newell_normal(pts3d)
    p2 = project_2d(pts3d, normal)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    area2 = sum(cross((0, 0), p2[i], p2[(i + 1) % n]) for i in range(n))
    idx = list(range(n))
    if area2 < 0:
        idx.reverse()

    def point_in_tri(p, a, b, c):
        d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
        return d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12

    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        m = len(idx)
        for k in range(m):
            i0, i1, i2 = idx[(k - 1) % m], idx[k], idx[(k + 1) % m]
            a, b, c = p2[i0], p2[i1], p2[i2]
            if cross(a, b, c) <= 1e-12:
                continue
            if any(point_in_tri(p2[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            found = True
            break
        if not found:  # 退化ポリゴン → 扇形分割にフォールバック
            for k in range(1, len(idx) - 1):
                tris.append((idx[0], idx[k], idx[k + 1]))
            return tris
    if len(idx) == 3:
        tris.append((idx[0], idx[1], idx[2]))
    return tris


# ---------------------------------------------------------------- CityGML パース

def parse_poslist(text: str):
    vals = text.split()
    pts = []
    for i in range(0, len(vals) - 2, 3):
        pts.append((float(vals[i]), float(vals[i + 1]), float(vals[i + 2])))
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts.pop()
    return pts


def gml_id(el) -> str:
    for k, v in el.attrib.items():
        if local(k) == "id":
            return v
    return ""


def extract_polygon(poly_el):
    """Polygon要素 → (poly_id, ring_id, pts[(lat,lon,h)]) / 内周リングは無視。"""
    pid = gml_id(poly_el)
    for child in poly_el:
        if local(child.tag) != "exterior":
            continue
        for ring in child:
            if local(ring.tag) != "LinearRing":
                continue
            rid = gml_id(ring)
            pts = []
            for e in ring:
                ln = local(e.tag)
                if ln == "posList" and e.text:
                    pts = parse_poslist(e.text)
                elif ln == "pos" and e.text:
                    v = [float(x) for x in e.text.split()]
                    if len(v) >= 3:
                        pts.append((v[0], v[1], v[2]))
            if len(pts) > 2 and pts[0] == pts[-1]:
                pts.pop()
            return pid, rid, pts
    return pid, "", []


def collect_building_polygons(bldg_el):
    """1棟から (surface_type, poly_id, ring_id, pts) を収集。LOD2優先、無ければLOD1。"""
    polys = []
    for bounded in bldg_el.iter():
        if local(bounded.tag) != "boundedBy":
            continue
        for surf in bounded:
            stype = local(surf.tag)
            if stype not in WALL_TYPES | ROOF_TYPES | GROUND_TYPES:
                continue
            kind = "roof" if stype in ROOF_TYPES else ("ground" if stype in GROUND_TYPES else "wall")
            for poly in surf.iter():
                if local(poly.tag) == "Polygon":
                    pid, rid, pts = extract_polygon(poly)
                    if len(pts) >= 3:
                        polys.append((kind, pid, rid, pts))
    if polys:
        return polys, 2
    # LOD1 フォールバック
    for solid_tag in ("lod1Solid", "lod2Solid"):
        for el in bldg_el.iter():
            if local(el.tag) != solid_tag:
                continue
            for poly in el.iter():
                if local(poly.tag) == "Polygon":
                    pid, rid, pts = extract_polygon(poly)
                    if len(pts) >= 3:
                        normal = newell_normal(pts)  # (lat,lon,h)空間だが上下判定には十分
                        kind = "roof" if normal[2] > 0.5 else ("ground" if normal[2] < -0.5 else "wall")
                        polys.append((kind, pid, rid, pts))
            if polys:
                return polys, 1
    return polys, 0


def collect_appearance(root):
    """ring_id -> (image_uri, [(u,v), ...])"""
    mapping = {}
    for el in root.iter():
        if local(el.tag) != "ParameterizedTexture":
            continue
        image_uri = None
        for c in el.iter():
            if local(c.tag) == "imageURI" and c.text:
                image_uri = c.text.strip()
                break
        if not image_uri:
            continue
        for target in el.iter():
            if local(target.tag) != "target":
                continue
            for tc in target.iter():
                if local(tc.tag) != "textureCoordinates" or not tc.text:
                    continue
                ring_ref = ""
                for k, v in tc.attrib.items():
                    if local(k) == "ring":
                        ring_ref = v.lstrip("#")
                vals = [float(x) for x in tc.text.split()]
                uvs = [(vals[i], vals[i + 1]) for i in range(0, len(vals) - 1, 2)]
                if ring_ref:
                    mapping[ring_ref] = (image_uri, uvs)
    return mapping


# ---------------------------------------------------------------- OBJ 書き出し

DEFAULT_MATERIALS = """
newmtl wall
Kd 0.780 0.760 0.740
Ks 0.04 0.04 0.04
Ns 12
newmtl roof
Kd 0.310 0.300 0.320
Ks 0.02 0.02 0.02
Ns 6
newmtl ground
Kd 0.240 0.235 0.230
Ns 4
"""


def sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", name)


def convert_gml(gml_path: Path, out_dir: Path, transformer: Transformer,
                radius_m: float | None = None) -> dict | None:
    """1つの .gml を OBJ に変換。radius_m 指定時は原点からの距離で建物をフィルタ。"""
    print(f"  parse: {gml_path.name}")
    try:
        tree = ET.parse(gml_path)
    except ET.ParseError as e:
        print(f"  [FAIL] XML parse error: {e}")
        return None
    root = tree.getroot()
    appearance = collect_appearance(root)

    out_dir.mkdir(parents=True, exist_ok=True)
    tex_out = out_dir / "textures"
    stem = sanitize(gml_path.stem)
    obj_path = out_dir / f"{stem}.obj"
    mtl_path = out_dir / f"{stem}.mtl"

    vertices, uvs, normals = [], [], []
    faces_by_mat: dict[str, list] = {}
    materials: dict[str, str | None] = {"wall": None, "roof": None, "ground": None}
    n_buildings = 0
    n_lod2 = 0

    for member in root:
        if local(member.tag) != "cityObjectMember":
            continue
        for bldg in member:
            if local(bldg.tag) != "Building":
                continue
            polys, lod = collect_building_polygons(bldg)
            if not polys:
                continue
            if radius_m is not None:
                lat, lon, _ = polys[0][3][0]
                x, _, z = transformer.to_local(lat, lon, 0)
                if math.sqrt(x * x + z * z) > radius_m:
                    continue
            n_buildings += 1
            if lod >= 2:
                n_lod2 += 1
            for kind, _pid, rid, pts in polys:
                tex = appearance.get(rid)
                local_pts = [transformer.to_local(la, lo, h) for (la, lo, h) in pts]
                tris = triangulate(local_pts)
                if not tris:
                    continue
                ring_uvs = None
                if tex:
                    image_uri, ring_uvs = tex
                    if len(ring_uvs) == len(pts) + 1:
                        ring_uvs = ring_uvs[:-1]
                    if len(ring_uvs) != len(pts):
                        ring_uvs = None
                if ring_uvs is not None:
                    mat = "tex_" + sanitize(Path(image_uri).stem)
                    if mat not in materials:
                        src = (gml_path.parent / image_uri).resolve()
                        rel_dest = None
                        if src.exists():
                            tex_out.mkdir(parents=True, exist_ok=True)
                            dest = tex_out / sanitize(Path(image_uri).name)
                            if not dest.exists():
                                shutil.copy2(src, dest)
                            rel_dest = f"textures/{dest.name}"
                        materials[mat] = rel_dest
                    if materials[mat] is None:
                        mat = kind
                        ring_uvs = None
                else:
                    mat = kind
                base_v = len(vertices)
                vertices.extend(local_pts)
                nrm = newell_normal(local_pts)
                normals.append(nrm)
                ni = len(normals)
                if ring_uvs is not None:
                    base_t = len(uvs)
                    uvs.extend(ring_uvs)
                    for (a, b, c) in tris:
                        faces_by_mat.setdefault(mat, []).append(
                            (base_v + a + 1, base_t + a + 1, ni,
                             base_v + b + 1, base_t + b + 1, ni,
                             base_v + c + 1, base_t + c + 1, ni, True))
                else:
                    for (a, b, c) in tris:
                        faces_by_mat.setdefault(mat, []).append(
                            (base_v + a + 1, 0, ni, base_v + b + 1, 0, ni, base_v + c + 1, 0, ni, False))

    if not vertices:
        print("  [skip] 対象範囲内に建物なし")
        return None

    with open(mtl_path, "w", encoding="utf-8") as f:
        f.write("# PLATEAU -> OBJ (tools/citygml_to_obj.py)\n")
        f.write(DEFAULT_MATERIALS)
        for mat, tex_rel in materials.items():
            if mat in ("wall", "roof", "ground") or tex_rel is None:
                continue
            f.write(f"\nnewmtl {mat}\nKd 1 1 1\nKs 0.05 0.05 0.05\nNs 16\nmap_Kd {tex_rel}\n")

    n_tris = 0
    with open(obj_path, "w", encoding="utf-8") as f:
        f.write(f"# PLATEAU {gml_path.name} -> OBJ\n")
        f.write(f"mtllib {mtl_path.name}\n")
        for (x, y, z) in vertices:
            f.write(f"v {x:.3f} {y:.3f} {z:.3f}\n")
        for (u, v) in uvs:
            f.write(f"vt {u:.5f} {v:.5f}\n")
        for (x, y, z) in normals:
            f.write(f"vn {x:.4f} {y:.4f} {z:.4f}\n")
        for mat, faces in faces_by_mat.items():
            f.write(f"usemtl {mat}\n")
            for fc in faces:
                a_v, a_t, a_n, b_v, b_t, b_n, c_v, c_t, c_n, has_uv = fc
                if has_uv:
                    f.write(f"f {a_v}/{a_t}/{a_n} {b_v}/{b_t}/{b_n} {c_v}/{c_t}/{c_n}\n")
                else:
                    f.write(f"f {a_v}//{a_n} {b_v}//{b_n} {c_v}//{c_n}\n")
                n_tris += 1

    print(f"  -> {obj_path.name}: 建物 {n_buildings} 棟 (LOD2 {n_lod2}) / {n_tris} tris")
    return {"obj": obj_path.name, "buildings": n_buildings, "lod2": n_lod2, "tris": n_tris}


def main():
    ap = argparse.ArgumentParser(description="CityGML -> OBJ 変換")
    ap.add_argument("gml", nargs="+", help="入力 .gml ファイル")
    ap.add_argument("--center", default="35.6595,139.7005", help="原点 lat,lon (渋谷スクランブル交差点)")
    ap.add_argument("--radius", type=float, default=None, help="この半径[m]内の建物のみ出力")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "game" / "assets" / "city"))
    args = ap.parse_args()

    lat0, lon0 = (float(x) for x in args.center.split(","))
    tr = Transformer(lat0, lon0)
    out_dir = Path(args.out)
    entries = []
    for g in args.gml:
        info = convert_gml(Path(g), out_dir, tr, args.radius)
        if info:
            entries.append(info)
    manifest = {"center": [lat0, lon0], "files": entries}
    (out_dir / "city_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"city_manifest.json 書き出し ({len(entries)} ファイル)")
    if not entries:
        sys.exit(1)


if __name__ == "__main__":
    main()
