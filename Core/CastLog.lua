-------------------------------------------------------------------------------
-- SHPlates: cast bars without SuperWoW
--
-- The 1.12 client only reports other units' casts as combat log text, e.g.
-- "Defias Pillager begins to cast Fireball." There is no GUID, so a cast
-- belongs to every plate with that name. Cast times come from the table in
-- CastTimes.lua. A spell that isn't in it gets a 2 second bar the first time
-- and its real cast time is learned when it lands (saved for all characters).
-- With SuperWoW none of this runs: UNIT_CASTEVENT is exact.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local CastLog = {}
SHPlates.CastLog = CastLog

local DEFAULT_MS = 2000
local byName = {}   -- caster name -> cast (same shape as Data.casts entries)

local function Pattern(gs)
	if not gs then return nil end
	local p = string.gsub(gs, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	p = string.gsub(p, "%%%%s", "(.+)")
	p = string.gsub(p, "%%%%d", "(%%d+)")
	return "^" .. p   -- no end anchor: hits can end with " (12 resisted)"
end

-- English fallbacks in case a global string is missing
local P = {
	start      = Pattern(SPELLCASTOTHERSTART or "%s begins to cast %s."),
	perform    = Pattern(SPELLPERFORMOTHERSTART or "%s begins to perform %s."),
	hit        = Pattern(SPELLLOGOTHEROTHER or "%s's %s hits %s for %d."),
	crit       = Pattern(SPELLLOGCRITOTHEROTHER or "%s's %s crits %s for %d."),
	hitYou     = Pattern(SPELLLOGOTHERSELF or "%s's %s hits you for %d."),
	critYou    = Pattern(SPELLLOGCRITOTHERSELF or "%s's %s crits you for %d."),
	castGo     = Pattern(SPELLCASTGOOTHER or "%s casts %s."),
	castOn     = Pattern(SPELLCASTGOOTHERTARGETTED or "%s casts %s on %s."),
	performGo  = Pattern(SPELLPERFORMGOOTHER or "%s performs %s."),
	performOn  = Pattern(SPELLPERFORMGOOTHERTARGETTED or "%s performs %s on %s."),
	resist     = Pattern(SPELLRESISTOTHEROTHER or "%s's %s was resisted by %s."),
	resistYou  = Pattern(SPELLRESISTOTHERSELF or "%s's %s was resisted."),
	youKick    = Pattern(SPELLINTERRUPTSELFOTHER or "You interrupt %s's %s."),
	otherKick  = Pattern(SPELLINTERRUPTOTHEROTHER or "%s interrupts %s's %s."),
	afflicted  = Pattern(AURAADDEDOTHERHARMFUL or "%s is afflicted by %s."),
	dies       = Pattern(UNITDIESOTHER or "%s dies."),
	slain      = Pattern(PARTYKILLOTHER or "%s is slain by %s!"),
}

local function Learned()
	if type(SHPlatesLearned) ~= "table" then SHPlatesLearned = {} end
	if type(SHPlatesLearned.castTimes) ~= "table" then SHPlatesLearned.castTimes = {} end
	return SHPlatesLearned.castTimes
end

local function Changed(name)
	if SHPlates.OnCastChangedByName then SHPlates.OnCastChangedByName(name) end
end

local function Start(caster, spell)
	local info = SHPlates.CastTimes[spell]
	local ms = (info and info.t) or Learned()[spell]
	local cast = {
		spell = spell,
		icon = info and info.icon and ("Interface\\Icons\\" .. info.icon) or "Interface\\Icons\\INV_Misc_QuestionMark",
		start = GetTime(),
		guessed = not ms,
	}
	cast.finish = cast.start + (ms or DEFAULT_MS) / 1000
	byName[caster] = cast
	Changed(caster)
end

-- landed: the spell finished, so a guessed cast time can be learned
local function Stop(caster, spell, landed)
	local cast = caster and byName[caster]
	if not cast or (spell and cast.spell ~= spell) then return end
	if landed and cast.guessed then
		local took = (GetTime() - cast.start) * 1000
		if took >= 300 and took <= 10000 then Learned()[cast.spell] = math.floor(took / 100 + .5) * 100 end
	end
	byName[caster] = nil
	Changed(caster)
end

function CastLog.Get(name)
	local cast = name and byName[name]
	if cast and GetTime() > cast.finish + .2 then byName[name] = nil; return nil end
	return cast
end

local function M(msg, pattern) return string.find(msg, pattern) end

local function Parse(msg)
	if not msg then return end
	local _, a, b, c
	_, _, a, b = M(msg, P.start); if a then Start(a, b); return end
	_, _, a, b = M(msg, P.perform); if a then Start(a, b); return end
	_, _, a, b = M(msg, P.hit); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.crit); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.hitYou); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.critYou); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.castOn); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.castGo); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.performOn); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.performGo); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.resist); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.resistYou); if a then Stop(a, b, true); return end
	_, _, a, b = M(msg, P.youKick); if a then Stop(a, b); return end
	_, _, c, a, b = M(msg, P.otherKick); if a then Stop(a, b); return end
	-- stunned, silenced or feared by something that breaks casts
	_, _, a, b = M(msg, P.afflicted)
	if a then
		if SHPlates.CastInterrupts[b] then Stop(a) end
		return
	end
	_, _, a = M(msg, P.dies); if a then Stop(a); return end
	_, _, a = M(msg, P.slain); if a then Stop(a); return end
end

local EVENTS = {
	"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
	"CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
	"CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
	"CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
	"CHAT_MSG_SPELL_PARTY_DAMAGE", "CHAT_MSG_SPELL_PARTY_BUFF",
	"CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_COMBAT_HOSTILE_DEATH",
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		for k in pairs(byName) do byName[k] = nil end
		if not C.HasSuperWoW and not this.listening then
			this.listening = true
			for i = 1, table.getn(EVENTS) do this:RegisterEvent(EVENTS[i]) end
		end
		return
	end
	if SHPlates.disabled then return end
	Parse(arg1)
end)

CastLog.Parse = Parse  -- for testing
