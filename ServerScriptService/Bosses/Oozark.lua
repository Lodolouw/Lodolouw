--[[
	Oozark  (ModuleScript, parent: ServerScriptService > Bosses, name: "Oozark")

	Floor 1's boss: Oozark, the Gelatinous Tyrant (Config.Bosses[1]) - the slime
	that fights on the surface and trades blows with you. This file is only ITS
	attacks. Everything a surface boss shares lives in BossService: waking up,
	picking a target, choosing an attack that suits the distance (from
	Config.Bosses[1].Attacks), moving and turning, its waves and puddles, the
	shell breaking at half health, resetting, dying and the rewards.

	HOW A BOSS FILE WORKS (see _Template.lua for a new one):
	  * BossService finds this file by the boss's short name in Config
	    (Short = "Oozark") and calls Boss.init(kit) once, handing over the
	    shared helpers (setAction, waitUntil, hitArea, ...).
	  * Boss.Attacks[name](E, token) runs one attack. Each attack in
	    Config.Bosses[1].Attacks needs a function here with the same name.
	    E is the encounter (where it is, who it's after, its health...); token
	    is checked by every wait, so a reset or a death stops the attack.
	  * Every attack publishes what it's doing (setAction, setSlot) so each
	    player's screen (BossClient + ReplicatedStorage/BossBodies/Oozark) can
	    draw the warning at exactly the moment the server will hit.
]]

local Boss = {}

-- The shared helpers these attacks use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, stoneUnder, besideStone, hitArea, recovery, targetPosition

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil = kit.setAction, kit.setSlot, kit.waitUntil
	stoneUnder, besideStone, hitArea, recovery, targetPosition = kit.stoneUnder, kit.besideStone, kit.hitArea, kit.recovery, kit.targetPosition
end

----------------------------------------------------------------------
-- The attacks
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks


-- Rears up, wobbles at the top, drops its whole bulk where it stands.
function Attacks.Slam(E, token)
	local a = E.def.Attacks.Slam
	E.track = true
	local t0 = setAction(E, "Slam", a.Radius)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	hitArea(E, E.pos, a.Radius, a.Damage, a.Knockback)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- Flattens, then pushes a wall of slime outward along the floor. The wall is
-- tracked every frame (see stepWaves) so it hits exactly as it's drawn.
function Attacks.Wave(E, token)
	local a = E.def.Attacks.Wave
	E.track = true
	local t0 = setAction(E, "Wave", a.Speed)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	setSlot(E, 1, E.pos)
	table.insert(E.waves, {
		origin = E.pos,
		start = E.def.Size / 2, -- it rolls out from under the body's edge
		t0 = t0 + a.Tell,
		speed = a.Speed,
		reach = a.Reach,
		thickness = a.Thickness,
		height = a.Height,
		damage = a.Damage,
		knockback = a.Knockback,
		lastR = E.def.Size / 2,
		hit = {},
	})
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- Roots itself and spits globs at where you're standing. Each lands after a
-- flight, hits around where it lands, and leaves a burning puddle.
function Attacks.Spit(E, token)
	local a = E.def.Attacks.Spit
	E.track = true
	local t0 = setAction(E, "Spit", a.Flight)
	for i = 1, a.Globs do
		local spitAt = t0 + a.Tell + (i - 1) * a.Gap
		if not waitUntil(E, token, spitAt) then
			return
		end
		-- The barrage: the first glob goes where you're standing, the next where
		-- you're heading, and the rest spray around you in a widening circle, so
		-- stepping aside isn't enough - you have to read the markers and move
		-- through the gaps. In a party it takes turns on everyone.
		local list = fightersIn(E)
		local victim = (#list > 1) and list[((i - 1) % #list) + 1] or E.target
		local root = victim and rootOf(victim)
		local aim
		if root then
			local here = flat(root.Position) + Vector3.new(0, E.floorY, 0)
			local vel = flat(root.AssemblyLinearVelocity)
			if i == 1 then
				aim = here
			elseif i == 2 then
				aim = here + vel * a.Flight -- where you'll be if you keep going
			else
				local spread = a.Spread * math.sqrt(E.rng:NextNumber())
				local ang = E.rng:NextNumber() * math.pi * 2
				aim = here + vel * a.Flight * 0.5 + Vector3.new(math.cos(ang) * spread, 0, math.sin(ang) * spread)
			end
		else
			aim = E.pos + E.facing * 20
		end
		-- never off the edge of the fighting floor
		local off = flat(aim - E.home)
		if off.Magnitude > E.def.Leash + 30 then
			aim = E.home + off.Unit * (E.def.Leash + 30)
		end
		aim = Vector3.new(aim.X, E.floorY, aim.Z)
		setSlot(E, i, aim)
		task.spawn(function()
			if waitUntil(E, token, spitAt + a.Flight) then
				hitArea(E, aim, a.Radius, a.Damage, 18)
				if stoneUnder(E, aim) then
					return -- it lands on stone: nothing for it to sink into
				end
				table.insert(E.puddles, {
					pos = aim,
					radius = a.Puddle,
					untilT = now() + a.PuddleTime,
					nextTick = now() + a.PuddleTick,
					tick = a.PuddleTick,
					damage = a.PuddleDamage,
				})
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Globs - 1) * a.Gap + recovery(E, a.Recovery))
end

-- Leans back, then hurls itself at where you were when it committed.
function Attacks.Lunge(E, token)
	local a = E.def.Attacks.Lunge
	E.track = true
	local t0 = setAction(E, "Lunge", nil)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local from = E.pos
	local aim = targetPosition(E) or (from + E.facing * a.MaxDistance)
	local offset = flat(aim - from)
	local distance = math.min(offset.Magnitude, a.MaxDistance)
	local dir = unitOr(offset, E.facing)
	local to = from + dir * distance
	-- never out past its leash
	local fromHome = flat(to - E.home)
	if fromHome.Magnitude > E.def.Leash then
		to = E.home + fromHome.Unit * E.def.Leash
	end
	local travel = math.max(0.25, flatDistance(to, from) / a.Speed)
	E.facing = dir
	E.model:SetAttribute("ActN", travel)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local start = now()
	local struck = {}
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	E.sweep = { radius = E.def.Size / 2 + 0.5, damage = a.Damage, knockback = a.Knockback, hit = struck }
	if not waitUntil(E, token, start + travel) then
		return
	end
	E.motion, E.sweep = nil, nil
	E.pos = to
	-- the landing splashes anyone it didn't already run through
	hitArea(E, to, a.Splash, a.Damage, a.Knockback, struck)
	waitUntil(E, token, start + travel + recovery(E, a.Recovery))
end

-- Phase two: three slams in a row, hopping after you between them, each with
-- a tighter radius. The roll's cooldown makes this just about dodgeable.
function Attacks.TripleSlam(E, token)
	local a = E.def.Attacks.TripleSlam
	E.track = true
	local t0 = setAction(E, "TripleSlam", a.Gap)
	setSlot(E, 1, E.pos)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	hitArea(E, E.pos, a.Radii[1], a.Damage, a.Knockback)
	for i = 2, 3 do
		local from = E.pos
		local aim = targetPosition(E) or from
		local step = flat(aim - from)
		if step.Magnitude > a.Hop then
			step = step.Unit * a.Hop
		end
		local to = from + step
		if flat(to - E.home).Magnitude > E.def.Leash then
			to = from
		end
		E.facing = unitOr(step, E.facing)
		setSlot(E, i, to)
		local landAt = t0 + a.Tell + (i - 1) * a.Gap
		E.motion = { from = from, to = to, t0 = now(), t1 = landAt }
		if not waitUntil(E, token, landAt) then
			return
		end
		E.motion = nil
		E.pos = to
		hitArea(E, to, a.Radii[i], a.Damage, a.Knockback)
	end
	waitUntil(E, token, t0 + a.Tell + 2 * a.Gap + recovery(E, a.Recovery))
end

-- Phase two: rings bloom under the players' feet one after another and erupt
-- after a fuse. Standing still - or stopping to drink - gets you hit.
function Attacks.Wail(E, token)
	local a = E.def.Attacks.Wail
	E.track = true
	local t0 = setAction(E, "Wail", a.Fuse)
	for i = 1, a.Rings do
		local bloomAt = t0 + a.Tell + (i - 1) * a.Gap
		if not waitUntil(E, token, bloomAt) then
			return
		end
		-- the first ring is for its target; the rest go round the party
		local list = fightersIn(E)
		if E.target and table.find(list, E.target) then
			table.remove(list, table.find(list, E.target))
			table.insert(list, 1, E.target)
		end
		local victim = list[((i - 1) % math.max(#list, 1)) + 1]
		local root = victim and rootOf(victim)
		local at = root and (flat(root.Position) + Vector3.new(0, E.floorY, 0)) or (E.pos + E.facing * 15)
		-- it can't come up through stone: it erupts on the sand beside it
		local stone = stoneUnder(E, at)
		if stone then
			at = besideStone(E, stone, at, E.pos, a.Radius * 0.8)
		end
		setSlot(E, i, at)
		task.spawn(function()
			if waitUntil(E, token, bloomAt + a.Fuse) then
				hitArea(E, at, a.Radius, a.Damage, a.Knockback, nil, true)
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Rings - 1) * a.Gap + a.Fuse + recovery(E, a.Recovery))
end

return Boss
