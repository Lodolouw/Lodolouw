--!nocheck
-- Builds the whole lobby (the real LobbyBuilder) and runs RetroWorld on a
-- pretend screen, then prints every part as one JSON line: for drawing the
-- lobby (render_lobby.py) and checking it for building mistakes
-- (check_lobby.py).   luau lobby_dump.luau > lobby.jsonl
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
local lobby = M.load(S.LobbyBuilder, "LobbyBuilder", env)().Build()
M.run(1)
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
if ({ ... })[1] ~= "server" then
	M.task.spawn(M.load(S.RetroWorld, "RetroWorld", env))
	local RunService = M.services.RunService
	local t = 1
	for _ = 1, 400 do
		t += 1 / 30
		M.run(t)
		RunService.Heartbeat:Fire(1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
	end
end
local CS = M.services.CollectionService
local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\]', ""))
end
local function top(d)
	-- the lobby piece (or RetroWorld folder) it belongs to, and its path
	local chain = {}
	local a = d.Parent
	while a and a ~= M.workspace do
		table.insert(chain, 1, a.Name)
		a = a.Parent
	end
	return table.concat(chain, "/")
end
-- (which object each part belongs to: its nearest Model, numbered, so two
-- torches in the same folder are told apart)
local modelIds, nextId = {}, 0
local function modelOf(d)
	local a = d.Parent
	while a and a ~= M.workspace do
		if a:IsA("Model") and a ~= lobby then
			if not modelIds[a] then
				nextId += 1
				modelIds[a] = nextId
			end
			return modelIds[a]
		end
		a = a.Parent
	end
	return 0
end
local roots = { lobby, M.workspace:FindFirstChild("RetroWorld") }
for _, r in ipairs(roots) do
	for _, d in ipairs(r and r:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			local c = d.CFrame
			local comps = { c:GetComponents() }
			for i, v in ipairs(comps) do
				comps[i] = string.format("%.3f", v)
			end
			local col = d.Color
			local tags = {}
			for _, tg in ipairs({ "FX", "Wave", "Pulse", "Sway", "Rotor", "Dummy" }) do
				if CS:HasTag(d, tg) then
					table.insert(tags, '"' .. tg .. '"')
				end
			end
			print(string.format('{"n":"%s","c":"%s","p":"%s","mid":%d,"s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f,"cc":%s,"cs":%s,"tags":[%s]}',
				esc(d.Name), d.ClassName, esc(top(d)), modelOf(d), d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
				math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
				d.Material.Name, d.Shape and d.Shape.Name or "Block", d.Transparency,
				tostring(d.CanCollide ~= false), tostring(d.CastShadow ~= false), table.concat(tags, ",")))
		end
	end
end
