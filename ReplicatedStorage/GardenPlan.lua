--[[
	GardenPlan  (ModuleScript, parent: ReplicatedStorage, name: "GardenPlan")

	The shape of Petalina's greenhouse garden (floor 8), and the sums her
	attacks share, in one place - so the arena (GreenhouseBuilder), her moves
	(ServerScriptService/Bosses/Petalina) and every player's screen
	(ReplicatedStorage/BossBodies/Petalina) all agree exactly.

	THE GARDEN, seen from above (distances are from her stem, in the middle):
	  * her MOUND: a round mound of soil and roots, out to Mound
	  * the INNER PATH: a paved ring round the mound, out to Inner
	  * four STRAIGHT PATHS, PathHalf * 2 wide, running out from the inner
	    path to the edge: south (to the door), east, north and west
	  * the OUTER PATH: a paved ring from Outer out to the fight's Edge
	  * the greenhouse itself is square (its glass walls Walls out each way):
	    the round garden fits inside it, with planters in the corners
	  * the FLOWER BEDS: everything else - four big quarter-rings of soil
	    between the paths, raised a little (BedUp) above the paving. Each is
	    built from strips Step studs deep, so their curved edges step like
	    pixels (GardenPlan.bedStrips lists them). In round 2 thorns grow all
	    over them: then the paths (and her mound) are the only safe ground.

	THE PETAL BOOMERANG: a petal flies out in a loop and comes back. Its path
	is an oval from her stem out to `far` (past you) and back, bulging out to
	one side by `width` on the way out and the other side on the way back.
	GardenPlan.petalPoint gives where it is `s` of the way round (0 to 1), and
	GardenPlan.petalTime how long the whole loop takes at a speed.
]]

local GardenPlan = {}

GardenPlan.Mound = 7 -- her mound of roots
GardenPlan.Inner = 17 -- the inner ring path runs from the mound out to here
GardenPlan.Outer = 54 -- the outer ring path starts here
GardenPlan.Edge = 66 -- the fight's edge (an invisible wall: nobody gets past this)
GardenPlan.Walls = 72 -- the greenhouse is square: its glass walls stand this far out each way
GardenPlan.PathHalf = 6 -- half the width of each straight path
GardenPlan.BedUp = 0.4 -- the flower beds' soil stands this far above the paving
GardenPlan.Step = 2 -- how deep each strip of a flower bed is

-- One strip of the beds: between z0 and z0 + Step away from the east-west
-- path's middle line (and mirrored to all four sides), a bed runs from x0 to
-- x1 away from the north-south path's middle line. nil if there's no bed
-- there. (The strict ends: nowhere on the strip pokes into a path.)
function GardenPlan.strip(z0)
	local P = GardenPlan
	local z1 = z0 + P.Step
	local x0 = math.max(P.PathHalf, math.sqrt(math.max(0, P.Inner * P.Inner - z0 * z0)))
	local x1 = math.sqrt(math.max(0, P.Outer * P.Outer - z1 * z1))
	if x1 - x0 < 0.5 then
		return nil
	end
	return x0, x1
end

-- every strip of every bed: { z0, z1, x0, x1 } measured on one quarter
-- (a bed is the same in all four quarters, mirrored)
function GardenPlan.bedStrips()
	local P = GardenPlan
	local list = {}
	local z0 = P.PathHalf
	while z0 < P.Outer do
		local x0, x1 = P.strip(z0)
		if x0 then
			table.insert(list, { z0 = z0, z1 = z0 + P.Step, x0 = x0, x1 = x1 })
		end
		z0 = z0 + P.Step
	end
	return list
end

-- Is the spot (dx, dz) from her stem safe ground - a path or her mound -
-- rather than a flower bed? (Exactly where the arena's beds are.)
function GardenPlan.safe(dx, dz)
	local P = GardenPlan
	local ax, az = math.abs(dx), math.abs(dz)
	if ax <= P.PathHalf or az <= P.PathHalf then
		return true
	end
	local z0 = P.PathHalf + math.floor((az - P.PathHalf) / P.Step) * P.Step
	local x0, x1 = P.strip(z0)
	return not (x0 and ax >= x0 and ax <= x1)
end

-- The middle of the nearest path to (dx, dz): the spot a seed aimed at
-- someone standing there lands on, when it has to land on a path.
function GardenPlan.nearestSafe(dx, dz)
	if GardenPlan.safe(dx, dz) then
		return dx, dz
	end
	local r = math.sqrt(dx * dx + dz * dz)
	-- the candidates: onto the inner ring, onto the outer ring, or sideways
	-- onto whichever straight path is closest
	local best, bx, bz = math.huge, dx, dz
	local function try(x, z)
		local d = (x - dx) ^ 2 + (z - dz) ^ 2
		if d < best then
			best, bx, bz = d, x, z
		end
	end
	if r > 0 then
		local inR, outR = GardenPlan.Inner - 1, GardenPlan.Outer + 1
		try(dx / r * inR, dz / r * inR)
		try(dx / r * outR, dz / r * outR)
	end
	local edge = GardenPlan.PathHalf - 1
	try(math.clamp(dx, -edge, edge), dz)
	try(dx, math.clamp(dz, -edge, edge))
	return bx, bz
end

-- THE PETAL BOOMERANG'S LOOP. origin = her stem (on the floor), far = the
-- far end of the loop (on the floor), side = 1 or -1 (which way it bulges
-- out first), width = how far it bulges. s = 0 at her, 0.5 at the far end,
-- 1 back at her.
function GardenPlan.petalPoint(origin, far, side, width, s)
	local along = far - origin
	along = Vector3.new(along.X, 0, along.Z)
	local length = along.Magnitude
	local dir = length > 1e-3 and along / length or Vector3.new(0, 0, 1)
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local a = s * math.pi * 2
	return origin + dir * (length * (1 - math.cos(a)) / 2) + across * (side * width * math.sin(a))
end

-- how long the loop takes at `speed` studs a second (the oval's length:
-- Ramanujan's sum for the edge of an ellipse)
function GardenPlan.petalTime(length, width, speed)
	local a, b = math.max(length / 2, 0.5), math.max(width, 0.5)
	local perimeter = math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)))
	return perimeter / math.max(speed, 1)
end

-- THE FACE STRETCH: where her head is `u` of the way through shooting out
-- (0 to 1). It dives from high over her stem (restHeight up) down to low
-- over the start of the lane (6 studs out), then races along the lane,
-- low over the floor (lowHeight up), to `finish` (on the floor).
GardenPlan.DIVE = 0.35 -- (the share of the time the dive takes)
function GardenPlan.headPoint(base, restHeight, finish, lowHeight, u)
	local flatOff = Vector3.new(finish.X - base.X, 0, finish.Z - base.Z)
	local dir = flatOff.Magnitude > 1e-3 and flatOff.Unit or Vector3.new(0, 0, 1)
	local top = base + Vector3.new(0, restHeight, 0)
	local laneStart = Vector3.new(base.X, finish.Y, base.Z) + dir * 6 + Vector3.new(0, lowHeight, 0)
	u = math.clamp(u, 0, 1)
	if u < GardenPlan.DIVE then
		return top:Lerp(laneStart, u / GardenPlan.DIVE)
	end
	return laneStart:Lerp(finish + Vector3.new(0, lowHeight, 0), (u - GardenPlan.DIVE) / (1 - GardenPlan.DIVE))
end

return GardenPlan
