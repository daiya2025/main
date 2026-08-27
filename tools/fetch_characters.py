#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""リグ+スケルタルアニメーション付きの既存3Dキャラクターモデルを自動取得する。

1. Godette (Godot 公式 TPS デモのロボット) — 約39,000頂点 / 4K PBR (albedo+ORM+normal+emissive)
   / 55 アニメーション (idle, walk, run, jump 4段階, flinch, lean ...)
   (c) Juan Linietsky, Fernando Miguel Calabró — CC-BY 3.0
2. Mannequiny (GDQuest) — リグ + 10 アニメーション (idle/run/dash/jump/punch/kick)
   (c) GDQuest — CC-BY 4.0

すべて GitHub の raw コンテンツから取得するため、追加の認証は不要。
取得先: game/assets/characters/  (Godot 側の CharacterRig.gd が自動検出する)

使い方:
    py -3 tools\\fetch_characters.py
"""

import json
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT = REPO_ROOT / "game" / "assets" / "characters"
UA = {"User-Agent": "shibuya-rift-character-fetcher/1.0"}

RAW_TPS = "https://raw.githubusercontent.com/godotengine/tps-demo/master"
RAW_MANNEQUIN = "https://raw.githubusercontent.com/gdquest-demos/godot-3d-mannequin/master"

FILES = {
    # Godette: glb本体 + PBRテクスチャ4枚
    "godette/godette.glb": f"{RAW_TPS}/player/model/player.glb",
    "godette/textures/player_robot_albedo.png": f"{RAW_TPS}/player/textures/player_robot_albedo.png",
    "godette/textures/player_robot_orm.png": f"{RAW_TPS}/player/textures/player_robot_orm.png",
    "godette/textures/player_robot_normal.png": f"{RAW_TPS}/player/textures/player_robot_normal.png",
    "godette/textures/player_robot_emissive.png": f"{RAW_TPS}/player/textures/player_robot_emissive.png",
    # Mannequiny (フォールバック / 軽量)
    "mannequiny/mannequiny.glb": f"{RAW_MANNEQUIN}/godot/assets/3d/mannequiny/mannequiny-0.3.0.glb",
}

CREDITS = """このフォルダのキャラクターアセットの出典:
- godette/    : Godot TPS Demo (c) Juan Linietsky, Fernando Miguel Calabró - CC-BY 3.0
                https://github.com/godotengine/tps-demo
- mannequiny/ : Mannequiny (c) GDQuest and contributors - CC-BY 4.0
                https://github.com/gdquest-demos/godot-3d-mannequin
"""


def download(url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        print(f"  [skip] {dest.relative_to(REPO_ROOT)}")
        return True
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
                while True:
                    chunk = r.read(1 << 18)
                    if not chunk:
                        break
                    f.write(chunk)
            print(f"  [done] {dest.relative_to(REPO_ROOT)} ({dest.stat().st_size / 1e6:.1f} MB)")
            return True
        except Exception as e:  # noqa: BLE001
            print(f"  [retry {i + 1}] {url}: {e}")
            time.sleep(2 ** i)
    print(f"  [FAIL] {url}")
    return False


def main():
    print("=== キャラクターモデル取得 (GitHub raw) ===")
    ok = {}
    for rel, url in FILES.items():
        ok[rel] = download(url, OUT / rel)
    (OUT / "CREDITS.txt").write_text(CREDITS, encoding="utf-8")

    manifest = {
        "godette": bool(ok.get("godette/godette.glb")),
        "mannequiny": bool(ok.get("mannequiny/mannequiny.glb")),
    }
    (OUT / "characters_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"\ngodette: {manifest['godette']} / mannequiny: {manifest['mannequiny']}")
    print("Godot エディタを一度開き直すとインポートされます。")


if __name__ == "__main__":
    main()
