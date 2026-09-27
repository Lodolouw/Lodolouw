--!nocheck
-- Headless test of THE DRINK (CombatClient's "The drink, as everyone sees it"):
-- the real code, cut out of CombatClient, run on a pretend R6 character.
-- CombatService puts "Drinking" (seconds) on a character while it drinks; the
-- right arm must bring a little potion up to the chin, tip it back with the
-- head back, then put everything back exactly as it was.
--
--   luau test_drink.luau             every check
--   luau test_drink.luau -a poses    prints the joints over a drink (for render_drink.py)
local M = require("./rbxmock")
local S = require("./sources")
local Instance, CFrame, Vector3 = M.Instance, M.CFrame, M.Vector3
local Players = M.services.Players
local RunService = M.services.RunService

local args = { ... }
local MODE = args[1] or "all"

local env = M.env({})
local Config = M.load(S.Config, "Config", env)()

-- the drink's code, exactly as it is in CombatClient
local src = S.files["StarterPlayerScripts/CombatClient.client.lua"]
local a = assert(string.find(src, "-- The drink, as everyone sees it", 1, true), "the drink's code isn't in CombatClient")
local b = assert(string.find(src, "\n----------------------------------------------------------------------\n-- Weapon: the ability", a, true)
	or string.find(src, "\n----------------------------------------------------------------------\n-- Damage numbers", a, true), "can't find where the drink's code ends")
local chunk = "local Players, RunService, RGB, CC = ...\n" .. string.sub(src, a, b)
M.load(chunk, "CombatClient (the drink)", env)(Players, RunService, M.Color3.fromRGB, Config.Combat)

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- a pretend R6 character with Roblox's own joints
local function part(model, name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new()
	p.Parent = model
	return p
end
local function r6(name)
	local model = Instance.new("Model")
	model.Name = name
	local torso = part(model, "Torso", Vector3.new(2, 2, 1))
	local arm = part(model, "Right Arm", Vector3.new(1, 2, 1))
	local head = part(model, "Head", Vector3.new(2, 1, 1))
	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "Right Shoulder"
	shoulder.Part0, shoulder.Part1 = torso, arm
	shoulder.C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	shoulder.C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	shoulder.Transform = CFrame.new()
	shoulder.Parent = torso
	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.Part0, neck.Part1 = torso, head
	neck.C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	neck.C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	neck.Transform = CFrame.new()
	neck.Parent = torso
	model.Parent = M.workspace
	return model, shoulder, neck
end

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char, shoulder, neck = r6("Tester")
me.Character = char
M.players = { me } -- (who Players:GetPlayers() lists)

local t = 0
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Stepped:Fire(t, 1 / 60)
		if each then
			each()
		end
	end
end

-- where the hand is, in the torso's space (the bottom of the arm)
local function hand(j)
	return (j.C0 * j.Transform * j.C1:Inverse()) * Vector3.new(0, -1, 0)
end
-- which way the face looks (the head's front, in the torso's space)
local function look(j)
	local head = j.C0 * j.Transform * j.C1:Inverse()
	return head.LookVector
end
local function potion(c)
	return c:FindFirstChild("DrinkPotion")
end
local function isRest(j)
	local p = j.Transform.Position
	local lv, uv = j.Transform.LookVector, j.Transform.UpVector
	return p.Magnitude < 1e-6 and (lv - Vector3.new(0, 0, -1)).Magnitude < 1e-4 and (uv - Vector3.new(0, 1, 0)).Magnitude < 1e-4
end
local function finite(cf)
	for _, n in ipairs({ cf:GetComponents() }) do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

local function drinkOnce(seconds)
	seconds = seconds or Config.Combat.FlaskDrinkTime
	char:SetAttribute("Drinking", seconds)
	local highest, closest, faceUp = -99, 99, -99
	local sawPotion = false
	step(seconds, function()
		local h = hand(shoulder)
		highest = math.max(highest, h.Y)
		closest = math.min(closest, (h - Vector3.new(0, 1.3, -0.62)).Magnitude)
		faceUp = math.max(faceUp, look(neck).Y)
		sawPotion = sawPotion or potion(char) ~= nil
		check(finite(shoulder.Transform) and finite(neck.Transform), "the joints stay real numbers")
	end)
	char:SetAttribute("Drinking", nil) -- (what CombatService does when the drink is over)
	return highest, closest, faceUp, sawPotion
end

local function all()
	-- resting: nothing happens
	step(0.5)
	check(isRest(shoulder) and isRest(neck) and not potion(char), "nothing moves before a drink")

	-- a drink
	char:SetAttribute("Drinking", Config.Combat.FlaskDrinkTime)
	step(1 / 60)
	local p = potion(char)
	check(p ~= nil, "a potion appears in the hand")
	if p then
		local n, welds = 0, 0
		for _, bit in ipairs(p:GetChildren()) do
			if bit:IsA("Part") then
				n += 1
				check(bit.CanCollide == false and bit.Massless == true and bit.CanQuery == false, "the potion's " .. bit.Name .. " can't bump into anything")
				local w = bit:FindFirstChildOfClass("Weld")
				if w and w.Part0 == char["Right Arm"] and w.Part1 == bit then
					welds += 1
				end
			end
		end
		check(n == 3 and welds == 3, ("the potion is a bottle, a neck and a cork, welded to the right arm (%d parts, %d welds)"):format(n, welds))
	end
	char:SetAttribute("Drinking", nil)
	step(1)

	local highest, closest, faceUp, saw = drinkOnce()
	check(saw, "the potion shows while drinking")
	check(closest < 0.95, ("the hand comes up to the chin (%.2f studs from the mouth)"):format(closest))
	check(highest > 1.2, ("then lifts higher to tip it back (hand up to %.2f)"):format(highest))
	check(faceUp > 0.2, ("the head tips back (face looking up %.2f)"):format(faceUp))
	-- the hand never goes inside the body
	step(0.35)
	check(not potion(char), "the potion's put away afterwards")
	check(isRest(shoulder) and isRest(neck), "the arm and head are back exactly where they were")

	-- nothing piles up: a joint nobody else moves reaches the pose and no further
	char:SetAttribute("Drinking", 0.9)
	step(0.8)
	local first = shoulder.Transform
	step(0.05)
	local second = shoulder.Transform
	check((first.Position - second.Position).Magnitude < 1e-6 and (first.LookVector - second.LookVector).Magnitude < 0.05,
		"holding the tip, the arm stays put (it doesn't keep turning)")
	char:SetAttribute("Drinking", nil)
	step(0.5)
	check(isRest(shoulder) and isRest(neck), "back to rest again")

	-- walking moves the joints every frame (Roblox's animations do it just before
	-- the drink's code runs - here the pretend walk pose is written before each frame):
	-- the drink starts from wherever the arm was, it doesn't snap
	local walk = CFrame.Angles(0, 0, math.rad(20))
	for _ = 1, 30 do
		shoulder.Transform = walk
		step(1 / 60)
	end
	check(shoulder.Transform == walk, "walking alone: the drink's code leaves the arm alone")
	char:SetAttribute("Drinking", 0.9)
	local start = nil
	for i = 1, 20 do
		shoulder.Transform = walk
		step(1 / 60)
		if i == 1 then
			start = hand(shoulder)
		end
	end
	check(start and (start - ((shoulder.C0 * walk * shoulder.C1:Inverse()) * Vector3.new(0, -1, 0))).Magnitude < 0.3,
		"the drink starts from the walking arm (no snap)")
	char:SetAttribute("Drinking", nil)
	for _ = 1, 30 do
		shoulder.Transform = walk
		step(1 / 60)
	end
	check(not potion(char), "put away")

	-- dying mid-drink: everything tidied up
	char:SetAttribute("Drinking", 0.9)
	step(0.3)
	char.Parent = nil
	step(0.1)
	char.Parent = M.workspace
	check(not potion(char), "a character that's gone loses its potion")

	-- someone else drinking is shown too
	local other = Instance.new("Player")
	other.Name = "Friend"
	other.UserId = 1002
	other.Parent = Players
	local oc, os_ = r6("Friend")
	other.Character = oc
	table.insert(M.players, other)
	oc:SetAttribute("Drinking", 0.9)
	step(0.5)
	check(potion(oc) ~= nil and not isRest(os_), "another player's drink shows on your screen too")
	oc:SetAttribute("Drinking", nil)
	step(0.5)
	check(potion(oc) == nil and isRest(os_), "and ends")

	-- not an R6 body: nothing happens, nothing breaks
	local r15 = Instance.new("Player")
	r15.Name = "Blocky"
	r15.UserId = 1003
	r15.Parent = Players
	local m = Instance.new("Model")
	m.Name = "Blocky"
	part(m, "UpperTorso", Vector3.new(2, 1, 1))
	m.Parent = M.workspace
	r15.Character = m
	table.insert(M.players, r15)
	m:SetAttribute("Drinking", 0.9)
	step(1)
	check(not potion(m), "no potion on a body without R6 joints")
end

local function poses()
	step(0.2)
	char:SetAttribute("Drinking", Config.Combat.FlaskDrinkTime)
	step(1 / 60)
	for _, bit in ipairs(potion(char):GetChildren()) do
		local w = bit:FindFirstChildOfClass("Weld")
		local c = bit.Color
		print(string.format("BIT %s %.2f %.2f %.2f %d %d %d %s", bit.Name, bit.Size.X, bit.Size.Y, bit.Size.Z,
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), table.concat({ w.C0:GetComponents() }, " ")))
	end
	t -= 1 / 60 -- (so the first picture is the very start)
	local marks = { 0.0, 0.12, 0.25, 0.45, 0.62, 0.85 }
	local start = t
	local i = 1
	step(Config.Combat.FlaskDrinkTime, function()
		local el = t - start
		if marks[i] and el >= marks[i] then
			local s = { shoulder.Transform:GetComponents() }
			local n = { neck.Transform:GetComponents() }
			print(string.format("POSE %.2f %s | %s | %s", el, table.concat(s, " "), table.concat(n, " "), potion(char) and "potion" or "-"))
			i += 1
		end
	end)
	char:SetAttribute("Drinking", nil)
	step(0.12)
	local s = { shoulder.Transform:GetComponents() }
	local n = { neck.Transform:GetComponents() }
	print(string.format("POSE %.2f %s | %s | %s", t - start, table.concat(s, " "), table.concat(n, " "), potion(char) and "potion" or "-"))
end

if MODE == "poses" then
	poses()
	return
end
local ok, err = pcall(all)
if not ok then
	fails += 1
	print("FAIL: errored: " .. tostring(err))
end
if #M.errors > 0 then
	fails += 1
	print("FAIL: " .. #M.errors .. " script errors")
	for i = 1, math.min(3, #M.errors) do
		print(M.errors[i])
	end
end
if fails == 0 then
	print("PASS drink")
else
	print(fails .. " failures")
end
