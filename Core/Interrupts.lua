-------------------------------------------------------------------------------
-- SHPlates: Interrupt learning
--
-- 1.12 never tells the client whether a cast can be interrupted, so SHPlates
-- learns it. When you (or a group member) land an interrupt on a mob that is
-- casting, and the cast keeps going anyway, that mob + spell is remembered
-- as uninterruptible and gets the "can't interrupt" border from then on.
-- If a later interrupt does stop it, the entry is removed again.
--
-- Knowledge is keyed by MOB NAME + SPELL ID, because the same spell can be
-- interruptible on one mob and not on another. Stored account-wide in
-- SHPlatesLearned so every character benefits.
--
-- "Landed" means it didn't miss/dodge/parry/resist/etc:
--   * Nampower SPELL_MISS_SELF / SPELL_MISS_OTHER (any language, any caster)
--   * fallback: your own combat log text (your interrupts only)
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local I = {}
SHPlates.Interrupts = I

local RESOLVE_DELAY = .6   -- seconds after the interrupt to check the cast

-- Spells whose purpose is to interrupt a cast (all ranks, matched by name)
I.InterruptSpells = {
	["Kick"] = true,
	["Pummel"] = true,
	["Shield Bash"] = true,
	["Earth Shock"] = true,
	["Counterspell"] = true,
	["Feral Charge"] = true,
	["Spell Lock"] = true,
	["Silence"] = true,
}

local pending = {}  -- list of { caster, mob, mobName, castSpell, castStart, interrupt, interruptName, at, missed }

local function DB()
	if type(SHPlatesLearned) ~= "table" then SHPlatesLearned = {} end
	if type(SHPlatesLearned.nostop) ~= "table" then SHPlatesLearned.nostop = {} end
	return SHPlatesLearned.nostop
end

function I.IsUninterruptible(mobName, spellId)
	if not (mobName and spellId) then return false end
	local mob = DB()[mobName]
	return mob and mob[spellId] and true or false
end

local function Refresh(mobGUID)
	if SHPlates.OnCastChanged then SHPlates.OnCastChanged(mobGUID) end
end

local function Learn(p, uninterruptible)
	local db = DB()
	local mob = db[p.mobName]
	if uninterruptible then
		if not mob then mob = {}; db[p.mobName] = mob end
		if not mob[p.castSpell] then
			mob[p.castSpell] = true
			if SHPlatesDB and SHPlatesDB.announceLearned ~= false then
				local spellName = C.SpellNameIcon(p.castSpell) or ("spell " .. p.castSpell)
				C.print("learned: " .. p.mobName .. "'s |cffffff00" .. spellName .. "|r can't be interrupted.")
			end
		end
	elseif mob and mob[p.castSpell] then
		mob[p.castSpell] = nil
		if not next(mob) then db[p.mobName] = nil end
	end
	Refresh(p.mob)
end

local function IsTrackedCaster(casterGUID)
	if casterGUID == Data.PlayerGUID() then return true end
	if SHPlatesDB and SHPlatesDB.learnFromGroup == false then return false end
	return Data.InGroup(UnitName(casterGUID))
end

-- From Data.lua, for every UNIT_CASTEVENT
function I.OnCastEvent(caster, target, kind, spellId)
	if kind ~= "CAST" or not (caster and target and spellId) then return end
	local name = C.SpellNameIcon(spellId)
	if not (name and I.InterruptSpells[name]) then return end
	if not IsTrackedCaster(caster) then return end
	local cast = Data.GetCast(target)
	if not cast then return end
	local mobName = UnitName(target)
	if not mobName or UnitIsPlayer(target) then return end
	table.insert(pending, {
		caster = caster, mob = target, mobName = mobName,
		castSpell = cast.spellId, castStart = cast.start,
		interrupt = spellId, interruptName = name, at = GetTime(),
	})
end

-- Nampower miss event: casterGuid, targetGuid, spellId, missInfo
function I.OnMiss(caster, target, spellId)
	for i = 1, table.getn(pending) do
		local p = pending[i]
		if p.caster == caster and p.mob == target and p.interrupt == spellId then p.missed = true end
	end
end

-- Fallback: "Your Kick was parried by X." etc. built from the client's own strings
local missPatterns
local function BuildMissPatterns()
	missPatterns = {}
	local names = { "SPELLMISSSELFOTHER", "SPELLDODGEDSELFOTHER", "SPELLPARRIEDSELFOTHER",
		"SPELLRESISTSELFOTHER", "SPELLBLOCKEDSELFOTHER", "SPELLEVADEDSELFOTHER",
		"SPELLDEFLECTEDSELFOTHER", "SPELLREFLECTSELFOTHER", "IMMUNESPELLSELFOTHER",
		"SPELLIMMUNESELFOTHER", "SPELLLOGABSORBSELFOTHER" }
	for i = 1, table.getn(names) do
		local fmt = getglobal(names[i])
		if type(fmt) == "string" then
			local pat = string.gsub(fmt, "%%%d?%$?s", "\001")
			pat = string.gsub(pat, "%%%d?%$?d", "\002")
			pat = string.gsub(pat, "([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
			pat = string.gsub(pat, "\001", "(.+)")
			pat = string.gsub(pat, "\002", "%%d+")
			table.insert(missPatterns, "^" .. pat .. "$")
		end
	end
end

function I.OnSelfDamageText(msg)
	if C.HasNampower or not msg then return end  -- Nampower's events are better
	if not missPatterns then BuildMissPatterns() end
	local me = Data.PlayerGUID()
	for i = 1, table.getn(missPatterns) do
		if string.find(msg, missPatterns[i]) then
			for j = 1, table.getn(pending) do
				local p = pending[j]
				if p.caster == me and string.find(msg, p.interruptName, 1, true) then p.missed = true end
			end
			return
		end
	end
end

-- Resolve pending attempts
local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function()
	local n = table.getn(pending)
	if n == 0 then return end
	local now = GetTime()
	for i = n, 1, -1 do
		local p = pending[i]
		if now - p.at >= RESOLVE_DELAY then
			table.remove(pending, i)
			if not p.missed then
				local cast = Data.GetCast(p.mob)
				local stop = Data.lastStop[p.mob]
				if cast and cast.start == p.castStart and cast.spellId == p.castSpell then
					-- interrupt landed, cast kept going
					Learn(p, true)
				elseif stop and stop.kind == "FAIL" and stop.start == p.castStart and stop.time >= p.at - .1 then
					-- interrupt worked
					Learn(p, false)
				end
				-- anything else (finished right as we kicked, mob died...) is ambiguous: ignore
			end
		end
	end
end)

function I.Count()
	local n = 0
	for _, mob in pairs(DB()) do for _ in pairs(mob) do n = n + 1 end end
	return n
end

function I.Forget() SHPlatesLearned.nostop = {} end

function I.List()
	local lines = {}
	for mobName, mob in pairs(DB()) do
		for spellId in pairs(mob) do
			local spellName = C.SpellNameIcon(spellId) or ("spell " .. spellId)
			table.insert(lines, mobName .. ": " .. spellName)
		end
	end
	table.sort(lines)
	return lines
end
