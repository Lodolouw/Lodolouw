--[[
	CarPath  (ModuleScript, parent: ReplicatedStorage, name: "CarPath")

	How Speedy Revvington drives - the sums, shared by the server
	(ServerScriptService/Bosses/Revvington.lua) and every player's screen
	(ReplicatedStorage/BossBodies/Revvington.lua), so the car is drawn exactly
	where he really is at every moment, however fast he goes and whatever
	your ping.

	He never just "moves": everything he does is a SEGMENT that starts at a
	moment on the server's clock and lasts `dur` seconds:
	  Line  from `a` to `b` (driving forward - or backward, `back`)
	  Arc   round the centre `a`: `b` = (radius, start angle, sweep angle)
	  Spin  on the spot at `a`, turning: `b` = (start heading, turn), sliding
	        `c` studs as he goes (a skid)
	and `ease` says how the speed changes along it: "lin" steady, "in"
	speeding up, "out" slowing down, "io" both.
	Angles are headings: 0 faces +Z, and a heading h faces (sin h, 0, cos h).

	The server writes the segment onto his model as attributes (SegK, SegT0,
	SegDur, SegA, SegB, SegC, SegE, then SegId last, so the rest is in place
	when a screen sees it); CarPath.read gets it back.
]]

local CarPath = {}

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

-- how far along a segment he is, from how far through its time (both 0-1)
function CarPath.ease(kind, u)
	u = clamp(u, 0, 1)
	if kind == "in" then
		return u * u
	elseif kind == "out" then
		return 1 - (1 - u) * (1 - u)
	elseif kind == "io" then
		return u * u * (3 - 2 * u)
	end
	return u
end

-- a heading as a direction, and back
function CarPath.dirOf(h)
	return Vector3.new(math.sin(h), 0, math.cos(h))
end

function CarPath.angleOf(v)
	return math.atan2(v.X, v.Z)
end

-- the shortest turn from heading `from` to heading `to` (-pi..pi)
function CarPath.turnBetween(from, to)
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- Where the segment puts him at server time `t`: his position (on the floor
-- plane: its Y is whatever the segment's points had), the way he faces (a
-- flat unit direction) and how far through the segment's time he is (0-1).
function CarPath.eval(seg, t)
	local u = clamp((t - seg.t0) / math.max(seg.dur, 1e-3), 0, 1)
	local e = CarPath.ease(seg.ease, u)
	local kind = seg.kind
	if kind == "Line" then
		local d = seg.b - seg.a
		local flatD = Vector3.new(d.X, 0, d.Z)
		local dir = flatD.Magnitude > 1e-3 and flatD.Unit or CarPath.dirOf(seg.h or 0)
		if seg.back then
			dir = -dir
		end
		return seg.a:Lerp(seg.b, e), dir, u
	elseif kind == "Arc" then
		local r, a0, sweep = seg.b.X, seg.b.Y, seg.b.Z
		local a = a0 + sweep * e
		local pos = seg.a + Vector3.new(math.sin(a), 0, math.cos(a)) * r
		local s = (sweep >= 0) and 1 or -1
		return pos, Vector3.new(math.cos(a), 0, -math.sin(a)) * s, u
	end
	-- Spin (and anything unknown: standing still)
	local h0, turn = seg.b.X, seg.b.Y
	local slide = seg.c or Vector3.new()
	return seg.a + slide * CarPath.ease("out", u), CarPath.dirOf(h0 + turn * e), u
end

-- the moment a segment ends (server time)
function CarPath.endsAt(seg)
	return seg.t0 + seg.dur
end

-- The segment published on his model (nil if there's none yet)
function CarPath.read(model)
	local k = model:GetAttribute("SegK")
	if type(k) ~= "string" then
		return nil
	end
	local a, b = model:GetAttribute("SegA"), model:GetAttribute("SegB")
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return nil
	end
	local c = model:GetAttribute("SegC")
	return {
		kind = k,
		t0 = model:GetAttribute("SegT0") or 0,
		dur = model:GetAttribute("SegDur") or 0,
		a = a,
		b = b,
		c = typeof(c) == "Vector3" and c or Vector3.new(),
		ease = model:GetAttribute("SegE") or "lin",
		back = model:GetAttribute("SegBack") == true,
		id = model:GetAttribute("SegId") or 0,
	}
end

-- Publishes a segment on his model for every screen (the server does this)
function CarPath.write(model, seg, id)
	model:SetAttribute("SegK", seg.kind)
	model:SetAttribute("SegT0", seg.t0)
	model:SetAttribute("SegDur", seg.dur)
	model:SetAttribute("SegA", seg.a)
	model:SetAttribute("SegB", seg.b)
	model:SetAttribute("SegC", seg.c or Vector3.new())
	model:SetAttribute("SegE", seg.ease or "lin")
	model:SetAttribute("SegBack", seg.back == true)
	model:SetAttribute("SegId", id) -- last, so the rest is in place when a screen sees it
end

return CarPath
