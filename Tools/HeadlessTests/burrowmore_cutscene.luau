--!nocheck
-- An 11-second cutscene of floor 3 for a YouTube Short, starring KNIGHT
-- BURROWMORE: the real Glimmer Dig (DigBuilder), the real BossService with
-- his brain stopped and his moves forced one after another like a scripted
-- scene, the real BossClient drawing him (BossBodies/Burrowmore), and a
-- blocky player who runs, rolls and punches. Every video frame (30 a second)
-- prints what's on screen; render_burrowmore_cutscene.py films it.
--
--   luau burrowmore_cutscene.luau > burrowmore.txt
--   python3 render_burrowmore_cutscene.py burrowmore.txt ../../Docs/youtube/burrowmore_cutscene.mp4
--
-- The scene, beat by beat: he finishes waking up (the shovel yanked out of
-- the dirt, a twirl, his pose); a SHOVEL DROP (the red circle chases the
-- player, who rolls out of it as he slams down); his shovel's stuck - three
-- punches; a CHARGE DASH into the edge of the dig (the player rolls aside at
-- the last moment) and he's seeing stars - three more punches crack his
-- armour: NO QUARTER! - and his SHOVEL METEOR (the film freezes as he plunges
-- out of the sky, the player racing for the edge of the shadow).
--
-- The film's clock and the game's clock aren't always the same: the armour
-- cracking plays at double speed until his shoulder plates fly off, and the
-- meteor's long wait high in the sky goes by fast. The game clock only ever
-- runs forward, a frame or less at a time, so the server and the screen see
-- every moment in between (a sped-up stretch just isn't printed frame by
-- frame). At two cuts the player jumps to a new spot (a jump cut: no frame
-- shows them moving).
--
-- What it prints (as brute_cutscene.luau): STATIC (every arena part, once,
-- each with an index), then for every frame FRAME (film time, game time),
-- POS (his middle on the floor, the player's), STATE, BAR (his health bar),
-- AIM / HEAD (the middle of his drawn body and the top of it - BossClient's
-- own measure, for the lock-on), and the parts that moved: his body and
-- effects, the player, and any arena part that changed (by index). And, as
-- they happen: BURST (a puff of particles BossClient emitted: the renderer
-- draws them, the pretend Roblox can't), KICK (a camera knock the game asked
-- for) and EVENT (the film's own moments, with the spots the cameras need).
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(1) -- (anything using math.random: the same film every run)

local arena = mount.require(mount.module("ServerScriptService/DigBuilder.lua")).Build()
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
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(3)
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

-- he's fighting (what the end of his wake-up would have set, had his brain
-- been allowed to start)
local function fighting()
	E.state = "Fighting"
	model:SetAttribute("State", "Fighting")
	model:SetAttribute("Invulnerable", false)
end

-- one of his moves, right now (his own brain stops: this is a scene)
local function force(name)
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.chase = false
	E.motion, E.sweep, E.arc = nil, nil, nil
	local fn = (name == "ShovelMeteor") and E.boss._Meteor or E.boss.Attacks[name]
	M.task.spawn(function()
		fn(E, token)
	end)
end

-- a punch landing: his health drops (he wobbles and blanches on screen) and
-- the blow jolts him back (what CombatService does for a real punch).
-- `share` is how much of his whole health it knocks off.
local hits = 0
local function punchLands(weight, share, fromPos)
	local max = model:GetAttribute("MaxHealth") or 100
	local hp = model:GetAttribute("Health") or max
	local dmg = math.max(1, math.floor(max * share + 0.5))
	model:SetAttribute("Health", math.max(1, hp - dmg))
	hits += 1
	local away = Vector3.new(E.pos.X - fromPos.X, 0, E.pos.Z - fromPos.Z)
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

local function v3(v)
	return string.format("%.3f %.3f %.3f", v.X, v.Y, v.Z)
end
local frame = 0
local function dumpFrame(v)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f", frame, v, M.now()))
	local b = model:GetPivot().Position
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, b.Y, E.pos.Z, P.pos.X, P.pos.Y, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %d", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), model:GetAttribute("Phase") or 1))
	realPrint(string.format("BAR KNIGHT BURROWMORE|%.4f|%d", (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), model:GetAttribute("Phase") or 1))
	local aim, head = model:GetAttribute("AimAt"), model:GetAttribute("HeadAt")
	if M.typeof(aim) == "Vector3" and M.typeof(head) == "Vector3" then
		realPrint("AIM " .. v3(aim) .. " " .. v3(head))
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
-- the stage (studs from the middle of the dig, on the floor)
----------------------------------------------------------------------
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function spot(dx, dz)
	return Vector3.new(C.X + dx, floorY + 3, C.Z + dz)
end
-- how far from `from` along `dir` the edge of his leash is (the server's own
-- sum: where a Charge Dash runs into the edge of the dig)
local function toEdge(from, dir, r)
	local o = flat(from - home)
	local b = o:Dot(dir)
	local c = o:Dot(o) - r * r
	local disc = b * b - c
	if disc < 0 then
		return 0
	end
	return math.max(0, -b + math.sqrt(disc))
end
-- the spot for a punch: in front of him, just outside his body, facing him
local PUNCH_GAP = def.Size / 2 + 2.9
local function punchSpotFacing(dir)
	return Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + dir * PUNCH_GAP
end

local walkPhase = 0
local function walkTo(target, speed)
	local d = flat(target - P.pos)
	local stepLen = math.min(d.Magnitude, speed * DT)
	if stepLen > 0.001 then
		P.pos = P.pos + d.Unit * stepLen
		P.facing = d.Unit
		walkPhase += stepLen * 0.5
		P.legs = math.sin(walkPhase) * 0.75
		P.arms = math.sin(walkPhase) * 0.65
	else
		P.legs, P.arms = P.legs * 0.7, P.arms * 0.7
	end
end
local rolling = nil -- { t0, from, to, time, dash }
local function startRoll(v, to, seconds)
	rolling = { t0 = v, from = P.pos, to = to, time = seconds or 0.38 }
	P.rollDir = flat(to - P.pos).Unit
	P.legs, P.arms = 0, 0
end
-- a quick dash in: the roll's easing, without the tumble
local function approach(v, to, seconds)
	rolling = { t0 = v, from = P.pos, to = to, time = seconds, dash = true }
	P.facing = flat(to - P.pos).Unit
end
local function stepRoll(v)
	if not rolling then
		return
	end
	local k = math.min(1, (v - rolling.t0) / rolling.time)
	P.pos = rolling.from:Lerp(rolling.to, 1 - (1 - k) * (1 - k))
	P.roll = (k < 1 and not rolling.dash) and k or nil
	if rolling.dash and k < 1 then
		P.lean = 0.3 * (1 - k)
		P.legs = math.sin(k * 9) * 0.8
		P.arms = -math.sin(k * 9) * 0.6
	end
	if k >= 1 then
		rolling = nil
		P.roll = nil
		P.lean = 0
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
			if not pu.landed and since >= 0.07 - 1e-6 then
				pu.landed = true
				local fist = (pu.left and body.larm or body.rarm).CFrame * CFrame.new(0, -1, 0)
				punchLands(pu.weight, pu.share, P.pos)
				event("hit", v, string.format("%d %.2f %.2f %.2f", pu.weight, fist.Position.X, fist.Position.Y, fist.Position.Z))
			end
		end
	end
end
local done = {}
local function once(key, v, at, fn)
	if not done[key] and v >= at - 1e-6 then
		done[key] = true
		fn()
	end
end

----------------------------------------------------------------------
-- before the camera rolls: the player walks up and he starts to wake
----------------------------------------------------------------------
P.pos = spot(2, 25)
P.facing = flat(home - P.pos).Unit
pose()
advanceTo(T + 0.5)
dumpStatic()
me:SetAttribute("SpireFloor", 3) -- (in his range: he wakes at his next look round)
while model:GetAttribute("Action") ~= "Wake" do
	advanceTo(T + DT)
end
local wakeAt = model:GetAttribute("ActionStart")
local WAKE_FROM = 1.44 -- the film starts this far into his wake-up (he's just standing up)
advanceTo(wakeAt + WAKE_FROM - DT)

----------------------------------------------------------------------
-- the film
----------------------------------------------------------------------
local drop = def.Attacks.ShovelDrop
local dash = def.Attacks.ChargeDash
local met = def.Attacks.ShovelMeteor
local FILM = {
	drop = 1.45, -- the Shovel Drop: he crouches...
	run = 2.02, -- ...he's off the ground: the player runs for it, the circle chasing them
	dropRoll = 2.86, -- the circle has locked: roll out of it
	dashIn = 3.40, -- he's landed and his shovel's stuck: in to his face
	combo = { { at = 3.55, weight = 1, left = true, share = 0.05 }, { at = 3.81, weight = 2, share = 0.05 },
		{ at = 4.09, weight = 3, share = 0.08 } },
	rollBack = 4.30, -- out of there before he pulls it free
	dash = 4.45, -- (a jump cut) the CHARGE DASH, the player far down his lane
	dashSide = dash.Tell - 0.14, -- (seconds into the dash) roll out of the lane, just before he goes
	dashInAfter = 0.18, -- (seconds after the crash) in to punch the dizzy knight
	combo2 = { 0.42, 0.68, 0.96 }, -- (seconds after the crash) three punches: the last cracks his armour
	fastBreak = 0.455, -- the armour cracking at double speed for this long, until the plates fly off
	meteor = 8.30, -- the SHOVEL METEOR
	sky = 9.20, -- (a jump cut) the shadow, the player racing for its edge
	skyFast = 0.5, -- the long wait in the sky at speed for this long...
	skyFrom = 0.9, skyTo = 3.22, -- (...from this far into the meteor to this far: he's just starting to fall)
	slowRate = 0.35, -- then slow motion as he plunges...
	freezeAt = 3.4167, -- (...until this far into the meteor: the freeze frame - he's falling, fire trailing)
	after = 1.0, -- the ending's seconds after the freeze
}
local DASH_DIR = Vector3.new(1, 0, 0) -- the way he charges: east, along the dig
local RUN_DIR = Vector3.new(1, 0, 0) -- the way the player runs from the drop
local SKY_OUT = Vector3.new(0.35, 0, 0.94).Unit -- the way the player races the meteor's shadow

local dropAt, dashAt, dashGo, crashAt, crashV, breakAt, breakV, meteorAt, meteorV, freezeV = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
local combo2 = nil
local fling = nil -- { t0, from, dir }: thrown back by his armour bursting
local laneFrom, laneTo = nil, nil
local seen = {}
local k = 0
while true do
	k += 1
	local v = (k - 1) * DT
	if freezeV and v > freezeV + FILM.after + 1e-6 then
		break
	end

	------------------------------------------------------------------
	-- the game clock for this frame
	------------------------------------------------------------------
	local want = T + DT
	if breakV and v <= breakV + FILM.fastBreak + 1e-6 then
		want = breakAt + DT + (v - breakV) * 2
	end
	local slowMo = meteorV and v > FILM.sky + FILM.skyFast + 1e-6
	if meteorV and v >= FILM.sky - 1e-6 and not slowMo then
		want = meteorAt + FILM.skyFrom + (v - FILM.sky) * (FILM.skyTo - FILM.skyFrom) / FILM.skyFast
	elseif slowMo then
		want = meteorAt + FILM.skyTo + (v - FILM.sky - FILM.skyFast) * FILM.slowRate
	end

	------------------------------------------------------------------
	-- 1) HE WAKES: the shovel yanked out of the dirt, a twirl, the pose
	-- (the player stands and watches, off camera)
	------------------------------------------------------------------
	once("pose", v, (wakeAt + def.WakeTime * 0.76) - (wakeAt + WAKE_FROM) + DT, function()
		event("pose", v)
	end)

	------------------------------------------------------------------
	-- 2) SHOVEL DROP: he crouches and leaps; the red circle chases the
	-- player across the dirt, flashes and locks - they roll out of it
	------------------------------------------------------------------
	once("drop", v, FILM.drop, function()
		force("ShovelDrop")
		fighting()
		dropAt = model:GetAttribute("ActionStart")
		event("drop", v)
	end)
	if dropAt and not seen.takeoff and T + DT >= dropAt + drop.Tell then
		seen.takeoff = true
		event("takeoff", v)
	end
	if dropAt and not seen.lock and T + DT >= dropAt + drop.Tell + drop.Air * drop.Lock then
		seen.lock = true
		event("lock", v)
	end
	if v >= FILM.run and v < FILM.dropRoll then
		walkTo(P.pos + RUN_DIR * 50, 17)
	end
	once("dropRoll", v, FILM.dropRoll, function()
		startRoll(v, P.pos + RUN_DIR * 11 + Vector3.new(0, 0, 2), 0.38)
	end)
	if dropAt and not seen.land and T + DT >= dropAt + drop.Tell + drop.Air then
		seen.land = true
		-- (the landing spot, where the circle locked)
		local B = model:GetAttribute("ActB")
		event("land", v, M.typeof(B) == "Vector3" and v3(B) or "")
	end
	if seen.land and not rolling and v < FILM.dashIn then
		faceBoss()
		P.legs, P.arms = P.legs * 0.7, P.arms * 0.7
	end

	------------------------------------------------------------------
	-- 3) THE OPENING: his shovel's stuck in the dirt - in to his face and
	-- three punches, then roll back out
	------------------------------------------------------------------
	once("dashIn", v, FILM.dashIn, function()
		approach(v, punchSpotFacing(E.facing), 0.16)
		event("dashin", v)
	end)
	if v >= FILM.dashIn and v < FILM.dash then
		throwPunches(FILM.combo, v)
	end
	once("rollBack", v, FILM.rollBack, function()
		P.punch, P.punchL, P.lean = 0, 0, 0
		startRoll(v, P.pos + flat(P.pos - E.pos).Unit * 11, 0.38)
	end)

	------------------------------------------------------------------
	-- 4) CHARGE DASH (a jump cut: the player is far down his lane, near the
	-- edge of the dig). He scrapes his shovel, the lane locks on, they roll
	-- aside at the last moment - and he runs into the edge: seeing stars
	------------------------------------------------------------------
	once("dash", v, FILM.dash, function()
		rolling = nil
		P.roll, P.punch, P.punchL, P.lean, P.legs, P.arms = nil, 0, 0, 0, 0, 0
		-- far enough that his charge would carry on past the edge: a crash
		local room = toEdge(E.pos, DASH_DIR, def.Leash)
		local d = room - dash.Overshoot + 3
		P.pos = Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + DASH_DIR * d
		P.facing = -DASH_DIR
		force("ChargeDash")
		dashAt = model:GetAttribute("ActionStart")
		event("dash", v, string.format("%.2f %.2f", room, d))
	end)
	if dashAt and not seen.commit and model:GetAttribute("ActA") ~= nil then
		seen.commit = true
		laneFrom, laneTo = model:GetAttribute("ActA"), model:GetAttribute("ActB")
		event("commit", v, v3(laneFrom) .. " " .. v3(laneTo) .. " " .. tostring(model:GetAttribute("ActC") ~= nil))
	end
	if dashAt then
		once("dashSide", v, FILM.dash + FILM.dashSide, function()
			startRoll(v, P.pos + Vector3.new(0, 0, -11), 0.38)
		end)
	end
	if dashAt and not seen.go and T + DT >= dashAt + dash.Tell then
		seen.go = true
		dashGo = v
		event("go", v)
	end
	if dashGo and not rolling and not crashAt and seen.go then
		faceBoss()
	end
	if dashAt and not crashAt and laneTo and T + DT >= dashAt + dash.Tell + (model:GetAttribute("ActN") or 1) then
		crashAt = T + DT
		crashV = v
		event("crash", v, v3(laneTo))
		combo2 = {}
		for i, at in ipairs(FILM.combo2) do
			combo2[i] = { at = v + at, weight = i, left = (i == 1), share = (i == 3) and 0.13 or 0.1 }
		end
	end
	-- dazed, he stumbles round to face the player coming in
	if crashV and not seen.turned and v >= crashV + 0.05 then
		seen.turned = true
		local inward = flat(home - E.pos).Unit
		E.track = false
		E.facing = inward
	end
	if crashV then
		once("dashIn2", v, crashV + FILM.dashInAfter, function()
			approach(v, punchSpotFacing(flat(home - E.pos).Unit), 0.2)
			event("dashin2", v)
		end)
		if not breakAt then
			throwPunches(combo2, v)
		end
	end

	------------------------------------------------------------------
	-- 5) NO QUARTER! The last punch cracks his armour (the real break:
	-- BossService starts it when his health crosses half). His shoulder
	-- plates fly off, gold bursts out of the cracks, the player's thrown back
	------------------------------------------------------------------
	if not breakAt and model:GetAttribute("Action") == "Break" then
		breakAt = model:GetAttribute("ActionStart")
		breakV = v
		event("break", v)
	end
	if breakAt and not seen.plates and T + DT >= breakAt + def.BreakTime * 0.35 then
		seen.plates = true
		P.punch, P.punchL, P.lean = 0, 0, 0
		rolling = nil
		fling = { t0 = v, from = P.pos, dir = flat(P.pos - E.pos).Unit }
		event("plates", v)
	end
	if fling then
		-- (thrown back by the blast: up and away, tumbling - then back on their feet)
		local u = v - fling.t0 + DT
		if u < 0.5 then
			local dist = 16 * (1 - math.exp(-u * 6))
			P.pos = fling.from + fling.dir * dist
			P.jump = math.max(0, 30 * u - 60 * u * u)
			P.roll, P.rollDir = u * 1.6, fling.dir
			P.facing = -fling.dir
			P.legs, P.arms = 0.5, -1.2
		else
			P.pos = fling.from + fling.dir * 16 * (1 - math.exp(-3))
			P.jump, P.roll = 0, nil
			P.legs, P.arms = P.legs * 0.7, P.arms * 0.7
			faceBoss()
		end
	end

	------------------------------------------------------------------
	-- 6) SHOVEL METEOR: a deep crouch, and he rockets up out of sight...
	-- (a jump cut) the huge shadow grows in the middle of the dig, the player
	-- racing for its edge - and he comes down like a meteor (the freeze)
	------------------------------------------------------------------
	once("meteor", v, FILM.meteor, function()
		force("ShovelMeteor") -- (the armour's show is cut short: his brain never restarts)
		fighting()
		meteorAt = model:GetAttribute("ActionStart")
		meteorV = v
		event("meteor", v)
	end)
	if meteorAt and not seen.launch and T + DT >= meteorAt + met.Tell then
		seen.launch = true
		event("launch", v)
	end
	once("sky", v, FILM.sky, function()
		fling = nil
		P.pos = spot(0, 0) + SKY_OUT * 23.5
		P.jump, P.roll, P.lean = 0, nil, 0
		event("sky", v, string.format("%.3f %.3f", SKY_OUT.X, SKY_OUT.Z))
	end)
	once("slow", v, FILM.sky + FILM.skyFast + DT, function()
		event("slow", v)
	end)
	if done.sky and not freezeV then
		-- (running flat out - slowed down in the slow motion, like everything else)
		walkTo(P.pos + SKY_OUT * 50, slowMo and 18 * FILM.slowRate or 18)
	end
	if meteorAt and not freezeV and want >= meteorAt + FILM.freezeAt - 1e-6 then
		want = meteorAt + FILM.freezeAt -- (exactly: the freeze frame)
		freezeV = v
		event("freeze", v)
	end

	stepRoll(v)
	pose()
	advanceTo(want)
	dumpFrame(v)
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
