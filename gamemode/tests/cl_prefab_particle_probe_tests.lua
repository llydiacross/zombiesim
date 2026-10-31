return function(createProbe, createService)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { active = false, missing = nil, hooks = {}, events = {}, errors = {}, effects = {}, anchors = {}, now = 0 }
        local vectorMeta = { __add = function(a, b)
            return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a))
        end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local editor = { Origin = vector(100, 200, 300), IsActive = function() return state.active end }
        local api = {
            Editor = editor, Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            Catalog = { Resolve = function(id)
                assert(id == "steam")
                return { id = "steam", particleFile = "particles/train_steam.pcf",
                    particleSystem = "steam_train", sound = "ambient/gas/steam_loop1.wav" }
            end },
            IsValid = function(value) return value and value.valid end,
            file = { Exists = function(path, realm)
                assert(realm == "GAME")
                return path ~= state.missing
            end },
            game = { AddParticles = function(path) state.events[#state.events + 1] = "file:" .. path end },
            PrecacheParticleSystem = function(name) state.events[#state.events + 1] = "precache:" .. name end,
            CreateParticleSystemNoEntity = function(name, position)
                state.events[#state.events + 1] = "create:" .. name
                if state.effectFailure then return nil end
                local effect = { valid = true, position = position }
                function effect:StopEmission(infinite, remove, wake) self.stopped = { infinite, remove, wake }; self.valid = false end
                function effect:GetEffectName() return name end
                function effect:IsFinished() return self.finished == true end
                function effect:SetControlPoint(index, value) self["control" .. index] = value end
                function effect:SetControlPointOrientation(index, value) self["orientation" .. index] = value end
                state.effects[#state.effects + 1] = effect
                return effect
            end,
            ClientsideModel = function(path, group)
                if state.modelFailure then return nil end
                local model = { valid = true, path = path, group = group }
                function model:SetNoDraw(value) self.noDraw = value end
                function model:SetPos(value) self.position = value end
                function model:Remove() self.valid = false end
                state.anchors[#state.anchors + 1] = model
                return model
            end,
            RENDERGROUP_OTHER = 13,
            CreateSound = function(anchor, path)
                if state.soundFailure then return nil end
                local sound = { anchor = anchor, path = path }
                function sound:SetSoundLevel(value) self.level = value end
                function sound:Play() self.playing = true end
                function sound:Stop() self.playing = false end
                function sound:IsPlaying() return self.playing == true end
                state.sound = sound
                return sound
            end,
            ErrorNoHalt = function(message) state.errors[#state.errors + 1] = message end,
            RealTime = function() return state.now end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        }
        local service = createService(api)
        return state, createProbe(api, service), service, api
    end
    suite:Add("steam preview starts from mounted assets and cleans up", function(check)
        local state, probe = fixture()
        local ok = probe:Start("burst")
        check(not ok and #state.anchors == 0, "inactive editor cannot start a preview")
        state.active = true
        check(probe:Start("burst"), "active editor starts the preview")
        local effect, anchor = state.effects[1], state.anchors[1]
        local status = probe:Status()
        check(state.events[1] == "file:particles/train_steam.pcf" and state.events[2] == "precache:steam_train"
            and state.events[3] == "create:steam_train", "mounted particle file is loaded before precache and creation")
        check(effect.position.x == 100 and effect.position.y == 200 and effect.position.z == 316
            and anchor.noDraw and anchor.position.z == 316 and state.sound.path == "ambient/gas/steam_loop1.wav"
            and state.sound.level == 75 and status.active and status.soundPlaying and status.effectName == "steam_train",
            "effect and spatial audio share the workspace origin and report actual status")
        check(not probe:Start("burst"), "a second preview cannot be started")
        state.active = false
        state.hooks.Think()
        check(not effect.valid and effect.stopped[2] and not anchor.valid and not state.sound.playing
            and not probe:Status().active, "closing the editor removes particles, sound and anchor")
    end)
    suite:Add("steam preview reports missing assets and allocation failures", function(check)
        local state, probe = fixture()
        state.active, state.missing = true, "particles/train_steam.pcf"
        local ok, problem = probe:Start("burst")
        check(not ok and type(problem) == "string" and #state.anchors == 0, "missing particle asset is reported")
        state.missing, state.modelFailure = nil, true
        ok, problem = probe:Start("burst")
        check(not ok and type(problem) == "string", "audio-anchor failure is reported")
        state.modelFailure, state.effectFailure = false, true
        ok, problem = probe:Start("burst")
        check(not ok and type(problem) == "string" and not state.anchors[#state.anchors].valid,
            "particle allocation failure removes the audio anchor")
        state.effectFailure, state.soundFailure = false, true
        ok, problem = probe:Start("burst")
        check(not ok and type(problem) == "string" and not state.effects[#state.effects].valid
            and not state.anchors[#state.anchors].valid, "sound failure removes the effect and audio anchor")
    end)
    suite:Add("unexpected effect loss is reported and releases audio", function(check)
        local state, probe = fixture()
        state.active = true
        check(probe:Start("burst"), "preview starts")
        state.effects[1].valid = false
        state.hooks.Think()
        check(not state.sound.playing and not state.anchors[1].valid and #state.errors == 1
            and type(probe:Status().error) == "string", "lost effect stops sound and reports the failure")
        state.hooks.PreCleanupMap()
        state.hooks.ShutDown()
        check(not state.anchors[1].valid, "cleanup remains safe when repeated")
    end)
    suite:Add("observed particle completion is distinguished from unexpected loss", function(check)
        local state, probe = fixture()
        state.active = true
        check(probe:Start("burst"), "preview starts")
        state.now, state.effects[1].finished = 8, true
        state.hooks.Think()
        check(probe:Status().finished and probe:Status().finishedAfter == 8,
            "finished state and elapsed time are reported")
        state.now, state.effects[1].valid = 10, false
        state.hooks.Think()
        local status = probe:Status()
        check(status.endedAfter == 10 and status.error == nil and not state.sound.playing
            and not state.anchors[1].valid, "observed completion is not reported as an unknown failure")
    end)
    suite:Add("continuous preview replaces ended steam without cutting audio", function(check)
        local state, probe = fixture()
        state.active = true
        check(not probe:Start("invalid"), "unknown preview modes are rejected")
        check(probe:Start("loop"), "loop preview starts")
        local anchor, sound = state.anchors[1], state.sound
        state.now, state.effects[1].valid = 5.8, false
        state.hooks.Think()
        check(probe:Status().active and probe:Status().replacements == 1 and #state.effects == 2
            and anchor.valid and sound.playing, "an ended burst is replaced without recreating audio")
        state.now, state.effects[2].valid = 11.6, false
        state.effectFailure = true
        state.hooks.Think()
        check(not probe:Status().active and type(probe:Status().error) == "string"
            and not anchor.valid and not sound.playing and #state.errors == 1,
            "replacement failure is surfaced and all owned resources are removed")
    end)
    suite:Add("shared particle instances move and reuse mounted precaches", function(check)
        local state, _, service, api = fixture()
        local definition = api.Catalog.Resolve("steam")
        local first = service.Create(definition, api.Vector(1, 2, 3), api.Angle(0, 0, 0), "continuous")
        local second = service.Create(definition, api.Vector(4, 5, 6), api.Angle(0, 0, 0), "triggered")
        check(first and second and #state.events == 4,
            "two instances load the particle file and precache only once")
        local position, angles = api.Vector(7, 8, 9), api.Angle(20, 30, 40)
        first:Move(position, angles)
        check(state.effects[1].control0 == position and state.effects[1].control1 == position
            and state.effects[1].orientation0 == angles and state.anchors[1].position == position,
            "moving updates both control points, direction and sound location")
        first:Stop()
        second:Stop()
        check(not state.anchors[1].valid and not state.anchors[2].valid
            and not state.effects[1].valid and not state.effects[2].valid,
            "independent instances release their owned resources")
    end)
    return suite
end
