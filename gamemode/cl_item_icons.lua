// Client item icons: an optional authored PNG override, otherwise the item's mounted model rendered as a spawn icon.
ZM_ItemIcons = ZM_ItemIcons or {}
local Icons = ZM_ItemIcons

local overrideCache = {}

function Icons:GetOverride(definition)
    local name = definition and definition.thumbnail
    if not name then
        return nil
    end
    if overrideCache[name] == nil then
        overrideCache[name] = file.Exists("materials/items/" .. name .. ".png", "GAME") and Material("items/" .. name .. ".png", "smooth") or false
    end
    return overrideCache[name] or nil
end

function Icons:GetModel(definition)
    return definition and definition.iconModel or ZM_StaticData.DefaultItemIconModel
end

// Draws an authored override. Returns false when the item uses a model icon instead.
function Icons:DrawOverride(definition, x, y, size)
    local material = self:GetOverride(definition)
    if not material then
        return false
    end
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(material)
    surface.DrawTexturedRect(x, y, size, size)
    return true
end

// Adds a non-interactive spawn icon, kept square and centred, so the parent keeps clicks, drag/drop, and tooltips.
// Overlays drawn in the parent's Paint sit underneath the icon; draw them in PaintOver instead.
function Icons:Attach(parent, definition, inset)
    if not IsValid(parent) or not definition or self:GetOverride(definition) then
        return nil
    end
    local image = vgui.Create("ModelImage", parent)
    image:SetMouseInputEnabled(false)
    image:SetKeyboardInputEnabled(false)
    image:SetModel(self:GetModel(definition))
    inset = inset or 0

    local basePerformLayout = parent.PerformLayout
    parent.PerformLayout = function(panel, width, height)
        if basePerformLayout then
            basePerformLayout(panel, width, height)
        end
        local size = math.max(0, math.min(width, height) - inset * 2)
        image:SetSize(size, size)
        image:SetPos(math.floor((width - size) * 0.5), math.floor((height - size) * 0.5))
    end
    parent:InvalidateLayout()
    return image
end
