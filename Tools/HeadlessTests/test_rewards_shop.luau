--!nocheck
-- Headless test of THE NEW GUI's SERVER SIDE: RewardService (login streak,
-- free gift, codes, update gifts, the Index and collector bar, the community
-- chest, looks, settings, the corner bonuses, boosts) and ShopService (Robux
-- products and their receipts, gifts, game passes, Daily Items, paid random
-- items where they aren't allowed, luck), run for real on a pretend server
-- with three players.
--   * every purchase is handed out EXACTLY ONCE: a receipt Roblox sends again
--     pays nothing, and Roblox is only told "granted" once the save with the
--     purchase in it has been written (a failed save says "not yet")
--   * rewards pay what they say, once; XP and coins are multiplied by the
--     passes, VIP, the boosts and the corner bonuses - and the intro's exact
--     amounts ("raw") aren't
--   * the new save fields start empty and a nonsense save is cleaned up
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame, Random, Enum = M.Instance, M.Vector3, M.CFrame, M.Random, M.Enum
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
-- (Bravo's VIP pass is "made" before the server starts, so joining finds it)
Shop.Passes.VIP.PassId = 901
local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local AS = mount.require(mount.module("ServerScriptService/ArcadeService.lua"))
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
AS.Start(PS, nil)
RS.Start(PS)
SS.Start(PS, RS)
AS.LuckFor = SS.Luck
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
-- The saves
----------------------------------------------------------------------
do
	check(d.Rewards.streak == 0 and d.Rewards.giftPlay >= 0 and next(d.Rewards.codes) == nil, "a new player's rewards start empty")
	check(next(d.Looks.titles) == nil and d.Looks.title == nil, "a new player has no looks")
	check(d.Boosts.XP == 0 and d.Tickets.Revive == 0 and d.Shop.starter == false and #d.Shop.receipts == 0, "no boosts, tickets or purchases")
	check(d.Settings.music == true and d.Settings.hideOthers == false, "the default settings")
	-- Bravo's nonsense, cleaned up
	local r = bd.Rewards
	check(r.streak == #R.Login, "a streak past day 7 is day 7 (got " .. tostring(r.streak) .. ")")
	check(r.giftPlay <= R.GiftMinutes * 60, "the gift clock is never past the gift")
	check(r.codes.LAUNCH == true and r.codes.X == nil and r.codes[5] == nil, "only real used-code marks are kept")
	check(r.index.Nope == nil, "the Index only keeps real weapons")
	check(r.seen == "", "a nonsense 'update seen' is cleared")
	check(bd.Looks.titles.Loyal == true and bd.Looks.titles.Fake == nil, "only real titles are kept")
	check(bd.Looks.title == nil, "a title you don't have can't be worn")
	check(bd.Looks.aura == nil and next(bd.Looks.auras) == nil, "no auras from nonsense")
	check(bd.Boosts.XP == 0 and bd.Boosts.Coins == 0 and bd.Boosts.Luck <= 30 * 24 * 3600, "boosts: no minus, no NaN, no forever")
	check(bd.Tickets.Revive == 2 and bd.Tickets.Rush == 0, "tickets are whole numbers")
	check(bd.Shop.starter == false, "the starter pack is only 'bought' if it's true")
	check(#bd.Shop.receipts == 2, "only real receipt ids are kept")
	check(bd.Shop.daily.day ~= 3, "yesterday's Daily Items are forgotten")
	check(bd.Settings.music == false and bd.Settings.sfx == true and bd.Settings.hack == nil, "settings: only known ones, the right kind")
end

----------------------------------------------------------------------
-- The shop's checks at join: passes and PolicyService
----------------------------------------------------------------------
do
	play(0.2)
	check(bravo:GetAttribute("Pass_VIP") == true and bravo:GetAttribute("VIP") == true, "Bravo's VIP pass is found when they join")
	check(bd.Looks.titles.VIP == true, "VIP comes with the VIP title")
	check(me:GetAttribute("VIP") == nil, "Alpha isn't VIP")
	check(me:GetAttribute("NoPaidRandom") == nil, "Alpha can buy paid random items")
	check(bravo:GetAttribute("NoPaidRandom") == true, "Bravo can't (PolicyService says so)")
	check(charlie:GetAttribute("NoPaidRandom") == true, "Charlie can't either (Roblox couldn't say: play safe)")
end

----------------------------------------------------------------------
-- The login streak
----------------------------------------------------------------------
do
	local coins, tokens = d.Coins, d.Tokens
	local ok, msg = ask("RewardLogin")
	check(ok and d.Rewards.streak == 1 and d.Coins == coins + R.Login[1].Coins, "day 1 pays its coins (" .. tostring(msg) .. ")")
	check(d.Rewards.streakDay == today(), "the claim's day is kept")
	ok = ask("RewardLogin")
	check(not ok and d.Coins == coins + R.Login[1].Coins, "only one claim a day")
	jump(86400)
	ok = ask("RewardLogin")
	check(ok and d.Rewards.streak == 2 and d.Tokens == tokens + R.Login[2].Tokens, "the next day is day 2")
	jump(2 * 86400)
	ok = ask("RewardLogin")
	check(ok and d.Rewards.streak == 1, "a missed day starts the streak again")
	-- days 2..7: day 7 pays the Loyal title (once)
	for day = 2, 7 do
		jump(86400)
		ask("RewardLogin")
		check(d.Rewards.streak == day, "day " .. day)
	end
	check(d.Looks.titles.Loyal == true and d.Rewards.loyal == true, "day 7 pays the Loyal title")
	local t = d.Tokens
	jump(86400)
	ask("RewardLogin")
	check(d.Rewards.streak == 1 and d.Tokens == t, "after day 7 it goes round to day 1 (coins, not tokens)")
end

----------------------------------------------------------------------
-- The free gift
----------------------------------------------------------------------
do
	d.Rewards.giftPlay, d.Rewards.gifts = 0, 0
	local ok = ask("RewardGift")
	check(not ok, "the gift isn't ready at once")
	play(R.GiftMinutes * 60 - 5, 1)
	check(not ask("RewardGift"), "not ready 5 seconds before")
	play(6, 1)
	check(d.Rewards.giftPlay >= R.GiftMinutes * 60, "ready after " .. R.GiftMinutes .. " minutes of play")
	local coins = d.Coins
	ok = ask("RewardGift")
	check(ok and d.Coins == coins + R.Gifts[1].Coins and d.Rewards.giftPlay == 0, "the first gift pays its coins and the clock starts again")
	check(not ask("RewardGift"), "one gift at a time")
	-- the daily limit: the clock stops
	d.Rewards.giftsToday = R.GiftsPerDay
	play(20, 1)
	check(d.Rewards.giftPlay == 0, "after " .. R.GiftsPerDay .. " gifts today the clock stops")
	jump(86400)
	play(3, 1)
	check(d.Rewards.giftsToday == 0 and d.Rewards.giftPlay > 0, "a new day: the clock runs again")
	-- the 4th gift is a boost
	d.Rewards.gifts, d.Rewards.giftPlay = 3, R.GiftMinutes * 60
	ok = ask("RewardGift")
	check(ok and d.Boosts.Coins == R.Gifts[4].Minutes * 60, "the 4th gift is a 2x Coins boost")
end

----------------------------------------------------------------------
-- Codes and update gifts
----------------------------------------------------------------------
do
	local tokens, coins = d.Tokens, d.Coins
	check(not ask("RewardCode", "NOPE"), "a wrong code does nothing")
	check(not ask("RewardCode", 5), "a code has to be words")
	check(not ask("RewardCode", string.rep("A", 40)), "a long code does nothing")
	local ok = ask("RewardCode", " launch ")
	check(ok and d.Tokens == tokens + 3 and d.Coins == coins + 1000, "codes ignore capitals and spaces")
	check(not ask("RewardCode", "LAUNCH") and d.Tokens == tokens + 3, "a code works once")
	check(ask("RewardCode", "walrus") and d.Looks.titles["Walrus Food"] == true, "WALRUS pays its title")
	-- a code that's run out
	R.Codes.OLD = { Coins = 5, Until = 1600000000 }
	check(not ask("RewardCode", "OLD"), "a code past its date doesn't work")
	R.Codes.OLD = nil

	local u = R.Updates[1]
	tokens = d.Tokens
	check(not ask("RewardUpdate", "0.0"), "no such update")
	check(ask("RewardUpdate", u.Id) and d.Tokens == tokens + u.Gift.Tokens, "the update gift pays")
	check(not ask("RewardUpdate", u.Id), "the update gift pays once")
	check(d.Rewards.seen == u.Id, "claiming an update's gift marks it seen")
	check(ask("RewardSeen", u.Id, bravo) and bd.Rewards.seen == u.Id, "an update can be marked seen")
end

----------------------------------------------------------------------
-- The Index, the collector bar, the community chest
----------------------------------------------------------------------
do
	local W = Config.Weapons
	local have, missing = nil, nil
	for id in pairs(W.List) do
		if d.Weapons.own[id] ~= nil then
			have = have or id
		else
			missing = missing or id
		end
	end
	assert(have and missing, "a weapon owned and one not")
	check(not ask("IndexClaim", missing), "a weapon you haven't found can't be claimed")
	check(not ask("IndexClaim", "Nope"), "no such weapon")
	local pay = R.IndexFind[W.List[have].Rarity]
	local coins, tokens = d.Coins, d.Tokens
	check(ask("IndexClaim", have), "a weapon you own can be claimed")
	check(d.Coins == coins + (pay.Coins or 0) and d.Tokens == tokens + (pay.Tokens or 0), "it pays by its rarity")
	check(not ask("IndexClaim", have), "each weapon pays once")

	-- the collector bar: 10 a weapon, 20 a boss beaten
	local n = 0
	for id in pairs(d.Weapons.own) do
		if W.List[id] then
			n += 1
		end
	end
	d.Cleared = {}
	check(RS.CollectorPoints(d) == n * R.CollectorPoints.Weapon, "the collector bar counts weapons")
	local lvl2 = R.CollectorLevel * 1
	local need = lvl2 - RS.CollectorPoints(d)
	if need > 0 then
		check(not ask("CollectorClaim", 2), "collector level 2 needs its points")
		for i = 1, math.ceil(need / R.CollectorPoints.Boss) do
			d.Cleared[i] = 1
		end
	end
	check(Config.collectorLevel(RS.CollectorPoints(d)) >= 2, "bosses beaten fill the bar too")
	tokens = d.Tokens
	check(ask("CollectorClaim", 2) and d.Tokens == tokens + 2, "collector level 2 pays")
	check(not ask("CollectorClaim", 2), "once")
	check(not ask("CollectorClaim", 10), "level 10 is far off")
	check(not ask("CollectorClaim", 4), "there's nothing at level 4")

	-- the community chest
	local ok, msg = ask("GroupClaim")
	check(not ok and string.find(msg, "isn't linked"), "no community linked yet: the chest says so")
	R.GroupId = 555
	ok = ask("GroupClaim")
	check(not ok, "not in the community: nothing")
	groups[1001] = true
	tokens = d.Tokens
	ok = ask("GroupClaim")
	check(ok and d.Tokens == tokens + R.Group.Tokens and d.Looks.titles.Member == true, "in the community: tokens and the Member title")
	check(not ask("GroupClaim"), "the chest pays once")
end

----------------------------------------------------------------------
-- Looks and settings
----------------------------------------------------------------------
do
	check(not ask("WearTitle", "Hoarder"), "a title you don't have can't be worn")
	check(ask("WearTitle", "Loyal") and d.Looks.title == "Loyal", "wearing a title")
	local tag = me.Character.Head:FindFirstChild("LookTitle")
	check(tag ~= nil and tag.Text.Text == "[ Loyal ]", "the title shows over your head")
	check(ask("WearTitle", "") and d.Looks.title == nil, "taking it off")
	check(me.Character.Head:FindFirstChild("LookTitle") == nil, "and it's gone from over your head")
	d.Looks.auras.Rainbow = true
	check(ask("WearAura", "Rainbow") and d.Looks.aura == "Rainbow", "wearing an aura")
	check(me.Character.HumanoidRootPart:FindFirstChild("LookAura") ~= nil, "the aura shows round you")
	check(not ask("WearAura", "Gold"), "an aura you don't have can't be worn")

	check(ask("SaveSettings", { music = false, shake = "x", nope = true }), "saving settings")
	check(d.Settings.music == false and d.Settings.shake == true and d.Settings.nope == nil, "only known settings, the right kind")
	check(not ask("SaveSettings", "x"), "settings have to be a table")
end

----------------------------------------------------------------------
-- The corner bonuses, the passes and boosts on XP and coins
----------------------------------------------------------------------
do
	play(6, 1)
	check(me:GetAttribute("FriendBonus") == R.Friends.PerFriend + Shop.VIP.FriendXP, "Alpha: +5% for Bravo, +10% more as Bravo is VIP (got " .. tostring(me:GetAttribute("FriendBonus")) .. ")")
	check(bravo:GetAttribute("FriendBonus") == R.Friends.PerFriend, "Bravo: +5% for Alpha")
	check(charlie:GetAttribute("FriendBonus") == 0, "Charlie has no friends here")
	local want = math.min(R.Playtime.Max, math.floor(M.now() / (R.Playtime.StepMinutes * 60)) * R.Playtime.PerStep)
	local pb = me:GetAttribute("PlayBonus")
	check(want > 0 and (pb == want or pb == want - R.Playtime.PerStep), "+" .. R.Playtime.PerStep .. "% for every " .. R.Playtime.StepMinutes .. " minutes in the server (got " .. tostring(pb) .. ", want " .. want .. ")")

	local function xp(player, amount, raw)
		local dd = PS.GetData(player)
		local before = dd.Power
		PS.AddPower(player, amount, raw)
		return dd.Power - before
	end
	local function coins(player, amount, raw)
		local dd = PS.GetData(player)
		local before = dd.Coins
		PS.AddCoins(player, amount, raw)
		return dd.Coins - before
	end
	local cb = 1 + (charlie:GetAttribute("PlayBonus") + charlie:GetAttribute("FriendBonus")) / 100
	check(xp(charlie, 100) == math.floor(100 * cb + 0.5), "plain XP gets only the corner bonuses")
	check(xp(charlie, 100, true) == 100, "exact XP (the intro) gets nothing")
	check(coins(charlie, 100) == 100, "coins don't get the corner bonuses")
	charlie:SetAttribute("Pass_DoubleXP", true)
	check(xp(charlie, 100) == math.floor(200 * cb + 0.5), "the 2x XP pass doubles it")
	cd.Boosts.XP = 60
	check(xp(charlie, 100) == math.floor(400 * cb + 0.5), "and a 2x XP boost doubles it again")
	charlie:SetAttribute("Pass_DoubleCoins", true)
	check(coins(charlie, 100) == 200, "the 2x Coins pass")
	check(coins(charlie, 100, true) == 100, "exact coins get nothing")
	local bb = 1 + (bravo:GetAttribute("PlayBonus") + bravo:GetAttribute("FriendBonus")) / 100
	check(xp(bravo, 100) == math.floor(100 * (1 + Shop.VIP.XP) * bb + 0.5), "VIP: +50% XP")
	check(coins(bravo, 100) == math.floor(100 * (1 + Shop.VIP.Coins) + 0.5), "VIP: +25% coins")

	-- boosts run down while you play
	play(61, 1)
	check(cd.Boosts.XP == 0, "a boost runs out")
	check(xp(charlie, 100) == math.floor(200 * cb + 0.5), "and XP is back to the pass only")
	charlie:SetAttribute("Pass_DoubleXP", nil)
	charlie:SetAttribute("Pass_DoubleCoins", nil)
end

----------------------------------------------------------------------
-- Robux products and their receipts
----------------------------------------------------------------------
local PG, NPY = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
do
	check(Marketplace.ProcessReceipt == SS.ProcessReceipt, "the shop takes Roblox's receipts")
	local ok, msg = ask("ShopBuy", "Tokens10")
	check(not ok and msg == "Coming soon!" and #prompts == 0, "a product without an id yet: SOON, no prompt")
	check(not ask("ShopBuy", "Nope"), "no such product")
	-- the products are "made"
	local ids = { Tokens10 = 111, Revive3 = 112, Starter = 113, Rush3 = 114 }
	for key, id in pairs(ids) do
		Shop.Products[key].ProductId = id
		Config.ShopByProductId[id] = key
	end
	ok = ask("ShopBuy", "Tokens10")
	check(ok and #prompts == 1 and prompts[1].player == me and prompts[1].id == 111, "buying shows Roblox's prompt for the product")
	ok, msg = ask("ShopBuy", "Tokens10", bravo)
	check(not ok and #prompts == 1, "no paid random items where they aren't allowed (" .. tostring(msg) .. ")")
	check(ask("ShopBuy", "Revive3", bravo) and #prompts == 2, "but tickets are fine there")

	-- the receipt
	local function receipt(userId, productId, purchaseId)
		local out
		M.task.spawn(function()
			out = SS.ProcessReceipt({ PlayerId = userId, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 99 })
		end)
		play(4, 0.5)
		return out
	end
	local tokens = d.Tokens
	local res = receipt(1001, 111, "P1")
	check(res == PG, "a paid receipt is granted (got " .. tostring(res) .. ")")
	check(d.Tokens == tokens + 10, "it pays the tokens")
	check(table.find(d.Shop.receipts, "P1") ~= nil, "its id is kept")
	check(saves.u_1001 and table.find(saves.u_1001.Shop.receipts, "P1") ~= nil, "and was saved before saying 'granted'")
	check(noticeFor(me, "Thanks!"), "the buyer is thanked")
	res = receipt(1001, 111, "P1")
	check(res == PG and d.Tokens == tokens + 10, "the same receipt again: granted, nothing more paid")

	-- the save fails: paid (once), but Roblox is told "not yet" - and asks again
	broken = true
	res = receipt(1001, 111, "P2")
	check(res == NPY, "a save that fails: not yet granted (got " .. tostring(res) .. ")")
	check(d.Tokens == tokens + 20, "(it's in their bag already)")
	broken = false
	res = receipt(1001, 111, "P2")
	check(res == PG and d.Tokens == tokens + 20, "asked again once saves work: granted, not paid twice")

	check(receipt(1001, 999, "P3") == NPY, "an unknown product: not yet")
	check(receipt(4242, 111, "P4") == NPY, "a buyer who isn't here: not yet (Roblox asks when they're back)")

	-- the starter pack: once
	ok = ask("ShopBuy", "Starter")
	check(ok, "the starter pack can be bought")
	res = receipt(1001, 113, "P5")
	check(res == PG and d.Shop.starter == true and d.Looks.titles.Rookie == true, "the starter pack pays (and its title)")
	ok, msg = ask("ShopBuy", "Starter")
	check(not ok, "the starter pack is once only (" .. tostring(msg) .. ")")

	-- gifts
	check(not ask("ShopBuy", { key = "Revive3", gift = 1001 }), "you can't gift yourself")
	check(not ask("ShopBuy", { key = "Revive3", gift = 4242 }), "you can only gift someone in this server")
	check(not ask("ShopBuy", { key = "Starter", gift = 1003 }), "the starter pack can't be gifted")
	check(not ask("ShopBuy", { key = "Tokens10", gift = 1002 }), "no paid random gifts to where they aren't allowed")
	ok = ask("ShopBuy", { key = "Revive3", gift = 1003 })
	check(ok and prompts[#prompts].player == me and prompts[#prompts].id == 112, "a gift: the buyer gets the prompt")
	local mine, theirs = d.Tickets.Revive, cd.Tickets.Revive
	res = receipt(1001, 112, "P6")
	check(res == PG and cd.Tickets.Revive == theirs + 3 and d.Tickets.Revive == mine, "the friend gets the gift, not the buyer")
	check(noticeFor(charlie, "gifted you") and noticeFor(me, "Gift sent"), "both are told")
	check(table.find(d.Shop.receipts, "P6") ~= nil, "the buyer's save keeps the receipt")
	-- a gift whose friend left before paying: the buyer gets it
	ok = ask("ShopBuy", { key = "Rush3", gift = 1003 })
	check(ok, "another gift")
	local leaving = table.find(M.players, charlie)
	charlie.Parent = nil
	res = receipt(1001, 114, "P7")
	check(res == PG and d.Tickets.Rush == 3, "the friend left: the buyer gets it")
	charlie.Parent = Players
	check(leaving ~= nil, "(Charlie's back)")
end

----------------------------------------------------------------------
-- Game passes
----------------------------------------------------------------------
do
	local ok, msg = ask("ShopPass", "DoubleXP")
	check(not ok and msg == "Coming soon!", "a pass without an id yet: SOON")
	Shop.Passes.DoubleXP.PassId = 902
	Shop.Passes.Luck2.PassId = 903
	ok = ask("ShopPass", "DoubleXP")
	check(ok and passPrompts[#passPrompts].id == 902, "buying a pass shows Roblox's prompt")
	check(not ask("ShopPass", "VIP", bravo), "a pass you have can't be bought again")
	check(not ask("ShopPass", "Luck2", bravo), "no luck passes where paid random items aren't allowed")
	Marketplace.PromptGamePassPurchaseFinished:Fire(me, 902, false)
	check(me:GetAttribute("Pass_DoubleXP") == nil, "a closed prompt gives nothing")
	Marketplace.PromptGamePassPurchaseFinished:Fire(me, 902, true)
	check(me:GetAttribute("Pass_DoubleXP") == true, "a bought pass works at once")
	me:SetAttribute("Pass_DoubleXP", nil)
end

----------------------------------------------------------------------
-- Daily Items
----------------------------------------------------------------------
do
	local items = Config.dailyItems(today())
	check(#items == Shop.Daily.Count, "there are " .. Shop.Daily.Count .. " Daily Items")
	local same = true
	for i, it in ipairs(Config.dailyItems(today())) do
		same = same and it == items[i]
	end
	check(same, "the same items all day, for everyone")
	local item = items[1]
	d.Coins = item.Price - 1
	check(not ask("DailyBuy", 1), "not enough coins")
	d.Coins = item.Price + 10
	check(ask("DailyBuy", 1), "buying a Daily Item")
	local list = item.Kind == "Title" and d.Looks.titles or d.Looks.auras
	check(list[item.Id] == true and d.Coins == 10, "it's yours and it cost its price")
	check(not ask("DailyBuy", 1), "you can't buy one you have")
	check(not ask("DailyBuy", 99), "only what's on sale today")
end

----------------------------------------------------------------------
-- Luck (the Arcade)
----------------------------------------------------------------------
do
	d.Boosts.Luck = 0 -- (the login streak's day 5 gave one)
	check(SS.Luck(me, d) == 1, "no luck without a pass or boost")
	d.Boosts.Luck = 60
	check(SS.Luck(me, d) == Shop.BoostLuck, "the Luck boost")
	me:SetAttribute("Pass_Luck2", true)
	check(SS.Luck(me, d) == 2, "the +100% luck pass (the best one counts)")
	local A = Config.Arcade
	local odds = Config.arcadeOdds(2)
	local total, rare = 0, 0
	for _, r in ipairs(A.Order) do
		total += odds[r]
	end
	check(math.abs(total - 100) < 1e-9, "lucky odds still add up to 100%")
	check(math.abs(odds.Legendary / odds.Common - 2 * A.Odds.Legendary / A.Odds.Common) < 1e-9, "Legendary is twice as likely next to Common")
	check(Config.arcadeOdds(1) == A.Odds, "no luck: the normal odds")
	-- rolls with luck come out at the lucky odds
	local rng = Random.new(3)
	local N, epicPlus = 100000, 0
	for _ = 1, N do
		local r = AS.rollRarity(rng, { spins = 1, pity = {} }, "Slime", odds)
		if r ~= "Common" and r ~= "Rare" then
			epicPlus += 1
		end
	end
	local p = 1 - (odds.Common + odds.Rare) / 100
	local sigma = math.sqrt(p * (1 - p) / N)
	check(math.abs(epicPlus / N - p) < 5 * sigma, string.format("with luck, Epic or better comes up %.2f%% of the time (the odds say %.2f%%)", epicPlus / N * 100, p * 100))
	-- and a real spin uses the player's luck
	local used = nil
	local real = Config.arcadeOdds
	Config.arcadeOdds = function(luck)
		used = luck
		return real(luck)
	end
	d.Tokens = 50
	local okSpin = ask("ArcadeRoll", { machine = "Slime", count = 1 })
	Config.arcadeOdds = real
	check(okSpin and used == 2, "a spin uses your luck (got " .. tostring(used) .. ")")
	me:SetAttribute("Pass_Luck2", nil)
end

if fails == 0 then
	print("PASS  test_rewards_shop: rewards, receipts, gifts, passes, Daily Items, luck")
else
	print("FAILED: " .. fails)
end
