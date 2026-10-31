"""Focused offline checks of guard-kill rewards against the gameplay owners."""

from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
from glua.harness import FixtureRunner, lua_source


class GuardRewardTests(unittest.TestCase):
    def test_guard_weapon_catalog_matches_hammer_choices(self):
        catalog = json.loads((ROOT / "content" / "data_static" / "prefab_guard_weapons.json").read_text(encoding="utf-8"))
        fgd = (ROOT / "zombiesim.fgd").read_text(encoding="utf-8")
        guard = fgd.split('= zn_prefab_guard', 1)[1].split('@SolidClass', 1)[0]
        self.assertEqual([entry["id"] for entry in catalog], ["pistol", "smg"])
        for entry in catalog:
            self.assertIn('"' + entry["id"] + '" :', guard)

    def test_guard_clothing_uses_existing_render_queue(self):
        runner = FixtureRunner(ROOT / "gamemode", ["utils/test_harness.lua", "cl_clothing.lua"])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            table.Add = function(target, values)
                for _, value in ipairs(values) do target[#target + 1] = value end
            end
            state = { applied = {}, hooks = {} }
            local function entity(class, shirt, pants)
                return { class = class, shirt = shirt, pants = pants, valid = true,
                    GetNWString = function(self, key)
                        if key == "ZM_Clothing_shirt" then return self.shirt end
                        if key == "ZM_Clothing_pants" then return self.pants end
                        return ""
                    end }
            end
            local survivor = entity("player", "survivor_shirt", "")
            local walker = entity("zn_walker_zombie", "walker_shirt", "walker_pants")
            local guard = entity("zn_prefab_guard", "guard_shirt", "guard_pants")
            local preview = entity("preview_guard", "preview_shirt", "preview_pants")
            function IsValid(value) return type(value) == "table" and value.valid == true end
            function RealTime() return 1 end
            function SysTime() return 0 end
            player = { GetAll = function() return { survivor } end }
            ents = { FindByClass = function(class)
                if class == "zn_walker_zombie" then return { walker } end
                if class == "zn_prefab_guard" then return { guard } end
                assert(class == "class C_HL2MPRagdoll" or class == "prop_ragdoll")
                return {}
            end }
            hook = { Add = function(_, name, callback) state.hooks[name] = callback end }
            ZM_PrefabGuardPreview = { ClothingSelections = function()
                return { { entity = preview, shirt = preview.shirt, pants = preview.pants } }
            end }
            ZM_Clothing = {
                GetEntitySelection = function(_, value)
                    return { shirt = value.shirt, pants = value.pants, bloody = value == walker }
                end,
                Apply = function(_, value, shirt, pants, bloody)
                    state.applied[#state.applied + 1] = { class = value.class, shirt = shirt,
                        pants = pants, bloody = bloody }
                    return true
                end
            }
        """)
        source = lua_source(ROOT / "gamemode" / "cl_clothing.lua")
        start = source.index('hook.Add("PreRender", "ZM.Clothing.Equipped"')
        end = source.index("function Clothing:GetDiagnosticSnapshot()", start)
        runner.lua.execute("""
            local Clothing = ZM_Clothing
            local applied, corpses = {}, {}
            local pending, pendingIndex, nextScan = {}, 1, 0
            local compositionBudgetSeconds = 0.002
        """ + source[start:end])
        suite = runner.lua.execute("""
            local suite = ZM_TestHarness.NewSuite()
            suite:Add("guard outfits join the existing clothing queue", function(check)
                state.hooks["ZM.Clothing.Equipped"]()
                check(#state.applied == 4, "survivor, walker, guard and editor preview are all processed")
                check(state.applied[1].class == "player" and state.applied[2].class == "zn_walker_zombie"
                    and state.applied[3].class == "zn_prefab_guard", "existing queue owners remain intact")
                check(state.applied[3].shirt == "guard_shirt" and state.applied[3].pants == "guard_pants"
                    and not state.applied[3].bloody, "the guard's own clean outfit reaches the renderer")
                check(state.applied[4].class == "preview_guard" and state.applied[4].shirt == "preview_shirt"
                    and state.applied[4].pants == "preview_pants" and not state.applied[4].bloody,
                    "the editor preview uses the same clean, budgeted clothing queue")
            end)
            return suite
        """)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard clothing queue")

    def test_guard_editor_preview(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/cl_guard_preview.lua",
            "tests/cl_prefab_guard_preview_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/cl_prefab_guard_preview_tests.lua")(
            runner.load("prefabs/cl_guard_preview.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard preview")

    def test_guard_probe(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "sv_prefab_guard_probe.lua", "tests/sv_prefab_guard_probe_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_guard_probe_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard probe")

    def test_guard_actor(self):
        runner = FixtureRunner(ROOT, [
            "gamemode/utils/test_harness.lua", "gamemode/tests/sv_prefab_guard_actor_tests.lua",
            "entities/entities/zn_prefab_guard/init.lua",
        ])
        runner.load("gamemode/utils/test_harness.lua")
        suite = runner.load("gamemode/tests/sv_prefab_guard_actor_tests.lua")(runner.compile)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard actor")

    def test_guard_config(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sh_contract.lua", "prefabs/sv_guard_config.lua",
            "tests/sv_prefab_guard_config_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_guard_config_tests.lua")(
            runner.load("prefabs/sv_guard_config.lua"),
            runner.load("prefabs/sh_contract.lua"),
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard config")

    def test_guard_weapons(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sv_guard_weapons.lua",
            "tests/sv_prefab_guard_weapons_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_guard_weapons_tests.lua")(
            runner.load("prefabs/sv_guard_weapons.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard weapons")

    def test_guard_targeting(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "prefabs/sv_guard_targeting.lua",
            "tests/sv_prefab_guard_targeting_tests.lua",
        ])
        runner.load("utils/test_harness.lua")
        suite = runner.load("tests/sv_prefab_guard_targeting_tests.lua")(
            runner.load("prefabs/sv_guard_targeting.lua")
        )
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard targeting")

    def test_guard_shot_probe_is_isolated_and_cleans_up(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "tests/sv_prefab_guard_shot.lua", "prefabs/sv_guard_targeting.lua",
        ])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            registered = {}
            ZM_TestHarness.Register = function(spec) registered[spec.command] = spec end
            state = { allowed = false, entities = {}, removed = 0, fail = false, safe = false }
            local vectorMeta = {}
            vectorMeta.__index = vectorMeta
            function vectorMeta.__add(a, b) return setmetatable({ x=a.x+b.x, y=a.y+b.y, z=a.z+b.z }, vectorMeta) end
            function vectorMeta.__sub(a, b) return setmetatable({ x=a.x-b.x, y=a.y-b.y, z=a.z-b.z }, vectorMeta) end
            function vectorMeta:LengthSqr() return self.x*self.x + self.y*self.y + self.z*self.z end
            function vectorMeta:DistToSqr(other) return (self - other):LengthSqr() end
            function vectorMeta:GetNormalized() return self end
            local function vector(x, y, z) return setmetatable({ x=x, y=y, z=z }, vectorMeta) end
            local owner = { ZM_PrefabEditorOrigin = vector(0, 0, 0) }
            local function create(class)
                local entity = { valid = true, class = class, health = 10000 }
                function entity:SetModel(model) self.model = model end
                function entity:GetClass() return self.class end
                function entity:SetPos(position) self.position = position end
                function entity:GetPos() return self.position end
                function entity:SetNoDraw(hidden) self.hidden = hidden end
                function entity:Spawn() end
                function entity:SetSolid(solid) self.solid = solid end
                function entity:SetHealth(value) self.health = value end
                function entity:Health() return self.health end
                function entity:WorldSpaceCenter() return self.position + vector(0, 0, 36) end
                function entity:FireBullets(bullet)
                    if state.fail then error("shot failed") end
                    state.safe = bullet.Callback(self, { Entity = owner }).damage == false
                    local result = bullet.Callback(self, { Entity = state.walker })
                    if not result or result.damage ~= false then state.walker.health = state.walker.health - bullet.Damage end
                end
                function entity:Remove() state.removed = state.removed + 1 end
                state.entities[#state.entities + 1] = entity
                if class == "zn_walker_zombie" then state.walker = entity end
                return entity
            end
            api = {
                Editor = { IsParticipant = function() return state.allowed end,
                    IsFixtureMap = function() return false end },
                FirstHuman = function() return owner end,
                ents = { Create = create },
                util = { TraceLine = function() return { Entity = state.walker } end },
                IsValid = function(value) return type(value) == "table" and value.valid == true end,
                IsVector = function(value) return getmetatable(value) == vectorMeta end,
                Vector = vector, SOLID_NONE = 0, MASK_SHOT = 1
            }
            function advance()
                for _, entity in ipairs(state.entities) do entity.valid = false end
            end
        """)
        runner.load("tests/sv_prefab_guard_shot.lua")(
            runner.lua.globals().api, runner.load("prefabs/sv_guard_targeting.lua")
        )
        commands = runner.lua.globals().registered
        shot = commands["zn_test_prefab_guard_shot"]
        cleanup = commands["zn_test_prefab_guard_shot_cleanup"]
        self.assertEqual(shot.run().failed, 1)
        self.assertEqual(len(runner.lua.globals().state.entities), 0)
        runner.lua.globals().state.allowed = True
        self.assertEqual(shot.run().passed, 1)
        self.assertTrue(runner.lua.globals().state.safe)
        self.assertEqual(runner.lua.globals().state.removed, 2)
        self.assertEqual(cleanup.run().failed, 1)
        runner.lua.globals().advance()
        self.assertEqual(cleanup.run().passed, 1)
        runner.lua.globals().state.fail = True
        self.assertEqual(shot.run().failed, 1)
        self.assertEqual(runner.lua.globals().state.removed, 4)
        runner.lua.globals().advance()
        self.assertEqual(cleanup.run().passed, 1)

    def test_guard_kill_probe_restores_temporary_state(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "tests/sv_prefab_guard_kill_live.lua",
        ])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            registered = {}
            ZM_TestHarness.Register = function(spec) registered[spec.command] = spec end
            state = { launcher = false, humans = 1, entities = {}, fail = nil }
            local vectorMeta = {}
            vectorMeta.__add = function(a, b)
                return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vectorMeta)
            end
            local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
            local owner = { valid = true, IsAdmin = function() return true end }
            local registry = { enemies = {} }
            local function create(class)
                local entity = { valid = true, class = class }
                function entity:SetPos(value) self.position = value end
                function entity:GetPos() return self.position end
                function entity:SetAngles(value) self.angles = value end
                function entity:SetNoDraw(value) self.hidden = value end
                function entity:SetMaxHealth(value) self.maxHealth = value end
                function entity:SetHealth(value) self.health = value end
                function entity:Health() return self.health end
                function entity:Spawn()
                    if self.class == "zn_prefab_guard" then
                        self.ZM_GuardConfig.weapon = { damage = self.ZM_GuardConfig.damage }
                    end
                end
                function entity:Remove() self.removeRequested = true end
                function entity:CreateCorpse() return create("prop_ragdoll") end
                function entity:ConfigureCorpse() return true end
                state.entities[#state.entities + 1] = entity
                return entity
            end
            api = {
                game = { GetMap = function() return state.launcher and "zn_preview_start" or "gm_flatgrass" end },
                World = { ActiveProfile = "preview" },
                player = { GetHumans = function()
                    if state.humans == 2 then return { owner, {} } end
                    return { owner }
                end },
                IsValid = function(value) return type(value) == "table" and value.valid == true end,
                ents = { Create = create }, Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
                LootSpots = {},
                StaticData = { GetRegistry = function() return registry end },
                Enemies = { OnEnemyKilled = function(_, victim)
                    assert(victim.EnemyRewarded)
                    return false, "already rewarded"
                end },
                Targeting = { Fire = function(guard, _, walker, _, weapon)
                    assert(guard.class == "zn_prefab_guard" and weapon.damage == 23)
                    assert(registry.enemies[walker.EnemyId] and api.LootSpots.Cell)
                    if state.fail == "replace" then api.LootSpots.Cell = state.otherCell; error("injected replacement") end
                    if state.fail then error("injected shot failure") end
                    walker.WalkerDead, walker.EnemyRewarded = true, true
                    walker.EnemyReward = { xp = 0, item = { itemId = "itemBandage" } }
                    local corpse = walker:CreateCorpse()
                    api.LootSpots.Cell.spotsByEntity[corpse] = {
                        runtime = true, state = "available", item = walker.EnemyReward.item
                    }
                    walker:ConfigureCorpse(corpse, true)
                    walker:Remove()
                    return true
                end }
            }
            function advance()
                for _, entity in ipairs(state.entities) do
                    if entity.removeRequested then entity.valid = false end
                end
            end
            function registrySlot() return registry.enemies.zz_dev_prefab_guard_kill end
        """)
        runner.load("tests/sv_prefab_guard_kill_live.lua")(runner.lua.globals().api)
        commands = runner.lua.globals().registered
        shot = commands["zn_test_prefab_guard_kill"]
        cleanup = commands["zn_test_prefab_guard_kill_cleanup"]
        state = runner.lua.globals().state
        api = runner.lua.globals().api

        self.assertEqual(shot.run().failed, 1)
        self.assertEqual(len(state.entities), 0)
        state.launcher, state.humans = True, 2
        self.assertEqual(shot.run().failed, 1)
        self.assertEqual(len(state.entities), 0)
        state.humans = 1
        api.LootSpots.Cell = runner.lua.table()
        self.assertEqual(shot.run().failed, 1)
        self.assertEqual(len(state.entities), 0)
        api.LootSpots.Cell = None

        state.fail = "shot"
        self.assertEqual(shot.run().failed, 1)
        self.assertIsNone(api.LootSpots.Cell)
        self.assertIsNone(runner.lua.globals().registrySlot())
        self.assertEqual(cleanup.run().failed, 1)
        runner.lua.globals().advance()
        self.assertEqual(cleanup.run().passed, 1)

        state.otherCell = runner.lua.table()
        state.fail = "replace"
        self.assertEqual(shot.run().failed, 1)
        self.assertTrue(runner.lua.eval("function(a, b) return a == b end")(api.LootSpots.Cell, state.otherCell))
        self.assertIsNone(runner.lua.globals().registrySlot())
        api.LootSpots.Cell = None
        runner.lua.globals().advance()
        self.assertEqual(cleanup.run().passed, 1)

        state.fail = None
        self.assertEqual(shot.run().passed, 1)
        self.assertIsNone(api.LootSpots.Cell)
        self.assertIsNone(runner.lua.globals().registrySlot())
        runner.lua.globals().advance()
        self.assertEqual(cleanup.run().passed, 1)

    def test_guard_engine_probe_registration_and_cleanup(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "tests/sv_prefab_guard_engine.lua", "prefabs/sv_guard_weapons.lua",
            "prefabs/sh_contract.lua", "prefabs/sv_guard_config.lua",
        ])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            ZM_TestHarness.Register = function(spec) registered[spec.command] = spec end
            registered = {}
            probeState = { removed = 0, fail = false, report = nil, entity = nil, fixture = false, guards = {} }
            local function entity()
                local value = { valid = true }
                function value:SetModel(model) self.model = model end
                function value:SetPos(position) self.position = position end
                function value:SetNoDraw(hidden) self.hidden = hidden end
                function value:Spawn() end
                function value:SetSolid(solid) self.solid = solid end
                function value:GetSequenceList()
                    if probeState.fail then error("sequence inspection failed") end
                    return { [0] = "idle_all_01", [1] = "shoot_pistol" }
                end
                function value:LookupSequence() return 0 end
                function value:LookupBone() return 12 end
                function value:LookupAttachment() return 1 end
                function value:Remove() probeState.removed = probeState.removed + 1 end
                probeState.entity = value
                return value
            end
            probeApi = {
                Clothing = { Models = { ["models/player/group01/male_03.mdl"] = "male" }, Finishes = {} },
                util = { IsValidModel = function() return true end,
                    JSONToTable = function() return {
                        { id = "pistol", label = "9mm Handgun", class = "weapon_zn_handgun_9mm",
                            idle = "idle_pistol", attack = "range_pistol" },
                        { id = "smg", label = "HL2 SMG", class = "weapon_zn_hl2_smg",
                            idle = "idle_smg1", attack = "range_smg1" }
                    } end },
                file = { Read = function(path, realm)
                    assert(path == "data_static/prefab_guard_weapons.json" and realm == "GAME")
                    return "fixture"
                end },
                weapons = { Get = function(class) return {
                    WorldModel = class, FireSound = "shot", BulletDamage = 12, BulletSpread = 0.02,
                    BulletForce = 1, BulletRange = 3000, BulletCount = 1, FireDelay = 0.2
                } end },
                ents = { Create = function(class) assert(class == "prop_dynamic"); return entity() end,
                    FindByClass = function(class) assert(class == "zn_prefab_guard"); return probeState.guards end },
                IsValid = function(value) return type(value) == "table" and value.valid == true end,
                Vector = function(x, y, z) return { x = x, y = y, z = z } end,
                SOLID_NONE = 0,
                DevConsole = { Report = function(_, _, report) probeState.report = report end },
                Editor = { IsFixtureMap = function() return probeState.fixture end,
                    IsParticipant = function() return probeState.fixture end },
                FirstHuman = function() return {} end
            }
        """)
        api = runner.lua.globals().probeApi
        api.GuardConfig = runner.load("prefabs/sv_guard_config.lua")(
            api.Clothing, runner.load("prefabs/sv_guard_weapons.lua")(api),
            api.util.IsValidModel, runner.load("prefabs/sh_contract.lua"),
        )
        runner.load("tests/sv_prefab_guard_engine.lua")(
            api, runner.load("prefabs/sv_guard_weapons.lua")
        )
        registered = runner.lua.globals().registered
        probe = registered["zn_test_prefab_guard_engine"]
        cleanup = registered["zn_test_prefab_guard_engine_cleanup"]
        self.assertEqual(registered["zn_test_prefab_guard_weapons"].run().passed, 1)
        self.assertEqual(registered["zn_test_prefab_guard_config"].run().passed, 1)
        self.assertEqual(registered["zn_test_prefab_guard_hammer"].run().failed, 1)
        self.assertEqual(registered["zn_test_prefab_guard_anchor"].run().failed, 1)
        first = probe.run()
        self.assertEqual(first.passed, 1)
        self.assertEqual(first.failed, 0)
        self.assertEqual(runner.lua.globals().probeState.removed, 1)
        self.assertEqual(runner.lua.globals().probeState.report.idle, 0)
        self.assertEqual(len(runner.lua.globals().probeState.report.sequences), 2)
        self.assertEqual(cleanup.run().failed, 1)
        runner.lua.globals().probeState.entity.valid = False
        self.assertEqual(cleanup.run().passed, 1)
        runner.lua.globals().probeState.fail = True
        failed = probe.run()
        self.assertEqual(failed.failed, 1)
        self.assertEqual(runner.lua.globals().probeState.removed, 2)
        runner.lua.globals().probeState.entity.valid = False
        self.assertEqual(cleanup.run().passed, 1)

    def test_guard_spawn_live_fixture_is_isolated_and_cleans_up(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "tests/sv_prefab_guard_spawn_live.lua",
        ])
        runner.load("utils/test_harness.lua")
        runner.lua.execute("""
            registered = {}
            ZM_TestHarness.Register = function(spec) registered[spec.command] = spec end
            state = { allowed = false, callbacks = {}, hooks = {}, timers = {}, created = 0 }
            local player = { valid = true, IsAdmin = function() return true end }
            local function entity()
                local value = { valid = true }
                function value:SetPos(pos) self.pos = pos end
                function value:GetPos() return self.pos end
                function value:SetAngles(angles) self.angles = angles end
                function value:GetAngles() return self.angles end
                function value:Spawn() end
                function value:Remove() self.valid = false end
                return value
            end
            api = {
                player = { GetHumans = function() return { player } end },
                game = { GetMap = function() return state.allowed and "zn_preview_start" or "gm_flatgrass" end },
                World = { ActiveProfile = "preview" },
                IsValid = function(value) return type(value) == "table" and value.valid == true end,
                ents = { Create = function(class) assert(class == "info_target"); state.created = state.created + 1; return entity() end },
                Vector = function(x, y, z) return { x = x, y = y, z = z } end,
                Angle = function(p, y, r) return { p = p, y = y, r = r } end,
                LocalToWorld = function() end, util = {}, GuardConfig = { PrepareDocumentGuard = function() end },
                AngleDifference = function(a, b) return (a - b + 180) % 360 - 180 end,
                timer = {
                    Create = function(name, _, _, callback) state.timers[name] = callback end,
                    Remove = function(name) state.timers[name] = nil end
                },
                hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
            }
            function fakeSpawn(_, options)
                assert(options.AllowGuards and type(options.ResolveGuard) == "function")
                return { Create = function(_, anchor, callback)
                    local yaw = anchor.angles.y
                    local radians = math.rad(yaw)
                    local guard = entity()
                    guard.pos = { x = 32 * math.cos(radians) - 16 * math.sin(radians),
                        y = 32 * math.sin(radians) + 16 * math.cos(radians), z = 4100 }
                    guard.angles = { y = yaw + 90 }
                    guard.ZM_GuardReady = true
                    guard.ZM_GuardConfig = { weapon = { damage = 23, delay = 0.075, spread = 0.04 } }
                    guard.ZM_WeaponModel = entity()
                    state.callbacks[#state.callbacks + 1] = callback
                    return { guard }, nil, true
                end }
            end
        """)
        runner.load("tests/sv_prefab_guard_spawn_live.lua")(
            runner.lua.globals().api, runner.lua.table(), runner.lua.globals().fakeSpawn
        )
        commands = runner.lua.globals().registered
        self.assertEqual(commands["zn_test_prefab_guard_spawn"].run().failed, 1)
        self.assertEqual(runner.lua.globals().state.created, 0)
        runner.lua.globals().state.allowed = True
        self.assertEqual(commands["zn_test_prefab_guard_spawn"].run().passed, 1)
        self.assertEqual(commands["zn_test_prefab_guard_spawn"].run().failed, 1)
        self.assertEqual(commands["zn_test_prefab_guard_spawn_check"].run().failed, 1)
        for callback in runner.lua.globals().state.callbacks.values():
            callback(True)
        self.assertEqual(commands["zn_test_prefab_guard_spawn_check"].run().passed, 1)
        self.assertEqual(commands["zn_test_prefab_guard_spawn_cleanup"].run().passed, 1)

    def test_guard_rewards(self):
        runner = FixtureRunner(ROOT / "gamemode", [
            "utils/test_harness.lua", "sv_item_generation.lua",
            "tests/sv_prefab_guard_reward_tests.lua",
        ])
        runner.lua.execute("""
            math.Clamp = function(value, minimum, maximum)
                return math.max(minimum, math.min(maximum, value))
            end
            math.Round = function(value) return math.floor(value + 0.5) end
            function Lerp(fraction, low, high) return low + fraction * (high - low) end
            table.Copy = function(input)
                local result = {}
                for key, value in pairs(input) do result[key] = value end
                return result
            end
            function IsValid(value)
                return type(value) == "table" and type(value.IsValid) == "function" and value:IsValid()
            end
            local definition = { minLevel = 10, maxLevel = 30, attributes = { "power" },
                minAttributes = 1, maxAttributes = 10 }
            ZM_Items = {
                GetDefinition = function(_, id) return id == "weapon" and definition or nil end,
                ValidateInstance = function(_, item)
                    return item.level >= definition.minLevel and item.level <= definition.maxLevel
                end
            }
            local drop = { item = "weapon", minWeight = 1, maxWeight = 1, minCount = 1, maxCount = 1 }
            local enemy = { id = "fixture", xp = 12, minDanger = 0, maxDanger = 1,
                minLootDropChance = 1, maxLootDropChance = 1, lootEntries = { drop } }
            local empty = { id = "no_drop", xp = 12, minDanger = 0, maxDanger = 1,
                minLootDropChance = 0, maxLootDropChance = 0, lootEntries = { drop } }
            ZM_StaticData = {
                GetEnemy = function(_, id)
                    if id == "fixture" then return enemy elseif id == "no_drop" then return empty end
                end,
                GetBoss = function(_, id)
                    if id == "fixture_boss" then return { id = id, enemy = "fixture", lootEntries = { drop } } end
                end,
                GetItem = function() return { lootCategory = "weapons" } end
            }
            state = { xp = 0, bonusCalls = 0 }
            state.guard = function() return {
                IsValid = function() return true end, IsPlayer = function() return false end,
                GetClass = function() return "zn_prefab_guard" end
            } end
            state.other = function() return {
                IsValid = function() return true end, IsPlayer = function() return false end,
                GetClass = function() return "prop_physics" end
            } end
            state.player = function() return {
                xp = 0, IsValid = function() return true end, IsPlayer = function() return true end,
                SteamID = function() return "fixture" end, GetLevel = function() return 15 end,
                AddXP = function(self, amount) self.xp = self.xp + amount; state.xp = state.xp + amount end
            } end
            ZM_ImplantService = { GetLootBonuses = function()
                state.bonusCalls = state.bonusCalls + 1
                return {}
            end }
            ZM_Enemies = {}
            ZM_Bosses = { Finish = function(_, id, profile)
                state.finished, state.finishedProfile = id, profile
                return true
            end }
        """)
        runner.load("utils/test_harness.lua")
        runner.load("sv_item_generation.lua")

        loot = lua_source(ROOT / "gamemode" / "sv_loot.lua")
        runner.lua.execute(loot[:loot.index("-- Samples a group")])
        enemies = lua_source(ROOT / "gamemode" / "sv_enemies.lua")
        start = enemies.index("function Enemies.ResolveKiller")
        end = enemies.index("local reply = ZM_Util.Reply", start)
        runner.lua.execute("local Enemies = ZM_Enemies\n" + enemies[start:end])
        bosses = lua_source(ROOT / "gamemode" / "sv_bosses.lua")
        start = bosses.index("function Bosses:OnBossKilled")
        end = bosses.index("function Bosses:SpawnForPlayer", start)
        runner.lua.execute("local Bosses = ZM_Bosses\n" + bosses[start:end])

        suite = runner.load("tests/sv_prefab_guard_reward_tests.lua")(runner.lua.globals().state)
        runnable = runner.lua.eval(
            "function(suite) return { Run = function() return suite:Run() end } end"
        )(suite)
        runner.run(runnable, "Prefab guard rewards")


if __name__ == "__main__":
    unittest.main()
