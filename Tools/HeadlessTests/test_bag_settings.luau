--!nocheck
-- Headless test of THE BAG and THE SETTINGS (BagMenu.client.lua,
-- SettingsMenu.client.lua) in the see-through menus, with a pretend server:
--   * THE BAG: the weapon in your hand, big (name, mastery, its one ability
--     on [F] and what the next mastery tier adds, IN HAND, FISTS); every
--     weapon you own rarest first with the green E on the one in your hand;
--     tapping one shows it with EQUIP (EquipWeapon); the rarity filter; LOOKS
--     is the shop's page; B opens the Bag
--   * THE SETTINGS: your saved settings are put into effect when your data
--     arrives; each switch saves (SaveSettings) and works at once - music and
--     sound effects (the sound groups), shadows, low graphics (shadows and
--     the light's effects), hiding others' effects (and their ability effects
--     really aren't drawn: AbilityFX), camera shake
--   luau test_bag_settings.luau -a snaps    ...also prints snapshots for render_gui.py
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum, CFrame = M.Instance, M.Enum, M.CFrame
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage
local SoundService, Lighting = M.services.SoundService, M.services.Lighting
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
local other = newPlayer("Other", 1002)
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

-- the mix's sound groups, and the light's effects
local groups = {}
for name, vol in pairs({ Music = 0.7, Effects = 1, UI = 0.8 }) do
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = vol
	g.Parent = SoundService
	groups[name] = g
end
Lighting.GlobalShadows = true
local bloom = Instance.new("BloomEffect")
bloom.Enabled = true
bloom.Parent = Lighting

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
-- (AbilityFX listens here for everyone's ability effects)
local combatRemotes = Instance.new("Folder")
combatRemotes.Name = "CombatRemotes"
combatRemotes.Parent = ReplicatedStorage
local abilityFx = Instance.new("RemoteEvent")
abilityFx.Name = "AbilityFx"
abilityFx.Parent = combatRemotes
local asked, saved = {}, nil
M.onInvokeServer = function(_, name, arg)
	if name == "SaveSettings" then
		saved = arg
	end
	table.insert(asked, tostring(name) .. (arg ~= nil and type(arg) ~= "table" and (":" .. tostring(arg)) or ""))
	return true, nil
end
local function askedFor(s)
	return table.find(asked, s) ~= nil
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local W = Config.Weapons
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
local MoveFX = mount.require(mount.module("ReplicatedStorage/MoveFX.lua"))
local toldFor = {}
MoveFX.told = function(player)
	table.insert(toldFor, player)
end
local opened = {}
Menus.external.Gear = function()
	opened.Gear = true
end
mount.runClient("StarterPlayerScripts/ShopMenu.client.lua", me)
mount.runClient("StarterPlayerScripts/BagMenu.client.lua", me)
mount.runClient("StarterPlayerScripts/SettingsMenu.client.lua", me)
mount.runClient("StarterPlayerScripts/WeaponBag.client.lua", me)
mount.runClient("StarterPlayerScripts/AbilityFX.client.lua", me)
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
local slime = W.Packs[1].Weapons
local own = { IronSword = Config.masteryPointsFor(3), [slime[1]] = 0, [slime[2]] = Config.masteryPointsFor(12), [slime[5]] = 0 }
local function snapshot(over)
	local d = {
		Power = Config.powerForLevel(12), Coins = 4000, Tokens = 2, Chests = { [1] = 2 },
		Weapons = { own = own }, Quests = { day = 0, list = {} }, Rewards = {},
		Tickets = { Revive = 0, Rush = 0 }, Boosts = { XP = 0, Coins = 0, Luck = 0 },
		Shop = { starter = true, receipts = {}, daily = {} },
		Looks = { titles = { Loyal = true }, auras = {} },
		Settings = { music = false, sfx = true, shadows = true, hideOthers = false, shake = true, low = false, revives = true, rush = true },
	}
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
local function tab(name)
	find("Tab_" .. name, playerGui.Menus.Root).Activated:Fire()
	wait(0.2)
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
-- your saved settings take effect when your data arrives
----------------------------------------------------------------------
me:SetAttribute("Weapon", "IronSword")
send(snapshot())
check(groups.Music.Volume == 0, "saved: music off - the music group is silent")
check(groups.Effects.Volume == 1 and groups.UI.Volume == 0.8, "sound effects stay on")

----------------------------------------------------------------------
-- THE BAG
----------------------------------------------------------------------
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B }, false)
wait(0.2)
check(Menus.current() == "Bag", "B opens the Bag")
local detail = find("Detail")
check(detail and find("WeaponName", detail).Text == "Iron Sword", "the weapon in your hand, big")
check(find("InHand", detail) ~= nil and find("Fists", detail) ~= nil, "IN HAND, and FISTS to put it away")
check(string.find(find("Mastery", detail):FindFirstChild("Text").Text, "MASTERY 3") ~= nil, "its mastery (" .. find("Mastery", detail):FindFirstChild("Text").Text .. ")")
check(find("Key", detail).Text == "F" and string.find(find("Ability", detail).Text, W.List.IronSword.Ability.Name) ~= nil, "its one ability, on F")
check(find("Now", detail).Text == W.List.IronSword.Ability.Say[1], "what it does now")
check(find("Next", detail) and string.find(find("Next", detail).Text, "At mastery 25") ~= nil, "and what the next mastery tier adds")
-- the grid: rarest first, the E on the one in your hand
local order = {}
for _, c in ipairs(find("Grid"):GetChildren()) do
	if c.Name ~= "UIGridLayout" then
		order[c.LayoutOrder] = c.Name
	end
end
check(order[1] == slime[5] and W.List[order[#order]].Rarity == "Common", "rarest first (" .. tostring(order[1]) .. " ... " .. tostring(order[#order]) .. ")")
check(find("Equipped", find("IronSword", find("Grid"))) ~= nil, "the E on the one in your hand")
snap("THE BAG · WEAPONS|the one in your hand, its [F] ability and next tier; every weapon you own")
asked = {}
click(find("Tap", find(slime[2], find("Grid"))))
detail = find("Detail")
check(find("WeaponName", detail).Text == W.List[slime[2]].Name, "tapping a weapon shows it")
check(string.find(find("Mastery", detail):FindFirstChild("Text").Text, "MASTERY 12") ~= nil, "with its own mastery")
click(find("Equip", detail))
check(askedFor("EquipWeapon:" .. slime[2]), "EQUIP asks the server for it")
me:SetAttribute("Weapon", nil)
wait(0.2)
click(find("Tap", find("IronSword", find("Grid"))))
click(find("Filter_Common"))
local commons, others = 0, 0
for _, c in ipairs(find("Grid"):GetChildren()) do
	if W.List[c.Name] then
		if W.List[c.Name].Rarity == "Common" then
			commons += 1
		else
			others += 1
		end
	end
end
check(commons > 0 and others == 0, "the filter shows only that rarity")
click(find("Filter_All"))
check(find("Tab_Stats", playerGui.Menus.Root) == nil and find("Tab_Gear", playerGui.Menus.Root) == nil, "no Stats or Gear tab")
Menus.open("Bag", "Looks")
check(find("Title_Loyal") ~= nil, "LOOKS: the shop's looks page")
Menus.close()

----------------------------------------------------------------------
-- THE SETTINGS
----------------------------------------------------------------------
check(Menus.open("Settings"), "the settings open")
local musicRow = find("Setting_music")
check(musicRow and find("Switch", musicRow).Text == "OFF", "music shows OFF (as saved)")
snap("SETTINGS · SOUND|each a switch, saved with your data")
click(find("Switch", musicRow))
check(groups.Music.Volume == 0.7, "music back on: the group at its full volume")
check(saved and saved.music == true, "and it's saved")
click(find("Switch", find("Setting_sfx")))
check(groups.Effects.Volume == 0 and groups.UI.Volume == 0 and groups.Music.Volume == 0.7, "sound effects off: the effects and UI groups go quiet")
tab("Graphics")
click(find("Switch", find("Setting_shadows")))
check(Lighting.GlobalShadows == false, "shadows off")
click(find("Switch", find("Setting_shadows")))
check(Lighting.GlobalShadows == true, "shadows back")
click(find("Switch", find("Setting_low")))
check(Lighting.GlobalShadows == false and bloom.Enabled == false, "low graphics: no shadows, no bloom")
click(find("Switch", find("Setting_low")))
check(Lighting.GlobalShadows == true and bloom.Enabled == true, "and back")
click(find("Switch", find("Setting_shake")))
check(me:GetAttribute("NoShake") == true, "camera shake off")
snap("SETTINGS · GRAPHICS|shadows, low graphics, others' effects, camera shake")
-- others' ability effects: drawn, then not
abilityFx.OnClientEvent:Fire(other, "Test", 1, 1)
wait(0.1)
check(#toldFor == 1, "another player's ability effect is drawn")
click(find("Switch", find("Setting_hideOthers")))
check(me:GetAttribute("HideOthersFX") == true, "hide others' effects on")
abilityFx.OnClientEvent:Fire(other, "Test", 1, 1)
abilityFx.OnClientEvent:Fire(me, "Test", 1, 1)
wait(0.1)
check(#toldFor == 2 and toldFor[2] == me, "then only your own are drawn")
tab("Fights")
check(find("Setting_revives") and find("Setting_rush"), "the tickets' switches")
click(find("Switch", find("Setting_revives")))
check(saved and saved.revives == false, "revives off is saved (the server reads it)")
Menus.close()

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings")
if fails == 0 then
	print("PASS  test_bag_settings: the Bag (weapons, [F] ability, equip, filter, looks) and the Settings")
else
	print("FAILED: " .. fails)
end
