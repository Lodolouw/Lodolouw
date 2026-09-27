--[[
	Oozark  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Oozark")

	How Oozark, the Gelatinous Tyrant (floor 1's boss, Config.Bosses[1]) looks
	on your screen: a translucent slime with a hollow dark core, eyes that
	follow you, a crown of broken stone, and squash-and-stretch on everything;
	the shape of each of its moves (rearing up for a slam, flattening into a
	wave, spitting, lunging, the triple slam, the wail), their warnings on the
	floor (the shadow under a slam, the wall of slime, glob marks and their
	puddles, the wail's rings), the crown shattering when its shell breaks,
	the dissolve on death, and its arena's slime pools brightening in phase two.

	HOW A BODY FILE WORKS (see _Template.lua for a new one):
	  * BossClient finds it by the boss's short name in Config (Short =
	    "Oozark") and calls Body.init(kit) once, handing over the drawing kit.
	  * Body.build(def) makes the body's parts; Body.pose(B, P, ground, facing,
	    t, dt) moves them every frame from the pose P.
	  * Poses[action](B, t, P) reshapes the pose t seconds into an action;
	    Starts[action](B, t0) schedules its one-off moments with at(B, when, fn);
	    SlotSpawns[action](B, i, spot, t0) draws a warning for each position
	    the server fills in (ActA, ActB...). The action names are the server's
	    (ServerScriptService/Bosses/Oozark.lua).
	  * Body.fx(def): what its attacks are made of (slime you can see into).
	  * Body.calm(B, name) / Body.breaks(B): its arena settling when it wakes,
	    sleeps or resets, and answering phase two.
]]

local Workspace = game:GetService("Workspace")

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init): the helpers every boss shares
local serverNow, clamp, lerp, smooth, easeOut, easeOutBack, spring, flat, tween
local fxFolder, PIXEL, snapColor, newPart, placeDisc, newRing, placeRing, onFloor, removeRing, burst
local STONE, STONE_DARK, BONE, SLOT_NAMES
local kick, playSound, SPLAT_VOLUME, SPLAT_LEAD
local addTelegraph, shockRing, onStone, at

function Body.init(kit)
	serverNow, clamp, lerp, smooth, easeOut, easeOutBack = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.easeOut, kit.easeOutBack
	spring, flat, tween = kit.spring, kit.flat, kit.tween
	fxFolder, PIXEL, snapColor, newPart, placeDisc = kit.fxFolder, kit.PIXEL, kit.snapColor, kit.newPart, kit.placeDisc
	newRing, placeRing, onFloor, removeRing, burst = kit.newRing, kit.placeRing, kit.onFloor, kit.removeRing, kit.burst
	STONE, STONE_DARK, BONE, SLOT_NAMES = kit.STONE, kit.STONE_DARK, kit.BONE, kit.SLOT_NAMES
	kick, playSound, SPLAT_VOLUME, SPLAT_LEAD = kit.kick, kit.playSound, kit.SPLAT_VOLUME, kit.SPLAT_LEAD
	addTelegraph, shockRing, onStone, at = kit.addTelegraph, kit.shockRing, kit.onStone, kit.at
end

-- The shape of each of its actions over time (Poses), their one-off moments
-- (Starts) and the warnings for positions the server fills in as it goes
-- (SlotSpawns) - BossClient looks each action up by name in these.
local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
-- Gloomgut's body: a slime
local function buildSlimeBody(def)
	local D = def.Size
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }

	body.shell = newPart("Shell", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.3, folder)
	body.shell.Reflectance = 0.06
	body.shell.CastShadow = true
	body.inner = newPart("Depths", Enum.PartType.Ball, def.DeepColor, Enum.Material.SmoothPlastic, 0.55, folder)
	-- the hollow thing inside: murky enough to see into, with a heart that beats
	body.core = newPart("HollowCore", Enum.PartType.Ball, def.CoreColor, Enum.Material.SmoothPlastic, 0.3, folder)
	body.heart = newPart("Heart", Enum.PartType.Ball, def.HeartColor or RGB(214, 255, 120), Enum.Material.Neon, 0, folder)
	body.light = Instance.new("PointLight")
	body.light.Color = def.Color
	body.light.Range = D * 1.3
	body.light.Brightness = 1.1
	body.light.Shadows = false
	body.light.Parent = body.heart

	-- the face: two slit eyes under heavy brows, and more eyes than it should have
	body.eyes = {}
	body.brows = {}
	for i = 1, 2 do
		body.eyes[i] = newPart("Eye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder)
		body.brows[i] = newPart("Brow", Enum.PartType.Ball, def.CoreColor:Lerp(def.DeepColor, 0.35), Enum.Material.SmoothPlastic, 0.12, folder)
	end
	body.smallEyes = {}
	for i, spot in ipairs({ { -0.66, 0.44, 0.9 }, { 0.62, 0.52, 1.0 }, { -0.3, 0.7, 0.75 }, { 0.72, 0.06, 0.8 } }) do
		body.smallEyes[i] = {
			part = newPart("SmallEye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder),
			x = spot[1], y = spot[2], size = spot[3],
			rate = 0.23 + i * 0.061, -- each one blinks on its own clock
			seed = i * 0.37,
		}
	end
	-- the maw: a dark gash that grins shut and gapes open, lined with teeth
	body.mouth = newPart("Mouth", Enum.PartType.Ball, RGB(14, 22, 12), Enum.Material.SmoothPlastic, 0.05, folder)
	body.teeth = {}
	for i = 1, 13 do
		local upper = i <= 7
		local n, k = upper and 7 or 6, upper and i or i - 7
		body.teeth[i] = {
			part = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder),
			upper = upper,
			x = (k - 0.5) / n - 0.5, -- across the mouth, -0.5 .. 0.5
			long = 0.8 + ((i * 7) % 5) / 10, -- ragged, not a neat row
			tilt = (((i * 13) % 7) - 3) * 0.06,
		}
	end

	-- the crown: broken pillar stone it has worn for centuries, and one great shard
	body.crown = {}
	for i = 1, 7 do
		local shard = newPart("CrownShard", nil, i % 2 == 0 and STONE or STONE_DARK, Enum.Material.Slate, 0, folder)
		shard.CastShadow = true
		body.crown[i] = {
			part = shard,
			angle = (i - 1) / 7 * math.pi * 2 + 0.3,
			size = V3(1.7 + (i % 3) * 0.55, 3.4 + ((i * 5) % 4) * 1.05, 1.4 + (i % 2) * 0.4),
			tilt = 0.26 + (i % 3) * 0.14,
		}
	end
	local spire = newPart("CrownShard", nil, STONE, Enum.Material.Slate, 0, folder)
	spire.CastShadow = true
	body.crown[8] = { part = spire, angle = 0, size = V3(2.2, 7.2, 1.9), tilt = 0.08, center = true }

	-- what it has swallowed, turning slowly inside it
	body.debris = {}
	for i = 1, 5 do
		local chunk = newPart("Swallowed", nil, i % 2 == 0 and STONE_DARK or RGB(96, 90, 80), Enum.Material.Slate, 0.1, folder)
		body.debris[i] = { part = chunk, angle = i / 5 * math.pi * 2, height = -0.15 + (i % 3) * 0.14, size = V3(1 + (i % 2), 0.8 + (i % 3) * 0.4, 1.1), spin = 0.3 + i * 0.07 }
	end
	-- its foot: the body spreads over the floor it sits on, with a few lumps
	body.foot = newPart("Foot", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.34, folder)
	body.skirt = {}
	for i = 1, 5 do
		body.skirt[i] = { part = newPart("Skirt", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.3, folder), angle = (i - 0.5) / 5 * math.pi * 2 + 0.4, size = 0.15 + (i % 3) * 0.025 }
	end
	-- slime running down its sides
	body.drips = {}
	for i = 1, 6 do
		body.drips[i] = { part = newPart("Drip", Enum.PartType.Cylinder, def.Color, Enum.Material.SmoothPlastic, 0.18, folder), angle = (i - 1) / 6 * math.pi * 2 + 0.5, phase = i * 1.3, phase2 = i > 4 }
	end
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, RGB(8, 14, 8), Enum.Material.SmoothPlastic, 0.55, folder)

	folder.Parent = fxFolder
	return body
end

-- where a point on the front of the (stretched) body sits, so the eyes and
-- mouth stay on its surface whatever shape it's squashed into
local function onSurface(halfX, halfY, halfZ, x, y)
	if PIXEL then
		return -halfZ - 0.05 -- (the body is a block: its face is flat)
	end
	local k = 1 - (x / halfX) ^ 2 - (y / halfY) ^ 2
	return -halfZ * math.sqrt(math.max(k, 0.02)) - 0.05
end

-- Puts every part of the body where this frame's pose says.
local function applySlimePose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	if PIXEL then
		-- (sits a hair above the floor, so the cube's bottom never cuts through
		-- the glowing slime channels in the paving - see-through things that
		-- cut through each other flicker)
		ground = ground + V3(0, 0.3, 0)
	end
	local D = def.Size
	local H = D * 0.85 * P.sy
	local halfX, halfY, halfZ = D * P.sx / 2, H / 2, D * P.sz / 2
	local sinkDepth = P.sink * H * 0.85
	if PIXEL then
		-- (a round body can half-show out of the pool like a dome; a cube would be
		-- a flat slab sticking out of it - so asleep, it's right under the surface)
		sinkDepth = P.sink * (H + 2)
	end
	local fade = P.fade or 0
	local phase2 = B.phase2Look
	-- 8-BIT: only the jelly cube itself is see-through. Everything inside it or
	-- on it is solid, and pops out of sight in steps as it dies (fade) instead
	-- of turning see-through - because Roblox can't sort see-through parts
	-- that sit inside each other, and they flicker in front of each other.
	local function solid(goneAt)
		return (fade >= goneAt) and 1 or 0
	end

	local jitter = V3(0, 0, 0)
	if P.shake > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local base = CFrame.lookAt(ground + jitter, ground + jitter + facing) * CFrame.Angles(-P.lean, 0, 0)
	local center = base * CFrame.new(0, P.lift + H / 2 - sinkDepth, 0)

	-- a punch landing turns the slime pale for a blink: you see every hit connect
	local flash = B.flashAt and clamp(1 - (os.clock() - B.flashAt) / 0.14, 0, 1) or 0
	body.shell.Size = V3(D * P.sx, H, D * P.sz)
	body.shell.CFrame = center
	body.shell.Transparency = lerp(phase2 and 0.44 or 0.3, 1, fade)
	body.shell.Color = def.Color:Lerp(RGB(236, 255, 214), 0.5 * flash)
	if PIXEL then
		-- (8-bit hit flash: a crisp white blink, not a fade)
		body.shell.Color = flash > 0.35 and RGB(255, 255, 255) or snapColor(def.Color)
	end
	body.inner.Size = body.shell.Size * 0.84
	body.inner.CFrame = center * CFrame.new(0, -H * 0.06, 0)
	body.inner.Transparency = lerp(phase2 and 0.72 or 0.55, 1, fade)
	if PIXEL then
		body.inner.Transparency = 1
	end

	-- the core lags behind the body: a little secondary motion reads as jelly
	local coreSize = D * (phase2 and 0.47 or 0.36) * (1 + 0.05 * math.sin(t * 2.7)) * (P.coreScale or 1)
	local coreWant = center * CFrame.new(0, -H * 0.04 + math.sin(t * 1.9) * 0.4, 0)
	B.corePos = B.corePos and B.corePos:Lerp(coreWant.Position, 1 - math.exp(-dt * 7)) or coreWant.Position
	body.core.Size = V3(coreSize, coreSize * 0.95, coreSize)
	body.core.CFrame = CFrame.new(B.corePos) * (center - center.Position)
	body.core.Transparency = lerp(phase2 and 0.4 or 0.3, 1, clamp(fade * 1.3 - 0.2, 0, 1))
	if PIXEL then
		body.core.Transparency = solid(0.6)
	end

	-- the heart: the thing you are actually killing. Two beats and a rest, faster
	-- once the shell is broken and faster again when it is nearly dead.
	local health = B.model and (B.model:GetAttribute("Health") or 1) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1) or 1
	local rate = phase2 and (health <= def.DesperateAt and 2.4 or 1.7) or 1.1
	local beatT = (os.clock() * rate) % 1
	local beat = math.exp(-((beatT - 0.05) / 0.06) ^ 2) + 0.6 * math.exp(-((beatT - 0.24) / 0.06) ^ 2)
	local heartSize = D * (phase2 and 0.13 or 0.1) * (1 + 0.2 * beat + 0.3 * P.flare) * math.min(P.coreScale or 1, 1.25)
	body.heart.Size = V3(heartSize, heartSize, heartSize)
	body.heart.CFrame = CFrame.new(B.corePos)
	body.heart.Transparency = lerp(0, 1, clamp(fade * 1.5, 0, 1))
	if PIXEL then
		-- (the core is solid now: the heart glows on its front, like a gem, so you
		-- can still see the thing you're killing)
		body.heart.CFrame = body.core.CFrame * CFrame.new(0, 0, -(coreSize / 2))
		body.heart.Transparency = solid(0.7)
	end
	body.heart.Color = (def.HeartColor or RGB(214, 255, 120)):Lerp(RGB(255, 255, 230), 0.4 * beat + 0.4 * P.flare)
	body.light.Brightness = lerp((phase2 and 2.1 or 1.1) + 0.6 * beat + P.flare * 1.6, 0, fade)
	body.light.Range = D * (phase2 and 1.7 or 1.3)

	-- eyes: slits angled down toward the middle, glowing, shut when asleep
	local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
	local eyeY = H * 0.17
	for i, eye in ipairs(body.eyes) do
		local side = (i == 1) and -1 or 1
		local ex = side * D * 0.15 * P.sx
		local ez = onSurface(halfX, halfY, halfZ, ex, eyeY)
		eye.Size = V3(D * 0.17, math.max(D * 0.048 * eyeOpen * (1 + 0.5 * P.flare), 0.05), D * 0.05)
		eye.CFrame = center * CFrame.new(ex, eyeY, ez) * CFrame.Angles(0, 0, side * 0.32)
		eye.Transparency = eyeOpen < 0.05 and 1 or 0
		eye.Color = (def.EyeColor):Lerp(RGB(255, 255, 255), clamp(P.flare, 0, 1) * 0.5)
		-- the brow hangs over it at a steeper angle: that is what makes it glare
		local brow = body.brows[i]
		local bx, by = side * D * 0.16 * P.sx, eyeY + D * 0.07 - D * 0.02 * P.flare
		local bz = onSurface(halfX, halfY, halfZ, bx, by) + 0.12
		brow.Size = V3(D * 0.24, D * 0.06, D * 0.09)
		brow.CFrame = center * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, side * 0.44)
		brow.Transparency = PIXEL and solid(0.3) or lerp(0.12, 1, fade)
	end
	-- the other eyes, each blinking on its own slow clock
	for _, e in ipairs(body.smallEyes) do
		local x, y = e.x * halfX * 0.86, e.y * halfY * 0.86
		local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.07 and 0 or 1
		local open = eyeOpen * blink
		local z = onSurface(halfX, halfY, halfZ, x, y)
		local size = D * 0.055 * e.size
		e.part.Size = V3(size, math.max(size * 0.8 * open, 0.05), size * 0.6)
		e.part.CFrame = center * CFrame.new(x, y, z) * CFrame.Angles(0, PIXEL and 0 or math.atan2(x, -z) * 0.8, 0)
		e.part.Transparency = open < 0.05 and 1 or 0
	end

	-- the maw
	local my = -H * 0.12
	local mouthW = D * 0.46 * P.sx
	local mouthH = math.max(D * (0.03 + 0.24 * P.mouth), 0.05)
	local mz = onSurface(halfX, halfY, halfZ, 0, my)
	body.mouth.Size = V3(mouthW, mouthH, D * 0.08)
	body.mouth.CFrame = center * CFrame.new(0, my - D * 0.04 * P.mouth, mz)
	body.mouth.Transparency = PIXEL and solid(0.4) or lerp(0.05, 1, fade)
	local mouthMid = my - D * 0.04 * P.mouth
	for _, tooth in ipairs(body.teeth) do
		local x = tooth.x * mouthW * 0.86
		local curve = 1 - (2 * tooth.x) ^ 2 -- the mouth is an oval: its edge dips at the corners
		local edge = mouthH / 2 * math.sqrt(math.max(curve, 0.05))
		local len = D * 0.07 * tooth.long * (0.75 + 0.25 * math.sqrt(math.max(curve, 0)))
		local y = tooth.upper and (mouthMid + edge - len / 2 + 0.15) or (mouthMid - edge + len / 2 - 0.15)
		local z = onSurface(halfX, halfY, halfZ, x, y) - 0.08
		tooth.part.Size = V3(D * 0.024, len * 1.1, D * 0.03) -- slim fangs, not a row of bricks
		tooth.part.CFrame = center * CFrame.new(x, y, z) * CFrame.Angles(0, 0, tooth.tilt + (tooth.upper and 0 or math.pi))
		tooth.part.Transparency = lerp(0, 1, clamp(fade * 1.2, 0, 1))
	end

	-- the crown, until the shell breaks
	for _, c in ipairs(body.crown) do
		if B.crownGone then
			c.part.Transparency = 1
		else
			local r = c.center and 0 or D * 0.21 * P.sx
			local pos = center * CFrame.new(math.cos(c.angle) * r, H * 0.42 + (c.center and 0.9 or 0), math.sin(c.angle) * r)
			c.part.Size = c.size
			c.part.CFrame = pos * CFrame.Angles(0, -c.angle, 0) * CFrame.Angles(0, 0, c.tilt)
			c.part.Transparency = PIXEL and solid(0.5) or fade
		end
	end
	-- what's inside, circling
	for _, d in ipairs(body.debris) do
		local a = d.angle + t * d.spin * (phase2 and 1.8 or 1)
		local r = D * 0.23
		d.part.Size = d.size
		d.part.CFrame = center * CFrame.new(math.cos(a) * r * P.sx, H * d.height, math.sin(a) * r * P.sz) * CFrame.Angles(t * d.spin, a, t * 0.4)
		d.part.Transparency = PIXEL and solid(0.5) or lerp(0.1, 1, fade)
	end
	-- the foot: spread out over the floor, pulled in when it leaves the ground,
	-- splashed wide when it lands
	local spread = clamp(1 - P.lift / (D * 0.3), 0.35, 1)
	local footW = D * 1.14 * spread * (1 + 0.6 * math.max(P.sx - 1, 0))
	local footH = D * 0.15 * (1 + 0.8 * math.max(P.sx - 1, 0))
	body.foot.Size = V3(footW, footH, footW * P.sz / P.sx)
	body.foot.CFrame = base * CFrame.new(0, P.lift * 0.96 + footH * 0.28 - sinkDepth * 0.4, 0)
	body.foot.Transparency = lerp(phase2 and 0.46 or 0.34, 1, math.max(fade, P.sink * 0.8))
	body.foot.Color = body.shell.Color
	-- (8-bit: a point on the cube's outside, in direction `a` round it, and
	-- which way that face looks)
	local function onBox(a, out)
		local cx, cz = math.cos(a), math.sin(a)
		local k = 1 / math.max(math.abs(cx) / halfX, math.abs(cz) / halfZ)
		local nx, nz = 0, 0
		if math.abs(cx) / halfX > math.abs(cz) / halfZ then
			nx = cx > 0 and 1 or -1
		else
			nz = cz > 0 and 1 or -1
		end
		return cx * k + nx * out, cz * k + nz * out
	end
	if PIXEL then
		body.foot.Transparency = 1 -- (a square sheet round a cube just looked odd)
	end
	for _, sk in ipairs(body.skirt) do
		local size = D * sk.size * (1 + 0.5 * math.max(P.sx - 1, 0)) * (1 - 0.3 * P.sink) * spread
		local r = footW * 0.43
		local pos = base * CFrame.new(math.cos(sk.angle) * r, size * 0.3 - sinkDepth * 0.3 + P.lift * 0.96, math.sin(sk.angle) * r * P.sz / P.sx)
		sk.part.Size = V3(size, size * 0.72, size)
		sk.part.Transparency = lerp(phase2 and 0.42 or 0.3, 1, fade)
		if PIXEL then
			-- solid lumps of goo oozing out at the foot of each face
			local x, z = onBox(sk.angle, size * 0.3)
			pos = base * CFrame.new(x, size * 0.3 - sinkDepth + P.lift * 0.96, z)
			sk.part.Transparency = math.max(solid(0.3), P.sink > 0.3 and 1 or 0)
			sk.part.Color = body.shell.Color
		end
		sk.part.CFrame = pos
	end
	-- drips lengthen and snap back
	for _, d in ipairs(body.drips) do
		if d.phase2 and not phase2 then
			d.part.Transparency = 1
		else
			local len = 1.5 + 2.2 * ((t * 0.45 + d.phase) % 1)
			local x, z = math.cos(d.angle) * halfX * 0.97, math.sin(d.angle) * halfZ * 0.97
			if PIXEL then
				x, z = onBox(d.angle, 0.2) -- (running down the outside of a face)
				len = math.floor(len * 2 + 0.5) / 2 -- (and growing in chunky steps)
			end
			local top = center * CFrame.new(x, -H * 0.02, z)
			d.part.Size = V3(len, 0.55, 0.55)
			d.part.CFrame = top * CFrame.new(0, -len / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			d.part.Transparency = PIXEL and solid(0.3) or lerp(0.18, 1, fade)
		end
	end
	-- its shadow on the floor: widens as it rears up, marking where it will land
	local shadowD = P.shadowD or (D * 0.95 * P.sx)
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.08, 0), shadowD, 0.1)
	body.shadow.Transparency = lerp(P.shadowDark and (0.62 - 0.3 * P.shadowDark) or 0.62, 1, math.max(fade, P.sink))
	if PIXEL then
		-- a solid dark shadow (a see-through one under a see-through cube flickers)
		body.shadow.Transparency = (fade > 0.5 or P.sink > 0.5) and 1 or 0
		body.shadow.Color = RGB(24, 20, 37)
	end
end

----------------------------------------------------------------------
-- Its warnings in the world
----------------------------------------------------------------------
-- The wall of slime: its radius at any moment is exactly what the server tests.
local function waveRing(B, origin, t0)
	local a = B.def.Attacks.Wave
	local start = B.def.Size / 2
	local wallT = B.fx.solid and 0 or 0.25 -- a wall of slime you can see into; a wall of sand you can't
	local wall = newRing(52, B.fx.color, B.fx.material, wallT)
	local crest = newRing(52, B.def.EyeColor, Enum.Material.Neon, 0.55)
	local life = a.Reach / a.Speed
	addTelegraph(B, {
		update = function(now)
			local age = now - t0
			if age > life then
				return false
			end
			if age < 0 then
				placeRing(wall, origin, start, 0.05, a.Thickness, 1)
				placeRing(crest, origin, start, 0.05, a.Thickness * 0.4, 1)
				return true
			end
			local r = start + a.Speed * age
			local fadeOut = clamp((age - (life - 0.35)) / 0.35, 0, 1)
			local h = a.Height * (1 - 0.45 * fadeOut) * (0.92 + 0.08 * math.sin(now * 30))
			placeRing(wall, origin + V3(0, 0.05, 0), r, h, a.Thickness, lerp(wallT, 1, fadeOut), true)
			placeRing(crest, origin + V3(0, h * 0.85, 0), r, h * 0.3, a.Thickness * 0.45, lerp(0.5, 1, fadeOut), true)
			return true
		end,
		cleanup = function()
			removeRing(wall)
			removeRing(crest)
		end,
	})
end

-- A glob in flight: where it will land is marked on the floor from the moment
-- it leaves the mouth, filling in as it comes down.
local function glob(B, from, to, launchAt)
	local a = B.def.Attacks.Spit
	to = onFloor(to)
	local landAt = launchAt + a.Flight
	local fx = B.fx
	-- the slime spits glowing globs that leave burning puddles; the worm hurls
	-- clods of hardened sand that leave churning quicksand
	local ballT = fx.solid and 0 or 0.15
	local ball = newPart("Glob", Enum.PartType.Ball, fx.color, fx.material, ballT)
	ball.Size = fx.solid and V3(3.2, 3.2, 3.2) or V3(2.4, 2.4, 2.4)
	local mark = newRing(22, B.def.EyeColor, Enum.Material.Neon, 0.4)
	local fill = newPart("GlobMark", Enum.PartType.Cylinder, fx.solid and fx.deep or B.def.Color, fx.solid and Enum.Material.Sand or Enum.Material.Neon, 0.7)
	local peak = 7 + flat(to - from).Magnitude * 0.18
	local landed = false
	local splatted = false
	addTelegraph(B, {
		update = function(now)
			local u = (now - launchAt) / a.Flight
			if u < 0 then
				ball.Transparency = 1
				return true
			end
			-- the splat starts a few hundredths early: sound takes a moment to
			-- reach your ears, so a splat started on the exact frame feels late
			if not splatted and now >= launchAt + a.Flight - SPLAT_LEAD then
				splatted = true
				playSound(B.def, "Splat", to, SPLAT_VOLUME)
			end
			if u < 1 then
				local p = from:Lerp(to, u) + V3(0, peak * 4 * u * (1 - u), 0)
				ball.Transparency = ballT
				ball.CFrame = CFrame.new(p) * CFrame.Angles(u * 7, u * 5, 0) -- (a clod tumbles)
				placeRing(mark, to + V3(0, 0.06, 0), a.Radius, 0.18, 0.5, 0.45 - 0.3 * u)
				placeDisc(fill, to + V3(0, 0.07, 0), 2 * a.Radius * u, 0.08)
				fill.Transparency = 0.75 - 0.25 * u
				return true
			end
			if not landed then
				landed = true
				ball.Transparency = 1
				burst(to + V3(0, 0.5, 0), fx.color, 16, 18, 1.2, 0.5)
				shockRing(B, to, 1, a.Radius * 1.2, 0.3, fx.color)
				kick(to, a.Radius, 0.35)
			end
			-- then the puddle it leaves, burning for a few seconds (a clod that
			-- lands on stone just shatters: nothing for it to sink into)
			local left = (landAt + a.PuddleTime) - now
			if left <= 0 or (fx.solid and onStone(B, to)) then
				return false
			end
			placeRing(mark, to + V3(0, 0.05, 0), a.Puddle, 0.12, 0.4, lerp(1, 0.55, clamp(left, 0, 1)))
			placeDisc(fill, to + V3(0, 0.06, 0), 2 * a.Puddle * (0.96 + 0.04 * math.sin(now * 6)), 0.1)
			fill.Transparency = lerp(1, 0.35, clamp(left, 0, 1))
			return true
		end,
		cleanup = function()
			ball:Destroy()
			fill:Destroy()
			removeRing(mark)
		end,
	})
end

-- A ring of the wail: blooms, fills over its fuse (faster pulse near the end),
-- then erupts in a column of slime.
local function wailRing(B, at, bloomAt)
	local a = B.def.Attacks.Wail
	at = onFloor(at)
	local eruptAt = bloomAt + a.Fuse
	local fx = B.fx
	local outline = newRing(30, B.def.EyeColor, Enum.Material.Neon, 0.3)
	local fill = newPart("WailFill", Enum.PartType.Cylinder, fx.solid and fx.deep or B.def.Color, fx.solid and Enum.Material.Sand or Enum.Material.Neon, 0.6)
	-- a pillar of slime - or of sand, with shards of rock thrown up in it
	local column = newPart("Geyser", Enum.PartType.Cylinder, fx.color, fx.material, 1)
	local columnT = fx.solid and 0.05 or 0.35
	local spikes = {}
	for i = 1, 6 do
		spikes[i] = newPart("Spike", nil, fx.solid and fx.rock or B.def.DeepColor, fx.solid and Enum.Material.Slate or Enum.Material.Glass, 1)
	end
	local erupted = false
	addTelegraph(B, {
		update = function(now)
			local k = (now - bloomAt) / a.Fuse
			if k < 0 then
				return true
			end
			if k < 1 then
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 26, k))
				placeRing(outline, at + V3(0, 0.06, 0), a.Radius, 0.25, 0.6, lerp(0.45, 0.1, pulse * k))
				placeDisc(fill, at + V3(0, 0.07, 0), 2 * a.Radius * smooth(k), 0.08)
				fill.Transparency = lerp(0.75, 0.35, k)
				return true
			end
			if not erupted then
				erupted = true
				burst(at + V3(0, 1, 0), fx.color, 26, 30, 1.8, 0.8, true)
				shockRing(B, at, 1, a.Radius * 1.3, 0.35)
				playSound(B.def, "Erupt", at, 0.9)
				kick(at, a.Radius, 0.8, -2.5)
				for i = 1, #outline.parts do
					outline.parts[i].Transparency = 1
				end
				fill.Transparency = 1
			end
			local e = now - eruptAt
			if e > 0.9 then
				return false
			end
			-- the geyser: shoots up, then collapses
			local up = e < 0.18 and easeOut(e / 0.18) or (1 - smooth((e - 0.18) / 0.72))
			local h = (a.Geyser or 16) * up -- a pillar of slime
			column.Size = V3(math.max(h, 0.05), a.Radius * 1.1, a.Radius * 1.1)
			column.CFrame = CFrame.new(at + V3(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			column.Transparency = lerp(columnT, 1, clamp((e - 0.3) / 0.6, 0, 1))
			for i, sp in ipairs(spikes) do
				local ang = i / #spikes * math.pi * 2
				local len = (a.Geyser or 16) * 0.4 * up
				local p = at + V3(math.cos(ang) * a.Radius * 0.6, len / 2, math.sin(ang) * a.Radius * 0.6)
				sp.Size = V3(1.1 + a.Radius * 0.08, math.max(len, 0.05), 1.1 + a.Radius * 0.08)
				sp.CFrame = CFrame.new(p) * CFrame.Angles(math.sin(ang) * 0.4, 0, -math.cos(ang) * 0.4)
				sp.Transparency = column.Transparency
			end
			return true
		end,
		cleanup = function()
			removeRing(outline)
			fill:Destroy()
			column:Destroy()
			for _, sp in ipairs(spikes) do
				sp:Destroy()
			end
		end,
	})
end

-- the crown flying apart when the shell breaks
local function shatterCrown(B, center)
	B.crownGone = true
	for i, c in ipairs(B.body.crown) do
		local shard = newPart("Shard", nil, c.part.Color, Enum.Material.Slate, 0)
		shard.Size = c.size
		shard.CastShadow = true
		local start = c.part.CFrame
		local out = V3(math.cos(c.angle + i), 0, math.sin(c.angle + i))
		local speed = 18 + (i % 3) * 6
		local t0 = serverNow()
		addTelegraph(B, {
			update = function(now)
				local e = now - t0
				if e > 1.6 then
					return false
				end
				local p = start.Position + out * speed * e + V3(0, 22 * e - 30 * e * e, 0)
				if p.Y < center.Y - 6 then
					p = V3(p.X, center.Y - 6, p.Z)
				end
				shard.CFrame = CFrame.new(p) * (start - start.Position) * CFrame.Angles(e * 7, e * 3, 0)
				shard.Transparency = clamp((e - 1.1) / 0.5, 0, 1)
				return true
			end,
			cleanup = function()
				shard:Destroy()
			end,
		})
	end
end

----------------------------------------------------------------------
-- The shape of each action over time
----------------------------------------------------------------------
-- Every pose starts from breathing (BossClient) and an action reshapes it. t is
-- seconds since the action began on the server.
function Poses.Dormant(B, t, P)
	P.sink, P.eyes = 1, 0
	P.sy = 0.9 + 0.05 * math.sin(t * 1.3)
end

function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local u = clamp(t / W, 0, 1)
	if u < 0.25 then
		local k = u / 0.25
		P.sink = 1 - 0.2 * k
		P.shake = 0.1 * k
	elseif u < 0.72 then
		local e = easeOutBack((u - 0.25) / 0.47)
		P.sink = clamp(0.8 * (1 - e), 0, 1)
		P.sy = 0.85 + 0.3 * e
		P.sx = 1.25 - 0.28 * e
		P.sz = P.sx
	else
		local w = spring((u - 0.72) * W, 4, 14)
		P.sink = 0
		P.sy = 1 + 0.12 * w
		P.sx = 1 - 0.08 * w
		P.sz = P.sx
	end
	P.eyes = clamp((u - 0.55) / 0.08, 0, 1)
	if u > 0.6 and u < 0.88 then
		P.mouth = math.sin((u - 0.6) / 0.28 * math.pi) -- the roar
		P.shake = math.max(P.shake, 0.35 * P.mouth)
		P.flare = P.mouth
	end
	if PIXEL then
		-- 8-bit: it heaves up out of the pool in chunky steps, like a sprite
		P.sink = math.floor(P.sink * 10 + 0.5) / 10
		P.sy = math.floor(P.sy * 16 + 0.5) / 16
		P.sx = math.floor(P.sx * 16 + 0.5) / 16
		P.sz = P.sx
	end
end

function Poses.Reset(B, t, P)
	local u = clamp(t / 2, 0, 1)
	P.sink = smooth(u)
	P.eyes = 1 - clamp(u * 2, 0, 1)
	P.sy = 1 + 0.08 * spring(t, 3, 12)
	if PIXEL then
		P.sink = math.floor(P.sink * 10 + 0.5) / 10 -- (sinking back down in steps too)
	end
end

function Poses.Slam(B, t, P)
	local a = B.def.Attacks.Slam
	local T = a.Tell
	local D = B.def.Size
	if t < T - 0.08 then
		local k = clamp(t / (T - 0.08), 0, 1)
		local e = easeOut(math.min(k / 0.8, 1))
		P.lift = a.Rise * e
		P.sy, P.sx = 1 + 0.26 * e, 1 - 0.13 * e
		P.sz = P.sx
		if k > 0.8 then -- hanging at the top: here it comes
			local w = (k - 0.8) / 0.2
			P.sy = P.sy + 0.05 * math.sin(w * math.pi * 3)
			P.shake = 0.12 * w
		end
		P.shadowD = lerp(D * 0.95, a.Radius * 2, e)
		P.shadowDark = e
	elseif t < T then
		local k = (t - (T - 0.08)) / 0.08
		P.lift = a.Rise * (1 - k * k)
		P.sy, P.sx = 1.3, 0.84
		P.sz = P.sx
		P.shadowD, P.shadowDark = a.Radius * 2, 1
	else
		local w = spring(t - T, 5, 13)
		P.sy, P.sx = 1 - 0.42 * w, 1 + 0.36 * w
		P.sz = P.sx
		P.shadowD = lerp(D * 0.95, a.Radius * 2, clamp(1 - (t - T) / 0.3, 0, 1))
	end
end

function Poses.Wave(B, t, P)
	local a = B.def.Attacks.Wave
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sy, P.sx = 1 - 0.36 * k, 1 + 0.28 * k
		P.sz = P.sx
		if t > a.Tell * 0.7 then
			P.shake = 0.15 * (t - a.Tell * 0.7) / (a.Tell * 0.3)
		end
	else
		local w = spring(t - a.Tell, 4.5, 11)
		P.sy, P.sx = 1 + 0.3 * w, 1 - 0.2 * w
		P.sz = P.sx
	end
end

function Poses.Spit(B, t, P)
	local a = B.def.Attacks.Spit
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sx, P.sy = 1 + 0.1 * k, 1 + 0.12 * k
		P.sz = P.sx
		P.mouth, P.lean = 0.45 * k, -0.1 * k
		return
	end
	local last = a.Tell + (a.Globs - 1) * a.Gap
	local settle = clamp((t - last - 0.25) / 0.5, 0, 1)
	P.sx, P.sy = lerp(1.1, 1, settle), lerp(1.12, 1, settle)
	P.sz = P.sx
	P.mouth, P.lean = lerp(0.45, 0, settle), lerp(-0.1, 0, settle)
	for i = 1, a.Globs do
		local d = t - (a.Tell + (i - 1) * a.Gap)
		if d >= 0 and d < 0.22 then
			local pulse = math.sin(d / 0.22 * math.pi)
			P.mouth = 0.45 + 0.55 * pulse
			P.lean = -0.1 + 0.3 * pulse
			P.sz = P.sz - 0.12 * pulse
		end
	end
end

function Poses.Lunge(B, t, P)
	local a = B.def.Attacks.Lunge
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.lean = -0.38 * k
		P.sy, P.sx = 1 + 0.14 * k, 1 - 0.07 * k
		if t > a.Tell * 0.75 then -- crouches to spring
			local c = (t - a.Tell * 0.75) / (a.Tell * 0.25)
			P.sy = P.sy - 0.24 * c
			P.sx = P.sx + 0.1 * c
		end
		P.sz = P.sx
		return
	end
	local m = B.model
	local from, to, travel = m:GetAttribute("ActA"), m:GetAttribute("ActB"), m:GetAttribute("ActN")
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or not travel then
		P.lean = -0.38 -- committed, waiting to hear where to
		return
	end
	local u = clamp((t - a.Tell) / travel, 0, 1)
	if u < 1 then
		P.override = from:Lerp(to, u)
		P.lift = 5.5 * math.sin(math.pi * u)
		P.sz, P.sy, P.sx, P.lean = 1.34, 0.8, 0.94, 0.24
		P.shadowD = B.def.Size * 0.9
	else
		local w = spring(t - a.Tell - travel, 5, 13)
		P.sy, P.sx = 1 - 0.4 * w, 1 + 0.34 * w
		P.sz = P.sx
	end
end

function Poses.TripleSlam(B, t, P)
	local a = B.def.Attacks.TripleSlam
	local m = B.model
	local spots = { m:GetAttribute("ActA"), m:GetAttribute("ActB"), m:GetAttribute("ActC") }
	local D = B.def.Size
	if t < a.Tell - 0.07 then
		local e = easeOut(clamp(t / (a.Tell - 0.07) / 0.8, 0, 1))
		P.lift = a.Rise * e
		P.sy, P.sx = 1 + 0.24 * e, 1 - 0.12 * e
		P.sz = P.sx
		P.shadowD, P.shadowDark = lerp(D * 0.95, a.Radii[1] * 2, e), e
		P.shake = 0.1 * e
		return
	elseif t < a.Tell then
		local k = (t - (a.Tell - 0.07)) / 0.07
		P.lift = a.Rise * (1 - k * k)
		P.sy, P.sx = 1.28, 0.86
		P.sz = P.sx
		P.shadowD, P.shadowDark = a.Radii[1] * 2, 1
		return
	end
	local k = t - a.Tell
	local hop = math.floor(k / a.Gap) + 2
	if hop <= 3 then
		local u = clamp((k - (hop - 2) * a.Gap) / a.Gap, 0, 1)
		local from, to = spots[hop - 1], spots[hop]
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			P.override = from:Lerp(to, smooth(u))
		end
		-- up fast, a beat at the top, down hard
		local h = u < 0.7 and easeOut(u / 0.7) or (1 - ((u - 0.7) / 0.3) ^ 2)
		P.lift = a.Rise * 0.85 * h
		local land = spring(k - (hop - 2) * a.Gap, 7, 16) * (u < 0.3 and 1 or 0)
		P.sy, P.sx = 1 + 0.2 * h - 0.4 * land, 1 - 0.1 * h + 0.34 * land
		P.sz = P.sx
		P.shadowD = lerp(D * 0.95, a.Radii[hop] * 2, h)
		P.shadowDark = h
	else
		local w = spring(k - 2 * a.Gap, 5, 13)
		P.sy, P.sx = 1 - 0.42 * w, 1 + 0.36 * w
		P.sz = P.sx
	end
end

function Poses.Wail(B, t, P)
	local a = B.def.Attacks.Wail
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sx, P.sy = 1 - 0.12 * k, 1 - 0.1 * k
		P.sz = P.sx
		P.mouth, P.shake, P.flare = k, 0.3 * k, k
		return
	end
	local k = t - a.Tell
	local total = (a.Rings - 1) * a.Gap + a.Fuse
	if k < total then
		P.mouth, P.shake, P.flare = 1, 0.28, 1
		P.sx, P.sy = 0.88, 0.9 + 0.05 * math.sin(k * 20)
		P.sz = P.sx
	else
		local s = clamp((k - total) / 0.5, 0, 1)
		P.mouth, P.flare = 1 - s, 1 - s
		P.sx, P.sy = lerp(0.88, 1, s), lerp(0.9, 1, s)
		P.sz = P.sx
	end
end

function Poses.Break(B, t, P)
	local BT = B.def.BreakTime
	if t < BT * 0.35 then
		local k = t / (BT * 0.35)
		local w = math.sin(t * 50)
		P.sx, P.sy = 1 + 0.12 * k * w, 1 - 0.1 * k * w
		P.sz = P.sx
		P.shake, P.flare, P.mouth = 0.5 * k, k, 0.6 * k
		P.coreScale = 1 + 0.25 * k
	else
		local k = t - BT * 0.35
		local w = spring(k, 3, 10)
		P.sx, P.sy = 1 + 0.35 * w, 1 - 0.3 * w
		P.sz = P.sx
		P.mouth = clamp(1 - k, 0, 1)
		P.flare = clamp(1 - k * 0.8, 0, 1)
	end
end

function Poses.Death(B, t, P)
	if t < 0.5 then
		P.shake, P.flare = 0.4, 1
		P.eyes = (t % 0.12 < 0.06) and 1 or 0 -- the light going out
		P.mouth = 0.7
	elseif t < 2.4 then
		local k = (t - 0.5) / 1.9
		local e = k * k
		P.sy, P.sx = 1 - 0.88 * e, 1 + 0.55 * k
		P.sz = P.sx
		P.eyes, P.mouth = 0, 0.7 * (1 - k)
		P.fade = clamp(k * 0.75, 0, 1)
		P.coreScale = t < 1.2 and (1 + (t - 0.5)) or 0.01
	else
		P.sy, P.sx = 0.12, 1.55
		P.sz = P.sx
		P.eyes = 0
		P.coreScale = 0.01
		P.fade = clamp(0.75 + (t - 2.4) / 1.6 * 0.25, 0, 1)
	end
end

----------------------------------------------------------------------
-- One-off moments in each action (sounds, landings, telegraphs)
----------------------------------------------------------------------
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
end

function Starts.Slam(B, t0)
	local a = B.def.Attacks.Slam
	at(B, t0 + a.Tell, function()
		shockRing(B, B.vpos, B.def.Size / 2, a.Radius * 1.15, 0.35)
		burst(B.vpos + V3(0, 0.6, 0), B.fx.color, 36, 34, 2, 0.6)
		playSound(B.def, "Slam", B.vpos, 1)
		kick(B.vpos, a.Radius, 1.1, -4)
	end)
end

function Starts.Wave(B, t0)
	local a = B.def.Attacks.Wave
	at(B, t0 + a.Tell, function()
		local origin = B.model:GetAttribute("ActA")
		waveRing(B, typeof(origin) == "Vector3" and origin or B.vpos, t0 + a.Tell)
		burst(B.vpos + V3(0, 0.6, 0), B.fx.color, 24, 26, 1.6, 0.5)
		playSound(B.def, "Wave", B.vpos, 1)
		kick(B.vpos, 20, 0.5)
	end)
end

function Starts.Spit(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Spit", B.vpos, 0.6)
	end)
end

function Starts.Lunge(B, t0)
	local a = B.def.Attacks.Lunge
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Lunge", B.vpos, 1)
		burst(B.vpos + V3(0, 0.4, 0), RGB(170, 170, 160), 16, 16, 1.6, 0.5)
	end)
end

function Starts.TripleSlam(B, t0)
	local a = B.def.Attacks.TripleSlam
	for i = 1, 3 do
		at(B, t0 + a.Tell + (i - 1) * a.Gap, function()
			local spot = B.model:GetAttribute(SLOT_NAMES[i])
			spot = typeof(spot) == "Vector3" and spot or B.vpos
			shockRing(B, spot, B.def.Size / 2, a.Radii[i] * 1.15, 0.3)
			burst(spot + V3(0, 0.6, 0), B.fx.color, 26, 30, 1.8, 0.5)
			playSound(B.def, "Slam", spot, 0.9)
			kick(spot, a.Radii[i], 0.9, -3)
		end)
	end
end

function Starts.Wail(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Wail", B.vpos, 1)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		shatterCrown(B, B.vpos)
		shockRing(B, B.vpos, def.Size / 2, def.BreakReach, 0.55)
		burst(B.vpos + V3(0, def.Size * 0.5, 0), B.fx.color, 50, 40, 2.6, 1, true)
		playSound(def, "Break", B.vpos, 1)
		kick(B.vpos, def.BreakReach, 1.3, -5)
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
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(def.EyeColor, def.Color)
		e.LightEmission = 0.9
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
end

-- Telegraphs that depend on positions the server fills in as it goes.
function SlotSpawns.Spit(B, i, spot, t0)
	local a = B.def.Attacks.Spit
	local mouth = B.mawPos or (B.vpos + V3(0, B.def.Size * 0.4, 0) + (B.vfacing * B.def.Size * 0.45))
	glob(B, mouth, spot, t0 + a.Tell + (i - 1) * a.Gap)
end

function SlotSpawns.Wail(B, i, spot, t0)
	local a = B.def.Attacks.Wail
	wailRing(B, spot, t0 + a.Tell + (i - 1) * a.Gap)
end

----------------------------------------------------------------------
-- The arena answering phase two: its slime pools brighten
----------------------------------------------------------------------
local POOL_NAMES = { SlimePool = true, SlimePoolDeep = true, SlimePuddle = true, Moat = true, SlimeFall = true }
local function brightenPools(on)
	local arena = Workspace:FindFirstChild("SlimeArena")
	if not arena then
		return
	end
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("BasePart") and POOL_NAMES[d.Name] then
			local base = d:GetAttribute("BaseTransparency")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			tween(d, 1.2, { Transparency = on and math.max(0, base - 0.18) or base })
		end
	end
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
Body.build = buildSlimeBody
Body.pose = applySlimePose

-- what its attacks are made of: slime you can see into
function Body.fx(def)
	return { color = def.Color, deep = def.DeepColor, rock = def.DeepColor, material = Enum.Material.Glass, solid = false }
end

-- its arena settling again when it wakes, sleeps or resets...
function Body.calm(B, name)
	brightenPools(false)
end

-- ...and answering its shell breaking
function Body.breaks(B)
	brightenPools(true)
end

return Body
