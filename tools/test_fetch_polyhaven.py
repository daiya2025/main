#!/usr/bin/env python3
"""Offline tests for the Poly Haven fetcher's response parsing.

The download itself needs the network, but the part that can silently go wrong
is the shape of the /files/<slug> tree: which map keys exist, how resolutions
nest, and which format to prefer. These fixtures mirror the real API responses
so a change in the parser is caught without hitting polyhaven.com.

    python tools/test_fetch_polyhaven.py
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fetch_polyhaven as fp  # noqa: E402


def _file(url: str) -> dict:
    return {"url": url, "md5": "0" * 32, "size": 1234}


# Trimmed but structurally faithful /files/rock_ground response.
TEXTURE_FILES = {
    "blend": {"4k": {"blend": _file("https://dl.polyhaven.org/x/rock_ground_4k.blend")}},
    "gltf": {"4k": {"gltf": _file("https://dl.polyhaven.org/x/rock_ground_4k.gltf")}},
    "Diffuse": {
        "1k": {"jpg": _file("https://dl.polyhaven.org/x/rock_ground_diff_1k.jpg"),
               "png": _file("https://dl.polyhaven.org/x/rock_ground_diff_1k.png")},
        "2k": {"jpg": _file("https://dl.polyhaven.org/x/rock_ground_diff_2k.jpg")},
        "4k": {"jpg": _file("https://dl.polyhaven.org/x/rock_ground_diff_4k.jpg")},
    },
    "nor_gl": {"2k": {"exr": _file("https://dl.polyhaven.org/x/rock_ground_nor_gl_2k.exr")}},
    "nor_dx": {"2k": {"exr": _file("https://dl.polyhaven.org/x/rock_ground_nor_dx_2k.exr")}},
    "Rough": {"2k": {"exr": _file("https://dl.polyhaven.org/x/rock_ground_rough_2k.exr")}},
    "AO": {"2k": {"jpg": _file("https://dl.polyhaven.org/x/rock_ground_ao_2k.jpg")}},
    "Displacement": {"2k": {"png": _file("https://dl.polyhaven.org/x/rock_ground_disp_2k.png")}},
    "arm": {"2k": {"jpg": _file("https://dl.polyhaven.org/x/rock_ground_arm_2k.jpg")}},
}

HDRI_FILES = {
    "hdri": {
        "1k": {"hdr": _file("https://dl.polyhaven.org/x/kloppenheim_1k.hdr"),
               "exr": _file("https://dl.polyhaven.org/x/kloppenheim_1k.exr")},
        "4k": {"hdr": _file("https://dl.polyhaven.org/x/kloppenheim_4k.hdr")},
    },
    "tonemapped": {"jpg": _file("https://dl.polyhaven.org/x/kloppenheim.jpg")},
}

MODEL_FILES = {
    "gltf": {
        "2k": {
            "gltf": {
                "url": "https://dl.polyhaven.org/x/tree_small_02_2k.gltf",
                "md5": "0" * 32,
                "include": {
                    "tree_small_02_2k.bin": _file("https://dl.polyhaven.org/x/tree_small_02_2k.bin"),
                    "textures/tree_small_02_diff_2k.jpg":
                        _file("https://dl.polyhaven.org/x/textures/tree_small_02_diff_2k.jpg"),
                },
            }
        }
    },
    "blend": {"2k": {"blend": _file("https://dl.polyhaven.org/x/tree_small_02_2k.blend")}},
}


class TextureParsing(unittest.TestCase):
    def setUp(self) -> None:
        self.jobs: list = []
        self.entry = fp.fetch_texture("rock_ground", TEXTURE_FILES, "2k", "assets/polyhaven", self.jobs)

    def test_maps_are_normalised(self) -> None:
        for key in ("diffuse", "normal", "rough", "ao", "disp", "arm"):
            self.assertIn(key, self.entry, f"missing {key} in {sorted(self.entry)}")

    def test_blend_and_gltf_are_not_downloaded_for_textures(self) -> None:
        urls = " ".join(url for url, _dest, _md5 in self.jobs)
        self.assertNotIn(".blend", urls)
        self.assertNotIn(".gltf", urls)

    def test_requested_resolution_wins(self) -> None:
        self.assertIn("_2k", self.entry["diffuse"])

    def test_opengl_normal_preferred_over_directx(self) -> None:
        self.assertIn("_normal_", self.entry["normal"])
        self.assertNotIn("_normal_dx_", self.entry["normal"])

    def test_jpg_preferred_when_several_formats_exist(self) -> None:
        self.assertTrue(self.entry["diffuse"].endswith(".jpg"))

    def test_paths_are_res_relative(self) -> None:
        self.assertTrue(self.entry["diffuse"].startswith("res://assets/polyhaven/"))

    def test_every_map_has_a_download_job(self) -> None:
        maps = [k for k in self.entry if k not in ("slug", "kind")]
        # normal is aliased from nor_gl, so jobs == distinct files
        self.assertGreaterEqual(len(self.jobs), len(maps) - 1)

    def test_missing_resolution_falls_back(self) -> None:
        jobs: list = []
        entry = fp.fetch_texture("rock_ground", TEXTURE_FILES, "8k", "assets/polyhaven", jobs)
        self.assertIn("diffuse", entry)
        self.assertTrue(len(jobs) > 0)

    def test_directx_only_asset_still_yields_a_normal(self) -> None:
        files = {k: v for k, v in TEXTURE_FILES.items() if k != "nor_gl"}
        entry = fp.fetch_texture("x", files, "2k", "assets/polyhaven", [])
        self.assertIn("normal", entry)
        self.assertIn("_normal_dx_", entry["normal"])


class HdriParsing(unittest.TestCase):
    def test_hdr_preferred_and_resolution_respected(self) -> None:
        jobs: list = []
        path = fp.fetch_hdri("kloppenheim", HDRI_FILES, "4k", "assets/polyhaven", jobs)
        self.assertIsNotNone(path)
        self.assertTrue(path.endswith("_4k.hdr"), path)
        self.assertEqual(len(jobs), 1)

    def test_tonemapped_jpg_is_ignored(self) -> None:
        jobs: list = []
        fp.fetch_hdri("kloppenheim", HDRI_FILES, "1k", "assets/polyhaven", jobs)
        self.assertNotIn(".jpg", jobs[0][0])

    def test_asset_without_hdri_branch_returns_none(self) -> None:
        self.assertIsNone(fp.fetch_hdri("x", {"tonemapped": {}}, "2k", "assets/polyhaven", []))


class ModelParsing(unittest.TestCase):
    def setUp(self) -> None:
        self.jobs: list = []
        self.entry = fp.fetch_model("tree_small_02", MODEL_FILES, "2k", "assets/polyhaven", self.jobs)

    def test_scene_points_at_the_gltf(self) -> None:
        self.assertTrue(self.entry["scene"].endswith(".gltf"))

    def test_buffers_and_textures_are_included(self) -> None:
        destinations = [dest.replace("\\", "/") for _url, dest, _md5 in self.jobs]
        self.assertTrue(any(d.endswith("tree_small_02_2k.bin") for d in destinations))
        self.assertTrue(any(d.endswith("textures/tree_small_02_diff_2k.jpg") for d in destinations),
                        "glTF texture paths must keep their relative folder")

    def test_model_without_gltf_is_skipped(self) -> None:
        self.assertIsNone(fp.fetch_model("x", {"blend": {}}, "2k", "assets/polyhaven", []))


class PathHelpers(unittest.TestCase):
    def test_to_res_path_handles_absolute_paths(self) -> None:
        self.assertEqual(
            fp.to_res_path("/home/user/main/assets/polyhaven/textures/a/b.jpg"),
            "res://assets/polyhaven/textures/a/b.jpg")

    def test_curated_slugs_match_the_gdscript_roles(self) -> None:
        # A slug renamed in only one of the two places silently disables the role.
        role_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                                 "src", "core", "asset_library.gd")
        with open(role_file, encoding="utf-8") as handle:
            gd = handle.read()
        missing = [slug for slug in fp.CURATED_TEXTURES if f'"{slug}"' not in gd]
        self.assertEqual(missing, [], f"slugs fetched but never referenced by a role: {missing}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
