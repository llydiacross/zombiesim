ZM_ThirdPartyLicenses = ZM_ThirdPartyLicenses or {}
local Licenses = ZM_ThirdPartyLicenses
local colours = ZM_DermaSkin.Palette

function Licenses:Load()
    local records, errors = {}, {}
    local function fail(message)
        errors[#errors + 1] = message
        ErrorNoHalt("[ZombieSim] Third-party notices: " .. message .. "\n")
    end
    local function read(path)
        if not isstring(path) then fail("Notice path is not a string") return nil end
        path = string.Replace(path, "\\", "/")
        if not string.match(path, "^data_static/[%w_/%-%.]+$") or string.find(path, "..", 1, true) then
            fail("Invalid notice path: " .. path)
            return nil
        end
        local text = file.Read(path, "GAME")
        if not text then fail("Missing notice: " .. path) end
        return text
    end
    local function catalog(path)
        local text = read(path)
        if not text then return nil end
        local data = util.JSONToTable(text)
        if not istable(data) or data.schemaVersion ~= 1 then
            fail("Invalid notice catalogue: " .. path)
            return nil
        end
        return data
    end
    local sky = catalog("data_static/sky_catalogue.json")
    if sky then
        if not istable(sky.entries) then
            fail("Sky catalogue has no notice entries")
        else
            for _, entry in ipairs(sky.entries) do
                if not istable(entry) then fail("Invalid sky notice entry") continue end
                local text = isstring(entry.licenceFile) and read(entry.licenceFile) or nil
                if not isstring(entry.licenceFile) then fail("Sky notice has no original file: " .. tostring(entry.id)) end
                records[#records + 1] = {
                    title = "Sky: " .. tostring(entry.label or entry.id), credit = entry.credit and tostring(entry.credit),
                    permission = entry.permission and tostring(entry.permission), text = text, source = entry.licenceFile
                }
            end
        end
    end
    local assets = catalog("data_static/imported_assets.json")
    if assets then
        if not istable(assets.sources) then
            fail("Imported asset catalogue has no source records")
        else
            for _, source in ipairs(assets.sources) do
                if not istable(source) then fail("Invalid imported asset source") continue end
                local texts = {}
                if not istable(source.creditFiles) then fail("Missing credit-file list: " .. tostring(source.package)) end
                for _, path in ipairs(istable(source.creditFiles) and source.creditFiles or {}) do
                    local text = read(path)
                    if text then texts[#texts + 1] = text end
                end
                records[#records + 1] = {
                    title = tostring(source.title or source.package), source = source.archive,
                    permission = source.permission and tostring(source.permission), text = #texts > 0 and table.concat(texts, "\n\n") or
                        "No license document was supplied. The creator-permission record above is not original license text."
                }
            end
        end
    end
    table.sort(records, function(a, b) return string.lower(a.title) < string.lower(b.title) end)
    return records, errors
end

function Licenses:Open(parent)
    if IsValid(self.Frame) then self.Frame:MakePopup() return self.Frame end
    local records, errors = self:Load()
    local frame = vgui.Create("DFrame")
    self.Frame = frame
    frame:SetSkin("ZombieSim")
    frame:SetTitle("THIRD PARTY LICENSES")
    frame:SetSize(math.min(860, ScrW() - 32), math.min(760, ScrH() - 32))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame:MakePopup()
    if ZM_UI then ZM_UI:RegisterTransient(frame) end
    frame.OnRemove = function()
        if self.Frame == frame then self.Frame = nil end
        if ZM_UI then ZM_UI:UnregisterTransient(frame) end
    end
    frame.OnClose = function()
        if not IsValid(parent) then return end
        local window = parent
        while IsValid(window:GetParent()) and window:GetParent() ~= vgui.GetWorldPanel() do
            window = window:GetParent()
        end
        window:MakePopup()
    end
    frame.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then frame:Close() end
    end
    frame.Think = function()
        if parent ~= nil and not IsValid(parent) then frame:Remove() end
    end
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(4, 4, 4, 4)
    frame.ZM_LicenseScroll = scroll
    frame.ZM_LicenseRecords = records
    frame.ZM_LicenseErrors = errors
    ZM_Changelog:Paragraph(scroll, "Original shipped notices and attribution, with recorded creator permissions where no license document was supplied.", colours.muted, 12)
    ZM_Changelog:Paragraph(scroll, "Mounted Garry's Mod and Counter-Strike: Source assets are referenced in place, not copied by this notice browser. Native-game rights remain with their owners.", colours.muted, 12)
    for _, message in ipairs(errors) do ZM_Changelog:Paragraph(scroll, message, colours.redBright, 12) end
    for _, entry in ipairs(records) do
        local heading = ZM_Changelog:Paragraph(scroll, entry.title, colours.redBright, 12)
        heading:SetFont("ZM_ToolsHeading")
        heading:DockMargin(12, 18, 12, 6)
        if entry.credit then ZM_Changelog:Paragraph(scroll, "Credit: " .. entry.credit, colours.muted, 12) end
        if entry.source then ZM_Changelog:Paragraph(scroll, "Source: " .. tostring(entry.source), colours.muted, 12) end
        if entry.permission then ZM_Changelog:Paragraph(scroll, "Permission record: " .. entry.permission, colours.muted, 12) end
        if entry.text then ZM_Changelog:Paragraph(scroll, entry.text, colours.text, 12) end
    end
    return frame
end
