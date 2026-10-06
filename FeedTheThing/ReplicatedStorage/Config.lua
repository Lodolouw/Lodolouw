--[[
	Config  (ModuleScript, parent: ReplicatedStorage, name: "Config")

	Every number you would want to tune lives here. The server and the client
	both read this file, so the food bar, the HUD and the server's checks
	always agree.
]]

local Config = {}

----------------------------------------------------------------------
-- General
----------------------------------------------------------------------
Config.GameName = "Feed the Thing in the Basement"
Config.DataStoreName = "FeedTheThing_v2" -- change the _v2 to start everyone fresh (v2: the simple loop)
Config.AutosaveEvery = 60 -- seconds
Config.Font = Enum.Font.FredokaOne
-- Images for the GUI (upload.bat fills these in; 0 = not uploaded yet)
Config.GuiImages = {
	StudsImage = 0, -- GUI/studs.png: the studs on menus and buttons...
	StudsDecal = 0, -- ...or this, if Roblox only took it as a Decal
}

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
-- The whole game: buy a food, feed it to the Thing, it burps out an egg,
-- the egg hatches into a Thinglet that earns coins. Better food = better
-- odds of a rare Thinglet. Then do it again.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Foods, cheapest first (the food bar shows them in this order).
--   price    = coins for one (Tomato is free, so you can always play)
--   egg      = seconds its egg takes to hatch
--   growth   = how much it grows the Thing
--   odds     = the chance of each rarity. Any food can hatch any rarity;
--              better food has better odds. (Must add up to 1.)
--   secret   = the chance of the secret Thinglet instead
--   thinglet = the Thinglet it leans towards, when it rolls that rarity
----------------------------------------------------------------------
Config.Crops = {
	{
		id = "Tomato", name = "Tomato", price = 0, egg = 6, growth = 1, secret = 0.00001,
		odds = { Common = 0.927, Rare = 0.07, Epic = 0.0028, Legendary = 0.0002 },
		thinglet = "Blorp", color = Color3.fromRGB(235, 60, 55),
	},
	{
		id = "Chili", name = "Chili", price = 50, egg = 8, growth = 3, secret = 0.00003,
		odds = { Common = 0.81, Rare = 0.177, Epic = 0.0124, Legendary = 0.0006 },
		thinglet = "Sizzle", color = Color3.fromRGB(220, 35, 35),
	},
	{
		id = "Eyeberry", name = "Eyeberry", price = 1000, egg = 12, growth = 10, secret = 0.0001,
		odds = { Common = 0.63, Rare = 0.328, Epic = 0.04, Legendary = 0.002 },
		thinglet = "Peeper", color = Color3.fromRGB(70, 95, 230),
	},
	{
		id = "Glowshroom", name = "Glowshroom", price = 15000, egg = 18, growth = 30, secret = 0.0003,
		odds = { Common = 0.42, Rare = 0.45, Epic = 0.12, Legendary = 0.01 },
		thinglet = "Glumcap", color = Color3.fromRGB(60, 220, 210),
	},
	{
		id = "Pumpkin", name = "Pumpkin", price = 200000, egg = 25, growth = 100, secret = 0.0008,
		odds = { Common = 0.22, Rare = 0.49, Epic = 0.25, Legendary = 0.04 },
		thinglet = "Gourdo", color = Color3.fromRGB(255, 140, 30),
	},
	{
		id = "MoonMelon", name = "Moon Melon", price = 2500000, egg = 35, growth = 300, secret = 0.002,
		odds = { Common = 0.08, Rare = 0.37, Epic = 0.40, Legendary = 0.15 },
		thinglet = "Moonmoth", color = Color3.fromRGB(200, 245, 190),
	},
}
-- the rarities, commonest first (luck moves chances along this list:
-- see Rules.hatchOdds)
Config.RarityOrder = { "Common", "Rare", "Epic", "Legendary" }

----------------------------------------------------------------------
-- Thinglets (the creatures)
--   cps    = coins per second when fully grown (mutations multiply it)
--   grow   = seconds from hatching to fully grown (real time, also offline)
--   height = studs tall when fully grown (an avatar is about 5)
----------------------------------------------------------------------
Config.Thinglets = {
	Blorp = { name = "Blorp", rarity = "Common", cps = 1, grow = 120, height = 6 },
	Sizzle = { name = "Sizzle", rarity = "Common", cps = 2, grow = 180, height = 6 },
	Peeper = { name = "Peeper", rarity = "Rare", cps = 5, grow = 600, height = 8 },
	Glumcap = { name = "Glumcap", rarity = "Rare", cps = 8, grow = 900, height = 8 },
	Gourdo = { name = "Gourdo", rarity = "Epic", cps = 25, grow = 1800, height = 11 },
	Mishmash = { name = "Mishmash", rarity = "Epic", cps = 40, grow = 2700, height = 11 },
	Moonmoth = { name = "Moonmoth", rarity = "Legendary", cps = 150, grow = 7200, height = 14 },
	LilThing = { name = "Lil' Thing", rarity = "Legendary", cps = 600, grow = 10800, height = 14, secret = true },
}
-- the order of the dex
Config.ThingletOrder = { "Blorp", "Sizzle", "Peeper", "Glumcap", "Gourdo", "Mishmash", "Moonmoth", "LilThing" }
Config.HatchlingHeight = 1.5 -- studs tall at the moment it hatches
Config.SecretThinglet = "LilThing"
Config.FavouriteChance = 0.6 -- when a food rolls its Thinglet's rarity, how often it's that Thinglet

----------------------------------------------------------------------
-- Mutations: a rare extra look on a hatch, worth more coins.
--   base = the chance on every hatch (luck and weather raise it)
----------------------------------------------------------------------
Config.Mutations = {
	{ id = "Frozen", name = "Frozen", mult = 2, base = 0.04, color = Color3.fromRGB(150, 220, 255), letter = "F" },
	{ id = "Glowing", name = "Glowing", mult = 3, base = 0.02, color = Color3.fromRGB(120, 255, 175), letter = "L" },
	{ id = "Gold", name = "Gold", mult = 5, base = 0.005, color = Color3.fromRGB(255, 205, 60), letter = "G" },
}

----------------------------------------------------------------------
-- The Thing. It grows as it eats (every food adds its `growth`).
--   growth     = total needed to reach this size
--   luck       = extra luck at this size (better odds, see Rules.hatchOdds)
--   hatchStart = how grown a new Thinglet starts (share of size and income)
--   hole       = how wide the hatch is (studs)
----------------------------------------------------------------------
Config.Thing = {
	Sizes = {
		{ name = "Lurker", growth = 0, luck = 0, hatchStart = 0.25, hole = 6, arms = 1 },
		{ name = "Muncher", growth = 100, luck = 0.1, hatchStart = 0.30, hole = 8, arms = 2,
			grew = "It grew a second arm! +10% luck" },
		{ name = "Gobbler", growth = 2000, luck = 0.2, hatchStart = 0.35, hole = 10, arms = 2, teeth = true,
			grew = "It grew teeth! +20% luck" },
		{ name = "Glutton", growth = 25000, luck = 0.35, hatchStart = 0.45, hole = 12, arms = 4, teeth = true, horns = true,
			grew = "It grew horns! +35% luck" },
		{ name = "Colossus", growth = 250000, luck = 0.5, hatchStart = 0.60, hole = 14, arms = 4, teeth = true, horns = true, cracks = true,
			grew = "The ground is cracking! +50% luck" },
	},
	EyeColor = Color3.fromRGB(215, 255, 90),
	SkinColor = Color3.fromRGB(70, 35, 95), -- the arms
	PitColor = Color3.fromRGB(14, 8, 22),
}

----------------------------------------------------------------------
-- Feeding
----------------------------------------------------------------------
Config.Feed = {
	Range = 34, -- studs from your hatch to feed it
	FlightTime = 0.35, -- the food's flight into the hatch
	MinInterval = 0.2, -- seconds between feeds (server check)
}

----------------------------------------------------------------------
-- Eggs: they sit on nests in your yard and hatch by themselves
----------------------------------------------------------------------
Config.Eggs = {
	StartNests = 3, -- more with the Nests upgrade
	-- where the nests are: in the planter boxes beside the hatch (plot-local,
	-- the first of World.PlantSpots), so you see them while you feed
	NestSpots = {
		Vector3.new(-13, 0, 16), Vector3.new(13, 0, 16), Vector3.new(-13, 0, 26),
		Vector3.new(13, 0, 26), Vector3.new(-21, 0, 16), Vector3.new(21, 0, 16),
	},
	Size = 2.4, -- studs tall on the nest
	BigReveal = 3, -- from this rarity rank up (Epic), a hatch gets the big reveal
	FirstEgg = 3, -- your very first egg hatches in 3 seconds
}

----------------------------------------------------------------------
-- Yard: where Thinglets live and earn. When it's full, a better new
-- Thinglet takes the weakest one's place (the weaker one is sold).
----------------------------------------------------------------------
Config.Yard = {
	StartCap = 8,
	MaxCap = 16,
	Prices = {
		[9] = 500, [10] = 2500, [11] = 10000, [12] = 40000,
		[13] = 150000, [14] = 600000, [15] = 2500000, [16] = 10000000,
	},
	SellSeconds = 10, -- a Thinglet sells for this many seconds of its full income
	ConfirmRank = 2, -- selling one this rare (or rarer) by hand asks "are you sure?"
}

----------------------------------------------------------------------
-- Upgrades (the Upgrades menu, incremental style). Every upgrade has
-- levels and each level costs more than the last:
--   cost = base * growth ^ level   (rounded to 2 digits)
-- Yard space uses the price list above instead.
--   per = what one level adds (see Rules.upgradeValue for each one)
-- Everything is bought with coins. Nothing here is for Robux.
----------------------------------------------------------------------
Config.Upgrades = {
	{ id = "yard", name = "Yard space", desc = "Room for more Thinglets", icon = "house" },
	{ id = "nests", name = "Nests", desc = "Hatch more eggs at once", icon = "egg", max = 3, base = 500, growth = 10, per = 1 },
	{ id = "luck", name = "Lucky Thing", desc = "Better odds for rare Thinglets", icon = "clover", max = 20, base = 200, growth = 1.8, per = 0.05 },
	{ id = "income", name = "Comfy yard", desc = "Your Thinglets earn more", icon = "coin", max = 25, base = 300, growth = 1.6, per = 0.1 },
	{ id = "speed", name = "Quick eggs", desc = "Eggs hatch faster", icon = "clock", max = 10, base = 250, growth = 2, per = 0.1 },
}

----------------------------------------------------------------------
-- Weather (server-wide): while it lasts, one mutation is more likely
----------------------------------------------------------------------
Config.Weather = {
	Every = 720, -- a cycle is 12 minutes...
	Duration = 180, -- ...and the last 3 of them have weather
	Types = {
		{ id = "Snow", name = "Snow", mutation = "Frozen", boost = 3,
			banner = "SNOW! Frozen Thinglets are 3x as likely." },
		{ id = "FullMoon", name = "Full Moon", mutation = "Glowing", boost = 3,
			banner = "FULL MOON! Glowing Thinglets are 3x as likely." },
	},
}

----------------------------------------------------------------------
-- Offline, friends
----------------------------------------------------------------------
Config.Offline = {
	MaxSeconds = 7200, -- Thinglets earn up to 2 hours while you're away
	ShowAfter = 60, -- only show "Welcome back" after at least this long away
}
Config.Friends = {
	PerFriend = 0.10, -- +10% coins for every friend in the server
	Max = 0.30,
}

----------------------------------------------------------------------
-- The world: a stud-style neighbourhood. One street runs down the middle
-- (along X) with 4 plots on each side, every plot facing the road.
-- Plot-local positions: X = left/right, Z = towards the house (+) or
-- towards the road (-).
----------------------------------------------------------------------
Config.World = {
	Plots = 8,
	PlotsPerSide = 4,
	PlotSpacing = 80, -- plot centre to plot centre along the street
	-- which plot is which: { side (1 = north, -1 = south), column 1-4 }.
	-- The first players get the middle of the street, across from each other.
	PlotOrder = {
		{ 1, 2 }, { -1, 2 }, { 1, 3 }, { -1, 3 },
		{ 1, 1 }, { -1, 1 }, { 1, 4 }, { -1, 4 },
	},
	RoadWidth = 24,
	SidewalkWidth = 6,
	FrontYard = 2, -- grass between the sidewalk and the plot
	RoadPastPlots = 10, -- the road runs this far past the last plots...
	PlazaLength = 50, -- ...then a plaza at each end, and a tunnel into the wall at each end
	PlazaHalfWidth = 40,
	BackYard = 15, -- room behind the plots, before the wall
	WallHeight = 24,
	TunnelRadius = 13, -- the tunnels the delivery truck uses (half as wide as the opening)
	StandZ = -28, -- the (old) seed stand stands beside the west tunnel, on the south side
	-- The map itself is a model made in Blender (FeedTheThing/Blender). These
	-- numbers must match build_map.py; the game adds invisible floors and
	-- walls to match it.

	PlotWidth = 70,
	PlotDepth = 100,
	PitSize = 14, -- the hole under the hatch (big enough for size 5)
	PitDepth = 9,
	Hatch = Vector3.new(0, 0, 21),
	Spawn = Vector3.new(0, 0, 9),
	House = Vector3.new(0, 0, 42),
	-- the planter boxes beside the hatch (in the Blender map). The nests sit
	-- in the first ones (Config.Eggs.NestSpots); the rest just hold dirt.
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
	-- bright, toy-like colours (the stud look)
	HouseColors = {
		Color3.fromRGB(255, 120, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 200, 70),
		Color3.fromRGB(120, 210, 120), Color3.fromRGB(190, 130, 255), Color3.fromRGB(255, 150, 70),
		Color3.fromRGB(80, 210, 200), Color3.fromRGB(255, 140, 200),
	},
	RoofColors = {
		Color3.fromRGB(170, 40, 50), Color3.fromRGB(30, 80, 170), Color3.fromRGB(190, 110, 30),
		Color3.fromRGB(40, 120, 60), Color3.fromRGB(100, 50, 160), Color3.fromRGB(170, 70, 30),
		Color3.fromRGB(20, 110, 110), Color3.fromRGB(170, 50, 120),
	},
	Grass = Color3.fromRGB(110, 205, 45), -- the street's grass
	Lawn = Color3.fromRGB(135, 225, 55), -- your plot (a little brighter)
	Dirt = Color3.fromRGB(125, 80, 45),
	Road = Color3.fromRGB(70, 72, 82),
	RoadLine = Color3.fromRGB(255, 210, 50),
	Sidewalk = Color3.fromRGB(205, 205, 210),
	Fence = Color3.fromRGB(175, 95, 45),
	FencePost = Color3.fromRGB(80, 55, 50),
	WallA = Color3.fromRGB(225, 160, 95), -- the checkered wall round the map
	WallB = Color3.fromRGB(200, 135, 75),
	WallTop = Color3.fromRGB(90, 210, 40),
	Studs = true, -- studs on top of the ground, roofs and walls (the stud look)
}

----------------------------------------------------------------------
-- Uploaded assets. Tools/upload_assets.py fills in the ids (it runs by
-- itself on GitHub after every push, see the README). 0 = not uploaded yet.
--   Sounds: made by Sounds/make_sounds.py and played from one sound sheet
--   (see SoundSheet.lua). Here you set each one's volume. To swap one for
--   another sound, put that sound's id here (or a Sound with the same name
--   in SoundService).
--   Map / Props: the Blender models; the game loads them by itself, so you
--   don't need to import them into Studio.
----------------------------------------------------------------------
Config.Sounds = {
	Click = { id = 0, volume = 0.35 },
	Pop = { id = 0, volume = 0.5 },
	Coin = { id = 0, volume = 0.5 },
	Chomp = { id = 0, volume = 0.7 },
	Throw = { id = 0, volume = 0.45 },
	Perfect = { id = 0, volume = 0.6 },
	Combo = { id = 0, volume = 0.5 },
	Crack = { id = 0, volume = 0.6 },
	Hatch = { id = 0, volume = 0.6 },
	HatchRare = { id = 0, volume = 0.7 },
	SizeUp = { id = 0, volume = 0.7 },
	Buy = { id = 0, volume = 0.55 },
	Burp = { id = 0, volume = 0.6 },
	Error = { id = 0, volume = 0.3 },
	Announce = { id = 0, volume = 0.45 },
	Honk = { id = 0, volume = 0.35 },
	Thud = { id = 0, volume = 0.7 },
	Poof = { id = 0, volume = 0.55 },
}
Config.AssetIds = {
	Map = 0, -- Blender/Export/FeedTheThing_Map.fbx
	Props = 0, -- Blender/Export/FeedTheThing_Props.fbx
}

----------------------------------------------------------------------
-- The coin truck: every couple of minutes a truck comes out of the tunnel
-- at the west end, drives down the street, stops at someone's plot and
-- lobs a package onto their lawn, then drives off into the tunnel at the
-- east end (under the FEED THE THING sign). The package bursts into coins.
----------------------------------------------------------------------
Config.Delivery = {
	Every = 120, -- seconds between trucks (each one picks a random player)
	TipSeconds = 15, -- the package holds this many seconds of that player's income...
	MinTip = 25, -- ...and never less than this
	StartX = -232, -- sets off inside the west tunnel...
	EndX = 232, -- ...and is gone inside the east tunnel (the walls are at x = +-215)
	Fade = 22, -- studs over which it fades in and out of the tunnels' darkness
	Lane = 6, -- how far from the road's middle it drives (on your side)
	Speed = 75, -- average studs per second on the way to you (it cruises, then brakes hard)
	Brake = 0.5, -- seconds stopped before the throw
	Throw = 1.1, -- seconds the package flies
	Open = 1.0, -- bounce, then it bursts into coins
	Leave = 0.5, -- seconds after the throw before it pulls away
	PullAway = 60, -- how fast it speeds up as it leaves (studs per second, per second)
	LeaveSpeed = 50, -- top speed leaving (slow enough to watch it vanish into the tunnel)
	LandAt = Vector3.new(0, 0, -36), -- where the package lands (plot-local, the front lawn)
}

return Config
