// Development profiler: temporarily wraps every per-frame client hook, times each call with SysTime, then restores
// the original callbacks and writes data/zombiesim/hook_profile.json. Usage: zombiesim_dev_profile_hooks [seconds]
ZM_DevProfiler = ZM_DevProfiler or {}
local Profiler = ZM_DevProfiler

local profiledEvents = {
    "Think", "Tick", "PreRender", "PostRender", "CalcView", "RenderScene", "SetupWorldFog", "SetupSkyboxFog", "PostDraw2DSkyBox",
    "PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "PreDrawTranslucentRenderables",
    "PostDrawTranslucentRenderables", "RenderScreenspaceEffects", "PreDrawHUD", "HUDPaintBackground", "HUDPaint", "PostDrawHUD",
    "DrawOverlay", "HUDShouldDraw"
}
local outputPath = "zombiesim/hook_profile.json"
local captureRequests = {}

concommand.Add("zombiesim_dev_ui", function(_, _, arguments)
    local survivor = LocalPlayer()
    if not IsValid(survivor) or not survivor:IsAdmin() or not ZM_World or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] UI inspection requires a preview admin.\n")
        return
    end
    local mode = arguments[1]
    if #arguments ~= 1 or (mode ~= "inventory" and mode ~= "scoreboard" and mode ~= "wardrobe" and
        mode ~= "options" and mode ~= "sky" and mode ~= "sky_edit" and mode ~= "tools" and mode ~= "close") then
        ErrorNoHalt("[ZombieSim] Usage: zombiesim_dev_ui inventory|scoreboard|wardrobe|options|sky|sky_edit|close\n")
        return
    end
    Profiler.LastUIRequest = { mode = mode, receivedAt = RealTime() }
    if mode == "inventory" then
        ZM_Inventory:Open()
    elseif mode == "scoreboard" then
        ZM_Scoreboard:Open()
    elseif mode == "wardrobe" then
        ZM_Wardrobe:Open()
    elseif mode == "tools" then
        ZM_LauncherTools:Open()
    elseif mode == "options" then
        ZM_Options:Open()
    elseif mode == "sky" or mode == "sky_edit" then
        if not IsValid(ZM_Options.Frame) then ZM_Options:Open() end
        ZM_SkyBrowser:Open(ZM_Options.Frame)
        if mode == "sky_edit" then
            local id = GetConVar("zombiesim_sky_palette"):GetString()
            ZM_SkyBrowser:OpenEditor(ZM_SkyPalettes:GetProfile(id) and id or nil)
        end
    else
        if ZM_LauncherMenu and ZM_LauncherMenu.Page == "tools" and IsValid(ZM_LauncherMenu.Frame) then
            ZM_LauncherMenu.Page = "menu"
            ZM_LauncherMenu:Render()
        end
        if ZM_SkyBrowser then ZM_SkyBrowser:Close() end
        if IsValid(ZM_Options.Frame) then ZM_Options.Frame:Close() end
        if IsValid(ZM_Inventory.Frame) then ZM_Inventory.Frame:Close() end
        if IsValid(ZM_Scoreboard.Frame) then ZM_Scoreboard.Frame:Remove() end
        if ZM_Wardrobe and IsValid(ZM_Wardrobe.Frame) then ZM_Wardrobe.Frame:Close() end
    end
end)

concommand.Add("zombiesim_dev_capture", function(_, _, arguments)
    local player = LocalPlayer()
    local label = arguments[1] or ""
    if not IsValid(player) or not player:IsAdmin() or not ZM_World or ZM_World.ActiveProfile ~= "preview" then
        ErrorNoHalt("[ZombieSim] Screenshot capture requires a preview admin.\n")
        return
    end
    if (#arguments ~= 1 and #arguments ~= 3 and #arguments ~= 6) or
        #label < 1 or #label > 48 or not string.match(label, "^[%w_-]+$") then
        ErrorNoHalt("[ZombieSim] Invalid screenshot label.\n")
        return
    end
    local numbers = {}
    for index = 2, #arguments do
        local value = tonumber(arguments[index])
        if not value or value ~= value or math.abs(value) > 32768 then
            ErrorNoHalt("[ZombieSim] Screenshot angles/origin must be finite numbers within engine bounds.\n")
            return
        end
        numbers[index] = value
    end
    if #captureRequests >= 8 then
        ErrorNoHalt("[ZombieSim] Screenshot queue is full; wait for pending captures.\n")
        return
    end
    captureRequests[#captureRequests + 1] = {
        label = label, requestedAt = RealTime(),
        angles = #arguments > 1 and Angle(math.Clamp(numbers[2], -89, 89), numbers[3], 0) or nil,
        origin = #arguments == 6 and Vector(numbers[4], numbers[5], numbers[6]) or nil
    }
end)

local function renderCaptureView(angles, requestedOrigin)
    local player = LocalPlayer()
    local origin = requestedOrigin or player:EyePos()
    local ok = ZM_Skybox:RenderClientView({ origin = origin, angles = angles, x = 0, y = 0,
        w = ScrW(), h = ScrH(), fov = 75, drawhud = false, drawviewmodel = false })
    if not ok then return nil end
    return origin
end

local function captureFrame(afterVGUI)
    local request = captureRequests[1]
    if not request or Profiler.LastCaptureFrame == FrameNumber() then return end
    local visibleUI = (ZM_Inventory and IsValid(ZM_Inventory.Frame)) or
        (ZM_Scoreboard and IsValid(ZM_Scoreboard.Frame)) or (ZM_Wardrobe and IsValid(ZM_Wardrobe.Frame)) or
        (ZM_Options and IsValid(ZM_Options.Frame)) or (ZM_SkyBrowser and IsValid(ZM_SkyBrowser.Frame)) or
        (ZM_LauncherMenu and ZM_LauncherMenu.Page == "tools" and IsValid(ZM_LauncherMenu.Frame))
    local needsVGUI = not request.angles and visibleUI == true
    if needsVGUI ~= afterVGUI then return end
    if ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud() then
        if RealTime() - request.requestedAt < 30 then return end
        table.remove(captureRequests, 1)
        ErrorNoHalt("[ZombieSim] Screenshot timed out behind the loading screen.\n")
        return
    end
    table.remove(captureRequests, 1)
    Profiler.LastCaptureFrame = FrameNumber()
    local captureOrigin = request.angles and renderCaptureView(request.angles, request.origin)
    if request.angles and not captureOrigin then return end
    local data = render.Capture({ format = "png", x = 0, y = 0, w = ScrW(), h = ScrH(), alpha = false })
    if not data then
        ErrorNoHalt("[ZombieSim] Screenshot capture failed; close the Escape menu and retry.\n")
        return
    end
    file.CreateDir("zombiesim/screenshots")
    local path = "zombiesim/screenshots/" .. request.label
    file.Write(path .. ".png", data)
    file.Write(path .. ".json", util.TableToJSON({
        map = game.GetMap(), capturedAt = os.time(), requestedAt = request.requestedAt,
        afterVGUI = afterVGUI, frameNumber = FrameNumber(),
        viewOrigin = captureOrigin or ZM_Skybox and ZM_Skybox.ViewOrigin,
        viewForward = request.angles and request.angles:Forward() or ZM_Skybox and ZM_Skybox.ViewForward,
        skybox = ZM_Skybox and ZM_Skybox:GetDiagnosticSnapshot(),
        skyPalette = ZM_SkyPalettes and ZM_SkyPalettes:GetDiagnosticSnapshot(),
        skyBrowser = ZM_SkyBrowser and ZM_SkyBrowser:GetDiagnosticSnapshot(),
        skyInspection = ZM_SkyInspection and ZM_SkyInspection:GetDiagnosticSnapshot(),
        launcherTools = ZM_LauncherTools and ZM_LauncherTools:GetDiagnosticSnapshot(),
        clothing = ZM_ClothingPreview and ZM_ClothingPreview:GetDiagnosticSnapshot(),
        equippedClothing = ZM_Clothing and ZM_Clothing.GetDiagnosticSnapshot and ZM_Clothing:GetDiagnosticSnapshot(),
        wardrobe = ZM_Wardrobe and ZM_Wardrobe:GetDiagnosticSnapshot(),
        ui = { request = Profiler.LastUIRequest,
            inventory = ZM_Inventory and IsValid(ZM_Inventory.Frame),
            options = ZM_Options and IsValid(ZM_Options.Frame),
            scoreboard = ZM_Scoreboard and IsValid(ZM_Scoreboard.Frame) },
        fog = ZM_Atmosphere and ZM_Atmosphere:GetFogSettings(),
        lightScale = GetConVar("zombiesim_sky_light_scale"):GetFloat(),
        detail = GetConVar("zombiesim_sky_detail"):GetInt(),
        props = GetConVar("zombiesim_sky_props"):GetFloat(),
        fires = GetConVar("zombiesim_sky_fires"):GetBool()
    }, true))
    print("[ZombieSim] Screenshot saved to data/" .. path .. ".png")
end

hook.Add("PostRender", "ZM.DevProfiler.Capture", function()
    captureFrame(false)
end)
hook.Add("PostRenderVGUI", "ZM.DevProfiler.CaptureUI", function()
    captureFrame(true)
end)

local function restoreHooks()
    for _, entry in ipairs(Profiler.Wrapped or {}) do
        local current = hook.GetTable()[entry.event]
        if current and current[entry.name] == entry.wrapper then
            hook.Add(entry.event, entry.name, entry.original)
        end
    end
    Profiler.Wrapped = nil
    hook.Remove("PostRender", "ZM.DevProfiler.Frame")
end

local function finishProfile()
    local session = Profiler.Session
    Profiler.Session = nil
    restoreHooks()
    if not session then return end

    local frames = math.max(1, session.frames)
    local results = {}
    for key, stats in pairs(session.stats) do
        results[#results + 1] = {
            hook = key,
            calls = stats.calls,
            totalMs = stats.total * 1000,
            msPerFrame = stats.total * 1000 / frames,
            maxMs = stats.max * 1000,
            allocatedKbPerFrame = stats.allocated / frames
        }
    end
    table.sort(results, function(a, b) return a.totalMs > b.totalMs end)

    local frameTimes = session.frameTimes
    table.sort(frameTimes)
    local function percentile(fraction)
        if #frameTimes == 0 then return 0 end
        return frameTimes[math.Clamp(math.ceil(#frameTimes * fraction), 1, #frameTimes)] * 1000
    end
    local hookTotal = 0
    for _, result in ipairs(results) do hookTotal = hookTotal + result.msPerFrame end
    local slowFrames = 0
    for _, frameTime in ipairs(frameTimes) do
        if frameTime > 1 / 59.5 then slowFrames = slowFrames + 1 end
    end

    local report = {
        map = game.GetMap(),
        seconds = SysTime() - session.started,
        frames = session.frames,
        averageFps = session.frames / math.max(0.001, SysTime() - session.started),
        frameMs = { p50 = percentile(0.5), p95 = percentile(0.95), p99 = percentile(0.99), max = percentile(1) },
        framesOver60Hz = slowFrames,
        luaHookMsPerFrame = hookTotal,
        // Rough Lua allocation rate: positive heap growth between frames (garbage-collection cycles are excluded).
        allocatedKbPerFrame = session.allocated / frames,
        weather = ZM_Atmosphere and ZM_Atmosphere.Weather or nil,
        snowCover = ZM_Atmosphere and ZM_Atmosphere.SnowCoverAmount or nil,
        puddleRenderLobes = ZM_Atmosphere and ZM_Atmosphere.PuddleRenderLobes or nil,
        puddleDropRings = ZM_Atmosphere and ZM_Atmosphere.PuddleDropRings or nil,
        skyInspection = ZM_SkyInspection and ZM_SkyInspection:GetDiagnosticSnapshot() or nil,
        hooks = results
    }
    file.CreateDir("zombiesim")
    file.Write(outputPath, util.TableToJSON(report, true))
    print(string.format("[ZombieSim] Hook profile: %d frames, %.1f fps, frame p50 %.2f / p95 %.2f / max %.2f ms, Lua hooks %.3f ms/frame, %.1f KB/frame allocated.",
        report.frames, report.averageFps, report.frameMs.p50, report.frameMs.p95, report.frameMs.max,
        report.luaHookMsPerFrame, report.allocatedKbPerFrame))
    for index = 1, math.min(12, #results) do
        local result = results[index]
        print(string.format("  %-60s %7.3f ms/frame  max %6.2f ms  %6.2f KB/frame", result.hook, result.msPerFrame,
            result.maxMs, result.allocatedKbPerFrame))
    end
    print("[ZombieSim] Hook profile saved to data/" .. outputPath)
end

function Profiler:Start(seconds)
    if self.Session then
        print("[ZombieSim] A hook profile is already running.")
        return
    end
    seconds = math.Clamp(tonumber(seconds) or 10, 1, 120)
    local session = { stats = {}, frames = 0, frameTimes = {}, allocated = 0, started = SysTime() }
    self.Session = session
    self.Wrapped = {}
    local hooks = hook.GetTable()
    for _, event in ipairs(profiledEvents) do
        for name, original in pairs(hooks[event] or {}) do
            if isstring(name) and isfunction(original) then
                local key = event .. " / " .. name
                local stats = { calls = 0, total = 0, max = 0, allocated = 0 }
                session.stats[key] = stats
                local wrapper = function(...)
                    local memoryBefore = collectgarbage("count")
                    local started = SysTime()
                    local a, b, c, d, e, f = original(...)
                    local elapsed = SysTime() - started
                    local allocated = collectgarbage("count") - memoryBefore
                    stats.calls = stats.calls + 1
                    stats.total = stats.total + elapsed
                    // A collection inside the call makes the delta negative; those calls are skipped.
                    if allocated > 0 then stats.allocated = stats.allocated + allocated end
                    if elapsed > stats.max then stats.max = elapsed end
                    return a, b, c, d, e, f
                end
                self.Wrapped[#self.Wrapped + 1] = { event = event, name = name, original = original, wrapper = wrapper }
            end
        end
    end
    for _, entry in ipairs(self.Wrapped) do
        hook.Add(entry.event, entry.name, entry.wrapper)
    end

    local lastFrame, lastMemory = SysTime(), collectgarbage("count")
    hook.Add("PostRender", "ZM.DevProfiler.Frame", function()
        local now, memory = SysTime(), collectgarbage("count")
        session.frames = session.frames + 1
        session.frameTimes[#session.frameTimes + 1] = now - lastFrame
        if memory > lastMemory then session.allocated = session.allocated + memory - lastMemory end
        lastFrame, lastMemory = now, memory
    end)
    timer.Create("ZM.DevProfiler.Finish", seconds, 1, finishProfile)
    print(string.format("[ZombieSim] Profiling %d client hooks for %d s.", #self.Wrapped, seconds))
end

concommand.Add("zombiesim_dev_profile_hooks", function(_, _, arguments)
    Profiler:Start(arguments and arguments[1])
end)
