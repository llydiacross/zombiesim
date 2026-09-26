// Client diagnostics for Escape/menu state during development-console testing.
local lastMenuVisible = false

hook.Add("Think", "ZM.LogPauseState", function()
    local menuVisible = gui.IsGameUIVisible()
    if menuVisible == lastMenuVisible then return end
    lastMenuVisible = menuVisible
    print(menuVisible and "[ZombieSim] Game menu open; console bridge commands may wait until it closes." or "[ZombieSim] Game menu closed; pending console bridge commands may now run.")
end)