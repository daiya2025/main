#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""フルパイプライン一括実行: Poly Haven取得 → PLATEAU取得・変換 → (任意) デモMP4生成。

    py -3 tools\\run_all.py
    py -3 tools\\run_all.py --with-demo --godot "C:\\Godot\\Godot_v4.4.1-stable_win64.exe"
"""

import argparse
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent


def step(name: str, cmd: list[str]) -> bool:
    print(f"\n{'=' * 60}\n STEP: {name}\n{'=' * 60}")
    code = subprocess.call([sys.executable] + [str(c) for c in cmd])
    if code != 0:
        print(f"[warn] {name} が失敗しました (続行します)")
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--with-demo", action="store_true", help="最後に60秒デモMP4も生成")
    ap.add_argument("--godot", default=None)
    ap.add_argument("--radius", default="700")
    ap.add_argument("--hdri-res", default="4k")
    ap.add_argument("--tex-res", default="2k")
    args = ap.parse_args()

    ok_ph = step("Poly Haven アセット取得",
                 [TOOLS / "fetch_polyhaven.py", "--hdri-res", args.hdri_res, "--tex-res", args.tex_res])
    ok_pl = step("PLATEAU 渋谷駅周辺 取得・変換",
                 [TOOLS / "fetch_plateau.py", "--radius", args.radius])

    if args.with_demo:
        cmd = [TOOLS / "make_demo_mp4.py"]
        if args.godot:
            cmd += ["--godot", args.godot]
        step("60秒デモ MP4 生成", cmd)

    print("\n" + "=" * 60)
    print(f" Poly Haven: {'OK' if ok_ph else 'FAILED (ゲームはフォールバック品質で動作)'}")
    print(f" PLATEAU   : {'OK' if ok_pl else 'FAILED (ゲームは手続き生成の街で動作)'}")
    print(" 次: Godot 4.4 で game/project.godot を開き、F5 で実行")
    print("=" * 60)


if __name__ == "__main__":
    main()
