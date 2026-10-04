include("shared.lua")

function ENT:Draw()
    self:DrawModel()
    local playerEntity = LocalPlayer()
    if not IsValid(playerEntity) or playerEntity:GetPos():DistToSqr(self:GetPos()) > 500 * 500 then return end

    local name = self:GetNWString("ZM_DropItemName", "Item")
    local count = self:GetNWInt("ZM_DropItemCount", 0)
    cam.Start3D2D(self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 6), Angle(0, playerEntity:EyeAngles().y - 90, 90), 0.08)
        draw.SimpleTextOutlined(name .. " x" .. count, "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
    cam.End3D2D()
end
