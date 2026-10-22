-------------------------------------------------------------------------------
-- SHPlates: Compat
-- Namespaces, client detection (SuperWoW / Nampower) and small helpers that
-- replace 3.3.5 conveniences missing from the 1.12 client (Lua 5.0).
-------------------------------------------------------------------------------

SHPlates = {}
SHPlatesUtility = {}
SHPlatesWidgets = {}
if not SHPlatesThemeList then SHPlatesThemeList = {} end

SHPlates.ADDON = "SHPlates"
SHPlates.MEDIA = "Interface\\AddOns\\SHPlates\\Media\\"
SHPlates.ART = "Interface\\AddOns\\SHPlates\\Art\\"

local C = {}
SHPlates.Compat = C

-- SuperWoW: GUIDs on nameplates, GUIDs as unit tokens, UNIT_CASTEVENT, SpellInfo
C.HasSuperWoW = (SUPERWOW_VERSION ~= nil) or (SpellInfo ~= nil)
-- Nampower: aura cast events with durations, spell records
C.HasNampower = (GetNampowerVersion ~= nil)

-- wipe(): empties a table in place
function C.wipe(t)
	for k in pairs(t) do t[k] = nil end
	return t
end

-- print(): 1.12 has no print
function C.print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SHPlates|r: " .. tostring(msg))
	end
end

-- InCombat(): stands in for InCombatLockdown(). Deliberately NOT a global,
-- since other addons test for InCombatLockdown to detect the client version.
function C.InCombat()
	if UnitAffectingCombat("player") then return true end
	return false
end

-- GUID(unit): SuperWoW returns the GUID as the second value of UnitExists
function C.GUID(unitid)
	if not C.HasSuperWoW then return nil end
	local exists, guid = UnitExists(unitid)
	if exists and guid and guid ~= "" then return guid end
	return nil
end

-- PlateGUID(frame): SuperWoW returns the GUID of a nameplate with GetName(1)
-- When the client recycles a plate for another unit, GetName(1) can still
-- hand back the previous unit's GUID for a moment. If the GUID's name doesn't
-- match the name on the plate, it's stale: ignore it until it catches up.
function C.PlateGUID(plate, plateName)
	if not C.HasSuperWoW then return nil end
	local guid = plate:GetName(1)
	if not guid or guid == "" or guid == "0x0000000000000000" then return nil end
	if plateName then
		local name = UnitName(guid)
		if not name or name ~= plateName then return nil end
	end
	return guid
end

-- Safe CVar helpers (unknown CVars throw errors in 1.12)
function C.GetCVarSafe(name)
	local ok, value = pcall(GetCVar, name)
	if ok then return value end
	return nil
end

function C.SetCVarSafe(name, value)
	local ok = pcall(SetCVar, name, value)
	return ok
end

-- Hook a script without replacing it (no HookScript in 1.12).
-- Handlers in 1.12 read 'this' and 'arg1..' globals, which stay intact here.
function C.HookScript(frame, script, func)
	local original = frame:GetScript(script)
	frame:SetScript(script, function()
		if original then original() end
		func()
	end)
end

-- Spell name/icon lookup by spell ID
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function C.SpellNameIcon(spellId)
	if not spellId then return nil, QUESTION end
	if SpellInfo then
		local name, _, icon = SpellInfo(spellId)
		return name, icon or QUESTION
	end
	if GetSpellNameAndRankForId then
		local name = GetSpellNameAndRankForId(spellId)
		return name, QUESTION
	end
	return nil, QUESTION
end

-- Splits text into lines, ignoring blanks
function C.Lines(text)
	local t = {}
	if not text then return t end
	for line in string.gfind(text, "[^\r\n]+") do
		line = string.gsub(line, "^%s+", "")
		line = string.gsub(line, "%s+$", "")
		if line ~= "" then table.insert(t, line) end
	end
	return t
end

SHPlates.InCombat = C.InCombat
SHPlates.Print = C.print
