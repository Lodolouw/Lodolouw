--[[
	Scribble  (ModuleScript, parent: ServerScriptService > Bosses, name: "Scribble")

	Floor 9's boss: Scribble, the 4th-Dimensional Doodle (Config.Bosses[9]) -
	a stick figure drawn in blue pen who knows he's inside a video game, so
	he fights with the game itself. He's fast and tricky. Three rounds:

	 ROUND 1, "DOODLE" (the drawing tools):
	  PENCIL DASH    a dotted line draws itself across the paper through you,
	                 then he rockets along it. Get off the line! He skids at
	                 the end: hit him.
	  ERASER SWEEP   a pink strip across the paper glows under you, then a
	                 giant eraser rubs it out for a few seconds. Get off it.
	  PAINT BUCKET   the grid square you're in outlines and drips, then floods
	                 with paint. Leave the square.
	  COPY-PASTE     "CTRL+C... CTRL+V!" - two ink copies of him peel off and
	                 chase you. A punch or two pops one.
	  UNDO           a giant Z key pops up in front of you. Punch it in time
	                 and he's stunned; miss it and "CTRL+Z!" - he undoes your
	                 last few hits.
	 ROUND 2, "BREAKING THE 4TH WALL" (at PhaseAt: he tears himself out of the
	 paper, red marker now, and your SCREEN becomes his weapon):
	  THE CURSOR     a giant mouse pointer's shadow hunts you across the paper,
	                 freezes, and clicks there. Roll!
	  BOSS BAR WHIP  he rips his own health bar off your screen and swings it
	                 round himself as a giant red whip. Jump it!
	  ERROR POP-UPS  ERROR, 404 and LAG windows drop out of the sky onto their
	                 shadows and stand there as walls, then shatter.
	  LAG SPIKE      "LAG!" - ghosts of him in a line to you, then he skips
	                 from ghost to ghost. Get off them.
	 ROUND 3, "DELETE" (at Round3At: he glitches into rainbow colours):
	  every few seconds a giant box pops up at the edge of the paper -
	  "Delete FLOOR 9? YES / NO" - with a countdown, while the paper is
	  erased from the edges in. Punch NO and he CRASHES (dizzy: the big
	  damage window). Miss it and everyone takes a big hit (never a killing
	  one) and the paper stays smaller. Meanwhile he fights on with rounds
	  1 and 2's moves (all but copy-paste and undo). Erased paper hurts.
	  At the end he's crumpled into a paper ball and thrown in the recycle
	  bin (his body file does that).

	HIS BRAIN is the shared surface-boss brain with a third round
	(Boss.brain below): pick a move that suits the distance, do it, breathe,
	drift after you. His every-frame step (Boss.step) runs the things he
	leaves about: the clones, the eraser strips and wet paint, the DELETE
	box, the erased edge.

	PUNCHABLE PROPS live in Workspace.ScribbleProps, each a Model with Kind,
	Id, Floor, Born (and EndKind / EndAt when it goes):
	  "Clone"     an ink copy of him (InkClone). It moves (its pivot is where
	              it is); per swipe: SwipeWarn (it winds up), SwipeAt (it
	              slashes), SwipeDir, SwipeId. EndKind Broken / Smudge / Gone.
	  "UndoKey"   the Z key. Until = when the undo happens if it's still
	              there. EndKind Broken (he's stunned) / Undo / Gone.
	  "NoButton"  the DELETE box's NO button (DeleteBox). Side (1-4: north,
	              east, south, west - see CanvasPlan.promptSpots), To (the
	              paper's edge it's erasing to), Until (when the countdown
	              runs out). EndKind Pressed / Yes / Gone.

	ON HIS MODEL: Paper (how far out the paper is still solid each way),
	EraseTo / EraseStart / EraseEnd (round 3: the edge creeping in while a
	DELETE box is up - CanvasPlan.paperAt), Cursor (where the cursor's
	shadow is while it hunts, ten times a second).

	EACH MOVE publishes its name and start time (setAction, a number in ActN)
	and the spots it fills in as it goes (setSlot) - each move below says
	which slot is what. The paper's shape is ReplicatedStorage/CanvasPlan, so
	every screen draws exactly what hits you.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CanvasPlan = require(ReplicatedStorage:WaitForChild("CanvasPlan"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setState, setAction, setSlot, place, waitUntil, valid, hitArea, recovery, targetPosition, knockbackFrom
local pickTarget, healthShare, breakShell, stepMovement
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setState, setAction, setSlot, place = kit.setState, kit.setAction, kit.setSlot, kit.place
	waitUntil, valid, hitArea, recovery = kit.waitUntil, kit.valid, kit.hitArea, kit.recovery
	targetPosition, knockbackFrom = kit.targetPosition, kit.knockbackFrom
	pickTarget, healthShare, breakShell, stepMovement = kit.pickTarget, kit.healthShare, kit.breakShell, kit.stepMovement
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

local X_AXIS = Vector3.new(1, 0, 0)
local Z_AXIS = Vector3.new(0, 0, 1)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a number for this round: a { round 1, round 2, round 3 } list, or just a number
local function perRound(E, v)
	if type(v) == "table" then
		return v[math.min(E.phase, #v)]
	end
	return v
end

-- how far out the paper is still solid right now (each way from the middle)
local function paperNow(E, t)
	return CanvasPlan.paperAt(E.paper, E.eraseTo, E.eraseStart, E.eraseEnd, t or now())
end

-- a spot pulled onto the solid paper, `margin` in from its edge, on the floor
local function inside(E, pos, margin)
	local off = pos - E.home
	local x, z = CanvasPlan.inside(off.X, off.Z, paperNow(E), margin or 0)
	return Vector3.new(E.home.X + x, E.floorY, E.home.Z + z)
end

-- a spot near someone: `spread` studs round `pos`, at random
local function near(E, pos, spread)
	local a = E.rng:NextNumber() * math.pi * 2
	local r = math.sqrt(E.rng:NextNumber()) * spread
	return pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- how high off the floor someone is (standing on the paper: about 0)
local function above(E, root)
	return root.Position.Y - (E.floorY + STAND_HEIGHT)
end

-- is `pos` inside a flat box: middle `c`, long way `ax` (a flat unit
-- vector), `hl` out along it and `hw` out across it?
local function inBox(pos, c, ax, hl, hw)
	local d = flat(pos - c)
	local across = Vector3.new(-ax.Z, 0, ax.X)
	return math.abs(d:Dot(ax)) <= hl and math.abs(d:Dot(across)) <= hw
end

-- Everyone standing in a flat box takes the hit once, thrown out of it
-- sideways (or, `radial`, straight out from its middle: a square)
local function hitBox(E, c, ax, hl, hw, damage, knockback, already, radial)
	local landed = 0
	for _, p in ipairs(fightersIn(E)) do
		if not (already and already[p]) then
			local root = rootOf(p)
			if root and inBox(root.Position, c, ax, hl + PLAYER_RADIUS, hw + PLAYER_RADIUS) then
				if already then
					already[p] = true
				end
				local d = flat(root.Position - c)
				local out
				if radial then
					out = unitOr(d, Vector3.new(0, 0, 1))
				else
					local across = Vector3.new(-ax.Z, 0, ax.X)
					out = (d:Dot(across) >= 0) and across or -across
				end
				local kb = out * (knockback or 0) + Vector3.new(0, (knockback or 0) * 0.35, 0)
				if CombatService.DamagePlayer(p, damage, root.Position - out * 2, kb) then
					landed = landed + 1
				end
			end
		end
	end
	return landed
end

-- how much damage the last `hits` hits on him did (only ones in the last
-- `memory` seconds)
local function recentDamage(E, memory, hits)
	local t = now()
	local sum, n = 0, 0
	for i = #E.recent, 1, -1 do
		local h = E.recent[i]
		if t - h.t > memory or n >= hits then
			break
		end
		sum = sum + h.dmg
		n = n + 1
	end
	return sum
end

-- gives him back `amount` health (never past the top of this round's share
-- of his bar). Returns how much he really got back.
local function heal(E, amount)
	local m = E.model
	local max = m:GetAttribute("MaxHealth") or 1
	local ceiling = max
	if E.phase >= 2 then
		ceiling = math.floor(max * E.def.PhaseAt)
	end
	local hp = m:GetAttribute("Health") or 0
	local new = math.min(ceiling, hp + math.floor(amount))
	if new > hp then
		m:SetAttribute("Health", new)
		return new - hp
	end
	return 0
end

-- punches at this floor's recommended power it takes to break a prop
local function propHealth(E, punches)
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	return math.max(1, math.floor(rec * punches))
end

----------------------------------------------------------------------
-- Props you can punch (Workspace.ScribbleProps)
----------------------------------------------------------------------
local function propFolder(E)
	if not (E.folder and E.folder.Parent) then
		local f = Workspace:FindFirstChild("ScribbleProps")
		if not f then
			f = Instance.new("Folder")
			f.Name = "ScribbleProps"
			f.Parent = Workspace
		end
		E.folder = f
	end
	return E.folder
end

-- A new prop at `spot` (on the floor), its middle `up` studs higher. With
-- `hp` it can be punched (tagged CombatTarget by whoever made it, once
-- it's ready). Returns the model and its OnHit event.
local function newProp(E, kind, name, spot, up, hp, radius)
	E.propId = (E.propId or 0) + 1
	local model = Instance.new("Model")
	model.Name = name
	local hit = Instance.new("Part")
	hit.Name = "Hit"
	hit.Size = Vector3.new(3, 4, 3)
	hit.CFrame = CFrame.new(spot + Vector3.new(0, up, 0))
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanQuery = false
	hit.CanTouch = false
	hit.CastShadow = false
	hit.Parent = model
	model.PrimaryPart = hit
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Id", E.propId)
	model:SetAttribute("Floor", E.floor)
	model:SetAttribute("Born", now())
	if hp then
		model:SetAttribute("MaxHealth", hp)
		model:SetAttribute("Health", hp)
		model:SetAttribute("HitRadius", radius or 2)
		model:SetAttribute("NoBar", true)
		model:SetAttribute("StudioFair", true)
		model:SetAttribute("DisplayName", name)
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- (every screen has it, to lock on)
	end)
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = model
	model.Parent = propFolder(E)
	return model, onHit
end

-- a prop's end: `kind` says how (the screens show it), and it's gone soon after
local function endProp(prop, kind)
	if not prop or prop.gone then
		return
	end
	prop.gone = true
	local model = prop.model
	CollectionService:RemoveTag(model, "CombatTarget")
	model:SetAttribute("EndKind", kind)
	model:SetAttribute("EndAt", now())
	task.delay(0.9, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- The ink clones (COPY-PASTE)
----------------------------------------------------------------------
local function liveClones(E)
	local n = 0
	for _, c in ipairs(E.clones) do
		if not c.gone then
			n = n + 1
		end
	end
	return n
end

local function spawnClone(E, spot)
	local a = E.def.Attacks.CopyPaste
	-- too many already: the oldest smudges away to make room
	while liveClones(E) >= a.Max do
		for _, c in ipairs(E.clones) do
			if not c.gone then
				endProp(c, "Smudge")
				break
			end
		end
	end
	local model, onHit = newProp(E, "Clone", "InkClone", spot, 2.5, propHealth(E, a.Punches), 2.2)
	local c = { model = model, pos = spot, dir = E.facing, dieAt = now() + a.Life, nextSwipe = now() + 0.8, swipeId = 0 }
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 then
			endProp(c, "Broken")
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	table.insert(E.clones, c)
	return c
end

-- every frame: each clone chases whoever's nearest, and swipes when close
local function stepClones(E, t, dt, list)
	if #E.clones == 0 then
		return
	end
	local a = E.def.Attacks.CopyPaste
	for i = #E.clones, 1, -1 do
		local c = E.clones[i]
		if c.gone then
			table.remove(E.clones, i)
		elseif t >= c.dieAt then
			endProp(c, "Smudge")
		elseif c.swipeAt then
			if t >= c.swipeAt then
				-- SLASH
				hitArea(E, c.pos + c.swipeDir * 2, a.Reach, a.Damage, a.Knockback)
				c.swipeAt = nil
				c.nextSwipe = t + a.Rest
			end
		else
			local best, bestD = nil, math.huge
			for _, p in ipairs(list) do
				local root = rootOf(p)
				if root then
					local d = flatDistance(root.Position, c.pos)
					if d < bestD then
						best, bestD = root, d
					end
				end
			end
			if best then
				c.dir = unitOr(flat(best.Position - c.pos), c.dir)
				if bestD <= a.Reach + 0.5 and t >= c.nextSwipe then
					-- close enough: wind up a swipe (it can't move while it does)
					c.swipeId = c.swipeId + 1
					c.swipeDir = c.dir
					c.swipeAt = t + a.SwipeTell
					local m = c.model
					m:SetAttribute("SwipeDir", c.swipeDir)
					m:SetAttribute("SwipeWarn", t)
					m:SetAttribute("SwipeAt", c.swipeAt)
					m:SetAttribute("SwipeId", c.swipeId)
				elseif bestD > 2.6 then
					c.pos = inside(E, c.pos + c.dir * math.min(a.Speed * dt, bestD - 2.6), 2)
				end
			end
		end
	end
	-- the clones never stand in each other, and they're where they are
	for i, c in ipairs(E.clones) do
		if not c.gone then
			for j = i + 1, #E.clones do
				local o = E.clones[j]
				if not o.gone then
					local d = flat(c.pos - o.pos)
					if d.Magnitude < 3 then
						local push = unitOr(d, X_AXIS) * (3 - d.Magnitude) / 2
						c.pos = inside(E, c.pos + push, 2)
						o.pos = inside(E, o.pos - push, 2)
					end
				end
			end
			local at = c.pos + Vector3.new(0, 2.5, 0)
			c.model:PivotTo(CFrame.lookAt(at, at + c.dir))
		end
	end
end

----------------------------------------------------------------------
-- Things that hurt to stand in: the eraser's strips, wet paint, and
-- (round 3) the erased edge of the paper
----------------------------------------------------------------------
-- a flat box that stings anyone standing in it, `damage` every `tick`
-- seconds, from `from` until `till`
local function addZone(E, c, ax, hl, hw, from, till, damage, tick)
	table.insert(E.zones, { c = c, ax = ax, hl = hl, hw = hw, from = from, till = till, damage = damage, tick = tick })
end

local function stepZones(E, t, list)
	if #E.zones == 0 then
		return
	end
	for i = #E.zones, 1, -1 do
		if t > E.zones[i].till then
			table.remove(E.zones, i)
		end
	end
	for _, p in ipairs(list) do
		local root = rootOf(p)
		if root and above(E, root) < 2.5 then
			for _, z in ipairs(E.zones) do
				if t >= z.from and inBox(root.Position, z.c, z.ax, z.hl + 0.5, z.hw + 0.5) then
					if t - (E.zoneAt[p] or -math.huge) >= z.tick then
						E.zoneAt[p] = t
						CombatService.DamagePlayer(p, z.damage, root.Position, nil, true)
					end
					break -- one zone's worth, however many you're in
				end
			end
		end
	end
end

-- Standing on erased paper stings, and nudges you back onto the paper
local function stepEdge(E, t, list)
	local half = paperNow(E, t)
	if half >= CanvasPlan.Half - 0.01 then
		return
	end
	local d = E.def.Delete
	for _, p in ipairs(list) do
		local root = rootOf(p)
		if root and above(E, root) < 3 then
			local off = root.Position - E.home
			if not CanvasPlan.onPaper(off.X, off.Z, half) and t - (E.edgeAt[p] or -math.huge) >= d.EdgeTick then
				E.edgeAt[p] = t
				local back = unitOr(flat(-off), Z_AXIS)
				CombatService.DamagePlayer(p, d.EdgeDamage, root.Position - back * 2, back * 26 + Vector3.new(0, 10, 0), true)
			end
		end
	end
end

-- the paper's edge as it is now, for every screen
local function publishPaper(E)
	local m = E.model
	m:SetAttribute("Paper", E.paper)
	m:SetAttribute("EraseTo", E.eraseTo)
	m:SetAttribute("EraseStart", E.eraseStart)
	m:SetAttribute("EraseEnd", E.eraseEnd)
end

local function resetPaper(E)
	E.paper = CanvasPlan.Half
	E.eraseTo, E.eraseStart, E.eraseEnd = nil, nil, nil
	E.nextPrompt = nil
	publishPaper(E)
end

----------------------------------------------------------------------
-- The moves (Config.Bosses[9].Attacks - the names must match)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- PENCIL DASH. setAction's number = how many dashes. Slot 2k - 1 = where
-- dash k starts, slot 2k = where it ends. Dash 1 starts at Tell; each dash
-- takes max(0.12, its length / Speed) seconds, and the next starts Chain
-- seconds after it ends (its line appears the moment the one before ends).
-- After the last he skids (Skid seconds): hit him!
function Attacks.PencilDash(E, token)
	local a = E.def.Attacks.PencilDash
	local count = perRound(E, a.Count)
	E.track = true
	local t0 = setAction(E, "PencilDash", count)
	local from = E.pos
	local startAt = t0 + a.Tell
	for k = 1, count do
		-- the line: from him, through you, Past studs beyond (kept on the paper)
		local aim = targetPosition(E) or (from + E.facing * 30)
		local dir = unitOr(flat(aim - from), E.facing)
		local to = inside(E, from + dir * (flatDistance(aim, from) + a.Past), 6)
		setSlot(E, 2 * k - 1, from)
		setSlot(E, 2 * k, to)
		if not waitUntil(E, token, startAt) then
			return
		end
		-- WHOOSH: along the line as a streak of ink
		E.track = false
		E.facing = unitOr(flat(to - from), E.facing)
		local travel = math.max(0.12, flatDistance(to, from) / a.Speed)
		E.motion = { from = from, to = to, t0 = startAt, t1 = startAt + travel }
		E.sweep = { radius = a.Width / 2 + 0.5, damage = a.Damage, knockback = a.Knockback, hit = {} }
		if not waitUntil(E, token, startAt + travel) then
			return
		end
		E.motion, E.sweep = nil, nil
		E.pos = to
		from = to
		startAt = startAt + travel + a.Chain
		E.track = true
	end
	E.track = false
	-- the skid: wide open
	waitUntil(E, token, now() + recovery(E, a.Skid))
end

-- ERASER SWEEP. setAction's number = how many strips. Strip k: slot 2k - 1
-- is its middle and slot 2k a point 10 studs along it (the way it runs:
-- east-west or north-south, right across the paper). It's rubbed out from
-- Tell for Time seconds.
function Attacks.EraserSweep(E, token)
	local a = E.def.Attacks.EraserSweep
	local strips = perRound(E, a.Strips)
	E.track = true
	local t0 = setAction(E, "EraserSweep", strips)
	local aim = inside(E, targetPosition(E) or (E.pos + E.facing * 20), 0)
	-- the first strip runs across the way from him to you (it cuts you off);
	-- the second (later rounds) crosses it, through you too
	local toYou = flat(aim - E.pos)
	local firstAlongX = math.abs(toYou.Z) >= math.abs(toYou.X)
	local list = {}
	for k = 1, strips do
		local alongX = (k % 2 == 1) == firstAlongX
		local ax = alongX and X_AXIS or Z_AXIS
		local c = alongX and Vector3.new(E.home.X, E.floorY, aim.Z) or Vector3.new(aim.X, E.floorY, E.home.Z)
		setSlot(E, 2 * k - 1, c)
		setSlot(E, 2 * k, c + ax * 10)
		list[k] = { c = c, ax = ax }
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local half = paperNow(E)
	for _, s in ipairs(list) do
		hitBox(E, s.c, s.ax, half, a.Width / 2, a.Damage, a.Knockback)
		addZone(E, s.c, s.ax, half, a.Width / 2, t0 + a.Tell + 0.5, t0 + a.Tell + a.Time, a.TickDamage, a.Tick)
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- PAINT BUCKET. setAction's number = how many squares. Slot k = the middle
-- of square k (a big grid square: CanvasPlan.Cell across; the first is the
-- one you're in, the rest its neighbours). They flood at Tell, and stay wet
-- for Wet seconds.
function Attacks.PaintBucket(E, token)
	local a = E.def.Attacks.PaintBucket
	local n = perRound(E, a.Squares)
	E.track = true
	local t0 = setAction(E, "PaintBucket", n)
	local aim = targetPosition(E) or (E.pos + E.facing * 16)
	local off = aim - E.home
	local cx, cz = CanvasPlan.cellOf(off.X, off.Z)
	local cells = { { cx, cz } }
	local size = CanvasPlan.Cell
	local lim = CanvasPlan.Half - size / 2
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }
	for i = #dirs, 2, -1 do
		local j = E.rng:NextInteger(1, i)
		dirs[i], dirs[j] = dirs[j], dirs[i]
	end
	for _, d in ipairs(dirs) do
		if #cells >= n then
			break
		end
		local x, z = cx + d[1] * size, cz + d[2] * size
		if math.abs(x) <= lim and math.abs(z) <= lim then
			table.insert(cells, { x, z })
		end
	end
	for k, c in ipairs(cells) do
		setSlot(E, k, Vector3.new(E.home.X + c[1], E.floorY, E.home.Z + c[2]))
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local h = size / 2
	for _, c in ipairs(cells) do
		local mid = Vector3.new(E.home.X + c[1], E.floorY, E.home.Z + c[2])
		hitBox(E, mid, X_AXIS, h, h, a.Damage, a.Knockback, nil, true)
		addZone(E, mid, X_AXIS, h, h, t0 + a.Tell + 0.5, t0 + a.Tell + a.Wet, a.WetDamage, a.Tick)
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- COPY-PASTE. setAction's number = how many clones. Slot k = where clone k
-- appears, at Tell (then it's a prop: see stepClones).
function Attacks.CopyPaste(E, token)
	local a = E.def.Attacks.CopyPaste
	E.track = true
	local t0 = setAction(E, "CopyPaste", a.Clones)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local side = Vector3.new(-E.facing.Z, 0, E.facing.X)
	for k = 1, a.Clones do
		local s = (k % 2 == 1) and 1 or -1
		local spot = inside(E, E.pos + side * (s * 5) + E.facing * 2, 3)
		setSlot(E, k, spot)
		spawnClone(E, spot)
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- UNDO. setAction's number = Window. Slot 1 = where the Z key pops up (at
-- Tell; then it's a prop, UndoKey, until Tell + Window). Broken: the action
-- "Stunned" (its number = Stun seconds). Not broken: "Undone" (its number
-- = how much of his bar he got back).
function Attacks.Undo(E, token)
	local a = E.def.Attacks.Undo
	E.track = true
	E.lastUndo = now()
	local t0 = setAction(E, "Undo", a.Window)
	-- the key: between him and you, a few studs in front of you
	local aim = targetPosition(E) or (E.pos + E.facing * 12)
	local toHim = unitOr(flat(E.pos - aim), -E.facing)
	local spot = inside(E, aim + toHim * math.min(6, flatDistance(aim, E.pos) * 0.5), 3)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local untilT = t0 + a.Tell + a.Window
	local model, onHit = newProp(E, "UndoKey", "UndoKey", spot, 3.4, propHealth(E, a.Punches), 2.6)
	model:SetAttribute("Until", untilT)
	local key = { model = model }
	local broken = false
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 and not key.gone then
			broken = true
			endProp(key, "Broken")
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	E.key = key
	while now() < untilT and not broken do
		if not valid(E, token) then
			if E.key == key then
				endProp(key, "Gone")
				E.key = nil
			end
			return
		end
		task.wait()
	end
	E.key = nil
	if broken then
		-- the key's broken: he's STUNNED, wide open
		local t1 = setAction(E, "Stunned", a.Stun)
		waitUntil(E, token, t1 + a.Stun)
	else
		-- CTRL+Z: your last few hits are undone
		endProp(key, "Undo")
		local max = E.model:GetAttribute("MaxHealth") or 1
		local healed = heal(E, math.min(recentDamage(E, a.Memory, a.Hits), max * a.Max))
		E.recent = {}
		local t1 = setAction(E, "Undone", healed / math.max(max, 1))
		waitUntil(E, token, t1 + 0.9)
	end
end

-- THE CURSOR. setAction's number = how many clicks. Click k happens at
-- Hunt + Lock + (k - 1) * (Hunt2 + Lock); its shadow freezes Lock seconds
-- before, and slot k is published then: where it clicks. While it hunts,
-- the model's Cursor attribute follows it (ten times a second).
function Attacks.Cursor(E, token)
	local a = E.def.Attacks.Cursor
	local clicks = perRound(E, a.Clicks)
	E.track = true
	local t0 = setAction(E, "Cursor", clicks)
	local target = E.target
	local root = target and rootOf(target)
	-- it swoops in from above him, toward you
	local pos = inside(E, root and root.Position or (E.pos + E.facing * 15), 0)
	pos = inside(E, pos:Lerp(E.pos, 0.35), 0)
	local m = E.model
	m:SetAttribute("Cursor", pos)
	local lastPublish, last = now(), now()
	for k = 1, clicks do
		local clickAt = t0 + a.Hunt + a.Lock + (k - 1) * (a.Hunt2 + a.Lock)
		local lockAt = clickAt - a.Lock
		-- hunting: the shadow follows them across the paper
		while now() < lockAt do
			if not valid(E, token) then
				m:SetAttribute("Cursor", nil)
				return
			end
			local tn = now()
			local dt = math.clamp(tn - last, 0, 0.2)
			last = tn
			local r = target and rootOf(target)
			if r then
				local want = flat(r.Position - pos)
				if want.Magnitude > 0.05 then
					pos = pos + want.Unit * math.min(want.Magnitude, a.Speed * dt)
				end
			end
			pos = inside(E, pos, 0)
			if tn - lastPublish >= 0.1 then
				lastPublish = tn
				m:SetAttribute("Cursor", pos)
			end
			task.wait()
		end
		-- locked: here it clicks
		setSlot(E, k, pos)
		m:SetAttribute("Cursor", pos)
		if not waitUntil(E, token, clickAt) then
			m:SetAttribute("Cursor", nil)
			return
		end
		-- CLICK: anyone under it is grabbed and flung
		hitArea(E, pos, a.Radius, a.Damage, a.Fling)
		last = now()
	end
	m:SetAttribute("Cursor", nil)
	E.track = false
	waitUntil(E, token, now() + recovery(E, a.Recovery))
end

-- is angle `phi` between angles a and b (b a little way on from a, either way)?
local function swept(a, b, phi)
	local step = b - a
	local tau = math.pi * 2
	if step >= 0 then
		return (phi - a) % tau <= step
	end
	return (a - phi) % tau <= -step
end

-- BOSS BAR WHIP. setAction's number = turns, signed (+ one way round, -
-- the other). Slot 1 = the bar's tip at the start of the spin (published at
-- Tell). The spin starts at Tell and takes |turns| * Spin seconds, round
-- the spot he's standing on. The bar is Length long and low: jump it.
function Attacks.BarWhip(E, token)
	local a = E.def.Attacks.BarWhip
	local turns = perRound(E, a.Turns)
	local dir = (E.rng:NextNumber() < 0.5) and 1 or -1
	E.track = true
	local t0 = setAction(E, "BarWhip", dir * turns)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	-- it starts a quarter turn back from you, so it swings AT you first
	local aim = targetPosition(E) or (E.pos + E.facing * 10)
	local toYou = unitOr(flat(aim - E.pos), E.facing)
	local a0 = math.atan2(toYou.X, toYou.Z) - dir * math.pi / 2
	local centre = E.pos
	setSlot(E, 1, centre + Vector3.new(math.sin(a0), 0, math.cos(a0)) * a.Length)
	local spinStart = t0 + a.Tell
	local spinTime = turns * a.Spin
	local omega = dir * 2 * math.pi / a.Spin
	local hit = {}
	local lastAng = a0
	while now() < spinStart + spinTime do
		if not valid(E, token) then
			return
		end
		local ang = a0 + omega * (now() - spinStart)
		for _, p in ipairs(fightersIn(E)) do
			if not hit[p] then
				local root = rootOf(p)
				if root then
					local d = flat(root.Position - centre)
					local dist = d.Magnitude
					if dist <= a.Length + PLAYER_RADIUS and swept(lastAng, ang, math.atan2(d.X, d.Z))
						and above(E, root) < a.Height * 0.8 then
						hit[p] = true
						-- thrown the way the bar's going
						local along = Vector3.new(math.cos(ang), 0, -math.sin(ang)) * dir
						CombatService.DamagePlayer(p, a.Damage, root.Position - along * 2,
							along * a.Knockback + Vector3.new(0, a.Knockback * 0.35, 0))
					end
				end
			end
		end
		lastAng = ang
		task.wait()
	end
	waitUntil(E, token, spinStart + spinTime + recovery(E, a.Recovery))
end

-- ERROR POP-UPS. setAction's number = how many windows. Window k drops at
-- Tell + (k - 1) * Gap (slot k = where it lands, published then) and lands
-- Fall seconds later, standing up: odd windows run east-west, even ones
-- north-south, Width wide and Depth thick. They stand for Stay seconds
-- (walls on every screen), then shatter.
function Attacks.ErrorPopups(E, token)
	local a = E.def.Attacks.ErrorPopups
	local n = perRound(E, a.Windows)
	E.track = true
	local t0 = setAction(E, "ErrorPopups", n)
	local list = fightersIn(E)
	for k = 1, n do
		local dropAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, dropAt) then
			return
		end
		E.track = false
		local who = #list > 0 and rootOf(list[(k - 1) % #list + 1]) or nil
		local around = who and Vector3.new(who.Position.X, E.floorY, who.Position.Z) or (E.pos + E.facing * 20)
		local spot = inside(E, near(E, around, (k <= #list) and 1 or a.Spread), a.Width / 2 + 1)
		setSlot(E, k, spot)
		local ax = (k % 2 == 1) and X_AXIS or Z_AXIS
		task.spawn(function()
			if waitUntil(E, token, dropAt + a.Fall) then
				hitBox(E, spot, ax, a.Width / 2, a.Depth / 2 + 0.5, a.Damage, a.Knockback)
			end
		end)
	end
	waitUntil(E, token, t0 + a.Tell + (n - 1) * a.Gap + a.Fall + recovery(E, a.Recovery))
end

-- LAG SPIKE. setAction's number = how many frames. The ghosts appear at
-- Tell * 0.4 (slot k = ghost k: in a line from him to where you are, the
-- last on you). He skips to ghost k at Tell + (k - 1) * Step, hitting
-- round it (the last skip harder).
function Attacks.LagSpike(E, token)
	local a = E.def.Attacks.LagSpike
	E.track = true
	local t0 = setAction(E, "LagSpike", a.Frames)
	if not waitUntil(E, token, t0 + a.Tell * 0.4) then
		return
	end
	E.track = false
	local from = E.pos
	local aim = inside(E, targetPosition(E) or (from + E.facing * 20), 8)
	local ghosts = {}
	for k = 1, a.Frames do
		ghosts[k] = from:Lerp(aim, k / a.Frames)
		setSlot(E, k, ghosts[k])
	end
	E.facing = unitOr(flat(aim - from), E.facing)
	-- (the skips on the way don't touch anyone standing on the last ghost: the
	-- last frame is theirs to dodge, with one roll)
	local last = ghosts[a.Frames]
	for k = 1, a.Frames do
		if not waitUntil(E, token, t0 + a.Tell + (k - 1) * a.Step) then
			return
		end
		E.pos = ghosts[k]
		place(E)
		if k == a.Frames then
			hitArea(E, last, a.LastRadius, a.LastDamage, a.Knockback)
		else
			local spared = {}
			for _, p in ipairs(fightersIn(E)) do
				local root = rootOf(p)
				if root and flatDistance(root.Position, last) <= a.LastRadius + PLAYER_RADIUS then
					spared[p] = true
				end
			end
			hitArea(E, ghosts[k], a.Radius, a.Damage, a.Knockback * 0.5, spared)
		end
	end
	waitUntil(E, token, t0 + a.Tell + (a.Frames - 1) * a.Step + recovery(E, a.Recovery))
end

----------------------------------------------------------------------
-- Tidying up
----------------------------------------------------------------------
-- everything he's left lying about goes (the paper stays as it is)
local function tidy(E, kind)
	for _, c in ipairs(E.clones or {}) do
		endProp(c, kind)
	end
	E.clones = {}
	if E.key then
		endProp(E.key, kind)
		E.key = nil
	end
	if E.prompt then
		endProp(E.prompt, kind)
		E.prompt = nil
	end
	E.zones = {}
	E.zoneAt, E.edgeAt = {}, {}
	E.model:SetAttribute("Cursor", nil)
end

----------------------------------------------------------------------
-- Round 3: the DELETE box
----------------------------------------------------------------------
-- he CRASHES (the NO was pressed): the crash costs him CrashDamage of his
-- health (it never finishes him: that's your job), then he's dizzy for
-- Crash seconds. The action "Crash" (its number = seconds).
local function crash(E, token)
	local d = E.def.Delete
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	E.model:SetAttribute("Cursor", nil)
	local m = E.model
	local max = m:GetAttribute("MaxHealth") or 1
	local hp = m:GetAttribute("Health") or 0
	local cost = math.min(math.floor(max * d.CrashDamage), hp - 1)
	if cost > 0 then
		m:SetAttribute("Health", hp - cost)
	end
	local t0 = setAction(E, "Crash", d.Crash)
	E.nextPrompt = t0 + d.Crash + d.Every
	return waitUntil(E, token, t0 + d.Crash)
end

local function closePrompt(E, pr, kind)
	if E.prompt == pr then
		E.prompt = nil
	end
	endProp(pr, kind)
	E.nextPrompt = math.max(E.nextPrompt or 0, now() + E.def.Delete.Every)
end

-- Someone punched NO: the erasing stops (the paper comes back to where it
-- was) and he crashes - whatever he was doing
local function pressNo(E, pr)
	if E.prompt ~= pr or E.state ~= "Fighting" then
		return
	end
	E.eraseTo, E.eraseStart, E.eraseEnd = nil, nil, nil
	publishPaper(E)
	closePrompt(E, pr, "Pressed")
	E.token = E.token + 1
	local token = E.token
	task.spawn(function()
		if crash(E, token) then
			Boss.brain(E, token)
		end
	end)
end

-- A DELETE box pops up on the side of the paper furthest from him, and the
-- paper starts being erased in toward `to`
local function openPrompt(E)
	local d = E.def.Delete
	local t = now()
	local to = math.max(d.MinPaper, E.paper - d.Shrink)
	local off = E.pos - E.home
	local best, bestScore = 1, -math.huge
	for i, n in ipairs(CanvasPlan.Sides) do
		local score = -(off.X * n.X + off.Z * n.Z) + E.rng:NextNumber() * 10
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	local _, _, noAt = CanvasPlan.promptSpots(best, to)
	local spot = Vector3.new(E.home.X + noAt.X, E.floorY, E.home.Z + noAt.Z)
	local model, onHit = newProp(E, "NoButton", "DeleteBox", spot, CanvasPlan.ButtonUp, propHealth(E, d.NoPunches), 2.8)
	model:SetAttribute("Side", best)
	model:SetAttribute("To", to)
	model:SetAttribute("Until", t + d.Countdown)
	local pr = { model = model, untilT = t + d.Countdown, to = to }
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 and not pr.gone then
			pressNo(E, pr)
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	E.prompt = pr
	E.eraseTo, E.eraseStart, E.eraseEnd = to, t, t + d.Countdown
	publishPaper(E)
end

-- every frame in round 3: open a box when it's time; when one's countdown
-- runs out, the delete goes through
local function stepPrompt(E, t, list)
	local pr = E.prompt
	if not pr then
		if E.phase == 3 and E.state == "Fighting" and E.nextPrompt and t >= E.nextPrompt then
			openPrompt(E)
		end
		return
	end
	if pr.gone then
		E.prompt = nil
		return
	end
	if t >= pr.untilT then
		-- YES: that much of the floor is deleted for good
		E.paper = pr.to
		E.eraseTo, E.eraseStart, E.eraseEnd = nil, nil, nil
		publishPaper(E)
		closePrompt(E, pr, "Yes")
		-- and it hits everyone hard (never a killing blow: you're left on 1)
		local d = E.def.Delete
		for _, p in ipairs(list) do
			local root = rootOf(p)
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if root and hum then
				local amount = math.min(d.YesDamage, hum.Health - 1)
				if amount > 0 then
					CombatService.DamagePlayer(p, amount, root.Position + Vector3.new(0, 6, 0), Vector3.new(0, 30, 0))
				end
			end
		end
	end
end

-- ROUND 3: he glitches into rainbow colours ("Glitch", GlitchTime seconds,
-- untouchable, everyone near thrown back), then the DELETE boxes begin
local function glitch(E, token)
	local def = E.def
	E.phase = 3
	E.model:SetAttribute("Phase", 3)
	E.model:SetAttribute("MinHealth", nil)
	E.model:SetAttribute("Invulnerable", true)
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	tidy(E, "Gone")
	setState(E, "Transition")
	local t0 = setAction(E, "Glitch", def.GlitchTime)
	if not waitUntil(E, token, t0 + def.GlitchTime * 0.4) then
		return false
	end
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and flatDistance(root.Position, E.pos) <= def.BreakReach then
			CombatService.Shove(p, knockbackFrom(E.pos, root, def.BreakShove, 26))
		end
	end
	if not waitUntil(E, token, t0 + def.GlitchTime) then
		return false
	end
	E.model:SetAttribute("Invulnerable", false)
	setState(E, "Fighting")
	E.nextPrompt = now() + 0.6 -- (the first box right away)
	return true
end

----------------------------------------------------------------------
-- His brain: the shared one, with a third round
----------------------------------------------------------------------
-- A weighted pick among the moves that suit this distance and this round
-- (the same as the shared one, plus: UpTo, and UNDO only when you've been
-- hitting him - and not too often)
local function choose(E, distance)
	local options, total = {}, 0
	for name, a in pairs(E.def.Attacks) do
		if a.Phase <= E.phase and (not a.UpTo or E.phase <= a.UpTo) and distance >= a.Range[1] and distance <= a.Range[2] then
			local w = a.Weight
			if name == "Undo" then
				local max = E.model:GetAttribute("MaxHealth") or 1
				if now() - (E.lastUndo or -math.huge) < a.Cooldown or recentDamage(E, a.Memory, a.Hits) < max * 0.02 then
					w = 0
				end
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

function Boss.brain(E, token)
	while valid(E, token) and E.state ~= "Dead" do
		if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
			if not breakShell(E, token) then
				return
			end
		end
		if E.phase == 2 and healthShare(E) <= E.def.Round3At + 1e-6 then
			if not glitch(E, token) then
				return
			end
		end
		local target = pickTarget(E)
		local aimAt = target and targetPosition(E)
		if not aimAt then
			E.chase, E.track = false, false
			task.wait(0.2)
		else
			local name = choose(E, flatDistance(aimAt, E.pos))
			if not name then
				-- nothing reaches from here: close in for a moment and think again
				E.chase, E.track = true, true
				task.wait(0.35)
			else
				E.chase = false
				E.history = { name, E.history[1] }
				Attacks[name](E, token)
				if not valid(E, token) then
					return
				end
				-- breathe, drifting after them
				local b = E.def.Breather[E.phase] or E.def.Breather[1]
				E.chase, E.track = true, true
				E.model:SetAttribute("Action", "Idle")
				local pause = b[1] + E.rng:NextNumber() * (b[2] - b[1])
				waitUntil(E, token, now() + pause)
			end
		end
	end
end

----------------------------------------------------------------------
-- Every frame (BossService calls this instead of its own steps)
----------------------------------------------------------------------
function Boss.step(E, dt)
	stepMovement(E, dt)
	local t = now()
	local list = fightersIn(E)
	stepClones(E, t, dt, list)
	stepZones(E, t, list)
	stepEdge(E, t, list)
	stepPrompt(E, t, list)
	-- round 3 comes the moment his health gets down to it, whatever he's doing
	-- (it's held there until then, so it always plays)
	if E.phase == 2 and E.state == "Fighting" and healthShare(E) <= E.def.Round3At + 1e-6 then
		E.token = E.token + 1
		local token = E.token
		task.spawn(function()
			if glitch(E, token) then
				Boss.brain(E, token)
			end
		end)
	end
end

-- he stays on the solid paper (round 3 erases its edges)
function Boss.onMove(E, _dt)
	local half = math.max(4, paperNow(E) - 3)
	local off = E.pos - E.home
	local x, z = math.clamp(off.X, -half, half), math.clamp(off.Z, -half, half)
	if x ~= off.X or z ~= off.Z then
		E.pos = Vector3.new(E.home.X + x, E.floorY, E.home.Z + z)
	end
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
-- Built: where you can punch him (he's a thin stick figure standing up), and
-- a note of every hit that lands on him (the UNDO takes them back)
function Boss.onBuild(E)
	E.clones, E.zones, E.zoneAt, E.edgeAt, E.recent = {}, {}, {}, {}, {}
	resetPaper(E)
	local def = E.def
	CombatService.SetTargetShape(E.model, function(from)
		local b = E.pos
		local y = math.clamp(from.Y, E.floorY + 1, E.floorY + def.Height - 2)
		return Vector3.new(b.X, y, b.Z), def.BodyRadius
	end)
	local onHit = E.model:FindFirstChild("OnHit")
	if onHit then
		onHit.Event:Connect(function(_player, damage)
			local d = tonumber(damage) or 0
			if d > 0 then
				table.insert(E.recent, { t = now(), dmg = d })
				if #E.recent > 30 then
					table.remove(E.recent, 1)
				end
			end
		end)
	end
end

-- ROUND 2: whatever he'd left lying about goes, and his health is held at
-- round 3's line until round 3 has begun (so it always plays)
function Boss.onBreak(E)
	tidy(E, "Gone")
	local max = E.model:GetAttribute("MaxHealth") or 1
	E.model:SetAttribute("MinHealth", math.floor(max * E.def.Round3At))
end

function Boss.onReset(E)
	tidy(E, "Gone")
	E.recent = {}
end

function Boss.onHome(E)
	resetPaper(E) -- (the paper comes back whole)
end

function Boss.onDie(E)
	tidy(E, "Gone")
	E.eraseTo, E.eraseStart, E.eraseEnd = nil, nil, nil
	publishPaper(E)
	E.recent = {}
end

return Boss
