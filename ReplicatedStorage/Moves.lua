--[[
	Moves  (ModuleScript, parent: ReplicatedStorage, name: "Moves")

	What each weapon's ability DOES, step by step - read by the server (what it
	hits), by your own screen (your dash or leap, and the ability's animation)
	and by every screen (the effects: ReplicatedStorage/MoveFX). One list, so
	they can't disagree. By weapon id (Config.Weapons.List); the ability's
	cooldown, stamina cost and building blocks (Effects: damage up, guard...)
	stay in Config with the weapon.

	A move:
	  Time    how long it commits you (no walking, no swings), seconds
	  Style   how its effects look (MoveFX.STYLES: colours and bits)
	  Anim    its animation's name in AssetIds.Animations (default: the weapon id)
	  Steps   what happens when, each one:
	    At      seconds after you press it
	    Mark    remember where you are now under this name (for Line hits and
	            Strip zones: "Start", "End")
	    Pick    choose a spot and remember it under this name ("T"): the enemy
	            you're locked on to, or the nearest one in front within Range,
	            else Ahead studs in front of you - every screen is told where
	    Move    YOUR screen moves you (the server trusts where you end up):
	              { Kind = "Dash", Distance, Time, ToTarget, StopShort, StopAt }  - along
	                the floor (StopAt: stop on running into an enemy that close)
	              { Kind = "Leap", Distance, Up, Time, ToTarget, StopShort } - up and over,
	                landing exactly when Time runs out
	              { Kind = "Hop", Distance, Up, Time }   - a small jump forward
	    Hit     the server hits (x your hit, like a swing; Weight 1-3 is how hard
	            it lands):
	              { Shape = "Circle", Radius, Ahead, Side, At = "T" }  - round a spot
	              { Shape = "Arc", Radius, Arc }            - a cone in front (degrees each side)
	              { Shape = "Line", From = "Start", To, Ahead, Width } - along a path
	              ... and Damage, Weight
	    Zone    a patch left on the floor that hurts every Tick seconds for Time:
	              { Radius, Ahead, At = "T", Time, Tick, Damage, Slow }
	              { Strip = true, From = "Start", Width, ... } - along a path
	    Shot    things thrown (barrels, globs, clods), each flying along the floor:
	              { Count, Spread (degrees apart), Around (spread all the way
	                round), Speed, Range, Radius, Damage, Pierce (keeps going
	                through enemies), Burst = { Radius, Damage } (where it ends),
	                Zone = { ... } (left where it ends), Look (for MoveFX) }
	    Buff    a special effect for Time seconds (the Config Effects switch on
	            when you press): { Special = "ChopWave" | "Clones" | "DashHits", Time }
	    Fx      the name of an effect (MoveFX.RECIPES[weapon][Fx], else a shared one)
	    Shake   the camera shakes this much for anyone close
]]

local Moves = {}

----------------------------------------------------------------------
-- 1. SLIME (Oozark)
----------------------------------------------------------------------
Moves.GooGloves = { -- Sticky Fists: clap your gloves - goo splats, sticky fists for 4 s
	Time = 0.55, Style = "Slime",
	Steps = { { At = 0.18, Fx = "Clap" } },
}
Moves.Jellyblade = { -- Wobble Guard: the blade up, a wobbling jelly bubble round you
	Time = 0.6, Style = "Slime",
	Steps = { { At = 0.15, Fx = "JellyGuard" } },
}
Moves.GelatinHammer = { -- Goo Slam: hop and slam; a sticky puddle is left behind
	Time = 1.0, Style = "Slime",
	Steps = {
		{ At = 0, Move = { Kind = "Hop", Distance = 5, Up = 5, Time = 0.4 }, Fx = "Rise" },
		{ At = 0.42, Hit = { Shape = "Circle", Ahead = 4, Radius = 10, Damage = 1.8, Weight = 3 }, Fx = "Slam", Shake = 1.2 },
		{ At = 0.45, Zone = { Ahead = 4, Radius = 8, Time = 3, Tick = 0.5, Damage = 0.2, Slow = 0.4 }, Fx = "Puddle" },
	},
}
Moves.OozeDaggers = { -- Slime Trail: dash through them, a burning slime trail behind you
	Time = 0.75, Style = "Acid",
	Steps = {
		{ At = 0, Mark = "Start", Fx = "Crouch" },
		{ At = 0.1, Move = { Kind = "Dash", Distance = 16, Time = 0.28 }, Fx = "Streak" },
		{ At = 0.4, Mark = "End", Hit = { Shape = "Line", From = "Start", Width = 7, Ahead = 1, Damage = 2.1, Weight = 3 }, Fx = "Cut" },
		{ At = 0.42, Zone = { Strip = true, From = "Start", To = "End", Width = 4, Time = 3, Tick = 0.5, Damage = 0.25, Slow = 0.3 }, Fx = "Trail" },
	},
}
Moves.AcidScythe = { -- Acid Rain: a spinning sweep that flings three acid globs; they burst into puddles
	Time = 1.0, Style = "Acid",
	Steps = {
		{ At = 0.22, Hit = { Shape = "Circle", Radius = 11, Damage = 2.5, Weight = 3 }, Fx = "Spin", Shake = 0.8 },
		{ At = 0.3, Shot = { Count = 3, Around = true, Speed = 26, Range = 11, Radius = 3, Damage = 0.6, Look = "Glob",
			Burst = { Radius = 5, Damage = 1.0 }, Zone = { Radius = 5, Time = 3, Tick = 0.5, Damage = 0.2, Slow = 0.3 } }, Fx = "Fling" },
	},
}
Moves.GelatinousEdge = { -- Oozark's Jaw: a quick-draw - a giant ghostly jaw chomps everything in front
	Time = 1.1, Style = "Slime",
	Steps = {
		{ At = 0, Fx = "Draw" },
		{ At = 0.3, Fx = "Jaw" },
		{ At = 0.68, Hit = { Shape = "Arc", Radius = 15, Arc = 50, Damage = 3.0, Weight = 3 }, Fx = "Chomp", Shake = 2 },
	},
}

----------------------------------------------------------------------
-- 3. KNIGHT (Burrowmore)
----------------------------------------------------------------------
Moves.ShovelHammer = { -- Dig Slam: dig in - your next hit is a dig slam (MoveFX: DigSlam when it lands)
	Time = 0.6, Style = "Dirt",
	Steps = { { At = 0.28, Fx = "Dig" } },
}
Moves.RelicDaggers = { -- Treasure Eye: a golden glint - crits for 4 s, gold sparkles on every crit
	Time = 0.5, Style = "Gold",
	Steps = { { At = 0.12, Fx = "Glint" } },
}
Moves.SpadeScythe = { -- Dirt Spin: a low spin that flings dirt clods all round
	Time = 0.9, Style = "Dirt",
	Steps = {
		{ At = 0.24, Hit = { Shape = "Circle", Radius = 10, Damage = 1.8, Weight = 3 }, Fx = "Spin", Shake = 0.6 },
		{ At = 0.3, Shot = { Count = 6, Around = true, Speed = 30, Range = 9, Radius = 2.5, Damage = 0.4, Look = "Clod" }, Fx = "Clods" },
	},
}
Moves.HonourBlade = { -- Pogo Drop: leap high and plunge down on them blade-first - BOING, bounce off and plunge again
	Time = 1.45, Style = "Gold",
	Steps = {
		{ At = 0, Move = { Kind = "Leap", Distance = 10, Up = 11, Time = 0.55, ToTarget = true, StopShort = 1 }, Fx = "Jump" },
		{ At = 0.58, Hit = { Shape = "Circle", Radius = 8, Damage = 1.5, Weight = 3 }, Fx = "Plunge", Shake = 1.2 },
		{ At = 0.62, Move = { Kind = "Hop", Distance = 1, Up = 6, Time = 0.4 }, Fx = "Bounce" }, -- (almost straight up: you come down on them again)
		{ At = 1.04, Hit = { Shape = "Circle", Radius = 7, Damage = 1.0, Weight = 2 }, Fx = "Plunge2", Shake = 1.0 },
	},
}
Moves.AnchorFists = { -- Anchor Pull: throw an anchor on a chain; it drags you to them for a slam
	Time = 1.15, Style = "Iron",
	Steps = {
		{ At = 0, Pick = "T", Range = 20, Ahead = 16, Fx = "Throw" },
		{ At = 0.32, Move = { Kind = "Dash", Distance = 16, Time = 0.3, ToTarget = true, StopShort = 3 }, Fx = "Reel" },
		{ At = 0.66, Hit = { Shape = "Circle", Radius = 9, Damage = 2.5, Weight = 3 }, Fx = "Slam", Shake = 1.6 },
	},
}
Moves.NoQuarter = { -- No Quarter: your armour cracks gold for 8 s (a gold wave on every chop) and a meteor falls
	Time = 1.2, Style = "Gold",
	Steps = {
		{ At = 0, Fx = "Crack", Buff = { Special = "ChopWave", Time = 8 } },
		{ At = 0.6, Pick = "T", Range = 30, Ahead = 10, Fx = "Meteor" },
		{ At = 1.15, Hit = { Shape = "Circle", At = "T", Radius = 10, Damage = 2.5, Weight = 3 }, Fx = "Impact", Shake = 2.2 },
	},
}

----------------------------------------------------------------------
-- 5. SPEEDWAY (Revvington)
----------------------------------------------------------------------
Moves.TyreScythe = { -- Burnout: rev up - faster for 4 s, leaving skid marks
	Time = 0.5, Style = "Smoke",
	Steps = { { At = 0.1, Fx = "Rev" } },
}
Moves.NitroKatana = { -- Nitro: a blue flame bursts out behind you - stamina back, faster rolls
	Time = 0.5, Style = "Nitro",
	Steps = { { At = 0.08, Fx = "Boost" } },
}
Moves.PistonPunchers = { -- Piston Dash: a dash-punch forward with a flame trail
	Time = 0.75, Style = "Flame",
	Steps = {
		{ At = 0, Mark = "Start", Fx = "Pump" },
		{ At = 0.14, Move = { Kind = "Dash", Distance = 12, Time = 0.24, ToTarget = true, StopShort = 3 }, Fx = "Flames" },
		{ At = 0.4, Hit = { Shape = "Line", From = "Start", Ahead = 3, Width = 6, Damage = 1.8, Weight = 3 }, Fx = "Boom", Shake = 1 },
	},
}
Moves.PitStopSabre = { -- Skid Spin: a skid-turn spin in a cloud of tyre smoke - and the pit crew's four spare tyres go flying
	Time = 1.0, Style = "Smoke",
	Steps = {
		{ At = 0.2, Hit = { Shape = "Circle", Radius = 11, Damage = 1.7, Weight = 3 }, Fx = "SkidSpin", Shake = 0.8 },
		{ At = 0.3, Shot = { Count = 4, Around = true, Speed = 28, Range = 16, Radius = 2.5, Damage = 0.5, Pierce = true, Look = "Tyre" }, Fx = "Tyres" },
	},
}
Moves.WheelieWrecker = { -- Wheelie: charge forward on a flaming wheel, then slam down
	Time = 1.35, Style = "Flame",
	Steps = {
		{ At = 0, Mark = "Start", Fx = "Wheel" },
		{ At = 0.08, Move = { Kind = "Dash", Distance = 18, Time = 0.78 } },
		{ At = 0.5, Hit = { Shape = "Circle", Radius = 5, Damage = 0.6, Weight = 1 } },
		{ At = 0.86, Hit = { Shape = "Line", From = "Start", Width = 6, Damage = 0.8, Weight = 2 } },
		{ At = 1.02, Hit = { Shape = "Circle", Ahead = 3, Radius = 10, Damage = 2.0, Weight = 3 }, Fx = "Slam", Shake = 1.6 },
	},
}
Moves.VictoryLap = { -- Victory Lap: GO! a blur for 6 s - every roll hits - then a finish-line blast
	Time = 0.6, Style = "Checker",
	Steps = {
		{ At = 0, Fx = "Go", Buff = { Special = "DashHits", Time = 6 } },
		{ At = 6, Hit = { Shape = "Circle", Radius = 12, Damage = 2.5, Weight = 3 }, Fx = "Finish", Shake = 1.8 },
	},
}

----------------------------------------------------------------------
-- 7. JUNGLE (Kongo)
----------------------------------------------------------------------
Moves.ChestPoundFists = { -- Roar: pound your chest left-right-left and roar - more damage for 4 s
	Time = 0.8, Style = "Rage",
	Steps = {
		{ At = 0.05, Fx = "Pound" },
		{ At = 0.4, Fx = "Roar", Shake = 0.6 },
	},
}
Moves.JungleFang = { -- Fang: a red fang flash - your hits heal you for 5 s
	Time = 0.5, Style = "Blood",
	Steps = { { At = 0.1, Fx = "Fang" } },
}
Moves.VineScythe = { -- Vine Swing: swing forward on a vine into a sweeping arc
	Time = 1.0, Style = "Leaf",
	Steps = {
		{ At = 0, Fx = "Vine" },
		{ At = 0.04, Move = { Kind = "Leap", Distance = 12, Up = 6, Time = 0.55, ToTarget = true, StopShort = 3 } },
		{ At = 0.62, Hit = { Shape = "Arc", Radius = 11, Arc = 80, Damage = 1.8, Weight = 3 }, Fx = "Sweep", Shake = 0.8 },
	},
}
Moves.BarrelDaggers = { -- Barrel Roll: curl up inside a barrel and roll right through them - it bursts apart at the end
	Time = 0.8, Style = "Wood",
	Steps = {
		{ At = 0, Mark = "Start", Fx = "Barrel" },
		{ At = 0.06, Move = { Kind = "Dash", Distance = 16, Time = 0.46, ToTarget = true, StopShort = 1, StopAt = 2.5 } },
		-- (it bursts the moment it rolls into an enemy - Contact - or at the end)
		{ At = 0.52, Contact = 2.5, Hit = { Shape = "Line", From = "Start", Width = 6, Damage = 2.1, Weight = 3 }, Fx = "Burst", Shake = 0.9 },
	},
}
Moves.BarrelHammer = { -- Barrel Toss: bat two barrels forward; they roll and blow up
	Time = 0.9, Style = "Wood",
	Steps = {
		{ At = 0.34, Shot = { Count = 2, Spread = 30, Speed = 24, Range = 18, Radius = 3.5, Damage = 1.6, Pierce = true, Look = "BigBarrel",
			Burst = { Radius = 7, Damage = 1.2 } }, Fx = "Bat", Shake = 0.6 },
	},
}
Moves.KongsCrown = { -- Sky Fist: a giant ape fist smashes down from the sky
	Time = 1.3, Style = "Gold",
	Steps = {
		{ At = 0, Pick = "T", Range = 30, Ahead = 10, Fx = "Call" },
		{ At = 0.15, Fx = "SkyFist" },
		{ At = 0.9, Hit = { Shape = "Circle", At = "T", Radius = 12, Damage = 3.0, Weight = 3 }, Fx = "Impact", Shake = 2.4 },
	},
}

----------------------------------------------------------------------
-- 9. CANVAS (Scribble)
----------------------------------------------------------------------
Moves.EraserHammer = { -- Erase: rub the eraser - your next hit erases their armour (MoveFX: Erased when it lands)
	Time = 0.6, Style = "Eraser",
	Steps = { { At = 0.2, Fx = "Rub" } },
}
Moves.PencilSword = { -- Sharpen: shavings fly - longer reach and ink trails for 4 s
	Time = 0.5, Style = "Ink",
	Steps = { { At = 0.1, Fx = "Sharpen" } },
}
Moves.InkFists = { -- Ink Splash: hop and pound the ground in a splash of ink
	Time = 0.85, Style = "Ink",
	Steps = {
		{ At = 0, Move = { Kind = "Hop", Distance = 3, Up = 5, Time = 0.35 } },
		{ At = 0.37, Hit = { Shape = "Circle", Ahead = 2, Radius = 10, Damage = 1.8, Weight = 3 }, Fx = "Splash", Shake = 1 },
	},
}
Moves.DoodleKatana = { -- Doodle Clone: dash-slash; a doodle of you repeats it a second later
	Time = 0.8, Style = "Doodle",
	Steps = {
		{ At = 0, Mark = "Start", Fx = "Doodle" },
		{ At = 0.1, Move = { Kind = "Dash", Distance = 16, Time = 0.26 } },
		{ At = 0.37, Mark = "End", Hit = { Shape = "Line", From = "Start", Width = 6, Ahead = 1, Damage = 2.1, Weight = 3 }, Fx = "Slash" },
		{ At = 1.3, Hit = { Shape = "Line", From = "Start", To = "End", Width = 6, Ahead = 1, Damage = 1.0, Weight = 2 }, Fx = "Redraw" },
	},
}
Moves.CopyPasteScythe = { -- Copy-Paste: two ink copies of you copy your sweeps for 5 s
	Time = 0.7, Style = "Doodle",
	Steps = { { At = 0.15, Fx = "Copy", Buff = { Special = "Clones", Time = 5 } } },
}
Moves.DeleteKey = { -- DELETE: the screen glitches, a giant DEL key falls on them - and they shatter
	Time = 1.2, Style = "Glitch",
	Steps = {
		{ At = 0, Pick = "T", Range = 30, Ahead = 8, Fx = "Glitch" },
		{ At = 0.72, Hit = { Shape = "Circle", At = "T", Radius = 8, Damage = 3.0, Weight = 3 }, Fx = "Delete", Shake = 2 },
	},
}

-- the move for a weapon id (nil: its ability is building blocks only, or the Whirlwind)
function Moves.of(id)
	return id and Moves[id] or nil
end

return Moves
