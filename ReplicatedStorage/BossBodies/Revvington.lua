--[[
	Revvington  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Revvington")

	How Speedy Revvington, King of the Speedway (floor 5's boss,
	Config.Bosses[5]) looks on your screen: a chunky 8-bit cartoon race car,
	shiny red, a lightning bolt down each side and a big "57" on his doors and
	roof. His FACE is his windscreen - two huge eyes that follow you about,
	blink, squint and roll - and his MOUTH is the grille on his front bumper:
	a cocky grin full of teeth. His wheels really turn (the front ones steer),
	his springs bounce, he leans out of turns, dips his nose when he brakes,
	squats when he revs, and leaves tyre smoke and skid marks all over the
	track.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Revvington.lua, where each move is explained):
	  * where he is: the SEGMENT he's driving (ReplicatedStorage/CarPath) - the
	    server's own sums, so he's drawn exactly where he really is, even at
	    100 studs a second (Body.glide)
	  * Poses[move]   his body during a move: revving, charging, braking,
	                  rearing up, puffing his cheeks, leaning, spinning...
	  * Starts[move]  the move's sounds, shouts ("HONK!!"), bursts, camera
	                  kicks and its warnings on the track, on the server's clock
	  * SlotSpawns    the spots the server fills in as a move goes: the crash
	                  marker, the burning puddles, the ring of fire, the dash
	  * the moments every boss has: parked on the start line (revving now and
	    then), the COUNTDOWN when you walk up (3... 2... 1... GO! - the lights
	    on the gantry really light up), honking goodbye when everyone leaves,
	    TURBO! at half health (blue nitro flames, his stripes glow), and
	    FINISH!: he sputters, a wheel rolls away, his bumper drops off... and
	    he bursts into checkered confetti. The screen shows your time.
	  * his RACE CLOCK under the boss bar, his engine's hum (a looping sound
	    whose pitch follows his speed), a hint over his roof when he's open
	    ("DIZZY! HIT HIM!"), and you can't walk through him (his real shape:
	    a box, not a ball)

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one uses its own
	pose fields as well as BossClient's: facing (the way his segment points),
	wheelie (0-1: up on his back wheels), pitch / roll (extra tilts, radians),
	hop (studs up), spin (extra turning, radians), slump (0-1: a front wheel
	gone), revs (0-1: his engine shaking him), smoke (0-1: tyre smoke),
	wheelSpin (his wheels spinning on the spot), lids (his eyelids' slope:
	+ angry, - worried), squint (his bottom lids up: grinning), look (a spot
	his eyes look at), dizzy, xeyes, face (his mouth: "grin", "smirk", "grit",
	"open", "o", "sad", "happy", "shut"), open (0-1: how wide), puff (0-1:
	cheeks puffed), pipes (0-1: his exhausts glowing), nitro (0-1: blue
	flames), lights (0-1: headlights on), hoodPop (0-1: his bonnet flipped
	up), stars (dizzy stars), steam, ghost (0-1: see-through).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CarPath = require(ReplicatedStorage:WaitForChild("CarPath"))

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, easeOut, easeOutBack, spring, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local kick, playSound, findSound, soundGroup, addTelegraph, shockRing, at, SLOT_NAMES, myRoot
local bigText, shout

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config (all from the game's 32)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local HOT_RED = RGB(255, 0, 68)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local ORANGE = RGB(247, 118, 34)
local CYAN = RGB(44, 232, 245)
local GREEN = RGB(99, 199, 77)
local PALE = RGB(192, 203, 220)
local GREY = RGB(139, 155, 180)
local PINK = RGB(246, 117, 122)
local LAMP_DARK = RGB(162, 38, 51) -- (the start lights while they're off: SpeedwayBuilder's colour)
local PIXEL_FONT = nil

-- His shape (studs, for an 18-long car - it all grows or shrinks with
-- Config's Car.Length). His own space: x = his right, y = up from the floor,
-- z = BACK (his nose is at -z, like every Roblox part's front).
local AXLE_Z = 5.5 -- the axles, in front of and behind his middle
local AXLE_X = 4.05 -- the wheels, out from his middle
local WHEEL_R = 1.45 -- his wheels' radius
local MOUTH_Y, MOUTH_Z = 2.05, -9.32 -- the middle of his mouth, on his front bumper

function Body.init(kit)
	serverNow, clamp, lerp, smooth = kit.serverNow, kit.clamp, kit.lerp, kit.smooth
	easeOut, easeOutBack, spring, flat = kit.easeOut, kit.easeOutBack, kit.spring, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	onFloor, removeRing, burst = kit.onFloor, kit.removeRing, kit.burst
	kick, playSound, findSound, soundGroup = kit.kick, kit.playSound, kit.findSound, kit.soundGroup
	addTelegraph, shockRing, at, SLOT_NAMES, myRoot = kit.addTelegraph, kit.shockRing, kit.at, kit.SLOT_NAMES, kit.myRoot
	bigText, shout = kit.bigText, kit.shout
	pcall(function()
		PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	-- WARM-UP: his sounds and music loaded in the background as soon as you
	-- join, so none of them stalls or plays silent the first time
	task.delay(2.5, function()
		pcall(function()
			local def = nil
			for _, d in pairs(require(ReplicatedStorage:WaitForChild("Config")).Bosses or {}) do
				if d.Short == "Revvington" then
					def = d
				end
			end
			local list = {}
			for _, name in pairs(def and def.Sounds or {}) do
				local sound = findSound(name)
				if sound then
					table.insert(list, sound)
				end
			end
			local music = def and def.Music and findSound(def.Music)
			if music then
				table.insert(list, music)
			end
			if #list > 0 then
				game:GetService("ContentProvider"):PreloadAsync(list)
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function slot(B, i)
	local v = B.model:GetAttribute(SLOT_NAMES[i])
	return typeof(v) == "Vector3" and v or nil
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

-- the way to his right, from the way he faces (flat)
local function rightOf(dir)
	return V3(-dir.Z, 0, dir.X)
end

-- `dir` turned round the up axis by `a` radians (the way CarPath's headings
-- turn: more is to his left)
local function turnY(dir, a)
	return CarPath.dirOf(CarPath.angleOf(dir) + a)
end

-- a pair { round 1, TURBO } for the round he's in
local function byRound(B, v)
	if type(v) == "table" then
		return v[B.model:GetAttribute("Phase") or 1] or v[1]
	end
	return v
end

-- a block stretched from a to b (world points), `w` wide and `d` deep;
-- `upHint` says which way its depth faces
local function stretch(p, a, b, w, d, upHint)
	local dir = b - a
	local len = dir.Magnitude
	local center = (a + b) / 2
	if len < 1e-3 then
		p.Size = V3(w, d, 0.05)
		p.CFrame = CFrame.new(center)
		return
	end
	p.Size = V3(w, d, len)
	local up = upHint or V3(0, 1, 0)
	if math.abs(dir.Unit:Dot(up.Unit)) > 0.98 then
		up = V3(1, 0, 0) -- (nearly along the hint: any other side will do)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- a flat strip on the floor from a to b (floor points), `width` wide
local function floorStrip(p, a, b, width, lift)
	local d = flat(b - a)
	local len = math.max(d.Magnitude, 0.1)
	local mid = (a + b) / 2 + V3(0, lift or 0.13, 0)
	p.Size = V3(width, 0.12, len)
	p.CFrame = CFrame.lookAt(mid, mid + unitOr(d, V3(0, 0, -1)))
end

local function smoothTo(B, key: string, want: any, rate: number, dt: number): any
	local old = B[key]
	if old == nil then
		B[key] = want
		return want
	end
	local k = 1 - math.exp(-dt * rate)
	local v
	if typeof(want) == "Vector3" then
		v = old:Lerp(want, k)
	else
		v = old + (want - old) * k
	end
	B[key] = v
	return v
end

-- a spring: `x` pulled toward `want` (stiffness `k`, damping `c`); `v` is how
-- fast it's moving
local function springStep(x, v, want, k, c, dt)
	v = v + (k * (want - x) - c * v) * dt
	return x + v * dt, v
end

-- one of his sounds, played only if you're in his arena (the lobby doesn't
-- need to hear him honking)
local function sfx(B, key, volume)
	if B.here then
		playSound(B.def, key, B.vpos, volume or 1)
	end
end

-- a word bubble over his roof
local function yell(B, text, seconds, color)
	if B.here then
		pcall(function()
			shout(B.body.roof, text, seconds or 1, color or YELLOW)
		end)
	end
end

-- a spot on him (his own space: x right, y up, z back), as he was last drawn
local function onCar(B, x, y, z)
	local u = B.def.Car.Length / 18
	local cf = B.bodyCF
	if not cf then
		return B.vpos + V3(0, y * u, 0)
	end
	return cf * V3(x * u, y * u, z * u)
end

-- how many seconds, as the race clock shows them ("1:07.4")
local function formatTime(sec)
	sec = math.floor(math.max(sec, 0) * 10) / 10
	local m = math.floor(sec / 60)
	return string.format("%d:%04.1f", m, sec - m * 60)
end

-- the moment of GO! (the server's RaceStart, unless that's from an older race)
local function raceStartOf(B)
	local rs = B.model:GetAttribute("RaceStart")
	local wake = B.wakeAt and (B.wakeAt + (B.def.WakeTime or 0)) or nil
	if type(rs) == "number" and (not wake or rs >= wake - 0.5) then
		return rs
	end
	return wake
end

-- the speedway on your screen (the model with this floor's number and the
-- track's shape; looked for again now and then - it may not have loaded yet)
local function speedwayOf(B)
	if B.speedway and B.speedway.Parent then
		return B.speedway
	end
	if os.clock() < (B.speedwayLook or -math.huge) + 2 then
		return nil
	end
	B.speedwayLook = os.clock()
	B.speedway = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == B.floor and child:GetAttribute("Spine") then
			B.speedway = child
		end
	end
	return B.speedway
end

-- THE START LIGHTS on the gantry (only on your screen): the first `n` lit in
-- `color` - the outside two first, then the next two in, then the middle
-- one - and the rest dark
local LAMP_ORDER = { 1, 5, 2, 4, 3 }
local function setLamps(B, n, color)
	local arena = speedwayOf(B)
	if not arena then
		return
	end
	local lit = {}
	for k = 1, math.min(n, 5) do
		lit[LAMP_ORDER[k]] = true
	end
	for i = 1, 5 do
		local lamp = arena:FindFirstChild("StartLight" .. i, true)
		if lamp and lamp:IsA("BasePart") then
			if lit[i] then
				lamp.Color = color
				lamp.Material = Enum.Material.Neon
			else
				lamp.Color = LAMP_DARK
				lamp.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

-- the lights go dark again at `when` (unless something else lit them since)
local function lampsOffLater(B, when)
	local token = (B.lampToken or 0) + 1
	B.lampToken = token
	addTelegraph(B, {
		update = function(now)
			if B.lampToken ~= token then
				return false
			end
			if now >= when then
				setLamps(B, 0)
				return false
			end
			return true
		end,
		cleanup = function() end,
	})
end

----------------------------------------------------------------------
-- Where he is: his segment (the server's own sums, from CarPath)
----------------------------------------------------------------------
-- News of a new segment reaches your screen a moment after it began (your
-- ping), so he'd jump a little each time. Instead the gap is kept and melts
-- away in about a tenth of a second: he's always smooth, and never more than
-- a blink from where he really is. (The drives whose start matters - a
-- charge, a dash - arrive before they start, so those are never late.) And
-- a flat-out drive that has just ended slides on the way it was going until
-- the next segment arrives (the server always brakes that way), instead of
-- stopping dead for a moment - unless it ends in the tyre wall.
local function follow(B, now)
	if B.followAt == now and B.drawPos then
		return B.drawPos, B.drawDir
	end
	local last = B.followAt or now
	B.followAt = now
	local seg = CarPath.read(B.model)
	if not seg then
		return nil, nil
	end
	local pos, dir, u = CarPath.eval(seg, now)
	if seg.kind == "Line" and u >= 1 and (seg.ease == "lin" or seg.ease == "in") and not B.crashAhead then
		local len = flat(seg.b - seg.a).Magnitude
		local v0 = len / math.max(seg.dur, 1e-3) * ((seg.ease == "in") and 2 or 1)
		local e = math.min(now - (seg.t0 + seg.dur), 0.3)
		if v0 > 30 and e > 0 then
			pos = pos + dir * v0 * 0.12 * (1 - math.exp(-e / 0.12))
		end
	end
	if seg.id ~= B.segId then
		local gap = B.drawPos and flat(B.drawPos - pos).Magnitude or math.huge
		if B.segId ~= nil and gap < 25 then
			B.offPos = flat(B.drawPos - pos)
			B.offAng = CarPath.turnBetween(CarPath.angleOf(dir), CarPath.angleOf(B.drawDir))
		else
			B.offPos, B.offAng = V3(), 0 -- (the first sight of him, or put back home: no melting)
		end
		B.segId, B.seg = seg.id, seg
		-- (the moves watch for their drives: see watchDrive)
		if seg.kind == "Line" and seg.ease == "lin" then
			B.lastLine = seg
		elseif seg.kind == "Arc" then
			B.lastArc = seg
		end
	end
	local k = math.exp(-math.max(now - last, 0) / 0.07)
	B.offPos = (B.offPos or V3()) * k
	B.offAng = (B.offAng or 0) * k
	B.drawPos = pos + B.offPos
	B.drawDir = CarPath.dirOf(CarPath.angleOf(dir) + B.offAng)
	B.segU = u
	return B.drawPos, B.drawDir
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
-- the number on his doors and roof
local function numberOn(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Number"
	gui.Face = face
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "57"
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextColor3 = INK
	label.Parent = gui
	gui.Parent = part
	return label
end

local function emitter(parent, name, color, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = typeof(color) == "ColorSequence" and color or ColorSequence.new(color)
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Rate = 0
	e.Parent = parent
	return e
end

function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {}, custom = {}, numbers = {} }
	local paint, deep = def.Color or RED, def.DeepColor or LAMP_DARK
	local ink = def.CoreColor or INK
	local stripe = def.StripeColor or GOLD
	body.stripe = stripe
	-- every part remembers its own colour (for the flashes)
	local function add(name, color, material)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, { part = p, color = p.Color, material = p.Material })
		return p
	end
	-- THE BODY: the tub, the dark sills, the bonnet, the boot lid, the cabin
	-- and roof, the bumpers, fenders over the wheels, wing mirrors
	body.tub = add("Tub", paint)
	body.sills = { add("Sill", deep), add("Sill", deep) }
	body.hood = add("Hood", paint)
	body.deck = add("Deck", paint)
	body.cabin = add("Cabin", paint)
	body.roof = add("Roof", paint)
	body.bumper = add("Bumper", deep)
	body.rearBumper = add("RearBumper", deep)
	body.fenders = {}
	for i = 1, 4 do
		body.fenders[i] = add("Fender", paint)
	end
	body.mirrors = { add("Mirror", paint), add("Mirror", paint) }
	-- HIS FACE: the windscreen, two big eyes, lids above and below, X eyes
	body.screen = add("Windscreen", ink)
	body.whites, body.irises, body.pupils, body.glints, body.lids, body.lowLids = {}, {}, {}, {}, {}, {}
	for i = 1, 2 do
		body.whites[i] = add("EyeWhite", WHITE)
		body.irises[i] = add("Iris", def.EyeColor or CYAN)
		body.pupils[i] = add("Pupil", ink)
		body.glints[i] = add("Glint", WHITE, Enum.Material.Neon)
		body.lids[i] = add("Lid", paint)
		body.lowLids[i] = add("LowLid", paint)
	end
	body.xs = {}
	for i = 1, 4 do
		body.xs[i] = add("EyeX", ink)
	end
	-- HIS MOUTH: the grille on his front bumper, teeth, tongue, the corners
	-- that turn up when he grins, cheeks that puff out for a honk
	body.mouth = add("Mouth", ink)
	body.teeth = add("Teeth", WHITE)
	body.tongue = add("Tongue", PINK)
	body.corners = { add("MouthCorner", ink), add("MouthCorner", ink) }
	body.cheeks = { add("Cheek", PINK), add("Cheek", PINK) }
	-- LIGHTS, EXHAUST PIPES (and their flames), THE SPOILER
	body.headlights = { add("Headlight", YELLOW), add("Headlight", YELLOW) }
	body.tailLights = { add("TailLight", HOT_RED, Enum.Material.Neon), add("TailLight", HOT_RED, Enum.Material.Neon) }
	body.pipes, body.pipeHoles, body.flames = {}, {}, {}
	for i = 1, 2 do
		body.pipes[i] = add("Pipe", PALE)
		body.pipeHoles[i] = add("PipeHole", ink)
		body.flames[i] = add("Flame", ORANGE, Enum.Material.Neon)
	end
	body.posts = { add("SpoilerPost", ink), add("SpoilerPost", ink) }
	body.wing = add("Spoiler", paint)
	body.wingEdge = add("SpoilerEdge", stripe)
	-- THE LIGHTNING BOLTS down his sides (and one on his bonnet), his number
	body.bolts = { {}, {} }
	for i = 1, 2 do
		for k = 1, 3 do
			body.bolts[i][k] = add("Bolt", stripe)
		end
	end
	body.hoodBolt = add("Bolt", stripe)
	body.roundels = { add("Roundel", WHITE), add("Roundel", WHITE) }
	body.roofRoundel = add("RoofRoundel", WHITE)
	table.insert(body.numbers, { label = numberOn(body.roundels[1], Enum.NormalId.Left), part = body.roundels[1] })
	table.insert(body.numbers, { label = numberOn(body.roundels[2], Enum.NormalId.Right), part = body.roundels[2] })
	table.insert(body.numbers, { label = numberOn(body.roofRoundel, Enum.NormalId.Top), part = body.roofRoundel })
	-- THE WHEELS: a chunky tyre (a square and a diamond: nearly round), a
	-- silver rim that turns, a gold hub cap
	body.wheels = {}
	for i = 1, 4 do
		body.wheels[i] = { tyre = add("Tyre", ink), tyreB = add("Tyre", ink), rim = add("Rim", PALE), hub = add("Hub", stripe) }
	end
	-- dizzy stars, speed lines
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon)
	end
	body.lines = {}
	for i = 1, 6 do
		body.lines[i] = add("SpeedLine", WHITE, Enum.Material.Neon)
	end
	-- his shadow on the track
	body.shadow = newPart("Shadow", nil, INK, Enum.Material.SmoothPlastic, 0, folder)
	-- TYRE SMOKE off every wheel, STEAM from under his bonnet, NITRO sparks
	-- out of his pipes
	for i, w in ipairs(body.wheels) do
		w.smoke = emitter(w.tyre, "TyreSmoke", PALE, {
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 5.5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.5),
			Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = V3(0, 4, 0),
			Drag = 2,
		})
		local _ = i
	end
	body.steam = emitter(body.hood, "Steam", WHITE, {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = V3(0, 6, 0),
	})
	body.nitro = {}
	for i = 1, 2 do
		body.nitro[i] = emitter(body.pipes[i], "Nitro", ColorSequence.new(CYAN, WHITE), {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.2, 0.4),
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(12, 12),
			EmissionDirection = Enum.NormalId.Back,
		})
	end
	-- the parts that choose their own colour every frame (see applyPose)
	for _, p in ipairs({ body.headlights[1], body.headlights[2], body.pipeHoles[1], body.pipeHoles[2], body.flames[1], body.flames[2], body.hoodBolt }) do
		body.custom[p] = true
	end
	for i = 1, 2 do
		for k = 1, 3 do
			body.custom[body.bolts[i][k]] = true
		end
	end
	-- which parts decide for themselves whether they show (see applyPose)
	body.selfShown = {}
	for _, name in ipairs({ "Teeth", "Tongue", "Cheek", "LowLid", "EyeX", "Iris", "Pupil", "Glint", "Flame", "DizzyStar", "SpeedLine" }) do
		body.selfShown[name] = true
	end
	-- each part pops at its own moment when he bursts into confetti
	body.popAt = {}
	for i, rec in ipairs(body.all) do
		body.popAt[rec.part] = ((i * 37) % 29) / 29
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- his mouth's shapes: w = width, h = height (studs), curve = how far its
-- corners turn up, asym = the right corner up more (a smirk), teeth / tongue
-- = how much of each shows; wOpen / hOpen = more when P.open is 1
local FACES = {
	grin = { w = 6.2, h = 1.05, curve = 0.3, teeth = 0.45 },
	smirk = { w = 5.0, h = 0.7, curve = 0.12, asym = 0.35, teeth = 0.55 },
	grit = { w = 6.4, h = 1.15, curve = -0.05, teeth = 1 },
	open = { w = 5.0, h = 0.9, curve = 0.1, teeth = 0.28, tongue = 0.45, wOpen = 0.8, hOpen = 1.3 },
	o = { w = 1.9, h = 1.5, curve = 0, teeth = 0 },
	sad = { w = 4.2, h = 0.55, curve = -0.35, teeth = 0 },
	happy = { w = 6.4, h = 1.45, curve = 0.45, teeth = 0.35, tongue = 0.4 },
	shut = { w = 3.8, h = 0.25, curve = 0, teeth = 0 },
}

-- the lightning bolt down each side: three bars, { y, z from; y, z to; thickness }
local BOLT = { { 2.25, -7.4, 3.05, -1.2, 0.62 }, { 3.05, -1.2, 2.15, 0.9, 0.62 }, { 2.15, 0.9, 3.1, 7.6, 0.9 } }

-- the front wheel that rolled away at the finish: where it is now, and how
-- far it has turned
local function rolledWheel(B, now, u)
	local w = B.wheelOff
	local e = math.max(now - w.t0, 0)
	local ee = math.min(e, 1.9)
	local d = 11 * ee - 2.8 * ee * ee -- (rolling out, slowing down)
	local fall = clamp((e - 1.9) / 0.45, 0, 1) -- (then it topples over)
	local wobble = math.sin(e * 9) * 0.25 * math.max(0, 1 - e / 1.9)
	local p = w.from + w.dir * d
	local y = w.floorY + lerp(WHEEL_R * u, 0.8 * u, fall)
	local at0 = V3(p.X, y, p.Z)
	return CFrame.lookAt(at0, at0 + w.dir) * CFrame.Angles(0, 0, wobble + fall * math.pi / 2), d / (WHEEL_R * u)
end

local function applyPose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local u = def.Car.Length / 18
	local now = serverNow()
	dt = clamp(dt, 1 / 240, 1 / 15)
	local fade = P.fade or 0
	local ghost = P.ghost or 0
	local phase2 = B.phase2Look

	-- HOW HE'S MOVING (from where he's drawn, frame to frame)
	local look = unitOr(flat(facing), V3(0, 0, -1))
	local ang = CarPath.angleOf(look)
	local moved = B.lastPos and flat(ground - B.lastPos) or V3()
	if moved.Magnitude > 25 then
		moved = V3() -- (put back home: not a drive)
	end
	local turned = B.lastAng and CarPath.turnBetween(B.lastAng, ang) or 0
	B.lastPos, B.lastAng = ground, ang
	local right = rightOf(look)
	local speed = smoothTo(B, "speedS", moved:Dot(look) / dt, 12, dt)
	local slide = smoothTo(B, "slideS", moved:Dot(right) / dt, 12, dt)
	local yaw = smoothTo(B, "yawS", turned / dt, 12, dt)
	local accel = smoothTo(B, "accelS", (speed - (B.prevSpeed or speed)) / dt, 8, dt)
	B.prevSpeed = speed
	B.speed = speed
	local revs = clamp(P.revs or 0.12, 0, 1)
	B.revsNow = revs

	-- HIS SPRINGS: his body pitches (nose up as he speeds up, down as he
	-- brakes), rolls (out of turns, and away from a slide) and bounces - all a
	-- bit too much: he's a cartoon
	local wantPitch = clamp(accel * 0.0022, -0.14, 0.1) + (P.pitch or 0)
	local wantRoll = clamp(-speed * yaw * 0.0011 - slide * 0.003, -0.14, 0.14) + (P.roll or 0)
	B.pitchA, B.pitchV = springStep(B.pitchA or 0, B.pitchV or 0, wantPitch, 150, 9, dt)
	B.rollA, B.rollV = springStep(B.rollA or 0, B.rollV or 0, wantRoll, 150, 9, dt)
	B.heave, B.heaveV = springStep(B.heave or 0, B.heaveV or 0, 0, 170, 7, dt)
	-- (and his engine shakes him: a buzz that's stronger the harder he revs)
	local buzz = (math.sin(now * 71) * 0.06 + math.sin(now * 43 + 1) * 0.035) * revs * u

	-- WHERE EVERYTHING GOES: `base` is him on the floor; `chassis` lifted
	-- (hops, bounces) and turned up round his back axle for a wheelie;
	-- `bodyCF` his sprung body on top, tipped by the springs
	local jitter = V3()
	if (P.shake or 0) > 0 then
		jitter = V3(math.sin(now * 53), 0, math.cos(now * 61)) * P.shake
	end
	local g = ground + jitter
	local lookD = (P.spin and P.spin ~= 0) and turnY(look, P.spin) or look
	local base = CFrame.lookAt(g, g + lookD)
	local chassis = base * CFrame.new(0, (P.hop or 0) + B.heave * u, 0)
	local wheelie = clamp(P.wheelie or 0, 0, 1.3) * 0.5
	if wheelie > 1e-3 then
		local pivot = CFrame.new(0, WHEEL_R * u, AXLE_Z * u)
		chassis = chassis * pivot * CFrame.Angles(wheelie, 0, 0) * pivot:Inverse()
	end
	-- (the finish: a front wheel gone, he slumps onto that corner)
	local slump = clamp(P.slump or 0, 0, 1)
	if slump > 0 then
		chassis = chassis * CFrame.new(0, -0.55 * slump * u, 0) * CFrame.Angles(-0.1 * slump, 0, 0.12 * slump)
	end
	local sx, sy, sz = P.sx or 1, P.sy or 1, P.sz or 1
	local bodyCF = chassis * CFrame.new(0, 2.2 * u + buzz, 0) * CFrame.Angles(B.pitchA, 0, B.rollA) * CFrame.new(0, -2.2 * u, 0)
	B.bodyCF = bodyCF

	-- (a part placed in his body's space - x right, y up from the floor, z
	-- back - and stretched with his squash and stretch)
	local function put(p, x, y, z, w, h, d, turn)
		p.Size = V3(math.max(w * u * sx, 0.05), math.max(h * u * sy, 0.05), math.max(d * u * sz, 0.05))
		local cf = bodyCF * CFrame.new(x * u * sx, y * u * sy, z * u * sz)
		p.CFrame = turn and cf * turn or cf
	end
	local function where(x, y, z)
		return bodyCF * V3(x * u * sx, y * u * sy, z * u * sz)
	end

	-- THE BODY
	put(body.tub, 0, 2.55, 0, 8.2, 2.3, 17.2)
	for i, sl in ipairs(body.sills) do
		put(sl, ((i == 1) and -1 or 1) * 4.12, 1.72, 0, 0.2, 0.6, 7.4)
	end
	-- (his bonnet, hinged at the back: it flips up in a crash)
	local pop = clamp(P.hoodPop or 0, 0, 1)
	local hinge = bodyCF * CFrame.new(0, 3.85 * u * sy, -2.75 * u * sz) * CFrame.Angles(0.75 * pop, 0, 0)
	body.hood.Size = V3(7.6 * u * sx, 0.45 * u * sy, 5.6 * u * sz)
	body.hood.CFrame = hinge * CFrame.new(0, 0, -2.8 * u * sz)
	stretch(body.hoodBolt, hinge * V3(-2.3 * u * sx, 0.25 * u * sy, -5.0 * u * sz), hinge * V3(1.8 * u * sx, 0.25 * u * sy, -0.8 * u * sz), 0.7 * u, 0.06, hinge.UpVector)
	put(body.deck, 0, 3.85, 6.3, 7.6, 0.45, 3.6)
	put(body.cabin, 0, 4.95, 1.2, 7.0, 2.5, 6.6)
	put(body.roof, 0, 6.38, 1.5, 6.6, 0.36, 5.4)
	put(body.roofRoundel, 0, 6.6, 1.5, 2.6, 0.08, 2.6)
	put(body.rearBumper, 0, 1.95, 8.85, 8.6, 1.1, 0.8)
	for i, f in ipairs(body.fenders) do
		put(f, ((i % 2 == 1) and -1 or 1) * 4.12, 3.25, ((i <= 2) and -1 or 1) * AXLE_Z, 1.9, 0.5, 3.8)
	end
	for i, m in ipairs(body.mirrors) do
		put(m, ((i == 1) and -1 or 1) * 3.85, 4.55, -1.5, 0.5, 0.45, 0.8)
	end
	-- (his front bumper: it drops off at the finish)
	local bumperCF = bodyCF * CFrame.new(0, 2.0 * u * sy, -8.85 * u * sz)
	local off = B.bumperOff
	if off then
		off.from = off.from or bumperCF
		local e = math.max(now - off.t0, 0)
		local drop = clamp(e / 0.35, 0, 1)
		local bounce = math.max(0, math.sin(clamp((e - 0.35) / 0.3, 0, 1) * math.pi)) * 0.6 * u
		local from = off.from
		local p = from.Position + from.LookVector * (0.8 * u * math.min(e, 0.6))
		local y = lerp(from.Position.Y, off.floorY + 0.45 * u, drop * drop) + bounce
		bumperCF = CFrame.new(V3(p.X, y, p.Z)) * (from - from.Position) * CFrame.Angles(-0.35 * drop, 0, 0.12 * drop)
	end
	body.bumper.Size = V3(8.6 * u * sx, 1.3 * u * sy, 0.9 * u * sz)
	body.bumper.CFrame = bumperCF

	-- HIS MOUTH: the grille on his bumper (grin, smirk, gritted teeth, wide
	-- open, a little "o"...), and cheeks at its ends that puff out for a HONK
	local F = FACES[P.face or "grin"] or FACES.grin
	local openK = clamp(P.open or 0, 0, 1)
	local puff = smoothTo(B, "puffS", clamp(P.puff or 0, 0, 1), 20, dt)
	local mw = smoothTo(B, "mouthW", (F.w + (F.wOpen or 0) * openK) * (1 - 0.5 * puff), 16, dt)
	local mh = smoothTo(B, "mouthH", (F.h + (F.hOpen or 0) * openK) * (1 - 0.8 * puff), 16, dt)
	local curve = smoothTo(B, "mouthC", F.curve, 16, dt)
	local asym = smoothTo(B, "mouthA", F.asym or 0, 16, dt)
	local teeth = smoothTo(B, "mouthT", F.teeth or 0, 16, dt)
	local tongue = smoothTo(B, "mouthTg", F.tongue or 0, 16, dt)
	local mz = off and -8.66 or MOUTH_Z -- (no bumper: his mouth is on his front)
	local mouthCF = bodyCF * CFrame.new(0, MOUTH_Y * u * sy, mz * u * sz)
	body.mouth.Size = V3(mw * u * sx, mh * u * sy, 0.12)
	body.mouth.CFrame = mouthCF
	local th = math.max(mh * teeth, 0.05)
	body.teeth.Size = V3(math.max(mw - 0.5, 0.2) * u * sx, th * u * sy, 0.1)
	body.teeth.CFrame = mouthCF * CFrame.new(0, (mh - th) / 2 * u * sy, -0.05)
	body.teeth.Transparency = (teeth > 0.06 and ghost < 0.5) and ghost or 1
	local tg = math.max(mh * tongue, 0.05)
	body.tongue.Size = V3(mw * 0.45 * u * sx, tg * u * sy, 0.1)
	body.tongue.CFrame = mouthCF * CFrame.new(0, -(mh - tg) / 2 * u * sy, -0.05)
	body.tongue.Transparency = (tongue > 0.06 and ghost < 0.5) and ghost or 1
	for i, c in ipairs(body.corners) do
		local s = (i == 1) and -1 or 1
		local lift = curve + ((s > 0) and asym or 0)
		c.Size = V3(0.85 * u * sx, 0.32 * u * sy, 0.12)
		c.CFrame = mouthCF * CFrame.new(s * (mw / 2 + 0.2) * u * sx, lift * 0.9 * u * sy, 0) * CFrame.Angles(0, 0, s * clamp(lift * 1.3, -0.7, 0.7))
	end
	for i, ch in ipairs(body.cheeks) do
		local s = (i == 1) and -1 or 1
		ch.Size = V3((0.2 + 2.0 * puff) * u, (0.2 + 1.7 * puff) * u, (0.2 + 1.0 * puff) * u)
		ch.CFrame = bodyCF * CFrame.new(s * 3.5 * u * sx, 2.15 * u * sy, (mz - 0.25) * u * sz)
		ch.Transparency = (puff > 0.05 and ghost < 0.5) and ghost or 1
	end

	-- HIS FACE: two big eyes on his windscreen (it leans back). They follow
	-- you, blink now and then, squint, go angry (the lids slope in), roll
	-- round when he's dizzy, and cross out at the finish.
	local screenCF = bodyCF * CFrame.new(0, 5.1 * u * sy, -2.5 * u * sz) * CFrame.Angles(0.22, 0, 0)
	body.screen.Size = V3(6.8 * u * sx, 2.5 * u * sy, 0.25)
	body.screen.CFrame = screenCF
	local open = clamp(P.eyes or 1, 0, 1.25)
	local xeyes = (P.xeyes or 0) > 0.5
	if ((now * 0.29 + 0.37) % 1) < 0.035 and open > 0.3 and not xeyes and not P.dizzy then
		open = 0.04 -- (a blink now and then)
	end
	local target = P.look
	if not target then
		local root = myRoot()
		target = (root and flat(root.Position - g).Magnitude < 160) and root.Position or (g + lookD * 40 + V3(0, 3, 0))
	end
	local rel = bodyCF:PointToObjectSpace(target)
	local ax = math.atan2(rel.X, -rel.Z)
	local ay = math.atan2(rel.Y - 5 * u, math.sqrt(rel.X * rel.X + rel.Z * rel.Z) + 1)
	local px = smoothTo(B, "pupilX", clamp(ax / 1.1, -1, 1), 14, dt)
	local py = smoothTo(B, "pupilY", clamp(ay / 0.7, -1, 1), 14, dt)
	local wide = 1 + 0.15 * math.max(open - 1, 0)
	local ew, eh = 2.9 * u * sx * wide, 2.0 * u * sy * wide
	local lids = P.lids or 0
	for i = 1, 2 do
		local s = (i == 1) and -1 or 1
		local eyeCF = screenCF * CFrame.new(s * 1.62 * u * sx, 0, -0.18)
		body.whites[i].Size = V3(ew, eh, 0.1)
		body.whites[i].CFrame = eyeCF
		-- the iris and pupil, looking about (round and round when he's dizzy)
		local dx, dy = px * 0.62 * u * sx, py * 0.25 * u * sy
		if P.dizzy then
			local a = now * 10 + s * 1.6
			dx, dy = math.cos(a * s) * 0.5 * u, math.sin(a * s) * 0.25 * u
		end
		body.irises[i].Size = V3(1.35 * u * sx, 1.5 * u * sy, 0.1)
		body.irises[i].CFrame = eyeCF * CFrame.new(dx, dy, -0.05)
		body.pupils[i].Size = V3(0.72 * u * sx, 0.9 * u * sy, 0.1)
		body.pupils[i].CFrame = eyeCF * CFrame.new(dx * 1.1, dy * 1.1, -0.1)
		body.glints[i].Size = V3(0.34 * u, 0.34 * u, 0.06)
		body.glints[i].CFrame = eyeCF * CFrame.new(dx * 1.1 - 0.2 * u, dy * 1.1 + 0.27 * u, -0.14)
		for _, p in ipairs({ body.irises[i], body.pupils[i], body.glints[i] }) do
			p.Transparency = (xeyes or ghost > 0.5) and 1 or ghost
		end
		-- the lids: the top one comes down (sloping in when he's angry), the
		-- bottom one comes up when he grins or squints
		local lidH = math.max(eh * (1 - clamp(open, 0, 1)), math.abs(lids) * eh * 0.55) + 0.14 * u
		lidH = math.min(lidH, eh + 0.1)
		body.lids[i].Size = V3(ew + 0.35 * u, lidH, 0.12)
		body.lids[i].CFrame = eyeCF * CFrame.new(0, eh / 2 - lidH / 2 + 0.06 * u, -0.2) * CFrame.Angles(0, 0, s * lids * 0.6)
		local low = clamp(P.squint or 0, 0, 1) * eh * 0.5
		body.lowLids[i].Size = V3(ew + 0.35 * u, math.max(low, 0.05), 0.12)
		body.lowLids[i].CFrame = eyeCF * CFrame.new(0, -eh / 2 + low / 2 - 0.04 * u, -0.2)
		body.lowLids[i].Transparency = (low > 0.05 and ghost < 0.5) and ghost or 1
		-- X eyes (the finish)
		for k = 1, 2 do
			local x = body.xs[(i - 1) * 2 + k]
			x.Size = V3(ew * 0.8, 0.4 * u, 0.1)
			x.CFrame = eyeCF * CFrame.new(0, 0, -0.12) * CFrame.Angles(0, 0, (k == 1) and 0.6 or -0.6)
			x.Transparency = (xeyes and ghost < 0.5) and ghost or 1
		end
	end

	-- HEADLIGHTS (they blaze as he locks on), TAIL LIGHTS, EXHAUST PIPES
	-- (glowing hot before a backfire) and their flames (blue with nitro)
	local lights = clamp(P.lights or 0, 0, 1)
	local flashing = B.lightsFlashAt ~= nil and (now - B.lightsFlashAt) < 0.45 and ((now - B.lightsFlashAt) % 0.15) < 0.08
	for i, hl in ipairs(body.headlights) do
		local big = flashing and 1.35 or 1
		put(hl, ((i == 1) and -1 or 1) * 3.15, 3.15, -8.66, 1.5 * big, 0.8 * big, 0.14)
		local on = flashing or lights > 0.5
		hl.Color = on and WHITE or YELLOW
		hl.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
	for i, tl in ipairs(body.tailLights) do
		put(tl, ((i == 1) and -1 or 1) * 3.15, 3.1, 8.66, 1.5, 0.7, 0.14)
	end
	local glow = clamp(P.pipes or 0, 0, 1)
	local nitro = clamp(math.max(P.nitro or 0, (phase2 and math.abs(speed) > 35) and 0.8 or 0), 0, 1)
	if fade > 0.2 or ghost > 0.5 then
		nitro = 0
	end
	for i = 1, 2 do
		local s = (i == 1) and -1 or 1
		put(body.pipes[i], s * 2.3, 1.55, 9.45, 0.85, 0.85, 1.3)
		local hole = body.pipeHoles[i]
		put(hole, s * 2.3, 1.55, 10.12, 0.5 + 0.2 * glow, 0.5 + 0.2 * glow, 0.06)
		hole.Color = (glow > 0.05) and ORANGE:Lerp(YELLOW, glow) or INK
		hole.Material = (glow > 0.05) and Enum.Material.Neon or Enum.Material.SmoothPlastic
		local fl = body.flames[i]
		local want = math.max(nitro, (glow > 0.7) and (glow - 0.7) * 2 or 0)
		if want > 0.05 then
			local len = (1.0 + 2.2 * want) * (0.75 + 0.25 * math.sin(now * 37 + i * 2))
			put(fl, s * 2.3, 1.55, 10.2 + len / 2, 0.55, 0.55, len)
			fl.Color = (nitro > 0.05 and nitro >= want - 0.01) and CYAN or ORANGE
			fl.Transparency = 0.15
		else
			fl.Transparency = 1
		end
		body.nitro[i].Rate = (nitro > 0.3) and 40 * nitro or 0
	end

	-- THE SPOILER (taller in TURBO)
	local wingY = phase2 and 6.1 or 5.35
	for i, post in ipairs(body.posts) do
		put(post, ((i == 1) and -1 or 1) * 2.8, (3.85 + wingY) / 2, 7.7, 0.45, wingY - 3.85, 0.7)
	end
	put(body.wing, 0, wingY + 0.2, 7.9, phase2 and 9.2 or 8.4, 0.45, 2.0)
	put(body.wingEdge, 0, wingY + 0.47, 8.75, phase2 and 9.3 or 8.5, 0.2, 0.35)

	-- THE LIGHTNING BOLTS down his sides (glowing in TURBO) and his number
	for i = 1, 2 do
		local s = (i == 1) and -1 or 1
		for k, bar in ipairs(BOLT) do
			local p = body.bolts[i][k]
			stretch(p, where(s * 4.16, bar[1], bar[2]), where(s * 4.16, bar[3], bar[4]), bar[5] * u * sy, 0.1, bodyCF.RightVector)
		end
		put(body.roundels[i], s * 4.26, 2.6, 0.9, 0.1, 1.9, 1.9)
	end

	-- THE WHEELS: turning as he drives (and spinning on the spot when he revs
	-- or skids round), the front ones steering (full lock when he skids round
	-- on the spot)
	local rollRate = speed / (WHEEL_R * u)
	local extra = (P.wheelSpin or 0) + math.abs(yaw) * 2
	B.spinF = (B.spinF or 0) + clamp(rollRate + extra * clamp(P.wheelie or 0, 0, 1), -20, 20) * dt
	B.spinR = (B.spinR or 0) + clamp(rollRate + extra, -20, 20) * dt
	local steerWant = clamp(yaw * 0.13, -0.55, 0.55)
	if math.abs(speed) < 5 and math.abs(yaw) > 1 then
		steerWant = ((yaw > 0) and 1 or -1) * 0.5
	end
	local steer = smoothTo(B, "steerS", steerWant, 10, dt)
	for i, w in ipairs(body.wheels) do
		local s = (i % 2 == 1) and -1 or 1
		local front = i <= 2
		local cf = chassis * CFrame.new(s * AXLE_X * u, WHEEL_R * u, (front and -AXLE_Z or AXLE_Z) * u)
		if front then
			cf = cf * CFrame.Angles(0, steer, 0)
		end
		local spinA = front and B.spinF or B.spinR
		if B.wheelOff and i == 1 then
			cf, spinA = rolledWheel(B, now, u) -- (rolling away on its own: the finish)
		end
		local ts = V3(1.55 * u, 2.9 * u, 2.9 * u)
		w.tyre.Size, w.tyre.CFrame = ts, cf
		w.tyreB.Size, w.tyreB.CFrame = ts, cf * CFrame.Angles(math.pi / 4, 0, 0)
		w.rim.Size = V3(1.65 * u, 1.5 * u, 1.5 * u)
		w.rim.CFrame = cf * CFrame.Angles(-spinA, 0, 0)
		w.hub.Size = V3(1.72 * u, 0.6 * u, 0.6 * u)
		w.hub.CFrame = cf * CFrame.Angles(-spinA + math.pi / 4, 0, 0)
		local c = cf.Position
		w.ground = V3(c.X, ground.Y, c.Z) -- (for the skid marks)
	end

	-- DIZZY STARS round his roof
	local stars = P.stars or 0
	for i, st in ipairs(body.stars) do
		if stars > 0.05 and ghost < 0.5 and fade < 0.3 then
			local a = now * 5 + i * (math.pi * 2 / 3)
			local p = where(0, 8.2, 1.2) + V3(math.cos(a) * 3 * u, 0.3 * math.sin(now * 7 + i), math.sin(a) * 3 * u)
			st.Size = V3(1.0, 1.0, 0.4) * u
			st.CFrame = CFrame.new(p) * CFrame.Angles(0, a, now * 6)
			st.Transparency = 0
		else
			st.Transparency = 1
		end
	end

	-- SPEED LINES streaming past him when he's flat out
	local fast = clamp((math.abs(speed) - 50) / 35, 0, 1)
	for j, ln in ipairs(body.lines) do
		if fast > 0.02 and ghost < 0.5 and fade < 0.3 then
			local s = (j % 2 == 0) and 1 or -1
			local k = (now * 2.6 + j * 0.37) % 1
			local len = (3 + 4 * fast) * (1 - 0.5 * k)
			ln.Size = V3(0.18, 0.18, len * u)
			ln.CFrame = base * CFrame.new(s * (4.9 + (j % 3) * 0.5) * u, (1.6 + (j % 3) * 1.7) * u, (11 + k * 9 + len / 2) * u)
			ln.Transparency = lerp(1, 0.25, fast * (1 - k))
		else
			ln.Transparency = 1
		end
	end

	-- HIS SHADOW on the track
	local sg = ground + V3(0, 0.06, 0)
	body.shadow.Size = V3(9.4 * u, 0.1, 18.6 * u)
	body.shadow.CFrame = CFrame.lookAt(sg, sg + lookD)
	body.shadow.Transparency = (fade > 0.5 or ghost > 0.5) and 1 or 0.3

	-- TYRE SMOKE (skidding round, braking hard, sliding, burning out) and
	-- STEAM (a crash, the finish)
	local skid = 0
	local seg = B.seg
	if seg and seg.kind == "Spin" and (B.segU or 1) < 1 then
		local rate = math.abs(seg.b.Y) / math.max(seg.dur, 0.05)
		if rate > 2.5 or seg.c.Magnitude > 1 then
			skid = 1
		end
	end
	if math.abs(slide) > 8 then
		skid = 1
	end
	if accel < -90 then
		skid = math.max(skid, 0.7)
	end
	local smokeK = clamp(math.max(P.smoke or 0, skid), 0, 1)
	if fade > 0.2 or ghost > 0.5 then
		smokeK = 0
	end
	B.skidding = skid > 0.5 and ghost < 0.5 and fade <= 0
	for i, w in ipairs(body.wheels) do
		w.smoke.Rate = smokeK * ((i >= 3) and 40 or 14)
	end
	body.steam.Rate = ((P.steam or 0) > 0.05 and fade < 0.3) and 30 * P.steam or 0

	-- COLOURS: a punch landing blinks him white; the parts that choose their
	-- own colours (lights, pipes, bolts) chose them above
	local hitFlash = B.flashAt and (os.clock() - B.flashAt) < 0.08
	for i = 1, 2 do
		for k = 1, 3 do
			local p = body.bolts[i][k]
			p.Color = body.stripe
			p.Material = phase2 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
	body.hoodBolt.Color = body.stripe
	body.hoodBolt.Material = phase2 and Enum.Material.Neon or Enum.Material.SmoothPlastic
	for _, rec in ipairs(body.all) do
		local p = rec.part
		if hitFlash then
			p.Color = WHITE
			p.Material = Enum.Material.SmoothPlastic
		elseif not body.custom[p] then
			p.Color = rec.color
			p.Material = rec.material
		end
	end

	-- SEE-THROUGH (vanishing in a puff when everyone leaves), and the FINISH:
	-- each piece pops at its own moment into checkered confetti
	for _, rec in ipairs(body.all) do
		local p = rec.part
		local popped = fade > 0 and fade >= body.popAt[p] * 0.9 + 0.05
		if popped then
			p.Transparency = 1
		elseif not body.selfShown[p.Name] then
			p.Transparency = ghost
		end
	end
	for _, n in ipairs(body.numbers) do
		n.label.TextTransparency = n.part.Transparency
	end
end
Body.pose = applyPose

----------------------------------------------------------------------
-- Warnings and effects on the track
----------------------------------------------------------------------
-- Calls `onStart(seg)` when this move's flat-out drive (a Line), or its lap
-- (an Arc: kind "Arc"), begins, and `onEnd(seg)` when it's over. (A drive is
-- known the moment its segment reaches your screen: see follow.)
local function watchDrive(B, onStart, onEnd, kind)
	local name, t0 = B.action, B.actionStart or 0
	local seen, started = nil, false
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name or B.actionStart ~= t0 then
				return false
			end
			local seg = (kind == "Arc") and B.lastArc or B.lastLine
			if seg and seg ~= seen and seg.t0 >= t0 - 0.05 then
				seen, started = seg, false
			end
			if seen then
				if not started and now >= seen.t0 then
					started = true
					if onStart then
						onStart(seen)
					end
				end
				if started and now >= seen.t0 + seen.dur then
					if onEnd then
						onEnd(seen)
					end
					return false
				end
			end
			return true
		end,
		cleanup = function() end,
	})
end

-- THE LANE: red on the track, as wide as he is. Until the server fixes it
-- (slots `sa` and `sb`) it follows his nose, pale, `guessLen` long; then it
-- locks with two quick white flashes, from where he starts to where he'll stop - his
-- whole body, tail to nose - and arrows march down it the way he'll come. As
-- he drives down it, it's gone behind him. It ends with his drive (`untilFn`).
local function lane(B, sa, sb, guessLen, untilFn)
	local car = B.def.Car
	local width = car.Width + 1
	local strip = newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1)
	local rims = { newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1), newPart("LaneWarning", nil, RED, Enum.Material.Neon, 1) }
	local chevrons = {}
	for k = 1, 3 do
		chevrons[k] = { newPart("LaneArrow", nil, WHITE, Enum.Material.Neon, 1), newPart("LaneArrow", nil, WHITE, Enum.Material.Neon, 1) }
	end
	local lockedAt = nil
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name or now > untilFn() then
				return false
			end
			local from, to = slot(B, sa), slot(B, sb)
			local c0, c1, dir
			if from and to then
				lockedAt = lockedAt or now
				dir = unitOr(flat(to - from), B.drawDir or V3(0, 0, -1))
				local f = onFloor(from)
				c0 = f - dir * car.Length / 2
				c1 = onFloor(to) + dir * car.Length / 2
				-- (the part he has already driven over is gone)
				local line = B.lastLine
				if line and now > line.t0 and B.drawPos then
					local done = flat(B.drawPos - from):Dot(dir) - car.Length / 2
					if done > -car.Length / 2 then
						c0 = f + dir * math.min(done, flat(c1 - f).Magnitude - 0.2)
					end
				end
			else
				dir = B.drawDir or V3(0, 0, -1)
				c0 = onFloor(B.drawPos or B.vpos) + dir * car.Length / 2
				c1 = c0 + dir * guessLen
			end
			local blink = lockedAt ~= nil and (now - lockedAt) < 0.12 and ((now - lockedAt) % 0.06) < 0.03
			local color = blink and WHITE or RED
			floorStrip(strip, c0, c1, width)
			strip.Transparency = lockedAt and 0.45 or 0.75
			strip.Color = color
			local side = rightOf(dir)
			for i, rim in ipairs(rims) do
				local s = (i == 1) and -1 or 1
				floorStrip(rim, c0 + side * s * width / 2, c1 + side * s * width / 2, 0.5, 0.15)
				rim.Transparency = lockedAt and 0.1 or 0.5
				rim.Color = color
			end
			local len = flat(c1 - c0).Magnitude
			for k, pair in ipairs(chevrons) do
				local f = ((now * 1.2) + k / #chevrons) % 1
				local tip = c0 + dir * (len * f)
				for j, bar in ipairs(pair) do
					if lockedAt and len > 4 then
						local s = (j == 1) and -1 or 1
						floorStrip(bar, tip - dir * 1.3 + side * s * 1.3, tip, 0.45, 0.17)
						bar.Transparency = 0.25
					else
						bar.Transparency = 1
					end
				end
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
			for _, rim in ipairs(rims) do
				rim:Destroy()
			end
			for _, pair in ipairs(chevrons) do
				pair[1]:Destroy()
				pair[2]:Destroy()
			end
		end,
	})
end

-- A WEDGE on the floor: everything within `reach` of the spot, `arcDeg` wide
-- round the way it points (180 = a half-circle), and `back` studs over the
-- line behind it (the server's own shapes). It fills in until `hitAt()` - a
-- band sweeping out from the spot - flashes white as it starts to hurt (solid
-- red while it does), and is gone
-- at `endAt()`. `getSpot()` returns the spot and the way it points (nil
-- until the server has said).
local function wedge(B, getSpot, reach, arcDeg, back, showAt, hitAt, endAt)
	local N = math.max(6, math.floor(arcDeg / 16))
	local rim, band = {}, {}
	for i = 1, N do
		rim[i] = newPart("WedgeWarning", nil, RED, Enum.Material.Neon, 1)
		band[i] = newPart("WedgeWarning", nil, RED, Enum.Material.Neon, 1)
	end
	local edges = { newPart("WedgeWarning", nil, RED, Enum.Material.Neon, 1), newPart("WedgeWarning", nil, RED, Enum.Material.Neon, 1) }
	local backStrip = newPart("WedgeWarning", nil, RED, Enum.Material.Neon, 1)
	local half = math.rad(arcDeg / 2)
	local name = B.action
	local function arc(parts, c, dir, r, thick, tr, color)
		local step = (half * 2) / N
		for i, p in ipairs(parts) do
			local out = turnY(dir, -half + (i - 0.5) * step)
			local pos = c + out * r + V3(0, 0.15, 0)
			p.Size = V3(2 * r * math.sin(step / 2) + 0.25, 0.12, thick)
			p.CFrame = CFrame.lookAt(pos, pos + out)
			p.Transparency = tr
			p.Color = color
		end
	end
	local function hide()
		for i = 1, N do
			rim[i].Transparency, band[i].Transparency = 1, 1
		end
		edges[1].Transparency, edges[2].Transparency, backStrip.Transparency = 1, 1, 1
	end
	addTelegraph(B, {
		update = function(now)
			local stop = endAt()
			if B.action ~= name or (stop and now > stop) then
				return false
			end
			local c, dir = getSpot()
			if not c or now < showAt then
				hide()
				return true
			end
			c = onFloor(c)
			local hitT = hitAt()
			local k = hitT and clamp((now - showAt) / math.max(hitT - showAt, 0.05), 0, 1) or 0.35
			local live = hitT ~= nil and now >= hitT
			local color = (live and now - hitT < 0.08) and WHITE or RED
			arc(rim, c, dir, reach, 0.5, live and 0.05 or 0.25, color)
			arc(band, c, dir, math.max(reach * smooth(k), 1.2), 1.1, live and 0.3 or lerp(0.7, 0.35, k), color)
			for i, e in ipairs(edges) do
				local s = (i == 1) and -1 or 1
				floorStrip(e, c, c + turnY(dir, s * half) * reach, 0.45, 0.15)
				e.Transparency = live and 0.05 or 0.3
				e.Color = color
			end
			if back > 0 then
				floorStrip(backStrip, c - dir * back, c, reach * 2, 0.12)
				backStrip.Transparency = live and 0.45 or 0.75
				backStrip.Color = color
			else
				backStrip.Transparency = 1
			end
			return true
		end,
		cleanup = function()
			for i = 1, N do
				rim[i]:Destroy()
				band[i]:Destroy()
			end
			edges[1]:Destroy()
			edges[2]:Destroy()
			backStrip:Destroy()
		end,
	})
end

-- A RED CIRCLE on the floor round a spot, filling in until `hitAt`
local function circleWarning(B, getSpot, radius, showAt, hitAt)
	local disc = newPart("CircleWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local rim = newRing(24, RED, Enum.Material.Neon, 1)
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name or now > hitAt + 0.1 then
				return false
			end
			local c = getSpot()
			if not c or now < showAt then
				disc.Transparency = 1
				return true
			end
			c = onFloor(c)
			local k = clamp((now - showAt) / math.max(hitAt - showAt, 0.05), 0, 1)
			local color = (now >= hitAt) and WHITE or RED
			placeDisc(disc, c + V3(0, 0.12, 0), math.max(radius * 2 * smooth(k), 0.2), 0.12)
			disc.Transparency = lerp(0.7, 0.35, k)
			disc.Color = color
			placeRing(rim, c, radius, 0.15, 0.5, 0.15)
			for _, p in ipairs(rim.parts) do
				p.Color = color
			end
			return true
		end,
		cleanup = function()
			disc:Destroy()
			removeRing(rim)
		end,
	})
end

-- A BURNING PUDDLE (a backfire's, the ring of fire's): flames on the track
-- from `litAt` that hurt to stand in until `untilT` (a pale ring shows where
-- from `warnFrom`; `bare` = no rim, for the ring of fire's many)
local function firePuddle(B, pos, radius, litAt, untilT, warnFrom, bare)
	pos = onFloor(pos)
	local disc = newPart("FirePuddle", Enum.PartType.Cylinder, ORANGE, Enum.Material.Neon, 1)
	local core = newPart("FirePuddle", Enum.PartType.Cylinder, YELLOW, Enum.Material.Neon, 1)
	local rim = (not bare) and newRing(14, RED, Enum.Material.Neon, 1) or nil
	local holder = newPart("FireFlames", nil, ORANGE, nil, 1)
	holder.Size = V3(radius * 1.3, 0.2, radius * 1.3)
	holder.CFrame = CFrame.new(pos + V3(0, 0.3, 0))
	local flames = emitter(holder, "Flames", ColorSequence.new(YELLOW, ORANGE), {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(15, 15),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	addTelegraph(B, {
		update = function(now)
			if now > untilT then
				return false
			end
			if now < litAt then
				if rim and warnFrom and now >= warnFrom then
					placeRing(rim, pos, radius, 0.12, 0.35, 0.5)
				end
				return true
			end
			local dying = clamp(1 - (untilT - now) / 0.6, 0, 1)
			local flick = 0.9 + 0.1 * math.sin(now * 23 + pos.X)
			placeDisc(disc, pos + V3(0, 0.1, 0), radius * 2 * flick, 0.12)
			disc.Transparency = lerp(0.35, 1, dying)
			placeDisc(core, pos + V3(0, 0.14, 0), radius * 1.1 * flick, 0.12)
			core.Transparency = lerp(0.3, 1, dying)
			if rim then
				placeRing(rim, pos, radius, 0.14, 0.4, lerp(0.15, 1, dying))
			end
			flames.Rate = (dying < 0.5) and 14 or 0
			return true
		end,
		cleanup = function()
			disc:Destroy()
			core:Destroy()
			if rim then
				removeRing(rim)
			end
			holder:Destroy()
		end,
	})
end

-- THE SHOCK RING after a wheelie slam: a wall of dust rolling out across
-- the track, its radius at any moment exactly what the server tests (jump
-- it!). It starts at `t0` from slot 1.
local function slamWave(B, t0)
	local a = B.def.Attacks.WheelieSlam
	local start = a.Radius * 0.6
	local wall = newRing(48, PALE, Enum.Material.SmoothPlastic, 1)
	local crest = newRing(48, GOLD, Enum.Material.Neon, 1)
	local life = a.WaveReach / a.WaveSpeed
	local origin = nil
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			local age = now - t0
			if age > life then
				return false
			end
			if age < 0 then
				return B.action == name -- (the slam never came: gone)
			end
			origin = origin or slot(B, 1)
			if not origin then
				return false
			end
			local c = onFloor(origin)
			local r = start + a.WaveSpeed * age
			local fadeOut = clamp((age - (life - 0.3)) / 0.3, 0, 1)
			local h = a.WaveHeight * (1 - 0.4 * fadeOut) * (0.92 + 0.08 * math.sin(now * 30))
			placeRing(wall, c + V3(0, 0.05, 0), r, h, a.WaveThickness, lerp(0.1, 1, fadeOut), true)
			placeRing(crest, c + V3(0, h * 0.85, 0), r, h * 0.3, a.WaveThickness * 0.45, lerp(0.35, 1, fadeOut), true)
			return true
		end,
		cleanup = function()
			removeRing(wall)
			removeRing(crest)
		end,
	})
end

-- the honk's sound waves: arcs flying out across the cone
local function honkWaves(B, origin, dir, reach, arcDeg)
	local N = 7
	local sets = {}
	for s = 1, 3 do
		sets[s] = {}
		for i = 1, N do
			sets[s][i] = newPart("HonkWave", nil, WHITE, Enum.Material.Neon, 1)
		end
	end
	local half = math.rad(arcDeg / 2)
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > 0.8 then
				return false
			end
			local step = half * 2 / N
			for s, set in ipairs(sets) do
				local k = clamp((e - (s - 1) * 0.12) / 0.45, 0, 1)
				local r = 2 + (reach - 2) * k
				for i, p in ipairs(set) do
					local out = turnY(dir, -half + (i - 0.5) * step)
					local pos = origin + out * r + V3(0, 3, 0)
					p.Size = V3(2 * r * math.sin(step / 2) + 0.2, 1.4 * (1 - k) + 0.3, 0.4)
					p.CFrame = CFrame.lookAt(pos, pos + out)
					p.Transparency = (k <= 0 or k >= 1) and 1 or lerp(0.1, 0.9, k)
				end
			end
			return true
		end,
		cleanup = function()
			for _, set in ipairs(sets) do
				for _, p in ipairs(set) do
					p:Destroy()
				end
			end
		end,
	})
end

-- tyres flying off the wall he crashed into (bouncing, then gone)
local function flyingTyres(B, at0, dir)
	local list = {}
	local side = rightOf(dir)
	for k = 1, 5 do
		local p = newPart("LooseTyre", nil, INK, Enum.Material.SmoothPlastic, 0)
		p.Size = V3(1.1, 2.4, 2.4)
		local a = (k - 3) * 0.45
		list[k] = { p = p, pos = at0 + V3(0, 2 + k * 0.4, 0), vel = -dir * 9 + side * math.sin(a) * 18 + V3(0, 22 + (k % 3) * 6, 0), spin = (k % 2 == 0) and 7 or -9 }
	end
	local t0 = serverNow()
	local last = t0
	local floorY = B.vpos.Y
	addTelegraph(B, {
		update = function(now)
			local e = now - t0
			if e > 2.6 then
				return false
			end
			local step = clamp(now - last, 0, 0.05)
			last = now
			for _, tr in ipairs(list) do
				tr.vel = tr.vel + V3(0, -70, 0) * step
				tr.pos = tr.pos + tr.vel * step
				if tr.pos.Y < floorY + 1.2 then
					tr.pos = V3(tr.pos.X, floorY + 1.2, tr.pos.Z)
					tr.vel = V3(tr.vel.X * 0.6, math.abs(tr.vel.Y) * 0.45, tr.vel.Z * 0.6)
				end
				tr.p.CFrame = CFrame.new(tr.pos) * CFrame.Angles(e * tr.spin, e * 2, 0)
				tr.p.Transparency = clamp((e - 2.1) / 0.5, 0, 1)
			end
			return true
		end,
		cleanup = function()
			for _, tr in ipairs(list) do
				tr.p:Destroy()
			end
		end,
	})
end

-- a yellow ring pulsing where his lane meets the tyre wall: HE'LL CRASH HERE
local function crashMarker(B, spot, t0)
	local ring = newRing(16, YELLOW, Enum.Material.Neon, 1)
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name then
				return false
			end
			local line = B.lastLine
			if line and line.t0 >= t0 and now > line.t0 + line.dur + 0.3 then
				return false
			end
			local from = slot(B, 1)
			local dir = from and unitOr(flat(spot - from), V3(1, 0, 0)) or V3(1, 0, 0)
			local c = onFloor(spot) + dir * (B.def.Car.Length / 2)
			local k = (now * 3) % 1
			placeRing(ring, c, 2 + 2.5 * k, 0.15, 0.5, lerp(0.1, 1, k))
			return true
		end,
		cleanup = function()
			removeRing(ring)
		end,
	})
end

-- the ring of fire's circle: where the flames will go
local function ringWarning(B, center, radius, t0)
	center = onFloor(center)
	local ring = newRing(36, ORANGE, Enum.Material.Neon, 1)
	local name = B.action
	addTelegraph(B, {
		update = function(now)
			if B.action ~= name then
				return false
			end
			local arc = B.lastArc
			if arc and arc.t0 >= t0 and now > arc.t0 + arc.dur + 0.2 then
				return false
			end
			local pulse = 0.5 + 0.5 * math.sin(now * 12)
			placeRing(ring, center, radius, 0.14, 0.6, lerp(0.55, 0.2, pulse))
			return true
		end,
		cleanup = function()
			removeRing(ring)
		end,
	})
end

-- smoke (or flame) out of his pipes
local function pipePuff(B, color, count, speed, size)
	for _, s in ipairs({ -1, 1 }) do
		burst(onCar(B, s * 2.3, 1.55, 10.4), color, count or 8, speed or 8, size or 1.2, 0.7)
	end
end

-- the crowd goes wild: a cheer, and confetti over the grandstand
local function cheer(B, loud)
	sfx(B, "Cheer", loud or 0.8)
	local arena = speedwayOf(B)
	local c = arena and arena:GetAttribute("Center")
	if typeof(c) ~= "Vector3" or not B.here then
		return
	end
	local edge = arena:GetAttribute("Edge") or 62
	for k, x in ipairs({ -66, -22, 22, 66 }) do
		local p = V3(c.X + x, c.Y + 16, c.Z + edge + 16)
		burst(p, (k % 2 == 0) and YELLOW or WHITE, 14, 14, 0.6, 1.4, true)
		burst(p, (k % 2 == 0) and RED or CYAN, 10, 12, 0.6, 1.4, true)
	end
end

-- checkered confetti (the finish)
local function confetti(pos, n)
	burst(pos, WHITE, n, 18, 0.7, 1.6, true)
	burst(pos, INK, n, 18, 0.7, 1.6, true)
end

-- CRASH! into the tyre wall at the end of a charge
local function crashFx(B, line, stun)
	local dir = unitOr(flat(line.b - line.a), B.drawDir or V3(1, 0, 0))
	B.crashed = true
	B.dizzyUntil = line.t0 + line.dur + stun
	local nose = line.b + dir * B.def.Car.Length / 2
	sfx(B, "Crash", 1)
	yell(B, "CRASH!", 1.1, YELLOW)
	kick(nose, 60, 1.3, -5)
	burst(nose + V3(0, 3, 0), YELLOW, 30, 30, 1.2, 0.5)
	burst(nose + V3(0, 3, 0), ORANGE, 16, 20, 1.6, 0.5)
	burst(nose + V3(0, 2, 0), PALE, 20, 10, 3, 1.2, true)
	flyingTyres(B, nose, dir)
	B.heaveV = (B.heaveV or 0) + 6
end

----------------------------------------------------------------------
-- The shape of each move over time
----------------------------------------------------------------------
-- (his default: eyes on you, a cocky little smirk, engine ticking over)
function Poses.Idle(B, t, P)
	P.face, P.revs = "smirk", 0.15
end

-- CRUISE: driving round you like a shark - grinning
function Poses.Cruise(B, t, P)
	P.face, P.revs, P.lids = "grin", 0.3, 0.1
end

-- in the tyre wall: squashed, bonnet up, then reeling - stars, steam, eyes
-- rolling round - and cross about it afterwards
local function crashedPose(e, stun, P)
	local hit = spring(e, 5, 14)
	P.sz = 1 - 0.18 * hit
	P.sx = 1 + 0.08 * hit
	P.sy = 1 + 0.05 * hit
	P.hoodPop = 0.4 * clamp(e / 0.15, 0, 1) * ((e < stun) and 1 or clamp(1 - (e - stun) / 0.3, 0, 1))
	if e < stun then
		P.face, P.dizzy, P.stars, P.steam = "sad", true, 1, 1
		P.pitch, P.eyes = -0.05, 0.9
	else
		P.face, P.lids = "grit", 0.3
	end
end

-- CHARGE: revving (his back wheels spinning in a cloud of smoke, the lane
-- following you, his headlights blazing as it locks); roaring down it, mouth
-- wide; braking in a skid ("whoa!"); the slow turn round (smug). Into the
-- tyre wall: see crashedPose.
function Poses.Charge(B, t, P)
	local a = B.def.Attacks.Charge
	local T = byRound(B, a.Tell)
	local now = (B.actionStart or 0) + t
	if t < T then
		local k = t / T
		P.revs = 0.55 + 0.45 * k
		P.smoke = 0.25 + 0.75 * k
		P.wheelSpin = 16
		P.pitch = 0.05 * k
		P.lids, P.face = 0.5, "grit"
		P.lights = (t >= T * a.Lock) and 1 or 0
		return
	end
	local line = B.lastLine
	if line and now < line.t0 + line.dur then
		P.face, P.open, P.lids, P.eyes = "open", 0.8, 0.2, 1.15
		P.lights, P.revs = 1, 0.35
		return
	end
	local e = now - (line and (line.t0 + line.dur) or ((B.actionStart or 0) + T))
	if B.crashed then
		crashedPose(e, a.CrashStun, P)
		return
	end
	if e < a.Brake then
		P.face, P.eyes, P.lids, P.smoke = "o", 1.15, -0.2, 1
		return
	end
	P.face, P.lids = "smirk", 0.1
end

-- TAIL WHIP: a cheeky squint while he lines up; driving by, eyes on you; the
-- whip: laughing, tongue out, a big skid
function Poses.TailWhip(B, t, P)
	local a = B.def.Attacks.TailWhip
	local now = (B.actionStart or 0) + t
	local aim = slot(B, 3)
	if t < a.Tell then
		P.revs, P.face, P.lids, P.squint = 0.7, "smirk", 0.3, 0.3
		P.look = aim and aim + V3(0, 3, 0)
		return
	end
	local line = B.lastLine
	if line and now < line.t0 + line.dur then
		P.face, P.lids = "grin", 0.2
		P.look = aim and aim + V3(0, 3, 0)
		return
	end
	local e = now - (line and (line.t0 + line.dur) or ((B.actionStart or 0) + a.Tell))
	if e < a.Whip + 0.25 then
		P.face, P.open, P.squint, P.smoke = "happy", 0.3, 0.5, 1
		return
	end
	P.face = "smirk"
end

-- WHEELIE SLAM: up on his back wheels (front wheels spinning in the air,
-- roaring), then SLAM - squashed flat, bouncing on his springs
function Poses.WheelieSlam(B, t, P)
	local a = B.def.Attacks.WheelieSlam
	local T = a.Tell
	if t < T then
		local k = clamp(t / (T * 0.55), 0, 1)
		P.wheelie = easeOutBack(k) * (1 + 0.04 * math.sin(t * 20))
		P.face, P.open, P.lids, P.eyes = "open", 0.6, 0.35, 1.15
		P.revs, P.smoke, P.wheelSpin, P.lights = 0.9, 0.6, 20, 1
		return
	end
	local e = t - T
	P.wheelie = math.max(0, 1 - e / 0.07)
	local w = spring(e, 4.5, 15)
	P.sy, P.sx, P.sz = 1 - 0.28 * w, 1 + 0.14 * w, 1 + 0.1 * w
	P.face = (e < 0.5) and "grit" or "smirk"
	P.lids = (e < 0.5) and 0.4 or 0.1
	P.eyes = (e < 0.25) and 0.4 or 1
end

-- HONK: cheeks puffing up, eyes squeezed shut... then HONK!! - mouth wide
-- open, thrown back on his springs
function Poses.Honk(B, t, P)
	local a = B.def.Attacks.Honk
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.puff, P.face, P.eyes = k, "shut", 1 - 0.8 * k
		P.sy, P.sx = 1 + 0.06 * k, 1 + 0.07 * k
		P.shake = 0.08 * k
		return
	end
	local e = t - a.Tell
	local w = spring(e, 4, 12)
	P.face, P.open = (e < 0.55) and "open" or "grin", 1
	P.eyes = (e < 0.55) and 1.2 or 1
	P.pitch = 0.1 * math.max(w, 0)
	P.sz = 1 + 0.1 * w
end

-- BACKFIRE: his pipes glowing hotter and hotter, his tail up, rumbling, a
-- sly look... BANG - jolted forward, laughing
function Poses.Backfire(B, t, P)
	local a = B.def.Attacks.Backfire
	if t < a.Tell then
		local k = t / a.Tell
		P.pipes, P.revs = k, 0.6 + 0.4 * k
		P.pitch = -0.07 * smooth(k)
		P.face, P.squint, P.lids = "smirk", 0.35, 0.2
		P.shake = 0.05 * k
		return
	end
	local e = t - a.Tell
	P.pitch = -0.08 * spring(e, 5, 13)
	P.face = (e < 0.6) and "happy" or "smirk"
	P.squint = (e < 0.6) and 0.6 or 0.2
end

-- SIDE BUMP: leaning away from you (his wheels on your side lifting),
-- gritting his teeth... then a hop sideways at you: BONK!
function Poses.SideBump(B, t, P)
	local a = B.def.Attacks.SideBump
	local c = slot(B, 1)
	local s = 1 -- (+1: you're on his right)
	if c then
		s = (flat(c - (B.drawPos or B.vpos)):Dot(rightOf(B.drawDir or V3(0, 0, -1))) >= 0) and 1 or -1
	end
	if t < a.Tell then
		P.roll = s * 0.2 * smooth(t / a.Tell)
		P.face, P.lids = "grit", 0.4
		local out = slot(B, 2)
		P.look = out and out + V3(0, 3, 0)
		return
	end
	local e = t - a.Tell
	P.hop = 1.4 * math.sin(math.pi * clamp(e / 0.25, 0, 1))
	P.roll = -s * 0.22 * spring(e, 6, 14)
	P.face = (e < 0.5) and "grit" or "grin"
end

-- DONUTS: spinning round and round in a cloud of smoke, whooping
function Poses.Donuts(B, t, P)
	P.smoke, P.wheelSpin, P.revs = 1, 20, 0.7
	P.face, P.squint = "happy", 0.6
	P.roll = 0.1 * math.sin(t * 5)
	P.hop = 0.15 * math.abs(math.sin(t * 9))
end

-- BURNOUT RING: fired up (blue nitro), grinning through his teeth; the lap
-- (flames behind him); the dash through the middle, mouth wide; braking
function Poses.BurnoutRing(B, t, P)
	local now = (B.actionStart or 0) + t
	local arc = B.lastArc
	local dash = B.lastLine
	P.nitro = 0.8
	if dash and now >= dash.t0 then
		if now < dash.t0 + dash.dur then
			P.face, P.open, P.eyes, P.lights = "open", 0.9, 1.15, 1
			return
		end
		P.nitro = 0
		if now - (dash.t0 + dash.dur) < B.def.Attacks.Charge.Brake then
			P.face, P.eyes, P.smoke = "o", 1.1, 1
		else
			P.face, P.lids = "smirk", 0.1
		end
		return
	end
	if arc and now >= arc.t0 and now < arc.t0 + arc.dur then
		P.face, P.open, P.lids, P.smoke = "open", 0.5, 0.3, 0.5
		return
	end
	P.face, P.lids, P.revs = "grit", 0.45, 0.8
end

-- TURBO!: knocked about by your hit ("oh!")... then a blast of nitro, a spin
-- in a cloud of smoke, and he's back - glowing, grinning through his teeth
function Poses.Break(B, t, P)
	local hit = B.def.BreakTime * 0.35
	if t < hit then
		local k = t / hit
		P.face, P.eyes, P.lids = "o", 1.2, -0.2
		P.shake = 0.12 * (1 - k)
		P.revs = 0.3 + 0.7 * k
		return
	end
	local e = t - hit
	P.spin = math.pi * 2 * easeOut(clamp(e / 0.8, 0, 1))
	P.smoke = (e < 1) and 1 or 0
	P.nitro, P.revs = 1, 0.8
	P.face = (e < 1.1) and "open" or "grit"
	P.open, P.lids = 0.9, 0.35
end

-- PARKED on the start line: engine ticking over, eyes half shut (bored:
-- nobody's brave enough), revving now and then to show off. Someone near:
-- his eyes open wide and he grins - a challenger?
function Poses.Dormant(B, t, P)
	local cycle = serverNow() % 4.6
	local rev = (cycle < 0.5) and math.sin(cycle / 0.5 * math.pi) or 0
	P.face, P.eyes = "smirk", 0.5
	P.revs = 0.12 + 0.8 * rev
	P.pitch = 0.03 * rev
	local root = myRoot()
	if root and flat(root.Position - B.vpos).Magnitude < (B.def.WakeRange or 45) + 25 then
		P.face, P.eyes = "grin", 0.9
	end
end

-- (the countdown's moments, from the start of Wake: "3", "2", "1", GO!)
local function countTimes(B)
	local go = (B.def.WakeTime or 4.2) - 0.3
	return go - 2.7, go - 1.8, go - 0.9, go
end

-- THE COUNTDOWN: his eyes pop open, he grins at you, revs on every beep,
-- and on "1" his back wheels spin up in a cloud of smoke. GO!: mouth wide.
function Poses.Wake(B, t, P)
	local t3, t2, t1, go = countTimes(B)
	if t < 0.35 then
		P.face, P.eyes = "o", 0.5 + 2 * t
		return
	end
	P.face, P.eyes, P.lids = "grin", 1.05, 0.15
	for _, beat in ipairs({ 0.55, t3, t2, t1 }) do
		local e = t - beat
		if e >= 0 and e < 0.35 then
			P.revs = 0.9
			P.pitch = 0.06 * math.sin(e / 0.35 * math.pi)
		end
	end
	if t >= t1 then
		P.smoke, P.wheelSpin, P.revs = 1, 20, 1
		P.face, P.lids = "grit", 0.45
	end
	if t >= go then
		P.face, P.open, P.lids, P.eyes, P.lights = "open", 1, 0.2, 1.15, 1
	end
end

-- EVERYONE'S GONE: "BEEP BEEP!" (a smug honk-honk) and he vanishes in a puff
-- of smoke (home again on the start line)
function Poses.Reset(B, t, P)
	P.face, P.squint = "happy", 0.5
	if (t > 0.15 and t < 0.35) or (t > 0.45 and t < 0.65) then
		P.face, P.open = "open", 1
	end
	P.ghost = clamp((t - 1.2) / 0.5, 0, 1)
end

-- FINISH!: knocked back, his engine coughing and dying, a front wheel pops
-- off and rolls away (he slumps onto that corner), his bumper drops off, X
-- eyes, tongue out... and he bursts into checkered confetti
function Poses.Death(B, t, P)
	P.revs = (t < 1.8) and 0.4 * (1 - t / 1.8) or 0
	if t < 0.6 then
		P.face, P.eyes = "o", 1.2
		P.shake = 0.15 * (1 - t / 0.6)
		return
	end
	local k = clamp((t - 0.6) / 1.2, 0, 1)
	P.face, P.eyes, P.lids = "sad", lerp(1, 0.55, k), -0.3
	P.sy = 1 - 0.06 * k
	P.slump = clamp((t - 1.5) / 0.25, 0, 1)
	P.steam = (t > 2.4) and 0.8 or 0
	P.hoodPop = (t > 2.4) and 0.35 * clamp((t - 2.4) / 0.2, 0, 1) or 0
	if t >= 2.7 then
		P.xeyes, P.face, P.open = 1, "open", 0.4
	end
	P.fade = clamp((t - 3.6) / 0.6, 0, 1)
end

----------------------------------------------------------------------
-- One-off moments in each move (sounds, shouts, bursts, warnings)
----------------------------------------------------------------------
function Starts.Idle(B, t0) end
function Starts.Cruise(B, t0) end

function Starts.Charge(B, t0)
	local a = B.def.Attacks.Charge
	local T = byRound(B, a.Tell)
	at(B, t0 + 0.02, function()
		sfx(B, "Rev", 1)
		pipePuff(B, GREY, 6, 6, 1)
	end)
	lane(B, 1, 2, 50, function()
		local line = B.lastLine
		return (line and line.t0 >= t0) and (line.t0 + line.dur) or (t0 + T + 3)
	end)
	at(B, t0 + T * a.Lock, function()
		B.lightsFlashAt = serverNow() -- (his headlights flash: locked on)
		sfx(B, "Skid", 0.35)
	end)
	at(B, t0 + T, function()
		sfx(B, "Charge", 1)
		burst(onCar(B, 0, 1, 9), PALE, 26, 10, 2.6, 1)
		kick(B.vpos, 40, 0.5, -2)
	end)
	-- the end of the lane: brakes screeching... or CRASH
	watchDrive(B, nil, function(line)
		if slot(B, 3) then
			crashFx(B, line, a.CrashStun)
		else
			sfx(B, "Skid", 1)
			burst(onCar(B, 0, 1, 0), PALE, 20, 8, 2.4, 1)
		end
	end)
end

-- slot 3: the lane ends in the tyre wall
function SlotSpawns.Charge(B, i, spot, t0)
	if i == 3 then
		B.crashAhead = true -- (no sliding on at the end of it: see follow)
		crashMarker(B, spot, t0)
	end
end

function Starts.TailWhip(B, t0)
	local a = B.def.Attacks.TailWhip
	local function whipAt()
		local line = B.lastLine
		return (line and line.t0 >= t0) and (line.t0 + line.dur) or nil
	end
	at(B, t0 + 0.02, function()
		sfx(B, "Rev", 0.8)
	end)
	-- the path he'll drive (slot 1 to slot 2)...
	lane(B, 1, 2, 30, function()
		return whipAt() or (t0 + a.Tell + 3)
	end)
	-- ...and the whip's half-circle at the end of it, on your side (slot 3 =
	-- where you were; its middle is a little past the end: he skids on)
	wedge(B, function()
		local W, aim, from = slot(B, 2), slot(B, 3), slot(B, 1)
		if not (W and aim) then
			return nil
		end
		local dir = unitOr(flat(W - (from or W)), B.drawDir or V3(0, 0, -1))
		return W + dir * 2.5, unitOr(flat(aim - W), rightOf(dir))
	end, a.Radius, 180, 2.5, t0, whipAt, function()
		local w = whipAt()
		return w and (w + a.Whip + 0.05) or (t0 + a.Tell + 4)
	end)
	at(B, t0 + a.Tell, function()
		sfx(B, "Charge", 0.5)
	end)
	watchDrive(B, nil, function()
		sfx(B, "Whip", 1)
		burst(onCar(B, 0, 1, 6), PALE, 30, 12, 2.6, 1)
		kick(B.vpos, 30, 0.5, -2)
	end)
end

function Starts.WheelieSlam(B, t0)
	local a = B.def.Attacks.WheelieSlam
	at(B, t0 + 0.02, function()
		sfx(B, "Rev", 1)
	end)
	circleWarning(B, function()
		return slot(B, 1)
	end, a.Radius, t0, t0 + a.Tell)
	slamWave(B, t0 + a.Tell)
	at(B, t0 + a.Tell, function()
		local c = slot(B, 1) or onCar(B, 0, 0, -a.Ahead)
		sfx(B, "Slam", 1)
		kick(c, 40, 1.1, -4)
		burst(c + V3(0, 1, 0), PALE, 30, 22, 2.4, 0.8)
		burst(onCar(B, 0, 1, -9), YELLOW, 16, 20, 0.8, 0.4) -- (sparks off his bumper)
		shockRing(B, c, 2, a.Radius, 0.3, GOLD)
		B.heaveV = (B.heaveV or 0) - 5
	end)
end

function Starts.Honk(B, t0)
	local a = B.def.Attacks.Honk
	local half = B.def.Car.Length / 2
	-- the cone in front of his nose (he doesn't turn while he honks)
	wedge(B, function()
		local dir = B.drawDir or V3(0, 0, -1)
		return (B.drawPos or B.vpos) + dir * half, dir
	end, a.Reach + 1, a.Arc, 0, t0, function()
		return t0 + a.Tell
	end, function()
		return t0 + a.Tell + 0.15
	end)
	at(B, t0 + a.Tell, function()
		local dir = B.drawDir or V3(0, 0, -1)
		sfx(B, "Honk", 1)
		yell(B, "HONK!!", 0.9, YELLOW)
		honkWaves(B, (B.drawPos or B.vpos) + dir * half, dir, a.Reach, a.Arc)
		kick(B.vpos, a.Reach, 0.9, -4)
	end)
end

function Starts.Backfire(B, t0)
	local a = B.def.Attacks.Backfire
	local half = B.def.Car.Length / 2
	at(B, t0 + 0.02, function()
		sfx(B, "Rev", 0.7)
	end)
	-- the cone behind his tail
	wedge(B, function()
		local back = -(B.drawDir or V3(0, 0, -1))
		return (B.drawPos or B.vpos) + back * half, back
	end, a.Reach + 1, a.Arc, 0, t0, function()
		return t0 + a.Tell
	end, function()
		return t0 + a.Tell + 0.15
	end)
	at(B, t0 + a.Tell, function()
		local back = -(B.drawDir or V3(0, 0, -1))
		local tail = (B.drawPos or B.vpos) + back * half
		sfx(B, "Backfire", 1)
		yell(B, "BANG!", 0.8, ORANGE)
		for k = 0, 3 do
			burst(tail + back * (3 + k * 4) + V3(0, 2, 0), (k % 2 == 0) and ORANGE or YELLOW, 14, 16, 2.2, 0.5)
		end
		burst(tail + V3(0, 3, 0), INK, 16, 10, 2.6, 1.0, true)
		kick(tail, 30, 0.9, -4)
	end)
end

-- slots 1..Puddles: the burning puddles his backfire leaves
function SlotSpawns.Backfire(B, i, spot, t0)
	local a = B.def.Attacks.Backfire
	firePuddle(B, spot, a.PuddleRadius, t0 + a.Tell, t0 + a.Tell + a.PuddleTime, t0)
end

function Starts.SideBump(B, t0)
	local a = B.def.Attacks.SideBump
	-- the half-circle on your side (slot 1 = its middle, slot 2 = out that way)
	wedge(B, function()
		local c, out = slot(B, 1), slot(B, 2)
		if not (c and out) then
			return nil
		end
		local side = unitOr(flat(out - c), rightOf(B.drawDir or V3(0, 0, -1)))
		return c + side * a.Hop * 0.5, side
	end, a.Radius, 180, 2.5, t0, function()
		return t0 + a.Tell
	end, function()
		return t0 + a.Tell + 0.2
	end)
	at(B, t0 + a.Tell, function()
		local c = slot(B, 1) or B.vpos
		sfx(B, "Bump", 1)
		yell(B, "BONK!", 0.7, YELLOW)
		burst(c + V3(0, 2, 0), YELLOW, 16, 18, 0.9, 0.4)
		kick(c, 25, 0.8, -3)
	end)
end

function Starts.Donuts(B, t0)
	local a = B.def.Attacks.Donuts
	at(B, t0 + 0.05, function()
		sfx(B, "Donut", 1)
		yell(B, "WOO-HOO!", 1.2, YELLOW)
		cheer(B, 0.8)
	end)
	at(B, t0 + a.Time * 0.6, function()
		cheer(B, 0.5)
	end)
end

function Starts.BurnoutRing(B, t0)
	at(B, t0 + 0.02, function()
		sfx(B, "Rev", 1)
		yell(B, "RING OF FIRE!", 1.2, ORANGE)
		pipePuff(B, CYAN, 12, 12, 1)
	end)
	-- the lap and the dash: when their segments arrive
	watchDrive(B, function()
		sfx(B, "Charge", 0.8)
	end, nil, "Arc")
	watchDrive(B, function()
		sfx(B, "Charge", 1)
		kick(B.vpos, 40, 0.5, -2)
	end, function()
		sfx(B, "Skid", 1)
		burst(onCar(B, 0, 1, 0), PALE, 20, 8, 2.4, 1)
	end)
end

-- slot 1: the ring's middle; slots 2..Flames+1: each flame as it's lit;
-- Flames+2 and Flames+3: the dash
function SlotSpawns.BurnoutRing(B, i, spot, t0)
	local a = B.def.Attacks.BurnoutRing
	if i == 1 then
		ringWarning(B, spot, a.Radius, t0)
	elseif i <= a.Flames + 1 then
		local k = i - 1
		local arc = B.lastArc
		local litAt = (arc and arc.t0 >= t0) and (arc.t0 + a.Lap * k / a.Flames) or serverNow()
		firePuddle(B, spot, a.FlameRadius, litAt, litAt + a.FlameTime, nil, true)
		if k % 4 == 1 then
			sfx(B, "Fire", 0.6)
		end
	elseif i == a.Flames + 3 then
		lane(B, a.Flames + 2, a.Flames + 3, 30, function()
			local line = B.lastLine
			return (line and line.t0 >= t0) and (line.t0 + line.dur) or (serverNow() + 1)
		end)
	end
end

function Starts.Wake(B, t0)
	local def = B.def
	local t3, t2, t1, go = countTimes(B)
	B.lampToken = (B.lampToken or 0) + 1
	setLamps(B, 0)
	-- his engine starts: a cough of black smoke, then a roar
	at(B, t0 + 0.3, function()
		sfx(B, "Rev", 0.9)
		pipePuff(B, INK, 8, 5, 1.4)
		B.heaveV = (B.heaveV or 0) + 3
	end)
	at(B, t0 + 0.7, function()
		yell(B, "READY TO LOSE?", 1.4, YELLOW)
	end)
	-- 3... 2... 1... (the start lights: the outside two, the next two, the middle)
	for i, when in ipairs({ t3, t2, t1 }) do
		at(B, t0 + when, function()
			if B.here then
				pcall(function()
					bigText(tostring(4 - i), { color = (i == 3) and YELLOW or WHITE, size = 110, hold = 0.65 })
				end)
			end
			sfx(B, "Beep", 1)
			setLamps(B, ({ 2, 4, 5 })[i], HOT_RED)
			pipePuff(B, GREY, 6, 7, 1.1)
			B.heaveV = (B.heaveV or 0) - 3
		end)
	end
	at(B, t0 + go - (def.WakeSoundLead or 0.2), function()
		sfx(B, "Wake", 1)
	end)
	-- GO!
	at(B, t0 + go, function()
		if B.here then
			pcall(function()
				bigText("GO!", { color = GREEN, size = 120, hold = 0.9 })
			end)
		end
		sfx(B, "Go", 1)
		setLamps(B, 5, GREEN)
		yell(B, "KA-VROOM!", 1.1, YELLOW)
		burst(onCar(B, 0, 1, 8), PALE, 40, 14, 3, 1.2)
		kick(B.vpos, 70, 0.8, -4)
		cheer(B, 0.7)
		lampsOffLater(B, serverNow() + 2.5)
	end)
end

function Starts.Dormant(B, t0)
	-- (back on the start line after vanishing: a puff of smoke)
	if B.prevAction == "Reset" then
		burst(B.vpos + V3(0, 2, 0), PALE, 30, 12, 3, 1)
	end
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.15, function()
		sfx(B, "Honk", 0.5)
		yell(B, "BEEP BEEP!", 1.0, YELLOW)
	end)
	at(B, t0 + 0.45, function()
		sfx(B, "Honk", 0.4)
	end)
	at(B, t0 + 1.2, function()
		burst(B.vpos + V3(0, 2, 0), PALE, 30, 12, 3, 1)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	local hit = t0 + def.BreakTime * 0.35
	at(B, t0 + 0.05, function()
		sfx(B, "Skid", 0.7)
		burst(B.vpos + V3(0, 2, 0), PALE, 16, 10, 2, 0.6)
	end)
	at(B, hit - 0.3, function()
		sfx(B, "Rev", 1)
	end)
	at(B, hit, function()
		B.phase2Look = true
		shockRing(B, B.vpos, 3, def.BreakReach, 0.55, CYAN)
		shockRing(B, B.vpos, 2, def.BreakReach * 0.6, 0.4, WHITE)
		pipePuff(B, CYAN, 30, 24, 1.6)
		burst(B.vpos + V3(0, 3, 0), CYAN, 30, 26, 1.6, 0.8, true)
		sfx(B, "Break", 1)
		kick(B.vpos, def.BreakReach, 1.3, -6)
		if B.here then
			pcall(function()
				bigText("TURBO!", { color = CYAN, sub = "HE'S EVEN FASTER NOW", subColor = YELLOW, size = 96, hold = 1.5 })
			end)
		end
		yell(B, "TURBO TIME!", 1.2, CYAN)
		cheer(B, 0.6)
	end)
	at(B, t0 + def.BreakTime - 0.3, function()
		sfx(B, "Charge", 0.6)
	end)
end

function Starts.Death(B, t0)
	local rs = raceStartOf(B)
	local time = rs and math.max(t0 - rs, 0) or nil
	B.finishTime = time
	at(B, t0 + 0.05, function()
		sfx(B, "Death", 1)
		if B.here then
			pcall(function()
				bigText("FINISH!", { color = YELLOW, sub = time and ("YOUR TIME " .. formatTime(time)) or nil, subColor = WHITE, size = 96, hold = 2.2 })
			end)
			sfx(B, "Finish", 1)
			confetti(B.vpos + V3(0, 8, 0), 20)
		end
		kick(B.vpos, 40, 0.8, -3)
	end)
	-- his engine coughing: black smoke and little bangs
	for _, when in ipairs({ 0.75, 1.15, 1.7, 2.2 }) do
		at(B, t0 + when, function()
			pipePuff(B, INK, 10, 5, 1.6)
			sfx(B, "Backfire", 0.25)
		end)
	end
	-- a front wheel pops off and rolls away (out to his left)
	at(B, t0 + 1.5, function()
		local w = B.body.wheels[1]
		local fwd = B.drawDir or V3(0, 0, -1)
		B.wheelOff = { t0 = serverNow(), from = w.tyre.Position, dir = unitOr(-rightOf(fwd) * 0.8 + fwd * 0.6, fwd), floorY = B.vpos.Y }
		sfx(B, "Bump", 0.8)
		burst(w.tyre.Position, YELLOW, 10, 14, 0.6, 0.4)
	end)
	-- his bumper drops off
	at(B, t0 + 2.1, function()
		B.bumperOff = { t0 = serverNow(), floorY = B.vpos.Y }
		sfx(B, "Crash", 0.4)
	end)
	at(B, t0 + 2.5, function()
		cheer(B, 1)
	end)
	-- ...and he bursts into checkered confetti
	at(B, t0 + 3.6, function()
		for k = 0, 3 do
			confetti(B.vpos + V3(0, 1.5 + k * 1.5, 0), 16)
		end
		burst(B.vpos + V3(0, 2, 0), RED, 20, 16, 1, 1.2, true)
		kick(B.vpos, 30, 0.6, -2)
	end)
end

----------------------------------------------------------------------
-- The race clock (under the boss bar), a hint over his roof, his engine
----------------------------------------------------------------------
local clock = nil
local function buildClock()
	local Players = game:GetService("Players")
	local gui = Instance.new("ScreenGui")
	gui.Name = "RevvingtonClock"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.Enabled = false
	gui:SetAttribute("RetroSkip", true) -- (it has its own pixel look)
	local label = Instance.new("TextLabel")
	label.Name = "Time"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 101)
	label.Size = UDim2.new(0, 300, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextScaled = true
	label.TextColor3 = YELLOW
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = INK
	label.Text = ""
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	clock = { gui = gui, label = label }
end

-- the time since GO! while you fight him (cyan in TURBO); your finishing
-- time, flashing, for a few seconds after the finish
local function stepClock(B, show)
	if show and not clock then
		pcall(buildClock)
	end
	if not clock then
		return
	end
	local rs = raceStartOf(B)
	if not show or not rs then
		clock.gui.Enabled = false
		return
	end
	local now = serverNow()
	local e
	if B.stateNow == "Dead" then
		if not B.finishTime or now > (B.actionStart or now) + 6 then
			clock.gui.Enabled = false
			return
		end
		e = B.finishTime
		clock.label.TextColor3 = (math.floor(os.clock() * 4) % 2 == 0) and YELLOW or WHITE
	else
		e = now - rs
		clock.label.TextColor3 = B.phase2Look and CYAN or YELLOW
	end
	clock.gui.Enabled = true
	clock.label.Text = "TIME " .. formatTime(e)
end

-- the hint over his roof while he's open
local function hintOf(B)
	if B.action == "Donuts" then
		return "SHOWING OFF! HIT HIM!"
	end
	if B.crashed and B.dizzyUntil and serverNow() < B.dizzyUntil then
		return "DIZZY! HIT HIM!"
	end
	return nil
end

local function stepHint(B, show)
	local want = show and hintOf(B) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(os.clock() * 6) % 2 == 0) and 0 or 0.25
		end
		return
	end
	B.hintText = want
	if B.hintGui then
		B.hintGui:Destroy()
		B.hintGui, B.hintLabel = nil, nil
	end
	if want then
		local bb = Instance.new("BillboardGui")
		bb.Name = "RevvingtonHint"
		bb.Size = UDim2.fromOffset(280, 30)
		bb.StudsOffsetWorldSpace = V3(0, 5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.body.roof
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.Arcade
		if PIXEL_FONT then
			label.FontFace = PIXEL_FONT
		end
		label.TextColor3 = YELLOW
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = INK
		label.Text = want
		label.Parent = bb
		bb.Parent = B.body.folder
		B.hintGui, B.hintLabel = bb, label
	end
end

-- HIS ENGINE: a looping hum (Config's Sounds.Engine - quiet until you add
-- it) while you're in his arena, higher the faster he goes and the harder
-- he revs, louder the nearer he is
local function stepEngine(B, dt, on)
	if not on then
		if B.engine then
			B.engine:Destroy()
			B.engine = nil
		end
		return
	end
	if not B.engine then
		local name = B.def.Sounds and B.def.Sounds.Engine
		local template = name and findSound(name)
		if not (template and template:IsA("Sound")) then
			return
		end
		local s = template:Clone()
		s.Name = "RevvingtonEngine"
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = soundGroup("Effects")
		s.Parent = game:GetService("SoundService")
		s:Play()
		B.engine = s
	end
	local speed = math.abs(B.speed or 0)
	local revs = B.revsNow or 0
	local root = myRoot()
	local d = root and flat(root.Position - B.vpos).Magnitude or 60
	local near = clamp(1 - (d - 25) / 140, 0.2, 1)
	local want = (0.25 + 0.35 * clamp(speed / 90, 0, 1) + 0.25 * revs) * near * 0.8
	B.engine.Volume = B.engine.Volume + (want - B.engine.Volume) * math.min(1, dt * 8)
	B.engine.PlaybackSpeed = 0.75 + 0.9 * clamp(speed / 100, 0, 1) + 0.35 * revs
end

----------------------------------------------------------------------
-- Skid marks
----------------------------------------------------------------------
-- dark strips his tyres leave on the track while he skids, fading away over
-- a few seconds (at most MAX_MARKS at once: the oldest are reused)
local MARK_LIFE, MAX_MARKS = 5, 90
local function addMark(B, a, b)
	local part = table.remove(B.spareMarks)
	if not part then
		if #B.marks >= MAX_MARKS then
			part = table.remove(B.marks, 1).part
		else
			part = newPart("SkidMark", nil, INK, Enum.Material.SmoothPlastic, 1, B.body.folder)
		end
	end
	local d = flat(b - a)
	local mid = (a + b) / 2 + V3(0, 0.04, 0)
	part.Size = V3(1.1, 0.05, d.Magnitude + 0.3)
	part.CFrame = CFrame.lookAt(mid, mid + d)
	part.Transparency = 0.3
	table.insert(B.marks, { part = part, t0 = serverNow() })
end

local function stepMarks(B)
	B.marks = B.marks or {}
	B.spareMarks = B.spareMarks or {}
	local now = serverNow()
	for _, w in ipairs(B.body.wheels) do
		local p = w.ground
		if B.skidding and p then
			if w.markFrom and (p - w.markFrom).Magnitude >= 0.9 then
				if (p - w.markFrom).Magnitude < 6 then
					addMark(B, w.markFrom, p)
				end
				w.markFrom = p
			elseif not w.markFrom then
				w.markFrom = p
			end
		else
			w.markFrom = nil
		end
	end
	for i = #B.marks, 1, -1 do
		local m = B.marks[i]
		local k = (now - m.t0) / MARK_LIFE
		if k >= 1 then
			m.part.Transparency = 1
			table.remove(B.marks, i)
			table.insert(B.spareMarks, m.part)
		else
			m.part.Transparency = lerp(0.3, 1, k * k)
		end
	end
end

-- a fresh track: every mark gone
local function clearMarks(B)
	for _, m in ipairs(B.marks or {}) do
		m.part.Transparency = 1
		B.spareMarks = B.spareMarks or {}
		table.insert(B.spareMarks, m.part)
	end
	B.marks = {}
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- what his moves are made of: red paint and tyre smoke
function Body.fx(def)
	return { color = def.Color or RED, deep = def.DeepColor or LAMP_DARK, rock = GREY, material = Enum.Material.SmoothPlastic, solid = true }
end

-- where he is between the server's updates: exactly on his segment
function Body.glide(B, now, ground)
	local _ = ground
	return (follow(B, now))
end

-- a pose, played: facing the way his segment points
function Body.runPose(B, shape, t, now, P)
	follow(B, now)
	-- (a car breathes less than a slime)
	P.sy, P.sx, P.sz = 1 + (P.sy - 1) * 0.5, 1 + (P.sx - 1) * 0.5, 1 + (P.sz - 1) * 0.5
	shape(B, t, P)
	if B.drawDir and not P.facing then
		P.facing = B.drawDir
	end
end

-- every frame, after he's posed: his skid marks
function Body.afterPose(B)
	stepMarks(B)
end

-- a new move began
function Body.onAction(B, name, t0, now)
	B.lastLine, B.lastArc = nil, nil
	B.crashed, B.crashAhead = false, false
	if name == "Wake" or name == "Dormant" or name == "Reset" then
		B.wheelOff, B.bumperOff, B.dizzyUntil, B.finishTime = nil, nil, nil, nil
	end
	if name == "Wake" then
		B.wakeAt = t0
	end
	local _ = now
end

-- joined while TURBO was already on
function Body.lateBreak(B)
	B.phase2Look = true
end

-- a fresh start: the start lights dark, and (back home) a clean track
function Body.calm(B, name)
	B.lampToken = (B.lampToken or 0) + 1
	setLamps(B, 0)
	if name == "Dormant" then
		clearMarks(B)
	end
end

-- every frame: the race clock, the hint over his roof, his engine, and a
-- puff from his pipes each time he revs on the start line
function Body.senses(B, dt, here, awake, state)
	B.here = here
	B.stateNow = state
	stepEngine(B, dt, here and (state == "Dormant" or awake))
	stepHint(B, here and awake)
	stepClock(B, here and (state == "Fighting" or state == "Transition" or state == "Dead"))
	if state == "Dormant" and here then
		local cycle = math.floor(serverNow() / 4.6)
		if B.revCycle and cycle ~= B.revCycle then
			pipePuff(B, GREY, 5, 5, 1)
		end
		B.revCycle = cycle
	end
end

-- you can't walk through him: nudged out to the edge of his body (a box, the
-- way he faces). Not while he's driving fast: then he's running you over!
function Body.pushOut(B, P, here, awake, state)
	if not here or not (awake or state == "Dormant") or (P.fade or 0) > 0.3 or (P.ghost or 0) > 0.3 then
		return
	end
	if math.abs(B.speed or 0) > 15 then
		return
	end
	local hrp = myRoot()
	if not hrp then
		return
	end
	local car = B.def.Car
	local look = B.drawDir or B.vfacing
	local right = rightOf(look)
	local rel = flat(hrp.Position - B.vpos)
	if hrp.Position.Y - (B.vpos.Y + 3) > car.Height then
		return -- (up on top of him)
	end
	local hx, hz = car.Width / 2 + 1.3, car.Length / 2 + 1.3
	local x, z = rel:Dot(right), rel:Dot(look)
	if math.abs(x) < hx and math.abs(z) < hz then
		local out
		if hx - math.abs(x) < hz - math.abs(z) then
			out = right * (((x >= 0) and 1 or -1) * hx) + look * z
		else
			out = look * (((z >= 0) and 1 or -1) * hz) + right * x
		end
		local target = B.vpos + out
		hrp.CFrame = CFrame.new(V3(target.X, hrp.Position.Y, target.Z)) * (hrp.CFrame - hrp.Position)
	end
end

return Body
