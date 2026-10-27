-------------------------------------------------------------------------------
-- SHPlates Widgets: Threat Wheel, Tug-o'-Threat line, Tanked icon
-- Numbers come from Turtle's server threat (TWThreat packets) when the plate
-- is your target; everything else is estimated from who the mob is attacking.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Data = SHPlates.Data
local ART = SHPlates.ART
local threatfont = "Fonts\\ARIALN.TTF"

-- size of the aggro holder's name (each template sets its own)
local function HolderFont(text, flags)
	local size = SHPlates.TOpt("holderFontSize") or 8
	if text._size ~= size then text._size = size; text:SetFont(threatfont, size, flags) end
end

local function GetRelativeThreat(unit) return Data.GetRelativeThreat(unit) end
local IsRaidTank = Data.IsRaidTank

local function IsPlayerTank() return SHPlates.GetRole and SHPlates.GetRole() == "Tank" end
local function IsPlayerInRaid() return UnitInRaid("player") and true or false end
local function InGroupOrPet()
	return (GetNumPartyMembers() > 0) or UnitInRaid("player") or UnitExists("pet")
end

local function GetThreatSegment(threat)
	if not threat then return nil end
	if threat > 133 then return "HIGHTANK"
	elseif threat > 116 then return "MEDIUMTANK"
	elseif threat > 100 then return "LOWTANK"
	elseif threat > 83 then return "HIGHDPS"
	elseif threat > 66 then return "MEDIUMDPS"
	else return "LOWDPS" end
end

---------------
-- Threat Wheel
---------------
do
	local art = ART .. "ThreatSpinner\\SpinnerArt"
	local SEGMENT = {
		HIGHTANK = { .75, 1, .5, 1 },
		MEDIUMTANK = { .5, .75, .5, 1 },
		LOWTANK = { .25, .5, .5, 1 },
		HIGHDPS = { 0, .25, .5, 1 },
		MEDIUMDPS = { .75, 1, 0, .5 },
		LOWDPS = { .5, .75, 0, .5 },
		UNKNOWN = { .25, .5, 0, .5 },
	}

	local function UpdateThreatWheelWidget(frame, unit)
		if not unit.isPreview and (unit.reaction == "FRIENDLY" or (not C.InCombat())) then frame:Hide(); return end
		if unit.isTarget or unit.isMouseover then
			local threat, holder, estimated = GetRelativeThreat(unit)
			-- the Designer's sample plate: you hold aggro
			if unit.isPreview then threat, holder, estimated = 75, UnitName("player"), false end
			HolderFont(frame.TargetText, "")
			local segment = GetThreatSegment(threat)
			if segment then
				frame.ThreatIcon:SetTexCoord(unpack(SEGMENT[segment]))
				if estimated then frame.ThreatText:SetText("")
				else frame.ThreatText:SetText(math.floor(threat)) end
				if holder then frame.TargetText:SetText(holder) else frame.TargetText:SetText("") end
				frame:Show()
				frame.FadeTime = GetTime() + 3
				frame:HideIn(frame.FadeTime)
			else frame:Hide() end
		elseif (GetTime() > frame.FadeTime) then frame:Hide() end
	end

	function SHPlatesWidgets.CreateThreatWheelWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(64)
		frame:SetHeight(64)
		frame.ThreatIcon = frame:CreateTexture(nil, "OVERLAY")
		frame.ThreatIcon:SetAllPoints(frame)
		frame.ThreatIcon:SetTexture(art)
		frame.ThreatText = frame:CreateFontString(nil, "OVERLAY")
		frame.ThreatText:SetFont(threatfont, 8, "")
		frame.ThreatText:SetPoint("CENTER", frame.ThreatIcon, "CENTER", -1, 0)
		frame.ThreatText:SetWidth(20)
		frame.ThreatText:SetHeight(20)
		frame.TargetText = frame:CreateFontString(nil, "OVERLAY")
		frame.TargetText:SetFont(threatfont, 8, "")
		frame.TargetText:SetShadowOffset(1, -1)
		frame.TargetText:SetShadowColor(0, 0, 0, 1)
		frame.TargetText:SetPoint("BOTTOM", frame, "TOP", 1, -25)
		frame.TargetText:SetWidth(50)
		frame.TargetText:SetHeight(20)
		frame.HideIn = SHPlatesWidgets.HideIn
		frame.FadeTime = 0
		frame:Hide()
		frame.Update = UpdateThreatWheelWidget
		return frame
	end
end

---------------
-- Tug-o'-Threat (Threat Line)
---------------
do
	local TEX = {
		None = { .75, 1, 0, 1 },
		Line = { 0, .25, 0, 1 },
		Right = { .5, .75, 0, 1 },
		Left = { .25, .5, 0, 1 },
	}
	local art = ART .. "ThreatLine\\ThreatLineUnified"

	local function UpdateThreatLineWidget(frame, unit)
		if not unit.isPreview and (unit.reaction == "FRIENDLY" or (not C.InCombat()) or (not InGroupOrPet())) then frame:Hide(); return end

		if unit.isTarget or unit.isMouseover then
			local threat, holder = GetRelativeThreat(unit)
			-- the Designer's sample plate: you hold aggro
			if unit.isPreview then threat, holder = 75, UnitName("player") end
			HolderFont(frame.TargetText, "OUTLINE")
			if not threat or threat <= 0 then frame:Hide(); return end
			local middledot, outerdot = "Left", "Right"
			local lineAnchor, dotAnchor, lineWidth = "RIGHT", "LEFT", 0
			local threatcolor
			if threat > 100 then
				lineWidth = math.ceil((threat - 100) / 2)
				lineAnchor, dotAnchor = "LEFT", "RIGHT"
				threatcolor = frame._HighColor
				frame.TargetText:SetText("")
			else
				lineWidth = math.ceil((100 - threat) / 2)
				threatcolor = frame._LowColor
				middledot, outerdot = "Right", "Left"
			end
			if holder then
				if (IsPlayerTank() or (not IsPlayerInRaid()) or unit.isPreview) and frame._ShowTargetOf then
					frame.TargetText:SetText(holder)
				else frame.TargetText:SetText("") end
				if IsRaidTank(holder) then
					threatcolor = frame._TankedColor
					frame.TargetText:SetTextColor(0, .9, .1, 1)
				else frame.TargetText:SetTextColor(1, 1, 1, 1) end
			else frame.TargetText:SetText("") end
			if lineWidth < 1 then lineWidth = 1 end
			if unit.isPreview then
				-- the Designer's sample: the whole line, low side left, high side
				-- right in yellow, so it can be lined up with the bar
				local low, high = frame._LowColor, { r = 1, g = .85, b = 0 }
				frame.Line:ClearAllPoints()
				frame.Line:SetPoint("RIGHT", frame.Middle, "CENTER", 0, 0)
				frame.Line:SetWidth(50)
				frame.Line:SetVertexColor(low.r, low.g, low.b)
				frame.Dot:ClearAllPoints()
				frame.Dot:SetPoint("CENTER", frame.Line, "LEFT", 0, 0)
				frame.Dot:SetTexCoord(unpack(TEX.Left))
				frame.Dot:SetVertexColor(low.r, low.g, low.b)
				frame.Line2:ClearAllPoints()
				frame.Line2:SetPoint("LEFT", frame.Middle, "CENTER", 0, 0)
				frame.Line2:SetWidth(50)
				frame.Line2:SetVertexColor(high.r, high.g, high.b)
				frame.Line2:Show()
				frame.Dot2:ClearAllPoints()
				frame.Dot2:SetPoint("CENTER", frame.Line2, "RIGHT", 0, 0)
				frame.Dot2:SetTexCoord(unpack(TEX.Right))
				frame.Dot2:SetVertexColor(high.r, high.g, high.b)
				frame.Dot2:Show()
				frame.Middle:SetTexCoord(unpack(TEX.Right))
				frame.Middle:SetVertexColor(low.r, low.g, low.b)
				frame:Show()
				frame.FadeTime = GetTime() + 2
				frame:HideIn(frame.FadeTime)
				return
			end
			frame.Line2:Hide(); frame.Dot2:Hide()
			frame.Line:ClearAllPoints()
			frame.Line:SetPoint(lineAnchor, frame.Middle, "CENTER", 0, 0)
			frame.Line:SetWidth(lineWidth)
			frame.Dot:ClearAllPoints()
			frame.Dot:SetPoint("CENTER", frame.Line, dotAnchor, 0, 0)
			frame.Dot:SetVertexColor(threatcolor.r, threatcolor.g, threatcolor.b)
			frame.Line:SetVertexColor(threatcolor.r, threatcolor.g, threatcolor.b)
			frame.Middle:SetVertexColor(threatcolor.r, threatcolor.g, threatcolor.b)
			frame.Middle:SetTexCoord(unpack(TEX[middledot]))
			frame.Dot:SetTexCoord(unpack(TEX[outerdot]))
			frame:Show()
			frame.FadeTime = GetTime() + 2
			frame:HideIn(frame.FadeTime)
		elseif (GetTime() > frame.FadeTime) then frame:Hide() end
	end

	local function SetThreatLineWidgetTexture(self, texture)
		if texture then
			self.Middle:SetTexture(texture)
			self.Dot:SetTexture(texture)
			self.Line:SetTexture(texture)
		end
	end

	function SHPlatesWidgets.CreateThreatLineWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(100)
		frame:SetHeight(24)
		frame.Middle = frame:CreateTexture(nil, "OVERLAY")
		frame.Middle:SetTexture(art)
		frame.Middle:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Middle:SetWidth(32)
		frame.Middle:SetHeight(32)
		frame.Dot = frame:CreateTexture(nil, "OVERLAY")
		frame.Dot:SetTexture(art)
		frame.Dot:SetWidth(32)
		frame.Dot:SetHeight(32)
		frame.Line = frame:CreateTexture(nil, "OVERLAY")
		frame.Line:SetTexture(art)
		frame.Line:SetTexCoord(unpack(TEX["Line"]))
		frame.Line:SetWidth(32)
		frame.Line:SetHeight(32)
		-- second half of the line, only used by the Designer's sample to show
		-- the whole line at once (both sides) so it can be centered
		frame.Line2 = frame:CreateTexture(nil, "OVERLAY")
		frame.Line2:SetTexture(art)
		frame.Line2:SetTexCoord(unpack(TEX["Line"]))
		frame.Line2:SetHeight(32)
		frame.Line2:Hide()
		frame.Dot2 = frame:CreateTexture(nil, "OVERLAY")
		frame.Dot2:SetTexture(art)
		frame.Dot2:SetWidth(32)
		frame.Dot2:SetHeight(32)
		frame.Dot2:Hide()
		frame.TargetText = frame:CreateFontString(nil, "OVERLAY")
		frame.TargetText:SetFont(threatfont, 8, "OUTLINE")
		-- fixed above the left part of the line (Tidy Plates tied it to the moving
		-- dot, which made the name slide around as threat changed)
		frame.TargetText:SetPoint("BOTTOM", frame, "CENTER", -24, -1)
		frame.TargetText:SetShadowOffset(1, -1)
		frame.TargetText:SetShadowColor(0, 0, 0, 1)
		frame.TargetText:SetWidth(50)
		frame.TargetText:SetHeight(20)
		frame.HideIn = SHPlatesWidgets.HideIn
		frame.FadeTime = 0
		frame:Hide()
		frame.Update = UpdateThreatLineWidget
		frame.SetWidgetTexture = SetThreatLineWidgetTexture
		-- Themes can move the "who has aggro" name, e.g. under the plate
		frame.SetTargetTextPoint = function(self, point, relative, relPoint, x, y)
			self._textPoint = { point, relative, relPoint, x or 0, y or 0 }
			self._lift = nil
			self:SetTextLift(0)
			self.TargetText:SetWidth(120)
			self.TargetText:SetHeight(12)
		end
		-- Moves the "who has aggro" name up by 'lift' pixels (the combo point
		-- bar uses the space it normally sits in). Only re-anchors on change.
		frame._textPoint = { "BOTTOM", frame, "CENTER", -24, -1 }
		-- Moves the whole widget (line + name) up by 'lift' pixels from where
		-- the theme placed it with SetBasePoint. Used to clear the combo bar.
		frame.SetBasePoint = function(self, point, relative, relPoint, x, y)
			self._basePoint = { point, relative, relPoint, x or 0, y or 0 }
			self._frameLift = nil
			self:SetLift(0)
		end
		frame.SetLift = function(self, lift)
			lift = lift or 0
			local p = self._basePoint
			if not p or self._frameLift == lift then return end
			self._frameLift = lift
			self:ClearAllPoints()
			-- plus the Designer offset (SetDesignOffset)
			self:SetPoint(p[1], p[2], p[3], p[4] + (self._dx or 0), p[5] + lift + (self._dy or 0))
		end
		frame.SetDesignOffset = function(self, x, y)
			if self._dx == x and self._dy == y then return end
			self._dx, self._dy = x, y
			local lift = self._frameLift or 0
			self._frameLift = nil
			self:SetLift(lift)
			-- the name is its own piece: keep it where it was
			self._lift = nil
			self:SetTextLift(self._textLift or 0)
		end
		-- Designer offset for the aggro holder's name, separate from the line
		frame.SetTextDesignOffset = function(self, x, y)
			if self._tdx == x and self._tdy == y then return end
			self._tdx, self._tdy = x, y
			self._lift = nil
			self:SetTextLift(self._textLift or 0)
		end
		frame.SetTextLift = function(self, lift)
			lift = lift or 0
			self._textLift = lift
			if self._lift == lift then return end
			self._lift = lift
			local p = self._textPoint
			-- Designer offsets: the name's own, minus the line's when the name
			-- hangs off the line, so moving the line doesn't drag the name along
			local x, y = self._tdx or 0, self._tdy or 0
			if p[2] == self then x, y = x - (self._dx or 0), y - (self._dy or 0) end
			self.TargetText:ClearAllPoints()
			self.TargetText:SetPoint(p[1], p[2], p[3], p[4] + x, p[5] + lift + y)
		end
		frame._LowColor = { r = .14, g = .75, b = 1 }
		frame._TankedColor = { r = 0, g = .9, b = .1 }
		frame._HighColor = { r = 1, g = .67, b = .14 }
		frame._ShowTargetOf = true
		return frame
	end
end

---------------
-- Tanked Widget (shield = a tank has it, knife = a squishy has it)
---------------
do
	local artpath = ART .. "MainTanked\\"

	local function UpdateTankedWidget(frame, unit)
		if not unit.isPreview and (unit.reaction == "FRIENDLY" or (not C.InCombat())) then frame:Hide(); return end
		if unit.isTarget or unit.isMouseover then
			local holder = Data.GetAggroHolder(unit)
			if unit.isPreview then holder = UnitName("player") end
			if holder then
				frame.FadeTime = GetTime() + 2
				frame:HideIn(frame.FadeTime)
				frame:Show()
				if IsRaidTank(holder) or (unit.threatSituation == "HIGH" and IsPlayerTank()) then
					frame.tank:Show(); frame.squishy:Hide()
				else frame.tank:Hide(); frame.squishy:Show() end
			else frame:Hide() end
		elseif (GetTime() > frame.FadeTime) then frame:Hide() end
	end

	function SHPlatesWidgets.CreateTankedWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame.FadeTime = 0
		frame:SetWidth(26)
		frame:SetHeight(26)
		frame.tank = frame:CreateTexture(nil, "OVERLAY")
		frame.tank:SetTexture(artpath .. "Shield")
		frame.tank:SetAllPoints(frame)
		frame.tank:Hide()
		frame.squishy = frame:CreateTexture(nil, "OVERLAY")
		frame.squishy:SetTexture(artpath .. "Knife")
		frame.squishy:SetAllPoints(frame)
		frame.squishy:Hide()
		frame.HideIn = SHPlatesWidgets.HideIn
		frame.Update = UpdateTankedWidget
		frame:Hide()
		return frame
	end
end
