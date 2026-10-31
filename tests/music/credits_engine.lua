fixture = {
    now = 1, frameTime = 0.1, musicEnabled = true, musicVolume = 0.8,
    pending = {}, channels = {}, hooks = {}, commands = {}, timers = {},
    errors = {}, requests = {}, cues = {}, paths = {
        ["sounds/music/menu.mp3"] = true,
        ["sounds/music/menu 2.mp3"] = true,
        ["sounds/music/credits.mp3"] = true,
        ["sounds/music/preview skybox 1.mp3"] = true
    }
}

ZM_Music = {}
ZM_LauncherMenu = { Active = true, CreditsCamera = {}, CreditsGeneration = 0 }
Menu = ZM_LauncherMenu
function Menu:SyncCharacterPreview() self.previewSynced = true end
function Menu:PlayCue(name) table.insert(fixture.cues, name) end
function Menu:Request(action, slot) table.insert(fixture.requests, { action = action, slot = slot }) end
ZM_LauncherSceneClient = {
    BeginCredits = function(self)
        Menu.CreditsGeneration = Menu.CreditsGeneration + 1
        Menu.CreditsEnding, self.Started, Menu.Credits = nil, fixture.now, true
    end
}
ZM_LauncherScene = { GetData = function() return { credits = {} } end }
ZM_StaticData = { GetRegistry = function() return nil end }
ZM_World = { IsLoaded = function() return false end }

KEY_ESCAPE, KEY_ENTER, KEY_SPACE = 70, 71, 72
TEXT_ALIGN_CENTER = 1
GMOD_CHANNEL_STOPPED, GMOD_CHANNEL_PLAYING, GMOD_CHANNEL_PAUSED = 0, 1, 2
palette = { text = {} }

function IsValid(value) return type(value) == "table" and value.valid == true end
function LocalPlayer() return nil end
function RealTime() return fixture.now end
function FrameTime() return fixture.frameTime end
function ScrW() return 1280 end
function ScrH() return 720 end
function ErrorNoHalt(message) table.insert(fixture.errors, message) end
function CreateClientConVar(name)
    assert(name == "zombiesim_music_enabled")
    return { GetBool = function() return fixture.musicEnabled end }
end
function GetConVar(name)
    assert(name == "snd_musicvolume")
    return { GetFloat = function() return fixture.musicVolume end }
end
function math.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end
function Lerp(amount, first, second) return first + amount * (second - first) end

file = {
    Exists = function(path, realm)
        assert(realm == "GAME")
        return fixture.paths[path] == true
    end
}
hook = {
    Add = function(event, name, callback)
        assert((event == "Think" and (name == "ZM.Music" or name == "ZM.Music.SkyPreview"))
            or (event == "ShutDown" and (name == "ZM.Music" or name == "ZM.Music.SkyPreview"))
            or (event == "ZM.MusicDeparture" and name == "ZM.Music"))
        fixture.hooks[event .. ":" .. name] = callback
    end
}
concommand = {
    Add = function(name, callback)
        assert(name == "zombiesim_music_probe")
        fixture.commands[name] = callback
    end
}
sound = {
    PlayFile = function(path, flags, callback)
        assert(fixture.paths[path] and (flags == "noplay" or flags == "noplay noblock"))
        table.insert(fixture.pending, { path = path, flags = flags, callback = callback })
    end
}
timer = {
    Simple = function(delay, callback)
        table.insert(fixture.timers, { due = fixture.now + delay, callback = callback })
    end
}
surface = { SetDrawColor = function() end, DrawRect = function() end }
draw = { SimpleText = function() end }

local panel = {}
panel.__index = panel
function panel:SetSize(width, height) self.width, self.height = width, height end
function panel:SetPos(x, y) self.x, self.y = x, y end
function panel:SetTitle(title) self.title = title end
function panel:ShowCloseButton(value) self.closeButton = value end
function panel:SetDraggable(value) self.draggable = value end
function panel:MakePopup() self.popup = true end
function panel:SetVisible(value) self.visible = value end
function panel:Remove()
    if not self.valid then return end
    self.valid = false
    if self.OnRemove then self:OnRemove() end
end
vgui = {
    Create = function(class)
        assert(class == "DFrame")
        return setmetatable({ valid = true, visible = true }, panel)
    end
}
Menu.Frame = vgui.Create("DFrame")

local channel = {}
channel.__index = channel
function channel:Play()
    assert(self.valid)
    for _, other in ipairs(fixture.channels) do
        assert(other == self or other.state ~= GMOD_CHANNEL_PLAYING, "music channels overlapped")
    end
    self.state = GMOD_CHANNEL_PLAYING
    self.plays = self.plays + 1
end
function channel:Pause()
    assert(self.valid)
    self.state = GMOD_CHANNEL_PAUSED
    self.pauses = self.pauses + 1
end
function channel:Stop()
    assert(self.valid)
    self.state, self.valid = GMOD_CHANNEL_STOPPED, false
    self.stops = self.stops + 1
end
function channel:SetVolume(value) assert(self.valid) self.volume = value end
function channel:EnableLooping(value) self.looping = value end
function channel:GetState() assert(self.valid) return self.state end
function channel:GetTime() assert(self.valid) return self.position end
function channel:GetLength() assert(self.valid) return self.length end

function fixture:Complete(index, fail)
    local request = assert(self.pending[index])
    assert(not request.completed)
    request.completed = true
    if fail then
        request.callback(nil, 42, "fixture decoding error")
        return nil
    end
    local result = setmetatable({ valid = true, state = GMOD_CHANNEL_STOPPED,
        position = 0, length = 225, plays = 0, pauses = 0, stops = 0, path = request.path }, channel)
    table.insert(self.channels, result)
    request.callback(result)
    return result
end

function fixture:Advance(seconds)
    self.now = self.now + seconds
    self.hooks["Think:ZM.Music"]()
    local pending = self.timers
    self.timers = {}
    for _, entry in ipairs(pending) do
        if entry.due <= self.now then entry.callback()
        else table.insert(self.timers, entry) end
    end
end
