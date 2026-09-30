--!nocheck
-- Headless test of TRADING at the lobby's picnic benches: the real lobby
-- (LobbyBuilder's benches with their Seats), the real server (PlayerService,
-- CombatService, TradeService) and the real window on Alpha's screen
-- (TradeClient), with four pretend players.
--   * the benches: two, each with two real Seats (tagged, Bench and Side,
--     facing the table)
--   * sitting alone: the waiting line; two across from each other: a trade
--     opens for both
--   * offers: put in and taken out, the partner sees them; what's refused
--     (not a weapon, not yours, in your hand, the partner has it, twice, a
--     5th one, not in a trade, an old trade); a weapon picked up while it's
--     in the trade comes out of it
--   * ACCEPT: the other side sees it; a change takes both back; both: the
--     countdown, and a change in it stops it; at the end the swap happens
--     exactly once (the weapons move, at mastery 0, both saves sent), both
--     stand up, "Trade complete!"; then a cooldown
--   * standing up, CANCEL, being knocked out, leaving the lobby or the game
--     stop the trade with nothing moved; nobody is ever in two trades;
--     requests fired over and over can't copy a weapon
--   * the window (Alpha's screen): opens with both names, the weapon grid,
--     tapping a weapon / a slot / ACCEPT / CANCEL asks the server the right
--     thing, the countdown, the partner's side changing, the result window
local SNAPS = ({ ... })[1] == "snaps" -- (luau test_trade.luau -a snaps: also prints the window for render_gui.py)
local snapGui = SNAPS and require("./gui_snap") or nil
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage
local CollectionService = M.services.CollectionService
local workspace = M.workspace

RunService.IsStudio = function()
	return true
end
M.game.BindToClose = function() end
M.services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
}
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
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
	local pg = Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = p
	p.Parent = Players
	table.insert(M.players, p)
	return p, hum
end
local alpha, aHum = newPlayer("Alpha", 1001, Vector3.new(60, 3.55, 20))
local bravo, bHum = newPlayer("Bravo", 1002, Vector3.new(62, 3.55, 20))
local charlie, cHum = newPlayer("Charlie", 1003, Vector3.new(64, 3.55, 20))
local delta, dHum = newPlayer("Delta", 1004, Vector3.new(66, 3.55, 20))
Players.LocalPlayer = alpha
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- what the server tells each screen (and Alpha's screen really gets it)
local events = {} -- [player] = { { kind, a, b, c }, ... }
local invokes = {}
M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	if remote.Name == "TradeEvent" and target then
		events[target] = events[target] or {}
		table.insert(events[target], a)
	end
	M.task.defer(function()
		if target == alpha or target == nil then
			remote.OnClientEvent:Fire(table.unpack(a, 1, a.n))
		end
	end)
end
M.onInvokeServer = function(remote, name, arg)
	table.insert(invokes, { name = name, arg = arg })
	return remote.OnServerInvoke(alpha, name, arg)
end
M.onFireServer = function(remote, ...)
	local a = table.pack(...)
	M.task.defer(function()
		remote.OnServerEvent:Fire(alpha, table.unpack(a, 1, a.n))
	end)
end

local T = 0
local DT = 1 / 30
local function step(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
	end
end

----------------------------------------------------------------------
-- The benches
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local W, TR = Config.Weapons, Config.Trade
mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
local seats = {} -- [bench][side] = seat
do
	local tagged = CollectionService:GetTagged("TradeSeat")
	check(#tagged == 4, "four trade seats (" .. #tagged .. ")")
	for _, s in ipairs(tagged) do
		local bench, side = s:GetAttribute("Bench"), s:GetAttribute("Side")
		check(s.ClassName == "Seat" and s.Name == "TradeSeat", "a trade seat is a real Seat named TradeSeat")
		check(s.Anchored == true and s.Size.X == 9, "the seat is the bench's long plank")
		check(s.Parent and CollectionService:HasTag(s.Parent, "TradeBench") and s.Parent:GetAttribute("Bench") == bench, "it's on its bench")
		seats[bench] = seats[bench] or {}
		seats[bench][side] = s
	end
	for i = 1, 2 do
		local a, b = seats[i] and seats[i].A, seats[i] and seats[i].B
		check(a and b, "bench " .. i .. " has a side A and a side B")
		if a and b then
			local middle = (a.Position + b.Position) / 2
			check((middle - a.Position):Dot(a.CFrame.LookVector) > 0 and (middle - b.Position):Dot(b.CFrame.LookVector) > 0, "bench " .. i .. ": both seats face the table")
			check(math.abs((a.Position - b.Position).Magnitude - 5.8) < 0.01, "bench " .. i .. ": the seats are across the table from each other")
		end
		for _, part in ipairs(seats[i].A.Parent:GetChildren()) do
			check(part.Name ~= "Seat", "the old plain Seat parts are gone")
		end
	end
end

local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local TS = mount.require(mount.module("ServerScriptService/TradeService.lua"))
PS.Start()
CS.Start(PS)
TS.Start(PS, CS)
step(0.5)
local ad, bd, cd, dd = PS.GetData(alpha), PS.GetData(bravo), PS.GetData(charlie), PS.GetData(delta)
assert(ad and bd and cd and dd, "every save should be loaded")
check(ReplicatedStorage:FindFirstChild("TradeEvent") ~= nil, "the TradeEvent RemoteEvent is made")
local Action = ReplicatedStorage.Remotes.Action

-- saves sent to the screens (MarkDirty) are counted
local dirty = {}
local realMark = PS.MarkDirty
PS.MarkDirty = function(p)
	dirty[p] = (dirty[p] or 0) + 1
	return realMark(p)
end

-- weapons to trade: every pack's
local ids = {}
for _, pack in ipairs(W.Packs) do
	for _, id in ipairs(pack.Weapons) do
		table.insert(ids, id)
	end
end
table.sort(ids)
assert(#ids >= 12, "enough weapons to trade")
-- Alpha: 1-6 (at mastery 500); Bravo: 7-9, and 6; Charlie: 10
for i = 1, 6 do
	ad.Weapons.own[ids[i]] = 500
end
for i = 7, 9 do
	bd.Weapons.own[ids[i]] = 300
end
bd.Weapons.own[ids[6]] = 40
cd.Weapons.own[ids[10]] = 10
local A1, A2, A3, A4, A5, SHARED = ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]
local B1, B2 = ids[7], ids[8]

-- the Action remote, as that player (a short wait first: every player has a
-- small request budget)
local function ask(who, name, arg)
	step(0.15)
	return Action.OnServerInvoke(who, name, arg)
end
local function last(p, kind)
	local list = events[p] or {}
	for i = #list, 1, -1 do
		if list[i][1] == kind then
			return list[i][2], list[i][3], list[i][4], i
		end
	end
	return nil
end
local function count(p, kind)
	local n = 0
	for _, e in ipairs(events[p] or {}) do
		if e[1] == kind then
			n += 1
		end
	end
	return n
end
local function tradeId(p)
	local v = last(p, "State")
	return v and v.id
end
local function sit(hum, seat)
	seat:Sit(hum)
	step(0.1)
end
local function stand(hum)
	hum.Sit = false
	step(0.1)
end
local function owns(d, id)
	return d.Weapons.own[id] ~= nil
end

----------------------------------------------------------------------
-- Alpha's screen
----------------------------------------------------------------------
mount.runClient("StarterPlayerScripts/TradeClient.client.lua", alpha)
step(0.5)
local screen = alpha.PlayerGui:FindFirstChild("Trade")
assert(screen, "the Trade screen should be made")
local function find(name, root)
	return (root or screen):FindFirstChild(name, true)
end
local win, hintChip, toastLabel, doneWin = find("TradeWindow"), find("Hint"), find("Toast"), find("TradeDone")
assert(win and hintChip and toastLabel and doneWin, "the screen's parts should be there")
check(screen:GetAttribute("RetroSkip") == true, "the retro recolour leaves it alone")
check(find("UIScale") ~= nil, "it scales with the screen")
check(not win.Visible, "no window before a trade")

----------------------------------------------------------------------
-- Sitting down: waiting, then a trade for both
----------------------------------------------------------------------
sit(aHum, seats[1].A)
check(last(alpha, "Hint") == "Waiting for someone to sit across from you", "sitting alone: the waiting line (" .. tostring(last(alpha, "Hint")) .. ")")
step(0.2)
check(hintChip.Visible and string.find(hintChip.Text, "Waiting", 1, true), "the waiting line shows on Alpha's screen")
check(count(alpha, "State") == 0, "no trade with nobody across")
sit(bHum, seats[1].B)
local va, vb = last(alpha, "State"), last(bravo, "State")
check(va and vb and va.id == vb.id, "both sat across: a trade opens for both")
check(va and va.name == "Bravo" and vb and vb.name == "Alpha", "each sees the other's name")
check(va and #va.mine == 0 and #va.theirs == 0 and va.max == TR.MaxSlots, "it starts empty")
step(0.2)
check(win.Visible, "the trade window opens on Alpha's screen")
check(not hintChip.Visible, "and the waiting line hides")
check(string.find(find("Title", win).Text, "BRAVO", 1, true), "the window names Bravo")
local grid = find("Inventory", win)
local cards = 0
for _, c in ipairs(grid:GetChildren()) do
	if c:GetAttribute("Weapon") then
		cards += 1
	end
end
check(cards == 6, "Alpha's grid shows her six weapons (" .. cards .. ")")
local id = tradeId(alpha)

----------------------------------------------------------------------
-- Offers
----------------------------------------------------------------------
local ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = A1 })
check(ok, "Alpha puts a weapon in: " .. tostring(msg))
check(table.find(last(bravo, "State").theirs, A1), "Bravo sees it on Alpha's side")
check(table.find(last(alpha, "State").mine, A1), "Alpha sees it on her side")
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = A1 })
check(not ok and string.find(msg, "already in the trade", 1, true), "the same weapon twice is refused: " .. tostring(msg))
ok = ask(alpha, "TradeRemove", { trade = id, weapon = A1 })
check(ok and #last(bravo, "State").theirs == 0, "taking it back: Bravo sees it go")
ok, msg = ask(alpha, "TradeRemove", { trade = id, weapon = A1 })
check(not ok, "taking back what isn't there is refused: " .. tostring(msg))

-- refusals
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = "Coins" })
check(not ok and string.find(msg, "Only weapons", 1, true), "coins can't be traded: " .. tostring(msg))
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = B1 })
check(not ok and string.find(msg, "don't have", 1, true), "someone else's weapon is refused: " .. tostring(msg))
CS.Equip(alpha, A2)
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = A2 })
check(not ok and string.find(msg, "Put it away first", 1, true), "the weapon in your hand is refused: " .. tostring(msg))
CS.Equip(alpha, nil)
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = SHARED })
check(not ok and string.find(msg, "Bravo already has", 1, true), "one Bravo already has is refused: " .. tostring(msg))
ok, msg = ask(charlie, "TradeOffer", { trade = id, weapon = ids[10] })
check(not ok and string.find(msg, "not in a trade", 1, true), "not in a trade: refused: " .. tostring(msg))
ok, msg = ask(alpha, "TradeOffer", { trade = id + 99, weapon = A1 })
check(not ok and string.find(msg, "trade is over", 1, true), "a request for another trade is refused: " .. tostring(msg))
ok, msg = ask(alpha, "TradeOffer", A1)
check(not ok, "a request without its trade is refused: " .. tostring(msg))
for _, w in ipairs({ A1, A2, A3, A4 }) do
	ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = w })
	check(ok, "putting in " .. w .. ": " .. tostring(msg))
end
ok, msg = ask(alpha, "TradeOffer", { trade = id, weapon = A5 })
check(not ok and string.find(msg, "at most", 1, true), "a 5th weapon is refused: " .. tostring(msg))
check(#last(bravo, "State").theirs == 4, "four on Alpha's side")
-- picking one up takes it out of the trade
CS.Equip(alpha, A4)
step(0.1)
check(not table.find(last(bravo, "State").theirs, A4), "a weapon picked up comes out of the trade")
check(string.find(tostring(last(alpha, "Note")), "in your hand", 1, true), "and Alpha is told why")
CS.Equip(alpha, nil)
ask(alpha, "TradeRemove", { trade = id, weapon = A3 })
ask(alpha, "TradeRemove", { trade = id, weapon = A2 })
-- now: Alpha offers A1

----------------------------------------------------------------------
-- ACCEPT
----------------------------------------------------------------------
ok = ask(alpha, "TradeAccept", { trade = id, on = true })
check(ok and last(bravo, "State").themOk == true and last(alpha, "State").meOk == true, "Alpha accepts: both see it")
ok = ask(bravo, "TradeOffer", { trade = id, weapon = B1 })
check(ok and last(alpha, "State").meOk == false and last(bravo, "State").themOk == false, "Bravo changes his side: Alpha's ACCEPT is taken back")
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
local v = last(alpha, "State")
check(v.meOk and v.themOk and type(v.countdown) == "number" and v.countdown > TR.Countdown - 0.5, "both accept: the countdown starts")
step(0.2)
check(string.find(find("Countdown", win).Text, "Trading in", 1, true), "the window says Trading in... (" .. find("Countdown", win).Text .. ")")
step(1)
ok = ask(bravo, "TradeRemove", { trade = id, weapon = B1 })
v = last(alpha, "State")
check(ok and not v.meOk and not v.themOk and v.countdown == nil, "a change in the countdown stops it and takes both ACCEPTs back")
step(TR.Countdown + 1)
check(owns(ad, A1) and not owns(bd, A1) and (TS.swaps or 0) == 0, "so nothing was swapped")
ask(bravo, "TradeOffer", { trade = id, weapon = B1 })
ask(bravo, "TradeOffer", { trade = id, weapon = B2 })

-- both accept, and each fires ACCEPT over and over (and more offers) in the countdown
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
dirty = {}
local slow = 0
for _ = 1, 30 do
	local ok2, m2 = Action.OnServerInvoke(alpha, "TradeAccept", { trade = id, on = true })
	local ok3, m3 = Action.OnServerInvoke(bravo, "TradeAccept", { trade = id, on = true })
	if m2 == "Slow down!" or m3 == "Slow down!" then
		slow += 1
	end
end
check(slow > 0, "a flood of requests is slowed down")
step(TR.Countdown + 0.5)
check((TS.swaps or 0) == 1, "the swap happened exactly once (" .. tostring(TS.swaps) .. ")")
check(not owns(ad, A1) and bd.Weapons.own[A1] == 0, "Alpha's weapon went to Bravo, at mastery 0 (" .. tostring(bd.Weapons.own[A1]) .. ")")
check(not owns(bd, B1) and not owns(bd, B2) and ad.Weapons.own[B1] == 0 and ad.Weapons.own[B2] == 0, "Bravo's two went to Alpha, at mastery 0")
check(owns(ad, A2) and owns(bd, ids[9]) and bd.Weapons.own[SHARED] == 40, "nothing else moved")
check((dirty[alpha] or 0) >= 1 and (dirty[bravo] or 0) >= 1, "both saves are sent")
local got, gave, from = last(alpha, "Done")
check(got and #got == 2 and table.find(got, B1) and table.find(got, B2) and #gave == 1 and gave[1] == A1 and from == "Bravo", "Alpha is told what she got and gave")
got = last(bravo, "Done")
check(got and #got == 1 and got[1] == A1, "Bravo is told what he got")
check(aHum.SeatPart == nil and bHum.SeatPart == nil and seats[1].A.Occupant == nil, "both stand up after the trade")
step(0.3)
check(doneWin.Visible and string.find(find("Words", doneWin).Text, "Bravo", 1, true), "Alpha's screen: Trade complete! (" .. find("Words", doneWin).Text .. ")")
check(find(B1, find("Got", doneWin)) ~= nil, "with the weapons she got")
check(not win.Visible, "and the trade window closes")
for _ = 1, 5 do
	ok, msg = Action.OnServerInvoke(alpha, "TradeAccept", { trade = id, on = true })
end
check(not ok and (TS.swaps or 0) == 1, "accepting again after it does nothing: " .. tostring(msg))
step(1)
ok, msg = ask(bravo, "TradeOffer", { trade = id, weapon = A1 })
check(not ok, "and the old trade takes no more offers")

-- the cooldown
sit(aHum, seats[1].A)
sit(bHum, seats[1].B)
local before = count(alpha, "State")
step(0.6)
check(count(alpha, "State") == before and string.find(tostring(last(alpha, "Hint")), "just traded", 1, true), "straight after a trade: wait (" .. tostring(last(alpha, "Hint")) .. ")")
step(TR.Cooldown)
check(count(alpha, "State") > before and tradeId(alpha) ~= id, "after the cooldown the trade opens")
id = tradeId(alpha)

----------------------------------------------------------------------
-- Stopping a trade: nothing moves
----------------------------------------------------------------------
ask(alpha, "TradeOffer", { trade = id, weapon = A2 })
ask(bravo, "TradeOffer", { trade = id, weapon = ids[9] })
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
stand(bHum)
check(string.find(tostring(last(alpha, "Closed")), "Bravo stood up", 1, true), "Bravo stands up in the countdown: stopped (" .. tostring(last(alpha, "Closed")) .. ")")
check(last(bravo, "Closed") ~= nil, "for both")
step(TR.Countdown + 0.5)
check(owns(ad, A2) and owns(bd, ids[9]) and (TS.swaps or 0) == 1, "nothing moved")
step(0.3)
check(not win.Visible and toastLabel.Visible and string.find(toastLabel.Text, "stood up", 1, true), "Alpha's window closes with the message")
check(string.find(tostring(last(alpha, "Hint")), "Waiting", 1, true), "Alpha waits again")

-- the window's buttons ask the right things
sit(bHum, seats[1].B)
id = tradeId(alpha)
step(0.3)
check(win.Visible, "a new trade: the window opens again")
invokes = {}
local card = nil
for _, c in ipairs(grid:GetChildren()) do
	if c:GetAttribute("Weapon") == A3 then
		card = c
	end
end
check(card ~= nil, "A3's card is in the grid")
if card then
	find("Tap", card).Activated:Fire()
	step(0.2)
end
check(invokes[1] and invokes[1].name == "TradeOffer" and invokes[1].arg.weapon == A3 and invokes[1].arg.trade == id, "tapping a weapon asks TradeOffer")
check(find("YourSide", win).Slot1:GetAttribute("Weapon") == A3, "it shows in her first slot")
ask(bravo, "TradeOffer", { trade = id, weapon = ids[9] })
step(0.2)
check(find("TheirSide", win).Slot1:GetAttribute("Weapon") == ids[9], "Bravo's weapon shows on his side of her window")
find("Accept", win).Activated:Fire()
step(0.2)
check(invokes[2] and invokes[2].name == "TradeAccept" and invokes[2].arg.on == true, "ACCEPT asks TradeAccept")
check(find("Ready", find("YourSide", win)).Text == "ACCEPTED", "her side shows ACCEPTED")
if SNAPS then
	snapGui(screen, "TRADING|sit across from someone at a picnic bench: your side, theirs, your weapons, ACCEPT", 1280, 720)
end
check(find("Ready", find("TheirSide", win)).Text == "NOT READY", "his doesn't yet")
find("YourSide", win).Slot1.Activated:Fire()
step(0.2)
check(invokes[3] and invokes[3].name == "TradeRemove" and invokes[3].arg.weapon == A3, "tapping her slot asks TradeRemove")
check(find("Ready", find("YourSide", win)).Text == "NOT READY", "and the change takes her ACCEPT back")
find("Cancel", win).Activated:Fire()
step(0.3)
check(invokes[4] and invokes[4].name == "TradeCancel", "CANCEL asks TradeCancel")
check(aHum.SeatPart == nil and not win.Visible, "CANCEL stands her up and closes the window")
check(string.find(tostring(last(bravo, "Closed")), "Alpha cancelled", 1, true), "Bravo is told Alpha cancelled")
check(owns(ad, A3) and owns(bd, ids[9]), "nothing moved")

-- knocked out
sit(aHum, seats[1].A)
id = tradeId(alpha)
ask(alpha, "TradeOffer", { trade = id, weapon = A2 })
bHum.Health = 0
step(0.2)
check(string.find(tostring(last(alpha, "Closed")), "knocked out", 1, true), "Bravo knocked out: stopped (" .. tostring(last(alpha, "Closed")) .. ")")
-- (the body lets go of the seat, and a new one comes, as when you come
-- back after being knocked out)
stand(bHum)
step(4)
do
	local char = Instance.new("Model")
	char.Name = "Bravo"
	bHum = Instance.new("Humanoid")
	bHum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(62, 3.55, 20)
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	bravo.Character = char
	bravo.CharacterAdded:Fire(char)
	step(0.2)
end

-- leaving the lobby
sit(bHum, seats[1].B)
id = tradeId(alpha)
ask(alpha, "TradeOffer", { trade = id, weapon = A2 })
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
alpha:SetAttribute("Colosseum", true)
step(0.2)
check(string.find(tostring(last(bravo, "Closed")), "Alpha left the lobby", 1, true), "Alpha leaves the lobby: stopped (" .. tostring(last(bravo, "Closed")) .. ")")
step(TR.Countdown + 1)
check(owns(ad, A2) and (TS.swaps or 0) == 1, "nothing moved")
check(count(bravo, "State") > 0 and tradeId(bravo) == id, "and no new trade pops open while she's away")
alpha:SetAttribute("Colosseum", nil)
stand(aHum)
stand(bHum)

----------------------------------------------------------------------
-- Never in two trades
----------------------------------------------------------------------
sit(aHum, seats[1].A)
sit(bHum, seats[1].B)
id = tradeId(alpha)
sit(cHum, seats[2].A)
-- (Alpha somehow in the other bench's seat too)
seats[2].B.Occupant = aHum
step(0.6)
check(count(charlie, "State") == 0, "Alpha can't be in a second trade with Charlie")
ask(alpha, "TradeOffer", { trade = id, weapon = A2 })
check(table.find(last(bravo, "State").theirs, A2), "her trade with Bravo goes on")
seats[2].B.Occupant = nil
step(0.1)

-- Delta sits across Charlie and leaves the game mid-trade
sit(dHum, seats[2].B)
local cid = tradeId(charlie)
check(cid ~= nil and cid ~= id, "Charlie and Delta get their own trade")
ask(charlie, "TradeOffer", { trade = cid, weapon = ids[10] })
ask(charlie, "TradeAccept", { trade = cid, on = true })
ask(delta, "TradeAccept", { trade = cid, on = true })
Players.PlayerRemoving:Fire(delta)
step(0.2)
check(string.find(tostring(last(charlie, "Closed")), "Delta left the game", 1, true), "Delta leaves the game: stopped (" .. tostring(last(charlie, "Closed")) .. ")")
step(TR.Countdown + 1)
check(owns(cd, ids[10]) and not owns(dd, ids[10]) and (TS.swaps or 0) == 1, "nothing moved")

----------------------------------------------------------------------
-- Copying a weapon: no way
----------------------------------------------------------------------
-- Bravo gets A2 some other way during the countdown: re-checked at the swap
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeOffer", { trade = id, weapon = ids[9] })
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
bd.Weapons.own[A2] = 5
step(TR.Countdown + 0.5)
check((TS.swaps or 0) == 1 and string.find(tostring(last(alpha, "Closed")), "already has", 1, true), "Bravo got it meanwhile: the swap is stopped (" .. tostring(last(alpha, "Closed")) .. ")")
check(owns(ad, A2) and bd.Weapons.own[A2] == 5 and owns(bd, ids[9]) and not owns(ad, ids[9]), "and nothing moved")
bd.Weapons.own[A2] = nil
stand(aHum)
stand(bHum)
step(0.2)

-- the same weapon flooded in
sit(aHum, seats[1].A)
sit(bHum, seats[1].B)
id = tradeId(alpha)
local n = 0
for _ = 1, 10 do
	Action.OnServerInvoke(alpha, "TradeOffer", { trade = id, weapon = A5 })
end
for _, w in ipairs(last(bravo, "State").theirs) do
	if w == A5 then
		n += 1
	end
end
check(n == 1, "offering the same weapon ten times puts it in once (" .. n .. ")")
step(2)
-- both accept: the swap
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
step(TR.Countdown + 0.5)
check((TS.swaps or 0) == 2 and not owns(ad, A5) and bd.Weapons.own[A5] == 0, "the second swap happened")
-- (a look round straight after: nothing more happens)
local swapsNow = TS.swaps
TS.Refresh()
check(TS.swaps == swapsNow and not owns(ad, A5), "it doesn't happen twice")
local weaponsA, weaponsB = 0, 0
for _ in pairs(ad.Weapons.own) do
	weaponsA += 1
end
for _ in pairs(bd.Weapons.own) do
	weaponsB += 1
end
-- Alpha: 6 - 1 + 2 - 1 = 6; Bravo: 4 + 1 - 2 + 1 = 4 (10 in all, as at the start)
check(weaponsA == 6 and weaponsB == 4, "no weapon was ever made or lost (" .. weaponsA .. " + " .. weaponsB .. ")")

-- a weapon given away is never still in a hand (the saved one too)
step(TR.Cooldown + 0.5)
sit(aHum, seats[1].A)
sit(bHum, seats[1].B)
id = tradeId(alpha)
ask(alpha, "TradeOffer", { trade = id, weapon = A3 })
ask(alpha, "TradeAccept", { trade = id, on = true })
ask(bravo, "TradeAccept", { trade = id, on = true })
ad.Weapons.hold = A3 -- (as if saved as the one she holds)
step(TR.Countdown + 0.5)
check((TS.swaps or 0) == 3 and not owns(ad, A3) and ad.Weapons.hold == nil and alpha:GetAttribute("Weapon") == nil, "a weapon given away isn't held any more")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings (" .. tostring(M.warnings) .. ")")
if fails == 0 then
	print("PASS trade (server and screen)")
else
	print(fails .. " failures")
end
