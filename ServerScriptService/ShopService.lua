--[[
	ShopService  (ModuleScript, parent: ServerScriptService, name: "ShopService")

	THE SHOP (Config.Shop), decided and handed out here:
	  * DEVELOPER PRODUCTS (tokens, tickets, boosts, the one-time Starter
	    Pack): the screen asks (ShopBuy), the server checks and shows Roblox's
	    purchase prompt, and Roblox calls ProcessReceipt when it's paid.
	    EVERY PURCHASE IS HANDED OUT EXACTLY ONCE: its PurchaseId is kept in
	    the buyer's save, and Roblox is only told "granted" once that save has
	    been written - if the server dies halfway, Roblox asks again and the
	    kept id stops it being handed out twice.
	  * GIFTS: ShopBuy with a friend's UserId (someone in this server): the
	    buyer pays, the friend gets it (if they've left meanwhile, the buyer does)
	  * GAME PASSES (VIP, 2x XP, 2x Coins, luck, instant x10): checked with
	    Roblox when you join and when you buy one; kept as player attributes
	    ("Pass_DoubleXP" = true, and "VIP")
	  * DAILY ITEMS: looks for coins, a new set every day (DailyBuy)
	  * PAID RANDOM ITEMS: where Roblox doesn't allow them (PolicyService),
	    anything marked Random (tokens, luck) can't be bought - the player
	    attribute "NoPaidRandom" tells the screen to hide them
	  * what XP / coins are multiplied by (VIP, the passes, the timed boosts)

	  ShopService.Luck(player, data)  -> the Arcade's luck for this player (1 = none)
	  ShopService.HasPass(player, key)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ShopService = {}
local PlayerService, RewardService = nil, nil
local S = Config.Shop
local giftFor = {} -- [buyer] = { key, target (UserId), at (os.clock) }
local GIFT_WINDOW = 120 -- seconds a gift choice waits for its purchase

local function notify(player, text, kind)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ev = remotes and remotes:FindFirstChild("Notify")
	if ev and player and player.Parent then
		ev:FireClient(player, text, kind or "good")
	end
end

function ShopService.HasPass(player, key)
	return player:GetAttribute("Pass_" .. key) == true
end

function ShopService.Luck(player, d)
	local luck = 1
	for key, p in pairs(S.Passes) do
		if p.Luck and ShopService.HasPass(player, key) then
			luck = math.max(luck, p.Luck)
		end
	end
	if d and d.Boosts and (d.Boosts.Luck or 0) > 0 then
		luck = math.max(luck, S.BoostLuck or 1.5)
	end
	return luck
end

-- a pass owned: its attribute (and VIP's title)
local function givePass(player, key)
	player:SetAttribute("Pass_" .. key, true)
	if key == "VIP" then
		player:SetAttribute("VIP", true)
		local d = PlayerService.GetData(player)
		if d and S.VIP.Title and Config.Looks.Titles[S.VIP.Title] then
			d.Looks.titles[S.VIP.Title] = true
			PlayerService.MarkDirty(player)
		end
	end
end

local function checkPasses(player)
	for key, p in pairs(S.Passes) do
		if (p.PassId or 0) > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.PassId)
			end)
			if ok and owns then
				givePass(player, key)
			end
		end
	end
end

local function checkPolicy(player)
	local ok, info = pcall(function()
		return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
	end)
	-- (if Roblox can't say, play safe: no paid random items)
	local restricted = (not ok) or (type(info) == "table" and info.ArePaidRandomItemsRestricted == true)
	player:SetAttribute("NoPaidRandom", restricted and true or nil)
end

----------------------------------------------------------------------
-- handing out a product
----------------------------------------------------------------------
local function grant(receiver, key)
	local p = S.Products[key]
	local d = PlayerService.GetData(receiver)
	if not (p and d) then
		return false
	end
	if p.Once then
		d.Shop.starter = true
	end
	if RewardService then
		RewardService.Pay(receiver, p, nil)
	end
	PlayerService.MarkDirty(receiver)
	return true
end

-- Roblox calls this once a product is paid for (again and again until it's
-- told PurchaseGranted)
local function processReceipt(info)
	local buyer = Players:GetPlayerByUserId(info.PlayerId)
	local key = Config.ShopByProductId[info.ProductId]
	if not buyer or not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = PlayerService.GetData(buyer)
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(info.PurchaseId)
	if table.find(d.Shop.receipts, id) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- (handed out already)
	end
	-- a gift? (chosen in the last couple of minutes, for this product, and
	-- the friend is still here)
	local receiver = buyer
	local g = giftFor[buyer]
	if g and g.key == key and os.clock() - g.at < GIFT_WINDOW then
		local friend = Players:GetPlayerByUserId(g.target)
		if friend and PlayerService.GetData(friend) then
			receiver = friend
		end
		giftFor[buyer] = nil
	end
	if not grant(receiver, key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(d.Shop.receipts, id)
	while #d.Shop.receipts > 50 do
		table.remove(d.Shop.receipts, 1)
	end
	local p = S.Products[key]
	if receiver ~= buyer then
		notify(receiver, buyer.DisplayName .. " gifted you " .. p.Name .. "! " .. Config.rewardText(p), "rare")
		notify(buyer, "Gift sent to " .. receiver.DisplayName .. "!", "good")
		PlayerService.SaveNow(receiver)
	else
		notify(buyer, "Thanks! " .. Config.rewardText(p), "rare")
	end
	-- (only "granted" once the save with the purchase in it is written)
	if PlayerService.SaveNow(buyer) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
ShopService.ProcessReceipt = processReceipt -- (the tests call it)

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
-- ShopBuy: arg = key, or { key, gift = UserId }
local function buy(player, d, arg)
	local key, target = arg, nil
	if type(arg) == "table" then
		key, target = arg.key, tonumber(arg.gift)
	end
	local p = type(key) == "string" and S.Products[key]
	if not p then
		return false, "There's no such thing in the shop."
	end
	if (p.ProductId or 0) <= 0 then
		return false, "Coming soon!"
	end
	if p.Random and player:GetAttribute("NoPaidRandom") then
		return false, "This can't be bought where you live."
	end
	if p.Once and d.Shop.starter and not target then
		return false, "You already have the Starter Pack!"
	end
	if target then
		local friend = Players:GetPlayerByUserId(target)
		if not p.Gift or not friend or friend == player then
			return false, "Pick someone in this server to gift it to."
		end
		if p.Random and friend:GetAttribute("NoPaidRandom") then
			return false, "That can't be gifted to them."
		end
		giftFor[player] = { key = key, target = target, at = os.clock() }
	else
		giftFor[player] = nil
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, p.ProductId)
	end)
	return ok, ok and nil or "The shop couldn't open - try again."
end

local function buyPass(player, d, key)
	local p = type(key) == "string" and S.Passes[key]
	if not p then
		return false, "There's no such pass."
	end
	if (p.PassId or 0) <= 0 then
		return false, "Coming soon!"
	end
	if ShopService.HasPass(player, key) then
		return false, "You already have it!"
	end
	if p.Random and player:GetAttribute("NoPaidRandom") then
		return false, "This can't be bought where you live."
	end
	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, p.PassId)
	end)
	return ok, ok and nil or "The shop couldn't open - try again."
end

local function buyDaily(player, d, arg)
	local today = Config.questDay()
	local items = Config.dailyItems(today)
	local i = tonumber(arg)
	local item = i and items[i]
	if not item then
		return false, "That's not on sale today."
	end
	if d.Shop.daily.day ~= today then
		d.Shop.daily = { day = today, bought = {} }
	end
	local list = item.Kind == "Title" and d.Looks.titles or d.Looks.auras
	if list[item.Id] then
		return false, "You already have it!"
	end
	if (d.Coins or 0) < item.Price then
		return false, "Not enough coins yet."
	end
	d.Coins = d.Coins - item.Price
	list[item.Id] = true
	d.Shop.daily.bought[item.Kind .. ":" .. item.Id] = true
	return true, "Bought: " .. item.Id .. (item.Kind == "Title" and " title" or " aura") .. "! Wear it from your Bag."
end

----------------------------------------------------------------------
function ShopService.Start(playerService, rewardService)
	PlayerService, RewardService = playerService, rewardService
	PlayerService.AddAction("ShopBuy", buy)
	PlayerService.AddAction("ShopPass", buyPass)
	PlayerService.AddAction("DailyBuy", function(player, d, arg)
		local ok, msg = buyDaily(player, d, arg)
		if ok then
			PlayerService.MarkDirty(player)
		end
		return ok, msg
	end)
	-- XP and coins: VIP, the 2x passes, the timed boosts
	PlayerService.AddGainHook(function(player, d, kind, amount)
		local m = 1
		if kind == "Power" then
			if ShopService.HasPass(player, "VIP") then
				m = m * (1 + S.VIP.XP)
			end
			if ShopService.HasPass(player, "DoubleXP") then
				m = m * 2
			end
			if (d.Boosts.XP or 0) > 0 then
				m = m * 2
			end
		elseif kind == "Coins" then
			if ShopService.HasPass(player, "VIP") then
				m = m * (1 + S.VIP.Coins)
			end
			if ShopService.HasPass(player, "DoubleCoins") then
				m = m * 2
			end
			if (d.Boosts.Coins or 0) > 0 then
				m = m * 2
			end
		end
		return amount * m
	end)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, p in pairs(S.Passes) do
			if p.PassId == passId then
				givePass(player, key)
				notify(player, "Thanks! " .. p.Name .. " is yours.", "rare")
			end
		end
	end)
	local function added(player)
		task.spawn(checkPasses, player)
		task.spawn(checkPolicy, player)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in ipairs(Players:GetPlayers()) do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		giftFor[player] = nil
	end)
end

return ShopService
