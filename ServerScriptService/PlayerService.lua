--[[
	PlayerService  (ModuleScript, parent: ServerScriptService, name: "PlayerService")

	Server-authoritative game logic for the lobby:
	  * per-player data (Power = XP, Coins, Loot, Upgrades, Talismans, Stats, Gear) + DataStore saving
	  * training on the dummy pads (manual clicks + auto-train)
	  * Sell Shop, Upgrade Shop, Talisman crafting/equipping, stat points, gear
	  * daily quests (the Quest Board)
	  * remotes for the HUD

	Hooks for your future arena scripts:
	    local PlayerService = require(game.ServerScriptService.PlayerService)
	    PlayerService.AddLoot(player, "Scrap", 3)   --> returns how many actually fit
	    PlayerService.AddCoins(player, 50)
	    PlayerService.AddPower(player, 10)
	    PlayerService.GetData(player)               --> the live data table (or nil)
	    PlayerService.QuestProgress(player, "spar", 1) --> counts towards today's quests of that kind
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))

local PlayerService = {}

local STORE_NAME = "BossGrowLobby_v1"
local AUTOSAVE_SECONDS = 90

local profiles = {} -- [player] = { data = {...}, canSave = bool, ... }
local dirty = {} -- [player] = true when the client needs a fresh snapshot
local lastHit = {} -- [player] = os.clock() of last accepted training hit
local combos = {} -- [player] = { count, zone, lastAt } for manual training hits
local started = {} -- [player] = true once onPlayerAdded ran
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
	local loot = {}
	for _, m in ipairs(Config.Materials) do
		loot[m.id] = 0
	end
	local ups = {}
	for _, u in ipairs(Config.Upgrades) do
		ups[u.id] = 0
	end
	return {
		Power = 0,
		Coins = 0,
		Prestige = 0,
		Loot = loot,
		Upgrades = ups,
		Owned = {},
		Equipped = {},
		Auto = false,
		Cleared = {}, -- ["1"] = how many times you've killed floor 1's boss
		-- gear (see ReplicatedStorage.Items). Items: [uid] = { id, r = rolls,
		-- t = when it dropped, lock = true if protected from salvaging}
		Items = {},
		Gear = {}, -- [slot] = uid of the item worn there
		Chests = {}, -- ["1"] = unopened treasure chests from floor 1's boss
		NextId = 1, -- (each item gets a new, never-reused id)
		BestLevel = 1, -- the highest level you've ever reached (gear needs it)
		Stats = {}, -- stat points spent: [stat] = points (see Config.StatPoints)
		-- today's quests (see Config.Quests): which day they're for, and for
		-- each one how far along you are and whether you've handed it in
		-- (three are offered each day; `pick` is the one you chose, 1-3)
		Quests = { day = 0, list = {}, pick = nil },
	}
end

-- Copy only the fields we know about, so old/edited saves can't break anything
local function mergeSaved(saved)
	local d = defaultData()
	if type(saved) ~= "table" then
		return d
	end
	if type(saved.Power) == "number" then
		d.Power = saved.Power
	end
	if type(saved.Coins) == "number" then
		d.Coins = saved.Coins
	end
	-- (prestige is gone: every prestige you had becomes one of Oozark's
	-- treasure chests, once, and your count goes back to 0)
	local oldPrestige = type(saved.Prestige) == "number" and math.floor(saved.Prestige) or 0
	if type(saved.Loot) == "table" then
		for id in pairs(d.Loot) do
			if type(saved.Loot[id]) == "number" then
				d.Loot[id] = saved.Loot[id]
			end
		end
	end
	if type(saved.Upgrades) == "table" then
		for id in pairs(d.Upgrades) do
			if type(saved.Upgrades[id]) == "number" then
				d.Upgrades[id] = saved.Upgrades[id]
			end
		end
	end
	if type(saved.Owned) == "table" then
		for id in pairs(Config.TalismanById) do
			if saved.Owned[id] == true then
				d.Owned[id] = true
			end
		end
	end
	if type(saved.Equipped) == "table" then
		for id in pairs(Config.TalismanById) do
			if saved.Equipped[id] == true and d.Owned[id] then
				d.Equipped[id] = true
			end
		end
	end
	d.Auto = saved.Auto == true
	if type(saved.Cleared) == "table" then
		for floorId in pairs(Config.Bosses or {}) do
			local n = saved.Cleared[tostring(floorId)]
			if type(n) == "number" and n > 0 then
				d.Cleared[tostring(floorId)] = math.floor(n)
			end
		end
	end
	-- gear: only real items, with rolls kept inside their item's ranges
	if type(saved.NextId) == "number" then
		d.NextId = math.max(1, math.floor(saved.NextId))
	end
	if type(saved.BestLevel) == "number" then
		d.BestLevel = math.max(1, math.floor(saved.BestLevel))
	end
	if type(saved.Items) == "table" then
		for uid, rec in pairs(saved.Items) do
			local def = type(uid) == "string" and type(rec) == "table" and Items.ById[rec.id]
			if def then
				local r = {}
				for stat, range in pairs(def.stats) do
					local v = type(rec.r) == "table" and rec.r[stat]
					r[stat] = type(v) == "number" and math.clamp(math.floor(v), range[1], range[2]) or range[1]
				end
				d.Items[uid] = { id = def.id, r = r, t = type(rec.t) == "number" and rec.t or 0, lock = rec.lock == true or nil }
			end
		end
	end
	if type(saved.Gear) == "table" then
		for _, slot in ipairs(Items.Slots) do
			local uid = saved.Gear[slot]
			local rec = type(uid) == "string" and d.Items[uid]
			if rec and Items.ById[rec.id].slot == slot then
				d.Gear[slot] = uid
			end
		end
	end
	if type(saved.Chests) == "table" then
		for floorId in pairs(Items.ByFloor) do
			local n = saved.Chests[tostring(floorId)]
			if type(n) == "number" and n > 0 then
				d.Chests[tostring(floorId)] = math.floor(n)
			end
		end
	end
	-- quests: only real ones, and only kept if they're still today's
	-- (anything older is thrown away and today's are dealt out fresh)
	if type(saved.Quests) == "table" and saved.Quests.day == Config.questDay() and type(saved.Quests.list) == "table" then
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
	if oldPrestige > 0 then
		d.Chests["1"] = (d.Chests["1"] or 0) + math.min(oldPrestige, 100)
	end
	-- stat points: only real stats, and never more than you've earned
	if type(saved.Stats) == "table" then
		for _, st in ipairs(Config.StatPoints.Stats) do
			local v = saved.Stats[st.id]
			if type(v) == "number" and v > 0 then
				d.Stats[st.id] = math.floor(v)
			end
		end
		if Config.statPointsSpent(d) > Config.statPointsTotal(d) then
			d.Stats = {}
		end
	end
	return d
end

-- the highest Spire floor this player has ever cleared (0 = none yet)
local function highestCleared(d)
	local best = 0
	for key, n in pairs(d.Cleared or {}) do
		local id = tonumber(key)
		if id and n > 0 and id > best then
			best = id
		end
	end
	return best
end

-- SAVING, SAFELY. Only one server may own a player's save at a time: when a
-- server loads it, it writes its own id into it (a "lock"), keeps that fresh
-- with every autosave, and lets go when the player leaves. Another server
-- that loads the save while it's locked waits for the lock to be let go -
-- so hopping servers can never load an old copy of your save before the last
-- server has finished writing the new one (that would let you open a chest,
-- hop, and have it back; with trading, it would copy items). A lock older than
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

-- `release` = true when the player is leaving: the lock is let go
local function saveProfile(player, release)
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return
	end
	local key = "u_" .. player.UserId
	for attempt = 1, 3 do
		local stolen = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				if type(old) == "table" and old._lockJob and old._lockJob ~= JOB then
					stolen = true
					return nil -- (another server owns it now: never write over its copy)
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
			return
		end
		warn("[PlayerService] save failed (" .. attempt .. "/3): " .. tostring(err))
		task.wait(1)
	end
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
-- Humanoid.WalkSpeed is ignored - which is why the Swift Boots upgrade changed
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

-- Which training pad (if any) a world position is standing on
local function zoneAt(position)
	-- (the training pads are gone - the Colosseum stands where they were -
	-- so nowhere counts as a pad any more)
	if true then
		return 0
	end
	local half = Config.Yard.PadSize / 2
	for i = 1, #Config.Zones do
		local c = Config.zonePosition(i)
		-- (measured from the pad's own ground: the terrace's pads are a step up)
		if math.abs(position.X - c.X) <= half and math.abs(position.Z - c.Z) <= half and position.Y > c.Y - 3 and position.Y < c.Y + 14 then
			return i
		end
	end
	return 0
end

-- comboCount is nil for auto-train hits (they don't build or use the combo)
local function giveTrainingPower(player, zoneIndex, comboCount)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.data
	local comboMult = comboCount and Config.comboMult(comboCount) or 1
	local gain = Config.BaseTrainGain * Config.Zones[zoneIndex].mult * Config.stats(d).powerMult * comboMult
	d.Power = d.Power + gain
	markDirty(player)
	remotes.TrainFeedback:FireClient(player, gain, zoneIndex, comboCount or 0, comboMult)
end

-- Counts consecutive manual hits on the same dummy. A pause longer than
-- Config.ComboWindow, or switching dummies, starts it over at 1.
local function nextCombo(player, zoneIndex, now)
	local c = combos[player]
	if c and c.zone == zoneIndex and now - c.lastAt <= Config.ComboWindow then
		c.count = c.count + 1
	else
		c = { count = 1, zone = zoneIndex }
		combos[player] = c
	end
	c.lastAt = now
	return c.count
end

----------------------------------------------------------------------
-- Daily quests
----------------------------------------------------------------------
-- Deals out today's quests if the ones you have are from another day.
-- Returns true if it did (so the screen needs the new ones).
local function ensureQuests(d)
	local today = Config.questDay()
	if d.Quests.day == today and #d.Quests.list == Config.Quests.PerDay then
		return false
	end
	d.Quests = { day = today, list = {}, pick = nil }
	for _, id in ipairs(Config.questsForDay(today)) do
		table.insert(d.Quests.list, { id = id, n = 0, claimed = false })
	end
	return true
end

-- Something happened that counts towards quests of this kind
-- ("train", "combo", "spar", "boss", "sell", "chest").
function PlayerService.QuestProgress(player, kind, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.data
	local changed = ensureQuests(d)
	-- (all three count from the start of the day, so whichever you pick
	-- already has everything you've done today - even before you picked it)
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

function PlayerService.AddLoot(player, materialId, amount)
	local profile = profiles[player]
	if not profile or not Config.MaterialById[materialId] then
		return 0
	end
	local d = profile.data
	local space = Config.stats(d).capacity - Config.lootCount(d)
	local added = math.max(0, math.min(math.floor(amount), space))
	if added > 0 then
		d.Loot[materialId] = d.Loot[materialId] + added
		markDirty(player)
	end
	return added
end

function PlayerService.AddCoins(player, amount)
	local profile = profiles[player]
	if profile then
		profile.data.Coins = profile.data.Coins + amount
		markDirty(player)
	end
end

-- A boss on `floorId` died with this player in the arena. Returns true if it
-- was their first time beating it (BossService pays a bigger reward for that).
function PlayerService.RecordBossKill(player, floorId)
	local profile = profiles[player]
	if not profile then
		return false
	end
	local d = profile.data
	d.Cleared = d.Cleared or {}
	local key = tostring(floorId)
	local before = d.Cleared[key] or 0
	d.Cleared[key] = before + 1
	player:SetAttribute("SpireCleared", highestCleared(d))
	markDirty(player)
	PlayerService.QuestProgress(player, "boss", 1)
	return before == 0
end

-- A treasure chest from floor `floorId`'s boss, into the bag (unopened)
function PlayerService.AddChest(player, floorId, count)
	local profile = profiles[player]
	if not profile or not Items.ByFloor[floorId] then
		return
	end
	local d = profile.data
	local key = tostring(floorId)
	d.Chests[key] = (d.Chests[key] or 0) + (count or 1)
	markDirty(player)
end

function PlayerService.AddPower(player, amount)
	local profile = profiles[player]
	if profile then
		profile.data.Power = profile.data.Power + amount
		markDirty(player)
	end
end

----------------------------------------------------------------------
-- Actions (called through the Action RemoteFunction; return ok, message)
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Gear: open chests, wear, take off, lock, salvage. Everything is decided
-- here on the server; the client only asks.
----------------------------------------------------------------------
local chestRng = Random.new()

handlers.OpenChest = function(player, d, floorId)
	floorId = tonumber(floorId)
	local key = floorId and tostring(floorId)
	if not key or (d.Chests[key] or 0) < 1 then
		return false, "You don't have that chest."
	end
	if Items.count(d) >= Items.BagSize then
		return false, "Your bag is full! Salvage something first."
	end
	local def = Items.rollDrop(floorId, chestRng)
	if not def then
		return false, "That chest is empty?!"
	end
	d.Chests[key] = d.Chests[key] - 1
	if d.Chests[key] <= 0 then
		d.Chests[key] = nil
	end
	local uid = tostring(player.UserId) .. "-" .. tostring(d.NextId)
	d.NextId = d.NextId + 1
	local rec = { id = def.id, r = Items.rollStats(def, chestRng), t = os.time() }
	d.Items[uid] = rec
	markDirty(player)
	PlayerService.QuestProgress(player, "chest", 1)
	-- the whole server hears about the big ones
	local rarity = Items.RarityById[def.rarity]
	if rarity.rank >= Items.RarityById.Legendary.rank then
		local msg = string.format("* %s pulled a %s %s!", player.DisplayName, string.upper(def.rarity), def.name)
		for _, other in ipairs(Players:GetPlayers()) do
			notify(other, msg, "rare")
		end
	end
	return true, { uid = uid, item = rec }
end

handlers.EquipItem = function(player, d, uid)
	local rec = type(uid) == "string" and d.Items[uid]
	local def = rec and Items.ById[rec.id]
	if not def then
		return false, "You don't have that item."
	end
	if Items.gearLevel(d) < def.level then
		return false, "You need to reach Level " .. def.level .. " to wear that."
	end
	d.Gear[def.slot] = uid
	applyCharacterStats(player, false)
	markDirty(player)
	return true
end

handlers.UnequipSlot = function(player, d, slot)
	if type(slot) ~= "string" or not d.Gear[slot] then
		return false, "Nothing to take off."
	end
	d.Gear[slot] = nil
	applyCharacterStats(player, false)
	markDirty(player)
	return true
end

handlers.LockItem = function(player, d, uid)
	local rec = type(uid) == "string" and d.Items[uid]
	if not rec then
		return false, "You don't have that item."
	end
	rec.lock = (not rec.lock) or nil
	markDirty(player)
	return true
end

handlers.SalvageItem = function(player, d, uid)
	local rec = type(uid) == "string" and d.Items[uid]
	local def = rec and Items.ById[rec.id]
	if not def then
		return false, "You don't have that item."
	end
	if rec.lock then
		return false, "It's locked - unlock it first."
	end
	for _, worn in pairs(d.Gear) do
		if worn == uid then
			return false, "Take it off first."
		end
	end
	local coins = math.floor(Items.RarityById[def.rarity].salvage * def.floor)
	d.Items[uid] = nil
	d.Coins = d.Coins + coins
	markDirty(player)
	return true, coins
end

handlers.BuyUpgrade = function(player, d, id)
	local def = type(id) == "string" and Config.UpgradeById[id]
	if not def then
		return false, "Unknown upgrade."
	end
	if not nearStation(player, "Upgrades") then
		return false, "Walk up to the Upgrade Shop first!"
	end
	local level = d.Upgrades[id] or 0
	if level >= def.maxLevel then
		return false, "Already maxed out!"
	end
	local cost = Config.upgradeCost(def, level)
	if d.Coins < cost then
		return false, "Not enough coins (need " .. Config.format(cost) .. ")."
	end
	d.Coins = d.Coins - cost
	d.Upgrades[id] = level + 1
	applyCharacterStats(player, false)
	markDirty(player)
	return true, def.name .. " is now level " .. (level + 1) .. "!"
end

handlers.Sell = function(player, d, arg)
	if not nearStation(player, "Sell") then
		return false, "Walk up to the Sell Shop first!"
	end
	local s = Config.stats(d)
	local total = 0
	local items = 0

	local function sellMaterial(m)
		local n = d.Loot[m.id] or 0
		if n > 0 then
			total = total + n * m.sell
			items = items + n
			d.Loot[m.id] = 0
		end
	end

	if arg == "All" then
		for _, m in ipairs(Config.Materials) do
			sellMaterial(m)
		end
	elseif type(arg) == "string" and Config.MaterialById[arg] then
		sellMaterial(Config.MaterialById[arg])
	else
		return false, "Unknown item."
	end

	if items == 0 then
		return false, "Nothing to sell."
	end
	local coins = math.floor(total * s.coinMult)
	d.Coins = d.Coins + coins
	markDirty(player)
	PlayerService.QuestProgress(player, "sell", items)
	return true, "Sold " .. items .. (items == 1 and " item" or " items") .. " for " .. Config.format(coins) .. " coins!"
end

handlers.Craft = function(player, d, id)
	local t = type(id) == "string" and Config.TalismanById[id]
	if not t then
		return false, "Unknown talisman."
	end
	if not nearStation(player, "Craft") then
		return false, "Walk up to the Workbench first!"
	end
	if d.Owned[id] then
		return false, "You already crafted that one."
	end
	if d.Coins < t.cost.coins then
		return false, "Not enough coins."
	end
	for matId, need in pairs(t.cost.materials) do
		if (d.Loot[matId] or 0) < need then
			return false, "Missing materials."
		end
	end
	d.Coins = d.Coins - t.cost.coins
	for matId, need in pairs(t.cost.materials) do
		d.Loot[matId] = d.Loot[matId] - need
	end
	d.Owned[id] = true
	local equipped = false
	if Config.equippedCount(d) < Config.TalismanSlots then
		d.Equipped[id] = true
		equipped = true
	end
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Crafted " .. t.name .. (equipped and " and equipped it!" or "! Equip it from the list.")
end

handlers.Equip = function(player, d, id)
	if type(id) ~= "string" or not Config.TalismanById[id] or not d.Owned[id] then
		return false, "You don't own that talisman."
	end
	if d.Equipped[id] then
		return false, "Already equipped."
	end
	if Config.equippedCount(d) >= Config.TalismanSlots then
		return false, "All talisman slots are full. Unequip one first."
	end
	d.Equipped[id] = true
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Equipped " .. Config.TalismanById[id].name .. "."
end

handlers.Unequip = function(player, d, id)
	if type(id) ~= "string" or not d.Equipped[id] then
		return false, "That talisman isn't equipped."
	end
	d.Equipped[id] = nil
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Unequipped."
end

-- Stat points: spend `n` (1-100) on a stat, or reset them all (free)
handlers.SpendStat = function(player, d, arg)
	local stat = type(arg) == "table" and arg.stat
	local n = type(arg) == "table" and arg.n or 1
	if type(stat) ~= "string" or not Config.StatById[stat] then
		return false, "Unknown stat."
	end
	-- (a real, whole number: NaN or infinity here used to be written straight
	-- into your stats, and a save with NaN in it can't be written at all)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return false, "Bad amount."
	end
	n = math.clamp(math.floor(n), 1, 100)
	n = math.min(n, Config.statPointsLeft(d))
	if n < 1 then
		return false, "No stat points left - level up for more!"
	end
	d.Stats[stat] = (d.Stats[stat] or 0) + n
	applyCharacterStats(player, false)
	markDirty(player)
	return true
end

handlers.ResetStats = function(player, d)
	for id in pairs(d.Stats) do
		d.Stats[id] = 0
	end
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Stat points refunded."
end

-- Choose today's quest at the Quest Board (arg = its place on the board, 1-3).
-- One a day: once you've picked, that's the one.
handlers.PickQuest = function(player, d, index)
	if not nearStation(player, "Quests") then
		return false, "Walk up to the Quest Board first!"
	end
	ensureQuests(d)
	if d.Quests.pick then
		return false, "You've already picked today's quest."
	end
	local q = type(index) == "number" and d.Quests.list[index]
	local def = q and Config.QuestById[q.id]
	if not def then
		return false, "There's no such quest."
	end
	d.Quests.pick = index
	markDirty(player)
	return true, "Quest taken: " .. Config.questText(def)
end

-- Hand in today's quest once it's done
handlers.ClaimQuest = function(player, d)
	if not nearStation(player, "Quests") then
		return false, "Walk up to the Quest Board first!"
	end
	if ensureQuests(d) then
		markDirty(player)
		return false, "A new day - new quests!"
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
	q.claimed = true
	d.Coins = d.Coins + def.reward
	markDirty(player)
	return true, "+" .. Config.format(def.reward) .. " coins!"
end

handlers.SetAuto = function(player, d, on)
	d.Auto = (on == true)
	markDirty(player)
	return true
end

-- Studio-only test helpers (the arena doesn't exist yet, so nothing drops loot)
handlers.DevGive = function(player, d, kind)
	if not RunService:IsStudio() then
		return false, "Dev tools only work in Studio."
	end
	if kind == "Loot" then
		for _, m in ipairs(Config.Materials) do
			PlayerService.AddLoot(player, m.id, 5)
		end
		return true, "Gave test loot."
	elseif kind == "Coins" then
		d.Coins = d.Coins + 10000
	elseif kind == "Power" then
		d.Power = d.Power + 5000
	elseif kind == "MaxUpgrades" then
		for _, u in ipairs(Config.Upgrades) do
			d.Upgrades[u.id] = u.maxLevel
		end
		applyCharacterStats(player, false)
	else
		return false, "Unknown dev action."
	end
	markDirty(player)
	return true, "Done."
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
	player:SetAttribute("CurrentZone", 0)

	local saved, ok, stillLocked = loadData(player)
	if not player.Parent then
		return
	end
	if stillLocked then
		-- (still being saved by the server they just left: never play on a copy
		-- that might be out of date)
		player:Kick("Your save is still being written by another server. Please rejoin in a minute.")
		return
	end

	local profile = { data = mergeSaved(saved), canSave = ok }
	profiles[player] = profile
	ensureQuests(profile.data)
	player:SetAttribute("SpireCleared", highestCleared(profile.data)) -- the Spire menu shows it

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
end

local function onPlayerRemoving(player)
	saveProfile(player, true) -- (and let go of the lock)
	profiles[player] = nil
	dirty[player] = nil
	lastHit[player] = nil
	combos[player] = nil
	started[player] = nil
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
	make("RemoteEvent", "Train") -- client -> server: one click
	make("RemoteEvent", "TrainFeedback") -- server -> client: (gain, zoneIndex)
	make("RemoteEvent", "Notify") -- server -> client: (text, kind)
	make("RemoteEvent", "OpenPanel") -- server -> client: panel name
	make("RemoteFunction", "Action") -- client -> server: (name, arg) -> ok, message

	folder.Parent = ReplicatedStorage

	remotes.RequestState.OnServerEvent:Connect(function(player)
		if profiles[player] and allowRequest(player) then
			markDirty(player)
		end
	end)

	remotes.Train.OnServerEvent:Connect(function(player)
		local profile = profiles[player]
		if not profile then
			return
		end
		local now = os.clock()
		if now - (lastHit[player] or 0) < Config.TrainMinInterval then
			return
		end
		local zi = player:GetAttribute("CurrentZone")
		if type(zi) ~= "number" or zi < 1 then
			return
		end
		if profile.data.Power < Config.Zones[zi].req then
			return -- pad still locked
		end
		lastHit[player] = now
		local combo = nextCombo(player, zi, now)
		giveTrainingPower(player, zi, combo)
		PlayerService.QuestProgress(player, "train", 1)
		if combo == 100 then
			PlayerService.QuestProgress(player, "combo", 1)
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
		local ok, success, message = pcall(handler, player, profile.data, arg)
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
-- The server's own moves (travelling to the Spire, the Colosseum's pipe,
-- the sea washing you back) are allowed: whatever moves a player sets
--   player:SetAttribute("MoveTo", destination)
--   player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + seconds)
-- first, and for that long the player isn't judged (then starts fresh from
-- wherever the move put them).
-- (A client can't set those: attributes a client sets never reach the server.)
local TELEPORT_STUDS = 60
local SPEED_WINDOW = 3
local SPEED_SLACK = 12 -- studs a second on top of walk speed * 1.35
local FLY_SECONDS = 2.5
local guard = setmetatable({}, { __mode = "k" })

local function flatMag(v)
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- (while a move the server started is under way, the player isn't judged at
-- all - their screen may take a moment to get them there, and network lag
-- mustn't snap them back mid-trip - and once it's over, wherever they are
-- is their new starting point)
local function sanctioned(player, pos)
	local to = player:GetAttribute("MoveTo")
	local untilT = player:GetAttribute("MoveUntil")
	return typeof(to) == "Vector3" and type(untilT) == "number" and workspace:GetServerTimeNow() <= untilT
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
	if sanctioned(player, pos) then
		-- a move the server asked for: start again from here
		g.last, g.good, g.history, g.air = pos, pos, {}, 0
		return
	end

	local why = nil
	-- 1. teleports
	if flatMag(pos - g.last) > TELEPORT_STUDS or pos.Y - g.last.Y > TELEPORT_STUDS then
		why = "teleport"
	end
	-- 2. speed, averaged so a roll or a knock-back never counts
	table.insert(g.history, { t = now, pos = pos })
	while #g.history > 0 and now - g.history[1].t > SPEED_WINDOW do
		table.remove(g.history, 1)
	end
	local oldest = g.history[1]
	if not why and oldest and now - oldest.t > SPEED_WINDOW * 0.8 then
		local d = PlayerService.GetData(player)
		local limit = Config.walkSpeedFor(player, d) * 1.35 + SPEED_SLACK
		if flatMag(pos - oldest.pos) / (now - oldest.t) > limit then
			why = "speed"
		end
	end
	-- 3. flying: nothing under them, and not coming down
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local ground = workspace:Raycast(pos, Vector3.new(0, -16, 0), params)
	if ground or pos.Y < g.last.Y - 0.3 then
		g.air = 0
	else
		g.air = g.air + dt
		if g.air > FLY_SECONDS and not why then
			why = "flying"
		end
	end

	if why then
		-- back to where they last stood fairly, stopped dead
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(g.good) * (root.CFrame - root.Position)
		g.last, g.history, g.air = g.good, {}, 0
		g.strikes = g.strikes + 1
		if g.strikes == 1 or g.strikes % 20 == 0 then
			warn(string.format("[PlayerService] movement guard: %s (%s) - put back (%d times)", player.Name, why, g.strikes))
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
					profile.data.BestLevel = math.max(profile.data.BestLevel or 1, profile.leaderLevel.Value)
					remotes.StateUpdate:FireClient(player, profile.data)
				end
			end
		end
	end)

	-- Work out which pad each player is standing on
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in pairs(profiles) do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local zi = root and zoneAt(root.Position) or 0
				if player:GetAttribute("CurrentZone") ~= zi then
					player:SetAttribute("CurrentZone", zi)
				end
			end
		end
	end)

	-- Auto-train ticks
	task.spawn(function()
		while true do
			task.wait(Config.AutoInterval)
			for player, profile in pairs(profiles) do
				if profile.data.Auto then
					local zi = player:GetAttribute("CurrentZone")
					if type(zi) == "number" and zi > 0 and profile.data.Power >= Config.Zones[zi].req then
						giveTrainingPower(player, zi)
					end
				end
			end
		end
	end)

	-- New quests at midnight (UTC) for anyone still playing
	task.spawn(function()
		while true do
			task.wait(30)
			for player, profile in pairs(profiles) do
				if ensureQuests(profile.data) then
					markDirty(player)
					notify(player, "New daily quests on the Quest Board!", "ok")
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
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(saveProfile, p, true)
		end
		task.wait(3)
	end)
end

return PlayerService
