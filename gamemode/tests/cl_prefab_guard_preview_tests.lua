return function(createPreview)
    local suite = ZM_TestHarness.NewSuite()

    local function fixture()
        local state = { models = {}, timers = {}, errors = {}, failAt = nil }
        local vectors = {}
        vectors.__index = vectors
        function vectors.__add(a, b)
            return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vectors)
        end
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectors) end
        local api = {
            IsValid = function(value) return type(value) == "table" and value.valid == true end,
            IsVector = function(value) return getmetatable(value) == vectors end,
            Vector = vector, Angle = function(p, y, r) return { p = p, y = y, r = r } end,
            EF_BONEMERGE = 1, RENDERGROUP_OTHER = 0,
            Report = function(message) state.errors[#state.errors + 1] = message end,
            timer = { Simple = function(_, callback) state.timers[#state.timers + 1] = callback end }
        }
        api.ClientsideModel = function(path)
            if #state.models + 1 == state.failAt then return nil end
            local model = { valid = true, path = path }
            function model:SetNoDraw(value) self.hidden = value end
            function model:GetModel() return self.path end
            function model:SetPos(value) self.position = value end
            function model:SetAngles(value) self.angles = value end
            function model:GetParent() return self.parent end
            function model:SetParent(value) self.parent = value end
            function model:AddEffects(value) self.effects = value end
            function model:SetLocalPos(value) self.localPosition = value end
            function model:SetLocalAngles(value) self.localAngles = value end
            function model:LookupSequence(value) return value == "idle_all_01" and 2 or -1 end
            function model:ResetSequence(value) self.sequence = value end
            function model:FrameAdvance() self.advanced = (self.advanced or 0) + 1 end
            function model:DrawModel() self.drawn = true end
            function model:Remove() self.valid = false end
            state.models[#state.models + 1] = model
            return model
        end
        local guard = {
            model = "models/player/group01/male_03.mdl", idle = "idle_all_01", shirt = "shirt_a", pants = "pants_a",
            position = { x = 10, y = 20, z = 30 }, angles = { p = 0, y = 90, r = 0 }
        }
        return state, createPreview(api), guard, vector
    end

    suite:Add("guard previews share their outfit and clean up their owned models", function(check)
        local state, preview, guard, vector = fixture()
        local instance, problem = preview:Create(guard, { model = "models/weapons/w_pistol.mdl" }, vector(1, 2, 3))
        check(instance ~= nil, "preview creates both models: " .. tostring(problem))
        check(instance and instance.model.hidden and instance.weapon.hidden and instance.weapon.parent == instance.model
            and instance.weapon.effects == 1, "the preview weapon is bone-merged and both models are manually drawn")
        check(instance and instance.model.position.x == 11 and instance.model.position.y == 22
            and instance.model.position.z == 33 and instance.model.angles.y == 90, "local transform uses the preview origin")
        state.timers[1]()
        check(instance.model.sequence == 2, "the idle sequence is applied on the next tick")
        local selections = preview:ClothingSelections()
        check(#selections == 1 and selections[1].entity == instance.model
            and selections[1].shirt == "shirt_a" and selections[1].pants == "pants_a",
            "outfit data can join the existing clothing queue")
        preview:Advance(instance)
        local ok = preview:Draw(instance)
        check(ok and instance.model.drawn and instance.weapon.drawn and instance.model.advanced == 1,
            "both models draw and the guard animation advances")
        instance.weapon.parent = nil
        guard.position.z, guard.shirt = 40, "shirt_b"
        check(preview:Update(instance, guard, vector(1, 2, 3)) and instance.weapon.parent == instance.model
            and instance.model.position.z == 43 and preview:ClothingSelections()[1].shirt == "shirt_b",
            "movement, changed clothing and a detached weapon are reconciled")
        preview:Remove(instance)
        check(not state.models[1].valid and not state.models[2].valid and #preview:ClothingSelections() == 0,
            "removal releases both models and their clothing request")
    end)

    suite:Add("guard preview failures are reported without leaking models", function(check)
        local state, preview, guard, vector = fixture()
        state.failAt = 2
        local instance, problem = preview:Create(guard, { model = "missing.mdl" }, vector(0, 0, 0))
        check(not instance and type(problem) == "string" and not state.models[1].valid,
            "weapon creation failure removes the guard model")
        state.failAt = nil
        instance = preview:Create(guard, { model = "weapon.mdl" }, vector(0, 0, 0))
        guard.idle = "missing"
        check(preview:Update(instance, guard, vector(0, 0, 0)), "invalid animation can be reported asynchronously")
        state.timers[#state.timers]()
        check(#state.errors == 1, "unsupported animation is explicitly reported")
        local pending = #state.timers
        guard.idle = "idle_all_01"
        check(preview:Update(instance, guard, vector(0, 0, 0)), "a corrected animation schedules an update")
        preview:Remove(instance)
        state.timers[pending + 1]()
        check(not instance.model.valid and #state.errors == 1, "a stale callback cannot revive a removed model")
    end)
    suite:Add("a model panel can own the guard body without drawing it twice", function(check)
        local state, preview, guard, vector = fixture()
        local body = {
            valid = true, path = guard.model,
            GetModel = function(self) return self.path end,
            SetNoDraw = function(self, value) self.hidden = value end,
            SetPos = function(self, value) self.position = value end,
            SetAngles = function(self, value) self.angles = value end,
            DrawModel = function(self) self.drawn = true end,
            Remove = function(self) self.valid = false end
        }
        local instance = preview:Create(guard, { model = "weapon.mdl" }, vector(0, 0, 0), body)
        check(instance and instance.model == body and instance.weapon.parent == body,
            "the model-panel body is reused as the weapon parent")
        check(preview:Draw(instance, true) and not body.drawn and instance.weapon.drawn,
            "the panel draws its body once and the helper draws only the weapon")
        preview:Remove(instance)
        state.timers[1]()
        check(not body.valid and not instance.weapon.valid, "panel-model cleanup releases the entire preview")
    end)
    return suite
end
