--[[
	GameService  (ModuleScript, parent: ServerScriptService, name: "GameService")

	The server's side of the whole game:

	  buy a food -> feed it to the Thing -> it burps out an egg onto a nest
	  -> the egg hatches by itself after a short countdown -> the Thinglet
	  earns coins in your yard -> buy better food -> again

	It checks every feed, rolls what each egg will hatch into (the food's
	odds, your luck, the weather), hatches the eggs when they're ready, keeps
	your best Thinglets in the yard (a better one takes the weakest one's
	place, the other is sold), and runs the upgrades, the weather, the coin
	truck, offline coins and the friend bonus.

	The server decides everything; the clients only draw it. What a client
	needs to draw lives in two places:
	  * ReplicatedStorage.Plots.PlotN attributes - public (everyone sees
	    your Thing's size, your eggs and your Thinglets)
	  * the "State" remote - private (your coins, upgrades, dex...)
	What an egg will hatch into stays on the server until it hatches.
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
	Feed = remoteFolder:WaitForChild("Feed") :: RemoteEvent,
	FeedResult = remoteFolder:WaitForChild("FeedResult") :: RemoteEvent,
	State = remoteFolder:WaitForChild("State") :: RemoteEvent,
	Notify = remoteFolder:WaitForChild("Notify") :: RemoteEvent,
	Hatched = remoteFolder:WaitForChild("Hatched") :: RemoteEvent,
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
local serverRng = Random.new()

local function now()
	return workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
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

local function nestCount(data)
	return math.min(Rules.upgradeEffect(data, "nests"), #Config.Eggs.NestSpots)
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
-- the eggs on the nests: which food, when it was laid and when it hatches
-- (not what's inside: that's a surprise)
local function publishEggs(s)
	local list = {}
	for _, egg in ipairs(s.data.eggs) do
		table.insert(list, { id = egg.id, n = egg.nest, f = egg.food, l = egg.laid, r = egg.ready })
	end
	plotFolders[s.plot]:SetAttribute("Eggs", HttpService:JSONEncode(list))
end

local function publishYard(s)
	local list = {}
	for _, t in ipairs(s.data.yard) do
		table.insert(list, { id = t.id, k = t.kind, m = t.mut, b = t.born, s = t.start, slot = t.slot, n = t.nest })
	end
	plotFolders[s.plot]:SetAttribute("Yard", HttpService:JSONEncode(list))
end

local function publishSign(s)
	local size = Config.Thing.Sizes[s.size]
	WorldBuilder.setSign(s.plot, s.player.DisplayName .. "'s Basement", "Size " .. s.size .. ": " .. size.name, s.player.UserId)
end

-- what each Thinglet's income is multiplied by (the name tags show it)
local function publishIncomeMult(s)
	plotFolders[s.plot]:SetAttribute("IncomeMult", Rules.upgradeEffect(s.data, "income") * (1 + s.friendBonus))
end

local function publishPlot(s)
	local folder = plotFolders[s.plot]
	folder:SetAttribute("Owner", s.player.UserId)
	folder:SetAttribute("OwnerName", s.player.DisplayName)
	folder:SetAttribute("ThingSize", s.size)
	folder:SetAttribute("Nests", nestCount(s.data))
	publishSign(s)
	publishEggs(s)
	publishYard(s)
	publishIncomeMult(s)
end

local function clearPlot(i)
	local folder = plotFolders[i]
	folder:SetAttribute("Owner", 0)
	folder:SetAttribute("OwnerName", "")
	folder:SetAttribute("ThingSize", 1)
	folder:SetAttribute("Nests", 0)
	folder:SetAttribute("IncomeMult", 1)
	folder:SetAttribute("Eggs", "[]")
	folder:SetAttribute("Yard", "[]")
	WorldBuilder.setSign(i, "Free plot", "", 0)
end

----------------------------------------------------------------------
-- The private state each player's client draws its HUD from
----------------------------------------------------------------------
local function yardIncome(s)
	local t = now()
	local total = 0
	for _, record in ipairs(s.data.yard) do
		total += Rules.income(record, t)
	end
	return total * (1 + s.friendBonus) * Rules.upgradeEffect(s.data, "income")
end

local function buildState(s)
	local data = s.data
	return {
		coins = data.coins,
		income = s.income,
		yardCap = data.yardCap,
		yardCount = #data.yard,
		upgrades = data.upgrades,
		growth = data.growth,
		size = s.size,
		luck = Rules.luck(data, s.size),
		nests = nestCount(data),
		eggs = #data.eggs,
		dex = data.dex,
		friendBonus = s.friendBonus,
		stats = data.stats,
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
-- The Thing grows as it eats
----------------------------------------------------------------------
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
-- Feeding: pay for the food, the Thing eats it and burps out an egg
----------------------------------------------------------------------
local function onFeed(player, foodId)
	local s = sessions[player]
	if not s or not s.ready then
		return
	end
	if typeof(foodId) ~= "string" then
		return
	end
	local data = s.data
	local t = now()
	local function reject(reason, code)
		remotes.FeedResult:FireClient(player, { ok = false, reason = reason, code = code, food = foodId })
	end

	-- a small token bucket rather than a hard gap, so feeds that arrive
	-- bunched up (a phone network catching up) still count
	s.feedTokens = math.min(3, (s.feedTokens or 3) + (t - (s.tokensAt or t)) / Config.Feed.MinInterval)
	s.tokensAt = t
	if s.feedTokens < 1 then
		reject("", "slow")
		return
	end
	s.feedTokens -= 1
	local crop = Rules.crop(foodId)
	if not crop then
		reject("", "bad")
		return
	end
	local root = character(player)
	if not root or flatDistance(root.Position, hatchPosition(s)) > Config.Feed.Range + 8 then
		reject("Get closer to your hatch!", "far")
		return
	end
	local nest = Rules.freeNest(data.eggs, nestCount(data))
	if not nest then
		reject("Your nests are full! Wait for an egg to hatch.", "nests")
		return
	end
	if data.coins < crop.price then
		reject("Not enough coins for a " .. crop.name .. "!", "coins")
		return
	end

	data.coins -= crop.price
	data.growth += crop.growth
	data.stats.feeds += 1
	local grew = checkSizeUp(s)

	-- what it will hatch into is decided now (luck and weather at feeding time)
	local rng = s.rng
	local luck = Rules.luck(data, s.size)
	local kind, mutation = Rules.rollHatch(crop.id, luck, currentWeather, rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber())
	local first = data.stats.feeds == 1
	local egg = {
		id = "e" .. data.nextId,
		nest = nest,
		food = crop.id,
		kind = kind,
		mut = mutation,
		laid = t,
		ready = t + Rules.eggSeconds(crop.id, Rules.upgradeEffect(data, "speed"), first),
	}
	data.nextId += 1
	table.insert(data.eggs, egg)
	publishEggs(s)
	remotes.FeedResult:FireClient(player, { ok = true, food = crop.id, nest = nest, ready = egg.ready, grew = grew })
	markDirty(s)
end

----------------------------------------------------------------------
-- Hatching: eggs hatch by themselves when their countdown ends
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

local function hatch(s, egg)
	local data = s.data
	local kind = Config.Thinglets[egg.kind] and egg.kind or Config.ThingletOrder[1]
	local mutation = (type(egg.mut) == "string" and Rules.mutation(egg.mut)) and egg.mut or nil
	local record = {
		id = "t" .. data.nextId,
		kind = kind,
		mut = mutation,
		born = now(),
		start = Rules.size(data.growth).hatchStart,
		slot = 0,
		nest = egg.nest, -- where it hopped out from
	}
	data.nextId += 1
	data.stats.hatches += 1

	local newKind = data.dex[kind] == nil
	data.dex[kind] = data.dex[kind] or {}
	local look = mutation or "Normal"
	local newLook = not data.dex[kind][look]
	data.dex[kind][look] = true

	-- into the yard; when it's full, a better one takes the weakest one's
	-- place and the weaker one is sold (no choices to make)
	local how, index = Rules.yardPlace(data.yard, data.yardCap, record)
	local sold, soldKind, soldMut = 0, nil, nil
	if how == "add" then
		record.slot = freeSlot(data)
		table.insert(data.yard, record)
	elseif how == "replace" then
		local old = data.yard[index]
		sold, soldKind, soldMut = Rules.sellPrice(old), old.kind, old.mut
		record.slot = old.slot
		data.yard[index] = record
	else
		sold, soldKind, soldMut = Rules.sellPrice(record), kind, mutation
	end
	data.coins += sold

	remotes.Hatched:FireClient(s.player, {
		kind = kind,
		mut = mutation,
		newKind = newKind,
		newLook = newLook,
		how = how, -- "add", "replace" or "sell"
		sold = sold,
		soldKind = soldKind,
		soldMut = soldMut,
		nest = egg.nest,
		food = egg.food,
	})

	local def = Config.Thinglets[kind]
	if Rules.rarityRank(def.rarity) >= 4 or mutation == "Gold" then
		local name = (mutation and (mutation .. " ") or "") .. def.name
		announce(s.player.DisplayName .. " hatched a " .. string.upper(def.rarity) .. " " .. name .. "!", Config.Rarities[def.rarity].color)
	end
end

local function hatchReady(s)
	local t = now()
	if t < (s.hatchAfter or 0) then
		return
	end
	local ready, waiting = {}, {}
	for _, egg in ipairs(s.data.eggs) do
		table.insert(egg.ready <= t and ready or waiting, egg)
	end
	if #ready == 0 then
		return
	end
	table.sort(ready, function(a, b)
		return a.ready < b.ready
	end)
	s.data.eggs = waiting
	publishEggs(s)
	for _, egg in ipairs(ready) do
		hatch(s, egg)
	end
	publishYard(s)
	s.income = yardIncome(s)
	markDirty(s)
end

----------------------------------------------------------------------
-- Actions from the HUD (one RemoteFunction, answers { ok, msg })
----------------------------------------------------------------------
local actions = {}

-- Buy up to `want` levels of an upgrade (as many as you can afford)
function actions.upgrade(s, id, want)
	local def = typeof(id) == "string" and Rules.upgradeDef(id)
	if not def then
		return { ok = false, msg = "That's not an upgrade." }
	end
	if typeof(want) ~= "number" or want ~= want then
		want = 1
	end
	want = math.clamp(math.floor(want), 1, 1000)
	local data = s.data
	local level = Rules.upgradeLevel(data, id)
	if level >= Rules.upgradeMax(id) then
		return { ok = false, msg = def.name .. " is maxed out!" }
	end
	local n, cost = Rules.upgradeBuy(id, level, data.coins, want)
	if n == 0 then
		return { ok = false, msg = "Not enough coins yet." }
	end
	data.coins -= cost
	if id == "yard" then
		data.yardCap += n
	else
		data.upgrades[id] = level + n
	end
	if id == "nests" then
		plotFolders[s.plot]:SetAttribute("Nests", nestCount(data))
	elseif id == "income" then
		s.income = yardIncome(s)
		publishIncomeMult(s)
	end
	markDirty(s)
	local msg = def.name .. (n > 1 and (" +" .. n .. " levels!") or " level up!")
	return { ok = true, msg = msg, id = id, level = level + n, n = n }
end

function actions.sell(s, id)
	local data = s.data
	for i, t in ipairs(data.yard) do
		if t.id == id then
			local price = Rules.sellPrice(t)
			data.coins += price
			table.remove(data.yard, i)
			publishYard(s)
			s.income = yardIncome(s)
			markDirty(s)
			return { ok = true, msg = "Sold for " .. Rules.short(price) .. " coins.", coins = price }
		end
	end
	return { ok = false, msg = "That Thinglet isn't in your yard." }
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
-- The coin truck: every so often it brings someone a package of coins
----------------------------------------------------------------------
local function sendTruck()
	local list = {}
	for _, s in pairs(sessions) do
		if s.ready then
			table.insert(list, s)
		end
	end
	if #list == 0 then
		return
	end
	local s = list[serverRng:NextInteger(1, #list)]
	local start = now() + 0.5
	local times = Rules.deliveryTimes(s.plot)
	remotes.Fx:FireAllClients({ type = "delivery", plot = s.plot, start = start })
	notify(s.player, { type = "truckComing" })
	task.delay(start - now() + times.total, function()
		if sessions[s.player] ~= s or not s.ready then
			return
		end
		local coins = math.max(Config.Delivery.MinTip, math.floor(s.income * Config.Delivery.TipSeconds))
		s.data.coins += coins
		notify(s.player, { type = "tip", coins = coins })
		markDirty(s)
	end)
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
			if s.ready then
				publishIncomeMult(s)
			end
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

-- An older or hand-edited save could hold eggs that make no sense: keep the
-- good ones, one per nest
local function tidyEggs(data)
	local kept, used = {}, {}
	for _, egg in ipairs(data.eggs) do
		if type(egg) == "table" and Rules.crop(egg.food) and Config.Thinglets[egg.kind]
			and type(egg.nest) == "number" and not used[egg.nest] and Config.Eggs.NestSpots[egg.nest]
			and type(egg.ready) == "number" then
			used[egg.nest] = true
			table.insert(kept, egg)
		end
	end
	data.eggs = kept
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
		friendBonus = 0,
		income = 0,
		size = 1,
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
	tidyEggs(data)

	-- the time away: Thinglets earned (up to Offline.MaxSeconds), and eggs
	-- that finished meanwhile hatch a moment after you arrive
	local t = now()
	local away = data.lastOnline > 0 and (t - data.lastOnline) or 0
	local offline = Rules.offlineCoins(data.yard, data.lastOnline, t, Config.Offline.MaxSeconds, Rules.upgradeEffect(data, "income"))
	data.coins += offline
	data.lastOnline = t
	local readyEggs = 0
	for _, egg in ipairs(data.eggs) do
		if egg.ready <= t then
			readyEggs += 1
		end
	end
	s.hatchAfter = t + 3

	s.size = Rules.sizeIndex(data.growth)
	s.income = yardIncome(s)
	publishPlot(s)
	s.ready = true
	updateFriendBonuses()
	sendState(s)

	if offline > 0 and away >= Config.Offline.ShowAfter then
		notify(player, { type = "welcome", coins = offline, away = away, eggs = readyEggs })
	end
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
--   game.Players.YourName:SetAttribute("HatchNow", true)      (every egg hatches now)
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
	if player:GetAttribute("HatchNow") then
		player:SetAttribute("HatchNow", nil)
		for _, egg in ipairs(s.data.eggs) do
			egg.ready = now()
		end
		publishEggs(s)
	end
end

local truckTimer = 60 -- the first truck comes a minute after the server starts
local function tickSecond(dt)
	tickWeather()
	local studio = RunService:IsStudio()
	for _, s in pairs(sessions) do
		if s.ready then
			if studio then
				studioHelpers(s)
			end
			s.income = yardIncome(s)
			s.data.coins += s.income * dt
			markDirty(s) -- coins changed
		end
	end
	truckTimer -= dt
	if truckTimer <= 0 then
		truckTimer = Config.Delivery.Every
		sendTruck()
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

	remotes.Feed.OnServerEvent:Connect(onFeed)
	remotes.Action.OnServerInvoke = onAction

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	local secondTimer, hatchTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		secondTimer += dt
		hatchTimer += dt
		if hatchTimer >= 0.2 then
			hatchTimer = 0
			for _, s in pairs(sessions) do
				if s.ready then
					hatchReady(s)
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
