return function(contract, createMap, createTransfer)
    local suite = ZM_TestHarness.NewSuite()
    local function fixture()
        local state = { files = {}, values = {}, serial = 0, fail = {} }
        local function clone(value)
            if type(value) ~= "table" then return value end
            local result = {}
            for key, entry in pairs(value) do result[key] = clone(entry) end
            return result
        end
        local api = {
            SysTime = function() return 1 end, RealTime = function() return 2 end,
            file = {
                Exists = function(path, realm) assert(realm == "DATA"); return state.files[path] ~= nil end,
                CreateDir = function() end,
                Write = function(path, text)
                    if state.fail.write then return false end
                    state.files[path] = text
                    return true
                end,
                Read = function(path, realm) assert(realm == "DATA"); return state.files[path] end,
                Delete = function(path)
                    if state.fail.delete then return false end
                    state.files[path] = nil
                    return true
                end
            },
            util = {
                CRC = function() return "123" end,
                TableToJSON = function(value)
                    state.serial = state.serial + 1
                    local key = "json" .. state.serial
                    state.values[key] = clone(value)
                    if state.fail.roundtrip then state.values[key].tabs[1].view.cameraYaw = 0 end
                    return key
                end,
                JSONToTable = function(value) return clone(state.values[value]) end
            }
        }
        local tabs = { {
            number = 1, openedId = "saved", dirty = true, revision = 4, mode = "move",
            selected = nil,
            document = { schemaVersion = 1, id = "saved", name = "", description = "", tags = {},
                props = {}, lights = {}, particles = {}, guards = {} },
            view = { cameraYaw = 45, cameraPitch = 55, cameraDistance = 1000, panX = 0, panY = 0,
                positionSnap = 16, rotationSnap = 15, snapEnabled = true, gridSpacing = 64,
                showGrid = true, showCompass = true, previewDark = false, referenceOffset = 0, prefabOffset = 25 }
        } }
        return state, createTransfer(api, createMap(contract)), tabs
    end

    suite:Add("map transfers preserve and restore unsaved tab data", function(check)
        local state, transfer, tabs = fixture()
        local saved, problem = transfer:Save("gm_construct", tabs, 1)
        check(saved and saved.token == "switch_123" and saved.openIds[1] == "saved" and transfer:Exists(),
            "a verified local draft is saved before switching: " .. tostring(problem))
        local restored, encoded = transfer:Read(saved.token, { "saved" })
        check(restored and restored.tabs[1].dirty and restored.tabs[1].document.name == ""
            and restored.tabs[1].view.prefabOffset == 25 and encoded == saved.encoded,
            "incomplete metadata and per-tab view state survive recovery")
        check(not transfer:Read("wrong", { "saved" }) and not transfer:Read(saved.token, {})
            and transfer:Exists(), "token and server authorization mismatches preserve the draft")
        check(not transfer:Remove("different") and transfer:Exists(), "changed files are never deleted")
        check(transfer:Remove(saved.encoded) and not transfer:Exists(), "matching restored drafts are removed explicitly")
        check(tabs[1].document.name == "" and tabs[1].dirty, "the original editor tabs are not mutated")
        saved = transfer:Save("zz_preview_fixture", tabs, 1, 302)
        local cellDraft = saved and transfer:Read(saved.token, { "saved" })
        check(cellDraft and cellDraft.cellId == 302 and transfer:Remove(saved.encoded),
            "cell identity accompanies a generated-map draft without changing its tabs")
    end)

    suite:Add("map transfer failures never overwrite an existing draft", function(check)
        local state, transfer, tabs = fixture()
        state.fail.roundtrip = true
        local saved, problem = transfer:Save("gm_construct", tabs, 1)
        check(not saved and type(problem) == "string" and not transfer:Exists(),
            "lossy JSON round trips fail before writing")
        state.fail.roundtrip, state.fail.write = false, true
        saved, problem = transfer:Save("gm_construct", tabs, 1)
        check(not saved and type(problem) == "string", "write failures are reported")
        state.fail.write = false
        saved = transfer:Save("gm_construct", tabs, 1)
        check(saved and not transfer:Save("gm_flatgrass", tabs, 1), "an existing recovery draft is never overwritten")
        state.fail.delete = true
        check(not transfer:Remove(saved.encoded) and transfer:Exists(), "failed cleanup retains the original draft")
    end)
    return suite
end
