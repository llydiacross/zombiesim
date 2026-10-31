include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local player = LocalPlayer()
    if not IsValid(player) or player:GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end
    local name = self:GetNWString("ZM_NpcName", "")
    if name == "" then return end
    cam.Start3D2D(self:GetPos() + Vector(0, 0, 80), Angle(0, player:EyeAngles().y - 90, 90), 0.08)
        draw.SimpleTextOutlined(name, "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
    cam.End3D2D()
end
