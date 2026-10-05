--[[
	Config  (ModuleScript, parent: ReplicatedStorage, name: "Config")

	Every number you would want to tune lives here. The server and the client
	both read this file, so the shop, the HUD and the server's checks always
	agree. The economy numbers come from the simulation in
	Docs/FeedTheThing/economy_sim.py - change them there first, rerun it, then
	copy them here.
]]

local Config = {}

----------------------------------------------------------------------
-- General
----------------------------------------------------------------------
Config.GameName = "Feed the Thing in the Basement"
Config.DataStoreName = "FeedTheThing_v1" -- change the _v1 to start everyone fresh
Config.AutosaveEvery = 60 -- seconds
Config.Font = Enum.Font.FredokaOne

----------------------------------------------------------------------
-- Rarities (rank is used for ties, sorting and "are you sure?" prompts)
----------------------------------------------------------------------
Config.Rarities = {
	Common = { rank = 1, color = Color3.fromRGB(205, 215, 225) },
	Rare = { rank = 2, color = Color3.fromRGB(80, 175, 255) },
	Epic = { rank = 3, color = Color3.fromRGB(195, 100, 255) },
	Legendary = { rank = 4, color = Color3.fromRGB(255, 195, 45) },
}

----------------------------------------------------------------------
-- Crops, cheapest first. The order IS the rarity order: on a tie in the
-- belly, the food further down this list wins.
--   seed   = price of the seed (the plant is permanent)
--   regrow = seconds per fruit (a plant holds up to Garden.FruitCap)
--   coins  = coins for one toss (before multipliers); also how much it
--            grows the Thing
--   stock  = chance a restock has it, and how many (min, max)
--   thinglet = what a belly full of mostly this food hatches
----------------------------------------------------------------------
Config.Crops = {
	{
		id = "Tomato", name = "Tomato", rarity = "Common",
		seed = 10, regrow = 15, coins = 3,
		stockChance = 1, stockMin = 0, stockMax = 0, -- always in stock
		thinglet = "Blorp",
		color = Color3.fromRGB(235, 60, 55),
	},
	{
		id = "Chili", name = "Chili", rarity = "Common",
		seed = 50, regrow = 20, coins = 8,
		stockChance = 1, stockMin = 0, stockMax = 0,
		thinglet = "Sizzle",
		color = Color3.fromRGB(220, 35, 35),
	},
	{
		id = "Eyeberry", name = "Eyeberry", rarity = "Rare",
		seed = 750, regrow = 45, coins = 30,
		stockChance = 0.8, stockMin = 1, stockMax = 3,
		thinglet = "Peeper",
		color = Color3.fromRGB(70, 95, 230),
	},
	{
		id = "Glowshroom", name = "Glowshroom", rarity = "Rare",
		seed = 7500, regrow = 75, coins = 100,
		stockChance = 0.6, stockMin = 1, stockMax = 2,
		thinglet = "Glumcap",
		color = Color3.fromRGB(60, 220, 210),
	},
	{
		id = "Pumpkin", name = "Pumpkin", rarity = "Epic",
		seed = 100000, regrow = 100, coins = 400,
		stockChance = 0.4, stockMin = 1, stockMax = 1,
		thinglet = "Gourdo",
		color = Color3.fromRGB(255, 140, 30),
	},
	{
		id = "MoonMelon", name = "Moon Melon", rarity = "Legendary",
		seed = 1000000, regrow = 180, coins = 2000,
		stockChance = 0.2, stockMin = 1, stockMax = 1,
		thinglet = "Moonmoth",
		color = Color3.fromRGB(200, 245, 190),
	},
}

----------------------------------------------------------------------
-- Thinglets (the creatures)
--   cps    = coins per second when fully grown (mutations multiply it)
--   grow   = seconds from hatching to fully grown (real time, also offline)
--   height = studs tall when fully grown (an avatar is about 5)
----------------------------------------------------------------------
Config.Thinglets = {
	Blorp = { name = "Blorp", rarity = "Common", cps = 1, grow = 120, height = 6,
		hint = "It loves red and juicy..." },
	Sizzle = { name = "Sizzle", rarity = "Common", cps = 3, grow = 180, height = 6,
		hint = "Something spicy..." },
	Peeper = { name = "Peeper", rarity = "Rare", cps = 10, grow = 600, height = 8,
		hint = "Food that looks back..." },
	Glumcap = { name = "Glumcap", rarity = "Rare", cps = 30, grow = 900, height = 8,
		hint = "Something from the dark..." },
	Gourdo = { name = "Gourdo", rarity = "Epic", cps = 100, grow = 1800, height = 11,
		hint = "Something big and orange..." },
	Mishmash = { name = "Mishmash", rarity = "Epic", cps = 175, grow = 2700, height = 11,
		hint = "A bit of everything. 5 different!" },
	Moonmoth = { name = "Moonmoth", rarity = "Legendary", cps = 500, grow = 7200, height = 14,
		hint = "Fruit from the moon..." },
	LilThing = { name = "Lil' Thing", rarity = "Legendary", cps = 1000, grow = 10800, height = 14,
		hint = "Only Moon Melons. Only perfect throws." },
}
-- the order of the dex
Config.ThingletOrder = { "Blorp", "Sizzle", "Peeper", "Glumcap", "Gourdo", "Mishmash", "Moonmoth", "LilThing" }
Config.HatchlingHeight = 1.5 -- studs tall at the moment it hatches (at size 1)

-- The two special hatch rules (checked before "most food wins")
Config.SecretThinglet = "LilThing" -- a full belly of SecretFood, every toss PERFECT
Config.SecretFood = "MoonMelon"
Config.MishmashThinglet = "Mishmash" -- this many different foods in one belly
Config.MishmashKinds = 5

----------------------------------------------------------------------
-- Mutations (one per Thinglet; mutated food also pays more per toss)
--   base = chance on every egg; each mutated food of the same kind in the
--   belly adds MutatedFoodBonus, each PERFECT toss adds PerfectBonus to all,
--   each Thing size above 1 adds SizeLuckBonus to all.
----------------------------------------------------------------------
Config.Mutations = {
	{ id = "Frozen", name = "Frozen", mult = 2, base = 0.05, color = Color3.fromRGB(150, 220, 255), letter = "F" },
	{ id = "Glowing", name = "Glowing", mult = 3, base = 0.03, color = Color3.fromRGB(120, 255, 175), letter = "L" },
	{ id = "Gold", name = "Gold", mult = 5, base = 0.01, color = Color3.fromRGB(255, 205, 60), letter = "G" },
}
Config.MutatedFoodBonus = 0.08
Config.PerfectBonus = 0.01
Config.SizeLuckBonus = 0.01

----------------------------------------------------------------------
-- The Thing. It grows by eating: every toss adds the food's `coins` value.
--   growth    = total needed to reach this size
--   belly     = slots in the belly
--   coinMult  = multiplies toss coins
--   hatchStart= how grown a new Thinglet starts (share of size and income)
--   hole      = how wide the hatch is (studs)
----------------------------------------------------------------------
Config.Thing = {
	Sizes = {
		{ name = "Lurker", growth = 0, belly = 3, coinMult = 1, hatchStart = 0.25, hole = 6, arms = 1 },
		{ name = "Muncher", growth = 100, belly = 5, coinMult = 1.25, hatchStart = 0.30, hole = 8, arms = 2,
			grew = "It grew a second arm!" },
		{ name = "Gobbler", growth = 3000, belly = 5, coinMult = 1.5, hatchStart = 0.35, hole = 10, arms = 2, teeth = true,
			grew = "It grew teeth!" },
		{ name = "Glutton", growth = 50000, belly = 5, coinMult = 2, hatchStart = 0.45, hole = 12, arms = 4, teeth = true, horns = true,
			grew = "It grew horns!" },
		{ name = "Colossus", growth = 800000, belly = 5, coinMult = 3, hatchStart = 0.60, hole = 14, arms = 4, teeth = true, horns = true, cracks = true,
			grew = "The ground is cracking!" },
	},
	EyeColor = Color3.fromRGB(215, 255, 90),
	SkinColor = Color3.fromRGB(70, 35, 95), -- the arms
	PitColor = Color3.fromRGB(14, 8, 22),
}

----------------------------------------------------------------------
-- The toss
----------------------------------------------------------------------
Config.Toss = {
	Range = 34, -- studs from your hatch to toss
	RingCycle = 1.2, -- seconds for the ring to shrink and grow back
	PerfectWindow = 0.30, -- share of the cycle that counts as PERFECT
	FlightTime = 0.35,
	MinInterval = 0.12, -- seconds between tosses (server check; the client waits 0.22)
	CravingMult = 3,
	Combo = { 1, 2, 3, 5 }, -- 1st, 2nd, 3rd, 4th+ craving hit in a row
	ComboTimeout = 6, -- seconds without a toss before the combo drops back
	MaxClockSkew = 1.5, -- how old a toss's release time may be
}

----------------------------------------------------------------------
-- Garden
----------------------------------------------------------------------
Config.Garden = {
	StartPlots = 4,
	MaxPlots = 10,
	FruitCap = 3, -- ripe fruit a plant holds (also caps offline growth)
	HarvestRange = 16, -- walk this close to a plant and its fruit jumps into your basket
	PlotPrices = { [5] = 150, [6] = 1000, [7] = 5000, [8] = 25000, [9] = 150000, [10] = 750000 },
	-- what a brand new player starts with (fruit already ripe)
	StartPlants = { { crop = "Tomato", ripe = 2 }, { crop = "Tomato", ripe = 1 } },
}

----------------------------------------------------------------------
-- Yard
----------------------------------------------------------------------
Config.Yard = {
	StartCap = 8,
	MaxCap = 16,
	Prices = { [9] = 2000, [10] = 8000, [11] = 30000, [12] = 100000, [13] = 300000, [14] = 1000000, [15] = 3000000, [16] = 10000000 },
	SellSeconds = 30, -- a Thinglet sells for this many seconds of its full income
	ConfirmRank = 3, -- Epic and up ask "are you sure?" before selling
}

----------------------------------------------------------------------
-- Seed shop. Restocks on one server-wide timer; every player has their own
-- stock. The SecretFood (Moon Melon) is always in stock at the top of each hour.
----------------------------------------------------------------------
Config.Shop = {
	RestockEvery = 300,
	MoonGuaranteeEvery = 12, -- restocks (12 x 5 min = every hour, on the hour)
}

----------------------------------------------------------------------
-- Weather (server-wide; fruit that ripens during it may mutate)
----------------------------------------------------------------------
Config.Weather = {
	Every = 720, -- a cycle is 12 minutes...
	Duration = 180, -- ...and the last 3 of them have weather
	Types = {
		{ id = "Snow", name = "Snow", mutation = "Frozen", chance = 0.2,
			banner = "SNOW! Crops that ripen now may freeze." },
		{ id = "FullMoon", name = "Full Moon", mutation = "Glowing", chance = 0.2,
			banner = "FULL MOON! Crops that ripen now may glow." },
	},
	GoldChance = 0.01, -- any time, online
}

----------------------------------------------------------------------
-- Offline, daily craving, friends
----------------------------------------------------------------------
Config.Offline = {
	MaxSeconds = 3600, -- Thinglets earn up to this much while you're away
	ShowAfter = 60, -- only show "Welcome back" after at least this long away
}
Config.Daily = {
	Need = 10, -- feed this many of today's food...
	Odds = { Frozen = 0.6, Glowing = 0.3, Gold = 0.1 }, -- ...for an egg that is always mutated
}
Config.Friends = {
	PerFriend = 0.10, -- +10% coins for every friend in the server
	Max = 0.30,
}

----------------------------------------------------------------------
-- The world. Plots stand in a ring round a plaza. Plot-local positions:
-- X = left/right, Z = towards the house (+) or towards the plaza (-).
----------------------------------------------------------------------
Config.World = {
	Plots = 8,
	RingRadius = 140, -- plaza centre to plot centre
	PlazaRadius = 60,
	PlotWidth = 70,
	PlotDepth = 100,
	PitSize = 14, -- the hole under the hatch (big enough for size 5)
	PitDepth = 9,
	Hatch = Vector3.new(0, 0, 21),
	Spawn = Vector3.new(0, 0, 9),
	House = Vector3.new(0, 0, 42),
	-- garden spots, in the order they're used (nearest the hatch first)
	PlantSpots = {
		Vector3.new(-13, 0, 16), Vector3.new(13, 0, 16),
		Vector3.new(-13, 0, 26), Vector3.new(13, 0, 26),
		Vector3.new(-21, 0, 16), Vector3.new(21, 0, 16),
		Vector3.new(-21, 0, 26), Vector3.new(21, 0, 26),
		Vector3.new(-29, 0, 21), Vector3.new(29, 0, 21),
	},
	-- where Thinglets live, 16 spots in a 4 x 4 grid on the front lawn
	YardSlots = {
		Vector3.new(-8, 0, -4), Vector3.new(8, 0, -4), Vector3.new(-24, 0, -4), Vector3.new(24, 0, -4),
		Vector3.new(-8, 0, -16), Vector3.new(8, 0, -16), Vector3.new(-24, 0, -16), Vector3.new(24, 0, -16),
		Vector3.new(-8, 0, -28), Vector3.new(8, 0, -28), Vector3.new(-24, 0, -28), Vector3.new(24, 0, -28),
		Vector3.new(-8, 0, -40), Vector3.new(8, 0, -40), Vector3.new(-24, 0, -40), Vector3.new(24, 0, -40),
	},
	HouseColors = {
		Color3.fromRGB(255, 205, 210), Color3.fromRGB(200, 230, 255), Color3.fromRGB(255, 240, 190),
		Color3.fromRGB(210, 245, 210), Color3.fromRGB(235, 215, 255), Color3.fromRGB(255, 220, 185),
		Color3.fromRGB(200, 245, 240), Color3.fromRGB(245, 245, 245),
	},
	Grass = Color3.fromRGB(110, 200, 90),
	Lawn = Color3.fromRGB(125, 215, 100),
	Dirt = Color3.fromRGB(120, 80, 50),
}

return Config
