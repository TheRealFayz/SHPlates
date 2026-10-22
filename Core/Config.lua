-------------------------------------------------------------------------------
-- SHPlates: Settings, theme loading, role switching, options window, slash
--
-- Like Tidy Plates' primary/secondary spec themes, settings are saved PER
-- TALENT BUILD: OctoWoW/Turtle swap talents server-side and there is no
-- 3.3.5-style talent group API, so the build itself (points per tree) is
-- the key. Switching specs switches theme and mode automatically.
-- Mode can also be "Auto", which follows stance/form.
-- 1.12 has no Interface Options panel, so options live in /shplates.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local copytable = SHPlatesUtility.copyTable
local mergetable = SHPlatesUtility.mergeTable
local applysaved = SHPlatesUtility.applySaved

local DEFAULTS = {
	theme = "Neon",        -- default theme for talent builds not configured yet
	specs = {},            -- talent signature -> { theme = "Neon", role = "AUTO"|"Tank"|"DPS" }
	autohide = false,
	overlap = false,
	hidePfUIPlates = true,
	showFriendly = true,
	showCritters = false,
	clickThrough = false,
	classColorEnemies = true,
	classColorFriends = false,
	noClassColorPvP = false,
	tappedColorOn = true,
	tappedColor = { r = .5, g = .5, b = .5 },
	stunColorOn = true,
	stunColor = { r = .376, g = .027, b = .431 },
	fontFace = 1,
	fontSizeOffset = 0,
	learnFromGroup = true,
	announceLearned = true,
	tankNames = {},
	notes = {},
	themevars = {},
}

SHPlates.DEFAULTS = DEFAULTS  -- Share.lua checks imports against these

local activeRole = "DPS"
local lastSpecApplied
local activeThemeName = nil
local RESERVED = { vars = true, optionsSchema = true }

-------------------------------------------------------------------------------
-- Theme loading
-------------------------------------------------------------------------------
local function LoadTheme(name)
	local theme = SHPlatesThemeList[name]
	if type(theme) ~= "table" then
		SHPlates:ActivateTheme(SHPlates.defaultTheme)
		activeThemeName = nil
		return
	end
	if type(theme.SetStyle) == "function" then
		for stylename, s in pairs(theme) do
			if type(s) == "table" and not RESERVED[stylename] then
				theme[stylename] = mergetable(SHPlates.defaultTheme, s)
			end
		end
	else
		for propertyname, oldvalue in pairs(SHPlates.defaultTheme) do
			local newvalue = theme[propertyname]
			if type(newvalue) == "table" then theme[propertyname] = mergetable(oldvalue, newvalue)
			else theme[propertyname] = copytable(oldvalue) end
		end
	end
	if theme.OnApplyVars then theme.OnApplyVars(theme) end
	SHPlates.ApplyFontOverrides(theme)
	SHPlates:ActivateTheme(theme)
	activeThemeName = name
end

-------------------------------------------------------------------------------
-- Font override (General page): face + size offset on top of the theme's own
-------------------------------------------------------------------------------
SHPlates.FONTS = {
	{ "Theme default", nil },
	{ "Liberation Sans", SHPlates.MEDIA .. "LiberationSans-Regular.ttf" },
	{ "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
	{ "Arial Narrow", "Fonts\\ARIALN.TTF" },
	{ "Skurri", "Fonts\\skurri.ttf" },
	{ "Morpheus", "Fonts\\MORPHEUS.ttf" },
}
local FONT_KEYS = { "name", "level", "specialText", "specialText2" }

function SHPlates.ApplyFontOverrides(theme)
	if not SHPlatesDB then return end
	local face = SHPlates.FONTS[SHPlatesDB.fontFace or 1]
	local offset = SHPlatesDB.fontSizeOffset or 0
	local styles = {}
	if type(theme.SetStyle) == "function" then
		for k, v in pairs(theme) do if type(v) == "table" and v.name and v.healthbar then table.insert(styles, v) end end
	else styles[1] = theme end
	for i = 1, table.getn(styles) do
		local st = styles[i]
		-- remember the theme's own values the first time, so offsets don't stack
		if not st._fontBase then
			st._fontBase = {}
			for j = 1, table.getn(FONT_KEYS) do
				local f = st[FONT_KEYS[j]]
				if f then st._fontBase[FONT_KEYS[j]] = { typeface = f.typeface, size = f.size } end
			end
		end
		for key, base in pairs(st._fontBase) do
			local f = st[key]
			f.typeface = (face and face[2]) or base.typeface
			f.size = math.max(4, (base.size or 9) + offset)
		end
	end
end

-- Families: "Neon/Tank" + "Neon/DPS" -> "Neon"; standalone themes keep their name
local function GetThemeFamilies()
	local list, seen = {}, {}
	for name in pairs(SHPlatesThemeList) do
		local _, _, family = string.find(name, "^(.-)/")
		family = family or name
		if not seen[family] then seen[family] = true; table.insert(list, family) end
	end
	table.sort(list)
	table.insert(list, "None")
	return list
end

local function ResolveThemeName(family, role)
	if SHPlatesThemeList[family .. "/" .. role] then return family .. "/" .. role end
	if SHPlatesThemeList[family] then return family end
	return nil
end

-------------------------------------------------------------------------------
-- Role detection (replaces dual-spec switching)
-------------------------------------------------------------------------------
local function HasBuffTexture(fragment)
	for i = 1, 32 do
		local tex = UnitBuff("player", i)
		if not tex then return false end
		if string.find(string.lower(tex), fragment, 1, true) then return true end
	end
	return false
end

local function ActiveFormTexture()
	if not GetNumShapeshiftForms then return nil end
	for i = 1, GetNumShapeshiftForms() do
		local icon, _, active = GetShapeshiftFormInfo(i)
		if active and icon then return string.lower(icon) end
	end
	return nil
end

local function DetectRole()
	local _, class = UnitClass("player")
	local form = ActiveFormTexture()
	if class == "WARRIOR" and form and string.find(form, "defensivestance", 1, true) then return "Tank" end
	if class == "DRUID" and form and string.find(form, "bearform", 1, true) then return "Tank" end
	if class == "PALADIN" and HasBuffTexture("sealoffury") then return "Tank" end
	return "DPS"
end

function SHPlates.GetRole() return activeRole end

-------------------------------------------------------------------------------
-- Talent builds (dual spec)
-------------------------------------------------------------------------------
local function GetSpecInfo()
	local n = GetNumTalentTabs and GetNumTalentTabs() or 0
	local parts, labels = {}, {}
	local best, bestPoints = nil, 0
	for i = 1, n do
		local name, _, points = GetTalentTabInfo(i)
		points = points or 0
		table.insert(parts, points)
		table.insert(labels, (name or "?") .. " " .. points)
		if points > bestPoints then best, bestPoints = i, points end
	end
	return table.concat(parts, "/"), table.concat(labels, " / "), best
end

-- Sensible starting point for a build nobody has configured yet
local function DefaultSpecRole(bestTree)
	local _, class = UnitClass("player")
	if not bestTree then return "AUTO" end
	if class == "WARRIOR" then if bestTree == 3 then return "Tank" end return "AUTO" end
	if class == "PALADIN" then if bestTree == 2 then return "Tank" end return "AUTO" end
	if class == "DRUID" then if bestTree == 2 then return "AUTO" end return "DPS" end
	return "DPS"
end

local currentSpec
local function CurrentSpec()
	local sig, label, best = GetSpecInfo()
	currentSpec = sig
	local saved = SHPlatesDB.specs[sig]
	if saved then return saved, sig, label, true end
	return { theme = SHPlatesDB.theme, role = DefaultSpecRole(best) }, sig, label, false
end
SHPlates.CurrentSpec = function() return CurrentSpec() end

-- Store a setting for the current build (only stored once you change something)
local function SetSpecSetting(key, value)
	local settings, sig = CurrentSpec()
	if not SHPlatesDB.specs[sig] then
		SHPlatesDB.specs[sig] = { theme = settings.theme, role = settings.role }
	end
	SHPlatesDB.specs[sig][key] = value
	if key == "theme" then SHPlatesDB.theme = value end
end
SHPlates.SetSpecSetting = SetSpecSetting

local function ApplyAll(silent)
	local settings = CurrentSpec()
	local role = settings.role
	if role ~= "Tank" and role ~= "DPS" then role = DetectRole() end
	activeRole = role
	local name = ResolveThemeName(settings.theme or SHPlatesDB.theme, role)
	local changed = name ~= activeThemeName
	LoadTheme(name)
	SHPlatesWidgets.ResetWidgets()
	SHPlates:ForceUpdate()
	Data.BroadcastRole()
	if changed and not silent and name then C.print("now using " .. name) end
	if SHPlates.RefreshConfig then SHPlates.RefreshConfig() end
end
SHPlates.ApplySettings = ApplyAll

local function CheckRole()
	if not SHPlatesDB then return end
	local settings, sig = CurrentSpec()
	if sig ~= lastSpecApplied then lastSpecApplied = sig; ApplyAll(); return end
	if settings.role ~= "Tank" and settings.role ~= "DPS" and DetectRole() ~= activeRole then ApplyAll() end
end

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------
local function InitDB()
	if type(SHPlatesDB) ~= "table" then SHPlatesDB = {} end
	for k, v in pairs(DEFAULTS) do
		if SHPlatesDB[k] == nil then
			if type(v) == "table" then SHPlatesDB[k] = copytable(v) else SHPlatesDB[k] = v end
		end
	end
	-- Saved theme variables are written into the live tables the themes use
	for name, theme in pairs(SHPlatesThemeList) do
		if type(theme) == "table" and type(theme.vars) == "table" then
			local saved = SHPlatesDB.themevars[name]
			if type(saved) == "table" then applysaved(theme.vars, saved) end
			SHPlatesDB.themevars[name] = theme.vars
		end
	end
end

-------------------------------------------------------------------------------
-- Options window helpers (1.12 templates)
-------------------------------------------------------------------------------
local uid = 0
local function NewName(prefix) uid = uid + 1; return "SHPlatesCfg" .. prefix .. uid end

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function SetToLines(t, isNotes)
	local lines = {}
	for k, v in pairs(t) do
		if isNotes then table.insert(lines, k .. " = " .. tostring(v))
		else table.insert(lines, k) end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function LinesToSet(text, target, isNotes)
	C.wipe(target)
	local lines = C.Lines(text)
	for i = 1, table.getn(lines) do
		local line = lines[i]
		if isNotes then
			local _, _, k, v = string.find(line, "^(.-)%s*=%s*(.+)$")
			if k and k ~= "" then target[k] = v end
		else
			target[line] = true
		end
	end
end

local function CreateHeader(parent, text, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
	fs:SetText(text)
	return fs, 24
end

local function CreateCheck(parent, label, y, getter, setter)
	local name = NewName("Check")
	local cb = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	getglobal(name .. "Text"):SetText(label)
	cb.Refresh = function() cb:SetChecked(getter() and 1 or nil) end
	cb:SetScript("OnClick", function() setter(this:GetChecked() and true or false) end)
	cb.Refresh()
	return cb, 26
end

local function CreateSlider(parent, label, y, minv, maxv, step, ispct, getter, setter)
	local name = NewName("Slider")
	local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y - 14)
	sl:SetWidth(200)
	sl:SetMinMaxValues(minv, maxv)
	sl:SetValueStep(step)
	local fmt = function(v) if ispct then return math.floor(v * 100 + .5) .. "%" end return tostring(v) end
	getglobal(name .. "Low"):SetText(fmt(minv))
	getglobal(name .. "High"):SetText(fmt(maxv))
	local text = getglobal(name .. "Text")
	local loading = false
	sl.Refresh = function()
		loading = true
		local v = getter() or minv
		sl:SetValue(v)
		text:SetText(label .. ": " .. fmt(v))
		loading = false
	end
	sl:SetScript("OnValueChanged", function()
		local v = math.floor(this:GetValue() / step + .5) * step
		text:SetText(label .. ": " .. fmt(v))
		if not loading then setter(v) end
	end)
	sl.Refresh()
	return sl, 46
end

local function CreateColor(parent, label, y, getter, setter)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
	swatch:SetWidth(20); swatch:SetHeight(20)
	swatch:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameColorSwatch",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, tileSize = 16, edgeSize = 8,
		insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	local fs = swatch:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
	fs:SetText(label)
	swatch.Refresh = function()
		local c = getter()
		swatch:SetBackdropColor(c.r, c.g, c.b, 1)
	end
	swatch:SetScript("OnClick", function()
		local c = getter()
		local pr, pg, pb = c.r, c.g, c.b
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			setter(r, g, b); swatch.Refresh()
		end
		ColorPickerFrame.cancelFunc = function()
			setter(pr, pg, pb); swatch.Refresh()
		end
		ColorPickerFrame.previousValues = { r = pr, g = pg, b = pb }
		ColorPickerFrame:SetColorRGB(pr, pg, pb)
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end)
	swatch.Refresh()
	return swatch, 26
end

local function CreateChoice(parent, label, y, choices, getter, setter)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
	fs:SetText(label)
	local name = NewName("Choice")
	local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 14)
	b:SetWidth(200); b:SetHeight(20)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.Refresh = function()
		local v = getter()
		b:SetText("<  " .. (choices[v] or tostring(v)) .. "  >")
	end
	b:SetScript("OnClick", function()
		local n = table.getn(choices)
		local v = getter() or 1
		if arg1 == "RightButton" then v = v - 1 else v = v + 1 end
		if v > n then v = 1 elseif v < 1 then v = n end
		setter(v)
		b.Refresh()
	end)
	b.Refresh()
	return b, 40
end

-- One button per option, the selected one stays lit (used for the theme picker)
local function CreateButtonRow(parent, label, y, choices, getter, setter)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
	fs:SetText(label)
	local row = { buttons = {} }
	local perRow, width = 3, 104
	for i = 1, table.getn(choices) do
		local index = i
		local b = CreateFrame("Button", NewName("Pick"), parent, "UIPanelButtonTemplate")
		local col = math.mod(i - 1, perRow)
		local line = math.floor((i - 1) / perRow)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16 + col * (width + 4), y - 14 - line * 24)
		b:SetWidth(width); b:SetHeight(22)
		b:SetScript("OnClick", function() setter(index); row.Refresh() end)
		row.buttons[i] = b
	end
	row.Refresh = function()
		local current = getter()
		for i = 1, table.getn(choices) do
			local b = row.buttons[i]
			if i == current then
				b:SetText("|cff00ff00" .. choices[i] .. "|r")
				b:LockHighlight()
			else
				b:SetText(choices[i])
				b:UnlockHighlight()
			end
		end
	end
	row.Refresh()
	local lines = math.floor((table.getn(choices) - 1) / perRow) + 1
	return row, 20 + lines * 24
end

local function CreateList(parent, label, y, getter, setter, height)
	height = height or 70
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
	fs:SetText(label)
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 14)
	box:SetWidth(300); box:SetHeight(height)
	box:SetBackdrop(BACKDROP)
	box:SetBackdropColor(0, 0, 0, .6)
	box:SetBackdropBorderColor(.4, .4, .4, 1)
	box:EnableMouse(true)
	local name = NewName("Edit")
	local edit = CreateFrame("EditBox", name, box)
	edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
	edit:SetWidth(284); edit:SetHeight(height - 12)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	edit:SetScript("OnEditFocusLost", function() setter(this:GetText()) end)
	box:SetScript("OnMouseUp", function() edit:SetFocus() end)
	edit.Refresh = function() edit:SetText(getter() or "") end
	edit.Refresh()
	return edit, height + 22
end

-------------------------------------------------------------------------------
-- Options window
-------------------------------------------------------------------------------
local Config = CreateFrame("Frame", "SHPlatesConfig", UIParent)
Config:Hide()
Config:SetWidth(420); Config:SetHeight(520)
Config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Config:SetFrameStrata("DIALOG")
Config:SetMovable(true)
Config:EnableMouse(true)
Config:RegisterForDrag("LeftButton")
Config:SetScript("OnDragStart", function() this:StartMoving() end)
Config:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
Config:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
table.insert(UISpecialFrames, "SHPlatesConfig")

Config.title = Config:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
Config.title:SetPoint("TOP", Config, "TOP", 0, -16)
Config.title:SetText("SHPlates")

local close = CreateFrame("Button", "SHPlatesConfigClose", Config, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", Config, "TOPRIGHT", -6, -6)

local pages, tabs = {}, {}
local currentPage

local function ShowPage(key)
	for k, p in pairs(pages) do if k == key then p:Show() else p:Hide() end end
	for k, t in pairs(tabs) do
		if k == key or t.pageKey == key then t:LockHighlight() else t:UnlockHighlight() end
	end
	currentPage = key
	if pages[key] and pages[key].RefreshAll then pages[key].RefreshAll() end
end

local function CreatePage(key)
	local scrollName = NewName("Scroll")
	local scroll = CreateFrame("ScrollFrame", scrollName, Config, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", Config, "TOPLEFT", 18, -74)
	scroll:SetPoint("BOTTOMRIGHT", Config, "BOTTOMRIGHT", -38, 18)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(350); child:SetHeight(100)
	scroll:SetScrollChild(child)
	scroll.child = child
	scroll.controls = {}
	scroll.RefreshAll = function()
		for i = 1, table.getn(scroll.controls) do
			local c = scroll.controls[i]
			if c.Refresh then c.Refresh() end
		end
	end
	scroll:Hide()
	pages[key] = scroll
	return scroll
end

local function AddControl(page, control) table.insert(page.controls, control) end

-- Called after any change that affects the active theme
local function Changed(themeName)
	if not themeName or themeName == activeThemeName then
		if activeThemeName then LoadTheme(activeThemeName) end
		SHPlatesWidgets.ResetWidgets()
		SHPlates:ForceUpdate()
	end
end

local function BuildThemePage(page, themeName)
	local theme = SHPlatesThemeList[themeName]
	local child = page.child
	local y = -4
	local vars = theme and theme.vars
	if not (theme and vars and theme.optionsSchema) then
		local fs = child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		fs:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y)
		fs:SetText("This theme has no options.")
		return
	end
	local schema = theme.optionsSchema
	for i = 1, table.getn(schema) do
		local item = schema[i]
		local key = item.key
		local control, h
		if item.type == "header" then
			control, h = CreateHeader(child, item.text, y - 6); h = h + 6
		elseif item.type == "check" then
			control, h = CreateCheck(child, item.label, y,
				function() return vars[key] end,
				function(v) vars[key] = v; Changed(themeName) end)
		elseif item.type == "slider" then
			control, h = CreateSlider(child, item.label, y, item.min, item.max, item.step, item.pct,
				function() return vars[key] end,
				function(v) vars[key] = v; Changed(themeName) end)
		elseif item.type == "color" then
			control, h = CreateColor(child, item.label, y,
				function() return vars[key] end,
				function(r, g, b) local c = vars[key]; c.r, c.g, c.b = r, g, b; Changed(themeName) end)
		elseif item.type == "choice" then
			control, h = CreateChoice(child, item.label, y, item.choices,
				function() return vars[key] end,
				function(v) vars[key] = v; Changed(themeName) end)
		elseif item.type == "list" then
			if type(vars[key]) ~= "table" then vars[key] = {} end
			control, h = CreateList(child, item.label, y,
				function() return SetToLines(vars[key]) end,
				function(text) LinesToSet(text, vars[key]); Changed(themeName) end)
		end
		if control then AddControl(page, control); y = y - (h or 24) end
	end
	child:SetHeight(-y + 20)
end

local generalStatus, learnedText

local function SpecTheme()
	local settings = CurrentSpec()
	return settings.theme or SHPlatesDB.theme
end

local function BuildGeneralPage(page)
	local child = page.child
	local y = -4
	local c, h
	local families = GetThemeFamilies()

	c, h = CreateHeader(child, "This talent build", y); y = y - h
	generalStatus = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	generalStatus:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
	generalStatus:SetWidth(320)
	generalStatus:SetJustifyH("LEFT")
	y = y - 56

	c, h = CreateButtonRow(child, "Theme for this build", y, families,
		function()
			local current = SpecTheme()
			for i = 1, table.getn(families) do if families[i] == current then return i end end
			return 1
		end,
		function(v) SetSpecSetting("theme", families[v]); ApplyAll(true); SHPlates.RefreshConfigTabs() end)
	AddControl(page, c); y = y - h

	local roles = { "Auto (stance / form)", "Tank", "DPS" }
	local roleKeys = { "AUTO", "Tank", "DPS" }
	c, h = CreateChoice(child, "Mode for this build", y, roles,
		function()
			local settings = CurrentSpec()
			for i = 1, 3 do if roleKeys[i] == settings.role then return i end end
			return 1
		end,
		function(v) SetSpecSetting("role", roleKeys[v]); ApplyAll(true) end)
	AddControl(page, c); y = y - h

	local tip = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tip:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
	tip:SetWidth(320); tip:SetJustifyH("LEFT")
	tip:SetText("Saved per talent build: swap specs and SHPlates swaps with you. " ..
		"Auto = Tank in Defensive Stance, Bear Form or Righteous Fury.")
	y = y - 34

	c, h = CreateHeader(child, "Nameplates", y); y = y - h
	c, h = CreateCheck(child, "Allow overlapping nameplates", y,
		function() return SHPlatesDB.overlap end,
		function(v) SHPlatesDB.overlap = v; SHPlates:SetOverlap(v) end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Turn off pfUI's nameplates while SHPlates is on", y,
		function() return SHPlatesDB.hidePfUIPlates end,
		function(v) SHPlatesDB.hidePfUIPlates = v
			if v then SHPlates.Conflicts.KillPfUIPlates()
			else C.print("pfUI's nameplates come back after a /reload.") end end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Show plates only in combat (auto-hide)", y,
		function() return SHPlatesDB.autohide end,
		function(v) SHPlatesDB.autohide = v; SHPlates:UseAutoHide(v)
			if not v and ShowNameplates then ShowNameplates() end end)
	AddControl(page, c); y = y - h

	local showBtn = CreateFrame("Button", NewName("Btn"), child, "UIPanelButtonTemplate")
	showBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y - 4)
	showBtn:SetWidth(150); showBtn:SetHeight(22)
	showBtn:SetText("Show Nameplates")
	showBtn:SetScript("OnClick", function()
		if ShowNameplates then ShowNameplates() end
		if ShowFriendNameplates then ShowFriendNameplates() end
		SHPlates:ForceUpdate()
	end)
	local resetBtn = CreateFrame("Button", NewName("Btn"), child, "UIPanelButtonTemplate")
	resetBtn:SetPoint("LEFT", showBtn, "RIGHT", 10, 0)
	resetBtn:SetWidth(150); resetBtn:SetHeight(22)
	resetBtn:SetText("Reset All + Reload")
	resetBtn:SetScript("OnClick", function() SHPlatesDB = nil; ReloadUI() end)
	y = y - 34

	c, h = CreateHeader(child, "Which plates show", y); y = y - h
	c, h = CreateCheck(child, "Show friendly plates", y,
		function() return SHPlatesDB.showFriendly end,
		function(v) SHPlatesDB.showFriendly = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Show critters", y,
		function() return SHPlatesDB.showCritters end,
		function(v) SHPlatesDB.showCritters = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Click-through (plates ignore the mouse)", y,
		function() return SHPlatesDB.clickThrough end,
		function(v) SHPlatesDB.clickThrough = v; SHPlates:SetOverlap(SHPlatesDB.overlap) end)
	AddControl(page, c); y = y - h
	local tipHidden = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tipHidden:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
	tipHidden:SetWidth(320); tipHidden:SetJustifyH("LEFT")
	tipHidden:SetText("Hidden plates still show when you target them. Hidden plates can't be clicked.")
	y = y - 28

	c, h = CreateHeader(child, "Health bar colors", y); y = y - h
	c, h = CreateCheck(child, "Class colors for enemy players", y,
		function() return SHPlatesDB.classColorEnemies end,
		function(v) SHPlatesDB.classColorEnemies = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "...but not for PvP-flagged enemies (plain red)", y,
		function() return SHPlatesDB.noClassColorPvP end,
		function(v) SHPlatesDB.noClassColorPvP = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Class colors for friendly players", y,
		function() return SHPlatesDB.classColorFriends end,
		function(v) SHPlatesDB.classColorFriends = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Gray when tapped by someone outside your group", y,
		function() return SHPlatesDB.tappedColorOn end,
		function(v) SHPlatesDB.tappedColorOn = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateColor(child, "Tapped color", y,
		function() return SHPlatesDB.tappedColor end,
		function(r, g, b) local col = SHPlatesDB.tappedColor; col.r, col.g, col.b = r, g, b; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Special color while stunned", y,
		function() return SHPlatesDB.stunColorOn end,
		function(v) SHPlatesDB.stunColorOn = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateColor(child, "Stunned color", y,
		function() return SHPlatesDB.stunColor end,
		function(r, g, b) local col = SHPlatesDB.stunColor; col.r, col.g, col.b = r, g, b; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h

	c, h = CreateHeader(child, "Fonts", y); y = y - h
	local fontNames = {}
	for i = 1, table.getn(SHPlates.FONTS) do fontNames[i] = SHPlates.FONTS[i][1] end
	c, h = CreateChoice(child, "Nameplate font", y, fontNames,
		function() return SHPlatesDB.fontFace or 1 end,
		function(v) SHPlatesDB.fontFace = v; ApplyAll(true) end)
	AddControl(page, c); y = y - h
	c, h = CreateSlider(child, "Text size (+/-)", y, -4, 8, 1, false,
		function() return SHPlatesDB.fontSizeOffset or 0 end,
		function(v) SHPlatesDB.fontSizeOffset = v; ApplyAll(true) end)
	AddControl(page, c); y = y - h

	c, h = CreateHeader(child, "Raid marks", y); y = y - h
	local tipMarks = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tipMarks:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
	tipMarks:SetWidth(320); tipMarks:SetJustifyH("LEFT")
	tipMarks:SetText("Key Bindings > SHPlates: mark your target with a key. Works solo too (only you see solo marks).")
	y = y - 30

	c, h = CreateHeader(child, "Uninterruptible casts (learned)", y); y = y - h
	learnedText = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	learnedText:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
	learnedText:SetWidth(320); learnedText:SetJustifyH("LEFT")
	y = y - 30
	c, h = CreateCheck(child, "Also learn from group members' interrupts", y,
		function() return SHPlatesDB.learnFromGroup end,
		function(v) SHPlatesDB.learnFromGroup = v end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Announce in chat when something new is learned", y,
		function() return SHPlatesDB.announceLearned end,
		function(v) SHPlatesDB.announceLearned = v end)
	AddControl(page, c); y = y - h
	local listBtn = CreateFrame("Button", NewName("Btn"), child, "UIPanelButtonTemplate")
	listBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y - 4)
	listBtn:SetWidth(150); listBtn:SetHeight(22)
	listBtn:SetText("List in chat")
	listBtn:SetScript("OnClick", function() SHPlatesSlashCommands.learned() end)
	local forgetBtn = CreateFrame("Button", NewName("Btn"), child, "UIPanelButtonTemplate")
	forgetBtn:SetPoint("LEFT", listBtn, "RIGHT", 10, 0)
	forgetBtn:SetWidth(150); forgetBtn:SetHeight(22)
	forgetBtn:SetText("Forget all")
	forgetBtn:SetScript("OnClick", function() SHPlates.Interrupts.Forget(); page.RefreshAll(); SHPlates:Update() end)
	y = y - 34

	c, h = CreateHeader(child, "Other tanks", y); y = y - h
	c, h = CreateList(child, "Names here count as tanks for threat widgets (one per line).", y,
		function() return SetToLines(SHPlatesDB.tankNames) end,
		function(text) LinesToSet(text, SHPlatesDB.tankNames); SHPlates:Update() end, 60)
	AddControl(page, c); y = y - h

	c, h = CreateHeader(child, "Mob Notes", y); y = y - h
	c, h = CreateList(child, "One per line:  Mob Name = note text", y,
		function() return SetToLines(SHPlatesDB.notes, true) end,
		function(text) LinesToSet(text, SHPlatesDB.notes, true); SHPlates:Update() end, 90)
	AddControl(page, c); y = y - h

	child:SetHeight(-y + 20)

	page.RefreshAllBase = page.RefreshAll
	page.RefreshAll = function()
		page.RefreshAllBase()
		local _, sig, label, saved = CurrentSpec()
		local threat = (GetTime() - Data.threat.targetStamp < 30) and "|cff00ff00receiving|r" or "none yet (needs a group)"
		generalStatus:SetText(
			"Talents: |cffffffff" .. (label ~= "" and label or "none") .. "|r" ..
			(saved and "" or "  |cff888888(defaults)|r") .. "\n" ..
			"Active: |cffffffff" .. (activeThemeName or "None") .. "|r\n" ..
			"SuperWoW: " .. (C.HasSuperWoW and "|cff00ff00yes|r" or "|cffff4040no (limited)|r") ..
			"   Nampower: " .. (C.HasNampower and "|cff00ff00yes|r" or "|cffff4040no|r") ..
			"\nServer threat: " .. threat)
		learnedText:SetText("Mob + spell combinations that ignored an interrupt: |cffffffff" ..
			SHPlates.Interrupts.Count() .. "|r\nThey get the \"can't interrupt\" cast border.")
	end
end

local function CreateTab(key, text, x)
	local b = CreateFrame("Button", NewName("Tab"), Config, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", Config, "TOPLEFT", x, -42)
	b:SetWidth(90); b:SetHeight(22)
	b:SetText(text)
	b:SetScript("OnClick", function() ShowPage(key) end)
	tabs[key] = b
	return b
end

-- Theme pages are built per theme name, on demand
function SHPlates.RefreshConfigTabs()
	if not tabs.modeTank then return end
	local family = SpecTheme()
	for _, role in ipairs({ "Tank", "DPS" }) do
		local key = "mode" .. role
		local themeName = ResolveThemeName(family, role)
		local pageKey = themeName and ("theme:" .. themeName) or nil
		local tab = tabs[key]
		if pageKey and not pages[pageKey] then
			BuildThemePage(CreatePage(pageKey), themeName)
		end
		if pageKey then
			tab:Show()
			tab:SetScript("OnClick", function() ShowPage(pageKey) end)
			tab:SetText(family .. ": " .. role)
		else tab:Hide() end
		tab.pageKey = pageKey
	end
	if currentPage and currentPage ~= "general" then ShowPage("general") end
end

local built = false
local function BuildConfig()
	if built then return end
	built = true
	BuildGeneralPage(CreatePage("general"))
	-- Share page: plain frame (its text box scrolls on its own)
	local share = CreateFrame("Frame", nil, Config)
	share:SetPoint("TOPLEFT", Config, "TOPLEFT", 20, -74)
	share:SetPoint("BOTTOMRIGHT", Config, "BOTTOMRIGHT", -20, 18)
	share:Hide()
	pages.share = share
	SHPlates.Share.BuildPage(share)
	CreateTab("general", "General", 20)
	CreateTab("modeTank", "Tank", 114)
	CreateTab("modeDPS", "DPS", 208)
	CreateTab("share", "Share", 302)
	SHPlates.RefreshConfigTabs()
	ShowPage("general")
end

function SHPlates.ToggleConfig()
	BuildConfig()
	if Config:IsShown() then Config:Hide() else Config:Show(); ShowPage(currentPage or "general") end
end

-- /shp export, /shp import, /shp share open the Share page
function SHPlates.ShowConfigPage(key)
	BuildConfig()
	Config:Show()
	ShowPage(key)
end

-- After an import: every page re-reads its values
function SHPlates.RefreshAllConfigPages()
	if not built then return end
	for _, p in pairs(pages) do if p.RefreshAll then p.RefreshAll() end end
end

-- Called by ApplyAll so an open window follows spec swaps
function SHPlates.RefreshConfig()
	if not built then return end
	local family = SpecTheme()
	if tabs.modeTank.family ~= family then
		tabs.modeTank.family = family
		SHPlates.RefreshConfigTabs()
	end
	if Config:IsShown() and pages.general and currentPage == "general" then pages.general.RefreshAll() end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
loader:RegisterEvent("PLAYER_AURAS_CHANGED")
loader:RegisterEvent("CHARACTER_POINTS_CHANGED")
loader:RegisterEvent("SPELLS_CHANGED")
local ready = false
local recheck = nil
loader:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == SHPlates.ADDON then
		InitDB()
	elseif SHPlates.disabled then
		return  -- GudaPlates is running: keep settings loaded, do nothing else
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not SHPlatesDB then InitDB() end
		SHPlates:UseAutoHide(SHPlatesDB.autohide)
		SHPlates:SetOverlap(SHPlatesDB.overlap)
		local _, sig = CurrentSpec()
		lastSpecApplied = sig
		ApplyAll(true)
		if not ready then
			ready = true
			if not C.HasSuperWoW then
				C.print("SuperWoW not detected: casts, class, elite and per-plate debuffs are limited. Type /shplates for options.")
			end
		end
	elseif ready then
		-- talent swaps fire several events in a row: check once, shortly after
		recheck = GetTime() + .5
	end
end)
loader:SetScript("OnUpdate", function()
	if recheck and GetTime() >= recheck then
		recheck = nil
		CheckRole()
	end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SHPlatesSlashCommands = {}
SHPlatesSlashCommands.reset = function() SHPlatesDB = nil; ReloadUI() end
SHPlatesSlashCommands.tank = function() SetSpecSetting("role", "Tank"); ApplyAll() end
SHPlatesSlashCommands.dps = function() SetSpecSetting("role", "DPS"); ApplyAll() end
SHPlatesSlashCommands.auto = function() SetSpecSetting("role", "AUTO"); ApplyAll() end
SHPlatesSlashCommands.status = function()
	local settings, sig, label = CurrentSpec()
	C.print("theme " .. tostring(activeThemeName) .. ", mode " .. activeRole ..
		" (" .. tostring(settings.role) .. " for build " .. sig .. "), themes loaded: " ..
		table.concat(GetThemeFamilies(), ", ") .. ", SuperWoW " ..
		(C.HasSuperWoW and "yes" or "no") .. ", Nampower " .. (C.HasNampower and "yes" or "no"))
end
-- /shplates debug : one line per visible plate, to see what the client reports
SHPlatesSlashCommands.debug = function()
	local n = 0
	for plate in pairs(SHPlates.VisibleNameplates) do
		local ext = plate.extended
		if ext and plate:IsShown() then
			n = n + 1
			local u = ext.unit
			local raw = plate.GetName and plate:GetName(1)
			local text = ext.regions.name:GetText()
			local gname = raw and raw ~= "" and UnitName(raw)
			local hp, low, high = ext.bars.health:GetValue(), ext.bars.health:GetMinMaxValues()
			local r, g, b = ext.bars.health:GetStatusBarColor()
			local ghp, gmax, ctype, react
			if raw and raw ~= "" then
				ghp, gmax = UnitHealth(raw), UnitHealthMax(raw)
				ctype = UnitCreatureType(raw)
				react = UnitReaction and UnitReaction(raw, "player")
			end
			DEFAULT_CHAT_FRAME:AddMessage(string.format(
				"|cff33ff99[%d]|r plate='%s' guid=%s guidName=%s used=%s | bar %s/%s rgb %.2f,%.2f,%.2f | guidHP %s/%s type=%s react=%s | crit=%s %s alpha=%.2f",
				n, tostring(text), tostring(raw), tostring(gname), tostring(u.guid),
				tostring(hp), tostring(high), r or 0, g or 0, b or 0,
				tostring(ghp), tostring(gmax), tostring(ctype), tostring(react),
				tostring(u.isCritter), tostring(u.reaction), ext:GetAlpha()))
		end
	end
	if n == 0 then C.print("no visible plates") end
	local th = SHPlates:GetActiveTheme()
	local vars = th and th.vars or {}
	C.print("theme=" .. tostring(activeThemeName) .. " hideNeutral=" .. tostring(vars.OpacityHideNeutral) ..
		" showCritters=" .. tostring(SHPlatesDB.showCritters) .. " showFriendly=" .. tostring(SHPlatesDB.showFriendly) ..
		" lastError=" .. tostring(SHPlates.lastError))
	for plate in pairs(SHPlates.VisibleNameplates) do
		local u = plate.extended and plate.extended.unit
		if u and u.isCritter then
			local a, f = th.SetAlpha and th.SetAlpha(u)
			C.print("critter '" .. tostring(u.name) .. "': theme alpha=" .. tostring(a) .. " filtered=" .. tostring(SHPlates.IsFilteredOut(u)))
		end
	end
end

SHPlatesSlashCommands.learned = function()
	local lines = SHPlates.Interrupts.List()
	if table.getn(lines) == 0 then C.print("no uninterruptible casts learned yet"); return end
	C.print("uninterruptible casts learned:")
	for i = 1, table.getn(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. lines[i]) end
end

local function Slash(msg)
	msg = string.lower(msg or "")
	local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.-)$")
	if cmd == "theme" and rest ~= "" then
		for name in pairs(SHPlatesThemeList) do
			local _, _, family = string.find(name, "^(.-)/")
			family = family or name
			if string.lower(family) == rest then
				SetSpecSetting("theme", family); ApplyAll()
				return
			end
		end
		C.print("unknown theme '" .. rest .. "'")
	elseif SHPlatesSlashCommands[cmd] then
		SHPlatesSlashCommands[cmd]()
	else
		SHPlates.ToggleConfig()
	end
end

SLASH_SHPLATES1 = "/shplates"
SLASH_SHPLATES2 = "/shp"
SlashCmdList["SHPLATES"] = Slash
