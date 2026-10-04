local registry = ZM_StaticData:GetRegistry()
if registry and registry.music then
    for _, track in pairs(registry.music.tracks) do resource.AddFile(track.file) end
end

ZM_Util.RegisterCommands({
    zombiesim_dev_music = "Preview-only music check: play|default|sewer|assets|status, or a catalogue track id."
}, function(caller, command, arguments)
    local target = ZM_Util.ResolveCommandTarget(caller, command)
    if not IsValid(target) then return false, "no admin player" end
    if not target:IsAdmin() or ZM_World.ActiveProfile ~= "preview" then
        ZM_Util.Reply(caller, "Music probes require an admin preview session.")
        return false, "admin preview required"
    end
    local action = arguments[1] or "status"
    local data = ZM_StaticData:GetRegistry()
    local knownTrack = data and data.music and data.music.tracks[action] ~= nil
    if not knownTrack and not ({ play = true, default = true, sewer = true, assets = true, status = true })[action] then
        ZM_Util.Reply(caller, "Usage: " .. command .. " play|default|sewer|assets|status|<trackId>")
        return false, "unknown music probe"
    end
    target:ConCommand("zombiesim_music_probe " .. action)
    ZM_Util.Reply(caller, "Requested client music " .. action .. " check.")
    return true
end)
