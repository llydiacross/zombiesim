local Gizmo = {}

function Gizmo.DistanceToSegment(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 then return math.huge end
    local fraction = math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / lengthSquared))
    local offsetX, offsetY = x - (ax + fraction * dx), y - (ay + fraction * dy)
    return math.sqrt(offsetX * offsetX + offsetY * offsetY)
end

function Gizmo.AxisDelta(mouseX, mouseY, axisX, axisY, worldLength)
    local lengthSquared = axisX * axisX + axisY * axisY
    if lengthSquared < 1 then return nil end
    return (mouseX * axisX + mouseY * axisY) * worldLength / lengthSquared
end

function Gizmo.Snap(value, step)
    if step <= 0 then return value end
    local magnitude = math.floor(math.abs(value) / step + 0.5) * step
    return value < 0 and -magnitude or magnitude
end

function Gizmo.RingAngle(first, second)
    if type(first) ~= "number" or type(second) ~= "number" or first ~= first or second ~= second
        or math.abs(first) == math.huge or math.abs(second) == math.huge
        or first * first + second * second < 1 then return nil end
    return math.deg(math.atan2(second, first))
end

function Gizmo.AngleDelta(previous, current)
    return (current - previous + 180) % 360 - 180
end

return Gizmo
