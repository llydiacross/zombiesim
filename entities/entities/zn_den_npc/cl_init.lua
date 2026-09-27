include("shared.lua")

local roleColor = Color(222, 184, 84)

function ENT:Draw()
    self:DrawModel()
    if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end
    local name = self:GetNWString("ZM_NpcName", "Den Resident")
    local job = self:GetNWString("ZM_NpcJob", "")
    local trader = self:GetNWString("ZM_NpcTrader", "")
    local role = job ~= "" and (job .. " lvl " .. self:GetNWInt("ZM_NpcLevel", 1)) or ""
    if trader ~= "" then role = role ~= "" and (role .. "  |  Trader") or "Trader" end
    cam.Start3D2D(self:GetPos() + Vector(0, 0, 80), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), 0.08)
        draw.SimpleTextOutlined(name, "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, color_black)
        if role ~= "" then
            draw.SimpleTextOutlined(role, "DermaDefaultBold", 0, 6, roleColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
        end
    cam.End3D2D()
end
