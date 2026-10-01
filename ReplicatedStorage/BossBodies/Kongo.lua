--[[
	Kongo  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Kongo")

	How Kongo, the Jungle Brawler (floor 7's boss, Config.Bosses[7]) looks on
	your screen: a big chunky 8-bit silverback gorilla nearly three times your
	height - charcoal fur with a silver saddle on his back, a pale grey face
	with a big muzzle, a heavy brow, a tuft of hair on top, huge arms that hang
	down to his knuckles, and a gold chain round his neck with a big banana
	medallion. In round 2 his face goes angry red.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Kongo.lua, where each move is explained):
	  * Poses[move]   his body t seconds into a move: winding his arm round,
	                  slapping the ground, curled into a ball, spinning like a
	                  helicopter, heaving barrels, pounding his chest...
	  * Starts[move]  the move's sounds, dust and camera kicks, and its
	                  warnings on the floor, all timed on the server's clock
	  * SlotSpawns    warnings for the spots the server fills in as a move goes:
	                  the Giant Punch's lane locking, each barrel's lane, each
	                  TNT's red circle, the roll's path, the grab
	  * Body.glide    exactly where he is during a lunge or a roll (the
	                  server's own line), so what you see is what hits you
	  * Body.senses   every frame: the monkey villagers (they bounce along,
	                  cheer when he shows off, and cover their eyes when he
	                  loses), the tiki torches (they flare up in round 2), and
	                  the "HIT HIM!" over him when he's open
	  * the moments every boss has: asleep sitting in the clearing, waking up
	    (a yawn, a jump, a chest pound and a roar), sitting back down when
	    everyone leaves, going bananas at half health, and falling flat on his
	    back at the end

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: crouch, lean, twist, headPitch, sit,
	fall, rHand / lHand (where his hands are, in his chest's space, in units
	of his size), ball (curled up) and ballSpin, spinA (a helicopter spin),
	holding ("Barrel" / "TNT" over his head), roar (mouth wide), stars (dizzy).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}
-- (which arena copy is this boss's: ReplicatedStorage/Arenas)
local Arenas = require(game:GetService("ReplicatedStorage"):WaitForChild("Arenas"))

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

-- colours that aren't in his Config
local RED = RGB(228, 59, 68)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local YELLOW = RGB(254, 231, 97)
local ORANGE = RGB(247, 118, 34)
local WOOD = RGB(184, 111, 80)
local WOOD_DARK = RGB(115, 62, 57)
local DIRT = RGB(194, 133, 105)
local DIRT_DARK = RGB(184, 111, 80)
local PIXEL_FONT = nil
pcall(function()
	PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

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

-- a number for this round: a { round 1, round 2 } pair, or just a number
local function perRound(B, v)
	if type(v) == "table" then
		local phase = num(B.model:GetAttribute("Phase"), 1)
		return v[math.min(phase, #v)]
	end
	return v
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

-- where the elbow (or knee) goes for a limb from `a` to `c` made of two
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

-- the same for a position (a hand, in his chest's space)
local function smoothVec(B, key, want, rate, dt): Vector3
	local old = B[key]
	if typeof(old) ~= "Vector3" then
		B[key] = want
		return want
	end
	local v = old:Lerp(want, 1 - math.exp(-dt * rate))
	B[key] = v
	return v
end

-- the Giant Punch's lane length while he's still winding (before it locks):
-- it grows the longer he winds, the server's own sum
local function windReach(a, e)
	local k = clamp((e - a.Wind[1] * 0.5) / math.max(a.Wind[2] - a.Wind[1] * 0.5, 0.01), 0, 1)
	return lerp(a.Reach[1], a.Reach[2], k)
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {}, fur = {}, skin = {} }
	local fur, deep, skin = def.Color, def.DeepColor, def.SkinColor or RGB(232, 183, 150)
	local function add(name, color, material, kind, shape)
		local p = newPart(name, shape, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, p)
		if kind == "fur" then
			table.insert(body.fur, { part = p, color = color })
		elseif kind == "skin" then
			table.insert(body.skin, { part = p, color = color })
		end
		return p
	end
	-- legs: short and thick, with big tan feet
	body.thighs, body.shins, body.feet = {}, {}, {}
	for i = 1, 2 do
		body.thighs[i] = add("Thigh", fur, nil, "fur")
		body.shins[i] = add("Shin", fur, nil, "fur")
		body.feet[i] = add("Foot", skin, nil, "skin")
	end
	-- the middle: hips, a round belly, a huge chest, broad shoulders
	body.hips = add("Hips", fur, nil, "fur")
	body.belly = add("Belly", fur, nil, "fur")
	body.chest = add("Chest", fur, nil, "fur")
	body.shoulders = { add("Shoulder", fur, nil, "fur"), add("Shoulder", fur, nil, "fur") }
	body.back = add("BackFur", def.BackColor or deep, nil, "fur") -- (a silverback: the silver saddle on his back)
	-- THE CHAIN: a gold collar, two strands in a V, and a banana medallion
	-- (the pieces keep their old "Tie" names)
	body.knot = add("TieKnot", def.TieColor or RED)
	body.tie = add("Tie", def.TieColor or RED)
	body.tieTip = add("TieTip", def.TieColor or RED)
	body.letter = { add("TieLetter", def.LetterColor or YELLOW), add("TieLetter", def.LetterColor or YELLOW), add("TieLetter", def.LetterColor or YELLOW) }
	-- arms: long and thick, with big tan hands
	body.upperArms, body.foreArms, body.hands = {}, {}, {}
	for i = 1, 2 do
		body.upperArms[i] = add("UpperArm", fur, nil, "fur")
		body.foreArms[i] = add("ForeArm", fur, nil, "fur")
		body.hands[i] = add("Hand", skin, nil, "skin")
	end
	-- the head: fur, a grey face and big muzzle, a heavy brow, a tuft of hair
	body.head = add("Head", fur, nil, "fur")
	body.tuft = { add("HairTuft", fur, nil, "fur"), add("HairTuft", deep, nil, "fur"), add("HairTuft", fur, nil, "fur") }
	body.face = add("Face", skin, nil, "skin")
	body.muzzle = add("Muzzle", skin, nil, "skin")
	body.brow = add("Brow", deep, nil, "fur")
	body.ears = { add("Ear", skin, nil, "skin"), add("Ear", skin, nil, "skin") }
	body.eyes = { add("Eye", def.EyeColor or WHITE), add("Eye", def.EyeColor or WHITE) }
	body.pupils = { add("Pupil", def.CoreColor or INK), add("Pupil", def.CoreColor or INK) }
	body.nostrils = { add("Nostril", def.CoreColor or INK), add("Nostril", def.CoreColor or INK) }
	body.mouth = add("Mouth", def.CoreColor or INK)
	body.teeth = add("Teeth", WHITE)
	-- things he holds: a barrel, a TNT barrel (with its fuse)
	body.barrel = add("HeldBarrel", WOOD, nil, nil, Enum.PartType.Cylinder)
	body.barrelBands = { add("HeldBarrelBand", WOOD_DARK, nil, nil, Enum.PartType.Cylinder), add("HeldBarrelBand", WOOD_DARK, nil, nil, Enum.PartType.Cylinder) }
	body.tnt = add("HeldTNT", RED, nil, nil, Enum.PartType.Cylinder)
	body.tntBand = add("HeldTNTBand", YELLOW, nil, nil, Enum.PartType.Cylinder)
	body.fuse = add("TNTFuse", ORANGE, Enum.Material.Neon)
	-- curled up into a ball (the Rolling Attack): three flat blocks crossed
	-- through each other plus a cube in the middle make a chunky pixel ball (a
	-- round Ball part would just turn into a cube in the pixel look). His face,
	-- tie, hands and feet poke out of it so you can see it's him rolling.
	body.balls = {}
	for i = 1, 4 do
		body.balls[i] = add("RollBall", fur, nil, "fur")
	end
	body.ballFace = add("RollBallFace", skin, nil, "skin")
	body.ballEyes = { add("RollBallEye", def.CoreColor or INK), add("RollBallEye", def.CoreColor or INK) }
	body.ballTie = add("RollBallTie", def.TieColor or RED)
	body.ballHands = { add("RollBallHand", skin, nil, "skin"), add("RollBallHand", skin, nil, "skin") }
	body.ballFeet = { add("RollBallFoot", skin, nil, "skin"), add("RollBallFoot", skin, nil, "skin") }
	-- (every piece of the ball, for showing and hiding it all together)
	body.ballBits = { body.ballFace, body.ballTie, body.ballEyes[1], body.ballEyes[2], body.ballHands[1], body.ballHands[2],
		body.ballFeet[1], body.ballFeet[2] }
	for _, b in ipairs(body.balls) do
		table.insert(body.ballBits, b)
	end
	-- dizzy stars, and the helicopter blur round him (Spinning Kong)
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon)
	end
	-- his shadow, and the spot word bubbles hang from
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0, folder)
	body.anchor = newPart("Anchor", nil, WHITE, Enum.Material.SmoothPlastic, 1, folder)
	body.anchor.Size = V3(0.2, 0.2, 0.2)
	-- each part vanishes at its own moment when he pops into pixels, and
	-- some parts decide for themselves whether they show (see applyPose)
	body.popAt, body.selfShown = {}, {}
	local SELF = { HeldBarrel = true, HeldBarrelBand = true, HeldTNT = true, HeldTNTBand = true, TNTFuse = true, RollBall = true,
		RollBallFace = true, RollBallEye = true, RollBallTie = true, RollBallHand = true, RollBallFoot = true, DizzyStar = true,
		Teeth = true }
	for i, p in ipairs(body.all) do
		body.popAt[p] = ((i * 37) % 23) / 23
		body.selfShown[p] = SELF[p.Name] == true
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- (his resting stance: arms hanging down to his knuckles, just in front)
local REST_R = V3(3.4, -2.1, -1.3)
local REST_L = V3(-3.4, -2.1, -1.3)

local function show(p, on)
	p.Transparency = on and 0 or 1
end

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 10
	local model = B.model
	-- knuckle-walking: legs swing and he rocks while the server says he's moving
	local moving = model:GetAttribute("Moving") == true
	B.walk = smoothNum(B, "walkS", moving and 1 or 0, 8, dt)
	B.stridePhase = (B.stridePhase or 0) + dt * 8 * math.max(B.walk, 0.15)
	local stride = math.sin(B.stridePhase) * B.walk
	-- (everything eases between poses, so nothing snaps; P.snap = a moment that must be exact)
	local rate = P.snap and 60 or (P.rate or 16)
	local crouch = smoothNum(B, "crouchS", clamp(P.crouch or 0, -0.3, 1), rate, dt)
	local sit = smoothNum(B, "sitS", clamp(P.sit or 0, 0, 1), rate * 0.6, dt)
	local lean = smoothNum(B, "leanS", (P.lean or 0) + 0.12 * B.walk, rate, dt)
	local twist = smoothNum(B, "twistS", P.twist or 0, rate, dt)
	local headPitch = smoothNum(B, "headS", P.headPitch or 0, rate, dt)
	local walkSwing = V3(0, 0, stride * 1.1)
	local rHandT = smoothVec(B, "rHandS", P.rHand or (REST_R + walkSwing), rate, dt)
	local lHandT = smoothVec(B, "lHandS", P.lHand or (REST_L - walkSwing), rate, dt)
	local ballK = smoothNum(B, "ballS", clamp(P.ball or 0, 0, 1), P.snap and 60 or 22, dt)
	local roar = smoothNum(B, "roarS", clamp(P.roar or 0, 0, 1), 18, dt)
	local fall = smoothNum(B, "fallS", clamp(P.fall or 0, 0, 1), 6, dt)
	local sx, sy = P.sx or 1, P.sy or 1
	local sink = P.sink or 0
	local fade = P.fade or 0
	local mad = B.phase2Look
	local flash = B.flashAt and (os.clock() - B.flashAt) < 0.1

	local jitter = V3(0, 0, 0)
	if (P.shake or 0) > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local groundPos = ground + jitter + V3(0, (P.lift or 0) - sink * 14 * u, 0)
	local look = unitOr(flat(facing), V3(0, 0, -1))
	if P.spinA then
		look = turnY(look, P.spinA) -- (the helicopter: spinning round)
	end
	local base = CFrame.lookAt(groundPos, groundPos + look)
	if fall > 0 then
		-- flat on his back: tipping over his heels
		base = base * CFrame.new(0, 0, 1.6 * u) * CFrame.Angles(fall * 1.45, 0, 0) * CFrame.new(0, 0, -1.6 * u)
	end
	local forward = base.LookVector

	-- CURLED UP INTO A BALL: just the ball (his face and tie showing as it rolls)
	local balled = ballK > 0.5
	local R = 4.4 * u
	if balled then
		local r = R * (0.7 + 0.3 * ballK) -- (he puffs up to full size as he curls)
		-- the blocks: three flat ones, each long (2r) one way and 1.2r the other
		-- two ways, and a 1.6r cube in the middle. Seen from any side that makes
		-- a pixel circle: rows 1.2r, 1.6r, then 2r wide across the middle.
		local long, flatW, mid = 2 * r, 1.2 * r, 1.6 * r
		-- rolling over: as it turns, its corners lift it off the floor a little,
		-- so it bumps along like a real chunky ball instead of sinking in
		local spinA = P.ballSpin or 0
		local s, c0 = math.abs(math.sin(spinA)), math.abs(math.cos(spinA))
		local bump = math.max(0.6 * s + c0, s + 0.6 * c0, 0.8 * (s + c0))
		local c = groundPos + V3(0, r * bump, 0)
		local cf = CFrame.lookAt(c, c + look) * CFrame.Angles(-spinA, 0, 0)
		body.balls[1].Size = V3(long, flatW, flatW)
		body.balls[2].Size = V3(flatW, long, flatW)
		body.balls[3].Size = V3(flatW, flatW, long)
		body.balls[4].Size = V3(mid, mid, mid)
		for _, b in ipairs(body.balls) do
			b.CFrame = cf
		end
		-- his face (with two eyes) and tie on the front, just past the fur
		body.ballFace.Size = V3(r * 0.9, r * 0.7, 0.4 * u)
		body.ballFace.CFrame = cf * CFrame.new(0, r * 0.2, -r - 0.15 * u)
		for i, eye in ipairs(body.ballEyes) do
			eye.Size = V3(r * 0.14, r * 0.2, 0.12)
			eye.CFrame = cf * CFrame.new(((i == 1) and -0.2 or 0.2) * r, r * 0.3, -r - 0.36 * u)
		end
		body.ballTie.Size = V3(0.9 * u, r * 0.28, 0.3 * u)
		body.ballTie.CFrame = cf * CFrame.new(0, -r * 0.42, -r - 0.1 * u)
		-- his hands hugging his sides, and the soles of his feet at the back
		for i, hand in ipairs(body.ballHands) do
			local side = (i == 1) and -1 or 1
			hand.Size = V3(0.45 * u, r * 0.6, r * 0.7)
			hand.CFrame = cf * CFrame.new(side * (r + 0.12 * u), -r * 0.1, -r * 0.25)
		end
		for i, foot in ipairs(body.ballFeet) do
			local side = (i == 1) and -1 or 1
			foot.Size = V3(r * 0.45, r * 0.5, 0.45 * u)
			foot.CFrame = cf * CFrame.new(side * 0.3 * r, -r * 0.25, r + 0.12 * u)
		end
	end
	for _, b in ipairs(body.ballBits) do
		show(b, balled and fade < 0.5)
	end

	-- LEGS (two pieces each, knees bent out like a gorilla's)
	local hipY = (3.4 - 1.4 * math.max(crouch, 0) - 2.2 * sit) * u * sy
	local legX = (1.5 + 0.4 * math.max(crouch, 0) + 0.5 * sit) * u * sx
	local L1, L2 = 1.9 * u, 1.9 * u
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local hip = base * V3(side * legX, hipY, 0.2 * u)
		local fz = -side * stride * 1.2 * u
		local liftFoot = math.max(0, -side * stride) * 0.6 * u
		local ankle
		if sit > 0.05 then
			-- sitting: legs out in front, crossed at the ankles
			local sitAnkle = base * V3(-side * 0.6 * u, 0.6 * u, -3.2 * u)
			ankle = (base * V3(side * legX, 1.0 * u + liftFoot, fz)):Lerp(sitAnkle, sit)
		else
			ankle = base * V3(side * legX * 1.1, 1.0 * u + liftFoot, fz)
		end
		local bend = unitOr(forward + base.RightVector * side * 0.6, forward)
		local knee, ankle2 = twoBone(hip, ankle, L1, L2, bend)
		stretch(body.thighs[i], hip, knee, 2.1 * u * sx, 2.1 * u, forward)
		stretch(body.shins[i], knee, ankle2, 1.9 * u * sx, 1.9 * u, forward)
		local foot = body.feet[i]
		foot.Size = V3(2.0 * u * sx, 1.0 * u, 3.0 * u)
		foot.CFrame = CFrame.lookAt(ankle2, ankle2 + forward) * CFrame.new(0, -0.45 * u, -0.6 * u)
	end

	-- THE UPPER BODY: from the hips, leaning, twisting
	local torso = base * CFrame.new(0, hipY, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, 0)
	local up, tlook, right = torso.UpVector, torso.LookVector, torso.RightVector
	local breathe = 1 + 0.03 * math.sin(os.clock() * 2.2)
	body.hips.Size = V3(4.6 * u * sx, 1.8 * u * sy, 3.4 * u)
	body.hips.CFrame = torso * CFrame.new(0, 0.6 * u * sy, 0.1 * u)
	body.belly.Size = V3(4.4 * u * sx, 2.4 * u * sy, 3.8 * u) * breathe
	body.belly.CFrame = torso * CFrame.new(0, 2.0 * u * sy, -0.25 * u)
	local chestH = 3.2 * u * sy
	local chestY = 2.6 * u * sy + chestH / 2
	body.chest.Size = V3(6.4 * u * sx, chestH, 4.0 * u) * breathe
	body.chest.CFrame = torso * CFrame.new(0, chestY, 0)
	body.back.Size = V3(5.6 * u * sx, chestH * 0.9, 1.0 * u)
	body.back.CFrame = torso * CFrame.new(0, chestY + 0.2 * u, 1.9 * u)
	local neckY = chestY + chestH / 2
	local shoulders = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local scf = torso * CFrame.new(side * 3.5 * u * sx, neckY - 0.7 * u, 0)
		body.shoulders[i].Size = V3(2.6, 2.4, 3.2) * u
		body.shoulders[i].CFrame = scf
		shoulders[i] = scf.Position
	end
	-- the chain: a gold collar at his neck, two strands down his chest in a V,
	-- and a big banana medallion where they meet
	local tieCF = torso * CFrame.new(0, neckY - 0.35 * u, -2.05 * u) * CFrame.Angles(0.08 + lean * 0.5, 0, 0)
	body.knot.Size = V3(3.4 * u, 0.45 * u, 0.5 * u)
	body.knot.CFrame = tieCF
	body.tie.Size = V3(0.4 * u, 2.3 * u * sy, 0.35 * u)
	body.tie.CFrame = tieCF * CFrame.new(-0.85 * u, -1.05 * u * sy, -0.05 * u) * CFrame.Angles(0, 0, math.rad(-32))
	body.tieTip.Size = V3(0.4 * u, 2.3 * u * sy, 0.35 * u)
	body.tieTip.CFrame = tieCF * CFrame.new(0.85 * u, -1.05 * u * sy, -0.05 * u) * CFrame.Angles(0, 0, math.rad(32))
	-- (the banana: three chunky blocks bent in a curve)
	local mcf = tieCF * CFrame.new(0, -2.35 * u * sy, -0.25 * u)
	body.letter[1].Size = V3(0.45 * u, 0.8 * u, 0.3 * u)
	body.letter[1].CFrame = mcf * CFrame.new(-0.5 * u, 0.2 * u, 0) * CFrame.Angles(0, 0, math.rad(55))
	body.letter[2].Size = V3(0.8 * u, 0.5 * u, 0.3 * u)
	body.letter[2].CFrame = mcf * CFrame.new(0, -0.1 * u, 0)
	body.letter[3].Size = V3(0.45 * u, 0.8 * u, 0.3 * u)
	body.letter[3].CFrame = mcf * CFrame.new(0.5 * u, 0.2 * u, 0) * CFrame.Angles(0, 0, math.rad(-55))

	-- the head
	local head = torso * CFrame.new(0, neckY + 1.5 * u * sy, -0.9 * u) * CFrame.Angles(-headPitch, 0, 0)
	body.head.Size = V3(4.2, 3.6, 3.8) * u
	body.head.CFrame = head
	for i, tf in ipairs(body.tuft) do
		tf.Size = V3(0.9, 1.3, 0.9) * u
		tf.CFrame = head * CFrame.new((i - 2) * 0.7 * u, 2.1 * u, 0.2 * u) * CFrame.Angles(0, 0, (i - 2) * -0.4)
	end
	body.face.Size = V3(3.2 * u, 1.9 * u, 0.4 * u)
	body.face.CFrame = head * CFrame.new(0, 0.55 * u, -1.9 * u)
	-- his brow comes down when he's angry
	local browDrop = mad and 0.25 or 0
	body.brow.Size = V3(4.0 * u, 0.9 * u, 1.2 * u)
	body.brow.CFrame = head * CFrame.new(0, (1.35 - browDrop) * u, -1.9 * u)
	body.muzzle.Size = V3(3.4 * u, (1.7 + 0.5 * roar) * u, 1.6 * u)
	body.muzzle.CFrame = head * CFrame.new(0, (-0.85 - 0.25 * roar) * u, -2.2 * u)
	for i, ear in ipairs(body.ears) do
		local side = (i == 1) and -1 or 1
		ear.Size = V3(0.6, 1.3, 1.1) * u
		ear.CFrame = head * CFrame.new(side * 2.3 * u, 0.3 * u, 0)
	end
	local eyeOpen = clamp(num(P.eyes, 1), 0, 1) * (1 - fade)
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local ecf = head * CFrame.new(side * 0.75 * u, 0.6 * u, -2.12 * u)
		local eye, pupil = body.eyes[i], body.pupils[i]
		eye.Size = V3(0.8 * u, math.max(0.9 * u * eyeOpen, 0.05), 0.12)
		eye.CFrame = ecf
		eye.Transparency = eyeOpen < 0.05 and 1 or 0
		pupil.Size = V3(0.42 * u, math.max(0.5 * u * eyeOpen, 0.05), 0.12)
		-- (dizzy: the pupils roll round)
		local roll = (P.stars or 0) > 0.05 and V3(math.cos(os.clock() * 9 + i) * 0.15 * u, math.sin(os.clock() * 9 + i) * 0.15 * u, 0) or V3()
		pupil.CFrame = ecf * CFrame.new(side * -0.08 * u + roll.X, -0.05 * u + roll.Y, -0.05)
		pupil.Transparency = eyeOpen < 0.05 and 1 or 0
		pupil.Color = mad and (def.RageColor or RED) or (def.CoreColor or INK)
		local n = body.nostrils[i]
		n.Size = V3(0.45, 0.3, 0.1) * u
		n.CFrame = head * CFrame.new(side * 0.55 * u, (-0.45 - 0.2 * roar) * u, -3.02 * u)
	end
	local mouthOpen = math.max(roar, clamp(num(P.mouth, 0), 0, 1))
	body.mouth.Size = V3(2.0 * u, math.max(0.25 * u + 1.1 * u * mouthOpen, 0.05), 0.12)
	body.mouth.CFrame = head * CFrame.new(0, (-1.35 - 0.45 * mouthOpen) * u, -3.02 * u)
	body.teeth.Size = V3(1.6 * u, 0.3 * u, 0.13)
	body.teeth.CFrame = head * CFrame.new(0, (-1.0 - 0.1 * mouthOpen) * u, -3.03 * u)
	body.teeth.Transparency = (mouthOpen > 0.3 and fade < 0.5) and 0 or 1

	-- ARMS: from each shoulder to where the pose wants that hand
	local hands = {}
	local wants = { torso * (lHandT * u), torso * (rHandT * u) }
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local bend = (right * side * 0.7 - up * 0.3 + tlook * 0.2)
		local elbow, hand = twoBone(shoulders[i], wants[i], 2.8 * u, 2.8 * u, bend.Unit)
		hands[i] = hand
		stretch(body.upperArms[i], shoulders[i], elbow, 2.0 * u, 2.0 * u, tlook)
		stretch(body.foreArms[i], elbow, hand, 2.2 * u, 2.2 * u, tlook)
		body.hands[i].Size = V3(2.0, 1.8, 2.2) * u
		body.hands[i].CFrame = CFrame.lookAt(hand, hand + (hand - elbow), tlook)
	end
	B.handR, B.handL = hands[2], hands[1]

	-- WHAT HE'S HOLDING over his head: a barrel, or TNT
	local holding = P.holding
	-- it sits on the far side of his hands from his shoulders: out in front
	-- while he swings it up, then on top of his hands once they're over his
	-- head (so it never goes through his face)
	local midHands = (hands[1] + hands[2]) / 2
	local pivot = torso * V3(0, neckY - 0.7 * u, 0)
	local over = midHands + unitOr(midHands - pivot, up) * 1.5 * u
	local bcf = CFrame.lookAt(over, over + right) -- (lying sideways across his hands)
	local showBarrel = holding == "Barrel" and fade < 0.5 and not balled
	local showTNT = holding == "TNT" and fade < 0.5 and not balled
	body.barrel.Size = V3(3.6, 3.0, 3.0) * u
	body.barrel.CFrame = bcf * CFrame.Angles(0, math.pi / 2, 0)
	show(body.barrel, showBarrel)
	for k, band in ipairs(body.barrelBands) do
		band.Size = V3(0.35, 3.15, 3.15) * u
		band.CFrame = body.barrel.CFrame * CFrame.new((k == 1) and -1.1 * u or 1.1 * u, 0, 0)
		show(band, showBarrel)
	end
	body.tnt.Size = V3(3.4, 2.9, 2.9) * u
	body.tnt.CFrame = bcf * CFrame.Angles(0, math.pi / 2, 0)
	show(body.tnt, showTNT)
	body.tntBand.Size = V3(1.2, 3.0, 3.0) * u
	body.tntBand.CFrame = body.tnt.CFrame
	show(body.tntBand, showTNT)
	body.fuse.Size = V3(0.3, 0.9, 0.3) * u
	body.fuse.CFrame = body.tnt.CFrame * CFrame.new(1.8 * u, 0.6 * u, 0) * CFrame.Angles(0, 0, -0.6)
	body.fuse.Color = (math.floor(os.clock() * 12) % 2 == 0) and YELLOW or ORANGE
	show(body.fuse, showTNT)
	B.overHead = over

	-- DIZZY STARS round his head
	local stars = P.stars or 0
	for i, st in ipairs(body.stars) do
		if stars > 0.05 and fade < 0.5 then
			local a = os.clock() * 5 + i * (math.pi * 2 / 3)
			local p = balled and (groundPos + V3(math.cos(a) * 3 * u, 2 * R + 1.5 * u, math.sin(a) * 3 * u))
				or (head * V3(math.cos(a) * 2.8 * u, 3.0 * u, math.sin(a) * 2.8 * u))
			st.Size = V3(1.1, 1.1, 0.45) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, os.clock() * 6)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- where word bubbles hang, and the top of his head
	B.headTop = balled and (groundPos + V3(0, 2 * R + 1, 0)) or (head * V3(0, 2.6 * u, 0))
	body.anchor.CFrame = CFrame.new(B.headTop + V3(0, 1.5, 0))

	-- his shadow
	local shadowD = 9 * u * (1 - clamp((P.lift or 0) / 40, 0, 0.7))
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.06, 0), shadowD, 0.1)
	body.shadow.Transparency = (fade > 0.5 or sink > 0.4) and 1 or 0

	-- colours: the hit flash; round 2's angry red face
	for _, f in ipairs(body.fur) do
		f.part.Color = flash and WHITE or f.color
	end
	local skinNow = mad and (def.SkinColor or RGB(232, 183, 150)):Lerp(def.RageColor or RED, 0.45) or nil
	for _, s in ipairs(body.skin) do
		s.part.Color = flash and WHITE or (skinNow or s.color)
	end

	-- the body hides while he's a ball; popping into pixels at the end: each
	-- part goes at its own moment
	local hidden = sink > 0.97
	for _, p in ipairs(body.all) do
		if hidden or (fade > 0 and fade >= body.popAt[p] * 0.9 + 0.05) then
			p.Transparency = 1
		elseif not body.selfShown[p] then
			p.Transparency = balled and 1 or 0
		end
	end
	if hidden or fade > 0.5 then
		for _, p in ipairs(body.ballBits) do
			p.Transparency = 1
		end
	end
	local _ = t
end
Body.pose = applyPose

----------------------------------------------------------------------
-- His warnings in the world
----------------------------------------------------------------------
-- A red lane on the floor from `c0` to `c1`, `width` wide - dim while it's
-- still following you, bright (with a white blink) once it locks
local function laneParts()
	return {
		strip = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
		rimL = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
		rimR = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1),
	}
end

local function placeLane(L, c0, c1, width, locked, blink)
	local dir = unitOr(flat(c1 - c0), V3(0, 0, -1))
	local sideV = V3(-dir.Z, 0, dir.X)
	local len = flat(c1 - c0).Magnitude
	local mid = (c0 + c1) / 2 + V3(0, 0.12, 0)
	local color = blink and WHITE or RED
	L.strip.Size = V3(width * 2, 0.12, math.max(len, 0.1))
	L.strip.CFrame = CFrame.lookAt(mid, mid + dir)
	L.strip.Transparency = locked and 0.45 or 0.72
	L.strip.Color = color
	for i, rim in ipairs({ L.rimL, L.rimR }) do
		local s = (i == 1) and -1 or 1
		local rm = mid + sideV * s * width + V3(0, 0.02, 0)
		rim.Size = V3(0.5, 0.14, math.max(len, 0.1))
		rim.CFrame = CFrame.lookAt(rm, rm + dir)
		rim.Transparency = locked and 0.1 or 0.5
		rim.Color = color
	end
end

local function hideLane(L)
	L.strip.Transparency, L.rimL.Transparency, L.rimR.Transparency = 1, 1, 1
end

local function removeLane(L)
	L.strip:Destroy()
	L.rimL:Destroy()
	L.rimR:Destroy()
end

-- THE GIANT PUNCH's lane: it grows the longer he winds, following his
-- facing, and locks (slots 1-2) just before he goes
local function punchLane(B, a, t0, wind)
	local L = laneParts()
	local lockedAt = nil
	addTelegraph(B, {
		update = function(now)
			local from, to = slot(B, 1), slot(B, 2)
			local len = (from and to) and flat(to - from).Magnitude or 0
			local ends = t0 + wind + len / a.Speed
			if B.action ~= "GiantPunch" or B.actionStart ~= t0 or now > ends + 0.05 then
				return false
			end
			if from and to then
				lockedAt = lockedAt or now
				local blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
				placeLane(L, onFloor(from), onFloor(to), a.Width, true, blink)
			else
				local c0 = onFloor(B.vpos)
				placeLane(L, c0, c0 + B.vfacing * windReach(a, now - t0), a.Width, false, false)
			end
			return true
		end,
		cleanup = function()
			removeLane(L)
		end,
	})
end

-- A shockwave rolling out along the floor: its radius at any moment is
-- exactly what the server tests (BossService's stepWaves)
local function waveRing(B, origin, t0, speed, reach, height, thickness)
	local wall = newRing(52, DIRT, Enum.Material.SmoothPlastic, 0)
	local crest = newRing(52, WHITE, Enum.Material.Neon, 0.55)
	local life = reach / speed
	local start = 2
	addTelegraph(B, {
		update = function(now)
			local age = now - t0
			if age > life then
				return false
			end
			if age < 0 then
				placeRing(wall, origin, start, 0.05, thickness, 1)
				placeRing(crest, origin, start, 0.05, thickness * 0.4, 1)
				return true
			end
			local r = start + speed * age
			local fadeOut = clamp((age - (life - 0.3)) / 0.3, 0, 1)
			local h = height * (1 - 0.45 * fadeOut) * (0.92 + 0.08 * math.sin(now * 30))
			placeRing(wall, origin + V3(0, 0.05, 0), r, h, thickness, lerp(0, 1, fadeOut), true)
			placeRing(crest, origin + V3(0, h * 0.85, 0), r, h * 0.3, thickness * 0.45, lerp(0.5, 1, fadeOut), true)
			return true
		end,
		cleanup = function()
			removeRing(wall)
			removeRing(crest)
		end,
	})
end

-- THE ROLL's path: a lane to the bounce (slot 2), and on to where he stops
-- (slot 3) - dim while he's curling up and it's still following you
local function rollLanes(B, a, t0)
	local L1, L2 = laneParts(), laneParts()
	local lockedAt = nil
	addTelegraph(B, {
		update = function(now)
			local travel = num(B.model:GetAttribute("ActN"), nil)
			local from, mid, to = slot(B, 1), slot(B, 2), slot(B, 3)
			local ends = t0 + a.Tell + (travel or 1.5)
			if B.action ~= "Roll" or B.actionStart ~= t0 or now > ends + 0.05 then
				return false
			end
			if from and mid then
				lockedAt = lockedAt or now
				local blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
				placeLane(L1, onFloor(from), onFloor(mid), a.Width, true, blink)
				if to then
					placeLane(L2, onFloor(mid), onFloor(to), a.Width, true, blink)
				else
					hideLane(L2)
				end
			else
				local c0 = onFloor(B.vpos)
				placeLane(L1, c0, c0 + B.vfacing * 30, a.Width, false, false)
				hideLane(L2)
			end
			return true
		end,
		cleanup = function()
			removeLane(L1)
			removeLane(L2)
		end,
	})
end

-- SPINNING KONG's ring: red round him, wherever he goes, while he spins
local function spinRing(B, a, t0)
	local ring = newRing(32, RED, Enum.Material.Neon, 1)
	local disc = newPart("SpinWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local startsAt, endsAt = t0 + a.Tell, t0 + a.Tell + a.Time
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "Spin" or B.actionStart ~= t0 or now > endsAt then
				return false
			end
			local c = onFloor(B.vpos)
			local k = clamp((now - t0) / a.Tell, 0, 1)
			local on = now >= startsAt
			local blink = on and (math.floor(now * 8) % 2 == 0)
			placeRing(ring, c + V3(0, 0.14, 0), a.Radius, 0.3, 0.6, on and (blink and 0.05 or 0.25) or lerp(0.8, 0.35, k))
			placeDisc(disc, c + V3(0, 0.1, 0), a.Radius * 2 * (on and 1 or k), 0.1)
			disc.Transparency = on and 0.6 or 0.8
			return true
		end,
		cleanup = function()
			removeRing(ring)
			disc:Destroy()
		end,
	})
end

-- a barrel rolling along its lane (slots 2k-1, 2k), thrown at `throwAt`
local function rollingBarrel(B, a, k, throwAt)
	local L = laneParts()
	local barrel = newPart("RollingBarrel", Enum.PartType.Cylinder, WOOD, Enum.Material.SmoothPlastic, 1)
	local bands = { newPart("RollingBarrelBand", Enum.PartType.Cylinder, WOOD_DARK, Enum.Material.SmoothPlastic, 1),
		newPart("RollingBarrelBand", Enum.PartType.Cylinder, WOOD_DARK, Enum.Material.SmoothPlastic, 1) }
	local smashed = false
	addTelegraph(B, {
		update = function(now)
			local from, to = slot(B, 2 * k - 1), slot(B, 2 * k)
			if not (from and to) then
				return B.action == "Barrel" and now < throwAt + 1
			end
			from, to = onFloor(from), onFloor(to)
			local len = flat(to - from).Magnitude
			local ends = throwAt + len / a.Speed
			if now > ends + 0.05 then
				if not smashed then
					smashed = true
					burst(to + V3(0, 1.5, 0), WOOD, 14, 16, 1.2, 0.6, true)
					playSound(B.def, "BarrelBreak", to, 0.7)
				end
				return false
			end
			local dir = unitOr(flat(to - from), V3(0, 0, -1))
			if now < throwAt then
				placeLane(L, from, to, a.Radius, true, false)
				L.strip.Transparency = 0.7
				barrel.Transparency = 1
				for _, b in ipairs(bands) do
					b.Transparency = 1
				end
				return true
			end
			local gone = (now - throwAt) * a.Speed
			placeLane(L, from + dir * gone, to, a.Radius, true, false)
			local r = a.Radius
			local c = from + dir * gone + V3(0, r, 0)
			local cf = CFrame.lookAt(c, c + dir) * CFrame.Angles(-gone / r, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
			barrel.Size = V3(r * 1.5, r * 2, r * 2)
			barrel.CFrame = cf
			barrel.Transparency = 0
			for i, b in ipairs(bands) do
				b.Size = V3(0.3, r * 2.08, r * 2.08)
				b.CFrame = cf * CFrame.new((i == 1) and -r * 0.45 or r * 0.45, 0, 0)
				b.Transparency = 0
			end
			return true
		end,
		cleanup = function()
			removeLane(L)
			barrel:Destroy()
			for _, b in ipairs(bands) do
				b:Destroy()
			end
		end,
	})
end

-- a TNT barrel lobbed onto slot k: a red circle fills in where it lands,
-- the barrel arcs over, and BOOM
local function tntLob(B, a, k, throwAt)
	local disc = newPart("TNTWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local ring = newRing(28, RED, Enum.Material.Neon, 1)
	local keg = newPart("FlyingTNT", Enum.PartType.Cylinder, RED, Enum.Material.SmoothPlastic, 1)
	local band = newPart("FlyingTNTBand", Enum.PartType.Cylinder, YELLOW, Enum.Material.SmoothPlastic, 1)
	local from = nil
	local landAt = throwAt + a.Flight
	local boomed = false
	addTelegraph(B, {
		update = function(now)
			local spot = slot(B, k)
			if not spot then
				return B.action == "TNT" and now < landAt + 0.5
			end
			spot = onFloor(spot)
			if now >= landAt then
				if not boomed then
					boomed = true
					burst(spot + V3(0, 2, 0), ORANGE, 30, 30, 2, 0.7, true)
					burst(spot + V3(0, 3, 0), YELLOW, 20, 24, 1.6, 0.5, true)
					burst(spot + V3(0, 1, 0), DIRT, 20, 20, 1.8, 0.7)
					shockRing(B, spot, 1, a.Radius * 1.2, 0.35, ORANGE)
					playSound(B.def, "TNT", spot, 1)
					kick(spot, a.Radius + 24, 1.2, -4)
				end
				return false
			end
			local k01 = clamp((now - throwAt) / a.Flight, 0, 1)
			placeDisc(disc, spot + V3(0, 0.12, 0), a.Radius * 2 * (0.3 + 0.7 * k01), 0.1)
			disc.Transparency = lerp(0.65, 0.35, k01)
			local blink = k01 > 0.75 and (math.floor(now * 12) % 2 == 0)
			disc.Color = blink and WHITE or RED
			placeRing(ring, spot + V3(0, 0.14, 0), a.Radius, 0.3, 0.55, 0.15)
			if now >= throwAt then
				from = from or (B.overHead or (B.vpos + V3(0, 14, 0)))
				local p = from:Lerp(spot + V3(0, 1.5, 0), k01) + V3(0, math.sin(k01 * math.pi) * (10 + flat(spot - from).Magnitude * 0.25), 0)
				local cf = CFrame.new(p) * CFrame.Angles(k01 * 8, 0, k01 * 5)
				keg.Size = V3(3, 2.6, 2.6)
				keg.CFrame = cf
				keg.Transparency = 0
				band.Size = V3(1.1, 2.7, 2.7)
				band.CFrame = cf
				band.Transparency = 0
			end
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
			keg:Destroy()
			band:Destroy()
		end,
	})
end

-- CARGO THROW's grab: a wedge in front of him, filling in as he winds up
local function grabWedge(B, a, t0)
	local N = 12
	local bits = {}
	for i = 1, N do
		bits[i] = newPart("GrabWarning", nil, RED, Enum.Material.Neon, 1)
	end
	local hitAt = t0 + a.Tell
	local half = math.rad(a.Arc / 2)
	addTelegraph(B, {
		update = function(now)
			if now > hitAt + 0.08 or B.action ~= "CargoThrow" then
				return false
			end
			local c = onFloor(B.vpos)
			local aim = slot(B, 1)
			local dir = aim and unitOr(flat(aim - B.vpos), B.vfacing) or B.vfacing
			local k = clamp((now - t0) / a.Tell, 0, 1)
			local step = (half * 2) / N
			for i, p in ipairs(bits) do
				local ang = -half + (i - 0.5) * step
				local out = turnY(dir, ang)
				local r = a.Reach * (0.35 + 0.65 * k)
				local pos = c + out * (r / 2) + V3(0, 0.14, 0)
				p.Size = V3(math.max(2 * r * math.sin(step / 2), 0.3), 0.12, r)
				p.CFrame = CFrame.lookAt(pos, pos + out)
				p.Transparency = aim and 0.35 or 0.6
			end
			return true
		end,
		cleanup = function()
			for _, p in ipairs(bits) do
				p:Destroy()
			end
		end,
	})
end

-- dust puffing up where a hand (or a foot) hits the ground
local function dust(B, at_, big)
	local c = onFloor(at_)
	burst(c + V3(0, 0.6, 0), DIRT, big and 22 or 12, big and 22 or 14, big and 1.8 or 1.2, 0.55)
	if big then
		burst(c + V3(0, 0.4, 0), DIRT_DARK, 12, 16, 1.4, 0.5)
	end
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- ASLEEP in the middle of the clearing: sitting, head nodding, snoring
function Poses.Dormant(B, t, P)
	P.sit = 1
	P.eyes = 0
	P.headPitch = 0.35 + 0.06 * math.sin(os.clock() * 1.1)
	P.rHand, P.lHand = V3(1.3, 1.9, -2.0), V3(-1.3, 1.9, -2.0)
	P.sy = 1 + 0.04 * math.sin(os.clock() * 1.6)
	local _ = B
	local _ = t
end

-- WAKING UP: a yawn and a stretch, a jump up, a chest pound, a ROAR
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local u1, u2, u3 = W * 0.25, W * 0.45, W * 0.6
	if t < u1 then
		-- stretching and yawning, still sitting
		local k = smooth(t / u1)
		P.sit = 1
		P.eyes = 0.3
		P.rHand, P.lHand = V3(2.4, 7.2 * k + 2 * (1 - k), -0.6), V3(-2.4, 7.2 * k + 2 * (1 - k), -0.6)
		P.mouth = k
	elseif t < u2 then
		-- up onto his feet (a little hop)
		local k = (t - u1) / (u2 - u1)
		P.sit = 1 - smooth(k)
		P.lift = math.sin(k * math.pi) * 3
		P.eyes = 1
	elseif t < u3 then
		-- a crouch...
		P.crouch = 0.5
		P.eyes = 1
		P.rHand, P.lHand = V3(2.2, 2.6, -2.6), V3(-2.2, 2.6, -2.6)
	else
		-- CHEST POUND and ROAR
		local e = t - u3
		local beat = math.floor(e * 7) % 2
		P.rHand = V3(1.3, (beat == 0) and 4.4 or 5.2, (beat == 0) and -2.1 or -3.4)
		P.lHand = V3(-1.3, (beat == 1) and 4.4 or 5.2, (beat == 1) and -2.1 or -3.4)
		P.roar = 1
		P.headPitch = -0.25
		P.eyes = 1
	end
end

-- EVERYONE'S GONE: a big shrug... and he sits back down for a nap
function Poses.Reset(B, t, P)
	if t < 0.8 then
		P.rHand, P.lHand = V3(3.4, 4.2, -1.2), V3(-3.4, 4.2, -1.2)
		P.headPitch = 0.1
	else
		P.sit = smooth((t - 0.8) / 0.8)
		P.eyes = 1 - smooth((t - 1.4) / 0.6)
		P.rHand, P.lHand = V3(1.3, 1.9, -2.0), V3(-1.3, 1.9, -2.0)
	end
	local _ = B
end

-- GIANT PUNCH: the windmill, the lunge, and - if he missed - tired
function Poses.GiantPunch(B, t, P)
	local a = B.def.Attacks.GiantPunch
	local wind = num(B.model:GetAttribute("ActN"), a.Wind[1])
	if t < wind then
		-- the windmill: his right fist whirls round beside him, faster and faster
		local k = t / wind
		local ang = (t * t) * 9 + t * 4
		local c = V3(3.9, 4.6, 0.4)
		P.rHand = c + V3(0, math.cos(ang) * 2.6, math.sin(ang) * 2.6)
		P.lHand = V3(-2.4, 3.4, -2.6)
		P.lean = -0.12 * k
		P.twist = -0.35 * k
		P.crouch = 0.25 * k
		P.snap = true
		return
	end
	local from, to = slot(B, 1), slot(B, 2)
	local travel = (from and to) and flat(to - from).Magnitude / a.Speed or 0.3
	local e = t - wind
	if e < travel + 0.15 then
		-- THE PUNCH: thrown forward, arm out straight
		P.rHand = V3(1.0, 4.4, -6.4)
		P.lHand = V3(-3.3, 2.4, 1.8)
		P.lean = 0.35
		P.twist = 0.3
		P.crouch = 0.15
		P.snap = true
		return
	end
	if slot(B, 3) then
		-- missed: tired, hands on his knees, panting
		local pant = math.sin(os.clock() * 9)
		P.rHand, P.lHand = V3(1.7, -0.4 + pant * 0.1, -2.4), V3(-1.7, -0.4 + pant * 0.1, -2.4)
		P.lean = 0.45
		P.crouch = 0.35 + pant * 0.04
		P.headPitch = 0.25
		P.mouth = 0.6 + 0.3 * math.abs(pant)
		P.stars = (e > travel + 0.4) and 1 or 0
	else
		-- landed it: a cocky shake of the fist
		P.rHand = V3(3.0, 5.6 + math.sin(os.clock() * 16) * 0.3, -1.2)
		P.headPitch = -0.15
	end
end

-- HAND SLAP: both arms up, then slap after slap on the ground in front
function Poses.HandSlap(B, t, P)
	local a = B.def.Attacks.HandSlap
	local slaps = num(B.model:GetAttribute("ActN"), 3)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.rHand = REST_R:Lerp(V3(2.4, 7.8, -1.0), k)
		P.lHand = REST_L:Lerp(V3(-2.4, 7.8, -1.0), k)
		P.lean = -0.1 * k
		return
	end
	local e = t - a.Tell
	local i = math.min(math.floor(e / a.Gap), slaps - 1)
	local within = e - i * a.Gap
	local down = V3(1.9, -2.6, -3.8)
	local up = V3(2.4, 6.8, -1.4)
	local hit = within < 0.12 and 1 or clamp(1 - (within - 0.12) / (a.Gap - 0.12), 0, 1)
	local rightHand = (i % 2 == 0)
	if i >= slaps - 1 and within > a.Gap then
		-- done: getting back up
		P.crouch = 0.2
		return
	end
	local downR = rightHand and down or V3(down.X, lerp(up.Y, down.Y, 0.2), down.Z)
	local downL = (not rightHand) and V3(-down.X, down.Y, down.Z) or V3(-down.X, lerp(up.Y, down.Y, 0.2), down.Z)
	P.rHand = up:Lerp(downR, rightHand and hit or 0.2)
	P.lHand = V3(-up.X, up.Y, up.Z):Lerp(downL, (not rightHand) and hit or 0.2)
	P.lean = 0.3 * hit
	P.crouch = 0.45 * hit
	P.snap = within < 0.12
end

-- ROLLING ATTACK: curls up, revs on the spot, rolls - then sits there dizzy
function Poses.Roll(B, t, P)
	local a = B.def.Attacks.Roll
	local travel = num(B.model:GetAttribute("ActN"), 1)
	if t < a.Tell then
		local k = clamp(t / (a.Tell * 0.5), 0, 1)
		P.crouch = 0.8 * k
		P.ball = (t > a.Tell * 0.35) and 1 or 0
		P.ballSpin = (t > a.Tell * 0.35) and ((t - a.Tell * 0.35) ^ 2 * 40) or 0 -- (revving up)
		P.rHand, P.lHand = V3(1.2, 1.2, -2.8), V3(-1.2, 1.2, -2.8)
		return
	end
	local e = t - a.Tell
	if e < travel then
		P.ball = 1
		P.ballSpin = (a.Tell * 0.65) ^ 2 * 40 + e * a.Speed / (4.4 * B.def.Size / 10)
		P.snap = true
		return
	end
	-- dizzy after
	P.stars = 1
	P.eyes = 1
	P.lean = math.sin(os.clock() * 4) * 0.15
	P.twist = math.sin(os.clock() * 3) * 0.2
	P.rHand, P.lHand = V3(3.6, -1.0, -0.6), V3(-3.6, -1.0, -0.6)
end

-- SPINNING KONG: arms out, then round and round like a helicopter; dizzy after
function Poses.Spin(B, t, P)
	local a = B.def.Attacks.Spin
	local k = smooth(t / a.Tell)
	P.rHand = REST_R:Lerp(V3(5.8, 4.8, 0), k)
	P.lHand = REST_L:Lerp(V3(-5.8, 4.8, 0), k)
	P.crouch = 0.15 * k
	if t >= a.Tell and t < a.Tell + a.Time then
		P.spinA = (t - a.Tell) * 16
		P.headPitch = -0.1
		return
	end
	if t >= a.Tell + a.Time then
		P.stars = 1
		P.lean = math.sin(os.clock() * 4) * 0.2
		P.twist = math.sin(os.clock() * 3) * 0.3
		P.rHand, P.lHand = V3(4.4, 1.5, -0.6), V3(-4.4, 1.5, -0.6)
	end
end

-- HEADBUTT: head back... and in
function Poses.Headbutt(B, t, P)
	local a = B.def.Attacks.Headbutt
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.headPitch = -0.55 * k
		P.lean = -0.25 * k
		P.rHand, P.lHand = V3(3.4, 1.6, 1.2), V3(-3.4, 1.6, 1.2)
		return
	end
	P.headPitch = (t < a.Tell + a.Time + 0.1) and 0.45 or 0.1
	P.lean = (t < a.Tell + a.Time + 0.1) and 0.6 or 0.1
	P.rHand, P.lHand = V3(3.6, 1.0, 2.0), V3(-3.6, 1.0, 2.0)
	P.snap = t < a.Tell + a.Time
end

-- Heaving something up over his head: his straight arms swing round in an
-- arc, from `fromDeg` (0 = hanging down, 90 = straight out in front) up to
-- nearly straight up, `k` of the way there (0 to 1). Going round the front
-- like this keeps the barrel out in front of his face instead of through it,
-- and stopping just short of straight up leaves his hands where you can see
-- them, above his head and under the barrel.
local SHOULDER_Y = 5.1 -- (how high his shoulders are, in body sizes)
local function heave(P, fromDeg, k)
	local a = math.rad(lerp(fromDeg, 175, k))
	local y, z = SHOULDER_Y - 5.2 * math.cos(a), -5.2 * math.sin(a)
	P.rHand = V3(1.9, y, z)
	P.lHand = V3(-1.9, y, z)
end

-- BARREL THROW: heaves a barrel overhead, throws it; again for each one
function Poses.Barrel(B, t, P)
	local a = B.def.Attacks.Barrel
	local count = num(B.model:GetAttribute("ActN"), 2)
	for k = 1, count do
		local throwAt = a.Tell + (k - 1) * a.Gap
		local liftStart = (k == 1) and 0 or throwAt - 0.4
		if t >= liftStart and t < throwAt then
			local up = smooth((t - liftStart) / math.max(throwAt - liftStart - 0.1, 0.1))
			heave(P, (k == 1) and 30 or 70, up)
			P.holding = up > 0.1 and "Barrel" or nil
			P.lean = -0.15 * up
			return
		end
		if t >= throwAt and t < throwAt + 0.3 then
			P.rHand, P.lHand = V3(1.8, 3.2, -4.8), V3(-1.8, 3.2, -4.8)
			P.lean = 0.35
			P.snap = true
			return
		end
	end
end

-- TNT: the same heave, a red barrel with its fuse fizzing
function Poses.TNT(B, t, P)
	local a = B.def.Attacks.TNT
	local count = num(B.model:GetAttribute("ActN"), 1)
	for k = 1, count do
		local throwAt = a.Tell + (k - 1) * a.Gap
		local liftStart = (k == 1) and 0 or throwAt - 0.4
		if t >= liftStart and t < throwAt then
			local up = smooth((t - liftStart) / math.max(throwAt - liftStart - 0.1, 0.1))
			heave(P, (k == 1) and 30 or 105, up)
			P.holding = up > 0.1 and "TNT" or nil
			P.lean = -0.2 * up
			return
		end
		if t >= throwAt and t < throwAt + 0.3 then
			P.rHand, P.lHand = V3(1.8, 6.5, -3.8), V3(-1.8, 6.5, -3.8)
			P.lean = 0.2
			P.snap = true
			return
		end
	end
end

-- CHEST POUND: "OOH OOH!" - showing off
function Poses.Pound(B, t, P)
	local beat = math.floor(t * 7) % 2
	P.rHand = V3(1.3, (beat == 0) and 4.4 or 5.3, (beat == 0) and -2.1 or -3.5)
	P.lHand = V3(-1.3, (beat == 1) and 4.4 or 5.3, (beat == 1) and -2.1 or -3.5)
	P.roar = 0.7 + 0.3 * math.abs(math.sin(t * 7))
	P.headPitch = -0.2
	P.lift = math.abs(math.sin(t * 3.5)) * 0.6
	local _ = B
end

-- CARGO THROW: arms wide, a lunge, the grab... and the throw overhead
function Poses.CargoThrow(B, t, P)
	local a = B.def.Attacks.CargoThrow
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.rHand = REST_R:Lerp(V3(5.0, 4.0, -3.2), k)
		P.lHand = REST_L:Lerp(V3(-5.0, 4.0, -3.2), k)
		P.crouch = 0.3 * k
		P.lean = 0.2 * k
		return
	end
	local e = t - a.Tell
	if e < 0.15 then
		P.rHand, P.lHand = V3(1.1, 4.2, -4.4), V3(-1.1, 4.2, -4.4)
		P.lean = 0.35
		P.snap = true
	elseif e < 0.55 then
		local k = smooth((e - 0.15) / 0.4)
		P.rHand = V3(1.1, lerp(4.2, 9.0, k), lerp(-4.4, 1.4, k))
		P.lHand = V3(-1.1, lerp(4.2, 9.0, k), lerp(-4.4, 1.4, k))
		P.lean = lerp(0.35, -0.25, k)
		P.roar = slot(B, 2) and 1 or 0
	else
		P.roar = slot(B, 2) and 0.5 or 0
		P.stars = slot(B, 2) and 0 or 1 -- (missed: he stumbles, dizzy)
	end
end

-- GOING BANANAS (round 2): he pounds his chest faster and faster and ROARS
function Poses.Break(B, t, P)
	local def = B.def
	local fast = 7 + t * 3
	local beat = math.floor(t * fast) % 2
	P.rHand = V3(1.3, (beat == 0) and 4.4 or 5.3, (beat == 0) and -2.1 or -3.5)
	P.lHand = V3(-1.3, (beat == 1) and 4.4 or 5.3, (beat == 1) and -2.1 or -3.5)
	P.roar = 1
	P.headPitch = -0.3
	P.shake = (t > def.BreakTime * 0.35) and 0.25 or 0.08
	P.crouch = (t < def.BreakTime * 0.35) and 0.3 or 0
end

-- THE END: dizzy, wobbling... and flat on his back. Then gone in a pop of pixels.
function Poses.Death(B, t, P)
	P.stars = 1
	P.eyes = 1
	if t < 1.1 then
		P.lean = math.sin(t * 9) * 0.25
		P.twist = math.sin(t * 7) * 0.3
		P.rHand, P.lHand = V3(4.2, 2.0, -0.6), V3(-4.2, 2.0, -0.6)
		return
	end
	P.fall = 1
	P.rHand, P.lHand = V3(5.2, 1.0, 0), V3(-5.2, 1.0, 0)
	P.fade = clamp((t - 3.4) / 0.7, 0, 1)
	local _ = B
end

----------------------------------------------------------------------
-- Starts and slots: the sounds, bursts and warnings of each move
----------------------------------------------------------------------
function Starts.Wake(B, t0)
	local W = B.def.WakeTime
	at(B, t0 + W * 0.1, function()
		shout(B.body.anchor, "*YAWN*", 1.0, WHITE)
	end)
	at(B, t0 + W * 0.45, function()
		dust(B, B.vpos, true)
		kick(B.vpos, 24, 0.5)
	end)
	at(B, t0 + W * 0.6 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W * 0.6, function()
		playSound(B.def, "Pound", B.vpos, 0.8)
		shout(B.body.anchor, "OOH OOH!", 1.2, YELLOW)
		kick(B.vpos, 40, 0.8, -3)
	end)
end

function Starts.Dormant(B, t0)
	-- (back from a reset: a puff of dust as he plops down)
	if B.prevAction == "Reset" then
		dust(B, B.vpos, false)
	end
	local _ = t0
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		shout(B.body.anchor, "HMPH. BORING.", 1.2, WHITE)
	end)
	at(B, t0 + 1.4, function()
		dust(B, B.vpos, false)
	end)
end

function Starts.GiantPunch(B, t0)
	local a = B.def.Attacks.GiantPunch
	local wind = num(B.model:GetAttribute("ActN"), a.Wind[1])
	punchLane(B, a, t0, wind)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Wind", B.vpos, 0.8)
	end)
	at(B, t0 + wind, function()
		playSound(B.def, "Punch", B.vpos, 1)
		shout(B.body.anchor, "GIANT PUNCH!", 0.9, YELLOW)
		burst(B.vpos + V3(0, 2, 0), WHITE, 12, 20, 1.2, 0.35, true)
	end)
	-- the end of the lunge: dust, a camera kick, the ground shaking (round 2)
	local done = false
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "GiantPunch" or B.actionStart ~= t0 then
				return false
			end
			local from, to = slot(B, 1), slot(B, 2)
			if done or not (from and to) then
				return not done
			end
			local land = t0 + wind + flat(to - from).Magnitude / a.Speed
			if now >= land then
				done = true
				dust(B, to + unitOr(flat(to - from), B.vfacing) * 5, true)
				kick(to, 24, 0.9, -3)
				local shake = slot(B, 4)
				if shake then
					waveRing(B, onFloor(shake), land, a.WaveSpeed, a.WaveReach, a.WaveHeight, a.WaveThickness)
					kick(to, 60, 1.6, -6)
				end
			end
			return true
		end,
		cleanup = function() end,
	})
end

function SlotSpawns.GiantPunch(B, i, spot, t0)
	if i == 3 then
		at(B, serverNow() + 0.2, function()
			playSound(B.def, "Tired", B.vpos, 0.8)
		end)
	end
	local _ = spot
	local _ = t0
end

function Starts.HandSlap(B, t0)
	local a = B.def.Attacks.HandSlap
	local slaps = num(B.model:GetAttribute("ActN"), perRound(B, a.Slaps))
	for k = 1, slaps do
		local slapAt = t0 + a.Tell + (k - 1) * a.Gap
		at(B, slapAt, function()
			local origin = slot(B, 1) or (B.vpos + B.vfacing * 5)
			origin = onFloor(origin)
			waveRing(B, origin, slapAt, a.Speed, a.Reach, a.Height, a.Thickness)
			dust(B, origin, true)
			playSound(B.def, "Slap", origin, 0.9)
			kick(origin, 30, 0.7, -3)
		end)
	end
end

function Starts.Roll(B, t0)
	local a = B.def.Attacks.Roll
	rollLanes(B, a, t0)
	at(B, t0 + a.Tell * 0.35, function()
		playSound(B.def, "Roll", B.vpos, 0.6)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Roll", B.vpos, 1)
		dust(B, B.vpos, true)
	end)
end

function SlotSpawns.Roll(B, i, spot, t0)
	-- the bounce off the edge: a thud and a spray of dirt when he gets there
	if i == 3 then
		local a = B.def.Attacks.Roll
		local from, mid = slot(B, 1), slot(B, 2)
		if from and mid then
			local bounceAt = t0 + a.Tell + flat(mid - from).Magnitude / a.Speed
			at(B, bounceAt, function()
				dust(B, mid, true)
				kick(mid, 24, 0.8, -2)
			end)
		end
	end
	local _ = spot
end

function Starts.Spin(B, t0)
	local a = B.def.Attacks.Spin
	spinRing(B, a, t0)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Spin", B.vpos, 1)
		shout(B.body.anchor, "SPINNING KONG!", 1.0, YELLOW)
	end)
	-- dust kicking up as he spins
	for k = 0, math.floor(a.Time / 0.3) do
		at(B, t0 + a.Tell + k * 0.3, function()
			if B.action == "Spin" then
				burst(onFloor(B.vpos) + V3(0, 0.6, 0), DIRT, 6, 18, 1, 0.4)
			end
		end)
	end
end

function Starts.Headbutt(B, t0)
	local a = B.def.Attacks.Headbutt
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Headbutt", B.vpos, 1)
	end)
end

function SlotSpawns.Headbutt(B, i, spot, t0)
	-- its short lane, once it locks
	if i == 2 then
		local a = B.def.Attacks.Headbutt
		local L = laneParts()
		addTelegraph(B, {
			update = function(now)
				local from = slot(B, 1)
				if not from or now > t0 + a.Tell + a.Time or B.action ~= "Headbutt" then
					return false
				end
				placeLane(L, onFloor(from), onFloor(spot), a.Width, true, false)
				return true
			end,
			cleanup = function()
				removeLane(L)
			end,
		})
	end
end

function Starts.Barrel(B, t0)
	local a = B.def.Attacks.Barrel
	local count = num(B.model:GetAttribute("ActN"), 2)
	for k = 1, count do
		local throwAt = t0 + a.Tell + (k - 1) * a.Gap
		rollingBarrel(B, a, k, throwAt)
		at(B, throwAt, function()
			playSound(B.def, "Barrel", B.vpos, 0.9)
		end)
	end
end

function Starts.TNT(B, t0)
	local a = B.def.Attacks.TNT
	local count = num(B.model:GetAttribute("ActN"), 1)
	for k = 1, count do
		local throwAt = t0 + a.Tell + (k - 1) * a.Gap
		tntLob(B, a, k, throwAt)
		at(B, throwAt, function()
			playSound(B.def, "Barrel", B.vpos, 0.8)
		end)
	end
end

function Starts.Pound(B, t0)
	local a = B.def.Attacks.Pound
	at(B, t0 + 0.05, function()
		playSound(B.def, "Pound", B.vpos, 1)
		shout(B.body.anchor, "OOH OOH!", a.Time * 0.9, YELLOW)
	end)
	at(B, t0 + a.Time * 0.5, function()
		playSound(B.def, "Hoot", B.vpos, 0.9)
	end)
end

function Starts.CargoThrow(B, t0)
	local a = B.def.Attacks.CargoThrow
	grabWedge(B, a, t0)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Grab", B.vpos, 1)
	end)
end

function SlotSpawns.CargoThrow(B, i, spot, t0)
	if i == 2 then
		shout(B.body.anchor, "YOINK!", 1.0, YELLOW)
		burst(onFloor(spot) + V3(0, 3, 0), WHITE, 14, 18, 1.2, 0.4, true)
		kick(spot, 20, 0.8, -2)
	end
	local _ = t0
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + 0.05, function()
		playSound(def, "Pound", B.vpos, 1)
	end)
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		playSound(def, "Break", B.vpos, 1)
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, def.RageColor or RED)
		burst(B.vpos + V3(0, 8, 0), def.RageColor or RED, 40, 30, 1.8, 0.9, true)
		dust(B, B.vpos, true)
		kick(B.vpos, def.BreakReach + 20, 1.4, -5)
		if B.here then
			pcall(bigText, "GOING BANANAS!", { color = YELLOW, sub = "ROUND 2", size = 64, hold = 1.2 })
		end
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.2, function()
		playSound(def, "Death", B.vpos, 1)
	end)
	at(B, t0 + 1.4, function()
		-- flat on his back: THUD
		dust(B, B.vpos - B.vfacing * 6, true)
		kick(B.vpos, 40, 1.2, -4)
	end)
	at(B, t0 + 3.4, function()
		for k = 1, 4 do
			burst(B.vpos + V3(0, 1 + k * 1.5, 0), (k % 2 == 0) and def.Color or (def.TieColor or RED), 14, 14, 1.2, 0.8, true)
		end
		-- (a banana, left behind)
		burst(B.vpos + V3(0, 2, 0), YELLOW, 10, 10, 1, 1.2, true)
	end)
end

----------------------------------------------------------------------
-- Every frame: the villagers, the torches, the "HIT HIM!"
----------------------------------------------------------------------
-- The monkey villagers (JungleBuilder's "JungleMonkey" models): each part's
-- place is remembered the first time they're seen, then every frame they
-- bob along - jumping and waving when he shows off (a roar, a chest pound,
-- going bananas), covering their eyes when he loses.
local function monkeysOf(B)
	if B.monkeys and os.clock() < (B.monkeysLook or 0) + 3 then
		return B.monkeys
	end
	B.monkeysLook = os.clock()
	B.monkeys = B.monkeys or {}
	B.monkeySeen = B.monkeySeen or {}
	for _, mk in ipairs(game:GetService("CollectionService"):GetTagged("JungleMonkey")) do
		if not B.monkeySeen[mk] and mk:IsA("Model") and mk:GetAttribute("Floor") == B.floor and mk.PrimaryPart and Arenas.inside(Arenas.arenaFor(B.model), mk) then
			B.monkeySeen[mk] = true
			local baseCF = mk.PrimaryPart.CFrame
			local parts = {}
			for _, p in ipairs(mk:GetChildren()) do
				if p:IsA("BasePart") then
					table.insert(parts, { part = p, rel = baseCF:ToObjectSpace(p.CFrame), name = p.Name })
				end
			end
			table.insert(B.monkeys, { base = baseCF, parts = parts, seed = num(mk:GetAttribute("Index"), #B.monkeys + 1) })
		end
	end
	return B.monkeys
end

local function stepMonkeys(B, now)
	local list = monkeysOf(B)
	if #list == 0 then
		return
	end
	local act = B.action
	local cheer = (act == "Pound" or act == "Break" or (act == "Wake" and B.actionStart and now - B.actionStart > B.def.WakeTime * 0.55))
	local sad = act == "Death" or B.stateNow == "Dead"
	local fightOn = B.stateNow == "Fighting" or B.stateNow == "Transition" or B.stateNow == "Waking"
	for _, mk in ipairs(list) do
		local s = mk.seed
		local hop = 0
		if cheer then
			hop = math.abs(math.sin(now * 8 + s)) * 1.3
		elseif fightOn then
			hop = math.abs(math.sin(now * 3 + s * 1.7)) * 0.25
		end
		local sway = math.sin(now * 2 + s) * 0.06
		local cf = mk.base * CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, sway)
		for _, rec in ipairs(mk.parts) do
			local rel = rec.rel
			if rec.name == "MonkeyArm" then
				local side = rel.Position.X < 0 and -1 or 1
				if sad then
					-- hands over their eyes
					rel = CFrame.new(side * 0.35, 1.25, -0.75) * CFrame.Angles(1.3, 0, -side * 0.5)
				elseif cheer then
					-- waving their arms in the air
					local wave = math.sin(now * 10 + s + side) * 0.3
					rel = CFrame.new(rel.Position.X, rel.Position.Y + 1.2, rel.Position.Z) * CFrame.Angles(0, 0, side * (2.6 + wave))
						* CFrame.new(0, 0.5, 0)
				end
			end
			rec.part.CFrame = cf * rel
		end
	end
end

-- The tiki torches (JungleBuilder's "JungleTorch" flames): bigger and
-- redder once he's gone bananas, back to normal when the fight's over
local function stepTorches(B)
	B.torches = B.torches or nil
	if not B.torches then
		B.torches = {}
		for _, f in ipairs(game:GetService("CollectionService"):GetTagged("JungleTorch")) do
			if f:IsA("BasePart") and f:GetAttribute("Floor") == B.floor and Arenas.inside(Arenas.arenaFor(B.model), f) then
				table.insert(B.torches, { part = f, size = f.Size, cf = f.CFrame, color = f.Color })
			end
		end
	end
	local hot = B.phase2Look and (B.stateNow == "Fighting" or B.stateNow == "Transition")
	if hot == B.torchesHot then
		if hot then
			for i, tr in ipairs(B.torches) do
				local flick = 1 + 0.12 * math.sin(os.clock() * 14 + i)
				tr.part.Size = tr.size * V3(1.5, 1.9 * flick, 1.5)
				tr.part.CFrame = tr.cf * CFrame.new(0, tr.size.Y * 0.45, 0)
			end
		end
		return
	end
	B.torchesHot = hot
	for _, tr in ipairs(B.torches) do
		tr.part.Size = hot and tr.size * V3(1.5, 1.9, 1.5) or tr.size
		tr.part.CFrame = hot and (tr.cf * CFrame.new(0, tr.size.Y * 0.45, 0)) or tr.cf
		tr.part.Color = hot and RED or tr.color
	end
end

-- "HIT HIM!" over his head while he's wide open
local function openNow(B, now)
	local t0 = B.actionStart
	if not t0 then
		return nil
	end
	local t = now - t0
	local A = B.def.Attacks
	local act = B.action
	if act == "Pound" then
		return "HIT HIM!"
	end
	if act == "GiantPunch" and slot(B, 3) then
		return "HIT HIM!"
	end
	if act == "Roll" then
		local travel = num(B.model:GetAttribute("ActN"), 1)
		if t > A.Roll.Tell + travel + 0.1 then
			return "DIZZY! HIT HIM!"
		end
	end
	if act == "Spin" and t > A.Spin.Tell + A.Spin.Time + 0.1 then
		return "DIZZY! HIT HIM!"
	end
	return nil
end

local function stepHint(B, show)
	local now = serverNow()
	local want = show and openNow(B, now) or nil
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
		bb.Name = "KongoHint"
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
-- what his moves are made of: dirt and dust
function Body.fx(def)
	local _ = def
	return { color = DIRT, deep = DIRT_DARK, rock = DIRT_DARK, material = Enum.Material.SmoothPlastic, solid = true }
end

-- where he is between the server's updates: exactly on his lunge's line (or
-- his roll's path, bounce and all) - the server's own sums
function Body.glide(B, now, ground)
	local _ = ground
	local t0 = B.actionStart
	if not t0 then
		return nil
	end
	local A = B.def.Attacks
	local act = B.action
	local from, mid = slot(B, 1), slot(B, 2)
	if not (from and mid) then
		return nil
	end
	if act == "GiantPunch" then
		local wind = num(B.model:GetAttribute("ActN"), A.GiantPunch.Wind[1])
		local travel = flat(mid - from).Magnitude / A.GiantPunch.Speed
		local e = now - t0 - wind
		if e < 0 or e > travel + 0.2 then
			return nil
		end
		return from:Lerp(mid, clamp(e / math.max(travel, 1e-3), 0, 1))
	elseif act == "Headbutt" then
		local e = now - t0 - A.Headbutt.Tell
		if e < 0 or e > A.Headbutt.Time + 0.2 then
			return nil
		end
		return from:Lerp(mid, clamp(e / A.Headbutt.Time, 0, 1))
	elseif act == "Roll" then
		local a = A.Roll
		local e = now - t0 - a.Tell
		if e < 0 then
			return nil
		end
		local t1 = flat(mid - from).Magnitude / a.Speed
		local to = slot(B, 3)
		local t2 = to and flat(to - mid).Magnitude / a.Speed or 0
		if e > t1 + t2 + 0.2 then
			return nil
		end
		if e < t1 then
			return from:Lerp(mid, e / math.max(t1, 1e-3))
		end
		if to then
			return mid:Lerp(to, clamp((e - t1) / math.max(t2, 1e-3), 0, 1))
		end
		return mid
	end
	return nil
end

-- a new move began: whatever was held goes
function Body.onAction(B, name, t0, now)
	local _ = name
	local _ = t0
	local _ = now
end

-- joined while he'd already gone bananas
function Body.lateBreak(B)
	B.phase2Look = true
end

-- a fresh start (a reset, a new fight): calm again, torches back to normal
function Body.calm(B, name)
	local _ = name
	B.phase2Look = false
	B.torchesHot = nil
end

-- every frame, whatever he's doing: the village, the torches, the hint
function Body.senses(B, dt, here, awake, state)
	local _ = dt
	B.here = here
	B.stateNow = state
	local now = serverNow()
	local function run(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.warned = B.warned or {}
			if not B.warned[name] then
				B.warned[name] = true
				warn("[BossClient] Kongo's " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	if here then
		run("villagers", stepMonkeys, B, now)
	end
	run("torches", stepTorches, B)
	run("hint", stepHint, B, here and awake)
end

return Body
