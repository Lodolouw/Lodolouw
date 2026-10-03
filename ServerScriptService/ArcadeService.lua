--[[
	ArcadeService  (ModuleScript, parent: ServerScriptService, name: "ArcadeService")

	THE ARCADE's spins, decided here on the server (the numbers: Config.Arcade;
	the building: ArcadeBuilder; the show on your screen: ArcadeClient).

	The "ArcadeRoll" action (through PlayerService's Action remote, so it gets
	the same request budget and checks): { machine = "Slime", count = 1 or 10 }.
	It checks that the machine is open to you, that you're in the lobby (not
	in a fight, the Spire or the intro) and that you can pay; takes the tokens;
	picks each result by the odds - your very first spin is Rare or better,
	and a Legendary or better is guaranteed within Config.Arcade.Pity spins on
	a machine; gives you each new weapon, or mastery for one you own (coins
	once it's at mastery 100 - never a token back, so a spin always costs); and answers with what you got. Your screen
	then plays the spin, which only SHOWS the result it was given.

	The "ArcadeExchange" action: THE COIN EXCHANGE - coins for a token, once
	every Config.Arcade.Exchange.Hours, at Config.exchangePrice (it grows
	with your best Spire floor). The time you last traded is saved
	(Arcade.exchanged, os.time()).

	Everyone's screen is told too (the "ArcadeEvent" RemoteEvent: "Roll",
	userId, name, machine, { {id, rarity}, ... }), so that machine lights up
	for the whole lobby and a Secret gets a banner. The server's latest
	Legendary-or-better spins are kept on the same RemoteEvent (its "BigWins"
	attribute: "name|rarity|weapon;..." newest first) for the BIG WINS board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local A = Config.Arcade
local W = Config.Weapons

local ArcadeService = {}
ArcadeService.rng = Random.new() -- (the headless tests give it a seed)

local PlayerService, CombatService
local event = nil -- the ArcadeEvent RemoteEvent
local last = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() of their last spin
local bigWins = {} -- the BIG WINS board's lines, newest first ("name|rarity|weapon")
local BIG_WINS = 5

local function isIn(list, rarity)
	for _, r in ipairs(list) do
		if r == rarity then
			return true
		end
	end
	return false
end

-- one rarity from `list`, weighted by `odds` (Config.Arcade.Odds, or the
-- player's lucky odds: Config.arcadeOdds)
local function pickFrom(rng, list, odds)
	odds = odds or A.Odds
	local total = 0
	for _, r in ipairs(list) do
		total = total + (odds[r] or 0)
	end
	local x = rng:NextNumber() * total
	for _, r in ipairs(list) do
		x = x - (odds[r] or 0)
		if x < 0 then
			return r
		end
	end
	return list[#list]
end

-- One spin's rarity on `machineId`, for a player whose Arcade counters are
-- `arcade` ({ spins, pity = { [machine] = spins since a Legendary+ } }) -
-- which it moves on. The first spin ever is Rare or better; the spin that
-- reaches the pity is a Legendary or better. `odds` (optional) are the
-- player's odds with their luck in (Config.arcadeOdds).
function ArcadeService.rollRarity(rng, arcade, machineId, odds)
	arcade.pity = arcade.pity or {}
	local pity = arcade.pity[machineId] or 0
	local rarity
	if (arcade.spins or 0) == 0 then
		rarity = pickFrom(rng, A.FirstSpin, odds)
	elseif pity + 1 >= A.Pity then
		rarity = pickFrom(rng, A.PityRarities, odds)
	else
		rarity = pickFrom(rng, A.Order, odds)
	end
	arcade.spins = (arcade.spins or 0) + 1
	arcade.pity[machineId] = isIn(A.PityRarities, rarity) and 0 or pity + 1
	return rarity
end

-- in the lobby: not on a Spire floor, in the Colosseum or in the intro
local function inLobby(player)
	local floor = player:GetAttribute("SpireFloor")
	if floor ~= nil and floor ~= 0 then
		return false
	end
	return not player:GetAttribute("Colosseum") and not player:GetAttribute("Intro")
end

-- The weapon goes in the player's bag - or, if they have it, its mastery goes up
local function give(player, d, id, rarity)
	local own = d.Weapons.own
	d.Weapons.found = d.Weapons.found or {}
	d.Weapons.found[id] = true -- (found it yourself: it counts for the Index)
	if own[id] == nil then
		own[id] = 0
		return { id = id, rarity = rarity, new = true }
	end
	local max = Config.masteryPointsFor(W.MasteryMax)
	if own[id] >= max then
		-- (nothing left to learn: coins instead - roll, below)
		return { id = id, rarity = rarity, maxed = true }
	end
	local points = A.Duplicate[rarity] or 0
	own[id] = math.min(max, own[id] + points)
	-- (the card on their screen shows the new level if it's in their hand; the
	-- "MASTERY 12!" pop-up isn't used - it would give the spin away)
	if player:GetAttribute("Weapon") == id and CombatService and CombatService.ShowMastery then
		CombatService.ShowMastery(player, id)
	end
	return { id = id, rarity = rarity, mastery = points }
end

-- a Legendary or better goes up on the BIG WINS board
local function boardWin(player, id, rarity)
	if not isIn(A.PityRarities, rarity) then
		return
	end
	local name = string.gsub(tostring(player.DisplayName), "[|;]", "")
	table.insert(bigWins, 1, name .. "|" .. rarity .. "|" .. id)
	while #bigWins > BIG_WINS do
		table.remove(bigWins)
	end
	if event then
		event:SetAttribute("BigWins", table.concat(bigWins, ";"))
	end
end

local function roll(player, d, arg)
	local machineId = type(arg) == "table" and arg.machine or nil
	local count = type(arg) == "table" and arg.count or nil
	local machine = type(machineId) == "string" and A.Machines[machineId]
	if not machine then
		return false, "There's no such machine."
	end
	if count ~= 1 and count ~= 10 then
		return false, "You can spin 1 or 10 at a time."
	end
	local open, why = Config.arcadeOpen(d, machineId)
	if not open then
		return false, why
	end
	if not inLobby(player) then
		return false, "Go to the Arcade in the lobby to spin!"
	end
	local now = os.clock()
	if last[player] and now - last[player] < A.Gap then
		return false, "One spin at a time!"
	end
	local price = count == 10 and machine.Ten or machine.Price
	if (d.Tokens or 0) < price then
		return false, "Not enough tokens - that's " .. price .. (price == 1 and " token." or " tokens.")
	end
	last[player] = now
	d.Tokens = d.Tokens - price
	d.Arcade = type(d.Arcade) == "table" and d.Arcade or { spins = 0, pity = {} }
	-- (luck: a luck pass or the Luck boost - the machine's screen shows these odds)
	local luck = ArcadeService.LuckFor and ArcadeService.LuckFor(player, d) or 1
	local odds = Config.arcadeOdds(luck)
	local results, shown = {}, {}
	for i = 1, count do
		local rarity = ArcadeService.rollRarity(ArcadeService.rng, d.Arcade, machineId, odds)
		local id = Config.arcadeWeapon(machineId, rarity)
		if id then
			results[#results + 1] = give(player, d, id, rarity)
			shown[#shown + 1] = { id = id, rarity = rarity }
			boardWin(player, id, rarity)
		end
	end
	-- a weapon already mastered pays coins (more for rarer ones and dearer
	-- machines) - never a token back: a token back made spins free once
	-- everything was mastered
	for _, r in ipairs(results) do
		if r.maxed then
			r.coins = (A.MaxedCoins[r.rarity] or 0) * machine.Price
			d.Coins = (d.Coins or 0) + r.coins
		end
	end
	if PlayerService and PlayerService.MarkDirty then
		PlayerService.MarkDirty(player)
	end
	if event then
		event:FireAllClients("Roll", player.UserId, player.DisplayName, machineId, shown)
	end
	-- the new player path's first spin: the best weapon it won goes straight
	-- into their hand (if they're holding nothing yet) - no hunting through
	-- the bag before the first fight
	local P = d.Path
	local step = P and not P.done and Config.Path and Config.Path.Steps[P.step]
	if step and step.Id == "Spin" and player:GetAttribute("Weapon") == nil and CombatService and CombatService.Equip then
		local order = (Config.Arcade and Config.Arcade.Order) or {}
		local best, bestRank = nil, -1
		for _, r in ipairs(shown) do
			local def = W.List[r.id]
			local rank = table.find(order, r.rarity) or 0
			if def and W.Types[def.Type] and rank > bestRank then
				best, bestRank = r.id, rank
			end
		end
		if best then
			CombatService.Equip(player, best)
			local notify = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Notify")
			if notify then
				notify:FireClient(player, "You're holding your new " .. W.List[best].Name .. "! (Swap any time in your BAG.)", "rare")
			end
		end
	end
	if PlayerService and PlayerService.PathEvent then
		task.defer(PlayerService.PathEvent, player, "Spin") -- (the new player path's first step)
	end
	if PlayerService and PlayerService.AwardBadge then
		PlayerService.AwardBadge(player, "FirstSpin")
	end
	return true, {
		machine = machineId,
		results = results,
		tokens = d.Tokens,
		pity = d.Arcade.pity[machineId] or 0,
		spins = d.Arcade.spins,
	}
end
ArcadeService._roll = roll -- (for the headless tests)

-- THE COIN EXCHANGE: coins for a token, once every few hours, at a price that
-- grows with your best Spire floor (Config.Arcade.Exchange)
ArcadeService.now = os.time -- (the headless tests move the clock)
local function exchange(player, d)
	local X = A.Exchange
	if not X then
		return false, "The exchange is closed."
	end
	d.Arcade = type(d.Arcade) == "table" and d.Arcade or { spins = 0, pity = {} }
	local now = ArcadeService.now()
	local wait = Config.exchangeWait(d, now)
	if wait > 0 then
		local h, m = math.floor(wait / 3600), math.ceil((wait % 3600) / 60)
		if m == 60 then
			h, m = h + 1, 0
		end
		return false, "The exchange is recharging - ready in " .. (h > 0 and (h .. "h " .. m .. "m") or (m .. "m")) .. "."
	end
	local price = Config.exchangePrice(d)
	if (d.Coins or 0) < price then
		return false, "Not enough coins yet - that's " .. Config.format(price) .. " coins."
	end
	d.Coins = d.Coins - price
	d.Tokens = (d.Tokens or 0) + X.Tokens
	d.Arcade.exchanged = now
	if PlayerService and PlayerService.MarkDirty then
		PlayerService.MarkDirty(player)
	end
	return true, {
		tokens = d.Tokens,
		coins = d.Coins,
		price = price,
		wait = X.Hours * 3600,
	}
end
ArcadeService._exchange = exchange -- (for the headless tests)

function ArcadeService.Start(playerService, combatService)
	PlayerService, CombatService = playerService, combatService
	event = ReplicatedStorage:FindFirstChild("ArcadeEvent")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "ArcadeEvent"
		event.Parent = ReplicatedStorage
	end
	if PlayerService and PlayerService.AddAction then
		PlayerService.AddAction("ArcadeRoll", roll)
		PlayerService.AddAction("ArcadeExchange", exchange)
	end
end

return ArcadeService
