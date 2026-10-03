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
Config.BaseWalkSpeed = 44 -- your speed outside a fight (the lobby is big: much quicker than Roblox's 16)
-- GRIP: how your character's feet hold the ground (Roblox's ControllerManager
-- movement starts and stops gently by default, which feels floaty at speed).
-- Shorter times = up to speed and stopped quicker; more friction = less slide;
-- a bigger turn factor = sharper turns. (Hud.client.lua applies them.)
Config.Grip = { AccelerationTime = 0.06, DecelerationTime = 0.04, Friction = 2, FrictionWeight = 2, TurnSpeedFactor = 1.6 }
Config.RequireProximity = true -- shops only work when you stand near them
Config.StationRange = 34 -- studs
Config.MaxPrestige = 0 -- (prestige is gone)

-- Where the shops stand. Used by the lobby builder AND by server range checks.
Config.Stations = {
	Upgrades = Vector3.new(-50, -18.5, 330), -- the mushroom house, on the sandy cove south of the castle (the Upgrade Shop was here: it's just a house now)
	Arcade = Vector3.new(75, 0, -41), -- the Arcade (ServerScriptService/ArcadeBuilder), north-east of the fountain
	Prestige = Vector3.new(0, 0, 0),
	Quests = Vector3.new(48, 0, 45), -- the Quest Board, where the Sell Shop was (east of the plaza, up the little path off the road)
}
-- which way each building turns (degrees round the vertical)
Config.StationTurn = {
	Upgrades = 90, -- faces east, towards the stairs and the pier
	Quests = -90, -- faces west, down the little path to the road
}

----------------------------------------------------------------------
-- The Colosseum (a wave arena for farming)
----------------------------------------------------------------------
-- The Spire's ground floor (TRAIN in the Spire menu, at the Spire's doors)
-- takes you to your own fight in the Colosseum: straw dummies
-- hop in wave after wave and try to squash you. Nobody else can see or hit
-- your dummies, and theirs can't hurt you - everyone farms on their own.
-- Dummies are always your level, so a fight takes the same few punches
-- whatever your level; the rewards grow as you do. A quest runs the whole
-- time: BEAT 5 WAVES (a whole run, the King's wave last) for a big lump of
-- Power (XP) and coins, and it starts over with the next run. Pick how hard
-- it is on the CLEARED screen for the next run (it's remembered): Normal,
-- Hard or Nightmare.
Config.Colosseum = {
	-- THE SPIRE'S TRAINING GROUNDS: the Colosseum trains you for your next
	-- floor. While you're below its recommended level, everything in here pays
	-- PerLevel more XP for each level you're short (coins stay the same), up
	-- to Max more (1 = double). (Config.colosseumCatchUp)
	CatchUp = { PerLevel = 0.25, Max = 2 }, -- (under the next floor's level: +25% XP per level short, up to +200%)
	Center = Vector3.new(-2600, 0, 0), -- well away from the lobby and the Spire's arenas
	Radius = 82, -- how far out dummies can go: right up to the foot of the stands, so nowhere is safe
	-- (the way in is the Spire menu's ground floor, at the Spire's doors: the
	-- little Colosseum in the lobby is gone)

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

	HitsToKill = 3, -- punches a dummy takes from a player at its level
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
		health = 10, -- about 30 punches at your level
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

	-- DIFFICULTY: picked on the CLEARED screen for the next run (it's saved,
	-- so you go in on the one you picked last). The first is open to
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
		-- (Normal is the friendly one: softer hits and dummies that go down quicker)
		{ id = "Normal", name = "NORMAL", health = 0.85, damage = 0.7, extra = 0, pace = 1, reward = 1, color = Color3.fromRGB(99, 199, 77) },
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
-- The floor you're training for (the next one you haven't beaten, that's
-- open), and how much more XP the Colosseum pays you for being below its
-- level (0.45 = +45%). cleared = the highest floor you've beaten.
-- The next boss to beat: the first floor not beaten on the lowest tier not
-- finished (`cleared`: a number - Normal's best floor - or the table
-- Config.spireCleared gives). Returns that floor as on its tier (its level).
function Config.nextSpireFloor(cleared)
	if type(cleared) ~= "table" then
		cleared = { Normal = cleared or 0 }
	end
	for _, t in ipairs(Config.Spire and Config.Spire.Tiers or { { id = "Normal" } }) do
		for _, f in ipairs(Config.Spire and Config.Spire.Floors or {}) do
			if f.open and f.id > (cleared[t.id] or 0) then
				return Config.spireFloorFor and Config.spireFloorFor(f.id, t.id) or f
			end
		end
	end
	return nil
end
function Config.colosseumCatchUp(level, cleared)
	local CU = Config.Colosseum.CatchUp
	local f = Config.nextSpireFloor(cleared)
	if not (CU and f) then
		return 0, f
	end
	return math.clamp((f.level - level) * CU.PerLevel, 0, CU.Max), f
end

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
-- Every `Hours` hours the Quest Board offers the same PerDay quests to
-- everyone, picked from the pool below - never two of the same kind at once.
-- You choose ONE of them; finish it, then hand it in at the board for the
-- coins and `Tokens` Arcade Tokens (it gets stamped COMPLETED). A new
-- player's very first choice of dummy quest is always the small one
-- (`First`), so their first token - and their first spin - comes quickly.
--   kind: arena = dummies beaten in the Colosseum, boss = Spire bosses beaten,
--         clear = Colosseum runs cleared
-- (the old "sell" and "open treasure chests" quests are gone: loot and boss
-- chests don't drop any more)
Config.Quests = {
	PerDay = 3,
	Hours = 6,
	Tokens = 1,
	First = "Arena10",
	Pool = {
		{ id = "Arena10", kind = "arena", goal = 10, reward = 80, text = "Beat %d dummies in the Colosseum" },
		{ id = "Arena30", kind = "arena", goal = 30, reward = 150, text = "Beat %d dummies in the Colosseum" },
		{ id = "Arena100", kind = "arena", goal = 100, reward = 400, text = "Beat %d dummies in the Colosseum" },
		{ id = "Boss1", kind = "boss", goal = 1, reward = 300, text = "Defeat a Spire boss" },
		{ id = "Boss3", kind = "boss", goal = 3, reward = 800, text = "Defeat %d Spire bosses" },
		{ id = "Clear1", kind = "clear", goal = 1, reward = 200, text = "Clear a Colosseum run" },
		{ id = "Clear3", kind = "clear", goal = 3, reward = 500, text = "Clear %d Colosseum runs" },
	},
}
Config.QuestById = {}
for _, q in ipairs(Config.Quests.Pool) do
	Config.QuestById[q.id] = q
end

-- which day it is (changes at midnight UTC): the Colosseum's first clear of
-- the day
function Config.questDay(t)
	return math.floor((t or os.time()) / 86400)
end

-- which set of quests is on the board (a new one every Config.Quests.Hours)
function Config.questPeriod(t)
	return math.floor((t or os.time()) / (3600 * (Config.Quests.Hours or 24)))
end

-- when the board's next set of quests comes (os.time)
function Config.nextQuestTime(t)
	return (Config.questPeriod(t) + 1) * 3600 * (Config.Quests.Hours or 24)
end

-- the quests for a given set: the same for everyone, never two of one kind
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
-- the Colosseum and beating bosses - up to MaxLevel. Every level makes you
-- a little stronger at everything (Config.LevelBonus).
-- Total Power for a level = LevelScale x (level - 1) ^ LevelCurve
-- (level 2 needs 18, level 44 about 1.4M, level 256 about 297M, level 500
-- about 2.2 billion). The Spire's levels run 15 to 150 (Normal), then
-- Nightmare 160-250, Eclipse 260-350 and Doom 360-450 (Config.Spire.Tiers);
-- MaxLevel leaves room to grow past Doom's last floor.
----------------------------------------------------------------------
Config.MaxLevel = 500
Config.LevelScale = 17.9
Config.LevelCurve = 3

-- The Power that `levels` more levels take from `level` (fractions too):
-- what a boss win pays (its Reward, counted in levels)
function Config.levelsWorth(level, levels)
	level = math.max(1, level or 1)
	local a = math.max(0, level - 1)
	return math.max(1, math.floor(Config.LevelScale * ((a + (levels or 0)) ^ Config.LevelCurve - a ^ Config.LevelCurve)))
end

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
-- WHAT EVERY LEVEL GIVES YOU (there are no stat points to spend and no
-- armour to wear any more - your level alone makes you stronger at
-- everything; your weapon and its ability do the rest): each level above 1
-- adds these. At level 100 that's +37% damage, +149 health, +7% less damage
-- taken and +37% Power from training.
----------------------------------------------------------------------
Config.LevelBonus = {
	Damage = 0.375, -- % more damage to bosses
	Health = 1.5, -- more max health
	Defense = 0.075, -- % less damage taken (MaxDefense at most)
	Power = 0.375, -- % more Power from training
}
Config.MaxDefense = 60 -- % less damage taken, at most
Config.CritMultiplier = 1.75 -- a critical hit (a weapon's Crit effect) does this much damage

-- what your level gives: { Damage = %, Health = n, Defense = %, Power = % }
function Config.statBonus(d)
	local levels = math.max(0, Config.levelFromPower(d and d.Power or 0) - 1)
	local out = {}
	for k, per in pairs(Config.LevelBonus) do
		out[k] = levels * per
	end
	return out
end

-- (Prestige is gone: levels are the true progress now. These stay only so
-- anything old that asks gets "no bonus".)
function Config.prestigePowerMult()
	return 1
end
function Config.prestigeCoinMult()
	return 1
end

----------------------------------------------------------------------
-- Derived stats (shared so the HUD and the server always agree)
----------------------------------------------------------------------
-- How fast a player moves. In a FIGHT (a Spire arena, the Colosseum, the
-- intro's fight) everyone moves at the same speed, Config.Combat.ArenaWalkSpeed
-- - the fights are about dodging, not outrunning. Outside a fight:
-- BaseWalkSpeed. Every place that sets walk speed asks this, so they can't
-- disagree.
function Config.walkSpeedFor(player, d)
	if player then
		local intro = player:GetAttribute("Intro")
		if player:GetAttribute("SpireFloor") or player:GetAttribute("Colosseum") or intro == "Void" or intro == "Fight" then
			return (Config.Combat and Config.Combat.ArenaWalkSpeed) or 20
		end
	end
	return d and Config.stats(d).walkSpeed or Config.BaseWalkSpeed
end

-- What your level makes of you (Config.LevelBonus): Power from training,
-- max health; and walk speed outside fights. (The Upgrade Shop, talismans
-- and the Sell Shop are gone.)
function Config.stats(d)
	local points = Config.statBonus(d)
	local powerMult = 1 + points.Power / 100
	local walkSpeed = Config.BaseWalkSpeed
	local maxHealth = math.floor(Config.BaseHealth + points.Health)

	return {
		powerMult = powerMult,
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
-- The Spire (boss floors). Floors 1-8 have arenas and bosses; any more
-- would show as sealed in the Spire menu.
----------------------------------------------------------------------
Config.Spire = {
	EnterRange = 38, -- how close to the Spire's doors you must be to enter
	-- each floor opens once you've beaten the boss on the floor below it
	-- (on the same tier), for everyone - Studio and devs too
	RequirePrevious = true,
	-- true = devs (Studio, the game's owner) can enter any floor, to test them
	DevSkip = false,
	-- each floor also stays locked until you reach its level (floor 1, Oozark:
	-- Lv 15) - the Colosseum, the ground floor, is where you train up to it
	LevelLock = true,
	-- THE HORIZON: in every arena the far distance melts into that arena's own
	-- sky (its Atmosphere colour), so the other islands - the lobby, the other
	-- floors - are never seen, while the arena itself stays crisp. Density is
	-- how thick the air is (higher hides things nearer), Offset how fully far
	-- things blend into the sky (1 = completely), Haze a soft glowing band
	-- along the horizon. These are the least every arena gets; a floor's own
	-- ambience.Atmosphere can ask for more (the sandstorm does), and a floor
	-- can set its own with ambience.Horizon = { Density = ..., ... }.
	Horizon = { Density = 0.46, Offset = 0.92, Haze = 2 },
	Floors = {
		{
			id = 1,
			boss = "Oozark, the Gelatinous Tyrant",
			area = "Oozark's Hollow",
			level = 15, -- recommended level
			blurb = "A bloated slime king rules the drowned colosseum beneath the Spire. It is slow to anger, and slower to die.",
			color = Color3.fromRGB(120, 230, 90),
			open = true,
			-- a damp, green-grey hollow under the Spire (the acid rain is BossClient's)
			ambience = {
				Atmosphere = {
					Color = Color3.fromRGB(168, 196, 172),
					Decay = Color3.fromRGB(92, 122, 104),
					Glare = 0,
				},
				Tint = Color3.fromRGB(246, 255, 246),
				Saturation = 0.04,
				Contrast = 0.04,
				Grains = 0, -- (no drifting dust: the rain is enough)
				Clouds = false,
			},
		},
		{
			id = 2,
			boss = "Tuber",
			area = "The Sunken Dunes",
			level = 30,
			blurb = "A sunny cactus desert. In a little garden at its heart naps Tuber, a chubby cactus with a flower on his head. He looks harmless. The desert knows better.",
			color = Color3.fromRGB(99, 199, 77),
			open = true,
			-- how the arena looks and sounds on your screen while you're in it
			-- (ArenaAmbience puts the lobby's look back when you leave)
			ambience = {
				ClockTime = 15.6, -- a hot afternoon sun, turning golden
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
				-- THE SANDSTORM. Just a breeze while little Tuber fights - but when
				-- he powers up, a wall of sand rolls in across the arena and whips
				-- round him while the cactus flies, then settles to a haze for the
				-- Brute (BossBodies/Tuber decides how hard it blows, and when).
				Storm = {
					Front = true, -- the wall of sand you see rolling in (false: it just thickens)
					FrontSpeed = 55, -- how fast the wall crosses the arena, studs a second
					-- the air at the storm's height: Density is how thick (0..1) - the
					-- higher, the less you can see. 0.85 is a fog: things are clear up
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
				Horizon = { Density = 0.5, Offset = 1, Haze = 2.4 }, -- (the void swallows everything past the grid)
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
		{
			id = 7,
			boss = "Kongo, the Jungle Brawler",
			area = "Kongo's Jungle Village",
			level = 105,
			blurb = "A village of huts on stilts in a jungle clearing, a waterfall thundering behind it. Its king is a huge gorilla in a red tie, and he has never lost a fight in his clearing. The whole village comes to watch.",
			color = Color3.fromRGB(115, 62, 57),
			open = true,
			-- a warm afternoon in the jungle: sun through the leaves, a green
			-- haze, and leaves drifting past on the breeze
			ambience = {
				ClockTime = 15.8,
				Atmosphere = {
					Density = 0.3,
					Offset = 0.12,
					Color = Color3.fromRGB(206, 232, 186),
					Decay = Color3.fromRGB(120, 164, 110),
					Glare = 0.25,
					Haze = 1.4,
				},
				Tint = Color3.fromRGB(255, 246, 226),
				Saturation = 0.14,
				Contrast = 0.05,
				Sand = Color3.fromRGB(99, 199, 77), -- (the "dust" here is leaves)
				Grains = 0.18,
				Clouds = false,
				Wind = Vector3.new(0.6, 0, 1),
				Sound = "Jungle Ambience", -- birds and the waterfall, looping, if you add one
				Volume = 0.35,
			},
		},
		{
			id = 8,
			boss = "Petalina, the Blooming Terror",
			area = "The Glasshouse Garden",
			level = 120,
			blurb = "A giant glass greenhouse full of sunlight and flower beds. In the middle grows a flower taller than a house, with the sweetest smile you've ever seen. Don't trust the smile.",
			color = Color3.fromRGB(246, 117, 122),
			open = true,
			-- a bright midday under glass: warm sunlight, a soft golden haze,
			-- and pollen drifting in the air
			ambience = {
				ClockTime = 12.6,
				Atmosphere = {
					Density = 0.26,
					Offset = 0.1,
					Color = Color3.fromRGB(240, 244, 214),
					Decay = Color3.fromRGB(184, 206, 150),
					Glare = 0.35,
					Haze = 1.2,
				},
				Tint = Color3.fromRGB(255, 250, 236),
				Saturation = 0.16,
				Contrast = 0.04,
				Sand = Color3.fromRGB(255, 236, 140), -- (the "dust" here is pollen)
				Grains = 0.14,
				Clouds = false,
				Wind = Vector3.new(0.2, 0, 0.4),
				Sound = "Greenhouse Ambience", -- birdsong and dripping water, looping, if you add one
				Volume = 0.35,
			},
		},
		{
			id = 9,
			boss = "Scribble, the 4th-Dimensional Doodle",
			area = "The Canvas",
			level = 135,
			blurb = "A giant sheet of graph paper inside a paint program, floating over a computer desktop. It belongs to a stick figure who knows he's inside a video game - and he'll use the whole game against you.",
			color = Color3.fromRGB(0, 153, 219),
			open = true,
			-- inside a computer: bright, clean light, a pale blue haze, and
			-- scraps of paper drifting past
			ambience = {
				ClockTime = 13,
				Atmosphere = {
					Density = 0.22,
					Offset = 0.08,
					Color = Color3.fromRGB(214, 234, 255),
					Decay = Color3.fromRGB(140, 180, 230),
					Glare = 0.2,
					Haze = 1.0,
				},
				Tint = Color3.fromRGB(248, 252, 255),
				Saturation = 0.1,
				Contrast = 0.06,
				Sand = Color3.fromRGB(255, 255, 255), -- (the "dust" here is scraps of paper)
				Grains = 0.1,
				Clouds = false,
				Wind = Vector3.new(0.3, 0, 0.6),
				Sound = "Desktop Hum", -- a quiet computer fan, looping, if you add one
				Volume = 0.3,
			},
		},
		{
			id = 10,
			boss = "King Gavelgrunt, Lord of the Spire",
			area = "The Throne Summit",
			level = 150,
			blurb = "The very top of the Spire: a stone courtyard above the clouds, a golden throne, and a thunderstorm that never ends. Its king - a colossal, scarred walrus with an iron war-gavel - has watched you climb every floor. He does not share his tower.",
			color = Color3.fromRGB(104, 56, 108),
			open = true,
			-- a THUNDERSTORM above the clouds at dusk, the moment you walk in: dark
			-- blue-grey light, heavy cloud, the wind whipping spray past (his body
			-- file adds the rain, the lightning and the thunder, darkens it more
			-- in round 2 and turns it into a red eclipse in round 3)
			ambience = {
				ClockTime = 16.5, -- (a stormy late afternoon: dark enough to feel it, light enough to see him)
				Atmosphere = {
					Density = 0.2,
					Offset = 0.3,
					Color = Color3.fromRGB(100, 110, 134),
					Decay = Color3.fromRGB(70, 80, 106),
					Glare = 0,
					Haze = 0.7,
				},
				Tint = Color3.fromRGB(214, 222, 240),
				Saturation = -0.05,
				Contrast = 0.12,
				Sand = Color3.fromRGB(192, 203, 220), -- (the "dust" here is wind-blown spray and cloud)
				Grains = 0.35,
				Clouds = true,
				Wind = Vector3.new(1.0, 0, 0.35),
				Sound = "Summit Wind", -- a howling storm wind, looping, if you add one
				Volume = 0.3,
			},
		},
	},
}

-- THE HARDER SPIRE: after King Gavelgrunt falls, the whole Spire again -
-- NIGHTMARE, then ECLIPSE, then DOOM. Same floors, same bosses and moves,
-- at higher levels (floor 1 at `start`, then `step` more a floor), and
-- tougher than the level alone makes them:
--   health  takes this many times the punches a Normal fight does (for a
--           player at the floor's level - their level's damage bonus is
--           already allowed for)
--   damage  their hits take this many times the share of your health a
--           Normal hit does (your level's health and defence allowed for)
--   pace    recoveries and chasing: x this long (0.8 = 20% quicker)
--   reward  the win's levels (Reward) x this - the floors are closer together
--   tokens  Arcade Tokens for each floor's first win on this tier
-- A tier's floor 1 opens once the tier before it is beaten to the top;
-- after that, floor by floor as in Normal. Your best floor on each is the
-- player's SpireCleared (Normal) / SpireCleared_<id> attribute.
Config.Spire.Tiers = {
	{ id = "Normal", name = "NORMAL", color = Color3.fromRGB(255, 63, 164), health = 1, damage = 1, pace = 1, reward = 1 },
	{ id = "Nightmare", name = "NIGHTMARE", color = Color3.fromRGB(229, 57, 74), start = 160, step = 10, health = 1.25, damage = 1.3, pace = 0.85, reward = 0.7, tokens = 2,
		blurb = "The Spire's bosses, back from the dead and angrier. Faster, tougher, and they hit harder." },
	{ id = "Eclipse", name = "ECLIPSE", color = Color3.fromRGB(141, 75, 255), start = 260, step = 10, health = 1.5, damage = 1.6, pace = 0.75, reward = 0.7, tokens = 3,
		blurb = "The sun has gone out over the Spire. Every boss is quicker still, and one mistake costs a lot." },
	{ id = "Doom", name = "DOOM", color = Color3.fromRGB(150, 20, 30), start = 360, step = 10, health = 1.8, damage = 2, pace = 0.65, reward = 0.7, tokens = 5,
		blurb = "The last climb. Bosses at their very worst - only the strongest reach the top." },
}

-- a tier by id (Normal if it's not one)
function Config.spireTier(id)
	for i, t in ipairs(Config.Spire.Tiers) do
		if t.id == id then
			return t, i
		end
	end
	return Config.Spire.Tiers[1], 1
end

-- a floor's recommended level on a tier
function Config.spireLevel(floorId, tierId)
	local t = Config.spireTier(tierId)
	local f = Config.Spire.Floors[floorId]
	if not t.start then
		return f and f.level or 1
	end
	return t.start + t.step * ((floorId or 1) - 1)
end

-- A player's level as the server keeps it (their leaderstats), for the
-- Spire's level lock (Config.Spire.LevelLock)
function Config.levelOf(player)
	local ls = player and player:FindFirstChild("leaderstats")
	local lv = ls and ls:FindFirstChild("Level")
	return lv and lv.Value or 1
end
-- Is this floor (on this tier) still above the player's level? Returns the
-- level it needs, or nil if they can go in.
function Config.spireLevelLocked(player, floorId, tierId)
	if not Config.Spire.LevelLock then
		return nil
	end
	local need = Config.spireLevel(floorId, tierId)
	if Config.levelOf(player) < need then
		return need
	end
	return nil
end

-- a floor as it is on a tier: a copy with that tier's level (and its id)
function Config.spireFloorFor(floorId, tierId)
	local f = Config.Spire.Floors[floorId]
	if not f then
		return nil
	end
	local t = Config.spireTier(tierId)
	if t.id == "Normal" then
		return f
	end
	local copy = table.clone(f)
	copy.level = Config.spireLevel(floorId, t.id)
	copy.tier = t.id
	return copy
end

-- (a player at level L: their punch's level bonus, their health and the
-- share of a hit they take - Config.LevelBonus)
local function atLevel(level)
	local n = math.max(0, level - 1)
	local B = Config.LevelBonus
	return 1 + B.Damage * n / 100, (Config.BaseHealth or 100) + B.Health * n, 1 - math.min(B.Defense * n, Config.MaxDefense or 60) / 100
end

-- a boss's health on a tier, x its Normal health (for a player at the level)
function Config.spireTierHealth(floorId, tierId)
	local t = Config.spireTier(tierId)
	if t.id == "Normal" then
		return 1
	end
	local dmgN = atLevel(Config.spireLevel(floorId, "Normal"))
	local dmgT = atLevel(Config.spireLevel(floorId, t.id))
	return t.health * dmgT / dmgN
end

-- a boss's hits on a tier, x their Normal damage (so each takes `damage` x
-- the share of your health a Normal hit takes, at the floor's level)
function Config.spireTierDamage(floorId, tierId)
	local t = Config.spireTier(tierId)
	if t.id == "Normal" then
		return 1
	end
	local _, hpN, takeN = atLevel(Config.spireLevel(floorId, "Normal"))
	local _, hpT, takeT = atLevel(Config.spireLevel(floorId, t.id))
	return t.damage * (hpT / hpN) * (takeN / takeT)
end

-- the attribute that keeps a player's best floor on a tier
function Config.spireClearedKey(tierId)
	return (tierId == nil or tierId == "Normal") and "SpireCleared" or ("SpireCleared_" .. tierId)
end

-- a player's best floor on every tier: { Normal = 10, Nightmare = 3, ... }
function Config.spireCleared(player)
	local out = {}
	for _, t in ipairs(Config.Spire.Tiers) do
		out[t.id] = (player and player:GetAttribute(Config.spireClearedKey(t.id))) or 0
	end
	return out
end

-- Can this tier be played at all? (the tier before it beaten to the top)
function Config.spireTierOpen(cleared, tierId)
	local _, i = Config.spireTier(tierId)
	if i <= 1 then
		return true
	end
	local before = Config.Spire.Tiers[i - 1]
	return (cleared[before.id] or 0) >= #Config.Spire.Floors
end

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
	Title = "DEFEAT A BOSS",
	Subtitle = "TO GROW",
	Blip = "UI Blip", -- a short blip on clicks, if you add a Sound with this name to SoundService
	-- the lobby in the same look (RetroWorld - only on your screen, only how
	-- things look: nothing is moved, and nothing solid changes)
	World = {
		On = true,
		Palette = true, -- the lobby's colours snapped to the same palette as the menus
		Flat = true, -- realistic textures (cobblestone, slate, metal...) become flat colour
		Motes = 36, -- glowing pixel cubes drifting around you (0 = none)
		SaveStar = false, -- (off: the spinning pixel star over the spawn - the user had it removed; true brings it back)
		Flavour = false, -- (off: a line of text typed out when you walk up to a place - the user found it useless; true brings it back)
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

-- THE HEART: your health on screen, as red liquid inside a pixel heart
-- (ReplicatedStorage/Vitals draws it, for Hud).
Config.Heart = {
	Pixel = 5, -- screen pixels per pixel of the heart (bigger = a bigger heart)
	Drain = 1.2, -- how fast it drains after a hit (a whole heart a second, x this)
	Fill = 0.5, -- how fast it fills when you heal
	Slosh = 1.6, -- how wildly the liquid can slosh
	Drops = 36, -- drops spilled per whole heart lost (a hit spills at least 3...)
	MaxDrops = 12, -- ...and at most this many
	Low = 0.25, -- below this much health it beats and its outline blinks red
}

-- In a fight, either side of the heart (ReplicatedStorage/Vitals): your
-- flasks as a pixel POTION on its left and your stamina as a pixel LIGHTNING
-- BOLT on its right. They use the heart's pixel size (Heart.Pixel above).
Config.Vitals = {
	Gap = 10, -- screen pixels between the heart and the potion / the bolt
	Follow = 16, -- how quickly the bolt's level keeps up with your stamina (higher = snappier)
	Sparks = true, -- little sparks crackling off the bolt while it's full
	Tip = 60, -- how far (degrees) the potion tips over to pour into the heart
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
-- It drops a chest with your first Arcade Token in it, the mist rolls back and the lobby builds
-- itself around you, piece by piece - and the Spire last: OOZARK AWAITS...
-- You can't lose (Oozlet never takes you below Floor of your health), and
-- only brand-new players get it (beating it is saved). IntroService runs
-- the fight; IntroClient draws all of it, on that player's screen only.
Config.Intro = {
	On = true, -- false: nobody gets the intro (new players start in the lobby)
	-- In Roblox Studio: false = it never starts by itself (watch it any time
	-- with the dev console's "DEV: Replay Intro"); true = every Play starts
	-- with it. (Studio often can't save - no API access - so otherwise every
	-- Play would look like a brand-new player's.) In the real game only
	-- brand-new players get it, whatever this says.
	InStudio = false,

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
		PunchHow = { Mouse = "CLICK TO PUNCH", Touch = "TAP THE RED BUTTON", Gamepad = "PRESS R2 TO PUNCH" },
		RollHow = { Mouse = "PRESS SHIFT TO ROLL", Touch = "TAP ROLL", Gamepad = "PRESS B TO ROLL" },
	},

	-- The end: the mist rolls back and the lobby builds itself round you
	Reveal = {
		Delay = 3.6, -- seconds after Oozlet pops before the mist starts to go (the token chest lands and opens)
		Time = 8, -- how long the mist takes to roll back across the whole island
		Reach = 600, -- how far it rolls (past the island's edge)
		Spire = 3.4, -- the look at the Spire at the very end (OOZARK AWAITS...)
	},

	-- What beating it gives you
	Reward = {
		Tokens = 1, -- the chest Oozlet drops holds your first Arcade Token (a spin at the Arcade)
		Coins = 100,
		Level = 5, -- you're at least this level after
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

		-- What a kill is worth, in LEVELS at the floor's recommended level (Power
		-- = every win, FirstClear = on top the first time; a harder Spire's
		-- tier multiplies it: Config.Spire.Tiers' reward).
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
		Name = "Tuber",
		Short = "Tuber",
		-- TUBER (a parody of a certain famous stack of cactus from a certain
		-- famous plumber's games - with his own name and look): a chubby,
		-- potato-shaped little cactus stack with a flower on his head. He looks
		-- like a joke... until his first health bar runs out. Then every cactus
		-- in the desert rips out of the ground and flies to him, and he rebuilds
		-- himself into THE BRUTE, THE CACTUS KING: a giant cactus golem who
		-- fights from a distance - walls of cactus, needle turrets, rolling
		-- balls, quicksand - and keeps hopping away from you. (TUBER and BRUTE
		-- are the same five letters: watch them swap places.)
		-- His brain: ServerScriptService/Bosses/Tuber.lua. His body:
		-- ReplicatedStorage/BossBodies/Tuber.lua. His arena: DunesBuilder.
		Round2Name = "The Brute, the Cactus King", -- the name on his second health bar
		VictoryName = "The Brute", -- the banner when you win: THE BRUTE VANQUISHED
		Color = Color3.fromRGB(99, 199, 77), -- his cactus green
		DeepColor = Color3.fromRGB(62, 137, 72), -- the green of his lumps and shadows
		CoreColor = Color3.fromRGB(38, 92, 66), -- the golem's dark green
		EyeColor = Color3.fromRGB(24, 20, 37), -- Tuber's little dot eyes
		FlowerColor = Color3.fromRGB(246, 117, 122), -- the flower on his head
		RageColor = Color3.fromRGB(255, 0, 68), -- the Brute's glowing eyes (and his warnings)
		CrownColor = Color3.fromRGB(254, 174, 52), -- the Cactus King's crown
		SpineColor = Color3.fromRGB(234, 212, 170), -- his spines

		-- BOTH bars together, in punches at your recommended power (see PhaseAt)
		HealthPunches = 40,
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 8, -- little Tuber (the Brute's size is below)
		WakeRange = 45,
		WakeTime = 3.0, -- he pops up out of his garden, yawns, and waves
		WakeSoundLead = 0.3,
		Leash = 96, -- he stays this far from the middle of the arena (its wall is 150 out)
		MoveSpeed = { 7, 0 }, -- Tuber waddles after you (studs a second); the Brute never walks: he hops
		TurnSpeed = { 200, 300 }, -- degrees a second, per round

		-- THE TWO BARS: his first bar is the top 38% of his health (PhaseAt =
		-- 0.62), the Brute's is the other 62%. When the first runs out: the
		-- POWER-UP, BreakTime seconds long (nobody can be hurt while it plays).
		PhaseAt = 0.62,
		BreakTime = 9.0,
		BreakShove = 60, -- the golem standing up throws everyone near back...
		BreakReach = 34, -- ...this far
		Phase2Recovery = 0.85,
		DesperateAt = 0.19, -- (his RAGE: 30% of the Brute's bar)
		DesperateRecovery = 0.7,
		Breather = { { 1.5, 2.3 }, { 0.5, 1.0 } }, -- seconds between moves: easy little Tuber, then the Brute
		RageBreather = { 0.3, 0.7 },
		-- the golem: how tall and wide his body is (for your punches and the
		-- lock-on camera). Reach = how far out from his middle you can hit him.
		Brute = { Height = 24, Width = 14, Reach = 6.5 },

		-- His moves. Tell = the warning before it lands (always longer than your
		-- roll's 0.5s). Recovery = how long he's open afterwards. Range =
		-- { closest, furthest } he uses it from. Phase = 1: little Tuber's
		-- (round 1), 2: the Brute's (round 2). Anything given as { a, b } in
		-- round 2 is { normal, in a RAGE }.
		Attacks = {
			-- WOBBLE BONK: leans back... and flops his head forward (the red wedge). Step aside.
			Bonk = { Tell = 1.0, Lock = 0.25, Reach = 11, Arc = 80, Damage = 14, Knockback = 40, Recovery = 1.3,
				Range = { 0, 14 }, Weight = 5, Phase = 1 },
			-- CLUMSY TOPPLE: falls flat along the red lane like a tree, then lies
			-- there flailing - free hits all along him - and struggles back up
			Topple = { Tell = 1.2, Lock = 0.35, Fall = 0.35, Length = 12, Width = 6, Damage = 20, Knockback = 45,
				Down = 2.4, Rise = 0.9, Range = { 5, 26 }, Weight = 4, Phase = 1 },
			-- NEEDLE SNEEZE: "ah... ah... ACHOO!" - a ring of needles. Jump it or roll through.
			Sneeze = { Tell = 1.3, Reach = 26, Speed = 24, Thickness = 2.5, Height = 3.2, Damage = 12, Knockback = 30,
				Recovery = 1.0, Range = { 0, 22 }, Weight = 4, Phase = 1 },
			-- BOUNCE STOMP: springs up and lands on the red circle (with a little ring of sand to jump)
			Stomp = { Crouch = 0.55, Air = 1.05, Height = 12, Radius = 8, Damage = 16, Knockback = 40, RingReach = 12,
				RingDamage = 8, Recovery = 1.1, Range = { 8, 40 }, Weight = 4, Phase = 1 },
			-- SPLIT!: pops into three cactus balls that spin-dash at you one after
			-- another (each bounces once off a rock or the edge) - jump them or roll -
			-- then sit there dizzy (free hits: punch any of them) and hop back into
			-- a stack. His special: never picked at random - he splits after
			-- every Every other moves.
			Split = { Shake = 0.6, Pop = 0.5, Spread = 7, Rev = 0.9, Gap = 0.85, Speed = 50, Length = 110, Radius = 2.4,
				Height = 4, Damage = 18, Knockback = 45, Dizzy = 2.2, Restack = 0.9, Every = 2,
				Range = { 10, 70 }, Weight = 0, Phase = 1 },

			-- NEEDLE VOLLEY: a red cone, then three fans of needles. Roll sideways - a rock or a wall stops them.
			Volley = { Tell = 0.8, Lock = 0.2, Shots = 3, Gap = 0.28, Needles = 5, Spread = 40, Speed = 70, Reach = 90,
				Radius = 1, Height = 3.5, Damage = 10, Knockback = 20, Recovery = 0.6, Range = { 14, 999 }, Weight = 5, Phase = 2 },
			-- DESERT RAIN: spits cactus balls into the sky; they land on the red circles round you
			Rain = { Spit = 0.8, Drops = { 7, 10 }, Gap = 0.22, Fall = 1.25, Radius = 6, Spread = 16, Damage = 16,
				Knockback = 30, Recovery = 0.5, Range = { 10, 999 }, Weight = 4, Phase = 2 },
			-- SPINE LANCE: charges up - the red line follows you, then locks and flashes -
			-- and fires a giant spike across the arena. Dodge late. A rock stops it.
			Lance = { Charge = 1.4, Lock = 0.5, Speed = 150, Width = 5, Height = 5, Damage = 30, Knockback = 65,
				Recovery = 1.0, Range = { 20, 999 }, Weight = 3, Phase = 2 },
			-- CACTUS WALL: a wall bursts up between you and him. Go round it, or punch
			-- its glowing weak spot (Punches punches). Touching it pricks. In a rage it creeps toward you.
			Wall = { Tell = 1.0, Length = { 40, 48 }, Segment = 4, Height = 7, Thick = 2.5, At = 0.45, RiseDamage = 14,
				TouchDamage = 8, Knockback = 40, Life = { 14, 12 }, Slide = { 0, 3 }, Max = { 2, 3 }, Punches = 2,
				Range = { 16, 999 }, Weight = 3, Phase = 2 },
			-- NEEDLE TURRETS: little cactus towers sprout round you and shoot needles
			-- (a thin red line first). Punches punches each.
			Turrets = { Plant = { 2, 3 }, Max = { 3, 4 }, Grow = 0.9, Near = 22, Far = 30, Every = 2.4, First = 1.6,
				Warn = 0.7, Speed = 80, Reach = 80, Radius = 1, Height = 3.5, Damage = 10, Knockback = 20, Life = 26,
				Punches = 2, Range = { 14, 999 }, Weight = 3, Phase = 2 },
			-- BALL HERD: spinning cactus balls roll in from the edge at you, bouncing off rocks and walls. Jump or roll.
			Herd = { Balls = { 3, 5 }, Show = 0.6, Gap = 0.35, Tell = 0.9, Speed = 46, Bounces = 2, Length = 170,
				Radius = 2.6, Height = 4.5, Damage = 16, Knockback = 50, Range = { 10, 999 }, Weight = 3, Phase = 2 },
			-- PRICKLY BUDDIES: little cactus minions waddle after you and pop into
			-- needles if they reach you. Punches punches each.
			Buddies = { Spawn = { 2, 3 }, Max = { 3, 4 }, Land = 0.9, Speed = 10, Trigger = 4.5, Puff = 0.7, Radius = 7,
				Damage = 14, Knockback = 45, Life = 18, Punches = 1, Range = { 14, 999 }, Weight = 2, Phase = 2 },
			-- QUICKSAND: swirling sand opens up between you and him: it drags you in
			-- (Pull: studs a second at its edge and its middle - you run 20) and nibbles at you
			Quicksand = { Patches = { 2, 3 }, Max = { 3, 4 }, Warn = 0.8, Radius = 10, Life = 12, Pull = { 5, 9 },
				Damage = 4, Tick = 0.6, Range = { 18, 999 }, Weight = 2, Phase = 2 },
		},
		-- The Brute's moves that aren't picked at random (see Bosses/Tuber.lua)
		Moves = {
			-- ROOT HOP: get within Trigger studs and he leaps away (landing Want
			-- studs from you if he can, never under Min), then it takes Cooldown
			-- seconds to recharge ({ normal, rage })
			RootHop = { Trigger = 16, Tell = 0.55, Air = 1.35, Height = 34, Plant = 0.5, Radius = 7, Damage = 22,
				Knockback = 50, RingReach = 16, RingSpeed = 30, RingDamage = 14, Cooldown = { 7, 5 }, Want = 58, Min = 36 },
			-- SHOVE BURST: right next to him with his hop recharging? His spines blast you back.
			ShoveBurst = { Tell = 0.6, Radius = 11, Damage = 10, Knockback = 70, Recovery = 0.5 },
			-- CORNERED: catch him before his hop recharges and he panics for Panic
			-- seconds (free hits!), then blasts you back and escapes. Once every Cooldown seconds.
			Cornered = { Panic = { 2.4, 1.8 }, Cooldown = 10 },
			-- STUNNED: break the last of his walls and turrets (after breaking at
			-- least Needs) and he's out of cactus: Time seconds of free hits, and no
			-- new walls or turrets for NoCacti more
			Stunned = { Time = 5.5, NoCacti = 6, Needs = 2 },
			-- RAGE: at this share of the Brute's bar, he roars (needles fly off him)
			Rage = { At = 0.3, Time = 1.6, Reach = 30, Damage = 10 },
		},

		Reward = { Power = 2.0, FirstClear = 5 },

		-- The fight's music. Round 1: add a cute, bouncy Sound named "Tuber Song"
		-- to SoundService (until you do, Oozark's plays). The power-up goes
		-- quiet, and round 2's song slams in the moment THE BRUTE is named.
		-- (Capitals and spaces don't matter.)
		Music = "Tuber Song",
		Round2Music = "SANDWORMSONG",
		MusicVolume = 0.8,
		Round2MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		-- a breeze in round 1; the power-up whips up a sandstorm (ArenaAmbience)
		Weather = "Sandstorm",

		-- His sounds: the names of Sounds in SoundService. They're the sounds you
		-- already have from the old worm; any you haven't added borrow one of
		-- Oozark's instead.
		Sounds = {
			Wake = "Worm Erupt", -- popping up out of his garden
			Bonk = "SandWhip", -- the wobble bonk
			Crash = "Worm Slam", -- toppling over, stomping down, the Brute landing
			Sneeze = "SandWhip", -- ACHOO! (and every ring of needles)
			Split = "Worm Crack", -- popping apart
			Roll = "Worm Charge", -- a cactus ball spin-dashing
			Stack = "Worm Devour", -- snapping back together
			Rumble = "SandRumble", -- the ground rumbling in the power-up
			Rip = "Worm Erupt", -- a cactus ripping out of the ground
			Form = "Worm Devour", -- the golem forming
			Break = "Worm Crack", -- the power-up's big burst
			Roar = "SandRoar", -- THE BRUTE roars
			Hop = "Worm Charge", -- his roots ripping up for a hop
			Needle = "SandWhip", -- needles firing
			Lance = "Worm Charge", -- the spine lance
			Wall = "Worm Erupt", -- a cactus wall bursting up
			Pop = "Worm Crack", -- a wall, turret or buddy breaking
			Death = "Worm Death",
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
		SoundVolume = 0.7, -- his sounds, a little quieter than the other bosses' (1 = the same)
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
		-- A cocky orange muscle car with white racing stripes (his own name,
		-- number, colours and catchphrase: "Ka-VROOM!"). A DRIVE-BY DUEL:
		-- like a knight on horseback he charges at you, drives past swinging,
		-- rears up, skids round and charges again. He never walks: he drives,
		-- along lines, arcs and skid turns that every screen follows exactly
		-- (ReplicatedStorage/CarPath.lua). His brain: ServerScriptService/
		-- Bosses/Revvington.lua. His body: ReplicatedStorage/BossBodies/Revvington.lua.
		Color = Color3.fromRGB(247, 118, 34), -- his orange paint
		DeepColor = Color3.fromRGB(190, 74, 40), -- the paint in shadow
		CoreColor = Color3.fromRGB(24, 20, 37), -- tyres, grille, his mouth
		EyeColor = Color3.fromRGB(99, 199, 77), -- his big green eyes
		StripeColor = Color3.fromRGB(255, 255, 255), -- the white racing stripes down his sides and bonnet

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
		-- how long each sound plays, seconds (to fit its moment): a longer one is
		-- faded out there, a shorter one loops until then. Leave a sound out to
		-- play it as it is (the backfire's BANG and TURBO! shouldn't repeat).
		SoundLength = {
			Wake = 1.2, -- "Ka-VROOM!" just before GO!
			Rev = 0.9, -- in a move's warning
			Charge = 1.4, -- down the lane and past you
			Skid = 1.2,
			Whip = 0.6,
			Crash = 1.0,
			Slam = 0.7,
			Honk = 0.7,
			Bump = 0.45,
			Donut = 2.2, -- the whole donut spin
			Fire = 1.5,
			Death = 2.0,
			Beep = 0.35, -- each start light (about a second apart)
			Finish = 2.2, -- while FINISH! is up
			Cheer = 3.0,
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
		Accent = Color3.fromRGB(44, 232, 245), -- cyan (the VS splash)

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

		-- the fight's music: his own song (Tools/Sounds/music_gridlock.py - 128
		-- beats a minute, 96 bars, so it fits Bpm above beat for beat), and in
		-- round 2 the same song played harder. Until they're uploaded,
		-- FallbackMusic plays (a song of your own: set Bpm to its tempo).
		Music = "Gridlock Theme",
		Round2Music = "Gridlock Theme Flip",
		FallbackMusic = "Gridlock Song",
		MusicVolume = 1.2, -- (his songs are mixed softer than most: turned up to match)
		Round2MusicVolume = 1.2,
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

	[7] = {
		Name = "Kongo, the Jungle Brawler",
		Short = "Kongo",
		-- A big, cocky silverback gorilla with a gold banana chain (his own
		-- name and look: charcoal fur, a pale grey face, no tie) who fights up close
		-- with moves from his games: a Giant Punch he winds up like a windmill,
		-- ground slaps, a rolling attack, a helicopter spin, barrels and TNT.
		-- A brawl on flat ground: read his wind-ups, dodge at the right moment,
		-- and punish him when he's tired. He fights on the surface, so the shared
		-- brain runs him; his moves: ServerScriptService/Bosses/Kongo.lua. His
		-- body: ReplicatedStorage/BossBodies/Kongo.lua. His arena: JungleBuilder.
		Color = Color3.fromRGB(70, 68, 82), -- his charcoal fur
		DeepColor = Color3.fromRGB(38, 36, 50), -- the fur in shadow, his brow
		SkinColor = Color3.fromRGB(165, 160, 172), -- his pale grey face, hands and feet
		BackColor = Color3.fromRGB(170, 172, 186), -- the silver saddle on his back (a silverback)
		CoreColor = Color3.fromRGB(24, 20, 37), -- his pupils, nostrils, mouth
		EyeColor = Color3.fromRGB(255, 255, 255), -- the whites of his eyes
		TieColor = Color3.fromRGB(254, 174, 52), -- his gold chain
		LetterColor = Color3.fromRGB(254, 231, 97), -- the banana medallion on it
		RageColor = Color3.fromRGB(255, 0, 68), -- round 2: his face and eyes, angry red
		Accent = Color3.fromRGB(254, 174, 52), -- the VS splash's colour

		HealthPunches = 42,
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 11, -- how wide he is for hits (he stands nearly three times your height)
		WakeRange = 46, -- walk this close and he wakes up
		WakeTime = 3.4, -- he yawns, jumps up, pounds his chest and roars
		WakeSoundLead = 0.3,
		Leash = 62, -- he can go anywhere in the clearing (its wall is 70 out)
		MoveSpeed = { 15, 18 }, -- knuckle-walking after you between moves, per round (you run 16-24)
		TurnSpeed = { 320, 420 }, -- degrees a second
		Breather = { { 0.6, 1.1 }, { 0.3, 0.6 } }, -- the pause between moves, per round

		PhaseAt = 0.5, -- ROUND 2 at half health
		BreakTime = 3.2, -- he pounds his chest, roars, and his face goes red (everyone near is thrown back)
		BreakShove = 52,
		BreakReach = 26,
		Phase2Recovery = 0.8,
		DesperateAt = 0.2,
		DesperateRecovery = 0.7,

		-- His moves. Tell = the wind-up you see before it hits (every one is at
		-- least your roll's half a second). Recovery = how long he's open after
		-- it. Range = { closest, furthest } he uses it from; Weight = how often;
		-- Phase 2 = only in round 2. A pair like { 3, 4 } means { round 1, round 2 }.
		Attacks = {
			-- GIANT PUNCH: he winds his arm round like a windmill - the red lane in
			-- front of him grows the longer he winds (anywhere from Wind[1] to
			-- Wind[2] seconds) and follows you until Commit of the way through,
			-- then locks. Then he throws himself down it fist-first. Step out of
			-- the lane! If he MISSES he's tired - hands on his knees, panting - for
			-- Tired seconds: your big chance. In round 2 a fully wound punch
			-- (past Big seconds) shakes the ground where it lands: a shockwave ring.
			GiantPunch = { Wind = { 0.9, 1.6 }, Commit = 0.75, Reach = { 12, 30 }, Speed = 62, Width = 5, Damage = { 22, 34 },
				Knockback = { 50, 80 }, Recovery = 0.8, Tired = 2.4, Big = 1.35, WaveSpeed = 34, WaveReach = 30,
				WaveHeight = 2.6, WaveThickness = 2.4, WaveDamage = 14, Phase = 1, Range = { 6, 34 }, Weight = 3 },
			-- HAND SLAP: both arms up, then he slaps the ground again and again -
			-- each slap sends a shockwave rolling out along the floor. JUMP each one
			-- (or roll through it). Slaps = how many, per round.
			HandSlap = { Tell = 0.6, Slaps = { 3, 4 }, Gap = 0.5, Speed = 32, Reach = 34, Thickness = 2.4, Height = 2.6, Damage = 14,
				Knockback = 28, Recovery = 0.9, Phase = 1, Range = { 0, 30 }, Weight = 3 },
			-- ROLLING ATTACK: he curls up into a ball and revs (the red lane locks
			-- at Commit of the way through), then rolls at you - bouncing once off
			-- the edge of the clearing if he gets there. Roll through him, or get
			-- out of the lane. He's dizzy after (a chance to hit him).
			Roll = { Tell = 0.75, Commit = 0.75, Speed = 46, Distance = 72, Width = 5.5, Damage = 20, Knockback = 45,
				Recovery = 1.3, Phase = 1, Range = { 12, 60 }, Weight = 2.5 },
			-- SPINNING KONG: arms out like a helicopter, he spins and drifts after
			-- you for Time seconds - anyone inside the red ring gets clobbered
			-- (again every Rehit seconds). Back off! He's dizzy after.
			Spin = { Tell = 0.6, Time = 2.4, Speed = 11, Radius = 8.5, Damage = 12, Knockback = 34, Rehit = 0.6, Recovery = 1.4,
				Phase = 1, Range = { 0, 22 }, Weight = 2 },
			-- HEADBUTT: a quick, short lunge head-first. Tiny wind-up - watch his head go back.
			Headbutt = { Tell = 0.5, Distance = 10, Time = 0.22, Width = 4.5, Damage = 16, Knockback = 40, Recovery = 0.6,
				Phase = 1, Range = { 0, 12 }, Weight = 2 },
			-- BARREL THROW: he heaves a barrel over his head and throws it - it
			-- rolls along the floor at you. Jump it or roll through it. Barrels =
			-- how many, one after another (each aimed at you), per round.
			Barrel = { Tell = 0.8, Barrels = { 2, 3 }, Gap = 0.65, Speed = 36, Reach = 80, Radius = 2.6, Height = 3.2, Damage = 16,
				Knockback = 30, Recovery = 0.7, Phase = 1, Range = { 14, 200 }, Weight = 2.5 },
			-- TNT: he lobs a TNT barrel high - a red circle marks where it lands -
			-- and it explodes. Get out of the circle! Count = how many, per round
			-- (the second one lands where you ran to).
			TNT = { Tell = 0.9, Count = { 1, 2 }, Gap = 0.55, Flight = 1.1, Radius = 9, Damage = 26, Knockback = 55, Recovery = 0.8,
				Phase = 1, Range = { 18, 200 }, Weight = 1.5 },
			-- CHEST POUND: he pounds his chest and hoots at you ("OOH OOH!") - showing
			-- off. Nothing hurts: run in and hit him!
			Pound = { Time = 1.6, Phase = 1, Range = { 26, 200 }, Weight = 1 },
			-- CARGO THROW (round 2): arms wide, he lunges and GRABS - anyone in
			-- front of him (Reach, Arc degrees wide) is scooped up and hurled far
			-- across the clearing. Dodge sideways or roll.
			CargoThrow = { Tell = 0.55, Reach = 10, Arc = 110, Damage = 22, Throw = 90, Lift = 45, Recovery = 0.8,
				Phase = 2, Range = { 0, 11 }, Weight = 2.5 },
			-- COMBO (round 2): no breathers - a couple of slaps, straight into a
			-- roll, straight into a quick Giant Punch.
			Combo = { Slaps = 2, Wind = 0.85, Phase = 2, Range = { 0, 30 }, Weight = 2.5 },
		},

		Reward = { Power = 2.8, FirstClear = 7 },

		-- the fight's music: add a Sound named "Kongo Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Kongo Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient).
		Sounds = {
			Wake = "Kongo Roar", -- waking up: a big roar
			Pound = "Kongo Chest Pound", -- pounding his chest
			Wind = "Kongo Wind Up", -- the Giant Punch winding up
			Punch = "Kongo Giant Punch", -- the Giant Punch landing
			Slap = "Kongo Slap", -- each ground slap
			Roll = "Kongo Roll", -- rolling
			Spin = "Kongo Spin", -- Spinning Kong
			Headbutt = "Kongo Headbutt", -- the headbutt
			Barrel = "Barrel Throw", -- a barrel thrown
			BarrelBreak = "Barrel Break", -- a barrel smashing at the end of its roll
			TNT = "TNT Boom", -- the TNT going off
			Grab = "Kongo Grab", -- Cargo Throw: the grab and the throw
			Tired = "Kongo Pant", -- tired after a missed punch
			Hoot = "Kongo Hoot", -- "OOH OOH!"
			Break = "Kongo Rage", -- round 2: the angry roar
			Death = "Kongo Death", -- his last groan
		},
	},

	[8] = {
		Name = "Petalina, the Blooming Terror",
		Short = "Petalina",
		-- A giant cartoon flower (a parody of a certain famous flower boss from
		-- a certain old-cartoon-style run-and-gun game - with her own name and
		-- look), planted in the middle of her greenhouse. She never moves from
		-- her spot, so you have to work your way in: seeds that sprout into
		-- biting flytraps, petals that fly out and back like boomerangs, vines
		-- bursting out of the ground, clouds of pollen, and her head stretching
		-- out to chomp you. In round 2 thorns cover every flower bed, so you can
		-- only fight on the paths. The shared brain runs her (she just never
		-- walks); her moves: ServerScriptService/Bosses/Petalina.lua. Her body:
		-- ReplicatedStorage/BossBodies/Petalina.lua. Her arena: GreenhouseBuilder
		-- (the garden's shape: ReplicatedStorage/GardenPlan).
		Color = Color3.fromRGB(246, 117, 122), -- her petals
		TipColor = Color3.fromRGB(232, 183, 150), -- the petals' pale tips
		DeepColor = Color3.fromRGB(181, 80, 136), -- the petals' dark middles
		FaceColor = Color3.fromRGB(254, 231, 97), -- her face, in the middle of the petals
		StemColor = Color3.fromRGB(99, 199, 77), -- her stem and leaves
		StemDeep = Color3.fromRGB(62, 137, 72), -- the stem in shadow, the leaf veins
		CheekColor = Color3.fromRGB(228, 59, 68), -- rosy cheeks
		CoreColor = Color3.fromRGB(24, 20, 37), -- her pupils and mouth
		EyeColor = Color3.fromRGB(255, 255, 255), -- the whites of her eyes
		EvilColor = Color3.fromRGB(162, 38, 51), -- round 2: her petals go dark and wicked
		EvilTip = Color3.fromRGB(255, 0, 68), -- round 2: the petals' tips
		ThornColor = Color3.fromRGB(104, 56, 108), -- the brambles
		ThornTip = Color3.fromRGB(228, 59, 68), -- their sharp red tips
		Accent = Color3.fromRGB(246, 117, 122), -- the VS splash's colour

		HealthPunches = 44,
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 12, -- the size of her body (her stem and roots; her head sits HeadHeight up)
		HeadHeight = 26, -- how high her face is when she stands tall (you're about 5)
		StemRadius = 3, -- how thick her stem is, for your punches
		HeadRadius = 4.5, -- and her head, when it's down where you can reach it
		WakeRange = 44, -- walk this close and she wakes up
		WakeTime = 3.6, -- the bud opens, she stretches her leaves and smiles
		WakeSoundLead = 0.3,
		Leash = 0, -- she never leaves her spot
		MoveSpeed = { 0, 0 },
		TurnSpeed = { 200, 260 }, -- her face turning to follow you, degrees a second
		Breather = { { 0.7, 1.2 }, { 0.45, 0.85 } }, -- the pause between moves, per round

		PhaseAt = 0.5, -- ROUND 2 at half health
		BreakTime = 3.6, -- her face twists into an evil grin and thorns spread over the beds
		BreakShove = 50,
		BreakReach = 22,
		Phase2Recovery = 0.8,
		DesperateAt = 0.2,
		DesperateRecovery = 0.7,

		-- ROUND 2's THORNS: from Grace seconds after she turns evil, standing on
		-- a flower bed hurts - Damage every Tick seconds. Stay on the paths!
		Thorns = { Tick = 0.5, Damage = 6, Grace = 1.2 },

		-- THE FLYTRAPS her seeds sprout into: each grows for Grow seconds, then
		-- turns to face whoever comes within Sense and bites - its jaws gape
		-- for Tell seconds (get back, or roll), then it lunges Lunge studs and
		-- snaps shut on anyone within Reach. Rest between bites. One punch
		-- pops it; left alone it wilts after Life seconds. Max = how many at
		-- once, per round.
		Flytrap = { Grow = 0.8, Life = 12, Sense = 14, Tell = 0.65, Lunge = 2.5, Reach = 4, Rest = 1.3, Damage = 16,
			Knockback = 28, Punches = 1, Max = { 5, 7 } },

		-- Her moves. Tell = the wind-up you see before it hits (every one is at
		-- least your roll's half a second). Recovery = how long she's open after
		-- it. Range = { closest, furthest } she uses it from; Weight = how often;
		-- Phase 2 = only in round 2. A pair like { 3, 4 } means { round 1, round 2 }.
		Attacks = {
			-- SEED SPIT: her cheeks puff up, then she spits seeds high into the
			-- air, one every Gap seconds; each lands Flight later on a red circle
			-- near you (Spread studs round you). Sprout of them grow into flytraps
			-- where they land.
			SeedSpit = { Tell = 0.7, Seeds = { 3, 4 }, Gap = 0.2, Flight = 0.95, Spread = 10, Radius = 3.2, Damage = 14, Knockback = 20,
				Sprout = { 2, 2 }, Recovery = 0.8, Phase = 1, Range = { 10, 200 }, Weight = 2.5 },
			-- PETAL BOOMERANG: she plucks petals off her head and flings them,
			-- one every Gap seconds. Each flies out in a loop past you (a dotted
			-- line on the floor shows its whole path) and comes back to her. It
			-- flies low: jump it, roll through it, or stay inside the loop.
			Petals = { Tell = 0.8, Count = { 2, 3 }, Gap = 0.35, Speed = 46, Width = 10, Past = 8, Radius = 2.6, Height = 3.2,
				Damage = 16, Knockback = 30, Recovery = 0.6, Phase = 1, Range = { 10, 200 }, Weight = 2.5 },
			-- VINE WHIP: she slaps her leaves down, and red lines run out from her
			-- across the floor - one at you, the others fanned Spread degrees
			-- apart. Then vines burst up along them, racing outward (Speed studs
			-- a second). You can't jump them: step off the line, or roll.
			VineWhip = { Tell = 0.9, Lines = { 3, 5 }, Spread = 28, Length = 66, Width = 3.4, Speed = 90, Up = 0.9, Damage = 18,
				Knockback = 40, Recovery = 0.7, Phase = 1, Range = { 0, 200 }, Weight = 3 },
			-- POLLEN CLOUD: she shakes her head and puffs out pollen: clouds drift
			-- down onto red circles near you and hang there for Life seconds.
			-- Standing in one stings (Damage every Tick seconds). Get out of it!
			Pollen = { Tell = 0.8, Clouds = { 2, 3 }, Drift = 1.1, Spread = 9, Radius = 7, Height = 9, Life = 6, Tick = 0.5, Damage = 5,
				Recovery = 0.6, Phase = 1, Range = { 8, 200 }, Weight = 2 },
			-- FACE STRETCH: she pulls her head back (the red lane follows you
			-- until Commit of the way through, then locks), then her neck
			-- stretches and her head shoots down the lane to CHOMP at the end.
			-- Get out of the lane! Then her head lies there, dizzy, for Droop
			-- seconds - it's right there on the floor: HIT HER!
			FaceStretch = { Tell = 0.85, Commit = 0.7, Reach = { 10, 34 }, Time = 0.32, Width = 4.5, Damage = 20, Chomp = 5,
				ChompDamage = 26, Knockback = 50, Droop = 2.4, Back = 0.5, Phase = 1, Range = { 6, 36 }, Weight = 3 },
			-- ROOT RING: you're right up against her - her roots wriggle, the soil
			-- round her cracks in a circle, and roots burst up out of it. Get out
			-- of the circle, or roll.
			RootRing = { Tell = 0.8, Radius = 13, Damage = 20, Knockback = 55, Recovery = 0.6, Phase = 1, Range = { 0, 13 }, Weight = 3.5 },
			-- SUNBATHE: she turns her face up to the sun and hums ("La la la~").
			-- Nothing hurts: run in and hit her!
			Sunbathe = { Time = 1.8, Phase = 1, Range = { 26, 200 }, Weight = 1 },
			-- THORN RING (round 2): she spins her head and flings a ring of thorns
			-- that spreads out across the whole garden - then another, and
			-- another. JUMP each one (or roll through it).
			ThornRing = { Tell = 0.7, Rings = 3, Gap = 0.8, Speed = 26, Reach = 66, Thickness = 2.6, Height = 3, Damage = 16,
				Knockback = 30, Recovery = 0.7, Phase = 2, Range = { 0, 200 }, Weight = 3 },
			-- SEED RAIN (round 2): she shrieks at the glass roof and seeds rain
			-- down onto red circles all over the paths near you. Sprout of them
			-- grow into flytraps.
			SeedRain = { Tell = 1.0, Drops = 10, Spread = 16, Fall = 1.1, Stagger = 0.7, Radius = 3.4, Damage = 16, Knockback = 25,
				Sprout = 2, Recovery = 0.7, Phase = 2, Range = { 0, 200 }, Weight = 2.5 },
		},

		Reward = { Power = 3.2, FirstClear = 8 },

		-- the fight's music: add a Sound named "Petalina Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Petalina Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- Her sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient).
		Sounds = {
			Wake = "Petalina Hum", -- waking up: a sweet little "la la la"
			Spit = "Seed Spit", -- each seed spat out
			Land = "Seed Land", -- a seed thumping down
			Sprout = "Flytrap Sprout", -- a flytrap popping up out of the soil
			Chomp = "Flytrap Chomp", -- a flytrap snapping shut
			Petal = "Petal Throw", -- a petal boomerang thrown
			Whip = "Vine Burst", -- vines bursting up along a line
			Pollen = "Pollen Puff", -- a puff of pollen
			Stretch = "Petalina Stretch", -- her neck stretching out
			Bite = "Petalina Chomp", -- her big chomp at the end of it
			Root = "Root Burst", -- roots bursting up round her
			Giggle = "Petalina Giggle", -- a giggle (sunbathing, and when she hits you)
			Thorn = "Thorn Ring", -- a ring of thorns flung out
			Rain = "Seed Rain", -- the shriek before the seed rain
			Spread = "Thorns Spread", -- round 2: the thorns creeping over the beds
			Break = "Petalina Evil Laugh", -- round 2: her evil laugh
			Death = "Petalina Wilt", -- wilting away at the end
		},
	},

	[9] = {
		Name = "Scribble, the 4th-Dimensional Doodle",
		Short = "Scribble",
		-- A stick figure drawn in blue pen who knows he's inside a video game
		-- (his own name and look - no famous stick figure's), so he fights with
		-- the game itself: round 1 with the drawing tools (a pencil dash, a
		-- giant eraser, a paint bucket, copy-paste, undo), round 2 with your
		-- SCREEN (the mouse cursor, his own health bar as a whip, error
		-- windows, lag), and round 3 by trying to DELETE the whole floor. He's
		-- fast and tricky. Three rounds: his own brain runs them (the shared
		-- one with a third round); his moves: ServerScriptService/Bosses/
		-- Scribble.lua. His body: ReplicatedStorage/BossBodies/Scribble.lua.
		-- His arena: CanvasBuilder (the paper's shape: ReplicatedStorage/CanvasPlan).
		Color = Color3.fromRGB(0, 153, 219), -- round 1: blue pen ink
		InkDeep = Color3.fromRGB(18, 78, 137), -- the ink where it's thickest
		MarkerColor = Color3.fromRGB(228, 59, 68), -- round 2: red marker
		MarkerDeep = Color3.fromRGB(162, 38, 51),
		PencilColor = Color3.fromRGB(254, 174, 52), -- the pencil behind his ear
		EraserColor = Color3.fromRGB(246, 117, 122), -- its pink rubber, and the giant eraser's
		CoreColor = Color3.fromRGB(24, 20, 37), -- his eyes and grin
		DeepColor = Color3.fromRGB(18, 78, 137),
		EyeColor = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(0, 153, 219), -- the VS splash's colour

		HealthPunches = 84, -- (three rounds, 3-4 minutes: the longest fight yet - about twice Petalina's)
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 5, -- how wide he stands, for bumping into him (a thin stick figure)
		Height = 16, -- how tall he is (you're about 5)
		BodyRadius = 2.4, -- how thick he is, for your punches
		WakeRange = 40, -- walk this close and he wakes up
		WakeTime = 3.4, -- he draws himself onto the paper, line by line, and grins
		WakeSoundLead = 0.3,
		Leash = 85, -- (the paper is square, 60 each way: his own step keeps him on it, corners and all)
		MoveSpeed = { 24, 28, 30 }, -- per round (you run at 20 in a fight)
		TurnSpeed = { 420, 520, 600 }, -- degrees a second
		Breather = { { 0.6, 1.0 }, { 0.45, 0.8 }, { 0.35, 0.65 } }, -- the pause between moves, per round

		PhaseAt = 0.55, -- ROUND 2 ("breaking the 4th wall") at 55% health
		BreakTime = 3.4, -- he tears himself out of the paper and turns red marker
		BreakShove = 50,
		BreakReach = 20,
		Phase2Recovery = 0.85,
		DesperateAt = 0.2,
		DesperateRecovery = 0.75,

		-- ROUND 3, "DELETE", at Round3At health: he glitches into rainbow
		-- colours for GlitchTime seconds, then keeps trying to delete the floor.
		-- A giant box pops up at the edge of the paper - "Delete FLOOR 9?
		-- YES / NO" - with a Countdown, while the paper is erased from the
		-- edges in. Punch NO (NoPunches punches) and he CRASHES: dizzy for Crash
		-- seconds (hit him!), and the crash itself costs him CrashDamage of his
		-- health. Miss it and the delete goes through: everyone takes
		-- YesDamage (it never kills - you're left on 1) and the paper stays
		-- Shrink studs smaller each side (never below MinPaper). A new box
		-- comes Every seconds after the last one closes. Standing on erased
		-- paper hurts (EdgeDamage every EdgeTick seconds).
		Round3At = 0.2,
		GlitchTime = 3.0,
		Delete = { Countdown = 7, Every = 10, NoPunches = 3, Crash = 4.5, CrashDamage = 0.04, YesDamage = 38, Shrink = 10,
			MinPaper = 30, EdgeDamage = 7, EdgeTick = 0.5 },

		-- His moves. Tell = the wind-up you see before it hits (every one is at
		-- least your roll's half a second). Recovery = how long he's open after
		-- it. Range = { closest, furthest } he uses it from; Weight = how often;
		-- Phase = the first round it's used in (UpTo = the last). A list like
		-- { 1, 2, 2 } means { round 1, round 2, round 3 }.
		Attacks = {
			-- PENCIL DASH: a dotted line draws itself across the paper - from him,
			-- through you, Past studs beyond - then he rockets along it as a
			-- streak of ink (Speed studs a second). Get off the line! In later
			-- rounds he chains a second dash (its line drawn Chain seconds
			-- before). At the end he skids for Skid seconds: HIT HIM!
			PencilDash = { Tell = 0.9, Count = { 1, 2, 2 }, Chain = 0.65, Speed = 95, Past = 14, Width = 5, Damage = 20, Knockback = 50,
				Skid = 1.3, Phase = 1, Range = { 8, 200 }, Weight = 3 },
			-- ERASER SWEEP: a pink strip across the whole paper glows under you,
			-- then a giant eraser rubs it out for Time seconds. Standing in the
			-- strip hurts (Damage when it starts, TickDamage every Tick after).
			-- Get off the strip! (Later rounds: two strips, a cross.)
			EraserSweep = { Tell = 1.0, Strips = { 1, 2, 2 }, Width = 10, Time = 3, Damage = 12, Knockback = 30, TickDamage = 6, Tick = 0.5,
				Recovery = 0.5, Phase = 1, Range = { 0, 200 }, Weight = 2.5 },
			-- PAINT BUCKET: the grid square you're in outlines and drips... then
			-- floods with paint. Leave the square! The paint stays wet for Wet
			-- seconds (WetDamage every Tick). Later rounds: Squares at once.
			PaintBucket = { Tell = 1.1, Squares = { 1, 3, 3 }, Damage = 18, Knockback = 25, Wet = 2.5, WetDamage = 5, Tick = 0.5,
				Recovery = 0.5, Phase = 1, Range = { 0, 200 }, Weight = 2.5 },
			-- COPY-PASTE: "CTRL+C... CTRL+V!" - Clones ink copies of him peel off
			-- and chase you (Speed studs a second - slower than you). Close up they
			-- wind up a swipe (SwipeTell) and slash anyone within Reach. Punches
			-- punches pop one; left alone they smudge away after Life seconds.
			-- Never more than Max at once. (Rounds 1 and 2.)
			CopyPaste = { Tell = 1.2, Clones = 2, Punches = 1.5, Speed = 15, Life = 14, Reach = 4.5, SwipeTell = 0.55, Damage = 14,
				Knockback = 30, Rest = 1.2, Max = 3, Recovery = 0.3, Phase = 1, UpTo = 2, Range = { 0, 200 }, Weight = 1.6 },
			-- UNDO: a giant Z key pops up in front of you. Punch it (Punches
			-- punches) within Window seconds and he's STUNNED for Stun seconds -
			-- hit him! Miss it and "CTRL+Z!": he undoes your last Hits hits (from
			-- the last Memory seconds, at most Max of his health). He only does it
			-- when you've been hitting him, and not twice within Cooldown
			-- seconds. (Rounds 1 and 2.)
			Undo = { Tell = 0.6, Window = 3.2, Punches = 2, Hits = 5, Memory = 10, Max = 0.07, Stun = 2.8, Cooldown = 22, Phase = 1, UpTo = 2,
				Range = { 0, 200 }, Weight = 1.4 },
			-- THE CURSOR (round 2): a giant mouse pointer hunts you - its shadow
			-- follows you across the paper (Speed studs a second) for Hunt
			-- seconds, freezes, and Lock seconds later it CLICKS there: roll! If
			-- it catches you, it flings you (Fling). Clicks in a row per round.
			Cursor = { Hunt = 2.0, Hunt2 = 1.2, Lock = 0.45, Clicks = { 1, 2, 2 }, Speed = 23, Radius = 4.5, Damage = 18, Fling = 70,
				Recovery = 0.5, Phase = 2, Range = { 0, 200 }, Weight = 3 },
			-- BOSS BAR WHIP (round 2): he rips his own health bar off the top of
			-- your screen and swings it round himself as a giant red whip, low
			-- over the floor (Length studs long, Turns turns, Spin seconds a
			-- turn). JUMP it, or roll through it. The bar pops back afterwards.
			BarWhip = { Tell = 1.0, Length = 34, Turns = { 1.25, 1.25, 1.75 }, Spin = 1.0, Height = 3, Damage = 20, Knockback = 45,
				Recovery = 0.6, Phase = 2, Range = { 0, 30 }, Weight = 2.5 },
			-- ERROR POP-UPS (round 2): ERROR, 404 and LAG windows drop out of the
			-- sky (Windows of them, one every Gap seconds, each Fall seconds in
			-- the air) - their shadows show where. Each lands standing up, Width
			-- studs wide, and stays as a wall for Stay seconds, then shatters.
			ErrorPopups = { Tell = 0.6, Windows = { 4, 5, 6 }, Gap = 0.28, Fall = 0.9, Spread = 12, Width = 12, Depth = 2, Stay = 4,
				Damage = 20, Knockback = 35, Recovery = 0.6, Phase = 2, Range = { 0, 200 }, Weight = 2.5 },
			-- LAG SPIKE (round 2): "LAG" flashes and ghosts of him appear in a line
			-- towards you (Frames of them, the last where you're standing). Then
			-- he skips from ghost to ghost, one every Step seconds - each skip
			-- hits round it (Radius), the last one harder (LastRadius). Get off
			-- the ghosts, or roll on the last frame.
			LagSpike = { Tell = 0.8, Frames = 4, Step = 0.28, Radius = 3.5, Damage = 12, LastRadius = 5.5, LastDamage = 24, Knockback = 45,
				Recovery = 0.7, Phase = 2, Range = { 10, 200 }, Weight = 2.5 },
		},

		Reward = { Power = 3.6, FirstClear = 9 },

		-- the fight's music: add a Sound named "Scribble Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Scribble Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient).
		Sounds = {
			Wake = "Scribble Laugh", -- drawing himself in, and his cheeky laugh
			Draw = "Pencil Scratch", -- a pencil line scratching across the paper
			Dash = "Ink Dash", -- him rocketing along the line
			Skid = "Ink Skid", -- skidding to a stop
			Erase = "Eraser Rub", -- the giant eraser rubbing
			Paint = "Paint Splash", -- a square flooding with paint
			Copy = "Copy Paste", -- CTRL+C, CTRL+V
			Swipe = "Clone Swipe", -- an ink clone's slash
			Key = "Key Pop", -- the Z key popping up
			Undo = "Undo Rewind", -- CTRL+Z: your hits rewinding
			Stun = "Scribble Dizzy", -- stunned (the key broken, the NO pressed)
			Click = "Mouse Click", -- the giant cursor clicking
			Whip = "Bar Whip", -- the health bar whooshing round
			Popup = "Error Pop", -- an error window dropping in
			Lag = "Lag Glitch", -- the lag spike stuttering
			Delete = "Delete Warning", -- the DELETE box popping up
			Crash = "Scribble Crash", -- pressing NO: he crashes
			Break = "Scribble Rip", -- round 2: tearing himself out of the paper
			Glitch = "Scribble Glitch", -- round 3: glitching into rainbow
			Death = "Paper Crumple", -- crumpled into a ball at the end
		},
	},

	[10] = {
		Name = "King Gavelgrunt, Lord of the Spire",
		Short = "Gavelgrunt",
		-- THE FINAL BOSS: the king at the top of the Spire - every boss below
		-- works for him. A COLOSSAL WALRUS KING, nine times your height: a
		-- great layered belly, huge shoulders under spiked gold pauldrons, a
		-- deep crimson cape with an ermine collar, a tall spiked crown, ivory
		-- tusks (one chipped) and an old scar right across his left eye - an
		-- eye that still glows. He swings an iron war-gavel with gold bands
		-- whose runes light up as he winds up. (His own design and name.)
		-- He sleeps on his throne in a thunderstorm; walk up and he wakes
		-- with a crack of lightning, stands up on the throne and leaps down
		-- in front of you. Three rounds: round 1 he's amused (slow, heavy
		-- gavel smashes), round 2 the gavel becomes a steam-powered piston
		-- hammer, round 3 his crown flies off, his scar burns red and he goes
		-- berserk under a red eclipse. His own brain runs the rounds; his
		-- moves: ServerScriptService/Bosses/Gavelgrunt.lua. His body:
		-- ReplicatedStorage/BossBodies/Gavelgrunt.lua. His arena: ThroneBuilder
		-- (its shape: ReplicatedStorage/ThronePlan).
		Color = Color3.fromRGB(115, 62, 57), -- his hide: a dark, scarred walrus
		DeepColor = Color3.fromRGB(62, 39, 49), -- its creases, and the undersides of his flippers
		BellyColor = Color3.fromRGB(184, 111, 80), -- the front of his belly, and his whisker pad
		ScarColor = Color3.fromRGB(232, 183, 150), -- the old scar across his left eye
		TuskColor = Color3.fromRGB(234, 212, 170), -- ivory (the right tusk is chipped)
		CapeColor = Color3.fromRGB(162, 38, 51), -- his deep crimson cape
		FurColor = Color3.fromRGB(255, 255, 255), -- the cape's ermine collar (with black spots)
		GoldColor = Color3.fromRGB(254, 174, 52), -- his crown, pauldrons, belt, bracers and the gavel's bands
		IronColor = Color3.fromRGB(58, 68, 102), -- the war-gavel's iron head
		GripColor = Color3.fromRGB(62, 39, 49), -- its leather-wrapped handle
		SteelColor = Color3.fromRGB(139, 155, 180), -- round 2: the piston hammer
		SteamColor = Color3.fromRGB(192, 203, 220),
		CoreColor = Color3.fromRGB(24, 20, 37), -- his mouth and nostrils
		EyeColor = Color3.fromRGB(254, 174, 52), -- his eyes glow gold...
		ScarEyeColor = Color3.fromRGB(254, 231, 97), -- ...the scarred one brightest
		RuneColor = Color3.fromRGB(254, 231, 97), -- the gavel's runes, glowing as he winds up
		RageColor = Color3.fromRGB(255, 0, 68), -- round 3: his eyes, scar and runes burn red
		Accent = Color3.fromRGB(254, 174, 52), -- the VS splash's colour

		HealthPunches = 96, -- (three rounds, 4-5 minutes: the final boss is the longest fight)
		PartyScale = 0.6,
		StudioFairFight = true,

		Size = 24, -- how wide he is for bumping into him and hits (his belly)
		Height = 44, -- how tall he is (you're about 5; his crown goes higher still)
		BodyRadius = 11, -- how thick he is, for your punches
		WakeRange = 62, -- walk this close to where he fights from and he wakes up
		-- HIS ENTRANCE (WakeTime seconds): lightning cracks, his eyes light up,
		-- he stands up on his throne and raises the gavel to the storm, then
		-- leaps down in front of you and lands with a slam that shakes the
		-- courtyard - that's when the VS splash slams in (IntroDelay seconds
		-- in) - and laughs while it plays. He can't be hurt or hurt you until
		-- it's over.
		WakeTime = 6.0,
		IntroDelay = 3.4,
		WakeSoundLead = 0.3,
		Court = 72, -- how far from the middle of the courtyard he can go (it's 87 across the middle: his belly stays on it)
		Leash = 96, -- (the same, measured from where he fights from - Court is the one that counts)
		MoveSpeed = { 11, 13, 16 }, -- per round (you run at 20 in a fight)
		TurnSpeed = { 220, 280, 360 }, -- degrees a second
		Breather = { { 0.8, 1.3 }, { 0.55, 1.0 }, { 0.4, 0.75 } }, -- the pause between moves, per round

		PhaseAt = 0.65, -- ROUND 2 ("the Mechanical Gavel") at 65% health
		BreakTime = 3.6, -- steam bursts out, the gavel splits open into a piston hammer
		BreakShove = 55,
		BreakReach = 30,
		Phase2Recovery = 0.85,
		DesperateAt = 0.15,
		DesperateRecovery = 0.75,
		-- ROUND 3 ("NO ONE TAKES MY CROWN") at Round3At: his crown flies off, his
		-- scar burns red, the storm turns to a red eclipse, and every pillar
		-- still standing crumbles
		Round3At = 0.3,
		BerserkTime = 3.6,
		-- THE FINAL GAVEL: once, at FinalAt health, he leaps up high and brings
		-- the gavel down on the whole courtyard - a huge red warning for Tell
		-- seconds, then the slam (Radius round him: Damage) and a shockwave
		-- rolling out over everything (jump it, or roll through it). Then he's
		-- worn out for Tired seconds: finish him!
		FinalAt = 0.1,
		Final = { Tell = 3.0, Radius = 18, Damage = 50, Knockback = 70, WaveSpeed = 40, WaveReach = 125, WaveHeight = 3,
			WaveThickness = 3, WaveDamage = 40, Tired = 4.5 },

		-- His moves. Tell = the wind-up you see before it hits (every one is at
		-- least your roll's half a second). Recovery = how long he's open after
		-- it. Range = { closest, furthest } he uses it from; Weight = how often;
		-- Phase = the first round it's used in (UpTo = the last). A list like
		-- { 1, 2, 2 } means { round 1, round 2, round 3 }. Damage is against
		-- your 100 health.
		Attacks = {
			-- ROYAL SMASH: he heaves the gavel up over his head (a red circle
			-- marks where it lands, in front of him - up to Reach away) and SMASHES
			-- it down: Radius round it hurts, and shockwave rings roll out along the
			-- floor (Rings per round - jump them, or roll through). The gavel is
			-- STUCK in the floor for Stuck seconds after: free hits! A smash on a
			-- pillar breaks it.
			RoyalSmash = { Tell = 1.1, Reach = 22, Radius = 8, Damage = 26, Knockback = 55, Rings = { 1, 2, 2 }, RingGap = 0.45,
				WaveSpeed = 34, WaveReach = 38, WaveHeight = 2.6, WaveThickness = 2.4, WaveDamage = 14, Stuck = 1.8,
				Phase = 1, Range = { 0, 28 }, Weight = 3 },
			-- GAVEL SWEEP: a huge sideways swing in front of him (Reach, Arc
			-- degrees wide). Get behind him, or roll.
			GavelSweep = { Tell = 0.8, Reach = 24, Arc = 160, Damage = 22, Knockback = 60, Recovery = 0.7, Phase = 1,
				Range = { 0, 22 }, Weight = 2.5 },
			-- BELLY BOUNCE: he crouches and hops high (Height studs), and his
			-- shadow grows under you - then he belly-flops onto it (Radius), and
			-- the landing bounces everyone near away. Bounces per round.
			BellyBounce = { Tell = 0.9, Air = 0.85, Height = 26, Bounces = { 1, 2, 2 }, Gap = 0.35, Radius = 13, Damage = 28,
				Knockback = 60, Recovery = 1.0, Phase = 1, Range = { 10, 70 }, Weight = 2.5 },
			-- ROYAL DECREE: "GUARDS!" - little tin guards from the floors below drop
			-- in (Guards per round) and chase you (Speed studs a second - slower
			-- than you). Close up they wind up a spear jab (SwipeTell) and jab
			-- anyone within Reach. Punches punches knock one over; left alone
			-- they march off after Life seconds. Never more than Max at once.
			RoyalDecree = { Tell = 1.0, Guards = { 2, 2, 3 }, Punches = 1.5, Speed = 13, Life = 16, Reach = 4.5, SwipeTell = 0.6,
				Damage = 12, Knockback = 28, Rest = 1.3, Max = 4, Recovery = 0.4, Phase = 1, Range = { 0, 200 }, Weight = 1.4 },
			-- TOE STOMP: he stamps his giant flipper down in front of him
			-- (Radius). Then the tip of it GLOWS for Window seconds: punch it
			-- (Punches punches) and he hops round on one foot holding it for Hop
			-- seconds - hit him!
			ToeStomp = { Tell = 0.7, Radius = 7, Damage = 20, Knockback = 45, Window = 2.2, Punches = 1, Hop = 2.6, Recovery = 0.5,
				Phase = 1, Range = { 0, 20 }, Weight = 2 },
			-- TAX COLLECTOR: "TAXES ARE DUE!" - gold coins rain down round you
			-- (Coins per round, spread over Drop seconds, Spread studs round each
			-- of you) and lie there for Lie seconds. Walk over one to grab it:
			-- it heals you Heal. Then he sucks up every coin that's left - each one
			-- makes his NEXT move hit PerCoin harder (at most MaxCoins). (Rounds 1
			-- and 2.)
			TaxCollector = { Tell = 0.9, Coins = { 6, 8, 8 }, Drop = 1.0, Lie = 4.5, Spread = 22, Pickup = 3.2, Heal = 5,
				PerCoin = 0.08, MaxCoins = 8, Recovery = 0.4, Phase = 1, UpTo = 2, Range = { 0, 200 }, Weight = 1.2 },

			-- PISTON TRIPLE SLAM (round 2): three slams, one after another,
			-- stepping towards you (Step studs each) - each one hurts round it
			-- and sends out its own shockwave ring. The rings overlap: find the gap.
			TripleSlam = { Tell = 0.9, Slams = 3, Gap = 0.62, Step = 8, Radius = 8, Damage = 22, Knockback = 50, WaveSpeed = 32,
				WaveReach = 28, WaveHeight = 2.6, WaveThickness = 2.4, WaveDamage = 12, Recovery = 1.0, Phase = 2,
				Range = { 0, 34 }, Weight = 3 },
			-- HAMMER TORNADO (round 2): hammer out, he spins and chases you for
			-- Time seconds - anyone inside the red ring gets clobbered (again every
			-- Rehit seconds). Then he's DIZZY for Dizzy seconds: hit him!
			HammerTornado = { Tell = 0.7, Time = 3.0, Speed = 14, Radius = 16, Damage = 14, Knockback = 40, Rehit = 0.6,
				Dizzy = 2.2, Phase = 2, Range = { 0, 30 }, Weight = 2 },
			-- BIG GULP (round 2): he breathes in HARD for Inhale seconds, pulling
			-- everyone in front of him (Reach, Arc wide) towards his mouth. Anyone
			-- right in front of him at the end (Swallow) is swallowed (Damage),
			-- chewed for Chew seconds and SPAT out across the courtyard. Then a huge
			-- BURP: a cone of wind that throws everyone in front back. Run - or roll
			-- out of his breath.
			BigGulp = { Tell = 0.5, Inhale = 2.2, Reach = 40, Arc = 120, Pull = 14, Swallow = 16, Damage = 30, Chew = 0.7,
				Spit = 110, BurpReach = 34, BurpArc = 100, BurpDamage = 10, BurpKnockback = 75, Recovery = 0.9, Phase = 2,
				Range = { 0, 30 }, Weight = 2 },
			-- ROCKET HAMMER (round 2): the piston fires the hammer's head at you on
			-- a chain - a red lane Length long, Width wide - and yanks it back
			-- along the same lane. Get out of the lane!
			RocketHammer = { Tell = 0.8, Length = 56, Speed = 75, Width = 8, Damage = 24, Knockback = 55, Hold = 0.35,
				Recovery = 0.7, Phase = 2, Range = { 10, 60 }, Weight = 2 },
			-- THE ROYAL FEAST (round 2): servants wheel in a giant roast on a
			-- platter and he sits down to eat, healing HealRate of his health a
			-- second for Feast seconds. Break the platter (Punches punches) - or hit
			-- him hard enough (ChokeAt of his health) - and he CHOKES: stunned for
			-- Choke seconds, and the healing stops. Not more than once every
			-- Cooldown seconds.
			RoyalFeast = { Tell = 1.0, Feast = 6, HealRate = 0.012, Punches = 4, ChokeAt = 0.05, Choke = 3.2, Recovery = 0.5,
				Cooldown = 30, Phase = 2, UpTo = 2, Range = { 16, 200 }, Weight = 1.2 },
			-- THE ROYAL ROLL (round 2): he tucks into a ball (he's round enough)
			-- and bowls across the courtyard at you, bouncing off the edge
			-- (Bounces times) and smashing through pillars. Get out of his lane
			-- (Width wide: the ball's size) - or roll through him. Dizzy after.
			RoyalRoll = { Tell = 0.9, Speed = 56, Distance = 170, Bounces = 2, Width = 16, Damage = 24, Knockback = 60,
				Dizzy = 1.4, Phase = 2, Range = { 14, 70 }, Weight = 2 },

			-- ROYAL EARTHQUAKE (round 3): he jumps sky-high and lands in the middle
			-- of the courtyard. While he's up, some flagstones light up gold (Safe
			-- of them - at least one near each of you): stand on one! Everyone
			-- else is shaken off their feet (Damage). A roll at the landing works too.
			Earthquake = { Tell = 0.6, Air = 1.4, Safe = 6, Damage = 30, Knockback = 45, Recovery = 1.0, Cooldown = 16, Phase = 3,
				Range = { 0, 200 }, Weight = 1.6 },
			-- CROWN GRAB (round 3): his crown lands somewhere in the courtyard and
			-- he lumbers after it for Rush seconds. Get in his way and hit him Trip
			-- times before he gets there and he TRIPS: flat on his face for Tripped
			-- seconds. Too slow and he puts it back on: a roar that throws you back
			-- (RoarRadius) and heals him Heal of his health.
			CrownGrab = { Tell = 0.8, Rush = 3.6, Trip = 5, Tripped = 4.0, Heal = 0.03, RoarRadius = 18, RoarDamage = 18,
				Knockback = 60, Recovery = 0.6, Cooldown = 24, Phase = 3, Range = { 0, 200 }, Weight = 1.4 },
			-- "GUILTY!" (round 3): he bangs the gavel like a judge and one of you
			-- is SENTENCED (a spotlight). Countdown seconds later a giant gavel
			-- falls on them (it locks on Lock seconds before). Stand on a PODIUM
			-- and it hits you Podium as hard. Anyone standing with them (Share)
			-- SHARES the damage.
			Guilty = { Tell = 0.7, Countdown = 4.0, Lock = 0.6, Radius = 7, Damage = 60, Podium = 0.25, Share = 8, Knockback = 50,
				Recovery = 0.6, Cooldown = 16, Phase = 3, Range = { 0, 200 }, Weight = 1.6 },
			-- THRONE TOSS (round 3, once): he leaps back to his throne (Leap
			-- seconds), rips it out of the floor (Lift) and hurls it at you - a red
			-- circle marks where it lands (Flight seconds in the air). It stays
			-- there as cover: the only cover left once the pillars are gone.
			ThroneToss = { Leap = 0.9, Lift = 0.8, Flight = 1.0, Radius = 12, Damage = 30, Knockback = 60, Recovery = 0.8,
				Phase = 3, Range = { 0, 200 }, Weight = 1.2 },
		},

		Reward = { Power = 4.2, FirstClear = 10 },

		-- the fight's music: add a Sound named "Gavelgrunt Song" to SoundService
		-- (until you do, Oozark's plays instead)
		Music = "Gavelgrunt Song",
		MusicVolume = 0.8,
		VictorySound = "Victory Is Ours (a) Sting",
		VictoryName = "King Gavelgrunt",
		Weather = "Clear",

		-- His sounds: add Sounds with these names to SoundService whenever you
		-- like. Any you haven't added yet borrow one of Oozark's (see BossClient)
		-- - except the thunder, which waits for its own.
		Sounds = {
			Wake = "Gavelgrunt Laugh", -- his entrance: a deep, booming royal laugh
			Thunder = "Thunder Crack", -- the storm over his summit: lightning and thunder
			Smash = "Gavel Smash", -- the gavel slamming into the floor
			Sweep = "Gavel Swing", -- the big sideways swing whooshing past
			Bounce = "Belly Bounce", -- his belly-flop (a huge wobbling THUD)
			Land = "Giant Land", -- landing after a jump
			Guards = "Royal Trumpet", -- "GUARDS!": a fanfare
			Guard = "Guard Jab", -- a little guard's spear jab
			Stomp = "Giant Stomp", -- stamping his foot
			Toe = "Toe Ouch", -- "OW! MY TOE!"
			Coins = "Coin Rain", -- coins pouring down
			Coin = "Coin Pickup", -- you grabbing a coin
			Vacuum = "Coin Vacuum", -- him sucking up the coins that are left
			Piston = "Piston Hiss", -- round 2's steam hammer hissing
			Tornado = "Hammer Spin", -- the tornado's whoosh
			Gulp = "Big Inhale", -- breathing in HARD
			Swallow = "Gulp", -- gulping someone down
			Spit = "Spit Out", -- spitting them out
			Burp = "Royal Burp", -- the huge burp
			Rocket = "Rocket Hammer", -- the hammer's head firing out
			Chain = "Chain Rattle", -- the chain yanking back
			Feast = "Royal Feast", -- the servants' dinner bell
			Eat = "Munching", -- him munching
			Choke = "Choke Cough", -- choking on it
			Roll = "Royal Roll", -- rolling like a boulder
			Quake = "Earthquake", -- the earthquake landing
			Crown = "Crown Clang", -- his crown hitting the floor
			Trip = "Giant Trip", -- tripping flat on his face
			Guilty = "Gavel Guilty", -- the judge's gavel: "GUILTY!"
			Gavel = "Giant Gavel", -- the giant gavel coming down
			Throne = "Throne Crash", -- the throne smashing down
			Final = "Final Gavel", -- the final gavel's slam
			Pillar = "Pillar Crumble", -- a pillar breaking
			Break = "Gavel Transform", -- round 2: the gavel becoming a piston hammer
			Berserk = "King Roar", -- round 3: his crown flies off, a furious roar
			Death = "King Fall", -- falling flat on his back at the end
		},
	},
}


----------------------------------------------------------------------
-- Combat in the Spire (Souls style: stamina, dodge roll, flasks)
----------------------------------------------------------------------
Config.Combat = {
	MaxStamina = 100,
	StaminaRegen = 45, -- per second
	StaminaRegenDelay = 0.55, -- seconds after spending before it refills
	PunchCost = 6,
	PunchInterval = 0.34, -- fastest you can punch (seconds)
	PunchLock = 0.34, -- each punch commits you: you can't punch again for this long...
	PunchMoveSpeed = 0.45, -- ...and you only slow down (this share of your speed), you don't stop dead
	PunchRollCancel = 0.12, -- ...and after this much of it you can roll out of the punch
	PunchRange = 8,
	PunchContact = 0.45, -- how far into a swing the fist actually lands (share of
	-- PunchLock). Damage, the camera and the sound all happen at this moment, and
	-- it is also where tracking stops and you are committed. -- studs from you to the enemy's surface
	RollCost = 20,
	JumpCost = 14, -- jumping in an arena costs stamina too; below this you can't jump
	RollCooldown = 0.45,
	RollInvincible = 0.6, -- seconds of invincibility from the moment you roll
	-- The roll takes about 0.46s in all (the hop, the dash through the air and
	-- the landing), so half a second covers you from the floor and back again.
	RollSpeed = 62, -- studs/second
	RollTime = 0.28, -- how long the dash lasts
	Flasks = 4, -- healing flasks per trip into the arena
	FlaskHeal = 0.5, -- heals this share of your max health
	-- every Spire boss, on every tier: their hits x BossDamage, their health x
	-- BossHealth (the bosses' own numbers stay as designed; this keeps the
	-- whole climb friendly - people like winning)
	BossDamage = 0.75,
	BossHealth = 0.85,
	FlaskDrinkTime = 0.7, -- seconds to drink (you're slowed and can't attack)
	FlaskWalkSpeed = 10,
	-- not hit for Delay seconds in a fight: your health comes back, Rate of
	-- your max health a second (a breather between attacks)
	Regen = { Delay = 6, Rate = 0.02 },
	-- a punch without lock-on turns you to the nearest enemy this close (studs
	-- to its middle), so swings don't whiff past it
	AutoFace = 18,
	-- Your own sounds: names of Sounds in SoundService (capitals and spaces don't
	-- matter) and how loud each plays. Getting hurt is the one you must never miss.
	PlayerSounds = {
		Roll = { Name = "Roll", Volume = 0.5 },
		Hurt = { Name = "Hurt 8-Bit", Volume = 0.75 },
		Drink = { Name = "Drinking Potion", Volume = 0.6 },
		Death = { Name = "8bit death sound", Volume = 0.85 },
	},
	ArenaWalkSpeed = 20, -- everyone's speed in a fight (Spire, Colosseum, the intro), whatever
	-- anything else: a boss can only press you if you can't simply outrun it
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

	-- What an enemy does when a hit lands on it, on every screen. None of it
	-- touches damage. The weight of a hit is 1, 2 or 3: which swing of the
	-- string it was, 3 being the finisher (the last swing, or a crit).
	HitReact = {
		Flash = 0.1, -- seconds it flashes white (0: never)
		-- the Colosseum's dummies tip away from the blow and wobble back upright
		-- like punching bags, and get knocked back; a finisher sends them flying
		-- (bigger, heavier kinds budge less; the Straw King doesn't budge at all)
		Tilt = { 14, 18, 40 }, -- degrees they tip over, by weight
		Push = { 1.4, 2, 7 }, -- studs they're knocked back, by weight
		Rise = 2.6, -- how high a finisher throws them
		-- bosses are too big to shove: they jolt back a little from each hit
		BossJolt = { 0.35, 0.5, 1.1 }, -- studs, by weight
	},

	Combo = {
		Window = 0.85, -- punch again within this of the last one to continue the string
		Steps = { 1, 1.3, 1.7 }, -- how far each swing carries you (x the base step)
		Recovery = { 1, 1, 1.35 }, -- how long each swing leaves you committed (x PunchLock)
		Buffer = 0.3, -- a press this close to the end of a swing is queued, not lost
	}, -- the practice slime takes about this many hits at the recommended level
}

----------------------------------------------------------------------
-- WEAPONS (the new direction: see Docs/HANDOFF_PROMPT.md, "Weapon types
-- and abilities"). A weapon replaces your punches in a fight: its TYPE
-- decides how its normal attacks swing (every sword swings like a sword),
-- and each WEAPON has one ability of its own that gets better as that
-- weapon's MASTERY grows (mastery goes up by landing hits with it).
-- For now there's one, the Iron Sword, to test the feel: the dev console's
-- "DEV: Test Sword" gives it to you and "DEV: Mastery +25" levels it.
-- The weapons you own, each one's mastery and the one in your hand are
-- saved (PlayerService: data.Weapons).
----------------------------------------------------------------------
Config.Weapons = {
	-- how much harder than your punch a weapon hits: its rarity's Start at
	-- mastery 1, rising to its Ceiling at mastery 100 (small differences at
	-- first, the rare ones pull away later)
	Rarity = {
		Common = { Start = 1.00, Ceiling = 1.50 },
		Uncommon = { Start = 1.02, Ceiling = 1.70 },
		Rare = { Start = 1.04, Ceiling = 1.95 },
		Epic = { Start = 1.06, Ceiling = 2.25 },
		Legendary = { Start = 1.08, Ceiling = 2.60 },
		Mythic = { Start = 1.10, Ceiling = 3.00 },
		Secret = { Start = 1.12, Ceiling = 3.40 },
		Event = { Start = 1.10, Ceiling = 3.20 },
	},
	MasteryMax = 100,
	MasteryHits = 8, -- hits for the first mastery level; each level after needs 2 more
	MasteryPerHit = 1, -- mastery points per enemy you hit (an ability hit counts the same)

	-- how each TYPE's normal attacks work: a string of swings, like the punches.
	-- Damage is x your punch; Lock is how long each swing commits you (you
	-- stand still, like a punch); Contact is how far into it the blade lands;
	-- Range is studs from you to the enemy's edge; Arc is how wide the swing
	-- cuts in front of you (degrees either side). A swing hits EVERY enemy in
	-- its arc - that's what a blade has over a fist. Lunge is how far each
	-- swing dashes you in (studs; it stops short of a locked-on target).
	Types = {
		Sword = {
			Window = 0.9, -- swing again within this to carry on the string
			Swings = {
				{ Damage = 1.0, Lock = 0.5, Contact = 0.4, Cost = 10, Range = 10, Arc = 75, Lunge = 3.5 }, -- a flat forehand, right to left
				{ Damage = 1.0, Lock = 0.5, Contact = 0.4, Cost = 10, Range = 10, Arc = 75, Lunge = 3.5 }, -- a rising backhand, left to right
				{ Damage = 1.5, Lock = 0.75, Contact = 0.45, Cost = 14, Range = 11, Arc = 30, Lunge = 6 }, -- the finisher: a leaping spin
			},
			-- the uploaded animations (Tools/Animations: made in Blender for R6,
			-- published from Studio). Empty ones fall back to the swings made in
			-- code (WeaponFX.POSES). The sword is held by a Motor6D "Grip" (Right
			-- Arm -> the sword's Handle), so they swing the blade too.
			Animations = {
				Idle = "rbxassetid://99655870498978",
				Swings = { "rbxassetid://72648607435013", "rbxassetid://85757155370756", "rbxassetid://81267393019854" },
			},
			Sounds = { Swing = "Sword Swing", Hit = "Sword Hit" }, -- Sounds in SoundService (missing: the punch ones)
			-- the hit feel (anime style): how long a hit freezes your swing
			-- (hit-stop) and whether a heavy hit flashes the screen with speed lines
			HitStop = 0.06, -- a normal hit
			HeavyHitStop = 0.12, -- the finisher, a crit, the last spin
			ImpactFrames = true,
			ComboCounter = true, -- "12 HITS" climbing while you keep hitting
			SlamSwing = 3, -- (the finisher's blade hits the floor: a shockwave)
		},
		-- (the types below: animations made in Tools/Animations/weapon_types.py and
		-- uploaded with upload_animations.bat; without ids their baked clips play)
		Fists = { -- gauntlets: they punch exactly like your bare fists (the same
			-- punch animations, timing, step and whoosh - CombatClient's playPunch);
			-- the gauntlets just sit on your hands and hit harder
			UsePunch = true,
			-- (its own animations, made and uploaded but not used while UsePunch is on:
			-- Idle 135523120214627, Swings 89651695203012, 84109678195624, 79304465940795)
			Window = 0.85, -- (Config.Combat.Combo's)
			Swings = { -- Lock / Contact: the punch's (Combat.PunchLock x Combo.Recovery, PunchContact)
				{ Damage = 1.0, Lock = 0.42, Contact = 0.45, Cost = 7, Range = 8, Arc = 45, Lunge = 2.5 }, -- a jab
				{ Damage = 1.0, Lock = 0.42, Contact = 0.45, Cost = 7, Range = 8, Arc = 55, Lunge = 2.5 }, -- another
				{ Damage = 1.5, Lock = 0.67, Contact = 0.45, Cost = 11, Range = 8, Arc = 45, Lunge = 4 }, -- the big one
			},
			-- (no Sounds: your punches' own whoosh and hits)
			HitStop = 0.05,
			HeavyHitStop = 0.11,
			ImpactFrames = true,
			ComboCounter = true,
		},
		Hammer = { -- slow and heavy: two big swings and an overhead slam
			-- its uploaded animations (Tools/Animations: upload_animations.bat)
			Animations = { Idle = "rbxassetid://128575426696379", Swings = { "rbxassetid://121242455864935", "rbxassetid://122456781582985", "rbxassetid://84478711326775" } },
			AnimCuts = { { 0.3, 0.56 }, { 0.3, 0.56 }, { 0.46, 0.72 } }, -- (when each swing's smear shows: its Cut and Through markers)
			Window = 1.1,
			Swings = {
				{ Damage = 1.35, Lock = 0.75, Contact = 0.55, Cost = 14, Range = 10, Arc = 70, Lunge = 2.5 }, -- a heavy diagonal
				{ Damage = 1.35, Lock = 0.75, Contact = 0.55, Cost = 14, Range = 10, Arc = 75, Lunge = 2.5 }, -- a sweeping backhand
				{ Damage = 2.2, Lock = 1.0, Contact = 0.6, Cost = 20, Range = 11, Arc = 45, Lunge = 4 }, -- the overhead slam
			},
			Sounds = { Swing = "Hammer Swing", Hit = "Hammer Hit" },
			HitStop = 0.09,
			HeavyHitStop = 0.18,
			ImpactFrames = true,
			ComboCounter = true,
			SlamSwing = 3,
		},
		Daggers = { -- fast stabs, one in each hand: four quick cuts, the last a crossing slash
			-- its uploaded animations (Tools/Animations: upload_animations.bat)
			Animations = { Idle = "rbxassetid://94113040659585", Swings = { "rbxassetid://126936759541915", "rbxassetid://101685032051973", "rbxassetid://102338026181663", "rbxassetid://114558344936315" } },
			AnimCuts = { { 0.08, 0.2 }, { 0.08, 0.2 }, { 0.07, 0.22 }, { 0.16, 0.34 } }, -- (when each swing's smear shows: its Cut and Through markers)
			Window = 0.65,
			Swings = {
				{ Damage = 0.7, Lock = 0.3, Contact = 0.45, Cost = 6, Range = 7, Arc = 50, Lunge = 3 }, -- a right stab
				{ Damage = 0.7, Lock = 0.3, Contact = 0.45, Cost = 6, Range = 7, Arc = 50, Lunge = 3 }, -- a left stab
				{ Damage = 0.7, Lock = 0.3, Contact = 0.45, Cost = 6, Range = 7, Arc = 60, Lunge = 3 }, -- a right slash
				{ Damage = 1.2, Lock = 0.5, Contact = 0.5, Cost = 10, Range = 8, Arc = 60, Lunge = 5 }, -- both blades crossing
			},
			Sounds = { Swing = "Dagger Swing", Hit = "Sword Hit" },
			HitStop = 0.04,
			HeavyHitStop = 0.1,
			ImpactFrames = true,
			ComboCounter = true,
		},
		Scythe = { -- wide, slow sweeps that cut everything round you
			-- its uploaded animations (Tools/Animations: upload_animations.bat)
			Animations = { Idle = "rbxassetid://135542125721488", Swings = { "rbxassetid://85625670938609", "rbxassetid://75951784403018", "rbxassetid://134801390482850" } },
			AnimCuts = { { 0.22, 0.48 }, { 0.22, 0.48 }, { 0.36, 0.8 } }, -- (when each swing's smear shows: its Cut and Through markers)
			Window = 1.0,
			Swings = {
				{ Damage = 1.1, Lock = 0.65, Contact = 0.5, Cost = 12, Range = 12, Arc = 110, Lunge = 2 }, -- a wide sweep
				{ Damage = 1.1, Lock = 0.65, Contact = 0.5, Cost = 12, Range = 12, Arc = 110, Lunge = 2 }, -- sweeping back
				{ Damage = 1.8, Lock = 0.9, Contact = 0.55, Cost = 18, Range = 13, Arc = 180, Lunge = 2 }, -- a full turn
			},
			Sounds = { Swing = "Scythe Swing", Hit = "Sword Hit" },
			HitStop = 0.06,
			HeavyHitStop = 0.13,
			ImpactFrames = true,
			ComboCounter = true,
		},
		Katana = { -- fast, light slashes and a dashing thrust
			-- its uploaded animations (Tools/Animations: upload_animations.bat)
			Animations = { Idle = "rbxassetid://110792943215320", Swings = { "rbxassetid://139384073255581", "rbxassetid://80295576559950", "rbxassetid://91990342601620" } },
			AnimCuts = { { 0.1, 0.32 }, { 0.1, 0.32 }, { 0.18, 0.36 } }, -- (when each swing's smear shows: its Cut and Through markers)
			Window = 0.8,
			Swings = {
				{ Damage = 0.9, Lock = 0.4, Contact = 0.4, Cost = 8, Range = 10, Arc = 55, Lunge = 4 }, -- a fast flat cut
				{ Damage = 0.9, Lock = 0.4, Contact = 0.4, Cost = 8, Range = 10, Arc = 55, Lunge = 4 }, -- a rising cut
				{ Damage = 1.4, Lock = 0.6, Contact = 0.45, Cost = 12, Range = 11, Arc = 40, Lunge = 8 }, -- the dashing thrust
			},
			Sounds = { Swing = "Katana Swing", Hit = "Sword Hit" },
			HitStop = 0.05,
			HeavyHitStop = 0.12,
			ImpactFrames = true,
			ComboCounter = true,
		},
	},

	-- every weapon
	List = {
		IronSword = {
			Name = "Iron Sword",
			Type = "Sword",
			Rarity = "Common",
			-- the 3D model (Tools/Weapons, imported into ReplicatedStorage with
			-- Studio's 3D Importer); missing: the blocky sword made in code
			Model = "IronWarden",
			Colors = {
				Blade = Color3.fromRGB(192, 203, 220),
				Edge = Color3.fromRGB(255, 255, 255),
				Guard = Color3.fromRGB(254, 174, 52),
				Grip = Color3.fromRGB(115, 62, 57),
			},
			-- no ability: it's the starter weapon (F does nothing with it)
		},
	},
	-- what every player owns from the start (saved with their mastery; the
	-- Iron Sword moves to an early quest reward later)
	Starters = { "IronSword" },
	-- abilities whose uploaded animation is switched off (the move, its hits
	-- and its effects still happen). Chest Pound Fists and Kong's Crown knock
	-- you over: off while we find out whether their animations are why.
	NoAbilityAnim = { ChestPoundFists = true, KongsCrown = true },
	Test = "IronSword", -- what "DEV: Test Sword" gives you
	-- what "DEV: Next Sword" goes through, one press at a time (then back to fists)
	TestList = { "IronSword", "EmberCleaver", "Tidefang", "Voidstar" },
}

-- The other 3D swords (Tools/Weapons), to try them in hand: for now they're
-- Iron Swords in everything but their looks (the same swings), with the Whirlwind.
-- Their models must be in ReplicatedStorage (EmberCleaver, Tidefang, Voidstar).
do
	local L = Config.Weapons.List
	-- (the Whirlwind: spin round, cutting everything close to you)
	local WHIRLWIND = {
		Name = "Whirlwind",
		Cooldown = 10, -- seconds
		Cost = 20, -- stamina
		SpinTime = 0.32, -- seconds per spin
		Sound = "Whirlwind", -- a Sound in SoundService (missing: the swing sound)
		-- what it does at each mastery (the highest one you've reached counts)
		Tiers = {
			{ Mastery = 1, Spins = 1, Radius = 9, Damage = 1.6 },
			{ Mastery = 25, Spins = 1, Radius = 11, Damage = 1.9 },
			{ Mastery = 50, Spins = 2, Radius = 11, Damage = 1.6 },
			{ Mastery = 75, Spins = 2, Radius = 12, Damage = 1.6, Ring = 16, RingDamage = 1.2 },
			{ Mastery = 100, Spins = 3, Radius = 13, Damage = 1.6, Ring = 16, RingDamage = 1.2, Golden = true },
		},
		-- the words for each tier (the weapon card shows what's next)
		Say = {
			"Spin once, cutting all round you",
			"A wider, harder spin",
			"Spin twice",
			"The last spin sends out a shockwave",
			"AWAKENED: three golden spins",
		},
	}
	local function sword(name, rarity, model, blade, guard, grip)
		return {
			Name = name,
			Type = "Sword",
			Rarity = rarity,
			Model = model,
			Colors = { Blade = blade, Edge = Color3.fromRGB(255, 255, 255), Guard = guard, Grip = grip }, -- (the blocky one, if its model's missing)
			Ability = WHIRLWIND,
		}
	end
	L.EmberCleaver = sword("Ember Cleaver", "Rare", "EmberCleaver", Color3.fromRGB(255, 120, 30), Color3.fromRGB(60, 40, 40), Color3.fromRGB(120, 28, 30))
	L.Tidefang = sword("Tidefang", "Epic", "Tidefang", Color3.fromRGB(80, 255, 240), Color3.fromRGB(30, 70, 58), Color3.fromRGB(52, 110, 84))
	L.Voidstar = sword("Voidstar", "Legendary", "Voidstar", Color3.fromRGB(70, 40, 110), Color3.fromRGB(255, 170, 250), Color3.fromRGB(40, 25, 70))
end

-- ABILITY BUILDING BLOCKS (CombatService, "Ability building blocks"): most
-- weapons' abilities are a few of these switched on together. An ability
-- without Tiers is this kind:
--   Ability = { Name, Cooldown, Cost (stamina), Aura (a colour), Busy (seconds
--     you're stopped for, default 0.25), Effects = { ... }, Burst = { Radius,
--     Damage (x your hit), Delay } (optional: a hit all round you) }
-- and a weapon can have Passive = { ... }: effects always on while held.
-- Each effect is { Block = name, Amount, Time (seconds) }:
--   DamageUp       you deal Amount more (0.2 = +20%)
--   Crit           Amount extra chance of a critical hit (0.15 = +15%)
--   Lifesteal      every hit heals Amount of your max health (x the swing's weight)
--   StaminaOnHit   every hit gives Amount stamina back
--   StaminaRefill  (instant) refills Amount of your stamina (1 = all of it)
--   Guard          you take Amount less damage (0.2 = 20% less; at most 80%)
--   Shield         the next hit on you does nothing (then it breaks)
--   Thorns         when you're hit, the nearest enemy (within Range, 14) takes Amount x your hit
--   MoveSpeed      you walk Amount faster (0.2 = +20%)
--   Reach          your swings reach Amount studs further
--   NextHit        your next hit deals Amount more (and is a crit); Mark =
--                  the target then takes Mark more from everyone for MarkTime s
--   Stacks         (usually Passive) every hit adds a stack; at Max the hit
--                  deals Amount more and they reset
-- Mastery makes every Amount stronger, up to +50% at mastery 100, and every
-- Time a little longer (Config.blockScale).
function Config.blockScale(mastery)
	local max = Config.Weapons.MasteryMax
	return 1 + 0.5 * math.clamp(((mastery or 1) - 1) / math.max(1, max - 1), 0, 1)
end

-- THE LAUNCH WEAPONS (Docs/weapons_plan.md): one pack per Arcade Machine,
-- on every second floor (1, 3, 5, 7, 9); the even floors' packs come in
-- updates. Each pack has one weapon of each type, Common to Secret.
-- Commons and Rares are building blocks (above); Epic and up are moves
-- (ReplicatedStorage/Moves). Every ability's look: ReplicatedStorage/MoveFX.
do
	local L = Config.Weapons.List
	local RGB = Color3.fromRGB
	local WHITE = RGB(255, 255, 255)

	Config.Weapons.Packs = {}

	-- a pack: its id, floor, boss, colours (main, accent, grip), and its weapons
	-- in rarity order: { id, name, type, ability, passive? }
	local function pack(id, floor, boss, main, accent, grip, weapons)
		local list = {}
		local rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
		for i, w in ipairs(weapons) do
			L[w[1]] = {
				Name = w[2],
				Type = w[3],
				Rarity = rarities[i],
				Pack = id,
				-- its voxel model (Tools/Weapons/packs; ReplicatedStorage/WeaponModelInfo):
				-- until it's loaded, the blocky one made in code in these Colors
				Model = w[1],
				Colors = { Blade = main, Edge = WHITE, Guard = accent, Grip = grip },
				Ability = w[4],
				Passive = w[5],
			}
			table.insert(list, w[1])
		end
		table.insert(Config.Weapons.Packs, { Id = id, Floor = floor, Boss = boss, Color = main, Weapons = list })
	end

	-- Epic and up: a move (ReplicatedStorage/Moves: what it does step by step -
	-- dashes, leaps, slams, things thrown - and MoveFX, how it looks), plus any
	-- building blocks it switches on when you press it
	local function standIn(name, rarity, color, todo, effects)
		return {
			Name = name,
			Cooldown = rarity == "Secret" and 16 or 14,
			Cost = 25,
			Aura = color,
			Effects = effects or {},
			Say = todo,
		}
	end
	local function buffAbility(name, cooldown, color, effects)
		return { Name = name, Cooldown = cooldown, Cost = 15, Aura = color, Effects = effects }
	end

	-- 1. SLIME (Oozark)
	local slime = RGB(110, 230, 90)
	pack("Slime", 1, "Oozark", slime, RGB(40, 140, 60), RGB(30, 80, 40), {
		{ "GooGloves", "Goo Gloves", "Fists",
			buffAbility("Sticky Fists", 12, slime, { { Block = "DamageUp", Amount = 0.15, Time = 4 } }),
			{ { Block = "Stacks", Max = 5, Amount = 0.5 } } }, -- every punch adds slime; the 5th splats for +50%
		{ "Jellyblade", "Jellyblade", "Sword",
			buffAbility("Wobble Guard", 13, slime, { { Block = "Guard", Amount = 0.2, Time = 4 }, { Block = "StaminaOnHit", Amount = 3, Time = 4 } }) },
		{ "GelatinHammer", "Gelatin Hammer", "Hammer",
			standIn("Goo Slam", "Epic", slime, "a ground slam that leaves a sticky puddle, slowing enemies for 2 s") },
		{ "OozeDaggers", "Ooze Daggers", "Daggers",
			standIn("Slime Trail", "Legendary", slime, "dash through an enemy, leaving a slime trail that hurts over time", { { Block = "MoveSpeed", Amount = 0.2, Time = 3 } }) },
		{ "AcidScythe", "Acid Scythe", "Scythe",
			standIn("Acid Rain", "Mythic", slime, "a spinning sweep that flings 3 acid globs; they burst into puddles") },
		{ "GelatinousEdge", "Gelatinous Edge", "Katana",
			standIn("Oozark's Jaw", "Secret", slime, "quick-draw: a giant ghostly Oozark jaw chomps everything in front of you", { { Block = "DamageUp", Amount = 0.25, Time = 4 } }) },
	})

	-- 3. KNIGHT (Burrowmore)
	local steel, gold = RGB(150, 190, 230), RGB(254, 200, 60)
	pack("Knight", 3, "Burrowmore", steel, gold, RGB(90, 60, 40), {
		{ "ShovelHammer", "Shovel Hammer", "Hammer",
			buffAbility("Dig Slam", 12, gold, { { Block = "NextHit", Amount = 0.6, Time = 5 } }) },
		{ "RelicDaggers", "Relic Daggers", "Daggers",
			buffAbility("Treasure Eye", 13, gold, { { Block = "Crit", Amount = 0.15, Time = 4 }, { Block = "StaminaOnHit", Amount = 2, Time = 4 } }) },
		{ "SpadeScythe", "Spade Scythe", "Scythe",
			standIn("Dirt Spin", "Epic", steel, "a spin sweep that flings dirt clods around you") },
		{ "HonourBlade", "Honour Blade", "Katana",
			standIn("Pogo Drop", "Legendary", gold, "leap up and plunge down onto the target blade-first - BOING! - bounce off and plunge again") },
		{ "AnchorFists", "Anchor Fists", "Fists",
			standIn("Anchor Pull", "Mythic", steel, "throw an anchor on a chain: it pulls you to the target for a slam") },
		{ "NoQuarter", "No Quarter", "Sword",
			standIn("No Quarter", "Secret", gold, "your armour cracks gold for 8 s: bigger swings, a gold shockwave on each chop, a meteor finisher",
				{ { Block = "DamageUp", Amount = 0.3, Time = 8 }, { Block = "Guard", Amount = 0.2, Time = 8 } }) },
	})

	-- 5. SPEEDWAY (Revvington)
	local red, flame = RGB(230, 50, 50), RGB(255, 170, 40)
	pack("Speedway", 5, "Revvington", red, flame, RGB(40, 40, 50), {
		{ "TyreScythe", "Tyre Scythe", "Scythe",
			buffAbility("Burnout", 12, flame, { { Block = "MoveSpeed", Amount = 0.2, Time = 4 } }) },
		{ "NitroKatana", "Nitro Katana", "Katana",
			buffAbility("Nitro", 14, RGB(80, 200, 255), { { Block = "StaminaRefill", Amount = 1 }, { Block = "MoveSpeed", Amount = 0.15, Time = 3 } }) },
		{ "PistonPunchers", "Piston Punchers", "Fists",
			standIn("Piston Dash", "Epic", flame, "a dash-punch forward with a flame trail") },
		{ "PitStopSabre", "Pit Stop Sabre", "Sword",
			standIn("Skid Spin", "Legendary", red, "a skid-turn spin hitting all round you in a cloud of tyre smoke - and four spare tyres go flying") },
		{ "WheelieWrecker", "Wheelie Wrecker", "Hammer",
			standIn("Wheelie", "Mythic", flame, "charge forward on a flaming wheel, then slam down") },
		{ "VictoryLap", "Victory Lap", "Daggers",
			standIn("Victory Lap", "Secret", flame, "a blur for 6 s: afterimages, every dash hits, a finish-line blast at the end",
				{ { Block = "MoveSpeed", Amount = 0.3, Time = 6 } }) },
	})

	-- 7. JUNGLE (Kongo)
	local leaf, bark = RGB(70, 170, 70), RGB(150, 95, 45)
	pack("Jungle", 7, "Kongo", leaf, bark, RGB(90, 55, 30), {
		{ "ChestPoundFists", "Chest Pound Fists", "Fists",
			buffAbility("Roar", 12, RGB(255, 120, 60), { { Block = "DamageUp", Amount = 0.2, Time = 4 } }) },
		{ "JungleFang", "Jungle Fang", "Katana",
			buffAbility("Fang", 14, RGB(220, 40, 60), { { Block = "Lifesteal", Amount = 0.03, Time = 5 } }) },
		{ "VineScythe", "Vine Scythe", "Scythe",
			standIn("Vine Swing", "Epic", leaf, "a rope-swing leap forward into a sweeping arc") },
		{ "BarrelDaggers", "Barrel Daggers", "Daggers",
			standIn("Barrel Roll", "Legendary", bark, "curl up inside a barrel and roll right through them - it bursts apart at the end") },
		{ "BarrelHammer", "Barrel Hammer", "Hammer",
			standIn("Barrel Toss", "Mythic", bark, "rolls barrels (mastery: bigger, two barrels, exploding, a giant golden barrel)") },
		{ "KongsCrown", "Kong's Crown", "Sword",
			standIn("Sky Fist", "Secret", RGB(254, 200, 60), "a giant ape fist smashes down from the sky") },
	})

	-- 9. CANVAS (Scribble)
	local ink, paper = RGB(40, 40, 60), RGB(245, 240, 225)
	pack("Canvas", 9, "Scribble", paper, ink, RGB(200, 60, 60), {
		{ "EraserHammer", "Eraser Hammer", "Hammer",
			buffAbility("Erase", 12, RGB(255, 150, 190), { { Block = "NextHit", Amount = 0.3, Time = 5, Mark = 0.25, MarkTime = 3 } }) },
		{ "PencilSword", "Pencil Sword", "Sword",
			buffAbility("Sharpen", 13, RGB(255, 220, 90), { { Block = "Reach", Amount = 3, Time = 4 }, { Block = "Crit", Amount = 0.1, Time = 4 } }) },
		{ "InkFists", "Ink Fists", "Fists",
			standIn("Ink Splash", "Epic", ink, "a ground slam with an ink splash") },
		{ "DoodleKatana", "Doodle Katana", "Katana",
			standIn("Doodle Clone", "Legendary", RGB(90, 160, 255), "a dash-slash that leaves a doodle clone; it repeats the slash 1 s later") },
		{ "CopyPasteScythe", "Copy-Paste Scythe", "Scythe",
			standIn("Copy-Paste", "Mythic", RGB(90, 160, 255), "2 ink clones copy your sweeps for 5 s") },
		{ "DeleteKey", "Delete Key", "Daggers",
			standIn("DELETE", "Secret", RGB(255, 60, 60), "the screen glitches and a giant DEL key falls on the target: huge damage, everything round it shatters") },
	})
end

----------------------------------------------------------------------
-- THE ARCADE: where weapons come from. One machine per weapon pack; a spin
-- costs Arcade Tokens and gives one of that pack's six weapons. The server
-- picks the result (ServerScriptService/ArcadeService) before the spin
-- plays on your screen (StarterPlayerScripts/ArcadeClient); the building
-- stands where the forge was (ServerScriptService/ArcadeBuilder).
--   * Odds are shown on every machine (a Roblox rule for paid random items)
--     and the spinning strip is filled using the real odds.
--   * PITY: a Legendary or better is guaranteed within `Pity` spins on one
--     machine (the counter shows on the machine).
--   * Your FIRST spin ever is Rare or better (said on the machine).
--   * A weapon you already own gives it mastery points instead
--     (`Duplicate`), or coins once it's at mastery 100 (`MaxedCoins`, times
--     the machine's price) - never a token back, so every spin costs.
-- Tokens come from quests (Config.Quests.Tokens), a boss's first clear
-- (`FirstClear`), and later from the Robux shop.
----------------------------------------------------------------------
do
	local RGB = Color3.fromRGB
	Config.Arcade = {
		-- the machines, left to right along the back wall: one per pack in
		-- Config.Weapons.Packs. Price: tokens for one spin; Ten: for ten at
		-- once (a little cheaper). Open: open from the start (the Slime
		-- machine); every other one opens when you beat its pack's boss.
		-- Body/Side/Light: its paint (in the lobby's palette).
		Machines = {
			Slime = { Price = 1, Ten = 9, Open = true, Body = RGB(62, 137, 72), Side = RGB(99, 199, 77), Light = RGB(99, 199, 77) },
			Knight = { Price = 2, Ten = 18, Body = RGB(58, 68, 102), Side = RGB(139, 155, 180), Light = RGB(254, 174, 52) },
			Speedway = { Price = 3, Ten = 27, Body = RGB(162, 38, 51), Side = RGB(228, 59, 68), Light = RGB(254, 231, 97) },
			Jungle = { Price = 4, Ten = 36, Body = RGB(38, 92, 66), Side = RGB(115, 62, 57), Light = RGB(254, 231, 97) },
			Canvas = { Price = 5, Ten = 45, Body = RGB(234, 212, 170), Side = RGB(38, 43, 68), Light = RGB(0, 153, 219) },
		},
		-- the update packs, listed in the menu as "coming soon" (their machines
		-- are built when their packs come)
		Soon = {
			{ Id = "Cactus", Boss = "Tuber" },
			{ Id = "Dojo", Boss = "Kaze" },
			{ Id = "Neon", Boss = "Gridlock" },
			{ Id = "Garden", Boss = "Petalina" },
			{ Id = "Throne", Boss = "Gavelgrunt" },
		},
		-- each rarity's chance, in percent (must add up to 100); a pack has one
		-- weapon of each, so this is each weapon's chance too
		Odds = { Common = 45, Rare = 30, Epic = 15, Legendary = 7, Mythic = 2.5, Secret = 0.5 },
		Pity = 30,
		PityRarities = { "Legendary", "Mythic", "Secret" },
		FirstSpin = { "Rare", "Epic", "Legendary", "Mythic", "Secret" },
		Duplicate = { Common = 60, Rare = 90, Epic = 140, Legendary = 220, Mythic = 320, Secret = 500 },
		-- coins for a weapon you've already mastered (times the machine's price)
		MaxedCoins = { Common = 100, Rare = 150, Epic = 250, Legendary = 500, Mythic = 1000, Secret = 2500 },
		-- tokens for beating a Spire floor's boss for the first time
		FirstClear = { [1] = 5, [2] = 5, [3] = 6, [4] = 6, [5] = 7, [6] = 7, [7] = 8, [8] = 8, [9] = 9, [10] = 10 },
		-- a spin can't be asked for again sooner than this (seconds)
		Gap = 0.4,
		-- THE COIN EXCHANGE (the top of the Arcade menu): coins for a token,
		-- once every `Hours` hours. Its price grows with how far up the Spire
		-- you are: `Base` coins with floor 1 (or nothing) beaten, `PerFloor`
		-- more for every floor above that (floor 10: 15,500) - so coins keep a
		-- use, but it never replaces quests or the token packs.
		Exchange = { Tokens = 1, Hours = 3, Base = 2000, PerFloor = 1500 },
		-- THE ARCADE'S MUSIC (made by Tools/Sounds/arcade_sfx.py; Sounds in
		-- SoundService by these names): its own song while you're in the
		-- Arcade, its menu or a spin (the lobby's song fades out under it),
		-- playing `SpinSpeed` times faster while the strip spins; the
		-- build-up under a spin; the heartbeat before a Legendary or better
		Music = {
			Song = "Arcade Theme",
			Volume = 0.6, -- (1 = as loud as it was made)
			SpinSpeed = 1.25,
			Riser = "Spin Riser",
			Heartbeat = "Heartbeat",
		},
		-- what you hear when a spin lands (the last three are the jackpots:
		-- glass smashing, alarm bells, a casino siren, showers of coins)
		LandSounds = {
			Common = "Win Common", Rare = "Win Rare", Epic = "Win Epic",
			Legendary = "Jackpot Legendary", Mythic = "Jackpot Mythic", Secret = "Jackpot Secret",
		},
		-- how a rarity looks on the machines and in the reveal
		Colors = {
			Common = RGB(192, 203, 220), Rare = RGB(0, 153, 219), Epic = RGB(181, 80, 136),
			Legendary = RGB(254, 174, 52), Mythic = RGB(228, 59, 68), Secret = RGB(255, 255, 255),
		},
		Order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	}
end

-- A machine's pack (Config.Weapons.Packs entry), or nil
function Config.arcadePack(machineId)
	for _, p in ipairs(Config.Weapons.Packs or {}) do
		if p.Id == machineId then
			return p
		end
	end
	return nil
end

-- The weapon of this rarity in that pack, or nil
function Config.arcadeWeapon(machineId, rarity)
	local p = Config.arcadePack(machineId)
	for _, id in ipairs(p and p.Weapons or {}) do
		local def = Config.Weapons.List[id]
		if def and def.Rarity == rarity then
			return id
		end
	end
	return nil
end

-- THE COIN EXCHANGE: the highest Spire floor this player has beaten (on
-- Normal; 0 = none yet), what a trade costs them, and how many seconds until
-- they can trade again (0 = now) - `now` is os.time()
function Config.bestFloor(data)
	local best = 0
	local cleared = type(data) == "table" and type(data.Cleared) == "table" and data.Cleared or {}
	for key, n in pairs(cleared) do
		local f = tonumber(key) -- (Normal's are "<floor>"; harder tiers' "<tier>:<floor>")
		if f and type(n) == "number" and n > 0 and f > best then
			best = f
		end
	end
	return best
end
function Config.exchangePrice(data)
	local X = Config.Arcade.Exchange
	return X.Base + X.PerFloor * math.max(0, Config.bestFloor(data) - 1)
end
function Config.exchangeWait(data, now)
	local X = Config.Arcade.Exchange
	local at = type(data) == "table" and type(data.Arcade) == "table" and tonumber(data.Arcade.exchanged) or 0
	return math.max(0, math.ceil(at + X.Hours * 3600 - now))
end

-- Whether a player with this data may spin that machine (and if not, why)
function Config.arcadeOpen(data, machineId)
	local m = Config.Arcade.Machines[machineId]
	local p = Config.arcadePack(machineId)
	if not m or not p then
		return false, "There's no such machine."
	end
	if m.Open then
		return true
	end
	local cleared = type(data) == "table" and type(data.Cleared) == "table" and data.Cleared[tostring(p.Floor)]
	if type(cleared) == "number" and cleared > 0 then
		return true
	end
	return false, "Beat " .. tostring(p.Boss) .. " (Spire floor " .. tostring(p.Floor) .. ") to open this machine."
end

----------------------------------------------------------------------
-- TRADING at the picnic benches in the lobby: sit across from someone and a
-- trade opens for you both (the server decides everything: TradeService;
-- the window: TradeClient; the benches: LobbyBuilder's buildPicnic).
-- Only weapons can be traded, and a weapon you get arrives at mastery 0.
----------------------------------------------------------------------
Config.Trade = {
	MaxSlots = 4, -- weapons each side can put in
	Countdown = 3, -- seconds from both pressing ACCEPT to the swap
	Cooldown = 10, -- seconds after a trade before you can trade again
}

-- Whether weapon `id` can be traded (a real weapon, not marked NoTrade)
function Config.tradeable(id)
	local def = type(id) == "string" and Config.Weapons.List[id] or nil
	-- (a starter comes back to everyone on every load: trading one would make copies)
	return def ~= nil and not def.NoTrade and not table.find(Config.Weapons.Starters or {}, id)
end

-- The weapons a player has FOUND themselves (the Arcade, a reward, a starter) -
-- not ones traded to them: the Index's rewards and the collector bar count
-- these, so passing weapons between accounts can't claim them over and over.
-- (An old save without the list: everything it owns counts.)
function Config.foundWeapons(data)
	local w = type(data) == "table" and type(data.Weapons) == "table" and data.Weapons or {}
	if type(w.found) == "table" then
		return w.found
	end
	return type(w.own) == "table" and w.own or {}
end

-- The mastery level `points` mastery points make (1 to MasteryMax), and how far
-- into that level they are (0 to 1)
function Config.masteryLevel(points)
	local W = Config.Weapons
	local level, need = 1, W.MasteryHits
	points = math.max(0, points or 0)
	while level < W.MasteryMax and points >= need do
		points = points - need
		level = level + 1
		need = W.MasteryHits + 2 * (level - 1)
	end
	return level, level >= W.MasteryMax and 1 or points / need
end

-- The mastery points it takes to reach mastery `level`
function Config.masteryPointsFor(level)
	local W = Config.Weapons
	local total = 0
	for l = 1, math.clamp(math.floor(level or 1), 1, W.MasteryMax) - 1 do
		total = total + W.MasteryHits + 2 * (l - 1)
	end
	return total
end

-- x your punch for a weapon at a mastery level (its rarity's Start to Ceiling)
function Config.weaponMultiplier(weapon, mastery)
	local W = Config.Weapons
	local r = W.Rarity[weapon and weapon.Rarity or "Common"] or W.Rarity.Common
	local t = math.clamp(((mastery or 1) - 1) / math.max(1, W.MasteryMax - 1), 0, 1)
	return r.Start + (r.Ceiling - r.Start) * t
end

-- The ability tier for a mastery level (the highest one reached), and its number
function Config.abilityTier(weapon, mastery)
	local tiers = weapon and weapon.Ability and weapon.Ability.Tiers
	if not tiers then
		return nil, 0
	end
	local best, index = tiers[1], 1
	for i, t in ipairs(tiers) do
		if (mastery or 1) >= t.Mastery then
			best, index = t, i
		end
	end
	return best, index
end

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
-- Always you in Studio. In the real game: nobody, unless DevInLiveGame is
-- true - then the game's owner (when a person owns it, not a group) and
-- anyone whose UserId is in DevUserIds (your UserId is the number in your
-- Roblox profile's web address). The SERVER decides: every dev action checks
-- this again, so nobody else can use them even if they hack their screen -
-- the screen only uses it to show the button.
----------------------------------------------------------------------
Config.DevInLiveGame = false -- true: the DEV button for the owner in the real game too
Config.DevUserIds = {}
----------------------------------------------------------------------
-- THE NEW PLAYER PATH: right after the intro, three steps lead a new player
-- through the game - the lobby's goal card shows the step (and its trail
-- leads there; the Bag step points at the BAG button). The server moves you
-- on only when it sees the thing really happen (PlayerService.PathEvent) and
-- pays each step's Reward then, and Done at the end. Players from before the
-- path existed skip it. DEV: "New Player Path" starts it again from step 1.
--   Place = a walk-up spot in the lobby the trail leads to ("Arcade",
--   "Quests", "Spire"); Open = a menu the goal card opens; Point = a lobby
--   button an arrow bounces beside.
----------------------------------------------------------------------
Config.Path = {
	Steps = {
		-- the first 15 minutes, straight after the slime: spin the token it
		-- dropped (the weapon goes straight into your hand), then one full
		-- Colosseum run. After that the usual goals take over.
		{ Id = "Spin", Text = "Spin your token at the Arcade", Sub = "Oozlet's token wins your first weapon!", Icon = "Arcade", Place = "Arcade", Reward = { Coins = 100 } },
		{ Id = "Colosseum", Text = "Fight in the Colosseum", Sub = "Walk to the Spire's doors and pick THE COLOSSEUM", Icon = "Weapons", Place = "Spire", Reward = { Coins = 100 } },
		{ Id = "Clear", Text = "Clear the Colosseum", Sub = "Beat all 5 waves - the Straw King comes last!", Icon = "Bosses", Place = "Spire", Reward = { Coins = 300 } },
	},
	Done = { Tokens = 2, Coins = 500 }, -- for finishing the whole path
}

function Config.isDev(player)
	local ok, studio = pcall(function()
		return game:GetService("RunService"):IsStudio()
	end)
	if ok and studio then
		return true
	end
	if not player or not Config.DevInLiveGame then
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

-- UPLOADED SOUNDS: name -> Roblox audio ID. When the game starts, the server
-- makes a Sound in SoundService for each one that isn't there yet, so you
-- don't have to drag them in by hand. Add new uploads here.
Config.SoundIds = {
	["Gridlock Wake"] = 124621958011681,
	["Cube Hop"] = 133657713861136,
	["Cube Slam"] = 122356354040834,
	["Spikes Up"] = 90258458987927,
	["Portal Whoosh"] = 100712036939696,
	["Ship Thrust"] = 118239455654163,
	["Bomb Drop"] = 92028192585506,
	["Ship Dive"] = 123096415709603,
	["UFO Burst"] = 124981384720696,
	["Orb Land"] = 119623153835788,
	["Wave Zoom"] = 107082153634457,
	["Drop Build"] = 116841049720508,
	["The Drop"] = 70533779267743,
	["Gridlock Stun"] = 104242748637460,
	["Gravity Flip"] = 100607897272133,
	["Jump Pad"] = 137308430368505,
	["Gridlock Break"] = 121424067026249,
	["Gridlock Shatter"] = 121001153471952,
	["Attempt Start"] = 111633764060334,
	["Level Complete"] = 126251365588787,
}

-- How loud each uploaded 8-bit sound plays (1 = normal). Lower a number if
-- one still hurts; they also get their shrill top end turned down.
Config.SoundLoudness = {}
for name in pairs(Config.SoundIds) do
	Config.SoundLoudness[name] = 0.4
end
Config.SoundLoudness["Ship Thrust"] = 0.25 -- (a long buzz)
Config.SoundLoudness["Wave Zoom"] = 0.25
Config.SoundLoudness["Spikes Up"] = 0.3

-- FLOORS 7-10's BOSS SOUNDS (Tools/Sounds/boss_sfx.py, loaded by SoundLoader):
-- softened like the 8-bit ones above - quieter, and their harsh top end
-- turned down. Every one plays at BossSoundLoudness.Default; the big hits
-- (roars, booms, crashes, glitches) and the long rumbles and hums at their
-- own lower level. Lower a number if one's still too much.
Config.BossSoundNames = {
	"Bar Whip", "Barrel Break", "Barrel Throw", "Belly Bounce", "Big Inhale", "Chain Rattle", "Choke Cough",
	"Clone Swipe", "Coin Pickup", "Coin Rain", "Coin Vacuum", "Copy Paste", "Crown Clang", "Delete Warning",
	"Earthquake", "Eraser Rub", "Error Pop", "Final Gavel", "Flytrap Chomp", "Flytrap Sprout", "Gavel Guilty",
	"Gavel Smash", "Gavel Swing", "Gavel Transform", "Gavelgrunt Laugh", "Giant Gavel", "Giant Land", "Giant Stomp",
	"Giant Trip", "Guard Jab", "Gulp", "Hammer Spin", "Ink Dash", "Ink Skid", "Key Pop", "King Fall", "King Roar",
	"Kongo Chest Pound", "Kongo Death", "Kongo Giant Punch", "Kongo Grab", "Kongo Headbutt", "Kongo Hoot", "Kongo Pant",
	"Kongo Rage", "Kongo Roar", "Kongo Roll", "Kongo Slap", "Kongo Spin", "Kongo Wind Up", "Lag Glitch", "Mouse Click",
	"Munching", "Paint Splash", "Paper Crumple", "Pencil Scratch", "Petal Throw", "Petalina Chomp",
	"Petalina Evil Laugh", "Petalina Giggle", "Petalina Hum", "Petalina Stretch", "Petalina Wilt", "Piston Hiss",
	"Pollen Puff", "Rocket Hammer", "Root Burst", "Royal Burp", "Royal Feast", "Royal Roll", "Royal Trumpet",
	"Scribble Crash", "Scribble Dizzy", "Scribble Glitch", "Scribble Laugh", "Scribble Rip", "Seed Land", "Seed Rain",
	"Seed Spit", "Spit Out", "TNT Boom", "Thorn Ring", "Thorns Spread", "Throne Crash", "Thunder Crack", "Toe Ouch",
	"Undo Rewind", "Vine Burst",
}
Config.BossSoundLoudness = { Default = 0.4 }
for _, name in ipairs({
	"Barrel Break", "Belly Bounce", "Delete Warning", "Earthquake", "Error Pop", "Final Gavel", "Gavel Guilty",
	"Gavel Smash", "Giant Gavel", "Giant Land", "Giant Stomp", "Giant Trip", "King Fall", "King Roar",
	"Kongo Chest Pound", "Kongo Death", "Kongo Giant Punch", "Kongo Rage", "Kongo Roar", "Lag Glitch",
	"Petalina Evil Laugh", "Rocket Hammer", "Root Burst", "Royal Trumpet", "Scribble Crash", "Scribble Glitch",
	"TNT Boom", "Throne Crash", "Thunder Crack", "Vine Burst",
}) do
	Config.BossSoundLoudness[name] = 0.28 -- (the big hits)
end
for _, name in ipairs({
	"Chain Rattle", "Coin Rain", "Hammer Spin", "Kongo Roll", "Kongo Spin", "Petalina Hum", "Piston Hiss", "Royal Roll",
	"Seed Rain", "Thorns Spread",
}) do
	Config.BossSoundLoudness[name] = 0.25 -- (long rumbles, hums and rain)
end

----------------------------------------------------------------------
-- THE NEW GUI (Previews/gui_windows_sketch.html): the new lobby screen
-- (StarterPlayerScripts/LobbyHud) and the see-through menus
-- (ReplicatedStorage/Menus). Set to false to bring the old HUD's buttons
-- back (and LobbyHud doesn't start).
----------------------------------------------------------------------
Config.NewHud = true

----------------------------------------------------------------------
-- THE NEW GUI's REWARDS (ServerScriptService/RewardService; the Rewards
-- window, the Index and the lobby's corner icons draw them). Everything a
-- player can claim is decided and paid by the server. A reward is a table
-- of any of: Coins, Tokens, Revives, Rushes (Boss Rush tickets), Boost
-- (+ Minutes: "XP" / "Coins" / "Luck", ticking only while you play), Title
-- (a Config.Looks.Titles id), Aura (a Config.Looks.Auras id).
----------------------------------------------------------------------
Config.Rewards = {
	-- LOGIN STREAK: one claim a day (days change at midnight UTC). Miss a day
	-- and it starts again at day 1; after day 7 it goes round again.
	Login = {
		{ Coins = 500 },
		{ Tokens = 1 },
		{ Coins = 1500 },
		{ Tokens = 2 },
		{ Boost = "Luck", Minutes = 30 },
		{ Tokens = 3 },
		{ Tokens = 5, Title = "Loyal" }, -- DAY 7 (the title only the first time)
	},
	-- THE FREE GIFT: ready after every GiftMinutes of play (a clock that only
	-- runs while you're in the game), paying the next of Gifts in turn
	GiftMinutes = 15,
	Gifts = {
		{ Coins = 300 },
		{ Coins = 600 },
		{ Coins = 1000 },
		{ Boost = "Coins", Minutes = 20 },
	},
	GiftsPerDay = 12, -- (then the clock stops until tomorrow: no farming it overnight)
	-- CODES: typed in the Rewards window, one use each per player. Codes are
	-- matched ignoring capitals. Until = the os.time() it stops working (nil: never).
	Codes = {
		LAUNCH = { Tokens = 3, Coins = 1000 },
		WALRUS = { Tokens = 2, Title = "Walrus Food" },
	},
	-- UPDATES: newest first. The Rewards window shows each with its notes and
	-- a gift to claim; the newest opens by itself the first time you join
	-- after it comes out.
	Updates = {
		{
			Id = "1.1",
			Title = "The Walrus King",
			Notes = {
				"Floor 10: King Gavelgrunt, the final boss",
				"A new look for every menu",
				"Rewards: a login streak, a free gift, codes",
				"The Index: collect every weapon",
			},
			Gift = { Tokens = 3, Coins = 1000 },
		},
	},
	-- THE INDEX: every weapon pays once, the first time you own it (by its
	-- rarity), and every find and first boss win fills the COLLECTOR bar
	IndexFind = {
		Common = { Coins = 200 },
		Rare = { Coins = 400 },
		Epic = { Tokens = 1 },
		Legendary = { Tokens = 2 },
		Mythic = { Tokens = 3 },
		Secret = { Tokens = 5 },
	},
	CollectorPoints = { Weapon = 10, Boss = 20 }, -- per weapon found, per boss beaten
	CollectorLevel = 50, -- points for each collector level
	Collector = { -- claimable once you reach the level
		{ Level = 2, Tokens = 2 },
		{ Level = 3, Coins = 3000 },
		{ Level = 5, Title = "Collector" },
		{ Level = 7, Tokens = 4 },
		{ Level = 10, Aura = "Rainbow", Title = "Hoarder" },
	},
	-- THE COMMUNITY CHEST in the lobby: join the group, walk up, claim (once).
	-- GroupId: the number in your community's web address (0: the chest just
	-- says the community isn't linked yet).
	GroupId = 1064901184,
	Group = { Tokens = 3, Title = "Member" },
	-- where the chest stands: on the grass west of the plaza, just north of the
	-- east-west path (it faces the path; its walk-up box is between the two)
	ChestAt = Vector3.new(-50, 0, 18),
	-- THE CORNER BONUSES (on XP): +PerStep% for every StepMinutes you've been
	-- in this server, up to Max%; and +PerFriend% for each Roblox friend in
	-- the server with you, up to Max%
	Playtime = { StepMinutes = 5, PerStep = 1, Max = 10 },
	Friends = { PerFriend = 5, Max = 20 },
}

----------------------------------------------------------------------
-- LOOKS (cosmetics - nothing here changes a fight): titles over your head
-- and auras round you. From rewards, the shop's Daily Items and VIP.
----------------------------------------------------------------------
do
	local RGB = Color3.fromRGB
	Config.Looks = {
		Titles = {
			Rookie = { Text = "Rookie", Color = RGB(180, 230, 255) },
			Loyal = { Text = "Loyal", Color = RGB(120, 230, 140) },
			Collector = { Text = "Collector", Color = RGB(196, 150, 255) },
			Hoarder = { Text = "Hoarder", Color = RGB(255, 182, 46) },
			Member = { Text = "Member", Color = RGB(255, 160, 210) },
			VIP = { Text = "VIP", Color = RGB(255, 214, 40) },
			["Walrus Food"] = { Text = "Walrus Food", Color = RGB(200, 160, 120) },
			["Slime Slayer"] = { Text = "Slime Slayer", Color = RGB(110, 230, 90) },
			["Spire Climber"] = { Text = "Spire Climber", Color = RGB(141, 75, 255) },
			["Boss Hunter"] = { Text = "Boss Hunter", Color = RGB(229, 59, 68) },
		},
		Auras = {
			Gold = { Color = RGB(255, 200, 60) },
			Pink = { Color = RGB(255, 95, 210) },
			Ink = { Color = RGB(60, 40, 110) },
			Frost = { Color = RGB(150, 220, 255) },
			Rainbow = { Color = RGB(255, 255, 255), Rainbow = true },
		},
	}
end

----------------------------------------------------------------------
-- THE SHOP (ServerScriptService/ShopService; the Shop window draws it).
-- ROBUX: make each product in the Creator Dashboard (your experience >
-- Monetization > Developer Products / Passes), then paste its id here. An
-- id of 0 means it isn't made yet: its button says SOON and can't be bought.
-- Price is only what the button shows - Roblox charges what you set there,
-- so keep them the same. Every purchase is handed out exactly once, even if
-- the game crashes halfway (see ShopService). Nothing here makes you
-- stronger in a fight: tokens, time, luck, tickets and looks only.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- BADGES: make each one on create.roblox.com (your game -> Engagement ->
-- Badges; the pictures are in Docs/badges) and paste its ID here. 0 = not
-- made yet: it's simply not given. The server gives them (PlayerService.
-- AwardBadge), at the moment each one is earned:
--   Welcome            joining the game
--   SlimeSlayer        beating Oozlet, the intro's slime
--   FirstSpin          the first spin at the Arcade
--   ColosseumChampion  clearing the Colosseum (all 5 waves)
--   OozarkDown         beating Oozark, floor 1 (any tier)
--   SpireConqueror     beating the Spire's top floor (floor 10)
----------------------------------------------------------------------
Config.Badges = {
	Welcome = 3162828158323873,
	SlimeSlayer = 0,
	FirstSpin = 2441787687313271,
	ColosseumChampion = 3910121594326082,
	OozarkDown = 0,
	SpireConqueror = 0,
}

Config.Shop = {
	-- DEVELOPER PRODUCTS (bought again and again). Gift = can be bought for
	-- another player in the server (the gift button). (The Tokens tab works
	-- out how much more each bigger pack gives from these numbers - never a
	-- made-up "bonus".)
	Products = {
		Tokens10 = { ProductId = 3715970994, Price = 99, Tokens = 10, Name = "Handful", Gift = true, Random = true },
		Tokens25 = { ProductId = 3715971051, Price = 229, Tokens = 25, Name = "Pouch", Gift = true, Random = true },
		Tokens60 = { ProductId = 3715971088, Price = 449, Tokens = 60, Name = "Sack", Gift = true, Random = true },
		Tokens150 = { ProductId = 3715971137, Price = 1199, Tokens = 150, Name = "Treasure Chest", Gift = true, Random = true },
		Revive3 = { ProductId = 3715971207, Price = 29, Revives = 3, Name = "Revive x3", Gift = true },
		Spin3 = { ProductId = 3715971231, Price = 45, Tokens = 3, Name = "Spin x3", Gift = true, Random = true },
		Rush3 = { ProductId = 3715971473, Price = 35, Rushes = 3, Name = "Boss Rush x3", Gift = true },
		Boost30 = { ProductId = 3715971539, Price = 25, Boost = "XP", Minutes = 30, Name = "30 min 2x XP", Gift = true },
		-- once per player, offered after the first boss
		Starter = { ProductId = 3715971585, Price = 49, Once = true, Tokens = 10, Coins = 5000, Revives = 1, Title = "Rookie", Name = "Starter Pack", Gift = false },
	},
	-- GAME PASSES (bought once, kept forever)
	Passes = {
		VIP = { PassId = 2005418400, Price = 299, Name = "VIP" }, -- +50% XP, +25% coins, VIP title, +10% XP for friends in your server
		DoubleXP = { PassId = 2005268391, Price = 199, Name = "2x XP" },
		DoubleCoins = { PassId = 2005370419, Price = 199, Name = "2x Coins" },
		Luck1 = { PassId = 2005430397, Price = 99, Luck = 1.5, Name = "+50% Luck", Random = true },
		Luck2 = { PassId = 2006948389, Price = 299, Luck = 2, Name = "+100% Luck", Random = true },
		Luck3 = { PassId = 2005934386, Price = 799, Luck = 3, Name = "+200% Luck", Random = true },
		InstantTen = { PassId = 2006204386, Price = 29, Name = "Instant x10" }, -- the x10 spin skips straight to the results
	},
	VIP = { XP = 0.5, Coins = 0.25, FriendXP = 10, Title = "VIP" },
	-- TICKETS in fights (used by themselves; Settings can turn each off):
	-- a REVIVE stands you back up at half health when a hit would finish you
	-- in a boss fight (this many per fight); a BOSS RUSH makes a win on a boss
	-- you've beaten before pay RushMultiplier times as much
	RevivesPerFight = 1,
	RushMultiplier = 2,
	BoostLuck = 1.5, -- a Luck boost (the login streak's) = the +50% luck pass while it lasts
	-- DAILY ITEMS: Count looks from the pool, for coins, the same for everyone
	-- each day (a new set at midnight UTC)
	Daily = {
		Count = 5,
		Pool = {
			{ Kind = "Aura", Id = "Gold", Price = 5000, Rarity = "Legendary" },
			{ Kind = "Aura", Id = "Pink", Price = 2500, Rarity = "Epic" },
			{ Kind = "Aura", Id = "Ink", Price = 2500, Rarity = "Epic" },
			{ Kind = "Aura", Id = "Frost", Price = 3000, Rarity = "Epic" },
			{ Kind = "Title", Id = "Slime Slayer", Price = 1200, Rarity = "Rare" },
			{ Kind = "Title", Id = "Spire Climber", Price = 1500, Rarity = "Rare" },
			{ Kind = "Title", Id = "Boss Hunter", Price = 2000, Rarity = "Rare" },
		},
	},
}
-- a product's id -> its key (Tokens10...)
Config.ShopByProductId = {}
for key, p in pairs(Config.Shop.Products) do
	if (p.ProductId or 0) > 0 then
		Config.ShopByProductId[p.ProductId] = key
	end
end

-- the Arcade's odds with `luck` (1 = none): Epic and rarer are `luck` times
-- more likely, the rest share what's left - still adding up to 100
function Config.arcadeOdds(luck)
	local A = Config.Arcade
	luck = math.max(1, tonumber(luck) or 1)
	if luck == 1 then
		return A.Odds
	end
	local boosted, total = {}, 0
	for r, pct in pairs(A.Odds) do
		local w = (r == "Epic" or r == "Legendary" or r == "Mythic" or r == "Secret") and pct * luck or pct
		boosted[r] = w
		total = total + w
	end
	local out = {}
	for r, w in pairs(boosted) do
		out[r] = w / total * 100
	end
	return out
end

-- the Daily Items on sale on day `day` (Config.questDay)
function Config.dailyItems(day)
	local pool = table.clone(Config.Shop.Daily.Pool)
	local rng = Random.new((day or 0) * 104729 + 31)
	local picked = {}
	while #picked < Config.Shop.Daily.Count and #pool > 0 do
		table.insert(picked, table.remove(pool, rng:NextInteger(1, #pool)))
	end
	return picked
end

-- your collector level for `points` (Config.Rewards.CollectorLevel each)
function Config.collectorLevel(points)
	return 1 + math.floor(math.max(0, points or 0) / Config.Rewards.CollectorLevel)
end

-- what a reward table pays, in words ("+3 TOKENS, +1,000 coins")
function Config.rewardText(r)
	local bits = {}
	if (r.Tokens or 0) > 0 then
		table.insert(bits, "+" .. r.Tokens .. (r.Tokens == 1 and " TOKEN" or " TOKENS"))
	end
	if (r.Coins or 0) > 0 then
		table.insert(bits, "+" .. Config.format(r.Coins) .. " coins")
	end
	if (r.Revives or 0) > 0 then
		table.insert(bits, "+" .. r.Revives .. (r.Revives == 1 and " revive" or " revives"))
	end
	if (r.Rushes or 0) > 0 then
		table.insert(bits, "+" .. r.Rushes .. " Boss Rush")
	end
	if r.Boost then
		table.insert(bits, (r.Minutes or 30) .. " min " .. (r.Boost == "Luck" and "+50% luck" or ("2x " .. r.Boost)))
	end
	if r.Title then
		table.insert(bits, "\"" .. r.Title .. "\" title")
	end
	if r.Aura then
		table.insert(bits, r.Aura .. " aura")
	end
	return table.concat(bits, ", ")
end

return Config
