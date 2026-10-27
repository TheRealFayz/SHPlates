-------------------------------------------------------------------------------
-- SHPlates Theme: Grey (Tank and DPS modes) - the classic boxy look
-- Ported from Tidy Plates: Grey by Binny
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Shared = SHPlates.ThemeShared
local WidgetLib = SHPlatesWidgets
local greyart = SHPlates.MEDIA .. "Grey\\"

local function CreateTargetbox(frame)
	local icon = frame:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(greyart .. "TargetBox")
	icon:SetWidth(128)
	icon:SetHeight(64)
	icon:Hide()
	icon.SetTarget = function(self, value)
		if not value then icon:Hide(); return end
		-- Size and Style tab: optional color for the selection box
		local c = SHPlates.TOpt("targetColorOn") and SHPlates.TOpt("targetColor")
		if c then icon:SetVertexColor(c.r, c.g, c.b) else icon:SetVertexColor(1, 1, 1) end
		icon:Show()
	end
	return icon
end

local function CreateGrey(mode)
	local isTank = (mode == "Tank")
	local name = "Grey/" .. mode
	local theme = {}
	SHPlatesThemeList[name] = theme
	theme.family, theme.mode = "Grey", mode

	local LocalVars = {
		OpacityNonTarget = .5,
		OpacityHideNeutral = false,
		OpacityHideNonElites = false,
		ScaleGeneral = 1,
		ScaleIgnoreNonElite = false,
		WidgetTug = true,
		WidgetSelect = true,
		WidgetDebuff = false,
		WidgetDebuffList = { ["Rip"] = true, ["Rake"] = true, },
		WidgetDebuffMode = 1,
		WidgetClassIcon = false,
		WidgetMobNote = false,
		HealthText = 1,
		AggroHealth = false,
		AggroBorder = true,
		HideNames = {},
	}
	if isTank then
		LocalVars.ScaleLoose = 1.5
		LocalVars.WidgetWheel = false
		LocalVars.WidgetTanked = false
		LocalVars.AggroLooseColor = { r = .6, g = 1, b = 0, a = 1, }
		LocalVars.AggroTankedColor = { r = 1, g = 0, b = 0, a = 1, }
	else
		LocalVars.ScaleDanger = 1.5
		LocalVars.WidgetCombo = false
		LocalVars.AggroSafeColor = { r = .6, g = 1, b = 0, a = 1, }
		LocalVars.AggroDangerColor = { r = 1, g = 0, b = 0, a = 1, }
	end
	if isTank then
		Shared.AddExtraVars(LocalVars, true, { losing = { r = 1, g = .6, b = 0 }, othertank = { r = .6, g = .8, b = 1 } })
	else
		Shared.AddExtraVars(LocalVars, false, { warning = { r = 1, g = .6, b = 0 } })
	end
	theme.vars = LocalVars

	-- Style (uses the default boxy art)
	theme.hitbox = { width = 140, height = 35, }
	-- the elite star is its own piece (movable in the Designer), so elites
	-- use the plain border with the star drawn on top in the same spot
	theme.healthborder = { elitetexture = SHPlates.MEDIA .. "RegularBorder" }
	theme.eliteicon = { texture = greyart .. "EliteStar", width = 16, height = 16, x = -51, y = 16, anchor = "CENTER" }
	theme.name = { width = 100, }
	-- raid marker: right end of the bar, mirroring the elite star on the left
	theme.raidicon = { width = 14, height = 14, x = 50, y = 16, anchor = "CENTER", }
	theme.options = { showLevel = true, showSpecialText = true, showSpecialText2 = true, showAggroGlow = true, }
	theme.threatcolor = {
		LOW = { r = .6, g = 1, b = 0, a = 1, },
		MEDIUM = { r = .6, g = 1, b = 0, a = 1, },
		HIGH = { r = 1, g = 0, b = 0, a = 1, },
	}

	-- The border glow option and the global "Hide unit levels" setting drive
	-- the style, so the style is refreshed whenever the theme loads.
	theme.OnApplyVars = function(t)
		t.options.showAggroGlow = LocalVars.AggroBorder and true or false
		t.options.showLevel = true
		-- the name gives up room on the right only while the level is there
		if LocalVars.hideLevel then t.name.width = 100 else t.name.width = 88 end
		-- name/level stay exactly where Tidy Plates put them
		t.name.y = 1
		t.level.y = 1
		local loose = isTank and LocalVars.AggroLooseColor or LocalVars.AggroSafeColor
		local tight = isTank and LocalVars.AggroTankedColor or LocalVars.AggroDangerColor
		-- Same mapping as the original Grey: LOW and MEDIUM use the loose/safe
		-- color, HIGH uses the tanking/danger color.
		t.threatcolor.LOW = { r = loose.r, g = loose.g, b = loose.b, a = 1 }
		t.threatcolor.MEDIUM = { r = loose.r, g = loose.g, b = loose.b, a = 1 }
		t.threatcolor.HIGH = { r = tight.r, g = tight.g, b = tight.b, a = 1 }
	end

	local function HealthTextDelegate(unit)
		local f = Shared.HealthTextFunctions[LocalVars.HealthText] or Shared.HealthTextFunctions[1]
		return f(unit.health, unit.healthmax, unit.level)
	end

	local function Scale(unit)
		if C.InCombat() and unit.type == "NPC" then
			local trigger
			if isTank then trigger = unit.reaction == "HOSTILE" and unit.threatSituation ~= "HIGH"
			else trigger = unit.reaction ~= "FRIENDLY" and unit.threatSituation ~= "LOW" end
			if trigger then
				local s = isTank and LocalVars.ScaleLoose or LocalVars.ScaleDanger
				if LocalVars.ScaleIgnoreNonElite then
					if unit.isElite then return s end
				else return s end
			end
		end
		return LocalVars.ScaleGeneral
	end

	local function HealthColorDelegate(unit)
		if LocalVars.AggroHealth and C.InCombat() and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
			local c = Shared.PickThreatColor(LocalVars, isTank, unit)
			return c.r, c.g, c.b
		end
		return unit.red, unit.green, unit.blue
	end

	local DebuffFilter = Shared.MakeDebuffFilter(LocalVars)

	local function OnInitializeDelegate(plate)
		local w = plate.widgets
		if LocalVars.WidgetTug and not w.WidgetTug then
			w.WidgetTug = WidgetLib.CreateThreatLineWidget(plate)
			w.WidgetTug:SetBasePoint("CENTER", plate, "CENTER", 0, 18)
		end
		if isTank and LocalVars.WidgetWheel and not w.WidgetWheel then
			w.WidgetWheel = WidgetLib.CreateThreatWheelWidget(plate)
			w.WidgetWheel:SetPoint("CENTER", plate, "CENTER", 30, 18)
		end
		if (not isTank) and LocalVars.WidgetCombo and not w.WidgetCombo then
			-- 5 sections sitting on the top edge of the health bar, drawn
			-- above the border like the raid icon
			-- Lives on the icon frame (a child of the health bar), like the raid
			-- icon: when the client re-sorts plates it flattens the plate's
			-- direct children to one level, and the threat line would then
			-- randomly draw over the sections. One level deeper always wins.
			w.WidgetCombo = WidgetLib.CreateComboPointWidget(plate.iconFrame or plate, 101, 6)
			w.WidgetCombo:SetPoint("BOTTOM", plate.bars.healthbar, "TOP", 0, 1)
			w.WidgetCombo._y = 1
		end
		if LocalVars.WidgetSelect and not w.targetbox then
			w.targetbox = CreateTargetbox(plate)
			w.targetbox:SetPoint("CENTER", plate, "CENTER", 0, -5)
		end
		if isTank and LocalVars.WidgetTanked and not w.WidgetTanked then
			w.WidgetTanked = WidgetLib.CreateTankedWidget(plate)
			w.WidgetTanked:SetPoint("CENTER", plate, "CENTER", 37, 17)
		end
		if LocalVars.WidgetDebuff and not w.WidgetDebuff then
			w.WidgetDebuff = WidgetLib.CreateAuraWidget(plate)
			w.WidgetDebuff:SetPoint("CENTER", plate, "CENTER", 15, 41)
			w.WidgetDebuff:SetFrameLevel(plate:GetFrameLevel())
			w.WidgetDebuff.Filter = DebuffFilter
		end
		if LocalVars.WidgetClassIcon and not w.ClassWidget then
			w.ClassWidget = WidgetLib.CreateClassWidget(plate)
			w.ClassWidget:SetPoint("RIGHT", plate, "LEFT", 22, -4)
		end
		if LocalVars.WidgetMobNote and not w.NoteWidget then
			w.NoteWidget = WidgetLib.CreateNoteWidget(plate)
			w.NoteWidget:SetPoint("CENTER", plate, "CENTER", 0, 48)
		end
		if LocalVars.WidgetPower ~= 1 and not w.PowerBar then
			-- inside the bottom edge of the health bar, so nothing else moves
			w.PowerBar = WidgetLib.CreatePowerBar(plate, 101, 3)
			w.PowerBar:SetPoint("BOTTOM", plate.bars.healthbar, "BOTTOM", 0, 0)
			w.PowerBar:SetFrameLevel(plate.bars.healthbar:GetFrameLevel() + 1)
		end
	end

	local function OnUpdateDelegate(plate, unit)
		local w = plate.widgets
		-- Stack, from the health bar up: threat line, combo bar, aggro name.
		local tugShown = false
		if w.WidgetTug then
			if LocalVars.WidgetTug then w.WidgetTug:Update(unit) end
			tugShown = w.WidgetTug:IsShown() and true or false
		end
		local comboUp = false
		if w.WidgetCombo then
			if LocalVars.WidgetCombo then w.WidgetCombo:Update(unit) else w.WidgetCombo:Hide() end
			comboUp = w.WidgetCombo:IsShown() and true or false
			-- above the threat line when it's showing, otherwise right on the bar
			local y = tugShown and 8 or 1
			if comboUp and w.WidgetCombo._y ~= y then
				w.WidgetCombo._y = y
				w.WidgetCombo:ClearAllPoints()
				w.WidgetCombo:SetPoint("BOTTOM", plate.bars.healthbar, "TOP", 0, y)
			end
		end
		-- the aggro holder's name moves up over the combo bar
		if w.WidgetTug then w.WidgetTug:SetTextLift((comboUp and tugShown) and 10 or 0) end
		if w.WidgetWheel and LocalVars.WidgetWheel then w.WidgetWheel:Update(unit) end
		if LocalVars.WidgetSelect and w.targetbox then w.targetbox:SetTarget(unit.isTarget) end
		if w.WidgetTanked and LocalVars.WidgetTanked then w.WidgetTanked:Update(unit) end
		if LocalVars.WidgetDebuff and w.WidgetDebuff then w.WidgetDebuff:Update(unit) end
		if LocalVars.WidgetClassIcon and w.ClassWidget then w.ClassWidget:Update(unit) end
		if LocalVars.WidgetMobNote and w.NoteWidget then w.NoteWidget:Update(unit) end
		if w.PowerBar then w.PowerBar:Update(unit, LocalVars.WidgetPower, LocalVars.WidgetPowerManaOnly) end
	end

	theme.SetSpecialText = HealthTextDelegate
	theme.healthTextKey = "specialText"  -- which text shows health (Size and Style tab)
	theme.SetSpecialText2 = Shared.SpellTextDelegate
	theme.SetScale = Scale
	theme.SetAlpha = Shared.MakeAlpha(LocalVars)
	theme.OnUpdate = OnUpdateDelegate
	theme.OnInitialize = OnInitializeDelegate
	theme.SetHealthbarColor = HealthColorDelegate

	local s = {}
	table.insert(s, { type = "header", text = "Opacity" })
	table.insert(s, { type = "slider", key = "OpacityNonTarget", label = "Non-Target Opacity", min = 0, max = 1, step = .05, pct = true })
	table.insert(s, { type = "check", key = "OpacityHideNeutral", label = "Hide Neutral Units" })
	table.insert(s, { type = "check", key = "OpacityHideNonElites", label = "Hide Non-Elites (out of combat)" })
	table.insert(s, { type = "header", text = "Scale" })
	table.insert(s, { type = "slider", key = "ScaleGeneral", label = "General Scale", min = .5, max = 2, step = .05, pct = true })
	if isTank then
		table.insert(s, { type = "slider", key = "ScaleLoose", label = "Lost Unit Scale", min = 1, max = 2, step = .05, pct = true })
	else
		table.insert(s, { type = "slider", key = "ScaleDanger", label = "Aggro Scale", min = 1, max = 2, step = .05, pct = true })
	end
	table.insert(s, { type = "check", key = "ScaleIgnoreNonElite", label = "Ignore Non-Elites" })
	table.insert(s, { type = "header", text = "Widgets" })
	table.insert(s, { type = "check", key = "WidgetSelect", label = "Selection Box" })
	table.insert(s, { type = "check", key = "WidgetTug", label = "Tug-o'-Threat" })
	if isTank then
		table.insert(s, { type = "check", key = "WidgetWheel", label = "Threat Wheel" })
		table.insert(s, { type = "check", key = "WidgetTanked", label = "Tanked Icon" })
	else
		table.insert(s, { type = "check", key = "WidgetCombo", label = "Combo Points" })
	end
	table.insert(s, { type = "check", key = "WidgetClassIcon", label = "Enemy Class Icon" })
	table.insert(s, { type = "check", key = "WidgetMobNote", label = "Mob Notes (edit on the Notes tab)" })
	table.insert(s, { type = "choice", key = "WidgetDebuffMode", label = "Debuff Mode", choices = Shared.DebuffModes })
	table.insert(s, { type = "list", key = "WidgetDebuffList", label = "Debuff filter list (one per line)" })
	table.insert(s, { type = "header", text = "Threat Indication" })
	table.insert(s, { type = "check", key = "AggroHealth", label = "Health Bar Color" })
	table.insert(s, { type = "check", key = "AggroBorder", label = "Border Glow" })
	if isTank then
		table.insert(s, { type = "color", key = "AggroLooseColor", label = "Loose Color" })
		table.insert(s, { type = "color", key = "AggroTankedColor", label = "Tanking Color" })
	else
		table.insert(s, { type = "color", key = "AggroSafeColor", label = "Safe Color" })
		table.insert(s, { type = "color", key = "AggroDangerColor", label = "Danger Color" })
	end
	table.insert(s, { type = "header", text = "Text" })
	table.insert(s, { type = "choice", key = "HealthText", label = "Health Text Mode", choices = { "None", "Percent", "Actual", "Deficit", "Total & Percent", "Plus-and-Minus" } })
	table.insert(s, { type = "list", key = "HideNames", label = "Always hide these units (one name per line)" })
	Shared.AddExtraSchema(s, isTank)
	theme.optionsSchema = s
	return theme
end

CreateGrey("Tank")
CreateGrey("DPS")
