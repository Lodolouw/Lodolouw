--[[
	_Template  (ModuleScript, parent: ServerScriptService > Bosses, name: "_Template")

	NOT A REAL BOSS: a starting point for a new one. (Nothing loads it: bosses
	are found by their short name in Config.Bosses, and none is "_Template".)
	It's a tiny working surface boss with one attack, STOMP, and the headless
	test Tools/HeadlessTests/test_boss_template.luau fights it to prove it works.

	HOW TO ADD A BOSS
	  1. Copy this file here, next to itself, and name the copy after the new
	     boss's short name - e.g. "Frostjaw" -> ServerScriptService/Bosses/Frostjaw.lua.
	  2. Copy ReplicatedStorage/BossBodies/_Template.lua the same way (its body:
	     what players see).
	  3. In Config.Bosses, add it on its floor: copy Oozark's entry (floor 1)
	     and change it - Short = "Frostjaw", its Name, Size, colours, health...
	     and its Attacks: one entry per attack in this file, with the same name
	     (Tell, Damage, Radius, Knockback, Recovery, Range = { min, max }
	     distance it's used from, Weight = how often, Phase = 1 or 2).
	  4. Give it an arena with a part tagged "BossHome" (attributes: Floor =
	     its floor, Facing = the way it faces) - built like LobbyBuilder's slime
	     arena or DunesBuilder - and its floor in Config.Spire.Floors.

	WHAT BOSSSERVICE DOES FOR IT (you don't write any of this)
	  Waking up when someone comes near, picking who to fight, choosing an
	  attack that suits the distance (from Config), walking after them and
	  turning to face them, its health and the break at half health (phase
	  two: its Phase = 2 attacks join in), resetting when everyone's gone,
	  dying, and the rewards. BossService.lua explains all of it.

	WHAT THIS FILE DOES: its attacks. Each one:
	  * publishes what it's doing with setAction(E, "Name", number) - every
	    player's screen starts drawing its warning at that moment (the body
	    file's Starts.Name and Poses.Name) - and positions with setSlot(E, i, v);
	  * waits with waitUntil(E, token, time), which returns false if the fight
	    was reset or won meanwhile (then the attack just stops);
	  * hurts players with hitArea(E, center, radius, damage, knockback).

	MORE A BOSS CAN DO (see Bosses/Nahrzul.lua, which uses all of these)
	  Boss.brain(E, token)  its own way of fighting instead of the shared one
	  Boss.step(E, dt)      its own every-frame step (movement, hazards)
	  Boss.onBuild(E), Boss.onReset(E), Boss.onHome(E), Boss.onDie(E),
	  Boss.onBreak(E)       extras at those moments
	  Every shared helper is in BossService's makeKit list.
]]

local Boss = {}

-- The shared helpers its attacks use, from BossService (see Boss.init)
local setAction, waitUntil, hitArea, recovery

function Boss.init(kit)
	setAction, waitUntil, hitArea, recovery = kit.setAction, kit.waitUntil, kit.hitArea, kit.recovery
end

----------------------------------------------------------------------
-- The attacks (each needs an entry of the same name in Config's Attacks)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- STOMP: it turns to face its target while a red circle fills in round it
-- for Tell seconds, then everyone inside Radius is hit and thrown back.
--   E      the encounter: E.pos (where it is), E.def (its Config), E.target...
--   token  handed to every wait: if the fight is reset or won meanwhile, the
--          wait returns false and the attack stops there
function Attacks.Stomp(E, token)
	local a = E.def.Attacks.Stomp
	E.track = true -- (it keeps turning to face its target while it winds up)
	local t0 = setAction(E, "Stomp", a.Radius) -- every screen starts the warning now
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false -- (committed: it lands where it's facing)
	hitArea(E, E.pos, a.Radius, a.Damage, a.Knockback)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

return Boss
