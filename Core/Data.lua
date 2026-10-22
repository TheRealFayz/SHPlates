-------------------------------------------------------------------------------
-- SHPlates: Data
-- The 1.12 client has no threat API, no UnitCastingInfo, no aura durations
-- and no combat log GUIDs. This module rebuilds that information from:
--   * SuperWoW : UNIT_CASTEVENT (casts by GUID), GUID unit tokens, UnitPosition
--   * Nampower : AURA_CAST_* (aura durations + caster), SPELL_MISS_* (misses)
--   * The Turtle/OctoWoW server's threat API. SHPlates asks the server itself
--     (the same request TWThreat uses), so no other addon is needed.
-- Everything degrades gracefully when one of them is missing.
-------------------------------------------------------------------------------

local C = SHPlates.Compat
local Data = {}
SHPlates.Data = Data

local GetTime = GetTime
local wipe = C.wipe

Data.casts = {}      -- guid -> { spellId, spell, icon, start, finish, channel }
Data.lastStop = {}   -- guid -> { kind = "CAST"|"FAIL", spellId, time }
Data.auras = {}      -- guid -> spellId -> { expires, duration, caster }   (Nampower)
Data.castTimers = {} -- guid -> spell name -> { expires, duration, caster } (fallback)
Data.roster = {}     -- player name -> unitid (party/raid)
Data.groupRoles = {} -- player name -> "Tank"/"DPS" (broadcast by other SHPlates users)
Data.threat = {
	target = {},      -- name -> { threat, perc, tank }  (player's current target)
	targetStamp = 0,
	tankmode = {},    -- mob guid -> { holder, perc, creature }
	tankStamp = 0,
}

local ADDON_PREFIX = "SHPlates"
local THREAT_REQUEST = "TWT_UDTSv4_TM"   -- server threat query (with all-mob list)
local THREAT_LIMIT = "limit=10"

local playerName = UnitName("player")
local playerGUID

local function Notify(guid)
	if SHPlates.OnCastChanged then SHPlates.OnCastChanged(guid) end
end

local function NotifyAura(guid)
	if SHPlates.OnAuraChanged then SHPlates.OnAuraChanged(guid) end
end

local function GroupChannel()
	if UnitInRaid("player") then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

-------------------------------------------------------------------------------
-- Casts
-------------------------------------------------------------------------------
local function StartCast(guid, spellId, durationMs, channel)
	if not guid then return end
	local spell, icon = C.SpellNameIcon(spellId)
	local cast = {}
	local now = GetTime()
	cast.spellId = spellId
	cast.spell = spell or "Casting"
	cast.icon = icon
	cast.start = now
	cast.finish = now + ((durationMs or 0) / 1000)
	cast.channel = channel
	Data.casts[guid] = cast
	Notify(guid)
end

local function StopCast(guid, kind)
	if not guid then return end
	local cast = Data.casts[guid]
	if cast then
		Data.lastStop[guid] = { kind = kind, spellId = cast.spellId, time = GetTime(), start = cast.start }
		Data.casts[guid] = nil
		Notify(guid)
	end
end

function Data.GetCast(guid)
	if not guid then return nil end
	local cast = Data.casts[guid]
	if cast and GetTime() > cast.finish + .2 then
		Data.casts[guid] = nil
		return nil
	end
	return cast
end

-------------------------------------------------------------------------------
-- Auras (Nampower)
-------------------------------------------------------------------------------
function Data.GetAuraTimer(guid, spellId, name)
	if not guid then return nil end
	local now = GetTime()
	local list = spellId and Data.auras[guid]
	local aura = list and list[spellId]
	if aura then
		if aura.expires >= now then return aura.expires, aura.duration, aura.caster end
		list[spellId] = nil
	end
	-- fallback: timer started from a cast we saw (duration table)
	local byName = name and Data.castTimers[guid]
	aura = byName and byName[name]
	if aura then
		if aura.expires >= now then return aura.expires, aura.duration, aura.caster end
		byName[name] = nil
	end
	return nil
end

-- A spell finished casting on a target: start a fallback timer if we know
-- its duration and Nampower didn't already give us one
local function TrackCastTimer(caster, target, spellId)
	if not (caster and target and spellId and SpellInfo) then return end
	local name, rank = SpellInfo(spellId)
	local duration = SHPlates.GetFallbackDuration and SHPlates.GetFallbackDuration(name, rank)
	if not duration then return end
	local list = Data.castTimers[target]
	if not list then list = {}; Data.castTimers[target] = list end
	list[name] = { expires = GetTime() + duration, duration = duration, caster = caster }
	NotifyAura(target)
end

-- Stunned? (throttled per unit; reads debuff names through SuperWoW)
local stunCache = {}
function Data.IsStunned(guid)
	if not (guid and SpellInfo and SHPlates.StunEffects) then return false end
	local now = GetTime()
	local c = stunCache[guid]
	if c and now - c.time < .4 then return c.value end
	local value = false
	for i = 1, 16 do
		local icon, _, _, auraId = UnitDebuff(guid, i)
		if not icon then break end
		local name = auraId and SpellInfo(auraId)
		if name and SHPlates.StunEffects[name] then value = true; break end
	end
	if not c then c = {}; stunCache[guid] = c end
	c.time, c.value = now, value
	return value
end

-- Is anyone else close to taking aggro off you? (your target, server data)
function Data.IsLosingAggro(unit)
	if not (unit.isTarget and GetTime() - Data.threat.targetStamp < 2.5) then return false end
	local me = Data.threat.target[playerName]
	if not (me and me.tank) then return false end
	for name, entry in pairs(Data.threat.target) do
		if name ~= playerName and entry.perc >= 85 then return true end
	end
	return false
end

function Data.PlayerGUID()
	if not playerGUID then playerGUID = C.GUID("player") end
	return playerGUID
end

function Data.IsMine(casterGUID)
	if not casterGUID then return nil end
	return casterGUID == Data.PlayerGUID()
end

-------------------------------------------------------------------------------
-- Roster / tanks
-------------------------------------------------------------------------------
local function UpdateRoster()
	wipe(Data.roster)
	if UnitInRaid("player") then
		for i = 1, GetNumRaidMembers() do
			local id = "raid" .. i
			local name = UnitName(id)
			if name then Data.roster[name] = id end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local id = "party" .. i
			local name = UnitName(id)
			if name then Data.roster[name] = id end
		end
	end
	if UnitExists("pet") then
		local pet = UnitName("pet")
		if pet then Data.roster[pet] = "pet" end
	end
	-- forget roles of people who left
	for name in pairs(Data.groupRoles) do
		if not Data.roster[name] then Data.groupRoles[name] = nil end
	end
end
Data.UpdateRoster = UpdateRoster

-- Is this name a group member (or our pet)?
function Data.InGroup(name)
	return name and (Data.roster[name] ~= nil or name == playerName)
end

-- Tanks: group members whose SHPlates is in Tank mode, the manual list, your pet.
-- (1.12 has no main tank assignment like 3.3.5's GetPartyAssignment.)
function Data.IsRaidTank(name)
	if not name then return false end
	if Data.groupRoles[name] == "Tank" then return true end
	if SHPlatesDB and SHPlatesDB.tankNames and SHPlatesDB.tankNames[name] then return true end
	if UnitExists("pet") and UnitName("pet") == name then return true end
	return false
end

-- Tell other SHPlates users in the group which mode we're in
local lastRoleSent, lastRoleTime = nil, 0
function Data.BroadcastRole(force)
	local channel = GroupChannel()
	if not channel or not SHPlates.GetRole then return end
	local role = SHPlates.GetRole()
	local now = GetTime()
	if not force and role == lastRoleSent and now - lastRoleTime < 30 then return end
	lastRoleSent, lastRoleTime = role, now
	SendAddonMessage(ADDON_PREFIX, "ROLE:" .. role, channel)
	-- GudaPlates users read tanks from their own channel: tell them too
	SendAddonMessage("GudaPlates", (role == "Tank") and "TM=1" or "TM=0", channel)
end

-------------------------------------------------------------------------------
-- Threat / aggro
-------------------------------------------------------------------------------
local TARGET_FRESH, TANKMODE_FRESH = 2.5, 3


-- Who the mob is attacking. Server data first, then the mob's own target.
function Data.GetAggroHolder(unit)
	local guid = unit.guid
	local now = GetTime()
	if guid then
		local tm = Data.threat.tankmode[guid]
		if tm and now - Data.threat.tankStamp < TANKMODE_FRESH then return tm.holder, "server" end
		local tot = guid .. "target"
		if UnitExists(tot) then return UnitName(tot), "target" end
		return nil
	end
	-- No SuperWoW: only possible for the target/mouseover
	local unitid
	if unit.isTarget then unitid = "targettarget"
	elseif unit.isMouseover then unitid = "mouseovertarget" end
	if unitid and UnitExists(unitid) then return UnitName(unitid), "target" end
	return nil
end

local function TargetThreatFresh(unit)
	return unit.isTarget and GetTime() - Data.threat.targetStamp < TARGET_FRESH
end

-- LOW / MEDIUM / HIGH, same meaning as the 3.3.5 aggro glow
function Data.GetThreatSituation(unit)
	if not C.InCombat() then return "LOW" end
	if unit.reaction == "FRIENDLY" or unit.type ~= "NPC" then return "LOW" end
	if unit.guid and not UnitAffectingCombat(unit.guid) then return "LOW" end

	if TargetThreatFresh(unit) then
		local me = Data.threat.target[playerName]
		if me then
			if me.tank then return "HIGH" end
			if me.perc >= 80 then return "MEDIUM" end
			return "LOW"
		end
	end
	local holder = Data.GetAggroHolder(unit)
	if holder and holder == playerName then return "HIGH" end
	return "LOW"
end

-- Returns threat (scale: <100 not tanking, >100 tanking with lead), holder name,
-- and a flag that is true when the number is an estimate (no server data).
function Data.GetRelativeThreat(unit)
	if not unit then return nil end
	if TargetThreatFresh(unit) then
		local list = Data.threat.target
		local me = list[playerName]
		if me then
			local holder, second = nil, 0
			for name, entry in pairs(list) do
				if name ~= playerName then
					if entry.perc > second then second = entry.perc end
					if entry.tank then holder = name end
				end
			end
			if me.tank then
				return 100 + (100 - math.min(second, 100)), nil, false
			end
			return me.perc, holder, false
		end
	end
	-- Estimate from the mob's target
	local holder = Data.GetAggroHolder(unit)
	if not holder then return nil end
	if holder == playerName then return 150, nil, true end
	return 50, holder, true
end

-------------------------------------------------------------------------------
-- Range (SuperWoW UnitPosition, else interact distances)
-------------------------------------------------------------------------------
function Data.GetRange(unitid)
	if not UnitExists(unitid) then return nil end
	if UnitPosition then
		local px, py, pz = UnitPosition("player")
		local ux, uy, uz = UnitPosition(unitid)
		if px and ux then
			local dx, dy, dz = px - ux, py - uy, (pz or 0) - (uz or 0)
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end
	end
	if CheckInteractDistance(unitid, 3) then return 9
	elseif CheckInteractDistance(unitid, 2) then return 11
	elseif CheckInteractDistance(unitid, 4) then return 28
	elseif UnitIsVisible(unitid) then return 100 end
	return nil
end

-------------------------------------------------------------------------------
-- Server threat packets
-- TWTv4=name:tank:threat:perc:melee;...   (your target, perc relative to tank)
-- TMTv1=creature:guid:holder:perc;...     (every mob you're fighting)
-- Both can arrive in one message, separated by '#'.
-------------------------------------------------------------------------------
local function Split(str, sep)
	local t = {}
	for part in string.gfind(str, "([^" .. sep .. "]+)") do table.insert(t, part) end
	return t
end

local function PacketBody(msg, api)
	local s = string.find(msg, api, 1, true)
	if not s then return nil end
	local body = string.sub(msg, s + string.len(api))
	local hash = string.find(body, "#", 1, true)
	if hash then body = string.sub(body, 1, hash - 1) end
	return body
end

local function HandleThreatPacket(msg)
	local body = PacketBody(msg, "TWTv4=")
	if not body then return end
	local list = wipe(Data.threat.target)
	local entries = Split(body, ";")
	for i = 1, table.getn(entries) do
		local p = Split(entries[i], ":")
		if p[1] and p[2] and p[3] and p[4] then
			list[p[1]] = { tank = (p[2] == "1"), threat = tonumber(p[3]) or 0, perc = tonumber(p[4]) or 0 }
		end
	end
	Data.threat.targetStamp = GetTime()
end

local function HandleTankModePacket(msg)
	local body = PacketBody(msg, "TMTv1=")
	if not body then return end
	local list = wipe(Data.threat.tankmode)
	local entries = Split(body, ";")
	for i = 1, table.getn(entries) do
		local p = Split(entries[i], ":")
		if p[1] and p[2] and p[3] then
			list[p[2]] = { creature = p[1], holder = p[3], perc = tonumber(p[4]) or 0 }
		end
	end
	Data.threat.tankStamp = GetTime()
end

-- Ask the server for threat while fighting in a group
local queryTimer = 0
local function QueryThreat(elapsed)
	queryTimer = queryTimer + elapsed
	local interval = (SHPlates.GetRole and SHPlates.GetRole() == "Tank") and .6 or 1
	if queryTimer < interval then return end
	queryTimer = 0
	if not C.InCombat() then return end
	local channel = GroupChannel()
	if not channel then return end
	if not (UnitExists("target") and UnitAffectingCombat("target")) or UnitIsPlayer("target") then return end
	-- another addon (e.g. TWThreat) is already asking: just listen
	if GetTime() - Data.threat.targetStamp < interval * .8 then return end
	SendAddonMessage(THREAT_REQUEST, THREAT_LIMIT, channel)
end

-------------------------------------------------------------------------------
-- Nampower CVars: switched on automatically (never switched off, since other
-- addons may rely on them too)
-------------------------------------------------------------------------------
function Data.EnableNampowerEvents()
	if not C.HasNampower then return end
	C.SetCVarSafe("NP_EnableAuraCastEvents", "1")
	C.SetCVarSafe("NP_EnableSpellMissEvents", "1")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local events = {}

function events.PLAYER_ENTERING_WORLD()
	playerName = UnitName("player")
	playerGUID = C.GUID("player")
	wipe(Data.casts)
	wipe(Data.auras)
	wipe(Data.lastStop)
	UpdateRoster()
	Data.EnableNampowerEvents()
	Data.BroadcastRole(true)
end
local function RosterChanged() UpdateRoster(); Data.BroadcastRole(true) end
events.PARTY_MEMBERS_CHANGED = RosterChanged
events.RAID_ROSTER_UPDATE = RosterChanged
events.UNIT_PET = UpdateRoster

-- SuperWoW: arg1 caster, arg2 target, arg3 type, arg4 spellId, arg5 duration(ms)
function events.UNIT_CASTEVENT()
	local guid, kind, spellId, duration = arg1, arg3, arg4, arg5
	if kind == "START" then
		StartCast(guid, spellId, duration, false)
	elseif kind == "CHANNEL" then
		StartCast(guid, spellId, duration, true)
	elseif kind == "CAST" then
		local cast = Data.casts[guid]
		if cast and not cast.channel and cast.spellId == spellId then StopCast(guid, "CAST") end
	elseif kind == "FAIL" then
		StopCast(guid, "FAIL")
	end
	if kind == "CAST" and arg2 and arg2 ~= "" then TrackCastTimer(guid, arg2, spellId) end
	if SHPlates.Interrupts then SHPlates.Interrupts.OnCastEvent(arg1, arg2, kind, spellId) end
end

-- Nampower fallbacks / extras
function events.SPELL_START_OTHER()
	if C.HasSuperWoW then return end -- UNIT_CASTEVENT already covers it
	StartCast(arg3, arg2, arg6, false)
end
function events.SPELL_FAILED_OTHER() StopCast(arg1, "FAIL") end

local function OnAuraCast()
	-- spellId, casterGuid, targetGuid, effect, effectAuraName, amplitude, misc, durationMs
	local spellId, caster, target, durationMs = arg1, arg2, arg3, arg8
	if not (target and spellId and durationMs) or durationMs <= 0 then return end
	local list = Data.auras[target]
	if not list then list = {}; Data.auras[target] = list end
	local aura = list[spellId] or {}
	aura.duration = durationMs / 1000
	aura.expires = GetTime() + aura.duration
	aura.caster = caster
	list[spellId] = aura
	NotifyAura(target)
end
events.AURA_CAST_ON_OTHER = OnAuraCast
events.AURA_CAST_ON_SELF = OnAuraCast

local function OnAuraRemoved()
	-- guid, slot, spellId, stackCount (0 = fully removed)
	local guid, spellId, stacks = arg1, arg3, arg4
	if stacks and stacks > 0 then NotifyAura(guid); return end
	local list = Data.auras[guid]
	if list then list[spellId] = nil end
	NotifyAura(guid)
end
events.DEBUFF_REMOVED_OTHER = OnAuraRemoved
events.DEBUFF_ADDED_OTHER = function() NotifyAura(arg1) end

-- Nampower: casterGuid, targetGuid, spellId, missInfo
local function OnSpellMiss()
	if SHPlates.Interrupts then SHPlates.Interrupts.OnMiss(arg1, arg2, arg3, arg4) end
end
events.SPELL_MISS_SELF = OnSpellMiss
events.SPELL_MISS_OTHER = OnSpellMiss

-- Without Nampower: read our own misses from the combat log text
function events.CHAT_MSG_SPELL_SELF_DAMAGE()
	if SHPlates.Interrupts then SHPlates.Interrupts.OnSelfDamageText(arg1) end
end

function events.UNIT_DIED()
	if arg1 then
		Data.casts[arg1] = nil
		Data.auras[arg1] = nil
		Data.castTimers[arg1] = nil
		Notify(arg1)
	end
end

function events.CHAT_MSG_ADDON()
	local prefix, msg, sender = arg1, arg2, arg4
	if not msg then return end
	if prefix == ADDON_PREFIX then
		local _, _, role = string.find(msg, "^ROLE:(%a+)")
		if role and sender and sender ~= playerName then Data.groupRoles[sender] = role end
		return
	end
	if prefix == "GudaPlates" and sender and sender ~= playerName then
		local _, _, tm = string.find(msg, "^TM=(%d)")
		if tm then Data.groupRoles[sender] = (tm == "1") and "Tank" or "DPS" end
		return
	end
	if string.find(msg, "TWTv4=", 1, true) then HandleThreatPacket(msg) end
	if string.find(msg, "TMTv1=", 1, true) then HandleTankModePacket(msg) end
end

frame:SetScript("OnEvent", function()
	if SHPlates.disabled then return end
	local handler = events[event]
	if handler then handler() end
end)
-- pcall: events from SuperWoW/Nampower may not exist on this client
for name in pairs(events) do pcall(frame.RegisterEvent, frame, name) end

-- Threat queries + drop stale data now and then
local sweep = 0
frame:SetScript("OnUpdate", function()
	if SHPlates.disabled then return end
	local elapsed = arg1 or 0
	QueryThreat(elapsed)
	sweep = sweep + elapsed
	if sweep < 10 then return end
	sweep = 0
	local now = GetTime()
	for guid, list in pairs(Data.auras) do
		local any = false
		for id, aura in pairs(list) do
			if aura.expires < now then list[id] = nil else any = true end
		end
		if not any then Data.auras[guid] = nil end
	end
	for guid, cast in pairs(Data.casts) do
		if cast.finish + 1 < now then Data.casts[guid] = nil end
	end
	for guid, list in pairs(Data.castTimers) do
		local any = false
		for name, t in pairs(list) do
			if t.expires < now then list[name] = nil else any = true end
		end
		if not any then Data.castTimers[guid] = nil end
	end
	for guid, c in pairs(stunCache) do
		if now - c.time > 10 then stunCache[guid] = nil end
	end
	for guid, stop in pairs(Data.lastStop) do
		if stop.time + 5 < now then Data.lastStop[guid] = nil end
	end
end)
