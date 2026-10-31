return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { allowed = false, owner = false, fixture = false, entities = {}, hooks = {},
            timers = {}, timerDurations = {}, errors = {}, configValid = true }
        local vectorMeta = {}
        vectorMeta.__index = vectorMeta
        function vectorMeta.__add(a, b)
            return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vectorMeta)
        end
        function vectorMeta.__sub(a, b)
            return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
        end
        function vectorMeta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
        function vectorMeta:GetNormalized()
            local length = math.sqrt(self:LengthSqr())
            return setmetatable({ x = self.x / length, y = self.y / length, z = self.z / length }, vectorMeta)
        end
        function vectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local owner = { valid = true, ZM_PrefabEditorOrigin = vector(100, 200, 300) }
        local env = {
            pairs = pairs, ipairs = ipairs, table = table, type = type, tostring = tostring, tonumber = tonumber, math = math,
            CurTime = function() return 12 end,
            Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end, EF_BONEMERGE = 1,
            IsValid = function(value) return type(value) == "table" and value.valid == true end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            ZM_Clothing = { CatalogueReady = true, Finishes = {
                shirt = { garment = "shirt" }, pants = { garment = "pants" }
            } },
            ZM_PrefabEditor = {
                IsParticipant = function() return state.allowed end,
                IsOwner = function() return state.owner end,
                IsFixtureMap = function() return state.fixture end
            },
            ZM_PrefabGuardConfig = { Validate = function(config)
                state.lastConfig = config
                if not state.configValid then return nil, "invalid config" end
                return config
            end },
            ZM_Util = {
                ResolveCommandTarget = function() return owner end,
                RegisterCommands = function(_, callback) state.command = callback end
            },
            ZM_DevConsole = { Report = function(_, name, value) state.report = { name = name, value = value } end },
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end },
            timer = {
                Create = function(name, delay, _, callback) state.timers[name], state.timerDurations[name] = callback, delay end,
                Remove = function(name) state.timers[name], state.timerDurations[name] = nil, nil end,
                Simple = function(_, callback) state.readyCheck = callback end
            },
            ents = { Create = function(class)
                if state.failedClass == class then return nil end
                local entity = { valid = true, class = class }
                function entity:SetPos(value) self.position = value end
                function entity:GetPos() return self.position end
                function entity:SetAngles(value) self.angles = value end
                function entity:WorldSpaceCenter() return self.position end
                function entity:Spawn() end
                function entity:SetMaxHealth(value) self.maxHealth = value end
                function entity:SetHealth(value) self.health = value end
                function entity:Health() return self.health end
                function entity:Remove()
                    self.valid = false
                    if self.ZM_WeaponModel then self.ZM_WeaponModel.valid = false end
                end
                state.entities[#state.entities + 1] = entity
                return entity
            end }
        }
        local chunk = loadChunk("sv_prefab_guard_probe.lua")
        setfenv(chunk, env)
        chunk()
        return state
    end

    suite:Add("guard preview requires the sole editor owner and cleans up", function(check)
        local state = fixture()
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "start" }) and #state.entities == 0,
            "unauthorized start creates nothing")
        state.allowed, state.owner, state.fixture = true, true, true
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "start" }) and #state.entities == 0,
            "the anchor fixture is not the editor workspace")
        state.fixture = false
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "start", "unknown" }) and #state.entities == 0,
            "unknown preview weapons are rejected")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "start" }) and #state.entities == 2,
            "the editor owner creates one guard and one temporary walker")
        local guard, walker = state.entities[1], state.entities[2]
        check(guard.position.x == -60 and guard.position.y == 600 and walker.health == 100000,
            "the isolated target has bounded placement and high health")
        local weapon = { valid = true, position = guard.position, angles = { p = 0, y = 0, r = 0 } }
        function weapon:GetLocalAngles() return self.angles end
        function weapon:SetLocalAngles(value) self.angles = value end
        function weapon:GetLocalPos() return self.localPosition or setmetatable({ x = 0, y = 0, z = 0 }, getmetatable(self.position)) end
        function weapon:SetLocalPos(value) self.localPosition = value end
        function weapon:SetParent(value, attachment) self.parent, self.attachment = value, attachment end
        function weapon:AddEffects() self.merged = true end
        function weapon:RemoveEffects() self.merged = false end
        function weapon:IsEffectActive() return self.merged == true end
        function weapon:LookupAttachment() return 1 end
        function weapon:GetAttachment() return { Pos = self.position + setmetatable({ x = 1, y = 0, z = 0 }, getmetatable(self.position)) } end
        function weapon:GetPos() return self.position end
        guard.ZM_GuardReady, guard.ZM_WeaponModel, guard.ZM_Shots, guard.ZM_HandAttachment = true, weapon, 2, 5
        function guard:IsValidLayer() return true end
        guard.ZM_AttackLayer = 4
        state.readyCheck()
        state.command(nil, "zombiesim_prefab_guard_probe", { "status" })
        check(state.report.value.ready and state.report.value.weapon and state.report.value.shots == 2
            and state.report.value.firingGesture and state.report.value.muzzleAlignment == 1,
            "status reports actual guard readiness and shots")
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "orient", "0", "nan", "0" }),
            "invalid preview angles are rejected")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "orient", "0", "180", "0" })
            and weapon.angles.y == 180, "the owner can adjust only the temporary weapon")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "merge", "on" })
            and weapon.merged and weapon.parent == guard, "the owner can test bone merging")
        state.command(nil, "zombiesim_prefab_guard_probe", { "status" })
        check(state.report.value.boneMerged and state.report.value.muzzleError ~= nil,
            "status distinguishes client-side bone merge from server muzzle measurements")
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "orient", "0", "0", "0" }),
            "attachment offsets cannot be changed while bone merge is active")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "merge", "off" })
            and not weapon.merged and weapon.angles.y == 180 and weapon.attachment == 5,
            "turning bone merge off restores the previous attachment transform")
        state.hooks.PreCleanupMap()
        check(not guard.valid and not walker.valid, "map cleanup removes both owned entities")
        state.command(nil, "zombiesim_prefab_guard_probe", { "status" })
        check(state.report.value.cleanupRemaining == 0, "status verifies the guard, walker and weapon are gone")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "start", "smg" })
            and state.entities[3].ZM_GuardConfig.weapon == "smg",
            "the separate SMG preview uses its own selected firearm")
        state.hooks.PreCleanupMap()
    end)
    suite:Add("guard preview validates and reports optional combat overrides", function(check)
        local state = fixture()
        state.allowed, state.owner = true, true
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "start", "pistol", "23" })
            and #state.entities == 0, "partial overrides cannot start a probe")
        state.configValid = false
        check(not state.command(nil, "zombiesim_prefab_guard_probe", { "start", "pistol", "23", "0.2", "0" })
            and #state.entities == 0, "invalid combat settings are rejected before creating entities")
        state.configValid = true
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "start", "pistol", "23", "0.2", "0" }),
            "the editor owner can start an override probe")
        local guard, walker = state.entities[1], state.entities[2]
        check(state.lastConfig.damage == 23 and state.lastConfig.fireInterval == 0.2
            and state.lastConfig.spread == 0 and not walker:IsValidTarget({}),
            "the guard receives all overrides and its temporary walker cannot target players")
        check(state.timerDurations["ZM.PrefabGuardProbe.Expiry"] == 15, "the override probe expires after 15 seconds")
        guard.ZM_GuardConfig.weapon = { id = "pistol", damage = 23, delay = 0.2, spread = 0 }
        guard.ZM_GuardReady = true
        state.command(nil, "zombiesim_prefab_guard_probe", { "status" })
        check(state.report.value.sampleTime == 12 and state.report.value.combat.damage == 23
            and state.report.value.combat.fireInterval == 0.2 and state.report.value.combat.spread == 0,
            "status reports the initialized weapon values with a sample time")
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "stop" })
            and not guard.valid and not walker.valid, "the owner removes the override probe")
    end)

    suite:Add("guard preview reports failed initialization and removes its target", function(check)
        local state = fixture()
        state.allowed, state.owner = true, true
        check(state.command(nil, "zombiesim_prefab_guard_probe", { "start" }), "the preview starts")
        state.readyCheck()
        check(not state.entities[1].valid and not state.entities[2].valid and #state.errors == 1,
            "failed asynchronous initialization removes both entities and logs the error")
        state.command(nil, "zombiesim_prefab_guard_probe", { "status" })
        check(state.report.value.error ~= nil and not state.report.value.guard,
            "the failure remains visible in status")
    end)
    return suite
end
