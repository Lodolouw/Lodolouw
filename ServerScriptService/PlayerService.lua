--[[
	PlayerService  (ModuleScript, parent: ServerScriptService, name: "PlayerService")

	Server-authoritative game logic for the lobby:
	  * per-player data (Power = XP, Coins, Arcade Tokens, weapons, quests) + DataStore saving
	  * quests (the Quest Board: a new set every 6 hours, each paying an Arcade Token)
	  * remotes for the HUD

	Hooks for your future arena scripts:
	    local PlayerService = require(game.ServerScriptService.PlayerService)
	    PlayerService.AddCoins(player, 50)
	    PlayerService.AddTokens(player, 5, "why they got them")
	    PlayerService.AddPower(player, 10)
	    PlayerService.GetData(player)               --> the live data table (or nil)
	    PlayerService.QuestProgress(player, "arena", 1) --> counts towards the board's current quests of that kind
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PlayerService = {}

local STORE_NAME = "BossGrowLobby_v1"
local AUTOSAVE_SECONDS = 90

local profiles = {} -- [player] = { data = {...}, canSave = bool, ... }
local dirty = {} -- [player] = true when the client needs a fresh snapshot
local started = {} -- [player] = true once onPlayerAdded ran
local busy = {} -- [player] = true while one of their actions is running (one at a time)
local releasing = {} -- [userId] = the profile of a player who left, until its leave-save is written
local hookedPrompts = {}
local allowRequest, saneArg -- (the request budget and argument checks, below)
local remotes = {}
local handlers = {}
local isStarted = false

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local function defaultData()
	return {
		Power = 0,
		Coins = 0,
		Prestige = 0,
		Cleared = {}, -- ["1"] = how many times you've killed floor 1's boss
		IntroDone = false, -- beaten Oozlet (the intro: only brand-new players get it)
		-- THE NEW PLAYER PATH (Config.Path): the step you're on (0: not started -
		-- it starts when the intro ends), and whether it's all done
		Path = { step = 0, done = false },
		-- the board's quests (see Config.Quests): which set they're from (`day`:
		-- Config.questPeriod, a new set every 6 hours), and for
		-- each one how far along you are and whether you've handed it in
		-- (three are offered in each set; `pick` is the one you chose, 1-3)
		Quests = { day = 0, list = {}, pick = nil },
		-- the Colosseum's 5-wave runs: how many you've cleared, your fastest
		-- clear (seconds; nil until you've cleared one), and the day you last
		-- got the first-clear-of-the-day bonus. And the difficulty you picked
		-- (Config.Colosseum.Difficulties), with runs cleared (`wins`) and your
		-- fastest clear (`bests`) on each one: ["Hard"] = 3
		Colosseum = { clears = 0, best = nil, bonusDay = 0, pick = "Normal", wins = {}, bests = {} },
		-- WEAPONS (Config.Weapons): the ones you own, each with its mastery
		-- points (["IronSword"] = 140), and the one in your hand (nil: fists)
		Weapons = { own = {}, found = {}, hold = nil },
		-- ARCADE TOKENS (Config.Arcade): what the Arcade's machines take
		Tokens = 0,
		-- the Arcade: spins ever (the first is Rare or better), and on each
		-- machine the spins since your last Legendary or better (the pity)
		Arcade = { spins = 0, pity = {} },
		QuestsDone = 0, -- quests ever handed in (a new player's first is a small dummy one)
		-- THE NEW GUI's REWARDS (RewardService, Config.Rewards): the login
		-- streak (its day number and the day it was last claimed), the free
		-- gift (seconds played towards the next one, gifts ever, today's count),
		-- codes used, update gifts claimed, Index finds paid, collector
		-- milestones claimed, the community chest, the update last seen
		Rewards = { streak = 0, streakDay = 0, loyal = false, giftPlay = 0, gifts = 0, giftDay = 0, giftsToday = 0,
			codes = {}, updates = {}, index = {}, milestones = {}, group = false, seen = "" },
		-- LOOKS (Config.Looks): titles and auras owned, and the ones worn
		Looks = { titles = {}, auras = {}, title = nil, aura = nil },
		-- timed boosts: seconds left on each (they only tick while you play)
		Boosts = { XP = 0, Coins = 0, Luck = 0 },
		-- tickets: revives (a boss fight) and Boss Rush (2x rewards on a boss win)
		Tickets = { Revive = 0, Rush = 0 },
		-- THE SHOP (ShopService): the starter pack bought, the last purchases
		-- handed out (so none is ever handed out twice), today's Daily Items bought
		Shop = { starter = false, receipts = {}, daily = { day = 0, bought = {} } },
		-- SETTINGS (the Settings window), kept with your save
		-- (revives / rush: use those tickets by themselves in boss fights)
		Settings = { music = true, sfx = true, shadows = true, hideOthers = false, shake = true, low = false, revives = true, rush = true, guide = true },
	}
end

-- Copy only the fields we know about, so old/edited saves can't break anything
-- Hands in a quest: its coins and Arcade Tokens, and one more quest done.
-- Returns what it paid as words ("+1 ARCADE TOKEN and +80 coins!").
local function payQuest(d, q, def)
	q.claimed = true
	d.Coins = (d.Coins or 0) + def.reward
	local tokens = Config.Quests.Tokens or 0
	d.Tokens = (d.Tokens or 0) + tokens
	d.QuestsDone = (d.QuestsDone or 0) + 1
	if tokens > 0 then
		return "+" .. tokens .. (tokens == 1 and " ARCADE TOKEN" or " ARCADE TOKENS") .. " and +" .. Config.format(def.reward) .. " coins!"
	end
	return "+" .. Config.format(def.reward) .. " coins!"
end

-- The quest you picked from a set of quests, if it's finished but was never
-- handed in (the board changed first - it does every 6 hours): it's handed
-- in for you, so its token isn't lost. Returns what it paid, or nil.
local function payFinished(d, quests)
	if type(quests) ~= "table" or type(quests.list) ~= "table" then
		return nil
	end
	local q = quests.list[tonumber(quests.pick) or 0]
	local def = type(q) == "table" and Config.QuestById[q.id]
	if def and q.claimed ~= true and type(q.n) == "number" and q.n >= def.goal then
		return payQuest(d, q, def)
	end
	return nil
end

-- THE OLD GEAR, SWAPPED. Armour gear and boss treasure chests were taken out
-- of the game; a save from before then still lists them. Each becomes Arcade
-- Tokens, once: every unopened chest (and every old prestige, which had
-- become a chest) and every Common to Rare piece is 1, the rarer pieces are
-- worth more (below) - up to Max in all.
local OLD_GEAR = {
	Chest = 1,
	Piece = 1,
	Max = 100,
	Rare = {
		[2] = { "SumpScepter", "GooMantle", "NahrzulFang", "DeepCarapace", "FireStick", "AnchorPlate",
			"KazeGloves", "FocusMantle", "PistonFists", "NitroVest", "PortalGauntlets", "GravityBoots" }, -- Epic
		[5] = { "OozarkCrown", "TyrantTreads", "MawHelm", "SunkenTreads", "CheckpointCrown", "PogoGreaves",
			"DragonBand", "TornadoTreads", "CheckeredVisor", "BurnoutBoots", "DemonCubeHelm", "DropArmor" }, -- Legendary
		[10] = { "HollowHeart", "Dunebreaker", "LegendShovel", "FourWinds", "GoldenPiston", "FinalBeat" }, -- Mythic
		[25] = { "FirstPuddle", "BuriedSun", "FirstShovel", "EndlessHeadband", "KaVroomEngine", "SecretCoin" }, -- Secret
	},
}
local oldGearWorth = {}
for worth, ids in pairs(OLD_GEAR.Rare) do
	for _, id in ipairs(ids) do
		oldGearWorth[id] = worth
	end
end

-- how many Arcade Tokens an old save's gear and chests are worth
local function oldGearTokens(saved, oldPrestige)
	local n = math.min(math.max(0, oldPrestige or 0), 100) * OLD_GEAR.Chest
	if type(saved.Chests) == "table" then
		for _, c in pairs(saved.Chests) do
			if type(c) == "number" and c == c and c > 0 then
				n = n + math.min(math.floor(c), OLD_GEAR.Max) * OLD_GEAR.Chest
			end
		end
	end
	if type(saved.Items) == "table" then
		for _, rec in pairs(saved.Items) do
			if type(rec) == "table" and type(rec.id) == "string" then
				n = n + (oldGearWorth[rec.id] or OLD_GEAR.Piece)
			end
		end
	end
	return math.min(n, OLD_GEAR.Max)
end

-- THE OLD SHOP, REFUNDED. The Upgrade Shop, the talismans and the Sell Shop
-- were taken out of the game too; a save from before then still lists what
-- was bought, and the loot that was never sold. The coins spent come back,
-- and the loot is sold at its old price, once - up to Max in all.
local OLD_SHOP = {
	Max = 50000,
	-- the upgrades' prices: { first level's price, how much dearer each level is, most levels }
	Upgrades = { Backpack = { 100, 1.55, 40 }, PowerGain = { 150, 1.6, 50 }, SellValue = { 200, 1.6, 50 }, WalkSpeed = { 300, 1.7, 40 } },
	-- the talismans' prices in coins
	Talismans = { Might = 200, Fortune = 400, Vigor = 600, Haste = 800, Greed = 1500, Titan = 5000 },
	-- the loot's old sell prices
	Loot = { Scrap = 5, Shard = 25, Ember = 120, Void = 600 },
}

-- how many coins an old save's upgrades, talismans and loot are worth
local function oldShopRefund(saved)
	local n = 0
	if type(saved.Upgrades) == "table" then
		for id, price in pairs(OLD_SHOP.Upgrades) do
			local level = saved.Upgrades[id]
			if type(level) == "number" and level == level and level > 0 then
				for l = 0, math.min(math.floor(level), price[3]) - 1 do
					n = n + math.floor(price[1] * price[2] ^ l)
				end
			end
		end
	end
	if type(saved.Loot) == "table" then
		for id, price in pairs(OLD_SHOP.Loot) do
			local count = saved.Loot[id]
			if type(count) == "number" and count == count and count > 0 then
				n = n + math.floor(math.min(count, 1e6)) * price
			end
		end
	end
	if type(saved.Owned) == "table" then
		for id, price in pairs(OLD_SHOP.Talismans) do
			if saved.Owned[id] == true then
				n = n + price
			end
		end
	end
	return math.min(n, OLD_SHOP.Max)
end

-- A save, checked: only known things and sensible numbers are kept. Returns
-- the data, how many Arcade Tokens the old gear became (OLD_GEAR) and how
-- many coins the old shop gave back (OLD_SHOP).
local function mergeSaved(saved)
	local d = defaultData()
	if type(saved) ~= "table" then
		return d, 0, 0
	end
	if type(saved.Power) == "number" then
		d.Power = saved.Power
	end
	if type(saved.Coins) == "number" then
		d.Coins = saved.Coins
	end
	-- (the intro is for brand-new players: a save from before it existed that
	-- has any progress counts as having done it)
	d.IntroDone = saved.IntroDone == true or d.Power > 0
	-- (the new player path: kept in range; a save from before it existed
	-- skips it if the intro's done - they know their way round already)
	local steps = Config.Path and #Config.Path.Steps or 0
	if type(saved.Path) == "table" then
		local s = tonumber(saved.Path.step)
		d.Path.step = (s and s == s) and math.clamp(math.floor(s), 0, steps) or 0
		d.Path.done = saved.Path.done == true
	else
		d.Path.done = d.IntroDone
	end
	-- (prestige is gone: every prestige you had became one of Oozark's
	-- treasure chests, once - and now the chests are gone too, an Arcade
	-- Token each: OLD_GEAR, above)
	local oldPrestige = type(saved.Prestige) == "number" and math.floor(saved.Prestige) or 0
	-- (the Upgrade Shop, talismans and the Sell Shop are gone: the coins spent
	-- come back and the loot is sold, once - OLD_SHOP, above)
	local refund = oldShopRefund(saved)
	d.Coins = d.Coins + refund
	if type(saved.Cleared) == "table" then
		-- (Normal's wins by "<floor>", the harder tiers' by "<tier>:<floor>")
		for floorId in pairs(Config.Bosses or {}) do
			for _, t in ipairs(Config.Spire.Tiers) do
				local key = t.id == "Normal" and tostring(floorId) or (t.id .. ":" .. tostring(floorId))
				local n = saved.Cleared[key]
				if type(n) == "number" and n > 0 then
					d.Cleared[key] = math.floor(n)
				end
			end
		end
	end
	-- quests: only real ones, and only kept if they're still the board's
	-- current set (anything older is thrown away and the new set dealt out -
	-- after its finished quest, if any, is handed in: below)
	local oldQuests = nil
	if type(saved.Quests) == "table" and saved.Quests.day ~= Config.questPeriod() then
		oldQuests = saved.Quests
	end
	if type(saved.Quests) == "table" and saved.Quests.day == Config.questPeriod() and type(saved.Quests.list) == "table" then
		d.Quests.day = saved.Quests.day
		local pick = tonumber(saved.Quests.pick)
		d.Quests.pick = (pick and pick >= 1 and pick <= Config.Quests.PerDay) and math.floor(pick) or nil
		for _, q in ipairs(saved.Quests.list) do
			local def = type(q) == "table" and Config.QuestById[q.id]
			if def then
				local n = type(q.n) == "number" and math.clamp(math.floor(q.n), 0, def.goal) or 0
				table.insert(d.Quests.list, { id = def.id, n = n, claimed = q.claimed == true })
			end
		end
	end
	-- the Colosseum's runs: only sensible numbers
	if type(saved.Colosseum) == "table" then
		local c = saved.Colosseum
		if type(c.clears) == "number" and c.clears > 0 then
			d.Colosseum.clears = math.floor(c.clears)
		end
		if type(c.best) == "number" and c.best > 0 then
			d.Colosseum.best = c.best
		end
		if type(c.bonusDay) == "number" then
			d.Colosseum.bonusDay = math.floor(c.bonusDay)
		end
		-- (only difficulties that exist, and only sensible numbers)
		for _, def in ipairs(Config.Colosseum.Difficulties or {}) do
			local w = type(c.wins) == "table" and c.wins[def.id]
			if type(w) == "number" and w > 0 then
				d.Colosseum.wins[def.id] = math.floor(w)
			end
			local b = type(c.bests) == "table" and c.bests[def.id]
			if type(b) == "number" and b > 0 then
				d.Colosseum.bests[def.id] = b
			end
		end
		-- (saved before there were difficulties: every run then was Normal)
		local first = Config.colosseumDifficulty(nil).id
		if type(c.wins) ~= "table" and d.Colosseum.clears > 0 then
			d.Colosseum.wins[first] = d.Colosseum.clears
		end
		if type(c.bests) ~= "table" and d.Colosseum.best then
			d.Colosseum.bests[first] = d.Colosseum.best
		end
		-- (a pick that's still open to you, or back to Normal)
		if type(c.pick) == "string" and Config.colosseumUnlocked(d.Colosseum, c.pick) then
			d.Colosseum.pick = c.pick
		end
	end
	-- (stat points are gone - your level gives the same everywhere now, see
	-- Config.LevelBonus - so an old save's spent points are simply dropped)
	-- weapons: only real ones, mastery kept in range, holding only one you own
	local W = Config.Weapons
	if W and type(saved.Weapons) == "table" then
		local maxPoints = Config.masteryPointsFor(W.MasteryMax)
		if type(saved.Weapons.own) == "table" then
			for id, points in pairs(saved.Weapons.own) do
				if type(id) == "string" and W.List[id] and type(points) == "number" and points == points then
					d.Weapons.own[id] = math.clamp(math.floor(points), 0, maxPoints)
				end
			end
		end
		local hold = saved.Weapons.hold
		if type(hold) == "string" and d.Weapons.own[hold] then
			d.Weapons.hold = hold
		end
		-- (found yourself - Config.foundWeapons; an old save without the list:
		-- everything it owns, once)
		if type(saved.Weapons.found) == "table" then
			for id, on in pairs(saved.Weapons.found) do
				if type(id) == "string" and W.List[id] and on == true then
					d.Weapons.found[id] = true
				end
			end
		else
			for id in pairs(d.Weapons.own) do
				d.Weapons.found[id] = true
			end
		end
	end
	-- tokens, the Arcade's counters, quests handed in: only sensible numbers
	local function count(v)
		return (type(v) == "number" and v == v and v > 0 and v < 1e9) and math.floor(v) or 0
	end
	d.Tokens = count(saved.Tokens)
	-- the old armour gear and boss chests are gone: whatever an old save still
	-- has of them becomes Arcade Tokens, once (the next save leaves them out)
	local swapped = oldGearTokens(saved, oldPrestige)
	d.Tokens = d.Tokens + swapped
	d.QuestsDone = count(saved.QuestsDone)
	if type(saved.Arcade) == "table" then
		d.Arcade.spins = count(saved.Arcade.spins)
		-- (when you last used the Coin Exchange: os.time(), never in the future)
		local ex = saved.Arcade.exchanged
		if type(ex) == "number" and ex == ex and ex > 0 and ex <= os.time() + 60 then
			d.Arcade.exchanged = math.floor(ex)
		end
		if type(saved.Arcade.pity) == "table" then
			for id in pairs(Config.Arcade and Config.Arcade.Machines or {}) do
				d.Arcade.pity[id] = count(saved.Arcade.pity[id])
			end
		end
	end
	-- THE NEW GUI's saves: only known things, only sensible numbers
	local function flags(v, known)
		local out = {}
		if type(v) == "table" then
			for k, on in pairs(v) do
				if type(k) == "string" and #k <= 40 and on == true and (known == nil or known[k]) then
					out[k] = true
				end
			end
		end
		return out
	end
	local R = saved.Rewards
	if type(R) == "table" then
		local r = d.Rewards
		r.streak = math.clamp(count(R.streak), 0, #Config.Rewards.Login)
		r.streakDay = count(R.streakDay)
		r.loyal = R.loyal == true
		r.giftPlay = math.clamp(count(R.giftPlay), 0, Config.Rewards.GiftMinutes * 60)
		r.gifts = count(R.gifts)
		r.giftDay = count(R.giftDay)
		r.giftsToday = count(R.giftsToday)
		r.codes = flags(R.codes)
		r.updates = flags(R.updates)
		r.index = flags(R.index, W and W.List)
		r.milestones = flags(R.milestones)
		r.group = R.group == true
		r.seen = type(R.seen) == "string" and #R.seen <= 20 and R.seen or ""
	end
	if type(saved.Looks) == "table" then
		local L = saved.Looks
		d.Looks.titles = flags(L.titles, Config.Looks.Titles)
		d.Looks.auras = flags(L.auras, Config.Looks.Auras)
		d.Looks.title = type(L.title) == "string" and d.Looks.titles[L.title] and L.title or nil
		d.Looks.aura = type(L.aura) == "string" and d.Looks.auras[L.aura] and L.aura or nil
	end
	if type(saved.Boosts) == "table" then
		for k in pairs(d.Boosts) do
			d.Boosts[k] = math.min(count(saved.Boosts[k]), 30 * 24 * 3600)
		end
	end
	if type(saved.Tickets) == "table" then
		d.Tickets.Revive = count(saved.Tickets.Revive)
		d.Tickets.Rush = count(saved.Tickets.Rush)
	end
	if type(saved.Shop) == "table" then
		local sh = saved.Shop
		d.Shop.starter = sh.starter == true
		if type(sh.receipts) == "table" then
			for _, id in ipairs(sh.receipts) do
				if type(id) == "string" and #id <= 80 and #d.Shop.receipts < 60 then
					table.insert(d.Shop.receipts, id)
				end
			end
		end
		if type(sh.daily) == "table" and sh.daily.day == Config.questDay() then
			d.Shop.daily.day = sh.daily.day
			d.Shop.daily.bought = flags(sh.daily.bought)
		end
	end
	if type(saved.Settings) == "table" then
		for k, v in pairs(d.Settings) do
			if type(saved.Settings[k]) == type(v) then
				d.Settings[k] = saved.Settings[k]
			end
		end
	end
	-- (everyone has the starter weapons)
	for _, id in ipairs(W and W.Starters or {}) do
		if W.List[id] and not d.Weapons.own[id] then
			d.Weapons.own[id] = 0
		end
		if W.List[id] then
			d.Weapons.found[id] = true
		end
	end
	-- a quest finished in an earlier set but never handed in: handed in now
	if oldQuests then
		payFinished(d, oldQuests)
	end
	return d, swapped, refund
end

-- the highest Spire floor this player has ever cleared (0 = none yet)
-- The highest floor beaten on a tier. Wins are kept in d.Cleared by
-- "<floor>" (Normal) or "<tier>:<floor>" (Nightmare, Eclipse, Doom).
local function clearedKey(floorId, tierId)
	if tierId == nil or tierId == "Normal" then
		return tostring(floorId)
	end
	return tostring(tierId) .. ":" .. tostring(floorId)
end
local function highestCleared(d, tierId)
	local best = 0
	local prefix = (tierId == nil or tierId == "Normal") and "" or (tostring(tierId) .. ":")
	for key, n in pairs(d.Cleared or {}) do
		local id = nil
		if prefix == "" then
			id = tonumber(key)
		elseif string.sub(key, 1, #prefix) == prefix then
			id = tonumber(string.sub(key, #prefix + 1))
		end
		if id and n > 0 and id > best then
			best = id
		end
	end
	return best
end
-- every tier's best floor, on the player (the Spire menu shows them)
local function showCleared(player, d)
	for _, t in ipairs(Config.Spire.Tiers) do
		player:SetAttribute(Config.spireClearedKey(t.id), highestCleared(d, t.id))
	end
end

-- SAVING, SAFELY. Only one server may own a player's save at a time: when a
-- server loads it, it writes its own id into it (a "lock"), keeps that fresh
-- with every autosave, and lets go when the player leaves. Another server
-- that loads the save while it's locked waits for the lock to be let go -
-- so hopping servers can never load an old copy of your save before the last
-- server has finished writing the new one (that would let you spend tokens,
-- hop, and have them back; with trading, it would copy items). A lock older than
-- LOCK_EXPIRES is from a server that crashed, and is taken over.
local LOCK_EXPIRES = 240 -- seconds
local JOB = game.JobId

-- A copy of the data safe to write: no NaN or infinite numbers (one of those
-- makes the whole save fail to write), nothing absurdly deep.
local function cleanCopy(v, depth)
	if type(v) == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return 0
		end
		return v
	elseif type(v) == "table" then
		if depth > 8 then
			return nil
		end
		local t = {}
		for k, x in pairs(v) do
			t[k] = cleanCopy(x, depth + 1)
		end
		return t
	end
	return v
end

-- returns: saved data (nil for a new player), whether it may be saved, and
-- whether another server still had it locked the whole time
local function loadData(player)
	if not store then
		return nil, false, false
	end
	local key = "u_" .. player.UserId
	local lockedTries = 0
	for attempt = 1, 10 do
		local locked = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				if type(old) == "table" and old._lockJob and old._lockJob ~= JOB
					and os.time() - (tonumber(old._lockTime) or 0) < LOCK_EXPIRES then
					locked = true
					return nil -- (not ours yet: leave it exactly as it is)
				end
				old = type(old) == "table" and old or {}
				old._lockJob = JOB
				old._lockTime = os.time()
				return old
			end)
		end)
		if ok and not locked then
			return result, true, false
		end
		if locked then
			lockedTries = lockedTries + 1
		elseif attempt >= 2 then
			-- (DataStores not reachable - e.g. Studio without API access: play
			-- straight away without saving, rather than waiting on it)
			return nil, false, false
		end
		if not player.Parent then
			return nil, false, false
		end
		task.wait(locked and 5 or 1.5) -- (give the other server time to finish saving)
	end
	return nil, false, lockedTries >= 5
end

-- `release` = true when the player is leaving: the lock is let go. Once a
-- profile has started letting go, no ordinary save may write again (an
-- autosave landing after the leave-save would take the lock back and leave
-- it stuck), and an ordinary save only writes while the lock is still ours.
local function saveProfile(player, release, profile)
	profile = profile or profiles[player]
	if not profile or not profile.canSave or not store then
		return
	end
	if release then
		profile.released = true
	elseif profile.released then
		return false
	end
	local key = "u_" .. player.UserId
	for attempt = 1, 3 do
		local stolen = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				if type(old) == "table" and old._lockJob ~= JOB and (old._lockJob ~= nil or not release) then
					stolen = true
					return nil -- (another server owns it now, or it's been let go: never write over it)
				end
				local out = cleanCopy(profile.data, 0)
				out._lockJob = (not release) and JOB or nil
				out._lockTime = os.time()
				return out
			end)
		end)
		if ok then
			if stolen then
				profile.canSave = false
				warn("[PlayerService] " .. player.Name .. "'s save is owned by another server now - not saving here")
			end
			return not stolen
		end
		warn("[PlayerService] save failed (" .. attempt .. "/3): " .. tostring(err))
		task.wait(1)
	end
	return false
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function markDirty(player)
	dirty[player] = true
end

local function notify(player, text, kind)
	if remotes.Notify and player.Parent then
		remotes.Notify:FireClient(player, text, kind or "ok")
	end
end

-- Newer Roblox characters can be driven by a physics-based ControllerManager
-- instead of the classic Humanoid movement. When one is present, how fast you
-- actually move comes from ControllerManager.BaseMoveSpeed (default 16) and
-- Humanoid.WalkSpeed is ignored - which is why the old Swift Boots upgrade changed
-- the WalkSpeed number but not your real speed. So set both.
local function applyMoveSpeed(char, speed)
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("ControllerManager") then
			inst.BaseMoveSpeed = speed
		end
	end
end

local function applyCharacterStats(player, fill)
	local profile = profiles[player]
	if not profile then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local s = Config.stats(profile.data)
	local ratio = 1
	if hum.MaxHealth > 0 then
		ratio = hum.Health / hum.MaxHealth
	end
	local speed = Config.walkSpeedFor(player, profile.data) -- capped in a Spire arena
	hum.WalkSpeed = speed
	applyMoveSpeed(char, speed)
	hum.MaxHealth = s.maxHealth
	if fill then
		hum.Health = s.maxHealth
	else
		hum.Health = s.maxHealth * ratio
	end
end

local function nearStation(player, stationName)
	if not Config.RequireProximity then
		return true
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = Config.Stations[stationName]
	if not root or not pos then
		return false
	end
	local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
	return flat.Magnitude <= Config.StationRange
end

----------------------------------------------------------------------
-- Quests (the Quest Board: a new set every Config.Quests.Hours)
----------------------------------------------------------------------
-- Deals out the board's current quests if the ones you have are from an
-- earlier set (a new set every Config.Quests.Hours). Returns true if it did
-- (so the screen needs the new ones), and what the old set's finished quest
-- paid if it hadn't been handed in yet (it is now: payFinished). A player
-- who's never handed a quest in gets the small dummy quest
-- (Config.Quests.First) in place of the set's dummy quest, so their first
-- token comes quickly.
local function ensureQuests(d)
	local now = Config.questPeriod()
	if d.Quests.day == now and #d.Quests.list == Config.Quests.PerDay then
		return false
	end
	local paid = payFinished(d, d.Quests)
	d.Quests = { day = now, list = {}, pick = nil }
	local first = (d.QuestsDone or 0) == 0 and Config.QuestById[Config.Quests.First or ""]
	for _, id in ipairs(Config.questsForDay(now)) do
		local def = Config.QuestById[id]
		if first and def and def.kind == first.kind then
			id = first.id
		end
		table.insert(d.Quests.list, { id = id, n = 0, claimed = false })
	end
	return true, paid
end

-- Something happened that counts towards quests of this kind
-- ("arena", "boss", "clear": Config.Quests).
function PlayerService.QuestProgress(player, kind, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.data
	local changed, paid = ensureQuests(d)
	if paid then
		notify(player, "Your finished quest was handed in for you: " .. paid, "rare")
	end
	-- (all three count from the start of the set, so whichever you pick
	-- already has everything you've done since - even before you picked it)
	for i, q in ipairs(d.Quests.list) do
		local def = Config.QuestById[q.id]
		if def and def.kind == kind and not q.claimed and q.n < def.goal then
			q.n = math.min(def.goal, q.n + (amount or 1))
			changed = true
			if q.n >= def.goal and i == d.Quests.pick then
				notify(player, "Quest done: " .. Config.questText(def) .. "! Hand it in at the Quest Board.", "ok")
			end
		end
	end
	if changed then
		markDirty(player)
	end
end

----------------------------------------------------------------------
-- Public API (for your arena scripts)
----------------------------------------------------------------------
function PlayerService.GetData(player)
	local profile = profiles[player]
	return profile and profile.data or nil
end

-- What earned XP and coins are multiplied by (the shop's passes and boosts,
-- VIP, the corner bonuses): RewardService and ShopService each add a hook,
-- fn(player, data, kind ("Power" / "Coins"), amount) -> the new amount
local gainHooks = {}
function PlayerService.AddGainHook(fn)
	table.insert(gainHooks, fn)
end
-- (a real, finite number: NaN or an infinity in a balance would make every
-- "can you afford it?" check pass, so none may ever reach one)
local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
PlayerService.finite = finite
local function boosted(player, d, kind, amount)
	if not finite(amount) or amount <= 0 then
		return finite(amount) and amount or 0
	end
	for _, fn in ipairs(gainHooks) do
		local ok, v = pcall(fn, player, d, kind, amount)
		if ok and finite(v) and v >= 0 then
			amount = v
		end
	end
	return math.floor(amount + 0.5)
end

-- Coins earned (multiplied by the gain hooks), or exactly `amount` if `raw`
function PlayerService.AddCoins(player, amount, raw)
	local profile = profiles[player]
	if profile and finite(amount) then
		if not raw then
			amount = boosted(player, profile.data, "Coins", amount)
		end
		local new = (profile.data.Coins or 0) + amount
		if not finite(new) then
			warn("[PlayerService] refused a bad coin amount: " .. tostring(amount))
			return
		end
		profile.data.Coins = math.max(0, new)
		markDirty(player)
	end
end

-- Arcade Tokens (whole ones; `why`, if given, pops up on their screen)
function PlayerService.AddTokens(player, amount, why)
	local profile = profiles[player]
	amount = math.floor(tonumber(amount) or 0)
	if profile and finite(amount) and amount > 0 and amount < 1e6 then
		profile.data.Tokens = (profile.data.Tokens or 0) + amount
		markDirty(player)
		if why then
			notify(player, why, "rare")
		end
	end
end

-- A boss on `floorId` died with this player in the arena. Returns true if it
-- was their first time beating it (BossService pays a bigger reward for that).
function PlayerService.RecordBossKill(player, floorId, tierId)
	local profile = profiles[player]
	if not profile then
		return false
	end
	local d = profile.data
	d.Cleared = d.Cleared or {}
	local key = clearedKey(floorId, tierId)
	local before = d.Cleared[key] or 0
	d.Cleared[key] = before + 1
	if floorId == 1 and (tierId == nil or tierId == "Normal") then
		task.defer(PlayerService.PathEvent, player, "Beat")
	end
	showCleared(player, d)
	-- a boss's first clear pays a bundle of Arcade Tokens (a harder tier's:
	-- its own number, Config.Spire.Tiers)
	local tier = Config.spireTier(tierId)
	local tokens = 0
	if before == 0 then
		if tier.id == "Normal" then
			tokens = Config.Arcade and Config.Arcade.FirstClear[tonumber(floorId) or 0] or 0
		else
			tokens = tier.tokens or 0
		end
	end
	if tokens > 0 then
		d.Tokens = (d.Tokens or 0) + tokens
		notify(player, "First win! +" .. tokens .. " ARCADE TOKENS - spin them at the Arcade!", "rare")
	end
	markDirty(player)
	PlayerService.QuestProgress(player, "boss", 1)
	return before == 0
end

-- Oozlet (the intro) has been beaten: saved, so it never comes back
function PlayerService.SetIntroDone(player)
	local profile = profiles[player]
	if profile then
		profile.data.IntroDone = true
		-- (the intro's over: the new player path starts)
		local P = profile.data.Path
		if P and not P.done and P.step == 0 then
			P.step = 1
			PlayerService.PathBegin(player)
		end
		markDirty(player)
	end
end

----------------------------------------------------------------------
-- THE NEW PLAYER PATH (Config.Path). Other services tell it what just
-- happened - PathEvent(player, "Spin" / "Equip" / "Quest" / "Enter" /
-- "Beat") - and it only counts if it's the step you're on: the server saw
-- it happen, so nothing a client says can skip a step or claim its reward.
----------------------------------------------------------------------
local function payPath(player, r)
	if (r.Coins or 0) > 0 then
		PlayerService.AddCoins(player, r.Coins, true)
	end
	if (r.Tokens or 0) > 0 then
		PlayerService.AddTokens(player, r.Tokens)
	end
end
local function rewardWords(r)
	local bits = {}
	if (r.Tokens or 0) > 0 then
		table.insert(bits, "+" .. r.Tokens .. (r.Tokens == 1 and " token" or " tokens"))
	end
	if (r.Coins or 0) > 0 then
		table.insert(bits, "+" .. Config.format(r.Coins) .. " coins")
	end
	return table.concat(bits, ", ")
end

-- a step has just begun: make sure it can be done
function PlayerService.PathBegin(player)
	local profile = profiles[player]
	local P = profile and profile.data.Path
	local step = P and not P.done and Config.Path.Steps[P.step]
	if not step then
		return
	end
	local d = profile.data
	if step.Id == "Spin" and (d.Tokens or 0) < 1 then
		-- (the first spin is on us: nobody gets stuck on step 1)
		d.Tokens = (d.Tokens or 0) + 1
		notify(player, "Here's a token for your first spin!", "rare")
	elseif step.Id == "Quest" and d.Quests and d.Quests.pick then
		-- (already holding a quest: that step's done)
		task.defer(PlayerService.PathEvent, player, "Quest")
	end
	markDirty(player)
end

function PlayerService.PathEvent(player, id)
	local profile = profiles[player]
	local P = profile and profile.data.Path
	if not P or P.done or P.step < 1 then
		return
	end
	local steps = Config.Path.Steps
	local step = steps[P.step]
	if not step or step.Id ~= id then
		return
	end
	payPath(player, step.Reward or {})
	P.step = P.step + 1
	if P.step > #steps then
		P.step = #steps
		P.done = true
		payPath(player, Config.Path.Done or {})
		notify(player, "PATH COMPLETE! You know the way now. " .. rewardWords(Config.Path.Done or {}), "rare")
	else
		notify(player, "Step done! " .. rewardWords(step.Reward or {}) .. "  Next: " .. steps[P.step].Text, "good")
		PlayerService.PathBegin(player)
	end
	markDirty(player)
end

-- A Colosseum run was cleared in `seconds` (worked out by the server) on the
-- difficulty `diffId`. Counts it, keeps the fastest time on that difficulty,
-- and says whether it was the first clear today (ColosseumService pays a
-- bonus for that) and which difficulty it opened, if any. Returns
-- { clears (on every difficulty), wins (on this one), best (on this one),
-- newBest, firstToday, unlocked }, or nil if the player has no data.
function PlayerService.RecordColosseumClear(player, seconds, diffId)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local c = profile.data.Colosseum
	local id = Config.colosseumDifficulty(diffId).id
	-- (which difficulties were locked before this clear)
	local locked = {}
	for _, def in ipairs(Config.Colosseum.Difficulties or {}) do
		locked[def.id] = not Config.colosseumUnlocked(c, def.id)
	end
	c.clears = c.clears + 1
	c.wins[id] = (c.wins[id] or 0) + 1
	local newBest = seconds > 0 and (c.bests[id] == nil or seconds < c.bests[id])
	if newBest then
		c.bests[id] = seconds
	end
	if seconds > 0 and (c.best == nil or seconds < c.best) then
		c.best = seconds -- (the fastest on any difficulty)
	end
	local unlocked = nil
	for _, def in ipairs(Config.Colosseum.Difficulties or {}) do
		if locked[def.id] and Config.colosseumUnlocked(c, def.id) then
			unlocked = def.id
		end
	end
	local today = Config.questDay()
	local firstToday = c.bonusDay ~= today
	if firstToday then
		c.bonusDay = today
	end
	markDirty(player)
	PlayerService.QuestProgress(player, "clear", 1)
	return { clears = c.clears, wins = c.wins[id], best = c.bests[id], newBest = newBest, firstToday = firstToday, unlocked = unlocked }
end

-- Chooses the Colosseum difficulty the player's next runs use (it's saved).
-- Returns true, or false and why not.
function PlayerService.SetColosseumPick(player, diffId)
	local profile = profiles[player]
	if not profile then
		return false, "Not ready yet."
	end
	local def = type(diffId) == "string" and Config.colosseumDifficulty(diffId)
	if not def or def.id ~= diffId then
		return false, "There's no such difficulty."
	end
	local c = profile.data.Colosseum
	if not Config.colosseumUnlocked(c, def.id) then
		return false, "Locked! Clear a run on the one before it first."
	end
	c.pick = def.id
	markDirty(player)
	return true
end

-- Lets another service add an action the client can ask for through the
-- Action RemoteFunction (so it gets the same request budget and argument
-- checks as everything else). handler(player, data, arg) -> ok, message
-- (another service changed a player's data: send them a fresh copy)
function PlayerService.MarkDirty(player)
	if profiles[player] then
		markDirty(player)
	end
end

-- Give a player a weapon to keep (an id in Config.Weapons.List). Returns
-- true if it's new to them (already owned: nothing changes).
function PlayerService.GiveWeapon(player, id)
	local profile = profiles[player]
	local W = Config.Weapons
	if not profile or type(id) ~= "string" or not (W and W.List[id]) then
		return false
	end
	local own = profile.data.Weapons.own
	if own[id] then
		return false
	end
	own[id] = 0
	profile.data.Weapons.found = profile.data.Weapons.found or {}
	profile.data.Weapons.found[id] = true
	markDirty(player)
	return true
end

-- Saves this player right now (a Robux purchase: ShopService). True if it
-- was written to the DataStore.
-- Whether this player's progress is being saved (false after a failed load,
-- or once another server owns their save; true in Studio without saves is
-- not needed - there's nothing to copy into)
function PlayerService.CanSave(player)
	local profile = profiles[player]
	return profile ~= nil and (profile.canSave == true or store == nil)
end

function PlayerService.SaveNow(player)
	return saveProfile(player, false) == true
end

function PlayerService.AddAction(name, handler)
	if type(name) == "string" and type(handler) == "function" then
		handlers[name] = handler
	end
end

-- Power (XP) earned (multiplied by the gain hooks), or exactly `amount` if `raw`
function PlayerService.AddPower(player, amount, raw)
	local profile = profiles[player]
	if profile and finite(amount) then
		if not raw then
			amount = boosted(player, profile.data, "Power", amount)
		end
		local before = Config.levelFromPower(profile.data.Power)
		local new = profile.data.Power + amount
		if not finite(new) then
			warn("[PlayerService] refused a bad power amount: " .. tostring(amount))
			return
		end
		profile.data.Power = math.max(0, new)
		-- (a new level: more max health - every level gives some, Config.LevelBonus)
		if Config.levelFromPower(profile.data.Power) ~= before then
			applyCharacterStats(player, false)
		end
		markDirty(player)
	end
end

----------------------------------------------------------------------
-- Actions (called through the Action RemoteFunction; return ok, message)
----------------------------------------------------------------------
-- Choose a quest at the Quest Board (arg = its place on the board, 1-3).
-- One per set: once you've picked, that's the one until the next set.
handlers.PickQuest = function(player, d, index)
	if not nearStation(player, "Quests") then
		return false, "Walk up to the Quest Board first!"
	end
	local _, paid = ensureQuests(d)
	if paid then
		notify(player, "Your finished quest was handed in for you: " .. paid, "rare")
	end
	if d.Quests.pick then
		return false, "You've already picked one - new quests come every " .. (Config.Quests.Hours or 24) .. " hours."
	end
	local q = type(index) == "number" and d.Quests.list[index]
	local def = q and Config.QuestById[q.id]
	if not def then
		return false, "There's no such quest."
	end
	d.Quests.pick = index
	markDirty(player)
	task.defer(PlayerService.PathEvent, player, "Quest")
	return true, "Quest taken: " .. Config.questText(def)
end

-- Hand in your quest once it's done (coins and Arcade Tokens)
handlers.ClaimQuest = function(player, d)
	if not nearStation(player, "Quests") then
		return false, "Walk up to the Quest Board first!"
	end
	local fresh, paid = ensureQuests(d)
	if fresh then
		markDirty(player)
		if paid then
			return true, "Handed in: " .. paid .. " New quests are up - pick one!"
		end
		return false, "New quests are up - pick one!"
	end
	local q = d.Quests.pick and d.Quests.list[d.Quests.pick]
	local def = q and Config.QuestById[q.id]
	if not def then
		return false, "Pick a quest first!"
	end
	if q.claimed then
		return false, "You've already handed that one in."
	end
	if q.n < def.goal then
		return false, "Not finished yet!"
	end
	local message = payQuest(d, q, def)
	markDirty(player)
	return true, message
end

-- DEV: walk the new player path from step 1 (the steps really have to be
-- done again: spin, equip, pick a quest, enter the Spire, beat Oozark)
handlers.DevPath = function(player, d)
	if not Config.isDev(player) then
		return false, "Dev tools are only for the game's owner."
	end
	d.Path = { step = 1, done = false }
	PlayerService.PathBegin(player)
	markDirty(player)
	return true, "New player path: back to step 1 - " .. Config.Path.Steps[1].Text
end

-- DEV: wipe this player's save back to a brand-new player's (exactly what a
-- first join gets). Only the list of Robux receipts already handed out is
-- kept, so no purchase can ever be paid out twice. (IntroService's
-- "DevResetMe" calls this, then plays the intro.)
function PlayerService.ResetToNew(player)
	local profile = profiles[player]
	if not profile then
		return false
	end
	local old = profile.data
	local fresh = mergeSaved(nil)
	if old.Shop and type(old.Shop.receipts) == "table" then
		fresh.Shop.receipts = old.Shop.receipts
	end
	profile.data = fresh
	ensureQuests(fresh)
	showCleared(player, fresh)
	if profile.leaderPower then
		profile.leaderPower.Value = 0
	end
	if profile.leaderLevel then
		profile.leaderLevel.Value = Config.levelFromPower(0)
	end
	pcall(applyCharacterStats, player, true)
	markDirty(player)
	return true
end

-- Dev test helpers: Studio, or the game's owner in the real game (Config.isDev)
handlers.DevGive = function(player, d, kind)
	if not Config.isDev(player) then
		return false, "Dev tools are only for the game's owner."
	end
	if kind == "Coins" then
		d.Coins = d.Coins + 10000
	elseif kind == "Tokens" then
		d.Tokens = (d.Tokens or 0) + 10
	elseif kind == "Power" then
		d.Power = d.Power + 5000
	else
		return false, "Unknown dev action."
	end
	markDirty(player)
	return true, "Done."
end

-- DEV: become exactly this level, as a real player at that level would be:
-- your Power is set to that level's (so the Colosseum and bosses feel as
-- they're meant to). Your coins are left alone.
handlers.DevSetLevel = function(player, d, level)
	if not Config.isDev(player) then
		return false, "Dev tools are only for the game's owner."
	end
	level = tonumber(level)
	level = finite(level) and math.floor(level) or 0 -- (tonumber("nan") is NaN)
	if level < 1 or level > Config.MaxLevel then
		return false, "Pick a level from 1 to " .. Config.MaxLevel .. "."
	end
	d.Power = Config.powerForLevel(level)
	applyCharacterStats(player, true)
	markDirty(player)
	return true, "You're level " .. level .. " now."
end

----------------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------------
local function onCharacter(player, char)
	-- The ControllerManager (see applyMoveSpeed) can be added a moment after
	-- the character spawns, and Roblox's own setup may reset its speed to the
	-- default right after adding it - so re-apply our speed whenever one shows
	-- up, on the next frame, once that setup has finished.
	char.DescendantAdded:Connect(function(inst)
		if inst:IsA("ControllerManager") then
			task.defer(function()
				local profile = profiles[player]
				if profile and inst.Parent then
					inst.BaseMoveSpeed = Config.walkSpeedFor(player, profile.data)
				end
			end)
		end
	end)

	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		applyCharacterStats(player, true)
	end
end

local function onPlayerAdded(player)
	if started[player] then
		return
	end
	started[player] = true
	-- (the owner's screen shows the DEV button: see Config.isDev)
	if Config.isDev(player) then
		player:SetAttribute("Dev", true)
	end

	-- (back on this same server while their leave-save is still being
	-- written or retried: carry on with that copy - it's newer than anything
	-- in the DataStore, and loading the stored one would roll them back)
	local pending = releasing[player.UserId]
	local saved, ok, stillLocked
	if pending then
		releasing[player.UserId] = nil
		pending.released = nil
		ok = pending.canSave
	else
		saved, ok, stillLocked = loadData(player)
	end
	if not player.Parent then
		if ok and not pending then
			task.spawn(function() -- (left while loading: let go of the lock we just took)
				pcall(function()
					store:UpdateAsync("u_" .. player.UserId, function(old)
						if type(old) == "table" and old._lockJob == JOB then
							old._lockJob = nil
							return old
						end
						return nil
					end)
				end)
			end)
		end
		return
	end
	if stillLocked then
		-- (still being saved by the server they just left: never play on a copy
		-- that might be out of date)
		player:Kick("Your save is still being written by another server. Please rejoin in a minute.")
		return
	end

	local data, swapped, refund
	local profile
	if pending then
		data, swapped, refund = pending.data, 0, 0
		profile = pending
	else
		data, swapped, refund = mergeSaved(saved)
		profile = { data = data, canSave = ok }
	end
	profiles[player] = profile
	ensureQuests(profile.data)
	showCleared(player, profile.data) -- the Spire menu shows them

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	-- Level first so it's the main number on the player list
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = Config.levelFromPower(profile.data.Power)
	level.Parent = ls
	local power = Instance.new("NumberValue")
	power.Name = "Power"
	power.Value = math.floor(profile.data.Power)
	power.Parent = ls
	ls.Parent = player
	profile.leaderPower = power
	profile.leaderLevel = level

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end

	markDirty(player)
	if not ok then
		notify(player, "Couldn't load saved data - progress this session won't be saved.", "bad")
	end
	if swapped > 0 then
		-- (once their screen is up)
		task.delay(6, function()
			if player.Parent then
				notify(player, "* Armour gear is gone from the game: your old gear and chests became " .. swapped .. " Arcade Tokens!", "rare")
			end
		end)
	end
	if refund > 0 then
		task.delay(9, function()
			if player.Parent then
				notify(player, "* The Upgrade Shop, talismans and the Sell Shop are gone: your old upgrades and loot became " .. Config.format(refund) .. " coins!", "rare")
			end
		end)
	end
end

local function onPlayerRemoving(player)
	local profile = profiles[player]
	busy[player] = nil
	if profile then
		releasing[player.UserId] = profile
	end
	local saved = saveProfile(player, true) -- (and let go of the lock)
	profiles[player] = nil
	dirty[player] = nil
	started[player] = nil
	-- a failed leave-save is retried (a few times, further apart each time)
	-- rather than leaving the DataStore with an older copy; the profile stays
	-- in `releasing` until it's written, so rejoining here picks it up
	local tries = 0
	while profile and saved == false and profile.canSave and releasing[player.UserId] == profile and tries < 5 do
		tries += 1
		task.wait(2 ^ tries)
		if releasing[player.UserId] ~= profile then
			return -- (they came back to this server: that copy is live again)
		end
		saved = saveProfile(player, true, profile)
	end
	if releasing[player.UserId] == profile then
		releasing[player.UserId] = nil
	end
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
-- ASKING THE SERVER, FAIRLY. Each player gets a small budget of requests
-- (refilling 10 a second, up to 20 saved up): far more than any real player
-- clicks, but a script firing thousands a second is simply ignored instead of
-- lagging the whole server.
local budgets = setmetatable({}, { __mode = "k" }) -- (forgets players who leave)
allowRequest = function(player)
	local now = os.clock()
	local b = budgets[player]
	if not b then
		b = { tokens = 20, at = now }
		budgets[player] = b
	end
	b.tokens = math.min(20, b.tokens + (now - b.at) * 10)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens = b.tokens - 1
	return true
end

-- What a client sends is checked before any handler sees it: numbers must be
-- real numbers (no NaN, no infinity), and tables small and shallow. Handlers
-- still check that the values make sense for what they do.
saneArg = function(v, depth)
	local t = type(v)
	if t == "number" then
		return v == v and v ~= math.huge and v ~= -math.huge
	elseif t == "string" then
		return #v <= 100
	elseif t == "table" then
		if depth >= 2 then
			return false
		end
		local count = 0
		for k, x in pairs(v) do
			count = count + 1
			if count > 20 or not saneArg(k, depth + 1) or not saneArg(x, depth + 1) then
				return false
			end
		end
		return true
	end
	return t == "nil" or t == "boolean" or t == "Instance"
end

local function buildRemotes()
	local old = ReplicatedStorage:FindFirstChild("Remotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	local function make(className, name)
		local r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		remotes[name] = r
		return r
	end

	make("RemoteEvent", "RequestState") -- client -> server
	make("RemoteEvent", "StateUpdate") -- server -> client: full snapshot
	make("RemoteEvent", "Notify") -- server -> client: (text, kind)
	make("RemoteEvent", "OpenPanel") -- server -> client: panel name
	make("RemoteFunction", "Action") -- client -> server: (name, arg) -> ok, message

	folder.Parent = ReplicatedStorage

	remotes.RequestState.OnServerEvent:Connect(function(player)
		if profiles[player] and allowRequest(player) then
			markDirty(player)
		end
	end)

	remotes.Action.OnServerInvoke = function(player, name, arg)
		if not allowRequest(player) then
			return false, "Slow down!"
		end
		if not saneArg(arg, 0) then
			return false, "Bad request."
		end
		local profile = profiles[player]
		local handler = type(name) == "string" and handlers[name]
		if not profile or not handler then
			return false, "Not ready yet."
		end
		-- ONE AT A TIME: a handler that yields (a web call, a save) could
		-- otherwise be run again by the same player before the first one has
		-- finished, and both would pass its "already claimed?" check
		if busy[player] then
			return false, "One thing at a time!"
		end
		busy[player] = true
		local ok, success, message = pcall(handler, player, profile.data, arg)
		busy[player] = nil
		if not ok then
			warn("[PlayerService] " .. tostring(name) .. " failed: " .. tostring(success))
			return false, "Something went wrong."
		end
		return success, message
	end
end

local function hookPrompt(prompt)
	if hookedPrompts[prompt] then
		return
	end
	hookedPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		local panel = prompt:GetAttribute("Panel")
		if panel then
			remotes.OpenPanel:FireClient(player, panel)
		end
	end)
end

----------------------------------------------------------------------
-- The movement guard
----------------------------------------------------------------------
-- Each player's own computer moves their character (that's how Roblox
-- works), so a cheat can move it anywhere: teleport, run at double speed,
-- fly. The server watches every character ten times a second and, if it
-- moved in a way no player can, puts it back where it last stood fairly:
--   * a TELEPORT: more than TELEPORT_STUDS in one tick
--   * a SPEED hack: faster, averaged over SPEED_WINDOW seconds, than their
--     walk speed allows (with room for rolls and being knocked about)
--   * FLYING: no ground under them for FLY_SECONDS without falling
-- The server's own moves (travelling to the Spire, the Colosseum's trip in and out,
-- the sea washing you back) are allowed: whatever moves a player sets
--   player:SetAttribute("MoveTo", destination)
--   player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + seconds)
-- first, and for that long the player isn't judged (then starts fresh from
-- wherever the move put them).
-- (A client can't set those: attributes a client sets never reach the server.)
local TELEPORT_STUDS = 60 -- straight up in one tick (and the most any one tick may ever move)
local TICK_SLACK = 2.5 -- one tick may move this many times the allowed speed (rolls, lag)
local TICK_MIN = 24 -- ...but never less than this many studs (a lag spike, a knock)
local SPEED_WINDOW = 3
local SPEED_SLACK = 12 -- studs a second on top of walk speed * 1.35
local FLY_SECONDS = 2.5
local FIGHT_FLY_SECONDS = 1.3 -- in an arena: off the floor longer than any jump = hovering
local FIGHT_GROUND_RAY = 7 -- (in an arena the floor has to be right under you)
local FALLING = 1.2 -- studs a tick: dropping at least this fast is really falling
local CORRIDOR = 40 -- a server move: anywhere this close to the line from start to finish
local ARRIVED = 30 -- ...and this close to the finish counts as there
local STRIKE_WINDOW, STRIKE_KICK = 60, 30 -- this many put-backs inside a minute: kicked
local guard = setmetatable({}, { __mode = "k" })

local function flatMag(v)
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- (while a move the server started is under way, the player isn't judged -
-- their screen may take a moment to get them there, and network lag mustn't
-- snap them back mid-trip - but ONLY along the way: somewhere near the line
-- from where they set off to where they're going. Anywhere else is judged as
-- usual, so a server move can't be used as a moment to teleport anywhere.
-- Arriving makes that spot their new starting point.)
-- returns "arrived", "along" or nil
local function sanctioned(player, pos, g)
	local to = player:GetAttribute("MoveTo")
	local untilT = player:GetAttribute("MoveUntil")
	if not (typeof(to) == "Vector3" and type(untilT) == "number" and workspace:GetServerTimeNow() <= untilT) then
		return nil
	end
	if (pos - to).Magnitude <= ARRIVED then
		return "arrived"
	end
	local a = g.good
	local ab = to - a
	local len2 = ab:Dot(ab)
	local t = len2 > 1e-6 and math.clamp((pos - a):Dot(ab) / len2, 0, 1) or 0
	if (pos - (a + ab * t)).Magnitude <= CORRIDOR then
		return "along"
	end
	return nil
end

local function checkMovement(player, dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then
		return
	end
	local pos = root.Position
	local g = guard[player]
	if not g or g.char ~= char then
		-- a new body (joined, respawned): start watching from where it is
		g = { char = char, last = pos, good = pos, history = {}, air = 0, strikes = 0 }
		guard[player] = g
		return
	end
	local now = os.clock()
	local moving = sanctioned(player, pos, g)
	if moving == "arrived" then
		-- a move the server asked for, done: start again from here
		g.last, g.good, g.history, g.air, g.vy = pos, pos, {}, 0, 0
		return
	elseif moving == "along" then
		g.last, g.history, g.air = pos, {}, 0 -- (on the way: not judged, start point kept)
		return
	end

	local why = nil
	local d = PlayerService.GetData(player)
	local limit = Config.walkSpeedFor(player, d) * 1.35 + SPEED_SLACK
	local fighting = player:GetAttribute("SpireFloor") ~= nil or player:GetAttribute("Colosseum") ~= nil
	-- 1. teleports: one tick may only carry them so far (what their speed
	-- allows, with room for a roll or lag), never 60 studs up, and a drop
	-- only as fast as falling gets
	local tickCap = math.min(TELEPORT_STUDS, math.max(TICK_MIN, limit * dt * TICK_SLACK))
	local drop = g.last.Y - pos.Y
	local maxDrop = math.max(TELEPORT_STUDS, (g.vy or 0) * dt + (tonumber(workspace.Gravity) or 196.2) * dt * dt + 10)
	if flatMag(pos - g.last) > tickCap or pos.Y - g.last.Y > TELEPORT_STUDS or drop > maxDrop then
		why = "teleport"
	end
	g.vy = math.max(0, drop / math.max(dt, 1e-3))
	-- 2. speed, averaged so a roll or a knock-back never counts
	table.insert(g.history, { t = now, pos = pos })
	while #g.history > 0 and now - g.history[1].t > SPEED_WINDOW do
		table.remove(g.history, 1)
	end
	local oldest = g.history[1]
	if not why and oldest and now - oldest.t > SPEED_WINDOW * 0.8 then
		-- (the distance actually travelled, every step added up - darting out
		-- and back can't hide behind a small net move)
		local path = 0
		for i = 2, #g.history do
			path = path + flatMag(g.history[i].pos - g.history[i - 1].pos)
		end
		if path / (now - oldest.t) > limit then
			why = "speed"
		end
	end
	-- 3. flying: nothing solid under them, and not really falling (in an
	-- arena: the floor right under them - holding yourself up off it to float
	-- over the shockwaves counts as flying, and is put back down)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	local ground = workspace:Raycast(pos, Vector3.new(0, fighting and -FIGHT_GROUND_RAY or -16, 0), params)
	if ground or drop >= FALLING then
		g.air = 0
	else
		g.air = g.air + dt
		if g.air > (fighting and FIGHT_FLY_SECONDS or FLY_SECONDS) and not why then
			why = "flying"
		end
	end

	if why then
		-- back to where they last stood fairly, stopped dead
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(g.good) * (root.CFrame - root.Position)
		g.last, g.history, g.air, g.vy = g.good, {}, 0, 0
		g.strikes = g.strikes + 1
		if g.strikes == 1 or g.strikes % 20 == 0 then
			warn(string.format("[PlayerService] movement guard: %s (%s) - put back (%d times)", player.Name, why, g.strikes))
		end
		-- (put back again and again inside a minute: no real connection does
		-- that - the session ends rather than playing tug-of-war forever)
		g.recent = g.recent or {}
		table.insert(g.recent, now)
		while g.recent[1] and now - g.recent[1] > STRIKE_WINDOW do
			table.remove(g.recent, 1)
		end
		if #g.recent >= STRIKE_KICK then
			warn("[PlayerService] movement guard: " .. player.Name .. " kicked (" .. why .. ")")
			player:Kick("Your character kept moving in ways the game can't allow. Please rejoin.")
		end
		return
	end
	g.last = pos
	if ground then
		g.good = pos -- (standing on something, having moved fairly)
	end
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function PlayerService.Start()
	if isStarted then
		return
	end
	isStarted = true

	buildRemotes()

	for _, inst in ipairs(CollectionService:GetTagged("PanelPrompt")) do
		hookPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal("PanelPrompt"):Connect(hookPrompt)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	-- Push snapshots to clients (at most ~10 per second per player)
	task.spawn(function()
		while true do
			task.wait(0.1)
			for player in pairs(dirty) do
				dirty[player] = nil
				local profile = profiles[player]
				if profile and player.Parent then
					profile.leaderPower.Value = math.floor(profile.data.Power)
					profile.leaderLevel.Value = Config.levelFromPower(profile.data.Power)
					remotes.StateUpdate:FireClient(player, profile.data)
				end
			end
		end
	end)

	-- New quests at midnight (UTC) for anyone still playing
	task.spawn(function()
		while true do
			task.wait(30)
			for player, profile in pairs(profiles) do
				local fresh, paid = ensureQuests(profile.data)
				if fresh then
					markDirty(player)
					if paid then
						notify(player, "Your finished quest was handed in for you: " .. paid, "rare")
					end
					notify(player, "New quests on the Quest Board!", "ok")
				end
			end
		end
	end)

	-- The movement guard, ten times a second
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(checkMovement, player, dt)
				if not ok then
					warn("[PlayerService] movement guard failed: " .. tostring(err))
				end
			end
		end
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in pairs(profiles) do
				task.spawn(saveProfile, player)
			end
		end
	end)

	game:BindToClose(function()
		-- (wait for every save to finish - up to 25 s of the 30 Roblox gives)
		local left = 0
		for _, p in ipairs(Players:GetPlayers()) do
			left += 1
			task.spawn(function()
				pcall(saveProfile, p, true)
				left -= 1
			end)
		end
		local t0 = os.clock()
		while left > 0 and os.clock() - t0 < 25 do
			task.wait(0.25)
		end
	end)
end

return PlayerService
