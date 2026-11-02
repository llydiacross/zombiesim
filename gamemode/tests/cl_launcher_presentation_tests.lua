local Suite = ZM_TestHarness.NewSuite()
local Scene = ZM_LauncherSceneClient

for _, entry in ipairs(ZM_LauncherProfessionPicker.Tests.cases) do
    Suite:Add(entry.name, entry.body)
end

Suite:Add("Earth materials and bounded static spheres", function(check)
    local materials = Scene:GetMaterialStatus()
    for name, status in pairs(materials) do
        check(status.valid, name .. " material resolves")
        local expected = name == "rim" and 256 or 2048
        check(status.width == expected and status.height == (name == "rim" and 256 or 1024),
            name .. " has its authored dimensions")
    end
    for name, status in pairs(Scene:GetHighDetailMaterialStatus()) do
        check(status.valid and status.width == 4096 and status.height == 2048,
            "close-zoom " .. name .. " layer resolves at 4096x2048")
    end
    local qualityConVar = GetConVar("zombiesim_globe_quality")
    local originalQuality = qualityConVar:GetString()
    qualityConVar:SetBool(true)
    check(Scene:GetEarthHighDetailBlend(1) == 0 and Scene:GetEarthHighDetailBlend(1.5) == 0,
        "the standard texture owns the ordinary and moderately zoomed globe")
    local midway = Scene:GetEarthHighDetailBlend(1.8)
    check(midway > 0 and midway < 1 and Scene:GetEarthHighDetailBlend(2.1) == 1
        and Scene:GetEarthHighDetailBlend(3) == 1,
        "deep zoom crossfades smoothly to the high-detail texture")
    qualityConVar:SetBool(false)
    check(Scene:GetEarthHighDetailBlend(3) == 0, "low globe quality never uses the high-detail layer")
    qualityConVar:SetString(originalQuality)
    local low = Scene:GetSphereForDetail(16)
    local high = Scene:GetSphereForDetail(32)
    check(low.triangles == 960 and low.vertices == 2880, "low quality has a fixed sphere budget")
    check(high.triangles == 3968 and high.vertices == 11904, "high quality has a fixed sphere budget")
    check(low.seamVertices == 32 and high.seamVertices == 64, "both qualities duplicate only the UV seam")
    check(low.poleTriangles == 64 and high.poleTriangles == 128, "both qualities use non-degenerate pole fans")
    check(table.Count(Scene.Spheres) == 2, "building both qualities owns exactly two sphere pairs")
    local light = Vector(-0.4, -0.8, 0.45):GetNormalized()
    local dayAmount, nightAmount = Scene:GetEarthNightBlend(light)
    check(dayAmount == 1 and nightAmount == 0,
        "real night-light imagery fades completely on the illuminated hemisphere")
    dayAmount, nightAmount = Scene:GetEarthNightBlend(-light)
    check(dayAmount == 0 and nightAmount == 1,
        "the night surface reaches full weight on the dark hemisphere")
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
    local laLatitude, laLongitude = 34.05, -118.24
    Scene.Yaw, Scene.Pitch = -90 - laLongitude, laLatitude
    local _, laNormal = Scene:GetEarthMarkerPosition(vector_origin, 1, 1, laLatitude, laLongitude)
    local pole = Scene:GetEarthRotation() * Vector(0, 0, 1)
    check(laNormal:Distance(Vector(0, -1, 0)) < 0.001 and math.abs(pole.x) < 0.001 and pole.z > 0,
        "a centred far-west city faces the camera with north still upright, not rolled")
    Scene.Yaw, Scene.Pitch = 0, 40
    pole = Scene:GetEarthRotation() * Vector(0, 0, 1)
    check(math.abs(pole.x) < 0.001 and pole.z > 0,
        "vertical gimbal tilt never rolls the pole sideways at any yaw")
    Scene.Yaw, Scene.Pitch = originalYaw, originalPitch
end)

Suite:Add("manual Earth view is bounded and Home-owned", function(check)
    local menu = ZM_LauncherMenu
    local inspection = ZM_SkyInspection
    local original = {
        yaw = Scene.Yaw, pitch = Scene.Pitch, zoom = Scene.EarthViewZoom,
        returnTransition = Scene.EarthViewReturn,
        dragging = Scene.EarthDragging, spinYaw = Scene.EarthSpinYawVelocity,
        spinPitch = Scene.EarthSpinPitchVelocity,
        manual = Scene.ManualEarthView, presentation = Scene.PresentationState or "earth",
        shown = Scene.PresentationShown,
        transition = Scene.PresentationTransition, page = menu.Page, active = menu.Active,
        waiting = menu.Waiting, credits = menu.Credits, inspection = inspection.State,
        frameVisible = IsValid(menu.Frame) and menu.Frame:IsVisible()
    }
    local minimum, maximum, distance = Scene:GetEarthZoomBounds()
    check(minimum == 0.72 and maximum > 1.65 and maximum <= 3 and distance > 100
        and 42 * maximum <= distance - 24 + 0.001,
        "extended zoom uses the authored camera clearance without entering the Earth")
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = 0, 0, 1
    Scene:AdjustEarthView(10000, 10000, 50)
    check(Scene.ManualEarthView and Scene.Pitch == 72 and Scene.EarthViewZoom == maximum,
        "drag pitch and wheel zoom clamp at their safe bounds")
    Scene:AdjustEarthView(0, -20000, -100)
    check(Scene.Pitch == -72 and Scene.EarthViewZoom == minimum,
        "reverse drag and wheel input clamp at their safe bounds")
    menu.Active, menu.Page, menu.Waiting, menu.Credits = true, "menu", nil, nil
    if IsValid(menu.Frame) then menu.Frame:SetVisible(true) end
    inspection.State = nil
    Scene.PresentationTransition = nil
    Scene.PresentationState, Scene.PresentationShown = "earth", nil
    check(menu:IsEarthControlsActive(), "manual input is owned by the exposed Home Earth viewport")
    menu.Page = "options"
    check(not menu:IsEarthControlsActive(), "Settings cannot retain Earth input ownership")
    Scene:ResetEarthView()
    local latitude, longitude = Scene:GetEarthTarget()
    check(not Scene.ManualEarthView and Scene.EarthViewReturn ~= nil,
        "Reset View starts an animated return without changing gameplay coordinates")
    Scene:AdvanceEarthViewReturn(Scene.EarthViewReturn.startedAt + Scene.EarthViewReturn.duration)
    local expectedYaw = longitude and -90 - longitude or 0
    check(Scene.EarthViewZoom == 1
        and math.abs(math.AngleDifference(Scene.Yaw, expectedYaw)) < 0.001
        and math.abs(Scene.Pitch - (latitude or 12)) < 0.001,
        "the animated return finishes centred on the saved location")
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = original.yaw, original.pitch, original.zoom
    Scene.EarthViewReturn = original.returnTransition
    Scene.ManualEarthView, Scene.PresentationState = original.manual, original.presentation
    Scene.PresentationShown = original.shown
    Scene.EarthDragging = original.dragging
    Scene.EarthSpinYawVelocity, Scene.EarthSpinPitchVelocity = original.spinYaw, original.spinPitch
    Scene.PresentationTransition = original.transition
    menu.Page, menu.Active, menu.Waiting, menu.Credits =
        original.page, original.active, original.waiting, original.credits
    if IsValid(menu.Frame) then menu.Frame:SetVisible(original.frameVisible) end
    inspection.State = original.inspection
end)

Suite:Add("Earth spin carries momentum after drag and releases at bounds", function(check)
    local original = {
        yaw = Scene.Yaw, pitch = Scene.Pitch, manual = Scene.ManualEarthView,
        dragging = Scene.EarthDragging, spinYaw = Scene.EarthSpinYawVelocity,
        spinPitch = Scene.EarthSpinPitchVelocity
    }
    Scene.Yaw, Scene.Pitch = 0, 0
    Scene.ManualEarthView, Scene.EarthDragging = true, false
    Scene:AdjustEarthView(10, 10, 0)
    check(Scene.Yaw > 0 and Scene.Pitch > 0,
        "mouse movement drives the two gimbal axes independently")
    Scene.Yaw, Scene.Pitch = 0, 0
    Scene:AdjustEarthView(10, 0, 0)
    check(Scene.Yaw > 0 and Scene.Pitch == 0,
        "horizontal drag turns only the vertical gimbal axis")
    Scene.Yaw, Scene.Pitch = 0, 0
    Scene:AdjustEarthView(0, 10, 0)
    check(Scene.Yaw == 0 and Scene.Pitch > 0,
        "vertical drag turns only the horizontal gimbal axis")
    Scene.Yaw, Scene.Pitch = 0, 0
    Scene.EarthSpinYawVelocity, Scene.EarthSpinPitchVelocity = 180, 90
    Scene:AdvanceEarthMomentum(0.1)
    check(Scene.Yaw > 0 and Scene.Pitch > 0
        and Scene.EarthSpinYawVelocity > 0 and Scene.EarthSpinYawVelocity < 180,
        "a released drag keeps rotating while angular velocity damps smoothly")
    Scene.Pitch, Scene.EarthSpinPitchVelocity = 71, 240
    Scene:AdvanceEarthMomentum(0.1)
    check(Scene.Pitch == 72 and Scene.EarthSpinPitchVelocity == 0,
        "inertial pitch stops cleanly at the safe camera-angle limit")
    Scene.EarthSpinYawVelocity, Scene.EarthSpinPitchVelocity = 80, -40
    Scene:AdjustEarthView(0, 0, 1)
    check(Scene.EarthSpinYawVelocity == 0 and Scene.EarthSpinPitchVelocity == 0,
        "zooming cancels residual spin so the selected area stays under the cursor")
    Scene:ReleaseEarthView()
    check(not Scene.ManualEarthView and Scene.EarthSpinYawVelocity == 0
        and Scene.EarthSpinPitchVelocity == 0,
        "leaving Home releases inertial ownership and clears spin")
    Scene.Yaw, Scene.Pitch, Scene.ManualEarthView, Scene.EarthDragging =
        original.yaw, original.pitch, original.manual, original.dragging
    Scene.EarthSpinYawVelocity, Scene.EarthSpinPitchVelocity = original.spinYaw, original.spinPitch
end)

Suite:Add("Earth recenter cancels when manual input resumes", function(check)
    local original = {
        yaw = Scene.Yaw, pitch = Scene.Pitch, zoom = Scene.EarthViewZoom,
        manual = Scene.ManualEarthView, transition = Scene.EarthViewReturn,
        dragging = Scene.EarthDragging, spinYaw = Scene.EarthSpinYawVelocity,
        spinPitch = Scene.EarthSpinPitchVelocity
    }
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = 40, 20, 1.3
    Scene:ResetEarthView()
    local transition = Scene.EarthViewReturn
    check(transition ~= nil, "recenter retains a time-bounded interpolation")
    Scene:AdvanceEarthViewReturn(transition.startedAt + transition.duration * 0.5)
    check(Scene.EarthViewReturn ~= nil and Scene.EarthViewZoom < 1.3 and Scene.EarthViewZoom > 1,
        "recenter smoothly interpolates orientation and zoom")
    Scene:BeginEarthDrag()
    check(Scene.EarthViewReturn == nil and Scene.EarthDragging,
        "a new drag takes ownership and cancels recentering")
    Scene:ReleaseEarthView()
    Scene.Yaw, Scene.Pitch, Scene.EarthViewZoom = original.yaw, original.pitch, original.zoom
    Scene.ManualEarthView, Scene.EarthViewReturn = original.manual, original.transition
    Scene.EarthDragging = original.dragging
    Scene.EarthSpinYawVelocity, Scene.EarthSpinPitchVelocity = original.spinYaw, original.spinPitch
end)

Suite:Add("launcher music volume toggle is scoped to its own track", function(check)
    local music = ZM_Music
    local original = music.LauncherTrackLowered
    check(music.LauncherTracks.intro.path == "sounds/music/menu.mp3"
        and not music.LauncherTracks.intro.looping,
        "the first menu track plays once")
    check(music.LauncherTracks.loop.path == "sounds/music/menu 2.mp3"
        and music.LauncherTracks.loop.looping,
        "menu 2 follows the first track and is configured to loop")
    check(music:SetLauncherTrackLowered(true) == true, "launcher menu track can select the quieter level")
    check(music:ToggleLauncherTrackLevel() == false, "the adjacent control restores normal launcher music")
    music:SetLauncherTrackLowered(original == true)
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
    check(launcher.launcherPresentation and launcher.activeEntry == "imported_space_9",
        "orbital launcher presentation uses the dedicated deep-space cube")
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

Suite:Add("presentation transitions fade through black and are interruptible", function(check)
    local original = Scene.PresentationState or "earth"
    local fadeOut, hold, fadeIn = Scene:GetFadeTimings()
    check(fadeOut == 0.22 and hold == 0.1 and fadeIn == 0.4,
        "the approved fade timing is 0.22 s out, 0.1 s black and 0.4 s in")
    local revealDelay, revealSeconds = Scene:GetUIRevealTimings()
    Scene:SetPresentationState("earth")
    check(Scene:TransitionPresentationState("city")
        and Scene:GetPresentationTransitionState() == "entering_play",
        "Home to Play starts a black fade")
    Scene.PresentationTransition.startedAt = RealTime() - fadeOut * 0.5
    local halfOut = Scene:AdvancePresentationFade()
    check(math.abs(halfOut - 0.5) < 0.05 and Scene:GetPresentationState() == "earth",
        "the Earth stays shown while the screen darkens")
    check(Scene:IsPresentationSwapPending() and math.abs(Scene:GetPresentationUIAlpha() - (1 - halfOut)) < 0.05,
        "page content waits for black and panels fade with the darkness")
    local earthSky = Scene:GetPresentationSky()
    check(Scene.PresentationSkyId == earthSky,
        "the night sky stays applied while the screen darkens")
    Scene.PresentationTransition.startedAt = RealTime() - fadeOut * 0.25
    local quarterOut = Scene:AdvancePresentationFade()
    check(quarterOut > 0 and quarterOut < 0.2,
        "the darkening eases in gently rather than starting abruptly")
    Scene.PresentationTransition.startedAt = RealTime() - (fadeOut + hold * 0.5)
    check(Scene:AdvancePresentationFade() == 1 and Scene:GetPresentationState() == "city"
        and not Scene:IsPresentationSwapPending(),
        "the deploy scene swaps in only while the screen is fully black")
    check(Scene.PresentationSkyId == Scene:GetPresentationSky() and Scene.PresentationSkyId ~= earthSky,
        "the day sky swaps with the scene while the screen is fully black")
    Scene.PresentationTransition.startedAt = RealTime() - (fadeOut + hold + fadeIn * 0.5)
    local halfIn = Scene:AdvancePresentationFade()
    check(math.abs(halfIn - 0.5) < 0.05 and Scene:GetPresentationState() == "city",
        "the deploy scene fades in from black")
    check(Scene:GetPresentationUIAlpha() == 0,
        "launcher panels stay hidden while the new scene fades in")
    check(Scene:TransitionPresentationState("earth")
        and Scene:GetPresentationTransitionState() == "returning_home",
        "Back mid-fade retargets to Home")
    local resumed = Scene:AdvancePresentationFade()
    check(math.abs(resumed - halfIn) < 0.05 and Scene:GetPresentationState() == "city",
        "interruption resumes from the current darkness without snapping")
    Scene.PresentationTransition.startedAt = RealTime() - (fadeOut + hold * 0.5)
    check(Scene:AdvancePresentationFade() == 1 and Scene:GetPresentationState() == "earth",
        "the return swaps back to the Earth behind black")
    Scene.PresentationTransition.startedAt = RealTime() - (fadeOut + hold + fadeIn + 0.1)
    check(Scene:AdvancePresentationFade() == 0 and Scene.PresentationTransition == nil
        and Scene:GetPresentationState() == "earth",
        "a completed return leaves one Earth owner and no stale fade")
    local revealAt = Scene.PresentationUIRevealAt or RealTime()
    check(Scene:GetPresentationUIAlpha(revealAt + revealDelay * 0.5) == 0,
        "launcher panels wait after the scene has fully appeared")
    local midReveal = Scene:GetPresentationUIAlpha(revealAt + revealDelay + revealSeconds * 0.5)
    check(midReveal > 0.4 and midReveal < 0.6, "launcher panels then fade in smoothly")
    check(Scene:GetPresentationUIAlpha(revealAt + revealDelay + revealSeconds + 0.1) == 1
        and Scene.PresentationUIRevealAt == nil,
        "the panel reveal completes and clears its timer")
    Scene:SetPresentationState("earth")
    Scene:TransitionPresentationState("city")
    Scene.PresentationTransition.startedAt = RealTime() - fadeOut * 0.5
    Scene:TransitionPresentationState("earth")
    Scene.PresentationTransition.startedAt = Scene.PresentationTransition.startedAt - (fadeIn + 0.1)
    check(Scene:AdvancePresentationFade() == 0 and Scene:GetPresentationState() == "earth",
        "cancelling before the swap fades back into the unchanged Earth")
    Scene:SetPresentationState(original)
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

Suite:Add("creation camera owns every creation and appearance step", function(check)
    local menu = ZM_LauncherMenu
    local inspection = ZM_SkyInspection
    local calcView = hook.GetTable().CalcView["ZombieSim.Launcher.MenuCamera"]
    local original = {
        active = menu.Active, page = menu.Page, step = menu.Step, waiting = menu.Waiting,
        credits = menu.Credits, camera = menu.Camera, creationCamera = menu.CreationCamera,
        deployCamera = menu.DeployCamera, presentation = Scene.PresentationState or "earth",
        preview = menu.PreviewPanel, globe = menu.Globe, inspection = inspection.State,
        creditsView = Scene.CreditsView
    }
    local ok, failure = pcall(function()
        local main = { origin = Vector(1, 2, 3), angles = Angle(4, 5, 6), fov = 70 }
        local creation = { origin = Vector(11, 12, 13), angles = Angle(14, 15, 16), fov = 80 }
        menu.Active, menu.Credits, menu.Camera, menu.CreationCamera = true, false, main, creation
        menu.PreviewPanel, menu.Globe, inspection.State = nil, Vector(1, 1, 1), nil
        menu.Page = "create"
        for step = 2, 6 do
            menu.Step = step
            local view = calcView(nil, nil, nil, 90)
            check(view.origin == creation.origin and view.angles == creation.angles and view.fov == 80,
                "creation step " .. step .. " uses the authored pose")
        end
        menu.Waiting = "create"
        check(calcView(nil, nil, nil, 90).origin == creation.origin and Scene:IsPresentationHidden(),
            "the creation pose remains active and the globe stays hidden while saving")
        menu.Waiting, menu.Page = nil, "appearance"
        check(calcView(nil, nil, nil, 90).origin == creation.origin,
            "legacy appearance uses the same creation pose")
        menu.Page = "load"
        Scene:SetPresentationState("earth")
        menu.DeployCamera = nil
        check(calcView(nil, nil, nil, 90).origin == main.origin and not Scene:IsPresentationHidden(),
            "returning to survivor selection restores the normal launcher view")
        local deploy = { origin = Vector(31, 32, 33), angles = Angle(0, 27.5, 0), fov = 90 }
        menu.DeployCamera = deploy
        check(calcView(nil, nil, nil, 90).origin == main.origin,
            "the deploy pose waits until the fade has swapped scenes")
        Scene:SetPresentationState("city")
        local deployView = calcView(nil, nil, nil, 90)
        check(deployView.origin == deploy.origin and deployView.angles == deploy.angles,
            "Play views the authored deploy_camera once the scene has swapped")
        menu.DeployCamera = nil
        check(calcView(nil, nil, nil, 90).origin == main.origin,
            "an older launcher without deploy_camera retains the normal camera")
        Scene:SetPresentationState("earth")
        menu.Page, menu.CreationCamera = "create", nil
        check(calcView(nil, nil, nil, 90).origin == main.origin,
            "an older launcher without the marker retains the normal camera")
        menu.CreationCamera, menu.Credits = creation, true
        local credits = { origin = Vector(21, 22, 23) }
        Scene.CreditsView = function() return credits end
        check(calcView(nil, nil, nil, 90) == credits, "credits retain camera priority")
        menu.Active = false
        check(calcView(nil, nil, nil, 90) == nil, "inactive launchers do not override the view")
    end)
    menu.Active, menu.Page, menu.Step, menu.Waiting =
        original.active, original.page, original.step, original.waiting
    menu.Credits, menu.Camera, menu.CreationCamera =
        original.credits, original.camera, original.creationCamera
    menu.PreviewPanel, menu.Globe, inspection.State = original.preview, original.globe, original.inspection
    Scene.CreditsView = original.creditsView
    menu.DeployCamera = original.deployCamera
    Scene:SetPresentationState(original.presentation)
    if not ok then error(failure, 0) end
end)

Suite:Add("profession selection preserves the create wizard and draft", function(check)
    local menu = ZM_LauncherMenu
    local original = {
        page = menu.Page, step = menu.Step, draft = menu.Draft, waiting = menu.Waiting,
        error = menu.Error, request = menu.Request, presentation = Scene.PresentationState,
        transition = Scene.PresentationTransition, manual = Scene.ManualEarthView
    }
    local ok, failure = pcall(function()
        menu.Waiting = nil
        menu.Request = function() error("The profession fixture must not send a server request") end
        menu.Draft = { slot = 1, name = "Fixture", attributes = { Strength = 3 },
            appearance = { model = ZM_CharacterRules.Models[1], skin = 0,
                bodygroups = {}, playerColour = { 1, 1, 1 } } }
        menu:SetPage("create")
        menu.Step = 4
        menu:Render()
        local view = menu.ProfessionPickerView
        check(view ~= nil and not view.nextButton:IsEnabled(),
            "the real profession step opens without an implicit job")
        view.cards.Doctor:DoClick()
        check(menu.Step == 4 and menu.Draft.job == "Doctor" and menu.Draft.attributes.Strength == 3,
            "choosing a card keeps the user on the job step and preserves points")
        view.nextButton:DoClick()
        check(menu.Step == 5 and menu.Draft.job == "Doctor" and menu.Draft.attributes.Strength == 3,
            "Next reaches the existing point-allocation step")
        menu:Back()
        check(menu.Step == 4 and menu.ProfessionPickerView.title:GetText() == "DOCTOR"
            and menu.Draft.attributes.Strength == 3, "Back restores the selected profession and points")
        menu:Back()
        check(menu.Step == 3 and menu.Page == "create", "Back still returns to appearance")
    end)
    menu.Request, menu.Draft, menu.Step = original.request, original.draft, original.step
    menu.Waiting, menu.Error = original.waiting, original.error
    menu:SetPage(original.page or "menu")
    Scene.PresentationState, Scene.PresentationTransition = original.presentation, original.transition
    Scene.ManualEarthView = original.manual
    menu:Render()
    if not ok then error(failure, 0) end
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
    menu:Render(true)
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
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] Launcher presentation " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do print("[ZombieSim]     " .. failure) end
    end
    print(string.format("[ZombieSim] Launcher presentation tests: %d passed, %d failed.", summary.passed, summary.failed))
end)
