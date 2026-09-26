--!nocheck
-- How much the lobby's animation moves each second, standing at the spawn:
-- builds the lobby (the real LobbyBuilder), runs LobbyFX for 10 seconds of
-- pretend time at 60 frames a second, and counts the parts moved and the
-- see-through changes.  luau fx_cost.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance, CFrame, Vector3 = M.Instance, M.CFrame, M.Vector3
local ReplicatedStorage = M.services.ReplicatedStorage
local configModule = Instance.new("ModuleScript")
configModule.Name = "Config"
configModule.Parent = ReplicatedStorage
local Config
local env = M.env({
	require = function(mod)
		if mod == configModule then
			return Config
		end
		error("require of unknown module " .. tostring(mod))
	end,
})
Config = M.load(S.Config, "Config", env)()
local lobby = M.load(S.LobbyBuilder, "LobbyBuilder", env)().Build()
M.run(1)
local shadows = 0
for _, d in ipairs(lobby:GetDescendants()) do
	if d:IsA("BasePart") and d.CastShadow ~= false and d.Transparency < 1 then
		shadows += 1
	end
end
local Players = M.services.Players
local player = Instance.new("Player")
player.Name = "Tester"
player.Parent = Players
Players.LocalPlayer = player
M.players = { player }
local cam = Instance.new("Camera")
cam.CFrame = CFrame.new(Vector3.new(0, 12, 50), Vector3.new(0, 5, 20)) -- (behind someone at the spawn)
M.workspace.CurrentCamera = cam
-- (count see-through changes on the lobby's parts)
local trWrites = 0
for _, d in ipairs(lobby:GetDescendants()) do
	if d:IsA("BasePart") then
		d:GetPropertyChangedSignal("Transparency"):Connect(function()
			trWrites += 1
		end)
	end
end
local movedByName = {}
for _, d in ipairs(lobby:GetDescendants()) do
	if d:IsA("BasePart") then
		d:GetPropertyChangedSignal("CFrame"):Connect(function()
			movedByName[d.Name] = (movedByName[d.Name] or 0) + 1
		end)
	end
end
M.task.spawn(M.load(S.LobbyFX, "LobbyFX", env))
local RunService = M.services.RunService
local t = 1
local function frames(n)
	for _ = 1, n do
		t += 1 / 60
		M.run(t)
		RunService.RenderStepped:Fire(1 / 60)
		RunService.Heartbeat:Fire(1 / 60)
	end
end
frames(60) -- (settle)
M.writes.CFrame, M.writes.Bulk, trWrites = 0, 0, 0
table.clear(movedByName)
frames(600)
print(string.format("parts casting shadows %d | per second: parts moved %d, batches %.1f, see-through changes %d",
	shadows, (M.writes.CFrame or 0) / 10, (M.writes.Bulk or 0) / 10, trWrites / 10))
local byName = {}
for k, v in pairs(movedByName) do
	table.insert(byName, { k, v })
end
table.sort(byName, function(a, b)
	return a[2] > b[2]
end)
local top = {}
for i = 1, math.min(8, #byName) do
	table.insert(top, byName[i][1] .. " " .. math.floor(byName[i][2] / 10))
end
print("most moved (per second): " .. table.concat(top, ", "))
-- (what's in range of the camera, by kind)
local CS = M.services.CollectionService
local camPos = cam.CFrame.Position
local function near(tag, range, models)
	local n, parts = 0, 0
	for _, x in ipairs(CS:GetTagged(tag)) do
		local p = x:IsA("Model") and x.PrimaryPart or x
		if p and (p.Position - camPos).Magnitude < range then
			n += 1
			parts += models and #x:GetDescendants() or 1
		end
	end
	return n, parts
end
print(string.format("in range: FX %d, Wave %d, Sway %d (%d parts), Pulse %d", near("FX", 400), near("Wave", 450), near("Sway", 350, true), select(2, near("Sway", 350, true)), near("Pulse", 600)))
print("errors: " .. #M.errors)
