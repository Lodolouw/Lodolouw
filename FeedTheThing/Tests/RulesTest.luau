--[[
	Tests for Rules.lua, run outside Studio:
	    python3 FeedTheThing/Tests/run_tests.py
	(needs the Luau command line, "luau", from https://github.com/luau-lang/luau/releases)
	run_tests.py bundles Config.lua and Rules.lua in front of this file with a
	few stand-ins for Roblox types, so `require("Config")` below works.
]]

local Config = require("Config")
local Rules = require("Rules")
Rules.useConfig(Config)

local passed, failed = 0, 0
local function check(name, got, want)
	if got == want then
		passed += 1
	else
		failed += 1
		print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end
local function near(name, got, want)
	check(name, math.abs(got - want) < 1e-6, true)
	if math.abs(got - want) >= 1e-6 then
		print("   ", got, want)
	end
end
local function sum(odds)
	local total = 0
	for _, chance in pairs(odds) do
		total += chance
	end
	return total
end

-- the foods' odds in Config add up to 1, and better food is luckier
do
	local okSums, better = true, true
	local previousRare = -1
	for _, crop in ipairs(Config.Crops) do
		if math.abs(sum(crop.odds) - 1) > 1e-9 then
			okSums = false
			print("   odds of " .. crop.id .. " add up to " .. sum(crop.odds))
		end
		local rare = 1 - crop.odds.Common
		if rare <= previousRare then
			better = false
		end
		previousRare = rare
	end
	check("every food's odds add up to 1", okSums, true)
	check("each food is better than the one before", better, true)
end

-- hatch odds
local odds = Rules.hatchOdds("Tomato", 0)
near("no luck: as in Config", odds.Legendary, Config.Crops[1].odds.Legendary)
near("odds add up to 1", sum(odds), 1)
local lucky = Rules.hatchOdds("Tomato", 0.5)
near("lucky odds add up to 1", sum(lucky), 1)
check("luck: more Rare", lucky.Rare > odds.Rare, true)
check("luck: more Legendary", lucky.Legendary > odds.Legendary, true)
check("luck: less Common", lucky.Common < odds.Common, true)
check("luck helps Legendary most", lucky.Legendary / odds.Legendary > lucky.Rare / odds.Rare, true)
local melon, luckyMelon = Rules.hatchOdds("MoonMelon", 0), Rules.hatchOdds("MoonMelon", 1.5)
check("luck still matters with the best food", luckyMelon.Legendary > melon.Legendary + 0.05, true)
near("best food, lots of luck: still adds up", sum(luckyMelon), 1)
near("unknown food acts like the first", Rules.hatchOdds("Nope", 0).Common, Config.Crops[1].odds.Common)
near("negative luck counts as none", Rules.hatchOdds("Chili", -3).Rare, Config.Crops[2].odds.Rare)

-- mutations
local chances = Rules.mutationChances(0, "")
near("base frozen", chances.Frozen, 0.04)
near("base gold", chances.Gold, 0.005)
near("luck raises gold", Rules.mutationChances(1, "").Gold, 0.01)
near("snow: frozen x3", Rules.mutationChances(0, "Snow").Frozen, 0.12)
near("snow: glowing stays", Rules.mutationChances(0, "Snow").Glowing, 0.02)
near("full moon: glowing x3", Rules.mutationChances(0, "FullMoon").Glowing, 0.06)
local maxed = Rules.mutationChances(1.5, "Snow")
check("never more than 100% mutated", maxed.Frozen + maxed.Glowing + maxed.Gold < 1, true)

-- rolling a hatch (the r's are the dice: 0 up to 1)
local kind, mut, rarity = Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.1, 0.9)
check("common roll", kind, "Blorp")
check("common roll: rarity", rarity, "Common")
check("no mutation", mut, "")
check("its favourite most of the time", (Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.59, 0.9)), "Blorp")
check("other commons the rest", (Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.99, 0.9)), "Sizzle")
check("a rare from a tomato", select(3, Rules.rollHatch("Tomato", 0, "", 0.5, 0.95, 0.1, 0.9)), "Rare")
check("rare kinds share it", (Rules.rollHatch("Tomato", 0, "", 0.5, 0.95, 0.99, 0.9)), "Glumcap")
check("legendary from a tomato", (Rules.rollHatch("Tomato", 0, "", 0.5, 0.99999, 0.5, 0.9)), "Moonmoth")
check("chili's favourite", (Rules.rollHatch("Chili", 0, "", 0.5, 0.1, 0.3, 0.9)), "Sizzle")
check("eyeberry leans to Peeper", (Rules.rollHatch("Eyeberry", 0, "", 0.5, 0.9, 0.3, 0.9)), "Peeper")
check("the secret", (Rules.rollHatch("MoonMelon", 0, "", 0.0001, 0.5, 0.5, 0.9)), "LilThing")
check("the secret is rare", (Rules.rollHatch("MoonMelon", 0, "", 0.01, 0.01, 0.5, 0.9)) ~= "LilThing", true)
check("the secret is never rolled as a normal Legendary", (Rules.rollHatch("MoonMelon", 0, "", 0.5, 0.999, 0.99, 0.9)), "Moonmoth")
check("gold (rarest first)", select(2, Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.1, 0.004)), "Gold")
check("glowing", select(2, Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.1, 0.01)), "Glowing")
check("frozen", select(2, Rules.rollHatch("Tomato", 0, "", 0.5, 0.1, 0.1, 0.05)), "Frozen")
check("snow makes frozen likely", select(2, Rules.rollHatch("Tomato", 0, "Snow", 0.5, 0.1, 0.1, 0.12)), "Frozen")
do
	-- roll lots with a fixed random generator: about the right share comes out
	local rand = Rules.random(4242)
	local counts, n = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }, 20000
	for _ = 1, n do
		local _, _, r = Rules.rollHatch("Glowshroom", 0, "", rand(), rand(), rand(), rand())
		counts[r] += 1
	end
	check("about 45% rare from glowshrooms", math.abs(counts.Rare / n - 0.45) < 0.015, true)
	check("about 12% epic from glowshrooms", math.abs(counts.Epic / n - 0.12) < 0.01, true)
end

-- eggs and nests
check("a tomato egg", Rules.eggSeconds("Tomato", 1, false), 6)
check("quick eggs", Rules.eggSeconds("Chili", 2, false), 4)
check("the first egg is quick", Rules.eggSeconds("MoonMelon", 1, true), Config.Eggs.FirstEgg)
check("first nest", Rules.freeNest({}, 3), 1)
check("next free nest", Rules.freeNest({ { nest = 1 }, { nest = 3 } }, 3), 2)
check("nests full", Rules.freeNest({ { nest = 1 }, { nest = 2 }, { nest = 3 } }, 3), nil)
check("never more nests than spots", Rules.freeNest({}, 0), nil)
check("as many spots as the max nests", #Config.Eggs.NestSpots >= Config.Eggs.StartNests + Rules.upgradeMax("nests"), true)

-- the thing's size
check("size 1", Rules.sizeIndex(0), 1)
check("size 2", Rules.sizeIndex(Config.Thing.Sizes[2].growth), 2)
check("size 5", Rules.sizeIndex(1e12), 5)
near("luck from size", Rules.luck({ upgrades = {} }, 2), Config.Thing.Sizes[2].luck)
near("luck from size + upgrade", Rules.luck({ upgrades = { luck = 4 } }, 1), 4 * Rules.upgradeDef("luck").per)

-- growth and income
local blorp = { kind = "Blorp", born = 1000, start = 0.25 }
near("progress at birth", Rules.progress(blorp, 1000), 0.25)
near("progress half way", Rules.progress(blorp, 1060), 0.625)
near("progress grown", Rules.progress(blorp, 5000), 1)
near("height at birth", Rules.height(blorp, 1000), Config.HatchlingHeight)
near("height grown", Rules.height(blorp, 5000), 6)
near("earned while growing", Rules.earned(blorp, 1000, 1120), (0.25 + 1) / 2 * 120)
near("earned after grown", Rules.earned(blorp, 2000, 2100), 100)
near("earned across", Rules.earned(blorp, 1060, 1180), (0.625 + 1) / 2 * 60 + 60)
local goldBlorp = { kind = "Blorp", mut = "Gold", born = 0, start = 1 }
check("offline capped", Rules.offlineCoins({ goldBlorp }, 100, 100 + 86400, 3600), 5 * 3600)
check("offline short", Rules.offlineCoins({ goldBlorp }, 100, 160), 300)
check("offline with comfy yard", Rules.offlineCoins({ goldBlorp }, 100, 160, 3600, 1.5), 450)
check("offline new player", Rules.offlineCoins({ goldBlorp }, 0, 160), 0)
check("sell price", Rules.sellPrice(goldBlorp), 5 * Config.Yard.SellSeconds)

-- the yard: room, then better ones take the weakest one's place
do
	local yard = { { kind = "Peeper" }, { kind = "Blorp" }, { kind = "Sizzle" } }
	check("room in the yard", Rules.yardPlace(yard, 4, { kind = "Blorp" }), "add")
	local how, index = Rules.yardPlace(yard, 3, { kind = "Glumcap" })
	check("better: replaces...", how, "replace")
	check("...the weakest", index, 2)
	check("no better: sold", Rules.yardPlace(yard, 3, { kind = "Blorp" }), "sell")
	check("a mutation counts", Rules.yardPlace(yard, 3, { kind = "Blorp", mut = "Frozen" }), "replace")
end

-- weather
local w, changeAt = Rules.weatherAt(0)
check("calm at cycle start", w, nil)
check("weather starts at 9 min", changeAt, 540)
w, changeAt = Rules.weatherAt(600)
check("weather at 10 min", w ~= nil, true)
check("weather ends at 12 min", changeAt, 720)
local kinds = {}
for c = 0, 200 do
	local t = Rules.weatherAt(c * 720 + 600)
	kinds[t.id] = true
end
check("both weathers happen", kinds.Snow and kinds.FullMoon, true)

-- numbers
check("short 999", Rules.short(999), "999")
check("short 1000", Rules.short(1000), "1K")
check("short 1500", Rules.short(1500), "1.5K")
check("short 100000", Rules.short(100000), "100K")
check("short 12345678", Rules.short(12345678), "12.3M")
check("short 1.05B", Rules.short(1050000000), "1.05B")
check("rate small", Rules.rate(0.25), "0.2")
check("rate whole", Rules.rate(1), "1")
check("rate tens", Rules.rate(12.7), "12")
check("rate big", Rules.rate(1500), "1.5K")
check("clock", Rules.clock(125), "2:05")

-- plots and the coin truck
local x1, z1, side1 = Rules.plotSpot(1)
check("plot 1 is north of the street", side1, 1)
check("plot 1 faces the road from the north", z1 > 0, true)
local _, z2, side2 = Rules.plotSpot(2)
check("plot 2 is across the street", side2 == -1 and z2 < 0, true)
check("plots 1 and 2 face each other", x1, (Rules.plotSpot(2)))
local west, far = Rules.deliveryTimes(5), Rules.deliveryTimes(7) -- west end vs east end
check("the far end takes longer", far.total > west.total, true)
check("timeline in order", west.drive < west.throwAt and west.throwAt < west.landAt and west.landAt < west.total, true)
check("a delivery takes a few seconds", far.total > 3 and far.total < 10, true)
check("cruiseBrake starts at 0", Rules.cruiseBrake(0), 0)
check("cruiseBrake ends at 1", math.abs(Rules.cruiseBrake(1) - 1) < 1e-9, true)
check("cruiseBrake joins up smoothly", math.abs(Rules.cruiseBrake(0.7 - 1e-6) - Rules.cruiseBrake(0.7 + 1e-6)) < 1e-4, true)
do
	local D = Config.Delivery
	local smooth, forward, previous = true, true, nil
	for plot = 1, 8 do
		local times = Rules.deliveryTimes(plot)
		local plotX = Rules.plotSpot(plot)
		check("truck " .. plot .. " starts in the west tunnel", (Rules.truckX(plot, 0)), D.StartX)
		check("truck " .. plot .. " stops at its plot", math.abs(Rules.truckX(plot, times.drive) - plotX) < 1e-6, true)
		check("truck " .. plot .. " is stopped for the throw", select(2, Rules.truckX(plot, times.throwAt)), "stop")
		check("truck " .. plot .. " leaves after the throw", times.leaveAt > times.throwAt, true)
		check("truck " .. plot .. " is gone in 15s", Rules.truckX(plot, 15) > D.EndX, true)
		previous = nil
		for k = 0, 1500 do
			local x = Rules.truckX(plot, k / 100)
			if previous then
				if x < previous - 1e-9 then
					forward = false
				end
				if x - previous > 1.2 then -- 120 studs a second at most
					smooth = false
				end
			end
			previous = x
		end
	end
	check("the truck never backs up", forward, true)
	check("the truck never jumps", smooth, true)
	check("hidden deep in the west tunnel", Rules.truckVisible(D.StartX), 0)
	check("hidden deep in the east tunnel", Rules.truckVisible(D.EndX), 0)
	check("hidden past the end", Rules.truckVisible(D.EndX + 50), 0)
	check("seen on the street", Rules.truckVisible(0), 1)
	check("seen at the last plot", Rules.truckVisible(Rules.plotSpot(7) + 40), 1)
	check("half faded in the tunnel mouth", Rules.truckVisible(D.EndX - D.Fade / 2), 0.5)
end
check("clock hours", Rules.clock(3725), "1:02:05")

-- upgrades
do
	local fresh = { yardCap = Config.Yard.StartCap, upgrades = {} }
	check("new save: no levels", Rules.upgradeLevel(fresh, "luck"), 0)
	check("yard level from the save", Rules.upgradeLevel({ yardCap = 10 }, "yard"), 2)
	check("yard uses its price list", Rules.upgradeCost("yard", 0), Config.Yard.Prices[9])
	check("yard max", Rules.upgradeMax("yard"), Config.Yard.MaxCap - Config.Yard.StartCap)
	check("maxed costs nothing (nil)", Rules.upgradeCost("nests", 3), nil)
	check("first nest", Rules.upgradeCost("nests", 0), 500)
	check("prices are tidy", Rules.upgradeCost("income", 7) % 10, 0)
	local rising = true
	for _, def in ipairs(Config.Upgrades) do
		for level = 1, Rules.upgradeMax(def.id) - 1 do
			if Rules.upgradeCost(def.id, level) <= Rules.upgradeCost(def.id, level - 1) then
				rising = false
				print("   " .. def.id .. " level " .. level)
			end
		end
	end
	check("every level costs more than the last", rising, true)
	local n, cost = Rules.upgradeBuy("income", 0, 3000, 10)
	check("buy as many as you can afford", n > 1 and n < 10 and cost <= 3000, true)
	check("buy x1", (Rules.upgradeBuy("income", 0, 3000, 1)), 1)
	check("can't afford any", (Rules.upgradeBuy("income", 0, 10, 10)), 0)
	check("buy max stops at max", (Rules.upgradeBuy("nests", 1, 1e12, 999)), 2)
	check("nests count", Rules.upgradeValue("nests", 2), Config.Eggs.StartNests + 2)
	check("yard count", Rules.upgradeValue("yard", 3), Config.Yard.StartCap + 3)
	near("income +10% a level", Rules.upgradeValue("income", 3), 1.3)
	near("speed", Rules.upgradeValue("speed", 5), 1.5)
	near("luck from 0", Rules.upgradeValue("luck", 0), 0)
	check("text: income", Rules.upgradeText("income", 3), "+30% coins")
	check("text: speed", Rules.upgradeText("speed", 2), "+20% faster")
	check("text: luck", Rules.upgradeText("luck", 4), "+20% luck")
	check("text: nests", Rules.upgradeText("nests", 1), "4 nests")
	check("text: yard", Rules.upgradeText("yard", 1), "9 Thinglets")
	check("short: nests", Rules.upgradeShort("nests", 1), "4")
	check("short: income", Rules.upgradeShort("income", 3), "+30%")
	check("short: luck", Rules.upgradeShort("luck", 2), "+10%")
	near("effect from a save", Rules.upgradeEffect({ upgrades = { income = 2 } }, "income"), 1.2)
	check("every upgrade has an icon", (function()
		for _, def in ipairs(Config.Upgrades) do
			if type(def.icon) ~= "string" then
				return false
			end
		end
		return true
	end)(), true)
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
