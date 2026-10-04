ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "ZombieSim Den NPC"
ENT.Category = "ZombieSim"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.ZM_IsDenNpc = true

ENT.IdleSequences = { "idle_subtle", "lineidle01", "idle_all_01", "idle01" }

if SERVER then
    for name, method in pairs(ZM_DenNpcs and ZM_DenNpcs.ProviderMethods or {}) do
        ENT[name] = method
    end

    // Den NPCs are few and the level map shows them all, so they are networked outside the PVS too.
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end
end

// "Army Soldier lvl 15  |  Trader" style role line from the networked settings ("" for a plain resident).
function ENT:GetRoleText()
    local job = self:GetNWString("ZM_NpcJob", "")
    local trader = self:GetNWString("ZM_NpcTrader", "")
    local role = ""
    if job ~= "" then
        local profession = ZM_Professions and ZM_Professions:Get(job)
        role = ((profession and profession.name) or job) .. " lvl " .. self:GetNWInt("ZM_NpcLevel", 1)
    end
    if trader ~= "" then role = role ~= "" and (role .. "  |  Trader") or "Trader" end
    return role
end

// Hammer keyvalues arrive before Spawn; they are kept raw and resolved by ZM_DenNpcs against the live static data.
function ENT:KeyValue(key, value)
    self.ZM_Config = self.ZM_Config or {}
    self.ZM_Config[string.lower(key)] = value
end

function ENT:Initialize()
    if SERVER then
        self.ZM_Config = self.ZM_Config or {}
        local model = self.ZM_Config.model
        if type(model) == "string" and model ~= "" and not util.IsValidModel(model) then
            ErrorNoHalt("[ZombieSim] zn_den_npc has invalid model '" .. model .. "'; using its default.\n")
            model = nil
        end
        model = (type(model) == "string" and model ~= "") and model or ZM_DenNpcs.DefaultModel
        self:SetModel(model)
        self:SetSolid(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
        self:SetUseType(SIMPLE_USE)
        local function findSequence(name)
            if type(name) ~= "string" or string.Trim(name) == "" then return nil end
            local sequence = self:LookupSequence(string.Trim(name))
            return sequence and sequence >= 0 and sequence or nil
        end
        local animation = string.Trim(tostring(self.ZM_Config.animation or ""))
        local fallback = string.Trim(tostring(self.ZM_Config.default_animation or ""))
        local sequence = findSequence(animation)
        if animation ~= "" and not sequence then
            ErrorNoHalt("[ZombieSim] zn_den_npc model '" .. model .. "' has no animation sequence '" .. animation .. "'.\n")
        end
        if not sequence then
            sequence = findSequence(fallback)
            if fallback ~= "" and not sequence then
                ErrorNoHalt("[ZombieSim] zn_den_npc model '" .. model .. "' has no default animation sequence '" .. fallback .. "'.\n")
            end
        end
        if not sequence then
            for _, name in ipairs(self.IdleSequences) do
                sequence = findSequence(name)
                if sequence then break end
            end
        end
        if sequence then
            self:ResetSequence(sequence)
        else
            ErrorNoHalt("[ZombieSim] zn_den_npc model '" .. model .. "' has no usable idle animation.\n")
        end
        ZM_DenNpcs:Sync(self)
    end
end

function ENT:Think()
    self:FrameAdvance()
    self:NextThink(CurTime())
    return true
end

function ENT:Use(playerEntity)
    if not ZM_DenNpcs:CanInteract(playerEntity, self, false) then return end
    if playerEntity.ZM_NextDenNpcInteractAt and CurTime() < playerEntity.ZM_NextDenNpcInteractAt then return end
    playerEntity.ZM_NextDenNpcInteractAt = CurTime() + 0.25
    local resolved = ZM_DenNpcs:Resolve(self)
    net.Start("ZM.DenNpc.Open")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteBool(resolved.trader ~= nil)
        net.WriteBool(resolved.job ~= nil and #resolved.services > 0)
    net.Send(playerEntity)
end
