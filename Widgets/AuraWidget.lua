-------------------------------------------------------------------------------
-- SHPlates Widgets: Aura (debuff) widget
--
-- 1.12's UnitDebuff only returns texture, stacks and type. SHPlates adds:
--   * SuperWoW: debuffs for ANY plate (GUID unit token) + aura spell ID
--   * Nampower: duration and caster (AURA_CAST_* events) -> timers, "mine only"
-- Without SuperWoW, only the target's debuffs can be read.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local aurafont = SHPlates.MEDIA .. "LiberationSans-Regular.ttf"
local MAX_ICONS = 6
local SCAN_INTERVAL = .5

----------------------
-- Tooltip scanner, for debuff names when SpellInfo isn't available
----------------------
local scanner
local function ScanDebuffName(unitid, index)
	if not scanner then
		scanner = CreateFrame("GameTooltip", "SHPlatesScanTooltip", nil, "GameTooltipTemplate")
	end
	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanner:ClearLines()
	scanner:SetUnitDebuff(unitid, index)
	local line = getglobal("SHPlatesScanTooltipTextLeft1")
	local text = line and line:GetText()
	scanner:Hide()
	return text
end

----------------------
-- PolledHideIn(): updates the frame each second until it expires
----------------------
local PolledHideIn
do
	local Framelist = {}
	local Watcherframe = CreateFrame("Frame")
	local WatcherframeActive = false
	local timeToUpdate = 0

	local function CheckFramelist()
		local curTime = GetTime()
		if curTime < timeToUpdate then return end
		local framecount = 0
		timeToUpdate = curTime + 1
		for frame, expiration in pairs(Framelist) do
			if expiration < curTime then frame:Hide(); Framelist[frame] = nil
			else
				frame:Update(expiration)
				framecount = framecount + 1
			end
		end
		if framecount == 0 then Watcherframe:SetScript("OnUpdate", nil); WatcherframeActive = false end
	end

	function PolledHideIn(frame, expiration)
		if not expiration or expiration == 0 then
			-- unknown duration: show without a timer
			Framelist[frame] = nil
			frame.TimeLeft:SetText("")
			frame:Show()
		elseif expiration < 0 then
			frame:Hide()
			Framelist[frame] = nil
		else
			Framelist[frame] = expiration
			frame:Update(expiration)
			frame:Show()
			if not WatcherframeActive then
				Watcherframe:SetScript("OnUpdate", CheckFramelist)
				WatcherframeActive = true
			end
		end
	end
end

----------------------
-- Debuff frame
----------------------
do
	local function UpdateAuraFrame(frame, expiration)
		if frame.hideTimers then frame.TimeLeft:SetText(""); return end
		local timeleft = expiration - GetTime()
		local green, yellow, red = "|cFF84FF00", "|cFFFFB400", "|cFFFF0000"
		local textcolor
		if timeleft > 60 then frame.TimeLeft:SetText(green .. math.ceil(timeleft / 60) .. "m")
		else
			if timeleft < 3 then textcolor = red
			elseif timeleft < 5 then textcolor = yellow
			else textcolor = green end
			frame.TimeLeft:SetText(textcolor .. math.ceil(timeleft))
		end
	end

	local AuraBorderArt = SHPlates.ART .. "Aura\\AuraFrame"

	local function CreateAuraFrame(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(26); frame:SetHeight(14)
		frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
		frame.Icon:SetAllPoints(frame)
		frame.Icon:SetTexCoord(.07, 1 - .07, .23, 1 - .23)
		frame.Border = frame:CreateTexture(nil, "ARTWORK")
		frame.Border:SetWidth(32); frame.Border:SetHeight(32)
		frame.Border:SetPoint("CENTER", frame, "CENTER", 1, -2)
		frame.Border:SetTexture(AuraBorderArt)
		frame.TimeLeft = frame:CreateFontString(nil, "OVERLAY")
		frame.TimeLeft:SetFont(aurafont, 9, "OUTLINE")
		frame.TimeLeft:SetShadowOffset(1, -1)
		frame.TimeLeft:SetShadowColor(0, 0, 0, 1)
		frame.TimeLeft:SetPoint("RIGHT", frame, "RIGHT", 0, 8)
		frame.TimeLeft:SetWidth(26)
		frame.TimeLeft:SetHeight(16)
		frame.TimeLeft:SetJustifyH("RIGHT")
		frame.Stacks = frame:CreateFontString(nil, "OVERLAY")
		frame.Stacks:SetFont(aurafont, 10, "OUTLINE")
		frame.Stacks:SetShadowOffset(1, -1)
		frame.Stacks:SetShadowColor(0, 0, 0, 1)
		frame.Stacks:SetPoint("RIGHT", frame, "RIGHT", 0, -6)
		frame.Stacks:SetWidth(26)
		frame.Stacks:SetHeight(16)
		frame.Stacks:SetJustifyH("RIGHT")
		frame.PolledHideIn = PolledHideIn
		frame.Update = UpdateAuraFrame
		frame:Hide()
		return frame
	end

	local auraDurationFilter = 600
	local function DefaultFilterFunction(debuff)
		return (debuff.duration or 0) < auraDurationFilter
	end

	local aura = {}
	local PREVIEW_ICONS = { "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
		"Interface\\Icons\\Spell_Shadow_CurseOfSargeras", "Interface\\Icons\\Spell_Shadow_ShadowWordPain" }
	local list = {}   -- reused every scan

	local function HideAll(frame)
		for index = 1, MAX_ICONS do PolledHideIn(frame.AuraFrames[index], -1) end
	end

	local function UpdateAuraWidget(frame, unit)
		local AuraFrames = frame.AuraFrames
		-- debuff icon size (Size and Style tab)
		local size = SHPlates.TOpt("debuffScale") or 1
		if frame._size ~= size then frame._size = size; frame:SetScale(size) end
		-- timers tick outside the plate update, so each icon remembers the setting
		local hideTimers = SHPlates.TOpt("hideDebuffTimers") and true or false
		for i = 1, MAX_ICONS do AuraFrames[i].hideTimers = hideTimers end
		if unit.isPreview then
			-- the designer's sample plate: three made-up debuffs to place
			for i = 1, 3 do
				local f = AuraFrames[i]
				f.Icon:SetTexture(PREVIEW_ICONS[i])
				f.Stacks:SetText("")
				f:PolledHideIn(GetTime() + 20 * i)
			end
			for i = 4, MAX_ICONS do PolledHideIn(AuraFrames[i], -1) end
			return
		end
		local unitid = unit.guid
		-- without SuperWoW only the target / mouseover can be read; with it, a
		-- plate whose GUID isn't confirmed yet shows nothing rather than guess
		if not unitid and not C.HasSuperWoW then
			if unit.isTarget then unitid = "target"
			elseif unit.isMouseover then unitid = "mouseover" end
		end
		if not unitid then HideAll(frame); frame.lastGUID = nil; return end

		-- Throttle: rescan on unit change, on aura events, or every SCAN_INTERVAL
		local now = GetTime()
		local ext = frame.extended
		if frame.lastGUID == unitid and (now - (frame.lastScan or 0)) < SCAN_INTERVAL
			and not (ext and ext.auraDirty) then return end
		frame.lastGUID = unitid
		frame.lastScan = now
		if ext then ext.auraDirty = nil end

		-- Gather every debuff that passes the filter, then show yours first:
		-- with 6 slots, other players' debuffs could push yours off the plate.
		-- Order: yours, then unknown caster, then other people's. Within each
		-- group the game's own order is kept, so icons don't jump around.
		local found = 0
		for index = 1, 16 do
			local icon, count, dispelType, spellId = UnitDebuff(unitid, index)
			if not icon then break end
			local name
			if spellId and SpellInfo then name = SpellInfo(spellId)
			else name = ScanDebuffName(unitid, index) end
			local expires, duration, caster
			if unit.guid then expires, duration, caster = Data.GetAuraTimer(unit.guid, spellId, name) end

			aura.name, aura.icon, aura.count, aura.dispelType = name, icon, count or 0, dispelType
			aura.spellId, aura.duration, aura.expires, aura.caster = spellId, duration or 0, expires, caster
			if caster then aura.isMine = Data.IsMine(caster)
			elseif C.HasNampower then aura.isMine = false
			else aura.isMine = nil end

			if frame.Filter(aura) then
				found = found + 1
				local entry = list[found]
				if not entry then entry = {}; list[found] = entry end
				entry.icon, entry.count, entry.expires, entry.index = icon, count or 0, expires, index
				if aura.isMine then entry.rank = 1 elseif aura.isMine == nil then entry.rank = 2 else entry.rank = 3 end
			end
		end
		for i = found + 1, table.getn(list) do list[i].rank = nil end
		-- stable sort (insertion): small list, no table.sort surprises
		for i = 2, found do
			local e = list[i]
			local j = i - 1
			while j >= 1 and (list[j].rank > e.rank or (list[j].rank == e.rank and list[j].index > e.index)) do
				list[j + 1] = list[j]; j = j - 1
			end
			list[j + 1] = e
		end
		local auraCount = 0
		for i = 1, found do
			if auraCount >= MAX_ICONS then break end
			local e = list[i]
			auraCount = auraCount + 1
			local AuraFrame = AuraFrames[auraCount]
			AuraFrame.Icon:SetTexture(e.icon)
			if e.count > 1 then AuraFrame.Stacks:SetText(e.count)
			else AuraFrame.Stacks:SetText("") end
			AuraFrame:PolledHideIn(e.expires or 0)
		end
		for index = auraCount + 1, MAX_ICONS do PolledHideIn(AuraFrames[index], -1) end
	end

	function SHPlatesWidgets.CreateAuraWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(128); frame:SetHeight(32); frame:Show()
		frame.extended = parent
		frame.AuraFrames = {}
		local AuraFrames = frame.AuraFrames
		frame.Update = UpdateAuraWidget
		for index = 1, MAX_ICONS do AuraFrames[index] = CreateAuraFrame(frame) end
		-- first row
		AuraFrames[1]:SetPoint("LEFT", frame, "LEFT", 0, 0)
		for index = 2, 3 do AuraFrames[index]:SetPoint("LEFT", AuraFrames[index - 1], "RIGHT", 5, 0) end
		-- second row
		AuraFrames[4]:SetPoint("BOTTOMLEFT", AuraFrames[1], "TOPLEFT", 0, 8)
		for index = 5, 6 do AuraFrames[index]:SetPoint("LEFT", AuraFrames[index - 1], "RIGHT", 5, 0) end
		-- If the plate gets hidden, reset so icons don't leak onto another unit
		frame:SetScript("OnHide", function() HideAll(frame); frame.lastGUID = nil end)
		frame.Filter = DefaultFilterFunction
		return frame
	end
end
