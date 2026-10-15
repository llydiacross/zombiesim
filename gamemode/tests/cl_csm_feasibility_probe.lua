local hookName = "ZM.CSM.FeasibilityProbe"
local probe = {
	active = false,
	light = nil,
	sunDirection = nil,
	sunDirectionSource = nil,
	brightness = 1,
	skipShadowUpdates = false,
	updateRateHz = 60,
	nextUpdateAt = 0,
	updates = 0,
	totalUpdateSeconds = 0,
	maximumUpdateSeconds = 0,
	lastTarget = "none",
	lastFailure = nil,
	lastOutcome = "not started"
}

local function IsFiniteNumber(value)
	return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsFiniteVector(value)
	return isvector(value) and IsFiniteNumber(value.x) and IsFiniteNumber(value.y) and IsFiniteNumber(value.z)
end

local function GetTraceTarget(player)
	local trace = player:GetEyeTrace()
	if trace.HitWorld then return "world brush" end
	if IsValid(trace.Entity) then return trace.Entity:GetClass() end
	return "none"
end

local function GetPreviewSunDirection()
	if not ZM_CSM or not isfunction(ZM_CSM.GetSunDirection) then
		return nil, "ZM_CSM sunlight helper is unavailable"
	end
	return ZM_CSM:GetSunDirection(game.GetMap())
end

local function StopProbe(reason)
	hook.Remove("PreDrawOpaqueRenderables", hookName)
	hook.Remove("PreCleanupMap", hookName)
	hook.Remove("ShutDown", hookName)

	if IsValid(probe.light) then
		probe.light:Remove()
	end

	probe.active = false
	probe.light = nil
	probe.lastOutcome = "removed: " .. reason
	probe.skipShadowUpdates = false
	probe.nextUpdateAt = 0
	print(string.format(
		"[ZombieSim][CSM probe] Removed (%s); updates=%d; Update avg=%.4fms max=%.4fms; last target=%s.",
		reason,
		probe.updates,
		probe.updates > 0 and probe.totalUpdateSeconds * 1000 / probe.updates or 0,
		probe.maximumUpdateSeconds * 1000,
		probe.lastTarget
	))
end

local function RejectStart(reason)
	probe.lastFailure = reason
	probe.lastOutcome = "rejected"
	ErrorNoHalt("[ZombieSim][CSM probe] " .. reason .. "\n")
end

local function StartProbe()
	if probe.active then
		probe.lastOutcome = "already active"
		print("[ZombieSim][CSM probe] Already active; use zombiesim_dev_csm_probe_status or zombiesim_dev_csm_probe_stop.")
		return
	end
	probe.lastFailure = nil
	probe.lastOutcome = "starting"

	local developer = GetConVar("developer")
	if not developer or developer:GetInt() <= 0 then
		RejectStart("Set the client developer convar to 1 before starting this test-only probe.")
		return
	end

	local player = LocalPlayer()
	if not IsValid(player) or not player:Alive() or not game.GetMap():match("^zz_preview_") then
		RejectStart("Deploy into a generated preview city cell before starting the probe.")
		return
	end

	local sunDirection, sunDirectionSource
	sunDirection, sunDirectionSource = GetPreviewSunDirection()
	if not IsFiniteVector(sunDirection) then
		RejectStart("This preview map has no finite sun direction; no projector was created.")
		return
	end

	local textureMaterial = Material("effects/flashlight001")
	if textureMaterial:IsError() then
		RejectStart("Mounted effects/flashlight001 material is unavailable; no projector was created.")
		return
	end

	local light = ProjectedTexture()
	if not IsValid(light) then
		RejectStart("ProjectedTexture allocation failed; no hook was registered.")
		return
	end

	local configured, configureError = pcall(function()
		light:SetTexture("effects/flashlight001")
		light:SetEnableShadows(true)
		light:SetOrthographic(true, -512, 512, 512, -512)
		light:SetNearZ(16)
		light:SetFarZ(4096)
		light:SetColor(Color(255, 255, 255))
		light:SetBrightness(1)
	end)
	if not configured then
		if IsValid(light) then light:Remove() end
		RejectStart("ProjectedTexture configuration failed: " .. tostring(configureError))
		return
	end

	probe.light = light
	probe.sunDirection = sunDirection
	probe.sunDirectionSource = sunDirectionSource
	probe.skipShadowUpdates = false
	probe.nextUpdateAt = 0
	probe.updates = 0
	probe.totalUpdateSeconds = 0
	probe.maximumUpdateSeconds = 0
	probe.lastTarget = GetTraceTarget(player)
	probe.active = true
	probe.lastOutcome = "active"

	-- This is a local additive feasibility probe only; it does not touch map lightstyles or baked lighting.
	hook.Add("PreDrawOpaqueRenderables", hookName, function(depth, skybox)
		if depth or skybox then return end
		local now = SysTime()
		if now < probe.nextUpdateAt then return end
		probe.nextUpdateAt = now + 1 / probe.updateRateHz

		local currentPlayer = LocalPlayer()
		if not IsValid(currentPlayer) or not currentPlayer:Alive() or not IsValid(probe.light) then
			StopProbe("player or projector became invalid")
			return
		end

		local updated, elapsedOrError = pcall(function()
			local sunwardOffset = probe.sunDirection * 1024
			probe.light:SetPos(currentPlayer:GetPos() + sunwardOffset)
			probe.light:SetAngles(Vector(-probe.sunDirection.x, -probe.sunDirection.y, -probe.sunDirection.z):Angle())

			local startedAt = SysTime()
			probe.light:Update()
			return SysTime() - startedAt
		end)
		if not updated then
			StopProbe("ProjectedTexture:Update failed")
			probe.lastFailure = "ProjectedTexture update failed: " .. tostring(elapsedOrError)
			ErrorNoHalt("[ZombieSim][CSM probe] " .. probe.lastFailure .. "\n")
			return
		end
		local elapsed = elapsedOrError

		probe.updates = probe.updates + 1
		probe.totalUpdateSeconds = probe.totalUpdateSeconds + elapsed
		probe.maximumUpdateSeconds = math.max(probe.maximumUpdateSeconds, elapsed)
	end)
	hook.Add("PreCleanupMap", hookName, function() StopProbe("map cleanup") end)
	hook.Add("ShutDown", hookName, function() StopProbe("client shutdown") end)

	local description = "Started one local 1024-unit orthographic sun projector on " .. game.GetMap() .. " using " .. sunDirectionSource .. "."
	print("[ZombieSim][CSM probe] " .. description .. " This adds light at brightness 1 and consumes one of eight documented shared shadow-projector slots. Run zombiesim_dev_csm_probe_status, then zombiesim_dev_csm_probe_stop.")
end

concommand.Add("zombiesim_dev_csm_probe", function()
	StartProbe()
end)
concommand.Add("zombiesim_dev_csm_probe_stop", function()
	if probe.active then
		StopProbe("manual stop")
	else
		print("[ZombieSim][CSM probe] Not active.")
	end
end)
concommand.Add("zombiesim_dev_csm_probe_skip_updates", function(_, _, args)
	if not probe.active or not IsValid(probe.light) then
		ErrorNoHalt("[ZombieSim][CSM probe] Start the orthographic probe before changing shadow-update mode.\n")
		return
	end

	local value = string.lower(string.Trim(args[1] or ""))
	if value ~= "on" and value ~= "off" then
		ErrorNoHalt("[ZombieSim][CSM probe] Usage: zombiesim_dev_csm_probe_skip_updates on|off\n")
		return
	end
	if not isfunction(probe.light.SetSkipShadowUpdates) then
		probe.lastFailure = "SetSkipShadowUpdates is unavailable on this client branch."
		ErrorNoHalt("[ZombieSim][CSM probe] " .. probe.lastFailure .. "\n")
		return
	end

	local enabled = value == "on"
	local updated, updateError = pcall(probe.light.SetSkipShadowUpdates, probe.light, enabled)
	if not updated then
		probe.lastFailure = "SetSkipShadowUpdates failed: " .. tostring(updateError)
		ErrorNoHalt("[ZombieSim][CSM probe] " .. probe.lastFailure .. "\n")
		return
	end
	probe.skipShadowUpdates = enabled
	probe.lastFailure = nil
	probe.lastOutcome = "shadow update skipping " .. value
	print("[ZombieSim][CSM probe] SetSkipShadowUpdates(" .. tostring(enabled) .. "); this is a test-only static-view optimization and may freeze/stale shadows.")
end)
concommand.Add("zombiesim_dev_csm_probe_rate", function(_, _, args)
	if not probe.active then
		ErrorNoHalt("[ZombieSim][CSM probe] Start the orthographic probe before changing its update rate.\n")
		return
	end

	local rate = tonumber(string.Trim(args[1] or ""))
	if rate ~= 15 and rate ~= 30 and rate ~= 60 then
		ErrorNoHalt("[ZombieSim][CSM probe] Usage: zombiesim_dev_csm_probe_rate 15|30|60\n")
		return
	end

	probe.updateRateHz = rate
	probe.nextUpdateAt = 0
	probe.lastOutcome = "update rate set to " .. rate .. " Hz"
	print("[ZombieSim][CSM probe] Projector Update rate set to " .. rate .. " Hz.")
end)
concommand.Add("zombiesim_dev_csm_probe_status", function(_, _, args)
	local player = LocalPlayer()
	probe.lastTarget = IsValid(player) and GetTraceTarget(player) or "no valid local player"
	local status = {
		map = game.GetMap(),
		active = probe.active,
		projectorValid = IsValid(probe.light),
		skipShadowUpdatesSupported = IsValid(probe.light) and isfunction(probe.light.SetSkipShadowUpdates) or false,
		skipShadowUpdates = probe.skipShadowUpdates,
		sunDirection = probe.sunDirection and {
			x = probe.sunDirection.x,
			y = probe.sunDirection.y,
			z = probe.sunDirection.z
		} or nil,
		sunDirectionSource = probe.sunDirectionSource,
		brightness = probe.brightness,
		updateRateHz = probe.updateRateHz,
		updates = probe.updates,
		updateAverageMilliseconds = probe.updates > 0 and probe.totalUpdateSeconds * 1000 / probe.updates or 0,
		updateMaximumMilliseconds = probe.maximumUpdateSeconds * 1000,
		lastTarget = probe.lastTarget,
		lastFailure = probe.lastFailure,
		lastOutcome = probe.lastOutcome
	}
	print(string.format(
		"[ZombieSim][CSM probe] map=%s active=%s projectorValid=%s sunDirection=%s updateRate=%dHz updates=%d UpdateAvg=%.4fms UpdateMax=%.4fms lastTarget=%s",
		status.map,
		tostring(status.active),
		tostring(status.projectorValid),
		status.sunDirection and tostring(probe.sunDirection) or "unavailable",
		status.updateRateHz,
		status.updates,
		status.updateAverageMilliseconds,
		status.updateMaximumMilliseconds,
		status.lastTarget
	))

	local requestId = tonumber(args[1])
	if requestId and requestId == math.floor(requestId) and requestId > 0 and requestId <= 65535 then
		local encoded = util.TableToJSON(status)
		if not encoded or #encoded > 8192 then
			ErrorNoHalt("[ZombieSim][CSM probe] Could not serialize a bounded status report.\n")
			return
		end
		net.Start("ZM.CSM.FeasibilityProbe.Status")
			net.WriteUInt(requestId, 16)
			net.WriteString(encoded)
		net.SendToServer()
	end
end)
