--!nocheck
-- A 14-second LOOP of floor 9 for a YouTube Short, starring SCRIBBLE's
-- ERASER: the real Canvas (CanvasBuilder), the real BossService with his
-- brain stopped and his moves forced like a scripted scene, the real
-- BossClient drawing him (BossBodies/Scribble: the dotted dash line, the
-- paint squares, the ink clones, the pink strip and the giant eraser), and a
-- blocky player he rubs out. Every video frame (30 a second) prints what's
-- on screen, the camera included; render_scribble_cutscene.py films it.
--
--   luau scribble_cutscene.luau > scribble.txt
--   python3 render_scribble_cutscene.py scribble.txt ../../Docs/animations/scribble_short.mp4
--
-- The scene, beat by beat (game seconds `s` from the first frame):
--   0.0  PENCIL DASH: the dotted line through the player, he rockets down it
--        straight at us - the player dives out of the way.
--   1.6  PAINT BUCKET: the player's square drips... they run, too late:
--        SPLAT, flung face first, stars.
--   4.6  COPY-PASTE: "CTRL+C... CTRL+V!" - two ink clones run them down the
--        paper toward us.
--   7.4  phew... (bent over, panting, back to him) - the ERASER SWEEP strip
--        lights up under them. They look down: ?! - and the giant eraser
--        comes through: legs gone, arms gone, body gone, and on the last pass
--        (slow motion) the head: DELETED.
--  11.7  close on him, laughing.
--  12.6  the player sketched back in where they started... and the same
--        Pencil Dash begins again: the last frame runs into the first.
--
-- Film and game clocks are the same but for one slow-motion stretch (the
-- last pass of the eraser).
--
-- What it prints: STATIC (every arena part once, indexed), then per frame
-- FRAME (frame, film time, game time, s), CAM (eye, look, fov: the film's
-- camera, also Workspace.CurrentCamera so he faces it - he's a drawing),
-- POS, STATE, BAR, AIM, the moving parts, changed arena parts; and BURST,
-- KICK and EVENT lines as they happen (see gavelgrunt_cutscene.luau).
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(1)

local arena = mount.require(mount.module("ServerScriptService/CanvasBuilder.lua")).Build()
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
-- (a face on the head, so you can tell which way they look: two eyes)
local eyes = { limb("Eye", Vector3.new(0.22, 0.3, 0.1), M.Color3.fromRGB(24, 20, 37)),
	limb("Eye", Vector3.new(0.22, 0.3, 0.1), M.Color3.fromRGB(24, 20, 37)) }
local stars = {}
for i = 1, 3 do
	local s = limb("Star", Vector3.new(0.8, 0.8, 0.8), M.Color3.fromRGB(255, 214, 40))
	s.Material = M.Enum.Material.Neon
	stars[i] = s
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
kick.Event:Connect(function(strength)
	realPrint(string.format("KICK %.4f %.3f", M.now(), tonumber(strength) or 0))
end)
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1080, Y = 1920 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- the pose (as gavelgrunt_cutscene.luau): pos = the middle of the body,
-- facing, legs / arms swing, guard raises the arms, spread throws them out,
-- lean tips forward round the hips, tumble flips round the middle, jump
-- lifts; and here `gone` (limbs rubbed out: legs, arms, torso, head) and
-- `fade` (0 = drawn, 1 = not there: being sketched back in)
local P = { pos = Vector3.zero, facing = Vector3.new(0, 0, 1), legs = 0, arms = 0, guard = 0, spread = 0, lean = 0,
	tumble = 0, jump = 0, headYaw = 0, roll = 0, gone = {}, fade = 0, stars = nil }
local function pose()
	local look = Vector3.new(P.facing.X, 0, P.facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, 1)
	local at = P.pos + Vector3.new(0, P.jump, 0)
	local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(-P.tumble, 0, P.roll) * CFrame.new(0, -1, 0)
		* CFrame.Angles(-P.lean, 0, 0) * CFrame.new(0, 1, 0)
	root.CFrame = CFrame.new(at) * (cf - cf.Position)
	body.torso.CFrame = cf
	local headCf = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, P.headYaw, 0)
	body.head.CFrame = headCf
	eyes[1].CFrame = headCf * CFrame.new(-0.25, 0.1, -0.62)
	eyes[2].CFrame = headCf * CFrame.new(0.25, 0.1, -0.62)
	local function swing(part, x, y, angle, drop, out)
		part.CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(angle, 0, out or 0) * CFrame.new(0, -drop, 0)
	end
	swing(body.lleg, -0.5, -1, P.legs, 1)
	swing(body.rleg, 0.5, -1, -P.legs, 1)
	local up = P.guard * 2.2
	swing(body.larm, -1.5, 0.5, -P.arms + up, 0.5, -P.spread)
	swing(body.rarm, 1.5, 0.5, P.arms + up, 0.5, P.spread)
	local g = P.gone
	local hidden = { torso = g.torso, head = g.head, larm = g.arms, rarm = g.arms, lleg = g.legs, rleg = g.legs }
	for k, p in pairs(body) do
		p.Transparency = hidden[k] and 1 or P.fade
	end
	for _, e in ipairs(eyes) do
		e.Transparency = g.head and 1 or P.fade
	end
	for i, s in ipairs(stars) do
		if P.stars and not g.head and P.fade < 0.5 then
			local a = P.stars * 7 + i * math.pi * 2 / 3
			s.CFrame = headCf * CFrame.new(math.cos(a) * 1.5, 1.2 + 0.25 * math.sin(a * 2), math.sin(a) * 1.5)
				* CFrame.Angles(a, a * 0.7, 0)
			s.Transparency = 0
		else
			s.Transparency = 1
		end
	end
end

----------------------------------------------------------------------
-- the boss: the real server brain and the real screen
----------------------------------------------------------------------
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
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 9 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(9)
local model, def, home = E.model, E.def, E.home
local floorY = E.floorY or home.Y
local C = arena:GetAttribute("Center") or home
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

local function killClones()
	for _, c in ipairs(E.clones or {}) do
		c.dieAt = 0
	end
end
local function takeOver(pos, face)
	E.token += 1
	E.motion, E.sweep = nil, nil
	E.chase, E.track = false, false
	E.zones = {}
	if pos then
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = face
	end
	E.target, E.targetSince = me, M.now()
	return E.token
end
local function force(name)
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.chase = false
	E.motion, E.sweep = nil, nil
	M.task.spawn(function()
		E.boss.Attacks[name](E, token)
	end)
end

----------------------------------------------------------------------
-- what's printed
----------------------------------------------------------------------
local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
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
local props = workspace:FindFirstChild("ScribbleProps")
local statics = {}
local function isDynamic(d)
	fx = fx or workspace:FindFirstChild("BossFX")
	props = props or workspace:FindFirstChild("ScribbleProps")
	return (fx and d:IsDescendantOf(fx)) or (props and d:IsDescendantOf(props)) or d:IsDescendantOf(char)
		or d:IsDescendantOf(model)
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
local frame = 0
local camEye, camLook, camFov = MID, MID, 70
local function dumpFrame(v, s)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f %.4f", frame, v, M.now(), s))
	realPrint(string.format("CAM %s %s %.2f", v3(camEye), v3(camLook), camFov))
	local b = model:GetPivot().Position
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, b.Y, E.pos.Z, P.pos.X, P.pos.Y + P.jump, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %d", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), model:GetAttribute("Phase") or 1))
	realPrint(string.format("BAR SCRIBBLE|%.4f|%d", (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), model:GetAttribute("Phase") or 1))
	local aim, head = model:GetAttribute("AimAt"), model:GetAttribute("HeadAt")
	if M.typeof(aim) == "Vector3" and M.typeof(head) == "Vector3" then
		realPrint("AIM " .. v3(aim) .. " " .. v3(head))
	end
	fx = fx or workspace:FindFirstChild("BossFX")
	props = props or workspace:FindFirstChild("ScribbleProps")
	local roots = { char } -- (not { fx, props, char }: ipairs stops at the first nil)
	if fx then
		table.insert(roots, fx)
	end
	if props then
		table.insert(roots, props)
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
	realPrint("ENDFRAME")
end
local function event(name, v, extra)
	realPrint(string.format("EVENT %s %.4f %s", name, v, extra or ""))
end

----------------------------------------------------------------------
-- the script (game seconds s from the first frame)
----------------------------------------------------------------------
local SOUTH = Vector3.new(0, 0, 1)
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

local A = def.Attacks
local DASH_LEAD = 0.45 -- the film starts this long into a Pencil Dash (the line drawn, blinking)
local DASH1 = -DASH_LEAD
local PAINT = 1.6
local FLOOD = PAINT + A.PaintBucket.Tell
local COPY = 4.6
local CLONES = COPY + A.CopyPaste.Tell
local CALM = 7.4
local ERASE = 7.6
local RUB = ERASE + A.EraserSweep.Tell
-- the eraser runs along its strip as sin(u * pi) with u = (now - RUB) / 0.5:
-- through the middle (where the player is) every half second
local PASS = { RUB, RUB + 0.5, RUB + 1.0, RUB + 2.0 } -- legs, arms, body, head
local LAUGH = RUB + A.EraserSweep.Time + 0.1 -- (close on him)
local GAME_LEN = 13.3
local DASH2 = GAME_LEN - DASH_LEAD -- (the loop: the same dash, the same moment)
local REDRAW0, REDRAW1 = DASH2 - 0.55, DASH2 - 0.1
-- the slow motion: the last pass, the head
local SLOW_AT, SLOW_GAME, SLOW_RATE = PASS[4] - 0.15, 0.3, 0.3
local SLOW_FRAMES = math.floor(SLOW_GAME / (DT * SLOW_RATE) + 0.5)
local K_SLOW = math.floor(SLOW_AT / DT + 0.5)
local FRAMES = math.floor((GAME_LEN - SLOW_GAME) / DT + 0.5) + SLOW_FRAMES

local START = spot(0, 26) -- (the player at the start, and where they're drawn back in)
local DIVE_TO = spot(7, 26)
local SQUARE = spot(10, 30) -- (the middle of a paint square)
local LANDED = spot(-9, 30)
local FLEE0, FLEE1 = spot(0, 20), spot(2, 44)
local ERASED = spot(0, 30)

-- the player at s: worked out from s, never stepped along
local function placePlayer(s)
	P.legs, P.arms, P.guard, P.spread, P.lean, P.tumble, P.jump, P.headYaw, P.roll = 0, 0, 0, 0, 0, 0, 0, 0, 0
	P.gone, P.fade, P.stars = {}, 0, nil
	P.facing = -SOUTH -- (toward him)
	if s < PAINT then
		-- 1) the dash: they dive out of its way (east), roll and get up
		local d0, d1 = 0.05, 0.42
		if s < d0 or s >= DASH2 - 1e-6 then
			P.pos = START
			P.guard, P.spread = 0.15, 0.2
			P.legs = 0.08 * math.sin(s * 9)
			return
		end
		if s < d1 then
			local k = (s - d0) / (d1 - d0)
			P.pos = START:Lerp(DIVE_TO, k) + Vector3.new(0, -1.5 * k + 3 * math.sin(math.pi * k), 0)
			P.facing = Vector3.new(1, 0, 0)
			P.lean = math.pi / 2 * ease(k * 1.4)
			P.guard, P.spread = 1, 0.15
			P.legs = 0.2
			return
		end
		if s < 0.75 then
			P.pos = DIVE_TO + Vector3.new(0, -1.5, 0)
			P.facing = Vector3.new(1, 0, 0)
			P.lean = math.pi / 2
			P.guard = 1
			P.legs = 0.2
			return
		end
		local k = ease((s - 0.75) / 0.3)
		P.pos = DIVE_TO + Vector3.new(0, -1.5 * (1 - k), 0)
		P.facing = Vector3.new(1, 0, 0):Lerp(Vector3.new(-0.4, 0, 1), k)
		P.lean = math.pi / 2 * (1 - k)
		P.guard = 1 - k
		P.headYaw = 0.6 * k -- (looking back at where he went)
		return
	end
	if s < COPY then
		-- 2) the paint square: standing in it, it drips - they run (west), the
		-- flood flings them face first, stars, up
		local run0 = FLOOD - 0.7
		if s < run0 then
			P.pos = SQUARE
			P.guard, P.spread = 0.2, 0.3
			P.headYaw = 0.3 * math.sin((s - PAINT) * 5) -- (looking about)
			return
		end
		local west = Vector3.new(-1, 0, 0)
		local at = SQUARE + west * (s - run0) * 13
		if s < FLOOD then
			P.pos = at
			P.facing = west
			local ph = s * 22
			P.legs, P.arms = math.sin(ph) * 0.95, math.sin(ph + 0.6) * 0.9
			P.lean, P.spread, P.jump = 0.3, 0.3, 0.12 * math.abs(math.sin(ph))
			return
		end
		local fly = 0.5
		local from = SQUARE + west * 0.7 * 13
		if s < FLOOD + fly then
			local k = (s - FLOOD) / fly
			local base = from:Lerp(LANDED + Vector3.new(0, -2.5, 0), k)
			P.pos = base + Vector3.new(0, 5 * math.sin(math.pi * k), 0)
			P.facing = west
			P.tumble = k * (math.pi * 2 + math.pi / 2)
			P.guard, P.spread = 0.9, 1.1
			P.legs = 0.4 * math.sin(s * 24)
			return
		end
		local up0 = COPY - 0.75
		if s < up0 then
			P.pos = LANDED + west * 1 + Vector3.new(0, -1.5, 0)
			P.facing = west
			P.lean = math.pi / 2
			P.guard, P.spread, P.legs = 1, 0.2, 0.15
			P.stars = s
			return
		end
		local k = ease((s - up0) / 0.4)
		P.pos = LANDED + west * (1 - k) + Vector3.new(0, -1.5 * (1 - k), 0)
		P.facing = west:Lerp(-SOUTH, k)
		P.lean = math.pi / 2 * (1 - k)
		P.guard = 1 - k
		P.stars = s
		return
	end
	if s < CALM then
		-- 3) the clones: facing him... they peel off, and run at them: they
		-- turn and run for it, down the paper toward us
		local turn = CLONES + 0.15
		if s < turn then
			P.pos = FLEE0
			P.guard, P.spread = 0.6, 0.2 -- (fists up)
			P.legs = 0.15
			P.jump = 0.15 * math.abs(math.sin(s * 8)) -- (bouncing on their toes)
			return
		end
		local k = (s - turn) / (CALM - turn)
		P.pos = FLEE0:Lerp(FLEE1, k)
		P.facing = SOUTH
		local ph = s * 24
		P.legs, P.arms = math.sin(ph) * 1.0, math.sin(ph + 0.6) * 1.0
		P.lean, P.spread, P.jump = 0.32, 0.5, 0.15 * math.abs(math.sin(ph))
		P.headYaw = (math.floor(s * 2.5) % 2 == 0) and 0.7 or 0 -- (glances back)
		return
	end
	if s < LAUGH then
		-- 4) phew - bent over, panting, back to him (facing us)... the strip
		-- lights up under them: ?! - they try to run: the eraser takes them a
		-- bit at a time
		P.facing = SOUTH
		local look, flee = RUB - 0.45, RUB - 0.2
		if s < look then
			P.pos = ERASED
			P.lean = 0.55 + 0.06 * math.sin(s * 14) -- (panting)
			P.arms, P.guard = -0.5, 0
			P.spread = 0.15
			return
		end
		if s < flee then
			-- (a look down at the pink under their feet)
			local k = ease((s - look) / 0.12)
			P.pos = ERASED
			P.lean = 0.55 * (1 - k) + 0.25 * k
			P.guard, P.spread = 0.5 * k, 0.6 * k
			P.jump = 0.6 * math.sin(math.pi * math.clamp((s - look) / 0.18, 0, 1))
			return
		end
		local ph = s * 24
		if s < PASS[1] then
			P.pos = ERASED + SOUTH * (s - flee) * 6
			local k = (s - flee) / (PASS[1] - flee)
			P.legs, P.arms = math.sin(ph) * k, math.sin(ph + 0.6)
			P.lean, P.spread = 0.3, 0.4
			return
		end
		local stop = ERASED + SOUTH * (PASS[1] - flee) * 6
		P.gone.legs = true
		if s < PASS[2] then
			-- (no legs: the body drops onto the paper, arms flailing)
			local k = math.clamp((s - PASS[1]) / 0.15, 0, 1)
			P.pos = stop + Vector3.new(0, -2 * k ^ 2, 0)
			P.arms = math.sin(ph * 1.3) * 1.2
			P.guard, P.spread = 0.6, 0.8 + 0.3 * math.sin(ph)
			P.headYaw = 0.5 * math.sin(s * 11)
			return
		end
		P.gone.arms = true
		if s < PASS[3] then
			P.pos = stop + Vector3.new(0, -2, 0)
			P.roll = 0.15 * math.sin(s * 18) -- (wobbling)
			P.headYaw = 0.6 * math.sin(s * 13)
			return
		end
		P.gone.torso = true
		if s < PASS[4] then
			-- (just a head: it drops, bounces, and turns to see the eraser coming)
			local t = s - PASS[3]
			local drop = math.max(0, 1 - t / 0.2)
			local bounce = (t > 0.2) and 0.8 * math.abs(math.sin((t - 0.2) * 9)) * math.exp(-(t - 0.2) * 4) or 0
			P.pos = stop + Vector3.new(0, -4.0 + 2 * drop ^ 2 + bounce, 0)
			P.headYaw = (t > 0.55) and 1.3 * ease((t - 0.55) / 0.15) or 0
			return
		end
		P.gone.head = true
		P.pos = stop + Vector3.new(0, -4, 0)
		return
	end
	-- 5) gone (he laughs)... and sketched back in where they started
	P.pos = START
	P.guard, P.spread = 0.15, 0.2
	if s < REDRAW0 then
		P.fade = 1
	elseif s < REDRAW1 then
		P.fade = 1 - ease((s - REDRAW0) / (REDRAW1 - REDRAW0))
	end
	P.legs = 0.08 * math.sin(s * 9)
end

-- the film's camera at s (the renderer draws from it; he faces it)
local function shot(s)
	local bossAt = Vector3.new(E.pos.X, floorY, E.pos.Z)
	if s < PAINT or s >= DASH2 - 0.25 then
		-- 1) down the dash line, low: he rockets straight at us
		local t = s >= DASH2 - 0.25 and (s - GAME_LEN) or s
		local push = 2.5 * math.clamp(t / 1.6, -1, 1)
		return spot(7, 41 - push, 3.5), spot(1, 14, 4.5), 72
	end
	if s < COPY then
		-- 2) the paint square, from up high and off to the side
		local k = ease((s - PAINT) / (COPY - PAINT))
		return spot(-3 + 2 * k, 64 - 4 * k, 11 - 2 * k), spot(1, 22, 3), 64
	end
	if s < CALM then
		-- 3) the clones: behind him... then backing away in front of the player
		local p = P.pos
		local z = math.max(46, p.Z - MID.Z + 22)
		return spot(10, z, 6), Vector3.new(MID.X + 0.5 * (p.X - MID.X), floorY + 4, lerp(MID.Z + 6, p.Z - 4, ease((s - CLONES) / 1.5))), 70
	end
	if s < LAUGH then
		-- 4) the eraser: close in front of them, low, the strip across the
		-- picture, pushing in slowly as they're rubbed out
		local k = ease((s - CALM) / (PASS[4] - CALM))
		local back = lerp(20, 13, k)
		return spot(5 - 2 * k, 31 + back, 3 - 0.8 * k), spot(0, 26 - 2 * k, -1.2 - 0.6 * k), 70
	end
	-- 5) close on him, laughing
	local head = model:GetAttribute("HeadAt")
	local hp = (M.typeof(head) == "Vector3") and head or (bossAt + Vector3.new(0, 10, 0))
	local k = ease((s - LAUGH) / (DASH2 - 0.25 - LAUGH))
	return hp + Vector3.new(3.5 - 1.5 * k, -2, 25 - 5 * k), hp + Vector3.new(0, -3.5, 0), 55
end

----------------------------------------------------------------------
-- before the camera rolls: his entrance, then at his spot
----------------------------------------------------------------------
P.pos = START
pose()
advanceTo(T + 0.5)
dumpStatic()
me:SetAttribute("SpireFloor", 9)
while model:GetAttribute("Action") ~= "Wake" do
	advanceTo(T + DT)
end
advanceTo(model:GetAttribute("ActionStart") + def.WakeTime + 0.3)
while model:GetAttribute("State") ~= "Fighting" do
	advanceTo(T + DT)
end
takeOver(MID, SOUTH)
advanceTo(T + 5) -- (his body settles on his spot; anything he drew before fades away)
local T0 = T + DASH_LEAD + 0.05 -- (s = 0)
-- (lining up: the camera, the player where they start)
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
stepTo(DASH1 - 0.05)
takeOver(MID, SOUTH)
force("PencilDash")
event("dash1", 0, string.format("%.4f", model:GetAttribute("ActionStart") or 0))
local s = DASH1
while s < -1e-6 do
	s = math.min(0, s + DT)
	stepTo(s)
end

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
event("loop", 0, string.format("%d %.4f %.4f %.4f %.4f", FRAMES, GAME_LEN, SLOW_AT, SLOW_GAME, SLOW_RATE))
event("times", 0, string.format("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", PAINT, FLOOD, COPY,
	CLONES, CALM, ERASE, RUB, PASS[1], PASS[2], PASS[3], PASS[4], LAUGH, DASH2, REDRAW0))
event("stage", 0, v3(MID))
local done = {}
local function once(name, when, ss, fn)
	if not done[name] and ss >= when - 1e-6 then
		done[name] = true
		fn()
	end
end
for k = 0, FRAMES - 1 do
	local v = k * DT
	local ss
	local slowing = k >= K_SLOW and k < K_SLOW + SLOW_FRAMES
	if k < K_SLOW then
		ss = k * DT
	elseif slowing then
		ss = K_SLOW * DT + (k - K_SLOW) * DT * SLOW_RATE
	else
		ss = K_SLOW * DT + SLOW_GAME + (k - K_SLOW - SLOW_FRAMES) * DT
	end
	-- the moves, on their beats (each at a cut: he's put on his spot there)
	once("paint", PAINT, ss, function()
		advanceTo(T0 + PAINT)
		takeOver(MID, SOUTH)
		placePlayer(PAINT)
		pose()
		force("PaintBucket")
		event("paint", v, "")
	end)
	once("copy", COPY, ss, function()
		advanceTo(T0 + COPY)
		takeOver(MID, SOUTH)
		placePlayer(COPY)
		pose()
		force("CopyPaste")
		event("copy", v, "")
	end)
	once("calm", CALM, ss, function()
		advanceTo(T0 + CALM)
		killClones()
		takeOver(MID, SOUTH)
		event("calm", v, "")
	end)
	once("erase", ERASE, ss, function()
		advanceTo(T0 + ERASE)
		placePlayer(ERASE)
		pose()
		force("EraserSweep")
		event("erase", v, "")
	end)
	once("dash2", DASH2, ss, function()
		advanceTo(T0 + DASH2)
		takeOver(MID, SOUTH)
		placePlayer(DASH2)
		pose()
		force("PencilDash")
		event("dash2", v, "")
	end)
	for i, at in ipairs(PASS) do
		once("pass" .. i, at, ss, function()
			event("pass", v, string.format("%d %s", i, v3(P.pos)))
			-- (eraser crumbs and bits of them, where the eraser just went through)
			local cols = { { 62, 137, 72 }, { 254, 231, 97 }, { 0, 153, 219 }, { 254, 231, 97 } }
			local c = cols[i]
			local y = ({ -1.5, 0.5, -0.5, -2.4 })[i]
			burstLine(P.pos + Vector3.new(0, y, 0), c[1], c[2], c[3], 14, 0.5, 0.9, 6, 14, 0.4, 0.8, 80, -30, 2)
			burstLine(P.pos + Vector3.new(0, y, 0), 246, 117, 122, 22, 0.4, 0.8, 8, 18, 0.4, 0.9, 90, -30, 2)
			burstLine(P.pos + Vector3.new(0, y, 0), 235, 235, 240, 16, 0.3, 0.6, 5, 12, 0.5, 1.0, 100, -25, 2)
		end)
	end
	stepTo(ss)
	once("flood", FLOOD, ss, function()
		event("flood", v, v3(P.pos))
	end)
	once("laugh", LAUGH, ss, function()
		event("laugh", v, "")
	end)
	if k == K_SLOW then
		event("slow", v, string.format("%.4f", ss))
	end
	if k == K_SLOW + SLOW_FRAMES then
		event("fast", v, string.format("%.4f", ss))
	end
	dumpFrame(v, ss)
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
