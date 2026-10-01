--[[
	Tuber  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Tuber")

	How floor 2's boss (Config.Bosses[2]) looks on your screen, in both of his
	rounds:

	  TUBER (round 1): a chubby, potato-shaped stack of three lumpy cactus
	  blocks with a pink flower on top, dot eyes, rosy cheeks and a little
	  smile. He wobbles like jelly when he waddles. SPLIT!: the three blocks
	  pop apart into buddies (each with its own eyes) that curl up into spiky
	  balls and spin-dash, then sit there dizzy and hop back into a stack.

	  THE POWER-UP: he flops over, his flower wilts, the music stops... the
	  ground rumbles, a sandstorm whips up, and every cactus in the arena rips
	  out of the ground and flies to him. The pieces slam together into THE
	  BRUTE, a giant cactus golem - a crown drops onto his head, his eyes
	  light up red - while across your screen TUBER's letters shake, swap
	  places and turn red: BRUTE. THE slams down next to it. He roars, THE
	  CACTUS KING... THE DESERT BOWS: camels, meerkats, vultures and lizards
	  have come to watch, and they bow. His second health bar fills and the
	  music slams in. (Your camera swoops round him for it: kit.shot.)

	  THE BRUTE (round 2): the golem - legs like tree trunks with roots that
	  dig into the sand (they wriggle when his hop is ready), arms made of
	  cactus balls, a barrel-cactus head with a crown and burning red eyes,
	  spines all over. Everything he plants round the arena (walls, turrets,
	  buddies, quicksand: Workspace.TuberProps) is drawn here too, and the
	  quicksand really drags you.

	  THE END: he freezes, cracks... and crumbles into a heap of cactus balls
	  that roll away. Out of the rubble pops tiny Tuber, flower wilted, who
	  waddles off in a huff.

	Everything is drawn from what the server publishes - see
	ServerScriptService/Bosses/Tuber.lua, where each move is explained. The
	hops and the rolling balls use the server's own sums, so they're drawn
	exactly where they really are.

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one also draws
	his health bars (barLook: one per round) and picks the music (music:
	round 1's song, silence in the power-up, round 2's song).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Body = {}
-- (which arena copy is this boss's: ReplicatedStorage/Arenas)
local Arenas = require(game:GetService("ReplicatedStorage"):WaitForChild("Arenas"))

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, easeOut, easeOutBack, spring, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, removeRing, burst
local kick, playSound, addTelegraph, at, SLOT_NAMES, myRoot
local bigText, shout, shot

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config (all from the game's 32)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local HOT = RGB(255, 0, 68)
local YELLOW = RGB(254, 231, 97)
local ORANGE = RGB(247, 118, 34)
local PINK = RGB(246, 117, 122)
local SAND = RGB(228, 166, 114)
local SAND_DARK = RGB(184, 111, 80)
local SAND_LIGHT = RGB(234, 212, 170)
local BROWN = RGB(115, 62, 57)
local TAN = RGB(194, 133, 105)
local SKIN = RGB(232, 183, 150)
local PLUM = RGB(62, 39, 49)
local WILTED = RGB(184, 111, 80)
local PIXEL_FONT = nil

local STACK = 3.2 -- (each of his segments' height in the stack: the server's number)
-- his three segments, bottom to top: width, height, depth
local SEG = { V3(5.6, 3.4, 5.2), V3(5.0, 3.4, 4.6), V3(4.6, 3.4, 4.4) }

function Body.init(kit)
	serverNow, clamp, lerp, smooth = kit.serverNow, kit.clamp, kit.lerp, kit.smooth
	easeOut, easeOutBack, spring, flat = kit.easeOut, kit.easeOutBack, kit.spring, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	removeRing, burst = kit.removeRing, kit.burst
	kick, playSound, addTelegraph, at = kit.kick, kit.playSound, kit.addTelegraph, kit.at
	SLOT_NAMES, myRoot = kit.SLOT_NAMES, kit.myRoot
	bigText, shout, shot = kit.bigText, kit.shout, kit.shot
	pcall(function()
		PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
end

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function slot(B, i)
	local v = B.model:GetAttribute(SLOT_NAMES[i])
	return typeof(v) == "Vector3" and v or nil
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

local function num(v, fallback)
	return type(v) == "number" and v or fallback
end

-- the ground under him (the arena floor's height)
local function floorY(B)
	local root = B.model.PrimaryPart
	if root then
		return root.Position.Y - root.Size.Y / 2
	end
	return B.vpos.Y
end

local function atFloor(B, p)
	return V3(p.X, floorY(B), p.Z)
end

-- a block stretched from a to b (world points), `w` wide and `h` tall
local function stretch(p, a, b, w, h)
	local dir = b - a
	local len = dir.Magnitude
	local center = (a + b) / 2
	if len < 1e-3 then
		p.Size = V3(w, h, 0.05)
		p.CFrame = CFrame.new(center)
		return
	end
	p.Size = V3(w, h, len)
	local up = V3(0, 1, 0)
	if math.abs(dir.Unit.Y) > 0.98 then
		up = V3(1, 0, 0)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- How high something is `e` seconds into a hop of `air` seconds (the
-- server's own sum: Bosses/Tuber.lua's arcHeight)
local function arcHeight(e, air, rise, height)
	if e <= 0 or e >= air then
		return 0
	end
	local up = air * rise
	if e < up then
		local u = e / up
		return height * (1 - (1 - u) * (1 - u))
	end
	local v = (e - up) / math.max(air - up, 1e-3)
	return height * (1 - v * v)
end

local function pathLength(pts)
	local n = 0
	for i = 2, #pts do
		n = n + flat(pts[i] - pts[i - 1]).Magnitude
	end
	return n
end

-- where along a path something is, `dist` studs from its start (the server's sum)
local function pointAlong(pts, dist)
	for i = 2, #pts do
		local seg = flat(pts[i] - pts[i - 1]).Magnitude
		if dist <= seg or i == #pts then
			local u = seg > 1e-3 and clamp(dist / seg, 0, 1) or 1
			return pts[i - 1]:Lerp(pts[i], u)
		end
		dist = dist - seg
	end
	return pts[#pts]
end

-- which way along a path something is heading, `dist` studs from its start
local function headingAlong(pts, dist, fallback)
	for i = 2, #pts do
		local d = flat(pts[i] - pts[i - 1])
		local seg = d.Magnitude
		if (dist <= seg or i == #pts) and seg > 1e-3 then
			return d.Unit
		end
		dist = dist - seg
	end
	return fallback
end

-- a steady "random" number (0-1) from a seed: the same on every screen, and
-- it doesn't touch math.random (other bosses' wobbles use that)
local function hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- one of his sounds, played only if you're in his arena
local function sfx(B, key, volume, where)
	if B.here then
		playSound(B.def, key, where or B.vpos, volume or 1)
	end
end

-- a word bubble over him
local function yell(B, text, seconds, color, part)
	if B.here then
		pcall(function()
			shout(part or B.body.anchor, text, seconds or 1, color or YELLOW)
		end)
	end
end

-- big pixel words across the screen (only if you're in his arena)
local function banner(B, text, opts)
	if B.here then
		pcall(function()
			bigText(text, opts)
		end)
	end
end

----------------------------------------------------------------------
-- His body: both forms, built once
----------------------------------------------------------------------
-- THE BRUTE, part by part: which bone it hangs from, its size, where it sits
-- on the bone (x right, y up, z back: his face looks down -z), its colour,
-- and when it slams into place during the power-up (seconds into it).
local function bruteParts(def)
	local green, deep, core = def.Color, def.DeepColor, def.CoreColor
	local eye, crown, spine = def.RageColor or HOT, def.CrownColor or ORANGE, def.SpineColor or SAND_LIGHT
	local list = {}
	local function add(name, bone, size, pos, color, material, joinAt, extra)
		local rec = { name = name, bone = bone, size = size, pos = pos, color = color, material = material, joinAt = joinAt }
		for k, v in pairs(extra or {}) do
			rec[k] = v
		end
		table.insert(list, rec)
		return rec
	end
	for _, s in ipairs({ -1, 1 }) do
		local side = (s < 0) and "L" or "R"
		add("Foot", "leg" .. side, V3(5, 1.2, 6), V3(0, 0.6, -0.6), deep, nil, 1.9)
		add("Shin", "leg" .. side, V3(4.4, 4.6, 4.4), V3(0, 2.3, 0), green, nil, 2.0)
		add("Thigh", "thigh" .. side, V3(4.0, 1, 4.0), V3(0, 0, 0), green, nil, 2.1, { thigh = true })
		for r = 1, 3 do
			add("Root", "leg" .. side, V3(0.6, 0.6, 3.4), V3(0, 0, 0), BROWN, nil, 2.0, { root = r, side = s })
		end
	end
	add("Pelvis", "hips", V3(8.6, 5, 7), V3(0, 0.5, 0), green, nil, 2.4)
	add("Belly", "hips", V3(5.6, 3.6, 0.5), V3(0, 0.6, -3.6), deep, nil, 2.5)
	add("Chest", "chest", V3(10.4, 6.2, 7.6), V3(0, 3.1, 0), green, nil, 2.7)
	add("ChestLump", "chest", V3(6, 4, 0.6), V3(-1.4, 3.6, -4.0), deep, nil, 2.8)
	for _, s in ipairs({ -1, 1 }) do
		local side = (s < 0) and "L" or "R"
		add("Upper", "arm" .. side, V3(4.2, 4.2, 4.2), V3(0, -2.2, 0), green, nil, 3.0)
		add("Lower", "arm" .. side, V3(3.8, 3.8, 3.8), V3(0, -5.8, 0), green, nil, 3.2)
		add("Fist", "arm" .. side, V3(4.8, 4.4, 4.8), V3(0, -9.6, 0), deep, nil, 3.4)
	end
	add("Head", "head", V3(7.2, 6, 6.6), V3(0, 3, 0), green, nil, 3.6)
	add("Brow", "head", V3(6.2, 1.1, 1.0), V3(0, 4.4, -3.35), core, nil, 3.7)
	add("Eye", "head", V3(1.4, 0.9, 0.3), V3(-1.6, 3.55, -3.45), eye, Enum.Material.Neon, 4.5, { eye = true })
	add("Eye", "head", V3(1.4, 0.9, 0.3), V3(1.6, 3.55, -3.45), eye, Enum.Material.Neon, 4.5, { eye = true })
	add("Mouth", "head", V3(4.2, 1.0, 0.3), V3(0, 1.5, -3.45), INK, nil, 3.7, { mouth = true })
	for i = -1, 1 do
		add("Tooth", "head", V3(0.6, 0.6, 0.35), V3(i * 1.25, 1.85, -3.5), spine, nil, 3.8, { tooth = true })
	end
	add("Crown", "head", V3(7.6, 1.2, 7.0), V3(0, 6.6, 0), crown, nil, 4.4, { crown = true })
	for _, c in ipairs({ { -2.8, -2.6 }, { 0, -2.9 }, { 2.8, -2.6 }, { -2.2, 2.6 }, { 2.2, 2.6 } }) do
		add("CrownSpike", "head", V3(1.0, 2.2, 1.0), V3(c[1], 8.2, c[2]), crown, nil, 4.4, { crown = true })
	end
	add("CrownGem", "head", V3(1.0, 1.0, 0.4), V3(0, 6.6, -3.55), eye, Enum.Material.Neon, 4.4, { crown = true })
	add("FlowerHeart", "head", V3(1.2, 0.9, 1.2), V3(0, 7.7, 0.8), ORANGE, nil, 4.5, { flower = true })
	add("FlowerPetal", "head", V3(2.4, 0.45, 0.9), V3(0, 7.5, 0.8), RED_DARK, nil, 4.5, { flower = true })
	add("FlowerPetal", "head", V3(0.9, 0.45, 2.4), V3(0, 7.5, 0.8), RED_DARK, nil, 4.5, { flower = true })
	-- his spines: where each sits and which way it sticks out
	local spines = {
		{ "chest", V3(-4.4, 4.8, -3.9), V3(0, 0, -1) }, { "chest", V3(3.6, 2.0, -3.9), V3(0, 0, -1) },
		{ "chest", V3(1.2, 5.4, -3.9), V3(0, 0, -1) }, { "chest", V3(5.3, 3.8, 1.0), V3(1, 0, 0) },
		{ "chest", V3(-5.3, 2.0, -1.0), V3(-1, 0, 0) }, { "chest", V3(0, 3.0, 3.9), V3(0, 0, 1) },
		{ "hips", V3(4.4, 1.4, -2.0), V3(1, 0, 0) }, { "hips", V3(-4.4, -0.2, 1.4), V3(-1, 0, 0) },
		{ "head", V3(3.7, 3.2, -1.0), V3(1, 0, 0) }, { "head", V3(-3.7, 2.4, 0.8), V3(-1, 0, 0) },
		{ "head", V3(0, 3.4, 3.4), V3(0, 0, 1) }, { "armL", V3(-2.2, -2.4, 0), V3(-1, 0, 0) },
		{ "armL", V3(0, -6.0, -2.0), V3(0, 0, -1) }, { "armR", V3(2.2, -2.4, 0), V3(1, 0, 0) },
		{ "armR", V3(0, -6.0, -2.0), V3(0, 0, -1) }, { "legL", V3(-2.3, 2.6, 0), V3(-1, 0, 0) },
		{ "legR", V3(2.3, 2.6, 0), V3(1, 0, 0) }, { "hips", V3(0, -1.4, 3.6), V3(0, 0, 1) },
	}
	for i, sp in ipairs(spines) do
		add("Spine", sp[1], V3(0.35, 0.35, 1.2), sp[2] + sp[3] * 0.5, spine, nil, 2.0 + hash(i) * 2.0, { out = sp[3] })
	end
	return list
end

function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {} }
	local function add(name, color, material, group, parent)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 1, parent or folder)
		table.insert(body.all, { part = p, color = p.Color, group = group })
		return p
	end
	local green, deep = def.Color, def.DeepColor
	local spine = def.SpineColor or SAND_LIGHT
	-- LITTLE TUBER: three lumpy segments (1 = bottom, 3 = his head)
	body.segs = {}
	for k = 1, 3 do
		local seg = {
			core = add("Segment", green, nil, "stack"),
			lump = add("Lump", deep, nil, "stack"),
			spines = {},
			eyes = {},
		}
		for i = 1, 4 do
			seg.spines[i] = add("Spine", spine, nil, "stack")
		end
		if k < 3 then
			-- (the bottom two only show their eyes when he's split up)
			for i = 1, 2 do
				seg.eyes[i] = add("BuddyEye", def.EyeColor or INK, nil, "stack")
			end
		end
		body.segs[k] = seg
	end
	body.face = {
		eyes = { add("Eye", def.EyeColor or INK, nil, "stack"), add("Eye", def.EyeColor or INK, nil, "stack") },
		blush = { add("Blush", PINK, nil, "stack"), add("Blush", PINK, nil, "stack") },
		mouth = add("Mouth", INK, nil, "stack"),
	}
	body.flower = { heart = add("FlowerHeart", YELLOW, nil, "stack"), petals = {} }
	for i = 1, 4 do
		body.flower.petals[i] = add("FlowerPetal", def.FlowerColor or PINK, nil, "stack")
	end
	body.arms = { add("Arm", green, nil, "stack"), add("Arm", green, nil, "stack") }
	-- THE BRUTE
	body.brute = {}
	for _, rec in ipairs(bruteParts(def)) do
		rec.part = add("Brute" .. rec.name, rec.color, rec.material, "brute")
		table.insert(body.brute, rec)
	end
	-- dizzy stars, his shadow, and an invisible anchor that follows his head
	-- (word bubbles and hints hang over it)
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon, "fx")
	end
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 1, folder)
	body.anchor = newPart("Anchor", nil, WHITE, nil, 1, folder)
	body.anchor.Size = V3(0.2, 0.2, 0.2)
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- SPLIT!: where each of his three buddies is (1 = bottom, 2 = middle, 3 =
-- his head), how high off the ground, and what it's doing - the server's
-- own sums (Bosses/Tuber.lua's splitPos), from the spots it publishes
----------------------------------------------------------------------
local function splitPos(B, k, now)
	local S = B.split
	local a = B.def.Attacks.Split
	local popStart = S.t0 + a.Shake
	local pop = S.pops[k] or S.base
	if now < popStart then
		return S.base, (k - 1) * STACK, "stack"
	end
	if now < S.popEnd then
		local u = (now - popStart) / a.Pop
		return S.base:Lerp(pop, u), arcHeight(now - popStart, a.Pop, 0.5, 4 + (k - 1) * 2) + (k - 1) * STACK * (1 - u), "hop"
	end
	local ball = S.balls[k]
	if not ball or now < ball.launch then
		return pop, 0, "rev"
	end
	if now < ball.stop then
		return pointAlong(ball.pts, (now - ball.launch) * a.Speed), 0, "roll"
	end
	local stopAt = ball.pts[#ball.pts]
	if not S.rally or now < (S.restackAt or math.huge) then
		return stopAt, 0, "dizzy"
	end
	local u = clamp((now - S.restackAt) / a.Restack, 0, 1)
	return stopAt:Lerp(S.rally, u), arcHeight(now - S.restackAt, a.Restack, 0.5, 6 + (k - 1) * 2) + (k - 1) * STACK * u, "hop"
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
local vis, tint -- (this frame: which parts show, how see-through, recoloured)

local function show(p, cf, size, tr)
	p.CFrame = cf
	p.Size = V3(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	vis[p] = tr or 0
end

local EYES = {
	open = { 0.55, 0.8 }, shut = { 0.85, 0.18 }, happy = { 0.8, 0.26 }, wide = { 0.7, 0.95 }, dizzy = { 0.8, 0.2 },
}
local MOUTHS = {
	smile = { 1.0, 0.28, 0 }, grin = { 1.5, 0.32, 0 }, o = { 0.6, 0.6, -0.1 }, open = { 1.2, 0.85, -0.2 },
	sad = { 0.9, 0.22, -0.25 }, sniff = { 0.5, 0.2, 0 },
}

-- one of little Tuber's segments (k), its middle at `cf`, `d` its size
local function placeSegment(B, P, k, cf, d, split, mode, fade)
	local body = B.body
	local seg = body.segs[k]
	local w, h, dd = d.X, d.Y, d.Z
	show(seg.core, cf, d, fade)
	-- (a lump poking out of one side makes him potato-shaped)
	show(seg.lump, cf * CFrame.new(w * 0.2 * ((k % 2 == 0) and -1 or 1), -h * 0.06, -dd * 0.14), V3(w * 0.72, h * 0.8, dd * 0.8), fade)
	local sp = { { w / 2, 0.15 * h, 0.2 * dd, V3(1, 0, 0) }, { -w / 2, -0.1 * h, -0.2 * dd, V3(-1, 0, 0) },
		{ 0.25 * w, 0.2 * h, -dd / 2, V3(0, 0, -1) }, { -0.2 * w, -0.05 * h, dd / 2, V3(0, 0, 1) } }
	for i, s in ipairs(sp) do
		local at0 = cf * CFrame.new(s[1], s[2], s[3])
		local out = cf:VectorToWorldSpace(s[4])
		show(seg.spines[i], CFrame.lookAt(at0.Position + out * 0.35, at0.Position + out), V3(0.25, 0.25, 0.8), fade)
	end
	if k < 3 and split and mode ~= "roll" then
		-- (a buddy's own little eyes, when he's split up)
		for i, e in ipairs(seg.eyes) do
			local shape = (mode == "dizzy") and EYES.dizzy or EYES.open
			local x = (i == 1) and -0.7 or 0.7
			local tilt = (mode == "dizzy") and ((i == 1) and 0.5 or -0.5) or 0
			show(e, cf * CFrame.new(x, 0.35, -dd / 2 - 0.06) * CFrame.Angles(0, 0, tilt), V3(shape[1] * 0.8, shape[2] * 0.8, 0.12), fade)
		end
	end
	if k == 3 then
		-- his face and his flower
		local face = body.face
		local eye = EYES[P.eyes or "open"] or EYES.open
		for i, e in ipairs(face.eyes) do
			local x = (i == 1) and -0.95 or 0.95
			local tilt = ((P.eyes == "dizzy") and ((i == 1) and 0.5 or -0.5)) or 0
			local y = (P.eyes == "happy") and 0.45 or 0.35
			show(e, cf * CFrame.new(x, y, -dd / 2 - 0.06) * CFrame.Angles(0, 0, tilt), V3(eye[1], eye[2], 0.12), fade)
		end
		for i, b in ipairs(face.blush) do
			local x = (i == 1) and -1.55 or 1.55
			show(b, cf * CFrame.new(x, -0.3, -dd / 2 - 0.05), V3(0.75, 0.32, 0.1), (P.blush == false) and 1 or fade)
		end
		local m = MOUTHS[P.mouth or "smile"] or MOUTHS.smile
		show(face.mouth, cf * CFrame.new(0, -0.62 + m[3], -dd / 2 - 0.06), V3(m[1], m[2], 0.12), fade)
		local wilt = clamp(P.wilt or 0, 0, 1)
		local top = cf * CFrame.new(0, h / 2, 0)
		show(body.flower.heart, top * CFrame.new(0, 0.3 - wilt * 0.2, 0), V3(0.85, 0.5, 0.85), fade)
		tint[body.flower.heart] = YELLOW:Lerp(WILTED, wilt)
		for i, petal in ipairs(body.flower.petals) do
			local a = (i - 1) * math.pi / 2 + math.pi / 4
			local out = V3(math.sin(a), 0, math.cos(a))
			local droop = wilt * 1.0
			local pcf = top * CFrame.new(out * (0.72 + wilt * 0.15) + V3(0, 0.22 - droop * 0.55, 0))
			pcf = CFrame.lookAt(pcf.Position, pcf.Position + top:VectorToWorldSpace(out)) * CFrame.Angles(-droop, 0, 0)
			show(petal, pcf, V3(0.7, 0.3, 0.85), fade)
			tint[petal] = (B.def.FlowerColor or PINK):Lerp(WILTED, wilt)
		end
	elseif k == 2 then
		-- his stubby little arms (waving, flailing)
		for i, arm in ipairs(body.arms) do
			local s = (i == 1) and -1 or 1
			local up = (i == 1) and (P.armL or 0) or (P.armR or 0)
			local acf = cf * CFrame.new(s * (w / 2 + 0.4), 0.1 * h + up * 0.9, -0.1) * CFrame.Angles(0, 0, s * up * 0.9)
			show(arm, acf, V3(0.95, 0.95, 0.95), fade)
		end
	end
end

-- LITTLE TUBER, stacked (or lying on his side, or toppled flat, or sunk in
-- the sand asleep with just his head showing)
local function placeStack(B, P, base, look, now, scale, fade)
	scale = scale or 1
	local sx, sy = (P.sx or 1), (P.sy or 1)
	local cf = CFrame.lookAt(base, base + look)
	cf = cf * CFrame.new(0, (P.lift or 0) - (P.sink or 0), 0)
	if (P.topple or 0) > 0 then
		local pivot = SEG[1].Z / 2 * scale
		cf = cf * CFrame.new(0, 0, -pivot) * CFrame.Angles(-P.topple * math.pi / 2, 0, 0) * CFrame.new(0, 0, pivot)
	end
	if (P.side or 0) > 0 then
		local pivot = SEG[1].X / 2 * scale
		cf = cf * CFrame.new(pivot, 0, 0) * CFrame.Angles(0, 0, -P.side * math.pi / 2) * CFrame.new(-pivot, 0, 0)
	end
	if (P.lean or 0) ~= 0 then
		cf = cf * CFrame.new(0, 0, -SEG[1].Z / 2 * scale) * CFrame.Angles(-P.lean, 0, 0) * CFrame.new(0, 0, SEG[1].Z / 2 * scale)
	end
	if (P.shake or 0) > 0 then
		cf = cf + V3(math.sin(now * 53), 0, math.cos(now * 61)) * P.shake
	end
	local ground = floorY(B)
	for k = 1, 3 do
		local d = SEG[k] * scale
		d = V3(d.X * sx, d.Y * sy, d.Z * sx)
		local wob = (P.wobble or 0) * math.sin(now * 7 - k * 0.9) * (k - 1) * 0.22 * scale
		local segCF = cf * CFrame.new(wob, (k - 1) * STACK * scale * sy + d.Y / 2, 0)
		-- (a segment all the way under the sand doesn't show)
		local under = segCF.Position.Y + d.Y / 2 < ground - 0.1 and (P.topple or 0) == 0 and (P.side or 0) == 0
		placeSegment(B, P, k, segCF, d, false, nil, under and 1 or fade)
	end
	B.headTop = (cf * CFrame.new(0, 3 * STACK * scale * sy + 1.5, 0)).Position
end

-- LITTLE TUBER, split into three buddies (each where the server says)
local function placeSplit(B, P, now)
	local look = unitOr(flat(B.faceDir or B.vfacing), V3(0, 0, -1))
	local a = B.def.Attacks.Split
	local ground = floorY(B)
	local headTop = nil
	for k = 1, 3 do
		local pos, up, mode = splitPos(B, k, now)
		local d = SEG[k]
		local face = look
		local spin = nil
		if mode == "roll" then
			local S = B.split
			local ball = S.balls[k]
			local dist = (now - ball.launch) * a.Speed
			face = headingAlong(ball.pts, dist, look)
			spin = dist / 2.4
			d = V3(4.4, 4.4, 4.4) -- (curled up into a spiky ball)
		elseif mode == "rev" then
			local S = B.split
			local lane = S.lanes and S.lanes[k]
			if lane then
				face = unitOr(flat(lane[2] - lane[1]), look)
			end
			local rev = clamp((now - (S.popEnd + (k - 1) * a.Gap)) / a.Rev, 0, 1)
			spin = rev * rev * 18 -- (revving up on the spot, faster and faster)
			d = V3(lerp(d.X, 4.4, rev), lerp(d.Y, 4.4, rev), lerp(d.Z, 4.4, rev))
		elseif mode == "dizzy" then
			local root = myRoot()
			face = root and unitOr(flat(root.Position - pos), look) or look
		end
		local center = V3(pos.X, ground + up + d.Y / 2, pos.Z)
		local cf = CFrame.lookAt(center, center + face)
		if spin then
			cf = cf * CFrame.Angles(-spin, 0, 0)
		end
		if mode == "dizzy" then
			cf = cf * CFrame.Angles(0, 0, math.sin(now * 5 + k) * 0.12)
		end
		placeSegment(B, P, k, cf, d, true, mode, 0)
		if k == 3 then
			headTop = center + V3(0, d.Y / 2 + 1.2, 0)
		end
	end
	B.headTop = headTop
end

-- SPLIT UP WHEN THE POWER-UP HIT: his three buddies hop back together (from
-- wherever they were, even mid-dash) onto the spot he'll stand on now
local REJOIN = 0.45
local function placeRejoin(B, P, base, look, now)
	local R = B.rejoin
	local e = now - R.t0
	local u = clamp(e / REJOIN, 0, 1)
	local ground = floorY(B)
	for k = 1, 3 do
		local from = R.from[k] or { pos = base, up = (k - 1) * STACK }
		local pos = from.pos:Lerp(base, u)
		local up = from.up * (1 - u) + arcHeight(e, REJOIN, 0.5, 4 + (k - 1) * 2) + (k - 1) * STACK * u
		local d = SEG[k]
		local center = V3(pos.X, ground + up + d.Y / 2, pos.Z)
		placeSegment(B, P, k, CFrame.lookAt(center, center + look), d, true, "hop", 0)
		if k == 3 then
			B.headTop = center + V3(0, d.Y / 2 + 1.2, 0)
		end
	end
end

-- a spot on one of the Brute's bones
local function bruteBones(B, P, base, look, now)
	local lift = P.lift or 0
	local crouch = clamp(P.crouch or 0, 0, 1)
	local hipY = 10 - crouch * 3 - (P.sink or 0)
	local root = CFrame.lookAt(base, base + look) + V3(0, lift - (P.sink or 0), 0)
	if (P.shake or 0) > 0 then
		root = root + V3(math.sin(now * 53), 0, math.cos(now * 61)) * P.shake
	end
	local bones = { base = root }
	local tuck = clamp(lift / 12, 0, 1) * 1.6
	bones.legL = root * CFrame.new(-2.7, tuck, 0)
	bones.legR = root * CFrame.new(2.7, tuck, 0)
	local lean = P.lean or 0
	bones.hips = root * CFrame.new(0, hipY + (P.sink or 0), 0) * CFrame.Angles(-lean * 0.5, P.twist or 0, P.sway or 0)
	bones.chest = bones.hips * CFrame.new(0, 3, 0) * CFrame.Angles(-lean * 0.5, (P.twist or 0) * 0.5, 0)
	bones.head = bones.chest * CFrame.new(0, 6.2, 0) * CFrame.Angles(P.headPitch or 0, P.headYaw or 0, P.headRoll or 0)
	bones.armL = bones.chest * CFrame.new(-6.4, 4.8, 0) * CFrame.Angles(P.armLPitch or 0, 0, -(P.armLRoll or 0.12))
	bones.armR = bones.chest * CFrame.new(6.4, 4.8, 0) * CFrame.Angles(P.armRPitch or 0, 0, (P.armRRoll or 0.12))
	return bones
end

-- THE BRUTE. buildT = seconds into the power-up while he's being built (each
-- piece slams into place at its moment), or nil when he's whole.
local function placeBrute(B, P, base, look, now, buildT, fade)
	local body = B.body
	local bones = bruteBones(B, P, base, look, now)
	local glow = clamp(P.glow or 1, 0, 1.5)
	local eyeColor = (glow <= 1) and RED_DARK:Lerp(B.def.RageColor or HOT, glow) or (B.def.RageColor or HOT):Lerp(WHITE, glow - 1)
	local roar = clamp(P.roar or 0, 0, 1)
	local hopReady = B.hopReady
	for _, rec in ipairs(body.brute) do
		local p = rec.part
		local cf, size
		if rec.thigh then
			local s = (rec.bone == "thighL") and -1 or 1
			local knee = (bones[s < 0 and "legL" or "legR"] * CFrame.new(0, 4.4, 0)).Position
			local hip = (bones.hips * CFrame.new(s * 2.7, -1.6, 0)).Position
			local dir = hip - knee
			size = V3(4.0, 4.0, math.max(dir.Magnitude + 1.2, 1))
			cf = CFrame.lookAt((knee + hip) / 2, hip, look)
		elseif rec.root then
			-- his roots: dug into the sand while he's planted (wriggling when his
			-- hop is ready), ripped up when he hops
			local leg = bones[rec.side < 0 and "legL" or "legR"]
			local out = leg:VectorToWorldSpace(V3(rec.side, 0, 0))
			local ang = (rec.root - 2) * 0.95
			local c, sn = math.cos(ang), math.sin(ang)
			local dir = V3(out.X * c + out.Z * sn, 0, -out.X * sn + out.Z * c)
			local foot = leg.Position + V3(0, 0.3, 0)
			local ripped = clamp(P.roots or 0, 0, 1)
			local wig = hopReady and (math.sin(now * 9 + rec.root * 2 + rec.side) * 0.5) or 0
			local a0 = foot + dir * 2.2
			local b0 = a0 + dir * 3.2 + V3(0, lerp(-0.7, 2.6, ripped) + wig, 0)
			stretch(p, a0, b0, 0.6, 0.6)
			cf, size = p.CFrame, p.Size
		else
			local bone = bones[rec.bone]
			local pos = rec.pos
			size = rec.size
			if rec.mouth then
				size = V3(size.X, size.Y + roar * 1.8, size.Z)
				pos = pos - V3(0, roar * 0.9, 0)
			elseif rec.tooth then
				pos = pos + V3(0, roar * 0.25, 0)
			end
			cf = bone * CFrame.new(pos)
			if rec.out then
				local w = bone:VectorToWorldSpace(rec.out)
				cf = CFrame.lookAt(cf.Position, cf.Position + w)
			end
			if rec.eye then
				tint[p] = eyeColor
			end
		end
		local tr = fade or 0
		if buildT then
			local e = buildT - rec.joinAt
			if e < 0 then
				tr = 1
			elseif rec.crown and e < 0.35 then
				cf = cf + V3(0, (1 - e / 0.35) ^ 2 * 14, 0) -- (the crown drops onto his head)
			elseif e < 0.3 then
				local k = lerp(0.3, 1, easeOutBack(e / 0.3))
				size = size * k
				cf = cf + V3(0, (1 - e / 0.3) * 5, 0)
			end
		end
		show(p, cf, size, tr)
	end
	B.headTop = (bones.head * CFrame.new(0, 10.5, 0)).Position
	B.bruteBones = bones
end

-- THE END: every piece of the golem flies off and rolls away (each on its
-- own path, the same on every screen)
local function placeCrumble(B, now)
	local body = B.body
	local e0 = now - B.crumbleAt
	if not B.shards then
		B.shards = {}
		local c = (B.bruteBones and B.bruteBones.hips.Position) or (B.vpos + V3(0, 10, 0))
		for i, rec in ipairs(body.brute) do
			local p = rec.part
			local out = unitOr(flat(p.Position - c), V3(math.sin(i * 2.4), 0, math.cos(i * 2.4)))
			B.shards[p] = {
				cf = p.CFrame,
				size = p.Size,
				vel = out * (10 + hash(i) * 16) + V3(0, 8 + hash(i + 50) * 14, 0),
				spin = V3(hash(i + 7) - 0.5, hash(i + 9) - 0.5, hash(i + 11) - 0.5) * 12,
				delay = hash(i + 3) * 0.35,
			}
		end
	end
	local ground = floorY(B)
	for _, rec in ipairs(body.brute) do
		local p = rec.part
		local s = B.shards[p]
		if s then
			local tau = math.max(e0 - s.delay, 0)
			local pos = s.cf.Position + s.vel * tau + V3(0, -45 * tau * tau, 0)
			local low = ground + math.min(s.size.Y, 3) / 2
			if pos.Y < low then
				-- (hit the ground: now it rolls along it, slowing down)
				local tHit = (s.vel.Y + math.sqrt(math.max(s.vel.Y * s.vel.Y + 4 * 45 * (s.cf.Position.Y - low), 0))) / 90
				local roll = math.max(tau - tHit, 0)
				local flatVel = flat(s.vel)
				local rolled = flatVel * (tHit + (1 - math.exp(-roll * 1.5)) / 1.5)
				pos = V3(s.cf.Position.X + rolled.X, low, s.cf.Position.Z + rolled.Z)
			end
			local spin = s.spin * tau
			show(p, CFrame.new(pos) * CFrame.Angles(spin.X, spin.Y, spin.Z) * (s.cf - s.cf.Position), s.size, clamp((e0 - 2.2) / 0.8, 0, 1))
		end
	end
end

local function applyPose(B, P, ground, facing, t, dt)
	local body = B.body
	local now = serverNow()
	local _ = dt
	vis = B.vis or {}
	tint = B.tint or {}
	table.clear(vis)
	table.clear(tint)
	B.vis, B.tint = vis, tint
	local look = unitOr(flat(facing), V3(0, 0, -1))
	local base = V3(ground.X, floorY(B), ground.Z)
	local form = B.formShown or "Stack"
	local fade = clamp(P.fade or 0, 0, 1)
	if B.split and form == "Stack" and not B.crumbleAt then
		placeSplit(B, P, now)
	elseif B.rejoin and form == "Stack" and now < B.rejoin.t0 + REJOIN then
		placeRejoin(B, P, base, look, now)
	elseif form == "Stack" then
		placeStack(B, P, base, look, now, 1, fade)
	elseif form == "Morph" then
		-- THE POWER-UP: the golem slams together round little Tuber, who
		-- shrinks away inside it
		local bt = B.buildT or 0
		placeBrute(B, P, base, look, now, bt, 0)
		if bt < 2.6 then
			local k = clamp((bt - 1.8) / 0.8, 0, 1)
			placeStack(B, P, base, look, now, lerp(1, 0.45, k), k > 0.95 and 1 or 0)
		end
	elseif form == "Brute" then
		if B.crumbleAt and now >= B.crumbleAt then
			placeCrumble(B, now)
		else
			placeBrute(B, P, base, look, now, nil, fade)
		end
	end
	-- tiny Tuber, after the Brute crumbles: pops out of the rubble and
	-- waddles off in a huff
	if B.tinyAt and now >= B.tinyAt then
		local e = now - B.tinyAt
		local dir = B.tinyDir or look
		local walked = math.min(math.max(e - 0.6, 0), 4.5) * 2.4
		local tinyP = {
			sx = 1, sy = 1 + ((e < 0.6) and 0.3 * spring(e, 6, 14) or 0), eyes = (e < 0.6) and "wide" or "shut",
			mouth = "sad", wilt = 1, wobble = (walked < 10.8 and e > 0.6) and 1 or 0,
			lift = (e < 0.4) and arcHeight(e, 0.4, 0.5, 3) or 0,
		}
		local spot = B.tinyFrom + dir * walked
		placeStack(B, tinyP, V3(spot.X, floorY(B), spot.Z), dir, now, 0.42, 0)
	end
	-- dizzy stars round his head
	local dizzy = (P.dizzy or 0) > 0 and B.headTop
	for i, star in ipairs(body.stars) do
		if dizzy then
			local a = now * 4 + i * math.pi * 2 / 3
			local r = (form == "Brute") and 3.4 or 1.8
			show(star, CFrame.new(B.headTop + V3(math.cos(a) * r, math.sin(now * 6 + i) * 0.3, math.sin(a) * r)) * CFrame.Angles(0, a, 0.8),
				V3(0.6, 0.6, 0.6), 0)
		end
	end
	-- his shadow
	local lift = P.lift or 0
	local wide = (form == "Brute" or form == "Morph") and 13 or 7
	if not B.split and not B.crumbleAt and (P.sink or 0) < 5 then
		placeDisc(body.shadow, base + V3(0, 0.08, 0), wide * (1 - clamp(lift / 80, 0, 0.5)), 0.06)
		vis[body.shadow] = lerp(0.5, 0.85, clamp(lift / 40, 0, 1))
	end
	-- the anchor over his head (word bubbles hang from it)
	body.anchor.CFrame = CFrame.new(B.headTop or (base + V3(0, 10, 0)))
	-- which parts show, and their colour (white for a blink when he's hit)
	local flash = B.flashAt ~= nil and (os.clock() - B.flashAt) < 0.08
	for _, rec in ipairs(body.all) do
		local p = rec.part
		local tr = vis[p]
		p.Transparency = tr or 1
		if tr and tr < 1 then
			p.Color = flash and WHITE or (tint[p] or rec.color)
		end
	end
	body.shadow.Transparency = vis[body.shadow] or 1
	local _ = t
end

Body.pose = applyPose

----------------------------------------------------------------------
-- THE POWER-UP, out in the desert: the cacti fly to him, the animals come
-- to watch, the letters swap places, the camera swoops round him
----------------------------------------------------------------------
-- (all of it timed from the start of the power-up - BossService's "Break"
-- action - so a late arrival, or a hitch, sees exactly the right moment)
local T_FLOP, T_RUMBLE, T_FLY = 0.5, 1.2, 1.6
local T_BUILD, T_BUILT, T_TITLE, T_SHAKE, T_SWAP, T_SNAP = 1.8, 4.8, 4.6, 5.2, 5.6, 6.4
local T_THE, T_ROAR, T_KING, T_BOWS, T_BACK, T_END = 7.0, 7.2, 7.3, 8.0, 8.1, 8.7
local T_ANIMALS = 5.0
local T_WATCH, T_WATCHED = 5.05, 6.2 -- (the camera's long look at them turning up)

local function breakTime(B, now)
	if B.action == "Break" and B.actionStart then
		return now - B.actionStart
	end
	return nil
end

-- The arena's cacti (DunesBuilder tags them "DuneCactus"): each part's
-- place is remembered the first time it's seen, so the cactus can be ripped
-- out, flown into the golem, and put back exactly where it was.
local function cactiOf(B)
	B.cacti = B.cacti or {}
	B.cactusSeen = B.cactusSeen or {}
	if os.clock() < (B.cactiLook or -math.huge) + 2 then
		return B.cacti
	end
	B.cactiLook = os.clock()
	local added = false
	for _, m in ipairs(CollectionService:GetTagged("DuneCactus")) do
		if not B.cactusSeen[m] and m:IsA("Model") and m:GetAttribute("Floor") == B.floor and Arenas.inside(Arenas.arenaFor(B.model), m) then
			local hub = m.PrimaryPart or m:FindFirstChild("CactusBase")
			if hub then
				B.cactusSeen[m] = true
				local parts = {}
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(parts, { part = d, cf = d.CFrame, rel = hub.CFrame:ToObjectSpace(d.CFrame), tr = d.Transparency })
					end
				end
				table.insert(B.cacti, {
					model = m, hub = hub.CFrame, parts = parts, delay = num(m:GetAttribute("Delay"), 0.5),
					index = num(m:GetAttribute("Index"), #B.cacti + 1),
				})
				added = true
			end
		end
	end
	if added then
		table.sort(B.cacti, function(a, b)
			return a.index < b.index
		end)
	end
	return B.cacti
end

-- when each cactus rips out of the ground (seconds into the power-up), and when it arrives
local function cactusTimes(c)
	local rip = T_FLY + c.delay * 1.9
	return rip, rip + 0.25, rip + 1.05
end

local function stepCacti(B, now)
	local list = cactiOf(B)
	if #list == 0 then
		return
	end
	local t = breakTime(B, now)
	local form = B.model:GetAttribute("Form")
	local mode
	if t and B.here then
		mode = "fly"
	elseif form == "Brute" and B.stateNow ~= "Dormant" then
		mode = "gone"
	else
		mode = "home"
	end
	if mode == B.cactiMode and mode ~= "fly" then
		return -- (nothing's changed)
	end
	B.cactiMode = mode
	local center = B.vpos
	for i, c in ipairs(list) do
		local state = mode
		local e = 0
		if mode == "fly" then
			local rip, go, land = cactusTimes(c)
			if t < rip then
				state = "home"
			elseif t >= land then
				state = "gone"
			else
				state = (t < go) and "rip" or "air"
				e = (t < go) and (t - rip) / (go - rip) or (t - go) / (land - go)
			end
		end
		if state == "home" then
			for _, rec in ipairs(c.parts) do
				rec.part.CFrame = rec.cf
				rec.part.Transparency = rec.tr
			end
		elseif state == "gone" then
			for _, rec in ipairs(c.parts) do
				rec.part.Transparency = 1
			end
		else
			local hub
			local start = c.hub.Position
			if state == "rip" then
				-- tearing loose: shaking, lifting out of the sand
				local jig = V3(math.sin(now * 60 + i), 0, math.cos(now * 55 + i)) * 0.35
				hub = c.hub + V3(0, e * 2.5, 0) + jig
			else
				-- flying in an arc into his body, tumbling
				local goal = center + V3((hash(i) - 0.5) * 8, 6 + hash(i + 20) * 14, (hash(i + 40) - 0.5) * 6)
				local from = start + V3(0, 2.5, 0)
				local u = e * e * (3 - 2 * e)
				local pos = from:Lerp(goal, u) + V3(0, math.sin(e * math.pi) * (10 + hash(i + 60) * 10), 0)
				hub = CFrame.new(pos) * CFrame.Angles(e * 6 * (hash(i + 5) - 0.5), e * 8, e * 5 * (hash(i + 6) - 0.5)) * (c.hub - c.hub.Position)
			end
			for _, rec in ipairs(c.parts) do
				rec.part.CFrame = hub * rec.rel
				rec.part.Transparency = rec.tr
			end
		end
	end
end

-- THE AUDIENCE: the desert's animals come to watch the Cactus King fight,
-- at the lookouts DunesBuilder marks ("DuneLookout": a spot, and which
-- animal). Each is a few blocks: where each sits on the animal (x right, y
-- up, z back - it faces -z, toward the fight), its size and colour.
local LIZARD = RGB(190, 74, 47)
local ANIMALS = {
	Camel = {
		{ "Body", V3(2.4, 2.2, 4.4), V3(0, 3.9, 0), SAND }, { "Hump", V3(1.8, 1.3, 1.8), V3(0, 5.6, 0.3), TAN },
		-- (a bright saddle blanket, so you can pick him out against the sandstone)
		{ "Blanket", V3(2.7, 0.3, 2.8), V3(0, 5.05, 0.3), RED_DARK }, { "Blanket", V3(0.16, 1.1, 2.8), V3(-1.28, 4.5, 0.3), RED_DARK },
		{ "Blanket", V3(0.16, 1.1, 2.8), V3(1.28, 4.5, 0.3), RED_DARK }, { "Blanket", V3(0.2, 0.28, 2.9), V3(-1.3, 3.95, 0.3), YELLOW },
		{ "Blanket", V3(0.2, 0.28, 2.9), V3(1.3, 3.95, 0.3), YELLOW },
		{ "Neck", V3(0.9, 2.6, 0.9), V3(0, 5.2, -2.4), SAND }, { "Head", V3(1.1, 1.0, 2.0), V3(0, 6.6, -3.0), SAND },
		{ "Leg", V3(0.55, 2.8, 0.55), V3(-0.8, 1.4, -1.5), TAN }, { "Leg", V3(0.55, 2.8, 0.55), V3(0.8, 1.4, -1.5), TAN },
		{ "Leg", V3(0.55, 2.8, 0.55), V3(-0.8, 1.4, 1.5), TAN }, { "Leg", V3(0.55, 2.8, 0.55), V3(0.8, 1.4, 1.5), TAN },
	},
	Meerkat = {
		{ "Body", V3(0.9, 1.9, 0.8), V3(0, 1.0, 0), SKIN }, { "Head", V3(0.8, 0.75, 1.0), V3(0, 2.3, -0.1), SKIN },
		{ "Mask", V3(0.7, 0.2, 0.1), V3(0, 2.4, -0.62), PLUM }, { "Tail", V3(0.25, 0.25, 1.2), V3(0, 0.3, 0.8), TAN },
	},
	Vulture = {
		{ "Body", V3(1.3, 1.5, 2.0), V3(0, 1.2, 0), PLUM }, { "Wing", V3(2.4, 0.3, 1.5), V3(-1.6, 1.5, 0.2), PLUM },
		{ "Wing", V3(2.4, 0.3, 1.5), V3(1.6, 1.5, 0.2), PLUM }, { "Head", V3(0.6, 1.1, 0.6), V3(0, 2.3, -0.8), PINK },
		{ "Beak", V3(0.3, 0.3, 0.6), V3(0, 2.5, -1.3), YELLOW },
	},
	Lizard = {
		{ "Body", V3(0.7, 0.45, 2.0), V3(0, 0.25, 0), LIZARD }, { "Head", V3(0.6, 0.4, 0.8), V3(0, 0.3, -1.3), LIZARD },
		{ "Tail", V3(0.3, 0.25, 1.6), V3(0, 0.2, 1.7), RED_DARK },
	},
}

local function buildAudience(B)
	local list = {}
	local spots = {}
	for _, a in ipairs(CollectionService:GetTagged("DuneLookout")) do
		if a:IsA("BasePart") and a:GetAttribute("Floor") == B.floor and ANIMALS[a:GetAttribute("Kind")] and Arenas.inside(Arenas.arenaFor(B.model), a) then
			table.insert(spots, { cf = a.CFrame, kind = a:GetAttribute("Kind"), index = num(a:GetAttribute("Index"), #spots + 1) })
		end
	end
	table.sort(spots, function(a, b)
		return a.index < b.index
	end)
	for i, s in ipairs(spots) do
		local parts = {}
		for j, spec in ipairs(ANIMALS[s.kind]) do
			local p = newPart("Watcher" .. spec[1], nil, spec[4], nil, 1, B.body.folder)
			parts[j] = { part = p, spec = spec }
		end
		table.insert(list, { kind = s.kind, cf = s.cf, parts = parts, seed = i })
	end
	B.audience = list
end

-- where an animal is and how it moves at time `e` since it arrived (e < 0:
-- still on its way), `bow` (0-1) and `cheer` (0-1)
local function placeAnimal(an, now, e, bow, cheer, leave)
	local k = an.kind
	-- (a camel stands side-on to the fight with its head turned to watch -
	-- from the side you can tell it's a camel)
	local turn = (k == "Camel") and ((an.seed % 2 == 0) and 0.9 or -0.9) or 0
	local cf = an.cf * CFrame.Angles(0, turn, 0)
	local back = cf.LookVector * -1
	local tr = 0
	local offset, tilt = V3(), 0
	if e < 0 then
		tr = 1
	elseif k == "Camel" then
		local u = clamp(e / 1.8, 0, 1)
		offset = back * (1 - smooth(u)) * 10 -- (walks up to the ridge)
	elseif k == "Meerkat" then
		local u = clamp(e / 0.5, 0, 1)
		offset = V3(0, (easeOutBack(u) - 1) * 2.6, 0) -- (pops up out of its burrow)
	elseif k == "Vulture" then
		local u = clamp(e / 1.6, 0, 1)
		local s = 1 - smooth(u)
		offset = back * s * 14 + V3(0, s * 22, 0) -- (glides down onto its perch)
	elseif k == "Lizard" then
		local u = clamp(e / 0.6, 0, 1)
		offset = cf.RightVector * (1 - easeOut(u)) * 6 -- (scurries in)
	end
	if leave > 0 then
		if k == "Meerkat" or k == "Lizard" then
			offset = offset + V3(0, -leave * 3, 0)
		elseif k == "Vulture" then
			offset = offset + back * leave * 20 + V3(0, leave * 24, 0)
		else
			offset = offset + back * leave * 12
		end
		tr = (leave > 0.9) and 1 or tr
	end
	local hop = cheer > 0 and math.abs(math.sin(now * 8 + an.seed)) * 1.2 * cheer or 0
	tilt = bow * 0.55
	local base = (cf + offset + V3(0, hop, 0)) * CFrame.Angles(-tilt, 0, 0)
	for i, rec in ipairs(an.parts) do
		local spec = rec.spec
		local pos = spec[3]
		local extra = CFrame.new()
		local name = spec[1]
		if (name == "Head" or name == "Neck") and k == "Camel" then
			-- (turned round on his neck to look at the fight; the head chewing)
			local look = CFrame.Angles(0, -turn * 0.85, 0)
			local neckBase = V3(0, 4.9, -2.1)
			pos = neckBase + look * (pos - neckBase)
			extra = look
			if name == "Head" then
				pos = pos + V3(0, math.sin(now * 2.1 + an.seed) * 0.15, 0)
			end
		elseif name == "Head" and k == "Meerkat" then
			extra = CFrame.Angles(0, math.sin(now * 0.9 + an.seed * 1.7) * 0.9, 0) -- (looking round)
		elseif name == "Wing" and k == "Vulture" then
			local flap = (e < 1.6 or cheer > 0) and math.sin(now * 12) or ((now + an.seed) % 3.2 < 0.4 and math.sin(now * 16) or -0.2)
			extra = CFrame.Angles(0, 0, ((i == 2) and 1 or -1) * flap * 0.6)
		elseif name == "Leg" and k == "Camel" and e >= 0 and e < 1.8 then
			pos = pos + V3(0, 0, math.sin(now * 9 + i * 1.6) * 0.35) -- (walking)
		elseif k == "Lizard" and name == "Body" then
			pos = pos + V3(0, math.max(0, math.sin(now * 3 + an.seed)) * 0.2, 0) -- (push-ups)
		end
		local p = rec.part
		p.Size = spec[2]
		p.CFrame = base * CFrame.new(pos) * extra
		p.Transparency = tr
	end
end

local function stepAudience(B, now)
	local form = B.model:GetAttribute("Form")
	local t = breakTime(B, now)
	local watching = B.here and form == "Brute" and (t == nil or t >= T_ANIMALS)
	local dying = B.action == "Death" and B.actionStart and now - B.actionStart or nil
	if B.stateNow == "Dead" and dying == nil then
		dying = 99
	end
	if not watching then
		if B.audience and not B.audienceHidden then
			B.audienceHidden = true
			for _, an in ipairs(B.audience) do
				for _, rec in ipairs(an.parts) do
					rec.part.Transparency = 1
				end
			end
		end
		return
	end
	if not B.audience then
		buildAudience(B)
	end
	B.audienceHidden = false
	for i, an in ipairs(B.audience) do
		local e = 99
		if t then
			e = t - (T_ANIMALS + (i - 1) * 0.06)
		end
		local bow = 0
		if t and t >= T_BOWS then
			local b = t - T_BOWS - (i - 1) * 0.04
			bow = (b > 0 and b < 1.1) and math.sin(clamp(b / 1.1, 0, 1) * math.pi) or 0
		end
		local cheer, leave = 0, 0
		if dying then
			cheer = (dying > 2.5 and dying < 6) and 1 or 0
			leave = clamp((dying - 6) / 2, 0, 1)
		end
		placeAnimal(an, now, e, bow, cheer, leave)
	end
end

-- THE LETTERS: TUBER, bouncy and green... shaking... sliding into new
-- places, turning red: BRUTE. Then THE slams down next to it. (Built the
-- first time it's needed; every letter placed from the clock each frame.)
local LETTER_X = { -192, -96, 0, 96, 192 }
local SWAP = { 4, 3, 1, 5, 2 } -- (T U B E R -> B R U T E: where each letter goes)
local title = nil

local function buildTitle()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TuberTitle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 27
	gui.Enabled = false
	gui:SetAttribute("RetroSkip", true) -- (it has its own look)
	local flashBox = Instance.new("Frame")
	flashBox.Name = "Flash"
	flashBox.Size = UDim2.new(1, 0, 1, 0)
	flashBox.BackgroundColor3 = WHITE
	flashBox.BackgroundTransparency = 1
	flashBox.BorderSizePixel = 0
	flashBox.Parent = gui
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.3, 0)
	holder.Size = UDim2.new(0, 10, 0, 10)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local function label(name, text, w, h)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Size = UDim2.new(0, w, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Arcade
		if PIXEL_FONT then
			l.FontFace = PIXEL_FONT
		end
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = WHITE
		l.TextStrokeColor3 = INK
		l.TextStrokeTransparency = 0
		l.Parent = holder
		local s = Instance.new("UIScale")
		s.Parent = l
		return l, s
	end
	local letters = {}
	for i = 1, 5 do
		local l, s = label("Letter" .. i, string.sub("TUBER", i, i), 100, 120)
		letters[i] = { label = l, scale = s }
	end
	local the, theScale = label("The", "THE", 230, 110)
	local sub = label("Sub", "", 760, 40)
	sub.Position = UDim2.new(0, 35, 0, 105)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	title = { gui = gui, holder = holder, scale = scale, letters = letters, the = the, theScale = theScale, sub = sub, flash = flashBox }
end

local function stepTitle(B, now)
	local t = breakTime(B, now)
	local on = B.here and t and t >= T_TITLE and t < T_END + 0.3
	if not on then
		if title then
			title.gui.Enabled = false
		end
		return
	end
	if not title then
		pcall(buildTitle)
		if not title then
			return
		end
	end
	title.gui.Enabled = true
	-- (smaller on a small screen)
	pcall(function()
		local cam = Workspace.CurrentCamera
		local w = cam and cam.ViewportSize.X or 1000
		title.scale.Scale = clamp(w / 1000, 0.45, 1.2)
	end)
	local fadeOut = clamp((t - T_END) / 0.3, 0, 1)
	local green, red = B.def.Color or RGB(99, 199, 77), RED
	for i, L in ipairs(title.letters) do
		local x, y = LETTER_X[i], 0
		local s = 1
		local color = green
		local tIn = T_TITLE + (i - 1) * 0.08
		if t < tIn then
			s = 0
		elseif t < T_SHAKE then
			-- bouncy and green, each letter bobbing
			s = easeOutBack(clamp((t - tIn) / 0.25, 0, 1))
			y = math.sin(now * 6 + i) * 6
		elseif t < T_SWAP then
			-- shaking, harder and harder, going red
			local k = (t - T_SHAKE) / (T_SWAP - T_SHAKE)
			x = x + math.sin(now * 70 + i * 3) * 6 * k
			y = math.cos(now * 63 + i * 5) * 6 * k
			color = green:Lerp(red, k * 0.6)
		elseif t < T_SNAP then
			-- sliding into their new places (some over, some under)
			local u = smooth((t - T_SWAP) / (T_SNAP - T_SWAP))
			local to = LETTER_X[SWAP[i]] + 70
			x = lerp(LETTER_X[i], to, u)
			y = math.sin(u * math.pi) * 70 * ((i % 2 == 0) and -1 or 1)
			color = green:Lerp(red, 0.6 + 0.4 * u)
			s = 1 + math.sin(u * math.pi) * 0.25
		else
			-- BRUTE: snapped together, blood red
			x = LETTER_X[SWAP[i]] + 70
			local w = spring(t - T_SNAP, 7, 18)
			s = 1.15 + 0.3 * w
			color = (t - T_SNAP < 0.1) and WHITE or HOT
			if t >= T_THE and t < T_THE + 0.25 then
				y = math.sin((t - T_THE) / 0.25 * math.pi) * 8 -- (THE lands: everything jumps)
			end
		end
		L.label.Position = UDim2.new(0, x, 0, y)
		L.scale.Scale = s
		L.label.TextColor3 = color
		L.label.TextStrokeColor3 = (t >= T_SNAP) and RED_DARK or INK
		L.label.TextTransparency = fadeOut
		L.label.TextStrokeTransparency = fadeOut
	end
	-- THE: drops from the top of the screen and SLAMS down
	local the = title.the
	if t < T_THE - 0.18 then
		the.TextTransparency, the.TextStrokeTransparency = 1, 1
	else
		local u = clamp((t - (T_THE - 0.18)) / 0.18, 0, 1)
		local y = lerp(-420, 0, u * u)
		local squash = (t >= T_THE) and spring(t - T_THE, 6, 16) or 0
		the.Position = UDim2.new(0, LETTER_X[1] + 70 - 180, 0, y)
		title.theScale.Scale = 1 + squash * 0.25
		the.TextColor3 = (t >= T_THE and t < T_THE + 0.08) and WHITE or HOT
		the.TextStrokeColor3 = RED_DARK
		the.TextTransparency, the.TextStrokeTransparency = fadeOut, fadeOut
	end
	-- the white flash of it landing
	local f = (t >= T_THE) and clamp(1 - (t - T_THE) / 0.25, 0, 1) or 0
	title.flash.BackgroundTransparency = 1 - f * 0.6
	-- THE CACTUS KING... THE DESERT BOWS
	local sub = title.sub
	if t >= T_BOWS then
		sub.Text = "THE DESERT BOWS"
		sub.TextColor3 = B.def.CrownColor or ORANGE
	elseif t >= T_KING then
		sub.Text = "THE CACTUS KING"
		sub.TextColor3 = B.def.CrownColor or ORANGE
	else
		sub.Text = ""
	end
	local subIn = clamp((t - T_KING) / 0.3, 0, 1)
	sub.TextTransparency = math.max(1 - subIn, fadeOut)
	sub.TextStrokeTransparency = math.max(1 - subIn, fadeOut)
end

-- THE DESERT COMES TO WATCH: a long lens, from just in front of the golem,
-- on the nearest camel's ledge as the animals turn up (the camel low in the
-- picture, under the letters; the lens zoomed so it's the same size however
-- far away it is)
local function watchShot(B, c)
	local best, bestD = nil, math.huge
	for _, a in ipairs(CollectionService:GetTagged("DuneLookout")) do
		if a:IsA("BasePart") and a:GetAttribute("Floor") == B.floor and a:GetAttribute("Kind") == "Camel" and Arenas.inside(Arenas.arenaFor(B.model), a) then
			local d = flat(a.Position - c).Magnitude
			if d < bestD then
				best, bestD = a.Position, d
			end
		end
	end
	if not best then
		return nil, nil
	end
	local eye = c + unitOr(flat(best - c), V3(0, 0, -1)) * 9 + V3(0, 20, 0)
	local dist = (best - eye).Magnitude
	return CFrame.lookAt(eye, best + V3(0, 3 + dist * 0.03, 0)), clamp(11 * 180 / math.max(dist, 1), 7, 28)
end

-- THE CAMERA: while the power-up plays it pulls away from you, swings
-- slowly round him as the golem builds, looks out at the animals turning
-- up, pushes in on his face for the name, and comes back to you
-- (CombatClient moves the camera: kit.shot)
local function stepShot(B, now)
	local t = breakTime(B, now)
	local root = myRoot()
	if not (B.here and t and t >= 1.0 and t < T_END and root) then
		if B.shooting then
			B.shooting = false
			B.watchCf, B.watchFov = nil, nil
			shot(nil)
		end
		return
	end
	local c = B.vpos
	if not B.shooting then
		B.shooting = true
		local cam = Workspace.CurrentCamera
		B.shotFrom = cam and cam.CFrame or CFrame.lookAt(root.Position + V3(0, 8, 14), c)
		local away = unitOr(flat(root.Position - c), V3(0, 0, 1))
		B.shotAng = math.atan2(away.X, away.Z)
	end
	local function orbit(ang, dist, height, lookY)
		local eye = c + V3(math.sin(ang) * dist, height, math.cos(ang) * dist)
		return CFrame.lookAt(eye, c + V3(0, lookY, 0))
	end
	local a0 = B.shotAng
	local cf
	if t >= T_WATCH and t < T_WATCHED then
		if not B.watchCf then
			B.watchCf, B.watchFov = watchShot(B, c)
			B.watchCf = B.watchCf or false -- (no camels: no look at them)
		end
		if B.watchCf then
			shot(B.watchCf, B.watchFov)
			return
		end
	end
	if t < 2.0 then
		cf = B.shotFrom:Lerp(orbit(a0, 58, 30, 6), smooth(t - 1.0))
	elseif t < T_TITLE then
		local u = (t - 2.0) / (T_TITLE - 2.0)
		cf = orbit(a0 + u * 0.7, 58, lerp(30, 22, u), lerp(6, 13, u))
	elseif t < T_THE then
		local u = smooth((t - T_TITLE) / (T_THE - T_TITLE))
		cf = orbit(a0 + 0.7 + u * 0.15, lerp(58, 32, u), lerp(22, 16, u), lerp(13, 21, u))
	elseif t < T_BACK then
		local u = (t - T_THE) / (T_BACK - T_THE)
		cf = orbit(a0 + 0.85, lerp(32, 27, u), 16, 21)
	else
		local u = smooth((t - T_BACK) / (T_END - T_BACK))
		local toBoss = unitOr(flat(c - root.Position), V3(0, 0, -1))
		local behind = CFrame.lookAt(root.Position - toBoss * 13 + V3(0, 6, 0), c + V3(0, 12, 0))
		cf = orbit(a0 + 0.85, 27, 16, 21):Lerp(behind, u)
	end
	shot(cf)
end

----------------------------------------------------------------------
-- THE CACTUS HE LEAVES AROUND (round 2): walls, turrets, buddies and
-- quicksand. The server keeps each one in Workspace.TuberProps with its own
-- attributes (see ServerScriptService/Bosses/Tuber.lua); each is drawn here
-- from those, and when one ends (EndKind) it plays its end and goes.
----------------------------------------------------------------------
local function ended(inst)
	return inst.Parent == nil or inst:GetAttribute("EndKind") ~= nil
end

local function endInfo(inst, now)
	local kind = inst:GetAttribute("EndKind") or "Gone"
	local at0 = num(inst:GetAttribute("EndAt"), now)
	return kind, now - at0
end

-- A CACTUS WALL: its red line, then each segment bursting up out of the
-- sand, spines on top, the weak spot glowing (cracked once it's been hit)
local function makeWall(B, inst)
	local def = B.def
	local a = def.Attacks.Wall
	local A, Bp = inst:GetAttribute("A"), inst:GetAttribute("B")
	local n = num(inst:GetAttribute("N"), 0)
	if typeof(A) ~= "Vector3" or typeof(Bp) ~= "Vector3" or n < 2 then
		return nil
	end
	local keep = tostring(inst:GetAttribute("Keep") or "")
	local weak = num(inst:GetAttribute("Weak"), 0)
	local warnAt, t0 = num(inst:GetAttribute("Warn"), 0), num(inst:GetAttribute("T0"), 0)
	local slide, slideFor = inst:GetAttribute("Slide"), num(inst:GetAttribute("SlideFor"), 0)
	if typeof(slide) ~= "Vector3" then
		slide = V3()
	end
	local along = unitOr(flat(Bp - A), V3(1, 0, 0))
	local across = V3(-along.Z, 0, along.X)
	local segs = {}
	for i = 1, n do
		if string.sub(keep, i, i) ~= "0" then
			local seg = {
				c = A:Lerp(Bp, (i - 1) / (n - 1)),
				core = newPart("WallCactus", nil, def.Color, nil, 1, B.body.folder),
				tops = { newPart("WallSpine", nil, def.SpineColor or SAND_LIGHT, nil, 1, B.body.folder),
					newPart("WallSpine", nil, def.SpineColor or SAND_LIGHT, nil, 1, B.body.folder) },
				weak = (i == weak) and newPart("WallWeakSpot", nil, YELLOW, Enum.Material.Neon, 1, B.body.folder) or nil,
				i = i,
			}
			table.insert(segs, seg)
		end
	end
	local line = newPart("WallWarning", nil, def.RageColor or HOT, Enum.Material.Neon, 1, B.body.folder)
	local rec = { inst = inst, kind = "Wall", segs = segs, line = line }
	local rose, endedFx = false, false
	function rec.update(now)
		local off = slide * clamp(now - t0, 0, slideFor)
		local gone, age = false, 0
		if ended(inst) then
			local kind
			kind, age = endInfo(inst, now)
			if not endedFx then
				endedFx = true
				if kind == "Broken" then
					sfx(B, "Pop", 0.9, (A + Bp) / 2)
					for _, s in ipairs(segs) do
						burst(s.c + off + V3(0, a.Height / 2, 0), def.Color, 8, 14, 1.2, 0.6, true)
					end
				elseif kind == "Wither" then
					burst((A + Bp) / 2 + off + V3(0, 1, 0), SAND, 14, 8, 2, 0.8)
				end
			end
			if kind == "Gone" or age > 0.7 then
				gone = true
			end
		end
		if gone then
			return false
		end
		-- (the red line, until it bursts up)
		if now >= warnAt and now < t0 then
			local k = (now - warnAt) / math.max(t0 - warnAt, 0.05)
			stretch(line, A + V3(0, 0.12, 0), Bp + V3(0, 0.12, 0), 1.2 + k * 1.6, 0.12)
			line.Transparency = (math.floor(now * 10) % 2 == 0) and 0.15 or 0.45
		else
			line.Transparency = 1
		end
		if now < t0 then
			return true
		end
		if not rose then
			rose = true
			if B.here then
				sfx(B, "Wall", 0.9, (A + Bp) / 2)
				burst((A + Bp) / 2 + V3(0, 1, 0), SAND, 20, 18, 2.4, 0.7, true)
				kick((A + Bp) / 2, 20, 0.5, -2)
			end
		end
		local up = easeOutBack(clamp((now - t0) / 0.25, 0, 1))
		local sink = 1
		if ended(inst) then
			local kind
			kind, age = endInfo(inst, now)
			sink = (kind == "Broken") and clamp(1 - age / 0.35, 0, 1) or clamp(1 - age / 0.7, 0, 1)
		end
		local h = a.Height * up * sink
		local hp = num(inst:GetAttribute("Health"), 1)
		local hpMax = math.max(num(inst:GetAttribute("MaxHealth"), 1), 1)
		for _, s in ipairs(segs) do
			local c = s.c + off
			local cf = CFrame.lookAt(c + V3(0, h / 2, 0), c + V3(0, h / 2, 0) + across)
			s.core.CFrame = cf
			s.core.Size = V3(a.Segment - 0.25, math.max(h, 0.05), a.Thick)
			s.core.Transparency = 0
			for j, top in ipairs(s.tops) do
				local x = (j == 1) and -0.9 or 0.9
				top.CFrame = cf * CFrame.new(x, h / 2 + 0.45, (j == 1) and -0.4 or 0.4)
				top.Size = V3(0.3, 0.9, 0.3)
				top.Transparency = (h > 1) and 0 or 1
			end
			if s.weak then
				-- the weak spot: glowing, pulsing - red and shaking once cracked
				local cracked = hp < hpMax - 0.5
				local pulse = 0.5 + 0.5 * math.sin(now * 8)
				s.weak.Color = cracked and HOT or YELLOW:Lerp(def.Color, pulse * 0.6)
				local jig = cracked and V3(math.sin(now * 50), 0, 0) * 0.08 or V3()
				s.weak.CFrame = cf + jig
				s.weak.Size = V3(1.8, math.max(h * 0.6, 0.05), a.Thick + 0.35)
				s.weak.Transparency = (h > 1) and 0 or 1
			end
		end
		return true
	end
	function rec.cleanup()
		for _, s in ipairs(segs) do
			s.core:Destroy()
			for _, top in ipairs(s.tops) do
				top:Destroy()
			end
			if s.weak then
				s.weak:Destroy()
			end
		end
		line:Destroy()
	end
	return rec
end

-- a needle from `from` to `to`, launched at `fireAt` at `speed` (a turret's
-- shot, or one of a volley's), with its thin red line from `warnAt`
local function needle(B, from, to, warnAt, fireAt, speed, color)
	local def = B.def
	local line = warnAt and newPart("NeedleLine", nil, color or def.RageColor or HOT, Enum.Material.Neon, 1, B.body.folder) or nil
	local spike = newPart("Needle", nil, def.SpineColor or SAND_LIGHT, nil, 1, B.body.folder)
	local len = flat(to - from).Magnitude
	local dir = unitOr(flat(to - from), V3(0, 0, -1))
	local y = V3(0, 2.2, 0)
	addTelegraph(B, {
		update = function(now)
			if line then
				if now >= warnAt and now < fireAt then
					stretch(line, from + V3(0, 0.15, 0), to + V3(0, 0.15, 0), 0.3, 0.1)
					line.Transparency = (now > fireAt - 0.2) and 0.05 or 0.45
				else
					line.Transparency = 1
				end
			end
			local gone = (now - fireAt) * speed
			if gone < 0 then
				spike.Transparency = 1
				return true
			end
			if gone >= len then
				return false
			end
			local p = from + dir * gone + y
			spike.CFrame = CFrame.lookAt(p, p + dir)
			spike.Size = V3(0.35, 0.35, 2.2)
			spike.Transparency = 0
			return true
		end,
		cleanup = function()
			if line then
				line:Destroy()
			end
			spike:Destroy()
		end,
	})
end

-- A NEEDLE TURRET: a little cactus tower with an angry red eye, sprouting
-- out of the sand; each shot's thin red line, then the needle
local function makeTurret(B, inst)
	local def = B.def
	local a = def.Attacks.Turrets
	local hit = inst.PrimaryPart
	if not hit then
		return nil
	end
	local spot = atFloor(B, hit.Position)
	local born, grow = num(inst:GetAttribute("Born"), 0), num(inst:GetAttribute("Grow"), 0.9)
	local f = B.body.folder
	local parts = {
		base = newPart("TurretBase", nil, def.DeepColor, nil, 1, f),
		body = newPart("TurretBody", nil, def.Color, nil, 1, f),
		head = newPart("TurretHead", nil, def.Color, nil, 1, f),
		eye = newPart("TurretEye", nil, def.RageColor or HOT, Enum.Material.Neon, 1, f),
		barrels = {},
	}
	for i = 1, 4 do
		parts.barrels[i] = newPart("TurretSpine", nil, def.SpineColor or SAND_LIGHT, nil, 1, f)
	end
	local rec = { inst = inst, kind = "Turret" }
	local seenShot = 0
	local aim = unitOr(flat((myRoot() and myRoot().Position or spot + V3(0, 0, -1)) - spot), V3(0, 0, -1))
	local recoilAt = -math.huge
	local sprouted, endedFx = false, false
	function rec.update(now)
		if ended(inst) then
			local kind, age = endInfo(inst, now)
			if not endedFx then
				endedFx = true
				if kind == "Broken" then
					sfx(B, "Pop", 0.8, spot)
					burst(spot + V3(0, 3, 0), def.Color, 16, 16, 1.2, 0.6, true)
				end
			end
			if kind == "Gone" or age > 0.5 then
				return false
			end
		end
		if now >= born and not sprouted then
			sprouted = true
			if B.here then
				burst(spot + V3(0, 0.5, 0), SAND, 12, 10, 1.6, 0.6, true)
			end
		end
		-- each new shot: aim, the red line, the needle
		local id = num(inst:GetAttribute("ShotId"), 0)
		if id ~= seenShot then
			seenShot = id
			local from, to = inst:GetAttribute("ShotFrom"), inst:GetAttribute("ShotTo")
			local warnAt, fireAt = num(inst:GetAttribute("ShotWarn"), now), num(inst:GetAttribute("ShotAt"), now)
			if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
				aim = unitOr(flat(to - from), aim)
				recoilAt = fireAt
				if B.here then
					needle(B, from, to, warnAt, fireAt, a.Speed)
					at(B, fireAt, function()
						sfx(B, "Needle", 0.5, spot)
					end)
				end
			end
		end
		local k = easeOutBack(clamp((now - born) / grow, 0, 1))
		if ended(inst) then
			local _, age = endInfo(inst, now)
			k = k * clamp(1 - age / 0.5, 0, 1)
		end
		local recoil = (now >= recoilAt and now < recoilAt + 0.25) and (1 - (now - recoilAt) / 0.25) or 0
		local cf = CFrame.lookAt(spot, spot + aim) * CFrame.new(0, 0, recoil * 0.5)
		local function put(p, size, pos)
			p.Size = size * math.max(k, 0.02)
			p.CFrame = cf * CFrame.new(pos * k)
			p.Transparency = (k > 0.02) and 0 or 1
		end
		put(parts.base, V3(2.8, 1.0, 2.8), V3(0, 0.5, 0))
		put(parts.body, V3(2.0, 3.6, 2.0), V3(0, 2.8, 0))
		put(parts.head, V3(2.6, 1.4, 2.6), V3(0, 5.2, 0))
		put(parts.eye, V3(1.1, 0.6, 0.2), V3(0, 5.3, -1.35))
		for i, b in ipairs(parts.barrels) do
			local ang = (i - 1) * math.pi / 2
			local out = V3(math.sin(ang), 0, -math.cos(ang))
			b.Size = V3(0.35, 0.35, 1.2) * math.max(k, 0.02)
			local pos = (cf * CFrame.new(out * 1.5 * k + V3(0, 5.2 * k, 0))).Position
			b.CFrame = CFrame.lookAt(pos, pos + cf:VectorToWorldSpace(out))
			b.Transparency = (k > 0.02) and 0 or 1
		end
		return true
	end
	function rec.cleanup()
		for _, p in pairs(parts) do
			if typeof(p) == "Instance" then
				p:Destroy()
			end
		end
		for _, b in ipairs(parts.barrels) do
			b:Destroy()
		end
	end
	return rec
end

-- A PRICKLY BUDDY: a mini Tuber hopping off the Brute, then waddling after
-- you; it puffs up red before it pops
local function makeBuddy(B, inst)
	local def = B.def
	local a = def.Attacks.Buddies
	local from, to = inst:GetAttribute("From"), inst:GetAttribute("To")
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return nil
	end
	local born, land = num(inst:GetAttribute("Born"), 0), num(inst:GetAttribute("Land"), 0)
	local f = B.body.folder
	local parts = {
		body = newPart("BuddyBody", nil, def.Color, nil, 1, f),
		lump = newPart("BuddyLump", nil, def.DeepColor, nil, 1, f),
		eyes = { newPart("BuddyEye", nil, INK, nil, 1, f), newPart("BuddyEye", nil, INK, nil, 1, f) },
		feet = { newPart("BuddyFoot", nil, def.DeepColor, nil, 1, f), newPart("BuddyFoot", nil, def.DeepColor, nil, 1, f) },
		flower = newPart("BuddyFlower", nil, def.FlowerColor or PINK, nil, 1, f),
	}
	local ring = nil
	local rec = { inst = inst, kind = "Buddy" }
	local pos, facing = from, unitOr(flat(to - from), V3(0, 0, -1))
	local endedFx = false
	function rec.update(now, dt)
		local puffAt = inst:GetAttribute("PuffAt")
		if ended(inst) then
			local kind, age = endInfo(inst, now)
			if not endedFx then
				endedFx = true
				if kind == "Pop" then
					sfx(B, "Pop", 0.8, pos)
					burst(pos + V3(0, 1.5, 0), def.SpineColor or SAND_LIGHT, 22, 22, 0.9, 0.5)
					burst(pos + V3(0, 1.5, 0), def.Color, 12, 14, 1.4, 0.5)
					if B.here then
						local shock = newRing(20, def.RageColor or HOT, Enum.Material.Neon, 0.2)
						local popAt = now
						addTelegraph(B, {
							update = function(n2)
								local u = (n2 - popAt) / 0.3
								if u >= 1 then
									return false
								end
								placeRing(shock, pos + V3(0, 0.1, 0), lerp(1, a.Radius, easeOut(u)), 1.2 * (1 - u) + 0.1, 0.6, u)
								return true
							end,
							cleanup = function()
								removeRing(shock)
							end,
						})
					end
				elseif kind == "Broken" then
					sfx(B, "Pop", 0.6, pos)
					burst(pos + V3(0, 1.5, 0), def.Color, 14, 12, 1.2, 0.5, true)
				end
			end
			if kind ~= "Wither" or age > 0.5 then
				return false
			end
		end
		local lift = 0
		if now < land then
			local span = math.max(land - born, 0.05)
			pos = from:Lerp(to, clamp((now - born) / span, 0, 1))
			lift = arcHeight(now - born, span, 0.5, 5)
		else
			local hit = inst.PrimaryPart
			if hit then
				local want = atFloor(B, hit.Position)
				pos = pos:Lerp(want, 1 - math.exp(-(dt or 1 / 60) * 15))
				local lv = flat(hit.CFrame.LookVector)
				if lv.Magnitude > 0.1 then
					facing = lv.Unit
				end
			end
		end
		local puff = (type(puffAt) == "number") and clamp((now - puffAt) / a.Puff, 0, 1) or 0
		local k = 1 + puff * 0.6
		local sink = 0
		if ended(inst) then
			local _, age = endInfo(inst, now)
			sink = clamp(age / 0.5, 0, 1) * 2.6
		end
		local bob = (now >= land and puff == 0) and math.abs(math.sin(now * 10)) * 0.3 or 0
		local cf = CFrame.lookAt(pos, pos + facing) * CFrame.new(0, lift + bob - sink, 0)
		local color = def.Color:Lerp(RED, puff)
		parts.body.Size = V3(2.2, 2.4, 2.0) * k
		parts.body.CFrame = cf * CFrame.new(0, 1.4 * k, 0)
		parts.body.Color = color
		parts.lump.Size = V3(1.4, 1.6, 1.4) * k
		parts.lump.CFrame = cf * CFrame.new(0.55 * k, 1.2 * k, -0.2)
		for i, e in ipairs(parts.eyes) do
			e.Size = V3(0.35, 0.5, 0.1) * k
			e.CFrame = cf * CFrame.new(((i == 1) and -0.45 or 0.45) * k, 1.7 * k, -1.02 * k)
		end
		for i, ft in ipairs(parts.feet) do
			local step = (now >= land) and math.sin(now * 10 + i * math.pi) * 0.3 or 0
			ft.Size = V3(0.7, 0.4, 0.9)
			ft.CFrame = cf * CFrame.new((i == 1) and -0.55 or 0.55, 0.2, step)
		end
		parts.flower.Size = V3(0.8, 0.4, 0.8) * k
		parts.flower.CFrame = cf * CFrame.new(0, 2.8 * k, 0)
		for _, p in pairs(parts) do
			if typeof(p) == "Instance" then
				p.Transparency = 0
			end
		end
		for _, list in ipairs({ parts.eyes, parts.feet }) do
			for _, p in ipairs(list) do
				p.Transparency = 0
			end
		end
		-- (puffing up: a red ring shows how far its needles reach)
		if puff > 0 and B.here then
			ring = ring or newRing(20, def.RageColor or HOT, Enum.Material.Neon, 0.4)
			placeRing(ring, pos + V3(0, 0.1, 0), a.Radius, 0.2, 0.5, (math.floor(now * 12) % 2 == 0) and 0.2 or 0.5)
		end
		return true
	end
	function rec.cleanup()
		for _, p in pairs(parts) do
			if typeof(p) == "Instance" then
				p:Destroy()
			end
		end
		for _, list in ipairs({ parts.eyes, parts.feet }) do
			for _, p in ipairs(list) do
				p:Destroy()
			end
		end
		if ring then
			removeRing(ring)
		end
	end
	return rec
end

-- QUICKSAND: a swirl of dark sand (a red ring while it opens up) that drags
-- you toward its middle - only with your feet on the ground, and never as
-- fast as you run: running out always works, it just takes longer, and a
-- roll slips free
local function dragMe(B, center, radius, pull, dt)
	local hrp = myRoot()
	if not hrp or Players.LocalPlayer:GetAttribute("SpireFloor") ~= B.floor or not Arenas.isMine(Players.LocalPlayer, B.model) then
		return
	end
	local off = flat(center - hrp.Position)
	local d = off.Magnitude
	if d > radius or d < 0.6 then
		return
	end
	local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
	if hum and hum.FloorMaterial == Enum.Material.Air then
		return
	end
	local speed = lerp(pull[1], pull[2], 1 - d / radius)
	hrp.CFrame = hrp.CFrame + off.Unit * math.min(speed * dt, d)
end

local function makeSand(B, inst)
	local def = B.def
	local a = def.Attacks.Quicksand
	local c = inst:GetAttribute("C")
	if typeof(c) ~= "Vector3" then
		return nil
	end
	local r = num(inst:GetAttribute("R"), a.Radius)
	local warnAt, t0, t1 = num(inst:GetAttribute("Warn"), 0), num(inst:GetAttribute("T0"), 0), num(inst:GetAttribute("T1"), 0)
	local disc = newPart("Quicksand", Enum.PartType.Cylinder, SAND_DARK, Enum.Material.SmoothPlastic, 1, B.body.folder)
	local edge = newRing(24, def.RageColor or HOT, Enum.Material.Neon, 1)
	local swirls = { newRing(16, BROWN, Enum.Material.SmoothPlastic, 1), newRing(12, TAN, Enum.Material.SmoothPlastic, 1) }
	local rec = { inst = inst, kind = "Sand" }
	-- (a ring whose pieces turn round its middle: the swirl)
	local function spin(ring, radius, angle, tr)
		local n = ring.n
		for i, p in ipairs(ring.parts) do
			local ang = (i - 0.5) / n * math.pi * 2 + angle
			local out = V3(math.sin(ang), 0, math.cos(ang))
			local pos = c + out * radius + V3(0, 0.14, 0)
			p.Size = V3(2 * radius * math.sin(math.pi / n) * 0.7, 0.08, 0.5)
			p.CFrame = CFrame.lookAt(pos, pos + out)
			p.Transparency = tr
		end
	end
	function rec.update(now, dt)
		local fade = 0
		if ended(inst) then
			local kind, age = endInfo(inst, now)
			if kind == "Gone" or age > 0.5 then
				return false
			end
			fade = clamp(age / 0.5, 0, 1)
		end
		if now < t0 then
			local k = clamp((now - warnAt) / math.max(t0 - warnAt, 0.05), 0, 1)
			placeRing(edge, c + V3(0, 0.1, 0), r, 0.2, 0.6, (math.floor(now * 10) % 2 == 0) and 0.2 or 0.55)
			placeDisc(disc, c + V3(0, 0.1, 0), r * 2 * k, 0.08)
			disc.Transparency = lerp(1, 0.4, k)
			spin(swirls[1], r * 0.62, 0, 1)
			spin(swirls[2], r * 0.3, 0, 1)
			return true
		end
		placeRing(edge, c, r, 0.05, 0.1, 1)
		placeDisc(disc, c + V3(0, 0.1, 0), r * 2, 0.08)
		disc.Transparency = lerp(0.2, 1, fade)
		spin(swirls[1], r * 0.62, now * 1.6, lerp(0.1, 1, fade))
		spin(swirls[2], r * 0.3, -now * 2.4, lerp(0.1, 1, fade))
		if not ended(inst) and now < t1 and B.here then
			dragMe(B, c, r, a.Pull, dt or 1 / 60)
		end
		return true
	end
	function rec.cleanup()
		disc:Destroy()
		removeRing(edge)
		for _, s in ipairs(swirls) do
			removeRing(s)
		end
	end
	return rec
end

local PROP_MAKERS = { Wall = makeWall, Turret = makeTurret, Buddy = makeBuddy, Sand = makeSand }

local function stepProps(B, now, dt)
	B.props = B.props or {}
	B.propOf = B.propOf or {}
	local folder = Arenas.folderFor(B.model, "TuberProps") -- (his own arena copy's)
	if folder then
		local fresh = {}
		for _, inst in ipairs(folder:GetChildren()) do
			if B.propOf[inst] == nil and inst:GetAttribute("Floor") == B.floor then
				table.insert(fresh, inst)
			end
		end
		table.sort(fresh, function(x, y)
			return num(x:GetAttribute("Id"), 0) < num(y:GetAttribute("Id"), 0)
		end)
		for _, inst in ipairs(fresh) do
			local maker = PROP_MAKERS[inst:GetAttribute("Kind")]
			local rec = maker and maker(B, inst) or nil
			B.propOf[inst] = rec or false
			if rec then
				table.insert(B.props, rec)
			end
		end
	end
	for i = #B.props, 1, -1 do
		local rec = B.props[i]
		local ok, keep = pcall(rec.update, now, dt)
		if not ok and not B.warnedProp then
			B.warnedProp = true
			warn("[BossClient] Tuber's " .. tostring(rec.kind) .. " failed: " .. tostring(keep))
		end
		if not ok or not keep then
			pcall(rec.cleanup)
			table.remove(B.props, i)
		end
	end
	-- (forget the ones the server has taken away)
	for inst, rec in pairs(B.propOf) do
		if inst.Parent == nil and (rec == false or not table.find(B.props, rec)) then
			B.propOf[inst] = nil
		end
	end
end

local function clearProps(B)
	for _, rec in ipairs(B.props or {}) do
		pcall(rec.cleanup)
	end
	B.props = {}
end

----------------------------------------------------------------------
-- Warnings on the floor
----------------------------------------------------------------------
-- his current facing, for a warning still following you (until it locks)
local function facingNow(B)
	return unitOr(flat(B.faceDir or B.vfacing or V3(0, 0, -1)), V3(0, 0, -1))
end

-- A WEDGE in front of him (spokes and an edge): it turns with him until
-- `lock()` gives it a direction to stay on, then glows brighter until it lands
local function wedge(B, reach, arcDeg, tHit, color)
	local spokes, edge = {}, {}
	for i = 1, 5 do
		spokes[i] = newPart("WedgeSpoke", nil, color, Enum.Material.Neon, 1)
	end
	for i = 1, 6 do
		edge[i] = newPart("WedgeEdge", nil, color, Enum.Material.Neon, 1)
	end
	local w = { dir = nil }
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			if now > tHit + 0.15 then
				return false
			end
			local dir = w.dir or facingNow(B)
			local origin = atFloor(B, B.vpos) + V3(0, 0.12, 0)
			local k = clamp((now - t0) / math.max(tHit - t0, 0.05), 0, 1)
			local tr = w.dir and ((math.floor(now * 12) % 2 == 0) and 0.1 or 0.35) or lerp(0.7, 0.4, k)
			for i, sp in ipairs(spokes) do
				local ang = math.rad(-arcDeg / 2 + (i - 1) * arcDeg / 4)
				local c, s = math.cos(ang), math.sin(ang)
				local d = V3(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c)
				stretch(sp, origin + d * 1.5, origin + d * reach, 0.35, 0.1)
				sp.Transparency = tr
			end
			for i, e in ipairs(edge) do
				local a1 = math.rad(-arcDeg / 2 + (i - 1) * arcDeg / 6)
				local a2 = math.rad(-arcDeg / 2 + i * arcDeg / 6)
				local function dirAt(ang)
					local c, s = math.cos(ang), math.sin(ang)
					return V3(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c)
				end
				stretch(e, origin + dirAt(a1) * reach, origin + dirAt(a2) * reach, 0.45, 0.1)
				e.Transparency = tr
			end
			return true
		end,
		cleanup = function()
			for _, p in ipairs(spokes) do
				p:Destroy()
			end
			for _, p in ipairs(edge) do
				p:Destroy()
			end
		end,
	})
	return w
end

-- A LANE: a strip on the floor from `a` to `b` (while `a` and `b` are nil it
-- runs `length` studs out along his facing). Shown until `tEnd`.
local function lane(B, width, length, tHit, tEnd, color, a, b)
	local strip = newPart("Lane", nil, color, Enum.Material.Neon, 1)
	local l = { a = a, b = b }
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			if now > tEnd then
				return false
			end
			local from, to = l.a, l.b
			if not (from and to) then
				local dir = facingNow(B)
				from = atFloor(B, B.vpos)
				to = from + dir * length
			end
			stretch(strip, from + V3(0, 0.1, 0), to + V3(0, 0.1, 0), width, 0.1)
			local k = clamp((now - t0) / math.max(tHit - t0, 0.05), 0, 1)
			if now >= tHit then
				strip.Transparency = lerp(0.3, 1, clamp((now - tHit) / math.max(tEnd - tHit, 0.05), 0, 1))
			elseif l.a then
				strip.Transparency = (math.floor(now * 12) % 2 == 0) and 0.15 or 0.4
			else
				strip.Transparency = lerp(0.75, 0.45, k)
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
		end,
	})
	return l
end

-- a path of lanes (a rolling ball's: start, bounce, bounce, stop)
local function pathLanes(B, pts, width, tShow, tEnd, color)
	for i = 2, #pts do
		if flat(pts[i] - pts[i - 1]).Magnitude > 0.2 then
			lane(B, width, 0, tShow + 0.6, tEnd, color, pts[i - 1], pts[i])
		end
	end
end

-- A CIRCLE on the floor: a disc filling in until `tHit`, and its edge
local function circle(B, c, radius, tHit, color, tShow)
	local disc = newPart("Circle", Enum.PartType.Cylinder, color, Enum.Material.Neon, 1)
	local ring = newRing(24, color, Enum.Material.Neon, 1)
	local t0 = tShow or serverNow()
	addTelegraph(B, {
		update = function(now)
			if now > tHit + 0.1 then
				return false
			end
			if now < t0 then
				return true
			end
			local k = clamp((now - t0) / math.max(tHit - t0, 0.05), 0, 1)
			placeDisc(disc, c + V3(0, 0.09, 0), radius * 2 * k, 0.06)
			disc.Transparency = 0.55
			placeRing(ring, c + V3(0, 0.08, 0), radius, 0.18, 0.5, (k > 0.8 and math.floor(now * 14) % 2 == 0) and 0.05 or 0.3)
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- A RING OF NEEDLES spreading out along the ground from `origin` (the
-- server's own ring: from `fromR` to `toR` at `speed`, `height` tall - jump
-- it or roll through it)
local function needleRing(B, origin, fromR, toR, speed, height, color, t0)
	t0 = t0 or serverNow()
	local ring = newRing(28, color or B.def.SpineColor or SAND_LIGHT, Enum.Material.SmoothPlastic, 1)
	local life = (toR - fromR) / math.max(speed, 1)
	addTelegraph(B, {
		update = function(now)
			local u = (now - t0) / life
			if u >= 1 then
				return false
			end
			if u < 0 then
				return true
			end
			placeRing(ring, atFloor(B, origin), lerp(fromR, toR, u), height * lerp(1, 0.6, u), 0.5, u * 0.7)
			return true
		end,
		cleanup = function()
			removeRing(ring)
		end,
	})
end

-- a spiky cactus ball rolling along `pts` from `launch` at `speed`
local function rollingBall(B, pts, launch, speed, size)
	local def = B.def
	local ball = newPart("CactusBall", nil, def.Color, nil, 1)
	local spikes = {}
	for i = 1, 4 do
		spikes[i] = newPart("BallSpike", nil, def.SpineColor or SAND_LIGHT, nil, 1)
	end
	local len = pathLength(pts)
	local lastDust = 0
	addTelegraph(B, {
		update = function(now)
			local gone = (now - launch) * speed
			if gone > len + 0.1 then
				burst(pts[#pts] + V3(0, 1, 0), def.Color, 8, 10, 1.2, 0.5)
				return false
			end
			if gone < 0 then
				return true
			end
			local p = pointAlong(pts, gone)
			local dir = headingAlong(pts, gone, V3(0, 0, -1))
			local cf = CFrame.lookAt(p + V3(0, size / 2, 0), p + V3(0, size / 2, 0) + dir) * CFrame.Angles(-gone / (size / 2), 0, 0)
			ball.CFrame = cf
			ball.Size = V3(size, size, size)
			ball.Transparency = 0
			for i, s in ipairs(spikes) do
				local out = ({ V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0) })[i]
				local pos = (cf * CFrame.new(out * (size / 2 + 0.4))).Position
				s.CFrame = CFrame.lookAt(pos, pos + cf:VectorToWorldSpace(out))
				s.Size = V3(0.35, 0.35, 1.0)
				s.Transparency = 0
			end
			if B.here and now - lastDust > 0.12 then
				lastDust = now
				burst(p + V3(0, 0.3, 0), SAND, 3, 5, 1.4, 0.4)
			end
			return true
		end,
		cleanup = function()
			ball:Destroy()
			for _, s in ipairs(spikes) do
				s:Destroy()
			end
		end,
	})
end

-- a cactus ball falling out of the sky onto `spot` at `landAt`
local function fallingBall(B, spot, landAt, radius)
	local def = B.def
	local ball = newPart("RainBall", nil, def.Color, nil, 1)
	addTelegraph(B, {
		update = function(now)
			local e = landAt - now
			if e < 0 then
				burst(spot + V3(0, 1, 0), def.Color, 10, 12, 1.4, 0.5, true)
				burst(spot + V3(0, 0.5, 0), SAND, 10, 10, 1.8, 0.6)
				sfx(B, "Crash", 0.35, spot)
				needleRing(B, spot, 1, radius, 26, 1.2, SAND_LIGHT)
				return false
			end
			if e > 0.9 then
				ball.Transparency = 1
				return true
			end
			local h = (e / 0.9) ^ 1.6 * 60
			ball.CFrame = CFrame.new(spot + V3(0, 1.6 + h, 0)) * CFrame.Angles(now * 5, now * 3, 0)
			ball.Size = V3(3.2, 3.2, 3.2)
			ball.Transparency = 0
			return true
		end,
		cleanup = function()
			ball:Destroy()
		end,
	})
end

----------------------------------------------------------------------
-- Poses: his shape through each move (t = seconds since it started)
----------------------------------------------------------------------
-- LITTLE TUBER --------------------------------------------------------
function Poses.Idle(B, t, P)
	if B.formShown == "Brute" then
		P.sway = math.sin(serverNow() * 1.3) * 0.03
		P.armLPitch = math.sin(serverNow() * 1.1) * 0.08
		P.armRPitch = -math.sin(serverNow() * 1.1) * 0.08
		return
	end
	-- (a blink now and then)
	if (serverNow() % 3.4) < 0.12 then
		P.eyes = "shut"
	end
	local _ = t
end

-- ASLEEP in his garden: sunk in the sand up to his head, eyes shut, snoozing
function Poses.Dormant(B, t, P)
	local now = serverNow()
	P.sink = 6.6
	P.eyes, P.mouth, P.blush = "shut", "sniff", true
	P.sy = 1 + 0.04 * math.sin(now * 1.6)
	P.wilt = 0.15
	local _ = B
	local _ = t
end

-- WAKING UP: pops up out of the sand, yawns and stretches, and waves hello
function Poses.Wake(B, t, P)
	if t < 0.6 then
		P.sink = 6.6 * (1 - easeOutBack(t / 0.6))
		P.eyes, P.mouth = "wide", "o"
	elseif t < 1.6 then
		local u = (t - 0.6) / 1.0
		P.sy = 1 + 0.16 * math.sin(u * math.pi)
		P.eyes, P.mouth = "shut", "open"
		P.armL, P.armR = math.sin(u * math.pi), math.sin(u * math.pi)
	else
		P.eyes, P.mouth = "happy", "grin"
		P.armR = 0.7 + 0.3 * math.sin((t - 1.6) * 14)
	end
	local _ = B
end

-- EVERYONE'S GONE: a wave bye-bye and he sinks back into his garden (the
-- Brute sinks into the sand, rumbling)
function Poses.Reset(B, t, P)
	if B.formShown == "Brute" then
		P.sink = clamp(t / 1.8, 0, 1) ^ 2 * 30
		P.shake = 0.2
		P.glow = 0.4
		return
	end
	P.eyes, P.mouth = "happy", "smile"
	P.armR = 0.7 + 0.3 * math.sin(t * 14)
	P.sink = clamp((t - 1.0) / 0.8, 0, 1) * 6.6
end

-- WOBBLE BONK: leans back... and flops his head forward
function Poses.Bonk(B, t, P)
	local a = B.def.Attacks.Bonk
	if t < a.Tell then
		P.lean = -0.3 * smooth(t / a.Tell)
		P.shake = (t > a.Tell - 0.3) and 0.06 or 0
		P.eyes, P.mouth = "shut", "grin"
	elseif t < a.Tell + 0.5 then
		P.lean = 1.1 * clamp((t - a.Tell) / 0.12, 0, 1)
		P.eyes, P.mouth = "wide", "o"
	else
		local e = t - a.Tell - 0.5
		P.lean = 1.1 * (1 - smooth(e / math.max(a.Recovery - 0.5, 0.1))) + 0.08 * spring(e, 4, 12)
		P.eyes = "dizzy"
		P.dizzy = (e < 0.7) and 1 or 0
	end
end

-- CLUMSY TOPPLE: "whoa... whoa..." - timber! - flailing on the ground, and up again
function Poses.Topple(B, t, P)
	local a = B.def.Attacks.Topple
	local hit = a.Tell + a.Fall
	if t < a.Tell then
		P.lean = -0.22 * math.sin(t * 7)
		P.armL, P.armR = 0.5 + 0.5 * math.sin(t * 12), 0.5 + 0.5 * math.sin(t * 12 + 2)
		P.eyes, P.mouth = "wide", "o"
	elseif t < hit then
		local u = (t - a.Tell) / a.Fall
		P.topple = u * u
		P.eyes, P.mouth = "wide", "open"
	elseif t < hit + a.Down then
		P.topple = 1
		P.armL, P.armR = 0.5 + 0.5 * math.sin(t * 16), 0.5 + 0.5 * math.sin(t * 16 + 1.5)
		P.eyes, P.mouth = "dizzy", "o"
		P.dizzy = 1
	else
		P.topple = 1 - smooth((t - hit - a.Down) / a.Rise)
		P.eyes, P.mouth = "shut", "sad"
	end
end

-- NEEDLE SNEEZE: "ah... ah..." (head back, twice) - ACHOO!
function Poses.Sneeze(B, t, P)
	local a = B.def.Attacks.Sneeze
	if t < a.Tell then
		P.lean = -0.22 * math.abs(math.sin(t * math.pi / 0.65))
		P.eyes, P.mouth = "shut", "o"
		P.sy = 1 + 0.06 * math.abs(math.sin(t * math.pi / 0.65))
	elseif t < a.Tell + 0.35 then
		local u = (t - a.Tell) / 0.35
		P.lean = 0.35 * math.sin(u * math.pi)
		P.eyes, P.mouth = "shut", "open"
		P.sy, P.sx = 0.85, 1.12
	else
		P.eyes, P.mouth = "open", "sniff"
	end
end

-- BOUNCE STOMP: squash, spring up, land on the circle, wobble
function Poses.Stomp(B, t, P)
	local a = B.def.Attacks.Stomp
	if t < a.Crouch then
		local u = t / a.Crouch
		P.sy, P.sx = 1 - 0.3 * u, 1 + 0.15 * u
		P.eyes, P.mouth = "shut", "grin"
	elseif t < a.Crouch + a.Air then
		P.lift = arcHeight(t - a.Crouch, a.Air, 0.5, a.Height)
		P.sy, P.sx = 1.15, 0.92
		P.eyes, P.mouth = "happy", "open"
		P.armL, P.armR = 1, 1
	else
		local w = spring(t - a.Crouch - a.Air, 5, 14)
		P.sy, P.sx = 1 - 0.3 * w, 1 + 0.18 * w
		P.eyes, P.mouth = "happy", "grin"
	end
end

-- SPLIT! (while he's in pieces, placeSplit draws each buddy)
function Poses.Split(B, t, P)
	local a = B.def.Attacks.Split
	if t < a.Shake then
		P.shake = 0.12 + 0.2 * (t / a.Shake)
		P.eyes, P.mouth = "wide", "grin"
	else
		P.eyes, P.mouth = "happy", "grin"
	end
end

-- THE POWER-UP (see T_* above): he flops over, his flower wilts... the golem
-- builds round him... it stands, crowned... and ROARS
function Poses.Break(B, t, P)
	if B.formShown == "Stack" then
		-- (if his buddies had to hop back together first, he flops once they have)
		local f = math.max(t - (B.rejoin and REJOIN or 0), 0)
		P.side = smooth(f / T_FLOP)
		P.eyes = (f < 0.35) and "wide" or "shut"
		P.mouth = "sad"
		P.wilt = smooth((f - 0.2) / 0.8)
		P.shake = (t > T_RUMBLE) and 0.18 or 0
		return
	end
	-- (the golem)
	P.side = 1
	P.wilt = 1
	P.eyes, P.mouth = "shut", "sad"
	local b = t
	P.crouch = (b < 3.15) and 0.5 or 0.5 * (1 - smooth((b - 3.15) / 0.5))
	P.glow = (b < 4.5) and 0 or ((b < 4.7) and 1.5 or 1)
	P.shake = (b < 3.15) and 0.08 or 0
	if b >= 3.15 and b < 3.8 then
		local w = spring(b - 3.15, 5, 12)
		P.armLRoll, P.armRRoll = 0.12 + 0.9 * w, 0.12 + 0.9 * w
	end
	if b >= T_ROAR and b < T_ROAR + 1.3 then
		local u = clamp((b - T_ROAR) / 0.25, 0, 1) * (1 - clamp((b - T_ROAR - 1.0) / 0.3, 0, 1))
		P.roar = u
		P.armLPitch, P.armRPitch = 2.6 * u, 2.6 * u
		P.armLRoll, P.armRRoll = 0.12 + 0.5 * u, 0.12 + 0.5 * u
		P.headPitch = -0.35 * u
		P.shake = 0.25 * u
		P.glow = 1 + 0.5 * u
	end
end

-- THE END: the Brute freezes, cracking... (then placeCrumble)
function Poses.Death(B, t, P)
	P.shake = (t < 0.8) and 0.3 or 0
	P.glow = (math.floor(t * 14) % 2 == 0) and 1.5 or 0.3
	P.roar = (t < 0.8) and 0.6 or 0
	P.armLPitch, P.armRPitch = 0.4, 0.4
	P.eyes, P.mouth = "dizzy", "o"
	local _ = B
end

-- THE BRUTE -----------------------------------------------------------
-- ROOT HOP: rips his roots up, leaps across the arena, slams down, digs in
function Poses.RootHop(B, t, P)
	local H = B.def.Moves.RootHop
	if t < H.Tell then
		local u = t / H.Tell
		P.crouch = smooth(u)
		P.roots = smooth(u)
		P.armLPitch, P.armRPitch = -0.5 * u, -0.5 * u
	elseif t < H.Tell + H.Air then
		local e = t - H.Tell
		P.lift = arcHeight(e, H.Air, 0.45, H.Height)
		P.roots = 1
		P.armLPitch, P.armRPitch = 2.2, 2.2
		P.armLRoll, P.armRRoll = 0.5, 0.5
	else
		local e = t - H.Tell - H.Air
		P.crouch = 0.6 * math.max(spring(e, 5, 10), 0)
		P.roots = 1 - smooth(e / H.Plant)
		P.shake = (e < 0.2) and 0.3 or 0
	end
end

-- SHOVE BURST: bristling... BLAST
function Poses.ShoveBurst(B, t, P)
	local S = B.def.Moves.ShoveBurst
	if t < S.Tell then
		local u = t / S.Tell
		P.crouch = 0.4 * u
		P.armLRoll, P.armRRoll = -0.2 * u, -0.2 * u
		P.shake = 0.12 * u
		P.glow = 1 + 0.4 * u
	else
		local w = spring(t - S.Tell, 5, 12)
		P.armLRoll, P.armRRoll = 0.12 + 1.3 * math.max(w, 0), 0.12 + 1.3 * math.max(w, 0)
		P.crouch = 0
	end
end

-- CORNERED: panicking, flailing, looking for a way out
function Poses.Cornered(B, t, P)
	local now = serverNow()
	P.armLPitch = 1.2 + math.sin(now * 14) * 1.3
	P.armRPitch = 1.2 + math.sin(now * 14 + 2) * 1.3
	P.armLRoll, P.armRRoll = 0.6 + math.sin(now * 11) * 0.4, 0.6 + math.cos(now * 11) * 0.4
	P.headYaw = math.sin(now * 5) * 0.6
	P.shake = 0.12
	P.glow = (math.floor(now * 8) % 2 == 0) and 1.3 or 0.7
	local _ = B
	local _ = t
end

-- STUNNED: out of cactus - slumped, dizzy
function Poses.Stunned(B, t, P)
	local now = serverNow()
	P.lean = 0.5
	P.headPitch = 0.45
	P.armLPitch, P.armRPitch = 0.25, 0.25
	P.sway = math.sin(now * 2.2) * 0.08
	P.glow = 0.3
	P.dizzy = 1
	local _ = B
	local _ = t
end

-- RAGE: arms up, ROAR
function Poses.Rage(B, t, P)
	local R = B.def.Moves.Rage
	local u = clamp(t / 0.3, 0, 1) * (1 - clamp((t - R.Time + 0.3) / 0.3, 0, 1))
	P.roar = u
	P.armLPitch, P.armRPitch = 2.8 * u, 2.8 * u
	P.armLRoll, P.armRRoll = 0.12 + 0.6 * u, 0.12 + 0.6 * u
	P.headPitch = -0.35 * u
	P.shake = 0.28 * u
	P.glow = 1 + 0.5 * u
end

-- NEEDLE VOLLEY: his arm points; three shots, each kicking it back
function Poses.Volley(B, t, P)
	local a = B.def.Attacks.Volley
	local raise = smooth(t / 0.4)
	local kickBack = 0
	for s = 1, a.Shots do
		local e = t - a.Tell - (s - 1) * a.Gap
		if e >= 0 and e < 0.2 then
			kickBack = 1 - e / 0.2
		end
	end
	P.armRPitch = 1.5 * raise - 0.4 * kickBack
	P.glow = 1 + 0.3 * raise
end

-- DESERT RAIN: head back, spitting cactus balls into the sky
function Poses.Rain(B, t, P)
	local a = B.def.Attacks.Rain
	P.headPitch = -0.55 * smooth(t / 0.4)
	local e = t - a.Spit
	P.roar = (e > -0.3) and (0.4 + 0.4 * math.abs(math.sin(e * math.pi / a.Gap))) or 0.2
	P.lean = -0.1
	local _ = B
end

-- SPINE LANCE: an arm drawn back, glowing brighter... THRUST
function Poses.Lance(B, t, P)
	local a = B.def.Attacks.Lance
	if t < a.Charge then
		local u = t / a.Charge
		P.armRPitch = -1.0 * smooth(u)
		P.lean = -0.15 * u
		P.glow = 1 + 0.5 * u
		P.shake = 0.1 * u
		P.twist = -0.3 * u
	else
		local w = clamp((t - a.Charge) / 0.12, 0, 1)
		P.armRPitch = lerp(-1.0, 1.7, w)
		P.lean = 0.2 * w
		P.twist = 0.25 * w
	end
end

-- CACTUS WALL: both fists up... SLAM the ground
function Poses.Wall(B, t, P)
	if t < 0.2 then
		local u = t / 0.2
		P.armLPitch, P.armRPitch = 2.6 * u, 2.6 * u
	else
		local e = t - 0.2
		P.armLPitch, P.armRPitch = 0.9, 0.9
		P.crouch = 0.6 * math.max(spring(e, 4, 9), 0) + 0.2
		P.lean = 0.35
	end
	local _ = B
end

-- NEEDLE TURRETS: a fist punched into the sand
function Poses.Turrets(B, t, P)
	local u = smooth(t / 0.7)
	P.armRPitch = lerp(0, 2.4, clamp(t / 0.4, 0, 1)) * (1 - clamp((t - 0.55) / 0.15, 0, 1)) + 1.0 * clamp((t - 0.55) / 0.15, 0, 1)
	P.crouch = 0.45 * u
	P.lean = 0.3 * u
	local _ = B
end

-- BALL HERD: a stamp and a bellow
function Poses.Herd(B, t, P)
	local w = (t > 0.3) and math.max(spring(t - 0.3, 5, 10), 0) or 0
	P.crouch = 0.4 * w
	P.roar = (t < 0.8) and 0.5 or 0
	P.armLRoll, P.armRRoll = 0.12 + 0.4 * smooth(t / 0.3), 0.12 + 0.4 * smooth(t / 0.3)
	local _ = B
end

-- PRICKLY BUDDIES: he shakes himself and little buddies pop off him
function Poses.Buddies(B, t, P)
	P.shake = (t < 0.5) and 0.25 or 0
	P.armLRoll, P.armRRoll = 0.12 + 0.5 * smooth((t - 0.4) / 0.2), 0.12 + 0.5 * smooth((t - 0.4) / 0.2)
	local _ = B
end

-- QUICKSAND: a big stamp
function Poses.Quicksand(B, t, P)
	local w = (t > 0.3) and math.max(spring(t - 0.3, 5, 11), 0) or 0
	P.crouch = 0.5 * w
	P.shake = (t > 0.3 and t < 0.6) and 0.2 or 0
	local _ = B
end

----------------------------------------------------------------------
-- Starts and SlotSpawns: the moments in each move (sounds, bursts, warnings)
----------------------------------------------------------------------
function Starts.Idle(B, t0)
	local _ = B
	local _ = t0
end

function Starts.Dormant(B, t0)
	if B.prevAction == "Reset" then
		at(B, t0 + 0.05, function()
			burst(atFloor(B, B.vpos) + V3(0, 1, 0), SAND, 16, 10, 2.2, 0.7)
		end)
	end
end

function Starts.Wake(B, t0)
	at(B, t0 + (B.def.WakeSoundLead or 0.2) * 0.2, function()
		sfx(B, "Wake", 1)
		burst(atFloor(B, B.vpos) + V3(0, 1, 0), SAND, 22, 14, 2.2, 0.7, true)
	end)
	at(B, t0 + 1.7, function()
		yell(B, "HI THERE!", 1.3, B.def.FlowerColor or PINK)
	end)
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.1, function()
		if B.formShown == "Brute" then
			sfx(B, "Crash", 0.7)
			burst(atFloor(B, B.vpos) + V3(0, 1, 0), SAND, 30, 16, 3, 0.9, true)
		else
			yell(B, "BYE BYE!", 1.2, B.def.FlowerColor or PINK)
		end
	end)
end

function Starts.Bonk(B, t0)
	local a = B.def.Attacks.Bonk
	B.wedge = wedge(B, a.Reach, a.Arc, t0 + a.Tell, B.def.RageColor or HOT)
	at(B, t0 + a.Tell, function()
		local spot = slot(B, 1) or (atFloor(B, B.vpos) + facingNow(B) * a.Reach * 0.7)
		sfx(B, "Bonk", 0.9, spot)
		burst(spot + V3(0, 0.5, 0), SAND, 12, 10, 1.8, 0.5)
		kick(spot, 14, 0.4, -1.5)
		yell(B, "BONK!", 0.8, YELLOW)
	end)
end

function SlotSpawns.Bonk(B, i, spot, t0)
	if i == 1 and B.wedge then
		B.wedge.dir = unitOr(flat(spot - B.vpos), facingNow(B))
	end
	local _ = t0
end

function Starts.Topple(B, t0)
	local a = B.def.Attacks.Topple
	local hit = t0 + a.Tell + a.Fall
	B.lane = lane(B, a.Width, a.Length, hit, hit + 0.4, B.def.RageColor or HOT)
	at(B, t0 + 0.3, function()
		yell(B, "WHOA...", 0.9, YELLOW)
	end)
	at(B, hit, function()
		local l = B.lane
		local a0 = l and l.a or atFloor(B, B.vpos)
		local b0 = l and l.b or (a0 + facingNow(B) * a.Length)
		sfx(B, "Crash", 1, (a0 + b0) / 2)
		for k = 0, 3 do
			burst(a0:Lerp(b0, k / 3) + V3(0, 0.5, 0), SAND, 10, 12, 2, 0.6)
		end
		kick((a0 + b0) / 2, 22, 0.7, -2.5)
	end)
end

function SlotSpawns.Topple(B, i, spot, t0)
	if B.lane then
		if i == 1 then
			B.lane.pendingA = spot
		elseif i == 2 then
			B.lane.a, B.lane.b = B.lane.pendingA or atFloor(B, B.vpos), spot
		end
	end
	local _ = t0
end

function Starts.Sneeze(B, t0)
	local a = B.def.Attacks.Sneeze
	at(B, t0 + 0.2, function()
		yell(B, "AH...", 0.5, YELLOW)
	end)
	at(B, t0 + 0.75, function()
		yell(B, "AH...", 0.5, YELLOW)
	end)
	at(B, t0 + a.Tell, function()
		yell(B, "ACHOO!", 0.9, WHITE)
		sfx(B, "Sneeze", 1)
		local c = atFloor(B, B.vpos)
		needleRing(B, c, 3, a.Reach, a.Speed, a.Height, B.def.SpineColor)
		burst(c + V3(0, 6, 0), B.def.SpineColor or SAND_LIGHT, 20, 18, 0.8, 0.5)
	end)
	-- (a small red ring round him while he winds up)
	circle(B, atFloor(B, B.vpos), 4.5, t0 + a.Tell, B.def.RageColor or HOT)
end

function Starts.Stomp(B, t0)
	local a = B.def.Attacks.Stomp
	local land = t0 + a.Crouch + a.Air
	at(B, t0 + a.Crouch, function()
		sfx(B, "Hop", 0.6)
		burst(atFloor(B, B.vpos) + V3(0, 0.5, 0), SAND, 10, 8, 1.8, 0.5)
	end)
	at(B, land, function()
		local spot = slot(B, 2) or atFloor(B, B.vpos)
		sfx(B, "Crash", 0.9, spot)
		burst(spot + V3(0, 0.5, 0), SAND, 20, 16, 2.4, 0.6)
		kick(spot, a.Radius + 6, 0.8, -3)
		needleRing(B, spot, a.Radius, a.Radius + a.RingReach, 22, 2.5, SAND_LIGHT)
	end)
end

function SlotSpawns.Stomp(B, i, spot, t0)
	local a = B.def.Attacks.Stomp
	if i == 2 then
		circle(B, spot, a.Radius, t0 + a.Crouch + a.Air, B.def.RageColor or HOT)
	end
end

-- SPLIT!: the buddies' paths arrive one by one
function Starts.Split(B, t0)
	local a = B.def.Attacks.Split
	local root = B.model.PrimaryPart
	local base = root and atFloor(B, root.Position) or atFloor(B, B.vpos)
	B.split = { t0 = t0, base = base, pops = {}, balls = {}, lanes = {}, popEnd = t0 + a.Shake + a.Pop }
	at(B, t0 + 0.05, function()
		yell(B, "SPLIT!", 1.0, B.def.FlowerColor or PINK)
	end)
	at(B, t0 + a.Shake, function()
		sfx(B, "Split", 1)
		burst(base + V3(0, 5, 0), B.def.Color, 18, 16, 1.4, 0.6, true)
	end)
end

function SlotSpawns.Split(B, i, spot, t0)
	local S = B.split
	if not S then
		return
	end
	local a = B.def.Attacks.Split
	if i <= 3 then
		S.pops[i] = spot
		return
	end
	if i == 10 then
		S.rally = spot
		at(B, (S.restackAt or serverNow()) + a.Restack, function()
			sfx(B, "Stack", 0.9, spot)
			burst(spot + V3(0, 4, 0), B.def.Color, 14, 12, 1.4, 0.6, true)
		end)
		return
	end
	local k = math.floor((i - 4) / 2) + 1
	S.pending = S.pending or {}
	if (i - 4) % 2 == 0 then
		S.pending[k] = spot -- (its bounce)
		return
	end
	local pop = S.pops[k] or S.base
	local pts = { pop, S.pending[k] or spot, spot }
	local revAt = S.popEnd + (k - 1) * a.Gap
	local launch = revAt + a.Rev
	local stop = launch + pathLength(pts) / a.Speed
	S.balls[k] = { pts = pts, launch = launch, stop = stop }
	S.lanes[k] = { pop, pts[2] }
	pathLanes(B, pts, a.Radius * 2, serverNow(), stop, B.def.RageColor or HOT)
	at(B, launch, function()
		sfx(B, "Roll", 0.8, pop)
		burst(pop + V3(0, 1, 0), SAND, 12, 14, 1.8, 0.5)
	end)
	if S.balls[1] and S.balls[2] and S.balls[3] then
		local last = math.max(S.balls[1].stop, S.balls[2].stop, S.balls[3].stop)
		S.restackAt = last + a.Dizzy
	end
	local _ = t0
end

-- THE POWER-UP: every sound and burst of it (the rest is drawn every frame)
function Starts.Break(B, t0)
	local def = B.def
	B.breakAt = t0
	B.revealAt = t0 + T_ROAR
	at(B, t0 + 0.05, function()
		sfx(B, "Crash", 0.5)
		yell(B, "...", 1.2, WHITE)
	end)
	at(B, t0 + T_RUMBLE, function()
		sfx(B, "Rumble", 1)
		banner(B, "...?", { color = WHITE, size = 50, hold = 0.8, y = 0.3 })
	end)
	for k = 0, 5 do
		at(B, t0 + T_RUMBLE + k * 0.55, function()
			kick(B.vpos, 80, 0.35, nil)
		end)
	end
	if B.here then
		for i, c in ipairs(cactiOf(B)) do
			local rip = cactusTimes(c)
			at(B, t0 + rip, function()
				burst(c.hub.Position + V3(0, 1, 0), SAND, 8, 10, 1.8, 0.6, true)
				if i % 3 == 1 then
					sfx(B, "Rip", 0.6, c.hub.Position)
				end
			end)
		end
	end
	local shove = t0 + def.BreakTime * 0.35
	at(B, shove, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Form", 1)
		burst(c + V3(0, 6, 0), def.Color, 34, 26, 2, 0.9, true)
		burst(c + V3(0, 1, 0), SAND, 30, 24, 3, 0.9)
		needleRing(B, c, 4, def.BreakReach, 60, 3, SAND_LIGHT)
		kick(c, def.BreakReach + 10, 1.0, -4)
	end)
	at(B, t0 + 4.4, function()
		sfx(B, "Break", 1)
		burst(atFloor(B, B.vpos) + V3(0, 30, 0), def.CrownColor or ORANGE, 24, 18, 1.2, 0.7, true)
	end)
	at(B, t0 + T_THE, function()
		sfx(B, "Crash", 1)
		kick(B.vpos, 200, 1.1, -5)
	end)
	at(B, t0 + T_ROAR, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Roar", 1)
		kick(c, 200, 1.3, -6)
		burst(c + V3(0, 24, 0), def.RageColor or HOT, 30, 22, 1.4, 0.8, true)
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	if B.model:GetAttribute("Form") == "Brute" then
		B.crumbleAt = t0 + 0.8
		B.tinyAt = t0 + 2.4
		B.tinyFrom = atFloor(B, B.vpos)
		local root = myRoot()
		local away = root and unitOr(flat(B.vpos - root.Position), facingNow(B)) or facingNow(B)
		B.tinyDir = away
	end
	at(B, t0 + 0.05, function()
		yell(B, "NO... NOOO!", 1.2, def.RageColor or HOT)
	end)
	at(B, t0 + 0.8, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Death", 1)
		burst(c + V3(0, 12, 0), def.Color, 40, 28, 2, 1.0, true)
		burst(c + V3(0, 2, 0), SAND, 30, 20, 3, 1.0)
		kick(c, 60, 1.1, -4)
	end)
	at(B, t0 + 2.5, function()
		yell(B, "HMPH!", 1.2, def.FlowerColor or PINK)
	end)
end

-- ROOT HOP: where he'll land shows the moment he rips his roots up
function Starts.RootHop(B, t0)
	local H = B.def.Moves.RootHop
	local land = t0 + H.Tell + H.Air
	at(B, t0 + 0.1, function()
		sfx(B, "Hop", 0.8)
		burst(atFloor(B, B.vpos) + V3(0, 0.5, 0), SAND, 14, 10, 2, 0.6, true)
	end)
	at(B, land, function()
		local spot = slot(B, 2) or atFloor(B, B.vpos)
		sfx(B, "Crash", 1, spot)
		burst(spot + V3(0, 1, 0), SAND, 28, 20, 3, 0.8)
		kick(spot, H.RingReach + 10, 0.9, -3.5)
		needleRing(B, spot, H.Radius - 1, H.RingReach, H.RingSpeed, 3, SAND_LIGHT)
	end)
end

function SlotSpawns.RootHop(B, i, spot, t0)
	local H = B.def.Moves.RootHop
	if i == 2 then
		circle(B, spot, H.Radius, t0 + H.Tell + H.Air, B.def.RageColor or HOT)
	end
end

function Starts.ShoveBurst(B, t0)
	local S = B.def.Moves.ShoveBurst
	circle(B, atFloor(B, B.vpos), S.Radius, t0 + S.Tell, B.def.RageColor or HOT)
	at(B, t0 + S.Tell, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Needle", 1)
		burst(c + V3(0, 10, 0), B.def.SpineColor or SAND_LIGHT, 30, 30, 0.8, 0.5)
		needleRing(B, c, 5, S.Radius + 2, 50, 3, SAND_LIGHT)
		kick(c, S.Radius + 8, 0.6, -2)
	end)
end

function Starts.Cornered(B, t0)
	at(B, t0 + 0.05, function()
		yell(B, "!!", 0.9, YELLOW)
	end)
end

function Starts.Stunned(B, t0)
	at(B, t0 + 0.05, function()
		yell(B, "OUT OF CACTUS!", 1.2, YELLOW)
		burst(B.headTop or (B.vpos + V3(0, 26, 0)), YELLOW, 12, 10, 1, 0.6, true)
	end)
end

function Starts.Rage(B, t0)
	local R = B.def.Moves.Rage
	at(B, t0 + 0.1, function()
		sfx(B, "Roar", 1)
		kick(B.vpos, 120, 1.2, -5)
		banner(B, "RAGE!", { color = HOT, sub = "THE CACTUS KING IS FURIOUS", subColor = B.def.CrownColor or ORANGE, size = 80, hold = 1.4 })
	end)
	at(B, t0 + 0.6, function()
		needleRing(B, atFloor(B, B.vpos), 6, R.Reach, 30, 3.5, B.def.SpineColor)
	end)
end

-- NEEDLE VOLLEY: the cone follows you, locks, then three fans of needles
function Starts.Volley(B, t0)
	local a = B.def.Attacks.Volley
	B.wedge = wedge(B, 40, a.Spread, t0 + a.Tell, B.def.RageColor or HOT)
	for s = 1, a.Shots do
		at(B, t0 + a.Tell + (s - 1) * a.Gap, function()
			sfx(B, "Needle", 0.7)
		end)
	end
end

function SlotSpawns.Volley(B, i, spot, t0)
	local a = B.def.Attacks.Volley
	if i == 1 then
		B.volleyFrom = spot
		if B.wedge then
			B.wedge.dir = unitOr(flat(spot - B.vpos), facingNow(B))
		end
		return
	end
	local s = math.floor((i - 2) / a.Needles) + 1
	local fireAt = t0 + a.Tell + (s - 1) * a.Gap
	if B.here and B.volleyFrom then
		needle(B, B.volleyFrom, spot, nil, fireAt, a.Speed)
	end
end

-- DESERT RAIN: each circle as its ball goes up; the ball comes down on it
function Starts.Rain(B, t0)
	at(B, t0 + 0.3, function()
		sfx(B, "Sneeze", 0.6)
		burst((B.headTop or B.vpos + V3(0, 24, 0)), B.def.Color, 10, 20, 1.2, 0.6, true)
	end)
end

function SlotSpawns.Rain(B, i, spot, t0)
	local a = B.def.Attacks.Rain
	local showAt = t0 + a.Spit + (i - 1) * a.Gap
	local landAt = showAt + a.Fall
	circle(B, spot, a.Radius, landAt, B.def.RageColor or HOT)
	if B.here then
		fallingBall(B, spot, landAt, a.Radius)
	end
end

-- SPINE LANCE: the line follows you... locks and flashes... the spike flies
function Starts.Lance(B, t0)
	local a = B.def.Attacks.Lance
	local fire = t0 + a.Charge
	B.lane = lane(B, a.Width, 150, fire, fire + 0.3, B.def.RageColor or HOT)
	at(B, t0 + 0.1, function()
		sfx(B, "Needle", 0.6)
	end)
	at(B, fire, function()
		sfx(B, "Lance", 1)
		kick(B.vpos, 60, 0.7, -2)
	end)
end

function SlotSpawns.Lance(B, i, spot, t0)
	local a = B.def.Attacks.Lance
	if not B.lane then
		return
	end
	if i == 1 then
		B.lane.pendingA = spot
		return
	end
	local from = B.lane.pendingA or atFloor(B, B.vpos)
	B.lane.a, B.lane.b = from, spot
	local fire = t0 + a.Charge
	-- the spike itself
	local spike = newPart("SpineLance", nil, B.def.SpineColor or SAND_LIGHT, nil, 1)
	local tip = newPart("SpineLanceTip", nil, B.def.RageColor or HOT, Enum.Material.Neon, 1)
	local len = flat(spot - from).Magnitude
	local dir = unitOr(flat(spot - from), facingNow(B))
	addTelegraph(B, {
		update = function(now)
			local gone = (now - fire) * a.Speed
			if gone < 0 then
				return true
			end
			if gone > len then
				burst(spot + V3(0, 2, 0), SAND, 14, 14, 2, 0.6)
				return false
			end
			local p = from + dir * gone + V3(0, 2.5, 0)
			spike.CFrame = CFrame.lookAt(p - dir * 5, p)
			spike.Size = V3(1.6, 1.6, 10)
			spike.Transparency = 0
			tip.CFrame = CFrame.lookAt(p + dir * 0.6, p + dir * 2)
			tip.Size = V3(1.0, 1.0, 1.8)
			tip.Transparency = 0
			return true
		end,
		cleanup = function()
			spike:Destroy()
			tip:Destroy()
		end,
	})
end

function Starts.Wall(B, t0)
	at(B, t0 + 0.2, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Crash", 0.8, c)
		burst(c + V3(0, 0.5, 0), SAND, 16, 14, 2.2, 0.6)
		kick(c, 30, 0.6, -2)
	end)
end

function Starts.Turrets(B, t0)
	at(B, t0 + 0.7, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Crash", 0.7, c)
		burst(c + V3(0, 0.5, 0), SAND, 12, 12, 2, 0.6)
	end)
end

function Starts.Herd(B, t0)
	at(B, t0 + 0.3, function()
		sfx(B, "Roar", 0.6)
		kick(B.vpos, 40, 0.4, -1)
	end)
end

function SlotSpawns.Herd(B, i, spot, t0)
	local a = B.def.Attacks.Herd
	B.herd = B.herd or {}
	if i == 1 or (i - 1) % 4 == 0 then
		B.herd = {}
	end
	table.insert(B.herd, spot)
	if #B.herd < 4 then
		return
	end
	local k = math.floor((i - 1) / 4) + 1
	local pts = { B.herd[1] }
	for j = 2, 4 do
		if flat(B.herd[j] - pts[#pts]).Magnitude > 0.2 then
			table.insert(pts, B.herd[j])
		end
	end
	B.herd = {}
	if #pts < 2 then
		return
	end
	local showAt = t0 + a.Show + (k - 1) * a.Gap
	local launch = showAt + a.Tell
	local stop = launch + pathLength(pts) / a.Speed
	pathLanes(B, pts, a.Radius * 2, showAt, stop, B.def.RageColor or HOT)
	if B.here then
		rollingBall(B, pts, launch, a.Speed, a.Radius * 2)
		at(B, launch, function()
			sfx(B, "Roll", 0.6, pts[1])
		end)
	end
end

function Starts.Buddies(B, t0)
	at(B, t0 + 0.5, function()
		sfx(B, "Split", 0.7)
		burst((B.headTop or B.vpos + V3(0, 20, 0)) - V3(0, 8, 0), B.def.Color, 14, 14, 1.4, 0.6, true)
	end)
end

function Starts.Quicksand(B, t0)
	at(B, t0 + 0.35, function()
		local c = atFloor(B, B.vpos)
		sfx(B, "Crash", 0.7, c)
		kick(c, 40, 0.5, -1.5)
		burst(c + V3(0, 0.5, 0), SAND, 14, 12, 2.4, 0.6)
	end)
end

----------------------------------------------------------------------
-- The hint over him while he's open ("HIT HIM!")
----------------------------------------------------------------------
local function hintOf(B, now)
	local t = now - (B.actionStart or now)
	local a = B.def.Attacks
	if B.action == "Cornered" or B.action == "Stunned" then
		return "HIT HIM!"
	end
	if B.action == "Topple" then
		local hit = a.Topple.Tell + a.Topple.Fall
		if t >= hit and t < hit + a.Topple.Down then
			return "HIT HIM!"
		end
	end
	local S = B.split
	if B.action == "Split" and S and S.restackAt and S.balls[3] then
		local last = math.max(S.balls[1].stop, S.balls[2].stop, S.balls[3].stop)
		if now >= last and now < S.restackAt then
			return "DIZZY! HIT THEM!"
		end
	end
	return nil
end

local function stepHint(B, show)
	local now = serverNow()
	local want = show and hintOf(B, now) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(now * 6) % 2 == 0) and 0 or 0.25
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
		bb.Name = "TuberHint"
		bb.Size = UDim2.new(0, 300, 0, 30)
		bb.StudsOffsetWorldSpace = V3(0, 3, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.body.anchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
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

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- which of his forms shows right now: little Tuber, the golem - or, in the
-- middle of the power-up, the golem slamming together round him
local function formNow(B, now)
	local t = breakTime(B, now)
	if t then
		if t < T_BUILD then
			return "Stack", nil
		elseif t < T_BUILT then
			return "Morph", t
		end
		return "Brute", nil
	end
	if B.model:GetAttribute("Form") == "Brute" then
		return "Brute", nil
	end
	return "Stack", nil
end

-- what his moves are made of: cactus green, and sand
function Body.fx(def)
	return { color = def.Color, deep = def.DeepColor, rock = SAND, material = Enum.Material.SmoothPlastic, solid = true }
end

-- where he is between the server's updates: exactly on his hop's arc (the
-- server's own sums), otherwise BossClient's smoothing
function Body.glide(B, now, ground)
	local _ = ground
	local t = now - (B.actionStart or now)
	local from, to = slot(B, 1), slot(B, 2)
	if not (from and to) then
		return nil
	end
	local lead, air
	if B.action == "RootHop" then
		lead, air = B.def.Moves.RootHop.Tell, B.def.Moves.RootHop.Air
	elseif B.action == "Stomp" then
		lead, air = B.def.Attacks.Stomp.Crouch, B.def.Attacks.Stomp.Air
	else
		return nil
	end
	local u = clamp((t - lead) / air, 0, 1)
	return from:Lerp(to, u)
end

-- a pose, played: his form for this moment, his usual face, the move's shape
function Body.runPose(B, shape, t, now, P)
	local form, bt = formNow(B, now)
	B.formShown, B.buildT = form, bt
	P.eyes, P.mouth = "open", "smile"
	P.glow = 1
	P.roots = 0
	P.wobble = B.model:GetAttribute("Moving") and 1 or 0.25
	-- (the golem breathes slower and heavier)
	if form ~= "Stack" then
		P.sy, P.sx, P.sz = 1, 1, 1
		P.lean = 0
		P.sway = math.sin(now * 1.2) * 0.02
	end
	shape(B, t, P)
	-- which way he faces: the server's facing, turned smoothly
	local dt = clamp(now - (B.faceAt or now), 0, 0.1)
	B.faceAt = now
	local want = unitOr(flat(B.vfacing or V3(0, 0, -1)), V3(0, 0, -1))
	if not B.faceDir then
		B.faceDir = want
	else
		local k = 1 - math.exp(-math.max(dt, 1 / 240) * 12)
		B.faceDir = unitOr(B.faceDir:Lerp(want, k), want)
	end
	P.facing = B.faceDir
end

-- a new move began
function Body.onAction(B, name, t0, now)
	-- (split up and not stacked back yet - the power-up, a reset: his buddies
	-- hop back together from where they were; placeRejoin draws it)
	B.rejoin = nil
	local S = B.split
	if S and name ~= "Split" then
		local a = B.def.Attacks.Split
		if not (S.restackAt and t0 >= S.restackAt + a.Restack - 0.05) then
			local from = {}
			for k = 1, 3 do
				local ok, pos, up = pcall(splitPos, B, k, t0)
				if ok and pos then
					from[k] = { pos = pos, up = up or 0 }
				end
			end
			B.rejoin = { t0 = t0, from = from }
		end
	end
	if name ~= "Split" then
		B.split = nil
	end
	if name ~= "Death" then
		B.crumbleAt, B.shards, B.tinyAt = nil, nil, nil
	end
	B.wedge, B.lane = nil, nil
	local _ = t0
	local _ = now
end

-- joined while round 2 was already on
function Body.lateBreak(B)
	B.phase2Look = true
end

-- a fresh start: the cacti home, the animals gone, his mess swept away
function Body.calm(B, name)
	clearProps(B)
	B.cactiMode = nil -- (they go back where they grew next frame)
	B.revealAt, B.breakAt = nil, nil
	B.split, B.rejoin = nil, nil
	B.crumbleAt, B.shards, B.tinyAt = nil, nil, nil
	if B.shooting then
		B.shooting = false
		shot(nil)
	end
	local _ = name
end

-- every frame: the desert (the cacti, the audience, his cactus mess), the
-- power-up's letters and camera, the hint over him
function Body.senses(B, dt, here, awake, state)
	B.here = here
	B.stateNow = state
	local now = serverNow()
	local hopAt = B.model:GetAttribute("HopAt")
	B.hopReady = B.model:GetAttribute("Form") == "Brute" and type(hopAt) == "number" and now >= hopAt
	-- (each on its own: if one ever fails it's reported once in the Output,
	-- and the rest carry on)
	local function run(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.warned = B.warned or {}
			if not B.warned[name] then
				B.warned[name] = true
				warn("[BossClient] Tuber's " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	run("cacti", stepCacti, B, now)
	run("audience", stepAudience, B, now)
	run("cactus mess", stepProps, B, now, dt)
	run("letters", stepTitle, B, now)
	run("camera", stepShot, B, now)
	run("hint", stepHint, B, here and awake)
end

-- you can't walk through him: nudged out of his round little body, or the
-- golem's great trunk. (Not while he's in pieces, lying flat, in the air or
-- falling apart.)
function Body.pushOut(B, P, here, awake, state)
	if not here or not (awake or state == "Dormant") then
		return
	end
	if B.split or (P.topple or 0) > 0.2 or (P.lift or 0) > 4 or B.crumbleAt or B.formShown == "Morph" or (P.sink or 0) > 3 then
		return
	end
	local hrp = myRoot()
	if not hrp then
		return
	end
	local radius = (B.formShown == "Brute") and (B.def.Brute.Reach + 1.3) or (B.def.Size * 0.4 + 1.2)
	local offset = flat(hrp.Position - B.vpos)
	if offset.Magnitude < radius and hrp.Position.Y < floorY(B) + ((B.formShown == "Brute") and 26 or 11) then
		local out = offset.Magnitude > 0.05 and offset.Unit or facingNow(B)
		local target = B.vpos + out * radius
		hrp.CFrame = CFrame.new(V3(target.X, hrp.Position.Y, target.Z)) * (hrp.CFrame - hrp.Position)
	end
end

-- HIS TWO HEALTH BARS (BossClient asks every frame). His health is one
-- pool on the server: round 1's bar is the part above PhaseAt, the Brute's
-- the part below. During the power-up round 1's bar sits empty; the
-- Brute's fills up the moment he roars.
function Body.barLook(B, now, share)
	local m = B.model
	local max = math.max(num(m:GetAttribute("MaxHealth"), 1), 1)
	local hp = num(m:GetAttribute("Health"), 0)
	local line = math.max(1, math.floor(max * B.def.PhaseAt))
	if num(m:GetAttribute("Phase"), 1) < 2 then
		return { name = B.def.Name, share = clamp((hp - line) / math.max(max - line, 1), 0, 1), color = B.def.Color }
	end
	if B.revealAt and now < B.revealAt then
		return { name = B.def.Name, share = 0, color = B.def.Color }
	end
	local fill = B.revealAt and smooth((now - B.revealAt) / 1.6) or 1
	local _ = share
	return { name = B.def.Round2Name or B.def.Name, share = math.min(fill, clamp(hp / line, 0, 1)), color = RED }
end

-- THE MUSIC: round 1's song; silence while he powers up; round 2's the
-- moment THE BRUTE is named
function Body.music(B, now)
	if num(B.model:GetAttribute("Phase"), 1) < 2 then
		return B.def.Music
	end
	if B.revealAt and now < B.revealAt then
		return false
	end
	return B.def.Round2Music or B.def.Music, B.def.Round2MusicVolume
end

-- THE SANDSTORM: just a breeze while little Tuber fights; the power-up
-- whips up a storm (a wall of sand rolls in) round the flying cactus; then
-- a haze for the Brute, so you can still see the animals watching
function Body.stormWant(B, state, want)
	local _ = want
	if state ~= "Waking" and state ~= "Fighting" and state ~= "Transition" then
		return 0.2
	end
	if num(B.model:GetAttribute("Phase"), 1) < 2 then
		return 0.3
	end
	local t = breakTime(B, serverNow())
	if t and t > T_RUMBLE and t < 6.8 then
		return 1
	end
	return 0.55
end

return Body
