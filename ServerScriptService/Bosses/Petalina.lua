--[[
	Petalina  (ModuleScript, parent: ServerScriptService > Bosses, name: "Petalina")

	Floor 8's boss: Petalina, the Blooming Terror (Config.Bosses[8]) - a giant
	cartoon flower with the sweetest smile, planted in the middle of her
	greenhouse garden. She NEVER MOVES from her spot: she fills the garden with
	things to dodge, and you weave through them to get close and hit her stem
	(or her head, when it's down on the floor). BossService's shared brain runs
	her - it picks a move that suits how far away you are (from
	Config.Bosses[8].Attacks), turns her face to follow you, goes into ROUND 2
	at half health, resets, dies, pays out - and her own every-frame step
	(Boss.step) runs the things she leaves in the garden. Her moves:

	  SEED SPIT       spits seeds high into the air; they land on red circles
	                  near you, and some sprout into FLYTRAPS where they land.
	  PETAL BOOMERANG flings petals that fly out in a loop past you and come
	                  back (they fly low: jump them, or stay inside the loop).
	  VINE WHIP       red lines run out from her across the floor, then vines
	                  burst up along them, racing outward. Step off the line.
	  POLLEN CLOUD    clouds of pollen drift down onto red circles near you and
	                  hang there, stinging anyone inside.
	  FACE STRETCH    her neck stretches and her head shoots down a red lane to
	                  CHOMP at the end. Then it lies there, dizzy: HIT HER!
	  ROOT RING       right up close: roots burst up in a circle round her.
	  SUNBATHE        she turns her face to the sun and hums. Free hits!
	 round 2 (she turns evil; thorns cover every flower bed - off the paths,
	 they sting):
	  THORN RING      rings of thorns spreading out across the garden: jump them.
	  SEED RAIN       seeds rain from the glass roof onto the paths near you.

	THE FLYTRAPS live in Workspace.PetalinaProps, each a Model with Kind =
	"Flytrap", Id, Floor, Born, Grow (seconds it takes to sprout) and, for
	each bite, BiteWarn (its jaws start to gape), BiteAt (it snaps), BiteDir
	(the way it lunges) and BiteId. One punch pops it (EndKind "Broken"); left
	alone it wilts (EndKind "Wither"); when the fight resets they all go
	("Gone"). EndAt says when.

	Everything else is published for each player's screen (BossClient +
	ReplicatedStorage/BossBodies/Petalina): the move's name and start time
	(setAction, with its number in ActN) and the spots it fills in as it goes
	(setSlot) - each move below says which slot is what - and ThornsAt on her
	model (round 2: when the thorns start to sting). The garden's shape, the
	petals' loop and her head's path are shared sums in
	ReplicatedStorage/GardenPlan, so every screen draws exactly what hits you.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local GardenPlan = require(ReplicatedStorage:WaitForChild("GardenPlan"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, hitArea, recovery, targetPosition, knockbackFrom
local stepMovement, stepWaves
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	hitArea, recovery, targetPosition, knockbackFrom = kit.hitArea, kit.recovery, kit.targetPosition, kit.knockbackFrom
	stepMovement, stepWaves = kit.stepMovement, kit.stepWaves
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a number for this round: a { round 1, round 2 } pair, or just a number
local function perRound(E, v)
	if type(v) == "table" then
		return v[math.min(E.phase, #v)]
	end
	return v
end

-- her stem, on the floor (she never moves: it's always her home)
local function base(E)
	return E.home
end

-- a spot pulled in to within `r` of the middle of the garden, on the floor
local function inside(E, pos, r)
	local off = flat(pos - E.home)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.home.X + off.X, E.floorY, E.home.Z + off.Z)
end

-- in round 2 (thorns on the beds), a spot moved onto the nearest path
local function onPath(E, pos)
	local off = pos - E.home
	local x, z = GardenPlan.nearestSafe(off.X, off.Z)
	return Vector3.new(E.home.X + x, E.floorY, E.home.Z + z)
end

-- the way to her target (or the way she's facing, if there's nobody)
local function aimDir(E)
	local aim = targetPosition(E)
	return aim and unitOr(flat(aim - E.home), E.facing) or E.facing, aim
end

-- a spot near someone: `spread` studs round `pos`, at random
local function near(E, pos, spread)
	local a = E.rng:NextNumber() * math.pi * 2
	local r = math.sqrt(E.rng:NextNumber()) * spread
	return pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- a shockwave ring along the floor from `origin`, starting at `t0` (see
-- BossService's stepWaves: jump it, or roll through it)
local function addWave(E, origin, t0, speed, reach, thickness, height, damage, knockback)
	table.insert(E.waves, {
		origin = origin,
		start = 4,
		t0 = t0,
		speed = speed,
		reach = reach,
		thickness = thickness,
		height = height,
		damage = damage,
		knockback = knockback,
		lastR = 4,
		hit = {},
	})
end

-- how high off the floor someone is (standing on the paving: about 0)
local function above(E, root)
	return root.Position.Y - (E.floorY + STAND_HEIGHT)
end

----------------------------------------------------------------------
-- The flytraps (Workspace.PetalinaProps)
----------------------------------------------------------------------
local function propFolder(E)
	if not (E.folder and E.folder.Parent) then
		local f = Workspace:FindFirstChild("PetalinaProps")
		if not f then
			f = Instance.new("Folder")
			f.Name = "PetalinaProps"
			f.Parent = Workspace
		end
		E.folder = f
	end
	return E.folder
end

local function endTrap(trap, kind)
	if trap.gone then
		return
	end
	trap.gone = true
	local model = trap.model
	CollectionService:RemoveTag(model, "CombatTarget")
	model:SetAttribute("EndKind", kind)
	model:SetAttribute("EndAt", now())
	task.delay(0.8, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

local function clearTraps(E, kind)
	for _, trap in ipairs(E.traps or {}) do
		endTrap(trap, kind)
	end
	E.traps = {}
end

local function liveTraps(E)
	local n = 0
	for _, trap in ipairs(E.traps) do
		if not trap.gone then
			n = n + 1
		end
	end
	return n
end

-- A flytrap sprouting at `spot` at `bornAt`. One punch pops it.
local function spawnTrap(E, spot, bornAt)
	local f = E.def.Flytrap
	-- too many already: the oldest wilts to make room
	local max = perRound(E, f.Max)
	while liveTraps(E) >= max do
		for _, trap in ipairs(E.traps) do
			if not trap.gone then
				endTrap(trap, "Wither")
				break
			end
		end
	end
	E.trapId = (E.trapId or 0) + 1
	local model = Instance.new("Model")
	model.Name = "Flytrap"
	local hit = Instance.new("Part")
	hit.Name = "Hit"
	hit.Size = Vector3.new(3, 4, 3)
	hit.CFrame = CFrame.new(spot + Vector3.new(0, 2, 0))
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CanQuery = false
	hit.CanTouch = false
	hit.CastShadow = false
	hit.Parent = model
	model.PrimaryPart = hit
	model:SetAttribute("Kind", "Flytrap")
	model:SetAttribute("Id", E.trapId)
	model:SetAttribute("Floor", E.floor)
	model:SetAttribute("Born", bornAt)
	model:SetAttribute("Grow", f.Grow)
	-- punchable: one punch at the floor's recommended power pops it
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	local hp = math.max(1, math.floor(rec * f.Punches))
	model:SetAttribute("MaxHealth", hp)
	model:SetAttribute("Health", hp)
	model:SetAttribute("HitRadius", 1.8)
	model:SetAttribute("NoBar", true)
	model:SetAttribute("StudioFair", true)
	model:SetAttribute("DisplayName", "Flytrap")
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- (every screen has it, to lock on)
	end)
	local trap = {
		model = model, pos = spot, growAt = bornAt + f.Grow, dieAt = bornAt + f.Life,
		nextBite = bornAt + f.Grow + 0.3, biteId = 0,
	}
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = model
	onHit.Event:Connect(function(_player, damage, killed)
		if killed and (tonumber(damage) or 0) > 0 then
			endTrap(trap, "Broken")
		end
	end)
	model.Parent = propFolder(E)
	table.insert(E.traps, trap)
	return trap
end

local function stepTraps(E, t, list)
	local f = E.def.Flytrap
	for i = #E.traps, 1, -1 do
		local trap = E.traps[i]
		if trap.gone then
			table.remove(E.traps, i)
		elseif t >= trap.dieAt then
			endTrap(trap, "Wither")
		elseif t >= trap.growAt then
			if not trap.tagged then
				trap.tagged = true
				CollectionService:AddTag(trap.model, "CombatTarget")
			end
			if trap.biteAt then
				if t >= trap.biteAt then
					-- SNAP: it lunges and bites
					local at = trap.pos + trap.biteDir * f.Lunge
					hitArea(E, at, f.Reach, f.Damage, f.Knockback)
					trap.biteAt = nil
					trap.nextBite = t + f.Rest
				end
			elseif t >= trap.nextBite then
				-- someone close? turn to them and gape
				local best, bestD = nil, f.Sense
				for _, p in ipairs(list) do
					local root = rootOf(p)
					if root then
						local d = flatDistance(root.Position, trap.pos)
						if d < bestD then
							best, bestD = root, d
						end
					end
				end
				if best then
					trap.biteId = trap.biteId + 1
					trap.biteDir = unitOr(flat(best.Position - trap.pos), Vector3.new(0, 0, 1))
					trap.biteAt = t + f.Tell
					local m = trap.model
					m:SetAttribute("BiteDir", trap.biteDir)
					m:SetAttribute("BiteWarn", t)
					m:SetAttribute("BiteAt", trap.biteAt)
					m:SetAttribute("BiteId", trap.biteId)
				else
					trap.nextBite = t + 0.25
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- The pollen clouds, the thorns, her head
----------------------------------------------------------------------
local function stepClouds(E, t, list)
	local a = E.def.Attacks.Pollen
	for i = #E.clouds, 1, -1 do
		local c = E.clouds[i]
		if t > c.t2 then
			table.remove(E.clouds, i)
		elseif t >= c.t1 then
			for _, p in ipairs(list) do
				local root = rootOf(p)
				if root and flatDistance(root.Position, c.pos) <= a.Radius + PLAYER_RADIUS * 0.5 and above(E, root) < a.Height
					and t - (E.pollenAt[p] or -math.huge) >= a.Tick then
					E.pollenAt[p] = t
					CombatService.DamagePlayer(p, a.Damage, c.pos, nil, true)
				end
			end
		end
	end
end

-- round 2: standing on a flower bed (not a path) stings
local function stepThorns(E, t, list)
	if not E.thornsAt or t < E.thornsAt or E.state ~= "Fighting" then
		return
	end
	local th = E.def.Thorns
	for _, p in ipairs(list) do
		local root = rootOf(p)
		if root and above(E, root) < GardenPlan.BedUp + 2 then
			local off = root.Position - E.home
			if not GardenPlan.safe(off.X, off.Z) and t - (E.thornAt[p] or -math.huge) >= th.Tick then
				E.thornAt[p] = t
				CombatService.DamagePlayer(p, th.Damage, root.Position - Vector3.new(0, 2, 0), nil, true)
			end
		end
	end
end

-- The Face Stretch's head: where it is now (nil while it's up on her stem),
-- and anyone in the lane as it races along gets bitten
local function stepHead(E, t)
	local h = E.head
	if not h then
		E.headNow = nil
		return
	end
	local a = E.def.Attacks.FaceStretch
	if t < h.shootAt then
		E.headNow = nil
	elseif t < h.landAt then
		local u = (t - h.shootAt) / (h.landAt - h.shootAt)
		E.headNow = GardenPlan.headPoint(base(E), E.def.HeadHeight, h.finish, 2.5, u)
		if u >= GardenPlan.DIVE then
			local ground = Vector3.new(E.headNow.X, E.floorY, E.headNow.Z)
			hitArea(E, ground, a.Width / 2, a.Damage, a.Knockback, h.hit)
		end
	elseif t < h.backAt then
		E.headNow = h.finish + Vector3.new(0, 2.5, 0) -- (lying there, dizzy)
	elseif t < h.backAt + a.Back then
		local u = 1 - (t - h.backAt) / a.Back
		E.headNow = GardenPlan.headPoint(base(E), E.def.HeadHeight, h.finish, 2.5, u)
	else
		E.head, E.headNow = nil, nil
	end
end

----------------------------------------------------------------------
-- The moves (Config.Bosses[8].Attacks - the names must match)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- SEED SPIT. setAction's number = how many seeds. Seed k is spat at Tell +
-- (k - 1) * Gap and lands Flight later on slot k; the first Sprout of them
-- grow into flytraps there.
function Attacks.SeedSpit(E, token)
	local a = E.def.Attacks.SeedSpit
	local count = perRound(E, a.Seeds)
	local sprout = perRound(E, a.Sprout)
	E.track = true
	local t0 = setAction(E, "SeedSpit", count)
	for k = 1, count do
		local spitAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, spitAt) then
			return
		end
		local aim = targetPosition(E) or (base(E) + E.facing * 24)
		local spot = inside(E, near(E, aim, (k == 1) and 2 or a.Spread), GardenPlan.Edge - 3)
		if E.phase >= 2 then
			spot = onPath(E, spot)
		end
		setSlot(E, k, spot)
		local landAt = spitAt + a.Flight
		local grows = k <= sprout
		task.spawn(function()
			if waitUntil(E, token, landAt) then
				hitArea(E, spot, a.Radius, a.Damage, a.Knockback)
				if grows then
					spawnTrap(E, spot, landAt)
				end
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (count - 1) * a.Gap + a.Flight * 0.5 + recovery(E, a.Recovery))
end

-- Where a petal's loop reaches to, so its way OUT passes right through
-- where you are (`dist` along `dir`): the loop is Past longer than that, and
-- tipped over to one side just enough that its bulge crosses your spot.
local function petalFar(E, dir, dist, side, a)
	local length = math.min(dist + a.Past, GardenPlan.Edge - 3)
	local tilt = 0
	if dist > 6 and dist < length then
		-- (the tilt that puts you on the oval: found by halving the gap)
		local half = length / 2
		local lo, hi = 0, math.pi / 2
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			local x, y = dist * math.cos(mid), dist * math.sin(mid)
			if ((x - half) / half) ^ 2 + (y / a.Width) ^ 2 < 1 then
				lo = mid
			else
				hi = mid
			end
		end
		tilt = lo
	end
	-- turn the loop away from you, to the side it bulges out on first, so
	-- the bulge swings back through you
	local c, s = math.cos(tilt), math.sin(tilt)
	local turned = { Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c), Vector3.new(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c) }
	for _, d in ipairs(turned) do
		local across = Vector3.new(-d.Z, 0, d.X)
		if dir:Dot(across) * side > 0 or tilt == 0 then
			return base(E) + d * length
		end
	end
	return base(E) + dir * length
end

-- PETAL BOOMERANG. setAction's number = how many petals. Petal k is thrown at
-- Tell + (k - 1) * Gap; slot k = the far end of its loop (past where you
-- were). Odd petals bulge out to her left first, even ones to her right
-- (GardenPlan.petalPoint). A petal hits each player once, unless they jump
-- over it or roll through it.
function Attacks.Petals(E, token)
	local a = E.def.Attacks.Petals
	local count = perRound(E, a.Count)
	E.track = true
	local t0 = setAction(E, "Petals", count)
	for k = 1, count do
		local throwAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, throwAt - 0.1) then
			return
		end
		local dir, aim = aimDir(E)
		E.facing = dir
		local dist = aim and flatDistance(aim, base(E)) or 24
		local side = (k % 2 == 1) and 1 or -1
		local far = petalFar(E, dir, dist, side, a)
		local length = flatDistance(far, base(E))
		local loop = GardenPlan.petalTime(length, a.Width, a.Speed)
		setSlot(E, k, far)
		task.spawn(function()
			if not waitUntil(E, token, throwAt) then
				return
			end
			local struck = {}
			while valid(E, token) do
				local s = (now() - throwAt) / loop
				if s >= 1 then
					return
				end
				if s > 0.06 and s < 0.94 then
					local p = GardenPlan.petalPoint(base(E), far, side, a.Width, s)
					for _, pl in ipairs(fightersIn(E)) do
						if not struck[pl] then
							local root = rootOf(pl)
							if root and flatDistance(root.Position, p) <= a.Radius + PLAYER_RADIUS and above(E, root) < a.Height * 0.8 then
								struck[pl] = true
								CombatService.DamagePlayer(pl, a.Damage, p, knockbackFrom(p, root, a.Knockback))
							end
						end
					end
				end
				task.wait()
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (count - 1) * a.Gap + recovery(E, a.Recovery))
end

-- VINE WHIP. setAction's number = how many lines. Slot i = the far end of
-- line i (they all start at her stem); the lines lock 70% of the way through
-- the Tell. At Tell the vines burst up along every line at once, racing out
-- at Speed, and stay up Up seconds behind the front. You can't jump them.
function Attacks.VineWhip(E, token)
	local a = E.def.Attacks.VineWhip
	local lines = perRound(E, a.Lines)
	E.track = true
	local t0 = setAction(E, "VineWhip", lines)
	if not waitUntil(E, token, t0 + a.Tell * 0.7) then
		return
	end
	E.track = false
	local dir = aimDir(E)
	E.facing = dir
	local dirs, lens = {}, {}
	for i = 1, lines do
		local ang = math.rad((i - (lines + 1) / 2) * a.Spread)
		local c, s = math.cos(ang), math.sin(ang)
		local d = Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
		dirs[i] = d
		local tip = inside(E, base(E) + d * a.Length, GardenPlan.Edge)
		lens[i] = flatDistance(tip, base(E))
		setSlot(E, i, tip)
	end
	local start = t0 + a.Tell
	if not waitUntil(E, token, start) then
		return
	end
	task.spawn(function()
		local struck = {}
		local last = start + a.Length / a.Speed + a.Up
		while valid(E, token) and now() < last do
			local t = now()
			local front = (t - start) * a.Speed
			for _, pl in ipairs(fightersIn(E)) do
				if not struck[pl] then
					local root = rootOf(pl)
					if root then
						local off = flat(root.Position - base(E))
						for i, d in ipairs(dirs) do
							local along = off:Dot(d)
							local lateral = math.abs(off.X * d.Z - off.Z * d.X)
							if along > 2 and along <= math.min(front, lens[i]) and t <= start + along / a.Speed + a.Up
								and lateral <= a.Width / 2 + PLAYER_RADIUS then
								struck[pl] = true
								local at = base(E) + d * along
								CombatService.DamagePlayer(pl, a.Damage, at, knockbackFrom(at, root, a.Knockback, a.Knockback * 0.8))
								break
							end
						end
					end
				end
			end
			task.wait()
		end
	end)
	waitUntil(E, token, start + recovery(E, a.Recovery))
end

-- POLLEN CLOUD. setAction's number = how many clouds. At Tell each drifts
-- off her toward slot k (near you), settles Drift later and hangs there for
-- Life seconds.
function Attacks.Pollen(E, token)
	local a = E.def.Attacks.Pollen
	local count = perRound(E, a.Clouds)
	E.track = true
	local t0 = setAction(E, "Pollen", count)
	if not waitUntil(E, token, t0 + a.Tell - 0.1) then
		return
	end
	E.track = false
	local aim = targetPosition(E) or (base(E) + E.facing * 20)
	for k = 1, count do
		local spot = inside(E, near(E, aim, (k == 1) and 1.5 or a.Spread), GardenPlan.Edge - 4)
		setSlot(E, k, spot)
		local t1 = t0 + a.Tell + a.Drift
		table.insert(E.clouds, { pos = spot, t1 = t1, t2 = t1 + a.Life })
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- FACE STRETCH. setAction's number = how far the lane reaches. Slot 1 = the
-- lane's end (locked Commit of the way through the Tell). At Tell her head
-- shoots out (GardenPlan.headPoint) for Time seconds, biting anyone in the
-- lane as it races along it, then CHOMPS at the end. It lies there, dizzy,
-- for Droop seconds (punch it!), then pulls back in Back seconds.
function Attacks.FaceStretch(E, token)
	local a = E.def.Attacks.FaceStretch
	E.track = true
	local aim0 = targetPosition(E)
	local reach = math.clamp((aim0 and flatDistance(aim0, base(E)) or a.Reach[1]) + 3, a.Reach[1], a.Reach[2])
	local t0 = setAction(E, "FaceStretch", reach)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return
	end
	E.track = false
	local dir = aimDir(E)
	E.facing = dir
	local finish = inside(E, base(E) + dir * reach, GardenPlan.Edge - 3)
	setSlot(E, 1, finish)
	local shootAt = t0 + a.Tell
	local landAt = shootAt + a.Time
	E.head = { finish = finish, shootAt = shootAt, landAt = landAt, backAt = landAt + a.Droop, hit = {} }
	if not waitUntil(E, token, landAt) then
		return
	end
	hitArea(E, finish, a.Chomp, a.ChompDamage, a.Knockback, E.head and E.head.hit)
	waitUntil(E, token, landAt + a.Droop + a.Back + recovery(E, 0.2))
	E.head = nil
end

-- ROOT RING: roots burst up out of the soil in a circle round her (Radius).
function Attacks.RootRing(E, token)
	local a = E.def.Attacks.RootRing
	E.track = true
	local t0 = setAction(E, "RootRing", a.Radius)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	hitArea(E, base(E), a.Radius, a.Damage, a.Knockback, nil, true)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- SUNBATHE: she hums in the sunshine. Nothing hurts - it's your chance.
function Attacks.Sunbathe(E, token)
	local a = E.def.Attacks.Sunbathe
	E.track = false
	local t0 = setAction(E, "Sunbathe", a.Time)
	waitUntil(E, token, t0 + a.Time)
end

-- THORN RING (round 2). setAction's number = how many rings. Ring k leaves
-- her at Tell + (k - 1) * Gap and spreads across the garden (a shockwave:
-- jump it, or roll through it).
function Attacks.ThornRing(E, token)
	local a = E.def.Attacks.ThornRing
	local rings = perRound(E, a.Rings)
	E.track = true
	local t0 = setAction(E, "ThornRing", rings)
	for k = 1, rings do
		addWave(E, base(E), t0 + a.Tell + (k - 1) * a.Gap, a.Speed, a.Reach, a.Thickness, a.Height, a.Damage, a.Knockback)
	end
	waitUntil(E, token, t0 + a.Tell + (rings - 1) * a.Gap + recovery(E, a.Recovery))
end

-- SEED RAIN (round 2). setAction's number = how many seeds. Slot i = where
-- seed i lands (on a path near one of you), at Tell + Fall + (i - 1) / Drops
-- * Stagger. The first Sprout of them grow into flytraps.
function Attacks.SeedRain(E, token)
	local a = E.def.Attacks.SeedRain
	E.track = true
	local t0 = setAction(E, "SeedRain", a.Drops)
	if not waitUntil(E, token, t0 + a.Tell * 0.8) then
		return
	end
	E.track = false
	local list = fightersIn(E)
	for i = 1, a.Drops do
		local who = #list > 0 and rootOf(list[(i - 1) % #list + 1]) or nil
		local around = who and Vector3.new(who.Position.X, E.floorY, who.Position.Z) or (base(E) + E.facing * 20)
		local spot = onPath(E, inside(E, near(E, around, (i <= #list) and 1.5 or a.Spread), GardenPlan.Edge - 3))
		setSlot(E, i, spot)
		local landAt = t0 + a.Tell + a.Fall + (i - 1) / a.Drops * a.Stagger
		local grows = i <= a.Sprout
		task.spawn(function()
			if waitUntil(E, token, landAt) then
				hitArea(E, spot, a.Radius, a.Damage, a.Knockback)
				if grows then
					spawnTrap(E, spot, landAt)
				end
			end
		end)
	end
	waitUntil(E, token, t0 + a.Tell + a.Fall + a.Stagger + recovery(E, a.Recovery))
end

----------------------------------------------------------------------
-- Every frame (BossService calls this instead of its own steps)
----------------------------------------------------------------------
function Boss.step(E, dt)
	E.chase = false -- (she never walks: the brain's breathers only turn her face)
	stepMovement(E, dt)
	stepWaves(E)
	local t = now()
	local list = fightersIn(E)
	stepHead(E, t)
	stepTraps(E, t, list)
	stepClouds(E, t, list)
	stepThorns(E, t, list)
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
local function tidy(E)
	E.waves = {}
	E.clouds = {}
	E.head, E.headNow = nil, nil
	E.pollenAt, E.thornAt = {}, {}
	E.thornsAt = nil
	E.model:SetAttribute("ThornsAt", nil)
	clearTraps(E, "Gone")
end

-- Built: where you can punch her - her stem (always), and her head when
-- it's down where you can reach it
function Boss.onBuild(E)
	E.traps, E.clouds, E.pollenAt, E.thornAt = {}, {}, {}, {}
	local def = E.def
	CombatService.SetTargetShape(E.model, function(from)
		local b = E.home
		local y = math.clamp(from.Y, E.floorY, E.floorY + def.HeadHeight - 3)
		local stem = Vector3.new(b.X, y, b.Z)
		local best, bestR = stem, def.StemRadius
		local bestD = (Vector3.new(from.X, 0, from.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude - def.StemRadius
		local head = E.headNow
		if head then
			local d = (Vector3.new(from.X, 0, from.Z) - Vector3.new(head.X, 0, head.Z)).Magnitude - def.HeadRadius
			if d < bestD and math.abs(head.Y - from.Y) < 10 then
				best, bestR = head, def.HeadRadius
			end
		end
		return best, bestR
	end)
end

-- ROUND 2: she turns evil. Whatever was flying stops; thorns creep over
-- every flower bed and start to sting Grace seconds after the change is over.
function Boss.onBreak(E)
	E.waves = {}
	E.head, E.headNow = nil, nil
	E.thornsAt = now() + E.def.BreakTime + E.def.Thorns.Grace
	E.model:SetAttribute("ThornsAt", E.thornsAt)
end

function Boss.onReset(E)
	tidy(E)
end

function Boss.onDie(E)
	tidy(E)
end

return Boss
