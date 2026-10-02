--!nocheck
-- Headless SECURITY test of the economy, run like an exploiter would: the
-- real PlayerService, RewardService, ShopService and ArcadeService on a
-- pretend server, poked with requests a modified client can send.
--   * the community chest can't be claimed twice by firing claims in
--     parallel (IsInGroup waits on Roblox), and the Action remote runs one
--     action per player at a time
--   * no NaN / infinite / negative amount ever reaches coins, tokens or power
--   * a purchase whose payout breaks part-way is never paid twice when
--     Roblox sends the receipt again; a once-only pack bought again (any
--     client can prompt any product) gives its worth, not a second pack
--   * Index rewards and collector points count only weapons you found
--     yourself, not ones traded to you; starter weapons can't be traded
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


----------------------------------------------------------------------
-- 1. The community chest, raced
----------------------------------------------------------------------
do
	R.GroupId = 777
	groups[me.UserId] = true
	-- (asking Roblox takes a moment - the first ask for a player waits on the web)
	me.IsInGroup = function(self, g)
		task.wait(0.4)
		return groups[self.UserId] == true
	end
	local tokens = d.Tokens
	local answers = {}
	play(0.5) -- (a full request budget)
	for i = 1, 15 do
		task.spawn(function()
			answers[i] = { Action.OnServerInvoke(me, "GroupClaim") }
		end)
	end
	play(1.5)
	local yes, busy = 0, 0
	for i = 1, 15 do
		local a = answers[i]
		if a and a[1] == true then
			yes += 1
		elseif a and tostring(a[2]) == "One thing at a time!" then
			busy += 1
		end
	end
	check(yes == 1, "15 claims fired at once: paid exactly once (" .. yes .. ")")
	check(busy >= 1, "the others are turned away while it runs (" .. busy .. ")")
	check(d.Tokens == tokens + (R.Group.Tokens or 0), "the chest's tokens once (" .. d.Tokens - tokens .. ")")
	local ok = ask("GroupClaim")
	check(not ok, "and never again")
end

----------------------------------------------------------------------
-- 2. Numbers that aren't numbers
----------------------------------------------------------------------
do
	local coins, power, tokens = d.Coins, d.Power, d.Tokens
	PS.AddCoins(me, 0 / 0)
	PS.AddCoins(me, math.huge)
	PS.AddCoins(me, -math.huge)
	check(d.Coins == coins, "NaN / infinite coins are refused (" .. tostring(d.Coins) .. ")")
	PS.AddCoins(me, -1e12, true)
	check(d.Coins == 0, "coins never go below 0 (" .. tostring(d.Coins) .. ")")
	d.Coins = coins
	PS.AddPower(me, 0 / 0)
	PS.AddPower(me, math.huge)
	check(d.Power == power, "NaN / infinite power is refused")
	PS.AddTokens(me, math.huge)
	PS.AddTokens(me, 0 / 0)
	PS.AddTokens(me, -5)
	check(d.Tokens == tokens, "NaN / infinite / negative tokens are refused (" .. tostring(d.Tokens) .. ")")
	-- a gain hook that goes wrong can't poison the amount either
	PS.AddGainHook(function()
		return 0 / 0
	end)
	PS.AddCoins(me, 10)
	check(d.Coins == coins + 10 or d.Coins > coins, "a broken gain hook is ignored (" .. tostring(d.Coins) .. ")")
	check(d.Coins == d.Coins, "and coins are still a real number")
	local ok = ask("DevSetLevel", "nan")
	check(d.Power == d.Power, "\"nan\" for a level can't make power NaN")
end

----------------------------------------------------------------------
-- 3. Receipts: a payout that breaks part-way, and once-only packs
----------------------------------------------------------------------
do
	Shop.Products.Tokens10.ProductId = 4001
	Config.ShopByProductId[4001] = "Tokens10"
	local tokens = d.Tokens
	-- the looks refresh breaking (a player deleting their own title) mustn't
	-- make a paid purchase look unpaid
	local real = RS.RefreshLooks
	RS.RefreshLooks = function()
		error("their title's parts are gone (pretend)")
	end
	local r1 = SS.ProcessReceipt({ PlayerId = me.UserId, ProductId = 4001, PurchaseId = "sec-1", CurrencySpent = 99 })
	local r2 = SS.ProcessReceipt({ PlayerId = me.UserId, ProductId = 4001, PurchaseId = "sec-1", CurrencySpent = 99 })
	RS.RefreshLooks = real
	check(d.Tokens == tokens + 10, "a pack whose looks refresh breaks still pays once (" .. d.Tokens - tokens .. ")")
	check(r1 == Enum.ProductPurchaseDecision.PurchaseGranted, "and is granted")
	check(r2 == Enum.ProductPurchaseDecision.PurchaseGranted and d.Tokens == tokens + 10, "the same receipt again pays nothing")
	-- the Starter Pack, prompted again by a client (it's once only)
	Shop.Products.Starter.ProductId = 4002
	Config.ShopByProductId[4002] = "Starter"
	d.Shop.starter = true
	local before = d.Tokens
	local titles = d.Looks.titles.Rookie
	SS.ProcessReceipt({ PlayerId = me.UserId, ProductId = 4002, PurchaseId = "sec-2", CurrencySpent = 49 })
	check(d.Tokens == before + (Shop.Products.Starter.Tokens or 0), "a second Starter Pack gives its tokens' worth")
	check((d.Tickets.Revive or 0) >= 0 and d.Looks.titles.Rookie == titles, "but not the pack again (no title)")
end

----------------------------------------------------------------------
-- 4. Weapons: Index rewards only for weapons you found yourself
----------------------------------------------------------------------
do
	local W = Config.Weapons
	check(not Config.tradeable("IronSword"), "the starter sword can't be traded (everyone gets it back)")
	local id
	for k, def in pairs(W.List) do
		if def.Rarity == "Epic" and not table.find(W.Starters or {}, k) then
			id = k
			break
		end
	end
	assert(id, "an Epic weapon to test with")
	-- traded to Charlie (in the trade the server swaps own, never found)
	cd.Weapons.own[id] = 0
	local tokens = cd.Tokens
	local ok, msg = ask("IndexClaim", id, charlie)
	check(not ok and string.find(tostring(msg), "find yourself"), "a traded weapon's Index reward can't be claimed (" .. tostring(msg) .. ")")
	check(cd.Tokens == tokens, "and pays nothing")
	local pts = RS.CollectorPoints(cd)
	cd.Weapons.found[id] = true -- (now Charlie wins it at the Arcade too)
	check(RS.CollectorPoints(cd) > pts, "a weapon found yourself fills the collector bar; a traded one doesn't")
	ok = ask("IndexClaim", id, charlie)
	check(ok, "found yourself: the Index reward is yours")
end

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
if fails == 0 then
	print("PASS  test_security_economy: chest race, one action at a time, bad numbers, receipts, once-only packs, found weapons")
else
	print("FAILED: " .. fails)
end
