return function(loadChunk)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("particle event receiver preserves the server message order", function(check)
        local state = { values = {
            { "string", "42:particle_1" }, { "string", "steam" },
            { "double", 20000.125 }, { "double", -21000.5 }, { "double", 12.75 },
            { "double", 10 }, { "double", 90 }, { "double", -5 }, { "bool", true }
        }, index = 1 }
        local function read(kind)
            local item = state.values[state.index]
            assert(item and item[1] == kind, "particle message read order mismatch")
            state.index = state.index + 1
            return item[2]
        end
        local world = {
            Trigger = function(_, id, effect, position, angles, overlap)
                state.received = { id, effect, position, angles, overlap }
                return true
            end,
            StopBursts = function(_, id) state.stopped = id end,
            Status = function() return {} end
        }
        local env = {
            type = type, tostring = tostring, string = string,
            ZM_PrefabParticleCatalog = {}, ZM_PrefabParticleEffects = {}, ZM_PrefabParticlePreview = {},
            IsValid = function() end, isvector = function() end, isangle = function() end,
            RealTime = function() end, ErrorNoHalt = function(message) state.error = message end,
            hook = {}, ents = {},
            Vector = function(x, y, z) return { x = x, y = y, z = z } end,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            include = function(path)
                assert(path == "prefabs/cl_particle_world.lua")
                return function() return world end
            end,
            net = {
                Receive = function(name, callback)
                    state.receivers = state.receivers or {}
                    state.receivers[name] = callback
                end,
                ReadString = function() return read("string") end,
                ReadDouble = function() return read("double") end,
                ReadBool = function() return read("bool") end
            },
            concommand = { Add = function() end }
        }
        local chunk = loadChunk("gamemode/cl_prefab_particle_world.lua")
        setfenv(chunk, env)
        chunk()
        state.receivers["ZM.PrefabParticle.Trigger"]()
        local result = state.received
        check(result and result[1] == "42:particle_1" and result[2] == "steam"
            and result[3].x == 20000.125 and result[3].y == -21000.5 and result[3].z == 12.75
            and result[4].p == 10 and result[4].y == 90 and result[4].r == -5 and result[5] == true,
            "IDs, uncompressed coordinates, orientation and overlap arrive in order")
        state.values, state.index = { { "string", "42:particle_1" } }, 1
        state.receivers["ZM.PrefabParticle.Stop"]()
        check(state.stopped == "42:particle_1", "anchor cleanup stops the matching burst")
    end)
    return suite
end
