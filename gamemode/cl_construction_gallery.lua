// The gallery owns only its transient input and presentation; selection remains server-authoritative.
local Construction = ZM_Construction
local Gallery = { cards = {} }
Construction.Gallery = Gallery

local categories = { "Foundations", "Floors", "Walls", "Roofs", "Access" }
local spacing = 8
local cardHeight = 126

local function menuKey()
	local binding = input.LookupBinding("+menu")
	if not binding then return nil, "Bind +menu" end
	local code = input.GetKeyCode(binding)
	return code and code > 0 and code or nil, string.upper(binding)
end

function Gallery:BindingLabel()
	local _, label = menuKey()
	return label
end

function Gallery:IsOpen()
	return IsValid(self.Frame)
end

function Gallery:Close()
	if self:IsOpen() then self.Frame:Remove() end
end

local function layoutCards(grid, width)
	if width < 1 then return end
	local columns = math.max(1, math.floor((width + spacing) / 154))
	local cardWidth = math.max(1, math.floor((width - (columns - 1) * spacing) / columns))
	for _, card in ipairs(Gallery.cards) do
		card:SetWide(cardWidth)
		card.preview = Construction.Geometry.PreviewPolygons(card.kind, math.max(1, cardWidth - 24), 63)
		for _, polygon in ipairs(card.preview) do
			for _, point in ipairs(polygon.points) do
				point.x, point.y = point.x + 12, point.y + 20
			end
		end
	end
end

local function paintCard(card, width, height)
	local palette = ZM_DermaSkin.Palette
	local player = LocalPlayer()
	local weapon = IsValid(player) and player:GetActiveWeapon() or nil
	local active = IsValid(weapon) and card.kind == Construction.SelectedPiece(weapon)
	surface.SetDrawColor(card:IsHovered() and palette.raised or palette.panel)
	surface.DrawRect(0, 0, width, height)
	surface.SetDrawColor(active and palette.redBright or palette.border)
	surface.DrawOutlinedRect(0, 0, width, height, 1)
	draw.SimpleText(card.category, "DermaDefault", 8, 6, palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.NoTexture()
	for _, polygon in ipairs(card.preview or {}) do
		local shade = polygon.shade
		surface.SetDrawColor(157 * shade, 128 * shade, 94 * shade, 255)
		surface.DrawPoly(polygon.points)
		surface.SetDrawColor(45, 37, 29, 255)
		for index, point in ipairs(polygon.points) do
			local nextPoint = polygon.points[index % #polygon.points + 1]
			surface.DrawLine(point.x, point.y, nextPoint.x, nextPoint.y)
		end
	end
	draw.SimpleText(card.name, "DermaDefaultBold", width * 0.5, height - 31, palette.text,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	draw.SimpleText(card.cost, "DermaDefault", width * 0.5, height - 15, palette.muted,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

function Gallery:Select(kind)
	if not self:IsOpen() or not Construction:LocalBuildMode() or Construction:LocalDeleteMode()
		or not Construction.Pieces[kind] then return false end
	net.Start("ZM.Construction.SelectPiece")
	net.WriteString(kind)
	net.SendToServer()
	self:Close()
	return true
end

function Gallery:Open()
	local player = LocalPlayer()
	if not Construction:LocalBuildMode() or Construction:LocalDeleteMode()
		or not IsValid(player) or not player:Alive() then return false end
	if self:IsOpen() then return true end
	if gui.IsGameUIVisible() or vgui.CursorVisible() or IsValid(vgui.GetKeyboardFocus())
		or ZM_LauncherMenu and ZM_LauncherMenu.Active then return false end

	local frame = vgui.Create("DFrame")
	frame:SetSkin("ZombieSim")
	frame:SetTitle("Build pieces")
	frame:SetSize(math.min(850, ScrW() - 40), math.min(660, ScrH() - 40))
	frame:Center()
	frame:MakePopup()
	self.Frame = frame
	self.cards = {}
	self.keyWasDown = true
	if ZM_UI then ZM_UI:OpenExclusive(frame) end
	frame.OnRemove = function()
		if Gallery.Frame == frame then Gallery.Frame = nil end
		Gallery.releaseMouse = true
		if ZM_UI then ZM_UI:UnregisterTransient(frame) end
	end

	local info = vgui.Create("DPanel", frame)
	info:Dock(TOP)
	info:DockMargin(12, 4, 12, 4)
	info:SetTall(28)
	info.Paint = function(_, width, height)
		local _, label = menuKey()
		draw.SimpleText("Choose a piece; the gallery closes when selected. " .. label .. " / Esc closes.",
			"DermaDefault", 0, height * 0.5, ZM_DermaSkin.Palette.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(12, 0, 12, 12)
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(spacing)
	grid:SetSpaceY(spacing)
	grid.Paint = function() end
	grid.OnSizeChanged = layoutCards

	local weapon = player:GetActiveWeapon()
	local mastercraft = weapon.GetItemMastercraft and weapon:GetItemMastercraft() or false
	for _, category in ipairs(categories) do
		for _, kind in ipairs(Construction.PieceOrder) do
			local piece = Construction.Pieces[kind]
			if piece.category == category then
				local card = grid:Add("DButton")
				card.kind, card.category, card.name = kind, category, piece.name
				card.cost = Construction:CostText(kind, mastercraft)
				card:SetSize(150, cardHeight)
				card:SetText("")
				card:SetTooltip(piece.name .. " | " .. card.cost)
				card.Paint = paintCard
				card.DoClick = function() Gallery:Select(kind) end
				self.cards[#self.cards + 1] = card
			end
		end
	end
	layoutCards(grid, math.max(1, frame:GetWide() - 48))
	return true
end

hook.Add("PlayerBindPress", "ZM.Construction.GalleryBind", function(_, bind, pressed)
	if not pressed or string.lower(bind or "") ~= "+menu" then return end
	if Construction:LocalDeleteMode() then return true end
	if Gallery:IsOpen() then
		Gallery:Close()
		return true
	end
	if Gallery:Open() then return true end
end)

hook.Add("Think", "ZM.Construction.GalleryLifecycle", function()
	if not Gallery:IsOpen() then return end
	local player = LocalPlayer()
	if not IsValid(player) or not player:Alive() or not Construction:LocalBuildMode() or Construction:LocalDeleteMode()
		or gui.IsGameUIVisible() or ZM_LauncherMenu and ZM_LauncherMenu.Active then
		Gallery:Close()
		return
	end
	local code = menuKey()
	local down = code and input.IsButtonDown(code) or false
	if down and not Gallery.keyWasDown then
		Gallery:Close()
	else
		Gallery.keyWasDown = down
	end
end)

hook.Add("OnPauseMenuShow", "ZM.Construction.GalleryEscape", function()
	if not Gallery:IsOpen() then return end
	Gallery:Close()
	return false
end)

hook.Add("CreateMove", "ZM.Construction.GalleryInput", function(command)
	if not Gallery:IsOpen() and not Gallery.releaseMouse then return end
	command:RemoveKey(IN_ATTACK)
	command:RemoveKey(IN_ATTACK2)
	command:RemoveKey(IN_USE)
	if not Gallery:IsOpen() and not input.IsMouseDown(MOUSE_LEFT) and not input.IsMouseDown(MOUSE_RIGHT) then
		Gallery.releaseMouse = false
	end
end)
