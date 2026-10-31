return function(categoryFor)
    local state = { latest = nil, pending = nil }
    local serialRange = 4294967294

    local function newer(serial, previous)
        if not previous then return true end
        local distance = (serial - previous) % serialRange
        return distance > 0 and distance <= serialRange / 2
    end

    local function whole(value, minimum, maximum)
        return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
    end

    function state:Push(packet)
        if type(packet) ~= "table" or not whole(packet.serial, 1, serialRange) then
            return "error", "Invalid calling-card response serial."
        end
        local serial = packet.serial
        local current = self.pending
        if not current or serial ~= current.serial then
            if not newer(serial, current and current.serial or self.latest) then return "ignored" end
            current = {
                serial = serial, total = packet.total, ok = packet.ok, message = packet.message,
                requestId = packet.requestId, background = packet.background, detail = packet.detail, parts = {}, received = 0
            }
            self.pending = current
        end
        local function reject(message)
            self.latest, self.pending = serial, nil
            return "error", message
        end
        if not whole(packet.total, 1, 65535) or not whole(packet.part, 1, packet.total)
            or type(packet.ok) ~= "boolean" or type(packet.message) ~= "string"
            or type(packet.requestId) ~= "string" or #packet.requestId > 40
            or type(packet.background) ~= "string" or type(packet.detail) ~= "string"
            or type(packet.ids) ~= "table" or #packet.ids > 32 then
            return reject("Invalid calling-card response.")
        end
        if current.total ~= packet.total or current.ok ~= packet.ok or current.message ~= packet.message
            or current.requestId ~= packet.requestId
            or current.background ~= packet.background or current.detail ~= packet.detail then
            return reject("Calling-card response parts do not match.")
        end
        if current.parts[packet.part] then return "ignored" end
        for _, id in ipairs(packet.ids) do
            if not categoryFor(id) then return reject("Calling-card response contains an invalid ID.") end
        end
        current.parts[packet.part] = packet.ids
        current.received = current.received + 1
        if current.received ~= current.total then return "pending" end

        local owned = {}
        for part = 1, current.total do
            for _, id in ipairs(current.parts[part]) do
                if owned[id] then return reject("Calling-card response repeats an ID.") end
                owned[id] = true
            end
        end
        local hasSelection = current.background ~= "" or current.detail ~= ""
        if hasSelection then
            if categoryFor(current.background) ~= "background" or categoryFor(current.detail) ~= "detail"
                or not owned.background_default or not owned.detail_default then
                return reject("Calling-card response contains an invalid selection or ownership list.")
            end
        elseif current.ok or next(owned) then
            return reject("Calling-card response is missing its selection.")
        end
        self.latest, self.pending = serial, nil
        return "complete", {
            available = hasSelection, ok = current.ok, message = current.message,
            requestId = current.requestId,
            selection = hasSelection and { background = current.background, detail = current.detail } or nil,
            owned = owned
        }
    end

    return state
end
