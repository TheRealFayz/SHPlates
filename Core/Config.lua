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
	hidePfUIPlates = true,
	hideShaguPlates = true,
	layout = {},           -- Designer tab: piece offsets per template
	learnFromGroup = true,
	announceLearned = true,
	tankNames = {},
	notes = {},
	themevars = {},        -- every template's own settings (see TEMPLATE_DEFAULTS)
}

-- Settings each template (Grey/Tank, Grey/DPS, Neon/Tank, Neon/DPS, and any
-- added later) keeps for itself, in its vars next to its own options
local TEMPLATE_DEFAULTS = {
	-- Display tab
	overlap = false, clickThrough = false, autohide = false,
	hideFriendly = false, hideCritters = true, hideLevel = false, hideCastbars = false,
	classColorEnemies = true, classColorFriends = false, noClassColorPvP = false,
	tappedColorOn = true, tappedColor = { r = .5, g = .5, b = .5 },
	stunColorOn = true, stunColor = { r = .376, g = .027, b = .431 },
	-- Size and Style tab (1 = the theme's own size)
	barWidth = 1, barHeight = 1, fontSizeOffset = 0,
	friendlyWidth = 1, friendlyHeight = 1, friendlyFontOffset = 0,
	castWidth = 1, castHeight = 1, castFontOffset = 0, hideSpellIcon = false,
	castColorOn = false, castColor = { r = 1, g = .8, b = 0 },
	debuffScale = 1, hideDebuffTimers = false,
	fontFace = 1, healthTextAlign = 1, holderFontSize = 8,
	healthTextColorOn = false, healthTextColor = { r = 1, g = 1, b = 1 },
	nameColorOn = false, nameColor = { r = 1, g = 1, b = 1 },
	targetColorOn = false, targetColor = { r = 1, g = 1, b = 1 },
}
SHPlates.TEMPLATE_DEFAULTS = TEMPLATE_DEFAULTS

SHPlates.DEFAULTS = DEFAULTS  -- Share.lua checks imports against these

local activeRole = "DPS"
local lastSpecApplied
local activeThemeName = nil
local RESERVED = { vars = true, optionsSchema = true }

-------------------------------------------------------------------------------
-- Theme loading
-------------------------------------------------------------------------------
-- Fill in a theme's style from the defaults and the settings, without
-- switching to it (the Designer previews the other mode this way)
local function PrepareTheme(name)
	local theme = SHPlatesThemeList[name]
	if type(theme) ~= "table" then return nil end
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
	return theme
end
SHPlates.PrepareTheme = PrepareTheme

local function LoadTheme(name)
	local theme = PrepareTheme(name)
	if not theme then
		SHPlates:ActivateTheme(SHPlates.defaultTheme)
		activeThemeName = nil
		return
	end
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
	local vars = theme.vars or TEMPLATE_DEFAULTS
	local face = SHPlates.FONTS[vars.fontFace or 1]
	local offset = vars.fontSizeOffset or 0
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

-- the active template's value for a template setting
local function TV(key)
	local th = SHPlates:GetActiveTheme()
	local v = th and th.vars and th.vars[key]
	if v == nil then v = TEMPLATE_DEFAULTS[key] end
	return v
end

local lastAutohide
local function ApplyAll(silent)
	local settings = CurrentSpec()
	local role = settings.role
	if role ~= "Tank" and role ~= "DPS" then role = DetectRole() end
	activeRole = role
	local name = ResolveThemeName(settings.theme or SHPlatesDB.theme, role)
	local changed = name ~= activeThemeName
	LoadTheme(name)
	-- these follow the template too
	SHPlates:SetOverlap(TV("overlap"))
	local ah = TV("autohide") and true or false
	if ah ~= lastAutohide then
		if lastAutohide and not ah and ShowNameplates then ShowNameplates() end
		lastAutohide = ah
		SHPlates:UseAutoHide(ah)
	end
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
	-- "Show friendly plates" became "Hide friendly plates": the box keeps
	-- the state it had, and checked now means hidden
	if SHPlatesDB.showFriendly ~= nil then
		if SHPlatesDB.hideFriendly == nil then SHPlatesDB.hideFriendly = SHPlatesDB.showFriendly and true or false end
		SHPlatesDB.showFriendly = nil
	end
	-- Friendly text size used to be added on top of the enemy one: keep the
	-- size friendly plates had
	if not SHPlatesDB.fontOffsetsSplit then
		if SHPlatesDB.fontSizeOffset or SHPlatesDB.friendlyFontOffset then
			SHPlatesDB.friendlyFontOffset = (SHPlatesDB.fontSizeOffset or 0) + (SHPlatesDB.friendlyFontOffset or 0)
		end
		SHPlatesDB.fontOffsetsSplit = true
	end
	-- Same for "Show critters", which became "Hide critters"
	if SHPlatesDB.showCritters ~= nil then
		if SHPlatesDB.hideCritters == nil then SHPlatesDB.hideCritters = not SHPlatesDB.showCritters end
		SHPlatesDB.showCritters = nil
	end
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
			-- Grey's old per-theme "Unit Level" box is replaced by "Hide unit levels"
			theme.vars.LevelText = nil
			SHPlatesDB.themevars[name] = theme.vars
		end
	end
	-- Every template gets its own copy of the template settings. Settings
	-- that used to be shared start out as they were, in every template.
	for name, theme in pairs(SHPlatesThemeList) do
		if type(theme) == "table" and type(theme.vars) == "table" then
			for k, def in pairs(TEMPLATE_DEFAULTS) do
				if theme.vars[k] == nil then
					local old = SHPlatesDB[k]
					local v = def
					if old ~= nil and type(old) == type(def) then v = old end
					if type(v) == "table" then v = copytable(v) end
					theme.vars[k] = v
				end
			end
		end
	end
	for k in pairs(TEMPLATE_DEFAULTS) do SHPlatesDB[k] = nil end
end

-------------------------------------------------------------------------------
-- Options window
--
-- Same layout as AutoSpam: one dialog window, the title up top, a dark inset
-- the pages share, and spellbook-style tabs down the right side.
-------------------------------------------------------------------------------
local W, H = 400, 514
local MIN_SCALE, MAX_SCALE = .6, 1.6
local CW = 322           -- usable width inside a page
local uid = 0
local function NewName(prefix) uid = uid + 1; return "SHPlatesCfg" .. prefix .. uid end

local BOX_BACKDROP = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
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

local function AddBlend(tex) if tex then tex:SetBlendMode("ADD") end end

local function Tooltip(frame, title, text)
	if not title then return end
	frame:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, 1) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, text, w)
	local b = CreateFrame("Button", NewName("Btn"), parent, "UIPanelButtonTemplate")
	b:SetWidth(w or 120); b:SetHeight(22)
	b:SetText(text)
	return b
end

-- Gold section title with a faint rule under it
local function CreateHeader(parent, text, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
	fs:SetText(text)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture(1, .82, 0, .25)
	rule:SetHeight(1); rule:SetWidth(CW)
	rule:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y - 16)
	-- remember where each section starts (the Designer jumps to them)
	parent.sections = parent.sections or {}
	if not parent.sections[text] then parent.sections[text] = { y = -y, fs = fs } end
	return fs, 26
end

-- Small gray help text. lines = how many lines it needs.
local function CreateTip(parent, text, y, lines)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	fs:SetWidth(CW - 8); fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs, (lines or 1) * 12 + 8
end

local function CreateCheck(parent, label, y, getter, setter, tip)
	local cb = CreateFrame("CheckButton", NewName("Check"), parent)
	cb:SetWidth(22); cb:SetHeight(22)
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
	cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
	AddBlend(cb:GetHighlightTexture())
	cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	fs:SetText(label)
	-- the label is part of the click area
	if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -(fs:GetStringWidth() or 0) - 6, 0, 0) end
	cb.label = fs
	cb.Refresh = function() cb:SetChecked(getter() and 1 or nil) end
	cb:SetScript("OnClick", function() setter(this:GetChecked() and true or false) end)
	Tooltip(cb, tip and label, tip)
	cb.Refresh()
	return cb, 24
end

local function OpenColorPicker(getter, setter, done)
	local c = getter()
	local pr, pg, pb = c.r, c.g, c.b
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func = function()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		setter(r, g, b); done()
	end
	ColorPickerFrame.cancelFunc = function() setter(pr, pg, pb); done() end
	ColorPickerFrame.previousValues = { r = pr, g = pg, b = pb }
	ColorPickerFrame:SetColorRGB(pr, pg, pb)
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

local function MakeSwatch(parent)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetWidth(18); swatch:SetHeight(18)
	swatch:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameColorSwatch",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, tileSize = 16, edgeSize = 8,
		insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	return swatch
end

local function CreateColor(parent, label, y, getter, setter)
	local swatch = MakeSwatch(parent)
	swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y - 2)
	local fs = swatch:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	fs:SetText(label)
	swatch.Refresh = function()
		local c = getter()
		swatch:SetBackdropColor(c.r, c.g, c.b, 1)
	end
	swatch:SetScript("OnClick", function() OpenColorPicker(getter, setter, swatch.Refresh) end)
	Tooltip(swatch, label, "Click to pick a color.")
	swatch.Refresh()
	return swatch, 24
end

-- A checkbox with its color swatch at the end of the same row
local function CreateCheckColor(parent, label, y, getOn, setOn, getColor, setColor, tip)
	local cb = CreateCheck(parent, label, y, getOn, setOn, tip)
	local swatch = MakeSwatch(parent)
	swatch:SetPoint("TOPRIGHT", parent, "TOPLEFT", 8 + CW, y - 2)
	local refreshCheck = cb.Refresh
	cb.Refresh = function()
		refreshCheck()
		local c = getColor()
		swatch:SetBackdropColor(c.r, c.g, c.b, 1)
	end
	swatch:SetScript("OnClick", function() OpenColorPicker(getColor, setColor, cb.Refresh) end)
	Tooltip(swatch, label, "Click to pick the color.")
	cb.Refresh()
	return cb, 24
end

local function CreateSlider(parent, label, y, minv, maxv, step, ispct, getter, setter)
	local name = NewName("Slider")
	-- ispct: true = percent, "abs" = a plain number, otherwise a +/- offset
	local fmt = function(v)
		if ispct == "abs" then return tostring(v) end
		if ispct then return math.floor(v * 100 + .5) .. "%" end
		if v > 0 then return "+" .. v end return tostring(v) end
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y - 16)
	sl:SetWidth(CW - 16); sl:SetHeight(16)
	sl:SetMinMaxValues(minv, maxv)
	sl:SetValueStep(step)
	getglobal(name .. "Low"):SetText(fmt(minv))
	getglobal(name .. "High"):SetText(fmt(maxv))
	getglobal(name .. "Text"):SetText("")
	local loading = false
	local function Show(v) title:SetText(label .. ":  |cffffffff" .. fmt(v) .. "|r") end
	sl.Refresh = function()
		loading = true
		local v = getter() or minv
		sl:SetValue(v)
		Show(v)
		loading = false
	end
	sl:SetScript("OnValueChanged", function()
		local v = math.floor(this:GetValue() / step + .5) * step
		Show(v)
		if not loading then setter(v) end
	end)
	sl.Refresh()
	return sl, 50
end

-- Label, then  [<]  value  [>]. Click the value or > for the next one,
-- < or right-click for the previous one.
local function CreateChoice(parent, label, y, choices, getter, setter)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	title:SetText(label)
	local holder = { }
	local function Step(dir)
		local n = table.getn(choices)
		local v = (getter() or 1) + dir
		if v > n then v = 1 elseif v < 1 then v = n end
		setter(v)
		holder.Refresh()
	end
	local function Arrow(kind)
		local b = CreateFrame("Button", nil, parent)
		b:SetWidth(24); b:SetHeight(24)
		b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		AddBlend(b:GetHighlightTexture())
		return b
	end
	local prev = Arrow("Prev")
	prev:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y - 13)
	local box = CreateFrame("Button", nil, parent)
	box:SetWidth(180); box:SetHeight(22)
	box:SetPoint("LEFT", prev, "RIGHT", 2, 0)
	box:SetBackdrop(BOX_BACKDROP)
	box:SetBackdropColor(0, 0, 0, .6)
	box:SetBackdropBorderColor(.4, .4, .4, 1)
	box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("CENTER", box, "CENTER", 0, 0)
	local nextb = Arrow("Next")
	nextb:SetPoint("LEFT", box, "RIGHT", 2, 0)
	prev:SetScript("OnClick", function() Step(-1) end)
	nextb:SetScript("OnClick", function() Step(1) end)
	box:SetScript("OnClick", function() if arg1 == "RightButton" then Step(-1) else Step(1) end end)
	holder.Refresh = function()
		local v = getter()
		text:SetText(choices[v] or tostring(v))
	end
	holder.Refresh()
	return holder, 42
end

-- One button per option, the picked one stays lit (theme and mode pickers)
local function CreateButtonRow(parent, label, y, choices, getter, setter, tips)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	title:SetText(label)
	local row = { buttons = {} }
	local perRow, width = 3, 104
	for i = 1, table.getn(choices) do
		local index = i
		local b = Button(parent, choices[i], width)
		local col = math.mod(i - 1, perRow)
		local line = math.floor((i - 1) / perRow)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10 + col * (width + 4), y - 14 - line * 24)
		b:SetScript("OnClick", function() setter(index); row.Refresh() end)
		if tips and tips[i] then Tooltip(b, choices[i], tips[i]) end
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
	return row, 22 + lines * 24
end

local function CreateList(parent, label, y, getter, setter, height)
	height = height or 70
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
	fs:SetWidth(CW - 8); fs:SetJustifyH("LEFT")
	fs:SetText(label)
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y - 14)
	box:SetWidth(CW); box:SetHeight(height)
	box:SetBackdrop(BOX_BACKDROP)
	box:SetBackdropColor(0, 0, 0, .6)
	box:SetBackdropBorderColor(.4, .4, .4, 1)
	box:EnableMouse(true)
	local edit = CreateFrame("EditBox", NewName("Edit"), box)
	edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
	edit:SetWidth(CW - 16); edit:SetHeight(height - 12)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	edit:SetScript("OnEditFocusLost", function() setter(this:GetText()) end)
	box:SetScript("OnMouseUp", function() edit:SetFocus() end)
	edit.Refresh = function() edit:SetText(getter() or "") end
	edit.Refresh()
	return edit, height + 24
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local Config = CreateFrame("Frame", "SHPlatesConfig", UIParent)
Config:Hide()
Config:SetWidth(W); Config:SetHeight(H)
Config:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
-- HIGH, so the color picker and the reset prompt open on top of it
Config:SetFrameStrata("HIGH")
Config:SetMovable(true)
Config:EnableMouse(true)
Config:SetClampedToScreen(true)
Config:RegisterForDrag("LeftButton")
Config:SetScript("OnDragStart", function() this:StartMoving() end)
Config:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
Config:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
Config:SetBackdropColor(0, 0, 0, .9)
table.insert(UISpecialFrames, "SHPlatesConfig")

-- Round portrait over the top-left corner, like AutoSpam's hourglass
local portraitFrame = CreateFrame("Frame", nil, Config)
portraitFrame:SetWidth(72); portraitFrame:SetHeight(72)
portraitFrame:SetPoint("TOPLEFT", Config, "TOPLEFT", -12, 12)
portraitFrame:SetFrameLevel(Config:GetFrameLevel() + 5)
local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
portrait:SetAllPoints(portraitFrame)
portrait:SetTexture(SHPlates.MEDIA .. "Portrait")

-- the header sits a little right of center to balance the portrait
local title = Config:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", Config, "TOP", 16, -18)
title:SetText("SHPlates")
local byline = Config:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
byline:SetPoint("TOP", title, "BOTTOM", 0, -2)
byline:SetText("by Fayz")
-- what's running right now: theme, mode and build
local statusLine = Config:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
statusLine:SetPoint("TOP", byline, "BOTTOM", 0, -6)
statusLine:SetWidth(W - 110)

local close = CreateFrame("Button", "SHPlatesConfigClose", Config, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", Config, "TOPRIGHT", -6, -6)

local inset = CreateFrame("Frame", nil, Config)
inset:SetPoint("TOPLEFT", Config, "TOPLEFT", 14, -72)
inset:SetPoint("BOTTOMRIGHT", Config, "BOTTOMRIGHT", -14, 28)  -- the strip below holds the resize grip
inset:SetBackdrop(BOX_BACKDROP)
inset:SetBackdropColor(0, 0, 0, .5)
inset:SetBackdropBorderColor(.4, .4, .4, 1)

local pages, tabs, tabOrder = {}, {}, {}
local currentPage

local function UpdateScrollBar(page)
	if not page.scrollName then return end
	page:UpdateScrollChildRect()
	local bar = getglobal(page.scrollName .. "ScrollBar")
	if not bar then return end
	local need = (page.child:GetHeight() or 0) > (page:GetHeight() or 0) + 1
	if need then bar:Show() else bar:Hide(); bar:SetValue(0) end
end

local function ShowPage(key)
	-- hide the others first: a template tab closing puts the Designer away,
	-- and must not do that after the new tab has taken it
	for k, p in pairs(pages) do if k ~= key then p:Hide() end end
	if pages[key] then pages[key]:Show() end
	for _, t in pairs(tabs) do
		if t.key == key or t.pageKey == key then t:SetChecked(1) else t:SetChecked(nil) end
	end
	currentPage = key
	local page = pages[key]
	if page then
		if page.RefreshAll then page.RefreshAll() end
		UpdateScrollBar(page)
	end
end

-- A list that scrolls when its content is taller than the space it has
local function CreateScroll(parent, top, bottom)
	local name = NewName("Scroll")
	local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, top or -8)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, bottom or 8)
	scroll.scrollName = name
	scroll.scrollBarHideable = 1  -- the stock template hides the bar when nothing scrolls
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(CW + 16); child:SetHeight(100)
	scroll:SetScrollChild(child)
	scroll.child = child
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function()
		local bar = getglobal(this.scrollName .. "ScrollBar")
		if bar and bar:IsShown() then bar:SetValue(bar:GetValue() - arg1 * 40) end
	end)
	scroll.controls = {}
	scroll.RefreshAll = function()
		for i = 1, table.getn(scroll.controls) do
			local c = scroll.controls[i]
			if c.Refresh then c.Refresh() end
		end
	end
	return scroll
end

-- A page that scrolls when its content is taller than the inset
local function CreatePage(key)
	local scroll = CreateScroll(inset)
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

local function SpecTheme()
	local settings = CurrentSpec()
	return settings.theme or SHPlatesDB.theme
end

local function UpdateStatusLine()
	local settings, sig = CurrentSpec()
	if not activeThemeName then
		statusLine:SetText("No theme  |cff888888(build " .. sig .. ")|r")
		portrait:SetVertexColor(.55, .55, .55)  -- dimmed while plates are plain
		return
	end
	portrait:SetVertexColor(1, 1, 1)
	local _, _, family = string.find(activeThemeName, "^(.-)/")
	local mode = activeRole
	if settings.role ~= "Tank" and settings.role ~= "DPS" then mode = mode .. " (Auto)" end
	statusLine:SetText("|cffffffff" .. (family or activeThemeName) .. "|r theme,  |cffffffff" ..
		mode .. "|r mode  |cff888888(build " .. sig .. ")|r")
end

-------------------------------------------------------------------------------
-- Theme pages (Tank and DPS tabs), built from the theme's own list of options
-------------------------------------------------------------------------------
local function BuildThemeSection(page, child, y, themeName)
	local theme = SHPlatesThemeList[themeName]
	local vars = theme and theme.vars
	local c, h
	if not (theme and vars and theme.optionsSchema) then return y end
	local schema = theme.optionsSchema
	for i = 1, table.getn(schema) do
		local item = schema[i]
		local key = item.key
		local control
		h = nil
		if item.type == "header" then
			y = y - 8
			control, h = CreateHeader(child, item.text, y)
			control = nil
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
				function(r, g, b) local col = vars[key]; col.r, col.g, col.b = r, g, b; Changed(themeName) end)
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
		if control then AddControl(page, control) end
		y = y - (h or 0)
	end
	return y
end

-------------------------------------------------------------------------------
-- Which template the Display, Size and Style and Designer tabs edit. Every
-- template keeps its own settings; this picks Tank or DPS of the current theme.
-------------------------------------------------------------------------------
local editTemplate   -- the template whose tab is open ("Grey/DPS"...)
local function EditTheme()
	return (editTemplate and SHPlatesThemeList[editTemplate]) or SHPlates:GetActiveTheme()
end
local noneVars = {}
-- the settings being edited
local function EV()
	local th = EditTheme()
	if th and th.vars then return th.vars end
	-- theme "None": a scratch copy, nothing to save to
	for k, v in pairs(TEMPLATE_DEFAULTS) do
		if noneVars[k] == nil then if type(v) == "table" then noneVars[k] = copytable(v) else noneVars[k] = v end end
	end
	return noneVars
end

-------------------------------------------------------------------------------
-- General: talent build, theme, mode, plate behavior
-------------------------------------------------------------------------------
local buildText

local function ConfirmReset()
	if StaticPopupDialogs and StaticPopup_Show then
		StaticPopupDialogs["SHPLATES_RESET"] = {
			text = "Reset every SHPlates setting on this character and reload your UI?",
			button1 = YES or "Yes", button2 = NO or "No",
			OnAccept = function() SHPlatesDB = nil; ReloadUI() end,
			timeout = 0, whileDead = 1, hideOnEscape = 1,
		}
		StaticPopup_Show("SHPLATES_RESET")
	else
		SHPlatesDB = nil; ReloadUI()
	end
end

local function BuildGeneralPage(page)
	local child = page.child
	local y = -6
	local c, h
	local families = GetThemeFamilies()

	c, h = CreateHeader(child, "This talent build", y); y = y - h
	buildText = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	buildText:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
	buildText:SetWidth(CW - 8)
	buildText:SetJustifyH("LEFT")
	y = y - 46

	c, h = CreateButtonRow(child, "Theme", y, families,
		function()
			local current = SpecTheme()
			for i = 1, table.getn(families) do if families[i] == current then return i end end
			return 1
		end,
		function(v) SetSpecSetting("theme", families[v]); ApplyAll(true); SHPlates.RefreshConfigTabs() end)
	AddControl(page, c); y = y - h

	local roles = { "Auto", "Tank", "DPS" }
	local roleKeys = { "AUTO", "Tank", "DPS" }
	c, h = CreateButtonRow(child, "Mode", y, roles,
		function()
			local settings = CurrentSpec()
			for i = 1, 3 do if roleKeys[i] == settings.role then return i end end
			return 1
		end,
		function(v) SetSpecSetting("role", roleKeys[v]); ApplyAll(true) end,
		{ "Tank in Defensive Stance, Bear Form or Righteous Fury, DPS otherwise.",
		  "Always use the Tank settings with this build.",
		  "Always use the DPS settings with this build." })
	AddControl(page, c); y = y - h
	c, h = CreateTip(child, "Saved per talent build. Swap specs and SHPlates swaps with you.", y); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Raid marks", y); y = y - h
	c, h = CreateTip(child, "Set a key for each mark under Key Bindings > SHPlates. " ..
		"Marks work solo too, and only you see them.", y, 2); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Other addons", y); y = y - h
	c, h = CreateCheck(child, "Turn off pfUI's nameplates", y,
		function() return SHPlatesDB.hidePfUIPlates end,
		function(v) SHPlatesDB.hidePfUIPlates = v
			if v then SHPlates.Conflicts.KillPfUIPlates()
			else C.print("pfUI's nameplates come back after a /reload.") end end,
		"Keeps pfUI from drawing its own plates on top of SHPlates. Unchecking needs a /reload.")
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Turn off ShaguTweaks' nameplate tweaks", y,
		function() return SHPlatesDB.hideShaguPlates end,
		function(v) SHPlatesDB.hideShaguPlates = v
			if v then SHPlates.Conflicts.KillShaguPlates()
			else C.print("ShaguTweaks' nameplate tweaks come back after a /reload.") end end,
		"Stops ShaguTweaks' class colors, scale, castbar and dark border on the game's plates, " ..
		"which would otherwise fight with SHPlates. Unchecking needs a /reload.")
	AddControl(page, c); y = y - h

	local showBtn = Button(child, "Show Nameplates", 150)
	showBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y - 6)
	showBtn:SetScript("OnClick", function()
		if ShowNameplates then ShowNameplates() end
		if ShowFriendNameplates then ShowFriendNameplates() end
		SHPlates:ForceUpdate()
	end)
	Tooltip(showBtn, "Show Nameplates", "Turns the game's nameplates on, in case they were switched off.")
	local resetBtn = Button(child, "Reset Everything", 150)
	resetBtn:SetPoint("LEFT", showBtn, "RIGHT", 10, 0)
	resetBtn:SetScript("OnClick", ConfirmReset)
	Tooltip(resetBtn, "Reset Everything", "Puts every SHPlates setting on this character back to default and reloads. You'll be asked first.")
	y = y - 36

	child:SetHeight(-y + 10)

	page.RefreshAllBase = page.RefreshAll
	page.RefreshAll = function()
		page.RefreshAllBase()
		local _, sig, label, saved = CurrentSpec()
		local threat = (GetTime() - Data.threat.targetStamp < 30) and "|cff00ff00receiving|r" or "|cff888888none yet (needs a group)|r"
		buildText:SetText(
			"Talents: |cffffffff" .. (label ~= "" and label or "none") .. "|r" ..
			(saved and "" or "  |cff888888(not set up yet)|r") .. "\n" ..
			"SuperWoW: " .. (C.HasSuperWoW and "|cff00ff00yes|r" or "|cffff4040no (limited)|r") ..
			"    Nampower: " .. (C.HasNampower and "|cff00ff00yes|r" or "|cffff4040no|r") ..
			"\nServer threat: " .. threat)
	end
end

-------------------------------------------------------------------------------
-- Display: which plates show, text, health bar colors
-------------------------------------------------------------------------------
local function BuildDisplaySection(page, child, y)
	local c, h
	c, h = CreateHeader(child, "Nameplates", y); y = y - h
	c, h = CreateCheck(child, "Allow overlapping nameplates", y,
		function() return EV().overlap end,
		function(v) EV().overlap = v; ApplyAll(true) end,
		"Plates stay over their unit instead of spreading out to avoid each other.")
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Click-through plates", y,
		function() return EV().clickThrough end,
		function(v) EV().clickThrough = v; ApplyAll(true) end,
		"Plates ignore the mouse, so clicks go to the world behind them.")
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Show plates only in combat", y,
		function() return EV().autohide end,
		function(v) EV().autohide = v; ApplyAll(true) end,
		"Turns nameplates on when a fight starts and off when it ends.")
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Which plates show", y); y = y - h
	c, h = CreateCheck(child, "Hide friendly plates", y,
		function() return EV().hideFriendly end,
		function(v) EV().hideFriendly = v; SHPlates:ForceUpdate() end,
		"Hides friendly players and NPCs. Players only count as enemies when you can attack them.")
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Hide critters", y,
		function() return EV().hideCritters end,
		function(v) EV().hideCritters = v; SHPlates:ForceUpdate() end,
		"Hides rabbits, rats, squirrels and other critters.")
	AddControl(page, c); y = y - h
	c, h = CreateTip(child, "A hidden plate still shows while it's your target. Without SuperWoW, " ..
		"critters are learned when you target or mouse over them.", y, 2); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Levels", y); y = y - h
	c, h = CreateCheck(child, "Hide unit levels", y,
		function() return EV().hideLevel end,
		function(v) EV().hideLevel = v; ApplyAll(true) end,
		"Takes the level number off every plate, in every theme. Boss skulls still show.")
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Cast bars", y); y = y - h
	c, h = CreateCheck(child, "Hide cast bars", y,
		function() return EV().hideCastbars end,
		function(v) EV().hideCastbars = v; ApplyAll(true) end,
		"Takes cast bars and spell names off every plate, in every theme.")
	AddControl(page, c); y = y - h
	if not C.HasSuperWoW then
		c, h = CreateTip(child, "Without SuperWoW, casts come from the combat log: a cast shows on every plate with that name.", y, 2); y = y - h
	end

	y = y - 4
	c, h = CreateHeader(child, "Health bar colors", y); y = y - h
	c, h = CreateCheck(child, "Class colors for enemy players", y,
		function() return EV().classColorEnemies end,
		function(v) EV().classColorEnemies = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Plain red for PvP-flagged enemies", y,
		function() return EV().noClassColorPvP end,
		function(v) EV().noClassColorPvP = v; SHPlates:ForceUpdate() end,
		"Enemy players flagged for PvP skip the class color and show plain red.")
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Class colors for friendly players", y,
		function() return EV().classColorFriends end,
		function(v) EV().classColorFriends = v; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheckColor(child, "Color mobs tapped by others", y,
		function() return EV().tappedColorOn end,
		function(v) EV().tappedColorOn = v; SHPlates:ForceUpdate() end,
		function() return EV().tappedColor end,
		function(r, g, b) local col = EV().tappedColor; col.r, col.g, col.b = r, g, b; SHPlates:ForceUpdate() end,
		"Mobs tagged by someone outside your group get this color.")
	AddControl(page, c); y = y - h
	c, h = CreateCheckColor(child, "Color stunned mobs", y,
		function() return EV().stunColorOn end,
		function(v) EV().stunColorOn = v; SHPlates:ForceUpdate() end,
		function() return EV().stunColor end,
		function(r, g, b) local col = EV().stunColor; col.r, col.g, col.b = r, g, b; SHPlates:ForceUpdate() end)
	AddControl(page, c); y = y - h

	return y
end

-------------------------------------------------------------------------------
-- Size and Style: sizes, friendly plates, colors (on top of any theme)
-------------------------------------------------------------------------------
local function BuildSizeSection(page, child, y)
	local c, h
	local function Restyle() ApplyAll(true) end
	local function Slider(label, key, minv, maxv)
		c, h = CreateSlider(child, label, y, minv, maxv, .05, true,
			function() return EV()[key] end,
			function(v) EV()[key] = v; Restyle() end)
		AddControl(page, c); y = y - h
	end
	local function CheckColor(label, onKey, colorKey, tip)
		c, h = CreateCheckColor(child, label, y,
			function() return EV()[onKey] end,
			function(v) EV()[onKey] = v; Restyle() end,
			function() return EV()[colorKey] end,
			function(r, g, b) local col = EV()[colorKey]; col.r, col.g, col.b = r, g, b; Restyle() end, tip)
		AddControl(page, c); y = y - h
	end

	c, h = CreateHeader(child, "Enemy and neutral plates", y); y = y - h
	Slider("Width", "barWidth", .5, 2)
	Slider("Height", "barHeight", .5, 2)
	c, h = CreateSlider(child, "Text size", y, -6, 8, 1, false,
		function() return EV().fontSizeOffset or 0 end,
		function(v) EV().fontSizeOffset = v; Restyle() end)
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Friendly plates", y); y = y - h
	Slider("Width", "friendlyWidth", .3, 2)
	Slider("Height", "friendlyHeight", .3, 2)
	c, h = CreateSlider(child, "Text size", y, -6, 8, 1, false,
		function() return EV().friendlyFontOffset or 0 end,
		function(v) EV().friendlyFontOffset = v; Restyle() end)
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Cast bars", y); y = y - h
	Slider("Width", "castWidth", .5, 2)
	Slider("Height", "castHeight", .5, 2)
	c, h = CreateSlider(child, "Text size", y, -6, 8, 1, false,
		function() return EV().castFontOffset or 0 end,
		function(v) EV().castFontOffset = v; Restyle() end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Hide the spell icon", y,
		function() return EV().hideSpellIcon end,
		function(v) EV().hideSpellIcon = v; Restyle() end)
	AddControl(page, c); y = y - h
	CheckColor("Custom cast bar color", "castColorOn", "castColor")

	y = y - 4
	c, h = CreateHeader(child, "Debuffs", y); y = y - h
	-- the theme's own debuff widget switch (WidgetDebuff): off means no icons and no timers
	c, h = CreateCheck(child, "Hide debuffs", y,
		function() return not EV().WidgetDebuff end,
		function(v) EV().WidgetDebuff = not v; Restyle() end,
		"Takes the debuff icons and their timers off the plates.")
	AddControl(page, c); y = y - h
	Slider("Icon size", "debuffScale", .5, 2)
	c, h = CreateCheck(child, "Hide debuff timers", y,
		function() return EV().hideDebuffTimers end,
		function(v) EV().hideDebuffTimers = v; Restyle() end)
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Text and colors", y); y = y - h
	c, h = CreateSlider(child, "Aggro holder name size", y, 6, 16, 1, "abs",
		function() return EV().holderFontSize or 8 end,
		function(v) EV().holderFontSize = v; Restyle() end)
	AddControl(page, c); y = y - h
	local fontNames = {}
	for i = 1, table.getn(SHPlates.FONTS) do fontNames[i] = SHPlates.FONTS[i][1] end
	c, h = CreateChoice(child, "Font", y, fontNames,
		function() return EV().fontFace or 1 end,
		function(v) EV().fontFace = v; ApplyAll(true) end)
	AddControl(page, c); y = y - h
	c, h = CreateChoice(child, "Health text position", y, { "Theme default", "Left", "Center", "Right" },
		function() return EV().healthTextAlign or 1 end,
		function(v) EV().healthTextAlign = v; Restyle() end)
	AddControl(page, c); y = y - h
	CheckColor("Custom health text color", "healthTextColorOn", "healthTextColor")
	CheckColor("Custom name color", "nameColorOn", "nameColor")
	CheckColor("Custom selection box color", "targetColorOn", "targetColor",
		"The box around your target's plate (turn on Selection Box further down this tab).")

	y = y - 6
	local resetBtn = Button(child, "Back to Theme Sizes", 170)
	resetBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y)
	resetBtn:SetScript("OnClick", function()
		for _, k in ipairs({ "barWidth", "barHeight", "castWidth", "castHeight", "friendlyWidth",
			"friendlyHeight", "debuffScale" }) do EV()[k] = 1 end
		EV().friendlyFontOffset = 0
		EV().fontSizeOffset = 0
		Restyle(); page.RefreshAll()
	end)
	Tooltip(resetBtn, "Back to Theme Sizes", "Puts every size on this tab back to 100%. Colors and checkboxes stay as they are.")
	y = y - 34

	return y
end

-------------------------------------------------------------------------------
-- Designer: drag the pieces of a sample plate. The sample is a fake vanilla
-- plate that SHPlates styles exactly like a real one, so what you see is what
-- your plates get. Offsets are saved per theme and mode (Grey/DPS, Neon/Tank...).
-------------------------------------------------------------------------------
local PIECES = {
	{ id = "cast", label = "Cast bar" },
	{ id = "name", label = "Name" },
	{ id = "health", label = "Health text" },
	{ id = "spell", label = "Spell name" },
	{ id = "level", label = "Level" },
	{ id = "debuffs", label = "Debuffs" },
	{ id = "note", label = "Mob note" },
	{ id = "spellicon", label = "Spell icon" },
	{ id = "raid", label = "Raid icon" },
	{ id = "class", label = "Class icon" },
	{ id = "elite", label = "Elite star" },
	{ id = "tug", label = "Threat line" },
	{ id = "holder", label = "Aggro holder name" },
	{ id = "wheel", label = "Threat wheel" },
	{ id = "tanked", label = "Tanked icon" },
}

-- Clicking a piece in the Designer scrolls its tab to these sections
local PIECE_SECTION = {
	cast = "Cast bars", spellicon = "Cast bars", spell = "Cast bars",
	debuffs = "Debuffs",
	name = "Text and colors", health = "Text and colors", holder = "Text and colors",
	level = "Levels",
	class = "Widgets", note = "Widgets", tug = "Widgets", wheel = "Widgets", tanked = "Widgets",
}

local function PieceObject(ext, id, th)
	local hk = th and th.healthTextKey
	local v, w = ext.visual, ext.widgets
	if id == "name" then return v.name
	elseif id == "level" then return v.level
	elseif id == "health" then return hk and v[hk]
	elseif id == "spell" then return hk and v[hk == "specialText" and "specialText2" or "specialText"]
	elseif id == "raid" then return v.raidicon
	elseif id == "cast" then return ext.bars.castbar
	elseif id == "spellicon" then return v.spellicon
	elseif id == "debuffs" then return w.AuraIcon or w.WidgetDebuff
	elseif id == "class" then return w.ClassWidget
	elseif id == "note" then return w.NoteWidget
	elseif id == "elite" then return v.eliteicon
	elseif id == "tug" then return w.WidgetTug
	elseif id == "holder" then return w.WidgetTug and w.WidgetTug.TargetText
	elseif id == "wheel" then return w.WidgetWheel
	elseif id == "tanked" then return w.WidgetTanked
	end
end

-- Screen rectangle of what a piece actually shows, so the Designer's boxes
-- hug the visible part instead of the frame it lives in
local function ScreenRect(r)
	if not (r and r.GetLeft) then return nil end
	local l, rt, t, b = r:GetLeft(), r:GetRight(), r:GetTop(), r:GetBottom()
	if not (l and rt and t and b) then return nil end
	local owner = r.GetEffectiveScale and r or (r.GetParent and r:GetParent())
	local sc = owner and owner.GetEffectiveScale and owner:GetEffectiveScale() or 1
	return l * sc, rt * sc, t * sc, b * sc, sc
end

-- text: only the string itself, placed by its justification
local function TextRect(fs)
	local l, r, t, b, sc = ScreenRect(fs)
	if not l then return nil end
	local w = (fs.GetStringWidth and fs:GetStringWidth() or 0) * sc
	if w <= 0 then w = 12 * sc end   -- empty text: a small box to grab
	local _, size = fs:GetFont()
	local h = ((size or 9) + 2) * sc
	local jh = fs.GetJustifyH and fs:GetJustifyH() or "CENTER"
	local jv = fs.GetJustifyV and fs:GetJustifyV() or "MIDDLE"
	local x
	if jh == "LEFT" then x = l elseif jh == "RIGHT" then x = r - w else x = (l + r - w) / 2 end
	local y
	if jv == "TOP" then y = t elseif jv == "BOTTOM" then y = b + h else y = (t + b + h) / 2 end
	return x, x + w, y, y - h
end

local function Union(rects)
	local l, r, t, b
	for i = 1, table.getn(rects) do
		local q = rects[i]
		if q and q[1] then
			if not l or q[1] < l then l = q[1] end
			if not r or q[2] > r then r = q[2] end
			if not t or q[3] > t then t = q[3] end
			if not b or q[4] < b then b = q[4] end
		end
	end
	return l, r, t, b
end

local function Rect(r) return { ScreenRect(r) } end

local function ContentRect(id, obj)
	if id == "name" or id == "level" or id == "health" or id == "spell" or id == "holder" then
		return TextRect(obj)
	elseif id == "note" then
		return TextRect(obj.Text)
	elseif id == "debuffs" then
		local list = {}
		for i = 1, table.getn(obj.AuraFrames or {}) do
			local f = obj.AuraFrames[i]
			if f:IsShown() then table.insert(list, Rect(f)) end
		end
		return Union(list)
	elseif id == "tug" then
		local parts = { Rect(obj.Line), Rect(obj.Middle), Rect(obj.Dot) }
		-- the Designer's sample also shows the other half of the line
		if obj.Line2 and obj.Line2:IsShown() then
			table.insert(parts, Rect(obj.Line2)); table.insert(parts, Rect(obj.Dot2))
		end
		local l, r = Union(parts)
		local _, _, t, b, sc = ScreenRect(obj.Middle)
		if not (l and t) then return nil end
		local cy = (t + b) / 2
		-- the art is 32 tall, the line itself is thin
		return l + 10 * sc, r - 10 * sc, cy + 5 * sc, cy - 5 * sc
	elseif id == "wheel" then
		return ScreenRect(obj.ThreatIcon)
	elseif id == "tanked" then
		if obj.tank and obj.tank:IsShown() then return ScreenRect(obj.tank) end
		return ScreenRect(obj.squishy)
	elseif id == "class" then
		return ScreenRect(obj.Icon)
	end
	return ScreenRect(obj)
end

-- does a piece show anything right now?
local TEXT_PIECES = { name = true, level = true, health = true, spell = true, holder = true }
local function Shows(id, obj)
	if obj.GetAlpha and obj:GetAlpha() == 0 then return false end
	local fs = (id == "note") and obj.Text or (TEXT_PIECES[id] and obj)
	if fs and fs.GetText then
		local text = fs:GetText()
		if not text or text == "" then return false end
	end
	return true
end

-- shown, and every parent shown (works for frames, textures and text)
local function Visible(obj)
	if obj.IsVisible then return obj:IsVisible() end
	local o = obj
	while o do
		if o.IsShown and not o:IsShown() then return false end
		o = o.GetParent and o:GetParent()
	end
	return true
end

-- The Designer block sits at the top of every template tab (one shared
-- block, moved into whichever tab is open)
local DESIGNER_H = 214
local function BuildDesigner(page)
	local box = CreateFrame("Frame", nil, page)
	box:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -2)
	box:SetWidth(CW); box:SetHeight(160)
	box:SetBackdrop(BOX_BACKDROP)
	box:SetBackdropColor(.12, .12, .12, .9)
	box:SetBackdropBorderColor(.4, .4, .4, 1)

	-- the stage is scaled up so pieces are easy to grab
	local stage = CreateFrame("Frame", nil, box)
	stage:SetWidth(1); stage:SetHeight(1)
	stage:SetPoint("CENTER", box, "CENTER", 0, 0)
	stage:SetScale(1.6)

	-- a plate built the way the 1.12 client builds one
	local plate = CreateFrame("Button", nil, stage)
	plate:SetWidth(128); plate:SetHeight(32)
	plate:SetPoint("CENTER", stage, "CENTER", 0, 0)
	local health = CreateFrame("StatusBar", nil, plate)
	health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	health:SetMinMaxValues(0, 100); health:SetValue(65)
	health:SetStatusBarColor(1, 0, 0)
	local border = plate:CreateTexture(nil, "BORDER")
	border:SetTexture("Interface\\Tooltips\\Nameplate-Border")
	local glow = plate:CreateTexture(nil, "OVERLAY"); glow:Hide()
	local name = plate:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); name:SetText("Target Dummy")
	local level = plate:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"); level:SetText("60")
	level:SetTextColor(1, 1, 0)
	local skull = plate:CreateTexture(nil, "ARTWORK"); skull:Hide()
	local raid = plate:CreateTexture(nil, "ARTWORK")
	raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	raid:SetTexCoord(.75, 1, .25, .5)   -- skull
	plate:Hide()
	page.preview = plate
	local problem = box:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	problem:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, 8)
	problem:SetWidth(CW - 16); problem:SetJustifyH("LEFT")

	-- selected piece and its offset
	local selected
	local selText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	selText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -8)
	selText:SetWidth(CW - 8); selText:SetJustifyH("LEFT")

	-- the theme the sample is drawn with: the mode picked above
	local function Theme() return plate.previewTheme or SHPlates:GetActiveTheme() end
	local function Layout(create) return SHPlates.GetLayout(Theme(), create) end
	local function GetOffset(id)
		local l = Layout()
		local o = l and l[id]
		if o then return o.x, o.y end
		return 0, 0
	end
	local function SetOffset(id, x, y)
		local l = Layout(true)
		if not l then return end
		if x == 0 and y == 0 then l[id] = nil else l[id] = { x = x, y = y } end
	end
	local function Refresh(all)
		SHPlates.RestylePlate(plate)
		if all then SHPlates:ForceUpdate() end
		if selected then
			local x, y = GetOffset(selected.id)
			selText:SetText("Selected: |cffffffff" .. selected.label .. "|r   moved " .. x .. ", " .. y)
		else
			selText:SetText("Drag a piece to move it, click to select it, right-click to put it back.")
		end
	end

	-- one handle over each piece
	local handles = {}
	-- scroll the open tab's list to a piece's settings and flash the header
	local flash
	local function JumpTo(id)
		local list = page:GetParent() and page:GetParent().list
		local name = PIECE_SECTION[id]
		local sec = list and name and list.child.sections and list.child.sections[name]
		if not sec then return end
		local bar = getglobal(list.scrollName .. "ScrollBar")
		if bar then
			local lo, hi = bar:GetMinMaxValues()
			local v = sec.y - 4
			if hi and v > hi then v = hi end
			if lo and v < lo then v = lo end
			bar:SetValue(v)
		end
		if flash then flash.fs:SetTextColor(1, .82, 0) end
		sec.fs:SetTextColor(1, 1, 1)
		flash = { fs = sec.fs, untilTime = GetTime() + 1.2 }
	end

	local function Select(h)
		selected = h and h.piece
		for i = 1, table.getn(handles) do
			local o = handles[i]
			if o == h then o:SetBackdropBorderColor(1, .82, 0, 1) else o:SetBackdropBorderColor(1, 1, 1, .25) end
		end
		Refresh()
		if selected then JumpTo(selected.id) end
	end
	for i = 1, table.getn(PIECES) do
		local h = CreateFrame("Button", nil, box)
		h:SetFrameLevel(box:GetFrameLevel() + 30 + i)
		h:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 } })
		h:SetBackdropBorderColor(1, 1, 1, .25)
		h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		h.piece = PIECES[i]
		h:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_TOP")
			GameTooltip:SetText(this.piece.label)
			GameTooltip:AddLine("Drag to move. Right-click to put it back.", 1, 1, 1)
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		h:SetScript("OnMouseDown", function()
			Select(this)
			if arg1 == "RightButton" then
				SetOffset(this.piece.id, 0, 0)
				Refresh(true)
				return
			end
			local cx, cy = GetCursorPosition()
			this.x0, this.y0 = cx, cy
			this.ox, this.oy = GetOffset(this.piece.id)
			this.dragging = true
		end)
		h:SetScript("OnMouseUp", function()
			if this.dragging then this.dragging = false; Refresh(true) end
		end)
		h:Hide()
		handles[i] = h
	end

	-- nudge buttons and resets
	local function Nudge(dx, dy)
		if not selected then return end
		local x, y = GetOffset(selected.id)
		SetOffset(selected.id, x + dx, y + dy)
		Refresh(true)
	end
	local arrows = { { "<", -1, 0 }, { "^", 0, 1 }, { "v", 0, -1 }, { ">", 1, 0 } }
	local prev
	for i = 1, 4 do
		local a = arrows[i]
		local b = Button(page, a[1], 28)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else b:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -26) end
		local dx, dy = a[2], a[3]
		b:SetScript("OnClick", function() Nudge(dx, dy) end)
		prev = b
	end
	Tooltip(prev, "Nudge", "Moves the selected piece one step at a time.")
	local resetPiece = Button(page, "Reset Piece", 100)
	resetPiece:SetPoint("LEFT", prev, "RIGHT", 8, 0)
	resetPiece:SetScript("OnClick", function()
		if selected then SetOffset(selected.id, 0, 0); Refresh(true) end
	end)
	local resetAll = Button(page, "Reset All", 80)
	resetAll:SetPoint("LEFT", resetPiece, "RIGHT", 4, 0)
	resetAll:SetScript("OnClick", function()
		local th = Theme()
		if SHPlatesDB.layout and th and th.family then SHPlatesDB.layout[th.family .. "/" .. (th.mode or "")] = nil end
		Refresh(true)
	end)
	Tooltip(resetAll, "Reset All", "Puts every piece back where the theme had it, for this theme and mode.")

	-- keep handles on their pieces, and drag
	local tick = 0
	local function Track()
		if flash and GetTime() > flash.untilTime then flash.fs:SetTextColor(1, .82, 0); flash = nil end
		local ext = plate.extended
		if not ext then return end
		tick = tick + (arg1 or 0)
		for i = 1, table.getn(handles) do
			local h = handles[i]
			if h.dragging then
				local cx, cy = GetCursorPosition()
				local sc = ext:GetEffectiveScale()
				local x = math.floor((h.ox + (cx - h.x0) / sc) * 2 + .5) / 2
				local yy = math.floor((h.oy + (cy - h.y0) / sc) * 2 + .5) / 2
				local ox, oy = GetOffset(h.piece.id)
				if x ~= ox or yy ~= oy then SetOffset(h.piece.id, x, yy); Refresh() end
			end
			local obj = PieceObject(ext, h.piece.id, Theme())
			-- nothing to grab when the piece is hidden, faded out, or its text is empty
			if obj and not Shows(h.piece.id, obj) then obj = nil end
			local l, r, t, b
			if obj and Visible(obj) then l, r, t, b = ContentRect(h.piece.id, obj) end
			if l and r and t and b then
				local he = h:GetEffectiveScale()
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / he - 2, t / he + 2)
				h:SetWidth((r - l) / he + 4)
				h:SetHeight((t - b) / he + 4)
				h:Show()
			elseif obj and Visible(obj) then
				-- couldn't measure it: cover the whole piece
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", obj, "TOPLEFT", -2, 2)
				h:SetPoint("BOTTOMRIGHT", obj, "BOTTOMRIGHT", 2, -2)
				h:Show()
			else h:Hide() end
		end
		-- keep the sample alive (widgets, debuff timers)
		if tick > 1 then tick = 0; SHPlates.RestylePlate(plate) end
	end
	local reported = false
	page:SetScript("OnUpdate", function()
		local ok, err = pcall(Track)
		if not ok and not reported then
			reported = true
			problem:SetText("Designer error: " .. tostring(err))
			C.print("designer: " .. tostring(err))
		end
	end)

	-- draw the sample with this tab's template
	local function SetTemplate(name)
		local th = SHPlatesThemeList[name]
		if not th then return end
		if th == SHPlates:GetActiveTheme() then plate.previewTheme = nil
		else plate.previewTheme = SHPlates.PrepareTheme(name) end
		-- each template has its own widgets: rebuild them
		local ext = plate.extended
		if ext and ext.widgets then
			for k, w in pairs(ext.widgets) do
				if type(w) == "table" and w.Hide then w:Hide() end
				ext.widgets[k] = nil
			end
		end
		plate:Hide(); plate:Show()
		Select(nil)
	end
	page.SetTemplate = SetTemplate

	page:SetScript("OnShow", function()
		-- if the sample can't be built, say why instead of showing an empty box
		local ok, err = pcall(SHPlates.AdoptPreviewPlate, plate)
		if ok then ok, err = pcall(plate.Show, plate) end
		if ok and page.template then ok, err = pcall(SetTemplate, page.template) end
		if ok then problem:SetText("")
		else
			problem:SetText("The sample plate couldn't be drawn: " .. tostring(err))
			C.print("designer: " .. tostring(err))
		end
	end)
	page:SetScript("OnHide", function()
		for i = 1, table.getn(handles) do handles[i].dragging = false end
		plate:Hide()
	end)
end

-------------------------------------------------------------------------------
-- Notes: learned casts, other tanks, mob notes
-------------------------------------------------------------------------------
local learnedText

local function BuildNotesPage(page)
	local child = page.child
	local y = -6
	local c, h

	c, h = CreateHeader(child, "Casts you can't interrupt", y); y = y - h
	learnedText = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	learnedText:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
	learnedText:SetWidth(CW - 8); learnedText:SetJustifyH("LEFT")
	y = y - 32
	c, h = CreateCheck(child, "Learn from group members' interrupts", y,
		function() return SHPlatesDB.learnFromGroup end,
		function(v) SHPlatesDB.learnFromGroup = v end)
	AddControl(page, c); y = y - h
	c, h = CreateCheck(child, "Say in chat when a new one is learned", y,
		function() return SHPlatesDB.announceLearned end,
		function(v) SHPlatesDB.announceLearned = v end)
	AddControl(page, c); y = y - h
	local listBtn = Button(child, "List in Chat", 150)
	listBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y - 6)
	listBtn:SetScript("OnClick", function() SHPlatesSlashCommands.learned() end)
	local forgetBtn = Button(child, "Forget All", 150)
	forgetBtn:SetPoint("LEFT", listBtn, "RIGHT", 10, 0)
	forgetBtn:SetScript("OnClick", function() SHPlates.Interrupts.Forget(); page.RefreshAll(); SHPlates:Update() end)
	y = y - 38

	c, h = CreateHeader(child, "Other tanks", y); y = y - h
	c, h = CreateList(child, "One name per line. They count as tanks for threat colors.", y,
		function() return SetToLines(SHPlatesDB.tankNames) end,
		function(text) LinesToSet(text, SHPlatesDB.tankNames); SHPlates:Update() end, 64)
	AddControl(page, c); y = y - h

	y = y - 4
	c, h = CreateHeader(child, "Mob notes", y); y = y - h
	c, h = CreateList(child, "One per line:  Mob Name = note text", y,
		function() return SetToLines(SHPlatesDB.notes, true) end,
		function(text) LinesToSet(text, SHPlatesDB.notes, true); SHPlates:Update() end, 96)
	AddControl(page, c); y = y - h
	c, h = CreateTip(child, "Turn on Mob Notes in a template's tab to see them on plates.", y); y = y - h

	child:SetHeight(-y + 10)

	page.RefreshAllBase = page.RefreshAll
	page.RefreshAll = function()
		page.RefreshAllBase()
		learnedText:SetText("Learned so far: |cffffffff" .. SHPlates.Interrupts.Count() ..
			"|r\nThese casts get the \"can't interrupt\" cast border.")
	end
end

-------------------------------------------------------------------------------
-- Side tabs
-------------------------------------------------------------------------------
local TAB_GENERAL = { key = "general", tip = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01" }
local TABS_END = {
	{ key = "notes", tip = "Casts, Tanks and Notes", icon = "Interface\\Icons\\INV_Misc_Note_01" },
	{ key = "share", tip = "Share", icon = "Interface\\Icons\\INV_Scroll_03" },
}
-- template tab icons: by theme and mode, with a fallback for themes added later
local TEMPLATE_ICONS = {
	["Grey/Tank"] = "Ability_Warrior_DefensiveStance", ["Grey/DPS"] = "Ability_DualWield",
	["Neon/Tank"] = "Spell_Holy_DevotionAura", ["Neon/DPS"] = "Spell_Nature_Lightning",
	Tank = "INV_Shield_06", DPS = "INV_Sword_04",
}

local function LayoutTabs()
	local n = 0
	for i = 1, table.getn(tabOrder) do
		local t = tabOrder[i]
		if t:IsShown() then
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", Config, "TOPLEFT", W - 4, -48 - n * 48)
			n = n + 1
		end
	end
end

local function CreateTab(info)
	local t = CreateFrame("CheckButton", NewName("Tab"), Config)
	t:SetWidth(32); t:SetHeight(32)
	local bg = t:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	bg:SetWidth(64); bg:SetHeight(64)
	bg:SetPoint("TOPLEFT", t, "TOPLEFT", -3, 11)
	t:SetNormalTexture(info.icon)
	t:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	AddBlend(t:GetHighlightTexture())
	t:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	AddBlend(t:GetCheckedTexture())
	t.key = info.key
	t.tip = info.tip
	t:SetScript("OnClick", function() ShowPage(this.pageKey or this.key) end)
	t:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(this.tip)
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tabs[info.key] = t
	table.insert(tabOrder, t)
	return t
end

-- Tab tooltips say which template is in use right now
function SHPlates.RefreshConfigTabs()
	local active = SHPlates:GetActiveTheme()
	for _, t in pairs(tabs) do
		if t.template then
			local th = SHPlatesThemeList[t.template]
			t.tip = string.gsub(t.template, "/", ": ") .. ((th == active) and "  |cff888888(in use now)|r" or "")
		end
	end
end

-- One tab per template: the Designer on top, every setting of that template
-- in a scrolling list under it
local designer
local function BuildTemplatePage(name)
	local key = "tpl:" .. name
	-- full inset width, so the list below is as wide as on the other tabs
	local page = CreateFrame("Frame", nil, inset)
	page:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, -8)
	page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 8)
	page:Hide()
	pages[key] = page
	local list = CreateScroll(page, -DESIGNER_H, 0)
	page.list = list
	list.controls = list.controls or {}
	local child = list.child
	local y = -6
	y = BuildDisplaySection(list, child, y)
	y = BuildSizeSection(list, child, y - 4)
	y = BuildThemeSection(list, child, y - 4, name)
	child:SetHeight(-y + 10)
	page.RefreshAll = function()
		list.RefreshAll()
		UpdateScrollBar(list)
	end
	page:SetScript("OnShow", function()
		editTemplate = name
		-- move the Designer in and point it at this template
		designer:Hide()
		designer:SetParent(page)
		designer:ClearAllPoints()
		designer:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
		designer:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
		designer:SetHeight(DESIGNER_H)
		designer.template = name
		designer:Show()
	end)
	-- leaving the tab puts the sample plate away
	page:SetScript("OnHide", function() designer:Hide() end)
	return key
end

local built = false
-------------------------------------------------------------------------------
-- Scale grip (bottom-right corner), the same as AutoSpam's.
-- Drag to scale the whole window, right-click to reset to 100%.
-------------------------------------------------------------------------------
local function SetWindowScale(s, absLeft, absTop)
	if s < MIN_SCALE then s = MIN_SCALE end
	if s > MAX_SCALE then s = MAX_SCALE end
	s = math.floor(s * 100 + .5) / 100
	if not absLeft then
		local eff = Config:GetEffectiveScale()
		absLeft = Config:GetLeft() * eff
		absTop = Config:GetTop() * eff
	end
	Config:SetScale(s)
	-- keep the top-left corner where it was on screen
	local eff = Config:GetEffectiveScale()
	Config:ClearAllPoints()
	Config:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", absLeft / eff, absTop / eff)
	SHPlatesDB.configScale = s
end

local function CreateScaleGrip()
	local g = CreateFrame("Button", nil, Config)
	g:SetWidth(16); g:SetHeight(16)
	g:SetPoint("BOTTOMRIGHT", Config, "BOTTOMRIGHT", -10, 10)
	g:SetFrameLevel(Config:GetFrameLevel() + 10)
	g:EnableMouse(true)
	g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	g:SetNormalTexture(SHPlates.MEDIA .. "SizeGrabber-Up")
	g:SetPushedTexture(SHPlates.MEDIA .. "SizeGrabber-Down")
	g:SetHighlightTexture(SHPlates.MEDIA .. "SizeGrabber-Highlight")
	g:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:AddLine("Right-click to reset", 1, 1, 1)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function()
		if not this.sizing then GameTooltip:Hide() end
	end)
	g:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" then
			local eff = Config:GetEffectiveScale()
			this.left = Config:GetLeft() * eff
			this.top = Config:GetTop() * eff
			this.sizing = true
			this:SetButtonState("PUSHED", 1)   -- stay pressed for the whole drag
		elseif arg1 == "RightButton" then
			SetWindowScale(1)
		end
	end)
	g:SetScript("OnMouseUp", function()
		if this.sizing then
			this.sizing = false
			this:SetButtonState("NORMAL")
			GameTooltip:Hide()
		end
	end)
	g:SetScript("OnUpdate", function()
		if not this.sizing then return end
		local cx, cy = GetCursorPosition()
		-- size the window so its bottom-right corner follows the cursor
		local wantEff = ((cx - this.left) / W + (this.top - cy) / H) / 2
		SetWindowScale(wantEff / UIParent:GetEffectiveScale(), this.left, this.top)
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("Scale: " .. math.floor(SHPlatesDB.configScale * 100 + .5) .. "%")
		GameTooltip:Show()
	end)
	return g
end

local function BuildConfig()
	if built then return end
	built = true
	CreateScaleGrip()
	-- saved per character, and left out of Share strings on purpose:
	-- window size depends on each person's screen
	Config:SetScale(SHPlatesDB.configScale or 1)
	BuildGeneralPage(CreatePage("general"))
	-- the shared Designer block (template tabs move it in when they open)
	designer = CreateFrame("Frame", nil, inset)
	designer:Hide()
	BuildDesigner(designer)
	-- a tab for every template, in a steady order (Grey before Neon, Tank before DPS)
	local names = {}
	for name, theme in pairs(SHPlatesThemeList) do
		if type(theme) == "table" and theme.family and type(theme.vars) == "table" then table.insert(names, name) end
	end
	table.sort(names, function(x, z)
		local fx, fz = SHPlatesThemeList[x].family, SHPlatesThemeList[z].family
		if fx ~= fz then return fx < fz end
		return (SHPlatesThemeList[x].mode == "Tank" and 0 or 1) < (SHPlatesThemeList[z].mode == "Tank" and 0 or 1)
	end)
	CreateTab(TAB_GENERAL)
	for i = 1, table.getn(names) do
		local name = names[i]
		local th = SHPlatesThemeList[name]
		local key = BuildTemplatePage(name)
		local icon = TEMPLATE_ICONS[name] or TEMPLATE_ICONS[th.mode or ""] or "INV_Misc_QuestionMark"
		local t = CreateTab({ key = key, tip = string.gsub(name, "/", ": "), icon = "Interface\\Icons\\" .. icon })
		t.template = name
	end
	BuildNotesPage(CreatePage("notes"))
	-- Share page: a plain frame, its text box scrolls on its own
	local share = CreateFrame("Frame", nil, inset)
	share:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -8)
	share:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -8, 8)
	share:Hide()
	CreateHeader(share, "Share your setup", -6)
	local body = CreateFrame("Frame", nil, share)
	body:SetPoint("TOPLEFT", share, "TOPLEFT", 8, -32)
	body:SetPoint("BOTTOMRIGHT", share, "BOTTOMRIGHT", -2, 0)
	SHPlates.Share.BuildPage(body)
	share.RefreshAll = body.RefreshAll
	pages.share = share
	for i = 1, table.getn(TABS_END) do CreateTab(TABS_END[i]) end
	LayoutTabs()
	SHPlates.RefreshConfigTabs()
	ShowPage("general")
end

Config:SetScript("OnShow", function() UpdateStatusLine() end)

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
	UpdateStatusLine()
end

-- Called by ApplyAll so an open window follows spec swaps
function SHPlates.RefreshConfig()
	if not built then return end
	SHPlates.RefreshConfigTabs()
	if Config:IsShown() then
		UpdateStatusLine()
		if currentPage == "general" then pages.general.RefreshAll() end
	end
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
			local raw = (not plate.shpPreview) and plate.GetName and plate:GetName(1)
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
		" hideCritters=" .. tostring(TV("hideCritters")) .. " hideFriendly=" .. tostring(TV("hideFriendly")) ..
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
