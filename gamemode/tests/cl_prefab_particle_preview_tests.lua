return function(createPreview)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { now = 0, hooks = {}, created = {}, messages = {} }
        local vectorMeta = { __add = function(a, b)
            return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a))
        end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local editor = { active = true, Origin = vector(100, 200, 300), PrefabPreviewOffset = 0,
            Document = { particles = {} } }
        function editor:IsActive() return self.active end
        function editor:GetPreviewOrigin() return self.Origin + vector(0, 0, self.PrefabPreviewOffset) end
        function editor:Message(message, problem) state.messages[#state.messages + 1] = { message, problem } end
        local catalog = { Resolve = function(id)
            if id ~= "steam" then return nil, "Unknown effect." end
            return { id = id }
        end }
        local service = { Create = function(definition, position, angles, mode)
            if state.fail then return nil, "Allocation failed." end
            local handle = { definition = definition, position = position, angles = angles, mode = mode, active = true }
            function handle:Stop() self.active = false; self.stopped = true end
            function handle:Move(value, angle) self.position, self.angles, self.moves = value, angle, (self.moves or 0) + 1 end
            function handle:Update()
                if self.problem then self:Stop(); return false, self.problem end
                return self.active
            end
            state.created[#state.created + 1] = handle
            return handle
        end }
        local preview = createPreview({
            GetEditor = function() return editor end, Vector = vector,
            Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            RealTime = function() return state.now end,
            ErrorNoHalt = function(message) state.messages[#state.messages + 1] = { message, true } end,
            hook = { Add = function(event, _, callback) state.hooks[event] = callback end }
        }, catalog, service)
        local function particle(id, mode, overlap)
            return { particleId = id, effect = "steam", position = { x = 1, y = 2, z = 3 },
                angles = { p = 4, y = 5, r = 6 }, mode = mode, overlap = overlap }
        end
        return state, editor, preview, particle
    end
    suite:Add("continuous particles move and clean up with the editor", function(check)
        local state, editor, preview, particle = fixture()
        editor.Document.particles = { particle("a", "continuous", true) }
        state.hooks.Think()
        local first = state.created[1]
        check(first and first.mode == "continuous" and first.position.x == 101
            and preview:Status().continuous == 1, "continuous particle creates at its workspace transform")
        state.hooks.Think()
        check(#state.created == 1 and not first.moves, "unchanged particles do not rebuild or move")
        editor.Document.particles[1].position.x = 8
        editor.Document.particles[1].angles.y = 90
        state.hooks.Think()
        check(first.moves == 1 and first.position.x == 108 and first.angles.y == 90,
            "editing moves the existing particle and sound")
        editor.Document.particles = {}
        state.hooks.Think()
        check(first.stopped and preview:Status().continuous == 0, "deleting an effect cleans it up")
        editor.Document.particles = { particle("b", "continuous", true) }
        state.hooks.Think()
        editor.active = false
        state.hooks.Think()
        check(state.created[2].stopped, "closing the editor cleans up the active effect")
    end)
    suite:Add("triggered particles honor overlap without a fixed cap", function(check)
        local state, editor, preview, particle = fixture()
        local effect = particle("a", "triggered", true)
        editor.Document.particles = { effect }
        state.hooks.Think()
        check(#state.created == 0, "triggered effects do not start on document load")
        for _ = 1, 40 do check(preview:Trigger("a"), "overlapping trigger starts") end
        check(preview:Status().bursts == 40 and #state.created == 40,
            "overlap has no fixed simultaneous-effect cap")
        effect.overlap = false
        check(preview:Trigger("a") and preview:Status().bursts == 1,
            "overlap off restarts rather than layering")
        check(state.created[1].stopped and state.created[40].stopped and not state.created[41].stopped,
            "restart stops all previous bursts and keeps the new one")
        state.created[41].active = false
        state.hooks.Think()
        check(preview:Status().bursts == 0, "completed bursts leave the active set")
        effect.overlap = true
        check(preview:Trigger("a"), "a new burst can start")
        effect.mode = "continuous"
        state.hooks.Think()
        check(state.created[42].stopped and preview:Status().bursts == 0
            and preview:Status().continuous == 1, "changing to continuous mode stops old triggered bursts")
    end)
    suite:Add("preview height moves continuous and existing triggered effects", function(check)
        local state, editor, preview, particle = fixture()
        local continuous = particle("a", "continuous", true)
        local triggered = particle("b", "triggered", true)
        editor.Document.particles = { continuous, triggered }
        state.hooks.Think()
        check(preview:Trigger("b"), "triggered effect starts")
        local first, burst = state.created[1], state.created[2]
        triggered.position.z = 8
        editor.PrefabPreviewOffset = 25
        state.hooks.Think()
        check(first.position.z == 328 and first.moves == 1 and burst.position.z == 328 and burst.moves == 1,
            "both effects move by the preview offset without relocating an existing burst to the edited emitter")
        check(continuous.position.z == 3 and triggered.position.z == 8,
            "preview movement leaves saved particle positions unchanged")
        check(preview:Trigger("b") and state.created[3].position.z == 333,
            "new triggers use the edited local position and current preview offset")
        state.hooks.PreCleanupMap()
        check(first.stopped and burst.stopped and state.created[3].stopped, "cleanup stops all offset effects")
    end)
    suite:Add("preview failures are explicit and retry without repeated notifications", function(check)
        local state, editor, preview, particle = fixture()
        editor.Document.particles = { particle("a", "continuous", true) }
        state.fail = true
        state.hooks.Think()
        state.hooks.Think()
        check(#state.messages == 1 and preview:Status().errors.a == "Allocation failed.",
            "allocation failure is shown once and recorded")
        state.now, state.fail = 3, false
        state.hooks.Think()
        check(#state.created == 1 and preview:Status().errors.a == nil, "failed creation retries")
        state.created[1].problem = "Runtime failure."
        state.hooks.Think()
        check(#state.messages == 2 and preview:Status().continuous == 0,
            "runtime failure is surfaced rather than silently dropped")
        check(not preview:Trigger("a"), "continuous effects cannot be triggered")
        state.hooks.PreCleanupMap()
        check(preview:Status().continuous == 0 and preview:Status().bursts == 0, "map cleanup clears the preview")
    end)
    return suite
end
