--[[
	_Template  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "_Template")

	NOT A REAL BOSS: the starting point for a new boss's BODY - what players
	see. (The server side is ServerScriptService/Bosses/_Template.lua; read
	its "HOW TO ADD A BOSS" first.) Copy this file next to itself and name the
	copy after the boss's short name in Config (e.g. BossBodies/Frostjaw.lua).
	It's a small working body: a chunky 8-bit block creature with glowing
	eyes, its STOMP (a red warning circle, then a shockwave), and simple
	versions of the moments every boss has - asleep, waking, resetting, the
	break at half health, and dying. The headless test
	Tools/HeadlessTests/test_boss_template.luau draws it to prove it works.

	HOW BOSSCLIENT USES A BODY FILE
	  * Body.init(kit): once, with the drawing kit - newPart (8-bit parts on
	    the game's palette), placeDisc, burst, shockRing, kick (camera),
	    playSound (by name from SoundService), addTelegraph (a warning in the
	    world), at (a moment on the server's clock) and more (see BossClient).
	  * Body.build(def) -> body: make its parts (return a table with `folder`,
	    the Model holding them all).
	  * Body.pose(B, P, ground, facing, t, dt): every frame, place the parts.
	    P is its pose this frame: breathing and crawling (BossClient), then the
	    current action's Poses[name] reshapes it. The fields: lift (studs up),
	    sx / sy / sz (squash and stretch), lean, sink (0-1 into the floor),
	    eyes (0-1 open), mouth, shake, flare, fade (0-1 gone).
	  * Poses[action](B, t, P): its shape t seconds into an action.
	    Starts[action](B, t0): when an action begins - schedule its sounds,
	    bursts and warnings with at(B, when, fn) and addTelegraph.
	    SlotSpawns[action](B, i, spot, t0): a warning for each position the
	    server fills in (setSlot). The action names are the server file's.
	    "Dormant" and "Death" are its poses while asleep and once dead;
	    "Wake", "Reset" and "Break" come from BossService.
	  * Body.fx(def): what its attacks are made of (colours for bursts).
	  * Optional (see BossBodies/Tuber.lua or BossBodies/Gridlock.lua, which use
	    most of them): onTrack, onAction, lateBreak, calm, breaks, signs,
	    runPose, glide, afterPose, senses, pushOut, everyFrame, and barLook
	    (its own health bars), music (its own songs), stormWant (its storm).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local clamp, smooth, spring, fxFolder, newPart, placeDisc, onFloor, burst
local kick, playSound, addTelegraph, shockRing, at

function Body.init(kit)
	clamp, smooth, spring, fxFolder, newPart = kit.clamp, kit.smooth, kit.spring, kit.fxFolder, kit.newPart
	placeDisc, onFloor, burst = kit.placeDisc, kit.onFloor, kit.burst
	kick, playSound, addTelegraph, shockRing, at = kit.kick, kit.playSound, kit.addTelegraph, kit.shockRing, kit.at
end

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }
	body.torso = newPart("Torso", nil, def.Color, Enum.Material.SmoothPlastic, 0, folder)
	body.head = newPart("Head", nil, def.DeepColor, Enum.Material.SmoothPlastic, 0, folder)
	body.eyes = {}
	for i = 1, 2 do
		body.eyes[i] = newPart("Eye", nil, def.EyeColor, Enum.Material.Neon, 0, folder)
	end
	folder.Parent = fxFolder
	return body
end

function Body.pose(B, P, ground, facing, t, dt)
	local body, D = B.body, B.def.Size
	-- down into the floor while it sleeps, up in the air when it jumps
	local base = ground + V3(0, P.lift - P.sink * D * 0.9, 0)
	local cf = CFrame.lookAt(base, base + facing) * CFrame.Angles(-P.lean, 0, 0)
	local w, h = D * P.sx, D * 0.8 * P.sy
	body.torso.Size = V3(w, h, D * P.sz)
	body.torso.CFrame = cf * CFrame.new(0, h / 2, 0)
	local hs = D * 0.45
	body.head.Size = V3(hs, hs, hs)
	body.head.CFrame = cf * CFrame.new(0, h + hs / 2, 0)
	for i, eye in ipairs(body.eyes) do
		eye.Size = V3(hs * 0.2, hs * 0.2 * math.max(P.eyes, 0.05), 0.3)
		eye.CFrame = cf * CFrame.new((i == 1 and -1 or 1) * hs * 0.24, h + hs * 0.62, -hs / 2 - 0.15)
	end
	local fade = P.fade or 0
	body.torso.Transparency = fade
	body.head.Transparency = fade
	for _, eye in ipairs(body.eyes) do
		eye.Transparency = (P.eyes > 0.5 and fade < 0.5) and 0 or 1
	end
end

-- what its attacks are made of (the colour of its bursts)
function Body.fx(def)
	return { color = def.Color, deep = def.DeepColor, rock = def.DeepColor, material = Enum.Material.SmoothPlastic, solid = true }
end

----------------------------------------------------------------------
-- The moments every boss has
----------------------------------------------------------------------
function Poses.Dormant(B, t, P)
	P.sink, P.eyes = 1, 0
end

function Poses.Wake(B, t, P)
	local u = clamp(t / B.def.WakeTime, 0, 1)
	P.sink = 1 - smooth(u)
	P.eyes = clamp((u - 0.6) / 0.2, 0, 1)
end

function Poses.Reset(B, t, P)
	local u = clamp(t / 2, 0, 1)
	P.sink = smooth(u)
	P.eyes = 1 - u
end

function Poses.Break(B, t, P)
	P.shake = 0.4
	P.sy = 1 + 0.2 * spring(t, 3, 10)
end

function Poses.Death(B, t, P)
	local k = clamp(t / 2.4, 0, 1)
	P.sy, P.sx = 1 - 0.8 * k, 1 + 0.4 * k
	P.sz = P.sx
	P.eyes = 0
	P.fade = clamp((t - 1.5) / 1.5, 0, 1)
end

function Starts.Wake(B, t0)
	at(B, t0 + B.def.WakeTime * 0.6, function()
		playSound(B.def, "Wake", B.vpos, 1)
		kick(B.vpos, 30, 0.9, -3)
		burst(B.vpos + V3(0, 2, 0), B.fx.color, 24, 22, 2.2, 0.8, true)
	end)
end

function Starts.Break(B, t0)
	at(B, t0 + B.def.BreakTime * 0.35, function()
		B.phase2Look = true
		shockRing(B, B.vpos, B.def.Size / 2, B.def.BreakReach, 0.55)
		playSound(B.def, "Break", B.vpos, 1)
		kick(B.vpos, B.def.BreakReach, 1.2, -5)
	end)
end

function Starts.Death(B, t0)
	at(B, t0 + 0.4, function()
		playSound(B.def, "Death", B.vpos, 1)
		burst(B.vpos + V3(0, 3, 0), B.def.EyeColor, 30, 20, 2, 1, true)
	end)
end

----------------------------------------------------------------------
-- Its attacks
----------------------------------------------------------------------
-- STOMP: it rises up while a red circle fills in round it, then slams down
-- (the server hits everyone inside at exactly t0 + Tell)
function Poses.Stomp(B, t, P)
	local T = B.def.Attacks.Stomp.Tell
	if t < T then
		local k = t / T
		P.lift = 6 * smooth(k)
		P.sy, P.sx = 1 + 0.15 * k, 1 - 0.08 * k
	else
		local w = spring(t - T, 5, 14)
		P.sy, P.sx = 1 - 0.25 * w, 1 + 0.2 * w
	end
	P.sz = P.sx
end

function Starts.Stomp(B, t0)
	local a = B.def.Attacks.Stomp
	-- the warning: a red disc on the floor, filling in until it lands
	local disc = newPart("StompWarning", Enum.PartType.Cylinder, RGB(228, 59, 68), Enum.Material.Neon, 0.55)
	addTelegraph(B, {
		update = function(now)
			local k = clamp((now - t0) / a.Tell, 0, 1)
			placeDisc(disc, onFloor(B.vpos), a.Radius * 2 * k, 0.2)
			return now < t0 + a.Tell
		end,
		cleanup = function()
			disc:Destroy()
		end,
	})
	at(B, t0 + a.Tell, function()
		shockRing(B, B.vpos, 2, a.Radius, 0.35)
		burst(B.vpos + V3(0, 1, 0), B.fx.color, 20, 24, 1.8, 0.6)
		playSound(B.def, "Slam", B.vpos, 1)
		kick(B.vpos, a.Radius, 0.9, -3)
	end)
end

return Body
