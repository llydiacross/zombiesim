// Client land claims: caches the server's claim snapshot, runs claim mode (entered by using a claim token: the core
// tile under the cursor is highlighted and a left click asks the server to claim it) and draws claimed tiles as
// bordered boxes on the HUD minimap and the world map. The server re-validates every claim request.
ZM_Claims = ZM_Claims or {}
local Claims = ZM_Claims

Claims.Snapshot = Claims.Snapshot or { cellId = 0, tileSize = 640, claimable = {}, claims = {}, owned = {} }
Claims.Active = Claims.Active or false
Claims.Draws = 0
Claims.MapDraws = 0
Claims.Paths = Claims.Paths or {}

Claims.Colours = {
	mine = Color( 90, 220, 120 ),
	lapsed = Color( 150, 150, 150 ),
	friend = Color( 90, 200, 255 ),
	other = Color( 235, 70, 60 ),
	free = Color( 245, 214, 80 ),
	far = Color( 240, 140, 40 ),
	idle = Color( 220, 220, 220 )
}

// --- Pure helpers (also exercised by offline fixtures) -------------------------------------------------------------

// Clips a screen polygon ({ {x, y}, ... }) to an axis-aligned rectangle (Sutherland-Hodgman).
function Claims.ClipPolygon( polygon, x, y, width, height )
	for _, edge in ipairs( { { "x", x, 1 }, { "x", x + width, -1 }, { "y", y, 1 }, { "y", y + height, -1 } } ) do
		local clipped = {}
		if #polygon > 0 then
			local previous = polygon[#polygon]
			local previousDistance = ( previous[edge[1]] - edge[2] ) * edge[3]
			for _, point in ipairs( polygon ) do
				local distance = ( point[edge[1]] - edge[2] ) * edge[3]
				if ( distance >= 0 ) ~= ( previousDistance >= 0 ) then
					local t = previousDistance / ( previousDistance - distance )
					clipped[#clipped + 1] = { x = previous.x + ( point.x - previous.x ) * t,
						y = previous.y + ( point.y - previous.y ) * t }
				end
				if distance >= 0 then clipped[#clipped + 1] = point end
				previous, previousDistance = point, distance
			end
		end
		polygon = clipped
	end
	return polygon
end

// surface.DrawPoly expects clockwise screen-space vertices (y down); reverses anticlockwise input in place.
function Claims.Clockwise( polygon )
	local area = 0
	for index = 1, #polygon do
		local a, b = polygon[index], polygon[index % #polygon + 1]
		area = area + a.x * b.y - b.x * a.y
	end
	if area < 0 then
		for index = 1, math.floor( #polygon / 2 ) do
			polygon[index], polygon[#polygon - index + 1] = polygon[#polygon - index + 1], polygon[index]
		end
	end
	return polygon
end

// The four cell-local world corners of a centred core tile (east +X, north +Y).
function Claims.TileCorners( tileX, tileY, tileSize )
	local half = tileSize * 0.5
	local cx, cy = tileX * tileSize, tileY * tileSize
	return {
		{ x = cx - half, y = cy + half }, { x = cx + half, y = cy + half },
		{ x = cx + half, y = cy - half }, { x = cx - half, y = cy - half }
	}
end

// Screen rectangle of a tile inside a world-map cell square whose imagery spans one neighbour pitch.
function Claims.GridTileRect( cellLeft, cellTop, cellWidth, cellHeight, tileX, tileY, tileSize, pitch )
	local half = tileSize * 0.5
	local left = cellLeft + ( 0.5 + ( tileX * tileSize - half ) / pitch ) * cellWidth
	local right = cellLeft + ( 0.5 + ( tileX * tileSize + half ) / pitch ) * cellWidth
	local top = cellTop + ( 0.5 - ( tileY * tileSize + half ) / pitch ) * cellHeight
	local bottom = cellTop + ( 0.5 - ( tileY * tileSize - half ) / pitch ) * cellHeight
	return left, top, right - left, bottom - top
end

// Client mirror of the server reach rule: the player must be within 1.5 tiles (per axis) of the tile centre.
function Claims.WithinReach( position, tileX, tileY, tileSize )
	local reach = tileSize * 1.5
	return math.abs( position.x - tileX * tileSize ) <= reach and math.abs( position.y - tileY * tileSize ) <= reach
end

// Presentation state of a tile in the current cell: "mine", "lapsed", "friend", "other", "free" or nil (unclaimable).
function Claims.TileState( snapshot, tileX, tileY )
	for _, claim in ipairs( snapshot.claims ) do
		if claim.tileX == tileX and claim.tileY == tileY then
			if claim.active then
				if claim.mine then return "mine" end
				return claim.access and "friend" or "other"
			end
			if claim.mine then return "lapsed" end
		end
	end
	for _, tile in ipairs( snapshot.claimable ) do
		if tile.x == tileX and tile.y == tileY then return "free" end
	end
	return nil
end

// --- Snapshot -------------------------------------------------------------------------------------------------------

net.Receive( "ZM.Claims.Snapshot", function()
	local snapshot = { claimable = {}, claims = {}, owned = {} }
	snapshot.cellId = net.ReadUInt( 32 )
	snapshot.tileSize = net.ReadUInt( 16 )
	for _ = 1, net.ReadUInt( 5 ) do
		snapshot.claimable[#snapshot.claimable + 1] = { x = net.ReadInt( 4 ), y = net.ReadInt( 4 ) }
	end
	for _ = 1, net.ReadUInt( 5 ) do
		snapshot.claims[#snapshot.claims + 1] = { tileX = net.ReadInt( 4 ), tileY = net.ReadInt( 4 ),
			active = net.ReadBool(), mine = net.ReadBool(), access = net.ReadBool() }
	end
	for _ = 1, net.ReadUInt( 10 ) do
		snapshot.owned[#snapshot.owned + 1] = { cellId = net.ReadUInt( 32 ), tileX = net.ReadInt( 4 ),
			tileY = net.ReadInt( 4 ), active = net.ReadBool() }
	end
	Claims.Snapshot = snapshot
	Claims.Paths = {}
	Claims.ReceivedAt = CurTime()
end )

net.Receive( "ZM.Claims.Result", function()
	local ok, message = net.ReadBool(), net.ReadString()
	Claims.Result = { ok = ok, text = message, at = CurTime() }
	Claims.Pending = nil
	if ok then
		Claims:Exit()
		surface.PlaySound( "buttons/button9.wav" )
	else
		surface.PlaySound( "buttons/button10.wav" )
	end
end )

function Claims:RequestSnapshot()
	net.Start( "ZM.Claims.Request" )
	net.WriteUInt( 0, 2 )
	net.SendToServer()
end

hook.Add( "InitPostEntity", "ZM.Claims.InitialSnapshot", function()
	timer.Simple( 2, function() Claims:RequestSnapshot() end )
end )

// --- Claim mode -----------------------------------------------------------------------------------------------------

local function inSafeZone( client )
	return client:GetNWString( "CurrentSafeZoneId", "" ) ~= ""
end

function Claims:Enter()
	local client = LocalPlayer()
	if not IsValid( client ) or not client:Alive() then return false end
	if inSafeZone( client ) then
		self.Result = { ok = false, text = "Land can only be claimed in city cells.", at = CurTime() }
		return false
	end
	self.Active = true
	self.Hovered = nil
	self.Pending = nil
	self.Result = nil
	self:RequestSnapshot()
	return true
end

function Claims:Exit()
	self.Active = false
	self.Hovered = nil
	self.Pending = nil
end

function Claims:IsActive()
	return self.Active == true
end

function Claims:Submit()
	local hovered = self.Hovered
	if not hovered then
		self.Result = { ok = false, text = "Point at a core tile of this cell.", at = CurTime() }
		return
	end
	if hovered.state ~= "free" then
		self.Result = { ok = false, text = hovered.state == "mine" and "You already own that tile."
			or "That tile cannot be claimed.", at = CurTime() }
		return
	end
	if not hovered.inReach then
		self.Result = { ok = false, text = "Move closer to the tile to claim it.", at = CurTime() }
		return
	end
	if self.Pending and CurTime() - self.Pending < 2 then return end
	self.Pending = CurTime()
	net.Start( "ZM.Claims.Request" )
	net.WriteUInt( 1, 2 )
	net.WriteInt( hovered.tileX, 4 )
	net.WriteInt( hovered.tileY, 4 )
	net.SendToServer()
end

concommand.Add( "zombiesim_claim_mode", function()
	if Claims:IsActive() then Claims:Exit() else Claims:Enter() end
end )

hook.Add( "PlayerBindPress", "ZM.Claims.Input", function( _, bind, pressed )
	if not Claims:IsActive() then return end
	local command = string.lower( bind or "" )
	if command == "+attack" then
		if pressed then Claims:Submit() end
		return true
	end
	if command == "+attack2" then
		if pressed then Claims:Exit() end
		return true
	end
end )

hook.Add( "CreateMove", "ZM.Claims.BlockAttack", function( cmd )
	if not Claims:IsActive() then return end
	cmd:RemoveKey( IN_ATTACK )
	cmd:RemoveKey( IN_ATTACK2 )
end )

hook.Add( "OnPauseMenuShow", "ZM.Claims.EscapeExits", function()
	if not Claims:IsActive() then return end
	Claims:Exit()
	return false
end )

hook.Add( "Think", "ZM.Claims.AutoExit", function()
	if not Claims:IsActive() then return end
	local client = LocalPlayer()
	if not IsValid( client ) or not client:Alive() or inSafeZone( client ) then Claims:Exit() end
end )

// --- World highlight ------------------------------------------------------------------------------------------------

local beamMaterial = Material( "effects/laser1" )
local sampleSpacing = 128
local groundLift = 8
local inset = 12
local scratchColour = Color( 255, 255, 255, 255 )

// Ground-following outline of one tile, inset so neighbouring outlines stay distinct; cached per snapshot.
local function tilePath( tileX, tileY, tileSize, referenceZ )
	local key = tileX .. "," .. tileY
	local cached = Claims.Paths[key]
	if cached then return cached end
	local half = tileSize * 0.5 - inset
	local cx, cy = tileX * tileSize, tileY * tileSize
	local corners = { { cx - half, cy + half }, { cx + half, cy + half }, { cx + half, cy - half }, { cx - half, cy - half } }
	local points = {}
	for index = 1, 4 do
		local a, b = corners[index], corners[index % 4 + 1]
		local steps = math.max( 1, math.ceil( ( tileSize - inset * 2 ) / sampleSpacing ) )
		for step = 0, steps - 1 do
			local fraction = step / steps
			local x, y = a[1] + ( b[1] - a[1] ) * fraction, a[2] + ( b[2] - a[2] ) * fraction
			local trace = util.TraceLine( {
				start = Vector( x, y, referenceZ + 1024 ),
				endpos = Vector( x, y, referenceZ - 4096 ),
				mask = MASK_SOLID_BRUSHONLY
			} )
			local z = trace.Hit and not trace.StartSolid and trace.HitPos.z or referenceZ
			points[#points + 1] = Vector( x, y, z + groundLift )
		end
	end
	points[#points + 1] = points[1]
	Claims.Paths[key] = points
	return points
end

local function drawTile( tileX, tileY, tileSize, referenceZ, colour, width )
	local points = tilePath( tileX, tileY, tileSize, referenceZ )
	for index = 2, #points do
		render.DrawBeam( points[index - 1], points[index], width, 0, 1, colour )
		Claims.Draws = Claims.Draws + 1
	end
end

local function updateHover( client, tileSize )
	local screenX, screenY
	if ZM_GetAimCursor then screenX, screenY = ZM_GetAimCursor() end
	if not screenX then screenX, screenY = ScrW() * 0.5, ScrH() * 0.5 end
	local origin = EyePos()
	local trace = util.TraceLine( {
		start = origin,
		endpos = origin + gui.ScreenToVector( screenX, screenY ) * 32768,
		mask = MASK_SOLID,
		filter = client
	} )
	Claims.Hovered = nil
	if not trace.Hit or trace.HitSky or not ZM_World or not ZM_World.GetCoreTileAt then return end
	local tileX, tileY = ZM_World:GetCoreTileAt( trace.HitPos )
	if not tileX then return end
	Claims.Hovered = {
		tileX = tileX, tileY = tileY,
		state = Claims.TileState( Claims.Snapshot, tileX, tileY ) or "none",
		inReach = Claims.WithinReach( client:GetPos(), tileX, tileY, tileSize )
	}
end

hook.Add( "PostDrawTranslucentRenderables", "ZM.Claims.WorldHighlight", function( depth, skybox )
	if depth or skybox then return end
	Claims.Draws = 0
	if not Claims:IsActive() then return end
	local client = LocalPlayer()
	if not IsValid( client ) then return end
	local snapshot = Claims.Snapshot
	local tileSize = snapshot.tileSize > 0 and snapshot.tileSize or 640
	updateHover( client, tileSize )
	local referenceZ = client:GetPos().z
	render.SetMaterial( beamMaterial )
	local pulse = 150 + 100 * math.abs( math.sin( CurTime() * 3 ) )
	for _, tile in ipairs( snapshot.claimable ) do
		local state = Claims.TileState( snapshot, tile.x, tile.y )
		local base = Claims.Colours[state == "free" and "idle" or state] or Claims.Colours.idle
		scratchColour.r, scratchColour.g, scratchColour.b = base.r, base.g, base.b
		scratchColour.a = state == "free" and 70 or 160
		drawTile( tile.x, tile.y, tileSize, referenceZ, scratchColour, 4 )
	end
	local hovered = Claims.Hovered
	if hovered and hovered.state ~= "none" then
		local key = hovered.state == "free" and ( hovered.inReach and "free" or "far" ) or hovered.state
		local base = Claims.Colours[key] or Claims.Colours.idle
		scratchColour.r, scratchColour.g, scratchColour.b, scratchColour.a = base.r, base.g, base.b, pulse
		drawTile( hovered.tileX, hovered.tileY, tileSize, referenceZ, scratchColour, 10 )
	end
end )

// --- HUD hint -------------------------------------------------------------------------------------------------------

local function hoverDescription( hovered )
	if not hovered or hovered.state == "none" then return "Point at a core tile of this cell", Claims.Colours.idle end
	if hovered.state == "free" then
		if hovered.inReach then return "Free tile - click to claim", Claims.Colours.free end
		return "Too far - move closer to claim", Claims.Colours.far
	end
	if hovered.state == "mine" then return "Your claim", Claims.Colours.mine end
	if hovered.state == "lapsed" then return "Your lapsed claim", Claims.Colours.lapsed end
	if hovered.state == "friend" then return "Claimed by a friend", Claims.Colours.friend end
	return "Claimed by another survivor", Claims.Colours.other
end

// Sits under the top-centre compass so it never covers the minimap, status panels or build label.
hook.Add( "HUDPaint", "ZM.Claims.Hint", function()
	local result = Claims.Result
	local showResult = result and CurTime() - result.at < 4
	if not Claims:IsActive() and not showResult then return end
	local scale = GetConVar( "zombiesim_compass_height" )
	local compassHeight = math.floor( 94 * math.Clamp( scale and scale:GetFloat() or 0.55, 0.55, 1.5 ) )
	local width = math.min( 380, ScrW() - 40 )
	local height = Claims:IsActive() and 74 or 30
	local x, y = math.floor( ( ScrW() - width ) * 0.5 ), 18 + compassHeight + 12
	draw.RoundedBox( 5, x, y, width, height, Color( 10, 14, 18, 220 ) )
	surface.SetDrawColor( 245, 214, 80, 190 )
	surface.DrawOutlinedRect( x, y, width, height, 1 )
	local centre = x + width * 0.5
	if Claims:IsActive() then
		draw.SimpleText( "CLAIM MODE", "DermaDefaultBold", centre, y + 8, Claims.Colours.free, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		local text, colour = hoverDescription( Claims.Hovered )
		if Claims.Snapshot.cellId == 0 or #Claims.Snapshot.claimable == 0 then
			text, colour = "No claimable land in this cell", Claims.Colours.other
		end
		draw.SimpleText( text, "DermaDefaultBold", centre, y + 28, colour, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		draw.SimpleText( "LMB claim  |  RMB / Esc cancel", "DermaDefault", centre, y + 50,
			Color( 210, 210, 210 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		if showResult and not result.ok then
			draw.SimpleText( result.text, "DermaDefault", centre, y + height + 6, Claims.Colours.other,
				TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		end
		return
	end
	draw.SimpleText( result.text, "DermaDefaultBold", centre, y + height * 0.5,
		result.ok and Claims.Colours.mine or Claims.Colours.other, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
end )

// --- Map overlays ---------------------------------------------------------------------------------------------------

local function stateColour( state )
	return Claims.Colours[state] or Claims.Colours.other
end

// Draws one bordered box from four screen points, clipped to the map rectangle.
local function drawBox( points, colour, clipX, clipY, clipW, clipH, thickness )
	draw.NoTexture()
	local fill = Claims.ClipPolygon( Claims.Clockwise( {
		{ x = points[1].x, y = points[1].y }, { x = points[2].x, y = points[2].y },
		{ x = points[3].x, y = points[3].y }, { x = points[4].x, y = points[4].y } } ), clipX, clipY, clipW, clipH )
	local drawn = false
	if #fill >= 3 then
		surface.SetDrawColor( colour.r, colour.g, colour.b, 55 )
		surface.DrawPoly( fill )
		drawn = true
	end
	local cx = ( points[1].x + points[2].x + points[3].x + points[4].x ) * 0.25
	local cy = ( points[1].y + points[2].y + points[3].y + points[4].y ) * 0.25
	local inner = {}
	for index = 1, 4 do
		local dx, dy = cx - points[index].x, cy - points[index].y
		local length = math.sqrt( dx * dx + dy * dy )
		local step = length > 0 and math.min( thickness * 1.414, length ) / length or 0
		inner[index] = { x = points[index].x + dx * step, y = points[index].y + dy * step }
	end
	surface.SetDrawColor( colour.r, colour.g, colour.b, 235 )
	for index = 1, 4 do
		local nextIndex = index % 4 + 1
		local edge = Claims.ClipPolygon( Claims.Clockwise( {
			{ x = points[index].x, y = points[index].y }, { x = points[nextIndex].x, y = points[nextIndex].y },
			{ x = inner[nextIndex].x, y = inner[nextIndex].y }, { x = inner[index].x, y = inner[index].y } } ),
			clipX, clipY, clipW, clipH )
		if #edge >= 3 then surface.DrawPoly( edge ) drawn = true end
	end
	if drawn then Claims.MapDraws = Claims.MapDraws + 1 end
end

// Current-cell claims on a local map view. project(Vector-like) returns screen x, y.
function Claims:DrawLocal( project, clipX, clipY, clipW, clipH )
	self.MapDraws = 0
	local snapshot = self.Snapshot
	if snapshot.cellId == 0 or clipW <= 0 or clipH <= 0 then return end
	local tileSize = snapshot.tileSize > 0 and snapshot.tileSize or 640
	for _, claim in ipairs( snapshot.claims ) do
		local state = self.TileState( snapshot, claim.tileX, claim.tileY )
		if state and state ~= "free" then
			local points = {}
			for index, corner in ipairs( self.TileCorners( claim.tileX, claim.tileY, tileSize ) ) do
				local x, y = project( Vector( corner.x, corner.y, 0 ) )
				points[index] = { x = x, y = y }
			end
			drawBox( points, stateColour( state ), clipX, clipY, clipW, clipH, 2 )
		end
	end
end

// Claims on the world-grid views (atlas, satellite, walker, wireframe). gridCoordinates(cell) returns gridX, gridY.
function Claims:DrawWorldGrid( mapX, mapY, cellWidth, cellHeight, gridCoordinates, clipX, clipY, clipW, clipH )
	self.MapDraws = 0
	local snapshot = self.Snapshot
	if not ZM_World or not ZM_World.GetCellById then return end
	local bounds = ZM_World:GetCellBounds()
	local tileSize = snapshot.tileSize > 0 and snapshot.tileSize or tonumber( bounds.tileSize ) or 640
	local pitch = tonumber( bounds.neighbourPitch ) or 5760
	local function boxFor( cellId, tileX, tileY, state )
		local cell = ZM_World:GetCellById( cellId )
		if not cell then return end
		local gridX, gridY = gridCoordinates( cell )
		if not gridX or not gridY then return end
		local left, top, width, height = self.GridTileRect( mapX + gridX * cellWidth, mapY + gridY * cellHeight,
			cellWidth, cellHeight, tileX, tileY, tileSize, pitch )
		// Keep tiny boxes visible when the map is zoomed out.
		local minimum = 5
		if width < minimum then left, width = left + ( width - minimum ) * 0.5, minimum end
		if height < minimum then top, height = top + ( height - minimum ) * 0.5, minimum end
		drawBox( { { x = left, y = top }, { x = left + width, y = top },
			{ x = left + width, y = top + height }, { x = left, y = top + height } },
			stateColour( state ), clipX, clipY, clipW, clipH, math.Clamp( width / 8, 1, 2 ) )
	end
	local drawnMine = {}
	for _, claim in ipairs( snapshot.owned ) do
		drawnMine[claim.cellId .. ":" .. claim.tileX .. "," .. claim.tileY] = true
		boxFor( claim.cellId, claim.tileX, claim.tileY, claim.active and "mine" or "lapsed" )
	end
	if snapshot.cellId ~= 0 then
		for _, claim in ipairs( snapshot.claims ) do
			local state = self.TileState( snapshot, claim.tileX, claim.tileY )
			if state and state ~= "free" and not drawnMine[snapshot.cellId .. ":" .. claim.tileX .. "," .. claim.tileY] then
				boxFor( snapshot.cellId, claim.tileX, claim.tileY, state )
			end
		end
	end
end

function Claims:Diagnostics()
	return {
		active = self.Active, cellId = self.Snapshot.cellId, claimable = #self.Snapshot.claimable,
		claims = #self.Snapshot.claims, owned = #self.Snapshot.owned, worldDraws = self.Draws,
		mapDraws = self.MapDraws, hovered = self.Hovered
	}
end
