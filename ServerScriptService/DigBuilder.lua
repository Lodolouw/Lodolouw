--[[
	DigBuilder  (ModuleScript, parent: ServerScriptService, name: "DigBuilder")

	Builds the Spire's third floor: THE GLIMMER DIG, Knight Burrowmore's arena.

	An old dig site out on the sunny plains. You come in through a stone gate
	(with a glowing checkpoint orb beside it, like the ones in a certain shovel
	game) and walk down a short dirt path onto a wide round floor of packed dirt,
	fenced with wooden posts. Out past the fence: heaps of gold coins, open
	treasure chests, rocks studded with gems, dirt mounds with spare shovels
	stuck in them, the knight's striped tent and his campfire with a log to sit
	on. Beyond that the plains roll away in stepped green hills and blocky
	trees, with a purple castle on a far hill, little floating islands of dirt
	and gems in the sky, and blue mountains all round the edge of the world.
	Everything is chunky and 8-bit, in the game's 32 colours.

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"  where you arrive (in this model, Floor = 3)
	  * "ArenaExit"   the Leave prompt on the gate's fog (switched off on your
	                  screen), plus a walk-up box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"    the middle of the dig, Floor = 3, facing the gate
	  * "DigEdgeWall" the invisible walls round the dirt you fight on
	  * the model itself carries Floor = 3 and Center (the middle of the dig)

	Main calls DigBuilder.Build() once at startup, after the Sunken Dunes and
	before BossService (which puts the knight on his BossHome).
	The floor you fight on is one solid, flat disc of dirt: everything drawn on
	it (the darker tiles, the rings, the holes, the pebbles) can't be tripped on.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local DigBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (angle 0 is south, +Z: the gate; the knight kneels in the middle
-- facing it)
----------------------------------------------------------------------
local CENTER = V3(-2600, 0, 2600) -- well away from the lobby, the Colosseum and the other floors
local FIGHT_R = 84 -- the dirt you fight on (the invisible wall stands here)
local DIRT_R = 90 -- the dirt floor itself
local FENCE_R = 85 -- the wooden fence round it (just outside the invisible wall)
local GATE_R = 106 -- the stone gate, south
local SPAWN_R = 97 -- where you arrive, on the path in from the gate
local GRASS_R = 500 -- the plains (out under the far mountains)
local PATH_HALF = 7 -- half the width of the dirt path from the gate

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local DIRT = RGB(194, 133, 105)
local DIRT_DARK = RGB(184, 111, 80)
local DIRT_DEEP = RGB(115, 62, 57)
local DIRT_LIGHT = RGB(228, 166, 114)
local HOLE = RGB(62, 39, 49)
local GRASS = RGB(99, 199, 77)
local GRASS_DARK = RGB(62, 137, 72)
local GRASS_DEEP = RGB(38, 92, 66)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local WOOD = RGB(115, 62, 57)
local WOOD_LIGHT = RGB(184, 111, 80)
local GOLD = RGB(254, 174, 52)
local GOLD_LIGHT = RGB(254, 231, 97)
local BLUE = RGB(0, 153, 219)
local BLUE_DARK = RGB(18, 78, 137)
local RED = RGB(228, 59, 68)
local WHITE = RGB(255, 255, 255)
local FOG = RGB(235, 240, 255)
local CYAN = RGB(44, 232, 245)
local PURPLE = RGB(104, 56, 108)
local PURPLE_LIGHT = RGB(181, 80, 136)
local MOUNTAIN = RGB(90, 105, 136)
local MOUNTAIN_LIGHT = RGB(139, 155, 180)
local SNOW = RGB(192, 203, 220)
local FLAME = { RGB(247, 118, 34), RGB(254, 174, 52), RGB(254, 231, 97) }
local GEMS = { RGB(44, 232, 245), RGB(255, 0, 68), RGB(99, 199, 77), RGB(181, 80, 136), RGB(254, 231, 97) }
local PETALS = { RGB(255, 255, 255), RGB(254, 231, 97), RGB(246, 117, 122), RGB(44, 232, 245), RGB(228, 59, 68) }

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the dunes')
----------------------------------------------------------------------
local seed = 20260926
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
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

-- A WedgePart. Roblox wedges are full height at their back (+Z) and slope down
-- to nothing at their front (-Z).
local function wedge(name, size, cf, color, extra, parent)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = Mat.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			w[k] = v
		end
	end
	w.Parent = parent or m
	return w
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

-- a slow glow in and out (LobbyFX animates anything tagged "Pulse")
local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
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
-- angle 0 is south (+Z, the gate); pi is north
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y, math.cos(a) * r)
end
local function facingCentre(p)
	return CFrame.lookAt(p, V3(CENTER.X, p.Y, CENTER.Z))
end
local function wrap(a) -- to -pi..pi
	return (a + math.pi) % (2 * math.pi) - math.pi
end
-- how far a spot is from the path in from the gate (so nothing is put on it)
local function nearPath(p)
	local rel = p - CENTER
	return math.abs(rel.X) < PATH_HALF + 6 and rel.Z > 40
end

-- a light that glows warm (the campfire, the braziers)
local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

-- a pixel picture made of rows: each letter is one block ("." = nothing).
-- Runs of the same letter on a row are joined into one block, so a picture is
-- only a handful of parts. `cf` is its centre, facing the way it looks out.
local function pixelArt(name, rows, ink, pixel, cf, depth)
	local h, w = #rows, #rows[1]
	for y = 1, h do
		local row = rows[y]
		local x = 1
		while x <= w do
			local ch = string.sub(row, x, x)
			local color = ink[ch]
			if color then
				local x2 = x
				while x2 < w and string.sub(row, x2 + 1, x2 + 1) == ch do
					x2 = x2 + 1
				end
				local cx = ((x + x2) / 2 - (w + 1) / 2) * pixel
				local cy = ((h + 1) / 2 - y) * pixel
				part(name, V3((x2 - x + 1) * pixel, pixel, depth or 0.2), cf * CFrame.new(cx, cy, 0), color, DECOR)
				x = x2 + 1
			else
				x = x + 1
			end
		end
	end
end

-- the knight's sign: a golden spade
local SPADE = {
	"..G..",
	".GGG.",
	"GGGGG",
	"GGGGG",
	".GGG.",
	"..W..",
	"..W..",
	".WWW.",
}
local SPADE_INK = { G = GOLD, W = GOLD_LIGHT }

----------------------------------------------------------------------
-- The ground: the dirt you fight on and the plains round it
----------------------------------------------------------------------
local function buildGround()
	-- the plains: a huge grass disc, a little lower than the dirt
	cylinder("Plains", 4, GRASS_R * 2, CFrame.new(at(0, -2.3, 0)), GRASS)
	-- the dig: one solid, flat disc of packed dirt, its top at y = 0
	cylinder("DigFloor", 4, DIRT_R * 2, CFrame.new(at(0, -2, 0)), DIRT)
	-- the path in from the gate: dirt, level with the floor
	local len = GATE_R - DIRT_R + 6
	part("GatePath", V3(PATH_HALF * 2, 4, len), CFrame.new(at(0, -2, DIRT_R - 3 + len / 2)), DIRT)

	-- its edge isn't a clean circle: lumps of darker dirt and tufts of grass
	-- break it up all the way round
	for i = 0, 71 do
		local a = (i + rnd() * 0.6) / 72 * math.pi * 2
		local p = onRing(DIRT_R - 0.6 + rnd() * 1.6, a, 0)
		if not nearPath(p) then
			local w = 2 + rnd() * 3
			part("DirtLump", V3(w, 0.5 + rnd() * 0.5, 1.4 + rnd() * 1.6), facingCentre(p) * CFrame.new(0, 0.1, 0), (i % 3 == 0) and DIRT_DEEP or DIRT_DARK, DECOR)
			if rnd() < 0.5 then
				local g = onRing(DIRT_R + 1 + rnd() * 2, a + (rnd() - 0.5) * 0.04, -0.3)
				for _ = 1, 2 + math.floor(rnd() * 2) do
					local hh = 0.5 + rnd() * 0.8
					part("GrassTuft", V3(0.35, hh, 0.35), CFrame.new(g + V3((rnd() - 0.5) * 1.6, hh / 2, (rnd() - 0.5) * 1.6)), (rnd() < 0.5) and GRASS_DARK or GRASS, DECOR)
				end
			end
		end
	end

	-- 8-bit dirt: darker and lighter tiles scattered over the floor, on a grid
	-- so no two ever overlap (two see-through-flat faces in one place flicker)
	local CELL = 4
	local n = math.floor(FIGHT_R / CELL)
	for gx = -n, n do
		for gz = -n, n do
			local cx, cz = gx * CELL, gz * CELL
			local r = math.sqrt(cx * cx + cz * cz)
			if r < FIGHT_R - 2 and r > 11 and rnd() < 0.2 then
				-- (square, like 8-bit dirt blocks: mostly a shade darker, now and then a light speck)
				local light = rnd() < 0.2
				local w = light and (0.8 + rnd() * 0.8) or (1.8 + rnd() * 1.4)
				local color = light and DIRT_LIGHT or DIRT_DARK
				local thick = ((gx + gz) % 2 == 0) and 0.1 or 0.14
				part("DirtTile", V3(w, thick, w), CFrame.new(at(cx + (rnd() - 0.5) * 0.6, thick / 2, cz + (rnd() - 0.5) * 0.6)), color, DECOR)
			end
		end
	end

	-- two old rings worn into the floor (their pieces overlap a little at
	-- the joints: every other one sits a hair lower, so their tops never share
	-- a height and flicker)
	local function ringBand(r, width, segs, color)
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * math.pi * 2
			local p = onRing(r, a, 0)
			local odd = (i % 2 == 1) and 0.04 or 0
			local len = 2 * r * math.sin(math.pi / segs) + 0.3
			local thick = 0.2 - odd
			-- (facing out from the middle, so each piece's length runs along the ring)
			local q = p + V3(0, thick / 2, 0)
			part("DigRing", V3(len, thick, width), CFrame.lookAt(q, q + V3(math.sin(a), 0, math.cos(a))), color, DECOR)
		end
	end
	ringBand(52, 2, 44, DIRT_DARK)
	ringBand(24, 1.6, 24, DIRT_DARK)

	-- where the knight kneels: a darker patch, and gems half-buried round it
	cylinder("RestPatch", 0.16, 18, CFrame.new(at(0, 0.08, 0)), DIRT_DEEP, DECOR)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + 0.3
		local p = onRing(6 + rnd() * 2.5, a, 0.35)
		local gem = part("BuriedGem", V3(0.8, 0.8, 0.8), CFrame.new(p) * CFrame.Angles(math.rad(45), a, math.rad(35)), pick(GEMS), merge(DECOR, { Material = Mat.Neon }))
		pulse(gem, 0.6 + rnd() * 0.5, 0, 0.45)
	end

	-- dug holes: dark pits with little mounds of dirt thrown up round them
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2 + 0.5
		local p = onRing(30 + ((i * 17) % 40), a, 0)
		if not nearPath(p) then
			local s = 2.6 + rnd() * 1.4
			part("DugHole", V3(s, 0.18, s), CFrame.new(p + V3(0, 0.09, 0)) * CFrame.Angles(0, rnd() * 3, 0), HOLE, DECOR)
			for k = 0, 3 do
				local b = k / 4 * math.pi * 2 + rnd()
				local q = p + V3(math.cos(b), 0, math.sin(b)) * (s * 0.7 + 0.5)
				local hh = 0.4 + rnd() * 0.5
				part("HoleMound", V3(1.2 + rnd() * 0.8, hh, 1 + rnd() * 0.6), CFrame.new(q + V3(0, hh / 2, 0)) * CFrame.Angles(0, b, 0), DIRT_LIGHT, DECOR)
			end
		end
	end

	-- pebbles
	for _ = 1, 60 do
		local a, r = rnd() * math.pi * 2, 12 + math.sqrt(rnd()) * (FIGHT_R - 14)
		local p = onRing(r, a, 0)
		if not nearPath(p) then
			local s = 0.4 + rnd() * 0.6
			part("Pebble", V3(s, s * 0.7, s), CFrame.new(p + V3(0, s * 0.35, 0)) * CFrame.Angles(0, rnd() * 3, 0), (rnd() < 0.5) and STONE or STONE_DARK, DECOR)
		end
	end
end

----------------------------------------------------------------------
-- The fence round the dig
----------------------------------------------------------------------
local function buildFence()
	local N = 60
	local posts = {}
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local p = onRing(FENCE_R, a, 0)
		if math.abs(wrap(a)) > 0.13 then -- (a gap for the path in)
			part("FencePost", V3(0.9, 3.4, 0.9), CFrame.new(p + V3(0, 1.7, 0)) * CFrame.Angles(0, -a, 0), WOOD, DECOR)
			part("FencePostCap", V3(1.1, 0.3, 1.1), CFrame.new(p + V3(0, 3.55, 0)) * CFrame.Angles(0, -a, 0), WOOD_LIGHT, DECOR)
			posts[i] = p
		end
	end
	for i = 0, N - 1 do
		local a, b = posts[i], posts[(i + 1) % N]
		if a and b then
			for _, y in ipairs({ 1.3, 2.6 }) do
				local p, q = a + V3(0, y, 0), b + V3(0, y, 0)
				part("FenceRail", V3(0.35, 0.45, (q - p).Magnitude + 0.2), CFrame.lookAt((p + q) / 2, q), WOOD_LIGHT, DECOR)
			end
		end
	end
end

----------------------------------------------------------------------
-- The gate, the way in and out
----------------------------------------------------------------------
local function brazier(pos)
	part("BrazierFoot", V3(2.2, 2.4, 2.2), CFrame.new(pos + V3(0, 1.2, 0)), STONE_DARK)
	part("BrazierBowl", V3(3, 0.9, 3), CFrame.new(pos + V3(0, 2.85, 0)), STONE)
	part("BrazierCoals", V3(2.4, 0.3, 2.4), CFrame.new(pos + V3(0, 3.4, 0)), RGB(62, 39, 49), DECOR)
	local flames = {}
	for k, c in ipairs(FLAME) do
		local s = 1.9 - k * 0.45
		local f = part("BrazierFlame", V3(s, s * 1.2, s), CFrame.new(pos + V3(0, 3.4 + k * 0.7, 0)) * CFrame.Angles(0, k * 0.5, 0), c, merge(DECOR, { Material = Mat.Neon }))
		pulse(f, 2.2 + k * 0.4, 0, 0.35)
		flames[k] = f
	end
	light(flames[1], RGB(255, 170, 90), 16, 1.3)
end

local function buildGate()
	local gp = onRing(GATE_R, 0, 0)
	local gcf = CFrame.lookAt(gp, at(0, 0, 0)) -- -Z faces the dig
	local function blk(name, size, x, y, z, color, extra)
		return part(name, size, gcf * CFrame.new(x, y, z), color or STONE, extra)
	end
	-- two stout stone pillars with gold caps
	for _, sx in ipairs({ -1, 1 }) do
		blk("GateBase", V3(7, 3, 7), sx * 10.5, 1.5, 0, STONE_DARK)
		blk("GatePillar", V3(5, 18, 5), sx * 10.5, 12, 0)
		for _, y in ipairs({ 6, 12, 18 }) do
			blk("GateBand", V3(5.4, 0.6, 5.4), sx * 10.5, y, 0, STONE_DARK, DECOR)
		end
		blk("GateCap", V3(6.4, 1.6, 6.4), sx * 10.5, 21.8, 0, GOLD)
		blk("GateKnob", V3(2.4, 2.4, 2.4), sx * 10.5, 23.8, 0, GOLD_LIGHT)
		-- a blue banner on each pillar with the knight's golden spade
		local banner = blk("Banner", V3(3.6, 9, 0.25), sx * 10.5, 13.5, -2.7, BLUE, DECOR)
		blk("BannerTrim", V3(3.8, 0.5, 0.3), sx * 10.5, 18.1, -2.72, GOLD, DECOR)
		-- (the banner's torn bottom: two tails)
		for _, tx in ipairs({ -0.95, 0.95 }) do
			blk("BannerTail", V3(1.3, 1.4, 0.25), sx * 10.5 + tx, 8.3, -2.7, BLUE_DARK, DECOR)
		end
		pixelArt("BannerSpade", SPADE, SPADE_INK, 0.55, banner.CFrame * CFrame.new(0, 0.4, -0.2), 0.12)
	end
	blk("GateLintel", V3(27, 3.6, 5.6), 0, 22.4, 0)
	blk("GateLintelTrim", V3(27.6, 0.8, 6), 0, 20.4, 0, STONE_DARK, DECOR)
	-- the golden spade over the doorway
	pixelArt("GateSpade", SPADE, SPADE_INK, 0.42, gcf * CFrame.new(0, 22.4, -2.95), 0.25)

	-- behind the fog: the dark passage back, and solid stone so nobody walks through
	blk("GatePassage", V3(16, 19, 1), 0, 9.5, 3.5, RGB(24, 20, 37))
	blk("GateBack", V3(30, 26, 8), 0, 13, 8, STONE_DARK)

	-- the fog in the doorway: the way out
	local fog = blk("FogWall", V3(16, 19, 0.6), 0, 9.5, 0, FOG, { Transparency = 0.45, CanCollide = false, CastShadow = false, Material = Mat.Neon })
	pulse(fog, 0.4, 0.35, 0.6)
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 8
	fe.Color = ColorSequence.new(RGB(240, 245, 255))
	fe.LightEmission = 0.4
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	fe.Lifetime = NumberRange.new(2, 3)
	fe.Speed = NumberRange.new(0.5, 1.5)
	fe.Parent = fog
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Dig Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(gcf * CFrame.new(0, 4, -3), V3(16, 8, 6), "Spire", "Leave")

	-- the checkpoint: a glass orb on a stone post, glowing, just inside the gate
	local cp = (gcf * CFrame.new(-11, 0, -8)).Position
	part("CheckpointPost", V3(2.2, 3.4, 2.2), CFrame.new(cp + V3(0, 1.7, 0)), STONE)
	part("CheckpointRim", V3(2.8, 0.5, 2.8), CFrame.new(cp + V3(0, 3.6, 0)), GOLD)
	local orb = part("CheckpointOrb", V3(2.2, 2.2, 2.2), CFrame.new(cp + V3(0, 5, 0)) * CFrame.Angles(0, math.rad(45), 0), CYAN,
		merge(DECOR, { Material = Mat.Neon, Transparency = 0.15 }))
	pulse(orb, 0.8, 0.05, 0.4)
	part("CheckpointSpark", V3(0.7, 0.7, 0.7), CFrame.new(cp + V3(0, 5, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), WHITE, merge(DECOR, { Material = Mat.Neon }))
	light(orb, CYAN, 12, 1)

	-- braziers either side of the path, just inside
	for _, sx in ipairs({ -1, 1 }) do
		brazier((gcf * CFrame.new(sx * 9.5, 0, -14)).Position)
	end

	-- a sign by the path: THE GLIMMER DIG
	local sp = (gcf * CFrame.new(11, 0, -9)).Position
	local signCF = CFrame.lookAt(sp, sp + (gcf.LookVector * V3(1, 0, 1)).Unit)
	part("SignPost", V3(0.7, 4.4, 0.7), signCF * CFrame.new(0, 2.2, 0), WOOD)
	local board = part("SignBoard", V3(6.4, 2.4, 0.4), signCF * CFrame.new(0, 4.6, 0), WOOD_LIGHT)
	part("SignTrim", V3(6.8, 0.3, 0.45), signCF * CFrame.new(0, 5.85, 0), WOOD, DECOR)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(320, 120)
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "THE GLIMMER\nDIG"
	text.TextColor3 = RGB(62, 39, 49)
	text.TextScaled = true
	text.Font = Enum.Font.Arcade
	pcall(function()
		text.FontFace = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	text.Parent = gui
	gui.Parent = board

	-- where you arrive: on the path, just inside the gate, looking at the dig
	local spawnP = onRing(SPAWN_R, 0, 3)
	local arrive = anchorPart("ArenaSpawn", facingCentre(spawnP))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- The knight's camp and his treasure, out past the fence
----------------------------------------------------------------------
-- a heap of gold coins: stepped layers, sparkling
local function coinPile(pos, size)
	for k = 0, 2 do
		local s = size * (1 - k * 0.3)
		part("CoinPile", V3(s, size * 0.28, s * 0.9), CFrame.new(pos + V3(0, size * 0.14 + k * size * 0.26, 0)) * CFrame.Angles(0, k * 0.4, 0), (k % 2 == 0) and GOLD or GOLD_LIGHT, DECOR)
	end
	for _ = 1, 4 do
		local c = part("Coin", V3(0.9, 0.2, 0.9), CFrame.new(pos + V3((rnd() - 0.5) * size * 1.6, 0.1, (rnd() - 0.5) * size * 1.6)) * CFrame.Angles(0, rnd() * 3, 0), GOLD, DECOR)
		c.Material = Mat.SmoothPlastic
	end
	local glint = part("CoinGlint", V3(0.5, 0.5, 0.5), CFrame.new(pos + V3(0, size * 0.85, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), WHITE, merge(DECOR, { Material = Mat.Neon }))
	pulse(glint, 1.3 + rnd(), 0, 1)
end

-- an open treasure chest, gold glowing inside
local function chest(pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part("ChestBox", V3(4, 2.4, 2.8), cf * CFrame.new(0, 1.2, 0), WOOD_LIGHT, DECOR)
	for _, x in ipairs({ -1.5, 1.5 }) do
		part("ChestBand", V3(0.4, 2.5, 2.9), cf * CFrame.new(x, 1.2, 0), GOLD, DECOR)
	end
	part("ChestLock", V3(0.7, 0.8, 0.3), cf * CFrame.new(0, 1.9, -1.5), GOLD_LIGHT, DECOR)
	local gold = part("ChestGold", V3(3.5, 0.5, 2.3), cf * CFrame.new(0, 2.45, 0), GOLD_LIGHT, merge(DECOR, { Material = Mat.Neon }))
	pulse(gold, 0.7, 0, 0.3)
	-- the lid, thrown open behind it
	part("ChestLid", V3(4, 0.6, 2.8), cf * CFrame.new(0, 3.3, 1.9) * CFrame.Angles(math.rad(-70), 0, 0), WOOD, DECOR)
	part("ChestGem", V3(0.6, 0.6, 0.6), cf * CFrame.new(0.8, 2.9, -0.2) * CFrame.Angles(math.rad(45), 0.4, math.rad(45)), pick(GEMS), merge(DECOR, { Material = Mat.Neon }))
end

-- a lump of rock with gems stuck in it
local function gemRock(pos)
	for k = 1, 3 do
		local s = 3.2 - k * 0.6
		part("GemRock", V3(s + rnd(), s, s + rnd()), CFrame.new(pos + V3((rnd() - 0.5) * 2, s / 2 + (k - 1) * 0.6, (rnd() - 0.5) * 2)) * CFrame.Angles(0, rnd() * 3, 0), (k % 2 == 1) and STONE_DARK or STONE, DECOR)
	end
	for _ = 1, 3 do
		local gem = part("RockGem", V3(0.8, 1.1, 0.8), CFrame.new(pos + V3((rnd() - 0.5) * 3, 1.2 + rnd() * 2, (rnd() - 0.5) * 3)) * CFrame.Angles(rnd(), rnd() * 3, rnd()), pick(GEMS), merge(DECOR, { Material = Mat.Neon }))
		pulse(gem, 0.5 + rnd() * 0.6, 0, 0.4)
	end
end

-- a mound of dug-up dirt, stepped, sometimes with a spare shovel stuck in it
local function dirtMound(pos, size, shovel)
	for k = 0, 2 do
		local s = size * (1 - k * 0.32)
		part("DirtMound", V3(s, size * 0.3, s * 0.85), CFrame.new(pos + V3(0, size * 0.15 + k * size * 0.28, 0)) * CFrame.Angles(0, k * 0.5 + rnd(), 0), (k == 1) and DIRT_DARK or DIRT, DECOR)
	end
	if shovel then
		local top = pos + V3(0, size * 0.8, 0)
		local tilt = CFrame.new(top) * CFrame.Angles(0, rnd() * 6, math.rad(12))
		part("SpareShovelHandle", V3(0.35, 5, 0.35), tilt * CFrame.new(0, 2.2, 0), WOOD, DECOR)
		part("SpareShovelGrip", V3(1.2, 0.35, 0.35), tilt * CFrame.new(0, 4.7, 0), WOOD_LIGHT, DECOR)
		part("SpareShovelBlade", V3(1.6, 1.6, 0.25), tilt * CFrame.new(0, -0.4, 0), GOLD, DECOR)
	end
end

local function campfire(pos)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part("CampStone", V3(1.1, 0.8, 1.1), CFrame.new(pos + V3(math.cos(a) * 2.3, 0.4, math.sin(a) * 2.3)) * CFrame.Angles(0, a, 0), (i % 2 == 0) and STONE or STONE_DARK, DECOR)
	end
	for k = 0, 2 do
		part("CampLog", V3(0.7, 0.7, 3.6), CFrame.new(pos + V3(0, 0.45, 0)) * CFrame.Angles(0, k * math.pi / 3, 0), WOOD, DECOR)
	end
	local flames = {}
	for k, c in ipairs(FLAME) do
		local s = 2 - k * 0.5
		local f = part("CampFlame", V3(s, s * 1.3, s), CFrame.new(pos + V3(0, 0.8 + k * 0.8, 0)) * CFrame.Angles(0, k * 0.6, 0), c, merge(DECOR, { Material = Mat.Neon }))
		pulse(f, 2 + k * 0.5, 0, 0.35)
		flames[k] = f
	end
	light(flames[1], RGB(255, 170, 90), 22, 1.5)
	-- a log to sit on, and a bedroll
	part("SittingLog", V3(5, 1.4, 1.4), CFrame.new(pos + V3(0, 0.7, 4.8)), WOOD_LIGHT, DECOR)
	part("SittingLogEnd", V3(0.2, 1.2, 1.2), CFrame.new(pos + V3(2.55, 0.7, 4.8)), DIRT_LIGHT, DECOR)
	part("Bedroll", V3(3, 0.5, 6), CFrame.new(pos + V3(-4.8, 0.25, 0.5)) * CFrame.Angles(0, 0.2, 0), BLUE, DECOR)
	part("BedrollStripe", V3(3.05, 0.55, 0.6), CFrame.new(pos + V3(-4.8, 0.25, 0.5)) * CFrame.Angles(0, 0.2, 0) * CFrame.new(0, 0, -1.6), GOLD, DECOR)
	part("Pillow", V3(2.2, 0.7, 1.4), CFrame.new(pos + V3(-4.8, 0.6, 0.5)) * CFrame.Angles(0, 0.2, 0) * CFrame.new(0, 0, 2.2), WHITE, DECOR)
end

-- the knight's tent: blue and gold stripes, a pennant on top
local function tent(pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local L, W, H = 12, 10, 7
	local strips = 6
	for i = 0, strips - 1 do
		local x = (i + 0.5) / strips * L - L / 2
		local c = (i % 2 == 0) and BLUE or GOLD
		-- (two wedges back to back make the roof's two slopes)
		wedge("TentSide", V3(L / strips, H, W / 2), cf * CFrame.new(x, H / 2, -W / 4), c, DECOR)
		wedge("TentSide", V3(L / strips, H, W / 2), cf * CFrame.new(x, H / 2, W / 4) * CFrame.Angles(0, math.pi, 0), c, DECOR)
	end
	-- the doorway: a dark triangle-ish gap at one end
	part("TentDoor", V3(0.2, 3.6, 2.6), cf * CFrame.new(-L / 2 - 0.05, 1.8, 0), RGB(24, 20, 37), DECOR)
	part("TentPole", V3(0.4, 4, 0.4), cf * CFrame.new(-L / 2 + 0.5, H + 1.6, 0), WOOD, DECOR)
	part("TentPennant", V3(0.15, 1.4, 2.4), cf * CFrame.new(-L / 2 + 0.5, H + 3, -1.2), RED, DECOR)
end

local function buildCamp()
	-- east: his campfire (angle pi/2 is +X)
	campfire(onRing(101, math.pi / 2 + 0.12, 0))
	-- west: his tent
	tent(onRing(106, -math.pi / 2 - 0.1, -0.3), 0.15)
	-- treasure, all the way round (never on the path)
	local spots = {
		{ "pile", 0.55, 97 }, { "chest", 0.85, 99 }, { "rock", 1.15, 103 }, { "mound", 1.95, 96 },
		{ "pile", 2.3, 100 }, { "rock", 2.6, 108 }, { "chest", 2.95, 97 }, { "mound", 3.3, 101 },
		{ "pile", -2.95, 104 }, { "mound", -2.6, 97 }, { "rock", -2.25, 100 }, { "chest", -1.95, 96 },
		{ "pile", -1.15, 99 }, { "mound", -0.85, 103 }, { "rock", -0.5, 96 }, { "mound", 1.45, 112 },
		{ "pile", 2.1, 116 }, { "rock", -1.5, 118 },
	}
	for i, s in ipairs(spots) do
		local p = onRing(s[3], s[2], -0.3)
		if s[1] == "pile" then
			coinPile(p, 3 + rnd() * 2)
		elseif s[1] == "chest" then
			chest(p, s[2] + math.pi + (rnd() - 0.5) * 0.6)
		elseif s[1] == "rock" then
			gemRock(p)
		else
			dirtMound(p, 4 + rnd() * 3, i % 2 == 0)
		end
	end
	-- a wheelbarrow full of dirt by the path
	local wp = onRing(95, -0.2, -0.3)
	local wcf = CFrame.new(wp) * CFrame.Angles(0, 0.6, 0)
	part("Barrow", V3(2.6, 1.4, 3.6), wcf * CFrame.new(0, 1.5, 0), STONE_DARK, DECOR)
	part("BarrowDirt", V3(2.2, 0.6, 3.2), wcf * CFrame.new(0, 2.3, 0), DIRT_DARK, DECOR)
	part("BarrowWheel", V3(0.5, 1.4, 1.4), wcf * CFrame.new(0, 0.7, -2), RGB(62, 39, 49), DECOR)
	for _, x in ipairs({ -1, 1 }) do
		part("BarrowHandle", V3(0.3, 0.3, 3), wcf * CFrame.new(x, 1.3, 2.6), WOOD, DECOR)
	end
end

----------------------------------------------------------------------
-- The plains beyond: hills, trees, flowers, a far castle, the sky
----------------------------------------------------------------------
local function hill(pos, w, h)
	local layers = 3 + math.floor(rnd() * 2)
	for k = 0, layers - 1 do
		local s = w * (1 - k / (layers + 0.6))
		local color = (k % 2 == 0) and GRASS or GRASS_DARK
		part("Hill", V3(s, h / layers, s * (0.7 + rnd() * 0.3)), CFrame.new(pos + V3((rnd() - 0.5) * 3, (k + 0.5) * h / layers, (rnd() - 0.5) * 3)) * CFrame.Angles(0, rnd() * 0.6, 0), color, SCENERY)
	end
end

local function tree(pos, s)
	part("TreeTrunk", V3(1.6 * s, 7 * s, 1.6 * s), CFrame.new(pos + V3(0, 3.5 * s, 0)), WOOD, SCENERY)
	local leaves = { GRASS, GRASS_DARK, GRASS_DEEP }
	part("TreeLeaves", V3(7 * s, 4 * s, 7 * s), CFrame.new(pos + V3(0, 8 * s, 0)) * CFrame.Angles(0, rnd(), 0), leaves[2], SCENERY)
	part("TreeLeaves", V3(5 * s, 3 * s, 5 * s), CFrame.new(pos + V3(0.6 * s, 11 * s, 0.3 * s)) * CFrame.Angles(0, rnd(), 0), leaves[1], SCENERY)
	part("TreeLeaves", V3(3 * s, 2 * s, 3 * s), CFrame.new(pos + V3(-0.3 * s, 13.2 * s, 0)) * CFrame.Angles(0, rnd(), 0), leaves[rnd() < 0.5 and 1 or 3], SCENERY)
end

local function buildPlains()
	-- rolling stepped hills, in two rings
	for i = 0, 23 do
		local a = (i + rnd() * 0.5) / 24 * math.pi * 2
		if math.abs(wrap(a)) > 0.25 then
			hill(onRing(170 + rnd() * 40, a, -0.3), 40 + rnd() * 30, 8 + rnd() * 10)
		end
	end
	for i = 0, 17 do
		local a = (i + rnd() * 0.6) / 18 * math.pi * 2
		hill(onRing(250 + rnd() * 50, a, -0.3), 60 + rnd() * 40, 16 + rnd() * 16)
	end
	-- trees and bushes
	for i = 0, 33 do
		local a = (i + rnd() * 0.7) / 34 * math.pi * 2
		local p = onRing(128 + rnd() * 90, a, -0.3)
		if math.abs(wrap(a)) > 0.18 or (p - CENTER).Magnitude > 150 then
			tree(p, 0.9 + rnd() * 0.6)
		end
	end
	for _ = 1, 30 do
		local a = rnd() * math.pi * 2
		local p = onRing(118 + rnd() * 70, a, -0.3)
		local s = 2 + rnd() * 2
		part("Bush", V3(s * 1.4, s, s * 1.2), CFrame.new(p + V3(0, s / 2, 0)) * CFrame.Angles(0, rnd() * 3, 0), (rnd() < 0.5) and GRASS_DARK or GRASS_DEEP, DECOR)
	end
	-- flowers dotted over the grass near the fence
	for _ = 1, 90 do
		local a = rnd() * math.pi * 2
		local p = onRing(DIRT_R + 3 + rnd() * 40, a, -0.3)
		if not nearPath(p) then
			part("FlowerStem", V3(0.2, 0.7, 0.2), CFrame.new(p + V3(0, 0.35, 0)), GRASS_DARK, DECOR)
			part("Flower", V3(0.55, 0.55, 0.55), CFrame.new(p + V3(0, 0.85, 0)), pick(PETALS), DECOR)
		end
	end
	-- rocks
	for _ = 1, 18 do
		local a = rnd() * math.pi * 2
		local p = onRing(115 + rnd() * 100, a, -0.3)
		local s = 2 + rnd() * 3
		part("Rock", V3(s * 1.3, s, s), CFrame.new(p + V3(0, s * 0.4, 0)) * CFrame.Angles(0, rnd() * 3, rnd() * 0.3), (rnd() < 0.5) and STONE or STONE_DARK, SCENERY)
	end

	-- a castle on a far hill to the north (purple walls, golden roofs)
	local cp = onRing(300, math.pi, -0.3)
	hill(cp, 130, 26)
	local base = cp + V3(0, 26, 0)
	local ccf = facingCentre(base)
	part("CastleWall", V3(46, 14, 18), ccf * CFrame.new(0, 7, 0), PURPLE, SCENERY)
	for x = -20, 20, 5 do
		part("CastleMerlon", V3(2.5, 2.5, 18.4), ccf * CFrame.new(x, 15.2, 0), PURPLE, SCENERY)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part("CastleTower", V3(10, 28, 10), ccf * CFrame.new(sx * 24, 14, 0), PURPLE_LIGHT, SCENERY)
		for k = 0, 2 do
			local s = 12 - k * 3.6
			part("CastleRoof", V3(s, 3, s), ccf * CFrame.new(sx * 24, 29.5 + k * 3, 0), (k % 2 == 0) and GOLD or GOLD_LIGHT, SCENERY)
		end
		part("CastleFlag", V3(0.3, 3, 2.4), ccf * CFrame.new(sx * 24, 40, -1.2), RED, SCENERY)
	end
	part("CastleKeep", V3(16, 22, 14), ccf * CFrame.new(0, 18, 2), PURPLE_LIGHT, SCENERY)
	for k = 0, 3 do
		local s = 18 - k * 4.4
		part("CastleKeepRoof", V3(s, 3, s * 0.85), ccf * CFrame.new(0, 30.5 + k * 3, 2), (k % 2 == 0) and GOLD or GOLD_LIGHT, SCENERY)
	end
	part("CastleGate", V3(7, 9, 0.4), ccf * CFrame.new(0, 4.5, -9.2), RGB(24, 20, 37), SCENERY)

	-- little floating islands of dirt and gems in the sky
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + 0.7
		local p = onRing(150 + rnd() * 60, a, 45 + rnd() * 25)
		local s = 8 + rnd() * 6
		part("IslandTop", V3(s, 1.4, s * 0.8), CFrame.new(p), GRASS, SCENERY)
		part("IslandDirt", V3(s * 0.85, 2.2, s * 0.68), CFrame.new(p - V3(0, 1.8, 0)), DIRT, SCENERY)
		part("IslandDirt", V3(s * 0.55, 2, s * 0.45), CFrame.new(p - V3(0, 3.9, 0)), DIRT_DARK, SCENERY)
		part("IslandTip", V3(s * 0.25, 2, s * 0.22), CFrame.new(p - V3(0, 5.9, 0)), DIRT_DEEP, SCENERY)
		local gem = part("IslandGem", V3(1.2, 1.6, 1.2), CFrame.new(p + V3(0, 1.6, 0)) * CFrame.Angles(0.3, rnd() * 3, 0.3), pick(GEMS), merge(DECOR, { Material = Mat.Neon }))
		pulse(gem, 0.5, 0, 0.4)
	end

	-- blocky clouds
	for _ = 1, 12 do
		local a = rnd() * math.pi * 2
		local p = onRing(160 + rnd() * 240, a, 95 + rnd() * 50)
		local s = 12 + rnd() * 12
		local yaw = CFrame.Angles(0, rnd() * 3, 0)
		part("Cloud", V3(s * 2, s * 0.4, s), CFrame.new(p) * yaw, WHITE, DECOR)
		part("Cloud", V3(s, s * 0.35, s * 0.7), CFrame.new(p + V3(0, s * 0.35, 0)) * yaw * CFrame.new(s * 0.2, 0, 0), WHITE, DECOR)
		part("CloudShade", V3(s * 1.8, s * 0.12, s * 0.9), CFrame.new(p - V3(0, s * 0.24, 0)) * yaw, SNOW, DECOR)
	end

	-- blue mountains all round the edge of the world
	for i = 0, 15 do
		local a = (i + rnd() * 0.5) / 16 * math.pi * 2
		local p = onRing(440 + rnd() * 40, a, -2)
		local w = 90 + rnd() * 60
		local h = 60 + rnd() * 50
		local mcf = facingCentre(p)
		part("Mountain", V3(w, h * 0.5, 40), mcf * CFrame.new(0, h * 0.25, 0), MOUNTAIN, SCENERY)
		part("Mountain", V3(w * 0.62, h * 0.32, 36), mcf * CFrame.new(rnd() * 8, h * 0.66, 0), MOUNTAIN_LIGHT, SCENERY)
		part("MountainSnow", V3(w * 0.3, h * 0.18, 34), mcf * CFrame.new(rnd() * 6, h * 0.91, 0), SNOW, SCENERY)
	end
end

----------------------------------------------------------------------
-- The walls round the fight, and the marks the boss will use
----------------------------------------------------------------------
local function buildBounds()
	local N = 48
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		if math.abs(wrap(a)) > 0.1 then -- the gap is the path to the gate
			local p = onRing(FIGHT_R, a, 30)
			local wall = part("EdgeWall", V3(2 * FIGHT_R * math.sin(math.pi / N) + 0.5, 60, 2), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))),
				WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(wall, "DigEdgeWall")
		end
	end
	-- the path to the gate has walls down both sides, so you can't wander off
	-- (and a short piece at each corner closes the gap where they meet the ring)
	for _, sx in ipairs({ -1, 1 }) do
		local z0, z1 = FIGHT_R - 2, GATE_R + 2
		local wall = part("EdgeWall", V3(2, 60, z1 - z0), CFrame.new(at(sx * (PATH_HALF + 1.5), 30, (z0 + z1) / 2)), WHITE,
			{ Transparency = 1, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(wall, "DigEdgeWall")
		local corner = part("EdgeWall", V3(5, 60, 2), CFrame.new(at(sx * (PATH_HALF + 4), 30, FIGHT_R - 0.5)), WHITE,
			{ Transparency = 1, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(corner, "DigEdgeWall")
	end
	-- Where Knight Burrowmore kneels: the middle of the dig, facing the gate
	-- you come in by. BossService builds the knight himself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 3)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function DigBuilder.Build()
	local old = Workspace:FindFirstChild("DigArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "DigArena"
	seed = 20260926 -- (the same "random" every time it's built)

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Ground", buildGround },
		{ "Fence", buildFence },
		{ "Gate", buildGate },
		{ "Camp and treasure", buildCamp },
		{ "Plains", buildPlains },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[DigBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 3)
	m:SetAttribute("Center", CENTER)
	m.Parent = Workspace
	if failed == 0 then
		print("[DigBuilder] The Glimmer Dig built OK")
	end
	return m
end

return DigBuilder
