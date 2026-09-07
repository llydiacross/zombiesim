// Confirms a client has finished loading after buildcubemaps restarts the current map.
hook.Add("InitPostEntity", "ZombieSim.ResumeMapBatchFromClient", function()
    timer.Simple(3, function()
        RunConsoleCommand("zombiesim_map_batch_resume")
    end)
end)