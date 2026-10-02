// Client side of AFK menus. Counted menus open only when the server finishes its countdown; the client reports
// when the last AFK menu closes and draws the countdown, AFK and exit-grace state. The server owns protection.
ZM_AFK = ZM_AFK or {}
local AFK = ZM_AFK

AFK.Actions = { begin = 1, immediate = 2, cancel = 3, leave = 4, hold = 5 }
AFK.HeartbeatSeconds = 2
AFK.State = AFK.State or { afk = false, countdownUntil = 0, countdownMenu = "", graceUntil = 0 }
AFK.MenuLabels = { inventory = "INVENTORY", scoreboard = "SCOREBOARD", options = "OPTIONS", cheats = "CHEATS" }

surface.CreateFont("ZM_AFKTitle", { font = "Trebuchet MS", size = 22, weight = 900, antialias = true })
surface.CreateFont("ZM_AFKDetail", { font = "Trebuchet MS", size = 15, weight = 700, antialias = true })

local openers = {
	inventory = function() ZM_Inventory:Open() end,
	scoreboard = function() ZM_Scoreboard:Open() end,
	options = function() ZM_Options:Open() end,
	cheats = function() ZM_PreviewCheats:Open() end
}

local menuOwners = {
	function() return ZM_Inventory end,
	function() return ZM_Scoreboard end,
	function() return ZM_Options end,
	function() return ZM_PreviewCheats end
}

function AFK:Request(action, menu)
	net.Start("ZM.AFKRequest")
		net.WriteUInt(action, 3)
		net.WriteString(menu or "")
	net.SendToServer()
end

function AFK:IsAnyMenuOpen()
	for _, owner in ipairs(menuOwners) do
		local menuOwner = owner()
		if menuOwner and IsValid(menuOwner.Frame) then
			return true
		end
	end
	return false
end

function AFK:IsCountingDown()
	return self.State.countdownMenu ~= ""
end

function AFK:IsMenu(menu)
	return openers[menu] ~= nil
end

// Opens an AFK menu: cheats immediately, others after the server countdown unless already AFK.
function AFK:OpenMenu(menu)
	local opener = openers[menu]
	if not opener then
		return false
	end
	if menu == "cheats" then
		opener()
		self:Request(self.Actions.immediate, menu)
		return true
	end
	if self.State.afk then
		opener()
		return true
	end
	if self:IsCountingDown() then
		return false
	end
	self.State.countdownMenu = menu
	self.State.countdownUntil = CurTime() + 3
	self:Request(self.Actions.begin, menu)
	return true
end

// Pressing the menu key during a countdown cancels it. Returns true when the key press was consumed.
function AFK:CancelFromInput()
	if not self:IsCountingDown() then
		return false
	end
	self.State.countdownMenu = ""
	self.State.countdownUntil = 0
	self.Notice = { text = "CANCELLED", at = RealTime() }
	self:Request(self.Actions.cancel)
	return true
end

net.Receive("ZM.AFKState", function()
	local state = AFK.State
	state.afk = net.ReadBool()
	state.countdownUntil = net.ReadFloat()
	state.countdownMenu = net.ReadString()
	state.graceUntil = net.ReadFloat()
	local openMenu = net.ReadString()
	local message = net.ReadString()
	AFK.LeaveSent = false
	if message ~= "" then
		AFK.Notice = { text = string.upper(message), at = RealTime() }
		surface.PlaySound("buttons/button10.wav")
	end
	if openMenu ~= "" and openers[openMenu] then
		openers[openMenu]()
	end
end)

local nextCheckAt = 0
hook.Add("Think", "ZM.AFK.MenuWatch", function()
	if RealTime() < nextCheckAt then return end
	nextCheckAt = RealTime() + 0.1
	if not AFK.State.afk then
		return
	end
	if AFK:IsAnyMenuOpen() then
		if RealTime() >= (AFK.NextHeartbeatAt or 0) then
			AFK.NextHeartbeatAt = RealTime() + AFK.HeartbeatSeconds
			AFK:Request(AFK.Actions.hold)
		end
	elseif not AFK.LeaveSent then
		AFK.LeaveSent = true
		AFK:Request(AFK.Actions.leave)
	end
end)

local function drawBanner(centerX, y, title, detail, accent, progress)
	local palette = ZM_DermaSkin.Palette
	surface.SetFont("ZM_AFKTitle")
	local titleWidth = surface.GetTextSize(title)
	surface.SetFont("ZM_AFKDetail")
	local detailWidth = detail and surface.GetTextSize(detail) or 0
	local width = math.max(titleWidth, detailWidth) + 40
	local height = detail and 54 or 34
	local x = math.floor(centerX - width * 0.5)
	surface.SetDrawColor(palette.black.r, palette.black.g, palette.black.b, 215)
	surface.DrawRect(x, y, width, height)
	surface.SetDrawColor(accent)
	surface.DrawRect(x, y, 3, height)
	if progress then
		surface.DrawRect(x, y + height - 3, math.floor(width * math.Clamp(progress, 0, 1)), 3)
	end
	draw.SimpleText(title, "ZM_AFKTitle", centerX, y + 6, palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	if detail then
		draw.SimpleText(detail, "ZM_AFKDetail", centerX, y + 31, palette.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

// Drawn after VGUI so the AFK badge stays visible above the open menus.
hook.Add("PostRenderVGUI", "ZM.AFK.Status", function()
	if gui.IsGameUIVisible() or (ZM_LauncherMenu and ZM_LauncherMenu.Active) or not ZM_DermaSkin then return end
	local palette = ZM_DermaSkin.Palette
	local state = AFK.State
	local centerX = ScrW() * 0.5
	local y = math.floor(ScrH() * 0.04)
	local now = CurTime()
	if state.afk then
		drawBanner(centerX, y, "AFK", "Zombies ignore you while this menu is open", palette.red)
	elseif AFK:IsCountingDown() then
		local remaining = math.max(0, state.countdownUntil - now)
		drawBanner(centerX, math.floor(ScrH() * 0.62), string.format("OPENING %s  %.1f", AFK.MenuLabels[state.countdownMenu] or "MENU", remaining),
			"Press TAB to cancel. Taking damage interrupts.", palette.redBright, 1 - remaining / 3)
	elseif state.graceUntil > now then
		drawBanner(centerX, y, string.format("PROTECTED  %.1f", state.graceUntil - now), "Firing ends protection", palette.red)
	elseif AFK.Notice and RealTime() - AFK.Notice.at < 1.5 then
		drawBanner(centerX, math.floor(ScrH() * 0.62), AFK.Notice.text, nil, palette.redBright)
	end
end)
