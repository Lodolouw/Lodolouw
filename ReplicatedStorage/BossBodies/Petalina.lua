--[[
	Petalina  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Petalina")

	How Petalina, the Blooming Terror (floor 8's boss, Config.Bosses[8]) looks
	on your screen: a giant chunky 8-bit cartoon flower, taller than a house -
	a thick green stem curving up out of her mound of roots, two big leaves
	she uses like arms, and on top a big round yellow face ringed with pink
	petals: huge eyes with long lashes, rosy cheeks and a sweet smile. In
	round 2 her petals go dark red, her brows come down, her smile turns into
	a grin full of fangs, and thorns sprout all along her stem.

	Everything she does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Petalina.lua, where each move is explained):
	  * Poses[move]   her body t seconds into a move: puffing her cheeks,
	                  flinging petals with her leaves, slapping the ground,
	                  shaking her head, her head stretching out down its lane
	                  (exactly on GardenPlan.headPoint, the server's own path)
	                  and lying there dizzy, humming in the sun...
	  * Starts[move]  the move's sounds, bursts and camera kicks, and its
	                  warnings on the floor, all timed on the server's clock
	  * SlotSpawns    warnings for the spots the server fills in: each seed's
	                  red circle, each petal's dotted loop, each vine line,
	                  each pollen cloud, the lane's end
	  * Body.senses   every frame: her FLYTRAPS (Workspace.PetalinaProps -
	                  sprouting, gaping, snapping, popping, wilting), round 2's
	                  BRAMBLES growing up out of the flower beds (the arena's
	                  "GardenThorn" clumps), the butterflies ("GardenButterfly")
	                  and the "HIT HER!" over her when she's open
	  * the moments every boss has: asleep as a closed bud, blooming awake
	    (the petals unfurl, a stretch, "HELLO, SWEETIE~!"), closing up again
	    when everyone leaves, turning evil at half health, and wilting at the
	    end - her petals dropping one by one

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: bloom (0 a closed bud - 1 wide open),
	sway, lean (her head forward/back), headPitch (face up +, down -), spin
	(her head spinning round), leafL / leafR (her leaves: -1 slapped down, 0
	resting, 1 up high), mouthShape ("smile" / "o" / "wide" / "grin" /
	"chomp"), mouth (0-1 open), eyes (0-1 open), happy (eyes closed happily),
	puff (cheeks puffed), dizzy, lost (petals fallen off), droop (her head on
	the floor - the Face Stretch sets its own head spot), shake, fade.
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GardenPlan = require(ReplicatedStorage:WaitForChild("GardenPlan"))

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES, bigText, shout

function Body.init(kit)
	serverNow, clamp, lerp, smooth, flat = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES = kit.kick, kit.playSound, kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES
	bigText, shout = kit.bigText, kit.shout
end

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in her Config
local RED = RGB(228, 59, 68)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local YELLOW = RGB(254, 231, 97)
local GREEN = RGB(99, 199, 77)
local GREEN_DARK = RGB(62, 137, 72)
local PINK = RGB(246, 117, 122)
local SOIL = RGB(115, 62, 57)
local SOIL_DARK = RGB(62, 39, 49)
local SEED = RGB(62, 39, 49)
local POLLEN = RGB(254, 231, 97)
local BROWN = RGB(184, 111, 80)
local PIXEL_FONT = nil
pcall(function()
	PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

local PETALS = 12
local STEM_SEGS = 8
local NECK_SEGS = 8
local THORNLETS = 8

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function slot(B, i)
	local v = B.model:GetAttribute(SLOT_NAMES[i])
	return typeof(v) == "Vector3" and v or nil
end

local function num(v, fallback)
	return type(v) == "number" and v or fallback
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

-- a block stretched from a to b (world points), `w` wide and `d` deep
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
	if math.abs(dir.Unit:Dot(up)) > 0.98 then
		up = V3(1, 0, 0)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- a point `u` along the curve from a (through the pull of c) to b
local function bezier(a, c, b, u)
	local p = a:Lerp(c, u)
	local q = c:Lerp(b, u)
	return p:Lerp(q, u)
end

-- eases B[key] toward `want` (a number) at `rate`
local function smoothNum(B, key, want, rate, dt): number
	local old = B[key]
	if type(old) ~= "number" then
		B[key] = want
		return want
	end
	local v = old + (want - old) * (1 - math.exp(-dt * rate))
	B[key] = v
	return v
end

local function show(p, on)
	p.Transparency = on and 0 or 1
end

-- The Face Stretch's timing (the server's own sums): where her head is now,
-- or nil while it's up on her stem
local function headNow(B, now)
	if B.action ~= "FaceStretch" or not B.actionStart then
		return nil, nil
	end
	local a = B.def.Attacks.FaceStretch
	local finish = slot(B, 1)
	if not finish then
		return nil, nil
	end
	local shootAt = B.actionStart + a.Tell
	local landAt = shootAt + a.Time
	local backAt = landAt + a.Droop
	local base = B.vpos
	local H = B.def.HeadHeight
	if now < shootAt then
		return nil, nil
	elseif now < landAt then
		return GardenPlan.headPoint(base, H, finish, 2.5, (now - shootAt) / a.Time), "shoot"
	elseif now < backAt then
		return finish + V3(0, 2.5, 0), "droop"
	elseif now < backAt + a.Back then
		return GardenPlan.headPoint(base, H, finish, 2.5, 1 - (now - backAt) / a.Back), "back"
	end
	return nil, nil
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {}, tinted = {} }
	local function add(name, color, material, tint)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, p)
		if tint ~= false then
			table.insert(body.tinted, { part = p, color = color })
		end
		return p
	end
	-- the stem, in segments (and the neck that stretches out for the Face Stretch)
	body.stem, body.neck = {}, {}
	for i = 1, STEM_SEGS do
		body.stem[i] = add("Stem", (i % 2 == 0) and def.StemColor or def.StemDeep)
	end
	for i = 1, NECK_SEGS do
		body.neck[i] = add("Neck", (i % 2 == 0) and def.StemColor or def.StemDeep)
	end
	-- round 2: thorns all along the stem
	body.thornlets = {}
	for i = 1, THORNLETS do
		body.thornlets[i] = add("StemThorn", def.ThornTip)
	end
	-- two big leaves she uses like arms, and two little ones low down
	body.leaves, body.leafTips = {}, {}
	for i = 1, 4 do
		body.leaves[i] = add("Leaf", def.StemColor)
		body.leafTips[i] = add("LeafTip", def.StemDeep)
	end
	-- the head: petals behind, the petals, their tips, the face
	body.backPetals, body.petals, body.tips = {}, {}, {}
	for i = 1, PETALS do
		body.backPetals[i] = add("PetalBack", def.DeepColor)
		body.petals[i] = add("Petal", def.Color)
		body.tips[i] = add("PetalTip", def.TipColor)
	end
	body.faces = { add("Face", def.FaceColor), add("Face", def.FaceColor) }
	body.eyes, body.pupils, body.shines, body.lashes, body.brows, body.cheeks = {}, {}, {}, {}, {}, {}
	for i = 1, 2 do
		body.eyes[i] = add("Eye", def.EyeColor)
		body.pupils[i] = add("Pupil", def.CoreColor)
		body.shines[i] = add("Shine", WHITE)
		body.lashes[i] = { add("Lash", def.CoreColor), add("Lash", def.CoreColor) }
		body.brows[i] = add("Brow", def.CoreColor)
		body.cheeks[i] = add("Cheek", def.CheekColor)
	end
	body.mouth = add("Mouth", def.CoreColor)
	body.corners = { add("MouthCorner", def.CoreColor), add("MouthCorner", def.CoreColor) }
	body.tongue = add("Tongue", PINK)
	body.teeth = add("Teeth", WHITE)
	body.fangs = {}
	for i = 1, 4 do
		body.fangs[i] = add("Fang", WHITE)
	end
	-- dizzy stars round her head
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon, false)
	end
	-- the shadow under her head, and the spot word bubbles hang from
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0, folder)
	body.anchor = newPart("Anchor", nil, WHITE, Enum.Material.SmoothPlastic, 1, folder)
	body.anchor.Size = V3(0.2, 0.2, 0.2)
	-- each part vanishes at its own moment when she pops into pixels
	body.popAt = {}
	for i, p in ipairs(body.all) do
		body.popAt[p] = ((i * 37) % 23) / 23
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting her together every frame
----------------------------------------------------------------------
local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 10
	local H = def.HeadHeight
	local rate = P.snap and 60 or (P.rate or 10)
	local bloom = smoothNum(B, "bloomS", clamp(P.bloom or 1, 0, 1), rate * 0.6, dt)
	local lean = smoothNum(B, "leanS", P.lean or 0, rate, dt)
	local pitch = smoothNum(B, "pitchS", P.headPitch or 0, rate, dt)
	local leafL = smoothNum(B, "leafLS", P.leafL or 0, rate * 1.2, dt)
	local leafR = smoothNum(B, "leafRS", P.leafR or 0, rate * 1.2, dt)
	local puff = smoothNum(B, "puffS", P.puff or 0, rate * 1.5, dt)
	local openM = smoothNum(B, "mouthS", clamp(num(P.mouth, 0), 0, 1), rate * 1.5, dt)
	local eyes = smoothNum(B, "eyesS", clamp(num(P.eyes, 1), 0, 1), rate * 1.5, dt)
	local sway = (P.sway or 0) + math.sin(os.clock() * 1.3) * 0.6 * (P.calm == false and 0 or 1)
	local fade = P.fade or 0
	local mad = B.phase2Look
	local flash = B.flashAt and (os.clock() - B.flashAt) < 0.1
	local look = unitOr(flat(facing), V3(0, 0, -1))
	local right = V3(-look.Z, 0, look.X)
	local jitter = V3()
	if (P.shake or 0) > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local base = ground + V3(0, 0.8, 0) + jitter * 0.3

	-- WHERE HER HEAD IS: up on her stem (swaying, leaning), or out on the
	-- Face Stretch's path, or drooped down to the floor at the very end
	local restHead = base + V3(0, H - 0.8, 0) + right * sway + look * (lean * 6) + jitter
	local out, stage = headNow(B, serverNow())
	local droop = smoothNum(B, "droopS", clamp(P.droop or 0, 0, 1), 3, dt)
	local head = restHead
	if out then
		head = out
	elseif droop > 0 then
		-- (wilting: her head bends right over to the floor in front of her)
		local down = ground + look * 12 + V3(0, 3, 0)
		head = restHead:Lerp(down, smooth(droop))
	end
	-- which way her face looks: at you (the way she faces), tipped by
	-- headPitch; out on the stretch it looks down the lane, and lying on the
	-- floor it looks up, dizzy
	local faceDir = look
	local pitchNow = pitch
	if out then
		local lane = unitOr(flat(head - ground), look)
		faceDir = lane
		pitchNow = (stage == "droop") and 0.9 or -0.35
	elseif droop > 0 then
		pitchNow = lerp(pitch, 1.1, droop)
	end
	local headCF = CFrame.lookAt(head, head + faceDir) * CFrame.Angles(pitchNow, 0, 0) * CFrame.Angles(0, 0, P.spin or 0)
	B.headPos = head

	-- THE STEM: a curve from her mound up to the back of her head (at rest),
	-- in segments; out on the stretch, the NECK curves on from there to her head
	local stemTop = restHead - V3(0, 3.2 * u, 0) + look * 0.8
	local bend = base:Lerp(stemTop, 0.5) + right * (sway * 1.6) - look * (2 + lean * 3)
	if droop > 0 then
		stemTop = stemTop:Lerp(head - V3(0, 2, 0) - look * 2, droop)
		bend = bend:Lerp(base + V3(0, H * 0.55, 0) + look * 2, droop)
	end
	local pts = {}
	for i = 0, STEM_SEGS do
		pts[i] = bezier(base, bend, stemTop, i / STEM_SEGS)
	end
	for i = 1, STEM_SEGS do
		local w = lerp(2.6, 1.7, i / STEM_SEGS) * u
		stretch(body.stem[i], pts[i - 1], pts[i] + (pts[i] - pts[i - 1]).Unit * 0.3, w, w, look)
	end
	local neckOn = out ~= nil
	if neckOn then
		local hb = head - faceDir * 1.2 * u
		local mid = stemTop:Lerp(hb, 0.5) + V3(0, 3 + (head - stemTop).Magnitude * 0.12, 0)
		local prev = stemTop
		for i = 1, NECK_SEGS do
			local p = bezier(stemTop, mid, hb, i / NECK_SEGS)
			local w = lerp(1.7, 1.4, i / NECK_SEGS) * u
			stretch(body.neck[i], prev, p + (p - prev).Unit * 0.25, w, w, V3(0, 1, 0))
			prev = p
		end
	end
	for i = 1, NECK_SEGS do
		show(body.neck[i], neckOn and fade < 0.5)
	end
	-- round 2: thorns along the stem
	for i, th in ipairs(body.thornlets) do
		local k = math.clamp(math.floor((i - 0.5) / THORNLETS * STEM_SEGS) + 1, 1, STEM_SEGS)
		local p = pts[k - 1]:Lerp(pts[k], 0.5)
		local side = (i % 2 == 0) and 1 or -1
		local outDir = (right * side + look * ((i % 3) - 1) * 0.6).Unit
		th.Size = V3(0.5, 0.5, 1.4) * u
		th.CFrame = CFrame.lookAt(p + outDir * 1.3 * u, p + outDir * 3)
		show(th, mad and fade < 0.5)
	end

	-- THE LEAVES: two big ones (arms) halfway up, two little ones low down
	for i = 1, 4 do
		local big = i <= 2
		local side = (i % 2 == 1) and -1 or 1
		local k = big and 0.42 or 0.18
		local root = bezier(base, bend, stemTop, k)
		local lift = big and ((side < 0) and leafL or leafR) or 0
		-- (-1 slapped down to the floor, 0 resting out to the side, 1 raised high)
		local len = (big and 7 or 3.6) * u
		local outDir = (right * side * math.cos(lift * 0.9) + V3(0, math.sin(lift * 1.1) + (big and 0.25 or 0.35), 0) + look * 0.25).Unit
		local tip = root + outDir * len
		if big and lift < -0.3 then
			-- slapping the ground: the leaf reaches down to the floor in front of her
			local slap = ground + right * side * 7 + look * 6 + V3(0, 0.6, 0)
			tip = tip:Lerp(slap, clamp((-lift - 0.3) / 0.7, 0, 1))
		end
		local leaf, leafTip = body.leaves[i], body.leafTips[i]
		local blade = (big and 3.2 or 1.8) * u
		stretch(leaf, root, tip, blade, 0.5 * u, V3(0, 1, 0))
		local tipDir = unitOr(tip - root, outDir)
		stretch(leafTip, tip - tipDir * 0.5, tip + tipDir * (big and 2 or 1.1) * u, blade * 0.55, 0.45 * u, V3(0, 1, 0))
	end

	-- THE HEAD: the petals (a closed bud when bloom is 0), the face, the eyes
	local R = 3.6 * u -- the face's radius
	local lost = P.lost or 0
	for i = 1, PETALS do
		local a = (i - 0.5) / PETALS * math.pi * 2
		local fold = (1 - bloom) * 1.3 + (P.wiltFold or 0)
		local L = 4.2 * u
		local hinge = headCF * CFrame.Angles(0, 0, a) * CFrame.new(R * 0.85, 0, 0.3 * u) * CFrame.Angles(0, fold, 0)
		local petal, tipP, back = body.petals[i], body.tips[i], body.backPetals[i]
		petal.Size = V3(L, 2.9 * u, 0.6 * u)
		petal.CFrame = hinge * CFrame.new(L / 2, 0, 0)
		tipP.Size = V3(1.5 * u, 2.1 * u, 0.62 * u)
		tipP.CFrame = hinge * CFrame.new(L + 0.5 * u, 0, 0)
		local bh = headCF * CFrame.Angles(0, 0, a + math.pi / PETALS) * CFrame.new(R * 0.8, 0, 0.8 * u) * CFrame.Angles(0, fold * 0.8, 0)
		back.Size = V3(L * 1.1, 3.2 * u, 0.5 * u)
		back.CFrame = bh * CFrame.new(L * 0.55, 0, 0)
		local gone = i <= lost
		show(petal, not gone and fade < 0.5)
		show(tipP, not gone and fade < 0.5)
		show(back, not gone and fade < 0.5)
	end
	-- the face: two crossed blocks make a chunky pixel circle (a bit wider
	-- when her cheeks are puffed)
	local fw = 1 + 0.18 * puff
	body.faces[1].Size = V3(2 * R * fw, 2 * R * 0.7, 1.4 * u)
	body.faces[2].Size = V3(2 * R * 0.7 * fw, 2 * R, 1.4 * u)
	body.faces[1].CFrame = headCF
	body.faces[2].CFrame = headCF
	local front = -0.72 * u -- (the face's front, in the head's space)
	-- eyes: open, shut (a line), or happily shut; the pupils look where she faces
	local happy = P.happy or 0
	local dizzy = P.dizzy or (stage == "droop" and 1 or 0)
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local ecf = headCF * CFrame.new(side * 1.35 * u, 0.7 * u, front - 0.05)
		local open = eyes * (1 - happy)
		local eh = math.max(2.3 * u * open, 0.3 * u)
		body.eyes[i].Size = V3(1.5 * u, eh, 0.14)
		body.eyes[i].CFrame = ecf
		body.eyes[i].Color = (open < 0.2) and def.CoreColor or def.EyeColor
		local roll = V3()
		if dizzy > 0 then
			local sp = os.clock() * 10 + i
			roll = V3(math.cos(sp) * 0.3 * u, math.sin(sp) * 0.3 * u, 0)
		end
		local pupil = body.pupils[i]
		pupil.Size = V3(0.8 * u, math.max(1.3 * u * open, 0.05), 0.14)
		pupil.CFrame = ecf * CFrame.new(side * -0.1 * u + roll.X, -0.15 * u + roll.Y, -0.06)
		pupil.Color = mad and (def.ThornTip or RED) or def.CoreColor
		show(pupil, open > 0.2 and fade < 0.5)
		body.shines[i].Size = V3(0.32 * u, 0.4 * u, 0.1)
		body.shines[i].CFrame = pupil.CFrame * CFrame.new(0.18 * u, 0.3 * u, -0.05)
		show(body.shines[i], open > 0.2 and not mad and fade < 0.5)
		-- long lashes flicking out at the top corner
		for j, lash in ipairs(body.lashes[i]) do
			lash.Size = V3(0.25 * u, 0.9 * u, 0.12)
			lash.CFrame = ecf * CFrame.new(side * (0.55 + 0.35 * j) * u, eh / 2 + 0.2 * u, -0.02) * CFrame.Angles(0, 0, -side * (0.5 + 0.3 * j))
			show(lash, fade < 0.5)
		end
		-- brows: sweet arches in round 1, angry slants in round 2
		local brow = body.brows[i]
		brow.Size = V3(1.6 * u, 0.32 * u, 0.12)
		if mad then
			brow.CFrame = headCF * CFrame.new(side * 1.3 * u, 2.0 * u, front - 0.08) * CFrame.Angles(0, 0, side * 0.45)
		else
			brow.CFrame = headCF * CFrame.new(side * 1.35 * u, 2.3 * u, front - 0.08) * CFrame.Angles(0, 0, -side * 0.2)
		end
		show(brow, fade < 0.5)
		local cheek = body.cheeks[i]
		cheek.Size = V3(1.2 * u * (1 + 0.4 * puff), 0.7 * u * (1 + 0.5 * puff), 0.12)
		cheek.CFrame = headCF * CFrame.new(side * 2.35 * u * fw, -0.55 * u, front - 0.04)
	end
	-- the mouth: a smile, an "o", wide open, a fanged grin, or snapped shut
	local shape = P.mouthShape or (mad and "grin" or "smile")
	local mw, mh, my = 2.4, 0.45, -1.7
	if shape == "o" then
		mw, mh = 1.1 + 0.4 * openM, 0.9 + 0.8 * openM
	elseif shape == "wide" then
		mw, mh = 3.4, 0.6 + 2.0 * openM
	elseif shape == "grin" then
		mw, mh = 3.6, 0.7 + 1.2 * openM
	elseif shape == "chomp" then
		mw, mh = 3.4, 0.35
	end
	local mcf = headCF * CFrame.new(0, (my - mh / 2 + 0.2) * u, front - 0.07)
	body.mouth.Size = V3(mw * u, mh * u, 0.12)
	body.mouth.CFrame = mcf
	for i, c in ipairs(body.corners) do
		local side = (i == 1) and -1 or 1
		c.Size = V3(0.45 * u, 0.45 * u, 0.12)
		c.CFrame = mcf * CFrame.new(side * (mw / 2 + 0.1) * u, (mh / 2 + 0.15) * u, 0)
		show(c, (shape == "smile" or shape == "grin") and fade < 0.5)
	end
	local tongueOn = mh > 1.2 and shape ~= "grin"
	body.tongue.Size = V3(mw * 0.55 * u, math.min(mh * 0.35, 0.8) * u, 0.1)
	body.tongue.CFrame = mcf * CFrame.new(0, -mh * 0.3 * u, -0.03)
	show(body.tongue, tongueOn and fade < 0.5)
	local teethOn = mh > 1 and not mad
	body.teeth.Size = V3(mw * 0.8 * u, 0.32 * u, 0.1)
	body.teeth.CFrame = mcf * CFrame.new(0, (mh / 2 - 0.2) * u, -0.04)
	show(body.teeth, teethOn and fade < 0.5)
	for i, fg in ipairs(body.fangs) do
		local x = (i - 2.5) / 1.5 * (mw / 2 - 0.4)
		fg.Size = V3(0.45 * u, 0.45 * u, 0.1)
		fg.CFrame = mcf * CFrame.new(x * u, (mh / 2 - 0.25) * u, -0.04) * CFrame.Angles(0, 0, math.rad(45))
		show(fg, mad and fade < 0.5)
	end

	-- dizzy stars
	for i, st in ipairs(body.stars) do
		if dizzy > 0.05 and fade < 0.5 then
			local a = os.clock() * 5 + i * (math.pi * 2 / 3)
			local p = head + V3(math.cos(a) * 5 * u, 4.6 * u, math.sin(a) * 5 * u)
			st.Size = V3(1.1, 1.1, 0.45) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, os.clock() * 6)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- word bubbles hang over her head; her shadow under it
	B.headTop = head + V3(0, R + 4.5 * u, 0)
	body.anchor.CFrame = CFrame.new(B.headTop + V3(0, 1, 0))
	B.mouthPos = mcf.Position
	placeDisc(body.shadow, onFloor(V3(head.X, ground.Y, head.Z)) + V3(0, 0.07, 0), 10 * u, 0.1)
	body.shadow.Transparency = (fade > 0.5) and 1 or 0.35

	-- colours: the hit flash; round 2's wicked petals
	for _, tp in ipairs(body.tinted) do
		local want = tp.color
		if mad then
			if tp.part.Name == "Petal" then
				want = def.EvilColor
			elseif tp.part.Name == "PetalTip" then
				want = def.EvilTip
			elseif tp.part.Name == "PetalBack" then
				want = def.ThornColor
			end
		end
		tp.part.Color = flash and WHITE or want
	end

	-- popping into pixels at the end: each part at its own moment
	if fade > 0 then
		for _, p in ipairs(body.all) do
			if fade >= body.popAt[p] * 0.9 + 0.05 then
				p.Transparency = 1
			end
		end
	end
	local _ = t
end
Body.pose = applyPose

----------------------------------------------------------------------
-- Her warnings in the world
----------------------------------------------------------------------
-- a red circle on the floor, filling in until `hitAt`, blinking white at the end
local function warnCircle(B, name, spot, radius, fromT, hitAt, color)
	local disc = newPart(name, Enum.PartType.Cylinder, color or RED, Enum.Material.Neon, 1)
	local ring = newRing(20, color or RED, Enum.Material.Neon, 1)
	local c = onFloor(spot)
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.05 then
				return false
			end
			local k = clamp((now - fromT) / math.max(hitAt - fromT, 0.05), 0, 1)
			local blink = k > 0.75 and (math.floor(now * 12) % 2 == 0)
			placeDisc(disc, c + V3(0, 0.12, 0), radius * 2 * (0.25 + 0.75 * k), 0.1)
			disc.Transparency = lerp(0.7, 0.35, k)
			disc.Color = blink and WHITE or (color or RED)
			placeRing(ring, c + V3(0, 0.14, 0), radius, 0.3, 0.45, 0.2)
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

local function dirt(B, spot, big)
	local c = onFloor(spot)
	burst(c + V3(0, 0.6, 0), SOIL, big and 20 or 12, big and 22 or 14, big and 1.6 or 1.1, 0.55)
	local _ = B
end

-- A SEED: from her mouth (or high up by the glass roof, `fromRoof`) in an
-- arc to `spot`, landing at `landAt` on its red circle
local function seedFlight(B, spot, spitAt, landAt, radius, fromRoof)
	warnCircle(B, "SeedWarning", spot, radius, serverNow(), landAt)
	local seed = newPart("Seed", nil, SEED, Enum.Material.SmoothPlastic, 1)
	seed.Size = V3(1.1, 1.5, 1.1)
	local from = nil
	local target = onFloor(spot) + V3(0, 0.6, 0)
	local landed = false
	addTelegraph(B, {
		update = function(now)
			if now >= landAt then
				if not landed then
					landed = true
					dirt(B, spot, false)
					playSound(B.def, "Land", spot, 0.6)
				end
				return false
			end
			if now < spitAt then
				seed.Transparency = 1
				return true
			end
			from = from or (fromRoof and (target + V3(0, 46, 0)) or (B.mouthPos or (B.vpos + V3(0, 24, 0))))
			local k = clamp((now - spitAt) / math.max(landAt - spitAt, 0.05), 0, 1)
			local p
			if fromRoof then
				p = from:Lerp(target, k * k)
			else
				local hgt = 8 + flat(target - from).Magnitude * 0.25
				p = from:Lerp(target, k) + V3(0, math.sin(k * math.pi) * hgt, 0)
			end
			seed.CFrame = CFrame.new(p) * CFrame.Angles(k * 9, k * 4, 0)
			seed.Transparency = 0
			return true
		end,
		cleanup = function()
			seed:Destroy()
		end,
	})
end

-- A PETAL BOOMERANG: its dotted loop on the floor (each dot goes as the
-- petal passes it), and the petal itself spinning round it
local function petalFlight(B, k, far, throwAt)
	local a = B.def.Attacks.Petals
	local side = (k % 2 == 1) and 1 or -1
	local origin = B.vpos
	local length = flat(far - origin).Magnitude
	local loop = GardenPlan.petalTime(length, a.Width, a.Speed)
	local N = 26
	local dots = {}
	for i = 1, N do
		dots[i] = newPart("PetalPath", nil, RED, Enum.Material.Neon, 1)
	end
	local petal = newPart("FlyingPetal", nil, B.def.Color, Enum.Material.SmoothPlastic, 1)
	local tip = newPart("FlyingPetal", nil, B.def.TipColor, Enum.Material.SmoothPlastic, 1)
	local whooshed = false
	addTelegraph(B, {
		update = function(now)
			local s = (now - throwAt) / loop
			if s >= 1 or B.action == "Reset" or B.action == "Death" then
				return false
			end
			for i, d in ipairs(dots) do
				local ds = (i - 0.5) / N
				if s < ds then
					local p = GardenPlan.petalPoint(origin, far, side, a.Width, ds)
					d.Size = V3(1.2, 0.1, 1.2)
					d.CFrame = CFrame.new(onFloor(p) + V3(0, 0.12, 0)) * CFrame.Angles(0, math.rad(45), 0)
					d.Transparency = (now < throwAt) and 0.5 or 0.25
				else
					d.Transparency = 1
				end
			end
			if s < 0 then
				petal.Transparency, tip.Transparency = 1, 1
				return true
			end
			if not whooshed then
				whooshed = true
				playSound(B.def, "Petal", B.headPos or origin, 0.8)
			end
			local ground = GardenPlan.petalPoint(origin, far, side, a.Width, s)
			-- it leaves her head, swoops down low for the loop, and flies back up
			local headH = (B.headPos and (B.headPos.Y - origin.Y)) or B.def.HeadHeight
			local up = 1 - clamp(math.min(s, 1 - s) / 0.08, 0, 1)
			local p = onFloor(ground) + V3(0, lerp(2.6, headH, smooth(up)), 0)
			local cf = CFrame.new(p) * CFrame.Angles(0, now * 14, 0)
			petal.Size = V3(4.2, 0.5, 2.4)
			petal.CFrame = cf
			tip.Size = V3(1.4, 0.55, 1.8)
			tip.CFrame = cf * CFrame.new(2.6, 0, 0)
			petal.Transparency, tip.Transparency = 0, 0
			return true
		end,
		cleanup = function()
			for _, d in ipairs(dots) do
				d:Destroy()
			end
			petal:Destroy()
			tip:Destroy()
		end,
	})
end

-- A VINE WHIP line: red on the floor until the vines come, then vines
-- bursting up along it one after another, racing outward, then sinking
local function vineLine(B, tip, start)
	local a = B.def.Attacks.VineWhip
	local origin = onFloor(B.vpos)
	local dir = unitOr(flat(tip - origin), V3(0, 0, 1))
	local len = flat(tip - origin).Magnitude
	local strip = newPart("VineWarning", nil, RED, Enum.Material.Neon, 1)
	local n = math.max(2, math.floor(len / 3))
	local vines = {}
	for i = 1, n do
		vines[i] = { stalk = newPart("Vine", nil, (i % 2 == 0) and GREEN or GREEN_DARK, Enum.Material.SmoothPlastic, 1),
			thorn = newPart("VineThorn", nil, B.def.ThornTip, Enum.Material.SmoothPlastic, 1), dist = 2 + (i - 0.5) / n * (len - 2) }
	end
	local ends = start + len / a.Speed + a.Up + 0.3
	addTelegraph(B, {
		update = function(now)
			if now > ends or B.action == "Reset" then
				return false
			end
			if now < start then
				local blink = (start - now) < 0.25 and (math.floor(now * 12) % 2 == 0)
				local mid = origin + dir * (2 + len / 2) + V3(0, 0.12, 0)
				strip.Size = V3(a.Width + 1, 0.12, len - 2)
				strip.CFrame = CFrame.lookAt(mid, mid + dir)
				strip.Transparency = 0.4
				strip.Color = blink and WHITE or RED
			else
				strip.Transparency = 1
			end
			for i, v in ipairs(vines) do
				local reach = start + v.dist / a.Speed
				local h = 0
				if now >= reach then
					local e = now - reach
					if e < 0.1 then
						h = e / 0.1
					elseif e < a.Up then
						h = 1
					else
						h = 1 - clamp((e - a.Up) / 0.25, 0, 1)
					end
				end
				if h > 0.02 then
					local p = origin + dir * v.dist
					local height = 5.5 * h
					local lean = ((i % 2 == 0) and 1 or -1) * 0.25
					local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, lean) * CFrame.new(0, height / 2, 0)
					v.stalk.Size = V3(1.6, height, 1.6)
					v.stalk.CFrame = cf
					v.stalk.Transparency = 0
					v.thorn.Size = V3(0.5, 0.5, 1.4)
					v.thorn.CFrame = cf * CFrame.new(0, height * 0.2, -0.9)
					v.thorn.Transparency = 0
				else
					v.stalk.Transparency, v.thorn.Transparency = 1, 1
				end
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
			for _, v in ipairs(vines) do
				v.stalk:Destroy()
				v.thorn:Destroy()
			end
		end,
	})
end

-- A POLLEN CLOUD: drifts down off her head onto its red circle, then hangs
-- there, glittering, until it's gone
local function pollenCloud(B, spot, t0)
	local a = B.def.Attacks.Pollen
	local t1 = t0 + a.Tell + a.Drift
	local t2 = t1 + a.Life
	local c = onFloor(spot)
	local disc = newPart("PollenWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local puffs = {}
	for i = 1, 7 do
		puffs[i] = newPart("PollenCloud", nil, POLLEN, Enum.Material.SmoothPlastic, 1)
	end
	local from = nil
	local nextSparkle = 0
	addTelegraph(B, {
		update = function(now)
			if now > t2 + 0.5 or B.action == "Reset" or B.action == "Dormant" then
				return false
			end
			local fadeOut = clamp((now - t2) / 0.5, 0, 1)
			-- the circle: red while it drifts in, a faint yellow once it's there
			placeDisc(disc, c + V3(0, 0.12, 0), a.Radius * 2, 0.1)
			if now < t1 then
				disc.Color = RED
				disc.Transparency = lerp(0.75, 0.4, clamp((now - t0) / (t1 - t0), 0, 1))
			else
				disc.Color = POLLEN
				disc.Transparency = lerp(0.55, 1, fadeOut)
			end
			if now < t0 + a.Tell then
				for _, p in ipairs(puffs) do
					p.Transparency = 1
				end
				return true
			end
			from = from or (B.headPos or (B.vpos + V3(0, 24, 0)))
			local k = clamp((now - t0 - a.Tell) / a.Drift, 0, 1)
			local center = from:Lerp(c + V3(0, a.Height * 0.45, 0), smooth(k))
			local size = lerp(0.35, 1, k)
			for i, p in ipairs(puffs) do
				-- (a ring of puffs round a big one in the middle: a lumpy cloud)
				local ang = i / 6 * math.pi * 2 + now * 0.5
				local ringR = (i == 7) and 0 or a.Radius * 0.55
				local off = V3(math.cos(ang) * ringR, math.sin(now * 1.3 + i) * 0.5 + ((i == 7) and 1.4 or ((i % 2 == 0) and 0.6 or -0.4)), math.sin(ang) * ringR)
				local k2 = (i == 7) and 1.1 or (0.55 + 0.12 * (i % 3))
				p.Size = V3(a.Radius * k2, a.Height * (0.34 + 0.1 * (i % 2)), a.Radius * k2) * size
				p.CFrame = CFrame.new(center + off * size) * CFrame.Angles(0, ang, 0)
				p.Transparency = lerp(0.55, 1, fadeOut)
			end
			if now >= t1 and now >= nextSparkle and fadeOut < 1 then
				nextSparkle = now + 0.5
				burst(center, POLLEN, 5, 6, 0.6, 0.7, true)
			end
			return true
		end,
		cleanup = function()
			disc:Destroy()
			for _, p in ipairs(puffs) do
				p:Destroy()
			end
		end,
	})
end

-- THE FACE STRETCH's lane: it follows her gaze until it locks (slot 1),
-- blinks, and a circle marks where she chomps at the end
local function faceLane(B, a, t0)
	local L = {
		strip = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
		rimL = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
		rimR = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
	}
	local ring = newRing(20, RED, Enum.Material.Neon, 1)
	local lockedAt = nil
	local half = a.Width / 2 + 1
	local reach = num(B.model:GetAttribute("ActN"), a.Reach[1])
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "FaceStretch" or B.actionStart ~= t0 or now > t0 + a.Tell + a.Time + 0.05 then
				return false
			end
			local origin = onFloor(B.vpos)
			local finish = slot(B, 1)
			local locked = finish ~= nil
			local dir = locked and unitOr(flat(finish - origin), B.vfacing) or B.vfacing
			local c0 = origin + dir * 6
			local c1 = locked and onFloor(finish) or (origin + dir * reach)
			local blink = false
			if locked then
				lockedAt = lockedAt or now
				blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
			end
			local sideV = V3(-dir.Z, 0, dir.X)
			local len = flat(c1 - c0).Magnitude
			local mid = (c0 + c1) / 2 + V3(0, 0.12, 0)
			local color = blink and WHITE or RED
			L.strip.Size = V3(half * 2, 0.12, math.max(len, 0.1))
			L.strip.CFrame = CFrame.lookAt(mid, mid + dir)
			L.strip.Transparency = locked and 0.45 or 0.72
			L.strip.Color = color
			for i, rim in ipairs({ L.rimL, L.rimR }) do
				local s = (i == 1) and -1 or 1
				local rm = mid + sideV * s * half + V3(0, 0.02, 0)
				rim.Size = V3(0.5, 0.14, math.max(len, 0.1))
				rim.CFrame = CFrame.lookAt(rm, rm + dir)
				rim.Transparency = locked and 0.1 or 0.5
				rim.Color = color
			end
			placeRing(ring, c1 + V3(0, 0.14, 0), a.Chomp, 0.3, 0.5, locked and 0.15 or 0.5)
			return true
		end,
		cleanup = function()
			L.strip:Destroy()
			L.rimL:Destroy()
			L.rimR:Destroy()
			removeRing(ring)
		end,
	})
end

-- THE ROOT RING: a red ring round her (the soil cracking), then roots
-- bursting up all over inside it
local function rootRing(B, a, t0)
	local ring = newRing(36, RED, Enum.Material.Neon, 1)
	local disc = newPart("RootWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local spikes = {}
	for i = 1, 20 do
		local ang = i * 2.39996
		local r = 3 + math.sqrt((i - 0.5) / 20) * (a.Radius - 3.5)
		spikes[i] = { part = newPart("RootSpike", nil, (i % 2 == 0) and BROWN or SOIL, Enum.Material.SmoothPlastic, 1),
			off = V3(math.cos(ang) * r, 0, math.sin(ang) * r), h = 4 + (i % 3) }
	end
	local hitAt = t0 + a.Tell
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 1 or (B.action ~= "RootRing" and now < hitAt) then
				return false
			end
			local c = onFloor(B.vpos)
			if now < hitAt then
				local k = clamp((now - t0) / a.Tell, 0, 1)
				local blink = k > 0.75 and (math.floor(now * 12) % 2 == 0)
				placeRing(ring, c + V3(0, 0.14, 0), a.Radius, 0.35, 0.6, 0.1)
				for _, p in ipairs(ring.parts) do
					p.Color = blink and WHITE or RED
				end
				placeDisc(disc, c + V3(0, 0.1, 0), a.Radius * 2 * k, 0.1)
				disc.Transparency = 0.7
			else
				placeRing(ring, c, a.Radius, 0.05, 0.1, 1)
				disc.Transparency = 1
			end
			for _, s in ipairs(spikes) do
				local e = now - hitAt
				local h = 0
				if e >= 0 then
					h = (e < 0.1) and (e / 0.1) or ((e < 0.6) and 1 or (1 - clamp((e - 0.6) / 0.3, 0, 1)))
				end
				if h > 0.02 then
					local height = s.h * h
					s.part.Size = V3(1.2, height, 1.2)
					s.part.CFrame = CFrame.new(c + s.off + V3(0, height / 2, 0)) * CFrame.Angles(0.2, s.off.X, 0.15)
					s.part.Transparency = 0
				else
					s.part.Transparency = 1
				end
			end
			return true
		end,
		cleanup = function()
			removeRing(ring)
			disc:Destroy()
			for _, s in ipairs(spikes) do
				s.part:Destroy()
			end
		end,
	})
end

-- A THORN RING: brambles and red thorns in a ring that spreads out across
-- the garden - its radius is exactly the server's (BossService's stepWaves)
local function thornRing(B, t0k)
	local a = B.def.Attacks.ThornRing
	local band = newRing(44, B.def.ThornColor, Enum.Material.SmoothPlastic, 1)
	local tips = newRing(44, B.def.ThornTip, Enum.Material.SmoothPlastic, 1)
	local life = a.Reach / a.Speed
	local origin = onFloor(B.vpos)
	local sounded = false
	for _, p in ipairs(band.parts) do
		p.Name = "ThornRing"
	end
	for _, p in ipairs(tips.parts) do
		p.Name = "ThornRing"
	end
	addTelegraph(B, {
		update = function(now)
			local age = now - t0k
			if age > life or B.action == "Reset" then
				return false
			end
			if age < 0 then
				placeRing(band, origin, 4, 0.05, 1, 1)
				placeRing(tips, origin, 4, 0.05, 1, 1)
				return true
			end
			if not sounded then
				sounded = true
				playSound(B.def, "Thorn", origin, 0.8)
			end
			local r = 4 + a.Speed * age
			local fadeOut = clamp((age - (life - 0.3)) / 0.3, 0, 1)
			local h = a.Height * (0.85 + 0.15 * math.sin(now * 25))
			placeRing(band, origin + V3(0, 0.05, 0), r, h * 0.6, a.Thickness, fadeOut, true)
			placeRing(tips, origin + V3(0, h * 0.5, 0), r, h * 0.5, a.Thickness * 0.35, fadeOut, true)
			return true
		end,
		cleanup = function()
			removeRing(band)
			removeRing(tips)
		end,
	})
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- ASLEEP: a closed bud, nodding gently
function Poses.Dormant(B, t, P)
	P.bloom = 0
	P.eyes = 0
	P.headPitch = -0.35 + 0.05 * math.sin(os.clock() * 1.1)
	P.leafL, P.leafR = -0.2, -0.2
	local _ = B
	local _ = t
end

-- WAKING UP: the bud opens, the petals unfurl, a big stretch, a smile
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	P.bloom = smooth(t / (W * 0.55))
	P.eyes = (t > W * 0.35) and 1 or 0
	local stretchK = math.sin(clamp((t - W * 0.3) / (W * 0.45), 0, 1) * math.pi)
	P.leafL, P.leafR = lerp(-0.2, 1, stretchK), lerp(-0.2, 1, stretchK)
	P.headPitch = lerp(-0.35, 0.25, smooth(t / (W * 0.5))) - 0.25 * smooth((t - W * 0.7) / (W * 0.3))
	P.mouthShape = (t > W * 0.3 and t < W * 0.55) and "o" or "smile"
	P.mouth = 1
	P.happy = (t > W * 0.55 and t < W * 0.8) and 1 or 0
end

-- EVERYONE'S GONE: a little wave... and she closes up into a bud again
function Poses.Reset(B, t, P)
	P.bloom = 1 - smooth((t - 0.6) / 1.2)
	P.eyes = 1 - smooth((t - 0.4) / 0.6)
	P.leafR = (t < 0.8) and (0.6 + 0.3 * math.sin(t * 14)) or -0.2
	P.headPitch = lerp(0, -0.35, smooth((t - 0.6) / 1.2))
	local _ = B
end

-- SEED SPIT: cheeks puff up... then spit, spit, spit
function Poses.SeedSpit(B, t, P)
	local a = B.def.Attacks.SeedSpit
	local count = num(B.model:GetAttribute("ActN"), 3)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.puff = k
		P.lean = -0.25 * k
		P.headPitch = 0.15 * k
		P.mouthShape = "smile"
		P.mouth = 0
		return
	end
	local e = t - a.Tell
	local k = math.floor(e / a.Gap)
	if k < count then
		local w = (e - k * a.Gap) / a.Gap
		P.puff = 1 - k / count
		P.mouthShape = "o"
		P.mouth = 1 - w
		P.lean = 0.15 * (1 - w)
		P.headPitch = 0.3
		P.snap = true
	else
		P.mouthShape = "smile"
	end
end

-- PETAL BOOMERANG: her leaves fling petals, one side then the other
function Poses.Petals(B, t, P)
	local a = B.def.Attacks.Petals
	local count = num(B.model:GetAttribute("ActN"), 2)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.leafL, P.leafR = 0.9 * k, 0.9 * k
		P.lean = -0.1 * k
		P.mouthShape = "grin"
		P.mouth = 0.3
		return
	end
	local e = t - a.Tell
	local k = math.floor(e / a.Gap)
	if k < count then
		local left = (k % 2 == 0)
		local w = (e - k * a.Gap) / a.Gap
		local fling = 1 - 1.4 * math.sin(math.min(w, 1) * math.pi)
		if left then
			P.leafL, P.leafR = fling, 0.6
		else
			P.leafL, P.leafR = 0.6, fling
		end
		P.spin = (left and -1 or 1) * 0.3 * math.sin(w * math.pi)
		P.snap = true
	end
	P.mouthShape = "grin"
	P.mouth = 0.4
end

-- VINE WHIP: leaves up high... SLAP the ground
function Poses.VineWhip(B, t, P)
	local a = B.def.Attacks.VineWhip
	local slapAt = a.Tell * 0.7
	if t < slapAt then
		local k = smooth(t / slapAt)
		P.leafL, P.leafR = k, k
		P.lean = -0.15 * k
		P.headPitch = 0.1
		P.mouthShape = "grin"
		P.mouth = 0.5
	elseif t < a.Tell + 0.8 then
		P.leafL, P.leafR = -1, -1
		P.lean = 0.35
		P.headPitch = -0.25
		P.mouthShape = "wide"
		P.mouth = 0.6
		P.snap = t < slapAt + 0.12
	end
end

-- POLLEN CLOUD: she shakes her head, then puffs out pollen
function Poses.Pollen(B, t, P)
	local a = B.def.Attacks.Pollen
	if t < a.Tell then
		P.sway = math.sin(t * 28) * 2.2
		P.calm = false
		P.eyes = 0.2
		P.mouthShape = "smile"
		P.leafL, P.leafR = 0.3, 0.3
	elseif t < a.Tell + 0.6 then
		P.mouthShape = "o"
		P.mouth = 1
		P.puff = 0.6
		P.lean = 0.2
	end
end

-- FACE STRETCH: head back, a wicked grin... then her head shoots out down
-- the lane (applyPose puts it exactly on the server's path), CHOMPS, and
-- lies there dizzy
function Poses.FaceStretch(B, t, P)
	local a = B.def.Attacks.FaceStretch
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.lean = -0.45 * k
		P.headPitch = 0.2 * k
		P.mouthShape = "grin"
		P.mouth = 0.6 * k
		P.leafL, P.leafR = 0.5 * k, 0.5 * k
		return
	end
	local e = t - a.Tell
	if e < a.Time then
		P.mouthShape = "wide"
		P.mouth = 1
		P.snap = true
	elseif e < a.Time + a.Droop then
		P.mouthShape = (e < a.Time + 0.25) and "chomp" or "wide"
		P.mouth = 0.5
		P.eyes = 1
		P.dizzy = 1
		P.leafL, P.leafR = -0.4, -0.4
	else
		P.mouthShape = "o"
		P.mouth = 0.4
	end
end

-- ROOT RING: she shudders, her roots wriggling
function Poses.RootRing(B, t, P)
	local a = B.def.Attacks.RootRing
	if t < a.Tell then
		P.shake = 0.35 * (t / a.Tell)
		P.eyes = 0.15
		P.mouthShape = "grin"
		P.mouth = 0.3
		P.leafL, P.leafR = 0.4, 0.4
	elseif t < a.Tell + 0.5 then
		P.mouthShape = "wide"
		P.mouth = 0.8
		P.leafL, P.leafR = 1, 1
		P.headPitch = 0.3
	end
end

-- SUNBATHE: face up to the sun, eyes shut, humming - free hits!
function Poses.Sunbathe(B, t, P)
	P.headPitch = 0.6
	P.happy = 1
	P.mouthShape = "o"
	P.mouth = 0.3 + 0.2 * math.sin(t * 6)
	P.leafL, P.leafR = 0.5 + 0.2 * math.sin(t * 3), 0.5 + 0.2 * math.sin(t * 3 + 1)
	P.sway = math.sin(t * 3) * 1.5
	local _ = B
end

-- THORN RING: her head spins like a saw, flinging rings of thorns
function Poses.ThornRing(B, t, P)
	local a = B.def.Attacks.ThornRing
	local rings = num(B.model:GetAttribute("ActN"), 3)
	local stop = a.Tell + (rings - 1) * a.Gap + 0.4
	if t < stop then
		local spinUp = clamp(t / a.Tell, 0, 1)
		P.spin = (t * t * 4 + t * 10 * spinUp)
		P.mouthShape = "grin"
		P.mouth = 0.5
		P.leafL, P.leafR = 0.8, 0.8
	end
	local _ = B
end

-- SEED RAIN: a shriek at the glass roof
function Poses.SeedRain(B, t, P)
	local a = B.def.Attacks.SeedRain
	if t < a.Tell + 0.6 then
		local k = smooth(t / (a.Tell * 0.5))
		P.headPitch = 0.75 * k
		P.mouthShape = "wide"
		P.mouth = k
		P.shake = 0.25 * k
		P.leafL, P.leafR = k, k
	end
	local _ = B
end

-- ROUND 2: she shakes with fury and turns wicked
function Poses.Break(B, t, P)
	local T = B.def.BreakTime
	if t < T * 0.35 then
		P.shake = 0.6
		P.eyes = 0.2
		P.leafL, P.leafR = 0.9, 0.9
		P.mouthShape = "chomp"
	else
		P.mouthShape = "grin"
		P.mouth = 0.8 + 0.2 * math.sin(t * 20)
		P.headPitch = -0.15
		P.leafL, P.leafR = 1, 1
		P.shake = 0.15
	end
end

-- THE END: she wilts - her petals drop off one by one, her head bows right
-- down to the floor... and she pops into pixels
function Poses.Death(B, t, P)
	P.lost = math.floor(clamp((t - 0.4) / 2.2, 0, 1) * PETALS)
	P.droop = clamp((t - 0.6) / 1.4, 0, 1)
	P.eyes = (t < 1.5) and 1 or 0
	P.mouthShape = "o"
	P.mouth = 0.6
	P.leafL, P.leafR = -0.8, -0.8
	P.fade = clamp((t - 3.2) / 0.7, 0, 1)
	local _ = B
end

----------------------------------------------------------------------
-- Starts and slots: the sounds, bursts and warnings of each move
----------------------------------------------------------------------
function Starts.Wake(B, t0)
	local W = B.def.WakeTime
	at(B, t0 + W * 0.1 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W * 0.35, function()
		burst((B.headPos or B.vpos) + V3(0, 1, 0), B.def.Color, 20, 18, 1.2, 0.8, true)
	end)
	at(B, t0 + W * 0.6, function()
		shout(B.body.anchor, "HELLO, SWEETIE~!", 1.4, B.def.TipColor)
	end)
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		shout(B.body.anchor, "AWW... LEAVING SO SOON?", 1.4, WHITE)
	end)
end

function Starts.SeedSpit(B, t0)
	local a = B.def.Attacks.SeedSpit
	local count = num(B.model:GetAttribute("ActN"), 3)
	for k = 1, count do
		at(B, t0 + a.Tell + (k - 1) * a.Gap, function()
			playSound(B.def, "Spit", B.headPos or B.vpos, 0.7)
		end)
	end
end

function SlotSpawns.SeedSpit(B, i, spot, t0)
	local a = B.def.Attacks.SeedSpit
	local spitAt = t0 + a.Tell + (i - 1) * a.Gap
	seedFlight(B, spot, spitAt, spitAt + a.Flight, a.Radius, false)
end

function SlotSpawns.Petals(B, i, far, t0)
	local a = B.def.Attacks.Petals
	petalFlight(B, i, far, t0 + a.Tell + (i - 1) * a.Gap)
end

function Starts.VineWhip(B, t0)
	local a = B.def.Attacks.VineWhip
	at(B, t0 + a.Tell * 0.7, function()
		for _, side in ipairs({ -1, 1 }) do
			local r = V3(-B.vfacing.Z, 0, B.vfacing.X)
			dirt(B, B.vpos + r * side * 7 + B.vfacing * 6, true)
		end
		kick(B.vpos, 36, 0.6, -2)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Whip", B.vpos, 1)
	end)
end

function SlotSpawns.VineWhip(B, i, tip, t0)
	local _ = i
	vineLine(B, tip, t0 + B.def.Attacks.VineWhip.Tell)
end

function Starts.Pollen(B, t0)
	local a = B.def.Attacks.Pollen
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Pollen", B.headPos or B.vpos, 0.9)
		burst((B.headPos or B.vpos) + V3(0, 1, 0), POLLEN, 24, 18, 1, 0.9, true)
	end)
end

function SlotSpawns.Pollen(B, i, spot, t0)
	local _ = i
	pollenCloud(B, spot, t0)
end

function Starts.FaceStretch(B, t0)
	local a = B.def.Attacks.FaceStretch
	faceLane(B, a, t0)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Stretch", B.headPos or B.vpos, 1)
	end)
	at(B, t0 + a.Tell + a.Time, function()
		local finish = slot(B, 1) or B.vpos
		playSound(B.def, "Bite", finish, 1)
		shout(B.body.anchor, "CHOMP!", 0.8, YELLOW)
		dirt(B, finish, true)
		kick(finish, 30, 0.8, -3)
	end)
end

function Starts.RootRing(B, t0)
	local a = B.def.Attacks.RootRing
	rootRing(B, a, t0)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Root", B.vpos, 1)
		dirt(B, B.vpos, true)
		kick(B.vpos, a.Radius + 20, 0.9, -3)
	end)
end

function Starts.Sunbathe(B, t0)
	at(B, t0 + 0.15, function()
		shout(B.body.anchor, "LA LA LA~", 1.4, B.def.TipColor)
		playSound(B.def, "Giggle", B.headPos or B.vpos, 0.8)
	end)
end

function Starts.ThornRing(B, t0)
	local a = B.def.Attacks.ThornRing
	local rings = num(B.model:GetAttribute("ActN"), 3)
	for k = 1, rings do
		thornRing(B, t0 + a.Tell + (k - 1) * a.Gap)
	end
end

function Starts.SeedRain(B, t0)
	at(B, t0 + 0.1, function()
		playSound(B.def, "Rain", B.headPos or B.vpos, 1)
	end)
end

function SlotSpawns.SeedRain(B, i, spot, t0)
	local a = B.def.Attacks.SeedRain
	local landAt = t0 + a.Tell + a.Fall + (i - 1) / a.Drops * a.Stagger
	seedFlight(B, spot, landAt - a.Fall * 0.7, landAt, a.Radius, true)
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		B.thornsFrom = t0 + def.BreakTime * 0.35
		playSound(def, "Break", B.vpos, 1)
		playSound(def, "Spread", B.vpos, 0.8)
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, def.EvilTip or RED)
		burst((B.headPos or B.vpos) + V3(0, 2, 0), def.EvilColor, 40, 30, 1.8, 0.9, true)
		kick(B.vpos, def.BreakReach + 20, 1.4, -5)
		if B.here then
			pcall(bigText, "YOU TRAMPLED MY FLOWERS!", { color = def.EvilTip, sub = "ROUND 2", size = 52, hold = 1.3 })
		end
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.2, function()
		playSound(def, "Death", B.vpos, 1)
	end)
	-- her petals fluttering down as they drop off
	for k = 1, PETALS do
		at(B, t0 + 0.4 + (k - 0.5) / PETALS * 2.2, function()
			burst((B.headPos or B.vpos) + V3(0, 1, 0), (k % 2 == 0) and def.Color or def.TipColor, 3, 6, 1.4, 1.2, false)
		end)
	end
	at(B, t0 + 3.2, function()
		for k = 1, 4 do
			burst((B.headPos or B.vpos) + V3(0, k * 1.5, 0), (k % 2 == 0) and def.Color or def.FaceColor, 14, 14, 1.2, 0.8, true)
		end
	end)
end

----------------------------------------------------------------------
-- Every frame: the flytraps, the brambles, the butterflies, "HIT HER!"
----------------------------------------------------------------------
-- A FLYTRAP (the server's Workspace.PetalinaProps): a stalk and two leaves
-- on the ground, a green head with pink jaws and white teeth. It sprouts,
-- bobs, turns to whoever it's about to bite, gapes (a red circle where it
-- will snap), lunges and snaps; popped, it bursts; left alone, it wilts.
local function makeTrap(B, inst)
	local def = B.def
	local f = def.Flytrap
	local hit = inst.PrimaryPart or inst:FindFirstChild("Hit")
	if not hit then
		return nil
	end
	local rec = { kind = "Flytrap", parts = {} }
	local function add(name, color)
		local p = newPart(name, nil, color, Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	local stalk = add("TrapStem", GREEN_DARK)
	local leaves = { add("TrapLeaf", GREEN), add("TrapLeaf", GREEN) }
	local head = add("TrapHead", GREEN)
	local jaws = { add("TrapJaw", PINK), add("TrapJaw", PINK) }
	local teeth = {}
	for i = 1, 4 do
		teeth[i] = add("TrapTooth", WHITE)
	end
	local warnDisc = newPart("TrapWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	table.insert(rec.parts, warnDisc)
	local pos = onFloor(hit.Position - V3(0, hit.Size.Y / 2, 0))
	local born = num(inst:GetAttribute("Born"), serverNow())
	local grow = num(inst:GetAttribute("Grow"), f.Grow)
	local lastBite = 0
	local sprouted = false
	local turned = V3(0, 0, 1)
	function rec.update(now)
		local endKind = inst:GetAttribute("EndKind")
		local endAge = endKind and (now - num(inst:GetAttribute("EndAt"), now)) or 0
		if inst.Parent == nil and not endKind then
			return false
		end
		if endKind then
			if endKind == "Broken" and not rec.popped then
				rec.popped = true
				burst(pos + V3(0, 2.5, 0), GREEN, 16, 16, 1.1, 0.6, true)
				burst(pos + V3(0, 2.5, 0), PINK, 8, 12, 0.9, 0.5, true)
			end
			if endKind ~= "Wither" or endAge > 0.7 then
				return false
			end
		end
		local k = clamp((now - born) / math.max(grow, 0.05), 0, 1)
		if k <= 0 then
			for _, p in ipairs(rec.parts) do
				p.Transparency = 1
			end
			return true
		end
		if not sprouted then
			sprouted = true
			dirt(B, pos, false)
			playSound(def, "Sprout", pos, 0.6)
		end
		local wilt = (endKind == "Wither") and clamp(endAge / 0.6, 0, 1) or 0
		local s = smooth(k) * (1 - 0.6 * wilt) * 1.35 -- (a little bigger than you'd think: easy to spot)
		-- which way it faces: at what it's biting, or at the nearest player
		local biteAt, biteWarn = inst:GetAttribute("BiteAt"), inst:GetAttribute("BiteWarn")
		local biteDir = inst:GetAttribute("BiteDir")
		local want = typeof(biteDir) == "Vector3" and biteDir or nil
		if not want then
			local lp = Players.LocalPlayer
			local root = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
			want = root and unitOr(flat(root.Position - pos), turned) or turned
		end
		turned = unitOr(turned:Lerp(want, 0.2), want)
		-- gaping, snapping
		local gape, lunge = 0.25 + 0.1 * math.sin(now * 3), 0
		if type(biteAt) == "number" and type(biteWarn) == "number" then
			if now >= biteWarn and now < biteAt then
				gape = lerp(0.3, 1, (now - biteWarn) / math.max(biteAt - biteWarn, 0.05))
			elseif now >= biteAt and now < biteAt + 0.35 then
				local e = now - biteAt
				gape = 0
				lunge = (e < 0.12) and (e / 0.12) or (1 - (e - 0.12) / 0.23)
				if lastBite ~= biteAt then
					lastBite = biteAt
					playSound(def, "Chomp", pos, 0.7)
				end
			end
			if now >= biteWarn and now < biteAt then
				local spot = pos + (typeof(biteDir) == "Vector3" and biteDir or turned) * f.Lunge
				placeDisc(warnDisc, onFloor(spot) + V3(0, 0.13, 0), f.Reach * 2 * gape, 0.1)
				warnDisc.Transparency = 0.45
			else
				warnDisc.Transparency = 1
			end
		else
			warnDisc.Transparency = 1
		end
		local color = (wilt > 0) and BROWN or GREEN
		local frame = CFrame.lookAt(pos, pos + turned)
		local top = frame * CFrame.new(0, 3.2 * s, -lunge * f.Lunge)
		stretch(stalk, pos, top.Position, 0.6 * s, 0.6 * s, V3(0, 0, 1))
		stalk.Color = (wilt > 0) and BROWN or GREEN_DARK
		for i, lf in ipairs(leaves) do
			local side = (i == 1) and -1 or 1
			lf.Size = V3(1.6, 0.25, 2.6) * math.max(s, 0.05)
			lf.CFrame = frame * CFrame.new(side * 1.1 * s, 0.2, 0) * CFrame.Angles(0, side * 0.6, side * 0.3)
			lf.Color = color
		end
		head.Size = V3(1.8, 1, 1.6) * math.max(s, 0.05)
		head.CFrame = top
		head.Color = color
		-- the jaws: hinged at the back of its head, opening upward and downward
		for i, jw in ipairs(jaws) do
			local side = (i == 1) and 1 or -1
			local hinge = top * CFrame.new(0, side * 0.35 * s, 0.5 * s) * CFrame.Angles(side * gape * 0.9, 0, 0)
			jw.Size = V3(2, 0.5, 2.2) * math.max(s, 0.05)
			jw.CFrame = hinge * CFrame.new(0, 0, -1.1 * s)
			jw.Color = (wilt > 0) and BROWN or PINK
			for j = 1, 2 do
				local tooth = teeth[(i - 1) * 2 + j]
				tooth.Size = V3(0.3, 0.6, 0.3) * math.max(s, 0.05)
				tooth.CFrame = hinge * CFrame.new((j - 1.5) * 1.1 * s, -side * 0.4 * s, -2 * s)
			end
		end
		for _, p in ipairs(rec.parts) do
			if p ~= warnDisc then
				p.Transparency = 0
			end
		end
		return true
	end
	function rec.cleanup()
		for _, p in ipairs(rec.parts) do
			p:Destroy()
		end
	end
	return rec
end

local function stepTraps(B, now)
	B.traps = B.traps or {}
	B.trapOf = B.trapOf or {}
	local folder = Workspace:FindFirstChild("PetalinaProps")
	if folder then
		for _, inst in ipairs(folder:GetChildren()) do
			if B.trapOf[inst] == nil and inst:GetAttribute("Floor") == B.floor and inst:GetAttribute("Kind") == "Flytrap" then
				local rec = makeTrap(B, inst)
				B.trapOf[inst] = rec or false
				if rec then
					table.insert(B.traps, rec)
				end
			end
		end
	end
	for i = #B.traps, 1, -1 do
		local rec = B.traps[i]
		local ok, keep = pcall(rec.update, now)
		if not ok and not B.warnedTrap then
			B.warnedTrap = true
			warn("[BossClient] Petalina's flytrap failed: " .. tostring(keep))
		end
		if not ok or not keep then
			pcall(rec.cleanup)
			table.remove(B.traps, i)
		end
	end
	for inst, rec in pairs(B.trapOf) do
		if inst.Parent == nil and (rec == false or not table.find(B.traps, rec)) then
			B.trapOf[inst] = nil
		end
	end
end

-- ROUND 2's BRAMBLES (GreenhouseBuilder's "GardenThorn" clumps, hidden in
-- the soil of the flower beds): each grows up out of the soil at its own
-- moment once she turns evil (nearest her first), and sinks back when the
-- fight's over. Only on your screen; the server knows where the beds are.
local function thornsOf(B)
	if not B.thorns then
		local list = {}
		for _, c in ipairs(CollectionService:GetTagged("GardenThorn")) do
			if c:IsA("Model") and c:GetAttribute("Floor") == B.floor and c.PrimaryPart then
				table.insert(list, { model = c, base = c:GetPivot(), up = num(c:GetAttribute("Up"), 4.5), delay = num(c:GetAttribute("Delay"), 0), k = 0 })
			end
		end
		if #list == 0 then
			return list -- (the arena isn't here yet: look again next time)
		end
		B.thorns = list
	end
	return B.thorns
end

local function stepThorns(B, now)
	local list = thornsOf(B)
	local grow = B.phase2Look and B.stateNow ~= "Dead" and B.stateNow ~= "Dormant" and B.stateNow ~= "Resetting"
	if grow then
		B.thornsGoneAt = nil
	elseif not B.thornsGoneAt then
		B.thornsGoneAt = now
	end
	for _, th in ipairs(list) do
		local want
		if grow then
			want = smooth((now - (B.thornsFrom or now) - th.delay) / 0.35)
		else
			want = math.min(th.k, 1 - smooth((now - B.thornsGoneAt - th.delay * 0.3) / 0.5))
		end
		want = clamp(want, 0, 1)
		if math.abs(want - th.k) > 0.005 or (want == 0 and th.k ~= 0) or (want == 1 and th.k ~= 1) then
			th.k = want
			th.model:PivotTo(th.base + V3(0, th.up * want, 0))
		end
	end
end

-- THE BUTTERFLIES: flitting in lazy loops over the beds, wings flapping.
-- In round 2 they flee up under the glass roof.
local function fliesOf(B)
	if not B.flies then
		local list = {}
		for _, f in ipairs(CollectionService:GetTagged("GardenButterfly")) do
			if f:IsA("Model") and f:GetAttribute("Floor") == B.floor and f.PrimaryPart then
				local rec = { model = f, body = f.PrimaryPart, wings = {}, base = f.PrimaryPart.Position, seed = num(f:GetAttribute("Index"), 1) }
				for _, p in ipairs(f:GetChildren()) do
					if p:IsA("BasePart") and p ~= f.PrimaryPart then
						table.insert(rec.wings, p)
					end
				end
				table.insert(list, rec)
			end
		end
		if #list == 0 then
			return list
		end
		B.flies = list
	end
	return B.flies
end

local function stepFlies(B, now, dt)
	local flee = B.phase2Look and (B.stateNow == "Fighting" or B.stateNow == "Transition")
	B.fleeK = smoothNum(B, "fleeS", flee and 1 or 0, 1.5, dt)
	for _, fl in ipairs(fliesOf(B)) do
		local s = fl.seed
		local w = 0.5 + 0.07 * s
		local p = fl.base + V3(math.cos(now * w + s) * 5, math.sin(now * 2 * w + s) * 1.2, math.sin(now * w + s) * 5)
		p = p + V3(0, 26 * B.fleeK, 0)
		local vel = V3(-math.sin(now * w + s), 0, math.cos(now * w + s))
		local cf = CFrame.lookAt(p, p + vel)
		fl.body.CFrame = cf
		local flap = math.sin(now * 18 + s) * 0.8
		for i, wing in ipairs(fl.wings) do
			local side = (i == 1) and -1 or 1
			wing.CFrame = cf * CFrame.Angles(0, 0, side * flap) * CFrame.new(side * 0.55, 0, 0)
		end
	end
end

-- "HIT HER!" over her while she's open: her head down on the floor after a
-- Face Stretch, or sunbathing
local function openNow(B, now)
	local t0 = B.actionStart
	if not t0 then
		return nil
	end
	local A = B.def.Attacks
	local t = now - t0
	if B.action == "Sunbathe" then
		return "HIT HER!"
	end
	if B.action == "FaceStretch" and t > A.FaceStretch.Tell + A.FaceStretch.Time + 0.1 and t < A.FaceStretch.Tell + A.FaceStretch.Time + A.FaceStretch.Droop then
		return "HIT HER!"
	end
	return nil
end

local function stepHint(B, showIt)
	local now = serverNow()
	local want = showIt and openNow(B, now) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(now * 6) % 2 == 0) and 0 or 0.25
			if B.hintGui and B.headPos then
				B.hintAnchor.CFrame = CFrame.new(B.headPos + V3(0, 7, 0))
			end
		end
		return
	end
	B.hintText = want
	if B.hintGui then
		B.hintGui:Destroy()
		B.hintGui, B.hintLabel = nil, nil
	end
	if want then
		B.hintAnchor = B.hintAnchor or newPart("HintSpot", nil, WHITE, Enum.Material.SmoothPlastic, 1, B.body.folder)
		B.hintAnchor.Size = V3(0.2, 0.2, 0.2)
		B.hintAnchor.CFrame = CFrame.new((B.headPos or B.vpos) + V3(0, 7, 0))
		local bb = Instance.new("BillboardGui")
		bb.Name = "PetalinaHint"
		bb.Size = UDim2.new(0, 300, 0, 30)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.hintAnchor
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
		label.Text = want
		label.Parent = bb
		bb.Parent = B.body.folder
		B.hintGui, B.hintLabel = bb, label
	end
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- what her moves are made of: soil and leaves
function Body.fx(def)
	local _ = def
	return { color = SOIL, deep = SOIL_DARK, rock = SOIL_DARK, material = Enum.Material.SmoothPlastic, solid = true }
end

-- joined while she'd already turned evil: the brambles are already up
function Body.lateBreak(B)
	B.phase2Look = true
	B.thornsFrom = serverNow() - 5
end

-- a fresh start (a reset, a new fight): sweet again, the brambles sink away
function Body.calm(B, name)
	local _ = name
	B.phase2Look = false
end

-- you can't walk through her stem (but you can get right up to it)
function Body.pushOut(B, P, here, awake, state)
	local _ = P
	local _ = state
	if not (here and awake) then
		return
	end
	local lp = Players.LocalPlayer
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local offset = flat(hrp.Position - B.vpos)
		local minimum = B.def.StemRadius + 1.2
		if offset.Magnitude < minimum then
			local outDir = offset.Magnitude > 0.05 and offset.Unit or B.vfacing
			local target = B.vpos + outDir * minimum
			hrp.CFrame = CFrame.new(V3(target.X, hrp.Position.Y, target.Z)) * (hrp.CFrame - hrp.Position)
		end
	end
end

-- every frame, whatever she's doing: the flytraps, the brambles, the
-- butterflies, the hint
function Body.senses(B, dt, here, awake, state)
	B.here = here
	B.stateNow = state
	local now = serverNow()
	local function run(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.warned = B.warned or {}
			if not B.warned[name] then
				B.warned[name] = true
				warn("[BossClient] Petalina's " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	run("flytraps", stepTraps, B, now)
	run("brambles", stepThorns, B, now)
	if here then
		run("butterflies", stepFlies, B, now, dt)
	end
	run("hint", stepHint, B, here and awake)
end

return Body
