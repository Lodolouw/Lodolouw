--!nocheck
-- Headless test of THE NEW PLAYER PATH (Config.Path, PlayerService.PathEvent)
-- on a pretend server: a brand-new player gets it when the intro ends, a
-- player from before it skips it; each step only moves on when the server
-- sees that thing really happen - in order - and pays its reward once; the
-- whole path pays Done at the end; a client can't push it along itself; it
-- spins the slime's token (the weapon goes straight into your hand), then one
-- Colosseum run; the spin step hands out a token if you've none; DEV: New
-- Player Path starts it again from step 1.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame, Random, Enum = M.Instance, M.Vector3, M.CFrame, M.Random, M.Enum
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage
local workspace = M.workspace
local task = M.task

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

-- a pretend DataStore (Bravo's old save has nonsense in the new fields);
-- `broken` makes every save fail
local broken = false
local saves = {
	u_1002 = {
		Power = 100, Coins = 100,
		Rewards = { streak = 99, giftPlay = 1e9, codes = { LAUNCH = true, [5] = true, X = "yes" }, index = { Nope = true }, seen = 7 },
		Looks = { titles = { Loyal = true, Fake = true }, auras = "x", title = "Fake", aura = "Gold" },
		Boosts = { XP = -5, Coins = 0 / 0, Luck = 1e12 },
		Tickets = { Revive = 2.7, Rush = "x" },
		Shop = { starter = 1, receipts = { "a", 5, "b" }, daily = { day = 3, bought = { x = true } } },
		Settings = { music = false, sfx = "no", hack = true },
	},
}
M.services.DataStoreService = {
	GetDataStore = function()
		return {
			UpdateAsync = function(_, key, fn)
				if broken then
					error("the DataStore is down (pretend)")
				end
				local new = fn(saves[key])
				if new ~= nil then
					saves[key] = new
				end
				return new
			end,
		}
	end,
}

-- a pretend Marketplace: remembers the prompts; Bravo owns the VIP pass
local prompts, passPrompts = {}, {}
local owned = { [1002] = { [901] = true } }
local Marketplace = {
	PromptGamePassPurchaseFinished = M.Signal.new(),
	PromptProductPurchase = function(_, player, id)
		table.insert(prompts, { player = player, id = id })
	end,
	PromptGamePassPurchase = function(_, player, id)
		table.insert(passPrompts, { player = player, id = id })
	end,
	UserOwnsGamePassAsync = function(_, userId, id)
		return owned[userId] ~= nil and owned[userId][id] == true
	end,
}
M.services.MarketplaceService = Marketplace
-- a pretend PolicyService: Bravo lives where paid random items aren't allowed;
-- for Charlie, Roblox can't say (play safe: not allowed either)
M.services.PolicyService = {
	GetPolicyInfoForPlayerAsync = function(_, player)
		if player.UserId == 1003 then
			error("PolicyService is down (pretend)")
		end
		return { ArePaidRandomItemsRestricted = player.UserId == 1002 }
	end,
}

M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local groups = {} -- [userId] = true: in the community
local function newPlayer(name, id, at)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	p.IsFriendsWith = function(self, other)
		-- (Alpha and Bravo are friends)
		return (self.UserId == 1001 and other == 1002) or (self.UserId == 1002 and other == 1001)
	end
	p.IsInGroup = function(self, g)
		return groups[self.UserId] == true
	end
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	local head = Instance.new("Part")
	head.Name = "Head"
	head.CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0))
	head.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	p.Parent = Players
	table.insert(M.players, p)
	return p
end
local me = newPlayer("Alpha", 1001, Vector3.new(0, 3.55, 30))
local bravo = newPlayer("Bravo", 1002, Vector3.new(6, 3.55, 30))
local charlie = newPlayer("Charlie", 1003, Vector3.new(-6, 3.55, 30))

local notices = {}
M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	if remote.Name == "Notify" then
		table.insert(notices, { target = target, text = tostring(a[1]) })
	end
end
local function noticeFor(player, pattern)
	for _, n in ipairs(notices) do
		if n.target == player and string.find(n.text, pattern) then
			return true
		end
	end
	return false
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Shop, R = Config.Shop, Config.Rewards
-- start from a shop that isn't set up yet (the real ids are in Config):
-- every product and pass at 0, each test gives ids to the ones it buys
for _, p in pairs(Shop.Products) do p.ProductId = 0 end
for _, p in pairs(Shop.Passes) do p.PassId = 0 end
table.clear(Config.ShopByProductId)
-- (Bravo's VIP pass is "made" before the server starts, so joining finds it)
Shop.Passes.VIP.PassId = 901
local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local AS = mount.require(mount.module("ServerScriptService/ArcadeService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local RS = mount.require(mount.module("ServerScriptService/RewardService.lua"))
local SS = mount.require(mount.module("ServerScriptService/ShopService.lua"))

local T = 0
-- `seconds` of play, a heartbeat each `dt`
local function play(seconds, dt)
	dt = dt or 1 / 30
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += dt
		M.run(T)
		RunService.Heartbeat:Fire(dt)
	end
end
-- move the calendar on (a new day) without playing through it
local function jump(seconds)
	M.dayShift += seconds
	play(0.1)
end

PS.Start()
CS.Start(PS)
AS.Start(PS, CS)
RS.Start(PS)
SS.Start(PS, RS)
AS.LuckFor = SS.Luck
CS.ReviveHook = SS.Revive
play(0.5)
local d, bd, cd = PS.GetData(me), PS.GetData(bravo), PS.GetData(charlie)
assert(d and bd and cd, "the saves should be loaded")
local Action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action")
local function ask(name, arg, who)
	play(0.15, 0.15) -- (a moment between clicks: the request budget refills)
	return Action.OnServerInvoke(who or me, name, arg)
end
-- (the day, as the server counts them)
local function today()
	return Config.questDay(1700000000 + math.floor(M.now()) + M.dayShift)
end



local P = Config.Path
local steps = P.Steps
check(#steps == 3, "three steps: spin, into the Colosseum, clear it")

----------------------------------------------------------------------
-- who gets it
----------------------------------------------------------------------
check(d.Path and d.Path.step == 0 and not d.Path.done, "a brand-new player: the path waits for the intro")
check(bd.Path and bd.Path.done == true, "a player from before the path existed skips it")

----------------------------------------------------------------------
-- step by step
----------------------------------------------------------------------
d.Tokens = 0
PS.SetIntroDone(me)
play(0.2)
check(d.Path.step == 1 and steps[1].Id == "Spin", "the intro ends: step 1, spin your token (" .. tostring(d.Path.step) .. ")")
check(d.Tokens >= 1, "with no token, the spin step hands you one")

-- out of order: nothing
local coins = d.Coins
PS.PathEvent(me, "Colosseum")
PS.PathEvent(me, "Clear")
PS.PathEvent(me, "Equip")
PS.PathEvent(me, "Quest")
check(d.Path.step == 1 and d.Coins == coins, "doing a later step (or an old one) first moves nothing and pays nothing")

-- a client can't push it along
local ok = ask("PathEvent", "Spin")
check(not ok and d.Path.step == 1, "there's no remote to push the path along")

-- (badges: a pretend BadgeService records what's given)
local awarded = {}
M.services.BadgeService = {
	UserHasBadgeAsync = function(_, userId, id)
		return awarded[id] == userId
	end,
	AwardBadge = function(_, userId, id)
		awarded[id] = userId
		return true
	end,
}
Config.Badges.FirstSpin, Config.Badges.OozarkDown, Config.Badges.SpireConqueror = 111, 222, 333

-- 1. spin (for real, at the Arcade): the weapon goes straight into your hand
me:SetAttribute("Weapon", nil)
ok = ask("ArcadeRoll", { machine = "Slime", count = 1 })
play(0.2)
check(ok, "the spin happens")
check(d.Path.step == 2, "spinning: on to step 2 (" .. tostring(d.Path.step) .. ")")
check(d.Coins == coins + (steps[1].Reward.Coins or 0), "step 1's reward (" .. d.Coins - coins .. ")")
local held = me:GetAttribute("Weapon")
check(held ~= nil and d.Weapons.own[held] ~= nil, "the weapon it won is in your hand (" .. tostring(held) .. ")")
-- a second spin doesn't pay again, or swap what you hold
coins = d.Coins
d.Tokens = math.max(d.Tokens, 1)
play(0.6)
ask("ArcadeRoll", { machine = "Slime", count = 1 })
play(0.2)
check(d.Path.step == 2 and d.Coins == coins, "spinning again pays nothing more")
check(me:GetAttribute("Weapon") == held, "and doesn't swap your weapon")

play(0.1)
check(awarded[111] == me.UserId, "the first spin gives the First Spin badge")
check(awarded[222] == nil, "and nothing else")
PS.RecordBossKill(me, 1, "Nightmare")
PS.RecordBossKill(me, #Config.Spire.Floors)
play(0.1)
check(awarded[222] == me.UserId and awarded[333] == me.UserId, "beating Oozark and the top floor give theirs")
Config.Badges.ColosseumChampion = 0
PS.AwardBadge(me, "ColosseumChampion")
check(awarded[0] == nil, "a badge not made yet (ID 0) is never given")

-- 2. into the Colosseum (ColosseumService tells the path when you arrive)
PS.PathEvent(me, "Colosseum")
play(0.1)
check(d.Path.step == 3, "in the Colosseum: on to step 3 (" .. tostring(d.Path.step) .. ")")
check(d.Coins == coins + (steps[2].Reward.Coins or 0), "step 2's reward")

-- 3. the Colosseum cleared (ColosseumService.FinishRun): the path is done
local tokens
tokens, coins = d.Tokens, d.Coins
PS.PathEvent(me, "Clear")
play(0.1)
check(d.Path.done, "the Colosseum cleared: the path is done")
check(d.Tokens >= tokens + (P.Done.Tokens or 0), "the path's Done reward: tokens (" .. d.Tokens - tokens .. ")")
check(d.Coins >= coins + (steps[3].Reward.Coins or 0) + (P.Done.Coins or 0), "and coins (" .. d.Coins - coins .. ")")
check(me:GetAttribute("PathStep") == nil, "and the usual goals take over (no path step)")
local after = d.Coins
PS.PathEvent(me, "Clear")
PS.PathEvent(me, "Spin")
check(d.Coins == after, "done is done: nothing more")

----------------------------------------------------------------------
-- the save
----------------------------------------------------------------------
do
	Players.PlayerRemoving:Fire(charlie)
	play(1)
	saves.u_1003.Path = { step = 99, done = "yes" }
	Players.PlayerAdded:Fire(charlie)
	play(0.5)
	local c = PS.GetData(charlie)
	check(c and c.Path.step == #steps and c.Path.done == false, "a nonsense saved path is kept in range (" .. tostring(c and c.Path.step) .. ")")
end

----------------------------------------------------------------------
-- DEV: New Player Path
----------------------------------------------------------------------
do
	local ok2, msg = ask("DevPath")
	check(ok2 and d.Path.step == 1 and not d.Path.done, "DEV: the path starts again from step 1 (" .. tostring(msg) .. ")")
end

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
if fails == 0 then
	print("PASS  test_path: who gets it, step by step in order, rewards once, no client push, the save, DEV restart")
else
	print("FAILED: " .. fails)
end
