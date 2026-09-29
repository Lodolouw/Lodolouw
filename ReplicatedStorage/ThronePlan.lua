--[[
	ThronePlan  (ModuleScript, parent: ReplicatedStorage, name: "ThronePlan")

	The shape of the Throne Summit (floor 10, King Gavelgrunt's arena), so
	the arena (ServerScriptService/ThroneBuilder), his moves
	(ServerScriptService/Bosses/Gavelgrunt) and every player's screen
	(ReplicatedStorage/BossBodies/Gavelgrunt) all agree exactly.

	Everything is measured from the middle of the courtyard (x, z studs;
	+Z is south: the door you come in by; the throne is at the north end).
	  Radius        the round stone courtyard you fight on
	  Pillars       four stone pillars you can hide behind (his big moves
	                break them; all that are left crumble when round 3 begins)
	  Podiums       three low stone podiums round the edge (stand on one when
	                he finds you GUILTY: the gavel hits you far softer there)
	  tiles()       the floor's big square flagstones (the EARTHQUAKE lights
	                some up: only those are safe)
	  Throne        where his throne stands (he throws it in round 3; he
	                sleeps sitting on it)
	  Spawn         where you arrive
]]

local ThronePlan = {}

ThronePlan.Radius = 62
ThronePlan.Wall = 66 -- the invisible wall round the courtyard
ThronePlan.DoorHalf = 7 -- the gate in the south wall is this wide each way

ThronePlan.PillarRadius = 3.2
ThronePlan.PillarHeight = 22
-- (at the four diagonals, 34 studs out)
ThronePlan.Pillars = {
	Vector3.new(24, 0, -24),
	Vector3.new(24, 0, 24),
	Vector3.new(-24, 0, 24),
	Vector3.new(-24, 0, -24),
}

ThronePlan.PodiumRadius = 4
ThronePlan.PodiumHeight = 1.2
ThronePlan.Podiums = {
	Vector3.new(46, 0, 0),
	Vector3.new(-40, 0, 26),
	Vector3.new(-40, 0, -26),
}

ThronePlan.Throne = Vector3.new(0, 0, -52)
ThronePlan.Spawn = Vector3.new(0, 0, 54)
ThronePlan.Home = Vector3.new(0, 0, -14) -- where he fights from, facing the door

-- HIS THRONE is built ThroneScale times its drawing's size (he's huge: so is
-- his chair). He sleeps sitting on it - at SeatAt, on a cushion SeatHeight
-- up - and leaps down to Home when he wakes. For the Throne Toss he lands at
-- ThroneFront (just clear of its steps) to rip it out of the floor.
ThronePlan.ThroneScale = 1.45
ThronePlan.SeatHeight = 14.5
ThronePlan.SeatAt = Vector3.new(0, 0, -48.5)
ThronePlan.ThroneFront = Vector3.new(0, 0, -30)

-- THE FLAGSTONES: a grid of Cell-stud squares; the ones whose middle is at
-- least Cell/2 inside the courtyard's edge. Returns a list of { x, z }.
ThronePlan.Cell = 12
function ThronePlan.tiles()
	local list = {}
	local c = ThronePlan.Cell
	local n = math.floor(ThronePlan.Radius / c) + 1
	for i = -n, n do
		for j = -n, n do
			local x, z = i * c, j * c
			if math.sqrt(x * x + z * z) <= ThronePlan.Radius - c / 2 then
				table.insert(list, { x, z })
			end
		end
	end
	return list
end

-- is (x, z) - an offset from the middle - on the flagstone whose middle is (tx, tz)?
function ThronePlan.onTile(x, z, tx, tz, margin)
	local h = ThronePlan.Cell / 2 + (margin or 0)
	return math.abs(x - tx) <= h and math.abs(z - tz) <= h
end

-- is (x, z) on a podium? (which one, or nil)
function ThronePlan.podiumAt(x, z, margin)
	for i, p in ipairs(ThronePlan.Podiums) do
		local dx, dz = x - p.X, z - p.Z
		if math.sqrt(dx * dx + dz * dz) <= ThronePlan.PodiumRadius + (margin or 0) then
			return i
		end
	end
	return nil
end

-- the pillar a spot is inside or touching (with `margin`), or nil
function ThronePlan.pillarAt(x, z, margin)
	for i, p in ipairs(ThronePlan.Pillars) do
		local dx, dz = x - p.X, z - p.Z
		if math.sqrt(dx * dx + dz * dz) <= ThronePlan.PillarRadius + (margin or 0) then
			return i
		end
	end
	return nil
end

-- the broken pillars, as a string of 0s and 1s (one per pillar), and back
function ThronePlan.encodeBroken(broken)
	local s = ""
	for i = 1, #ThronePlan.Pillars do
		s = s .. (broken[i] and "1" or "0")
	end
	return s
end
function ThronePlan.decodeBroken(s)
	local out = {}
	s = type(s) == "string" and s or ""
	for i = 1, #ThronePlan.Pillars do
		out[i] = string.sub(s, i, i) == "1"
	end
	return out
end

return ThronePlan
