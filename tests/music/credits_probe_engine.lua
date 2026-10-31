fixture = { now = 10, map = "zn_preview_start", writes = 0, errors = {}, sent = {}, logs = {} }

local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
local function vector(x, y, z) return setmetatable({ kind = "vector", x = x, y = y, z = z }, vectorMeta) end
local angleMeta = {}
angleMeta.__index = angleMeta
function angleMeta:Forward() return self.forward end
function angleMeta:Right() return self.right end
function angleMeta:Up() return self.up end
local function angle(p, y, r, forward, right, up)
    return setmetatable({ kind = "angle", p = p, y = y, r = r,
        forward = forward or vector(1, 0, 0), right = right or vector(0, 1, 0),
        up = up or vector(0, 0, 1) }, angleMeta)
end
fixture.vector, fixture.angle = vector, angle

local entityMeta = {}
entityMeta.__index = entityMeta
function entityMeta:GetModel() return self.model end
function entityMeta:GetClass() return "prop_ragdoll" end
function entityMeta:SetupBones() self.setups = self.setups + 1 end
function entityMeta:LookupBone(name)
    assert(name == "ValveBiped.Bip01_Head1")
    if not self.noHead then return 6 end
end
function entityMeta:GetBoneParent(index) assert(index == 6) return 5 end
function entityMeta:TranslateBoneToPhysBone(index) assert(index == 6) return 2 end
function entityMeta:GetBoneName(index) assert(index == 5) return "neck" end
function entityMeta:GetBoneMatrix(index)
    assert(index == 6)
    if not self.noMatrix then return self.matrix end
end
function entityMeta:LookupAttachment(name) assert(name == "eyes") return self.noEyes and 0 or 1 end
function entityMeta:GetAttachment(index)
    assert(index == 1)
    return { Bone = 6, Pos = vector(12, 4, 80),
        Ang = angle(0, 90, 0, vector(0, 1, 0), vector(-1, 0, 0), vector(0, 0, 1)) }
end

fixture.dancers = {}
Menu = { Active = true, Credits = true, Profile = "preview", DancerNames = {}, DancerIds = {} }
Scene = { Phase = "orbit", LastCreditsView = { origin = vector(20, 10, 90), angles = angle(0, 0, 0) },
    LastCreditsViewAt = 9.9 }
function Scene:GetDancer(index) return fixture.dancers[index] end
for index, name in ipairs({ "gman", "alyx", "barney", "kleiner" }) do
    local matrix = { position = vector(index, 2, 70), angles = angle(0, 0, 0) }
    function matrix:GetTranslation() return self.position end
    function matrix:GetAngles() return self.angles end
    fixture.dancers[index] = setmetatable({ valid = true, model = "models/" .. name .. ".mdl",
        matrix = matrix, setups = 0 }, entityMeta)
    Menu.DancerNames[index], Menu.DancerIds[index] = "dancing_" .. name, 100 + index
end
fixture.player = { valid = true, admin = true }
function fixture.player:IsAdmin() return self.admin end
function fixture.player:ConCommand(command) table.insert(fixture.sent, command) end
fixture.channel = { valid = true }
function fixture.channel:GetState() return 1 end
function fixture.channel:GetTime() return 5 end
function fixture.channel:GetLength() return 225 end
Music = { CreditsMusic = { phase = "playing", path = "sounds/music/credits.mp3", channel = fixture.channel } }

function isvector(value) return type(value) == "table" and value.kind == "vector" end
function isangle(value) return type(value) == "table" and value.kind == "angle" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function LocalPlayer() return fixture.player end
function RealTime() return fixture.now end
function ErrorNoHalt(message) table.insert(fixture.errors, message) end
function print(message) table.insert(fixture.logs, message) end
game = { GetMap = function() return fixture.map end }
concommand = {
    Remove = function(name) assert(name == "zombiesim_dev_credits_status") end,
    Add = function(name, callback)
        assert(name == "zombiesim_dev_credits_status")
        fixture.command = callback
    end
}
file = {
    CreateDir = function(path) assert(path == "zombiesim") end,
    Write = function(path, contents)
        assert(path == "zombiesim/credits-status.json" and contents == "fixture-json")
        if fixture.failWrite then return false end
        fixture.writes, fixture.report = fixture.writes + 1, fixture.encoded
        return true
    end
}
util = { TableToJSON = function(report, pretty)
    assert(pretty == true)
    fixture.encoded = report
    return "fixture-json"
end }
function fixture:Capture(id) self.command(nil, nil, { id }) end
