--!nocheck
-- Snapshots of a boss TALKING, for pictures: the real arena, the real
-- BossService, the real BossClient drawing the boss (and measuring where its
-- middle and head are: AimAt / HeadAt) and the real BossIntro putting its
-- wake line in a speech bubble - seen through your LOCK-ON camera (the same
-- sums as CombatClient's), with the lock-on's brackets where they'd be. A
-- pretend player (a blocky figure, for scale) stands in front of it.
--   luau talk_snaps.luau -a <floor> [before]
-- prints one picture ("talk<floor>"); "before" adds how it looked before the
-- change ("before<floor>": the brackets and camera on its small invisible
-- Root, the old black box under the boss bar). Put several floors' output in
-- one file and draw them with render_talk.py:
--   (for f in 9 1 2; do luau talk_snaps.luau -a $f; done) > talk_snaps.txt
--   python3 render_talk.py talk_snaps.txt ../../Docs/talk_preview.png
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
local args = { ... }
local FLOOR = tonumber(args[1]) or 9
local BEFORE = args[2] == "before"
local NEAR = tonumber(args[3]) -- (how far from it you stand: the picture's own choice below if not given)
math.randomseed(FLOOR)

local BUILDERS = {
	[3] = "DigBuilder", [4] = "DojoBuilder", [5] = "SpeedwayBuilder", [6] = "GridBuilder",
	[7] = "JungleBuilder", [8] = "GreenhouseBuilder", [9] = "CanvasBuilder",
}
mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
mount.require(mount.module("ServerScriptService/DunesBuilder.lua")).Build()
if BUILDERS[FLOOR] then
	mount.require(mount.module("ServerScriptService/" .. BUILDERS[FLOOR] .. ".lua")).Build()
end
M.run(1)
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= FLOOR then
		CollectionService:RemoveTag(h, "BossHome")
	end
end

-- the player: a blocky figure you can see (for scale)
local me = Instance.new("Player")
me.Name = "Alpha"
me.DisplayName = "Alpha"
me.UserId = 1001
me.Parent = Players
M.players = { me }
Players.LocalPlayer = me
local char = Instance.new("Model")
char.Name = "Alpha"
local hum = Instance.new("Humanoid")
hum.MaxHealth, hum.Health = 1e9, 1e9
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Transparency = 1
root.Parent = char
char.PrimaryPart = root
char.Parent = workspace
me.Character = char
local figure = {}
local function limb(name, size, offset, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Parent = char
	table.insert(figure, { part = p, offset = offset })
end
limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), M.Color3.fromRGB(0, 153, 219))
limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), M.Color3.fromRGB(254, 231, 97))
limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), M.Color3.fromRGB(254, 231, 97))
limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), M.Color3.fromRGB(254, 231, 97))
limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), M.Color3.fromRGB(62, 137, 72))
limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), M.Color3.fromRGB(62, 137, 72))
local function standAt(pos, lookAt)
	local cf = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
	root.CFrame = cf
	for _, f in ipairs(figure) do
		f.part.CFrame = cf * CFrame.new(f.offset)
	end
end
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.FieldOfView = 70
cam.CFrame = CFrame.lookAt(Vector3.new(0, 20, 60), Vector3.new(0, 0, 0))
cam.Parent = workspace
workspace.CurrentCamera = cam

-- pretend CombatService / PlayerService (nobody gets hurt in a picture)
local Combat = {
	PlayersInArena = function(f)
		return me:GetAttribute("SpireFloor") == f and { me } or {}
	end,
	IsFighting = function(p)
		return p:GetAttribute("SpireFloor") ~= nil
	end,
	IsInvulnerable = function()
		return true
	end,
	DamagePlayer = function()
		return false
	end,
	Shove = function() end,
	SetTargetShape = function() end,
}
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = assert(BS.Encounter(FLOOR), "no boss on floor " .. FLOOR)
local model, def, home = E.model, E.def, E.home
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)
mount.runClient("StarterPlayerScripts/BossIntro.client.lua", me)

local T = 0
local DT = 1 / 30
local function step(seconds)
	local stop = T + seconds
	while T < stop do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
		RunService.RenderStepped:Fire(DT)
	end
end

local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
local function printParts(center, reach)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 and (d.Position - center).Magnitude < reach + d.Size.Magnitude / 2 then
			local comps = { d.CFrame:GetComponents() }
			for i, v in ipairs(comps) do
				comps[i] = string.format("%.3f", v)
			end
			local col = d.Color
			realPrint(string.format('{"n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f}',
				esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
				math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
				d.Material.Name, d.Shape and d.Shape.Name or "Block", d.Transparency or 0))
		end
	end
end

-- your lock-on: CombatClient's own targetPoint (where it aims) and lockView
-- (where its camera sits and looks), cut out of it
local combat = S.files["StarterPlayerScripts/CombatClient.client.lua"]
local function cut(from, to, name)
	local a = assert(string.find(combat, from, 1, true), "no " .. name .. " in CombatClient")
	local b = assert(string.find(combat, to, a, true), "can't find where " .. name .. " ends")
	return M.load(string.sub(combat, a, b - 1) .. "\nreturn " .. name, "CombatClient (" .. name .. ")", M.env({}))()
end
local targetPoint = cut("-- Where to aim at it", "\nlocal function lockable", "targetPoint")
local lockView = cut("-- Where your lock-on camera sits and looks", 'RunService:BindToRenderStep("LockOnCamera"', "lockView")
local function lockCamera(tpos, tsize, drawn)
	return lockView(root.Position + Vector3.new(0, 1.5, 0), tpos, tsize, drawn)
end

local function snap(name, eye, look, lockAt, extra)
	cam.CFrame = CFrame.lookAt(eye, look)
	step(DT) -- (a frame for the bubble, and anything that faces your camera, to catch up)
	realPrint(string.format("SNAP %s %.3f %.3f %.3f %.3f %.3f %.3f", name, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z))
	printParts(home, 320)
	local max = math.max(model:GetAttribute("MaxHealth") or 1, 1)
	realPrint(string.format("BAR %s|%.3f|%d", def.Name, math.clamp((model:GetAttribute("Health") or max) / max, 0, 1), math.min(2, model:GetAttribute("Phase") or 1)))
	if lockAt then
		realPrint(string.format("LOCK %.3f %.3f %.3f", lockAt.X, lockAt.Y, lockAt.Z))
	end
	if extra then
		extra()
	end
	realPrint("ENDSNAP")
end

-- what the speech bubble looks like right now (BossIntro's own parts)
local function printBubble()
	local talk = gui:FindFirstChild("BossTalk")
	local bubble = talk and talk.Enabled and talk:FindFirstChild("Bubble")
	if not bubble then
		realPrint("ERROR no speech bubble up")
		return
	end
	local box = bubble:FindFirstChild("Box")
	local words = box:FindFirstChild("Words")
	local tag = box:FindFirstChild("Tag")
	local tail = "none"
	for _, n in ipairs({ "Down", "Left", "Right" }) do
		local t = bubble:FindFirstChild("Tail" .. n)
		if t and t.Visible then
			tail = string.lower(n)
		end
	end
	local a = box.AnchorPoint
	local c = tag.BackgroundColor3
	realPrint(string.format("BUBBLE %.1f %.1f %.2f %.2f %.1f %.1f %s %d,%d,%d|%s|%s",
		bubble.Position.X.Offset, bubble.Position.Y.Offset, a.X or a[1], a.Y or a[2],
		box.Position.X.Offset, box.Position.Y.Offset, tail,
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
		esc(tag:FindFirstChildOfClass("TextLabel").Text), esc(words.Text)))
end

-- the pictures' captions
if BEFORE then
	realPrint("CAPTION before" .. FLOOR .. " BEFORE: LOCKED ON AT ITS FEET, A BLACK BOX OVER THE FIGHT")
	realPrint("CAPTION talk" .. FLOOR .. " AFTER: LOCKED ON AT ITS MIDDLE, THE WORDS BY ITS HEAD")
else
	realPrint("CAPTION talk" .. FLOOR .. " " .. string.upper(def.Short) .. " (FLOOR " .. FLOOR .. ")")
end

-- walk up to it: it wakes, and (just after the VS splash) says hello
local face = E.homeFacing
local near = NEAR or math.clamp(def.Size * 1.6 + 8, 16, 30)
standAt(home + face * near + Vector3.new(0, 3, 0), home)
me:SetAttribute("SpireFloor", FLOOR)
while model:GetAttribute("State") ~= "Waking" do
	step(DT)
end
local wokeAt = M.now()
-- (its brain stopped once it's up, so it stands for the picture)
while model:GetAttribute("State") ~= "Fighting" and M.now() - wokeAt < 8 do
	step(DT)
end
E.token += 1
E.motion, E.sweep, E.chase, E.track = nil, nil, nil, nil
local sayAt = wokeAt + 2.6
while M.now() < math.max(sayAt + 0.8, wokeAt + def.WakeTime + 0.4) do
	step(DT)
end

if BEFORE then
	-- before: the brackets on its Root, the camera framing its Root, the black box
	local r = model.PrimaryPart
	local eye, look = lockCamera(r.Position, r.Size, false)
	snap("before" .. FLOOR, eye, look, r.Position, function()
		local talk = gui:FindFirstChild("BossTalk")
		local words = talk and talk:FindFirstChild("Words", true)
		realPrint("OLDBOX " .. esc(words and words.Text or ""))
	end)
end
local tpos, tsize, drawn = targetPoint(model)
assert(drawn, "BossClient should have measured it")
local eye, look = lockCamera(tpos, tsize, drawn)
snap("talk" .. FLOOR, eye, look, model:GetAttribute("AimAt"), printBubble)
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
