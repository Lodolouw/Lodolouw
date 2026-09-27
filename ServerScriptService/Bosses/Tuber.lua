--[[
	Tuber  (ModuleScript, parent: ServerScriptService > Bosses, name: "Tuber")

	Floor 2's boss (Config.Bosses[2]). He has two health bars and two
	completely different fights.

	ROUND 1: TUBER, a chubby, potato-shaped little stack of cactus with a
	flower on his head. Easy on purpose - long warnings, long breaks - so you
	think he's a joke:
	  WOBBLE BONK    leans back... and flops his head forward (step aside)
	  CLUMSY TOPPLE  falls flat along a lane like a tree, then lies there
	                 flailing (free hits) and struggles back up
	  NEEDLE SNEEZE  "ah... ah... ACHOO!": a ring of needles (jump or roll it)
	  BOUNCE STOMP   springs up and lands on the red circle
	  SPLIT!         pops into three cactus balls that spin-dash at you one
	                 after another (each bounces once off a rock or the edge),
	                 then sit there dizzy (free hits - punch any of them, they
	                 share his health) and hop back into a stack

	THE POWER-UP (his first bar runs out): he flops over and his flower
	wilts... then every cactus in the desert rips out of the ground and flies
	to him, and he rebuilds himself into THE BRUTE, THE CACTUS KING - a giant
	cactus golem. TUBER's letters swap places into BRUTE, and THE slams down
	next to it. (BossService's break: BreakTime seconds, and he can't be hurt
	while it plays. BossBodies/Tuber draws all of it.)

	ROUND 2: THE BRUTE, who fights from a distance. His goal is to keep you
	away; yours is to break through his cactus and catch him:
	  ROOT HOP       you come close: he rips his roots up and leaps away
	                 across the arena (it has to recharge - HopAt says when)
	  CORNERED       you reach him before it's recharged: he panics (free
	                 hits!), blasts you back with a SHOVE BURST, and escapes
	  STUNNED        break the last of his walls and turrets: he's out of
	                 cactus for a moment (free hits)
	  NEEDLE VOLLEY  a red cone, then three fans of needles
	  DESERT RAIN    cactus balls spat into the sky land on red circles
	  SPINE LANCE    charges, locks on, fires a giant spike across the arena
	  CACTUS WALL    a wall bursts up between you and him: go round it, or
	                 punch its glowing weak spot (2 punches)
	  NEEDLE TURRETS little cactus towers that shoot at you (2 punches each)
	  BALL HERD      spinning cactus balls roll in from the edge, bouncing
	  PRICKLY BUDDIES little minions that waddle after you and pop into
	                 needles (1 punch each)
	  QUICKSAND      swirling sand between you and him drags you in
	  RAGE           once, low on health: he roars; more of everything, and
	                 his walls creep toward you

	Published on his model (besides BossService's own): Form ("Stack" or
	"Brute"), HopAt (when his hop is ready again), Rage. Each move publishes
	its spots with setSlot (see each one). The things he leaves around the
	arena - walls, turrets, buddies, quicksand - live in Workspace.TuberProps,
	each with its own attributes (see "The cactus he leaves around"); the
	punchable ones are CombatTargets with their own small health.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, hitArea, targetPosition, healthShare, knockbackFrom
local pickTarget, breakShell, stepMovement, stepWaves, stepPuddles, place
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

local STACK = 3.2 -- how tall each of little Tuber's three segments is
local WALL_BLOCK = 2.2 -- (half a wall segment: how close a ball or needle gets to one)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a pair { normal, rage } for how angry he is (a plain number stays as it is)
local function byRage(E, v)
	if type(v) == "table" then
		return (E.rage and v[2]) or v[1]
	end
	return v
end

local function ground(E)
	return Vector3.new(E.pos.X, E.floorY, E.pos.Z)
end

local function atFloor(E, p)
	return Vector3.new(p.X, E.floorY, p.Z)
end

-- a flat direction turned round the vertical by `a` radians
local function rotateY(v, a)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c + v.Z * s, 0, -v.X * s + v.Z * c)
end

-- the point on the segment a-b nearest to p (on the ground plane), and how far
local function segNearest(a, b, p)
	local ab = flat(b - a)
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return a, flat(p - a).Magnitude
	end
	local u = math.clamp(flat(p - a):Dot(ab) / len2, 0, 1)
	local q = a + (b - a) * u
	return q, flat(p - q).Magnitude
end

-- how far from `from` along `dir` before leaving the circle of radius `r` round `c`
local function toEdge(c, from, dir, r)
	local o = flat(from - c)
	local b = o:Dot(dir)
	local cc = o:Dot(o) - r * r
	local disc = b * b - cc
	if disc < 0 then
		return 0
	end
	return math.max(0, -b + math.sqrt(disc))
end

-- how far along a ray it first touches the circle (c, r) from outside, or nil
local function rayCircle(from, dir, c, r)
	local o = flat(from - c)
	local b = o:Dot(dir)
	local cc = o:Dot(o) - r * r
	if cc <= 0 or b >= 0 then
		return nil -- (inside it already, or heading away)
	end
	local disc = b * b - cc
	if disc < 0 then
		return nil
	end
	return -b - math.sqrt(disc)
end

-- a spot kept inside the circle of radius `r` round the arena's middle
local function inside(E, p, r)
	local off = flat(p - E.center)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.center.X + off.X, E.floorY, E.center.Z + off.Z)
end

-- a spot moved out of every rock, `pad` studs clear of it
local function clearOfRocks(E, p, pad)
	for _, rk in ipairs(E.rocks) do
		local off = flat(p - rk.center)
		local need = rk.radius + pad
		if off.Magnitude < need then
			p = rk.center + unitOr(off, Vector3.new(0, 0, 1)) * need
		end
	end
	return atFloor(E, p)
end

-- How high something is `e` seconds into a hop of `air` seconds: up fast
-- (slowing at the top) for `rise` of it, then down faster and faster.
-- (BossBodies/Tuber draws his hops with exactly the same sum.)
local function arcHeight(e, air, rise, height)
	if e <= 0 or e >= air then
		return 0
	end
	local up = air * rise
	if e < up then
		local u = e / up
		return height * (1 - (1 - u) * (1 - u))
	end
	local v = (e - up) / math.max(air - up, 1e-3)
	return height * (1 - v * v)
end

local function airHeight(E, t)
	local arc = E.arc
	if not arc then
		return 0
	end
	return arcHeight(t - arc.t0, arc.air, arc.rise, arc.height)
end

-- the Brute's share of his own bar (his second bar is the bottom PhaseAt of his health)
local function bruteShare(E)
	local max = E.model:GetAttribute("MaxHealth") or 1
	local line = math.max(1, math.floor(max * E.def.PhaseAt))
	return (E.model:GetAttribute("Health") or 0) / line
end

----------------------------------------------------------------------
-- The arena: its rocks, and the paths things roll and fly along
----------------------------------------------------------------------
local function findRocks(E)
	local list = {}
	for _, rm in ipairs(CollectionService:GetTagged("DesertRock")) do
		if rm:GetAttribute("Floor") == E.floor then
			local core = rm:FindFirstChild("RockCore") or rm.PrimaryPart
			if core then
				table.insert(list, {
					center = atFloor(E, core.Position),
					radius = rm:GetAttribute("Radius") or 5,
					index = rm:GetAttribute("Index") or (#list + 1),
				})
			end
		end
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

-- the nearest point of a cactus wall's line, and how far
local function wallNearest(w, p)
	local best, bestD = nil, math.huge
	local half = w.along * (w.seg / 2)
	for i, c in ipairs(w.segNow) do
		if w.keep[i] then
			local q, d = segNearest(c - half, c + half, p)
			if d < bestD then
				best, bestD = q, d
			end
		end
	end
	return best or p, bestD
end

-- The first thing a ray from `from` along `dir` runs into within `len`: a
-- rock, a standing cactus wall (unless noWalls), or (edge) the rim of the
-- arena where rolling things bounce. Returns how far, and the way back out
-- (a bounce's normal) - or nil if nothing's in the way.
local function firstHit(E, from, dir, len, pad, edge, noWalls)
	local bestT, bestN = nil, nil
	for _, rk in ipairs(E.rocks) do
		local t = rayCircle(from, dir, rk.center, rk.radius + pad)
		if t and t <= len and (not bestT or t < bestT) then
			bestT, bestN = t, unitOr(flat(from + dir * t - rk.center), -dir)
		end
	end
	if not noWalls then
		for _, w in ipairs(E.propList) do
			if w.kind == "Wall" and w.risen and not w.gone then
				for i, c in ipairs(w.segNow) do
					if w.keep[i] then
						local t = rayCircle(from, dir, c, WALL_BLOCK + pad)
						if t and t <= len and (not bestT or t < bestT) then
							bestT, bestN = t, unitOr(flat(from + dir * t - c), -dir)
						end
					end
				end
			end
		end
	end
	if edge then
		local t = toEdge(E.center, from, dir, E.edgeR)
		if t <= len and (not bestT or t < bestT) then
			bestT, bestN = t, unitOr(flat(E.center - (from + dir * t)), -dir)
		end
	end
	return bestT, bestN
end

-- how far a needle gets before a rock or a wall stops it
local function blockedAt(E, from, dir, len, pad)
	local t = firstHit(E, from, dir, len, pad, false)
	return t and math.max(0, t) or len
end

-- A rolling ball's path: from `from` along `dir`, bouncing off rocks, walls
-- and the rim (at most `bounces` times), `len` studs long in all. Returns
-- the corners: start, each bounce, end.
local function tracePath(E, from, dir, len, bounces, pad)
	local pts = { atFloor(E, from) }
	local p, d, left = pts[1], dir, len
	for b = 0, bounces do
		local t, n = firstHit(E, p, d, left, pad, true)
		if not t then
			pts[#pts + 1] = p + d * left
			break
		end
		t = math.max(t, 0)
		local q = p + d * t
		pts[#pts + 1] = q
		left = left - t
		if b == bounces or left < 1 then
			break
		end
		d = unitOr(d - n * (2 * d:Dot(n)), -d)
		p = q + d * 0.01
	end
	return pts
end

local function pathLength(pts)
	local n = 0
	for i = 2, #pts do
		n = n + flat(pts[i] - pts[i - 1]).Magnitude
	end
	return n
end

-- where along a path something is, `dist` studs from its start
local function pointAlong(pts, dist)
	for i = 2, #pts do
		local seg = flat(pts[i] - pts[i - 1]).Magnitude
		if dist <= seg or i == #pts then
			local u = seg > 1e-3 and math.clamp(dist / seg, 0, 1) or 1
			return pts[i - 1]:Lerp(pts[i], u)
		end
		dist = dist - seg
	end
	return pts[#pts]
end

----------------------------------------------------------------------
-- Hitting players
----------------------------------------------------------------------
-- whoever's in front of him, within `reach` and `arcDeg` degrees either side of dead ahead
local function hitFront(E, reach, arcDeg, damage, knockback)
	local half = math.rad(arcDeg / 2)
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local off = flat(root.Position - E.pos)
			local d = off.Magnitude
			if d <= reach + PLAYER_RADIUS
				and (d < 2 or math.acos(math.clamp(off.Unit:Dot(E.facing), -1, 1)) <= half) then
				CombatService.DamagePlayer(p, damage, E.pos, knockbackFrom(E.pos, root, knockback))
			end
		end
	end
end

-- whoever's on a strip from `a` to `b`, `width` wide (thrown off it, sideways)
local function hitStrip(E, a, b, width, damage, knockback)
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local q, d = segNearest(a, b, root.Position)
			if d <= width / 2 + PLAYER_RADIUS then
				CombatService.DamagePlayer(p, damage, q, knockbackFrom(q, root, knockback))
			end
		end
	end
end

-- a ring of needles (or sand) spreading out along the ground (BossService's
-- shock rings: jump it, or roll through it)
local function addRing(E, origin, start, reach, speed, thickness, height, damage, knockback)
	table.insert(E.waves, {
		origin = atFloor(E, origin), start = start, t0 = now(), speed = speed, reach = reach,
		thickness = thickness, height = height, damage = damage, knockback = knockback,
		lastR = start, hit = {},
	})
end

-- Something flying or rolling along a path (a needle, a cactus ball, the
-- lance): along `pts` from time `t0` at `speed`. Everyone it passes over
-- (and isn't jumping clear of) is hit once. `owner`: a turret whose shot it
-- is (a broken turret's shot that hasn't flown yet never flies).
local function addShot(E, pts, t0, speed, radius, height, damage, knockback, struck, owner)
	table.insert(E.shots, {
		pts = pts, len = pathLength(pts), t0 = t0, speed = speed, radius = radius, height = height,
		damage = damage, knockback = knockback, struck = struck or {}, done = 0, owner = owner,
	})
end

local function stepShots(E, t)
	if #E.shots == 0 then
		return
	end
	local list = fightersIn(E)
	for i = #E.shots, 1, -1 do
		local s = E.shots[i]
		local gone = (t - s.t0) * s.speed
		if s.owner and s.owner.gone and gone < 0 then
			table.remove(E.shots, i)
		elseif gone >= 0 then
			local upTo = math.min(gone, tonumber(s.len) or 0)
			local a, b = pointAlong(s.pts, s.done), pointAlong(s.pts, upTo)
			for _, p in ipairs(list) do
				if not s.struck[p] then
					local root = rootOf(p)
					if root and root.Position.Y - (E.floorY + STAND_HEIGHT) < s.height * 0.8 then
						local q, d = segNearest(a, b, root.Position)
						if d <= s.radius + PLAYER_RADIUS then
							s.struck[p] = true -- (rolling through it counts: it can't come back for you)
							CombatService.DamagePlayer(p, s.damage, q, knockbackFrom(q, root, s.knockback))
						end
					end
				end
			end
			s.done = upTo
			if gone >= s.len then
				table.remove(E.shots, i)
			end
		end
	end
end

-- cactus balls falling out of the sky (the desert rain): each lands at `at`
local function stepDrops(E, t)
	for i = #E.drops, 1, -1 do
		local d = E.drops[i]
		if t >= d.at then
			table.remove(E.drops, i)
			hitArea(E, d.pos, d.radius, d.damage, d.knockback)
		end
	end
end

----------------------------------------------------------------------
-- The cactus he leaves around (round 2)
----------------------------------------------------------------------
-- Everything lives in Workspace.TuberProps (never inside his own model: that
-- would confuse the lock-on camera and the health bars). Each one has Kind,
-- Id and Floor, plus its own:
--   "Wall"   a Model: A and B (its two ends, on the ground), N (how many
--            segments), Keep (a "1"/"0" per segment: a rock can leave a
--            gap), Weak (which segment is the weak spot), Warn (when its red
--            line shows), T0 (when it bursts up), T1 (when it crumbles),
--            Slide (how fast it creeps, studs a second - rage) and SlideFor
--            (for how long). Its PrimaryPart "Weak" is the punchable weak
--            spot; "Block1".. are the invisible blocks you can't walk through.
--   "Turret" a Model: Born, Grow (seconds it takes to sprout). Each shot:
--            ShotFrom, ShotTo, ShotWarn (the red line), ShotAt (it fires), ShotId.
--   "Buddy"  a Model (its PrimaryPart "Hit" is where it is - it walks):
--            Born, Land (when it lands from its hop off him), From, To,
--            PuffAt (it's about to pop).
--   "Sand"   a Folder: C (its middle), R (how big), Warn, T0 (it starts
--            dragging), T1 (it's gone).
-- When one ends, EndKind says how ("Broken" by a punch, "Wither", "Pop" or
-- "Gone" when the fight resets) and EndAt when; it's removed a moment later.
local function propFolder(E)
	if not (E.folder and E.folder.Parent) then
		local f = Instance.new("Folder")
		f.Name = "TuberProps"
		f.Parent = Workspace
		E.folder = f
	end
	return E.folder
end

local function newId(E)
	E.propId = (E.propId or 0) + 1
	return E.propId
end

local function hitbox(name, size, cf, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function count(E, kind)
	local n = 0
	for _, q in ipairs(E.propList) do
		if q.kind == kind and not q.gone then
			n = n + 1
		end
	end
	return n
end

-- the end of one: every screen sees EndKind and plays it, and it's taken
-- away a moment later (you can walk through a wall straight away)
local function endProp(_E, prop, kind)
	if prop.gone then
		return
	end
	prop.gone = true
	if prop.puddle then
		prop.puddle.untilT = 0 -- (quicksand stops dragging at once)
	end
	local inst = prop.model or prop.folder
	if not inst then
		return
	end
	if prop.model then
		CollectionService:RemoveTag(prop.model, "CombatTarget")
	end
	for _, b in ipairs(prop.blocks or {}) do
		b.CanCollide = false
		b.CanQuery = false
	end
	inst:SetAttribute("EndKind", kind)
	inst:SetAttribute("EndAt", now())
	task.delay(0.8, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end

local function clearProps(E, kind)
	for _, q in ipairs(E.propList or {}) do
		endProp(E, q, kind)
	end
	E.propList = {}
end

-- One broken by a punch. Breaking the last of his walls and turrets (after
-- breaking a couple) leaves him out of cactus: STUNNED.
local function broken(E, prop)
	endProp(E, prop, "Broken")
	if prop.kind ~= "Turret" and prop.kind ~= "Wall" then
		return
	end
	E.brokenSinceStun = (E.brokenSinceStun or 0) + 1
	for _, q in ipairs(E.propList) do
		if not q.gone and (q.kind == "Turret" or q.kind == "Wall") then
			return -- (he's still got some)
		end
	end
	if E.phase >= 2 and E.state == "Fighting" and E.brokenSinceStun >= E.def.Moves.Stunned.Needs then
		E.pendingStun = true
		E.brokenSinceStun = 0
	end
end

-- Something you can punch: health for `punches` punches at the floor's
-- recommended power. One that takes two can't be broken in one however
-- strong you are (the first punch can only take half: MinHealth).
local function makePunchable(E, prop, punches, radius, name)
	local model = prop.model
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	local hp = math.max(1, math.floor(rec * punches))
	model:SetAttribute("MaxHealth", hp)
	model:SetAttribute("Health", hp)
	if punches >= 2 then
		model:SetAttribute("MinHealth", math.floor(hp / 2))
	end
	model:SetAttribute("HitRadius", radius)
	model:SetAttribute("NoBar", true)
	model:SetAttribute("StudioFair", true)
	model:SetAttribute("DisplayName", name)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- (every screen has it, to lock on)
	end)
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = model
	onHit.Event:Connect(function(_player, damage, killed)
		if prop.gone or (tonumber(damage) or 0) <= 0 then
			return
		end
		if model:GetAttribute("MinHealth") then
			model:SetAttribute("MinHealth", nil) -- (the first punch landed: the next can break it)
		end
		if killed then
			broken(E, prop)
		end
	end)
end

local function newModel(E, name, kind, id)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Id", id)
	model:SetAttribute("Floor", E.floor)
	return model
end

-- A CACTUS WALL across `mid`, running along `along`, `length` long. Its red
-- line shows at warnAt, it bursts up at riseAt and crumbles at crumbleAt;
-- in a rage it creeps along `toward` at slideSpeed.
local function spawnWall(E, mid, along, toward, length, warnAt, riseAt, crumbleAt, slideSpeed)
	local a = E.def.Attacks.Wall
	local seg = a.Segment
	local n = math.max(3, math.floor(length / seg) + 1)
	if n % 2 == 0 then
		n = n + 1
	end
	local half = (n - 1) * seg / 2
	local ends = { atFloor(E, mid - along * half), atFloor(E, mid + along * half) }
	local keep, segs, keepText = {}, {}, {}
	local weak, weakD = nil, math.huge
	local middle = (n + 1) / 2
	for i = 1, n do
		local c = ends[1]:Lerp(ends[2], (i - 1) / (n - 1))
		local ok = flat(c - E.center).Magnitude <= E.fightR - 4
		for _, rk in ipairs(E.rocks) do
			if flatDistance(c, rk.center) < rk.radius + 1.5 then
				ok = false -- (a rock leaves a gap in it)
			end
		end
		keep[i], segs[i], keepText[i] = ok, c, ok and "1" or "0"
		if ok and math.abs(i - middle) < weakD then
			weak, weakD = i, math.abs(i - middle)
		end
	end
	if not weak then
		return nil
	end
	-- how long it can creep before it reaches the arena's edge
	local slide = toward * slideSpeed
	local slideFor = 0
	if slideSpeed > 0 then
		slideFor = (tonumber(crumbleAt) or 0) - (tonumber(riseAt) or 0)
		for i, c in ipairs(segs) do
			if keep[i] then
				local room = tonumber(toEdge(E.center, c, toward, E.fightR - 4)) or 0
				slideFor = math.min(slideFor, room / slideSpeed)
			end
		end
	end
	local id = newId(E)
	local model = newModel(E, "CactusWall", "Wall", id)
	local up = Vector3.new(0, a.Height / 2, 0)
	local function blockAt(c)
		return CFrame.lookAt(c + up, c + up + toward) -- (its long side runs along the wall)
	end
	local weakPart = hitbox("Weak", Vector3.new(3, a.Height, 3), blockAt(segs[weak]), model)
	model.PrimaryPart = weakPart
	local blocks, bases = {}, {}
	for i = 1, n do
		if keep[i] then
			local b = hitbox("Block" .. i, Vector3.new(seg + 0.3, a.Height, a.Thick), blockAt(segs[i]), model)
			blocks[#blocks + 1] = b
			bases[b] = b.CFrame
		end
	end
	model:SetAttribute("A", ends[1])
	model:SetAttribute("B", ends[2])
	model:SetAttribute("N", n)
	model:SetAttribute("Keep", table.concat(keepText))
	model:SetAttribute("Weak", weak)
	model:SetAttribute("Warn", warnAt)
	model:SetAttribute("T0", riseAt)
	model:SetAttribute("T1", crumbleAt)
	model:SetAttribute("Slide", slide)
	model:SetAttribute("SlideFor", slideFor)
	local prop = {
		kind = "Wall", id = id, model = model, weakPart = weakPart, weakBase = weakPart.CFrame,
		blocks = blocks, bases = bases, segs = segs, segNow = table.clone(segs), keep = keep,
		along = along, seg = seg, riseAt = riseAt, crumbleAt = crumbleAt, slide = slide,
		slideFor = slideFor, touched = {},
	}
	makePunchable(E, prop, a.Punches, 2.2, "Cactus Wall")
	model.Parent = propFolder(E)
	table.insert(E.propList, prop)
	return prop
end

local function stepWall(E, w, t, list)
	if t >= w.crumbleAt then
		endProp(E, w, "Wither")
		return
	end
	local a = E.def.Attacks.Wall
	if w.slideFor > 0 and t > w.riseAt then
		-- (rage: the whole wall creeps toward you)
		local off = w.slide * math.min(t - w.riseAt, w.slideFor)
		for i, c in ipairs(w.segs) do
			w.segNow[i] = c + off
		end
		for _, b in ipairs(w.blocks) do
			b.CFrame = w.bases[b] + off
		end
		w.weakPart.CFrame = w.weakBase + off
	end
	local reach = a.Thick / 2 + PLAYER_RADIUS + 0.5
	if not w.risen then
		if t >= w.riseAt then
			-- IT BURSTS UP: solid now, punchable now, and anyone standing on its
			-- line is thrown off it
			w.risen = true
			for _, b in ipairs(w.blocks) do
				b.CanCollide = true
				b.CanQuery = true -- (so standing on top of it counts as standing on the ground)
			end
			CollectionService:AddTag(w.model, "CombatTarget")
			for _, p in ipairs(list) do
				local root = rootOf(p)
				if root then
					local q, d = wallNearest(w, root.Position)
					if d <= reach then
						w.touched[p] = t
						CombatService.DamagePlayer(p, a.RiseDamage, q, knockbackFrom(q, root, a.Knockback))
					end
				end
			end
		end
		return
	end
	-- its spines: touch it and it pricks you (once a second at most)
	for _, p in ipairs(list) do
		if t - (w.touched[p] or -math.huge) >= 1 then
			local root = rootOf(p)
			if root then
				local q, d = wallNearest(w, root.Position)
				if d <= reach - 0.1 then
					w.touched[p] = t
					CombatService.DamagePlayer(p, a.TouchDamage, q, knockbackFrom(q, root, a.Knockback * 0.7))
				end
			end
		end
	end
end

-- A NEEDLE TURRET sprouting at `spot` (it's grown, and punchable, Grow later)
local function spawnTurret(E, spot, bornAt)
	local a = E.def.Attacks.Turrets
	local id = newId(E)
	local model = newModel(E, "NeedleTurret", "Turret", id)
	local hit = hitbox("Hit", Vector3.new(3, 6, 3), CFrame.new(spot + Vector3.new(0, 3, 0)), model)
	model.PrimaryPart = hit
	model:SetAttribute("Born", bornAt)
	model:SetAttribute("Grow", a.Grow)
	local prop = {
		kind = "Turret", id = id, model = model, pos = atFloor(E, spot), growAt = bornAt + a.Grow,
		nextShot = bornAt + a.First, crumbleAt = bornAt + a.Life, shotId = 0,
	}
	makePunchable(E, prop, a.Punches, 2, "Needle Turret")
	model.Parent = propFolder(E)
	table.insert(E.propList, prop)
	return prop
end

local function stepTurret(E, tu, t, list)
	if t >= tu.crumbleAt then
		endProp(E, tu, "Wither")
		return
	end
	if t < tu.growAt then
		return
	end
	local a = E.def.Attacks.Turrets
	if not tu.tagged then
		tu.tagged = true
		CollectionService:AddTag(tu.model, "CombatTarget")
	end
	if t < tu.nextShot then
		return
	end
	tu.nextShot = t + a.Every
	-- at whoever's nearest (within reach): a thin red line, then the needle
	local best, bestD = nil, a.Reach
	for _, p in ipairs(list) do
		local root = rootOf(p)
		if root then
			local d = flatDistance(root.Position, tu.pos)
			if d < bestD then
				best, bestD = root, d
			end
		end
	end
	if not best then
		return
	end
	local dir = unitOr(flat(best.Position - tu.pos), Vector3.new(0, 0, 1))
	local from = tu.pos + dir * 1.8
	local len = blockedAt(E, from, dir, a.Reach, a.Radius)
	local to = from + dir * len
	tu.shotId = tu.shotId + 1
	local m = tu.model
	m:SetAttribute("ShotFrom", from)
	m:SetAttribute("ShotTo", to)
	m:SetAttribute("ShotWarn", t)
	m:SetAttribute("ShotAt", t + a.Warn)
	m:SetAttribute("ShotId", tu.shotId)
	addShot(E, { from, to }, t + a.Warn, a.Speed, a.Radius, a.Height, a.Damage, a.Knockback, nil, tu)
end

-- A PRICKLY BUDDY hopping off him from `from` to `to` (it lands at Land)
local function spawnBuddy(E, from, to, bornAt)
	local a = E.def.Attacks.Buddies
	local id = newId(E)
	local model = newModel(E, "PricklyBuddy", "Buddy", id)
	local hit = hitbox("Hit", Vector3.new(2.6, 3.2, 2.6), CFrame.new(from + Vector3.new(0, 1.6, 0)), model)
	model.PrimaryPart = hit
	model:SetAttribute("Born", bornAt)
	model:SetAttribute("Land", bornAt + a.Land)
	model:SetAttribute("From", from)
	model:SetAttribute("To", to)
	local prop = {
		kind = "Buddy", id = id, model = model, hit = hit, from = from, to = to, pos = from,
		bornAt = bornAt, landAt = bornAt + a.Land, crumbleAt = bornAt + a.Life,
		facing = unitOr(flat(to - from), E.facing),
	}
	makePunchable(E, prop, a.Punches, 1.6, "Prickly Buddy")
	model.Parent = propFolder(E)
	table.insert(E.propList, prop)
	return prop
end

local function stepBuddy(E, bu, t, list, dt)
	local a = E.def.Attacks.Buddies
	if bu.puffAt then
		if t >= bu.puffAt + a.Puff then
			-- POP: a ring of needles round it
			hitArea(E, bu.pos, a.Radius, a.Damage, a.Knockback)
			endProp(E, bu, "Pop")
		end
		return
	end
	if t >= bu.crumbleAt then
		endProp(E, bu, "Wither")
		return
	end
	if t < bu.landAt then
		-- (still hopping off him)
		local span = bu.landAt - bu.bornAt
		bu.pos = bu.from:Lerp(bu.to, math.clamp((t - bu.bornAt) / span, 0, 1))
		bu.hit.CFrame = CFrame.new(bu.pos + Vector3.new(0, 1.6 + arcHeight(t - bu.bornAt, span, 0.5, 5), 0))
		return
	end
	if not bu.tagged then
		bu.tagged = true
		CollectionService:AddTag(bu.model, "CombatTarget")
	end
	-- waddling after whoever's nearest
	local best, bestD = nil, math.huge
	for _, p in ipairs(list) do
		local root = rootOf(p)
		if root then
			local d = flatDistance(root.Position, bu.pos)
			if d < bestD then
				best, bestD = root, d
			end
		end
	end
	if not best then
		return
	end
	if bestD <= a.Trigger then
		bu.puffAt = t -- (it puffs up... then pops)
		bu.model:SetAttribute("PuffAt", t)
		return
	end
	local dir = unitOr(flat(best.Position - bu.pos), bu.facing)
	bu.facing = dir
	local p = bu.pos + dir * math.min(a.Speed * dt, bestD)
	p = clearOfRocks(E, p, 1.4)
	-- (round a wall, not through it)
	for _, w in ipairs(E.propList) do
		if w.kind == "Wall" and w.risen and not w.gone then
			for i, c in ipairs(w.segNow) do
				if w.keep[i] then
					local off = flat(p - c)
					if off.Magnitude < WALL_BLOCK + 1.4 then
						p = c + unitOr(off, -dir) * (WALL_BLOCK + 1.4)
					end
				end
			end
		end
	end
	p = inside(E, p, E.fightR - 3)
	bu.pos = p
	local at = p + Vector3.new(0, 1.6, 0)
	bu.hit.CFrame = CFrame.lookAt(at, at + dir)
end

-- A QUICKSAND patch at `center` (it drags from onAt to offAt)
local function spawnSand(E, center, radius, warnAt, onAt, offAt)
	local id = newId(E)
	local folder = Instance.new("Folder")
	folder.Name = "Quicksand"
	folder:SetAttribute("Kind", "Sand")
	folder:SetAttribute("Id", id)
	folder:SetAttribute("Floor", E.floor)
	folder:SetAttribute("C", center)
	folder:SetAttribute("R", radius)
	folder:SetAttribute("Warn", warnAt)
	folder:SetAttribute("T0", onAt)
	folder:SetAttribute("T1", offAt)
	folder.Parent = propFolder(E)
	local prop = { kind = "Sand", id = id, folder = folder, center = center, radius = radius, onAt = onAt, offAt = offAt }
	table.insert(E.propList, prop)
	return prop
end

local function stepSand(E, s, t)
	if t >= s.offAt then
		endProp(E, s, "Wither")
		return
	end
	if t >= s.onAt and not s.puddle then
		-- it nibbles at whoever stands in it (BossService's burning puddles,
		-- quietly); the drag is on your screen (BossBodies/Tuber)
		local a = E.def.Attacks.Quicksand
		s.puddle = { pos = s.center, radius = s.radius, untilT = s.offAt, tick = a.Tick, damage = a.Damage }
		table.insert(E.puddles, s.puddle)
	end
end

local function stepProps(E, t, dt)
	if #E.propList == 0 then
		return
	end
	local list = fightersIn(E)
	local live = {}
	for _, prop in ipairs(E.propList) do
		if not prop.gone then
			if prop.kind == "Wall" then
				stepWall(E, prop, t, list)
			elseif prop.kind == "Turret" then
				stepTurret(E, prop, t, list)
			elseif prop.kind == "Buddy" then
				stepBuddy(E, prop, t, list, dt)
			elseif prop.kind == "Sand" then
				stepSand(E, prop, t)
			end
		end
		if not prop.gone then
			live[#live + 1] = prop
		end
	end
	E.propList = live
end

----------------------------------------------------------------------
-- His two forms
----------------------------------------------------------------------
-- Little Tuber ("Stack") or the golem ("Brute"): his invisible body (the
-- Root) is sized to match, so the lock-on camera pulls back for the golem.
local function setForm(E, form)
	E.form = form
	E.model:SetAttribute("Form", form)
	local w, h
	if form == "Brute" then
		w, h = E.def.Brute.Width, E.def.Brute.Height
	else
		w, h = E.def.Size, E.def.Size * 0.85
	end
	E.height = h
	E.root.Size = Vector3.new(w, h, w)
	E.model:SetAttribute("HitRadius", w / 2)
	place(E)
end

-- Where you can punch him (CombatService asks, from where you stand):
-- whichever of his three buddies is nearest while he's split, the lane he's
-- lying along when he's toppled, his round little body - or the golem's
-- great trunk. Always at your height, unless he's up in the air.
local function aimPoint(E, from)
	local t = now()
	local up = airHeight(E, t)
	if E.split and E.buddyPos then
		local best, bestD = nil, math.huge
		for k = 1, 3 do
			local p = E.buddyPos[k]
			if p then
				local d = flatDistance(p, from)
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
		if best then
			return best, E.def.Attacks.Split.Radius
		end
	end
	if E.down then
		local q = segNearest(E.down.a, E.down.b, from)
		return Vector3.new(q.X, E.floorY + 2.2, q.Z), 3
	end
	local c = Vector3.new(E.pos.X, E.floorY + up, E.pos.Z)
	if E.form == "Brute" then
		local B = E.def.Brute
		local off = flat(from - c)
		local p = (off.Magnitude > B.Reach) and (c + off.Unit * B.Reach) or Vector3.new(from.X, c.Y, from.Z)
		return Vector3.new(p.X, math.clamp(from.Y, c.Y + 1, c.Y + B.Height * 0.6), p.Z), 0.6
	end
	return Vector3.new(c.X, math.clamp(from.Y, c.Y + 1.5, c.Y + STACK * 3), c.Z), E.def.Size * 0.4
end

----------------------------------------------------------------------
-- SPLIT!: where each of his three buddies is (1 = bottom, 2 = middle,
-- 3 = his head), and how high off the ground
----------------------------------------------------------------------
local function splitPos(E, S, k, t)
	local a = E.def.Attacks.Split
	local popStart = S.t0 + a.Shake
	if t < popStart then
		return S.base, (k - 1) * STACK -- (still a stack, shaking)
	end
	if t < S.popEnd then
		local u = (t - popStart) / a.Pop
		return S.base:Lerp(S.pops[k], u), arcHeight(t - popStart, a.Pop, 0.5, 4 + (k - 1) * 2) + (k - 1) * STACK * (1 - u)
	end
	local ball = S.balls[k]
	if not ball or t < ball.launch then
		return S.pops[k], 0 -- (revving up where it landed)
	end
	if t < ball.stop then
		return pointAlong(ball.pts, (t - ball.launch) * a.Speed), 0 -- (spin-dashing)
	end
	local stopAt = ball.pts[#ball.pts]
	if not S.rally or t < S.restackAt then
		return stopAt, 0 -- (dizzy)
	end
	local u = math.clamp((t - S.restackAt) / a.Restack, 0, 1)
	return stopAt:Lerp(S.rally, u), arcHeight(t - S.restackAt, a.Restack, 0.5, 6 + (k - 1) * 2) + (k - 1) * STACK * u
end

local function stepSplit(E, t)
	local S = E.split
	E.buddyPos = E.buddyPos or {}
	for k = 1, 3 do
		local p, up = splitPos(E, S, k, t)
		E.buddyPos[k] = Vector3.new(p.X, E.floorY + 2.2 + up, p.Z)
	end
	-- (his invisible body follows his head, so a lock-on follows it too)
	local head = E.buddyPos[3]
	E.pos = Vector3.new(head.X, E.floorY, head.Z)
	place(E)
end

-- Tidies away anything a move left behind when it was cut short (the
-- power-up, a reset, a test forcing a move): split back into one, standing
-- up, feet on the ground.
local function settle(E)
	if E.split then
		-- (his three buddies hop back together where they are on average,
		-- inside his ground - they may have rolled right out to the rim.
		-- BossBodies/Tuber draws the hop, so his body jumping there is fine.)
		local sum, n = Vector3.new(), 0
		for _, p in ipairs(E.buddyPos or {}) do
			sum, n = sum + p, n + 1
		end
		local mid = (n > 0) and (sum / n) or E.pos
		E.pos = clearOfRocks(E, inside(E, mid, E.def.Leash - 1), 3)
		E.split = nil
		place(E)
	end
	E.buddyPos = nil
	E.down = nil
	E.motion, E.arc, E.sweep = nil, nil, nil
end

-- starts a move: leftovers tidied, then published for every screen
local function begin(E, name, number)
	settle(E)
	return setAction(E, name, number)
end

----------------------------------------------------------------------
-- ROUND 1: TUBER's moves
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- WOBBLE BONK: leans back (turning to face you until a blink before), then
-- flops his head forward. Slot 1 = the spot straight ahead it lands on.
function Attacks.Bonk(E, token)
	local a = E.def.Attacks.Bonk
	E.track, E.chase = true, false
	local t0 = begin(E, "Bonk", nil)
	if not waitUntil(E, token, t0 + a.Tell - a.Lock) then
		return false
	end
	E.track = false
	setSlot(E, 1, ground(E) + E.facing * a.Reach)
	if not waitUntil(E, token, t0 + a.Tell) then
		return false
	end
	hitFront(E, a.Reach, a.Arc, a.Damage, a.Knockback)
	return waitUntil(E, token, t0 + a.Tell + a.Recovery)
end

-- CLUMSY TOPPLE: leans back (the lane follows you until it locks), falls
-- flat along it like a tree, lies there flailing (free hits along his whole
-- length) and struggles back up. Slot 1 = his feet, slot 2 = where his head lands.
function Attacks.Topple(E, token)
	local a = E.def.Attacks.Topple
	E.track, E.chase = true, false
	local t0 = begin(E, "Topple", nil)
	if not waitUntil(E, token, t0 + a.Tell - a.Lock) then
		return false
	end
	E.track = false
	local base = ground(E)
	local tip = base + E.facing * a.Length
	setSlot(E, 1, base)
	setSlot(E, 2, tip)
	local hitAt = t0 + a.Tell + a.Fall
	if not waitUntil(E, token, hitAt) then
		return false
	end
	hitStrip(E, base, tip, a.Width, a.Damage, a.Knockback)
	E.down = { a = base + E.facing * 2, b = tip }
	if not waitUntil(E, token, hitAt + a.Down) then
		return false
	end
	local ok = waitUntil(E, token, hitAt + a.Down + a.Rise * 0.5)
	E.down = nil -- (half way up: back to his usual shape)
	return ok and waitUntil(E, token, hitAt + a.Down + a.Rise)
end

-- NEEDLE SNEEZE: "ah... ah... ACHOO!" and a ring of needles spreads out
-- from him. No slots: the ring starts from where he stands.
function Attacks.Sneeze(E, token)
	local a = E.def.Attacks.Sneeze
	E.track, E.chase = true, false
	local t0 = begin(E, "Sneeze", nil)
	if not waitUntil(E, token, t0 + a.Tell) then
		return false
	end
	E.track = false
	addRing(E, ground(E), 3, a.Reach, a.Speed, a.Thickness, a.Height, a.Damage, a.Knockback)
	return waitUntil(E, token, t0 + a.Tell + a.Recovery)
end

-- BOUNCE STOMP: squashes down, springs up and lands on the red circle
-- (where you were when he crouched), with a little ring of sand. Slot 1 =
-- take-off, slot 2 = landing.
function Attacks.Stomp(E, token)
	local a = E.def.Attacks.Stomp
	E.chase = false
	local t0 = begin(E, "Stomp", nil)
	local from = ground(E)
	local to = inside(E, targetPosition(E) or from, E.def.Leash - 1)
	E.facing = unitOr(flat(to - from), E.facing)
	E.track = false
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local up = t0 + a.Crouch
	E.arc = { t0 = up, air = a.Air, rise = 0.5, height = a.Height }
	E.motion = { from = from, to = to, t0 = up, t1 = up + a.Air }
	if not waitUntil(E, token, up + a.Air) then
		return false
	end
	E.motion, E.arc = nil, nil
	E.pos = to
	hitArea(E, to, a.Radius, a.Damage, a.Knockback)
	addRing(E, to, a.Radius, a.Radius + a.RingReach, 22, 2.5, 2.5, a.RingDamage, 25)
	return waitUntil(E, token, up + a.Air + a.Recovery)
end

-- SPLIT!: he shakes, pops into three buddies (slots 1-3: where each lands),
-- and one after another each revs up and SPIN-DASHES at you as a spiky ball
-- (the path is set as it starts revving: slots 4-5 for the bottom one's
-- bounce and stop, 6-7 the middle one's, 8-9 his head's). They all sit
-- there dizzy - free hits, any of them - then hop back into a stack (slot
-- 10: where). Punching any of them hurts him: they share his health.
function Attacks.Split(E, token)
	local a = E.def.Attacks.Split
	E.track, E.chase = true, false
	local t0 = begin(E, "Split", nil)
	local base = ground(E)
	local face = E.facing
	local pops = {}
	for k = 1, 3 do
		local ang = math.rad(({ -120, 120, 0 })[k])
		local spot = clearOfRocks(E, base + rotateY(face, ang) * a.Spread, 2.5)
		pops[k] = inside(E, spot, E.def.Leash)
		setSlot(E, k, pops[k])
	end
	E.track = false
	local S = { t0 = t0, base = base, pops = pops, popEnd = t0 + a.Shake + a.Pop, balls = {} }
	E.split = S
	stepSplit(E, now())
	for k = 1, 3 do
		local revAt = S.popEnd + (k - 1) * a.Gap
		if not waitUntil(E, token, revAt) then
			return false
		end
		local aim = targetPosition(E) or base
		local dir = unitOr(flat(aim - pops[k]), face)
		local pts = tracePath(E, pops[k], dir, a.Length, 1, a.Radius)
		setSlot(E, 3 + (k - 1) * 2 + 1, pts[3] and pts[2] or pts[#pts])
		setSlot(E, 3 + (k - 1) * 2 + 2, pts[#pts])
		local launch = revAt + a.Rev
		local len = pathLength(pts)
		S.balls[k] = { pts = pts, launch = launch, stop = launch + len / a.Speed }
		addShot(E, pts, launch, a.Speed, a.Radius, a.Height, a.Damage, a.Knockback)
	end
	local lastStop = 0
	for k = 1, 3 do
		lastStop = math.max(lastStop, S.balls[k].stop)
	end
	S.restackAt = lastStop + a.Dizzy
	if not waitUntil(E, token, S.restackAt) then
		return false
	end
	-- back together where they are, on average (inside his ground)
	local sum = Vector3.new()
	for k = 1, 3 do
		sum = sum + S.balls[k].pts[#S.balls[k].pts]
	end
	S.rally = clearOfRocks(E, inside(E, sum / 3, E.def.Leash - 1), 3)
	setSlot(E, 10, S.rally)
	if not waitUntil(E, token, S.restackAt + a.Restack) then
		return false
	end
	E.split = nil
	E.buddyPos = nil
	E.pos = S.rally
	place(E)
	return true
end

----------------------------------------------------------------------
-- ROUND 2: THE BRUTE's moves
----------------------------------------------------------------------
-- the spot he hops to: far from everyone (but not so far he's out of sight),
-- inside his ground, and not onto a rock, a wall, a turret or his own quicksand
local function hopSpot(E, from)
	local H = E.def.Moves.RootHop
	local fighters = {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			fighters[#fighters + 1] = atFloor(E, root.Position)
		end
	end
	local best, bestScore = nil, -math.huge
	local reach = E.def.Leash - 3
	for ring = 1, 3 do
		local r = reach * ({ 0.35, 0.65, 1 })[ring]
		for i = 0, 23 do
			local ang = i / 24 * math.pi * 2
			local p = atFloor(E, E.center + Vector3.new(math.sin(ang) * r, 0, math.cos(ang) * r))
			local dMin = math.huge
			for _, f in ipairs(fighters) do
				dMin = math.min(dMin, flatDistance(p, f))
			end
			if dMin == math.huge then
				dMin = H.Want
			end
			local score = -math.abs(dMin - H.Want)
			if dMin < H.Min then
				score = score - 200
			end
			local hop = flatDistance(p, from)
			if hop < 20 then
				score = score - 100
			end
			for _, rk in ipairs(E.rocks) do
				if flatDistance(p, rk.center) < rk.radius + 7 then
					score = score - 300
				end
			end
			for _, q in ipairs(E.propList) do
				if not q.gone then
					if q.kind == "Wall" then
						local _, d = wallNearest(q, p)
						if d < 7 then
							score = score - 300
						end
					elseif q.kind == "Turret" and flatDistance(p, q.pos) < 7 then
						score = score - 300
					elseif q.kind == "Sand" and flatDistance(p, q.center) < q.radius + 3 then
						score = score - 150
					end
				end
			end
			-- (a shorter hop, all else equal; ties broken the same way every time)
			score = score - hop * 0.02 + (ring * 24 + i) * 1e-5
			if score > bestScore then
				best, bestScore = p, score
			end
		end
	end
	return best or from
end

local Moves = {}
Boss.Moves = Moves

-- ROOT HOP: rips his roots up (the landing spot shows), leaps across the
-- arena and slams down with a ring of sand - then his hop has to recharge
-- (HopAt). Slot 1 = take-off, slot 2 = landing.
function Moves.RootHop(E, token)
	local H = E.def.Moves.RootHop
	E.track, E.chase = false, false
	local t0 = begin(E, "RootHop", nil)
	local from = ground(E)
	local to = hopSpot(E, from)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local up = t0 + H.Tell
	E.arc = { t0 = up, air = H.Air, rise = 0.45, height = H.Height }
	E.motion = { from = from, to = to, t0 = up, t1 = up + H.Air }
	if not waitUntil(E, token, up + H.Air) then
		return false
	end
	E.motion, E.arc = nil, nil
	E.pos = to
	hitArea(E, to, H.Radius, H.Damage, H.Knockback)
	addRing(E, to, H.Radius - 1, H.RingReach, H.RingSpeed, 3, 3, H.RingDamage, 35)
	E.hopReadyAt = now() + byRage(E, H.Cooldown)
	E.model:SetAttribute("HopAt", E.hopReadyAt)
	E.track = true
	return waitUntil(E, token, up + H.Air + H.Plant)
end

-- SHOVE BURST: his spines bristle (a small red ring) and blast out: anyone
-- right next to him is thrown back
function Moves.ShoveBurst(E, token)
	local S = E.def.Moves.ShoveBurst
	E.track = false
	local t0 = begin(E, "ShoveBurst", nil)
	if not waitUntil(E, token, t0 + S.Tell) then
		return false
	end
	hitArea(E, ground(E), S.Radius, S.Damage, S.Knockback)
	return waitUntil(E, token, t0 + S.Tell + S.Recovery)
end

-- CORNERED: you caught him with his hop still recharging! He panics for
-- ActN seconds (free hits), blasts you back, and escapes.
function Moves.Cornered(E, token)
	local C = E.def.Moves.Cornered
	local panic = byRage(E, C.Panic)
	E.track = false
	local t0 = begin(E, "Cornered", panic)
	E.corneredReadyAt = t0 + C.Cooldown
	if not waitUntil(E, token, t0 + panic) then
		return false
	end
	if not Moves.ShoveBurst(E, token) then
		return false
	end
	E.hopReadyAt = 0
	return Moves.RootHop(E, token)
end

-- STUNNED: out of cactus (you broke the last of his walls and turrets). He
-- slumps for ActN seconds - free hits - and can't grow more for a while.
function Moves.Stunned(E, token)
	local S = E.def.Moves.Stunned
	E.track = false
	local t0 = begin(E, "Stunned", S.Time)
	E.noCactiUntil = t0 + S.Time + S.NoCacti
	return waitUntil(E, token, t0 + S.Time)
end

-- RAGE: once, low on health - he roars and needles fly off him. From now
-- on: more of everything, shorter breaks, and his walls creep toward you.
function Moves.Rage(E, token)
	local R = E.def.Moves.Rage
	E.track = false
	E.rage = true
	E.model:SetAttribute("Rage", true)
	local t0 = begin(E, "Rage", R.Time)
	if not waitUntil(E, token, t0 + 0.6) then
		return false
	end
	addRing(E, ground(E), 6, R.Reach, 30, 2.5, 3.5, R.Damage, 30)
	return waitUntil(E, token, t0 + R.Time)
end

-- NEEDLE VOLLEY: a red cone (following you until it locks), then three
-- fans of needles. A rock or a wall stops a needle. Slot 1 = where the
-- needles start (in front of him); slots 2.. = where each needle stops,
-- five a fan, set as each fan fires.
function Attacks.Volley(E, token)
	local a = E.def.Attacks.Volley
	E.track, E.chase = true, false
	local t0 = begin(E, "Volley", nil)
	if not waitUntil(E, token, t0 + a.Tell - a.Lock) then
		return false
	end
	E.track = false
	local dir = E.facing
	local origin = ground(E) + dir * 6
	setSlot(E, 1, origin)
	for s = 1, a.Shots do
		local fireAt = t0 + a.Tell + (s - 1) * a.Gap
		if not waitUntil(E, token, fireAt) then
			return false
		end
		local struck = {} -- (one needle of a fan hits you, not all five)
		for n = 1, a.Needles do
			local ang = math.rad(-a.Spread / 2 + (n - 1) * a.Spread / math.max(a.Needles - 1, 1))
			local d = rotateY(dir, ang)
			local to = origin + d * blockedAt(E, origin, d, a.Reach, a.Radius)
			setSlot(E, 1 + (s - 1) * a.Needles + n, to)
			addShot(E, { origin, to }, fireAt, a.Speed, a.Radius, a.Height, a.Damage, a.Knockback, struck)
		end
	end
	return waitUntil(E, token, t0 + a.Tell + (a.Shots - 1) * a.Gap + a.Recovery)
end

-- DESERT RAIN: spits cactus balls high into the sky; one after another a
-- red circle shows round you, and a ball lands on it Fall seconds later.
-- Slot k = where the k-th lands.
function Attacks.Rain(E, token)
	local a = E.def.Attacks.Rain
	E.track, E.chase = true, false
	local t0 = begin(E, "Rain", nil)
	local n = byRage(E, a.Drops)
	for k = 1, n do
		local showAt = t0 + a.Spit + (k - 1) * a.Gap
		if not waitUntil(E, token, showAt) then
			return false
		end
		local aim = targetPosition(E) or ground(E)
		local spot = aim
		if k > 1 then
			local ang = E.rng:NextNumber() * math.pi * 2
			local r = 4 + E.rng:NextNumber() * (a.Spread - 4)
			spot = aim + Vector3.new(math.sin(ang) * r, 0, math.cos(ang) * r)
		end
		spot = inside(E, spot, E.fightR - 4)
		setSlot(E, k, spot)
		table.insert(E.drops, { pos = spot, at = showAt + a.Fall, radius = a.Radius, damage = a.Damage, knockback = a.Knockback })
	end
	E.track = false
	return waitUntil(E, token, t0 + a.Spit + (n - 1) * a.Gap + a.Fall + a.Recovery)
end

-- SPINE LANCE: charges up (ActN = how long), the red line following you
-- until it locks and flashes; then a giant spike flies across the arena
-- (through his own walls - but a rock stops it). Slot 1 = where it starts,
-- slot 2 = where it stops.
function Attacks.Lance(E, token)
	local a = E.def.Attacks.Lance
	E.track, E.chase = true, false
	local t0 = begin(E, "Lance", a.Charge)
	if not waitUntil(E, token, t0 + a.Charge - a.Lock) then
		return false
	end
	E.track = false
	local dir = E.facing
	local from = ground(E) + dir * 7
	local len = toEdge(E.center, from, dir, E.fightR - 2)
	local rockAt = firstHit(E, from, dir, len, a.Width / 2, false, true)
	if rockAt then
		len = math.max(1, rockAt)
	end
	local to = from + dir * len
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local fireAt = t0 + a.Charge
	addShot(E, { from, to }, fireAt, a.Speed, a.Width / 2, a.Height, a.Damage, a.Knockback)
	return waitUntil(E, token, fireAt + a.Recovery)
end

-- CACTUS WALL: he slams the ground and a wall of cactus bursts up across
-- the way between you and him (its red line shows first). No slots: the
-- wall itself carries everything (see "The cactus he leaves around").
function Attacks.Wall(E, token)
	local a = E.def.Attacks.Wall
	E.track, E.chase = true, false
	local t0 = begin(E, "Wall", nil)
	local aim = targetPosition(E)
	if aim then
		local gap = flat(aim - ground(E))
		local d = gap.Magnitude
		local toward = unitOr(gap, E.facing)
		local at = math.clamp(d * a.At, 12, math.max(12, d - 10))
		local mid = ground(E) + toward * at
		local along = Vector3.new(-toward.Z, 0, toward.X)
		local warnAt = t0 + 0.2
		local riseAt = warnAt + a.Tell
		spawnWall(E, mid, along, toward, byRage(E, a.Length), warnAt, riseAt, riseAt + byRage(E, a.Life), byRage(E, a.Slide))
	end
	E.track = false
	return waitUntil(E, token, t0 + 0.2 + a.Tell + 0.3)
end

-- NEEDLE TURRETS: he punches the ground and little cactus towers sprout
-- round you (on your sides, so they cross-fire)
local function turretSpot(E, aim, base, k)
	local a = E.def.Attacks.Turrets
	local offsets = { 90, -90, 150, -150, 45, -45, 180, 0 }
	for j = 0, #offsets - 1 do
		local dir = rotateY(base, math.rad(offsets[((k - 1 + j) % #offsets) + 1]))
		for _, dist in ipairs({ a.Far, a.Near }) do
			local p = atFloor(E, aim + dir * dist)
			local ok = flat(p - E.center).Magnitude <= E.fightR - 8 and flatDistance(p, E.pos) >= 10
			for _, rk in ipairs(E.rocks) do
				if flatDistance(p, rk.center) < rk.radius + 5 then
					ok = false
				end
			end
			for _, q in ipairs(E.propList) do
				if not q.gone then
					if q.kind == "Turret" and flatDistance(p, q.pos) < 8 then
						ok = false
					elseif q.kind == "Wall" then
						local _, d = wallNearest(q, p)
						if d < 6 then
							ok = false
						end
					end
				end
			end
			if ok then
				return p
			end
		end
	end
	return nil
end

function Attacks.Turrets(E, token)
	local a = E.def.Attacks.Turrets
	E.track, E.chase = true, false
	local t0 = begin(E, "Turrets", nil)
	if not waitUntil(E, token, t0 + 0.7) then
		return false
	end
	local aim = targetPosition(E) or ground(E)
	local base = unitOr(flat(ground(E) - aim), E.facing)
	local n = math.min(byRage(E, a.Plant), byRage(E, a.Max) - count(E, "Turret"))
	for k = 1, n do
		local spot = turretSpot(E, aim, base, k)
		if spot then
			spawnTurret(E, spot, t0 + 0.9)
		end
	end
	E.track = false
	return waitUntil(E, token, t0 + 0.9 + a.Grow)
end

-- BALL HERD: spinning cactus balls roll in from the edge of the arena, one
-- after another, at you (each lane shows Tell seconds before it rolls),
-- bouncing off rocks, walls and the rim. Slots: four a ball - its start,
-- its first and second bounce, and where it stops (a spot repeats if it
-- bounces less).
function Attacks.Herd(E, token)
	local a = E.def.Attacks.Herd
	E.track, E.chase = true, false
	local t0 = begin(E, "Herd", nil)
	local n = byRage(E, a.Balls)
	local offsets = { 1.1, -1.1, 0.55, -0.55, 1.6 }
	for k = 1, n do
		local showAt = t0 + a.Show + (k - 1) * a.Gap
		if not waitUntil(E, token, showAt) then
			return false
		end
		local aim = targetPosition(E) or ground(E)
		local rel = flat(aim - E.center)
		local ang = (rel.Magnitude > 8) and math.atan2(rel.X, rel.Z) or math.atan2(E.facing.X, E.facing.Z)
		ang = ang + offsets[((k - 1) % #offsets) + 1]
		local start = atFloor(E, E.center + Vector3.new(math.sin(ang), 0, math.cos(ang)) * (E.edgeR - 1))
		local dir = unitOr(flat(aim - start), unitOr(flat(E.center - start), Vector3.new(0, 0, 1)))
		local pts = tracePath(E, start, dir, a.Length, a.Bounces, a.Radius)
		for j = 1, 4 do
			setSlot(E, (k - 1) * 4 + j, pts[math.min(j, #pts)])
		end
		addShot(E, pts, showAt + a.Tell, a.Speed, a.Radius, a.Height, a.Damage, a.Knockback)
	end
	E.track = false
	return waitUntil(E, token, t0 + a.Show + (n - 1) * a.Gap + a.Tell + 0.4)
end

-- PRICKLY BUDDIES: he shakes and little cactus buddies hop off him; they
-- waddle after you and pop into needles if they reach you
function Attacks.Buddies(E, token)
	local a = E.def.Attacks.Buddies
	E.track, E.chase = true, false
	local t0 = begin(E, "Buddies", nil)
	if not waitUntil(E, token, t0 + 0.5) then
		return false
	end
	local n = math.min(byRage(E, a.Spawn), byRage(E, a.Max) - count(E, "Buddy"))
	for k = 1, n do
		local dir = rotateY(E.facing, (k - (n + 1) / 2) * 0.7)
		local from = ground(E) + dir * 4
		local to = inside(E, clearOfRocks(E, ground(E) + dir * 10, 2), E.fightR - 4)
		spawnBuddy(E, from, to, t0 + 0.5)
	end
	E.track = false
	return waitUntil(E, token, t0 + 0.5 + a.Land)
end

-- QUICKSAND: he stomps and swirling patches of sand open up between you and
-- him (the oldest go if there'd be too many)
function Attacks.Quicksand(E, token)
	local a = E.def.Attacks.Quicksand
	E.track, E.chase = true, false
	local t0 = begin(E, "Quicksand", nil)
	if not waitUntil(E, token, t0 + 0.4) then
		return false
	end
	local aim = targetPosition(E) or ground(E)
	local n = byRage(E, a.Patches)
	local spare = byRage(E, a.Max) - count(E, "Sand")
	for _, q in ipairs(E.propList) do
		if spare >= n then
			break
		end
		if q.kind == "Sand" and not q.gone then
			endProp(E, q, "Wither")
			spare = spare + 1
		end
	end
	for k = 1, n do
		local spot = ground(E):Lerp(aim, k / (n + 1))
		spot = inside(E, clearOfRocks(E, spot, 2), E.fightR - 6)
		local warnAt = t0 + 0.4
		spawnSand(E, spot, a.Radius, warnAt, warnAt + a.Warn, warnAt + a.Warn + a.Life)
	end
	E.track = false
	return waitUntil(E, token, t0 + 0.4 + a.Warn)
end

----------------------------------------------------------------------
-- His brain
----------------------------------------------------------------------
local KIND_OF = { Wall = "Wall", Turrets = "Turret", Buddies = "Buddy", Quicksand = "Sand" }

-- A weighted pick among this round's moves that suit the distance. The same
-- move is less likely twice running and never three times; he won't make
-- more walls, turrets, buddies or quicksand than he's allowed at once.
local function choose(E, dist, round)
	local options, total = {}, 0
	local t = now()
	for name, a in pairs(E.def.Attacks) do
		if (a.Phase or 1) == round and Attacks[name] then
			local w = a.Weight or 0
			if dist < a.Range[1] or dist > a.Range[2] then
				w = 0
			end
			if a.Max and KIND_OF[name] and count(E, KIND_OF[name]) >= byRage(E, a.Max) then
				w = 0
			end
			if (name == "Wall" or name == "Turrets") and t < (E.noCactiUntil or 0) then
				w = 0 -- (stunned a moment ago: out of cactus)
			end
			if E.history[1] == name then
				w = (E.history[2] == name) and 0 or w * 0.4
			end
			if w > 0 then
				options[#options + 1] = { name, w }
				total = total + w
			end
		end
	end
	table.sort(options, function(x, y)
		return x[1] < y[1] -- a stable order, so the pick depends only on the roll
	end)
	if total <= 0 then
		return nil
	end
	local roll = E.rng:NextNumber() * total
	for _, o in ipairs(options) do
		roll = roll - o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return options[#options][1]
end

-- waits until `t`, but gives up early if anyone comes close (he reacts)
local function watchUntil(E, token, t)
	local trigger = E.def.Moves.RootHop.Trigger
	while now() < t do
		if not valid(E, token) then
			return false
		end
		for _, p in ipairs(fightersIn(E)) do
			local root = rootOf(p)
			if root and flatDistance(root.Position, E.pos) <= trigger then
				return true
			end
		end
		task.wait()
	end
	return valid(E, token)
end

local function tuberTurn(E, token, aim)
	local d = flatDistance(aim, E.pos)
	local S = E.def.Attacks.Split
	local name
	if (E.sinceSplit or 0) >= S.Every and d >= S.Range[1] and d <= S.Range[2] then
		name = "Split"
	else
		name = choose(E, d, 1)
	end
	if not name then
		-- nothing reaches from here: waddle closer and think again
		E.chase, E.track = true, true
		waitUntil(E, token, now() + 0.35)
		E.chase = false
		return valid(E, token)
	end
	E.history = { name, E.history[1] }
	Attacks[name](E, token)
	if not valid(E, token) then
		return false
	end
	E.sinceSplit = (name == "Split") and 0 or (E.sinceSplit or 0) + 1
	-- a breather: waddling after you
	local b = E.def.Breather[1]
	E.chase, E.track = true, true
	setAction(E, "Idle", nil)
	waitUntil(E, token, now() + b[1] + E.rng:NextNumber() * (b[2] - b[1]))
	E.chase = false
	return valid(E, token)
end

local function bruteTurn(E, token, aim)
	local M = E.def.Moves
	local d = flatDistance(aim, E.pos)
	if d <= M.RootHop.Trigger then
		-- you're right on top of him
		if now() >= (E.hopReadyAt or 0) then
			Moves.RootHop(E, token)
		elseif now() >= (E.corneredReadyAt or 0) then
			Moves.Cornered(E, token)
		else
			Moves.ShoveBurst(E, token)
		end
		return valid(E, token)
	end
	local name = choose(E, d, 2)
	if not name then
		E.track = true
		watchUntil(E, token, now() + 0.4)
		return valid(E, token)
	end
	E.history = { name, E.history[1] }
	Attacks[name](E, token)
	if not valid(E, token) then
		return false
	end
	-- a breather: turning to face you, watching for anyone coming close
	local b = E.rage and E.def.RageBreather or E.def.Breather[2]
	E.track = true
	setAction(E, "Idle", nil)
	watchUntil(E, token, now() + b[1] + E.rng:NextNumber() * (b[2] - b[1]))
	return valid(E, token)
end

-- One go round: think, move, breathe. Returns false once this fight is over
-- (reset, killed, or the power-up has taken over).
local function cycle(E, token)
	if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
		if not breakShell(E, token) then
			return false
		end
	end
	if E.phase >= 2 then
		if E.pendingHop then
			-- (round 2 starts with him leaping away from you)
			E.pendingHop = false
			Moves.RootHop(E, token)
			return valid(E, token)
		end
		if E.pendingStun then
			E.pendingStun = false
			Moves.Stunned(E, token)
			return valid(E, token)
		end
		if not E.raged and bruteShare(E) <= E.def.Moves.Rage.At + 1e-6 then
			E.raged = true
			Moves.Rage(E, token)
			return valid(E, token)
		end
	end
	local target = pickTarget(E)
	local aim = target and targetPosition(E)
	if not aim then
		E.chase, E.track = false, false
		task.wait(0.25)
		return valid(E, token)
	end
	if E.phase >= 2 then
		return bruteTurn(E, token, aim)
	end
	return tuberTurn(E, token, aim)
end

-- Tuber's fight: round and round the cycle, each go protected (an error in
-- one move is reported once and he carries on with the next)
function Boss.brain(E, token)
	if E.phase == 1 then
		-- a fresh fight (not again after the power-up: the brain starts over then)
		E.sinceSplit = 0
		E.history = {}
		E.rage, E.raged = false, false
	end
	while valid(E, token) and E.state ~= "Dead" do
		local ok, result = pcall(cycle, E, token)
		if not ok then
			if not E.warnedError then
				E.warnedError = true
				warn("[BossService] " .. E.def.Short .. " hit an error and carried on: " .. tostring(result))
			end
			settle(E)
			task.wait(0.3)
		elseif not result then
			return
		end
	end
end

----------------------------------------------------------------------
-- Every frame: where he is, and everything he's thrown or planted hurting
-- people (only while the fight's on - not during the power-up)
----------------------------------------------------------------------
function Boss.step(E, dt)
	local t = now()
	if E.split then
		stepSplit(E, t)
	else
		stepMovement(E, dt)
	end
	if E.state ~= "Fighting" then
		return
	end
	stepWaves(E)
	stepPuddles(E)
	stepShots(E, t)
	stepDrops(E, t)
	stepProps(E, t, dt)
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	hitArea, targetPosition, healthShare, knockbackFrom = kit.hitArea, kit.targetPosition, kit.healthShare, kit.knockbackFrom
	pickTarget, breakShell, stepMovement, place = kit.pickTarget, kit.breakShell, kit.stepMovement, kit.place
	stepWaves, stepPuddles = kit.stepWaves, kit.stepPuddles
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

-- everything thrown, planted or split, gone (and nothing left to hurt anyone)
local function tidy(E, kind)
	settle(E)
	E.shots, E.drops = {}, {}
	clearProps(E, kind)
	E.pendingHop, E.pendingStun = false, false
end

local function warnOnce(E, what, err)
	if not E.warnedHook then
		E.warnedHook = true
		warn("[BossService] " .. E.def.Short .. " " .. what .. " failed: " .. tostring(err))
	end
end

-- Built: the arena found (DunesBuilder's model: its middle, its edge, its
-- rocks), and CombatService told where his body really is
function Boss.onBuild(E)
	local arena = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == E.floor and child:GetAttribute("FightRadius") then
			arena = child
		end
	end
	local c = arena and arena:GetAttribute("Center")
	E.center = typeof(c) == "Vector3" and atFloor(E, c) or E.home
	E.fightR = (arena and arena:GetAttribute("FightRadius")) or 150
	E.edgeR = E.fightR - 6 -- (where rolling balls bounce off the rim)
	E.rocks = findRocks(E)
	local old = Workspace:FindFirstChild("TuberProps")
	if old then
		old:Destroy()
	end
	E.propList, E.propId = {}, 0
	E.shots, E.drops = {}, {}
	propFolder(E)
	setForm(E, "Stack")
	E.model:SetAttribute("Rage", false)
	CombatService.SetTargetShape(E.model, function(from)
		return aimPoint(E, from)
	end)
end

-- Everyone left or died: everything he threw or planted goes
function Boss.onReset(E)
	local ok, err = pcall(tidy, E, "Gone")
	if not ok then
		warnOnce(E, "reset", err)
	end
end

-- Home again: little Tuber, asleep in his garden
function Boss.onHome(E)
	local ok, err = pcall(function()
		tidy(E, "Gone")
		setForm(E, "Stack")
		E.rage, E.raged = false, false
		E.model:SetAttribute("Rage", false)
		E.model:SetAttribute("HopAt", nil)
	end)
	if not ok then
		warnOnce(E, "going home", err)
	end
end

-- THE POWER-UP: whatever he was doing, it's over - he's one little Tuber
-- again (split up, his buddies hop back together), the round-1 mess cleared
-- away - and he becomes THE BRUTE (BossBodies/Tuber draws the whole show).
-- Round 2 opens with a Root Hop, away from you.
function Boss.onBreak(E)
	local ok, err = pcall(function()
		tidy(E, "Wither")
		E.waves, E.puddles = {}, {}
		setForm(E, "Brute")
		local t = now()
		E.pendingHop = true
		E.hopReadyAt = t + E.def.BreakTime
		E.corneredReadyAt = t + E.def.BreakTime + 4
		E.brokenSinceStun = 0
		E.noCactiUntil = 0
		E.rage, E.raged = false, false
		E.history = {}
		E.model:SetAttribute("HopAt", E.hopReadyAt)
		E.model:SetAttribute("Rage", false)
	end)
	if not ok then
		warnOnce(E, "power-up", err)
	end
end

function Boss.onDie(E)
	local ok, err = pcall(tidy, E, "Wither")
	if not ok then
		warnOnce(E, "death", err)
	end
end

-- (for tests and BossBodies: the same sums, and a way to tidy up between moves)
Boss.arcHeight = arcHeight
Boss._setForm = setForm
Boss._tidy = tidy
Boss._tracePath = tracePath
Boss._pathLength = pathLength
Boss._pointAlong = pointAlong
Boss._hopSpot = hopSpot
Boss._aimPoint = aimPoint
Boss._splitPos = splitPos

return Boss
