--!nocheck
-- Headless test of THE SPIRE MENU (SpireClient.client.lua) in the new
-- see-through menus, with a pretend server:
--   * walking up to the Spire's doors opens it (walking away closes it), on
--     the floor you're up to; the floors are cards - the ground floor (the
--     Colosseum) and floors 1 to 10, BEATEN / LV / a lock - and the picked
--     one is big: its boss, area, the whole blurb, the level it wants and
--     yours, and ENTER (SpireTravel "enter")
--   * a floor you haven't opened: LOCKED, "Beat ... first", ENTER does nothing
--   * under a floor's level: TOO LOW and TRAIN FIRST (SpireTravel "colosseum");
--     the ground floor's TRAIN and its +XP bonus
--   * in a party: the leader's floor ("LEADER PICKS" for the others)
--   * in the arena: the LEAVE ARENA button and the "Leave?" check (STAY /
--     LEAVE: SpireTravel "leave"), and a refusal shows as a toast
--   luau test_spire_menu.luau -a snaps    ...also prints snapshots for render_gui.py
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum, CFrame, Vector3 = M.Instance, M.Enum, M.CFrame, M.Vector3
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage
local CollectionService = M.services.CollectionService
local SNAPS = ({ ... })[1] == "snaps"
local snapGui = SNAPS and require("./gui_snap") or nil

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	else
		print("  ok   " .. msg)
	end
end

RunService.IsStudio = function()
	return false -- (in Studio every floor is open: here they open one by one)
end
RunService.IsClient = function()
	return true
end
local UIS = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
}
M.services.UserInputService = UIS
local function newPlayer(name, id)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	p.Parent = Players
	table.insert(M.players, p)
	return p
end
M.players = {}
local me = newPlayer("Tester", 1001)
local friend = newPlayer("Alpha", 1002)
Players.LocalPlayer = me
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local char = Instance.new("Model")
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
-- your level (the leaderboard's)
local ls = Instance.new("Folder")
ls.Name = "leaderstats"
ls.Parent = me
local levelValue = Instance.new("IntValue")
levelValue.Name = "Level"
levelValue.Value = 50
levelValue.Parent = ls

-- the remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "StateUpdate", "RequestState", "Notify" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes
local spireRemotes = Instance.new("Folder")
spireRemotes.Name = "SpireRemotes"
spireRemotes.Parent = ReplicatedStorage
local spireEvent = Instance.new("RemoteEvent")
spireEvent.Name = "SpireEvent"
spireEvent.Parent = spireRemotes
local spireTravel = Instance.new("RemoteFunction")
spireTravel.Name = "SpireTravel"
spireTravel.Parent = spireRemotes
local travelled = {}
local travelAnswer = { true }
local travelTier = {}
M.onInvokeServer = function(remote, a, b, c)
	if remote == spireTravel then
		table.insert(travelled, tostring(a) .. (b ~= nil and (":" .. tostring(b)) or ""))
		table.insert(travelTier, c)
		return travelAnswer[1], travelAnswer[2]
	end
	return true, nil
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local F = Config.Spire.Floors
if SNAPS then
	local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
	AssetIds.Icons = AssetIds.Icons or {}
	local id = 9100000
	for _, key in ipairs({ "Shop", "Bag", "Arcade", "Index", "Gift", "Rewards", "Settings", "Spire", "Lock", "Weapons", "Bosses", "Goals", "Friends" }) do
		id += 1
		AssetIds.Icons["UI_" .. key] = id
	end
	for key, aid in pairs(AssetIds.Icons) do
		print("ICONMAP " .. tostring(aid) .. " " .. key)
	end
end
local Menus = mount.require(mount.module("ReplicatedStorage/Menus.lua"))
mount.runClient("StarterPlayerScripts/SpireClient.client.lua", me)
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
local function send(d)
	remotes.StateUpdate.OnClientEvent:Fire(d)
	wait(0.3)
end
local function page()
	local g = playerGui:FindFirstChild("Menus")
	return g and g.Root:FindFirstChild("Page")
end
local function find(name, root)
	root = root or page()
	return root and root:FindFirstChild(name, true)
end
local function click(b)
	check(b ~= nil, "a button to press")
	if b then
		b.Activated:Fire()
		wait(0.3)
	end
end
local function tap(cardName)
	click(find("Tap", find(cardName, find("Floors"))))
end
local function textOf(name, root)
	local l = find(name, root)
	return l and l.Text or ""
end
local function snap(caption)
	if SNAPS then
		snapGui(playerGui:FindFirstChild("Menus"), caption, 1280, 720)
	end
end
local function toasts()
	local list = {}
	local g = playerGui:FindFirstChild("Menus")
	local host = g and g:FindFirstChild("Toasts")
	for _, t in ipairs(host and host:GetChildren() or {}) do
		if t:IsA("TextLabel") then
			table.insert(list, t.Text)
		end
	end
	return table.concat(list, " | ")
end
send({ Power = Config.powerForLevel(50), Coins = 12450, Tokens = 8, Quests = { day = 0, list = {} } })

----------------------------------------------------------------------
-- walking up to the Spire's doors opens it, on the floor you're up to
----------------------------------------------------------------------
me:SetAttribute("SpireCleared", 2)
local DOORS = Vector3.new(0, 4, -120)
local zone = Instance.new("Part")
zone.Name = "AutoOpenZone"
zone.Size = Vector3.new(16, 8, 10)
zone.CFrame = CFrame.new(DOORS)
zone:SetAttribute("Spire", "Menu")
zone.Parent = M.workspace
CollectionService:AddTag(zone, "AutoOpenZone")
wait(0.3)
check(Menus.current() == nil, "nothing open away from the doors")
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
check(Menus.current() == "Spire", "walking up to the doors opens the Spire menu")
check(playerGui.Menus.Root.Title.Text == "The Spire", "titled The Spire, like the other menus")
check(find("Tab_Normal", playerGui.Menus.Root) ~= nil and find("Tab_Doom", playerGui.Menus.Root) ~= nil, "a tab for each Spire: Normal ... Doom")
local floors = find("Floors")
local cards = 0
for _, c in ipairs(floors and floors:GetChildren() or {}) do
	if c.Name == "GroundFloor" or string.match(c.Name, "^Floor%d+$") then
		cards += 1
	end
end
check(cards == #F + 1, "a card for the ground floor and every floor (" .. cards .. ")")
local detail = find("Detail")
check(detail ~= nil and textOf("BossName", detail) == F[3].boss, "it opens on floor 3, the one you're up to (" .. textOf("BossName", detail) .. ")")
check(textOf("Blurb", detail) == F[3].blurb, "the whole blurb, not cut off")
check(textOf("Recommended", detail) == "RECOMMENDED LV " .. F[3].level and textOf("You", detail) == "YOU LV 50", "the level it wants and yours")
check(textOf("State", detail) == "READY", "READY (" .. textOf("State", detail) .. ")")
check(find("Floor3", floors).Face:GetAttribute("Picked") == true, "its card is picked (the yellow edge)")
check(textOf("State", find("Floor1", floors)) == "BEATEN" and textOf("State", find("Floor2", floors)) == "BEATEN", "the floors you've beaten say so")
check(find("Lock", find("Floor5", floors)) ~= nil and find("Lock", find("Floor3", floors)) == nil, "the ones not open yet have a lock")
local enter = find("Enter", detail)
check(enter and enter.Text == "ENTER" and enter.Active ~= false, "a big ENTER")
snap("THE SPIRE|the floors as cards, the one you're up to, big, and ENTER")
-- walking away closes it; back in, it opens again
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
check(Menus.current() == nil, "walking away closes it")
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
check(Menus.current() == "Spire", "back at the doors, it opens again")
-- Esc closes it, and it stays closed while you stand there
Menus.close()
wait(0.5)
check(Menus.current() == nil, "closed by hand, it stays closed while you stand there")
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
check(Menus.current() == "Spire", "step out and back in: it opens again")

----------------------------------------------------------------------
-- tapping a card shows it; a beaten floor; a locked floor; ENTER
----------------------------------------------------------------------
tap("Floor1")
detail = find("Detail")
check(textOf("BossName", detail) == F[1].boss and textOf("State", detail) == "BEATEN", "tapping floor 1 shows it: BEATEN")
check(find("Enter", detail).Text == "ENTER", "a beaten floor can be fought again: ENTER (not greyed out)")
tap("Floor6")
detail = find("Detail")
check(textOf("State", detail) == "LOCKED", "floor 6: LOCKED")
check(string.find(textOf("Note", detail), "Beat ", 1, true) ~= nil, "and says who to beat first (" .. textOf("Note", detail) .. ")")
enter = find("Enter", detail)
check(enter.Text == "LOCKED" and enter.Active == false, "ENTER says LOCKED and can't be pressed")
table.clear(travelled)
click(enter)
check(#travelled == 0 and Menus.current() == "Spire", "pressing it does nothing")
tap("Floor3")
click(find("Enter", find("Detail")))
wait(1) -- (the screen fades to black first)
check(travelled[1] == "enter:3", "ENTER asks the server to go up to floor 3 (" .. tostring(travelled[1]) .. ")")
check(Menus.current() == nil, "and the menu closes")
wait(2)

----------------------------------------------------------------------
-- too low: TRAIN FIRST; the ground floor's TRAIN
----------------------------------------------------------------------
levelValue.Value = 8
me:SetAttribute("SpireCleared", 0)
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
detail = find("Detail")
check(textOf("BossName", detail) == F[1].boss and textOf("State", detail) == "TOO LOW", "Lv 8 for floor 1: TOO LOW")
check(textOf("You", detail) == "YOU LV 8", "your level, in red")
check(find("TrainFirst", detail) ~= nil, "TRAIN FIRST beside ENTER")
snap("THE SPIRE · TOO LOW|under the floor's level: TRAIN FIRST in the Colosseum")
table.clear(travelled)
click(find("TrainFirst", detail))
check(travelled[1] == "colosseum", "TRAIN FIRST takes you to the Colosseum (" .. tostring(travelled[1]) .. ")")
check(Menus.current() == nil, "and closes the menu")
wait(0.5)
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
tap("GroundFloor")
detail = find("Detail")
check(textOf("BossName", detail) == "The Colosseum" and textOf("FloorChip", detail) == "GROUND FLOOR", "the ground floor: the Colosseum")
check(string.find(textOf("State", detail), "% XP", 1, true) ~= nil, "with its training bonus (" .. textOf("State", detail) .. ")")
check(string.find(textOf("TrainingFor", detail), string.upper(string.match(F[1].boss, "^[^,]+")), 1, true) ~= nil, "training for floor 1's boss (" .. textOf("TrainingFor", detail) .. ")")
snap("THE SPIRE · GROUND FLOOR|the Colosseum: what you're training for, the XP bonus, TRAIN")
table.clear(travelled)
-- a refusal shows why, as a toast
travelAnswer = { false, "Stand at the Spire's doors to enter." }
click(find("Train", detail))
check(travelled[1] == "colosseum", "TRAIN asks to go in")
check(string.find(toasts(), "Stand at the Spire's doors", 1, true) ~= nil, "the server's no shows as a toast (" .. toasts() .. ")")
travelAnswer = { true }
wait(3)

----------------------------------------------------------------------
-- in a party: only the leader picks
----------------------------------------------------------------------
levelValue.Value = 50
me:SetAttribute("SpireCleared", 2)
me:SetAttribute("PartyLeader", friend.UserId)
friend:SetAttribute("PartyLeader", friend.UserId)
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
detail = find("Detail")
enter = find("Enter", detail)
check(enter.Text == "LEADER PICKS" and enter.Active == false, "in someone's party: LEADER PICKS")
check(string.find(textOf("Note", detail), "Alpha", 1, true) ~= nil, "and says who (" .. textOf("Note", detail) .. ")")
me:SetAttribute("PartyLeader", me.UserId)
friend:SetAttribute("PartyLeader", me.UserId)
wait(0.3)
detail = find("Detail")
check(find("Enter", detail).Text == "ENTER" and string.find(textOf("Note", detail), "party of 2", 1, true) ~= nil, "leading it: ENTER, and your party comes with you (" .. textOf("Note", detail) .. ")")
me:SetAttribute("PartyLeader", nil)
friend:SetAttribute("PartyLeader", nil)
Menus.close()
wait(0.3)

----------------------------------------------------------------------
-- in the arena: LEAVE ARENA, and the "Leave?" check
----------------------------------------------------------------------
local win = playerGui:FindFirstChild("SpireWindows")
check(win ~= nil and win:GetAttribute("RetroSkip") == true, "the arena's buttons are in the new look (RetroUI leaves them alone)")
local leaveBtn = find("LeaveArena", win)
check(leaveBtn and not leaveBtn.Visible, "no LEAVE ARENA in the lobby")
hrp.CFrame = CFrame.new(0, 3, 2600)
me:SetAttribute("SpireFloor", 3)
wait(0.3)
check(leaveBtn.Visible, "LEAVE ARENA in the arena")
local confirm = find("ConfirmLeave", win)
click(leaveBtn)
check(confirm.Visible, "it asks first")
check(string.find(textOf("Words", confirm), F[3].area, 1, true) ~= nil, "naming the arena (" .. textOf("Words", confirm) .. ")")
if SNAPS then
	snapGui(win, "THE SPIRE · LEAVE?|in the arena: STAY or LEAVE", 1280, 720)
end
click(find("Stay", confirm))
check(not confirm.Visible, "STAY closes it")
spireEvent.OnClientEvent:Fire("ConfirmLeave")
wait(0.2)
check(confirm.Visible, "touching the fog gate asks too")
table.clear(travelled)
click(find("Leave", confirm))
wait(1) -- (the screen fades to black first)
check(travelled[1] == "leave", "LEAVE asks the server (" .. tostring(travelled[1]) .. ")")
me:SetAttribute("SpireFloor", nil)
wait(2)
check(not leaveBtn.Visible and not confirm.Visible, "back in the lobby: both gone")

----------------------------------------------------------------------
-- THE HARDER SPIRE: Nightmare, Eclipse, Doom
----------------------------------------------------------------------
me:SetAttribute("SpireCleared", 2)
levelValue.Value = 50
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
click(find("Tab_Nightmare", playerGui.Menus.Root))
detail = find("Detail")
check(textOf("TierChip", detail) == "NIGHTMARE", "the Nightmare tab: its floors, marked NIGHTMARE")
check(textOf("Recommended", detail) == "RECOMMENDED LV " .. Config.spireLevel(3, "Nightmare"), "at Nightmare's levels (" .. textOf("Recommended", detail) .. ")")
check(textOf("State", detail) == "LOCKED" and string.find(textOf("Note", detail), "whole Spire on NORMAL", 1, true) ~= nil, "locked until Normal is beaten to the top (" .. textOf("Note", detail) .. ")")
-- beat Normal: Nightmare opens, and the menu opens on it
me:SetAttribute("SpireCleared", 10)
levelValue.Value = 170
Menus.close()
hrp.CFrame = CFrame.new(DOORS + Vector3.new(0, 0, 40))
wait(0.3)
hrp.CFrame = CFrame.new(DOORS)
wait(0.3)
check(select(2, Menus.current()) == "Nightmare", "with Normal beaten, it opens on Nightmare (" .. tostring(select(2, Menus.current())) .. ")")
detail = find("Detail")
check(textOf("BossName", detail) == F[1].boss and textOf("State", detail) == "READY", "on its floor 1, READY at Lv 170")
snap("THE SPIRE · NIGHTMARE|the harder Spire: the same floors at Nightmare's levels")
table.clear(travelled)
click(find("Enter", detail))
wait(1)
check(travelled[1] == "enter:1" and travelTier[#travelTier] == "Nightmare", "ENTER goes up floor 1 on Nightmare (" .. tostring(travelled[1]) .. ", " .. tostring(travelTier[#travelTier]) .. ")")
wait(2)
check(Config.spireTierHealth(10, "Doom") > 1.8 and Config.spireTierDamage(10, "Doom") > 2, "Doom's bosses: tougher and harder-hitting than their level alone")
check(Config.levelsWorth(150, 1) == Config.powerForLevel(151) - Config.powerForLevel(150), "a level's worth of Power")

check(#M.errors == 0, "no errors (" .. #M.errors .. ")")
for i = 1, math.min(5, #M.errors) do
	print("    " .. tostring(M.errors[i]))
end
print(fails == 0 and "PASS  test_spire_menu: the Spire menu in the new look" or ("FAILED: " .. fails))
