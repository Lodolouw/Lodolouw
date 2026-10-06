--[[
	Rules  (ModuleScript, parent: ReplicatedStorage, name: "Rules")

	The game's rules as plain functions: what an egg hatches into (food odds,
	luck, weather), how long it takes, how grown a Thinglet is, what it has
	earned, the upgrades and the weather. The server decides with these and
	the HUD shows the same answers, so they can never disagree.

	Nothing in here touches Roblox objects (except plotCFrame at the bottom),
	so the rules can be tested outside Studio: see Tests/RulesTest.luau.
]]

local Rules = {}

local Config
local cropById, cropRank, mutationById, upgradeById, byRarity

local function index()
	cropById, cropRank, mutationById, upgradeById, byRarity = {}, {}, {}, {}, {}
	-- the (non-secret) Thinglets of each rarity, in dex order
	for _, kind in ipairs(Config.ThingletOrder) do
		local def = Config.Thinglets[kind]
		if def and not def.secret then
			byRarity[def.rarity] = byRarity[def.rarity] or {}
			table.insert(byRarity[def.rarity], kind)
		end
	end
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
-- What an egg hatches into. Every food can hatch every rarity; better
-- food has better odds (Config.Crops[].odds). Luck (a bigger Thing, the
-- Lucky Thing upgrade) makes the rarer ones more likely: 0.5 = +50%.
-- It helps the rarest most: Rare x(1 + luck), Epic x(1 + 2 luck),
-- Legendary x(1 + 3 luck), and then the odds are shared out again so
-- they still add up to 1. (So luck still matters with the best food.)
----------------------------------------------------------------------
-- All your luck: the Thing's size plus the Lucky Thing upgrade
function Rules.luck(data, sizeIndex)
	local size = Config.Thing.Sizes[sizeIndex or 1] or Config.Thing.Sizes[1]
	return (size.luck or 0) + Rules.upgradeEffect(data, "luck")
end

-- { Common = 0.9, Rare = 0.095, ... } for this food with this luck
function Rules.hatchOdds(foodId, luck)
	local crop = cropById[foodId] or Config.Crops[1]
	luck = math.max(0, luck or 0)
	local odds, total = {}, 0
	for i, rarity in ipairs(Config.RarityOrder) do
		odds[rarity] = (crop.odds[rarity] or 0) * (1 + luck * (i - 1))
		total += odds[rarity]
	end
	for rarity, weight in pairs(odds) do
		odds[rarity] = total > 0 and weight / total or 0
	end
	return odds
end

-- { Frozen = 0.04, Glowing = 0.02, Gold = 0.005 }: luck raises them all,
-- the weather multiplies its own mutation
function Rules.mutationChances(luck, weatherId)
	local weather
	for _, w in ipairs(Config.Weather.Types) do
		if w.id == weatherId then
			weather = w
		end
	end
	local chances = {}
	for _, mutation in ipairs(Config.Mutations) do
		local chance = mutation.base * (1 + math.max(0, luck or 0))
		if weather and weather.mutation == mutation.id then
			chance *= weather.boost or 1
		end
		chances[mutation.id] = chance
	end
	return chances
end

-- What hatches. The r's are random numbers from 0 up to 1 (the server
-- rolls them; the tests pass their own). Returns kind, mutation ("" for
-- none), rarity.
function Rules.rollHatch(foodId, luck, weatherId, rSecret, rRarity, rKind, rMutation)
	local crop = cropById[foodId] or Config.Crops[1]
	local boost = 1 + math.max(0, luck or 0)
	local kind
	if rSecret < (crop.secret or 0) * boost then
		kind = Config.SecretThinglet
	else
		local odds = Rules.hatchOdds(foodId, luck)
		local rarity = Config.RarityOrder[1]
		local total = 0
		for _, r in ipairs(Config.RarityOrder) do
			total += odds[r]
			if rRarity < total then
				rarity = r
				break
			end
		end
		local kinds = byRarity[rarity] or { Config.ThingletOrder[1] }
		local favourite = crop.thinglet
		local leans = Config.Thinglets[favourite] and Config.Thinglets[favourite].rarity == rarity
		if leans and rKind < Config.FavouriteChance then
			kind = favourite
		else
			local u = leans and (rKind - Config.FavouriteChance) / (1 - Config.FavouriteChance) or rKind
			kind = kinds[math.clamp(math.floor(u * #kinds) + 1, 1, #kinds)]
		end
	end
	-- a mutation? (rarest first)
	local chances = Rules.mutationChances(luck, weatherId)
	local mutation, total = "", 0
	for i = #Config.Mutations, 1, -1 do
		local id = Config.Mutations[i].id
		total += chances[id]
		if rMutation < total then
			mutation = id
			break
		end
	end
	return kind, mutation, Config.Thinglets[kind].rarity
end

-- Seconds this food's egg takes (speed = the Quick eggs upgrade, 1.2 = 20% faster)
function Rules.eggSeconds(foodId, speed, first)
	if first then
		return Config.Eggs.FirstEgg
	end
	local crop = cropById[foodId] or Config.Crops[1]
	return crop.egg / math.max(1, speed or 1)
end

-- The first empty nest (eggs = { { nest = 2, ... } ... }), or nil when
-- all `nests` are taken
function Rules.freeNest(eggs, nests)
	local used = {}
	for _, egg in ipairs(eggs) do
		used[egg.nest or 0] = true
	end
	for nest = 1, math.min(nests, #Config.Eggs.NestSpots) do
		if not used[nest] then
			return nest
		end
	end
	return nil
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

-- What the whole yard earned while you were away (capped at Offline.MaxSeconds;
-- mult = the Comfy yard upgrade and friends)
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

-- Where a new Thinglet goes: "add" (there's room), "replace" (the yard is
-- full and it's better than the weakest one there: also returns that one's
-- index) or "sell" (the yard is full of better ones)
function Rules.yardPlace(yard, cap, record)
	if #yard < cap then
		return "add", nil
	end
	local weakest, lowest = nil, math.huge
	for i, other in ipairs(yard) do
		local income = Rules.fullIncome(other)
		if income < lowest then
			weakest, lowest = i, income
		end
	end
	if weakest and Rules.fullIncome(record) > lowest then
		return "replace", weakest
	end
	return "sell", nil
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
-- yardCap and upgrades = { [id] = level }.
----------------------------------------------------------------------
function Rules.upgradeDef(id)
	return upgradeById[id]
end

function Rules.upgradeLevel(data, id)
	if id == "yard" then
		return (data.yardCap or Config.Yard.StartCap) - Config.Yard.StartCap
	end
	return data.upgrades and data.upgrades[id] or 0
end

function Rules.upgradeMax(id)
	if id == "yard" then
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
	if id == "yard" then
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
	if id == "yard" then
		return Config.Yard.StartCap + level -- Thinglets
	elseif id == "nests" then
		return Config.Eggs.StartNests + level -- nests
	elseif id == "luck" then
		return (def and def.per or 0) * level -- extra luck (0.3 = +30%)
	end
	return 1 + (def and def.per or 0) * level -- income, speed: multipliers
end

local function percent(x)
	return math.floor(x * 100 + 0.5)
end

-- The same, in words for the menu
function Rules.upgradeText(id, level)
	local value = Rules.upgradeValue(id, level)
	if id == "yard" then
		return value .. " Thinglets"
	elseif id == "nests" then
		return value .. " nests"
	elseif id == "luck" then
		return "+" .. percent(value) .. "% luck"
	elseif id == "speed" then
		return "+" .. percent(value - 1) .. "% faster"
	end
	return "+" .. percent(value - 1) .. "% coins"
end

-- Just the number, short, for small cards: "9", "+30%"
function Rules.upgradeShort(id, level)
	local value = Rules.upgradeValue(id, level)
	if id == "yard" or id == "nests" then
		return tostring(value)
	elseif id == "luck" then
		return "+" .. percent(value) .. "%"
	end
	return "+" .. percent(value - 1) .. "%"
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

-- The coin truck's timeline for plot i, in seconds after it sets off.
-- The server pays out at `total`; every client plays the same show.
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
