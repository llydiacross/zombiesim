// Client-only prompts for optional host-installed dependencies.
ZM_DependencyPrompts = ZM_DependencyPrompts or {}
local DependencyPrompts = ZM_DependencyPrompts

DependencyPrompts.WalkerReleaseUrl = "https://github.com/llydiacross/zombiesim/releases"
DependencyPrompts.VoltDownloadUrl = "https://git.froggi.es/joshua/vphysics_jolt_gmod_builds"
DependencyPrompts.WalkerPromptCookie = "zombiesim_walker_prompt_v1_seen"
DependencyPrompts.WalkerPromptTestCookie = "zombiesim_walker_prompt_v1_test"
DependencyPrompts.VoltPromptCookie = "zombiesim_volt_prompt_v7_seen"
DependencyPrompts.LauncherReadyTransitionId = DependencyPrompts.LauncherReadyTransitionId or 0

surface.CreateFont("ZM_DependencyBriefingTitle", {
    font = "Trebuchet MS",
    size = 28,
    weight = 900,
    antialias = true
})

local function hasOpenPrompt()
    return IsValid(DependencyPrompts.ActivePrompt)
end

local function setLauncherBlackout(enabled)
    if enabled then
        if IsValid(DependencyPrompts.LauncherBlackout) then
            return
        end

        local blackout = vgui.Create("DPanel", vgui.GetWorldPanel())
        blackout:Dock(FILL)
        blackout:SetZPos(-32768)
        blackout:SetMouseInputEnabled(false)
        blackout:SetKeyboardInputEnabled(false)
        blackout.Paint = function(_, width, height)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, width, height)
        end
        blackout.OnRemove = function()
            if DependencyPrompts.LauncherBlackout == blackout then
                DependencyPrompts.LauncherBlackout = nil
            end
        end
        DependencyPrompts.LauncherBlackout = blackout
        return
    end

    if IsValid(DependencyPrompts.LauncherBlackout) then
        DependencyPrompts.LauncherBlackout:Remove()
    end
end

local function hasVoltVPhysics()
    return GetConVar("vjolt_substeps") ~= nil
end

function DependencyPrompts:SendLauncherReady()
    local transitionId = self.Status and self.Status.transitionId or 0
    if not self.Status or not self.Status.isLauncher or not self.Status.waitingForReady or transitionId == 0 or
        self.LauncherReadyTransitionId == transitionId then
        return
    end

    self.LauncherReadyTransitionId = transitionId
    net.Start("ZM.DependencyPromptsReady")
        net.WriteUInt(transitionId, 32)
    net.SendToServer()
end

local function createPrompt(options)
    local palette = ZM_DermaSkin.Palette
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle(options.frameTitle)
    frame:SetSize(math.min(500, ScrW() - 32), math.min(options.height or 368, ScrH() - 32))
    frame:Center()
    frame:MakePopup()
    frame:SetSizable(false)
    DependencyPrompts.ActivePrompt = frame
    if ZM_UI then
        ZM_UI:OpenExclusive(frame)
    end

    local content = vgui.Create("DPanel", frame)
    content:Dock(FILL)
    content:DockMargin(12, 37, 12, 12)
    content.Paint = function() end

    local artwork = vgui.Create("DPanel", content)
    artwork:Dock(TOP)
    artwork:DockMargin(0, 4, 0, 8)
    artwork:SetTall(136)
    artwork.Paint = function(_, width, height)
        surface.SetDrawColor(palette.black.r, palette.black.g, palette.black.b, 235)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 75)
        surface.DrawRect(1, 1, width - 2, 4)
        surface.SetDrawColor(palette.border.r, palette.border.g, palette.border.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)

        if options.artworkLabel then
            draw.SimpleText(options.artworkLabel, "ZM_DermaButton", 10, 10, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        if options.scanning then
            local scanY = math.floor((CurTime() * 42) % math.max(height - 8, 1)) + 4
            surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 125)
            surface.DrawRect(1, scanY, width - 2, 2)
        end

        local imageSize = options.imageSize or 80
        surface.SetMaterial(options.image)
        surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 255)
        surface.DrawTexturedRect(math.floor((width - imageSize) * 0.5), math.floor((height - imageSize) * 0.5), imageSize, imageSize)
    end

    local headline = vgui.Create("DLabel", content)
    headline:Dock(TOP)
    headline:DockMargin(8, 0, 8, 2)
    headline:SetTall(38)
    headline:SetFont("ZM_DermaFrameTitle")
    headline:SetText(options.headline)
    headline:SetTextColor(options.accent)
    headline:SetContentAlignment(5)

    if options.detailLines then
        local details = vgui.Create("DPanel", content)
        details:Dock(TOP)
        details:DockMargin(8, 4, 8, 6)
        details:SetTall(#options.detailLines * 16 + 34)
        details.Paint = function(_, width, height)
            surface.SetDrawColor(palette.raised.r, palette.raised.g, palette.raised.b, 235)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 210)
            surface.DrawRect(0, 0, 3, height)
            surface.SetDrawColor(palette.border.r, palette.border.g, palette.border.b, 255)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(options.detailTitle, "ZM_DermaButton", 12, 8, options.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            for index, line in ipairs(options.detailLines) do
                draw.SimpleText(line, "DermaDefault", 12, 25 + (index - 1) * 16, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
    end

    local command = vgui.Create("DButton", content)
    command:Dock(TOP)
    command:DockMargin(36, 14, 36, 7)
    command:SetTall(38)
    command:SetText(options.commandLabel)
    command:SetTooltip(options.commandTooltip)
    command.DoClick = function()
        gui.OpenURL(options.url)
        frame:Close()
    end

    local dismiss = vgui.Create("DButton", content)
    dismiss:Dock(TOP)
    dismiss:DockMargin(36, 0, 36, 0)
    dismiss:SetTall(27)
    dismiss:SetText(options.dismissLabel)
    dismiss.DoClick = function()
        frame:Close()
    end

    frame.OnClose = function()
        if options.onClosed then
            options.onClosed()
        end
    end

    frame.OnRemove = function()
        if DependencyPrompts.ActivePrompt == frame then
            DependencyPrompts.ActivePrompt = nil
        end
        if ZM_UI then
            ZM_UI:UnregisterTransient(frame)
        end
        timer.Simple(0, function()
            DependencyPrompts:ShowNextPrompt()
        end)
    end
end

local function createDependencyBriefing(options)
    local palette = ZM_DermaSkin.Palette
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle(options.frameTitle)
    frame:SetSize(math.min(920, ScrW() - 32), math.min(560, ScrH() - 32))
    frame:Center()
    frame:MakePopup()
    frame:SetSizable(false)
    DependencyPrompts.ActivePrompt = frame
    if ZM_UI then
        ZM_UI:OpenExclusive(frame)
    end

    local content = vgui.Create("DPanel", frame)
    content:Dock(FILL)
    content:DockMargin(18, 38, 18, 18)
    content.Paint = function() end

    local controls = vgui.Create("DPanel", content)
    controls:Dock(BOTTOM)
    controls:SetTall(54)
    controls.Paint = function() end

    local install = vgui.Create("DButton", controls)
    install:Dock(LEFT)
    install:SetWide(math.max(170, math.floor(controls:GetWide() * 0.43)))
    install:SetText(options.commandLabel)
    install:SetTooltip(options.commandTooltip)
    install.DoClick = function()
        gui.OpenURL(options.url)
        frame:Close()
    end

    local standardPhysics = vgui.Create("DButton", controls)
    standardPhysics:Dock(LEFT)
    standardPhysics:DockMargin(10, 0, 0, 0)
    standardPhysics:SetWide(math.max(210, math.floor(controls:GetWide() * 0.5)))
    standardPhysics:SetText(options.dismissLabel)
    standardPhysics.DoClick = function()
        frame:Close()
    end

    controls.PerformLayout = function(panel, width, height)
        local gap = 10
        local installWidth = math.max(150, math.floor((width - gap) * 0.42))
        install:SetWide(installWidth)
        standardPhysics:SetWide(math.max(0, width - installWidth - gap))
        install:SetTall(height)
        standardPhysics:SetTall(height)
    end

    local heading = vgui.Create("DLabel", content)
    heading:Dock(TOP)
    heading:SetTall(62)
    heading:SetFont("ZM_DependencyBriefingTitle")
    heading:SetText(options.headline)
    heading:SetTextColor(palette.text)
    heading:SetWrap(true)
    heading:SetContentAlignment(4)

    local divider = vgui.Create("DPanel", content)
    divider:Dock(TOP)
    divider:SetTall(2)
    divider:DockMargin(0, 0, 0, 16)
    divider.Paint = function(_, width, height)
        surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 255)
        surface.DrawRect(0, 0, width, height)
    end

    local body = vgui.Create("DPanel", content)
    body:Dock(FILL)
    body.Paint = function() end

    local briefing = vgui.Create("DPanel", body)
    briefing:Dock(LEFT)
    briefing:SetWide(math.floor((frame:GetWide() - 36) * 0.56))
    briefing:DockMargin(0, 0, 18, 0)
    briefing.Paint = function() end

    local eyebrow = vgui.Create("DLabel", briefing)
    eyebrow:Dock(TOP)
    eyebrow:SetTall(24)
    eyebrow:SetFont("ZM_DermaButton")
    eyebrow:SetText(options.detailTitle)
    eyebrow:SetTextColor(options.accent)

    local summary = vgui.Create("DLabel", briefing)
    summary:Dock(TOP)
    summary:DockMargin(0, 6, 0, 12)
    summary:SetTall(46)
    summary:SetFont("DermaDefaultBold")
    summary:SetText(options.summary)
    summary:SetTextColor(palette.text)
    summary:SetWrap(true)

    for _, line in ipairs(options.detailLines) do
        local bulletRow = vgui.Create("DPanel", briefing)
        bulletRow:Dock(TOP)
        bulletRow:DockMargin(0, 0, 0, 8)
        bulletRow:SetTall(32)
        bulletRow.Paint = function() end

        local bulletIcon = vgui.Create("DImage", bulletRow)
        bulletIcon:Dock(LEFT)
        bulletIcon:DockMargin(0, 7, 8, 7)
        bulletIcon:SetWide(18)
        bulletIcon:SetImage("icon16/accept.png")
        bulletIcon:SetImageColor(options.accent)

        local bulletText = vgui.Create("DLabel", bulletRow)
        bulletText:Dock(FILL)
        bulletText:SetFont("DermaDefault")
        bulletText:SetText(line)
        bulletText:SetTextColor(palette.muted)
        bulletText:SetWrap(true)
        bulletText:SetContentAlignment(4)
    end

    local display = vgui.Create("DPanel", body)
    display:Dock(FILL)
    display:DockMargin(0, 0, 0, 14)
    display.Paint = function(_, width, height)
        surface.SetDrawColor(palette.black.r, palette.black.g, palette.black.b, 245)
        surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
        draw.SimpleText(options.artworkTitle, "ZM_DermaButton", 12, 11, options.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(options.artworkSubtitle, "DermaDefault", 12, 29, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local imageAspect = options.imageAspect or 2
        local imageWidth = math.min(math.max(40, math.min(width - 30, 300)), math.max(40, height - 64) * imageAspect)
        local imageHeight = math.floor(imageWidth / imageAspect)
        local imageX = math.floor((width - imageWidth) * 0.5)
        local imageY = 52 + math.floor((math.max(40, height - 64) - imageHeight) * 0.5)
        surface.SetMaterial(options.image)
        surface.SetDrawColor(options.imageTint.r, options.imageTint.g, options.imageTint.b, options.imageTint.a or 255)
        surface.DrawTexturedRect(imageX, imageY, imageWidth, imageHeight)

        local scanY = math.floor((CurTime() * 36) % math.max(height - 12, 1)) + 6
        surface.SetDrawColor(options.accent.r, options.accent.g, options.accent.b, 95)
        surface.DrawRect(1, scanY, width - 2, 2)
    end

    frame.OnClose = function()
        if options.onClosed then
            options.onClosed()
        end
    end
    frame.OnRemove = function()
        if DependencyPrompts.ActivePrompt == frame then
            DependencyPrompts.ActivePrompt = nil
        end
        if ZM_UI then
            ZM_UI:UnregisterTransient(frame)
        end
        timer.Simple(0, function()
            DependencyPrompts:ShowNextPrompt()
        end)
    end
end

local function createWalkerBriefing(onClosed)
    createDependencyBriefing({
        frameTitle = "Z-NATION OPTIONAL COMPONENT",
        headline = "INSTALL WALKER SIMULATION",
        detailTitle = "OPTIONAL NATIVE MODULE",
        summary = "WALKER SIMULATION RUNS Z-NATION'S HORDE MODEL OUTSIDE THE SERVER LUA TICK.",
        detailLines = {
            "Keeps large horde simulation off the server Lua tick.",
            "Powers the live Walker satellite view in preview.",
            "Z-Nation plays normally without this module.",
            "Install the matching Win64 DLL while Garry's Mod is closed."
        },
        commandLabel = "GET WALKER DLL",
        commandTooltip = "Open the ZombieSim releases page",
        dismissLabel = "CONTINUE WITHOUT WALKER SIMULATION",
        url = DependencyPrompts.WalkerReleaseUrl,
        image = Material("zombiesim/ui/logo.png", "smooth"),
        accent = ZM_DermaSkin.Palette.redBright,
        imageTint = color_white,
        imageAspect = 2,
        artworkTitle = "WALKER // NATIVE MODULE",
        artworkSubtitle = "MODULE NOT DETECTED",
        onClosed = onClosed
    })
end

local function createVoltBriefing(onClosed)
    createDependencyBriefing({
        frameTitle = "Z-NATION OPTIONAL COMPONENT",
        headline = "INSTALL VOLT FOR A BETTER EXPERIENCE",
        detailTitle = "OPTIONAL PHYSICS UPGRADE",
        summary = "VOLT REPLACES GARRY'S MOD'S STANDARD VPHYSICS BACKEND WITH JOLT.",
        detailLines = {
            "More stable ragdolls, props, and constraints.",
            "More physics headroom in busy scenes.",
            "Z-Nation works normally without Volt.",
            "Install only while Garry's Mod is closed."
        },
        commandLabel = "VIEW VOLT INSTALL",
        commandTooltip = "Open the Volt VPhysics GMod builds page",
        dismissLabel = "CONTINUE WITH STANDARD PHYSICS",
        url = DependencyPrompts.VoltDownloadUrl,
        image = Material("zombiesim/ui/volt_logo.png", "smooth"),
        accent = Color(238, 191, 68),
        imageTint = color_white,
        imageAspect = 2,
        artworkTitle = "VOLT // JOLT BACKEND",
        artworkSubtitle = "OPTIONAL COMPONENT",
        onClosed = onClosed
    })
end

local function showTestBriefing(name, createBriefing)
    if hasOpenPrompt() then
        DependencyPrompts.ActivePrompt:Remove()
    end

    local removeTestBlackout = not IsValid(DependencyPrompts.LauncherBlackout)
    if removeTestBlackout then
        setLauncherBlackout(true)
    end
    print("[ZombieSim] Opening " .. name .. " dependency prompt test.")
    createBriefing(function()
        if removeTestBlackout then
            setLauncherBlackout(false)
        end
    end)
end

concommand.Add("zombiesim_dev_test_walker_prompt", function()
    showTestBriefing("Walker", createWalkerBriefing)
end)

concommand.Add("zombiesim_dev_test_volt_prompt", function()
    showTestBriefing("Volt", createVoltBriefing)
end)

local function refreshLauncherPromptSequence()
    local status = DependencyPrompts.Status
    if not status or not status.isLauncher or not status.waitingForReady then
        return
    end

    if hasOpenPrompt() then
        DependencyPrompts.ActivePrompt:Remove()
    end
    timer.Simple(0, function()
        DependencyPrompts:ShowNextPrompt()
    end)
end

concommand.Add("zombiesim_dev_reset_walker_prompt", function()
    cookie.Set(DependencyPrompts.WalkerPromptCookie, "0")
    cookie.Set(DependencyPrompts.WalkerPromptTestCookie, "1")
    print("[ZombieSim] Walker prompt reset and test override armed for the next eligible launcher transition.")
    refreshLauncherPromptSequence()
end)

concommand.Add("zombiesim_dev_reset_volt_prompt", function()
    cookie.Set(DependencyPrompts.VoltPromptCookie, "0")
    print("[ZombieSim] Volt prompt cookie reset; it will display at the next eligible launcher transition.")
    refreshLauncherPromptSequence()
end)

concommand.Add("zombiesim_dev_volt_status", function()
    print("[ZombieSim] Volt VPhysics: " .. (hasVoltVPhysics() and "detected" or "not detected") .. ".")
end)

concommand.Add("zombiesim_dev_dependency_prompt_status", function()
    local status = DependencyPrompts.Status or {}
    print(string.format(
        "[ZombieSim] Dependency prompts: launcher=%s waiting=%s walker=%s walkerCookie=%s walkerTest=%s volt=%s voltCookie=%s.",
        tostring(status.isLauncher == true),
        tostring(status.waitingForReady == true),
        tostring(status.hasWalker == true),
        cookie.GetString(DependencyPrompts.WalkerPromptCookie, "0"),
        cookie.GetString(DependencyPrompts.WalkerPromptTestCookie, "0"),
        hasVoltVPhysics() and "detected" or "not detected",
        cookie.GetString(DependencyPrompts.VoltPromptCookie, "0")
    ))
end)

local function createLauncherBeginPrompt()
    local palette = ZM_DermaSkin.Palette
    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("Z-NATION LAUNCHER")
    frame:SetSize(math.min(460, ScrW() - 32), math.min(240, ScrH() - 32))
    frame:Center()
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame:SetSizable(false)
    DependencyPrompts.ActivePrompt = frame
    if ZM_UI then
        ZM_UI:OpenExclusive(frame)
    end

    frame.OnKeyCodePressed = function() end

    local content = vgui.Create("DPanel", frame)
    content:Dock(FILL)
    content:DockMargin(18, 38, 18, 18)
    content.Paint = function() end

    local heading = vgui.Create("DLabel", content)
    heading:Dock(TOP)
    heading:SetTall(72)
    heading:SetFont("ZM_DependencyBriefingTitle")
    heading:SetText("READY TO DEPLOY")
    heading:SetTextColor(palette.text)
    heading:SetContentAlignment(5)

    local divider = vgui.Create("DPanel", content)
    divider:Dock(TOP)
    divider:SetTall(2)
    divider:DockMargin(54, 0, 54, 24)
    divider.Paint = function(_, width, height)
        surface.SetDrawColor(palette.redBright.r, palette.redBright.g, palette.redBright.b, 255)
        surface.DrawRect(0, 0, width, height)
    end

    local begin = vgui.Create("DButton", content)
    begin:Dock(BOTTOM)
    begin:SetTall(54)
    begin:SetText("BEGIN")
    begin.DoClick = function()
        DependencyPrompts:SendLauncherReady()
        frame:Remove()
    end

    frame.OnRemove = function()
        if DependencyPrompts.ActivePrompt == frame then
            DependencyPrompts.ActivePrompt = nil
        end
        if ZM_UI then
            ZM_UI:UnregisterTransient(frame)
        end
    end
end

function DependencyPrompts:ShowNextPrompt()
    if hasOpenPrompt() or not self.Status then
        return
    end

    if self.Status.isLauncher then
        if not self.Status.waitingForReady then
            return
        end
        if not hasVoltVPhysics() and cookie.GetString(self.VoltPromptCookie, "0") ~= "1" then
            createVoltBriefing(function()
                cookie.Set(self.VoltPromptCookie, "1")
            end)
            return
        end
        if (not self.Status.hasWalker or cookie.GetString(self.WalkerPromptTestCookie, "0") == "1") and
            cookie.GetString(self.WalkerPromptCookie, "0") ~= "1" then
            createWalkerBriefing(function()
                cookie.Set(self.WalkerPromptCookie, "1")
                cookie.Set(self.WalkerPromptTestCookie, "0")
            end)
            return
        end
        createLauncherBeginPrompt()
        return
    end
end

net.Receive("ZM.DependencyStatus", function()
    DependencyPrompts.Status = {
        isLauncher = net.ReadBool(),
        hasWalker = net.ReadBool(),
        waitingForReady = net.ReadBool(),
        transitionId = net.ReadUInt(32)
    }
    setLauncherBlackout(DependencyPrompts.Status.isLauncher)
    DependencyPrompts:ShowNextPrompt()
end)

hook.Add("InitPostEntity", "ZombieSim.DependencyPrompts.RequestStatus", function()
    timer.Simple(0, function()
        net.Start("ZM.RequestDependencyStatus")
        net.SendToServer()
    end)
end)