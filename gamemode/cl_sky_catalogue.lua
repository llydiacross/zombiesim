ZM_SkyPalettes = ZM_SkyPalettes or {}
local Palettes = ZM_SkyPalettes
Palettes.ContextOrder = { "day", "overcast", "dusk", "night" }
Palettes.Entries = {
    natural_day = { label = "Natural daylight", context = "day", top = { 65, 119, 184 } },
    natural_dusk = { label = "Natural dusk", context = "dusk", top = { 77, 82, 120 } },
    natural_night = { label = "Natural night", context = "night", top = { 13, 23, 42 } },
    natural_overcast = { label = "Natural overcast", context = "overcast", top = { 106, 122, 140 } },
    cinematic_day = { label = "Cinematic daylight", context = "day", top = { 42, 96, 160 } },
    cinematic_dusk = { label = "Cinematic violet dusk", context = "dusk", top = { 81, 52, 112 } },
    cinematic_night = { label = "Cinematic silver-blue night", context = "night", top = { 14, 28, 55 } },
    cinematic_overcast = { label = "Cinematic overcast", context = "overcast", top = { 76, 94, 116 } },
    mounted_day = { label = "HL2 cloudy daylight", context = "day", mounted = "skybox/sky_day03_06c" }
}
// LDR skies avoid treating the engine's packed HDR textures as ordinary UnlitGeneric colour.
for _, name in ipairs({
    "sky_borealis01", "sky_wasteland02", "sky_day01_01", "sky_day01_04", "sky_day01_05",
    "sky_day01_06", "sky_day01_07", "sky_day01_08", "sky_day01_09", "sky_day02_01",
    "sky_day02_02", "sky_day02_03", "sky_day02_04", "sky_day02_05", "sky_day02_06",
    "sky_day02_07", "sky_day02_09", "sky_day02_10", "sky_day03_01", "sky_day03_02",
    "sky_day03_03", "sky_day03_04", "sky_day03_05", "sky_day03_06", "sky_day03_06b",
    "sky_ep01_00", "sky_ep01_01", "sky_ep01_02", "sky_ep01_04", "sky_ep01_04a",
    "sky_ep02_01", "sky_ep02_02", "sky_ep02_03", "sky_ep02_04", "sky_ep02_05",
    "sky_ep02_06", "sky_ep02_07"
}) do
    local context = name:find("day02", 1, true) and "dusk" or "day"
    if name == "sky_borealis01" then context = "night"
    elseif name == "sky_wasteland02" then context = "overcast" end
    Palettes.Entries["mounted_" .. name] = {
        label = "HL2 / " .. name:gsub("^sky_", ""), context = context, mounted = "skybox/" .. name
    }
end

Palettes.CatalogueFailure = nil
local rawCatalogue = file.Read("data_static/sky_catalogue.json", "GAME")
local catalogue = rawCatalogue and util.JSONToTable(rawCatalogue)
local function validFaces(faces)
    if not istable(faces) then return false end
    for _, suffix in ipairs({ "ft", "bk", "lf", "rt", "up", "dn" }) do
        local info = faces[suffix]
        if not istable(info) or not isnumber(info.width) or not isnumber(info.height) or
            info.width < 1 or info.height < 1 or not isstring(info.transform) or
            (info.scaleX ~= 1 and info.scaleX ~= 2) or (info.scaleY ~= 1 and info.scaleY ~= 2) then return false end
    end
    return true
end
if not catalogue or catalogue.schemaVersion ~= 1 or not istable(catalogue.entries) then
    Palettes.CatalogueFailure = "Sky content catalogue unavailable or invalid; rebuild/stage the sky catalogue."
    ErrorNoHalt("[ZombieSim] " .. Palettes.CatalogueFailure .. "\n")
else
    for _, entry in ipairs(catalogue.entries) do
        if not isstring(entry.id) or not entry.id:match("^imported_[a-z0-9_]+$") or
            not isstring(entry.material) or not entry.material:match("^zombiesim/skies/[a-z0-9_]+$") or
            not isstring(entry.label) or not isstring(entry.credit) or not isstring(entry.licence) or not validFaces(entry.faces) or
            not table.HasValue(Palettes.ContextOrder, entry.context) or Palettes.Entries[entry.id] then
            Palettes.CatalogueFailure = "Invalid imported sky catalogue entry."
            ErrorNoHalt("[ZombieSim] " .. Palettes.CatalogueFailure .. "\n")
        else
            Palettes.Entries[entry.id] = { label = entry.label, context = entry.context,
                mounted = entry.material, credit = entry.credit, licence = entry.licence, faces = entry.faces }
        end
    end
end

Palettes.Profiles = {}
Palettes.ProfileOrder = { "natural", "cinematic", "coastal", "warm", "muted", "moonlit" }
for _, id in ipairs({ "natural", "cinematic" }) do
    local contexts = {}
    for _, context in ipairs(Palettes.ContextOrder) do contexts[context] = id .. "_" .. context end
    Palettes.Profiles[id] = { label = id == "natural" and "Natural" or "Cinematic", contexts = contexts }
end
Palettes.Profiles.coastal = { label = "Coastal haze", contexts = {
    day = "mounted_sky_day01_04", overcast = "mounted_day", dusk = "natural_dusk", night = "natural_night" } }
Palettes.Profiles.warm = { label = "Warm horizons", contexts = {
    day = "mounted_sky_day01_05", overcast = "cinematic_overcast",
    dusk = "mounted_sky_day02_01", night = "cinematic_night" } }
Palettes.Profiles.muted = { label = "Muted wasteland", contexts = {
    day = "mounted_sky_day03_01", overcast = "mounted_sky_wasteland02",
    dusk = "natural_dusk", night = "natural_night" } }
Palettes.Profiles.moonlit = { label = "Moonlit clouds", contexts = {
    day = "mounted_sky_day01_01", overcast = "natural_overcast",
    dusk = "cinematic_dusk", night = "imported_moonlit" } }
for index = 1, 6 do
    local id = "tropospheric_" .. index
    Palettes.ProfileOrder[#Palettes.ProfileOrder + 1] = id
    Palettes.Profiles[id] = { label = "Tropospheric " .. index, contexts = {
        day = "imported_tropo_day_" .. index, overcast = "imported_tropo_verycloudy_" .. index,
        dusk = "imported_tropo_dusk_" .. index, night = "imported_tropo_night_" .. (index <= 3 and 1 or 2) } }
end

for _, profile in ipairs({
    { id = "cloud_prelude", label = "Cloud prelude", contexts = {
        day = "imported_sky1", overcast = "imported_tropo_cloudy_1",
        dusk = "imported_prelude", night = "imported_moonlit" } },
    { id = "terrassee_horizons", label = "Terrassee horizons", contexts = {
        day = "imported_mr53", overcast = "imported_tropo_cloudy_2",
        dusk = "imported_terrassee", night = "imported_tropo_night_2" } },
    { id = "worldsend_horizons", label = "World's End horizons", contexts = {
        day = "imported_plainsky", overcast = "imported_tropo_cloudy_3",
        dusk = "imported_worldsend", night = "imported_tropo_night_1" } },
    { id = "neon_twilight", label = "Neon twilight (stylized)", contexts = {
        day = "imported_sky1", overcast = "imported_tropo_cloudy_4",
        dusk = "imported_waporvave", night = "cinematic_night" } },
    { id = "alien_embers", label = "Alien embers (stylized)", contexts = {
        day = "imported_mr53", overcast = "imported_tropo_cloudy_5",
        dusk = "imported_alienred", night = "imported_moonlit" } },
    { id = "cloudbound", label = "Cloudbound", contexts = {
        day = "imported_plainsky", overcast = "imported_tropo_cloudy_6",
        dusk = "imported_prelude", night = "imported_moonlit" } }
}) do
    Palettes.ProfileOrder[#Palettes.ProfileOrder + 1] = profile.id
    Palettes.Profiles[profile.id] = { label = profile.label, contexts = profile.contexts }
end

function Palettes:GetAvailability(id)
    if id == "default" then return true end
    local entry = self.Entries[id]
    if not entry then return false, "Unknown sky: " .. tostring(id) end
    if entry.mounted then
        for _, suffix in ipairs({ "ft", "bk", "lf", "rt", "up", "dn" }) do
            if not file.Exists("materials/" .. entry.mounted .. suffix .. ".vmt", "GAME") then
                return false, "Missing mounted sky face: " .. entry.mounted .. suffix
            end
        end
    end
    return true
end

function Palettes:GetProfile(id)
    return self.Profiles[id] or self.CustomStore.profiles[id]
end

function Palettes:ValidateCustomProfile(profile)
    if not istable(profile) or not isstring(profile.label) or #string.Trim(profile.label) == 0 or
        #profile.label > 60 or profile.label:find("[%c]") or not istable(profile.contexts) then
        return false, "Give the palette a name of 1-60 characters and choose all four atmosphere states."
    end
    for _, context in ipairs(self.ContextOrder) do
        local id = profile.contexts[context]
        if not isstring(id) or (id ~= "default" and not self.Entries[id]) then
            return false, "Choose an individual sky or the native map sky for " .. context .. "."
        end
    end
    for context in pairs(profile.contexts) do
        if not table.HasValue(self.ContextOrder, context) then return false, "Unknown palette context: " .. tostring(context) end
    end
    return true
end

function Palettes:ValidateCustomStore(store)
    if not istable(store) or store.schemaVersion ~= 1 or not isnumber(store.nextId) or
        store.nextId < 1 or store.nextId % 1 ~= 0 or not istable(store.profiles) then
        return false, "Invalid custom sky palette storage."
    end
    for id, profile in pairs(store.profiles) do
        local number = isstring(id) and tonumber(id:match("^custom_(%d+)$"))
        if not number or number < 1 or number >= store.nextId then return false, "Invalid custom palette id." end
        local ok, failure = self:ValidateCustomProfile(profile)
        if not ok then return false, failure end
    end
    return true
end

Palettes.CustomPath = "zombiesim/sky_custom_palettes.json"
Palettes.CustomStore = { schemaVersion = 1, nextId = 1, profiles = {} }
Palettes.CustomFailure = nil
function Palettes:LoadCustomProfiles()
    if not file.Exists(self.CustomPath, "DATA") then
        self.CustomStore = { schemaVersion = 1, nextId = 1, profiles = {} }
        self.CustomFailure = nil
        return true
    end
    local raw = file.Read(self.CustomPath, "DATA")
    local parsed = raw and util.JSONToTable(raw)
    local ok, failure = self:ValidateCustomStore(parsed)
    if not ok then
        self.CustomFailure = failure .. " Existing file preserved: data/" .. self.CustomPath
        ErrorNoHalt("[ZombieSim] " .. self.CustomFailure .. "\n")
        return false, self.CustomFailure
    end
    self.CustomStore, self.CustomFailure = parsed, nil
    return true
end

function Palettes:WriteCustomStore(store)
    if self.CustomFailure then return false, self.CustomFailure end
    local ok, failure = self:ValidateCustomStore(store)
    if not ok then return false, failure end
    local json = util.TableToJSON(store, true)
    if not json then return false, "Could not encode custom sky palettes." end
    file.CreateDir("zombiesim")
    local previous = file.Read(self.CustomPath, "DATA")
    if previous and (not file.Write(self.CustomPath .. ".backup.json", previous) or
        file.Read(self.CustomPath .. ".backup.json", "DATA") ~= previous) then
        return false, "Could not retain the previous custom sky palettes; save cancelled."
    end
    if not file.Write(self.CustomPath, json) or file.Read(self.CustomPath, "DATA") ~= json then
        if previous then
            if not file.Write(self.CustomPath, previous) or file.Read(self.CustomPath, "DATA") ~= previous then
                ErrorNoHalt("[ZombieSim] Failed to restore previous custom sky palette file.\n")
            end
        else
            file.Delete(self.CustomPath)
        end
        return false, "Could not save custom sky palettes; your active palette was not changed."
    end
    self.CustomStore = store
    return true
end

function Palettes:SaveCustomProfile(id, profile)
    local ok, failure = self:ValidateCustomProfile(profile)
    if not ok then return false, failure end
    for _, context in ipairs(self.ContextOrder) do
        ok, failure = self:GetAvailability(profile.contexts[context])
        if not ok then return false, failure end
        if profile.contexts[context] ~= "default" and self.Entries[profile.contexts[context]].mounted then
            local materials
            materials, failure = self:GetFaceMaterials(profile.contexts[context])
            if not materials then return false, failure end
        end
    end
    local store = table.Copy(self.CustomStore)
    if id and not store.profiles[id] then return false, "This custom palette no longer exists." end
    if not id then
        id = "custom_" .. store.nextId
        store.nextId = store.nextId + 1
    end
    store.profiles[id] = { label = string.Trim(profile.label), contexts = table.Copy(profile.contexts) }
    ok, failure = self:WriteCustomStore(store)
    if not ok then return false, failure end
    return true, id
end

function Palettes:DeleteCustomProfile(id)
    if not self.CustomStore.profiles[id] then return false, "This custom palette no longer exists." end
    local store = table.Copy(self.CustomStore)
    store.profiles[id] = nil
    local ok, failure = self:WriteCustomStore(store)
    if not ok then return false, failure end
    if GetConVar("zombiesim_sky_palette"):GetString() == id then self:Select("default") end
    return true
end

Palettes:LoadCustomProfiles()
