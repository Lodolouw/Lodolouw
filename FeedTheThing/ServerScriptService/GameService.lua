--[[
	GameService  (ModuleScript, parent: ServerScriptService, name: "GameService")

	The server's side of the whole game: hands out plots, grows the garden,
	harvests when you walk past, checks every toss, fills the belly, hatches
	eggs, runs the yard and its income, the seed shop, the weather, the daily
	craving, offline coins and the friend bonus.

	The server decides everything; the clients only draw it. What a client
	needs to draw lives in two places:
	  * ReplicatedStorage.Plots.PlotN attributes - public (everyone sees
	    your plants, your Thing's size and your Thinglets)
	  * the "State" remote - private (your coins, basket, belly, shop...)
]]

local GameService = {}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	Toss = remoteFolder:WaitForChild("Toss") :: RemoteEvent,
	TossResult = remoteFolder:WaitForChild("TossResult") :: RemoteEvent,
	State = remoteFolder:WaitForChild("State") :: RemoteEvent,
	Notify = remoteFolder:WaitForChild("Notify") :: RemoteEvent,
	Hatched = remoteFolder:WaitForChild("Hatched") :: RemoteEvent,
	Harvested = remoteFolder:WaitForChild("Harvested") :: RemoteEvent,
	Fx = remoteFolder:WaitForChild("Fx") :: RemoteEvent,
	Action = remoteFolder:WaitForChild("Action") :: RemoteFunction,
}

local DataService, WorldBuilder -- handed in by Main

local W = Config.World
local sessions = {} -- [player] = session (see onPlayerAdded)
local plotOwners = {} -- [plot index] = player
local plotFolders = {} -- [plot index] = Folder in ReplicatedStorage.Plots
local friendCache = {} -- ["a_b"] = true/false
local currentWeather = ""

local MUT_LETTER = { [""] = "N" }
for _, mutation in ipairs(Config.Mutations) do
	MUT_LETTER[mutation.id] = mutation.letter
end
-- best variant first when tossing (it pays the most)
local TOSS_ORDER = { "Gold", "Glowing", "Frozen", "Normal" }

local function now()
	return workspace:GetServerTimeNow()
end

local function weatherNow()
	return (Rules.weatherAt(now()))
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function basketCount(data, cropId)
	local variants = data.basket[cropId]
	if not variants then
		return 0
	end
	local total = 0
	for _, count in pairs(variants) do
		total += count
	end
	return total
end

local function basketAdd(data, cropId, mutation, amount)
	local key = (mutation == nil or mutation == "") and "Normal" or mutation
	data.basket[cropId] = data.basket[cropId] or {}
	data.basket[cropId][key] = (data.basket[cropId][key] or 0) + (amount or 1)
end

-- Takes one of this food out of the basket, best variant first.
-- Returns the mutation id ("" for normal), or nil if there's none.
local function basketTake(data, cropId)
	local variants = data.basket[cropId]
	if not variants then
		return nil
	end
	for _, key in ipairs(TOSS_ORDER) do
		if (variants[key] or 0) > 0 then
			variants[key] -= 1
			return key == "Normal" and "" or key
		end
	end
	return nil
end

local function plantedKinds(data)
	local kinds, seen = {}, {}
	for _, plant in ipairs(data.plants) do
		if not seen[plant.crop] then
			seen[plant.crop] = true
			table.insert(kinds, plant.crop)
		end
	end
	return kinds
end

local function character(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function flatDistance(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function hatchPosition(s)
	return (Rules.plotCFrame(s.plot) * CFrame.new(W.Hatch)).Position
end

local function spotPosition(s, spot)
	return (Rules.plotCFrame(s.plot) * CFrame.new(W.PlantSpots[spot])).Position
end

local function notify(player, payload)
	remotes.Notify:FireClient(player, payload)
end

local function announce(text, color)
	remotes.Notify:FireAllClients({ type = "announce", text = text, color = color })
end

local function markDirty(s)
	s.dirty = true
end

----------------------------------------------------------------------
-- Publishing what everyone can see (plot attributes)
----------------------------------------------------------------------
local function publishPlants(s)
	local list = {}
	for i, plant in ipairs(s.data.plants) do
		local letters = {}
		for _, mutation in ipairs(plant.fruit) do
			table.insert(letters, MUT_LETTER[mutation] or "N")
		end
		-- a = when its delivery lands (clients hide it until then)
		local arriving = plant.arrive and plant.arrive > now() and plant.arrive or nil
		list[i] = { c = plant.crop, f = table.concat(letters), a = arriving }
	end
	plotFolders[s.plot]:SetAttribute("Plants", HttpService:JSONEncode(list))
end

local function publishYard(s)
	local list = {}
	for _, t in ipairs(s.data.yard) do
		table.insert(list, { id = t.id, k = t.kind, m = t.mut, b = t.born, s = t.start, slot = t.slot })
	end
	plotFolders[s.plot]:SetAttribute("Yard", HttpService:JSONEncode(list))
end

local function publishSign(s)
	local size = Config.Thing.Sizes[s.size]
	WorldBuilder.setSign(s.plot, s.player.DisplayName .. "'s Basement", "Size " .. s.size .. ": " .. size.name, s.player.UserId)
end

local function publishPlot(s)
	local folder = plotFolders[s.plot]
	folder:SetAttribute("Owner", s.player.UserId)
	folder:SetAttribute("OwnerName", s.player.DisplayName)
	folder:SetAttribute("ThingSize", s.size)
	folder:SetAttribute("PlotsOwned", s.data.plots)
	WorldBuilder.setPlotsOwned(s.plot, s.data.plots)
	publishSign(s)
	publishPlants(s)
	publishYard(s)
end

local function clearPlot(i)
	local folder = plotFolders[i]
	folder:SetAttribute("Owner", 0)
	folder:SetAttribute("OwnerName", "")
	folder:SetAttribute("ThingSize", 1)
	folder:SetAttribute("PlotsOwned", 0)
	folder:SetAttribute("Plants", "[]")
	folder:SetAttribute("Yard", "[]")
	WorldBuilder.setPlotsOwned(i, 0)
	WorldBuilder.setSign(i, "Free plot", "", 0)
end

----------------------------------------------------------------------
-- The private state each player's client draws its HUD from
----------------------------------------------------------------------
local function refreshShop(s)
	local index = Rules.restockIndex(now())
	if s.data.shop.index ~= index then
		s.data.shop = { index = index, bought = {} }
	end
	if s.stockIndex ~= index then
		s.stockIndex = index
		s.stock = Rules.stockFor(s.player.UserId, index)
		return true
	end
	return false
end

-- -1 = always in stock
local function stockLeft(s, cropId)
	local total = s.stock[cropId] or 0
	if total < 0 then
		return -1
	end
	return math.max(0, total - (s.data.shop.bought[cropId] or 0))
end

local function refreshDaily(s)
	local day = Rules.dayIndex(now())
	local daily = s.data.daily
	if daily.day ~= day or daily.food == "" then
		s.data.daily = { day = day, food = Rules.dailyFood(s.player.UserId, day, plantedKinds(s.data)), fed = 0, done = false }
		return true
	end
	return false
end

local function yardIncome(s)
	local t = now()
	local total = 0
	for _, record in ipairs(s.data.yard) do
		total += Rules.income(record, t)
	end
	return total * (1 + s.friendBonus)
end

local function buildState(s)
	local data = s.data
	local stock = {}
	for _, crop in ipairs(Config.Crops) do
		stock[crop.id] = stockLeft(s, crop.id)
	end
	local plants = {}
	for _, plant in ipairs(data.plants) do
		table.insert(plants, plant.crop)
	end
	return {
		coins = data.coins,
		income = s.income,
		plots = data.plots,
		plants = plants,
		yardCap = data.yardCap,
		yardCount = #data.yard,
		growth = data.growth,
		size = s.size,
		basket = data.basket,
		belly = data.belly,
		bellyCap = Rules.size(data.growth).belly,
		craving = s.craving or "",
		streak = s.streak,
		stock = stock,
		restockAt = Rules.nextRestockAt(now()),
		dex = data.dex,
		daily = {
			food = data.daily.food, fed = data.daily.fed, need = Config.Daily.Need,
			done = data.daily.done, resetAt = (data.daily.day + 1) * 86400,
		},
		friendBonus = s.friendBonus,
		stats = data.stats,
		pending = #data.pending,
	}
end

local function sendState(s)
	s.dirty = false
	s.lastSent = os.clock()
	local player = s.player
	player:SetAttribute("Coins", s.data.coins)
	player:SetAttribute("Income", s.income)
	remotes.State:FireClient(player, buildState(s))
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local coins = stats:FindFirstChild("Coins")
		if coins and coins:IsA("StringValue") then
			coins.Value = Rules.short(s.data.coins)
		end
		local size = stats:FindFirstChild("Thing")
		if size and size:IsA("IntValue") then
			size.Value = s.size
		end
	end
end

----------------------------------------------------------------------
-- Cravings
----------------------------------------------------------------------
local function pickCraving(s, avoid)
	local inBasket = {}
	for _, crop in ipairs(Config.Crops) do
		if basketCount(s.data, crop.id) > 0 then
			table.insert(inBasket, crop.id)
		end
	end
	-- something else in your basket; if you only have one kind, it keeps wanting that
	local options = {}
	for _, id in ipairs(inBasket) do
		if id ~= avoid then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		options = #inBasket > 0 and inBasket or plantedKinds(s.data)
	end
	if #options == 0 then
		s.craving = Config.Crops[1].id
		return
	end
	s.craving = options[s.rng:NextInteger(1, #options)]
end

----------------------------------------------------------------------
-- Hatching
----------------------------------------------------------------------
local function freeSlot(data)
	local used = {}
	for _, t in ipairs(data.yard) do
		used[t.slot or 0] = true
	end
	for slot = 1, #W.YardSlots do
		if not used[slot] then
			return slot
		end
	end
	return 1
end

local function weakestIndex(data)
	local best, bestIncome = nil, math.huge
	for i, t in ipairs(data.yard) do
		local income = Rules.fullIncome(t)
		if income < bestIncome then
			best, bestIncome = i, income
		end
	end
	return best
end

local function sendYardFull(s)
	local record = s.data.pending[1]
	if not record then
		return
	end
	local weakest = weakestIndex(s.data)
	notify(s.player, {
		type = "yardFull",
		kind = record.kind,
		mut = record.mut,
		sellNew = Rules.sellPrice(record),
		weakestId = weakest and s.data.yard[weakest].id or "",
		weakestKind = weakest and s.data.yard[weakest].kind or "",
		weakestMut = weakest and s.data.yard[weakest].mut or nil,
		sellWeakest = weakest and Rules.sellPrice(s.data.yard[weakest]) or 0,
	})
end

-- Eggs waiting for room move into the yard as soon as there is room
-- (after buying yard space, selling, or choosing). Asks again if any still wait.
local function drainPending(s)
	local data = s.data
	local moved = false
	while data.pending[1] and #data.yard < data.yardCap do
		local record = table.remove(data.pending, 1)
		record.slot = freeSlot(data)
		table.insert(data.yard, record)
		moved = true
	end
	if moved then
		publishYard(s)
		markDirty(s)
	end
	if data.pending[1] then
		sendYardFull(s)
	end
end

local function hatch(s, kind, mutation, source)
	local data = s.data
	local record = {
		id = "t" .. data.nextId,
		kind = kind,
		mut = mutation,
		born = now(),
		start = Rules.size(data.growth).hatchStart,
		slot = 0,
	}
	data.nextId += 1
	data.stats.hatches += 1

	local newKind = data.dex[kind] == nil
	data.dex[kind] = data.dex[kind] or {}
	local look = mutation or "Normal"
	local newLook = not data.dex[kind][look]
	data.dex[kind][look] = true

	local pending = false
	if #data.pending == 0 and #data.yard < data.yardCap then
		record.slot = freeSlot(data)
		table.insert(data.yard, record)
		publishYard(s)
	else
		table.insert(data.pending, record)
		pending = true
	end

	remotes.Hatched:FireClient(s.player, {
		kind = kind,
		mut = mutation,
		newKind = newKind,
		newLook = newLook,
		pending = pending,
		source = source,
	})
	if pending and #data.pending == 1 then
		sendYardFull(s)
	end

	local def = Config.Thinglets[kind]
	local rank = Rules.rarityRank(def.rarity)
	if rank >= 3 or mutation == "Gold" then
		local name = (mutation and (mutation .. " ") or "") .. def.name
		announce(s.player.DisplayName .. " hatched a " .. string.upper(def.rarity) .. " " .. name .. "!", Config.Rarities[def.rarity].color)
	end
	markDirty(s)
end

local function layEgg(s)
	local data = s.data
	local capacity = Rules.size(data.growth).belly
	local kind = Rules.resolveHatch(data.belly, capacity) or Config.ThingletOrder[1]
	local odds = Rules.mutationOdds(data.belly, s.size)
	local mutation = Rules.rollMutation(odds, s.rng:NextNumber())
	data.belly = {}
	hatch(s, kind, mutation, "belly")
end

local function checkSizeUp(s)
	local newSize = Rules.sizeIndex(s.data.growth)
	if newSize <= s.size then
		return false
	end
	s.size = newSize
	plotFolders[s.plot]:SetAttribute("ThingSize", newSize)
	publishSign(s)
	local size = Config.Thing.Sizes[newSize]
	notify(s.player, { type = "sizeUp", size = newSize, name = size.name, grew = size.grew or "" })
	if newSize == #Config.Thing.Sizes then
		announce(s.player.DisplayName .. "'s Thing grew to full size: " .. size.name .. "!", Config.Thing.EyeColor)
	end
	return true
end

----------------------------------------------------------------------
-- The toss
----------------------------------------------------------------------
local function onToss(player, cropId, releaseTime)
	local s = sessions[player]
	if not s or not s.ready then
		return
	end
	if typeof(cropId) ~= "string" or typeof(releaseTime) ~= "number" or releaseTime ~= releaseTime then
		return
	end
	local data = s.data
	local t = now()
	local function reject(reason)
		remotes.TossResult:FireClient(player, { ok = false, reason = reason, food = cropId })
	end

	-- a small token bucket rather than a hard gap, so tosses that arrive
	-- bunched up (a phone network catching up) still count
	s.tossTokens = math.min(3, (s.tossTokens or 3) + (t - (s.tokensAt or t)) / Config.Toss.MinInterval)
	s.tokensAt = t
	if s.tossTokens < 1 then
		reject("slow")
		return
	end
	s.tossTokens -= 1
	if #data.pending > 0 then
		sendYardFull(s)
		reject("Choose what to do with your new Thinglet first!")
		return
	end
	local root = character(player)
	if not root or flatDistance(root.Position, hatchPosition(s)) > Config.Toss.Range + 8 then
		reject("Get closer to your hatch!")
		return
	end
	local crop = Rules.crop(cropId)
	if not crop then
		reject("bad")
		return
	end
	local mutation = basketTake(data, cropId)
	if not mutation then
		reject("You don't have any " .. crop.name .. "!")
		return
	end

	-- PERFECT is judged by the ring at the moment you let go
	if releaseTime > t + 0.25 or releaseTime < t - Config.Toss.MaxClockSkew then
		releaseTime = t
	end
	local perfect = Rules.isPerfect(releaseTime)

	-- cravings and the combo
	if t - s.lastTossAt > Config.Toss.ComboTimeout then
		s.streak = 0
	end
	s.lastTossAt = t
	local cravingHit = cropId == s.craving
	if cravingHit then
		s.streak += 1
	else
		s.streak = 0
	end
	local coins = Rules.tossCoins(cropId, mutation, s.size, cravingHit, s.streak, s.friendBonus)
	data.coins += coins
	data.growth += crop.coins
	data.stats.tosses += 1
	if perfect then
		data.stats.perfects += 1
	end
	table.insert(data.belly, { f = cropId, m = mutation, p = perfect })

	local grew = checkSizeUp(s)
	remotes.TossResult:FireClient(player, {
		ok = true,
		food = cropId,
		mut = mutation,
		coins = coins,
		perfect = perfect,
		craving = cravingHit,
		streak = s.streak,
		combo = Rules.comboMult(cravingHit and s.streak or 0),
		grew = grew,
	})
	remotes.Fx:FireAllClients({ type = "chomp", plot = s.plot, perfect = perfect })

	if cravingHit or basketCount(data, s.craving or "") == 0 then
		pickCraving(s, s.craving)
	end

	-- the belly's full: lay an egg
	if #data.belly >= Rules.size(data.growth).belly then
		layEgg(s)
	end

	-- the daily craving
	local daily = data.daily
	if not daily.done and cropId == daily.food then
		daily.fed += 1
		if daily.fed >= Config.Daily.Need then
			daily.done = true
			local roll = s.rng:NextNumber()
			local mut = Rules.rollMutation(Config.Daily.Odds, roll) or "Frozen"
			hatch(s, crop.thinglet, mut, "daily")
		end
	end
	markDirty(s)
end

----------------------------------------------------------------------
-- Actions from the HUD (one RemoteFunction, answers { ok, msg })
----------------------------------------------------------------------
local actions = {}

function actions.buySeed(s, cropId, replace)
	local data = s.data
	local crop = typeof(cropId) == "string" and Rules.crop(cropId)
	if not crop then
		return { ok = false, msg = "Unknown seed." }
	end
	refreshShop(s)
	if stockLeft(s, crop.id) == 0 then
		return { ok = false, msg = "Sold out! New stock in " .. Rules.clock(Rules.nextRestockAt(now()) - now()) .. "." }
	end
	if data.coins < crop.seed then
		return { ok = false, msg = "Not enough coins yet." }
	end

	local spot
	if #data.plants < data.plots then
		spot = #data.plants + 1
	else
		-- every plot is full: replace the weakest plant, if it's weaker
		local weakest, weakestRank = nil, math.huge
		for i, plant in ipairs(data.plants) do
			local rank = Rules.cropRank(plant.crop)
			if rank < weakestRank then
				weakest, weakestRank = i, rank
			end
		end
		if not weakest or weakestRank >= Rules.cropRank(crop.id) then
			return { ok = false, msg = "Your garden is full of better plants. Buy more plots in Upgrades!" }
		end
		local old = data.plants[weakest]
		if replace ~= true then
			return { ok = false, needReplace = true, msg = "Replace your " .. Rules.crop(old.crop).name .. " plant? You get its seed price back." }
		end
		-- pick its fruit first, and refund the seed
		for _, mutation in ipairs(old.fruit) do
			basketAdd(data, old.crop, mutation)
		end
		data.coins += Rules.crop(old.crop).seed
		spot = weakest
	end

	data.coins -= crop.seed
	-- a delivery truck brings it: the plant starts growing when the package lands
	local t = now()
	local start = math.max(t, s.deliveryFreeAt or 0)
	s.deliveryFreeAt = start + Config.Delivery.Gap
	local times = Rules.deliveryTimes(s.plot)
	data.plants[spot] = { crop = crop.id, fruit = {}, timer = 0, arrive = start + times.total }
	data.shop.bought[crop.id] = (data.shop.bought[crop.id] or 0) + 1
	publishPlants(s)
	remotes.Fx:FireAllClients({ type = "delivery", plot = s.plot, spot = spot, crop = crop.id, start = start })
	if refreshDaily(s) then
		markDirty(s)
	end
	markDirty(s)
	return { ok = true, msg = "Your " .. crop.name .. " seeds are on their way!" }
end

function actions.buyPlot(s)
	local data = s.data
	if data.plots >= Config.Garden.MaxPlots then
		return { ok = false, msg = "Your garden is as big as it gets!" }
	end
	local price = Config.Garden.PlotPrices[data.plots + 1]
	if data.coins < price then
		return { ok = false, msg = "Not enough coins yet." }
	end
	data.coins -= price
	data.plots += 1
	plotFolders[s.plot]:SetAttribute("PlotsOwned", data.plots)
	WorldBuilder.setPlotsOwned(s.plot, data.plots)
	markDirty(s)
	return { ok = true, msg = "New garden plot!" }
end

function actions.buyYard(s)
	local data = s.data
	if data.yardCap >= Config.Yard.MaxCap then
		return { ok = false, msg = "Your yard is as big as it gets!" }
	end
	local price = Config.Yard.Prices[data.yardCap + 1]
	if data.coins < price then
		return { ok = false, msg = "Not enough coins yet." }
	end
	data.coins -= price
	data.yardCap += 1
	drainPending(s)
	markDirty(s)
	return { ok = true, msg = "More room in the yard!" }
end

function actions.sell(s, id)
	local data = s.data
	for i, t in ipairs(data.yard) do
		if t.id == id then
			local price = Rules.sellPrice(t)
			data.coins += price
			table.remove(data.yard, i)
			publishYard(s)
			drainPending(s)
			markDirty(s)
			return { ok = true, msg = "Sold for " .. Rules.short(price) .. " coins.", coins = price }
		end
	end
	return { ok = false, msg = "That Thinglet isn't in your yard." }
end

function actions.yardChoice(s, choice)
	local data = s.data
	local record = data.pending[1]
	if not record then
		return { ok = false, msg = "" }
	end
	local price = 0
	if choice == "swap" then
		local weakest = weakestIndex(data)
		if not weakest then
			return { ok = false, msg = "" }
		end
		local old = data.yard[weakest]
		price = Rules.sellPrice(old)
		record.slot = old.slot
		table.remove(data.yard, weakest)
		table.insert(data.yard, record)
		publishYard(s)
	elseif choice == "sellNew" then
		price = Rules.sellPrice(record)
	else
		return { ok = false, msg = "" }
	end
	data.coins += price
	table.remove(data.pending, 1)
	drainPending(s) -- the yard might have room again, or the next egg is waiting
	markDirty(s)
	return { ok = true, msg = "+" .. Rules.short(price) .. " coins", coins = price }
end

function actions.askYardFull(s)
	drainPending(s)
	return { ok = true, msg = "" }
end

local function onAction(player, name, a, b)
	local s = sessions[player]
	if not s or not s.ready then
		return { ok = false, msg = "Still loading..." }
	end
	if typeof(name) ~= "string" or not actions[name] then
		return { ok = false, msg = "" }
	end
	if os.clock() - (s.lastActionAt or 0) < 0.1 then
		return { ok = false, msg = "" }
	end
	s.lastActionAt = os.clock()
	local ok, result = pcall(actions[name], s, a, b)
	if not ok then
		warn("[GameService] action " .. name .. " failed: " .. tostring(result))
		return { ok = false, msg = "Something went wrong." }
	end
	if s.dirty then
		sendState(s)
	end
	return result
end

----------------------------------------------------------------------
-- The garden: growing and harvesting
----------------------------------------------------------------------
local function rollFruit(s)
	local weather = weatherNow()
	if weather and s.rng:NextNumber() < weather.chance then
		return weather.mutation
	end
	if s.rng:NextNumber() < Config.Weather.GoldChance then
		return "Gold"
	end
	return ""
end

local function growPlants(s, dt)
	local changed = false
	local t = now()
	for _, plant in ipairs(s.data.plants) do
		local crop = Rules.crop(plant.crop)
		if plant.arrive and plant.arrive > t then
			continue -- still on the delivery truck
		end
		if crop and #plant.fruit < Config.Garden.FruitCap then
			plant.timer += dt
			if plant.timer >= crop.regrow then
				plant.timer -= crop.regrow
				table.insert(plant.fruit, rollFruit(s))
				changed = true
			end
		elseif crop then
			plant.timer = 0
		end
	end
	if changed then
		publishPlants(s)
	end
end

-- While you were away: plants fill up (no weather, so nothing mutates)
local function growPlantsOffline(data, seconds)
	if seconds <= 0 then
		return
	end
	for _, plant in ipairs(data.plants) do
		local crop = Rules.crop(plant.crop)
		if crop then
			plant.timer += seconds
			while plant.timer >= crop.regrow and #plant.fruit < Config.Garden.FruitCap do
				plant.timer -= crop.regrow
				table.insert(plant.fruit, "")
			end
			if #plant.fruit >= Config.Garden.FruitCap then
				plant.timer = 0
			end
		end
	end
end

local function harvest(s)
	local root = character(s.player)
	if not root then
		return
	end
	local picked = {}
	for spot, plant in ipairs(s.data.plants) do
		if #plant.fruit > 0 and flatDistance(root.Position, spotPosition(s, spot)) <= Config.Garden.HarvestRange then
			local letters = {}
			for _, mutation in ipairs(plant.fruit) do
				basketAdd(s.data, plant.crop, mutation)
				table.insert(letters, MUT_LETTER[mutation] or "N")
			end
			plant.fruit = {}
			table.insert(picked, { spot = spot, crop = plant.crop, fruit = table.concat(letters) })
		end
	end
	if #picked > 0 then
		publishPlants(s)
		remotes.Harvested:FireClient(s.player, picked)
		if not s.craving or basketCount(s.data, s.craving) == 0 then
			pickCraving(s, nil)
		end
		markDirty(s)
	end
end

----------------------------------------------------------------------
-- Friends: +10% coins for every friend in the server
----------------------------------------------------------------------
local function areFriends(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. "_" .. high
	if friendCache[key] == nil then
		local ok, result = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		if not ok then
			return false -- a web hiccup: don't remember it, ask again next time
		end
		friendCache[key] = result == true
	end
	return friendCache[key]
end

local function updateFriendBonuses()
	for player, s in pairs(sessions) do
		local count = 0
		for other in pairs(sessions) do
			if other ~= player and other.Parent and areFriends(player, other) then
				count += 1
			end
		end
		local bonus = math.min(Config.Friends.Max, count * Config.Friends.PerFriend)
		if bonus ~= s.friendBonus then
			s.friendBonus = bonus
			markDirty(s)
		end
	end
end

----------------------------------------------------------------------
-- Joining and leaving
----------------------------------------------------------------------
local function placeCharacter(s, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait()
	local spawnCF = Rules.plotCFrame(s.plot) * CFrame.new(W.Spawn + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.pi, 0)
	char:PivotTo(spawnCF)
end

local function makeLeaderstats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = stats
	local size = Instance.new("IntValue")
	size.Name = "Thing"
	size.Value = 1
	size.Parent = stats
	stats.Parent = player
end

local function onPlayerAdded(player)
	local plot
	for i = 1, W.Plots do
		if not plotOwners[i] then
			plot = i
			break
		end
	end
	if not plot then
		player:Kick("This server is full - please join another one!")
		return
	end
	plotOwners[plot] = player

	local s = {
		player = player,
		plot = plot,
		ready = false,
		dirty = true,
		lastSent = 0,
		streak = 0,
		lastTossAt = 0,
		craving = nil,
		friendBonus = 0,
		income = 0,
		size = 1,
		stock = {},
		stockIndex = -1,
		rng = Random.new(),
	}
	sessions[player] = s
	plotFolders[plot]:SetAttribute("Owner", player.UserId)
	plotFolders[plot]:SetAttribute("OwnerName", player.DisplayName)

	player.CharacterAdded:Connect(function(char)
		placeCharacter(s, char)
	end)
	if player.Character then
		task.spawn(placeCharacter, s, player.Character)
	end
	makeLeaderstats(player)

	local data = DataService.load(player)
	if not player.Parent then
		DataService.forget(player) -- left while loading (onPlayerRemoving freed the plot)
		return
	end
	s.data = data

	-- the time away: plants fill up, Thinglets earn (up to an hour)
	local t = now()
	local away = data.lastOnline > 0 and (t - data.lastOnline) or 0
	growPlantsOffline(data, away)
	local offline = Rules.offlineCoins(data.yard, data.lastOnline, t)
	data.coins += offline
	data.lastOnline = t

	s.size = Rules.sizeIndex(data.growth)
	refreshShop(s)
	refreshDaily(s)
	pickCraving(s, nil)
	s.income = yardIncome(s)
	publishPlot(s)
	s.ready = true
	updateFriendBonuses()
	sendState(s)

	if offline > 0 and away >= Config.Offline.ShowAfter then
		notify(player, { type = "welcome", coins = offline, away = away })
	end
	drainPending(s)
end

local function onPlayerRemoving(player)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	if plotOwners[s.plot] == player then
		plotOwners[s.plot] = nil
		clearPlot(s.plot)
	end
	if s.data then
		DataService.release(player)
	end
	updateFriendBonuses()
end

----------------------------------------------------------------------
-- The game loop
----------------------------------------------------------------------
local function tickWeather()
	local weather, changeAt = Rules.weatherAt(now())
	local id = weather and weather.id or ""
	if id ~= currentWeather then
		currentWeather = id
		ReplicatedStorage:SetAttribute("Weather", id)
		ReplicatedStorage:SetAttribute("WeatherChangeAt", changeAt)
		if weather then
			remotes.Notify:FireAllClients({ type = "weather", id = id, text = weather.banner })
		end
	else
		ReplicatedStorage:SetAttribute("WeatherChangeAt", changeAt)
	end
end

-- Studio-only test helpers: from the Command Bar while playing,
--   game.Players.YourName:SetAttribute("GiveCoins", 1e6)
--   game.Players.YourName:SetAttribute("GiveGrowth", 50000)   (feeds the Thing)
local function studioHelpers(s)
	local player = s.player
	local coins = player:GetAttribute("GiveCoins")
	if type(coins) == "number" then
		player:SetAttribute("GiveCoins", nil)
		s.data.coins += coins
	end
	local growth = player:GetAttribute("GiveGrowth")
	if type(growth) == "number" then
		player:SetAttribute("GiveGrowth", nil)
		s.data.growth += growth
		checkSizeUp(s)
	end
end

local function tickSecond(dt)
	tickWeather()
	local studio = RunService:IsStudio()
	for _, s in pairs(sessions) do
		if s.ready and studio then
			studioHelpers(s)
		end
		if s.ready then
			growPlants(s, dt)
			s.income = yardIncome(s)
			s.data.coins += s.income * dt
			if refreshShop(s) then
				markDirty(s)
			end
			if refreshDaily(s) then
				markDirty(s)
			end
			markDirty(s) -- coins changed
		end
	end
end

function GameService.start(dataService, worldBuilder)
	DataService = dataService
	WorldBuilder = worldBuilder
	assert(DataService and WorldBuilder, "GameService needs DataService and WorldBuilder (see the lines above)")

	-- one folder of attributes per plot, for every client to draw from
	local plotsFolder = ReplicatedStorage:FindFirstChild("Plots")
	if not plotsFolder then
		plotsFolder = Instance.new("Folder")
		plotsFolder.Name = "Plots"
		plotsFolder.Parent = ReplicatedStorage
	end
	for i = 1, W.Plots do
		local folder = plotsFolder:FindFirstChild("Plot" .. i) or Instance.new("Folder")
		folder.Name = "Plot" .. i
		folder:SetAttribute("Index", i)
		folder.Parent = plotsFolder
		plotFolders[i] = folder
		clearPlot(i)
	end
	ReplicatedStorage:SetAttribute("Weather", "")

	remotes.Toss.OnServerEvent:Connect(onToss)
	remotes.Action.OnServerInvoke = onAction

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	local secondTimer, harvestTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		secondTimer += dt
		harvestTimer += dt
		if harvestTimer >= 0.2 then
			harvestTimer = 0
			for _, s in pairs(sessions) do
				if s.ready then
					harvest(s)
				end
			end
		end
		if secondTimer >= 1 then
			local step = secondTimer
			secondTimer = 0
			tickSecond(step)
		end
		-- send private state when something changed (at most 4 times a second)
		for _, s in pairs(sessions) do
			if s.ready and s.dirty and os.clock() - s.lastSent >= 0.25 then
				sendState(s)
			end
		end
	end)
end

return GameService
