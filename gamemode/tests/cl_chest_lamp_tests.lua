local suite = ZM_TestHarness.NewSuite()
local ChestLamp = ZM_ChestLamp

local function makeCSM(state, enabledValue, projectorCount)
	local projectors = {}
	for index = 1, projectorCount do
		projectors[index] = {}
	end

	return {
		State = state,
		Projectors = projectors,
		ConVars = {
			enabled = {
				GetBool = function()
					return enabledValue
				end
			}
		}
	}
end

suite:Add("only the local chest lamp shadows while CSM is ready", function(check)
	local localPlayer = {}
	local remotePlayer = {}
	local activeCSM = makeCSM("ready", true, 3)

	check(ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, activeCSM),
		"the local lamp casts shadows with ready, enabled CSM projectors")
	check(not ChestLamp.ShouldShadowOwner(remotePlayer, localPlayer, activeCSM),
		"remote players' lamps remain unshadowed")
	check(not ChestLamp.ShouldShadowOwner(localPlayer, {}, activeCSM),
		"a non-local owner does not receive the local shadowed lamp")
end)

suite:Add("inactive or incomplete CSM keeps the chest lamp unshadowed", function(check)
	local localPlayer = {}

	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, makeCSM("off", true, 1)),
		"disabled CSM state keeps shadows off")
	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, makeCSM("suspended", true, 1)),
		"suspended CSM state keeps shadows off")
	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, makeCSM("ready", false, 1)),
		"the enabled convar is required")
	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, makeCSM("ready", true, 0)),
		"at least one active CSM projector is required")
	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, nil),
		"missing CSM state keeps shadows off")

	local missingConVar = { State = "ready", Projectors = { {} }, ConVars = {} }
	check(not ChestLamp.ShouldShadowOwner(localPlayer, localPlayer, missingConVar),
		"missing CSM convar keeps shadows off")
end)

concommand.Remove("zombiesim_dev_test_chest_lamp_client")
concommand.Add("zombiesim_dev_test_chest_lamp_client", function()
	local summary = suite:Run()
	file.CreateDir("zombiesim")
	file.Write("zombiesim/chest-lamp-client-tests.json", util.TableToJSON(summary, true))
	for _, result in ipairs(summary.cases) do
		print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
		for _, failure in ipairs(result.failures) do
			ErrorNoHalt("[ZombieSim] " .. failure .. "\n")
		end
	end
	print(string.format("[ZombieSim] Chest lamp client tests: %d passed, %d failed.", summary.passed, summary.failed))
end)

return suite
