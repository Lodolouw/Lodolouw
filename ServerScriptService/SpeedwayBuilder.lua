--[[
	SpeedwayBuilder  (ModuleScript, parent: ServerScriptService, name: "SpeedwayBuilder")

	Builds the Spire's fifth floor: PISTON SPEEDWAY, Speedy Revvington's arena.

	An oval racetrack out in the desert on a hot afternoon. You come out of
	the tunnel under the pit garages onto the track: dark asphalt with a white
	line down the middle, red-and-white curbs round the grassy infield (a big
	"57" painted on it), and a checkered start line under the starting-light
	gantry, where Revvington sits revving. Round the outside: a tyre wall and
	a catch fence, packed grandstands of blocky fans under a striped roof, a
	press tower, the pit garages, a giant screen, flags, a blimp overhead, and
	red desert mesas, cacti and a water tower out to the horizon.
	Everything is chunky and 8-bit, in the game's 32 colours.

	THE SHAPE: the track is a stadium - a "capsule". Take the line down its
	middle from x = -SPINE to x = +SPINE; every spot within EDGE studs of that
	line is the track (you fight anywhere on it, and on the infield, which is
	within INFIELD of the line). Bosses/Revvington.lua keeps him inside it with
	the same sum (the model's attributes Spine and Edge).

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"   where you arrive: in the tunnel (in this model, Floor = 5)
	  * "ArenaExit"    the Leave prompt on the tunnel's fog (switched off on your
	                   screen), plus a walk-up box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"     the start line, Floor = 5, facing down the track
	  * "SpeedwayWall" the invisible walls round the track
	  * the start lights: parts named StartLight1..5 on the gantry (BossClient
	    lights them for the countdown: red, red, red... GREEN)
	  * the model itself carries Floor = 5, Center, Spine, Edge and Infield

	Main calls SpeedwayBuilder.Build() once at startup, after the dojo and
	before BossService (which parks Revvington on his BossHome).
	Everything inside the track's edge is paper-thin paint on one flat floor:
	he drives straight through all of it, and so can you.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local SpeedwayBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the main straight and its grandstand; the tunnel
-- you come in by is north)
----------------------------------------------------------------------
local CENTER = V3(0, 0, -2600) -- well away from the lobby and the other floors
local SPINE = 70 -- the line down the middle of the track runs from x = -70 to +70
local EDGE = 62 -- the track's outside edge (the invisible wall), from that line
local INFIELD = 30 -- the grass in the middle, from that line
local MID = (EDGE + INFIELD) / 2 -- the white line down the middle of the track
local GAP = 8 -- half the width of the tunnel
local TUNNEL_END = 94 -- the tunnel runs from the track's edge out to here (north)
local SPAWN_Z = -80 -- where you arrive (in the tunnel)
local WALL_R = 65 -- the tyre wall, just outside the edge

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local ASPHALT = RGB(58, 68, 102)
local ASPHALT_DARK = RGB(38, 43, 68)
local GRASS = RGB(99, 199, 77)
local GRASS_DARK = RGB(62, 137, 72)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local ORANGE = RGB(247, 118, 34)
local BLUE = RGB(0, 153, 219)
local BLUE_DARK = RGB(18, 78, 137)
local CYAN = RGB(44, 232, 245)
local CONCRETE = RGB(192, 203, 220)
local CONCRETE_DARK = RGB(139, 155, 180)
local STEEL = RGB(90, 105, 136)
local SAND = RGB(228, 166, 114)
local SAND_DARK = RGB(194, 133, 105)
local ROCK = RGB(190, 74, 47)
local ROCK_LIGHT = RGB(215, 118, 67)
local ROCK_DARK = RGB(115, 62, 57)
local CACTUS = RGB(62, 137, 72)
local SKIN = { RGB(232, 183, 150), RGB(194, 133, 105), RGB(115, 62, 57), RGB(234, 212, 170) }
local SHIRTS = { RED, BLUE, YELLOW, GRASS, ORANGE, WHITE, RGB(181, 80, 136), CYAN, GOLD, RGB(104, 56, 108) }
local FOG = RGB(235, 240, 255)

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other arenas')
----------------------------------------------------------------------
local seed = 20260928
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function pick(list)
	return list[math.floor(rnd() * #list) + 1]
end

local m -- the arena model, set by Build()

local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
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

local function anchorPart(name, cf, parent)
	return part(name, V3(1, 1, 1), cf, WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
end

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

-- words on a board (a SurfaceGui on its front face)
local function signText(board, text, color, face, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(board.Size.X * 40, board.Size.Y * 40)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or INK
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

-- A walk round the capsule at distance `r` from its middle line: calls
-- fn(position, outward direction, along-the-way direction) every `step`
-- studs (the two straights, then the two round ends).
local function aroundCapsule(r, step, fn)
	local out = {}
	-- the south straight (+z), west to east, then the east end, the north
	-- straight east to west, the west end
	local len = SPINE * 2
	local n = math.max(1, math.floor(len / step + 0.5))
	for i = 0, n - 1 do
		local x = -SPINE + (i + 0.5) * len / n
		table.insert(out, { at(x, 0, r), V3(0, 0, 1), V3(1, 0, 0) })
	end
	local arcN = math.max(2, math.floor(math.pi * r / step + 0.5))
	for i = 0, arcN - 1 do
		local a = (i + 0.5) / arcN * math.pi -- from south round the east to north
		local o = V3(math.sin(a), 0, math.cos(a))
		table.insert(out, { at(SPINE, 0, 0) + o * r, o, V3(math.cos(a), 0, -math.sin(a)) })
	end
	for i = 0, n - 1 do
		local x = SPINE - (i + 0.5) * len / n
		table.insert(out, { at(x, 0, -r), V3(0, 0, -1), V3(-1, 0, 0) })
	end
	for i = 0, arcN - 1 do
		local a = math.pi + (i + 0.5) / arcN * math.pi
		local o = V3(math.sin(a), 0, math.cos(a))
		table.insert(out, { at(-SPINE, 0, 0) + o * r, o, V3(math.cos(a), 0, -math.sin(a)) })
	end
	for k, v in ipairs(out) do
		fn(v[1], v[2], v[3], k)
	end
	return #out
end

-- pixel digits (3 x 5), for the "57" painted on the infield
local DIGITS = {
	["5"] = { "###", "#..", "###", "..#", "###" },
	["7"] = { "###", "..#", ".#.", ".#.", ".#." },
}
local function paintNumber(text, center, pixel, color, rotY)
	local cf = CFrame.new(center) * CFrame.Angles(0, rotY or 0, 0)
	local w = #text * 4 - 1
	for ci = 1, #text do
		local rows = DIGITS[string.sub(text, ci, ci)]
		if rows then
			for ry = 1, 5 do
				for rx = 1, 3 do
					if string.sub(rows[ry], rx, rx) == "#" then
						local x = ((ci - 1) * 4 + rx - (w + 1) / 2) * pixel
						local z = (ry - 3) * pixel
						part("InfieldNumber", V3(pixel, 0.12, pixel), cf * CFrame.new(x, 0.1, z), color, DECOR)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- The track and the infield
----------------------------------------------------------------------
local function buildTrack()
	-- the asphalt: one solid floor the shape of the whole track, top at y = 0
	part("Track", V3(SPINE * 2, 4, EDGE * 2), CFrame.new(at(0, -2, 0)), ASPHALT)
	for _, sx in ipairs({ -1, 1 }) do
		cylinder("TrackEnd", 4, EDGE * 2, CFrame.new(at(sx * SPINE, -2, 0)), ASPHALT)
	end
	-- the infield grass, a hair above
	part("Infield", V3(SPINE * 2, 0.1, INFIELD * 2), CFrame.new(at(0, 0.05, 0)), GRASS, DECOR)
	for _, sx in ipairs({ -1, 1 }) do
		cylinder("InfieldEnd", 0.1, INFIELD * 2, CFrame.new(at(sx * SPINE, 0.05, 0)), GRASS, DECOR)
	end
	-- mown stripes across the grass
	for i = -6, 6, 2 do
		part("GrassStripe", V3(10, 0.12, INFIELD * 2 - 2), CFrame.new(at(i * 10, 0.06, 0)), GRASS_DARK, DECOR)
	end
	-- red-and-white curbs round the infield
	aroundCapsule(INFIELD, 4, function(p, out, along, k)
		local c = (k % 2 == 0) and RED or WHITE
		part("Curb", V3(4.1, 0.16, 1.8), CFrame.lookAt(p + V3(0, 0.08, 0), p + V3(0, 0.08, 0) + along) * CFrame.Angles(0, math.pi / 2, 0), c, DECOR)
		local _ = out
	end)
	-- a white line along the outside edge, and the dashed line down the middle
	aroundCapsule(EDGE - 2, 6, function(p, out, along)
		part("EdgeLine", V3(6.2, 0.1, 0.6), CFrame.lookAt(p + V3(0, 0.05, 0), p + V3(0, 0.05, 0) + along) * CFrame.Angles(0, math.pi / 2, 0), WHITE, DECOR)
		local _ = out
	end)
	aroundCapsule(MID, 10, function(p, out, along, k)
		if k % 2 == 0 then
			part("MidLine", V3(5, 0.1, 0.5), CFrame.lookAt(p + V3(0, 0.05, 0), p + V3(0, 0.05, 0) + along) * CFrame.Angles(0, math.pi / 2, 0), WHITE, DECOR)
		end
		local _ = out
	end)
	-- skid marks worn into the track (old races)
	for _ = 1, 16 do
		local x = (rnd() * 2 - 1) * SPINE
		local z = (rnd() < 0.5 and -1 or 1) * (INFIELD + 4 + rnd() * (EDGE - INFIELD - 8))
		local len = 10 + rnd() * 16
		local yaw = (rnd() - 0.5) * 0.4
		for _, off in ipairs({ -2.2, 2.2 }) do
			part("SkidMark", V3(len, 0.09, 0.8), CFrame.new(at(x, 0.045, z)) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, off), ASPHALT_DARK, DECOR)
		end
	end

	-- THE START / FINISH LINE: a checkered strip across the main straight
	local sq = 2
	local nz = math.floor((EDGE - INFIELD) / sq)
	for row = 0, 1 do
		for i = 0, nz - 1 do
			local z = INFIELD + (i + 0.5) * (EDGE - INFIELD) / nz
			local c = ((i + row) % 2 == 0) and WHITE or INK
			part("Checker", V3(sq, 0.12, (EDGE - INFIELD) / nz), CFrame.new(at((row - 0.5) * sq, 0.06, z)), c, DECOR)
		end
	end
	-- the starting grid: white boxes behind the line
	for k = 1, 3 do
		local x = -10 - (k - 1) * 22
		for _, z in ipairs({ MID - 7, MID + 7 }) do
			part("GridBox", V3(0.5, 0.1, 9), CFrame.new(at(x, 0.05, z)), WHITE, DECOR)
			part("GridBox", V3(8, 0.1, 0.5), CFrame.new(at(x - 4, 0.05, z - 4.5)), WHITE, DECOR)
		end
	end

	-- the big 57 and a lightning bolt, painted on the infield (white: nothing
	-- painted on the track is red, so it's never mistaken for a warning)
	paintNumber("57", at(-24, 0, 0), 4, WHITE, 0)
	local bolt = { { 18, -10 }, { 22, -6 }, { 18, -2 }, { 24, 2 }, { 20, 6 }, { 26, 10 } }
	for i = 1, #bolt - 1 do
		local a, b = bolt[i], bolt[i + 1]
		local p, q = at(a[1], 0.12, a[2]), at(b[1], 0.12, b[2])
		part("InfieldBolt", V3(3, 0.14, (q - p).Magnitude + 2), CFrame.lookAt((p + q) / 2, q), YELLOW, DECOR)
	end
	for i = 1, #bolt - 1 do
		local a, b = bolt[i], bolt[i + 1]
		local p, q = at(a[1] + 1.2, 0.1, a[2]), at(b[1] + 1.2, 0.1, b[2])
		part("InfieldBoltShade", V3(3, 0.12, (q - p).Magnitude + 2), CFrame.lookAt((p + q) / 2, q), GOLD, DECOR)
	end
end

----------------------------------------------------------------------
-- The tyre wall and the catch fence round the outside
----------------------------------------------------------------------
local function buildWall()
	-- (the tunnel's gap in the north straight is left open)
	aroundCapsule(WALL_R, 5, function(p, out, along, k)
		local rel = p - CENTER
		if not (math.abs(rel.X) < GAP + 2 and rel.Z < 0) then
			local cf = CFrame.lookAt(p + V3(0, 1.6, 0), p + V3(0, 1.6, 0) + along) * CFrame.Angles(0, math.pi / 2, 0)
			part("TyreWall", V3(5.2, 3.2, 3), cf, INK)
			-- every other stack's sidewalls painted, red and white, facing the track
			if k % 2 == 0 then
				part("TyreStripe", V3(5.2, 0.8, 0.1), cf * CFrame.new(0, 0.3, -1.52) * CFrame.new(0, 0, 0), (k % 4 == 0) and RED or WHITE, DECOR)
			end
			-- the fence above it: a post every third stack, a rail along the top
			if k % 3 == 0 then
				part("FencePost", V3(0.5, 9, 0.5), CFrame.new(p + out * 1.2 + V3(0, 7.7, 0)), STEEL, DECOR)
				part("FenceRail", V3(15.4, 0.35, 0.35), CFrame.lookAt(p + out * 1.2 + V3(0, 12, 0), p + out * 1.2 + V3(0, 12, 0) + along) * CFrame.Angles(0, math.pi / 2, 0), STEEL, DECOR)
			end
		end
	end)
	-- the ground just outside the wall: concrete apron, then the desert
	part("Apron", V3(SPINE * 2, 2, 30), CFrame.new(at(0, -1.1, EDGE + 14)), CONCRETE_DARK, SCENERY)
	part("Apron", V3(SPINE * 2, 2, 30), CFrame.new(at(0, -1.1, -EDGE - 14)), CONCRETE_DARK, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		cylinder("ApronEnd", 2, (EDGE + 16) * 2, CFrame.new(at(sx * SPINE, -1.12, 0)), CONCRETE_DARK, SCENERY)
	end
	cylinder("Desert", 2, 1400, CFrame.new(at(0, -1.4, 0)), SAND, SCENERY)
end

----------------------------------------------------------------------
-- The grandstands (south), the pits and the tunnel (north)
----------------------------------------------------------------------
-- a stepped stand of seats, `rows` deep, facing `face` (a flat direction),
-- fans in about `full` of the seats
local function stand(center, width, rows, face, full, roof)
	local cf = CFrame.lookAt(center, center + face) -- -Z faces the track
	local rowD, rowH = 3.2, 2.2
	for r = 0, rows - 1 do
		local z = r * rowD
		local y = 1 + r * rowH
		part("StandStep", V3(width, rowH, rowD), cf * CFrame.new(0, y - rowH / 2 + 0.5, z), (r % 2 == 0) and CONCRETE or CONCRETE_DARK, SCENERY)
		-- seats and fans along the row
		local seats = math.floor(width / 3)
		for s = 0, seats - 1 do
			local x = -width / 2 + (s + 0.5) * width / seats
			if rnd() < full then
				local shirt = pick(SHIRTS)
				local base = cf * CFrame.new(x, y + 0.5, z)
				part("Fan", V3(1.4, 1.6, 1), base * CFrame.new(0, 0.9, 0), shirt, DECOR)
				part("FanHead", V3(1, 1, 1), base * CFrame.new(0, 2.2, 0), pick(SKIN), DECOR)
				if rnd() < 0.15 then
					-- an arm up, waving (or a foam finger)
					part("FanArm", V3(0.4, 1.4, 0.4), base * CFrame.new(0.9, 2.3, 0) * CFrame.Angles(0, 0, -0.3), (rnd() < 0.5) and shirt or YELLOW, DECOR)
				end
			end
		end
		-- the row's seats: one long red bench
		part("Bench", V3(width - 1, 0.6, 1.2), cf * CFrame.new(0, y + 0.8, z + 0.8), (r % 2 == 0) and RED or RED_DARK, DECOR)
	end
	-- the back wall and the roof
	local backZ = rows * rowD
	local topY = 1 + rows * rowH
	part("StandBack", V3(width, topY + 4, 1.4), cf * CFrame.new(0, (topY + 4) / 2, backZ + 0.7), CONCRETE_DARK, SCENERY)
	if roof then
		for s = -2, 2 do
			part("RoofPost", V3(1, topY + 12, 1), cf * CFrame.new(s * width / 4.5, (topY + 12) / 2, backZ), STEEL, SCENERY)
		end
		local roofCF = cf * CFrame.new(0, topY + 12, backZ * 0.5) * CFrame.Angles(math.rad(-6), 0, 0)
		local stripes = 10
		for i = 0, stripes - 1 do
			local x = -width / 2 + (i + 0.5) * width / stripes
			part("StandRoof", V3(width / stripes + 0.05, 1, backZ + 6), roofCF * CFrame.new(x, 0, 0), (i % 2 == 0) and RED or WHITE, SCENERY)
		end
		part("RoofTrim", V3(width + 1, 1.4, 1), roofCF * CFrame.new(0, -0.2, -(backZ + 6) / 2), GOLD, SCENERY)
		-- the banner along the front of the roof
		local banner = part("StandBanner", V3(width * 0.6, 3.4, 0.4), roofCF * CFrame.new(0, -2.4, -(backZ + 6) / 2), INK, SCENERY)
		signText(banner, "PISTON SPEEDWAY", YELLOW, Enum.NormalId.Front)
	end
	return cf, backZ, topY
end

local function buildStands()
	-- the main grandstand along the south straight, with a roof
	local cf, backZ, topY = stand(at(0, 0, EDGE + 9), 176, 6, V3(0, 0, -1), 0.6, true)
	-- the press tower in the middle, on top
	local tower = cf * CFrame.new(0, topY + 13, backZ * 0.5)
	part("PressBox", V3(30, 8, 12), tower * CFrame.new(0, 5, 0), WHITE, SCENERY)
	part("PressWindows", V3(28, 3, 0.2), tower * CFrame.new(0, 5.4, -6.05), BLUE_DARK, SCENERY)
	part("PressRoof", V3(32, 1.2, 14), tower * CFrame.new(0, 9.6, 0), RED, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("FlagPole", V3(0.5, 12, 0.5), tower * CFrame.new(sx * 13, 16, 0), STEEL, DECOR)
		part("CheckerFlag", V3(0.2, 3, 5), tower * CFrame.new(sx * 13, 20.5, -2.5), WHITE, DECOR)
		for i = 0, 2 do
			for j = 0, 1 do
				if (i + j) % 2 == 0 then
					part("CheckerFlag", V3(0.25, 1, 2.5), tower * CFrame.new(sx * 13, 19.5 + i, -1.25 - j * 2.5), INK, DECOR)
				end
			end
		end
	end
	-- a smaller stand along the north straight, either side of the pits
	for _, sx in ipairs({ -1, 1 }) do
		stand(at(sx * 92, 0, -EDGE - 18), 40, 4, V3(0, 0, 1), 0.55, false)
	end
end

local function buildPits()
	-- the pit garages along the north straight (either side of the tunnel)
	local z0 = -(EDGE + 8)
	for _, sx in ipairs({ -1, 1 }) do
		local cx = sx * 40
		part("PitBuilding", V3(56, 12, 16), CFrame.new(at(cx, 5, z0 - 8)), CONCRETE, SCENERY)
		part("PitRoof", V3(58, 1.4, 18), CFrame.new(at(cx, 11.7, z0 - 8)), BLUE, SCENERY)
		for g = 0, 3 do
			local gx = cx - 21 + g * 14
			part("GarageDoor", V3(10, 8, 0.4), CFrame.new(at(gx, 4, z0 + 0.1)), (g % 2 == 0) and STEEL or CONCRETE_DARK, SCENERY)
			for k = 1, 3 do
				part("DoorSlat", V3(10, 0.3, 0.2), CFrame.new(at(gx, 1 + k * 2, z0 + 0.35)), INK, DECOR)
			end
			local num = part("GarageNumber", V3(3, 2, 0.2), CFrame.new(at(gx, 9.4, z0 + 0.35)), WHITE, DECOR)
			signText(num, tostring(10 + g * 11 + (sx > 0 and 3 or 0)), INK, Enum.NormalId.Back)
		end
		-- stacks of spare tyres and a fuel pump by the garages
		for k = 0, 2 do
			for h = 0, 2 do
				cylinder("SpareTyre", 1, 3, CFrame.new(at(cx + 26 * sx - k * 3.4 * sx, 0.5 + h * 1.05 - 1, z0 + 4)), INK, DECOR)
			end
		end
		part("FuelPump", V3(2, 4.6, 1.6), CFrame.new(at(cx - 26 * sx, 0.3, z0 + 3.5)), RED, DECOR)
		part("FuelPumpTop", V3(2.2, 0.8, 1.8), CFrame.new(at(cx - 26 * sx, 3, z0 + 3.5)), YELLOW, DECOR)
	end
end

local function buildTunnel()
	-- the tunnel under the pits, out to the fog (the way back to the lobby)
	local z0, z1 = -EDGE - 1, -TUNNEL_END
	local zc, len = (z0 + z1) / 2, z0 - z1
	part("TunnelFloor", V3(GAP * 2 + 4, 4, len + 2), CFrame.new(at(0, -2, zc)), CONCRETE_DARK)
	for _, sx in ipairs({ -1, 1 }) do
		part("TunnelWall", V3(2, 14, len), CFrame.new(at(sx * (GAP + 1), 7, zc)), CONCRETE)
		for k = 0, 3 do
			local light = part("TunnelLight", V3(0.4, 0.8, 3), CFrame.new(at(sx * GAP, 10, z0 - 5 - k * 7)), YELLOW, merge(DECOR, { Material = Mat.Neon }))
			pulse(light, 0.3, 0, 0.2)
		end
	end
	part("TunnelRoof", V3(GAP * 2 + 4, 2, len), CFrame.new(at(0, 15, zc)), CONCRETE_DARK)
	local arch = part("TunnelArch", V3(GAP * 2 + 8, 4, 2), CFrame.new(at(0, 16, z0 - 1)), RED)
	signText(arch, "TO THE TRACK", WHITE, Enum.NormalId.Back)
	-- the fog at the far end: the way out
	local fog = part("FogWall", V3(GAP * 2, 13, 0.6), CFrame.new(at(0, 6.5, z1 + 5)), FOG,
		{ Transparency = 0.45, CanCollide = false, CastShadow = false, Material = Mat.Neon })
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
	exit.ObjectText = "Tunnel"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(CFrame.new(at(0, 4, z1 + 8)), V3(GAP * 2, 8, 6), "Spire", "Leave")
	part("TunnelBack", V3(GAP * 2 + 4, 14, 2), CFrame.new(at(0, 7, z1 + 1)), INK)
	-- where you arrive: in the tunnel, looking out at the track
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, SPAWN_Z), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- The starting lights, the big screen, flags, the blimp
----------------------------------------------------------------------
local function buildGantry()
	-- the starting-light gantry over the start line, held out from the
	-- grandstand side (nothing stands on the track)
	local base = at(0, 0, EDGE + 5)
	part("GantryPost", V3(2, 18, 2), CFrame.new(base + V3(-3, 9, 0)), STEEL)
	part("GantryPost", V3(2, 18, 2), CFrame.new(base + V3(3, 9, 0)), STEEL)
	local beamLen = EDGE - INFIELD + 8
	part("GantryBeam", V3(3, 2.4, beamLen), CFrame.new(at(0, 17, EDGE + 5 - beamLen / 2)), STEEL)
	part("GantryBrace", V3(1, 1, 14), CFrame.new(at(0, 12, EDGE - 1)) * CFrame.Angles(math.rad(-40), 0, 0), STEEL, DECOR)
	-- five light pods, facing down the track both ways (dark until the countdown)
	for i = 1, 5 do
		local z = EDGE - 2 - i * (beamLen - 6) / 6
		part("LightPod", V3(3.6, 3.2, 3.6), CFrame.new(at(0, 14.6, z)), INK)
		local lamp = part("StartLight" .. i, V3(3.8, 2, 2), CFrame.new(at(0, 14.6, z)), RED_DARK, merge(DECOR, { Material = Mat.SmoothPlastic }))
		lamp:SetAttribute("StartLight", i)
	end
	-- checkered flags on poles either side of the line
	for _, z in ipairs({ INFIELD - 3, EDGE + 3 }) do
		if z > EDGE then
			part("LineFlagPole", V3(0.5, 10, 0.5), CFrame.new(at(-6, 5, z)), STEEL, DECOR)
			for i = 0, 3 do
				for j = 0, 2 do
					part("LineFlag", V3(0.2, 1, 1.4), CFrame.new(at(-6, 8.8 + j, z - 0.8 - i * 1.4)), ((i + j) % 2 == 0) and WHITE or INK, DECOR)
				end
			end
		end
	end
end

local function buildScreen()
	-- the giant screen at the east end, facing the track
	local p = at(SPINE + EDGE + 34, 0, 0)
	local cf = CFrame.lookAt(p, at(0, 0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		part("ScreenLeg", V3(3, 24, 3), cf * CFrame.new(sx * 16, 12, 0), STEEL, SCENERY)
	end
	part("ScreenFrame", V3(40, 22, 3), cf * CFrame.new(0, 34, 0), INK, SCENERY)
	local screen = part("Screen", V3(36, 18, 0.4), cf * CFrame.new(0, 34, -1.7), INK, SCENERY)
	signText(screen, "#57\nKA-VROOM!", YELLOW, Enum.NormalId.Front, INK)
	part("ScreenTop", V3(42, 2, 4), cf * CFrame.new(0, 46, 0), RED, SCENERY)
	-- a big trophy (the Golden Piston) on a plinth beside it
	local tp = at(SPINE + EDGE + 22, 0, 30)
	part("TrophyPlinth", V3(6, 4, 6), CFrame.new(tp + V3(0, 2, 0)), CONCRETE, SCENERY)
	cylinder("TrophyBase", 1.4, 4, CFrame.new(tp + V3(0, 4.7, 0)), GOLD, SCENERY)
	part("TrophyStem", V3(1.2, 3, 1.2), CFrame.new(tp + V3(0, 6.9, 0)), GOLD, SCENERY)
	part("TrophyCup", V3(4, 3.6, 4), CFrame.new(tp + V3(0, 10, 0)), GOLD, SCENERY)
	part("TrophyPiston", V3(2, 3, 2), CFrame.new(tp + V3(0, 13, 0)), YELLOW, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("TrophyHandle", V3(0.8, 2.4, 1.2), CFrame.new(tp + V3(sx * 2.6, 10.3, 0)), GOLD, SCENERY)
	end
end

local function buildBlimp()
	local p = at(-40, 110, 70)
	local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(20), 0)
	part("Blimp", V3(46, 14, 14), cf, CONCRETE, SCENERY)
	part("BlimpNose", V3(6, 10, 10), cf * CFrame.new(26, 0, 0), CONCRETE, SCENERY)
	part("BlimpTail", V3(6, 10, 10), cf * CFrame.new(-26, 0, 0), CONCRETE, SCENERY)
	part("BlimpTip", V3(3, 6, 6), cf * CFrame.new(-30, 0, 0), CONCRETE_DARK, SCENERY)
	part("BlimpFin", V3(8, 10, 1), cf * CFrame.new(-28, 7, 0), RED, SCENERY)
	part("BlimpFin", V3(8, 1, 10), cf * CFrame.new(-28, 0, 7), RED, SCENERY)
	part("BlimpFin", V3(8, 1, 10), cf * CFrame.new(-28, 0, -7), RED, SCENERY)
	part("BlimpCabin", V3(10, 3, 5), cf * CFrame.new(2, -8.5, 0), WHITE, SCENERY)
	local band = part("BlimpBand", V3(30, 6, 14.4), cf, RED, SCENERY)
	signText(band, "VROOM TV", WHITE, Enum.NormalId.Front)
	signText(band, "VROOM TV", WHITE, Enum.NormalId.Back)
end

----------------------------------------------------------------------
-- The desert beyond: mesas, cacti, a water tower, a billboard
----------------------------------------------------------------------
local function mesa(pos, w, h)
	local layers = 3 + math.floor(rnd() * 2)
	for k = 0, layers - 1 do
		local s = w * (1 - k * 0.14)
		local c = (k % 2 == 0) and ROCK or ROCK_LIGHT
		part("Mesa", V3(s, h / layers, s * (0.6 + rnd() * 0.3)), CFrame.new(pos + V3((rnd() - 0.5) * 4, (k + 0.5) * h / layers, (rnd() - 0.5) * 4)) * CFrame.Angles(0, rnd() * 0.5, 0), c, SCENERY)
	end
	part("MesaTop", V3(w * 0.5, 2, w * 0.35), CFrame.new(pos + V3(0, h + 1, 0)), ROCK_DARK, SCENERY)
end

local function cactus(pos, s)
	part("Cactus", V3(1.6 * s, 8 * s, 1.6 * s), CFrame.new(pos + V3(0, 4 * s, 0)), CACTUS, SCENERY)
	part("CactusArm", V3(3 * s, 1.2 * s, 1.2 * s), CFrame.new(pos + V3(1.6 * s, 4.5 * s, 0)), CACTUS, SCENERY)
	part("CactusArm", V3(1.2 * s, 3 * s, 1.2 * s), CFrame.new(pos + V3(2.6 * s, 6 * s, 0)), CACTUS, SCENERY)
	part("CactusArm", V3(2.6 * s, 1.2 * s, 1.2 * s), CFrame.new(pos + V3(-1.4 * s, 3.4 * s, 0)), CACTUS, SCENERY)
	part("CactusArm", V3(1.2 * s, 2.4 * s, 1.2 * s), CFrame.new(pos + V3(-2.2 * s, 4.6 * s, 0)), CACTUS, SCENERY)
end

local function buildDesert()
	for i = 0, 15 do
		local a = (i + rnd() * 0.5) / 16 * math.pi * 2
		local r = 330 + rnd() * 160
		mesa(at(math.sin(a) * r * 1.25, -1, math.cos(a) * r), 60 + rnd() * 60, 50 + rnd() * 70)
	end
	for _ = 1, 18 do
		local a = rnd() * math.pi * 2
		local r = 190 + rnd() * 120
		cactus(at(math.sin(a) * r * 1.2, -0.5, math.cos(a) * r), 0.8 + rnd() * 0.7)
	end
	for _ = 1, 24 do
		local a = rnd() * math.pi * 2
		local r = 180 + rnd() * 200
		local s = 2 + rnd() * 5
		part("DesertRock", V3(s * 1.4, s, s), CFrame.new(at(math.sin(a) * r * 1.2, s * 0.35 - 0.5, math.cos(a) * r)) * CFrame.Angles(0, rnd() * 3, 0),
			(rnd() < 0.5) and ROCK_LIGHT or SAND_DARK, SCENERY)
	end
	-- a water tower out west
	local wt = at(-230, 0, -60)
	for _, dx in ipairs({ -4, 4 }) do
		for _, dz in ipairs({ -4, 4 }) do
			part("TowerLeg", V3(1, 30, 1), CFrame.new(wt + V3(dx, 15, dz)), STEEL, SCENERY)
		end
	end
	cylinder("TowerTank", 14, 16, CFrame.new(wt + V3(0, 37, 0)), RED, SCENERY)
	part("TowerCap", V3(12, 3, 12), CFrame.new(wt + V3(0, 45.5, 0)), RED_DARK, SCENERY)
	-- a billboard by the road out east: his grinning face (almost)
	local bb = at(210, 0, -140)
	local bcf = CFrame.lookAt(bb, at(0, 0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		part("BillboardLeg", V3(1.5, 16, 1.5), bcf * CFrame.new(sx * 12, 8, 0), STEEL, SCENERY)
	end
	local board = part("Billboard", V3(34, 14, 1), bcf * CFrame.new(0, 22, 0), WHITE, SCENERY)
	signText(board, "KA-VROOM!\nSEE THE KING RACE", RED, Enum.NormalId.Front)
	-- a road running past, with a dashed line
	part("Road", V3(20, 0.3, 1200), CFrame.new(at(250, -0.3, 0)), ASPHALT, SCENERY)
	for k = -30, 30 do
		part("RoadLine", V3(0.6, 0.32, 8), CFrame.new(at(250, -0.28, k * 20)), YELLOW, DECOR)
	end
	-- a few small clouds
	for _ = 1, 8 do
		local a = rnd() * math.pi * 2
		local r = 200 + rnd() * 250
		local s = 14 + rnd() * 12
		part("Cloud", V3(s * 2, s * 0.4, s), CFrame.new(at(math.sin(a) * r, 120 + rnd() * 50, math.cos(a) * r)), WHITE, DECOR)
		part("Cloud", V3(s, s * 0.35, s * 0.7), CFrame.new(at(math.sin(a) * r + s * 0.2, 120 + rnd() * 50 + s * 0.35, math.cos(a) * r)), WHITE, DECOR)
	end
end

----------------------------------------------------------------------
-- The walls round the track, and the marks the boss will use
----------------------------------------------------------------------
local function wallPiece(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "SpeedwayWall")
	return w
end

local function buildBounds()
	local H = 60
	-- the straights (the north one has the tunnel's gap)
	wallPiece(CFrame.new(at(0, H / 2, EDGE + 1)), V3(SPINE * 2 + 1, H, 2))
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * GAP, sx * (SPINE + 0.5)
		wallPiece(CFrame.new(at((x0 + x1) / 2, H / 2, -EDGE - 1)), V3(math.abs(x1 - x0), H, 2))
	end
	-- the round ends
	for _, sx in ipairs({ -1, 1 }) do
		local N = 28
		for i = 0, N - 1 do
			local a = (i + 0.5) / N * math.pi
			local o = V3(sx * math.sin(a), 0, math.cos(a))
			local p = at(sx * SPINE, H / 2, 0) + o * (EDGE + 1)
			wallPiece(CFrame.lookAt(p, p + o), V3(2 * (EDGE + 1) * math.sin(math.pi / N / 2) + 0.8, H, 2))
		end
	end
	-- the tunnel's sides are its own walls (see buildTunnel); close the corners
	for _, sx in ipairs({ -1, 1 }) do
		wallPiece(CFrame.new(at(sx * (GAP + 2), H / 2, -EDGE - 1.5)), V3(3, H, 3))
	end
	-- Where Revvington waits: on the start line, facing down the track
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, MID)))
	home:SetAttribute("Floor", 5)
	home:SetAttribute("Facing", V3(1, 0, 0))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function SpeedwayBuilder.Build()
	local old = Workspace:FindFirstChild("SpeedwayArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "SpeedwayArena"
	seed = 20260928 -- (the same "random" every time it's built)

	local pieces = {
		{ "Track", buildTrack },
		{ "Tyre wall", buildWall },
		{ "Grandstands", buildStands },
		{ "Pits", buildPits },
		{ "Tunnel", buildTunnel },
		{ "Start lights", buildGantry },
		{ "Big screen", buildScreen },
		{ "Blimp", buildBlimp },
		{ "Desert", buildDesert },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[SpeedwayBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 5)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("Spine", SPINE) -- the track's middle line runs from x = -Spine to +Spine
	m:SetAttribute("Edge", EDGE) -- the track's outside edge, that far from the line
	m:SetAttribute("Infield", INFIELD) -- the grass in the middle
	m.Parent = Workspace
	if failed == 0 then
		print("[SpeedwayBuilder] Piston Speedway built OK")
	end
	return m
end

SpeedwayBuilder.Center = CENTER
SpeedwayBuilder.Spine = SPINE
SpeedwayBuilder.Edge = EDGE
SpeedwayBuilder.Infield = INFIELD

return SpeedwayBuilder
