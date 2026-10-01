--[[
	Gridlock  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Gridlock")

	How Gridlock, the Final Beat (floor 6's boss, Config.Bosses[6]) looks on
	your screen: a giant neon CUBE - black, glowing red edges, two slanted
	yellow eyes, a jagged grin and little horns - who flips through the air
	on every hop, bounces on every beat, and changes FORM through portals:
	a SHIP (a black rocket with a flame, him riding in its cockpit), a UFO (a
	saucer with a glass dome and lights that blink on the beat), a WAVE (a
	neon dart). The whole level moves with the music: the lines between the
	tiles pulse on the beat, the saws spin, the neon frames turn, the jump
	pads bounce - and in round 2 the world turns upside down.

	Everything he does is drawn from what the server publishes (see
	ServerScriptService/Bosses/Gridlock.lua, where each move is explained):
	  * where he is: his MOVE (a hop, a flight, a fall, a zig-zag - see
	    ReplicatedStorage/BeatGrid), with the server's own sums, so he's drawn
	    exactly where he really is (Body.glide)
	  * THE LEVEL: every tile pattern the server lights (Tiles1..12, TilesK) -
	    red warnings that brighten on each beat, then spikes (or a wall of
	    light, or the whole floor for THE DROP, the jump pads glowing green)
	  * Poses / Starts / SlotSpawns: his face and the moments of each move:
	    the swoop's lane, the UFO's circle and tractor beam, falling bombs and
	    orbs, portals, gravity portals
	  * the moments every boss has: asleep in the middle (dim, breathing with
	    the beat), ATTEMPT N when the level starts, GRAVITY FLIP! at half
	    health, DROP IN 3... 2... 1..., STUNNED! HIT HIM!, and LEVEL COMPLETE!:
	    he shatters into little cubes
	  * the level's % under the boss bar (how far through him you are), a hint
	    over him when he's open, and you can't walk through him

	HOW A BODY FILE WORKS: see BossBodies/_Template.lua. This one's own pose
	fields: eyes (0-1 open), mouth ("grin", "open", "o", "shut"), glow (0-1:
	his neon blazing), dizzy, squash (on the beat), fade (0-1: shattered),
	ghost (0-1: see-through), beam (0-1: the UFO's tractor beam).
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local BeatGrid = require(ReplicatedStorage:WaitForChild("BeatGrid"))

local Body = {}
-- (which arena copy is this boss's: ReplicatedStorage/Arenas)
local Arenas = require(game:GetService("ReplicatedStorage"):WaitForChild("Arenas"))

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, easeOutBack, spring, flat
local fxFolder, newPart, placeDisc, newRing, placeRing, removeRing, burst
local kick, playSound, findSound, addTelegraph, shockRing, at, SLOT_NAMES, myRoot
local bigText, shout

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config (all from the game's 32)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local NIGHT = RGB(38, 43, 68)
local HOT = RGB(255, 0, 68)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local ORANGE = RGB(247, 118, 34)
local YELLOW = RGB(254, 231, 97)
local GREEN = RGB(99, 199, 77)
local CYAN = RGB(44, 232, 245)
local BLUE = RGB(0, 153, 219)
local PURPLE = RGB(104, 56, 108)
local MAGENTA = RGB(181, 80, 136)
local PINK = RGB(246, 117, 122)
local PIXEL_FONT = nil

-- the colour of each form's portal (the new form's), and the gravity portals'
-- (yellow turns you upside down, blue puts you back - like the real thing)
local FORMS = { "Cube", "Ship", "Ufo", "Wave" }
local PORTAL_COLOR = { Cube = GREEN, Ship = PINK, Ufo = ORANGE, Wave = CYAN }
local FORM_SHOUT = { Cube = "CUBE!", Ship = "SHIP!", Ufo = "UFO!", Wave = "WAVE!" }
local GRAVITY_UP, GRAVITY_DOWN = YELLOW, BLUE

-- (how many attempts you've made at him since you joined: ATTEMPT N)
local attempts = 0

function Body.init(kit)
	serverNow, clamp, lerp, smooth = kit.serverNow, kit.clamp, kit.lerp, kit.smooth
	easeOutBack, spring, flat = kit.easeOutBack, kit.spring, kit.flat
	fxFolder, newPart, placeDisc, newRing, placeRing = kit.fxFolder, kit.newPart, kit.placeDisc, kit.newRing, kit.placeRing
	removeRing, burst = kit.removeRing, kit.burst
	kick, playSound, findSound = kit.kick, kit.playSound, kit.findSound
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
				if d.Short == "Gridlock" then
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
			for _, key in ipairs({ "Music", "Round2Music", "FallbackMusic" }) do
				local music = def and def[key] and findSound(def[key])
				if music then
					table.insert(list, music)
				end
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

local function rightOf(dir)
	return V3(-dir.Z, 0, dir.X)
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

-- a block stretched from a to b (world points), `w` wide and `d` deep
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
		up = V3(1, 0, 0)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- one of his sounds, played only if you're in his level (the lobby doesn't
-- need to hear him)
local function sfx(B, key, volume)
	if B.here then
		playSound(B.def, key, B.center3 or B.vpos, volume or 1)
	end
end

-- a word bubble over him
local function yell(B, text, seconds, color)
	if B.here then
		pcall(function()
			shout(B.body.core, text, seconds or 1, color or YELLOW)
		end)
	end
end

-- big pixel words across the screen (only if you're in his level)
local function banner(B, text, opts)
	if B.here then
		pcall(function()
			bigText(text, opts)
		end)
	end
end

----------------------------------------------------------------------
-- The level: its grid, and the beat
----------------------------------------------------------------------
-- the level on your screen (the model with this floor's number and its grid;
-- looked for again now and then - it may not have loaded yet)
local function levelOf(B)
	if B.level and B.level.Parent then
		return B.level
	end
	if os.clock() < (B.levelLook or -math.huge) + 2 then
		return nil
	end
	B.levelLook = os.clock()
	B.level = Arenas.arenaFor(B.model, "Tiles") -- (his own arena copy)
	if B.level then
		local c = B.level:GetAttribute("Center")
		B.grid = BeatGrid.grid(c, B.level:GetAttribute("Tiles") or 15, B.level:GetAttribute("TileSize") or 8)
		B.floorY = c.Y
		B.ceiling = B.level:GetAttribute("Ceiling") or B.def.Ceiling
	end
	return B.level
end

-- the grid (from the level, or - until it has loaded - round where he sleeps)
local function gridOf(B)
	levelOf(B)
	if not B.grid then
		B.grid = BeatGrid.grid(V3(B.vpos.X, B.vpos.Y, B.vpos.Z), 15, 8)
		B.floorY = B.floorY or B.vpos.Y
	end
	return B.grid
end

local function floorY(B)
	gridOf(B)
	return B.floorY or B.vpos.Y
end

local function bpm(B)
	return B.model:GetAttribute("Bpm") or B.def.Bpm or 120
end

-- the moment the beat started counting (the server's BeatStart; before it
-- arrives, the start of the wake, the same sum the server uses)
local function beat0(B)
	local b = B.model:GetAttribute("BeatStart")
	local wake = B.wakeAt and (B.wakeAt + (B.def.BeatOffset or 0)) or nil
	if type(b) == "number" and (not wake or b >= wake - 0.5) then
		return b
	end
	return wake or 0
end

local function beatTime(B, k)
	return BeatGrid.beatTime(beat0(B), bpm(B), k)
end

-- how far into the beat we are (0 right on it), and which beat it is
local function beatNow(B, now)
	local len = BeatGrid.beatLen(bpm(B))
	local x = (now - beat0(B)) / len
	local k = math.floor(x)
	return x - k, k
end

----------------------------------------------------------------------
-- Where he is: his move (the server's own sums, from BeatGrid)
----------------------------------------------------------------------
-- News of a new move reaches your screen a moment after it began (your ping),
-- so he'd jump a little each time: instead the gap is kept and melts away in
-- about a tenth of a second. (The moves whose start matters are published
-- before they start, so those are never late.)
local onMove -- (what a new move sets off: see below)
local function follow(B, now)
	if B.followAt == now and B.here3 then
		return B.here3, B.alt
	end
	local last = B.followAt or now
	B.followAt = now
	local m = BeatGrid.readMove(B.model)
	if not m then
		return nil, nil
	end
	local p, h, u = BeatGrid.motion(m, now)
	local pos = V3(p.X, h, p.Z)
	if m.id ~= B.moveId then
		local gap = B.drawn3 and (B.drawn3 - pos).Magnitude or math.huge
		if B.moveId ~= nil and gap < 30 then
			B.offset = B.drawn3 - pos
		else
			B.offset = V3() -- (the first sight of him, or put back home: no melting)
		end
		local old = B.move
		B.moveId, B.move = m.id, m
		if onMove then
			onMove(B, m, old, now)
		end
	end
	B.offset = (B.offset or V3()) * math.exp(-math.max(now - last, 0) / 0.07)
	B.drawn3 = pos + B.offset
	B.moveU = u
	B.here3 = V3(B.drawn3.X, floorY(B), B.drawn3.Z)
	B.alt = B.drawn3.Y
	return B.here3, B.alt
end

-- which way he's going right now (from his move a moment ago)
local function heading(B, now)
	local m = B.move
	if not m then
		return nil
	end
	local p1 = BeatGrid.motion(m, now)
	local p0 = BeatGrid.motion(m, now - 0.04)
	local d = flat(p1 - p0)
	if d.Magnitude < 0.02 then
		return nil
	end
	return d.Unit, d.Magnitude / 0.04
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
-- (the cube's twelve edges: each is along one axis, at two of the other two's signs)
local EDGES = {}
for axis = 1, 3 do
	for _, s1 in ipairs({ -1, 1 }) do
		for _, s2 in ipairs({ -1, 1 }) do
			table.insert(EDGES, { axis, s1, s2 })
		end
	end
end

function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder, all = {} }
	local neon, dark = def.Color or HOT, def.DeepColor or INK
	body.neon = neon
	local function add(name, color, material, group)
		local p = newPart(name, nil, color, material or Enum.Material.SmoothPlastic, 0, folder)
		table.insert(body.all, { part = p, color = p.Color, material = p.Material, group = group })
		return p
	end
	-- THE CUBE (his face is on its front): the black block, twelve neon edges,
	-- slanted eyes with pupils, angry brows, a jagged grin, little horns
	body.core = add("Core", dark, nil, "icon")
	body.edges = {}
	for i = 1, #EDGES do
		body.edges[i] = add("Edge", neon, Enum.Material.Neon, "icon")
	end
	body.eyes, body.pupils, body.brows, body.horns = {}, {}, {}, {}
	for i = 1, 2 do
		body.eyes[i] = add("Eye", def.EyeColor or YELLOW, Enum.Material.Neon, "icon")
		body.pupils[i] = add("Pupil", INK, nil, "icon")
		body.brows[i] = add("Brow", neon, Enum.Material.Neon, "icon")
		body.horns[i] = add("Horn", neon, Enum.Material.Neon, "icon")
	end
	body.mouth = add("Mouth", RED_DARK, nil, "icon")
	body.teeth = {}
	for i = 1, 9 do
		body.teeth[i] = add("Tooth", WHITE, nil, "icon")
	end
	body.xs = {}
	for i = 1, 4 do
		body.xs[i] = add("EyeX", WHITE, Enum.Material.Neon, "icon")
	end
	-- THE SHIP: a black hull with a diamond nose, swept wings, a tail fin,
	-- neon edges all round (like his cube's), a thruster and its flame (he
	-- rides in the cockpit)
	local function edge(name, group)
		return add(name, neon, Enum.Material.Neon, group)
	end
	body.ship = {
		hull = add("ShipHull", dark, nil, "Ship"),
		nose = add("ShipNose", dark, nil, "Ship"),
		tip = edge("ShipTip", "Ship"),
		wings = { add("ShipWing", NIGHT, nil, "Ship"), add("ShipWing", NIGHT, nil, "Ship") },
		wingEdges = { edge("ShipWingEdge", "Ship"), edge("ShipWingEdge", "Ship") },
		fin = add("ShipFin", NIGHT, nil, "Ship"),
		finEdge = edge("ShipFinEdge", "Ship"),
		trims = { edge("ShipTrim", "Ship"), edge("ShipTrim", "Ship") },
		thruster = add("ShipThruster", ORANGE, Enum.Material.Neon, "Ship"),
		flame = add("ShipFlame", YELLOW, Enum.Material.Neon, "Ship"),
	}
	-- THE UFO: an eight-sided saucer with a neon rim, lights round it, a
	-- glowing belly, a glass dome (he sits inside)
	body.ufo = {
		disc = add("UfoDisc", dark, nil, "Ufo"),
		discB = add("UfoDisc", dark, nil, "Ufo"),
		rims = { edge("UfoRim", "Ufo"), edge("UfoRim", "Ufo") },
		belly = add("UfoBelly", ORANGE, Enum.Material.Neon, "Ufo"),
		dome = add("UfoDome", CYAN, Enum.Material.Glass, "Ufo"),
		lights = {},
	}
	for i = 1, 8 do
		body.ufo.lights[i] = add("UfoLight", YELLOW, Enum.Material.Neon, "Ufo")
	end
	-- THE WAVE: a neon-edged dart
	body.wave = {
		dart = add("WaveDart", dark, nil, "Wave"),
		tip = add("WaveTip", dark, nil, "Wave"),
		edges = {},
	}
	for i = 1, 4 do
		body.wave.edges[i] = add("WaveEdge", CYAN, Enum.Material.Neon, "Wave")
	end
	-- dizzy stars (stunned), the tractor beam (the UFO slam), his shadow
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, Enum.Material.Neon, "fx")
	end
	body.beam = add("TractorBeam", YELLOW, Enum.Material.Neon, "fx")
	body.shadow = newPart("Shadow", nil, INK, Enum.Material.SmoothPlastic, 0, folder)
	-- (the level's warnings live in their own folder, their parts reused)
	body.tiles = Instance.new("Folder")
	body.tiles.Name = "LevelTiles"
	body.tiles.Parent = folder
	-- which parts show in which form (the rest decide for themselves)
	body.custom = {}
	for _, p in ipairs({ body.ufo.dome, body.beam, body.ship.flame }) do
		body.custom[p] = true
	end
	-- each part flies off at its own moment when he shatters
	body.popAt = {}
	for i, rec in ipairs(body.all) do
		body.popAt[rec.part] = ((i * 37) % 31) / 31
	end
	folder.Parent = fxFolder
	return body
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
-- each form's half-height (the middle of his box is this far over its
-- bottom: the server's own numbers), how wide his shadow is, and the box you
-- can't walk into (half its size each way, the server's too)
local HALF_Y = { Cube = 5, Ship = 2.6, Ufo = 2.6, Wave = 2.2 }
local FOOT = { Cube = 10, Ship = 9, Ufo = 11, Wave = 7 }
local BOX = {
	Cube = V3(5, 5, 5),
	Ship = V3(5.5, 2.6, 5.5),
	Ufo = V3(6.5, 2.6, 6.5),
	Wave = V3(4, 2.2, 4),
}
local R45 = CFrame.Angles(0, math.rad(45), 0)

-- `x` moved toward `want` by at most `step`
local function approach(x, want, step)
	if x < want then
		return math.min(x + step, want)
	end
	return math.max(x - step, want)
end

-- `dir` turned round the up axis by `a` radians
local function turnY(dir, a)
	return CFrame.Angles(0, a, 0) * dir
end

-- a part placed in frame `cf` (x right, y up, z back), everything `k` times
-- as big and stretched by sx / sy / sz
local function putIn(cf, k, sx, sy, sz, p, x, y, z, w, h, d, rot)
	p.Size = V3(math.max(w * k * sx, 0.05), math.max(h * k * sy, 0.05), math.max(d * k * sz, 0.05))
	local c = cf * CFrame.new(x * k * sx, y * k * sy, z * k * sz)
	p.CFrame = rot and c * rot or c
end

-- his mouth's shapes: the band's width, height and height on his face; and
-- his teeth (0 none, 1 a jagged grin, 2 wide apart)
local MOUTHS = {
	grin = { 6.4, 2.2, -2.3, 1 },
	open = { 6.0, 3.6, -2.6, 2 },
	o = { 2.4, 2.4, -2.6, 0 },
	shut = { 5.2, 0.6, -2.4, 0 },
}
local TOP_TEETH = { -2.6, -1.3, 0, 1.3, 2.6 }
local BOTTOM_TEETH = { -1.95, -0.65, 0.65, 1.95 }

-- HIS FACE: the cube, drawn round frame `cf` (its middle; his face is on its
-- front, -z), `k` times full size (1 = the 10-stud cube; small when he rides
-- in a ship, a UFO or on the wave). Parts that shouldn't show go in B.hide.
local function placeIcon(B, cf, k, P, sx, sy, sz)
	local body = B.body
	local hide = B.hide
	local function put(p, x, y, z, w, h, d, rot)
		putIn(cf, k, sx, sy, sz, p, x, y, z, w, h, d, rot)
	end
	put(body.core, 0, 0, 0, 9.7, 9.7, 9.7)
	local e, off, len = 0.9, 4.55, 10.05
	for i, ed in ipairs(EDGES) do
		local axis, s1, s2 = ed[1], ed[2], ed[3]
		if axis == 1 then
			put(body.edges[i], 0, s1 * off, s2 * off, len, e, e)
		elseif axis == 2 then
			put(body.edges[i], s1 * off, 0, s2 * off, e, len, e)
		else
			put(body.edges[i], s1 * off, s2 * off, 0, e, e, len)
		end
	end
	-- where his eyes look: at you (on your screen he's always glaring at YOU)
	local px, py = 0, 0
	if B.lookAt then
		local rel = cf:PointToObjectSpace(B.lookAt)
		if rel.Z < -1 then
			px = clamp(rel.X / -rel.Z * 1.4, -0.55, 0.55)
			py = clamp(rel.Y / -rel.Z * 1.4, -0.35, 0.35)
		end
	end
	local zf = -4.93
	local dizzy = (P.dizzy or 0) > 0.5
	local anger = P.anger or 0.5
	local slit = B.phase2Look
	for i = 1, 2 do
		local s = (i == 1) and -1 or 1
		local slant = CFrame.Angles(0, 0, s * 0.3)
		local own = P.eyeR
		if i == 1 then
			own = P.eyeL
		end
		local open = clamp(own or P.eyes or 1, 0, 1)
		put(body.eyes[i], s * 2.2, 1.2, zf, 2.8, math.max(1.8 * open, 0.14), 0.12, slant)
		put(body.pupils[i], s * 2.2 + px, 1.2 + py * open, zf - 0.05, slit and 0.45 or 0.9, math.max((slit and 1.4 or 0.9) * open, 0.1), 0.1, slant)
		put(body.brows[i], s * 2.2, 2.75 + (P.browUp or 0), zf, 3.4, 0.7, 0.3, CFrame.Angles(0, 0, s * (0.15 + 0.4 * anger)))
		put(body.horns[i], s * 3.4, 6.1, -2.4, 1.4, 3.0, 1.4, CFrame.Angles(0, 0, -s * 0.5))
		-- X eyes (dizzy, or done for)
		for j = 1, 2 do
			local x = body.xs[(i - 1) * 2 + j]
			put(x, s * 2.2, 1.2, zf - 0.03, 2.6, 0.55, 0.12, CFrame.Angles(0, 0, (j == 1) and 0.785 or -0.785))
			if not dizzy then
				hide[x] = true
			end
		end
		if dizzy then
			hide[body.eyes[i]] = true
			hide[body.pupils[i]] = true
		elseif open < 0.3 then
			hide[body.pupils[i]] = true
		end
	end
	local m = MOUTHS[P.mouth] or MOUTHS.grin
	put(body.mouth, 0, m[3], zf, m[1], m[2], 0.12)
	local teeth = m[4]
	for i, tooth in ipairs(body.teeth) do
		if teeth == 0 then
			hide[tooth] = true
		else
			local inset = (teeth == 1) and 0.15 or 0.25
			local x, y
			if i <= #TOP_TEETH then
				x, y = TOP_TEETH[i], m[3] + m[2] / 2 - inset
			else
				x, y = BOTTOM_TEETH[i - #TOP_TEETH], m[3] - m[2] / 2 + inset
			end
			put(tooth, x * m[1] / 6.4, y, zf - 0.03, 1.0, 1.0, 0.1, CFrame.Angles(0, 0, math.rad(45)))
		end
	end
end

-- his neon, from dim (0) through bright (1) to white-hot (1.5)
local function glowColor(neon, glow)
	if glow <= 1 then
		return RED_DARK:Lerp(neon, clamp(glow, 0, 1))
	end
	return neon:Lerp(WHITE, clamp(glow - 1, 0, 1))
end

local function applyPose(B, P, ground, facing, t, dt)
	local body = B.body
	local now = serverNow()
	dt = clamp(dt, 1 / 240, 1 / 15)
	local _ = t
	local form = B.formShown or "Cube"
	local fy = floorY(B)
	local spot = B.here3 or ground
	local alt = (B.alt or 0) + (P.lift or 0)
	local fade = clamp(P.fade or 0, 0, 1)
	local ghost = clamp(P.ghost or 0, 0, 1)
	local look = unitOr(flat(facing), V3(0, 0, 1))
	if P.spin and P.spin ~= 0 then
		look = turnY(look, P.spin)
	end
	local jitter = V3()
	if (P.shake or 0) > 0 then
		jitter = V3(math.sin(now * 53), math.sin(now * 47) * 0.5, math.cos(now * 61)) * P.shake
	end
	local sx, sy, sz = P.sx or 1, P.sy or 1, P.sz or 1
	local halfY = HALF_Y[form]
	local center = V3(spot.X, fy + alt + halfY, spot.Z) + jitter
	B.center3 = center
	-- (upside down on the ceiling: he rolls over, quickly, when gravity flips)
	local wantInv = (B.gravShown == -1) and math.pi or 0
	B.inv = approach(B.inv or wantInv, wantInv, dt * 9)
	-- a pop when he changes form: small, then springing out to full size
	local k = 1
	if B.popAt and now >= B.popAt and now < B.popAt + 0.4 then
		k = lerp(0.55, 1, easeOutBack((now - B.popAt) / 0.3))
	end
	B.hide = B.hide or {}
	B.tint = B.tint or {}
	local hide, tint = B.hide, B.tint
	table.clear(hide)
	table.clear(tint)
	local root = myRoot()
	B.lookAt = P.lookAt or (root and root.Position) or nil

	local neon = body.neon
	local glow = P.glow or 0.8
	local edgeColor = glowColor(neon, glow)
	local up = V3(0, 1, 0)
	local iconK = k
	if form == "Cube" then
		-- THE CUBE: squashed onto his feet (the floor - or the ceiling), then
		-- flipped round his middle as he hops
		-- (P.anchorHead: squashed against whatever his head hit instead)
		local base = CFrame.lookAt(center, center + look) * CFrame.Angles(0, 0, B.inv)
		base = base * CFrame.new(0, (P.anchorHead and -1 or 1) * halfY * (sy - 1), 0)
		local cf = base * CFrame.Angles(-(P.flip or 0) - (P.lean or 0), 0, P.tilt or 0)
		placeIcon(B, cf, k, P, sx, sy, sz)
		up = base.UpVector
	else
		-- A VEHICLE: it pitches as it climbs or dives, and banks into turns
		local vy = smoothTo(B, "vyS", (alt - (B.lastAlt or alt)) / dt, 8, dt)
		local turn = (B.lastLook or look):Cross(look).Y
		local yawRate = smoothTo(B, "yawS", math.asin(clamp(turn, -1, 1)) / dt, 8, dt)
		local pitch, bank = P.pitch or 0, P.bank or 0
		if form == "Ship" then
			pitch += clamp(vy * 0.035, -0.55, 0.55)
			bank += clamp(yawRate * 0.18, -0.7, 0.7)
		elseif form == "Ufo" then
			bank += clamp(yawRate * 0.06, -0.3, 0.3)
		else
			pitch += clamp(vy * 0.03, -0.4, 0.4)
			bank += clamp(yawRate * 0.12, -0.6, 0.6)
		end
		local vcf = CFrame.lookAt(center, center + look) * CFrame.Angles(pitch - (P.lean or 0), 0, bank + (P.tilt or 0))
		local function put(p, x, y, z, w, h, d, rot)
			putIn(vcf, k, sx, sy, sz, p, x, y, z, w, h, d, rot)
		end
		local ph, bk = beatNow(B, now)
		if form == "Ship" then
			local sh = body.ship
			put(sh.hull, 0, 0, 0.6, 5.2, 2.2, 8.4)
			put(sh.nose, 0, -0.1, -4.0, 3.4, 2.0, 3.4, R45)
			put(sh.tip, 0, -0.1, -5.9, 1.3, 1.1, 1.3, R45)
			tint[sh.tip] = edgeColor
			for i, wing in ipairs(sh.wings) do
				local s = (i == 1) and -1 or 1
				-- (each wing swept back, a neon strip along its front edge)
				local wcf = vcf * CFrame.new(s * 4.2 * k * sx, -0.5 * k * sy, 1.8 * k * sz) * CFrame.Angles(0, -s * 0.45, 0)
				wing.Size = V3(4.4 * k * sx, 0.5 * k * sy, 4.2 * k * sz)
				wing.CFrame = wcf
				local we = sh.wingEdges[i]
				we.Size = V3(4.7 * k * sx, 0.35 * k * sy, 0.5 * k * sz)
				we.CFrame = wcf * CFrame.new(0, 0.1 * k * sy, -2.1 * k * sz)
				tint[we] = edgeColor
			end
			local fcf = vcf * CFrame.new(0, 1.9 * k * sy, 3.3 * k * sz) * CFrame.Angles(0.35, 0, 0)
			sh.fin.Size = V3(0.5 * k * sx, 2.4 * k * sy, 2.6 * k * sz)
			sh.fin.CFrame = fcf
			sh.finEdge.Size = V3(0.62 * k * sx, 2.5 * k * sy, 0.4 * k * sz)
			sh.finEdge.CFrame = fcf * CFrame.new(0, 0, 1.3 * k * sz)
			tint[sh.finEdge] = edgeColor
			for i, trim in ipairs(sh.trims) do
				local s = (i == 1) and -1 or 1
				put(trim, s * 2.5, 1.1, 0.6, 0.4, 0.4, 8.3)
				tint[trim] = edgeColor
			end
			put(sh.thruster, 0, 0, 5.0, 3.0, 1.6, 0.6)
			local flame = clamp(P.flame or 0.45, 0, 1)
			local L = 0.8 + 4.4 * flame * (0.85 + 0.15 * math.sin(now * 40))
			put(sh.flame, 0, 0, 5.3 + L / 2, 1.8 - 0.6 * flame, 1.0, L)
			tint[sh.thruster] = ORANGE:Lerp(YELLOW, flame)
			sh.flame.Transparency = (fade > 0.5 or ghost > 0.5) and 1 or 0.15
			sh.flame.Color = flame > 0.7 and WHITE or YELLOW
			iconK = 0.42 * k
			placeIcon(B, vcf * CFrame.new(0, 2.6 * k * sy, 0.4 * k * sz), iconK, P, sx, sy, sz)
		elseif form == "Ufo" then
			local uf = body.ufo
			put(uf.disc, 0, 0, 0, 9.4, 1.4, 9.4)
			put(uf.discB, 0, 0, 0, 9.4, 1.4, 9.4, R45)
			put(uf.rims[1], 0, -0.5, 0, 9.9, 0.45, 9.9)
			put(uf.rims[2], 0, -0.5, 0, 9.9, 0.45, 9.9, R45)
			tint[uf.rims[1]], tint[uf.rims[2]] = edgeColor, edgeColor
			put(uf.belly, 0, -1.1, 0, 5.4, 1.0, 5.4, R45)
			put(uf.dome, 0, 2.3, 0, 5.8, 4.2, 5.8)
			uf.dome.Transparency = (fade > 0.5 or ghost > 0.5) and 1 or 0.6
			-- lights chasing round the rim, one step an eighth of a beat
			local chase = math.floor((bk + ph) * 8)
			for i, l in ipairs(uf.lights) do
				local a = (i - 1) / 8 * math.pi * 2
				put(l, math.sin(a) * 6.2, 0.1, math.cos(a) * 6.2, 0.9, 0.7, 0.9)
				local lit = ((i + chase) % 4 == 0) or (P.lightsAll == true)
				tint[l] = lit and YELLOW or RED_DARK
			end
			tint[uf.belly] = ORANGE:Lerp(YELLOW, clamp(P.beam or 0, 0, 1))
			iconK = 0.4 * k
			placeIcon(B, vcf * CFrame.new(0, 2.2 * k * sy, 0), iconK, P, sx, sy, sz)
		else
			local wv = body.wave
			put(wv.dart, 0, 0, 0.6, 4.6, 1.6, 4.6, R45)
			put(wv.tip, 0, 0, -3.3, 2.2, 1.4, 2.2, R45)
			local corners = { V3(0, 0.85, -4.85), V3(-3.25, 0.85, 0.6), V3(0, 0.85, 3.85), V3(3.25, 0.85, 0.6) }
			for i, edge in ipairs(wv.edges) do
				local a, b = corners[i], corners[i % 4 + 1]
				stretch(edge, vcf * V3(a.X * k * sx, a.Y * k * sy, a.Z * k * sz), vcf * V3(b.X * k * sx, b.Y * k * sy, b.Z * k * sz), 0.45 * k, 0.45 * k, vcf.UpVector)
				tint[edge] = CYAN:Lerp(WHITE, 0.6 * (1 - ph) ^ 3)
			end
			iconK = 0.34 * k
			placeIcon(B, vcf * CFrame.new(0, 2.5 * k * sy, 0.9 * k * sz), iconK, P, sx, sy, sz)
		end
		up = vcf.UpVector
	end
	B.lastAlt, B.lastLook = alt, look

	-- his colours: the neon glowing with the beat, the eyes (cyan in round 2)
	for _, ed in ipairs(body.edges) do
		tint[ed] = edgeColor
	end
	for i = 1, 2 do
		tint[body.brows[i]] = edgeColor
		tint[body.horns[i]] = edgeColor
		tint[body.eyes[i]] = B.phase2Look and CYAN or (B.def.EyeColor or YELLOW)
	end

	-- DIZZY: stars circling over his head
	local dizzy = clamp(P.dizzy or 0, 0, 1)
	local headTop = center + up * (halfY * sy * ((form == "Cube") and 1 or 0.6) + 2.2)
	for i, star in ipairs(body.stars) do
		if dizzy > 0.05 and fade < 0.5 then
			local a = now * 4 + i * math.pi * 2 / 3
			star.Size = V3(0.9, 0.9, 0.9)
			star.CFrame = CFrame.new(headTop + V3(math.sin(a) * 3.2, math.sin(a * 2) * 0.4, math.cos(a) * 3.2)) * CFrame.Angles(0, a, math.rad(45))
			star.Transparency = 1 - dizzy
		else
			star.Transparency = 1
		end
	end
	-- THE TRACTOR BEAM (the UFO slam): a column of light down to the tiles
	local beam = clamp(P.beam or 0, 0, 1)
	if form == "Ufo" and beam > 0.02 and fade < 0.5 then
		local top = center - V3(0, 1.4, 0)
		local h = math.max(top.Y - fy, 0.5)
		body.beam.Size = V3(7.5, h, 7.5)
		body.beam.CFrame = CFrame.new(V3(top.X, fy + h / 2, top.Z)) * CFrame.Angles(0, now * 1.5, 0)
		body.beam.Transparency = 1 - beam * (0.35 + 0.1 * math.sin(now * 30))
	else
		body.beam.Transparency = 1
	end
	-- HIS SHADOW on the tiles
	local shadow = body.shadow
	local shrink = 1 - clamp(alt / 60, 0, 0.6)
	local foot = FOOT[form] * k * shrink
	shadow.Size = V3(foot, 0.1, foot)
	local sp = V3(spot.X, fy + 0.09, spot.Z)
	shadow.CFrame = CFrame.lookAt(sp, sp + look)
	shadow.Transparency = (fade > 0.5 or ghost > 0.5) and 1 or lerp(0.45, 0.85, clamp(alt / 45, 0, 1))

	-- which parts show (his face always; the vehicle he's in; nothing else),
	-- how see-through, and their colour (white for a blink when he's hit, or
	-- as he changes form)
	local flash = (B.flashAt ~= nil and (os.clock() - B.flashAt) < 0.08) or (B.whiteUntil ~= nil and now < B.whiteUntil)
	local see = math.max(fade, ghost * 0.85)
	for _, rec in ipairs(body.all) do
		local p = rec.part
		if not body.custom[p] and rec.group ~= "fx" then
			local on = (rec.group == "icon" or rec.group == form) and not hide[p]
			p.Transparency = on and see or 1
			p.Color = flash and WHITE or (tint[p] or rec.color)
		end
	end
	if form ~= "Ship" then
		body.ship.flame.Transparency = 1
	end
	if form ~= "Ufo" then
		body.ufo.dome.Transparency = 1
	end

	-- LEVEL COMPLETE: he shatters, every piece flying off on its own
	if B.shatterAt and now >= B.shatterAt then
		if not B.shards then
			B.shards = {}
			for i, rec in ipairs(body.all) do
				local p = rec.part
				if p.Transparency < 1 then
					local pop = body.popAt[p] or 0
					local out = unitOr(flat(p.Position - center), V3(math.sin(i * 2.4), 0, math.cos(i * 2.4)))
					B.shards[p] = {
						cf = p.CFrame,
						vel = out * (16 + pop * 22) + V3(0, 18 + ((i * 7) % 11) * 1.8, 0),
						spin = V3(((i * 3) % 7 - 3) * 1.6, ((i * 5) % 9 - 4) * 1.4, ((i * 11) % 5 - 2) * 2),
						delay = pop * 0.25,
						tr = p.Transparency,
					}
				end
			end
		end
		for _, rec in ipairs(body.all) do
			local p = rec.part
			local s = B.shards[p]
			if s then
				local tau = math.max(now - B.shatterAt - s.delay, 0)
				local pos = s.cf.Position + s.vel * tau + V3(0, -22.5 * tau * tau, 0)
				p.CFrame = CFrame.new(pos) * CFrame.Angles(s.spin.X * tau, s.spin.Y * tau, s.spin.Z * tau) * (s.cf - s.cf.Position)
				p.Transparency = math.max(s.tr, clamp((tau - 0.7) / 1.0, 0, 1))
			else
				p.Transparency = 1
			end
		end
		shadow.Transparency = 1
	end
end

Body.pose = applyPose

----------------------------------------------------------------------
-- THE LEVEL: tiles lighting up, then spiking, on the beat
----------------------------------------------------------------------
-- Every tile attack the server publishes (Tiles1..12 and TilesK - see
-- ServerScriptService/Bosses/Gridlock.lua) is drawn with the same sums
-- (BeatGrid): from its warning beat a red square on each tile, flaring on
-- every beat (white on the last one: GET OFF!), then on the beat it hurts
-- spikes shoot up out of it - or a bomb bursts on it, an orb lands on it, he
-- lands on it - and then it's gone. The parts are reused, never thrown away.
local PATTERN_SLOTS = 12 -- (the server's newest patterns, round and round Tiles1..12)
local SPIKE_RISE, SPIKE_SINK = 0.07, 0.18
-- a spike's three steps (a pixel spike): width (a share of the tile), height
-- (a share of the spike)
local STEPS = { { 0.72, 0.4 }, { 0.46, 0.35 }, { 0.2, 0.25 } }

local function levelState(B)
	if not B.lv then
		B.lv = { pats = {}, free = {}, made = 0, seen = nil }
	end
	return B.lv
end

-- a tile's parts: the warning on it (its spike's three steps are made the
-- first time it spikes)
local function takeTile(B)
	local lv = levelState(B)
	local e = table.remove(lv.free)
	if not e then
		e = { plate = newPart("TileWarn", nil, RED, Enum.Material.Neon, 1, B.body.tiles), folder = B.body.tiles }
		lv.made += 1
	end
	e.spikeK = nil
	return e
end

local function giveTile(B, e)
	e.plate.Transparency = 1
	for _, s in ipairs(e.steps or {}) do
		s.Transparency = 1
	end
	table.insert(levelState(B).free, e)
end

-- The biggest attacks light the whole floor (THE DROP; a checkerboard and
-- its other half), so the tiles' parts are made ahead, a few each frame while
-- the level starts - never a pile at once in the middle of the fight.
local POOL_WARM, WARM_EACH = 232, 12
local function warmPool(B)
	local lv = levelState(B)
	local n = 0
	while lv.made < POOL_WARM and n < WARM_EACH do
		local folder = B.body.tiles
		table.insert(lv.free, {
			plate = newPart("TileWarn", nil, RED, Enum.Material.Neon, 1, folder),
			folder = folder,
			steps = {
				newPart("TileSpike", nil, HOT, Enum.Material.Neon, 1, folder),
				newPart("TileSpike", nil, HOT, Enum.Material.Neon, 1, folder),
				newPart("TileSpikeTip", nil, WHITE, Enum.Material.Neon, 1, folder),
			},
		})
		lv.made += 1
		n += 1
	end
end

-- the spike on a tile, `r` of the way up (0 = gone)
local function placeSpike(e, spot, tile, height, r)
	if e.spikeK == r or (r <= 0.01 and not e.steps) then
		return
	end
	e.spikeK = r
	if not e.steps then
		e.steps = {
			newPart("TileSpike", nil, HOT, Enum.Material.Neon, 1, e.folder),
			newPart("TileSpike", nil, HOT, Enum.Material.Neon, 1, e.folder),
			newPart("TileSpikeTip", nil, WHITE, Enum.Material.Neon, 1, e.folder),
		}
	end
	local y = spot.Y
	for i, st in ipairs(STEPS) do
		local p = e.steps[i]
		if r <= 0.01 then
			p.Transparency = 1
		else
			local h = height * st[2] * r
			local w = tile * st[1]
			p.Size = V3(w, math.max(h, 0.05), w)
			p.CFrame = CFrame.new(V3(spot.X, y + h / 2, spot.Z))
			p.Transparency = 0
			y += h
		end
	end
end

-- the middles of a pattern's tiles (on the tiles' tops)
local function spotsOf(B, kind, a, b, c, d)
	local g = gridOf(B)
	local fy = floorY(B)
	local list = {}
	for _, tl in ipairs(BeatGrid.tiles(g, kind, a, b, c, d)) do
		local ctr = BeatGrid.tileCenter(g, tl[1], tl[2])
		list[#list + 1] = V3(ctr.X, fy, ctr.Z)
	end
	return list
end

-- THE DROP spikes the runway too (nobody hides there): spikes along it, two
-- across and three along
local function runwaySpots(B)
	local level = levelOf(B)
	local a = level and level:GetAttribute("RunwayA")
	local b = level and level:GetAttribute("RunwayB")
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return {}
	end
	local fy = floorY(B)
	local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
	local z0, z1 = math.min(a.Z, b.Z) + 1, math.max(a.Z, b.Z)
	local nx = math.max(1, math.floor((x1 - x0) / 8 + 0.5))
	local nz = math.max(1, math.floor((z1 - z0) / 8 + 0.5))
	local list = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			list[#list + 1] = V3(x0 + (i + 0.5) * (x1 - x0) / nx, fy, z0 + (j + 0.5) * (z1 - z0) / nz)
		end
	end
	return list
end

local function addPattern(B, pat)
	if pat.spots and not pat.center then
		local sum = V3()
		for _, s in ipairs(pat.spots) do
			sum += s
		end
		pat.center = (#pat.spots > 0) and sum / #pat.spots or gridOf(B).center
	end
	pat.tile = pat.tile or gridOf(B).size
	table.insert(levelState(B).pats, pat)
end

-- A GLOW over some tiles, for show (no harm): the level starting, flipping,
-- being beaten. `c` = which ring round the middle (0 = the middle tile).
local function glowRing(B, c, at0, dur, color)
	addPattern(B, { style = "glow", spots = spotsOf(B, "Ring", gridOf(B).mid, gridOf(B).mid, c, 0), tWarn = at0, tHit = at0, tEnd = at0 + dur, color = color, height = 0 })
end

-- how each server pattern looks: spikes (most), his landing (a tall square),
-- bombs and orbs (single tiles in those moves), THE DROP, the wave's wall
local function styleOf(p, action)
	if p.kind == "Trail" then
		return "trail"
	elseif p.kind == "Drop" then
		return "drop"
	elseif p.kind == "Square" and p.height >= 10 then
		return "slam"
	elseif p.kind == "Tile" and action == "BombRun" then
		return "bomb"
	elseif p.kind == "Tile" and action == "OrbRain" then
		return "orb"
	end
	return "spike"
end

local function serverPattern(B, p, now)
	local tWarn, tHit = beatTime(B, p.warn), beatTime(B, p.hit)
	local tEnd = beatTime(B, p.hit + p.len)
	if tEnd + 0.3 < now then
		return -- (long over)
	end
	local pat = { kind = p.kind, style = styleOf(p, B.model:GetAttribute("Action")), tWarn = tWarn, tHit = tHit, tEnd = tEnd, height = p.height }
	if p.kind == "Trail" then
		local c = gridOf(B).center
		local fy = floorY(B)
		pat.a = V3(c.X + p.a, fy, c.Z + p.b)
		pat.b = V3(c.X + p.c, fy, c.Z + p.d)
		pat.width = (B.def.Attacks.ZigZag and B.def.Attacks.ZigZag.Width) or 3
	else
		pat.spots = spotsOf(B, p.kind, p.a, p.b, p.c, p.d)
		if p.kind == "Drop" then
			for _, s in ipairs(runwaySpots(B)) do
				table.insert(pat.spots, s)
			end
		end
		if pat.style == "bomb" or pat.style == "orb" then
			pat.faller = {}
		end
	end
	addPattern(B, pat)
end

-- the server's new patterns (drawn only while you're in the level)
local function readPatterns(B, now, draw)
	local lv = levelState(B)
	local K = B.model:GetAttribute("TilesK")
	if type(K) ~= "number" then
		return
	end
	if lv.seen == nil or K < lv.seen then
		lv.seen = math.max(0, K - PATTERN_SLOTS)
	end
	if K > lv.seen + PATTERN_SLOTS then
		lv.seen = K - PATTERN_SLOTS
	end
	while lv.seen < K do
		lv.seen += 1
		if draw then
			local p = BeatGrid.decode(B.model:GetAttribute("Tiles" .. ((lv.seen - 1) % PATTERN_SLOTS + 1)))
			if p then
				serverPattern(B, p, now)
			end
		end
	end
end

-- a bomb (or an orb) falling out of him onto its tile, landing just as the
-- tile hurts
local function stepFaller(B, pat, now)
	local f = pat.faller
	if f.done then
		return
	end
	local bomb = pat.style == "bomb"
	local fall = bomb and 0.38 or 0.55
	local t0 = pat.tHit - fall
	if now < t0 then
		return
	end
	if not f.part then
		local from = (B.center3 or (pat.center + V3(0, 12, 0))) - V3(0, 2, 0)
		if flat(from - pat.center).Magnitude > 30 then
			from = pat.center + V3(0, 14, 0)
		end
		f.from = from
		if bomb then
			f.part = newPart("Bomb", nil, INK, Enum.Material.SmoothPlastic, 0, B.body.tiles)
			f.part.Size = V3(2.8, 2.8, 2.8)
			f.core = newPart("BombBand", nil, HOT, Enum.Material.Neon, 0, B.body.tiles)
			f.core.Size = V3(3.0, 0.9, 3.0)
			f.spark = newPart("BombSpark", nil, YELLOW, Enum.Material.Neon, 0, B.body.tiles)
			f.spark.Size = V3(1.1, 1.1, 1.1)
		else
			f.part = newPart("Orb", nil, MAGENTA, Enum.Material.Neon, 0, B.body.tiles)
			f.part.Size = V3(2.2, 2.2, 2.2)
			f.core = newPart("OrbCore", nil, WHITE, Enum.Material.Neon, 0, B.body.tiles)
			f.core.Size = V3(1, 1, 1)
		end
	end
	local u = clamp((now - t0) / fall, 0, 1)
	local to = pat.center + V3(0, 1, 0)
	local pos = V3(lerp(f.from.X, to.X, u), lerp(f.from.Y, to.Y, u * u), lerp(f.from.Z, to.Z, u))
	local spin = CFrame.new(pos) * CFrame.Angles(u * 4, u * 3, 0)
	f.part.CFrame = spin
	if f.spark then
		f.spark.CFrame = CFrame.new(pos + V3(0, 2, 0))
		f.spark.Transparency = (math.floor(now * 20) % 2 == 0) and 0 or 0.6
	end
	if f.core then
		f.core.CFrame = bomb and spin or (CFrame.new(pos) * CFrame.Angles(0, u * 6, math.rad(45)))
	end
	if u >= 1 then
		f.done = true
		for _, key in ipairs({ "part", "spark", "core" }) do
			if f[key] then
				f[key]:Destroy()
				f[key] = nil
			end
		end
	end
end

-- a quick flash of light standing on a spot (a bomb bursting, an orb landing)
local function flashColumn(B, spot, color, h, w)
	local p = newPart("Flash", nil, color, Enum.Material.Neon, 0.1)
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local u = (now - t0) / 0.3
			if u >= 1 then
				return false
			end
			local ww = w * (1 + u * 0.6)
			p.Size = V3(ww, h * (1 - u * 0.5), ww)
			p.CFrame = CFrame.new(spot + V3(0, h * (1 - u * 0.5) / 2, 0))
			p.Transparency = lerp(0.1, 1, u)
			return true
		end,
		cleanup = function()
			p:Destroy()
		end,
	})
end

-- the moment a pattern hurts: its sound, and a burst (once)
local function patternHits(B, pat)
	local now = serverNow()
	if pat.style == "bomb" then
		sfx(B, "Bomb", 0.8)
		burst(pat.center + V3(0, 1.5, 0), ORANGE, 16, 20, 1.6, 0.5, true)
		burst(pat.center + V3(0, 1, 0), YELLOW, 10, 14, 1.0, 0.4)
		flashColumn(B, pat.center, YELLOW, 7, 5)
		kick(pat.center, 6, 0.35, -1)
	elseif pat.style == "orb" then
		sfx(B, "Orb", 0.75)
		burst(pat.center + V3(0, 1, 0), MAGENTA, 16, 16, 1.2, 0.5, true)
		flashColumn(B, pat.center, PINK, 6, 4)
		kick(pat.center, 5, 0.3, -1)
	elseif pat.style == "spike" or pat.style == "drop" then
		-- (one clink a moment, however many rows spike at once)
		if now - (B.spikeSoundAt or -1) > 0.12 then
			B.spikeSoundAt = now
			local n = pat.spots and #pat.spots or 1
			sfx(B, "Spike", clamp(0.45 + n / 40, 0.45, 1))
		end
	end
end

-- one tile pattern, this frame; false once it's over
local function stepTiles(B, pat, now, beatLen, pulse, ph)
	local style = pat.style
	if now < pat.tWarn - 0.03 then
		return true -- (not yet)
	end
	if now >= pat.tEnd + ((style == "glow") and 0 or 0.3) then
		return false
	end
	if not pat.entries then
		pat.entries = {}
		local w = pat.tile - 0.8
		for k, spot in ipairs(pat.spots) do
			local e = takeTile(B)
			e.plate.Size = V3(w, 0.12, w)
			-- (a hair apart in height, so overlapping warnings don't flicker)
			e.plate.CFrame = CFrame.new(spot + V3(0, 0.07 + (#levelState(B).pats % 5) * 0.006, 0))
			pat.entries[k] = e
		end
	end
	local tr, col
	if style == "glow" then
		local u = clamp((now - pat.tWarn) / math.max(pat.tEnd - pat.tWarn, 1e-3), 0, 1)
		tr, col = lerp(0.15, 1, u), pat.color
	elseif now < pat.tHit then
		-- THE WARNING: brighter as it nears, flaring on every beat
		local u = clamp((now - pat.tWarn) / math.max(pat.tHit - pat.tWarn, 1e-3), 0, 1)
		local p = pulse
		if style == "drop" then
			p = (1 - ((ph * 2) % 1)) ^ 3 -- (the drop's: twice a beat)
		end
		tr = lerp(0.72, 0.32, u) - 0.28 * p
		col = (style == "drop") and HOT or RED
		if now >= pat.tHit - beatLen + 1e-3 then
			col = col:Lerp(WHITE, 0.65 * p) -- (the last beat: GET OFF!)
		end
	elseif now < pat.tEnd then
		if style == "slam" or style == "bomb" or style == "orb" then
			local u = clamp((now - pat.tHit) / 0.25, 0, 1)
			tr, col = lerp(0, 0.4, u), WHITE:Lerp(HOT, u)
		else
			tr, col = 0.1, HOT
		end
	else
		tr, col = lerp(0.3, 1, clamp((now - pat.tEnd) / 0.3, 0, 1)), HOT
	end
	tr = clamp(tr, 0, 1)
	if pat.lastTr == nil or math.abs(pat.lastTr - tr) > 0.01 or pat.lastCol ~= col then
		pat.lastTr, pat.lastCol = tr, col
		for _, e in ipairs(pat.entries) do
			e.plate.Transparency = tr
			e.plate.Color = col
		end
	end
	-- THE SPIKES: up out of the tiles as it hurts (a little too far, then
	-- settling), down again after
	if style == "spike" or style == "drop" then
		local r = 0
		if now >= pat.tHit and now < pat.tEnd then
			r = easeOutBack((now - pat.tHit) / SPIKE_RISE)
		elseif now >= pat.tEnd then
			r = 1 - clamp((now - pat.tEnd) / SPIKE_SINK, 0, 1)
		end
		r = math.floor(r * 50 + 0.5) / 50 -- (only redrawn when it has moved)
		for k, e in ipairs(pat.entries) do
			placeSpike(e, pat.spots[k], pat.tile, pat.height, r)
		end
	end
	if pat.faller then
		stepFaller(B, pat, now)
	end
	if now >= pat.tHit and not pat.hitDone and style ~= "glow" then
		pat.hitDone = true
		if now - pat.tHit < 0.4 then
			patternHits(B, pat)
		end
	end
	return true
end

-- THE WAVE'S WALL OF LIGHT: a dotted path blinking on the beat until he draws
-- it; the wall grows behind him as he zooms along (it hurts from the moment
-- he's done that leg), burns a few beats, and is gone
local function stepTrail(B, pat, now, beatLen, pulse)
	if now < pat.tWarn - 0.03 then
		return true
	end
	if now >= pat.tEnd + 0.3 then
		return false
	end
	local a, b = pat.a, pat.b
	if not pat.dots then
		local len = flat(b - a).Magnitude
		pat.dots = {}
		local n = math.max(2, math.floor(len / 2.6))
		for k = 1, n do
			local d = newPart("ZigDot", nil, CYAN, Enum.Material.Neon, 1, B.body.tiles)
			d.Size = V3(0.9, 0.12, 0.9)
			d.CFrame = CFrame.new(a:Lerp(b, (k - 0.5) / n) + V3(0, 0.09, 0)) * R45
			pat.dots[k] = d
		end
		pat.wall = newPart("LightWall", nil, CYAN, Enum.Material.Neon, 1, B.body.tiles)
		pat.core = newPart("LightWallCore", nil, WHITE, Enum.Material.Neon, 1, B.body.tiles)
	end
	local tDraw = pat.tHit - beatLen -- (he starts down this leg)
	for k, d in ipairs(pat.dots) do
		local drawn = now >= tDraw + (k - 0.5) / #pat.dots * beatLen
		d.Transparency = drawn and 1 or (0.15 + 0.55 * (1 - pulse))
	end
	local grow = clamp((now - tDraw) / beatLen, 0, 1)
	if grow <= 0 then
		pat.wall.Transparency, pat.core.Transparency = 1, 1
	else
		local tip = a:Lerp(b, grow)
		local h = pat.height
		local gone = (now > pat.tEnd) and clamp((now - pat.tEnd) / 0.3, 0, 1) or 0
		local hot = now >= pat.tHit
		local lift = V3(0, h / 2, 0)
		stretch(pat.wall, a + lift, tip + lift, pat.width, h)
		stretch(pat.core, a + lift, tip + lift, 0.5, h * 0.85)
		pat.wall.Transparency = lerp((hot and 0.3 or 0.55) - 0.15 * pulse, 1, gone)
		pat.core.Transparency = lerp(0.15, 1, gone)
	end
	return true
end

local function dropPattern(B, pat)
	for _, e in ipairs(pat.entries or {}) do
		giveTile(B, e)
	end
	pat.entries = nil
	for _, key in ipairs({ "wall", "core" }) do
		if pat[key] then
			pat[key]:Destroy()
			pat[key] = nil
		end
	end
	for _, d in ipairs(pat.dots or {}) do
		d:Destroy()
	end
	pat.dots = nil
	local f = pat.faller
	if f then
		for _, key in ipairs({ "part", "spark", "core" }) do
			if f[key] then
				f[key]:Destroy()
				f[key] = nil
			end
		end
	end
end

local function stepLevel(B, now)
	local lv = levelState(B)
	if #lv.pats == 0 then
		return
	end
	local beatLen = BeatGrid.beatLen(bpm(B))
	local ph = beatNow(B, now)
	local pulse = (1 - ph) ^ 3
	for i = #lv.pats, 1, -1 do
		local pat = lv.pats[i]
		local keep
		if pat.style == "trail" then
			keep = stepTrail(B, pat, now, beatLen, pulse)
		else
			keep = stepTiles(B, pat, now, beatLen, pulse, ph)
		end
		if not keep then
			dropPattern(B, pat)
			table.remove(lv.pats, i)
		end
	end
end

-- a clean level: nothing lit
local function clearLevel(B)
	local lv = levelState(B)
	for _, pat in ipairs(lv.pats) do
		dropPattern(B, pat)
	end
	lv.pats = {}
end

----------------------------------------------------------------------
-- THE LEVEL MOVES TO THE MUSIC (only on your screen, while you're in it)
----------------------------------------------------------------------
-- The neon under the tiles pulses on every beat (red, twice a beat, as THE
-- DROP builds; white as it hits; cyan in round 2). The jump pads bob on the
-- beat, glow green for the drop, and bounce when they throw someone up. The
-- saws spin, the neon frames turn, the floating blocks' glow flashes - and
-- when gravity flips, the whole world round the grid turns upside down.

-- the level's moving parts, found once (and again if it reloads): where each
-- started, so it can be put back exactly
local function worldOf(B)
	local level = levelOf(B)
	if not level then
		return nil
	end
	local w = B.world
	if w and w.level == level then
		return w
	end
	w = { level = level, pads = {}, saws = {}, frames = {}, glows = {}, still = {}, ang = 0 }
	local c = level:GetAttribute("Center") or B.here3 or V3()
	w.pivot = CFrame.new(c + V3(0, (level:GetAttribute("Ceiling") or 44) / 2, 0))
	for _, d in ipairs(level:GetDescendants()) do
		if d:IsA("BasePart") and CollectionService:HasTag(d, "GridUnder") then
			w.under, w.underColor = d, d.Color
		end
	end
	for _, pad in ipairs(CollectionService:GetTagged("JumpPad")) do
		if pad:IsDescendantOf(level) then
			local rec = { index = pad:GetAttribute("Index") or (#w.pads + 1), parts = {} }
			for _, d in ipairs(pad:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(rec.parts, { part = d, cf = d.CFrame, color = d.Color, name = d.Name })
					if d.Name == "PadPlate" then
						rec.center = d.Position
					end
				end
			end
			rec.center = rec.center or (rec.parts[1] and rec.parts[1].part.Position) or c
			w.pads[rec.index] = rec
		end
	end
	local back = nil
	for _, d in ipairs(CollectionService:GetTagged("GridBackdrop")) do
		if d:IsDescendantOf(level) then
			back = d
		end
	end
	if back then
		local owned = {}
		for _, saw in ipairs(CollectionService:GetTagged("GridSaw")) do
			if saw:IsDescendantOf(back) and saw.PrimaryPart then
				local hub = saw.PrimaryPart.CFrame
				local rec = { hub = hub, parts = {} }
				for _, d in ipairs(saw:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(rec.parts, { part = d, rel = hub:Inverse() * d.CFrame })
						owned[d] = true
					end
				end
				table.insert(w.saws, rec)
			end
		end
		for _, fr in ipairs(CollectionService:GetTagged("GridSpin")) do
			if fr:IsDescendantOf(back) then
				local sum, n, parts = V3(), 0, {}
				for _, d in ipairs(fr:GetDescendants()) do
					if d:IsA("BasePart") then
						sum += d.Position
						n += 1
						table.insert(parts, d)
					end
				end
				if n > 0 then
					local mid = sum / n
					local hub = CFrame.lookAt(mid, mid + unitOr(flat(c - mid), V3(0, 0, 1)))
					local rec = { hub = hub, parts = {} }
					for _, d in ipairs(parts) do
						table.insert(rec.parts, { part = d, rel = hub:Inverse() * d.CFrame })
						owned[d] = true
					end
					table.insert(w.frames, rec)
				end
			end
		end
		for _, d in ipairs(back:GetDescendants()) do
			if d:IsA("BasePart") and not owned[d] then
				table.insert(w.still, { part = d, cf = d.CFrame })
				if CollectionService:HasTag(d, "GridPulse") then
					table.insert(w.glows, { part = d, tr = d.Transparency })
				end
			end
		end
	end
	B.world = w
	return w
end

-- the moment of this move's beat x (counted from the beat it started on)
local function actBeat(B, x)
	return beatTime(B, (B.k0 or 0) + x)
end

-- is THE DROP building (from its start to the moment it spikes)? And the
-- jump pads: green (STAND HERE!) from its start until its spikes are gone
local function dropBuilding(B, now)
	return B.action == "Drop" and now < actBeat(B, B.def.Drop.Build) + 0.05
end
local function dropPads(B, now)
	return B.action == "Drop" and now < actBeat(B, B.def.Drop.Build + 0.5) + 0.35
end

local function stepWorld(B, now, awake)
	local w = worldOf(B)
	if not w then
		return
	end
	local ph, bk = beatNow(B, now)
	local pulse = (1 - ph) ^ 2
	local building = dropBuilding(B, now)
	-- the neon under the tiles
	if w.under then
		local col = w.underColor
		if awake or B.stateNow == "Dead" then
			local hi, amt = B.phase2Look and CYAN or MAGENTA, pulse * 0.8
			if building then
				col, hi, amt = RED_DARK, HOT, (1 - ((ph * 2) % 1)) ^ 2
			end
			if B.flashWorldAt and now - B.flashWorldAt < 0.5 and now >= B.flashWorldAt then
				hi, amt = B.flashColor or WHITE, 1 - (now - B.flashWorldAt) / 0.5
			end
			col = col:Lerp(hi, clamp(amt, 0, 1))
		else
			col = col:Lerp(MAGENTA, 0.2 * (0.5 + 0.5 * math.sin(now * 1.6))) -- (asleep: slow and soft)
		end
		w.under.Color = col
	end
	-- THE JUMP PADS: a bounce when one throws someone up (the server says which)
	local padAt = B.model:GetAttribute("PadAt")
	if type(padAt) == "number" and padAt ~= w.lastPadAt then
		w.lastPadAt = padAt
		local rec = w.pads[B.model:GetAttribute("PadIndex") or 0]
		if rec and now - padAt < 1 then -- (an old one, from before you came: skipped)
			rec.boingAt = padAt
			playSound(B.def, "Pad", rec.center, 0.8)
			burst(rec.center + V3(0, 1, 0), YELLOW, 14, 16, 0.8, 0.5, true)
		end
	end
	B.padBeams = B.padBeams or {}
	local safe = dropPads(B, now)
	for idx, rec in pairs(w.pads) do
		local boing = rec.boingAt and clamp(1 - (now - rec.boingAt) / 0.45, 0, 1) or 0
		local bob = (awake and 0.35 * pulse or 0) + 1.6 * boing * boing
		for _, pr in ipairs(rec.parts) do
			if pr.name == "PadArrow" then
				pr.part.CFrame = CFrame.new(0, bob, 0) * pr.cf
			elseif pr.name == "PadPlate" then
				local col = pr.color
				if safe then
					col = GREEN:Lerp(WHITE, 0.55 * (1 - ((ph * 2) % 1)) ^ 2) -- (STAND HERE!)
				end
				if boing > 0.6 then
					col = WHITE
				end
				pr.part.Color = col
			end
		end
		-- (and a green beam of light over each while the drop is on)
		local beam = B.padBeams[idx]
		if safe then
			if not beam then
				beam = newPart("PadBeam", nil, GREEN, Enum.Material.Neon, 1, B.body.folder)
				B.padBeams[idx] = beam
			end
			beam.Size = V3(5.6, 30, 5.6)
			beam.CFrame = CFrame.new(rec.center + V3(0, 15, 0)) * CFrame.Angles(0, now * 2, 0)
			beam.Transparency = 0.82 - 0.1 * (1 - ((ph * 2) % 1)) ^ 2
		elseif beam then
			beam.Transparency = 1
		end
	end
	-- THE WORLD ROUND THE GRID: upside down while he is (turning over in about
	-- a second)
	local want = (B.gravShown == -1) and math.pi or 0
	if w.want ~= want then
		w.from, w.want, w.turnAt = w.ang, want, now
	end
	local turning = false
	if w.turnAt then
		local u = clamp((now - w.turnAt) / 1.2, 0, 1)
		w.ang = lerp(w.from, w.want, smooth(u))
		turning = u < 1
		if not turning then
			w.turnAt = nil
		end
	end
	local W = w.pivot * CFrame.Angles(w.ang, 0, 0) * w.pivot:Inverse()
	if turning or w.drawnAng ~= w.ang then
		for _, s in ipairs(w.still) do
			s.part.CFrame = W * s.cf
		end
		w.drawnAng = w.ang
	end
	-- the saws spin, the frames turn
	local spin = now * (B.phase2Look and 2.4 or 1.4)
	for i, saw in ipairs(w.saws) do
		local hub = W * saw.hub * CFrame.Angles(spin * ((i % 2 == 0) and 1 or -1), 0, 0)
		for _, pr in ipairs(saw.parts) do
			pr.part.CFrame = hub * pr.rel
		end
	end
	for i, fr in ipairs(w.frames) do
		local hub = W * fr.hub * CFrame.Angles(0, 0, now * 0.35 * ((i % 2 == 0) and 1 or -1))
		for _, pr in ipairs(fr.parts) do
			pr.part.CFrame = hub * pr.rel
		end
	end
	-- the floating blocks' glow: half on one beat, half on the next
	for i, g in ipairs(w.glows) do
		local on = awake and ((bk + i) % 2 == 0)
		g.part.Transparency = on and lerp(g.tr, 0.5, pulse) or g.tr
	end
end

-- the level back as it was built (the world the right way up, the pads yellow)
local function calmWorld(B)
	local w = B.world
	if not w then
		return
	end
	w.ang, w.want, w.turnAt, w.from = 0, 0, nil, nil
	for _, s in ipairs(w.still) do
		s.part.CFrame = s.cf
	end
	w.drawnAng = 0
	for _, rec in pairs(w.pads) do
		rec.boingAt = nil
		for _, pr in ipairs(rec.parts) do
			pr.part.CFrame = pr.cf
			pr.part.Color = pr.color
		end
	end
	for _, beam in pairs(B.padBeams or {}) do
		beam.Transparency = 1
	end
	if w.under then
		w.under.Color = w.underColor
	end
end

----------------------------------------------------------------------
-- Warnings and effects in the level
----------------------------------------------------------------------
-- a landing that shakes the level: shock rings, dust, a thud
local function slamFx(B, spot, radius, loud)
	local s = V3(spot.X, floorY(B), spot.Z)
	shockRing(B, s, 3, radius + 3, 0.45, HOT)
	shockRing(B, s, 2, radius * 0.6, 0.3, WHITE)
	burst(s + V3(0, 1, 0), PURPLE, 22, 22, 2, 0.6)
	burst(s + V3(0, 0.5, 0), B.def.Color or HOT, 12, 18, 1.2, 0.5)
	sfx(B, "Slam", loud or 1)
	kick(s, radius, 0.9 * (loud or 1), -3)
end

-- A PORTAL: a tall oval ring of light in the new form's colour, standing
-- across his path. It grows in, flashes as he flies through, shrinks away.
local function portalRing(B, center, dir, color, tIn, tMid, tOut)
	local N = 18
	local segs = {}
	for i = 1, N do
		segs[i] = newPart("PortalPiece", nil, color, Enum.Material.Neon, 1)
	end
	local pane = newPart("PortalGlow", nil, color, Enum.Material.Neon, 1)
	local face = CFrame.lookAt(center, center + unitOr(flat(dir), V3(0, 0, 1)))
	local id = B.seenId
	addTelegraph(B, {
		update = function(now)
			if now >= tOut + 0.35 or B.seenId ~= id then
				return false
			end
			local s = easeOutBack((now - tIn) / 0.3) * (1 - clamp((now - tOut) / 0.35, 0, 1))
			local hot = now >= tMid and now < tMid + 0.15
			if s <= 0.02 then
				for _, p in ipairs(segs) do
					p.Transparency = 1
				end
				pane.Transparency = 1
				return true
			end
			for i, p in ipairs(segs) do
				local a = (i - 0.5) / N * math.pi * 2
				local pos = face * V3(math.sin(a) * 5.5 * s, math.cos(a) * 8.5 * s, 0)
				local along = face:VectorToWorldSpace(V3(5.5 * math.cos(a), -8.5 * math.sin(a), 0))
				p.Size = V3(1.3 * s, 1.3 * s, 3.0 * s)
				p.CFrame = CFrame.lookAt(pos, pos + along, face.LookVector)
				p.Transparency = 0
				p.Color = hot and WHITE or color
			end
			pane.Size = V3(9 * s, 15 * s, 0.2)
			pane.CFrame = face
			pane.Transparency = hot and 0.4 or 0.82
			return true
		end,
		cleanup = function()
			for _, p in ipairs(segs) do
				p:Destroy()
			end
			pane:Destroy()
		end,
	})
end

-- A GRAVITY PORTAL: a flat ring halfway up, round the way he'll fall (yellow:
-- up to the ceiling; blue: back down); it flashes as he falls through it
local function gravityRing(B, spot, color, tIn, tFlip, tOut)
	local ring = newRing(20, color, Enum.Material.Neon, 1)
	local glow = newPart("GravityGlow", Enum.PartType.Cylinder, color, Enum.Material.Neon, 1)
	local id = B.seenId
	local c = V3(spot.X, floorY(B) + (B.ceiling or B.def.Ceiling or 44) / 2, spot.Z)
	addTelegraph(B, {
		update = function(now)
			if now >= tOut or B.seenId ~= id then
				return false
			end
			local s = easeOutBack((now - tIn) / 0.3) * (1 - clamp((now - (tOut - 0.3)) / 0.3, 0, 1))
			if s <= 0.02 then
				placeRing(ring, c, 0.5, 0.1, 0.1, 1)
				glow.Transparency = 1
				return true
			end
			placeRing(ring, c, 8 * s, 0.8, 1.0, 0.05)
			placeDisc(glow, c + V3(0, 0.4, 0), 15 * s, 0.2)
			glow.Transparency = (now >= tFlip and now < tFlip + 0.2) and 0.35 or 0.8
			return true
		end,
		cleanup = function()
			removeRing(ring)
			glow:Destroy()
		end,
	})
end

-- THE UFO'S CIRCLE: under him (pale, pulsing on the beat) while he bursts
-- after you; then locked where he'll land (red, filling in) until the slam
local function slamCircle(B, radius, tLock, tHit)
	local ring = newRing(28, RED, Enum.Material.Neon, 1)
	local disc = newPart("SlamFill", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local id = B.seenId
	addTelegraph(B, {
		update = function(now)
			if now >= tHit + 0.05 or B.seenId ~= id then
				return false
			end
			local locked = (now >= tLock) and slot(B, 1) or nil
			local c = locked or B.here3 or B.vpos
			c = V3(c.X, floorY(B) + 0.1, c.Z)
			local pulse = (1 - beatNow(B, now)) ^ 3
			placeRing(ring, c, radius, 0.35, 0.8, locked and 0.05 or (0.6 - 0.3 * pulse))
			for _, p in ipairs(ring.parts) do
				p.Color = locked and HOT or RED
			end
			local k = locked and clamp((now - tLock) / math.max(tHit - tLock, 0.05), 0, 1) or 0
			placeDisc(disc, c + V3(0, 0.03, 0), math.max(radius * 2 * k, 0.1), 0.12)
			disc.Transparency = locked and 0.5 or 1
			return true
		end,
		cleanup = function()
			removeRing(ring)
			disc:Destroy()
		end,
	})
end

-- THE SWOOP'S LANE: red on the tiles from where he dives to where he stops,
-- as wide as the server's (Width). Pale and pulsing while it aims; it locks
-- (slot 3) with two white flashes and arrows march down it; as he dives,
-- it's gone behind him.
local function swoopLane(B, a, tLock, tDive, tEnd)
	local strip = newPart("SwoopLane", nil, RED, Enum.Material.Neon, 1)
	local rims = { newPart("SwoopRim", nil, HOT, Enum.Material.Neon, 1), newPart("SwoopRim", nil, HOT, Enum.Material.Neon, 1) }
	local arrows = {}
	for i = 1, 8 do
		arrows[i] = newPart("SwoopArrow", nil, WHITE, Enum.Material.Neon, 1)
	end
	local all = { strip, rims[1], rims[2] }
	for _, p in ipairs(arrows) do
		table.insert(all, p)
	end
	local id = B.seenId
	addTelegraph(B, {
		update = function(now)
			if now >= tEnd or B.seenId ~= id then
				return false
			end
			local p0, p1 = slot(B, 1), slot(B, 2)
			local fy = floorY(B)
			local from = p0 and V3(p0.X, fy, p0.Z) or nil
			local to = p1 and V3(p1.X, fy, p1.Z) or nil
			local dir = (from and to) and unitOr(flat(to - from), V3(0, 0, 1)) or V3(0, 0, 1)
			if from and to and now >= tDive and B.here3 then
				local along = clamp(flat(B.here3 - from):Dot(dir), 0, flat(to - from).Magnitude)
				from = from + dir * along
			end
			local len = (from and to) and flat(to - from).Magnitude or 0
			if len < 0.5 then
				for _, p in ipairs(all) do
					p.Transparency = 1
				end
				return true
			end
			local locked = (B.model:GetAttribute("ActK") or 0) >= 3
			local right = rightOf(dir)
			local w = a.Width
			local mid = (from + to) / 2 + V3(0, 0.08, 0)
			strip.Size = V3(w, 0.1, len)
			strip.CFrame = CFrame.lookAt(mid, mid + dir)
			local pulse = (1 - beatNow(B, now)) ^ 3
			local since = now - tLock
			local flashing = locked and since >= 0 and since < 0.36 and (since % 0.18) < 0.09
			strip.Transparency = locked and (flashing and 0.1 or 0.45) or (0.75 - 0.2 * pulse)
			strip.Color = flashing and WHITE or RED
			for i, rim in ipairs(rims) do
				local s = (i == 1) and -1 or 1
				local rm = mid + right * (s * (w / 2 - 0.2)) + V3(0, 0.03, 0)
				rim.Size = V3(0.4, 0.14, len)
				rim.CFrame = CFrame.lookAt(rm, rm + dir)
				rim.Transparency = locked and 0 or 0.5
			end
			for i = 1, 4 do
				local pair = { arrows[i * 2 - 1], arrows[i * 2] }
				if locked then
					local u = ((i - 1) / 4 + math.max(since, 0) * 1.2) % 1
					local c = from + dir * (u * len) + V3(0, 0.12, 0)
					for j, bar in ipairs(pair) do
						local s = (j == 1) and -1 or 1
						bar.Size = V3(0.5, 0.1, 2.4)
						bar.CFrame = CFrame.lookAt(c, c + dir) * CFrame.new(s * 0.8, 0, 0) * CFrame.Angles(0, s * 0.7, 0)
						bar.Transparency = 0.1
					end
				else
					pair[1].Transparency, pair[2].Transparency = 1, 1
				end
			end
			return true
		end,
		cleanup = function()
			for _, p in ipairs(all) do
				p:Destroy()
			end
		end,
	})
end

-- WHERE HE'LL DROP (the ceiling drop): a red line of light from the ceiling
-- down onto the locked square, flashing faster and faster until he lands
local function dropLine(B, spot, tLand)
	local line = newPart("DropLine", nil, HOT, Enum.Material.Neon, 1)
	local id = B.seenId
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			if now >= tLand or B.seenId ~= id then
				return false
			end
			local fy = floorY(B)
			local top = fy + (B.ceiling or B.def.Ceiling or 44)
			line.Size = V3(0.6, top - fy, 0.6)
			line.CFrame = CFrame.new(V3(spot.X, (fy + top) / 2, spot.Z))
			local u = clamp((now - t0) / math.max(tLand - t0, 0.05), 0, 1)
			line.Transparency = ((now * lerp(4, 14, u)) % 1 < 0.5) and 0.2 or 0.6
			return true
		end,
		cleanup = function()
			line:Destroy()
		end,
	})
end

-- LEVEL COMPLETE: little neon cubes flying out of him, bouncing on the tiles
local function littleCubes(B, from, n)
	local parts, t0 = {}, serverNow()
	local cols = { B.def.Color or HOT, YELLOW, WHITE, CYAN, B.def.Color or HOT }
	local fy = floorY(B)
	for i = 1, n do
		local s = 0.6 + ((i * 7) % 5) * 0.2
		local p = newPart("LittleCube", nil, cols[i % #cols + 1], Enum.Material.Neon, 0)
		p.Size = V3(s, s, s)
		local a = i * 2.39996
		local sp = 14 + (i % 4) * 5
		parts[i] = { part = p, s = s, vel = V3(math.sin(a) * sp, 16 + ((i * 3) % 7) * 3, math.cos(a) * sp), spin = V3(i % 3 + 1, i % 5 - 2, 2) }
	end
	addTelegraph(B, {
		update = function(now)
			local tau = now - t0
			if tau > 2.4 then
				return false
			end
			for _, q in ipairs(parts) do
				local pos = from + q.vel * tau + V3(0, -22.5 * tau * tau, 0)
				pos = V3(pos.X, math.max(pos.Y, fy + q.s / 2), pos.Z)
				q.part.CFrame = CFrame.new(pos) * CFrame.Angles(q.spin.X * tau * 3, q.spin.Y * tau * 3, q.spin.Z * tau * 3)
				q.part.Transparency = clamp((tau - 1.3) / 1.0, 0, 1)
			end
			return true
		end,
		cleanup = function()
			for _, q in ipairs(parts) do
				q.part:Destroy()
			end
		end,
	})
end

-- ATTEMPT N, written in the level itself (over the end of the runway, facing
-- you as you arrive), fading away after a while
local function attemptSign(B, n, t0)
	if not B.here then
		return
	end
	local g = gridOf(B)
	local c = g.center
	local pos = V3(c.X, floorY(B) + 12, c.Z + g.size * g.n / 2 - 6)
	local board = newPart("AttemptSign", nil, INK, Enum.Material.SmoothPlastic, 1, B.body.folder)
	board.Size = V3(36, 7, 0.2)
	board.CFrame = CFrame.lookAt(pos, pos + V3(0, 0, 1))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AttemptText"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(36 * 30, 7 * 30)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "ATTEMPT " .. n
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = INK
	label.Parent = gui
	gui.Parent = board
	addTelegraph(B, {
		update = function(now)
			if B.action == "Reset" or B.action == "Dormant" or now > t0 + 16 then
				return false
			end
			local k = clamp((now - (t0 + 12)) / 4, 0, 1)
			label.TextTransparency = k
			label.TextStrokeTransparency = k
			return true
		end,
		cleanup = function()
			board:Destroy()
		end,
	})
end

----------------------------------------------------------------------
-- The shape of each move over time
----------------------------------------------------------------------
-- (his usual look - a grin, eyes on you, his neon flaring on every beat -
-- is set for every move before its own shape: see Body.runPose)
function Poses.Idle(B, t, P)
	local _ = B
	local _ = t
	local _ = P
end

-- ASLEEP in the middle of the grid: dim, eyes shut, breathing with the beat
-- (a breath every two beats). Walk near and one eye opens a crack...
function Poses.Dormant(B, t, P)
	local now = serverNow()
	local len = BeatGrid.beatLen(bpm(B))
	local breathe = math.sin(now * math.pi / len)
	P.sy, P.sx = 1 + 0.03 * breathe, 1 - 0.015 * breathe
	P.sz = P.sx
	P.eyes, P.mouth, P.glow, P.anger = 0.05, "shut", 0.18 + 0.08 * breathe, 0.2
	P.noBeat = true
	local root = myRoot()
	if root and B.here3 and flat(root.Position - B.here3).Magnitude < (B.def.WakeRange or 40) + 25 then
		P.eyeR = 0.35 -- (he's seen you)
		P.glow += 0.1
	end
	local _ = t
end

-- THE LEVEL STARTS (ATTEMPT N): the grid lights up from the middle, a ring a
-- beat; on beat 4 his eyes snap open and he ROARS, then he bounces on the
-- beat, grinning, and on beat 8 hops up with a flip - ready
function Poses.Wake(B, t, P)
	local now = serverNow()
	local len = BeatGrid.beatLen(bpm(B))
	local b = (now - beat0(B)) / len
	P.noBeat = true
	if b < 4 then
		P.eyes, P.mouth, P.anger = 0.05, "shut", 0.3
		P.glow = 0.2 + 0.12 * math.max(b, 0)
		P.shake = (b > 3) and 0.15 * (b - 3) or 0
	elseif b < 5 then
		local w = spring((b - 4) * len, 5, 14)
		P.eyes, P.mouth, P.anger, P.glow = 1, "open", 1, 1.3
		P.sy, P.sx = 1 + 0.25 * w, 1 - 0.15 * w
		P.sz = P.sx
	elseif b < 8 then
		local ph = b % 1
		local k = (1 - ph) ^ 3
		P.sy, P.sx = 1 - 0.12 * k, 1 + 0.08 * k
		P.sz = P.sx
		P.mouth = (ph < 0.25) and "open" or "grin"
		P.glow = 0.9 + 0.3 * k
	elseif b < 9 then
		local v = b - 8
		P.lift = 9 * 4 * v * (1 - v)
		P.flip = 2 * math.pi * v
		P.mouth, P.glow = "open", 1.1
	else
		local w = spring((b - 9) * len, 6, 16)
		P.sy, P.sx = 1 - 0.3 * w, 1 + 0.2 * w
		P.sz = P.sx
	end
	local _ = t
end

-- EVERYONE'S GONE: he laughs at you (bouncing, mouth wide) and vanishes
function Poses.Reset(B, t, P)
	local k = (1 - ((t * 5) % 1)) ^ 2
	P.sy, P.sx = 1 - 0.1 * k, 1 + 0.06 * k
	P.sz = P.sx
	P.mouth, P.eyeL, P.eyeR, P.anger = "open", 0.3, 0.3, 0
	P.fade = clamp((t - 1.3) / 0.5, 0, 1)
	P.noBeat = true
	local _ = B
end

-- GRAVITY FLIP! (half health): knocked about, glitching... then he falls UP
-- to the ceiling, blazing
function Poses.Break(B, t, P)
	local hit = B.def.BreakTime * 0.35
	P.noBeat = true
	if t < hit then
		P.shake = 0.35
		P.mouth, P.eyes, P.anger = "o", 1, 0.2
		P.glow = (math.floor(t * 16) % 2 == 0) and 1.4 or 0.4
		P.sy = P.sy + 0.08 * math.sin(t * 40)
	else
		local w = spring(t - hit, 4, 12)
		P.mouth, P.anger, P.glow = "grin", 1, 1.25
		P.sy, P.sx = 1 + 0.2 * w, 1 - 0.12 * w
		P.sz = P.sx
	end
end

-- LEVEL COMPLETE: he freezes, glitching, X-eyed... and shatters (see
-- applyPose)
function Poses.Death(B, t, P)
	P.noBeat, P.noHop = true, true
	P.dizzy, P.mouth = 1, "o"
	P.shake = (t < 0.6) and 0.35 or 0
	P.glow = (math.floor(t * 14) % 2 == 0) and 1.5 or 0.5
	local _ = B
end

-- HOP SLAM: crouching, grinning, as his square lights up; a huge hop
-- (spinning, like every cube should); SLAM
function Poses.HopSlam(B, t, P)
	local a = B.def.Attacks.HopSlam
	local now = serverNow()
	local tTake = actBeat(B, a.Tell - 1)
	if now < tTake then
		local k = smooth((now - B.actionStart) / math.max(tTake - B.actionStart, 0.05))
		P.sy, P.sx = 1 - 0.26 * k, 1 + 0.15 * k
		P.sz = P.sx
		P.eyes, P.anger, P.glow = 1 - 0.35 * k, 1, 0.8 + 0.3 * k
		P.shake = 0.1 * k
	elseif now < actBeat(B, a.Tell) then
		P.mouth, P.anger = "open", 1
	end
	local _ = t
end

-- SPIKE ROWS: a little hop onto his tile, a stomp - then he stomps every beat
-- as the rows of spikes march out from him
function Poses.SpikeRows(B, t, P)
	local a = B.def.Attacks.SpikeRows
	local now = serverNow()
	local tStomp = actBeat(B, a.Tell)
	local tDone = actBeat(B, a.Tell + a.Rows - 1)
	if now < actBeat(B, a.Tell - 1) then
		P.sy, P.sx = 0.9, 1.06
		P.sz = P.sx
		P.anger = 1
	elseif now >= tStomp and now < tDone + 0.3 then
		local ph = beatNow(B, now)
		local k = (1 - ph) ^ 2
		P.sy, P.sx = 1 - 0.2 * k, 1 + 0.13 * k
		P.sz = P.sx
		P.mouth = (ph < 0.3) and "open" or "grin"
		P.anger, P.glow = 1, 0.9 + 0.4 * k
		P.noBeat = true
	elseif now >= tDone + 0.3 then
		P.eyes = 0.7
	end
	local _ = t
end

-- STOMP CHAIN (round 2): three hop slams, one a beat - mouth wide
function Poses.StompChain(B, t, P)
	local a = B.def.Attacks.StompChain
	if serverNow() < actBeat(B, a.Hops) then
		P.mouth, P.anger, P.glow = "open", 1, 1.1
	end
	local _ = t
end

-- CEILING DROP (round 2, upside down): hopping along the ceiling after you; a
-- glint as it locks; he drops (stretched)... head first into the tiles.
-- STUCK: X eyes, stars - then he falls back up.
function Poses.CeilingDrop(B, t, P)
	local a = B.def.Attacks.CeilingDrop
	local now = serverNow()
	local tLock, tFall, tLand = actBeat(B, a.Lock), actBeat(B, a.Tell - 0.5), actBeat(B, a.Tell)
	B.stuckNow = false
	if now < tLock then
		P.anger = 0.8
	elseif now < tFall then
		P.anger, P.glow, P.eyes, P.shake = 1, 1.2, 0.6, 0.1
	elseif now < tLand then
		P.sy, P.sx = 1.25, 0.88
		P.sz = P.sx
		P.mouth = "open"
	else
		local m = B.move
		local rising = m and m.kind == "Fall" and m.b.Y > 1 and now >= m.t0
		P.anchorHead = true
		if not rising then
			B.stuckNow = true
			P.dizzy, P.mouth, P.glow = 1, "o", 0.35
			P.tilt = 0.08 * math.sin(now * 5)
			P.noBeat = true
		end
	end
	local _ = t
end

-- BOMB RUN (ship): turning along the lane, the flame building... then off
-- down it, a bomb a beat
function Poses.BombRun(B, t, P)
	local a = B.def.Attacks.BombRun
	local now = serverNow()
	local tGo = actBeat(B, a.Tell - 1)
	if now < tGo then
		local k = clamp((now - B.actionStart) / math.max(tGo - B.actionStart, 0.05), 0, 1)
		P.flame, P.pitch, P.anger, P.shake = 0.3 + 0.5 * k, -0.08 * k, 1, 0.06 * k
	elseif B.move and B.move.kind == "Fly" and now < B.move.t1 then
		P.flame, P.mouth, P.anger = 1, "open", 1
	end
	local _ = t
end

-- SWOOP (ship): rearing back as the lane aims, eyes flashing as it locks;
-- nose down, flame roaring, down the lane; skimming the tiles ("whoa!") -
-- your chance - then climbing away
function Poses.Swoop(B, t, P)
	local a = B.def.Attacks.Swoop
	local now = serverNow()
	local tLock, tDive = actBeat(B, a.Tell - a.Lock), actBeat(B, a.Tell)
	local tSkim, tClimb = actBeat(B, a.Tell + 1), actBeat(B, a.Tell + 1 + a.Skim)
	if now < tDive then
		local k = clamp((now - B.actionStart) / math.max(tDive - B.actionStart, 0.05), 0, 1)
		P.pitch, P.flame, P.anger = 0.3 * smooth(k), 0.2 + 0.6 * k, 1
		if now >= tLock then
			P.glow, P.eyes = 1.3, 0.6
		end
	elseif now < tSkim then
		P.pitch, P.flame, P.mouth, P.anger = -0.1, 1, "open", 1
	elseif now < tClimb then
		P.flame, P.mouth, P.anger = 0.15, "o", 0
	else
		P.flame = 0.8
	end
	local _ = t
end

-- UFO SLAM: bursting up after you (the circle under him follows you); every
-- light on and the tractor beam down as it locks... SLAM - and he's stuck on
-- the tiles, lopsided, lights flickering, dizzy
function Poses.UfoSlam(B, t, P)
	local a = B.def.Attacks.UfoSlam
	local now = serverNow()
	local tLock, tFall, tLand = actBeat(B, a.Lock), actBeat(B, a.Tell - 0.5), actBeat(B, a.Tell)
	B.stuckNow = false
	if now < tLock then
		P.anger = 0.9
	elseif now < tFall then
		P.beam = clamp((now - tLock) / 0.15, 0, 1)
		P.lightsAll = true
		P.anger, P.glow = 1, 1.2
	elseif now < tLand then
		P.beam = 1 - clamp((now - tFall) / 0.1, 0, 1)
		P.mouth = "open"
	else
		local m = B.move
		local rising = m and m.kind == "Fly" and now >= m.t0 and m.t0 > tLand + 0.05
		if not rising then
			B.stuckNow = true
			P.dizzy, P.mouth, P.glow = 1, "o", 0.35
			P.tilt = 0.22 + 0.04 * math.sin(now * 6)
			P.noBeat = true
		end
	end
	local _ = t
end

-- ORB RAIN (UFO): bobbing on the beat, orbs dropping out of his belly onto
-- the lit tiles
function Poses.OrbRain(B, t, P)
	P.anger, P.glow = 0.8, 1
	local _ = B
	local _ = t
end

-- ZIG-ZAG (wave): crouched, eyes narrowed, as the dotted path shows; then he
-- ZOOMS along it, mouth wide
function Poses.ZigZag(B, t, P)
	local a = B.def.Attacks.ZigZag
	local now = serverNow()
	if now < actBeat(B, a.Tell) then
		P.sy, P.sx = 0.85, 1.08
		P.sz = P.sx
		P.eyes, P.anger, P.shake = 0.6, 1, 0.05
	elseif now < actBeat(B, a.Tell + a.Legs) then
		P.mouth, P.anger, P.glow = "open", 1, 1.2
	end
	local _ = t
end

-- TILE PATTERN: the level itself - he dances on the spot, swaying to the beat
function Poses.TilePattern(B, t, P)
	local ph, bk = beatNow(B, serverNow())
	P.tilt = 0.12 * math.sin(math.pi * (bk + ph))
	P.mouth = (ph < 0.3) and "open" or "grin"
	P.glow = 1
	local _ = t
end

-- THE DROP: rising to the middle as the music builds - shaking harder and
-- glowing hotter every beat - a ROAR as everything spikes, then CRASH
function Poses.Drop(B, t, P)
	local d = B.def.Drop
	local now = serverNow()
	local tHit = actBeat(B, d.Build)
	if now < tHit then
		local k = clamp((now - B.actionStart) / math.max(tHit - B.actionStart, 0.05), 0, 1)
		P.glow, P.shake, P.anger = 0.9 + 0.6 * k, 0.05 + 0.25 * k, 1
	else
		P.glow, P.mouth, P.anger = 1.5, "open", 1
		if B.move and B.move.kind == "Fall" and now < B.move.t1 then
			P.sy, P.sx = 1.2, 0.9
			P.sz = P.sx
		end
	end
	P.flame = 0.6
	local _ = t
end

-- STUNNED after the drop: squashed, X-eyed, stars round his head, swaying -
-- free hits!
function Poses.Stunned(B, t, P)
	local now = serverNow()
	local m = B.move
	if m and m.kind == "Fly" and now >= m.t0 and m.t0 > (B.actionStart or 0) + 0.2 then
		return -- (up and away again)
	end
	P.dizzy, P.mouth, P.glow, P.anger = 1, "shut", 0.3, 0
	P.sy, P.sx = 0.88, 1.06
	P.sz = P.sx
	P.tilt = 0.12 * math.sin(now * 3)
	P.lean = 0.05 * math.sin(now * 2.3)
	P.noBeat = true
	P.flame = 0
	local _ = t
end

-- A PORTAL: flying through it; halfway, POP - a new form
function Poses.Portal(B, t, P)
	P.mouth, P.anger, P.glow = "grin", 0.7, 1.1
	local _ = B
	local _ = t
end

-- A GRAVITY FLIP: crouched and glowing over the gravity portal... then he
-- falls up to the ceiling (or back down to the tiles, landing with a slam)
function Poses.Flip(B, t, P)
	local now = serverNow()
	local tGo = actBeat(B, 0)
	if now < tGo then
		local k = clamp((now - B.actionStart) / math.max(tGo - B.actionStart, 0.05), 0, 1)
		P.sy, P.sx = 1 - 0.15 * k, 1 + 0.08 * k
		P.sz = P.sx
		P.glow, P.anger = 1 + 0.3 * k, 1
	else
		P.mouth = "open"
	end
	local _ = t
end

-- THE CUBE'S HOPS (any move made of hops): a full flip in the air on every
-- long hop, stretched as he leaves the tiles; and (any form) squashed as he
-- lands - harder the higher he came from
local function hopShape(B, now, P)
	if P.noHop then
		return
	end
	local m = B.move
	if m and (m.kind == "Hop" or m.kind == "Fall") and now >= m.t0 then
		local n = math.max(1, math.floor(m.n or 1))
		local span = math.max(m.t1 - m.t0, 1e-3)
		local u = clamp((now - m.t0) / span, 0, 1)
		if m.kind == "Hop" then
			local x = u * n
			local j = math.min(math.floor(x), n - 1)
			local v = x - j
			if now < m.t1 and B.formShown == "Cube" then
				local dist = flat(m.b - m.a).Magnitude / n
				if dist > 5 and math.abs(m.h or 0) >= 3 then
					P.flip = (P.flip or 0) + 2 * math.pi * v
				end
				if v < 0.3 then
					local s = 0.2 * (1 - v / 0.3)
					P.sy += s
					P.sx -= s * 0.5
					P.sz -= s * 0.5
				end
			end
			if j >= 1 or now >= m.t1 then
				local land = m.t0 + span * ((now >= m.t1) and n or j) / n
				if not B.landAt or land > B.landAt then
					B.landAt, B.landHard = land, clamp(math.abs(m.h or 0) / 12, 0.3, 1)
				end
			end
		elseif now >= m.t1 and (not B.landAt or m.t1 > B.landAt) then
			B.landAt, B.landHard = m.t1, 1
		end
	end
	if B.landAt and now >= B.landAt and now - B.landAt < 0.8 then
		local w = spring(now - B.landAt, 7, 16) * (B.landHard or 0.5)
		P.sy -= 0.32 * w
		P.sx += 0.22 * w
		P.sz += 0.22 * w
	end
end

-- what a new move sets off: the UFO's bursts, the cube's landings, the wave's
-- zoom, the ship's thrust (and a hop that was cut short still lands)
function onMove(B, m, old, now)
	if old and (old.kind == "Hop" or old.kind == "Fall") and old.t1 <= now + 0.05 and old.t1 > (B.landAt or -math.huge) then
		B.landAt = old.t1
		B.landHard = (old.kind == "Fall") and 1 or clamp(math.abs(old.h or 0) / 12, 0.3, 1)
	end
	if not B.here then
		return
	end
	local form = B.formShown or B.model:GetAttribute("Form") or "Cube"
	local n = math.max(1, math.floor(m.n or 1))
	local span = m.t1 - m.t0
	if m.kind == "Hop" and form == "Ufo" and (m.h or 0) >= 2.5 then
		for k = 0, n - 1 do
			local when = m.t0 + span * k / n
			if when >= now - 0.1 then
				at(B, when, function()
					sfx(B, "Burst", 0.5)
					burst((B.center3 or B.vpos) - V3(0, 2, 0), ORANGE, 8, 10, 1.0, 0.35)
				end)
			end
		end
	elseif m.kind == "Hop" and form == "Cube" and math.abs(m.h or 0) >= 3 then
		for k = 1, n do
			at(B, m.t0 + span * k / n, function()
				local c = B.here3 or B.vpos
				local y = (B.gravShown == -1) and (floorY(B) + (B.ceiling or 44) - 0.5) or (floorY(B) + 0.5)
				burst(V3(c.X, y, c.Z), PURPLE, 8, 10, 1.4, 0.4)
			end)
		end
	elseif m.kind == "Zig" and form == "Wave" and B.action ~= "ZigZag" then
		at(B, m.t0, function()
			sfx(B, "Zoom", 0.45)
		end)
	elseif m.kind == "Fly" and form == "Ship" and span > 0.3 and flat(m.b - m.a).Magnitude > 20 and B.action ~= "BombRun" and B.action ~= "Swoop" then
		at(B, m.t0, function()
			sfx(B, "Ship", 0.4)
		end)
	end
end

----------------------------------------------------------------------
-- One-off moments in each move (sounds, shouts, bursts, warnings)
----------------------------------------------------------------------
function Starts.Idle(B, t0)
	local _ = B
	local _ = t0
end

-- (home again after vanishing: a puff of magenta)
function Starts.Dormant(B, t0)
	if B.prevAction == "Reset" then
		at(B, t0 + 0.05, function()
			burst((B.center3 or B.vpos) + V3(0, 1, 0), MAGENTA, 24, 12, 2.4, 0.8)
		end)
	end
end

-- THE LEVEL STARTS: ATTEMPT N (big across your screen, and written in the
-- level), the grid lighting up from the middle a ring a beat, his roar on
-- beat 4 and his landing on beat 9
function Starts.Wake(B, t0)
	local def = B.def
	if B.here then
		attempts += 1
	end
	local n = math.max(attempts, 1)
	B.attemptN = n
	local len = BeatGrid.beatLen(bpm(B))
	at(B, t0 + 0.05, function()
		sfx(B, "Attempt", 1)
		banner(B, "ATTEMPT " .. n, { color = WHITE, size = 90, hold = 1.6 })
	end)
	attemptSign(B, n, t0)
	if B.here then
		for c = 0, 7 do
			glowRing(B, c, beatTime(B, c), len * 0.9, (c % 2 == 0) and CYAN or MAGENTA)
		end
	end
	at(B, beatTime(B, 4) - (def.WakeSoundLead or 0.2), function()
		sfx(B, "Wake", 1)
	end)
	at(B, beatTime(B, 4), function()
		local c = B.center3 or B.vpos
		burst(c, def.Color or HOT, 26, 22, 1.8, 0.8, true)
		kick(c, 40, 0.8, -3)
		yell(B, "FEEL THE BEAT!", 1.4, HOT)
	end)
	at(B, beatTime(B, 9), function()
		slamFx(B, B.here3 or B.vpos, 6, 0.6)
	end)
end

-- EVERYONE'S GONE: he laughs, and vanishes in a puff
function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		yell(B, "HA HA HA!", 1.1, MAGENTA)
	end)
	at(B, t0 + 1.5, function()
		burst((B.center3 or B.vpos) + V3(0, 1, 0), MAGENTA, 24, 12, 2.4, 0.8)
	end)
end

-- GRAVITY FLIP! (half health): knocked about and glitching, then the level
-- turns upside down and he falls up to the ceiling
function Starts.Break(B, t0)
	local def = B.def
	local hit = t0 + def.BreakTime * 0.35
	at(B, t0 + 0.02, function()
		burst(B.center3 or B.vpos, def.Color or HOT, 20, 16, 1.4, 0.6)
		sfx(B, "Stun", 0.6)
	end)
	at(B, hit - 0.25, function()
		sfx(B, "Flip", 1)
	end)
	at(B, hit, function()
		B.phase2Look = true
		local c = B.here3 or B.vpos
		shockRing(B, c, 3, def.BreakReach, 0.55, CYAN)
		shockRing(B, c, 2, def.BreakReach * 0.6, 0.4, WHITE)
		burst((B.center3 or c) + V3(0, 2, 0), CYAN, 30, 26, 1.6, 0.8, true)
		sfx(B, "Break", 1)
		kick(c, def.BreakReach, 1.3, -6)
		banner(B, "GRAVITY FLIP!", { color = CYAN, sub = "THE LEVEL IS UPSIDE DOWN", subColor = YELLOW, size = 90, hold = 1.6 })
		yell(B, "UPSIDE DOWN!", 1.2, CYAN)
		B.flashWorldAt, B.flashColor = hit, CYAN
		if B.here then
			-- (the grid flashes from its edges in)
			for c2 = 7, 0, -1 do
				glowRing(B, c2, hit + (7 - c2) * 0.05, 0.4, CYAN)
			end
		end
	end)
end

-- LEVEL COMPLETE!: he glitches, X-eyed... shatters into little cubes; the
-- grid lights up green from the middle out
function Starts.Death(B, t0)
	B.shatterAt = t0 + 0.6
	local n = B.attemptN or math.max(attempts, 1)
	at(B, t0 + 0.05, function()
		sfx(B, "Stun", 0.8)
	end)
	at(B, t0 + 0.6, function()
		local c = B.center3 or B.vpos
		sfx(B, "Death", 1)
		burst(c, B.def.Color or HOT, 40, 30, 1.6, 1.0, true)
		burst(c, YELLOW, 24, 24, 1.2, 0.8, true)
		kick(c, 50, 1.0, -4)
		littleCubes(B, c, 26)
	end)
	at(B, t0 + 1.1, function()
		sfx(B, "Complete", 1)
		banner(B, "LEVEL COMPLETE!", { color = YELLOW, sub = "ATTEMPTS: " .. n, subColor = WHITE, size = 84, hold = 3 })
		B.flashWorldAt, B.flashColor = serverNow(), GREEN
		if B.here then
			for c = 0, 7 do
				glowRing(B, c, serverNow() + c * 0.09, 0.6, (c % 2 == 0) and GREEN or YELLOW)
			end
		end
	end)
end

-- HOP SLAM: the hop, and the slam on his square
function Starts.HopSlam(B, t0)
	local a = B.def.Attacks.HopSlam
	at(B, actBeat(B, a.Tell - 1), function()
		sfx(B, "Hop", 0.8)
	end)
	at(B, actBeat(B, a.Tell), function()
		slamFx(B, slot(B, 1) or B.here3 or B.vpos, a.Radius, 1)
	end)
	local _ = t0
end

-- SPIKE ROWS: the stomp that sends them marching
function Starts.SpikeRows(B, t0)
	local a = B.def.Attacks.SpikeRows
	at(B, actBeat(B, a.Tell), function()
		slamFx(B, slot(B, 1) or B.here3 or B.vpos, 6, 0.8)
	end)
	local _ = t0
end

-- STOMP CHAIN: a hop and a slam a beat
function Starts.StompChain(B, t0)
	local a = B.def.Attacks.StompChain
	for h = 1, a.Hops do
		at(B, actBeat(B, h - 1), function()
			sfx(B, "Hop", 0.5)
		end)
		at(B, actBeat(B, h), function()
			slamFx(B, slot(B, h) or B.here3 or B.vpos, a.Radius, (h == a.Hops) and 1 or 0.7)
		end)
	end
	local _ = t0
end

-- CEILING DROP: the glint as it locks, the whoosh of the drop, the crash
function Starts.CeilingDrop(B, t0)
	local a = B.def.Attacks.CeilingDrop
	at(B, actBeat(B, a.Lock), function()
		yell(B, "!", 0.6, HOT)
	end)
	at(B, actBeat(B, a.Tell - 0.5), function()
		sfx(B, "Dive", 0.9)
	end)
	at(B, actBeat(B, a.Tell), function()
		slamFx(B, slot(B, 1) or B.here3 or B.vpos, a.Radius, 1.1)
		burst((B.here3 or B.vpos) + V3(0, 1, 0), YELLOW, 10, 12, 0.8, 0.5, true)
	end)
	local _ = t0
end

-- slot 1: where he'll land
function SlotSpawns.CeilingDrop(B, i, spot, t0)
	if i == 1 then
		dropLine(B, spot, actBeat(B, B.def.Attacks.CeilingDrop.Tell))
	end
	local _ = t0
end

-- BOMB RUN: off he goes
function Starts.BombRun(B, t0)
	local a = B.def.Attacks.BombRun
	at(B, t0 + 0.05, function()
		yell(B, "BOMBS AWAY!", 1, PINK)
	end)
	at(B, actBeat(B, a.Tell - 1), function()
		sfx(B, "Ship", 0.9)
	end)
end

-- SWOOP: the lane, the dive, the climb
function Starts.Swoop(B, t0)
	local a = B.def.Attacks.Swoop
	local tLock, tDive = actBeat(B, a.Tell - a.Lock), actBeat(B, a.Tell)
	local tSkim, tClimb = actBeat(B, a.Tell + 1), actBeat(B, a.Tell + 1 + a.Skim)
	swoopLane(B, a, tLock, tDive, tSkim)
	at(B, tDive, function()
		sfx(B, "Dive", 1)
	end)
	at(B, tSkim, function()
		burst((B.here3 or B.vpos) + V3(0, 0.5, 0), YELLOW, 14, 14, 0.7, 0.4)
		kick(B.here3 or B.vpos, 10, 0.5, -2)
	end)
	at(B, tClimb, function()
		sfx(B, "Ship", 0.7)
	end)
	local _ = t0
end

-- UFO SLAM: the circle, the beam, the slam
function Starts.UfoSlam(B, t0)
	local a = B.def.Attacks.UfoSlam
	local tLock, tLand = actBeat(B, a.Lock), actBeat(B, a.Tell)
	slamCircle(B, a.Radius, tLock, tLand)
	at(B, actBeat(B, a.Tell - 0.5), function()
		sfx(B, "Dive", 0.7)
	end)
	at(B, tLand, function()
		slamFx(B, slot(B, 1) or B.here3 or B.vpos, a.Radius, 1.1)
	end)
	local _ = t0
end

-- ORB RAIN: (the orbs are the level's: see stepFaller)
function Starts.OrbRain(B, t0)
	at(B, t0 + 0.05, function()
		yell(B, "ORB RAIN!", 1, MAGENTA)
	end)
end

-- ZIG-ZAG: a zoom on every leg
function Starts.ZigZag(B, t0)
	local a = B.def.Attacks.ZigZag
	for k = 1, a.Legs do
		at(B, actBeat(B, a.Tell + k - 1), function()
			sfx(B, "Zoom", 0.7)
		end)
	end
	local _ = t0
end

-- TILE PATTERN: he shouts what's coming (slot 1 says which: its X)
local PATTERN_NAMES = { "CHECKERS!", "STRIPES!", "STRIPES!", "RINGS!", "HALF AND HALF!", "HALF AND HALF!" }
function Starts.TilePattern(B, t0)
	at(B, t0 + 0.05, function()
		local pick = slot(B, 1)
		yell(B, PATTERN_NAMES[pick and math.floor(pick.X + 0.5) or 1] or "DODGE THIS!", 1.2, HOT)
	end)
end

-- THE DROP: the music builds - DROP IN 3... 2... 1... (get on a jump pad!) -
-- DROP! - and his crash
function Starts.Drop(B, t0)
	local d = B.def.Drop
	at(B, t0 + 0.03, function()
		sfx(B, "Build", 1)
		yell(B, "HERE IT COMES...", 1.6, HOT)
	end)
	for i = 1, d.Build - 1 do
		at(B, actBeat(B, i), function()
			banner(B, "DROP IN " .. (d.Build - i), { color = (i == d.Build - 1) and HOT or WHITE, sub = (i == 1) and "GET ON A JUMP PAD!" or nil, subColor = GREEN, size = 90, hold = 0.42 })
			kick(B.here3 or B.vpos, 200, 0.25 + 0.15 * i, -1)
		end)
	end
	at(B, actBeat(B, d.Build), function()
		banner(B, "DROP!", { color = HOT, size = 130, hold = 0.8 })
		sfx(B, "Drop", 1)
		kick(B.here3 or B.vpos, 200, 1.4, -8)
		B.flashWorldAt, B.flashColor = serverNow(), WHITE
	end)
	at(B, actBeat(B, d.Build + 0.5), function()
		slamFx(B, B.here3 or B.vpos, 10, 1.2)
	end)
end

-- STUNNED: dizzy stars and a groan
function Starts.Stunned(B, t0)
	at(B, t0 + 0.02, function()
		sfx(B, "Stun", 1)
		burst((B.center3 or B.vpos) + V3(0, 4, 0), YELLOW, 16, 10, 0.8, 0.6, true)
	end)
end

-- A PORTAL: the new form's colour, and POP as he flies through
function Starts.Portal(B, t0)
	local n = tonumber(B.model:GetAttribute("ActN")) or 1
	local to = FORMS[math.floor(n)] or "Cube"
	local switch = actBeat(B, 1)
	B.portal = { from = B.formShown or "Cube", to = to, at = switch }
	at(B, switch, function()
		B.popAt = switch
		B.whiteUntil = switch + 0.08
		sfx(B, "Portal", 1)
		burst(B.center3 or B.vpos, PORTAL_COLOR[to], 30, 22, 1.6, 0.7)
		yell(B, FORM_SHOUT[to], 1, PORTAL_COLOR[to])
	end)
	local _ = t0
end

-- slot 1: where the portal stands (across his path, as high as he'll be
-- flying through it)
function SlotSpawns.Portal(B, i, spot, t0)
	if i ~= 1 then
		return
	end
	local pt = B.portal
	local to = pt and pt.to or "Cube"
	local from = B.here3 or B.vpos
	local fromAlt = B.alt or 0
	local toAlt = (B.def.Forms[to] and B.def.Forms[to].Height) or 0
	local y = floorY(B) + (fromAlt + toAlt) / 2 + 5
	local c = V3(spot.X, math.max(y, floorY(B) + 8.6), spot.Z)
	portalRing(B, c, flat(spot - from), PORTAL_COLOR[to] or GREEN, serverNow(), actBeat(B, 1), actBeat(B, 2))
	local _ = t0
end

-- A GRAVITY FLIP: which way, the whoosh, and (back down) a slam
function Starts.Flip(B, t0)
	local g = B.model:GetAttribute("ActN")
	g = (g == -1) and -1 or 1
	B.flipTo, B.flipAt = g, actBeat(B, 0)
	at(B, B.flipAt, function()
		sfx(B, "Flip", 1)
		yell(B, (g == -1) and "UP!" or "DOWN!", 0.9, (g == -1) and GRAVITY_UP or GRAVITY_DOWN)
	end)
	if g == 1 then
		at(B, actBeat(B, 1), function()
			slamFx(B, B.here3 or B.vpos, 9, 1)
		end)
	end
	local _ = t0
end

-- slot 1: the gravity portal, round where he stands
function SlotSpawns.Flip(B, i, spot, t0)
	if i == 1 then
		local g = B.flipTo or -1
		gravityRing(B, spot, (g == -1) and GRAVITY_UP or GRAVITY_DOWN, serverNow(), actBeat(B, 0), actBeat(B, 1.4))
	end
	local _ = t0
end

----------------------------------------------------------------------
-- The level's % (under the boss bar), and a hint over him while he's open
----------------------------------------------------------------------
-- how far through the level you are: how much of him is gone (100% = LEVEL
-- COMPLETE), as a bar like the real thing's, with the number beside it
local hud = nil
local function buildHud()
	local Players = game:GetService("Players")
	local gui = Instance.new("ScreenGui")
	gui.Name = "GridlockProgress"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.Enabled = false
	gui:SetAttribute("RetroSkip", true) -- (it has its own pixel look)
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 101)
	holder.Size = UDim2.new(0, 320, 0, 18)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 0, 0.5, -5)
	bar.Size = UDim2.new(1, -70, 0, 10)
	bar.BackgroundColor3 = INK
	bar.BorderSizePixel = 0
	bar.Parent = holder
	local edge = Instance.new("UIStroke")
	edge.Color = WHITE
	edge.Thickness = 2
	edge.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local label = Instance.new("TextLabel")
	label.Name = "Percent"
	label.Position = UDim2.new(1, -62, 0, 0)
	label.Size = UDim2.new(0, 62, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = INK
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Text = "0%"
	label.Parent = holder
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	hud = { gui = gui, fill = fill, label = label }
end

local function stepHud(B, show)
	if show and not hud then
		pcall(buildHud)
	end
	if not hud then
		return
	end
	local now = serverNow()
	if not show or (B.stateNow == "Dead" and now > (B.actionStart or now) + 6) then
		hud.gui.Enabled = false
		return
	end
	local max = math.max(B.model:GetAttribute("MaxHealth") or 1, 1)
	local hp = math.max(B.model:GetAttribute("Health") or 0, 0)
	local pct = (B.stateNow == "Dead") and 100 or clamp(math.floor((1 - hp / max) * 100 + 1e-6), 0, 99)
	if pct ~= B.pctShown then
		B.pctShown = pct
		hud.label.Text = pct .. "%"
		hud.fill.Size = UDim2.fromScale(pct / 100, 1)
	end
	if B.stateNow == "Dead" then
		-- (100%: flashing)
		hud.fill.BackgroundColor3 = (math.floor(now * 4) % 2 == 0) and YELLOW or GREEN
	else
		hud.fill.BackgroundColor3 = B.phase2Look and CYAN or GREEN
	end
	hud.gui.Enabled = true
end

-- the hint over him while he's open
local function hintOf(B)
	if B.action == "Stunned" and (B.alt or 0) < 1 then
		return "STUNNED! HIT HIM!"
	end
	if B.stuckNow and (B.action == "CeilingDrop" or B.action == "UfoSlam") then
		return "STUCK! HIT HIM!"
	end
	return nil
end

local function stepHint(B, show)
	local want = show and hintOf(B) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(serverNow() * 6) % 2 == 0) and 0 or 0.25
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
		bb.Name = "GridlockHint"
		bb.Size = UDim2.fromOffset(280, 30)
		bb.StudsOffsetWorldSpace = V3(0, 9, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.body.core
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

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- the form he's drawn in: the server's - except through a portal, where the
-- old one lasts until he's halfway (the moment the server changes it too)
local function formNow(B, now)
	local f = B.model:GetAttribute("Form")
	if type(f) ~= "string" or not HALF_Y[f] then
		f = "Cube"
	end
	local pt = B.portal
	if B.action == "Portal" and pt then
		f = (now < pt.at) and pt.from or pt.to
	end
	return f
end

-- which way is down for him: 1 = the tiles, -1 = the ceiling (the server's -
-- except it changes at the moment he starts to fall, not a moment early)
local function gravityNow(B, now)
	local g = B.model:GetAttribute("Gravity")
	g = (g == -1) and -1 or 1
	if B.action == "Break" and now < (B.actionStart or now) + B.def.BreakTime * 0.35 then
		g = 1
	elseif B.action == "Flip" and B.flipAt then
		g = (now < B.flipAt) and -(B.flipTo or 1) or (B.flipTo or 1)
	end
	return g
end

-- what his moves are made of: his neon, and the level's purple
-- HIS SONG: Config's Music, and Round2Music once GRAVITY FLIP! starts round
-- 2 (the same song played harder, the same length - BossClient starts it at
-- the same spot, so the beat never slips). One not uploaded yet: the next in
-- line (FallbackMusic last).
function Body.music(B, now)
	local def = B.def
	local round2 = (tonumber(B.model:GetAttribute("Phase")) or 1) >= 2
	-- (asked every frame: the answer is kept for a second, so a song that
	-- isn't there isn't hunted for sixty times a second)
	if B.songPick and B.songRound2 == round2 and os.clock() - B.songPickAt < 1 then
		return B.songPick, B.songVolume
	end
	B.songRound2, B.songPickAt = round2, os.clock()
	B.songPick, B.songVolume = def.Music, nil
	local order = {}
	if round2 and def.Round2Music then
		table.insert(order, def.Round2Music)
	end
	table.insert(order, def.Music)
	table.insert(order, def.FallbackMusic)
	for _, name in ipairs(order) do
		if name and findSound(name) then
			B.songPick, B.songVolume = name, (round2 and name == def.Round2Music) and def.Round2MusicVolume or nil
			break
		end
	end
	return B.songPick, B.songVolume
end

function Body.fx(def)
	return { color = def.Color or HOT, deep = def.DeepColor or INK, rock = NIGHT, material = Enum.Material.Neon, solid = true }
end

-- where he is between the server's updates: exactly on his move
function Body.glide(B, now, ground)
	local _ = ground
	return (follow(B, now))
end

-- a pose, played: his form and gravity for this moment, his usual look, the
-- move's own shape, the beat, and his hops
function Body.runPose(B, shape, t, now, P)
	follow(B, now)
	B.formShown = formNow(B, now)
	B.gravShown = gravityNow(B, now)
	-- (a cube breathes less than a slime)
	P.sy, P.sx, P.sz = 1 + (P.sy - 1) * 0.4, 1 + (P.sx - 1) * 0.4, 1 + (P.sz - 1) * 0.4
	P.lean = 0
	P.mouth, P.glow, P.anger = "grin", 0.8, 0.5
	shape(B, t, P)
	-- ON THE BEAT: his neon flares, and (standing on the tiles) he bounces
	if not P.noBeat then
		local k = (1 - beatNow(B, now)) ^ 3
		P.glow = (P.glow or 0.8) + 0.35 * k
		local m = B.move
		local still = not m or m.kind == "Hold" or now >= m.t1
		if B.formShown == "Cube" and still and (B.alt or 0) < 0.5 then
			P.sy -= 0.07 * k
			P.sx += 0.04 * k
			P.sz += 0.04 * k
		end
	end
	hopShape(B, now, P)
	-- which way he faces: the way his move says (the wave: the way it's
	-- going), turned smoothly
	local dt = clamp(now - (B.faceAt or now), 0, 0.1)
	B.faceAt = now
	local want = nil
	if B.formShown == "Wave" then
		want = heading(B, now)
	end
	want = want or (B.move and B.move.f) or B.vfacing
	want = unitOr(flat(want), B.faceDir or V3(0, 0, 1))
	local f = B.faceDir and smoothTo(B, "faceDir", want, 14, math.max(dt, 1 / 240)) or want
	B.faceDir = unitOr(flat(f), want)
	P.facing = P.facing or B.faceDir
end

-- every frame, after he's posed: THE LEVEL (the tiles' warnings and spikes)
function Body.afterPose(B)
	local now = serverNow()
	if B.here and (B.stateNow == "Waking" or B.stateNow == "Fighting" or B.stateNow == "Transition") then
		warmPool(B)
	end
	readPatterns(B, now, B.here == true)
	stepLevel(B, now)
end

-- a new move began
function Body.onAction(B, name, t0, now)
	local n = B.model:GetAttribute("ActN")
	if name == "Portal" or name == "Flip" or type(n) ~= "number" then
		B.k0 = BeatGrid.beatAfter(beat0(B), bpm(B), t0 + 0.12)
	else
		B.k0 = n
	end
	if name == "Wake" then
		B.wakeAt = t0
		B.k0 = BeatGrid.beatAfter(beat0(B), bpm(B), t0 + 0.12)
	end
	if name ~= "Death" then
		B.shatterAt, B.shards = nil, nil
	end
	if name == "Break" or name == "Death" then
		clearLevel(B) -- (the server forgets its tile attacks at these moments too)
	end
	if name ~= "Portal" then
		B.portal = nil
	end
	if name ~= "Flip" then
		B.flipAt, B.flipTo = nil, nil
	end
	B.stuckNow = false
	local _ = now
end

-- joined while round 2 was already on (the gravity comes from the server)
function Body.lateBreak(B)
	B.phase2Look = true
end

-- a fresh start: nothing lit, the world the right way up
function Body.calm(B, name)
	clearLevel(B)
	calmWorld(B)
	B.flashWorldAt, B.pctShown = nil, nil
	B.inv = nil
	local _ = name
end

-- every frame: the level's % and the hint over him, and (while you're in
-- the level) the level moving to the music
function Body.senses(B, dt, here, awake, state)
	B.here = here
	B.stateNow = state
	stepHud(B, here and (awake or state == "Dead"))
	stepHint(B, here and awake)
	if here then
		stepWorld(B, serverNow(), awake)
	end
	local _ = dt
end

-- you can't walk through him: nudged out of his box (the server's own box
-- for the form he's in). Not while he's charging through you - that's a hit!
function Body.pushOut(B, P, here, awake, state)
	if not here or not (awake or state == "Dormant") or (P.fade or 0) > 0.3 or (P.ghost or 0) > 0.3 or B.shards then
		return
	end
	local now = serverNow()
	local m = B.move
	if m and (m.kind == "Zig" or (m.kind == "Fly" and B.action == "Swoop")) and now >= m.t0 and now < m.t1 then
		return
	end
	if B.offset and B.offset.Magnitude > 2 then
		return -- (still catching up with where he really is)
	end
	local hrp = myRoot()
	local c = B.center3
	if not (hrp and c) then
		return
	end
	local half = BOX[B.formShown or "Cube"] or BOX.Cube
	local rel = hrp.Position - c
	if hrp.Position.Y - 3 > c.Y + half.Y or hrp.Position.Y + 2 < c.Y - half.Y then
		return -- (over him, or under him)
	end
	local hx, hz = half.X + 1.3, half.Z + 1.3
	if math.abs(rel.X) < hx and math.abs(rel.Z) < hz then
		local out
		if hx - math.abs(rel.X) < hz - math.abs(rel.Z) then
			out = V3(((rel.X >= 0) and 1 or -1) * hx, 0, rel.Z)
		else
			out = V3(rel.X, 0, ((rel.Z >= 0) and 1 or -1) * hz)
		end
		local target = c + out
		hrp.CFrame = CFrame.new(V3(target.X, hrp.Position.Y, target.Z)) * (hrp.CFrame - hrp.Position)
	end
end

return Body
