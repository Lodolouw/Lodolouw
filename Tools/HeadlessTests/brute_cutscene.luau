--!nocheck
-- A 10-second cutscene of floor 2 for a YouTube Short, starring THE BRUTE:
-- the real Sunken Dunes (DunesBuilder), the real BossService with Tuber's
-- brain stopped and his moves forced one after another like a scripted scene,
-- the real BossClient drawing him (BossBodies/Tuber: little Tuber, the
-- power-up, the golem), and a blocky player who punches, rolls and gets
-- blasted. Every video frame (30 a second) prints what's on screen;
-- render_brute_cutscene.py films it.
--
--   luau brute_cutscene.luau > brute.txt
--   python3 render_brute_cutscene.py brute.txt ../../Docs/youtube/brute_cutscene.mp4
--
-- The film's clock and the game's clock aren't the same: the power-up is 9
-- seconds in the game, so the film cuts through it - real time as little
-- Tuber flops, fast (x3) while the desert flies to him and the golem slams
-- together, real time as the crown drops, then a jump cut to the roar. The
-- game clock only ever runs forward, in steps of a frame or less, so the
-- server and the screen see every moment in between (a jump cut just isn't
-- printed).
--
-- What it prints: STATIC (every arena part, once, each with an index), then
-- for every frame FRAME (film time, game time), POS (his middle, the
-- player's), STATE, BAR (his health bar as his body file draws it), ANCHOR
-- (the point over his head his words hang from), SHOUT / HINT / BIG (his word
-- bubbles, the "HIT HIM!" over him, big words across the screen), and the
-- parts that moved: his body and effects, the player, and any arena part that
-- changed (by index: the cacti flying to him). And, as they happen: BURST (a
-- puff of particles BossClient emitted: the renderer draws them, the
-- pretend Roblox can't), KICK (a camera knock the game asked for) and EVENT
-- (the film's own moments: punches landing, the slam...).
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

local arena = mount.require(mount.module("ServerScriptService/DunesBuilder.lua")).Build()
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
M.methods.Emit = function(self, count)
	local holder = self.Parent
	if not (holder and holder.CFrame) then
		return
	end
	local p = holder.Position
	local col = type(self.Color) == "table" and self.Color[1] or M.Color3.fromRGB(255, 255, 255)
	local size = type(self.Size) == "table" and self.Size[1] or {}
	local s0 = type(size[1]) == "table" and size[1][2] or 1.5
	local s1 = type(size[2]) == "table" and size[2][2] or s0 * 2.2
	local acc = self.Acceleration or Vector3.new(0, -30, 0)
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
local body = {
	torso = limb("Torso", Vector3.new(2, 2, 1), SHIRT),
	head = limb("Head", Vector3.new(1.2, 1.2, 1.2), SKIN),
	larm = limb("LeftArm", Vector3.new(1, 2, 1), SKIN),
	rarm = limb("RightArm", Vector3.new(1, 2, 1), SKIN),
	lleg = limb("LeftLeg", Vector3.new(1, 2, 1), PANTS),
	rleg = limb("RightLeg", Vector3.new(1, 2, 1), PANTS),
}
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
-- (the power-up's own camera shots, CombatClient's cutscene event: kept, and printed)
local gameShot = nil
local cut = Instance.new("BindableEvent")
cut.Name = "CombatCutscene"
cut.Parent = scripts
cut.Event:Connect(function(kind, cf, fov)
	gameShot = (kind == "Shot") and { cf = cf, fov = fov } or nil
end)
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1080, Y = 1920 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- where the player is and how they're posed: `pos` is the middle of the body
-- (3 studs over the floor), `facing` the way they look, and the limbs swing
-- by `legs` / `arms` (radians, + is forward); `roll` tumbles the whole body
-- round the way it's moving (0-1 is one full roll); `punch` / `punchL` throw
-- the right / left fist straight out (0-1); `guard` puts both arms up in
-- front of the face (0-1); `lean` tips the body forward (radians); `jump` is
-- how high the feet are off the floor. (oozark_cutscene.luau's figure.)
local P = { pos = Vector3.zero, facing = Vector3.new(0, 0, -1), legs = 0, arms = 0, roll = nil, rollDir = nil,
	punch = 0, punchL = 0, guard = 0, lean = 0, jump = 0 }
local function pose()
	local look = Vector3.new(P.facing.X, 0, P.facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local at = P.pos + Vector3.new(0, P.jump, 0)
	-- (leaning pivots at the hips, a stud under the middle)
	local cf = CFrame.lookAt(at, at + look) * CFrame.new(0, -1, 0) * CFrame.Angles(-P.lean, 0, 0) * CFrame.new(0, 1, 0)
	if P.roll then
		local dir = P.rollDir or look
		local axis = Vector3.new(0, 1, 0):Cross(dir).Unit
		cf = CFrame.new(at) * CFrame.fromAxisAngle(axis, -P.roll * math.pi * 2) * (cf - cf.Position)
	end
	root.CFrame = CFrame.new(at) * (cf - cf.Position)
	body.torso.CFrame = cf
	body.head.CFrame = cf * CFrame.new(0, 1.6, 0)
	local function swing(part, x, y, angle, drop)
		part.CFrame = cf * CFrame.new(x, y, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -drop, 0)
	end
	local tuck = P.roll and 1.2 or 0 -- (curled up in a roll: knees and arms in)
	swing(body.lleg, -0.5, -1, P.legs + tuck, 1)
	swing(body.rleg, 0.5, -1, -P.legs + tuck, 1)
	local up = P.guard * 2.2 -- (arms raised, fists by the face)
	local la = -P.arms + tuck + up
	local ra = P.arms + tuck + up
	swing(body.larm, -1.5, 0.5, la + P.punchL * (math.pi / 2 - la), 0.5)
	swing(body.rarm, 1.5, 0.5, ra + P.punch * (math.pi / 2 - ra), 0.5)
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
local Profile = { RecordBossKill = function() return true end, AddPower = function() end, AddChest = function() end }
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 2 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(2)
local model, def, home = E.model, E.def, E.home
local floorY = home.Y
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

-- BossService's setAction, from out here: a new action every screen sees
local SLOTS = { "ActA", "ActB", "ActC", "Act4", "Act5", "Act6", "Act7", "Act8", "Act9", "Act10", "Act11", "Act12" }
local function publish(name, number)
	E.actionId += 1
	for _, key in ipairs(SLOTS) do
		model:SetAttribute(key, nil)
	end
	model:SetAttribute("ActK", 0)
	model:SetAttribute("ActN", number)
	model:SetAttribute("Action", name)
	model:SetAttribute("ActionStart", M.now())
	model:SetAttribute("ActionId", E.actionId)
end

-- stands him where we say, facing where we say
local function stand(pos, facing)
	E.pos = Vector3.new(pos.X, floorY, pos.Z)
	E.facing = Vector3.new(facing.X, 0, facing.Z).Unit
	E.motion, E.arc, E.sweep = nil, nil, nil
	E.root.CFrame = CFrame.lookAt(E.pos + Vector3.new(0, E.height / 2, 0), E.pos + Vector3.new(0, E.height / 2, 0) + E.facing)
end

-- one of his moves, right now (his own brain stops: this is a scene)
local function force(name)
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.chase = false
	local fn = E.boss.Attacks[name] or E.boss.Moves[name]
	M.task.spawn(function()
		fn(E, token)
	end)
end

-- a punch landing: his health drops (he wobbles and blanches on screen) and
-- the blow jolts him back (what CombatService does for a real punch).
-- `share` is how much of the bar showing it knocks off.
local hits = 0
local function punchLands(weight, share)
	local max = model:GetAttribute("MaxHealth") or 100
	local line = math.max(1, math.floor(max * def.PhaseAt))
	local hp = model:GetAttribute("Health") or max
	local barSize = ((model:GetAttribute("Phase") or 1) < 2) and (max - line) or line
	local floorHp = ((model:GetAttribute("Phase") or 1) < 2) and line or 1
	local dmg = math.max(1, math.floor(barSize * share + 0.5))
	model:SetAttribute("Health", math.max(floorHp, hp - dmg))
	hits += 1
	local away = Vector3.new(E.pos.X - P.pos.X, 0, E.pos.Z - P.pos.Z)
	away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, -1)
	model:SetAttribute("HitFx", string.format("%d:%d:%.3f:%.3f", hits, weight, away.X, away.Z))
	local onHit = model:FindFirstChild("OnHit")
	if onHit then
		onHit:Fire(me, dmg, false, weight)
	end
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

-- his health bar, as BossBodies/Tuber's barLook draws it: round 1's bar
-- (little Tuber's share above PhaseAt); empty through the power-up; then
-- the Brute's, filling up from the moment he roars (7.2 s into it)
local T_ROAR = 7.2
local breakAt = nil
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function barNow()
	local max = math.max(model:GetAttribute("MaxHealth") or 1, 1)
	local hp = model:GetAttribute("Health") or max
	local line = math.max(1, math.floor(max * def.PhaseAt))
	if (model:GetAttribute("Phase") or 1) < 2 then
		return def.Name, math.clamp((hp - line) / math.max(max - line, 1), 0, 1), 1
	end
	local reveal = breakAt and breakAt + T_ROAR
	if reveal and M.now() < reveal then
		return def.Name, 0, 1
	end
	local fill = reveal and smooth((M.now() - reveal) / 1.6) or 1
	return def.Round2Name, math.min(fill, math.clamp(hp / line, 0, 1)), 2
end

-- the words on screen the game made (BillboardGuis over him, big words)
local function labelIn(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d.ClassName == "TextLabel" then
			return d
		end
	end
	return nil
end
local function colorText(c)
	c = c or M.Color3.fromRGB(255, 255, 255)
	return string.format("%d %d %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function dumpWords()
	for _, g in ipairs(gui:GetChildren()) do
		if g.Name == "BossShout" and g.Adornee then
			local l = labelIn(g)
			local p = g.Adornee.Position + (g.StudsOffsetWorldSpace or Vector3.zero)
			if l then
				realPrint(string.format("SHOUT %s %.2f %.2f %.2f %s", colorText(l.TextColor3), p.X, p.Y, p.Z, esc(l.Text)))
			end
		elseif g.Name == "BossBigText" and g.Enabled ~= false then
			local big = g:FindFirstChild("Big", true)
			if big and (big.TextTransparency or 0) < 0.9 and big.Text ~= "" then
				realPrint(string.format("BIG %s %s", colorText(big.TextColor3), esc(big.Text)))
			end
		end
	end
	for _, d in ipairs(fx:GetDescendants()) do
		if d.Name == "TuberHint" and d.Adornee then
			local l = labelIn(d)
			local p = d.Adornee.Position + (d.StudsOffsetWorldSpace or Vector3.zero)
			if l then
				realPrint(string.format("HINT %s %.2f %.2f %.2f %s", colorText(l.TextColor3), p.X, p.Y, p.Z, esc(l.Text)))
			end
		end
	end
end

local frame = 0
local function dumpFrame(v)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f", frame, v, M.now()))
	local b = model:GetPivot().Position
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, b.Y, E.pos.Z, P.pos.X, P.pos.Y, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %s", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), tostring(model:GetAttribute("Form"))))
	local name, share, phase = barNow()
	realPrint(string.format("BAR %s|%.4f|%d", esc(name), share, phase))
	fx = fx or workspace:FindFirstChild("BossFX")
	local anchor = fx and fx:FindFirstChild("Anchor", true)
	if anchor then
		local a = anchor.Position
		realPrint(string.format("ANCHOR %.3f %.3f %.3f", a.X, a.Y, a.Z))
	end
	if gameShot then
		local p, l = gameShot.cf.Position, gameShot.cf.Position + gameShot.cf.LookVector * 100
		realPrint(string.format("GAMECAM %.3f %.3f %.3f %.3f %.3f %.3f %.2f", p.X, p.Y, p.Z, l.X, l.Y, l.Z, gameShot.fov or 70))
	end
	dumpWords()
	for _, r in ipairs({ fx, char }) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 and d ~= root then
				realPrint(partLine(d))
			end
		end
	end
	-- arena parts the boss's screen moved or hid (the cacti, ripped out and flying to him)
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
-- the stage (studs from the middle of the bowl, on the floor)
----------------------------------------------------------------------
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function spot(dx, dz)
	return Vector3.new(C.X + dx, floorY + 3, C.Z + dz)
end
local HOME = Vector3.new(home.X, floorY, home.Z) -- little Tuber's garden, in the very middle
-- where the Brute's hop lands: one of the spots his hop picks from (his
-- hopSpot looks round three rings about the middle of the bowl, 0.35, 0.65
-- and 1.0 of his Leash less 3) - the nearest ring, on the gate side
local HOP_R = (def.Leash - 3) * 0.35
local LAND = Vector3.new(C.X, floorY, C.Z + HOP_R)
-- (and the spot it has to be 58 studs from - the distance he likes to land
-- from you, Moves.RootHop.Want - for him to pick LAND: straight on out from it)
local DECOY = Vector3.new(C.X, floorY + 3, C.Z + HOP_R + def.Moves.RootHop.Want)

----------------------------------------------------------------------
-- before the camera rolls: the player walks into the dunes, Tuber wakes up
-- (pops out of his garden and waves), and then his brain is stopped
----------------------------------------------------------------------
P.pos = spot(0, 30)
P.facing = Vector3.new(0, 0, -1)
pose()
me:SetAttribute("SpireFloor", 2)
advanceTo(T + 0.5)
dumpStatic()
while model:GetAttribute("State") ~= "Fighting" do
	advanceTo(T + DT)
end
E.token += 1 -- (his brain stops)
E.boss._tidy(E, "Gone")
E.track, E.chase, E.target = false, false, me
local TUBER_FACE = Vector3.new(0.3, 0, 1).Unit -- (turned a touch toward the camera, over the player's right shoulder)
stand(HOME, TUBER_FACE)
publish("Idle", nil)
-- his first bar: most of it already punched away (the fight's nearly won...)
do
	local max = model:GetAttribute("MaxHealth")
	local line = math.floor(max * def.PhaseAt)
	model:SetAttribute("Health", line + math.floor((max - line) * 0.3))
end
P.pos = HOME + Vector3.new(-0.2, 3, 4.75)
P.facing = flat(HOME - P.pos).Unit
pose()
advanceTo(T + 2.5) -- (everything settles: no leftover warnings from the move his brain had started)

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
local FILM = {
	punches = { { at = 0.0, weight = 1, left = true, share = 0.1 }, { at = 0.2, weight = 2, share = 0.1 },
		{ at = 0.42, weight = 3, share = 1 } }, -- (the third empties his first bar: the power-up)
	cutFly = 1.0, -- the desert flies to him (x3)
	cutCrown = 1.95, -- the crown drops (real time)
	cutRoar = 2.6, -- (a jump) the roar
	cutHop = 4.1, -- (a jump) the root hop
	rollOut = 5.52, -- out of the red circle as he comes down
	rollIn = 6.12, -- through the ring of sand, in to him
	cornered = 6.5, -- CORNERED: his hop isn't ready
	combo = { { at = 6.62, weight = 1, left = true, share = 0.03 }, { at = 6.88, weight = 2, share = 0.035 },
		{ at = 7.16, weight = 3, share = 0.06 }, { at = 7.52, weight = 1, left = true, share = 0.03 },
		{ at = 7.78, weight = 2, share = 0.035 }, { at = 8.06, weight = 3, share = 0.06 },
		{ at = 8.42, weight = 1, left = true, share = 0.03 } }, -- (the last one greedy: he's bristling)
	uhOh = 8.64, -- (they see it coming: arms up)
	shove = 8.2, -- SHOVE BURST: he snaps out of it...
	frames = 300,
}
-- where the power-up is in each part of the film (seconds into it)
local FLY_FROM, FLY_TO = 1.2, 4.2
local CROWN_FROM = 4.2
local ROAR_FROM = 7.0

local walkPhase = 0
local rolling = nil -- { t0, from, to, time, dash }
local function startRoll(v, to, seconds)
	rolling = { t0 = v, from = P.pos, to = to, time = seconds or 0.38 }
	P.rollDir = flat(to - P.pos).Unit
end
local function stepRoll(v)
	if not rolling then
		return
	end
	local k = math.min(1, (v - rolling.t0) / rolling.time)
	P.pos = rolling.from:Lerp(rolling.to, 1 - (1 - k) * (1 - k))
	P.roll = (k < 1 and not rolling.dash) and k or nil
	if k >= 1 then
		rolling = nil
		P.roll = nil
	end
end
local function faceBoss()
	local d = flat(E.pos - P.pos)
	if d.Magnitude > 0.01 then
		P.facing = d.Unit
	end
end
local function throwPunches(list, v)
	for _, pu in ipairs(list) do
		local since = v - pu.at
		if since >= 0 and since < 0.24 then
			faceBoss()
			local k = since < 0.07 and since / 0.07 or math.max(0, 1 - (since - 0.07) / 0.17)
			if pu.left then
				P.punchL = k
			else
				P.punch = k
			end
			P.lean = k * (pu.weight >= 3 and 0.35 or 0.15)
			if not pu.landed and since >= 0.07 then
				pu.landed = true
				local fist = (pu.left and body.larm or body.rarm).CFrame * CFrame.new(0, -1, 0)
				punchLands(pu.weight, pu.share)
				event("hit", v, string.format("%d %.2f %.2f %.2f", pu.weight, fist.Position.X, fist.Position.Y, fist.Position.Z))
			end
		end
	end
end

local done = {}
local function once(key, v, at, fn)
	if not done[key] and v >= at then
		done[key] = true
		fn()
	end
end

local hopAt = nil -- (when the hop started, game time)
local fling = nil -- { t0, from, dir }: blasted off his spines
for k = 1, FILM.frames do
	local v = (k - 1) * DT

	------------------------------------------------------------------
	-- the game clock for this frame
	------------------------------------------------------------------
	local want = T + DT
	if breakAt and v >= FILM.cutFly and v < FILM.cutCrown then
		want = breakAt + FLY_FROM + (v - FILM.cutFly) * (FLY_TO - FLY_FROM) / (FILM.cutCrown - FILM.cutFly)
	elseif breakAt and v >= FILM.cutCrown and v < FILM.cutRoar then
		want = breakAt + CROWN_FROM + (v - FILM.cutCrown)
	elseif breakAt and v >= FILM.cutRoar and v < FILM.cutHop then
		want = breakAt + ROAR_FROM + (v - FILM.cutRoar)
	end

	------------------------------------------------------------------
	-- 1) THE PUSHOVER: three punches on little Tuber - the last empties his
	-- first bar, and the power-up begins
	------------------------------------------------------------------
	if v < FILM.cutFly then
		throwPunches(FILM.punches, v)
		if not breakAt and model:GetAttribute("Action") == "Break" then
			breakAt = model:GetAttribute("ActionStart")
			event("break", v)
		end
		if v > 0.7 then
			P.punch, P.punchL, P.lean = P.punch * 0.6, P.punchL * 0.6, P.lean * 0.6
		end
	end

	------------------------------------------------------------------
	-- 2) the desert flies to him: the player has been thrown back (the
	-- golem standing up shoves everyone near away), arms up against the storm
	------------------------------------------------------------------
	once("fly", v, FILM.cutFly, function()
		P.punch, P.punchL, P.lean = 0, 0, 0
		P.pos = spot(0.6, 13)
		P.facing = Vector3.new(0, 0, -1)
		E.facing = Vector3.new(0.12, 0, 1).Unit
		event("fly", v)
	end)
	if v >= FILM.cutFly and v < FILM.cutRoar then
		P.guard = math.min(1, (v - FILM.cutFly) / 0.15)
		P.lean = -0.08
	end
	-- 3) the crown drops (and THE slams down with it)
	once("crown", v, FILM.cutCrown, function()
		E.facing = Vector3.new(0.35, 0, 1).Unit -- (his face toward the camera, low on his right)
		event("crown", v)
	end)
	------------------------------------------------------------------
	-- 4) THE ROAR: he towers over the player, who flinches back
	------------------------------------------------------------------
	once("roar", v, FILM.cutRoar, function()
		P.pos = spot(-2.4, 25)
		P.facing = Vector3.new(0, 0, -1)
		P.guard, P.lean = 0, 0
		E.facing = Vector3.new(-0.18, 0, 1).Unit
		event("roar", v)
	end)
	if v >= FILM.cutRoar and v < FILM.cutHop then
		local u = v - (FILM.cutRoar + 0.2) -- (he roars 7.2 s into the power-up)
		P.guard = (u > 0) and math.min(1, u / 0.1) * (u < 0.9 and 1 or math.max(0, 1 - (u - 0.9) / 0.3)) or 0
		P.lean = (u > 0 and u < 1.0) and -0.12 or 0
		if u > 0 and u < 0.25 then
			P.pos = P.pos + Vector3.new(0, 0, 3.2 * DT / 0.25) -- (a step back)
		end
	end

	------------------------------------------------------------------
	-- 5) ROOT HOP: he rips his roots up and leaps at them - they're
	-- standing right where he'll land
	------------------------------------------------------------------
	if v >= FILM.cutHop and not hopAt then
		-- (the power-up's last moments go by in the cut; his brain stops just
		-- before it would start round 2 itself)
		advanceTo(breakAt + def.BreakTime - 0.05)
		want = T + DT
		E.token += 1
		E.boss._tidy(E, "Gone")
		stand(HOME, Vector3.new(0, 0, 1))
		P.pos = LAND + Vector3.new(1.0, 3, 1.6)
		P.facing = flat(HOME - P.pos).Unit
		P.guard, P.lean = 0, 0
		pose()
		-- (for a moment the player "stands" at DECOY - out of sight, in no
		-- frame - so the real hopSpot picks LAND: the spot 58 studs from them)
		local keep = root.CFrame
		root.CFrame = CFrame.new(DECOY)
		local pick = E.boss._hopSpot(E, HOME)
		assert((pick - LAND).Magnitude < 0.01, "the hop should land at LAND, not " .. tostring(pick))
		force("RootHop")
		root.CFrame = keep
		hopAt = model:GetAttribute("ActionStart")
		-- (this frame shows the game a frame into the hop; from here the clocks run together)
		local H = def.Moves.RootHop
		event("hop", v)
		event("takeoff", v + H.Tell - DT)
		event("land", v + H.Tell + H.Air - DT)
	end
	-- looking up at him the whole way
	if hopAt and v < FILM.rollOut then
		faceBoss()
	end
	once("rollout", v, FILM.rollOut, function()
		startRoll(v, LAND + Vector3.new(3.4, 3, 12.6), 0.4)
	end)
	-- ...and roll straight back in, through the ring of sand as it passes, to
	-- stand in front of his left shin (he'll face them turned a little toward
	-- the camera, which is off their right shoulder)
	local faceB = Vector3.new(0.34, 0, 1).Unit
	local rightB = faceB:Cross(Vector3.new(0, 1, 0)) -- (his RightVector: his left leg is on the other side)
	local punchSpot = LAND + faceB * 5.0 - rightB * 2.5 + Vector3.new(0, 3, 0)
	once("rollin", v, FILM.rollIn, function()
		startRoll(v, punchSpot, 0.36)
	end)

	------------------------------------------------------------------
	-- 6) CORNERED: his hop has to recharge - he panics, and they punch
	------------------------------------------------------------------
	once("cornered", v, FILM.cornered, function()
		E.facing = faceB
		force("Cornered")
		event("cornered", v)
	end)
	if v >= FILM.cornered then
		throwPunches(FILM.combo, v)
	end
	-- he snaps out of it: SHOVE BURST (spines bristle... BLAST)
	once("shove", v, FILM.shove, function()
		force("ShoveBurst")
		event("shove", v)
	end)
	local blastV = FILM.shove + def.Moves.ShoveBurst.Tell
	if v >= FILM.uhOh and v < blastV then
		P.guard = math.min(1, (v - FILM.uhOh) / 0.08)
		P.lean = -0.1
	end
	once("blast", v, blastV, function()
		P.punch, P.punchL, P.lean = 0, 0, 0
		fling = { t0 = v, from = P.pos, dir = flat(P.pos - LAND).Unit }
		event("blast", v)
	end)
	if fling then
		-- (thrown back off his spines: up and away, tumbling)
		local u = v - fling.t0 + DT -- (the blast lands between frames: a frame's worth of it already)
		local dist = 16 * (1 - math.exp(-u * 6))
		P.pos = fling.from + fling.dir * dist
		P.jump = math.max(0, 30 * u - 0.5 * 120 * u * u)
		P.roll, P.rollDir = u * 1.6, fling.dir
		P.facing = -fling.dir
		P.legs, P.arms = 0.5, -1.2
	end

	stepRoll(v)
	pose()
	advanceTo(want)
	dumpFrame(v)
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
