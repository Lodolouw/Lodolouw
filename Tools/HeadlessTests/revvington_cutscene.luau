--!nocheck
-- A ~12-second LOOP of floor 5 for a YouTube Short, starring SPEEDY
-- REVVINGTON, King of the Speedway: the real Piston Speedway
-- (SpeedwayBuilder), the real BossService with his brain stopped and his
-- moves forced like a scripted scene, the real BossClient drawing him
-- (BossBodies/Revvington: the start lights, the countdown, the red lane, the
-- tyre smoke, the backfire's fire, TURBO!'s nitro, the donuts, the race
-- clock) and a blocky player. Every video frame (30 a second) prints what's
-- on screen, the camera, and what the real screen code put on the player's
-- screen (the big words, the race clock, the word bubbles, the hint over his
-- roof); the sounds it played too. render_revvington_cutscene.py films it.
--
--   luau revvington_cutscene.luau > revv.txt
--   python3 render_revvington_cutscene.py revv.txt ../../Docs/animations/revvington_short.mp4 \
--       --font FredokaOne.ttf --pixel-font PressStart2P.ttf
--
-- The scene (s = seconds from the start of his wake, the game's clock):
--   2.1   "2" (the film opens here, mid-countdown) ... (jump cut) ... "1"
--   3.9   GO! (KA-VROOM!, the lights green, the race clock starts)
--   4.2   CHARGE: he skids round, revs, the red lane follows the player and
--         locks - he roars down it; the player dodge-rolls out of the lane
--         at the last moment. He brakes in a skid (turning part way round)
--   then  the player sprints round behind him and punches his back bumper -
--         BACKFIRE: his pipes glow... the player rolls out past his side as
--         it goes BANG! (fire, burning puddles); punches him (low, at his
--         side) while he's open, down past half
--   then  TURBO! (HE'S EVEN FASTER NOW): the nitro blast throws the player
--         back ... (jump cut) ...
--   then  DONUTS (SHOWING OFF! HIT HIM!): punches down to 1% left
--   then  CHARGE (TURBO): the player goes for the last punch instead of
--         rolling (slow motion)... and is run over. Flat. At 1%.
--   -> the first frame: the countdown again (it loops: the race restarting).
--
-- Scripted (not how a real fight would go): his brain is stopped and every
-- move is forced (a charge straight after GO!, a backfire while he's still
-- braking, donuts in TURBO from up close, a TURBO charge from up close); his
-- dice are fixed (the donuts' way round); his health is set as the player's
-- punches land (bigger chunks than real punches); the player runs a little
-- faster than in the game; three jump cuts; slow motion round the last
-- charge. Nobody is really hurt: the scene only notes the moment the real
-- charge's car-box test (carHits) would have run the player over.
--
-- What it prints: STATIC (every speedway part once, indexed), then per frame
-- FRAME (frame, film time, game time, s), CAM, POS (him, the player), STATE,
-- BAR (his name, health, round), the moving parts, changed speedway parts
-- (the start lights), BIG (kit.bigText's words), CLOCK (the race clock), BB
-- (word bubbles and the hint over his roof); and BURST, KICK, SOUND and EVENT
-- lines as they happen.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(5)

local arena = mount.require(mount.module("ServerScriptService/SpeedwayBuilder.lua")).Build()
M.run(1)

----------------------------------------------------------------------
-- the particles BossClient emits, written down for the renderer
----------------------------------------------------------------------
local function first(seq, i, fallback)
	local v = type(seq) == "table" and seq[i]
	return type(v) == "number" and v or fallback
end
M.methods.Emit = function(self, count)
	local holder = self.Parent
	if not (holder and holder.CFrame) then
		return
	end
	local col = type(self.Color) == "table" and self.Color[1] or M.Color3.fromRGB(255, 255, 255)
	local size = type(self.Size) == "table" and self.Size[1] or {}
	local s0 = type(size[1]) == "table" and size[1][2] or 1.5
	local s1 = type(size[2]) == "table" and size[2][2] or s0 * 2.2
	local acc = self.Acceleration or Vector3.new(0, -30, 0)
	local p = holder.Position
	realPrint(string.format("BURST %.4f %.2f %.2f %.2f %d %d %d %d %.2f %.2f %.2f %.2f %.3f %.3f %.1f %.2f %.2f",
		M.now(), p.X, p.Y, p.Z, math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		tonumber(count) or 20, first(self.Speed, 1, 7), first(self.Speed, 2, 14), s0, s1, first(self.Lifetime, 1, 0.36),
		first(self.Lifetime, 2, 0.6), first(self.SpreadAngle, 1, 80), acc.Y, tonumber(self.Drag) or 3))
end

----------------------------------------------------------------------
-- the player: a blocky figure whose arms and legs we pose
----------------------------------------------------------------------
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
local SKIN, SHIRT, PANTS = M.Color3.fromRGB(254, 231, 97), M.Color3.fromRGB(0, 153, 219), M.Color3.fromRGB(62, 137, 72)
local function limb(name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Parent = char
	return p
end
local SIZES = {
	torso = Vector3.new(2, 2, 1), head = Vector3.new(1.2, 1.2, 1.2), larm = Vector3.new(1, 2, 1), rarm = Vector3.new(1, 2, 1),
	lleg = Vector3.new(1, 2, 1), rleg = Vector3.new(1, 2, 1),
}
local body = {
	torso = limb("Torso", SIZES.torso, SHIRT),
	head = limb("Head", SIZES.head, SKIN),
	larm = limb("LeftArm", SIZES.larm, SKIN),
	rarm = limb("RightArm", SIZES.rarm, SKIN),
	lleg = limb("LeftLeg", SIZES.lleg, PANTS),
	rleg = limb("RightLeg", SIZES.rleg, PANTS),
}
local EYE = Vector3.new(0.22, 0.3, 0.1)
local eyes = { limb("Eye", EYE, M.Color3.fromRGB(24, 20, 37)), limb("Eye", EYE, M.Color3.fromRGB(24, 20, 37)) }
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
kick.Event:Connect(function(strength)
	realPrint(string.format("KICK %.4f %.3f", M.now(), tonumber(strength) or 0))
end)
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1080, Y = 1920 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- the pose (as kaze_cutscene.luau): pos = the middle of the body, facing,
-- legs / arms swing, guard raises the arms, spread throws them out, lean
-- tips forward round the hips, tumble flips round the middle (a roll), jump
-- lifts, punch / punchL a straight arm, tuck pulls the knees up; `flat`
-- (seconds since the car ran them over: flat on their back on the track,
-- squashed thin, arms and legs out)
local P = {}
local function resetPose()
	P.pos, P.facing = P.pos or Vector3.zero, Vector3.new(0, 0, -1)
	P.legs, P.arms, P.guard, P.spread, P.lean, P.tumble, P.jump, P.headYaw, P.roll = 0, 0, 0, 0, 0, 0, 0, 0, 0
	P.punch, P.punchL, P.tuck, P.flat = 0, 0, 0, nil
end
resetPose()
local FLOOR_Y = 0
local function pose()
	local look = Vector3.new(P.facing.X, 0, P.facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	if P.flat then
		-- run over: on their back (face up, head the way the car went), thin
		local t = P.flat
		local thin = 0.16 + 0.07 * math.sin(t * 34) * math.exp(-t * 7)
		local at = Vector3.new(P.pos.X, FLOOR_Y + 0.5 * thin + 0.05, P.pos.Z)
		local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(math.pi / 2, 0, 0)
		root.CFrame = CFrame.new(P.pos)
		local function lay(part, size, x, y, turn)
			part.Size = Vector3.new(size.X * 1.25, size.Y * 1.12, size.Z * thin)
			part.CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, turn or 0)
		end
		lay(body.torso, SIZES.torso, 0, 0)
		lay(body.head, SIZES.head, 0, 1.95)
		lay(body.larm, SIZES.larm, -2.05, 0.45, -0.75)
		lay(body.rarm, SIZES.rarm, 2.05, 0.45, 0.75)
		lay(body.lleg, SIZES.lleg, -0.95, -2.3, 0.3)
		lay(body.rleg, SIZES.rleg, 0.95, -2.3, -0.3)
		-- (the eyes on the face, looking up: the face is local -z now)
		local headCf = body.head.CFrame
		local up = -(SIZES.head.Z * thin) / 2 - 0.04
		eyes[1].Size, eyes[2].Size = Vector3.new(0.3, 0.12, 0.08), Vector3.new(0.3, 0.12, 0.08)
		eyes[1].CFrame = headCf * CFrame.new(-0.28, 0.05, up)
		eyes[2].CFrame = headCf * CFrame.new(0.28, 0.05, up)
		return
	end
	for k, part in pairs(body) do
		part.Size = SIZES[k]
	end
	eyes[1].Size, eyes[2].Size = EYE, EYE
	local at = P.pos + Vector3.new(0, P.jump, 0)
	local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(-P.tumble, 0, P.roll) * CFrame.new(0, -1, 0)
		* CFrame.Angles(-P.lean, 0, 0) * CFrame.new(0, 1, 0)
	root.CFrame = CFrame.new(at) * (cf - cf.Position)
	body.torso.CFrame = cf
	local headCf = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, P.headYaw, 0)
	body.head.CFrame = headCf
	local function swing(part, x, y, angle, drop, out)
		part.CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(angle, 0, out or 0) * CFrame.new(0, -drop, 0)
	end
	swing(body.lleg, -0.5, -1, P.legs + P.tuck * 1.3, 1)
	swing(body.rleg, 0.5, -1, -P.legs + P.tuck * 1.3, 1)
	local up = P.guard * 2.2
	local la = (-P.arms + up) * (1 - P.punchL) + (math.pi / 2) * P.punchL
	local ra = (P.arms + up) * (1 - P.punch) + (math.pi / 2) * P.punch
	swing(body.larm, -1.5, 0.5, la, 0.5 + 0.4 * P.punchL, -P.spread * (1 - P.punchL))
	swing(body.rarm, 1.5, 0.5, ra, 0.5 + 0.4 * P.punch, P.spread * (1 - P.punch))
	eyes[1].CFrame = headCf * CFrame.new(-0.25, 0.1, -0.62)
	eyes[2].CFrame = headCf * CFrame.new(0.25, 0.1, -0.62)
end

----------------------------------------------------------------------
-- the boss: the real server and the real screen
----------------------------------------------------------------------
local T0 = 0 -- (the game clock at s = 0: the start of his wake)
local rollUntil = -math.huge -- (the player's roll: untouchable until then, game clock)
local finalFrom = math.huge -- (from then on, the car's box catching the player counts: the last charge)
local runOver = nil -- (when the real carHits caught them in the last charge: game clock)
local shoveAt = nil
local model, def -- (his model and Config entry: filled in below)
local Combat = {
	PlayersInArena = function(f)
		return me:GetAttribute("SpireFloor") == f and { me } or {}
	end,
	IsFighting = function(p)
		return p:GetAttribute("SpireFloor") ~= nil
	end,
	IsInvulnerable = function()
		return M.now() < rollUntil
	end,
	-- (nobody's really hurt: the scene only notes the moment the last charge's
	-- real car-box test catches them)
	DamagePlayer = function(_, damage, from)
		if not runOver and M.now() >= finalFrom and M.now() >= rollUntil and model and model:GetAttribute("Action") == "Charge" then
			runOver = { M.now(), damage }
		end
		return false
	end,
	Shove = function()
		shoveAt = shoveAt or M.now()
	end,
	SetTargetShape = function() end,
}
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }

-- his sounds: a Sound in SoundService for each name in his Config, so the
-- real screen code plays them; every one it plays is written down (SOUND
-- time name volume) for the renderer to mix
do
	local SoundService = M.game:GetService("SoundService")
	local cfg = mount.require(mount.module("ReplicatedStorage/Config.lua"))
	for _, name in pairs(cfg.Bosses[5].Sounds) do
		local snd = Instance.new("Sound")
		snd.Name = name
		snd.Parent = SoundService
	end
end
M.methods.Play = function(self)
	if self and self.ClassName == "Sound" then
		realPrint(string.format("SOUND %.4f %s|%.3f", M.now(), (string.gsub(tostring(self.Name), "[%c|]", "")), tonumber(self.Volume) or 1))
	end
end

local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(5)
model, def = E.model, E.def
local floorY = E.floorY or E.home.Y
FLOOR_Y = floorY
local HOME = Vector3.new(E.home.X, floorY, E.home.Z) -- (his spot on the start line)
local C = arena:GetAttribute("Center")
C = Vector3.new(C.X, floorY, C.Z) -- (the middle of the track)
-- his brain stopped (only for this scene): BossService starts it after the
-- countdown and after TURBO; here it does nothing, and the scene says what he does
E.boss.brain = function() end
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

local T = M.now()
local DT = 1 / 30
local function tick(dt)
	T += dt
	M.run(T)
	RunService.Heartbeat:Fire(dt)
	RunService.RenderStepped:Fire(dt)
end
local function advanceTo(t)
	while T < t - 1e-6 do
		tick(math.min(DT, t - T))
	end
end

-- his dice: fixed by the scene (NextNumber answers RNG)
local RNG = 0.2
E.rng = { NextNumber = function() return RNG end, NextInteger = function(_, lo) return lo end }

-- whatever he was doing stopped (he stays where his segment has him),
-- aiming at the player
local function takeOver()
	E.token += 1
	E.contact, E.wheelie = nil, false
	E.target, E.targetSince = me, M.now()
	return E.token
end
local function force(name)
	local token = takeOver()
	M.task.spawn(function()
		E.boss.Attacks[name](E, token)
	end)
end
local function setPct(pct)
	-- (pct = how much of him is gone)
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.max(1, math.floor(max * (1 - pct / 100) + 0.5)))
end

----------------------------------------------------------------------
-- what's printed
----------------------------------------------------------------------
local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
local function rgb(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function partLine(d, index)
	local comps = { d.CFrame:GetComponents() }
	for i, v in ipairs(comps) do
		comps[i] = string.format("%.3f", v)
	end
	local col = d.Color
	return string.format('{"n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f%s}',
		esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
		math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		d.Material.Name, d.Shape and d.Shape.Name or "Block", d.Transparency or 0, index and (',"i":' .. index) or "")
end
local fx = workspace:FindFirstChild("BossFX")
local statics = {}
local function isDynamic(d)
	fx = fx or workspace:FindFirstChild("BossFX")
	return (fx and d:IsDescendantOf(fx)) or d:IsDescendantOf(char) or d:IsDescendantOf(model)
end
local function dumpStatic()
	realPrint("STATIC")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not isDynamic(d) and (d.Position - C).Magnitude < 700 then
			local pr = rawget(d, "__props")
			statics[#statics + 1] = { d, pr.CFrame, pr.Size, pr.Color, pr.Transparency }
			if (d.Transparency or 0) < 0.98 then
				realPrint(partLine(d, #statics))
			end
		end
	end
	realPrint("ENDSTATIC")
end
local function v3(v)
	return string.format("%.3f %.3f %.3f", v.X, v.Y, v.Z)
end
local function firstLabel(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("TextLabel") then
			return d
		end
	end
	return nil
end
local function dumpScreen()
	local big = gui:FindFirstChild("BossBigText")
	if big and big.Enabled then
		local holder = big:FindFirstChildOfClass("Frame")
		local label = holder and holder:FindFirstChild("Big")
		local sub = holder and holder:FindFirstChild("Sub")
		local limit = label and label:FindFirstChildOfClass("UITextSizeConstraint")
		if label and (label.TextTransparency or 0) < 0.99 then
			realPrint(string.format("BIG %s|%s|%s|%s|%.3f|%d", esc(label.Text), rgb(label.TextColor3), esc(sub and sub.Text or ""),
				rgb(sub and sub.TextColor3 or M.Color3.new(1, 1, 1)), holder.Position.Y.Scale, limit and limit.MaxTextSize or 64))
		end
	end
	-- his RACE CLOCK (BossBodies/Revvington's RevvingtonClock, under the boss bar)
	local clock = gui:FindFirstChild("RevvingtonClock")
	if clock and clock.Enabled then
		local label = clock:FindFirstChild("Time")
		if label and label.Text ~= "" then
			realPrint(string.format("CLOCK %s|%s", esc(label.Text), rgb(label.TextColor3)))
		end
	end
	local seen = {}
	local function bubble(bb)
		if seen[bb] or not bb.Adornee or not bb.Adornee.Parent then
			return
		end
		seen[bb] = true
		local label = firstLabel(bb)
		if not label then
			return
		end
		local stroke = nil
		for _, d in ipairs(bb:GetDescendants()) do
			if d:IsA("UIStroke") then
				stroke = d
			end
		end
		local off = bb.StudsOffsetWorldSpace or Vector3.zero
		realPrint(string.format("BB %s|%s|%s|%s|%s", esc(bb.Name), esc(label.Text), rgb(label.TextColor3),
			stroke and rgb(stroke.Color) or "", v3(bb.Adornee.Position + off)))
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("BillboardGui") then
			bubble(d)
		end
	end
	fx = fx or workspace:FindFirstChild("BossFX")
	for _, d in ipairs(fx and fx:GetDescendants() or {}) do
		if d:IsA("BillboardGui") then
			bubble(d)
		end
	end
end
local frame = 0
local camEye, camLook, camFov = HOME, HOME, 70
local function bossAt()
	local p = model:GetPivot().Position
	return Vector3.new(p.X, floorY, p.Z)
end
local function dumpFrame(v, s)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f %.4f", frame, v, M.now(), s))
	realPrint(string.format("CAM %s %s %.2f", v3(camEye), v3(camLook), camFov))
	local b = bossAt()
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", b.X, b.Y, b.Z, P.pos.X, P.pos.Y + P.jump, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action"))))
	local st = model:GetAttribute("State")
	local awake = st == "Waking" or st == "Fighting" or st == "Transition"
	realPrint(string.format("BAR %s|%.4f|%d", awake and esc(def.Name) or "", (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), model:GetAttribute("Phase") or 1))
	fx = fx or workspace:FindFirstChild("BossFX")
	local roots = { char }
	if fx then
		table.insert(roots, fx)
	end
	for _, r in ipairs(roots) do
		for _, d in ipairs(r:GetDescendants()) do
			if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 and d ~= root then
				realPrint(partLine(d))
			end
		end
	end
	for i, st2 in ipairs(statics) do
		local d = st2[1]
		local pr = rawget(d, "__props")
		if pr.CFrame ~= st2[2] or pr.Size ~= st2[3] or pr.Color ~= st2[4] or pr.Transparency ~= st2[5] then
			realPrint(partLine(d, i))
		end
	end
	dumpScreen()
	realPrint("ENDFRAME")
end
local function event(name, v, extra)
	realPrint(string.format("EVENT %s %.4f %s", name, v, extra or ""))
end

----------------------------------------------------------------------
-- the script (s = seconds from the start of his wake)
----------------------------------------------------------------------
local A = def.Attacks
local function ease(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.05 and f.Unit or (fallback or Vector3.new(0, 0, -1))
end
local function rightOf(dir)
	return Vector3.new(-dir.Z, 0, dir.X)
end
local ROLL_TIME, ROLL_SPEED = 0.28, 62 -- (Config.Combat: RollTime, RollSpeed; untouchable for 0.5 s)
local ROLL_SAFE = 0.5
local SPRINT = 34 -- (studs a second: a little faster than the game's run)
-- which way is the infield from the start line (toward the middle of the track)
local INFIELD = flatUnit(C - HOME, Vector3.new(0, 0, -1))
local ALONG = -rightOf(INFIELD) -- (down the straight: the way he faces on the start line is -ALONG)

local WT = def.WakeTime
local GO = WT - 0.3 -- GO! (BossBodies/Revvington's countTimes)
local FILM_FROM = GO - 1.8 + 0.04 -- the first frame: "2" just up
local CH1 = WT + 0.03 -- CHARGE (once he's fighting: the wake's over)
local ROAR1 = CH1 + A.Charge.Tell[1]
local ROLL1 = ROAR1 + 0.15 -- the dodge-roll out of the lane, at the last moment
local START = HOME - ALONG * 28 + Vector3.new(0, 3, 0) -- where the player stands for the countdown (in front of him)
-- the rest is planned once the charge's lane locks (where he'll stop): plan()
local TL = nil
local PUNCHES = {}
local CUTS = { { FILM_FROM + 0.55, GO - 0.93 } }
local SLOW_RATE = 0.3
local AFTER = 0.95 -- how long the film runs on after the car gets them

local function plan(brakeEnd, line)
	local bf = brakeEnd + 0.02
	TL = {}
	-- (where he'll stop: the end of the lane and a skid on)
	TL.CDIR = flatUnit(line.b - line.a, -ALONG)
	TL.STOP = Vector3.new(line.b.X, floorY, line.b.Z) + TL.CDIR * 7
	TL.BF = bf -- BACKFIRE (the pipes glow for its Tell)
	TL.ROLL2 = bf + 0.56 -- out past his side as it goes BANG
	TL.BREAK = bf + 1.72 -- TURBO! (his health under half)
	TL.DONUTS = TL.BREAK + def.BreakTime + 0.05
	TL.FINAL = TL.DONUTS + 1.36 -- the TURBO charge
	TL.ROAR2 = TL.FINAL + A.Charge.Tell[2]
	TL.SLOW_FROM = TL.FINAL + 0.5
	CUTS[2] = { TL.BREAK + 0.42, TL.BREAK + 0.88 }
	CUTS[3] = { TL.BREAK + 2.5, TL.DONUTS - 0.01 }
	PUNCHES = {
		{ bf + 0.27, 6 }, { bf + 0.45, 12 },
		{ bf + 1.08, 21 }, { bf + 1.23, 30 }, { bf + 1.38, 39 }, { bf + 1.53, 47 },
		{ TL.DONUTS + 0.22, 57 }, { TL.DONUTS + 0.4, 66 }, { TL.DONUTS + 0.58, 75 }, { TL.DONUTS + 0.76, 84 },
		{ TL.DONUTS + 0.94, 92 }, { TL.DONUTS + 1.14, 99 },
	}
end

local function run(ph, k)
	P.legs, P.arms = math.sin(ph) * 0.95 * k, math.sin(ph + 0.6) * 0.9 * k
	P.lean, P.spread = 0.25 * k, 0.25
	P.jump = 0.12 * math.abs(math.sin(ph)) * k
end
local function punchAt(s)
	local best, side = 0, 1
	for i, pu in ipairs(PUNCHES) do
		local d = s - (pu[1] - 0.07)
		if d >= 0 and d < 0.16 then
			best = math.sin(math.pi * d / 0.16)
			side = (i % 2 == 0) and -1 or 1
		end
	end
	if side > 0 then
		P.punch = best
	else
		P.punchL = best
	end
	return best
end
-- a roll from `from` along `dir` starting at s0: tumbling, tucked
local function rolling(s, s0, from, dir)
	local u = math.clamp((s - s0) / ROLL_TIME, 0, 1)
	P.pos = from + dir * (ROLL_SPEED * ROLL_TIME) * u
	P.facing = dir
	P.tumble = 2 * math.pi * ease(u)
	P.tuck = math.sin(math.pi * u) * 1.1
	P.guard = 0.8
	P.jump = -0.9 * math.sin(math.pi * u)
	return P.pos
end
local function towardBoss(from)
	return flatUnit(bossAt() - from, -ALONG)
end
local function bossFacing()
	return flatUnit(E.facing or Vector3.new(0, 0, -1))
end
local function standY(p)
	return Vector3.new(p.X, floorY + 3, p.Z)
end

-- the player's own state across frames (where they've run to)
local runPos, lastS = nil, nil
local rollFrom2, rollDir2 = nil, nil
local shovedFrom, donutSpot, flatAt = nil, nil, nil
-- runs toward `want` (a spot that may move), at SPRINT; true once there
local function sprintTo(s, want)
	local ds = math.max(0, s - (lastS or s))
	local d = want - runPos
	d = Vector3.new(d.X, 0, d.Z)
	local step = SPRINT * ds
	if d.Magnitude <= step or d.Magnitude < 0.05 then
		runPos = want
		return true
	end
	runPos = runPos + d.Unit * step
	P.facing = d.Unit
	run(s * 22, 1)
	return false
end

local function placePlayer(s)
	resetPose()
	local function done()
		lastS = s
	end
	if s < ROLL1 then
		-- 1) 3... 2... 1... GO!: guard up, bouncing; then the lane on them
		P.pos, P.facing = START, towardBoss(START)
		P.guard, P.spread = 0.6, 0.25
		P.legs = 0.08 * math.sin(s * 6)
		P.jump = 0.1 * math.abs(math.sin(s * 5))
		if s > CH1 + 0.6 then
			P.guard, P.spread, P.lean = 0.85, 0.45, -0.1
		end
		return done()
	end
	if s < ROLL1 + ROLL_TIME + 0.04 then
		runPos = rolling(s, ROLL1, START, INFIELD)
		return done()
	end
	if not TL or s < TL.BF + 0.2 then
		-- 2) up, and sprinting round behind him as he brakes
		local tail = standY(E.pos - bossFacing() * 11.5)
		if s < ROLL1 + ROLL_TIME + 0.2 then
			-- (a moment to get up and look)
			P.pos, P.facing = runPos, towardBoss(runPos)
			P.guard, P.lean = 0.5, -0.1
			return done()
		end
		if not sprintTo(s, tail) then
			P.pos = runPos
			return done()
		end
		P.pos, P.facing = runPos, towardBoss(runPos)
		P.guard = 0.6
		punchAt(s)
		return done()
	end
	if s < TL.ROLL2 then
		-- 3) at his back bumper, punching low (the pipes glowing)
		runPos = standY(E.pos - bossFacing() * 11.5)
		P.pos, P.facing = runPos, towardBoss(runPos)
		P.guard, P.lean = 0.6, 0.18
		punchAt(s)
		return done()
	end
	if not rollFrom2 then
		local f = bossFacing()
		local side = rightOf(f)
		if side:Dot(-TL.CDIR) < 0 then
			side = -side
		end
		rollFrom2 = runPos
		rollDir2 = flatUnit(side * 0.8 + f * 0.6)
	end
	if s < TL.ROLL2 + ROLL_TIME + 0.04 then
		runPos = rolling(s, TL.ROLL2, rollFrom2, rollDir2)
		return done()
	end
	if s < TL.BREAK then
		-- 4) in at his side (the fire behind him): punches while he's open
		local f = bossFacing()
		local side = rightOf(f)
		if (rollFrom2 + rollDir2 * 17 - E.pos):Dot(side) < 0 then
			side = -side
		end
		local spot = standY(E.pos - f * 2.5 + side * 7.8)
		if not sprintTo(s, spot) then
			P.pos = runPos
			return done()
		end
		P.pos, P.facing = runPos, towardBoss(runPos)
		P.guard, P.lean = 0.6, 0.2
		punchAt(s)
		return done()
	end
	if s < TL.DONUTS then
		-- 5) TURBO!: the nitro's blast throws them back
		local from = runPos
		P.facing = towardBoss(from)
		local sh = shoveAt and (shoveAt - T0) or (TL.BREAK + def.BreakTime * 0.35)
		if s < sh then
			P.pos = from
			P.guard, P.spread = 0.8, 0.5
			return done()
		end
		local u = s - sh
		local away = flatUnit(from - E.pos, INFIELD)
		local k = 1 - math.exp(-u * 7)
		P.pos = from + away * 13 * k
		P.jump = math.max(0, 9 * u - 0.5 * 60 * u * u)
		P.lean = -0.5 * math.exp(-u * 3)
		P.spread, P.guard = 0.9 * math.exp(-u * 2), 0.5
		P.tumble = -0.5 * math.sin(math.min(u / 0.5, 1) * math.pi)
		shovedFrom = from + away * 13
		return done()
	end
	if not donutSpot then
		-- (down the straight from him: where his last charge has room)
		donutSpot = standY(E.pos + ALONG * 12.2)
	end
	if s < TL.FINAL then
		-- 6) DONUTS: every punch (SHOWING OFF! HIT HIM!)
		P.pos, P.facing = donutSpot, towardBoss(donutSpot)
		P.guard, P.lean = 0.6, 0.16
		P.jump = 0.1 * math.abs(math.sin(s * 9))
		punchAt(s)
		return done()
	end
	if not runOver or s < runOver[1] - T0 then
		-- 7) 1% LEFT: the last punch, wound right back... as he revs
		local u = s - TL.FINAL
		local k = ease(u / 0.6)
		P.pos = donutSpot + towardBoss(donutSpot) * 0.8 * k
		P.facing = towardBoss(P.pos)
		P.guard = 0.25
		P.lean = 0.12 + 0.12 * k
		P.punch = -0.55 * k -- (the right arm pulled back)
		P.arms = 0.5 * k
		P.spread = 0.3
		P.jump = 0.06 * math.abs(math.sin(s * 10))
		return done()
	end
	-- 8) run over: flat
	flatAt = flatAt or (donutSpot + towardBoss(donutSpot) * 0.8)
	P.pos = flatAt
	P.facing = ALONG -- (head the way the car went)
	P.flat = s - (runOver[1] - T0)
	return done()
end

----------------------------------------------------------------------
-- the film's camera
----------------------------------------------------------------------
-- over the player's shoulder at him: `back` behind them, `up`, `side` to
-- their right; looking between them and him (more at him for `toward`)
local function overShoulder(back, up, side, fov, toward, lift)
	local p = P.pos
	local bo = bossAt()
	local d = flatUnit(p - bo, Vector3.new(0, 0, 1))
	local r = Vector3.new(-d.Z, 0, d.X)
	local eye = p + d * back + r * (side or 0) + Vector3.new(0, up, 0)
	local look = p:Lerp(bo + Vector3.new(0, lift or 4, 0), toward or 0.6)
	return eye, look, fov
end
local held = {}
local function hold(key, fn)
	-- a shot that's worked out once (where it starts) and then stays put
	if not held[key] then
		held[key] = { fn() }
	end
	return held[key][1], held[key][2], held[key][3]
end
-- (the HUD covers the top third of a phone screen: every shot looks a little
-- above what matters, so it sits in the lower two thirds)
local function shot(s)
	if s < CH1 + 0.1 then
		-- 3... 2... 1... GO!: low behind the player, the start lights over him
		local k = ease((s - FILM_FROM) / 2.2)
		local e, l, f = overShoulder(11 - 2 * k, 4, 3.5, 52, 0.85, 8)
		return e, l, f
	end
	if s < ROAR1 + 0.4 then
		-- the charge: low beside the lane, behind the player (he roars past on the right)
		local e, l, f = hold("charge", function()
			local eye = START - ALONG * 11 + INFIELD * 8 + Vector3.new(0, 1.5, 0)
			return eye, START:Lerp(HOME + Vector3.new(0, 3, 0), 0.55) + Vector3.new(0, 3, 0), 60
		end)
		return e, l, f
	end
	if not TL or s < TL.BREAK then
		-- the brake, the backfire, the punches: from the infield, following him
		local b = bossAt()
		-- (from back up the lane, a little to the outside: he's side on once he's
		-- skidded round, the player at his tail)
		local e, l, f = hold("brake", function()
			return TL.STOP - TL.CDIR * 30 - INFIELD * 4 + Vector3.new(0, 9, 0), TL.STOP + Vector3.new(0, 2.5, 0), 56
		end)
		local mid = b:Lerp(P.pos, 0.3) - bossFacing() * 8 + Vector3.new(0, 2.5, 0) -- (his tail in, for the backfire)
		return e, l:Lerp(mid, 0.6), f
	end
	if s < TL.DONUTS then
		-- TURBO!: in front of him (his face), pushing in
		local b = bossAt()
		local k = ease((s - TL.BREAK) / 2.6)
		local F = hold("turboF", function()
			return bossFacing()
		end)
		return b + F * (28 - 5 * k) + rightOf(F) * (7 - 2 * k) + Vector3.new(0, 8.5 - k, 0), b + Vector3.new(0, 6.8, 0), 60
	end
	if not runOver or s < runOver[1] - T0 + 0.2 then
		-- the donuts, the last punch, the TURBO charge: from the infield,
		-- side on (he roars in from the left), looking between him and the player
		local e, l, f = hold("donuts", function()
			local mid = E.pos:Lerp(donutSpot or E.pos, 0.55)
			return mid + INFIELD * 33 + Vector3.new(0, 8, 0), mid + Vector3.new(0, 4.2, 0), 60
		end)
		local between = bossAt():Lerp(P.pos, 0.5)
		return e, Vector3.new(between.X, l.Y, between.Z), f
	end
	-- run over: from just behind the flat player, him skidding away down the straight
	local e, l, f = hold("flat", function()
		local p = flatAt
		return p - ALONG * 11 + INFIELD * 5 + Vector3.new(0, 12.5, 0), p + ALONG * 10 + Vector3.new(0, 1, 0), 60
	end)
	local b = bossAt()
	local p = flatAt
	return e, (p + ALONG * 8 + Vector3.new(0, 1, 0)):Lerp(b + Vector3.new(0, 1, 0), 0.12), f
end

----------------------------------------------------------------------
-- before the camera rolls: the player walks up, he wakes
----------------------------------------------------------------------
P.pos, P.facing = START, -ALONG
pose()
advanceTo(T + 0.5)
dumpStatic()
cam.CFrame = CFrame.lookAt(START - ALONG * 12 + Vector3.new(0, 4, 0), HOME + Vector3.new(0, 5, 0))
me:SetAttribute("SpireFloor", 5)
while model:GetAttribute("Action") ~= "Wake" do
	advanceTo(T + DT)
end
T0 = model:GetAttribute("ActionStart")
local function setCam(s)
	camEye, camLook, camFov = shot(s)
	cam.CFrame = CFrame.lookAt(camEye, camLook)
end
local function stepTo(s)
	placePlayer(s)
	pose()
	setCam(s)
	advanceTo(T0 + s)
end
stepTo(FILM_FROM - DT)

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
local done = {}
local function once(name, when, ss, fn)
	if when and not done[name] and ss >= when - 1e-6 then
		done[name] = true
		advanceTo(T0 + when)
		fn()
	end
end
local ss = FILM_FROM
local v = 0
local k = 0
local cutsDone = {}
local slowFrom, slowTo = nil, nil
local stopAt = nil
while true do
	k += 1
	-- his moves, on their moments
	once("racestart", WT, ss, function()
		model:SetAttribute("RaceStart", T0 + GO) -- (as his brain does at GO!)
	end)
	once("charge1", CH1, ss, function()
		force("Charge")
		event("charge", v, "1")
	end)
	once("roll1", ROLL1, ss, function()
		rollUntil = M.now() + ROLL_SAFE
		event("roll", v, "1")
	end)
	-- the brake: when the charge's run down the lane is published, plan the rest
	if not TL and ss > CH1 + 0.2 and E.seg and E.seg.kind == "Line" then
		plan(E.seg.t0 + E.seg.dur + A.Charge.Brake - T0, E.seg)
		for _, pu in ipairs(PUNCHES) do
			event("punch", pu[1], string.format("%d", pu[2]))
		end
	end
	if TL then
		once("backfire", TL.BF, ss, function()
			force("Backfire")
			event("backfire", v, "")
		end)
		once("roll2", TL.ROLL2, ss, function()
			rollUntil = M.now() + ROLL_SAFE
			event("roll", v, "2")
		end)
		once("break", TL.BREAK, ss, function()
			model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
			model:FindFirstChild("OnHit"):Fire(me, 1, false)
			event("break", v, "")
		end)
		once("donuts", TL.DONUTS, ss, function()
			RNG = 0.2 -- (round the way that swings his nose away from the player first)
			force("Donuts")
			event("donuts", v, "")
		end)
		once("final", TL.FINAL, ss, function()
			finalFrom = M.now()
			force("Charge")
			event("final", v, "")
		end)
		for i, pu in ipairs(PUNCHES) do
			once("punch" .. i, pu[1], ss, function()
				setPct(pu[2])
				local hitAt = P.pos + P.facing * 2.4 + Vector3.new(0, -0.4, 0)
				event("hit", v, string.format("%d %s", pu[2], v3(hitAt)))
			end)
		end
	end
	stepTo(ss)
	if runOver and not done.caught then
		done.caught = true
		event("caught", v, string.format("%.4f %s", runOver[1] - T0, v3(P.pos)))
		slowTo = runOver[1] - T0 + 0.2
		stopAt = runOver[1] - T0 + 0.2 + AFTER
	end
	dumpFrame(v, ss)
	-- the next frame's s
	local step = DT
	if TL and ss >= TL.SLOW_FROM - 1e-6 and (not slowTo or ss < slowTo) then
		slowFrom = slowFrom or ss
		step = DT * SLOW_RATE
	end
	local nxt = ss + step
	for i, c in ipairs(CUTS) do
		if not cutsDone[i] and nxt >= c[1] - 1e-6 then
			cutsDone[i] = true
			nxt = c[2]
			event("cut", v + DT, string.format("%.4f %.4f", c[1], c[2]))
		end
	end
	if stopAt and nxt >= stopAt then
		break
	end
	if k > 1200 then
		realPrint("ERROR the car never caught them")
		break
	end
	ss = nxt
	v += DT
end
event("loop", 0, string.format("%d %.4f %.4f %.4f", k, slowFrom or 0, slowTo or 0, SLOW_RATE))
event("times", 0, string.format("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", FILM_FROM, GO, CH1, TL.BF, TL.BREAK, TL.DONUTS,
	TL.FINAL, TL.ROAR2))
event("stage", 0, v3(C))
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
