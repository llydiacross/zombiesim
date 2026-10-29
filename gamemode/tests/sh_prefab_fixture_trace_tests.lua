return function(createTrace)
    local suite = ZM_TestHarness.NewSuite()
    suite:Add("fixture trace measures the scaled model midpoint and reports misses", function(check)
        local state = {}
        local vectorMeta = { __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, getmetatable(a)) end }
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local entity = {}
        function entity:GetPos() return vector(100, 200, 300) end
        function entity:GetModelBounds() return vector(-10, -10, 0), vector(10, 10, 40) end
        function entity:GetModelScale() return 0.5 end
        function entity:GetAngles() return { p = 0, y = 0, r = 0 } end
        function entity:EntIndex() return 17 end
        local trace = createTrace({
            IsValid = function(value) return value == entity end, Vector = vector, MASK_SOLID = 5,
            Angle = function() return {} end,
            LocalToWorld = function(offset, _, origin) return origin + offset end,
            util = { TraceLine = function(request)
                state.request = request
                return { Hit = state.hit ~= false, Entity = entity, StartSolid = false, HitPos = vector(105, 200, 310) }
            end }
        })
        local sample = trace.Sample(entity)
        check(sample and sample.entity == 17 and sample.scale == 0.5 and sample.extent == 5,
            "trace reports the entity, visible scale and measured collision extent")
        check(state.request.start.z == 310 and state.request.start.x == 612
            and state.request.whitelist and state.request.filter[1] == entity and state.request.ignoreworld,
            "trace uses the model midpoint and isolates the test entity")
        state.hit = false
        local missing, problem = trace.Sample(entity)
        check(not missing and type(problem) == "string", "a missing collision hit is reported")
        missing, problem = trace.Sample(nil)
        check(not missing and type(problem) == "string", "an invalid entity is reported")
    end)
    return suite
end
