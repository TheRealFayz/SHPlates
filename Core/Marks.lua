-------------------------------------------------------------------------------
-- SHPlates: Raid marks with keybinds, also when solo
-- In a group this is a normal raid mark. Solo, SuperWoW's "local" mark is
-- used (only you see it) and SHPlates also remembers it by GUID, so the plate
-- shows it either way. Bind keys under Key Bindings > SHPlates.
-------------------------------------------------------------------------------
local C = SHPlates.Compat
local Marks = {}
SHPlates.Marks = Marks
Marks.local_ = {}   -- guid -> index (solo marks)

BINDING_HEADER_SHPLATES = "SHPlates"
local NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
for i = 1, 8 do setglobal("BINDING_NAME_SHPLATES_MARK_" .. i, "Mark target: " .. NAMES[i]) end
BINDING_NAME_SHPLATES_MARK_0 = "Clear target mark"

local function InGroup()
	return UnitInRaid("player") or GetNumPartyMembers() > 0
end

function Marks.Get(guid)
	return guid and Marks.local_[guid]
end

function SHPlates_Mark(index)
	if not UnitExists("target") then return end
	local guid = C.GUID("target")
	local current = (GetRaidTargetIndex and GetRaidTargetIndex("target")) or Marks.Get(guid) or 0
	if index ~= 0 and current == index then index = 0 end  -- pressing it again clears it

	if InGroup() then
		SetRaidTarget("target", index)
	else
		if C.HasSuperWoW then pcall(SetRaidTarget, "target", index, "local") end
		if guid then
			-- one mark per icon, like real raid marks
			for g, i in pairs(Marks.local_) do if i == index then Marks.local_[g] = nil end end
			if index == 0 then Marks.local_[guid] = nil else Marks.local_[guid] = index end
		end
	end
	SHPlates:Update()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "UNIT_DIED")
f:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then C.wipe(Marks.local_)
	elseif arg1 then Marks.local_[arg1] = nil end
end)
