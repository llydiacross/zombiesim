ZM_DermaSkin = ZM_DermaSkin or {}

local palette = {
    black = Color(7, 8, 10),
    panel = Color(15, 17, 20),
    raised = Color(26, 29, 33),
    border = Color(85, 22, 29),
    red = Color(173, 28, 43),
    redBright = Color(239, 57, 72),
    redDark = Color(82, 14, 23),
    text = Color(232, 232, 234),
    muted = Color(158, 165, 171)
}

ZM_DermaSkin.Palette = palette

surface.CreateFont("ZM_DermaFrameTitle", {
    font = "Trebuchet MS",
    size = 18,
    weight = 900,
    antialias = true
})

surface.CreateFont("ZM_DermaButton", {
    font = "Trebuchet MS",
    size = 14,
    weight = 700,
    antialias = true
})

local skin = {}
skin.PrintName = "ZombieSim"
skin.Author = "ZombieSim"
skin.DermaVersion = 1
skin.Base = "Default"
skin.fontFrame = "ZM_DermaFrameTitle"
skin.fontButton = "ZM_DermaButton"
skin.Colours = table.Copy(derma.SkinList.Default.Colours)
skin.Colours.Window.TitleActive = palette.text
skin.Colours.Window.TitleInactive = palette.muted
skin.Colours.Label.Default = palette.text
skin.Colours.Label.Bright = palette.redBright
skin.Colours.Label.Dark = palette.muted
skin.Colours.Button.Normal = palette.text
skin.Colours.Button.Hover = palette.text
skin.Colours.Button.Down = palette.text
skin.Colours.Button.Disabled = Color(103, 107, 111)
skin.Colours.TextEntry = skin.Colours.TextEntry or {}
skin.Colours.TextEntry.Text = palette.text
skin.Colours.TextEntry.Highlight = palette.redBright

local function drawBevel(width, height, accent)
    surface.SetDrawColor(palette.border)
    surface.DrawOutlinedRect(0, 0, width, height, 1)
    surface.SetDrawColor(accent and palette.redBright or Color(49, 54, 59))
    surface.DrawLine(1, 1, width - 2, 1)
    surface.SetDrawColor(0, 0, 0, 210)
    surface.DrawLine(1, height - 2, width - 2, height - 2)
end

function skin:PaintFrame(panel, width, height)
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(palette.redDark)
    surface.DrawRect(1, 1, width - 2, 25)
    surface.SetDrawColor(palette.red)
    surface.DrawRect(1, 25, width - 2, 2)
    drawBevel(width, height, true)
end

function skin:PaintButton(panel, width, height)
    local isDisabled = panel:GetDisabled()
    local isActive = panel:IsDown()
    local isHovered = panel.Hovered
    local fill = isDisabled and Color(28, 30, 32) or isActive and palette.redDark or isHovered and Color(67, 19, 26) or palette.raised

    surface.SetDrawColor(fill)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, isHovered or isActive)
    if not isDisabled and (isHovered or isActive) then
        surface.SetDrawColor(palette.red)
        surface.DrawRect(2, height - 4, math.max(0, width - 4), 2)
    end
end

function skin:PaintCheckBox(panel, width, height)
    local isChecked = panel:GetChecked()
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, panel.Hovered or isChecked)
    if isChecked then
        surface.SetDrawColor(palette.redBright)
        surface.DrawRect(3, 3, math.max(0, width - 6), math.max(0, height - 6))
        surface.SetDrawColor(255, 236, 238, 255)
        surface.DrawLine(4, height * 0.5, width * 0.45, height - 4)
        surface.DrawLine(width * 0.45, height - 4, width - 4, 4)
    end
end

function skin:PaintVScrollBar(_, width, height)
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(palette.border)
    surface.DrawOutlinedRect(0, 0, width, height, 1)
end

function skin:PaintVScrollBarGrip(panel, width, height)
    surface.SetDrawColor(panel.Hovered and palette.red or palette.raised)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, panel.Hovered)
end

function skin:PaintHScrollBar(_, width, height)
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(palette.border)
    surface.DrawOutlinedRect(0, 0, width, height, 1)
end

function skin:PaintHScrollBarGrip(panel, width, height)
    surface.SetDrawColor(panel.Hovered and palette.red or palette.raised)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, panel.Hovered)
end

function skin:PaintTextEntry(panel, width, height)
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, panel:HasFocus())
    panel:DrawTextEntryText(palette.text, palette.redBright, palette.text)
end

function skin:PaintTooltip(_, width, height)
    surface.SetDrawColor(palette.black)
    surface.DrawRect(0, 0, width, height)
    drawBevel(width, height, true)
end

function skin:PaintWindowCloseButton(panel, width, height)
    surface.SetDrawColor(panel.Hovered and palette.redBright or palette.red)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(255, 235, 238, 255)
    surface.DrawLine(5, 5, width - 5, height - 5)
    surface.DrawLine(width - 5, 5, 5, height - 5)
end

derma.DefineSkin("ZombieSim", "ZombieSim black and red interface", skin)
