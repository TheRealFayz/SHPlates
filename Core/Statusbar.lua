-------------------------------------------------------------------------------
-- SHPlates: Statusbar
-- Lightweight texture-cropping statusbar (ported from Tidy Plates).
-------------------------------------------------------------------------------

local function UpdateBar(self)
	local range = self.MaxVal - self.MinVal
	local value = self.Value - self.MinVal
	local barsize = self.Dim or 1
	local fraction

	if range > 0 and value > 0 and range >= value then
		fraction = value / range
	else fraction = .01 end

	if self.Orientation == "VERTICAL" then
		self.Bar:SetHeight(barsize * fraction)
		self.Bar:SetTexCoord(0, 1, 1 - fraction, 1)
	else
		self.Bar:SetWidth(barsize * fraction)
		self.Bar:SetTexCoord(0, fraction, 0, 1)
	end
end

local function UpdateSize(self)
	if self.Orientation == "VERTICAL" then self.Dim = self:GetHeight()
	else self.Dim = self:GetWidth() end
	UpdateBar(self)
end

local function SetValue(self, value)
	if not value then return end
	if value >= self.MinVal and value <= self.MaxVal then self.Value = value
	elseif value < self.MinVal then self.Value = self.MinVal
	else self.Value = self.MaxVal end
	UpdateBar(self)
end

local function GetValue(self) return self.Value end
local function GetMinMaxValues(self) return self.MinVal, self.MaxVal end

local function SetStatusBarTexture(self, texture) self.Bar:SetTexture(texture) end
local function SetStatusBarColor(self, r, g, b, a) self.Bar:SetVertexColor(r, g, b, a or 1) end

local function SetOrientation(self, orientation)
	self.Bar:ClearAllPoints()
	if orientation == "VERTICAL" then
		self.Orientation = orientation
		self.Bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
		self.Bar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	else
		self.Orientation = "HORIZONTAL"
		self.Bar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		self.Bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
	end
	UpdateSize(self)
end

local function SetMinMaxValues(self, minval, maxval)
	if not (minval and maxval) then return end
	if maxval > minval then
		self.MinVal = minval
		self.MaxVal = maxval
	else
		self.MinVal = 0
		self.MaxVal = 1
	end
	if self.Value > self.MaxVal then self.Value = self.MaxVal
	elseif self.Value < self.MinVal then self.Value = self.MinVal end
	UpdateBar(self)
end

function SHPlates.CreateStatusbar(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(1)
	frame:SetWidth(1)
	frame.Value, frame.MinVal, frame.MaxVal, frame.Orientation = 1, 0, 1, "HORIZONTAL"
	frame.Bar = frame:CreateTexture(nil, "BACKGROUND")

	frame.SetValue = SetValue
	frame.GetValue = GetValue
	frame.GetMinMaxValues = GetMinMaxValues
	frame.SetMinMaxValues = SetMinMaxValues
	frame.SetOrientation = SetOrientation
	frame.SetStatusBarColor = SetStatusBarColor
	frame.SetStatusBarTexture = SetStatusBarTexture
	frame.UpdateSize = UpdateSize

	-- The core calls UpdateSize after resizing; OnSizeChanged is a backup
	frame:SetScript("OnSizeChanged", function() UpdateSize(frame) end)
	SetOrientation(frame, "HORIZONTAL")
	return frame
end
