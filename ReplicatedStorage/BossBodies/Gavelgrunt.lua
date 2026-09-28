--[[
	Gavelgrunt  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Gavelgrunt")

	How King Gavelgrunt, Lord of the Spire (floor 10's boss, the FINAL BOSS,
	Config.Bosses[10]) looks on your screen: a chunky 8-bit GOLIATH six times
	your height - stubby tree-trunk legs in big boots, an enormous round
	belly in a royal purple robe with a gold belt straining round it, a red
	cape with a white fur collar, a big round face with a bushy moustache and
	little angry eyes, a wonky gold crown with three gems, and THE GAVEL: a
	giant wooden mallet with gold bands, taller than you. In round 2 its head
	splits open into a steel piston hammer (a glowing core, steam). In round
	3 his crown flies off, his eyes burn red and the sky turns to an eclipse.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Gavelgrunt.lua, where each move is explained):
	  * Poses[move]   his body t seconds into a move
	  * Starts[move]  the move's sounds, dust and camera kicks, and its
	                  warnings on the floor, timed on the server's clock
	  * SlotSpawns    warnings for the spots the server fills in as it goes
	  * Body.glide    exactly where he is during a leap, a roll or a rush
	  * Body.senses   every frame: his props (tin guards, the glowing toe,
	                  coins, the roast platter), the pillars crumbling, his
	                  throne (hidden once he's thrown it, drawn where it
	                  landed), the torches, the sky (a storm in round 2, a red
	                  eclipse in round 3), the GUILTY spotlight, "HIT HIM!"
	  * the moments every boss has: asleep sitting on his throne's step,
	    waking up (a stretch, a heave up, a big laugh), sitting back down
	    when everyone's gone, round 2 (the mechanical gavel), round 3 (the
	    crown flies off), falling flat on his back at the end

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: crouch, lean, twist, headPitch, sit,
	fall (on his back), faceDown (tripped), rHand / lHand (where his hands
	are, in his body's space, studs), gavelAt (a world point the gavel's head
	reaches for) or gavelDir (the way it points, in his body's space), headAt
	(the gavel's head flying off on its chain), rFoot (his right foot lifted
	/ stamping), ball / ballSpin (curled up), spinA (spinning), mouth, cheeks,
	stars (dizzy), crown ("on" / "off": round 3's crown).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, flat, easeOut
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES, bigText, shout

function Body.init(kit)
	serverNow, clamp, lerp, smooth, flat, easeOut = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.flat, kit.easeOut
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES = kit.kick, kit.playSound, kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES
	bigText, shout = kit.bigText, kit.shout
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
local SILVER = RGB(192, 203, 220)
local STEEL = RGB(139, 155, 180)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local DUST = RGB(234, 212, 170)
local WOOD = RGB(184, 111, 80)
local WOOD_DARK = RGB(115, 62, 57)
local ROAST = RGB(190, 74, 47)
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
	local arena = workspace:FindFirstChild("ThroneArena")
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

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {}, tinted = {} }
	local robe, deep, skin = def.Color, def.DeepColor, def.SkinColor or RGB(232, 183, 150)
	local gold = def.GoldColor or GOLD
	local function add(name, color, material, tint, shape)
		local p = newPart(name, shape, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, p)
		if tint then
			table.insert(body.tinted, { part = p, color = color })
		end
		return p
	end
	-- legs: short and thick as tree trunks, in big boots with gold cuffs
	body.thighs, body.shins, body.boots, body.cuffs = {}, {}, {}, {}
	for i = 1, 2 do
		body.thighs[i] = add("Thigh", robe, nil, true)
		body.shins[i] = add("Shin", deep, nil, true)
		body.boots[i] = add("Boot", WOOD_DARK, nil, true)
		body.cuffs[i] = add("BootCuff", gold, nil, true)
	end
	-- THE BELLY: huge and round (three blocks through each other make a
	-- chunky pixel ball), the robe's gold hem, the belt straining round it
	body.belly = add("Belly", robe, nil, true)
	body.bellyBand = add("BellyBand", robe, nil, true)
	body.bellyFront = add("BellyFront", robe, nil, true)
	body.belt = add("Belt", gold, nil, true)
	body.buckle = add("Buckle", YELLOW, nil, true)
	body.hem = add("RobeHem", gold, nil, true)
	body.buttons = { add("RobeButton", gold, nil, true), add("RobeButton", gold, nil, true) }
	-- the chest, shoulders, fur collar and the red cape behind
	body.chest = add("Chest", robe, nil, true)
	body.shoulders = { add("Shoulder", robe, nil, true), add("Shoulder", robe, nil, true) }
	body.collar = add("FurCollar", def.FurColor or WHITE, nil, true)
	body.cape = add("Cape", def.CapeColor or RED, nil, true)
	body.capeHem = add("CapeHem", def.FurColor or WHITE, nil, true)
	-- arms: fat sleeves, white fur cuffs, big gloved hands
	body.upperArms, body.foreArms, body.armCuffs, body.hands = {}, {}, {}, {}
	for i = 1, 2 do
		body.upperArms[i] = add("UpperArm", robe, nil, true)
		body.foreArms[i] = add("ForeArm", robe, nil, true)
		body.armCuffs[i] = add("ArmCuff", def.FurColor or WHITE, nil, true)
		body.hands[i] = add("Hand", WHITE, nil, true)
	end
	-- the head: a big round face, a nose, little eyes, a bushy moustache
	body.head = add("Head", skin, nil, true)
	body.jowls = add("Jowls", skin, nil, true)
	body.nose = add("Nose", RGB(246, 117, 122), nil, true)
	body.eyes = { add("Eye", def.EyeColor or WHITE), add("Eye", def.EyeColor or WHITE) }
	body.pupils = { add("Pupil", def.CoreColor or INK), add("Pupil", def.CoreColor or INK) }
	body.brows = { add("Brow", def.BeardColor or WOOD_DARK, nil, true), add("Brow", def.BeardColor or WOOD_DARK, nil, true) }
	body.stache = { add("Moustache", def.BeardColor or WOOD_DARK, nil, true), add("Moustache", def.BeardColor or WOOD_DARK, nil, true) }
	body.mouth = add("Mouth", def.CoreColor or INK)
	body.cheeks = { add("Cheek", RGB(246, 117, 122), nil, true), add("Cheek", RGB(246, 117, 122), nil, true) }
	-- THE CROWN: a wonky gold band, five points, three gems (round 3 knocks it off)
	body.crown = add("Crown", gold, nil, true)
	body.crownPoints = {}
	for i = 1, 5 do
		body.crownPoints[i] = add("CrownPoint", gold, nil, true)
	end
	body.gems = { add("CrownGem", RGB(0, 153, 219)), add("CrownGem", RED), add("CrownGem", GREEN) }
	-- THE GAVEL: a long handle, a big head with gold bands (round 2: steel,
	-- with a glowing piston core and steam vents), a chain for the rocket
	body.handle = add("GavelHandle", WOOD_DARK, nil, true)
	body.gHead = add("GavelHead", def.WoodColor or WOOD, nil, true)
	body.gBands = { add("GavelBand", gold, nil, true), add("GavelBand", gold, nil, true) }
	body.gCore = add("GavelCore", ORANGE, Enum.Material.Neon)
	body.gVents = { add("GavelVent", STEEL, nil, true), add("GavelVent", STEEL, nil, true) }
	body.chain = {}
	for i = 1, 8 do
		body.chain[i] = newPart("GavelChain", nil, SILVER, Enum.Material.SmoothPlastic, 1)
	end
	-- curled up into a ball (the Royal Roll): three blocks crossed through a
	-- cube make a chunky pixel ball, purple with his crown and face showing
	body.balls = {}
	for i = 1, 4 do
		body.balls[i] = add("RollBall", robe, nil, true)
	end
	body.ballFace = add("RollBallFace", skin, nil, true)
	body.ballCrown = add("RollBallCrown", gold, nil, true)
	body.ballBits = { body.ballFace, body.ballCrown }
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
	local SELF = { RollBall = true, RollBallFace = true, RollBallCrown = true, DizzyStar = true, GavelCore = true, GavelVent = true,
		Crown = true, CrownPoint = true, CrownGem = true, Cheek = true }
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
-- (his resting stance: the gavel held at his right side, head down by his
-- boot; his left hand resting on his belly) - in his body's space, studs,
-- from his hips
local REST_R = V3(9.5, 3.5, -3.5)
local REST_L = V3(-7.5, 5.5, -6.5)
local REST_GAVEL = V3(0.25, -0.75, -0.6)
local SHOULDER_Y = 13
local ARM = 5.8 -- each arm piece
local HANDLE = 15 -- the gavel's handle

local function show(p, on)
	p.Transparency = on and 0 or 1
end

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Size / 16
	local model = B.model
	local moving = model:GetAttribute("Moving") == true
	B.walk = smoothNum(B, "walkS", moving and 1 or 0, 6, dt)
	B.stridePhase = (B.stridePhase or 0) + dt * 5 * math.max(B.walk, 0.1)
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
	local sx, sy = P.sx or 1, P.sy or 1
	local sink = P.sink or 0
	local fade = P.fade or 0
	local phase = num(model:GetAttribute("Phase"), 1)
	local piston = B.phase2Look or phase >= 2
	local rage = phase >= 3 or B.berserkLook
	local flash = B.flashAt and (os.clock() - B.flashAt) < 0.1

	local jitter = V3(0, 0, 0)
	if (P.shake or 0) > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local groundPos = ground + jitter + V3(0, (P.lift or 0) - sink * 30 * u, 0)
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
	local R = 9 * u
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
		body.ballFace.Size = V3(r * 0.8, r * 0.7, 0.6 * u)
		body.ballFace.CFrame = cf * CFrame.new(0, r * 0.15, -r - 0.2 * u)
		body.ballCrown.Size = V3(r * 0.8, r * 0.3, r * 0.8)
		body.ballCrown.CFrame = cf * CFrame.new(0, r * 0.55, -r * 0.55)
	end
	for _, b in ipairs(body.ballBits) do
		show(b, balled and fade < 0.5)
	end

	-- LEGS: two pieces each, bent out under all that weight
	local hipY = (6.2 - 2.6 * math.max(crouch, 0) - 4.2 * sit) * u * sy
	local legX = (4.4 + 0.8 * math.max(crouch, 0) + 1.2 * sit) * u * sx
	local L1, L2 = 3.6 * u, 3.4 * u
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local hip = base * V3(side * legX, hipY, 0.5 * u)
		local fz = -side * stride * 2.4 * u
		local liftFoot = math.max(0, -side * stride) * 1.0 * u
		local ankle
		if sit > 0.05 then
			local sitAnkle = base * V3(side * legX * 1.2, 1.0 * u, -6.5 * u)
			ankle = (base * V3(side * legX * 1.1, 1.2 * u + liftFoot, fz)):Lerp(sitAnkle, sit)
		else
			ankle = base * V3(side * legX * 1.1, 1.2 * u + liftFoot, fz)
		end
		if i == 2 and rFoot.Magnitude > 0.01 then
			ankle = ankle + base:VectorToWorldSpace(rFoot * u)
		end
		local bend = unitOr(forward + base.RightVector * side * 0.5, forward)
		local knee, ankle2 = twoBone(hip, ankle, L1, L2, bend)
		stretch(body.thighs[i], hip, knee, 4.2 * u * sx, 4.2 * u, forward)
		stretch(body.shins[i], knee, ankle2, 3.8 * u * sx, 3.8 * u, forward)
		local boot = body.boots[i]
		boot.Size = V3(4.4 * u * sx, 2.2 * u, 6.0 * u)
		boot.CFrame = CFrame.lookAt(ankle2, ankle2 + forward) * CFrame.new(0, -0.9 * u, -1.1 * u)
		body.cuffs[i].Size = V3(4.8 * u * sx, 1.0 * u, 4.6 * u)
		body.cuffs[i].CFrame = CFrame.lookAt(ankle2, ankle2 + forward) * CFrame.new(0, 0.5 * u, 0)
		if i == 2 then
			B.toeAt = boot.CFrame * V3(0, 0, -3.2 * u)
		end
	end

	-- THE UPPER BODY: from the hips, leaning, twisting
	local torso = base * CFrame.new(0, hipY, 0) * CFrame.Angles(0, twist, 0) * CFrame.Angles(-lean, 0, 0)
	local up, tlook, right = torso.UpVector, torso.LookVector, torso.RightVector
	local breathe = 1 + 0.035 * math.sin(os.clock() * 2)
	local bw = 15 * u * sx * breathe
	-- the belly: a pixel ball (the band sticks out widest, the front bulges)
	body.belly.Size = V3(bw * 0.86, 11 * u * sy, 13 * u * breathe)
	body.belly.CFrame = torso * CFrame.new(0, 5 * u * sy, -1 * u)
	body.bellyBand.Size = V3(bw, 7 * u * sy, 12 * u * breathe)
	body.bellyBand.CFrame = torso * CFrame.new(0, 4.5 * u * sy, -1 * u)
	body.bellyFront.Size = V3(bw * 0.62, 7.5 * u * sy, 15 * u * breathe)
	body.bellyFront.CFrame = torso * CFrame.new(0, 4.6 * u * sy, -1.2 * u)
	body.belt.Size = V3(bw + 0.2 * u, 1.3 * u, 12.2 * u * breathe)
	body.belt.CFrame = torso * CFrame.new(0, 2.6 * u * sy, -1 * u)
	body.buckle.Size = V3(2.6 * u, 1.9 * u, 0.6 * u)
	body.buckle.CFrame = torso * CFrame.new(0, 2.6 * u * sy, -8.8 * u * breathe)
	body.hem.Size = V3(bw * 0.9, 0.9 * u, 12.5 * u)
	body.hem.CFrame = torso * CFrame.new(0, -0.3 * u * sy, -1 * u)
	for k, b in ipairs(body.buttons) do
		b.Size = V3(0.9, 0.9, 0.5) * u
		b.CFrame = torso * CFrame.new(0, (5.6 + (k - 1) * 2.2) * u * sy, -8.6 * u * breathe)
	end
	local chestY = 12.2 * u * sy
	body.chest.Size = V3(13 * u * sx, 5 * u * sy, 10 * u)
	body.chest.CFrame = torso * CFrame.new(0, chestY, -0.5 * u)
	local shoulders = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local scf = torso * CFrame.new(side * 7.4 * u * sx, SHOULDER_Y * u * sy, -0.5 * u)
		body.shoulders[i].Size = V3(4.4, 4.4, 5.2) * u
		body.shoulders[i].CFrame = scf
		shoulders[i] = scf.Position
	end
	body.collar.Size = V3(12.4 * u * sx, 2.4 * u, 9.6 * u)
	body.collar.CFrame = torso * CFrame.new(0, (SHOULDER_Y + 1.6) * u * sy, -0.5 * u)
	-- the cape: from his shoulders down behind him, swinging a little as he moves
	local swing = 0.18 + 0.1 * B.walk + 0.06 * math.sin(os.clock() * 1.7)
	local capeTop = torso * V3(0, (SHOULDER_Y + 0.8) * u * sy, 5 * u)
	local capeDir = (torso:VectorToWorldSpace(V3(0, -1, math.sin(swing)))).Unit
	local capeLen = (SHOULDER_Y + hipY / u - 1) * u
	local capeEnd = capeTop + capeDir * capeLen
	stretch(body.cape, capeTop, capeEnd, 14 * u * sx, 0.8 * u, tlook)
	body.capeHem.Size = V3(14.4 * u * sx, 1.2 * u, 1.2 * u)
	body.capeHem.CFrame = CFrame.lookAt(capeEnd, capeEnd + tlook)

	-- the head
	local head = torso * CFrame.new(0, (SHOULDER_Y + 5.6) * u * sy, -1.2 * u) * CFrame.Angles(-headPitch, 0, 0)
	body.head.Size = V3(8.4, 8.2, 8.2) * u
	body.head.CFrame = head
	body.jowls.Size = V3(9.2 * u, 3.2 * u, 7.6 * u)
	body.jowls.CFrame = head * CFrame.new(0, -3 * u, -0.4 * u)
	body.nose.Size = V3(1.8, 1.6, 1.6) * u
	body.nose.CFrame = head * CFrame.new(0, -0.2 * u, -4.6 * u)
	local eyeOpen = clamp(num(P.eyes, 1), 0, 1) * (1 - fade)
	local angry = rage and 0.5 or 0.2
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local ecf = head * CFrame.new(side * 1.8 * u, 1.4 * u, -4.12 * u)
		local eye, pupil = body.eyes[i], body.pupils[i]
		eye.Size = V3(1.5 * u, math.max(1.1 * u * eyeOpen, 0.05), 0.15)
		eye.CFrame = ecf
		eye.Transparency = eyeOpen < 0.05 and 1 or 0
		pupil.Size = V3(0.8 * u, math.max(0.8 * u * eyeOpen, 0.05), 0.15)
		local roll = (P.stars or 0) > 0.05 and V3(math.cos(os.clock() * 9 + i) * 0.3 * u, math.sin(os.clock() * 9 + i) * 0.25 * u, 0) or V3()
		pupil.CFrame = ecf * CFrame.new(-side * 0.15 * u + roll.X, roll.Y, -0.05)
		pupil.Transparency = eyeOpen < 0.05 and 1 or 0
		pupil.Color = rage and (def.RageColor or RED) or (def.CoreColor or INK)
		pupil.Material = rage and Enum.Material.Neon or Enum.Material.SmoothPlastic
		local brow = body.brows[i]
		brow.Size = V3(2.4 * u, 0.7 * u, 0.6 * u)
		brow.CFrame = head * CFrame.new(side * 1.8 * u, 2.5 * u, -4.2 * u) * CFrame.Angles(0, 0, side * angry)
		local st = body.stache[i]
		local flap = mouthOpen * 0.4 + 0.08 * math.sin(os.clock() * 6)
		st.Size = V3(3.8 * u, 1.2 * u, 1.0 * u)
		st.CFrame = head * CFrame.new(side * 1.9 * u, -1.5 * u, -4.5 * u) * CFrame.Angles(0, 0, -side * (0.25 + flap))
		local ch = body.cheeks[i]
		ch.Size = V3(1.6 * u + 1.6 * u * cheeks, 1.2 * u + 1.2 * u * cheeks, 0.5 * u + 1.2 * u * cheeks)
		ch.CFrame = head * CFrame.new(side * 3.3 * u, -1.2 * u, -3.9 * u)
		ch.Transparency = fade > 0.5 and 1 or (0.25 - 0.25 * cheeks)
	end
	body.mouth.Size = V3(2.6 * u, math.max(0.5 * u + 3 * u * mouthOpen, 0.05), 0.15)
	body.mouth.CFrame = head * CFrame.new(0, (-2.6 - 1.0 * mouthOpen) * u, -4.62 * u)

	-- THE CROWN (round 3 knocks it off; putting it back on shows it again)
	local crownOn = P.crown == "on" or (P.crown ~= "off" and not rage)
	local crownCF = head * CFrame.new(0.4 * u, 5 * u, 0) * CFrame.Angles(0, 0, 0.1)
	body.crown.Size = V3(8.8 * u, 2.2 * u, 8.8 * u)
	body.crown.CFrame = crownCF
	for i, pt in ipairs(body.crownPoints) do
		local x = (i - 3) * 1.9 * u
		pt.Size = V3(1.2 * u, (i % 2 == 1) and 2.4 * u or 1.8 * u, 1.2 * u)
		pt.CFrame = crownCF * CFrame.new(x, 2 * u, -4 * u)
	end
	for i, gem in ipairs(body.gems) do
		gem.Size = V3(1.1 * u, 1.1 * u, 0.4 * u)
		gem.CFrame = crownCF * CFrame.new((i - 2) * 2.8 * u, 0, -4.5 * u)
	end
	B.crownCF = crownCF
	local crownShow = crownOn and fade < 0.5 and not balled
	show(body.crown, crownShow)
	for _, pt in ipairs(body.crownPoints) do
		show(pt, crownShow)
	end
	for _, gem in ipairs(body.gems) do
		show(gem, crownShow)
	end
	B.mouthAt = head * V3(0, -2.8 * u, -4.8 * u)

	-- ARMS: from each shoulder to where the pose wants that hand
	local hands = {}
	local wants = { torso * (lHandT * u), torso * (rHandT * u) }
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local bend = (right * side * 0.7 - up * 0.3 + tlook * 0.1)
		local elbow, hand = twoBone(shoulders[i], wants[i], ARM * u, ARM * u, bend.Unit)
		hands[i] = hand
		stretch(body.upperArms[i], shoulders[i], elbow, 3.8 * u, 3.8 * u, tlook)
		stretch(body.foreArms[i], elbow, hand, 3.5 * u, 3.5 * u, tlook)
		local wristDir = unitOr(hand - elbow, -up)
		body.armCuffs[i].Size = V3(4.4, 4.4, 1.4) * u
		body.armCuffs[i].CFrame = CFrame.lookAt(hand - wristDir * 1.2 * u, hand, tlook)
		body.hands[i].Size = V3(3.6, 3.4, 3.8) * u
		body.hands[i].CFrame = CFrame.lookAt(hand, hand + wristDir, tlook)
	end
	B.handR, B.handL = hands[2], hands[1]

	-- THE GAVEL: in his right hand, reaching for gavelAt (a world point) or
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
	stretch(body.handle, hand - dirW * 1.5 * u, tip, 1.3 * u, 1.3 * u, tlook)
	local headPos = typeof(P.headAt) == "Vector3" and P.headAt or tip
	local headCF = CFrame.lookAt(headPos, headPos + dirW, tlook)
	local hw = piston and 6.6 or 6
	body.gHead.Size = V3(10 * u, hw * u, hw * u)
	body.gHead.CFrame = headCF
	body.gHead.Color = flash and WHITE or (piston and (def.SteelColor or STEEL) or (def.WoodColor or WOOD))
	for k, band in ipairs(body.gBands) do
		band.Size = V3(1.2 * u, (hw + 0.4) * u, (hw + 0.4) * u)
		band.CFrame = headCF * CFrame.new((k == 1) and -3.4 * u or 3.4 * u, 0, 0)
	end
	body.gCore.Size = V3(2.6 * u, (hw + 0.2) * u, 2.2 * u)
	body.gCore.CFrame = headCF
	body.gCore.Color = rage and (def.RageColor or RED) or ORANGE
	show(body.gCore, piston and fade < 0.5 and not balled)
	for k, v in ipairs(body.gVents) do
		v.Size = V3(1.4, 1.4, 1.8) * u
		v.CFrame = headCF * CFrame.new((k == 1) and -5.2 * u or 5.2 * u, hw * 0.3 * u, 0)
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
			local a = os.clock() * 4 + i * (math.pi * 2 / 3)
			local p = balled and (groundPos + V3(math.cos(a) * 6 * u, 2 * R + 2 * u, math.sin(a) * 6 * u))
				or (head * V3(math.cos(a) * 6 * u, 6.5 * u, math.sin(a) * 6 * u))
			st.Size = V3(2.2, 2.2, 0.9) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, os.clock() * 5)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- where word bubbles hang, and the top of his head
	B.headTop = balled and (groundPos + V3(0, 2 * R + 1, 0)) or (head * V3(0, 7 * u, 0))
	body.anchor.CFrame = CFrame.new(B.headTop + V3(0, 2, 0))

	-- his shadow
	local shadowD = 18 * u * (1 - clamp((P.lift or 0) / 60, 0, 0.7))
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.06, 0), shadowD, 0.1)
	body.shadow.Transparency = (fade > 0.5 or sink > 0.4) and 1 or 0.35

	-- colours: the hit flash; a gold glow when he's carrying taxed coins
	local taxed = num(model:GetAttribute("Taxed"), 0) > 0
	for _, rec in ipairs(body.tinted) do
		local c = rec.color
		if flash then
			c = WHITE
		elseif taxed and rec.part ~= body.head and (math.floor(os.clock() * 6) % 2 == 0) then
			c = c:Lerp(GOLD, 0.35)
		end
		rec.part.Color = c
	end
	body.head.Color = flash and WHITE or ((P.choke and RGB(0, 153, 219)) or (rage and (def.SkinColor or RGB(232, 183, 150)):Lerp(RED, 0.3)) or (def.SkinColor or RGB(232, 183, 150)))

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

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- (the gavel raised high behind his head, both hands on it)
local OVERHEAD_R = V3(3, 21, 3)
local OVERHEAD_L = V3(-1.5, 20, 3)
local OVERHEAD_DIR = V3(0, 0.25, 1)

-- ASLEEP: sitting on the courtyard stones, chin on his belly, snoring
function Poses.Dormant(B, t, P)
	P.sit = 1
	P.eyes = 0
	P.headPitch = 0.35 + 0.05 * math.sin(os.clock() * 1.1)
	P.rHand, P.lHand = V3(9, 2, -4), V3(-6, 4.5, -8)
	P.gavelDir = V3(0.4, -0.2, -1)
	P.sy = 1 + 0.03 * math.sin(os.clock() * 1.4)
	P.mouth = 0.2 + 0.2 * math.sin(os.clock() * 1.4)
	local _ = B
	local _ = t
end

-- WAKING UP: a yawn and a stretch, heaving himself up, a crack of his neck,
-- the gavel slammed on the floor, and a big royal laugh
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local u1, u2, u3 = W * 0.28, W * 0.5, W * 0.66
	if t < u1 then
		local k = smooth(t / u1)
		P.sit = 1
		P.eyes = 0.3
		P.lHand = REST_L:Lerp(V3(-5, 22, -2), k)
		P.mouth = k
		P.headPitch = 0.3 - 0.5 * k
	elseif t < u2 then
		local k = (t - u1) / (u2 - u1)
		P.sit = 1 - smooth(k)
		P.lift = math.sin(k * math.pi) * 2
		P.eyes = 1
		P.crouch = 0.3 * (1 - k)
	elseif t < u3 then
		P.crouch = 0.35
		P.rHand, P.lHand = OVERHEAD_R, OVERHEAD_L
		P.gavelDir = OVERHEAD_DIR
		P.headPitch = math.sin((t - u2) * 20) * 0.08
	else
		-- SLAM, and laugh: belly bouncing
		local e = t - u3
		P.rHand = V3(4, 3, -12)
		P.gavelDir = V3(0, -0.8, -1)
		P.lHand = V3(-7, 6, -7)
		P.mouth = 0.8 + 0.2 * math.sin(e * 22)
		P.sy = 1 + 0.05 * math.sin(e * 22)
		P.headPitch = -0.3
		P.snap = e < 0.1
	end
end

-- EVERYONE'S GONE: a smug shrug... and he sits back down for a nap
function Poses.Reset(B, t, P)
	if t < 0.8 then
		P.rHand, P.lHand = V3(10, 11, -1), V3(-10, 11, -1)
		P.headPitch = 0.1
		P.mouth = 0.4
	else
		P.sit = smooth((t - 0.8) / 0.8)
		P.eyes = 1 - smooth((t - 1.4) / 0.6)
		P.rHand, P.lHand = V3(9, 2, -4), V3(-6, 4.5, -8)
	end
	local _ = B
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
		local w = clamp((within - a.Air) / 0.3, 0, 1)
		P.sy = 1 - 0.3 * (1 - w)
		P.sx = 1 + 0.25 * (1 - w)
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

-- TOE STOMP: his right foot up... STAMP. Then it stays out there, the big
-- toe glowing (punch it!)
function Poses.ToeStomp(B, t, P)
	local a = B.def.Attacks.ToeStomp
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.rFoot = V3(0, 7 * k, -3 * k)
		P.lean = -0.1 * k
		P.rHand, P.lHand = V3(11, 9, 0), V3(-11, 9, 0)
		return
	end
	P.rFoot = V3(0, 0, -3)
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
		P.ballSpin = (a.Tell * 0.65) ^ 2 * 30 + e * a.Speed / (9 * B.def.Size / 16)
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
	local W = B.def.WakeTime
	at(B, t0 + W * 0.1, function()
		shout(B.body.anchor, "*YAWN*", 1.0, WHITE)
	end)
	at(B, t0 + W * 0.5, function()
		dust(B, B.vpos, true)
		kick(B.vpos, 30, 0.6)
	end)
	at(B, t0 + W * 0.66 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + W * 0.66, function()
		local spot = B.vpos + B.vfacing * 14
		dust(B, spot, true)
		shockRing(B, spot, 2, 18, 0.5, GOLD)
		kick(B.vpos, 60, 1.1, -4)
		shout(B.body.anchor, "HO HO HO!", 1.4, GOLD)
	end)
end

function Starts.Dormant(B, t0)
	if B.prevAction == "Reset" then
		dust(B, B.vpos, false)
	end
	local _ = t0
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		shout(B.body.anchor, "PEASANTS. HMPH.", 1.3, WHITE)
	end)
	at(B, t0 + 1.4, function()
		dust(B, B.vpos, true)
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
	local seat = tp(V3(9, 3, 5), GOLD)
	local back = tp(V3(9, 11, 1.2), GOLD)
	local cushion = tp(V3(7.4, 8, 0.4), RED)
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
			local over = ((B.handR or B.vpos) + (B.handL or B.vpos)) / 2 + V3(0, 5, 0)
			local p = over
			local spin = 0
			local spot = slot(B, 2)
			if now >= throwAt and spot then
				from = from or over
				local k = clamp((now - throwAt) / a.Flight, 0, 1)
				local g = onFloor(spot) + V3(0, 4, 0)
				p = from:Lerp(g, k) + V3(0, math.sin(k * math.pi) * (14 + flat(g - from).Magnitude * 0.2), 0)
				spin = k * 7
			end
			local cf = CFrame.lookAt(p, p + B.vfacing) * CFrame.Angles(spin, 0, 0)
			seat.Size, seat.CFrame = parts[1].size, cf
			back.Size, back.CFrame = parts[2].size, cf * CFrame.new(0, 6, 2.5)
			cushion.Size, cushion.CFrame = parts[3].size, cf * CFrame.new(0, 6, 1.8)
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
-- Every frame: his props, the pillars, the throne, torches, sky, "HIT HIM!"
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

-- HIS BIG TOE, glowing: punch it!
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
	local p = B.toeAt or (hit.Position - V3(0, 0.6, 0))
	local pulse = 1 + 0.2 * math.sin(now * 12)
	rec.glow.Size = V3(2.6, 2.2, 2.6) * pulse
	rec.glow.CFrame = CFrame.new(p + V3(0, 0.6, 0))
	rec.glow.Transparency = endKind and 1 or 0.2
	placeRing(rec.ring, onFloor(p) + V3(0, 0.1, 0), 3.2 * pulse, 0.3, 0.5, endKind and 1 or 0.2)
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
	local folder = workspace:FindFirstChild("GavelgruntProps")
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
			if t:GetAttribute("Floor") == B.floor then
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
		s[1].Size, s[1].CFrame = V3(9, 3, 5), cf * CFrame.new(0, 1.5, 0)
		s[2].Size, s[2].CFrame = V3(9, 1.2, 11), cf * CFrame.new(0, 0.6, 7.6) * CFrame.Angles(0.15, 0, 0)
		s[3].Size, s[3].CFrame = V3(7.4, 0.4, 8), cf * CFrame.new(0, 1.35, 7.2) * CFrame.Angles(0.15, 0, 0)
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
			if f:IsA("BasePart") and f:GetAttribute("Floor") == B.floor then
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

-- THE SKY: sunset in round 1, a dark storm in round 2, a red eclipse in
-- round 3 (a colour grade on your screen only, while you're here)
local function stepSky(B, here, dt)
	local Lighting = game:GetService("Lighting")
	local phase = num(B.model:GetAttribute("Phase"), 1)
	local awake = B.stateNow == "Fighting" or B.stateNow == "Transition" or B.stateNow == "Waking"
	local want = 0
	if here and awake then
		want = (phase >= 3) and 2 or ((phase == 2) and 1 or 0)
	end
	B.skyK = (B.skyK or 0) + (want - (B.skyK or 0)) * math.min(1, dt * 1.2)
	local k = B.skyK
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
	local tint = WHITE:Lerp(RGB(170, 180, 215), storm):Lerp(RGB(255, 120, 110), eclipse)
	B.skyFx.TintColor = tint
	B.skyFx.Brightness = -0.08 * storm - 0.06 * eclipse
	B.skyFx.Contrast = 0.08 * storm + 0.1 * eclipse
	B.skyFx.Saturation = -0.15 * storm + 0.25 * eclipse
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
		local front = V3(c.X + ThronePlan.Throne.X, B.leapFrom.Y, c.Z + ThronePlan.Throne.Z + 12)
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

-- every frame, whatever he's doing: his props, pillars, throne, torches, sky, the hint
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
	run("sky", stepSky, B, here, dt)
	run("hint", stepHint, B, here and awake)
end

return Body
