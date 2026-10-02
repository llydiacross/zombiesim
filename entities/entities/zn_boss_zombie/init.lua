AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:OnKilled(damage)
    if self.WalkerDead then return end
    self.WalkerDead = true
    local rewarded, reward = false, nil
    if ZM_Bosses then
        rewarded, reward = ZM_Bosses:OnBossKilled(self, damage:GetAttacker())
    end
    local corpse = self:CreateCorpse()
    if IsValid(corpse) then
        if reward and reward.item and ZM_LootSpots then
            ZM_LootSpots:RegisterRuntimeSpot(corpse, reward.item, "bosscorpse_" .. tostring(self.BossInstanceId))
        end
        if ZM_Gore then
            ZM_Gore:ApplyCorpse(self, corpse)
        end
    end
    self:Remove()
end

function ENT:OnRemove()
    if self.WalkerDead or not ZM_Bosses or not self.BossInstanceId then return end
    ZM_Bosses:Finish(self.BossInstanceId, self.BossProfile)
end