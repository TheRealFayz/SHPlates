-------------------------------------------------------------------------------
-- SHPlates: Utility (table helpers and number formatting)
-------------------------------------------------------------------------------

local function copytable(original)
	local duplicate = {}
	for key, value in pairs(original) do
		if type(value) == "table" then duplicate[key] = copytable(value)
		else duplicate[key] = value end
	end
	return duplicate
end

-- Returns a new table: master's structure, overridden by mate's values
local function mergetable(master, mate)
	local merged = {}
	local matedata
	for key, value in pairs(master) do
		matedata = mate[key]
		if type(value) == "table" then
			if type(matedata) == "table" then merged[key] = mergetable(value, matedata)
			else merged[key] = copytable(value) end
		else
			if matedata == nil then merged[key] = value
			else merged[key] = matedata end
		end
	end
	-- keep keys that only exist in the mate (e.g. user list entries)
	for key, value in pairs(mate) do
		if merged[key] == nil then
			if type(value) == "table" then merged[key] = copytable(value) else merged[key] = value end
		end
	end
	return merged
end

-- Writes saved values into an existing (live) table in place, so local
-- references held by themes stay valid. Lists (tables without a matching
-- default structure) are replaced wholesale.
local function applysaved(live, saved)
	if type(live) ~= "table" or type(saved) ~= "table" then return live end
	for key, value in pairs(saved) do
		local current = live[key]
		if type(value) == "table" then
			if type(current) == "table" and key ~= "WidgetDebuffList" then
				applysaved(current, value)
			else
				live[key] = copytable(value)
			end
		elseif type(current) == type(value) or current == nil then
			live[key] = value
		end
	end
	return live
end

local function valueToString(value)
	if value ~= nil then
		if value >= 1000000 then return string.format("%.1fm", value / 1000000)
		elseif value >= 1000 then return string.format("%.1fk", value / 1000)
		else return value end
	end
end

SHPlatesUtility.abbrevNumber = valueToString
SHPlatesUtility.copyTable = copytable
SHPlatesUtility.mergeTable = mergetable
SHPlatesUtility.applySaved = applysaved

-- Threat helper: same contract as Tidy Plates' GetRelativeThreat, but takes
-- the plate's unit table (vanilla has no threat API). See Data.lua.
SHPlatesUtility.GetRelativeThreat = function(unit)
	return SHPlates.Data.GetRelativeThreat(unit)
end
