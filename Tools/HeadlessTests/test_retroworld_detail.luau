--!nocheck
-- RetroWorld's added detail: never piled up on the fountain, never doubled.
--
-- 1. Low graphics (the white block on the fountain). Some of RetroWorld's
-- lobby detail moves: the clouds, the birds and gulls, the breeze, the pixel
-- flames and smoke, the sparks, the beacon's runes and the save star. That
-- detail used to be put in its place only by its stepper. A part nobody has
-- moved sits at 0,0,0, which is the fountain in the middle of the plaza.
-- With Low graphics on, the steppers hold still, so every cloud piled up
-- there as one big white block.
--
-- 2. An arena is only kept loaded while you're on its floor, so it can unload
-- in the lobby and arrive again as a new model. Its detail (grass, spores,
-- pixel flames) lives in RetroWorld's own folder and is still standing, so
-- it mustn't be added again on top.
--
-- This builds the real lobby, the slime arena and the dunes, runs the real
-- RetroWorld with Low graphics on from the start, and checks:
--   * nothing it shows is left at 0,0,0
--   * while it's on, the flyers (birds, gulls, breeze) are put away and the
--     rest holds still
--   * switched off, the flyers come back and the detail moves again
--   * an arena that unloads and comes back gets its look again (its new fires
--     quieted) but not a second lot of detail
--
--   luau test_retroworld_detail.luau      (after: python3 build_sources.py)
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
M.load(S.LobbyBuilder, "LobbyBuilder", env)().Build()
M.load(S.files["ServerScriptService/DunesBuilder.lua"], "DunesBuilder", env)().Build() -- (the dunes: its braziers burn)
M.run(5)
for _, d in ipairs(M.workspace:GetDescendants()) do
	if (d:IsA("Fire") or d:IsA("Smoke")) and d.Enabled == nil then
		d.Enabled = true -- (a new fire burns: Roblox's default, which the pretend world doesn't have)
	end
end

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
player:SetAttribute("LowGraphics", true) -- (on before RetroWorld starts, as a saved setting would be)
M.task.spawn(M.load(S.RetroWorld, "RetroWorld", env))
M.run(5) -- (RetroWorld sets itself up; no frame drawn yet)
local mine = M.workspace:FindFirstChild("RetroWorld")
local detail = mine and mine:FindFirstChild("Detail")
local flyers = detail and detail:FindFirstChild("Flyers")

local RunService = M.services.RunService
local t = 5
local function frames(n)
	for _ = 1, n do
		t += 1 / 30
		M.run(t)
		RunService.Heartbeat:Fire(1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
	end
end

local fails = 0
local function check(ok, what)
	print((ok and "  ok   " or "  FAIL ") .. what)
	if not ok then
		fails += 1
	end
end

local function shown(p)
	return p.Transparency < 1 and p:IsDescendantOf(M.workspace)
end
-- RetroWorld's parts on the screen still sitting where every new part starts
local function atZero()
	local n, sizes = 0, {}
	for _, d in ipairs(mine:GetDescendants()) do
		if d:IsA("BasePart") and shown(d) and d.CFrame.Position.Magnitude < 0.01 then
			n += 1
			if #sizes < 4 then
				table.insert(sizes, string.format("%s %.1fx%.1fx%.1f", d.Parent.Name, d.Size.X, d.Size.Y, d.Size.Z))
			end
		end
	end
	return n, table.concat(sizes, ", ")
end
local function where()
	local at = {}
	for _, d in ipairs(mine:GetDescendants()) do
		if d:IsA("BasePart") then
			at[d] = d.CFrame.Position
		end
	end
	return at
end
local function movedSince(before)
	local n = 0
	for p, pos in pairs(before) do
		if (p.CFrame.Position - pos).Magnitude > 0.01 then
			n += 1
		end
	end
	return n
end

-- 1. Low graphics on from the start (the lobby's detail, the arenas' grass,
-- spores and flames: 20 seconds is plenty for all of it to be made)
check(flyers ~= nil, "RetroWorld made its folders (Detail, and Flyers in it)")
if not flyers then
	print("FAILED: " .. fails)
	return
end
frames(600)
local n, sizes = atZero()
check(n == 0, "with Low graphics on, nothing it shows sits at 0,0,0 (the fountain): " .. n .. (n > 0 and (" - " .. sizes) or ""))
check(flyers.Parent == nil, "the flyers (birds, gulls, breeze) are put away while it's on")
local flyerParts = 0
for _, d in ipairs(flyers:GetDescendants()) do
	if d:IsA("BasePart") then
		flyerParts += 1
	end
end
check(flyerParts > 40, "the flyers were still made (" .. flyerParts .. " parts), ready for when it's switched off")
local before = where()
frames(90)
check(movedSince(before) == 0, "with Low graphics on, the detail holds still")

-- 2. switched off: the flyers are back, the clouds and birds move again, and
-- still nothing sits at 0,0,0
local flyersAway = where()
for _, d in ipairs(flyers:GetDescendants()) do
	if d:IsA("BasePart") then
		flyersAway[d] = d.CFrame.Position
	end
end
player:SetAttribute("LowGraphics", nil)
frames(90)
check(flyers.Parent == detail, "switched off, the flyers are back")
local moved = movedSince(flyersAway)
check(moved > 100, "switched off, the detail moves again (" .. moved .. " parts moved)")
n, sizes = atZero()
check(n == 0, "switched off, still nothing at 0,0,0: " .. n .. (n > 0 and (" - " .. sizes) or ""))

-- 3. and on again: put away again
player:SetAttribute("LowGraphics", true)
frames(10)
check(flyers.Parent == nil, "switched on again, the flyers are put away again")

-- 4. each arena unloads (in the lobby, far away) and comes back as a new model
-- with its fires burning again, as the server sends it
local function retroParts()
	local n = 0
	for _, root in ipairs({ mine, flyers }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and (root == mine or flyers.Parent == nil) then
				n += 1
			end
		end
	end
	return n
end
for _, name in ipairs({ "SlimeArena", "DuneArena" }) do
	local arena = M.workspace:FindFirstChild(name)
	check(arena ~= nil, name .. " is built")
	if arena then
		local had = retroParts()
		local copy = arena:Clone()
		local fires = 0
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Fire") then
				d.Enabled = true
				fires += 1
			end
		end
		arena:Destroy()
		frames(30)
		copy.Parent = M.workspace
		frames(300)
		local now = retroParts()
		check(now == had, name .. " came back without a second lot of detail (" .. had .. " parts before, " .. now .. " after)")
		local burning = 0
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Fire") and d.Enabled then
				burning += 1
			end
		end
		check(burning == 0, name .. "'s fires are quieted again (" .. fires .. " fires; its pixel flames still stand)")
	end
end

check(#M.errors == 0, "no errors (" .. #M.errors .. ")")
for i = 1, math.min(3, #M.errors) do
	print("    " .. tostring(M.errors[i]))
end
print(fails == 0 and "PASS" or ("FAILED: " .. fails))
