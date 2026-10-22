-------------------------------------------------------------------------------
-- SHPlates Themes: shared delegates used by Neon and Grey
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local valueToString = SHPlatesUtility.abbrevNumber
local Shared = {}
SHPlates.ThemeShared = Shared

local function pct(health, healthmax)
	if not healthmax or healthmax <= 0 then return 0 end
	return math.ceil(100 * (health / healthmax))
end

Shared.HealthTextFunctions = {
	-- None
	function(health, healthmax) return "" end,
	-- Percent
	function(health, healthmax) if health ~= healthmax then return pct(health, healthmax) .. "%" else return "" end end,
	-- Actual
	function(health, healthmax) return valueToString(health) end,
	-- Deficit
	function(health, healthmax) if health ~= healthmax then return "-" .. valueToString(healthmax - health) else return "" end end,
	-- Total & Percent
	function(health, healthmax) return valueToString(health) .. " / " .. valueToString(healthmax) .. " (" .. pct(health, healthmax) .. "%)" end,
	-- Plus-and-Minus
	function(health, healthmax) return "+" .. valueToString(health) .. " (" .. pct(health, healthmax) .. "%) -" .. valueToString(healthmax - health) end,
	-- Level
	function(health, healthmax, level) return level or "" end,
}

Shared.HealthTextModes = { "None", "Percent", "Actual", "Deficit", "Total & Percent", "Plus-and-Minus", "Level" }
Shared.RangeModes = { "9 yards", "15 yards", "28 yards", "40 yards" }
Shared.RangeModeRef = { 9, 15, 28, 40 }
Shared.DebuffModes = { "All of mine", "Mine, filtered by list", "Everyone's" }

-- Spell text: works on every plate thanks to UNIT_CASTEVENT
function Shared.SpellTextDelegate(unit)
	if unit.isCasting and unit.spellName then return unit.spellName end
	return ""
end

-- Debuff filter shared by both themes
local DEBUFFMODE_ALL, DEBUFFMODE_FILTER, DEBUFFMODE_EVERYONE = 1, 2, 3
function Shared.MakeDebuffFilter(LocalVars)
	return function(debuff)
		local mode = LocalVars.WidgetDebuffMode or 1
		if mode == DEBUFFMODE_EVERYONE then return true end
		-- isMine is nil when Nampower is missing (caster unknown): show it
		if debuff.isMine == false then return false end
		if mode == DEBUFFMODE_FILTER then
			return debuff.name and LocalVars.WidgetDebuffList[debuff.name] and true or false
		end
		return true
	end
end

-- Alpha delegate (identical in all four original themes)
function Shared.MakeAlpha(LocalVars)
	return function(unit)
		if unit.isTarget then return 1 end
		if LocalVars.OpacityHideNeutral and unit.reaction == "NEUTRAL" then return 0 end
		-- non-elites stay hidden between pulls, but anything hostile shows
		-- once you're fighting (totems, summoned adds, minor mobs)
		if LocalVars.OpacityHideNonElites and not unit.isElite
			and not (C.InCombat() and unit.reaction == "HOSTILE") then return 0 end
		if LocalVars.HideNames and unit.name and LocalVars.HideNames[unit.name] then return 0 end
		if not UnitExists("target") then return 1 end
		return LocalVars.OpacityNonTarget, true
	end
end

-- Threat color picker shared by both themes.
-- Tank: tanking / losing it / another tank has it / loose.
-- DPS:  mob on you / you're close to pulling / safe.
function Shared.PickThreatColor(LocalVars, isTank, unit)
	local extra = LocalVars.ExtraThreatColors ~= false
	if isTank then
		if unit.threatSituation == "HIGH" then
			if extra and unit.losingAggro then return LocalVars.AggroLosingColor end
			return LocalVars.AggroTankedColor
		end
		if extra and unit.holderIsTank then return LocalVars.AggroOtherTankColor end
		return LocalVars.AggroLooseColor
	end
	if unit.threatSituation == "HIGH" then return LocalVars.AggroDangerColor end
	if unit.threatSituation == "MEDIUM" then
		if extra then return LocalVars.AggroWarningColor end
		return LocalVars.AggroDangerColor
	end
	return LocalVars.AggroSafeColor
end

-- Defaults for the extra variables, merged into each theme's LocalVars
function Shared.AddExtraVars(LocalVars, isTank, palette)
	LocalVars.ExtraThreatColors = true
	LocalVars.WidgetPower = 1
	LocalVars.WidgetPowerManaOnly = false
	if isTank then
		LocalVars.AggroLosingColor = palette.losing
		LocalVars.AggroOtherTankColor = palette.othertank
	else
		LocalVars.AggroWarningColor = palette.warning
	end
end

-- Options window rows for the extras
function Shared.AddExtraSchema(s, isTank)
	table.insert(s, { type = "header", text = "Extra threat colors" })
	table.insert(s, { type = "check", key = "ExtraThreatColors", label = "Use extra threat colors" })
	if isTank then
		table.insert(s, { type = "color", key = "AggroLosingColor", label = "Losing aggro (someone close)" })
		table.insert(s, { type = "color", key = "AggroOtherTankColor", label = "Another tank has it" })
	else
		table.insert(s, { type = "color", key = "AggroWarningColor", label = "High threat (warning)" })
	end
	table.insert(s, { type = "header", text = "Power bar" })
	table.insert(s, { type = "choice", key = "WidgetPower", label = "Show mana/rage/energy bar for", choices = SHPlatesWidgets.PowerModes })
	table.insert(s, { type = "check", key = "WidgetPowerManaOnly", label = "Mana users only" })
end
