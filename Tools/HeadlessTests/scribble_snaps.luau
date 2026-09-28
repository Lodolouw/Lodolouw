--!nocheck
-- Snapshots of Scribble for pictures: the real canvas (CanvasBuilder), the
-- real BossService with his moves and the real BossClient drawing him (his
-- warnings, clones, the Z key, the DELETE box, the erased edge), and a
-- pretend player (a blocky figure, for scale). At a few moments every part
-- you'd see is printed with the camera (he's a drawing: he turns to face
-- each picture's camera, the way he turns to face yours):
--   canvas   - The Canvas from the door: him a faint pencil sketch
--   wake     - he inks himself in and grins
--   dash     - PENCIL DASH: the dotted line, and him streaking along it
--   eraser   - ERASER SWEEP: the giant eraser rubbing out the strip
--   paint    - PAINT BUCKET: squares flooding with paint
--   clones   - COPY-PASTE: two ink clones running at you
--   undo     - UNDO: the Z key in front of you - punch it!
--   round2   - ROUND 2: tearing himself out of the paper, red marker now
--   cursor   - THE CURSOR: locked on, about to click
--   whip     - BOSS BAR WHIP: your health bar, swung round low
--   errors   - ERROR POP-UPS: windows standing like walls
--   lag      - LAG SPIKE: ghosts in a line to you
--   delete   - ROUND 3: "Delete FLOOR 9?" - punch NO; the paper erasing
--   end      - THE END: crumpled into a ball, into the recycle bin
--   luau scribble_snaps.luau > scribble_snaps.txt
--   python3 render_snaps.py scribble_snaps.txt ../../Docs/scribble_preview.png --cols 3 --title "SCRIBBLE|FLOOR 9  -  THE CANVAS|RECOMMENDED LV 135"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau scribble_snaps.luau -a poses > scribble_poses.txt
--   python3 render_snaps.py scribble_poses.txt ../../Docs/scribble_poses.png --cols 3 --title ""
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
local MODE = ({ ... })[1] or "fight"
math.randomseed(3)

local arena = mount.require(mount.module("ServerScriptService/CanvasBuilder.lua")).Build()
M.run(1)
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
local C = arena:GetAttribute("Center")

-- the player: a blocky figure you can see (for scale), standing where we say
local me = Instance.new("Player")
me.Name = "Alpha"
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
cam.CFrame = CFrame.lookAt(C + Vector3.new(0, 20, 70), C)
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
local Profile = { RecordBossKill = function() return true end, AddPower = function() end, AddChest = function() end }
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 9 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(9)
local model = E.model
local def = E.def
local home = E.home
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

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
local function stepUntil(t)
	while M.now() < t do
		step(DT)
	end
end

local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
local function snap(name, eye, look, fov)
	-- (the camera first, and one frame for him to turn to face it)
	cam.CFrame = CFrame.lookAt(eye, look)
	step(DT)
	realPrint(string.format("SNAP %s %.3f %.3f %.3f %.3f %.3f %.3f%s", name, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z, fov and (" " .. fov) or ""))
	local roots = { arena, workspace:FindFirstChild("BossFX"), char }
	for _, r in ipairs(roots) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local t = d.Transparency or 0
				if t < 0.98 then
					local comps = { d.CFrame:GetComponents() }
					for i, v in ipairs(comps) do
						comps[i] = string.format("%.3f", v)
					end
					local col = d.Color
					realPrint(string.format('{"n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f}',
						esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
						math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
						d.Material.Name, d.Shape and d.Shape.Name or "Block", t))
				end
			end
		end
	end
	local state = model:GetAttribute("State")
	local awake = state == "Waking" or state == "Fighting" or state == "Transition"
	local max = math.max(model:GetAttribute("MaxHealth") or 1, 1)
	local hp = model:GetAttribute("Health") or max
	local barHidden = model:GetAttribute("Action") == "BarWhip"
	realPrint(string.format("BAR %s|%.3f|%d", (awake and not barHidden) and def.Name or "", math.clamp(hp / max, 0, 1), math.min(2, model:GetAttribute("Phase") or 1)))
	realPrint("ENDSNAP")
end

-- a bright day inside a computer, and the captions
realPrint("SKY 150,200,255|225,238,255")
local CAPTIONS = {
	canvas = "1  THE CANVAS: A PENCIL SKETCH IN THE MIDDLE",
	wake = "2  HE INKS HIMSELF IN",
	dash = "3  PENCIL DASH: GET OFF THE LINE",
	eraser = "4  ERASER SWEEP: GET OFF THE STRIP",
	paint = "5  PAINT BUCKET: LEAVE THE SQUARE",
	clones = "6  COPY-PASTE: POP THE CLONES",
	undo = "7  UNDO: PUNCH THE Z KEY IN TIME",
	round2 = "8  ROUND 2: OUT OF THE PAPER",
	cursor = "9  THE CURSOR: ROLL ON THE CLICK",
	whip = "10  BOSS BAR WHIP: JUMP IT",
	errors = "11  ERROR POP-UPS: WALLS FROM THE SKY",
	lag = "12  LAG SPIKE: OFF THE GHOSTS",
	delete = "13  ROUND 3: DELETE FLOOR 9? PUNCH NO!",
	finale = "14  THE END: INTO THE RECYCLE BIN",
	sketch = "ASLEEP: A PENCIL SKETCH",
	idle = "BLUE PEN, A BIG GRIN",
	run = "RUNNING",
	crouch = "PENCIL DASH: READY...",
	skid = "SKIDDING: HIT HIM!",
	dizzy = "STUNNED: HIT HIM!",
	marker = "ROUND 2: RED MARKER",
	rainbow = "ROUND 3: GLITCHING",
	crash = "CRASHED: NOT RESPONDING",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

-- take him over: his brain stopped, put where we say facing `face`, aiming at the player
local function takeOver(pos, face)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.motion, E.sweep = nil, nil
	for _, c in ipairs(E.clones or {}) do
		c.dieAt = 0
	end
	E.zones = {}
	if pos then
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = face or Vector3.new(0, 0, 1)
	end
	E.target, E.targetSince = me, M.now()
	step(DT * 2)
	return E.token
end
local function force(name, pos, face, fn)
	local token = takeOver(pos, face)
	M.task.spawn(function()
		(fn or E.boss.Attacks[name])(E, token)
	end)
	step(DT * 2)
	return model:GetAttribute("ActionStart") or M.now()
end
local function closeUp(name, dist, side, height, lookH)
	local c = E.pos + Vector3.new(0, lookH or 8, 0)
	local look = Vector3.new(0, 0, 1)
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, c + look * (dist or 30) + sideV * (side or 8) + Vector3.new(0, height or 2, 0), c)
end
local function toRound(n)
	local max = model:GetAttribute("MaxHealth") or 1
	if E.phase < 2 then
		takeOver(nil)
		model:SetAttribute("Health", math.floor(max * def.PhaseAt))
		model:FindFirstChild("OnHit"):Fire(me, 1, false)
		step(def.BreakTime + 0.8)
	end
	if n >= 3 and E.phase < 3 then
		takeOver(nil)
		model:SetAttribute("Health", math.floor(max * def.Round3At))
		step(def.GlitchTime + 0.4)
	end
end
local function finish()
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
end

local MID = Vector3.new(C.X, 0, C.Z)
local SOUTH = Vector3.new(0, 0, 1)
local A = def.Attacks

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 58), home)
	step(1)
	closeUp("sketch", 30, 6, 0)
	me:SetAttribute("SpireFloor", 9)
	standAt(home + Vector3.new(0, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	step(def.WakeTime + 0.5)
	takeOver(MID, SOUTH)
	step(4)
	closeUp("idle", 28, 8, 0)
	-- running: after you
	E.chase, E.track = true, true
	standAt(home + Vector3.new(30, 3, 30), home)
	step(0.5)
	closeUp("run", 30, 8, 0)
	local t0 = force("PencilDash", MID, SOUTH)
	standAt(MID + Vector3.new(0, 3, 26), MID)
	stepUntil(t0 + A.PencilDash.Tell * 0.85)
	closeUp("crouch", 28, 8, 0)
	step(A.PencilDash.Tell + 0.3)
	E.pos = E.pos
	closeUp("skid", 28, -8, 0)
	step(3)
	-- stunned: the Z key broken
	takeOver(MID, SOUTH)
	M.task.spawn(function()
		local tok = E.token
		local t1 = E.model:GetAttribute("ActionStart")
		local _ = t1
		-- (straight to the stun, the way breaking the key does it)
		E.boss.Attacks.Undo(E, tok)
	end)
	step(A.Undo.Tell + 0.2)
	for _, t in ipairs(workspace.ScribbleProps:GetChildren()) do
		if t:GetAttribute("Kind") == "UndoKey" then
			t:SetAttribute("Health", 0)
			t:FindFirstChild("OnHit"):Fire(me, 1, true)
		end
	end
	step(0.8)
	closeUp("dizzy", 28, 8, 0)
	step(3)
	toRound(2)
	takeOver(MID, SOUTH)
	step(0.3)
	closeUp("marker", 28, -8, 0)
	toRound(3)
	takeOver(MID, SOUTH)
	E.nextPrompt = math.huge
	step(5)
	closeUp("rainbow", 28, 8, 0)
	-- crashed: the NO pressed
	E.token += 1
	E.nextPrompt = M.now()
	step(1)
	for _, t in ipairs(workspace.ScribbleProps:GetChildren()) do
		if t:GetAttribute("Kind") == "NoButton" then
			t:SetAttribute("Health", 0)
			t:FindFirstChild("OnHit"):Fire(me, 1, true)
		end
	end
	step(1)
	E.pos = MID
	step(0.2)
	closeUp("crash", 28, -8, 0)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the canvas from the door: him a faint pencil sketch in the middle
standAt(spawnPart.Position, home)
step(1)
snap("canvas", C + Vector3.new(14, 20, 57), C + Vector3.new(0, 6, -10))

-- 2) HE INKS HIMSELF IN: the player walks up
standAt(home + Vector3.new(4, 3, 30), home)
me:SetAttribute("SpireFloor", 9)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
stepUntil(model:GetAttribute("ActionStart") + def.WakeTime * 0.5)
snap("wake", home + Vector3.new(14, 10, 34), home + Vector3.new(0, 8, 0))
step(def.WakeTime)
takeOver(MID, SOUTH)
step(4.5)

-- 3) PENCIL DASH: the line drawn, him streaking along it
standAt(MID + Vector3.new(0, 3, 30), MID)
local t0 = force("PencilDash", MID, SOUTH)
stepUntil(t0 + A.PencilDash.Tell * 0.8)
standAt(MID + Vector3.new(9, 3, 30), MID) -- (stepping off the line)
stepUntil(t0 + A.PencilDash.Tell + 0.18)
snap("dash", MID + Vector3.new(34, 22, 58), MID + Vector3.new(0, 2, 22))
step(3)

-- 4) ERASER SWEEP: the giant eraser rubbing the strip
standAt(MID + Vector3.new(0, 3, 24), MID)
t0 = force("EraserSweep", MID, SOUTH)
stepUntil(t0 + A.EraserSweep.Tell * 0.8)
standAt(MID + Vector3.new(0, 3, 14), MID) -- (off the strip)
stepUntil(t0 + A.EraserSweep.Tell + 0.9)
snap("eraser", MID + Vector3.new(30, 24, 62), MID + Vector3.new(0, 2, 18))
step(3)

-- 5) PAINT BUCKET (round 2's three squares come later: one here)
standAt(MID + Vector3.new(4, 3, 26), MID)
t0 = force("PaintBucket", MID, SOUTH)
stepUntil(t0 + A.PaintBucket.Tell * 0.7)
standAt(MID + Vector3.new(4, 3, 36), MID)
stepUntil(t0 + A.PaintBucket.Tell + 0.3)
snap("paint", MID + Vector3.new(30, 26, 64), MID + Vector3.new(0, 2, 22))
step(3)

-- 6) COPY-PASTE: the clones running at you
standAt(MID + Vector3.new(0, 3, 22), MID)
t0 = force("CopyPaste", MID, SOUTH)
stepUntil(t0 + A.CopyPaste.Tell + 0.9)
E.token += 1
standAt(MID + Vector3.new(0, 3, 22), MID)
snap("clones", MID + Vector3.new(18, 12, 44), MID + Vector3.new(0, 4, 14))
for _, c in ipairs(E.clones) do
	c.dieAt = 0
end
step(1)

-- 7) UNDO: the Z key in front of you
local max = model:GetAttribute("MaxHealth")
table.insert(E.recent, { t = M.now(), dmg = math.floor(max * 0.04) })
standAt(MID + Vector3.new(0, 3, 16), MID)
t0 = force("Undo", MID, SOUTH)
stepUntil(t0 + A.Undo.Tell + 0.8)
snap("undo", MID + Vector3.new(12, 9, 34), MID + Vector3.new(0, 5, 6))
step(A.Undo.Window + 1.5)

-- 8) ROUND 2: tearing himself out of the paper
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(0, 3, 30), MID)
model:SetAttribute("Health", math.floor(max * def.PhaseAt))
model:FindFirstChild("OnHit"):Fire(me, 1, false)
local breakAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(breakAt + def.BreakTime * 0.5)
snap("round2", MID + Vector3.new(16, 10, 36), MID + Vector3.new(0, 9, 0))
stepUntil(breakAt + def.BreakTime + 0.6)

-- 9) THE CURSOR: locked on you
standAt(MID + Vector3.new(0, 3, 24), MID)
t0 = force("Cursor", MID, SOUTH)
stepUntil(t0 + A.Cursor.Hunt + A.Cursor.Lock * 0.5)
snap("cursor", MID + Vector3.new(24, 20, 56), MID + Vector3.new(0, 5, 18))
step(4)

-- 10) BOSS BAR WHIP: swinging round
standAt(MID + Vector3.new(0, 3, 22), MID)
t0 = force("BarWhip", MID, SOUTH)
stepUntil(t0 + A.BarWhip.Tell + A.BarWhip.Spin * 0.3)
snap("whip", MID + Vector3.new(30, 24, 50), MID + Vector3.new(0, 2, 4))
step(4)

-- 11) ERROR POP-UPS: windows standing like walls
standAt(MID + Vector3.new(0, 3, 22), MID)
t0 = force("ErrorPopups", MID, SOUTH)
stepUntil(t0 + A.ErrorPopups.Tell + 4 * A.ErrorPopups.Gap + A.ErrorPopups.Fall + 0.2)
snap("errors", MID + Vector3.new(26, 20, 60), MID + Vector3.new(0, 3, 18))
step(4)

-- 12) LAG SPIKE: the ghosts
standAt(MID + Vector3.new(0, 3, 28), MID)
t0 = force("LagSpike", MID, SOUTH)
stepUntil(t0 + A.LagSpike.Tell * 0.85)
snap("lag", MID + Vector3.new(30, 16, 40), MID + Vector3.new(0, 5, 14))
step(3)

-- 13) ROUND 3: the DELETE box, the paper erasing
takeOver(MID, SOUTH)
model:SetAttribute("Health", math.floor(max * def.Round3At))
step(def.GlitchTime + 0.3)
E.token += 1 -- (he stands still: just the box)
step(3)
do
	local box = nil
	for _, t in ipairs(workspace.ScribbleProps:GetChildren()) do
		if t:GetAttribute("Kind") == "NoButton" and not t:GetAttribute("EndKind") then
			box = t
		end
	end
	local c = box and box:GetPivot().Position or (MID + Vector3.new(0, 0, 40))
	local inward = Vector3.new(MID.X - c.X, 0, MID.Z - c.Z).Unit
	standAt(Vector3.new(c.X, 3, c.Z) + inward * 4, Vector3.new(c.X, 0, c.Z))
	local side = inward:Cross(Vector3.new(0, 1, 0))
	snap("delete", Vector3.new(c.X, 0, c.Z) + inward * 34 + side * 16 + Vector3.new(0, 18, 0), Vector3.new(c.X, 5, c.Z) + inward * 6)
end

-- 14) THE END: crumpled into a ball, flying into the recycle bin
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(6, 3, 24), MID)
finish()
step(2.2)
do
	-- (where the ball is now: Poses.Death's own sums - from 3 studs over his
	-- spot to just over the bin, in an arc 26 studs high)
	local bin = arena:GetAttribute("Bin")
	local u = math.clamp((2.2 + 1 / 30 - 1.3) / 1.5, 0, 1)
	local from = E.pos + Vector3.new(0, 3, 0)
	local ball = from:Lerp(bin + Vector3.new(0, 1.5, 0), u) + Vector3.new(0, 26 * math.sin(math.pi * u), 0)
	-- (side-on to its flight, the bin ahead of it in the picture)
	local along = Vector3.new(bin.X - from.X, 0, bin.Z - from.Z).Unit
	local side = along:Cross(Vector3.new(0, 1, 0))
	snap("finale", ball - side * 46 - along * 10 + Vector3.new(0, 2, 0), ball:Lerp(bin, 0.3) + Vector3.new(0, -6, 0))
end
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
