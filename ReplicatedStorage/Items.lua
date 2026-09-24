--[[
	Items  (ModuleScript, parent: ReplicatedStorage, name: "Items")

	Everything about GEAR in one place: the rarities, the stats, every item,
	the gear sets and what each boss's treasure chest can drop. Tune it here.

	How it works:
	  * Beat a boss -> you get its TREASURE CHEST (kept in your bag until you
	    open it). Opening one rolls a RARITY first (see Rarities' odds), then
	    picks an item of that rarity from that boss's loot.
	  * Every item ROLLS its stats inside a range when it drops, so two of the
	    same item aren't equal. The better the rolls, the more stars it shows
	    (0-3); an item with every stat at its best is PERFECT and glows.
	  * Wear up to four pieces: Weapon, Helmet, Chest, Boots. Wearing 2 or 4
	    pieces of the same SET unlocks its bonus.
	  * Every item needs a LEVEL: the highest level you've ever reached (so
	    prestiging never locks you out of your own gear).
	  * Gear and chests stay through prestige.

	The server rolls and hands out everything; the client only ever reads this.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local RGB = Color3.fromRGB
local Items = {}

----------------------------------------------------------------------
-- Rarities, from most to least common. `odds` are weights: the chance of a
-- rarity is its weight out of all of them (here they add up to 100, so
-- they read as percentages). Salvage = coins for breaking an item down.
----------------------------------------------------------------------
Items.Rarities = {
	{ id = "Common", color = RGB(235, 235, 240), odds = 46, salvage = 40 },
	{ id = "Uncommon", color = RGB(99, 199, 77), odds = 28, salvage = 100 },
	{ id = "Rare", color = RGB(0, 153, 219), odds = 16, salvage = 260 },
	{ id = "Epic", color = RGB(170, 100, 255), odds = 7, salvage = 700 },
	{ id = "Legendary", color = RGB(254, 174, 52), odds = 2.4, salvage = 2200 },
	{ id = "Mythic", color = RGB(255, 0, 68), odds = 0.58, salvage = 9000 },
	{ id = "Secret", color = RGB(255, 255, 255), odds = 0.02, salvage = 60000, secret = true }, -- about 1 chest in 5000
}
Items.RarityById = {}
for i, r in ipairs(Items.Rarities) do
	r.rank = i
	Items.RarityById[r.id] = r
end

----------------------------------------------------------------------
-- Stats. Percent stats are whole numbers (12 = 12%).
----------------------------------------------------------------------
Items.Stats = {
	{ id = "Damage", label = "Damage", percent = true, desc = "more damage to bosses" },
	{ id = "Crit", label = "Crit Chance", percent = true, desc = "chance of a critical hit (x1.75 damage)", cap = 60 },
	{ id = "Health", label = "Health", percent = false, desc = "more max health" },
	{ id = "Defense", label = "Defense", percent = true, desc = "less damage taken", cap = 60 },
	{ id = "Power", label = "Training Power", percent = true, desc = "more Power from training" },
}
Items.StatById = {}
for i, s in ipairs(Items.Stats) do
	s.order = i
	Items.StatById[s.id] = s
end
Items.CritMultiplier = 1.75

Items.Slots = { "Weapon", "Helmet", "Chest", "Boots" }
Items.BagSize = 60 -- how many items fit in your bag (chests don't count)

----------------------------------------------------------------------
-- Gear sets: wear `need` pieces of the set for each bonus
----------------------------------------------------------------------
Items.Sets = {
	Gelatinous = {
		name = "Gelatinous",
		bonuses = { { need = 2, stats = { Defense = 5 } }, { need = 4, stats = { Damage = 12, Health = 30 } } },
	},
	Regalia = {
		name = "Tyrant's Regalia",
		bonuses = { { need = 2, stats = { Crit = 8 } }, { need = 4, stats = { Damage = 20, Defense = 10 } } },
	},
	Duneworn = {
		name = "Duneworn",
		bonuses = { { need = 2, stats = { Defense = 6 } }, { need = 4, stats = { Damage = 15, Health = 50 } } },
	},
	Devourer = {
		name = "Devourer's",
		bonuses = { { need = 2, stats = { Crit = 10 } }, { need = 4, stats = { Damage = 25, Defense = 12 } } },
	},
}

----------------------------------------------------------------------
-- The items. stats = { Stat = { lowest, highest } }. tint = the colours its
-- pixel icon is drawn in. floor = the boss (Spire floor) that drops it.
----------------------------------------------------------------------
local list = {
	-- OOZARK, the Gelatinous Tyrant (floor 1)
	{ id = "GooBoots", name = "Goo-Stained Boots", slot = "Boots", rarity = "Common", level = 10, floor = 1, set = "Gelatinous",
		stats = { Health = { 6, 12 } }, tint = { RGB(99, 199, 77), RGB(62, 137, 72) },
		lore = "* They squelch. Every. Single. Step." },
	{ id = "JellyHelm", name = "Jelly Helm", slot = "Helmet", rarity = "Uncommon", level = 12, floor = 1, set = "Gelatinous",
		stats = { Health = { 10, 18 }, Defense = { 2, 4 } }, tint = { RGB(120, 255, 90), RGB(62, 137, 72) },
		lore = "* Wobbles when you nod. You'll get used to it." },
	{ id = "WobblePlate", name = "Wobble Plate", slot = "Chest", rarity = "Rare", level = 15, floor = 1, set = "Gelatinous",
		stats = { Health = { 20, 35 }, Defense = { 4, 7 } }, tint = { RGB(99, 199, 77), RGB(38, 92, 66) },
		lore = "* Blows bounce right off. So do compliments." },
	{ id = "JellySword", name = "Jelly Sword", slot = "Weapon", rarity = "Rare", level = 15, floor = 1, set = "Gelatinous",
		stats = { Damage = { 8, 14 } }, tint = { RGB(120, 255, 90), RGB(234, 212, 170) },
		lore = "* It wobbles when you swing it. Oozark's subjects still bow to it." },
	{ id = "SumpScepter", name = "Scepter of the Sump", slot = "Weapon", rarity = "Epic", level = 18, floor = 1, set = "Regalia",
		stats = { Damage = { 15, 24 }, Crit = { 3, 6 } }, tint = { RGB(254, 174, 52), RGB(120, 255, 90) },
		lore = "* The Tyrant ruled a puddle with it. A very large puddle." },
	{ id = "GooMantle", name = "Royal Goo Mantle", slot = "Chest", rarity = "Epic", level = 18, floor = 1, set = "Regalia",
		stats = { Health = { 35, 55 }, Defense = { 6, 9 } }, tint = { RGB(181, 80, 136), RGB(254, 174, 52) },
		lore = "* Fit for a king. Smells like one too. A damp one." },
	{ id = "OozarkCrown", name = "Crown of Oozark", slot = "Helmet", rarity = "Legendary", level = 20, floor = 1, set = "Regalia",
		stats = { Damage = { 8, 12 }, Health = { 25, 40 }, Crit = { 4, 7 } }, tint = { RGB(254, 231, 97), RGB(120, 255, 90) },
		lore = "* Do not touch the crown. It is also slime." },
	{ id = "TyrantTreads", name = "Tyrant's Treads", slot = "Boots", rarity = "Legendary", level = 20, floor = 1, set = "Regalia",
		stats = { Health = { 20, 32 }, Defense = { 5, 8 }, Power = { 5, 10 } }, tint = { RGB(254, 174, 52), RGB(181, 80, 136) },
		lore = "* Every step a royal decree." },
	{ id = "HollowHeart", name = "Heart of the Hollow", slot = "Weapon", rarity = "Mythic", level = 22, floor = 1,
		stats = { Damage = { 30, 45 }, Crit = { 8, 12 }, Power = { 10, 20 } }, tint = { RGB(255, 0, 68), RGB(120, 255, 90) },
		lore = "* Still beating. Still hungry. Still yours, for now." },
	{ id = "FirstPuddle", name = "Crown of the First Puddle", slot = "Helmet", rarity = "Secret", level = 25, floor = 1,
		stats = { Damage = { 40, 55 }, Health = { 80, 120 }, Crit = { 12, 16 }, Defense = { 10, 14 } }, tint = { RGB(44, 232, 245), RGB(255, 255, 255) },
		lore = "* bef#re th3 Tyr@nt th*re was a puddl3. it rem3mb#rs y%u." },

	-- NAHRZUL, Devourer of the Dunes (floor 2)
	{ id = "SandBoots", name = "Sand-Wrapped Boots", slot = "Boots", rarity = "Common", level = 25, floor = 2, set = "Duneworn",
		stats = { Health = { 14, 24 } }, tint = { RGB(228, 166, 114), RGB(184, 111, 80) },
		lore = "* Sand in them already. Sand in them forever." },
	{ id = "ScaleHelm", name = "Scaleplate Helm", slot = "Helmet", rarity = "Uncommon", level = 27, floor = 2, set = "Duneworn",
		stats = { Health = { 22, 34 }, Defense = { 3, 5 } }, tint = { RGB(194, 133, 105), RGB(234, 212, 170) },
		lore = "* Made from a scale Nahrzul shed. It was the size of a door." },
	{ id = "DuneCuirass", name = "Dunescale Cuirass", slot = "Chest", rarity = "Rare", level = 30, floor = 2, set = "Duneworn",
		stats = { Health = { 40, 60 }, Defense = { 6, 9 } }, tint = { RGB(228, 166, 114), RGB(115, 62, 57) },
		lore = "* Warm from the desert sun. Always. Somehow." },
	{ id = "FangDagger", name = "Worm-Fang Dagger", slot = "Weapon", rarity = "Rare", level = 30, floor = 2, set = "Duneworn",
		stats = { Damage = { 14, 22 }, Crit = { 2, 4 } }, tint = { RGB(234, 212, 170), RGB(115, 62, 57) },
		lore = "* One of a thousand teeth. It will not miss the other 999." },
	{ id = "NahrzulFang", name = "Fang of Nahrzul", slot = "Weapon", rarity = "Epic", level = 33, floor = 2, set = "Devourer",
		stats = { Damage = { 24, 34 }, Crit = { 4, 8 } }, tint = { RGB(255, 255, 255), RGB(247, 118, 34) },
		lore = "* The dunes remember the bite." },
	{ id = "DeepCarapace", name = "Carapace of the Deep", slot = "Chest", rarity = "Epic", level = 33, floor = 2, set = "Devourer",
		stats = { Health = { 60, 85 }, Defense = { 8, 12 } }, tint = { RGB(115, 62, 57), RGB(247, 118, 34) },
		lore = "* Armour from beneath the sand, where the light never reaches." },
	{ id = "MawHelm", name = "Maw Helm", slot = "Helmet", rarity = "Legendary", level = 36, floor = 2, set = "Devourer",
		stats = { Damage = { 12, 18 }, Health = { 45, 65 }, Crit = { 5, 8 } }, tint = { RGB(62, 39, 49), RGB(254, 174, 52) },
		lore = "* You wear its mouth. It does not seem to mind. Yet." },
	{ id = "SunkenTreads", name = "Sunken Treads", slot = "Boots", rarity = "Legendary", level = 36, floor = 2, set = "Devourer",
		stats = { Health = { 35, 50 }, Defense = { 7, 10 }, Power = { 8, 14 } }, tint = { RGB(184, 111, 80), RGB(254, 231, 97) },
		lore = "* Silent on stone. Silent on sand. Silent." },
	{ id = "Dunebreaker", name = "Dunebreaker", slot = "Weapon", rarity = "Mythic", level = 40, floor = 2,
		stats = { Damage = { 45, 65 }, Crit = { 10, 15 }, Defense = { 5, 8 } }, tint = { RGB(255, 0, 68), RGB(254, 174, 52) },
		lore = "* It split the desert once. It remembers how." },
	{ id = "BuriedSun", name = "Heart of the Buried Sun", slot = "Chest", rarity = "Secret", level = 45, floor = 2,
		stats = { Health = { 150, 220 }, Defense = { 15, 20 }, Damage = { 25, 35 }, Power = { 15, 25 } }, tint = { RGB(254, 231, 97), RGB(255, 255, 255) },
		lore = "* th3 sun th@t f#ll und#r the s@nd. it is st*ll w@rm." },
}

Items.ById = {}
Items.ByFloor = {} -- [floor][rarity] = { item, ... }
for i, it in ipairs(list) do
	it.order = i
	Items.ById[it.id] = it
	Items.ByFloor[it.floor] = Items.ByFloor[it.floor] or {}
	Items.ByFloor[it.floor][it.rarity] = Items.ByFloor[it.floor][it.rarity] or {}
	table.insert(Items.ByFloor[it.floor][it.rarity], it)
end
Items.List = list

-- The treasure chests: one per boss, named for it
function Items.chestName(floor)
	local def = Config.Bosses and Config.Bosses[floor]
	return ((def and def.Short) or ("Floor " .. floor)) .. "'s Chest"
end

----------------------------------------------------------------------
-- Rolling (the server does this)
----------------------------------------------------------------------
-- a rarity from the odds, then an item of it from this boss's loot. If the
-- boss has nothing of that rarity, it drops to the next rarer-to-commoner one.
function Items.rollDrop(floor, rng)
	local pool = Items.ByFloor[floor]
	if not pool then
		return nil
	end
	local total = 0
	for _, r in ipairs(Items.Rarities) do
		total = total + r.odds
	end
	local pick = rng:NextNumber() * total
	local rank = 1
	for i, r in ipairs(Items.Rarities) do
		pick = pick - r.odds
		if pick <= 0 then
			rank = i
			break
		end
	end
	for k = rank, 1, -1 do
		local choices = pool[Items.Rarities[k].id]
		if choices and #choices > 0 then
			return choices[rng:NextInteger(1, #choices)]
		end
	end
	return nil
end

-- the item's stats rolled inside their ranges
function Items.rollStats(def, rng)
	local r = {}
	for stat, range in pairs(def.stats) do
		r[stat] = rng:NextInteger(range[1], range[2])
	end
	return r
end

----------------------------------------------------------------------
-- Reading items (both sides)
----------------------------------------------------------------------
-- how good the rolls are: 0..1 overall, stars 0-3, and whether it's perfect
function Items.quality(def, rolls)
	local sum, n, perfect = 0, 0, true
	for stat, range in pairs(def.stats) do
		local v = rolls[stat] or range[1]
		local span = range[2] - range[1]
		local q = span > 0 and (v - range[1]) / span or 1
		sum = sum + q
		n = n + 1
		if v < range[2] then
			perfect = false
		end
	end
	local q = n > 0 and sum / n or 1
	local stars = (q >= 0.9 and 3) or (q >= 0.6 and 2) or (q >= 0.3 and 1) or 0
	return q, stars, perfect
end

-- everything your equipped gear gives you: its stats plus set bonuses, capped
function Items.gearStats(d)
	local total = { Damage = 0, Crit = 0, Health = 0, Defense = 0, Power = 0 }
	local sets = {}
	local items, gear = d and d.Items, d and d.Gear
	if type(items) ~= "table" or type(gear) ~= "table" then
		return total, sets
	end
	for _, slot in ipairs(Items.Slots) do
		local uid = gear[slot]
		local rec = uid and items[uid]
		local def = rec and Items.ById[rec.id]
		if def then
			for stat, v in pairs(rec.r or {}) do
				if total[stat] then
					total[stat] = total[stat] + v
				end
			end
			if def.set then
				sets[def.set] = (sets[def.set] or 0) + 1
			end
		end
	end
	for setId, count in pairs(sets) do
		local set = Items.Sets[setId]
		for _, b in ipairs(set and set.bonuses or {}) do
			if count >= b.need then
				for stat, v in pairs(b.stats) do
					total[stat] = total[stat] + v
				end
			end
		end
	end
	for _, s in ipairs(Items.Stats) do
		if s.cap then
			total[s.id] = math.min(total[s.id], s.cap)
		end
	end
	return total, sets
end

-- how many items are in the bag
function Items.count(d)
	local n = 0
	for _ in pairs(d and d.Items or {}) do
		n = n + 1
	end
	return n
end

-- the level that counts for gear: the highest you've ever reached
function Items.gearLevel(d)
	return math.max(d and d.BestLevel or 1, Config.levelFromPower(d and d.Power or 0))
end

-- "+12% Damage" / "+30 Health"
function Items.formatStat(stat, v)
	local s = Items.StatById[stat]
	if not s then
		return tostring(v)
	end
	return "+" .. tostring(v) .. (s.percent and "% " or " ") .. s.label
end

return Items
