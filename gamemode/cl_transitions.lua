local gatePromptRange = 96

local function getNearbySafeZoneDoor()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or not playerEntity:Alive() then
        return nil
    end

    local nearestDoor
    local nearestDistance
    for _, entity in ipairs(ents.FindByClass("zn_safezone_door")) do
        if entity:GetNWBool("ZMSafeZoneDoor", false) then
            local radius = entity:GetNWFloat("ZMSafeZoneDoorRadius", gatePromptRange)
            local distance = playerEntity:GetPos():DistToSqr(entity:GetPos())
            if distance <= radius * radius and (nearestDistance == nil or distance < nearestDistance) then
                nearestDoor = entity
                nearestDistance = distance
            end
        end
    end
    return nearestDoor
end

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
    local safeZoneDoor = getNearbySafeZoneDoor()
    if safeZoneDoor then
        local role = safeZoneDoor:GetNWString("ZMSafeZoneDoorRole", "")
        local prompt = role == "enter" and "PRESS E TO ENTER SAFE ZONE" or "PRESS E TO EXIT SAFE ZONE"
        draw.SimpleText(prompt, "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, Color(92, 240, 154), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local gate = getNearbyTransitionGate()
    if not gate then
        return
    end

    local direction = string.upper(gate:GetNWString("ZMTransitionDirection", ""))
    local prompt = direction ~= "" and "PRESS E TO TRAVEL " .. direction or "PRESS E TO TRAVEL"
    draw.SimpleText(prompt, "DermaLarge", ScrW() * 0.5, ScrH() * 0.5 + 38, Color(92, 240, 154), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)