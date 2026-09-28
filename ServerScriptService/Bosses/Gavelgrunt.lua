--[[
	Gavelgrunt  (ModuleScript, parent: ServerScriptService > Bosses, name: "Gavelgrunt")

	Floor 10's boss, THE FINAL BOSS: King Gavelgrunt, Lord of the Spire
	(Config.Bosses[10]) - a huge, fat, greedy goliath of a king with a giant
	wooden gavel. Every boss below works for him. Three rounds:

	 ROUND 1, "THE KING IS AMUSED" (slow and heavy):
	  ROYAL SMASH    the gavel comes down where a red circle marks, with
	                 shockwave rings rolling out - then it's STUCK in the
	                 floor for a moment: free hits
	  GAVEL SWEEP    a huge sideways swing in front of him
	  BELLY BOUNCE   a hop high into the air, and a belly-flop on your shadow
	  ROYAL DECREE   "GUARDS!" - little tin guards drop in and chase you
	  TOE STOMP      a stamp in front of him; then his big toe glows - punch
	                 it and he hops round holding it
	  TAX COLLECTOR  gold coins rain down: grab them (they heal you) before
	                 he sucks up the rest - each one makes his next move hit
	                 harder
	 ROUND 2, "THE MECHANICAL GAVEL" (at PhaseAt: the gavel splits open into
	 a steam-powered piston hammer):
	  TRIPLE SLAM    three slams stepping towards you, each with its ring
	  HAMMER TORNADO he spins and chases you, then he's dizzy
	  BIG GULP       he breathes in, pulling you to his mouth - swallowed,
	                 chewed and spat out; then a huge BURP blows everyone back
	  ROCKET HAMMER  the hammer's head fires down a lane on a chain and back
	  ROYAL FEAST    a roast on a platter: he sits and eats, healing - break
	                 the platter (or hit him hard) and he chokes
	  ROYAL ROLL     he tucks into a ball and bowls across the courtyard,
	                 bouncing off the edge, smashing pillars
	 ROUND 3, "NO ONE TAKES MY CROWN" (at Round3At: his crown flies off, the
	 sky turns to a red eclipse, every pillar left crumbles; he goes berserk):
	  EARTHQUAKE     a jump sky-high and a landing that shakes the courtyard:
	                 only the flagstones that light up gold are safe
	  CROWN GRAB     his crown lands somewhere and he lumbers after it: hit
	                 him enough on the way and he TRIPS
	  GUILTY!        one of you is sentenced: a giant gavel falls on you -
	                 stand on a podium (softer), friends beside you share it
	  THRONE TOSS    (once) he rips his throne up and hurls it at you
	  THE FINAL GAVEL  (once, at FinalAt) a leap and a slam on the whole
	                 courtyard: jump or roll the shockwave. Then he's spent.

	HIS BRAIN is the shared surface-boss brain with a third round and the
	final gavel (Boss.brain below). His every-frame step (Boss.step) runs the
	things he leaves about: the guards, the coins, pillars breaking as he
	rolls through them, the shockwaves.

	PROPS live in Workspace.GavelgruntProps, each a Model with Kind, Id,
	Floor, Born (and EndKind / EndAt when it goes):
	  "Guard"    a tin guard (TinGuard). It moves (its pivot is where it is);
	             per jab: SwipeWarn, SwipeAt, SwipeDir, SwipeId. EndKind
	             Broken (knocked over) / March (left) / Gone.
	  "Toe"      his glowing big toe (punch it). Until = when it stops
	             glowing. EndKind Broken (he hops) / Gone.
	  "Coin"     a gold coin on the floor. EndKind Taken (someone grabbed it)
	             / Taxed (he sucked it up) / Gone.
	  "Platter"  the roast on its platter (punch it). EndKind Broken (he
	             chokes) / Eaten / Gone.

	ON HIS MODEL: Pillars ("0101": which pillars are broken - the arena's
	pillars are swapped for rubble here too), ThroneAt (where his throne
	landed, once thrown), Taxed (how many coins his next move carries),
	Accused (the UserId of whoever he's found GUILTY) and Verdict (where they
	are, ten times a second, until the gavel locks on).

	EACH MOVE publishes its name and start time (setAction, a number in ActN)
	and the spots it fills in as it goes (setSlot) - each move below says
	which slot is what. The courtyard's shape is ReplicatedStorage/ThronePlan,
	so every screen draws exactly what hits you.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ThronePlan = require(ReplicatedStorage:WaitForChild("ThronePlan"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setState, setAction, setSlot, place, waitUntil, valid, hitArea, recovery, targetPosition, knockbackFrom
local pickTarget, healthShare, breakShell, stepMovement, stepWaves
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setState, setAction, setSlot, place = kit.setState, kit.setAction, kit.setSlot, kit.place
	waitUntil, valid, hitArea, recovery = kit.waitUntil, kit.valid, kit.hitArea, kit.recovery
	targetPosition, knockbackFrom = kit.targetPosition, kit.knockbackFrom
	pickTarget, healthShare, breakShell = kit.pickTarget, kit.healthShare, kit.breakShell
	stepMovement, stepWaves = kit.stepMovement, kit.stepWaves
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

local Z_AXIS = Vector3.new(0, 0, 1)
local X_AXIS = Vector3.new(1, 0, 0)

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

local function lerp(a, b, u)
	return a + (b - a) * u
end

-- where he stands, on the floor
local function ground(E)
	return Vector3.new(E.pos.X, E.floorY, E.pos.Z)
end

-- a spot pulled in to within `r` of the middle of the courtyard, on the floor
local function inside(E, pos, r)
	local off = flat(pos - E.center)
	r = r or (ThronePlan.Radius - 2)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.center.X + off.X, E.floorY, E.center.Z + off.Z)
end

-- how far he can go from `from` along `dir` before crossing the circle of
-- radius `r` round the middle of the courtyard
local function toEdge(E, from, dir, r)
	local o = flat(from - E.center)
	local b = o:Dot(dir)
	local c = o:Dot(o) - r * r
	local disc = b * b - c
	if disc < 0 then
		return 0
	end
	return math.max(0, -b + math.sqrt(disc))
end

-- the way to his target (or the way he's facing, if there's nobody)
local function aimDir(E, from)
	local aim = targetPosition(E)
	return aim and unitOr(flat(aim - from), E.facing) or E.facing, aim
end

-- a spot near `pos`: `spread` studs round it, at random
local function near(E, pos, spread)
	local a = E.rng:NextNumber() * math.pi * 2
	local r = math.sqrt(E.rng:NextNumber()) * spread
	return pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- how high off the floor someone is (standing: about 0)
local function above(E, root)
	return root.Position.Y - (E.floorY + STAND_HEIGHT)
end

-- his next move carries the coins he taxed: this much harder
local function dmg(E, amount)
	return amount * (E.taxBoost or 1)
end

-- Everyone within `reach` in front of him (a wedge `arc` degrees wide,
-- centred on `dir`) - and anyone right up against him. Returns the players
-- it caught (without hurting them: the move decides what happens).
local function inArc(E, reach, arc, dir)
	dir = dir or E.facing
	local cosHalf = math.cos(math.rad(arc / 2))
	local list = {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local off = flat(root.Position - E.pos)
			local d = off.Magnitude
			if d <= reach + PLAYER_RADIUS and (d < E.def.Size / 2 + PLAYER_RADIUS or off.Unit:Dot(dir) >= cosHalf) then
				table.insert(list, { player = p, root = root, d = d })
			end
		end
	end
	table.sort(list, function(x, y)
		return x.d < y.d
	end)
	return list
end

-- everyone in a wedge in front of him takes the hit, thrown away from him
local function hitArc(E, reach, arc, damage, knockback, dir)
	local landed = 0
	for _, c in ipairs(inArc(E, reach, arc, dir)) do
		if CombatService.DamagePlayer(c.player, damage, ground(E), knockbackFrom(E.pos, c.root, knockback)) then
			landed = landed + 1
		end
	end
	return landed
end

-- a shockwave ring along the floor from `origin`, starting at `t0` (see
-- BossService's stepWaves: jump it, or roll through it)
local function addWave(E, origin, t0, speed, reach, thickness, height, damage, knockback)
	table.insert(E.waves, {
		origin = origin,
		start = 2,
		t0 = t0,
		speed = speed,
		reach = reach,
		thickness = thickness,
		height = height,
		damage = damage,
		knockback = knockback,
		lastR = 2,
		hit = {},
	})
end

-- A lunge along a straight line from `from` to `to`, starting at `start`,
-- running over anyone in the way (each hit once; radius nil = hurting nobody).
-- Returns false if the fight moved on meanwhile.
local function lunge(E, token, from, to, start, travel, radius, damage, knockback)
	E.facing = unitOr(flat(to - from), E.facing)
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	if radius then
		E.sweep = { radius = radius, damage = damage, knockback = knockback, hit = {} }
	end
	local ok = waitUntil(E, token, start + travel)
	E.motion, E.sweep = nil, nil
	if ok then
		E.pos = to
	end
	return ok
end

-- gives him back `amount` health (never past the top of this round's share
-- of his bar). Returns how much he really got back.
local function heal(E, amount)
	local m = E.model
	local max = m:GetAttribute("MaxHealth") or 1
	local ceiling = max
	if E.phase == 2 then
		ceiling = math.floor(max * E.def.PhaseAt)
	elseif E.phase >= 3 then
		ceiling = math.floor(max * E.def.Round3At)
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

-- how much damage he's taken since `since`
local function damageSince(E, since)
	local sum = 0
	for i = #E.recent, 1, -1 do
		local h = E.recent[i]
		if h.t < since then
			break
		end
		sum = sum + h.dmg
	end
	return sum
end

-- how many hits have landed on him since `since`
local function hitsSince(E, since)
	local n = 0
	for i = #E.recent, 1, -1 do
		if E.recent[i].t < since then
			break
		end
		n = n + 1
	end
	return n
end

----------------------------------------------------------------------
-- The pillars (the arena's ThronePillar models)
----------------------------------------------------------------------
local function publishPillars(E)
	local broken = {}
	for i, pl in ipairs(E.pillars) do
		broken[i] = pl.broken
	end
	E.model:SetAttribute("Pillars", ThronePlan.encodeBroken(broken))
end

-- show a pillar standing or broken, for everyone
local function showPillar(pl)
	if not (pl.model and pl.model.Parent) then
		return
	end
	for _, p in ipairs(pl.model:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name == "Column" then
				p.Transparency = pl.broken and 1 or 0
				p.CanCollide = not pl.broken
			elseif p.Name == "Rubble" then
				p.Transparency = pl.broken and 0 or 1
			end
		end
	end
end

local function findPillars(E)
	E.pillars = {}
	for i, off in ipairs(ThronePlan.Pillars) do
		E.pillars[i] = { pos = E.center + off, broken = false }
	end
	for _, pm in ipairs(CollectionService:GetTagged("ThronePillar")) do
		local i = pm:GetAttribute("Index")
		if pm:GetAttribute("Floor") == E.floor and E.pillars[i] then
			E.pillars[i].model = pm
		end
	end
end

local function breakPillar(E, i)
	local pl = E.pillars[i]
	if not pl or pl.broken then
		return
	end
	pl.broken = true
	showPillar(pl)
	publishPillars(E)
end

-- every pillar standing within `radius` of `pos` breaks
local function breakPillarsNear(E, pos, radius)
	for i, pl in ipairs(E.pillars) do
		if not pl.broken and flatDistance(pl.pos, pos) <= radius + ThronePlan.PillarRadius then
			breakPillar(E, i)
		end
	end
end

local function restorePillars(E)
	for _, pl in ipairs(E.pillars) do
		pl.broken = false
		showPillar(pl)
	end
	publishPillars(E)
end

----------------------------------------------------------------------
-- Props (Workspace.GavelgruntProps)
----------------------------------------------------------------------
local function propFolder(E)
	if not (E.folder and E.folder.Parent) then
		local f = Workspace:FindFirstChild("GavelgruntProps")
		if not f then
			f = Instance.new("Folder")
			f.Name = "GavelgruntProps"
			f.Parent = Workspace
		end
		E.folder = f
	end
	return E.folder
end

-- A new prop at `spot` (on the floor), its middle `up` studs higher. With
-- `hp` it can be punched (tagged CombatTarget by whoever made it, once it's
-- ready). Returns the model and its OnHit event.
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
-- The tin guards (ROYAL DECREE)
----------------------------------------------------------------------
local function liveGuards(E)
	local n = 0
	for _, g in ipairs(E.guards) do
		if not g.gone then
			n = n + 1
		end
	end
	return n
end

local function spawnGuard(E, spot)
	local a = E.def.Attacks.RoyalDecree
	-- too many already: the oldest marches off to make room
	while liveGuards(E) >= a.Max do
		for _, g in ipairs(E.guards) do
			if not g.gone then
				endProp(g, "March")
				break
			end
		end
	end
	local model, onHit = newProp(E, "Guard", "TinGuard", spot, 2.5, propHealth(E, a.Punches), 2.2)
	local g = { model = model, pos = spot, dir = E.facing, dieAt = now() + a.Life, nextSwipe = now() + 1.0, swipeId = 0 }
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 then
			endProp(g, "Broken")
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	table.insert(E.guards, g)
	return g
end

-- every frame: each guard marches after whoever's nearest, and jabs when close
local function stepGuards(E, t, dt, list)
	if #E.guards == 0 then
		return
	end
	local a = E.def.Attacks.RoyalDecree
	for i = #E.guards, 1, -1 do
		local g = E.guards[i]
		if g.gone then
			table.remove(E.guards, i)
		elseif t >= g.dieAt then
			endProp(g, "March")
		elseif g.swipeAt then
			if t >= g.swipeAt then
				-- JAB
				hitArea(E, g.pos + g.swipeDir * 2, a.Reach, dmg(E, a.Damage), a.Knockback)
				g.swipeAt = nil
				g.nextSwipe = t + a.Rest
			end
		else
			local best, bestD = nil, math.huge
			for _, p in ipairs(list) do
				local root = rootOf(p)
				if root then
					local d = flatDistance(root.Position, g.pos)
					if d < bestD then
						best, bestD = root, d
					end
				end
			end
			if best then
				g.dir = unitOr(flat(best.Position - g.pos), g.dir)
				if bestD <= a.Reach + 0.5 and t >= g.nextSwipe then
					-- close enough: wind up a jab (it can't move while it does)
					g.swipeId = g.swipeId + 1
					g.swipeDir = g.dir
					g.swipeAt = t + a.SwipeTell
					local m = g.model
					m:SetAttribute("SwipeDir", g.swipeDir)
					m:SetAttribute("SwipeWarn", t)
					m:SetAttribute("SwipeAt", g.swipeAt)
					m:SetAttribute("SwipeId", g.swipeId)
				elseif bestD > 2.6 then
					g.pos = inside(E, g.pos + g.dir * math.min(a.Speed * dt, bestD - 2.6), ThronePlan.Radius - 2)
				end
			end
		end
	end
	-- the guards never stand in each other, and they're where they are
	for i, g in ipairs(E.guards) do
		if not g.gone then
			for j = i + 1, #E.guards do
				local o = E.guards[j]
				if not o.gone then
					local d = flat(g.pos - o.pos)
					if d.Magnitude < 3 then
						local push = unitOr(d, X_AXIS) * (3 - d.Magnitude) / 2
						g.pos = inside(E, g.pos + push, ThronePlan.Radius - 2)
						o.pos = inside(E, o.pos - push, ThronePlan.Radius - 2)
					end
				end
			end
			local at = g.pos + Vector3.new(0, 2.5, 0)
			g.model:PivotTo(CFrame.lookAt(at, at + g.dir))
		end
	end
end

----------------------------------------------------------------------
-- The coins (TAX COLLECTOR)
----------------------------------------------------------------------
local function publishTax(E)
	E.model:SetAttribute("Taxed", E.taxCoins or 0)
end

-- a coin lands at `spot`: someone can grab it until `untilT`
local function dropCoin(E, spot, untilT)
	local model = newProp(E, "Coin", "TaxCoin", spot, 0.6)
	model:SetAttribute("Until", untilT)
	table.insert(E.coins, { model = model, pos = spot, untilT = untilT })
end

-- every frame: coins grabbed by whoever walks over them; when their time's up,
-- he sucks up every one that's left
local function stepCoins(E, t, list)
	if #E.coins == 0 then
		return
	end
	local a = E.def.Attacks.TaxCollector
	local vacuumed = 0
	for i = #E.coins, 1, -1 do
		local c = E.coins[i]
		if c.gone then
			table.remove(E.coins, i)
		elseif t >= c.untilT then
			endProp(c, "Taxed")
			vacuumed = vacuumed + 1
			table.remove(E.coins, i)
		else
			for _, p in ipairs(list) do
				local root = rootOf(p)
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if root and hum and above(E, root) < 4 and flatDistance(root.Position, c.pos) <= a.Pickup then
					hum.Health = math.min(hum.MaxHealth, hum.Health + a.Heal)
					endProp(c, "Taken")
					table.remove(E.coins, i)
					break
				end
			end
		end
	end
	if vacuumed > 0 then
		E.taxCoins = math.min(a.MaxCoins, (E.taxCoins or 0) + vacuumed)
		publishTax(E)
	end
end

----------------------------------------------------------------------
-- The moves (Config.Bosses[10].Attacks - the names must match)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- ROYAL SMASH. setAction's number = how many rings. Slot 1 = where the gavel
-- lands (published at Tell * 0.55, when it locks on). It lands at Tell: ring
-- k rolls out from there at Tell + (k - 1) * RingGap. Stuck in the floor
-- until Tell + Stuck: free hits.
function Attacks.RoyalSmash(E, token)
	local a = E.def.Attacks.RoyalSmash
	local rings = perRound(E, a.Rings)
	E.track = true
	local t0 = setAction(E, "RoyalSmash", rings)
	if not waitUntil(E, token, t0 + a.Tell * 0.55) then
		return
	end
	E.track = false
	local from = ground(E)
	local dir, aim = aimDir(E, from)
	E.facing = dir
	local reach = a.Reach
	if aim then
		reach = math.clamp(flatDistance(aim, from), E.def.Size / 2 + 2, a.Reach)
	end
	local spot = inside(E, from + dir * reach, ThronePlan.Radius - 2)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	-- SMASH
	hitArea(E, spot, a.Radius, dmg(E, a.Damage), a.Knockback)
	breakPillarsNear(E, spot, a.Radius)
	for k = 1, rings do
		addWave(E, spot, t0 + a.Tell + (k - 1) * a.RingGap, a.WaveSpeed, a.WaveReach, a.WaveThickness, a.WaveHeight,
			dmg(E, a.WaveDamage), 30)
	end
	-- stuck in the floor: wide open
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Stuck))
end

-- GAVEL SWEEP. The swing lands at Tell on everyone in the wedge in front of
-- him (Reach, Arc). setAction's number = which way it swings (+1 right to
-- left, -1 left to right).
function Attacks.GavelSweep(E, token)
	local a = E.def.Attacks.GavelSweep
	local side = (E.rng:NextNumber() < 0.5) and 1 or -1
	E.track = true
	local t0 = setAction(E, "GavelSweep", side)
	if not waitUntil(E, token, t0 + a.Tell * 0.7) then
		return
	end
	E.track = false
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	hitArc(E, a.Reach, a.Arc, dmg(E, a.Damage), a.Knockback)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- BELLY BOUNCE. setAction's number = how many bounces. Bounce k: slot k =
-- where he lands (published as he takes off, at Tell + (k - 1) * (Air +
-- Gap)); he's in the air Air seconds, then belly-flops there (Radius).
function Attacks.BellyBounce(E, token)
	local a = E.def.Attacks.BellyBounce
	local n = perRound(E, a.Bounces)
	E.track = true
	local t0 = setAction(E, "BellyBounce", n)
	for k = 1, n do
		local up = t0 + a.Tell + (k - 1) * (a.Air + a.Gap)
		if not waitUntil(E, token, up) then
			return
		end
		E.track = false
		local from = ground(E)
		local aim = targetPosition(E) or (from + E.facing * 20)
		local spot = inside(E, aim, ThronePlan.Radius - E.def.Size / 2 - 1)
		setSlot(E, k, spot)
		if not lunge(E, token, from, spot, up, a.Air, nil) then
			return
		end
		-- THUD
		hitArea(E, spot, a.Radius, dmg(E, a.Damage), a.Knockback)
		breakPillarsNear(E, spot, a.Radius * 0.6)
	end
	waitUntil(E, token, t0 + a.Tell + n * a.Air + (n - 1) * a.Gap + recovery(E, a.Recovery))
end

-- ROYAL DECREE. setAction's number = how many guards. Slot k = where guard k
-- drops in, at Tell (then it's a prop: see stepGuards).
function Attacks.RoyalDecree(E, token)
	local a = E.def.Attacks.RoyalDecree
	local n = perRound(E, a.Guards)
	E.track = true
	local t0 = setAction(E, "RoyalDecree", n)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local side = Vector3.new(-E.facing.Z, 0, E.facing.X)
	local list = fightersIn(E)
	for k = 1, n do
		-- round each of you: in front of you, a little to the side
		local who = #list > 0 and rootOf(list[(k - 1) % #list + 1]) or nil
		local around = who and Vector3.new(who.Position.X, E.floorY, who.Position.Z) or (ground(E) + E.facing * 16)
		local s = (k % 2 == 1) and 1 or -1
		local spot = inside(E, around + side * (s * 7) + unitOr(flat(ground(E) - around), -E.facing) * 5, ThronePlan.Radius - 3)
		setSlot(E, k, spot)
		spawnGuard(E, spot)
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- TOE STOMP. Slot 1 = where his foot comes down (in front of him: published
-- at the start). It lands at Tell (Radius). Then the toe glows there until
-- Tell + Window (a prop, Toe). Punched: the action "ToeHop" (its number =
-- Hop seconds): he hops round holding it.
function Attacks.ToeStomp(E, token)
	local a = E.def.Attacks.ToeStomp
	E.track = true
	local t0 = setAction(E, "ToeStomp", a.Window)
	if not waitUntil(E, token, t0 + a.Tell * 0.5) then
		return
	end
	E.track = false
	local spot = inside(E, ground(E) + E.facing * (E.def.Size / 2 + 2), ThronePlan.Radius - 2)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	hitArea(E, spot, a.Radius, dmg(E, a.Damage), a.Knockback)
	-- the toe glows: punch it!
	local untilT = t0 + a.Tell + a.Window
	local model, onHit = newProp(E, "Toe", "BigToe", spot, 1.2, propHealth(E, a.Punches), 2.4)
	model:SetAttribute("Until", untilT)
	local toe = { model = model }
	local hurt = false
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 and not toe.gone then
			hurt = true
			endProp(toe, "Broken")
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	E.toe = toe
	while now() < untilT and not hurt do
		if not valid(E, token) then
			if E.toe == toe then
				endProp(toe, "Gone")
				E.toe = nil
			end
			return
		end
		task.wait()
	end
	E.toe = nil
	if hurt then
		-- OW! He hops round on one foot: wide open
		local t1 = setAction(E, "ToeHop", a.Hop)
		waitUntil(E, token, t1 + a.Hop)
	else
		endProp(toe, "Gone")
		waitUntil(E, token, now() + recovery(E, a.Recovery))
	end
end

-- TAX COLLECTOR. setAction's number = how many coins. Coin k: slot k = where
-- it lands (published as it starts falling, at Tell + (k - 1) * Drop /
-- coins); it lands 0.6 seconds later and lies there (a prop, Coin) for Lie
-- seconds.
local COIN_FALL = 0.6
function Attacks.TaxCollector(E, token)
	local a = E.def.Attacks.TaxCollector
	local n = perRound(E, a.Coins)
	E.track = true
	local t0 = setAction(E, "TaxCollector", n)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local list = fightersIn(E)
	local last = t0 + a.Tell
	for k = 1, n do
		local startAt = t0 + a.Tell + (k - 1) * a.Drop / n
		last = startAt
		if not waitUntil(E, token, startAt) then
			return
		end
		local who = #list > 0 and rootOf(list[(k - 1) % #list + 1]) or nil
		local around = who and Vector3.new(who.Position.X, E.floorY, who.Position.Z) or (ground(E) + E.facing * 20)
		local spot = inside(E, near(E, around, a.Spread), ThronePlan.Radius - 3)
		setSlot(E, k, spot)
		task.spawn(function()
			if waitUntil(E, token, startAt + COIN_FALL) then
				dropCoin(E, spot, startAt + COIN_FALL + a.Lie)
			end
		end)
	end
	waitUntil(E, token, last + COIN_FALL + recovery(E, a.Recovery))
end

-- TRIPLE SLAM (round 2). setAction's number = how many slams. Slam k lands
-- at Tell + (k - 1) * Gap; before each he steps Step towards you (a quick
-- lunge that ends as it lands). Slot k = where slam k lands (published
-- 0.45 seconds before it). Each sends out a ring.
function Attacks.TripleSlam(E, token)
	local a = E.def.Attacks.TripleSlam
	E.track = true
	local t0 = setAction(E, "TripleSlam", a.Slams)
	for k = 1, a.Slams do
		local hitAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, hitAt - 0.45) then
			return
		end
		E.track = false
		local from = ground(E)
		local dir, aim = aimDir(E, from)
		local step = a.Step
		if aim then
			step = math.min(step, math.max(0, flatDistance(aim, from) - E.def.Size / 2 - 3))
		end
		step = math.min(step, toEdge(E, from, dir, E.def.Leash))
		local to = from + dir * step
		local spot = inside(E, to + dir * (E.def.Size / 2 + 2.5), ThronePlan.Radius - 2)
		setSlot(E, k, spot)
		if not lunge(E, token, from, to, hitAt - 0.3, 0.3, nil) then
			return
		end
		-- SLAM
		hitArea(E, spot, a.Radius, dmg(E, a.Damage), a.Knockback)
		breakPillarsNear(E, spot, a.Radius)
		addWave(E, spot, hitAt, a.WaveSpeed, a.WaveReach, a.WaveThickness, a.WaveHeight, dmg(E, a.WaveDamage), 28)
		E.track = true
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Slams - 1) * a.Gap + recovery(E, a.Recovery))
end

-- HAMMER TORNADO (round 2). setAction's number = Time. He spins from Tell to
-- Tell + Time, chasing whoever he's after (Speed); anyone within Radius is
-- clobbered (again every Rehit seconds). Then he's dizzy for Dizzy seconds.
function Attacks.HammerTornado(E, token)
	local a = E.def.Attacks.HammerTornado
	E.track = true
	local t0 = setAction(E, "HammerTornado", a.Time)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local last = now()
	local hitAt = {}
	while now() < t0 + a.Tell + a.Time do
		if not valid(E, token) then
			return
		end
		local tn = now()
		local dt = math.clamp(tn - last, 0, 0.2)
		last = tn
		local aim = targetPosition(E)
		if aim then
			local want = flat(aim - E.pos)
			if want.Magnitude > 1 then
				E.pos = inside(E, E.pos + want.Unit * math.min(want.Magnitude, a.Speed * dt), E.def.Leash)
			end
		end
		E.pillarSweep = a.Radius * 0.7
		for _, p in ipairs(fightersIn(E)) do
			local root = rootOf(p)
			if root and flatDistance(root.Position, E.pos) <= a.Radius + PLAYER_RADIUS and tn - (hitAt[p] or -math.huge) >= a.Rehit then
				hitAt[p] = tn
				CombatService.DamagePlayer(p, dmg(E, a.Damage), ground(E), knockbackFrom(E.pos, root, a.Knockback))
			end
		end
		task.wait()
	end
	E.pillarSweep = nil
	-- dizzy: wide open
	waitUntil(E, token, t0 + a.Tell + a.Time + recovery(E, a.Dizzy))
end

-- BIG GULP (round 2). He breathes in from Tell to Tell + Inhale, pulling
-- everyone in front of him (Reach, Arc) to his mouth. At the end anyone
-- within Swallow in front is swallowed (slot 1 = his mouth, published then
-- if he caught anyone: that's what every screen shows); spat out Chew
-- seconds later; the BURP comes 0.3 seconds after that (BurpReach,
-- BurpArc) - slot 2 = the way it blows (a point in front of him).
function Attacks.BigGulp(E, token)
	local a = E.def.Attacks.BigGulp
	E.track = true
	local t0 = setAction(E, "BigGulp", a.Inhale)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local mouth = ground(E) + E.facing * (E.def.Size / 2)
	local endAt = t0 + a.Tell + a.Inhale
	local nextPull = now()
	while now() < endAt do
		if not valid(E, token) then
			return
		end
		if now() >= nextPull then
			nextPull = now() + 0.15
			for _, c in ipairs(inArc(E, a.Reach, a.Arc)) do
				local toMouth = unitOr(flat(mouth - c.root.Position), -E.facing)
				CombatService.Shove(c.player, toMouth * a.Pull)
			end
		end
		task.wait()
	end
	-- GULP
	local caught = inArc(E, a.Swallow, 70)
	if #caught > 0 then
		setSlot(E, 1, mouth)
		for _, c in ipairs(caught) do
			CombatService.DamagePlayer(c.player, dmg(E, a.Damage), mouth, nil)
		end
	end
	if not waitUntil(E, token, endAt + a.Chew) then
		return
	end
	-- PTOO: spat out across the courtyard
	for _, c in ipairs(caught) do
		CombatService.Shove(c.player, E.facing * a.Spit + Vector3.new(0, 40, 0))
	end
	if not waitUntil(E, token, endAt + a.Chew + 0.3) then
		return
	end
	-- BURP
	setSlot(E, 2, ground(E) + E.facing * a.BurpReach)
	hitArc(E, a.BurpReach, a.BurpArc, dmg(E, a.BurpDamage), a.BurpKnockback)
	for _, g in ipairs(E.guards) do
		if not g.gone and flatDistance(g.pos, E.pos) <= a.BurpReach then
			endProp(g, "Broken") -- (his own guards blown over too)
		end
	end
	waitUntil(E, token, endAt + a.Chew + 0.3 + recovery(E, a.Recovery))
end

-- ROCKET HAMMER (round 2). Slot 1 = where the head fires from, slot 2 =
-- where it stops (both published at Tell * 0.6: the lane locks). It flies
-- out from Tell (Speed), waits Hold seconds, and comes back the same way;
-- setAction's number = Speed. Anyone in the lane is hit going out (and
-- again coming back, softer).
function Attacks.RocketHammer(E, token)
	local a = E.def.Attacks.RocketHammer
	E.track = true
	local t0 = setAction(E, "RocketHammer", a.Speed)
	if not waitUntil(E, token, t0 + a.Tell * 0.6) then
		return
	end
	E.track = false
	local from = ground(E)
	local dir = aimDir(E, from)
	E.facing = dir
	local start = from + dir * (E.def.Size / 2)
	local len = math.max(6, math.min(a.Length, toEdge(E, start, dir, ThronePlan.Radius - 1)))
	local stop = start + dir * len
	setSlot(E, 1, start)
	setSlot(E, 2, stop)
	local travel = len / a.Speed
	local function fly(t1, fromP, toP, damage)
		local hit = {}
		while now() < t1 + travel do
			if not valid(E, token) then
				return false
			end
			local head = fromP:Lerp(toP, math.clamp((now() - t1) / travel, 0, 1))
			hitArea(E, head, a.Width / 2 + 0.5, damage, a.Knockback, hit)
			breakPillarsNear(E, head, a.Width / 2)
			task.wait()
		end
		return true
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	if not fly(t0 + a.Tell, start, stop, dmg(E, a.Damage)) then
		return
	end
	local back = t0 + a.Tell + travel + a.Hold
	if not waitUntil(E, token, back) then
		return
	end
	if not fly(back, stop, start, dmg(E, a.Damage * 0.5)) then
		return
	end
	waitUntil(E, token, back + travel + recovery(E, a.Recovery))
end

-- THE ROYAL FEAST (round 2). The platter rolls in at Tell (slot 1: a prop,
-- Platter) and he eats until Tell + Feast, healing. Broken (or hit hard
-- enough): the action "Choke" (its number = Choke seconds). Finished: the
-- platter's eaten.
function Attacks.RoyalFeast(E, token)
	local a = E.def.Attacks.RoyalFeast
	E.lastFeast = now()
	E.track = true
	local t0 = setAction(E, "RoyalFeast", a.Feast)
	local spot = inside(E, ground(E) + E.facing * (E.def.Size / 2 + 5), ThronePlan.Radius - 3)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local model, onHit = newProp(E, "Platter", "RoastPlatter", spot, 1.5, propHealth(E, a.Punches), 3.2)
	local platter = { model = model }
	local broken = false
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 and not platter.gone then
			broken = true
			endProp(platter, "Broken")
		end
	end)
	CollectionService:AddTag(model, "CombatTarget")
	E.platter = platter
	local max = E.model:GetAttribute("MaxHealth") or 1
	local started = now()
	local lastHeal = now()
	local choked = false
	while now() < t0 + a.Tell + a.Feast do
		if not valid(E, token) then
			if E.platter == platter then
				endProp(platter, "Gone")
				E.platter = nil
			end
			return
		end
		if broken or damageSince(E, started) >= max * a.ChokeAt then
			choked = true
			break
		end
		local tn = now()
		if tn - lastHeal >= 0.25 then
			heal(E, max * a.HealRate * (tn - lastHeal))
			lastHeal = tn
		end
		task.wait()
	end
	E.platter = nil
	if choked then
		endProp(platter, "Broken")
		local t1 = setAction(E, "Choke", a.Choke)
		waitUntil(E, token, t1 + a.Choke)
	else
		endProp(platter, "Eaten")
		waitUntil(E, token, now() + recovery(E, a.Recovery))
	end
end

-- THE ROYAL ROLL (round 2). setAction's number = how many points his path
-- has. Slot 1 = where he starts, slots 2.. = each bounce off the edge, the
-- last = where he stops (all published at Tell * 0.6: the path locks). He
-- rolls from Tell at Speed along them; dizzy for Dizzy seconds after.
function Attacks.RoyalRoll(E, token)
	local a = E.def.Attacks.RoyalRoll
	E.track = true
	local t0 = setAction(E, "RoyalRoll", 0)
	if not waitUntil(E, token, t0 + a.Tell * 0.6) then
		return
	end
	E.track = false
	-- the path: straight at you, bouncing off the edge of the courtyard
	local edge = E.def.Leash
	local from = ground(E)
	local dir = aimDir(E, from)
	local points = { from }
	local left = a.Distance
	local p = from
	for _ = 0, a.Bounces do
		local run = math.min(left, toEdge(E, p, dir, edge))
		if run < 0.5 then
			run = 0
		end
		p = p + dir * run
		left = left - run
		table.insert(points, p)
		if left <= 0.5 then
			break
		end
		-- bounce off the edge (a reflection about the way out from the middle)
		local n = unitOr(flat(p - E.center), Z_AXIS)
		dir = unitOr(dir - n * (2 * dir:Dot(n)), -dir)
	end
	E.model:SetAttribute("ActN", #points)
	for i, pt in ipairs(points) do
		setSlot(E, i, pt)
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local start = t0 + a.Tell
	E.pillarSweep = a.Width / 2
	for i = 1, #points - 1 do
		local travel = math.max(0.05, flatDistance(points[i + 1], points[i]) / a.Speed)
		if not lunge(E, token, points[i], points[i + 1], start, travel, a.Width / 2, dmg(E, a.Damage), a.Knockback) then
			E.pillarSweep = nil
			return
		end
		start = start + travel
	end
	E.pillarSweep = nil
	waitUntil(E, token, start + recovery(E, a.Dizzy))
end

-- EARTHQUAKE (round 3). He jumps at Tell and lands in the middle of the
-- courtyard at Tell + Air. Slots 1.. = the middles of the safe flagstones
-- (published at the start); setAction's number = how many. Anyone not on
-- one when he lands (and not in the air, not rolling) is shaken.
function Attacks.Earthquake(E, token)
	local a = E.def.Attacks.Earthquake
	E.lastQuake = now()
	E.track = true
	-- the safe flagstones: one close to each of you (not the one you're on),
	-- then more at random
	local tiles = ThronePlan.tiles()
	local chosen, used = {}, {}
	local function pick(i)
		if not used[i] and #chosen < a.Safe then
			used[i] = true
			table.insert(chosen, tiles[i])
		end
	end
	for _, pl in ipairs(fightersIn(E)) do
		local root = rootOf(pl)
		if root then
			local off = root.Position - E.center
			local best, bestD = nil, math.huge
			for i, t in ipairs(tiles) do
				local d = math.sqrt((t[1] - off.X) ^ 2 + (t[2] - off.Z) ^ 2)
				if d > ThronePlan.Cell * 0.8 and d < bestD then
					best, bestD = i, d
				end
			end
			if best then
				pick(best)
			end
		end
	end
	local guard = 0
	while #chosen < a.Safe and guard < 200 do
		guard = guard + 1
		pick(E.rng:NextInteger(1, #tiles))
	end
	local t0 = setAction(E, "Earthquake", #chosen)
	for i, t in ipairs(chosen) do
		setSlot(E, i, E.center + Vector3.new(t[1], 0, t[2]))
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local mid = Vector3.new(E.center.X, E.floorY, E.center.Z)
	if not lunge(E, token, ground(E), mid, t0 + a.Tell, a.Air, nil) then
		return
	end
	-- THE QUAKE
	for _, pl in ipairs(fightersIn(E)) do
		local root = rootOf(pl)
		if root and above(E, root) < 3 then
			local off = root.Position - E.center
			local safe = false
			for _, t in ipairs(chosen) do
				if ThronePlan.onTile(off.X, off.Z, t[1], t[2], 0.6) then
					safe = true
					break
				end
			end
			if not safe then
				CombatService.DamagePlayer(pl, dmg(E, a.Damage), root.Position - Vector3.new(0, 3, 0), Vector3.new(0, a.Knockback, 0))
			end
		end
	end
	waitUntil(E, token, t0 + a.Tell + a.Air + recovery(E, a.Recovery))
end

-- CROWN GRAB (round 3). Slot 1 = where the crown lands (at Tell); he
-- lumbers to it from Tell to Tell + Rush. Hit Trip times meanwhile: the
-- action "Tripped" (its number = Tripped seconds). Otherwise "Crowned": he
-- puts it on and roars (RoarRadius) and heals.
function Attacks.CrownGrab(E, token)
	local a = E.def.Attacks.CrownGrab
	E.lastCrown = now()
	E.track = false
	local t0 = setAction(E, "CrownGrab", a.Rush)
	-- across the courtyard from him
	local away = unitOr(flat(E.center - E.pos), E.facing)
	if flat(E.center - E.pos).Magnitude < 8 then
		away = unitOr(flat(-E.facing), Z_AXIS)
	end
	local spot = inside(E, E.center + away * 34 + Vector3.new(away.Z, 0, -away.X) * (E.rng:NextNumber() * 20 - 10), E.def.Leash)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local from = ground(E)
	local start = t0 + a.Tell
	local since = now()
	E.facing = unitOr(flat(spot - from), E.facing)
	E.motion = { from = from, to = spot, t0 = start, t1 = start + a.Rush }
	E.sweep = { radius = E.def.Size / 2, damage = dmg(E, 10), knockback = 40, hit = {} }
	local tripped = false
	while now() < start + a.Rush do
		if not valid(E, token) then
			E.motion, E.sweep = nil, nil
			return
		end
		if hitsSince(E, since) >= a.Trip then
			tripped = true
			break
		end
		task.wait()
	end
	-- (where he got to)
	local u = math.clamp((now() - start) / a.Rush, 0, 1)
	E.pos = from:Lerp(spot, u)
	E.motion, E.sweep = nil, nil
	place(E)
	if tripped then
		local t1 = setAction(E, "Tripped", a.Tripped)
		waitUntil(E, token, t1 + a.Tripped)
		return
	end
	-- he puts it back on: a ROAR
	local t1 = setAction(E, "Crowned", 1.2)
	if not waitUntil(E, token, t1 + 0.35) then
		return
	end
	hitArea(E, E.pos, a.RoarRadius, dmg(E, a.RoarDamage), a.Knockback)
	heal(E, (E.model:GetAttribute("MaxHealth") or 1) * a.Heal)
	waitUntil(E, token, t1 + 1.2 + recovery(E, a.Recovery))
end

-- "GUILTY!" (round 3). Slot 1 = where the accused stood when sentenced (at
-- Tell); the model's Accused = their UserId and Verdict follows them until
-- the gavel locks (slot 2 = where it lands, at Tell + Countdown - Lock). It
-- lands at Tell + Countdown: everyone within Share shares Damage (softened
-- to Podium on a podium). setAction's number = Countdown.
function Attacks.Guilty(E, token)
	local a = E.def.Attacks.Guilty
	E.lastGuilty = now()
	E.track = true
	local accused = E.target
	local t0 = setAction(E, "Guilty", a.Countdown)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local root = accused and rootOf(accused)
	if not root then
		return
	end
	local m = E.model
	m:SetAttribute("Accused", accused.UserId)
	local spot = inside(E, root.Position, ThronePlan.Radius)
	setSlot(E, 1, spot)
	local lockAt = t0 + a.Tell + a.Countdown - a.Lock
	local lastPublish = 0
	while now() < lockAt do
		if not valid(E, token) then
			m:SetAttribute("Accused", nil)
			m:SetAttribute("Verdict", nil)
			return
		end
		local r = rootOf(accused)
		if r then
			spot = inside(E, r.Position, ThronePlan.Radius)
		end
		if now() - lastPublish >= 0.1 then
			lastPublish = now()
			m:SetAttribute("Verdict", spot)
		end
		task.wait()
	end
	setSlot(E, 2, spot)
	m:SetAttribute("Verdict", spot)
	if not waitUntil(E, token, t0 + a.Tell + a.Countdown) then
		m:SetAttribute("Accused", nil)
		m:SetAttribute("Verdict", nil)
		return
	end
	-- THE GAVEL FALLS: shared by everyone under it
	local under = {}
	for _, p in ipairs(fightersIn(E)) do
		local r = rootOf(p)
		if r and flatDistance(r.Position, spot) <= a.Share + PLAYER_RADIUS then
			table.insert(under, { player = p, root = r })
		end
	end
	for _, c in ipairs(under) do
		local off = c.root.Position - E.center
		local share = dmg(E, a.Damage) / #under
		if ThronePlan.podiumAt(off.X, off.Z, 0.5) then
			share = share * a.Podium
		end
		CombatService.DamagePlayer(c.player, share, spot, knockbackFrom(spot, c.root, a.Knockback))
	end
	m:SetAttribute("Accused", nil)
	m:SetAttribute("Verdict", nil)
	waitUntil(E, token, t0 + a.Tell + a.Countdown + recovery(E, a.Recovery))
end

-- THRONE TOSS (round 3, once). He leaps back in front of his throne (slot 1,
-- from the start until Leap), lifts it (until Leap + Lift) and throws it:
-- slot 2 = where it lands (published at Leap + Lift), Flight seconds later.
-- It stays there (the model's ThroneAt).
function Attacks.ThroneToss(E, token)
	local a = E.def.Attacks.ThroneToss
	E.throneThrown = true
	E.track = false
	local t0 = setAction(E, "ThroneToss", a.Flight)
	local throne = E.center + ThronePlan.Throne
	local front = Vector3.new(throne.X, E.floorY, throne.Z + 12)
	setSlot(E, 1, throne)
	if not lunge(E, token, ground(E), front, t0, a.Leap, nil) then
		return
	end
	E.track = true
	if not waitUntil(E, token, t0 + a.Leap + a.Lift) then
		return
	end
	E.track = false
	local aim = targetPosition(E) or (front + E.facing * 30)
	local spot = inside(E, aim, ThronePlan.Radius - a.Radius * 0.5)
	E.facing = unitOr(flat(spot - front), E.facing)
	setSlot(E, 2, spot)
	if not waitUntil(E, token, t0 + a.Leap + a.Lift + a.Flight) then
		return
	end
	-- CRASH
	hitArea(E, spot, a.Radius, dmg(E, a.Damage), a.Knockback)
	breakPillarsNear(E, spot, a.Radius)
	E.throneAt = spot
	E.model:SetAttribute("ThroneAt", spot)
	waitUntil(E, token, t0 + a.Leap + a.Lift + a.Flight + recovery(E, a.Recovery))
end

----------------------------------------------------------------------
-- Tidying up
----------------------------------------------------------------------
-- everything he's left lying about goes (the pillars and throne stay as they are)
local function tidy(E, kind)
	for _, g in ipairs(E.guards or {}) do
		endProp(g, kind)
	end
	E.guards = {}
	for _, c in ipairs(E.coins or {}) do
		endProp(c, kind)
	end
	E.coins = {}
	if E.toe then
		endProp(E.toe, kind)
		E.toe = nil
	end
	if E.platter then
		endProp(E.platter, kind)
		E.platter = nil
	end
	E.pillarSweep = nil
	E.model:SetAttribute("Accused", nil)
	E.model:SetAttribute("Verdict", nil)
end

-- a fresh courtyard: pillars standing, the throne home, no taxes owed
local function freshArena(E)
	restorePillars(E)
	E.throneThrown, E.throneAt = false, nil
	E.model:SetAttribute("ThroneAt", nil)
	E.taxCoins, E.taxBoost = 0, 1
	publishTax(E)
	E.finalDone = false
end

----------------------------------------------------------------------
-- Round 3, and the Final Gavel
----------------------------------------------------------------------
-- ROUND 3: his crown flies off ("Berserk", BerserkTime seconds, untouchable,
-- everyone near thrown back), every pillar left crumbles, then he fights on
-- - his health held at the Final Gavel's line until it's been played
local function berserk(E, token)
	local def = E.def
	E.phase = 3
	E.model:SetAttribute("Phase", 3)
	local max = E.model:GetAttribute("MaxHealth") or 1
	E.model:SetAttribute("MinHealth", math.floor(max * def.FinalAt))
	E.model:SetAttribute("Invulnerable", true)
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	E.waves = {}
	tidy(E, "Gone")
	setState(E, "Transition")
	local t0 = setAction(E, "Berserk", def.BerserkTime)
	if not waitUntil(E, token, t0 + def.BerserkTime * 0.4) then
		return false
	end
	for i = 1, #E.pillars do
		breakPillar(E, i)
	end
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and flatDistance(root.Position, E.pos) <= def.BreakReach then
			CombatService.Shove(p, knockbackFrom(E.pos, root, def.BreakShove, 26))
		end
	end
	if not waitUntil(E, token, t0 + def.BerserkTime) then
		return false
	end
	E.model:SetAttribute("Invulnerable", false)
	setState(E, "Fighting")
	return true
end

-- THE FINAL GAVEL: he leaps into the middle of the courtyard (untouchable
-- while he winds up), and at Tell brings the gavel down: Radius round him,
-- and a shockwave over everything. Then he's worn out ("Worn", Tired
-- seconds). setAction's number = Tell.
local function finalGavel(E, token)
	local f = E.def.Final
	E.finalDone = true
	E.model:SetAttribute("MinHealth", nil)
	E.model:SetAttribute("Invulnerable", true)
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	tidy(E, "Gone")
	local t0 = setAction(E, "FinalGavel", f.Tell)
	local mid = Vector3.new(E.center.X, E.floorY, E.center.Z)
	if not lunge(E, token, ground(E), mid, t0, 1.0, nil) then
		return false
	end
	E.facing = unitOr(flat((E.center + ThronePlan.Spawn) - mid), Z_AXIS)
	if not waitUntil(E, token, t0 + f.Tell) then
		return false
	end
	E.model:SetAttribute("Invulnerable", false)
	hitArea(E, mid, f.Radius, f.Damage, f.Knockback)
	addWave(E, mid, t0 + f.Tell, f.WaveSpeed, f.WaveReach, f.WaveThickness, f.WaveHeight, f.WaveDamage, 40)
	local t1 = setAction(E, "Worn", f.Tired)
	return waitUntil(E, token, t1 + f.Tired)
end

----------------------------------------------------------------------
-- His brain: the shared one, with a third round and the final gavel
----------------------------------------------------------------------
-- A weighted pick among the moves that suit this distance and this round
-- (the same as the shared one, plus: UpTo, cooldowns, and the throne only once)
local function choose(E, distance)
	local options, total = {}, 0
	local t = now()
	for name, a in pairs(E.def.Attacks) do
		if a.Phase <= E.phase and (not a.UpTo or E.phase <= a.UpTo) and distance >= a.Range[1] and distance <= a.Range[2] then
			local w = a.Weight
			if a.Cooldown then
				local last = ({ RoyalFeast = E.lastFeast, Earthquake = E.lastQuake, CrownGrab = E.lastCrown, Guilty = E.lastGuilty })[name]
				if last and t - last < a.Cooldown then
					w = 0
				end
			end
			if name == "ThroneToss" and E.throneThrown then
				w = 0
			end
			if name == "Guilty" and #fightersIn(E) == 0 then
				w = 0
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
			if not berserk(E, token) then
				return
			end
		end
		if E.phase == 3 and not E.finalDone and healthShare(E) <= E.def.FinalAt + 1e-6 then
			if not finalGavel(E, token) then
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
				-- the coins he taxed go into this move
				local taxed = E.taxCoins or 0
				E.taxBoost = 1 + taxed * E.def.Attacks.TaxCollector.PerCoin
				Attacks[name](E, token)
				if taxed > 0 then
					E.taxCoins = math.max(0, (E.taxCoins or 0) - taxed)
					publishTax(E)
				end
				E.taxBoost = 1
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
	stepWaves(E)
	local t = now()
	local list = fightersIn(E)
	stepGuards(E, t, dt, list)
	stepCoins(E, t, list)
	-- rolling or spinning through a pillar breaks it
	if E.pillarSweep then
		breakPillarsNear(E, E.pos, E.pillarSweep)
	end
	-- round 3, and the final gavel, come the moment his health gets down to
	-- them, whatever he's doing (it's held there until then, so they always play)
	if E.state == "Fighting" then
		if E.phase == 2 and healthShare(E) <= E.def.Round3At + 1e-6 then
			E.token = E.token + 1
			local token = E.token
			task.spawn(function()
				if berserk(E, token) then
					Boss.brain(E, token)
				end
			end)
		elseif E.phase == 3 and not E.finalDone and healthShare(E) <= E.def.FinalAt + 1e-6 then
			E.token = E.token + 1
			local token = E.token
			task.spawn(function()
				if finalGavel(E, token) then
					Boss.brain(E, token)
				end
			end)
		end
	end
end

-- he stays on the courtyard (clear of its edge)
function Boss.onMove(E, _dt)
	local off = flat(E.pos - E.center)
	if off.Magnitude > E.def.Leash then
		off = off.Unit * E.def.Leash
		E.pos = Vector3.new(E.center.X + off.X, E.floorY, E.center.Z + off.Z)
	end
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
-- Built: where the courtyard is, its pillars, where you can punch him (he's
-- a tall, fat goliath standing up), and a note of every hit that lands on him
function Boss.onBuild(E)
	E.center = E.home - ThronePlan.Home
	E.guards, E.coins, E.recent = {}, {}, {}
	findPillars(E)
	freshArena(E)
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
				if #E.recent > 60 then
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
	E.waves = {}
	local max = E.model:GetAttribute("MaxHealth") or 1
	E.model:SetAttribute("MinHealth", math.floor(max * E.def.Round3At))
end

function Boss.onReset(E)
	tidy(E, "Gone")
	E.waves = {}
	E.recent = {}
end

function Boss.onHome(E)
	freshArena(E) -- (the pillars stand again, the throne's back)
end

function Boss.onDie(E)
	tidy(E, "Gone")
	E.waves = {}
	E.recent = {}
	E.taxCoins = 0
	publishTax(E)
end

return Boss
