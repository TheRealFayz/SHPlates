-------------------------------------------------------------------------------
-- SHPlates Theme: Neon (Tank and DPS modes)  - "It glows!"
-- Ported from Tidy Plates: Neon by Danltiger aka Binny
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Shared = SHPlates.ThemeShared
local WidgetLib = SHPlatesWidgets
local artpath = SHPlates.MEDIA .. "Neon\\"

local function BuildStyle(theme)
	local castadjust = -21
	local nameadjust = -8

	theme.hitbox = { width = 105, height = 20, }
	theme.frame = { x = 0, y = 4, }
	theme.healthborder = {
		texture = artpath .. "Neon_HealthOverlay",
		glowtexture = artpath .. "Neon_Highlight",
		elitetexture = artpath .. "Neon_HealthOverlayEliteStar",
		width = 128, height = 32, y = 0,
	}
	theme.healthbar = { texture = artpath .. "Neon_Bar", width = 100, height = 32, x = 0, y = 0, }
	theme.castborder = { texture = artpath .. "Neon_CastOverlayBlue", width = 128, height = 32, x = 0, y = castadjust, }
	theme.castnostop = { texture = artpath .. "Neon_CastOverlayRed", width = 128, height = 32, x = 0, y = castadjust, }
	theme.castbar = {
		texture = artpath .. "Neon_Bar", width = 100, height = 32,
		x = 0, y = castadjust, anchor = "CENTER", orientation = "HORIZONTAL",
	}
	theme.threatborder = {
		texture = artpath .. "Neon_Empty",
		elitetexture = artpath .. "Neon_AggroOverlayWhite",
		width = 256, height = 64, y = 1,
	}
	theme.spellicon = { width = 17, height = 17, x = 26, y = -3 + castadjust, anchor = "CENTER", }
	-- raid marker: right end of the bar, mirroring the elite star on the left
	theme.raidicon = { width = 14, height = 14, x = 49, y = 6, anchor = "CENTER", }
	theme.name = {
		size = 11, width = 150, height = 11, x = 0, y = nameadjust,
		align = "CENTER", anchor = "CENTER", vertical = "CENTER", shadow = true,
	}
	theme.level = {
		size = 9, width = 22, height = 11, x = 5, y = 5,
		align = "LEFT", anchor = "LEFT", vertical = "CENTER", flags = "OUTLINE", shadow = false,
	}
	theme.dangerskull = { width = 14, height = 14, x = 5, y = 5, anchor = "LEFT", }
	theme.specialText = {
		size = 11, width = 150, height = 11, x = 26, y = -19 + castadjust,
		align = "CENTER", anchor = "CENTER", vertical = "CENTER", shadow = true,
	}
	theme.specialText2 = {
		size = 9, width = 150, height = 11, x = 0, y = 1,
		align = "CENTER", anchor = "CENTER", vertical = "CENTER", shadow = false, flags = "OUTLINE",
	}
	theme.options = {
		showName = true, showLevel = false,
		showSpecialText = true, showSpecialText2 = true, showSpecialArt = true,
		useCustomHealthbarColor = true, forceAlpha = true,
	}
end

local function CreateTargetWidget(frame)
	local icon = frame.bars.healthbar:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(artpath .. "Neon_Select")
	icon:SetWidth(128)
	icon:SetHeight(32)
	icon:Hide()
	icon.SetTarget = function(self, value) if value then icon:Show() else icon:Hide() end end
	return icon
end

local function CreateNeon(mode)
	local isTank = (mode == "Tank")
	local name = "Neon/" .. mode
	local theme = {}
	SHPlatesThemeList[name] = theme
	theme.family, theme.mode = "Neon", mode

	local LocalVars = {
		OpacityNonTarget = .5,
		OpacityHideNeutral = false,
		OpacityHideNonElites = false,
		ScaleGeneral = 1,
		ScaleIgnoreNonElite = false,
		WidgetTug = true,
		WidgetSelect = true,
		WidgetDebuff = not isTank,
		WidgetDebuffList = isTank and { ["Rip"] = true, ["Rake"] = true, ["Sunder Armor"] = true, } or { ["Rip"] = true, ["Rake"] = true, },
		WidgetDebuffMode = 1,
		WidgetRange = false,
		WidgetCombo = false,
		WidgetWheel = false,
		WidgetClassIcon = false,
		WidgetMobNote = false,
		RangeMode = 1,
		HealthText = 1,
		HideNames = {},
		TugWidgetLooseColor = { r = .14, g = .75, b = 1 },
		TugWidgetAggroColor = { r = 1, g = .67, b = .14 },
	}
	if isTank then
		LocalVars.ScaleLoose = 1.2
		LocalVars.AggroHealth = true
		LocalVars.AggroBorder = false
		LocalVars.AggroLooseColor = { r = 15 / 255, g = 133 / 255, b = 255 / 255 }
		LocalVars.AggroTankedColor = { r = 255 / 255, g = 128 / 255, b = 0 }
		LocalVars.TugWidgetSafeColor = { r = 0, g = .9, b = .1 }
	else
		LocalVars.ScaleDanger = 1.2
		LocalVars.AggroSafeColor = { r = 15 / 255, g = 133 / 255, b = 255 / 255 }
		LocalVars.AggroDangerColor = { r = 255 / 255, g = 128 / 255, b = 0 }
	end
	if isTank then
		Shared.AddExtraVars(LocalVars, true, { losing = { r = 1, g = 1, b = 0 }, othertank = { r = 0, g = .9, b = .1 } })
	else
		Shared.AddExtraVars(LocalVars, false, { warning = { r = 1, g = .85, b = 0 } })
	end
	theme.vars = LocalVars

	BuildStyle(theme)


	local function HealthTextDelegate(unit)
		local f = Shared.HealthTextFunctions[LocalVars.HealthText] or Shared.HealthTextFunctions[1]
		return f(unit.health, unit.healthmax, unit.level)
	end

	local function Scale(unit)
		if C.InCombat() and unit.reaction == "HOSTILE" and unit.type == "NPC" then
			local trigger
			if isTank then trigger = unit.threatSituation ~= "HIGH" else trigger = unit.threatSituation ~= "LOW" end
			if trigger then
				local s = isTank and LocalVars.ScaleLoose or LocalVars.ScaleDanger
				if LocalVars.ScaleIgnoreNonElite then
					if unit.isElite then return s end
				else return s end
			end
		end
		return LocalVars.ScaleGeneral
	end

	local currentcolor
	local function HealthColorDelegate(unit)
		if (LocalVars.AggroHealth or not isTank) and C.InCombat() and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
			currentcolor = Shared.PickThreatColor(LocalVars, isTank, unit)
			return currentcolor.r, currentcolor.g, currentcolor.b
		end
		return unit.red, unit.green, unit.blue
	end

	local function ThreatColorDelegate(unit)
		if isTank and LocalVars.AggroBorder then
			if C.InCombat() and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
				if unit.threatSituation ~= "HIGH" then
					currentcolor = LocalVars.AggroLooseColor
					return currentcolor.r, currentcolor.g, currentcolor.b, 1
				end
			end
		end
		return 0, 0, 0, 0
	end

	local DebuffFilter = Shared.MakeDebuffFilter(LocalVars)

	local function OnInitializeDelegate(plate)
		local w = plate.widgets
		if LocalVars.WidgetTug and not w.WidgetTug then
			w.WidgetTug = WidgetLib.CreateThreatLineWidget(plate)
			w.WidgetTug:SetBasePoint("CENTER", plate, "CENTER", 0, 4)
			w.WidgetTug._LowColor = LocalVars.TugWidgetLooseColor
			w.WidgetTug._HighColor = LocalVars.TugWidgetAggroColor
			if isTank then w.WidgetTug._TankedColor = LocalVars.TugWidgetSafeColor end
		end
		if LocalVars.WidgetPower ~= 1 and not w.PowerBar then
			-- inside the bottom edge of the glowing bar, so nothing else moves
			w.PowerBar = WidgetLib.CreatePowerBar(plate, 92, 2)
			w.PowerBar:SetPoint("BOTTOM", plate.bars.healthbar, "CENTER", 0, -5)
			w.PowerBar:SetFrameLevel(plate.bars.healthbar:GetFrameLevel() + 1)
		end
		if LocalVars.WidgetSelect and not w.targetbox then
			w.targetbox = CreateTargetWidget(plate)
			w.targetbox:SetPoint("CENTER", plate, "CENTER", 0, 0)
		end
		if LocalVars.WidgetDebuff and not w.AuraIcon then
			w.AuraIcon = WidgetLib.CreateAuraWidget(plate)
			w.AuraIcon:SetPoint("CENTER", plate, "CENTER", 15, 26)
			w.AuraIcon:SetFrameLevel(plate:GetFrameLevel())
			w.AuraIcon.Filter = DebuffFilter
		end
		if LocalVars.WidgetClassIcon and not w.ClassWidget then
			w.ClassWidget = WidgetLib.CreateClassWidget(plate)
			w.ClassWidget:SetPoint("TOP", plate, "TOP", 0, 3)
			w.ClassWidget:SetScale(1.2)
		end
		if LocalVars.WidgetWheel and not w.WidgetWheel then
			w.WidgetWheel = WidgetLib.CreateThreatWheelWidget(plate)
			w.WidgetWheel:SetPoint("CENTER", plate, "CENTER", 36, 12)
		end
		if LocalVars.WidgetRange and not w.Range then
			w.Range = WidgetLib.CreateRangeWidget(plate)
			w.Range:SetPoint("CENTER", plate, "CENTER", 0, 0)
		end
		if LocalVars.WidgetMobNote and not w.NoteWidget then
			w.NoteWidget = WidgetLib.CreateNoteWidget(plate)
			w.NoteWidget:SetPoint("CENTER", plate, "CENTER", 0, 42)
		end
		if LocalVars.WidgetCombo and not w.WidgetCombo then
			-- along the top edge of the visible bar (mirrors the power bar at the bottom)
			-- Lives on the icon frame (a child of the health bar), like the raid
			-- icon: when the client re-sorts plates it flattens the plate's
			-- direct children to one level, and the threat line would then
			-- randomly draw over the sections. One level deeper always wins.
			w.WidgetCombo = WidgetLib.CreateComboPointWidget(plate.iconFrame or plate, 92, 4)
			w.WidgetCombo:SetPoint("BOTTOM", plate.bars.healthbar, "CENTER", 0, 5)
		end
	end

	local function OnUpdateDelegate(plate, unit)
		local w = plate.widgets
		local comboUp = false
		if w.WidgetCombo then
			if LocalVars.WidgetCombo then w.WidgetCombo:Update(unit) else w.WidgetCombo:Hide() end
			comboUp = w.WidgetCombo:IsShown() and true or false
		end
		if w.WidgetTug then
			w.WidgetTug:SetTextLift(comboUp and 5 or 0)
			if LocalVars.WidgetTug then w.WidgetTug:Update(unit) end
		end
		if LocalVars.WidgetSelect and w.targetbox then w.targetbox:SetTarget(unit.isTarget) end
		if LocalVars.WidgetDebuff and w.AuraIcon then w.AuraIcon:Update(unit) end
		if LocalVars.WidgetRange and w.Range then w.Range:Update(unit, Shared.RangeModeRef[LocalVars.RangeMode]) end
		if LocalVars.WidgetWheel and w.WidgetWheel then w.WidgetWheel:Update(unit) end
		if LocalVars.WidgetClassIcon and w.ClassWidget then w.ClassWidget:Update(unit) end
		if LocalVars.WidgetMobNote and w.NoteWidget then w.NoteWidget:Update(unit) end
		if w.PowerBar then w.PowerBar:Update(unit, LocalVars.WidgetPower, LocalVars.WidgetPowerManaOnly) end
	end

	theme.SetSpecialText = Shared.SpellTextDelegate
	theme.SetSpecialText2 = HealthTextDelegate
	theme.SetScale = Scale
	theme.SetAlpha = Shared.MakeAlpha(LocalVars)
	theme.OnUpdate = OnUpdateDelegate
	theme.OnInitialize = OnInitializeDelegate
	theme.SetHealthbarColor = HealthColorDelegate
	if isTank then theme.SetThreatColor = ThreatColorDelegate end

	-- Options window layout
	local s = {}
	table.insert(s, { type = "header", text = "Opacity" })
	table.insert(s, { type = "slider", key = "OpacityNonTarget", label = "Non-Target Opacity", min = 0, max = 1, step = .05, pct = true })
	table.insert(s, { type = "check", key = "OpacityHideNeutral", label = "Hide Neutral Units" })
	table.insert(s, { type = "check", key = "OpacityHideNonElites", label = "Hide Non-Elites (out of combat)" })
	table.insert(s, { type = "header", text = "Scale" })
	table.insert(s, { type = "slider", key = "ScaleGeneral", label = "General Scale", min = .5, max = 2, step = .05, pct = true })
	if isTank then
		table.insert(s, { type = "slider", key = "ScaleLoose", label = "Loose Unit Scale", min = 1, max = 2, step = .05, pct = true })
	else
		table.insert(s, { type = "slider", key = "ScaleDanger", label = "Aggro Scale", min = 1, max = 2, step = .05, pct = true })
	end
	table.insert(s, { type = "check", key = "ScaleIgnoreNonElite", label = "Ignore Non-Elites" })
	table.insert(s, { type = "header", text = "Threat Colors" })
	if isTank then
		table.insert(s, { type = "check", key = "AggroHealth", label = "Health Bar Color" })
		table.insert(s, { type = "check", key = "AggroBorder", label = "Border Glow" })
		table.insert(s, { type = "color", key = "AggroLooseColor", label = "Loose Color" })
		table.insert(s, { type = "color", key = "AggroTankedColor", label = "Aggro/Tanked Color" })
	else
		table.insert(s, { type = "color", key = "AggroSafeColor", label = "Safe Color" })
		table.insert(s, { type = "color", key = "AggroDangerColor", label = "Danger Color" })
	end
	table.insert(s, { type = "header", text = "Text" })
	table.insert(s, { type = "choice", key = "HealthText", label = "Health Text Mode", choices = Shared.HealthTextModes })
	table.insert(s, { type = "header", text = "Widgets" })
	table.insert(s, { type = "check", key = "WidgetClassIcon", label = "Enemy Class Icon" })
	table.insert(s, { type = "check", key = "WidgetSelect", label = "Selection Box" })
	table.insert(s, { type = "check", key = "WidgetTug", label = "Tug-o'-Threat" })
	table.insert(s, { type = "color", key = "TugWidgetLooseColor", label = isTank and "Tug: Loose Color" or "Tug: Safe Color" })
	table.insert(s, { type = "color", key = "TugWidgetAggroColor", label = "Tug: Aggro Color" })
	if isTank then table.insert(s, { type = "color", key = "TugWidgetSafeColor", label = "Tug: Other Tank Color" }) end
	table.insert(s, { type = "check", key = "WidgetWheel", label = "Threat Wheel" })
	table.insert(s, { type = "check", key = "WidgetCombo", label = "Combo Points" })
	table.insert(s, { type = "check", key = "WidgetRange", label = "Range Watcher" })
	table.insert(s, { type = "choice", key = "RangeMode", label = "Range", choices = Shared.RangeModes })
	table.insert(s, { type = "check", key = "WidgetMobNote", label = "Mob Notes (edit on the General page)" })
	table.insert(s, { type = "check", key = "WidgetDebuff", label = "Debuff Tracker" })
	table.insert(s, { type = "choice", key = "WidgetDebuffMode", label = "Debuff Mode", choices = Shared.DebuffModes })
	table.insert(s, { type = "list", key = "WidgetDebuffList", label = "Debuff filter list (one per line)" })
	table.insert(s, { type = "list", key = "HideNames", label = "Always hide these units (one name per line)" })
	Shared.AddExtraSchema(s, isTank)
	theme.optionsSchema = s

	return theme
end

CreateNeon("Tank")
CreateNeon("DPS")
