--!nocheck
-- A ~14-second LOOP of floor 6 for a YouTube Short, starring GRIDLOCK, the
-- Final Beat: the real Final Beat level (GridBuilder), the real BossService
-- with his brain stopped and his moves forced like a scripted scene (on his
-- real beat: Config's Bpm), the real BossClient drawing him
-- (BossBodies/Gridlock: the cube, the ship, the portals, the lit and spiking
-- tiles, THE DROP, the jump pads, his screen words and the level's % bar),
-- and a blocky player. Every video frame (30 a second) prints what's on
-- screen, the camera, and what's on the player's screen (the big words, the
-- % bar, the word bubbles); render_gridlock_cutscene.py films it.
--
--   luau gridlock_cutscene.luau > gridlock.txt
--   python3 render_gridlock_cutscene.py gridlock.txt ../../Docs/animations/gridlock_short.mp4
--
-- The scene, beat by beat (128 a minute: a beat is 0.469 s; beat 0 = the
-- first frame):
--   0     ATTEMPT 847: the level starts again (the real ATTEMPT N words, the
--         grid lighting up from the middle a ring a beat). At once a HOP
--         SLAM: his square lights under the player - they run - he flips
--         through the air and SLAMS (beat 2) - the ring of spikes (beat 3):
--         they jump it, land by him and punch (0% -> 14%).
--   6     a PORTAL: he flies through it and comes out a SHIP.
--   8     SWOOP: the lane locks on the player, the ship dives down it - they
--         dive out of the way.
--   12    another PORTAL: a CUBE again.
--   14    THE DROP: DROP IN 3... 2... 1... the player runs onto a jump pad,
--         which throws them up as the whole floor spikes (beat 18). He
--         crashes down, STUNNED.
--         (a jump cut: beats 19.2 -> 21.5)
--   21.5  STUNNED! HIT HIM! - punches: 14% -> 96%.
--   25    CHECKERS: the tiles round the player spike, then theirs is lit;
--         punch - 97, 98, 99%... they hop off a frame late (slow motion)
--         and a spike clips them: dead at 99%.
--   30    -> the first frame: ATTEMPT 847 again (it loops: a restart).
--
-- The game clock runs with the film's but for the jump cut and one slow
-- motion stretch (the clip).
--
-- What it prints: STATIC (every level part once, indexed), then per frame
-- FRAME (frame, film time, game time, s = game seconds from the first
-- frame), CAM (eye, look, fov), POS (him, the player), STATE, BAR, the moving
-- parts, changed level parts, and the player's screen: BIG (kit.bigText's
-- words), PCT (the % bar), BB (word bubbles over him: the shouts, the hint);
-- and BURST, KICK and EVENT lines as they happen.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(6)

local arena = mount.require(mount.module("ServerScriptService/GridBuilder.lua")).Build()
local BeatGrid = mount.require(mount.module("ReplicatedStorage/BeatGrid.lua"))
M.run(1)

----------------------------------------------------------------------
-- the particles BossClient emits, written down for the renderer
----------------------------------------------------------------------
local function first(seq, i, fallback)
	local v = type(seq) == "table" and seq[i]
	return type(v) == "number" and v or fallback
end
local function burstLine(p, r, g, b, count, s0, s1, v0, v1, l0, l1, spread, accY, drag)
	realPrint(string.format("BURST %.4f %.2f %.2f %.2f %d %d %d %d %.2f %.2f %.2f %.2f %.3f %.3f %.1f %.2f %.2f",
		M.now(), p.X, p.Y, p.Z, r, g, b, count, v0, v1, s0, s1, l0, l1, spread, accY, drag))
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
	burstLine(holder.Position, math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		tonumber(count) or 20, s0, s1, first(self.Speed, 1, 7), first(self.Speed, 2, 14), first(self.Lifetime, 1, 0.36),
		first(self.Lifetime, 2, 0.6), first(self.SpreadAngle, 1, 80), acc.Y, tonumber(self.Drag) or 3)
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
local body = {
	torso = limb("Torso", Vector3.new(2, 2, 1), SHIRT),
	head = limb("Head", Vector3.new(1.2, 1.2, 1.2), SKIN),
	larm = limb("LeftArm", Vector3.new(1, 2, 1), SKIN),
	rarm = limb("RightArm", Vector3.new(1, 2, 1), SKIN),
	lleg = limb("LeftLeg", Vector3.new(1, 2, 1), PANTS),
	rleg = limb("RightLeg", Vector3.new(1, 2, 1), PANTS),
}
local eyes = { limb("Eye", Vector3.new(0.22, 0.3, 0.1), M.Color3.fromRGB(24, 20, 37)),
	limb("Eye", Vector3.new(0.22, 0.3, 0.1), M.Color3.fromRGB(24, 20, 37)) }
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

-- the pose: pos = the middle of the body (the root), facing, legs / arms
-- swing, guard raises the arms, spread throws them out, lean tips forward
-- round the hips, tumble flips round the middle, jump lifts, punch (0-1) the
-- right arm straight out (punchL the left), tuck pulls the knees up; and
-- `dead` (seconds since a spike clipped them: the Roblox way - every limb
-- falls off on its own)
local P = {}
local function resetPose()
	P.pos, P.facing = P.pos or Vector3.zero, Vector3.new(0, 0, -1)
	P.legs, P.arms, P.guard, P.spread, P.lean, P.tumble, P.jump, P.headYaw, P.roll = 0, 0, 0, 0, 0, 0, 0, 0, 0
	P.punch, P.punchL, P.tuck, P.dead = 0, 0, 0, nil
end
resetPose()
-- (where each limb flies when they die: velocity, spin)
local DEATH = {
	head = { Vector3.new(0.5, 22, 6), Vector3.new(4, 6, 2) },
	torso = { Vector3.new(-1, 12, 5), Vector3.new(-3, 1, 2) },
	larm = { Vector3.new(-11, 16, 2), Vector3.new(6, 2, 5) },
	rarm = { Vector3.new(12, 17, 3), Vector3.new(-5, 3, 6) },
	lleg = { Vector3.new(-6, 9, 7), Vector3.new(7, 0, 3) },
	rleg = { Vector3.new(7, 10, 6), Vector3.new(-6, 2, 4) },
}
local FLOOR_Y = 0
local function pose()
	local look = Vector3.new(P.facing.X, 0, P.facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
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
	if P.dead then
		-- every limb off on its own: thrown, spinning, bouncing to a stop
		local t = P.dead
		for k, p in pairs(body) do
			local d = DEATH[k]
			local base = p.CFrame
			local v, w = d[1], d[2]
			local y = base.Position.Y + v.Y * t - 0.5 * 70 * t * t
			local rest = FLOOR_Y + 0.5
			local slide = math.min(t, 0.9)
			if y < rest then
				y = rest
			end
			local spin = math.min(t, 0.75)
			p.CFrame = CFrame.new(base.Position.X + v.X * slide * 0.6, y, base.Position.Z + v.Z * slide * 0.6)
				* (base - base.Position) * CFrame.Angles(w.X * spin, w.Y * spin, w.Z * spin)
		end
		headCf = body.head.CFrame
	end
	eyes[1].CFrame = headCf * CFrame.new(-0.25, 0.1, -0.62)
	eyes[2].CFrame = headCf * CFrame.new(0.25, 0.1, -0.62)
end

----------------------------------------------------------------------
-- the boss: the real server brain and the real screen
----------------------------------------------------------------------
local launches = {}
local padLaunch, dropOn = nil, false
local T0 = 0 -- (the game clock at the first frame: set before the film)
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
	-- (a jump pad throwing the player up: the scene moves them itself, on
	-- the same numbers - Config's Pads.Power - and writes it down)
	Launch = function(_, v)
		table.insert(launches, { M.now(), v.Y })
		if dropOn then
			padLaunch = padLaunch or M.now() -- (the first throw in THE DROP: the scene flies them from here)
		end
	end,
}
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }

-- his sounds: a Sound in SoundService for each name in his Config (as
-- Tools/Sounds/out has them), so the real screen code plays them; every one
-- it plays is written down (SOUND time name volume) for the renderer to mix
do
	local SoundService = M.game:GetService("SoundService")
	local cfg = mount.require(mount.module("ReplicatedStorage/Config.lua"))
	for _, name in pairs(cfg.Bosses[6].Sounds) do
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
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 6 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(6)
local model, def = E.model, E.def
local floorY = E.floorY or E.home.Y
FLOOR_Y = floorY
local C = arena:GetAttribute("Center") or E.home
local MID = Vector3.new(C.X, floorY, C.Z)
cam.CFrame = CFrame.lookAt(MID + Vector3.new(0, 20, 60), MID)
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

-- BossService's setAction (the same attributes, in the same order): for
-- the level restarting (an ATTEMPT) without the whole wake
local SLOTS = { "ActA", "ActB", "ActC", "Act4", "Act5", "Act6", "Act7", "Act8", "Act9", "Act10", "Act11", "Act12", "Act13", "Act14",
	"Act15", "Act16", "Act17", "Act18", "Act19", "Act20", "Act21", "Act22", "Act23", "Act24" }
local function setAction(name, number)
	E.actionId = E.actionId + 1
	for _, key in ipairs(SLOTS) do
		model:SetAttribute(key, nil)
	end
	model:SetAttribute("ActK", 0)
	model:SetAttribute("ActN", number)
	model:SetAttribute("Action", name)
	model:SetAttribute("ActionStart", M.now())
	model:SetAttribute("ActionId", E.actionId)
end

-- his brain stopped; him put where we say, in `form`, aiming at the player
local function takeOver(pos, form, face)
	E.token += 1
	E.contact = nil
	if form then
		E.form = form
		model:SetAttribute("Form", form)
		E.gravity = 1
		model:SetAttribute("Gravity", 1)
	end
	if pos then
		local h = def.Forms[E.form].Height
		local a = Vector3.new(pos.X, h, pos.Z)
		E.move = { kind = "Hold", t0 = M.now(), t1 = M.now() + 0.05, a = a, b = a, f = face or E.facing }
		E.moveId = (model:GetAttribute("MoveId") or 0) + 1
		BeatGrid.writeMove(model, E.move, E.moveId)
		E.pos = Vector3.new(pos.X, E.floorY + h, pos.Z)
		E.facing = E.move.f
	end
	E.target, E.targetSince = me, M.now()
	return E.token
end
-- one of his moves (an attack, or THE DROP / a portal), right now
local function force(name)
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	local fn = E.boss.Attacks[name] or E.boss.Moves[name]
	M.task.spawn(function()
		fn(E, token)
	end)
end
-- the same, with his dice fixed on their first answer (which form a portal
-- gives, which tile pattern)
local function forceFixed(name)
	local real = E.rng
	E.rng = { NextInteger = function(_, lo) return lo end, NextNumber = function() return 0 end }
	force(name)
	tick(DT)
	E.rng = real
end
local function setPct(pct)
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.max(1, math.floor(max * (1 - (pct + 0.5) / 100))))
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
		if d:IsA("BasePart") and not isDynamic(d) and (d.Position - MID).Magnitude < 330 then
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
-- the player's screen: the big words, the % bar, the word bubbles
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
	local prog = gui:FindFirstChild("GridlockProgress")
	if prog and prog.Enabled then
		local holder = prog:FindFirstChild("Holder")
		local fill = holder and holder:FindFirstChild("Bar") and holder.Bar:FindFirstChild("Fill")
		local label = holder and holder:FindFirstChild("Percent")
		if fill and label then
			realPrint(string.format("PCT %s|%.3f|%s", esc(label.Text), fill.Size.X.Scale, rgb(fill.BackgroundColor3)))
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
local camEye, camLook, camFov = MID, MID, 70
local function dumpFrame(v, s)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f %.4f", frame, v, M.now(), s))
	realPrint(string.format("CAM %s %s %.2f", v3(camEye), v3(camLook), camFov))
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, E.pos.Y, E.pos.Z, P.pos.X, P.pos.Y + P.jump, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %s %s", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), tostring(E.form),
		tostring(model:GetAttribute("Gravity"))))
	realPrint(string.format("BAR GRIDLOCK|%.4f|%d", (model:GetAttribute("Health") or 1)
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
	for i, st in ipairs(statics) do
		local d = st[1]
		local pr = rawget(d, "__props")
		if pr.CFrame ~= st[2] or pr.Size ~= st[3] or pr.Color ~= st[4] or pr.Transparency ~= st[5] then
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
-- the script, in BEATS from the first frame (b = s / LEN)
----------------------------------------------------------------------
local LEN = BeatGrid.beatLen(def.Bpm)
local function B(b)
	return b * LEN
end
local A = def.Attacks
local function spot(x, z, up)
	return Vector3.new(MID.X + x, floorY + 3 + (up or 0), MID.Z + z)
end
local function ease(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local NORTH, SOUTH, EAST, WEST = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0)

local ATTEMPTS = 847 -- (the number the level says when it starts again)
local HOP = 0 -- HOP SLAM: lit at once, he hops on beat 1, lands on 2, spikes 3
local PORTAL = 6 -- through the portal on beat 7: a SHIP
local SWOOP = 8 -- the lane locks on beat 9; the dive 10 -> 11, the skim 11 -> 12
local PORTAL2 = 12 -- through a portal on beat 13: the CUBE again
local DROP = 14 -- DROP IN 3 (15), 2 (16), 1 (17), DROP! (18), crash 18.5
local DROP_HIT = DROP + def.Drop.Build
local CUT_FROM, CUT_TO = 19.2, 21.5 -- (the jump cut)
local STUN_END = DROP_HIT + 0.5 + def.Drop.Stun
local CHECK = 25 -- checkers: one colour spikes on 27, the other on 29
local CLIP = CHECK + 2 * A.TilePattern.Tell -- the spike that gets them
local END = 30
local HOP_LAND, RING = HOP + A.HopSlam.Tell, HOP + A.HopSlam.Tell + 1
-- the slow motion: round the clip
local SLOW_AT, SLOW_GAME, SLOW_RATE = B(CLIP) - 0.3, 0.6, 0.3

-- the % (how much of him is gone) after each punch: { beat, % }
local PUNCHES = {
	{ 4.2, 4 }, { 4.7, 9 }, { 5.2, 14 },
	{ 21.6, 22 }, { 21.95, 31 }, { 22.3, 40 }, { 22.65, 49 }, { 23.0, 58 }, { 23.35, 67 }, { 23.7, 76 }, { 24.05, 85 },
	{ 24.4, 91 }, { 24.75, 96 },
	{ 25.6, 97 }, { 26.4, 98 }, { 28.1, 99 },
}

-- where things are (studs from the grid's middle; a tile is 8)
local BOSS0 = Vector3.new(MID.X, floorY, MID.Z - 16)
local START = spot(0, 16) -- the player, where every attempt starts
local DODGE = spot(14, 16) -- (just off his square)
local BESIDE = spot(7.6, 16) -- (punching him where he landed)
local STEPBACK = spot(9, 26)
local PAD = nil -- (the jump pad they use: worked out below)
local STUNSPOT = spot(0.5, 7.4)
local CHECK_A = spot(0.5, 7.4) -- (tile 7,8: one colour)
local CHECK_B = spot(8, 8.5) -- (tile 8,8: the other)
do
	local g = BeatGrid.grid(Vector3.new(C.X, floorY, C.Z), arena:GetAttribute("Tiles") or 15, arena:GetAttribute("TileSize") or 8)
	for _, t in ipairs(BeatGrid.pads(g)) do
		local c = BeatGrid.tileCenter(g, t[1], t[2])
		if math.abs(c.X - C.X) < 1 and c.Z > C.Z + 1 then
			PAD = Vector3.new(c.X, floorY + 3, c.Z) -- (the one due south of the middle)
		end
	end
end
local laneFrom, laneTo = nil, nil -- (the swoop's lane, once it locks)
local swoopDodge = nil

-- the player at s: worked out from s (and the lane, once it's locked)
local function run(ph, k)
	P.legs, P.arms = math.sin(ph) * 0.95 * k, math.sin(ph + 0.6) * 0.9 * k
	P.lean, P.spread = 0.25 * k, 0.25
	P.jump = 0.12 * math.abs(math.sin(ph)) * k
end
local function jumpArc(u, height)
	u = math.clamp(u, 0, 1)
	return height * 4 * u * (1 - u)
end
local function punchAt(b)
	-- the punch nearest beat b: 0-1 (out and back in 0.3 beats); left and right turn about
	local best, side = 0, 1
	for i, pu in ipairs(PUNCHES) do
		local d = b - (pu[1] - 0.12)
		if d >= 0 and d < 0.3 then
			best = math.sin(math.pi * d / 0.3)
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
local function placePlayer(s)
	resetPose()
	local b = s / LEN
	if b < PORTAL then
		-- 1) ATTEMPT 847: on their tile as it lights - run east, off his square;
		-- he lands; the ring of spikes - jump it, back toward him; punch
		if b < 0.15 then
			P.pos, P.facing = START, NORTH
			P.guard, P.spread = 0.15, 0.2
			return
		end
		local r1 = 1.85
		if b < r1 then
			local k = ease((b - 0.15) / (r1 - 0.15))
			P.pos = START:Lerp(DODGE, k)
			P.facing = EAST:Lerp(NORTH, 0.25)
			run(s * 22, 1)
			P.headYaw = -0.9 -- (looking back at him)
			return
		end
		local j0, j1 = RING - 0.2, RING + 0.95
		if b < j0 then
			P.pos, P.facing = DODGE, WEST
			P.guard, P.spread = 0.5, 0.3
			P.legs = 0.1
			return
		end
		if b < j1 then
			-- the jump over the ring of spikes (6.4 studs up: a Roblox jump), toward him
			local u = (b - j0) / (j1 - j0)
			P.pos = DODGE:Lerp(BESIDE, ease(u))
			P.jump = jumpArc(u, 6.4)
			P.facing = WEST
			P.tuck = math.sin(math.pi * u)
			P.guard, P.spread = 0.7, 0.5
			return
		end
		local back = 5.55
		if b < back then
			P.pos, P.facing = BESIDE, WEST
			P.guard = 0.6
			P.lean = 0.12
			punchAt(b)
			return
		end
		-- (out of his way: he's off through a portal)
		local k = ease((b - back) / (PORTAL - back + 0.3))
		P.pos = BESIDE:Lerp(STEPBACK, k)
		P.facing = WEST:Lerp(NORTH, k)
		P.jump = jumpArc(k, 1.5)
		P.guard, P.spread = 0.6, 0.3
		return
	end
	if b < PORTAL2 then
		-- 2) the ship: watching it; the lane locks on them - they dive out of it
		local lock = SWOOP + A.Swoop.Tell - A.Swoop.Lock
		local dive = SWOOP + A.Swoop.Tell
		if b < PORTAL + 0.3 then
			P.pos, P.facing = STEPBACK, NORTH
			P.guard, P.spread = 0.6, 0.3
			return
		end
		if b < dive - 0.25 or not laneFrom then
			P.pos = STEPBACK
			local bp = Vector3.new(E.pos.X, P.pos.Y, E.pos.Z)
			P.facing = (bp - P.pos).Magnitude > 0.1 and (bp - P.pos).Unit or NORTH
			P.guard, P.spread = 0.4, 0.25
			P.legs = 0.12 * math.sin(s * 9)
			P.jump = 0.12 * math.abs(math.sin(s * 8))
			if b > lock then
				P.guard, P.spread = 0.9, 0.5 -- (it's locked on: brace)
			end
			return
		end
		-- the dive out of the lane (sideways to it)
		local d0 = dive - 0.25
		local lane = Vector3.new(laneTo.X - laneFrom.X, 0, laneTo.Z - laneFrom.Z).Unit
		local side = Vector3.new(-lane.Z, 0, lane.X)
		if side.Z < 0 then
			side = -side -- (toward us)
		end
		swoopDodge = swoopDodge or (STEPBACK + side * 8)
		if b < d0 + 0.75 then
			local k = (b - d0) / 0.75
			P.pos = STEPBACK:Lerp(swoopDodge, ease(k)) + Vector3.new(0, -1.5 * ease(k * 1.5) + jumpArc(k, 2.5), 0)
			P.facing = side
			P.lean = math.pi / 2 * ease(k * 1.6)
			P.guard, P.spread = 1, 0.15
			P.legs = 0.2
			return
		end
		local up0 = d0 + 1.6
		if b < up0 then
			P.pos = swoopDodge + Vector3.new(0, -1.5, 0)
			P.facing = side
			P.lean = math.pi / 2
			P.guard = 1
			P.legs = 0.2
			P.headYaw = 0.5
			return
		end
		local k = ease((b - up0) / 0.6)
		P.pos = swoopDodge + Vector3.new(0, -1.5 * (1 - k), 0)
		P.facing = side:Lerp(NORTH, k)
		P.lean = math.pi / 2 * (1 - k)
		P.guard = 1 - k
		return
	end
	if b < CUT_TO then
		-- 3) he's a cube again; THE DROP coming: run for the jump pad; it throws
		-- them up as the floor spikes
		local from = swoopDodge or STEPBACK
		local RUN0 = PORTAL2 + 1.3
		local launch = DROP_HIT - 0.9 -- (about when they reach it)
		local thrown = padLaunch and (padLaunch - T0) or nil -- (when the pad really threw them)
		if not thrown or s < thrown then
			local k = math.clamp((b - RUN0) / (launch + 0.45 - RUN0), 0, 1)
			P.pos = from:Lerp(PAD, k)
			local d = PAD - from
			P.facing = Vector3.new(d.X, 0, d.Z).Magnitude > 0.1 and Vector3.new(d.X, 0, d.Z).Unit or SOUTH
			if b > RUN0 then
				run(s * 22, 1)
			else
				local bp = Vector3.new(E.pos.X, P.pos.Y, E.pos.Z)
				P.facing = (bp - P.pos).Magnitude > 0.1 and (bp - P.pos).Unit or NORTH
				P.guard, P.spread = 0.4, 0.25
				return
			end
			P.headYaw = 0.6 * math.sin(s * 3)
			return
		end
		-- thrown up by the pad (Pads.Power studs a second, the game's gravity)
		local t = s - thrown
		local k = math.clamp((thrown / LEN - RUN0) / (launch + 0.45 - RUN0), 0, 1)
		local vy, g = def.Pads.Power, M.workspace.Gravity or 196.2
		local y = vy * t - 0.5 * g * t * t
		local air = 2 * vy / g
		P.pos = from:Lerp(PAD, k):Lerp(PAD, math.clamp(t / air, 0, 1))
		P.facing = NORTH
		if t < air then
			P.jump = y
			P.spread, P.guard = 1.2, 0.9
			P.legs = 0.35 * math.sin(s * 14)
			P.tumble = 0
			P.tuck = 0.3
		else
			-- (landed: off the pad, toward him)
			local u = t - air
			P.pos = PAD + NORTH * math.min(u * 14, 6)
			run(s * 22, math.clamp(u * 6, 0, 1))
		end
		return
	end
	if b < CHECK + 0.3 then
		-- 4) STUNNED! HIT HIM! - every punch
		P.pos, P.facing = STUNSPOT, NORTH
		P.guard, P.lean = 0.6, 0.15
		P.jump = 0.15 * math.abs(math.sin(s * 9))
		punchAt(b)
		return
	end
	-- 5) checkers: spikes all round them (beat 27) - punch, punch - then
	-- off their own tile before it spikes (beat 29)... a frame late
	P.facing = NORTH
	local hop0 = CLIP - 0.12 -- (a frame late: still low over their tile as it spikes)
	if b < hop0 then
		P.pos = CHECK_A
		P.guard, P.lean = 0.6, 0.12
		if b > CLIP - 2.1 and b < CLIP - 1.7 then
			P.guard, P.spread, P.jump = 0.9, 0.6, 0.3 -- (flinching as the spikes come up round them)
		end
		punchAt(b)
		return
	end
	local die = CLIP + 0.07
	if b < die then
		local u = (b - hop0) / 0.9
		P.pos = CHECK_A:Lerp(CHECK_B, ease(u))
		P.jump = jumpArc(u, 3.2)
		P.facing = EAST:Lerp(NORTH, 0.4)
		P.tuck = 0.5 * math.sin(math.pi * u)
		P.guard, P.spread = 0.7, 0.6
		return
	end
	-- clipped: thrown up a little... and in bits
	local u = (die - hop0) / 0.9
	P.pos = CHECK_A:Lerp(CHECK_B, ease(u))
	P.jump = jumpArc(u, 3.2)
	P.facing = EAST:Lerp(NORTH, 0.4)
	P.guard, P.spread = 1, 1
	P.dead = s - B(die)
end

-- the film's camera at s
local function bossAt()
	return Vector3.new(E.pos.X, E.pos.Y, E.pos.Z)
end
-- over the player's shoulder at him: the player low in the picture, him high
local function overShoulder(back, up, fov, side)
	local p = P.pos + Vector3.new(0, P.jump * 0.5, 0)
	local bo = bossAt()
	local d = Vector3.new(p.X - bo.X, 0, p.Z - bo.Z)
	d = d.Magnitude > 0.5 and d.Unit or SOUTH
	local s = Vector3.new(-d.Z, 0, d.X) * (side or 0)
	local eye = p + d * back + s + Vector3.new(0, up, 0)
	local look = p:Lerp(bo + Vector3.new(0, 4, 0), 0.55)
	return eye, look, fov
end
local function shot(s)
	local b = s / LEN
	if b < PORTAL then
		-- 1) behind them (south, a little east), low: he flips over at us
		local k = ease(b / PORTAL)
		return spot(12 + 2 * k, 50 - 3 * k, 7), spot(3, 4 + 2 * k, 2.5), 72
	end
	if b < DROP then
		-- 2) the portal and the ship: wide, low, from the south-west; then down
		-- the swoop lane behind the player (it dives at us)
		if b < SWOOP + 1 then
			local k = ease((b - PORTAL) / 3)
			return spot(8 + 2 * k, 56 - 2 * k, 9), spot(12, 8, 6), 70
		end
		if b < PORTAL2 then
			local e, l, f = overShoulder(20, 7, 72, 4)
			return e, l, f
		end
		-- (wide, from the south-east: the green portal, him a cube again)
		local k = ease((b - PORTAL2) / (DROP - PORTAL2))
		return spot(26 - 6 * k, 68 - 4 * k, 16 - 3 * k), spot(2, 14, 5), 66
	end
	if b < DROP + 3 then
		-- 3) the run to the pad, him rising behind
		local p = P.pos
		local k = ease((b - DROP) / 3)
		return p + Vector3.new(8, 8 + 2 * k, 26 - 2 * k), Vector3.new(MID.X, floorY + 10 + 4 * k, MID.Z + 6), 72
	end
	if b < CUT_TO then
		-- THE DROP: low by the pad, looking up past them at him - the whole
		-- floor spiking under them as they fly
		local k = ease((b - DROP - 3) / (CUT_FROM - DROP - 3))
		local j = P.jump
		local pad = PAD or spot(0, 40)
		return pad + Vector3.new(11 - 3 * k, 1 + 0.4 * j, 27 - 3 * k), Vector3.new(pad.X - 3, floorY + 6 + 0.95 * j, pad.Z - 24), 74
	end
	if b < CHECK then
		-- 4) close on the punches
		local k = ease((b - CUT_TO) / (CHECK - CUT_TO))
		return spot(12 - 2 * k, 26 - 3 * k, 3.5), spot(0, 2, 3.5), 62
	end
	-- 5) the checkers, from up a little: the tiles round them, him above;
	-- in the slow motion, down to their feet and the spike
	local k = ease((b - CHECK) / (CLIP - 1 - CHECK))
	local push = ease((s - SLOW_AT) / (SLOW_GAME * 0.8))
	local eye = spot(15 - 3 * k, 34 - 6 * k, 17 - 4 * k):Lerp(spot(15, 14, -0.3), push)
	local look = spot(1, 3, 0):Lerp(spot(0.8, 7.4, -0.2), push)
	return eye, look, 62
end

----------------------------------------------------------------------
-- before the camera rolls: his real wake (ATTEMPT 1), then the level
-- started again and again (the attempts before this one)
----------------------------------------------------------------------
P.pos = START
pose()
advanceTo(T + 0.5)
dumpStatic()
P.pos = spot(0, 20)
pose()
me:SetAttribute("SpireFloor", 6)
while model:GetAttribute("Action") ~= "Wake" do
	advanceTo(T + DT)
end
advanceTo(model:GetAttribute("ActionStart") + def.WakeTime + 0.3)
while model:GetAttribute("State") ~= "Fighting" do
	advanceTo(T + DT)
end
takeOver(BOSS0, "Cube", SOUTH)
for _ = 2, ATTEMPTS - 1 do
	setAction("Wake", nil)
	advanceTo(T + DT * 2)
end
setAction("Idle", nil)
takeOver(BOSS0, "Cube", SOUTH)
advanceTo(T + 6) -- (everything from those starts fades away)

T0 = T + 2 -- (s = 0: beat 0 of the level, started again)
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
stepTo(-1.2)
takeOver(BOSS0, "Cube", SOUTH)
setPct(0)
stepTo(-0.3)
-- ATTEMPT 847: the level's beat starts again (beat 0 = the first frame),
-- its words, the grid lighting up from the middle
E.beat0 = T0
model:SetAttribute("BeatStart", T0)
setAction("Wake", nil)
event("attempt", 0, string.format("%d", ATTEMPTS))
stepTo(-0.2)
takeOver(BOSS0, "Cube", SOUTH)
force("HopSlam")
stepTo(-DT)

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
-- the frames: s for each (the jump cut, the slow motion)
local schedule = {}
do
	local s = 0
	while s < B(END) - 1e-6 do
		if s >= B(CUT_FROM) - 1e-6 and s < B(CUT_TO) then
			s = B(CUT_TO)
		end
		table.insert(schedule, s)
		if s >= SLOW_AT - 1e-6 and s < SLOW_AT + SLOW_GAME - 1e-6 then
			s += DT * SLOW_RATE
		else
			s += DT
		end
	end
end
local FRAMES = #schedule
event("loop", 0, string.format("%d %.4f %.4f %.4f %.4f %.4f %.4f %.4f", FRAMES, B(END), SLOW_AT, SLOW_GAME, SLOW_RATE, B(CUT_FROM), B(CUT_TO), LEN))
event("times", 0, string.format("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", B(HOP), B(HOP_LAND), B(RING), B(PORTAL), B(SWOOP), B(DROP),
	B(DROP_HIT), B(CHECK), B(CLIP)))
event("stage", 0, v3(MID))
for _, pu in ipairs(PUNCHES) do
	event("punch", B(pu[1]), string.format("%d", pu[2]))
end
local done = {}
local function once(name, when, ss, fn)
	if not done[name] and ss >= when - 1e-6 then
		done[name] = true
		fn()
	end
end
local cutDone = false
for k = 1, FRAMES do
	local ss = schedule[k]
	local v = (k - 1) * DT
	if ss >= B(CUT_TO) - 1e-6 and not cutDone then
		cutDone = true
		event("cut", v, string.format("%.4f", ss))
	end
	-- his moves, a moment before their beats (each counts from the next beat)
	once("portal", B(PORTAL) - 0.2, ss, function()
		advanceTo(T0 + B(PORTAL) - 0.2)
		forceFixed("Portal") -- (the first form offered: the SHIP)
		event("portal", v, "")
	end)
	once("portal2", B(PORTAL2) - 0.2, ss, function()
		advanceTo(T0 + B(PORTAL2) - 0.2)
		forceFixed("Portal") -- (the first form offered: the CUBE again)
		event("portal2", v, "")
	end)
	once("swoop", B(SWOOP) - 0.2, ss, function()
		advanceTo(T0 + B(SWOOP) - 0.2)
		force("Swoop")
		event("swoop", v, "")
	end)
	once("lock", B(SWOOP + A.Swoop.Tell - A.Swoop.Lock) + 0.05, ss, function()
		advanceTo(T0 + B(SWOOP + A.Swoop.Tell - A.Swoop.Lock) + 0.05)
		laneFrom, laneTo = model:GetAttribute("ActA"), model:GetAttribute("ActC") or model:GetAttribute("ActB")
		event("lock", v, (laneFrom and laneTo) and (v3(laneFrom) .. " " .. v3(laneTo)) or "")
	end)
	once("drop", B(DROP) - 0.2, ss, function()
		advanceTo(T0 + B(DROP) - 0.2)
		force("Drop")
		dropOn = true
		event("drop", v, "")
	end)
	once("check", B(CHECK) - 0.2, ss, function()
		advanceTo(T0 + B(CHECK) - 0.2)
		forceFixed("TilePattern") -- (the first pattern: checkers)
		event("check", v, "")
	end)
	for i, pu in ipairs(PUNCHES) do
		once("punch" .. i, B(pu[1]), ss, function()
			advanceTo(T0 + B(pu[1]))
			setPct(pu[2])
			event("hit", v, string.format("%d %s", pu[2], v3(P.pos + P.facing * 2.2 + Vector3.new(0, 0.6, 0))))
		end)
	end
	once("clip", B(CLIP + 0.07), ss, function()
		event("clip", v, v3(P.pos))
	end)
	stepTo(ss)
	if #launches > 0 then
		for _, l in ipairs(launches) do
			event("launch", v, string.format("%.4f %.2f", l[1] - T0, l[2]))
		end
		launches = {}
	end
	if math.abs(ss - SLOW_AT) < 1e-6 then
		event("slow", v, string.format("%.4f", ss))
	end
	dumpFrame(v, ss)
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
