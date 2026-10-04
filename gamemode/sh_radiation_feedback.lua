ZM_RadiationFeedback = ZM_RadiationFeedback or {}
local Feedback = ZM_RadiationFeedback

Feedback.Radius = 600
Feedback.QuietThreshold = 0.08
Feedback.ExtremeThresholdSv = 15

function Feedback.Proximity(distance, intensity)
    local falloff = math.Clamp(1 - distance / Feedback.Radius, 0, 1)
    return math.Clamp(intensity, 0, 1) * falloff * falloff
end

function Feedback.SensoryIntensity(cell, proximity)
    local intensity = math.max(math.Clamp(cell, 0, 1), math.Clamp(proximity, 0, 1))
    return math.Clamp((intensity - Feedback.QuietThreshold) / (1 - Feedback.QuietThreshold), 0, 1)
end

function Feedback.ClickInterval(intensity)
    return Lerp(math.Clamp(intensity, 0, 1), 1.6, 0.125)
end

function Feedback.ClickDelay(intensity, randomSample)
    local sample = math.Clamp(randomSample, 0.0001, 0.9999)
    return math.Clamp(-math.log(sample) * Feedback.ClickInterval(intensity), 0.06, 4)
end

function Feedback.AudioGain(intensity)
    return math.Clamp(intensity, 0, 1) ^ 0.5
end

function Feedback.WarningIntensity(cell, proximity)
    local combined = Feedback.DisplaySv(cell, proximity) / 20
    return math.Clamp((combined - Feedback.QuietThreshold) / (1 - Feedback.QuietThreshold), 0, 1)
end

function Feedback.CornerIntensity(cell, proximity, protected)
    return protected and 0 or Feedback.WarningIntensity(cell, proximity)
end

function Feedback.SymbolFrequency(intensity)
    return Lerp(math.Clamp(intensity, 0, 1), 0.2, 1.5)
end

function Feedback.CornerMaskAlpha(x, y)
    local radiusSquared = x * x + y * y
    if radiusSquared >= 1 then return 0 end
    local variation = 0.92 + 0.08 * math.sin(x * 9) * math.sin(y * 11)
    return (1 - radiusSquared) ^ 3 * variation
end

function Feedback.DisplaySv(cell, proximity)
    return (math.Clamp(cell, 0, 1) + math.Clamp(proximity, 0, 1)) * 10
end

function Feedback.ExtremeSeverity(cell, proximity, protected)
    if protected then return 0 end
    return math.Clamp((Feedback.DisplaySv(cell, proximity) - Feedback.ExtremeThresholdSv) / 5, 0, 1)
end

function Feedback.DamagePolicy(cell, proximity, protected)
    if protected then return 0, 0, false end
    if Feedback.ExtremeSeverity(cell, proximity, false) > 0 then return 1, 2, true end
    if cell <= 0 then return 0, 0, false end
    return cell >= 0.75 and 2 or 1, cell >= 0.75 and 60 or 120, false
end
