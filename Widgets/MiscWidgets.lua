-------------------------------------------------------------------------------
-- SHPlates Widgets: Range, Mob Notes, Cast text, Boss Debuff (prototype)
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local ART = SHPlates.ART

---------------
-- Range Widget: marks friendly group members within X yards
---------------
do
	local Ranges, RangesCache = {}, {}
	local RangeWatcher = CreateFrame("Frame")
	local nextCheck = 0
	local updateFreq = .5
	local usingRangeWidget = false

	local function CheckRanges()
		local now = GetTime()
		if now < nextCheck then return end
		nextCheck = now + updateFreq
		C.wipe(Ranges)
		for name, unitid in pairs(Data.roster) do
			Ranges[name] = Data.GetRange(unitid)
		end
		local changed = false
		for name, range in pairs(Ranges) do
			if range ~= RangesCache[name] then RangesCache[name] = range; changed = true end
		end
		for name in pairs(RangesCache) do
			if Ranges[name] == nil then RangesCache[name] = nil; changed = true end
		end
		if changed then SHPlates:Update() end
	end

	local function ActivateRangeWidget()
		if not usingRangeWidget then return end
		Data.UpdateRoster()
		if UnitInRaid("player") or GetNumPartyMembers() > 0 then
			RangeWatcher:SetScript("OnUpdate", CheckRanges)
		else RangeWatcher:SetScript("OnUpdate", nil) end
	end

	RangeWatcher:SetScript("OnEvent", ActivateRangeWidget)
	RangeWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	RangeWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
	RangeWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")

	local art = ART .. "RangeWidget\\RangeWidget"

	local function UpdateRangeWidget(self, unit, range)
		local saferange = range or self.Range
		if unit.reaction == "FRIENDLY" then
			local unitrange = RangesCache[unit.name] or 100
			if unitrange <= saferange then
				self.Texture:Show()
				self.Texture:SetVertexColor(1, .25, 0, .50)
			else self.Texture:Hide() end
			self:Show()
		else self:Hide() end
	end

	function SHPlatesWidgets.CreateRangeWidget(parent)
		if not usingRangeWidget then usingRangeWidget = true; ActivateRangeWidget() end
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(16); frame:SetHeight(16)
		frame.Texture = frame:CreateTexture(nil, "OVERLAY")
		frame.Texture:SetTexture(art)
		frame.Texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Texture:SetWidth(128)
		frame.Texture:SetHeight(128)
		frame.Range = 15
		frame:Hide()
		frame.Update = UpdateRangeWidget
		return frame
	end
end

---------------
-- Note Widget: a note above specific mobs, by name
-- Notes are edited in the options window (one "Mob Name = note" per line).
---------------
do
	local notefont = "Fonts\\ARIALN.TTF"
	local art = ART .. "NoteWidget\\NoteBackground"

	-- Built-in examples are empty on purpose; user notes live in SHPlatesDB.notes
	SHPlatesNoteWidgetNames = SHPlatesNoteWidgetNames or {}

	local function GetNote(name)
		if not name then return nil end
		if SHPlatesDB and SHPlatesDB.notes and SHPlatesDB.notes[name] then return SHPlatesDB.notes[name] end
		return SHPlatesNoteWidgetNames[name]
	end

	local function UpdateNoteWidget(self, unit)
		local text = unit.previewNote or GetNote(unit.name)
		if text then
			self.Text:SetText("|cFFFFC600" .. text)
			self:Show()
		else self:Hide() end
	end

	function SHPlatesWidgets.CreateNoteWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(16); frame:SetHeight(16)
		frame.Texture = frame:CreateTexture(nil, "OVERLAY")
		frame.Texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Texture:SetWidth(256)
		frame.Texture:SetHeight(64)
		frame.Texture:SetTexture(art)
		frame.Text = frame:CreateFontString(nil, "OVERLAY")
		frame.Text:SetFont(notefont, 14, "")
		frame.Text:SetPoint("CENTER", frame, "CENTER", 0, 7)
		frame.Text:SetShadowOffset(1, -1)
		frame.Text:SetShadowColor(0, 0, 0, 1)
		frame.Text:SetWidth(260)
		frame.Text:SetHeight(40)
		frame:Hide()
		frame.Update = UpdateNoteWidget
		return frame
	end
end

---------------
-- Cast Widget: spell name text for any casting plate
---------------
do
	local castfont = "Fonts\\ARIALN.TTF"
	local function UpdateCastWidget(self, unit)
		if unit.isCasting and unit.spellName then
			self.Text:SetText(unit.spellName)
			self:Show()
		else self:Hide() end
	end

	function SHPlatesWidgets.CreateCastWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(16); frame:SetHeight(16)
		frame.Text = frame:CreateFontString(nil, "OVERLAY")
		frame.Text:SetFont(castfont, 12, "OUTLINE")
		frame.Text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Text:SetWidth(200)
		frame.Text:SetHeight(20)
		frame:Hide()
		frame.Update = UpdateCastWidget
		return frame
	end
	SHPlatesWidgets.UpdateCastWidget = UpdateCastWidget
end

---------------
-- Boss Debuff Widget (prototype in Tidy Plates; kept for theme authors)
-- Shows the given art while the unit has a debuff named in frame.Watch
---------------
do
	local art = {
		FIRE = ART .. "BossDebuffWidget\\Fire",
		ICE = ART .. "BossDebuffWidget\\Ice",
		GREEN = ART .. "BossDebuffWidget\\Green",
		BOMB = ART .. "BossDebuffWidget\\Bomb",
		SKULLS = ART .. "BossDebuffWidget\\Skulls",
	}

	local function UpdateBossDebuffWidget(self, unit)
		local token = unit.guid or (unit.isTarget and "target")
		if not token or not SpellInfo then self:Hide(); return end
		for index = 1, 16 do
			local icon, _, _, spellId = UnitDebuff(token, index)
			if not icon then break end
			local name = spellId and SpellInfo(spellId)
			local which = name and self.Watch[name]
			if which and art[which] then
				self.Texture:SetTexture(art[which])
				self:Show()
				return
			end
		end
		self:Hide()
	end

	function SHPlatesWidgets.CreateBossDebuffWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(16); frame:SetHeight(16)
		frame.Texture = frame:CreateTexture(nil, "OVERLAY")
		frame.Texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Texture:SetWidth(150)
		frame.Texture:SetHeight(150)
		frame.Watch = {}  -- e.g. frame.Watch["Living Bomb"] = "BOMB"
		frame:Hide()
		frame.Update = UpdateBossDebuffWidget
		return frame
	end
end

---------------
-- Power Bar: mana / rage / energy under the health bar (SuperWoW needed for
-- units other than your target)
---------------
do
	local POWER_COLORS = {
		[0] = { 0, .55, 1 },     -- mana
		[1] = { 1, 0, 0 },       -- rage
		[2] = { 1, .5, .25 },    -- focus
		[3] = { 1, 1, 0 },       -- energy
	}
	local MODE_OFF, MODE_ENEMIES, MODE_FRIENDS, MODE_BOTH = 1, 2, 3, 4

	local function UpdatePowerBar(self, unit, mode, manaOnly)
		mode = mode or MODE_OFF
		local max = unit.powermax
		local friendly = unit.reaction == "FRIENDLY"
		local wanted = (mode == MODE_BOTH) or (mode == MODE_ENEMIES and not friendly) or (mode == MODE_FRIENDS and friendly)
		if not wanted or not max or max <= 0 or (manaOnly and unit.powerType ~= 0) then self:Hide(); return end
		local c = POWER_COLORS[unit.powerType or 0] or POWER_COLORS[0]
		self.bar:SetStatusBarColor(c[1], c[2], c[3])
		self.bar:SetMinMaxValues(0, max)
		self.bar:SetValue(unit.power or 0)
		self:Show()
	end

	function SHPlatesWidgets.CreatePowerBar(parent, width, height)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(width or 100); frame:SetHeight(height or 3)
		frame.bg = frame:CreateTexture(nil, "BACKGROUND")
		frame.bg:SetAllPoints(frame)
		frame.bg:SetTexture(0, 0, 0, .6)
		frame.bar = SHPlates.CreateStatusbar(frame)
		frame.bar:SetAllPoints(frame)
		frame.bar:SetWidth(width or 100); frame.bar:SetHeight(height or 3)
		frame.bar:SetStatusBarTexture(SHPlates.MEDIA .. "Statusbar")
		frame.bar:SetOrientation("HORIZONTAL")
		frame:Hide()
		frame.Update = UpdatePowerBar
		return frame
	end
	SHPlatesWidgets.PowerModes = { "Off", "Enemies", "Friends", "Everyone" }
end
