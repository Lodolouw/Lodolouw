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
local function belly(spec)
	-- "T T C*" -> tomato, tomato, perfect chili; "M*f" = perfect frozen melon
	local names = { T = "Tomato", C = "Chili", E = "Eyeberry", G = "Glowshroom", P = "Pumpkin", M = "MoonMelon" }
	local muts = { f = "Frozen", l = "Glowing", g = "Gold" }
	local list = {}
	for word in string.gmatch(spec, "%S+") do
		local item = { f = names[string.sub(word, 1, 1)], m = "", p = false }
		for i = 2, #word do
			local c = string.sub(word, i, i)
			if c == "*" then
				item.p = true
			elseif muts[c] then
				item.m = muts[c]
			end
		end
		table.insert(list, item)
	end
	return list
end

-- hatch rules
check("3 tomatoes", Rules.resolveHatch(belly("T T T"), 3), "Blorp")
check("most wins", Rules.resolveHatch(belly("T T C P E"), 5), "Blorp")
check("tie -> rarer", Rules.resolveHatch(belly("T T C C E"), 5), "Sizzle")
check("3-way tie -> rarest", Rules.resolveHatch(belly("T C E"), 3), "Peeper")
check("2 melons + 3 others", Rules.resolveHatch(belly("M M T C E"), 5), "Moonmoth")
check("5 different", Rules.resolveHatch(belly("T C E G P"), 5), "Mishmash")
check("5 different incl melon", Rules.resolveHatch(belly("M C E G P"), 5), "Mishmash")
check("secret", Rules.resolveHatch(belly("M* M* M*f M* M*"), 5), "LilThing")
check("secret needs all perfect", Rules.resolveHatch(belly("M* M* M M* M*"), 5), "Moonmoth")
check("secret needs a full belly", Rules.resolveHatch(belly("M* M* M*"), 5), "Moonmoth")
check("secret at size 1", Rules.resolveHatch(belly("M* M* M*"), 3), "LilThing")
check("empty", Rules.resolveHatch({}, 3), nil)

-- mutation odds
local odds = Rules.mutationOdds(belly("T T T"), 1)
near("base frozen", odds.Frozen, 0.05)
near("base gold", odds.Gold, 0.01)
near("base none", odds.None, 0.91)
odds = Rules.mutationOdds(belly("Tf T* T"), 3)
near("frozen food + perfect + size", odds.Frozen, 0.05 + 0.08 + 0.01 + 0.02)
near("glowing gets perfect + size", odds.Glowing, 0.03 + 0.01 + 0.02)
odds = Rules.mutationOdds(belly("Mg* Mg* Mg* Mg* Mg*"), 5)
near("best possible gold", odds.Gold, 0.01 + 0.04 + 5 * 0.08 + 5 * 0.01)
near("best possible none", odds.None, 0.24)
local oldBonus = Config.MutatedFoodBonus
Config.MutatedFoodBonus = 0.3
odds = Rules.mutationOdds(belly("Mg* Mg* Mg* Mg* Mg*"), 5)
near("capped at 100%", odds.Frozen + odds.Glowing + odds.Gold, 1)
near("none is 0 when capped", odds.None, 0)
Config.MutatedFoodBonus = oldBonus
check("roll low -> Frozen", Rules.rollMutation({ Frozen = 0.05, Glowing = 0.03, Gold = 0.01 }, 0.01), "Frozen")
check("roll mid -> Glowing", Rules.rollMutation({ Frozen = 0.05, Glowing = 0.03, Gold = 0.01 }, 0.06), "Glowing")
check("roll -> Gold", Rules.rollMutation({ Frozen = 0.05, Glowing = 0.03, Gold = 0.01 }, 0.085), "Gold")
check("roll high -> none", Rules.rollMutation({ Frozen = 0.05, Glowing = 0.03, Gold = 0.01 }, 0.5), nil)

-- toss
check("plain tomato", Rules.tossCoins("Tomato", "", 1, false, 0, 0), 3)
check("craving tomato", Rules.tossCoins("Tomato", "", 1, true, 1, 0), 9)
check("craving x combo 4", Rules.tossCoins("Tomato", "", 1, true, 4, 0), 45)
check("combo caps", Rules.tossCoins("Tomato", "", 1, true, 9, 0), 45)
check("gold chili size 3 + friend", Rules.tossCoins("Chili", "Gold", 3, false, 0, 0.1), math.floor(8 * 5 * 1.5 * 1.1 + 0.5))
check("perfect at mid-cycle", Rules.isPerfect(Config.Toss.RingCycle * 0.5), true)
check("not perfect at start", Rules.isPerfect(Config.Toss.RingCycle * 0.05), false)
near("ring smallest at mid", Rules.ringOpen(Config.Toss.RingCycle * 0.5), 0)

-- thing size
check("size 1", Rules.sizeIndex(0), 1)
check("size 2", Rules.sizeIndex(100), 2)
check("size 4", Rules.sizeIndex(60000), 4)
check("size 5", Rules.sizeIndex(1e9), 5)

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
check("offline capped at an hour", Rules.offlineCoins({ goldBlorp }, 100, 100 + 86400), 5 * 3600)
check("offline short", Rules.offlineCoins({ goldBlorp }, 100, 160), 300)
check("offline new player", Rules.offlineCoins({ goldBlorp }, 0, 160), 0)
check("sell price", Rules.sellPrice(goldBlorp), 5 * 30)

-- shop: same answer every time, commons always, moon on the hour
local s1 = Rules.stockFor(12345, 777)
local s2 = Rules.stockFor(12345, 777)
check("stock is repeatable", s1.Eyeberry, s2.Eyeberry)
check("tomato always", s1.Tomato, -1)
check("moon on the hour", Rules.stockFor(12345, 12 * 500).MoonMelon >= 1, true)
local seen, total = 0, 2000
for i = 1, total do
	if Rules.stockFor(98765, i).Pumpkin > 0 then
		seen += 1
	end
end
check("pumpkin about 40% of restocks", math.abs(seen / total - 0.4) < 0.04, true)
local bigId = Rules.stockFor(9876543210, 5900000)
check("huge ids work", bigId.Tomato, -1)

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

-- daily
check("daily picks a grown food", Rules.dailyFood(5, 20000, { "Chili" }), "Chili")
check("daily with nothing grown", Rules.dailyFood(5, 20000, {}), "Tomato")

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
check("clock hours", Rules.clock(3725), "1:02:05")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
