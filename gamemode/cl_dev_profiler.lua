// Development profiler: temporarily wraps every per-frame client hook, times each call with SysTime, then restores
// the original callbacks and writes data/zombiesim/hook_profile.json. Usage: zombiesim_dev_profile_hooks [seconds]
ZM_DevProfiler = ZM_DevProfiler or {}
local Profiler = ZM_DevProfiler

local profiledEvents = {
    "Think", "Tick", "PreRender", "PostRender", "CalcView", "SetupWorldFog", "SetupSkyboxFog",
    "PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "PreDrawTranslucentRenderables",
    "PostDrawTranslucentRenderables", "RenderScreenspaceEffects", "PreDrawHUD", "HUDPaintBackground", "HUDPaint", "PostDrawHUD",
    "DrawOverlay", "HUDShouldDraw"
}
local outputPath = "zombiesim/hook_profile.json"

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
