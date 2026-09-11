local gatePromptRange = 96

local function getNearbyTransitionGate()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive() then
        return nil
    end

    local nearestGate
    local nearestDistance = gatePromptRange * gatePromptRange
    for _, entity in ipairs(ents.FindByClass("trigger_multiple")) do
        if entity:GetNWBool("ZMTransitionGate", false) then
            local distance = playerEntity:GetPos():DistToSqr(entity:NearestPoint(playerEntity:GetPos()))
            if distance <= nearestDistance then
                nearestGate = entity
                nearestDistance = distance
            end
        end
    end
    return nearestGate
end

hook.Add("HUDPaint", "ZM.TransitionGatePrompt", function()
    local gate = getNearbyTransitionGate()
    if not gate then
        return
    end

    local direction = string.upper(gate:GetNWString("ZMTransitionDirection", ""))
    local prompt = direction ~= "" and "PRESS E TO TRAVEL " .. direction or "PRESS E TO TRAVEL"
    draw.SimpleText(prompt, "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, Color(92, 240, 154), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)