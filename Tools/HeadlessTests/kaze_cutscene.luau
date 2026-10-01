--!nocheck
-- A ~14-second LOOP of floor 4 for a YouTube Short, starring KAZE, the
-- Headband Hero: the real Rooftop Dojo (DojoBuilder), the real BossService
-- with his brain stopped and his moves forced like a scripted scene, the real
-- BossClient drawing him (BossBodies/Kaze: his poses, the ball of ki, the
-- Rising Dragon, the cancels' white flash, ROUND 2, the Super's fan and beam,
-- ROUND 1 / ROUND 2 / FIGHT! / SUPER!, his KI METER and cancel diamonds) and
-- a blocky player. Every video frame (30 a second) prints what's on screen,
-- the camera, and what the real screen code put on the player's screen (the
-- big words, the ki meter, the word bubbles, the flashes); the sounds it
-- played too. render_kaze_cutscene.py films it.
--
--   luau kaze_cutscene.luau > kaze.txt
--   python3 render_kaze_cutscene.py kaze.txt ../../Docs/animations/kaze_short.mp4 \
--       --font FredokaOne.ttf --pixel-font PressStart2P.ttf
--
-- The scene (s = seconds from the start of his wake, the game's clock):
--   1.0   ROUND 1 (the film opens here, mid-wake) ... (jump cut)
--   2.95  FIGHT!  ("HAH!", his stance)
--   3.3   KAZE-BLAST!: the ball of ki along the floor - the player rolls
--         straight through it (a roll is untouchable for half a second)
--   4.6   in close: two punches. PUNCH STRING: the jab... the player rolls
--         back out of it - CANCEL! (the white flash, a diamond gone) into a
--         RISING DRAGON! that misses; he lands, open: punches to half health
--   8.35  ROUND 2 (down on one knee, the burst of ki throws the player back,
--         his gi torn) ... (jump cut) ... FIGHT!
--         he's TIRED (TIRED! HIT HIM!): punches down to one hit left (2%)
--   then  KI FLARE: his meter flares to MAX ("HAAA!") - SUPER! HIDE BEHIND A
--         PILLAR! - he leaps to the middle, the red fan locks on the player,
--         who rolls... too early (slow motion): the beam sweeps into them the
--         moment the roll's safe half-second is over. In bits, at 2%.
--   -> the first frame: ROUND 1 again (it loops: the fight starting over).
--
-- Scripted (not how a real fight would go): his brain is stopped and every
-- move is forced; his dice are fixed (the string cancels after the jab, into
-- the Rising Dragon, which then doesn't hop back; the beam sweeps toward the
-- roll); his ki is set before the Kaze-Blast and the string (as if he had
-- built it up); the Tired is forced; the KI FLARE comes at 2% (the game's is
-- at 25% in round 2); his health is set as the player's punches land (bigger
-- chunks than real punches); two jump cuts; slow motion round the beam.
--
-- What it prints: STATIC (every dojo part once, indexed), then per frame
-- FRAME (frame, film time, game time, s), CAM, POS (him, the player), STATE,
-- BAR (his name, health, round), KI (the meter, as BossBodies/Kaze draws it),
-- the moving parts, changed dojo parts, BIG (kit.bigText's words), BB (word
-- bubbles and the hint over his head); and BURST, KICK, SOUND, FLASH, KIPOP
-- and EVENT lines as they happen.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
math.randomseed(4)

local arena = mount.require(mount.module("ServerScriptService/DojoBuilder.lua")).Build()
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

-- the pose (as gridlock_cutscene.luau): pos = the middle of the body,
-- facing, legs / arms swing, guard raises the arms, spread throws them out,
-- lean tips forward round the hips, tumble flips round the middle (a roll),
-- jump lifts, punch / punchL a straight arm, tuck pulls the knees up; `dead`
-- (seconds since the beam got them: every limb flies off on its own, along
-- deathDir)
local P = {}
local function resetPose()
	P.pos, P.facing = P.pos or Vector3.zero, Vector3.new(0, 0, -1)
	P.legs, P.arms, P.guard, P.spread, P.lean, P.tumble, P.jump, P.headYaw, P.roll = 0, 0, 0, 0, 0, 0, 0, 0, 0
	P.punch, P.punchL, P.tuck, P.dead = 0, 0, 0, nil
end
resetPose()
local DEATH = { -- (up, out along the blast, sideways; spin)
	head = { 24, 16, 2, Vector3.new(4, 6, 2) },
	torso = { 12, 20, -1, Vector3.new(-3, 1, 2) },
	larm = { 17, 13, -10, Vector3.new(6, 2, 5) },
	rarm = { 18, 15, 11, Vector3.new(-5, 3, 6) },
	lleg = { 10, 11, -6, Vector3.new(7, 0, 3) },
	rleg = { 11, 12, 7, Vector3.new(-6, 2, 4) },
}
local deathDir = Vector3.new(0, 0, 1)
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
		local t = P.dead
		local side = Vector3.new(-deathDir.Z, 0, deathDir.X)
		for k, p in pairs(body) do
			local d = DEATH[k]
			local base = p.CFrame
			local y = base.Position.Y + d[1] * t - 0.5 * 70 * t * t
			if y < FLOOR_Y + 0.5 then
				y = FLOOR_Y + 0.5
			end
			local slide = math.min(t, 0.9) * 0.6
			local h = (deathDir * d[2] + side * d[3]) * slide
			local w = d[4]
			local spin = math.min(t, 0.75)
			p.CFrame = CFrame.new(base.Position.X + h.X, y, base.Position.Z + h.Z) * (base - base.Position)
				* CFrame.Angles(w.X * spin, w.Y * spin, w.Z * spin)
		end
		headCf = body.head.CFrame
	end
	eyes[1].CFrame = headCf * CFrame.new(-0.25, 0.1, -0.62)
	eyes[2].CFrame = headCf * CFrame.new(0.25, 0.1, -0.62)
end

----------------------------------------------------------------------
-- the boss: the real server and the real screen
----------------------------------------------------------------------
local T0 = 0 -- (the game clock at s = 0: the start of his wake)
local rollUntil = -math.huge -- (the player's roll: untouchable until then, game clock)
local beamHit = nil -- (when the beam really caught them: game clock, and which way it threw them)
local shoveAt = nil
local model, def -- (Kaze's model and Config entry: filled in below)
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
	-- (nobody's really hurt: the scene only notes the moment the Super's
	-- beam - its real sweep, width and the pillars' shadows - catches them
	-- outside their roll)
	DamagePlayer = function(_, damage, from)
		if not beamHit and M.now() >= rollUntil and model and model:GetAttribute("Action") == "Super" then
			local d = root.Position - from
			d = Vector3.new(d.X, 0, d.Z)
			beamHit = { M.now(), d.Magnitude > 0.1 and d.Unit or Vector3.new(0, 0, 1), damage }
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
	for _, name in pairs(cfg.Bosses[4].Sounds) do
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
-- the screen's tweens jump straight to their end here, so the two that are
-- over in a blink are written down as they start: the white flash over the
-- whole screen (Body._flash) and the little +KI / -KI / MAX! by the meter
do
	local TS = M.services.TweenService
	local create = TS.Create
	TS.Create = function(self, inst, info, props)
		local par = inst.Parent
		if par and par.Name == "KazeFlash" and props.BackgroundTransparency == 1 then
			realPrint(string.format("FLASH %.4f %.3f %.3f", M.now(), 1 - (inst.BackgroundTransparency or 1), tonumber(info[1]) or 0.3))
		elseif par and par.Name == "Meter" and props.TextTransparency == 1 and inst:IsA("TextLabel") and inst.Text ~= "" then
			local c = inst.TextColor3
			realPrint(string.format("KIPOP %.4f %s|%d,%d,%d", M.now(), inst.Text, math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)))
		end
		return create(self, inst, info, props)
	end
end

local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(4)
model, def = E.model, E.def
local floorY = E.floorY or E.home.Y
FLOOR_Y = floorY
local H = Vector3.new(E.home.X, floorY, E.home.Z) -- (the middle of the dojo: Kaze's mat)
-- his brain stopped (only for this scene): BossService starts it after the
-- wake and after ROUND 2; here it does nothing, and the scene says what he does
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

-- BossService's setAction (the same attributes, in the same order)
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

-- his dice: fixed by the scene (NextNumber answers RNG)
local RNG = 0
E.rng = { NextNumber = function() return RNG end, NextInteger = function(_, lo) return lo end }

-- whatever he was doing stopped: his stance, facing the player
local function takeOver(action)
	E.token += 1
	E.motion, E.arc = nil, nil
	E.charging, E.focusing, E.guardBroken, E.chaining, E.supering = false, false, false, false, false
	E.track, E.chase = true, false
	E.target, E.targetSince = me, M.now()
	if action then
		setAction(action, nil)
	end
	return E.token
end
local function force(name, opts)
	takeOver(nil)
	local token = E.token
	M.task.spawn(function()
		E.boss.Attacks[name](E, token, opts or {})
	end)
end
local function setKi(v)
	E.ki = v
	E.kiShown = nil
	model:SetAttribute("Ki", math.floor(v + 0.5))
	E.kiShown = math.floor(v + 0.5)
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
		if d:IsA("BasePart") and not isDynamic(d) and (d.Position - H).Magnitude < 700 then
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
	-- his KI METER (BossBodies/Kaze's KazeKi): each bar's fill and colours,
	-- MAX, and the cancel diamonds
	local ki = gui:FindFirstChild("KazeKi")
	if ki and ki.Enabled then
		local holder = ki:FindFirstChild("Meter")
		local bars = {}
		for i = 1, 3 do
			local back = holder:FindFirstChild("Bar" .. i)
			local fill = back:FindFirstChild("Fill")
			local stroke = back:FindFirstChildOfClass("UIStroke")
			bars[i] = string.format("%.3f;%s;%s", fill.Size.X.Scale, rgb(fill.BackgroundColor3), rgb(stroke.Color))
		end
		local maxOn = 0
		for _, d in ipairs(holder:GetChildren()) do
			if d:IsA("TextLabel") and d.Text == "MAX" and d.Visible then
				maxOn = 1
			end
		end
		local ds = {}
		for i = 1, 5 do
			local d = holder:FindFirstChild("Cancel" .. i)
			ds[i] = (d and d.Visible) and rgb(d.BackgroundColor3) or "-"
		end
		realPrint(string.format("KI %s|%d|%s", table.concat(bars, " "), maxOn, table.concat(ds, " ")))
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
local camEye, camLook, camFov = H, H, 70
local function bossAt()
	return model:GetPivot().Position
end
local function dumpFrame(v, s)
	frame += 1
	realPrint(string.format("FRAME %d %.4f %.4f %.4f", frame, v, M.now(), s))
	realPrint(string.format("CAM %s %s %.2f", v3(camEye), v3(camLook), camFov))
	local b = bossAt()
	realPrint(string.format("POS %.3f %.3f %.3f %.3f %.3f %.3f", b.X, b.Y, b.Z, P.pos.X, P.pos.Y + P.jump, P.pos.Z))
	realPrint(string.format("STATE %s %.4f %s %d", tostring(model:GetAttribute("State")), (model:GetAttribute("Health") or 1)
		/ math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), math.floor(E.ki or 0)))
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
local function spot(x, z, up)
	return Vector3.new(H.X + x, floorY + 3 + (up or 0), H.Z + z)
end
local function ease(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function flatUnit(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.05 and f.Unit or (fallback or Vector3.new(0, 0, -1))
end
local NORTH = Vector3.new(0, 0, -1)
local ROLL_TIME, ROLL_SPEED = 0.28, 62 -- (Config.Combat: RollTime, RollSpeed; untouchable for 0.5 s)
local ROLL_SAFE = 0.5

local FILM_FROM = 1.02 -- the first frame: ROUND 1 just up
local BLAST = 3.42 -- KAZE-BLAST! (right after the wake: no charge, lets go 0.6 s later)
local START = spot(0.5, 26) -- where the player stands for ROUND 1
local ROLL1 = BLAST + 0.85 -- the roll through the ball
local ROLL1_END = START + NORTH * (ROLL_SPEED * ROLL_TIME)
local CLOSE = spot(1.2, 9.6) -- in close, punching
local STRING = BLAST + 1.65 -- PUNCH STRING (the jab lands at + Tells[1])
local JAB = STRING + A.PunchString.Tells[1]
local ROLL2 = JAB + 0.03 -- the roll back out under the jab (still close as it lands: he cancels into the Rising Dragon)
local BACK_DIR = Vector3.new(0.45, 0, 1).Unit
local DRAGON_LAND = JAB + A.RisingDragon.Tell + A.RisingDragon.Air[1]
local BREAK = DRAGON_LAND + 1.2 -- ROUND 2 (his health under half)
local TIRED = BREAK + def.BreakTime + 0.05
local FLARE = TIRED + 1.5 -- KI FLARE: MAX!
local SUPER = FLARE + 0.5 -- SUPER!
local LOCK = SUPER + A.Super.Tell * A.Super.Lock
local FIRE = SUPER + A.Super.Tell
local ROLL3 = FIRE - 0.36 -- the roll that's too early
local AFTER = 0.85 -- how long the film runs on after the beam catches them
-- the jump cuts (s from, s to)
local CUTS = { { FILM_FROM + 0.72, 2.82 }, { BREAK + 1.95, BREAK + 2.5 } }
-- the slow motion: from the roll to just after the beam catches them
local SLOW_FROM, SLOW_RATE = ROLL3 + 0.15, 0.33

-- the punches: { s, % of him gone }
local PUNCHES = {
	{ BLAST + 1.32, 3 }, { BLAST + 1.54, 6 },
	{ DRAGON_LAND + 0.25, 15 }, { DRAGON_LAND + 0.45, 24 }, { DRAGON_LAND + 0.65, 33 }, { DRAGON_LAND + 0.85, 42 },
	{ DRAGON_LAND + 1.07, 51 },
	{ TIRED + 0.18, 58 }, { TIRED + 0.40, 67 }, { TIRED + 0.62, 76 }, { TIRED + 0.84, 85 }, { TIRED + 1.06, 93 }, { TIRED + 1.30, 98 },
}

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
local function rolling(s, s0, from, dir, back)
	local u = math.clamp((s - s0) / ROLL_TIME, 0, 1)
	P.pos = from + dir * (ROLL_SPEED * ROLL_TIME) * u
	P.facing = back and -dir or dir
	P.tumble = (back and -1 or 1) * 2 * math.pi * ease(u)
	P.tuck = math.sin(math.pi * u) * 1.1
	P.guard = 0.8
	P.jump = -0.9 * math.sin(math.pi * u)
end
local function towardBoss(from)
	return flatUnit(bossAt() - from, NORTH)
end

local runFrom3, rollFrom3, rollDir3 = nil, nil, nil
local shovedFrom, punishSpot, hitSpot = nil, nil, nil
local function placePlayer(s)
	resetPose()
	if s < ROLL1 then
		-- 1) ROUND 1... FIGHT!: their guard up; then the ball coming
		P.pos, P.facing = START, NORTH
		P.guard, P.spread = 0.6, 0.25
		P.legs = 0.08 * math.sin(s * 6)
		P.jump = 0.1 * math.abs(math.sin(s * 5))
		if s > BLAST + 0.4 then
			P.guard, P.spread = 0.85, 0.4
		end
		return
	end
	if s < ROLL1 + ROLL_TIME + 0.08 then
		rolling(s, ROLL1, START, NORTH, false)
		return
	end
	if s < STRING + 0.2 then
		-- 2) up, in close, two punches
		local k = ease((s - ROLL1 - ROLL_TIME - 0.08) / 0.3)
		P.pos = ROLL1_END:Lerp(CLOSE, k)
		P.facing = towardBoss(P.pos)
		if k < 1 then
			run(s * 22, 1 - k * 0.5)
		end
		P.guard = 0.6
		punchAt(s)
		return
	end
	if s < ROLL2 then
		P.pos, P.facing = CLOSE, towardBoss(CLOSE)
		P.guard, P.lean = 0.75, 0.1
		return
	end
	local backEnd = CLOSE + BACK_DIR * (ROLL_SPEED * ROLL_TIME)
	if s < ROLL2 + ROLL_TIME + 0.05 then
		rolling(s, ROLL2, CLOSE, BACK_DIR, true)
		return
	end
	local runIn = DRAGON_LAND - 0.25
	if s < runIn then
		-- 3) out of the Rising Dragon's ring, watching him go up
		P.pos, P.facing = backEnd, towardBoss(backEnd)
		P.guard, P.spread = 0.9, 0.45
		P.headYaw = 0
		P.lean = -0.15
		return
	end
	if not punishSpot then
		-- (where he'll land: the Rising Dragon's slot 2 - they run in to punish it)
		local land = (E.motion and E.motion.to) or E.pos
		local d = flatUnit(backEnd - land, Vector3.new(0, 0, 1))
		punishSpot = Vector3.new(land.X, floorY + 3, land.Z) + d * 7.4
	end
	local PUNISH = punishSpot
	if s < BREAK then
		local k = ease((s - runIn) / 0.42)
		P.pos = backEnd:Lerp(PUNISH, k)
		P.facing = towardBoss(P.pos)
		if k < 1 then
			run(s * 22, 1)
		else
			P.guard, P.lean = 0.6, 0.12
		end
		punchAt(s)
		return
	end
	if s < TIRED - 0.6 then
		-- 4) ROUND 2: the burst of ki throws them back
		local from = PUNISH
		P.facing = towardBoss(from)
		local sh = shoveAt and (shoveAt - T0) or (BREAK + def.BreakTime * 0.35)
		if s < sh then
			P.pos = from
			P.guard = 0.7
			return
		end
		local u = s - sh
		local away = flatUnit(from - E.pos, Vector3.new(0, 0, 1))
		local k = 1 - math.exp(-u * 7)
		P.pos = from + away * 11 * k
		P.jump = math.max(0, 9 * u - 0.5 * 60 * u * u)
		P.lean = -0.5 * math.exp(-u * 3)
		P.spread, P.guard = 0.9 * math.exp(-u * 2), 0.5
		shovedFrom = from + away * 11
		return
	end
	local from = shovedFrom or spot(1.5, 24)
	if not hitSpot then
		local d = flatUnit(from - E.pos, Vector3.new(0, 0, 1))
		hitSpot = Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + d * 7.2
	end
	local HIT = hitSpot
	if s < FLARE then
		-- 5) he's TIRED: in, and every punch
		local k = ease((s - (TIRED - 0.6)) / 0.6)
		P.pos = from:Lerp(HIT, k)
		P.facing = towardBoss(P.pos)
		if k < 1 then
			run(s * 22, 1)
		else
			P.guard, P.lean = 0.6, 0.14
			P.jump = 0.12 * math.abs(math.sin(s * 9))
		end
		punchAt(s)
		return
	end
	-- 6) KI FLARE: a hop back - SUPER!: a run for the pillar, a roll... too early
	local flee = Vector3.new(0.55, 0, 0.83).Unit -- (toward the south-east pillar)
	if s < SUPER + 0.25 then
		local u = s - FLARE
		P.pos = HIT + flee * 3 * ease(u / 0.35)
		P.jump = math.max(0, 7 * u - 0.5 * 50 * u * u)
		P.facing = towardBoss(HIT)
		P.guard, P.spread = 1, 0.7
		return
	end
	runFrom3 = runFrom3 or (HIT + flee * 3)
	if s < ROLL3 then
		local k = math.clamp((s - SUPER - 0.25) / (ROLL3 - SUPER - 0.25), 0, 1)
		P.pos = runFrom3 + flee * 11 * k
		P.facing = flee
		run(s * 22, 1)
		P.headYaw = 0.8 -- (looking back at him)
		return
	end
	if not rollFrom3 then
		rollFrom3 = runFrom3 + flee * 11
		-- (sideways across the fan: toward where the beam starts its sweep)
		local out = flatUnit(rollFrom3 - H)
		local sign = model:GetAttribute("ActN") or 1
		local across = Vector3.new(out.Z, 0, -out.X) * (-sign)
		rollDir3 = across
	end
	if not beamHit or s < beamHit[1] - T0 then
		if s < ROLL3 + ROLL_TIME + 0.05 then
			rolling(s, ROLL3, rollFrom3, rollDir3, false)
		else
			-- up again: safe... (looking up at the beam)
			P.pos = rollFrom3 + rollDir3 * (ROLL_SPEED * ROLL_TIME)
			P.facing = towardBoss(P.pos)
			P.guard, P.spread = 0.3, 0.8
			P.jump = 0.4 * math.abs(math.sin((s - ROLL3) * 7))
			P.arms = 0.6 * math.sin((s - ROLL3) * 14)
		end
		return
	end
	-- caught: in bits
	P.pos = rollFrom3 + rollDir3 * (ROLL_SPEED * ROLL_TIME)
	P.facing = towardBoss(P.pos)
	P.guard, P.spread = 1, 1
	deathDir = beamHit[2]
	P.dead = s - (beamHit[1] - T0)
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
	if s < BLAST then
		-- ROUND 1... FIGHT!: low behind the player, pushing in on him
		local k = ease((s - 2.82) / 0.9)
		local e, l, f = overShoulder(15 - 3 * k, 5, 5, 54, 0.8, 8)
		return e, l, f
	end
	if s < STRING + 0.1 then
		-- the ball rolling at us; the roll through it
		local e, l, f = overShoulder(12, 5, 4.5, 62, 0.72, 7)
		return e, l, f
	end
	if s < BREAK then
		-- the string, the cancel, the Rising Dragon: further back, him high
		local b = bossAt()
		local air = math.max(0, b.Y - (floorY + 5))
		local e, l, f = hold("dragon", function()
			local base = spot(1.2, 9.6)
			local d = flatUnit(base - H, Vector3.new(0, 0, 1))
			local r = Vector3.new(-d.Z, 0, d.X)
			return base + d * 33 - r * 8 + Vector3.new(0, 3, 0), H + Vector3.new(1.5, 12, 6), 72
		end)
		return e, l + Vector3.new(0, air * 0.9, 0), f
	end
	if s < TIRED - 0.6 then
		-- ROUND 2: on him, a little closer as it goes
		local b = bossAt()
		local d = flatUnit(Vector3.new(0.35, 0, 1))
		local r = Vector3.new(-d.Z, 0, d.X)
		local k = ease((s - BREAK) / 2.5)
		return b + d * (31 - 4 * k) + r * 5 + Vector3.new(0, 7.5, 0), b + Vector3.new(0, 8, 0), 62
	end
	if s < FLARE then
		local e, l, f = overShoulder(15, 6, 6, 62, 0.75, 8.5)
		return e, l, f
	end
	if s < ROLL3 or not rollFrom3 then
		-- MAX! - SUPER!: wide behind the player, him leaping to the middle
		local k = ease((s - FLARE) / (ROLL3 - FLARE))
		local p = P.pos
		local d = flatUnit(p - H, Vector3.new(0, 0, 1))
		local r = Vector3.new(-d.Z, 0, d.X)
		local eye = p + d * (14 + 6 * k) + r * (4 + 2 * k) + Vector3.new(0, 7 + 5 * k, 0)
		return eye, p:Lerp(H + Vector3.new(0, 13, 0), 0.62), 64
	end
	-- the beam: high behind where the player rolls to (high enough that the
	-- beam sweeps under the camera, not through it), the beam sweeping in
	local e, l, f = hold("beam", function()
		local to = rollFrom3 + rollDir3 * (ROLL_SPEED * ROLL_TIME)
		local d = flatUnit(to - H, Vector3.new(0, 0, 1))
		return to + d * 22 + Vector3.new(0, 13, 0), to:Lerp(H + Vector3.new(0, 15, 0), 0.38), 70
	end)
	return e, l, f
end

----------------------------------------------------------------------
-- before the camera rolls: the player walks up, he wakes
----------------------------------------------------------------------
P.pos, P.facing = START, NORTH
pose()
advanceTo(T + 0.5)
dumpStatic()
cam.CFrame = CFrame.lookAt(START + Vector3.new(4, 4, 12), H + Vector3.new(0, 5, 0))
me:SetAttribute("SpireFloor", 4)
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
	if not done[name] and ss >= when - 1e-6 then
		done[name] = true
		advanceTo(T0 + when)
		fn()
	end
end
for _, pu in ipairs(PUNCHES) do
	event("punch", pu[1], string.format("%d", pu[2]))
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
	once("ki0", BLAST - 0.05, ss, function()
		setKi(135) -- (as if he'd built a bar and a bit)
	end)
	once("blast", BLAST, ss, function()
		RNG = 0.99
		force("KazeBlast", {})
		event("blast", v, "")
	end)
	once("roll1", ROLL1, ss, function()
		rollUntil = M.now() + ROLL_SAFE
		event("roll", v, "1")
	end)
	once("ki1", STRING - 0.05, ss, function()
		setKi(math.max(E.ki or 0, 118))
	end)
	once("string", STRING, ss, function()
		RNG = 0 -- (so the string cancels after the jab, into the Rising Dragon)
		force("PunchString", {})
		event("string", v, "")
	end)
	once("roll2", ROLL2, ss, function()
		rollUntil = M.now() + ROLL_SAFE
		event("roll", v, "2")
	end)
	once("nohop", JAB + 0.1, ss, function()
		RNG = 0.99 -- (and doesn't hop back out of it)
	end)
	once("break", BREAK, ss, function()
		model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
		model:FindFirstChild("OnHit"):Fire(me, 1, false)
		event("break", v, "")
	end)
	once("tired", TIRED, ss, function()
		local token = takeOver(nil)
		E.cancels = 0
		M.task.spawn(function()
			E.boss._tired(E, token)
		end)
		event("tired", v, "")
	end)
	once("flare", FLARE, ss, function()
		takeOver("Idle")
		setKi(def.Ki.Bar * def.Ki.Bars)
		model:SetAttribute("KiFlareAt", M.now())
		event("flare", v, "")
	end)
	once("super", SUPER, ss, function()
		RNG = 0.99 -- (the beam sweeps one way: +1)
		force("Super", {})
		event("super", v, "")
	end)
	once("roll3", ROLL3, ss, function()
		rollUntil = M.now() + ROLL_SAFE
		event("roll", v, "3")
	end)
	for i, pu in ipairs(PUNCHES) do
		once("punch" .. i, pu[1], ss, function()
			setPct(pu[2])
			local hitAt = P.pos + P.facing * 2.4 + Vector3.new(0, 0.6, 0)
			event("hit", v, string.format("%d %s", pu[2], v3(hitAt)))
		end)
	end
	stepTo(ss)
	if beamHit and not done.caught then
		done.caught = true
		event("caught", v, string.format("%.4f %s", beamHit[1] - T0, v3(P.pos)))
		slowTo = beamHit[1] - T0 + 0.22
		stopAt = beamHit[1] - T0 + AFTER
	end
	dumpFrame(v, ss)
	-- the next frame's s
	local step = DT
	if ss >= SLOW_FROM - 1e-6 and (not slowTo or ss < slowTo) then
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
		realPrint("ERROR the beam never caught them")
		break
	end
	ss = nxt
	v += DT
end
event("loop", 0, string.format("%d %.4f %.4f %.4f", k, slowFrom or 0, slowTo or 0, SLOW_RATE))
event("times", 0, string.format("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", FILM_FROM, BLAST, STRING, BREAK, TIRED, FLARE, SUPER, FIRE))
event("stage", 0, v3(H))
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
