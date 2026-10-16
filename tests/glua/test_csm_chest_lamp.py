"""CSM shadow gating for the local F-toggle chest lamp."""

from pathlib import Path
import unittest

from tests.glua.harness import FixtureRunner, lua_source


ROOT = Path(__file__).resolve().parents[2]


class CSMChestLampTests(unittest.TestCase):
    def test_local_lamp_shadow_gate(self):
        runner = FixtureRunner(
            ROOT,
            ["gamemode/utils/test_harness.lua", "gamemode/tests/cl_chest_lamp_tests.lua"],
        )
        runner.lua.execute("""
            ZM_ChestLamp = {}
            istable = function(value) return type(value) == "table" end
            isfunction = function(value) return type(value) == "function" end
            concommand = {
                Add = function() end,
                Remove = function() end
            }
        """)

        source = lua_source(ROOT / "gamemode/cl_chest_lamp.lua")
        start = source.index("local function ShouldShadowOwner")
        end = source.index("\nChestLamp.ShouldShadowOwner = ShouldShadowOwner", start)
        runner.lua.execute(
            "local ChestLamp = ZM_ChestLamp\n"
            + source[start:end]
            + "\nChestLamp.ShouldShadowOwner = ShouldShadowOwner"
        )

        runner.load("gamemode/utils/test_harness.lua")
        suite = runner.load("gamemode/tests/cl_chest_lamp_tests.lua")
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "CSM chest lamp shadows")

    def test_sun_shadow_anchor_uses_player_entity_position(self):
        runner = FixtureRunner(
            ROOT,
            ["gamemode/utils/test_harness.lua", "gamemode/tests/cl_csm_tests.lua"],
        )
        runner.lua.execute("""
            local vectorMeta = {}
            vectorMeta.__index = {
                DistToSqr = function(self, other)
                    return (self.x - other.x)^2 + (self.y - other.y)^2 + (self.z - other.z)^2
                end
            }
            vectorMeta.__add = function(left, right)
                return Vector(left.x + right.x, left.y + right.y, left.z + right.z)
            end
            vectorMeta.__mul = function(vector, scalar)
                if type(vector) == "number" then vector, scalar = scalar, vector end
                return Vector(vector.x * scalar, vector.y * scalar, vector.z * scalar)
            end
            function Vector(x, y, z)
                return setmetatable({ x = x, y = y, z = z }, vectorMeta)
            end
            ZM_CSM = { SunDirection = Vector(1, 0, 0), ShadowCasterOverrides = {} }
            isfunction = function(value) return type(value) == "function" end
            isnumber = function(value) return type(value) == "number" end
            isstring = function(value) return type(value) == "string" end
            istable = function(value) return type(value) == "table" end
            IsValid = function(value) return type(value) == "table" and value.valid ~= false end
            EF_NOSHADOW = 16
            RENDERGROUP_OPAQUE = 0
            ClientsideModel = function()
                return {
                    valid = true,
                    effects = 0,
                    SetNoDraw = function() end,
                    GetEffects = function(self) return self.effects end,
                    DrawShadow = function(self, shouldDraw)
                        if shouldDraw then
                            self.effects = bit.band(self.effects, bit.bnot(EF_NOSHADOW))
                        else
                            self.effects = bit.bor(self.effects, EF_NOSHADOW)
                        end
                    end,
                    Remove = function(self) self.valid = false end
                }
            end
            concommand = {
                Add = function() end,
                Remove = function() end
            }
        """)

        source = lua_source(ROOT / "gamemode/cl_csm.lua")
        threshold_start = source.index("local shadowTriangleThreshold")
        threshold_end = source.index("\nlocal shadowFilterScanInterval", threshold_start)
        vegetation_start = source.index("local vegetationTokens = {", threshold_end)
        vegetation_end = source.index("\nlocal modelMeasurementQueue", vegetation_start)
        classification_start = source.index("local function containsToken", vegetation_end)
        classification_end = source.index("\nlocal function removeProjectors", classification_start)
        anchor_start = source.index("function CSM:GetPlayerProjectorPosition")
        anchor_end = source.index("\nfunction CSM:Reconcile", anchor_start)
        restore_start = source.index("function CSM:RestoreShadowCaster(entity)")
        restore_end = source.index("\nfunction CSM:RestoreShadowCasterFilter", restore_start)
        state_start = source.index("function CSM:SetShadowCasterState", restore_end)
        state_end = source.index("\nlocal function measureModelInfo", state_start)
        runner.lua.execute(
            "local CSM = ZM_CSM\n"
            "CSM.ShadowModelInfo = {}\n"
            "CSM.ShadowModelFailures = {}\n"
            "CSM.ModelCacheDirty = false\n"
            + source[threshold_start:threshold_end]
            + source[vegetation_start:vegetation_end]
            + source[classification_start:classification_end]
            + source[anchor_start:anchor_end]
            + source[restore_start:restore_end]
            + source[state_start:state_end]
        )

        runner.load("gamemode/utils/test_harness.lua")
        suite = runner.load("gamemode/tests/cl_csm_tests.lua")
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "CSM player-centered shadow anchor")


if __name__ == "__main__":
    unittest.main()
