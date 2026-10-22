-------------------------------------------------------------------------------
-- SHPlates: Guard
-- GudaPlates and SHPlates both take over the same nameplates, so they can't
-- run together. When GudaPlates is active, SHPlates stays switched off (every
-- module checks SHPlates.disabled) and a warning sits across the middle of
-- the screen until GudaPlates is disabled and the UI is reloaded.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local CONFLICT = "GudaPlates"

local banner
local function BuildBanner()
	if banner then return end
	banner = CreateFrame("Frame", "SHPlatesConflictWarning", UIParent)
	banner:SetFrameStrata("FULLSCREEN_DIALOG")
	banner:SetPoint("LEFT", UIParent, "LEFT", 0, 60)
	banner:SetPoint("RIGHT", UIParent, "RIGHT", 0, 60)
	banner:SetHeight(110)
	banner:EnableMouse(true)

	local bg = banner:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(banner)
	bg:SetTexture(0, 0, 0, .8)
	local top = banner:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT", banner, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", banner, "TOPRIGHT", 0, 0)
	top:SetHeight(2)
	top:SetTexture(.8, .1, .1, 1)
	local bottom = banner:CreateTexture(nil, "BORDER")
	bottom:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(2)
	bottom:SetTexture(.8, .1, .1, 1)

	local title = banner:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOP", banner, "TOP", 0, -14)
	title:SetTextColor(1, .2, .2)
	title:SetText("SHPlates and GudaPlates can't both be active")

	local body = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	body:SetPoint("TOP", title, "BOTTOM", 0, -8)
	body:SetText("SHPlates is disabled until GudaPlates is disabled and you reload your UI.")

	local disable = CreateFrame("Button", "SHPlatesConflictDisable", banner, "UIPanelButtonTemplate")
	disable:SetWidth(220); disable:SetHeight(24)
	disable:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", -6, 12)
	disable:SetText("Disable GudaPlates and Reload")
	disable:SetScript("OnClick", function()
		DisableAddOn(CONFLICT)
		ReloadUI()
	end)

	local dismiss = CreateFrame("Button", "SHPlatesConflictDismiss", banner, "UIPanelButtonTemplate")
	dismiss:SetWidth(120); dismiss:SetHeight(24)
	dismiss:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 6, 12)
	dismiss:SetText("Dismiss")
	dismiss:SetScript("OnClick", function() banner:Hide() end)
end

function SHPlates.ShowConflictWarning()
	BuildBanner()
	banner:Show()
end

local warnedInChat = false
local function Warn()
	SHPlates.ShowConflictWarning()
	if not warnedInChat then
		warnedInChat = true
		C.print("|cffff4040disabled:|r GudaPlates is active. Disable GudaPlates and reload your UI to use SHPlates.")
	end
end

-- SHPlates was already running when GudaPlates showed up (load-on-demand,
-- or a renamed folder that loads later): stop drawing plates right away.
local function Shutdown()
	SHPlates.disabled = true
	local handler = getglobal("SHPlatesPlateHandler")
	if handler then handler:SetScript("OnUpdate", nil) end
	if SHPlates.AllNameplates then
		for plate in pairs(SHPlates.AllNameplates) do
			if plate.extended then plate.extended:Hide() end
		end
	end
end

local guard = CreateFrame("Frame")
guard:RegisterEvent("ADDON_LOADED")
guard:RegisterEvent("PLAYER_LOGIN")
guard:RegisterEvent("PLAYER_ENTERING_WORLD")
guard:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 == CONFLICT then
			local wasRunning = not SHPlates.disabled
			Shutdown()
			if wasRunning then Warn() end
		end
	elseif event == "PLAYER_LOGIN" then
		if IsAddOnLoaded(CONFLICT) then SHPlates.disabled = true end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if SHPlates.disabled then Warn() end
	end
end)

-- /shp brings the warning back instead of opening settings
local slash = SlashCmdList["SHPLATES"]
SlashCmdList["SHPLATES"] = function(msg)
	if SHPlates.disabled then
		warnedInChat = false
		Warn()
		return
	end
	slash(msg)
end
