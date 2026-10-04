local Music = ZM_Music
if Music.Pause then Music:Pause() end
local enabled = CreateClientConVar("zombiesim_music_enabled", "1", true, false, "Enables environment music.", 0, 1)
local volume = GetConVar("snd_musicvolume")
Music.Generation = (Music.Generation or 0) + 1
Music.Mode = "waiting"
Music.Assets = {}
Music.Gain = 0
Music.Channel = nil
Music.Profile = nil
Music.State = nil

local function registry()
    local data = ZM_StaticData:GetRegistry()
    return data and data.music
end

local function active()
    local target = LocalPlayer()
    return IsValid(target) and ZM_World:IsLoaded() and target:GetWorldCell() ~= nil
        and not (ZM_LauncherMenu and ZM_LauncherMenu.Active)
        and not (ZM_LoadingScreen and ZM_LoadingScreen:IsHidingHud())
end

function Music:GetContext()
    local target = LocalPlayer()
    if not IsValid(target) then return {} end
    local zoneId = ZM_SafeZones:IsPlayerInside(target) and target:GetNWString("CurrentSafeZoneId", "") or nil
    local origin = ZM_SafeZones:GetOrigin()
    local environment = ZM_World:GetEnvironment(target:GetWorldCell()) or {}
    return { safeZoneId = zoneId, isOrigin = origin and zoneId == origin.id, tags = environment.tags or {} }
end

function Music:Save()
    if not self.State or not self.Profile then return end
    if IsValid(self.Channel) then
        self.State.position = self.Channel:GetTime()
        local track = registry() and registry().tracks[self.State.trackId]
        if track and self.State.position >= track.duration then
            self.State.trackId, self.State.position = nil, nil
            self.State.nextAt = os.time() + self.IdleDelay(registry())
        end
    end
    local encoded = util.TableToJSON(self.State)
    local path = "zombiesim/music_" .. self.Profile .. ".json"
    file.CreateDir("zombiesim")
    file.Write(path, encoded)
    self.Saved = file.Read(path, "DATA") == encoded
    if not self.Saved then ErrorNoHalt("[ZombieSim] Could not persist local music resume state.\n") end
end

function Music:Pause()
    self.Generation = (self.Generation or 0) + 1
    self:Save()
    if IsValid(self.Channel) then self.Channel:Stop() end
    self.Channel, self.Gain = nil, 0
    self.Mode = "paused"
end

function Music:Schedule()
    self.Gain = 0
    self.State.trackId, self.State.position = nil, nil
    self.State.nextAt = os.time() + self.IdleDelay(registry())
    self.Mode = "waiting"
    self:Save()
end

function Music:ApplyContext(context)
    local action, set = self.TransitionAction(self.State, registry(), context)
    local changed = self.State.routeSet ~= set or self.State.safeZoneId ~= context.safeZoneId
    if action == "silence" or action == "switch" then self:Pause() end
    self.State.routeSet, self.State.safeZoneId = set, context.safeZoneId
    if action == "silence" then
        self.LastTransition = action
        self:Schedule()
    elseif action == "switch" then
        self.LastTransition = action
        self.State.trackId, self.State.position = nil, nil
        self.State.nextAt = os.time()
        self.Mode = "waiting"
        self:Save()
    elseif changed then
        self:Save()
    end
end

function Music:Failure(trackId, message, fallbackUsed)
    self.LastError = tostring(trackId) .. ": " .. tostring(message)
    ErrorNoHalt("[ZombieSim] Music playback failed: " .. self.LastError .. "\n")
    if not fallbackUsed then
        local data, available = registry(), {}
        for _, id in ipairs(data.sets[data.defaultSet]) do
            if id ~= trackId and file.Exists(data.tracks[id].file, "GAME") then available[#available + 1] = id end
        end
        if #available > 0 then self:Start(available[math.random(#available)], 0, true) return end
    end
    self:Schedule()
end

function Music:Start(trackId, position, fallbackUsed)
    local data = registry()
    local track = data and data.tracks[trackId]
    if not track then self:Failure(trackId, "unknown track", fallbackUsed) return end
    self:Pause()
    local generation = self.Generation
    self.State.trackId, self.State.position = trackId, position or 0
    self.Mode, self.FallbackUsed = "loading", fallbackUsed == true
    self:Save()
    local step = ZM_Loading:Begin("Loading music: " .. track.name)
    sound.PlayFile(track.file, "noplay noblock", function(channel, errorId, errorName)
        if generation ~= self.Generation then
            if IsValid(channel) then channel:Stop() end
            ZM_Loading:Finish(step, "info", "Music load cancelled")
            return
        end
        if not IsValid(channel) then
            ZM_Loading:Finish(step, "warn", "Music unavailable")
            self:Failure(trackId, tostring(errorName) .. " (" .. tostring(errorId) .. ")", fallbackUsed)
            return
        end
        local length = channel:GetLength()
        if not self.DurationMatches(length, track.duration) then
            channel:Stop()
            ZM_Loading:Finish(step, "warn", "Music duration validation failed")
            self:Failure(trackId, "duration mismatch: " .. tostring(length) .. " vs " .. track.duration, fallbackUsed)
            return
        end
        if not active() or not enabled:GetBool() or volume:GetFloat() <= 0 then
            channel:Stop()
            self.Mode = "paused"
            ZM_Loading:Finish(step, "info", "Music paused")
            return
        end
        channel:SetVolume(0)
        channel:SetTime(math.Clamp(position or 0, 0, math.max(0, length - 0.01)))
        channel:Play()
        self.Channel, self.Mode, self.Gain = channel, "playing", 0
        self.ActualDuration = length
        self.NextSave = RealTime() + 30
        ZM_Loading:Finish(step, "ok", "Playing " .. track.name)
    end)
end

function Music:Depart(seconds)
    if not self.State then return end
    self:Save()
    if self.Mode == "playing" and IsValid(self.Channel) then
        self.Mode = "departure"
        self.DepartureStart, self.DepartureDuration = RealTime(), math.max(0.01, seconds or 1)
        self.DepartureGain = self.Gain
    else
        self:Pause()
    end
end

local nextContext = 0
hook.Add("Think", "ZM.Music", function()
    local data = registry()
    if not data or not ZM_World:IsLoaded() then return end
    if Music.Profile ~= ZM_World.ActiveProfile then
        Music:Pause()
        Music.Profile = ZM_World.ActiveProfile
        local path = "zombiesim/music_" .. Music.Profile .. ".json"
        local exists = file.Exists(path, "DATA")
        local saved = exists and util.JSONToTable(file.Read(path, "DATA") or "") or nil
        if exists and not Music.ValidResume(saved, data) then
            ErrorNoHalt("[ZombieSim] Invalid local music resume state; scheduling a new track.\n")
            saved = nil
        end
        Music.State = saved or { version = 1, nextAt = os.time() + Music.IdleDelay(data) }
        Music:Save()
    end
    if Music.Mode == "departure" then
        nextContext = 0
        local fraction = math.Clamp((RealTime() - Music.DepartureStart) / Music.DepartureDuration, 0, 1)
        if not IsValid(Music.Channel) or fraction >= 1 then Music:Pause()
        else Music.Channel:SetVolume(Music.DepartureGain * (1 - fraction)) end
        return
    end
    if not active() then
        nextContext = 0
        if Music.Mode == "playing" or Music.Mode == "loading" then Music:Pause() end
        return
    end
    if RealTime() >= nextContext then
        nextContext = RealTime() + 0.25
        local context = Music:GetContext()
        Music.ResolvedSet, Music.ResolvedKey = Music.Resolve(data, context)
        Music:ApplyContext(context)
    end
    if not enabled:GetBool() or volume:GetFloat() <= 0 then
        if Music.Mode == "playing" or Music.Mode == "loading" then Music:Pause() end
        return
    end
    if Music.Mode == "playing" then
        if not IsValid(Music.Channel) then Music:Failure(Music.State.trackId, "channel invalidated", Music.FallbackUsed) return end
        if Music.Channel:GetState() == GMOD_CHANNEL_STOPPED then
            Music.Channel:Stop()
            Music.Channel = nil
            Music:Schedule()
            return
        end
        local intensity = ZM_RadiationFeedback.SensoryIntensity(ZM_RadiationFeedback.GetClientChannels())
        local targetGain = Music.OutputGain(volume:GetFloat(), intensity)
        Music.Gain = Lerp(1 - math.exp(-3 * FrameTime()), Music.Gain, targetGain)
        Music.Channel:SetVolume(Music.Gain)
        if RealTime() >= Music.NextSave then Music:Save() Music.NextSave = RealTime() + 30 end
    elseif Music.Mode ~= "loading" then
        Music.Mode = "waiting"
        if Music.State.trackId then Music:Start(Music.State.trackId, Music.State.position)
        elseif os.time() >= Music.State.nextAt then
            Music:Start(Music.Select(data, Music.ResolvedSet or data.defaultSet), 0)
        end
    end
end)

hook.Add("ZM.MusicDeparture", "ZM.Music", function(seconds) Music:Depart(seconds) end)
hook.Add("ShutDown", "ZM.Music", function() Music:Pause() end)

function Music:GetDiagnosticSnapshot()
    return {
        enabled = enabled:GetBool(), volume = volume:GetFloat(), gain = self.Gain, mode = self.Mode,
        masterVolume = GetConVar("volume"):GetFloat(), effectsVolume = GetConVar("volume_sfx"):GetFloat(),
        volumeConVar = "snd_musicvolume", effectsConVar = "volume_sfx",
        profile = self.Profile, resolvedSet = self.ResolvedSet, resolvedKey = self.ResolvedKey,
        trackId = self.State and self.State.trackId, position = IsValid(self.Channel) and self.Channel:GetTime()
            or self.State and self.State.position, nextAt = self.State and self.State.nextAt,
        duration = self.ActualDuration, channelState = IsValid(self.Channel) and self.Channel:GetState(),
        saved = self.Saved, fallbackUsed = self.FallbackUsed, lastError = self.LastError,
        trackSet = self.State and self.State.routeSet, trackSafeZoneId = self.State and self.State.safeZoneId,
        lastTransition = self.LastTransition,
        assets = table.Copy(self.Assets)
    }
end

function Music:ValidateAssets()
    local data = registry()
    if not data then ErrorNoHalt("[ZombieSim] Music registry unavailable; asset check cannot run.\n") return end
    for id, track in pairs(data.tracks) do
        self.Assets[id] = { loading = true }
        sound.PlayFile(track.file, "noplay noblock", function(channel, errorId, errorName)
            local length = IsValid(channel) and channel:GetLength() or 0
            local passed = self.DurationMatches(length, track.duration)
            self.Assets[id] = { passed = passed, duration = length, expected = track.duration,
                error = not passed and tostring(errorName or "duration mismatch") .. " (" .. tostring(errorId) .. ")" or nil }
            if IsValid(channel) then channel:Stop() end
            if not passed then ErrorNoHalt("[ZombieSim] Music asset check failed: " .. id .. "\n") end
        end)
    end
end

concommand.Add("zombiesim_music_probe", function(_, _, arguments)
    if ZM_World.ActiveProfile ~= "preview" or not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then
        ErrorNoHalt("[ZombieSim] Music probes require an admin preview session.\n") return
    end
    local action = arguments[1] or "status"
    if action == "assets" then Music:ValidateAssets()
    elseif action == "status" then
        file.CreateDir("zombiesim")
        file.Write("zombiesim/music_status.json", util.TableToJSON(Music:GetDiagnosticSnapshot(), true))
    elseif action == "play" or action == "default" or action == "sewer"
        or registry() and registry().tracks[action] then
        if not Music.State or not active() then ErrorNoHalt("[ZombieSim] Deploy before starting a music probe.\n") return end
        local data = registry()
        if data.tracks[action] then Music:Start(action, 0)
        else
            local set = action == "play" and Music.Resolve(data, Music:GetContext())
                or action == "default" and data.defaultSet or "sewer"
            Music:Start(Music.Select(data, set), 0)
        end
    else ErrorNoHalt("[ZombieSim] Unknown music probe action.\n") end
end)
