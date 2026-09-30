--!nocheck
-- Headless test of THE ARCADE's server side: ArcadeService (the spins) and the
-- Arcade Tokens in PlayerService (quests, bosses, saves), run for real on a
-- pretend server with two players.
--   * the odds: 200,000 spins come out at the odds the machines show; the
--     first spin ever is never a Common; a Legendary or better never takes
--     more than Config.Arcade.Pity spins on a machine, and each machine keeps
--     its own count
--   * the ArcadeRoll action (through the real Action remote): what it refuses
--     (bad requests, a machine you haven't opened, outside the lobby, too
--     fast, not enough tokens) and what it does - takes the price (x1 / x10),
--     gives new weapons, mastery for ones you own (shown at once if it's in
--     your hand), a token back once one's mastered, tells every screen, and
--     puts Legendary-or-better spins on the BIG WINS board
--   * tokens: a new player's first quest is the small dummy one, a handed-in
--     quest pays a token, a new set of quests comes every 6 hours, a boss's
--     first win pays a bundle (and opens its machine), DEV: +10 Tokens, and
--     tokens and the Arcade's counters are saved - a nonsense save is cleaned up
--   * the board's Colosseum clear quest counts clears
--   * an old save's armour gear and boss chests become Arcade Tokens, once,
--     and the coins it spent on upgrades and talismans come back, once
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame, Enum, Random = M.Instance, M.Vector3, M.CFrame, M.Enum, M.Random
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage
local workspace = M.workspace

RunService.IsStudio = function()
	return true
end
M.game.BindToClose = function() end

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- a pretend DataStore: Bravo has an old save with nonsense in it
-- Delta and Echo left with a quest finished but not handed in, and the board
-- has changed since (Echo's was handed in; Foxtrot's wasn't finished)
local oldSet = math.floor((1700000000 - 6 * 3600) / (6 * 3600)) -- (the pretend clock's last set)
local function oldQuests(n, claimed)
	return { day = oldSet, pick = 1, list = { { id = "Arena30", n = n, claimed = claimed }, { id = "Boss1", n = 0 }, { id = "Clear1", n = 0 } } }
end
local saves = {
	u_1002 = {
		Power = 100, Coins = 5, Tokens = -5, QuestsDone = 1e12,
		Arcade = { spins = 0 / 0, pity = { Slime = 7.9, Knight = "x", Nope = 3 } },
	},
	u_1004 = { Power = 100, Coins = 100, Tokens = 2, QuestsDone = 4, Quests = oldQuests(30, false) },
	u_1005 = { Power = 100, Coins = 100, Tokens = 2, QuestsDone = 4, Quests = oldQuests(30, true) },
	u_1006 = { Power = 100, Coins = 100, Tokens = 2, QuestsDone = 4, Quests = oldQuests(12, false) },
	-- Golf and Hotel played before armour gear and boss chests were taken out
	u_1007 = {
		Power = 100, Coins = 100, Tokens = 3, Prestige = 2, NextId = 9, BestLevel = 40,
		Chests = { ["0"] = 1, ["1"] = 3, ["2"] = "x" },
		Items = { a = { id = "SquishyGloves" }, b = { id = "OozarkCrown" }, c = { id = "SecretCoin" }, d = { id = "GoneLongAgo" }, e = "x" },
		Gear = { Weapon = "a", Helmet = "c" },
		-- and bought from the Upgrade Shop and crafted talismans
		Upgrades = { PowerGain = 2, Backpack = 0, Nope = 9 }, Owned = { Might = true, Vigor = false },
		-- and loot never sold at the Sell Shop
		Loot = { Scrap = 4, Nope = 99 },
	},
	u_1008 = { Power = 100, Coins = 100, Tokens = 0, Chests = { ["1"] = 5000 } },
}
M.services.DataStoreService = {
	GetDataStore = function()
		return {
			UpdateAsync = function(_, key, fn)
				local new = fn(saves[key])
				if new ~= nil then
					saves[key] = new
				end
				return new
			end,
		}
	end,
}

-- the floor: flat everywhere (the server's movement guard looks for it)
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local function newPlayer(name, id, at)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	p.Parent = Players
	table.insert(M.players, p)
	return p, root
end
local me, myRoot = newPlayer("Alpha", 1001, Vector3.new(0, 3.55, 30))
local bravo = newPlayer("Bravo", 1002, Vector3.new(6, 3.55, 30))

-- a move the server allows (the movement guard leaves it alone)
local function moveTo(player, pos)
	player:SetAttribute("MoveTo", pos)
	player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + 1)
	player.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
end

-- what the server tells the screens
local rolls, notices = {}, {}
M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	if remote.Name == "ArcadeEvent" and a[1] == "Roll" then
		table.insert(rolls, { target = target, userId = a[2], name = a[3], machine = a[4], shown = a[5] })
	elseif remote.Name == "Notify" then
		table.insert(notices, tostring(a[1]))
	end
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local AS = mount.require(mount.module("ServerScriptService/ArcadeService.lua"))
local A, W = Config.Arcade, Config.Weapons

local T = 0
local function step(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += 1 / 30
		M.run(T)
		RunService.Heartbeat:Fire(1 / 30)
	end
end

PS.Start()
CS.Start(PS)
AS.Start(PS, CS)
step(0.5)
local d, bd = PS.GetData(me), PS.GetData(bravo)
assert(d and bd, "both saves should be loaded")
local Action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action")
local event = ReplicatedStorage:FindFirstChild("ArcadeEvent")
check(event ~= nil and event:IsA("RemoteEvent"), "the ArcadeEvent RemoteEvent is made")

local function ask(name, arg, who)
	local ok, msg = Action.OnServerInvoke(who or me, name, arg)
	return ok, msg
end
local function spin(machine, count)
	step(A.Gap + 0.1)
	return ask("ArcadeRoll", { machine = machine, count = count })
end

----------------------------------------------------------------------
-- The numbers
----------------------------------------------------------------------
do
	local total = 0
	for _, r in ipairs(A.Order) do
		total += A.Odds[r]
		check(A.Colors[r] ~= nil and A.Duplicate[r] ~= nil, r .. " has a colour and a duplicate's mastery")
	end
	check(math.abs(total - 100) < 1e-9, "the odds add up to 100% (got " .. total .. ")")
	for id, m in pairs(A.Machines) do
		local pack = Config.arcadePack(id)
		check(pack ~= nil, id .. ": a machine is a weapon pack")
		for _, r in ipairs(A.Order) do
			check(Config.arcadeWeapon(id, r) ~= nil, id .. ": has a " .. r .. " weapon")
		end
		check(m.Ten < m.Price * 10 and m.Ten > 0, id .. ": ten at once is a little cheaper")
		if pack and not m.Open then
			check(A.FirstClear[pack.Floor] ~= nil, id .. ": its boss's first win pays tokens")
		end
	end
	check(A.Machines.Slime.Open == true, "the Slime machine is open from the start")
end

----------------------------------------------------------------------
-- The odds, the first spin and the pity
----------------------------------------------------------------------
do
	local rng = Random.new(7)
	local N = 200000
	local counts = {}
	for _ = 1, N do
		local arcade = { spins = 1, pity = {} } -- (never near the pity)
		local r = AS.rollRarity(rng, arcade, "Slime")
		counts[r] = (counts[r] or 0) + 1
	end
	for _, r in ipairs(A.Order) do
		local p = A.Odds[r] / 100
		local got = (counts[r] or 0) / N
		local sigma = math.sqrt(p * (1 - p) / N)
		check(math.abs(got - p) < 5 * sigma, string.format("%s comes up %.3f%% of the time (the machine says %.3f%%)", r, got * 100, p * 100))
	end

	-- the first spin ever: Rare or better, at the others' odds
	local first, commons = {}, 0
	for _ = 1, 20000 do
		local arcade = { spins = 0, pity = {} }
		local r = AS.rollRarity(rng, arcade, "Slime")
		first[r] = (first[r] or 0) + 1
		if r == "Common" then
			commons += 1
		end
		check(arcade.spins == 1, "a spin is counted")
	end
	check(commons == 0, "the first spin is never a Common (got " .. commons .. ")")
	local share = (first.Rare or 0) / 20000
	check(math.abs(share - 30 / 55) < 0.02, string.format("a first spin is Rare %.1f%% of the time (30/55)", share * 100))

	-- the pity: never more than Pity - 1 misses in a row on a machine
	local arcade = { spins = 1, pity = {} }
	local run, longest, good = 0, 0, 0
	local SPINS = 100000
	for _ = 1, SPINS do
		local r = AS.rollRarity(rng, arcade, "Slime")
		if r == "Legendary" or r == "Mythic" or r == "Secret" then
			good += 1
			run = 0
			check(arcade.pity.Slime == 0, "a Legendary or better starts the count again")
		else
			run += 1
			longest = math.max(longest, run)
			check(arcade.pity.Slime == run, "the count goes up by one a miss")
		end
	end
	check(longest == A.Pity - 1, "at most " .. (A.Pity - 1) .. " misses in a row (longest: " .. longest .. ")")
	print(string.format("with the pity, a Legendary or better comes up %.2f%% of the time (10%% without)", good / SPINS * 100))

	-- each machine keeps its own count
	local two = { spins = 5, pity = { Slime = A.Pity - 1, Knight = 5 } }
	local r = AS.rollRarity(rng, two, "Slime")
	check(r == "Legendary" or r == "Mythic" or r == "Secret", "the spin that reaches the pity is a Legendary or better")
	check(two.pity.Slime == 0 and two.pity.Knight == 5, "and the other machines' counts are left alone")
end

----------------------------------------------------------------------
-- ArcadeRoll: what it refuses
----------------------------------------------------------------------
check(d.Tokens == 0 and d.Arcade and d.Arcade.spins == 0 and d.QuestsDone == 0, "a new player: no tokens, no spins, no quests handed in")
local ok, msg = spin("Slime", 1)
check(not ok and string.find(tostring(msg), "Not enough tokens") and string.find(tostring(msg), "1 token%."), "no tokens: no spin (" .. tostring(msg) .. ")")
ok, msg = ask("DevGive", "Tokens")
check(ok and d.Tokens == 10, "DEV: +10 Tokens gives ten (got " .. tostring(d.Tokens) .. ")")
for _, bad in ipairs({ { nil, "nothing" }, { "Slime", "a bare name" }, { { machine = "Nope", count = 1 }, "a machine that isn't there" },
	{ { machine = "Slime", count = 2 }, "two at once" }, { { machine = "Slime", count = 0 }, "none" }, { { machine = "Slime", count = "1" }, "a count in words" },
	{ { machine = "Slime", count = 1.5 }, "half a spin" }, { { machine = "Cactus", count = 1 }, "a covered machine" } }) do
	step(A.Gap + 0.1)
	ok, msg = ask("ArcadeRoll", bad[1])
	check(not ok, "refuses " .. bad[2])
end
check(d.Tokens == 10 and d.Arcade.spins == 0, "and nothing was taken")
local knightFloor = Config.arcadePack("Knight").Floor
ok, msg = spin("Knight", 1)
check(not ok and string.find(tostring(msg), "Beat " .. Config.arcadePack("Knight").Boss), "a machine you haven't opened says whose boss opens it (" .. tostring(msg) .. ")")
for _, where in ipairs({ { "SpireFloor", 2 }, { "Colosseum", true }, { "Intro", "Void" } }) do
	me:SetAttribute(where[1], where[2])
	ok, msg = spin("Slime", 1)
	check(not ok and string.find(tostring(msg), "Arcade"), "no spinning with " .. where[1] .. " set (" .. tostring(msg) .. ")")
	me:SetAttribute(where[1], nil)
end
check(d.Tokens == 10, "still nothing taken")

----------------------------------------------------------------------
-- ArcadeRoll: a spin
----------------------------------------------------------------------
local ownedBefore = {}
for id in pairs(d.Weapons.own) do
	ownedBefore[id] = true
end
rolls = {}
ok, msg = spin("Slime", 1)
check(ok and type(msg) == "table", "a spin works")
local answer = type(msg) == "table" and msg or {}
local first = answer.results and answer.results[1]
check(answer.machine == "Slime" and answer.results and #answer.results == 1, "one spin, one result")
check(first and first.rarity ~= "Common", "the first spin ever is Rare or better (got " .. tostring(first and first.rarity) .. ")")
check(first and first.id == Config.arcadeWeapon("Slime", first.rarity), "it's that rarity's Slime weapon")
check(first and first.new == true and d.Weapons.own[first.id] == 0, "it's new: it goes in your bag")
check(d.Tokens == 10 - A.Machines.Slime.Price and answer.tokens == d.Tokens, "the price is taken (" .. tostring(d.Tokens) .. " left)")
check(d.Arcade.spins == 1 and answer.spins == 1, "the spin is counted")
check(answer.pity == d.Arcade.pity.Slime, "the answer carries the machine's pity count")
check(#rolls == 1 and rolls[1].target == nil and rolls[1].userId == 1001 and rolls[1].name == "Alpha" and rolls[1].machine == "Slime", "every screen is told who spun what")
check(rolls[1] and #rolls[1].shown == 1 and rolls[1].shown[1].id == first.id and rolls[1].shown[1].rarity == first.rarity, "with the result")
ok, msg = ask("ArcadeRoll", { machine = "Slime", count = 1 })
check(not ok and string.find(tostring(msg), "One spin at a time"), "straight away again: too fast (" .. tostring(msg) .. ")")

-- ten at once
rolls = {}
local before = d.Tokens
ok, msg = spin("Slime", 10)
check(ok and type(msg) == "table" and #msg.results == 10, "ten at once gives ten")
check(d.Tokens == before - A.Machines.Slime.Ten, "for the ten price (" .. before .. " -> " .. d.Tokens .. ")")
check(d.Arcade.spins == 11, "eleven spins counted")
check(#rolls == 1 and #rolls[1].shown == 10, "every screen hears all ten at once")
ok, msg = spin("Slime", 10)
check(not ok and string.find(tostring(msg), A.Machines.Slime.Ten .. " tokens"), "ten more with " .. d.Tokens .. " left: not enough (" .. tostring(msg) .. ")")

----------------------------------------------------------------------
-- Duplicates, mastery and the refund (a fixed "rng" picks the rarity)
----------------------------------------------------------------------
local realRng = AS.rng
local function force(rarity)
	-- NextNumber * total lands in that rarity's slice of Config.Arcade.Order
	local lo = 0
	for _, r in ipairs(A.Order) do
		if r == rarity then
			break
		end
		lo += A.Odds[r]
	end
	local x = (lo + A.Odds[rarity] / 2) / 100
	AS.rng = { NextNumber = function()
		return x
	end }
end
d.Tokens = 20
local commonId = Config.arcadeWeapon("Slime", "Common")
d.Weapons.own[commonId] = d.Weapons.own[commonId] or 0
CS.Equip(me, commonId)
local points0 = d.Weapons.own[commonId]
force("Common")
ok, msg = spin("Slime", 1)
local r1 = type(msg) == "table" and msg.results[1]
check(r1 and r1.id == commonId and r1.mastery == A.Duplicate.Common and not r1.new, "a weapon you own gives mastery instead (" .. tostring(r1 and r1.mastery) .. ")")
check(d.Weapons.own[commonId] == points0 + A.Duplicate.Common, "the mastery goes into your save")
check(me:GetAttribute("Mastery") == Config.masteryLevel(d.Weapons.own[commonId]), "and shows at once, as it's in your hand")
local max = Config.masteryPointsFor(W.MasteryMax)
d.Weapons.own[commonId] = max - 10
ok, msg = spin("Slime", 1)
check(d.Weapons.own[commonId] == max, "mastery stops at the top")
before = d.Tokens
ok, msg = spin("Slime", 1)
r1 = type(msg) == "table" and msg.results[1]
check(r1 and r1.refund == 1, "a weapon already mastered gives a token back")
check(d.Tokens == before - A.Machines.Slime.Price + 1, "so that spin cost nothing")

-- the BIG WINS board
local secretId = Config.arcadeWeapon("Slime", "Secret")
force("Secret")
ok, msg = spin("Slime", 1)
check(ok and msg.results[1].id == secretId, "a Secret spin")
check(d.Arcade.pity.Slime == 0, "a Secret starts the pity count again")
local wins = event:GetAttribute("BigWins")
check(type(wins) == "string" and string.sub(wins, 1, #("Alpha|Secret|" .. secretId)) == "Alpha|Secret|" .. secretId, "it goes up first on the BIG WINS board (" .. tostring(wins) .. ")")
force("Common")
ok, msg = spin("Slime", 1)
check(event:GetAttribute("BigWins") == wins, "a Common doesn't")
d.Tokens = 100
force("Legendary")
for _ = 1, 7 do
	spin("Slime", 1)
end
local lines = string.split(event:GetAttribute("BigWins"), ";")
check(#lines == 5, "the board keeps the latest five (got " .. #lines .. ")")
check(string.find(lines[1], "|Legendary|"), "newest first")
AS.rng = realRng

----------------------------------------------------------------------
-- Tokens from quests
----------------------------------------------------------------------
-- (Bravo's save had nonsense in it)
check(bd.Tokens == 0 and bd.QuestsDone == 0, "a nonsense save's tokens and quests are cleaned up")
check(bd.Arcade.spins == 0 and bd.Arcade.pity.Slime == 7 and bd.Arcade.pity.Knight == 0 and bd.Arcade.pity.Nope == nil, "and its Arcade counters")

-- a new player: the dummy quest on the board is the small one
local newbie = newPlayer("Charlie", 1003, Vector3.new(-6, 3.55, 30))
Players.PlayerAdded:Fire(newbie)
step(0.5)
local cd = PS.GetData(newbie)
local arenaIndex, arenaQuests = nil, 0
for i, q in ipairs(cd.Quests.list) do
	local def = Config.QuestById[q.id]
	if def.kind == "arena" then
		arenaIndex = i
		arenaQuests += 1
	end
end
check(#cd.Quests.list == Config.Quests.PerDay and arenaQuests == 1, "the board has one dummy quest")
check(arenaIndex and cd.Quests.list[arenaIndex].id == Config.Quests.First, "a new player's dummy quest is " .. Config.Quests.First)
check(cd.Quests.day == Config.questPeriod(), "the set is the current 6 hours'")

-- pick it, beat the dummies, hand it in: a token
local board = Config.Stations.Quests
moveTo(newbie, Vector3.new(board.X + 2, 3.55, board.Z + 2))
step(0.2)
ok, msg = ask("PickQuest", arenaIndex, newbie)
check(ok, "picking the dummy quest works (" .. tostring(msg) .. ")")
step(0.2)
ok, msg = ask("ClaimQuest", nil, newbie)
check(not ok, "it can't be handed in before it's done")
PS.QuestProgress(newbie, "arena", Config.QuestById[Config.Quests.First].goal)
local coins = cd.Coins
step(0.2)
ok, msg = ask("ClaimQuest", nil, newbie)
check(ok and string.find(tostring(msg), "ARCADE TOKEN"), "handing it in says it paid a token (" .. tostring(msg) .. ")")
check(cd.Tokens == Config.Quests.Tokens and cd.QuestsDone == 1, "a handed-in quest pays " .. Config.Quests.Tokens .. " token")
check(cd.Coins == coins + Config.QuestById[Config.Quests.First].reward, "and its coins")
step(0.2)
ok, msg = ask("ClaimQuest", nil, newbie)
check(not ok and cd.Tokens == Config.Quests.Tokens, "only once")
-- ...and that token spins the Slime machine (the first spin: Rare or better)
moveTo(newbie, Config.Stations.Arcade + Vector3.new(0, 3.55, 0))
step(A.Gap + 0.1)
ok, msg = ask("ArcadeRoll", { machine = "Slime", count = 1 }, newbie)
check(ok and msg.results[1].rarity ~= "Common" and cd.Tokens == 0, "the quest's token buys the first spin")

-- a new set every 6 hours (a player who's handed one in gets the set as it is)
cd.Quests.day -= 1
PS.QuestProgress(newbie, "arena", 0)
local want = Config.questsForDay(Config.questPeriod())
local same = #cd.Quests.list == #want
for i, id in ipairs(want) do
	same = same and cd.Quests.list[i] and cd.Quests.list[i].id == id
end
check(same and cd.Quests.pick == nil, "an old set is swapped for the current one, nothing picked")

-- a quest finished but not handed in when the board changes is handed in for you
local arenaNow = nil
for i, q in ipairs(cd.Quests.list) do
	if Config.QuestById[q.id].kind == "arena" then
		arenaNow = i
	end
end
moveTo(newbie, Vector3.new(board.X + 2, 3.55, board.Z + 2))
step(0.3)
ok, msg = ask("PickQuest", arenaNow, newbie)
check(ok, "picking a quest in the new set")
local def = Config.QuestById[cd.Quests.list[arenaNow].id]
PS.QuestProgress(newbie, "arena", def.goal)
local tokensBefore, coinsBefore, doneBefore = cd.Tokens, cd.Coins, cd.QuestsDone
notices = {}
cd.Quests.day -= 1 -- (the board changes before it's handed in)
PS.QuestProgress(newbie, "arena", 0)
check(cd.Tokens == tokensBefore + Config.Quests.Tokens and cd.Coins == coinsBefore + def.reward and cd.QuestsDone == doneBefore + 1,
	"a finished quest is handed in for you when the board changes (its token isn't lost)")
local told = false
for _, n in ipairs(notices) do
	told = told or string.find(n, "handed in for you") ~= nil
end
check(told, "and you're told")
check(cd.Quests.pick == nil and cd.Quests.day == Config.questPeriod(), "then the new set is dealt")
cd.Quests.day -= 1
local t2 = cd.Tokens
PS.QuestProgress(newbie, "arena", 0)
check(cd.Tokens == t2, "an unfinished (or unpicked) set pays nothing when it changes")

-- ...and the same for a save from an earlier set
local delta = newPlayer("Delta", 1004, Vector3.new(-12, 3.55, 30))
local echo = newPlayer("Echo", 1005, Vector3.new(-14, 3.55, 30))
local fox = newPlayer("Foxtrot", 1006, Vector3.new(-16, 3.55, 30))
for _, p in ipairs({ delta, echo, fox }) do
	Players.PlayerAdded:Fire(p)
end
step(0.5)
local dd, ed, fd = PS.GetData(delta), PS.GetData(echo), PS.GetData(fox)
local reward = Config.QuestById.Arena30.reward
check(dd and dd.Tokens == 2 + Config.Quests.Tokens and dd.Coins == 100 + reward and dd.QuestsDone == 5, "a save's finished quest from an old set is handed in when you join")
check(ed and ed.Tokens == 2 and ed.Coins == 100 and ed.QuestsDone == 4, "one already handed in isn't paid twice")
check(fd and fd.Tokens == 2 and fd.Coins == 100, "an unfinished one pays nothing")
check(dd and dd.Quests.day == Config.questPeriod() and dd.Quests.pick == nil, "and the new set is dealt")
for _, t in ipairs({ 1700000000, 1700021599, 1700021600, 1712345678 }) do
	local secs = Config.Quests.Hours * 3600
	check(Config.questPeriod(t + secs) == Config.questPeriod(t) + 1, "a new set every " .. Config.Quests.Hours .. " hours")
	local left = Config.nextQuestTime(t) - t
	check(left > 0 and left <= secs, "the next set is less than " .. Config.Quests.Hours .. " hours away (" .. left .. " s)")
end

----------------------------------------------------------------------
-- Tokens from bosses (and machines opening)
----------------------------------------------------------------------
before = d.Tokens
notices = {}
check(PS.RecordBossKill(me, knightFloor) == true, "beating the Knight machine's boss")
check(d.Tokens == before + A.FirstClear[knightFloor], "the first win pays " .. A.FirstClear[knightFloor] .. " tokens (" .. before .. " -> " .. d.Tokens .. ")")
PS.RecordBossKill(me, knightFloor)
check(d.Tokens == before + A.FirstClear[knightFloor], "the second doesn't")
check(Config.arcadeOpen(d, "Knight") == true, "and the Knight machine is open now")
d.Tokens = 5
ok, msg = spin("Knight", 1)
check(ok and Config.arcadePack("Knight") and msg.results[1].id == Config.arcadeWeapon("Knight", msg.results[1].rarity), "it spins Knight weapons")
check(d.Tokens == 5 - A.Machines.Knight.Price, "at the Knight machine's price")

----------------------------------------------------------------------
-- The board's "clear a Colosseum run" quest (it took the place of the old
-- "open treasure chests" one)
----------------------------------------------------------------------
local clearQ = nil
for _, q in ipairs(d.Quests.list) do
	if Config.QuestById[q.id].kind == "clear" then
		clearQ = q
	end
end
check(clearQ ~= nil, "every set of quests has a Colosseum clear quest")
for _, q in ipairs(d.Quests.list) do
	check(Config.QuestById[q.id].kind ~= "chest", "and no treasure chest quests")
end
if clearQ then
	local n0 = clearQ.n
	check(PS.RecordColosseumClear(me, 60, "Normal") ~= nil, "a Colosseum clear is recorded")
	check(clearQ.n == math.min(n0 + 1, Config.QuestById[clearQ.id].goal), "and counts towards it (" .. n0 .. " -> " .. clearQ.n .. ")")
end

----------------------------------------------------------------------
-- Saved
----------------------------------------------------------------------
d.Tokens = 42
Players.PlayerRemoving:Fire(me)
step(1)
local s = saves.u_1001
check(s and s.Tokens == 42, "tokens are saved (" .. tostring(s and s.Tokens) .. ")")
check(s and s.Arcade and s.Arcade.spins == d.Arcade.spins and s.Arcade.pity.Slime == d.Arcade.pity.Slime, "and the Arcade's counters")
check(s and s.QuestsDone == d.QuestsDone, "and the quests handed in")

----------------------------------------------------------------------
-- The old gear, swapped for Arcade Tokens (once)
----------------------------------------------------------------------
notices = {}
local golf = newPlayer("Golf", 1007, Vector3.new(-18, 3.55, 30))
local hotel = newPlayer("Hotel", 1008, Vector3.new(-20, 3.55, 30))
Players.PlayerAdded:Fire(golf)
Players.PlayerAdded:Fire(hotel)
step(0.5)
local gd, hd = PS.GetData(golf), PS.GetData(hotel)
-- 2 old prestiges + 4 chests, and the pieces: a Common 1, a Legendary 5, a
-- Secret 25 and one that isn't in the game any more 1 (the "x"s are nonsense)
local want = 3 + 2 + 4 + 1 + 5 + 25 + 1
check(gd and gd.Tokens == want, "old gear and chests become tokens (" .. tostring(gd and gd.Tokens) .. ", want " .. want .. ")")
check(gd and gd.Items == nil and gd.Gear == nil and gd.Chests == nil and gd.NextId == nil and gd.BestLevel == nil, "and they're gone from the data")
check(hd and hd.Tokens == 100, "at most 100 tokens (" .. tostring(hd and hd.Tokens) .. ")")
-- Training Gloves level 2 (150 + 240), the Talisman of Might (200) and 4 Scrap (5 each)
check(gd and gd.Coins == 100 + 150 + 240 + 200 + 20, "the coins spent in the old shop come back, and the loot is sold (" .. tostring(gd and gd.Coins) .. ")")
check(gd and gd.Upgrades == nil and gd.Owned == nil and gd.Equipped == nil and gd.Loot == nil, "and the upgrades and talismans are gone from the data")
check(hd and hd.Coins == 100, "nothing bought, nothing back")
step(6.5)
local swapNotice = 0
for _, n in ipairs(notices) do
	if string.find(n, "became " .. (want - 3) .. " Arcade Tokens", 1, true) or string.find(n, "became 100 Arcade Tokens", 1, true) then
		swapNotice += 1
	end
end
check(swapNotice == 2, "each is told how many (" .. swapNotice .. "): " .. table.concat(notices, " | "))
Players.PlayerRemoving:Fire(golf)
step(1)
check(saves.u_1007 and saves.u_1007.Tokens == want and saves.u_1007.Items == nil and saves.u_1007.Chests == nil and saves.u_1007.Upgrades == nil, "the save leaves the old gear and shop out")
Players.PlayerAdded:Fire(golf)
step(0.5)
gd = PS.GetData(golf)
check(gd and gd.Tokens == want and gd.Coins == 710, "so it's only ever swapped once (" .. tostring(gd and gd.Tokens) .. ", " .. tostring(gd and gd.Coins) .. ")")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
if fails == 0 then
	print("PASS arcade (server)")
else
	print(fails .. " failures")
end
