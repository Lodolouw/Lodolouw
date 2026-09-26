--[[
	Nahrzul  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Nahrzul")

	How Nahrzul, Devourer of the Dunes (floor 2's boss, Config.Bosses[2], Body =
	"Worm" - "Mireworm" in older code) looks on your screen: a vast segmented
	worm that comes up out of the sand in an arch, the ridge it pushes up
	swimming under the sand, every warning of its attacks, the craters and
	trenches it tears in the dunes, the seal caving in and the armour blasting
	off in phase two, the rumble when it's close, the sinkhole and whirlpool
	dragging you in, the platforms breaking, the "HIT IT!" sign whenever it can
	be hurt, and its body being solid (it shoves you out of it).

	HOW A BODY FILE WORKS (see _Template.lua for a new one):
	  * BossClient finds it by the boss's short name in Config (Short =
	    "Nahrzul") and calls Body.init(kit) once, handing over the drawing kit.
	  * Body.build(def) / Body.pose(B, P, ground, facing, t, dt): its body.
	  * Poses / Starts / SlotSpawns: the shape of each action, its one-off
	    moments, its warnings (the action names are the server's:
	    ServerScriptService/Bosses/Nahrzul.lua).
	  * Everything else it adds to the shared frame (all optional for a boss):
	      Body.fx(def)             what its attacks are made of (sand and rock)
	      Body.onTrack(B)          when your screen starts drawing it
	      Body.onAction(B, name, t0, now)   when a new action begins
	      Body.lateBreak(B)        you arrived after its armour already broke
	      Body.calm(B, name)       it wakes, sleeps or resets
	      Body.signs(B, state)     every frame, first: the "HIT IT!" sign
	      Body.runPose(B, shape, t, now, P)  how a pose is played (catching
	                               up when the news came late, flowing between stages)
	      Body.glide(B, now, ground)   where it is between the server's updates
	      Body.afterPose(B)        after its body is posed (its trail, its arches)
	      Body.senses(B, dt, here, awake, state)  the rumble and the whirlpool
	      Body.pushOut(B, P, here, awake, state)  not letting you walk through it
	      Body.everyFrame()        once a frame, whatever is happening (its scars)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init): the helpers every boss shares
local serverNow, clamp, lerp, smooth, easeOut, easeOutBack, spring, flat, tween, myRoot
local fxFolder, PIXEL, snapColor, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local BONE
local kick, soundGroup, findSound, playSound
local addTelegraph, shockRing, onStone, arenaOf, at

function Body.init(kit)
	serverNow, clamp, lerp, smooth, easeOut, easeOutBack = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.easeOut, kit.easeOutBack
	spring, flat, tween, myRoot = kit.spring, kit.flat, kit.tween, kit.myRoot
	fxFolder, PIXEL, snapColor, newPart, placeDisc = kit.fxFolder, kit.PIXEL, kit.snapColor, kit.newPart, kit.placeDisc
	newRing, placeRing, onFloor, removeRing, burst = kit.newRing, kit.placeRing, kit.onFloor, kit.removeRing, kit.burst
	BONE = kit.BONE
	kick, soundGroup, findSound, playSound = kit.kick, kit.soundGroup, kit.findSound, kit.playSound
	addTelegraph, shockRing, onStone, arenaOf, at = kit.addTelegraph, kit.shockRing, kit.onStone, kit.arenaOf, kit.at
end

-- The shape of each of its actions over time (Poses), their one-off moments
-- (Starts) and the warnings for positions the server fills in as it goes
-- (SlotSpawns) - BossClient looks each action up by name in these.
local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- (the camera belongs to CombatClient: some of its shakes ask it directly)
local cameraKickEvent = nil
task.spawn(function()
	cameraKickEvent = player:WaitForChild("PlayerScripts"):WaitForChild("CombatCameraKick", 20)
end)

----------------------------------------------------------------------
-- Mireworm's body (any boss with Body = "Worm" in Config)
----------------------------------------------------------------------
-- A vast segmented worm that comes up out of the sand in an arch: its tail
-- runs down under the floor, its body rises and curls over, and its head hangs
-- over you with the maw pointed down at you. The maw is a dark throat ringed
-- with teeth, behind three armoured jaws that close into a point and bloom
-- open when it roars or spits. Plates of armour run down its back until
-- they're blasted off at half health - after that, the seams between its
-- segments glow like a furnace.
--
-- It reads the same pose knobs as the slime (lift, sink, lean, mouth, flare...)
-- so every Pose works for both bodies; this is just how a worm shows them:
--   lift  its head rears higher        sink  it goes down into the sand
--   lean  + head thrusts at you, - rears back      sy < 1  its head crashes down
--   ridge (worm only) the mound of sand it pushes up swimming underneath
-- and a few knobs only the worm has, for when it isn't standing up out of a hole:
--   path(s)  where its spine runs, tail (s = 0) to head (s = 1), in the world:
--            the breach's arc, the coil's ring
--   girth    how thick it is (the coil is thinner than it stands)
--   taper(s) how thick it is along its length, tail to head (the lash's whippy tail)
--   stage    a new stage inside one move (its body flows into it, like a new move)
--   collar   0 hides the mound of sand round its base; noShadow hides its shadow
local WORM_SEGMENTS = 20 -- (enough to bend smoothly into an arch, a ring or a leap)
local WORM_BLEND = 0.3 -- seconds its body takes to flow from one shape into the next
local WORM_SAND = RGB(224, 188, 128) -- the arena's sand, for everything it throws up
local WORM_SAND_DEEP = RGB(122, 92, 58) -- churned-up quicksand
local WORM_PLATE = RGB(156, 124, 88)
local WORM_PLATE_DARK = RGB(126, 100, 72)
local WORM_TEETH = 8 -- round the rim of the maw
local WORM_JAWS = 3
local WORM_EYES = 6

-- a scale of armour: a wedge, thick at the back and thin at the front, so
-- they overlap down its back like a fish's
local function newWedge(name, color, material, parent)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Color = color
	w.Material = material
	w.Size = V3(1, 1, 1)
	w.Parent = parent
	return w
end

local function wormEmitter(name, parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Rate = 0
	e.Parent = parent
	return e
end

local function buildWormBody(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }
	local heartColor = def.HeartColor or RGB(255, 90, 40)

	-- the body, from the tail (under the sand) to the head, banded light and dark
	body.segments, body.seams, body.plates = {}, {}, {}
	for i = 1, WORM_SEGMENTS do
		local head = i == WORM_SEGMENTS
		local color = (i % 2 == 0) and def.Color or def.Color:Lerp(def.DeepColor, 0.3)
		local seg = newPart(head and "Head" or "Segment", Enum.PartType.Ball, color, Enum.Material.Sandstone, 0, folder)
		seg.CastShadow = true
		body.segments[i] = { part = seg, color = color }
		-- the crease between this segment and the next: dark now, molten later
		if not head then
			body.seams[i] = newPart("Seam", Enum.PartType.Ball, def.DeepColor, Enum.Material.SmoothPlastic, 0, folder)
		end
		-- armour down its back: a ridge of overlapping scales, with plates on
		-- its flanks (only on the segments that ever come up out of the sand)
		if i >= 4 then
			table.insert(body.plates, { part = newWedge("Plate", WORM_PLATE, Enum.Material.Slate, folder), seg = i, side = 0 })
			if i % 2 == 0 and not head then
				for _, side in ipairs({ -1, 1 }) do
					local plate = newPart("Plate", nil, WORM_PLATE_DARK, Enum.Material.Slate, 0, folder)
					plate.CastShadow = true
					table.insert(body.plates, { part = plate, seg = i, side = side })
				end
			end
		end
	end

	-- the maw: a dark throat with the heart glowing in it, ringed with teeth
	body.maw = newPart("Maw", Enum.PartType.Cylinder, def.CoreColor, Enum.Material.SmoothPlastic, 0, folder)
	body.heart = newPart("Heart", Enum.PartType.Ball, heartColor, Enum.Material.Neon, 0, folder)
	body.light = Instance.new("PointLight")
	body.light.Color = heartColor
	body.light.Range = def.Size * 1.1
	body.light.Brightness = 1.2
	body.light.Shadows = false
	body.light.Parent = body.heart
	body.teeth = {}
	for i = 1, WORM_TEETH do
		body.teeth[i] = {
			part = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder),
			angle = (i - 0.5) / WORM_TEETH * math.pi * 2,
			long = 0.8 + ((i * 5) % 4) * 0.12, -- ragged, not a neat ring
		}
	end
	-- three jaws that close into a point and bloom open, fanged on the inside
	body.jaws = {}
	for j = 1, WORM_JAWS do
		local jaw = {
			part = newPart("Jaw", Enum.PartType.Ball, def.Color:Lerp(def.DeepColor, 0.45), Enum.Material.Sandstone, 0, folder),
			angle = (j - 1) / WORM_JAWS * math.pi * 2 + math.pi / 2,
			fangs = {},
		}
		jaw.part.CastShadow = true
		for f = 1, 3 do
			jaw.fangs[f] = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder)
		end
		body.jaws[j] = jaw
	end
	-- small eyes, far too many of them, in a ring behind the jaws
	body.eyes = {}
	for i = 1, WORM_EYES do
		body.eyes[i] = {
			part = newPart("Eye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder),
			angle = (i - 0.5) / WORM_EYES * math.pi * 2 + 0.2,
			size = 1.3 + (i % 3) * 0.35,
			rate = 0.19 + i * 0.043, -- each one blinks on its own clock
			seed = i * 0.31,
		}
	end

	-- the sand: a mound where it comes out of the floor, the ridge it pushes up
	-- when it swims underneath, sand pouring off it and dust round its base
	body.collar = newPart("SandCollar", Enum.PartType.Ball, WORM_SAND:Lerp(WORM_SAND_DEEP, 0.15), Enum.Material.Sand, 0, folder)
	body.ridge = newPart("SandRidge", Enum.PartType.Ball, WORM_SAND, Enum.Material.Sand, 1, folder)
	body.spillAt = newPart("SandSpill", nil, WORM_SAND, nil, 1, folder)
	body.spillAt.Size = V3(def.Size * 0.5, 2, def.Size * 0.5)
	body.spill = wormEmitter("Spill", body.spillAt, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.1, 1.7),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = V3(0, -42, 0),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	body.dustAt = newPart("SandDust", nil, WORM_SAND, nil, 1, folder)
	body.dustAt.Size = V3(def.Size * 1.2, 1, def.Size * 1.2)
	body.dust = wormEmitter("Dust", body.dustAt, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.4),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = V3(0, -3, 0),
		Drag = 1.5,
		RotSpeed = NumberRange.new(-40, 40),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, RGB(40, 28, 16), Enum.Material.SmoothPlastic, 0.55, folder)

	folder.Parent = fxFolder
	return body
end

local function bezier(p0, p1, p2, p3, s)
	local u = 1 - s
	return p0 * (u * u * u) + p1 * (3 * u * u * s) + p2 * (3 * u * s * s) + p3 * (s * s * s)
end

local function bezierSlope(p0, p1, p2, p3, s)
	local u = 1 - s
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * s) + (p3 - p2) * (3 * s * s)
end

-- a frame at `pos` whose look runs along `along`, with its top turned as near
-- to `up` as it can be
local function frameAlong(pos, along, up)
	local look = along.Magnitude > 1e-4 and along.Unit or V3(0, 1, 0)
	local y = up - look * up:Dot(look)
	if y.Magnitude < 1e-4 then
		y = math.abs(look.Y) < 0.9 and (V3(0, 1, 0) - look * look.Y) or (V3(1, 0, 0) - look * look.X)
	end
	y = y.Unit
	return CFrame.fromMatrix(pos, look:Cross(y), y, -look)
end

-- Drawing the worm cheaply. It's over a hundred parts, redrawn every frame, so:
--  * every part's new place is collected and they all move in one go (BulkMoveTo)
--  * sizes, colours, see-through-ness and materials are only written when they've
--    actually changed
--  * a segment deep under the sand (nobody can see it) is left where it was
local Fast = {
	parts = {}, cframes = {}, n = 0,
	sizes = setmetatable({}, { __mode = "k" }),
	alphas = setmetatable({}, { __mode = "k" }),
	colors = setmetatable({}, { __mode = "k" }),
}
function Fast.move(p, cf)
	local n = Fast.n + 1
	Fast.n = n
	Fast.parts[n], Fast.cframes[n] = p, cf
end
function Fast.flush()
	local n = Fast.n
	if n == 0 then
		return
	end
	for i = #Fast.parts, n + 1, -1 do
		Fast.parts[i], Fast.cframes[i] = nil, nil
	end
	local ok = pcall(function()
		Workspace:BulkMoveTo(Fast.parts, Fast.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i = 1, n do
			Fast.parts[i].CFrame = Fast.cframes[i]
		end
	end
	Fast.n = 0
end
-- (`tolerance`: how much it has to change by before it's worth resizing -
-- parts that overlap their neighbours can take a bigger one)
function Fast.size(p, v, tolerance)
	local old = Fast.sizes[p]
	if not old or math.abs(old.X - v.X) + math.abs(old.Y - v.Y) + math.abs(old.Z - v.Z) > (tolerance or 0.12) then
		Fast.sizes[p] = v
		p.Size = v
	end
end
function Fast.alpha(p, a)
	if Fast.alphas[p] ~= a then
		Fast.alphas[p] = a
		p.Transparency = a
	end
end
function Fast.color(p, c)
	if PIXEL and p.Material ~= Enum.Material.Neon then
		c = snapColor(c) -- (8-bit: its colours stay on the palette as they change)
	end
	if Fast.colors[p] ~= c then
		Fast.colors[p] = c
		p.Color = c
	end
end

local function applyWormPose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	local D = def.Size
	local fade = P.fade or 0
	local phase2 = B.phase2Look
	local sink = clamp(P.sink or 0, 0, 1)
	local ridge = clamp(P.ridge or 0, 0, 1.6)

	-- all the way under and nothing moving on the surface: it's already hidden
	-- where it last was, so there's nothing to do (the dunes are a long way
	-- from the lobby, and every screen runs this every frame). The same asleep
	-- in its coils while you're somewhere else: drawn once, then left.
	local resting = B.model:GetAttribute("State") == "Dormant" and player:GetAttribute("SpireFloor") ~= B.floor
	if (not P.path and sink >= 0.999 and ridge < 0.02 and fade <= 0) or fade >= 1 or resting then
		if B.parked then
			return
		end
		B.parked = true
	else
		B.parked = false
	end

	local jitter = V3(0, 0, 0)
	if P.shake > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local origin = ground + jitter
	local F = facing
	local U = V3(0, 1, 0)
	local R = F:Cross(U)
	local floorY = ground.Y

	-- how tall it stands and how thick it is (squash and stretch, toned down:
	-- it's a worm, not a jelly)
	local H = D * 1.35 * (1 + (P.sy - 1) * 0.8) + P.lift * 1.1
	local girth = P.girth or D * 0.64 * (1 + (P.sx - 1) * 0.6)
	local lean = P.lean
	local fwd, back = math.max(lean, 0), math.min(lean, 0)
	-- squashed: its head has come down hard. A slime springs straight back; a
	-- worm's head stays down in the sand a moment before it heaves it up again.
	local crash = math.max(0, 1 - P.sy)
	if crash >= (B.crashPeak or 0) * clamp(1 - (t - (B.crashAt or 0) - 0.15) / 0.3, 0, 1) then
		B.crashPeak, B.crashAt = crash, t
	end
	crash = math.max(crash, (B.crashPeak or 0) * clamp(1 - (t - (B.crashAt or 0) - 0.15) / 0.3, 0, 1))
	local moving = B.model:GetAttribute("Moving")
	local sway = math.sin(t * 1.2) * 0.05 + (moving and math.sin(t * 6) * 0.1 or 0)

	-- the spine: up out of the sand leaning back, over the top, and the head
	-- hanging down at you like a question mark
	-- (with a twist to one side, so it's a serpent from the front too, not a pillar)
	local c0 = V3(-D * 0.08, -D * 0.8, -D * 0.05)
	local c1 = V3(D * 0.2 + sway * D * 0.5, H * 0.72, -D * 0.3 + lean * D * 0.12)
	local c2 = V3(-D * 0.14 + sway * D * 0.9, math.max(H * (1.12 - 0.35 * fwd) - crash * H * 0.45, girth * 0.5), D * 0.3 + lean * D * 0.5)
	local c3 = V3(sway * D * 0.4,
		math.max(H * (0.76 - 0.45 * fwd - 0.32 * back) - crash * H * 1.6, girth * 0.45),
		D * 0.68 + lean * D * 0.55 - crash * D * 0.1)
	-- sunk: the whole of it goes down into the sand together
	local sinkDepth = sink * (math.max(c2.Y, c3.Y) + girth * 1.1 + 2)
	local function world(v)
		return origin + R * v.X + U * (v.Y - sinkDepth) + F * v.Z
	end
	local function slope(v)
		return R * v.X + U * v.Y + F * v.Z
	end

	-- a punch landing blanches it for a blink, so every hit shows
	local flash = B.flashAt and clamp(1 - (os.clock() - B.flashAt) / 0.14, 0, 1) or 0
	local health = (B.model:GetAttribute("Health") or 1) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1)

	-- the segments: along the question mark, or along whatever path the pose gave
	local points = {}
	local S0 = 0.08
	local path = P.path
	for i = 1, WORM_SEGMENTS do
		local s = S0 + (1 - S0) * (i - 1) / (WORM_SEGMENTS - 1)
		if path then
			local pos = path(s)
			points[i] = { s = s, pos = pos, along = path(math.min(s + 0.02, 1.02)) - path(math.max(s - 0.02, 0)) }
		else
			points[i] = { s = s, pos = world(bezier(c0, c1, c2, c3, s)), along = slope(bezierSlope(c0, c1, c2, c3, s)) }
		end
	end
	-- Hand-overs: when it starts something new, its body flows from the shape it
	-- was in to the new one instead of jumping. Head first: its head sets off
	-- into the new shape and the rest follows on down its length, the way a
	-- creature moves (not every part at once, like a morph). The further it has
	-- to go, the longer it takes - a moment either way. Parts that were out of
	-- sight under the sand simply come up in their new place. (Not when it's
	-- come up somewhere else entirely: then there's nothing to flow from.)
	local from = B.blendFrom
	if from and from[WORM_SEGMENTS] and not B.blendUntil then
		local hidden, far = B.blendHidden or {}, 0
		for i, pt in ipairs(points) do
			if not hidden[i] then
				far = math.max(far, (from[i] - pt.pos).Magnitude)
			end
		end
		B.blendTime = clamp(WORM_BLEND + far / 160, WORM_BLEND, 0.6)
		B.blendUntil = t + B.blendTime
	end
	if from and from[WORM_SEGMENTS] and t < B.blendUntil then
		if flat(from[WORM_SEGMENTS] - points[WORM_SEGMENTS].pos).Magnitude < 70 then
			local q = 1 - (B.blendUntil - t) / B.blendTime
			local w = smooth(q)
			local hidden = B.blendHidden or {}
			for i, pt in ipairs(points) do
				if not hidden[i] then
					pt.pos = from[i]:Lerp(pt.pos, smooth(clamp(q * 1.6 - (1 - pt.s) * 0.6, 0, 1)))
				end
			end
			for i, pt in ipairs(points) do
				local a, b = points[math.max(i - 1, 1)].pos, points[math.min(i + 1, WORM_SEGMENTS)].pos
				if (b - a).Magnitude > 1e-3 then
					pt.along = b - a
				end
			end
			girth = lerp(B.blendGirth or girth, girth, w)
		else
			B.blendFrom = nil
		end
	end
	-- (this frame's shape, to flow from next time)
	B.lastPoints = B.lastPoints or {}
	for i, pt in ipairs(points) do
		B.lastPoints[i] = pt.pos
	end
	B.lastGirth = girth

	-- which segments are deep under the sand (a girth or more down): once one
	-- has been put down there it's left alone - nobody can see it
	B.buried = B.buried or {}
	local skip = {}
	for i, pt in ipairs(points) do
		local deep = pt.pos.Y < floorY - girth * (i == WORM_SEGMENTS and 1.05 or 1)
		skip[i] = deep and B.buried[i] == true and fade <= 0
		B.buried[i] = deep
	end

	local frames, girths, lengths = {}, {}, {}
	for i, pt in ipairs(points) do
		local prev = points[i - 1] and (pt.pos - points[i - 1].pos).Magnitude or 0
		local nxt = points[i + 1] and (points[i + 1].pos - pt.pos).Magnitude or 0
		local g = girth * (P.taper and P.taper(pt.s) or (1.06 - 0.16 * pt.s))
		local len = math.max(prev, nxt) * 1.75
		if i == WORM_SEGMENTS then
			-- the head: broader than its neck, a hood over the maw
			g = g * 1.2
			len = math.max(len, g * 1.2)
		end
		local along = pt.along.Magnitude > 1e-4 and pt.along.Unit or U
		-- its top is its back (on a path - a ring, an arc, lying flat - its back is simply up)
		local cf = frameAlong(pt.pos, along, path and U or R:Cross(along))
		frames[i], girths[i], lengths[i] = cf, g, len
		if not skip[i] then
			local seg = body.segments[i]
			Fast.size(seg.part, V3(g, g * 0.96, len), 0.35)
			Fast.move(seg.part, cf)
			local c = phase2 and seg.color:Lerp(def.DeepColor, 0.2) or seg.color
			Fast.color(seg.part, flash > 0 and c:Lerp(RGB(255, 240, 214), 0.45 * flash) or c)
			Fast.alpha(seg.part, fade)
		end
	end

	B.segGirths = girths -- (how thick each piece is: you can't walk through it)

	-- the creases: dark, until its armour is gone and they burn
	local heartColor = def.HeartColor or RGB(255, 90, 40)
	for i, seam in ipairs(body.seams) do
		if not (skip[i] and skip[i + 1]) then
			local a, b = frames[i], frames[i + 1]
			local g = (girths[i] + girths[i + 1]) / 2 * 0.84
			Fast.size(seam, V3(g, g * 0.96, 1.3), 0.3)
			Fast.move(seam, frameAlong((a.Position + b.Position) / 2, b.Position - a.Position, a.UpVector))
			if phase2 then
				if seam.Material ~= Enum.Material.Neon then
					seam.Material = Enum.Material.Neon
				end
				local tq = math.floor(t * 12) / 12 -- (a dozen changes a second is plenty for a glow)
				Fast.color(seam, heartColor:Lerp(RGB(255, 214, 140), 0.25 + 0.25 * math.sin(tq * 3 + i)))
			else
				if seam.Material ~= Enum.Material.SmoothPlastic then
					seam.Material = Enum.Material.SmoothPlastic
				end
				Fast.color(seam, def.DeepColor)
			end
			Fast.alpha(seam, fade)
		end
	end

	-- the armour, until it's blasted off: scales down the ridge of its back
	-- (thick end toward the tail, so they overlap) and plates on its flanks
	for _, pl in ipairs(body.plates) do
		if B.crownGone then
			Fast.alpha(pl.part, 1)
		elseif not skip[pl.seg] then
			local cf, g, len = frames[pl.seg], girths[pl.seg], lengths[pl.seg]
			if pl.side == 0 then
				local h = g * (pl.seg == WORM_SEGMENTS and 0.15 or 0.2)
				Fast.size(pl.part, V3(g * 0.3, h, len * 0.62), 0.3)
				Fast.move(pl.part, cf * CFrame.new(0, g * 0.46 + h / 2 - g * 0.04, len * 0.08))
			else
				Fast.size(pl.part, V3(g * 0.3, g * 0.06, len * 0.5), 0.3)
				Fast.move(pl.part, cf * CFrame.Angles(0, 0, pl.side * 0.8) * CFrame.new(0, g * 0.47, 0))
			end
			Fast.alpha(pl.part, fade)
		end
	end

	-- the head
	local headCF = frames[WORM_SEGMENTS]
	local gH, lenH = girths[WORM_SEGMENTS], lengths[WORM_SEGMENTS]
	B.headPos = headCF.Position
	local T, top, side = headCF.LookVector, headCF.UpVector, headCF.RightVector
	local mouth = clamp(P.mouth, 0, 1)
	local rimR = gH * 0.27
	local mawAt = headCF.Position + T * (lenH / 2 * 0.8)
	B.mawPos = mawAt -- (what it spits from)
	local rate = phase2 and (health <= def.DesperateAt and 2.4 or 1.7) or 1.1
	local beatT = (os.clock() * rate) % 1
	local beat = math.exp(-((beatT - 0.05) / 0.06) ^ 2) + 0.6 * math.exp(-((beatT - 0.24) / 0.06) ^ 2)
	body.light.Brightness = lerp((phase2 and 2.4 or 1.2) + 0.6 * beat + P.flare * 1.8, 0, math.max(fade, sink))
	if not skip[WORM_SEGMENTS] then
		Fast.size(body.maw, V3(0.5, rimR * 2, rimR * 2))
		Fast.move(body.maw, CFrame.fromMatrix(mawAt, T, top, T:Cross(top)))
		Fast.alpha(body.maw, fade)

		-- the heart in its throat: two beats and a rest, faster once its armour is
		-- gone, faster again when it's nearly dead
		local heartSize = gH * (phase2 and 0.2 or 0.15) * (1 + 0.2 * beat + 0.3 * P.flare) * math.min(P.coreScale or 1, 1.3)
		Fast.size(body.heart, V3(heartSize, heartSize, heartSize * 0.6))
		Fast.move(body.heart, CFrame.fromMatrix(mawAt + T * 0.35, side, top, -T))
		Fast.alpha(body.heart, clamp(fade * 1.5, 0, 1))
		Fast.color(body.heart, heartColor:Lerp(RGB(255, 236, 190), 0.35 * beat + 0.4 * P.flare))
		body.light.Range = D * (phase2 and 1.6 or 1.1)

		-- teeth round the rim, pointing in at the throat
		for _, tooth in ipairs(body.teeth) do
			local radial = side * math.cos(tooth.angle) + top * math.sin(tooth.angle)
			local len = gH * 0.15 * tooth.long * (0.85 + 0.3 * mouth)
			local dir = (T * 0.45 - radial).Unit
			local base = mawAt + radial * (rimR * 0.96) + T * 0.2
			Fast.size(tooth.part, V3(gH * 0.05, len, gH * 0.05))
			Fast.move(tooth.part, CFrame.fromMatrix(base + dir * (len / 2), T:Cross(radial), dir))
			Fast.alpha(tooth.part, clamp(fade * 1.2, 0, 1))
		end

		-- the jaws: shut into a point, open straight ahead to spit, splayed wide to roar
		local jawLen = gH * 0.62
		local theta = lerp(-0.55, 1.15, mouth)
		for _, jaw in ipairs(body.jaws) do
			local radial = side * math.cos(jaw.angle) + top * math.sin(jaw.angle)
			local hinge = mawAt + radial * rimR - T * 0.4
			local dir = T * math.cos(theta) + radial * math.sin(theta)
			local out = radial * math.cos(theta) - T * math.sin(theta) -- its outer face
			local across = dir:Cross(out)
			Fast.size(jaw.part, V3(gH * 0.32, gH * 0.12, jawLen))
			Fast.move(jaw.part, CFrame.fromMatrix(hinge + dir * (jawLen / 2), across, out, -dir))
			Fast.alpha(jaw.part, fade)
			for f, fang in ipairs(jaw.fangs) do
				local len = gH * 0.1 * (1.15 - f * 0.12)
				local tip = hinge + dir * (jawLen * (0.25 + f * 0.18)) - out * (gH * 0.04)
				Fast.size(fang, V3(gH * 0.045, len, gH * 0.045))
				Fast.move(fang, CFrame.fromMatrix(tip - out * (len / 2), across, -out))
				Fast.alpha(fang, clamp(fade * 1.2, 0, 1))
			end
		end

		-- its eyes, in a ring round the head behind the jaws
		local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
		local ringAt = headCF.Position + T * (lenH / 2 * 0.42)
		local ringR = gH / 2 * 0.96 * math.sqrt(1 - 0.42 ^ 2) * 0.97
		local eyeColor = def.EyeColor:Lerp(RGB(255, 255, 255), clamp(P.flare, 0, 1) * 0.4)
		for _, e in ipairs(body.eyes) do
			local radial = side * math.cos(e.angle) + top * math.sin(e.angle)
			local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.06 and 0 or 1
			local open = eyeOpen * blink
			local size = e.size * (1 + 0.35 * P.flare)
			Fast.size(e.part, V3(size, math.max(size * open, 0.05), size * 0.7))
			Fast.move(e.part, CFrame.fromMatrix(ringAt + radial * ringR, T:Cross(radial), T, radial))
			Fast.alpha(e.part, open < 0.05 and 1 or 0)
			Fast.color(e.part, eyeColor)
		end
	end

	-- (the old sand collar, solid "ridge" lump and flat shadow disc are gone: it
	-- comes out of real craters in the Terrain sand now, its back arches out of
	-- the real sand when it swims, and its body casts real shadows)
	Fast.alpha(body.collar, 1)
	Fast.alpha(body.ridge, 1)
	Fast.alpha(body.shadow, 1)

	-- sand pours off it as it comes up; dust blows off its base as it moves
	local out = 1 - sink
	local floorAt = onFloor(ground)
	local lastSink = B.lastSink or sink
	B.lastSink = sink
	local rising = dt > 0 and (lastSink - sink) / dt or 0
	B.spillHeat = math.max((B.spillHeat or 0) * math.exp(-dt * 0.8), clamp(rising * 1.5, 0, 1))
	Fast.move(body.spillAt, headCF)
	body.spill.Rate = (P.spill or ((1 - fade) * out * (4 + 35 * B.spillHeat))) * 0.5
	Fast.move(body.dustAt, CFrame.new(floorAt + V3(0, 1, 0)))
	body.dust.Rate = (1 - fade) * (ridge * 18 + (moving and out * 6 or 0) + B.spillHeat * out * 15) * 0.5
	Fast.flush()
end

-- Mireworm's armour blasting off its back when it breaks at half health
local function shatterPlates(B)
	B.crownGone = true
	local floorY = B.vpos.Y
	for i, pl in ipairs(B.body.plates) do
		local start = pl.part.CFrame
		if pl.part.Transparency < 1 and i % 2 == 1 then -- half of them fly: plenty of debris, half the parts
			local shard = newPart("Shard", nil, pl.part.Color, Enum.Material.Slate, 0)
			shard.Size = pl.part.Size
			shard.CastShadow = true
			local away = start.UpVector + V3(0, 0.5, 0)
			away = away.Magnitude > 0.01 and away.Unit or V3(0, 1, 0)
			local speed = 24 + (i % 4) * 7
			local t0 = serverNow()
			addTelegraph(B, {
				update = function(now)
					local e = now - t0
					if e > 2.4 then
						return false
					end
					local p = start.Position + away * speed * e + V3(0, -38 * e * e, 0)
					if p.Y < floorY + 0.6 then
						p = V3(p.X, floorY + 0.6, p.Z) -- landed in the sand
					end
					shard.CFrame = CFrame.new(p) * (start - start.Position) * CFrame.Angles(e * 5, e * 2, e * 3)
					shard.Transparency = clamp((e - 1.8) / 0.6, 0, 1)
					return true
				end,
				cleanup = function()
					shard:Destroy()
				end,
			})
		end
	end
end

-- (Mireworm's sand tools live in their own block: a Roblox script may only
-- have 200 names at its top level, so only the ones used elsewhere are shared.)
local Terrain, newScar, scarHole, scarHeave, carve, closeScar, forgetScar, stepScars, closeAllScars, floorHeightAt, warmSand
do
	----------------------------------------------------------------------
	-- The sand floor, torn up (Mireworm's arena)
	----------------------------------------------------------------------
	-- The dunes' fighting floor is Terrain sand (DunesBuilder), so the worm can
	-- really tear it up: craters where it bursts out, a trench where its body
	-- crashes down, the ground heaving up before an ambush, fissures in a tremor,
	-- the sinkhole of a devour and the pit in phase two. It's all done on YOUR
	-- screen (every screen does the same thing at the same moment, from the
	-- server's clock), and you really walk in it. After Scars.Last seconds the
	-- sand slides back in and the floor is flat again. Hits never depend on it:
	-- the server decides those exactly as before.
	Terrain = Workspace:FindFirstChildOfClass("Terrain")
	local AIR, SANDMAT = Enum.Material.Air, Enum.Material.Sand
	local scars = {} -- torn-up sand waiting to slide back
	local floorInfo = nil -- the arena floor: where it is and what stands on it

	-- round down / up to Terrain's 4-stud grid
	local function grid(v, up)
		return up and math.ceil(v / 4) * 4 or math.floor(v / 4) * 4
	end

	-- Things standing on the sand (pillars, platforms, braziers...) that a hole
	-- mustn't open under, and flat decoration lying on it (ripples, bones...)
	-- that would float over a hole, so it's hidden until the sand comes back.
	local KEEP_OUT = { EdgeWall = true, SealStone = true, SealRing = true, SealCoil = true, SealTile = true, SandSwirl = true }
	local function arenaFloor(B)
		local arena = arenaOf(B)
		if not arena then
			return nil
		end
		if floorInfo and floorInfo.arena == arena and os.clock() < floorInfo.fresh then
			return floorInfo
		end
		local center = arena:GetAttribute("Center")
		if typeof(center) ~= "Vector3" then
			return nil
		end
		-- (looked through once - it's a big model - and again only if it changes)
		local info = { arena = arena, floor = B.floor, center = center, radius = arena:GetAttribute("SandRadius") or 146, y = center.Y, solids = {}, decor = {}, fresh = math.huge }
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("BasePart") and not KEEP_OUT[d.Name] then
				local p = d.Position
				local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
				local owner = d:FindFirstAncestorWhichIsA("Model")
				local ownName = owner and owner.Name or ""
				if big < 80 and flat(p - center).Magnitude < info.radius + 6 and math.abs(p.Y - info.y) < big / 2 + 1 then
					if d.CanCollide then
						table.insert(info.solids, { part = d, r = math.max(d.Size.X, d.Size.Z) / 2 })
					elseif d.Transparency < 1 and not ownName:find("^DunePlatform") then
						table.insert(info.decor, d)
					end
				end
			end
		end
		floorInfo = info
		return info
	end

	-- how big a hole can be here: it stops short of anything standing on the
	-- sand, and of the dunes round the edge
	local function roomAt(info, pos, radius)
		radius = math.min(radius, info.radius - 8 - flat(pos - info.center).Magnitude)
		for _, s in ipairs(info.solids) do
			if s.part.Parent and s.part.CanCollide then
				local gap = flat(pos - s.part.Position).Magnitude - s.r - 1.5
				if gap < radius then
					radius = gap
				end
			end
		end
		return radius
	end

	-- A new scar (a crater, a trench, fissures, a heave...) - balls of air (or of
	-- sand, for a heave) that go back to flat floor together
	function newScar(B, kind, life)
		-- (tearing up the Terrain sand is the heaviest thing the worm does to your
		-- screen: it's off unless Config turns it on - Scars.Terrain = true)
		local SC = B.def and B.def.Scars
		if not (SC and SC.Terrain) then
			return nil
		end
		local info = (player:GetAttribute("SpireFloor") == B.floor) and Terrain and arenaFloor(B)
		if not info then
			return nil
		end
		local sc = { kind = kind, info = info, balls = {}, hidden = {}, refillAt = serverNow() + (life or 7) }
		sc.halfAt = sc.refillAt - 1.1
		table.insert(scars, sc)
		return sc
	end

	-- Terrain edits wait their turn and go through a few a frame, so a whole
	-- trench (or the sand sliding back into several craters) never lands in one
	-- frame and hitches your screen.
	local edits = {}
	local EDITS_PER_FRAME = 2
	local function terrainEdit(fn)
		edits[#edits + 1] = fn
	end

	-- Sand about to be put back where YOU stand: you're lifted onto it first.
	-- (Your character's physics runs on your own screen, so sand appearing
	-- around your legs would bury you - and a buried character loses the
	-- ground and drops straight through the floor.) `top` is the new surface.
	local FEET = 3 -- (from the middle of your body down to your feet, near enough)
	local function liftOut(x0, x1, z0, z1, top, redug)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local p = hrp.Position
		if p.X < x0 - 1.5 or p.X > x1 + 1.5 or p.Z < z0 - 1.5 or p.Z > z1 + 1.5 then
			return
		end
		-- (standing in another hole that's dug straight back out in the same
		-- moment - the phase-two pit, say - you stay where you are)
		for _, b in ipairs(redug or {}) do
			if not b.height and flat(p - V3(b.x, 0, b.z)).Magnitude < b.r - 1 then
				return
			end
		end
		if p.Y - FEET < top + 0.3 and p.Y > top - 20 then
			hrp.CFrame = hrp.CFrame + V3(0, top + FEET + 0.6 - p.Y, 0)
			hrp.AssemblyLinearVelocity = V3(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
		end
	end

	-- puts one piece of a scar into the terrain (again, if something covered it)
	local TERRACES = 5
	local function carveBall(ball)
		if ball.closed then
			return -- (its scar has been filled back in since)
		end
		if ball.cone then
			-- a wide, shallow pit (the phase-two bowl): stacked discs of air, each
			-- narrower and deeper than the last - far less work for Terrain than
			-- one enormous ball - which Terrain rounds off into a smooth bowl
			for k = 1, TERRACES do
				local r = ball.r * (1 - (k - 1) / TERRACES)
				local d = ball.depth * k / TERRACES
				Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY - d / 2 + 0.5, ball.z), d + 1, r, AIR)
			end
		elseif ball.height then
			-- a heave: two stacked discs of sand, only ever above the floor (so
			-- it never fills in a crater next to it); Terrain rounds them off
			liftOut(ball.x - ball.r, ball.x + ball.r, ball.z - ball.r, ball.z + ball.r, ball.floorY + ball.height)
			Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY + ball.height * 0.3, ball.z), ball.height * 0.6, ball.r, SANDMAT)
			Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY + ball.height * 0.5, ball.z), ball.height, ball.r * 0.6, SANDMAT)
		else
			Terrain:FillBall(ball.c, ball.rs, AIR)
		end
	end
	local function ballFill(ball)
		terrainEdit(function()
			carveBall(ball)
		end)
	end

	-- Adds one bowl of air to a scar: `radius` across at the top, `depth` deep.
	-- (A big ball of air whose bottom just dips into the sand.)
	function scarHole(sc, pos, radius, depth)
		if not sc then
			return
		end
		local info = sc.info
		radius = roomAt(info, pos, radius)
		if radius < 2.5 then
			return
		end
		depth = math.min(depth, radius * 0.7)
		local rs = (radius * radius + depth * depth) / (2 * depth)
		local ball = { c = V3(pos.X, info.y - depth + rs, pos.Z), rs = rs, x = pos.X, z = pos.Z, r = radius, depth = depth, floorY = info.y }
		ball.cone = rs > 40 -- (very wide and shallow: carved in cheap stacked discs instead)
		ballFill(ball)
		table.insert(sc.balls, ball)
		-- what was lying there would float: hidden until the sand comes back
		for _, d in ipairs(info.decor) do
			if d.Parent and not sc.hidden[d] and flat(d.Position - pos).Magnitude < radius + 1 then
				sc.hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	end

	-- Adds a heave: sand pushed UP out of the floor in a low mound
	function scarHeave(sc, pos, radius, height)
		if not sc then
			return
		end
		local info = sc.info
		radius = roomAt(info, pos, radius)
		if radius < 2.5 then
			return
		end
		local ball = { x = pos.X, z = pos.Z, r = radius, height = height, floorY = info.y }
		ballFill(ball)
		table.insert(sc.balls, ball)
	end

	-- one-shot helpers
	function carve(B, pos, radius, depth, life)
		local sc = newScar(B, "hole", life)
		scarHole(sc, pos, radius, depth)
		return sc
	end

	-- the grid-aligned box round a scar's balls
	local function scarBox(sc)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, b in ipairs(sc.balls) do
			x0, x1 = math.min(x0, b.x - b.r), math.max(x1, b.x + b.r)
			z0, z1 = math.min(z0, b.z - b.r), math.max(z1, b.z + b.r)
		end
		return grid(x0 - 4), grid(x1 + 4, true), grid(z0 - 4), grid(z1 + 4, true)
	end

	-- The sand sliding back. `upTo` = how high to fill (the floor, or partway for
	-- the first half of the slide). A heave is simply cleared away above the floor.
	local function refillScar(sc, upTo)
		if #sc.balls == 0 then
			return
		end
		local info = sc.info
		local x0, x1, z0, z1 = scarBox(sc)
		local mid = V3((x0 + x1) / 2, 0, (z0 + z1) / 2)
		-- anything else torn up in that box (another crater, the phase-two pit)
		local redug = {}
		for _, other in ipairs(scars) do
			if other ~= sc then
				for _, b in ipairs(other.balls) do
					if b.x + b.r > x0 and b.x - b.r < x1 and b.z + b.r > z0 and b.z - b.r < z1 then
						redug[#redug + 1] = b
					end
				end
			end
		end
		terrainEdit(function()
			if sc.kind == "heave" then
				local h = grid(12, true)
				Terrain:FillBlock(CFrame.new(mid.X, info.y + h / 2, mid.Z), V3(x1 - x0, h, z1 - z0), AIR)
			else
				local bottom = info.y - 12
				local top = upTo or info.y
				liftOut(x0, x1, z0, z1, top, redug)
				Terrain:FillBlock(CFrame.new(mid.X, (bottom + top) / 2, mid.Z), V3(x1 - x0, top - bottom, z1 - z0), SANDMAT)
			end
			-- ...goes back the way it was in the SAME moment: there's never a
			-- frame where the sand covers a hole someone is standing in
			for _, b in ipairs(redug) do
				carveBall(b)
			end
		end)
	end

	function closeScar(sc)
		refillScar(sc)
		for _, b in ipairs(sc.balls) do
			b.closed = true -- (so nothing digs it back out later)
		end
		for d, t in pairs(sc.hidden) do
			if d.Parent then
				d.Transparency = t
			end
		end
		sc.balls, sc.hidden = {}, {}
	end

	-- Every frame: a few waiting terrain edits, and sand sliding back into the
	-- scars whose time is up
	function stepScars()
		for _ = 1, math.min(EDITS_PER_FRAME, #edits) do
			pcall(table.remove(edits, 1))
		end
		-- The safety net: if you ever end up under the arena's floor (whatever
		-- put you there), you're put straight back on top of the sand, right
		-- where you were (or just inside the edge), instead of falling forever.
		local info = floorInfo
		if info and player:GetAttribute("SpireFloor") == info.floor then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < info.y - 10 then
				local off = flat(hrp.Position - info.center)
				if off.Magnitude < info.radius + 60 then
					local keep = math.min(off.Magnitude, info.radius - 8)
					local spot = info.center + (off.Magnitude > 0.1 and off.Unit * keep or V3())
					hrp.AssemblyLinearVelocity = V3()
					hrp.CFrame = CFrame.new(V3(spot.X, info.y + FEET + 4, spot.Z)) * (hrp.CFrame - hrp.Position)
				end
			end
		end
		local now = serverNow()
		for i = #scars, 1, -1 do
			local sc = scars[i]
			if now >= sc.refillAt then
				table.remove(scars, i)
				closeScar(sc)
			elseif now >= sc.halfAt and not sc.halfDone and sc.kind == "hole" and sc.balls[1] then
				-- halfway: it's filling in (and a little sand pours in)
				sc.halfDone = true
				local deepest = 0
				for _, b in ipairs(sc.balls) do
					deepest = math.max(deepest, b.depth or 0)
				end
				refillScar(sc, sc.info.y - deepest * 0.45)
				local b = sc.balls[1]
				burst(V3(b.x, sc.info.y + 0.5, b.z), WORM_SAND, 8, 6, 1.6, 0.8)
			end
		end
	end

	-- everything back to flat (the worm went back to sleep, or you left)
	function closeAllScars()
		for i = #scars, 1, -1 do
			local sc = table.remove(scars, i)
			closeScar(sc)
		end
	end

	-- Ready the sand before the fight (the worm's warm-up, "rehearse"): look
	-- through the arena for what stands on the sand now, and dig one small
	-- hole deep inside the floor and fill it straight back in - out of sight -
	-- so the fight's first real crater doesn't stall.
	function warmSand(B)
		floorInfo = nil
		local info = arenaFloor(B)
		if info and Terrain then
			local deep = info.center - V3(0, 10, 0)
			pcall(function()
				Terrain:FillBall(deep, 2, AIR)
				Terrain:FillBall(deep, 2, SANDMAT)
			end)
		end
	end

	-- the height of the floor at a spot, given the scars (for putting things on
	-- the sides of a crater or the pit rather than floating over it)
	function floorHeightAt(pos, floorY)
		local y = floorY
		for _, sc in ipairs(scars) do
			if sc.kind == "hole" then
				for _, b in ipairs(sc.balls) do
					local x = flat(pos - V3(b.x, 0, b.z)).Magnitude
					if x < b.r then
						if b.cone then
							y = math.min(y, floorY - b.depth * (1 - x / b.r))
						else
							y = math.min(y, b.c.Y - math.sqrt(math.max(b.rs * b.rs - x * x, 0)))
						end
					end
				end
			end
		end
		return y
	end

	-- stops keeping track of a scar without filling it in (collapseSeal fills the
	-- bowl itself)
	function forgetScar(sc)
		for i, other in ipairs(scars) do
			if other == sc then
				table.remove(scars, i)
				return
			end
		end
	end
end

-- The stone seal at the middle of the dunes caves in when Mireworm's armour
-- breaks: the floor there collapses into a real bowl of sand, with arms of
-- sand swirling down into the pit at the bottom - and it's whole again the
-- next time the worm sleeps. (Only on your screen, but every screen does it
-- at the same moment.)
local SEAL_PARTS = { SealStone = true, SealRing = true, SealCoil = true, SealTile = true, SandSwirl = true }
local function collapseSeal(B, on, instant)
	local arena = arenaOf(B)
	if arena and (not B.seal or #B.seal == 0) then
		-- (what caves in, looked up once - the worm's warm-up does it before the fight)
		B.seal = {}
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("BasePart") and SEAL_PARTS[d.Name] then
				table.insert(B.seal, { part = d, cf = d.CFrame, transparency = d.Transparency or 0 })
			end
		end
	end
	if (B.sealDown or false) == on or not arena then
		return
	end
	B.sealDown = on
	for _, s in ipairs(B.seal) do
		if s.tween then
			s.tween:Cancel()
			s.tween = nil
		end
		if on and not instant then
			s.tween = tween(s.part, 1.2 + (s.cf.Position.Y % 0.3), { CFrame = s.cf - V3(0, 6, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif on then
			s.part.CFrame = s.cf - V3(0, 6, 0)
			s.part.Transparency = 1
		else
			s.part.CFrame = s.cf
			s.part.Transparency = s.transparency
		end
	end
	if B.crater then
		for _, p in ipairs(B.crater) do
			p:Destroy()
		end
		B.crater = nil
	end
	B.vortex = nil
	if B.bowl then
		-- the sand fills the pit back in
		forgetScar(B.bowl)
		closeScar(B.bowl)
		B.bowl = nil
	end
	if not on then
		return
	end
	-- the pit
	local center, radius = nil, 34
	for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
		if h:GetAttribute("Floor") == B.floor then
			center, radius = h.Position, h:GetAttribute("Radius") or 34
		end
	end
	center = center or arena:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then
		return
	end
	local W = B.def.Whirlpool or {}
	local bowlR, depth = (W.Radius or radius) - 2, W.Depth or 5
	-- the floor gives way: it sinks in stages (all at once if you arrive late)
	B.bowl = newScar(B, "hole", math.huge)
	if B.bowl then
		B.bowl.halfAt = math.huge
		if instant then
			scarHole(B.bowl, center, bowlR, depth)
		else
			local bowl = B.bowl
			for i, k in ipairs({ 0.45, 0.75, 1 }) do
				task.delay((i - 1) * 0.35, function()
					if B.bowl == bowl then
						scarHole(bowl, center, bowlR * k, depth * k)
						burst(center + V3(0, 1, 0), WORM_SAND, 20, 18, 3, 1, true)
					end
				end)
			end
		end
	end
	local bottom = center.Y - depth
	local deep = newPart("SinkholeDeep", Enum.PartType.Cylinder, RGB(24, 17, 10), Enum.Material.SmoothPlastic, instant and 0 or 1)
	placeDisc(deep, V3(center.X, bottom + 0.2, center.Z), (W.PitRadius or 8) * 2, 0.1)
	local pour = newPart("SinkholePour", nil, WORM_SAND, nil, 1)
	pour.Size = V3(bowlR * 1.6, 1, bowlR * 1.6)
	pour.CFrame = CFrame.new(center + V3(0, 1.5, 0))
	local e = wormEmitter("Pour", pour, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		Acceleration = V3(0, -6, 0),
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	e.Rate = 16
	B.crater = { deep, pour }
	-- the whirlpool: three arms of pale sand spiralling down the sides of the
	-- bowl into the pit (stepWormSenses turns them, and drags you in)
	B.vortex = { center = center, radius = bowlR, depth = depth, arms = {} }
	for arm = 0, 2 do
		for j = 0, 7 do
			local streak = newPart("VortexStreak", nil, WORM_SAND:Lerp(RGB(255, 240, 210), 0.35 - j * 0.03), Enum.Material.Sand, 0.1)
			table.insert(B.vortex.arms, { part = streak, arm = arm, j = j })
			table.insert(B.crater, streak)
		end
	end
	if not instant then
		-- the stone goes, then the floor gives way under it in a cloud of sand
		burst(center + V3(0, 1, 0), WORM_SAND, 50, 30, 4, 1.4, true)
		tween(deep, 1.4, { Transparency = 0 })
	end
end

-- (Everything Mireworm draws lives in this one block: a Roblox script may only
-- have 200 names at its top level, so only the handful used further down are
-- shared - the rest stay inside.)
local trailReset, trailRecord, stepHumps, stepWormSenses, pushOutOfWorm, glideWorm
do
	----------------------------------------------------------------------
	-- MIREWORM: the hunt, as your screen sees it
	----------------------------------------------------------------------
	-- BossService decides everything - where it swims, when each attack lands,
	-- who it hits. This draws it all from the same server clock: its back arching
	-- out of the sand as it swims, the sand it tears up, every warning, the rumble
	-- when it's close and the platforms breaking. None of
	-- Gloomgut's drawing above is used for it, and none of this is used for Gloomgut.
	local WORM_GLOW = RGB(255, 150, 70) -- warnings of something coming up from below
	local LOCKED = RGB(255, 60, 40) -- a breach that has stopped following you
	local STONE_BITS = { RGB(214, 172, 114), RGB(178, 134, 86), RGB(146, 102, 64) } -- the platforms' sandstone
	local SAND_BITS = { WORM_SAND, RGB(204, 166, 108), WORM_SAND_DEEP }

	-- How it swims: it follows the path its head took, under the sand, and every
	-- so often its back arches up out of the sand - the head first, then the body
	-- threading through the same arch - like a sea serpent.
	local BODY_LEN = 100 -- nose to tail, when it swims
	local HUMP_LEN = 38 -- one arch of its back
	local HUMP_EVERY = 62 -- studs it swims between arches (some attacks arch more often)
	local TRAIL_KEEP = BODY_LEN + HUMP_LEN + 60

	-- a spot on the sand, a hair above it: the markings on the floor sit on top
	-- of the Terrain sand rather than half inside its surface
	local function onSand(p)
		local f = onFloor(p)
		return V3(f.X, f.Y + 0.1, f.Z)
	end

	-- a bar lying flat on the floor from a to b
	local function placeStrip(p, a, b, width, thickness, y)
		local run = flat(b - a)
		local len = run.Magnitude
		local mid = (a + b) / 2
		local c = V3(mid.X, y or mid.Y, mid.Z)
		Fast.size(p, V3(width, thickness or 0.12, math.max(len, 0.05)), 0.05)
		if len > 0.05 then
			p.CFrame = CFrame.lookAt(c, c + run)
		else
			p.CFrame = CFrame.new(c)
		end
	end

	-- a bar from a to b, following them up and down (down the side of a pit)
	local function placeBar(p, a, b, width, thickness)
		local len = (b - a).Magnitude
		Fast.size(p, V3(width, thickness or 0.12, math.max(len, 0.05)), 0.05)
		if len > 0.05 then
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
		else
			p.CFrame = CFrame.new((a + b) / 2)
		end
	end

	local function hideRing(ring)
		for _, p in ipairs(ring.parts) do
			p.Transparency = 1
		end
	end

	-- the point on the segment a-b nearest to p
	local function nearestOnSegment(a, b, p)
		local ab = flat(b - a)
		local len = ab.Magnitude
		if len < 0.01 then
			return a
		end
		return a + ab.Unit * clamp(flat(p - a):Dot(ab.Unit), 0, len)
	end

	local function myFloorPos(B)
		local hrp = myRoot()
		return hrp and hrp.Position or B.vpos
	end

	-- a steady "random" number from a seed, so every screen picks the same one
	local function seeded(n)
		local x = math.sin(n * 12.9898) * 43758.5453
		return x - math.floor(x)
	end

	-- Drags YOUR character toward `center` (the devour's sinkhole, the whirlpool).
	-- Only on sand, only with your feet on the ground, and never faster than you
	-- can run: running outward always gets you out, it just takes longer - and
	-- a roll (in the air) slips free.
	local function dragMe(B, center, radius, edgeSpeed, centreSpeed, dt)
		local hrp = myRoot()
		if not hrp or player:GetAttribute("SpireFloor") ~= B.floor then
			return
		end
		local off = flat(center - hrp.Position)
		local d = off.Magnitude
		if d > radius or d < 0.6 or onStone(B, hrp.Position) then
			return
		end
		local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
		if hum and hum.FloorMaterial == Enum.Material.Air then
			return
		end
		local speed = lerp(edgeSpeed, centreSpeed, 1 - d / radius)
		hrp.CFrame = hrp.CFrame + off.Unit * math.min(speed * dt, d)
	end

	-- Chunks thrown up and out, bouncing to a stop and fading (only on your screen)
	local function flingRubble(center, count, colors, speedScale)
		colors = colors or STONE_BITS
		local bits = {}
		count = math.max(3, math.floor(count * 0.6))
		for i = 1, count do
			local p = newPart("Rubble", nil, colors[(i % #colors) + 1], Enum.Material.Sandstone, 0)
			p.Size = V3(1 + math.random() * 2.6, 0.8 + math.random() * 1.6, 1 + math.random() * 2.6)
			local ang = math.random() * math.pi * 2
			local speed = (8 + math.random() * 16) * (speedScale or 1)
			bits[i] = {
				part = p,
				pos = center + V3((math.random() - 0.5) * 8, 1, (math.random() - 0.5) * 8),
				vel = V3(math.cos(ang) * speed, (22 + math.random() * 20) * (speedScale or 1), math.sin(ang) * speed),
				spin = V3(math.random(), math.random(), math.random()) * 6,
			}
		end
		local t0 = os.clock()
		local conn
		local settled = false
		conn = RunService.RenderStepped:Connect(function(dt)
			local e = os.clock() - t0
			-- (once every chunk has landed and stopped, there's nothing to move)
			if not settled then
				local parts, cframes = {}, {}
				settled = true
				for k, b in ipairs(bits) do
					if not b.still then
						b.vel = b.vel + V3(0, -60 * dt, 0)
						b.pos = b.pos + b.vel * dt
						b.age = e
						if b.pos.Y < center.Y + 0.5 then
							b.pos = V3(b.pos.X, center.Y + 0.5, b.pos.Z)
							b.vel = V3(b.vel.X * 0.4, 0, b.vel.Z * 0.4)
							b.still = b.vel.Magnitude < 1.5
						end
						settled = false
						parts[#parts + 1] = b.part
						cframes[#cframes + 1] = CFrame.new(b.pos) * CFrame.Angles(b.spin.X * b.age, b.spin.Y * b.age, b.spin.Z * b.age)
					end
				end
				if #parts > 0 then
					pcall(function()
						Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
					end)
				end
			end
			if e > 2 then
				local fade = math.floor(clamp((e - 2) / 0.8, 0, 1) * 5) / 5 -- (in five steps)
				for _, b in ipairs(bits) do
					Fast.alpha(b.part, fade)
				end
			end
			if e > 2.8 then
				conn:Disconnect()
				for _, b in ipairs(bits) do
					b.part:Destroy()
				end
			end
		end)
	end

	local function scarLife(B)
		return (B.def.Scars and B.def.Scars.Last) or 7
	end

	----------------------------------------------------------------------
	-- Gliding: smooth movement between what the server sends
	----------------------------------------------------------------------
	-- The server moves it every frame, but your screen only hears about it a
	-- few dozen times a second, a little unevenly. Chasing each update makes it
	-- judder; instead every position is kept with the moment it arrived, and
	-- it's drawn GLIDE seconds behind, sliding steadily between them.
	-- Each position comes stamped with the moment the server put it there
	-- (the "PosT" attribute), so a burst of updates arriving together, or a
	-- slow patch on the connection, can't make it stop and jump. The delay
	-- grows by itself if your updates arrive late, and shrinks again after.
	function glideWorm(B, now, ground)
		if B.model:GetAttribute("State") == "Dormant" then
			B.snaps = nil -- asleep at home: nothing to glide (start afresh when it wakes)
			return ground
		end
		local stamp = B.model:GetAttribute("PosT")
		local snaps = B.snaps
		if not snaps then
			snaps = {}
			B.snaps = snaps
		end
		if type(stamp) ~= "number" then
			return ground -- (an older BossService that doesn't stamp: just follow it)
		end
		local last = snaps[#snaps]
		if not last or stamp > last.t then
			local gap = last and flat(ground - last.p).Magnitude or 0
			if gap > 40 or (gap > 4 and gap / math.max(stamp - last.t, 1 / 240) > 200) then
				-- it jumped on the server (came up somewhere else): faster than it
				-- can ever move, so it's shown as a jump now, not slid across
				table.clear(snaps)
			end
			snaps[#snaps + 1] = { t = stamp, p = ground, o = tonumber(B.model:GetAttribute("Odo")) }
			while #snaps > 40 do
				table.remove(snaps, 1)
			end
			-- how late this update is: the delay needs to cover the latest ones
			local late = now - stamp
			B.glideLate = math.max((B.glideLate or 0.1) * 0.97, late)
		end
		local want = clamp((B.glideLate or 0.1) + 0.05, 0.08, 0.4)
		B.glide = B.glide and (B.glide + (want - B.glide) * math.min(1, 0.05)) or want
		local at = now - B.glide
		if #snaps == 0 then
			return ground
		end
		-- (how far it had swum, on the server, at the moment it's drawn: the
		-- arches of its back are placed by that - see stepHumps)
		if at <= snaps[1].t then
			B.sodo = snaps[1].o
			return snaps[1].p
		end
		for i = #snaps, 2, -1 do
			local a = snaps[i - 1]
			if at >= a.t then
				local b = snaps[i]
				local k = clamp((at - a.t) / math.max(b.t - a.t, 1e-3), 0, 1)
				B.sodo = (a.o and b.o) and a.o + (b.o - a.o) * k or b.o
				return a.p:Lerp(b.p, k)
			end
		end
		B.sodo = snaps[#snaps].o
		return snaps[#snaps].p
	end

	----------------------------------------------------------------------
	-- Swimming under the sand
	----------------------------------------------------------------------
	-- The path its head has taken (recorded every frame), so its body can follow
	-- it exactly, and the arches its back makes out of the sand.
	function trailReset(B)
		B.trail, B.humps = { { odo = B.odo or 0, pos = B.vpos } }, {}
		B.odo = B.odo or 0
	end

	function trailRecord(B)
		local tr = B.trail
		local last = tr[#tr]
		local step = flat(B.vpos - last.pos).Magnitude
		if step < 1 then
			return
		end
		if step > 45 then
			trailReset(B) -- it burst up somewhere else entirely: start the path afresh
			B.trail[1].pos = B.vpos
			return
		end
		B.odo = B.odo + step
		tr[#tr + 1] = { odo = B.odo, pos = B.vpos }
		if #tr > 4 and B.odo - tr[1].odo > TRAIL_KEEP then
			table.remove(tr, 1)
		end
	end

	-- where its head was `back` studs of swimming ago
	local function trailAt(B, back)
		local tr = B.trail
		local want = B.odo - back
		if want >= tr[#tr].odo then
			return tr[#tr].pos
		end
		if want <= tr[1].odo then
			-- further back than it remembers: carry on straight back
			local a, b = tr[1], tr[2]
			local dir = b and flat(a.pos - b.pos) or V3(0, 0, 0)
			dir = dir.Magnitude > 0.01 and dir.Unit or -B.vfacing
			return a.pos + dir * (a.odo - want)
		end
		local lo, hi = 1, #tr
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if tr[mid].odo <= want then
				lo = mid
			else
				hi = mid
			end
		end
		local a, b = tr[lo], tr[hi]
		return a.pos:Lerp(b.pos, (want - a.odo) / math.max(b.odo - a.odo, 1e-3))
	end

	-- how far its back is lifted out of the sand at a point of its path (0..1)
	local function humpLift(B, odo)
		local lift = 0
		for _, h in ipairs(B.humps) do
			local x = (odo - h.o) / HUMP_LEN
			if x > 0 and x < 1 then
				lift = math.max(lift, math.sin(x * math.pi))
			end
		end
		return lift
	end

	-- its body under the sand, along its path, arching out where the humps are
	local function underPath(B)
		local g = B.def.Size * 0.64
		local baseY = B.vpos.Y - g * 1.1
		local rise = g * 1.2
		return function(s)
			local back = (1 - s) * BODY_LEN
			local p = trailAt(B, back)
			return V3(p.X, baseY + humpLift(B, B.odo - back) * rise, p.Z)
		end
	end

	-- The pose for anything it does under the sand. spray = the sand thrown up
	-- over its head; every = how often its back arches out (nil: it doesn't).
	local function underPose(B, P, spray, every)
		P.path = underPath(B)
		P.sink, P.ridge, P.eyes = 1, spray or 1, 1
		P.noShadow, P.noPush = true, true
		B.humpEvery = every
	end

	-- New arches as it swims, old ones gone once its tail is through them, and
	-- sand pouring off its back where it breaks the surface.
	-- Where the arches of its back come up is BossService's to decide (it's
	-- where you can hit it: see bodyNear there) - its "Humps", in how far it
	-- has swum - so every screen draws them in the same place.
	local OWN_HUMPS = {} -- (none now: BossService places every arch)
	function stepHumps(B)
		local list = B.model:GetAttribute("Humps")
		if type(list) == "string" and B.sodo and not OWN_HUMPS[B.action] then
			-- (its odometer on your screen vs the server's - eased, so the arches
			-- sit still instead of shivering by a stud as your screen counts)
			local shift = B.odo - B.sodo
			if not B.humpShift or math.abs(shift - B.humpShift) > 8 then
				B.humpShift = shift
			end
			B.humpShift = B.humpShift + (shift - B.humpShift) * 0.1
			shift = B.humpShift
			local humps = {}
			for h in string.gmatch(list, "[^,]+") do
				local o = tonumber(h)
				if o then
					humps[#humps + 1] = { o = o + shift }
				end
			end
			B.humps = humps
			B.lastHump = B.odo
		else
			if B.fromServer then
				B.humps = {} -- (its own arches from here, starting clean)
			end
			local humps = B.humps
			for i = #humps, 1, -1 do
				if B.odo - humps[i].o > BODY_LEN + HUMP_LEN then
					table.remove(humps, i)
				end
			end
			if B.humpEvery and B.odo - (B.lastHump or -math.huge) >= B.humpEvery then
				B.lastHump = B.odo
				table.insert(humps, { o = B.odo + 1 })
			end
		end
		B.fromServer = type(list) == "string" and B.sodo ~= nil and not OWN_HUMPS[B.action]
		local humps = B.humps
		if not B.humpDust then
			B.humpDust = {}
			for i = 1, 4 do
				local holder = newPart("HumpDust", nil, WORM_SAND, nil, 1, B.body.folder)
				holder.Size = V3(7, 1, 7)
				B.humpDust[i] = {
					holder = holder,
					emitter = wormEmitter("Pour", holder, {
						Color = ColorSequence.new(WORM_SAND),
						LightInfluence = 1,
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4.5) }),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
						Lifetime = NumberRange.new(0.8, 1.4),
						Speed = NumberRange.new(6, 15),
						SpreadAngle = Vector2.new(35, 35),
						Acceleration = V3(0, -40, 0),
						EmissionDirection = Enum.NormalId.Top,
						Shape = Enum.ParticleEmitterShape.Box,
						ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
					}),
				}
			end
		end
		-- where the two newest arches go into and come out of the sand
		local k = 0
		for i = #humps, math.max(1, #humps - 1), -1 do
			local h = humps[i]
			for _, w in ipairs({ h.o, h.o + HUMP_LEN }) do
				k = k + 1
				local d = B.humpDust[k]
				local covered = w <= B.odo and w >= B.odo - BODY_LEN -- some of its body is passing here
				if covered then
					local p = trailAt(B, B.odo - w)
					d.holder.CFrame = CFrame.new(V3(p.X, B.vpos.Y + 0.5, p.Z))
					d.emitter.Rate = 16
				else
					d.emitter.Rate = 0
				end
			end
		end
		for j = k + 1, 4 do
			B.humpDust[j].emitter.Rate = 0
		end
	end

	----------------------------------------------------------------------
	-- Its body in its other shapes
	----------------------------------------------------------------------
	-- Coiled round its quarry like a snake: the tail goes down into the sand off
	-- the start of the ring, its body runs all the way round (half sunk in the
	-- sand), and its neck climbs from the end of the ring up over the middle, the
	-- head looking down at whoever is inside. `down` sinks the whole coil.
	local function coilPath(C, r, g, headUp, rise, thEnd, down)
		down = down or 0
		local ringY = C.Y + g * 0.18 * rise - g * 1.1 * (1 - rise) - down
		local endP = V3(C.X + math.sin(thEnd) * r, ringY, C.Z + math.cos(thEnd) * r)
		local headP = V3(C.X, C.Y + headUp - down, C.Z)
		local ctrl = V3(C.X + math.sin(thEnd) * r * 0.55, C.Y + headUp * 1.15 + g * 0.3 - down, C.Z + math.cos(thEnd) * r * 0.55)
		local neck = (headP - endP).Magnitude * 1.15
		local ring = 2 * math.pi * r * 0.94
		local total = neck + ring + 24
		local th0 = thEnd - ring / r
		local startP = V3(C.X + math.sin(th0) * r, ringY, C.Z + math.cos(th0) * r)
		local onward = V3(-math.cos(th0), 0, math.sin(th0)) -- on round the way the ring runs
		return function(s)
			local d = (1 - s) * total -- distance back from its head
			if d <= neck then
				local q = d / neck
				local w = 1 - q
				return headP * (w * w) + ctrl * (2 * w * q) + endP * (q * q)
			end
			d = d - neck
			if d <= ring then
				local th = thEnd - d / r
				return V3(C.X + math.sin(th) * r, ringY, C.Z + math.cos(th) * r)
			end
			d = d - ring
			return startP + onward * (d * 0.5) + V3(0, -d * 0.9, 0)
		end
	end

	----------------------------------------------------------------------
	-- Warnings in the world (each is a telegraph: update(now) -> keep going?)
	----------------------------------------------------------------------
	-- AMBUSH: the ground heaves up under you in shoves (real sand: you feel it
	-- lift you), ringed in glowing warning, and then it bursts up out of it.
	local function ambushMark(B, spot, eruptAt)
		local a = B.def.Attacks.Ambush
		spot = onSand(spot)
		local t0 = serverNow()
		local ring = newRing(26, WORM_GLOW, Enum.Material.Neon, 1)
		local heave = newScar(B, "heave", math.max(eruptAt - t0, 0.1))
		local shoves = { 0.2, 0.5, 0.8 }
		local done = 0
		addTelegraph(B, {
			update = function(now)
				if now >= eruptAt then
					return false
				end
				local u = clamp((now - t0) / math.max(eruptAt - t0, 0.05), 0, 1)
				while done < #shoves and u >= shoves[done + 1] do
					done = done + 1
					scarHeave(heave, spot, a.Radius * (0.55 + 0.2 * done), 1.2 * done)
					burst(spot + V3(0, 1.2 * done, 0), WORM_SAND, 10, 10, 1.8, 0.6, true)
				end
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(12, 32, u))
				placeRing(ring, spot + V3(0, 0.08, 0), a.Radius + 0.5, 0.3, 0.55, lerp(0.7, 0.05, u * pulse))
				return true
			end,
			cleanup = function()
				removeRing(ring)
			end,
		})
	end

	-- BREACH: the strip its body will come down on. While it's in the air the
	-- strip FOLLOWS YOU (the server keeps re-aiming it); when it stops following
	-- (Lock), it flashes red - that's your moment to roll. It bursts out of a
	-- crater, and where it lands its body carves a trench.
	local function breachStrip(B, t0, tell)
		local a = B.def.Attacks.Breach
		local m = B.model
		local A = m:GetAttribute("ActA")
		if typeof(A) ~= "Vector3" then
			return
		end
		A = onSand(A)
		local launchAt = t0 + tell
		local landAt = launchAt + a.Flight
		local lockAt = launchAt + a.Flight * a.Lock
		local strip = newPart("BreachStrip", nil, WORM_SAND_DEEP, Enum.Material.Sand, 1)
		local edges = { newPart("BreachEdge", nil, WORM_GLOW, Enum.Material.Neon, 1), newPart("BreachEdge", nil, WORM_GLOW, Enum.Material.Neon, 1) }
		local launch = newRing(24, WORM_GLOW, Enum.Material.Neon, 1)
		local shadow = newPart("BreachShadow", Enum.PartType.Cylinder, RGB(40, 28, 16), Enum.Material.SmoothPlastic, 1)
		local launched, locked, landed = false, false, false
		local Bp = nil
		addTelegraph(B, {
			update = function(now)
				if now > landAt + 0.25 then
					return false
				end
				if not landed then
					local live = m:GetAttribute("ActB")
					if typeof(live) == "Vector3" and m:GetAttribute("Action") == "Breach" then
						Bp = onSand(live)
					end
				end
				if not Bp then
					return true
				end
				local run = flat(Bp - A)
				local len = run.Magnitude
				local dir = len > 0.01 and run.Unit or B.vfacing
				local side = V3(-dir.Z, 0, dir.X)
				local tail = Bp - dir * math.min(a.BodyLength, len)
				if not landed then
					local k = clamp((now - t0) / math.max(lockAt - t0, 0.05), 0, 1)
					local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 22, k))
					placeStrip(strip, tail, Bp, a.Width, 0.12, tail.Y + 0.07)
					strip.Transparency = locked and 0.2 or lerp(0.85, 0.45, k)
					for i, e in ipairs(edges) do
						local off = side * (a.Width / 2) * (i == 1 and 1 or -1)
						placeStrip(e, tail + off, Bp + off, locked and 0.9 or 0.55, 0.16, tail.Y + 0.1)
						e.Color = locked and LOCKED or WORM_GLOW
						e.Transparency = locked and 0 or lerp(0.7, 0.2, k * pulse)
					end
				end
				if now < launchAt then
					placeRing(launch, A + V3(0, 0.08, 0), a.Launch, 0.2, 0.5, lerp(0.7, 0.2, 0.5 + 0.5 * math.sin(now * 14)))
				elseif not launched then
					launched = true
					hideRing(launch)
					carve(B, A, a.Launch, 4, scarLife(B))
					burst(A + V3(0, 1, 0), WORM_SAND, 44, 42, 3.4, 1.2, true)
					flingRubble(A, 8, SAND_BITS, 0.8)
					shockRing(B, A, B.def.Size * 0.4, a.Launch * 1.6, 0.4, WORM_SAND)
					playSound(B.def, "Erupt", A, 1)
					kick(A, a.Launch, 1, -3)
				end
				if now >= lockAt and not locked then
					-- committed: the strip flashes, the ground along it shudders
					locked = true
					local near = nearestOnSegment(tail, Bp, myFloorPos(B))
					kick(near, a.Width, 0.35)
					for j = 0, 1 do
						burst(tail:Lerp(Bp, j) + V3(0, 0.5, 0), WORM_SAND, 6, 8, 1.4, 0.5, true)
					end
				end
				if now >= launchAt and now < landAt then
					local f = (now - launchAt) / a.Flight
					placeDisc(shadow, A:Lerp(Bp, f) + V3(0, 0.1, 0), B.def.Size * (0.6 + 0.6 * f), 0.1)
					shadow.Transparency = lerp(0.8, 0.45, f)
				else
					shadow.Transparency = 1
				end
				if now >= landAt and not landed then
					landed = true
					strip.Transparency = 1
					for _, e in ipairs(edges) do
						e.Transparency = 1
					end
					-- its whole body slams down along the strip, carving a trench
					local sc = newScar(B, "hole", scarLife(B) + 2)
					local n = math.max(2, math.floor(flat(Bp - tail).Magnitude / 7))
					for j = 0, n do
						scarHole(sc, tail:Lerp(Bp, j / n), 6.5, 2.6)
					end
					scarHole(sc, Bp, 10, 4.5) -- where its head drove into the sand
					for j = 0, 3 do
						burst(tail:Lerp(Bp, j / 3) + V3(0, 1, 0), WORM_SAND, 16, 26, 2.8, 0.9, true)
					end
					flingRubble(tail:Lerp(Bp, 0.5), 10, SAND_BITS, 0.9)
					local near = nearestOnSegment(tail, Bp, myFloorPos(B))
					playSound(B.def, "Crash", near, 1)
					kick(near, a.Width, 1.4, -4)
				end
				return true
			end,
			cleanup = function()
				strip:Destroy()
				for _, e in ipairs(edges) do
					e:Destroy()
				end
				removeRing(launch)
				shadow:Destroy()
			end,
		})
	end

	-- COIL: sand churning in a ring round you while it circles underneath, then
	-- (once its body is up) the crush zone inside the ring darkening as it
	-- tightens. At the crush: a crater where the head strikes down.
	local function coilMarks(B, C, t0)
		local a = B.def.Attacks.Coil
		C = onSand(C)
		local surfaceAt = t0 + a.Tell
		local crushAt = surfaceAt + a.Close
		local churn = newRing(40, WORM_SAND_DEEP, Enum.Material.Sand, 1)
		local rim = newRing(40, WORM_GLOW, Enum.Material.Neon, 1)
		local crush = newPart("CoilCrush", Enum.PartType.Cylinder, RGB(60, 30, 16), Enum.Material.SmoothPlastic, 1)
		local surfaced, crushed = false, false
		addTelegraph(B, {
			update = function(now)
				if now > crushAt + 0.1 then
					return false
				end
				if now < surfaceAt then
					local k = clamp((now - t0) / a.Tell, 0, 1)
					placeRing(churn, C + V3(0, 0.05, 0), a.Radius, 0.5 + 0.4 * math.sin(now * 20), a.Wall, lerp(0.85, 0.35, k))
					placeRing(rim, C + V3(0, 0.1, 0), a.Radius + a.Wall / 2 + 0.5, 0.25, 0.5, lerp(0.8, 0.15, k))
					crush.Transparency = 1
					return true
				end
				if not surfaced then
					surfaced = true
					hideRing(churn)
					hideRing(rim)
					for j = 0, 4 do
						local ang = j / 5 * math.pi * 2
						burst(C + V3(math.sin(ang), 0, math.cos(ang)) * a.Radius + V3(0, 1, 0), WORM_SAND, 10, 22, 2.4, 0.8, true)
					end
					playSound(B.def, "Erupt", C, 0.8)
					kick(C, a.Radius, 0.8, -2)
				end
				local u = clamp((now - surfaceAt) / a.Close, 0, 1)
				local r = a.Radius - (a.Radius - a.Crush) * u * u
				placeDisc(crush, C + V3(0, 0.07, 0), math.max(r - a.Wall / 2, 0.5) * 2, 0.1)
				crush.Transparency = lerp(0.8, 0.3, u)
				if now >= crushAt and not crushed then
					crushed = true
					crush.Transparency = 1
					carve(B, C, a.Crush + 2, 3, scarLife(B))
					shockRing(B, C, a.Crush, a.Radius, 0.35, WORM_SAND)
					burst(C + V3(0, 1, 0), WORM_SAND, 30, 30, 3, 1, true)
					playSound(B.def, "Crash", C, 1)
					kick(C, a.Radius, 1.3, -4)
				end
				return true
			end,
			cleanup = function()
				removeRing(churn)
				removeRing(rim)
				crush:Destroy()
			end,
		})
	end

	-- DEVOUR: a sinkhole opening under you - the sand really sinks away in
	-- stages - with arms of sand swirling down its sides into the dark pit at
	-- the bottom, the bite marked there, and it drags you in while it's open.
	local function devourFunnel(B, C, t0)
		local a = B.def.Attacks.Devour
		C = onSand(C)
		local biteAt = t0 + a.Tell
		local hole = newScar(B, "hole", math.max(biteAt - serverNow(), 0) + scarLife(B))
		local stages = { { 0.12, 0.55, 0.4 }, { 0.4, 0.8, 0.7 }, { 0.7, 1, 1 } } -- { when, size, depth }
		local done = 0
		local arms = {}
		for i = 1, 8 do
			arms[i] = newPart("FunnelArm", nil, WORM_SAND:Lerp(RGB(255, 240, 210), 0.3), Enum.Material.Sand, 1)
		end
		local pit = newPart("FunnelPit", Enum.PartType.Cylinder, RGB(24, 16, 10), Enum.Material.SmoothPlastic, 1)
		local rim = newRing(32, WORM_GLOW, Enum.Material.Neon, 1)
		local bite = newRing(24, WORM_GLOW, Enum.Material.Neon, 1)
		local last = nil
		addTelegraph(B, {
			update = function(now)
				if now >= biteAt then
					return false
				end
				local dt = last and math.clamp(now - last, 0, 0.1) or 0
				last = now
				local k = clamp((now - t0) / a.Tell, 0, 1)
				while done < #stages and k >= stages[done + 1][1] do
					done = done + 1
					scarHole(hole, C, a.Radius * stages[done][2], a.Depth * stages[done][3])
					burst(C + V3(0, 0.5, 0), WORM_SAND, 16, 10, 2.4, 0.8, true)
					kick(C, a.Radius, 0.4)
				end
				local open = a.Radius * ((done > 0) and stages[done][2] or 0.3)
				-- arms of sand swirling down its sides
				for i, arm in ipairs(arms) do
					local ang = i / #arms * math.pi * 2 + now * 2.6
					local p1 = C + V3(math.sin(ang), 0, math.cos(ang)) * open * 0.95
					local p2 = C + V3(math.sin(ang + 1), 0, math.cos(ang + 1)) * open * 0.3
					p1 = V3(p1.X, floorHeightAt(p1, C.Y) + 0.2, p1.Z)
					p2 = V3(p2.X, floorHeightAt(p2, C.Y) + 0.2, p2.Z)
					placeBar(arm, p1, p2, 1.4, 0.15)
					arm.Transparency = lerp(0.8, 0.25, k)
				end
				local bottom = floorHeightAt(C, C.Y)
				placeDisc(pit, V3(C.X, bottom + 0.15, C.Z), a.Bite * 1.4 * (0.4 + 0.6 * k), 0.1)
				pit.Transparency = lerp(0.6, 0.05, k)
				placeRing(rim, C + V3(0, 0.1, 0), open, 0.2, 0.5, lerp(0.8, 0.4, k))
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 30, k))
				local biteEdge = C + V3(a.Bite, 0, 0)
				placeRing(bite, V3(C.X, floorHeightAt(biteEdge, C.Y) + 0.15, C.Z), a.Bite, 0.3, 0.6, lerp(0.7, 0.05, k * pulse))
				dragMe(B, C, open, a.Pull[1], a.Pull[2], dt)
				return true
			end,
			cleanup = function()
				for _, arm in ipairs(arms) do
					arm:Destroy()
				end
				pit:Destroy()
				removeRing(rim)
				removeRing(bite)
			end,
		})
	end

	-- TAIL LASH. Its tail - the real end of its body, tapering to a bone spike -
	-- whips up out of a crater behind you and scythes round, low over the sand
	-- (the rest of it runs off under the sand to its head). It's a whip: the
	-- far end trails behind in the middle of the swing and cracks round at the
	-- end of it, and its tip tears a furrow through the sand as it goes. Before
	-- it comes, the sand heaves where it'll come up, and the fan it will sweep
	-- and the arc its tip will cut glow on the floor, lighting up the way it'll
	-- swing. In phase two it whips straight back again. BossService hits
	-- exactly this shape (lashAngle there): jump it, roll through it, or be out
	-- of reach.
	local function lashAngle(from, to, u, x)
		u = clamp(u, 0, 1)
		local span = to - from
		local trail = 0.13 * math.abs(span) * x ^ 1.6 * (4 * u * (1 - u)) ^ 2
		return from + span * (u * u * (3 - 2 * u)) - ((span >= 0) and trail or -trail)
	end

	local TAIL_SHARE = 0.5 -- how much of its body is tail (the rest stays under the sand)
	local S_TIP = 0.08 -- (where applyWormPose puts its first segment along its body)

	-- how thick it is along its length for a lash: thin and whippy for most of
	-- the tail, swelling back into its body where it comes out of the sand
	local function tailTaper(s)
		if s >= TAIL_SHARE then
			return 1.06 - 0.16 * s
		end
		local x = clamp((TAIL_SHARE - s) / (TAIL_SHARE - S_TIP), 0, 1) -- 1 = the tip
		if x >= 0.35 then
			return lerp(0.3, 0.2, (x - 0.35) / 0.65)
		end
		return lerp(0.3, 0.95, ((0.35 - x) / 0.35) ^ 1.5)
	end

	-- A lash at a moment: which swing, how far through it, which way, how far
	-- out of the sand the tail is, and the crack at the end of the swing
	local function lashState(L, now)
		local k = now - L.startAt
		local step = L.time + L.pause
		local i = clamp(math.floor(k / step) + 1, 1, L.sweeps)
		local into = k - (i - 1) * step
		local u = clamp(into / L.time, 0, 1)
		local f, g = L.from, L.to
		if i % 2 == 0 then
			f, g = g, f
		end
		local up = 1
		if k < 0 then
			up = clamp(1 + k / L.rise, 0, 1) -- bursting up, just before it swings
		elseif now > L.endAt then
			up = 1 - clamp((now - L.endAt) / 0.45, 0, 1) -- dropping back under
		end
		local after = into - L.time
		local crack = after > 0 and math.sin(math.min(after / 0.22, 1) * math.pi) * math.exp(-after * 5) or 0
		return i, u, f, g, smooth(up), crack
	end

	-- its body for a lash: s from its tail tip (0) to its head (1)
	local function lashPath(B, L, now)
		local g = B.def.Size * 0.64
		local A, R = L.anchor, L.reach
		local _, u, f, to, up, crack = lashState(L, now)
		local sign = (to >= f) and 1 or -1
		local swing = 4 * u * (1 - u) -- how fast it's going (nothing at either end of a swing)
		local back = V3(-math.sin(L.mid), 0, -math.cos(L.mid)) -- the way its body runs off under the sand
		return function(s)
			if s < TAIL_SHARE then
				local x = clamp((TAIL_SHARE - s) / (TAIL_SHARE - S_TIP), 0, 1)
				-- (the crack: its tip flicks on past the end of the swing, and back)
				local yaw = lashAngle(f, to, u, x) + sign * 0.16 * crack * x * x
				local thick = g * tailTaper(s)
				-- it heaves up in an arch where it comes out of the ground, then
				-- runs low along the sand (you can jump it), a ripple running out
				-- along it as it swings
				local h = thick * 0.45 + g * 0.45 * math.sin(math.pi * clamp(x / 0.35, 0, 1))
				h = h + math.sin(x * 8 - now * 20) * 0.7 * x * swing
				local y = h * up - (1 - up) * (thick + 3)
				return A + V3(math.sin(yaw) * x * R, y, math.cos(yaw) * x * R)
			end
			-- the rest of it: down the hole and away under the sand, to its head
			local b = (s - TAIL_SHARE) / (1 - TAIL_SHARE)
			return A + back * (b * 44) + V3(0, -g * 0.55 - b * g * 1.4, 0)
		end
	end

	local function tailLash(B, anchor, yaws, t0)
		local a = B.def.Attacks.TailLash
		anchor = onSand(anchor)
		local from, to = yaws.X, yaws.Y
		local phase = B.model:GetAttribute("Phase") or 1
		local sweeps = (type(a.Sweeps) == "table" and (a.Sweeps[phase] or a.Sweeps[1])) or 1
		local pause = a.Pause or 0.25
		local startAt = t0 + a.Tell
		local L = {
			anchor = anchor, from = from, to = to, mid = (from + to) / 2,
			startAt = startAt, endAt = startAt + sweeps * a.Time + (sweeps - 1) * pause,
			sweeps = sweeps, pause = pause, time = a.Time, reach = a.Reach, rise = 0.14,
		}
		B.lash = L -- (Poses.TailLash draws its body from this)
		local riseAt, goneAt = startAt - L.rise, L.endAt + 0.45
		local heave = newScar(B, "heave", math.max(riseAt - serverNow(), 0.1))
		local heaved = 0
		-- the warning, laid on the floor once: the fan it will sweep, and the
		-- arc its tip will cut (only their glow changes after that)
		local marks = {}
		for i = 1, 5 do
			local yaw = from + (to - from) * (i - 1) / 4
			local dir = V3(math.sin(yaw), 0, math.cos(yaw))
			local ray = newPart("LashRay", nil, WORM_GLOW, Enum.Material.Neon, 1)
			placeStrip(ray, anchor + dir * 3, anchor + dir * a.Reach, 0.35, 0.1, anchor.Y + 0.1)
			marks[#marks + 1] = { part = ray, order = (i - 1) / 4 }
		end
		local ARC = 12
		for k = 1, ARC do
			local y0 = from + (to - from) * (k - 1) / ARC
			local y1 = from + (to - from) * k / ARC
			local bar = newPart("LashRay", nil, WORM_GLOW, Enum.Material.Neon, 1)
			placeStrip(bar, anchor + V3(math.sin(y0), 0, math.cos(y0)) * (a.Reach + 0.5),
				anchor + V3(math.sin(y1), 0, math.cos(y1)) * (a.Reach + 0.5), 0.9, 0.1, anchor.Y + 0.1)
			marks[#marks + 1] = { part = bar, order = (k - 0.5) / ARC }
		end
		local spike = newPart("TailSpike", nil, BONE, Enum.Material.SmoothPlastic, 1)
		spike.Size = V3(0.9, 0.9, 3.6)
		local tipDust = newPart("TailDust", nil, WORM_SAND, nil, 1)
		tipDust.Size = V3(4, 1, 4)
		local spray = wormEmitter("Spray", tipDust, {
			Color = ColorSequence.new(WORM_SAND),
			LightInfluence = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(6, 16),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = V3(0, -35, 0),
			EmissionDirection = Enum.NormalId.Top,
		})
		local furrow, lastCut = nil, nil
		local sounded, cracked = 0, 0
		local came, warned = false, true
		addTelegraph(B, {
			update = function(now)
				if now > goneAt then
					return false
				end
				if now < riseAt then
					local k = clamp((now - t0) / a.Tell, 0, 1)
					if heaved < 2 and k >= (heaved + 1) * 0.35 then
						heaved = heaved + 1
						scarHeave(heave, anchor, 5 + heaved, 1.5 * heaved)
					end
					-- a pulse running the way it will swing, quicker as it comes
					local run = (now - t0) * lerp(1.2, 3, k)
					for _, m in ipairs(marks) do
						local glow = math.max(0, 1 - math.abs(((run - m.order) % 1) - 0.5) * 4)
						Fast.alpha(m.part, math.floor(lerp(0.85, lerp(0.5, 0.05, k), glow) * 20 + 0.5) / 20)
					end
					return true
				end
				if warned then
					warned = false
					for _, m in ipairs(marks) do
						Fast.alpha(m.part, 1)
					end
				end
				if not came then
					came = true
					carve(B, anchor, 6, 3, scarLife(B))
					burst(anchor + V3(0, 1, 0), WORM_SAND, 30, 30, 2.6, 0.9, true)
					flingRubble(anchor, 6, SAND_BITS, 0.7)
					kick(anchor, a.Reach, 0.7, -2)
					furrow = newScar(B, "hole", (goneAt - now) + scarLife(B))
				end
				local i, u, _, _, up = lashState(L, now)
				local swingAt = startAt + (i - 1) * (L.time + pause)
				if sounded < i and now >= swingAt - 0.1 then
					sounded = i
					playSound(B.def, "Sweep", anchor, 1)
				end
				-- its tip, where this frame's body put it: the spike on the end, the
				-- sand spraying off it, and the furrow it tears
				local pts = B.lastPoints
				local tip = B.action == "TailLash" and pts and pts[1]
				if tip and pts[2] and up > 0.05 then
					local along = tip - pts[2]
					along = along.Magnitude > 0.01 and along.Unit or V3(0, 0, 1)
					Fast.move(spike, CFrame.lookAt(tip + along * 1.8, tip + along * 4))
					Fast.alpha(spike, 0)
					local ground = V3(tip.X, anchor.Y, tip.Z)
					Fast.move(tipDust, CFrame.new(ground + V3(0, 0.5, 0)))
					local swinging = u > 0.02 and u < 0.98 and now < L.endAt
					spray.Rate = swinging and 40 or 0
					if swinging and furrow and (not lastCut or flat(ground - lastCut).Magnitude >= 10) then
						lastCut = ground
						scarHole(furrow, ground, 3.2, 1.2)
					end
					-- the crack at the end of each swing
					if cracked < i and now >= swingAt + L.time then
						cracked = i
						burst(ground + V3(0, 1, 0), WORM_SAND, 22, 26, 2.2, 0.7, true)
						shockRing(B, ground, 1, 9, 0.3, WORM_SAND)
						kick(ground, 14, 0.5, -1)
					end
				else
					Fast.alpha(spike, 1)
					spray.Rate = 0
				end
				Fast.flush()
				return true
			end,
			cleanup = function()
				if B.lash == L then
					B.lash = nil
				end
				for _, m in ipairs(marks) do
					m.part:Destroy()
				end
				spike:Destroy()
				tipDust:Destroy()
			end,
		})
	end

	-- TREMOR: dust rising off the whole floor as it thrashes, your view shuddering
	-- harder before each quake if you're on the sand, and at each quake the floor
	-- jumping and CRACKING OPEN in fissures running out from where it is.
	local function quakeEmitter(B)
		if B.quake and B.quake.Parent then
			return B.quakeEmitter
		end
		local arena = arenaOf(B)
		local center = arena and arena:GetAttribute("Center")
		local radius = (arena and arena:GetAttribute("SandRadius")) or 140
		if typeof(center) ~= "Vector3" then
			center = B.vpos
		end
		local holder = newPart("QuakeDust", nil, WORM_SAND, nil, 1)
		holder.Size = V3(radius * 1.6, 1, radius * 1.6)
		holder.CFrame = CFrame.new(V3(center.X, B.vpos.Y + 0.6, center.Z))
		B.quake = holder
		B.quakeEmitter = wormEmitter("Quake", holder, {
			Color = ColorSequence.new(WORM_SAND),
			LightInfluence = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(3, 11),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = V3(0, -9, 0),
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		return B.quakeEmitter
	end

	local function tremorShakes(B, t0)
		local a = B.def.Attacks.Tremor
		local dust = quakeEmitter(B)
		local done = t0 + a.Tell + (a.Quakes - 1) * a.Gap + 0.4
		local fired = {}
		addTelegraph(B, {
			update = function(now)
				if now > done then
					return false
				end
				if dust then
					dust.Rate = 18 * clamp((now - t0) / a.Tell, 0, 1)
				end
				local hrp = myRoot()
				local mine = hrp and player:GetAttribute("SpireFloor") == B.floor and not onStone(B, hrp.Position)
				for i = 1, a.Quakes do
					local hitAt = t0 + a.Tell + (i - 1) * a.Gap
					if mine and now > hitAt - 0.5 and now < hitAt and cameraKickEvent then
						cameraKickEvent:Fire(0.12 + 0.35 * (1 - (hitAt - now) / 0.5))
					end
					if now >= hitAt and not fired[i] then
						fired[i] = true
						if dust then
							dust:Emit(250)
						end
						-- a wave of sand racing out across the whole floor from it
						local wave = newRing(32, WORM_SAND, Enum.Material.Sand, 0.1)
						local w0, from = now, B.vpos
						addTelegraph(B, {
							update = function(n)
								local u = (n - w0) / 0.6
								if u >= 1 then
									return false
								end
								placeRing(wave, onSand(from), lerp(6, 140, easeOut(u)), 2.2 * (1 - u) + 0.2, 3.5, lerp(0.1, 1, u))
								return true
							end,
							cleanup = function()
								removeRing(wave)
							end,
						})
						-- fissures: the same on every screen (seeded from the moment it began)
						local origin = B.vpos
						local sc = newScar(B, "hole", scarLife(B) - 1)
						for f = 1, 3 do
							local seed = math.floor((t0 % 1000) * 10) + i * 7 + f * 13
							local ang = seeded(seed) * math.pi * 2
							local dir = V3(math.sin(ang), 0, math.cos(ang))
							local side = V3(-dir.Z, 0, dir.X)
							for k = 1, 4 do
								local wob = (seeded(seed + k) - 0.5) * 5
								scarHole(sc, origin + dir * (4 + k * 9) + side * wob, 3.2, 2.2)
							end
						end
						playSound(B.def, "Crash", B.vpos, 0.7)
						if mine then
							kick(hrp.Position, 10, 1.1, -3)
							burst(hrp.Position - V3(0, 2.8, 0), WORM_SAND, 12, 14, 1.8, 0.6, true)
						elseif hrp and cameraKickEvent and player:GetAttribute("SpireFloor") == B.floor then
							cameraKickEvent:Fire(0.25) -- you feel it through the stone, but it can't reach you
						end
					end
				end
				return true
			end,
			cleanup = function()
				if dust then
					dust.Rate = 0
				end
			end,
		})
	end

	-- UNDERMINE: a glowing ring round the platform it's circling under, sand
	-- spouting up round its edge faster and faster (the cracks on top glow too -
	-- the server lights those). The platform breaking is drawn further down.
	local function undermineMarks(B, C, radius, t0)
		local a = B.def.Attacks.Undermine
		C = onSand(C)
		local breakAt = t0 + a.Tell
		local ring = newRing(32, WORM_GLOW, Enum.Material.Neon, 1)
		local nextPuff = 0
		addTelegraph(B, {
			update = function(now)
				if now >= breakAt then
					return false
				end
				local k = clamp((now - t0) / a.Tell, 0, 1)
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 28, k))
				placeRing(ring, C + V3(0, 0.1, 0), radius + 1.5, 2.4, 0.6, lerp(0.8, 0.05, k * pulse))
				if now >= nextPuff then
					nextPuff = now + lerp(0.35, 0.1, k)
					local ang = math.random() * math.pi * 2
					burst(C + V3(math.sin(ang), 0, math.cos(ang)) * (radius + 2) + V3(0, 1, 0), WORM_SAND, 8, 12, 1.6, 0.6, true)
				end
				local hrp = myRoot()
				if hrp and k > 0.4 and cameraKickEvent and flat(hrp.Position - C).Magnitude < radius + 2 then
					cameraKickEvent:Fire(0.1 + 0.25 * k) -- the stone shaking under your feet
				end
				return true
			end,
			cleanup = function()
				removeRing(ring)
			end,
		})
	end

	----------------------------------------------------------------------
	-- Its poses
	----------------------------------------------------------------------
	-- Swimming under the sand, its back arching out as it goes.
	function Poses.Burrow(B, t, P)
		underPose(B, P, 1, HUMP_EVERY)
	end

	-- The dive's arc: from deep in the hole it stands in, up and over, and down
	-- into the sand at the spot ahead - and on down under it - measured along
	-- its length, so its body can slide along it.
	local function diveArc(O, into, H)
		local F = flat(into - O)
		F = F.Magnitude > 0.5 and F.Unit or V3(0, 0, 1)
		local q0, q1 = O - V3(0, 26, 0), O + V3(0, H, 0) - F * 2
		local q2, q3 = into + V3(0, H, 0) + F * 2, into + F * 8 - V3(0, 30, 0)
		local pts, lens, total = {}, { 0 }, 0
		for i = 0, 28 do
			pts[i + 1] = bezier(q0, q1, q2, q3, i / 28)
			if i > 0 then
				total = total + (pts[i + 1] - pts[i]).Magnitude
				lens[i + 1] = total
			end
		end
		local out = (pts[29] - pts[28]).Unit
		local lo = 1
		local function at(dist)
			if dist <= 0 then
				return q0 + V3(0, dist, 0) -- (the end of it still down in the hole)
			elseif dist >= total then
				return pts[29] + out * (dist - total) -- (gone on down under the sand)
			end
			if lens[lo] > dist then
				lo = 1
			end
			while lens[lo + 1] < dist do
				lo = lo + 1
			end
			return pts[lo]:Lerp(pts[lo + 1], (dist - lens[lo]) / math.max(lens[lo + 1] - lens[lo], 1e-3))
		end
		return at, total
	end

	-- Going back under. From standing, it rears back a little, then arches over
	-- and plunges head-first into the sand a little way ahead (where
	-- BossService sends it: ActA), its whole body pouring in after its head
	-- through the same hole, like a diving serpent. A coil (after a Coil, or
	-- just woken in its coils round the seal) sinks where it lies.
	local DIVE_BODY = 100 -- (about its length standing up out of the sand)
	function Poses.Dive(B, t, P)
		local T = B.def.Hunt.DiveTime
		local k = clamp(t / T, 0, 1)
		if (B.prevAction == "Coil" or B.prevAction == "Wake") and B.coilRest then
			local c = B.coilRest
			P.girth = c.g
			P.path = coilPath(c.C, c.r, c.g, c.headUp, c.rise or 1, c.thEnd, smooth(k) * c.g * 3)
			-- (where it "is" slips on under the sand to where it'll swim from next -
			-- the spot BossService sends it to - so it doesn't jump there after)
			local into = B.model:GetAttribute("ActA")
			P.override = typeof(into) == "Vector3" and c.C:Lerp(V3(into.X, c.C.Y, into.Z), smooth(k)) or c.C
			P.noPush, P.noShadow = true, true
			return
		end
		-- the arc, worked out once when it starts (and again if the spot it's
		-- diving at arrives a moment after the move does)
		local into = B.model:GetAttribute("ActA")
		local D = B.dive
		if not D or D.start ~= B.actionStart or D.into ~= into then
			local O = (D and D.start == B.actionStart) and D.O or B.vpos
			local target = typeof(into) == "Vector3" and V3(into.X, O.Y, into.Z) or O + B.vfacing * 18
			local at, total = diveArc(O, target, B.def.Size * 1.9)
			local run = flat(target - O)
			D = {
				start = B.actionStart, into = into, O = O, at = at, total = total,
				F = run.Magnitude > 0.5 and run.Unit or B.vfacing, span = run.Magnitude,
			}
			B.dive = D
		end
		-- where its head is along the arc: it rears back, then plunges - faster
		-- and faster - until every bit of it has gone in
		local head0 = DIVE_BODY - 10
		local head
		if k < 0.22 then
			head = head0 - 6 * math.sin(k / 0.22 * math.pi / 2)
		else
			local q = (k - 0.22) / 0.78
			head = (head0 - 6) + (D.total + DIVE_BODY + 5 - (head0 - 6)) * q ^ 1.5
		end
		local at = D.at
		P.path = function(s)
			return at(head - (1 - s) * DIVE_BODY)
		end
		-- where it "is" goes with its head, from the old hole to the new one (so
		-- it carries on swimming from where it went in, without a jump)
		local over = clamp(flat(at(head) - D.O):Dot(D.F), 0, D.span)
		P.override = D.O + D.F * over
		P.mouth = 0.6 * (1 - k)
		P.eyes = 1
		P.sink = smooth(clamp((k - 0.5) / 0.5, 0, 1)) -- (the glow in its throat going under with it)
		P.noShadow = true
	end

	-- Bursting up out of the sand, maw wide, then standing there: EXPOSED.
	function Poses.Erupt(B, t, P)
		local spot = B.model:GetAttribute("ActA")
		if typeof(spot) == "Vector3" then
			P.override = spot
		end
		local k = clamp(t / 0.38, 0, 1)
		P.sink = 1 - easeOut(k)
		P.mouth = t < 0.38 and 1 or clamp(1 - (t - 0.38) / 0.6, 0, 1)
		P.flare = clamp(1 - t / 0.9, 0, 1)
		P.lean = -0.35 * (1 - smooth((t - 0.25) / 0.6))
		P.lift = 6 * spring(t, 4, 9)
		P.spill = 32 * clamp(1 - t / 1.2, 0, 1) + 4 -- sand pouring off it
	end

	-- Racing after you under the sand (arching often), then waiting under the heave.
	function Poses.Ambush(B, t, P)
		local locked = typeof(B.model:GetAttribute("ActA")) == "Vector3"
		underPose(B, P, locked and 0.4 or 1.3, not locked and 42 or nil)
	end

	-- Leaping out in an arc toward the end of the strip (which follows you until
	-- it locks), crashing down along it, lying stuck in its trench, then sliding
	-- into the sand at the far end.
	function Poses.Breach(B, t, P)
		local a = B.def.Attacks.Breach
		local m = B.model
		local A, Bp = m:GetAttribute("ActA"), m:GetAttribute("ActB")
		local tell = B.breachTell or a.Tell
		if typeof(A) ~= "Vector3" or typeof(Bp) ~= "Vector3" or t < tell then
			underPose(B, P, 1.4, 30)
			P.shake = 0.25 * clamp(t / tell, 0, 1)
			P.stage = "under"
			return
		end
		P.stage = "leap"
		local last = (m:GetAttribute("ActN") or 1) == 1
		local run = flat(Bp - A)
		local len = math.max(run.Magnitude, 1)
		local dir = run.Magnitude > 0.01 and run.Unit or B.vfacing
		local g = B.def.Size * 0.64
		local fl = t - tell
		local head, arc = len, 0
		if fl < a.Flight then
			local u = fl / a.Flight
			head = u * len
			arc = 1 - smooth((u - 0.55) / 0.45) -- the arc flattens as it comes down
			P.mouth, P.flare = 1 - u * 0.5, 1 - u
			P.spill = 28 -- sand streaming off it in the air
		else
			local slideAt = m:GetAttribute("ActT")
			local now = (B.actionStart or 0) + t
			if typeof(slideAt) == "number" and now >= slideAt then
				local slide = last and a.Slide or a.Slide * 0.5
				head = len + clamp((now - slideAt) / slide, 0, 1) * (a.BodyLength + 12)
			end
			P.eyes = last and 0.6 or 1
			P.spill = 6
		end
		local BL, H = a.BodyLength, a.Height
		P.path = function(s)
			local x = head - (1 - s) * BL -- how far along the leap this bit of it is
			local lie = g * 0.2 -- (lying down in its trench)
			if x < 0 then
				return A + V3(0, lie + x, 0) -- still coming up out of the launch hole
			elseif x > len then
				return Bp + V3(0, lie - (x - len), 0) -- gone down the far hole
			end
			local v = x / len
			return A + dir * x + V3(0, lie + H * 4 * v * (1 - v) * arc, 0)
		end
		P.facing = dir
		P.noPush, P.noShadow = true, true
	end

	-- Circling you under the sand (its back arching out round you), then coiled
	-- round you with its head reared over the middle, tightening, striking down,
	-- and lying there coiled (EXPOSED).
	function Poses.Coil(B, t, P)
		local a = B.def.Attacks.Coil
		local C = B.model:GetAttribute("ActA")
		if typeof(C) ~= "Vector3" then
			underPose(B, P, 1, nil)
			return
		end
		if not B.coilAng then
			local off = flat(B.vpos - C)
			B.coilAng = off.Magnitude > 1 and math.atan2(off.X, off.Z) or 0
			B.coilFromR = off.Magnitude
		end
		local lap = math.pi * 2 * 0.94
		if t < a.Tell then
			-- circling you under the sand (BossService moves it round: its body
			-- follows exactly where it has been)
			underPose(B, P, 1.3, 24)
			P.stage = "circle"
			return
		end
		P.stage = "ring"
		local e = t - a.Tell
		local u = clamp(e / a.Close, 0, 1)
		local r = a.Radius - (a.Radius - a.Crush) * u * u
		local g = a.Wall + 2
		local strike = clamp((e - a.Close + 0.16) / 0.16, 0, 1)
		local headUp = lerp(g * 2.8, g * 0.55, strike * strike)
		local thEnd = B.coilAng + lap
		-- (it all bursts up out of the sand together: head and neck too)
		local up = smooth(clamp(e / 0.35, 0, 1))
		P.girth = g
		P.path = coilPath(C, r, g, headUp, clamp(e / 0.3, 0, 1), thEnd, (1 - up) * (headUp + g * 1.5))
		P.override = C
		P.mouth = (strike > 0 and strike < 1) and 1 or (0.35 + 0.3 * u)
		P.flare, P.eyes = u, 1
		P.spill = 12
		P.noPush, P.noShadow = true, true
		B.coilRest = { C = C, r = r, g = g, headUp = headUp, thEnd = thEnd }
	end

	-- Under the sinkhole, waiting (the funnel is all you see). (It swims to the
	-- middle of it under the sand - BossService moves it there.)
	function Poses.Devour(B, t, P)
		underPose(B, P, 0, nil)
	end

	-- Under the sand, getting behind you - then its tail whips up out of the sand
	-- and round (its own body, tapering to a spike: see tailLash).
	function Poses.TailLash(B, t, P)
		local L = B.lash
		local now = (B.actionStart or 0) + t
		if not L or now < L.startAt - L.rise then
			underPose(B, P, 0.4, nil)
			P.stage = "under"
			return
		end
		-- its tail, whipping round (see tailLash); its head stays under the sand
		P.stage = "lash"
		P.path = lashPath(B, L, now)
		P.taper = tailTaper
		P.girth = B.def.Size * 0.64
		P.override = L.anchor
		P.sink, P.ridge, P.eyes = 1, 0, 0
		P.noShadow = true
	end

	-- Thrashing underground.
	function Poses.Tremor(B, t, P)
		underPose(B, P, 0.9 + 0.35 * math.sin(t * 14), nil)
		P.shake = 0.4
	end

	-- Circling under a platform, its back arching out all the way round it.
	function Poses.Undermine(B, t, P)
		-- (BossService moves it round under the platform: its body follows)
		underPose(B, P, 1.1, 26)
	end

	----------------------------------------------------------------------
	-- Asleep in the middle of the arena, and waking
	----------------------------------------------------------------------
	-- Until someone comes near, it lies coiled round the seal at the heart of
	-- the arena, half sunk in the sand, its head laid in the middle of its
	-- coils (looking toward the gate), breathing slowly: the thing you see as
	-- you come in, and walk up to. Come within WakeRange (or punch it) and it
	-- wakes: it stirs, its head rears up out of the coils and roars at you -
	-- and then the coils sink and it's under the sand, hunting.
	-- (Gloomgut keeps its own sleeping and waking.)
	local SLEEP_R = 19 -- how far out from the seal its coils lie
	local function sleepCoil(B, t, rear, stir, down)
		local g = B.def.Size * 0.56
		local C = B.vpos
		if not B.sleepFace then
			-- its neck comes over from the far side, so its head faces the way
			-- it was put down facing (the gate)
			local root = B.model.PrimaryPart
			local f = root and flat(root.CFrame.LookVector) or B.vfacing
			f = f.Magnitude > 0.01 and f.Unit or V3(0, 0, 1)
			B.sleepFace = math.atan2(-f.X, -f.Z)
		end
		-- (breathing only while you're in its arena: elsewhere nobody sees it)
		local breathe = (player:GetAttribute("SpireFloor") == B.floor) and math.sin(t * 2 * math.pi / 5.5) or 0
		local headUp = lerp(g * 0.62 + breathe * 0.35, g * 2.9, rear) + math.sin(t * 23) * stir * 0.6
		B.coilRest = { C = C, r = SLEEP_R, g = g, headUp = headUp, thEnd = B.sleepFace, rise = 0.8 }
		return coilPath(C, SLEEP_R, g * (1 + 0.025 * breathe), headUp, 0.8, B.sleepFace, down or 0), g
	end

	function Poses.Dormant(B, t, P)
		-- (back from a fight: its coils come up out of the sand and settle)
		local up = smooth(clamp(t / 1.6, 0, 1))
		local path, g = sleepCoil(B, t, 0, 0, (1 - up) * B.def.Size * 1.4)
		P.path, P.girth = path, g
		P.eyes, P.mouth = 0, 0
		P.spill = 6 * (1 - up)
		P.noShadow = true
		P.solid = up > 0.9 -- (not while its coils are still coming up out of the sand)
	end

	function Poses.Wake(B, t, P)
		local u = clamp(t / B.def.WakeTime, 0, 1)
		local stir = u < 0.3 and u / 0.3 or math.max(0, 1 - (u - 0.3) * 6) -- its coils shudder as it stirs
		local rear = easeOutBack(clamp((u - 0.28) / 0.35, 0, 1)) -- then its head comes up
		local path, g = sleepCoil(B, t, rear, stir)
		P.path, P.girth = path, g
		P.eyes = clamp((u - 0.2) / 0.1, 0, 1)
		if u > 0.5 and u < 0.85 then
			P.mouth = math.sin((u - 0.5) / 0.35 * math.pi) -- the roar
			P.flare = P.mouth
		end
		P.spill = 10 * stir + 14 * clamp(rear, 0, 1) * (1 - u) -- sand pouring off its coils
		P.noShadow = true
	end

	-- You can't walk through it. Every piece of its body that's out of the
	-- sand is solid: walk into it - or let it swim into you - and you're
	-- shoved out to its side, like bumping into a wall. Its back arching out
	-- as it swims, its coil round you, its neck and head, its body lying in its
	-- trench, its sleeping coils. (Never up in the air above you: you can run
	-- under its head.) The one way THROUGH it is a roll: you're untouchable for
	-- the length of it (the server says the same), and that's how you get out
	-- of its coil.
	local sandOnly = RaycastParams.new()
	sandOnly.FilterType = Enum.RaycastFilterType.Include
	sandOnly.FilterDescendantsInstances = { Workspace:FindFirstChildOfClass("Terrain") }
	function pushOutOfWorm(B, hrp, P)
		local pts, gs = B.lastPoints, B.segGirths
		if P.solid == false or not pts or not gs then
			return
		end
		local char = hrp.Parent
		if char and char:FindFirstChild("RollIframes") then
			return -- mid-roll (CombatClient's glow while you're untouchable)
		end
		local pos = hrp.Position
		local feet, top = pos.Y - 2.6, pos.Y + 2.2
		local moved = false
		for _ = 1, 2 do -- (twice: pushed out of one piece of it into the next is caught)
			for i = 1, #pts do
				local c, r = pts[i], (gs[i] or 0) * 0.5
				if r > 0.5 and c.Y + r * 0.85 > feet and c.Y - r * 0.85 < top then
					local off = flat(pos - c)
					local d = off.Magnitude
					local want = r * 0.9 + 1.4
					if d < want then
						local out = d > 0.05 and off / d or B.vfacing
						pos = V3(c.X, pos.Y, c.Z) + out * want
						moved = true
					end
				end
			end
		end
		if moved then
			-- (a quick shove, not a jump: at most 3 studs a frame, which is still
			-- far faster than anyone walks into it)
			local shove = pos - hrp.Position
			if shove.Magnitude > 3 then
				pos = hrp.Position + shove.Unit * 3
			end
			-- and never into the side of a crater: if the sand where you'd land
			-- is higher than your feet, you land on top of it instead
			local hit = Workspace:Raycast(pos + V3(0, 8, 0), V3(0, -14, 0), sandOnly)
			if hit and hit.Position.Y > pos.Y - 2.2 then
				pos = V3(pos.X, hit.Position.Y + 3.1, pos.Z)
			end
			hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.Position)
		end
	end

	----------------------------------------------------------------------
	-- Its one-off moments (sounds, bursts, craters) and the warnings it places
	----------------------------------------------------------------------
	function Starts.Dive(B, t0)
		local T = B.def.Hunt.DiveTime
		B.lastHump = (B.odo or 0) - HUMP_EVERY * 0.5 -- (its back arches up soon after it goes under)
		at(B, t0 + T * 0.2, function()
			playSound(B.def, "Dive", B.vpos, 0.8)
		end)
		-- the sand bursting where its head plunges in, and pouring in after it
		local function where()
			local into = B.model:GetAttribute("ActA")
			return typeof(into) == "Vector3" and onSand(into) or B.vpos
		end
		at(B, t0 + T * 0.55, function()
			if B.prevAction == "Coil" or B.prevAction == "Wake" then
				return -- (a coil just sinks where it lies)
			end
			local spot = where()
			carve(B, spot, 7, 3.5, scarLife(B))
			burst(spot + V3(0, 1, 0), WORM_SAND, 30, 26, 2.8, 1, true)
			shockRing(B, spot, B.def.Size * 0.3, B.def.Size * 0.9, 0.35, WORM_SAND)
			kick(spot, 20, 0.5)
		end)
		at(B, t0 + T * 0.85, function()
			burst(where() + V3(0, 1, 0), WORM_SAND, 14, 14, 2.2, 0.8, true)
		end)
	end

	function Starts.Erupt(B, t0)
		at(B, t0, function()
			local spot = B.model:GetAttribute("ActA")
			spot = typeof(spot) == "Vector3" and spot or B.vpos
			-- it bursts out of a crater it blows in the sand
			carve(B, spot, 13, 5, scarLife(B))
			burst(spot + V3(0, 1, 0), WORM_SAND, 44, 40, 3.2, 1.2, true)
			burst(spot + V3(0, 0.5, 0), WORM_SAND_DEEP, 20, 24, 2.4, 0.8)
			flingRubble(spot, 10, SAND_BITS, 1)
			shockRing(B, spot, B.def.Size / 2, B.def.Size * 1.1, 0.4, WORM_SAND)
			playSound(B.def, "Erupt", spot, 1)
			kick(spot, 20, 1.1, -4)
		end)
	end

	function Starts.Breach(B, t0)
		-- a leap straight after another takes off faster
		local a = B.def.Attacks.Breach
		B.breachTell = (B.prevAction == "Breach") and a.ChainTell or a.Tell
	end

	function Starts.Coil(B, t0)
		B.coilAng, B.coilRest = nil, nil
	end

	function Starts.Devour(B, t0)
		at(B, t0 + 0.05, function()
			playSound(B.def, "Devour", B.vpos, 1)
		end)
	end

	function Starts.Tremor(B, t0)
		at(B, t0 + 0.05, function()
			playSound(B.def, "Roar", B.vpos, 1)
		end)
		tremorShakes(B, t0)
	end

	function Starts.Undermine(B, t0)
		B.underAng = nil
		at(B, t0 + 0.05, function()
			playSound(B.def, "Roar", B.vpos, 0.6)
		end)
	end

	function SlotSpawns.Ambush(B, i, spot)
		if i == 1 then
			local eruptAt = tonumber(B.model:GetAttribute("ActN")) or (serverNow() + B.def.Attacks.Ambush.Lock)
			ambushMark(B, spot, eruptAt)
		end
	end

	function SlotSpawns.Breach(B, i, spot, t0)
		if i == 2 then
			breachStrip(B, t0, B.breachTell or B.def.Attacks.Breach.Tell)
		end
	end

	function SlotSpawns.Coil(B, i, spot, t0)
		if i == 1 then
			coilMarks(B, spot, t0)
		end
	end

	function SlotSpawns.Devour(B, i, spot, t0)
		if i == 1 then
			devourFunnel(B, spot, t0)
		end
	end

	function SlotSpawns.TailLash(B, i, spot, t0)
		local anchor = B.model:GetAttribute("ActA")
		if i == 2 and typeof(anchor) == "Vector3" then
			tailLash(B, anchor, spot, t0) -- (slot 2 isn't a place: it's the sweep's start and end angles)
		end
	end

	function SlotSpawns.Undermine(B, i, spot, t0)
		if i == 1 then
			undermineMarks(B, spot, tonumber(B.model:GetAttribute("ActN")) or 10, t0)
		end
	end

	----------------------------------------------------------------------
	-- The arena answering it
	----------------------------------------------------------------------
	-- What stands in the arena trembles as it swims underneath: pillars, braziers,
	-- the columns on the platforms. (Only on your screen,
	-- and only by a hair - enough to see, never enough to trip you.)
	local SHAKERS = {
		SandPillar = true, SandPillarBand = true, SandPillarBreak = true, FallenDrum = true,
		BrazierStand = true, BrazierBowl = true, BrazierFoot = true,
		PlatformColumn = true, PlatformColumnBase = true, DuneRock = true,
		LairStone = true, LairStoneCap = true, LairGlyph = true, LairGlyphMark = true,
	}
	local function stepTremble(B, near)
		if not B.shakers or (#B.shakers == 0 and os.clock() > (B.shakerLook or 0)) then
			B.shakers = {}
			B.shakerLook = os.clock() + 3
			local arena = arenaOf(B)
			if arena then
				for _, d in ipairs(arena:GetDescendants()) do
					if d:IsA("BasePart") and SHAKERS[d.Name] then
						table.insert(B.shakers, { part = d, cf = d.CFrame })
					end
				end
			end
		end
		-- (a dozen times a second is plenty for a tremble, and it's all moved in one go)
		if os.clock() < (B.nextTremble or 0) then
			return
		end
		B.nextTremble = os.clock() + 0.08
		local parts, cframes = {}, {}
		for _, s in ipairs(B.shakers) do
			local p = s.part
			if p.Parent then
				local d = near and flat(s.cf.Position - near).Magnitude or math.huge
				if d < 34 then
					local k = (1 - d / 34) * 0.3
					parts[#parts + 1], cframes[#cframes + 1] = p, s.cf + V3((math.random() - 0.5) * k, 0, (math.random() - 0.5) * k)
					s.moved = true
					if k > 0.15 and math.random() < 0.01 then
						burst(V3(s.cf.X, B.vpos.Y + 0.5, s.cf.Z), WORM_SAND, 4, 5, 1.2, 0.6, true)
					end
				elseif s.moved then
					parts[#parts + 1], cframes[#cframes + 1] = p, s.cf
					s.moved = false
				end
			end
		end
		if #parts > 0 then
			pcall(function()
				Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end

	-- The middle of the dunes (where the seal caves in: the whirlpool). Looked
	-- for again until it's found - the arena might not have loaded in yet.
	local function sinkCenter(B)
		if not B.sinkCenter and os.clock() >= (B.sinkLook or 0) then
			B.sinkLook = os.clock() + 1
			for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
				if h:GetAttribute("Floor") == B.floor and h:IsA("BasePart") then
					B.sinkCenter = h.Position
				end
			end
		end
		return B.sinkCenter
	end

	local rehearse -- (below, with the rest of the warming up)

	-- Every frame, for the worm:
	--  * the warm-up, the moment you arrive in its arena (see rehearse)
	--  * the RUMBLE: each time the sand bucks round it (BossService's pulses)
	--    the ring shows how far it reaches, and your view thumps if it's close
	--    (plus a low looping "Worm Rumble" sound while it's near, if you've added one)
	--  * the WHIRLPOOL in phase two: the bowl in the middle drags you down
	--  * the whirlpool's sand spiralling down the sides of the bowl
	--  * the arena trembling as it passes under things
	function stepWormSenses(B, dt, here, awake, state)
		if here and not B.rehearsed then
			B.rehearsed = true
			rehearse(B)
		elseif not here then
			B.rehearsed = nil -- (and again next time you come)
		end
		local hrp = myRoot()
		local under = B.model:GetAttribute("Submerged") == true
		-- (Config.Bosses[2].Rumble: Range = how close before you feel it, Shake =
		-- how hard each thump knocks your view)
		local R = B.def.Rumble or {}
		local range, strength = R.Range or 40, R.Shake or 0.45
		local want = 0
		if here and awake and hrp and under then
			local d = flat(hrp.Position - B.vpos).Magnitude
			want = clamp(1 - (d - 8) / range, 0, 1)
		end
		B.rumble = (B.rumble or 0) + (want - (B.rumble or 0)) * math.min(1, dt * 4)
		-- Each pulse of the rumble (BossService sends one every Rumble.Every
		-- seconds as it swims, and hurts whoever is on the sand inside
		-- Rumble.Radius): the sand jumps in a ring round its ridge - that ring is
		-- how far it reaches - and you feel it in your view if it's close
		local pulseT = B.model:GetAttribute("RumbleT")
		if pulseT ~= B.rumbleSeen then
			B.rumbleSeen = pulseT
			local at = B.model:GetAttribute("RumbleP")
			if type(pulseT) == "number" and typeof(at) == "Vector3" and serverNow() - pulseT < 0.5 and here then
				local reach = R.Radius or 16
				local c = onSand(at)
				shockRing(B, c, 3, reach, 0.35, WORM_SAND)
				for i = 1, 8 do
					local a = i / 8 * math.pi * 2
					burst(c + V3(math.sin(a) * reach * 0.8, 0.5, math.cos(a) * reach * 0.8), WORM_SAND, 4, 14, 1.6, 0.5, true)
				end
				if hrp and cameraKickEvent then
					local d = flat(hrp.Position - c).Magnitude
					if d < range then
						cameraKickEvent:Fire(strength * (d <= reach and 1 or 0.35 + 0.4 * (1 - d / range)))
					end
				end
			end
		end
		if B.rumble > 0.55 and hrp and os.clock() > (B.nextPuff or 0) then
			B.nextPuff = os.clock() + 0.4
			burst(hrp.Position - V3((math.random() - 0.5) * 4, 2.6, (math.random() - 0.5) * 4), WORM_SAND, 5, 6, 1.1, 0.5, true)
		end
		-- the low sound (looked for every couple of seconds, not every frame)
		local name = B.def.Sounds and B.def.Sounds.Rumble
		if B.rumble > 0.01 and name and not B.rumbleSound and os.clock() > (B.rumbleLook or 0) then
			B.rumbleLook = os.clock() + 2
			local template = findSound(name)
			if template then
				local s = template:Clone()
				s.Looped = true
				s.Volume = 0
				s.SoundGroup = soundGroup("Effects")
				s.Parent = game:GetService("SoundService")
				s:Play()
				B.rumbleSound = s
			end
		end
		if B.rumbleSound then
			B.rumbleSound.Volume = 0.8 * B.rumble * ((Config.Audio and Config.Audio.BossSounds) or 0.85)
			if B.rumble <= 0.01 then
				B.rumbleSound:Destroy()
				B.rumbleSound = nil
			end
		end
		-- you arrived after the seal caved in: the pit is dug for you now
		if B.sealDown and here and not B.bowl and Terrain and B.def.Scars and B.def.Scars.Terrain and os.clock() > (B.bowlTry or 0) then
			B.bowlTry = os.clock() + 3
			B.sealDown = false
			collapseSeal(B, true, true)
		end
		-- the whirlpool
		local W = B.def.Whirlpool
		local center = sinkCenter(B)
		if W and center and here and B.phase2Look and state == "Fighting" then
			dragMe(B, center, W.Radius, W.Pull[1], W.Pull[2], dt)
		end
		if B.vortex then
			local v = B.vortex
			local spin = os.clock() * 0.9
			for _, s in ipairs(v.arms) do
				local function pt(k)
					local r = v.radius * (1 - k * 0.85)
					local ang = s.arm / 3 * math.pi * 2 + k * 2.6 + spin
					local p = v.center + V3(math.sin(ang) * r, 0, math.cos(ang) * r)
					return V3(p.X, floorHeightAt(p, v.center.Y) + 0.25, p.Z)
				end
				placeBar(s.part, pt(s.j / 8), pt((s.j + 1) / 8), 2.8 - s.j * 0.2, 0.15)
			end
		end
		-- the arena trembling as it passes underneath
		stepTremble(B, (here and awake and under) and B.vpos or nil)
	end

	----------------------------------------------------------------------
	-- The platforms (the dunes' own pieces)
	----------------------------------------------------------------------
	-- A platform shattering (undermined: it burst up through it)
	local platformsSeen = {}
	local function trackPlatform(pm)
		if platformsSeen[pm] or not pm:IsA("Model") then
			return
		end
		platformsSeen[pm] = true
		local function where()
			local slab = pm:FindFirstChild("PlatformSlab")
			return slab and V3(slab.Position.X, slab.Position.Y - 0.85, slab.Position.Z)
		end
		pm:GetAttributeChangedSignal("Cracks"):Connect(function()
			local c, spot = pm:GetAttribute("Cracks"), where()
			if c and c > 0 and spot then
				burst(spot + V3(0, 2, 0), STONE_BITS[1], 16, 16, 1.6, 0.7, true)
			end
		end)
		pm:GetAttributeChangedSignal("Broken"):Connect(function()
			local spot = where()
			if pm:GetAttribute("Broken") and spot then
				flingRubble(spot, 16)
				burst(spot + V3(0, 1, 0), WORM_SAND, 40, 30, 3.2, 1.1, true)
				local def = Config.Bosses[pm:GetAttribute("Floor") or 2]
				if def then
					playSound(def, "Crash", spot, 1)
				end
				kick(spot, 20, 1.2, -4)
			end
		end)
	end

	for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
		trackPlatform(pm)
	end
	CollectionService:GetInstanceAddedSignal("DunePlatform"):Connect(trackPlatform)

	----------------------------------------------------------------------
	-- Warming up
	----------------------------------------------------------------------
	-- Everything the fights play is fetched well before it's needed, so nothing
	-- stalls, or plays silent, the first time it happens:
	--  * every boss sound and song, a couple of seconds after you join (in the
	--    background), and again as you arrive in the worm's arena
	--  * the worm's whole fight rehearsed as you arrive (see rehearse below)
	--  * the particle textures the sand and slime are drawn with
	--  * the first time you arrive in a Spire arena, every material the fight
	--    draws with is shown to your screen for a moment, too small to see
	-- (The arenas themselves are loaded for you by SpireService as soon as you
	-- open the Spire menu.)
	local ContentProvider = game:GetService("ContentProvider")
	local function warmSounds()
		local list, seen = {}, {}
		local function add(name)
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				local sound = findSound(name)
				if sound then
					list[#list + 1] = sound
				end
			end
		end
		for _, def in pairs(Config.Bosses or {}) do
			for key, name in pairs(def.Sounds or {}) do
				add(name)
				add("Boss " .. key)
			end
			add(def.Music)
			add(def.VictorySound)
		end
		for _, key in ipairs({ "Wake", "Slam", "Wave", "Spit", "Splat", "Lunge", "Wail", "Erupt", "Break", "Death" }) do
			add("Boss " .. key) -- (what Mireworm borrows when it has no sound of its own)
		end
		add(Config.AcidRain and Config.AcidRain.Sound)
		for _, f in ipairs((Config.Spire and Config.Spire.Floors) or {}) do
			add(f.ambience and f.ambience.Sound)
		end
		list[#list + 1] = "rbxasset://textures/particles/smoke_main.dds"
		list[#list + 1] = "rbxasset://textures/particles/sparkles_main.dds"
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end
	task.delay(2, warmSounds)

	-- THE REHEARSAL: the moment you're in the worm's arena - while it's still
	-- asleep - everything its fight does for the first time is done now, so
	-- the fight looks right from its very first move instead of only the
	-- second time round:
	--  * the whole sand floor is loaded (the game streams the world in near
	--    you first: sand further off might not be there yet, and then the worm
	--    shows through where the sand should hide it and craters can't open)
	--  * every sound and song it plays
	--  * everything it looks up in the arena: what stands on the sand, the
	--    platforms, the seal that caves in, the pit, what trembles
	--  * one small hole dug and filled deep inside the floor, out of sight, so
	--    the first real crater doesn't stall
	--  * the dust of its tremor
	function rehearse(B)
		task.spawn(function()
			local arena = arenaOf(B)
			local center = arena and arena:GetAttribute("Center")
			if typeof(center) == "Vector3" then
				for i = 0, 8 do
					local a = i / 8 * math.pi * 2
					local spot = (i == 0) and center or center + V3(math.sin(a) * 110, 0, math.cos(a) * 110)
					pcall(function()
						player:RequestStreamAroundAsync(spot, 6)
					end)
				end
			end
		end)
		task.spawn(function()
			warmSounds()
		end)
		pcall(warmSand, B)
		pcall(onStone, B, B.vpos)
		pcall(sinkCenter, B)
		pcall(stepTremble, B, nil)
		pcall(collapseSeal, B, B.sealDown or false) -- (only looks the seal up: changes nothing)
		pcall(quakeEmitter, B)
	end

	local WARM_MATERIALS = {
		Enum.Material.Sand, Enum.Material.Sandstone, Enum.Material.Slate, Enum.Material.Neon, Enum.Material.SmoothPlastic,
		Enum.Material.Glass, Enum.Material.Metal, Enum.Material.Fabric, Enum.Material.Wood, Enum.Material.Limestone,
	}
	local warmedFloors = {}
	local function warmMaterials()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local bits = {}
		for k, mat in ipairs(WARM_MATERIALS) do
			local bit = newPart("Warm", nil, RGB(200, 200, 200), mat, 0.97)
			bit.Size = V3(0.2, 0.2, 0.2)
			bits[k] = bit
		end
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local cf = cam.CFrame
			for k, bit in ipairs(bits) do
				bit.CFrame = cf * CFrame.new((k - 5) * 0.25, -1.2, -5)
			end
			if os.clock() - t0 > 0.5 then
				conn:Disconnect()
				for _, bit in ipairs(bits) do
					bit:Destroy()
				end
			end
		end)
	end
	player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
		local f = player:GetAttribute("SpireFloor")
		if f and not warmedFloors[f] then
			warmedFloors[f] = true
			warmMaterials()
		end
	end)
end

-- The worm's body flows from the shape it was in to its next one (see
-- applyWormPose). Pieces of it that were out of sight under the sand don't
-- flow: they simply come up in their new place, so nothing flies across.
local function startWormBlend(B, now)
	if not B.lastPoints then
		return
	end
	local floorY, gs = B.vpos.Y, B.segGirths or {}
	local hidden = {}
	for i, p in ipairs(B.lastPoints) do
		hidden[i] = p.Y + (gs[i] or B.lastGirth or 0) * 0.5 < floorY
	end
	-- (how long it takes is worked out on its first frame: see applyWormPose)
	B.blendFrom, B.blendGirth, B.blendUntil, B.blendHidden = table.clone(B.lastPoints), B.lastGirth, nil, hidden
end

-- "HIT IT!": a big flashing 8-bit sign over the worm whenever it's out of
-- the sand and can be hurt - so you always know when your window is open.
local function hitSign(B, state)
	if B.kind ~= "Worm" or not B.body then
		return
	end
	local head = B.body.segments and B.body.segments[#B.body.segments]
	head = head and head.part
	if not head then
		return
	end
	local m = B.model
	local open = state == "Fighting" and not m:GetAttribute("Submerged") and not m:GetAttribute("Invulnerable")
		and player:GetAttribute("SpireFloor") == B.floor
	if not B.hitGui then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HitIt"
		bb.Size = UDim2.fromOffset(220, 70)
		bb.StudsOffsetWorldSpace = V3(0, 18, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 400
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.Arcade
		l.Text = "HIT IT!"
		l.TextScaled = true
		l.TextColor3 = RGB(254, 231, 97)
		l.Parent = bb
		local st = Instance.new("UIStroke")
		st.Thickness = 4
		st.Color = RGB(24, 20, 37)
		st.Parent = l
		B.hitGui, B.hitLabel = bb, l
		bb.Parent = playerGui
	end
	B.hitGui.Adornee = head
	B.hitGui.Enabled = open == true
	if open then
		-- flashes yellow / red in chunky steps, and bounces
		local k = math.floor(os.clock() * 6) % 2
		B.hitLabel.TextColor3 = k == 0 and RGB(254, 231, 97) or RGB(255, 0, 68)
		B.hitGui.StudsOffsetWorldSpace = V3(0, 18 + (k == 0 and 0 or 1.2), 0)
	end
end

----------------------------------------------------------------------
-- Its own versions of the moments every boss has: sinking back, the
-- break at half health, dying, and waking up
----------------------------------------------------------------------
function Poses.Reset(B, t, P)
	if B.resetUnder then
		P.sink, P.eyes = 1, 0 -- it was already under the sand: it just stays there
		return
	end
	local u = clamp(t / 2, 0, 1)
	P.sink = smooth(u)
	P.eyes = 1 - clamp(u * 2, 0, 1)
	P.sy = 1 + 0.08 * spring(t, 3, 12)
end

function Poses.Break(B, t, P)
	local BT = B.def.BreakTime
	if t < BT * 0.35 then
		-- rears back, shuddering, the glow building up behind its armour
		local k = t / (BT * 0.35)
		P.lean, P.lift, P.shake, P.flare, P.mouth = -0.4 * smooth(k), 6 * smooth(k), 0.45 * k, k, 0.5 * k
		P.coreScale = 1 + 0.3 * k
	else
		-- the plates blow off and it screams
		local k = t - BT * 0.35
		P.lean = -0.4 * math.max(0, 1 - k * 1.5) + 0.25 * spring(k, 3, 9)
		P.lift = 6 * math.max(0, 1 - k * 2)
		P.mouth = clamp(1 - (k - 0.6) / 0.8, 0, 1)
		P.flare = clamp(1 - k * 0.6, 0, 1)
		P.shake = 0.3 * math.max(0, 1 - k)
	end
end

function Poses.Death(B, t, P)
	if t < 0.6 then
		-- one last scream at the sky
		P.shake, P.flare, P.mouth = 0.5, 1, 1
		P.eyes = (t % 0.12 < 0.06) and 1 or 0
		P.lean, P.lift = -0.4 * smooth(t / 0.6), 5 * smooth(t / 0.6)
	elseif t < 2.2 then
		-- then it topples, faster and faster, and crashes down across the sand
		local k = (t - 0.6) / 1.6
		local e = k * k
		P.lean = lerp(-0.4, 1.7, e)
		P.lift = 5 * (1 - k)
		P.sy = 1 - 0.35 * e
		P.mouth = 1 - k
		P.eyes = 0
		P.coreScale = lerp(1.3, 0.3, k)
	else
		-- and the dunes take it back
		local k = clamp((t - 2.2) / 2.2, 0, 1)
		P.lean, P.sy, P.eyes = 1.7, 0.65 - 0.1 * k, 0
		P.coreScale = 0.01
		P.sink = smooth(k) * 0.9
		P.fade = clamp((t - 2.6) / 2, 0, 1)
	end
end

function Starts.Wake(B, t0)
	-- the roar's sound starts a little before the roar itself: your Wake sound
	-- has a build-up, so started on the moment it sounded late
	at(B, t0 + B.def.WakeTime * 0.62 - (B.def.WakeSoundLead or 0.5), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + B.def.WakeTime * 0.62, function()
		kick(B.vpos, 30, 0.9, -3)
		burst(B.vpos + V3(0, 2, 0), B.fx.color, 30, 26, 2.4, 0.9, true)
	end)
	at(B, t0 + B.def.WakeTime * 0.3, function()
		burst(B.vpos + V3(0, 1, 0), B.fx.color, 18, 14, 2, 0.8, true)
	end)
	-- the ground shakes first, then the sand explodes as it breaks the surface
	at(B, t0 + 0.1, function()
		kick(B.vpos, 60, 0.35)
	end)
	at(B, t0 + B.def.WakeTime * 0.27, function()
		burst(B.vpos + V3(0, 1, 0), WORM_SAND, 50, 40, 3.4, 1.3, true)
		burst(B.vpos + V3(0, 0.5, 0), WORM_SAND_DEEP, 24, 26, 2.4, 0.9)
		shockRing(B, B.vpos, B.def.Size / 2, B.def.Size * 1.4, 0.5, WORM_SAND)
		kick(B.vpos, 45, 1.1, -4)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		shatterPlates(B)
		collapseSeal(B, true)
		shockRing(B, B.vpos, def.Size / 2, def.BreakReach, 0.55, WORM_SAND)
		burst(B.vpos + V3(0, def.Size, 0), def.HeartColor or WORM_SAND, 40, 36, 2.4, 0.9, true)
		burst(B.vpos + V3(0, 1, 0), WORM_SAND, 44, 40, 3.2, 1.1, true)
		playSound(def, "Break", B.vpos, 1)
		kick(B.vpos, def.BreakReach, 1.4, -5)
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.5, function()
		playSound(def, "Death", B.vpos, 1)
		-- ash rising off it as it goes
		local holder = newPart("Ashes", nil, def.Color, nil, 1)
		holder.Size = V3(def.Size, 2, def.Size)
		holder.CFrame = CFrame.new(B.vpos + V3(0, 3, 0))
		local e = Instance.new("ParticleEmitter")
		-- a worm doesn't go up in sparks: it crumbles to sand
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(WORM_SAND, def.DeepColor)
		e.LightEmission = 0.05
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.2, 2.4)
		e.Rate = 90
		e.Speed = NumberRange.new(2, 6)
		e.Acceleration = V3(0, 9, 0)
		e.SpreadAngle = Vector2.new(50, 50)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Parent = holder
		task.delay(2.2, function()
			e.Enabled = false
		end)
		task.delay(5, function()
			holder:Destroy()
		end)
	end)
	at(B, t0 + 1.2, function()
		burst(B.vpos + V3(0, 3, 0), def.CoreColor, 24, 18, 2, 0.9, true) -- the core bursts
		kick(B.vpos, 20, 0.7, -2)
	end)
	-- its head hits the sand
	at(B, t0 + 2.1, function()
		local spot = B.mawPos and V3(B.mawPos.X, B.vpos.Y, B.mawPos.Z) or (B.vpos + B.vfacing * def.Size)
		burst(spot + V3(0, 1, 0), WORM_SAND, 50, 34, 3.4, 1.2, true)
		shockRing(B, spot, def.Size / 2, def.Size * 1.6, 0.5, WORM_SAND)
		playSound(def, "Slam", spot, 1)
		kick(spot, 40, 1.3, -4)
	end)
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
Body.build = buildWormBody
Body.pose = applyWormPose
Body.signs = hitSign
Body.glide = glideWorm
Body.senses = stepWormSenses
Body.everyFrame = stepScars

-- what its attacks are made of: sand and rock
function Body.fx(def)
	return { color = WORM_SAND, deep = WORM_SAND_DEEP, rock = WORM_PLATE_DARK, material = Enum.Material.Sand, solid = true }
end

-- your screen starts drawing it
function Body.onTrack(B)
	trailReset(B)
	if B.phase2Look then
		collapseSeal(B, true, true) -- you've arrived after the seal already caved in
	end
end

-- a new action began on the server
function Body.onAction(B, name, t0, now)
	startWormBlend(B, now)
	-- the news of a new move reaches your screen a moment after it began on
	-- the server. Its shape starts from the beginning anyway (a burst out of
	-- the sand really bursts up, instead of appearing half out) and plays a
	-- touch fast until it has caught up. (Arriving much later - you joined
	-- mid-move - it simply picks up where the server is.)
	local late = now - t0
	B.seenAt, B.lateBy = now, (late > 0 and late < 0.6) and late or 0
	B.stage = nil
	if name == "Reset" then
		B.resetUnder = B.model:GetAttribute("Submerged") == true
	end
	if name == "Dormant" then
		closeAllScars() -- asleep again: the floor is flat again
		B.sleepFace = nil -- (and it lies down facing the gate again)
	end
end

-- you arrived after its armour broke: the seal has already caved in
function Body.lateBreak(B)
	collapseSeal(B, true, true)
end

-- the seal closes again once it's back under (not while it's still sinking)
function Body.calm(B, name)
	if name ~= "Reset" then
		collapseSeal(B, false)
	end
end

-- a pose, played: a touch fast while it catches up with late news, and a new
-- stage inside the same move (a leap leaving the sand, a coil closing round
-- you) flows in rather than jumping
function Body.runPose(B, shape, t, now, P)
	local catch = B.lateBy and B.lateBy > 0 and clamp(1 - (now - B.seenAt) / 0.5, 0, 1) or 0
	shape(B, t - B.lateBy * catch, P)
	if P.stage ~= B.stage then
		if B.stage ~= nil and P.stage ~= nil then
			startWormBlend(B, now)
		end
		B.stage = P.stage
	end
end

-- after its body is posed: the path it follows under the sand, and its arches
function Body.afterPose(B)
	trailRecord(B) -- the path its body follows under the sand
	stepHumps(B)
end

-- you can't walk through it: every piece of it that's out of the sand (see pushOutOfWorm)
function Body.pushOut(B, P, here, awake, state)
	if here and (awake or state == "Dormant") then
		local hrp = myRoot()
		if hrp then
			pushOutOfWorm(B, hrp, P)
		end
	end
end

return Body
