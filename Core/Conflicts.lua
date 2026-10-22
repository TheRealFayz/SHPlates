-------------------------------------------------------------------------------
-- SHPlates: Conflicts
-- pfUI ships its own nameplates. Two nameplate addons on the same plates fight
-- (double bars, stolen clicks), so while SHPlates is running, pfUI's nameplate
-- module is switched off for the session. Nothing is written to pfUI's
-- settings: disable SHPlates and pfUI's plates are back after a reload.
--
-- This mirrors pfUI's own logout teardown: its nameplate frame stops all
-- events and updates, and every overlay it already built is hidden for good.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Cf = {}
SHPlates.Conflicts = Cf

local function Noop() end

local function KillFrame(f)
	if not f then return end
	if f.UnregisterAllEvents then f:UnregisterAllEvents() end
	f:SetScript("OnEvent", nil)
	f:SetScript("OnUpdate", nil)
end

local function Enabled()
	return not (SHPlatesDB and SHPlatesDB.hidePfUIPlates == false)
end

-- Hide one pfUI overlay and stop it from ever showing again
function Cf.ReleasePlate(plate)
	local pf = plate and plate.nameplate
	if not pf or pf.shplatesReleased or not Enabled() then return end
	pf.shplatesReleased = true
	if pf.UnregisterAllEvents then pf:UnregisterAllEvents() end
	pf:SetScript("OnEvent", nil)
	pf:SetScript("OnUpdate", nil)
	pf:SetScript("OnShow", nil)
	pf:EnableMouse(false)
	pf:SetAlpha(0)
	pf:Hide()
	pf.Show = Noop   -- pfUI calls plate:Show() when its data changes
end

local announced = false
function Cf.KillPfUIPlates()
	if not Enabled() then return true end
	local core = getglobal("pfNameplates")
	if not core then return false end
	if core.shplatesKilled then return true end
	core.shplatesKilled = true

	KillFrame(core)
	KillFrame(core.castbarFrame)
	if core.mouselook then core.mouselook:SetScript("OnUpdate", nil) end

	-- overlays pfUI already built
	local children = { WorldFrame:GetChildren() }
	for i = 1, table.getn(children) do
		local frame = children[i]
		if frame.nameplate and frame.nameplate.original then Cf.ReleasePlate(frame) end
	end

	if not announced then
		announced = true
		C.print("pfUI's nameplates are switched off while SHPlates is running.")
	end
	return true
end

-- pfUI creates its nameplate module when pfUI loads, which can be before or
-- after SHPlates. Keep looking until it exists (or clearly never will).
local watcher = CreateFrame("Frame")
local active, timer, giveUpAt = false, 0, nil
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
	if SHPlates.disabled then return end
	if event == "ADDON_LOADED" then
		if arg1 == SHPlates.ADDON or arg1 == "pfUI" then active = true end
	elseif event == "PLAYER_ENTERING_WORLD" then
		active = true
		giveUpAt = GetTime() + 30
	end
	if active and Cf.KillPfUIPlates() then active = false end
end)
watcher:SetScript("OnUpdate", function()
	if not active or SHPlates.disabled then return end
	timer = timer + (arg1 or 0)
	if timer < .25 then return end
	timer = 0
	if Cf.KillPfUIPlates() then active = false; return end
	local pfOff = pfUI_config and pfUI_config.disabled and pfUI_config.disabled.nameplates == "1"
	if giveUpAt and GetTime() > giveUpAt and (pfOff or not (IsAddOnLoaded and IsAddOnLoaded("pfUI"))) then
		active = false
	end
end)
