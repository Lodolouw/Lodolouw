--!nocheck
-- PICTURES OF A PHONE'S SCREEN in a fight: the real Hud (the heart, the
-- potion, the bolt), CombatClient (the touch buttons: ATTACK, JUMP, ROLL,
-- SKILL, the potion, LOCK), the boss bar (BossClient) and a boss's speech
-- bubble (BossIntro) on a phone, laid out the way Roblox does it - each
-- ScreenGui on the part of the screen it gets (a notched phone keeps them
-- out of the notch and off the home bar) - for render_gui.py to paint.
--   luau phone_snaps.luau [-a WxH] > snaps.txt
--   python3 render_gui.py snaps.txt ../../Docs/phone_fight.png --size 844x390
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local snapGui = require("./gui_snap")
local Instance, Enum, Vector3, CFrame = M.Instance, M.Enum, M.Vector3, M.CFrame
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage
local CollectionService = M.services.CollectionService

local args = { ... }
local SW, SH = 844, 390
if args[1] then
	local w, h = string.match(args[1], "^(%d+)x(%d+)$")
	SW, SH = tonumber(w) or SW, tonumber(h) or SH
end

RunService.IsStudio = function()
	return false
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
	TouchEnabled = true,
	KeyboardEnabled = false,
	GamepadEnabled = false,
	MouseEnabled = false,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	TouchStarted = M.Signal.new(),
	TouchEnded = M.Signal.new(),
	TouchMoved = M.Signal.new(),
	TouchSwipe = M.Signal.new(),
	JumpRequest = M.Signal.new(),
	LastInputTypeChanged = M.Signal.new(),
	GetLastInputType = function()
		return Enum.UserInputType.Touch
	end,
	IsKeyDown = function()
		return false
	end,
	IsMouseButtonPressed = function()
		return false
	end,
	GetMouseLocation = function()
		return { X = SW / 2, Y = SH / 2 }
	end,
}

local me = Instance.new("Player")
me.Name = "Tester"
me.DisplayName = "Tester"
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
local stats = Instance.new("Folder")
stats.Name = "leaderstats"
stats.Parent = me
local lv = Instance.new("IntValue")
lv.Name = "Level"
lv.Value = 16
lv.Parent = stats
local char = Instance.new("Model")
char.Name = "Tester"
local hum = Instance.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 72
hum.WalkSpeed = 16
hum.StateChanged = M.Signal.new()
hum.Jumping = M.Signal.new()
hum.Parent = char
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.Parent = char
char.Parent = M.workspace
me.Character = char
local cam = Instance.new("Camera")
cam.ViewportSize = { X = SW, Y = SH }
cam.FieldOfView = 70
cam.CFrame = CFrame.lookAt(Vector3.new(0, 14, 34), Vector3.new(0, 8, 0))
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam

-- Roblox's own touch controls: the jump button where it puts it on a phone
local tg = Instance.new("ScreenGui")
tg.Name = "TouchGui"
tg.Parent = playerGui
local tcf = Instance.new("Frame")
tcf.Name = "TouchControlFrame"
tcf.Size = M.UDim2.fromScale(1, 1)
tcf.BackgroundTransparency = 1
tcf.Parent = tg
local jump = Instance.new("ImageButton")
jump.Name = "JumpButton"
jump.Position = M.UDim2.new(1, -95, 1, -90)
jump.Size = M.UDim2.fromOffset(70, 70)
jump.BackgroundTransparency = 0.5
jump.BackgroundColor3 = M.Color3.fromRGB(255, 255, 255)
jump.Parent = tcf
local jc = Instance.new("UICorner")
jc.CornerRadius = M.UDim.new(1, 0)
jc.Parent = jump

M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
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
local combatRemotes = Instance.new("Folder")
combatRemotes.Name = "CombatRemotes"
combatRemotes.Parent = ReplicatedStorage
local combatEvent
for _, n in ipairs({ "CombatAction", "CombatEvent" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = combatRemotes
	if n == "CombatEvent" then
		combatEvent = r
	end
end
M.onInvokeServer = function()
	return true, nil
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
for _, path in ipairs({
	"StarterPlayerScripts/Hud.client.lua",
	"StarterPlayerScripts/LobbyHud.client.lua",
	"StarterPlayerScripts/CombatClient.client.lua",
	"StarterPlayerScripts/BossClient.client.lua",
	"StarterPlayerScripts/BossIntro.client.lua",
}) do
	mount.runClient(path, me)
end

local T = 0
local function wait(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += 1 / 30
		M.run(T)
		RunService.Heartbeat:Fire(1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
		if RunService.Stepped then
			RunService.Stepped:Fire(T, 1 / 30)
		end
	end
end
-- every ScreenGui that's on, bottom to top, as one picture
local function snapScreen(caption)
	local order = {}
	for _, g in ipairs(playerGui:GetChildren()) do
		if g.ClassName == "ScreenGui" and g.Enabled ~= false then
			table.insert(order, g)
		end
	end
	table.sort(order, function(a, b)
		return (a.DisplayOrder or 0) < (b.DisplayOrder or 0)
	end)
	for i, g in ipairs(order) do
		snapGui(g, i == 1 and caption or nil, SW, SH)
	end
end

wait(1)
snapScreen("THE LOBBY ON A PHONE|" .. SW .. "x" .. SH)

-- into a fight, on floor 1, with a weapon (so its SKILL button shows)
local weaponId = nil
local ids = {}
for id, def in pairs(Config.Weapons.List) do
	if type(def) == "table" and def.Ability then
		table.insert(ids, id)
	end
end
table.sort(ids)
weaponId = ids[1]
me:SetAttribute("Weapon", weaponId)
me:SetAttribute("SpireFloor", 1)
me:SetAttribute("InFight", true)
combatEvent.OnClientEvent:Fire("State", 80, 100, 3)
wait(1.5)

snapScreen("A FIGHT ON A PHONE|" .. SW .. "x" .. SH .. ", a weapon with a skill")

-- the boss wakes and talks: its bar across the top, its words in a bubble
-- over its head (BossClient and BossIntro, as they draw them)
local boss = Instance.new("Model")
boss.Name = "Boss_Oozark"
local broot = Instance.new("Part")
broot.Name = "Root"
broot.Size = Vector3.new(6, 6, 6)
broot.CFrame = CFrame.new(0, 3, -12)
broot.Transparency = 1
broot.Parent = boss
boss.PrimaryPart = broot
boss:SetAttribute("Floor", 1)
boss:SetAttribute("MaxHealth", 1000)
boss:SetAttribute("Health", 640)
boss:SetAttribute("State", "Dormant")
boss.Parent = M.workspace
CollectionService:AddTag(boss, "Boss")
wait(0.2)
math.randomseed(4)
boss:SetAttribute("State", "Waking")
local head = Vector3.new(0, 10, -12)
local stop = T + 4.2
while T < stop do
	T += 1 / 30
	M.run(T)
	boss:SetAttribute("HeadAt", head)
	boss:SetAttribute("AimTime", os.clock())
	RunService.Heartbeat:Fire(1 / 30)
	RunService.RenderStepped:Fire(1 / 30)
	if RunService.Stepped then
		RunService.Stepped:Fire(T, 1 / 30)
	end
end
snapScreen("A BOSS TALKING ON A PHONE|" .. SW .. "x" .. SH .. ": its bar, its words over its head")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
