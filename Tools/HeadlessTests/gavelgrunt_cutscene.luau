--!nocheck
-- A 5.6-second LOOP of floor 10 for a YouTube Short, starring KING
-- GAVELGRUNT's BIG GULP: the real Throne Summit (ThroneBuilder), the real
-- BossService with his brain stopped and the Big Gulp forced twice in a row,
-- the real BossClient drawing him (BossBodies/Gavelgrunt: the suction wedge,
-- the wind rushing to his mouth, his cheeks full, the green burp), and a
-- blocky player he eats. Every video frame (30 a second) prints what's on
-- screen; render_gavelgrunt_cutscene.py films it.
--
--   luau gavelgrunt_cutscene.luau > gulp.txt
--   python3 render_gavelgrunt_cutscene.py gulp.txt ../../Docs/youtube/gavelgrunt_gulp.mp4
--
-- The scene, beat by beat (a cycle: "c" seconds after the first Big Gulp
-- began): he's breathing in, mouth wide - the player runs for their life
-- straight at us, but the wind drags them back, feet scrabbling, and lifts
-- them tumbling into his mouth: GULP. Cheeks full, he chews... PTOO! - they
-- fly out at us - and his BURP blows them the rest of the way (slow motion),
-- face first along the floor. They get up, dizzy, stars round their head -
-- and behind them he's opening his mouth again. They look back, and run...
--
-- THE LOOP: the film starts one second into the first Big Gulp (the player
-- running, dragged) and ends one frame before the same moment of the second
-- one, G seconds later - and everything on screen is a sum of the seconds
-- since the move began: the player (every pose here is worked out from c,
-- not stepped along), his body (by then the same pose, the smoothing long
-- settled) and the camera. So the last frame runs straight into the first.
--
-- The film's clock and the game's clock aren't always the same: the burp
-- flinging them at us plays in slow motion (the game clock creeps a quarter
-- of a frame at a time), so the server and the screen see every moment.
--
-- What it prints (as burrowmore_cutscene.luau): STATIC (every arena part,
-- once, each with an index), then for every frame FRAME (film time, game
-- time, cycle time), POS (his middle on the floor, the player's), STATE, BAR
-- (his health bar), AIM / HEAD (the middle of his drawn body and the top of
-- it), MOUTH (where his mouth is drawn), and the parts that moved: his body
-- and effects, the player, and any arena part that changed (by index). And,
-- as they happen: BURST (a puff of particles: the renderer draws them, the
-- pretend Roblox can't), KICK (a camera knock the game asked for) and EVENT
-- (the film's own moments, with the spots the cameras need).
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(1) -- (anything using math.random: the same film every run)

local arena = mount.require(mount.module("ServerScriptService/ThroneBuilder.lua")).Build()
M.run(1)
local C = arena:GetAttribute("Center")

----------------------------------------------------------------------
-- the particles BossClient emits (burst(): a see-through holder part and a
-- ParticleEmitter told to Emit), written down so the renderer can draw them
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
-- (dizzy: little gold stars circling their head)
local stars = {}
for i = 1, 3 do
	local s = limb("Star", Vector3.new(0.8, 0.8, 0.8), M.Color3.fromRGB(255, 214, 40))
	s.Material = M.Enum.Material.Neon
	stars[i] = s
end
-- (their shadow on the floor while they're in the air: so you can see how high)
local shadow = limb("Shadow", Vector3.new(0.1, 2.4, 2.4), M.Color3.fromRGB(20, 18, 34))
shadow.Shape = M.Enum.PartType.Cylinder
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
-- (the camera knocks the game asks for, written down: the renderer shakes its own camera)
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

-- where the player is and how they're posed: `pos` is the middle of the body
-- (3 studs over the floor), `facing` the way they look, and the limbs swing
-- by `legs` / `arms` (radians, + is forward); `guard` raises both arms (0-1)
-- and `spread` throws them out to the sides (radians: flailing); `lean` tips
-- the body forward (radians, round the hips); `tumble` turns the whole body
-- head over heels round its middle (radians, + is a forward flip); `jump` is
-- how high the feet are off the floor; `headYaw` turns the head (looking back
-- over a shoulder); `hide` hides them (swallowed); `stars` circles the stars.
local P = { pos = Vector3.zero, facing = Vector3.new(0, 0, 1), legs = 0, arms = 0, guard = 0, spread = 0, lean = 0,
	tumble = 0, jump = 0, headYaw = 0, hide = false, stars = nil, shadowY = nil }
local function pose()
	local look = Vector3.new(P.facing.X, 0, P.facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, 1)
	local at = P.pos + Vector3.new(0, P.jump, 0)
	-- (leaning pivots at the hips, a stud under the middle; a tumble turns round the middle)
	local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(-P.tumble, 0, 0) * CFrame.new(0, -1, 0)
		* CFrame.Angles(-P.lean, 0, 0) * CFrame.new(0, 1, 0)
	root.CFrame = CFrame.new(at) * (cf - cf.Position)
	body.torso.CFrame = cf
	body.head.CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, P.headYaw, 0)
	local function swing(part, x, y, angle, drop, out)
		part.CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(angle, 0, out or 0) * CFrame.new(0, -drop, 0)
	end
	swing(body.lleg, -0.5, -1, P.legs, 1)
	swing(body.rleg, 0.5, -1, -P.legs, 1)
	local up = P.guard * 2.2 -- (arms raised)
	swing(body.larm, -1.5, 0.5, -P.arms + up, 0.5, -P.spread)
	swing(body.rarm, 1.5, 0.5, P.arms + up, 0.5, P.spread)
	for _, p in pairs(body) do
		p.Transparency = P.hide and 1 or 0
	end
	for i, s in ipairs(stars) do
		if P.stars and not P.hide then
			local a = P.stars * 7 + i * math.pi * 2 / 3
			s.CFrame = cf * CFrame.new(math.cos(a) * 1.7, 2.9 + 0.25 * math.sin(a * 2), math.sin(a) * 1.7)
				* CFrame.Angles(a, a * 0.7, 0)
			s.Transparency = 0
		else
			s.Transparency = 1
		end
	end
	if P.shadowY and not P.hide then
		-- (a dark disc on the floor under them, smaller and fainter the higher they are)
		local h = math.max(0, at.Y - P.shadowY)
		local r = math.max(0.8, 2.6 - h * 0.06)
		shadow.Size = Vector3.new(0.1, r, r)
		shadow.CFrame = CFrame.new(at.X, P.shadowY + 0.08, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
		shadow.Transparency = math.min(0.9, 0.45 + h * 0.02)
	else
		shadow.Transparency = 1
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
		return true -- (nobody gets hurt in a cutscene)
	end,
	DamagePlayer = function()
		return false
	end,
	Shove = function() end,
	SetTargetShape = function() end,
}
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 10 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(10)
local model, def, home = E.model, E.def, E.home
local floorY = E.floorY or home.Y
cam.CFrame = CFrame.lookAt(home + Vector3.new(0, 20, 60), home) -- (the film's camera is the renderer's; this one's for BossClient)
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

local T = M.now()
local DT = 1 / 30
local function tick(dt)
	T += dt
	M.run(T)
	RunService.Heartbeat:Fire(dt)
	RunService.RenderStepped:Fire(dt)
end
-- the game clock forward to `t`, a frame (or less) at a time
local function advanceTo(t)
	while T < t - 1e-6 do
		tick(math.min(DT, t - T))
	end
end

-- his brain stopped: he stands where we say, facing `face`, aiming at the player
local function takeOver(pos, face)
	E.token += 1
	E.motion, E.sweep, E.waves, E.pillarSweep = nil, nil, {}, nil
	E.chase, E.track = false, false
	E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
	E.facing = face
	E.target, E.targetSince = me, M.now()
	return E.token
end
-- one of his moves, right now (his own brain stays stopped: this is a scene)
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
local statics = {}
local function isDynamic(d)
	return (fx and d:IsDescendantOf(fx)) or d:IsDescendantOf(char) or d:IsDescendantOf(model)
end
local function dumpStatic()
	realPrint("STATIC")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not isDynamic(d) and (d.Position - home).Magnitude < 330 then
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
-- where his mouth is drawn (the dark slot under his muzzle: BossBodies/Gavelgrunt's "Mouth")
local function mouthAt()
	fx = fx or workspace:FindFirstChild("BossFX")
	local m = fx and fx:FindFirstChild("Mouth", true)
	return m and m.Position or nil
end
local frame = 0
local function dumpFrame(v, c)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f %.4f", frame, v, M.now(), c))
	local b = model:GetPivot().Position
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, b.Y, E.pos.Z, P.pos.X, P.pos.Y + P.jump, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %d", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), model:GetAttribute("Phase") or 1))
	realPrint(string.format("BAR KING GAVELGRUNT|%.4f|%d", (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), model:GetAttribute("Phase") or 1))
	local aim, head = model:GetAttribute("AimAt"), model:GetAttribute("HeadAt")
	if M.typeof(aim) == "Vector3" and M.typeof(head) == "Vector3" then
		realPrint("AIM " .. v3(aim) .. " " .. v3(head))
	end
	local m = mouthAt()
	if m then
		realPrint("MOUTH " .. v3(m))
	end
	fx = fx or workspace:FindFirstChild("BossFX")
	for _, r in ipairs({ fx, char }) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 and d ~= root then
				realPrint(partLine(d))
			end
		end
	end
	-- arena parts the boss's screen moved or hid
	for i, s in ipairs(statics) do
		local d = s[1]
		local pr = rawget(d, "__props")
		if pr.CFrame ~= s[2] or pr.Size ~= s[3] or pr.Color ~= s[4] or pr.Transparency ~= s[5] then
			realPrint(partLine(d, i))
		end
	end
	realPrint("ENDFRAME")
end
local function event(name, v, extra)
	realPrint(string.format("EVENT %s %.4f %s", name, v, extra or ""))
end

----------------------------------------------------------------------
-- the stage: he stands at his fighting spot facing the gate (south); the
-- player is on the line straight out in front of him, `d` studs from his
-- middle (so his aim never turns him)
----------------------------------------------------------------------
local SOUTH = Vector3.new(0, 0, 1)
local HOME = Vector3.new(home.X, floorY, home.Z)
local function along(d, up)
	return Vector3.new(HOME.X, floorY + 3 + (up or 0), HOME.Z + d)
end
local function ease(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end

local gulp = def.Attacks.BigGulp
local G = 5.0 -- the second Big Gulp starts this long after the first (the loop's length in game seconds)
local LOOP_AT = 1.0 -- the film starts (and loops) this far into a Big Gulp
local PULL0 = gulp.Tell -- the wind starts
local LIFT = gulp.Tell + gulp.Inhale - 0.6 -- the wind lifts them off their feet...
local GULP = gulp.Tell + gulp.Inhale -- ...and into his mouth: GULP
local SPIT = GULP + gulp.Chew -- PTOO
local BURP = SPIT + 0.3 -- the burp
-- (every beat on a frame: whole thirtieths of a second into the cycle)
local LAND = 121 / 30 -- they hit the floor...
local REST = 130 / 30 -- ...slide to a stop, face down...
local UP0, UP1 = 137 / 30, 148 / 30 -- ...and get up, dizzy
local LOOK0, LOOK1 = G + 0.1, G + 13 / 30 -- (his mouth opening again behind them: a look back)
local D_REST = 36 -- where they come to rest (and the wind starts dragging them from)
local D_LIFT = 17 -- where the wind lifts them off the floor
local D_LAND = 31.5 -- where they hit the floor
-- the slow motion: the burp flinging them at us - from the frame after it
-- hits, this many game seconds, at this speed (a whole number of frames each
-- side, so the film's frames land exactly on the loop)
local K_SLOW = math.floor((BURP - LOOP_AT) * 30 + 0.5) + 1 -- (the film frame it starts on)
local SLOW_FROM, SLOW_GAME, SLOW_RATE = LOOP_AT + K_SLOW / 30, 0.2, 0.25
local SLOW_FRAMES = math.floor(SLOW_GAME / (DT * SLOW_RATE) + 0.5)

----------------------------------------------------------------------
-- the player, worked out from c (seconds since the first Big Gulp began):
-- never stepped along, so the same c always gives the same picture
----------------------------------------------------------------------
local liftFrom, spitFrom = nil, nil -- (where the lift-off and the spit started)
local function dragged(u)
	-- running flat out at us (facing the camera), and dragged backwards anyway
	local k = math.clamp((u - PULL0) / (LIFT - PULL0), 0, 1)
	local d = D_REST - (D_REST - D_LIFT) * k ^ 2.2
	P.pos = along(d)
	P.facing = SOUTH
	local run = math.max(0, u - (PULL0 - 0.05)) -- (they start running just as the wind hits)
	local ph = u * 21
	P.legs = math.sin(ph) * 0.95 * math.min(1, run * 8)
	P.arms = math.sin(ph + 0.6) * 0.9
	P.guard = 0.35 + 0.2 * k
	P.spread = 0.35 + 0.25 * math.sin(ph * 0.5)
	P.lean = 0.28 + 0.2 * k -- (straining away from him)
	P.jump = 0.12 * math.abs(math.sin(ph))
	P.tumble, P.headYaw = 0, 0
end

local function placePlayer(c)
	P.hide, P.stars, P.shadowY = false, nil, floorY
	P.legs, P.arms, P.guard, P.spread, P.lean, P.tumble, P.jump, P.headYaw = 0, 0, 0, 0, 0, 0, 0, 0
	P.facing = SOUTH
	local u = c
	if c >= G then
		u = c - G
	end
	if c >= G + PULL0 - 0.05 or (c < LIFT) then
		-- 1) THE WIND: running for it, dragged back
		dragged(u)
		return
	end
	if c < GULP then
		-- 2) OFF THEIR FEET: lifted, tumbling backwards, up into his mouth
		local mouth = mouthAt() or (HOME + Vector3.new(0, 20, 9))
		liftFrom = liftFrom or along(D_LIFT)
		local k = (c - LIFT) / (GULP - LIFT)
		local e = k ^ 1.6
		P.pos = liftFrom:Lerp(mouth, e) + Vector3.new(0, 3.5 * math.sin(math.pi * k), 0)
		P.tumble = -k ^ 1.3 * 7.5 -- (backwards, head over heels)
		local ph = c * 30
		P.legs = math.sin(ph) * 1.1
		P.arms = math.sin(ph + 1) * 1.0
		P.guard, P.spread = 0.7, 0.9
		return
	end
	if c < SPIT then
		-- 3) SWALLOWED (he's chewing)
		P.hide = true
		P.pos = mouthAt() or HOME
		return
	end
	if c < LAND then
		-- 4) PTOO! out of his mouth at us, head over heels - and the burp
		-- catches them in the air and flings them the rest of the way
		spitFrom = spitFrom or (mouthAt() or (HOME + Vector3.new(0, 20, 9)))
		local t = c - SPIT
		local span = LAND - SPIT
		local k = t / span
		-- (along the floor: quick out of his mouth, quicker still once the burp hits)
		local burpK = (BURP - SPIT) / span
		local dk = k < burpK and 0.4 * (k / burpK) or 0.4 + 0.6 * (1 - (1 - (k - burpK) / (1 - burpK)) ^ 1.4)
		local d0 = spitFrom.Z - HOME.Z
		local d = lerp(d0, D_LAND, dk)
		-- (up and over: a throw that lands them lying flat, 1.5 studs up their middle)
		local y0, y1 = spitFrom.Y, floorY + 0.5
		local v0 = 6
		local g = 2 * (y0 - y1 + v0 * span) / (span * span)
		local y = y0 + v0 * t - 0.5 * g * t * t
		P.pos = Vector3.new(HOME.X, y - P.jump, HOME.Z + d)
		-- (a forward flip and a quarter: flat on their face as they land)
		P.tumble = k * (math.pi * 2 + math.pi / 2)
		P.legs = 0.4 * math.sin(c * 24)
		P.arms, P.guard, P.spread = 0.3 * math.sin(c * 20), 0.9, 1.1
		return
	end
	if c < REST then
		-- 5) SLIDING along the floor on their face, to a stop
		local k = (c - LAND) / (REST - LAND)
		local d = lerp(D_LAND, D_REST, 1 - (1 - k) ^ 2)
		P.pos = along(d - 1, -1.5) -- (lying flat, face down: the lean tips them forward round the hips)
		P.lean = math.pi / 2
		P.arms, P.guard, P.spread = 0, 1, 0.2 -- (arms out ahead)
		P.legs = 0.15
		return
	end
	if c < UP0 then
		-- 6) lying there
		P.pos = along(D_REST - 1, -1.5)
		P.lean = math.pi / 2
		P.guard, P.spread = 1, 0.2
		P.legs = 0.15
		P.stars = c
		return
	end
	if c < UP1 then
		-- 7) getting up, dizzy
		local k = ease((c - UP0) / (UP1 - UP0))
		P.pos = along(D_REST - (1 - k), -1.5 * (1 - k))
		P.lean = math.pi / 2 * (1 - k)
		P.guard = 1 - k
		P.spread = 0.2 + 0.3 * k
		P.legs = 0.15 * (1 - k)
		P.stars = c
		return
	end
	-- 8) up, swaying, stars round their head... his mouth's opening behind
	-- them: a look back over the shoulder - and they turn and run
	P.pos = along(D_REST)
	local sway = math.sin((c - UP1) * 9) * math.max(0, 1 - (c - UP1) / 0.6)
	P.lean = 0.12 * sway
	P.spread = 0.5 * math.max(0, 1 - (c - UP1) / 0.4)
	P.stars = (c < LOOK1) and c or nil
	if c >= LOOK0 then
		local k = math.min(1, (c - LOOK0) / 0.12)
		if c > LOOK1 - 0.08 then
			k = math.max(0, 1 - (c - (LOOK1 - 0.08)) / 0.08)
		end
		P.headYaw = math.pi * 0.85 * k
		P.facing = Vector3.new(-0.35 * k, 0, 1).Unit
	end
end

----------------------------------------------------------------------
-- before the camera rolls: his entrance, then he's at his spot and the
-- first Big Gulp begins
----------------------------------------------------------------------
P.pos = along(D_REST)
pose()
advanceTo(T + 0.5)
dumpStatic()
me:SetAttribute("SpireFloor", 10) -- (in range: he wakes at his next look round)
while model:GetAttribute("Action") ~= "Wake" do
	advanceTo(T + DT)
end
local wakeAt = model:GetAttribute("ActionStart")
advanceTo(wakeAt + def.WakeTime + 0.3)
while model:GetAttribute("State") ~= "Fighting" do
	advanceTo(T + DT)
end
takeOver(HOME, SOUTH)
advanceTo(T + 1.5) -- (his body settles on his spot)

force("BigGulp")
local TA = model:GetAttribute("ActionStart")
event("gulpA", 0, string.format("%.4f", TA))
local gulpB = nil
-- (the first second of the Big Gulp, before the film starts: the player already running)
local c = 0
while c < LOOP_AT - 1e-6 do
	c = math.min(LOOP_AT, c + DT)
	placePlayer(c)
	pose()
	advanceTo(TA + c)
end

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
local FRAMES = math.floor((G - SLOW_GAME) / DT + SLOW_GAME / (DT * SLOW_RATE) + 0.5)
event("loop", 0, string.format("%d %.4f %.4f %.4f", FRAMES, G, LOOP_AT, SLOW_RATE))
event("times", 0, string.format("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", PULL0, LIFT, GULP, SPIT, BURP, LAND,
	REST, UP0, UP1, LOOK0, LOOK1))
event("stage", 0, v3(HOME) .. " " .. string.format("%.2f %.2f %.2f %.2f", D_REST, D_LIFT, D_LAND, def.Size))
for k = 0, FRAMES - 1 do
	local v = k * DT
	-- the cycle time for this frame (slow motion as the burp flings them)
	local cc
	local slowing = k >= K_SLOW and k < K_SLOW + SLOW_FRAMES
	if k < K_SLOW then
		cc = LOOP_AT + k * DT
	elseif slowing then
		cc = SLOW_FROM + (k - K_SLOW) * DT * SLOW_RATE
	else
		cc = SLOW_FROM + SLOW_GAME + (k - K_SLOW - SLOW_FRAMES) * DT
	end
	if not gulpB and cc >= G - 1e-6 then
		-- (the game clock right up to the second Big Gulp, and it begins)
		advanceTo(TA + G)
		force("BigGulp")
		gulpB = model:GetAttribute("ActionStart")
		event("gulpB", v, string.format("%.4f", gulpB))
	end
	placePlayer(cc)
	pose()
	advanceTo(TA + cc)
	-- the film's moments
	for _, m in ipairs({ { "lift", LIFT }, { "gulp", GULP }, { "spit", SPIT }, { "burp", BURP }, { "land", LAND }, { "rest", REST },
		{ "up", UP0 }, { "open", G }, { "look", LOOK0 }, { "run", G + PULL0 - 0.05 } }) do
		if cc >= m[2] - 1e-6 and cc - m[2] < (slowing and DT * SLOW_RATE or DT) - 1e-6 then
			local mouth = mouthAt()
			event(m[1], v, string.format("%.4f %s %s", cc, v3(P.pos), mouth and v3(mouth) or ""))
			if m[1] == "burp" and mouth then
				-- (a green cloud bursting out of his mouth: the burp itself)
				burstLine(mouth + Vector3.new(0, -1, 2), 150, 230, 80, 34, 3, 7.5, 10, 24, 0.5, 0.9, 110, -4, 4)
			end
			if m[1] == "land" then
				-- (a puff of dust where they hit the floor)
				burstLine(along(D_LAND, -3), 196, 190, 214, 26, 1.6, 3.2, 6, 14, 0.35, 0.6, 70, -20, 3)
			end
		end
	end
	if k == K_SLOW then
		event("slow", v, string.format("%.4f", cc))
	end
	if k == K_SLOW + SLOW_FRAMES then
		event("fast", v, string.format("%.4f", cc))
	end
	dumpFrame(v, cc)
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
