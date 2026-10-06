--[[
	Rules  (ModuleScript, parent: ReplicatedStorage, name: "Rules")

	The game's rules as plain functions: what hatches, the mutation odds,
	coins per toss, how grown a Thinglet is, what it has earned, the shop's
	stock and the weather. The server decides with these and the HUD shows
	the same answers, so they can never disagree.

	Nothing in here touches Roblox objects (except plotCFrame at the bottom),
	so the rules can be tested outside Studio: see Tests/RulesTest.luau.
]]

local Rules = {}

local Config
local cropById, cropRank, mutationById, upgradeById

local function index()
	cropById, cropRank, mutationById, upgradeById = {}, {}, {}, {}
	for _, upgrade in ipairs(Config.Upgrades or {}) do
		upgradeById[upgrade.id] = upgrade
	end
	for i, crop in ipairs(Config.Crops) do
		cropById[crop.id] = crop
		cropRank[crop.id] = i
	end
	for _, mutation in ipairs(Config.Mutations) do
		mutationById[mutation.id] = mutation
	end
end

-- (the tests call this with their own copy of Config)
function Rules.useConfig(config)
	Config = config
	index()
end

if script then
	Rules.useConfig(require(script.Parent:WaitForChild("Config")))
end

----------------------------------------------------------------------
-- Lookups
----------------------------------------------------------------------
function Rules.crop(id)
	return cropById[id]
end

-- 1 for the cheapest crop, up to #Config.Crops for the rarest; 0 if unknown
function Rules.cropRank(id)
	return cropRank[id] or 0
end

function Rules.mutation(id)
	return mutationById[id]
end

function Rules.mutationMult(id)
	local mutation = id and mutationById[id]
	return mutation and mutation.mult or 1
end

function Rules.thinglet(kind)
	return Config.Thinglets[kind]
end

function Rules.rarityRank(rarity)
	local info = Config.Rarities[rarity]
	return info and info.rank or 0
end

----------------------------------------------------------------------
-- The Thing's size
----------------------------------------------------------------------
function Rules.sizeIndex(growth)
	local found = 1
	for i, size in ipairs(Config.Thing.Sizes) do
		if growth >= size.growth then
			found = i
		end
	end
	return found
end

function Rules.size(growth)
	return Config.Thing.Sizes[Rules.sizeIndex(growth)]
end

----------------------------------------------------------------------
-- What hatches. `belly` is a list of { f = food id, m = mutation id or "",
-- p = was it a PERFECT toss }. `capacity` is how many slots the belly has.
--   1. a full belly of the secret food, every toss PERFECT -> the secret one
--   2. MishmashKinds or more different foods                -> Mishmash
--   3. otherwise the food fed most wins; on a tie the rarer food wins
----------------------------------------------------------------------
function Rules.resolveHatch(belly, capacity)
	if #belly == 0 then
		return nil
	end
	if #belly >= capacity then
		local secret = true
		for _, item in ipairs(belly) do
			if item.f ~= Config.SecretFood or not item.p then
				secret = false
				break
			end
		end
		if secret then
			return Config.SecretThinglet
		end
	end

	local counts, kinds = {}, 0
	for _, item in ipairs(belly) do
		if not counts[item.f] then
			counts[item.f] = 0
			kinds += 1
		end
		counts[item.f] += 1
	end
	if kinds >= Config.MishmashKinds then
		return Config.MishmashThinglet
	end

	local best, bestCount = nil, 0
	for food, count in pairs(counts) do
		if count > bestCount or (count == bestCount and Rules.cropRank(food) > Rules.cropRank(best)) then
			best, bestCount = food, count
		end
	end
	local crop = best and cropById[best]
	return crop and crop.thinglet or nil
end

----------------------------------------------------------------------
-- Mutation odds for an egg from this belly. Returns { Frozen = 0.05, ... ,
-- None = 0.91 }. If the chances add up past 100% they're scaled down to fit.
----------------------------------------------------------------------
function Rules.mutationOdds(belly, sizeIndex)
	local odds, total = {}, 0
	for _, mutation in ipairs(Config.Mutations) do
		local chance = mutation.base + Config.SizeLuckBonus * ((sizeIndex or 1) - 1)
		for _, item in ipairs(belly) do
			if item.m == mutation.id then
				chance += Config.MutatedFoodBonus
			end
			if item.p then
				chance += Config.PerfectBonus
			end
		end
		odds[mutation.id] = chance
		total += chance
	end
	if total > 1 then
		for id, chance in pairs(odds) do
			odds[id] = chance / total
		end
		total = 1
	end
	odds.None = math.max(0, 1 - total)
	return odds
end

-- roll = a random number from 0 up to (not including) 1
function Rules.rollMutation(odds, roll)
	local acc = 0
	for _, mutation in ipairs(Config.Mutations) do
		acc += odds[mutation.id] or 0
		if roll < acc then
			return mutation.id
		end
	end
	return nil
end

----------------------------------------------------------------------
-- The toss
----------------------------------------------------------------------
-- Where the ring is at time `t`: 0 = start of a cycle, 0.5 = smallest
function Rules.ringPhase(t)
	local cycle = Config.Toss.RingCycle
	return (t % cycle) / cycle
end

-- window = share of the cycle that counts (the Sweet spot upgrade widens it)
function Rules.isPerfect(t, window)
	return math.abs(Rules.ringPhase(t) - 0.5) <= (window or Config.Toss.PerfectWindow) / 2
end

-- How big the ring is at time t: 0 = smallest, 1 = biggest
function Rules.ringOpen(t)
	return math.abs(math.cos(math.pi * Rules.ringPhase(t)))
end

-- streak = craving hits in a row, counting this one (0 if it wasn't one)
function Rules.comboMult(streak)
	if streak <= 0 then
		return 1
	end
	local combo = Config.Toss.Combo
	return combo[math.min(streak, #combo)]
end

-- bonus = extra share from friends (0.1 = +10%); mult = the Tasty tosses upgrade
function Rules.tossCoins(foodId, mutationId, sizeIndex, cravingHit, streak, bonus, mult)
	local crop = cropById[foodId]
	if not crop then
		return 0
	end
	local value = crop.coins
		* Rules.mutationMult(mutationId)
		* Config.Thing.Sizes[sizeIndex or 1].coinMult
		* (cravingHit and Config.Toss.CravingMult or 1)
		* Rules.comboMult(cravingHit and streak or 0)
		* (1 + (bonus or 0))
		* (mult or 1)
	return math.floor(value + 0.5)
end

----------------------------------------------------------------------
-- Thinglets. A record is { kind = "Blorp", mut = "Gold" or nil,
-- born = time it hatched, start = how grown it hatched (0.25..0.6) }.
----------------------------------------------------------------------
function Rules.fullIncome(record)
	local def = Config.Thinglets[record.kind]
	if not def then
		return 0
	end
	return def.cps * Rules.mutationMult(record.mut)
end

-- 0.25 .. 1: how grown it is (the share of its full size and income)
function Rules.progress(record, now)
	local def = Config.Thinglets[record.kind]
	local start = record.start or 0.25
	if not def then
		return start
	end
	local age = math.max(0, now - (record.born or now))
	return start + (1 - start) * math.min(1, age / def.grow)
end

function Rules.income(record, now)
	return Rules.fullIncome(record) * Rules.progress(record, now)
end

function Rules.isGrown(record, now)
	return Rules.progress(record, now) >= 1
end

-- studs tall right now
function Rules.height(record, now)
	local def = Config.Thinglets[record.kind]
	if not def then
		return Config.HatchlingHeight
	end
	local k = math.clamp((Rules.progress(record, now) - 0.25) / 0.75, 0, 1)
	return Config.HatchlingHeight + (def.height - Config.HatchlingHeight) * k
end

-- Coins this Thinglet earns between times a and b (it keeps growing meanwhile)
function Rules.earned(record, a, b)
	if b <= a then
		return 0
	end
	local def = Config.Thinglets[record.kind]
	if not def then
		return 0
	end
	local full = Rules.fullIncome(record)
	local start = record.start or 0.25
	local born = record.born or a
	local doneAt = born + def.grow
	local total = 0

	local ra, rb = math.max(a, born), math.min(b, doneAt)
	if rb > ra then
		local qa = start + (1 - start) * (ra - born) / def.grow
		local qb = start + (1 - start) * (rb - born) / def.grow
		total += full * (qa + qb) / 2 * (rb - ra)
	end
	local fa = math.max(a, doneAt)
	if b > fa then
		total += full * (b - fa)
	end
	return total
end

-- What the whole yard earned while you were away (capped at Offline.MaxSeconds,
-- or maxSeconds with the Long nap upgrade; mult = the Comfy yard upgrade)
function Rules.offlineCoins(yard, leftAt, now, maxSeconds, mult)
	if not leftAt or leftAt <= 0 or now <= leftAt then
		return 0
	end
	local stop = leftAt + math.min(now - leftAt, maxSeconds or Config.Offline.MaxSeconds)
	local total = 0
	for _, record in ipairs(yard) do
		total += Rules.earned(record, leftAt, stop)
	end
	return math.floor(total * (mult or 1))
end

function Rules.sellPrice(record)
	return math.floor(Rules.fullIncome(record) * Config.Yard.SellSeconds)
end

----------------------------------------------------------------------
-- A small random number generator that gives the same numbers for the
-- same seed on the server and every client (MINSTD).
----------------------------------------------------------------------
function Rules.random(seed)
	local state = math.floor(seed) % 2147483646 + 1
	local function nextNumber()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	nextNumber()
	nextNumber()
	return nextNumber
end

----------------------------------------------------------------------
-- Seed shop
----------------------------------------------------------------------
function Rules.restockIndex(now)
	return math.floor(now / Config.Shop.RestockEvery)
end

function Rules.nextRestockAt(now)
	return (Rules.restockIndex(now) + 1) * Config.Shop.RestockEvery
end

-- What this player's shop holds this restock: { Tomato = -1 (always), Eyeberry = 2, ... }
function Rules.stockFor(userId, restockIndex)
	local rand = Rules.random((userId % 1000003) * 7919 + restockIndex * 104729)
	local stock = {}
	for _, crop in ipairs(Config.Crops) do
		if crop.stockChance >= 1 then
			stock[crop.id] = -1
		elseif rand() < crop.stockChance then
			stock[crop.id] = crop.stockMin + math.floor(rand() * (crop.stockMax - crop.stockMin + 1))
		else
			stock[crop.id] = 0
		end
	end
	if restockIndex % Config.Shop.MoonGuaranteeEvery == 0 then
		stock[Config.SecretFood] = math.max(stock[Config.SecretFood] or 0, 1)
	end
	return stock
end

----------------------------------------------------------------------
-- Weather: the same for everyone, worked out from the clock.
-- Returns the weather type (or nil) and the time it next changes.
----------------------------------------------------------------------
function Rules.weatherAt(now)
	local w = Config.Weather
	local cycle = math.floor(now / w.Every)
	local cycleStart = cycle * w.Every
	local startsAt = cycleStart + w.Every - w.Duration
	if now >= startsAt then
		local rand = Rules.random(cycle * 31337 + 7)
		return w.Types[1 + math.floor(rand() * #w.Types)], cycleStart + w.Every
	end
	return nil, startsAt
end

----------------------------------------------------------------------
-- Daily craving: one of the foods you grow, picked fresh each UTC day
----------------------------------------------------------------------
function Rules.dayIndex(now)
	return math.floor(now / 86400)
end

-- grown = list of crop ids the player has planted (any order)
function Rules.dailyFood(userId, day, grown)
	if #grown == 0 then
		return Config.Crops[1].id
	end
	local sorted = table.clone(grown)
	table.sort(sorted, function(a, b)
		return Rules.cropRank(a) < Rules.cropRank(b)
	end)
	local rand = Rules.random((userId % 1000003) * 31 + day * 7477)
	return sorted[1 + math.floor(rand() * #sorted)]
end

----------------------------------------------------------------------
-- Friendly numbers: 999, 1.2K, 34.5M, 1.2B
----------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }
function Rules.short(n)
	n = math.floor(n or 0)
	if n < 1000 then
		return tostring(n)
	end
	local tier = 1
	local value = n
	while value >= 1000 and tier < #SUFFIXES do
		value /= 1000
		tier += 1
	end
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	elseif value >= 10 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = string.format("%.2f", math.floor(value * 100) / 100)
	end
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "") -- 1.50 -> 1.5
		text = string.gsub(text, "%.$", "") -- 2. -> 2
	end
	return text .. SUFFIXES[tier]
end

-- Coins per second: one decimal while it's small (0.3), short after (1.2K)
function Rules.rate(n)
	n = n or 0
	if n < 10 then
		local text = string.format("%.1f", math.floor(n * 10) / 10)
		return (string.gsub(text, "%.0$", ""))
	end
	return Rules.short(n)
end

-- "2:05"
function Rules.clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

----------------------------------------------------------------------
-- Upgrades (Config.Upgrades). `data` is a save (or the HUD's copy of it):
-- plots, yardCap and upgrades = { [id] = level }.
----------------------------------------------------------------------
function Rules.upgradeDef(id)
	return upgradeById[id]
end

function Rules.upgradeLevel(data, id)
	if id == "plots" then
		return (data.plots or Config.Garden.StartPlots) - Config.Garden.StartPlots
	elseif id == "yard" then
		return (data.yardCap or Config.Yard.StartCap) - Config.Yard.StartCap
	end
	return data.upgrades and data.upgrades[id] or 0
end

function Rules.upgradeMax(id)
	if id == "plots" then
		return Config.Garden.MaxPlots - Config.Garden.StartPlots
	elseif id == "yard" then
		return Config.Yard.MaxCap - Config.Yard.StartCap
	end
	local def = upgradeById[id]
	return def and def.max or 0
end

-- prices look tidy: 2 significant digits (1234 -> 1200)
local function tidy(x)
	if x < 100 then
		return math.floor(x + 0.5)
	end
	local step = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

-- What the level after `level` costs (nil when it's maxed)
function Rules.upgradeCost(id, level)
	if level >= Rules.upgradeMax(id) then
		return nil
	end
	if id == "plots" then
		return Config.Garden.PlotPrices[Config.Garden.StartPlots + level + 1]
	elseif id == "yard" then
		return Config.Yard.Prices[Config.Yard.StartCap + level + 1]
	end
	local def = upgradeById[id]
	return tidy(def.base * def.growth ^ level)
end

-- Buying up to `want` levels with `coins`: how many you get and what they
-- cost. You always get as many as you can afford (0 if not even one).
function Rules.upgradeBuy(id, level, coins, want)
	local n, total = 0, 0
	while n < want do
		local cost = Rules.upgradeCost(id, level + n)
		if not cost or total + cost > coins then
			break
		end
		total += cost
		n += 1
	end
	return n, total
end

-- The number an upgrade gives at `level`
function Rules.upgradeValue(id, level)
	local def = upgradeById[id]
	if id == "plots" then
		return Config.Garden.StartPlots + level
	elseif id == "yard" then
		return Config.Yard.StartCap + level
	elseif id == "reach" then
		return Config.Garden.HarvestRange + def.per * level -- studs
	elseif id == "perfect" then
		return Config.Toss.PerfectWindow + def.per * level -- share of the ring cycle
	elseif id == "bumper" then
		return def.per * level -- chance each picked fruit is doubled
	elseif id == "nap" then
		return Config.Offline.MaxSeconds + def.per * level -- seconds
	end
	return 1 + (def and def.per or 0) * level -- toss, growth, income, luck: multipliers
end

-- The same, in words for the menu
function Rules.upgradeText(id, level)
	local value = Rules.upgradeValue(id, level)
	if id == "plots" then
		return value .. " plots"
	elseif id == "yard" then
		return value .. " Thinglets"
	elseif id == "reach" then
		return value .. " studs"
	elseif id == "perfect" then
		return math.floor(value * 100 + 0.5) .. "% zone"
	elseif id == "bumper" then
		return math.floor(value * 100 + 0.5) .. "% chance"
	elseif id == "nap" then
		local hours = value / 3600
		return (hours == math.floor(hours) and string.format("%d", hours) or string.format("%.1f", hours)) .. "h away"
	elseif id == "growth" then
		return "+" .. math.floor((value - 1) * 100 + 0.5) .. "% speed"
	elseif id == "luck" then
		return "x" .. string.format("%.1f", value) .. " luck"
	elseif id == "income" then
		return "+" .. math.floor((value - 1) * 100 + 0.5) .. "% income"
	end
	return "+" .. math.floor((value - 1) * 100 + 0.5) .. "% coins"
end

-- Just the number, short, for small cards: "5", "+30%", "19", "1.5h", "x1.2"
function Rules.upgradeShort(id, level)
	local value = Rules.upgradeValue(id, level)
	if id == "plots" or id == "yard" or id == "reach" then
		return tostring(value)
	elseif id == "perfect" or id == "bumper" then
		return math.floor(value * 100 + 0.5) .. "%"
	elseif id == "nap" then
		local hours = value / 3600
		return (hours == math.floor(hours) and string.format("%d", hours) or string.format("%.1f", hours)) .. "h"
	elseif id == "luck" then
		return "x" .. string.format("%.1f", value)
	end
	return "+" .. math.floor((value - 1) * 100 + 0.5) .. "%"
end

-- The effect for a save, in one call (the server and the HUD both use it)
function Rules.upgradeEffect(data, id)
	return Rules.upgradeValue(id, Rules.upgradeLevel(data, id))
end

----------------------------------------------------------------------
-- Where plot `i` stands. Plots line both sides of the street (which runs
-- along X through the middle of the map). Its LookVector points at the
-- road, so plot-local -Z is the front lawn and +Z is the house.
----------------------------------------------------------------------
-- plot i's centre (x, z) and which side of the street it's on (1 north, -1 south)
function Rules.plotSpot(i)
	local w = Config.World
	local entry = w.PlotOrder[i] or w.PlotOrder[1]
	local side, column = entry[1], entry[2]
	local x = (column - (w.PlotsPerSide + 1) / 2) * w.PlotSpacing
	local z = side * (w.RoadWidth / 2 + w.SidewalkWidth + w.FrontYard + w.PlotDepth / 2)
	return x, z, side
end

function Rules.plotCFrame(i)
	local x, z = Rules.plotSpot(i)
	return CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, 0))
end

-- A seed delivery's timeline for plot i, in seconds after the truck sets off.
-- The server plants the seed at `total`; every client plays the same show.
function Rules.deliveryTimes(i)
	local d = Config.Delivery
	local x = Rules.plotSpot(i)
	local drive = math.max(0.6, (x - d.StartX) / d.Speed)
	local throwAt = drive + d.Brake
	local landAt = throwAt + d.Throw
	return { drive = drive, throwAt = throwAt, landAt = landAt, total = landAt + d.Open, leaveAt = throwAt + d.Leave }
end

-- 0..1 -> 0..1: drives at a steady speed, then brakes hard over the last 30%
local CRUISE = 0.7
function Rules.cruiseBrake(u)
	u = math.clamp(u, 0, 1)
	local v = 2 / (1 + CRUISE) -- the cruising speed that still gets there at u = 1
	if u <= CRUISE then
		return v * u
	end
	local w = u - CRUISE
	return v * CRUISE + v * w - v * w * w / (2 * (1 - CRUISE))
end

-- Where the delivery truck to plot i is along the street (x), t seconds
-- after it set off, and what it's doing: "drive" (u = 0..1 of the way),
-- "stop" (u = seconds stopped) or "leave" (u = seconds since it pulled away)
function Rules.truckX(i, t)
	local d = Config.Delivery
	local plotX = Rules.plotSpot(i)
	local times = Rules.deliveryTimes(i)
	if t < times.drive then
		local u = math.max(0, t) / times.drive
		return d.StartX + (plotX - d.StartX) * Rules.cruiseBrake(u), "drive", u
	end
	if t < times.leaveAt then
		return plotX, "stop", t - times.drive
	end
	local u = t - times.leaveAt
	local topAt = d.LeaveSpeed / d.PullAway
	if u < topAt then
		return plotX + 0.5 * d.PullAway * u * u, "leave", u
	end
	return plotX + 0.5 * d.PullAway * topAt * topAt + d.LeaveSpeed * (u - topAt), "leave", u
end

-- How much of the truck shows at x: 0 deep in a tunnel, 1 out on the street
function Rules.truckVisible(x)
	local d = Config.Delivery
	return math.clamp(math.min(x - d.StartX, d.EndX - x) / d.Fade, 0, 1)
end

return Rules
