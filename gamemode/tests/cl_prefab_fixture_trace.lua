return function(createTrace)
    local Trace = createTrace({ IsValid = IsValid, Vector = Vector, Angle = Angle,
        LocalToWorld = LocalToWorld, util = util, MASK_SOLID = MASK_SOLID })
    concommand.Add("zombiesim_dev_prefab_fixture_trace_client", function(_, _, arguments)
    local requestId = arguments[1]
    local mode = arguments[2] or ""
    local target = LocalPlayer()
    if game.GetMap() ~= "zn_dev_prefab_anchor" or not IsValid(target) or not target:IsAdmin()
        or not target:GetNWBool("ZM.PrefabEditorActive", false)
        or type(requestId) ~= "string" or not string.match(requestId, "^%d+$")
        or (mode ~= "" and mode ~= "activate_client") then
        ErrorNoHalt("[ZombieSim] Prefab fixture trace requires its preview admin and a request ID.\n")
        return
    end
    local samples, errors = {}, {}
    for _, entity in ipairs(ents.FindByClass("prop_physics")) do
        if entity:GetModel() == "models/props_c17/oildrum001.mdl" then
            if mode == "activate_client" then entity:Activate() end
            local sample, problem = Trace.Sample(entity)
            if sample then samples[#samples + 1] = sample else errors[#errors + 1] = tostring(problem) end
        end
    end
    if #samples ~= 10 then errors[#errors + 1] = "Expected ten fixture props; found " .. #samples .. "." end
    local report = { requestId = requestId, mode = mode, map = game.GetMap(), samples = samples, errors = errors }
    file.CreateDir("zombiesim")
    local encoded = util.TableToJSON(report, true)
    if type(encoded) ~= "string" or not file.Write("zombiesim/prefab-fixture-client-trace.json", encoded) then
        ErrorNoHalt("[ZombieSim] Could not write the prefab fixture client trace.\n")
        return
    end
    print(string.format("[ZombieSim] Prefab fixture client trace: %d samples, %d errors.", #samples, #errors))
    for _, problem in ipairs(errors) do print("[ZombieSim] Prefab fixture trace: " .. problem) end
    end)
end
