local ChestLamp = {}
ZM_ChestLamp = ChestLamp

local enabledNetworkKey = "ZM_ChestLampEnabled"
local toggleNetworkMessage = "ZM.ChestLamp.Toggle"
local projectionHook = "ZM.ChestLamp.Project"
local reconcileInterval = 0.25
local maximumRenderDistance = 2048
local maximumVisibleLamps = 4
local chestBoneName = "ValveBiped.Bip01_Spine2"
local states = {}
local failedModels = {}
local nextReconcile = 0
local frameUpdates = 0
local totalUpdateSeconds = 0
local maximumUpdateSeconds = 0

local function IsGameplayCell()
	return ZM_World and ZM_World.ActiveProfile ~= nil and game.GetMap():match("^zz_") ~= nil
end

local function IsFiniteNumber(value)
	return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsFiniteVector(value)
	return isvector(value) and IsFiniteNumber(value.x) and IsFiniteNumber(value.y) and IsFiniteNumber(value.z)
end

local function RemoveLight(owner, reason)
	local state = states[owner]
	if not state then return end

	if IsValid(state.light) then
		state.light:Remove()
	end
	states[owner] = nil

	if reason then
		ErrorNoHalt("[ZombieSim][Chest lamp] Removed a projected light: " .. reason .. "\n")
	end
end

local function ClearLights()
	for owner in pairs(states) do
		RemoveLight(owner)
	end
	states = {}
	failedModels = {}
end

local function FailModel(owner, message)
	local model = owner:GetModel()
	if failedModels[owner] == model then return end
	failedModels[owner] = model
	ErrorNoHalt("[ZombieSim][Chest lamp] " .. message .. " Model: " .. tostring(model) .. "\n")
end

local function IsFlashlightBind(bind)
	local translated = input.TranslateAlias(bind or "")
	if not isstring(translated) then translated = bind or "" end
	return string.lower(string.Trim(translated)) == "impulse 100"
end

local function CreateLight(owner, bone, model)
	local material = Material("effects/flashlight001")
	if material:IsError() then
		FailModel(owner, "Mounted effects/flashlight001 material is unavailable.")
		return nil
	end

	local light = ProjectedTexture()
	if not IsValid(light) then
		FailModel(owner, "ProjectedTexture allocation failed.")
		return nil
	end

	local configured, configureError = pcall(function()
		light:SetTexture("effects/flashlight001")
		light:SetOrthographic(false, 0, 0, 0, 0)
		light:SetFOV(60)
		light:SetNearZ(12)
		light:SetFarZ(maximumRenderDistance)
		light:SetColor(Color(255, 255, 255))
		light:SetBrightness(1)
		light:SetEnableShadows(false)
	end)
	if not configured then
		if IsValid(light) then light:Remove() end
		FailModel(owner, "ProjectedTexture setup failed: " .. tostring(configureError))
		return nil
	end

	failedModels[owner] = nil
	return {
		light = light,
		bone = bone,
		model = model,
		lastPosition = nil,
		lastDirection = nil
	}
end

local function ReconcileLights()
	if not IsGameplayCell() then
		ClearLights()
		return
	end

	local localPlayer = LocalPlayer()
	if not IsValid(localPlayer) then
		ClearLights()
		return
	end

	local localPosition = localPlayer:GetPos()
	local maximumDistanceSquared = maximumRenderDistance * maximumRenderDistance
	local candidates = {}
	for _, owner in ipairs(player.GetAll()) do
		if not IsValid(owner) or not owner:Alive() or not owner:GetNWBool(enabledNetworkKey, false) then
			failedModels[owner] = nil
			continue
		end

		local ownerPosition = owner:GetPos()
		local distanceSquared = ownerPosition:DistToSqr(localPosition)
		if distanceSquared <= maximumDistanceSquared then
			candidates[#candidates + 1] = {
				owner = owner,
				distanceSquared = distanceSquared,
				model = owner:GetModel()
			}
		end
	end

	table.sort(candidates, function(left, right)
		if left.distanceSquared ~= right.distanceSquared then return left.distanceSquared < right.distanceSquared end
		return left.owner:EntIndex() < right.owner:EntIndex()
	end)

	local selected = {}
	for index = 1, math.min(#candidates, maximumVisibleLamps) do
		local candidate = candidates[index]
		local owner = candidate.owner
		selected[owner] = true
		local state = states[owner]
		if state and (state.model ~= candidate.model or not IsValid(state.light)) then
			RemoveLight(owner)
			state = nil
		end

		if not state and failedModels[owner] ~= candidate.model then
			local bone = owner:LookupBone(chestBoneName)
			if bone == nil then
				FailModel(owner, "Chest bone " .. chestBoneName .. " was not found.")
			else
				state = CreateLight(owner, bone, candidate.model)
				if state then states[owner] = state end
			end
		end

	end

	for owner in pairs(states) do
		if not selected[owner] then RemoveLight(owner) end
	end
end

function ChestLamp:GetDiagnosticSnapshot()
	local active = {}
	for owner, state in pairs(states) do
		if IsValid(state.light) then
			active[#active + 1] = {
				player = IsValid(owner) and owner:Nick() or "disconnected",
				model = state.model
			}
		end
	end

	return {
		map = game.GetMap(),
		profile = ZM_World and ZM_World.ActiveProfile or nil,
		localLampEnabled = IsValid(LocalPlayer()) and LocalPlayer():GetNWBool(enabledNetworkKey, false) or false,
		activeProjectors = #active,
		shadowedProjectors = 0,
		maximumVisibleProjectors = maximumVisibleLamps,
		maximumDistance = maximumRenderDistance,
		frameUpdates = frameUpdates,
		updateAverageMilliseconds = frameUpdates > 0 and totalUpdateSeconds * 1000 / frameUpdates or 0,
		updateMaximumMilliseconds = maximumUpdateSeconds * 1000,
		projectors = active
	}
end

hook.Add("PlayerBindPress", "ZM.ChestLamp.ToggleBind", function(playerEntity, bind)
	if playerEntity ~= LocalPlayer() or not IsGameplayCell() then return end
	if vgui.CursorVisible() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then return end
	if not IsFlashlightBind(bind) then return end

	net.Start(toggleNetworkMessage)
	net.SendToServer()
	return true
end)

hook.Add("Think", "ZM.ChestLamp.Reconcile", function()
	local now = CurTime()
	if now < nextReconcile then return end
	nextReconcile = now + reconcileInterval
	ReconcileLights()
end)

hook.Add("PreDrawOpaqueRenderables", "ZM.ChestLamp.Project", function(depth, skybox)
	if depth or skybox or not next(states) then return end

	for owner, state in pairs(states) do
		if not IsValid(owner) or not owner:Alive() or not IsValid(state.light) then
			RemoveLight(owner)
			continue
		end

		local updated, elapsedOrError = pcall(function()
			local chestPosition = owner:GetBonePosition(state.bone)
			local aimAngles = owner:EyeAngles()
			local aimDirection = aimAngles:Forward()
			if not IsFiniteVector(chestPosition) or not IsFiniteVector(aimDirection) then
				error("chest bone position or eye direction is invalid")
			end

			local lightPosition = chestPosition + aimDirection * 8
			local positionChanged = not state.lastPosition or state.lastPosition:DistToSqr(lightPosition) > 0.25
			local directionChanged = not state.lastDirection or state.lastDirection:Dot(aimDirection) < 0.999999
			if not positionChanged and not directionChanged then return 0 end

			state.light:SetPos(lightPosition)
			state.light:SetAngles(aimAngles)
			local startedAt = SysTime()
			state.light:Update()
			state.lastPosition = lightPosition
			state.lastDirection = aimDirection
			return SysTime() - startedAt
		end)
		if not updated then
			RemoveLight(owner, "projector update failed: " .. tostring(elapsedOrError))
			FailModel(owner, "ProjectedTexture update failed: " .. tostring(elapsedOrError))
			continue
		end

		if elapsedOrError > 0 then
			frameUpdates = frameUpdates + 1
			totalUpdateSeconds = totalUpdateSeconds + elapsedOrError
			maximumUpdateSeconds = math.max(maximumUpdateSeconds, elapsedOrError)
		end
	end
end)

hook.Add("PreCleanupMap", "ZM.ChestLamp.Cleanup", ClearLights)
hook.Add("ShutDown", "ZM.ChestLamp.Cleanup", ClearLights)

concommand.Add("zombiesim_chest_lamp_status", function()
	print("[ZombieSim][Chest lamp] " .. util.TableToJSON(ChestLamp:GetDiagnosticSnapshot(), true))
end)
