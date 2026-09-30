--!nocheck
-- Headless test of the HUD's ARCADE TOKENS (Hud.client.lua): your tokens
-- bottom-left where the backpack count was, clicking them opens the Arcade
-- (ReplicatedStorage.ArcadeOpen), the hint line nudging you to the Arcade
-- while you have some, and DEV: +10 Tokens asking the server for them.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum = M.Instance, M.Enum
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage

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
me:SetAttribute("Dev", true)
Players.LocalPlayer = me
M.players = { me }
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local char = Instance.new("Model")
local hum = Instance.new("Humanoid")
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = char
char.Parent = M.workspace
me.Character = char
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam

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
	table.insert(asked, tostring(name) .. ":" .. tostring(arg))
	return true, "ok"
end
local opened = 0
local open = Instance.new("BindableEvent")
open.Name = "ArcadeOpen"
open.Parent = ReplicatedStorage
open.Event:Connect(function()
	opened += 1
end)

mount.runClient("StarterPlayerScripts/Hud.client.lua", me)
M.run(1)
local function send(tokens)
	remotes.StateUpdate.OnClientEvent:Fire({
		Power = 100, Coins = 50, Tokens = tokens, Loot = {},
		Weapons = { own = {} }, Quests = { day = 0, list = {} },
	})
	M.run(M.now() + 0.5)
end
local function find(pred)
	for _, d in ipairs(gui:GetDescendants()) do
		if pred(d) then
			return d
		end
	end
	return nil
end

send(0)
local click = find(function(d)
	return d.Name == "OpenArcade"
end)
check(click ~= nil, "the token counter is there")
local row = click and click.Parent
local function shown()
	for _, d in ipairs(row and row:GetDescendants() or {}) do
		if d.ClassName == "TextLabel" and tonumber(d.Text) then
			return d.Text
		end
	end
	return nil
end
check(shown() == "0", "it shows 0 tokens (" .. tostring(shown()) .. ")")
check(row and row:FindFirstChild("Token", true) ~= nil, "with a token picture")
check(not find(function(d)
	return d.ClassName == "TextLabel" and type(d.Text) == "string" and string.find(d.Text, "Arcade Token")
end), "no Arcade hint without tokens")

send(1)
check(shown() == "1", "one token shows")
check(find(function(d)
	return d.ClassName == "TextLabel" and d.Text == "You have an Arcade Token! Spin it at the Arcade for a weapon!"
end) ~= nil, "the hint says to spin it")
send(12)
check(shown() == "12", "twelve show")
check(find(function(d)
	return d.ClassName == "TextLabel" and d.Text == "You have 12 Arcade Tokens! Spin them at the Arcade for weapons!"
end) ~= nil, "the hint counts them")

click.Activated:Fire()
M.run(M.now() + 0.1)
check(opened == 1, "clicking the tokens opens the Arcade")

local dev = find(function(d)
	return d.ClassName == "TextButton" and d.Text == "DEV: +10 Tokens"
end)
check(dev ~= nil, "the dev tools have DEV: +10 Tokens")
if dev then
	dev.Activated:Fire()
	M.run(M.now() + 0.1)
	check(table.find(asked, "DevGive:Tokens") ~= nil, "which asks the server for them")
end

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
if fails == 0 then
	print("PASS hud tokens")
else
	print(fails .. " failures")
end
