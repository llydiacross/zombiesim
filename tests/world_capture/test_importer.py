"""Offline importer checks with isolated, repository-owned artifacts only."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import unittest
from uuid import uuid4

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("world_capture_importer", ROOT / "bin" / "import_world_captures.py")
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "generated" / "world_capture_tests" / ("import_" + uuid4().hex)
        self.root.mkdir(parents=True)
        self.world = {"world": {
            "profileId": "preview", "grid": [2, 2], "gridOrigin": [0, 0],
            "mapManifestSha256": "a" * 64, "templatePlanSha256": "b" * 64,
            "cellBounds": {"revision": 2, "neighbourPitch": 5760, "playableCeiling": 4608},
        }, "cells": [{"id": i, "map": "shared_recipe"} for i in range(4)]}
        self.skyline = {"profile": "preview", "templatePlanSha256": "b" * 64,
                        "cellSpan": 5760, "scale": 16, "cellBounds": {"revision": 2}, "cameraOrigin": [0, 0, 5120]}
        skyline_raw = json.dumps(self.skyline).encode()
        self.skyline_sha256 = hashlib.sha256(skyline_raw).hexdigest()
        (self.root / "zombiesim_skybox_preview.json").write_bytes(skyline_raw)
        revision = importer.expected_revision(self.world["world"], self.skyline,
                                             self.skyline_sha256)
        self.run = {
            "schemaVersion": 1, "runId": "test_run", "active": False,
            "restorationVerified": True, "revision": revision,
            "queue": [{"id": i, "x": i % 2, "y": i // 2, "worldX": i % 2,
                       "worldY": i // 2, "map": "shared_recipe"} for i in range(4)],
            "results": {"clear": {}, "atmospheric": {}},
        }
        colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]
        for variant in importer.VARIANTS:
            for i, color in enumerate(colors):
                relative = f"zombiesim/world_captures/test_run/{variant}/cell_{i}.png"
                path = self.root.joinpath(*relative.split("/"))
                path.parent.mkdir(parents=True, exist_ok=True)
                image = Image.new("RGB", (1024, 1024), color)
                image.putpixel((0, 0), (0, 0, 0))
                # Enough detail for the blank-buffer gate without changing the center colour.
                for x in range(64):
                    for y in range(64):
                        image.putpixel((x, y), (255 - color[0], 255 - color[1], 255 - color[2]))
                image.save(path)
                raw = path.read_bytes()
                self.run["results"][variant][str(i)] = {
                    "cellId": i, "variant": variant, "runId": "test_run",
                    "path": relative, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
                    "ok": True, "ready": True, "revision": revision,
                    "map": "shared_recipe",
                }
        self.run_path, self.world_path = self.root / "run.json", self.root / "world.json"
        self.write()

    def tearDown(self):
        shutil.rmtree(self.root)

    def write(self):
        self.run_path.write_text(json.dumps(self.run))
        self.world_path.write_text(json.dumps(self.world))

    def test_full_manifest_has_both_variants_north_up_small_tiles_and_budget(self):
        manifest = importer.import_run(self.run_path, self.world_path, self.root, self.root / "output")
        self.assertTrue(manifest["complete"])
        self.assertEqual(manifest["tileSize"], 256)
        self.assertLess(manifest["estimatedRGBABytes"], 384 * 1024 ** 2)
        with Image.open(self.root / "output" / "materials" / manifest["variants"]["clear"]["atlas"]) as atlas:
            self.assertEqual(atlas.getpixel((768, 768)), (255, 0, 0))
            self.assertEqual(atlas.getpixel((2304, 768)), (0, 255, 0))
            self.assertEqual(atlas.getpixel((768, 2304)), (0, 0, 255))
        self.assertEqual(len(manifest["ownedFiles"]), 10)

    def test_partial_pilot_never_enables_satellite(self):
        del self.run["results"]["atmospheric"]["3"]
        self.write()
        manifest = importer.import_run(self.run_path, self.world_path, self.root, self.root / "output")
        self.assertFalse(manifest["complete"])
        self.assertFalse(manifest["variants"]["atmospheric"]["complete"])
        self.assertTrue(manifest["variants"]["clear"]["complete"])

    def test_hashes_identity_checksum_readiness_and_restoration_are_fail_closed(self):
        mutations = [
            lambda r: r["revision"].update(templatePlanSha256="c" * 64),
            lambda r: r["revision"].update(skylineManifestSha256="d" * 64),
            lambda r: r["revision"].update(captureVersion=2),
            lambda r: r.update(active=True),
            lambda r: r.update(restorationVerified=False),
            lambda r: r["results"]["clear"]["0"].update(path="../escape.png"),
            lambda r: r["results"]["clear"]["0"].update(sha256="wrong"),
            lambda r: r["results"]["clear"]["0"].update(ready=False),
            lambda r: r["queue"][0].update(x=1),
        ]
        for mutate in mutations:
            run = copy.deepcopy(self.run)
            mutate(run)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                importer.validate(run, self.world, self.root, self.skyline, self.skyline_sha256)
        self.assertFalse((self.root / "output").exists())

    def test_blank_png_is_not_accepted_even_with_correct_hash(self):
        result = self.run["results"]["clear"]["0"]
        path = self.root.joinpath(*result["path"].split("/"))
        Image.new("RGB", (1024, 1024), (0, 0, 0)).save(path)
        raw = path.read_bytes()
        result.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        with self.assertRaisesRegex(ValueError, "blank"):
            importer.validate(self.run, self.world, self.root, self.skyline, self.skyline_sha256)

    def test_large_display_choices_are_bounded(self):
        with self.assertRaises(ValueError):
            importer.import_run(self.run_path, self.world_path, self.root, self.root / "output", tile_size=2048)
        with self.assertRaises(ValueError):
            importer.import_run(self.run_path, self.world_path, self.root, self.root / "output", overview_size=8192)


if __name__ == "__main__":
    unittest.main()
