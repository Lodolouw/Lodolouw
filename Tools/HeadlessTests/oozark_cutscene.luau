--!nocheck
-- A 10-second cutscene of the Oozark fight, for a YouTube Short: the real
-- slime pit (LobbyBuilder), the real BossService with Oozark's moves forced
-- one after another like a scripted scene, the real BossClient drawing him,
-- and a blocky player who walks in, dodges and punches. Every video frame
-- (30 a second) prints what's on screen; render_cutscene.py films it.
--
--   luau oozark_cutscene.luau > cutscene.txt
--   python3 render_cutscene.py cutscene.txt ../../Docs/youtube/oozark_cutscene.mp4
--
-- What it prints: STATIC (every part of the arena near the pit, once, each
-- with an index), then for every frame FRAME, POS (Oozark's middle and the
-- player's), HP (Oozark's health share), and the parts that moved: his body
-- and his effects, the player, and any arena part that changed (by index).
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(1) -- (the boss's shakes and splashes use math.random: the same film every run)

mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
M.run(1)

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
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
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
-- how high the feet are off the floor
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
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(1)
local model = E.model
local home = E.home
cam.CFrame = CFrame.lookAt(home + Vector3.new(0, 20, 90), home) -- (the film's camera is render_cutscene.py's; this one's for BossClient)
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

local T = 0
local DT = 1 / 30
local function tick()
	T += DT
	M.run(T)
	RunService.Heartbeat:Fire(DT)
	RunService.RenderStepped:Fire(DT)
end

-- one of his moves, right now (his own brain stops: this is a scene)
local function force(name)
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.motion, E.sweep, E.arc = nil, nil, nil
	E.chase = false
	M.task.spawn(function()
		E.boss.Attacks[name](E, token)
		if E.token == token then
			model:SetAttribute("Action", "Idle")
		end
	end)
end

-- a punch landing: his health drops (he wobbles and blanches on screen) and
-- the blow jolts him back (what CombatService does for a real punch)
local hits = 0
local function punchLands(weight)
	local max = model:GetAttribute("MaxHealth") or 100
	local dmg = math.floor(max * (weight >= 3 and 0.05 or 0.03))
	model:SetAttribute("Health", math.max(1, (model:GetAttribute("Health") or max) - dmg))
	local onHit = model:FindFirstChild("OnHit")
	if onHit then
		onHit:Fire(me, dmg, false, weight)
	end
	hits += 1
	local away = Vector3.new(E.pos.X - P.pos.X, 0, E.pos.Z - P.pos.Z)
	away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, -1)
	model:SetAttribute("HitFx", string.format("%d:%d:%.3f:%.3f", hits, weight, away.X, away.Z))
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
	return (fx and d:IsDescendantOf(fx)) or d:IsDescendantOf(char)
end
local function dumpStatic()
	realPrint("STATIC")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not isDynamic(d) and (d.Position - home).Magnitude < 260 then
			local pr = rawget(d, "__props")
			statics[#statics + 1] = { d, pr.CFrame, pr.Size, pr.Color, pr.Transparency }
			if (d.Transparency or 0) < 0.98 then
				realPrint(partLine(d, #statics))
			end
		end
	end
	realPrint("ENDSTATIC")
end

local frame = 0
local function dumpFrame()
	frame += 1
	realPrint(string.format("FRAME %d %.4f", frame, (frame - 1) * DT))
	local b = model:GetPivot().Position
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", E.pos.X, b.Y, E.pos.Z, P.pos.X, P.pos.Y, P.pos.Z))
	local hp = (model:GetAttribute("Health") or 1) / math.max(model:GetAttribute("MaxHealth") or 1, 1)
	realPrint(string.format("STATE %s %.4f %s", tostring(model:GetAttribute("State")), hp, tostring(model:GetAttribute("Action"))))
	fx = fx or workspace:FindFirstChild("BossFX")
	for _, r in ipairs({ fx, char }) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 and d ~= root then
				realPrint(partLine(d))
			end
		end
	end
	-- arena parts the boss's screen moved or recoloured (the pool, say)
	for i, s in ipairs(statics) do
		local d = s[1]
		local pr = rawget(d, "__props")
		if pr.CFrame ~= s[2] or pr.Size ~= s[3] or pr.Color ~= s[4] or pr.Transparency ~= s[5] then
			realPrint(partLine(d, i))
		end
	end
	realPrint("ENDFRAME")
end

----------------------------------------------------------------------
-- the scene
----------------------------------------------------------------------
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local floorY = home.Y
local function at(dx, dz)
	return Vector3.new(home.X + dx, floorY + 3, home.Z + dz)
end

-- (before the camera rolls: the player waits well back, the pit asleep)
P.pos = at(0, 80)
P.facing = Vector3.new(0, 0, -1)
pose()
me:SetAttribute("SpireFloor", 1)
for _ = 1, 30 do
	tick()
end
dumpStatic()

local walkPhase = 0
local function walkTo(target, speed, dt)
	local d = flat(target - P.pos)
	local stepLen = math.min(d.Magnitude, speed * dt)
	if stepLen > 0.001 then
		P.pos = P.pos + d.Unit * stepLen
		P.facing = d.Unit
		walkPhase += stepLen * 0.55
		P.legs = math.sin(walkPhase) * 0.65
		P.arms = math.sin(walkPhase) * 0.55
	else
		P.legs, P.arms = P.legs * 0.7, P.arms * 0.7
	end
	return d.Magnitude <= 0.01
end
local function faceBoss()
	local d = flat(E.pos - P.pos)
	if d.Magnitude > 0.01 then
		P.facing = d.Unit
	end
end
local rolling = nil -- { t0, from, to, time, dash }
local function startRoll(to, seconds)
	rolling = { t0 = T, from = P.pos, to = to, time = seconds or 0.35 }
	P.rollDir = flat(to - P.pos).Unit
end
-- a quick dash (or a step): the roll's easing, without the tumble
local function approach(target, seconds)
	rolling = { t0 = T, from = P.pos, to = target, time = seconds, dash = true }
end
local function stepRoll()
	if not rolling then
		return
	end
	local k = math.min(1, (T - rolling.t0) / rolling.time)
	P.pos = rolling.from:Lerp(rolling.to, 1 - (1 - k) * (1 - k))
	P.roll = (k < 1 and not rolling.dash) and k or nil
	if k >= 1 then
		rolling = nil
		P.roll = nil
	end
end
local punches = {} -- { at, weight, landed }

local FRAMES = 300
local startT = T
local done = {}
local function once(key, t, fn)
	if not done[key] and T - startT >= t then
		done[key] = true
		fn()
	end
end
local jumpAt = nil
for _ = 1, FRAMES do
	local t = T - startT
	-- walking up to the pit (it wakes as they cross into its range), then watching it rise
	if t < 2.4 then
		walkTo(at(0, 42), 16, DT)
	elseif not rolling and t < 5.6 then
		P.legs, P.arms = P.legs * 0.8, P.arms * 0.8
		faceBoss()
	end
	-- the roar: they flinch, a step back, arms up
	once("flinch", 3.98, function()
		approach(P.pos + Vector3.new(0, 0, 1.2), 0.18)
	end)
	if t >= 3.98 and t < 4.9 then
		local u = t - 3.98
		P.guard = math.min(1, u / 0.1) * (u < 0.6 and 1 or math.max(0, 1 - (u - 0.6) / 0.3))
	end
	-- he lunges; they roll aside just as he leaves the ground, so he lands where they stood
	once("lunge", 5.0, function()
		force("Lunge")
	end)
	once("dodge1", 5.6, function()
		startRoll(P.pos + Vector3.new(15, 0, 2.5), 0.4)
	end)
	-- he whips round to face them (turned a little toward the camera, which
	-- sits off their right shoulder: his face shows, and the blob of slime at
	-- the front of his base isn't in front of their legs)
	if t >= 6.02 and t < 7.0 then
		local toBoss = flat(E.pos - P.pos).Unit
		local side = toBoss:Cross(Vector3.new(0, 1, 0))
		local want = (-toBoss + side * 0.36).Unit -- (20 degrees round)
		local cur = E.facing
		local angle = math.acos(math.clamp(cur:Dot(want), -1, 1))
		local step = math.rad(320) * DT -- (his turning speed)
		if angle <= step then
			E.facing = want
		else
			local sign = cur:Cross(want).Y >= 0 and 1 or -1
			E.facing = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), sign * step):VectorToWorldSpace(cur)
		end
	end
	-- ...and they dash back in, three punches while he's still recovering
	once("dash", 6.04, function()
		local d = flat(P.pos - E.pos)
		approach(Vector3.new(E.pos.X, P.pos.Y, E.pos.Z) + d.Unit * 12.8, 0.14)
	end)
	once("combo", 6.15, function()
		punches = {
			{ at = 6.2, weight = 1, left = true },
			{ at = 6.48, weight = 2 },
			{ at = 6.78, weight = 3 },
		}
	end)
	for _, pu in ipairs(punches) do
		local since = t - pu.at
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
				punchLands(pu.weight)
				if pu.weight >= 3 then
					-- (the big one steps in behind it)
					P.pos = P.pos + flat(E.pos - P.pos).Unit * 0.6
				end
			end
		end
	end
	-- he rears up and slams; they roll clear of the ring just in time
	once("slam", 7.0, function()
		P.punch, P.punchL, P.lean = 0, 0, 0
		force("Slam")
	end)
	once("dodge2", 7.18, function()
		local away = flat(P.pos - E.pos)
		away = away.Magnitude > 0.01 and away.Unit or Vector3.new(1, 0, 0)
		startRoll(P.pos + away * 14, 0.38)
	end)
	-- and he flattens and sends a wall of slime rolling out at them: they jump it
	once("wave", 8.0, function()
		faceBoss()
		force("Wave")
	end)
	once("jump", 8.8, function()
		jumpAt = t
	end)
	if jumpAt then
		-- (a Roblox jump: 50 studs a second up, the world's gravity down)
		local u = t - jumpAt
		P.jump = math.max(0, 50 * u - 0.5 * 196.2 * u * u)
		local air = P.jump > 0 or u < 0.05
		P.legs = air and 0.5 or P.legs * 0.7
		P.arms = air and -0.9 or P.arms * 0.7
		if not air then
			jumpAt = nil
			P.jump = 0
		end
	end
	stepRoll()
	if t >= 7.7 and not rolling then
		faceBoss()
	end
	pose()
	tick()
	dumpFrame()
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
