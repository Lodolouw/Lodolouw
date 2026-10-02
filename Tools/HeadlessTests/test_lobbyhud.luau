--!nocheck
-- Headless test of THE NEW LOBBY SCREEN (LobbyHud.client.lua) and THE MENUS'
-- HOST (ReplicatedStorage/Menus), with the old HUD (Hud.client.lua) beside
-- them and a pretend server: the old left buttons, stats strip and hint
-- hide; the four picture buttons and STATS / GEAR with their badges; your
-- coins and tokens; the NEXT GOAL (pick a quest, spin your tokens, hand in a
-- quest, train in the Colosseum, climb the Spire) with the glowing trail on
-- the ground and the beam over the goal; the free gift's clock (tapping it
-- when it's ready claims it); rewards' badge; today's quest; the boost tags;
-- the corner bonuses; hiding in fights and behind a menu. The menus: a menu
-- opens over a dimmed, blurred world with its title, tabs and page, one at a
-- time; tabs switch; Esc and fights close it; the server's messages show on
-- top; unknown menus say "Coming soon!"; older windows open through
-- Menus.external.
--   luau test_lobbyhud.luau -a snaps    ...also prints snapshots for render_gui.py
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum, Vector3, CFrame = M.Instance, M.Enum, M.Vector3, M.CFrame
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage
local CollectionService = M.services.CollectionService
local SNAPS = ({ ... })[1] == "snaps"
local snapGui = SNAPS and require("./gui_snap") or nil

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

RunService.IsStudio = function()
	return true
end
RunService.IsClient = function()
	return true
end
M.services.StarterGui = {
	SetCoreGuiEnabled = function() end,
	GetCoreGuiEnabled = function()
		return true
	end,
	SetCore = function() end,
}
M.services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	LastInputTypeChanged = M.Signal.new(),
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
}
local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
M.players = { me }
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local char = Instance.new("Model")
local hum = Instance.new("Humanoid")
hum.Parent = char
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.Parent = char
char.Parent = M.workspace
me.Character = char
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam

-- flat ground everywhere
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

-- a little lobby: the walk-up boxes the trail leads to
local zones = {}
for name, spot in pairs({ Spire = { "Spire", "Menu", Vector3.new(0, 4, -120) }, Arcade = { "Activity", "Arcade", Vector3.new(80, 4, 0) }, Quests = { "Activity", "Quests", Vector3.new(-60, 4, 20) } }) do
	local z = Instance.new("Part")
	z.Name = "AutoOpenZone"
	z.Size = Vector3.new(16, 8, 10)
	z.CFrame = CFrame.new(spot[3])
	z:SetAttribute(spot[1], spot[2])
	z.Parent = M.workspace
	CollectionService:AddTag(z, "AutoOpenZone")
	zones[name] = z
end

-- the pretend server
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "StateUpdate", "RequestState", "Notify", "OpenPanel" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes
local asked = {}
M.onInvokeServer = function(_, name, arg)
	table.insert(asked, tostring(name))
	if name == "RewardGift" then
		return true, "Free gift! +300 coins"
	end
	return true, nil
end
local arcadeOpened = 0
local open = Instance.new("BindableEvent")
open.Name = "ArcadeOpen"
open.Parent = ReplicatedStorage
open.Event:Connect(function()
	arcadeOpened += 1
end)

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local R = Config.Rewards
if SNAPS then
	-- (the pictures: as if the menu icons were uploaded - render_gui.py paints
	-- Tools/Icons/out/ui/<name>.png for each)
	local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
	AssetIds.Icons = AssetIds.Icons or {}
	local id = 9100000
	for _, key in ipairs({ "Shop", "Bag", "Arcade", "Index", "Gift", "Rewards", "Settings", "Featured", "Tickets", "Tokens", "Daily", "Passes", "Looks", "Weapons", "Titles", "Bosses", "Goals", "Revive", "Spin", "BossRush", "Luck", "Playtime", "Friends", "Spire", "Lock", "Codes", "Updates", "Flask", "Bolt", "Stats", "Gear" }) do
		id += 1
		AssetIds.Icons["UI_" .. key] = id
	end
	for key, aid in pairs(AssetIds.Icons) do
		print("ICONMAP " .. tostring(aid) .. " " .. key)
	end
end
mount.runClient("StarterPlayerScripts/Hud.client.lua", me)
mount.runClient("StarterPlayerScripts/LobbyHud.client.lua", me)
local Menus = mount.require(mount.module("ReplicatedStorage/Menus.lua"))
M.run(1)

local T = 1
local function wait(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += 1 / 20
		M.run(T)
		RunService.Heartbeat:Fire(1 / 20)
	end
end

local today = Config.questDay(1700000000 + math.floor(M.now()))
local function snapshot(over)
	local d = {
		Power = 100, Coins = 1234, Tokens = 0,
		Weapons = { own = { StarterSword = 0 } }, Quests = { day = 0, list = { { id = "Arena10", n = 0 }, { id = "Boss1", n = 0 }, { id = "Clear1", n = 0 } } },
		Cleared = {},
		Rewards = { streak = 1, streakDay = today, giftPlay = 0, gifts = 0, giftsToday = 0, codes = {}, updates = { [R.Updates[1].Id] = true }, index = {}, milestones = {} },
		Boosts = { XP = 0, Coins = 0, Luck = 0 }, Tickets = { Revive = 0, Rush = 0 }, Shop = { starter = false, receipts = {}, daily = {} },
		Looks = { titles = {}, auras = {} }, Settings = {},
	}
	for k, v in pairs(over or {}) do
		d[k] = v
	end
	return d
end
local function send(over)
	remotes.StateUpdate.OnClientEvent:Fire(snapshot(over))
	wait(0.3)
end

local lobby = playerGui:FindFirstChild("LobbyHud")
local root = lobby and lobby:FindFirstChild("Root")
local function find(parent, name)
	return parent and parent:FindFirstChild(name, true)
end
local function goalText()
	local g = find(root, "NextGoal")
	return g and g.Visible and find(g, "Goal").Text or nil
end
local function dashesShown()
	local n = 0
	local folder = M.workspace:FindFirstChild("GuideTrail")
	for _, p in ipairs(folder and folder:GetChildren() or {}) do
		if p.Name == "Dash" and p.Transparency < 1 then
			n += 1
		end
	end
	return n
end
-- the average direction the shown dashes lie in, from the player
local function trailPointsTo(zone)
	local folder = M.workspace:FindFirstChild("GuideTrail")
	local sum, n = Vector3.new(0, 0, 0), 0
	for _, p in ipairs(folder and folder:GetChildren() or {}) do
		if p.Name == "Dash" and p.Transparency < 1 then
			sum += p.Position - hrp.Position
			n += 1
		end
	end
	if n == 0 then
		return false
	end
	local want = zone.Position - hrp.Position
	local a, b = Vector3.new(sum.X, 0, sum.Z).Unit, Vector3.new(want.X, 0, want.Z).Unit
	return a:Dot(b) > 0.98
end
local function badge(name)
	local b = find(find(root, "Buttons"), name)
	local bg = b and b:FindFirstChild("Badge", true)
	return bg and bg.Visible and bg.Text or nil
end

----------------------------------------------------------------------
-- The screen, and the old HUD's pieces hidden
----------------------------------------------------------------------
check(lobby ~= nil and lobby:GetAttribute("RetroSkip") == true, "the lobby screen is made (and RetroUI leaves it alone)")
local old = playerGui:FindFirstChild("BossGrowHud")
check(old and find(old, "LeftButtons").Visible == false, "the old left buttons hide")
check(old and find(old, "Stats").Visible == false, "the old stats strip hides")
check(old and find(old, "HintBanner").Visible == false, "the old hint line hides")
check(old and find(old, "GoalBar").Visible ~= false, "the level bar stays")
for _, name in ipairs({ "Shop", "Bag", "Arcade", "Index" }) do
	check(find(find(root, "Buttons"), name) ~= nil, "the " .. name .. " button is there")
end
check(find(find(root, "Buttons"), "Stats") == nil, "no STATS button (stat points are gone)")
check(find(find(root, "Buttons"), "Gear") == nil, "no GEAR button")
check(find(root, "Money") and find(find(root, "Money"), "Coin") and find(find(root, "Money"), "Token"), "coins and tokens bottom left, with their pictures")

----------------------------------------------------------------------
-- A new player: pick a quest
----------------------------------------------------------------------
send({})
check(find(find(root, "Coins"), "Amount").Text == Config.format(1234), "the coins show (" .. tostring(find(find(root, "Coins"), "Amount").Text) .. ")")
check(goalText() == "Pick a quest", "a new player's goal: pick a quest (" .. tostring(goalText()) .. ")")
check(dashesShown() >= 6, "the trail shows (" .. dashesShown() .. " dashes)")
check(trailPointsTo(zones.Quests), "it leads to the Quest Board")
local far = find(root, "Distance").Text
check(far == math.floor((Vector3.new(-60, 0, 20)).Magnitude) .. "m", "how far it is (" .. tostring(far) .. ")")
local beam = M.workspace.GuideTrail:FindFirstChild("Beam")
check(beam.Transparency < 1 and math.abs(beam.Position.X + 60) < 0.01, "a beam of light stands on the goal")
-- the GUIDE button under the card turns the trail and the light off (and on)
local guideBtn = find(root, "GuideToggle")
check(guideBtn and guideBtn.Text == "GUIDE: ON", "a GUIDE: ON button under the next goal")
guideBtn.Activated:Fire()
wait(0.3)
check(guideBtn.Text == "GUIDE: OFF" and dashesShown() == 0 and beam.Transparency == 1, "pressed: GUIDE: OFF, the trail and the light go")
check(find(root, "Distance").Text == far, "(it still says how far)")
guideBtn.Activated:Fire()
wait(0.3)
check(guideBtn.Text == "GUIDE: ON" and dashesShown() >= 6, "pressed again: back on")
check(badge("Arcade") == nil, "no tokens: no badge on ARCADE")
check(find(root, "Quest").Visible and find(find(root, "Quest"), "Text").Text == "Pick one at the Quest Board!", "today's quest says to pick one")

----------------------------------------------------------------------
-- Tokens to spin, a quest to hand in, training, the Spire
----------------------------------------------------------------------
send({ Tokens = 3 })
check(goalText() == "Spin at the Arcade", "tokens: spin them (" .. tostring(goalText()) .. ")")
check(trailPointsTo(zones.Arcade), "the trail turns to the Arcade")
check(badge("Arcade") == "3", "ARCADE's badge counts the tokens")
check(find(find(root, "Tokens"), "Amount").Text == "3", "the tokens show")

local quests = { day = 0, pick = 1, list = { { id = "Arena10", n = 10 }, { id = "Boss1", n = 0 }, { id = "Clear1", n = 0 } } }
send({ Tokens = 3, Quests = quests })
check(goalText() == "Hand in your quest", "a finished quest comes first (" .. tostring(goalText()) .. ")")
check(find(find(root, "Quest"), "Meter"):FindFirstChild("Text").Text == "HAND IT IN!", "the quest card says to hand it in")

quests.list[1].claimed = true
send({ Quests = quests, Power = 0 })
check(goalText() == "Train in the Colosseum", "too low for floor 1: train (" .. tostring(goalText()) .. ")")
check(trailPointsTo(zones.Spire), "the trail leads to the Spire (the Colosseum is its ground floor)")
local lv = Config.Spire.Floors[1].level
send({ Quests = quests, Power = Config.powerForLevel(lv) })
check(goalText() == "Climb the Spire · Floor 1", "strong enough: the Spire (" .. tostring(goalText()) .. ")")
check(trailPointsTo(zones.Spire), "the trail leads to the Spire")
send({ Quests = quests, Power = Config.powerForLevel(lv), Cleared = { ["1"] = 1 } })
check(goalText() ~= nil and string.find(goalText(), "Floor 2") ~= nil or goalText() == "Train in the Colosseum", "floor 1 beaten: on to floor 2 (" .. tostring(goalText()) .. ")")
check(badge("Shop") == "!", "first boss down: the shop's starter pack badge")

-- THE NEW PLAYER PATH comes first: its step on the card, the pips, the trail
-- to the step's place, and an arrow beside the BAG for the equip step
do
	local steps = Config.Path.Steps
	local function kicker()
		local g = find(root, "NextGoal")
		return g and find(g, "Kicker").Text or ""
	end
	send({ Quests = quests, Power = Config.powerForLevel(lv), Tokens = 3, Path = { step = 1, done = false } })
	check(goalText() == steps[1].Text, "the path's step 1 on the card (" .. tostring(goalText()) .. ")")
	check(string.find(kicker(), "STEP 1 OF " .. #steps) ~= nil, "...marked as the path's step 1 of " .. #steps .. " (" .. kicker() .. ")")
	check(trailPointsTo(zones.Arcade), "...and the trail leads to the Arcade")
	local pips = find(root, "PathPips")
	check(pips and pips.Visible, "the path's pips show")
	send({ Quests = quests, Power = Config.powerForLevel(lv), Path = { step = 2, done = false } })
	check(goalText() == steps[2].Text, "step 2: hold your weapon (" .. tostring(goalText()) .. ")")
	wait(0.1)
	local arrow = find(lobby, "PathArrow")
	check(arrow and arrow.Visible, "an arrow bobs beside the BAG")
	if SNAPS then
		snapGui(lobby, "THE NEW PLAYER PATH|step 2 of 5 on the goal card, the pips, an arrow at the BAG", 1280, 720)
	end
	send({ Quests = quests, Power = Config.powerForLevel(lv), Path = { step = 3, done = false } })
	check(goalText() == steps[3].Text and trailPointsTo(zones.Quests), "step 3: the Quest Board, trail and all")
	wait(0.1)
	check(not (arrow and arrow.Visible), "no arrow when the step's a place to walk to")
	send({ Quests = quests, Power = Config.powerForLevel(lv), Path = { step = 5, done = true } })
	check(goalText() ~= steps[5].Text and string.find(kicker(), "STEP") == nil, "the path done: back to the usual goals (" .. tostring(goalText()) .. ")")
	check(not (pips and pips.Visible), "and no pips")
end

-- walking up to it: the trail goes
hrp.CFrame = CFrame.new(zones.Spire.Position.X, 3, zones.Spire.Position.Z + 5)
send({ Quests = quests, Power = Config.powerForLevel(lv) })
check(dashesShown() == 0, "at the goal the trail goes")
hrp.CFrame = CFrame.new(0, 3, 0)

----------------------------------------------------------------------
-- The free gift, rewards, the Index, stats
----------------------------------------------------------------------
local need = R.GiftMinutes * 60
send({ Quests = quests, Rewards = { streak = 1, streakDay = today - 1, giftPlay = need - 65, giftsToday = 0, codes = {}, updates = {}, index = {}, milestones = {} }, Weapons = { own = { StarterSword = 0, GooGloves = 0 } } })
local giftLabel = find(find(find(root, "Corner"), "Gift"), "Label")
check(giftLabel.Text == "1:05" or giftLabel.Text == "1:04", "the gift's clock counts down (" .. giftLabel.Text .. ")")
check(find(find(root, "Corner"), "Rewards"):FindFirstChild("Badge", true).Text == "2", "rewards' badge: today's login and the update's gift")
local ownIndex = 0
for _, id in ipairs({ "StarterSword", "GooGloves" }) do
	if Config.Weapons.List[id] then
		ownIndex += 1
	end
end
check(ownIndex == 0 or badge("Index") == tostring(ownIndex), "INDEX's badge counts weapons to claim (" .. tostring(badge("Index")) .. ")")
local giftBtn = find(find(root, "Corner"), "Gift"):FindFirstChild("Button")
giftBtn.Activated:Fire()
wait(0.2)
check(table.find(asked, "RewardGift") == nil, "tapping it early doesn't claim it")
wait(70)
check(giftLabel.Text == "READY!", "then it's ready (" .. giftLabel.Text .. ")")
giftBtn.Activated:Fire()
wait(0.2)
check(table.find(asked, "RewardGift") ~= nil, "tapping it now claims it")

----------------------------------------------------------------------
-- Boosts, passes and the corner bonuses
----------------------------------------------------------------------
me:SetAttribute("PlayBonus", 3)
me:SetAttribute("FriendBonus", 10)
me:SetAttribute("Pass_DoubleCoins", true)
send({ Quests = quests, Boosts = { XP = 120, Coins = 0, Luck = 0 } })
local boosts = find(root, "Boosts")
check(boosts.XP.Visible and string.find(boosts.XP.Text, "2X XP 1:5") ~= nil, "a 2x XP boost shows with its time (" .. boosts.XP.Text .. ")")
check(boosts.Coins.Visible and boosts.Coins.Text == "2X COINS", "the 2x Coins pass shows")
check(not boosts.Luck.Visible, "no luck")
check(find(find(root, "Bonuses"), "Playtime"):FindFirstChild("Amount").Text == "+3%", "the play-time bonus")
check(find(find(root, "Bonuses"), "Friends"):FindFirstChild("Amount").Text == "+10%", "the friends bonus")

----------------------------------------------------------------------
-- Hidden in fights
----------------------------------------------------------------------
me:SetAttribute("SpireFloor", 1)
wait(0.3)
check(root.Visible == false, "in a fight the lobby screen hides")
check(dashesShown() == 0 and beam.Transparency == 1, "and the trail and beam go")
me:SetAttribute("SpireFloor", nil)
wait(0.3)
check(root.Visible == true, "back in the lobby it's back")

if SNAPS then
	send({ Tokens = 3, Quests = { day = 0, pick = 1, list = { { id = "Arena10", n = 6 }, { id = "Boss1", n = 0 }, { id = "Clear1", n = 0 } } }, Power = Config.powerForLevel(12), Boosts = { XP = 754, Coins = 0, Luck = 0 },
		Rewards = { streak = 1, streakDay = today - 1, giftPlay = need - 221, giftsToday = 0, codes = {}, updates = {}, index = {}, milestones = {} }, Weapons = { own = { StarterSword = 0, GooGloves = 0 } } })
	snapGui(playerGui:FindFirstChild("BossGrowHud"), "THE NEW LOBBY SCREEN|picture buttons, money, next goal, gift clock, quest, boosts, bonuses", 1280, 720)
	snapGui(lobby, nil, 1280, 720)
end

----------------------------------------------------------------------
-- The menus
----------------------------------------------------------------------
local drawn = {}
Menus.define("Test", {
	Title = "Test Menu",
	Color = Config and nil,
	Tabs = { { Key = "One", Label = "One", Icon = "Featured" }, { Key = "Two", Label = "Two", Icon = "Tickets" } },
	render = function(page, tab, api)
		table.insert(drawn, tab)
		local face = api.K.card(page, { Size = M.UDim2.fromOffset(300, 120) })
		api.K.label(face, { Name = "Words", Text = "tab " .. tab })
	end,
})
check(Menus.open("Test"), "a menu opens")
wait(0.3)
local mg = playerGui:FindFirstChild("Menus")
local mroot = mg and mg:FindFirstChild("Root")
check(mg and mg:GetAttribute("RetroSkip") == true and mroot.Visible, "the menus' screen shows")
check(me:GetAttribute("MenuOpen") == "Test", "MenuOpen says which")
check(M.services.Lighting:FindFirstChild("MenuBlur") ~= nil, "the world blurs behind")
check(find(mroot, "Veil") and find(mroot, "Veil").BackgroundTransparency < 1 and find(mroot, "Veil").BackgroundTransparency > 0, "and dims (see-through)")
check(find(mroot, "Title").Text == "Test Menu", "the big title")
check(drawn[#drawn] == "One", "the first tab is drawn")
check(root.Visible == false, "the lobby's buttons hide behind a menu")
check(find(find(mroot, "Money"), "Amount") ~= nil, "your money top right")
local tab2 = find(mroot, "Tab_Two")
check(tab2 ~= nil and find(mroot, "Tab_One"):GetAttribute("On") == true, "the tabs, the first picked")
tab2.Activated:Fire()
wait(0.1)
check(drawn[#drawn] == "Two" and find(mroot, "Tab_Two"):GetAttribute("On") == true, "a tab switches the page")
check(find(mroot, "Words").Text == "tab Two", "the page shows the new tab")
remotes.Notify.OnClientEvent:Fire("A message from the server", "good")
wait(0.1)
local onTop = false
for _, t in ipairs(mg.Toasts:GetChildren()) do
	onTop = onTop or (t.Name == "Toast" and t.Text == "A message from the server")
end
check(onTop, "the server's messages show over the menu")
M.services.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Escape }, false)
wait(0.1)
check(mroot.Visible == false and me:GetAttribute("MenuOpen") == nil, "Esc closes it")
check(M.services.Lighting:FindFirstChild("MenuBlur") == nil, "and the blur goes")
check(root.Visible == true, "the lobby's buttons come back")

Menus.open("Test", "Two")
check(drawn[#drawn] == "Two", "a menu can open at a tab")
me:SetAttribute("Colosseum", true)
wait(0.1)
check(Menus.current() == nil and mroot.Visible == false, "a fight closes the menu")
check(Menus.open("Test") == false, "and no menus open in a fight")
me:SetAttribute("Colosseum", nil)

local gearOpened = 0
Menus.external.Gear = function()
	gearOpened += 1
end
Menus.go("Gear")
wait(0.1)
check(gearOpened == 1, "an older window opens through Menus.external")
find(find(find(root, "Buttons"), "Arcade"), "Button").Activated:Fire()
wait(0.1)
check(arcadeOpened == 1, "ARCADE opens the Arcade's menu")
Menus.go("Nothing")
wait(0.1)
local soon = false
for _, t in ipairs(mg.Toasts:GetChildren()) do
	soon = soon or (t.Name == "Toast" and t.Text == "Coming soon!")
end
check(soon, "a menu that isn't made yet says so")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings")
if fails == 0 then
	print("PASS  test_lobbyhud: the lobby screen, the next goal and its trail, the menus' host")
else
	print("FAILED: " .. fails)
end
