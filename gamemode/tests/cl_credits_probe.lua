return function(menu, scene, music)
    local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    end

    local function vector(value)
        if not isvector(value) or not finite(value.x) or not finite(value.y) or not finite(value.z) then return nil end
        return { x = value.x, y = value.y, z = value.z }
    end

    local function angle(value)
        if not isangle(value) or not finite(value.p) or not finite(value.y) or not finite(value.r) then return nil end
        return { p = value.p, y = value.y, r = value.r }
    end

    local function fail(report, entry, reason)
        entry.errors[#entry.errors + 1] = reason
        report.errors[#report.errors + 1] = "dancer " .. entry.index .. ": " .. reason
    end

    local function inspectDancer(report, index)
        local names, ids = menu.DancerNames or {}, menu.DancerIds or {}
        local entry = { index = index, name = names[index] or false, id = ids[index] or false, ok = false, errors = {} }
        report.dancers[#report.dancers + 1] = entry
        if not entry.name or not entry.id or entry.id <= 0 then
            fail(report, entry, "missing dancer name or entity ID")
            return
        end
        local entity = scene:GetDancer(index)
        if not IsValid(entity) then
            fail(report, entry, "dancer entity is not available on the client")
            return
        end
        entry.model, entry.class = entity:GetModel(), entity:GetClass()
        entity:SetupBones()
        local head = entity:LookupBone("ValveBiped.Bip01_Head1")
        local headAngles
        if head == nil then
            fail(report, entry, "head bone is missing")
        else
            local parent = entity:GetBoneParent(head)
            entry.head = {
                index = head, parent = parent, physicsBone = entity:TranslateBoneToPhysBone(head)
            }
            if parent >= 0 then entry.head.parentName = entity:GetBoneName(parent) end
            local matrix = entity:GetBoneMatrix(head)
            if matrix then
                headAngles = matrix:GetAngles()
                entry.head.position, entry.head.angles = vector(matrix:GetTranslation()), angle(headAngles)
            end
            if not entry.head.position or not entry.head.angles then
                fail(report, entry, "head matrix is unavailable or non-finite")
                headAngles = nil
            end
        end

        local eyeId = entity:LookupAttachment("eyes")
        local eye = eyeId and eyeId > 0 and entity:GetAttachment(eyeId)
        if not eye then
            fail(report, entry, "eyes attachment is unavailable")
        else
            entry.eyes = { index = eyeId, bone = eye.Bone, position = vector(eye.Pos), angles = angle(eye.Ang) }
            if not entry.eyes.position or not entry.eyes.angles then
                fail(report, entry, "eyes attachment is non-finite")
            elseif headAngles then
                local forward = eye.Ang:Forward()
                local axis = {
                    forward = forward:Dot(headAngles:Forward()),
                    right = forward:Dot(headAngles:Right()),
                    up = forward:Dot(headAngles:Up())
                }
                if finite(axis.forward) and finite(axis.right) and finite(axis.up) then
                    entry.eyes.forwardInHead = axis
                else
                    fail(report, entry, "eyes/head basis is non-finite")
                end
            end
        end
        entry.ok = #entry.errors == 0
    end

    concommand.Remove("zombiesim_dev_credits_status")
    concommand.Add("zombiesim_dev_credits_status", function(_, _, arguments)
        local requestId, player = arguments[1], LocalPlayer()
        if game.GetMap() ~= "zn_preview_start" or menu.Profile ~= "preview"
            or not IsValid(player) or not player:IsAdmin()
            or type(requestId) ~= "string" or #requestId > 32 or not string.match(requestId, "^%d+$") then
            ErrorNoHalt("[ZombieSim] Credits status requires the preview launcher admin and a numeric request ID.\n")
            return
        end

        local now = RealTime()
        local report = { requestId = requestId, map = game.GetMap(), profile = menu.Profile,
            creditsActive = menu.Active == true and menu.Credits == true, capturedAt = now,
            phase = scene.Phase or false, camera = false, cameraAge = false, dancers = {}, errors = {} }
        local session = music.CreditsMusic
        report.music = { phase = session and session.phase or "inactive", path = session and session.path or false,
            channelValid = session and IsValid(session.channel) or false }
        if report.music.channelValid then
            report.music.state = session.channel:GetState()
            report.music.time = session.channel:GetTime()
            report.music.length = session.channel:GetLength()
        end
        if not report.creditsActive then
            report.errors[#report.errors + 1] = "credits are not active"
        else
            local view = scene.LastCreditsView
            if view and vector(view.origin) and angle(view.angles) and finite(scene.LastCreditsViewAt) then
                report.camera = { origin = vector(view.origin), angles = angle(view.angles) }
                report.cameraAge = now - scene.LastCreditsViewAt
                if report.cameraAge < 0 or report.cameraAge > 1 then
                    report.errors[#report.errors + 1] = "last credits camera view is stale"
                end
            else
                report.errors[#report.errors + 1] = "credits camera view is unavailable or non-finite"
            end
            for index = 1, 4 do inspectDancer(report, index) end
        end
        report.ok = #report.errors == 0
        file.CreateDir("zombiesim")
        local encoded = util.TableToJSON(report, true)
        if type(encoded) ~= "string" or not file.Write("zombiesim/credits-status.json", encoded) then
            ErrorNoHalt("[ZombieSim] Could not write the credits status report.\n")
            return
        end
        print(string.format("[ZombieSim] Credits status %s: %d dancers, %d errors.",
            requestId, #report.dancers, #report.errors))
        for _, reason in ipairs(report.errors) do print("[ZombieSim] Credits status: " .. reason) end
    end)
end
