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
	if not IsValid( client ) then return false end
	local weapon = client:GetActiveWeapon()
	return IsValid( weapon ) and weapon:GetClass() == self.ToolClass and weapon.GetBuildMode ~= nil and weapon:GetBuildMode() == true
end

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
	local centreX = ScrW() / 2
	draw.SimpleTextOutlined( "BUILD MODE  -  Reload to exit", "DermaLarge", centreX, ScrH() * 0.12,
		Color( 90, 200, 255 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color( 0, 0, 0, 200 ) )
	local weapon = LocalPlayer():GetActiveWeapon()
	local kind = Construction.SelectedPiece( weapon )
	local mastercraft = weapon.GetItemMastercraft and weapon:GetItemMastercraft() or false
	local seconds = Construction:BuildSeconds( kind, weapon.GetItemLevel and weapon:GetItemLevel() or 0 ) or 0
	draw.SimpleTextOutlined( string.format( "%s  -  %s  -  %.1fs", Construction.Pieces[kind].name,
		Construction:CostText( kind, mastercraft ), seconds ), "DermaDefaultBold", centreX, ScrH() * 0.12 + 28,
		color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color( 0, 0, 0, 200 ) )
	draw.SimpleTextOutlined( "LMB place  -  RMB next piece / remove blueprint  -  hold E to build", "DermaDefault",
		centreX, ScrH() * 0.12 + 46, Color( 200, 200, 200 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color( 0, 0, 0, 200 ) )
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
	local client = LocalPlayer()
	local weapon = client:GetActiveWeapon()
	local trace = self:AimTrace( client )
	if not trace.Hit then return nil end
	local kind = self.SelectedPiece( weapon )
	local x, y, z, yaw = self.SnapPlacement( kind, trace.HitPos.x, trace.HitPos.y, trace.HitPos.z, client:EyeAngles().y )
	local valid = trace.HitNormal.z >= 0.7
	local entity = trace.Entity
	if valid and not trace.HitWorld then
		valid = IsValid( entity ) and entity:GetClass() == "zn_construction_piece" and entity:GetComplete()
	end
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
	local minX, minY, minZ, maxX, maxY, maxZ = Construction.PieceBounds( kind, yaw )
	render.SetColorMaterial()
	render.DrawWireframeBox( origin, angle_zero, Vector( minX, minY, minZ ), Vector( maxX, maxY, maxZ ),
		valid and ghostValid or ghostInvalid, true )
	state.ghostDrawn = true
	state.ghostValid = valid
end )

// Diagnostics for a dev status report.
function Construction:ClientStatus()
	return {
		buildMode = self:LocalBuildMode(),
		tiles = #state.tiles,
		paths = #state.paths,
		beamsLastFrame = state.draws,
		ghostDrawn = state.ghostDrawn == true,
		ghostValid = state.ghostValid == true,
		materialError = beamMaterial:IsError(),
		pieceMaterials = ZM_ConstructionPieceMaterialStatus and ZM_ConstructionPieceMaterialStatus() or nil
	}
end
