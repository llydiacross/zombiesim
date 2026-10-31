return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { now = 0, timers = {}, errors = {}, target = nil, fire = true, shots = 0, weapons = {} }
        local vectorMeta = {}
        vectorMeta.__index = vectorMeta
        function vectorMeta.__sub(a, b)
            return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
        end
        function vectorMeta:Angle() return { p = 0, y = 90, r = 0 } end
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local config = { name = "Guard", model = "models/player/group01/male_03.mdl", idle = "idle_all_01",
            shirt = "shirt_a", pants = "", range = 1000,
            weapon = { model = "weapon.mdl", idle = "idle_pistol", attack = "range_pistol", delay = 0.2, sound = "shot" } }
        local env = {
            ENT = {}, SERVER = true, type = type, tostring = tostring, math = math, string = string,
            SOLID_BBOX = 1, SOLID_NONE = 0, MOVETYPE_NONE = 0, EF_BONEMERGE = 1,
            AddCSLuaFile = function() end, include = function(path) assert(path == "shared.lua") end,
            Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            IsValid = function(value) return type(value) == "table" and value.valid == true end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            CurTime = function() return state.now end,
            timer = { Simple = function(_, callback) state.timers[#state.timers + 1] = callback end },
            ZM_PrefabGuardConfig = { Validate = function(settings)
                state.lastSettings = settings
                if state.badConfig then return nil, "invalid config" end
                return config
            end, FromHammer = function(values)
                state.mapValues = values
                if state.badMapConfig then return nil, "invalid Hammer settings" end
                return { fromHammer = true }
            end },
            ZM_PrefabGuardTargeting = {
                Select = function() return state.target, state.selectError end,
                IsZombie = function(target) return target ~= nil and target.valid == true end,
                Fire = function()
                    state.shots = state.shots + 1
                    if not state.fire then return false, state.fireError or "The target is unavailable or obstructed." end
                    return true
                end
            },
            ents = { Create = function(class)
                assert(class == "prop_dynamic")
                local weapon = { valid = true }
                function weapon:SetModel(value) self.model = value end
                function weapon:Spawn() end
                function weapon:SetSolid(value) self.solid = value end
                function weapon:SetMoveType(value) self.moveType = value end
                function weapon:SetParent(value, attachment) self.parent, self.attachment = value, attachment end
                function weapon:AddEffects(value) self.effects = value end
                function weapon:SetLocalPos(value) self.position = value end
                function weapon:SetLocalAngles(value) self.angles = value end
                function weapon:Remove() self.valid = false end
                state.weapons[#state.weapons + 1] = weapon
                return weapon
            end }
        }
        local chunk = loadChunk("entities/entities/zn_prefab_guard/init.lua")
        setfenv(chunk, env)
        chunk()
        local actor = setmetatable({ valid = true, ZM_GuardConfig = {}, angles = { p = 0, y = 12, r = 0 },
            position = vector(0, 0, 0), network = {}, sequences = {} }, { __index = env.ENT })
        function actor:GetAngles() return self.angles end
        function actor:CreatedByMap() return state.createdByMap == true end
        function actor:SetAngles(value) self.angles = value end
        function actor:GetPos() return self.position end
        function actor:SetModel(value) self.model = value end
        function actor:SetMoveType(value) self.moveType = value end
        function actor:SetSolid(value) self.solid = value end
        function actor:SetCollisionBounds(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
        function actor:SetNWString(key, value) self.network[key] = value end
        function actor:SetNWBool(key, value) self.network[key] = value end
        function actor:LookupSequence(name) return state.missingSequence and -1 or ({ idle_all_01 = 1, idle_pistol = 2, range_pistol = 3 })[name] end
        function actor:LookupAttachment() return state.missingAttachment and 0 or 5 end
        function actor:ResetSequence(value) self.sequences[#self.sequences + 1] = value end
        function actor:FindGestureSequenceLayer() return self.gestureActive and 4 or -1 end
        function actor:IsValidLayer(layer) return layer == 4 and self.gestureActive == true end
        function actor:AddGestureSequence(sequence)
            self.gestureSequence, self.gestureActive = sequence, true
            self.gestureAdds = (self.gestureAdds or 0) + 1
            return 4
        end
        function actor:SetLayerCycle(_, cycle) self.gestureCycle = cycle end
        function actor:RemoveLayer() self.gestureActive = false end
        function actor:DeleteOnRemove(value) self.child = value end
        function actor:GetAttachment() return { Pos = vector(0, 0, 36) } end
        function actor:FrameAdvance() end
        function actor:NextThink(value) self.nextThink = value end
        function actor:EmitSound(value) self.sound = value end
        function actor:Remove() self.valid = false; self:OnRemove() end
        return state, actor, config, vector
    end

    suite:Add("guard actor initializes safely and is invulnerable", function(check)
        local state, actor = fixture()
        local results = {}
        actor.ZM_GuardReadyCallback = function(entity, ok, problem)
            results[#results + 1] = { entity = entity, ok = ok, problem = problem }
        end
        actor:Initialize()
        check(actor.valid and not actor.ZM_GuardReady and actor.network.ZM_NpcName == "Guard",
            "model and clothing are set before deferred initialization")
        state.timers[1]()
        check(actor.ZM_GuardReady and actor.child == state.weapons[1]
            and state.weapons[1].parent == actor and state.weapons[1].effects == 1
            and actor.ZM_HandAttachment == 5, "validated animations create an owned bone-merged weapon")
        check(#results == 1 and results[1].entity == actor and results[1].ok
            and actor.ZM_GuardReadyCallback == nil, "the owner receives exactly one readiness notification")
        local damage = { value = 5, SetDamage = function(self, value) self.value = value end }
        check(actor:OnTakeDamage(damage) == 0 and damage.value == 0, "the guard cannot take damage")
        actor:Remove()
        check(not state.weapons[1].valid and #results == 1, "removing a ready guard also removes its weapon")
    end)

    suite:Add("map guard consumes Hammer settings without replacing scripted settings", function(check)
        local state, actor = fixture()
        state.createdByMap, actor.ZM_GuardConfig = true, nil
        actor:KeyValue("Guard_Name", "Alex")
        actor:KeyValue("Fire_Interval", "0.1")
        actor:Initialize()
        check(actor.valid and state.mapValues.guard_name == "Alex" and state.mapValues.fire_interval == "0.1"
            and state.lastSettings.fromHammer == true, "map keyvalues are normalized and validated")
        local scriptedState, scripted = fixture()
        local scriptedSettings = scripted.ZM_GuardConfig
        scriptedState.createdByMap = true
        scripted:Initialize()
        check(scriptedState.mapValues == nil and scriptedState.lastSettings == scriptedSettings,
            "explicit scripted settings do not fall back to map keyvalues")
        local badState, bad = fixture()
        badState.createdByMap, badState.badMapConfig, bad.ZM_GuardConfig = true, true, nil
        bad:Initialize()
        check(not bad.valid and #badState.errors == 1, "invalid map settings are reported and removed")
    end)

    suite:Add("guard actor engages and then restores its authored idle", function(check)
        local state, actor, _, vector = fixture()
        actor:Initialize()
        state.timers[1]()
        local target = { valid = true, WorldSpaceCenter = function() return vector(100, 0, 36) end }
        state.target = target
        actor:Think()
        check(actor.ZM_Combat and state.shots == 1 and actor.angles.y == 90 and actor.sound == "shot",
            "a selected target turns the guard and produces a shot")
        check(actor.sequences[#actor.sequences] == "idle_pistol" and actor.gestureSequence == 3
            and actor.gestureAdds == 1, "the firing sequence layers over the combat idle")
        state.now = 0.1
        actor:Think()
        check(state.shots == 1, "weapon cadence prevents an early second shot")
        state.now = 0.17
        actor:Think()
        check(actor.nextThink == 0.2, "the next firing deadline is not rounded up to the polling interval")
        state.now = 0.2
        actor:Think()
        check(state.shots == 2 and actor.gestureAdds == 1 and actor.gestureCycle == 0,
            "repeated shots restart the existing gesture instead of accumulating layers")
        state.target = nil
        target.valid = false
        state.now = 0.3
        actor:Think()
        check(not actor.ZM_Combat and not actor.gestureActive and actor.angles.y == 12
            and actor.sequences[#actor.sequences] == "idle_all_01",
            "leaving combat restores the authored facing and idle")
    end)

    suite:Add("invalid guard setup and firing errors remove the actor", function(check)
        local state, actor = fixture()
        local failure
        actor.ZM_GuardReadyCallback = function(_, ok, problem) failure = { ok = ok, problem = problem } end
        state.badConfig = true
        actor:Initialize()
        check(not actor.valid and #state.errors == 1 and failure and not failure.ok and failure.problem,
            "invalid settings fail explicitly and notify their owner")
        local state2, actor2 = fixture()
        state2.missingAttachment = true
        actor2:Initialize()
        state2.timers[1]()
        check(not actor2.valid and #state2.errors == 1 and #state2.weapons == 0,
            "unsupported hand attachments fail without leaving a weapon")
        local state3, actor3, _, vector = fixture()
        actor3:Initialize()
        state3.timers[1]()
        state3.target = { valid = true, WorldSpaceCenter = function() return vector(100, 0, 36) end }
        state3.fire, state3.fireError = false, "Invalid guard firing parameters."
        actor3:Think()
        check(not actor3.valid and #state3.errors == 1 and not state3.weapons[1].valid,
            "unexpected firing errors are surfaced and cleaned up")
    end)
    suite:Add("removing an unready guard reports one initialization failure", function(check)
        local state, actor = fixture()
        local calls = 0
        actor.ZM_GuardReadyCallback = function(_, ok, problem)
            calls = calls + 1
            check(not ok and type(problem) == "string", "premature removal carries an error")
        end
        actor:Initialize()
        actor:Remove()
        state.timers[1]()
        check(calls == 1, "later initialization cannot notify or revive a removed guard")
    end)
    return suite
end
