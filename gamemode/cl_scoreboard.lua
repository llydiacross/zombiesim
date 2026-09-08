// Survivor roster and profile scoreboard opened from the quick menu.
ZM_Scoreboard = ZM_Scoreboard or {}
local Scoreboard = ZM_Scoreboard

surface.CreateFont("ZM_ScoreboardHeading", {
    font = "Trebuchet MS",
    size = 24,
    weight = 900,
    antialias = true
})

surface.CreateFont("ZM_ScoreboardName", {
    font = "Trebuchet MS",
    size = 18,
    weight = 800,
    antialias = true
})

surface.CreateFont("ZM_ScoreboardLabel", {
    font = "Trebuchet MS",
    size = 11,
    weight = 800,
    antialias = true
})

surface.CreateFont("ZM_ScoreboardValue", {
    font = "Trebuchet MS",
    size = 15,
    weight = 700,
    antialias = true
})

local scoreboardColors = {
    teal = Color(35, 187, 151),
    tealDark = Color(16, 91, 77),
    amber = Color(232, 172, 54),
    slate = Color(38, 44, 51)
}

local scoreboardIcons = {
    chart = Material("icon16/chart_bar.png", "smooth"),
    close = Material("icon16/cross.png", "smooth"),
    heart = Material("icon16/heart.png", "smooth"),
    lightning = Material("icon16/lightning.png", "smooth"),
    map = Material("icon16/map.png", "smooth"),
    pencil = Material("icon16/pencil.png", "smooth"),
    skills = Material("icon16/gun.png", "smooth"),
    world = Material("icon16/world.png", "smooth"),
    headerBackground = Material("scoreboard/info_header_background.png", "smooth"),
    headerDetail = Material("scoreboard/info_header_detail.png", "smooth")
}

local function drawScoreboardIcon(icon, x, y, size, color)
    surface.SetDrawColor(color or color_white)
    surface.SetMaterial(icon)
    surface.DrawTexturedRect(x, y, size, size)
end

local function openScoreboardOverlay(owner)
    if IsValid(owner.Frame) then
        owner.Frame:MakePopup()
        return owner.Frame
    end

    local frame = vgui.Create("DPanel")
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetMouseInputEnabled(true)
    frame:SetKeyboardInputEnabled(true)
    frame.Paint = function(_, width, height)
        surface.SetDrawColor(0, 0, 0, 190)
        surface.DrawRect(0, 0, width, height)
    end
    frame:MakePopup()
    frame.OnRemove = function()
        if owner.Frame == frame then owner.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    owner.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end
    return frame
end

local function relationshipId(playerEntity)
    if not IsValid(playerEntity) then
        return nil
    end
    if playerEntity:IsBot() then
        return "bot_" .. playerEntity:EntIndex()
    end
    local steamId = playerEntity:SteamID64()
    return steamId ~= "" and steamId or "entity_" .. playerEntity:EntIndex()
end

function Scoreboard:GetRelationship(playerEntity)
    local playerId = relationshipId(playerEntity)
    return playerId and cookie.GetString("zombiesim_scoreboard_relationship_" .. playerId, "") or ""
end

function Scoreboard:SetRelationship(playerEntity, relationship)
    local playerId = relationshipId(playerEntity)
    if not playerId then
        return
    end
    local current = self:GetRelationship(playerEntity)
    cookie.Set("zombiesim_scoreboard_relationship_" .. playerId, current == relationship and "" or relationship)
end

local function survivorStatus(playerEntity)
    if playerEntity == LocalPlayer() then
        return "YOU", scoreboardColors.teal
    end
    if playerEntity:IsBot() then
        return "BOT", scoreboardColors.amber
    end
    if not playerEntity:Alive() then
        return "DOWN", ZM_DermaSkin.Palette.redBright
    end
    return "ACTIVE", scoreboardColors.teal
end

local function drawScoreboardMetric(x, y, width, label, value, color, icon)
    local palette = ZM_DermaSkin.Palette
    local textOffset = icon and 20 or 0
    if icon then
        drawScoreboardIcon(icon, x, y + 4, 14, color or palette.muted)
    end
    draw.SimpleText(label, "ZM_ScoreboardLabel", x + textOffset, y, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(value, "ZM_ScoreboardValue", x + textOffset, y + 15, color or palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    surface.SetDrawColor(scoreboardColors.slate)
    surface.DrawRect(x, y + 38, width, 1)
end

local function getScoreboardValueColor(value)
    local numericValue = math.max(0, tonumber(value) or 0)
    local palette = ZM_DermaSkin.Palette
    if numericValue == 0 then
        return palette.muted
    end

    local progress = math.Clamp((numericValue - 1) / 9, 0, 1)
    return Color(
        math.floor(Lerp(progress, palette.redBright.r, scoreboardColors.teal.r) + 0.5),
        math.floor(Lerp(progress, palette.redBright.g, scoreboardColors.teal.g) + 0.5),
        math.floor(Lerp(progress, palette.redBright.b, scoreboardColors.teal.b) + 0.5)
    )
end

local function drawAttributeCell(x, y, width, label, value)
    local palette = ZM_DermaSkin.Palette
    surface.SetDrawColor(palette.black)
    surface.DrawRect(x, y, width, 38)
    surface.SetDrawColor(scoreboardColors.slate)
    surface.DrawOutlinedRect(x, y, width, 38, 1)
    draw.SimpleText(label, "ZM_ScoreboardLabel", x + 8, y + 5, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(tostring(value), "ZM_ScoreboardValue", x + width - 8, y + 16, getScoreboardValueColor(value), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

local function getBioPreview(bio)
    bio = string.Trim(tostring(bio or ""))
    if bio == "" then
        return "No bio recorded."
    end
    if string.len(bio) > 64 then
        return string.sub(bio, 1, 61) .. "..."
    end
    return bio
end

local function getCurrentSafeZoneName(playerEntity)
    local safeZoneId = playerEntity:GetNWString("CurrentSafeZoneId", "")
    if safeZoneId == "" then
        return "NOT IN A SAFE ZONE", ZM_DermaSkin.Palette.muted
    end

    local safeZone = ZM_World and ZM_World:GetSafeZoneById(safeZoneId) or nil
    if safeZone and type(safeZone.name) == "string" and safeZone.name ~= "" then
        return safeZone.name, scoreboardColors.teal
    end
    return "SAFE ZONE UNRESOLVED", ZM_DermaSkin.Palette.redBright
end

function Scoreboard:Open()
    local frame = openScoreboardOverlay(self)
    if frame.ScoreboardBuilt then
        return
    end
    frame.ScoreboardBuilt = true

    local root = vgui.Create("DPanel", frame)
    root:SetSize(math.min(1120, ScrW() - 40), math.min(720, ScrH() - 40))
    root:Center()
    root:SetKeyboardInputEnabled(true)
    root.Paint = function(_, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local header = vgui.Create("DPanel", root)
    header:Dock(TOP)
    header:SetTall(78)
    header:DockMargin(0, 0, 0, 8)
    header.Paint = function(_, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(palette.redDark)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.red)
        surface.DrawRect(0, height - 3, width, 3)
        draw.SimpleText("SCOREBOARD", "ZM_ScoreboardHeading", 18, 13, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Z-Nation", "ZM_ScoreboardLabel", 20, 45, palette.redBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.format("%02d CONNECTED", #player.GetAll()), "ZM_ScoreboardValue", width - 60, 20, scoreboardColors.teal, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        draw.SimpleText(LocalPlayer():GetName(), "ZM_ScoreboardLabel", width - 60, 46, palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end

    local close = vgui.Create("DButton", header)
    close:SetText("")
    close:SetTooltip("Close scoreboard")
    close:SetSize(36, 36)
    close:SetPos(header:GetWide() - 48, 20)
    close.Paint = function(currentButton, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(currentButton.Hovered and palette.redBright or palette.red)
        surface.DrawRect(0, 0, width, height)
        drawScoreboardIcon(scoreboardIcons.close, 10, 10, width - 20, palette.text)
    end
    close.DoClick = function()
        frame:Remove()
    end
    header.PerformLayout = function(currentHeader, width)
        close:SetPos(width - 48, 20)
    end

    local roster = vgui.Create("DPanel", root)
    roster:Dock(LEFT)
    roster:SetWide(360)
    roster:DockMargin(0, 0, 10, 0)
    roster.Paint = function(_, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    local rosterTitle = vgui.Create("DPanel", roster)
    rosterTitle:Dock(TOP)
    rosterTitle:SetTall(42)
    rosterTitle.Paint = function(_, width, height)
        draw.SimpleText("PLAYERS", "ZM_ScoreboardValue", 14, 10, ZM_DermaSkin.Palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("SELECT A SURVIVOR", "ZM_ScoreboardLabel", width - 14, 14, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(scoreboardColors.slate)
        surface.DrawRect(12, height - 1, width - 24, 1)
    end

    local rosterScroll = vgui.Create("DScrollPanel", roster)
    rosterScroll:Dock(FILL)
    rosterScroll:DockMargin(7, 4, 7, 7)

    local dossier = vgui.Create("DPanel", root)
    dossier:Dock(FILL)
    dossier:SetKeyboardInputEnabled(true)
    dossier.Paint = function(_, width, height)
        local palette = ZM_DermaSkin.Palette
        local playerEntity = frame.SelectedPlayer
        surface.SetDrawColor(palette.panel)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        if not IsValid(playerEntity) then
            draw.SimpleText("NO SURVIVOR SELECTED", "ZM_ScoreboardHeading", width * 0.5, height * 0.5, palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local status, statusColor = survivorStatus(playerEntity)
        local health = math.max(0, playerEntity:Health())
        local maximumHealth = math.max(1, playerEntity:GetMaxHealth())
        local stamina = math.Clamp(playerEntity:GetNWFloat("Stamina", 100), 0, 100)
        local cellX = playerEntity:GetNWInt("CellX", 0)
        local cellY = playerEntity:GetNWInt("CellY", 0)
        local relation = Scoreboard:GetRelationship(playerEntity)

        local headerX = 14
        local headerY = 14
        local headerWidth = width - 28
        local headerHeight = 125
        local xpX = 140
        local modelLeft = width - 124
        local xpWidth = math.max(80, modelLeft - xpX - 18)
        local experiencePerLevel = math.max(1, tonumber(playerEntity.ExperiencePerLevel) or 1000)
        local experience = math.Clamp(playerEntity:GetNWInt("XP", 0), 0, experiencePerLevel)
        local experienceProgress = experience / experiencePerLevel

        surface.SetDrawColor(palette.raised)
        surface.DrawRect(headerX, headerY, headerWidth, headerHeight)
        surface.SetMaterial(scoreboardIcons.headerBackground)
        surface.SetDrawColor(255, 255, 255, 70)
        surface.DrawTexturedRect(headerX, headerY, headerWidth, headerHeight)
        surface.SetMaterial(scoreboardIcons.headerDetail)
        surface.SetDrawColor(255, 255, 255, 225)
        surface.DrawTexturedRect(headerX, headerY, headerWidth, headerHeight)
        surface.SetDrawColor(statusColor)
        surface.DrawRect(headerX, headerY, 5, headerHeight)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(headerX, headerY, headerWidth, headerHeight, 1)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(20, 20, 108, 108)
        surface.SetDrawColor(statusColor)
        surface.DrawOutlinedRect(20, 20, 108, 108, 1)
        draw.SimpleText(playerEntity:Nick(), "ZM_ScoreboardHeading", 140, 26, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(status, "ZM_ScoreboardLabel", 142, 55, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.format("LEVEL %03d / %03d  //  %s", playerEntity:GetNWInt("Level", 1), playerEntity:GetNWInt("MaxLevel", 1), playerEntity:IsBot() and "AUTOMATED CONTACT" or "SURVIVOR"), "ZM_ScoreboardValue", 140, 73, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(palette.black)
        surface.DrawRect(xpX, 88, xpWidth, 8)
        surface.SetDrawColor(scoreboardColors.slate)
        surface.DrawOutlinedRect(xpX, 88, xpWidth, 8, 1)
        surface.SetDrawColor(scoreboardColors.teal)
        surface.DrawRect(xpX + 1, 89, math.floor((xpWidth - 2) * experienceProgress), 6)
        draw.SimpleText(string.format("PING %d MS", math.max(0, playerEntity:Ping())), "ZM_ScoreboardLabel", 142, 99, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if relation ~= "" then
            local relationColor = relation == "ally" and scoreboardColors.teal or palette.redBright
            draw.SimpleText(string.upper(relation) .. " MARKED", "ZM_ScoreboardLabel", width - 142, 34, relationColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end

        drawScoreboardMetric(28, 153, (width - 84) * 0.5, "HEALTH", string.format("%d / %d", health, maximumHealth), health > maximumHealth * 0.3 and scoreboardColors.teal or palette.redBright, scoreboardIcons.heart)
        drawScoreboardMetric(width * 0.5 + 14, 153, (width - 84) * 0.5, "STAMINA", string.format("%d%%", stamina), scoreboardColors.amber, scoreboardIcons.lightning)
        drawScoreboardMetric(28, 203, (width - 84) * 0.5, "WORLD CELL", string.format("%d, %d", cellX, cellY), palette.text, scoreboardIcons.world)
        local safeZoneName, safeZoneColor = getCurrentSafeZoneName(playerEntity)
        drawScoreboardMetric(width * 0.5 + 14, 203, (width - 84) * 0.5, "CURRENT SAFE ZONE", safeZoneName, safeZoneColor, scoreboardIcons.map)

        drawScoreboardIcon(scoreboardIcons.chart, 28, 255, 12, palette.muted)
        draw.SimpleText("CORE ATTRIBUTES", "ZM_ScoreboardLabel", 44, 255, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local attributeWidth = math.floor((width - 70) * 0.25)
        local attributeX = { 28, 38 + attributeWidth, 48 + attributeWidth * 2, 58 + attributeWidth * 3 }
        drawAttributeCell(attributeX[1], 271, attributeWidth, "STRENGTH", playerEntity:GetNWInt("Strength", 0))
        drawAttributeCell(attributeX[2], 271, attributeWidth, "AGILITY", playerEntity:GetNWInt("Agility", 0))
        drawAttributeCell(attributeX[3], 271, attributeWidth, "INTELLIGENCE", playerEntity:GetNWInt("Intelligence", 0))
        drawAttributeCell(attributeX[4], 271, attributeWidth, "ENDURANCE", playerEntity:GetNWInt("Endurance", 0))

        drawScoreboardIcon(scoreboardIcons.skills, 28, 325, 12, palette.muted)
        draw.SimpleText("SPECIALIST SKILLS", "ZM_ScoreboardLabel", 44, 325, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local skillWidth = math.floor((width - 76) / 5)
        local skillX = { 28, 40 + skillWidth, 52 + skillWidth * 2, 64 + skillWidth * 3, 76 + skillWidth * 4 }
        drawAttributeCell(skillX[1], 341, skillWidth, "MACHINE GUNS", playerEntity:GetNWInt("MachineGuns", 0))
        drawAttributeCell(skillX[2], 341, skillWidth, "SHOTGUNS", playerEntity:GetNWInt("Shotguns", 0))
        drawAttributeCell(skillX[3], 341, skillWidth, "SNIPERS", playerEntity:GetNWInt("Snipers", 0))
        drawAttributeCell(skillX[4], 341, skillWidth, "WEAPON CRAFT", playerEntity:GetNWInt("WeaponCrafting", 0))
        drawAttributeCell(skillX[5], 341, skillWidth, "ARMOR CRAFT", playerEntity:GetNWInt("ArmorCrafting", 0))
        drawAttributeCell(skillX[1], 385, skillWidth, "MEDICINE", playerEntity:GetNWInt("Medicine", 0))
        drawAttributeCell(skillX[2], 385, skillWidth, "FARMING", playerEntity:GetNWInt("Farming", 0))
        drawAttributeCell(skillX[3], 385, skillWidth, "WEAPON REPAIR", playerEntity:GetNWInt("WeaponRepairing", 0))
        drawAttributeCell(skillX[4], 385, skillWidth, "ARMOR REPAIR", playerEntity:GetNWInt("ArmorRepairing", 0))
        drawAttributeCell(skillX[5], 385, skillWidth, "MECHANICS", playerEntity:GetNWInt("Mechanics", 0))

        if playerEntity == LocalPlayer() then
            drawScoreboardIcon(scoreboardIcons.pencil, 28, 429, 12, palette.muted)
            draw.SimpleText("SURVIVOR BIO", "ZM_ScoreboardLabel", 44, 429, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(getBioPreview(playerEntity:GetNWString("PlayerBio", "")), "ZM_ScoreboardValue", 28, 451, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            surface.SetDrawColor(scoreboardColors.slate)
            surface.DrawRect(28, 435, width - 56, 1)
            draw.SimpleText("RELATIONSHIP", "ZM_ScoreboardLabel", 28, 447, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Local marker only", "ZM_ScoreboardValue", 28, 463, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    local profileAvatar = vgui.Create("AvatarImage", dossier)
    profileAvatar:SetSize(104, 104)
    profileAvatar:SetPos(22, 22)

    local modelPreview = vgui.Create("DModelPanel", dossier)
    modelPreview:SetSize(96, 110)
    modelPreview:SetFOV(28)
    modelPreview:SetCamPos(Vector(80, 0, 52))
    modelPreview:SetLookAt(Vector(0, 0, 42))
    modelPreview.LayoutEntity = function(_, modelEntity)
        modelEntity:SetAngles(Angle(0, 32, 0))
    end

    local function createSocialButton(label, color)
        local button = vgui.Create("DButton", dossier)
        button:SetText("")
        button.Paint = function(currentButton, width, height)
            local active = currentButton.Hovered or currentButton:IsDown()
            local disabled = currentButton:GetDisabled()
            surface.SetDrawColor(disabled and ZM_DermaSkin.Palette.black or (active and color or scoreboardColors.slate))
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(disabled and scoreboardColors.slate or color)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(currentButton.Label, "ZM_ScoreboardValue", width * 0.5, height * 0.5, disabled and ZM_DermaSkin.Palette.muted or ZM_DermaSkin.Palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.Label = label
        return button
    end

    local allyButton = createSocialButton("MARK ALLY", scoreboardColors.tealDark)
    local blockButton = createSocialButton("BLOCK", ZM_DermaSkin.Palette.redDark)
    allyButton:SetTooltip("Local relationship marker. Server alliance requests can replace this action later.")
    blockButton:SetTooltip("Local relationship marker. Server blocking can replace this action later.")
    allyButton.DoClick = function()
        if IsValid(frame.SelectedPlayer) and frame.SelectedPlayer ~= LocalPlayer() then
            Scoreboard:SetRelationship(frame.SelectedPlayer, "ally")
            surface.PlaySound("buttons/button15.wav")
        end
    end
    blockButton.DoClick = function()
        if IsValid(frame.SelectedPlayer) and frame.SelectedPlayer ~= LocalPlayer() then
            Scoreboard:SetRelationship(frame.SelectedPlayer, "blocked")
            surface.PlaySound("buttons/button10.wav")
        end
    end

    local bioButton = vgui.Create("DButton", dossier)
    bioButton:SetText("")
    bioButton:SetTooltip("Edit survivor bio")
    bioButton:SetVisible(false)
    bioButton.Paint = function(currentButton, width, height)
        local palette = ZM_DermaSkin.Palette
        surface.SetDrawColor(palette.black)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(scoreboardColors.slate)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        drawScoreboardIcon(scoreboardIcons.pencil, 13, 13, 16, palette.muted)
    end

    bioButton.DoClick = function()
        if frame.SelectedPlayer ~= LocalPlayer() or IsValid(frame.BioEditor) then
            return
        end

        local editor = vgui.Create("DFrame", frame)
        editor:SetSkin("ZombieSim")
        editor:SetTitle("EDIT SURVIVOR BIO")
        editor:SetSize(math.min(560, ScrW() - 80), math.min(320, ScrH() - 80))
        editor:Center()
        editor:MakePopup()
        editor.OnRemove = function()
            if frame.BioEditor == editor then
                frame.BioEditor = nil
            end
        end
        frame.BioEditor = editor

        local actions = vgui.Create("DPanel", editor)
        actions:Dock(BOTTOM)
        actions:SetTall(52)
        actions:DockMargin(10, 0, 10, 10)
        actions.Paint = function() end

        local cancel = vgui.Create("DButton", actions)
        cancel:Dock(RIGHT)
        cancel:SetWide(110)
        cancel:SetText("CANCEL")
        cancel.DoClick = function()
            editor:Remove()
        end

        local save = vgui.Create("DButton", actions)
        save:Dock(RIGHT)
        save:DockMargin(0, 0, 8, 0)
        save:SetWide(110)
        save:SetText("SAVE BIO")

        local bioInput = vgui.Create("DTextEntry", editor)
        bioInput:Dock(FILL)
        bioInput:DockMargin(10, 10, 10, 8)
        bioInput:SetMultiline(true)
        bioInput:SetEditable(true)
        bioInput:SetText(LocalPlayer():GetNWString("PlayerBio", ""))
        bioInput:RequestFocus()

        save.DoClick = function()
            net.Start("ZM.UpdatePlayerBio")
                net.WriteString(bioInput:GetValue())
            net.SendToServer()
            surface.PlaySound("buttons/button14.wav")
            editor:Remove()
        end
    end

    dossier.PerformLayout = function(_, width)
        local buttonWidth = math.min(170, math.max(112, math.floor((width - 92) * 0.25)))
        modelPreview:SetPos(width - 124, 17)
        allyButton:SetSize(buttonWidth, 40)
        allyButton:SetPos(width - buttonWidth * 2 - 40, 441)
        blockButton:SetSize(buttonWidth, 40)
        blockButton:SetPos(width - buttonWidth - 28, 441)
        bioButton:SetSize(42, 42)
        bioButton:SetPos(width - 70, 441)
    end

    local function selectPlayer(playerEntity)
        if IsValid(playerEntity) then
            frame.SelectedPlayer = playerEntity
            profileAvatar:SetPlayer(playerEntity, 104)
            modelPreview:SetModel(playerEntity:GetModel())
            if IsValid(modelPreview.Entity) then
                modelPreview.Entity:SetSkin(playerEntity:GetSkin())
                for bodyGroupIndex = 0, modelPreview.Entity:GetNumBodyGroups() - 1 do
                    modelPreview.Entity:SetBodygroup(bodyGroupIndex, playerEntity:GetBodygroup(bodyGroupIndex))
                end
            end
            local isLocalPlayer = playerEntity == LocalPlayer()
            bioButton:SetVisible(isLocalPlayer)
            allyButton:SetVisible(not isLocalPlayer)
            blockButton:SetVisible(not isLocalPlayer)
        end
    end

    local function rebuildRoster()
        local players = {}
        for _, playerEntity in ipairs(player.GetAll()) do
            if IsValid(playerEntity) then
                table.insert(players, playerEntity)
            end
        end
        table.sort(players, function(left, right)
            if left == LocalPlayer() then return true end
            if right == LocalPlayer() then return false end
            return string.lower(left:Nick()) < string.lower(right:Nick())
        end)
        if not IsValid(frame.SelectedPlayer) then
            selectPlayer(IsValid(LocalPlayer()) and LocalPlayer() or players[1])
        end

        rosterScroll:Clear()
        for _, playerEntity in ipairs(players) do
            local entry = vgui.Create("DButton", rosterScroll)
            entry:Dock(TOP)
            entry:SetTall(76)
            entry:DockMargin(0, 0, 0, 5)
            entry:SetText("")
            local avatar = vgui.Create("AvatarImage", entry)
            avatar:SetPlayer(playerEntity, 54)
            avatar:SetSize(54, 54)
            avatar:SetPos(11, 11)
            entry.Paint = function(currentEntry, width, height)
                local palette = ZM_DermaSkin.Palette
                local isSelected = frame.SelectedPlayer == playerEntity
                local status, statusColor = survivorStatus(playerEntity)
                local relation = Scoreboard:GetRelationship(playerEntity)
                surface.SetDrawColor(isSelected and palette.redDark or (currentEntry.Hovered and palette.raised or palette.black))
                surface.DrawRect(0, 0, width, height)
                surface.SetDrawColor(isSelected and palette.redBright or scoreboardColors.slate)
                surface.DrawOutlinedRect(0, 0, width, height, 1)
                surface.SetDrawColor(statusColor)
                surface.DrawRect(0, 0, 4, height)
                surface.SetDrawColor(palette.border)
                surface.DrawOutlinedRect(10, 10, 56, 56, 1)
                draw.SimpleText(playerEntity:Nick(), "ZM_ScoreboardName", 78, 12, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(string.format("LEVEL %03d  //  CELL %d, %d", playerEntity:GetNWInt("Level", 1), playerEntity:GetNWInt("CellX", 0), playerEntity:GetNWInt("CellY", 0)), "ZM_ScoreboardLabel", 79, 35, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(status, "ZM_ScoreboardLabel", 79, 52, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(string.format("%d MS", math.max(0, playerEntity:Ping())), "ZM_ScoreboardLabel", width - 12, 52, palette.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                if relation ~= "" then
                    draw.SimpleText(string.upper(relation), "ZM_ScoreboardLabel", width - 12, 14, relation == "ally" and scoreboardColors.teal or palette.redBright, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                end
            end
            entry.DoClick = function()
                selectPlayer(playerEntity)
                surface.PlaySound("buttons/button14.wav")
            end
        end
    end

    frame.NextRefresh = 0
    frame.Think = function(currentFrame)
        if CurTime() < currentFrame.NextRefresh then
            return
        end
        currentFrame.NextRefresh = CurTime() + 1
        rebuildRoster()
        local selected = currentFrame.SelectedPlayer
        local relation = IsValid(selected) and Scoreboard:GetRelationship(selected) or ""
        local canSetRelation = IsValid(selected) and selected ~= LocalPlayer()
        allyButton:SetEnabled(canSetRelation)
        blockButton:SetEnabled(canSetRelation)
        allyButton.Label = relation == "ally" and "ALLY MARKED" or "MARK ALLY"
        blockButton.Label = relation == "blocked" and "BLOCKED" or "BLOCK"
    end
    rebuildRoster()
end