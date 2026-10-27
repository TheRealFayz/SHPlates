-------------------------------------------------------------------------------
-- SHPlates: critters by name (for plates without a SuperWoW GUID)
--
-- Without SuperWoW a plate can't be asked for its creature type, but your
-- target and your mouseover can. Every critter you target or mouse over is
-- remembered by name (shared by all characters), and from then on its plates
-- count as critters. A name that turns out to be something else is marked as
-- not a critter, which also overrides the starter list below.
--
-- The starter list only has names that are always critters. Names that real
-- mobs also use (Spider, Scorpion, Snake, Turtle...) are left to learning.
-------------------------------------------------------------------------------
local Critters = {}
SHPlates.Critters = Critters

local TYPES = { ["Critter"] = true, ["Kleintier"] = true, ["Bestiole"] = true, ["Alimaña"] = true,
	["Animale"] = true, ["Bicho"] = true, ["Существо"] = true }
Critters.TYPES = TYPES

local STARTER = {}
for _, n in ipairs({
	"Rabbit", "Hare", "Squirrel", "Prairie Dog", "Brown Prairie Dog", "Toad", "Jungle Toad",
	"Huge Toad", "Biletoad", "Frog", "Chicken", "Fawn", "Deer", "Gazelle", "Sheep", "Cow",
	"Rat", "Black Rat", "Deeprun Rat", "Enthralled Deeprun Rat", "Core Rat", "Plagued Rat",
	"Tainted Rat", "Mouse", "Roach", "Tainted Cockroach", "Beetle", "Fire Beetle", "Maggot",
	"Plagued Maggot", "Larva", "Plagued Insect", "Plagueland Termite", "Infected Deer",
	"Infected Squirrel", "Sickly Deer", "Sickly Gazelle", "Cured Deer", "Cured Gazelle",
	"Adder", "Moccasin", "Parrot", "Belfry Bat", "Lava Crab",
}) do STARTER[n] = true end

local function Learned()
	if type(SHPlatesLearned) ~= "table" then SHPlatesLearned = {} end
	if type(SHPlatesLearned.critters) ~= "table" then SHPlatesLearned.critters = {} end
	return SHPlatesLearned.critters
end

function Critters.IsCritterName(name)
	if not name then return false end
	local known = Learned()[name]
	if known ~= nil then return known end
	return STARTER[name] or false
end

local function Learn(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then return end
	local name, kind = UnitName(unit), UnitCreatureType(unit)
	if not name or not kind then return end
	local isCritter = TYPES[kind] and true or false
	local known = Critters.IsCritterName(name)
	if known ~= isCritter then
		Learned()[name] = isCritter
		if SHPlates.ForceUpdate then SHPlates:ForceUpdate() end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:SetScript("OnEvent", function()
	if SHPlates.disabled then return end
	if event == "PLAYER_TARGET_CHANGED" then Learn("target") else Learn("mouseover") end
end)
