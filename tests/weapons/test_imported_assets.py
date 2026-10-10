import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("asset_importer", ROOT / "bin" / "import_assets.py")
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class ImportedAssetsTests(unittest.TestCase):
    def test_unified_owned_payloads_and_sources(self):
        manifest = json.loads((ROOT / "content" / "data_static" / "imported_assets.json").read_text())
        self.assertEqual({source["package"] for source in manifest["sources"]},
                         {"cs16", "hammer", "machete", "spanner", "lewis", "hev"})
        owned = {entry["path"] for entry in manifest["files"]}
        for source in manifest["sources"]:
            self.assertTrue(source["title"])
            self.assertTrue(source["permission"])
            self.assertIsInstance(source["creditFiles"], list)
            self.assertEqual(bool(source["creditFiles"]), source["package"] in ("cs16", "machete"))
            for path in source["creditFiles"]:
                self.assertIn(path, owned)
                self.assertTrue((ROOT / "content" / Path(path)).read_text().strip())
        for entry in manifest["files"]:
            body = (ROOT / "content" / Path(entry["path"])).read_bytes()
            self.assertEqual(len(body), entry["bytes"], entry["path"])
            self.assertEqual(hashlib.sha256(body).hexdigest(), entry["sha256"], entry["path"])
            self.assertNotIn(Path(entry["path"]).suffix, (".lua", ".vpk", ".exe"))
        self.assertGreater(manifest["hammerWorldTriangles"], 1000)

    def test_models_have_companions_and_material_directories(self):
        for path in (ROOT / "content" / "models" / "zombiesim" / "imported").rglob("*.mdl"):
            with self.subTest(model=path):
                self.assertTrue(path.with_suffix(".vvd").is_file())
                self.assertTrue(path.with_suffix(".dx90.vtx").is_file())
                body = path.read_bytes()
                self.assertEqual(struct.unpack_from("<i", body, 76)[0], len(body))
                count, offset = struct.unpack_from("<ii", body, 212)
                directories = [importer.cstring(body, struct.unpack_from("<i", body, offset + i * 4)[0])
                               for i in range(count)]
                self.assertTrue(any(directory.replace("\\", "/").startswith("zombiesim/imported/") for directory in directories))

    def test_texture_relocation_includes_unquoted_keys(self):
        source = b'"VertexLitGeneric" { $phongexponenttexture "models\\test\\mask" "$basetexture" "models/test/base" "$envmap" "env_cubemap" }'
        result = importer.relocate_material(source, "test", {"models/test/mask.vtf", "models/test/base.vtf"})
        self.assertIn(b'zombiesim/imported/test/models/test/mask', result)
        self.assertIn(b'zombiesim/imported/test/models/test/base', result)
        self.assertIn(b'"env_cubemap"', result)
        for path in (ROOT / "content" / "materials" / "zombiesim" / "imported").rglob("*.vmt"):
            for texture in re.findall(r'"(zombiesim/imported/[^"]+)"', path.read_text(errors="replace")):
                self.assertTrue((ROOT / "content" / "materials" / (texture + ".vtf")).exists(), str(path))

    def test_retained_cs16_verification_and_unsafe_paths(self):
        previous = json.loads((ROOT / "content" / "data_static" / "imported_assets.json").read_text())
        files, source = importer.cs16_assets(ROOT, previous)
        self.assertEqual(len(files), 1609)
        self.assertEqual(source["workshopId"], "2657591603")
        for path in ("../outside.mdl", "C:/outside.mdl", "/outside.mdl"):
            with self.assertRaises(ValueError):
                importer.safe_path(path)


if __name__ == "__main__":
    unittest.main()
