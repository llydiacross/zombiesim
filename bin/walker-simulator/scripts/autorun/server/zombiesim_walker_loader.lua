if not SERVER then return end
if engine.ActiveGamemode() ~= "zombiesim" then return end

require("zombiesimwalker")

if not ZM_WalkerNative then
    ErrorNoHalt("ZombieSim walker module loaded without ZM_WalkerNative\n")
    return
end

local info = ZM_WalkerNative.GetInfo()
print(string.format(
    "[ZombieSim] Walker module loaded: API %s, core %s, status %s",
    tostring(info.ApiVersion),
    tostring(info.Core),
    tostring(info.Status)
))

concommand.Add("zombiesim_walker_smoke", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local passed, reason = ZM_WalkerNative.RunSelfTest()
    local result = {
        apiVersion = ZM_WalkerNative.ApiVersion,
        info = ZM_WalkerNative.GetInfo(),
        passed = passed == true,
        reason = reason,
    }

    file.CreateDir("zombiesim")
    file.Write("zombiesim/walker_module_smoke.json", util.TableToJSON(result, true))
    print(string.format("[ZombieSim] Walker module smoke test: %s", result.passed and "passed" or "failed"))
end)