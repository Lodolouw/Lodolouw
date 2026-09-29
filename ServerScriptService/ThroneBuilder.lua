--[[
	ThroneBuilder  (ModuleScript, parent: ServerScriptService, name: "ThroneBuilder")

	Builds the Spire's tenth and last floor: THE THRONE SUMMIT, King
	Gavelgrunt's arena.

	The very top of the Spire, above the clouds in a thunderstorm. A round
	stone courtyard paved with big square flagstones, a purple carpet running
	from the gate in the south wall up to a giant golden throne at the north
	end (he sleeps on it), four tall stone pillars at the diagonals (his big
	moves break them), three low round podiums near the edge (stand on one
	when he finds you GUILTY), battlements all round with his banners (a gold
	crown on purple) and torches, rising out of a sea of storm cloud with a
	wall of mist all round (like Oozark's hollow). Everything is chunky and 8-bit, in the game's 32
	colours. (The rain and the lightning are drawn on each screen: see his
	body file.)

	The courtyard's shape comes from ReplicatedStorage/ThronePlan (the same
	numbers his moves and every screen use).

	Everything the fight needs is marked for SpireService / BossService / his
	moves:
	  * "ArenaSpawn"       where you arrive (Floor = 10)
	  * "ArenaExit"        the Leave prompt on the gate, plus a walk-up box in
	                       front of it (AutoOpenZone, Spire = "Leave")
	  * "BossHome"         where he waits (ThronePlan.Home), Floor = 10, facing the gate
	  * "ThroneEdgeWall"   the invisible walls round the courtyard
	  * "ThronePillar"     each pillar (a Model: Index 1-4, Floor = 10). Its
	                       parts named "Column" are the standing pillar; the
	                       ones named "Rubble" are its broken stump (hidden to
	                       begin with). His moves swap them when it breaks.
	  * "ThronePodium"     each podium (Index 1-3)
	  * "KingThrone"       the throne (a Model; his round 3 throws it: every
	                       screen hides it then and draws it flying)
	  * the arena model itself: Floor = 10, Center, FightRadius

	Main calls ThroneBuilder.Build() once at startup, after the other floors
	and before BossService (which puts the king on his BossHome). The floor
	you fight on is one solid, flat Part whose top is exactly y = 0.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThronePlan = require(ReplicatedStorage:WaitForChild("ThronePlan"))

local ThroneBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the gate; the throne is at the north end)
----------------------------------------------------------------------
-- (every arena has its own spot, 2600 studs apart: see the handoff notes)
local CENTER = V3(0, 0, 5200)
local R = ThronePlan.Radius
local WALL = ThronePlan.Wall
local DOOR_HALF = ThronePlan.DoorHalf
local GATE_H = 16

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local STONE = RGB(139, 155, 180)
local STONE_LIGHT = RGB(192, 203, 220)
local STONE_DARK = RGB(90, 105, 136)
local STONE_DEEP = RGB(58, 68, 102)
local PURPLE = RGB(104, 56, 108)
local PURPLE_DARK = RGB(62, 39, 49)
local MAGENTA = RGB(181, 80, 136)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local GOLD = RGB(254, 174, 52)
local YELLOW = RGB(254, 231, 97)
local ORANGE = RGB(247, 118, 34)
local WHITE = RGB(255, 255, 255)
local STORM = RGB(90, 105, 136) -- storm clouds
local STORM_DARK = RGB(58, 68, 102)
local WOOD = RGB(184, 111, 80)
local WOOD_DARK = RGB(115, 62, 57)
local INK = RGB(24, 20, 37)

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other floors')
----------------------------------------------------------------------
local seed = 20261310
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function between(a, b)
	return a + (b - a) * rnd()
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

local function anchorPart(name, cf, parent)
	return part(name, V3(1, 1, 1), cf, WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

-- words on a board (a SurfaceGui on its front)
local function signText(board, text, color)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = Enum.NormalId.Front
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

-- a frame at `p` whose front (-Z) faces the middle of the courtyard
local function facingCentre(p)
	local mid = V3(CENTER.X, p.Y, CENTER.Z)
	if (mid - p).Magnitude < 0.01 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, mid)
end

-- a flat round disc lying on the floor (a cylinder's round faces point along X)
local function disc(name, center, diameter, thickness, color, extra, parent)
	return part(name, V3(thickness, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color,
		merge({ Shape = Enum.PartType.Cylinder }, extra), parent)
end

----------------------------------------------------------------------
-- The courtyard floor: flagstones and the carpet
----------------------------------------------------------------------
local function buildFloor()
	-- the solid floor you stand on (its top is exactly y = 0)
	local size = (WALL + 10) * 2
	part("CourtyardFloor", V3(size, 4, size), CFrame.new(at(0, -2, 0)), STONE_DARK, { Material = Mat.SmoothPlastic })
	-- the flagstones: each a slightly different stone (8-bit: flat colours)
	local shades = { STONE, STONE_LIGHT, STONE, RGB(139, 155, 180), STONE_DARK }
	local c = ThronePlan.Cell
	for _, t in ipairs(ThronePlan.tiles()) do
		local shade = shades[math.floor(rnd() * #shades) + 1]
		part("Flagstone", V3(c - 0.6, 0.1, c - 0.6), CFrame.new(at(t[1], 0.04, t[2])), shade, DECOR)
	end
	-- the round rim of the courtyard: a ring of darker stone
	local N = 48
	for i = 1, N do
		local a = (i - 0.5) / N * math.pi * 2
		local p = at(math.sin(a) * (R + 1.2), 0.06, math.cos(a) * (R + 1.2))
		part("Rim", V3(2 * (R + 1.2) * math.sin(math.pi / N) + 0.3, 0.12, 2.4), facingCentre(p), STONE_DEEP, DECOR)
	end
	-- THE ROYAL CARPET: from the gate to the throne's steps, purple with a gold edge
	local z0, z1 = R, ThronePlan.Throne.Z + 7 * ThronePlan.ThroneScale
	local len = z0 - z1
	part("Carpet", V3(9, 0.12, len), CFrame.new(at(0, 0.1, (z0 + z1) / 2)), PURPLE, DECOR)
	for _, sx in ipairs({ -1, 1 }) do
		part("CarpetEdge", V3(0.8, 0.13, len), CFrame.new(at(sx * 4.9, 0.1, (z0 + z1) / 2)), GOLD, DECOR)
	end
	-- a gold crown sewn on the carpet, half way up
	part("CarpetCrown", V3(5, 0.14, 2), CFrame.new(at(0, 0.11, 18)), GOLD, DECOR)
	for i = -1, 1 do
		part("CarpetCrownPoint", V3(1.1, 0.14, 1.6), CFrame.new(at(i * 1.9, 0.11, 16.4)), GOLD, DECOR)
	end
end

----------------------------------------------------------------------
-- The throne
----------------------------------------------------------------------
local function buildThrone()
	local t = Instance.new("Model")
	t.Name = "KingThrone"
	local b = ThronePlan.Throne
	-- (drawn at the plan's size, built ThroneScale times bigger - he's a
	-- walrus nine times your height, and he sleeps sitting on it)
	local S = ThronePlan.ThroneScale
	local function tp(name, size, x, y, z, color, extra)
		return part(name, size * S, CFrame.new(at(b.X + x * S, y * S, b.Z + z * S)), color, merge(DECOR, extra), t)
	end
	-- the steps up to it
	tp("ThroneStep", V3(26, 1.2, 14), 0, 0.6, 0, STONE_LIGHT)
	tp("ThroneStep", V3(22, 1.2, 10), 0, 1.8, -1, STONE)
	tp("ThroneStepEdge", V3(26.2, 0.3, 0.6), 0, 1.25, 7, GOLD)
	-- the seat: a giant gold chair with red cushions (he's huge: so is his chair)
	tp("ThroneSeat", V3(18, 6, 10), 0, 5.4, -1, GOLD)
	tp("ThroneCushion", V3(15, 1.6, 8.4), 0, 9.2, -0.6, RED)
	tp("ThroneBack", V3(18, 22, 2.4), 0, 19, -5.2, GOLD)
	tp("ThroneBackCushion", V3(13, 16, 0.6), 0, 18, -3.8, RED)
	tp("ThroneBackTrim", V3(13.6, 0.6, 0.7), 0, 26.2, -3.7, YELLOW)
	for _, sx in ipairs({ -1, 1 }) do
		tp("ThroneArm", V3(2.4, 5, 10), sx * 9.4, 10.6, -1, GOLD)
		tp("ThroneArmKnob", V3(3, 3, 3), sx * 9.4, 14.2, 3.4, YELLOW)
		tp("ThroneBackPost", V3(3, 26, 3), sx * 9.8, 21, -5.2, GOLD)
		tp("ThronePostTop", V3(3.8, 3.8, 3.8), sx * 9.8, 35.4, -5.2, YELLOW)
	end
	-- its crest: a big crown on top, with three gems
	tp("ThroneCrest", V3(12, 4, 2.6), 0, 32, -5.2, GOLD)
	for i = -1, 1 do
		tp("ThroneCrestPoint", V3(2.4, 3.2, 2.6), i * 4.4, 35.4, -5.2, GOLD)
		tp("ThroneGem", V3(1.4, 1.4, 0.6), i * 4.4, 32, -3.8, (i == 0) and RED or ((i < 0) and RGB(0, 153, 219) or RGB(99, 199, 77)))
	end
	t:SetAttribute("Floor", 10)
	CollectionService:AddTag(t, "KingThrone")
	t.Parent = m
end

----------------------------------------------------------------------
-- The pillars (breakable) and the podiums
----------------------------------------------------------------------
local function buildPillars()
	local pr, ph = ThronePlan.PillarRadius, ThronePlan.PillarHeight
	for i, off in ipairs(ThronePlan.Pillars) do
		local pm = Instance.new("Model")
		pm.Name = "Pillar"
		local base = at(off.X, 0, off.Z)
		-- standing: a chunky square base, the shaft, a capital, a gold band
		local function column(name, size, y, color, extra)
			return part("Column", size, CFrame.new(base + V3(0, y, 0)), color,
				merge({ CastShadow = true }, merge(extra, { Name = "Column" })), pm)
		end
		column("Base", V3(pr * 2 + 1.6, 1.6, pr * 2 + 1.6), 0.8, STONE_DARK)
		column("Shaft", V3(pr * 2, ph - 3.2, pr * 2), 1.6 + (ph - 3.2) / 2, STONE_LIGHT)
		column("Band", V3(pr * 2 + 0.3, 0.8, pr * 2 + 0.3), ph * 0.55, GOLD, { CanCollide = false })
		column("Capital", V3(pr * 2 + 1.6, 1.6, pr * 2 + 1.6), ph - 0.8, STONE_DARK)
		-- broken: a jagged stump and chunks round it (hidden until it breaks)
		local function rubble(size, cf, color)
			return part("Rubble", size, cf, color, { Transparency = 1, CanCollide = false, CanQuery = false }, pm)
		end
		rubble(V3(pr * 2 + 1.6, 1.6, pr * 2 + 1.6), CFrame.new(base + V3(0, 0.8, 0)), STONE_DARK)
		rubble(V3(pr * 2, 3.2, pr * 2), CFrame.new(base + V3(0, 3.2, 0)) * CFrame.Angles(0.1, 0.4, -0.08), STONE_LIGHT)
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2 + rnd()
			local d = pr + 1.5 + rnd() * 3
			local s = 1.2 + rnd() * 1.6
			rubble(V3(s, s * 0.7, s), CFrame.new(base + V3(math.cos(a) * d, s * 0.35, math.sin(a) * d)) * CFrame.Angles(rnd(), rnd() * 3, rnd()),
				(k % 2 == 0) and STONE or STONE_LIGHT)
		end
		pm:SetAttribute("Index", i)
		pm:SetAttribute("Floor", 10)
		CollectionService:AddTag(pm, "ThronePillar")
		pm.Parent = m
	end
end

local function buildPodiums()
	local r, h = ThronePlan.PodiumRadius, ThronePlan.PodiumHeight
	for i, off in ipairs(ThronePlan.Podiums) do
		local c = at(off.X, 0, off.Z)
		-- a low round stone step (you walk up onto it), a gold rim, a purple top
		local pod = disc("Podium", c + V3(0, h / 2, 0), r * 2, h, STONE_LIGHT, { CastShadow = true })
		disc("PodiumTop", c + V3(0, h + 0.03, 0), r * 2 - 1.2, 0.06, PURPLE, DECOR)
		disc("PodiumRim", c + V3(0, h + 0.02, 0), r * 2, 0.04, GOLD, DECOR)
		-- a little gold gavel sign standing by it (so you know what it's for)
		local post = part("PodiumPost", V3(0.5, 4, 0.5), CFrame.new(c + V3(0, 2, 0) + (c - at(0, 0, 0)).Unit * (r + 1)), WOOD_DARK, DECOR)
		local sign = part("PodiumSign", V3(3.6, 1.4, 0.3), facingCentre(post.Position + V3(0, 2.4, 0)), WOOD, DECOR)
		signText(sign, "SAFE", GOLD)
		pod:SetAttribute("Index", i)
		pod:SetAttribute("Floor", 10)
		CollectionService:AddTag(pod, "ThronePodium")
	end
end

----------------------------------------------------------------------
-- The battlements, banners and torches round the edge
----------------------------------------------------------------------
local function buildWalls()
	local N = 40
	for i = 1, N do
		local a = (i - 0.5) / N * math.pi * 2
		local x, z = math.sin(a) * (WALL + 1.5), math.cos(a) * (WALL + 1.5)
		-- (the south gap: the gate)
		if not (z > 0 and math.abs(x) < DOOR_HALF + 4) then
			local p = at(x, 0, z)
			local len = 2 * (WALL + 1.5) * math.sin(math.pi / N) + 0.5
			part("Battlement", V3(len, 7, 3), facingCentre(p + V3(0, 3.5, 0)), STONE, SCENERY)
			-- every other one: a merlon on top (the chunky crenellation)
			if i % 2 == 0 then
				part("Merlon", V3(len * 0.6, 3, 3), facingCentre(p + V3(0, 8.5, 0)), STONE_LIGHT, SCENERY)
			end
			-- banners and torches, spaced round
			if i % 5 == 0 then
				local inward = facingCentre(p + V3(0, 0, 0))
				local bp = inward * CFrame.new(0, 12, -1.8)
				part("Banner", V3(4.2, 9, 0.3), bp, PURPLE, DECOR)
				part("BannerTrim", V3(4.4, 0.6, 0.35), bp * CFrame.new(0, 4.2, 0), GOLD, DECOR)
				part("BannerCrown", V3(2.6, 1.4, 0.36), bp * CFrame.new(0, 1, 0), GOLD, DECOR)
				for k = -1, 1 do
					part("BannerCrownPoint", V3(0.6, 1, 0.36), bp * CFrame.new(k * 0.9, 2.1, 0), GOLD, DECOR)
				end
				part("BannerTail", V3(2.9, 2.9, 0.3), bp * CFrame.new(0, -4.5, 0) * CFrame.Angles(0, 0, math.pi / 4), PURPLE, DECOR)
			elseif i % 5 == 2 then
				local inward = facingCentre(p)
				local tp = inward * CFrame.new(0, 9, -2)
				part("TorchHolder", V3(0.8, 2.4, 0.8), tp, WOOD_DARK, DECOR)
				local flame = part("TorchFlame", V3(1.3, 1.8, 1.3), tp * CFrame.new(0, 1.9, 0), ORANGE, merge(DECOR, { Material = Mat.Neon }))
				flame:SetAttribute("Floor", 10)
				CollectionService:AddTag(flame, "ThroneTorch")
				local light = Instance.new("PointLight")
				light.Color = ORANGE
				light.Range = 14
				light.Brightness = 1.2
				light.Parent = flame
			end
		end
	end
end

----------------------------------------------------------------------
-- The gate in the south wall, the sky and clouds
----------------------------------------------------------------------
local function buildGate()
	local z = WALL + 1.5
	-- two big towers either side, an arch over the top
	for _, sx in ipairs({ -1, 1 }) do
		part("GateTower", V3(8, 22, 8), CFrame.new(at(sx * (DOOR_HALF + 4), 11, z)), STONE, SCENERY)
		part("GateTowerTop", V3(9.4, 2, 9.4), CFrame.new(at(sx * (DOOR_HALF + 4), 23, z)), STONE_LIGHT, SCENERY)
		part("GateFlag", V3(0.4, 6, 0.4), CFrame.new(at(sx * (DOOR_HALF + 4), 27, z)), WOOD_DARK, DECOR)
		part("GateFlagCloth", V3(3.6, 2.4, 0.2), CFrame.new(at(sx * (DOOR_HALF + 4) + sx * 1.8, 28.8, z)), PURPLE, DECOR)
	end
	part("GateArch", V3(DOOR_HALF * 2, 4, 6), CFrame.new(at(0, GATE_H + 2, z)), STONE_LIGHT, SCENERY)
	local sign = part("GateSign", V3(14, 2.6, 0.4), CFrame.new(at(0, GATE_H + 5.4, z - 3.2)) * CFrame.Angles(0, math.pi, 0), PURPLE_DARK, SCENERY)
	signText(sign, "THE THRONE SUMMIT", GOLD)
	-- the portcullis, raised (its bottom edge shows under the arch)
	for k = -3, 3 do
		part("Portcullis", V3(0.5, 3, 0.5), CFrame.new(at(k * 2, GATE_H - 1.5, z)), INK, DECOR)
	end
	-- the way out: the Leave prompt on the gate and the walk-up box in front of it
	local gatePost = part("GateExit", V3(DOOR_HALF * 2, GATE_H, 1), CFrame.new(at(0, GATE_H / 2, z + 2)), INK,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "The Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = gatePost
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(CFrame.new(at(0, 4, WALL + 0.5)), V3(DOOR_HALF * 2 - 1, 8, 3.4), "Spire", "Leave")
	-- where you arrive: just inside the gate, looking up the carpet at him
	local s = ThronePlan.Spawn
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(s.X, 3, s.Z), at(0, 3, 0)))
	arrive:SetAttribute("Floor", 10)
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

local function buildSky()
	-- MIST hiding the void (like Oozark's hollow): the summit rises out of a
	-- sea of storm cloud - two see-through layers over a solid cloud floor,
	-- soft cloud puffs heaped evenly all round the battlements so there's
	-- never a hard edge, and a drifting fog under the courtyard
	local MIST = RGB(150, 160, 184)
	local PUFF = { RGB(170, 180, 202), RGB(139, 155, 180), RGB(192, 203, 220) }
	for _, layer in ipairs({ { -22, 0.7 }, { -40, 0.45 } }) do
		part("SummitMist", V3(2048, 1, 2048), CFrame.new(at(0, layer[1], 0)), MIST,
			merge(DECOR, { Transparency = layer[2], CanTouch = false }))
	end
	part("SummitCloudFloor", V3(2048, 1, 2048), CFrame.new(at(0, -60, 0)), STORM, merge(DECOR, { CanTouch = false }))
	-- three rings of puffs, evenly spread (each ring shifted so they don't line up)
	for ring, r in ipairs({ { WALL + 16, 30, -14 }, { WALL + 60, 44, -24 }, { WALL + 120, 60, -34 } }) do
		local n = 18 + ring * 6
		for i = 0, n - 1 do
			local ang = (i + (ring - 1) / 3 + rnd() * 0.4) / n * math.pi * 2
			local d = r[1] + rnd() * 16
			local size = r[2] * (0.75 + rnd() * 0.5)
			part("CloudPuff", V3(size, size * 0.55, size), CFrame.new(at(math.sin(ang) * d, r[3] - rnd() * 8, math.cos(ang) * d)),
				PUFF[(i + ring) % 3 + 1], merge(DECOR, { Shape = Enum.PartType.Ball, Transparency = 0.1 + rnd() * 0.2, CanTouch = false }))
		end
	end
	local underFog = anchorPart("UnderFog", CFrame.new(at(0, -18, 0)))
	underFog.Size = V3(360, 10, 360)
	local uf = Instance.new("ParticleEmitter")
	uf.Rate = 6
	uf.Color = ColorSequence.new(RGB(192, 203, 220))
	uf.LightEmission = 0.05
	uf.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 50), NumberSequenceKeypoint.new(1, 90) })
	uf.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
	uf.Lifetime = NumberRange.new(16, 24)
	uf.Speed = NumberRange.new(0.5, 2)
	uf.SpreadAngle = Vector2.new(180, 8)
	uf.Shape = Enum.ParticleEmitterShape.Box
	uf.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	uf.Parent = underFog
	-- A WALL OF MIST all the way round (like Oozark's): nothing out there can
	-- be seen, just the storm. Panels meeting edge to edge, a muted storm grey.
	local WALL_R, SEGS = 320, 72
	local bottom, top = -62, 420
	local apothem = WALL_R * math.cos(math.pi / SEGS)
	local chord = 2 * WALL_R * math.sin(math.pi / SEGS)
	for i = 0, SEGS - 1 do
		local ang = (i + 0.5) / SEGS * math.pi * 2
		local p = at(math.sin(ang) * apothem, (bottom + top) / 2, math.cos(ang) * apothem)
		part("MistWall", V3(chord, top - bottom, 1), CFrame.lookAt(p, p + V3(math.sin(ang), 0, math.cos(ang))), RGB(96, 106, 130),
			merge(DECOR, { Transparency = 0.08, CanTouch = false }))
	end
	-- soft fog drifting just inside it, so its edge never looks flat
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		local f = anchorPart("EdgeFog", CFrame.new(at(math.sin(ang) * 280, 20, math.cos(ang) * 280)))
		f.Size = V3(120, 60, 40)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 2
		e.Color = ColorSequence.new(RGB(150, 160, 184))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 60), NumberSequenceKeypoint.new(1, 100) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(18, 26)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 10)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Parent = f
	end
	-- the Spire's top: the courtyard sits on a great stone cap
	part("SummitCap", V3((WALL + 6) * 2, 18, (WALL + 6) * 2), CFrame.new(at(0, -13, 0)), STONE_DEEP, SCENERY)
	part("SummitCapTrim", V3((WALL + 7) * 2, 2, (WALL + 7) * 2), CFrame.new(at(0, -4.5, 0)), GOLD, DECOR)
	-- and the tower going on down into the clouds
	part("SpireBelow", V3(90, 90, 90), CFrame.new(at(0, -67, 0)), STONE_DARK, DECOR)
end

----------------------------------------------------------------------
-- The walls round the courtyard, and the marks the boss uses
----------------------------------------------------------------------
local function buildBounds()
	local H = 70
	local N = 40
	for i = 1, N do
		local a = (i - 0.5) / N * math.pi * 2
		local x, z = math.sin(a) * WALL, math.cos(a) * WALL
		-- (the south gap: the way to the gate)
		if not (z > 0 and math.abs(x) < DOOR_HALF) then
			local p = at(x, H / 2, z)
			local len = 2 * WALL * math.sin(math.pi / N) + 1
			local w = part("EdgeWall", V3(len, H, 2), facingCentre(p), WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(w, "ThroneEdgeWall")
		end
	end
	-- the sides of the way out, and right behind the gate
	for _, sx in ipairs({ -1, 1 }) do
		local w = part("EdgeWall", V3(2, H, 8), CFrame.new(at(sx * (DOOR_HALF + 1), H / 2, WALL + 2)), WHITE,
			{ Transparency = 1, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(w, "ThroneEdgeWall")
	end
	local back = part("EdgeWall", V3(DOOR_HALF * 2 + 2, H, 1), CFrame.new(at(0, H / 2, WALL + 5)), WHITE,
		{ Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(back, "ThroneEdgeWall")
	-- Where the king waits: up the carpet in front of his throne, facing the
	-- gate you come in by. BossService puts him on this spot.
	local h = ThronePlan.Home
	local home = anchorPart("BossHome", CFrame.new(at(h.X, 0, h.Z)))
	home:SetAttribute("Floor", 10)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function ThroneBuilder.Build()
	local old = Workspace:FindFirstChild("ThroneArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "ThroneArena"
	seed = 20261310 -- (the same "random" every time it's built)

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Floor", buildFloor },
		{ "Throne", buildThrone },
		{ "Pillars", buildPillars },
		{ "Podiums", buildPodiums },
		{ "Walls", buildWalls },
		{ "Gate", buildGate },
		{ "Sky", buildSky },
		{ "Bounds and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[ThroneBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 10)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("FightRadius", R)
	m.Parent = Workspace
	if failed == 0 then
		print("[ThroneBuilder] The Throne Summit built OK")
	end
	return m
end

ThroneBuilder.Center = CENTER
ThroneBuilder.FightRadius = R

return ThroneBuilder
