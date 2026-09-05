// Gmod SQL table to store player attributes and eventually their XP/Level and inventory

function CreatePlayerAttributesTable()
    if not sql.TableExists("player_attributes") then
        sql.Query("CREATE TABLE player_attributes (steamid TEXT PRIMARY KEY, Strength INTEGER, Agility INTEGER, Intelligence INTEGER, Endurance INTEGER, MachineGuns INTEGER, Shotguns INTEGER, Snipers INTEGER, WeaponCrafting INTEGER, ArmorCrafting INTEGER, Medicine INTEGER, Farming INTEGER, WeaponRepairing INTEGER, ArmorRepairing INTEGER, Mechanics INTEGER)")
    end
end

function CreatePlayerDataTable()
    if not sql.TableExists("player_data") then
        sql.Query("CREATE TABLE player_data (steamid TEXT PRIMARY KEY, XP INTEGER, Level INTEGER, MaxLevel INTEGER, Difficulty INTEGER, CellX INTEGER, CellY INTEGER, SkillPoints INTEGER)")
    end
end

function PlayerPreviouslyExists(steamid)
    local result = sql.Query("SELECT * FROM player_attributes WHERE steamid = " .. sql.SQLStr(steamid))
    if result then
        return true
    else
        return false
    end
end

function GetPlayerAttributes(steamid)
    local result = sql.Query("SELECT * FROM player_attributes WHERE steamid = " .. sql.SQLStr(steamid))
    if result then
        return result[1]
    else
        return nil
    end
end

function GetPlayerData(steamid)
    local result = sql.Query("SELECT * FROM player_data WHERE steamid = " .. sql.SQLStr(steamid))
    if result then
        return result[1]
    else
        return nil
    end
end

function SetPlayerAttributes(steamid, attributes)
    local query = "INSERT OR REPLACE INTO player_attributes (steamid, Strength, Agility, Intelligence, Endurance, MachineGuns, Shotguns, Snipers, WeaponCrafting, ArmorCrafting, Medicine, Farming, WeaponRepairing, ArmorRepairing, Mechanics) VALUES (" .. sql.SQLStr(steamid) .. ", " .. attributes.Strength .. ", " .. attributes.Agility .. ", " .. attributes.Intelligence .. ", " .. attributes.Endurance .. ", " .. attributes.MachineGuns .. ", " .. attributes.Shotguns .. ", " .. attributes.Snipers .. ", " .. attributes.WeaponCrafting .. ", " .. attributes.ArmorCrafting .. ", " .. attributes.Medicine .. ", " .. attributes.Farming .. ", " .. attributes.WeaponRepairing .. ", " .. attributes.ArmorRepairing .. ", " .. attributes.Mechanics .. ")"
    sql.Query(query)
end

function SetPlayerData(steamid, data)
    local query = "INSERT OR REPLACE INTO player_data (steamid, XP, Level, MaxLevel, Difficulty, CellX, CellY, SkillPoints) VALUES (" .. sql.SQLStr(steamid) .. ", " .. data.XP .. ", " .. data.Level .. ", " .. data.MaxLevel .. ", " .. data.Difficulty .. ", " .. data.CellX .. ", " .. data.CellY .. ", " .. data.SkillPoints .. ")"
    sql.Query(query)
end