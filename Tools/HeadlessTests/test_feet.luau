--!nocheck
-- Headless test of FEET ON THE FLOOR (LobbyActivities' "Feet on the floor:
-- never sunk into it, never floating over it"): the real code, cut out of
-- LobbyActivities, on a pretend R6 character held up by a pretend
-- ControllerManager (it holds the body GroundOffset above the floor).
--   * sunk into the floor after spawning: lifted out, and held higher
--   * sword lunges, strides and rolls (legs swung out) never lift you - they
--     used to, a bit more every time, until you floated
--   * lifted, then the avatar finishes loading and you float: let back down
--     (never lower than where it started)
--   * never lifted more than 3 studs; nothing happens mid-jump or walking
--
--   luau test_feet.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance, CFrame, Vector3, Enum = M.Instance, M.CFrame, M.Vector3, M.Enum
local Players = M.services.Players

local env = M.env({})

-- the code, exactly as it is in LobbyActivities
local src = S.files["StarterPlayerScripts/LobbyActivities.client.lua"]
local a = assert(string.find(src, "-- Feet on the floor: never sunk into it", 1, true), "the feet code isn't in LobbyActivities")
local chunk = "local player = ...\n" .. string.sub(src, a)

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- the floor: flat, its top at y = 0
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Parent = M.workspace
M.raycast = function(origin, dir)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Instance = floor }
	end
	return nil
end

-- a pretend R6 character and the ControllerManager holding it up
local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char = Instance.new("Model")
char.Name = "Tester"
local function part(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new()
	p.Parent = char
	return p
end
local root = part("HumanoidRootPart", Vector3.new(2, 2, 1))
local torso = part("Torso", Vector3.new(2, 2, 1))
local lleg = part("Left Leg", Vector3.new(1, 2, 1))
local rleg = part("Right Leg", Vector3.new(1, 2, 1))
char.PrimaryPart = root
local hum = Instance.new("Humanoid")
hum.Health = 100
hum.MaxHealth = 100
hum.RigType = Enum.HumanoidRigType.R6
hum.Parent = char
local cm = Instance.new("ControllerManager")
cm.Parent = hum
local gc = Instance.new("GroundController")
gc.GroundOffset = 2
gc.Parent = cm
local sensor = Instance.new("ControllerPartSensor")
sensor.SearchDistance = 5
sensor.Parent = cm
cm.GroundSensor = sensor
root.AssemblyLinearVelocity = Vector3.zero
char.Parent = M.workspace
me.Character = char

local G0 = 2 -- the offset that puts an R6 body's feet exactly on the floor
local sink = 0 -- how far the body sits too low (a bad start: the avatar not loaded yet)
local legTilt = 0 -- the legs swung out (a stride, a lunge, a roll), in degrees
local lifted = 0 -- (PivotTo lifts: the pretend controller takes over again next frame)
-- the pretend controller: holds the body at GroundOffset over the floor
local function hold()
	local y = 3 + (gc.GroundOffset - G0) + sink
	root.CFrame = CFrame.new(0, y, 0)
	torso.CFrame = CFrame.new(0, y, 0)
	for i, leg in ipairs({ lleg, rleg }) do
		local side = i == 1 and -0.5 or 0.5
		local swing = math.rad(legTilt) * (i == 1 and 1 or -1)
		leg.CFrame = CFrame.new(side, y - 1, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -1, 0)
	end
end
local function feetGap()
	return (lleg.CFrame * Vector3.new(0, -1, 0)).Y
end

local t = 0
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		hold()
		M.run(t)
		if each then
			each()
		end
	end
end

hold()
M.load(chunk, "LobbyActivities (feet on the floor)", env)(me)

local function all()
	-- a good start: nothing happens
	step(2)
	check(gc.GroundOffset == G0, "standing properly: the height's left alone")

	-- 1) sunk after a reset: lifted out and held higher
	sink = -1.2
	step(1)
	check(math.abs(gc.GroundOffset - (G0 + 1.2)) < 0.05, ("sunk 1.2 studs into the floor: held 1.2 higher (offset %.2f)"):format(gc.GroundOffset))
	check(math.abs(feetGap()) < 0.05, ("...feet back on the floor (%.2f)"):format(feetGap()))
	check(math.abs(sensor.SearchDistance - (5 + 1.2)) < 0.05, "...and the ground sensor reaches that much further")

	-- 2) the avatar finishes loading and now it floats: let back down (to where it started, no lower)
	sink = 0
	step(1)
	check(math.abs(gc.GroundOffset - G0) < 0.05, ("floating after that: let back down (offset %.2f)"):format(gc.GroundOffset))
	check(math.abs(feetGap()) < 0.05 and math.abs(sensor.SearchDistance - 5) < 0.05, "...feet on the floor, sensor back as it was")
	sink = 0.8 -- (floating, but not because of anything we did: never held lower than it started)
	step(1)
	check(gc.GroundOffset == G0, "floating for some other reason: never held lower than it started")
	sink = 0

	-- 3) sword lunges, strides, rolls: legs swung out poke a corner down, but that's not sunk
	for _ = 1, 10 do
		-- (like the sword's lunge: legs 50 degrees apart, the body lowered until
		-- the legs' ends touch the floor - so a corner of each foot pokes 0.38 in)
		legTilt = 50
		sink = -(2 - 2 * math.cos(math.rad(50)))
		step(0.6)
		legTilt, sink = 0, 0
		step(0.3)
	end
	check(gc.GroundOffset == G0, ("ten sword lunges don't lift you at all (offset %.2f)"):format(gc.GroundOffset))
	for _ = 1, 6 do
		legTilt = 120 -- (curled up in a roll)
		sink = -1
		root.AssemblyLinearVelocity = Vector3.new(40, 0, 0)
		step(0.45)
		legTilt, sink = 0, 0
		root.AssemblyLinearVelocity = Vector3.zero
		step(0.3)
	end
	check(gc.GroundOffset == G0, ("six rolls don't lift you (offset %.2f)"):format(gc.GroundOffset))

	-- 4) walking or jumping: left alone, even if something looks off
	sink = -1
	root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
	step(1)
	check(gc.GroundOffset == G0, "walking: left alone")
	root.AssemblyLinearVelocity = Vector3.new(0, 20, 0)
	step(1)
	check(gc.GroundOffset == G0, "jumping: left alone")
	root.AssemblyLinearVelocity = Vector3.zero

	-- 5) never more than 3 studs in all, however often it seems sunk
	sink = -2.5
	step(1)
	check(math.abs(gc.GroundOffset - (G0 + 2.5)) < 0.05, ("sunk 2.5: held 2.5 higher (offset %.2f)"):format(gc.GroundOffset))
	sink = -4
	step(1.5)
	check(gc.GroundOffset <= G0 + 3 + 1e-6 and gc.GroundOffset > G0 + 2.9, ("...but never more than 3 studs in all (offset %.2f)"):format(gc.GroundOffset))
	sink = 0
	step(2)
	check(math.abs(gc.GroundOffset - G0) < 0.05, "and let back down when it isn't needed")

	-- dying stops it
	hum.Health = 0
	sink = -1
	step(1)
	check(gc.GroundOffset == G0, "once you're dead it stops")
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
	print("PASS feet")
else
	print(fails .. " failures")
end
