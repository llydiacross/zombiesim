"""Check view migration and captured-world compatibility without engine mocks."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner


class CatalogTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[2] / "gamemode"
        self.runner = FixtureRunner(root, ["cl_world_map_catalog.lua"])
        self.catalog = self.runner.load("cl_world_map_catalog.lua")()
        self.lua = self.runner.lua

    def test_migration_preserves_other_modes_and_is_idempotent(self):
        check = self.lua.eval("""
        function(catalog)
            for _, old in ipairs({"default", "satellite", "walker", "map", "wireframe"}) do
                local values = {p_render_mode=old, zombiesim_world_map_layer_satellite_metro="1"}
                local store = {
                    GetString=function(key, fallback) return values[key] or fallback end,
                    Set=function(key, value) values[key]=value end
                }
                catalog.MigratePreferences(store, "p_", {{id="metro"}})
                assert(values.p_render_mode == ((old=="default" or old=="satellite") and "atlas" or old))
                assert(values.zombiesim_world_map_layer_atlas_metro=="1")
                values.p_render_mode="satellite"
                values.zombiesim_world_map_layer_atlas_metro="0"
                catalog.MigratePreferences(store, "p_", {{id="metro"}})
                assert(values.p_render_mode=="satellite" and values.zombiesim_world_map_layer_atlas_metro=="0")
            end
        end
        """)
        check(self.catalog)

    def test_manifest_requires_complete_matching_cells_and_safe_paths(self):
        check = self.lua.eval("""
        function(catalog)
            local world={world={mapManifestSha256="maps",templatePlanSha256="plan"},cells={{id=0},{id=1}}}
            local manifest={schemaVersion=1,profile="preview",complete=true,
                mapManifestSha256="maps",templatePlanSha256="plan",
                variants={clear={complete=true,atlas="worlds/preview/captured/clear/overview.png",
                    cells={["0"]="worlds/preview/captured/clear/cell_0.png",
                        ["1"]="worlds/preview/captured/clear/cell_1.png"}}}}
            assert(catalog.Validate(manifest,"preview",world).clear)
            manifest.complete=false
            assert(catalog.Validate(manifest,"preview",world)==nil)
            manifest.complete=true
            manifest.templatePlanSha256="stale"
            assert(catalog.Validate(manifest,"preview",world)==nil)
            manifest.templatePlanSha256="plan"
            assert(catalog.Validate(manifest,"city",world)==nil)
            manifest.variants.clear.cells["1"]=nil
            assert(catalog.Validate(manifest,"preview",world)==nil)
            manifest.variants.clear.cells["1"]="worlds/preview/captured/../cell_1.png"
            assert(catalog.Validate(manifest,"preview",world)==nil)
            manifest.variants.clear.cells["1"]="worlds/preview/captured/clear/cell_1.png"
            manifest.variants.clear.complete=false
            assert(catalog.Validate(manifest,"preview",world)==nil)
        end
        """)
        check(self.catalog)


if __name__ == "__main__":
    unittest.main()
