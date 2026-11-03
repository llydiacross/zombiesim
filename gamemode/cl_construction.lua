// Client construction presentation: while the held Hammer is in build mode, outline the outer boundary of the
// claim tiles the server says this player can build on, and show a small build-mode label. The server owns
// eligibility; this module only draws what it was sent.
local Construction = ZM_Construction

Construction.Client = Construction.Client or { tiles = {}, tileSize = 640, paths = {}, draws = 0 }
local state = Construction.Client

local beamMaterial = Material( "effects/laser1" )
local beamColor = Color( 90, 200, 255, 255 )
local sampleSpacing = 64
local groundLift = 8
local traceUp = 1024
local traceDown = 4096

// Ground-following points along one boundary edge, traced once when the tiles arrive.
local function tracePath( edge, referenceZ )
	local x1, y1, x2, y2 = edge[1], edge[2], edge[3], edge[4]
	local length = math.max( math.abs( x2 - x1 ), math.abs( y2 - y1 ) )
	local steps = math.max( 1, math.ceil( length / sampleSpacing ) )
	local points = {}
	for step = 0, steps do
		local fraction = step / steps
		local x, y = x1 + ( x2 - x1 ) * fraction, y1 + ( y2 - y1 ) * fraction
		local trace = util.TraceLine( {
			start = Vector( x, y, referenceZ + traceUp ),
			endpos = Vector( x, y, referenceZ - traceDown ),
			mask = MASK_SOLID_BRUSHONLY
		} )
		local z = trace.Hit and not trace.StartSolid and trace.HitPos.z or referenceZ
		points[#points + 1] = Vector( x, y, z + groundLift )
	end
	return points
end

local function rebuildPaths()
	local client = LocalPlayer()
	local referenceZ = IsValid( client ) and client:GetPos().z or 0
	state.paths = {}
	for _, edge in ipairs( Construction.BoundaryEdges( state.tiles, state.tileSize ) ) do
		state.paths[#state.paths + 1] = tracePath( edge, referenceZ )
	end
end

net.Receive( "ZM.Construction.Tiles", function()
	state.tileSize = net.ReadUInt( 16 )
	local count = net.ReadUInt( 5 )
	state.tiles = {}
	for _ = 1, count do
		state.tiles[#state.tiles + 1] = { tileX = net.ReadInt( 4 ), tileY = net.ReadInt( 4 ) }
	end
	rebuildPaths()
end )

function Construction:LocalBuildMode()
	local client = LocalPlayer()
	if not IsValid( client ) or not client:Alive() then return false end
	local weapon = client:GetActiveWeapon()
	return IsValid( weapon ) and weapon:GetClass() == self.ToolClass and weapon.GetBuildMode ~= nil and weapon:GetBuildMode() == true
end

function Construction:LocalDeleteMode()
	return self:LocalBuildMode() and LocalPlayer():GetNWBool( "ZM_ConstructionDeleteMode", false )
end

function Construction:PieceSelectedForDeletion( entity )
	return self:LocalDeleteMode() and entity:GetNWEntity( "ZM_ConstructionOwner" ) == LocalPlayer()
		and entity:GetNWBool( "ZM_ConstructionDeleteSelected", false )
end

hook.Add( "Think", "ZM.Construction.DeleteKey", function()
	local down = input.IsKeyDown( KEY_DELETE )
	local pressed = down and not state.deleteKeyDown
	state.deleteKeyDown = down
	if not pressed or not Construction:LocalBuildMode() then return end
	if gui.IsGameUIVisible() or vgui.CursorVisible() or IsValid( vgui.GetKeyboardFocus() )
		or Construction.Gallery and Construction.Gallery:IsOpen() then return end
	net.Start( "ZM.Construction.Delete" )
	net.SendToServer()
end )

hook.Add( "PostDrawTranslucentRenderables", "ZM.Construction.Boundary", function( depth, skybox )
	if depth or skybox then return end
	state.draws = 0
	if #state.paths == 0 or not Construction:LocalBuildMode() then return end
	local pulse = 150 + 100 * math.abs( math.sin( CurTime() * 2 ) )
	beamColor.a = pulse
	render.SetMaterial( beamMaterial )
	for _, points in ipairs( state.paths ) do
		for index = 2, #points do
			render.DrawBeam( points[index - 1], points[index], 6, 0, 1, beamColor )
			state.draws = state.draws + 1
		end
	end
end )

hook.Add( "HUDPaint", "ZM.Construction.Label", function()
	if not Construction:LocalBuildMode() then return end
	local x, y = 16, 16
	local width, height = math.min( 360, ScrW() - 32 ), 96
	draw.RoundedBox( 5, x, y, width, height, Color( 10, 14, 18, 220 ) )
	surface.SetDrawColor( 90, 200, 255, 190 )
	surface.DrawOutlinedRect( x, y, width, height, 1 )
	local left = x + 12
	local deleting = Construction:LocalDeleteMode()
	draw.SimpleText( deleting and "DELETE MODE" or "BUILD MODE", "DermaDefaultBold", left, y + 9,
		deleting and Color( 255, 75, 75 ) or Color( 90, 200, 255 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	draw.SimpleText( "Reload to exit", "DermaDefault", x + width - 12, y + 9, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
	if deleting then
		draw.SimpleText( LocalPlayer():GetNWInt( "ZM_ConstructionDeleteCount", 0 ) .. " piece(s) marked red",
			"DermaDefaultBold", left, y + 30, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		draw.SimpleText( "LMB mark/unmark  |  Delete confirm", "DermaDefault", left, y + 51,
			Color( 210, 210, 210 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		draw.SimpleText( "Paid materials refunded  |  Reload cancels", "DermaDefault", left, y + 69,
			Color( 210, 210, 210 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		return
	end
	local weapon = LocalPlayer():GetActiveWeapon()
	local kind = Construction.SelectedPiece( weapon )
	local mastercraft = weapon.GetItemMastercraft and weapon:GetItemMastercraft() or false
	local seconds = Construction:BuildSeconds( kind, weapon.GetItemLevel and weapon:GetItemLevel() or 0 ) or 0
	draw.SimpleText( string.format( "%s  |  %s  |  %.1fs", Construction.Pieces[kind].name,
		Construction:CostText( kind, mastercraft ), seconds ), "DermaDefaultBold", left, y + 30,
		color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	local galleryKey = Construction.Gallery and Construction.Gallery:BindingLabel() or "Q"
	draw.SimpleText( galleryKey .. " gallery  |  LMB place  |  Delete select", "DermaDefault",
		left, y + 51, Color( 210, 210, 210 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
	draw.SimpleText( "E build  |  RMB undo blueprint", "DermaDefault",
		left, y + 69, Color( 210, 210, 210 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
end )

// "N Wood, N Scrap Metal" for a piece, in a stable order.
function Construction:CostText( kind, mastercraft )
	local cost = self.MaterialCost( kind, mastercraft )
	if not cost then return "" end
	local ids = table.GetKeys( cost )
	table.sort( ids )
	local parts = {}
	for _, itemId in ipairs( ids ) do
		local definition = ZM_Items and ZM_Items:GetDefinition( itemId )
		parts[#parts + 1] = cost[itemId] .. " " .. ( definition and definition.name or itemId )
	end
	return table.concat( parts, ", " )
end

// Where the selected piece would go, mirroring the server's PrimaryBuild checks; nil when nothing is aimed at.
function Construction:GhostPlacement()
	if self:LocalDeleteMode() then return nil end
	local client = LocalPlayer()
	local weapon = client:GetActiveWeapon()
	local kind = self.SelectedPiece( weapon )
	local trace = self:PlacementTrace( client, kind )
	if not trace.Hit then return nil end
	local x, y, z, yaw, valid = self.ResolvePlacement( kind, trace, client:EyeAngles().y )
	if not x then return nil end
	if valid then
		for _, corner in ipairs( self.FootprintCorners( kind, x, y, yaw ) ) do
			if not self.WithinTiles( corner, state.tiles, state.tileSize, 0 ) then
				valid = false
				break
			end
		end
	end
	return kind, Vector( x, y, z ), yaw, valid
end

local ghostValid = Color( 90, 255, 140, 230 )
local ghostInvalid = Color( 255, 80, 80, 230 )

hook.Add( "PostDrawTranslucentRenderables", "ZM.Construction.Ghost", function( depth, skybox )
	if depth or skybox then return end
	state.ghostDrawn = false
	if not Construction:LocalBuildMode() then return end
	local kind, origin, yaw, valid = Construction:GhostPlacement()
	if not kind then return end
	render.SetColorMaterial()
	Construction.Geometry.DrawWire( kind, yaw, origin, valid and ghostValid or ghostInvalid )
	state.ghostDrawn = true
	state.ghostValid = valid
end )

// Diagnostics for a dev status report.
function Construction:ClientStatus()
	local beamTexture = beamMaterial:GetTexture( "$basetexture" )
	local client = LocalPlayer()
	return {
		buildMode = self:LocalBuildMode(),
		deleteMode = self:LocalDeleteMode(),
		deleteSelection = IsValid( client ) and client:GetNWInt( "ZM_ConstructionDeleteCount", 0 ) or 0,
		tiles = #state.tiles,
		paths = #state.paths,
		beamsLastFrame = state.draws,
		ghostDrawn = state.ghostDrawn == true,
		ghostValid = state.ghostValid == true,
		geometry = Construction.Geometry.Status(),
		galleryOpen = Construction.Gallery and Construction.Gallery:IsOpen() or false,
		materialError = beamMaterial:IsError(),
		materialShader = beamMaterial:GetShader(),
		materialTextureWidth = beamTexture and beamTexture:Width() or 0,
		pieceMaterials = ZM_ConstructionPieceMaterialStatus and ZM_ConstructionPieceMaterialStatus() or nil
	}
end

concommand.Add( "zombiesim_dev_construction_status", function()
	local client = LocalPlayer()
	if not IsValid( client ) or not client:IsAdmin() or not ZM_World or ZM_World.ActiveProfile ~= "preview" then
		ErrorNoHalt( "[ZombieSim] Construction diagnostics require a preview admin.\n" )
		return
	end
	local status = Construction:ClientStatus()
	status.map = game.GetMap()
	status.profile = ZM_World.ActiveProfile
	status.capturedAt = os.time()
	local encoded = util.TableToJSON( status, true )
	if not encoded then
		ErrorNoHalt( "[ZombieSim] Could not encode construction diagnostics.\n" )
		return
	end
	file.CreateDir( "zombiesim" )
	if not file.Write( "zombiesim/construction_status.json", encoded ) then
		ErrorNoHalt( "[ZombieSim] Could not write construction diagnostics.\n" )
		return
	end
	print( "[ZombieSim] Construction diagnostics saved to data/zombiesim/construction_status.json." )
end )
