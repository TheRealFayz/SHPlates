-------------------------------------------------------------------------------
-- SHPlates: debuff durations (fallback when Nampower isn't installed)
-- Base 1.12 durations in seconds. A number is the duration for every rank;
-- a list gives it per rank (last entry repeats for higher ranks).
-- Talents that change durations are not included.
-------------------------------------------------------------------------------
local D = {
	-- Warrior
	["Rend"] = { 9, 12, 15, 18, 21 },
	["Hamstring"] = 15,
	["Thunder Clap"] = { 10, 14, 18, 22, 26, 30 },
	["Demoralizing Shout"] = 30,
	["Sunder Armor"] = 30,
	["Mortal Strike"] = 10,
	["Piercing Howl"] = 6,
	["Disarm"] = 10,
	["Concussion Blow"] = 5,
	["Intimidating Shout"] = 8,
	["Mocking Blow"] = 6,
	["Challenging Shout"] = 6,
	["Deep Wound"] = 12,
	-- Rogue
	["Rupture"] = 16,
	["Garrote"] = 18,
	["Gouge"] = 4,
	["Sap"] = { 25, 35, 45 },
	["Cheap Shot"] = 4,
	["Kidney Shot"] = 6,
	["Blind"] = 10,
	["Expose Armor"] = 30,
	["Hemorrhage"] = 15,
	["Crippling Poison"] = 12,
	["Deadly Poison"] = 12,
	["Deadly Poison II"] = 12,
	["Deadly Poison III"] = 12,
	["Deadly Poison IV"] = 12,
	["Deadly Poison V"] = 12,
	["Mind-numbing Poison"] = { 10, 12, 14 },
	["Wound Poison"] = 15,
	-- Mage
	["Frostbolt"] = { 5, 6, 7, 7, 8, 8, 9 },
	["Polymorph"] = { 20, 30, 40, 50 },
	["Frost Nova"] = 8,
	["Cone of Cold"] = 8,
	["Fireball"] = { 4, 6, 6, 8 },
	["Pyroblast"] = 12,
	["Ignite"] = 4,
	["Fire Vulnerability"] = 30,
	["Winter's Chill"] = 15,
	["Detect Magic"] = 120,
	-- Warlock
	["Corruption"] = { 12, 15, 18 },
	["Curse of Agony"] = 24,
	["Immolate"] = 15,
	["Siphon Life"] = 30,
	["Curse of Weakness"] = 120,
	["Curse of Recklessness"] = 120,
	["Curse of Tongues"] = 30,
	["Curse of the Elements"] = 300,
	["Curse of Shadow"] = 300,
	["Curse of Doom"] = 60,
	["Curse of Exhaustion"] = 12,
	["Fear"] = { 10, 15, 20 },
	["Banish"] = { 20, 30 },
	["Howl of Terror"] = { 10, 15 },
	["Death Coil"] = 3,
	["Shadow Vulnerability"] = 12,
	-- Priest
	["Shadow Word: Pain"] = 18,
	["Mind Flay"] = 3,
	["Devouring Plague"] = 24,
	["Psychic Scream"] = 8,
	["Mind Soothe"] = 15,
	["Vampiric Embrace"] = 60,
	["Hex of Weakness"] = 120,
	["Shackle Undead"] = { 30, 40, 50 },
	["Holy Fire"] = 10,
	-- Druid
	["Moonfire"] = { 9, 12 },
	["Rake"] = 9,
	["Rip"] = 12,
	["Insect Swarm"] = 12,
	["Faerie Fire"] = 40,
	["Faerie Fire (Feral)"] = 40,
	["Entangling Roots"] = { 12, 15, 18, 21, 24, 27 },
	["Hibernate"] = { 20, 30, 40 },
	["Demoralizing Roar"] = 30,
	["Bash"] = { 2, 3, 4 },
	["Pounce Bleed"] = 18,
	["Challenging Roar"] = 6,
	-- Hunter
	["Serpent Sting"] = 15,
	["Hunter's Mark"] = 120,
	["Scorpid Sting"] = 20,
	["Viper Sting"] = 8,
	["Wing Clip"] = 10,
	["Concussive Shot"] = 4,
	["Scatter Shot"] = 4,
	["Freezing Trap Effect"] = { 10, 15, 20 },
	["Immolation Trap Effect"] = 15,
	["Explosive Trap Effect"] = 20,
	["Wyvern Sting"] = 12,
	["Counterattack"] = 5,
	-- Paladin
	["Hammer of Justice"] = { 3, 4, 5, 6 },
	["Judgement of Light"] = 10,
	["Judgement of Wisdom"] = 10,
	["Judgement of the Crusader"] = 10,
	["Judgement of Justice"] = 10,
	["Turn Undead"] = { 10, 15, 20 },
	["Repentance"] = 6,
	-- Shaman
	["Flame Shock"] = 12,
	["Frost Shock"] = 8,
	["Stormstrike"] = 12,
}

-- Effects that stun (used for the "stunned" health bar color)
local STUNS = {
	["Cheap Shot"] = true, ["Kidney Shot"] = true, ["Bash"] = true, ["Pounce"] = true,
	["Hammer of Justice"] = true, ["Concussion Blow"] = true, ["Charge Stun"] = true,
	["Intercept Stun"] = true, ["War Stomp"] = true, ["Impact"] = true, ["Intimidation"] = true,
	["Mace Stun Effect"] = true, ["Stun"] = true, ["Blackout"] = true, ["Revenge Stun"] = true,
	["Starfire Stun"] = true, ["Improved Concussive Shot"] = true, ["Stoneclaw Stun"] = true,
	["Seal of Justice"] = true, ["Hammer of Wrath Stun"] = true, ["Tidal Charm"] = true,
}

SHPlates.SpellDurations = D
SHPlates.StunEffects = STUNS

-- Duration for a spell name + rank text ("Rank 3"), or nil when unknown
function SHPlates.GetFallbackDuration(name, rankText)
	local entry = name and D[name]
	if not entry then return nil end
	if type(entry) == "number" then return entry end
	local rank = 1
	if rankText then
		local _, _, r = string.find(rankText, "(%d+)")
		rank = tonumber(r) or 1
	end
	local n = table.getn(entry)
	if rank > n then rank = n end
	return entry[rank]
end
