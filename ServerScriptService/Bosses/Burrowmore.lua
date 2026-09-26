--[[
	Burrowmore  (ModuleScript, parent: ServerScriptService > Bosses, name: "Burrowmore")

	Floor 3's boss: Knight Burrowmore, the Honourable Digger (Config.Bosses[3]) -
	a knight of the shovel. A souls-like fight: every move has ONE clear
	wind-up, ONE way to dodge it, and a moment afterwards when he's open. You
	learn him by losing to him. He fights on the surface, so BossService's
	shared brain runs him (it picks a move that suits the distance - from
	Config.Bosses[3].Attacks - walks after you, turns to face you, breaks his
	armour at half health, resets, dies, pays out). This file is his moves:

	  SHOVEL DROP    jumps high, shovel pointing down; the red circle under him
	                 FOLLOWS you, flashes and locks - roll just before he lands.
	                 He bounces once, then tugs his shovel out (an opening).
	  TRIPLE POGO    three pogo hops in a row, each at you: roll in rhythm.
	                 Dizzy after the third (a big opening).
	  SHOVEL SWING   pulls the shovel back, sweeps it round in front of him.
	  DIRT FLING     digs in, flings a fan of clods at you: roll out sideways.
	  ANCHOR TOSS    a relic: lobs an anchor in a high arc onto you; it sticks
	                 in the floor and he has to tug it out (a big opening).
	  FIRE STICK     a relic: three fireballs along the floor, each at you.
	  CHARGE DASH    scrapes his shovel, a red lane shows the way, he charges
	                 along it. Running into the edge of the dig dizzies him.
	  TAUNT          plants his shovel and laughs. Free hits.
	 phase two ("No Quarter!"):
	  DELAYED DROP   the drop, but he hangs at the top after it locks.
	  SWING DROP     a quick swing, then straight up into a drop.
	  GEM RAIN       treasure rains into marked circles while he keeps fighting.
	  SHOVEL METEOR  his final move (first time below Config's MeteorAt): he
	                 jumps out of sight, a huge shadow grows in the middle - get
	                 to the edge! Then he's stuck in the ground (a long opening).

	While he's high in the air you can't punch him: CombatService asks this
	file where his body is (SetTargetShape), and up there he's out of reach.

	Everything is published for each player's screen (BossClient + ReplicatedStorage/
	BossBodies/Burrowmore): the move's name and start time (setAction), and the
	spots it fills in as it goes (setSlot: take-off and landing, the swing's
	aim, the clods, the anchor, the fireballs, the dash lane). The gem rain
	carries on under his next moves, so it has its own attributes on his model:
	RainAt (when the first gem was picked), RainK (how many so far), Rain1..RainN.
]]

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, hitArea, recovery, targetPosition, healthShare, knockbackFrom
local CombatService, PLAYER_RADIUS, STAND_HEIGHT, SLOTS

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	hitArea, recovery, targetPosition, healthShare, knockbackFrom = kit.hitArea, kit.recovery, kit.targetPosition, kit.healthShare, kit.knockbackFrom
	CombatService, PLAYER_RADIUS, STAND_HEIGHT, SLOTS = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT, kit.SLOTS
end

local RAIN_SLOTS = 24 -- the most gems one rain can drop (Rain1..Rain24)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a spot pulled in to within `r` of the middle of the dig, on the floor
local function inside(E, pos, r)
	local off = flat(pos - E.home)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.home.X + off.X, E.floorY, E.home.Z + off.Z)
end

-- `dir` turned round by `deg` degrees (flat)
local function turn(dir, deg)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
end

-- how far he can go from `from` along `dir` before crossing the circle of
-- radius `r` round the middle of the dig
local function toEdge(E, from, dir, r)
	local o = flat(from - E.home)
	local b = o:Dot(dir)
	local c = o:Dot(o) - r * r
	local disc = b * b - c
	if disc < 0 then
		return 0
	end
	return math.max(0, -b + math.sqrt(disc))
end

-- How high he is `e` seconds into a jump: up fast (slowing at the top) for
-- `rise` of the `air` seconds, held at `height` for `hang` more seconds, then
-- dropping faster and faster. (BossBodies/Burrowmore draws him with exactly
-- the same sum, so what you see is where he is.)
local function jumpHeight(e, air, rise, height, hang)
	hang = hang or 0
	if e <= 0 then
		return 0
	end
	local up = air * rise
	if e < up then
		local u = e / up
		return height * (1 - (1 - u) * (1 - u))
	end
	if e < up + hang then
		return height
	end
	local v = math.min((e - up - hang) / math.max(air - up, 1e-3), 1)
	return height * (1 - v * v)
end

-- how high he is right now (0 on the ground)
local function airHeight(E, t)
	local arc = E.arc
	if not arc then
		return 0
	end
	return jumpHeight(t - arc.t0, arc.air, arc.rise, arc.height, arc.hang)
end

-- The swing: everyone within `reach` in front of him (a wedge `arc` degrees
-- wide, centred on the way he faces) - and anyone right up against him.
local function hitArc(E, reach, arc, damage, knockback)
	local cosHalf = math.cos(math.rad(arc / 2))
	local landed = 0
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local off = flat(root.Position - E.pos)
			local d = off.Magnitude
			if d <= reach + PLAYER_RADIUS and (d < E.def.Size / 2 + PLAYER_RADIUS or off.Unit:Dot(E.facing) >= cosHalf) then
				if CombatService.DamagePlayer(p, damage, E.pos, knockbackFrom(E.pos, root, knockback)) then
					landed = landed + 1
				end
			end
		end
	end
	return landed
end

-- One jump onto his target. He takes off at `tA` from where he stands; while
-- he's up, the landing spot FOLLOWS the target (no faster than a.Follow studs
-- a second) until a.Lock of the way through the jump - then it's committed.
-- The take-off and landing are published in slots `slotA` and `slotB` (the
-- landing is re-published as it moves, so every screen's circle follows too).
-- `hop` (optional) = the furthest one jump can go. Lands with a hit round the
-- landing spot. Returns the landing time, or nil if the fight moved on.
local function leap(E, token, a, tA, slotA, slotB, hop)
	local hang = a.Hang or 0
	local total = a.Air + hang
	local tB = tA + total
	local tL = tA + total * a.Lock
	local A = Vector3.new(E.pos.X, E.floorY, E.pos.Z)
	local function aimFrom(p)
		if hop then
			local off = flat(p - A)
			if off.Magnitude > hop then
				p = A + off.Unit * hop
			end
		end
		return inside(E, p, E.def.Leash)
	end
	local B = aimFrom(targetPosition(E) or (A + E.facing * 16))
	E.track = false
	E.facing = unitOr(flat(B - A), E.facing)
	setSlot(E, slotA, A)
	setSlot(E, slotB, B)
	E.arc = { t0 = tA, air = a.Air, rise = a.Rise, height = a.Height, hang = hang }
	E.motion = { from = A, to = B, t0 = tA, t1 = tB }
	local last, sent = now(), now()
	while now() < tL do
		if not valid(E, token) then
			return nil
		end
		local t = now()
		local dt = t - last
		last = t
		local aim = targetPosition(E)
		if aim then
			local want = aimFrom(aim)
			local step = flat(want - B)
			local most = a.Follow * dt
			if step.Magnitude > most then
				step = step.Unit * most
			end
			B = B + step
			E.motion.to = B
			local dir = flat(B - A)
			if dir.Magnitude > 0.5 then
				E.facing = dir.Unit
			end
			if t - sent >= 0.05 then
				sent = t
				E.model:SetAttribute(SLOTS[slotB], B) -- every screen moves its circle
			end
		end
		task.wait()
	end
	-- committed: the circle locks (and flashes on every screen)
	E.model:SetAttribute(SLOTS[slotB], B)
	E.motion.to = B
	if not waitUntil(E, token, tB) then
		return nil
	end
	E.motion, E.arc = nil, nil
	E.pos = B
	hitArea(E, B, a.Radius, a.Damage, a.Knockback)
	return tB
end

----------------------------------------------------------------------
-- The moves (each needs an entry of the same name in Config's Attacks)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- SHOVEL DROP (and the DELAYED DROP: the same, but with Hang - he holds at
-- the top after the circle locks). He crouches facing you, leaps, follows
-- you from above, drops shovel-first, bounces once, and tugs his shovel out.
local function drop(E, token, name)
	local a = E.def.Attacks[name]
	E.track = true
	local t0 = setAction(E, name, nil)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local tB = leap(E, token, a, t0 + a.Tell, 1, 2)
	if not tB then
		return
	end
	waitUntil(E, token, tB + a.Bounce + recovery(E, a.Recovery))
end

function Attacks.ShovelDrop(E, token)
	drop(E, token, "ShovelDrop")
end

function Attacks.DelayedDrop(E, token)
	drop(E, token, "DelayedDrop")
end

-- TRIPLE POGO: a long crouch (he glows), then three hops, each landing aimed
-- at you. Slots 1-2 are the first hop's take-off and landing, 3-4 the
-- second's, 5-6 the third's. Dizzy after the last.
function Attacks.TriplePogo(E, token)
	local a = E.def.Attacks.TriplePogo
	E.track = true
	local t0 = setAction(E, "TriplePogo", nil)
	for i = 1, a.Hops do
		local tA = t0 + a.Tell + (i - 1) * (a.Air + a.Ground)
		if not waitUntil(E, token, tA) then
			return
		end
		if not leap(E, token, a, tA, 2 * i - 1, 2 * i, a.Hop) then
			return
		end
	end
	waitUntil(E, token, t0 + a.Tell + a.Hops * a.Air + (a.Hops - 1) * a.Ground + recovery(E, a.Recovery))
end

-- SHOVEL SWING: he winds up turning to face you, commits (a spot straight
-- ahead goes in slot `slot`, so every screen draws the wedge exactly where
-- it'll hit), then sweeps. The swing-into-drop uses it too.
local function swing(E, token, t0, a, damage, slot)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return false
	end
	E.track = false
	setSlot(E, slot, Vector3.new(E.pos.X, E.floorY, E.pos.Z) + E.facing * a.Reach)
	if not waitUntil(E, token, t0 + a.Tell) then
		return false
	end
	hitArc(E, a.Reach, a.Arc, damage, a.Knockback)
	return true
end

function Attacks.ShovelSwing(E, token)
	local a = E.def.Attacks.ShovelSwing
	E.track = true
	local t0 = setAction(E, "ShovelSwing", nil)
	if not swing(E, token, t0, a, a.Damage, 1) then
		return
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- SWING INTO DROP (phase two): the swing, a short crouch, and up into a drop.
-- Slot 1 is the swing's aim, slots 2-3 the jump's take-off and landing.
function Attacks.SwingDrop(E, token)
	local a = E.def.Attacks.SwingDrop
	E.track = true
	local t0 = setAction(E, "SwingDrop", nil)
	if not swing(E, token, t0, a, a.SwingDamage, 1) then
		return
	end
	E.track = true
	local tA = t0 + a.Tell + a.Crouch
	if not waitUntil(E, token, tA) then
		return
	end
	local tB = leap(E, token, a, tA, 2, 3)
	if not tB then
		return
	end
	waitUntil(E, token, tB + a.Bounce + recovery(E, a.Recovery))
end

-- DIRT FLING: he digs in facing you, commits, and flings a fan of clods
-- (slots 1..Clods: where each lands) that all land together. However many
-- circles you're standing in, one clod's worth is all that hits you.
function Attacks.DirtFling(E, token)
	local a = E.def.Attacks.DirtFling
	E.track = true
	local t0 = setAction(E, "DirtFling", nil)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return
	end
	E.track = false
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local aim = targetPosition(E)
	local d = aim and math.clamp(flatDistance(aim, E.pos), a.Near, a.Far) or (a.Near + a.Far) / 2
	local spots = {}
	for i = 1, a.Clods do
		local dir = turn(E.facing, (i - (a.Clods + 1) / 2) * a.Spread)
		spots[i] = inside(E, E.pos + dir * d, E.def.Leash + 8)
		setSlot(E, i, spots[i])
	end
	local landAt = t0 + a.Tell + a.Flight
	task.spawn(function()
		if waitUntil(E, token, landAt) then
			local struck = {}
			for _, spot in ipairs(spots) do
				hitArea(E, spot, a.Radius, a.Damage, a.Knockback, struck)
			end
		end
	end)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- ANCHOR TOSS: he holds up the anchor, swings it round facing you, commits,
-- and lobs it at where you're heading (slot 1: where it lands). It lands with
-- a crash and sticks - he tugs at the chain the whole time he's open.
function Attacks.AnchorToss(E, token)
	local a = E.def.Attacks.AnchorToss
	E.track = true
	local t0 = setAction(E, "AnchorToss", nil)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return
	end
	E.track = false
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local root = E.target and rootOf(E.target)
	local aim = targetPosition(E) or (E.pos + E.facing * 30)
	if root then
		aim = aim + flat(root.AssemblyLinearVelocity) * a.Lead -- (where you'll be if you keep going)
	end
	aim = inside(E, aim, E.def.Leash + 6)
	setSlot(E, 1, aim)
	if not waitUntil(E, token, t0 + a.Tell + a.Flight) then
		return
	end
	hitArea(E, aim, a.Radius, a.Damage, a.Knockback)
	waitUntil(E, token, t0 + a.Tell + a.Flight + recovery(E, a.Recovery))
end

-- FIRE STICK: he raises the wand, then shoots fireballs one after another,
-- turning to aim each at you. Fireball k's start and end are slots 2k-1 and
-- 2k. Each rolls along the floor at a.Speed and hits whoever it touches -
-- unless they're jumping over it (or rolling through it).
function Attacks.FireStick(E, token)
	local a = E.def.Attacks.FireStick
	E.track = true
	local t0 = setAction(E, "FireStick", nil)
	for k = 1, a.Balls do
		local launch = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, launch) then
			return
		end
		local aim = targetPosition(E)
		local dir = aim and unitOr(flat(aim - E.pos), E.facing) or E.facing
		local from = Vector3.new(E.pos.X, E.floorY, E.pos.Z) + dir * (E.def.Size / 2 + 1)
		local len = math.max(8, math.min(a.Reach, toEdge(E, from, dir, E.def.Leash + 10)))
		local to = from + dir * len
		setSlot(E, 2 * k - 1, from)
		setSlot(E, 2 * k, to)
		task.spawn(function()
			local struck = {}
			while valid(E, token) do
				local gone = (now() - launch) * a.Speed
				if gone > len then
					return
				end
				local p = from + dir * math.max(gone, 0)
				for _, pl in ipairs(fightersIn(E)) do
					if not struck[pl] then
						local root = rootOf(pl)
						if root and flatDistance(root.Position, p) <= a.Radius + PLAYER_RADIUS
							and root.Position.Y - (E.floorY + STAND_HEIGHT) < a.Height * 0.8 then
							struck[pl] = true
							CombatService.DamagePlayer(pl, a.Damage, p, knockbackFrom(p, root, a.Knockback))
						end
					end
				end
				task.wait()
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Balls - 1) * a.Gap + recovery(E, a.Recovery))
end

-- CHARGE DASH: he crouches and scrapes his shovel, facing you, then commits:
-- the lane is fixed (slot 1 = where he starts, slot 2 = where he stops, and
-- slot 3 = the same again if he'll run into the edge of the dig). He charges
-- down it, running over anyone in the way. A crash into the edge stuns him longer.
function Attacks.ChargeDash(E, token)
	local a = E.def.Attacks.ChargeDash
	E.track = true
	local t0 = setAction(E, "ChargeDash", nil)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return
	end
	E.track = false
	local from = Vector3.new(E.pos.X, E.floorY, E.pos.Z)
	local aim = targetPosition(E)
	local dir = aim and unitOr(flat(aim - from), E.facing) or E.facing
	local want = math.min((aim and flatDistance(aim, from) or 40) + a.Overshoot, a.MaxDistance)
	local room = toEdge(E, from, dir, E.def.Leash)
	local len = math.min(want, room)
	local crash = room <= want
	if len < 10 then
		-- (no room to charge that way: he flings dirt instead)
		Attacks.DirtFling(E, token)
		return
	end
	E.facing = dir
	local to = from + dir * len
	local travel = len / a.Speed
	E.model:SetAttribute("ActN", travel)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	if crash then
		setSlot(E, 3, to)
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local start = now()
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	E.sweep = { radius = a.Width, damage = a.Damage, knockback = a.Knockback, hit = {} }
	if not waitUntil(E, token, start + travel) then
		return
	end
	E.motion, E.sweep = nil, nil
	E.pos = to
	waitUntil(E, token, start + travel + recovery(E, crash and a.WallStun or a.Recovery))
end

-- TAUNT: he plants his shovel and laughs at you (the Black Knight would be
-- proud). Nothing hurts - it's your chance.
function Attacks.Taunt(E, token)
	local a = E.def.Attacks.Taunt
	E.track = true
	local t0 = setAction(E, "Taunt", nil)
	waitUntil(E, token, t0 + a.Time)
end

-- GEM RAIN (phase two): he strikes the ground, and for a few seconds treasure
-- falls into circles round everyone fighting him - while he gets on with his
-- next moves. Each gem is picked a.Gap after the last and lands a.Fuse later.
local function clearRain(E)
	local m = E.model
	m:SetAttribute("RainAt", nil)
	m:SetAttribute("RainK", nil)
	for i = 1, RAIN_SLOTS do
		m:SetAttribute("Rain" .. i, nil)
	end
end

function Attacks.GemRain(E, token)
	local a = E.def.Attacks.GemRain
	if E.rainUntil and now() < E.rainUntil then
		-- (it's still raining from the last one: a drop instead)
		drop(E, token, "ShovelDrop")
		return
	end
	E.track = true
	local t0 = setAction(E, "GemRain", nil)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local gems = math.min(a.Gems, RAIN_SLOTS)
	local start = t0 + a.Tell
	E.rainUntil = start + (gems - 1) * a.Gap + a.Fuse
	clearRain(E)
	E.model:SetAttribute("RainAt", start)
	E.model:SetAttribute("RainK", 0)
	task.spawn(function()
		for i = 1, gems do
			local pickAt = start + (i - 1) * a.Gap
			if not waitUntil(E, token, pickAt) then
				return
			end
			-- round everyone in turn, landing somewhere near where they are
			local list = fightersIn(E)
			local victim = list[((i - 1) % math.max(#list, 1)) + 1]
			local root = victim and rootOf(victim)
			local near = root and root.Position or E.pos
			local ang = E.rng:NextNumber() * math.pi * 2
			local r = a.Spread * math.sqrt(E.rng:NextNumber())
			local spot = inside(E, near + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r), E.def.Leash + 5)
			E.model:SetAttribute("Rain" .. i, spot)
			E.model:SetAttribute("RainK", i)
			task.spawn(function()
				if waitUntil(E, token, pickAt + a.Fuse) then
					hitArea(E, spot, a.Radius, a.Damage, a.Knockback)
				end
			end)
		end
	end)
	waitUntil(E, token, start + recovery(E, a.Recovery))
end

-- SHOVEL METEOR (phase two, his final move): a deep crouch, and he launches
-- himself straight up out of sight. While he's up there a huge shadow grows
-- in the middle of the dig (slot 1). Then he comes down on it like a meteor -
-- everyone inside Radius is hit hard - and he's stuck in the ground, shovel
-- buried, for a.Stuck seconds (not shortened by anything: it's the reward
-- for getting clear).
local function meteor(E, token)
	local a = E.def.Attacks.ShovelMeteor
	E.meteorDone = true
	E.track = false
	local t0 = setAction(E, "ShovelMeteor", nil)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local tA = t0 + a.Tell
	local land = tA + a.Up + a.Fall
	local center = Vector3.new(E.home.X, E.floorY, E.home.Z)
	setSlot(E, 1, center)
	-- (up in a.Up, held far out of sight, and the last 0.3s straight down)
	E.arc = { t0 = tA, air = a.Up + 0.3, rise = a.Up / (a.Up + 0.3), height = 90, hang = a.Fall - 0.3 }
	E.motion = { from = Vector3.new(E.pos.X, E.floorY, E.pos.Z), to = center, t0 = tA + a.Up, t1 = land - 0.3 }
	if not waitUntil(E, token, land) then
		return
	end
	E.motion, E.arc = nil, nil
	E.pos = center
	hitArea(E, center, a.Radius, a.Damage, a.Knockback)
	waitUntil(E, token, land + a.Stuck)
end

function Attacks.ShovelMeteor(E, token)
	if healthShare(E) > (E.def.MeteorAt or 0) + 1e-6 then
		drop(E, token, "DelayedDrop") -- (not yet: saved for the end)
		return
	end
	meteor(E, token)
end

-- The first time he's below MeteorAt in phase two, whatever move the brain
-- picked, the Shovel Meteor comes instead - so everyone sees his final move.
local function wantsMeteor(E)
	return E.phase >= 2 and not E.meteorDone and healthShare(E) <= (E.def.MeteorAt or 0) + 1e-6
end
do
	local names = {}
	for name in pairs(Attacks) do
		if name ~= "ShovelMeteor" then
			table.insert(names, name)
		end
	end
	for _, name in ipairs(names) do
		local move = Attacks[name]
		Attacks[name] = function(E, token)
			if wantsMeteor(E) then
				meteor(E, token)
				return
			end
			move(E, token)
		end
	end
end
Boss._Meteor = meteor -- (for tests: the final move itself, whatever his health)

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
-- Built: CombatService asks where his body really is when you punch - high
-- in the air (a drop, a pogo, the meteor) he's out of your reach.
function Boss.onBuild(E)
	CombatService.SetTargetShape(E.model, function(_from)
		local up = airHeight(E, now())
		return Vector3.new(E.pos.X, E.floorY + up + E.height / 2, E.pos.Z), E.def.Size / 2
	end)
end

-- Everyone left or died: back to kneeling, everything forgotten
function Boss.onReset(E)
	E.arc, E.meteorDone, E.rainUntil = nil, nil, nil
	clearRain(E)
end

-- The armour cracks mid-move: he lands wherever he was
function Boss.onBreak(E)
	E.arc = nil
end

function Boss.onDie(E)
	E.arc, E.rainUntil = nil, nil
	clearRain(E)
end

-- (for tests and BossBodies: the same jump sum)
Boss.jumpHeight = jumpHeight

return Boss
