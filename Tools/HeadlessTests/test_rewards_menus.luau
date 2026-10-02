--!nocheck
-- Headless test of THE REWARDS MENU and THE INDEX (RewardsMenu.client.lua,
-- IndexMenu.client.lua) in the see-through menus (ReplicatedStorage/Menus),
-- with a pretend server:
--   * LOGIN: seven day cards; today's CLAIM (asks RewardLogin); claimed days;
--     "tomorrow" once today's is claimed; a missed day starts again at day 1
--   * GIFT: the clock counting down, CLAIM only when it's ready (RewardGift)
--   * CODES: what you type is sent (RewardCode) and kept when the page is
--     drawn again; the codes you've used
--   * UPDATES: the notes, CLAIM GIFT (RewardUpdate); the newest update opens
--     by itself for a returning player (RewardSeen) but not a brand-new one
--   * THE COMMUNITY CHEST: walking up opens its window, CLAIM (GroupClaim),
--     walking away closes it
--   * THE INDEX: every pack's weapons (found: name; not found: "???"), CLAIM
--     a new find (IndexClaim), the bosses (beaten or not), the collector bar
--     and its rewards (CollectorClaim)
--   luau test_rewards_menus.luau -a snaps    ...also prints snapshots for render_gui.py
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
M.services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
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

-- the community chest's walk-up box
local zone = Instance.new("Part")
zone.Name = "AutoOpenZone"
zone.Size = Vector3.new(14, 8, 7)
zone.CFrame = CFrame.new(-50, 4, 12)
zone:SetAttribute("Activity", "Community")
zone.Parent = M.workspace
CollectionService:AddTag(zone, "AutoOpenZone")
-- and the chest itself: its lid (shut, the hinge saved on it) and a ray
local chestModel = Instance.new("Model")
chestModel.Name = "CommunityChest"
local lidModel = Instance.new("Model")
lidModel.Name = "Lid"
local HINGE = CFrame.new(-50, 4.4, 20.05)
lidModel:SetAttribute("Hinge", HINGE)
lidModel.Parent = chestModel
local lidPart = Instance.new("Part")
lidPart.Name = "Lid"
lidPart.CFrame = HINGE * CFrame.new(0, 0.45, -2.05)
lidPart.Parent = lidModel
local LID_SHUT = lidPart.CFrame
local ray = Instance.new("Part")
ray.Name = "Ray"
ray.Transparency = 1
ray:SetAttribute("Shine", 0.78)
ray.Parent = chestModel
chestModel.Parent = M.workspace

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
local asked = {}
M.onInvokeServer = function(_, name, arg)
	table.insert(asked, tostring(name) .. (arg ~= nil and (":" .. tostring(arg)) or ""))
	return true, nil
end
local function askedFor(s)
	return table.find(asked, s) ~= nil
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local R = Config.Rewards
if SNAPS then
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
local Menus = mount.require(mount.module("ReplicatedStorage/Menus.lua"))
mount.runClient("StarterPlayerScripts/RewardsMenu.client.lua", me)
mount.runClient("StarterPlayerScripts/IndexMenu.client.lua", me)
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
local slimeIds = Config.Weapons.Packs[1].Weapons
local function snapshot(rw, over)
	local d = {
		Power = 5000, Coins = 12450, Tokens = 8, QuestsDone = 3, Cleared = { ["1"] = 2 },
		Weapons = { own = { IronSword = 0, [slimeIds[1]] = 0, [slimeIds[2]] = 0 } }, Quests = { day = 0, list = {} },
		Rewards = { streak = 2, streakDay = today - 1, giftPlay = 0, gifts = 0, giftsToday = 0, codes = { LAUNCH = true }, updates = {}, index = { IronSword = true }, milestones = {}, seen = R.Updates[1].Id },
	}
	for k, v in pairs(rw or {}) do
		d.Rewards[k] = v
	end
	for k, v in pairs(over or {}) do
		d[k] = v
	end
	return d
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
	return (root or page()):FindFirstChild(name, true)
end
local function button(parent)
	return parent and parent:FindFirstChildWhichIsA("TextButton", true)
end
local function click(b)
	check(b ~= nil, "a button to press")
	if b then
		b.Activated:Fire()
		wait(0.2)
	end
end
local function snap(caption)
	if SNAPS then
		snapGui(playerGui:FindFirstChild("Menus"), caption, 1280, 720)
	end
end

----------------------------------------------------------------------
-- LOGIN
----------------------------------------------------------------------
send(snapshot())
check(Menus.open("Rewards"), "the Rewards menu opens")
for i = 1, 7 do
	check(find("Day" .. i) ~= nil, "day " .. i .. "'s card")
end
check(find("Claimed", find("Day1")) and find("Claimed", find("Day2")), "days 1 and 2 are claimed")
local claim = find("Claim", find("Day3"))
check(claim ~= nil, "day 3 can be claimed today")
check(find("Claim", find("Day4")) == nil, "day 4 can't yet")
check(string.find(find("Reward", find("Day7")).Text, "TOKENS") ~= nil, "day 7 shows its tokens")
snap("REWARDS · LOGIN|seven days, today's claim, the streak")
click(claim)
check(askedFor("RewardLogin"), "CLAIM asks the server")
send(snapshot({ streak = 3, streakDay = today }))
check(find("Claimed", find("Day3")) ~= nil and find("Tomorrow", find("Day4")) ~= nil, "claimed today: day 4 is tomorrow")
send(snapshot({ streak = 5, streakDay = today - 3 }))
check(find("Claim", find("Day1")) ~= nil and find("Claimed", find("Day1")) == nil, "a missed day: back to day 1")

----------------------------------------------------------------------
-- GIFT
----------------------------------------------------------------------
local need = R.GiftMinutes * 60
send(snapshot({ giftPlay = need - 30, gifts = 1, giftsToday = 1 }))
find("Tab_Gift", playerGui.Menus.Root).Activated:Fire()
wait(0.3)
local time = find("Time", find("GiftCard"))
check(time and (time.Text == "0:30" or time.Text == "0:29"), "the gift's clock (" .. tostring(time and time.Text) .. ")")
check(find("Gift1") and string.find(find("Reward", find("Gift1")).Text, "600") ~= nil, "the next gift is the second (600 coins)")
snap("REWARDS · FREE GIFT|its clock, today's count, what's next")
asked = {}
click(find("Claim", find("GiftCard")))
check(not askedFor("RewardGift"), "not ready: CLAIM does nothing")
wait(31)
time = find("Time", find("GiftCard"))
check(time.Text == "READY!", "then it's ready (" .. time.Text .. ")")
click(find("Claim", find("GiftCard")))
check(askedFor("RewardGift"), "CLAIM asks for it")

----------------------------------------------------------------------
-- CODES
----------------------------------------------------------------------
find("Tab_Codes", playerGui.Menus.Root).Activated:Fire()
wait(0.2)
local box = find("Code")
check(box ~= nil and box.ClassName == "TextBox", "a box to type the code in")
box.Text = "walrus"
send(snapshot())
box = find("Code")
check(box.Text == "walrus", "what you typed stays when the page is drawn again")
asked = {}
click(find("Redeem"))
check(askedFor("RewardCode:walrus"), "REDEEM sends the code")
local words = find("Words")
check(words and string.find(words.Text, "LAUNCH") ~= nil, "the codes you've used")
snap("REWARDS · CODES|type a code, redeem it")

----------------------------------------------------------------------
-- UPDATES
----------------------------------------------------------------------
find("Tab_Updates", playerGui.Menus.Root).Activated:Fire()
wait(0.2)
local card = find("Update" .. R.Updates[1].Id)
check(card ~= nil, "the newest update's card")
check(card and string.find(find("Title", card).Text, string.upper(R.Updates[1].Title)) ~= nil, "with its title")
snap("REWARDS · UPDATES|what's new, and its gift")
asked = {}
click(find("Claim", card))
check(askedFor("RewardUpdate:" .. R.Updates[1].Id), "CLAIM GIFT asks for the update's gift")
Menus.close()

----------------------------------------------------------------------
-- THE COMMUNITY CHEST
----------------------------------------------------------------------
hrp.CFrame = CFrame.new(-50, 3, 12)
wait(0.5)
check(Menus.current() == "Community", "walking up to the chest opens its window")
wait(1)
local lifted = lidPart.Position.Y - LID_SHUT.Position.Y
check(lifted > 1, "and its lid swings open (the front up " .. string.format("%.2f", lifted) .. ")")
check((lidPart.Position - HINGE.Position).Magnitude - (LID_SHUT.Position - HINGE.Position).Magnitude < 0.01, "round its hinge")
check(ray.Transparency < 0.9, "the light shines out")
snap("THE COMMUNITY CHEST|join, then claim once")
asked = {}
click(find("Claim", find("ChestCard")))
check(askedFor("GroupClaim"), "CLAIM asks the server")
hrp.CFrame = CFrame.new(0, 3, 0)
wait(0.5)
check(Menus.current() == nil, "walking away closes it")
wait(2)
check((lidPart.Position - LID_SHUT.Position).Magnitude < 0.05, "and the lid falls shut")
check(ray.Transparency > 0.98, "the light goes out")

----------------------------------------------------------------------
-- THE INDEX
----------------------------------------------------------------------
check(Menus.open("Index"), "the Index opens")
local first = find(slimeIds[1])
check(first ~= nil and find("WeaponName", first).Text == Config.Weapons.List[slimeIds[1]].Name, "a weapon you've found shows its name")
local missing = find(slimeIds[4])
check(missing ~= nil and find("WeaponName", missing).Text == "???", "one you haven't is ???")
check(find("Rarity", missing).Text == string.upper(Config.Weapons.List[slimeIds[4]].Rarity), "but shows its rarity")
check(find("Done", find("IronSword")) ~= nil, "a claimed one is IN INDEX")
snap("THE INDEX · WEAPONS|found, not found, claim a new find, the collector bar")
asked = {}
click(find("Claim", first))
check(askedFor("IndexClaim:" .. slimeIds[1]), "CLAIM asks for the find's reward")
find("Tab_Bosses", playerGui.Menus.Root).Activated:Fire()
wait(0.2)
check(find("Floor1") and find("Chip", find("Floor1")).Text == "BEATEN x2", "floor 1: beaten twice")
check(find("Floor2") and find("Chip", find("Floor2")).Text == "LV " .. Config.Spire.Floors[2].level, "floor 2: its level")
snap("THE INDEX · BOSSES|beaten, still to beat")
find("Tab_Collector", playerGui.Menus.Root).Activated:Fire()
wait(0.2)
-- 3 weapons (30) + 1 boss (20) = 50: collector level 2
check(find("Level", find("Collector")).Text == "COLLECTOR LV 2", "the collector level (" .. tostring(find("Level", find("Collector")).Text) .. ")")
local lv2 = find("Level2")
check(lv2 and find("Claim", lv2) ~= nil, "level 2's reward can be claimed")
check(find("Claim", find("Level3")) == nil, "level 3's can't yet")
snap("THE INDEX · COLLECTOR|the bar and its rewards")
asked = {}
click(find("Claim", lv2))
check(askedFor("CollectorClaim:2"), "CLAIM asks for it")
Menus.close()

----------------------------------------------------------------------
-- The newest update opens by itself (once, for a returning player)
----------------------------------------------------------------------
asked = {}
send(snapshot({ seen = "" }))
wait(5)
check(Menus.current() == "Rewards" and select(2, Menus.current()) == "Updates", "the newest update opens by itself")
check(askedFor("RewardSeen:" .. R.Updates[1].Id), "and is marked seen")
Menus.close()

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings")
if fails == 0 then
	print("PASS  test_rewards_menus: login, gift, codes, updates, the community chest, the Index")
else
	print("FAILED: " .. fails)
end
