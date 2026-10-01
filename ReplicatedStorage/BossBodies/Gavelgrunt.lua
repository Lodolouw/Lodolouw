--[[
	Gavelgrunt  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Gavelgrunt")

	How King Gavelgrunt, Lord of the Spire (floor 10's boss, the FINAL BOSS,
	Config.Bosses[10]) looks on your screen: a colossal chunky 8-bit WALRUS
	KING nine times your height - stubby legs on broad hind flippers with gold
	anklets, a great layered belly (three rolls of blubber, a gold belt
	straining round them), huge shoulders under spiked gold pauldrons, a deep
	crimson cape with an ermine collar, front flippers in gold bracers, a
	heavy-browed head with a big whiskery muzzle, ivory tusks (the right one
	snapped off short), an old stitched scar slashed across his left eye -
	which still glows, blind and bright - and a tall spiked gold crown. THE
	GAVEL: an iron war-gavel with gold bands, a spike on top and runes that
	light up as he winds up a blow. In round 2 it becomes a steel piston
	hammer (a glowing core, steam). In round 3 his crown flies off, his eyes
	and scar burn red and the storm turns to a red eclipse.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Gavelgrunt.lua, where each move is explained):
	  * Poses[move]   his body t seconds into a move
	  * Starts[move]  the move's sounds, dust and camera kicks, and its
	                  warnings on the floor, timed on the server's clock
	  * SlotSpawns    warnings for the spots the server fills in as it goes
	  * Body.glide    exactly where he is during a leap, a roll or a rush
	  * Body.senses   every frame: his props (tin guards, the glowing flipper,
	                  coins, the roast platter), the pillars crumbling, his
	                  throne (hidden once he's thrown it, drawn where it
	                  landed), the torches, THE STORM (rain, lightning and
	                  thunder the moment you arrive; darker in round 2, a red
	                  eclipse in round 3), your camera for his entrance, and
	                  "HIT HIM!"
	  * the moments every boss has: asleep on his throne (the scarred eye
	    never quite closes), THE ENTRANCE (lightning cracks, he stands up on
	    his throne, raises the gavel into the storm - it's struck - and leaps
	    down in front of you with a slam that shakes the courtyard), back up
	    to his throne when everyone's gone, round 2 (the mechanical gavel),
	    round 3 (the crown flies off), falling flat on his back at the end

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: crouch, lean, twist, headPitch, sit,
	fall (on his back), faceDown (tripped), rHand / lHand (where his flippers
	are, in his body's space, studs), gavelAt (a world point the gavel's head
	reaches for) or gavelDir (the way it points, in his body's space), headAt
	(the gavel's head flying off on its chain), rFoot (his right foot lifted
	/ stamping) and rFootAt (a world point the tip of that flipper reaches
	for), ball / ballSpin (curled up), spinA (spinning), mouth, cheeks (his
	muzzle puffed out), stars (dizzy), crown ("on" / "off": round 3's crown),
	runes (the gavel's glow, 0-1, as well as its wind-ups'), glare (his eyes
	flaring) and scarEye (how open the scarred eye is while the other's shut).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}
-- (which arena copy is this boss's: ReplicatedStorage/Arenas)
local Arenas = require(game:GetService("ReplicatedStorage"):WaitForChild("Arenas"))

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, flat, easeOut
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES, bigText, shout, shot

function Body.init(kit)
	serverNow, clamp, lerp, smooth, flat, easeOut = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.flat, kit.easeOut
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES = kit.kick, kit.playSound, kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES
	bigText, shout, shot = kit.bigText, kit.shout, kit.shot
end

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

local ThronePlan = require(game:GetService("ReplicatedStorage"):WaitForChild("ThronePlan"))

-- colours that aren't in his Config
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local ORANGE = RGB(247, 118, 34)
local GREEN = RGB(99, 199, 77)
local SKY = RGB(44, 232, 245)
local BLUE = RGB(0, 153, 219)
local SILVER = RGB(192, 203, 220)
local STEEL = RGB(139, 155, 180)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local DUST = RGB(234, 212, 170)
local WOOD = RGB(184, 111, 80)
local WOOD_DARK = RGB(115, 62, 57)
local ROAST = RGB(190, 74, 47)
local HIDE = RGB(115, 62, 57)
local HIDE_DEEP = RGB(62, 39, 49)
local IVORY = RGB(234, 212, 170)
local CRIMSON = RGB(162, 38, 51)
local IRON = RGB(58, 68, 102)
local IRON_DARK = RGB(38, 43, 68)
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

-- a number for this round: a { round 1, round 2, round 3 } list, or just a number
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

-- from way `a` round towards way `b` (flat), `s` of the way (0 to 1)
local function blendDir(a, b, s)
	local ang = math.atan2(a.X * b.Z - a.Z * b.X, a.X * b.X + a.Z * b.Z)
	return turnY(a, ang * s)
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
	local up = upHint or V3(0, 1, 0)
	if math.abs(dir.Unit:Dot(up.Unit)) > 0.98 then
		up = V3(1, 0, 0)
	end
	p.Size = V3(w, d, len)
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- where the elbow (or knee) goes for a limb from `a` to `c` made of two
-- pieces `l1` and `l2` long, bending toward `bendDir`
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

local function smoothNum(B, key, want, rate, dt)
	local old = B[key]
	if type(old) ~= "number" then
		B[key] = want
		return want
	end
	local v = old + (want - old) * (1 - math.exp(-dt * rate))
	B[key] = v
	return v
end

local function smoothVec(B, key, want, rate, dt)
	local old = B[key]
	if typeof(old) ~= "Vector3" then
		B[key] = want
		return want
	end
	local v = old:Lerp(want, 1 - math.exp(-dt * rate))
	B[key] = v
	return v
end

-- the middle of the courtyard (the arena says; the plan knows where he waits)
local function centerOf(B)
	if B.center then
		return B.center
	end
	local arena = Arenas.arenaFor(B.model, "Center") -- (his own arena copy)
	local c = arena and arena:GetAttribute("Center")
	if typeof(c) == "Vector3" then
		B.center = c
		return c
	end
	return V3(0, 0, 5200)
end

-- the ground under a spot
local function floorAt(B, pos)
	return V3(pos.X, B.vpos and B.vpos.Y or pos.Y, pos.Z)
end

-- his throne: where he sits on it (a spot on the floor under him) and the
-- way he faces there (down the carpet, at the gate)
local function throneSeat(B)
	local c = centerOf(B)
	local s = ThronePlan.SeatAt
	return V3(c.X + s.X, B.vpos.Y, c.Z + s.Z), V3(0, 0, 1)
end

-- where he fights from (the server keeps him there while he wakes)
local function homeSpot(B)
	local root = B.model.PrimaryPart
	if root then
		return V3(root.Position.X, B.vpos.Y, root.Position.Z)
	end
	local c = centerOf(B)
	return V3(c.X + ThronePlan.Home.X, B.vpos.Y, c.Z + ThronePlan.Home.Z)
end

-- THE GAVEL'S RUNES light up as he winds up a blow with it (a move's Tell;
-- the whole of the Hammer Tornado; the Final Gavel held up to the sky)
local GAVEL_MOVES = { RoyalSmash = true, GavelSweep = true, TripleSlam = true, RocketHammer = true, Guilty = true, Earthquake = true }
local function windUp(B)
	local t0, act = B.actionStart, B.action
	if not (t0 and act) then
		return 0
	end
	local t = serverNow() - t0
	local a = B.def.Attacks[act]
	if act == "HammerTornado" then
		return (t >= 0 and t < a.Tell + a.Time) and 1 or 0
	elseif act == "FinalGavel" then
		return (t >= 0.8 and t < B.def.Final.Tell + 0.1) and 1 or 0
	elseif GAVEL_MOVES[act] and a and a.Tell then
		if t < 0 or t > a.Tell + 0.15 then
			return 0
		end
		return clamp(t / (a.Tell * 0.6), 0, 1)
	end
	return 0
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {}, tinted = {} }
	local hide, deep, belly = def.Color or HIDE, def.DeepColor or HIDE_DEEP, def.BellyColor or WOOD
	local gold, ivory = def.GoldColor or GOLD, def.TuskColor or IVORY
	local fur, cape = def.FurColor or WHITE, def.CapeColor or CRIMSON
	local function add(name, color, material, tint, shape)
		local p = newPart(name, shape, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, p)
		if tint then
			table.insert(body.tinted, { part = p, color = color })
		end
		return p
	end
	-- LEGS: short and fat, on broad hind flippers (splayed out, three ivory
	-- claws each) with gold anklets
	body.thighs, body.shins, body.anklets, body.flippers, body.fans, body.toeClaws = {}, {}, {}, {}, {}, {}
	for i = 1, 2 do
		body.thighs[i] = add("Thigh", hide, nil, true)
		body.shins[i] = add("Shin", hide, nil, true)
		body.anklets[i] = add("Anklet", gold, nil, true)
		body.flippers[i] = add("HindFlipper", deep, nil, true)
		body.fans[i] = add("HindFlipper", deep, nil, true)
		body.toeClaws[i] = {}
		for k = 1, 3 do
			body.toeClaws[i][k] = add("FlipperClaw", ivory, nil, true)
		end
	end
	-- THE BELLY: three great rolls of blubber, one on another (paler down the
	-- front), a crease under the top one, and a gold belt straining round the
	-- bottom two with a big buckle
	body.rolls, body.rollFronts = {}, {}
	for k = 1, 3 do
		body.rolls[k] = add("BellyRoll", hide, nil, true)
		body.rollFronts[k] = add("BellyFront", belly, nil, true)
	end
	body.creases = { add("BellyCrease", deep, nil, true), add("BellyCrease", deep, nil, true) }
	body.belt = add("Belt", gold, nil, true)
	body.buckle = add("Buckle", YELLOW, nil, true)
	body.buckleGem = add("BuckleGem", RED, nil, true)
	-- THE SHOULDERS: huge, under spiked gold pauldrons (a big plate, a smaller
	-- one under it, a dark iron rim, three spikes)
	body.shoulders, body.pauldrons, body.pauldronLows, body.pauldronRims, body.spikes, body.spikeTips = {}, {}, {}, {}, {}, {}
	for i = 1, 2 do
		body.shoulders[i] = add("Shoulder", hide, nil, true)
		body.pauldrons[i] = add("Pauldron", gold, nil, true)
		body.pauldronLows[i] = add("Pauldron", gold, nil, true)
		body.pauldronRims[i] = add("PauldronRim", def.IronColor or IRON, nil, true)
		body.spikes[i], body.spikeTips[i] = {}, {}
		for k = 1, 3 do
			body.spikes[i][k] = add("PauldronSpike", gold, nil, true)
			body.spikeTips[i][k] = add("PauldronSpike", YELLOW, nil, true)
		end
	end
	-- the ermine collar (white fur, black spots) and the crimson cape behind:
	-- two panels, flaring out as it falls, a gold hem along the bottom
	body.collar = add("FurCollar", fur, nil, true)
	body.ermine = {}
	for k = 1, 6 do
		body.ermine[k] = add("Ermine", INK)
	end
	body.capeTop = add("Cape", cape, nil, true)
	body.capeLow = add("Cape", cape, nil, true)
	body.capeHem = add("CapeHem", gold, nil, true)
	-- ARMS: thick, gold bracers at the wrists, broad front flippers with claws
	body.upperArms, body.foreArms, body.bracers, body.hands, body.claws = {}, {}, {}, {}, {}
	for i = 1, 2 do
		body.upperArms[i] = add("UpperArm", hide, nil, true)
		body.foreArms[i] = add("ForeArm", hide, nil, true)
		body.bracers[i] = add("Bracer", gold, nil, true)
		body.hands[i] = add("Flipper", deep, nil, true)
		body.claws[i] = {}
		for k = 1, 3 do
			body.claws[i][k] = add("FlipperClaw", ivory, nil, true)
		end
	end
	-- THE HEAD: round and heavy-browed; a big whiskery muzzle (two round
	-- lobes, pale bristles, nostrils on top, stiff whiskers); little glowing
	-- eyes (the left one blind and brightest); the tusks; the scar
	body.head = add("Head", hide, nil, true)
	body.headRound = add("Head", hide, nil, true)
	body.chin = add("Chin", hide, nil, true)
	body.headParts = { body.head, body.headRound, body.chin }
	body.brows = { add("Brow", deep, nil, true), add("Brow", deep, nil, true) }
	local muzzle = def.MuzzleColor or RGB(194, 133, 105)
	body.muzzle = { add("Muzzle", muzzle, nil, true), add("Muzzle", muzzle, nil, true) }
	body.muzzleV = { add("Muzzle", muzzle, nil, true), add("Muzzle", muzzle, nil, true) }
	body.nostrils = { add("Nostril", def.CoreColor or INK), add("Nostril", def.CoreColor or INK) }
	body.bristles = {}
	for k = 1, 8 do
		body.bristles[k] = add("Bristle", ivory, nil, true)
	end
	body.whiskers = {}
	for k = 1, 4 do
		body.whiskers[k] = add("Whisker", ivory, nil, true)
	end
	body.mouth = add("Mouth", def.CoreColor or INK)
	body.eyes = { add("Eye", def.ScarEyeColor or YELLOW, Enum.Material.Neon), add("Eye", def.EyeColor or GOLD, Enum.Material.Neon) }
	body.pupil = add("Pupil", def.CoreColor or INK)
	-- the tusks (the right one snapped off: a jagged stump)
	body.tusks = { add("Tusk", ivory, nil, true), add("Tusk", ivory, nil, true) }
	body.tuskTip = add("Tusk", ivory, nil, true)
	body.tuskChip = add("Tusk", ivory, nil, true)
	-- THE SCAR: a jagged slash from his brow, across his left eye, down onto
	-- his muzzle, stitched (it burns red in round 3)
	body.scar, body.stitches = {}, {}
	for k = 1, 4 do
		body.scar[k] = add("Scar", def.ScarColor or RGB(232, 183, 150))
	end
	for k = 1, 3 do
		body.stitches[k] = add("Scar", def.ScarColor or RGB(232, 183, 150))
	end
	-- THE CROWN: tall and spiked - a band, a darker rim, five spikes along the
	-- front and three behind (each with a sharp tip), three gems (round 3
	-- knocks it off)
	body.crown = add("Crown", gold, nil, true)
	body.crownRim = add("Crown", ORANGE, nil, true)
	body.crownPoints, body.crownTips = {}, {}
	for k = 1, 8 do
		body.crownPoints[k] = add("CrownPoint", gold, nil, true)
		body.crownTips[k] = add("CrownPoint", YELLOW, nil, true)
	end
	body.gems = { add("CrownGem", BLUE), add("CrownGem", RED), add("CrownGem", BLUE) }
	-- THE GAVEL: a leather-wrapped handle, a gold collar and pommel; an iron
	-- head with gold bands, flat striking faces, a spike on top and runes
	-- (round 2: steel, a glowing piston core and steam vents); a chain for the
	-- rocket
	body.handle = add("GavelHandle", def.GripColor or HIDE_DEEP, nil, true)
	body.gCollar = add("GavelCollar", gold, nil, true)
	body.pommel = add("GavelCollar", gold, nil, true)
	body.gHead = add("GavelHead", def.IronColor or IRON, nil, true)
	body.gFaces = { add("GavelFace", IRON_DARK, nil, true), add("GavelFace", IRON_DARK, nil, true) }
	body.gBands = { add("GavelBand", gold, nil, true), add("GavelBand", gold, nil, true) }
	body.gSpike = add("GavelSpike", def.IronColor or IRON, nil, true)
	body.gSpikeTip = add("GavelSpike", SILVER, nil, true)
	body.runes = {}
	for k = 1, 4 do
		body.runes[k] = add("GavelRune", IRON_DARK, Enum.Material.Neon)
	end
	body.gCore = add("GavelCore", ORANGE, Enum.Material.Neon)
	body.gVents = { add("GavelVent", STEEL, nil, true), add("GavelVent", STEEL, nil, true) }
	body.chain = {}
	for i = 1, 8 do
		body.chain[i] = newPart("GavelChain", nil, SILVER, Enum.Material.SmoothPlastic, 1)
	end
	-- curled up into a ball (the Royal Roll): three blocks crossed through a
	-- cube make a chunky pixel ball of blubber - his muzzle, tusks and eyes
	-- showing, his crown on top
	body.balls = {}
	for i = 1, 4 do
		body.balls[i] = add("RollBall", hide, nil, true)
	end
	body.ballFace = add("RollBallFace", belly, nil, true)
	body.ballTusks = { add("RollBallTusk", ivory, nil, true), add("RollBallTusk", ivory, nil, true) }
	body.ballEyes = { add("RollBallEye", def.ScarEyeColor or YELLOW, Enum.Material.Neon), add("RollBallEye", def.EyeColor or GOLD, Enum.Material.Neon) }
	body.ballCrown = add("RollBallCrown", gold, nil, true)
	body.ballBits = { body.ballFace, body.ballCrown, body.ballTusks[1], body.ballTusks[2], body.ballEyes[1], body.ballEyes[2] }
	for _, b in ipairs(body.balls) do
		table.insert(body.ballBits, b)
	end
	-- dizzy stars, his shadow, and the spot word bubbles hang from
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon)
	end
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0, folder)
	body.anchor = newPart("Anchor", nil, WHITE, Enum.Material.SmoothPlastic, 1, folder)
	body.anchor.Size = V3(0.2, 0.2, 0.2)
	-- each part vanishes at its own moment when he pops into pixels, and some
	-- decide for themselves whether they show (see applyPose)
	body.popAt, body.selfShown = {}, {}
	local SELF = { RollBall = true, RollBallFace = true, RollBallTusk = true, RollBallEye = true, RollBallCrown = true,
		DizzyStar = true, GavelCore = true, GavelVent = true, Crown = true, CrownPoint = true, CrownGem = true, Eye = true,
		Pupil = true }
	for i, p in ipairs(body.all) do
		body.popAt[p] = ((i * 37) % 29) / 29
		body.selfShown[p] = SELF[p.Name] == true
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- (his resting stance: the gavel held at his right side, its head down by his
-- flipper; his left flipper resting on his belly) - in his body's space,
-- studs (times his size), from his hips
local REST_R = V3(10, 4, -4)
local REST_L = V3(-8, 6.5, -8.6)
local REST_GAVEL = V3(0.25, -0.75, -0.6)
local SHOULDER_Y = 13.5
local SHOULDER_X = 8.4
local ARM = 6.2 -- each arm piece
local HANDLE = 15 -- the gavel's handle
local BALL_R = 6.3 -- curled up, this round (his Royal Roll's Width is about this ball)
local SPLAY = 0.28 -- his hind flippers point out this much (radians)
local TOE = 5.4 -- from his ankle to the tip of a hind flipper
-- his belly's three rolls: { height, how tall, how wide (of his width), how
-- deep, how far forward, how far its paler front bulges out }
local ROLLS = { { 3.4, 6.2, 0.9, 13.6, -1.0, 0.6 }, { 8.4, 5.4, 1.0, 14.0, -1.1, 1.1 }, { 12.4, 4.8, 0.8, 12.6, -0.8, 0.4 } }
-- the scar, on his face (in his head's space): brow, over the brow ridge,
-- across the eye, onto the muzzle, down it
local SCAR = { V3(-3.9, 3.5, -4.05), V3(-3.3, 2.3, -4.7), V3(-2.5, 0.9, -4.3), V3(-2.75, -0.3, -5.1), V3(-2.2, -1.9, -6.9) }
-- the crown's spikes: { across, how tall, front (-) or back (+) } (the back
-- ones stand right behind front ones, so the gaps between show)
local SPIKES = { { -3.4, 2.2, -3.2 }, { -1.7, 3.0, -3.3 }, { 0, 4.1, -3.4 }, { 1.7, 3.0, -3.3 }, { 3.4, 2.2, -3.2 },
	{ -3.4, 2.0, 3.2 }, { 0, 3.2, 3.3 }, { 3.4, 2.0, 3.2 } }

local function show(p, on)
	p.Transparency = on and 0 or 1
end

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 16
	local model = B.model
	local now = os.clock()
	local moving = model:GetAttribute("Moving") == true
	B.walk = smoothNum(B, "walkS", moving and 1 or 0, 6, dt)
	B.stridePhase = (B.stridePhase or 0) + dt * 4.4 * math.max(B.walk, 0.1)
	local stride = math.sin(B.stridePhase) * B.walk
	local rate = P.snap and 60 or (P.rate or 14)
	local crouch = smoothNum(B, "crouchS", clamp(P.crouch or 0, -0.3, 1), rate, dt)
	local sit = smoothNum(B, "sitS", clamp(P.sit or 0, 0, 1), rate * 0.5, dt)
	local lean = smoothNum(B, "leanS", (P.lean or 0) + 0.05 * B.walk, rate, dt)
	local twist = smoothNum(B, "twistS", (P.twist or 0) + 0.08 * stride, rate, dt)
	local headPitch = smoothNum(B, "headS", P.headPitch or 0, rate, dt)
	local rHandT = smoothVec(B, "rHandS", P.rHand or (REST_R + V3(0, 0, -stride * 1.5)), rate, dt)
	local lHandT = smoothVec(B, "lHandS", P.lHand or (REST_L + V3(0, 0, stride * 1.2)), rate, dt)
	local ballK = smoothNum(B, "ballS", clamp(P.ball or 0, 0, 1), P.snap and 60 or 20, dt)
	local mouthOpen = smoothNum(B, "mouthS", clamp(P.mouth or 0, 0, 1), 18, dt)
	local cheeks = smoothNum(B, "cheekS", clamp(P.cheeks or 0, 0, 1), 12, dt)
	local fall = smoothNum(B, "fallS", clamp(P.fall or 0, 0, 1), 5, dt)
	local faceDown = smoothNum(B, "downS", clamp(P.faceDown or 0, 0, 1), 7, dt)
	local rFoot = smoothVec(B, "rFootS", P.rFoot or V3(0, 0, 0), P.snap and 60 or 16, dt)
	local glare = smoothNum(B, "glareS", clamp(P.glare or 0, 0, 1), 10, dt)
	local sx, sy = P.sx or 1, P.sy or 1
	local sink = P.sink or 0
	local fade = P.fade or 0
	local phase = num(model:GetAttribute("Phase"), 1)
	local piston = B.phase2Look or phase >= 2
	local rage = phase >= 3 or B.berserkLook
	local flash = B.flashAt and (now - B.flashAt) < 0.1
	local rageColor = def.RageColor or RED

	local jitter = V3(0, 0, 0)
	if (P.shake or 0) > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	-- (flat on his back or his face, his great belly holds him up off the floor)
	local rest = (4 * fall + 3.5 * faceDown) * u
	local groundPos = ground + jitter + V3(0, (P.lift or 0) + rest - sink * 30 * u, 0)
	local look = unitOr(flat(facing), V3(0, 0, -1))
	if P.spinA then
		look = turnY(look, P.spinA)
	end
	local base = CFrame.lookAt(groundPos, groundPos + look)
	if fall > 0 then
		-- flat on his back: tipping over his heels
		base = base * CFrame.new(0, 0, 3 * u) * CFrame.Angles(fall * 1.45, 0, 0) * CFrame.new(0, 0, -3 * u)
	elseif faceDown > 0 then
		-- flat on his face (tripped): tipping over his toes
		base = base * CFrame.new(0, 0, -4 * u) * CFrame.Angles(-faceDown * 1.4, 0, 0) * CFrame.new(0, 0, 4 * u)
	end
	local forward = base.LookVector

	-- CURLED UP INTO A BALL (the Royal Roll)
	local balled = ballK > 0.5
	local R = BALL_R * u
	if balled then
		local r = R * (0.75 + 0.25 * ballK)
		local long, flatW, mid = 2 * r, 1.2 * r, 1.6 * r
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
		local front = cf * CFrame.new(0, 0, -r)
		body.ballFace.Size = V3(r * 0.9, r * 0.55, 0.8 * u)
		body.ballFace.CFrame = front * CFrame.new(0, -r * 0.1, -0.2 * u)
		for i = 1, 2 do
			local side = (i == 1) and -1 or 1
			local tusk = (i == 2) and r * 0.28 or r * 0.55 -- (the right one's the chipped one)
			body.ballTusks[i].Size = V3(0.9 * u, tusk, 0.9 * u)
			body.ballTusks[i].CFrame = front * CFrame.new(side * r * 0.22, -r * 0.36 - tusk / 2, -0.55 * u)
			body.ballEyes[i].Size = V3(0.9 * u, 0.7 * u, 0.3 * u)
			body.ballEyes[i].CFrame = front * CFrame.new(side * r * 0.3, r * 0.3, -0.15 * u)
		end
		body.ballCrown.Size = V3(r * 0.8, r * 0.35, r * 0.8)
		body.ballCrown.CFrame = cf * CFrame.new(0, r * 0.6, -r * 0.5)
	end
	for _, b in ipairs(body.ballBits) do
		show(b, balled and fade < 0.5)
	end

	-- LEGS: short and fat, bent out under all that weight, on broad hind
	-- flippers splayed out to the sides
	local hipY = (6.2 - 2.6 * math.max(crouch, 0) - 4.2 * sit) * u * sy
	local legX = (4.6 + 0.8 * math.max(crouch, 0) + 1.2 * sit) * u * sx
	local L1, L2 = 3.8 * u, 3.6 * u
	-- (the tip of his right flipper reaching for a spot: rFootAt)
	local footAt = typeof(P.rFootAt) == "Vector3" and P.rFootAt or nil
	if footAt then
		if not B.footAtS and B.toeAt then
			B.footAtS = B.toeAt -- (from where it is now)
		end
		footAt = smoothVec(B, "footAtS", footAt, P.snap and 60 or 16, dt)
	else
		B.footAtS = nil
	end
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local hip = base * V3(side * legX, hipY, 0.5 * u)
		local fz = -side * stride * 2.2 * u
		local liftFoot = math.max(0, -side * stride) * 1.0 * u
		local footDir = (base * CFrame.Angles(0, -side * SPLAY, 0)).LookVector
		local ankle
		if sit > 0.05 then
			local sitAnkle = base * V3(side * legX * 1.15, 1.2 * u, -6.5 * u)
			ankle = (base * V3(side * legX * 1.1, 1.3 * u + liftFoot, fz)):Lerp(sitAnkle, sit)
		else
			ankle = base * V3(side * legX * 1.1, 1.3 * u + liftFoot, fz)
		end
		if i == 2 then
			if footAt then
				ankle = footAt + base.UpVector * (1.3 * u) - footDir * (TOE * u)
			end
			if rFoot.Magnitude > 0.01 then
				ankle = ankle + base:VectorToWorldSpace(rFoot * u)
			end
		end
		local bend = unitOr(forward + base.RightVector * side * 0.5, forward)
		local knee, ankle2 = twoBone(hip, ankle, L1, L2, bend)
		stretch(body.thighs[i], hip, knee, 4.6 * u * sx, 4.6 * u, forward)
		stretch(body.shins[i], knee, ankle2, 4.0 * u * sx, 4.0 * u, forward)
		local af = CFrame.lookAt(ankle2, ankle2 + footDir, base.UpVector)
		body.anklets[i].Size = V3(4.7 * u * sx, 1.0 * u, 4.7 * u)
		body.anklets[i].CFrame = af * CFrame.new(0, 0.4 * u, 0)
		body.flippers[i].Size = V3(4.0 * u * sx, 1.4 * u, 3.8 * u)
		body.flippers[i].CFrame = af * CFrame.new(0, -0.6 * u, -1.3 * u)
		body.fans[i].Size = V3(5.4 * u * sx, 0.8 * u, 3.4 * u)
		body.fans[i].CFrame = af * CFrame.new(0, -1.0 * u, -3.6 * u)
		for k, cl in ipairs(body.toeClaws[i]) do
			cl.Size = V3(0.9, 0.7, 0.9) * u
			cl.CFrame = af * CFrame.new((k - 2) * 1.8 * u * sx, -0.9 * u, -5.5 * u)
		end
		if i == 2 then
			B.toeAt = af * V3(0, -1.2 * u, -TOE * u)
		end
	end

	-- THE UPPER BODY: from the hips, leaning, twisting
	local torso = base * CFrame.new(0, hipY, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, 0)
	local up, tlook, right = torso.UpVector, torso.LookVector, torso.RightVector
	local breathe = 1 + 0.035 * math.sin(now * 2)
	local bw = 16 * u * sx * breathe
	-- the belly: three rolls of blubber, the middle one widest, each paler
	-- down its front
	local fronts = {} -- (how far forward each roll's front comes, in his studs)
	for k, r in ipairs(ROLLS) do
		local y, h, wk, d, z, poke = r[1], r[2], r[3], r[4], r[5], r[6]
		body.rolls[k].Size = V3(bw * wk, h * u * sy, d * u * breathe)
		body.rolls[k].CFrame = torso * CFrame.new(0, y * u * sy, z * u)
		fronts[k] = z - d * breathe / 2 - poke
		body.rollFronts[k].Size = V3(bw * wk * 0.64, h * u * sy * 0.84, 4 * u)
		body.rollFronts[k].CFrame = torso * CFrame.new(0, y * u * sy, (fronts[k] + 2) * u)
	end
	-- (a deep crease under each of the top two rolls)
	for k, c in ipairs(body.creases) do
		local upper, lower = ROLLS[k + 1], ROLLS[k]
		c.Size = V3(bw * lower[3] * 0.62, 0.55 * u, 0.6 * u)
		c.CFrame = torso * CFrame.new(0, (upper[1] - upper[2] / 2 + 0.1) * u * sy, (fronts[k] - 0.2) * u)
	end
	-- the belt, low round his gut
	body.belt.Size = V3(bw * 0.93, 1.4 * u, 16 * u * breathe)
	body.belt.CFrame = torso * CFrame.new(0, 2.4 * u * sy, -1.0 * u)
	body.buckle.Size = V3(3.6, 2.6, 0.7) * u
	body.buckle.CFrame = torso * CFrame.new(0, 2.4 * u * sy, (-1.0 - 8 * breathe - 0.3) * u)
	body.buckleGem.Size = V3(1.2, 1.2, 0.4) * u
	body.buckleGem.CFrame = body.buckle.CFrame * CFrame.new(0, 0, -0.4 * u)
	-- THE SHOULDERS, under spiked gold pauldrons
	local shoulders = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local scf = torso * CFrame.new(side * SHOULDER_X * u * sx, SHOULDER_Y * u * sy, -0.4 * u)
		body.shoulders[i].Size = V3(5.6, 5.4, 6.4) * u
		body.shoulders[i].CFrame = scf
		shoulders[i] = scf.Position
		local plate = scf * CFrame.new(side * 0.8 * u, 2.6 * u, 0) * CFrame.Angles(0, 0, -side * 0.32)
		body.pauldrons[i].Size = V3(7.0, 2.2, 7.4) * u
		body.pauldrons[i].CFrame = plate
		body.pauldronRims[i].Size = V3(7.3, 0.6, 7.7) * u
		body.pauldronRims[i].CFrame = plate * CFrame.new(0, -1.2 * u, 0)
		body.pauldronLows[i].Size = V3(5.8, 1.6, 6.6) * u
		body.pauldronLows[i].CFrame = scf * CFrame.new(side * 2.7 * u, 0.3 * u, 0) * CFrame.Angles(0, 0, -side * 0.78)
		for k, sp in ipairs(body.spikes[i]) do
			-- (short and stubby: a thick base, a sharp tip)
			local h = ((k == 2) and 2.0 or 1.5) * u
			local at = plate * CFrame.new(side * (-1.9 + (k - 1) * 2.3) * u, 1.1 * u, 0) * CFrame.Angles(0, 0, -side * 0.12)
			sp.Size = V3(1.6 * u, h, 1.6 * u)
			sp.CFrame = at * CFrame.new(0, h / 2, 0)
			body.spikeTips[i][k].Size = V3(0.8, 1.2, 0.8) * u
			body.spikeTips[i][k].CFrame = at * CFrame.new(0, h + 0.55 * u, 0)
		end
	end
	-- the ermine collar
	-- (the ermine: a band of white fur round his shoulders and across his chest,
	-- little black tails dotted along it)
	local collar = torso * CFrame.new(0, (SHOULDER_Y + 0.4) * u * sy, -0.8 * u)
	body.collar.Size = V3(18 * u * sx, 2.7 * u, 13.8 * u)
	body.collar.CFrame = collar
	for k, spot in ipairs(body.ermine) do
		spot.Size = V3(0.45, 0.8, 0.3) * u
		spot.CFrame = collar * CFrame.new(({ -7.4, -5.2, -2.9, 2.9, 5.2, 7.4 })[k] * u * sx, (k % 2 == 0) and 0.35 * u or -0.35 * u, -6.98 * u)
	end
	-- the cape: from under the collar down behind him to the floor, flaring out
	-- as it falls, swinging as he moves
	local swing = 0.16 + 0.12 * B.walk + 0.06 * math.sin(now * 1.7)
	local capeTop = torso * V3(0, (SHOULDER_Y + 1.2) * u * sy, 6 * u)
	local capeMid = capeTop + torso:VectorToWorldSpace(V3(0, -1, math.sin(swing * 0.6))).Unit * (SHOULDER_Y * 0.55 * u * sy)
	local lowLen = math.max(SHOULDER_Y * 0.45 * u * sy + hipY - 1.5 * u, 2 * u)
	local capeEnd = capeMid + torso:VectorToWorldSpace(V3(0, -1, math.sin(swing + 0.12))).Unit * lowLen
	stretch(body.capeTop, capeTop, capeMid, 19 * u * sx, 0.9 * u, tlook)
	stretch(body.capeLow, capeMid, capeEnd, 21.5 * u * sx, 0.8 * u, tlook)
	body.capeHem.Size = V3(22 * u * sx, 1.3 * u, 1.3 * u)
	body.capeHem.CFrame = CFrame.lookAt(capeEnd, capeEnd + tlook)

	-- THE HEAD: low and forward on those shoulders
	local head = torso * CFrame.new(0, (SHOULDER_Y + 4.8) * u * sy, -2.6 * u) * CFrame.Angles(-headPitch, 0, 0)
	local face = head.LookVector
	body.head.Size = V3(8.4, 7.4, 8.0) * u
	body.head.CFrame = head
	body.headRound.Size = V3(9.4, 5.6, 7.0) * u
	body.headRound.CFrame = head * CFrame.new(0, -0.5 * u, 0.2 * u)
	-- (his jaw drops as he opens his mouth)
	body.chin.Size = V3(5.4, 2.0, 4.6) * u
	body.chin.CFrame = head * CFrame.new(0, (-4.1 - 1.6 * mouthOpen) * u, -2.9 * u)
	body.mouth.Size = V3(3.6 * u, 0.4 * u + 2.6 * u * mouthOpen, 0.4 * u)
	body.mouth.CFrame = head * CFrame.new(0, (-3.85 - 1.1 * mouthOpen) * u, -5.3 * u)
	-- the heavy brow, scowling (harder in round 3)
	local angry = rage and 0.5 or 0.28
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		body.brows[i].Size = V3(3.8, 1.3, 1.5) * u
		body.brows[i].CFrame = head * CFrame.new(side * 2.4 * u, 2.1 * u, -3.85 * u) * CFrame.Angles(0, 0, side * angry)
	end
	-- his eyes: little, deep-set, glowing - the left one (the scarred one)
	-- blind, pale and brightest; it never quite closes
	local eyeOpen = clamp(num(P.eyes, 1), 0, 1) * (1 - fade)
	local scarOpen = math.max(eyeOpen, clamp(num(P.scarEye, 0), 0, 1) * (1 - fade))
	local flare = 1 + 0.4 * glare
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local open = (i == 1) and scarOpen or eyeOpen
		local eye = body.eyes[i]
		local w, h = (i == 1) and 1.7 or 1.3, (i == 1) and 1.4 or 1.1
		eye.Size = V3(w * u * flare, math.max(h * u * open * flare, 0.05), 0.3 * u)
		eye.CFrame = head * CFrame.new(side * 2.5 * u, 0.9 * u, -4.05 * u)
		eye.Color = flash and WHITE or (rage and rageColor or ((i == 1) and (def.ScarEyeColor or YELLOW) or (def.EyeColor or GOLD)))
		eye.Transparency = (open < 0.05 or balled or fade > 0.5) and 1 or 0
	end
	B.eyeAt = body.eyes[1].Position
	-- (the good eye's pupil, rolling round when he's dizzy)
	local roll = (P.stars or 0) > 0.05 and V3(math.cos(now * 9) * 0.3 * u, math.sin(now * 9) * 0.25 * u, 0) or V3()
	body.pupil.Size = V3(0.5 * u, math.max(0.55 * u * eyeOpen, 0.05), 0.2 * u)
	body.pupil.CFrame = head * CFrame.new(2.35 * u + roll.X, 0.9 * u + roll.Y, -4.22 * u)
	body.pupil.Transparency = (eyeOpen < 0.05 or balled or fade > 0.5 or rage) and 1 or 0
	-- the muzzle: two big whiskery lobes (puffed out when he's got a mouthful),
	-- the snout on top with its nostrils, bristles, stiff whiskers
	local puff = 1 + 0.3 * cheeks
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local lobe = head * CFrame.new(side * 2.3 * u * puff, -2.0 * u, -5.2 * u)
		body.muzzle[i].Size = V3(4.2, 2.8, 3.4) * (u * puff)
		body.muzzle[i].CFrame = lobe
		body.muzzleV[i].Size = V3(3.2, 3.8, 3.0) * (u * puff)
		body.muzzleV[i].CFrame = lobe
		body.nostrils[i].Size = V3(0.9, 0.35, 0.8) * u
		body.nostrils[i].CFrame = head * CFrame.new(side * 1.1 * u * puff, (-0.1 + 0.9 * (puff - 1)) * u, -5.5 * u)
	end
	local lobeFront = (-5.2 - 1.7 * puff - 0.1) * u
	local BRISTLES = { { 1.1, -1.4 }, { 2.3, -1.8 }, { 3.4, -1.4 }, { 1.8, -2.7 } }
	for k, br in ipairs(body.bristles) do
		local side = (k <= 4) and -1 or 1
		local b = BRISTLES[(k - 1) % 4 + 1]
		br.Size = V3(0.4, 0.4, 0.3) * u
		br.CFrame = head * CFrame.new(side * b[1] * u * puff, b[2] * u, lobeFront)
	end
	for k, wk in ipairs(body.whiskers) do
		local side = (k <= 2) and -1 or 1
		local j = (k - 1) % 2
		local from = head * V3(side * 3.6 * u * puff, (-1.6 - j * 1.0) * u, -5.6 * u)
		local to = head * V3(side * (6.4 + j * 0.4) * u * puff, (-1.3 - j * 1.4) * u, -6.6 * u)
		stretch(wk, from, to, 0.3 * u, 0.3 * u, up)
	end
	-- THE TUSKS: long and ivory, hanging down past his chin over his chest
	-- (the right one snapped off short, a jagged end)
	local tA = head * V3(-1.9 * u, -3.4 * u, -5.4 * u)
	local tB = head * V3(-2.2 * u, -7.2 * u, -6.3 * u)
	local tC = head * V3(-1.8 * u, -10.2 * u, -6.6 * u)
	stretch(body.tusks[1], tA, tB, 1.4 * u, 1.4 * u, face)
	stretch(body.tuskTip, tB, tC, 1.1 * u, 1.1 * u, face)
	local cA = head * V3(1.9 * u, -3.4 * u, -5.4 * u)
	local cB = head * V3(2.15 * u, -6.3 * u, -6.1 * u)
	stretch(body.tusks[2], cA, cB, 1.4 * u, 1.4 * u, face)
	body.tuskChip.Size = V3(1.3, 0.8, 1.3) * u
	body.tuskChip.CFrame = CFrame.new(cB) * head.Rotation * CFrame.Angles(0.4, 0.3, 0.55)
	-- THE SCAR, stitched: pale - or burning red in round 3
	for k, p in ipairs(body.scar) do
		stretch(p, head * (SCAR[k] * u), head * (SCAR[k + 1] * u), 0.55 * u, 0.35 * u, face)
	end
	for k, st in ipairs(body.stitches) do
		local seg = ({ 1, 2, 4 })[k]
		local a, b = SCAR[seg], SCAR[seg + 1]
		local mid = head * ((a + b) / 2 * u)
		local across = head:VectorToWorldSpace((b - a).Unit):Cross(face)
		across = unitOr(across, right)
		stretch(st, mid - across * 0.75 * u, mid + across * 0.75 * u, 0.3 * u, 0.3 * u, face)
	end
	local scarColor, scarMat = def.ScarColor or RGB(232, 183, 150), Enum.Material.SmoothPlastic
	if rage then
		scarColor = rageColor:Lerp(RED_DARK, 0.5 * (0.5 - 0.5 * math.sin(now * 6)))
		scarMat = Enum.Material.Neon
	end
	if flash then
		scarColor = WHITE
	end
	for _, list in ipairs({ body.scar, body.stitches }) do
		for _, p in ipairs(list) do
			p.Color = scarColor
			if B.scarMat ~= scarMat then
				p.Material = scarMat
			end
		end
	end
	B.scarMat = scarMat

	-- THE CROWN: tall and spiked (round 3 knocks it off; putting it back on
	-- shows it again)
	local crownOn = P.crown == "on" or (P.crown ~= "off" and not rage)
	local crownCF = head * CFrame.new(0.3 * u, 4.6 * u, 0.3 * u) * CFrame.Angles(0, 0, 0.07)
	body.crown.Size = V3(8.2, 2.0, 7.6) * u
	body.crown.CFrame = crownCF
	body.crownRim.Size = V3(8.5, 0.6, 7.9) * u
	body.crownRim.CFrame = crownCF * CFrame.new(0, -0.9 * u, 0)
	for k, sp in ipairs(SPIKES) do
		local x, h, z = sp[1], sp[2], sp[3]
		body.crownPoints[k].Size = V3(1.0 * u, h * u, 1.0 * u)
		body.crownPoints[k].CFrame = crownCF * CFrame.new(x * u, (1.0 + h / 2) * u, z * u)
		body.crownTips[k].Size = V3(0.5, 0.9, 0.5) * u
		body.crownTips[k].CFrame = crownCF * CFrame.new(x * u, (1.0 + h + 0.4) * u, z * u)
	end
	for i, gem in ipairs(body.gems) do
		gem.Size = ((i == 2) and V3(1.5, 1.5, 0.4) or V3(1.0, 1.0, 0.4)) * u
		gem.CFrame = crownCF * CFrame.new((i - 2) * 2.5 * u, 0, -3.95 * u)
	end
	B.crownCF = crownCF
	local crownShow = crownOn and fade < 0.5 and not balled
	for _, list in ipairs({ { body.crown, body.crownRim }, body.crownPoints, body.crownTips, body.gems }) do
		for _, p in ipairs(list) do
			show(p, crownShow)
		end
	end
	B.mouthAt = head * V3(0, -3.9 * u, -5.4 * u)

	-- ARMS: from each shoulder to where the pose wants that flipper
	local hands = {}
	local wants = { torso * (lHandT * u), torso * (rHandT * u) }
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local bend = (right * side * 0.7 - up * 0.3 + tlook * 0.1)
		local elbow, hand = twoBone(shoulders[i], wants[i], ARM * u, ARM * u, bend.Unit)
		hands[i] = hand
		stretch(body.upperArms[i], shoulders[i], elbow, 4.6 * u, 4.6 * u, tlook)
		stretch(body.foreArms[i], elbow, hand, 4.2 * u, 4.2 * u, tlook)
		local wristDir = unitOr(hand - elbow, -up)
		body.bracers[i].Size = V3(4.9, 4.9, 2.0) * u
		body.bracers[i].CFrame = CFrame.lookAt(hand - wristDir * 2.1 * u, hand, tlook)
		local hcf = CFrame.lookAt(hand, hand + wristDir, tlook)
		body.hands[i].Size = V3(4.6, 2.8, 4.4) * u
		body.hands[i].CFrame = hcf
		for k, cl in ipairs(body.claws[i]) do
			cl.Size = V3(0.8, 0.7, 1.0) * u
			cl.CFrame = hcf * CFrame.new((k - 2) * 1.5 * u, -0.4 * u, -2.4 * u)
		end
	end
	B.handR, B.handL = hands[2], hands[1]

	-- THE GAVEL: in his right flipper, reaching for gavelAt (a world point) or
	-- pointing gavelDir (his body's space). Its head can fly off (headAt).
	local hand = hands[2]
	local dirW
	if typeof(P.gavelAt) == "Vector3" then
		dirW = unitOr(P.gavelAt - hand, torso:VectorToWorldSpace(REST_GAVEL))
	else
		dirW = torso:VectorToWorldSpace(unitOr(P.gavelDir or REST_GAVEL, REST_GAVEL))
	end
	dirW = smoothVec(B, "gavelS", dirW, P.snap and 60 or 16, dt)
	dirW = unitOr(dirW, -up)
	local len = HANDLE * u
	if typeof(P.gavelAt) == "Vector3" and P.gavelReach then
		len = clamp((P.gavelAt - hand).Magnitude, HANDLE * u * 0.6, HANDLE * u * 1.6)
	end
	local tip = hand + dirW * len
	local hw = piston and 6.4 or 5.8
	stretch(body.handle, hand - dirW * 2.0 * u, tip, 1.4 * u, 1.4 * u, tlook)
	body.pommel.Size = V3(2.2, 2.2, 2.2) * u
	body.pommel.CFrame = CFrame.lookAt(hand - dirW * 2.6 * u, hand, tlook)
	body.gCollar.Size = V3(2.1, 2.1, 1.1) * u
	body.gCollar.CFrame = CFrame.lookAt(tip - dirW * (hw / 2 + 0.55) * u, tip, tlook)
	local headPos = typeof(P.headAt) == "Vector3" and P.headAt or tip
	local headCF = CFrame.lookAt(headPos, headPos + dirW, tlook)
	body.gHead.Size = V3(9.2 * u, hw * u, hw * u)
	body.gHead.CFrame = headCF
	for k, f in ipairs(body.gFaces) do
		f.Size = V3(0.8 * u, (hw - 0.9) * u, (hw - 0.9) * u)
		f.CFrame = headCF * CFrame.new(((k == 1) and -4.9 or 4.9) * u, 0, 0)
	end
	for k, band in ipairs(body.gBands) do
		band.Size = V3(1.3 * u, (hw + 0.5) * u, (hw + 0.5) * u)
		band.CFrame = headCF * CFrame.new(((k == 1) and -3.2 or 3.2) * u, 0, 0)
	end
	-- (the spike on top, pointing on out along the handle)
	body.gSpike.Size = V3(1.6, 1.6, 2.6) * u
	body.gSpike.CFrame = headCF * CFrame.new(0, 0, -(hw / 2 + 1.2) * u)
	body.gSpikeTip.Size = V3(0.8, 0.8, 1.4) * u
	body.gSpikeTip.CFrame = headCF * CFrame.new(0, 0, -(hw / 2 + 3.0) * u)
	-- the runes: glowing as he winds up (the piston hammer's never quite go out)
	local runeK = smoothNum(B, "runeS", math.max(clamp(P.runes or 0, 0, 1), windUp(B)), 12, dt)
	runeK = math.max(runeK, piston and 0.35 or 0)
	local runeHot = rage and rageColor or (piston and ORANGE or (def.RuneColor or YELLOW))
	local runeColor = flash and WHITE or IRON_DARK:Lerp(runeHot, runeK)
	local e = hw / 2 + 0.06
	local RUNES = { { 0, e, 0, 4.2, 0.12, 0.9 }, { 0, -e, 0, 4.2, 0.12, 0.9 }, { 0, 0, e, 4.2, 0.9, 0.12 }, { 0, 0, -e, 4.2, 0.9, 0.12 } }
	for k, rn in ipairs(body.runes) do
		local r = RUNES[k]
		rn.Size = V3(r[4], r[5], r[6]) * u
		rn.CFrame = headCF * CFrame.new(r[1] * u, r[2] * u, r[3] * u)
		rn.Color = runeColor
	end
	B.runeGlow = runeK
	body.gCore.Size = V3(2.8 * u, (hw + 0.2) * u, 2.4 * u)
	body.gCore.CFrame = headCF
	body.gCore.Color = rage and rageColor or ORANGE
	show(body.gCore, piston and fade < 0.5 and not balled)
	for k, v in ipairs(body.gVents) do
		v.Size = V3(1.5, 1.5, 1.9) * u
		v.CFrame = headCF * CFrame.new(((k == 1) and -5.6 or 5.6) * u, hw * 0.3 * u, 0)
		show(v, piston and fade < 0.5 and not balled)
	end
	B.gavelHead = headPos
	-- the chain between the handle and a flying head
	local flying = typeof(P.headAt) == "Vector3" and (P.headAt - tip).Magnitude > 1
	for i, c in ipairs(body.chain) do
		if flying and fade < 0.5 then
			local a0 = tip:Lerp(P.headAt, (i - 1) / #body.chain)
			local a1 = tip:Lerp(P.headAt, i / #body.chain)
			stretch(c, a0, a1, 0.6 * u, 0.6 * u, (i % 2 == 0) and up or right)
			c.Transparency = 0
		else
			c.Transparency = 1
		end
	end

	-- DIZZY STARS round his head
	local stars = P.stars or 0
	for i, st in ipairs(body.stars) do
		if stars > 0.05 and fade < 0.5 then
			local a = now * 4 + i * (math.pi * 2 / 3)
			local p = balled and (groundPos + V3(math.cos(a) * 6 * u, 2 * R + 2 * u, math.sin(a) * 6 * u))
				or (head * V3(math.cos(a) * 6.5 * u, 6.5 * u, math.sin(a) * 6.5 * u))
			st.Size = V3(2.2, 2.2, 0.9) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, now * 5)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- where word bubbles hang, and the top of his head (over his crown)
	B.headTop = balled and (groundPos + V3(0, 2 * R + 1, 0)) or (head * V3(0, (crownShow and 9 or 5.5) * u, 0))
	body.anchor.CFrame = CFrame.new(B.headTop + V3(0, 2, 0))

	-- his shadow
	local shadowD = 20 * u * (1 - clamp((P.lift or 0) / 60, 0, 0.7))
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.06, 0), shadowD, 0.1)
	body.shadow.Transparency = (fade > 0.5 or sink > 0.4) and 1 or 0.35

	-- colours: the hit flash; a gold glow when he's carrying taxed coins
	local taxed = num(model:GetAttribute("Taxed"), 0) > 0 and (math.floor(now * 6) % 2 == 0)
	for _, rec in ipairs(body.tinted) do
		local c = rec.color
		if flash then
			c = WHITE
		elseif taxed then
			c = c:Lerp(GOLD, 0.35)
		end
		rec.part.Color = c
	end
	if not flash then
		-- (round 2's steel piston hammer; his face going blue as he chokes, or
		-- flushed red in round 3)
		body.gHead.Color = piston and (def.SteelColor or STEEL) or (def.IronColor or IRON)
		local headColor = (P.choke and BLUE) or (rage and (def.Color or HIDE):Lerp(RED, 0.3)) or nil
		if headColor then
			for _, p in ipairs(body.headParts) do
				p.Color = headColor
			end
		end
	end

	-- the body hides while he's a ball; popping into pixels at the end
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
-- a red disc on the floor, filling in until `untilT`, at `spotFn()` (a
-- spot, or nil to wait); blinking white at the end
local function redDisc(B, spotFn, radius, fromT, untilT, color)
	local disc = newPart("KingWarning", Enum.PartType.Cylinder, color or RED, Enum.Material.Neon, 1)
	local ring = newRing(28, color or RED, Enum.Material.Neon, 1)
	addTelegraph(B, {
		update = function(now)
			if now > untilT + 0.05 then
				return false
			end
			local spot = spotFn()
			if not spot then
				disc.Transparency, ring.parts[1].Transparency = 1, 1
				return true
			end
			spot = onFloor(spot)
			local k = clamp((now - fromT) / math.max(untilT - fromT, 0.05), 0, 1)
			placeDisc(disc, spot + V3(0, 0.12, 0), radius * 2 * (0.25 + 0.75 * k), 0.1)
			local blink = k > 0.8 and (math.floor(now * 12) % 2 == 0)
			disc.Color = blink and WHITE or (color or RED)
			disc.Transparency = lerp(0.7, 0.4, k)
			placeRing(ring, spot + V3(0, 0.14, 0), radius, 0.3, 0.6, 0.15)
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(ring)
		end,
	})
end

-- A shockwave rolling out along the floor: its radius at any moment is
-- exactly what the server tests (BossService's stepWaves)
local function waveRing(B, origin, t0, speed, reach, height, thickness, color)
	local wall = newRing(56, color or STONE, Enum.Material.SmoothPlastic, 0)
	local crest = newRing(56, WHITE, Enum.Material.Neon, 0.55)
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

-- a red lane on the floor from `c0` to `c1`, `width` wide
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
	L.strip.Size = V3(width, 0.12, math.max(len, 0.1))
	L.strip.CFrame = CFrame.lookAt(mid, mid + dir)
	L.strip.Transparency = locked and 0.45 or 0.72
	L.strip.Color = color
	for i, rim in ipairs({ L.rimL, L.rimR }) do
		local s = (i == 1) and -1 or 1
		local rm = mid + sideV * s * width / 2 + V3(0, 0.02, 0)
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

-- a wedge in front of him (Reach, Arc wide), filling in until `untilT`
local function wedge(B, reach, arcDeg, fromT, untilT, color, name)
	local N = 14
	local bits = {}
	for i = 1, N do
		bits[i] = newPart(name or "WedgeWarning", nil, color or RED, Enum.Material.Neon, 1)
	end
	local half = math.rad(arcDeg / 2)
	addTelegraph(B, {
		update = function(now)
			if now > untilT + 0.06 then
				return false
			end
			local c = onFloor(B.vpos)
			local dir = B.vfacing
			local k = clamp((now - fromT) / math.max(untilT - fromT, 0.05), 0, 1)
			local step = (half * 2) / N
			for i, p in ipairs(bits) do
				local ang = -half + (i - 0.5) * step
				local out = turnY(dir, ang)
				local r = reach * (0.35 + 0.65 * k)
				local pos = c + out * (r / 2) + V3(0, 0.14, 0)
				p.Size = V3(math.max(2 * r * math.sin(step / 2), 0.3), 0.12, r)
				p.CFrame = CFrame.lookAt(pos, pos + out)
				p.Transparency = lerp(0.75, 0.4, k)
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

-- dust puffing up where something heavy hits the floor
local function dust(B, at_, big)
	local c = onFloor(at_)
	burst(c + V3(0, 0.6, 0), DUST, big and 26 or 14, big and 26 or 16, big and 2.2 or 1.4, 0.6)
	if big then
		burst(c + V3(0, 0.4, 0), STONE_DARK, 14, 18, 1.6, 0.5)
	end
end

-- steam puffing from the piston hammer (round 2 on)
local function steam(B, big)
	if not (B.phase2Look or num(B.model:GetAttribute("Phase"), 1) >= 2) then
		return
	end
	local at_ = B.gavelHead or (B.vpos + V3(0, 10, 0))
	burst(at_ + V3(0, 2, 0), B.def.SteamColor or SILVER, big and 22 or 10, big and 18 or 10, big and 2.4 or 1.6, 0.8, true)
end

-- A BOLT OF LIGHTNING from high in the storm down to `to`: a jagged neon
-- line that flickers twice and is gone, the sky flashing with it, and its
-- thunder a moment later (sooner, the closer it is). `big` = a brighter,
-- thicker one (his entrance, his rounds).
local BOLT = RGB(192, 203, 220)
local function strike(B, to, big)
	local phase = num(B.model:GetAttribute("Phase"), 1)
	local red = phase >= 3 and B.stateNow ~= "Dormant" and B.stateNow ~= "Resetting"
	local color = red and (B.def.RageColor or RED) or BOLT
	B.skyFlashAt, B.skyFlashBig = os.clock(), big and 1 or 0.55
	local top = to + V3((math.random() - 0.5) * 40, 160 + math.random() * 40, (math.random() - 0.5) * 40)
	local n = big and 9 or 7
	local pts = { top }
	for i = 1, n - 1 do
		local k = i / n
		local wob = (1 - k * 0.7) * (big and 11 or 8)
		pts[i + 1] = top:Lerp(to, k) + V3((math.random() - 0.5) * 2 * wob, 0, (math.random() - 0.5) * 2 * wob)
	end
	pts[n + 1] = to
	local parts = {}
	local w = big and 1.8 or 1.2
	for i = 1, n do
		local seg = newPart("Lightning", nil, color, Enum.Material.Neon, 1)
		stretch(seg, pts[i], pts[i + 1], w, w)
		parts[i] = seg
	end
	-- (and a fork off it, part of the way down)
	local j = math.floor(n * 0.4)
	local fork = pts[j] + V3((math.random() - 0.5) * 50, -30 - math.random() * 20, (math.random() - 0.5) * 50)
	local f1 = newPart("Lightning", nil, color, Enum.Material.Neon, 1)
	stretch(f1, pts[j], fork, w * 0.6, w * 0.6)
	table.insert(parts, f1)
	local born = os.clock()
	addTelegraph(B, {
		update = function()
			local age = os.clock() - born
			if age > 0.3 then
				return false
			end
			local on = age < 0.09 or (age > 0.14 and age < 0.22)
			for _, p in ipairs(parts) do
				p.Transparency = on and 0 or 1
			end
			return true
		end,
		cleanup = function()
			for _, p in ipairs(parts) do
				p:Destroy()
			end
		end,
	})
	-- the thunder: a crack right away close by, a rumble later far off
	local cam = workspace.CurrentCamera
	local ear = cam and cam.CFrame.Position or to
	local delay = clamp((ear - to).Magnitude / 340, 0.03, 1.2)
	at(B, serverNow() + delay, function()
		playSound(B.def, "Thunder", to, big and 1 or 0.75)
	end)
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- (the gavel raised high behind his head, both hands on it)
local OVERHEAD_R = V3(3, 21, 3)
local OVERHEAD_L = V3(-1.5, 20, 3)
local OVERHEAD_DIR = V3(0, 0.25, 1)

-- (asleep on his throne: his flippers on his belly and the gavel, its head
-- resting on the step)
local SEAT_R = V3(10.5, 5, -5)
local SEAT_L = V3(-6.5, 5.5, -8.9)
local SEAT_GAVEL = V3(0.2, -1, -0.35)

-- ASLEEP ON HIS THRONE: slumped back, chin on his chest, snoring - but the
-- scarred eye never quite closes
function Poses.Dormant(B, t, P)
	local seat, face = throneSeat(B)
	P.override, P.facing = seat, face
	P.lift = ThronePlan.SeatHeight
	P.sit = 1
	P.eyes = 0
	P.scarEye = 0.3
	P.lean = -0.06
	P.headPitch = 0.32 + 0.04 * math.sin(os.clock() * 1.1)
	P.rHand, P.lHand = SEAT_R, SEAT_L
	P.gavelDir = SEAT_GAVEL
	P.sy = 1 + 0.03 * math.sin(os.clock() * 1.4)
	P.mouth = 0.12 + 0.12 * math.sin(os.clock() * 1.4)
	local _ = t
end

-- THE ENTRANCE's beats (seconds from when he wakes). He lands - and the VS
-- splash slams in - at IntroDelay.
local function wakeBeats(def)
	local land = def.IntroDelay or def.WakeTime * 0.57
	return {
		eyes = 0.25, -- his eyes snap open (the lightning struck at 0)
		stand0 = 0.55, -- he heaves himself up...
		stand1 = land - 1.9, -- ...standing tall on his throne
		strike = land - 1.6, -- the gavel raised into the storm: lightning hits it
		crouch = land - 1.15, -- he crouches...
		leap = land - 0.95, -- ...and leaps
		land = land, -- SLAM: the courtyard shakes
		laugh = land + 0.7, -- up tall, laughing, the gavel on his shoulder
		slam = def.WakeTime - 0.45, -- "KNEEL!": the gavel slammed on the floor
	}
end

-- WAKING UP: THE ENTRANCE. Lightning; his eyes light up; he stands up on his
-- throne and raises the gavel into the storm - it's struck, its runes blaze
-- - then he leaps down in front of you, lands with a slam that shakes the
-- courtyard, and laughs
function Poses.Wake(B, t, P)
	local W = wakeBeats(B.def)
	local seat, face = throneSeat(B)
	if t < W.leap then
		P.override, P.facing = seat, face
		P.lift = ThronePlan.SeatHeight
		if t < W.eyes then
			P.sit, P.eyes, P.scarEye = 1, 0, 0.3
			P.headPitch = 0.32
			P.rHand, P.lHand = SEAT_R, SEAT_L
			P.gavelDir = SEAT_GAVEL
			return
		end
		P.eyes = 1
		P.glare = (t < W.eyes + 0.5) and 1 or 0
		if t < W.stand0 then
			P.sit = 1
			P.headPitch = lerp(0.32, -0.1, smooth((t - W.eyes) / (W.stand0 - W.eyes)))
			P.rHand, P.lHand = SEAT_R, SEAT_L
			P.gavelDir = SEAT_GAVEL
			return
		end
		if t < W.stand1 then
			-- heaving himself up onto his feet
			local k = smooth((t - W.stand0) / (W.stand1 - W.stand0))
			P.sit = 1 - k
			P.lean = 0.15 * math.sin(k * math.pi)
			P.headPitch = -0.1
			P.rHand = SEAT_R:Lerp(REST_R, k)
			P.lHand = SEAT_L:Lerp(V3(-11, 9, -3), k)
			P.gavelDir = SEAT_GAVEL:Lerp(REST_GAVEL, k)
			return
		end
		if t < W.crouch then
			-- the gavel raised high into the storm (struck by lightning at W.strike)
			local k = smooth((t - W.stand1) / (W.strike - W.stand1))
			local struck = t >= W.strike
			P.rHand = REST_R:Lerp(V3(5, 23, 1), k)
			P.lHand = V3(-11, 9, -3):Lerp(V3(-10, 14, -2), k)
			P.gavelDir = REST_GAVEL:Lerp(V3(0.15, 1, 0.1), k)
			P.headPitch = -0.35 * k
			P.mouth = struck and 0.8 or 0.2
			P.runes = struck and 1 or 0
			P.glare = (struck and t < W.strike + 0.4) and 1 or 0
			P.shake = struck and 0.12 or 0
			return
		end
		-- crouching to leap
		local k = smooth((t - W.crouch) / (W.leap - W.crouch))
		P.crouch = 0.7 * k
		P.rHand = V3(5, 23, 1):Lerp(V3(11, 10, 3), k)
		P.lHand = V3(-11, 10, 3)
		P.gavelDir = V3(0.15, 1, 0.1):Lerp(V3(0.5, 0.5, 0.6), k)
		P.runes = 1
		return
	end
	if t < W.land then
		-- the leap: off his throne, high over the steps, down in front of you
		local k = (t - W.leap) / (W.land - W.leap)
		P.override = seat:Lerp(homeSpot(B), k)
		P.facing = face
		P.lift = lerp(ThronePlan.SeatHeight, 0, k) + math.sin(k * math.pi) * 20
		P.rHand, P.lHand = OVERHEAD_R, OVERHEAD_L
		P.gavelDir = OVERHEAD_DIR
		P.lean = lerp(-0.2, 0.3, k)
		P.runes = 1
		P.sy = 1 + 0.08 * math.sin(k * math.pi)
		return
	end
	if t < W.laugh then
		-- SLAM: landed in a deep crouch, the gavel down
		local e = t - W.land
		local w = clamp(e / 0.5, 0, 1)
		P.crouch = 0.9 * (1 - w) + 0.2 * w
		P.sy = 1 - 0.25 * (1 - w)
		P.sx = 1 + 0.18 * (1 - w)
		P.rHand, P.lHand = V3(2, 6, -10), V3(-1.5, 6.5, -10)
		P.gavelDir = V3(0, -0.9, -0.5)
		P.snap = e < 0.08
		P.runes = 1 - w
		return
	end
	if t < W.slam then
		-- up tall, the gavel on his shoulder, laughing (belly bouncing)
		local e = t - W.laugh
		P.rHand = V3(9, 17, 1)
		P.gavelDir = V3(-0.2, 0.3, 1)
		P.lHand = V3(-7, 7, -9)
		P.mouth = 0.7 + 0.3 * math.sin(e * 22)
		P.sy = 1 + 0.05 * math.sin(e * 22)
		P.headPitch = -0.35
		return
	end
	-- "KNEEL!": the gavel slammed down in front of him
	P.rHand = V3(4, 4, -12)
	P.gavelDir = V3(0, -0.8, -1)
	P.lHand = V3(-8, 10, -6)
	P.mouth = 1
	P.headPitch = -0.2
	P.snap = t - W.slam < 0.08
end

-- EVERYONE'S GONE: a scornful snort... a leap back up onto his throne, and he
-- settles down to sleep
function Poses.Reset(B, t, P)
	local seat, face = throneSeat(B)
	local from = B.resetFrom or seat
	if t < 0.55 then
		P.override = from
		P.rHand, P.lHand = V3(10, 11, -1), V3(-10, 11, -1)
		P.headPitch = 0.1
		P.mouth = 0.4
		return
	end
	if t < 1.45 then
		local k = (t - 0.55) / 0.9
		P.override = from:Lerp(seat, k)
		P.lift = lerp(0, ThronePlan.SeatHeight, k) + math.sin(k * math.pi) * 16
		-- (turning round in the air to land facing the gate)
		P.facing = blendDir(unitOr(flat(seat - from), face), face, smooth(clamp((k - 0.4) / 0.6, 0, 1)))
		P.crouch = (k > 0.85) and 0.4 or 0
		P.rHand, P.lHand = V3(10, 12, 2), V3(-10, 12, 2)
		return
	end
	P.override, P.facing = seat, face
	P.lift = ThronePlan.SeatHeight
	local k = smooth((t - 1.45) / 0.45)
	P.sit = k
	P.eyes = 1 - smooth((t - 1.6) / 0.35)
	P.scarEye = 0.3
	P.rHand = V3(10, 12, 2):Lerp(SEAT_R, k)
	P.lHand = V3(-10, 12, 2):Lerp(SEAT_L, k)
	P.gavelDir = REST_GAVEL:Lerp(SEAT_GAVEL, k)
end

-- ROYAL SMASH: the gavel up over his head... SMASH... stuck in the floor
function Poses.RoyalSmash(B, t, P)
	local a = B.def.Attacks.RoyalSmash
	if t < a.Tell then
		local k = smooth(t / (a.Tell * 0.7))
		P.rHand = REST_R:Lerp(OVERHEAD_R, k)
		P.lHand = REST_L:Lerp(OVERHEAD_L, k)
		P.gavelDir = REST_GAVEL:Lerp(OVERHEAD_DIR, k)
		P.lean = -0.15 * k
		P.headPitch = -0.15 * k
		P.snap = false
		return
	end
	local spot = slot(B, 1)
	local e = t - a.Tell
	P.rHand = V3(2, 6, -10)
	P.lHand = V3(-1.5, 6.5, -10)
	P.lean = 0.35
	P.crouch = 0.35
	P.snap = e < 0.12
	if spot then
		P.gavelAt = onFloor(spot) + V3(0, 3, 0)
		P.gavelReach = true
	else
		P.gavelDir = V3(0, -0.8, -1)
	end
	if e > 0.3 and e < a.Stuck then
		-- stuck: tugging at it, grunting
		P.shake = 0.15
		P.lean = 0.3 + 0.05 * math.sin(e * 18)
		P.mouth = 0.4
	end
end

-- GAVEL SWEEP: pulled back to one side... and swept round in front
function Poses.GavelSweep(B, t, P)
	local a = B.def.Attacks.GavelSweep
	local side = num(B.model:GetAttribute("ActN"), 1)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.rHand = REST_R:Lerp(V3(10 * side, 10, 5), k)
		P.lHand = REST_L:Lerp(V3(6 * side, 10, 3), k)
		P.gavelDir = REST_GAVEL:Lerp(V3(side, 0.1, 0.5), k)
		P.twist = side * 0.45 * k
		P.crouch = 0.2 * k
		return
	end
	local e = t - a.Tell
	local k = clamp(e / 0.22, 0, 1)
	local ang = lerp(math.rad(80), math.rad(-100), easeOut(k)) * side
	local d = V3(math.sin(ang), -0.12, -math.cos(ang))
	P.gavelDir = d
	P.rHand = V3(d.X * 9, 9, d.Z * 9)
	P.lHand = V3(d.X * 7 - side * 1.5, 9, d.Z * 7)
	P.twist = -side * 0.4 * k
	P.crouch = 0.2
	P.snap = true
end

-- BELLY BOUNCE: crouch... up into the air... belly-first onto your shadow
function Poses.BellyBounce(B, t, P)
	local a = B.def.Attacks.BellyBounce
	local n = num(B.model:GetAttribute("ActN"), 1)
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.crouch = 0.7 * k
		P.sy = 1 - 0.12 * k
		P.sx = 1 + 0.1 * k
		P.rHand, P.lHand = V3(10, 5, 2), V3(-10, 5, 2)
		return
	end
	local e = t - a.Tell
	local cycle = a.Air + a.Gap
	local i = math.min(math.floor(e / cycle), n - 1)
	local within = e - i * cycle
	if within < a.Air then
		local k = within / a.Air
		P.lift = math.sin(k * math.pi) * a.Height
		P.lean = lerp(-0.2, 0.9, k) -- belly first
		P.rHand, P.lHand = V3(10, 16, 1), V3(-10, 16, 1)
		P.gavelDir = V3(0.6, 0.6, 0.3)
		P.sy = 1 + 0.1 * math.sin(k * math.pi)
	else
		-- (squashed flat by the landing, springing back up)
		local w = clamp((within - a.Air) / 0.35, 0, 1)
		P.sy = 1 - 0.22 * (1 - w)
		P.sx = 1 + 0.2 * (1 - w)
		P.lean = 0.6 * (1 - w)
		P.crouch = 0.4 * (1 - w)
		P.snap = within - a.Air < 0.08
	end
end

-- ROYAL DECREE: "GUARDS!" - left hand up, pointing, mouth wide
function Poses.RoyalDecree(B, t, P)
	local a = B.def.Attacks.RoyalDecree
	local k = smooth(t / (a.Tell * 0.6))
	P.lHand = REST_L:Lerp(V3(-4, 23, -6), k)
	P.mouth = (t > a.Tell * 0.4 and t < a.Tell + 0.4) and 1 or 0.2
	P.headPitch = -0.2 * k
	P.gavelDir = V3(0.3, -0.5, -0.8)
end

-- TOE STOMP: his right flipper up... STAMP, its tip coming down right on
-- the spot (slot 1). Then it stays out there, glowing (punch it!)
function Poses.ToeStomp(B, t, P)
	local a = B.def.Attacks.ToeStomp
	local spot = slot(B, 1)
	if t < a.Tell then
		local k = smooth(t / (a.Tell * 0.6))
		P.lean = -0.1 * k
		P.rHand, P.lHand = V3(11, 9, 0), V3(-11, 9, 0)
		if spot then
			-- (over the spot, up high... and down in the last moment)
			P.rFootAt = onFloor(spot)
			P.rFoot = V3(0, 7 * (1 - clamp((t - (a.Tell - 0.12)) / 0.12, 0, 1)), 0)
		else
			P.rFoot = V3(0, 7 * k, -3 * k)
		end
		return
	end
	if spot then
		P.rFootAt = onFloor(spot)
	else
		P.rFoot = V3(0, 0, -3)
	end
	P.lean = 0.1
	P.snap = t - a.Tell < 0.1
	P.headPitch = 0.25 -- looking down at it
end

-- OW! MY TOE!: hopping round on his left foot, holding the right one
function Poses.ToeHop(B, t, P)
	local hop = math.abs(math.sin(t * 7))
	P.lift = hop * 3
	P.rFoot = V3(-2, 9, 0)
	P.rHand = V3(3, 5, -3)
	P.lHand = V3(-10, 12 + hop * 2, -1)
	P.mouth = 0.9
	P.eyes = 0.3
	P.twist = math.sin(t * 3) * 0.5
	P.gavelDir = V3(1, -0.2, 0.3)
	local _ = B
end

-- TAX COLLECTOR: rubbing his hands... arms up: coins pour down
function Poses.TaxCollector(B, t, P)
	local a = B.def.Attacks.TaxCollector
	if t < a.Tell then
		local rub = math.sin(t * 22) * 0.8
		P.rHand, P.lHand = V3(1.5 + rub, 9, -9), V3(-1.5 - rub, 9, -9)
		P.gavelDir = V3(0, 1, 0.3)
		P.mouth = 0.3
		return
	end
	P.rHand, P.lHand = V3(9, 21, -2), V3(-9, 21, -2)
	P.gavelDir = V3(0.3, 1, 0)
	P.headPitch = -0.3
	P.mouth = 0.8
end

-- TRIPLE SLAM (round 2): raised and slammed, three times, stepping in
function Poses.TripleSlam(B, t, P)
	local a = B.def.Attacks.TripleSlam
	for k = 1, a.Slams do
		local hitAt = a.Tell + (k - 1) * a.Gap
		local upFrom = (k == 1) and 0 or hitAt - a.Gap + 0.15
		if t < hitAt then
			local kk = smooth((t - upFrom) / math.max(hitAt - upFrom - 0.12, 0.1))
			P.rHand = V3(2, 6, -10):Lerp(OVERHEAD_R, kk)
			P.lHand = V3(-1.5, 6.5, -10):Lerp(OVERHEAD_L, kk)
			P.gavelDir = V3(0, -0.8, -1):Lerp(OVERHEAD_DIR, kk)
			P.lean = -0.1 * kk
			return
		end
		if t < hitAt + 0.15 or k == a.Slams then
			local spot = slot(B, k)
			P.rHand, P.lHand = V3(2, 6, -10), V3(-1.5, 6.5, -10)
			P.lean, P.crouch = 0.35, 0.3
			if spot then
				P.gavelAt = onFloor(spot) + V3(0, 3.3, 0)
				P.gavelReach = true
			else
				P.gavelDir = V3(0, -0.8, -1)
			end
			P.snap = t < hitAt + 0.1
			if t < hitAt + 0.15 then
				return
			end
		end
	end
end

-- HAMMER TORNADO (round 2): gavel out, round and round... then dizzy
function Poses.HammerTornado(B, t, P)
	local a = B.def.Attacks.HammerTornado
	local k = smooth(t / a.Tell)
	P.rHand = REST_R:Lerp(V3(11, 12, -2), k)
	P.lHand = REST_L:Lerp(V3(8, 12, -4), k)
	P.gavelDir = REST_GAVEL:Lerp(V3(1, 0.05, 0), k)
	P.crouch = 0.15 * k
	if t >= a.Tell and t < a.Tell + a.Time then
		P.spinA = (t - a.Tell) * 11
		return
	end
	if t >= a.Tell + a.Time then
		P.stars = 1
		P.lean = math.sin(os.clock() * 3) * 0.15
		P.twist = math.sin(os.clock() * 2.4) * 0.3
		P.rHand, P.lHand = V3(10, 4, 0), V3(-10, 4, 0)
		P.gavelDir = V3(0.5, -0.8, 0)
	end
end

-- BIG GULP (round 2): leaning back, mouth wide, breathing in... GULP,
-- cheeks full, chewing... PTOO... and a huge BURP
function Poses.BigGulp(B, t, P)
	local a = B.def.Attacks.BigGulp
	local inhaleEnd = a.Tell + a.Inhale
	if t < inhaleEnd then
		local k = smooth(t / (a.Tell + 0.3))
		P.mouth = k
		P.lean = -0.25 * k
		P.headPitch = -0.1 * k
		P.sy = 1 + 0.08 * clamp((t - a.Tell) / a.Inhale, 0, 1) -- (swelling up as he breathes in)
		P.sx = 1 + 0.06 * clamp((t - a.Tell) / a.Inhale, 0, 1)
		P.rHand, P.lHand = V3(11, 8, 2), V3(-11, 8, 2)
		return
	end
	local swallowed = slot(B, 1) ~= nil
	if t < inhaleEnd + a.Chew then
		P.mouth = 0
		P.cheeks = swallowed and 1 or 0.4
		P.sy = 1 + 0.04 * math.sin(t * 20)
		P.rHand, P.lHand = V3(4, 6, -8), V3(-4, 6, -8)
		return
	end
	if t < inhaleEnd + a.Chew + 0.3 then
		P.mouth = 0.6
		P.lean = 0.3
		return
	end
	-- BURP
	P.mouth = (t < inhaleEnd + a.Chew + 1.0) and 1 or 0.3
	P.lean = (t < inhaleEnd + a.Chew + 1.0) and 0.2 or 0
	P.headPitch = -0.2
	P.sy = 1 - 0.05 * math.sin(t * 16)
end

-- ROCKET HAMMER (round 2): the gavel levelled at you... the head fires out
-- on its chain, and is yanked back
function Poses.RocketHammer(B, t, P)
	local a = B.def.Attacks.RocketHammer
	P.rHand, P.lHand = V3(3, 10, -9), V3(-1, 10, -8)
	P.gavelDir = V3(0, 0.05, -1)
	P.crouch = 0.2
	local from, to = slot(B, 1), slot(B, 2)
	if not (from and to) or t < a.Tell then
		P.shake = t > a.Tell * 0.6 and 0.08 or 0
		return
	end
	local travel = flat(to - from).Magnitude / a.Speed
	local e = t - a.Tell
	local k
	if e < travel then
		k = e / travel
	elseif e < travel + a.Hold then
		k = 1
	else
		k = 1 - clamp((e - travel - a.Hold) / travel, 0, 1)
	end
	if k > 0.02 then
		local p = onFloor(from):Lerp(onFloor(to), k) + V3(0, 4, 0)
		P.headAt = p
	end
	P.lean = 0.15
	P.snap = true
end

-- THE ROYAL FEAST (round 2): he plonks down and eats, a leg in each hand
function Poses.RoyalFeast(B, t, P)
	local a = B.def.Attacks.RoyalFeast
	local k = smooth(t / a.Tell)
	P.sit = k
	P.gavelDir = V3(1, -0.3, 0.4)
	if t < a.Tell then
		P.rHand, P.lHand = V3(9, 8, -4), V3(-9, 8, -4)
		P.mouth = 0.5
		return
	end
	local chew = math.floor((t - a.Tell) * 3) % 2
	P.rHand = chew == 0 and V3(2, 17, -8) or V3(6, 9, -9)
	P.lHand = chew == 1 and V3(-2, 17, -8) or V3(-6, 9, -9)
	P.mouth = chew == 0 and 0.7 or 0.2
	P.cheeks = 0.5
	P.headPitch = 0.1
end

-- CHOKING on it: hands at his throat, face going blue, eyes bulging
function Poses.Choke(B, t, P)
	P.sit = 0.6
	P.rHand, P.lHand = V3(2, 15, -6), V3(-2, 15, -6)
	P.mouth = 0.6
	P.eyes = 1
	P.choke = true
	P.shake = 0.2
	P.headPitch = -0.2 + 0.1 * math.sin(t * 14)
	P.gavelDir = V3(1, -0.5, 0.3)
	P.stars = t > 1 and 1 or 0
	local _ = B
end

-- THE ROYAL ROLL (round 2): tucked into a ball, revving on the spot, rolling
function Poses.RoyalRoll(B, t, P)
	local a = B.def.Attacks.RoyalRoll
	if t < a.Tell then
		local k = clamp(t / (a.Tell * 0.5), 0, 1)
		P.crouch = 0.8 * k
		P.ball = (t > a.Tell * 0.35) and 1 or 0
		P.ballSpin = (t > a.Tell * 0.35) and ((t - a.Tell * 0.35) ^ 2 * 30) or 0
		return
	end
	local total = B.rollTotal or 1
	local e = t - a.Tell
	if e < total then
		P.ball = 1
		P.ballSpin = (a.Tell * 0.65) ^ 2 * 30 + e * a.Speed / (BALL_R * B.def.Size / 16) -- (rolling, not skidding)
		P.snap = true
		return
	end
	P.stars = 1
	P.lean = math.sin(os.clock() * 4) * 0.12
	P.twist = math.sin(os.clock() * 3) * 0.2
	P.rHand, P.lHand = V3(11, 4, -1), V3(-11, 4, -1)
end

-- EARTHQUAKE (round 3): a deep crouch... up, up, up... and DOWN
function Poses.Earthquake(B, t, P)
	local a = B.def.Attacks.Earthquake
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.crouch = 0.8 * k
		P.rHand, P.lHand = V3(10, 6, 2), V3(-10, 6, 2)
		return
	end
	local e = t - a.Tell
	if e < a.Air then
		local k = e / a.Air
		P.lift = math.sin(k * math.pi) * 46
		P.rHand, P.lHand = OVERHEAD_R, OVERHEAD_L
		P.gavelDir = OVERHEAD_DIR
		P.sy = 1 + 0.08 * math.sin(k * math.pi)
		return
	end
	local w = clamp((e - a.Air) / 0.4, 0, 1)
	P.crouch = 0.9 * (1 - w)
	P.sy = 1 - 0.3 * (1 - w)
	P.sx = 1 + 0.2 * (1 - w)
	P.rHand, P.lHand = V3(2, 6, -10), V3(-1.5, 6.5, -10)
	P.gavelDir = V3(0, -0.9, -0.5)
	P.snap = e - a.Air < 0.08
end

-- CROWN GRAB (round 3): his crown flies off to one side; he lumbers after it,
-- arms out, grabbing
function Poses.CrownGrab(B, t, P)
	local a = B.def.Attacks.CrownGrab
	P.crown = "off"
	if t < a.Tell then
		P.headPitch = -0.3
		P.mouth = 0.8
		P.lHand = V3(-3, 22, -3)
		return
	end
	local step = math.sin(t * 9)
	P.lean = 0.25
	P.rHand = V3(8, 11 + step, -9)
	P.lHand = V3(-8, 11 - step, -9)
	P.gavelDir = V3(0.3, 0.6, -0.8)
	P.mouth = 0.5
	B.walk = 1
end

-- TRIPPED: flat on his face, legs kicking
function Poses.Tripped(B, t, P)
	P.crown = "off"
	P.faceDown = 1
	P.stars = t > 0.6 and 1 or 0
	P.rHand, P.lHand = V3(11, 12, -4), V3(-11, 12, -4)
	P.rFoot = V3(0, 3 + 2 * math.sin(t * 8), 2)
	P.gavelDir = V3(1, 0, -0.3)
	local _ = B
end

-- CROWNED: he jams it back on and ROARS (it pops right back off after)
function Poses.Crowned(B, t, P)
	P.crown = (t < 0.9) and "on" or "off"
	P.mouth = (t > 0.3) and 1 or 0.4
	P.headPitch = -0.35
	P.rHand, P.lHand = V3(10, 16, -2), V3(-10, 16, -2)
	P.gavelDir = V3(0.2, 1, 0.2)
	P.shake = (t > 0.35 and t < 0.9) and 0.2 or 0
	local _ = B
end

-- "GUILTY!" (round 3): banging the gavel like a judge, again and again
function Poses.Guilty(B, t, P)
	local a = B.def.Attacks.Guilty
	local bang = (t < a.Tell + 0.8) and math.abs(math.sin(t * 9)) or 0.3
	P.rHand = V3(6, 8 + bang * 6, -9)
	P.gavelDir = V3(0, lerp(-0.9, 0.5, bang), -0.5)
	P.lHand = V3(-8, 12, -6)
	P.mouth = (t > a.Tell * 0.5 and t < a.Tell + 0.6) and 1 or 0.3
	P.headPitch = -0.15
end

-- THRONE TOSS (round 3): a leap back to the throne, heaving it overhead,
-- and hurling it
function Poses.ThroneToss(B, t, P)
	local a = B.def.Attacks.ThroneToss
	if t < a.Leap then
		local k = t / a.Leap
		P.lift = math.sin(k * math.pi) * 18
		P.rHand, P.lHand = V3(10, 12, 2), V3(-10, 12, 2)
		return
	end
	if t < a.Leap + a.Lift then
		local k = smooth((t - a.Leap) / a.Lift)
		P.rHand = V3(8, lerp(4, 24, k), lerp(-8, 2, k))
		P.lHand = V3(-8, lerp(4, 24, k), lerp(-8, 2, k))
		P.gavelDir = V3(1, 0.3, 0.5)
		P.lean = -0.2 * k
		P.shake = 0.1
		return
	end
	local e = t - a.Leap - a.Lift
	P.rHand, P.lHand = V3(6, 16, -12), V3(-6, 16, -12)
	P.lean = 0.35 * clamp(1 - e / 0.8, 0, 1)
	P.snap = e < 0.12
end

-- THE FINAL GAVEL: a leap into the middle, the gavel held up to the sky,
-- glowing... and brought down on everything. Then he's spent.
function Poses.FinalGavel(B, t, P)
	local f = B.def.Final
	if t < 1.0 then
		local k = t
		P.lift = math.sin(k * math.pi) * 24
		P.rHand, P.lHand = V3(10, 14, 2), V3(-10, 14, 2)
		return
	end
	if t < f.Tell then
		P.rHand, P.lHand = V3(1.5, 25, 0), V3(-1.5, 25, 0)
		P.gavelDir = V3(0, 1, 0.05)
		P.headPitch = -0.45
		P.mouth = 1
		P.shake = 0.1 + 0.3 * clamp((t - 1) / (f.Tell - 1), 0, 1)
		return
	end
	P.rHand, P.lHand = V3(2, 5, -11), V3(-1.5, 5.5, -11)
	P.gavelDir = V3(0, -0.9, -0.6)
	P.crouch, P.lean = 0.5, 0.4
	P.snap = t - f.Tell < 0.1
end

-- WORN OUT after the final gavel: sitting, panting, dizzy - finish him!
function Poses.Worn(B, t, P)
	local pant = math.sin(os.clock() * 7)
	P.sit = 0.8
	P.stars = 1
	P.mouth = 0.5 + 0.3 * math.abs(pant)
	P.headPitch = 0.3
	P.rHand, P.lHand = V3(9, 3, -2), V3(-9, 3, -2)
	P.sy = 1 + 0.03 * pant
	local _ = B
	local _ = t
end

-- ROUND 2: steam bursts out, the gavel shudders and splits open into a
-- piston hammer
function Poses.Break(B, t, P)
	local def = B.def
	P.rHand, P.lHand = V3(4, 16, -8), V3(-4, 16, -8)
	P.gavelDir = V3(0, 1, -0.2)
	P.shake = (t > def.BreakTime * 0.35) and 0.3 or 0.1
	P.mouth = (t > def.BreakTime * 0.35) and 1 or 0.3
	P.headPitch = -0.3
end

-- ROUND 3: his crown flies off and he goes BERSERK
function Poses.Berserk(B, t, P)
	local def = B.def
	local hit = def.BerserkTime * 0.4
	P.crown = (t < hit * 0.6) and "on" or "off"
	P.rHand, P.lHand = V3(10, 18, 0), V3(-10, 18, 0)
	P.gavelDir = V3(0.3, 1, 0)
	P.mouth = (t > hit * 0.5) and 1 or 0.4
	P.headPitch = -0.4
	P.shake = (t > hit) and 0.35 or 0.1
	P.crouch = (t < hit) and 0.3 or 0
end

-- THE END: dizzy, wobbling... and flat on his back (the ground shakes).
-- Then gone in a pop of pixels.
function Poses.Death(B, t, P)
	P.stars = 1
	P.eyes = 1
	P.crown = "off"
	if t < 1.3 then
		P.lean = math.sin(t * 7) * 0.2
		P.twist = math.sin(t * 5) * 0.3
		P.rHand, P.lHand = V3(11, 8, -1), V3(-11, 8, -1)
		return
	end
	P.fall = 1
	P.rHand, P.lHand = V3(12, 4, 0), V3(-12, 4, 0)
	P.gavelDir = V3(1, 0, 0)
	P.fade = clamp((t - 4.2) / 0.8, 0, 1)
	local _ = B
end

----------------------------------------------------------------------
-- Starts and slots: the sounds, bursts and warnings of each move
----------------------------------------------------------------------
function Starts.Wake(B, t0)
	local def = B.def
	local W = wakeBeats(def)
	local c = centerOf(B)
	local throne = V3(c.X + ThronePlan.Throne.X, B.vpos.Y, c.Z + ThronePlan.Throne.Z)
	-- lightning cracks down right behind his throne...
	at(B, t0 + 0.02, function()
		strike(B, throne + V3(-12, 0, -14), true)
		kick(throne, 70, 0.5, -2)
	end)
	-- ...and his eyes light up
	at(B, t0 + W.eyes, function()
		if B.eyeAt then
			burst(B.eyeAt, def.ScarEyeColor or YELLOW, 10, 8, 0.9, 0.5, true)
		end
	end)
	at(B, t0 + W.stand0 + 0.35, function()
		shout(B.body.anchor, "WHO DARES...", 1.4, WHITE)
	end)
	-- the gavel raised into the storm: struck by lightning, its runes blazing
	at(B, t0 + W.strike, function()
		local g = B.gavelHead or (throne + V3(0, 60, 0))
		strike(B, g, true)
		burst(g, def.RuneColor or YELLOW, 26, 24, 1.6, 0.6, true)
		kick(throne, 90, 0.7, -3)
	end)
	at(B, t0 + W.leap, function()
		burst(throneSeat(B) + V3(0, ThronePlan.SeatHeight, 0), DUST, 16, 16, 1.6, 0.5)
		playSound(def, "Lunge", B.vpos, 0.9)
	end)
	-- THE LANDING: the whole courtyard shakes
	at(B, t0 + W.land, function()
		local spot = homeSpot(B)
		dust(B, spot, true)
		shockRing(B, spot, 4, 36, 0.6, DUST)
		playSound(def, "Land", spot, 1)
		kick(spot, 150, 1.9, -8)
		for _ = 1, 8 do
			local a2 = math.random() * math.pi * 2
			local d = 12 + math.random() * 22
			dust(B, spot + V3(math.cos(a2) * d, 0, math.sin(a2) * d), false)
		end
	end)
	at(B, t0 + W.laugh - (def.WakeSoundLead or 0.3), function()
		playSound(def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W.laugh, function()
		shout(B.body.anchor, "HAR HAR HAR!", 1.3, GOLD)
	end)
	at(B, t0 + W.slam, function()
		local spot = B.vpos + B.vfacing * 18
		dust(B, spot, true)
		shockRing(B, spot, 2, 20, 0.5, GOLD)
		playSound(def, "Smash", spot, 0.8)
		kick(B.vpos, 60, 1.1, -4)
		shout(B.body.anchor, "KNEEL!", 1.2, RED)
	end)
end

function Starts.Dormant(B, t0)
	local _ = B
	local _ = t0
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.15, function()
		shout(B.body.anchor, "PEASANTS. HMPH.", 1.3, WHITE)
	end)
	at(B, t0 + 0.55, function()
		dust(B, B.vpos, false)
		playSound(B.def, "Lunge", B.vpos, 0.6)
	end)
	at(B, t0 + 1.45, function()
		local seat = throneSeat(B)
		burst(seat + V3(0, ThronePlan.SeatHeight, 0), DUST, 14, 14, 1.4, 0.5)
		kick(seat, 40, 0.6, -2)
	end)
end

function Starts.RoyalSmash(B, t0)
	local a = B.def.Attacks.RoyalSmash
	-- before it locks: a dim circle in front of him, following; then the real one
	redDisc(B, function()
		return slot(B, 1) or (B.vpos + B.vfacing * a.Reach * 0.8)
	end, a.Radius, t0, t0 + a.Tell)
	at(B, t0 + a.Tell * 0.5, function()
		steam(B, false)
	end)
	at(B, t0 + a.Tell, function()
		local spot = slot(B, 1) or (B.vpos + B.vfacing * a.Reach)
		spot = onFloor(spot)
		local rings = num(B.model:GetAttribute("ActN"), 1)
		for k = 1, rings do
			waveRing(B, spot, t0 + a.Tell + (k - 1) * a.RingGap, a.WaveSpeed, a.WaveReach, a.WaveHeight, a.WaveThickness)
		end
		dust(B, spot, true)
		burst(spot + V3(0, 2, 0), GOLD, 12, 20, 1.2, 0.4, true)
		playSound(B.def, "Smash", spot, 1)
		kick(spot, 40, 1.3, -5)
		steam(B, true)
	end)
end

function Starts.GavelSweep(B, t0)
	local a = B.def.Attacks.GavelSweep
	wedge(B, a.Reach, a.Arc, t0, t0 + a.Tell)
	at(B, t0 + a.Tell - 0.05, function()
		playSound(B.def, "Sweep", B.vpos, 1)
	end)
	at(B, t0 + a.Tell + 0.1, function()
		burst(B.vpos + B.vfacing * a.Reach * 0.6 + V3(0, 2, 0), DUST, 14, 20, 1.4, 0.4)
		kick(B.vpos, 26, 0.6, -2)
	end)
end

function SlotSpawns.BellyBounce(B, i, spot, t0)
	local a = B.def.Attacks.BellyBounce
	local up = t0 + a.Tell + (i - 1) * (a.Air + a.Gap)
	B.hopFrom = B.hopFrom or {}
	B.hopFrom[i] = B.vpos
	redDisc(B, function()
		return spot
	end, a.Radius, up, up + a.Air)
	at(B, up + a.Air, function()
		dust(B, spot, true)
		shockRing(B, spot, 3, a.Radius * 1.3, 0.4, DUST)
		playSound(B.def, "Bounce", spot, 1)
		kick(spot, a.Radius + 30, 1.4, -5)
	end)
end

function Starts.BellyBounce(B, t0)
	B.hopFrom = {}
	local a = B.def.Attacks.BellyBounce
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Lunge", B.vpos, 0.7)
	end)
end

function Starts.RoyalDecree(B, t0)
	local a = B.def.Attacks.RoyalDecree
	at(B, t0 + a.Tell * 0.4, function()
		playSound(B.def, "Guards", B.vpos, 1)
		shout(B.body.anchor, "GUARDS!", 1.2, GOLD)
	end)
end

function SlotSpawns.RoyalDecree(B, i, spot, t0)
	-- each guard lands with a clank and a puff
	burst(onFloor(spot) + V3(0, 1, 0), SILVER, 10, 14, 1, 0.4, true)
	local _ = i
	local _ = t0
end

function Starts.ToeStomp(B, t0)
	local a = B.def.Attacks.ToeStomp
	redDisc(B, function()
		return slot(B, 1)
	end, a.Radius, t0 + a.Tell * 0.5, t0 + a.Tell)
	at(B, t0 + a.Tell, function()
		local spot = slot(B, 1) or (B.vpos + B.vfacing * 10)
		dust(B, spot, true)
		playSound(B.def, "Stomp", spot, 1)
		kick(spot, 30, 1.0, -3)
	end)
end

function Starts.ToeHop(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Toe", B.vpos, 1)
		shout(B.body.anchor, "OW! MY TOE!", 1.4, YELLOW)
	end)
end

function Starts.TaxCollector(B, t0)
	local a = B.def.Attacks.TaxCollector
	at(B, t0 + 0.1, function()
		shout(B.body.anchor, "TAXES ARE DUE!", 1.4, GOLD)
	end)
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Coins", B.vpos, 1)
	end)
end

-- a coin falling out of the sky onto slot i (it lands 0.6 seconds later,
-- then the server's Coin prop takes over)
function SlotSpawns.TaxCollector(B, i, spot, t0)
	local startAt = serverNow()
	local coin = newPart("FallingCoin", Enum.PartType.Cylinder, GOLD, Enum.Material.SmoothPlastic, 1)
	local shadow = newPart("CoinShadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 1)
	addTelegraph(B, {
		update = function(now)
			local k = (now - startAt) / 0.6
			if k >= 1 then
				return false
			end
			local g = onFloor(spot)
			coin.Size = V3(0.5, 2.4, 2.4)
			coin.CFrame = CFrame.new(g + V3(0, 1.2 + (1 - k) * 34, 0)) * CFrame.Angles(0, now * 8, math.pi / 2)
			coin.Transparency = 0
			placeDisc(shadow, g + V3(0, 0.08, 0), 1 + 1.4 * k, 0.06)
			shadow.Transparency = lerp(0.8, 0.5, k)
			return true
		end,
		cleanup = function()
			coin:Destroy()
			shadow:Destroy()
		end,
	})
	local _ = i
	local _ = t0
end

function Starts.TripleSlam(B, t0)
	local a = B.def.Attacks.TripleSlam
	at(B, t0 + 0.1, function()
		steam(B, true)
		playSound(B.def, "Piston", B.vpos, 0.9)
	end)
	for k = 1, a.Slams do
		local hitAt = t0 + a.Tell + (k - 1) * a.Gap
		at(B, hitAt, function()
			local spot = slot(B, k) or (B.vpos + B.vfacing * 12)
			spot = onFloor(spot)
			waveRing(B, spot, hitAt, a.WaveSpeed, a.WaveReach, a.WaveHeight, a.WaveThickness)
			dust(B, spot, true)
			steam(B, false)
			playSound(B.def, "Smash", spot, 0.9)
			kick(spot, 34, 1.0, -3)
		end)
	end
end

function SlotSpawns.TripleSlam(B, i, spot, t0)
	local a = B.def.Attacks.TripleSlam
	local hitAt = t0 + a.Tell + (i - 1) * a.Gap
	redDisc(B, function()
		return spot
	end, a.Radius, hitAt - 0.45, hitAt)
end

function Starts.HammerTornado(B, t0)
	local a = B.def.Attacks.HammerTornado
	local ring = newRing(32, RED, Enum.Material.Neon, 1)
	local disc = newPart("TornadoWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local startsAt, endsAt = t0 + a.Tell, t0 + a.Tell + a.Time
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "HammerTornado" or B.actionStart ~= t0 or now > endsAt then
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
	at(B, startsAt, function()
		playSound(B.def, "Tornado", B.vpos, 1)
		shout(B.body.anchor, "SPIN TO WIN!", 1.0, GOLD)
	end)
	for k = 0, math.floor(a.Time / 0.3) do
		at(B, startsAt + k * 0.3, function()
			if B.action == "HammerTornado" then
				burst(onFloor(B.vpos) + V3(0, 0.6, 0), DUST, 6, 18, 1, 0.4)
			end
		end)
	end
end

function Starts.BigGulp(B, t0)
	local a = B.def.Attacks.BigGulp
	local inhaleEnd = t0 + a.Tell + a.Inhale
	-- the suction: a pale wedge in front, wind streaks rushing to his mouth
	wedge(B, a.Reach, a.Arc, t0, inhaleEnd, SILVER, "GulpWarning")
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Gulp", B.vpos, 1)
	end)
	for k = 0, math.floor(a.Inhale / 0.12) do
		at(B, t0 + a.Tell + k * 0.12, function()
			if B.action ~= "BigGulp" then
				return
			end
			local ang = (math.random() - 0.5) * math.rad(a.Arc)
			local far = onFloor(B.vpos) + turnY(B.vfacing, ang) * (a.Reach * (0.6 + 0.4 * math.random())) + V3(0, 3, 0)
			local streak = newPart("GulpWind", nil, WHITE, Enum.Material.Neon, 0.4)
			local born = serverNow()
			addTelegraph(B, {
				update = function(now)
					local kk = (now - born) / 0.35
					if kk >= 1 then
						return false
					end
					local mouth = B.mouthAt or (B.vpos + V3(0, 20, 0))
					local p = far:Lerp(mouth, kk)
					stretch(streak, p, p + unitOr(mouth - far, V3(0, 0, 1)) * 3, 0.3, 0.3)
					streak.Transparency = lerp(0.3, 0.9, kk)
					return true
				end,
				cleanup = function()
					streak:Destroy()
				end,
			})
		end)
	end
	at(B, inhaleEnd + a.Chew, function()
		if slot(B, 1) then
			playSound(B.def, "Spit", B.vpos, 1)
			shout(B.body.anchor, "PTOO!", 0.9, WHITE)
		end
	end)
	at(B, inhaleEnd + a.Chew + 0.3, function()
		playSound(B.def, "Burp", B.vpos, 1)
		shout(B.body.anchor, "*BUUURP*", 1.2, GREEN)
		kick(B.vpos, a.BurpReach + 10, 1.2, -4)
		-- the burp: a green cone of wind
		for k = 1, 16 do
			local ang = (k / 16 - 0.5) * math.rad(a.BurpArc)
			local dir = turnY(B.vfacing, ang)
			burst(onFloor(B.vpos) + dir * (6 + math.random() * a.BurpReach * 0.8) + V3(0, 3 + math.random() * 5, 0), GREEN, 5, 22, 2, 0.5)
		end
	end)
end

function SlotSpawns.BigGulp(B, i, spot, t0)
	if i == 1 then
		playSound(B.def, "Swallow", spot, 1)
		shout(B.body.anchor, "GULP!", 0.8, WHITE)
	end
	local _ = t0
end

function Starts.RocketHammer(B, t0)
	local a = B.def.Attacks.RocketHammer
	local L = laneParts()
	local lockedAt = nil
	addTelegraph(B, {
		update = function(now)
			local from, to = slot(B, 1), slot(B, 2)
			local travel = (from and to) and flat(to - from).Magnitude / a.Speed or 0.6
			local ends = t0 + a.Tell + travel * 2 + a.Hold
			if B.action ~= "RocketHammer" or B.actionStart ~= t0 or now > ends + 0.05 then
				return false
			end
			if from and to then
				lockedAt = lockedAt or now
				local blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
				placeLane(L, onFloor(from), onFloor(to), a.Width, true, blink)
			else
				local c0 = onFloor(B.vpos) + B.vfacing * (B.def.Size / 2)
				placeLane(L, c0, c0 + B.vfacing * a.Length, a.Width, false, false)
			end
			return true
		end,
		cleanup = function()
			removeLane(L)
		end,
	})
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Rocket", B.vpos, 1)
		steam(B, true)
	end)
	at(B, t0 + a.Tell + 0.6, function()
		playSound(B.def, "Chain", B.vpos, 0.8)
	end)
end

function Starts.RoyalFeast(B, t0)
	at(B, t0 + 0.1, function()
		playSound(B.def, "Feast", B.vpos, 1)
		shout(B.body.anchor, "DINNER TIME!", 1.3, GOLD)
	end)
	local a = B.def.Attacks.RoyalFeast
	for k = 0, math.floor(a.Feast / 0.66) do
		at(B, t0 + a.Tell + k * 0.66, function()
			if B.action == "RoyalFeast" then
				playSound(B.def, "Eat", B.vpos, 0.7)
				-- healing: little green pluses
				burst((B.mouthAt or B.vpos) + V3(0, 1, 0), GREEN, 6, 8, 0.8, 0.8, true)
			end
		end)
	end
end

function Starts.Choke(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Choke", B.vpos, 1)
		shout(B.body.anchor, "*CHOKE*", 1.4, SKY)
	end)
end

function Starts.RoyalRoll(B, t0)
	local a = B.def.Attacks.RoyalRoll
	B.rollTotal = nil
	local lanes = {}
	for i = 1, 4 do
		lanes[i] = laneParts()
	end
	local lockedAt = nil
	addTelegraph(B, {
		update = function(now)
			local n = num(B.model:GetAttribute("ActN"), 0)
			local pts = {}
			for i = 1, math.max(n, 0) do
				local p = slot(B, i)
				if not p then
					break
				end
				pts[i] = p
			end
			local total = 0
			for i = 1, #pts - 1 do
				total = total + flat(pts[i + 1] - pts[i]).Magnitude / a.Speed
			end
			if #pts >= 2 then
				B.rollTotal = total
			end
			if B.action ~= "RoyalRoll" or B.actionStart ~= t0 or now > t0 + a.Tell + (#pts >= 2 and total or 3) + 0.05 then
				return false
			end
			if #pts >= 2 then
				lockedAt = lockedAt or now
				local blink = (now - lockedAt) < 0.22 and ((now - lockedAt) % 0.11) < 0.055
				for i, L in ipairs(lanes) do
					if pts[i + 1] then
						placeLane(L, onFloor(pts[i]), onFloor(pts[i + 1]), a.Width, true, blink)
					else
						hideLane(L)
					end
				end
			else
				local c0 = onFloor(B.vpos)
				placeLane(lanes[1], c0, c0 + B.vfacing * 40, a.Width, false, false)
				for i = 2, #lanes do
					hideLane(lanes[i])
				end
			end
			return true
		end,
		cleanup = function()
			for _, L in ipairs(lanes) do
				removeLane(L)
			end
		end,
	})
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Roll", B.vpos, 1)
		dust(B, B.vpos, true)
		shout(B.body.anchor, "BOWLING!", 1.0, GOLD)
	end)
end

function Starts.Earthquake(B, t0)
	local a = B.def.Attacks.Earthquake
	local landAt = t0 + a.Tell + a.Air
	at(B, t0 + 0.05, function()
		if B.here then
			pcall(bigText, "STAND ON THE GOLD!", { color = GOLD, size = 40, hold = 1.4, y = 0.3 })
		end
	end)
	-- the whole courtyard pulses red, except the safe flagstones
	local c = centerOf(B)
	local wide = newPart("QuakeWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	addTelegraph(B, {
		update = function(now)
			if now > landAt + 0.05 then
				return false
			end
			local k = clamp((now - t0) / (landAt - t0), 0, 1)
			placeDisc(wide, onFloor(V3(c.X, B.vpos.Y, c.Z)) + V3(0, 0.1, 0), ThronePlan.Radius * 2, 0.05)
			wide.Transparency = lerp(0.9, 0.7, k) + ((math.floor(now * 6) % 2 == 0) and 0.05 or 0)
			return true
		end,
		cleanup = function()
			wide:Destroy()
		end,
	})
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Lunge", B.vpos, 0.8)
	end)
	at(B, landAt, function()
		local mid = onFloor(V3(c.X, B.vpos.Y, c.Z))
		dust(B, mid, true)
		shockRing(B, mid, 4, ThronePlan.Radius, 0.6, DUST)
		playSound(B.def, "Quake", mid, 1)
		kick(mid, 200, 2.2, -8)
		for _ = 1, 10 do
			local a2 = math.random() * math.pi * 2
			local d = math.random() * ThronePlan.Radius
			dust(B, mid + V3(math.cos(a2) * d, 0, math.sin(a2) * d), false)
		end
	end)
end

function SlotSpawns.Earthquake(B, i, spot, t0)
	local a = B.def.Attacks.Earthquake
	local landAt = t0 + a.Tell + a.Air
	local tile = newPart("SafeTile", nil, GOLD, Enum.Material.Neon, 1)
	local cell = ThronePlan.Cell
	addTelegraph(B, {
		update = function(now)
			if now > landAt + 0.4 then
				return false
			end
			local g = onFloor(spot)
			tile.Size = V3(cell - 0.8, 0.14, cell - 0.8)
			tile.CFrame = CFrame.new(g + V3(0, 0.16, 0))
			tile.Transparency = 0.35 + 0.15 * math.sin(now * 12)
			return true
		end,
		cleanup = function()
			tile:Destroy()
		end,
	})
	local _ = i
end

function Starts.CrownGrab(B, t0)
	local a = B.def.Attacks.CrownGrab
	local crown = newPart("LooseCrown", nil, GOLD, Enum.Material.SmoothPlastic, 1)
	local points = {}
	for k = 1, 3 do
		points[k] = newPart("LooseCrownPoint", nil, GOLD, Enum.Material.SmoothPlastic, 1)
	end
	local from = nil
	addTelegraph(B, {
		update = function(now)
			local spot = slot(B, 1)
			local act = B.action
			local done = act ~= "CrownGrab" and not (act == "Crowned" and now - (B.actionStart or now) < 0.2)
			if done or not spot then
				return not done
			end
			from = from or (B.crownCF and B.crownCF.Position) or (B.vpos + V3(0, 30, 0))
			local g = onFloor(spot) + V3(0, 1.2, 0)
			local k = clamp((now - t0) / a.Tell, 0, 1)
			local p = from:Lerp(g, k) + V3(0, math.sin(k * math.pi) * 20, 0)
			local cf = CFrame.new(p) * CFrame.Angles(0, now * (k < 1 and 10 or 1.5), (k < 1) and now * 6 or 0.15)
			crown.Size = V3(4.4, 1.6, 4.4)
			crown.CFrame = cf
			crown.Transparency = 0
			for j, pt in ipairs(points) do
				pt.Size = V3(0.8, 1.4, 0.8)
				pt.CFrame = cf * CFrame.new((j - 2) * 1.5, 1.4, -2)
				pt.Transparency = 0
			end
			return true
		end,
		cleanup = function()
			crown:Destroy()
			for _, pt in ipairs(points) do
				pt:Destroy()
			end
		end,
	})
	at(B, t0 + a.Tell, function()
		local spot = slot(B, 1)
		if spot then
			playSound(B.def, "Crown", spot, 1)
			burst(onFloor(spot) + V3(0, 1, 0), GOLD, 12, 12, 1, 0.5, true)
		end
		shout(B.body.anchor, "MY CROWN!!", 1.2, GOLD)
	end)
end

function Starts.Tripped(B, t0)
	at(B, t0 + 0.35, function()
		dust(B, B.vpos + B.vfacing * 12, true)
		playSound(B.def, "Trip", B.vpos, 1)
		kick(B.vpos, 50, 1.4, -4)
	end)
end

function Starts.Crowned(B, t0)
	local a = B.def.Attacks.CrownGrab
	at(B, t0 + 0.35, function()
		playSound(B.def, "Berserk", B.vpos, 0.9)
		shockRing(B, B.vpos, 3, a.RoarRadius, 0.45, GOLD)
		kick(B.vpos, a.RoarRadius + 20, 1.2, -4)
	end)
end

function Starts.Guilty(B, t0)
	local a = B.def.Attacks.Guilty
	at(B, t0 + 0.05, function()
		playSound(B.def, "Guilty", B.vpos, 1)
	end)
	at(B, t0 + a.Tell * 0.6, function()
		shout(B.body.anchor, "GUILTY!", 1.4, RED)
		local me = game:GetService("Players").LocalPlayer
		if B.here and me and B.model:GetAttribute("Accused") == me.UserId then
			pcall(bigText, "YOU'RE GUILTY!", { color = RED, sub = "GET TO A PODIUM!", size = 48, hold = 1.6 })
		end
	end)
	-- the spotlight and the countdown over the accused; the giant gavel
	local beam = newPart("Spotlight", Enum.PartType.Cylinder, YELLOW, Enum.Material.Neon, 1)
	local bigHead = newPart("GiantGavel", nil, WOOD, Enum.Material.SmoothPlastic, 1)
	local bigHandle = newPart("GiantGavelHandle", nil, WOOD_DARK, Enum.Material.SmoothPlastic, 1)
	local shareRing = newRing(28, RED, Enum.Material.Neon, 1)
	local disc = newPart("GuiltyWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 60)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 300
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextColor3 = RED
	label.TextStrokeTransparency = 0
	label.Text = ""
	label.Parent = bb
	local holder = newPart("GuiltyLabel", nil, WHITE, Enum.Material.SmoothPlastic, 1)
	holder.Size = V3(0.2, 0.2, 0.2)
	bb.Adornee = holder
	bb.Parent = holder
	local fallAt = t0 + a.Tell + a.Countdown
	local fell = false
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "Guilty" or B.actionStart ~= t0 or now > fallAt + 0.8 then
				return false
			end
			local spot = slot(B, 2) or B.model:GetAttribute("Verdict") or slot(B, 1)
			if typeof(spot) ~= "Vector3" or now < t0 + a.Tell then
				return true
			end
			local g = onFloor(spot)
			local locked = slot(B, 2) ~= nil
			-- the spotlight from the sky
			beam.Size = V3(80, a.Share * 2, a.Share * 2)
			beam.CFrame = CFrame.new(g + V3(0, 40, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			beam.Transparency = (now < fallAt) and 0.85 or 1
			placeRing(shareRing, g + V3(0, 0.14, 0), a.Share, 0.3, 0.6, locked and 0.05 or 0.35)
			local k = clamp((now - (t0 + a.Tell)) / a.Countdown, 0, 1)
			placeDisc(disc, g + V3(0, 0.12, 0), a.Radius * 2 * (0.3 + 0.7 * k), 0.1)
			disc.Transparency = lerp(0.7, 0.35, k)
			disc.Color = (locked and math.floor(now * 12) % 2 == 0) and WHITE or RED
			-- the countdown
			holder.CFrame = CFrame.new(g + V3(0, 9, 0))
			local left = math.max(0, math.ceil(fallAt - now))
			label.Text = (now < fallAt) and tostring(left) or "GUILTY!"
			-- the giant gavel: up in the sky, then swinging down in the last half second
			local drop = clamp((now - (fallAt - 0.5)) / 0.5, 0, 1)
			local hy = lerp(46, 4, drop * drop)
			local hp = g + V3(0, hy, 0)
			bigHead.Size = V3(8, 8, 16)
			bigHead.CFrame = CFrame.new(hp) * CFrame.Angles(0, 0, 0)
			bigHead.Transparency = (now > t0 + a.Tell + a.Countdown * 0.4) and 0 or 1
			stretch(bigHandle, hp + V3(0, 3, 0), hp + V3(0, 26, 0), 1.6, 1.6)
			bigHandle.Transparency = bigHead.Transparency
			if now >= fallAt and not fell then
				fell = true
				dust(B, g, true)
				shockRing(B, g, 2, a.Share + 2, 0.4, RED)
				playSound(B.def, "Gavel", g, 1)
				kick(g, 40, 1.6, -5)
			end
			return true
		end,
		cleanup = function()
			beam:Destroy()
			bigHead:Destroy()
			bigHandle:Destroy()
			removeRing(shareRing)
			disc:Destroy()
			holder:Destroy()
		end,
	})
end

function Starts.ThroneToss(B, t0)
	local a = B.def.Attacks.ThroneToss
	at(B, t0 + a.Leap, function()
		dust(B, B.vpos, true)
		kick(B.vpos, 40, 1.0, -3)
		shout(B.body.anchor, "MY THRONE! CATCH!", 1.4, GOLD)
	end)
	-- the throne in his hands, then flying
	local parts = {}
	local function tp(size, color)
		local p = newPart("FlyingThrone", nil, color, Enum.Material.SmoothPlastic, 1)
		table.insert(parts, { part = p, size = size })
		return p
	end
	local seat = tp(V3(16, 5.4, 9), GOLD)
	local back = tp(V3(16, 20, 2.2), GOLD)
	local cushion = tp(V3(13, 14, 0.7), RED)
	local throwAt = t0 + a.Leap + a.Lift
	local landAt = throwAt + a.Flight
	local from = nil
	addTelegraph(B, {
		update = function(now)
			if B.action ~= "ThroneToss" or B.actionStart ~= t0 or now > landAt + 0.05 then
				return false
			end
			local lifting = now >= t0 + a.Leap
			B.throneHeld = lifting
			if not lifting then
				for _, rec in ipairs(parts) do
					rec.part.Transparency = 1
				end
				return true
			end
			local over = ((B.handR or B.vpos) + (B.handL or B.vpos)) / 2 + V3(0, 8, 0)
			local p = over
			local spin = 0
			local spot = slot(B, 2)
			if now >= throwAt and spot then
				from = from or over
				local k = clamp((now - throwAt) / a.Flight, 0, 1)
				local g = onFloor(spot) + V3(0, 6, 0)
				p = from:Lerp(g, k) + V3(0, math.sin(k * math.pi) * (14 + flat(g - from).Magnitude * 0.2), 0)
				spin = k * 7
			end
			local cf = CFrame.lookAt(p, p + B.vfacing) * CFrame.Angles(spin, 0, 0)
			seat.Size, seat.CFrame = parts[1].size, cf
			back.Size, back.CFrame = parts[2].size, cf * CFrame.new(0, 11, 4.5)
			cushion.Size, cushion.CFrame = parts[3].size, cf * CFrame.new(0, 11, 3.2)
			for _, rec in ipairs(parts) do
				rec.part.Transparency = 0
			end
			return true
		end,
		cleanup = function()
			B.throneHeld = false
			for _, rec in ipairs(parts) do
				rec.part:Destroy()
			end
		end,
	})
end

function SlotSpawns.ThroneToss(B, i, spot, t0)
	local a = B.def.Attacks.ThroneToss
	if i == 2 then
		local throwAt = t0 + a.Leap + a.Lift
		redDisc(B, function()
			return spot
		end, a.Radius, throwAt, throwAt + a.Flight)
		at(B, throwAt + a.Flight, function()
			dust(B, spot, true)
			burst(onFloor(spot) + V3(0, 3, 0), GOLD, 20, 24, 1.6, 0.6, true)
			shockRing(B, spot, 3, a.Radius * 1.3, 0.45, GOLD)
			playSound(B.def, "Throne", spot, 1)
			kick(spot, a.Radius + 36, 1.6, -5)
		end)
	end
end

function Starts.FinalGavel(B, t0)
	local f = B.def.Final
	local c = centerOf(B)
	at(B, t0 + 0.05, function()
		if B.here then
			pcall(bigText, "THE FINAL GAVEL", { color = GOLD, sub = "JUMP OR ROLL THE SHOCKWAVE!", size = 56, hold = 2.2 })
		end
		shout(B.body.anchor, "KNEEL BEFORE YOUR KING!", 2.0, RED)
	end)
	-- the gavel glowing gold in the sky, a huge red circle filling in
	local mid = nil
	redDisc(B, function()
		mid = mid or onFloor(V3(c.X, B.vpos.Y, c.Z))
		return mid
	end, f.Radius, t0 + 1.0, t0 + f.Tell)
	for k = 0, 8 do
		at(B, t0 + 1.0 + k * (f.Tell - 1.0) / 9, function()
			burst((B.gavelHead or B.vpos + V3(0, 40, 0)), GOLD, 10, 14, 1.4, 0.5, true)
		end)
	end
	at(B, t0 + f.Tell, function()
		local g = onFloor(V3(c.X, B.vpos.Y, c.Z))
		waveRing(B, g, t0 + f.Tell, f.WaveSpeed, f.WaveReach, f.WaveHeight, f.WaveThickness, GOLD)
		dust(B, g, true)
		burst(g + V3(0, 4, 0), GOLD, 40, 40, 2.4, 0.8, true)
		playSound(B.def, "Final", g, 1)
		kick(g, 300, 2.6, -10)
	end)
end

function Starts.Worn(B, t0)
	at(B, t0 + 0.1, function()
		shout(B.body.anchor, "*PANT* *PANT*", 1.6, WHITE)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + 0.05, function()
		playSound(def, "Piston", B.vpos, 1)
	end)
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		strike(B, B.gavelHead or (B.vpos + V3(0, 40, 0)), true) -- (lightning forges the new hammer)
		playSound(def, "Break", B.vpos, 1)
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, def.SteamColor or SILVER)
		steam(B, true)
		burst((B.gavelHead or B.vpos) + V3(0, 3, 0), ORANGE, 30, 24, 1.6, 0.8, true)
		kick(B.vpos, def.BreakReach + 20, 1.4, -5)
		if B.here then
			pcall(bigText, "THE MECHANICAL GAVEL", { color = GOLD, sub = "ROUND 2", size = 52, hold = 1.4 })
		end
	end)
end

function Starts.Berserk(B, t0)
	local def = B.def
	local hit = t0 + def.BerserkTime * 0.4
	at(B, t0 + def.BerserkTime * 0.2, function()
		-- his crown flies off, spinning, and is gone over the battlements
		local from = B.crownCF and B.crownCF.Position or (B.vpos + V3(0, 30, 0))
		local crown = newPart("FlyingCrown", nil, GOLD, Enum.Material.SmoothPlastic, 0)
		local born = serverNow()
		local dir = turnY(B.vfacing, 2.2)
		addTelegraph(B, {
			update = function(now)
				local k = (now - born) / 1.4
				if k >= 1 then
					return false
				end
				local p = from + dir * (k * 50) + V3(0, math.sin(k * math.pi) * 24 - k * 10, 0)
				crown.Size = V3(4.4, 1.6, 4.4)
				crown.CFrame = CFrame.new(p) * CFrame.Angles(now * 9, now * 5, 0)
				return true
			end,
			cleanup = function()
				crown:Destroy()
			end,
		})
		playSound(def, "Crown", from, 1)
	end)
	at(B, hit, function()
		B.berserkLook = true
		strike(B, (B.eyeAt or B.vpos) + V3(0, 14, 0), true) -- (red lightning: the eclipse begins)
		playSound(def, "Berserk", B.vpos, 1)
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, def.RageColor or RED)
		burst(B.vpos + V3(0, 18, 0), def.RageColor or RED, 40, 30, 2, 0.9, true)
		kick(B.vpos, def.BreakReach + 30, 1.8, -6)
		if B.here then
			pcall(bigText, "NO ONE TAKES MY CROWN!", { color = RED, sub = "ROUND 3", size = 48, hold = 1.6 })
		end
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.2, function()
		playSound(def, "Death", B.vpos, 1)
		shout(B.body.anchor, "NOT... MY... CROOOWN...", 2.0, WHITE)
	end)
	at(B, t0 + 1.7, function()
		dust(B, B.vpos - B.vfacing * 10, true)
		kick(B.vpos, 80, 2.0, -6)
	end)
	at(B, t0 + 4.2, function()
		for k = 1, 5 do
			burst(B.vpos + V3(0, 2 + k * 3, 0), (k % 2 == 0) and def.Color or GOLD, 18, 16, 1.6, 0.9, true)
		end
		if B.here then
			pcall(bigText, "SPIRE CONQUERED!", { color = GOLD, sub = "THE KING HAS FALLEN", size = 60, hold = 3 })
		end
	end)
end

----------------------------------------------------------------------
-- Every frame: his props, the pillars, the throne, torches, the storm, "HIT HIM!"
----------------------------------------------------------------------
-- A TIN GUARD (the server's Workspace.GavelgruntProps): a little chunky
-- knight with a spear that marches after you, winds up a jab (spear back,
-- going red) and jabs; knocked over, it clatters apart; left alone, it
-- marches off
local function makeGuard(inst)
	local rec = { kind = "Guard", inst = inst, parts = {} }
	local function add(name, color, mat)
		local p = newPart(name, nil, color, mat or Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	rec.body = add("GuardBody", SILVER)
	rec.head = add("GuardHelm", STEEL)
	rec.plume = add("GuardPlume", RED)
	rec.visor = add("GuardVisor", INK)
	rec.legs = { add("GuardLeg", STONE_DARK), add("GuardLeg", STONE_DARK) }
	rec.spear = add("GuardSpear", WOOD_DARK)
	rec.tip = add("GuardSpearTip", SILVER)
	rec.tabard = add("GuardTabard", RGB(104, 56, 108))
	return rec
end

local function stepGuard(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.8) then
		return false
	end
	local pos = hit.Position - V3(0, 2.5, 0)
	local dir = unitOr(flat(hit.CFrame.LookVector), V3(0, 0, 1))
	local moved = rec.last and flat(pos - rec.last).Magnitude > 0.02
	rec.last = pos
	local warnAt, jabAt = inst:GetAttribute("SwipeWarn"), inst:GetAttribute("SwipeAt")
	local winding = warnAt and jabAt and now >= warnAt and now < jabAt
	local jabbing = jabAt and now >= jabAt and now < jabAt + 0.2
	local fade = 0
	if endKind == "March" or endKind == "Gone" then
		fade = clamp((now - endAt) / 0.6, 0, 1)
	elseif endKind == "Broken" then
		fade = 1
	end
	local step = moved and math.sin(now * 16) or 0
	local cf = CFrame.lookAt(pos, pos + dir)
	rec.body.Size = V3(2, 2.2, 1.4)
	rec.body.CFrame = cf * CFrame.new(0, 2.6, 0)
	rec.tabard.Size = V3(1.4, 1.6, 0.2)
	rec.tabard.CFrame = cf * CFrame.new(0, 2.5, -0.8)
	rec.head.Size = V3(1.6, 1.6, 1.6)
	rec.head.CFrame = cf * CFrame.new(0, 4.5, 0)
	rec.plume.Size = V3(0.4, 1.2, 1.4)
	rec.plume.CFrame = cf * CFrame.new(0, 5.6, 0.2)
	rec.visor.Size = V3(1.2, 0.3, 0.1)
	rec.visor.CFrame = cf * CFrame.new(0, 4.6, -0.82)
	for i, leg in ipairs(rec.legs) do
		local side = (i == 1) and -1 or 1
		leg.Size = V3(0.7, 1.5, 0.7)
		leg.CFrame = cf * CFrame.new(side * 0.5, 0.75, side * step * 0.4)
	end
	local back = winding and 1.4 or (jabbing and -1.6 or 0)
	local spearBase = cf * V3(1.3, 2.6, back)
	local spearTip = spearBase + dir * 5
	stretch(rec.spear, spearBase, spearTip, 0.3, 0.3)
	rec.tip.Size = V3(0.6, 0.6, 1)
	rec.tip.CFrame = CFrame.lookAt(spearTip, spearTip + dir)
	rec.tip.Color = (winding and math.floor(now * 14) % 2 == 0) and RED or SILVER
	for _, p in ipairs(rec.parts) do
		p.Transparency = fade
	end
	if endKind == "Broken" and not rec.clattered then
		rec.clattered = true
		burst(pos + V3(0, 2, 0), SILVER, 16, 16, 1, 0.5)
		playSound(B.def, "Guard", pos, 0.6)
	end
	if jabbing and not rec.jabbed then
		rec.jabbed = true
		playSound(B.def, "Guard", pos, 0.8)
	elseif not jabbing then
		rec.jabbed = false
	end
	return true
end

-- THE TIP OF HIS FLIPPER, glowing: punch it!
local function makeToe(inst)
	local rec = { kind = "Toe", inst = inst, parts = {} }
	rec.glow = newPart("ToeGlow", nil, YELLOW, Enum.Material.Neon, 1)
	rec.ring = newRing(16, YELLOW, Enum.Material.Neon, 1)
	table.insert(rec.parts, rec.glow)
	return rec
end

local function stepToe(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.3) then
		removeRing(rec.ring)
		return false
	end
	local p = hit.Position - V3(0, 1.2, 0) -- (the prop: where you punch - the tip of his flipper is on it)
	local pulse = 1 + 0.2 * math.sin(now * 12)
	rec.glow.Size = V3(3.2, 2.2, 3.2) * pulse
	rec.glow.CFrame = CFrame.new(p + V3(0, 0.6, 0))
	rec.glow.Transparency = endKind and 1 or 0.2
	placeRing(rec.ring, onFloor(p) + V3(0, 0.1, 0), 3.8 * pulse, 0.3, 0.5, endKind and 1 or 0.2)
	if endKind == "Broken" and not rec.popped then
		rec.popped = true
		burst(p + V3(0, 1, 0), YELLOW, 16, 16, 1, 0.4, true)
	end
	return true
end

-- A GOLD COIN on the floor, spinning: grab it! (Taken: a sparkle; Taxed:
-- it flies off into his mouth)
local function makeCoin(inst)
	local rec = { kind = "Coin", inst = inst, parts = {} }
	rec.coin = newPart("TaxCoin", Enum.PartType.Cylinder, GOLD, Enum.Material.SmoothPlastic, 1)
	rec.face = newPart("TaxCoinFace", nil, YELLOW, Enum.Material.Neon, 1)
	table.insert(rec.parts, rec.coin)
	table.insert(rec.parts, rec.face)
	return rec
end

local function stepCoin(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.6) then
		return false
	end
	local p = hit.Position
	if endKind == "Taxed" then
		local k = clamp((now - endAt) / 0.5, 0, 1)
		p = p:Lerp(B.mouthAt or (B.vpos + V3(0, 20, 0)), k * k)
	elseif endKind == "Taken" then
		if not rec.sparkled then
			rec.sparkled = true
			burst(p, YELLOW, 10, 10, 0.8, 0.5, true)
			playSound(B.def, "Coin", p, 0.8)
		end
		p = p + V3(0, (now - endAt) * 10, 0)
	end
	local cf = CFrame.new(p + V3(0, 0.5 + 0.2 * math.sin(now * 4), 0)) * CFrame.Angles(0, now * 3, 0)
	rec.coin.Size = V3(0.5, 2.4, 2.4)
	rec.coin.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	rec.face.Size = V3(0.8, 1.2, 0.52)
	rec.face.CFrame = cf
	local fade = (endKind == "Gone" or endKind == "Taken") and clamp((now - endAt) / 0.4, 0, 1) or 0
	local blink = 0
	local untilT = inst:GetAttribute("Until")
	if not endKind and type(untilT) == "number" and untilT - now < 1.2 then
		blink = (math.floor(now * 10) % 2 == 0) and 0.5 or 0
	end
	rec.coin.Transparency = math.max(fade, blink)
	rec.face.Transparency = math.max(fade, blink)
	if endKind == "Taxed" and not rec.sucked then
		rec.sucked = true
		playSound(B.def, "Vacuum", B.vpos, 0.5)
	end
	return true
end

-- THE ROAST on a silver platter (punch it: it breaks, and he chokes)
local function makePlatter(inst)
	local rec = { kind = "Platter", inst = inst, parts = {} }
	local function add(name, color, shape)
		local p = newPart(name, shape, color, Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	rec.cart = add("FeastCart", WOOD)
	rec.plate = add("FeastPlatter", SILVER, Enum.PartType.Cylinder)
	rec.roast = add("FeastRoast", ROAST)
	rec.legs = { add("FeastLeg", DUST), add("FeastLeg", DUST) }
	rec.apple = add("FeastApple", RED)
	return rec
end

local function stepPlatter(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.8) then
		return false
	end
	local g = hit.Position - V3(0, 1.5, 0)
	local born = inst:GetAttribute("Born") or now
	local roll = clamp((now - born) / 0.4, 0, 1)
	local cf = CFrame.lookAt(g, g + (B.vpos - g) * V3(1, 0, 1)) * CFrame.new(0, 0, (1 - roll) * -10)
	rec.cart.Size = V3(5, 2.4, 4)
	rec.cart.CFrame = cf * CFrame.new(0, 1.2, 0)
	rec.plate.Size = V3(0.3, 5.4, 5.4)
	rec.plate.CFrame = cf * CFrame.new(0, 2.55, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local eaten = (endKind == "Eaten") and 1 or 0
	local left = 1 - 0.7 * clamp((now - born) / 7, 0, 1) - 0.3 * eaten
	rec.roast.Size = V3(3.4 * left, 2.2 * left, 2.6 * left)
	rec.roast.CFrame = cf * CFrame.new(0, 3.8, 0)
	for i, leg in ipairs(rec.legs) do
		local side = (i == 1) and -1 or 1
		leg.Size = V3(0.5, 0.5, 1.6) * math.max(left, 0.3)
		leg.CFrame = cf * CFrame.new(side * 1.2, 4.3, -1.4)
	end
	rec.apple.Size = V3(0.9, 0.9, 0.9)
	rec.apple.CFrame = cf * CFrame.new(0, 4.4, 1.6)
	local fade = (endKind and endKind ~= "Broken") and clamp((now - endAt) / 0.5, 0, 1) or ((endKind == "Broken") and 1 or 0)
	for _, p in ipairs(rec.parts) do
		p.Transparency = fade
	end
	if endKind == "Broken" and not rec.smashed then
		rec.smashed = true
		burst(g + V3(0, 3, 0), ROAST, 16, 16, 1.2, 0.5)
		burst(g + V3(0, 3, 0), SILVER, 10, 14, 1, 0.4)
	end
	return true
end

local MAKERS = { Guard = makeGuard, Toe = makeToe, Coin = makeCoin, Platter = makePlatter }
local STEPPERS = { Guard = stepGuard, Toe = stepToe, Coin = stepCoin, Platter = stepPlatter }

local function stepProps(B, now)
	local folder = Arenas.folderFor(B.model, "GavelgruntProps") -- (his own arena copy's)
	B.props = B.props or {}
	if folder then
		for _, inst in ipairs(folder:GetChildren()) do
			if not B.props[inst] and inst:GetAttribute("Floor") == B.floor then
				local make = MAKERS[inst:GetAttribute("Kind")]
				if make then
					B.props[inst] = make(inst)
				end
			end
		end
	end
	for inst, rec in pairs(B.props) do
		local keep = inst.Parent ~= nil and STEPPERS[rec.kind](B, rec, now)
		if not keep then
			for _, p in ipairs(rec.parts) do
				p:Destroy()
			end
			if rec.ring then
				pcall(removeRing, rec.ring)
			end
			B.props[inst] = nil
		end
	end
end

-- THE PILLARS: the server swaps each for its rubble; here, the crash as it goes
local function stepPillars(B)
	local s = B.model:GetAttribute("Pillars")
	if s == B.pillarsSeen then
		return
	end
	local before = ThronePlan.decodeBroken(B.pillarsSeen)
	local now_ = ThronePlan.decodeBroken(s)
	B.pillarsSeen = s
	if not B.pillarsPrimed then
		B.pillarsPrimed = true -- (what was already broken when you arrived: no crash)
		return
	end
	local c = centerOf(B)
	for i, broken in ipairs(now_) do
		if broken and not before[i] then
			local off = ThronePlan.Pillars[i]
			local p = V3(c.X + off.X, B.vpos.Y, c.Z + off.Z)
			burst(p + V3(0, 8, 0), STONE, 26, 22, 2, 0.8)
			burst(p + V3(0, 2, 0), DUST, 20, 18, 2, 0.7)
			playSound(B.def, "Pillar", p, 1)
			kick(p, 40, 1.0, -3)
		end
	end
end

-- HIS THRONE: hidden (on every screen) while he holds it or once it's been
-- thrown; drawn where it landed
local function stepThrone(B)
	B.throneModel = (B.throneModel and B.throneModel.Parent) and B.throneModel or nil
	if not B.throneModel then
		for _, t in ipairs(game:GetService("CollectionService"):GetTagged("KingThrone")) do
			if t:GetAttribute("Floor") == B.floor and Arenas.inside(Arenas.arenaFor(B.model), t) then
				B.throneModel = t
				B.throneParts = {}
				for _, p in ipairs(t:GetDescendants()) do
					if p:IsA("BasePart") then
						table.insert(B.throneParts, { part = p, t = p.Transparency })
					end
				end
				break
			end
		end
	end
	local thrownAt = B.model:GetAttribute("ThroneAt")
	local gone = (typeof(thrownAt) == "Vector3") or B.throneHeld == true
	if B.throneParts and gone ~= B.throneGone then
		B.throneGone = gone
		for _, rec in ipairs(B.throneParts) do
			rec.part.Transparency = gone and 1 or rec.t
		end
	end
	-- where it landed: a smashed throne lying on its side
	if typeof(thrownAt) == "Vector3" then
		if not B.landedThrone then
			local seat = newPart("LandedThrone", nil, GOLD, Enum.Material.SmoothPlastic, 0)
			local back = newPart("LandedThrone", nil, GOLD, Enum.Material.SmoothPlastic, 0)
			local cushion = newPart("LandedThrone", nil, RED, Enum.Material.SmoothPlastic, 0)
			B.landedThrone = { seat, back, cushion }
		end
		local g = onFloor(thrownAt)
		local cf = CFrame.new(g) * CFrame.Angles(0, 0.7, 0)
		local s = B.landedThrone
		s[1].Size, s[1].CFrame = V3(16, 5.4, 9), cf * CFrame.new(0, 2.7, 0)
		s[2].Size, s[2].CFrame = V3(16, 2.2, 20), cf * CFrame.new(0, 1.1, 13.6) * CFrame.Angles(0.15, 0, 0)
		s[3].Size, s[3].CFrame = V3(13, 0.7, 14), cf * CFrame.new(0, 2.4, 12.8) * CFrame.Angles(0.15, 0, 0)
	elseif B.landedThrone then
		for _, p in ipairs(B.landedThrone) do
			p:Destroy()
		end
		B.landedThrone = nil
	end
end

-- The torches (ThroneBuilder's "ThroneTorch" flames): bigger and redder in round 3
local function stepTorches(B)
	if not B.torches then
		B.torches = {}
		for _, f in ipairs(game:GetService("CollectionService"):GetTagged("ThroneTorch")) do
			if f:IsA("BasePart") and f:GetAttribute("Floor") == B.floor and Arenas.inside(Arenas.arenaFor(B.model), f) then
				table.insert(B.torches, { part = f, size = f.Size, cf = f.CFrame, color = f.Color })
			end
		end
	end
	local phase = num(B.model:GetAttribute("Phase"), 1)
	local hot = phase >= 3 and (B.stateNow == "Fighting" or B.stateNow == "Transition")
	for i, tr in ipairs(B.torches) do
		if hot then
			local flick = 1 + 0.15 * math.sin(os.clock() * 14 + i)
			tr.part.Size = tr.size * V3(1.5, 1.9 * flick, 1.5)
			tr.part.CFrame = tr.cf * CFrame.new(0, tr.size.Y * 0.45, 0)
			tr.part.Color = RED
		elseif B.torchesHot then
			tr.part.Size, tr.part.CFrame, tr.part.Color = tr.size, tr.cf, tr.color
		end
	end
	B.torchesHot = hot
end

-- THE SKY over his summit (a colour grade on your screen only, while you're
-- here): a thunderstorm from the moment you arrive - darker in round 2, a red
-- eclipse in round 3 - lit up white by every flash of lightning
local function stepSky(B, here, dt)
	local Lighting = game:GetService("Lighting")
	local phase = num(B.model:GetAttribute("Phase"), 1)
	local awake = B.stateNow == "Fighting" or B.stateNow == "Transition" or B.stateNow == "Waking"
	local want, darker = 0, 0
	if here then
		want = (awake and phase >= 3) and 2 or 1
		darker = (awake and phase == 2) and 1 or 0
	end
	B.skyK = (B.skyK or 0) + (want - (B.skyK or 0)) * math.min(1, dt * 1.2)
	B.darkK = (B.darkK or 0) + (darker - (B.darkK or 0)) * math.min(1, dt * 1.2)
	local k = B.skyK
	-- (a flash, a flicker, gone)
	local flashK = 0
	if B.skyFlashAt then
		local age = os.clock() - B.skyFlashAt
		flashK = (B.skyFlashBig or 1) * (math.max(0, 1 - age / 0.12) + 0.6 * math.max(0, 1 - math.abs(age - 0.18) / 0.05))
		if age > 0.4 then
			B.skyFlashAt = nil
		end
	end
	if not here and k < 0.01 then
		if B.skyFx then
			B.skyFx:Destroy()
			B.skyFx = nil
		end
		return
	end
	if not (B.skyFx and B.skyFx.Parent) then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "KingSky"
		cc.Parent = Lighting
		B.skyFx = cc
	end
	local storm = math.min(k, 1)
	local eclipse = math.max(k - 1, 0)
	local d = B.darkK
	-- (the floor's own ambience already makes it a storm: this adds only a
	-- touch more, round 2's darker sky, round 3's eclipse and the flashes)
	local tint = WHITE:Lerp(RGB(232, 236, 248), storm):Lerp(RGB(176, 182, 214), d):Lerp(RGB(255, 120, 110), eclipse)
	B.skyFx.TintColor = tint:Lerp(WHITE, math.min(flashK, 1) * 0.6)
	B.skyFx.Brightness = -0.01 * storm - 0.06 * d - 0.06 * eclipse + 0.4 * flashK
	B.skyFx.Contrast = 0.04 * storm + 0.05 * d + 0.1 * eclipse + 0.12 * flashK
	B.skyFx.Saturation = -0.05 * storm - 0.08 * d + 0.3 * eclipse
end

-- THE LIGHTNING: every few seconds a bolt comes down somewhere out in the
-- storm - into the clouds below, among the thunderheads, now and then on the
-- battlements - more often as the fight goes on. (Never on the courtyard:
-- it's scenery - only his moves can hurt you.)
local function stepStorm(B, here)
	local now = os.clock()
	if not here or B.stateNow == "Waking" then
		B.nextBolt = nil -- (his entrance brings its own)
		return
	end
	local phase = num(B.model:GetAttribute("Phase"), 1)
	local awake = B.stateNow == "Fighting" or B.stateNow == "Transition"
	local gap = awake and ({ { 6, 11 }, { 4, 8 }, { 3, 6 } })[math.min(phase, 3)] or { 6, 11 }
	if not B.nextBolt then
		B.nextBolt = now + 1.5 + math.random() * 3
		return
	end
	if now < B.nextBolt then
		return
	end
	B.nextBolt = now + gap[1] + math.random() * (gap[2] - gap[1])
	local c = centerOf(B)
	local a = math.random() * math.pi * 2
	local to
	if math.random() < 0.25 then
		local r = ThronePlan.Wall + 1.5
		to = V3(c.X + math.sin(a) * r, c.Y + 10, c.Z + math.cos(a) * r)
	else
		local d = 110 + math.random() * 170
		to = V3(c.X + math.sin(a) * d, c.Y - 30 - math.random() * 20, c.Z + math.cos(a) * d)
	end
	strike(B, to, false)
end

-- THE RAIN: streaks driving down all round your camera and splashes on the
-- stones - like BossClient's acid rain, but cold grey storm rain, falling
-- the whole time you're up here (harder once the fight's on)
local RAIN = RGB(192, 203, 220)
local function stepRain(B, here, dt)
	local fighting = B.stateNow == "Fighting" or B.stateNow == "Transition"
	local want = here and (fighting and 1 or 0.7) or 0
	B.rainK = (B.rainK or 0) + (want - (B.rainK or 0)) * math.min(1, dt * 0.8)
	if not here and B.rainK < 0.01 then
		if B.rain then
			B.rain.cloud:Destroy()
			B.rain.floor:Destroy()
			B.rain = nil
		end
		return
	end
	if not B.rain then
		local cloud = newPart("KingRain", nil, WHITE, Enum.Material.SmoothPlastic, 1)
		cloud.Size = V3(70, 1, 70)
		local drops = Instance.new("ParticleEmitter")
		drops.Name = "Drops"
		drops.Texture = "rbxasset://textures/particles/smoke_main.dds"
		drops.Color = ColorSequence.new(RAIN)
		drops.LightEmission = 0.3
		drops.LightInfluence = 0.4
		drops.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		drops.Size = NumberSequence.new(0.3)
		drops.Squash = NumberSequence.new(6)
		drops.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, 0.35),
			NumberSequenceKeypoint.new(1, 0.45),
		})
		drops.Speed = NumberRange.new(70, 80)
		drops.Lifetime = NumberRange.new(0.45, 0.5)
		drops.EmissionDirection = Enum.NormalId.Bottom
		drops.SpreadAngle = Vector2.new(0, 0)
		drops.Shape = Enum.ParticleEmitterShape.Box
		drops.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		drops.Rate = 0
		drops.Parent = cloud
		local floorPart = newPart("KingRainSplashes", nil, WHITE, Enum.Material.SmoothPlastic, 1)
		floorPart.Size = V3(56, 0.2, 56)
		local splashes = Instance.new("ParticleEmitter")
		splashes.Name = "Splashes"
		splashes.Texture = "rbxasset://textures/particles/smoke_main.dds"
		splashes.Color = ColorSequence.new(RAIN)
		splashes.LightEmission = 0.3
		splashes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.8) })
		splashes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		splashes.Speed = NumberRange.new(2, 4)
		splashes.Lifetime = NumberRange.new(0.15, 0.25)
		splashes.EmissionDirection = Enum.NormalId.Top
		splashes.SpreadAngle = Vector2.new(70, 70)
		splashes.Shape = Enum.ParticleEmitterShape.Box
		splashes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		splashes.Rate = 0
		splashes.Parent = floorPart
		B.rain = { cloud = cloud, drops = drops, floor = floorPart, splashes = splashes }
	end
	B.rain.drops.Rate = 1300 * B.rainK
	B.rain.splashes.Rate = 220 * B.rainK
	-- (over your camera, a little ahead: where you're looking)
	local cam = workspace.CurrentCamera
	local camCF = cam and cam.CFrame
	if camCF then
		local focus = (cam.Focus or camCF).Position
		local look = camCF.LookVector
		local ahead = V3(look.X, 0, look.Z)
		if ahead.Magnitude > 0.01 then
			focus = focus + ahead.Unit * 14
		end
		local floorY = centerOf(B).Y
		B.rain.cloud.CFrame = CFrame.new(focus.X, floorY + 36, focus.Z) * CFrame.Angles(0, 0, math.rad(4))
		B.rain.floor.CFrame = CFrame.new(focus.X, floorY + 0.15, focus.Z)
	end
end

-- YOUR CAMERA for his entrance (CombatClient moves it: kit.shot): low at the
-- foot of his throne looking up at him as the lightning cracks, he stands up
-- and raises the gavel into the storm; out wide from the side as he leaps;
-- and back to you the moment he lands (as the VS splash slams in)
local function stepShot(B, here, state)
	local W = wakeBeats(B.def)
	local t = B.actionStart and (serverNow() - B.actionStart) or -1
	if not (here and state == "Waking" and B.action == "Wake" and t >= 0 and t < W.land) then
		if B.shooting then
			B.shooting = false
			shot(nil)
		end
		return
	end
	B.shooting = true
	local seat = throneSeat(B)
	local top = seat + V3(0, ThronePlan.SeatHeight, 0)
	if t < W.leap then
		local k = smooth(t / W.leap)
		local eye = top + V3(lerp(14, 8, k), lerp(-8.5, -7, k), lerp(46, 36, k))
		shot(CFrame.lookAt(eye, top + V3(0, lerp(26, 32, k), 0)), 62)
	else
		local mid = seat:Lerp(homeSpot(B), 0.55)
		local eye = mid + V3(64, 22, 14)
		shot(CFrame.lookAt(eye, B.vpos + V3(0, 26, 0)), 56)
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
	if act == "RoyalSmash" and t > A.RoyalSmash.Tell + 0.3 and t < A.RoyalSmash.Tell + A.RoyalSmash.Stuck then
		return "STUCK! HIT HIM!"
	end
	if act == "ToeStomp" and t > A.ToeStomp.Tell and t < A.ToeStomp.Tell + A.ToeStomp.Window then
		return "PUNCH HIS TOE!"
	end
	if act == "ToeHop" or act == "Choke" or act == "Tripped" or act == "Worn" then
		return "HIT HIM!"
	end
	if act == "HammerTornado" and t > A.HammerTornado.Tell + A.HammerTornado.Time + 0.1 then
		return "DIZZY! HIT HIM!"
	end
	if act == "RoyalRoll" and B.rollTotal and t > A.RoyalRoll.Tell + B.rollTotal + 0.1 then
		return "DIZZY! HIT HIM!"
	end
	if act == "RoyalFeast" and t > A.RoyalFeast.Tell then
		return "SMASH THE FEAST!"
	end
	if act == "CrownGrab" and t > A.CrownGrab.Tell then
		return "TRIP HIM!"
	end
	return nil
end

local function stepHint(B, showIt)
	local now = serverNow()
	local want = showIt and openNow(B, now) or nil
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
		bb.Name = "KingHint"
		bb.Size = UDim2.new(0, 320, 0, 32)
		bb.StudsOffsetWorldSpace = V3(0, 4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 260
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
-- what his moves are made of: stone dust
function Body.fx(def)
	local _ = def
	return { color = DUST, deep = STONE_DARK, rock = STONE_DARK, material = Enum.Material.SmoothPlastic, solid = true }
end

-- where he is between the server's updates: exactly on his leap's arc, his
-- roll's path (bounces and all) or his rush for the crown - the server's
-- own sums
function Body.glide(B, now, ground)
	local _ = ground
	local t0 = B.actionStart
	if not t0 then
		return nil
	end
	local A = B.def.Attacks
	local act = B.action
	local e = now - t0
	if act == "RoyalRoll" then
		local a = A.RoyalRoll
		local n = num(B.model:GetAttribute("ActN"), 0)
		local pts = {}
		for i = 1, n do
			local p = slot(B, i)
			if not p then
				break
			end
			pts[i] = p
		end
		if #pts < 2 then
			return nil
		end
		local run = e - a.Tell
		if run < 0 then
			return nil
		end
		for i = 1, #pts - 1 do
			local seg = flat(pts[i + 1] - pts[i]).Magnitude / a.Speed
			if run <= seg then
				return pts[i]:Lerp(pts[i + 1], run / math.max(seg, 1e-3))
			end
			run = run - seg
		end
		if run < 0.2 then
			return pts[#pts]
		end
		return nil
	elseif act == "BellyBounce" then
		local a = A.BellyBounce
		local cycle = a.Air + a.Gap
		local run = e - a.Tell
		if run < 0 then
			return nil
		end
		local i = math.floor(run / cycle) + 1
		local within = run - (i - 1) * cycle
		local to = slot(B, i)
		local from = B.hopFrom and B.hopFrom[i]
		if to and from and within <= a.Air then
			return from:Lerp(to, within / a.Air)
		end
		return nil
	elseif act == "Earthquake" then
		local a = A.Earthquake
		local run = e - a.Tell
		if run < 0 or run > a.Air + 0.2 then
			B.quakeFrom = nil
			return nil
		end
		B.quakeFrom = B.quakeFrom or B.vpos
		local c = centerOf(B)
		return B.quakeFrom:Lerp(V3(c.X, B.quakeFrom.Y, c.Z), clamp(run / a.Air, 0, 1))
	elseif act == "FinalGavel" then
		if e > 1.2 then
			B.finalFrom = nil
			return nil
		end
		B.finalFrom = B.finalFrom or B.vpos
		local c = centerOf(B)
		return B.finalFrom:Lerp(V3(c.X, B.finalFrom.Y, c.Z), clamp(e / 1.0, 0, 1))
	elseif act == "ThroneToss" then
		local a = A.ThroneToss
		if e > a.Leap + 0.2 then
			B.leapFrom = nil
			return nil
		end
		B.leapFrom = B.leapFrom or B.vpos
		local c = centerOf(B)
		local front = V3(c.X + ThronePlan.ThroneFront.X, B.leapFrom.Y, c.Z + ThronePlan.ThroneFront.Z)
		return B.leapFrom:Lerp(front, clamp(e / a.Leap, 0, 1))
	elseif act == "CrownGrab" then
		local a = A.CrownGrab
		local spot = slot(B, 1)
		local run = e - a.Tell
		if not spot or run < 0 then
			B.rushFrom = nil
			return nil
		end
		B.rushFrom = B.rushFrom or B.vpos
		return B.rushFrom:Lerp(floorAt(B, spot), clamp(run / a.Rush, 0, 1))
	end
	return nil
end

-- a new move began: reset what the last one remembered
function Body.onAction(B, name, t0, now)
	B.quakeFrom, B.finalFrom, B.leapFrom, B.rushFrom = nil, nil, nil, nil
	if name == "Wake" or name == "Dormant" or name == "Reset" then
		B.berserkLook = false
	end
	if name == "Reset" then
		B.resetFrom = B.vpos -- (he leaps back up onto his throne from here)
	end
	local _ = t0
	local _ = now
end

-- joined while he'd already broken into round 2 (or 3)
function Body.lateBreak(B)
	B.phase2Look = true
end

-- a fresh start (a reset, a new fight): calm again
function Body.calm(B, name)
	local _ = name
	B.phase2Look = false
	B.berserkLook = false
	B.torchesHot = true -- (puts the torches back once)
end

-- THE STORM NEVER FOLLOWS YOU HOME: every frame, even when his body isn't
-- being drawn at all (leave for the lobby and he can be unloaded before his
-- own senses tidy up), anything of his storm left on your screen goes the
-- moment you're not on his floor - his sky's colour grade and the rain
local stormOf = nil -- (the one whose storm is showing)
function Body.everyFrame()
	local B = stormOf
	if not B then
		return
	end
	local me = game:GetService("Players").LocalPlayer
	local stillHere = me and me:GetAttribute("SpireFloor") == B.floor and Arenas.isMine(me, B.model) and B.model.Parent ~= nil
	if stillHere then
		return
	end
	if B.skyFx then
		B.skyFx:Destroy()
		B.skyFx = nil
	end
	if B.rain then
		B.rain.cloud:Destroy()
		B.rain.floor:Destroy()
		B.rain = nil
	end
	B.skyK, B.rainK, B.skyFlashAt, B.nextBolt = 0, 0, nil, nil
	local left = game:GetService("Lighting"):FindFirstChild("KingSky")
	if left then
		left:Destroy()
	end
	stormOf = nil
end

-- every frame, whatever he's doing: his props, pillars, throne, torches, the
-- storm (sky, lightning, rain), your camera for his entrance, the hint
function Body.senses(B, dt, here, awake, state)
	B.here = here
	B.stateNow = state
	if num(B.model:GetAttribute("Phase"), 1) >= 3 and state ~= "Dormant" then
		B.berserkLook = true
	end
	local now = serverNow()
	local function run(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.warned = B.warned or {}
			if not B.warned[name] then
				B.warned[name] = true
				warn("[BossClient] Gavelgrunt's " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	run("props", stepProps, B, now)
	run("pillars", stepPillars, B)
	run("throne", stepThrone, B)
	run("torches", stepTorches, B)
	if here then
		stormOf = B
	end
	run("sky", stepSky, B, here, dt)
	run("storm", stepStorm, B, here)
	run("rain", stepRain, B, here, dt)
	run("shot", stepShot, B, here, state)
	run("hint", stepHint, B, here and awake)
end

return Body
