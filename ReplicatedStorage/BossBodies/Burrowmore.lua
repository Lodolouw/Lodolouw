--[[
	Burrowmore  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Burrowmore")

	How Knight Burrowmore, the Honourable Digger (floor 3's boss, Config.Bosses[3])
	looks on your screen: a chunky 8-bit knight about three times your height -
	blue armour with gold trim, a helmet with a T-shaped visor (two eyes glowing
	in the slit) and curly golden horns, big gold-edged shoulder plates, a red
	cape that streams out behind him when he jumps or charges, and his trusty
	shovel with a golden spade of a blade. His relics come out when he uses
	them: an anchor on a chain, and a fire stick.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Burrowmore.lua, where each move is explained):
	  * Poses[move]   his body t seconds into a move: crouching, leaping with his
	                  shovel pointing down, swinging, digging, charging...
	  * Starts[move]  the move's sounds, bursts of dirt and sparks, camera kicks,
	                  and its warnings on the floor, all timed on the server's clock
	  * SlotSpawns    warnings for the spots the server fills in as a move goes:
	                  the red circle under a drop (it follows you, then flashes and
	                  locks), each pogo landing, each clod, the anchor's landing,
	                  each fireball rolling along its red strip
	  * the gem rain's circles and falling treasure (from his RainAt / RainK /
	    Rain1.. attributes - it carries on under his next moves)
	  * the moments every boss has: kneeling asleep, getting up (pulling his
	    shovel out of the dirt, a twirl, a pose), burrowing away when everyone
	    leaves, NO QUARTER! (his shoulder plates fly off, cracks glow gold in his
	    armour), and the end: down on one knee... gone in a pop of pixels, and a
	    treasure chest bursting up out of the dirt where he knelt

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: crouch, kneel, stride, twist, roll,
	headPitch, rHand / lHand (where his hands are, in his chest's space),
	shovelDir (which way the shovel points, same space), shovelSpin, load (dirt
	on the shovel), stars (dizzy), wand (the fire stick), capeLift, glow.
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, easeOut, easeOutBack, spring, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, findSound, addTelegraph, shockRing, at, SLOT_NAMES

function Body.init(kit)
	serverNow, clamp, lerp, smooth, easeOut, easeOutBack = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.easeOut, kit.easeOutBack
	spring, flat = kit.spring, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, findSound, addTelegraph, shockRing, at, SLOT_NAMES = kit.kick, kit.playSound, kit.findSound, kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES
	-- WARM-UP: his sounds and music loaded in the background as soon as you
	-- join, so none of them stalls or plays silent the first time
	task.delay(2.5, function()
		pcall(function()
			local list = {}
			local def = nil
			for _, d in pairs(require(game:GetService("ReplicatedStorage"):WaitForChild("Config")).Bosses or {}) do
				if d.Short == "Burrowmore" then
					def = d
				end
			end
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

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config
local RED = RGB(228, 59, 68)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local WOOD = RGB(115, 62, 57)
local LEATHER = RGB(62, 39, 49)
local DIRT = RGB(194, 133, 105)
local DIRT_DARK = RGB(184, 111, 80)
local STEEL = RGB(139, 155, 180)
local STEEL_DARK = RGB(90, 105, 136)
local FIRE = RGB(247, 118, 34)
local FIRE_HOT = RGB(254, 231, 97)
local GLOW_ORANGE = RGB(247, 118, 34)
local GEMS = { RGB(44, 232, 245), RGB(255, 0, 68), RGB(99, 199, 77), RGB(181, 80, 136), RGB(254, 231, 97) }
local PIXEL_FONT = nil
pcall(function()
	PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- The same jump sum as the server's (Bosses/Burrowmore.lua): up fast for
-- `rise` of the `air` seconds, held at the top for `hang`, then dropping
-- faster and faster - so he's drawn exactly where he is.
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

-- `dir` turned round the up axis by `a` radians
local function turnY(dir, a)
	local c, s = math.cos(a), math.sin(a)
	return V3(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
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
	p.CFrame = CFrame.lookAt(center, center + dir, upHint or V3(0, 1, 0))
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
	-- the bend, square to the limb
	local perp = bendDir - dir * bendDir:Dot(dir)
	perp = unitOr(perp, V3(0, 0, -1))
	-- (law of cosines: how far along the limb the joint sits, and how far out)
	local along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local out = math.sqrt(math.max(l1 * l1 - along * along, 0))
	return a + dir * along + perp * out, c
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, armour = {}, trims = {}, all = {} }
	local armour, deep, trim = def.Color, def.DeepColor, def.TrimColor or RGB(254, 174, 52)
	local cape = def.CapeColor or RED
	local function add(name, color, material, kind)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, p)
		if kind == "armour" then
			table.insert(body.armour, { part = p, color = color })
		elseif kind == "trim" then
			table.insert(body.trims, { part = p, color = color })
		end
		return p
	end
	-- legs
	body.boots, body.shins, body.thighs, body.knees = {}, {}, {}, {}
	for i = 1, 2 do
		body.boots[i] = add("Boot", deep, nil, "armour")
		body.shins[i] = add("Shin", armour, nil, "armour")
		body.thighs[i] = add("Thigh", deep, nil, "armour")
		body.knees[i] = add("Knee", trim, nil, "trim")
	end
	-- middle
	body.belt = add("Belt", LEATHER)
	body.buckle = add("Buckle", trim, nil, "trim")
	body.tassets = { add("Tasset", armour, nil, "armour"), add("Tasset", armour, nil, "armour") }
	body.chest = add("Chest", armour, nil, "armour")
	body.chestShine = add("ChestShine", RGB(44, 232, 245), nil, "armour")
	body.collar = add("Collar", trim, nil, "trim")
	body.chestBand = add("ChestBand", trim, nil, "trim")
	-- shoulders and arms
	body.pauldrons, body.pauldronTrims = {}, {}
	body.upperArms, body.gauntlets, body.fists = {}, {}, {}
	for i = 1, 2 do
		body.pauldrons[i] = add("Pauldron", armour, nil, "armour")
		body.pauldronTrims[i] = add("PauldronTrim", trim, nil, "trim")
		body.upperArms[i] = add("UpperArm", deep, nil, "armour")
		body.gauntlets[i] = add("Gauntlet", armour, nil, "armour")
		body.fists[i] = add("Fist", deep, nil, "armour")
	end
	-- the head: helmet, visor, eyes, crest, curly horns
	body.helmet = add("Helmet", armour, nil, "armour")
	body.brow = add("HelmetBrow", deep, nil, "armour")
	body.crest = add("Crest", trim, nil, "trim")
	body.visor = add("VisorSlit", def.CoreColor or INK)
	body.nose = add("VisorNose", def.CoreColor or INK)
	body.eyes = { add("Eye", def.EyeColor, Enum.Material.Neon), add("Eye", def.EyeColor, Enum.Material.Neon) }
	body.horns = {}
	for i = 1, 8 do
		-- (every other block a shade deeper, so the curl reads)
		body.horns[i] = add("Horn", (i % 2 == 0) and RGB(247, 118, 34) or trim, nil, "trim")
	end
	-- the cape
	body.cape = add("Cape", cape)
	body.capeTail = add("CapeTail", cape)
	-- the shovel
	body.handle = add("ShovelHandle", WOOD)
	body.grip = add("ShovelGrip", trim, nil, "trim")
	body.blade = add("ShovelBlade", trim, nil, "trim")
	body.tip = add("ShovelTip", trim, nil, "trim")
	body.shine = add("ShovelShine", RGB(254, 231, 97))
	body.load = add("DirtLoad", DIRT)
	-- the relics
	body.anchor = {
		shank = add("AnchorShank", STEEL),
		stock = add("AnchorStock", STEEL_DARK),
		ring = add("AnchorRing", STEEL_DARK),
		arms = { add("AnchorArm", STEEL), add("AnchorArm", STEEL) },
		flukes = { add("AnchorFluke", STEEL_DARK), add("AnchorFluke", STEEL_DARK) },
	}
	body.links = {}
	for i = 1, 10 do
		body.links[i] = add("ChainLink", STEEL_DARK)
	end
	body.wand = add("FireStick", WOOD)
	body.wandGem = add("FireGem", FIRE, Enum.Material.Neon)
	-- dizzy stars
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", RGB(254, 231, 97), Enum.Material.Neon)
	end
	-- NO QUARTER!: cracks in the chest plate, glowing gold
	body.cracks, body.seams = {}, {}
	for i = 1, 3 do
		body.cracks[i] = add("Crack", INK)
		body.seams[i] = add("Seam", trim, Enum.Material.Neon)
	end
	-- his shadow on the floor (round, so you can read where he'll come down)
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0, folder)
	-- gold sparkles off him in phase two
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "NoQuarterAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(trim, RGB(254, 231, 97))
	aura.LightEmission = 1
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	aura.Lifetime = NumberRange.new(0.6, 1.2)
	aura.Speed = NumberRange.new(2, 5)
	aura.Acceleration = V3(0, 6, 0)
	aura.SpreadAngle = Vector2.new(60, 60)
	aura.Rate = 0
	aura.Parent = body.chest
	body.aura = aura
	-- each part vanishes at its own moment when he pops into pixels, and
	-- some parts decide for themselves whether they show (see applyPose)
	body.popAt, body.selfShown = {}, {}
	local SELF = { Pauldron = true, PauldronTrim = true, Crack = true, Seam = true, DirtLoad = true, FireStick = true,
		FireGem = true, DizzyStar = true, ChainLink = true, Eye = true }
	for i, p in ipairs(body.all) do
		body.popAt[p] = ((i * 37) % 23) / 23
		body.selfShown[p] = SELF[p.Name] or string.sub(p.Name, 1, 6) == "Anchor"
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- (his resting stance: shovel held out in front, blade low; left hand loose)
local CARRY_R = V3(1.9, 2.1, -1.9)
local CARRY_L = V3(-2.4, 1.7, -0.5)
local CARRY_DIR = V3(0.1, -0.6, -0.8).Unit

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

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 10
	local model = B.model
	-- walking: legs swing while the server says he's moving
	local moving = model:GetAttribute("Moving") == true
	B.walk = smoothTo(B, "walkS", moving and 1 or 0, 8, dt)
	B.stridePhase = (B.stridePhase or 0) + dt * 9 * math.max(B.walk, 0.15)
	local stride = P.stride or (math.sin(B.stridePhase) * B.walk)
	-- (everything eases between poses, so nothing snaps; P.snap = a moment that must be exact)
	local rate = P.snap and 60 or (P.rate or 16)
	local crouch = smoothTo(B, "crouchS", clamp(P.crouch or 0, 0, 1), rate, dt)
	local kneel = smoothTo(B, "kneelS", clamp(P.kneel or 0, 0, 1), rate, dt)
	local lean = smoothTo(B, "leanS", P.lean or 0, rate, dt)
	local twist = smoothTo(B, "twistS", P.twist or 0, rate, dt)
	local roll = smoothTo(B, "rollS", P.roll or 0, rate, dt)
	local headPitch = smoothTo(B, "headS", P.headPitch or 0, rate, dt)
	local rHandT = smoothTo(B, "rHandS", P.rHand or CARRY_R, rate, dt)
	local lHandT = smoothTo(B, "lHandS", P.lHand or CARRY_L, rate, dt)
	local shovelDirT = smoothTo(B, "shovelS", P.shovelDir or CARRY_DIR, rate, dt)
	local capeLift = smoothTo(B, "capeS", P.capeLift or 0, 10, dt)
	local sx, sy = P.sx or 1, P.sy or 1
	local sink = P.sink or 0
	local fade = P.fade or 0
	local phase2 = B.phase2Look

	-- a punch landing: the armour blinks white (8-bit hit flash)
	local flash = B.flashAt and (os.clock() - B.flashAt) < 0.1

	local jitter = V3(0, 0, 0)
	if P.shake > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local groundPos = ground + jitter + V3(0, P.lift - sink * 15 * u, 0)
	local base = CFrame.lookAt(groundPos, groundPos + facing)

	-- LEGS (two pieces each, bending forward at the knee)
	local hipY = (4.8 - 1.5 * crouch - 2.3 * kneel) * u * sy
	local legX = (1.25 + 0.35 * crouch) * u * sx
	local L1, L2 = 2.0 * u * sy, 2.0 * u * sy
	local forward = base.LookVector
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local hip = base * V3(side * legX, hipY, 0)
		-- where the ankle goes: striding, crouched wide, or (kneeling) the right
		-- knee down with its foot behind and the left foot planted in front
		local fz = -side * stride * 1.3 * u
		local liftFoot = math.max(0, -side * stride) * 0.6 * u
		if kneel > 0 then
			fz = lerp(fz, (side == 1) and 2.3 * u or -1.7 * u, kneel)
			liftFoot = liftFoot * (1 - kneel)
		end
		local ankle = base * V3(side * legX * 1.05, 1.25 * u + liftFoot, fz)
		local knee, ankle2 = twoBone(hip, ankle, L1, L2, forward)
		if kneel > 0.5 and side == 1 then
			-- (the kneeling knee rests on the floor)
			knee = knee:Lerp(base * V3(side * legX, 0.7 * u, 0.4 * u), (kneel - 0.5) * 2)
		end
		stretch(body.thighs[i], hip, knee, 1.9 * u * sx, 1.9 * u, forward)
		stretch(body.shins[i], knee, ankle2, 1.75 * u * sx, 1.75 * u, forward)
		local kn = body.knees[i]
		kn.Size = V3(1.35, 1.15, 0.7) * u
		kn.CFrame = CFrame.lookAt(knee, knee + forward) * CFrame.new(0, 0, -0.8 * u)
		local boot = body.boots[i]
		boot.Size = V3(2.0 * u * sx, 1.35 * u, 2.8 * u)
		boot.CFrame = CFrame.lookAt(ankle2, ankle2 + forward) * CFrame.new(0, -0.6 * u, -0.4 * u)
	end

	-- THE UPPER BODY: from the hips, leaning, twisting and tilting
	local torso = base * CFrame.new(0, hipY, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, roll)
	local up, look, right = torso.UpVector, torso.LookVector, torso.RightVector
	body.belt.Size = V3(4.5 * u * sx, 1.0 * u * sy, 2.9 * u)
	body.belt.CFrame = torso * CFrame.new(0, 0.5 * u * sy, 0)
	body.buckle.Size = V3(1.1, 0.8, 0.3) * u
	body.buckle.CFrame = torso * CFrame.new(0, 0.5 * u * sy, -1.5 * u)
	for i, tp in ipairs(body.tassets) do
		local side = (i == 1) and -1 or 1
		tp.Size = V3(1.8 * u, 1.4 * u, 0.45 * u)
		tp.CFrame = torso * CFrame.new(side * 1.15 * u, -0.45 * u * sy, -1.35 * u) * CFrame.Angles(0.15 + 0.3 * crouch, 0, 0)
	end
	local chestH = 3.5 * u * sy
	body.chest.Size = V3(4.9 * u * sx, chestH, 3.1 * u)
	body.chest.CFrame = torso * CFrame.new(0, 1.0 * u * sy + chestH / 2, 0)
	body.chestShine.Size = V3(0.8 * u, 1.5 * u * sy, 0.1)
	body.chestShine.CFrame = torso * CFrame.new(-1.4 * u, 1.0 * u * sy + chestH * 0.62, -1.58 * u)
	body.chestBand.Size = V3(5.0 * u * sx, 0.5 * u, 3.2 * u)
	body.chestBand.CFrame = torso * CFrame.new(0, 1.0 * u * sy + chestH * 0.3, 0)
	body.collar.Size = V3(3.3 * u, 0.6 * u, 3.3 * u)
	body.collar.CFrame = torso * CFrame.new(0, 1.0 * u * sy + chestH + 0.15 * u, 0)
	-- the cracks (only once his armour has broken)
	local crackSpots = { { -0.9, 0.7, 0.5 }, { 0.6, 0.4, -0.6 }, { 0.2, 0.15, 0.9 } }
	for i, c in ipairs(crackSpots) do
		local show = phase2 and fade < 0.4
		local cf = torso * CFrame.new(c[1] * u, 1.0 * u * sy + chestH * c[2] + 0.4 * u, -1.61 * u) * CFrame.Angles(0, 0, c[3])
		body.cracks[i].Size = V3(0.3 * u, 1.3 * u, 0.1)
		body.cracks[i].CFrame = cf
		body.cracks[i].Transparency = show and 0 or 1
		body.seams[i].Size = V3(0.14 * u, 1.1 * u, 0.12)
		body.seams[i].CFrame = cf * CFrame.new(0.2 * u, 0, -0.02)
		local glow = 0.5 + 0.5 * math.sin(os.clock() * 5 + i)
		body.seams[i].Transparency = show and (glow > 0.3 and 0 or 0.5) or 1
	end

	-- the head
	local neckY = 1.0 * u * sy + chestH
	local head = torso * CFrame.new(0, neckY + 1.8 * u * sy, -0.1 * u) * CFrame.Angles(-headPitch, 0, 0)
	body.helmet.Size = V3(3.9 * u, 3.6 * u * sy, 3.9 * u)
	body.helmet.CFrame = head
	body.brow.Size = V3(4.0 * u, 0.6 * u, 4.0 * u)
	body.brow.CFrame = head * CFrame.new(0, 0.95 * u * sy, 0)
	body.crest.Size = V3(0.6 * u, 0.6 * u, 4.1 * u)
	body.crest.CFrame = head * CFrame.new(0, 1.8 * u * sy + 0.3 * u, 0)
	body.visor.Size = V3(3.0 * u, 0.55 * u, 0.14)
	body.visor.CFrame = head * CFrame.new(0, 0.3 * u * sy, -1.95 * u - 0.06)
	body.nose.Size = V3(0.6 * u, 1.6 * u * sy, 0.12)
	body.nose.CFrame = head * CFrame.new(0, -0.55 * u * sy, -1.95 * u - 0.05)
	local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
	for i, eye in ipairs(body.eyes) do
		local side = (i == 1) and -1 or 1
		eye.Size = V3(0.62 * u, math.max(0.36 * u * eyeOpen, 0.05), 0.12)
		eye.CFrame = head * CFrame.new(side * 0.75 * u, 0.3 * u * sy, -1.95 * u - 0.14)
		eye.Transparency = eyeOpen < 0.05 and 1 or 0
		eye.Color = (phase2 or P.flare > 0.5) and WHITE or def.EyeColor
	end
	-- (curly horns, like a ram's: out from the sides of the helmet, up, and
	-- curling back in at the tips)
	local hornSpots = {
		{ 2.1, 1.0, 0.1, V3(0.95, 0.95, 1.2), 0 },
		{ 2.8, 1.65, 0.05, V3(0.85, 1.15, 0.85), 0.35 },
		{ 3.1, 2.55, -0.1, V3(0.75, 1.15, 0.75), 0.12 },
		{ 2.8, 3.2, 0.35, V3(0.65, 0.65, 0.85), -0.45 },
	}
	for i = 1, 8 do
		local side = (i <= 4) and -1 or 1
		local h = hornSpots[(i - 1) % 4 + 1]
		body.horns[i].Size = h[4] * u
		body.horns[i].CFrame = head * CFrame.new(side * h[1] * u, h[2] * u * sy, h[3] * u) * CFrame.Angles(0, 0, -side * h[5])
	end

	-- shoulders (gone once his armour breaks)
	local shoulders = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		shoulders[i] = torso * V3(side * 2.85 * u * sx, neckY - 0.55 * u, 0)
		local pcf = torso * CFrame.new(side * 2.95 * u * sx, neckY - 0.1 * u, 0) * CFrame.Angles(0, 0, -side * 0.25)
		body.pauldrons[i].Size = V3(2.8, 1.6, 3.4) * u
		body.pauldrons[i].CFrame = pcf
		body.pauldronTrims[i].Size = V3(2.9, 0.35, 3.5) * u
		body.pauldronTrims[i].CFrame = pcf * CFrame.new(0, -0.75 * u, 0)
		local gone = phase2 and 1 or 0
		body.pauldrons[i].Transparency = gone
		body.pauldronTrims[i].Transparency = gone
	end

	-- ARMS: from each shoulder to where the pose wants that hand
	local hands = {}
	local wants = { torso * (lHandT * u), torso * (rHandT * u) }
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local bend = (right * side * 0.4 - up * 0.6 + look * -0.7)
		local elbow, hand = twoBone(shoulders[i], wants[i], 2.05 * u, 2.05 * u, bend.Unit)
		hands[i] = hand
		stretch(body.upperArms[i], shoulders[i], elbow, 1.35 * u, 1.35 * u, look)
		stretch(body.gauntlets[i], elbow, hand, 1.6 * u, 1.6 * u, look)
		body.fists[i].Size = V3(1.5, 1.5, 1.5) * u
		body.fists[i].CFrame = CFrame.lookAt(hand, hand + (hand - elbow), look)
	end
	B.handR, B.handL = hands[2], hands[1]

	-- THE SHOVEL, gripped in the right hand
	local dirW = unitOr(torso:VectorToWorldSpace(unitOr(shovelDirT, CARRY_DIR)), -up)
	-- (its blade lies flat when it's held level, and faces forward when it
	-- points straight down - the pogo)
	local vert = math.abs(dirW:Dot(V3(0, 1, 0)))
	local hint = unitOr(up:Lerp(look, smooth((vert - 0.55) / 0.4)), up)
	if P.shovelSpin then
		hint = CFrame.fromAxisAngle(dirW, P.shovelSpin):VectorToWorldSpace(hint)
	end
	local hand = hands[2]
	local top = hand - dirW * 1.3 * u
	local bottom = hand + dirW * 6.0 * u
	stretch(body.handle, top, bottom, 0.45 * u, 0.45 * u, hint)
	local frame = CFrame.lookAt(bottom, bottom + dirW, hint)
	body.grip.Size = V3(1.4 * u, 0.45 * u, 0.45 * u)
	body.grip.CFrame = CFrame.lookAt(top, top + dirW, hint)
	body.blade.Size = V3(2.6 * u, 0.34 * u, 2.9 * u)
	body.blade.CFrame = frame * CFrame.new(0, 0, -1.45 * u)
	body.tip.Size = V3(1.2 * u, 0.34 * u, 1.0 * u)
	body.tip.CFrame = frame * CFrame.new(0, 0, -3.4 * u)
	body.shine.Size = V3(0.55 * u, 0.36 * u, 1.4 * u)
	body.shine.CFrame = frame * CFrame.new(-0.65 * u, 0.02, -1.35 * u)
	B.bladeTip = frame * V3(0, 0, -3.8 * u)
	B.bladeMid = frame * V3(0, 0, -1.45 * u)
	-- dirt heaped on the blade (Dirt Fling), glowing orange as he's about to throw
	local load = P.load or 0
	if load > 0.02 then
		local s = 0.6 + 1.4 * load
		body.load.Size = V3(1.9 * s, 0.9 * s, 1.9 * s) * u
		body.load.CFrame = frame * CFrame.new(0, 0.55 * s * u, -1.55 * u)
		local hot = (P.loadGlow or 0) > 0.5
		body.load.Material = hot and Enum.Material.Neon or Enum.Material.SmoothPlastic
		body.load.Color = hot and GLOW_ORANGE or DIRT
		body.load.Transparency = 0
	else
		body.load.Transparency = 1
	end

	-- THE CAPE: from his back, streaming out when he moves fast or jumps
	local capeA = 0.12 + 0.25 * B.walk + 0.9 * capeLift + 0.05 * math.sin(os.clock() * 3)
	local capeTopCF = torso * CFrame.new(0, neckY - 0.2 * u, 1.7 * u) * CFrame.Angles(-capeA, 0, 0)
	body.cape.Size = V3(4.4 * u * sx, 3.3 * u, 0.25 * u)
	body.cape.CFrame = capeTopCF * CFrame.new(0, -1.65 * u, 0)
	local tailA = 0.1 + 0.35 * B.walk + 0.5 * capeLift + 0.12 * math.sin(os.clock() * 4.3)
	local tailLen = phase2 and 2.0 or 3.0
	body.capeTail.Size = V3(4.2 * u * sx, tailLen * u, 0.25 * u)
	body.capeTail.CFrame = capeTopCF * CFrame.new(0, -3.3 * u, 0) * CFrame.Angles(-tailA, 0, 0) * CFrame.new(0, -tailLen / 2 * u, 0)

	-- THE FIRE STICK (left hand), while he's using it
	local wandOn = (P.wand or 0) > 0.5
	if wandOn then
		local wd = unitOr(torso:VectorToWorldSpace(P.wandDir or V3(0.1, 0.15, -1)), look)
		local a0, a1 = hands[1] - wd * 0.6 * u, hands[1] + wd * 2.4 * u
		stretch(body.wand, a0, a1, 0.38 * u, 0.38 * u, up)
		local g = 0.75 + 0.35 * (P.wandGlow or 0)
		body.wandGem.Size = V3(g, g, g) * u
		body.wandGem.CFrame = CFrame.lookAt(a1, a1 + wd, up) * CFrame.Angles(0.6, 0.6, 0)
		body.wandGem.Color = (P.wandGlow or 0) > 0.6 and FIRE_HOT or FIRE
		B.wandTip = a1
	end
	body.wand.Transparency = wandOn and 0 or 1
	body.wandGem.Transparency = wandOn and 0 or 1

	-- DIZZY STARS round his head
	local stars = P.stars or 0
	for i, st in ipairs(body.stars) do
		if stars > 0.05 then
			local a = os.clock() * 5 + i * (math.pi * 2 / 3)
			local p = head * V3(math.cos(a) * 2.8 * u, 3.4 * u, math.sin(a) * 2.8 * u)
			st.Size = V3(1.2, 1.2, 0.5) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, os.clock() * 6)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- THE ANCHOR and its chain (see anchorFrame below)
	B.headTop = head * V3(0, 2.0 * u, 0)
	B.headCF = head
	Body._placeAnchor(B, hands[1], u)

	-- his shadow
	local shadowD = 7 * u * (1 - clamp(P.lift / 40, 0, 0.7))
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.06, 0), shadowD, 0.1)
	body.shadow.Transparency = (fade > 0.5 or sink > 0.4) and 1 or 0

	-- colours: the hit flash, the gold glow
	for _, a in ipairs(body.armour) do
		a.part.Color = flash and WHITE or a.color
	end
	local glow = P.glow or 0
	for _, tr in ipairs(body.trims) do
		tr.part.Color = (flash or glow > 0.5) and RGB(254, 231, 97) or tr.color
	end
	body.aura.Rate = (phase2 and fade < 0.3 and sink < 0.3) and 14 or ((glow > 0.3) and 30 or 0)

	-- popping into pixels (death): each part goes at its own moment; asleep
	-- underground (after a burrow) nothing shows
	local hidden = sink > 0.97
	for _, p in ipairs(body.all) do
		if hidden or (fade > 0 and fade >= body.popAt[p] * 0.9 + 0.05) then
			p.Transparency = 1
		elseif not body.selfShown[p] then
			p.Transparency = 0
		end
	end
end
Body.pose = applyPose

----------------------------------------------------------------------
-- The anchor: held up, swung round overhead, thrown, stuck in the floor,
-- and yanked back when he's done with it
----------------------------------------------------------------------
-- B.anchorT = when his Anchor Toss began (server time), B.anchorSpot = where
-- it lands (slot 1), B.anchorYank = when he started yanking it back.
local function placeAnchorParts(B, cf, u, show)
	local an = B.body.anchor
	if not show then
		an.shank.Transparency, an.stock.Transparency, an.ring.Transparency = 1, 1, 1
		for i = 1, 2 do
			an.arms[i].Transparency, an.flukes[i].Transparency = 1, 1
		end
		return
	end
	-- (cf: the anchor's centre, its shank along cf's up: a ring at the top, a
	-- short bar under it, and at the bottom two arms curving up into points)
	an.shank.Size = V3(0.7, 4.4, 0.7) * u
	an.shank.CFrame = cf
	an.stock.Size = V3(1.7, 0.45, 0.45) * u
	an.stock.CFrame = cf * CFrame.new(0, 1.35 * u, 0)
	an.ring.Size = V3(1.2, 1.2, 0.45) * u
	an.ring.CFrame = cf * CFrame.new(0, 2.6 * u, 0)
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		an.arms[i].Size = V3(2.6, 0.65, 0.65) * u
		an.arms[i].CFrame = cf * CFrame.new(side * 1.05 * u, -1.75 * u, 0) * CFrame.Angles(0, 0, side * 0.55)
		an.flukes[i].Size = V3(0.9, 1.4, 0.75) * u
		an.flukes[i].CFrame = cf * CFrame.new(side * 2.2 * u, -0.9 * u, 0) * CFrame.Angles(0, 0, -side * 0.45)
	end
	for _, p in ipairs({ an.shank, an.stock, an.ring, an.arms[1], an.arms[2], an.flukes[1], an.flukes[2] }) do
		p.Transparency = 0
	end
end

local function placeChain(B, from, to, sag, u, show)
	local links = B.body.links
	for i, l in ipairs(links) do
		if show then
			local k = (i - 0.5) / #links
			local p = from:Lerp(to, k) - V3(0, sag * 4 * k * (1 - k), 0)
			local nextP = from:Lerp(to, math.min(k + 0.1, 1)) - V3(0, sag * 4 * math.min(k + 0.1, 1) * (1 - math.min(k + 0.1, 1)), 0)
			local dir = unitOr(nextP - p, V3(0, 1, 0))
			l.Size = V3(0.35, 0.5, (from - to).Magnitude / #links * 0.9 + 0.05)
			l.CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, (i % 2 == 0) and math.pi / 2 or 0)
			l.Transparency = 0
		else
			l.Transparency = 1
		end
	end
	local _ = u
end

function Body._placeAnchor(B, hand, u)
	local a = B.def.Attacks.AnchorToss
	local t0 = B.anchorT
	if not t0 then
		placeAnchorParts(B, nil, u, false)
		placeChain(B, hand, hand, 0, u, false)
		return
	end
	local now = serverNow()
	local t = now - t0
	local spot = B.anchorSpot or slot(B, 1)
	if spot and B.action == "AnchorToss" then
		B.anchorSpot = spot
	end
	local stuckAt = spot and (onFloor(spot) + V3(0, 1.4 * u, 0)) or nil
	local cf, sag, show = nil, 0, true
	if B.anchorYank then
		-- zipping back to his hand, then gone
		local k = (now - B.anchorYank) / 0.3
		if k >= 1 or not stuckAt then
			B.anchorT, B.anchorSpot, B.anchorYank = nil, nil, nil
			placeAnchorParts(B, nil, u, false)
			placeChain(B, hand, hand, 0, u, false)
			return
		end
		local p = stuckAt:Lerp(hand, easeOut(k)) + V3(0, 3 * math.sin(k * math.pi), 0)
		cf = CFrame.new(p) * CFrame.Angles(k * 9, 0, 0)
	elseif t < 0.35 then
		-- ITEM GET! held up high over his head
		cf = CFrame.new(hand + V3(0, 2.8 * u, 0))
		show = t >= 0.02
	elseif t < a.Tell then
		-- swung round and round overhead on its chain, faster and faster
		local e = t - 0.35
		local ang = math.pi * 2 * (1.1 * e + 1.6 * e * e)
		local c = (B.headTop or hand) + V3(0, 2.2 * u, 0)
		local p = c + V3(math.cos(ang), 0, math.sin(ang)) * 5 * u
		cf = CFrame.lookAt(p, p + V3(-math.sin(ang), 0, math.cos(ang))) * CFrame.Angles(0, 0, math.pi / 2)
	elseif stuckAt and t < a.Tell + a.Flight then
		-- flying in a high arc onto the spot, tumbling
		local k = (t - a.Tell) / a.Flight
		local from = B.anchorFrom or hand
		local p = from:Lerp(stuckAt, k) + V3(0, a.Height * 4 * k * (1 - k), 0)
		cf = CFrame.new(p) * CFrame.Angles(k * 7, k * 2, 0)
	elseif stuckAt then
		-- stuck in the floor, tilted; the chain pulled tight (he's tugging it)
		cf = CFrame.lookAt(stuckAt, stuckAt + unitOr(flat(stuckAt - hand), B.vfacing)) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, -0.6 * u, 0)
		sag = 0.4 + 0.3 * math.sin(now * 20)
		if B.action ~= "AnchorToss" then
			B.anchorYank = now
		end
	else
		cf = CFrame.new(hand + V3(0, 2.8 * u, 0))
	end
	if t < a.Tell then
		B.anchorFrom = cf.Position
	end
	placeAnchorParts(B, cf, u, show)
	local ringPos = (cf * CFrame.new(0, 2.6 * u, 0)).Position
	placeChain(B, hand, ringPos, sag, u, show and t >= 0.35)
end

----------------------------------------------------------------------
-- Warnings in the world
----------------------------------------------------------------------
-- A red circle on the floor that fills in until `hitAt`. Its middle comes
-- from getCenter(now) - so it can FOLLOW you (a drop's landing) - until
-- `lockAt`, when it flashes white and stays put.
local function landingCircle(B, getCenter, radius, showAt, hitAt, lockAt)
	local disc = newPart("DropWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local ring = newRing(28, RED, Enum.Material.Neon, 1)
	local last = nil
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.05 then
				return false
			end
			if now < showAt then
				return true
			end
			local c = getCenter(now) or last
			if not c then
				return true
			end
			last = c
			c = onFloor(c)
			local k = clamp((now - showAt) / math.max(hitAt - showAt, 0.05), 0, 1)
			local locked = lockAt and now >= lockAt
			local blink = locked and (now - lockAt) < 0.22 and ((now - lockAt) % 0.11) < 0.055
			local color = blink and WHITE or RED
			placeDisc(disc, c + V3(0, 0.12, 0), radius * 2 * (0.3 + 0.7 * k), 0.1)
			disc.Transparency = lerp(0.62, 0.36, k)
			disc.Color = color
			placeRing(ring, c + V3(0, 0.14, 0), radius, 0.3, 0.55, locked and 0.05 or 0.3)
			for _, p in ipairs(ring.parts) do
				p.Color = color
			end
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- The swing's warning: a wedge on the floor in front of him (Arc degrees
-- wide, Reach long) whose red edge sweeps outward as he winds up - when it
-- reaches the rim, the shovel comes round. It turns with him until he
-- commits (then the spot in slot `slotIndex` fixes it exactly).
local function swingWedge(B, a, t0, slotIndex)
	local N = 14
	local rim, band = {}, {}
	for i = 1, N do
		rim[i] = newPart("SwingWarning", nil, RED, Enum.Material.Neon, 1)
		band[i] = newPart("SwingWarning", nil, RED, Enum.Material.Neon, 1)
	end
	local edges = { newPart("SwingWarning", nil, RED, Enum.Material.Neon, 1), newPart("SwingWarning", nil, RED, Enum.Material.Neon, 1) }
	local hitAt = t0 + a.Tell
	local half = math.rad(a.Arc / 2)
	local function arc(parts, c, dir, r, thick, tr, y)
		local step = (half * 2) / N
		for i, p in ipairs(parts) do
			local ang = -half + (i - 0.5) * step
			local out = turnY(dir, ang)
			local pos = c + out * r + V3(0, y, 0)
			p.Size = V3(2 * r * math.sin(step / 2) + 0.25, 0.14, thick)
			p.CFrame = CFrame.lookAt(pos, pos + out)
			p.Transparency = tr
		end
	end
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.06 then
				return false
			end
			local c = onFloor(B.vpos)
			local aim = slot(B, slotIndex)
			local dir = aim and unitOr(flat(aim - B.vpos), B.vfacing) or B.vfacing
			local k = clamp((now - t0) / a.Tell, 0, 1)
			local locked = aim ~= nil
			arc(rim, c, dir, a.Reach, 0.5, locked and 0.15 or 0.35, 0.16)
			arc(band, c, dir, math.max(a.Reach * smooth(k), 1.5), 1.2, lerp(0.6, 0.3, k), 0.18)
			for i, e in ipairs(edges) do
				local out = turnY(dir, (i == 1) and -half or half)
				local p0, p1 = c + out * 1.2 + V3(0, 0.16, 0), c + out * a.Reach + V3(0, 0.16, 0)
				e.Size = V3(0.5, 0.14, (p1 - p0).Magnitude)
				e.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
				e.Transparency = locked and 0.15 or 0.35
			end
			return true
		end,
		cleanup = function()
			for i = 1, N do
				rim[i]:Destroy()
				band[i]:Destroy()
			end
			edges[1]:Destroy()
			edges[2]:Destroy()
		end,
	})
end

-- the swoosh the blade leaves as it comes round
local function swoosh(B, reach)
	local c, dir = B.vpos, B.vfacing
	local streaks = {}
	for i = 1, 7 do
		streaks[i] = newPart("SwingTrail", nil, (i % 2 == 0) and WHITE or RGB(254, 231, 97), Enum.Material.Neon, 0.2)
	end
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > 0.28 then
				return false
			end
			for i, s in ipairs(streaks) do
				local k = (i - 1) / (#streaks - 1)
				local ang = lerp(1.9, -1.8, k)
				local out = turnY(dir, ang)
				local pos = c + out * reach * 0.85 + V3(0, 3.2, 0)
				s.Size = V3(0.5, 0.5, reach * 0.35)
				s.CFrame = CFrame.lookAt(pos, pos + turnY(out, math.pi / 2))
				s.Transparency = clamp(0.2 + e / 0.28 + (k < e / 0.14 and 0 or 1), 0, 1)
			end
			return true
		end,
		cleanup = function()
			for _, s in ipairs(streaks) do
				s:Destroy()
			end
		end,
	})
end

-- a clod of dirt flying from his shovel onto `to`, with a red circle where it lands
local function clod(B, to, launch, a)
	to = onFloor(to)
	local lump = newPart("Clod", nil, DIRT_DARK, Enum.Material.SmoothPlastic, 1)
	local disc = newPart("ClodWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local ring = newRing(20, RED, Enum.Material.Neon, 1)
	local from = nil
	local landed = false
	addTelegraph(B, {
		update = function(now)
			if now < launch then
				return true
			end
			from = from or (B.bladeMid or (B.vpos + V3(0, 8, 0)))
			local k = (now - launch) / a.Flight
			if k < 1 then
				local peak = 6 + flat(to - from).Magnitude * 0.22
				local p = from:Lerp(to, k) + V3(0, peak * 4 * k * (1 - k), 0)
				lump.Size = V3(2.2, 1.8, 2.2)
				lump.CFrame = CFrame.new(p) * CFrame.Angles(k * 8, k * 5, 0)
				lump.Transparency = 0
				placeDisc(disc, to + V3(0, 0.12, 0), a.Radius * 2 * (0.3 + 0.7 * k), 0.1)
				disc.Transparency = lerp(0.62, 0.36, k)
				placeRing(ring, to + V3(0, 0.14, 0), a.Radius, 0.25, 0.45, 0.25)
				return true
			end
			if not landed then
				landed = true
				burst(to + V3(0, 0.6, 0), DIRT, 14, 18, 1.3, 0.5)
				shockRing(B, to, 1, a.Radius * 1.2, 0.3, DIRT_DARK)
				playSound(B.def, "Clod", to, 0.55)
				kick(to, a.Radius, 0.35)
			end
			return false
		end,
		cleanup = function()
			lump:Destroy()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- a fireball rolling along the floor from `from` to `to`, with a red strip
-- showing the path still ahead of it
local function fireball(B, from, to, launch, a)
	from, to = onFloor(from), onFloor(to)
	local dir = unitOr(flat(to - from), B.vfacing)
	local len = flat(to - from).Magnitude
	local ball = newPart("Fireball", nil, FIRE, Enum.Material.Neon, 1)
	local core = newPart("FireballCore", nil, FIRE_HOT, Enum.Material.Neon, 1)
	local lane = newPart("FireLane", nil, RED, Enum.Material.Neon, 1)
	local lastEmber = 0
	addTelegraph(B, {
		update = function(now)
			local gone = (now - launch) * a.Speed
			if gone > len then
				burst(from + dir * len + V3(0, 1.5, 0), FIRE, 10, 12, 1, 0.4)
				return false
			end
			local p = from + dir * math.max(gone, 0)
			-- the path ahead: a thin red strip on the floor
			local rest = len - math.max(gone, 0)
			lane.Size = V3(a.Radius * 1.6, 0.12, math.max(rest, 0.1))
			lane.CFrame = CFrame.lookAt(p + dir * rest / 2 + V3(0, 0.13, 0), p + dir * rest + V3(0, 0.13, 0))
			lane.Transparency = gone < 0 and 0.75 or 0.55
			if gone < 0 then
				ball.Transparency, core.Transparency = 1, 1
				return true
			end
			local s = a.Radius * 1.3
			local wob = 1 + 0.12 * math.sin(now * 40)
			ball.Size = V3(s, s, s) * wob
			ball.CFrame = CFrame.new(p + V3(0, a.Height * 0.55, 0)) * CFrame.Angles(now * 9, now * 7, 0)
			core.Size = V3(s, s, s) * 0.55
			core.CFrame = CFrame.new(p + V3(0, a.Height * 0.55, 0)) * CFrame.Angles(-now * 6, now * 5, 0)
			ball.Transparency, core.Transparency = 0, 0
			if now - lastEmber > 0.06 then
				lastEmber = now
				burst(p + V3(0, a.Height * 0.5, 0), FIRE, 3, 4, 0.8, 0.35, true)
			end
			return true
		end,
		cleanup = function()
			ball:Destroy()
			core:Destroy()
			lane:Destroy()
		end,
	})
end

-- One gem (or bomb) of the Gem Rain: a red circle fills in where it'll land
-- while it falls out of the sky, spinning.
local function gem(B, spot, decided, a, index)
	spot = onFloor(spot)
	local bomb = index % 4 == 0
	local color = bomb and INK or GEMS[(index % #GEMS) + 1]
	local stone = newPart(bomb and "Bomb" or "Gem", nil, color, bomb and Enum.Material.SmoothPlastic or Enum.Material.Neon, 1)
	local fuse = bomb and newPart("BombFuse", nil, RED, Enum.Material.Neon, 1) or nil
	local disc = newPart("GemWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local ring = newRing(22, RED, Enum.Material.Neon, 1)
	local landed = false
	addTelegraph(B, {
		update = function(now)
			if now < decided then
				return true
			end
			local k = clamp((now - decided) / a.Fuse, 0, 1)
			if k < 1 then
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(10, 28, k))
				placeDisc(disc, spot + V3(0, 0.12, 0), a.Radius * 2 * smooth(k), 0.1)
				disc.Transparency = lerp(0.7, 0.35, k)
				placeRing(ring, spot + V3(0, 0.14, 0), a.Radius, 0.3, 0.5, lerp(0.45, 0.05, pulse * k))
				-- falling: out of the sky, faster and faster
				local fall = clamp((now - decided - 0.25) / (a.Fuse - 0.25), 0, 1)
				local h = 46 * (1 - fall * fall)
				local s = bomb and 2.2 or 1.8
				stone.Size = bomb and V3(s, s, s) or V3(s, s * 1.4, s)
				stone.CFrame = CFrame.new(spot + V3(0, h + 1, 0)) * CFrame.Angles(math.rad(45), now * 4, math.rad(35))
				stone.Transparency = (now - decided) < 0.25 and 1 or 0
				if fuse then
					fuse.Size = V3(0.5, 0.8, 0.5)
					fuse.CFrame = CFrame.new(spot + V3(0, h + 2.6, 0))
					fuse.Transparency = (stone.Transparency == 0 and (now % 0.2) < 0.1) and 0 or 1
				end
				return true
			end
			if not landed then
				landed = true
				if bomb then
					burst(spot + V3(0, 1, 0), FIRE, 22, 22, 1.8, 0.5)
					burst(spot + V3(0, 1, 0), INK, 12, 14, 2, 0.6)
					kick(spot, a.Radius, 0.6, -2)
				else
					burst(spot + V3(0, 1, 0), color, 16, 18, 1.2, 0.5)
					kick(spot, a.Radius, 0.3)
				end
				shockRing(B, spot, 1, a.Radius * 1.2, 0.3, bomb and FIRE or color)
				playSound(B.def, "Gem", spot, bomb and 0.8 or 0.45)
			end
			return false
		end,
		cleanup = function()
			stone:Destroy()
			if fuse then
				fuse:Destroy()
			end
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- the Gem Rain carries on under his next moves: every frame, draw any new gem
-- the server has picked (RainK counts them; Rain1.. are where they land)
local function watchRain(B)
	local m = B.model
	local startAt = m:GetAttribute("RainAt")
	if startAt ~= B.rainAt then
		B.rainAt, B.rainDone = startAt, 0
	end
	if not startAt then
		return
	end
	local a = B.def.Attacks.GemRain
	local k = m:GetAttribute("RainK") or 0
	while (B.rainDone or 0) < k do
		B.rainDone = (B.rainDone or 0) + 1
		local i = B.rainDone
		local spot = m:GetAttribute("Rain" .. i)
		if typeof(spot) == "Vector3" then
			gem(B, spot, startAt + (i - 1) * a.Gap, a, i)
		end
	end
end

-- the charge's lane: follows the way he faces while he scrapes his shovel,
-- then flashes and fixes exactly where he'll go (slots 1 and 2)
local function dashLane(B, a, t0)
	local strip = newPart("DashWarning", nil, RED, Enum.Material.Neon, 1)
	local rimL = newPart("DashWarning", nil, RED, Enum.Material.Neon, 1)
	local rimR = newPart("DashWarning", nil, RED, Enum.Material.Neon, 1)
	local lockedAt = nil
	local lastSpark = 0
	addTelegraph(B, {
		update = function(now)
			local from, to = slot(B, 1), slot(B, 2)
			local travel = B.model:GetAttribute("ActN")
			local ends = t0 + a.Tell + (type(travel) == "number" and travel or 1)
			if now > ends + 0.05 or (B.action ~= "ChargeDash" and now > t0 + 0.1) then
				return false
			end
			-- sparks off the shovel scraping the ground
			if now < t0 + a.Tell and now - lastSpark > 0.09 and B.bladeTip then
				lastSpark = now
				burst(onFloor(B.bladeTip) + V3(0, 0.4, 0), (math.random() < 0.5) and FIRE_HOT or FIRE, 5, 14, 0.5, 0.25, true)
			end
			local c0, c1, tr
			if from and to then
				lockedAt = lockedAt or now
				c0, c1 = onFloor(from), onFloor(to)
				local blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
				local color = blink and WHITE or RED
				strip.Color, rimL.Color, rimR.Color = color, color, color
				tr = 0.45
			else
				c0 = onFloor(B.vpos)
				c1 = c0 + B.vfacing * 34
				tr = 0.72
			end
			local dir = unitOr(flat(c1 - c0), B.vfacing)
			local sideV = V3(-dir.Z, 0, dir.X)
			local len = flat(c1 - c0).Magnitude
			local mid = (c0 + c1) / 2 + V3(0, 0.12, 0)
			strip.Size = V3(a.Width * 2, 0.12, math.max(len, 0.1))
			strip.CFrame = CFrame.lookAt(mid, mid + dir)
			strip.Transparency = tr
			for i, rim in ipairs({ rimL, rimR }) do
				local s = (i == 1) and -1 or 1
				local rm = mid + sideV * s * a.Width + V3(0, 0.02, 0)
				rim.Size = V3(0.5, 0.14, math.max(len, 0.1))
				rim.CFrame = CFrame.lookAt(rm, rm + dir)
				rim.Transparency = from and 0.1 or 0.5
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
			rimL:Destroy()
			rimR:Destroy()
		end,
	})
end

-- the Shovel Meteor's shadow: a huge dark circle growing in the middle of
-- the dig while he's out of sight, a red ring marking how far it reaches
local function meteorShadow(B, a, showAt, land)
	local center = nil
	local shade = newPart("MeteorShadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 1)
	local ring = newRing(48, RED, Enum.Material.Neon, 1)
	local fill = newPart("MeteorWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	addTelegraph(B, {
		update = function(now)
			if now > land + 0.05 then
				return false
			end
			center = center or slot(B, 1)
			if not center or now < showAt then
				return true
			end
			local c = onFloor(center)
			local k = clamp((now - showAt) / (land - showAt), 0, 1)
			placeDisc(shade, c + V3(0, 0.1, 0), lerp(8, a.Radius * 1.9, smooth(k)), 0.1)
			shade.Transparency = lerp(0.55, 0.2, k)
			local pulse = 0.5 + 0.5 * math.sin(now * lerp(6, 24, k))
			placeRing(ring, c + V3(0, 0.16, 0), a.Radius, 0.6, 1.0, lerp(0.4, 0.0, pulse))
			placeDisc(fill, c + V3(0, 0.13, 0), a.Radius * 2, 0.1)
			fill.Transparency = lerp(0.85, 0.6, k)
			return true
		end,
		cleanup = function()
			shade:Destroy()
			fill:Destroy()
			removeRing(ring)
		end,
	})
end

-- "HA HA!" in a little speech box over his head (the taunt)
local function laughBubble(B, seconds)
	local bb = Instance.new("BillboardGui")
	bb.Name = "BurrowmoreLaugh"
	bb.Size = UDim2.fromOffset(170, 54)
	bb.StudsOffsetWorldSpace = V3(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 160
	bb.Adornee = B.body.helmet
	local box = Instance.new("Frame")
	box.BackgroundColor3 = RGB(0, 0, 0)
	box.BorderSizePixel = 0
	box.Size = UDim2.fromScale(1, 1)
	box.Parent = bb
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 3
	stroke.Parent = box
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.Text = "HAH!"
	label.Parent = box
	bb.Parent = B.body.folder
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > seconds or B.action ~= "Taunt" then
				return false
			end
			label.Text = (e < 0.5) and "HAH!" or ((math.floor(e * 4) % 2 == 0) and "HA HA!" or "HA HA HA!")
			bb.StudsOffsetWorldSpace = V3(0, 5.5 + 0.3 * math.sin(e * 16), 0)
			return true
		end,
		cleanup = function()
			bb:Destroy()
		end,
	})
end

-- his shoulder plates flying off when his armour breaks
local function platesFlyOff(B)
	for i, p in ipairs(B.body.pauldrons) do
		local piece = newPart("PlateShard", nil, B.def.Color, Enum.Material.SmoothPlastic, 0)
		piece.Size = p.Size
		local trimPiece = newPart("PlateShard", nil, B.def.TrimColor or RGB(254, 174, 52), Enum.Material.SmoothPlastic, 0)
		trimPiece.Size = B.body.pauldronTrims[i].Size
		local start = p.CFrame
		local side = (i == 1) and -1 or 1
		local out = (B.body.chest.CFrame.RightVector * side + V3(0, 0.3, 0)).Unit
		local t0 = serverNow()
		local floorY = B.vpos.Y
		addTelegraph(B, {
			update = function(now)
				local e = now - t0
				if e > 1.8 then
					return false
				end
				local pos = start.Position + out * 20 * e + V3(0, 16 * e - 34 * e * e, 0)
				if pos.Y < floorY + 0.7 then
					pos = V3(pos.X, floorY + 0.7, pos.Z)
				end
				piece.CFrame = CFrame.new(pos) * (start - start.Position) * CFrame.Angles(e * 8, e * 3, 0)
				trimPiece.CFrame = piece.CFrame * CFrame.new(0, -0.6, 0)
				local tr = clamp((e - 1.3) / 0.5, 0, 1)
				piece.Transparency, trimPiece.Transparency = tr > 0.5 and 1 or 0, tr > 0.5 and 1 or 0
				return true
			end,
			cleanup = function()
				piece:Destroy()
				trimPiece:Destroy()
			end,
		})
	end
end

-- the treasure chest that bursts up out of the dirt where he knelt
local function treasureChest(B, pos, facing)
	pos = onFloor(pos)
	local def = B.def
	local trim = def.TrimColor or RGB(254, 174, 52)
	local boxP = newPart("TreasureChest", nil, RGB(184, 111, 80), Enum.Material.SmoothPlastic, 1)
	local lid = newPart("TreasureLid", nil, WOOD, Enum.Material.SmoothPlastic, 1)
	local bands = { newPart("TreasureBand", nil, trim, Enum.Material.SmoothPlastic, 1), newPart("TreasureBand", nil, trim, Enum.Material.SmoothPlastic, 1) }
	local gold = newPart("TreasureGold", nil, RGB(254, 231, 97), Enum.Material.Neon, 1)
	local lock = newPart("TreasureLock", nil, RGB(254, 231, 97), Enum.Material.SmoothPlastic, 1)
	local t0 = serverNow()
	local opened, rose = false, false
	local look = unitOr(flat(facing), V3(0, 0, 1))
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > 10 then
				return false
			end
			if not rose then
				rose = true
				burst(pos + V3(0, 1, 0), DIRT, 26, 22, 1.8, 0.6, true)
				kick(pos, 20, 0.5, -2)
			end
			-- up out of the dirt with a bounce, and (at the end) back down into it
			local upK = easeOutBack(clamp(e / 0.4, 0, 1))
			local down = clamp((e - 9.2) / 0.8, 0, 1)
			local y = lerp(-3.2, 0, upK) - 3.2 * down
			local cf = CFrame.lookAt(pos + V3(0, y, 0), pos + V3(0, y, 0) + look)
			boxP.Size = V3(4.4, 2.8, 3.2)
			boxP.CFrame = cf * CFrame.new(0, 1.4, 0)
			for i, b in ipairs(bands) do
				b.Size = V3(0.45, 2.9, 3.3)
				b.CFrame = cf * CFrame.new((i == 1) and -1.6 or 1.6, 1.4, 0)
			end
			lock.Size = V3(0.8, 0.9, 0.3)
			lock.CFrame = cf * CFrame.new(0, 2.2, -1.7)
			-- the lid flips open after a moment, gold glowing inside
			local open = clamp((e - 0.7) / 0.3, 0, 1)
			if open > 0 and not opened then
				opened = true
				burst(pos + V3(0, 3.5, 0), RGB(254, 231, 97), 30, 26, 1.4, 0.9, true)
				for k = 1, 3 do
					burst(pos + V3(0, 3.2, 0), GEMS[k], 8, 22, 1, 0.8, true)
				end
				playSound(def, "Gem", pos, 1)
			end
			lid.Size = V3(4.4, 0.7, 3.2)
			lid.CFrame = cf * CFrame.new(0, 2.8, 1.6) * CFrame.Angles(math.rad(105) * easeOutBack(open), 0, 0) * CFrame.new(0, 0.35, -1.6)
			gold.Size = V3(3.8, 0.5, 2.6)
			gold.CFrame = cf * CFrame.new(0, 2.6, 0)
			local vis = e < 9.9
			for _, p in ipairs({ boxP, lid, bands[1], bands[2], lock }) do
				p.Transparency = vis and 0 or 1
			end
			gold.Transparency = (vis and open > 0.2) and 0 or 1
			return true
		end,
		cleanup = function()
			for _, p in ipairs({ boxP, lid, bands[1], bands[2], gold, lock }) do
				p:Destroy()
			end
		end,
	})
end

----------------------------------------------------------------------
-- The shape of each move over time
----------------------------------------------------------------------
-- (hand spots and shovel directions are in his chest's space: x = his right,
-- y = up from his hips, z = BACKWARD - so -z is in front of him)
local DOWN_R, DOWN_L, DOWN_DIR = V3(0.6, 2.6, -1.4), V3(0.05, 3.3, -1.45), V3(0, -1, 0.05)
local OVERHEAD_R, OVERHEAD_DIR = V3(1.4, 6.3, 0.2), V3(0.25, 0.9, 0.35)

-- in the air on a drop or a pogo: legs tucked, shovel pointing straight down
local function airPose(P)
	P.crouch = 0.55
	P.rHand, P.lHand, P.shovelDir = DOWN_R, DOWN_L, DOWN_DIR
	P.capeLift = 1
end

-- stuck: the blade buried in the dirt in front of him, tugging at it
local function stuckPose(P, t, hard)
	P.crouch = 0.35
	P.lean = 0.25 + 0.05 * math.sin(t * 18)
	P.rHand, P.lHand = V3(0.8, 1.5, -2.0), V3(-0.2, 1.9, -2.0)
	P.shovelDir = V3(0, -0.93, -0.35)
	P.shake = hard and 0.12 or 0.05
end

-- the drop, the delayed drop, and the drop half of the swing-drop: a crouch,
-- the leap (following you), the landing, one bounce, and the tug
local function dropPose(B, t, P, a, tA, slotA, slotB)
	local total = a.Air + (a.Hang or 0)
	if t < tA then
		-- crouching to spring, the shovel drawn up overhead
		local k = smooth(t / math.max(tA, 0.05))
		P.crouch = 0.9 * k
		P.lean = 0.15 * k
		P.rHand, P.shovelDir = OVERHEAD_R, OVERHEAD_DIR
		P.lHand = V3(-1.8, 3.4, -1.6)
		P.flare = k
		return
	end
	local A, Bs = slot(B, slotA), slot(B, slotB)
	local e = t - tA
	if e < total then
		airPose(P)
		P.lift = jumpHeight(e, a.Air, a.Rise, a.Height, a.Hang)
		if A and Bs then
			local k = clamp(e / total, 0, 1)
			P.override = A:Lerp(Bs, k)
			local d = flat(Bs - A)
			if d.Magnitude > 0.5 then
				P.facing = d.Unit
			end
		end
		-- falling: stretched long, a glint off the blade as it locks
		local up = a.Air * a.Rise + (a.Hang or 0)
		if e > up then
			P.sy = 1.12
			P.sx = 0.92
			P.snap = true
		elseif e > up - 0.05 and (a.Hang or 0) > 0 then
			P.glow = 1
		end
		return
	end
	-- landed: squash, one bounce, then the shovel's stuck
	local l = e - total
	if Bs then
		P.override = Bs
	end
	if l < a.Bounce then
		local k = l / a.Bounce
		P.lift = 4.5 * math.sin(math.pi * k)
		local w = spring(l, 7, 16)
		P.sy, P.sx = 1 - 0.3 * w, 1 + 0.2 * w
		airPose(P)
		P.capeLift = 0.5
		return
	end
	stuckPose(P, l, false)
end

function Poses.ShovelDrop(B, t, P)
	local a = B.def.Attacks.ShovelDrop
	dropPose(B, t, P, a, a.Tell, 1, 2)
end

function Poses.DelayedDrop(B, t, P)
	local a = B.def.Attacks.DelayedDrop
	dropPose(B, t, P, a, a.Tell, 1, 2)
end

-- the swing: wind up (twisted right, shovel back over his shoulder), then it
-- comes round in a flash, and follow through
local function swingPose(B, t, P, a)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.twist = -0.75 * k
		P.crouch = 0.25 * k
		P.lean = -0.05 * k
		P.rHand = V3(2.3, 4.6, 0.9)
		P.shovelDir = V3(0.35, 0.45, 0.82)
		P.lHand = V3(-1.9, 3.0, -2.2)
		P.flare = k > 0.8 and 1 or 0
		return
	end
	local e = t - a.Tell
	local k = clamp(e / 0.16, 0, 1)
	P.snap = e < 0.2
	P.twist = lerp(-0.75, 0.95, easeOut(k))
	P.crouch = 0.3
	P.lean = 0.12
	-- the shovel sweeps round level, from behind on the right to out front on the left
	local ang = lerp(2.2, -1.9, easeOut(k))
	local out = V3(math.sin(ang), -0.15, -math.cos(ang))
	P.shovelDir = out
	P.rHand = V3(0.6, 3.1, -0.6) + V3(out.X, 0, out.Z) * 2.2
	P.lHand = V3(-2.2, 2.4, 0.4)
end

function Poses.ShovelSwing(B, t, P)
	swingPose(B, t, P, B.def.Attacks.ShovelSwing)
end

function Poses.SwingDrop(B, t, P)
	local a = B.def.Attacks.SwingDrop
	if t < a.Tell + a.Crouch then
		swingPose(B, t, P, a)
		if t > a.Tell + 0.12 then
			-- straight into a crouch for the jump
			P.crouch = 0.85
			P.rHand, P.shovelDir = OVERHEAD_R, OVERHEAD_DIR
		end
		return
	end
	dropPose(B, t, P, a, a.Tell + a.Crouch, 2, 3)
end

-- the pogo: a long glowing crouch, three hops shovel-down, then dizzy
function Poses.TriplePogo(B, t, P)
	local a = B.def.Attacks.TriplePogo
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.crouch = 0.9 * k
		P.rHand, P.lHand, P.shovelDir = DOWN_R, DOWN_L, DOWN_DIR
		P.glow = (math.floor(t * 10) % 2 == 0) and 1 or 0
		P.flare = k
		return
	end
	local cycle = a.Air + a.Ground
	local e = t - a.Tell
	local hop = math.floor(e / cycle) + 1
	if hop <= a.Hops then
		local he = e - (hop - 1) * cycle
		local A, Bs = slot(B, 2 * hop - 1), slot(B, 2 * hop)
		if he < a.Air then
			airPose(P)
			P.lift = jumpHeight(he, a.Air, a.Rise, a.Height, 0)
			if A and Bs then
				P.override = A:Lerp(Bs, clamp(he / a.Air, 0, 1))
				local d = flat(Bs - A)
				if d.Magnitude > 0.5 then
					P.facing = d.Unit
				end
			end
			return
		end
		-- a split second on the ground between hops: squashed
		if Bs then
			P.override = Bs
		end
		local w = spring(he - a.Air, 8, 18)
		P.sy, P.sx = 1 - 0.3 * w, 1 + 0.22 * w
		P.crouch = 0.8
		P.rHand, P.lHand, P.shovelDir = DOWN_R, DOWN_L, DOWN_DIR
		return
	end
	-- dizzy: swaying, stars round his head, shovel drooping to the ground
	local last = slot(B, 2 * a.Hops)
	if last then
		P.override = last
	end
	local d = e - a.Hops * a.Air - (a.Hops - 1) * a.Ground
	P.stars = 1
	P.roll = 0.14 * math.sin(d * 5)
	P.twist = 0.25 * math.sin(d * 3.3)
	P.headPitch = 0.15 + 0.1 * math.sin(d * 6)
	P.crouch = 0.2
	P.rHand = V3(1.6, 1.2, -1.2)
	P.shovelDir = V3(0.2, -0.9, -0.4)
	P.lHand = V3(-2.5, 1.0, 0.2)
end

-- dirt fling: dig in (dirt piling on the blade, glowing), heave it back, fling
function Poses.DirtFling(B, t, P)
	local a = B.def.Attacks.DirtFling
	local dig = a.Tell * 0.6
	if t < dig then
		local k = smooth(t / dig)
		P.lean = 0.35 * k
		P.crouch = 0.35 * k
		P.rHand = V3(1.2, 1.4, -2.4)
		P.lHand = V3(0.2, 2.2, -2.3)
		P.shovelDir = V3(0, -0.8, -0.6)
		P.load = clamp((t - dig * 0.35) / (dig * 0.65), 0, 1)
		return
	end
	if t < a.Tell then
		local k = smooth((t - dig) / (a.Tell - dig))
		P.lean = lerp(0.35, -0.2, k)
		P.crouch = 0.3
		P.rHand = V3(2.1, 4.4, 0.6)
		P.lHand = V3(0.4, 4.0, -0.4)
		P.shovelDir = V3(0.2, 0.7, 0.68)
		P.load = 1
		P.loadGlow = (math.floor(t * 12) % 2 == 0) and 1 or 0
		P.flare = 1
		return
	end
	local e = t - a.Tell
	local k = clamp(e / 0.15, 0, 1)
	P.snap = e < 0.2
	P.lean = lerp(-0.2, 0.3, k)
	P.crouch = 0.25
	P.rHand = V3(1.4, lerp(4.4, 3.2, k), lerp(0.6, -2.6, k))
	P.lHand = V3(-0.2, 3.2, -2.2)
	P.shovelDir = V3(0.1, lerp(0.7, 0.3, k), lerp(0.68, -0.95, k))
end

-- anchor toss: ITEM GET! (held up high), swing it round overhead, throw, tug
function Poses.AnchorToss(B, t, P)
	local a = B.def.Attacks.AnchorToss
	if t < 0.35 then
		P.lHand = V3(-0.9, 7.4, -0.8)
		P.headPitch = -0.2
		P.flare = 1
		return
	end
	if t < a.Tell then
		local e = t - 0.35
		local ang = math.pi * 2 * (1.1 * e + 1.6 * e * e)
		-- (his hand circles with the chain)
		P.lHand = V3(-0.8 + math.cos(ang) * 0.9, 6.8, -0.4 + math.sin(ang) * 0.9)
		P.lean = -0.08
		P.twist = 0.1 * math.sin(ang)
		return
	end
	local e = t - a.Tell
	if e < 0.25 then
		-- the throw: arm whips forward
		local k = clamp(e / 0.12, 0, 1)
		P.snap = true
		P.lHand = V3(-1.4, lerp(6.8, 4.2, k), lerp(-0.4, -3.3, k))
		P.lean = 0.2 * k
		P.twist = 0.3 * k
		return
	end
	-- tugging the chain while the anchor's stuck in the floor
	P.lHand = V3(-1.4, 3.0, -1.4 + 0.3 * math.sin(e * 16))
	P.lean = -0.25
	P.crouch = 0.3
	P.shake = e > a.Flight and 0.06 or 0
end

-- fire stick: ITEM GET!, then point the wand at you and shoot
function Poses.FireStick(B, t, P)
	local a = B.def.Attacks.FireStick
	P.wand = 1
	if t < 0.35 then
		P.lHand = V3(-0.9, 7.2, -0.8)
		P.wandDir = V3(0, 1, 0)
		P.wandGlow = 1
		P.headPitch = -0.2
		P.flare = 1
		return
	end
	P.lHand = V3(-1.3, 4.3, -3.4)
	P.wandDir = V3(0.08, 0.1, -1)
	P.twist = 0.35
	P.wandGlow = clamp((t - 0.35) / (a.Tell - 0.35), 0, 1)
	for k = 1, a.Balls do
		local d = t - (a.Tell + (k - 1) * a.Gap)
		if d >= 0 and d < 0.15 then
			-- each shot kicks the wand up
			P.lHand = V3(-1.3, 4.9, -3.1)
			P.wandDir = V3(0.08, 0.45, -0.9)
			P.snap = true
		end
	end
end

-- charge dash: crouched low scraping the shovel behind him, then the charge
-- (shovel out in front like a lance), then a skid - or a crash
function Poses.ChargeDash(B, t, P)
	local a = B.def.Attacks.ChargeDash
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.crouch = 0.8 * k
		P.lean = 0.45 * k
		P.rHand = V3(2.4, 1.4, 1.5)
		P.shovelDir = V3(0.2, -0.45, 0.87)
		P.lHand = V3(-1.8, 3.2, -2.4)
		P.stride = 0.35 * math.sin(t * 20) * k
		return
	end
	local from, to = slot(B, 1), slot(B, 2)
	local travel = B.model:GetAttribute("ActN")
	travel = type(travel) == "number" and travel or 0.6
	local e = t - a.Tell
	if e < travel then
		if from and to then
			P.override = from:Lerp(to, clamp(e / travel, 0, 1))
			P.facing = unitOr(flat(to - from), B.vfacing)
		end
		P.crouch = 0.45
		P.lean = 0.5
		P.rHand = V3(1.3, 2.6, -2.8)
		P.shovelDir = V3(0.05, -0.2, -0.98)
		P.lHand = V3(-2.3, 2.8, 0.8)
		P.stride = math.sin(t * 30)
		P.capeLift = 1
		P.snap = true
		return
	end
	if to then
		P.override = to
	end
	local after = e - travel
	if slot(B, 3) then
		-- crashed into the edge: knocked back on his heels, seeing stars
		P.stars = 1
		P.lean = -0.2 + 0.08 * math.sin(after * 6)
		P.roll = 0.12 * math.sin(after * 5)
		P.headPitch = -0.15
		P.rHand = V3(2.0, 1.0, -0.8)
		P.shovelDir = V3(0.4, -0.85, -0.3)
		P.lHand = V3(-2.6, 1.2, 0.3)
		P.crouch = 0.2
		return
	end
	-- skidding to a halt, then catching his breath
	local k = clamp(after / 0.35, 0, 1)
	P.lean = lerp(-0.3, 0.2, k)
	P.crouch = lerp(0.6, 0.3, k)
	P.rHand = V3(1.6, 2.0, -2.0)
	P.shovelDir = V3(0.1, -0.7, -0.7)
	P.sy = 1 + 0.03 * math.sin(after * 10)
end

-- the taunt: shovel planted beside him, hand on hip, then pointing and laughing
function Poses.Taunt(B, t, P)
	P.rHand = V3(2.7, 3.4, -0.7)
	P.shovelDir = V3(0.06, -1, 0.02)
	if t < 0.45 then
		P.lHand = V3(-2.4, 1.5, 0.4)
		return
	end
	P.lHand = V3(-1.3, 5.3, -3.2)
	P.headPitch = -0.28
	P.lean = -0.1
	P.sy = 1 + 0.045 * math.sin(t * 22)
	P.twist = 0.15
end

-- gem rain: shovel raised high in both hands, then slammed into the ground
function Poses.GemRain(B, t, P)
	local a = B.def.Attacks.GemRain
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.rHand = V3(0.6, 7.4, -0.8)
		P.lHand = V3(-0.3, 7.2, -0.8)
		P.shovelDir = V3(0, 1, 0.1)
		P.headPitch = -0.3 * k
		P.glow = k > 0.6 and 1 or 0
		P.flare = k
		return
	end
	local e = t - a.Tell
	P.snap = e < 0.15
	P.crouch = 0.5
	P.lean = 0.3
	P.rHand = V3(0.5, 1.6, -2.6)
	P.lHand = V3(-0.3, 2.2, -2.6)
	P.shovelDir = V3(0, -0.9, -0.45)
end

-- the meteor: a deep crouch, rocket up out of sight, plunge shovel-first,
-- and stuck in the ground with stars
function Poses.ShovelMeteor(B, t, P)
	local a = B.def.Attacks.ShovelMeteor
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.crouch = k
		P.rHand, P.shovelDir = OVERHEAD_R, OVERHEAD_DIR
		P.lHand = V3(-1.4, 3.4, -1.8)
		P.shake = 0.2 * k
		P.flare = k
		P.glow = (math.floor(t * 12) % 2 == 0) and 1 or 0
		return
	end
	local e = t - a.Tell
	local total = a.Up + a.Fall
	if e < total then
		P.lift = jumpHeight(e, a.Up + 0.3, a.Up / (a.Up + 0.3), 90, a.Fall - 0.3)
		airPose(P)
		if e < a.Up then
			P.sy, P.sx = 1.15, 0.9 -- (stretched, rocketing up)
			P.rHand, P.shovelDir = OVERHEAD_R, V3(0, 1, 0)
		end
		return
	end
	stuckPose(P, e - total, true)
	P.stars = 1
	P.crouch = 0.55
end

-- THE MOMENTS EVERY BOSS HAS
-- asleep: kneeling, head bowed, both hands on his planted shovel
function Poses.Dormant(B, t, P)
	P.kneel = 1
	P.headPitch = 0.38
	P.rHand = V3(0.9, 1.2, -2.3)
	P.lHand = V3(0.1, 1.5, -2.3)
	P.shovelDir = V3(0, -1, 0)
	P.eyes = 0
	P.sy = 1 + 0.015 * math.sin(t * 1.4)
end

-- waking: the head comes up, eyes light, he stands, pulls the shovel out of
-- the dirt, twirls it, and strikes a pose
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local u = clamp(t / W, 0, 1)
	P.rHand = V3(0.9, 1.2, -2.3)
	P.lHand = V3(0.1, 1.5, -2.3)
	P.shovelDir = V3(0, -1, 0)
	if u < 0.3 then
		P.kneel = 1
		P.headPitch = lerp(0.38, 0, smooth(u / 0.3))
		P.eyes = (u > 0.15) and ((math.floor(t * 14) % 3 == 0) and 0 or 1) or 0
		return
	end
	P.eyes = 1
	if u < 0.5 then
		P.kneel = 1 - smooth((u - 0.3) / 0.2)
		return
	end
	if u < 0.58 then
		-- yank! the shovel comes up out of the ground
		local k = (u - 0.5) / 0.08
		P.rHand = V3(1.0, lerp(1.2, 5.5, k), -1.8)
		P.shovelDir = V3(0, -1, 0)
		P.snap = true
		return
	end
	if u < 0.76 then
		-- a twirl, held out in front
		local k = (u - 0.58) / 0.18
		P.rHand = V3(1.2, 4.2, -2.6)
		P.shovelDir = V3(0, 0.2, -1)
		P.shovelSpin = k * math.pi * 4
		P.lHand = V3(-2.4, 1.5, 0.4)
		return
	end
	-- the pose: shovel raised high and proud, fist on his hip
	P.rHand = V3(2.2, 6.4, -0.6)
	P.shovelDir = V3(0.35, 0.9, -0.2)
	P.lHand = V3(-2.4, 1.5, 0.4)
	P.headPitch = -0.12
	P.flare = u < 0.9 and 1 or 0
	P.glow = (u > 0.77 and u < 0.86) and 1 or 0
end

-- everyone's gone: he spins his shovel down into the ground and burrows away
function Poses.Reset(B, t, P)
	local k = clamp(t / 2, 0, 1)
	P.crouch = 0.6
	P.rHand = V3(0.6, 2.4, -1.6)
	P.lHand = V3(0.0, 3.0, -1.6)
	P.shovelDir = V3(0, -1, 0)
	P.facing = turnY(B.vfacing, t * 9) -- (spinning down into the dirt)
	P.sink = clamp((k - 0.2) / 0.7, 0, 1)
	P.eyes = 1 - k
end

-- NO QUARTER!: staggering while his armour cracks, then arms flung wide
function Poses.Break(B, t, P)
	local BT = B.def.BreakTime
	if t < BT * 0.35 then
		local k = t / (BT * 0.35)
		P.shake = 0.35 * k
		P.crouch = 0.3 * k
		P.lean = 0.25 * k
		P.lHand = V3(-0.8, 3.0, -1.6)
		P.rHand = V3(0.9, 2.6, -1.8)
		P.shovelDir = V3(0, -1, 0)
		P.headPitch = 0.3 * k
		return
	end
	local e = t - BT * 0.35
	local w = spring(e, 3, 9)
	P.lean = -0.2
	P.headPitch = -0.35
	P.rHand = V3(3.6, 6.0, -0.6)
	P.shovelDir = V3(0.4, 0.9, 0)
	P.lHand = V3(-3.6, 5.6, -0.6)
	P.sy = 1 + 0.12 * w
	P.flare = clamp(1 - e * 0.6, 0, 1)
	P.glow = e < 1.2 and 1 or 0
end

-- the end: a stagger, down on one knee, head bowed... then gone in a pop of pixels
function Poses.Death(B, t, P)
	P.eyes = 1
	if t < 0.6 then
		local k = t / 0.6
		P.lean = -0.3 * k
		P.shake = 0.2
		P.rHand = V3(1.4, 2.4, -1.5)
		P.shovelDir = V3(0.2, -0.95, -0.2)
		return
	end
	P.kneel = smooth((t - 0.6) / 0.6)
	P.headPitch = 0.42 * smooth((t - 0.6) / 0.8)
	P.rHand = V3(0.9, 1.2, -2.3)
	P.lHand = V3(-1.9, 1.4, -0.9)
	P.shovelDir = V3(0, -1, 0)
	P.eyes = t > 3.2 and 0 or 1
	-- (popping away in chunky steps, like an old game)
	if t > 3.6 then
		P.fade = math.floor(clamp((t - 3.6) / 1.0, 0, 1) * 5 + 0.5) / 5
	end
end

----------------------------------------------------------------------
-- One-off moments in each move (sounds, landings, sparks, warnings)
----------------------------------------------------------------------
-- a drop's landing: the thud, the ring of dirt, the camera
local function landFx(B, spot, radius, big)
	spot = spot or B.vpos
	shockRing(B, spot, 1.5, radius * 1.25, 0.32, DIRT_DARK)
	burst(spot + V3(0, 0.8, 0), DIRT, big and 30 or 18, 26, 1.8, 0.55)
	playSound(B.def, "Land", spot, big and 1 or 0.8)
	kick(spot, radius, big and 1.1 or 0.7, big and -4 or -2)
end

local function dropStarts(B, t0, a, tA, slotB)
	local total = a.Air + (a.Hang or 0)
	at(B, t0 + tA, function()
		playSound(B.def, "Jump", B.vpos, 0.9)
		burst(B.vpos + V3(0, 0.5, 0), DIRT, 12, 14, 1.4, 0.45)
	end)
	at(B, t0 + tA + total * a.Lock, function()
		local spot = slot(B, slotB)
		if spot then
			burst(onFloor(spot) + V3(0, 0.5, 0), WHITE, 8, 10, 0.9, 0.3, true)
		end
	end)
	at(B, t0 + tA + total, function()
		landFx(B, slot(B, slotB), a.Radius, true)
	end)
	at(B, t0 + tA + total + a.Bounce, function()
		burst(B.vpos + V3(0, 0.5, 0), DIRT, 10, 12, 1.2, 0.4)
		playSound(B.def, "Land", B.vpos, 0.4)
	end)
end

-- the red circle under a jump, following the published landing spot until it locks
local function jumpCircle(B, t0, a, tA, slotB)
	local total = a.Air + (a.Hang or 0)
	landingCircle(B, function()
		return slot(B, slotB)
	end, a.Radius, t0 + tA, t0 + tA + total, t0 + tA + total * a.Lock)
end

function Starts.ShovelDrop(B, t0)
	dropStarts(B, t0, B.def.Attacks.ShovelDrop, B.def.Attacks.ShovelDrop.Tell, 2)
end

function Starts.DelayedDrop(B, t0)
	dropStarts(B, t0, B.def.Attacks.DelayedDrop, B.def.Attacks.DelayedDrop.Tell, 2)
end

function SlotSpawns.ShovelDrop(B, i, spot, t0)
	if i == 2 then
		local a = B.def.Attacks.ShovelDrop
		jumpCircle(B, t0, a, a.Tell, 2)
	end
end

function SlotSpawns.DelayedDrop(B, i, spot, t0)
	if i == 2 then
		local a = B.def.Attacks.DelayedDrop
		jumpCircle(B, t0, a, a.Tell, 2)
	end
end

function Starts.TriplePogo(B, t0)
	local a = B.def.Attacks.TriplePogo
	at(B, t0 + 0.05, function()
		burst(B.vpos + V3(0, 1, 0), B.def.TrimColor or WHITE, 20, 12, 1.2, 0.7, true)
	end)
	for hop = 1, a.Hops do
		local tA = a.Tell + (hop - 1) * (a.Air + a.Ground)
		at(B, t0 + tA, function()
			playSound(B.def, "Jump", B.vpos, 0.7)
		end)
		at(B, t0 + tA + a.Air, function()
			landFx(B, slot(B, 2 * hop), a.Radius, hop == a.Hops)
		end)
	end
end

function SlotSpawns.TriplePogo(B, i, spot, t0)
	if i % 2 == 0 then
		local a = B.def.Attacks.TriplePogo
		local hop = i / 2
		local tA = a.Tell + (hop - 1) * (a.Air + a.Ground)
		landingCircle(B, function()
			return slot(B, i)
		end, a.Radius, t0 + tA, t0 + tA + a.Air, t0 + tA + a.Air * a.Lock)
	end
end

function Starts.ShovelSwing(B, t0)
	local a = B.def.Attacks.ShovelSwing
	swingWedge(B, a, t0, 1)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Swing", B.vpos, 1)
		swoosh(B, a.Reach)
		kick(B.vpos, a.Reach, 0.5)
	end)
end

function Starts.SwingDrop(B, t0)
	local a = B.def.Attacks.SwingDrop
	swingWedge(B, a, t0, 1)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Swing", B.vpos, 1)
		swoosh(B, a.Reach)
		kick(B.vpos, a.Reach, 0.5)
	end)
	dropStarts(B, t0, a, a.Tell + a.Crouch, 3)
end

function SlotSpawns.SwingDrop(B, i, spot, t0)
	if i == 3 then
		local a = B.def.Attacks.SwingDrop
		jumpCircle(B, t0, a, a.Tell + a.Crouch, 3)
	end
end

function Starts.DirtFling(B, t0)
	local a = B.def.Attacks.DirtFling
	at(B, t0 + 0.1, function()
		playSound(B.def, "Dig", B.vpos, 0.9)
		burst(onFloor(B.vpos + B.vfacing * 5), DIRT, 10, 10, 1.3, 0.5)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Swing", B.vpos, 0.7)
		burst((B.bladeMid or B.vpos) + V3(0, 1, 0), DIRT, 18, 20, 1.4, 0.5)
	end)
end

function SlotSpawns.DirtFling(B, i, spot, t0)
	local a = B.def.Attacks.DirtFling
	clod(B, spot, t0 + a.Tell, a)
end

function Starts.AnchorToss(B, t0)
	local a = B.def.Attacks.AnchorToss
	B.anchorT, B.anchorSpot, B.anchorYank, B.anchorFrom = t0, nil, nil, nil
	at(B, t0 + 0.05, function()
		playSound(B.def, "Relic", B.vpos, 1)
		burst((B.handL or B.vpos) + V3(0, 3, 0), RGB(254, 231, 97), 18, 10, 1, 0.8, true)
	end)
	at(B, t0 + 0.4, function()
		playSound(B.def, "Anchor", B.vpos, 0.7)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Anchor", B.vpos, 1)
	end)
	at(B, t0 + a.Tell + a.Flight, function()
		local spot = slot(B, 1) or B.anchorSpot
		if spot then
			shockRing(B, spot, 1.5, a.Radius * 1.3, 0.35, DIRT_DARK)
			burst(onFloor(spot) + V3(0, 1, 0), DIRT, 26, 24, 1.8, 0.6)
			playSound(B.def, "AnchorLand", spot, 1)
			kick(spot, a.Radius, 1, -3)
		end
	end)
end

function SlotSpawns.AnchorToss(B, i, spot, t0)
	if i == 1 then
		local a = B.def.Attacks.AnchorToss
		B.anchorSpot = spot
		landingCircle(B, function()
			return spot
		end, a.Radius, t0 + a.Tell, t0 + a.Tell + a.Flight, nil)
	end
end

function Starts.FireStick(B, t0)
	local a = B.def.Attacks.FireStick
	at(B, t0 + 0.05, function()
		playSound(B.def, "Relic", B.vpos, 1)
		burst((B.handL or B.vpos) + V3(0, 3, 0), RGB(254, 231, 97), 18, 10, 1, 0.8, true)
	end)
	for k = 1, a.Balls do
		at(B, t0 + a.Tell + (k - 1) * a.Gap, function()
			playSound(B.def, "Fire", B.vpos, 0.8)
			burst(B.wandTip or (B.vpos + V3(0, 7, 0)), FIRE, 12, 12, 1, 0.35, true)
		end)
	end
end

function SlotSpawns.FireStick(B, i, spot, t0)
	if i % 2 == 0 then
		local a = B.def.Attacks.FireStick
		local k = i / 2
		local from = slot(B, i - 1)
		if from then
			fireball(B, from, spot, t0 + a.Tell + (k - 1) * a.Gap, a)
		end
	end
end

function Starts.ChargeDash(B, t0)
	local a = B.def.Attacks.ChargeDash
	dashLane(B, a, t0)
	at(B, t0 + 0.08, function()
		playSound(B.def, "Dig", B.vpos, 0.6)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Dash", B.vpos, 1)
		burst(B.vpos + V3(0, 0.6, 0), DIRT, 20, 20, 1.6, 0.5)
	end)
	-- the end of the charge (its length is only known once he commits)
	local done = false
	addTelegraph(B, {
		update = function(now)
			local travel = B.model:GetAttribute("ActN")
			if B.action ~= "ChargeDash" then
				return false
			end
			if type(travel) ~= "number" or done then
				return not done
			end
			if now >= t0 + a.Tell + travel then
				done = true
				local to = slot(B, 2) or B.vpos
				if slot(B, 3) then
					playSound(B.def, "Crash", to, 1)
					shockRing(B, to, 2, 14, 0.4, WHITE)
					burst(to + V3(0, 4, 0), RGB(254, 231, 97), 16, 14, 1, 0.6, true)
					kick(to, 20, 1.2, -4)
				else
					burst(onFloor(to) + V3(0, 0.6, 0), DIRT, 24, 18, 1.8, 0.6)
					kick(to, 14, 0.5)
				end
			end
			return true
		end,
		cleanup = function() end,
	})
end

function Starts.Taunt(B, t0)
	local a = B.def.Attacks.Taunt
	at(B, t0 + 0.35, function()
		playSound(B.def, "Taunt", B.vpos, 1)
		laughBubble(B, a.Time - 0.35)
	end)
end

function Starts.GemRain(B, t0)
	local a = B.def.Attacks.GemRain
	at(B, t0 + 0.1, function()
		burst((B.bladeTip or B.vpos) + V3(0, 1, 0), RGB(254, 231, 97), 16, 8, 1, 0.9, true)
	end)
	at(B, t0 + a.Tell, function()
		local spot = onFloor(B.bladeTip or B.vpos)
		shockRing(B, spot, 1, 18, 0.45, RGB(254, 231, 97))
		burst(spot + V3(0, 1, 0), RGB(254, 231, 97), 30, 26, 1.6, 0.7, true)
		playSound(B.def, "Land", spot, 0.9)
		kick(spot, 20, 0.9, -3)
		-- a glitter high above: the treasure's on its way
		burst(B.vpos + V3(0, 40, 0), RGB(254, 231, 97), 40, 18, 2, 1.2)
	end)
end

function Starts.ShovelMeteor(B, t0)
	local a = B.def.Attacks.ShovelMeteor
	local land = t0 + a.Tell + a.Up + a.Fall
	meteorShadow(B, a, t0 + a.Tell + a.Up * 0.6, land)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Jump", B.vpos, 1)
		shockRing(B, B.vpos, 1, 16, 0.4, DIRT_DARK)
		burst(B.vpos + V3(0, 1, 0), DIRT, 34, 30, 2, 0.7, true)
		kick(B.vpos, 20, 0.9, -3)
	end)
	at(B, land - 0.3, function()
		-- a streak of fire as he plunges
		local p = onFloor(slot(B, 1) or B.vpos)
		for k = 1, 5 do
			burst(p + V3(0, 16 + k * 12, 0), (k % 2 == 0) and FIRE or FIRE_HOT, 8, 8, 2, 0.4)
		end
	end)
	at(B, land, function()
		local spot = slot(B, 1) or B.vpos
		playSound(B.def, "Meteor", spot, 1)
		shockRing(B, spot, 3, a.Radius * 1.3, 0.6, WHITE)
		shockRing(B, spot, 2, a.Radius * 0.9, 0.45, DIRT_DARK)
		for k = 0, 7 do
			local ang = k / 8 * math.pi * 2
			burst(onFloor(spot) + V3(math.cos(ang) * a.Radius * 0.6, 1, math.sin(ang) * a.Radius * 0.6), DIRT, 14, 20, 2, 0.7, true)
		end
		kick(spot, a.Radius + 20, 1.8, -7)
	end)
end

function Starts.Wake(B, t0)
	local W = B.def.WakeTime
	at(B, t0 + W * 0.2, function()
		burst(B.vpos + V3(0, 10, 0), B.def.EyeColor, 8, 4, 0.6, 0.6, true)
	end)
	at(B, t0 + W * 0.5, function()
		burst(onFloor(B.vpos + B.vfacing * 2.5) + V3(0, 0.6, 0), DIRT, 22, 20, 1.6, 0.6, true)
		playSound(B.def, "Dig", B.vpos, 0.8)
	end)
	at(B, t0 + W * 0.76 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W * 0.77, function()
		burst((B.bladeTip or B.vpos) + V3(0, 1, 0), RGB(254, 231, 97), 20, 12, 1, 0.8, true)
		kick(B.vpos, 30, 0.8, -3)
	end)
end

function Starts.Dormant(B, t0)
	-- (back at home after a burrow: he pops up out of the dirt, kneeling)
	if B.prevAction == "Reset" then
		burst(B.vpos + V3(0, 1, 0), DIRT, 20, 16, 1.6, 0.6, true)
	end
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.4, function()
		burst(B.vpos + V3(0, 0.6, 0), DIRT, 24, 18, 1.8, 0.7, true)
		playSound(B.def, "Dig", B.vpos, 0.7)
	end)
	at(B, t0 + 1.2, function()
		burst(B.vpos + V3(0, 0.6, 0), DIRT, 30, 20, 2, 0.8, true)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + 0.05, function()
		playSound(def, "Break", B.vpos, 0.6)
	end)
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		platesFlyOff(B)
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, def.TrimColor or WHITE)
		burst(B.vpos + V3(0, 8, 0), def.TrimColor or WHITE, 50, 36, 2, 1, true)
		playSound(def, "Break", B.vpos, 1)
		kick(B.vpos, def.BreakReach, 1.3, -5)
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.3, function()
		playSound(def, "Death", B.vpos, 1)
	end)
	at(B, t0 + 1.1, function()
		burst(B.vpos + V3(0, 0.5, 0), DIRT, 16, 12, 1.4, 0.5)
		kick(B.vpos, 20, 0.5, -2)
	end)
	at(B, t0 + 3.6, function()
		-- popping into pixels
		for k = 1, 4 do
			burst(B.vpos + V3(0, 2 + k * 2.5, 0), (k % 2 == 0) and def.Color or (def.TrimColor or WHITE), 14, 14, 1.2, 0.8, true)
		end
	end)
	at(B, t0 + 4.1, function()
		treasureChest(B, B.vpos, B.vfacing)
	end)
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- what his moves are made of: dirt
function Body.fx(def)
	return { color = DIRT, deep = DIRT_DARK, rock = DIRT_DARK, material = Enum.Material.SmoothPlastic, solid = true }
end

-- a new move began: what's left of the last one lets go
function Body.onAction(B, name, t0, now)
	if name ~= "AnchorToss" and B.anchorT and not B.anchorYank then
		B.anchorYank = now -- (the anchor zips back to his hand)
	end
	if name == "Wake" or name == "Dormant" or name == "Reset" or name == "Death" then
		B.anchorT, B.anchorSpot, B.anchorYank = nil, nil, nil
	end
end

-- joined while his armour was already broken
function Body.lateBreak(B)
	B.phase2Look = true
end

-- every frame, whatever he's doing: the gem rain's treasure
function Body.signs(B, state)
	watchRain(B)
end

return Body
