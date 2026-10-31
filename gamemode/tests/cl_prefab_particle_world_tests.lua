return function(createWorld)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { now = 0, hooks = {}, entities = {}, created = {}, errors = {} }
        local editor = { active = false, IsActive = function(self) return self.active end }
        local catalog = { Resolve = function(id)
            if id ~= "steam" then return nil, "Unknown effect." end
            return { id = id }
        end }
        local service = { Create = function(definition, position, angles, mode)
            if state.fail then return nil, "Allocation failed." end
            local handle = { definition = definition, position = position, angles = angles, mode = mode, active = true }
            function handle:Stop() self.active = false; self.stopped = true end
            function handle:Move(value, angle) self.position, self.angles = value, angle end
            function handle:Update()
                if self.problem then self:Stop(); return false, self.problem end
                return self.active
            end
            state.created[#state.created + 1] = handle
            return handle
        end }
        local api = {
            GetEditor = function() return editor end, FindEntities = function() return state.entities end,
            IsValid = function(value) return value and value.valid end,
            IsVector = function(value) return type(value) == "table" and value.kind == "vector" end,
            IsAngle = function(value) return type(value) == "table" and value.kind == "angle" end,
            RealTime = function() return state.now end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        }
        local function entity(id)
            local value = { valid = true, id = id, effect = "steam",
                position = { kind = "vector", x = 1, y = 2, z = 3 },
                angles = { kind = "angle", p = 4, y = 5, r = 6 } }
            function value:GetPrefabParticleId() return self.id end
            function value:GetParticleEffectId() return self.effect end
            function value:GetPos() return self.position end
            function value:GetAngles() return self.angles end
            return value
        end
        return state, editor, createWorld(api, catalog, service), entity
    end
    suite:Add("networked continuous particles initialize, move and clean up", function(check)
        local state, editor, world, entity = fixture()
        local first = entity("10:particle_1")
        state.entities = { first }
        state.hooks.Think()
        local handle = state.created[1]
        check(handle and handle.mode == "continuous" and world:Status().continuous == 1,
            "networked particle creates a client effect")
        state.now = 0.3
        first.position.x, first.angles.y = 25, 90
        state.hooks.Think()
        check(#state.created == 1 and handle.position.x == 25 and handle.angles.y == 90,
            "transform changes move the existing effect")
        state.entities, state.now = {}, 0.6
        state.hooks.Think()
        check(handle.stopped and world:Status().continuous == 0, "entity removal stops its effect")
        state.entities, state.now = { first }, 0.9
        state.hooks.Think()
        editor.active = true
        state.hooks.Think()
        check(state.created[2].stopped, "entering the editor clears world effects")
        world:SetFixtureActive(true)
        state.now = 1.2
        state.hooks.Think()
        check(world:Status().fixture and world:Status().continuous == 1,
            "the explicitly enabled isolated fixture can run inside the editor")
        world:SetFixtureActive(false)
        check(not world:Status().fixture and world:Status().continuous == 0 and state.created[3].stopped,
            "disabling the fixture cleans up world effects")
    end)
    suite:Add("triggered events overlap or restart without a fixed cap", function(check)
        local state, _, world = fixture()
        local position = { kind = "vector", x = 1, y = 2, z = 3 }
        local angles = { kind = "angle", p = 0, y = 90, r = 0 }
        for _ = 1, 40 do check(world:Trigger("10:particle_1", "steam", position, angles, true), "event starts") end
        check(world:Status().bursts == 40, "more than 16 overlapping effects remain active")
        check(world:Trigger("10:particle_1", "steam", position, angles, false)
            and world:Status().bursts == 1 and state.created[1].stopped and state.created[40].stopped,
            "overlap off restarts the matching particle")
        check(world:Trigger("11:particle_1", "steam", position, angles, true) and world:Status().bursts == 2,
            "another anchor has independent triggered bursts")
        world:StopBursts("10:particle_1")
        check(world:Status().bursts == 1 and state.created[41].stopped and not state.created[42].stopped,
            "anchor removal stops only its own active bursts")
        check(not world:Trigger("../bad", "steam", position, angles, true)
            and not world:Trigger("10:particle_1", "missing", position, angles, true)
            and not world:Trigger("10:particle_1", "steam", position, angles, "true"),
            "invalid events are rejected")
        state.hooks.PreCleanupMap()
        check(world:Status().bursts == 0 and state.created[41].stopped and state.created[42].stopped,
            "map cleanup stops triggered effects")
    end)
    suite:Add("continuous world effects have no fixed simultaneous cap", function(check)
        local state, _, world, entity = fixture()
        for index = 1, 40 do state.entities[index] = entity(tostring(index) .. ":particle_1") end
        state.hooks.Think()
        check(world:Status().continuous == 40 and #state.created == 40,
            "forty networked continuous effects are retained")
        state.hooks.PreCleanupMap()
        check(world:Status().continuous == 0 and state.created[1].stopped and state.created[40].stopped,
            "all uncapped effects are cleaned up")
    end)
    suite:Add("pending replication and allocation errors are visible", function(check)
        local state, _, world, entity = fixture()
        state.entities = { entity("") }
        state.hooks.Think()
        check(world:Status().pending == 1 and #state.created == 0, "not-yet-replicated IDs stay pending")
        state.entities[1].id, state.now, state.fail = "10:particle_1", 0.3, true
        state.hooks.Think()
        state.now = 0.6
        state.hooks.Think()
        check(#state.errors == 1 and world:Status().errors["10:particle_1"] == "Allocation failed.",
            "allocation errors are reported once while retry is delayed")
        state.now, state.fail = 2.4, false
        state.hooks.Think()
        check(world:Status().continuous == 1 and world:Status().errors["10:particle_1"] == nil,
            "successful retry clears the error")
        state.entities[2], state.now = entity("10:particle_1"), 2.7
        state.hooks.Think()
        check(#state.errors == 2 and world:Status().errors["10:particle_1"] == "Duplicate networked particle ID.",
            "duplicate IDs are reported")
    end)
    return suite
end
