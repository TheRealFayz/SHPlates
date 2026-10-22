-------------------------------------------------------------------------------
-- SHPlates Widgets: core helpers, class icon, selection box, combo points
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local ART = SHPlates.ART

----------------------
-- HideIn(): hides the frame once 'expiration' (GetTime) has passed
----------------------
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
			else framecount = framecount + 1 end
		end
		if framecount == 0 then Watcherframe:SetScript("OnUpdate", nil); WatcherframeActive = false end
	end

	function SHPlatesWidgets.HideIn(frame, expiration)
		Framelist[frame] = expiration
		if not WatcherframeActive then
			Watcherframe:SetScript("OnUpdate", CheckFramelist)
			WatcherframeActive = true
		end
	end
end

----------------------
-- Multi-purpose mouseover frame
----------------------
do
	local function UpdateMouseoverWidget(frame, unit)
		if unit.reaction == "FRIENDLY" or (not C.InCombat()) then frame:Hide(); return end
		if unit.isTarget or unit.isMouseover then
			frame.FadeTime = GetTime() + 2
			frame:HideIn(frame.FadeTime)
			frame:Show()
		elseif (GetTime() > frame.FadeTime) then frame:Hide() end
	end

	function SHPlatesWidgets.CreateMouseoverWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame.FadeTime = 0
		frame.HideIn = SHPlatesWidgets.HideIn
		frame.Update = UpdateMouseoverWidget
		frame:Hide()
		return frame
	end
end

----------------------
-- ResetWidgets(): removes widgets from every plate (on theme changes)
----------------------
function SHPlatesWidgets.ResetWidgets()
	for plate in pairs(SHPlates.AllNameplates) do
		local ext = plate.extended
		if ext and ext.widgets then
			for index, widget in pairs(ext.widgets) do
				if widget.Hide then widget:Hide() end
				ext.widgets[index] = nil
			end
		end
	end
end

---------------
-- Class Widget
---------------
do
	local path = ART .. "ClassWidget\\"
	local function UpdateClassWidget(self, unit)
		if unit.class and unit.class ~= "UNKNOWN" then
			self.Icon:SetTexture(path .. unit.class)
			self:Show()
		else self:Hide() end
	end

	function SHPlatesWidgets.CreateClassWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(16); frame:SetHeight(16)
		frame.Icon = frame:CreateTexture(nil, "OVERLAY")
		frame.Icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.Icon:SetWidth(24)
		frame.Icon:SetHeight(24)
		frame:Hide()
		frame.Update = UpdateClassWidget
		return frame
	end
end

---------------
-- Selection Widget
---------------
do
	local function UpdateSelectionWidget(self, unit)
		if unit.isTarget then self:Show() else self:Hide() end
	end
	local function SetSelectionWidgetTexture(self, texture)
		if texture then self.Texture:SetTexture(texture) end
	end
	function SHPlatesWidgets.CreateSelectionWidget(parent)
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(128); frame:SetHeight(32)
		frame.Texture = frame:CreateTexture(nil, "BACKGROUND")
		frame.Texture:SetAllPoints(frame)
		frame.Texture:SetTexture(SHPlates.MEDIA .. "Neon\\Neon_Select")
		frame.Update = UpdateSelectionWidget
		frame.SetWidgetTexture = SetSelectionWidgetTexture
		frame:Hide()
		return frame
	end
end

------------------------------
-- Combo Point Widget
-- A thin bar split into 5 sections along the top edge of the health bar.
-- Each combo point lights one section; at 5 the whole bar turns red.
------------------------------
do
	local ComboWatcher = CreateFrame("Frame")
	local isEnabled = false
	local LIT = { r = 1, g = .82, b = .1 }
	local FULL = { r = 1, g = .25, b = .1 }
	local GAP = 1

	local function UpdateComboPointFrame(frame, unit)
		local points = 0
		if unit.isTarget and UnitExists("target") then points = GetComboPoints() or 0 end
		if points <= 0 then frame:Hide(); return end
		local c = (points >= 5) and FULL or LIT
		for i = 1, 5 do
			local seg = frame.segments[i]
			if i <= points then seg.fill:SetVertexColor(c.r, c.g, c.b, 1); seg.fill:Show()
			else seg.fill:Hide() end
		end
		frame:Show()
	end

	local function EnableComboWatcher()
		ComboWatcher:SetScript("OnEvent", function() SHPlates:Update() end)
		ComboWatcher:RegisterEvent("PLAYER_COMBO_POINTS")
		isEnabled = true
	end

	function SHPlatesWidgets.CreateComboPointWidget(parent, width, height)
		width = width or 101
		height = height or 3
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetWidth(width); frame:SetHeight(height)
		-- 1px dark edge so the sections read against any health color
		frame.edge = frame:CreateTexture(nil, "BACKGROUND")
		frame.edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
		frame.edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
		frame.edge:SetTexture(0, 0, 0, .9)
		-- whole pixels only: fractional widths let the client round a
		-- section (or a gap) away
		local segWidth = math.floor((width - GAP * 4) / 5)
		local start = math.floor((width - (segWidth * 5 + GAP * 4)) / 2)
		frame.segments = {}
		for i = 1, 5 do
			local seg = {}
			seg.bg = frame:CreateTexture(nil, "BORDER")
			seg.bg:SetWidth(segWidth); seg.bg:SetHeight(height)
			seg.bg:SetPoint("LEFT", frame, "LEFT", start + (i - 1) * (segWidth + GAP), 0)
			seg.bg:SetTexture(.15, .15, .15, 1)
			seg.fill = frame:CreateTexture(nil, "ARTWORK")
			seg.fill:SetAllPoints(seg.bg)
			seg.fill:SetTexture(SHPlates.MEDIA .. "Statusbar")
			seg.fill:Hide()
			frame.segments[i] = seg
		end
		frame:Hide()
		frame.Update = UpdateComboPointFrame
		if not isEnabled then EnableComboWatcher() end
		return frame
	end
end
