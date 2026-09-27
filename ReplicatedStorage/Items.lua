--[[
	Items  (ModuleScript, parent: ReplicatedStorage, name: "Items")

	Everything about GEAR in one place: the rarities, the stats, every item,
	the gear sets and what each boss's treasure chest can drop. Tune it here.

	How it works:
	  * Beat a boss -> you get its TREASURE CHEST (kept in your bag until you
	    open it). Opening one rolls a RARITY first (see Rarities' odds), then
	    picks an item of that rarity from that boss's loot.
	  * Every new player's first chest is OOZLET'S (from the intro: Config.Intro):
	    starter gear anyone can wear, kept as "floor" 0.
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
	Spadeknight = {
		name = "Spade Knight's",
		bonuses = { { need = 2, stats = { Defense = 7 } }, { need = 4, stats = { Damage = 18, Health = 70 } } },
	},
	Relicbound = {
		name = "Relicbound",
		bonuses = { { need = 2, stats = { Crit = 11 } }, { need = 4, stats = { Damage = 28, Defense = 13 } } },
	},
	Windwalker = {
		name = "Windwalker",
		bonuses = { { need = 2, stats = { Defense = 8 } }, { need = 4, stats = { Damage = 21, Health = 90 } } },
	},
	KiMaster = {
		name = "Ki Master's",
		bonuses = { { need = 2, stats = { Crit = 12 } }, { need = 4, stats = { Damage = 32, Defense = 14 } } },
	},
	Speedster = {
		name = "Speedster",
		bonuses = { { need = 2, stats = { Defense = 9 } }, { need = 4, stats = { Damage = 24, Health = 110 } } },
	},
	Turbocharged = {
		name = "Turbocharged",
		bonuses = { { need = 2, stats = { Crit = 13 } }, { need = 4, stats = { Damage = 36, Defense = 15 } } },
	},
	Beatbound = {
		name = "Beatbound",
		bonuses = { { need = 2, stats = { Defense = 10 } }, { need = 4, stats = { Damage = 27, Health = 130 } } },
	},
	DemonGeometry = {
		name = "Demon Geometry",
		bonuses = { { need = 2, stats = { Crit = 14 } }, { need = 4, stats = { Damage = 40, Defense = 16 } } },
	},
}

----------------------------------------------------------------------
-- The items. stats = { Stat = { lowest, highest } }. tint = the colours its
-- pixel icon is drawn in. floor = the boss (Spire floor) that drops it.
----------------------------------------------------------------------
local list = {
	-- OOZLET, Oozark's little one (the intro - "floor" 0): its chest is every
	-- new player's first, so it's starter gear anyone can wear
	{ id = "SquishyGloves", name = "Squishy Gloves", slot = "Weapon", rarity = "Common", level = 1, floor = 0,
		stats = { Damage = { 3, 6 } }, tint = { RGB(120, 255, 90), RGB(62, 137, 72) },
		lore = "* Every punch goes 'boing'. Oozlet would be proud." },
	{ id = "BouncyBoots", name = "Bouncy Boots", slot = "Boots", rarity = "Common", level = 1, floor = 0,
		stats = { Health = { 4, 8 } }, tint = { RGB(99, 199, 77), RGB(234, 212, 170) },
		lore = "* Still a little sticky. That's how you know they're real." },
	{ id = "OozletCap", name = "Oozlet Cap", slot = "Helmet", rarity = "Uncommon", level = 1, floor = 0,
		stats = { Health = { 6, 10 }, Defense = { 1, 2 } }, tint = { RGB(120, 255, 90), RGB(254, 231, 97) },
		lore = "* A tiny crown of jelly. It wobbles when you're brave." },
	{ id = "GooVest", name = "Goo Vest", slot = "Chest", rarity = "Uncommon", level = 1, floor = 0,
		stats = { Health = { 8, 14 } }, tint = { RGB(99, 199, 77), RGB(38, 92, 66) },
		lore = "* Warm, green, and slightly alive." },

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

	-- KNIGHT BURROWMORE, the Honourable Digger (floor 3)
	{ id = "DigBoots", name = "Digger's Boots", slot = "Boots", rarity = "Common", level = 40, floor = 3, set = "Spadeknight",
		stats = { Health = { 20, 32 } }, tint = { RGB(18, 78, 137), RGB(115, 62, 57) },
		lore = "* Steel toes. For kicking your shovel into stubborn dirt." },
	{ id = "HornedHelm", name = "Curly-Horned Helm", slot = "Helmet", rarity = "Uncommon", level = 42, floor = 3, set = "Spadeknight",
		stats = { Health = { 30, 44 }, Defense = { 4, 6 } }, tint = { RGB(0, 153, 219), RGB(254, 174, 52) },
		lore = "* The horns are for style. The style is for honour." },
	{ id = "Spadeplate", name = "Spadeplate", slot = "Chest", rarity = "Rare", level = 45, floor = 3, set = "Spadeknight",
		stats = { Health = { 55, 80 }, Defense = { 7, 10 } }, tint = { RGB(0, 153, 219), RGB(18, 78, 137) },
		lore = "* Polished every morning. Muddy by every afternoon." },
	{ id = "TrustyShovel", name = "Trusty Shovel", slot = "Weapon", rarity = "Rare", level = 45, floor = 3, set = "Spadeknight",
		stats = { Damage = { 18, 28 }, Crit = { 3, 5 } }, tint = { RGB(254, 174, 52), RGB(115, 62, 57) },
		lore = "* Digs dirt. Digs foes. Mostly dirt." },
	{ id = "FireStick", name = "Fire Stick", slot = "Weapon", rarity = "Epic", level = 48, floor = 3, set = "Relicbound",
		stats = { Damage = { 30, 42 }, Crit = { 5, 9 } }, tint = { RGB(247, 118, 34), RGB(115, 62, 57) },
		lore = "* Point the hot end at the enemy. Not at your face." },
	{ id = "AnchorPlate", name = "Anchor Plate", slot = "Chest", rarity = "Epic", level = 48, floor = 3, set = "Relicbound",
		stats = { Health = { 75, 105 }, Defense = { 9, 13 } }, tint = { RGB(139, 155, 180), RGB(58, 68, 102) },
		lore = "* Nothing will knock you over. Getting up is another matter." },
	{ id = "CheckpointCrown", name = "Checkpoint Crown", slot = "Helmet", rarity = "Legendary", level = 51, floor = 3, set = "Relicbound",
		stats = { Damage = { 14, 20 }, Health = { 55, 80 }, Crit = { 6, 9 } }, tint = { RGB(44, 232, 245), RGB(254, 174, 52) },
		lore = "* Smash it for gold, or keep it for luck. Why not both?" },
	{ id = "PogoGreaves", name = "Pogo Greaves", slot = "Boots", rarity = "Legendary", level = 51, floor = 3, set = "Relicbound",
		stats = { Health = { 45, 65 }, Defense = { 8, 11 }, Power = { 10, 16 } }, tint = { RGB(18, 78, 137), RGB(254, 231, 97) },
		lore = "* Point your toes down and BOUNCE." },
	{ id = "LegendShovel", name = "Shovel of Legends", slot = "Weapon", rarity = "Mythic", level = 55, floor = 3,
		stats = { Damage = { 60, 85 }, Crit = { 12, 17 }, Defense = { 6, 9 } }, tint = { RGB(255, 0, 68), RGB(254, 174, 52) },
		lore = "* It has dug up dragons. And politely put them back." },
	{ id = "FirstShovel", name = "The Very First Shovel", slot = "Weapon", rarity = "Secret", level = 60, floor = 3,
		stats = { Damage = { 70, 95 }, Crit = { 16, 20 }, Health = { 120, 180 }, Power = { 20, 30 } }, tint = { RGB(254, 231, 97), RGB(255, 255, 255) },
		lore = "* b#fore the kn*ght th3re w@s a h0le. s0mebody d#g it." },

	-- KAZE, the Headband Hero (floor 4)
	{ id = "DojoSandals", name = "Dojo Sandals", slot = "Boots", rarity = "Common", level = 60, floor = 4, set = "Windwalker",
		stats = { Health = { 26, 40 } }, tint = { RGB(184, 111, 80), RGB(232, 183, 150) },
		lore = "* Worn smooth by ten thousand laps of the dojo." },
	{ id = "RedHeadband", name = "Red Headband", slot = "Helmet", rarity = "Uncommon", level = 62, floor = 4, set = "Windwalker",
		stats = { Health = { 38, 54 }, Defense = { 5, 7 } }, tint = { RGB(228, 59, 68), RGB(162, 38, 51) },
		lore = "* Tie it on and you feel 20% more heroic. Scientifically." },
	{ id = "TrainingGi", name = "Training Gi", slot = "Chest", rarity = "Rare", level = 65, floor = 4, set = "Windwalker",
		stats = { Health = { 68, 96 }, Defense = { 8, 11 } }, tint = { RGB(255, 255, 255), RGB(24, 20, 37) },
		lore = "* Smells like hard work. And a little like sunset." },
	{ id = "WindWraps", name = "Wind Wraps", slot = "Weapon", rarity = "Rare", level = 65, floor = 4, set = "Windwalker",
		stats = { Damage = { 22, 34 }, Crit = { 4, 6 } }, tint = { RGB(192, 203, 220), RGB(228, 59, 68) },
		lore = "* Wrap your fists. Feel the breeze. Punch the breeze." },
	{ id = "KazeGloves", name = "Kaze's Gloves", slot = "Weapon", rarity = "Epic", level = 68, floor = 4, set = "KiMaster",
		stats = { Damage = { 36, 50 }, Crit = { 6, 10 } }, tint = { RGB(228, 59, 68), RGB(44, 232, 245) },
		lore = "* Still warm from the last KAZE-BLAST!" },
	{ id = "FocusMantle", name = "Focus Mantle", slot = "Chest", rarity = "Epic", level = 68, floor = 4, set = "KiMaster",
		stats = { Health = { 90, 125 }, Defense = { 10, 14 } }, tint = { RGB(0, 153, 219), RGB(44, 232, 245) },
		lore = "* Breathe in. Breathe out. Hit things." },
	{ id = "DragonBand", name = "Rising Dragon Band", slot = "Helmet", rarity = "Legendary", level = 72, floor = 4, set = "KiMaster",
		stats = { Damage = { 17, 24 }, Health = { 68, 95 }, Crit = { 7, 10 } }, tint = { RGB(228, 59, 68), RGB(254, 174, 52) },
		lore = "* Uppercuts not included. Okay, a few are included." },
	{ id = "TornadoTreads", name = "Tornado Treads", slot = "Boots", rarity = "Legendary", level = 72, floor = 4, set = "KiMaster",
		stats = { Health = { 55, 78 }, Defense = { 9, 12 }, Power = { 12, 18 } }, tint = { RGB(255, 255, 255), RGB(44, 232, 245) },
		lore = "* Spin to win. Spin to win. Spin to... dizzy." },
	{ id = "FourWinds", name = "Fist of the Four Winds", slot = "Weapon", rarity = "Mythic", level = 74, floor = 4,
		stats = { Damage = { 72, 100 }, Crit = { 14, 19 }, Defense = { 7, 10 } }, tint = { RGB(255, 0, 68), RGB(44, 232, 245) },
		lore = "* North, south, east and west. All of them punch." },
	{ id = "EndlessHeadband", name = "The Endless Headband", slot = "Helmet", rarity = "Secret", level = 78, floor = 4,
		stats = { Damage = { 80, 110 }, Crit = { 18, 22 }, Health = { 140, 200 }, Power = { 22, 32 } }, tint = { RGB(228, 59, 68), RGB(255, 255, 255) },
		lore = "* th# w*nd n3ver st0ps bl0wing. n#ither d0es h3." },

	-- SPEEDY REVVINGTON, King of the Speedway (floor 5)
	{ id = "RacingSneakers", name = "Racing Sneakers", slot = "Boots", rarity = "Common", level = 75, floor = 5, set = "Speedster",
		stats = { Health = { 32, 48 } }, tint = { RGB(228, 59, 68), RGB(255, 255, 255) },
		lore = "* Red stripes make you faster. Everybody knows that." },
	{ id = "RaceHelmet", name = "Race Helmet", slot = "Helmet", rarity = "Uncommon", level = 77, floor = 5, set = "Speedster",
		stats = { Health = { 46, 64 }, Defense = { 6, 8 } }, tint = { RGB(228, 59, 68), RGB(24, 20, 37) },
		lore = "* Safety first. Speed a very, very close second." },
	{ id = "PitCrewJacket", name = "Pit Crew Jacket", slot = "Chest", rarity = "Rare", level = 80, floor = 5, set = "Speedster",
		stats = { Health = { 82, 114 }, Defense = { 9, 12 } }, tint = { RGB(254, 174, 52), RGB(24, 20, 37) },
		lore = "* Can change four tyres in six seconds. Cannot tie shoelaces." },
	{ id = "TireIron", name = "Tire Iron", slot = "Weapon", rarity = "Rare", level = 80, floor = 5, set = "Speedster",
		stats = { Damage = { 26, 40 }, Crit = { 4, 7 } }, tint = { RGB(139, 155, 180), RGB(58, 68, 102) },
		lore = "* For loosening nuts. And tightening grudges." },
	{ id = "PistonFists", name = "Piston Fists", slot = "Weapon", rarity = "Epic", level = 83, floor = 5, set = "Turbocharged",
		stats = { Damage = { 42, 58 }, Crit = { 7, 11 } }, tint = { RGB(139, 155, 180), RGB(254, 174, 52) },
		lore = "* Pump. Pump. PUNCH." },
	{ id = "NitroVest", name = "Nitro Vest", slot = "Chest", rarity = "Epic", level = 83, floor = 5, set = "Turbocharged",
		stats = { Health = { 105, 145 }, Defense = { 11, 15 } }, tint = { RGB(44, 232, 245), RGB(0, 153, 219) },
		lore = "* Do not light. Do not shake. Definitely do not do both." },
	{ id = "CheckeredVisor", name = "Checkered Visor", slot = "Helmet", rarity = "Legendary", level = 86, floor = 5, set = "Turbocharged",
		stats = { Damage = { 20, 28 }, Health = { 80, 110 }, Crit = { 8, 11 } }, tint = { RGB(255, 255, 255), RGB(24, 20, 37) },
		lore = "* The finish line is always in sight." },
	{ id = "BurnoutBoots", name = "Burnout Boots", slot = "Boots", rarity = "Legendary", level = 86, floor = 5, set = "Turbocharged",
		stats = { Health = { 64, 90 }, Defense = { 10, 13 }, Power = { 14, 20 } }, tint = { RGB(247, 118, 34), RGB(24, 20, 37) },
		lore = "* Leave a trail of fire. Politely." },
	{ id = "GoldenPiston", name = "The Golden Piston", slot = "Weapon", rarity = "Mythic", level = 89, floor = 5,
		stats = { Damage = { 84, 116 }, Crit = { 15, 20 }, Defense = { 8, 11 } }, tint = { RGB(254, 174, 52), RGB(254, 231, 97) },
		lore = "* The trophy every racer dreams of. It also punches." },
	{ id = "KaVroomEngine", name = "The Ka-VROOM Engine", slot = "Chest", rarity = "Secret", level = 93, floor = 5,
		stats = { Damage = { 92, 126 }, Crit = { 19, 23 }, Health = { 160, 230 }, Power = { 24, 34 } }, tint = { RGB(228, 59, 68), RGB(254, 231, 97) },
		lore = "* vr#om. vr0om. it st*ll w@nts t0 r#ce." },

	-- GRIDLOCK, the Final Beat (floor 6)
	{ id = "NeonSneakers", name = "Neon Sneakers", slot = "Boots", rarity = "Common", level = 90, floor = 6, set = "Beatbound",
		stats = { Health = { 38, 56 } }, tint = { RGB(44, 232, 245), RGB(24, 20, 37) },
		lore = "* They light up with every step. Mostly on the beat." },
	{ id = "PixelVisor", name = "Pixel Visor", slot = "Helmet", rarity = "Uncommon", level = 92, floor = 6, set = "Beatbound",
		stats = { Health = { 54, 74 }, Defense = { 7, 9 } }, tint = { RGB(181, 80, 136), RGB(44, 232, 245) },
		lore = "* Shows you the world in 32 colours. Which is plenty." },
	{ id = "GridJacket", name = "Grid Jacket", slot = "Chest", rarity = "Rare", level = 95, floor = 6, set = "Beatbound",
		stats = { Health = { 94, 130 }, Defense = { 10, 13 } }, tint = { RGB(104, 56, 108), RGB(44, 232, 245) },
		lore = "* Every square is a different shade of purple. Collect them all." },
	{ id = "SpikeKnuckles", name = "Spike Knuckles", slot = "Weapon", rarity = "Rare", level = 95, floor = 6, set = "Beatbound",
		stats = { Damage = { 30, 46 }, Crit = { 5, 8 } }, tint = { RGB(24, 20, 37), RGB(255, 0, 68) },
		lore = "* The one thing in the level that's on YOUR side." },
	{ id = "PortalGauntlets", name = "Portal Gauntlets", slot = "Weapon", rarity = "Epic", level = 98, floor = 6, set = "DemonGeometry",
		stats = { Damage = { 48, 66 }, Crit = { 8, 12 } }, tint = { RGB(247, 118, 34), RGB(44, 232, 245) },
		lore = "* Punch in one side. Knock them out the other." },
	{ id = "GravityBoots", name = "Gravity Boots", slot = "Boots", rarity = "Epic", level = 98, floor = 6, set = "DemonGeometry",
		stats = { Health = { 70, 98 }, Defense = { 11, 15 } }, tint = { RGB(0, 153, 219), RGB(254, 231, 97) },
		lore = "* Which way is down? These know. Usually." },
	{ id = "DemonCubeHelm", name = "Demon Cube Helm", slot = "Helmet", rarity = "Legendary", level = 101, floor = 6, set = "DemonGeometry",
		stats = { Damage = { 24, 32 }, Health = { 92, 126 }, Crit = { 9, 12 } }, tint = { RGB(24, 20, 37), RGB(255, 0, 68) },
		lore = "* Grin. Keep grinning. Never stop grinning." },
	{ id = "DropArmor", name = "Drop Armor", slot = "Chest", rarity = "Legendary", level = 101, floor = 6, set = "DemonGeometry",
		stats = { Health = { 130, 176 }, Defense = { 13, 17 }, Power = { 16, 22 } }, tint = { RGB(255, 0, 68), RGB(104, 56, 108) },
		lore = "* Built for the moment the bass hits." },
	{ id = "FinalBeat", name = "The Final Beat", slot = "Weapon", rarity = "Mythic", level = 104, floor = 6,
		stats = { Damage = { 96, 130 }, Crit = { 17, 22 }, Defense = { 9, 12 } }, tint = { RGB(255, 0, 68), RGB(254, 231, 97) },
		lore = "* One hundred percent. Level complete." },
	{ id = "SecretCoin", name = "The Secret Coin", slot = "Helmet", rarity = "Secret", level = 108, floor = 6,
		stats = { Damage = { 104, 140 }, Crit = { 20, 25 }, Health = { 180, 250 }, Power = { 26, 36 } }, tint = { RGB(254, 174, 52), RGB(255, 255, 255) },
		lore = "* y0u f#und it. n0b*dy f#nds it. h0w d#d y0u f*nd it." },
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

-- The treasure chests: one per boss, named for it (and Oozlet's, from the intro)
Items.ChestNames = { [0] = "Oozlet's Chest" }
function Items.chestName(floor)
	if Items.ChestNames[floor] then
		return Items.ChestNames[floor]
	end
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
