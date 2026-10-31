return function(createTargeting)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { candidates = {}, blocked = {}, shots = {} }
        local vectorMeta = {}
        vectorMeta.__index = vectorMeta
        function vectorMeta.__sub(a, b)
            return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
        end
        function vectorMeta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
        function vectorMeta:DistToSqr(other) return (self - other):LengthSqr() end
        function vectorMeta:GetNormalized() return self end
        local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
        local function entity(class, x, id)
            local value = { valid = true, class = class, position = vector(x, 0, 0), health = 10, id = id }
            function value:GetClass() return self.class end
            function value:Health() return self.health end
            function value:WorldSpaceCenter() return self.position end
            function value:EntIndex() return self.id end
            return value
        end
        local shooter = entity("zn_prefab_guard", 0, 1)
        function shooter:FireBullets(bullet) state.shots[#state.shots + 1] = bullet end
        local targeting = createTargeting({
            IsValid = function(value) return type(value) == "table" and value.valid == true end,
            IsVector = function(value) return getmetatable(value) == vectorMeta end,
            Vector = vector, MASK_SHOT = 1,
            ents = { FindInSphere = function() return state.candidates end },
            util = { TraceLine = function(trace)
                if state.blocked[trace.endpos] then return {} end
                return { Entity = state.targetByPosition[trace.endpos] }
            end }
        })
        state.targetByPosition = {}
        function state:add(value)
            self.candidates[#self.candidates + 1] = value
            self.targetByPosition[value.position] = value
        end
        return state, targeting, shooter, entity, vector
    end

    suite:Add("guards select only visible, living zombies within range", function(check)
        local state, targeting, shooter, entity, vector = fixture()
        local player = entity("player", 1, 2)
        local blocked = entity("zn_walker_zombie", 5, 3)
        local dead = entity("zn_walker_zombie", 6, 4)
        local walker = entity("zn_walker_zombie", 10, 8)
        local boss = entity("zn_boss_zombie", 10, 7)
        local far = entity("zn_walker_zombie", 40, 9)
        dead.health = 0
        for _, candidate in ipairs({ player, blocked, dead, walker, boss, far }) do state:add(candidate) end
        state.blocked[blocked.position] = true
        check(targeting.Select(shooter, vector(0, 0, 0), 20) == boss,
            "nearest visible eligible target wins with stable entity-index tie-breaking")
        local result, problem = targeting.Select(shooter, vector(0, 0, 0), 0)
        check(result == nil and problem ~= nil, "invalid targeting range is reported")
    end)

    suite:Add("guard bullets can damage only the chosen live zombie", function(check)
        local state, targeting, shooter, entity, vector = fixture()
        local target = entity("zn_walker_zombie", 10, 2)
        local other = entity("zn_boss_zombie", 11, 3)
        local player = entity("player", 9, 4)
        state:add(target)
        local weapon = { damage = 24.5, spread = 0.04, force = 1, tracer = 0 }
        local ok = targeting.Fire(shooter, vector(0, 0, 0), target, 20, weapon)
        local bullet = state.shots[1]
        check(ok and bullet and bullet.Distance == 20 and bullet.Damage == 24.5
            and bullet.Spread.x == 0.04 and bullet.Spread.y == 0.04,
            "one bounded shot uses the selected damage and accuracy")
        check(bullet.Callback(shooter, { Entity = player }).damage == false
            and bullet.Callback(shooter, { Entity = other }).damage == false
            and bullet.Callback(shooter, { Entity = target }) == nil,
            "only the selected zombie can take bullet damage")
        target.health = 0
        check(bullet.Callback(shooter, { Entity = target }).damage == false,
            "a zombie that has already died is not damaged again")
        check(not targeting.Fire(shooter, vector(0, 0, 0), target, 20, weapon), "dead targets cannot be fired at")
        target.health = 10
        state.blocked[target.position] = true
        check(not targeting.Fire(shooter, vector(0, 0, 0), target, 20, weapon),
            "an obstruction suppresses the shot")
        check(not targeting.Fire(shooter, vector(0, 0, 0), target, 20,
            { damage = 0, spread = 0, force = 1 }), "invalid weapon parameters are rejected")
    end)
    return suite
end
