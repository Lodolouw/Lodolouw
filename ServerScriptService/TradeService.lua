--[[
	TradeService  (ModuleScript, parent: ServerScriptService, name: "TradeService")

	TRADING at the lobby's picnic benches (the numbers: Config.Trade; the
	benches: LobbyBuilder's buildPicnic; the window: TradeClient).

	  * Each bench has two Seats (tagged "TradeSeat", attributes Bench and
	    Side "A" / "B"). Sit on one alone and you're told you're waiting;
	    when two players sit across from each other, a trade opens for both.
	  * Each side puts in up to Config.Trade.MaxSlots weapons (only weapons -
	    never coins or tokens). Not one you're holding, not one the other
	    player already has. Any change takes both ACCEPTs back.
	  * Both ACCEPT: a countdown (Config.Trade.Countdown seconds), then the
	    swap. Standing up, CANCEL, being knocked out, leaving the game or the
	    lobby stops the trade for both, with nothing moved.

	The server decides EVERYTHING here: the screens only ask, through
	PlayerService's Action remote (so every ask gets the same request budget
	and checks as the rest of the game):
	  "TradeOffer"  { trade = id, weapon = id }   put a weapon in
	  "TradeRemove" { trade = id, weapon = id }   take it back out
	  "TradeAccept" { trade = id, on = true/false } press / unpress ACCEPT
	  "TradeCancel" {}                            stop the trade (and stand up)
	The swap checks everything again first, then happens all in one go
	(nothing in it waits, so nothing can sneak in between): both players'
	weapons come out, then go to the other one, at mastery 0.

	The screens are told through the "TradeEvent" RemoteEvent:
	  "State", view         the trade as that player sees it (below: view)
	  "Hint", text or nil   the little line while you sit and wait
	  "Note", text          a short message (a weapon taken out of the trade)
	  "Closed", text        the trade stopped (and why)
	  "Done", got, gave, name   the trade happened: the weapons you got and gave
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local T = Config.Trade
local W = Config.Weapons

local TradeService = {}

local PlayerService, CombatService
local event = nil -- the TradeEvent RemoteEvent
local seats = {} -- [bench number] = { A = seat, B = seat }
local trades = {} -- [bench number] = the trade going on there
local tradeOf = {} -- [player] = the trade they're in
local cooldown = {} -- [player] = os.clock() when they can trade again
local hinted = {} -- [player] = the hint their screen is showing
local blocked = {} -- [bench number] = { a, b }: a trade just stopped with both still sat there
local hooked = setmetatable({}, { __mode = "k" }) -- [player] = true (their signals are joined)
local nextId = 0

local WAITING = "Waiting for someone to sit across from you"

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function send(player, ...)
	if event and player.Parent then
		event:FireClient(player, ...)
	end
end

local function weaponName(id)
	local def = W.List[id]
	return def and def.Name or tostring(id)
end

-- in the lobby: not on a Spire floor, in the Colosseum or in the intro
local function inLobby(player)
	local floor = player:GetAttribute("SpireFloor")
	if floor ~= nil and floor ~= 0 then
		return false
	end
	return not player:GetAttribute("Colosseum") and not player:GetAttribute("Intro")
end

-- the player sitting on a seat (alive), or nil
local function sitter(seat)
	local hum = seat and seat.Occupant
	local char = hum and hum.Parent
	local player = char and Players:GetPlayerFromCharacter(char)
	if player and player.Parent and hum.Health > 0 then
		return player
	end
	return nil
end

local function partnerOf(trade, player)
	return trade.a == player and trade.b or trade.a
end

-- makes a player get up off their seat
local function standUp(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return
	end
	hum.Sit = false
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	hum.Jump = true
end

-- the little waiting line on a player's screen (only sent when it changes)
local function hint(player, text)
	if hinted[player] ~= text then
		hinted[player] = text
		send(player, "Hint", text)
	end
end

-- what one player's screen is shown of a trade
local function view(trade, player)
	local other = partnerOf(trade, player)
	return {
		id = trade.id,
		bench = trade.bench,
		mine = table.clone(trade.offer[player]),
		theirs = table.clone(trade.offer[other]),
		meOk = trade.ok[player] == true,
		themOk = trade.ok[other] == true,
		name = other.DisplayName,
		userId = other.UserId,
		countdown = trade.endsAt and math.max(0, trade.endsAt - os.clock()) or nil,
		max = T.MaxSlots,
	}
end

local function push(trade)
	send(trade.a, "State", view(trade, trade.a))
	send(trade.b, "State", view(trade, trade.b))
end

-- Why a trade can't go on (a message for both), or nil if it's fine
local function problemWith(trade)
	local s = seats[trade.bench]
	for _, p in ipairs({ trade.a, trade.b }) do
		local name = p.DisplayName
		if not p.Parent then
			return name .. " left the game."
		end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return name .. " was knocked out."
		end
		if not inLobby(p) then
			return name .. " left the lobby."
		end
		if not PlayerService.GetData(p) then
			return name .. "'s save isn't ready."
		end
	end
	if not s or sitter(s.A) ~= trade.a then
		return trade.a.DisplayName .. " stood up."
	end
	if sitter(s.B) ~= trade.b then
		return trade.b.DisplayName .. " stood up."
	end
	return nil
end

-- Stops a trade for both, nothing moved. `message`: why (a string, or a
-- function(player) giving each their own words)
local function close(trade, message)
	if trade.closed then
		return
	end
	trade.closed = true
	if trades[trade.bench] == trade then
		trades[trade.bench] = nil
	end
	for _, p in ipairs({ trade.a, trade.b }) do
		if tradeOf[p] == trade then
			tradeOf[p] = nil
		end
		send(p, "Closed", type(message) == "function" and message(p) or message)
	end
	-- (both still sat there: one of them has to get up, or someone new sit
	-- down, before another trade opens - it doesn't just pop open again)
	local s = seats[trade.bench]
	if s and sitter(s.A) == trade.a and sitter(s.B) == trade.b then
		blocked[trade.bench] = { a = trade.a, b = trade.b }
	end
end

-- Opens a trade on a bench, if two players can trade there; and puts the
-- waiting line on the screen of anyone sitting alone
local function tryBench(bench, want)
	local s = seats[bench]
	local a, b = sitter(s.A), sitter(s.B)
	local bl = blocked[bench]
	if bl and (bl.a ~= a or bl.b ~= b) then
		blocked[bench] = nil
		bl = nil
	end
	if trades[bench] then
		return
	end
	if a and not b then
		want[a] = WAITING
		return
	elseif b and not a then
		want[b] = WAITING
		return
	elseif not (a and b) or a == b then
		return
	end
	if bl then
		want[a] = "Stand up and sit down again to trade again"
		want[b] = want[a]
		return
	end
	if tradeOf[a] or tradeOf[b] then
		return -- (never in two trades at once)
	end
	local now = os.clock()
	for _, p in ipairs({ a, b }) do
		if not inLobby(p) then
			want[a], want[b] = "Trading is only in the lobby", "Trading is only in the lobby"
			return
		end
		if cooldown[p] and now < cooldown[p] then
			local text = "You just traded - wait " .. math.ceil(cooldown[p] - now) .. " s"
			if p == a then
				want[a], want[b] = text, a.DisplayName .. " just traded - wait a moment"
			else
				want[b], want[a] = text, b.DisplayName .. " just traded - wait a moment"
			end
			return
		end
		if not PlayerService.GetData(p) then
			return
		end
	end
	nextId = nextId + 1
	local trade = { id = nextId, bench = bench, a = a, b = b, offer = { [a] = {}, [b] = {} }, ok = {}, rev = 0 }
	trades[bench] = trade
	tradeOf[a], tradeOf[b] = trade, trade
	push(trade)
end

-- Looks at every bench and trade: stops any trade that can't go on, opens
-- new ones, and keeps everyone's waiting line right
local function refresh()
	for _, trade in pairs(table.clone(trades)) do
		local problem = problemWith(trade)
		if problem then
			close(trade, problem)
		end
	end
	local want = {}
	for bench in pairs(seats) do
		tryBench(bench, want)
	end
	for p in pairs(tradeOf) do
		want[p] = nil
	end
	for p, text in pairs(want) do
		hint(p, text)
	end
	for p in pairs(table.clone(hinted)) do
		if want[p] == nil then
			hint(p, nil)
		end
	end
end
TradeService.Refresh = refresh -- (for the headless tests)

-- Someone changed an offer: both ACCEPTs (and any countdown) are off
local function changed(trade)
	trade.ok = {}
	trade.endsAt = nil
	trade.rev = trade.rev + 1
	push(trade)
end

----------------------------------------------------------------------
-- The swap
----------------------------------------------------------------------
-- What's wrong with `giver` handing over `list` to `taker`, or nil
local function badGive(giver, gd, list, taker, td)
	local seen = {}
	for _, id in ipairs(list) do
		if seen[id] or not Config.tradeable(id) or gd.Weapons.own[id] == nil then
			return giver.DisplayName .. " doesn't have " .. weaponName(id) .. " any more."
		end
		if td.Weapons.own[id] ~= nil then
			return taker.DisplayName .. " already has " .. weaponName(id) .. "."
		end
		seen[id] = true
	end
	return nil
end

local function finish(trade)
	if trade.closed or trades[trade.bench] ~= trade then
		return
	end
	local problem = problemWith(trade)
	if problem then
		close(trade, problem)
		return
	end
	local a, b = trade.a, trade.b
	local oa, ob = trade.offer[a], trade.offer[b]
	if not (trade.ok[a] and trade.ok[b]) or #oa + #ob == 0 or #oa > T.MaxSlots or #ob > T.MaxSlots then
		changed(trade)
		return
	end
	-- everything checked once more, right before the swap
	local da, db = PlayerService.GetData(a), PlayerService.GetData(b)
	problem = badGive(a, da, oa, b, db) or badGive(b, db, ob, a, da)
	if problem then
		close(trade, "Trade stopped: " .. problem)
		return
	end
	-- THE SWAP, all in one go (nothing in here waits): out of both bags,
	-- then into the other one's, at mastery 0
	trade.closed = true
	trades[trade.bench] = nil
	tradeOf[a], tradeOf[b] = nil, nil
	for _, id in ipairs(oa) do
		da.Weapons.own[id] = nil
	end
	for _, id in ipairs(ob) do
		db.Weapons.own[id] = nil
	end
	for _, id in ipairs(oa) do
		db.Weapons.own[id] = 0
	end
	for _, id in ipairs(ob) do
		da.Weapons.own[id] = 0
	end
	-- (a weapon given away isn't remembered as the one you hold)
	if da.Weapons.hold ~= nil and da.Weapons.own[da.Weapons.hold] == nil then
		da.Weapons.hold = nil
	end
	if db.Weapons.hold ~= nil and db.Weapons.own[db.Weapons.hold] == nil then
		db.Weapons.hold = nil
	end
	local now = os.clock()
	cooldown[a], cooldown[b] = now + T.Cooldown, now + T.Cooldown
	TradeService.swaps = (TradeService.swaps or 0) + 1
	-- after the swap: a weapon given away can't still be in your hand
	for _, p in ipairs({ a, b }) do
		local held = p:GetAttribute("Weapon")
		local d = p == a and da or db
		if held ~= nil and d.Weapons.own[held] == nil then
			if CombatService and CombatService.Equip then
				CombatService.Equip(p, nil)
			else
				p:SetAttribute("Weapon", nil)
			end
		end
	end
	PlayerService.MarkDirty(a)
	PlayerService.MarkDirty(b)
	send(a, "Done", table.clone(ob), table.clone(oa), b.DisplayName)
	send(b, "Done", table.clone(oa), table.clone(ob), a.DisplayName)
	standUp(a)
	standUp(b)
	refresh()
end
TradeService._finish = finish -- (for the headless tests)

----------------------------------------------------------------------
-- What the screens can ask for (each checked here)
----------------------------------------------------------------------
-- The trade a request is about: the one you're in, and the one it names
local function yours(player, arg)
	local trade = tradeOf[player]
	if not trade or trade.closed then
		return nil, "You're not in a trade."
	end
	if type(arg) ~= "table" or arg.trade ~= trade.id then
		return nil, "That trade is over."
	end
	local problem = problemWith(trade)
	if problem then
		close(trade, problem)
		return nil, problem
	end
	return trade
end

local function offer(player, d, arg)
	local trade, why = yours(player, arg)
	if not trade then
		return false, why
	end
	local id = arg.weapon
	if not Config.tradeable(id) then
		return false, "Only weapons can be traded."
	end
	if type(d.Weapons) ~= "table" or d.Weapons.own[id] == nil then
		return false, "You don't have that weapon."
	end
	if player:GetAttribute("Weapon") == id then
		return false, "Put it away first - " .. weaponName(id) .. " is in your hand."
	end
	local list = trade.offer[player]
	if table.find(list, id) then
		return false, "That's already in the trade."
	end
	if #list >= T.MaxSlots then
		return false, "You can put in " .. T.MaxSlots .. " weapons at most."
	end
	local other = partnerOf(trade, player)
	local od = PlayerService.GetData(other)
	if not od then
		return false, "Not ready yet."
	end
	if od.Weapons.own[id] ~= nil then
		return false, other.DisplayName .. " already has " .. weaponName(id) .. "."
	end
	table.insert(list, id)
	changed(trade)
	return true, weaponName(id) .. " is in the trade."
end

local function remove(player, _, arg)
	local trade, why = yours(player, arg)
	if not trade then
		return false, why
	end
	local list = trade.offer[player]
	local at = type(arg.weapon) == "string" and table.find(list, arg.weapon)
	if not at then
		return false, "That's not in the trade."
	end
	table.remove(list, at)
	changed(trade)
	return true, weaponName(arg.weapon) .. " taken back."
end

local function accept(player, _, arg)
	local trade, why = yours(player, arg)
	if not trade then
		return false, why
	end
	if arg.on == false then
		if trade.ok[player] then
			trade.ok[player] = nil
			trade.endsAt = nil
			trade.rev = trade.rev + 1
			push(trade)
		end
		return true, "Not accepted."
	end
	if #trade.offer[trade.a] + #trade.offer[trade.b] == 0 then
		return false, "Put a weapon in the trade first."
	end
	if trade.ok[player] then
		return true, "Accepted."
	end
	trade.ok[player] = true
	trade.rev = trade.rev + 1
	if trade.ok[trade.a] and trade.ok[trade.b] then
		-- both said yes: the countdown (any change before it ends stops it)
		trade.endsAt = os.clock() + T.Countdown
		local rev = trade.rev
		task.delay(T.Countdown, function()
			if trade.rev == rev then
				finish(trade)
			end
		end)
	end
	push(trade)
	return true, "Accepted."
end

local function cancel(player)
	local trade = tradeOf[player]
	if trade then
		close(trade, function(p)
			return p == player and "You cancelled the trade." or player.DisplayName .. " cancelled the trade."
		end)
	end
	standUp(player)
	refresh()
	return true, "Trade cancelled."
end
TradeService._actions = { offer = offer, remove = remove, accept = accept, cancel = cancel } -- (for the headless tests)

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
local function addSeat(seat)
	local bench, side = seat:GetAttribute("Bench"), seat:GetAttribute("Side")
	if not seat:IsA("Seat") or type(bench) ~= "number" or (side ~= "A" and side ~= "B") then
		return
	end
	seats[bench] = seats[bench] or {}
	seats[bench][side] = seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(refresh)
end

-- the weapon in your hand is taken out of the trade (you can't give away
-- what you're holding)
local function onWeapon(player)
	local trade = tradeOf[player]
	local held = player:GetAttribute("Weapon")
	local at = trade and held and table.find(trade.offer[player], held)
	if at then
		table.remove(trade.offer[player], at)
		changed(trade)
		send(player, "Note", weaponName(held) .. " is in your hand, so it came out of the trade.")
	end
end

local function hookPlayer(player)
	if hooked[player] then
		return
	end
	hooked[player] = true
	for _, name in ipairs({ "SpireFloor", "Colosseum", "Intro" }) do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	player:GetAttributeChangedSignal("Weapon"):Connect(function()
		onWeapon(player)
	end)
	local function onCharacter(char)
		local hum = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))
		if hum then
			hum.Died:Connect(refresh)
		end
		refresh()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

local function onLeave(player)
	local trade = tradeOf[player]
	if trade then
		close(trade, player.DisplayName .. " left the game.")
	end
	tradeOf[player] = nil
	cooldown[player] = nil
	hinted[player] = nil
	hooked[player] = nil
	for bench, bl in pairs(blocked) do
		if bl.a == player or bl.b == player then
			blocked[bench] = nil
		end
	end
end

function TradeService.Start(playerService, combatService)
	PlayerService, CombatService = playerService, combatService
	event = ReplicatedStorage:FindFirstChild("TradeEvent")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "TradeEvent"
		event.Parent = ReplicatedStorage
	end
	if PlayerService and PlayerService.AddAction then
		PlayerService.AddAction("TradeOffer", offer)
		PlayerService.AddAction("TradeRemove", remove)
		PlayerService.AddAction("TradeAccept", accept)
		PlayerService.AddAction("TradeCancel", cancel)
	end
	for _, seat in ipairs(CollectionService:GetTagged("TradeSeat")) do
		addSeat(seat)
	end
	CollectionService:GetInstanceAddedSignal("TradeSeat"):Connect(addSeat)
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(onLeave)
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	-- a look round twice a second, in case anything was missed (and so a
	-- trade opens once a cooldown is over)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(refresh)
			if not ok then
				warn("[TradeService] " .. tostring(err))
			end
		end
	end)
end

return TradeService
