#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""60秒シネマティックデモを MP4 (H.264) で書き出す。

Godot の Movie Maker モード (--write-movie) で 60fps 固定レンダリングした AVI (MJPEG) を
ffmpeg で高品質 MP4 に変換する。ゲーム側は movie モードを検知すると自動で
DemoDirector (60秒カメラワーク) が起動し、60秒経過で自動終了する。

使い方 (Windows / RTX 5080 推奨):
    py -3 tools\\make_demo_mp4.py --godot "C:\\Godot\\Godot_v4.4.1-stable_win64.exe"
    py -3 tools\\make_demo_mp4.py --resolution 3840x2160 --preset night

ffmpeg が無い場合:  winget install Gyan.FFmpeg
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_DIR = REPO_ROOT / "game"
OUTPUT_DIR = REPO_ROOT / "output"


def find_godot(cli_arg: str | None) -> str | None:
    candidates = [cli_arg, os.environ.get("GODOT")]
    candidates += ["godot", "godot4", "Godot_v4.4.1-stable_win64.exe"]
    for c in candidates:
        if not c:
            continue
        path = shutil.which(c) or (c if Path(c).exists() else None)
        if path:
            return path
    return None


def run(cmd: list[str], **kw) -> int:
    print("  $ " + " ".join(str(c) for c in cmd))
    return subprocess.call([str(c) for c in cmd], **kw)


def main():
    ap = argparse.ArgumentParser(description="60秒デモ MP4 生成")
    ap.add_argument("--godot", default=None, help="Godot 実行ファイルのパス")
    ap.add_argument("--resolution", default="1920x1080", help="例: 1920x1080 / 3840x2160")
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--preset", default="night", choices=["night", "dusk", "day"],
                    help="ライティングプリセット (既定: night = 渋谷の夜)")
    ap.add_argument("--crf", type=int, default=16, help="x264 品質 (小さいほど高品質)")
    ap.add_argument("--keep-raw", action="store_true", help="中間AVIを残す")
    ap.add_argument("--skip-render", action="store_true", help="既存AVIから変換のみ")
    args = ap.parse_args()

    godot = find_godot(args.godot)
    if not godot and not args.skip_render:
        print("[FAIL] Godot が見つかりません。--godot でパスを指定するか、環境変数 GODOT を設定してください。")
        print("       DL: https://godotengine.org/download/windows/")
        sys.exit(1)

    OUTPUT_DIR.mkdir(exist_ok=True)
    raw_avi = OUTPUT_DIR / "demo_raw.avi"
    mp4_out = OUTPUT_DIR / f"shibuya_rift_demo_{args.preset}_{args.resolution}.mp4"

    if not args.skip_render:
        print("=== 1/3 アセットインポート (初回は数分かかります) ===")
        run([godot, "--path", GAME_DIR, "--headless", "--import"])

        print(f"\n=== 2/3 Movie Maker レンダリング ({args.resolution} {args.fps}fps, 60秒 = {args.fps * 60} フレーム) ===")
        print("  リアルタイムではなく1フレームずつ確定レンダリングするため、実時間より長くかかります。")
        code = run([
            godot, "--path", GAME_DIR,
            "--write-movie", raw_avi,
            "--fixed-fps", args.fps,
            "--resolution", args.resolution,
            "--", f"--preset={args.preset}", "--demo",
        ])
        if code != 0 or not raw_avi.exists():
            print("[FAIL] レンダリングに失敗しました。")
            sys.exit(1)

    if not raw_avi.exists():
        print(f"[FAIL] {raw_avi} がありません。--skip-render を外して実行してください。")
        sys.exit(1)

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("[FAIL] ffmpeg が見つかりません。 winget install Gyan.FFmpeg でインストールしてください。")
        print(f"       中間ファイルはあります: {raw_avi}")
        sys.exit(1)

    print("\n=== 3/3 MP4 変換 (H.264, yuv420p) ===")
    code = run([
        ffmpeg, "-y", "-i", raw_avi,
        "-c:v", "libx264", "-preset", "slow", "-crf", args.crf,
        "-c:a", "aac", "-b:a", "192k",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        "-t", "60",
        mp4_out,
    ])
    if code != 0:
        sys.exit(1)
    if not args.keep_raw:
        raw_avi.unlink(missing_ok=True)
    size_mb = mp4_out.stat().st_size / 1e6
    print(f"\n完成: {mp4_out} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
