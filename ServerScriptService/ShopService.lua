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

	  * TICKETS in fights: ShopService.Revive (CombatService asks when a hit
	    would finish you in a boss fight) and ShopService.Rush (BossService asks
	    when you win against a boss you'd beaten before)

	  ShopService.Luck(player, data)  -> the Arcade's luck for this player (1 = none),
	                                     also kept as the player attribute "Luck"
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
local revived = {} -- [player] = revives used in this fight
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

----------------------------------------------------------------------
-- tickets in fights
----------------------------------------------------------------------
-- A hit is about to finish `player` in a boss fight: use a REVIVE ticket?
-- (only if they have one, haven't switched them off, and haven't used this
-- fight's). True if one was used - CombatService stands them back up.
function ShopService.Revive(player)
	local d = PlayerService and PlayerService.GetData(player)
	if not d or player:GetAttribute("SpireFloor") == nil then
		return false
	end
	if d.Settings.revives == false or (d.Tickets.Revive or 0) <= 0 then
		return false
	end
	if (revived[player] or 0) >= (S.RevivesPerFight or 1) then
		return false
	end
	revived[player] = (revived[player] or 0) + 1
	d.Tickets.Revive = d.Tickets.Revive - 1
	PlayerService.MarkDirty(player)
	local left = d.Tickets.Revive
	notify(player, "REVIVED! (" .. left .. (left == 1 and " revive" or " revives") .. " left)", "rare")
	return true
end

-- `player` beat the boss on `floor` again: use a BOSS RUSH ticket? Returns
-- what the win's rewards are multiplied by (1 = no ticket used).
function ShopService.Rush(player, floor)
	local d = PlayerService and PlayerService.GetData(player)
	if not d or d.Settings.rush == false or (d.Tickets.Rush or 0) <= 0 then
		return 1
	end
	d.Tickets.Rush = d.Tickets.Rush - 1
	PlayerService.MarkDirty(player)
	local m = S.RushMultiplier or 2
	notify(player, "BOSS RUSH! Rewards x" .. m .. " (" .. d.Tickets.Rush .. " left)", "rare")
	return m
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
		if d.Shop.starter then
			-- (a once-only pack bought again - a client can prompt any product
			-- itself: they paid, so they get its worth in tokens instead)
			p = { Tokens = p.Tokens or 0, Coins = p.Coins }
		end
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
	local p = S.Products[key]
	local function keep()
		table.insert(d.Shop.receipts, id)
		while #d.Shop.receipts > 50 do
			table.remove(d.Shop.receipts, 1)
		end
	end
	local function forget()
		local at = table.find(d.Shop.receipts, id)
		if at then
			table.remove(d.Shop.receipts, at)
		end
	end
	if receiver ~= buyer then
		-- A GIFT: the receipt lives in the buyer's save, so that's written
		-- FIRST - only then does the friend get it. (Granting first and then
		-- failing to save the buyer would let Roblox send the receipt again
		-- later, in a server where the gift is forgotten: paid once, granted
		-- twice.)
		keep()
		if not PlayerService.SaveNow(buyer) then
			forget()
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local okGrant, granted = pcall(grant, receiver, key)
		if not (okGrant and granted) then
			grant(buyer, key) -- (the friend left meanwhile: the buyer has it)
			PlayerService.SaveNow(buyer)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		notify(receiver, buyer.DisplayName .. " gifted you " .. p.Name .. "! " .. Config.rewardText(p), "rare")
		notify(buyer, "Gift sent to " .. receiver.DisplayName .. "!", "good")
		PlayerService.SaveNow(receiver)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- For yourself: the receipt is kept BEFORE anything is handed out, so a
	-- second copy of the same receipt (Roblox retries) finds it and stops.
	keep()
	local okGrant, granted = pcall(grant, buyer, key)
	if not okGrant then
		-- (it broke part-way: it may already have paid, so the receipt stays -
		-- never risk paying twice; the error is logged for a look)
		warn("[ShopService] grant failed after the receipt was kept: " .. tostring(granted))
	elseif not granted then
		forget() -- (nothing was handed out: let Roblox try again)
		return Enum.ProductPurchaseDecision.NotProcessedYet
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
	if ok then
		return true
	end
	return false, "The shop couldn't open - try again."
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
	if ok then
		return true
	end
	return false, "The shop couldn't open - try again."
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
		-- (this event alone isn't proof - Roblox is asked whether they really
		-- own it before anything is given, a few times while the sale settles)
		for key, p in pairs(S.Passes) do
			if p.PassId == passId and (p.PassId or 0) > 0 then
				task.spawn(function()
					for _ = 1, 5 do
						local ok, owns = pcall(function()
							return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
						end)
						if not player.Parent then
							return
						end
						if ok and owns then
							givePass(player, key)
							notify(player, "Thanks! " .. p.Name .. " is yours.", "rare")
							return
						end
						task.wait(2)
					end
				end)
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
		revived[player] = nil
	end)
	-- a new fight: its revive can be used again
	local function watchFights(player)
		player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
			revived[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(watchFights)
	for _, p in ipairs(Players:GetPlayers()) do
		watchFights(p)
	end
	-- the Arcade's luck, on each player (the Arcade's screen shows its odds)
	task.spawn(function()
		while true do
			for _, p in ipairs(Players:GetPlayers()) do
				local luck = ShopService.Luck(p, PlayerService.GetData(p))
				if p:GetAttribute("Luck") ~= luck then
					p:SetAttribute("Luck", luck)
				end
			end
			task.wait(1)
		end
	end)
end

return ShopService
