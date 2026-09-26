--!nocheck
-- Builds the whole lobby with the real LobbyBuilder in the pretend Roblox and
-- counts what's in it: parts per piece, lights, shadow-casting parts, Neon.
-- (For finding what makes the lobby heavy.)  luau lobby_count.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance = M.Instance
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
local LobbyBuilder = M.load(S.LobbyBuilder, "LobbyBuilder", env)()
local lobby = LobbyBuilder.Build()
M.run(5)
local function count(root)
	local c = { parts = 0, shadow = 0, lights = 0, neon = 0, small = 0, smallShadow = 0 }
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			c.parts += 1
			if d.CastShadow ~= false and d.Transparency < 1 then
				c.shadow += 1
			end
			if d.Material == M.Enum.Material.Neon then
				c.neon += 1
			end
			local sz = d.Size
			if math.max(sz.X, sz.Y, sz.Z) < 4 then
				c.small += 1
				if d.CastShadow ~= false and d.Transparency < 1 then
					c.smallShadow += 1
				end
			end
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			c.lights += 1
		end
	end
	return c
end
local rows = {}
for _, piece in ipairs(lobby:GetChildren()) do
	local c = count(piece)
	table.insert(rows, { piece.Name, c })
end
table.sort(rows, function(a, b)
	return a[2].parts > b[2].parts
end)
local total = count(lobby)
print(string.format("%-28s %6s %6s %6s %6s %6s", "piece", "parts", "shadow", "small", "lights", "neon"))
for _, r in ipairs(rows) do
	local c = r[2]
	print(string.format("%-28s %6d %6d %6d %6d %6d", r[1], c.parts, c.shadow, c.small, c.lights, c.neon))
end
print(string.format("%-28s %6d %6d %6d %6d %6d", "TOTAL", total.parts, total.shadow, total.small, total.lights, total.neon))
print("small parts casting shadows: " .. total.smallShadow)
-- what your own screen adds on top (RetroWorld's detail: cobbles, bricks,
-- grass, clouds...)
if ({ ... })[1] == "client" then
	local Players = M.services.Players
	local player = Instance.new("Player")
	player.Name = "Tester"
	player.UserId = 1001
	player.Parent = Players
	Players.LocalPlayer = player
	M.players = { player }
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	M.task.spawn(M.load(S.RetroWorld, "RetroWorld", env))
	local RunService = M.services.RunService
	local t = 5
	for _ = 1, 600 do
		t += 1 / 30
		M.run(t)
		RunService.Heartbeat:Fire(1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
	end
	local mine = M.workspace:FindFirstChild("RetroWorld")
	local byName = {}
	local n = 0
	for _, d in ipairs(mine and mine:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			n += 1
			byName[d.Parent.Name] = (byName[d.Parent.Name] or 0) + 1
		end
	end
	print("RetroWorld parts on your screen: " .. n)
	for k, v in pairs(byName) do
		print("  in " .. k .. ": " .. v)
	end
end
print("errors: " .. #M.errors)
-- (the biggest piece, by part name; and everything animated)
if ({ ... })[1] == "names" then
	local byName = {}
	for _, d in ipairs(lobby:FindFirstChild("IslandAndSea"):GetDescendants()) do
		if d:IsA("BasePart") then
			byName[d.Name] = (byName[d.Name] or 0) + 1
		end
	end
	local list = {}
	for k, v in pairs(byName) do
		table.insert(list, { k, v })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	for i = 1, math.min(25, #list) do
		print(string.format("  %-24s %d", list[i][1], list[i][2]))
	end
	local CS = M.services.CollectionService
	for _, tag in ipairs({ "FX", "Dummy", "ZoneSign", "AutoOpenZone" }) do
		print(tag .. ": " .. #CS:GetTagged(tag))
	end
end
