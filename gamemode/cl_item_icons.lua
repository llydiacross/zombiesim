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

// Clothing has no authored thumbnails or meaningful models, so icons are crops of the actual 1024x1024 garment layer.
local clothingCache = {}
local repeatingStyles = { ["repeat"] = true, checker = true, stripes = true }
local placementTags = { chest = "CHEST", chest_left = "L CHEST", chest_right = "R CHEST", front_full = "FRONT",
    back_full = "BACK", back_small = "BACK", arm_left = "L ARM", arm_right = "R ARM", pants_leg = "L THIGH",
    pants_leg_right = "R THIGH", pants_cuff = "L CUFF", pants_cuff_right = "R CUFF", pants_back_left = "L REAR",
    pants_back_right = "R REAR", arm_back_left = "L REAR ARM", arm_back_right = "R REAR ARM" }

local function resolveClothingIcon(finishId, garment, sex, label)
    local finish = ZM_Clothing and ZM_Clothing.Finishes[finishId]
    if not finish then
        return nil, "Missing clothing finish: " .. tostring(finishId)
    end
    local path = finish.layers and finish.layers[sex] or
        "models/zombiesim/clothing/prototype_" .. (garment == "shirt" and "shirt_" .. sex or "pants")
    local icon = finish.icon
    if icon and icon.layer then path = icon.layer end
    if not icon then
        local uv = garment == "shirt" and { 144, 764, 176, 224 } or { 784, 72, 88, 312 }
        if sex == "female" then uv[1] = garment == "shirt" and 163 or 812 end
        icon = { size = { uv[3], uv[4] }, [sex] = { { uv = uv, source = { 0, 0, uv[3], uv[4] } } } }
    end
    local material = Material(path)
    local texture = not material:IsError() and material:GetTexture("$basetexture")
    if not texture or texture:Width() ~= 1024 or texture:Height() ~= 1024 then
        return nil, "Missing wardrobe texture: " .. path
    end
    if type(icon.size) ~= "table" or type(icon[sex]) ~= "table" or
        not isnumber(icon.size[1]) or not isnumber(icon.size[2]) or
        not (icon.size[1] > 0 and icon.size[1] <= 1024 and icon.size[2] > 0 and icon.size[2] <= 1024) or
        #icon[sex] < 1 or #icon[sex] > 8 then
        return nil, "Invalid wardrobe icon canvas: " .. label
    end
    for _, piece in ipairs(icon[sex]) do
        if type(piece) ~= "table" or type(piece.uv) ~= "table" or type(piece.source) ~= "table" then
            return nil, "Invalid wardrobe icon piece: " .. label
        end
        for _, rectangle in ipairs({ piece.uv, piece.source }) do
            if type(rectangle) ~= "table" or #rectangle ~= 4 then return nil, "Invalid wardrobe icon piece: " .. label end
            for _, value in ipairs(rectangle) do
                if not isnumber(value) or value ~= value or value < 0 or value > 1024 then
                    return nil, "Invalid wardrobe icon coordinate: " .. label
                end
                if piece.uv[3] <= 0 or piece.uv[4] <= 0 or piece.source[3] <= 0 or piece.source[4] <= 0 or
                    piece.uv[1] + piece.uv[3] > 1024 or piece.uv[2] + piece.uv[4] > 1024 or
                    piece.source[1] + piece.source[3] > icon.size[1] or piece.source[2] + piece.source[4] > icon.size[2] then
                    return nil, "Wardrobe icon piece exceeds its canvas: " .. label
                end
            end
        end
    end
    return { material = material, icon = icon, pieces = icon[sex], finish = finish }
end

// Returns { material, icon, pieces, finish } or nil plus a failure message. Results, including failures, are cached.
function Icons:GetClothingIcon(finishId, garment, sex, label)
    sex = sex == "female" and "female" or "male"
    local key = tostring(finishId) .. "|" .. tostring(garment) .. "|" .. sex
    local cached = clothingCache[key]
    if not cached then
        local data, failure = resolveClothingIcon(finishId, garment, sex, label or tostring(finishId))
        cached = { data = data, failure = failure }
        clothingCache[key] = cached
    end
    return cached.data, cached.failure
end

// Draws the canvas window (wx, wy, ww, wh) into the destination rectangle, clipping each piece and its UVs.
local function drawCanvasWindow(data, wx, wy, ww, wh, x, y, width, height)
    local sx, sy = width / ww, height / wh
    surface.SetMaterial(data.material)
    for _, piece in ipairs(data.pieces) do
        local uv, source = piece.uv, piece.source
        local left, top = math.max(source[1], wx), math.max(source[2], wy)
        local right, bottom = math.min(source[1] + source[3], wx + ww), math.min(source[2] + source[4], wy + wh)
        if right > left and bottom > top then
            local ru, rv = uv[3] / source[3], uv[4] / source[4]
            local u0, v0 = uv[1] + (left - source[1]) * ru, uv[2] + (top - source[2]) * rv
            local u1, v1 = uv[1] + (right - source[1]) * ru, uv[2] + (bottom - source[2]) * rv
            surface.DrawTexturedRectUV(x + (left - wx) * sx, y + (top - wy) * sy,
                (right - left) * sx, (bottom - top) * sy, u0 / 1024, v0 / 1024, u1 / 1024, v1 / 1024)
        end
    end
end

local function drawGarmentGlyph(garment, x, y, size)
    local function rect(l, t, r, b)
        surface.DrawRect(x + math.floor(l * size), y + math.floor(t * size),
            math.max(1, math.floor((r - l) * size)), math.max(1, math.floor((b - t) * size)))
    end
    if garment == "pants" then
        rect(0.24, 0.14, 0.76, 0.3)
        rect(0.24, 0.3, 0.47, 0.88)
        rect(0.53, 0.3, 0.76, 0.88)
    else
        rect(0.1, 0.2, 0.9, 0.42)
        rect(0.3, 0.2, 0.7, 0.86)
    end
end

local function drawRepeatGlyph(x, y, size)
    local half = math.floor(size * 0.36)
    local left, top = x + math.floor(size * 0.14), y + math.floor(size * 0.14)
    surface.DrawRect(left, top, half, half)
    surface.DrawRect(left + half, top + half, half, half)
    surface.DrawOutlinedRect(left, top, half * 2, half * 2, 1)
end

// A fabric swatch plus garment/pattern badges. Placement prints show the whole crop over a dim fabric fill.
function Icons:DrawClothing(definition, x, y, size, sex)
    local clothing = definition and definition.clothing
    if not clothing then
        return false
    end
    local data = self:GetClothingIcon(clothing.finish, clothing.garment, sex, definition.thumbnail or clothing.finish)
    draw.RoundedBox(4, x, y, size, size, Color(14, 14, 16, 255))
    local pad = math.max(2, math.floor(size * 0.05))
    local inner = size - pad * 2
    local style = data and data.finish.style or ""
    if data then
        local cw, ch = data.icon.size[1], data.icon.size[2]
        local side = math.min(cw, ch)
        local placed = placementTags[style] ~= nil
        surface.SetDrawColor(255, 255, 255, placed and 70 or 255)
        drawCanvasWindow(data, (cw - side) / 2, (ch - side) / 2, side, side, x + pad, y + pad, inner, inner)
        if placed then
            local scale = inner / math.max(cw, ch)
            surface.SetDrawColor(255, 255, 255, 255)
            drawCanvasWindow(data, 0, 0, cw, ch, x + pad + (inner - cw * scale) / 2,
                y + pad + (inner - ch * scale) / 2, cw * scale, ch * scale)
        end
    else
        draw.SimpleText("?", "DermaDefaultBold", x + size / 2, y + size / 2, Color(200, 60, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawOutlinedRect(x + pad, y + pad, inner, inner, 1)

    local badge = math.max(10, math.floor(size * 0.26))
    local bx, by = x + size - pad - badge - 2, y + size - pad - badge - 2
    draw.RoundedBox(3, bx, by, badge, badge, Color(0, 0, 0, 210))
    surface.SetDrawColor(235, 235, 235, 255)
    drawGarmentGlyph(clothing.garment, bx, by, badge)
    if repeatingStyles[style] then
        local rx = bx - badge - 2
        draw.RoundedBox(3, rx, by, badge, badge, Color(0, 0, 0, 210))
        surface.SetDrawColor(235, 235, 235, 255)
        drawRepeatGlyph(rx, by, badge)
    end
    local tag = placementTags[style] or (style == "tie_dye" and "DYE" or nil)
    if tag and size >= 72 then
        surface.SetFont("DermaDefault")
        local tw, th = surface.GetTextSize(tag)
        draw.RoundedBox(3, x + pad + 2, by + badge - th - 2, tw + 6, th + 2, Color(0, 0, 0, 210))
        draw.SimpleText(tag, "DermaDefault", x + pad + 5, by + badge - th - 1, Color(235, 235, 235, 255))
    end
    return true
end

// Draws an authored override or a clothing swatch. Returns false when the item uses a model icon instead.
function Icons:DrawOverride(definition, x, y, size)
    if definition and definition.clothing then
        return self:DrawClothing(definition, x, y, size)
    end
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
    if not IsValid(parent) or not definition or definition.clothing or self:GetOverride(definition) then
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
