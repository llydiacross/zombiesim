local Suite = ZM_TestHarness.NewSuite()
local Scene = ZM_LauncherSceneClient

Suite:Add("Earth materials and bounded static spheres", function(check)
    local materials = Scene:GetMaterialStatus()
    for name, status in pairs(materials) do
        check(status.valid, name .. " material resolves")
        local expected = name == "rim" and 256 or 2048
        check(status.width == expected and status.height == (name == "rim" and 256 or 1024),
            name .. " has its authored dimensions")
    end
    local low = Scene:GetSphereForDetail(16)
    local high = Scene:GetSphereForDetail(32)
    check(low.triangles == 960 and low.vertices == 2880, "low quality has a fixed sphere budget")
    check(high.triangles == 3968 and high.vertices == 11904, "high quality has a fixed sphere budget")
    check(low.seamVertices == 32 and high.seamVertices == 64, "both qualities duplicate only the UV seam")
    check(low.poleTriangles == 64 and high.poleTriangles == 128, "both qualities use non-degenerate pole fans")
    check(table.Count(Scene.Spheres) == 2, "building both qualities owns exactly two sphere pairs")
    local horizon = Scene:GetHorizonMaterialStatus()
    check(horizon.sun.valid and horizon.terrain.valid and horizon.roads.valid,
        "sun, terrain and road materials resolve for the grounded city diorama")
    local diorama = Scene:GetDioramaMeshes()
    check(diorama.meshes == 2 and diorama.terrainTriangles == 1344
        and diorama.roadTriangles == 96,
        "terrain and crossing roads have fixed bounded static-mesh budgets")
    check(diorama.halfWidth == 620 and diorama.halfDepth == 520,
        "the ground plate is wide enough to carry its boundary out of frame")
    check(Scene:GetDioramaMeshes() == diorama,
        "repeated city draws reuse the same terrain and road meshes")
end)

Suite:Add("city marker follows the rotated Earth surface", function(check)
    local originalYaw, originalPitch = Scene.Yaw, Scene.Pitch
    Scene.Yaw, Scene.Pitch = 0, 0
    local position, normal = Scene:GetEarthMarkerPosition(Vector(10, 20, 30), 1, 1, 0, 0)
    check(position:Distance(Vector(53.2, 20, 30)) < 0.001 and normal == Vector(1, 0, 0),
        "the geographic marker sits just above its exact globe surface normal")
    Scene.Yaw, Scene.Pitch = 90, 0
    position, normal = Scene:GetEarthMarkerPosition(vector_origin, 2, 0.5, 0, 0)
    check(position:Distance(Vector(0, 43.2, 0)) < 0.001 and normal:Distance(Vector(0, 1, 0)) < 0.001,
        "the same marker transform follows Earth yaw and presentation scale")
    Scene.Yaw, Scene.Pitch = originalYaw, originalPitch
end)

Suite:Add("manual Earth view is bounded and Home-owned", function(check)
    local menu = ZM_LauncherMenu
    local inspection = ZM_SkyInspection
    local original = {
        yaw = Scene.Yaw, pitch = Scene.Pitch, zoom = Scene.EarthViewZoom,
        manual = Scene.ManualEarthView, presentation = Scene.PresentationState or "earth",
        transition = Scene.PresentationTransition, page = menu.Page, active = menu.Active,
        waiting = menu.Waiting, credits = menu.Credits, inspection = inspection.State,
        frameVisible = IsValid(menu.Frame) and menu.Frame:IsVisible()
    }
    local minimum, maximum, distance = Scene:GetEarthZoomBounds()
    check(minimum == 0.72 and maximum >= 1 and maximum <= 1.65 and distance > 42,
        "zoom bounds use the authored camera distance and keep the camera outside Earth")
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = 0, 0, 1
    Scene:AdjustEarthView(10000, 10000, 50)
    check(Scene.ManualEarthView and Scene.Pitch == 72 and Scene.EarthViewZoom == maximum,
        "drag pitch and wheel zoom clamp at their safe upper bounds")
    Scene:AdjustEarthView(0, -20000, -100)
    check(Scene.Pitch == -72 and Scene.EarthViewZoom == minimum,
        "reverse drag and wheel input clamp at their safe lower bounds")
    menu.Active, menu.Page, menu.Waiting, menu.Credits = true, "menu", nil, nil
    if IsValid(menu.Frame) then menu.Frame:SetVisible(true) end
    inspection.State = nil
    Scene.PresentationTransition = nil
    Scene.PresentationState = "earth"
    check(menu:IsEarthControlsActive(), "manual input is owned by the exposed Home Earth viewport")
    menu.Page = "options"
    check(not menu:IsEarthControlsActive(), "Settings cannot retain Earth input ownership")
    Scene:ResetEarthView()
    local latitude, longitude = Scene:GetEarthTarget()
    check(not Scene.ManualEarthView and Scene.EarthViewZoom == 1
        and Scene.Yaw == (longitude and -90 - longitude or 0)
        and Scene.Pitch == (latitude or 12),
        "Reset View returns to the saved location without changing gameplay coordinates")
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = original.yaw, original.pitch, original.zoom
    Scene.ManualEarthView, Scene.PresentationState = original.manual, original.presentation
    Scene.PresentationTransition = original.transition
    menu.Page, menu.Active, menu.Waiting, menu.Credits =
        original.page, original.active, original.waiting, original.credits
    if IsValid(menu.Frame) then menu.Frame:SetVisible(original.frameVisible) end
    inspection.State = original.inspection
end)

Suite:Add("presentation state has one visible owner", function(check)
    local original = Scene.PresentationState or "earth"
    check(Scene:SetPresentationState("earth") and Scene:GetPresentationState() ~= "city",
        "Earth owner can be selected")
    check(Scene:SetPresentationState("city") and Scene.PresentationState == "city",
        "city owner replaces Earth")
    check(not Scene:SetPresentationState("invalid") and Scene.PresentationState == "city",
        "invalid owners are rejected")
    Scene:SetPresentationState(original)
end)

Suite:Add("map-authored skybox owns one render pass", function(check)
    local original = ZM_LauncherMenu.PresentationSkybox
    ZM_LauncherMenu.PresentationSkybox = { origin = Vector(-6976, 1984, -142.5), scale = 16 }
    local transformed, scale = Scene:ToPresentationSpace(Vector(96, 32, 112))
    check(transformed == Vector(-6970, 1986, -135.5) and scale == 0.0625,
        "world presentation coordinates map into the authored scale-16 skybox")
    check(Scene:ShouldDrawPresentationPass(false, true)
        and not Scene:ShouldDrawPresentationPass(false, false)
        and not Scene:ShouldDrawPresentationPass(true, true),
        "the authored skybox draws once and skips world and depth passes")
    ZM_LauncherMenu.PresentationSkybox = nil
    check(Scene:ShouldDrawPresentationPass(false, false)
        and not Scene:ShouldDrawPresentationPass(false, true),
        "launchers without the marker retain the existing world-space fallback")
    ZM_LauncherMenu.PresentationSkybox = original
end)

Suite:Add("launcher space sky does not replace sky inspection", function(check)
    local palettes = ZM_SkyPalettes
    local inspection = ZM_SkyInspection
    local originalState = inspection.State
    local originalPresentation = Scene.PresentationState or "earth"
    inspection.State = nil
    Scene:SetPresentationState("earth")
    palettes:Update()
    local launcher = palettes:GetDiagnosticSnapshot()
    check(launcher.launcherPresentation and launcher.activeEntry == "imported_tropo_night_2",
        "orbital launcher presentation uses the dedicated approved night cube")
    Scene:SetPresentationState("city")
    palettes:Update()
    local grounded = palettes:GetDiagnosticSnapshot()
    check(grounded.launcherPresentation and grounded.activeEntry == "imported_tropo_day_2",
        "the grounded destination owns a daylight sky from the same approved set")
    Scene:SetPresentationState("earth")
    local previewFog = palettes:GetLauncherPreviewFog("imported_moonlit", "night")
    check(istable(previewFog) and istable(previewFog.color),
        "launcher preview fog exposes its horizon as a colour table")
    inspection.State = { launcherFog = previewFog }
    local updated, updateError = pcall(palettes.Update, palettes)
    check(updated, "sky inspection update accepts real launcher fog settings: " .. tostring(updateError))
    local preview = palettes:GetDiagnosticSnapshot()
    check(not preview.launcherPresentation and preview.activeEntry == "imported_moonlit",
        "sky inspection retains ownership of its selected preview sky")
    inspection.State = originalState
    Scene:SetPresentationState(originalPresentation)
    palettes:Update()
end)

Suite:Add("presentation transitions are timed and interruptible", function(check)
    local original = Scene.PresentationState or "earth"
    Scene:SetPresentationState("earth")
    check(Scene:TransitionPresentationState("city", 4.5)
        and Scene:GetPresentationTransitionState() == "entering_play"
        and Scene.PresentationTransition.duration == 4.5,
        "Home to Play owns the approved four-and-a-half-second transition")
    Scene.PresentationTransition.startedAt = RealTime() - 2.25
    local earthBefore, cityBefore, _, zoomBefore, atmosphereBefore, descentBefore =
        Scene:GetPresentationWeights()
    check(earthBefore > 0.6 and earthBefore < 0.72 and cityBefore == 0,
        "the destination stays hidden while the Earth begins fading behind the veil")
    check(zoomBefore > 6.2 and zoomBefore < 7 and atmosphereBefore > 0.85
        and descentBefore > 0.49 and descentBefore < 0.51,
        "the midpoint is a close atmospheric descent rather than a small model zoom")
    check(Scene:GetDescentVisuals(0).stage == "orbit"
        and Scene:GetDescentVisuals(0.55).stage == "atmosphere"
        and Scene:GetDescentVisuals(1).stage == "destination",
        "descent timing exposes orbit, atmosphere and grounded destination stages")
    check(not Scene:GetDescentVisuals(0.4).skyDay and Scene:GetDescentVisuals(0.58).skyDay
        and Scene:GetDescentVisuals(0.58).atmosphere > 0.99,
        "the sky only turns to day while the veil fully covers the handoff")
    check(Scene:TransitionPresentationState("earth", 3)
        and Scene:GetPresentationTransitionState() == "returning_home"
        and Scene.PresentationTransition.duration == 3,
        "Back retargets into the approved three-second return")
    local earthAfter, cityAfter, _, zoomAfter, atmosphereAfter, descentAfter =
        Scene:GetPresentationWeights()
    check(math.abs(earthAfter - earthBefore) < 0.02 and math.abs(cityAfter - cityBefore) < 0.02,
        "interruption resumes from the current blend without snapping")
    check(math.abs(zoomAfter - zoomBefore) < 0.05
        and math.abs(atmosphereAfter - atmosphereBefore) < 0.02
        and math.abs(descentAfter - descentBefore) < 0.02,
        "interrupted return preserves the globe pose and atmospheric handoff")
    Scene.PresentationTransition.startedAt = RealTime() - 3
    local finishedEarth, finishedCity, _, finishedZoom, finishedAtmosphere, finishedDescent =
        Scene:GetPresentationWeights()
    check(finishedEarth == 1 and finishedCity == 0 and finishedZoom == 1
        and finishedAtmosphere == 0 and finishedDescent == 0 and Scene.PresentationTransition == nil,
        "completed return has one Earth owner and no stale timer")
    Scene:SetPresentationState(original)
end)

Suite:Add("city presentation data is not parsed per frame", function(check)
    local before = Scene.PresentationAssetLoads or 0
    local firstWorld, firstSkyline = Scene:GetPresentationData(ZM_World.ActiveProfile)
    local afterFirst = Scene.PresentationAssetLoads or 0
    local secondWorld, secondSkyline = Scene:GetPresentationData(ZM_World.ActiveProfile)
    check(firstWorld == secondWorld and firstSkyline == secondSkyline,
        "repeated city draws reuse the same parsed world and skyline tables")
    check(afterFirst - before <= 1 and (Scene.PresentationAssetLoads or 0) == afterFirst,
        "presentation assets load at most once for the active profile")
    local firstModels = Scene:PrepareCity()
    local loadsAfterModel = Scene.PresentationAssetLoads or 0
    local secondModels = Scene:PrepareCity()
    check(istable(firstModels) and firstModels == secondModels and #firstModels >= 4 and #firstModels <= 18,
        "repeated city draws reuse one bounded detailed skyline cluster")
    check((Scene.PresentationAssetLoads or 0) == loadsAfterModel,
        "repeated city draws perform no additional presentation asset loads")
end)

Suite:Add("Home has four actions and Play never deploys", function(check)
    local menu = ZM_LauncherMenu
    local logo = menu:GetLogoStatus()
    check(logo.valid and logo.width == 288 and logo.height == 128,
        "Home uses the exact supplied transparent logo at its authored aspect")
    local originalPage = menu.Page or "menu"
    local originalWaiting = menu.Waiting
    local originalPresentation = Scene.PresentationState or "earth"
    menu.Waiting = nil
    Scene:SetPresentationState("earth")
    menu:SetPage("menu")
    menu:Render()
    local labels = {}
    for _, button in ipairs(menu.Buttons or {}) do labels[#labels + 1] = button:GetText() end
    check(#labels == 4 and labels[1] == "PLAY" and labels[2] == "TOOLS"
        and labels[3] == "SETTINGS" and labels[4] == "EXIT TO GMOD",
        "fresh Home exposes exactly Play, Tools, Settings and Exit")
    menu.Buttons[1]:DoClick()
    check(menu.Page == "load" and menu:GetState() == "entering_play" and menu.Waiting == nil,
        "Play opens survivor selection and starts its transition without deploying")
    menu.Waiting = originalWaiting
    menu:SetPage(originalPage)
    Scene:SetPresentationState(originalPresentation)
    menu:Render()
end)

Suite:Add("page lifecycle returns to the survivor grid and releases Earth input", function(check)
    local menu = ZM_LauncherMenu
    local originalPage, originalStep = menu.Page or "menu", menu.Step
    local originalDraft = menu.Draft
    local originalPresentation = Scene.PresentationState or "earth"
    local originalTransition = Scene.PresentationTransition
    local originalManual = Scene.ManualEarthView
    menu.Draft = {
        slot = 1, name = "Lifecycle Test", attributes = {},
        appearance = { model = ZM_CharacterRules.Models[1], skin = 0,
            bodygroups = {}, playerColour = { 1, 1, 1 } }
    }
    menu:SetPage("create")
    menu.Step = 4
    menu:Back()
    check(menu.Page == "create" and menu.Step == 3,
        "Back moves to the previous create step without leaving the wizard")
    menu.Step = 2
    menu:Back()
    check(menu.Page == "load", "cancelling the first create step returns to the survivor grid")
    menu:SetPage("appearance")
    menu:Back()
    check(menu.Page == "load", "cancelling legacy appearance returns to the survivor grid")
    Scene:SetPresentationState("earth")
    menu:SetPage("menu")
    menu:Render()
    Scene:SetPresentationState("earth")
    Scene:BeginEarthView()
    menu:SetPage("options")
    check(not Scene.ManualEarthView, "a page switch releases manual Earth ownership synchronously")
    menu:SetPage(originalPage)
    menu.Step = originalStep
    menu.Draft = originalDraft
    Scene.PresentationState = originalPresentation
    Scene.PresentationTransition = originalTransition
    Scene.ManualEarthView = originalManual
    menu:Render()
end)

Suite:Add("request failures preserve their initiating page", function(check)
    local menu = ZM_LauncherMenu
    local distribution = ZM_Distribution
    local original = {
        page = menu.Page, waiting = menu.Waiting, deadline = menu.Deadline,
        error = menu.Error, returnPage = menu.RequestReturnPage,
        contentReturn = menu.ContentReturnPage, refresh = distribution.RefreshClient
    }
    menu:SetPage("load")
    distribution.RefreshClient = function() return false, "fixture packages unavailable" end
    menu:Request("select", 1)
    check(menu.Page == "content" and menu.ContentReturnPage == "load" and not menu.Waiting,
        "content failure opens its explanation and retains the survivor-grid return page")
    distribution.RefreshClient = original.refresh
    menu:SetPage("load")
    menu.Waiting = "delete"
    menu.RequestReturnPage = "load"
    menu.Deadline = RealTime() - 1
    menu.Frame:Think()
    check(menu.Page == "load" and not menu.Waiting and menu.RequestReturnPage == nil,
        "a timed-out request returns to its initiating survivor grid")
    menu.Waiting = "delete"
    menu.RequestReturnPage = "load"
    menu:ApplyRequestResult("delete", false, "fixture request rejected", false)
    check(menu.Page == "load" and not menu.Waiting and menu.Error == "fixture request rejected",
        "an explicit server rejection preserves its initiating survivor grid and reason")
    menu:SetPage(original.page)
    menu.Waiting, menu.Deadline, menu.Error = original.waiting, original.deadline, original.error
    menu.RequestReturnPage, menu.ContentReturnPage = original.returnPage, original.contentReturn
    menu:Render()
end)

Suite:Add("empty survivor grid never exposes deployment", function(check)
    local menu = ZM_LauncherMenu
    local originalPage, originalSlots, originalSelected = menu.Page, menu.Slots, menu.SelectedSlot
    menu.Slots, menu.SelectedSlot = {}, nil
    menu:SetPage("load")
    menu:Render()
    local creates, deploys = 0, 0
    for _, button in ipairs(menu.Buttons or {}) do
        local text = button:GetText()
        if string.find(text, "+ CREATE", 1, true) then creates = creates + 1 end
        if string.find(text, "DEPLOY", 1, true) then deploys = deploys + 1 end
    end
    check(creates == 3 and deploys == 0,
        "three empty slots offer creation and no implicit deployment action")
    menu.Slots, menu.SelectedSlot = originalSlots, originalSelected
    menu:SetPage(originalPage)
    menu:Render()
end)

concommand.Remove("zombiesim_dev_test_launcher_presentation_client")
concommand.Add("zombiesim_dev_test_launcher_presentation_client", function()
    local summary = Suite:Run()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/launcher-presentation-client-tests.json", util.TableToJSON(summary, true))
end)
