local suite = ZM_TestHarness.NewSuite()
local CSM = ZM_CSM

suite:Add("sun-shadow projector position follows the local player", function(check)
    local testCSM = {
        SunDirection = Vector(1, 0, 0),
        GetPlayerProjectorPosition = CSM.GetPlayerProjectorPosition
    }
    local playerPosition = Vector(100, 200, 300)
    local cameraOrigin = Vector(-500, 600, 700)
    local projectorPosition = testCSM:GetPlayerProjectorPosition(playerPosition)

    check(projectorPosition:DistToSqr(playerPosition + testCSM.SunDirection * 1024) < 0.001,
        "the shadow projector is offset from the player's entity origin")
    check(projectorPosition:DistToSqr(cameraOrigin + testCSM.SunDirection * 1024) > 0.001,
        "render-camera position does not determine the shadow projector anchor")
end)

suite:Add("tree, bush, foliage and high-poly caster rules", function(check)
    check(CSM.GetDesiredShadowState("models/props_foliage/tree_dry01.mdl", 9000,
        { isFoliage = true, isTree = true }) == true,
        "trees remain CSM shadow casters even above the triangle threshold")
    check(CSM.GetDesiredShadowState("models/props/de_inferno/bushgreensmall.mdl", 400,
        { isFoliage = true, isBushOrHedge = true }) == false,
        "bushes are excluded regardless of triangle count")
    check(CSM.GetDesiredShadowState("models/props_c17/oil_drum.mdl", 5000, {}) == false,
        "non-foliage models at the 5,000-triangle cutoff are excluded")
    check(CSM.GetDesiredShadowState("models/props_c17/oil_drum.mdl", 4999, {}) == nil,
        "lower-poly non-foliage models retain their original shadow state")
    check(CSM.GetDesiredShadowState("models/props_foliage/fern.mdl", 9000,
        { isFoliage = true }) == nil,
        "other foliage keeps its authored shadow state")
    check(CSM.GetDesiredShadowState("models/zombiesim/skybox/cells/zz_preview_test_t0.mdl", 9000,
        { isFoliage = true, isTree = true }) == false,
        "generated skybox models never receive CSM, even if classified as trees")
    check(CSM.ShouldExcludeModel("models/zombiesim/skybox/cells/zz_preview_test_t0.mdl", 9000, {}),
        "skybox models are rejected before polygon measurement")
end)

suite:Add("CSM tree and exclusion overrides restore prior entity flags", function(check)
    local model = ClientsideModel("models/props_junk/wood_crate001a.mdl", RENDERGROUP_OPAQUE)
    check(IsValid(model), "temporary model allocates for the flag check")
    if not IsValid(model) then return end

    model:SetNoDraw(true)
    local wasShadowing = bit.band(model:GetEffects(), EF_NOSHADOW) == 0
    local desiredShadowState = not wasShadowing
    local testCSM = {
        ShadowCasterOverrides = {},
        SetShadowCasterState = CSM.SetShadowCasterState,
        RestoreShadowCaster = CSM.RestoreShadowCaster
    }
    testCSM:SetShadowCasterState(model, desiredShadowState, "models/props_junk/wood_crate001a.mdl")
    local isShadowingWhileOverridden = bit.band(model:GetEffects(), EF_NOSHADOW) == 0
    testCSM:RestoreShadowCaster(model)
    local isShadowingAfterRestore = bit.band(model:GetEffects(), EF_NOSHADOW) == 0
    model:Remove()

    check(isShadowingWhileOverridden == desiredShadowState, "the caster takes the requested CSM state")
    check(isShadowingAfterRestore == wasShadowing, "restore retains the model's original shadow flag")
end)

concommand.Remove("zombiesim_dev_test_csm_client")
concommand.Add("zombiesim_dev_test_csm_client", function()
    local summary = suite:Run()
    file.CreateDir("zombiesim")
    file.Write("zombiesim/csm-client-tests.json", util.TableToJSON(summary, true))
    for _, result in ipairs(summary.cases) do
        print("[ZombieSim] " .. (result.passed and "PASS " or "FAIL ") .. result.name)
        for _, failure in ipairs(result.failures) do
            ErrorNoHalt("[ZombieSim] " .. failure .. "\n")
        end
    end
    print(string.format("[ZombieSim] CSM client tests: %d passed, %d failed.", summary.passed, summary.failed))
end)

return suite
