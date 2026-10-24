-------------------------------------------------------------------------------
-- SHPlates: Core
-- Port of the Tidy Plates engine to the 1.12 client.
--
-- What changed versus 3.3.5:
--   * Vanilla plates are Buttons with regions border, glow, name, level,
--     levelicon (skull), raidicon and ONE child (the health bar). There is no
--     cast bar and no threat glow on the plate itself.
--   * Unit identity comes from SuperWoW (plate:GetName(1) returns the GUID).
--     That GUID is used as a unit token for class, elite, combat and target.
--   * Casts come from UNIT_CASTEVENT (see Data.lua) for every plate, not just
--     the target. Aggro comes from Data.GetThreatSituation.
--   * Lua 5.0: no '#', no select, no '...' varargs, script handlers use 'this'.
--
-- The theme API is unchanged: SetStyle, SetScale, SetAlpha, SetHealthbarColor,
-- SetThreatColor, SetCastbarColor, SetSpecialText, SetSpecialText2,
-- SetSpecialArt, OnInitialize, OnUpdate, OnContextUpdate.
-------------------------------------------------------------------------------

local C = SHPlates.Compat
local Data = SHPlates.Data
local wipe, InCombat = C.wipe, C.InCombat
local pairs, tostring, GetTime = pairs, tostring, GetTime
local CreateStatusbar = SHPlates.CreateStatusbar

-------------------------------------------------------------------------------
-- I. Variables and Simple Functions
-------------------------------------------------------------------------------
local activetheme = {}
local numChildren = -1
local echoUpdateList = {}
local echoSelf = {}
local ForEachPlate
local EMPTY_TEXTURE = SHPlates.MEDIA .. "Empty"
local useAutoHide = false
local inCombat, HasTarget = false, false
local targetGUID, targetName
local Plates, PlatesVisible = {}, {}
local GUID = {}

-- Show or hide everything a plate draws, part by part. The 1.12 client only
-- passes a frame's opacity down to the children that exist when it is set,
-- so widgets a theme creates later (mana bar, class icon...) would stay
-- visible on a hidden plate. Parts are fully on or off; the plate frame
-- itself carries the in-between opacity (non-target fading).
local function SetPartsAlpha(ext, alpha)
	local a = (alpha and alpha > 0) and 1 or 0
	local b = ext.bars
	if b then
		if b.healthbar then b.healthbar:SetAlpha(a) end
		if b.castbar then b.castbar:SetAlpha(a) end
	end
	if ext.iconFrame then ext.iconFrame:SetAlpha(a) end
	if ext.widgets then
		for _, w in pairs(ext.widgets) do
			if type(w) == "table" and w.SetAlpha then w:SetAlpha(a) end
		end
	end
end

-- How far a plate's health bar is from what the GUID's unit really has (0-1)
local function HealthMismatch(plate, guid)
	local ext = plate.extended
	local bar = ext and ext.bars and ext.bars.health
	if not bar then return 0 end
	local _, barMax = bar:GetMinMaxValues()
	local realMax = UnitHealthMax(guid)
	if not (barMax and barMax > 0 and realMax and realMax > 0) then return 0 end
	return math.abs((bar:GetValue() or 0) / barMax - (UnitHealth(guid) or 0) / realMax)
end

-- The plate's GUID, unless another visible plate holds the same one and fits
-- it better. The client can leave a recycled plate holding the previous mob's
-- GUID; in a pack of same-named mobs the name check can't catch that, and two
-- plates would read one mob (its debuffs showing on both). Health decides.
local function ResolveGUID(plate, plateName)
	local guid = C.PlateGUID(plate, plateName)
	if not guid then return nil end
	local other = GUID[guid]
	if other and other ~= plate and other:IsShown() then
		if HealthMismatch(plate, guid) >= HealthMismatch(other, guid) then return nil end
	end
	return guid
end
local nameplate, extended, bars, regions, visual
local unit, unitcache, style, stylename
local lastMouseover, currentTarget, unitchanged
local forceStyleUpdate = false

local overlapMode = false   -- "Allow overlapping nameplates"

-- Vanilla stacks plates using the size of the Blizzard frame. For overlap,
-- that frame shrinks to 1x1 and stops taking the mouse; our own click frame
-- (extended.clicker) takes over and forwards clicks to it.
local function Opt(key) return SHPlatesDB and SHPlatesDB[key] end

local CLASS_COLORS = {
	WARRIOR = { .78, .61, .43 }, MAGE = { .41, .80, .94 }, ROGUE = { 1, .96, .41 },
	DRUID = { 1, .49, .04 }, HUNTER = { .67, .83, .45 }, SHAMAN = { 0, .44, .87 },
	PRIEST = { 1, 1, 1 }, WARLOCK = { .58, .51, .79 }, PALADIN = { .96, .55, .73 },
}
SHPlates.CLASS_COLORS = CLASS_COLORS

local CRITTER_TYPES = { ["Critter"] = true, ["Kleintier"] = true, ["Bestiole"] = true, ["Alimaña"] = true }

-- Neutral mobs that joined the fight (same idea as GudaPlates): once a neutral
-- mob has gone after you or your group it stays "hostile" until it dies or
-- the fight is over. Without this it flickers back to hidden whenever it
-- briefly has no target (stuns, fear, switching targets, chasing a pet).
local angryNeutrals = {}
local function RememberAngry(guid) angryNeutrals[guid] = true end
local function IsAngryNeutral(guid)
	if not (guid and angryNeutrals[guid]) then return false end
	if UnitIsDead(guid) or not UnitExists(guid) then angryNeutrals[guid] = nil; return false end
	return true
end
SHPlates.IsAngryNeutral = IsAngryNeutral

-- Global (theme independent) visibility rules from the General page
local function IsFilteredOut(u)
	if u.isTarget then return false end
	if Opt("hideFriendly") and u.reaction == "FRIENDLY" then return true end
	if Opt("showCritters") == false and u.isCritter then return true end
	return false
end

SHPlates.IsFilteredOut = IsFilteredOut

local function ApplyPlateMouse(plate, clickable)
	if Opt("clickThrough") then clickable = false end
	local ext = plate.extended
	if overlapMode then
		if plate:GetWidth() > 1 then plate:SetWidth(1); plate:SetHeight(1) end
		plate:EnableMouse(false)
		ext.clicker:EnableMouse(clickable)
	else
		plate:EnableMouse(clickable)
		ext.clicker:EnableMouse(false)
	end
end

-- Stacking: the game spaces plates using the Blizzard frame's size, so in
-- stacking mode that frame covers everything SHPlates draws (frame size times
-- the current scale), not just Tidy Plates' smaller click hitbox.
local function UpdateStackingSize(plate)
	local ext = plate.extended
	if overlapMode then return end
	local st = ext.style
	if not (st and st.frame and st.hitbox) then return end
	local scale = ext:GetScale() or 1
	local w = math.max(st.hitbox.width or 0, st.frame.width or 0) * scale
	local h = math.max(st.hitbox.height or 0, st.frame.height or 0) * scale
	if ext.stackW ~= w or ext.stackH ~= h or math.abs(plate:GetWidth() - w) > .5 then
		ext.stackW, ext.stackH = w, h
		plate:SetWidth(w); plate:SetHeight(h)
	end
end

local POLL_INTERVAL = .2     -- full data refresh of visible plates
local pollTimer = 0

SHPlates.GUID = GUID
SHPlates.VisibleNameplates = PlatesVisible
SHPlates.AllNameplates = Plates

local function IsPlateShown(plate) if plate:IsShown() then return true end end
local function SetSelfEcho(plate, func) if func then echoSelf[plate] = func end end
local function SetEchoUpdate(func) if func then echoUpdateList[func] = true end end

local RaidIconNames = { "STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL" }
local RaidIconIndex = {}
for i = 1, 8 do RaidIconIndex[RaidIconNames[i]] = i end

local function RaidIconCoords(index)
	local left = math.mod(index - 1, 4) * .25
	local top = math.floor((index - 1) / 4) * .25
	return left, left + .25, top, top + .25
end

-------------------------------------------------------------------------------
-- II. Frame/Layer Appearance Functions
-------------------------------------------------------------------------------
local function SetObjectShape(object, width, height)
	if width then object:SetWidth(width) end
	if height then object:SetHeight(height) end
end
local function SetObjectFont(object, font, size, flags)
	if flags == "NONE" then flags = "" end
	object:SetFont(font, size, flags or "")
end
local function SetObjectJustify(object, horz, vert)
	object:SetJustifyH(horz or "CENTER")
	if vert == "CENTER" then vert = "MIDDLE" end
	object:SetJustifyV(vert or "MIDDLE")
end
local function SetObjectShadow(object, shadow)
	if shadow then object:SetShadowColor(0, 0, 0, 1); object:SetShadowOffset(1, -1)
	else object:SetShadowColor(0, 0, 0, 0) end
end
local function SetObjectAnchor(object, anchor, anchorTo, x, y)
	object:ClearAllPoints()
	object:SetPoint(anchor or "CENTER", anchorTo, anchor or "CENTER", x or 0, y or 0)
end
local function SetObjectTexture(object, texture) object:SetTexture(texture); object:SetTexCoord(0, 1, 0, 1) end
local function SetObjectBartexture(object, texture, orientation)
	object:SetStatusBarTexture(texture)
	object:SetOrientation(orientation)
end

local function SetFontGroupObject(object, objectstyle)
	SetObjectFont(object, objectstyle.typeface, objectstyle.size, objectstyle.flags)
	SetObjectJustify(object, objectstyle.align, objectstyle.vertical)
	SetObjectShadow(object, objectstyle.shadow)
end

local function SetAnchorGroupObject(object, objectstyle, anchorTo)
	SetObjectShape(object, objectstyle.width, objectstyle.height)
	SetObjectAnchor(object, objectstyle.anchor, anchorTo, objectstyle.x, objectstyle.y)
end

local function SetBarGroupObject(object, objectstyle, anchorTo)
	SetObjectShape(object, objectstyle.width, objectstyle.height)
	SetObjectAnchor(object, objectstyle.anchor, anchorTo, objectstyle.x, objectstyle.y)
	SetObjectBartexture(object, objectstyle.texture, objectstyle.orientation)
	object:UpdateSize()
end

-------------------------------------------------------------------------------
-- III. Nameplate Style
-------------------------------------------------------------------------------
local UpdateStyle
do
	local objectstyle, objectname
	local fontgroup = { "name", "level", "specialText", "specialText2" }
	local anchorgroup = { "healthborder", "threatborder", "castborder", "castnostop",
		"name", "specialText", "specialText2", "level",
		"specialArt", "spellicon", "raidicon", "dangerskull" }
	local bargroup = { "castbar", "healthbar" }
	local nfont, nanchor, nbar = 4, 12, 2

	function UpdateStyle()
		local styleOptions = style.options
		-- Hitbox (vanilla has no combat protection on plates)
		objectstyle = style.hitbox
		SetObjectShape(extended.clicker, objectstyle.width, objectstyle.height)
		if overlapMode then SetObjectShape(nameplate, 1, 1)
		else extended.stackW = nil; UpdateStackingSize(nameplate) end
		-- Frame
		SetAnchorGroupObject(extended, style.frame, nameplate)
		for i = 1, nanchor do
			objectname = anchorgroup[i]
			SetAnchorGroupObject(visual[objectname], style[objectname], extended)
		end
		for i = 1, nbar do
			objectname = bargroup[i]
			SetBarGroupObject(bars[objectname], style[objectname], extended)
		end
		SetObjectTexture(visual.castborder, style.castborder.texture)
		SetObjectTexture(visual.castnostop, style.castnostop.texture)
		for i = 1, nfont do
			objectname = fontgroup[i]
			SetFontGroupObject(visual[objectname], style[objectname])
		end
		-- Mouseover highlight follows the health border
		visual.highlight:SetTexture(style.healthborder.glowtexture)
		visual.highlight:ClearAllPoints()
		visual.highlight:SetAllPoints(visual.healthborder)
		-- Show/Hide
		if styleOptions.showName then visual.name:Show() else visual.name:Hide() end
		if styleOptions.showSpecialText then visual.specialText:Show() else visual.specialText:Hide() end
		if styleOptions.showSpecialText2 then visual.specialText2:Show() else visual.specialText2:Hide() end
		if styleOptions.showSpecialArt then visual.specialArt:Show() else visual.specialArt:Hide() end
		if styleOptions.showSpellIcon then visual.spellicon:Show() else visual.spellicon:Hide() end
		if styleOptions.showLevel and (not unit.isBoss) then visual.level:Show() else visual.level:Hide() end
		if unit.isBoss and styleOptions.showDangerSkull then visual.dangerskull:Show() else visual.dangerskull:Hide() end
	end
end

-------------------------------------------------------------------------------
-- IV. Indicators
-------------------------------------------------------------------------------
local UpdateIndicator_CustomScaleText, UpdateIndicator_HealthBar, UpdateIndicator_Standard
local UpdateIndicator_All, UpdateIndicator_CustomAlpha, UpdateIndicator_Level, UpdateIndicator_ThreatGlow
local UpdateIndicator_RaidIcon, UpdateIndicator_EliteIcon, UpdateIndicator_UnitColor, UpdateIndicator_Name
do
	local threatborder, alpha, forcealpha, scale
	alpha = 1

	local function ApplyHealthColor()
		-- Tapped and stunned colors win over everything (as in GudaPlates)
		if unit.isTapped and Opt("tappedColorOn") ~= false then
			local c = Opt("tappedColor") or { r = .5, g = .5, b = .5 }
			bars.healthbar:SetStatusBarColor(c.r, c.g, c.b)
		elseif unit.isStunned and Opt("stunColorOn") ~= false then
			local c = Opt("stunColor") or { r = .376, g = .027, b = .431 }
			bars.healthbar:SetStatusBarColor(c.r, c.g, c.b)
		elseif activetheme.SetHealthbarColor then
			bars.healthbar:SetStatusBarColor(activetheme.SetHealthbarColor(unit))
		else bars.healthbar:SetStatusBarColor(unit.red, unit.green, unit.blue) end
	end

	function UpdateIndicator_HealthBar()
		ApplyHealthColor()
		bars.healthbar:SetMinMaxValues(0, unit.healthmax or 1)
		bars.healthbar:SetValue(unit.health or 0)
	end

	function UpdateIndicator_Name()
		visual.name:SetText(unit.name)
	end

	function UpdateIndicator_Level()
		visual.level:SetText(unit.level)
		visual.level:SetTextColor(unit.levelcolorRed or 1, unit.levelcolorGreen or 1, unit.levelcolorBlue or 1)
	end

	function UpdateIndicator_ThreatGlow()
		local styleOptions = style.options
		threatborder = visual.threatborder
		if activetheme.SetThreatColor then
			threatborder:Show()
			threatborder:SetVertexColor(activetheme.SetThreatColor(unit))
		else
			if inCombat and styleOptions.showAggroGlow and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
				local color = style.threatcolor[unit.threatSituation]
				threatborder:Show()
				threatborder:SetVertexColor(color.r, color.g, color.b, (color.a or 1))
			else threatborder:Hide() end
		end
	end

	function UpdateIndicator_RaidIcon()
		-- Blizzard's own icon, moved onto our bar: the client shows, hides and
		-- crops it itself, so leave it alone
		local localIndex = SHPlates.Marks and SHPlates.Marks.Get(unit.guid)
		if extended.usesBlizzardRaidIcon then
			-- solo (local) marks the client doesn't draw: use our own copy
			local own = visual.raidiconOwn
			if localIndex and not regions.raidicon:IsShown() then
				own:SetTexCoord(RaidIconCoords(localIndex)); own:Show()
			else own:Hide() end
			return
		end
		local index = (unit.raidIcon and RaidIconIndex[unit.raidIcon]) or localIndex
		if index then
			visual.raidicon:Show()
			visual.raidicon:SetTexCoord(RaidIconCoords(index))
		else visual.raidicon:Hide() end
	end

	function UpdateIndicator_EliteIcon()
		threatborder = visual.threatborder
		if unit.isElite then
			visual.healthborder:SetTexture(style.healthborder.elitetexture)
			threatborder:SetTexture(style.threatborder.elitetexture)
		else
			visual.healthborder:SetTexture(style.healthborder.texture)
			threatborder:SetTexture(style.threatborder.texture)
		end
	end

	function UpdateIndicator_UnitColor()
		ApplyHealthColor()
	end

	function UpdateIndicator_Standard()
		if IsPlateShown(nameplate) then
			if unitcache.name ~= unit.name then UpdateIndicator_Name() end
			if unitcache.level ~= unit.level or unitcache.levelcolorRed ~= unit.levelcolorRed then UpdateIndicator_Level() end
			UpdateIndicator_ThreatGlow()
			UpdateIndicator_RaidIcon()
			if unitcache.isElite ~= unit.isElite then UpdateIndicator_EliteIcon() end
			if (unitcache.red ~= unit.red) or (unitcache.green ~= unit.green) or (unitcache.blue ~= unit.blue) then
				UpdateIndicator_UnitColor() end
		end
	end

	function UpdateIndicator_CustomAlpha()
		alpha = 1
		if activetheme.SetAlpha then
			alpha, forcealpha = activetheme.SetAlpha(unit)
			if forcealpha then alpha = (alpha or 1)
			else alpha = (alpha or 1) * (unit.alpha or 1) end
		else alpha = unit.alpha or 1 end
		if IsFilteredOut(unit) or extended.fastHidden then alpha = 0 end
		extended:SetAlpha(alpha)
		SetPartsAlpha(extended, alpha)
		-- Fully transparent plates should not eat clicks either
		ApplyPlateMouse(nameplate, alpha > 0)
	end

	function UpdateIndicator_CustomScaleText()
		local styleOptions = style.options
		if alpha > 0 then
			if activetheme.SetScale then
				scale = activetheme.SetScale(unit)
				if scale then extended:SetScale(scale) end
				UpdateStackingSize(nameplate)
			end
			if styleOptions.showSpecialText and activetheme.SetSpecialText then
				visual.specialText:SetText(activetheme.SetSpecialText(unit)) end
			if styleOptions.showSpecialText2 and activetheme.SetSpecialText2 then
				visual.specialText2:SetText(activetheme.SetSpecialText2(unit)) end
			if styleOptions.showSpecialArt and activetheme.SetSpecialArt then
				visual.specialArt:SetTexture(activetheme.SetSpecialArt(unit)) end
			ApplyHealthColor()
		end
	end

	function UpdateIndicator_All()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
		UpdateIndicator_Standard()
	end
end

-------------------------------------------------------------------------------
-- V. Data Gather
-------------------------------------------------------------------------------
local OnNewNameplate, OnShowNameplate, OnHideNameplate, OnUpdateNameplate, OnResetNameplate
local OnStartCast, OnStopCast, OnMouseoverNameplate, OnLeaveNameplate
local OnUpdateHealth, OnUpdateLevel, OnUpdateRaidIcon, OnUpdateReaction, OnEchoNewNameplate
local UpdateReferences
do
	local function UpdateUnitCache() for key, value in pairs(unit) do unitcache[key] = value end end

	function UpdateReferences(plate)
		unitchanged = false
		nameplate = plate
		extended = plate.extended
		bars = extended.bars
		regions = extended.regions
		unit = extended.unit
		unitcache = extended.unitcache
		visual = extended.visual
		style = extended.style
	end

	-- Vanilla health bar colors (no class colors on 1.12 plates)
	local function GetUnitReaction(red, green, blue)
		if red < .01 and blue < .01 and green > .99 then return "FRIENDLY", "NPC"
		elseif red < .01 and blue > .99 and green < .01 then return "FRIENDLY", "PLAYER"
		elseif red > .99 and blue < .01 and green > .99 then return "NEUTRAL", "NPC"
		elseif red > .99 and blue < .01 and green < .01 then return "HOSTILE", "NPC"
		else return "HOSTILE", "PLAYER" end
	end

	local function GetUnitCombatStatus(r, g, b) return (r > .5 and g < .5) end

	local function ReadRaidIcon()
		local guid = unit.guid
		if guid then
			-- SuperWoW: GUID as unit token...
			if GetRaidTargetIndex then
				local ok, index = pcall(GetRaidTargetIndex, guid)
				if ok and index and RaidIconNames[index] then return RaidIconNames[index] end
			end
			-- ...or the "mark1".."mark8" unit tokens
			for i = 1, 8 do
				local exists, markGUID = UnitExists("mark" .. i)
				if exists and markGUID == guid then return RaidIconNames[i] end
			end
		end
		-- Blizzard's own icon on the plate
		local icon = regions.raidicon
		if icon and icon:IsShown() and icon.GetTexCoord then
			local ux, uy = icon:GetTexCoord()
			if ux and uy then
				local col = math.floor(ux * 4 + .5)
				local row = math.floor(uy * 4 + .5)
				return RaidIconNames[row * 4 + col + 1]
			end
		end
		-- solo mark set with a SHPlates keybind
		local li = SHPlates.Marks and SHPlates.Marks.Get(unit.guid)
		if li then return RaidIconNames[li] end
		return nil
	end

	local function HideBlizzardRegions()
		regions.border:SetAlpha(0)
		regions.glow:SetAlpha(0)
		regions.levelicon:SetAlpha(0)
		if not extended.usesBlizzardRaidIcon then regions.raidicon:SetAlpha(0) end
		-- anything else on the Blizzard plate (in case a client or addon
		-- reordered or added regions)
		local extra = extended.blizzRegions
		for i = 1, table.getn(extra) do
			local region = extra[i]
			if region ~= visual.raidicon and region.GetObjectType and region:GetObjectType() == "Texture" then
				region:SetAlpha(0)
			end
		end
		if regions.name.SetAlpha then regions.name:SetAlpha(0) else regions.name:SetWidth(.1) end
		if regions.level.SetAlpha then regions.level:SetAlpha(0) else regions.level:SetWidth(.1) end
		-- Only once per show: re-setting the bar texture can briefly reset its
		-- color, which made neutral (yellow) mobs read as hostile and flicker
		if not extended.healthTexHidden then
			bars.health:SetStatusBarTexture(EMPTY_TEXTURE)
			extended.healthTexHidden = true
		end
		bars.health:SetAlpha(0)
	end

	-- Reaction: SuperWoW's UnitReaction when we have a GUID (bar colors in
	-- vanilla also change for tapped or fighting mobs), bar color otherwise
	local function ReadReaction()
		local r, g, b = bars.health:GetStatusBarColor()
		local white = r and r > .99 and g > .99 and b > .99
		if r and not white then
			unit.red, unit.green, unit.blue = r, g, b
			unit.reaction, unit.type = GetUnitReaction(r, g, b)
		elseif not unit.reaction then
			unit.red, unit.green, unit.blue = r or 1, g or 0, b or 0
			unit.reaction, unit.type = "HOSTILE", "NPC"
		end
		local guid = unit.guid
		if guid then
			if UnitIsPlayer(guid) then
				-- Players: friend or foe is "can I attack them", not faction.
				-- On cross-faction servers the other faction reads as neutral
				-- even when you can't touch them; they're only enemies when
				-- PvP makes them attackable.
				unit.type = "PLAYER"
				if UnitCanAttack("player", guid) then
					unit.reaction = "HOSTILE"
				else
					unit.reaction = "FRIENDLY"
					unit.red, unit.green, unit.blue = 0, 0, 1   -- vanilla's friendly player blue
				end
				return
			end
			unit.type = "NPC"
			local rx = UnitReaction and UnitReaction(guid, "player")
			if rx then
				if rx >= 5 then unit.reaction = "FRIENDLY"
				elseif rx == 4 then
					-- a neutral mob fighting you or your group counts as hostile,
					-- just like its bar turns red in vanilla
					local holder = UnitExists(guid .. "target") and UnitName(guid .. "target")
					if UnitAffectingCombat(guid) and holder and Data.InGroup(holder) then
						RememberAngry(guid)
						unit.reaction = "HOSTILE"
					elseif IsAngryNeutral(guid) then
						unit.reaction = "HOSTILE"
					else
						unit.reaction = "NEUTRAL"
					end
				else unit.reaction = "HOSTILE" end
			end
		end
	end

	local function GatherData_GUID(plate)
		local guid = ResolveGUID(plate, regions.name:GetText())
		if guid ~= unit.guid then
			if unit.guid and GUID[unit.guid] == plate then GUID[unit.guid] = nil end
			unit.guid = guid
			if guid then GUID[guid] = plate end
			unit.partyID = nil
			if activetheme.OnContextUpdate then activetheme.OnContextUpdate(unit) end
		end
		return guid
	end

	local function GatherData_Target()
		if unit.guid and targetGUID then
			unit.isTarget = (unit.guid == targetGUID)
		elseif HasTarget and not C.HasSuperWoW then
			-- Without SuperWoW: best effort by name. With SuperWoW a plate whose
			-- GUID isn't confirmed yet is NOT the target: matching by name
			-- would make every same-named mob in a pack "the target" and copy
			-- the target's debuffs, combo points and threat onto all of them.
			unit.isTarget = (unit.name == targetName)
		else
			unit.isTarget = false
		end
		if unit.isTarget then currentTarget = nameplate
		elseif currentTarget == nameplate then currentTarget = nil end
	end

	local function GatherData_Static()
		unit.name = regions.name:GetText()
		unit.isBoss = regions.levelicon:IsShown() and true or false
		unit.isDangerous = unit.isBoss
	end

	local function GatherData_BasicInfo()
		local guid = unit.guid
		unit.name = regions.name:GetText()
		unit.isBoss = regions.levelicon:IsShown() and true or false
		if unit.isBoss then unit.level = "??"
		else unit.level = regions.level:GetText() end
		unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue = regions.level:GetTextColor()

		local health, low, high = bars.health:GetValue(), bars.health:GetMinMaxValues()
		unit.health = health or 0
		unit.healthmax = high or 1
		if guid then
			local maxhp = UnitHealthMax(guid)
			if maxhp and maxhp > unit.healthmax then
				unit.health, unit.healthmax = UnitHealth(guid), maxhp
			end
		end

		ReadReaction()
		unit.class = "UNKNOWN"
		unit.isElite = false
		if guid then
			if UnitIsPlayer(guid) then
				unit.type = "PLAYER"
				local _, class = UnitClass(guid)
				unit.class = class or "UNKNOWN"
				unit.partyID = Data.roster[unit.name]
			else
				unit.type = "NPC"
			end
			local classification = UnitClassification(guid)
			unit.isElite = (classification == "elite" or classification == "rareelite" or classification == "worldboss")
			unit.isInCombat = UnitAffectingCombat(guid) and true or false
			unit.isDead = UnitIsDead(guid) and true or false
		else
			unit.isInCombat = GetUnitCombatStatus(regions.name:GetTextColor())
		end
		unit.InCombatLockdown = inCombat
		unit.raidIcon = ReadRaidIcon()
		unit.isMarked = unit.raidIcon ~= nil
		unit.threatSituation = Data.GetThreatSituation(unit)

		-- Extras (GudaPlates-style): tapped, stunned, critter, class colors,
		-- who has aggro, power
		unit.isTapped, unit.isStunned, unit.isCritter, unit.isPvP = false, false, false, false
		unit.aggroHolder, unit.holderIsTank, unit.losingAggro = nil, false, false
		unit.power, unit.powermax, unit.powerType = nil, nil, nil
		if guid then
			unit.isTapped = (UnitIsTapped(guid) and not UnitIsTappedByPlayer(guid)) and true or false
			if unit.isTapped then
				-- tapped by someone in our group is fine
				local holder = UnitExists(guid .. "target") and UnitName(guid .. "target")
				if holder and Data.InGroup(holder) then unit.isTapped = false end
			end
			if Opt("stunColorOn") ~= false and unit.reaction ~= "FRIENDLY" then unit.isStunned = Data.IsStunned(guid) end
			unit.isCritter = CRITTER_TYPES[UnitCreatureType(guid) or ""] and true or false
			unit.isPvP = UnitIsPVP(guid) and true or false
			unit.power, unit.powermax = UnitMana(guid), UnitManaMax(guid)
			unit.powerType = UnitPowerType(guid)
		end
		if unit.reaction ~= "FRIENDLY" and unit.type == "NPC" and inCombat then
			unit.aggroHolder = Data.GetAggroHolder(unit)
			unit.holderIsTank = (unit.aggroHolder and unit.aggroHolder ~= UnitName("player")
				and Data.IsRaidTank(unit.aggroHolder)) and true or false
			unit.losingAggro = Data.IsLosingAggro(unit)
		end
		-- class colors for players (vanilla paints every enemy player red)
		if unit.type == "PLAYER" and CLASS_COLORS[unit.class] then
			local enemy = unit.reaction ~= "FRIENDLY"
			local want = (enemy and Opt("classColorEnemies") ~= false) or ((not enemy) and Opt("classColorFriends"))
			if enemy and unit.isPvP and Opt("noClassColorPvP") then want = false end
			if want then
				local c = CLASS_COLORS[unit.class]
				unit.red, unit.green, unit.blue = c[1], c[2], c[3]
			end
		end
	end

	local function GatherData_Cast()
		local cast = Data.GetCast(unit.guid)
		if cast then
			unit.isCasting = true
			unit.spellName = cast.spell
			unit.spellIcon = cast.icon
			unit.isChanneling = cast.channel
			unit.spellId = cast.spellId
			unit.notInterruptible = SHPlates.Interrupts.IsUninterruptible(unit.name, cast.spellId)
		else
			unit.isCasting = false
			unit.spellName = nil
			unit.spellIcon = nil
			unit.isChanneling = nil
			unit.spellId = nil
			unit.notInterruptible = nil
		end
	end

	---------------------------------------------------------------------------
	-- Graphical updates
	---------------------------------------------------------------------------
	local function UpdateStubbornRegions()
		HideBlizzardRegions()
	end

	local function CheckNameplateStyle()
		if activetheme.SetStyle then
			stylename = activetheme.SetStyle(unit); extended.style = activetheme[stylename]
		else extended.style = activetheme; stylename = tostring(activetheme) end
		style = extended.style
		if extended.stylename ~= stylename or forceStyleUpdate then
			UpdateStyle()
			extended.stylename = stylename
		end
	end

	local function RefreshCastbar()
		local castbar = bars.castbar
		local cast = Data.GetCast(unit.guid)
		if cast then
			local r, g, b, a
			if activetheme.SetCastbarColor then r, g, b, a = activetheme.SetCastbarColor(unit)
			else r, g, b, a = 1, .8, 0, 1 end
			castbar:SetStatusBarColor(r, g, b, a or 1)
			castbar.cast = cast
			castbar:SetMinMaxValues(cast.start, cast.finish)
			castbar:SetValue(GetTime())
			visual.spellicon:SetTexture(cast.icon)
			if unit.notInterruptible and style.options.showNostopSpell then
				visual.castnostop:Show(); visual.castborder:Hide()
			else visual.castnostop:Hide(); visual.castborder:Show() end
			castbar:Show()
		else
			castbar.cast = nil
			castbar:Hide()
		end
	end

	local function ProcessUnitChanges()
		for key, value in pairs(unit) do
			if unitcache[key] ~= value then unitchanged = true; break end
		end
		if unitchanged then
			CheckNameplateStyle()
			UpdateIndicator_All()
			UpdateIndicator_HealthBar()
		else
			-- transparency also depends on things outside the unit (whether you
			-- have a target, option changes): keep it current every refresh
			UpdateIndicator_CustomAlpha()
		end
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
		UpdateUnitCache()
	end

	---------------------------------------------------------------------------
	-- Setup
	---------------------------------------------------------------------------
	local function PrepareNameplate(plate)
		extended.healthTexHidden = nil
		HideBlizzardRegions()
		GatherData_GUID(plate)
		GatherData_Static()
		unit.alpha = 1
		unit.isTarget = false
		unit.isMouseover = false
		extended.unitcache = wipe(extended.unitcache)
		unitcache = extended.unitcache
		extended.stylename = ""
		unit.isCasting = false
		bars.castbar:Hide()
		visual.highlight:Hide()
		extended.mouseShown = nil
		if activetheme.OnInitialize then activetheme.OnInitialize(extended) end
		-- widgets made just now start fully visible: match the plate
		SetPartsAlpha(extended, extended:GetAlpha())
	end

	local function FullGather(plate)
		GatherData_BasicInfo()
		GatherData_Target()
		GatherData_Cast()
		ProcessUnitChanges()
		RefreshCastbar()
	end

	---------------------------------------------------------------------------
	-- Entry points
	---------------------------------------------------------------------------
	function OnHideNameplate(plate)
		UpdateReferences(plate)
		if unit.guid and GUID[unit.guid] == plate then GUID[unit.guid] = nil end
		visual.highlight:Hide()
		bars.castbar:Hide()
		bars.castbar.cast = nil
		PlatesVisible[plate] = nil
		wipe(extended.unit)
		wipe(extended.unitcache)
		if plate == currentTarget then currentTarget = nil end
		if plate == lastMouseover then lastMouseover = nil end
	end

	function OnEchoNewNameplate(plate)
		if not plate:IsShown() then return end
		UpdateReferences(plate)
		FullGather(plate)
	end

	function OnShowNameplate(plate)
		PlatesVisible[plate] = true
		UpdateReferences(plate)
		PrepareNameplate(plate)
		FullGather(plate)
		SetSelfEcho(plate, OnUpdateNameplate)
	end

	function OnNewNameplate(plate)
		local health = bars.health
		C.HookScript(plate, "OnShow", function() OnShowNameplate(plate) end)
		C.HookScript(plate, "OnHide", function() OnHideNameplate(plate) end)
		C.HookScript(health, "OnValueChanged", function() OnUpdateHealth(plate) end)
		if plate:IsShown() then
			OnShowNameplate(plate)
		end
	end

	function OnUpdateNameplate(plate)
		if not plate:IsShown() then return end
		UpdateReferences(plate)
		local oldguid = unit.guid
		local guid = ResolveGUID(plate, regions.name:GetText())
		if guid ~= oldguid then
			-- Vanilla can recycle a visible plate for another unit
			PrepareNameplate(plate)
		end
		UpdateStubbornRegions()
		FullGather(plate)
	end

	function OnUpdateLevel(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		if unit.isBoss then unit.level = "??"
		else unit.level = regions.level:GetText() end
		UpdateIndicator_Level()
	end

	function OnUpdateRaidIcon(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		unit.raidIcon = ReadRaidIcon()
		unit.isMarked = unit.raidIcon ~= nil
		UpdateIndicator_RaidIcon()
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
	end

	function OnUpdateReaction(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		ReadReaction()
		UpdateIndicator_UnitColor()
		UpdateIndicator_CustomScaleText()
	end

	function OnLeaveNameplate(plate)
		plate.extended.unit.isMouseover = false
		plate.extended.visual.highlight:Hide()
	end

	function OnMouseoverNameplate(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		unit.isMouseover = true
		visual.highlight:Show()
		visual.highlight:SetAlpha(extended:GetAlpha())
		UpdateIndicator_CustomScaleText()
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
	end

	function OnUpdateHealth(plate)
		if not IsPlateShown(plate) or not PlatesVisible[plate] then return end
		UpdateReferences(plate)
		local health, low, high = bars.health:GetValue(), bars.health:GetMinMaxValues()
		unit.health = health or 0
		unit.healthmax = high or 1
		if unit.guid then
			local maxhp = UnitHealthMax(unit.guid)
			if maxhp and maxhp > unit.healthmax then
				unit.health, unit.healthmax = UnitHealth(unit.guid), maxhp
			end
		end
		UpdateIndicator_HealthBar()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
	end

	function OnStartCast(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		GatherData_Cast()
		RefreshCastbar()
		UpdateIndicator_CustomScaleText()
		if activetheme.OnUpdate then activetheme.OnUpdate(extended, unit) end
	end

	function OnStopCast(plate)
		if not IsPlateShown(plate) then return end
		UpdateReferences(plate)
		unit.isCasting = false
		unit.spellName = nil
		bars.castbar.cast = nil
		bars.castbar:Hide()
		UpdateIndicator_CustomScaleText()
		SetSelfEcho(plate, OnUpdateNameplate)
	end

	function OnResetNameplate(plate)
		local ext = plate.extended
		ext.unitcache = wipe(ext.unitcache)
		ext.stylename = ""
		OnShowNameplate(plate)
	end
end

-- Cast notifications from Data.lua
function SHPlates.OnCastChanged(guid)
	local plate = GUID[guid]
	if not plate or not PlatesVisible[plate] then return end
	if Data.GetCast(guid) then OnStartCast(plate) else OnStopCast(plate) end
end

-- Aura notifications: just refresh that plate's widgets soon
function SHPlates.OnAuraChanged(guid)
	local plate = GUID[guid]
	if plate and PlatesVisible[plate] then
		plate.extended.auraDirty = true
		SetSelfEcho(plate, OnUpdateNameplate)
	end
end

-------------------------------------------------------------------------------
-- VI. Nameplate Extension
-------------------------------------------------------------------------------
local ApplyPlateExtension
do
	local function CastbarOnUpdate(castbar)
		local cast = castbar.cast
		if not cast then castbar:Hide(); return end
		local now = GetTime()
		if now >= cast.finish then
			castbar.cast = nil
			castbar:Hide()
			if castbar.plate then OnStopCast(castbar.plate) end
			return
		end
		if cast.channel then
			castbar:SetValue(cast.finish - (now - cast.start))
		else
			castbar:SetValue(now)
		end
	end

	function ApplyPlateExtension(plate)
		Plates[plate] = true
		plate.extended = CreateFrame("Frame", nil, plate)
		local ext = plate.extended
		ext:SetPoint("CENTER", plate, "CENTER", 0, 0)
		ext:SetFrameLevel(plate:GetFrameLevel() + 1)
		ext.style, ext.unit, ext.unitcache, ext.stylecache, ext.widgets = {}, {}, {}, {}, {}
		ext.regions, ext.bars, ext.visual = {}, {}, {}
		ext.stylename = ""
		ext.plate = plate

		local r = ext.regions
		local b = ext.bars
		local pf = plate.nameplate
		if pf and pf.original then
			-- pfUI already took this plate over (it re-parents the raid icon,
			-- so GetRegions no longer has all six): use its references
			if SHPlates.Conflicts then SHPlates.Conflicts.ReleasePlate(plate) end
			local o = pf.original
			b.health = o.healthbar or plate:GetChildren()
			r.border, r.glow, r.name, r.level, r.levelicon = o.border, o.glow, o.name, o.level, o.levelicon
			r.raidicon = pf.raidicon
		else
			b.health = plate:GetChildren()
			-- Vanilla region order
			r.border, r.glow, r.name, r.level, r.levelicon, r.raidicon = plate:GetRegions()
		end
		-- Never leave a hole if another addon moved a region away
		if not r.border then r.border = ext:CreateTexture(nil, "BACKGROUND") end
		if not r.glow then r.glow = ext:CreateTexture(nil, "BACKGROUND"); r.glow:Hide() end
		if not r.levelicon then r.levelicon = ext:CreateTexture(nil, "BACKGROUND"); r.levelicon:Hide() end
		if not r.raidicon then r.raidicon = ext:CreateTexture(nil, "BACKGROUND"); r.raidicon:Hide() end
		if not r.name then r.name = ext:CreateFontString(nil, "BACKGROUND") end
		if not r.level then r.level = ext:CreateFontString(nil, "BACKGROUND") end

		-- Statusbars
		local level = ext:GetFrameLevel()
		b.healthbar = CreateStatusbar(ext)
		b.castbar = CreateStatusbar(ext)
		b.healthbar:SetFrameLevel(level)
		b.castbar:SetFrameLevel(level)
		b.castbar:Hide()
		b.castbar:SetStatusBarColor(1, .8, 0)
		b.castbar.plate = plate
		b.castbar:SetScript("OnUpdate", function() CastbarOnUpdate(b.castbar) end)

		-- Visual regions
		local v = ext.visual
		v.specialArt = ext:CreateTexture(nil, "OVERLAY")
		v.specialText = b.healthbar:CreateFontString(nil, "OVERLAY")
		v.specialText2 = b.healthbar:CreateFontString(nil, "OVERLAY")
		v.healthborder = b.healthbar:CreateTexture(nil, "ARTWORK")
		v.threatborder = b.healthbar:CreateTexture(nil, "OVERLAY")
		v.highlight = b.healthbar:CreateTexture(nil, "OVERLAY")
		v.highlight:SetBlendMode("ADD")
		v.highlight:Hide()
		v.castborder = b.castbar:CreateTexture(nil, "ARTWORK")
		v.castnostop = b.castbar:CreateTexture(nil, "ARTWORK")
		v.spellicon = b.castbar:CreateTexture(nil, "OVERLAY")
		-- Icons live on their own frame above the bar, so the glowing aggro
		-- border (same draw layer on the bar) can't cover them
		local icons = CreateFrame("Frame", nil, b.healthbar)
		icons:SetAllPoints(ext)
		icons:SetFrameLevel(b.healthbar:GetFrameLevel() + 3)
		ext.iconFrame = icons
		v.dangerskull = icons:CreateTexture(nil, "OVERLAY")
		v.raidicon = icons:CreateTexture(nil, "OVERLAY")
		v.eliteicon = b.healthbar:CreateTexture(nil, "OVERLAY")
		v.name = ext:CreateFontString(nil, "ARTWORK")

		-- Click frame used in overlap mode
		local clicker = CreateFrame("Button", nil, ext)
		clicker:SetPoint("CENTER", plate, "CENTER", 0, 0)
		clicker:SetWidth(100); clicker:SetHeight(30)
		clicker:SetFrameLevel(level + 5)
		clicker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		clicker:EnableMouse(false)
		clicker:SetScript("OnClick", function() plate:Click() end)
		clicker:SetScript("OnEnter", function()
			ext.hover = true
			if SetMouseoverUnit and ext.unit.guid then pcall(SetMouseoverUnit, ext.unit.guid) end
		end)
		clicker:SetScript("OnLeave", function() ext.hover = nil end)
		ext.clicker = clicker
		v.level = ext:CreateFontString(nil, "OVERLAY")

		v.raidicon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		-- textures start out visible: keep these hidden until data says otherwise
		v.raidicon:Hide()
		-- Prefer Blizzard's raid icon, re-parented onto our bar (what pfUI and
		-- GudaPlates do): the client already knows the mark and keeps it current.
		local blizzIcon = r.raidicon
		if blizzIcon and blizzIcon.SetParent and blizzIcon.GetTexture and blizzIcon:GetTexture() ~= nil
			and pcall(blizzIcon.SetParent, blizzIcon, icons) then
			if blizzIcon.SetDrawLayer then blizzIcon:SetDrawLayer("OVERLAY") end
			if pf then blizzIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons") end
			blizzIcon:SetAlpha(1)
			v.raidiconOwn = v.raidicon
			v.raidiconOwn:SetAllPoints(blizzIcon)
			v.raidicon = blizzIcon
			ext.usesBlizzardRaidIcon = true
		end
		v.dangerskull:Hide()
		v.eliteicon:Hide()
		ext.blizzRegions = { plate:GetRegions() }
		if pf and pf.raidicon then table.insert(ext.blizzRegions, pf.raidicon) end
		v.dangerskull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

		UpdateReferences(plate)
		OnNewNameplate(plate)
	end
end

-------------------------------------------------------------------------------
-- VII. World Update
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Fast hide (mirrors GudaPlates): checked for every plate EVERY FRAME, before
-- anything else, straight from the client's own data, so friendly, neutral and
-- critter plates never get a chance to show.
--   critter  : SuperWoW creature type, else neutral + level 1 + under 100 HP
--   hostile  : never hidden here
--   neutral  : hidden (theme option) unless it's your target or in combat
--   friendly : hidden (General option) unless it's your target
-------------------------------------------------------------------------------
local CRITTERS = { ["Critter"] = true, ["Kleintier"] = true, ["Bestiole"] = true, ["Alimaña"] = true,
	["Animale"] = true, ["Bicho"] = true, ["Существо"] = true }

local function ShouldFastHide(p)
	local ext = p.extended
	local health = ext.bars.health
	local name = ext.regions.name:GetText()
	local guid = C.PlateGUID(p, name)
	if guid and UnitIsUnit(guid, "target") then return false end
	if not guid and UnitExists("target") and name == UnitName("target") then return false end
	-- players: attackable ones always show, everyone else is friendly
	if guid and UnitIsPlayer(guid) then
		if UnitCanAttack("player", guid) then return false end
		return Opt("hideFriendly") and true or false
	end

	local r, g, b = health:GetStatusBarColor()
	if not r then return false end
	local hostile = r > .9 and g < .2 and b < .2
	local neutral = r > .9 and g > .9 and b < .2

	-- critters
	if Opt("showCritters") == false then
		if guid then
			if CRITTERS[UnitCreatureType(guid) or ""] then return true end
		elseif neutral then
			local _, hpmax = health:GetMinMaxValues()
			if ext.regions.level:GetText() == "1" and hpmax and hpmax > 0 and hpmax < 100 then return true end
		end
	end
	if hostile then return false end

	if neutral then
		local vars = activetheme.vars
		if not (vars and vars.OpacityHideNeutral) then return false end
		if guid then return not (UnitAffectingCombat(guid) or IsAngryNeutral(guid)) end
		-- no SuperWoW: the aggro glow means it's fighting
		return not ext.regions.glow:IsShown()
	end

	-- friendly
	return Opt("hideFriendly") and true or false
end
SHPlates.ShouldFastHide = ShouldFastHide

local OnUpdate
do
	local BORDER = "Interface\\Tooltips\\Nameplate-Border"

	local function IsFrameNameplate(frame)
		if frame.extended then return false end
		-- a plate pfUI already processed (it blanks the border texture)
		if frame.nameplate and frame.nameplate.original and frame.nameplate.original.healthbar then return true end
		local objtype = frame:GetObjectType()
		if objtype ~= "Button" and objtype ~= "Frame" then return false end
		local region = frame:GetRegions()
		return region and region.GetObjectType and region:GetObjectType() == "Texture"
			and region:GetTexture() == BORDER
	end

	local function ScanWorldFrame()
		local children = { WorldFrame:GetChildren() }
		for index = 1, table.getn(children) do
			local frame = children[index]
			if not Plates[frame] and IsFrameNameplate(frame) then
				ApplyPlateExtension(frame)
			end
		end
	end

	function ForEachPlate(functionToRun)
		for plate in pairs(PlatesVisible) do
			if plate:IsShown() and plate.extended:IsShown() then
				functionToRun(plate)
			end
		end
	end

	local existMouseover, func, plate
	local rescanTimer = 0

	function OnUpdate()
		local elapsed = arg1 or 0
		existMouseover = false

		-- Mouseover changes (the Blizzard glow region is the source of truth)
		for p in pairs(PlatesVisible) do
			-- the client resets plate sizes, so enforce ours every frame
			-- (pfUI does the same): 1x1 for overlap, full size for stacking
			if overlapMode then
				if p:GetWidth() > 1 then p:SetWidth(1); p:SetHeight(1) end
			elseif p.extended.stackW and math.abs(p:GetWidth() - p.extended.stackW) > .5 then
				p:SetWidth(p.extended.stackW); p:SetHeight(p.extended.stackH)
			end
			local ext = p.extended
			local hide = ShouldFastHide(p)
			if hide then
				if not ext.fastHidden or ext:GetAlpha() > 0 then
					ext.fastHidden = true
					ext:SetAlpha(0)
					SetPartsAlpha(ext, 0)
					ApplyPlateMouse(p, false)
				end
			elseif ext.fastHidden then
				ext.fastHidden = nil
				SetSelfEcho(p, OnUpdateNameplate)   -- let the theme set its alpha again
			end
			if p.extended.hover or p.extended.regions.glow:IsShown() then
				existMouseover = true
				if lastMouseover ~= p then
					if lastMouseover then OnLeaveNameplate(lastMouseover) end
					lastMouseover = p
					OnMouseoverNameplate(p)
				end
			end
		end
		if not existMouseover and lastMouseover then
			OnLeaveNameplate(lastMouseover)
			lastMouseover = nil
		end

		-- Update queue
		if echoUpdateList[OnResetNameplate] then
			ForEachPlate(OnResetNameplate)
			wipe(echoUpdateList)
			wipe(echoSelf)
		else
			for f in pairs(echoUpdateList) do
				echoUpdateList[f] = nil
				ForEachPlate(f)
			end
			for p, f in pairs(echoSelf) do
				echoSelf[p] = nil
				if p:IsShown() then f(p) end
			end
		end

		-- Periodic refresh (replaces 3.3.5's threat events)
		pollTimer = pollTimer + elapsed
		if pollTimer >= POLL_INTERVAL then
			pollTimer = 0
			-- report errors in chat once (many 1.12 UIs hide Lua errors)
			local ok, err = pcall(ForEachPlate, OnUpdateNameplate)
			if not ok then
				SHPlates.lastError = err
				if not SHPlates.reportedErrors then SHPlates.reportedErrors = {} end
				if not SHPlates.reportedErrors[err] then
					SHPlates.reportedErrors[err] = true
					C.print("|cffff4040error:|r " .. tostring(err))
				end
			end
		end

		-- New plates
		rescanTimer = rescanTimer + elapsed
		local cur = WorldFrame:GetNumChildren()
		if cur ~= numChildren or rescanTimer > 1 then
			numChildren = cur
			rescanTimer = 0
			ScanWorldFrame()
		end
	end
end

-------------------------------------------------------------------------------
-- VIII. Event Handlers
-------------------------------------------------------------------------------
do
	local events = {}
	local PlateHandler = CreateFrame("Frame", "SHPlatesPlateHandler", WorldFrame)
	PlateHandler:SetFrameStrata("TOOLTIP")

	local function UpdateTarget()
		HasTarget = UnitExists("target") and true or false
		targetGUID = C.GUID("target")
		targetName = HasTarget and UnitName("target") or nil
		if not HasTarget then currentTarget = nil end
	end

	function events.PLAYER_ENTERING_WORLD()
		inCombat = InCombat()
		UpdateTarget()
		numChildren = -1
		PlateHandler:SetScript("OnUpdate", OnUpdate)
	end
	function events.PLAYER_REGEN_ENABLED()
		inCombat = false
		for guid in pairs(angryNeutrals) do
			if not (UnitExists(guid) and UnitAffectingCombat(guid)) then angryNeutrals[guid] = nil end
		end
		SetEchoUpdate(OnUpdateNameplate)
		if useAutoHide and HideNameplates then HideNameplates() end
	end
	function events.PLAYER_REGEN_DISABLED()
		inCombat = true
		SetEchoUpdate(OnUpdateNameplate)
		if useAutoHide and ShowNameplates then ShowNameplates() end
	end
	function events.PLAYER_TARGET_CHANGED()
		UpdateTarget()
		SetEchoUpdate(OnUpdateNameplate)
	end
	function events.RAID_TARGET_UPDATE() ForEachPlate(OnUpdateRaidIcon); SetEchoUpdate(OnUpdateNameplate) end
	function events.UNIT_LEVEL() ForEachPlate(OnUpdateLevel) end
	function events.PLAYER_CONTROL_LOST() ForEachPlate(OnUpdateReaction) end
	function events.PLAYER_CONTROL_GAINED() ForEachPlate(OnUpdateReaction) end
	function events.UNIT_FACTION() ForEachPlate(OnUpdateReaction) end
	function events.UNIT_AURA()
		if arg1 == "target" and currentTarget then
			currentTarget.extended.auraDirty = true
			SetSelfEcho(currentTarget, OnUpdateNameplate)
		end
	end

	PlateHandler:SetScript("OnEvent", function()
		if SHPlates.disabled then return end  -- GudaPlates is running (see Guard.lua)
		local handler = events[event]
		if handler then handler() end
	end)
	for eventname in pairs(events) do PlateHandler:RegisterEvent(eventname) end
end

-------------------------------------------------------------------------------
-- IX. External Commands
-------------------------------------------------------------------------------
function SHPlates:ForceUpdate() forceStyleUpdate = true; SetEchoUpdate(OnResetNameplate) end
function SHPlates:Update() SetEchoUpdate(OnUpdateNameplate) end
function SHPlates:UseAutoHide(option)
	useAutoHide = option
	if useAutoHide and (not InCombat()) and HideNameplates then HideNameplates() end
end
function SHPlates:ActivateTheme(theme)
	if theme and type(theme) == "table" then activetheme = theme end
end
function SHPlates:GetActiveTheme() return activetheme end
function SHPlates:GetPlateByGUID(guid) return GUID[guid] end
function SHPlates:SetOverlap(enabled)
	overlapMode = enabled and true or false
	for plate in pairs(Plates) do ApplyPlateMouse(plate, true) end
	SHPlates:ForceUpdate()
end

-- After a forced reset, styles are re-applied once
local resetFrame = CreateFrame("Frame")
resetFrame:SetScript("OnUpdate", function()
	if forceStyleUpdate and not echoUpdateList[OnResetNameplate] then forceStyleUpdate = false end
end)

SHPlates:ActivateTheme(SHPlates.defaultTheme)
