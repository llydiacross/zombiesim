AddCSLuaFile()
DEFINE_BASECLASS("weapon_zn_base_imported_melee")

// The Hammer is also the building tool: Reload toggles build mode (ZM_Construction). Its item level sets build
// speed and a mastercraft halves material costs, so both are networked for the client build HUD.
SWEP.Base = "weapon_zn_base_imported_melee"
SWEP.PrintName = "Hammer"
SWEP.Slot = 0
SWEP.ViewModel = "models/zombiesim/imported/hammer/weapons/v_knife_t.mdl"
SWEP.WorldModel = "models/zombiesim/imported/hammer/w_hammer.mdl"
SWEP.MeleeDamage = 32
SWEP.MeleeRange = 64
SWEP.MeleeDelay = 0.65
SWEP.MeleeForce = 5500

function SWEP:SetupDataTables()
    BaseClass.SetupDataTables(self)
    self:NetworkVar("Int", 0, "ItemLevel")
    self:NetworkVar("Bool", 0, "ItemMastercraft")
    self:NetworkVar("Bool", 1, "BuildMode")
    self:NetworkVar("String", 1, "BuildPiece")
end

function SWEP:OnItemInstanceApplied(instance)
    self:SetItemLevel(math.floor(tonumber(instance.level) or 0))
    self:SetItemMastercraft(instance.mastercraft == true)
end

function SWEP:Reload()
    local owner = self:GetOwner()
    if not SERVER or not IsValid(owner) or not owner:IsPlayer() or not owner:KeyPressed(IN_RELOAD) then return end
    if not self.GetBuildMode then return end
    ZM_Construction:ToggleBuildMode(owner, self)
end

function SWEP:PrimaryAttack()
    // In build mode the swing places a blueprint of the selected piece instead of attacking.
    if self.GetBuildMode and self:GetBuildMode() then
        self:SetNextPrimaryFire(CurTime() + 0.3)
        if SERVER then ZM_Construction:PrimaryBuild(self:GetOwner(), self) end
        return
    end
    BaseClass.PrimaryAttack(self)
end

function SWEP:SecondaryAttack()
    // In build mode, right-click only undoes an owned blueprint; finished pieces use Delete mode.
    if self.GetBuildMode and self:GetBuildMode() then
        self:SetNextSecondaryFire(CurTime() + 0.3)
        if SERVER then ZM_Construction:SecondaryBuild(self:GetOwner(), self) end
        return
    end
    BaseClass.SecondaryAttack(self)
end

function SWEP:Holster(...)
    if SERVER and self.GetBuildMode and self:GetBuildMode() then
        ZM_Construction:Clear(self:GetOwner())
        self:SetBuildMode(false)
    end
    return true
end
