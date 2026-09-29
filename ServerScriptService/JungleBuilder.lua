--[[
	JungleBuilder  (ModuleScript, parent: ServerScriptService, name: "JungleBuilder")

	Builds the Spire's seventh floor: KONGO'S JUNGLE VILLAGE, Kongo's arena.

	A flat, round clearing of packed dirt in the middle of a jungle village,
	where Kongo holds his fights. Tiki torches stand round its edge. Round it
	the village: huts up on stilts with leaf roofs, rope bridges strung
	between them, two giant trees with treehouses, banana stalls, piles of
	barrels, strings of lanterns, a totem pole of Kongo's face and a big drum -
	and little monkey villagers everywhere, watching the fight. Behind the
	village a tall cliff with a waterfall thundering down into a pool (mist
	and a rainbow in the spray); the river from the pool winds round the
	village to a little dock with canoes. Thick jungle all round. You come in
	through the village gate in the south. Everything is chunky and 8-bit, in
	the game's 32 colours.

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"     where you arrive (in this model, Floor = 7)
	  * "ArenaExit"      the Leave prompt on the gate's vine curtain, plus a
	                     walk-up box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"       the middle of the clearing, Floor = 7, facing the gate
	  * "JungleEdgeWall" the invisible walls round the clearing you fight in
	  * "JungleMonkey"   the monkey villagers (models: Floor = 7, Index) - his
	                     body file makes them cheer
	  * "JungleTorch"    each tiki torch's flame (Floor = 7) - they flare up
	                     when he gets angry in round 2
	  * the model itself carries Floor = 7, Center (the middle of the
	    clearing) and FightRadius (how far out the invisible wall stands)

	Main calls JungleBuilder.Build() once at startup, after the other floors
	and before BossService (which puts Kongo on his BossHome).
	The floor you fight on is one solid, flat Part whose top is exactly y = 0
	(not Terrain: Terrain rounds its surface to its own grid). Nothing on it
	can be tripped on: the stepping stones and scuffs are paper-thin and
	can't be touched.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local JungleBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the gate; Kongo sits in the middle facing it)
----------------------------------------------------------------------
-- (well away from the lobby, the Colosseum - which is at -2600, 0, 0 - and
-- the other floors: every arena has its own spot, 2600 studs apart)
local CENTER = V3(-2600, 0, -2600)
local FIGHT_R = 70 -- the invisible wall stands this far out (the fight's edge)
local CLEARING_R = 76 -- the packed dirt goes a little further
local PATH_HALF = 7 -- half the width of the way in from the gate
local GATE_Z = 106 -- the village gate
local SPAWN_Z = 92 -- where you arrive
local POOL_Z = -150 -- the middle of the waterfall's pool
local CLIFF_Z = -178 -- the cliff's face
local RIVER_R = 150 -- the river winds round the east side this far out

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local GRASS = RGB(99, 199, 77)
local GRASS_DARK = RGB(62, 137, 72)
local GRASS_DEEP = RGB(38, 92, 66)
local DIRT = RGB(194, 133, 105)
local DIRT_DARK = RGB(184, 111, 80)
local WOOD = RGB(184, 111, 80)
local WOOD_LIGHT = RGB(228, 166, 114)
local WOOD_DARK = RGB(115, 62, 57)
local BARK = RGB(62, 39, 49)
local THATCH = RGB(234, 212, 170)
local THATCH_DARK = RGB(228, 166, 114)
local BAMBOO = RGB(254, 231, 97)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local STONE_DEEP = RGB(58, 68, 102)
local WATER = RGB(0, 153, 219)
local WATER_LIGHT = RGB(44, 232, 245)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local ORANGE = RGB(247, 118, 34)
local YELLOW = RGB(254, 231, 97)
local PINK = RGB(246, 117, 122)
local PURPLE = RGB(104, 56, 108)
local FUR = RGB(115, 62, 57)
local SKIN = RGB(232, 183, 150)
local GOLD = RGB(254, 174, 52)
local KONGO_FACE = RGB(165, 160, 172) -- (Kongo's pale grey face, on the totem)
local RAINBOW = { RED, ORANGE, YELLOW, GRASS, WATER_LIGHT, WATER, PURPLE }

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other floors')
----------------------------------------------------------------------
local seed = 20261004
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function between(a, b)
	return a + (b - a) * rnd()
end
local function pick(list)
	return list[math.floor(rnd() * #list) + 1]
end

local m -- the arena model, set by Build()

-- small decoration: no collisions, no raycasts, no shadow
local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
-- big scenery nobody can reach: no collisions or raycasts, but it does shade
local SCENERY = { CanCollide = false, CanQuery = false }

local function part(name, size, cf, color, extra, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Mat.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent or m
	return p
end

local function merge(a, b)
	local out = {}
	for k, v in pairs(a or {}) do
		out[k] = v
	end
	for k, v in pairs(b or {}) do
		out[k] = v
	end
	return out
end

-- Upright cylinder: `cf` is the centre, the axis points up
local function cylinder(name, height, d, cf, color, extra, parent)
	return part(name, V3(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, merge(extra, { Shape = Enum.PartType.Cylinder }), parent)
end

local function ball(name, d, cf, color, extra, parent)
	return part(name, V3(d, d, d), cf, color, merge(extra, { Shape = Enum.PartType.Ball }), parent)
end

-- a block stretched from a to b (a beam, a rope, a pole), `w` thick
local function beam(name, a, b, w, color, extra, parent)
	local len = (b - a).Magnitude
	return part(name, V3(w, w, math.max(len, 0.05)), CFrame.lookAt((a + b) / 2, b), color, extra, parent)
end

local function anchorPart(name, cf, parent)
	return part(name, V3(1, 1, 1), cf, WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

-- a slow glow in and out (LobbyFX animates anything tagged "Pulse")
local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
end

-- words on a board (a SurfaceGui on its front face)
local function signText(board, text, color, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(board.Size.X * 50, board.Size.Y * 50)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	pcall(function()
		label.FontFace = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	label.Parent = gui
	gui.Parent = board
	return gui
end

-- walking into this box opens the "Leave?" check (SpireClient watches these)
local function autoZone(cf, size, attr, value)
	local z = part("AutoOpenZone", size, cf, WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	z:SetAttribute(attr, value)
	CollectionService:AddTag(z, "AutoOpenZone")
	return z
end

local function at(x, y, z)
	return CENTER + V3(x, y, z)
end
-- angle 0 is south (+Z, the gate); pi/2 is east; pi is north (the waterfall)
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y or 0, math.cos(a) * r)
end
-- a frame at `p` whose front (-Z) faces the middle of the clearing
local function facingCentre(p)
	local flat = V3(CENTER.X, p.Y, CENTER.Z)
	if (flat - p).Magnitude < 0.01 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, flat)
end
local function wrap(a)
	return (a + math.pi) % (math.pi * 2) - math.pi
end

-- how wide (in angle) the way in from the gate is, at the clearing's wall
local GAP_ANGLE = math.asin((PATH_HALF + 1) / FIGHT_R)

----------------------------------------------------------------------
-- The ground: the clearing you fight in, the jungle floor, the way in
----------------------------------------------------------------------
local function buildGround()
	-- the jungle floor all round (a little lower than the clearing)
	cylinder("JungleGround", 4, 520, CFrame.new(at(0, -2.2, 0)), GRASS_DARK)
	-- THE CLEARING: one solid disc of packed dirt, top at exactly y = 0
	cylinder("ClearingFloor", 4, CLEARING_R * 2, CFrame.new(at(0, -2, 0)), DIRT)
	-- the way in from the gate: the same dirt, a hair lower (two floors at
	-- exactly the same height flicker where they overlap)
	part("GatePath", V3(PATH_HALF * 2 + 2, 4, GATE_Z + 14 - (FIGHT_R - 6)), CFrame.new(at(0, -2.03, (FIGHT_R - 6 + GATE_Z + 14) / 2)), DIRT)
	-- a darker trodden ring round the clearing's rim, and grass tufts
	for k = 0, 47 do
		local a = (k + 0.5) / 48 * math.pi * 2
		if math.abs(wrap(a)) > GAP_ANGLE + 0.05 then
			local p = onRing(CLEARING_R + 1.5, a, -0.5)
			part("ClearingRim", V3(2 * (CLEARING_R + 1.5) * math.tan(math.pi / 48) + 0.4, 1.2, 3), facingCentre(p), DIRT_DARK, SCENERY)
		end
	end
	for _ = 1, 70 do
		local a, r = rnd() * math.pi * 2, between(CLEARING_R + 2, CLEARING_R + 30)
		local p = onRing(r, a, -0.2)
		if math.abs(wrap(a)) > 0.2 then
			local h = between(0.8, 1.8)
			part("GrassTuft", V3(between(1, 2), h, between(1, 2)), CFrame.new(p + V3(0, h / 2, 0)) * CFrame.Angles(0, rnd() * 3, 0),
				pick({ GRASS, GRASS_DARK }), DECOR)
		end
	end
	-- a ring of flat stepping stones marking the fighting circle, and scuffs in
	-- the dirt (paper-thin, and nothing can touch them: nothing to trip on)
	for k = 0, 35 do
		local a = (k + 0.5) / 36 * math.pi * 2
		if math.abs(wrap(a)) > GAP_ANGLE + 0.1 then
			local p = onRing(60, a, 0.02)
			part("RingStone", V3(between(2.4, 3.2), 0.1, between(1.8, 2.4)), facingCentre(p) * CFrame.Angles(0, between(-0.3, 0.3), 0),
				pick({ STONE, STONE_DARK }), DECOR)
		end
	end
	for _ = 1, 16 do
		local a, r = rnd() * math.pi * 2, between(8, 52)
		local p = onRing(r, a, 0.015)
		part("Scuff", V3(between(3, 7), 0.06, between(1.2, 2.5)), CFrame.new(p) * CFrame.Angles(0, rnd() * 3, 0), DIRT_DARK, DECOR)
	end
end

----------------------------------------------------------------------
-- Tiki torches round the clearing (their flames flare in round 2)
----------------------------------------------------------------------
local function tikiTorch(p, index)
	local base = CFrame.new(p)
	part("TorchPole", V3(0.9, 8, 0.9), base * CFrame.new(0, 4, 0), BAMBOO, SCENERY)
	for _, y in ipairs({ 2.2, 4.4, 6.6 }) do
		part("TorchBand", V3(1.1, 0.25, 1.1), base * CFrame.new(0, y, 0), WOOD_DARK, DECOR)
	end
	part("TorchCup", V3(1.8, 1.2, 1.8), base * CFrame.new(0, 8.4, 0), WOOD_DARK, SCENERY)
	local flame = part("TorchFlame", V3(1.3, 1.9, 1.3), base * CFrame.new(0, 9.8, 0) * CFrame.Angles(0, 0.78, 0), ORANGE,
		merge(DECOR, { Material = Mat.Neon }))
	part("TorchFlameCore", V3(0.7, 1.1, 0.7), base * CFrame.new(0, 9.6, 0) * CFrame.Angles(0, 0.2, 0), YELLOW, merge(DECOR, { Material = Mat.Neon }))
	flame:SetAttribute("Floor", 7)
	flame:SetAttribute("Index", index)
	CollectionService:AddTag(flame, "JungleTorch")
	pulse(flame, 1.4, 0, 0.25)
	light(flame, RGB(255, 170, 90), 16, 1.2)
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Embers"
	fire.Color = ColorSequence.new(ORANGE, YELLOW)
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.5, 1)
	fire.Speed = NumberRange.new(2, 4)
	fire.SpreadAngle = Vector2.new(20, 20)
	fire.Rate = 5
	fire.Parent = flame
end

local function buildTorches()
	local n = 0
	for k = 0, 17 do
		local a = (k + 0.5) / 18 * math.pi * 2
		if math.abs(wrap(a)) > GAP_ANGLE + 0.12 then
			n = n + 1
			tikiTorch(onRing(FIGHT_R + 3, a, 0), n)
		end
	end
	-- and two either side of the way in
	for _, sx in ipairs({ -1, 1 }) do
		n = n + 1
		tikiTorch(at(sx * (PATH_HALF + 3), 0, FIGHT_R + 6), n)
	end
end

----------------------------------------------------------------------
-- The monkey villagers (his body file makes them cheer and jump)
----------------------------------------------------------------------
local monkeys = 0
local function monkey(cf)
	monkeys = monkeys + 1
	local mk = Instance.new("Model")
	mk.Name = "JungleMonkey"
	local s = between(0.85, 1.15)
	local body = part("MonkeyBody", V3(1.5, 1.6, 1.2) * s, cf * CFrame.new(0, 1.3 * s, 0), FUR, DECOR, mk)
	part("MonkeyBelly", V3(1.0, 1.0, 0.1) * s, cf * CFrame.new(0, 1.2 * s, -0.62 * s), SKIN, DECOR, mk)
	part("MonkeyHead", V3(1.5, 1.3, 1.3) * s, cf * CFrame.new(0, 2.75 * s, 0), FUR, DECOR, mk)
	part("MonkeyFace", V3(1.1, 0.8, 0.12) * s, cf * CFrame.new(0, 2.65 * s, -0.68 * s), SKIN, DECOR, mk)
	for _, sx in ipairs({ -1, 1 }) do
		part("MonkeyEye", V3(0.22, 0.26, 0.05) * s, cf * CFrame.new(sx * 0.25 * s, 2.8 * s, -0.75 * s), INK, DECOR, mk)
		part("MonkeyEar", V3(0.3, 0.55, 0.55) * s, cf * CFrame.new(sx * 0.85 * s, 2.8 * s, 0), SKIN, DECOR, mk)
		part("MonkeyArm", V3(0.45, 1.4, 0.45) * s, cf * CFrame.new(sx * 0.95 * s, 1.35 * s, 0), FUR, DECOR, mk)
		part("MonkeyLeg", V3(0.5, 0.7, 0.55) * s, cf * CFrame.new(sx * 0.4 * s, 0.35 * s, 0), FUR, DECOR, mk)
	end
	part("MonkeyTail", V3(0.3, 0.3, 1.4) * s, cf * CFrame.new(0, 0.9 * s, 1.1 * s) * CFrame.Angles(0.6, 0, 0), FUR, DECOR, mk)
	mk.PrimaryPart = body
	mk:SetAttribute("Floor", 7)
	mk:SetAttribute("Index", monkeys)
	CollectionService:AddTag(mk, "JungleMonkey")
	mk.Parent = m
	return mk
end

----------------------------------------------------------------------
-- The huts on stilts, and the rope bridges between them
----------------------------------------------------------------------
local HUT_ANGLES = { 0.95, 1.5, 2.05, 2.6, -0.95, -1.5, -2.05, -2.6 }
local HUT_R = 100
local DECK_Y = 9 -- how high the huts' floors are

-- a thatched roof: layers of straw, each a little smaller, with a point on top
local function thatch(cf, w, d, layers)
	for i = 0, layers - 1 do
		local k = 1 - i / layers
		part("Thatch", V3(w * k + 1, 1.3, d * k + 1), cf * CFrame.new(0, 0.65 + i * 1.2, 0),
			(i % 2 == 0) and THATCH or THATCH_DARK, SCENERY)
	end
	part("ThatchTop", V3(1.4, 1.6, 1.4), cf * CFrame.new(0, layers * 1.2 + 0.4, 0), WOOD_DARK, SCENERY)
end

local function hut(a, index)
	local p = onRing(HUT_R + between(-6, 6), a, -0.2)
	local cf = facingCentre(p) * CFrame.Angles(0, between(-0.25, 0.25), 0)
	local w, d = between(12, 15), between(11, 13)
	-- stilts, braces and the deck
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part("Stilt", V3(1.2, DECK_Y + 0.4, 1.2), cf * CFrame.new(sx * (w / 2 - 0.8), DECK_Y / 2, sz * (d / 2 - 0.8)), WOOD_DARK, SCENERY)
		end
		beam("StiltBrace", (cf * CFrame.new(sx * (w / 2 - 0.8), 1.5, d / 2 - 0.8)).Position,
			(cf * CFrame.new(sx * (w / 2 - 0.8), DECK_Y - 1, -(d / 2 - 0.8))).Position, 0.5, WOOD, DECOR)
	end
	part("HutDeck", V3(w + 3, 0.8, d + 3), cf * CFrame.new(0, DECK_Y, 0), WOOD, SCENERY)
	part("DeckEdge", V3(w + 3.2, 0.4, d + 3.2), cf * CFrame.new(0, DECK_Y - 0.5, 0), WOOD_DARK, DECOR)
	-- walls: bamboo, with a doorway facing the clearing and a window each side
	local wallH = 6.5
	local y = DECK_Y + 0.4 + wallH / 2
	part("HutWallBack", V3(w, wallH, 0.7), cf * CFrame.new(0, y, d / 2), BAMBOO, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("HutWallSide", V3(0.7, wallH, d), cf * CFrame.new(sx * w / 2, y, 0), BAMBOO, SCENERY)
		part("HutWindow", V3(0.2, 1.8, 2.2), cf * CFrame.new(sx * (w / 2 + 0.36), y + 0.6, 0), INK, DECOR)
		local side = (w - 4) / 2
		part("HutWallFront", V3(side, wallH, 0.7), cf * CFrame.new(sx * (2 + side / 2), y, -d / 2), BAMBOO, SCENERY)
	end
	part("HutLintel", V3(4.4, 1.2, 0.8), cf * CFrame.new(0, DECK_Y + 0.4 + wallH - 0.6, -d / 2), WOOD_DARK, SCENERY)
	part("HutDoorway", V3(4, wallH - 1.2, 0.1), cf * CFrame.new(0, DECK_Y + 0.4 + (wallH - 1.2) / 2, -d / 2 + 0.2), INK, DECOR)
	-- bamboo stripes on the walls
	for k = -2, 2 do
		part("HutStripe", V3(0.25, wallH, 0.75), cf * CFrame.new(k * (w / 5), y, d / 2 + 0.02), THATCH_DARK, DECOR)
	end
	thatch(cf * CFrame.new(0, DECK_Y + 0.4 + wallH, 0), w + 3, d + 3, 4)
	-- a ladder down to the ground on the clearing side
	local l0 = cf * CFrame.new(0, 0, -(d / 2 + 2.6))
	for _, sx in ipairs({ -1, 1 }) do
		beam("LadderRail", (l0 * CFrame.new(sx * 1.1, 0, 1.2)).Position, (l0 * CFrame.new(sx * 1.1, DECK_Y + 0.4, -0.2)).Position, 0.35, WOOD_DARK, DECOR)
	end
	for k = 1, 5 do
		local ly = k * (DECK_Y / 6)
		part("LadderRung", V3(2.4, 0.3, 0.3), l0 * CFrame.new(0, ly, 1.2 - 1.4 * (ly / DECK_Y)), WOOD, DECOR)
	end
	-- a monkey or two out on the deck, watching the fight
	monkey(cf * CFrame.new(-w / 2 + 1.5, DECK_Y + 0.4, -d / 2 - 0.8))
	if index % 2 == 0 then
		monkey(cf * CFrame.new(w / 2 - 1.5, DECK_Y + 0.4, -d / 2 - 0.8))
	end
	return cf, w, d
end

-- a rope bridge from deck to deck: planks along a sagging curve, rope rails,
-- and paper lanterns hanging from the ropes
local function ropeBridge(a0, b0, withMonkey)
	local dir = (b0 - a0)
	local n = math.max(6, math.floor(dir.Magnitude / 2.2))
	local side = V3(-dir.Unit.Z, 0, dir.Unit.X)
	local sag = math.min(3.5, dir.Magnitude * 0.08)
	local function point(u)
		return a0:Lerp(b0, u) - V3(0, math.sin(u * math.pi) * sag, 0)
	end
	for i = 1, n - 1 do
		local u = i / n
		local p = point(u)
		local ahead = point(math.min(u + 0.01, 1))
		local cf = CFrame.lookAt(p, V3(ahead.X, ahead.Y, ahead.Z) + dir.Unit * 0.01)
		part("BridgePlank", V3(3.4, 0.3, 1.5), cf, (i % 2 == 0) and WOOD or WOOD_LIGHT, DECOR)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local last = a0 + side * sx * 1.8 + V3(0, 2.4, 0)
		for i = 1, 8 do
			local u = i / 8
			local p = point(u) + side * sx * 1.8 + V3(0, 2.4, 0)
			beam("BridgeRope", last, p, 0.18, WOOD_LIGHT, DECOR)
			if i % 2 == 0 and sx == 1 then
				local lamp = part("Lantern", V3(0.8, 1.1, 0.8), CFrame.new(p - V3(0, 1, 0)), pick({ RED, ORANGE, YELLOW, PINK }),
					merge(DECOR, { Material = Mat.Neon }))
				pulse(lamp, 0.5, 0.05, 0.3)
			end
			last = p
		end
	end
	if withMonkey then
		local mid = point(0.5)
		monkey(CFrame.lookAt(mid, V3(CENTER.X, mid.Y, CENTER.Z)) * CFrame.new(0, 0.15, 0))
	end
end

local function buildVillage()
	local decks = {}
	for i, a in ipairs(HUT_ANGLES) do
		local cf, w, d = hut(a, i)
		decks[i] = { cf = cf, w = w, d = d }
	end
	-- bridges between neighbouring huts on each side (east: 1-2-3-4, west: 5-6-7-8)
	for _, pair in ipairs({ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 5, 6 }, { 6, 7 }, { 7, 8 } }) do
		local A, Bd = decks[pair[1]], decks[pair[2]]
		local pa, pb = A.cf.Position, Bd.cf.Position
		local toB = (pb - pa)
		local flatDir = V3(toB.X, 0, toB.Z).Unit
		local a0 = V3(pa.X, pa.Y + DECK_Y + 0.4, pa.Z) + flatDir * (A.w / 2 + 1.2)
		local b0 = V3(pb.X, pb.Y + DECK_Y + 0.4, pb.Z) - flatDir * (Bd.w / 2 + 1.2)
		ropeBridge(a0, b0, pair[1] % 2 == 1)
	end
end

----------------------------------------------------------------------
-- Two giant trees with treehouses, flanking the gate
----------------------------------------------------------------------
local function giantTree(p, treehouse)
	local trunkH = 44
	cylinder("GiantTrunk", trunkH, 7, CFrame.new(p + V3(0, trunkH / 2 - 0.5, 0)), BARK, SCENERY)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2 + 0.3
		local root = p + V3(math.cos(a) * 4.2, 1.2, math.sin(a) * 4.2)
		beam("GiantRoot", root + V3(0, 2.5, 0) - V3(math.cos(a), 0, math.sin(a)) * 2.5, root + V3(math.cos(a) * 2, -1.2, math.sin(a) * 2), 1.6, BARK, SCENERY)
	end
	for i, c in ipairs({ { 0, 46, 0, 26 }, { 7, 42, 4, 16 }, { -6, 43, -5, 17 }, { 3, 51, -3, 15 }, { -4, 50, 5, 14 } }) do
		part("GiantLeaves", V3(c[4], c[4] * 0.45, c[4]), CFrame.new(p + V3(c[1], c[2], c[3])) * CFrame.Angles(0, i * 0.7, 0),
			(i % 2 == 0) and GRASS or GRASS_DARK, SCENERY)
	end
	if treehouse then
		local y = 26
		local cf = facingCentre(p + V3(0, y, 0))
		part("TreeDeck", V3(14, 0.8, 14), cf, WOOD, SCENERY)
		for _, sx in ipairs({ -1, 1 }) do
			part("TreeRail", V3(0.4, 1.6, 14), cf * CFrame.new(sx * 6.8, 1.2, 0), WOOD_DARK, DECOR)
		end
		part("TreeRailFront", V3(14, 1.6, 0.4), cf * CFrame.new(0, 1.2, -6.8), WOOD_DARK, DECOR)
		part("TreeHouse", V3(8, 6, 7), cf * CFrame.new(0, 3.4, 2.5), BAMBOO, SCENERY)
		part("TreeHouseDoor", V3(2.4, 3.6, 0.1), cf * CFrame.new(0, 2.2, -1.05), INK, DECOR)
		thatch(cf * CFrame.new(0, 6.4, 2.5), 10, 9, 3)
		-- a rope ladder down the trunk
		for k = 1, 12 do
			part("RopeRung", V3(2.2, 0.25, 0.25), cf * CFrame.new(0, -y + k * (y / 13), -3.9), WOOD_LIGHT, DECOR)
		end
		monkey(cf * CFrame.new(-3.5, 0.4, -5.5))
		monkey(cf * CFrame.new(3.5, 0.4, -5.5))
	end
end

----------------------------------------------------------------------
-- The village bits: banana stalls, barrels, the totem, the drum, lanterns
----------------------------------------------------------------------
local function banana(cf)
	for k = 0, 2 do
		part("Banana", V3(0.45, 0.45, 1.5), cf * CFrame.new((k - 1) * 0.42, 0, 0) * CFrame.Angles(0.35, (k - 1) * 0.3, 0), YELLOW, DECOR)
	end
end

local function bananaStall(cf)
	part("StallCounter", V3(8, 3, 3), cf * CFrame.new(0, 1.5, 0), WOOD, SCENERY)
	part("StallTop", V3(8.4, 0.4, 3.4), cf * CFrame.new(0, 3.2, 0), WOOD_DARK, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("StallPost", V3(0.6, 7, 0.6), cf * CFrame.new(sx * 3.8, 3.5, 1.4), WOOD_DARK, SCENERY)
	end
	part("StallRoof", V3(9.4, 0.6, 4.8), cf * CFrame.new(0, 7.2, 0.4) * CFrame.Angles(-0.25, 0, 0), GRASS, SCENERY)
	for k = -3, 3 do
		banana(cf * CFrame.new(k * 1.05, 3.65, -0.3))
	end
	local sign = part("StallSign", V3(5, 1.4, 0.3), cf * CFrame.new(0, 6.1, -1.3), WOOD_LIGHT, SCENERY)
	signText(sign, "BANANAS", RED_DARK, Enum.NormalId.Front)
end

local function barrel(cf)
	cylinder("Barrel", 3.2, 2.6, cf * CFrame.new(0, 1.6, 0), WOOD, SCENERY)
	for _, y in ipairs({ 0.5, 1.6, 2.7 }) do
		cylinder("BarrelBand", 0.3, 2.75, cf * CFrame.new(0, y, 0), WOOD_DARK, DECOR)
	end
end

local function barrelPile(p)
	local cf = facingCentre(p)
	for _, o in ipairs({ { -1.5, 0, 0 }, { 1.5, 0, 0.3 }, { 0, 0, 2.4 } }) do
		barrel(cf * CFrame.new(o[1], o[2], o[3]))
	end
	barrel(cf * CFrame.new(0, 3.2, 1.0) * CFrame.Angles(0, 0.4, 0))
	-- and a TNT barrel, of course
	local tnt = cylinder("TNTBarrel", 3.2, 2.6, cf * CFrame.new(3.2, 1.6, 2.6), RED, SCENERY)
	cylinder("TNTBand", 0.9, 2.7, cf * CFrame.new(3.2, 1.6, 2.6), YELLOW, DECOR)
	local _ = tnt
end

local function totem(p)
	local cf = facingCentre(p)
	local faces = { WOOD, WOOD_DARK, WOOD }
	for i, c in ipairs(faces) do
		local y = (i - 1) * 5
		part("TotemBlock", V3(5, 5, 5), cf * CFrame.new(0, y + 2.5, 0), c, SCENERY)
		part("TotemBrow", V3(5.2, 0.9, 1), cf * CFrame.new(0, y + 3.7, -2.4), BARK, DECOR)
		part("TotemMuzzle", V3(3.4, 2, 1), cf * CFrame.new(0, y + 1.6, -2.5), (i == 3) and KONGO_FACE or WOOD_LIGHT, DECOR)
		for _, sx in ipairs({ -1, 1 }) do
			part("TotemEye", V3(0.9, 0.9, 0.3), cf * CFrame.new(sx * 1.1, y + 2.9, -2.55), (i == 3) and WHITE or YELLOW, DECOR)
		end
		part("TotemMouth", V3(2, 0.4, 0.3), cf * CFrame.new(0, y + 1.1, -3.05), INK, DECOR)
	end
	-- Kongo's own face on top (painted grey): his gold banana chain under it, and a crown of leaves
	part("TotemChain", V3(3.6, 0.5, 0.3), cf * CFrame.new(0, 10.5 - 0.5, -2.6), GOLD, DECOR)
	part("TotemBanana", V3(1.4, 0.7, 0.35), cf * CFrame.new(0, 10.5 - 1.3, -2.65), YELLOW, DECOR)
	for k = -2, 2 do
		part("TotemLeaf", V3(1.2, 3, 0.5), cf * CFrame.new(k * 1.1, 16.2, 0) * CFrame.Angles(0, 0, k * 0.28), GRASS, DECOR)
	end
end

local function bigDrum(p)
	local cf = facingCentre(p)
	cylinder("DrumBody", 5, 7, cf * CFrame.new(0, 2.5, 0), RED_DARK, SCENERY)
	cylinder("DrumSkin", 0.4, 6.6, cf * CFrame.new(0, 5.1, 0), THATCH, SCENERY)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		beam("DrumCord", (cf * CFrame.new(math.cos(a) * 3.45, 5, math.sin(a) * 3.45)).Position,
			(cf * CFrame.new(math.cos(a + 0.4) * 3.45, 0.4, math.sin(a + 0.4) * 3.45)).Position, 0.2, THATCH_DARK, DECOR)
	end
	local drum = cf * CFrame.new(0, 5.4, 0)
	local skin = part("DrumHit", V3(0.5, 0.5, 0.5), drum, THATCH, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	skin:SetAttribute("Floor", 7)
	CollectionService:AddTag(skin, "JungleDrum")
	for _, sx in ipairs({ -1, 1 }) do
		beam("DrumStick", (cf * CFrame.new(sx * 2.5, 5.4, -3)).Position, (cf * CFrame.new(sx * 1.2, 7.4, -1.2)).Position, 0.3, WOOD_LIGHT, DECOR)
	end
end

local function buildVillageBits()
	-- the totem pole and the big drum at the clearing's north edge, either side
	-- of the view to the waterfall
	totem(onRing(FIGHT_R + 9, math.pi - 0.28, -0.2))
	bigDrum(onRing(FIGHT_R + 8, math.pi + 0.28, -0.2))
	-- banana stalls by the way in
	bananaStall(CFrame.lookAt(at(-18, -0.2, FIGHT_R + 20), at(-6, -0.2, FIGHT_R + 20)))
	bananaStall(CFrame.lookAt(at(18, -0.2, FIGHT_R + 20), at(6, -0.2, FIGHT_R + 20)))
	-- piles of barrels round the edge (that's where he gets them!)
	for _, a in ipairs({ 0.62, 1.22, 1.78, 2.33, -0.62, -1.22, -1.78, -2.33 }) do
		barrelPile(onRing(FIGHT_R + 9, a, -0.2))
	end
	-- banana crates
	for _, a in ipairs({ 0.4, -0.4, 2.85, -2.85 }) do
		local p = onRing(FIGHT_R + 14, a, -0.2)
		local cf = facingCentre(p)
		part("Crate", V3(3.4, 2.4, 2.8), cf * CFrame.new(0, 1.2, 0), WOOD_LIGHT, SCENERY)
		part("CrateSlat", V3(3.5, 0.3, 2.9), cf * CFrame.new(0, 1.2, 0), WOOD_DARK, DECOR)
		for k = -1, 1 do
			banana(cf * CFrame.new(k * 1.0, 2.6, 0))
		end
	end
end

----------------------------------------------------------------------
-- The waterfall, its pool (mist and a rainbow), the river, the dock
----------------------------------------------------------------------
local function buildWaterfall()
	-- THE CLIFF: great blocks of mossy rock, taller in the middle
	for k = -9, 9 do
		local x = k * 16
		local h = 70 + math.cos(k / 9 * math.pi / 2) * 30 + between(-6, 6)
		if math.abs(k) >= 1 then
			part("Cliff", V3(17, h, 30), CFrame.new(at(x, h / 2 - 1, CLIFF_Z - 15 + math.abs(k) * 1.5)), (k % 2 == 0) and STONE_DARK or STONE_DEEP, SCENERY)
			part("CliffMoss", V3(17.4, 3, 30.4), CFrame.new(at(x, h - 1, CLIFF_Z - 15 + math.abs(k) * 1.5)), GRASS_DARK, SCENERY)
			for _ = 1, 2 do
				local y = between(12, h - 10)
				part("CliffLedge", V3(between(5, 9), 1.6, 3), CFrame.new(at(x + between(-5, 5), y, CLIFF_Z + 0.5 + math.abs(k) * 1.5)), GRASS, DECOR)
			end
		end
	end
	-- the notch the water pours over, and the rock behind it
	local topY = 96
	part("FallsBack", V3(30, topY, 20), CFrame.new(at(0, topY / 2 - 1, CLIFF_Z - 18)), STONE_DEEP, SCENERY)
	part("FallsLip", V3(32, 3, 10), CFrame.new(at(0, topY, CLIFF_Z - 4)), STONE_DARK, SCENERY)
	-- THE WATERFALL: a sheet of water from the lip to the pool, with white
	-- streaks running down it and falling spray
	local sheet = part("Waterfall", V3(26, topY, 2), CFrame.new(at(0, topY / 2, CLIFF_Z + 1)), WATER,
		merge(SCENERY, { Transparency = 0.15, Material = Mat.Glass }))
	for k = -5, 5 do
		local h = between(30, topY - 10)
		part("FallsStreak", V3(1, h, 0.4), CFrame.new(at(k * 2.3, between(h / 2, topY - h / 2), CLIFF_Z + 2.3)), (k % 2 == 0) and WHITE or WATER_LIGHT,
			merge(DECOR, { Transparency = 0.25, Material = Mat.Neon }))
	end
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Color = ColorSequence.new(WHITE, WATER_LIGHT)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.5) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(1.5, 2.5)
	spray.Speed = NumberRange.new(20, 30)
	spray.EmissionDirection = Enum.NormalId.Bottom
	spray.SpreadAngle = Vector2.new(4, 4)
	spray.Rate = 14
	spray.Parent = sheet
	-- THE POOL, with foam where the water lands and rocks round it
	cylinder("Pool", 1, 72, CFrame.new(at(0, -0.6, POOL_Z)), WATER, SCENERY)
	cylinder("PoolShallows", 1, 78, CFrame.new(at(0, -0.65, POOL_Z)), WATER_LIGHT, SCENERY)
	for _ = 1, 14 do
		local a, r = rnd() * math.pi * 2, between(0, 9)
		local p = at(math.cos(a) * r, 0, CLIFF_Z + 7 + math.sin(a) * r * 0.5)
		part("Foam", V3(between(3, 6), between(0.8, 1.6), between(3, 6)), CFrame.new(p) * CFrame.Angles(0, rnd() * 3, 0), WHITE, DECOR)
	end
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2
		local p = at(math.sin(a) * 38, 0, POOL_Z + math.cos(a) * 38)
		if math.cos(a) > -0.5 then
			local s = between(2.5, 5)
			part("PoolRock", V3(s * 1.3, s * 0.8, s), CFrame.new(p + V3(0, s * 0.2, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick({ STONE, STONE_DARK }), SCENERY)
		end
	end
	local mist = part("Mist", V3(30, 2, 12), CFrame.new(at(0, 2, CLIFF_Z + 8)), WHITE, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local fog = Instance.new("ParticleEmitter")
	fog.Name = "Mist"
	fog.Color = ColorSequence.new(WHITE)
	fog.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) })
	fog.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	fog.Lifetime = NumberRange.new(3, 5)
	fog.Speed = NumberRange.new(2, 5)
	fog.SpreadAngle = Vector2.new(70, 20)
	fog.Rate = 10
	fog.Parent = mist
	-- THE RAINBOW in the spray, arching over the pool
	for band, color in ipairs(RAINBOW) do
		local r = 44 - band * 1.6
		local last = nil
		for i = 0, 18 do
			local ang = math.rad(12 + i * (156 / 18))
			local p = at(math.cos(ang) * r, math.sin(ang) * r * 0.9 + 6, POOL_Z + 8)
			if last then
				beam("Rainbow", last, p, 1.6, color, merge(DECOR, { Transparency = 0.45, Material = Mat.Neon }))
			end
			last = p
		end
	end
	-- THE RIVER: out of the pool to the east, round the village and away south
	local points = {}
	for k = 0, 14 do
		local u = k / 14
		local ang = math.pi - u * (math.pi - 0.7) -- from the north, round the east, to the south-east
		local r = RIVER_R + math.sin(u * math.pi * 3) * 8
		table.insert(points, onRing(r, ang, -0.1))
	end
	points[1] = at(30, -0.1, POOL_Z + 4)
	for i = 1, #points - 1 do
		local a0, b0 = points[i], points[i + 1]
		local len = (b0 - a0).Magnitude
		part("River", V3(16, 1, len + 3), CFrame.lookAt((a0 + b0) / 2 - V3(0, 0.4, 0), b0 - V3(0, 0.4, 0)), WATER, SCENERY)
		part("RiverBank", V3(19, 0.6, len + 3), CFrame.lookAt((a0 + b0) / 2 - V3(0, 0.3, 0), b0 - V3(0, 0.3, 0)), DIRT_DARK, DECOR)
		if i % 2 == 0 then
			part("RiverGlint", V3(1, 0.2, 4), CFrame.lookAt((a0 + b0) / 2 + V3(between(-4, 4), 0.12, 0), b0 + V3(0, 0.12, 0)), WATER_LIGHT,
				merge(DECOR, { Material = Mat.Neon, Transparency = 0.3 }))
		end
	end
	-- THE DOCK, with two canoes tied up, on the river's inner bank to the east
	local dockAt = points[10]
	local inward = V3(CENTER.X - dockAt.X, 0, CENTER.Z - dockAt.Z).Unit
	local dcf = CFrame.lookAt(dockAt + inward * 10, dockAt)
	for k = 0, 5 do
		part("DockPlank", V3(8, 0.5, 1.6), dcf * CFrame.new(0, 0.9, -k * 1.7), (k % 2 == 0) and WOOD or WOOD_LIGHT, SCENERY)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ 0, -8.5 }) do
			part("DockPost", V3(0.8, 3.6, 0.8), dcf * CFrame.new(sx * 3.6, 0, z), WOOD_DARK, SCENERY)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local ccf = dcf * CFrame.new(sx * 7.5, -0.1, -8) * CFrame.Angles(0, math.pi / 2, 0)
		part("Canoe", V3(2.6, 1.2, 11), ccf, (sx == 1) and RED_DARK or WOOD_DARK, SCENERY)
		part("CanoeInside", V3(1.8, 0.2, 9.4), ccf * CFrame.new(0, 0.55, 0), WOOD_LIGHT, DECOR)
		part("CanoeTip", V3(1.6, 1.0, 1.6), ccf * CFrame.new(0, 0.4, 5.8) * CFrame.Angles(0, math.pi / 4, 0), (sx == 1) and RED_DARK or WOOD_DARK, DECOR)
		part("CanoeTip", V3(1.6, 1.0, 1.6), ccf * CFrame.new(0, 0.4, -5.8) * CFrame.Angles(0, math.pi / 4, 0), (sx == 1) and RED_DARK or WOOD_DARK, DECOR)
		beam("Paddle", (ccf * CFrame.new(0.4, 0.8, -2)).Position, (ccf * CFrame.new(-0.2, 0.9, 3)).Position, 0.3, WOOD_LIGHT, DECOR)
	end
end

----------------------------------------------------------------------
-- The jungle all round: palms, big trees, bushes, giant leaves, vines
----------------------------------------------------------------------
local function palm(p, lean)
	local h = between(14, 20)
	local dir = V3(math.cos(lean), 0, math.sin(lean))
	local last = p
	local segs = 6
	for i = 1, segs do
		local u = i / segs
		local q = p + V3(0, h * u, 0) + dir * (u * u) * 3.5
		beam("PalmTrunk", last, q, 1.2 - u * 0.3, (i % 2 == 0) and WOOD or WOOD_DARK, SCENERY)
		last = q
	end
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + rnd()
		local out = V3(math.cos(a), 0, math.sin(a))
		local tip = last + out * 7 + V3(0, -2.2, 0)
		beam("PalmFrond", last + out * 0.5, last + out * 3.8 + V3(0, 0.8, 0), 1.2, (k % 2 == 0) and GRASS or GRASS_DARK, DECOR)
		beam("PalmFrond", last + out * 3.8 + V3(0, 0.8, 0), tip, 1.0, (k % 2 == 0) and GRASS_DARK or GRASS, DECOR)
	end
	for k = 0, 2 do
		ball("Coconut", 1.1, CFrame.new(last + V3(math.cos(k * 2.1) * 0.8, -0.8, math.sin(k * 2.1) * 0.8)), WOOD_DARK, DECOR)
	end
end

local function jungleTree(p, big)
	local h = big and between(34, 50) or between(20, 30)
	local w = big and between(4, 6) or between(2.4, 3.4)
	part("TreeTrunk", V3(w, h, w), CFrame.new(p + V3(0, h / 2 - 0.5, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick({ BARK, WOOD_DARK }), SCENERY)
	local crowns = big and 4 or 3
	for i = 1, crowns do
		local s = (big and 18 or 12) * between(0.7, 1.1)
		local o = V3(between(-4, 4), h - between(0, 6) + i * 1.5, between(-4, 4))
		part("TreeLeaves", V3(s, s * 0.55, s), CFrame.new(p + o) * CFrame.Angles(0, rnd() * 3, 0), pick({ GRASS, GRASS_DARK, GRASS_DEEP }), SCENERY)
	end
end

local function bush(p)
	local s = between(3, 6)
	part("Bush", V3(s * 1.4, s, s * 1.2), CFrame.new(p + V3(0, s * 0.4, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick({ GRASS, GRASS_DARK }), SCENERY)
	part("Bush", V3(s, s * 0.8, s), CFrame.new(p + V3(s * 0.5, s * 0.7, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick({ GRASS_DARK, GRASS_DEEP }), SCENERY)
	if rnd() < 0.35 then
		part("Flower", V3(0.8, 0.5, 0.8), CFrame.new(p + V3(0, s * 1.05, 0)), pick({ PINK, RED, YELLOW }), DECOR)
	end
end

local function giantLeaf(p, a)
	local cf = CFrame.new(p) * CFrame.Angles(0, a, 0)
	beam("LeafStem", p, (cf * CFrame.new(0, 4, -2)).Position, 0.4, GRASS_DARK, DECOR)
	part("GiantLeaf", V3(4, 0.3, 7), cf * CFrame.new(0, 4.6, -5.5) * CFrame.Angles(0.35, 0, 0), GRASS, DECOR)
	part("LeafVein", V3(0.3, 0.32, 6.6), cf * CFrame.new(0, 4.65, -5.5) * CFrame.Angles(0.35, 0, 0), GRASS_DARK, DECOR)
end

-- (is this spot in the river? It winds round the east side, from the pool)
local function inRiver(a, r)
	local w = wrap(a)
	return w > 0.55 and w < math.pi - 0.05 and math.abs(r - RIVER_R) < 17
end

local function buildJungle()
	-- palms between the huts, round the clearing
	for k = 0, 13 do
		local a = (k + 0.5) / 14 * math.pi * 2
		local w = wrap(a)
		if math.abs(w) > 0.35 and math.abs(wrap(a - math.pi)) > 0.22 then
			palm(onRing(between(84, 90), a + between(-0.06, 0.06), -0.2), rnd() * math.pi * 2)
		end
	end
	-- the two giant trees with treehouses, either side of the gate
	giantTree(onRing(124, 0.42, -0.2), true)
	giantTree(onRing(124, -0.42, -0.2), true)
	-- rings of jungle trees behind the village (not in front of the waterfall)
	for k = 0, 55 do
		local a = (k + rnd() * 0.6) / 56 * math.pi * 2
		local nearFalls = math.abs(wrap(a - math.pi)) < 0.5
		local r = between(136, 170)
		if not nearFalls and math.abs(wrap(a)) > 0.12 and not inRiver(a, r) then
			jungleTree(onRing(r, a, -0.2), rnd() < 0.5)
		end
	end
	for k = 0, 47 do
		local a = (k + rnd() * 0.5) / 48 * math.pi * 2
		if math.abs(wrap(a - math.pi)) > 0.75 then
			jungleTree(onRing(between(185, 235), a, -0.2), true)
		end
	end
	-- bushes and giant leaves under them
	for _ = 1, 60 do
		local a, r = rnd() * math.pi * 2, between(112, 175)
		if math.abs(wrap(a)) > 0.12 and math.abs(wrap(a - math.pi)) > 0.3 and not inRiver(a, r) then
			bush(onRing(r, a, -0.2))
		end
	end
	for _ = 1, 24 do
		local a = rnd() * math.pi * 2
		if math.abs(wrap(a)) > 0.15 and math.abs(wrap(a - math.pi)) > 0.3 then
			giantLeaf(onRing(between(80, 96), a, -0.2), rnd() * math.pi * 2)
		end
	end
	-- vines hanging from the giant trees and the cliff
	for _, base in ipairs({ onRing(124, 0.42, 0), onRing(124, -0.42, 0) }) do
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			local top = base + V3(math.cos(a) * 9, 40, math.sin(a) * 9)
			beam("Vine", top, top - V3(0, between(14, 24), 0), 0.35, GRASS_DARK, DECOR)
		end
	end
	for k = -8, 8 do
		if math.abs(k) >= 2 then
			local top = at(k * 7 + between(-2, 2), 70 + between(-8, 8), CLIFF_Z + 1)
			beam("Vine", top, top - V3(0, between(18, 34), 0), 0.4, pick({ GRASS, GRASS_DARK }), DECOR)
		end
	end
end

----------------------------------------------------------------------
-- The village gate (south): the way in and out
----------------------------------------------------------------------
local function buildGate()
	local gcf = CFrame.lookAt(at(0, 0, GATE_Z), at(0, 0, 0)) -- (-Z faces the clearing)
	local function blk(name, size, x, y, z, color, extra)
		return part(name, size, gcf * CFrame.new(x, y, z), color or WOOD_DARK, extra)
	end
	-- two carved posts (monkey faces), a crossbar with a thatched top
	for _, sx in ipairs({ -1, 1 }) do
		blk("GatePost", V3(3, 18, 3), sx * 10, 9, 0)
		for i = 0, 2 do
			local y = 4 + i * 5
			blk("GatePostFace", V3(2.4, 2, 0.4), sx * 10, y, -1.6, (i % 2 == 0) and WOOD_LIGHT or SKIN, DECOR)
			blk("GatePostEyes", V3(1.6, 0.4, 0.2), sx * 10, y + 0.4, -1.85, INK, DECOR)
		end
		blk("GatePostTop", V3(3.6, 1, 3.6), sx * 10, 18.5, 0, BARK)
	end
	blk("GateBar", V3(26, 2, 2), 0, 16, 0)
	blk("GateBarLow", V3(21, 1, 1.4), 0, 12.5, 0, WOOD)
	for i = 0, 2 do
		blk("GateThatch", V3(28 - i * 5, 1.2, 4 - i * 0.6), 0, 17.8 + i * 1.1, 0, (i % 2 == 0) and THATCH or THATCH_DARK)
	end
	local sign = blk("GateSign", V3(14, 3, 0.6), 0, 14.2, -1.1, WOOD_LIGHT)
	signText(sign, "KONGO'S JUNGLE", RED_DARK, Enum.NormalId.Front)
	-- a pair of bananas crossed over the sign
	for _, sx in ipairs({ -1, 1 }) do
		blk("GateBanana", V3(0.8, 3, 0.6), sx * 8.2, 14.4, -1.3, YELLOW, merge(DECOR, {}))
	end
	-- behind the gate: an invisible wall, so nobody wanders off into the jungle
	blk("GateBack", V3(30, 26, 2), 0, 13, 4.5, WHITE, { Transparency = 1, CastShadow = false })
	-- the curtain of vines in the gateway: the way out
	local fog = blk("VineCurtain", V3(17, 12, 0.6), 0, 6.2, 0, GRASS, { Transparency = 0.45, CanCollide = false, CastShadow = false, Material = Mat.Neon })
	pulse(fog, 0.4, 0.35, 0.6)
	for k = -4, 4 do
		blk("CurtainVine", V3(0.4, between(8, 11.5), 0.3), k * 1.9, 7, -0.4, GRASS_DARK, DECOR)
	end
	local leaves = Instance.new("ParticleEmitter")
	leaves.Rate = 4
	leaves.Color = ColorSequence.new(GRASS, GRASS_DARK)
	leaves.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.3) })
	leaves.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	leaves.Lifetime = NumberRange.new(2, 3)
	leaves.Speed = NumberRange.new(0.5, 1.5)
	leaves.Parent = fog
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Village Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(gcf * CFrame.new(0, 4, -3), V3(16, 8, 6), "Spire", "Leave")
	-- a sign by the way in: KONGO'S JUNGLE VILLAGE
	local sp = at(PATH_HALF + 5, -0.2, GATE_Z - 8)
	local signCF = CFrame.lookAt(sp, sp + V3(-0.4, 0, -1))
	part("SignPost", V3(0.7, 6.4, 0.7), signCF * CFrame.new(0, 3.2, 0), WOOD_DARK)
	local board = part("SignBoard", V3(7, 2.6, 0.4), signCF * CFrame.new(0, 6.6, 0), WOOD_LIGHT)
	signText(board, "KONGO'S JUNGLE\nVILLAGE", BARK, Enum.NormalId.Front)
	-- where you arrive: inside the gate, looking at the clearing
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, SPAWN_Z), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- The walls round the fight, and the marks the boss will use
----------------------------------------------------------------------
local function wall(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "JungleEdgeWall")
	return w
end

local function buildBounds()
	local H = 60
	-- round the clearing, in straight pieces (leaving the way in open)
	local N = 48
	local len = 2 * (FIGHT_R + 1) * math.tan(math.pi / N) + 0.6
	for k = 0, N - 1 do
		local a = (k + 0.5) / N * math.pi * 2
		if math.abs(wrap(a)) > GAP_ANGLE then
			local p = onRing(FIGHT_R + 1, a, H / 2)
			wall(facingCentre(p), V3(len, H, 2))
		end
	end
	-- the way in's sides, out to the gate
	local z0 = FIGHT_R * math.cos(GAP_ANGLE) - 2
	local z1 = GATE_Z + 3
	for _, sx in ipairs({ -1, 1 }) do
		wall(CFrame.new(at(sx * (PATH_HALF + 1), H / 2, (z0 + z1) / 2)), V3(2, H, z1 - z0))
	end
	-- Where Kongo naps: the middle of the clearing, facing the gate you come in
	-- by. BossService builds Kongo himself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 7)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function JungleBuilder.Build()
	local old = Workspace:FindFirstChild("JungleArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "JungleArena"
	seed = 20261004 -- (the same "random" every time it's built)
	monkeys = 0

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Ground", buildGround },
		{ "Torches", buildTorches },
		{ "Village", buildVillage },
		{ "Village bits", buildVillageBits },
		{ "Waterfall", buildWaterfall },
		{ "Jungle", buildJungle },
		{ "Gate", buildGate },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[JungleBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 7)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("FightRadius", FIGHT_R) -- how far out the invisible wall stands
	m.Parent = Workspace
	if failed == 0 then
		print("[JungleBuilder] Kongo's Jungle Village built OK")
	end
	return m
end

-- (for Bosses/Kongo.lua and the tests: where things are)
JungleBuilder.Center = CENTER
JungleBuilder.FightRadius = FIGHT_R

return JungleBuilder
