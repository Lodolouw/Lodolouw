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
Config.BaseWalkSpeed = 24 -- your speed outside a fight (the lobby is big: quicker than Roblox's 16)
Config.BaseCapacity = 20 -- backpack slots before upgrades
Config.RequireProximity = true -- shops only work when you stand near them
Config.StationRange = 34 -- studs
Config.MaxPrestige = 0 -- (prestige is gone)
Config.TalismanSlots = 3

-- Where the shops stand. Used by the lobby builder AND by server range checks.
Config.Stations = {
	Sell = Vector3.new(52, 0, 45), -- south-east of the fountain plaza
	Upgrades = Vector3.new(-50, -18.5, 330), -- the mushroom house, on the sandy cove south of the castle
	Craft = Vector3.new(72, 0, -40), -- the forge, in the Gear Hall on the east side
	Prestige = Vector3.new(0, 0, 0),
	Quests = Vector3.new(18, 0, 27), -- the Quest Board, by the south road just past the plaza
}
-- which way each building turns (degrees round the vertical)
Config.StationTurn = {
	Sell = -90, -- faces west, towards the path from the plaza
	Upgrades = 90, -- faces east, towards the stairs and the pier
	Quests = -90, -- faces west, onto the road
}

----------------------------------------------------------------------
-- The Colosseum (a wave arena for farming)
----------------------------------------------------------------------
-- Walk through the Colosseum gate (between the fountain and the training
-- field) and you're taken to your own fight in the Colosseum: straw dummies
-- hop in wave after wave and try to squash you. Nobody else can see or hit
-- your dummies, and theirs can't hurt you - everyone farms on their own.
-- Dummies are always your level, so a fight takes the same few punches
-- whatever your level; the rewards grow as you do. A quest runs the whole
-- time: BEAT 5 WAVES (a whole run, the King's wave last) for a big lump of
-- Power (XP) and coins, and it starts over with the next run. Pick how hard
-- it is as you go in (a pop-up at the door) or on the CLEARED screen for the
-- next run: Normal, Hard or Nightmare.
Config.Colosseum = {
	Center = Vector3.new(-2600, 0, 0), -- well away from the lobby and the Spire's arenas
	Radius = 82, -- how far out dummies can go: right up to the foot of the stands, so nowhere is safe
	-- the mini colosseum in the lobby (where the training field was), and its little door
	-- (it sits beside the south road, and its bridge lands on the little
	-- paved stub that leaves the road there)
	LobbyModel = Vector3.new(-60, 0, 90), -- its middle
	LobbyRadius = 42,
	GateTurn = 90, -- the gate faces east, onto the south road
	GatePosition = Vector3.new(-14.6, 0, 90), -- the door (you shrink into it here)
	ShrinkTo = 0.3, -- how small you get going through the door (like a pipe)
	ShrinkSteps = 8, -- in this many 8-bit steps
	-- the Mario pipe sound, going in and popping out: the first Sound on this
	-- list that's in SoundService (capitals and spaces don't matter)
	PipeSound = { "Pipe", "Mario Pipe", "Warp Pipe" },
	PipeVolume = 0.7,

	-- THE COLOSSEUM'S SOUNDS: names of Sounds in SoundService (the first one on
	-- each list that's there; capitals and spaces don't matter), and how loud
	-- each plays (x its own Volume). The dummy ones happen a lot, so they're
	-- quieter. Further-off dummies sound quieter still.
	Sounds = {
		Land = { names = { "Dummy Land" }, volume = 0.6 }, -- a dummy dropping in
		Slam = { names = { "Dummy Slam" }, volume = 0.7 }, -- its slam coming down
		Poof = { names = { "Dummy Poof" }, volume = 0.7 }, -- a dummy beaten
		Charge = { names = { "Brute Charge" }, volume = 0.8 }, -- the Brute starting its charge
		Throw = { names = { "Hay Throw" }, volume = 0.7 }, -- the Slinger throwing a bale
		HayLand = { names = { "Hay Landing", "Hay Land" }, volume = 0.7 }, -- the bale landing
		Clang = { names = { "Shield Clang" }, volume = 0.8 }, -- a punch off the Knight's shield
		Blink = { names = { "Cursed Blink" }, volume = 0.8 }, -- the Cursed Dummy vanishing / reappearing
		WaveHorn = { names = { "Wave Horn" }, volume = 0.8 }, -- a wave starting
		Cheer = { names = { "Crowd Cheer" }, volume = 0.8 }, -- a wave cleared, the King beaten
		Reward = { names = { "Reward Pop" }, volume = 0.6 }, -- XP and coins popping out
		-- the coins and XP reaching you (quiet, quick ticks that rise in pitch);
		-- it borrows the Reward Pop until you add a "Coin Collect" sound
		Collect = { names = { "Coin Collect", "Reward Pop" }, volume = 0.3 },
		Quest = { names = { "Quest Complete" }, volume = 0.9 }, -- the quest done
	},
	-- the crowd murmuring in the stands the whole time you're inside (looped)
	CrowdSound = { "Colosseum Crowd" },
	CrowdVolume = 0.25,
	-- the music while you farm (the King's own song takes over in his fight;
	-- the lobby's music steps aside while you're in there)
	Music = { "Colosseum Song" },
	MusicVolume = 0.45,
	EnterRange = 20,

	HitsToKill = 4, -- punches a dummy takes from a player at its level (no gear)
	WaveSize = { 3, 7 }, -- dummies in the first wave, and the most in one wave
	WaveBreak = 2.5, -- seconds between waves

	-- how a dummy fights
	HopTime = 0.55, -- one hop
	HopHeight = 6,
	HopReach = 13, -- the furthest one hop goes
	Rest = { 0.35, 0.9 }, -- the pause between hops
	SlamRange = 7, -- after landing this close to you it winds up a slam...
	SlamTell = 0.7, -- ...shows a red ring for this long...
	SlamDamage = 0.12, -- ...and takes this much of your max health if you're in it

	-- THE DUMMIES. More kinds join the waves as you level up; each wave is a
	-- random mix of the kinds you've unlocked. `health` and `reward` multiply a
	-- straw dummy's (so a Brute takes 1.6x the punches and pays 1.5x). `max` =
	-- the most of that kind in one wave. `scale` = how big it's built.
	Types = {
		{ id = "Straw", name = "Straw Dummy", level = 1, health = 1.0, reward = 1.0, weight = 4, scale = 1 },
		-- charges at you in a straight line (the red strip shows where)
		{ id = "Brute", name = "Wooden Brute", level = 10, health = 1.6, reward = 1.5, weight = 3, max = 3, scale = 1.3 },
		-- keeps its distance and lobs hay bales where you're standing
		{ id = "Slinger", name = "Hay Slinger", level = 20, health = 0.8, reward = 1.4, weight = 3, max = 2, scale = 0.95 },
		-- its shield blocks punches from the front: get round the back
		{ id = "Knight", name = "Iron Knight", level = 35, health = 2.0, reward = 2.2, weight = 2, max = 2, scale = 1.15 },
		-- vanishes and reappears right behind you, then slams
		{ id = "Cursed", name = "Cursed Dummy", level = 50, health = 1.3, reward = 2.5, weight = 2, max = 2, scale = 1.05 },
	},
	-- the Brute's charge: from Range[1] to Range[2] studs away it lowers its
	-- head (Tell), then runs Length studs straight at where you were
	Charge = { Range = { 12, 42 }, Tell = 0.7, Speed = 62, Length = 36, Width = 4.5, Damage = 0.15 },
	-- the Slinger's hay bale: it stays Keep[1]-Keep[2] studs away, winds up
	-- (Tell) and throws; the bale lands after Flight, hurting within Radius
	Throw = { Keep = { 16, 32 }, Tell = 0.55, Flight = 0.95, Radius = 5, Damage = 0.1 },
	-- the Knight's shield: punches from within this many degrees of its front bounce off
	ShieldArc = 110,
	-- the Cursed Dummy: fades out (Tell), reappears Behind studs behind you,
	-- and slams after a shorter wind-up than usual
	Blink = { Tell = 0.5, Behind = 6, SlamTell = 0.45 },

	-- THE BOSS WAVE: every `Every` waves (5, 10, 15...) the GIANT STRAW KING
	-- drops in on his own, with a boss bar across the top of the screen. He
	-- can't be hurt while he makes his entrance (IntroTime). Every attack
	-- shows a red warning first, so a careful player can dodge them all.
	-- `health` and `reward` multiply a straw dummy's, like the kinds above.
	King = {
		-- A RUN is `Every` waves, the last one his. Beat him and the Colosseum is
		-- CLEARED, like a mini dungeon: your time is saved, you choose RUN AGAIN
		-- (healed, flasks full, back to wave 1) or LEAVE. (EndsRun = false: no
		-- runs - he just comes back every `Every` waves and the waves go on.)
		Every = 5,
		EndsRun = true,
		-- the first clear of each day pays a bonus: this share of the Power
		-- between your level and the next, and coins + coins per level
		ClearBonus = { Power = 0.5, Coins = { 150, 15 } },
		name = "Giant Straw King",
		health = 10, -- about 40 punches at your level (without gear)
		reward = 15, -- pays as much as 15 straw dummies
		scale = 2.3, -- how big he's built (a straw dummy is 1)
		IntroTime = 2.8, -- seconds he stands and shows off before the fight starts
		Rest = { 0.45, 1 }, -- the pause between his moves
		HopReach = 18, -- his hops are long...
		HopTime = 0.8, -- ...slow...
		HopHeight = 9, -- ...and high
		SlamRange = 11, -- when you're this close he slams: a red ring this wide round him...
		SlamTell = 0.8, -- ...that shows for this long before he comes down...
		SlamDamage = 0.18, -- ...and takes this share of your max health if you're in it
		-- GROUND POUND: a red ring marks where you're standing, he crouches
		-- (Tell), leaps (Air seconds) and crashes down in it. A SHOCKWAVE then
		-- rolls out across the sand: jump over it or roll through it.
		Pound = {
			Range = { 0, 90 }, -- used when you're between these distances from him
			Tell = 0.6,
			Air = 0.95,
			Height = 34, -- how high he leaps
			Radius = 9, -- the ring he lands in
			Damage = 0.2,
			Stuck = 0.8, -- he's stuck a moment after landing: hit him!
			WaveDelay = 0.35, -- a beat after he lands, the shockwave bursts out...
			WaveSpeed = 24, -- ...and rolls out this many studs a second
			WaveReach = 70, -- how far it goes
			WaveHeight = 2.2, -- how tall it is (jump higher than this)
			WaveDamage = 0.14, -- every time it hits you...
			ReHit = 1, -- ...but not again for this many seconds
			Cooldown = { 5, 8 },
		},
		-- SUMMON: he raises his arms and calls straw minions down from the
		-- sky round you. He always does it when his health drops past each
		-- share in `At`, and every so often (Cooldown) as well.
		Summon = {
			Count = 3, -- minions each time...
			Max = 4, -- ...but never more than this on the sand at once
			Tell = 1.1,
			At = { 0.75, 0.4 },
			Cooldown = { 16, 22 },
			health = 0.5, -- a minion takes half a straw dummy's punches...
			reward = 0.4, -- ...and pays a little less than one
		},
		-- WHIRLWIND: a red circle shows round him (Tell), then he spins for
		-- `Time` seconds and comes after you (like the Valkyrie in Clash
		-- Royale), straw whipping round the whole circle. Run, or roll out.
		Spin = {
			Range = 15, -- used when you're this close
			Radius = 14, -- the circle
			Tell = 1,
			Time = 2.4,
			Turns = 7,
			Damage = 0.16, -- every time it hits you...
			ReHit = 0.9, -- ...and again every this many seconds you stay in it
			Chase = 11, -- studs a second it comes after you (you walk at 16)...
			RageChase = 14, -- ...and when he's angry
			Dizzy = 0.8, -- he wobbles, dizzy, afterwards: hit him!
			Cooldown = { 4, 7 },
		},
		Rage = 0.5, -- below this share of his health he gets ANGRY:
		RageSpeed = 0.75, -- he moves faster (his waits and hops take this much time)...
		RageWaves = 2, -- ...his ground pound sends this many shockwaves, and his whirlwind is faster
		RageGap = 0.5, -- (seconds between the shockwaves)
		WaveBreak = 4.5, -- (EndsRun = false only) after he falls, a longer pause before the next wave

		-- His sounds and music: names of Sounds in SoundService (capitals and
		-- spaces don't matter). He uses the first one on each list that's
		-- there, so he borrows the Spire bosses' sounds until you add his own.
		Sounds = {
			Horn = { "Boss Wave Horn" }, -- when the BOSS WAVE banner comes up
			Land = { "Straw King Land", "Boss Slam" }, -- landing from a leap
			Roar = { "Straw King Roar", "Boss Wake" }, -- his entrance, and when he gets angry
			Spin = { "Straw King Spin", "Boss Wave" }, -- the whirlwind
			Summon = { "Straw King Summon", "Boss Wail" }, -- calling his minions
			Death = { "Straw King Death", "Boss Death" },
			Victory = { "Victory Is Ours (a) Sting" }, -- you beat him
		},
		Music = { "Straw King Song", "Straw King Music", "Straw King Theme", "Slime boss song" }, -- plays during his fight
		MusicVolume = 0.6,
	},

	-- KILL STREAKS: dummies beaten in a row without getting hit. Every `Every`
	-- kills adds `Bonus` to what each kill pays (up to `Max`): x5 = +10%,
	-- x10 = +20%... Getting hurt ends it. It carries on from run to run.
	Streak = { Every = 5, Bonus = 0.1, Max = 0.5 },

	-- DIFFICULTY: picked in the pop-up at the lobby's little door as you go
	-- in, or on the CLEARED screen for the next run (it's saved). The first is open to
	-- everyone; each one after it opens once you've cleared a run on the one
	-- before it. For each:
	--   health  dummies (and the King) take this many times the punches
	--   damage  their hits hurt this many times as much
	--   extra   this many more dummies in every wave
	--   pace    dummies wait and hop this much of the time (0.85 = 15% faster;
	--           their red warnings stay just as long, so you can still dodge)
	--   reward  EVERYTHING the run pays is multiplied by this: each kill, the
	--           quest, and the first clear of the day
	--   angry   the King is ANGRY from the start (faster, two shockwaves...)
	--   color   the colour it shows in on the screen
	Difficulties = {
		{ id = "Normal", name = "NORMAL", health = 1, damage = 1, extra = 0, pace = 1, reward = 1, color = Color3.fromRGB(99, 199, 77) },
		{ id = "Hard", name = "HARD", health = 1.4, damage = 1.5, extra = 1, pace = 0.85, reward = 2, color = Color3.fromRGB(247, 118, 34) },
		{ id = "Nightmare", name = "NIGHTMARE", health = 2, damage = 2, extra = 2, pace = 0.7, reward = 3.5, angry = true, color = Color3.fromRGB(228, 59, 68) },
	},

	-- rewards, worked out from how much Power your level needs to reach the next
	KillPower = 0.012, -- each dummy: this share of the Power between your level and the next
	KillCoins = { 4, 1 }, -- each dummy: 4 coins + 1 per level
	-- THE QUEST: beat QuestWaves waves (a whole run: the King's wave is the
	-- 5th) for this share of the way to your next level...
	QuestWaves = 5,
	QuestPower = 0.5,
	QuestCoins = { 150, 30 }, -- ...and 150 coins + 30 per level
}

-- A Colosseum difficulty by its id ("Normal", "Hard", "Nightmare"): the first
-- one (Normal) if there's no such difficulty
function Config.colosseumDifficulty(id)
	local list = Config.Colosseum.Difficulties or {}
	for _, d in ipairs(list) do
		if d.id == id then
			return d
		end
	end
	return list[1] or { id = "Normal", name = "NORMAL", health = 1, damage = 1, extra = 0, pace = 1, reward = 1, color = Color3.fromRGB(99, 199, 77) }
end

-- Whether a difficulty is open to a player. `col` is their saved Colosseum
-- record (data.Colosseum): the first difficulty is always open, and each one
-- after it once they've cleared a run on the one before it.
function Config.colosseumUnlocked(col, id)
	local list = Config.Colosseum.Difficulties or {}
	for i, d in ipairs(list) do
		if d.id == id then
			if i == 1 then
				return true
			end
			local wins = type(col) == "table" and type(col.wins) == "table" and col.wins[list[i - 1].id]
			return type(wins) == "number" and wins > 0
		end
	end
	return false
end

-- The rewards for a player of this level (kill = one dummy, quest = the whole quest)
function Config.colosseumRewards(level)
	local C = Config.Colosseum
	local gap = math.max(1, Config.powerForLevel(level + 1) - Config.powerForLevel(level))
	return {
		killPower = math.max(1, math.floor(gap * C.KillPower)),
		killCoins = C.KillCoins[1] + C.KillCoins[2] * level,
		questPower = math.max(1, math.floor(gap * C.QuestPower)),
		questCoins = C.QuestCoins[1] + C.QuestCoins[2] * level,
		-- the first Colosseum clear of the day
		clearPower = math.max(1, math.floor(gap * ((C.King and C.King.ClearBonus and C.King.ClearBonus.Power) or 0.5))),
		clearCoins = (C.King and C.King.ClearBonus and (C.King.ClearBonus.Coins[1] + C.King.ClearBonus.Coins[2] * level)) or 0,
	}
end

----------------------------------------------------------------------
-- Daily quests (the Quest Board)
----------------------------------------------------------------------
-- Every day (midnight UTC) the Quest Board offers the same PerDay quests
-- to everyone, picked from the pool below - never two of the same kind on
-- one day. You choose ONE of them; finish it, then hand it in at the board
-- for the coins (it gets stamped COMPLETED).
--   kind: arena = dummies beaten in the Colosseum, boss = Spire bosses beaten,
--         sell = items sold, chest = treasure chests opened
Config.Quests = {
	PerDay = 3,
	Pool = {
		{ id = "Arena10", kind = "arena", goal = 10, reward = 80, text = "Beat %d dummies in the Colosseum" },
		{ id = "Arena30", kind = "arena", goal = 30, reward = 150, text = "Beat %d dummies in the Colosseum" },
		{ id = "Arena100", kind = "arena", goal = 100, reward = 400, text = "Beat %d dummies in the Colosseum" },
		{ id = "Boss1", kind = "boss", goal = 1, reward = 300, text = "Defeat a Spire boss" },
		{ id = "Boss3", kind = "boss", goal = 3, reward = 800, text = "Defeat %d Spire bosses" },
		{ id = "Sell25", kind = "sell", goal = 25, reward = 150, text = "Sell %d items at the shop" },
		{ id = "Chest2", kind = "chest", goal = 2, reward = 200, text = "Open %d treasure chests" },
	},
}
Config.QuestById = {}
for _, q in ipairs(Config.Quests.Pool) do
	Config.QuestById[q.id] = q
end

-- which day it is for quests (changes at midnight UTC)
function Config.questDay(t)
	return math.floor((t or os.time()) / 86400)
end

-- the quests for a given day: the same for everyone, never two of one kind
function Config.questsForDay(day)
	local rng = Random.new(day * 7919 + 17)
	local pool = table.clone(Config.Quests.Pool)
	local picked, kinds = {}, {}
	while #picked < Config.Quests.PerDay and #pool > 0 do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		if not kinds[q.kind] then
			kinds[q.kind] = true
			table.insert(picked, q.id)
		end
	end
	return picked
end

-- the line shown on the board
function Config.questText(q)
	return string.format(q.text, q.goal)
end

----------------------------------------------------------------------
-- Levels (like Blox Fruits): your level is the number that matters. It
-- comes from your total Power (your XP), which only ever goes up - from
-- the Colosseum and beating bosses - up to MaxLevel. Every level gives you
-- StatPoints.PerLevel points to spend on your stats (see Config.StatPoints).
-- Total Power for a level = LevelScale x (level - 1) ^ LevelCurve
-- (level 2 needs 18, level 44 about 1.4M, level 256 about 297M).
----------------------------------------------------------------------
Config.MaxLevel = 256
Config.LevelScale = 17.9
Config.LevelCurve = 3

-- Total Power you need to reach `level`
function Config.powerForLevel(level)
	if level <= 1 then
		return 0
	end
	level = math.min(level, Config.MaxLevel + 1)
	return math.floor(Config.LevelScale * (level - 1) ^ Config.LevelCurve)
end

-- Your level for a given total Power (never above MaxLevel)
function Config.levelFromPower(power)
	power = math.max(power or 0, 0)
	local level = math.floor((power / Config.LevelScale) ^ (1 / Config.LevelCurve)) + 1
	level = math.clamp(level, 1, Config.MaxLevel)
	-- fix any rounding at the exact boundaries
	while level < Config.MaxLevel and Config.powerForLevel(level + 1) <= power do
		level = level + 1
	end
	while level > 1 and Config.powerForLevel(level) > power do
		level = level - 1
	end
	return level
end

----------------------------------------------------------------------
-- Stat points: every level gives you PerLevel points to spend in the STATS
-- menu (the button on the left, or the Shrine of Growth). `per` is what one
-- point gives. Resetting them is free.
----------------------------------------------------------------------
Config.StatPoints = {
	PerLevel = 3,
	Stats = {
		{ id = "Strength", name = "Strength", per = 0.5, gives = "Damage", desc = "% more damage to bosses", color = Color3.fromRGB(228, 59, 68) },
		{ id = "Vitality", name = "Vitality", per = 2, gives = "Health", desc = " more max health", color = Color3.fromRGB(99, 199, 77) },
		{ id = "Defense", name = "Defense", per = 0.1, gives = "Defense", desc = "% less damage taken (60% max, with gear)", color = Color3.fromRGB(0, 153, 219) },
		{ id = "Training", name = "Training", per = 0.5, gives = "Power", desc = "% more Power from training", color = Color3.fromRGB(254, 174, 52) },
	},
}
Config.StatById = {}
for _, st in ipairs(Config.StatPoints.Stats) do
	Config.StatById[st.id] = st
end

-- how many points you've earned, spent, and have left
function Config.statPointsTotal(d)
	return (Config.levelFromPower(d and d.Power or 0) - 1) * Config.StatPoints.PerLevel
end
function Config.statPointsSpent(d)
	local n = 0
	for _, st in ipairs(Config.StatPoints.Stats) do
		n = n + ((d and d.Stats and d.Stats[st.id]) or 0)
	end
	return n
end
function Config.statPointsLeft(d)
	return math.max(0, Config.statPointsTotal(d) - Config.statPointsSpent(d))
end
-- what your spent points give: { Damage = %, Health = n, Defense = %, Power = % }
function Config.statBonus(d)
	local out = { Damage = 0, Health = 0, Defense = 0, Power = 0 }
	for _, st in ipairs(Config.StatPoints.Stats) do
		out[st.gives] = out[st.gives] + ((d and d.Stats and d.Stats[st.id]) or 0) * st.per
	end
	return out
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
		desc = "+1 walk speed per level (outside fights)",
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

-- (Prestige is gone: levels are the true progress now. These stay only so
-- anything old that asks gets "no bonus".)
function Config.prestigePowerMult()
	return 1
end
function Config.prestigeCoinMult()
	return 1
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

-- How fast a player moves. In a FIGHT (a Spire arena, the Colosseum, the
-- intro's fight) everyone moves at the same speed, Config.Combat.ArenaWalkSpeed
-- - no upgrades or talismans: the fights are about dodging, not outrunning.
-- Outside a fight: BaseWalkSpeed plus Swift Boots and talismans. Every place
-- that sets walk speed asks this, so they can't disagree.
function Config.walkSpeedFor(player, d)
	if player then
		local intro = player:GetAttribute("Intro")
		if player:GetAttribute("SpireFloor") or player:GetAttribute("Colosseum") or intro == "Void" or intro == "Fight" then
			return (Config.Combat and Config.Combat.ArenaWalkSpeed) or 20
		end
	end
	return d and Config.stats(d).walkSpeed or Config.BaseWalkSpeed
end

function Config.stats(d)
	local up = d.Upgrades or {}
	local U = Config.UpgradeById
	local points = Config.statBonus(d)

	local powerMult = (1 + U.PowerGain.perLevel * (up.PowerGain or 0))
		* (1 + Config.talismanBonus(d, "PowerGain"))
		* (1 + points.Power / 100)

	local coinMult = (1 + U.SellValue.perLevel * (up.SellValue or 0))
		* (1 + Config.talismanBonus(d, "SellValue"))

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
	local maxHealth = math.floor(Config.BaseHealth * (1 + Config.talismanBonus(d, "MaxHealth")) + gear.Health + points.Health)

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
-- The Spire (boss floors). Floors 1-3 have arenas and bosses; the rest
-- show as sealed in the Spire menu.
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
		{
			id = 3,
			boss = "Knight Burrowmore, the Honourable Digger",
			area = "The Glimmer Dig",
			level = 45,
			blurb = "An old dig on the sunny plains, heaped with treasure. Its keeper is a knight of the shovel: cheerful, honourable - and he hits like a falling anvil.",
			color = Color3.fromRGB(0, 153, 219),
			open = true,
			-- how the dig looks on your screen while you're in it (ArenaAmbience):
			-- a bright afternoon over the plains, a little dust drifting past
			ambience = {
				ClockTime = 15.2, -- the sun a little past its highest
				Atmosphere = {
					Density = 0.28,
					Offset = 0.1,
					Color = Color3.fromRGB(206, 226, 255),
					Decay = Color3.fromRGB(150, 180, 230),
					Glare = 0.2,
					Haze = 1.2,
				},
				Tint = Color3.fromRGB(255, 248, 232),
				Saturation = 0.08,
				Contrast = 0.04,
				Sand = Color3.fromRGB(214, 180, 130), -- the drifting dust
				Grains = 0.2, -- how much of it (1 = the dunes' breeze): only a little
				Clouds = false, -- (no big rolling clouds of dust either)
				Wind = Vector3.new(1, 0, -0.4),
			},
		},
		{
			id = 4,
			boss = "Kaze, the Headband Hero",
			area = "The Rooftop Dojo",
			level = 60,
			blurb = "A dojo on a mountain peak above the clouds. A wandering fighter trains here, headband streaming in the wind. He has waited a long time for a real challenger.",
			color = Color3.fromRGB(228, 59, 68),
			open = true,
			-- sunset on the mountain, cherry blossom petals drifting past
			ambience = {
				ClockTime = 17.6,
				Atmosphere = {
					Density = 0.32,
					Offset = 0.15,
					Color = Color3.fromRGB(255, 196, 150),
					Decay = Color3.fromRGB(214, 120, 110),
					Glare = 0.5,
					Haze = 1.6,
				},
				Tint = Color3.fromRGB(255, 232, 214),
				Saturation = 0.1,
				Contrast = 0.05,
				Sand = Color3.fromRGB(246, 117, 122), -- (the "dust" here is petals)
				Grains = 0.3,
				Clouds = false,
				Wind = Vector3.new(1, 0, 0.3),
			},
		},
		{
			id = 5,
			boss = "Speedy Revvington, King of the Speedway",
			area = "Piston Speedway",
			level = 75,
			blurb = "A roaring racetrack in the desert, the stands packed with fans. Its champion is a cocky red race car who has never lost a race - and never lets anyone forget it.",
			color = Color3.fromRGB(228, 59, 68),
			open = true,
			-- a hot, bright desert afternoon, a little dust blowing across the track
			ambience = {
				ClockTime = 14.2,
				Atmosphere = {
					Density = 0.26,
					Offset = 0.1,
					Color = Color3.fromRGB(255, 226, 180),
					Decay = Color3.fromRGB(230, 160, 110),
					Glare = 0.3,
					Haze = 1.3,
				},
				Tint = Color3.fromRGB(255, 244, 226),
				Saturation = 0.1,
				Contrast = 0.05,
				Sand = Color3.fromRGB(228, 166, 114), -- (the dust off the desert)
				Grains = 0.15,
				Clouds = false,
				Wind = Vector3.new(1, 0, -0.2),
			},
		},
		{
			id = 6,
			boss = "Gridlock, the Final Beat",
			area = "The Final Beat",
			level = 90,
			blurb = "The last level. A grid of neon floating in the void, pulsing to the music - and the whole level is out to get you. It's led by a giant cube with a demon's grin.",
			color = Color3.fromRGB(255, 0, 68),
			open = true,
			-- a purple void, neon everywhere, a few sparks drifting past
			ambience = {
				ClockTime = 19.4,
				Atmosphere = {
					Density = 0.34,
					Offset = 0.2,
					Color = Color3.fromRGB(104, 56, 108),
					Decay = Color3.fromRGB(38, 43, 68),
					Glare = 0.2,
					Haze = 2.2,
				},
				Tint = Color3.fromRGB(236, 222, 255),
				Saturation = 0.2,
				Contrast = 0.12,
				Sand = Color3.fromRGB(181, 80, 136), -- (the "dust" here is neon sparks)
				Grains = 0.12,
				Clouds = false,
				Wind = Vector3.new(0.3, 0, 1),
			},
		},
		{ id = 7, boss = "???", area = "???", level = 105, blurb = "Sealed.", color = Color3.fromRGB(99, 199, 77), open = false },
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
		-- Lines = { SellShop = "* your own line" }, -- (to change what a place says)
		-- more to look at (all of it can't be touched or stood on)
		Detail = {
			On = true,
			Walls = true, -- stone courses and chunky stones on the castle walls
			Flames = true, -- pixel flames and smoke instead of the old fire effects
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
	Music = 0.7, -- every song (turned down a bit)
	Effects = 1, -- punches, the boss, the world
	UI = 0.8, -- coins, buttons, level-ups, menus

	LobbyMusic = 0.5, -- background, but clearly heard (raise it for louder, up to 1)
	BossMusic = 0.42, -- louder than the lobby: the fight should feel bigger
	Hits = 0.7, -- your punches landing, loudest thing you hear
	BossSounds = 0.85, -- the boss's own slams, roars and splats
	Victory = 0.6, -- the sting when it falls
}

----------------------------------------------------------------------
-- THE INTRO: OOZLET (a brand-new player's first minute)
----------------------------------------------------------------------
-- A new player wakes up in the dark, like the start of Undertale: only the
-- fountain and the plaza round it are there, with 8-bit mist all round and
-- nothing else - no buttons, no bars, no other players. Oozlet, a baby
-- slime (Oozark's little one), is happily hopping round the fountain. Big
-- pixel letters build up one by one - HIT THE SLIME! - and the "!" lands
-- with a BOOM. Punch it and it gets angry: a short, easy fight that
-- teaches punching and rolling (its first slam waits up in the air until
-- you roll out of the red), it cracks at half health, and then it pops.
-- It drops your first chest, the mist rolls back and the lobby builds
-- itself around you, piece by piece - and the Spire last: OOZARK AWAITS...
-- You can't lose (Oozlet never takes you below Floor of your health), and
-- only brand-new players get it (beating it is saved). IntroService runs
-- the fight; IntroClient draws all of it, on that player's screen only.
Config.Intro = {
	On = true, -- false: nobody gets the intro (new players start in the lobby)
	-- In Studio, every Play starts with the intro so you can see it (even with
	-- your own save). Set false and Studio works like the real game: only a
	-- brand-new player gets it.
	AlwaysInStudio = true,

	-- Where it happens
	Center = Vector3.new(0, 0, 0), -- the fountain: the middle of the lit circle
	Radius = 23.5, -- how far out the light reaches (the plaza is 23 studs from the middle)
	Wall = 24.5, -- you can't walk out past this while it's dark
	SpawnAt = Vector3.new(0, 0, 17), -- where you wake up (facing the fountain)
	Zoom = 26, -- how far the camera can pull back while it's dark (so the dark never ends)

	Oozlet = {
		Name = "OOZLET", -- on its health bar
		Health = 12, -- punches from a brand-new player (each of their punches does 1)
		Size = 4.6, -- studs across
		Hitbox = 2.6, -- how close to its middle a punch counts
		Color = Color3.fromRGB(99, 199, 77), -- the slime
		DeepColor = Color3.fromRGB(62, 137, 72), -- deeper inside it
		HeartColor = Color3.fromRGB(254, 231, 97), -- the little glowing heart in the middle
		CheekColor = Color3.fromRGB(246, 117, 122), -- rosy cheeks (while it's happy)
		CrownColor = Color3.fromRGB(254, 231, 97), -- its tiny crown (it's a prince)

		-- HAPPY (before you hit it): little hops round the fountain on a circle
		Circle = 13.5, -- studs from the fountain's middle
		HappyHop = 0.42, -- seconds a hop takes
		HappyHeight = 2.2, -- how high it hops
		HappyStep = 3.4, -- how far one hop goes
		HappyRest = { 0.2, 0.45 }, -- the pause between hops (seconds, lowest-highest)
		Bump = 10, -- stand still this long and it hops over and bumps you (it's harmless)
		WakeTime = 1.3, -- seconds it takes to get angry after your first punch

		-- ANGRY: it hops after you...
		HopTime = 0.45,
		HopHeight = 3,
		HopLength = 6.5,
		Rest = { 0.35, 0.7 },
		-- ...and slams when you're close: it rises up while a red circle fills
		-- round it, then comes down. Out of the circle (or rolling) = safe.
		SlamReach = 6, -- it slams when you're this close
		SlamTell = 0.95, -- seconds from the circle appearing to the landing
		SlamRadius = 6.5,
		SlamRise = 3.5, -- how high it rises
		SlamDamage = 0.12, -- share of your max health
		SlamRecover = 0.8, -- it stays squished on the ground this long after: hit it!

		-- ITS FIRST SLAM IS THE LESSON: it leaps up over you and HANGS in the air
		-- above a red circle (it can't be hit up there) until you roll out of
		-- the red - or walk out. Then it drops, and it's dizzy: hit it!
		Lesson = {
			Height = 7, -- how high it hangs
			Rise = 0.7, -- seconds to get up there
			Radius = 7, -- the red circle
			Wait = 12, -- the longest it hangs there (then it just drops)
			Drop = 0.2, -- seconds to come down
			Dizzy = 1.6, -- seconds it's dizzy after
		},

		-- AT HALF HEALTH IT CRACKS: it can't be hurt for a moment, its shell
		-- bursts (pushing you back, no harm), and it gets faster...
		Crack = { Time = 1.4, Push = 9 },
		Cracked = { HopTime = 0.36, Rest = { 0.18, 0.4 }, SlamTell = 0.8 },
		-- ...and sometimes it BOUNCES at you three times in a row, each one
		-- landing in a small red circle
		Bounce = {
			Count = 3,
			Time = 0.6, -- each bounce (the circle shows for this long before it lands)
			Height = 4,
			Length = 9, -- furthest one bounce goes
			Radius = 4.5,
			Damage = 0.08,
			Tired = 1.1, -- it's out of breath after: hit it!
			Chance = 0.4, -- how often it picks this (0-1)
		},

		Floor = 0.3, -- it never takes you below this share of your health: you can't lose
	},

	-- The words (capitals look best in the pixel font)
	Text = {
		Hit = "HIT THE SLIME!", -- built up letter by letter at the start
		Hits = { "AGAIN!", "HARDER!", "YES!!", "KEEP GOING!!" }, -- a new one each punch
		Roll = "ROLL!!", -- while it hangs over you
		Rolled = "NICE ROLL!",
		Stepped = "DODGED!",
		Ouch = "OUCH! ROLL!!", -- it waited and landed on you
		Dizzy = "NOW HIT IT!",
		Crack = "IT'S CRACKING!",
		Finish = "FINISH IT!!!", -- one or two punches left
		Awaits = "OOZARK AWAITS...", -- at the end, looking at the Spire
		-- the little line under the big words: how, on each kind of controls
		PunchHow = { Mouse = "CLICK TO PUNCH", Touch = "TAP TO PUNCH", Gamepad = "PRESS R2 TO PUNCH" },
		RollHow = { Mouse = "PRESS SHIFT TO ROLL", Touch = "TAP ROLL", Gamepad = "PRESS B TO ROLL" },
	},

	-- The end: the mist rolls back and the lobby builds itself round you
	Reveal = {
		Delay = 3.6, -- seconds after Oozlet pops before the mist starts to go (the chest lands and opens)
		Time = 8, -- how long the mist takes to roll back across the whole island
		Reach = 600, -- how far it rolls (past the island's edge)
		Spire = 3.4, -- the look at the Spire at the very end (OOZARK AWAITS...)
	},

	-- What beating it gives you
	Reward = {
		Chest = true, -- Oozlet's Chest: starter gear anyone can wear (Items, "floor" 0)
		Coins = 100, -- enough for a first upgrade
		Level = 3, -- you're at least this level after
	},

	-- The fight's music: the first of these Sounds that's in SoundService
	Music = { "Oozlet Song", "Slime boss song", "Colosseum Song" },
	MusicVolume = 0.45,
	-- Its sounds: the first name on each list that's in SoundService (capitals
	-- and spaces don't matter). If none of them is there, a built-in Roblox
	-- sound plays instead, so it's never silent.
	Sounds = {
		Blip = { "UI Blip" }, -- each letter locking in
		Boom = { "Boss Slam" }, -- the "!" landing
		Hop = { "Dummy Land" }, -- Oozlet landing a hop
		Squish = { "Boss Splat" }, -- Oozlet getting punched
		Wake = { "Boss Wake" }, -- Oozlet getting angry
		Slam = { "Boss Slam" }, -- its slams landing
		Crack = { "Boss Break" }, -- its shell cracking
		Pop = { "Boss Death", "Dummy Poof" }, -- the end of it
		Chest = { "Reward Pop" }, -- the chest landing and opening
		Win = { "Quest Complete" },
		Awaits = { "Boss Wake" }, -- the Spire appearing
	},
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
		MoveSpeed = { 24, 32 }, -- surging after you between attacks, per phase (everyone walks 20 in a fight)
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
		Color = Color3.fromRGB(228, 166, 114), -- its sand-crusted hide (8-bit: bands of this...)
		DeepColor = Color3.fromRGB(115, 62, 57), -- ...and this, its underside in shadow
		CoreColor = Color3.fromRGB(40, 26, 18), -- the dark of its throat
		EyeColor = Color3.fromRGB(255, 214, 90), -- small and many, amber
		HeartColor = Color3.fromRGB(255, 90, 40), -- the molten glow behind its armor

		-- The second boss: a little longer than Gloomgut, and it hits harder,
		-- but the same "punches at your recommended power" fairness applies.
		-- (You can only hurt it while it's out of the sand, so every window counts.)
		HealthPunches = 30,
		PartyScale = 0.62,
		-- after each punch that lands it shrugs off every other punch for this
		-- many seconds (from anyone) - bigger = fewer hits land, a harder fight
		IFrames = 0.35, -- (was 0.6: every opening is worth more punches now)
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
			Time = { { 0.9, 1.6 }, { 0.6, 1.2 } }, -- how long it stalks before it strikes, per phase (short: more fighting, less waiting)
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
		-- (Damage = 0 switches it off: the constant chip damage wasn't fun)
		Rumble = { Every = 1.1, Radius = 18, Damage = 0, Knockback = 26, Range = 40, Shake = 0.45 },

		-- THE SAND IT TEARS UP. Where it bursts out, crashes down or cracks the
		-- floor, the sand really opens up (craters, trenches, fissures - on your
		-- screen, and you walk in them). This is how long before it slides back.
		-- Terrain = false: off. Tearing up the Terrain sand was the laggiest
		-- thing in the fight, so the craters and trenches aren't dug any more
		-- (every hit still works exactly the same).
		Scars = { Last = 7, Terrain = false },

		-- Its attacks. Tell = the warning before it lands (always longer than
		-- your roll's 0.5s). Exposed = how long it stays out of the sand after,
		-- which is your chance to hit it. Sand = true: only used on someone
		-- standing on sand (it can't come up through stone). Anything given as
		-- { a, b } is { phase one, phase two }.
		Attacks = {
			-- AMBUSH: its back races after you through the sand, stops, the ground
			-- heaves up under you... and it bursts out where you stood. Move or roll off it.
			Ambush = { StalkSpeed = 44, StalkTime = 2.2, Lock = 0.65, Radius = 10, Damage = 30, Knockback = 70, Exposed = 2.6, Phase = 1, Weight = 6, Sand = true },
			-- BREACH: it leaps out of the sand in a great arc, and while it's in the
			-- air the strip it'll crash down on FOLLOWS YOU. Lock = how far through
			-- the leap it stops following (the strip flashes): roll then. Its body
			-- carves a trench where it lands, and it lies there stuck for a moment.
			-- In phase two it leaps again straight away (Leaps).
			Breach = { Tell = 1.0, Flight = 1.25, Lock = 0.62, Length = 120, Overshoot = 16, BodyLength = 72, Width = 14, Launch = 12, Height = 38,
				Damage = 32, Knockback = 60, Stuck = 3.4, Slide = 0.9, Leaps = { 1, 2 }, ChainTell = 0.5, Phase = 1, Weight = 4 },
			-- COIL: it circles you under the sand, then its body bursts up in a
			-- CLOSED ring round you with its head reared over you, and tightens.
			-- There's no gap: touching its body throws you back the way you came.
			-- The only way out is to ROLL through it. At the end the head strikes down.
			Coil = { Tell = 1.1, Radius = 22, Crush = 9, Close = 1.7, Wall = 10, WallDamage = 18, Damage = 40, Knockback = 55, Exposed = 2.6, Phase = 1, Weight = 4, Sand = true },
			-- DEVOUR: a sinkhole spins open under you - the sand really sinks - and
			-- drags you toward its middle, then its maw bursts up out of it. Roll
			-- (you can't be dragged in the air) or get on stone.
			Devour = { Tell = 1.5, Radius = 18, Depth = 6, Pull = { 6, 12 }, Bite = 10, Damage = 36, Knockback = 50, Exposed = 2.6, Phase = 1, Weight = 4, Sand = true },
			-- TAIL LASH: its tail rips up out of the sand BEHIND you and whips
			-- round in a wide arc, low over the sand - the tip trailing behind and
			-- cracking round at the end, like a whip - and in phase two, straight
			-- back again (Sweeps). Roll through it, jump it, or be out of reach.
			TailLash = { Tell = 0.85, Behind = 10, Reach = 26, Sweep = 220, Time = 0.55, Sweeps = { 1, 2 }, Pause = 0.25, Width = 5, Height = 5, Damage = 24, Knockback = 64, Phase = 1, Weight = 4 },
			-- TREMOR: it thrashes underground, the whole sand floor quakes and
			-- cracks open, a few times in a row. Be on stone, or in the air when each one hits.
			Tremor = { Tell = 1.3, Quakes = 2, Gap = 0.95, Damage = 12, Knockback = 22, Phase = 1, Weight = 2 },
			-- UNDERMINE (phase two): you're hiding on stone? It circles under the
			-- platform, the cracks glow... and it bursts up through it. The stone is
			-- gone for the rest of the fight. Get off when the cracks light up.
			Undermine = { Tell = 1.6, Damage = 30, Knockback = 60, Exposed = 2.4, Phase = 2, Weight = 6 },
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

	[3] = {
		Name = "Knight Burrowmore, the Honourable Digger",
		Short = "Burrowmore",
		-- A knight of the shovel (a parody of a certain blue shovel knight - with
		-- his own name, colours and curly horns). He fights on the surface like
		-- Oozark, so BossService's shared brain runs him: he picks a move that
		-- suits how far away you are. His moves are in ServerScriptService/
		-- Bosses/Burrowmore.lua; his body in ReplicatedStorage/BossBodies/Burrowmore.lua.
		-- A souls-like fight: every move has one clear wind-up, one way to dodge
		-- it, and a moment afterwards when he's open. You learn him by losing.
		Color = Color3.fromRGB(0, 153, 219), -- his armour
		DeepColor = Color3.fromRGB(18, 78, 137), -- the armour's shadowed side
		CoreColor = Color3.fromRGB(24, 20, 37), -- the dark behind his visor
		EyeColor = Color3.fromRGB(254, 231, 97), -- the glow in the visor's slit
		TrimColor = Color3.fromRGB(254, 174, 52), -- gold: his trim, his horns and his shovel's blade
		CapeColor = Color3.fromRGB(228, 59, 68), -- his cape

		HealthPunches = 34, -- (a little longer than Oozark's 30: he gives you more openings)
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 10, -- how wide he is for hits (he stands about three times your height)
		WakeRange = 42, -- walk this close and he stands up
		WakeTime = 3.0, -- getting up, pulling his shovel out of the dirt, a twirl, a pose
		WakeSoundLead = 0.3,
		Leash = 78, -- he can go anywhere on the dirt (its edge is 84 out): there's nowhere to hide
		MoveSpeed = { 15, 19 }, -- striding after you between moves, per phase (you run 16-24)
		TurnSpeed = { 300, 430 }, -- degrees a second while he lines up, per phase
		Breather = { { 0.45, 0.8 }, { 0.25, 0.55 } }, -- the pause between moves, per phase

		PhaseAt = 0.5, -- NO QUARTER! at half health his armour cracks and he glows gold
		BreakTime = 2.6,
		BreakShove = 52,
		BreakReach = 30,
		Phase2Recovery = 0.78, -- phase two: every opening is a little shorter
		DesperateAt = 0.2,
		DesperateRecovery = 0.66,
		MeteorAt = 0.3, -- below this much health his final move, the Shovel Meteor, comes
		-- straight away (once), and after that it's one of his moves

		-- His moves. Tell = the wind-up you see before it lands (every one is
		-- longer than your roll's 0.5s). Recovery = how long he's open after it:
		-- that's your chance to hit him. Range = { closest, furthest } he uses it
		-- from; Weight = how often; Phase = 2 only after his armour cracks.
		Attacks = {
			-- SHOVEL DROP, his signature: he jumps high, pointing his shovel down,
			-- and his shadow (a red circle) FOLLOWS you. Lock = how far through the
			-- jump it stops following (it flashes): roll just before he lands. He
			-- bounces once where he lands, then tugs his shovel out of the dirt.
			-- (Air = seconds in the air; Rise = the share of that spent going up;
			-- Hang = extra seconds held at the top; Follow = how fast, in studs a
			-- second, the circle can chase you)
			ShovelDrop = { Tell = 0.55, Air = 1.15, Rise = 0.5, Lock = 0.7, Height = 22, Follow = 30, Radius = 7.5,
				Damage = 24, Knockback = 45, Bounce = 0.55, Recovery = 0.9, Phase = 1, Range = { 0, 70 }, Weight = 6 },
			-- TRIPLE POGO: he crouches and glows, then pogos three times in a row,
			-- each landing aimed at you: roll three times, in rhythm. After the
			-- third he's dizzy (stars round his head) - a big opening.
			TriplePogo = { Tell = 0.8, Hops = 3, Air = 0.7, Ground = 0.12, Rise = 0.45, Lock = 0.55, Height = 12, Follow = 26, Hop = 28, Radius = 6.5,
				Damage = 17, Knockback = 38, Recovery = 1.8, Phase = 1, Range = { 0, 55 }, Weight = 3 },
			-- SHOVEL SWING: he pulls the shovel back over his shoulder and sweeps it
			-- round in front of him (the red wedge on the floor). Roll through it or
			-- step back. A small opening after.
			ShovelSwing = { Tell = 0.6, Commit = 0.7, Reach = 13, Arc = 210, Damage = 20, Knockback = 42, Recovery = 0.55, Phase = 1, Range = { 0, 15 }, Weight = 6 },
			-- DIRT FLING: he digs in (the dirt on his shovel glows orange), then
			-- flings clods in a fan at you. Roll out sideways - or rush in while
			-- he's still digging.
			DirtFling = { Tell = 0.85, Commit = 0.65, Clods = 5, Spread = 11, Flight = 0.75, Near = 14, Far = 48, Radius = 4.5,
				Damage = 15, Knockback = 30, Recovery = 0.65, Phase = 1, Range = { 14, 60 }, Weight = 4 },
			-- ANCHOR TOSS (a relic): he holds up an anchor ("item get!"), swings it
			-- round on its chain, then lobs it at you in a high arc - watch its
			-- shadow. It sticks in the floor and he has to tug it out: a big opening.
			AnchorToss = { Tell = 1.0, Commit = 0.75, Flight = 1.0, Height = 18, Lead = 0.35, Radius = 8,
				Damage = 26, Knockback = 55, Recovery = 1.6, Phase = 1, Range = { 18, 80 }, Weight = 3 },
			-- FIRE STICK (a relic): he raises a wand that sparks, then shoots
			-- fireballs along the floor, each one at you. Roll through them,
			-- step aside, or jump them.
			FireStick = { Tell = 0.7, Balls = 3, Gap = 0.35, Speed = 40, Reach = 80, Radius = 2.4, Height = 3,
				Damage = 15, Knockback = 26, Recovery = 0.8, Phase = 1, Range = { 12, 90 }, Weight = 3 },
			-- CHARGE DASH: he crouches and scrapes his shovel along the ground
			-- (sparks fly) while a red lane shows where he'll go - it follows you,
			-- then flashes and locks. Roll aside late. If he runs into the edge of
			-- the dig he crashes and is dizzy for longer.
			ChargeDash = { Tell = 0.85, Commit = 0.7, Speed = 72, MaxDistance = 80, Overshoot = 18, Width = 5.5,
				Damage = 26, Knockback = 60, Recovery = 1.1, WallStun = 2.0, Phase = 1, Range = { 20, 200 }, Weight = 4 },
			-- TAUNT: now and then he stops, plants his shovel and laughs at you.
			-- Free hits, for anyone patient enough to wait for it.
			Taunt = { Time = 1.9, Phase = 1, Range = { 14, 200 }, Weight = 1.4 },

			-- PHASE TWO ("No Quarter!")
			-- the Shovel Drop again, but he HANGS at the top a moment longer after
			-- the circle locks (it locks as he reaches the top) - to catch anyone
			-- who rolls too early. Roll as he starts to fall.
			DelayedDrop = { Tell = 0.5, Air = 1.0, Rise = 0.55, Hang = 0.55, Lock = 0.36, Height = 24, Follow = 32, Radius = 7.5,
				Damage = 26, Knockback = 48, Bounce = 0.5, Recovery = 0.9, Phase = 2, Range = { 8, 70 }, Weight = 4 },
			-- SWING INTO DROP: a quick Shovel Swing, and straight up into a Shovel Drop
			SwingDrop = { Tell = 0.5, Commit = 0.7, Reach = 13, Arc = 210, SwingDamage = 18, Crouch = 0.2, Air = 1.0, Rise = 0.5, Lock = 0.7,
				Height = 20, Follow = 30, Radius = 7.5, Damage = 24, Knockback = 45, Bounce = 0.5, Recovery = 1.1, Phase = 2, Range = { 0, 16 }, Weight = 5 },
			-- GEM RAIN: he strikes the ground and treasure rains down in marked
			-- circles round you for a few seconds - while he carries on fighting.
			GemRain = { Tell = 0.9, Gems = 16, Gap = 0.22, Fuse = 1.1, Spread = 14, Radius = 5, Damage = 14, Knockback = 26,
				Recovery = 0.35, Phase = 2, Range = { 0, 200 }, Weight = 2.5 },
			-- SHOVEL METEOR, his final move: he jumps right out of sight, and a huge
			-- shadow grows in the middle of the dig. Get to the edge! Afterwards
			-- he's stuck in the ground for a long time.
			ShovelMeteor = { Tell = 0.7, Up = 0.45, Fall = 2.3, Radius = 36, Damage = 38, Knockback = 75, Stuck = 3.2,
				Phase = 2, Range = { 0, 200 }, Weight = 3 },
		},

		Reward = { Power = 2.4, FirstClear = 6 },

		-- the fight's music: add a Sound named "Burrowmore Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Burrowmore Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear", -- no acid rain here, and no sandstorm

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient).
		Sounds = {
			Wake = "Burrowmore Wake", -- the shout as he strikes his pose
			Jump = "Burrowmore Jump", -- leaping into the air
			Land = "Burrowmore Land", -- a Shovel Drop or a pogo landing
			Swing = "Shovel Swing", -- the big swing
			Dig = "Shovel Dig", -- digging in (Dirt Fling)
			Clod = "Dirt Land", -- a clod landing
			Relic = "Relic Get", -- holding up a relic (the anchor, the fire stick)
			Anchor = "Anchor Throw", -- swinging and throwing the anchor
			AnchorLand = "Anchor Land", -- the anchor hitting the floor
			Fire = "Fire Stick", -- each fireball
			Dash = "Burrowmore Dash", -- the charge
			Crash = "Burrowmore Crash", -- running into the edge of the dig
			Taunt = "Burrowmore Laugh", -- his laugh
			Gem = "Gem Land", -- treasure landing
			Meteor = "Shovel Meteor", -- the final move landing
			Break = "Armour Crack", -- NO QUARTER! his armour cracking
			Death = "Burrowmore Death",
		},
	},

	[4] = {
		Name = "Kaze, the Headband Hero",
		Short = "Kaze",
		-- A wandering martial artist (a parody of a certain headband-wearing
		-- world warrior - with his own name, look and moves). He fights like a
		-- fighting-game character: a KI METER that fills when he hits you (and
		-- when you punch thin air near him), special moves that cost a bar of
		-- it, specials he can CHARGE, and CANCELS - cutting one move short into
		-- another. He has his own brain for all that: ServerScriptService/
		-- Bosses/Kaze.lua. His body: ReplicatedStorage/BossBodies/Kaze.lua.
		Color = Color3.fromRGB(255, 255, 255), -- his gi
		DeepColor = Color3.fromRGB(192, 203, 220), -- the gi's folds and shadows
		CoreColor = Color3.fromRGB(24, 20, 37), -- his black belt and eyebrows
		EyeColor = Color3.fromRGB(44, 232, 245), -- his ki: the glow in his eyes and fists
		SkinColor = Color3.fromRGB(232, 183, 150),
		HairColor = Color3.fromRGB(62, 39, 49),
		BandColor = Color3.fromRGB(228, 59, 68), -- the headband (and his gloves)
		Accent = Color3.fromRGB(228, 59, 68), -- the VS splash's colour (his gi's white would be too pale)

		HealthPunches = 36, -- (a little longer than Burrowmore: he gives you fewer free hits)
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 9, -- how wide he is for hits (he stands a bit over twice your height)
		WakeRange = 44, -- walk this close and he stops meditating
		WakeTime = 3.4, -- opens his eyes, stands, bows, drops into his stance ("ROUND 1... FIGHT!")
		WakeSoundLead = 0.3,
		Leash = 58, -- he can go anywhere on the dojo floor (its edge is 62 out)
		MoveSpeed = { 17, 21 }, -- shuffling after you between moves, per round (you run 16-24)
		TurnSpeed = { 420, 560 }, -- degrees a second: he turns fast, like a fighter
		Breather = { { 0.35, 0.7 }, { 0.2, 0.45 } }, -- the pause between moves, per round

		PhaseAt = 0.5, -- ROUND 2 at half health
		BreakTime = 3.0, -- down on one knee, a burst of ki (everyone near is thrown back), "ROUND 2... FIGHT!"
		BreakShove = 44,
		BreakReach = 26,
		Phase2Recovery = 0.8,
		DesperateAt = 0.2,
		DesperateRecovery = 0.7,

		-- THE KI METER (the blue bar at the bottom of your screen): three bars of
		-- `Bar` each. Every special move costs one bar; at a full meter he does
		-- his SUPER. It fills when one of his hits lands on you (Hit), when you
		-- punch thin air within WhiffRange studs of him (Whiff: don't swing
		-- wildly!), a little all the time (Passive, a second), and fast while he
		-- meditates for it (Focus, a second). Every punch you land while he's
		-- meditating or charging knocks FocusHit off it. In ROUND 2 it all fills
		-- Phase2 times as fast.
		Ki = { Bar = 100, Bars = 3, Hit = 45, Whiff = 12, WhiffRange = 16, Passive = 4, Focus = 70, FocusHit = 55, Phase2 = 2 },
		-- CANCELS (the little diamonds under the meter): cutting a move short
		-- into another - a punch string into a special, a fake charge into a
		-- dash, a hop back out of a missed special, one special into another.
		-- He has this many a round; when they run out he's TIRED (hands on his
		-- knees, panting) for Tired seconds - wide open - and then they refill.
		Cancels = { 3, 5 }, -- per round
		Tired = { 2.4, 3.0 }, -- per round
		-- CHARGING: now and then (Chance, per round) he holds a special before
		-- letting it go, glowing brighter and humming higher for Time seconds (a
		-- random amount between the two): the longer, the bigger the move. He
		-- can be hit while he charges - land Breaks punches and the charge
		-- breaks: he staggers for Stagger seconds (and loses ki).
		Charge = { Chance = { 0.4, 0.55 }, Time = { 0.55, 1.1 }, Breaks = 2, Stagger = 1.1 },
		-- ROUND 2: straight from one special into another (Chance, per round)
		Chain = { 0, 0.55 },
		-- KI FLARE: the first time his health drops below this share in each
		-- round, his meter flares straight to MAX ("HAAA!") - so every round
		-- has at least one Super in it, however well you're doing
		SuperAt = { 0.7, 0.25 },
		-- how he gets about: a dash (with afterimages) and a little hop back
		Movement = {
			Dash = { Distance = 14, Time = 0.25 },
			BackHop = { Distance = 12, Time = 0.35, Height = 4, Chance = 0.45 }, -- (Chance: hopping out of a missed special)
		},

		-- His moves. Tell = the wind-up you see before it hits (every one is at
		-- least your roll's half a second). Recovery = how long he's open after
		-- it. Range = { closest, furthest } he uses it from; Weight = how often.
		-- In his SPECIALS (Kaze-Blast, Rising Dragon, Tornado Kick) a pair like
		-- { 2.6, 4.6 } means { not charged, fully charged }.
		Attacks = {
			-- PUNCH STRING: jab, straight, then a heavy ("HYAH!"), each stepping in.
			-- Tells = the wind-up before each hit. Reach = how far his fists go
			-- (from his middle), in a wedge Arc degrees wide in front of him.
			-- After the first or second hit he may CANCEL into a special.
			PunchString = { Tells = { 0.55, 0.4, 0.45 }, Reach = 10, Arc = 150, Step = 3, Damage = { 12, 12, 18 }, Knockback = { 20, 20, 50 },
				Recovery = 0.7, CancelChance = 0.55, Phase = 1, Range = { 0, 13 }, Weight = 5 },
			-- DASH IN: a quick dash at you (white afterimages), straight into a punch string
			DashIn = { Phase = 1, Range = { 11, 42 }, Weight = 2.5 },
			-- KAZE-BLAST!: cups his hands at his hip (a ball of ki grows), then
			-- pushes it out along the floor at you. Jump it or roll through it.
			-- It bursts on a pillar - hide behind one!
			KazeBlast = { Tell = 0.6, Speed = { 40, 52 }, Radius = { 2.6, 4.6 }, Height = { 3, 5 }, Damage = { 18, 28 }, Knockback = { 30, 44 },
				Reach = 90, Recovery = 0.55, Phase = 1, Range = { 12, 200 }, Weight = 3.5 },
			-- RISING DRAGON!: crouches (a red ring round him fills in), then a
			-- spinning uppercut straight up. Back off out of the ring (or roll),
			-- then punish him when he lands. Up high he's out of your reach.
			-- (Active = how long the rising fist hurts; Forward = studs he drifts at you)
			RisingDragon = { Tell = 0.5, Radius = { 6.5, 8 }, Height = { 16, 22 }, Air = { 0.9, 1.1 }, Active = 0.3, Forward = 4,
				Damage = { 26, 34 }, Knockback = { 45, 60 }, Recovery = { 1.1, 1.4 }, Phase = 1, Range = { 0, 11 }, Weight = 3 },
			-- TORNADO KICK!: hops up and spins across the dojo along the red lane
			-- (it follows you until Commit of the wind-up, then locks). Roll
			-- through him or get out of the lane. A pillar stops him.
			TornadoKick = { Tell = 0.55, Commit = 0.7, Distance = { 34, 50 }, Speed = { 38, 44 }, Radius = 5.5, Hop = 3.5,
				Damage = { 20, 26 }, Knockback = { 40, 50 }, Recovery = 0.8, Phase = 1, Range = { 6, 44 }, Weight = 2.5 },
			-- KI FOCUS: plants his feet and shouts "HAAAA..." - his meter shoots
			-- up. RUSH HIM: every punch knocks his ki down, and a couple break it
			-- (he staggers). Time = the longest he meditates for.
			KiFocus = { Time = 2.2, Phase = 1, Range = { 14, 200 }, Weight = 1.8 },
			-- FAKE CHARGE: starts charging a Kaze-Blast... and cancels it (a white
			-- flash) into a dash at you and a punch string. Don't roll too early!
			FakeCharge = { Hold = { 0.4, 0.6 }, Phase = 1, Range = { 12, 32 }, Weight = 1.5 },
			-- SUPER! (only with a full meter): "SUPER!", the screen flashes, he
			-- leaps to the middle of the dojo and fires a giant beam that sweeps
			-- round (Sweep degrees in SweepTime seconds) across the red fan on the
			-- floor. HIDE BEHIND A PILLAR (the beam can't go through one), get out
			-- of the fan, or roll through the beam. Every pillar the beam hits
			-- crumbles afterwards (they're all back for ROUND 2). Then he's
			-- exhausted for Recovery seconds: your big chance.
			-- (Leap = the jump to the middle; Lock = how far through the wind-up
			-- the fan stops following you; Cooldown = the least time between
			-- two Supers - while it lasts, a full meter flashes MAX at you)
			Super = { Leap = 0.6, Tell = 1.8, Lock = 0.8, Sweep = 160, SweepTime = 1.4, Length = 100, Width = 10, Damage = 45, Knockback = 70,
				Recovery = 2.4, Cooldown = 22, Phase = 1, Range = { 0, 200 }, Weight = 0 },
		},

		Reward = { Power = 2.8, FirstClear = 7 },

		-- the fight's music: add a Sound named "Kaze Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Kaze Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient),
		-- except the announcer's (Round1, Round2, Fight, KO, Perfect): those just
		-- stay quiet until you add them.
		Sounds = {
			Wake = "Kaze Wake", -- "HAH!" as he drops into his stance
			Punch = "Kaze Punch", -- a jab or a straight
			Heavy = "Kaze Heavy", -- the third, heavy hit ("HYAH!")
			Blast = "Kaze Blast", -- "KAZE-BLAST!"
			Dragon = "Kaze Dragon", -- "RISING DRAGON!"
			Tornado = "Kaze Tornado", -- "TORNADO KICK!"
			Charge = "Kaze Charge", -- the rising hum while he holds a special
			Cancel = "Kaze Cancel", -- the white flash of a cancel
			Dash = "Kaze Dash", -- a dash, a hop back
			Land = "Kaze Land", -- landing from a jump
			Focus = "Kaze Focus", -- "HAAAAA..." building ki
			Stagger = "Kaze Stagger", -- his charge or focus broken
			Tired = "Kaze Pant", -- out of cancels: panting
			Super = "Kaze Super", -- "SUPER!"
			Beam = "Kaze Beam", -- the beam itself
			Pillar = "Pillar Crumble", -- a pillar breaking
			Break = "Kaze Round Two", -- down on one knee, then the burst of ki
			Death = "Kaze Death", -- his last cry
			Round1 = "Round One", -- the announcer: "ROUND ONE"
			Round2 = "Round Two", -- "ROUND TWO"
			Fight = "Fight", -- "FIGHT!"
			KO = "KO", -- "K.O.!"
			Perfect = "Perfect", -- "PERFECT!" (you beat him without a scratch)
		},
	},

	[5] = {
		Name = "Speedy Revvington, King of the Speedway",
		Short = "Revvington",
		-- A cocky red race car (a parody of a certain famous red race car - with
		-- his own name, number and catchphrase: "Ka-VROOM!"). A DRIVE-BY DUEL:
		-- like a knight on horseback he charges at you, drives past swinging,
		-- rears up, skids round and charges again. He never walks: he drives,
		-- along lines, arcs and skid turns that every screen follows exactly
		-- (ReplicatedStorage/CarPath.lua). His brain: ServerScriptService/
		-- Bosses/Revvington.lua. His body: ReplicatedStorage/BossBodies/Revvington.lua.
		Color = Color3.fromRGB(228, 59, 68), -- his paint
		DeepColor = Color3.fromRGB(162, 38, 51), -- the paint in shadow
		CoreColor = Color3.fromRGB(24, 20, 37), -- tyres, grille, his mouth
		EyeColor = Color3.fromRGB(0, 153, 219), -- his big blue eyes
		StripeColor = Color3.fromRGB(254, 174, 52), -- the lightning bolt down his sides

		HealthPunches = 38,
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 12, -- (his invisible root; hits use his real shape, Car, below)
		Car = { Length = 18, Width = 9, Height = 5 }, -- his body, studs: for his hits and yours
		WakeRange = 45, -- walk this close and the countdown starts
		WakeTime = 4.2, -- 3... 2... 1... GO!
		WakeSoundLead = 0.2,
		Leash = 53, -- his middle stays this far in from the track's middle line (his nose
		-- just touches the tyre wall there - see SpeedwayBuilder: the edge is 62 out)
		Breather = { { 0.25, 0.5 }, { 0.15, 0.35 } }, -- a pause between moves, per round

		PhaseAt = 0.5, -- TURBO! at half health
		BreakTime = 3.0, -- donuts, a blast of nitro (everyone near is thrown back), "TURBO!"
		BreakShove = 50,
		BreakReach = 26,
		Phase2Recovery = 0.75,
		DesperateAt = 0.2,
		DesperateRecovery = 0.65,

		-- How he drives between moves: Cruise = his speed (studs a second, per
		-- round: you run 16-24); SpinRate = how fast he skids round on the spot
		-- (degrees a second, per round - you can hit him while he does);
		-- CircleChance = how often he circles you like a shark instead of
		-- driving off in a line; CruiseAfter = how often he drives off to get
		-- some room after a move, per round.
		Drive = { Cruise = { 46, 58 }, SpinRate = { 260, 360 }, CircleChance = 0.6, CruiseAfter = { 0.65, 0.5 } },

		-- His moves. Tell = the warning before it hits. Recovery = how long he's
		-- open after it. Range = { closest, furthest } he uses it from; Facing =
		-- where you must be (Front: in front of his nose, Rear: behind him,
		-- Side: beside him); Weight = how often. { a, b } = { round 1, TURBO }.
		Attacks = {
			-- CHARGE: he skids round to face you and revs (tyres smoking, a red
			-- lane on the track that follows you, his headlights flash as it
			-- locks at Lock of the Tell), then roars down it, past you, brakes in
			-- a skid and turns round - slowly: your chance. If the lane ends at the
			-- tyre wall he CRASHES into it and is dizzy for CrashStun. TURBO: he
			-- charges twice (Charges).
			Charge = { Tell = { 1.0, 0.8 }, Lock = 0.75, Speed = { 85, 100 }, Overshoot = 24, Damage = 30, Knockback = 70,
				Brake = 0.5, BrakeSlide = 10, TurnAround = { 1.1, 0.7 }, Charges = { 1, 2 }, CrashStun = 2.2, Range = { 22, 400 }, Weight = 5 },
			-- TAIL WHIP: he drives by close beside you (a red strip shows his path)
			-- and as he passes he whips his tail round in a skid - the red
			-- half-circle on your side. Roll through it or get clear. After it he
			-- faces back toward you.
			TailWhip = { Tell = 0.7, Speed = 70, Offset = 7, Whip = 0.35, Radius = 13, Damage = 22, Knockback = 50,
				Recovery = { 0.7, 0.45 }, Range = { 16, 60 }, Weight = 4 },
			-- WHEELIE SLAM (you're close, in front): he rears up on his back wheels
			-- like a horse (a red circle in front of him fills in), then slams
			-- down - and a shock ring rolls out across the track: jump it. He
			-- bounces on his springs a moment after.
			WheelieSlam = { Tell = 0.8, Ahead = 7, Radius = 10, Damage = 28, Knockback = 55,
				WaveSpeed = 34, WaveReach = 26, WaveHeight = 3, WaveThickness = 4, WaveDamage = 14, WaveKnockback = 30,
				Recovery = { 1.1, 0.8 }, Range = { 0, 16 }, Facing = "Front", Weight = 5 },
			-- HONK (you're close, in front): his cheeks puff, then "HONK!!" - a
			-- blast of sound in a cone that throws you back (not much damage).
			Honk = { Tell = 0.6, Reach = 24, Arc = 70, Damage = 10, Knockback = 75, Recovery = 0.6, Range = { 0, 24 }, Facing = "Front", Weight = 3 },
			-- BACKFIRE (you're behind him): his exhaust pipes glow and rumble...
			-- BANG! Fire in a cone behind him, and burning puddles left on the track.
			Backfire = { Tell = 0.7, Reach = 18, Arc = 60, Damage = 20, Knockback = 40,
				Puddles = 3, PuddleRadius = 4.5, PuddleTime = 4, PuddleDamage = 3, PuddleTick = 0.5,
				Recovery = 0.8, Range = { 0, 22 }, Facing = "Rear", Weight = 6 },
			-- SIDE BUMP (you're right beside him): he hops sideways at you - BONK!
			-- (a red half-circle on that side).
			SideBump = { Tell = 0.55, Hop = 3, Radius = 10, Damage = 18, Knockback = 55, Recovery = 0.6, Range = { 0, 14 }, Facing = "Side", Weight = 5 },
			-- DONUTS: showing off for his fans, spinning on the spot in a cloud of
			-- tyre smoke. Free hits!
			Donuts = { Time = 2.2, Range = { 30, 400 }, Weight = 1 },
			-- BURNOUT RING (TURBO): he circles you once, fast, leaving a ring of fire
			-- on the track round you (the flames burn for FlameTime seconds) - then
			-- dashes straight through the middle at you. Jump the flames to get out,
			-- or roll the dash.
			BurnoutRing = { Tell = 0.6, Radius = 20, Lap = 1.7, Flames = 16, FlameRadius = 3.2, FlameTime = 4.5, FlameDamage = 4, FlameTick = 0.5,
				DashSpeed = 100, Damage = 28, Knockback = 65, Phase = 2, Range = { 20, 80 }, Weight = 3 },
		},

		Reward = { Power = 3.2, FirstClear = 8 },

		-- the fight's music: add a Sound named "Revvington Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Revvington Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see
		-- BossClient) - except the crowd, the start lights, the flag and his
		-- engine hum, which just stay quiet until you add them.
		Sounds = {
			Wake = "Revvington Wake", -- "Ka-VROOM!" at GO!
			Rev = "Engine Rev", -- revving before a charge
			Charge = "Revvington Charge", -- the charge's roar
			Skid = "Tire Skid", -- braking, skidding round
			Crash = "Revvington Crash", -- into the tyre wall
			Whip = "Tire Screech", -- the tail whip
			Slam = "Suspension Slam", -- the wheelie coming down
			Honk = "Big Honk", -- HONK!!
			Backfire = "Exhaust Backfire", -- BANG!
			Bump = "Car Bump", -- the side bump
			Donut = "Donut Screech", -- showing off
			Fire = "Fire Whoosh", -- the burnout ring's flames
			Break = "Revvington Turbo", -- TURBO!
			Death = "Revvington Sputter", -- his engine giving out
			Cheer = "Crowd Cheer", -- the fans in the stands
			Engine = "Revvington Engine", -- a LOOPING engine hum (its pitch follows his speed)
			Beep = "Start Beep", -- the start lights: 3... 2... 1...
			Go = "Start Go", -- GO!
			Finish = "Checkered Flag", -- FINISH!
		},
	},

	[6] = {
		Name = "Gridlock, the Final Beat",
		Short = "Gridlock",
		-- A living LEVEL (a parody of a certain famous final level of a certain
		-- rhythm game full of cubes and spikes - with his own name and look): a
		-- giant neon cube with a demon's grin who fights ON THE BEAT, in an
		-- arena that fights too: tiles light up and spike on the beat. He
		-- changes FORM through portals - CUBE (hops and slams), SHIP (bombing
		-- runs, dives), UFO (bursts up, slams down), WAVE (zig-zags leaving a
		-- wall of light) - and now and then the music builds to THE DROP: the
		-- whole floor spikes except the jump pads... then he's stunned.
		-- His brain: ServerScriptService/Bosses/Gridlock.lua. His body:
		-- ReplicatedStorage/BossBodies/Gridlock.lua. The grid, the beat and
		-- the tile patterns: ReplicatedStorage/BeatGrid.lua.
		Color = Color3.fromRGB(255, 0, 68), -- his neon edges
		DeepColor = Color3.fromRGB(24, 20, 37), -- his body
		CoreColor = Color3.fromRGB(104, 56, 108), -- the level's purple
		EyeColor = Color3.fromRGB(254, 231, 97), -- his eyes
		Accent = Color3.fromRGB(44, 232, 245), -- cyan (the VS splash, his chest's icon)

		HealthPunches = 42,
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 10, -- the cube (studs); his other forms are about as big
		WakeRange = 40, -- walk this close to him and the level starts
		WakeTime = 4.4, -- "ATTEMPT 1"... then the beat starts
		WakeSoundLead = 0.2,
		Leash = 52, -- his middle stays this far from the grid's middle (the grid is 120 across)

		-- THE BEAT: everything he does lands on it. Bpm = beats a minute: set it
		-- to your song's tempo, so the level pulses with the music. BeatOffset
		-- (seconds) nudges the beat to line up with the song's first beat.
		Bpm = 128,
		BeatOffset = 0,
		Breather = { { 1, 2 }, { 0, 1 } }, -- beats between moves, per round

		PhaseAt = 0.5, -- GRAVITY FLIP! at half health
		BreakTime = 3.4,
		BreakShove = 55,
		BreakReach = 28,
		Phase2Recovery = 0.75,
		DesperateAt = 0.2,
		DesperateRecovery = 0.65,

		-- His forms: Height = how high he flies (studs above the tiles); the cube
		-- hops Hop tiles a beat, HopHeight high. FormEvery = moves between form
		-- changes (through a portal), DropEvery = moves between drops, FlipEvery
		-- (round 2) = moves between gravity flips, per round.
		Forms = {
			Cube = { Height = 0, Hop = 2, HopHeight = 7 },
			Ship = { Height = 8, Wobble = 1.5 },
			Ufo = { Height = 8, Burst = 3 },
			Wave = { Height = 2.5 },
		},
		FormEvery = { 3, 1 },
		DropEvery = { 6, 5 },
		FlipEvery = 2,
		Ceiling = 44, -- the ceiling grid, studs above the tiles (round 2: he hangs from it)

		-- His moves. Every time is in BEATS. Tell = beats of warning. Recovery =
		-- beats he's open afterwards. Range = { closest, furthest } he uses it
		-- from. Form = the form he must be in; Gravity = -1: only while he hangs
		-- from the ceiling (round 2); Phase = 2: round 2 only. Spikes (tile
		-- attacks) are Height studs tall: jump them, roll through, or be elsewhere.
		Attacks = {
			-- HOP SLAM (cube): the square he'll land on lights up; he crouches, hops
			-- (spinning, like every cube should), SLAMS - and a ring of spikes pops
			-- up round him on the next beat
			HopSlam = { Form = "Cube", Gravity = 1, Tell = 2, Radius = 9, Damage = 28, Knockback = 55,
				Ring = 2, SpikeDamage = 16, SpikeKnockback = 30, Height = 3, Recovery = 2, Range = { 8, 80 }, Weight = 5 },
			-- SPIKE ROWS (cube): a stomp, then rows of spikes march out from him
			-- one tile a beat - along the four straight lines (round 2: the
			-- diagonals too). Stand off the lines, or jump each row on the beat.
			SpikeRows = { Form = "Cube", Gravity = 1, Tell = 1, Rows = 6, Damage = 18, Knockback = 35, Height = 3,
				Diagonals = { false, true }, Recovery = 1, Range = { 0, 45 }, Weight = 4 },
			-- STOMP CHAIN (cube, round 2): three hop slams, one a beat, each square
			-- lit a beat before he lands (the last one with its ring of spikes)
			StompChain = { Form = "Cube", Gravity = 1, Phase = 2, Hops = 3, Radius = 8, Damage = 24, Knockback = 50,
				Ring = 2, SpikeDamage = 16, SpikeKnockback = 30, Height = 3, Recovery = 2, Range = { 8, 80 }, Weight = 4 },
			-- CEILING DROP (round 2, hanging from the ceiling): the square under him
			-- follows you, locks, and he drops out of the sky onto it - a slam and
			-- a ring of spikes. Then he's stuck on the floor a moment: hit him!
			CeilingDrop = { Gravity = -1, Tell = 3, Lock = 2, Radius = 10, Damage = 32, Knockback = 60,
				Ring = 2, SpikeDamage = 16, SpikeKnockback = 30, Height = 3, Stuck = 3, Range = { 0, 400 }, Weight = 6 },
			-- BOMB RUN (ship): a lane of tiles lights up across the grid, through
			-- you; he flies along it dropping a bomb on a tile every beat
			BombRun = { Form = "Ship", Tell = 2, Bombs = 8, Damage = 20, Knockback = 40, Height = 4, Recovery = 1,
				Range = { 0, 80 }, Weight = 5 },
			-- SWOOP (ship): the red lane follows you, locks, and he dives down it,
			-- skimming the tiles (running into you), then climbs away
			Swoop = { Form = "Ship", Tell = 2, Lock = 1, Width = 8, Damage = 28, Knockback = 60, Skim = 1, Recovery = 1,
				Range = { 15, 90 }, Weight = 4 },
			-- UFO SLAM (UFO): hovering over you, bursting up on each beat, the
			-- circle under him follows you... locks, and he slams down. Stuck a moment.
			UfoSlam = { Form = "Ufo", Tell = 4, Lock = 3, Radius = 9, Damage = 30, Knockback = 60, Stuck = 2,
				Range = { 0, 70 }, Weight = 5 },
			-- ORB RAIN (UFO): glowing orbs fall onto lit tiles round you, one a beat
			OrbRain = { Form = "Ufo", Orbs = 6, Warn = 2, Spread = 3, Damage = 18, Knockback = 35, Height = 4, Recovery = 1,
				Range = { 0, 70 }, Weight = 4 },
			-- ZIG-ZAG (wave): a dotted zig-zag shows his path through you; he zooms
			-- along it, one leg a beat, leaving a wall of light that burns for
			-- Trail beats (jump it, or roll through)
			ZigZag = { Form = "Wave", Tell = 2, Legs = 4, Leg = 2, Width = 3, Height = 4, Trail = 4, Damage = 22,
				Knockback = 45, Recovery = 1, Range = { 10, 90 }, Weight = 5 },
			-- TILE PATTERN (any form): THE LEVEL ITSELF. A pattern of tiles lights
			-- up for two beats and spikes on the third - checkers, stripes, rings -
			-- then the other half. Keep moving onto the dark tiles!
			TilePattern = { Tell = 2, Cycles = { 2, 3 }, Damage = 20, Knockback = 30, Height = 3, Range = { 0, 400 }, Weight = 3 },
		},

		-- THE DROP: the music builds for Build beats (he rises to the middle, the
		-- jump pads glow, DROP IN 3... 2... 1...), then EVERY tile spikes except
		-- the jump pads - be on a pad (it throws you up), or in the air, or
		-- rolling. Then he crashes down, STUNNED for Stun beats: free hits!
		Drop = { Build = 4, Damage = 38, Knockback = 50, Height = 5, Rise = 14, Stun = 6 },
		-- The jump pads: step on one and it throws you Power studs a second up
		Pads = { Power = 95, Cooldown = 1.2 },

		Reward = { Power = 4, FirstClear = 10 },

		-- the fight's music: add a Sound named "Gridlock Song" to SoundService
		-- (until you do, Oozark's plays instead) - and set Bpm above to its tempo
		Music = "Gridlock Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see
		-- BossClient) - except the announcer's words, which just stay quiet.
		Sounds = {
			Wake = "Gridlock Wake", -- the level starts
			Hop = "Cube Hop", -- a hop
			Slam = "Cube Slam", -- landing hard
			Spike = "Spikes Up", -- tiles spiking
			Portal = "Portal Whoosh", -- changing form
			Ship = "Ship Thrust", -- flying
			Bomb = "Bomb Drop", -- a bomb bursting on a tile
			Dive = "Ship Dive", -- the swoop
			Burst = "UFO Burst", -- a UFO hop
			Orb = "Orb Land", -- an orb landing
			Zoom = "Wave Zoom", -- the zig-zag
			Build = "Drop Build", -- the music building up
			Drop = "The Drop", -- THE DROP
			Stun = "Gridlock Stun", -- stunned
			Flip = "Gravity Flip", -- the gravity flip
			Pad = "Jump Pad", -- a pad throwing you up
			Break = "Gridlock Break", -- GRAVITY FLIP! (half health)
			Death = "Gridlock Shatter", -- he shatters into cubes
			Attempt = "Attempt Start", -- "ATTEMPT 1"
			Complete = "Level Complete", -- LEVEL COMPLETE!
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
	ArenaWalkSpeed = 20, -- everyone's speed in a fight (Spire, Colosseum, the intro), whatever
	-- their boots or talismans: a boss can only press you if you can't simply outrun it
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

----------------------------------------------------------------------
-- DEV ACCESS: who gets the dev console (the DEV button's test tools).
-- Always you in Studio. In the real game: the game's owner (when a person
-- owns it, not a group) and anyone whose UserId is in DevUserIds (your
-- UserId is the number in your Roblox profile's web address). The SERVER
-- decides: every dev action checks this again, so nobody else can use them
-- even if they hack their screen - the screen only uses it to show the button.
----------------------------------------------------------------------
Config.DevUserIds = {}
function Config.isDev(player)
	local ok, studio = pcall(function()
		return game:GetService("RunService"):IsStudio()
	end)
	if ok and studio then
		return true
	end
	if not player then
		return false
	end
	local owner = false
	pcall(function()
		owner = game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
	end)
	if owner then
		return true
	end
	for _, id in ipairs(Config.DevUserIds) do
		if player.UserId == id then
			return true
		end
	end
	return false
end

return Config
