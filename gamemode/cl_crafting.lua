ZM_Crafting = ZM_Crafting or {}
local Crafting = ZM_Crafting

surface.CreateFont("ZM_CraftingHeading", { font = "Trebuchet MS", size = 20, weight = 900, antialias = true })
surface.CreateFont("ZM_CraftingBody", { font = "Trebuchet MS", size = 15, weight = 600, antialias = true })

function Crafting:Open()
    if IsValid(self.Frame) then
        self.Frame:MakePopup()
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetSkin("ZombieSim")
    frame:SetTitle("CRAFTING STATION")
    frame:SetSize(math.min(520, ScrW() - 40), math.min(260, ScrH() - 40))
    frame:Center()
    frame:MakePopup()
    frame.OnRemove = function()
        if Crafting.Frame == frame then Crafting.Frame = nil end
    end
    self.Frame = frame
    if ZM_UI then ZM_UI:OpenExclusive(frame) end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(16, 16, 16, 16)
    body.Paint = function(_, width, height)
        draw.SimpleText("CRAFTING", "ZM_CraftingHeading", width * 0.5, 24, ZM_DermaSkin.Palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("No recipes are available yet.", "ZM_CraftingBody", width * 0.5, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("This station is restricted to den maps.", "ZM_CraftingBody", width * 0.5, height - 24, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end