--[[
	Kaze  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Kaze")

	How Kaze, the Headband Hero (floor 4's boss, Config.Bosses[4]) looks on
	your screen: a chunky 8-bit martial artist a bit over twice your height -
	a white gi with torn-off sleeves, a black belt whose tails flap about, bare
	arms, red gloves, spiky dark hair and his red HEADBAND, its two long tails
	streaming in the mountain wind (they really blow about: every move swings
	them). When he gathers ki his fists and eyes glow blue.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Kaze.lua, where each move is explained):
	  * Poses[move]   his body t seconds into a move: his fighting stance with
	                  its bounce, jab-straight-heavy, the Kaze-Blast's cupped
	                  hands, the spinning Rising Dragon and Tornado Kick,
	                  meditating, panting, the Super's beam...
	  * Starts[move]  the move's sounds, shouts ("KAZE-BLAST!"), bursts, camera
	                  kicks and its warnings on the floor, on the server's clock
	  * SlotSpawns    the spots the server fills in as a move goes: the ball of
	                  ki rolling along its lane, the tornado's lane locking, the
	                  Super's fan locking
	  * the moments every boss has: meditating asleep, waking ("ROUND 1...
	    FIGHT!"), a gust of wind when everyone leaves, ROUND 2 (down on one
	    knee, a burst of ki, his gi torn, the headband re-tied), and K.O.: he
	    falls, his headband drifts away on the wind, and he scatters into
	    cherry blossom petals
	  * his KI METER under the boss bar (three bars, MAX when full, his
	    cancels as diamonds), a hint over his head when he's open ("TIRED!
	    HIT HIM!"), the white flash of every cancel, the pillars crumbling

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: stance (his fighting stance), crouch,
	sit (meditating), kneel, lie (on his back), twist, roll, headPitch, spin
	(extra turning: the spins), bob, rHand / lHand (where his fists go, in his
	chest's space: x = his right, y = up from his hips, z = BACKWARD - so -z
	is in front of him), rFoot / lFoot (where his feet go, the same way but
	from the floor under him), glow (ki in his fists and eyes), ball (the ball
	of ki between his hands), stars (dizzy), sweat, open (his mouth).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}
-- (which arena copy is this boss's: ReplicatedStorage/Arenas)
local Arenas = require(game:GetService("ReplicatedStorage"):WaitForChild("Arenas"))

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, spring, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, findSound, soundGroup, addTelegraph, shockRing, at, SLOT_NAMES, tween, myRoot
local bigText, shout
local underBar = function() end -- (BossClient's kit.underBar)

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local YELLOW = RGB(254, 231, 97)
local CYAN = RGB(44, 232, 245)
local BLUE = RGB(0, 153, 219)
local PINK = RGB(246, 117, 122)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local WOOD = RGB(194, 133, 105)
local PALE = RGB(192, 203, 220)
local PIXEL_FONT = nil

function Body.init(kit)
	serverNow, clamp, lerp, smooth = kit.serverNow, kit.clamp, kit.lerp, kit.smooth
	spring, flat = kit.spring, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, findSound, soundGroup = kit.kick, kit.playSound, kit.findSound, kit.soundGroup
	addTelegraph, shockRing, at, SLOT_NAMES, tween, myRoot = kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES, kit.tween, kit.myRoot
	bigText, shout = kit.bigText, kit.shout
	underBar = function(frame)
		if kit.underBar then
			kit.underBar(frame)
		end
	end
	pcall(function()
		PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	-- WARM-UP: his sounds and music loaded in the background as soon as you
	-- join, so none of them stalls or plays silent the first time
	task.delay(2.5, function()
		pcall(function()
			local def = nil
			for _, d in pairs(require(game:GetService("ReplicatedStorage"):WaitForChild("Config")).Bosses or {}) do
				if d.Short == "Kaze" then
					def = d
				end
			end
			local list = {}
			for _, name in pairs(def and def.Sounds or {}) do
				local sound = findSound(name)
				if sound then
					table.insert(list, sound)
				end
			end
			local music = def and def.Music and findSound(def.Music)
			if music then
				table.insert(list, music)
			end
			if #list > 0 then
				game:GetService("ContentProvider"):PreloadAsync(list)
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- The same jump sum as the server's (Bosses/Kaze.lua), so he's drawn exactly
-- where he is: up fast for `rise` of the `air` seconds, held for `hang`, then
-- down faster and faster.
local function jumpHeight(e, air, rise, height, hang)
	hang = hang or 0
	if e <= 0 then
		return 0
	end
	local up = air * rise
	if e < up then
		local u = e / up
		return height * (1 - (1 - u) * (1 - u))
	end
	if e < up + hang then
		return height
	end
	local v = math.min((e - up - hang) / math.max(air - up, 1e-3), 1)
	return height * (1 - v * v)
end

local function slot(B, i)
	local v = B.model:GetAttribute(SLOT_NAMES[i])
	return typeof(v) == "Vector3" and v or nil
end

local function actN(B)
	local v = B.model:GetAttribute("ActN")
	return type(v) == "number" and v or 0
end

-- `dir` turned round the up axis by `a` radians
local function turnY(dir, a)
	local c, s = math.cos(a), math.sin(a)
	return V3(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

-- a pair { not charged, fully charged } at charge `k`
local function byCharge(v, k)
	if type(v) == "table" then
		return v[1] + (v[2] - v[1]) * k
	end
	return v
end

-- how charged a special is (0-1), from how long he held it (the server's sum)
local function chargeLevel(B, hold)
	return clamp((hold or 0) / B.def.Charge.Time[2], 0, 1)
end

-- a block stretched from a to b (world points), `w` wide and `d` deep;
-- `upHint` says which way its width faces
local function stretch(p, a, b, w, d, upHint)
	local dir = b - a
	local len = dir.Magnitude
	local center = (a + b) / 2
	if len < 1e-3 then
		p.Size = V3(w, d, 0.05)
		p.CFrame = CFrame.new(center)
		return
	end
	p.Size = V3(w, d, len)
	local up = upHint or V3(0, 1, 0)
	if math.abs(dir.Unit:Dot(up.Unit)) > 0.98 then
		up = V3(1, 0, 0) -- (nearly along the hint: any other side will do)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- where the knee (or elbow) goes for a limb from `a` to `c` made of two
-- pieces `l1` and `l2` long, bending toward `bendDir`. Returns the joint and
-- the (possibly pulled-in) far end.
local function twoBone(a, c, l1, l2, bendDir)
	local off = c - a
	local d = off.Magnitude
	local reach = l1 + l2 - 0.01
	if d > reach then
		c = a + off.Unit * reach
		off = c - a
		d = reach
	end
	if d < 1e-3 then
		return a + bendDir * l1, c
	end
	local dir = off / d
	local perp = bendDir - dir * bendDir:Dot(dir)
	perp = unitOr(perp, V3(0, 0, -1))
	local along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local out = math.sqrt(math.max(l1 * l1 - along * along, 0))
	return a + dir * along + perp * out, c
end

local function smoothTo(B, key, want, rate, dt)
	local old = B[key]
	if old == nil then
		B[key] = want
		return want
	end
	local k = 1 - math.exp(-dt * rate)
	local v
	if typeof(want) == "Vector3" then
		v = old:Lerp(want, k)
	else
		v = old + (want - old) * k
	end
	B[key] = v
	return v
end

-- the way the mountain wind blows (the floor's ambience, from Config)
local windCache = nil
local function windDir()
	if windCache then
		return windCache
	end
	windCache = V3(1, 0, 0.3).Unit
	pcall(function()
		local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
		for _, f in ipairs(Config.Spire.Floors) do
			local w = f.id == 4 and f.ambience and f.ambience.Wind
			if typeof(w) == "Vector3" and w.Magnitude > 0.01 then
				windCache = V3(w.X, 0, w.Z).Unit
			end
		end
	end)
	return windCache
end

-- the dojo's four pillars on your screen: where they are, and whether the
-- beam has smashed them (looked for again now and then: the arena may not
-- have loaded in yet)
local CollectionService = game:GetService("CollectionService")
local function pillarsOf(B)
	local list = B.pillars
	if list and #list > 0 then
		local whole = true
		for _, pl in ipairs(list) do
			if not pl.model.Parent then
				whole = false
			end
		end
		if whole then
			return list -- (found: the same four for the rest of the fight)
		end
	end
	if os.clock() < (B.pillarsLook or -math.huge) + 2 then
		return list or {}
	end
	B.pillarsLook = os.clock()
	list = {}
	for _, pm in ipairs(CollectionService:GetTagged("DojoPillar")) do
		if pm:GetAttribute("Floor") == B.floor and Arenas.inside(Arenas.arenaFor(B.model), pm) then -- (his own arena copy's)
			local core = pm:FindFirstChild("PillarCore") or pm.PrimaryPart
			if core then
				table.insert(list, { model = pm, core = core, center = V3(core.Position.X, B.vpos.Y, core.Position.Z), radius = pm:GetAttribute("Radius") or 3.5 })
			end
		end
	end
	B.pillars = list
	return list
end

-- how far along a line from `from` (flat, unit `dir`) until it meets a
-- standing pillar (or `len` if it meets none), and that pillar
local function firstPillar(B, from, dir, len)
	local best, bestAt = nil, len
	for _, pl in ipairs(pillarsOf(B)) do
		if not pl.model:GetAttribute("Broken") then
			local rel = flat(pl.center - from)
			local along = rel:Dot(dir)
			if along > 0 then
				local side = (rel - dir * along).Magnitude
				if side < pl.radius then
					local edge = along - math.sqrt(pl.radius * pl.radius - side * side)
					if edge < bestAt then
						best, bestAt = pl, math.max(0, edge)
					end
				end
			end
		end
	end
	return bestAt, best
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {} }
	local gi, deep = def.Color or WHITE, def.DeepColor or PALE
	local skin = def.SkinColor or RGB(232, 183, 150)
	local hair = def.HairColor or RGB(62, 39, 49)
	local band = def.BandColor or RED
	local belt = def.CoreColor or INK
	-- every part remembers its own colour (for the flashes)
	local function add(name, color, material)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, { part = p, color = p.Color, material = p.Material })
		return p
	end
	-- legs: wide gi trousers, ankle wraps, bare feet
	body.thighs, body.shins, body.wraps, body.feet = {}, {}, {}, {}
	for i = 1, 2 do
		body.thighs[i] = add("Thigh", gi)
		body.shins[i] = add("Shin", gi)
		body.wraps[i] = add("AnkleWrap", deep)
		body.feet[i] = add("Foot", skin)
	end
	-- the middle: the belt and its knot (its tails are chains, below)
	body.belt = add("Belt", belt)
	body.knot = add("BeltKnot", belt)
	-- the gi jacket: its shaded side, its lapels crossing, the chest showing
	body.chest = add("Gi", gi)
	body.giShade = add("GiShade", deep)
	body.lapels = { add("Lapel", deep), add("Lapel", deep) }
	body.chestSkin = add("ChestSkin", skin)
	body.sleeves = { add("Sleeve", gi), add("Sleeve", gi) }
	body.torn = add("TornGi", deep) -- (round 2: the right sleeve's torn away)
	-- arms: bare, white wrist wraps, red gloves
	body.upperArms, body.forearms, body.wristWraps, body.gloves = {}, {}, {}, {}
	for i = 1, 2 do
		body.upperArms[i] = add("UpperArm", skin)
		body.forearms[i] = add("Forearm", skin)
		body.wristWraps[i] = add("WristWrap", gi)
		body.gloves[i] = add("Glove", band)
	end
	-- the head: spiky hair, stern eyebrows, eyes, a mouth, the headband
	body.head = add("Head", skin)
	body.hair = add("Hair", hair)
	body.spikes = {}
	for i = 1, 5 do
		body.spikes[i] = add("HairSpike", hair)
	end
	body.brows = { add("Brow", belt), add("Brow", belt) }
	body.eyes = { add("Eye", INK), add("Eye", INK) }
	body.mouth = add("Mouth", INK)
	body.band = add("Headband", band)
	body.bandKnot = add("BandKnot", band)
	-- the tails: the headband's two (long) and the belt's two (short)
	body.bandTails = { {}, {} }
	body.beltTails = { {}, {} }
	for i = 1, 2 do
		for k = 1, 5 do
			body.bandTails[i][k] = add("BandTail", band)
		end
		for k = 1, 3 do
			body.beltTails[i][k] = add("BeltTail", belt)
		end
	end
	-- ki: glowing fists, the ball of ki between his hands
	body.fistGlow = { add("FistGlow", CYAN, Enum.Material.Neon), add("FistGlow", CYAN, Enum.Material.Neon) }
	body.ball = add("KiBall", CYAN, Enum.Material.Neon)
	body.ballCore = add("KiBallCore", WHITE, Enum.Material.Neon)
	-- dizzy stars and sweat drops
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon)
	end
	body.sweat = {}
	for i = 1, 3 do
		body.sweat[i] = add("Sweat", CYAN)
	end
	-- his shadow on the floor
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0, folder)
	-- his ki aura: blue flames rising off him (charging, meditating, a full
	-- meter, round 2)
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "KiAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(CYAN, BLUE)
	aura.LightEmission = 1
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	aura.Lifetime = NumberRange.new(0.5, 0.9)
	aura.Speed = NumberRange.new(4, 9)
	aura.Acceleration = V3(0, 14, 0)
	aura.SpreadAngle = Vector2.new(40, 40)
	aura.Shape = Enum.ParticleEmitterShape.Box
	aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	aura.Rate = 0
	aura.Parent = body.chest
	body.aura = aura
	-- which parts decide for themselves whether they show (see applyPose)
	body.selfShown = {}
	for _, name in ipairs({ "FistGlow", "KiBall", "KiBallCore", "DizzyStar", "Sweat", "TornGi", "Sleeve", "Headband", "BandKnot", "BandTail" }) do
		body.selfShown[name] = true
	end
	-- each part vanishes at its own moment when he scatters into petals
	body.popAt = {}
	for i, rec in ipairs(body.all) do
		body.popAt[rec.part] = ((i * 37) % 23) / 23
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- The tails: little chains that swing and stream in the wind
----------------------------------------------------------------------
-- A chain of points hanging from `anchor` (the first point), each `seg`
-- apart, pushed by gravity and the wind and dragged by how the anchor moves.
local function stepChain(ch, anchor, dt, seg, push, floorY, back)
	local n = ch.n
	if not ch.p or (ch.p[1] - anchor).Magnitude > 12 then
		ch.p, ch.q = {}, {}
		for i = 1, n do
			local p = anchor + back * seg * (i - 1)
			ch.p[i], ch.q[i] = p, p
		end
	end
	dt = math.min(dt, 1 / 30)
	ch.p[1], ch.q[1] = anchor, anchor
	for i = 2, n do
		local p, q = ch.p[i], ch.q[i]
		local vel = (p - q) * 0.9
		ch.q[i] = p
		ch.p[i] = p + vel + push * dt * dt
	end
	for _ = 1, 3 do
		for i = 2, n do
			local a, b = ch.p[i - 1], ch.p[i]
			local d = b - a
			local len = d.Magnitude
			if len > 1e-4 then
				b = a + d * (seg / len)
			else
				b = a + back * seg
			end
			if b.Y < floorY + 0.15 then
				b = V3(b.X, floorY + 0.15, b.Z)
			end
			ch.p[i] = b
		end
	end
end

local function drawChain(parts, ch, w, d, up)
	for i, p in ipairs(parts) do
		local a, b = ch.p[i], ch.p[i + 1]
		if a and b then
			stretch(p, a, b, w, d, up)
		end
	end
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- his fighting stance (left side forward, fists up), and where his feet go in it
local GUARD_L, GUARD_R = V3(-0.7, 3.9, -2.7), V3(0.8, 3.6, -1.5)
local STANCE_LF, STANCE_RF = V3(-1.2, 0.55, -1.9), V3(1.4, 0.55, 1.7)
local REST_L, REST_R = V3(-2.4, 1.2, -0.2), V3(2.4, 1.2, -0.2)
local FOOT_L, FOOT_R = V3(-1.1, 0.55, 0), V3(1.1, 0.55, 0)

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 10
	local model = B.model
	local now = serverNow()
	-- walking: the legs step while the server says he's moving
	local moving = model:GetAttribute("Moving") == true
	B.walk = smoothTo(B, "walkS", moving and 1 or 0, 8, dt)
	B.stridePhase = (B.stridePhase or 0) + dt * 10 * math.max(B.walk, 0.1)
	local rate = P.snap and 60 or (P.rate or 16)
	local stance = smoothTo(B, "stanceS", clamp(P.stance or 0, 0, 1), rate, dt)
	local crouch = smoothTo(B, "crouchS", clamp(P.crouch or 0, 0, 1), rate, dt)
	local sit = smoothTo(B, "sitS", clamp(P.sit or 0, 0, 1), rate * 0.6, dt)
	local kneel = smoothTo(B, "kneelS", clamp(P.kneel or 0, 0, 1), rate, dt)
	local lie = smoothTo(B, "lieS", clamp(P.lie or 0, 0, 1), rate * 0.7, dt)
	local lean = smoothTo(B, "leanS", P.lean or 0, rate, dt)
	local twist = smoothTo(B, "twistS", (P.twist or 0) + (P.stance or 0) * -0.45, rate, dt)
	local roll = smoothTo(B, "rollS", P.roll or 0, rate, dt)
	local headPitch = smoothTo(B, "headS", P.headPitch or 0, rate, dt)
	local rHandT = smoothTo(B, "rHandS", P.rHand or (stance > 0.5 and GUARD_R or REST_R), rate, dt)
	local lHandT = smoothTo(B, "lHandS", P.lHand or (stance > 0.5 and GUARD_L or REST_L), rate, dt)
	local defaultL = FOOT_L:Lerp(STANCE_LF, clamp(P.stance or 0, 0, 1))
	local defaultR = FOOT_R:Lerp(STANCE_RF, clamp(P.stance or 0, 0, 1))
	local lFootT = smoothTo(B, "lFootS", P.lFoot or defaultL, rate, dt)
	local rFootT = smoothTo(B, "rFootS", P.rFoot or defaultR, rate, dt)
	local glow = smoothTo(B, "glowS", clamp(P.glow or 0, 0, 1), 12, dt)
	local sx, sy = P.sx or 1, P.sy or 1
	local fade = P.fade or 0
	local phase2 = B.phase2Look

	-- the fighter's bounce in his stance (not while walking: then he steps)
	local bob = (P.bob or 0) * (1 - B.walk)
	local bounce = bob * (0.5 + 0.5 * math.sin(now * math.pi * 2 * 1.7)) * 0.22 * u

	local jitter = V3(0, 0, 0)
	if (P.shake or 0) > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local groundPos = ground + jitter + V3(0, (P.lift or 0) + lie * 1.3 * u, 0)
	local look = unitOr(flat(facing), V3(0, 0, -1))
	if P.spin then
		look = turnY(look, P.spin)
	end
	local base = CFrame.lookAt(groundPos, groundPos + look)
	if lie > 0 then
		-- (lying on his back: the whole of him tipped over backward at his feet)
		base = base * CFrame.Angles(math.pi / 2 * lie, 0, 0)
	end
	local forward = base.LookVector

	-- LEGS (two pieces each, bending forward at the knee)
	local hipY = (4.35 - 0.55 * stance - 1.5 * crouch - 3.4 * sit - 2.0 * kneel) * u * sy - bounce
	hipY = math.max(hipY, 0.8 * u)
	local L1, L2 = 2.2 * u, 2.2 * u
	local stride = math.sin(B.stridePhase) * B.walk
	local feet = { lFootT, rFootT }
	local knees, ankles = {}, {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local hip = base * V3(side * 1.0 * u * sx, hipY, 0)
		local f = feet[i]
		-- (walking: each foot swings forward and back, lifting as it comes through)
		local fz = f.Z - side * stride * 1.4
		local fy = f.Y + math.max(0, side * stride) * 0.7
		local ankle = base * V3(f.X * u, fy * u, fz * u)
		local knee, ankle2 = twoBone(hip, ankle, L1, L2, (forward + base.RightVector * side * 0.25).Unit)
		if kneel > 0.5 and side == 1 then
			-- (the kneeling knee rests on the floor)
			knee = knee:Lerp(base * V3(1.0 * u, 0.55 * u, 0.5 * u), (kneel - 0.5) * 2)
		end
		if sit > 0.01 then
			-- (sitting cross-legged: knees out to the sides, feet tucked under the other knee)
			local sk = base * V3(side * 2.1 * u, 0.7 * u, -1.0 * u)
			local sa = base * V3(-side * 0.8 * u, 0.45 * u, -1.1 * u - (side + 1) * 0.3 * u)
			knee = knee:Lerp(sk, sit)
			ankle2 = ankle2:Lerp(sa, sit)
		end
		knees[i], ankles[i] = knee, ankle2
		stretch(body.thighs[i], hip, knee, 2.1 * u * sx, 2.0 * u, forward)
		stretch(body.shins[i], knee, ankle2, 1.85 * u * sx, 1.8 * u, forward)
		local footDir = forward
		if sit > 0.5 then
			footDir = unitOr(flat(base.RightVector * -side), forward)
		end
		local footCF = CFrame.lookAt(ankle2, ankle2 + footDir, base.UpVector)
		local wrap = body.wraps[i]
		wrap.Size = V3(1.5 * u, 0.5 * u, 1.5 * u)
		wrap.CFrame = footCF * CFrame.new(0, 0.05 * u, 0)
		local foot = body.feet[i]
		foot.Size = V3(1.2 * u, 0.75 * u, 2.1 * u)
		foot.CFrame = footCF * CFrame.new(0, -0.45 * u, -0.45 * u)
	end

	-- THE UPPER BODY: from the hips, leaning, twisting and tilting
	local torso = base * CFrame.new(0, hipY, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, roll)
	local up, tLook, right = torso.UpVector, torso.LookVector, torso.RightVector
	body.belt.Size = V3(4.1 * u * sx, 0.8 * u, 2.5 * u)
	body.belt.CFrame = torso * CFrame.new(0, 0.45 * u, 0)
	body.knot.Size = V3(1.0, 0.8, 0.5) * u
	body.knot.CFrame = torso * CFrame.new(-0.6 * u, 0.45 * u, -1.35 * u)
	local chestH = 3.4 * u * sy
	local chestY = 0.85 * u + chestH / 2
	body.chest.Size = V3(4.0 * u * sx, chestH, 2.4 * u)
	body.chest.CFrame = torso * CFrame.new(0, chestY, 0)
	body.giShade.Size = V3(1.0 * u, chestH * 0.94, 2.45 * u)
	body.giShade.CFrame = torso * CFrame.new(1.55 * u * sx, chestY - 0.05 * u, 0)
	-- the open V at the chest: skin, the lapels crossing over it
	body.chestSkin.Size = V3(1.5 * u, 1.6 * u, 0.1)
	body.chestSkin.CFrame = torso * CFrame.new(0, 0.85 * u + chestH - 0.85 * u, -1.22 * u)
	for i, lp in ipairs(body.lapels) do
		local side = (i == 1) and -1 or 1
		lp.Size = V3(0.5 * u, chestH * 0.95, 0.12)
		lp.CFrame = torso * CFrame.new(side * 0.55 * u, chestY, -1.24 * u) * CFrame.Angles(0, 0, side * 0.32)
	end
	-- the head
	local neckY = 0.85 * u + chestH
	local head = torso * CFrame.new(0, neckY + 1.3 * u, -0.1 * u) * CFrame.Angles(-headPitch, 0, 0)
	body.head.Size = V3(2.6 * u, 2.6 * u, 2.5 * u)
	body.head.CFrame = head
	body.hair.Size = V3(2.8 * u, 1.0 * u, 2.7 * u)
	body.hair.CFrame = head * CFrame.new(0, 1.35 * u, 0.1 * u)
	local spikes = {
		{ -0.8, 2.0, 0.2, 0.25 }, { 0.1, 2.3, 0.4, -0.05 }, { 0.9, 2.0, 0.3, -0.3 }, { -0.3, 1.9, 1.1, 0.5 }, { 0.6, 1.8, 1.2, -0.45 },
	}
	for i, s in ipairs(spikes) do
		local sp = body.spikes[i]
		sp.Size = V3(0.8, 1.1, 0.8) * u
		sp.CFrame = head * CFrame.new(s[1] * u, s[2] * u, s[3] * u) * CFrame.Angles(s[3] * 0.5, 0, s[4])
	end
	-- the headband round his forehead, its knot at the back
	body.band.Size = V3(2.72 * u, 0.55 * u, 2.62 * u)
	body.band.CFrame = head * CFrame.new(0, 0.55 * u, 0)
	body.bandKnot.Size = V3(0.8, 0.7, 0.5) * u
	body.bandKnot.CFrame = head * CFrame.new(0.3 * u, 0.55 * u, 1.35 * u)
	-- stern eyebrows, eyes (they glow blue with ki), the mouth (open when he shouts)
	local eyeOpen = clamp(P.eyes or 1, 0, 1) * (1 - fade)
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local brow = body.brows[i]
		brow.Size = V3(0.8 * u, 0.22 * u, 0.12)
		brow.CFrame = head * CFrame.new(side * 0.6 * u, 0.12 * u, -1.27 * u) * CFrame.Angles(0, 0, side * -0.3)
		local eye = body.eyes[i]
		local lit = glow > 0.35
		eye.Size = V3(0.36 * u, math.max(0.5 * u * eyeOpen, 0.05), 0.12)
		eye.CFrame = head * CFrame.new(side * 0.6 * u, -0.28 * u, -1.28 * u)
		eye.Color = lit and CYAN or INK
		eye.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
	local open = clamp(P.open or 0, 0, 1)
	body.mouth.Size = V3(0.8 * u, (0.16 + 0.5 * open) * u, 0.12)
	body.mouth.CFrame = head * CFrame.new(0, -0.85 * u, -1.27 * u)

	-- SHOULDERS, SLEEVES (the right one gone in round 2) and ARMS
	local shoulders = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		shoulders[i] = torso * V3(side * 2.2 * u * sx, neckY - 0.45 * u, 0)
		local sl = body.sleeves[i]
		sl.Size = V3(1.5, 1.3, 1.7) * u
		sl.CFrame = torso * CFrame.new(side * 2.25 * u * sx, neckY - 0.5 * u, 0) * CFrame.Angles(0, 0, -side * 0.2)
		sl.Transparency = (phase2 and i == 2) and 1 or 0
	end
	body.torn.Size = V3(0.9, 0.5, 1.8) * u
	body.torn.CFrame = torso * CFrame.new(1.85 * u * sx, neckY - 0.15 * u, 0) * CFrame.Angles(0, 0, 0.5)
	body.torn.Transparency = phase2 and 0 or 1
	local hands = {}
	local wants = { torso * (lHandT * u), torso * (rHandT * u) }
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local bend = (right * side * 0.5 - up * 0.55 + tLook * -0.45)
		local elbow, hand = twoBone(shoulders[i], wants[i], 1.95 * u, 1.9 * u, bend.Unit)
		hands[i] = hand
		stretch(body.upperArms[i], shoulders[i], elbow, 1.15 * u, 1.15 * u, tLook)
		stretch(body.forearms[i], elbow, hand, 1.05 * u, 1.05 * u, tLook)
		local toward = unitOr(hand - elbow, tLook)
		body.wristWraps[i].Size = V3(1.2, 1.2, 0.45) * u
		body.wristWraps[i].CFrame = CFrame.lookAt(hand - toward * 0.4 * u, hand, tLook)
		body.gloves[i].Size = V3(1.35, 1.35, 1.35) * u
		body.gloves[i].CFrame = CFrame.lookAt(hand + toward * 0.35 * u, hand + toward * 2, tLook)
		-- ki round the fist
		local fg = body.fistGlow[i]
		if glow > 0.05 and fade < 0.5 then
			local s = (1.5 + 0.5 * glow + 0.15 * math.sin(now * 30 + i)) * u
			fg.Size = V3(s, s, s)
			fg.CFrame = body.gloves[i].CFrame * CFrame.Angles(now * 5, now * 4, 0)
			fg.Transparency = lerp(0.8, 0.35, glow)
		else
			fg.Transparency = 1
		end
	end
	B.handR, B.handL = hands[2], hands[1]
	B.headCF, B.headTop = head, head * V3(0, 2.2 * u, 0)

	-- THE BALL OF KI between his hands
	local ball = P.ball or 0
	if ball > 0.02 and fade < 0.5 then
		local mid = (hands[1] + hands[2]) / 2 + tLook * 0.8 * u
		local s = (1.0 + 3.0 * ball) * u * (1 + 0.08 * math.sin(now * 40))
		body.ball.Size = V3(s, s, s)
		body.ball.CFrame = CFrame.new(mid) * CFrame.Angles(now * 6, now * 7, 0)
		body.ball.Transparency = 0.15
		body.ballCore.Size = V3(s, s, s) * 0.55
		body.ballCore.CFrame = CFrame.new(mid) * CFrame.Angles(-now * 5, now * 4, 0)
		body.ballCore.Transparency = 0
		B.ballAt = mid
	else
		body.ball.Transparency, body.ballCore.Transparency = 1, 1
	end

	-- THE TAILS: the headband's two long ones and the belt's two short ones,
	-- streaming in the wind and swinging with everything he does
	local wind = windDir()
	local gust = 0.75 + 0.25 * math.sin(now * 1.3) * math.sin(now * 3.1 + 1)
	local push = V3(0, -30, 0) + wind * 34 * gust + V3(0, 7 * math.sin(now * 6.2), 0)
	B.chains = B.chains or { { n = 6 }, { n = 6 }, { n = 4 }, { n = 4 } }
	local floorY = ground.Y
	local back = -look
	if not B.bandFree then
		for i = 1, 2 do
			local side = (i == 1) and -1 or 1
			local anchor = head * V3((0.3 + side * 0.18) * u, 0.5 * u, 1.45 * u)
			local ch = B.chains[i]
			stepChain(ch, anchor, dt, 1.2 * u, push + V3(0, side * 4 * math.sin(now * 9 + i), 0), floorY, back)
			drawChain(body.bandTails[i], ch, 0.7 * u, 0.16 * u, up)
		end
	end
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local anchor = torso * V3((-0.6 + side * 0.25) * u, 0.3 * u, -1.35 * u)
		local ch = B.chains[2 + i]
		stepChain(ch, anchor, dt, 0.75 * u, push * 0.7 + V3(0, -10, 0), floorY, V3(0, -1, 0))
		drawChain(body.beltTails[i], ch, 0.45 * u, 0.16 * u, tLook)
	end

	-- his headband drifting away on the wind (the K.O.)
	local free = B.bandFree
	if free then
		local e = now - free.t0
		local drift = free.from + wind * (6 * e + 1.2 * e * e) + V3(0, 2.5 * e + 1.5 * math.sin(e * 2.2), 0)
			+ V3(-wind.Z, 0, wind.X) * 2 * math.sin(e * 1.7)
		body.bandKnot.CFrame = CFrame.new(drift) * CFrame.Angles(e * 1.3, e * 2, e * 0.7)
		for i = 1, 2 do
			local ch = B.chains[i]
			stepChain(ch, drift, dt, 1.2 * u, push * 0.6 + V3(0, 26, 0), floorY, back)
			drawChain(body.bandTails[i], ch, 0.7 * u, 0.16 * u, V3(0, 1, 0))
		end
	end
	local bandShown = fade < 0.95 or (free ~= nil and now - free.t0 < 4.5)
	body.band.Transparency = (free or fade > 0.5) and 1 or 0
	body.bandKnot.Transparency = bandShown and 0 or 1
	for i = 1, 2 do
		for _, p in ipairs(body.bandTails[i]) do
			p.Transparency = bandShown and 0 or 1
		end
	end

	-- DIZZY STARS round his head, SWEAT off it
	local stars = P.stars or 0
	for i, st in ipairs(body.stars) do
		if stars > 0.05 and fade < 0.5 then
			local a = now * 5 + i * (math.pi * 2 / 3)
			local p = head * V3(math.cos(a) * 2.4 * u, 2.6 * u, math.sin(a) * 2.4 * u)
			st.Size = V3(1.0, 1.0, 0.4) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, now * 6)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end
	local sweat = P.sweat or 0
	for i, sw in ipairs(body.sweat) do
		if sweat > 0.05 and fade < 0.5 then
			local e = (now * 1.6 + i / 3) % 1
			local side = (i % 2 == 0) and 1 or -1
			local p = head * V3(side * (1.4 + e * 0.8) * u, (1.0 - e * 2.2) * u, -0.4 * u)
			sw.Size = V3(0.35, 0.55, 0.35) * u
			sw.CFrame = CFrame.new(p)
			sw.Transparency = e > 0.8 and 1 or 0.1
		else
			sw.Transparency = 1
		end
	end

	-- his shadow
	local shadowD = 6.5 * u * (1 - clamp((P.lift or 0) / 30, 0, 0.7))
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.07, 0) + back * lie * 3.2 * u, shadowD * (1 + lie * 0.15), 0.1)
	body.shadow.Transparency = (fade > 0.5) and 1 or 0

	-- the ki aura
	local full = (model:GetAttribute("Ki") or 0) >= def.Ki.Bar * def.Ki.Bars
	local auraRate = 0
	if fade < 0.3 then
		if glow > 0.3 then
			auraRate = 40 * glow
		elseif full then
			auraRate = 22
		elseif phase2 then
			auraRate = 8
		end
	end
	body.aura.Rate = auraRate

	-- colours: a punch landing blinks him pale; a cancel flashes him white
	local hitFlash = B.flashAt and (os.clock() - B.flashAt) < 0.1
	local cancelFlash = B.cancelFlashUntil and os.clock() < B.cancelFlashUntil
	for _, rec in ipairs(body.all) do
		local p = rec.part
		if cancelFlash then
			p.Color = WHITE
			p.Material = Enum.Material.Neon
		elseif hitFlash then
			p.Color = (rec.color == WHITE) and PALE or WHITE
			p.Material = rec.material
		elseif p.Name ~= "Eye" then
			p.Color = rec.color
			p.Material = rec.material
		end
	end

	-- scattering into petals (the K.O.): each part goes at its own moment
	for _, rec in ipairs(body.all) do
		local p = rec.part
		if fade > 0 and fade >= body.popAt[p] * 0.9 + 0.05 then
			if not (free and (p.Name == "BandKnot" or p.Name == "BandTail")) then
				p.Transparency = 1
			end
		elseif not body.selfShown[p.Name] then
			p.Transparency = 0
		end
	end
end
Body.pose = applyPose

----------------------------------------------------------------------
-- Warnings and effects in the world
----------------------------------------------------------------------
-- a ghost of his body where he is right now, fading (dashes, spins, leaps)
local function ghost(B, color)
	local body = B.body
	local src = { body.chest, body.head, body.hair, body.belt, body.thighs[1], body.thighs[2], body.shins[1], body.shins[2],
		body.upperArms[1], body.upperArms[2], body.forearms[1], body.forearms[2], body.gloves[1], body.gloves[2] }
	local list = {}
	for _, p in ipairs(src) do
		if p.Transparency < 0.5 then
			local g = newPart("Afterimage", nil, color or CYAN, Enum.Material.Neon, 0.55)
			g.Size = p.Size
			g.CFrame = p.CFrame
			table.insert(list, g)
		end
	end
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > 0.28 then
				return false
			end
			local tr = 0.55 + 0.45 * (e / 0.28)
			for _, g in ipairs(list) do
				g.Transparency = tr
			end
			return true
		end,
		cleanup = function()
			for _, g in ipairs(list) do
				g:Destroy()
			end
		end,
	})
end

-- ghosts every `every` seconds from `from` to `to` (server time)
local function ghostTrail(B, from, to, every, color)
	local last = -1
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if now > to or (B.action ~= name and now > from + 0.05) then
				return false
			end
			if now >= from and now - last >= every then
				last = now
				ghost(B, color)
			end
			return true
		end,
		cleanup = function() end,
	})
end

-- a red wedge on the floor in front of him (a punch), `arc` degrees wide and
-- `reach` long, its band sweeping outward until `hitAt`. It turns with him
-- until the server fixes the aim (slot `slotIndex`), then flashes.
local function punchWedge(B, reach, arcDeg, showAt, hitAt, slotIndex)
	local N = 9
	local rim, band = {}, {}
	for i = 1, N do
		rim[i] = newPart("PunchWarning", nil, RED, Enum.Material.Neon, 1)
		band[i] = newPart("PunchWarning", nil, RED, Enum.Material.Neon, 1)
	end
	local half = math.rad(arcDeg / 2)
	local lockedAt = nil
	local name = B.action
	local function arc(parts, c, dir, r, thick, tr, color)
		local step = (half * 2) / N
		for i, p in ipairs(parts) do
			local ang = -half + (i - 0.5) * step
			local out = turnY(dir, ang)
			local pos = c + out * r + V3(0, 0.16, 0)
			p.Size = V3(2 * r * math.sin(step / 2) + 0.2, 0.12, thick)
			p.CFrame = CFrame.lookAt(pos, pos + out)
			p.Transparency = tr
			p.Color = color
		end
	end
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.08 or (B.action ~= name) then
				return false
			end
			if now < showAt then
				return true
			end
			local c = onFloor(B.vpos)
			local aim = slot(B, slotIndex)
			if aim and not lockedAt then
				lockedAt = now
			end
			local dir = aim and unitOr(flat(aim - B.vpos), B.vfacing) or B.vfacing
			local k = clamp((now - showAt) / math.max(hitAt - showAt, 0.05), 0, 1)
			local blink = lockedAt and (now - lockedAt) < 0.12 and ((now - lockedAt) % 0.06) < 0.03
			local color = blink and WHITE or RED
			arc(rim, c, dir, reach, 0.45, lockedAt and 0.15 or 0.4, color)
			arc(band, c, dir, math.max(reach * smooth(k), 1.5), 1.0, lerp(0.65, 0.3, k), color)
			return true
		end,
		cleanup = function()
			for i = 1, N do
				rim[i]:Destroy()
				band[i]:Destroy()
			end
		end,
	})
end

-- a red lane on the floor from him: `width` wide. Until the server fixes it
-- (slots `sa` and `sb`), it follows the way he faces, `guessLen` long; then it
-- flashes and stays exactly where the move will go. Gone at `untilT`
-- (a function, so a move can say when once it knows).
local function lane(B, width, guessLen, sa, sb, untilT, pale)
	local strip = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1)
	local rims = { newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1), newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1) }
	local lockedAt = nil
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name or now > untilT() then
				return false
			end
			local from, to = slot(B, sa), slot(B, sb)
			local c0, c1
			if from and to then
				lockedAt = lockedAt or now
				c0, c1 = onFloor(from), onFloor(to)
			else
				c0 = onFloor(B.vpos)
				c1 = c0 + B.vfacing * guessLen
			end
			local blink = lockedAt and (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
			local color = blink and WHITE or RED
			local dir = unitOr(flat(c1 - c0), B.vfacing)
			local side = V3(-dir.Z, 0, dir.X)
			local len = math.max(flat(c1 - c0).Magnitude, 0.1)
			local mid = (c0 + c1) / 2 + V3(0, 0.13, 0)
			strip.Size = V3(width, 0.12, len)
			strip.CFrame = CFrame.lookAt(mid, mid + dir)
			strip.Transparency = lockedAt and 0.5 or (pale and 0.82 or 0.7)
			strip.Color = color
			for i, rim in ipairs(rims) do
				local s = (i == 1) and -1 or 1
				local rm = mid + side * s * width / 2 + V3(0, 0.02, 0)
				rim.Size = V3(0.45, 0.14, len)
				rim.CFrame = CFrame.lookAt(rm, rm + dir)
				rim.Transparency = lockedAt and 0.1 or 0.45
				rim.Color = color
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
			rims[1]:Destroy()
			rims[2]:Destroy()
		end,
	})
end

-- the ball of ki rolling along the floor from `from` to `to`, with the red
-- strip of the path still ahead of it; it bursts where it stops (on a pillar:
-- a spray of stone chips)
local function kiBall(B, from, to, launch, k)
	local a = B.def.Attacks.KazeBlast
	from, to = onFloor(from), onFloor(to)
	local dir = unitOr(flat(to - from), B.vfacing)
	local len = flat(to - from).Magnitude
	local radius, height = byCharge(a.Radius, k), byCharge(a.Height, k)
	local speed = byCharge(a.Speed, k)
	local ballP = newPart("KiBlast", nil, CYAN, Enum.Material.Neon, 1)
	local core = newPart("KiBlastCore", nil, WHITE, Enum.Material.Neon, 1)
	local rings = { newPart("KiBlastRing", nil, BLUE, Enum.Material.Neon, 1), newPart("KiBlastRing", nil, BLUE, Enum.Material.Neon, 1) }
	local lanePart = newPart("BlastLane", nil, RED, Enum.Material.Neon, 1)
	local lastTrail = 0
	local done = false
	addTelegraph(B, {
		update = function(now)
			local gone = (now - launch) * speed
			if gone > len then
				if not done then
					done = true
					local stopAt = from + dir * len + V3(0, height * 0.55, 0)
					burst(stopAt, CYAN, 22, 18, 1.4, 0.5)
					burst(stopAt, WHITE, 10, 10, 1, 0.4)
					shockRing(B, stopAt, 1, radius * 2.2, 0.3, CYAN)
					-- (did it stop on a pillar? chips of stone)
					local _, pl = firstPillar(B, from, dir, len + radius + 1)
					if pl then
						burst(stopAt, STONE, 12, 16, 1.1, 0.5)
					end
					playSound(B.def, "Blast", stopAt, 0.35)
				end
				return false
			end
			local p = from + dir * math.max(gone, 0)
			local rest = len - math.max(gone, 0)
			lanePart.Size = V3(radius * 1.7, 0.12, math.max(rest, 0.1))
			lanePart.CFrame = CFrame.lookAt(p + dir * rest / 2 + V3(0, 0.13, 0), p + dir * rest + V3(0, 0.13, 0))
			lanePart.Transparency = gone < 0 and 0.78 or 0.55
			if gone < 0 then
				ballP.Transparency, core.Transparency = 1, 1
				rings[1].Transparency, rings[2].Transparency = 1, 1
				return true
			end
			local c = p + V3(0, height * 0.55, 0)
			local s = radius * 1.35 * (1 + 0.1 * math.sin(now * 38))
			ballP.Size = V3(s, s, s)
			ballP.CFrame = CFrame.new(c) * CFrame.Angles(now * 9, now * 7, 0)
			core.Size = V3(s, s, s) * 0.55
			core.CFrame = CFrame.new(c) * CFrame.Angles(-now * 6, now * 5, 0)
			for i, r in ipairs(rings) do
				r.Size = V3(s * 1.5, 0.3, 0.3)
				r.CFrame = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, 0, now * (i == 1 and 12 or -9)) * CFrame.new(0, 0, 0)
				r.Transparency = 0.2
			end
			ballP.Transparency, core.Transparency = 0.1, 0
			if now - lastTrail > 0.05 then
				lastTrail = now
				burst(c - dir * s * 0.5, CYAN, 3, 4, 0.9 * (0.6 + k), 0.3, true)
			end
			return true
		end,
		cleanup = function()
			ballP:Destroy()
			core:Destroy()
			rings[1]:Destroy()
			rings[2]:Destroy()
			lanePart:Destroy()
		end,
	})
end

-- the Rising Dragon's ring: pale while he charges, filling in red through the
-- crouch, white as he goes up
local function dragonRing(B, radius, showAt, fillAt, hitAt)
	local disc = newPart("DragonWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local ring = newRing(26, RED, Enum.Material.Neon, 1)
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.06 or B.action ~= name then
				return false
			end
			if now < showAt then
				return true
			end
			local c = onFloor(B.vpos)
			local k = clamp((now - fillAt) / math.max(hitAt - fillAt, 0.05), 0, 1)
			local charging = now < fillAt
			placeDisc(disc, c + V3(0, 0.12, 0), radius * 2 * (charging and 0.25 or (0.25 + 0.75 * k)), 0.1)
			disc.Transparency = charging and 0.85 or lerp(0.65, 0.35, k)
			placeRing(ring, c + V3(0, 0.14, 0), radius, 0.3, 0.5, charging and (0.45 + 0.2 * math.sin(now * 16)) or 0.15)
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- The Super's fan: the whole area the beam will sweep, filled in red on the
-- floor (bands out to the beam's Length, pulsing, a bright rim). It follows
-- the way he faces until the server fixes it (slot 2, and ActN: which way it
-- sweeps), then flashes, and arrows along the rim show which way the beam
-- will come round.
local function superFan(B, a, t0)
	local half = math.rad(a.Sweep / 2)
	local BANDS = { { 13, 14 }, { 27, 14 }, { 41, 14 }, { 55, 14 }, { 69, 14 }, { 83, 14 }, { 97, 1.6 } } -- { radius, thickness }
	local N = 14
	local arcs = {}
	for b = 1, #BANDS do
		arcs[b] = {}
		for i = 1, N do
			arcs[b][i] = newPart("SuperWarning", nil, RED, Enum.Material.Neon, 1)
		end
	end
	local edges = { newPart("SuperWarning", nil, RED, Enum.Material.Neon, 1), newPart("SuperWarning", nil, RED, Enum.Material.Neon, 1) }
	local arrows = {}
	for i = 1, 3 do
		arrows[i] = newPart("SuperArrow", nil, WHITE, Enum.Material.Neon, 1)
	end
	local lockedAt = nil
	local endAt = t0 + a.Tell + a.SweepTime
	addTelegraph(B, {
		update = function(now)
			if now > endAt or B.action ~= "Super" then
				return false
			end
			local center = slot(B, 1)
			if not center or now < t0 + a.Leap * 0.6 then
				return true
			end
			center = onFloor(center)
			local mid = slot(B, 2)
			if mid and not lockedAt then
				lockedAt = now
			end
			local dir = mid and unitOr(flat(mid - center), B.vfacing) or B.vfacing
			local sign = actN(B)
			local blink = lockedAt and (now - lockedAt) < 0.3 and ((now - lockedAt) % 0.1) < 0.05
			local firing = now >= t0 + a.Tell
			local pulse = 0.5 + 0.5 * math.sin(now * (lockedAt and 18 or 8))
			local color = blink and WHITE or RED
			local step = (half * 2) / N
			for b, band in ipairs(BANDS) do
				local R, thick = band[1], band[2]
				local rim = b == #BANDS
				for i, p in ipairs(arcs[b]) do
					local ang = -half + (i - 0.5) * step
					local out = turnY(dir, ang)
					local pos = center + out * R + V3(0, rim and 0.2 or 0.16, 0)
					p.Size = V3(2 * (R + thick / 2) * math.sin(step / 2) + 0.3, 0.12, thick)
					p.CFrame = CFrame.lookAt(pos, pos + out)
					p.Color = color
					if firing then
						p.Transparency = rim and 0.5 or 0.86
					elseif rim then
						p.Transparency = lerp(0.25, 0.02, pulse)
					else
						p.Transparency = lerp(0.62, 0.45, pulse) - ((b % 2 == 0) and 0.05 or 0)
					end
				end
			end
			for i, e in ipairs(edges) do
				local out = turnY(dir, (i == 1) and -half or half)
				local p0, p1 = center + out * 6 + V3(0, 0.2, 0), center + out * BANDS[#BANDS][1] + V3(0, 0.2, 0)
				e.Size = V3(1.2, 0.12, (p1 - p0).Magnitude)
				e.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
				e.Color = color
				e.Transparency = firing and 0.6 or 0.1
			end
			-- arrows along the rim: which way the beam comes round
			for i, p in ipairs(arrows) do
				if lockedAt and sign ~= 0 and not firing then
					local ang = sign * (-half + (i + (now * 2 % 1)) * (half * 2) / 4)
					local out = turnY(dir, ang)
					local pos = center + out * (BANDS[#BANDS][1] - 6) + V3(0, 0.3, 0)
					local tangent = turnY(out, sign * math.pi / 2)
					p.Size = V3(2, 0.25, 6)
					p.CFrame = CFrame.lookAt(pos, pos + tangent)
					p.Transparency = 0.05
				else
					p.Transparency = 1
				end
			end
			return true
		end,
		cleanup = function()
			for b = 1, #arcs do
				for _, p in ipairs(arcs[b]) do
					p:Destroy()
				end
			end
			for _, p in ipairs(edges) do
				p:Destroy()
			end
			for _, p in ipairs(arrows) do
				p:Destroy()
			end
		end,
	})
end

-- white outlines round the standing pillars while the Super winds up: HIDE HERE
local function pillarGlow(B, untilT)
	local boxes = {}
	for _, pl in ipairs(pillarsOf(B)) do
		local box = newPart("PillarHint", nil, WHITE, Enum.Material.Neon, 1)
		table.insert(boxes, { part = box, pl = pl })
	end
	addTelegraph(B, {
		update = function(now)
			if now > untilT or B.action ~= "Super" then
				return false
			end
			for _, b in ipairs(boxes) do
				local standing = not b.pl.model:GetAttribute("Broken")
				local c = b.pl.core.Position
				b.part.Size = V3(6.4, 11, 6.4) + V3(1, 1, 1) * (0.3 * math.sin(now * 10))
				b.part.CFrame = CFrame.new(c) * CFrame.Angles(0, math.rad(22.5), 0)
				b.part.Transparency = standing and lerp(0.7, 0.4, 0.5 + 0.5 * math.sin(now * 10)) or 1
			end
			return true
		end,
		cleanup = function()
			for _, b in ipairs(boxes) do
				b.part:Destroy()
			end
		end,
	})
end

-- THE BEAM: strands of ki across its width, each stopped by the first
-- standing pillar in its way (where it sprays sparks), sweeping round with him
local function superBeam(B, a, t0)
	local tF = t0 + a.Tell
	local STRANDS = { -0.4, -0.2, 0, 0.2, 0.4 }
	local outer, inner = {}, {}
	for i = 1, #STRANDS do
		outer[i] = newPart("Beam", nil, CYAN, Enum.Material.Neon, 1)
		inner[i] = newPart("BeamCore", nil, WHITE, Enum.Material.Neon, 1)
	end
	local mouthGlow = newPart("BeamMouth", nil, WHITE, Enum.Material.Neon, 1)
	local lastSpark, lastDust = 0, 0
	local half = math.rad(a.Sweep / 2)
	addTelegraph(B, {
		update = function(now)
			if now > tF + a.SweepTime + 0.05 or B.action ~= "Super" then
				return false
			end
			local center, mid = slot(B, 1), slot(B, 2)
			if not (center and mid) or now < tF then
				return true
			end
			center = onFloor(center)
			local dir0 = unitOr(flat(mid - center), B.vfacing)
			local base = math.atan2(dir0.X, dir0.Z)
			local sign = actN(B)
			local uS = clamp((now - tF) / a.SweepTime, 0, 1)
			local ang = base + sign * (-half + 2 * half * uS)
			local dir = V3(math.sin(ang), 0, math.cos(ang))
			local side = V3(-dir.Z, 0, dir.X)
			local y = 3.4
			local src = (B.handR and B.handL) and ((B.handR + B.handL) / 2) or (center + V3(0, y, 0))
			for i, o in ipairs(STRANDS) do
				local from = center + side * o * a.Width
				local len, pl = firstPillar(B, from, dir, a.Length)
				local p0 = V3(from.X, src.Y, from.Z) + dir * 1.5
				local p1 = V3(from.X, src.Y, from.Z) + dir * math.max(len, 2)
				local w = (i == 3) and 3.6 or 2.6
				outer[i].Size = V3(w, w, (p1 - p0).Magnitude)
				outer[i].CFrame = CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, 0, now * 20 + i)
				outer[i].Transparency = 0.25 + 0.1 * math.sin(now * 50 + i)
				inner[i].Size = V3(w * 0.45, w * 0.45, (p1 - p0).Magnitude)
				inner[i].CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
				inner[i].Transparency = 0
				if pl and now - lastSpark > 0.05 then
					lastSpark = now
					burst(p1, WHITE, 6, 18, 0.8, 0.3)
					burst(p1, STONE, 4, 14, 0.8, 0.4)
				end
			end
			local ms = 5 + 0.6 * math.sin(now * 40)
			mouthGlow.Size = V3(ms, ms, ms)
			mouthGlow.CFrame = CFrame.new(src + dir * 1.5) * CFrame.Angles(now * 8, now * 6, 0)
			mouthGlow.Transparency = 0.1
			if now - lastDust > 0.08 then
				lastDust = now
				local len = firstPillar(B, center, dir, a.Length)
				burst(center + dir * (len * 0.6), PALE, 6, 10, 2, 0.5, true)
			end
			return true
		end,
		cleanup = function()
			for i = 1, #STRANDS do
				outer[i]:Destroy()
				inner[i]:Destroy()
			end
			mouthGlow:Destroy()
		end,
	})
end

-- pebbles and splinters floating up round him while he meditates
local function risingPebbles(B, untilT)
	local list = {}
	for i = 1, 8 do
		table.insert(list, { part = newPart("KiPebble", nil, (i % 3 == 0) and WOOD or STONE, Enum.Material.SmoothPlastic, 1), a = i / 8 * math.pi * 2, r = 5 + (i % 3) * 1.6, k = (i * 0.37) % 1 })
	end
	local name = B.action
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			if now > untilT or B.action ~= name then
				return false
			end
			local e = now - t0
			local c = onFloor(B.vpos)
			for _, pb in ipairs(list) do
				local h = ((e * 0.6 + pb.k) % 1)
				local ang = pb.a + e * 0.8
				local p = c + V3(math.cos(ang) * pb.r, 0.4 + h * 9, math.sin(ang) * pb.r)
				pb.part.Size = V3(0.6, 0.5, 0.6)
				pb.part.CFrame = CFrame.new(p) * CFrame.Angles(e * 2 + pb.a, e * 3, 0)
				pb.part.Transparency = (h > 0.85) and 1 or 0
			end
			return true
		end,
		cleanup = function()
			for _, pb in ipairs(list) do
				pb.part:Destroy()
			end
		end,
	})
end

-- a rising hum while he charges (the Charge sound, sped up as he holds it)
local function hum(B, seconds)
	local def = B.def
	local template = findSound(tostring(def.Sounds and def.Sounds.Charge or "Kaze Charge")) or findSound("Boss Wail")
	if not template or seconds <= 0 then
		return
	end
	local s = template:Clone()
	s.Looped = true
	s.PlaybackSpeed = 0.8
	s.Volume = 0.35
	s.SoundGroup = soundGroup("Effects")
	s.Parent = game:GetService("SoundService")
	s:Play()
	tween(s, seconds, { PlaybackSpeed = 1.45, Volume = 0.6 }, Enum.EasingStyle.Linear)
	task.delay(seconds + 0.05, function()
		s:Destroy()
	end)
end

-- stone chunks flying off a pillar as it crumbles
local function crumble(B, pl)
	local c = pl.core.Position
	for i = 1, 8 do
		local chunk = newPart("PillarChunk", nil, (i % 3 == 0) and RED_DARK or ((i % 2 == 0) and STONE or STONE_DARK), Enum.Material.SmoothPlastic, 0)
		local s = 1 + (i % 3) * 0.6
		chunk.Size = V3(s, s * 0.8, s)
		local ang = i / 8 * math.pi * 2
		local out = V3(math.cos(ang), 0, math.sin(ang))
		local start = c + V3(0, (i % 4) * 3 - 3, 0)
		local t0 = serverNow()
		local floorY = B.vpos.Y
		addTelegraph(B, {
			update = function(now)
				local e = now - t0
				if e > 1.6 then
					return false
				end
				local pos = start + out * 14 * e + V3(0, 12 * e - 30 * e * e, 0)
				if pos.Y < floorY + s * 0.4 then
					pos = V3(pos.X, floorY + s * 0.4, pos.Z)
				end
				chunk.CFrame = CFrame.new(pos) * CFrame.Angles(e * 7, e * 4 + ang, 0)
				chunk.Transparency = e > 1.3 and 1 or 0
				return true
			end,
			cleanup = function()
				chunk:Destroy()
			end,
		})
	end
	burst(c, STONE, 30, 20, 2.2, 0.8)
	burst(c + V3(0, 6, 0), PALE, 20, 14, 2.6, 0.9)
	kick(c, 20, 0.9, -3)
	playSound(B.def, "Pillar", c, 1)
end

----------------------------------------------------------------------
-- The shape of each move over time
----------------------------------------------------------------------
-- the stance and its bounce: his default whenever he's fighting
local function stancePose(P)
	P.stance = 1
	P.bob = 1
end

function Poses.Idle(B, t, P)
	stancePose(P)
end

-- PUNCH STRING: jab (left), straight (right), heavy (a rising right) - each
-- pulled back through its wind-up, snapped out at the hit
local STRIKES = {
	{ hand = "lHand", back = V3(-0.9, 3.8, -1.3), out = V3(-0.1, 3.8, -5.2), twistBack = -0.2, twistOut = 0.15 },
	{ hand = "rHand", back = V3(1.6, 3.4, 0.4), out = V3(0.1, 3.8, -5.2), twistBack = -0.35, twistOut = 0.85 },
	{ hand = "rHand", back = V3(2.0, 1.6, 1.3), out = V3(0.3, 4.9, -4.6), twistBack = -0.55, twistOut = 1.05 },
}
function Poses.PunchString(B, t, P)
	local a = B.def.Attacks.PunchString
	stancePose(P)
	P.bob = 0
	local t1 = 0
	for i = 1, 3 do
		local tHit = t1 + a.Tells[i]
		if t < tHit + 0.14 or i == 3 then
			local s = STRIKES[i]
			if t < tHit - 0.07 then
				local k = smooth((t - t1) / math.max(tHit - 0.07 - t1, 0.05))
				P[s.hand] = s.back
				P.twist = s.twistBack * k
				P.crouch = (i == 3) and 0.45 * k or 0.1
				P.lean = (i == 3) and -0.05 or 0.05
			elseif t < tHit + 0.14 then
				P[s.hand] = s.out
				P.twist = s.twistOut
				P.lean = (i == 3) and 0.25 or 0.12
				P.crouch = (i == 3) and 0.1 or 0.05
				P.snap = true
				P.open = (i == 3) and 1 or 0
				if i == 3 then
					P.lift = 1.2 * math.sin(math.pi * clamp((t - tHit + 0.07) / 0.3, 0, 1))
				end
			else
				-- (after the heavy: off-balance a moment, then back into his stance)
				local k = clamp((t - tHit - 0.14) / 0.5, 0, 1)
				P[s.hand] = s.out:Lerp(GUARD_R, smooth(k))
				P.twist = lerp(s.twistOut, 0, smooth(k))
				P.lean = lerp(0.25, 0, smooth(k))
			end
			return
		end
		t1 = tHit
	end
end

-- the cupped hands at his hip, the ball of ki growing (a Kaze-Blast's charge,
-- the Fake Charge, the Super's wind-up)
local function cupPose(P, ballSize, glow, wide)
	P.stance = 0.6
	P.bob = 0
	P.crouch = wide and 0.55 or 0.35
	P.twist = -0.75
	P.rHand = V3(1.9, 1.6, 0.9)
	P.lHand = V3(1.35, 1.9, 0.5)
	P.ball = ballSize
	P.glow = glow
	if wide then
		P.lFoot, P.rFoot = V3(-2.1, 0.55, -1.2), V3(2.0, 0.55, 1.3)
	end
end

-- both palms thrust out in front (the Kaze-Blast let go, the Super's beam)
local function pushPose(P, wide)
	P.stance = 0.6
	P.bob = 0
	P.crouch = wide and 0.5 or 0.25
	P.twist = 0.2
	P.lean = 0.12
	P.rHand = V3(0.4, 3.1, -4.4)
	P.lHand = V3(-0.4, 3.3, -4.4)
	P.open = 1
	P.glow = 1
	if wide then
		P.lFoot, P.rFoot = V3(-2.1, 0.55, -1.2), V3(2.0, 0.55, 1.3)
	end
end

function Poses.KazeBlast(B, t, P)
	local a = B.def.Attacks.KazeBlast
	local hold = actN(B)
	local tR = hold + a.Tell
	if t < tR - 0.08 then
		local grow = hold > 0 and clamp(t / (hold + a.Tell), 0, 1) or clamp(t / a.Tell, 0, 1)
		cupPose(P, 0.25 + 0.75 * grow * (0.6 + 0.4 * chargeLevel(B, hold)), (t < hold) and (0.6 + 0.4 * math.sin(t * 20)) or 1)
		P.shake = (t < hold) and 0.05 or 0
		return
	end
	pushPose(P)
	if t > tR + 0.35 then
		local k = clamp((t - tR - 0.35) / 0.3, 0, 1)
		P.glow = 1 - k
		P.open = 0
	end
end

-- FAKE CHARGE: exactly a Kaze-Blast's charge (the cancel itself starts his dash)
function Poses.FakeCharge(B, t, P)
	cupPose(P, 0.25 + 0.5 * clamp(t / 0.6, 0, 1), 0.6 + 0.4 * math.sin(t * 20))
	P.shake = 0.05
end

-- RISING DRAGON: a deep crouch, fist glowing low; then up, spinning, the
-- fist straight up; down tucked; a crouched landing, open
function Poses.RisingDragon(B, t, P)
	local a = B.def.Attacks.RisingDragon
	local hold = actN(B)
	local k = chargeLevel(B, hold)
	local tA = hold + a.Tell
	if t < tA then
		P.stance = 0.5
		P.bob = 0
		P.crouch = 0.85
		P.twist = -0.5
		P.rHand = V3(0.2, 1.3, -1.6)
		P.lHand = V3(-1.2, 3.2, -2.0)
		P.glow = (t < hold) and (0.6 + 0.4 * math.sin(t * 20)) or 1
		P.shake = (t < hold) and 0.06 or 0
		return
	end
	local air = byCharge(a.Air, k)
	local height = byCharge(a.Height, k)
	local e = t - tA
	local A, Bs = slot(B, 1), slot(B, 2)
	if e < air then
		P.lift = jumpHeight(e, air, 0.42, height, 0)
		if A and Bs then
			P.override = A:Lerp(Bs, clamp(e / air, 0, 1))
		end
		local rising = e < air * 0.42
		P.snap = true
		if rising then
			P.spin = e / (air * 0.42) * math.pi * 4
			P.rHand = V3(0.5, 8.4, -0.6)
			P.lHand = V3(-1.9, 2.2, 0.5)
			P.lFoot = V3(-0.9, 2.4, -1.4)
			P.rFoot = V3(1.0, 0.2, 0.5)
			P.sy = 1.1
			P.open = 1
			P.glow = 1
		else
			P.rHand = V3(0.9, 5.4, -1.8)
			P.lHand = V3(-1.6, 4.2, -1.6)
			P.lFoot = V3(-1.0, 1.6, -1.0)
			P.rFoot = V3(1.0, 1.2, 0.8)
			P.glow = 0.3
		end
		return
	end
	if Bs then
		P.override = Bs
	end
	-- landed: squash, crouched, catching his breath (open!)
	local l = e - air
	local w = spring(l, 7, 16)
	P.sy, P.sx = 1 - 0.18 * w, 1 + 0.12 * w
	P.crouch = lerp(0.75, 0.3, clamp(l / 0.8, 0, 1))
	P.stance = 0.4
	P.rHand = V3(1.2, 1.4, -2.2)
	P.lHand = V3(-1.6, 2.4, -1.6)
	P.headPitch = 0.15
end

-- TORNADO KICK: a chambered hop; then spinning along the lane, one leg
-- straight out; a landing
function Poses.TornadoKick(B, t, P)
	local a = B.def.Attacks.TornadoKick
	local hold = actN(B)
	local k = chargeLevel(B, hold)
	local tS = hold + a.Tell
	if t < tS then
		P.stance = 0.5
		P.bob = 0
		P.crouch = 0.5
		P.twist = -0.8
		P.rFoot = V3(1.3, 1.9, 0.6)
		P.rHand = V3(2.6, 3.6, 0.8)
		P.lHand = V3(-2.4, 3.8, -0.8)
		P.glow = (t < hold) and (0.6 + 0.4 * math.sin(t * 20)) or 0.6
		P.shake = (t < hold) and 0.06 or 0
		return
	end
	local from, to = slot(B, 1), slot(B, 2)
	local len = (from and to) and flat(to - from).Magnitude or 20
	local travel = len / byCharge(a.Speed, k)
	local e = t - tS
	if e < travel + 0.2 then
		P.lift = jumpHeight(e, travel + 0.2, 0.12, a.Hop, travel * 0.75)
		if from and to then
			P.override = from:Lerp(to, clamp(e / travel, 0, 1))
			P.facing = unitOr(flat(to - from), B.vfacing)
		end
		P.spin = e * 26
		P.snap = true
		P.rFoot = V3(5.0, 3.6, -0.3)
		P.lFoot = V3(-0.8, 2.2, 0.6)
		P.rHand = V3(2.8, 4.2, 0.4)
		P.lHand = V3(-2.8, 4.0, 0.4)
		P.lean = -0.15
		P.open = 1
		return
	end
	if to then
		P.override = to
	end
	local l = e - travel - 0.2
	local w = spring(l, 7, 16)
	P.sy, P.sx = 1 - 0.15 * w, 1 + 0.1 * w
	P.stance = 0.6
	P.crouch = lerp(0.5, 0.2, clamp(l / 0.6, 0, 1))
	P.roll = 0.1 * math.sin(l * 8) * math.max(0, 1 - l)
end

-- KI FOCUS: horse stance, fists at his hips, head back, roaring; shaking
function Poses.KiFocus(B, t, P)
	P.stance = 0
	P.crouch = 0.35
	P.lFoot, P.rFoot = V3(-2.3, 0.55, 0), V3(2.3, 0.55, 0)
	P.rHand = V3(1.9, 1.3, 0.2)
	P.lHand = V3(-1.9, 1.3, 0.2)
	P.headPitch = -0.22
	P.lean = -0.08
	P.open = 1
	P.glow = 1
	P.shake = 0.08
	P.eyes = 1
end

-- DASH: low and fast, arms back, afterimages
function Poses.Dash(B, t, P)
	local D = B.def.Movement.Dash
	local from, to = slot(B, 1), slot(B, 2)
	if from and to and t < D.Time then
		P.override = from:Lerp(to, clamp(t / D.Time, 0, 1))
	elseif to then
		P.override = to
	end
	P.stance = 0.5
	P.crouch = 0.35
	P.lean = 0.45
	P.rHand = V3(1.4, 2.4, 1.6)
	P.lHand = V3(-1.4, 2.4, 1.6)
	P.snap = true
end

-- BACK HOP: a little hop away, guard up
function Poses.BackHop(B, t, P)
	local H = B.def.Movement.BackHop
	local from, to = slot(B, 1), slot(B, 2)
	if t < H.Time then
		P.lift = jumpHeight(t, H.Time, 0.5, H.Height, 0)
		if from and to then
			P.override = from:Lerp(to, clamp(t / H.Time, 0, 1))
		end
		P.lFoot, P.rFoot = V3(-1.1, 1.4, -0.6), V3(1.2, 1.1, 0.8)
	elseif to then
		P.override = to
	end
	stancePose(P)
	P.bob = 0
	P.lean = -0.15
end

-- TIRED: bent over, hands on his knees, panting, sweating
function Poses.Tired(B, t, P)
	P.stance = 0
	P.crouch = 0.35
	P.lean = 0.6
	P.lFoot, P.rFoot = V3(-1.5, 0.55, -0.3), V3(1.5, 0.55, 0.3)
	P.rHand = V3(1.4, 0.2, -2.2)
	P.lHand = V3(-1.4, 0.2, -2.2)
	P.headPitch = -0.35
	P.sy = 1 + 0.05 * math.sin(t * 7)
	P.open = 0.6 + 0.4 * math.sin(t * 7)
	P.eyes = 0.45
	P.sweat = 1
end

-- STAGGER: knocked back, arms flung wide, seeing stars
function Poses.Stagger(B, t, P)
	local k = clamp(t / 0.2, 0, 1)
	P.stance = 0
	P.lean = -0.3 * k + 0.05 * math.sin(t * 6)
	P.roll = 0.12 * math.sin(t * 5)
	P.headPitch = -0.3
	P.rHand = V3(2.9, 4.4, 0.6)
	P.lHand = V3(-2.9, 4.1, 0.8)
	P.crouch = 0.2
	P.stars = 1
	P.shake = (t < 0.25) and 0.15 or 0
	P.eyes = 0.3
end

-- SUPER: a leap to the middle, the huge ball of ki at his hip while the fan
-- follows you, the beam (he turns with it), then exhausted
function Poses.Super(B, t, P)
	local a = B.def.Attacks.Super
	local center = slot(B, 1)
	if t < a.Leap then
		P.lift = jumpHeight(t, a.Leap, 0.5, 12, 0)
		if center and B.superFrom then
			P.override = B.superFrom:Lerp(center, clamp(t / a.Leap, 0, 1))
		end
		P.crouch = 0.6
		P.stance = 0.3
		P.spin = -t / a.Leap * math.pi * 2
		P.rHand, P.lHand = V3(1.6, 3.0, -1.2), V3(-1.6, 3.0, -1.2)
		P.lFoot, P.rFoot = V3(-1.0, 1.8, -0.8), V3(1.0, 1.6, 0.6)
		return
	end
	if center then
		P.override = center
	end
	if t < a.Tell then
		cupPose(P, 0.5 + 1.1 * clamp((t - a.Leap) / (a.Tell - a.Leap), 0, 1), 1, true)
		P.shake = 0.08
		P.open = (t > a.Tell - 0.5) and 1 or 0
		return
	end
	local tEnd = a.Tell + a.SweepTime
	if t < tEnd then
		pushPose(P, true)
		P.shake = 0.1
		-- he turns with the beam: the server's own sum
		local mid = slot(B, 2)
		if center and mid then
			local dir0 = unitOr(flat(mid - center), B.vfacing)
			local half = math.rad(a.Sweep / 2)
			local u = clamp((t - a.Tell) / a.SweepTime, 0, 1)
			local ang = math.atan2(dir0.X, dir0.Z) + actN(B) * (-half + 2 * half * u)
			P.facing = V3(math.sin(ang), 0, math.cos(ang))
			P.rate = 60
		end
		return
	end
	-- exhausted after it
	Poses.Tired(B, t - tEnd, P)
	P.sweat = 1
end

-- THE MOMENTS EVERY BOSS HAS
-- asleep: meditating cross-legged on his mat, hovering a little
function Poses.Dormant(B, t, P)
	local now = serverNow()
	P.sit = 1
	P.stance = 0
	P.lift = 0.5 + 0.25 * math.sin(now * 1.2)
	P.rHand = V3(1.7, 0.4, -1.3)
	P.lHand = V3(-1.7, 0.4, -1.3)
	P.headPitch = 0.18
	P.eyes = 0
	P.sy = 1 + 0.015 * math.sin(now * 1.4)
end

-- waking: his eyes open, he rises, bows (fist in palm), and drops into his stance
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	if t < 0.9 then
		Poses.Dormant(B, t, P)
		P.eyes = (t > 0.35) and 1 or 0
		P.headPitch = lerp(0.18, 0, smooth((t - 0.35) / 0.4))
		P.glow = (t > 0.35 and t < 0.6) and 1 or 0
		return
	end
	if t < 1.6 then
		-- standing up
		local k = smooth((t - 0.9) / 0.7)
		P.sit = 1 - k
		P.lift = 0.5 * (1 - k)
		P.rHand = V3(1.7, 0.4, -1.3):Lerp(REST_R, k)
		P.lHand = V3(-1.7, 0.4, -1.3):Lerp(REST_L, k)
		return
	end
	if t < 2.35 then
		-- the bow: right fist into his left palm, bending forward and back up
		local k = (t - 1.6) / 0.75
		P.rHand = V3(0.15, 3.2, -2.1)
		P.lHand = V3(-0.15, 3.3, -2.15)
		P.lean = 0.45 * math.sin(math.pi * clamp(k * 1.2, 0, 1))
		P.headPitch = 0.3 * math.sin(math.pi * clamp(k * 1.2, 0, 1))
		return
	end
	-- into his stance, and a "HAH!" flex
	stancePose(P)
	P.bob = 0
	if t > W - 0.55 and t < W - 0.3 then
		P.sy = 1.06
		P.open = 1
		P.glow = 1
	end
end

-- everyone's gone: a whirlwind of petals carries him away
function Poses.Reset(B, t, P)
	local k = clamp(t / 2, 0, 1)
	P.stance = 0
	P.spin = t * t * 6
	P.lift = 3 * smooth(k)
	P.rHand, P.lHand = V3(1.0, 3.2, -2.0), V3(-1.0, 3.2, -2.0)
	P.fade = clamp((t - 0.9) / 0.9, 0, 1)
	P.eyes = 0
end

-- ROUND 2: knocked down to one knee, a burst of ki as he rises roaring (his
-- gi tears), re-ties his headband, back into his stance
function Poses.Break(B, t, P)
	local BT = B.def.BreakTime
	local burstAt = BT * 0.35
	if t < burstAt then
		local k = clamp(t / 0.35, 0, 1)
		P.kneel = k
		P.stance = 0
		P.headPitch = 0.4 * k
		P.rHand = V3(1.2, 1.2, -1.6)
		P.lHand = V3(-1.3, 1.6, -1.4)
		P.glow = clamp((t - 0.3) / (burstAt - 0.3), 0, 1)
		P.shake = 0.05 + 0.15 * P.glow
		return
	end
	local e = t - burstAt
	if e < 0.7 then
		-- roaring, arms flung out
		P.rHand = V3(3.3, 5.2, -0.4)
		P.lHand = V3(-3.3, 5.2, -0.4)
		P.headPitch = -0.35
		P.lean = -0.15
		P.open = 1
		P.glow = 1
		P.sy = 1 + 0.08 * spring(e, 4, 10)
		return
	end
	if e < 1.45 then
		-- re-tying the headband
		P.rHand = V3(0.7, 5.5, 1.3 + 0.15 * math.sin(e * 18))
		P.lHand = V3(-0.7, 5.5, 1.3 - 0.15 * math.sin(e * 18))
		P.headPitch = 0.08
		return
	end
	stancePose(P)
	P.glow = 0.4
end

-- K.O.: reels back, drops to his knees, falls onto his back... his headband
-- drifts away on the wind, and he scatters into cherry blossom petals
function Poses.Death(B, t, P)
	P.stance = 0
	if t < 0.6 then
		local k = t / 0.6
		P.lean = -0.35 * k
		P.headPitch = -0.4 * k
		P.rHand = V3(2.2, 1.4, 0.6)
		P.lHand = V3(-2.2, 1.4, 0.6)
		P.shake = 0.1
		return
	end
	if t < 1.3 then
		P.kneel = smooth((t - 0.6) / 0.4)
		P.headPitch = 0.3
		P.rHand = V3(1.6, 1.0, -0.8)
		P.lHand = V3(-1.6, 1.0, -0.8)
		return
	end
	P.lie = smooth((t - 1.3) / 0.5)
	P.kneel = 1 - P.lie
	P.rHand = V3(2.8, 1.8, 0.2)
	P.lHand = V3(-2.8, 1.8, 0.2)
	P.eyes = 0
	if t > 3.6 then
		-- (scattering away in chunky steps, like an old game)
		P.fade = math.floor(clamp((t - 3.6) / 1.0, 0, 1) * 5 + 0.5) / 5
	end
end

----------------------------------------------------------------------
-- One-off moments in each move (sounds, shouts, bursts, warnings)
----------------------------------------------------------------------
-- his name for a move, shouted in a word bubble over his head
local function yell(B, text, seconds, color)
	local ok = pcall(function()
		shout(B.body.head, text, seconds or 1.1, color or WHITE)
	end)
	return ok
end

-- the start of a charge (only if he holds it): the glow, the rising hum
local function chargeStarts(B, t0, hold)
	if hold <= 0 then
		return
	end
	at(B, t0 + 0.02, function()
		hum(B, hold)
		burst(B.vpos + V3(0, 3, 0), CYAN, 16, 10, 1.2, 0.6, true)
	end)
end

function Starts.Idle(B, t0) end

function Starts.PunchString(B, t0)
	local a = B.def.Attacks.PunchString
	local t1 = t0
	for i = 1, 3 do
		local tHit = t1 + a.Tells[i]
		local showAt = t1
		punchWedge(B, a.Reach, a.Arc, showAt, tHit, i)
		at(B, tHit, function()
			playSound(B.def, (i == 3) and "Heavy" or "Punch", B.vpos, (i == 3) and 1 or 0.8)
			local fist = (i == 1) and B.handL or B.handR
			burst((fist or (B.vpos + V3(0, 4, 0))) + B.vfacing * 1.2, WHITE, (i == 3) and 14 or 8, 14, 0.8, 0.25)
			kick(B.vpos, a.Reach, (i == 3) and 0.7 or 0.35)
			if i == 3 then
				yell(B, "HYAH!", 0.6)
			end
		end)
		t1 = tHit
	end
end

function Starts.DashIn(B, t0) end

function Starts.Dash(B, t0)
	local D = B.def.Movement.Dash
	at(B, t0 + 0.01, function()
		playSound(B.def, "Dash", B.vpos, 0.8)
		burst(B.vpos + V3(0, 0.5, 0), PALE, 10, 12, 1.2, 0.4)
	end)
	ghostTrail(B, t0, t0 + D.Time, 0.05)
end

function Starts.BackHop(B, t0)
	local H = B.def.Movement.BackHop
	at(B, t0 + 0.01, function()
		playSound(B.def, "Dash", B.vpos, 0.6)
	end)
	ghostTrail(B, t0, t0 + H.Time, 0.07, WHITE)
	at(B, t0 + H.Time, function()
		burst(B.vpos + V3(0, 0.4, 0), PALE, 8, 8, 1, 0.35)
	end)
end

function Starts.KazeBlast(B, t0)
	local a = B.def.Attacks.KazeBlast
	local hold = actN(B)
	local k = chargeLevel(B, hold)
	chargeStarts(B, t0, hold)
	local tR = t0 + hold + a.Tell
	-- the lane it'll roll along (pale while he turns to face you)
	lane(B, byCharge(a.Radius, k) * 1.8, 30, 1, 2, function()
		return tR
	end, true)
	at(B, tR - 0.1, function()
		yell(B, "KAZE-BLAST!", 1.1, CYAN)
	end)
	at(B, tR, function()
		playSound(B.def, "Blast", B.vpos, 1)
		burst((B.ballAt or (B.vpos + V3(0, 3.5, 0))) + B.vfacing * 2, CYAN, 20, 16, 1.4, 0.4)
		kick(B.vpos, 20, 0.5, -2)
	end)
end

function SlotSpawns.KazeBlast(B, i, spot, t0)
	if i == 2 then
		local a = B.def.Attacks.KazeBlast
		local hold = actN(B)
		local from = slot(B, 1)
		if from then
			kiBall(B, from, spot, t0 + hold + a.Tell, chargeLevel(B, hold))
		end
	end
end

function Starts.FakeCharge(B, t0)
	-- (just like a real charge: the glow and the hum)
	chargeStarts(B, t0, math.max(actN(B), 0.4))
	lane(B, B.def.Attacks.KazeBlast.Radius[1] * 1.8, 30, 1, 2, function()
		return t0 + 2
	end, true)
end

function Starts.RisingDragon(B, t0)
	local a = B.def.Attacks.RisingDragon
	local hold = actN(B)
	local k = chargeLevel(B, hold)
	chargeStarts(B, t0, hold)
	local tA = t0 + hold + a.Tell
	dragonRing(B, byCharge(a.Radius, k), t0, t0 + hold, tA)
	at(B, tA, function()
		yell(B, "RISING DRAGON!", 1.2, YELLOW)
		playSound(B.def, "Dragon", B.vpos, 1)
		shockRing(B, B.vpos, 1, byCharge(a.Radius, k) * 1.2, 0.3, WHITE)
		burst(B.vpos + V3(0, 1, 0), YELLOW, 20, 24, 1.4, 0.5, true)
		kick(B.vpos, 20, 0.7, -3)
	end)
	ghostTrail(B, tA, tA + byCharge(a.Air, k) * 0.42, 0.06, YELLOW)
	at(B, tA + byCharge(a.Air, k), function()
		playSound(B.def, "Land", B.vpos, 0.8)
		burst(B.vpos + V3(0, 0.5, 0), PALE, 14, 14, 1.4, 0.45)
		kick(B.vpos, 14, 0.4)
	end)
end

function Starts.TornadoKick(B, t0)
	local a = B.def.Attacks.TornadoKick
	local hold = actN(B)
	local k = chargeLevel(B, hold)
	chargeStarts(B, t0, hold)
	local tS = t0 + hold + a.Tell
	lane(B, a.Radius * 2, byCharge(a.Distance, k), 1, 2, function()
		local from, to = slot(B, 1), slot(B, 2)
		local len = (from and to) and flat(to - from).Magnitude or byCharge(a.Distance, k)
		return tS + len / byCharge(a.Speed, k)
	end)
	at(B, tS - 0.15, function()
		yell(B, "TORNADO KICK!", 1.2, CYAN)
	end)
	at(B, tS, function()
		playSound(B.def, "Tornado", B.vpos, 1)
		burst(B.vpos + V3(0, 0.5, 0), PALE, 14, 14, 1.4, 0.4)
	end)
	ghostTrail(B, tS, tS + 2, 0.08)
end

function Starts.KiFocus(B, t0)
	local a = B.def.Attacks.KiFocus
	at(B, t0 + 0.05, function()
		playSound(B.def, "Focus", B.vpos, 1)
		shockRing(B, B.vpos, 2, 10, 0.5, CYAN)
	end)
	-- "HAAAA...", growing
	at(B, t0 + 0.1, function()
		local label = nil
		pcall(function()
			label = shout(B.body.head, "HA", a.Time, CYAN)
		end)
		if label then
			local start = serverNow()
			addTelegraph(B, {
				update = function(now)
					if B.action ~= "KiFocus" or now > start + a.Time then
						return false
					end
					label.Text = "H" .. string.rep("A", 1 + math.floor((now - start) * 4)) .. "..."
					return true
				end,
				cleanup = function() end,
			})
		end
	end)
	risingPebbles(B, t0 + a.Time)
end

function Starts.Stagger(B, t0)
	at(B, t0 + 0.02, function()
		playSound(B.def, "Stagger", B.vpos, 1)
		burst(B.vpos + V3(0, 5, 0), CYAN, 24, 16, 1.2, 0.5)
		burst(B.vpos + V3(0, 5, 0), YELLOW, 10, 10, 1, 0.5)
		kick(B.vpos, 16, 0.5)
	end)
end

function Starts.Tired(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Tired", B.vpos, 1)
		yell(B, "*pant* *pant*", 1.4, PALE)
	end)
end

function Starts.Super(B, t0)
	local a = B.def.Attacks.Super
	B.superFrom = B.vpos
	at(B, t0 + 0.01, function()
		playSound(B.def, "Super", B.vpos, 1)
		pcall(function()
			bigText("SUPER!", { color = CYAN, sub = "HIDE BEHIND A PILLAR!", subColor = YELLOW, size = 72, hold = 1.6 })
		end)
		Body._flash(0.55, 0.35)
		kick(B.vpos, 300, 0.8, -10)
		burst(B.vpos + V3(0, 4, 0), CYAN, 40, 22, 2, 0.8, true)
	end)
	ghostTrail(B, t0, t0 + a.Leap, 0.07)
	at(B, t0 + a.Leap, function()
		playSound(B.def, "Land", B.vpos, 1)
		shockRing(B, B.vpos, 2, 18, 0.4, CYAN)
		kick(B.vpos, 30, 0.6, -2)
		hum(B, a.Tell - a.Leap)
	end)
	superFan(B, a, t0)
	pillarGlow(B, t0 + a.Tell + a.SweepTime)
	superBeam(B, a, t0)
	at(B, t0 + a.Tell - 0.25, function()
		yell(B, "HAAAAAA!!", 1.6, CYAN)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Beam", B.vpos, 1)
		Body._flash(0.35, 0.25)
		kick(B.vpos, 300, 1.4, -6)
	end)
end

function Starts.Wake(B, t0)
	local W = B.def.WakeTime
	at(B, t0 + 0.35, function()
		burst(B.vpos + V3(0, 6, 0), CYAN, 10, 6, 0.8, 0.6, true)
	end)
	at(B, t0 + 1.0, function()
		if B.here then
			pcall(function()
				bigText("ROUND 1", { color = WHITE, size = 64, hold = 1.1 })
			end)
			playSound(B.def, "Round1", B.vpos, 1)
		end
	end)
	at(B, t0 + 1.6, function()
		playSound(B.def, "Land", B.vpos, 0.4)
	end)
	at(B, t0 + W - 0.55 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W - 0.55, function()
		burst(B.vpos + V3(0, 4, 0), CYAN, 30, 18, 1.4, 0.6, true)
		shockRing(B, B.vpos, 2, 16, 0.4, CYAN)
		kick(B.vpos, 30, 0.7, -3)
		yell(B, "HAH!", 0.7)
	end)
	at(B, t0 + W - 0.45, function()
		if B.here then
			pcall(function()
				bigText("FIGHT!", { color = RED, size = 80, hold = 0.9 })
			end)
			playSound(B.def, "Fight", B.vpos, 1)
		end
	end)
end

function Starts.Dormant(B, t0)
	-- (back home after the whirlwind: he settles on his mat in a swirl of petals)
	if B.prevAction == "Reset" then
		burst(B.vpos + V3(0, 3, 0), PINK, 30, 14, 1.2, 1.2, true)
		burst(B.vpos + V3(0, 3, 0), WHITE, 14, 10, 1, 1, true)
	end
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		playSound(B.def, "Dash", B.vpos, 0.6)
	end)
	for k = 0, 3 do
		at(B, t0 + 0.3 + k * 0.35, function()
			burst(B.vpos + V3(0, 2 + k, 0), (k % 2 == 0) and PINK or WHITE, 18, 16, 1, 0.9, true)
		end)
	end
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + 0.05, function()
		playSound(def, "Break", B.vpos, 0.6)
		burst(B.vpos + V3(0, 1, 0), PALE, 16, 12, 1.4, 0.5)
	end)
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, CYAN)
		shockRing(B, B.vpos, 2, def.BreakReach * 0.6, 0.4, WHITE)
		burst(B.vpos + V3(0, 6, 0), CYAN, 50, 36, 2, 1, true)
		burst(B.vpos + V3(0, 6, 0), WHITE, 20, 20, 1.4, 0.8)
		playSound(def, "Break", B.vpos, 1)
		kick(B.vpos, def.BreakReach, 1.3, -5)
		yell(B, "HAAAAA!!", 1.0, CYAN)
	end)
	at(B, t0 + def.BreakTime * 0.35 + 0.35, function()
		if B.here then
			pcall(function()
				bigText("ROUND 2", { color = WHITE, size = 64, hold = 1.0 })
			end)
			playSound(def, "Round2", B.vpos, 1)
		end
	end)
	at(B, t0 + def.BreakTime - 0.4, function()
		if B.here then
			pcall(function()
				bigText("FIGHT!", { color = RED, size = 80, hold = 0.9 })
			end)
			playSound(def, "Fight", B.vpos, 1)
		end
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.05, function()
		playSound(def, "Death", B.vpos, 1)
		if B.here then
			pcall(function()
				bigText("K.O.!", { color = RED, size = 96, hold = 1.8 })
			end)
			playSound(def, "KO", B.vpos, 1)
			Body._flash(0.6, 0.5)
		end
	end)
	at(B, t0 + 1.3, function()
		burst(B.vpos + V3(0, 0.5, 0), PALE, 18, 12, 1.6, 0.6)
		kick(B.vpos, 20, 0.6, -2)
	end)
	at(B, t0 + 2.2, function()
		-- the headband slips free and floats away on the wind
		local knot = B.body.bandKnot
		B.bandFree = { t0 = serverNow(), from = knot.Position }
	end)
	at(B, t0 + 2.5, function()
		if B.here and B.perfect then
			pcall(function()
				bigText("PERFECT!", { color = YELLOW, sub = "not a scratch on you", size = 72, hold = 2 })
			end)
			playSound(def, "Perfect", B.vpos, 1)
		end
	end)
	at(B, t0 + 3.6, function()
		-- scattering into cherry blossom petals
		for k = 1, 5 do
			burst(B.vpos + V3(0, 1 + k * 1.2, 0), (k % 2 == 0) and PINK or WHITE, 18, 12, 1, 1.4, true)
		end
	end)
end

----------------------------------------------------------------------
-- His ki meter (under the boss bar), and a hint over his head
----------------------------------------------------------------------
local hud = nil
local function buildHud()
	local Players = game:GetService("Players")
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "KazeKi"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.IgnoreGuiInset = false
	gui.Enabled = false
	gui:SetAttribute("RetroSkip", true) -- (it has its own pixel look)
	gui.Parent = playerGui
	local holder = Instance.new("Frame")
	holder.Name = "Meter"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 101)
	holder.Size = UDim2.new(0.52, 0, 0, 15)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(780, 15)
	limit.MinSize = Vector2.new(300, 15)
	limit.Parent = holder
	underBar(holder) -- (it moves and shrinks with the boss bar on a small screen)
	local function text(parent, t, color, size)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = t
		l.TextColor3 = color
		l.TextScaled = true
		l.Font = Enum.Font.Arcade
		if PIXEL_FONT then
			l.FontFace = PIXEL_FONT
		end
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = INK
		l.Size = size
		l.Parent = parent
		return l
	end
	local kiLabel = text(holder, "KI", CYAN, UDim2.new(0, 26, 1, 0))
	-- three bars
	local segs = {}
	for i = 1, 3 do
		local back = Instance.new("Frame")
		back.Name = "Bar" .. i
		back.BackgroundColor3 = INK
		back.BorderSizePixel = 0
		back.Position = UDim2.new((i - 1) / 3 * 0.74, 32 + (i - 1) * 2, 0, 2)
		back.Size = UDim2.new(0.74 / 3, -4, 1, -4)
		back.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = WHITE
		stroke.Thickness = 2
		stroke.LineJoinMode = Enum.LineJoinMode.Miter
		stroke.Parent = back
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = CYAN
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = back
		segs[i] = { back = back, fill = fill, stroke = stroke }
	end
	local maxLabel = text(holder, "MAX", YELLOW, UDim2.new(0.74, 0, 1.6, 0))
	maxLabel.Position = UDim2.new(0, 32, -0.3, 0)
	maxLabel.Visible = false
	-- his cancels: diamonds at the right end
	local diamonds = {}
	for i = 1, 5 do
		local d = Instance.new("Frame")
		d.Name = "Cancel" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Rotation = 45
		d.BorderSizePixel = 0
		d.BackgroundColor3 = WHITE
		d.Size = UDim2.fromOffset(9, 9)
		d.Position = UDim2.new(1, -8 - (5 - i) * 15, 0.5, 0)
		d.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = 2
		stroke.Parent = d
		diamonds[i] = d
	end
	-- the little +KI / -KI that pops up beside the meter
	local pop = text(holder, "", CYAN, UDim2.new(0, 70, 1.4, 0))
	pop.AnchorPoint = Vector2.new(0, 1)
	pop.Position = UDim2.new(0, 30, 0, -2)
	pop.TextTransparency = 1
	pop.TextStrokeTransparency = 1
	hud = { gui = gui, holder = holder, kiLabel = kiLabel, segs = segs, maxLabel = maxLabel, diamonds = diamonds, pop = pop }
	return hud
end

local function popText(t, color)
	if not hud then
		return
	end
	local pop = hud.pop
	pop.Text = t
	pop.TextColor3 = color
	pop.TextTransparency, pop.TextStrokeTransparency = 0, 0
	pop.Position = UDim2.new(0, 30, 0, -2)
	tween(pop, 0.7, { Position = UDim2.new(0, 30, 0, -14), TextTransparency = 1, TextStrokeTransparency = 1 })
end

-- the hint over his head while he's open
local HINTS = {
	Tired = "TIRED! HIT HIM!",
	Stagger = "STUNNED! HIT HIM!",
	KiFocus = "PUNCH HIM TO BREAK IT!",
}
local function hintOf(B)
	local action = B.action
	local hint = HINTS[action]
	if not hint and (action == "KazeBlast" or action == "RisingDragon" or action == "TornadoKick" or action == "FakeCharge") then
		local hold = actN(B)
		if hold > 0 and serverNow() < (B.actionStart or 0) + hold then
			hint = "CHARGING! BREAK IT!"
		end
	end
	return hint
end

local function stepHint(B, show)
	local want = show and hintOf(B) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(os.clock() * 6) % 2 == 0) and 0 or 0.25
		end
		return
	end
	B.hintText = want
	if B.hintGui then
		B.hintGui:Destroy()
		B.hintGui, B.hintLabel = nil, nil
	end
	if want then
		local bb = Instance.new("BillboardGui")
		bb.Name = "KazeHint"
		bb.Size = UDim2.fromOffset(260, 30)
		bb.StudsOffsetWorldSpace = V3(0, 3.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.body.head
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.Arcade
		if PIXEL_FONT then
			label.FontFace = PIXEL_FONT
		end
		label.TextColor3 = YELLOW
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = INK
		label.Text = want
		label.Parent = bb
		bb.Parent = B.body.folder
		B.hintGui, B.hintLabel = bb, label
	end
end

-- a quick white flash over the whole screen (the Super, the K.O.)
local flashGui = nil
function Body._flash(alpha, seconds)
	pcall(function()
		if not flashGui then
			local Players = game:GetService("Players")
			local gui = Instance.new("ScreenGui")
			gui.Name = "KazeFlash"
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.DisplayOrder = 25
			gui:SetAttribute("RetroSkip", true)
			local f = Instance.new("Frame")
			f.BackgroundColor3 = WHITE
			f.BorderSizePixel = 0
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundTransparency = 1
			f.Parent = gui
			gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			flashGui = { gui = gui, frame = f }
		end
		flashGui.frame.BackgroundTransparency = 1 - alpha
		tween(flashGui.frame, seconds, { BackgroundTransparency = 1 })
	end)
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- what his moves are made of: ki
function Body.fx(def)
	return { color = CYAN, deep = BLUE, rock = STONE_DARK, material = Enum.Material.Neon, solid = true }
end

-- a new move began
function Body.onAction(B, name, t0, now)
	if name == "Wake" or name == "Dormant" or name == "Reset" then
		B.bandFree = nil
		B.chains = nil
	end
	if name == "Wake" then
		-- (a fresh fight: were you ever hurt in it? PERFECT! if not)
		B.perfect = true
		local root = myRoot()
		local hum = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		B.myHealth = hum and hum.Health or nil
	end
end

-- joined while round 2 was already on
function Body.lateBreak(B)
	B.phase2Look = true
end

-- every frame, whatever he's doing: the white flash of a cancel, your missed
-- punches feeding him, the pillars crumbling and mending
function Body.signs(B, state)
	local m = B.model
	local now = serverNow()
	local ca = m:GetAttribute("CancelAt")
	if ca ~= B.seenCancel then
		local fresh = B.seenCancel ~= nil or (type(ca) == "number" and now - ca < 0.5)
		B.seenCancel = ca
		if fresh and type(ca) == "number" and now - ca < 0.5 then
			B.cancelFlashUntil = os.clock() + 0.12
			burst(B.vpos + V3(0, 4, 0), WHITE, 16, 16, 1.2, 0.3)
			playSound(B.def, "Cancel", B.vpos, 0.8)
			yell(B, "CANCEL!", 0.5, WHITE)
		end
	end
	local wa = m:GetAttribute("WhiffAt")
	if wa ~= B.seenWhiff then
		B.seenWhiff = wa
		if type(wa) == "number" and now - wa < 0.5 then
			popText("+KI", CYAN)
			B.meterFlash = os.clock()
		end
	end
	local kh = m:GetAttribute("KiHitAt")
	if kh ~= B.seenKiHit then
		B.seenKiHit = kh
		if type(kh) == "number" and now - kh < 0.5 then
			popText("-KI", RED)
			B.meterDrop = os.clock()
			burst(B.vpos + V3(0, 5, 0), CYAN, 8, 10, 0.8, 0.3)
		end
	end
	local kf = m:GetAttribute("KiFlareAt")
	if kf ~= B.seenFlare then
		B.seenFlare = kf
		if type(kf) == "number" and now - kf < 0.5 then
			popText("MAX!", YELLOW)
			burst(B.vpos + V3(0, 4, 0), CYAN, 40, 24, 1.8, 0.7, true)
			shockRing(B, B.vpos, 2, 14, 0.4, CYAN)
			yell(B, "HAAA!", 0.8, CYAN)
			playSound(B.def, "Focus", B.vpos, 0.8)
		end
	end
	-- the pillars
	for _, pl in ipairs(pillarsOf(B)) do
		local broken = pl.model:GetAttribute("Broken") == true
		if pl.wasBroken == nil then
			pl.wasBroken = broken
		elseif broken ~= pl.wasBroken then
			pl.wasBroken = broken
			if broken then
				crumble(B, pl)
			else
				-- mended (round 2, or a reset): a puff as it's back
				burst(pl.core.Position, PALE, 20, 12, 2, 0.7, true)
				burst(pl.core.Position + V3(0, 6, 0), PINK, 10, 10, 1, 0.8, true)
			end
		end
	end
	local _ = state
end

-- every frame: his meter under the boss bar (while you're here and he's
-- awake), the hint over his head, and whether you've been hurt this fight
function Body.senses(B, dt, here, awake, state)
	B.here = here
	local show = here and awake
	if show and not hud then
		pcall(buildHud)
	end
	if B.perfect and B.myHealth then
		local root = myRoot()
		local hum = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health < B.myHealth - 0.01 then
			B.perfect = false
		end
	end
	stepHint(B, show)
	if not hud then
		return
	end
	hud.gui.Enabled = show
	if not show then
		return
	end
	local def = B.def
	local ki = B.model:GetAttribute("Ki") or 0
	B.kiShown = (B.kiShown or ki) + (ki - (B.kiShown or ki)) * math.min(1, dt * 12)
	local full = ki >= def.Ki.Bar * def.Ki.Bars
	local t = os.clock()
	for i, sg in ipairs(hud.segs) do
		local k = clamp((B.kiShown - (i - 1) * def.Ki.Bar) / def.Ki.Bar, 0, 1)
		sg.fill.Size = UDim2.fromScale(k, 1)
		local whole = k >= 0.999
		local flashing = (B.meterFlash and t - B.meterFlash < 0.2) or false
		sg.fill.BackgroundColor3 = (flashing or (full and math.floor(t * 8) % 2 == 0)) and WHITE or (whole and CYAN or BLUE)
		sg.stroke.Color = (B.meterDrop and t - B.meterDrop < 0.25) and RED or (whole and YELLOW or WHITE)
	end
	hud.maxLabel.Visible = full and (math.floor(t * 4) % 2 == 0)
	local cancels = B.model:GetAttribute("Cancels") or 0
	local most = def.Cancels[B.phase2Look and 2 or 1] or 3
	for i, d in ipairs(hud.diamonds) do
		local idx = i - (5 - most)
		d.Visible = idx >= 1
		d.BackgroundColor3 = (idx >= 1 and idx <= cancels) and WHITE or RGB(58, 68, 102)
	end
	local _ = state
end

return Body
