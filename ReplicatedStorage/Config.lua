--[[
	Config  (ModuleScript, parent: ReplicatedStorage, name: "Config")

	Every number you would want to tune lives here. The server and the client
	both read this file, so the shops, HUD and validation always agree.
]]

local Config = {}

----------------------------------------------------------------------
-- General
----------------------------------------------------------------------
Config.GameName = "Boss Grow" -- working title, rename freely
Config.BaseHealth = 100
Config.BaseWalkSpeed = 16
Config.BaseCapacity = 20 -- backpack slots before upgrades
Config.RequireProximity = true -- shops only work when you stand near them
Config.StationRange = 34 -- studs
Config.MaxPrestige = 100
Config.TalismanSlots = 3

-- Where the shops stand. Used by the lobby builder AND by server range checks.
Config.Stations = {
	Sell = Vector3.new(-60, 0, -30),
	Upgrades = Vector3.new(60, 0, -30),
	Craft = Vector3.new(0, 0, -62),
	Prestige = Vector3.new(0, 0, 0),
}

----------------------------------------------------------------------
-- Training yard (the "treadmill": practice dummies with multipliers)
----------------------------------------------------------------------
Config.BaseTrainGain = 1 -- the "+1" per hit before any multiplier
Config.TrainClientInterval = 0.18 -- seconds between clicks the client sends
Config.TrainMinInterval = 0.12 -- server rejects hits faster than this
Config.AutoInterval = 1 -- seconds between auto-train hits

-- Combo: keep hitting the same dummy (manually - auto-train doesn't count)
-- without pausing longer than ComboWindow and your Power gain is multiplied.
-- Each tier kicks in once your combo reaches `hits`.
Config.ComboWindow = 1.1 -- seconds you can pause before the combo breaks
Config.ComboTiers = {
	{ hits = 10, mult = 1.1 },
	{ hits = 25, mult = 1.25 },
	{ hits = 50, mult = 1.5 },
	{ hits = 100, mult = 2 },
}

function Config.comboMult(count)
	local mult = 1
	for _, tier in ipairs(Config.ComboTiers) do
		if count >= tier.hits then
			mult = tier.mult
		end
	end
	return mult
end

Config.Yard = {
	CenterZ = 75, -- z position of the first row of pads
	Spacing = 32, -- distance between pad centres
	PadSize = 24, -- pad is PadSize x PadSize studs
	PerRow = 6, -- pads in a row; the next ones start a new row...
	RowGap = 44, -- ...this much further back (south)...
	TierHeight = 5, -- ...and a step up, on a raised stone terrace
}

----------------------------------------------------------------------
-- Levels. Your level IS your Power: it's worked out from your total
-- Power, so it goes up as you train and back down when you prestige
-- (prestige resets Power). Each level needs LevelGrowth times more Power
-- than the one before.
----------------------------------------------------------------------
Config.LevelBase = 20 -- Power needed to go from level 1 to level 2
Config.LevelGrowth = 1.25 -- each next level costs this much more

-- Total Power you need to reach `level`
function Config.powerForLevel(level)
	if level <= 1 then
		return 0
	end
	local g = Config.LevelGrowth
	return math.floor(Config.LevelBase * (g ^ (level - 1) - 1) / (g - 1))
end

-- Your level for a given total Power
function Config.levelFromPower(power)
	power = math.max(power or 0, 0)
	local g = Config.LevelGrowth
	local level = math.floor(math.log(power * (g - 1) / Config.LevelBase + 1) / math.log(g)) + 1
	level = math.max(1, level)
	-- fix any rounding at the exact boundaries
	while Config.powerForLevel(level + 1) <= power do
		level = level + 1
	end
	while level > 1 and Config.powerForLevel(level) > power do
		level = level - 1
	end
	return level
end

-- mult = Power multiplier for this dummy, level = level needed to use it.
-- (req, the Power that level needs, is filled in automatically below.)
Config.Zones = {
	{ id = "Straw", name = "Straw Dummy", mult = 1, level = 1, color = Color3.fromRGB(214, 168, 96) },
	{ id = "Iron", name = "Iron Dummy", mult = 1.5, level = 5, color = Color3.fromRGB(150, 190, 235) },
	{ id = "Frost", name = "Frost Dummy", mult = 3, level = 12, color = Color3.fromRGB(110, 225, 255) },
	{ id = "Ember", name = "Ember Dummy", mult = 5, level = 20, color = Color3.fromRGB(255, 120, 45) },
	{ id = "Void", name = "Void Dummy", mult = 8, level = 30, color = Color3.fromRGB(175, 95, 255) },
	{ id = "Celestial", name = "Celestial Dummy", mult = 10, level = 45, color = Color3.fromRGB(255, 215, 70) },
	-- the upper tier
	{ id = "Ooze", name = "Ooze Dummy", mult = 14, level = 55, color = Color3.fromRGB(120, 255, 90) },
	{ id = "Dune", name = "Dune Dummy", mult = 19, level = 64, color = Color3.fromRGB(240, 196, 120) },
	{ id = "Crystal", name = "Crystal Dummy", mult = 25, level = 73, color = Color3.fromRGB(255, 120, 200) },
	{ id = "Storm", name = "Storm Dummy", mult = 33, level = 82, color = Color3.fromRGB(120, 200, 255) },
	{ id = "Dragon", name = "Dragon Dummy", mult = 44, level = 92, color = Color3.fromRGB(255, 70, 60) },
	{ id = "Cosmic", name = "Cosmic Dummy", mult = 60, level = 105, color = Color3.fromRGB(150, 110, 255) },
}
for _, zone in ipairs(Config.Zones) do
	zone.req = Config.powerForLevel(zone.level)
end

-- World position of the centre of pad number `index` (Y is the ground it
-- stands on: 0 for the first row, TierHeight up for the terrace behind it)
function Config.zonePosition(index)
	local Y = Config.Yard
	local row = math.floor((index - 1) / Y.PerRow)
	local col = (index - 1) % Y.PerRow + 1
	local x = (col - (Y.PerRow + 1) / 2) * Y.Spacing
	return Vector3.new(x, row * Y.TierHeight, Y.CenterZ + row * Y.RowGap)
end

----------------------------------------------------------------------
-- Loot materials (dropped by bosses later, sold or used for crafting)
----------------------------------------------------------------------
Config.Materials = {
	{ id = "Scrap", name = "Scrap Metal", color = Color3.fromRGB(170, 176, 190), sell = 5 },
	{ id = "Shard", name = "Shadow Shard", color = Color3.fromRGB(150, 90, 255), sell = 25 },
	{ id = "Ember", name = "Ember Core", color = Color3.fromRGB(255, 125, 40), sell = 120 },
	{ id = "Void", name = "Void Crystal", color = Color3.fromRGB(60, 220, 255), sell = 600 },
}

----------------------------------------------------------------------
-- Upgrades (bought with coins at the Upgrade Shop)
----------------------------------------------------------------------
Config.Upgrades = {
	{
		id = "Backpack", name = "Bigger Backpack", icon = "🎒", color = Color3.fromRGB(70, 170, 110),
		desc = "+5 backpack slots per level",
		perLevel = 5, maxLevel = 40, baseCost = 100, growth = 1.55,
		effect = function(level) return "+" .. (level * 5) .. " slots" end,
	},
	{
		id = "PowerGain", name = "Training Gloves", icon = "🥊", color = Color3.fromRGB(230, 80, 90),
		desc = "+10% Power per hit per level",
		perLevel = 0.10, maxLevel = 50, baseCost = 150, growth = 1.6,
		effect = function(level) return "+" .. (level * 10) .. "% Power" end,
	},
	{
		id = "SellValue", name = "Silver Tongue", icon = "💰", color = Color3.fromRGB(230, 180, 50),
		desc = "+8% coins from selling per level",
		perLevel = 0.08, maxLevel = 50, baseCost = 200, growth = 1.6,
		effect = function(level) return "+" .. (level * 8) .. "% coins" end,
	},
	{
		id = "WalkSpeed", name = "Swift Boots", icon = "👟", color = Color3.fromRGB(70, 150, 240),
		desc = "+1 walk speed per level",
		-- Raised from 15: at the old cap (16+15=31 studs/sec) it was a bit low
		-- to clearly see the run animation blend in. Cost still grows the
		-- same way per level, so this doesn't make it free - just reachable.
		perLevel = 1, maxLevel = 40, baseCost = 300, growth = 1.7,
		effect = function(level) return "+" .. level .. " speed" end,
	},
}

function Config.upgradeCost(def, level)
	return math.floor(def.baseCost * def.growth ^ level)
end

----------------------------------------------------------------------
-- Talismans (crafted at the workbench, equipped in limited slots)
-- bonus kinds: PowerGain, SellValue, MaxHealth, WalkSpeed, Capacity
----------------------------------------------------------------------
Config.Talismans = {
	{
		id = "Might", name = "Talisman of Might", icon = "💪", color = Color3.fromRGB(230, 80, 90),
		bonus = "PowerGain", value = 0.15, desc = "+15% Power gain",
		cost = { coins = 200, materials = { Scrap = 10 } },
	},
	{
		id = "Fortune", name = "Talisman of Fortune", icon = "🍀", color = Color3.fromRGB(70, 190, 100),
		bonus = "SellValue", value = 0.20, desc = "+20% coins from selling",
		cost = { coins = 400, materials = { Scrap = 15, Shard = 3 } },
	},
	{
		id = "Vigor", name = "Talisman of Vigor", icon = "❤️", color = Color3.fromRGB(240, 100, 140),
		bonus = "MaxHealth", value = 0.25, desc = "+25% max health",
		cost = { coins = 600, materials = { Scrap = 20, Shard = 5 } },
	},
	{
		id = "Haste", name = "Talisman of Haste", icon = "⚡", color = Color3.fromRGB(250, 210, 60),
		bonus = "WalkSpeed", value = 0.10, desc = "+10% walk speed",
		cost = { coins = 800, materials = { Shard = 8 } },
	},
	{
		id = "Greed", name = "Talisman of Greed", icon = "🧿", color = Color3.fromRGB(80, 170, 255),
		bonus = "Capacity", value = 0.25, desc = "+25% backpack space",
		cost = { coins = 1500, materials = { Shard = 10, Ember = 2 } },
	},
	{
		id = "Titan", name = "Titan's Talisman", icon = "👑", color = Color3.fromRGB(255, 190, 50),
		bonus = "PowerGain", value = 0.40, desc = "+40% Power gain",
		cost = { coins = 5000, materials = { Ember = 6, Void = 2 } },
	},
}

----------------------------------------------------------------------
-- Prestige
----------------------------------------------------------------------
function Config.prestigeRequirement(prestige)
	return 50000 * 4 ^ prestige
end

function Config.prestigePowerMult(prestige)
	return 1 + 0.5 * prestige
end

function Config.prestigeCoinMult(prestige)
	return 1 + 0.25 * prestige
end

----------------------------------------------------------------------
-- Lookup tables
----------------------------------------------------------------------
Config.MaterialById = {}
for _, m in ipairs(Config.Materials) do
	Config.MaterialById[m.id] = m
end

Config.UpgradeById = {}
for _, u in ipairs(Config.Upgrades) do
	Config.UpgradeById[u.id] = u
end

Config.TalismanById = {}
for _, t in ipairs(Config.Talismans) do
	Config.TalismanById[t.id] = t
end

----------------------------------------------------------------------
-- Derived stats (shared so the HUD and the server always agree)
----------------------------------------------------------------------
function Config.talismanBonus(data, kind)
	local total = 0
	for id, on in pairs(data.Equipped or {}) do
		local t = Config.TalismanById[id]
		if on and t and t.bonus == kind then
			total = total + t.value
		end
	end
	return total
end

function Config.equippedCount(data)
	local n = 0
	for _, on in pairs(data.Equipped or {}) do
		if on then
			n = n + 1
		end
	end
	return n
end

function Config.lootCount(data)
	local n = 0
	for _, count in pairs(data.Loot or {}) do
		n = n + count
	end
	return n
end

-- How fast a player moves: their full speed in the lobby, capped inside a Spire
-- arena. Every place that sets walk speed asks this, so the two can't disagree.
function Config.walkSpeedFor(player, d)
	local speed = d and Config.stats(d).walkSpeed or Config.BaseWalkSpeed
	if player and player:GetAttribute("SpireFloor") then
		speed = math.min(speed, (Config.Combat and Config.Combat.ArenaWalkSpeed) or speed)
	end
	return speed
end

function Config.stats(d)
	local up = d.Upgrades or {}
	local prestige = d.Prestige or 0
	local U = Config.UpgradeById

	local powerMult = (1 + U.PowerGain.perLevel * (up.PowerGain or 0))
		* (1 + Config.talismanBonus(d, "PowerGain"))
		* Config.prestigePowerMult(prestige)

	local coinMult = (1 + U.SellValue.perLevel * (up.SellValue or 0))
		* (1 + Config.talismanBonus(d, "SellValue"))
		* Config.prestigeCoinMult(prestige)

	local capacity = math.floor(
		(Config.BaseCapacity + U.Backpack.perLevel * (up.Backpack or 0)) * (1 + Config.talismanBonus(d, "Capacity"))
	)

	local walkSpeed = (Config.BaseWalkSpeed + U.WalkSpeed.perLevel * (up.WalkSpeed or 0))
		* (1 + Config.talismanBonus(d, "WalkSpeed"))

	-- your gear (ReplicatedStorage.Items): extra health, and extra training Power
	local gear = { Health = 0, Power = 0 }
	local okItems, Items = pcall(require, game:GetService("ReplicatedStorage"):FindFirstChild("Items"))
	if okItems and type(Items) == "table" then
		gear = Items.gearStats(d)
	end
	powerMult = powerMult * (1 + gear.Power / 100)
	local maxHealth = math.floor(Config.BaseHealth * (1 + Config.talismanBonus(d, "MaxHealth")) + gear.Health)

	return {
		powerMult = powerMult,
		coinMult = coinMult,
		capacity = capacity,
		walkSpeed = walkSpeed,
		maxHealth = maxHealth,
	}
end

----------------------------------------------------------------------
-- Number formatting
----------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Config.format(n)
	n = math.floor(n or 0)
	if n < 1000 then
		return tostring(n)
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do
		v = v / 1000
		i = i + 1
	end
	return tostring(math.floor(v * 100) / 100) .. SUFFIXES[i]
end

-- Small gains keep one decimal so x1.5 hits read nicely
function Config.formatGain(g)
	if g >= 100 then
		return Config.format(g)
	end
	return tostring(math.floor(g * 10 + 0.5) / 10)
end

function Config.formatMult(m)
	return tostring(math.floor(m * 100 + 0.5) / 100)
end

----------------------------------------------------------------------
-- The Spire (boss floors). Only floor 1's arena exists so far; the rest
-- show as locked in the Spire menu.
----------------------------------------------------------------------
Config.Spire = {
	EnterRange = 38, -- how close to the Spire's doors you must be to enter
	-- each floor opens once you've beaten the boss on the floor below it
	-- (in Studio every open floor is free to enter, so you can test them)
	RequirePrevious = true,
	Floors = {
		{
			id = 1,
			boss = "Oozark, the Gelatinous Tyrant",
			area = "Oozark's Hollow",
			level = 15, -- recommended level
			blurb = "A bloated slime king rules the drowned colosseum beneath the Spire. It is slow to anger, and slower to die.",
			color = Color3.fromRGB(120, 230, 90),
			open = true,
		},
		{
			id = 2,
			boss = "Nahrzul, Devourer of the Dunes",
			area = "The Sunken Dunes",
			level = 30,
			blurb = "An arena the desert swallowed whole. Something vast sleeps coiled at its heart - wake it, and it hunts you by sound from under the sand. Stone is silent.",
			color = Color3.fromRGB(236, 186, 98),
			open = true,
			-- how the arena looks and sounds on your screen while you're in it
			-- (ArenaAmbience puts the lobby's look back when you leave)
			ambience = {
				ClockTime = 16.8, -- a low golden sun
				Atmosphere = {
					Density = 0.36,
					Offset = 0.12,
					Color = Color3.fromRGB(240, 202, 148),
					Decay = Color3.fromRGB(204, 132, 76),
					Glare = 0.4,
					Haze = 1.8,
				},
				Tint = Color3.fromRGB(255, 238, 212),
				Saturation = 0.06,
				Contrast = 0.05,
				Sand = Color3.fromRGB(226, 190, 130), -- the blowing sand
				Wind = Vector3.new(1, 0, 0.35), -- the way it blows
				Sound = "Sandstorm", -- a looping wind in SoundService, if you add one
				Volume = 0.3,
				-- THE SANDSTORM. When the fight starts a wall of sand rolls in across
				-- the arena, and while it rages it's like fog: thick blowing dust
				-- that swallows everything past a stone's throw. It dies down again
				-- when the worm does (and blows harder still once its armour cracks).
				Storm = {
					Front = true, -- the wall of sand you see rolling in (false: it just thickens)
					FrontSpeed = 55, -- how fast the wall crosses the arena, studs a second
					-- the air at the storm's height: Density is how thick (0..1) - the
					-- higher, the less you can see. 0.85 is a fog: the worm is clear up
					-- close and gone into the dust half the arena away. (0.6 = a haze.)
					Atmosphere = {
						Density = 0.85,
						Offset = 0.8,
						Color = Color3.fromRGB(198, 154, 102),
						Decay = Color3.fromRGB(150, 100, 60),
						Glare = 0,
						Haze = 6,
					},
					Veil = 0.45, -- dust right in front of your eyes (0 = none, 1 = blinding)
					Tint = Color3.fromRGB(255, 222, 180), -- the light, through the dust
					Brightness = -0.06, -- a little darker while it blows
					Volume = 0.75, -- the wind, at the storm's height
				},
			},
		},
		{ id = 3, boss = "???", area = "???", level = 45, blurb = "Sealed.", color = Color3.fromRGB(230, 110, 90), open = false },
	},
}

-- The bosses of the Spire, by floor. Every number that shapes a fight is here.
--
-- Times are in seconds, distances in studs, damage against a player's 100
-- health. A "tell" is how long an attack winds up before it lands: your dodge
-- roll makes you untouchable for 0.5s, so every tell is longer than that - the
-- fight is hard, but nothing in it is unfair.
-- The acid rain that falls while you fight a boss. Subtle on purpose: raise
-- Rate for a downpour, Tint for a greener world. Drop a looping Sound named
-- "Acid Rain" into SoundService and it plays under the rain.
Config.AcidRain = {
	Color = Color3.fromRGB(150, 255, 110),
	Rate = 900, -- drops a second, in the patch of sky around you
	Splashes = 160, -- little splashes on the floor around you, a second
	Tint = 0.2, -- how green it turns the world (0 = not at all, 1 = very)
	Sound = "Acid Rain",
	Volume = 0.25,
}

-- THE LOOK: modern retro, mixed from the pixel games that did it best:
--   Undertale / Deltarune - black boxes with thick white borders, the red heart
--     SOUL as your pointer, the button you point at turning yellow, messages
--     that type themselves out with a blip, the "encounter" flash
--   Pokemon - the double-line border inside every box, the bouncing title,
--     the striped battle wipe
--   Stardew Valley - chunky pixel icons (hearts, stars, coins, potions),
--     soft pixel corners
--   Celeste - everything squashes, bounces and sparkles when you touch it
-- Pixel letters and a bright 32-colour palette, on a clean screen. (RetroUI
-- does it - nothing else needs changing, and On = false puts the old look
-- back.) Each piece can be switched off on its own.
Config.Retro = {
	On = true,
	PixelFont = true, -- pixel text everywhere (and a chunkier one for big titles)
	MinText = 13, -- no text smaller than this (pixel letters get hard to read below it)
	Palette = true, -- every colour snapped to a 32-colour pixel-art palette
	Bands = 3, -- smooth gradients become this many bands of colour, like pixel shading (0 = smooth)
	Corners = 3, -- how round the corners of panels and buttons are (0 = hard square, like Undertale)
	Boxes = true, -- dark panels become black boxes with a thick white border (the Undertale box)
	BoxBorder = 3, -- how thick that white border is, in pixels
	Bevel = true, -- a second, thin line inside each box's border (the Pokemon double border)
	Sprites = true, -- pixel-art icons instead of the emoji ones (hearts, stars, coins, potions...)
	PixelImages = false, -- draw pictures with chunky pixels (off: pictures stay smooth)
	SegmentBars = false, -- health, level and boss bars split into segments
	Cursor = false, -- the red heart SOUL next to the button you point at (off: it got in the way)
	HoverYellow = true, -- the button you point at turns its text yellow
	Typewriter = true, -- new messages type themselves out, letter by letter
	TypeSpeed = 40, -- letters a second when they do
	TypeBlip = "UI Blip", -- the little voice blip while they type (a Sound in SoundService)
	Bounce = true, -- buttons squash when pressed, menus pop in
	ClickBurst = true, -- a burst of pixel sparks every time you click a button
	Scanlines = 1, -- an old-TV screen (1 = off - a clean screen; 0.93 = faint)
	StartScreen = true, -- the title screen when you join
	Title = "DEFEAT THE BOSS",
	Subtitle = "TO GROW",
	Blip = "UI Blip", -- a short blip on clicks, if you add a Sound with this name to SoundService
	-- the lobby in the same look (RetroWorld - only on your screen, only how
	-- things look: nothing is moved, and nothing solid changes)
	World = {
		On = true,
		Palette = true, -- the lobby's colours snapped to the same palette as the menus
		Flat = true, -- realistic textures (cobblestone, slate, metal...) become flat colour
		Motes = 36, -- glowing pixel cubes drifting around you (0 = none)
		SaveStar = true, -- the spinning pixel star over the spawn
		Flavour = true, -- a line of text typed out when you walk up to a shop, the shrine...
		Repeat = 150, -- seconds before the same place talks again
		Grade = true, -- a slightly warmer, punchier colour grade in the lobby
		DummyTalk = true, -- the training dummies mock you (and tell jokes) while you train
		-- Lines = { SellShop = "* your own line" }, -- (to change what a place says)
		-- more to look at (all of it can't be touched or stood on)
		Detail = {
			On = true,
			Walls = true, -- stone courses and chunky stones on the castle walls
			Flames = true, -- pixel flames and smoke instead of the old fire effects
			Pads = true, -- glowing pylons and rising sparks round the training pads
			Shrine = true, -- sparks rising round the prestige shrine
			Beacon = true, -- a pillar of light from the Spire's peak into the sky
			Grass = 320, -- tufts of grass and flowers scattered on the lawns (0 = none)
			Clouds = 14, -- voxel clouds drifting round the island (0 = none)
			Birds = 3, -- flocks of pixel birds circling the castle (0 = none)
		},
	},
}

-- THE HEART: your health on screen, as red liquid inside a pixel heart (Hud).
Config.Heart = {
	Pixel = 5, -- screen pixels per pixel of the heart (bigger = a bigger heart)
	Drain = 1.2, -- how fast it drains after a hit (a whole heart a second, x this)
	Fill = 0.5, -- how fast it fills when you heal
	Slosh = 1.6, -- how wildly the liquid can slosh
	Drops = 36, -- drops spilled per whole heart lost (a hit spills at least 3...)
	MaxDrops = 12, -- ...and at most this many
	Low = 0.25, -- below this much health it beats and its outline blinks red
}

-- the lobby's music: Sounds in SoundService, played in turn (or one name, looped)
Config.LobbyMusic = { "Lobby1song", "Lobby2song", "Lobby3song" }

-- The mix. Every sound in the game goes through one of three groups, so if an
-- asset turns out louder or quieter than expected, one number fixes the lot.
-- The levels are set against each other: the fight on top, music underneath
-- it, menu chimes quietest of all - you should always hear a punch land over
-- the song, and a coin ding should never drown out the room.
Config.Audio = {
	Music = 1, -- every song
	Effects = 1, -- punches, the boss, the world
	UI = 0.8, -- coins, buttons, level-ups, menus

	LobbyMusic = 0.5, -- background, but clearly heard (raise it for louder, up to 1)
	BossMusic = 0.42, -- louder than the lobby: the fight should feel bigger
	Hits = 0.7, -- your punches landing, loudest thing you hear
	BossSounds = 0.85, -- the boss's own slams, roars and splats
	Victory = 0.6, -- the sting when it falls
}

Config.Bosses = {
	[1] = {
		Name = "Oozark, the Gelatinous Tyrant",
		Short = "Oozark",
		Color = Color3.fromRGB(105, 210, 70), -- the slime
		DeepColor = Color3.fromRGB(46, 120, 40), -- deeper in the body
		CoreColor = Color3.fromRGB(26, 38, 22), -- the hollow thing inside
		EyeColor = Color3.fromRGB(236, 255, 170),

		-- How tough it is. Health is counted in punches from a player at exactly
		-- the floor's recommended level, so the fight is the same length for them
		-- whatever the numbers are. Stronger players cut it down faster, up to 3x.
		HealthPunches = 30, -- the first boss: long enough to learn, short enough to hook
		PartyScale = 0.6, -- +60% health for each extra player when the fight starts
		StudioFairFight = true, -- in Studio, your punches hit as if you were exactly the
		-- recommended level, so testing feels like the real fight even when you're strong

		Size = 20, -- how wide the body is (about four times your height standing up)
		WakeRange = 44, -- walk this close to the pit and it rises
		WakeTime = 2.6, -- rising out of the pool (it can't be hurt while it does)
		WakeSoundLead = 0.5, -- the roar's sound starts this much before the roar
		Leash = 95, -- it never strays further than this from the middle of the arena
		MoveSpeed = { 24, 32 }, -- surging after you between attacks, per phase (you walk 16, more with Swift Boots)
		TurnSpeed = { 320, 460 }, -- degrees a second while it lines up, per phase
		Breather = { { 0.25, 0.5 }, { 0.12, 0.35 } }, -- the pause between attacks, per phase

		PhaseAt = 0.5, -- the shell breaks at half health
		BreakTime = 2.5, -- the break itself, untouchable
		BreakShove = 58, -- how hard the break throws everyone back
		BreakReach = 40,
		Phase2Recovery = 0.75, -- phase two recovers 25% faster from everything
		DesperateAt = 0.15, -- below this it gets desperate...
		DesperateRecovery = 0.62, -- ...and recovers faster again

		Attacks = {
			-- rears up, wobbles, drops its whole bulk on you
			Slam = { Tell = 0.62, Damage = 22, Radius = 22, Recovery = 0.8, Knockback = 50, Rise = 8, Phase = 1, Range = { 0, 24 }, Weight = 5 },
			-- flattens and pushes a wall of slime outward: roll through it or jump it
			Wave = { Tell = 0.7, Damage = 18, Speed = 46, Reach = 80, Thickness = 5, Height = 4.2, Recovery = 0.75, Knockback = 40, Phase = 1, Range = { 8, 48 }, Weight = 4 },
			-- roots itself and hoses the floor around you with a barrage of globs;
			-- each leaves a burning puddle, so the arena fills up with them
			Spit = { Tell = 0.55, Damage = 11, Globs = 14, Gap = 0.09, Flight = 0.85, Spread = 16, Radius = 5, Puddle = 5, PuddleTime = 4.5, PuddleDamage = 2, PuddleTick = 0.5, Recovery = 0.9, Phase = 1, Range = { 12, 90 }, Weight = 4 },
			-- only at range: leans back and hurls itself at you
			Lunge = { Tell = 0.62, Damage = 25, Speed = 110, MaxDistance = 70, Knockback = 66, Splash = 17, Recovery = 0.95, Phase = 1, Range = { 20, 200 }, Weight = 7 },
			-- phase two: three slams in a row, hopping after you, each tighter than the last
			TripleSlam = { Tell = 0.6, Gap = 0.45, Damage = 20, Radii = { 20, 18, 16 }, Hop = 9, Rise = 7, Recovery = 1.0, Knockback = 44, Phase = 2, Range = { 0, 28 }, Weight = 4 },
			-- pillars of slime burst up under your feet, one after another: keep moving
			Wail = { Tell = 0.6, Rings = 5, Gap = 0.38, Fuse = 1.05, Radius = 11, Geyser = 30, Damage = 24, Recovery = 0.9, Knockback = 38, Phase = 1, Range = { 0, 200 }, Weight = 3 },
		},

		-- What a kill is worth, in multiples of the floor's recommended power.
		Reward = { Power = 1.5, FirstClear = 4 },

		-- the fight's music: the name of a Sound in SoundService
		Music = "Slime boss song",
		MusicVolume = 0.8, -- (louder than the default boss music level)
		-- played over the banner when it dies
		VictorySound = "Victory Is Ours (a) Sting",

		-- Sound ids for the fight. Blank ones play nothing rather than erroring.
		-- The fight's sounds: names of Sounds in SoundService (capitals and spaces
		-- don't matter). Left blank, each one looks for "Boss <name>".
		Sounds = { Wake = "Boss Wake", Slam = "Boss Slam", Wave = "Boss Wave", Spit = "Boss Spit", Splat = "Boss Splat",
			Lunge = "Boss Lunge", Wail = "Boss Wail", Erupt = "Boss Erupt", Break = "Boss Break", Death = "Boss Death" },
	},

	[2] = {
		Name = "Nahrzul, Devourer of the Dunes",
		Short = "Nahrzul",
		-- Body = "Worm" gives it the worm's body (BossClient) AND the worm's own
		-- way of fighting (BossService): it lives under the sand and hunts by
		-- sound. None of Gloomgut's attacks are used - its moves are all below.
		Body = "Worm",
		Color = Color3.fromRGB(178, 134, 74), -- its sand-crusted hide
		DeepColor = Color3.fromRGB(94, 64, 36), -- its underside, in shadow
		CoreColor = Color3.fromRGB(40, 26, 18), -- the dark of its throat
		EyeColor = Color3.fromRGB(255, 214, 90), -- small and many, amber
		HeartColor = Color3.fromRGB(255, 90, 40), -- the molten glow behind its armor

		-- The second boss: a little longer than Gloomgut, and it hits harder,
		-- but the same "punches at your recommended power" fairness applies.
		-- (You can only hurt it while it's out of the sand, so every window counts.)
		HealthPunches = 34,
		PartyScale = 0.62,
		-- after each punch that lands it shrugs off every other punch for this
		-- many seconds (from anyone) - bigger = fewer hits land, a harder fight
		IFrames = 0.6,
		StudioFairFight = true,

		Size = 30, -- a vast creature - half again as wide as Gloomgut
		WakeRange = 55,
		WakeTime = 3.2, -- it uncoils from round the seal and rears up to roar
		WakeSoundLead = 0.6,
		Leash = 130, -- keeps it inside the SandRadius DunesBuilder marked out for it
		TurnSpeed = { 260, 380 }, -- degrees a second it can turn while it swims, per phase

		PhaseAt = 0.5, -- its armor cracks at half health, and the seal caves in
		BreakTime = 3.0,
		BreakShove = 70,
		BreakReach = 55,
		Phase2Recovery = 0.72, -- phase two: its moments out of the sand are shorter
		DesperateAt = 0.15,
		DesperateRecovery = 0.6,

		-- THE HUNT. Between attacks it swims under the sand - you can't hurt it
		-- there, you only see the ridge it pushes up - and it goes after whoever
		-- is making the most noise. Running on sand is loud, rolling is louder,
		-- walking on stone is quiet and standing still is silent.
		Hunt = {
			SwimSpeed = { 30, 38 }, -- per phase (nobody runs faster than 24 in here)
			Time = { { 1.4, 2.4 }, { 0.9, 1.7 } }, -- how long it stalks before it strikes, per phase
			StrikeRange = 26, -- it strikes sooner once it's this close to its quarry
			DiveTime = 0.95, -- going back under after it's been out (it arches over and plunges in ahead)
			NoiseFade = 2.5, -- seconds a noise takes to fade (bigger = it remembers you longer)
			StoneNoise = 0.25, -- moving on stone is this much as loud as on sand
		},

		-- PHASE TWO: the seal caves in and the middle of the arena collapses into
		-- a real bowl of sand that drags you down toward the pit at the bottom,
		-- which burns. (The pull is on your screen; the damage is the server's.)
		Whirlpool = {
			Radius = 34, -- how far out the pull reaches (the seal's size)
			Depth = 5, -- how deep the bowl sinks at its middle
			Pull = { 5, 11 }, -- studs a second: at the edge, and near the middle (you run 16-24)
			PitRadius = 8, -- the bottom of the pit
			PitDamage = 6, PitTick = 0.5,
		},

		-- THE RUMBLE: while it swims under the sand hunting, the ground bucks in a
		-- ring round it every `Every` seconds - you see the sand jump. Anyone
		-- standing on sand inside `Radius` takes `Damage` and is jolted up: get
		-- away from where it went under, keep off its ridge, jump as the sand
		-- jumps, or get on stone. Range = how close before you feel each one in
		-- your view; Shake = how hard (0 = not at all).
		Rumble = { Every = 1.1, Radius = 18, Damage = 8, Knockback = 26, Range = 40, Shake = 0.45 },

		-- THE SAND IT TEARS UP. Where it bursts out, crashes down or cracks the
		-- floor, the sand really opens up (craters, trenches, fissures - on your
		-- screen, and you walk in them). This is how long before it slides back.
		Scars = { Last = 7 },

		-- Its attacks. Tell = the warning before it lands (always longer than
		-- your roll's 0.5s). Exposed = how long it stays out of the sand after,
		-- which is your chance to hit it. Sand = true: only used on someone
		-- standing on sand (it can't come up through stone). Anything given as
		-- { a, b } is { phase one, phase two }.
		Attacks = {
			-- AMBUSH: its back races after you through the sand, stops, the ground
			-- heaves up under you... and it bursts out where you stood. Move or roll off it.
			Ambush = { StalkSpeed = 44, StalkTime = 2.2, Lock = 0.65, Radius = 10, Damage = 30, Knockback = 70, Exposed = 1.6, Phase = 1, Weight = 6, Sand = true },
			-- BREACH: it leaps out of the sand in a great arc, and while it's in the
			-- air the strip it'll crash down on FOLLOWS YOU. Lock = how far through
			-- the leap it stops following (the strip flashes): roll then. Its body
			-- carves a trench where it lands, and it lies there stuck for a moment.
			-- In phase two it leaps again straight away (Leaps).
			Breach = { Tell = 1.0, Flight = 1.25, Lock = 0.62, Length = 120, Overshoot = 16, BodyLength = 72, Width = 14, Launch = 12, Height = 38,
				Damage = 32, Knockback = 60, Stuck = 2.6, Slide = 0.9, Leaps = { 1, 2 }, ChainTell = 0.5, Phase = 1, Weight = 4 },
			-- COIL: it circles you under the sand, then its body bursts up in a
			-- CLOSED ring round you with its head reared over you, and tightens.
			-- There's no gap: touching its body throws you back the way you came.
			-- The only way out is to ROLL through it. At the end the head strikes down.
			Coil = { Tell = 1.1, Radius = 22, Crush = 9, Close = 1.7, Wall = 10, WallDamage = 18, Damage = 40, Knockback = 55, Exposed = 1.8, Phase = 1, Weight = 4, Sand = true },
			-- DEVOUR: a sinkhole spins open under you - the sand really sinks - and
			-- drags you toward its middle, then its maw bursts up out of it. Roll
			-- (you can't be dragged in the air) or get on stone.
			Devour = { Tell = 1.5, Radius = 18, Depth = 6, Pull = { 6, 12 }, Bite = 10, Damage = 36, Knockback = 50, Exposed = 1.6, Phase = 1, Weight = 4, Sand = true },
			-- TAIL LASH: its tail rips up out of the sand BEHIND you and whips
			-- round in a wide arc, low over the sand - the tip trailing behind and
			-- cracking round at the end, like a whip - and in phase two, straight
			-- back again (Sweeps). Roll through it, jump it, or be out of reach.
			TailLash = { Tell = 0.85, Behind = 10, Reach = 26, Sweep = 220, Time = 0.55, Sweeps = { 1, 2 }, Pause = 0.25, Width = 5, Height = 5, Damage = 24, Knockback = 64, Phase = 1, Weight = 4 },
			-- TREMOR: it thrashes underground, the whole sand floor quakes and
			-- cracks open, a few times in a row. Be on stone, or in the air when each one hits.
			Tremor = { Tell = 1.3, Quakes = 3, Gap = 0.95, Damage = 12, Knockback = 22, Phase = 1, Weight = 3 },
			-- UNDERMINE (phase two): you're hiding on stone? It circles under the
			-- platform, the cracks glow... and it bursts up through it. The stone is
			-- gone for the rest of the fight. Get off when the cracks light up.
			Undermine = { Tell = 1.6, Damage = 30, Knockback = 60, Exposed = 1.6, Phase = 2, Weight = 6 },
		},

		Reward = { Power = 2.0, FirstClear = 5 },

		-- the fight's music: the Sound named "SANDWORMSONG" in SoundService
		-- (capitals and spaces don't matter). If it's ever missing, it plays
		-- Gloomgut's ("Boss") instead of nothing.
		Music = "SANDWORMSONG",
		-- how loud it plays: this song is quieter than Gloomgut's, so it's turned
		-- up (every other boss uses Config.Audio.BossMusic, 0.42). Higher = louder.
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		-- no acid rain here: the sandstorm (ArenaAmbience) picks up as it fights
		Weather = "Sandstorm",

		-- Its sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Gloomgut's instead.
		Sounds = {
			Wake = "SandRoar", -- rearing up out of its coils when it wakes
			Dive = "Worm Charge", -- going head-first under the sand
			Erupt = "Worm Erupt", -- bursting up out of the sand
			Crash = "Worm Slam", -- its body crashing down (breach, coil)
			Sweep = "SandWhip", -- the tail lash
			Roar = "SandRoar", -- the tremor
			Devour = "Worm Devour", -- the sinkhole opening
			Break = "Worm Crack", -- its armour blowing off
			Death = "Worm Death",
			Rumble = "SandRumble", -- a LOOPING low rumble, louder the closer it swims to you
		},
	},
}


----------------------------------------------------------------------
-- Combat in the Spire (Souls style: stamina, dodge roll, flasks)
----------------------------------------------------------------------
Config.Combat = {
	MaxStamina = 100,
	StaminaRegen = 34, -- per second
	StaminaRegenDelay = 0.8, -- seconds after spending before it refills
	PunchCost = 8,
	PunchInterval = 0.42, -- fastest you can punch (seconds)
	PunchLock = 0.42, -- each punch commits you: you can't move or punch again for this long
	PunchRollCancel = 0.25, -- ...but after this much of it you can roll out of the punch
	PunchRange = 8,
	PunchContact = 0.45, -- how far into a swing the fist actually lands (share of
	-- PunchLock). Damage, the camera and the sound all happen at this moment, and
	-- it is also where tracking stops and you are committed. -- studs from you to the enemy's surface
	RollCost = 24,
	JumpCost = 14, -- jumping in an arena costs stamina too; below this you can't jump
	RollCooldown = 0.55,
	RollInvincible = 0.5, -- seconds of invincibility from the moment you roll
	-- The roll takes about 0.46s in all (the hop, the dash through the air and
	-- the landing), so half a second covers you from the floor and back again.
	RollSpeed = 62, -- studs/second
	RollTime = 0.28, -- how long the dash lasts
	Flasks = 3, -- healing flasks per trip into the arena
	FlaskHeal = 0.45, -- heals this share of your max health
	FlaskDrinkTime = 0.9, -- seconds to drink (you're slowed and can't attack)
	FlaskWalkSpeed = 6,
	-- Your own sounds: names of Sounds in SoundService (capitals and spaces don't
	-- matter) and how loud each plays. Getting hurt is the one you must never miss.
	PlayerSounds = {
		Roll = { Name = "Roll", Volume = 0.5 },
		Hurt = { Name = "Hurt 8-Bit", Volume = 0.75 },
		Drink = { Name = "Drinking Potion", Volume = 0.6 },
		Death = { Name = "8bit death sound", Volume = 0.85 },
	},
	ArenaWalkSpeed = 24, -- the fastest anyone moves inside a Spire arena, however good their boots:
	-- a boss can only press you if you can't simply outrun it (the lobby is unaffected)
	-- your punch damage = the floor's recommended Power, times
	-- (your Power / recommended Power) ^ DamageCurve, kept between Min and Max
	DamageCurve = 0.5,
	DamageMin = 0.35,
	DamageMax = 3,
	PracticeHits = 25,

	-- A punch string, the Elden Ring idea kept simple: three swings that each
	-- carry you a bit further, the last one leaving you open for longer. A press
	-- near the end of a swing is remembered instead of dropped, and you only turn
	-- toward your target during a swing's wind-up - after that you're committed.
	-- The weight of a punch: what the world, the camera and your ears do when one
	-- lands. None of it touches damage. Paste sound ids in below (leave them blank
	-- and nothing plays rather than erroring).
	Impact = {
		World = false, -- the shockwave ring, air burst, dust and fist streaks.
		-- Off for now: only the camera reacts to a hit. Set true to bring them back.
		Ring = 13, -- how wide the shockwave ring opens, in studs
		Time = 0.2, -- and how fast: fast and gone reads as force, slow reads as magic
		Color = Color3.fromRGB(235, 245, 255),
		Shake = 1.1, -- how hard the camera is knocked about
		Fov = 4, -- degrees the view punches inward on a hit
		Stop = 0.09, -- the beat of slow motion on a finisher
		HitSounds = { "Punch 1", "Punch 2", "Punch 3", "Punch 4" }, -- Sounds in SoundService, one per landed hit
		Sounds = {
			Whoosh = "", -- the swing going through the air (played the moment you punch)
			Thump = "", -- the low body hit
			Crack = "", -- the sharp crack on top of it
		},
	},

	Combo = {
		Window = 0.85, -- punch again within this of the last one to continue the string
		Steps = { 1, 1.3, 1.7 }, -- how far each swing carries you (x the base step)
		Recovery = { 1, 1, 1.6 }, -- how long each swing leaves you committed (x PunchLock)
		Buffer = 0.3, -- a press this close to the end of a swing is queued, not lost
	}, -- the practice slime takes about this many hits at the recommended level
}

-- The bosses in the game's look: every colour that paints a boss (its body,
-- its underside, its eyes, its glow...) snapped to the same 32-colour
-- pixel-art palette as the menus and the lobby. Only how they look - the
-- fights are exactly the same. (Config.Retro.BossPalette = false: off.)
if Config.Retro and Config.Retro.On ~= false and Config.Retro.BossPalette ~= false then
	local RGB = Color3.fromRGB
	local PALETTE = {
		RGB(190, 74, 47), RGB(215, 118, 67), RGB(234, 212, 170), RGB(228, 166, 114),
		RGB(184, 111, 80), RGB(115, 62, 57), RGB(62, 39, 49), RGB(162, 38, 51),
		RGB(228, 59, 68), RGB(247, 118, 34), RGB(254, 174, 52), RGB(254, 231, 97),
		RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66), RGB(25, 60, 62),
		RGB(18, 78, 137), RGB(0, 153, 219), RGB(44, 232, 245), RGB(255, 255, 255),
		RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136), RGB(58, 68, 102),
		RGB(38, 43, 68), RGB(24, 20, 37), RGB(255, 0, 68), RGB(104, 56, 108),
		RGB(181, 80, 136), RGB(246, 117, 122), RGB(232, 183, 150), RGB(194, 133, 105),
	}
	local function snap(c)
		local best, bestD = c, math.huge
		for _, p in ipairs(PALETTE) do
			local d = (c.R - p.R) ^ 2 * 0.3 + (c.G - p.G) ^ 2 * 0.59 + (c.B - p.B) ^ 2 * 0.11
			if d < bestD then
				best, bestD = p, d
			end
		end
		return best
	end
	for _, def in pairs(Config.Bosses or {}) do
		for k, v in pairs(def) do
			if typeof(v) == "Color3" then
				def[k] = snap(v)
			end
		end
	end
end

return Config
