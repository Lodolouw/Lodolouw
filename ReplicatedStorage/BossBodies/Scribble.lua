--[[
	Scribble  (ModuleScript, parent: ReplicatedStorage > BossBodies, name: "Scribble")

	How Scribble, the 4th-Dimensional Doodle (floor 9's boss, Config.Bosses[9])
	looks on your screen. He's a DRAWING: a stick figure in blue pen ink, flat
	as paper, who always turns to face your camera (like a paper cut-out) and
	flips to look the way he's going. His lines wobble ("boil") like hand-drawn
	animation, redrawn ten times a second. A round head with two dot eyes and a
	big scribbled grin, a pencil tucked behind his ear. Round 2 he's thick red
	marker; round 3 he glitches through rainbow colours.

	What's drawn for each of his moves (the server's ServerScriptService/
	Bosses/Scribble.lua - its header says which slot is what):
	  PENCIL DASH    a dotted line drawing itself across the paper (a little
	                 pencil drawing it), then him as a streak of ink along it;
	                 then he skids: HIT HIM!
	  ERASER SWEEP   a pink strip across the paper, blinking, then a giant
	                 eraser rubbing it out (crumbs flying)
	  PAINT BUCKET   a grid square outlined, paint dripping into it, then the
	                 flood of paint (it stays wet a while)
	  COPY-PASTE     "CTRL+C" (marching ants round him), "CTRL+V!" - the ink
	                 clones (the server's props): little black stick figures
	                 that run at you and wind up a slash
	  UNDO           the giant Z key (a prop) with its timer; broken, he's
	                 dizzy (HIT HIM!); left alone, "CTRL+Z!" and a blue rewind
	  THE CURSOR     a giant pixel mouse pointer over its shadow, hunting you;
	                 it turns red when it locks, and drops for the click
	  BOSS BAR WHIP  your boss bar vanishes off the top of the screen and drops
	                 into his hand: a giant red bar, swung round low
	  ERROR POP-UPS  window shadows on the floor, the windows dropping out of
	                 the sky onto them, standing (you can't walk through), then
	                 shattering
	  LAG SPIKE      "LAG!", ghosts of him in a line (the last red), then him
	                 skipping from ghost to ghost
	  ROUND 2        he tears himself out of the paper (shreds of paper fly),
	                 red marker now: "ROUND 2 - BREAKING THE 4TH WALL", and a
	                 crack runs across your screen
	  ROUND 3        he glitches into rainbow colours: "ROUND 3 - DELETE"
	  THE DELETE BOX (a prop) a giant "Delete FLOOR 9?" window at the edge of
	                 the paper, counting down, YES and NO - NO pulsing to be
	                 punched; the erased paper is a grey checkerboard (the
	                 "transparent" of every paint program), with the line it's
	                 creeping to in red
	  CRASH          frozen and grey, "SCRIBBLE.EXE IS NOT RESPONDING": HIT HIM!
	  THE END        crumpled into a paper ball and thrown in the recycle bin
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CanvasPlan = require(ReplicatedStorage:WaitForChild("CanvasPlan"))

local RGB = Color3.fromRGB
local V3 = Vector3.new

local Body = {}

-- The drawing kit, from BossClient (see Body.init)
local serverNow, clamp, lerp, smooth, easeOut, spring, flat
local fxFolder, newPart, placeDisc, burst, kick, playSound, addTelegraph, shockRing, at, SLOT_NAMES, bigText, shout

function Body.init(kit)
	serverNow, clamp, lerp, smooth, easeOut, spring, flat = kit.serverNow, kit.clamp, kit.lerp, kit.smooth, kit.easeOut, kit.spring, kit.flat
	fxFolder, newPart, placeDisc, burst = kit.fxFolder, kit.newPart, kit.placeDisc, kit.burst
	kick, playSound, addTelegraph, shockRing, at = kit.kick, kit.playSound, kit.addTelegraph, kit.shockRing, kit.at
	SLOT_NAMES, bigText, shout = kit.SLOT_NAMES, kit.bigText, kit.shout
end

local Poses, Starts, SlotSpawns = {}, {}, {}
Body.Poses, Body.Starts, Body.SlotSpawns = Poses, Starts, SlotSpawns

-- colours that aren't in his Config (the game's 32)
local INK = RGB(24, 20, 37)
local WHITE = RGB(255, 255, 255)
local PAPER_GREY = RGB(192, 203, 220)
local STEEL = RGB(139, 155, 180)
local SLATE = RGB(90, 105, 136)
local NAVY = RGB(18, 78, 137)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local ORANGE = RGB(247, 118, 34)
local GREEN = RGB(99, 199, 77)
local SKY = RGB(44, 232, 245)
local BLUE = RGB(0, 153, 219)
local PURPLE = RGB(104, 56, 108)
local PINK = RGB(246, 117, 122)
local WOOD = RGB(228, 166, 114)
local RAINBOW = { RED, ORANGE, YELLOW, GREEN, SKY, BLUE, PURPLE, PINK }
local PAINTS = { RED, YELLOW, GREEN, PURPLE }
local ERROR_WORDS = { "ERROR", "404", "LAG", "OOPS!", "NOT RESPONDING", "FATAL ERROR" }
local PIXEL_FONT = nil
pcall(function()
	PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

-- a point on his flat page: x across your screen, y up (a Vector3 with no
-- depth - it adds and scales like one)
local function P2(x, y)
	return V3(x, y, 0)
end

-- his proportions (studs; he's Config's Height tall, you're about 5)
local HIP_Y = 7
local SPINE = 5
local HEAD_R = 2
local UPPER_ARM, FOREARM = 3, 3
local THIGH, SHIN = 3.6, 3.6
local HEAD_SEGS = 12
local GRIN_SEGS = 4

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function slot(B, i)
	local v = B.model:GetAttribute(SLOT_NAMES[i])
	return typeof(v) == "Vector3" and v or nil
end

-- the moments the server sweeps away whatever he's left on the floor (a new
-- round, a reset, the end): warnings that live on after their move stop then
local SWEPT = { Break = true, Glitch = true, Reset = true, Death = true, Dormant = true }
local function swept(B, since)
	return SWEPT[B.action] == true and (B.actionStart or 0) > since
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-3 and v.Unit or fallback
end

-- a block stretched from a to b (world points), `w` wide and `d` deep; its
-- `d` side faces `up` (for his lines: your camera, so you see them `w` wide)
local function stretch(p, a, b, w, d, up)
	local dir = b - a
	local len = dir.Magnitude
	local center = (a + b) / 2
	if len < 1e-3 then
		p.Size = V3(w, d, 0.05)
		p.CFrame = CFrame.new(center)
		return
	end
	p.Size = V3(w, d, len)
	up = up or V3(0, 1, 0)
	if math.abs(dir.Unit:Dot(up)) > 0.98 then
		up = V3(1, 0, 0)
	end
	p.CFrame = CFrame.lookAt(center, center + dir, up)
end

-- a hand-drawn wobble: a steady "random" number from -1 to 1 for (a, b)
local function noise(a, b)
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (x - math.floor(x)) * 2 - 1
end

-- words on a part's face (a SurfaceGui), in pixel letters
local function words(p, text, color, face, back)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Words"
	gui.Face = face or Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(400, 100)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = back and 0 or 1
	label.BackgroundColor3 = back or WHITE
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	if PIXEL_FONT then
		label.FontFace = PIXEL_FONT
	end
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return label
end

-- a disc on the floor, a hair up
local function floorDisc(p, center, diameter)
	placeDisc(p, V3(center.X, center.Y + 0.08, center.Z), diameter, 0.1)
end

-- the plane he's drawn in: square to your camera. Returns the way that's
-- "right" on your screen (flat) and the way toward the camera (flat).
local function camPlane(B, facing)
	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame and cam.CFrame.LookVector or nil
	local l = look and flat(look) or V3(0, 0, 0)
	if l.Magnitude < 0.05 then
		-- no camera to face (or it's looking straight down): face the way he faces
		l = -unitOr(flat(facing or B.vfacing or V3(0, 0, 1)), V3(0, 0, 1))
	end
	l = l.Unit
	return V3(-l.Z, 0, l.X), -l
end

-- which round he looks like now (1, 2 or 3)
local function roundLook(B)
	if B.round3Look then
		return 3
	elseif B.phase2Look then
		return 2
	end
	return 1
end

local function inkColor(B, k, now)
	local r = roundLook(B)
	if r == 3 then
		return RAINBOW[(k + math.floor(now * 8)) % #RAINBOW + 1]
	elseif r == 2 then
		return B.def.MarkerColor
	end
	return B.def.Color
end

----------------------------------------------------------------------
-- The body: every line of him
----------------------------------------------------------------------
function Body.build(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }
	local function add(name, color, t)
		return newPart(name, nil, color, Enum.Material.SmoothPlastic, t or 0, folder)
	end
	body.spine = add("Spine", def.Color)
	body.arms = { add("Arm", def.Color), add("Arm", def.Color), add("Arm", def.Color), add("Arm", def.Color) }
	body.legs = { add("Leg", def.Color), add("Leg", def.Color), add("Leg", def.Color), add("Leg", def.Color) }
	body.head = {}
	for i = 1, HEAD_SEGS do
		body.head[i] = add("Head", def.Color)
	end
	body.fill = { add("HeadFill", WHITE), add("HeadFill", WHITE) }
	body.eyes = { add("Eye", def.CoreColor), add("Eye", def.CoreColor) }
	body.grin = {}
	for i = 1, GRIN_SEGS do
		body.grin[i] = add("Grin", def.CoreColor)
	end
	body.teeth = add("Grin", def.CoreColor)
	body.pencil = { add("Pencil", def.PencilColor), add("Pencil", def.EraserColor), add("Pencil", WOOD), add("Pencil", INK) }
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 0.6, folder)
	-- the dizzy stars (stunned, crashed) and the paper ball (the end)
	body.stars = {}
	for i = 1, 3 do
		body.stars[i] = add("DizzyStar", YELLOW, 1)
	end
	body.ball = {}
	for i = 1, 4 do
		body.ball[i] = add("PaperBall", WHITE, 1)
	end
	folder.Parent = fxFolder
	return body
end

-- His standing pose, facing right on your screen. Angles in radians: an arm
-- or leg at 0 hangs straight down, + swings it forward (the way he faces),
-- pi points it straight up; the spine at 0 stands straight, + leans forward.
local function standing()
	return {
		spine = 0.04, head = 0, hipY = HIP_Y, x = 0, y = 0,
		bu = -0.4, bl = -0.25, -- the back arm (upper, lower)
		fu = 0.85, fl = -0.45, -- the front arm: a cheeky hand on his hip
		bt = -0.2, bs = -0.14, -- the back leg (thigh, shin)
		ft = 0.22, fs = 0.14, -- the front leg
		eyes = 1, grin = 1, dizzy = 0, grey = 0, draw = 1, sketch = 0, crumple = 0, jitter = 0,
	}
end

-- the way BossClient plays a pose: his standing pose (breathing, walking)
-- first, then the move's own shape on top
function Body.runPose(B, shape, t, now, P)
	local f = standing()
	f.y = 0.12 * math.sin(now * 2 * math.pi / 1.6)
	if B.model:GetAttribute("Moving") then
		-- a bouncy cartoon run
		local c = now * 2 * math.pi * 2.2
		f.ft, f.bt = 0.75 * math.sin(c), -0.75 * math.sin(c)
		f.fs = f.ft - 0.6 * math.max(0, math.cos(c))
		f.bs = f.bt - 0.6 * math.max(0, -math.cos(c))
		f.fu, f.fl = -0.7 * math.sin(c), -0.7 * math.sin(c) + 0.9
		f.bu, f.bl = 0.7 * math.sin(c), 0.7 * math.sin(c) + 0.9
		f.spine = 0.2
		f.y = 0.35 * math.abs(math.sin(c))
	end
	P.fig = f
	shape(B, t, P)
end

-- where every joint is (2D, facing right: x forward on your screen, y up),
-- from a pose
local function joints(f)
	local function from(o, ang, len)
		return o + P2(math.sin(ang), -math.cos(ang)) * len
	end
	local hips = P2(f.x, f.y + f.hipY)
	local neck = hips + P2(math.sin(f.spine), math.cos(f.spine)) * SPINE
	local shoulder = neck + P2(math.sin(f.spine), math.cos(f.spine)) * -0.5
	local head = neck + P2(math.sin(f.spine + f.head), math.cos(f.spine + f.head)) * (HEAD_R + 0.2)
	local j = { hips = hips, neck = neck, head = head, shoulder = shoulder }
	j.be = from(shoulder, f.bu, UPPER_ARM)
	j.bh = from(j.be, f.bl, FOREARM)
	j.fe = from(shoulder, f.fu, UPPER_ARM)
	j.fh = from(j.fe, f.fl, FOREARM)
	j.bk = from(hips, f.bt, THIGH)
	j.bf = from(j.bk, f.bs, SHIN)
	j.fk = from(hips, f.ft, THIGH)
	j.ff = from(j.fk, f.fs, SHIN)
	return j
end

-- Draws a stick figure (him, a clone, a ghost) from pose `f` at `base` (a
-- point on the floor), `scale` times his size, facing `flipDir` (+1 right,
-- -1 left on your screen). `lines` = { spine, arms[4], legs[4], head[n] },
-- `color(k)` gives line k's colour.
local function drawFigure(lines, f, base, right, toCam, flipDir, scale, width, color, boilT, boilAmp)
	local J = joints(f)
	local up = V3(0, 1, 0)
	local function world(v, k)
		local jx, jy = 0, 0
		if boilAmp and boilAmp > 0 then
			jx, jy = noise(boilT, k) * boilAmp, noise(boilT + 17, k) * boilAmp
		end
		return base + right * ((v.X + jx) * flipDir * scale) + up * ((v.Y + jy) * scale) + toCam * 0.05
	end
	local k = 0
	local function line(p, a, b, ka, kb)
		k = k + 1
		stretch(p, world(a, ka), world(b, kb), width * scale, 0.4 * scale, toCam)
		if color then
			p.Color = color(k)
		end
	end
	if lines.spine then
		line(lines.spine, J.hips, J.neck, 1, 2)
	end
	if lines.arms then
		line(lines.arms[1], J.shoulder, J.be, 3, 4)
		line(lines.arms[2], J.be, J.bh, 4, 5)
		line(lines.arms[3], J.shoulder, J.fe, 3, 6)
		line(lines.arms[4], J.fe, J.fh, 6, 7)
	end
	if lines.legs then
		line(lines.legs[1], J.hips, J.bk, 1, 8)
		line(lines.legs[2], J.bk, J.bf, 8, 9)
		line(lines.legs[3], J.hips, J.fk, 1, 10)
		line(lines.legs[4], J.fk, J.ff, 10, 11)
	end
	if lines.head then
		local n = #lines.head
		for i = 1, n do
			local a0, a1 = (i - 1) / n * math.pi * 2, i / n * math.pi * 2
			local r = HEAD_R
			line(lines.head[i], J.head + P2(math.cos(a0), math.sin(a0)) * r, J.head + P2(math.cos(a1), math.sin(a1)) * r, 12 + i, 13 + i)
		end
	end
	return J, world
end

----------------------------------------------------------------------
-- Putting him together every frame
----------------------------------------------------------------------
function Body.pose(B, P, ground, facing, t, dt)
	local body, def = B.body, B.def
	local f = P.fig or standing()
	local now = serverNow()
	local right, toCam = camPlane(B, facing)
	-- which way he looks on your screen (a drawing flips; it doesn't turn)
	local want = (facing:Dot(right) >= 0) and 1 or -1
	B.flip = B.flip or want
	if want ~= B.flip and now > (B.flipAt or 0) then
		B.flip = want
		B.flipAt = now + 0.12 -- (no flickering back and forth)
	end
	local flipDir = B.flip
	-- round 3's glitches: a slice of him jumps sideways for a moment now and then
	local r = roundLook(B)
	local glitchX = 0
	if r == 3 or f.jitter > 0 then
		local g = math.floor(now * 12)
		if noise(g, 3) > 0.55 or f.jitter > 0 then
			glitchX = noise(g, 5) * (0.8 + f.jitter * 1.5)
		end
	end
	local base = ground + V3(0, P.lift or 0, 0) + right * glitchX
	B.headWorld = nil
	local scale = 1
	local width = (r == 2) and 1.1 or ((r == 3) and 0.95 or 0.8)
	-- the crumple at the end: everything pulls in to his chest, smaller and smaller
	if f.crumple > 0 then
		local c = f.crumple
		local mid = P2(f.x, f.y + f.hipY + SPINE * 0.5)
		f.hipY = lerp(f.hipY, mid.Y - f.y, c)
		f.bu, f.fu, f.bt, f.ft = f.bu + c * 2, f.fu + c * 2, f.bt + c * 1.5, f.ft - c * 1.5
		scale = 1 - 0.85 * c
	end
	-- the pencil line he's drawn with: 10 wobbles a second (like a hand-drawn cartoon)
	local boilT = math.floor(now * 10)
	local boil = 0.12 + (r == 3 and 0.1 or 0)
	local sketch = f.sketch
	local lineColor = function(k)
		if f.grey > 0.5 then
			return STEEL
		end
		if sketch > 0.5 then
			return PAPER_GREY
		end
		return inkColor(B, k, now)
	end
	local lines = { spine = body.spine, arms = body.arms, legs = body.legs, head = body.head }
	local J, world = drawFigure(lines, f, base, right, toCam, flipDir, scale, width, lineColor, boilT, boil)
	-- drawing himself in (waking): the lines appear one after another
	local order = { body.legs[1], body.legs[2], body.legs[3], body.legs[4], body.spine, body.arms[1], body.arms[2], body.arms[3], body.arms[4] }
	for _, h in ipairs(body.head) do
		table.insert(order, h)
	end
	local n = #order
	local fade = P.fade or 0
	local ballOn = f.crumple >= 0.999
	for i, p in ipairs(order) do
		local inked = f.draw >= i / n - 1e-3
		if ballOn then
			p.Transparency = 1
		elseif sketch >= 0.5 then
			p.Transparency = math.max(fade, 0.4)
		elseif inked then
			p.Transparency = fade
		else
			-- (not inked yet: still the pencil sketch)
			p.Color = PAPER_GREY
			p.Transparency = 0.4
		end
	end
	-- the face: a white head, two dot eyes (on the side he's looking), a big grin
	local hc = J.head
	local faceOn = f.draw >= 0.999 and not ballOn and sketch < 0.5
	local fw = world(hc, 40)
	B.headWorld = fw
	local fr = HEAD_R * 0.92 * 2 * scale
	for i, p in ipairs(body.fill) do
		p.Size = (i == 1) and V3(fr, fr * 0.66, 0.2 * scale) or V3(fr * 0.66, fr, 0.2 * scale)
		p.CFrame = CFrame.lookAt(fw - toCam * 0.12, fw - toCam * 0.12 + toCam)
		p.Transparency = faceOn and fade or 1
	end
	local look = 0.35 * flipDir
	local dizzy = f.dizzy
	for i, p in ipairs(body.eyes) do
		local ex = (i == 1 and -0.65 or 0.65) + look
		local ey = 0.35
		if dizzy > 0 then
			-- dizzy: the eyes roll round
			ex = ex + math.cos(now * 9 + i * 3) * 0.2
			ey = ey + math.sin(now * 9 + i * 3) * 0.2
		end
		local e = world(hc + P2(ex * flipDir, ey), 0)
		p.Size = V3(0.45 * scale, math.max(0.1, 0.75 * f.eyes) * scale, 0.3 * scale)
		p.CFrame = CFrame.lookAt(e, e + toCam)
		p.Transparency = faceOn and fade or 1
	end
	-- the grin: a wide scribbly smile (a small "o" when he's dizzy)
	local g = f.grin
	for i, p in ipairs(body.grin) do
		local a0 = math.pi * (1.15 + 0.7 * (i - 1) / GRIN_SEGS)
		local a1 = math.pi * (1.15 + 0.7 * i / GRIN_SEGS)
		local rr = lerp(0.35, 1.25, g)
		local cy = lerp(-0.7, -0.05, g)
		-- (x here is "forward" on his page: world() turns it the way he faces)
		local pa = world(hc + P2(math.cos(a0) * rr + 0.18, cy + math.sin(a0) * rr * lerp(1, 0.75, g)), 50 + i)
		local pb = world(hc + P2(math.cos(a1) * rr + 0.18, cy + math.sin(a1) * rr * lerp(1, 0.75, g)), 51 + i)
		stretch(p, pa, pb, 0.32 * scale, 0.3 * scale, toCam)
		p.Transparency = faceOn and fade or 1
	end
	-- (a line across the grin: his teeth)
	local ta = world(hc + P2(-0.85 * g + 0.18, -0.6), 60)
	local tb = world(hc + P2(0.85 * g + 0.18, -0.6), 61)
	stretch(body.teeth, ta, tb, 0.22 * scale, 0.3 * scale, toCam)
	body.teeth.Transparency = (faceOn and g > 0.5) and fade or 1
	-- the pencil behind his ear (the back of his head)
	local pb0 = hc + P2(-1.5, 0.9)
	local ang = math.rad(55)
	local dirP = P2(math.cos(ang), math.sin(ang))
	local segs = { { -1.2, 0.6, body.pencil[2] }, { -0.6, 1.2, body.pencil[1] }, { 1.2, 1.7, body.pencil[3] }, { 1.7, 2.0, body.pencil[4] } }
	for _, s in ipairs(segs) do
		local a = world(pb0 + dirP * s[1], 70)
		local b = world(pb0 + dirP * s[2], 70)
		stretch(s[3], a - toCam * 0.1, b - toCam * 0.1, (s[3] == body.pencil[4]) and 0.3 * scale or 0.55 * scale, 0.5 * scale, toCam)
		s[3].Transparency = faceOn and fade or 1
	end
	-- the dizzy stars going round his head
	for i, p in ipairs(body.stars) do
		if dizzy > 0 and not ballOn then
			local a = now * 5 + i * math.pi * 2 / 3
			local sp = world(hc + P2(math.cos(a) * 2.6, 2.2 + math.sin(a) * 0.6), 0)
			p.Size = V3(0.8, 0.8, 0.8)
			p.CFrame = CFrame.new(sp) * CFrame.Angles(0, now * 4, math.rad(45))
			p.Transparency = 0
		else
			p.Transparency = 1
		end
	end
	-- his shadow on the paper
	local sd = (ballOn and 2 or 5) * (1 - fade)
	floorDisc(body.shadow, V3(base.X, ground.Y, base.Z), math.max(0.1, sd - math.min(3, (P.lift or 0) * 0.2)))
	body.shadow.Transparency = (fade >= 0.99 or sketch > 0.5) and 1 or 0.6
	-- the paper ball (the end): drawn by Poses.Death's numbers
	local bp = P.ballPos
	for i, p in ipairs(body.ball) do
		if ballOn and bp then
			local s = P.ballSize or 3
			p.Size = V3(s * (0.7 + 0.1 * i), s * (0.8 - 0.05 * i), s * (0.75 + 0.05 * i))
			p.CFrame = CFrame.new(bp) * CFrame.Angles(now * 5 + i, now * 3.3 + i * 0.7, i)
			p.Color = (i % 2 == 0) and WHITE or PAPER_GREY
			p.Transparency = P.ballFade or 0
		else
			p.Transparency = 1
		end
	end
	B.handWorld = world(J.fh, 7)
	B.bodyTop = world(hc + P2(0, HEAD_R), 0)
	B.J, B.world, B.right, B.toCam, B.flipNow = J, world, right, toCam, flipDir
end

----------------------------------------------------------------------
-- The warnings and effects of his moves
----------------------------------------------------------------------
-- PENCIL DASH: when dash k starts, and how long it takes (the server's sums)
local function dashTimes(B, k)
	local a = B.def.Attacks.PencilDash
	local start = (B.actionStart or 0) + a.Tell
	for i = 1, k do
		local s, e = slot(B, 2 * i - 1), slot(B, 2 * i)
		if not (s and e) then
			return nil
		end
		local travel = math.max(0.12, flat(e - s).Magnitude / a.Speed)
		if i == k then
			return start, travel, s, e
		end
		start = start + travel + a.Chain
	end
	return nil
end

-- A DOTTED LINE drawing itself from `s` to `e` before `startAt` (a little
-- pencil drawing it), then eaten up by his dash
local function dashLine(B, k, s, e, startAt, travel)
	local shownAt = serverNow()
	local len = flat(e - s).Magnitude
	local dir = unitOr(flat(e - s), V3(0, 0, 1))
	local n = math.max(2, math.floor(len / 2.2))
	local dots = {}
	for i = 1, n do
		dots[i] = newPart("DashLine", nil, B.def.InkDeep, Enum.Material.SmoothPlastic, 1)
	end
	local pencil = newPart("DrawPencil", nil, B.def.PencilColor, Enum.Material.SmoothPlastic, 1)
	local streak = newPart("InkStreak", nil, B.def.InkDeep, Enum.Material.SmoothPlastic, 1)
	local drawTime = math.max(0.2, (startAt - shownAt) * 0.6)
	playSound(B.def, "Draw", s, 0.6)
	addTelegraph(B, {
		update = function(now)
			if now > startAt + travel + 0.5 then
				return false
			end
			local drawn = clamp((now - shownAt) / drawTime, 0, 1)
			local passed = clamp((now - startAt) / travel, 0, 1)
			local blink = (startAt - now < 0.25 and now < startAt) and (math.floor(now * 16) % 2 == 0)
			for i, d in ipairs(dots) do
				local u = (i - 0.5) / n
				local p = s + dir * (u * len)
				d.Size = V3(0.9, 0.1, 1.2)
				d.CFrame = CFrame.lookAt(V3(p.X, s.Y + 0.1, p.Z), V3(p.X, s.Y + 0.1, p.Z) + dir)
				d.Color = blink and RED or B.def.InkDeep
				d.Transparency = (u <= drawn and u > passed) and 0 or 1
			end
			-- the little pencil at the drawing end
			if drawn < 1 then
				local tip = s + dir * (drawn * len)
				pencil.Size = V3(0.6, 3, 0.6)
				pencil.CFrame = CFrame.new(V3(tip.X, s.Y + 1.6, tip.Z)) * CFrame.Angles(0.4, 0, 0.3)
				pencil.Transparency = 0
			else
				pencil.Transparency = 1
			end
			-- the streak of ink behind him as he goes
			if now >= startAt and now < startAt + travel + 0.4 then
				local head = s + dir * (passed * len)
				local tail = s + dir * (math.max(0, passed * len - 14))
				local fadeOut = clamp((now - startAt - travel) / 0.4, 0, 1)
				stretch(streak, V3(tail.X, s.Y + 3, tail.Z), V3(head.X, s.Y + 3, head.Z), 2.2, 4, V3(0, 1, 0))
				streak.Transparency = 0.25 + 0.75 * fadeOut
			else
				streak.Transparency = 1
			end
			return true
		end,
		cleanup = function()
			for _, d in ipairs(dots) do
				d:Destroy()
			end
			pencil:Destroy()
			streak:Destroy()
		end,
	})
	at(B, startAt, function()
		playSound(B.def, "Dash", s, 1)
		burst(s + V3(0, 1, 0), B.def.InkDeep, 14, 18, 1.4, 0.5)
	end)
	local _ = k
end

-- AN ERASER STRIP: pink across the paper, blinking, then a giant eraser
-- rubbing it out from Tell for Time seconds
local function eraserStrip(B, c, ax, t0)
	local a = B.def.Attacks.EraserSweep
	local half = CanvasPlan.paperNow(B.model, serverNow())
	local strip = newPart("EraserStrip", nil, B.def.EraserColor, Enum.Material.SmoothPlastic, 1)
	local eraser = newPart("GiantEraser", nil, B.def.EraserColor, Enum.Material.SmoothPlastic, 1)
	local sleeve = newPart("GiantEraser", nil, BLUE, Enum.Material.SmoothPlastic, 1)
	local rubAt, endAt = t0 + a.Tell, t0 + a.Tell + a.Time
	local across = V3(-ax.Z, 0, ax.X)
	addTelegraph(B, {
		update = function(now)
			if now > endAt + 0.4 or swept(B, t0) then
				return false
			end
			local p = c + V3(0, 0.12, 0)
			strip.Size = V3(a.Width, 0.1, half * 2)
			strip.CFrame = CFrame.lookAt(p, p + ax)
			if now < rubAt then
				local blink = (rubAt - now < 0.3) and (math.floor(now * 16) % 2 == 0)
				strip.Color = blink and RED or B.def.EraserColor
				strip.Transparency = 0.45 - 0.25 * clamp((now - t0) / a.Tell, 0, 1)
			else
				-- being rubbed out: pink while it hurts to stand on, fading at the end
				strip.Color = B.def.EraserColor
				strip.Transparency = 0.3 + 0.7 * clamp((now - endAt) / 0.4, 0, 1)
			end
			if now >= rubAt - 0.25 and now < endAt then
				local u = (now - rubAt) / 0.5
				local along = math.sin(u * math.pi) * (half - 6)
				local ep = c + ax * along + V3(0, 3 + math.abs(math.cos(u * math.pi * 2)) * 0.8, 0)
				local cf = CFrame.lookAt(ep, ep + ax) * CFrame.Angles(0, 0, math.rad(8) * math.sin(u * 6))
				eraser.Size = V3(a.Width - 1, 5, 9)
				eraser.CFrame = cf
				eraser.Transparency = 0
				sleeve.Size = V3(a.Width - 0.6, 5.3, 4)
				sleeve.CFrame = cf * CFrame.new(0, 0, 2.6)
				sleeve.Transparency = 0
			else
				eraser.Transparency = 1
				sleeve.Transparency = 1
			end
			return true
		end,
		cleanup = function()
			strip:Destroy()
			eraser:Destroy()
			sleeve:Destroy()
		end,
	})
	at(B, rubAt, function()
		playSound(B.def, "Erase", c, 1)
		burst(c + V3(0, 1, 0), B.def.EraserColor, 18, 16, 1.2, 0.6)
		kick(c, a.Width, 0.5)
	end)
	local _ = across
end

-- A PAINT SQUARE: a grid square outlined, paint dripping into it from a
-- tipped bucket above, then the flood; it stays wet a while, then dries
local function paintSquare(B, i, mid, t0)
	local a = B.def.Attacks.PaintBucket
	local size = CanvasPlan.Cell
	local color = PAINTS[(i - 1) % #PAINTS + 1]
	local edges = {}
	for k = 1, 4 do
		edges[k] = newPart("PaintSquare", nil, color, Enum.Material.SmoothPlastic, 1)
	end
	local drips = {}
	for k = 1, 3 do
		drips[k] = newPart("PaintDrip", nil, color, Enum.Material.SmoothPlastic, 1)
	end
	local bucket = newPart("PaintBucketIcon", nil, STEEL, Enum.Material.SmoothPlastic, 1)
	local flood = newPart("PaintFlood", nil, color, Enum.Material.SmoothPlastic, 1)
	local floodAt, dryAt = t0 + a.Tell, t0 + a.Tell + a.Wet
	addTelegraph(B, {
		update = function(now)
			if now > dryAt + 0.6 or swept(B, t0) then
				return false
			end
			local y = mid.Y + 0.14
			local blink = now < floodAt and (floodAt - now < 0.3) and (math.floor(now * 16) % 2 == 0)
			for k, e in ipairs(edges) do
				local sx = (k <= 2) and 1 or 0
				local off = (k % 2 == 1) and -1 or 1
				if sx == 1 then
					e.Size = V3(size, 0.12, 0.6)
					e.CFrame = CFrame.new(mid + V3(0, y - mid.Y, off * (size / 2 - 0.3)))
				else
					e.Size = V3(0.6, 0.12, size)
					e.CFrame = CFrame.new(mid + V3(off * (size / 2 - 0.3), y - mid.Y, 0))
				end
				e.Color = blink and RED or color
				e.Transparency = now < floodAt and 0 or 1
			end
			-- the bucket, tipped over the square, and the paint dripping from it
			if now < floodAt + 0.2 then
				local bp = mid + V3(0, 13, 0)
				bucket.Size = V3(4, 4, 4)
				bucket.CFrame = CFrame.new(bp) * CFrame.Angles(0, 0, math.rad(-35 - 60 * clamp((now - floodAt + 0.4) / 0.4, 0, 1)))
				bucket.Transparency = 0
				for k, d in ipairs(drips) do
					local u = ((now - t0) * 1.6 + k / 3) % 1
					d.Size = V3(0.8, 1.4, 0.8)
					d.CFrame = CFrame.new(mid + V3((k - 2) * 1.5, 12 - u * 12, 0))
					d.Transparency = now < floodAt and 0 or 1
				end
			else
				bucket.Transparency = 1
				for _, d in ipairs(drips) do
					d.Transparency = 1
				end
			end
			-- the flood: up it comes, glossy, then it dries and fades
			if now >= floodAt then
				local rise = easeOut(clamp((now - floodAt) / 0.25, 0, 1))
				flood.Size = V3(size - 0.4, 0.1 + 0.3 * rise, size - 0.4)
				flood.CFrame = CFrame.new(mid + V3(0, 0.1 + 0.15 * rise, 0))
				flood.Transparency = 0.1 + 0.9 * clamp((now - dryAt) / 0.6, 0, 1)
			else
				flood.Transparency = 1
			end
			return true
		end,
		cleanup = function()
			for _, e in ipairs(edges) do
				e:Destroy()
			end
			for _, d in ipairs(drips) do
				d:Destroy()
			end
			bucket:Destroy()
			flood:Destroy()
		end,
	})
	at(B, floodAt, function()
		if i == 1 then
			playSound(B.def, "Paint", mid, 1)
			kick(mid, size / 2, 0.6)
		end
		burst(mid + V3(0, 1, 0), color, 20, 22, 1.6, 0.6)
	end)
end

-- LAG GHOSTS: see-through copies of him in a line, flickering (the last
-- red, with its circle); each goes as he skips onto it
local function lagGhosts(B, t0)
	local a = B.def.Attacks.LagSpike
	local ghosts = {}
	for k = 1, a.Frames do
		local g = { lines = { spine = nil, arms = {}, legs = {}, head = {} }, parts = {} }
		local function add(name)
			local p = newPart(name, nil, (k == a.Frames) and RED or B.def.Color, Enum.Material.SmoothPlastic, 1)
			table.insert(g.parts, p)
			return p
		end
		g.lines.spine = add("LagGhost")
		for i = 1, 4 do
			g.lines.arms[i] = add("LagGhost")
			g.lines.legs[i] = add("LagGhost")
		end
		for i = 1, 8 do
			g.lines.head[i] = add("LagGhost")
		end
		if k == a.Frames then
			g.ring = newPart("LagWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
		end
		ghosts[k] = g
	end
	local endAt = t0 + a.Tell + (a.Frames - 1) * a.Step + 0.3
	addTelegraph(B, {
		update = function(now)
			if now > endAt then
				return false
			end
			local right, toCam = camPlane(B, B.vfacing)
			for k, g in ipairs(ghosts) do
				local spot = slot(B, k)
				local arrive = t0 + a.Tell + (k - 1) * a.Step
				local on = spot and now < arrive and B.action == "LagSpike"
				if on then
					local f = standing()
					f.spine, f.ft, f.bt, f.fu, f.bu = 0.35, 0.7, -0.6, -0.9, 0.9
					local flicker = (math.floor(now * 20 + k) % 3 ~= 0)
					drawFigure(g.lines, f, spot, right, toCam, B.flipNow or 1, 1, 0.7, nil, math.floor(now * 10), 0.2)
					for _, p in ipairs(g.parts) do
						p.Transparency = flicker and 0.45 or 0.8
					end
					if g.ring then
						floorDisc(g.ring, spot, (a.LastRadius + 1.5) * 2)
						g.ring.Transparency = (arrive - now < 0.3 and math.floor(now * 16) % 2 == 0) and 0.2 or 0.55
					end
				else
					for _, p in ipairs(g.parts) do
						p.Transparency = 1
					end
					if g.ring then
						g.ring.Transparency = 1
					end
				end
			end
			return true
		end,
		cleanup = function()
			for _, g in ipairs(ghosts) do
				for _, p in ipairs(g.parts) do
					p:Destroy()
				end
				if g.ring then
					g.ring:Destroy()
				end
			end
		end,
	})
end

-- THE CURSOR: a giant pixel mouse pointer over its shadow. The shadow
-- follows the model's Cursor attribute (smoothly); once it locks (a slot),
-- it goes red and stops, and at the click the pointer drops onto it.
local function arrowParts(B)
	local rows = { 1, 2, 3, 4, 5, 6, 7, 5, 3 }
	local list = {}
	for r, n in ipairs(rows) do
		table.insert(list, { r = r, x = 0, w = n, color = INK, p = newPart("CursorArrow", nil, INK, Enum.Material.SmoothPlastic, 1) })
		if n > 2 and r < #rows then
			table.insert(list, { r = r, x = 1, w = n - 2, color = WHITE, p = newPart("CursorArrow", nil, WHITE, Enum.Material.SmoothPlastic, 1), front = true })
		end
	end
	return list
end

local function cursorFX(B, t0)
	local a = B.def.Attacks.Cursor
	local clicks = B.model:GetAttribute("ActN") or 1
	local arrow = arrowParts(B)
	local shadow = newPart("CursorShadow", Enum.PartType.Cylinder, INK, Enum.Material.SmoothPlastic, 1)
	local lastClick = t0 + a.Hunt + a.Lock + (clicks - 1) * (a.Hunt2 + a.Lock)
	local shown = nil
	addTelegraph(B, {
		update = function(now)
			if now > lastClick + 0.35 or (B.action ~= "Cursor" and now > t0 + 0.2) then
				return false
			end
			local target = B.model:GetAttribute("Cursor")
			-- which click is coming, and is it locked yet?
			local k = 1
			while k < clicks and now > t0 + a.Hunt + a.Lock + (k - 1) * (a.Hunt2 + a.Lock) + 0.05 do
				k = k + 1
			end
			local clickAt = t0 + a.Hunt + a.Lock + (k - 1) * (a.Hunt2 + a.Lock)
			local locked = slot(B, k)
			if locked and now >= clickAt - a.Lock - 0.05 then
				target = locked
			end
			if typeof(target) == "Vector3" then
				shown = shown and shown:Lerp(target, 0.35) or target
			end
			if not shown then
				return true
			end
			local isLocked = locked ~= nil and now >= clickAt - a.Lock - 0.05
			-- the pointer: hovering high, bobbing; dropping for the click
			local drop = 0
			if now >= clickAt - 0.1 and now < clickAt + 0.2 then
				drop = 1 - clamp(math.abs(now - clickAt) / 0.1, 0, 1)
			end
			local hover = lerp(12 + 0.6 * math.sin(now * 5), 1.5, drop)
			local cf = CFrame.new(shown + V3(0, hover, 0)) * CFrame.Angles(0, 0, math.rad(-20))
			local u = 1.1 -- (studs a pixel)
			local camLook = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame and Workspace.CurrentCamera.CFrame.LookVector
			local face = camLook and flat(camLook) or V3(0, 0, -1)
			face = face.Magnitude > 0.05 and face.Unit or V3(0, 0, -1)
			local rightV = V3(-face.Z, 0, face.X)
			for _, b in ipairs(arrow) do
				local x0 = (b.x + b.w / 2) * u
				local y0 = -(b.r - 0.5) * u
				local pos = cf.Position + rightV * x0 + V3(0, y0 * 1, 0) - face * (b.front and 0.3 or 0)
				b.p.Size = V3(b.w * u, u, 0.6)
				b.p.CFrame = CFrame.lookAt(pos, pos - face)
				b.p.Color = (isLocked and not b.front) and RED or b.color
				b.p.Transparency = 0
			end
			floorDisc(shadow, shown, (a.Radius + 1.5) * 2)
			shadow.Color = isLocked and RED or INK
			shadow.Transparency = isLocked and ((math.floor(now * 14) % 2 == 0) and 0.15 or 0.45) or 0.55
			return true
		end,
		cleanup = function()
			for _, b in ipairs(arrow) do
				b.p:Destroy()
			end
			shadow:Destroy()
		end,
	})
	for k = 1, clicks do
		at(B, t0 + a.Hunt + a.Lock + (k - 1) * (a.Hunt2 + a.Lock), function()
			local spot = slot(B, k) or shown
			if spot then
				playSound(B.def, "Click", spot, 1)
				shockRing(B, spot, 1, a.Radius + 3, 0.3, WHITE)
				kick(spot, a.Radius, 0.7)
			end
		end)
	end
end

-- THE BOSS BAR WHIP: the bar drops out of the sky into his raised hand, then
-- swings round low (from slot 1, the tip at the start); a red ring on the
-- floor shows how far it reaches
local function whipFX(B, t0)
	local a = B.def.Attacks.BarWhip
	local signed = B.model:GetAttribute("ActN") or 1
	local dir = signed >= 0 and 1 or -1
	local turns = math.abs(signed)
	local frame = newPart("WhipBar", nil, INK, Enum.Material.SmoothPlastic, 1)
	local fill = newPart("WhipBar", nil, RED, Enum.Material.SmoothPlastic, 1)
	local shine = newPart("WhipBar", nil, PINK, Enum.Material.SmoothPlastic, 1)
	local ring = newPart("WhipWarning", Enum.PartType.Cylinder, RED, Enum.Material.Neon, 1)
	local spinStart = t0 + a.Tell
	local spinEnd = spinStart + turns * a.Spin
	local centre = B.vpos
	addTelegraph(B, {
		update = function(now)
			if now > spinEnd + 0.3 or (B.action ~= "BarWhip" and now > t0 + 0.2) then
				return false
			end
			local y = centre.Y + 2.4
			local p0, p1
			if now < spinStart then
				centre = B.vpos
				-- ripped off your screen: it drops out of the sky into his hand
				local u = clamp((now - t0 - a.Tell * 0.25) / (a.Tell * 0.4), 0, 1)
				local hand = B.handWorld or (centre + V3(0, 12, 0))
				local top = hand + V3(0, 60 * (1 - easeOut(u)), 0)
				p0, p1 = top, top + V3(0, a.Length * 0.6 * u, 0)
				ring.Transparency = u > 0 and ((math.floor(now * 10) % 2 == 0) and 0.4 or 0.6) or 1
				floorDisc(ring, centre, (a.Length + 1.5) * 2)
				local shown = u > 0
				frame.Transparency, fill.Transparency, shine.Transparency = shown and 0 or 1, shown and 0 or 1, shown and 0 or 1
			else
				local s = slot(B, 1)
				local a0 = s and math.atan2(s.X - centre.X, s.Z - centre.Z) or 0
				local ang = a0 + dir * 2 * math.pi / a.Spin * (now - spinStart)
				local out = V3(math.sin(ang), 0, math.cos(ang))
				p0 = V3(centre.X, y, centre.Z) + out * 1.5
				p1 = V3(centre.X, y, centre.Z) + out * a.Length
				ring.Transparency = 0.75
				local fadeOut = clamp((now - spinEnd) / 0.3, 0, 1)
				frame.Transparency, fill.Transparency, shine.Transparency = fadeOut, fadeOut, fadeOut
			end
			stretch(frame, p0, p1, 1.9, 1.3, V3(0, 1, 0))
			stretch(fill, p0, p1, 1.4, 1.35, V3(0, 1, 0))
			stretch(shine, p0 + V3(0, 0.45, 0), p1 + V3(0, 0.45, 0), 1.45, 0.45, V3(0, 1, 0))
			return true
		end,
		cleanup = function()
			frame:Destroy()
			fill:Destroy()
			shine:Destroy()
			ring:Destroy()
		end,
	})
	at(B, spinStart, function()
		playSound(B.def, "Whip", centre, 1)
		kick(centre, a.Length, 0.6)
	end)
end

-- AN ERROR WINDOW: its shadow on the floor darkening, the window dropping
-- out of the sky onto it, standing there (a wall), then shattering
local function errorWindow(B, k, spot, t0)
	local a = B.def.Attacks.ErrorPopups
	local dropAt = t0 + a.Tell + (k - 1) * a.Gap
	local landAt = dropAt + a.Fall
	local gone = landAt + a.Stay
	local ax = (k % 2 == 1) and V3(1, 0, 0) or V3(0, 0, 1)
	local H = 8
	local shadowP = newPart("ErrorShadow", nil, INK, Enum.Material.SmoothPlastic, 1)
	local panel = newPart("ErrorWindow", nil, PAPER_GREY, Enum.Material.SmoothPlastic, 1)
	local bar = newPart("ErrorWindow", nil, NAVY, Enum.Material.SmoothPlastic, 1)
	local icon = newPart("ErrorIcon", nil, RED, Enum.Material.SmoothPlastic, 1)
	local ok = newPart("ErrorOK", nil, WHITE, Enum.Material.SmoothPlastic, 1)
	local word = ERROR_WORDS[(k - 1) % #ERROR_WORDS + 1]
	local frontLabel = words(bar, word, WHITE, Enum.NormalId.Front)
	local backLabel = words(bar, word, WHITE, Enum.NormalId.Back)
	words(icon, "X", WHITE, Enum.NormalId.Front)
	words(icon, "X", WHITE, Enum.NormalId.Back)
	words(ok, "OK", INK, Enum.NormalId.Front)
	words(ok, "OK", INK, Enum.NormalId.Back)
	local win = { c = spot, ax = ax, half = a.Width / 2, depth = a.Depth / 2, from = landAt, till = gone }
	B.windows = B.windows or {}
	table.insert(B.windows, win)
	local shattered = false
	addTelegraph(B, {
		update = function(now)
			if now > gone + 0.1 then
				return false
			end
			-- the shadow: darker as it comes
			local u = clamp((now - dropAt) / a.Fall, 0, 1)
			if now < landAt then
				shadowP.Size = V3(a.Width * (0.6 + 0.4 * u), 0.1, a.Depth + 1)
				shadowP.CFrame = CFrame.lookAt(spot + V3(0, 0.1, 0), spot + V3(0, 0.1, 0) + V3(-ax.Z, 0, ax.X))
				shadowP.Transparency = 0.8 - 0.45 * u
			else
				shadowP.Transparency = 1
			end
			local y = (now < landAt) and (40 * (1 - u * u)) or 0
			local base = spot + V3(0, y, 0)
			local cf = CFrame.lookAt(base + V3(0, H / 2, 0), base + V3(0, H / 2, 0) + V3(-ax.Z, 0, ax.X))
			if now >= dropAt then
				panel.Size = V3(a.Width, H, a.Depth)
				panel.CFrame = cf
				bar.Size = V3(a.Width, 1.8, a.Depth + 0.1)
				bar.CFrame = cf * CFrame.new(0, H / 2 - 0.9, 0)
				icon.Size = V3(2.4, 2.4, a.Depth + 0.15)
				icon.CFrame = cf * CFrame.new(-a.Width / 2 + 2.2, 0.4, 0)
				ok.Size = V3(3.2, 1.6, a.Depth + 0.15)
				ok.CFrame = cf * CFrame.new(a.Width / 2 - 2.6, -H / 2 + 1.4, 0)
				panel.Transparency, bar.Transparency, icon.Transparency, ok.Transparency = 0, 0, 0, 0
			else
				panel.Transparency, bar.Transparency, icon.Transparency, ok.Transparency = 1, 1, 1, 1
			end
			if now >= gone - 0.05 and not shattered then
				shattered = true
				burst(spot + V3(0, H / 2, 0), PAPER_GREY, 24, 20, 1.2, 0.6, true)
			end
			return true
		end,
		cleanup = function()
			shadowP:Destroy()
			panel:Destroy()
			bar:Destroy()
			icon:Destroy()
			ok:Destroy()
			for i, w in ipairs(B.windows or {}) do
				if w == win then
					table.remove(B.windows, i)
					break
				end
			end
		end,
	})
	at(B, landAt, function()
		playSound(B.def, "Popup", spot, 0.9)
		burst(spot + V3(0, 0.5, 0), PAPER_GREY, 14, 14, 1.2, 0.5)
		kick(spot, a.Width / 2, 0.5)
	end)
	local _ = frontLabel
	local _ = backLabel
end

-- MARCHING ANTS round him (CTRL+C: he's selected)
local function selectBox(B, t0, untilT)
	local edges = {}
	for k = 1, 4 do
		edges[k] = newPart("SelectBox", nil, INK, Enum.Material.SmoothPlastic, 1)
	end
	addTelegraph(B, {
		update = function(now)
			if now > untilT or B.action ~= "CopyPaste" then
				return false
			end
			local right, toCam = B.right or V3(1, 0, 0), B.toCam or V3(0, 0, 1)
			local c = B.vpos + V3(0, B.def.Height / 2, 0)
			local w, h = 9, B.def.Height + 1.5
			local on = (math.floor(now * 8) % 2 == 0)
			local corners = { c + right * (-w / 2) + V3(0, -h / 2, 0), c + right * (w / 2) + V3(0, -h / 2, 0), c + right * (w / 2) + V3(0, h / 2, 0), c + right * (-w / 2) + V3(0, h / 2, 0) }
			for k, e in ipairs(edges) do
				stretch(e, corners[k] + toCam * 0.4, corners[k % 4 + 1] + toCam * 0.4, 0.35, 0.3, toCam)
				e.Color = on and INK or WHITE
				e.Transparency = 0
			end
			return true
		end,
		cleanup = function()
			for _, e in ipairs(edges) do
				e:Destroy()
			end
		end,
	})
end

-- PAPER SHREDS flying up (round 2: tearing out of the paper)
local function shreds(B, from, count)
	local list = {}
	for i = 1, count do
		local p = newPart("PaperShred", nil, (i % 3 == 0) and PAPER_GREY or WHITE, Enum.Material.SmoothPlastic, 0)
		local a = i / count * math.pi * 2
		table.insert(list, { p = p, v = V3(math.cos(a) * (8 + (i % 4) * 3), 22 + (i % 5) * 4, math.sin(a) * (8 + (i % 3) * 3)), spin = i })
	end
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local t = now - t0
			if t > 1.6 then
				return false
			end
			for _, s in ipairs(list) do
				local pos = from + s.v * t + V3(0, -30 * t * t, 0)
				s.p.Size = V3(2.2, 0.2, 1.6)
				s.p.CFrame = CFrame.new(pos) * CFrame.Angles(t * 6 + s.spin, t * 4, s.spin)
				s.p.Transparency = clamp((t - 1.1) / 0.5, 0, 1)
			end
			return true
		end,
		cleanup = function()
			for _, s in ipairs(list) do
				s.p:Destroy()
			end
		end,
	})
end

-- a CRACK across your screen (round 2: the 4th wall breaking), fading away
local function screenCrack()
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ScribbleCrack"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 24
	gui:SetAttribute("RetroSkip", true)
	local lines = {
		{ 0.5, 0.45, 0.62, 0.30, 40 }, { 0.5, 0.45, 0.30, 0.38, -20 }, { 0.5, 0.45, 0.58, 0.70, 60 },
		{ 0.5, 0.45, 0.36, 0.64, -55 }, { 0.62, 0.30, 0.78, 0.22, 20 }, { 0.30, 0.38, 0.14, 0.30, -35 },
	}
	for _, l in ipairs(lines) do
		local x0, y0, x1, y1 = l[1], l[2], l[3], l[4]
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale((x0 + x1) / 2, (y0 + y1) / 2)
		local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		f.Size = UDim2.new(len, 0, 0, 5)
		f.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
		f.BackgroundColor3 = WHITE
		f.BorderSizePixel = 0
		f.Parent = gui
	end
	gui.Parent = pg
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 1.6 and gui.Parent do
			local k = clamp((os.clock() - t0 - 0.8) / 0.8, 0, 1)
			for _, f in ipairs(gui:GetChildren()) do
				if f:IsA("Frame") then
					f.BackgroundTransparency = k
				end
			end
			task.wait()
		end
		gui:Destroy()
	end)
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- ASLEEP: a faint pencil sketch of him, waiting to be inked
function Poses.Dormant(B, t, P)
	local f = P.fig
	f.sketch = 1
	f.eyes = 0.2
	f.y = 0
	local _ = B
	local _ = t
end

-- WAKING: a pencil inks him in, line by line... he blinks, grins, hops
function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local f = P.fig
	local u = clamp(t / (W * 0.7), 0, 1)
	f.draw = u
	f.sketch = (u < 0.02) and 1 or 0
	if t > W * 0.72 then
		local k = clamp((t - W * 0.72) / (W * 0.28), 0, 1)
		P.lift = 3 * math.sin(math.pi * k)
		f.fu, f.fl = lerp(0.85, 2.6, math.sin(math.pi * k)), lerp(-0.45, 2.9, math.sin(math.pi * k))
		f.bu = lerp(-0.4, -2.6, math.sin(math.pi * k))
	end
	f.eyes = (t > W * 0.7) and 1 or 0.2
end

-- EVERYONE'S GONE: he's rubbed out, back to a faint sketch
function Poses.Reset(B, t, P)
	local f = P.fig
	f.draw = 1 - clamp(t / 1.4, 0, 1)
	f.sketch = (t > 1.4) and 1 or 0
	if t > 1.4 then
		f.draw = 1
	end
	local _ = B
end

-- PENCIL DASH: crouch, arms back... WHOOSH along the line (exactly on it),
-- then a skid, arms windmilling: wide open
function Poses.PencilDash(B, t, P)
	local a = B.def.Attacks.PencilDash
	local f = P.fig
	local now = serverNow()
	local count = B.model:GetAttribute("ActN") or 1
	for k = 1, count do
		local start, travel, s, e = dashTimes(B, k)
		if start and now >= start - a.Chain and now < start + travel then
			if now < start then
				-- (between dashes: crouched, ready)
				f.hipY, f.spine, f.bu, f.fu = HIP_Y - 1.4, 0.55, -2.1, -1.7
				f.ft, f.fs, f.bt, f.bs = 0.9, -0.2, -0.6, -1.1
				return
			end
			local u = (now - start) / travel
			P.override = s:Lerp(e, u)
			P.facing = unitOr(flat(e - s), B.vfacing)
			f.spine, f.hipY = 1.25, HIP_Y - 1.5
			f.bu, f.bl, f.fu, f.fl = -1.9, -1.8, -1.6, -1.5
			f.bt, f.bs, f.ft, f.fs = -1.3, -1.5, -0.9, -1.2
			P.lift = 1.5
			return
		end
	end
	local first = dashTimes(B, 1)
	if first and now < first then
		-- the tell: crouching lower and lower, arms swept back
		local k = smooth(clamp(t / a.Tell, 0, 1))
		f.hipY = HIP_Y - 1.4 * k
		f.spine = 0.55 * k
		f.bu, f.fu = lerp(-0.4, -2.1, k), lerp(0.85, -1.7, k)
		f.fl = lerp(-0.45, -1.6, k)
		f.ft, f.fs = lerp(0.22, 0.9, k), lerp(0.14, -0.2, k)
		f.bt, f.bs = lerp(-0.2, -0.6, k), lerp(-0.14, -1.1, k)
		return
	end
	-- the skid: leaning way back, front foot out, arms windmilling
	local lastStart, lastTravel = dashTimes(B, count)
	local since = lastStart and (now - lastStart - lastTravel) or t
	local w = math.sin(since * 14)
	f.spine = -0.45
	f.ft, f.fs = 1.1, 1.3
	f.bt, f.bs = -0.2, -0.6
	f.fu, f.fl = 2.4 + 0.6 * w, 2.8 + 0.6 * w
	f.bu, f.bl = -2.4 - 0.6 * w, -2.8 - 0.6 * w
	f.grin, f.eyes = 0.3, 1.2
end

-- ERASER SWEEP: arms up, then scrubbing away
function Poses.EraserSweep(B, t, P)
	local a = B.def.Attacks.EraserSweep
	local f = P.fig
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		f.fu, f.fl = lerp(0.85, 2.7, k), lerp(-0.45, 3.0, k)
		f.bu, f.bl = lerp(-0.4, 2.2, k), lerp(-0.25, 2.8, k)
	else
		local s = math.sin((t - a.Tell) * 18)
		f.fu, f.fl = 1.4 + 0.5 * s, 1.6 + 0.6 * s
		f.bu, f.bl = 1.1 - 0.4 * s, 1.4 - 0.5 * s
		f.spine = 0.3
	end
end

-- PAINT BUCKET: an imaginary bucket held out... tipped over
function Poses.PaintBucket(B, t, P)
	local a = B.def.Attacks.PaintBucket
	local f = P.fig
	local k = smooth(clamp(t / a.Tell, 0, 1))
	f.fu, f.fl = lerp(0.85, 1.5, k), lerp(-0.45, 1.9, k)
	f.bu, f.bl = lerp(-0.4, 1.3, k), lerp(-0.25, 1.7, k)
	if t > a.Tell * 0.8 then
		local p = clamp((t - a.Tell * 0.8) / 0.3, 0, 1)
		f.spine = 0.35 * p
		f.fl, f.bl = f.fl + 0.8 * p, f.bl + 0.8 * p
	end
end

-- COPY-PASTE: hands up by his head ("CTRL+C")... then a shove out to both
-- sides ("CTRL+V!")
function Poses.CopyPaste(B, t, P)
	local a = B.def.Attacks.CopyPaste
	local f = P.fig
	if t < a.Tell * 0.6 then
		local k = smooth(t / (a.Tell * 0.6))
		f.fu, f.fl = lerp(0.85, 2.5, k), lerp(-0.45, 3.1, k)
		f.bu, f.bl = lerp(-0.4, -2.5, k), lerp(-0.25, -3.1, k)
	else
		local k = easeOut(clamp((t - a.Tell * 0.6) / 0.25, 0, 1))
		f.fu, f.fl = lerp(2.5, 1.6, k), lerp(3.1, 1.6, k)
		f.bu, f.bl = lerp(-2.5, -1.6, k), lerp(-3.1, -1.6, k)
	end
end

-- UNDO: pointing at the key, wagging a finger, grinning
function Poses.Undo(B, t, P)
	local f = P.fig
	f.fu, f.fl = 1.4, 1.5
	f.bu, f.bl = -0.2, 2.6 + 0.4 * math.sin(t * 12)
	f.grin = 1.2
	local _ = B
end

-- STUNNED (the key broken): swaying, arms limp, eyes rolling
function Poses.Stunned(B, t, P)
	local f = P.fig
	local s = math.sin(t * 5)
	f.spine, f.head = 0.25 * s, -0.3 * s
	f.fu, f.fl, f.bu, f.bl = 0.15, 0.05, -0.15, -0.05
	f.dizzy, f.grin, f.hipY = 1, 0, HIP_Y - 0.5
	local _ = B
end

-- UNDONE (CTRL+Z): arms up, delighted
function Poses.Undone(B, t, P)
	local f = P.fig
	local k = easeOut(clamp(t / 0.25, 0, 1))
	f.fu, f.fl = lerp(0.85, 2.7, k), lerp(-0.45, 3.0, k)
	f.bu, f.bl = lerp(-0.4, -2.7, k), lerp(-0.25, -3.0, k)
	P.lift = 1.2 * math.sin(math.pi * clamp(t / 0.5, 0, 1))
	f.grin = 1.3
	local _ = B
end

-- THE CURSOR: a hand on an invisible mouse, sliding it about
function Poses.Cursor(B, t, P)
	local f = P.fig
	f.fu, f.fl = 1.0 + 0.1 * math.sin(t * 6), 1.6 + 0.15 * math.sin(t * 6)
	f.spine = 0.15
	f.grin = 1.2
	local _ = B
end

-- BOSS BAR WHIP: reaching right up (for your screen's bar)... then spinning
-- round, arms out, holding it
function Poses.BarWhip(B, t, P)
	local a = B.def.Attacks.BarWhip
	local f = P.fig
	if t < a.Tell then
		local k = smooth(clamp(t / (a.Tell * 0.5), 0, 1))
		f.fu, f.fl = lerp(0.85, 3.0, k), lerp(-0.45, 3.1, k)
		P.lift = 1.2 * k
		if t > a.Tell * 0.6 then
			local pull = smooth((t - a.Tell * 0.6) / (a.Tell * 0.4))
			f.fu, f.fl = lerp(3.0, 1.57, pull), lerp(3.1, 1.57, pull)
		end
	else
		f.fu, f.fl, f.bu, f.bl = 1.57, 1.57, -1.57, -1.57
		f.spine = -0.15
		f.ft, f.bt = 0.35, -0.35
	end
end

-- ERROR POP-UPS: waving his arms at the sky
function Poses.ErrorPopups(B, t, P)
	local f = P.fig
	local s = math.sin(t * 10)
	f.fu, f.fl = 2.6 + 0.3 * s, 2.9 + 0.3 * s
	f.bu, f.bl = -2.6 + 0.3 * s, -2.9 + 0.3 * s
	f.grin = 1.2
	local _ = B
end

-- LAG SPIKE: stuttering on the spot... then skipping from ghost to ghost
function Poses.LagSpike(B, t, P)
	local a = B.def.Attacks.LagSpike
	local f = P.fig
	local now = serverNow()
	f.jitter = 1
	f.spine, f.ft, f.bt, f.fu, f.bu = 0.35, 0.7, -0.6, -0.9, 0.9
	if t >= a.Tell then
		local k = math.min(a.Frames, math.floor((t - a.Tell) / a.Step) + 1)
		local spot = slot(B, k)
		if spot then
			P.override = spot
		end
	end
	local _ = now
end

-- CRASH (NO pressed): frozen stiff and grey, a little dizzy
function Poses.Crash(B, t, P)
	local f = P.fig
	f.fu, f.fl, f.bu, f.bl = 2.2, 2.2, -2.2, -2.2
	f.grey = 1
	f.dizzy = 1
	f.grin = 0
	f.jitter = (t < 0.4) and 1 or 0
	local _ = B
end

-- ROUND 2: he grabs the edges... and tears himself out of the paper,
-- fists up, red marker now
function Poses.Break(B, t, P)
	local T = B.def.BreakTime
	local f = P.fig
	if t < T * 0.35 then
		local k = smooth(t / (T * 0.35))
		f.hipY = HIP_Y - 2 * k
		f.fu, f.fl, f.bu, f.bl = lerp(0.85, -0.3, k), lerp(-0.45, 0.4, k), lerp(-0.4, 0.3, k), lerp(-0.25, -0.4, k)
		f.jitter = k
	else
		local k = easeOut(clamp((t - T * 0.35) / 0.4, 0, 1))
		P.lift = 2.5 * k * (1 - clamp((t - T * 0.6) / (T * 0.3), 0, 1))
		f.fu, f.fl, f.bu, f.bl = 2.8, 3.0, -2.8, -3.0
		f.grin = 1.3
	end
end

-- ROUND 3: glitching through colours, arms thrown up
function Poses.Glitch(B, t, P)
	local f = P.fig
	f.jitter = 1
	f.fu, f.fl, f.bu, f.bl = 2.8 + 0.3 * math.sin(t * 30), 3.0, -2.8 + 0.3 * math.cos(t * 26), -3.0
	f.grin = 1.3
	local _ = B
end

-- THE END: he crumples into a paper ball... which is thrown into the
-- recycle bin
local function binSpot(B)
	local arena = Workspace:FindFirstChild("CanvasArena")
	local bin = arena and arena:GetAttribute("Bin")
	return typeof(bin) == "Vector3" and bin or nil
end

function Poses.Death(B, t, P)
	local f = P.fig
	f.crumple = clamp(t / 1.1, 0, 1)
	f.dizzy = 1
	f.grin = 0
	if f.crumple >= 1 then
		local start = B.deathFrom or (B.vpos + V3(0, 3, 0))
		B.deathFrom = start
		local bin = binSpot(B) or (start + V3(40, 10, -40))
		local u = clamp((t - 1.3) / 1.5, 0, 1)
		local p = start:Lerp(bin + V3(0, 1.5, 0), u) + V3(0, 26 * math.sin(math.pi * u), 0)
		if u >= 1 then
			p = bin + V3(0, 1.5 - clamp((t - 2.8) / 0.4, 0, 1) * 5, 0)
		end
		P.ballPos = p
		P.ballSize = 4.5
		P.ballFade = clamp((t - 3.2) / 0.3, 0, 1)
	end
end

----------------------------------------------------------------------
-- Starts and slots: the sounds, words and warnings of each move
----------------------------------------------------------------------
function Starts.Wake(B, t0)
	B.deathFrom = nil
	at(B, t0 + 0.1, function()
		playSound(B.def, "Draw", B.vpos, 0.7)
	end)
	at(B, t0 + B.def.WakeTime * 0.72 - (B.def.WakeSoundLead or 0.3), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + B.def.WakeTime * 0.72, function()
		burst(B.vpos + V3(0, 2, 0), B.def.Color, 20, 18, 1.6, 0.7, true)
		kick(B.vpos, 24, 0.6)
	end)
end

function Starts.Reset(B, t0)
	at(B, t0 + 0.2, function()
		burst(B.vpos + V3(0, 3, 0), B.def.EraserColor, 16, 12, 1.2, 0.6, true)
	end)
end

function Starts.PencilDash(B, t0)
	local _ = t0
	playSound(B.def, "Draw", B.vpos, 0.5)
end

function SlotSpawns.PencilDash(B, i, spot, t0)
	local _ = spot
	local _ = t0
	if i % 2 == 0 then
		local k = i / 2
		local start, travel, s, e = dashTimes(B, k)
		if start then
			dashLine(B, k, s, e, start, travel)
			local count = B.model:GetAttribute("ActN") or 1
			if k == count then
				at(B, start + travel, function()
					playSound(B.def, "Skid", e, 0.9)
					burst(e + V3(0, 0.5, 0), PAPER_GREY, 16, 14, 1.2, 0.6)
				end)
			end
		end
	end
end

function SlotSpawns.EraserSweep(B, i, spot, t0)
	if i % 2 == 0 then
		local c = slot(B, i - 1)
		if c then
			eraserStrip(B, c, unitOr(flat(spot - c), V3(1, 0, 0)), t0)
		end
	end
end

function SlotSpawns.PaintBucket(B, i, spot, t0)
	paintSquare(B, i, spot, t0)
end

function Starts.CopyPaste(B, t0)
	local a = B.def.Attacks.CopyPaste
	selectBox(B, t0, t0 + a.Tell)
	if B.body and B.body.spine then
		shout(B.body.spine, "CTRL+C", 0.9, WHITE)
	end
	at(B, t0 + a.Tell * 0.6, function()
		shout(B.body.spine, "CTRL+V!", 1.0, YELLOW)
		playSound(B.def, "Copy", B.vpos, 1)
	end)
end

function SlotSpawns.CopyPaste(B, i, spot, t0)
	local _ = i
	local _ = t0
	burst(spot + V3(0, 2, 0), INK, 12, 12, 1.2, 0.5)
end

function Starts.Undo(B, t0)
	local _ = t0
	playSound(B.def, "Key", B.vpos, 0.8)
end

function Starts.Stunned(B, t0)
	local _ = t0
	playSound(B.def, "Stun", B.vpos, 1)
	kick(B.vpos, 20, 0.5)
end

function Starts.Undone(B, t0)
	local _ = t0
	shout(B.body.spine, "CTRL+Z!", 1.2, SKY)
	playSound(B.def, "Undo", B.vpos, 1)
	-- a blue rewind swirl round him
	local swirl = {}
	for k = 1, 8 do
		swirl[k] = newPart("RewindArrow", nil, SKY, Enum.Material.Neon, 1)
	end
	local s0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local t = now - s0
			if t > 0.9 then
				return false
			end
			for k, p in ipairs(swirl) do
				local a = -t * 9 + k / 8 * math.pi * 2
				local r = 5 + t * 3
				p.Size = V3(1.6, 0.5, 0.5)
				local pos = B.vpos + V3(math.cos(a) * r, 3 + k * 1.2, math.sin(a) * r)
				p.CFrame = CFrame.lookAt(pos, pos + V3(-math.sin(a), 0, math.cos(a)))
				p.Transparency = clamp(t / 0.9, 0, 1)
			end
			return true
		end,
		cleanup = function()
			for _, p in ipairs(swirl) do
				p:Destroy()
			end
		end,
	})
end

function Starts.Cursor(B, t0)
	cursorFX(B, t0)
end

function Starts.BarWhip(B, t0)
	whipFX(B, t0)
end

function SlotSpawns.ErrorPopups(B, i, spot, t0)
	errorWindow(B, i, spot, t0)
end

function Starts.ErrorPopups(B, t0)
	local _ = t0
	shout(B.body.spine, "404", 0.9, RED)
end

function Starts.LagSpike(B, t0)
	shout(B.body.spine, "LAG!", 1.1, RED)
	playSound(B.def, "Lag", B.vpos, 1)
	lagGhosts(B, t0)
end

function Starts.Crash(B, t0)
	local _ = t0
	playSound(B.def, "Crash", B.vpos, 1)
	kick(B.vpos, 30, 0.8)
	burst(B.vpos + V3(0, 8, 0), STEEL, 20, 14, 1.4, 0.7, true)
	local label = shout(B.body.spine, "SCRIBBLE.EXE IS NOT RESPONDING", B.def.Delete.Crash, WHITE)
	local _ = label
end

function Starts.Break(B, t0)
	local T = B.def.BreakTime
	at(B, t0 + T * 0.35, function()
		B.phase2Look = true
		shreds(B, B.vpos + V3(0, 2, 0), 14)
		playSound(B.def, "Break", B.vpos, 1)
		kick(B.vpos, B.def.BreakReach, 1.2, -5)
		bigText("ROUND 2", { sub = "BREAKING THE 4TH WALL", color = RED })
		screenCrack()
	end)
end

function Starts.Glitch(B, t0)
	local T = B.def.GlitchTime
	playSound(B.def, "Glitch", B.vpos, 1)
	at(B, t0 + T * 0.4, function()
		B.round3Look = true
		kick(B.vpos, B.def.BreakReach, 1.2, -5)
		bigText("DELETE", { sub = "ROUND 3", color = RED })
		burst(B.vpos + V3(0, 6, 0), RED, 24, 24, 1.8, 0.8, true)
	end)
end

function Starts.Death(B, t0)
	B.deathFrom = nil
	at(B, t0 + 0.2, function()
		playSound(B.def, "Death", B.vpos, 1)
	end)
	at(B, t0 + 2.8, function()
		local bin = binSpot(B)
		if bin then
			burst(bin + V3(0, 2, 0), WHITE, 16, 14, 1.4, 0.6, true)
		end
	end)
end

----------------------------------------------------------------------
-- Every frame: his props (clones, the Z key, the DELETE box), the erased
-- edge of the paper, "HIT HIM!"
----------------------------------------------------------------------
-- AN INK CLONE (the server's Workspace.ScribbleProps): a little black stick
-- figure that runs at you, winds up a slash (its arm back, going red) and
-- slashes (a streak); popped, it splats; left alone, it smudges away
local function makeClone(B, inst)
	local rec = { kind = "Clone", inst = inst, parts = {}, lines = { arms = {}, legs = {}, head = {} } }
	local function add(name, color)
		local p = newPart(name, nil, color, Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	rec.lines.spine = add("CloneBody", INK)
	for i = 1, 4 do
		rec.lines.arms[i] = add("CloneBody", INK)
		rec.lines.legs[i] = add("CloneBody", INK)
	end
	for i = 1, 8 do
		rec.lines.head[i] = add("CloneBody", INK)
	end
	rec.eye = add("CloneEye", WHITE)
	rec.slash = add("CloneSlash", RED)
	return rec
end

local function stepClone(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.8) then
		return false
	end
	local pos = hit.Position - V3(0, 2.5, 0)
	local dir = flat(hit.CFrame.LookVector)
	local right, toCam = camPlane(B, dir)
	local flipDir = (dir:Dot(right) >= 0) and 1 or -1
	local moved = rec.last and flat(pos - rec.last).Magnitude > 0.02
	rec.last = pos
	local f = standing()
	local c = now * 2 * math.pi * 2.6
	if moved then
		f.ft, f.bt = 0.8 * math.sin(c), -0.8 * math.sin(c)
		f.fs, f.bs = f.ft - 0.5, f.bt - 0.5
		f.fu, f.bu = -0.8 * math.sin(c), 0.8 * math.sin(c)
		f.spine = 0.25
	end
	local warnAt, slashAt = inst:GetAttribute("SwipeWarn"), inst:GetAttribute("SwipeAt")
	local winding = warnAt and slashAt and now >= warnAt and now < slashAt
	local slashing = slashAt and now >= slashAt and now < slashAt + 0.18
	if winding then
		f.fu, f.fl = -2.4, -2.9
		f.spine = -0.2
	elseif slashing then
		f.fu, f.fl = 1.6, 1.4
		f.spine = 0.4
	end
	local fade = 0
	if endKind == "Smudge" or endKind == "Gone" then
		fade = clamp((now - endAt) / 0.6, 0, 1)
	elseif endKind == "Broken" then
		fade = 1
	end
	local J, world = drawFigure(rec.lines, f, pos, right, toCam, flipDir, 0.45, 1.0, function()
		return winding and ((math.floor(now * 14) % 2 == 0) and RED or INK) or INK
	end, math.floor(now * 10), 0.15)
	for _, p in ipairs(rec.parts) do
		if p ~= rec.slash and p ~= rec.eye then
			p.Transparency = math.max(0.15, fade)
		end
	end
	local e = world(J.head + P2(0.5 * flipDir, 0.3), 0)
	rec.eye.Size = V3(0.35, 0.45, 0.2)
	rec.eye.CFrame = CFrame.lookAt(e + toCam * 0.2, e + toCam)
	rec.eye.Transparency = fade
	if slashing then
		local sd = inst:GetAttribute("SwipeDir")
		sd = typeof(sd) == "Vector3" and sd or dir
		local p0 = pos + V3(0, 2, 0) + sd * 1 + V3(-sd.Z, 0, sd.X) * 3
		local p1 = pos + V3(0, 2, 0) + sd * 4.5 - V3(-sd.Z, 0, sd.X) * 3
		stretch(rec.slash, p0, p1, 0.6, 0.6, V3(0, 1, 0))
		rec.slash.Transparency = 0.2
	else
		rec.slash.Transparency = 1
	end
	if endKind == "Broken" and not rec.splat then
		rec.splat = true
		burst(pos + V3(0, 2, 0), INK, 18, 16, 1.2, 0.5)
	end
	return true
end

-- THE Z KEY: a big grey keyboard key with a Z on it, floating and bobbing,
-- its timer running down above it
local function makeKey(B, inst)
	local rec = { kind = "UndoKey", inst = inst, parts = {} }
	local function add(name, color)
		local p = newPart(name, nil, color, Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	rec.cap = add("ZKey", PAPER_GREY)
	rec.top = add("ZKey", WHITE)
	rec.base = add("ZKey", STEEL)
	rec.timer = add("KeyTimer", SKY)
	rec.letterFront = words(rec.top, "Z", INK, Enum.NormalId.Top)
	words(rec.cap, "Z", INK, Enum.NormalId.Front)
	words(rec.cap, "Z", INK, Enum.NormalId.Back)
	words(rec.cap, "Z", INK, Enum.NormalId.Left)
	words(rec.cap, "Z", INK, Enum.NormalId.Right)
	return rec
end

local function stepKey(B, rec, now)
	local inst = rec.inst
	local hit = inst.PrimaryPart
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if not hit or (endKind and now - endAt > 0.6) then
		return false
	end
	local c = hit.Position + V3(0, 0.3 * math.sin(now * 4), 0)
	local hp = (inst:GetAttribute("Health") or 1) / math.max(inst:GetAttribute("MaxHealth") or 1, 1)
	local press = 0
	if endKind == "Undo" then
		press = clamp((now - endAt) / 0.15, 0, 1)
	end
	local shake = (hp < 0.99) and 0.15 * math.sin(now * 40) or 0
	local cf = CFrame.new(c + V3(shake, -press * 0.8, 0)) * CFrame.Angles(0, now * 0.8, 0)
	rec.cap.Size = V3(4, 2.2, 4)
	rec.cap.CFrame = cf
	rec.top.Size = V3(3.4, 0.3, 3.4)
	rec.top.CFrame = cf * CFrame.new(0, 1.2, 0)
	rec.base.Size = V3(4.4, 0.6, 4.4)
	rec.base.CFrame = cf * CFrame.new(0, -1.4, 0)
	local untilT = inst:GetAttribute("Until") or now
	local born = inst:GetAttribute("Born") or now
	local left = clamp((untilT - now) / math.max(untilT - born, 0.1), 0, 1)
	rec.timer.Size = V3(4.4 * left, 0.5, 0.5)
	rec.timer.CFrame = CFrame.new(c + V3(0, 3.2, 0))
	rec.timer.Color = left < 0.35 and RED or SKY
	local fade = (endKind == "Broken") and 1 or (endKind and clamp((now - endAt) / 0.5, 0, 1) or 0)
	for _, p in ipairs(rec.parts) do
		p.Transparency = fade
	end
	rec.timer.Transparency = endKind and 1 or 0
	if endKind == "Broken" and not rec.smashed then
		rec.smashed = true
		burst(c, PAPER_GREY, 20, 18, 1.2, 0.6, true)
	end
	return true
end

-- THE DELETE BOX: a giant window at the edge of the paper: "DELETE?" on its
-- title bar, "Delete FLOOR 9?", the countdown, YES and NO (NO pulsing - punch
-- it!). Pressed, NO squashes in and the box folds away; left alone, YES
-- presses itself, the box flashes red, and it folds away
local function makeBox(B, inst)
	local rec = { kind = "NoButton", inst = inst, parts = {} }
	local function add(name, color)
		local p = newPart(name, nil, color, Enum.Material.SmoothPlastic, 1)
		table.insert(rec.parts, p)
		return p
	end
	rec.panel = add("DeleteBox", WHITE)
	rec.frame = add("DeleteBox", STEEL)
	rec.bar = add("DeleteBox", NAVY)
	rec.icon = add("DeleteIcon", RED)
	rec.yes = add("YesButton", PAPER_GREY)
	rec.no = add("NoButton", YELLOW)
	rec.hint = add("NoHint", YELLOW)
	words(rec.bar, "DELETE?", WHITE, Enum.NormalId.Front)
	words(rec.icon, "!", WHITE, Enum.NormalId.Front)
	words(rec.yes, "YES", INK, Enum.NormalId.Front)
	words(rec.no, "NO", INK, Enum.NormalId.Front)
	rec.text = words(rec.panel, "DELETE FLOOR 9?", INK, Enum.NormalId.Front)
	return rec
end

local function stepBox(B, rec, now)
	local inst = rec.inst
	local endKind = inst:GetAttribute("EndKind")
	local endAt = inst:GetAttribute("EndAt") or now
	if endKind and now - endAt > 0.7 then
		return false
	end
	local side = inst:GetAttribute("Side") or 1
	local to = inst:GetAttribute("To") or CanvasPlan.Half
	local base, face, noAt, yesAt = CanvasPlan.promptSpots(side, to)
	-- (the NO button is where the server put it: the paper's middle is back from it)
	local centre = inst.PrimaryPart and (inst.PrimaryPart.Position - V3(noAt.X, CanvasPlan.ButtonUp, noAt.Z)) or B.vpos
	local W, H = CanvasPlan.BoxWidth, CanvasPlan.BoxHeight
	-- it pops up (and folds away at the end)
	local born = inst:GetAttribute("Born") or now
	local pop = easeOut(clamp((now - born) / 0.25, 0, 1))
	local fold = endKind and clamp((now - endAt - 0.25) / 0.35, 0, 1) or 0
	local s = pop * (1 - fold)
	local b = centre + base
	local mid = b + V3(0, H / 2 * s, 0) - face * 0.6
	local cf = CFrame.lookAt(mid, mid + face)
	rec.panel.Size = V3(W * s, H * s, 0.6)
	rec.panel.CFrame = cf
	rec.frame.Size = V3(W * s + 1, H * s + 1, 0.5)
	rec.frame.CFrame = cf * CFrame.new(0, 0, 0.1)
	rec.bar.Size = V3(W * s, 2.4 * s, 0.7)
	rec.bar.CFrame = cf * CFrame.new(0, H / 2 * s - 1.2 * s, 0)
	rec.icon.Size = V3(3.2 * s, 3.2 * s, 0.7)
	rec.icon.CFrame = cf * CFrame.new(-W / 2 * s + 3 * s, 2.2 * s, 0)
	-- the countdown, and the words
	local untilT = inst:GetAttribute("Until") or now
	local left = math.max(0, math.ceil(untilT - now))
	if rec.text then
		rec.text.Text = endKind == "Yes" and "DELETED!" or (endKind == "Pressed" and "CANCELLED" or ("DELETE FLOOR 9?  " .. left))
		rec.text.TextColor3 = (endKind == "Yes" or (left <= 2 and math.floor(now * 8) % 2 == 0)) and RED or INK
	end
	-- the buttons
	local hp = (inst:GetAttribute("Health") or 1) / math.max(inst:GetAttribute("MaxHealth") or 1, 1)
	local pulse = 1 + 0.08 * math.sin(now * 10)
	local noPress = (endKind == "Pressed") and 0.5 or 0
	local yesPress = (endKind == "Yes") and 0.5 or 0
	local up = V3(0, CanvasPlan.ButtonUp, 0)
	local function button(p, off, w, h, press)
		local pos = centre + off + up * s - face * (0.4 - press)
		p.Size = V3(w * s, h * s, 1.4 - press)
		p.CFrame = CFrame.lookAt(pos, pos + face)
	end
	button(rec.yes, yesAt, 7, 3.4, yesPress)
	button(rec.no, noAt, 7 * (endKind and 1 or pulse), 3.4 * (endKind and 1 or pulse), noPress)
	rec.no.Color = (hp < 0.99) and ORANGE or YELLOW
	-- a bouncing arrow over NO: punch it!
	local hy = CanvasPlan.ButtonUp + 3.6 + 0.6 * math.abs(math.sin(now * 6))
	rec.hint.Size = V3(1.2 * s, 2 * s, 1.2 * s)
	rec.hint.CFrame = CFrame.new(centre + noAt + V3(0, hy, 0) + face * 0.5) * CFrame.Angles(0, 0, math.rad(45))
	local flash = (endKind == "Yes" and now - endAt < 0.25 and math.floor(now * 16) % 2 == 0)
	rec.panel.Color = flash and RED or WHITE
	for _, p in ipairs(rec.parts) do
		p.Transparency = (s <= 0.01) and 1 or 0
	end
	rec.hint.Transparency = (endKind or s < 0.99) and 1 or 0
	if endKind and not rec.ended then
		rec.ended = true
		if endKind == "Yes" then
			playSound(B.def, "Crash", b, 1)
			kick(b, 40, 1.1, -4)
			bigText("DELETED!", { color = RED, hold = 0.6 })
		end
	end
	if not rec.announced then
		rec.announced = true
		playSound(B.def, "Delete", b, 1)
	end
	return true
end

local PROP_MAKERS = { Clone = makeClone, UndoKey = makeKey, NoButton = makeBox }
local PROP_STEPS = { Clone = stepClone, UndoKey = stepKey, NoButton = stepBox }

local function stepProps(B, now)
	B.props = B.props or {}
	local folder = Workspace:FindFirstChild("ScribbleProps")
	if folder then
		for _, inst in ipairs(folder:GetChildren()) do
			local kind = inst:GetAttribute("Kind")
			if inst:IsA("Model") and not B.props[inst] and PROP_MAKERS[kind] and inst:GetAttribute("Floor") == B.floor then
				B.props[inst] = PROP_MAKERS[kind](B, inst)
			end
		end
	end
	for inst, rec in pairs(B.props) do
		local keep = rec and inst.Parent ~= nil and PROP_STEPS[rec.kind](B, rec, now)
		if not keep then
			if rec then
				for _, p in ipairs(rec.parts) do
					p:Destroy()
				end
			end
			B.props[inst] = nil
		end
	end
end

-- THE ERASED EDGE (round 3): outside the square of paper that's left, a
-- grey checkerboard (the "transparent" of every paint program); a black
-- line round what's left; while a DELETE box is up, a red line where the
-- erasing will stop
local CHECK = 6
local function stepEdge(B, now)
	local m = B.model
	local half = CanvasPlan.paperNow(m, now)
	local to = m:GetAttribute("EraseTo")
	local arena = Workspace:FindFirstChild("CanvasArena")
	local centre = arena and arena:GetAttribute("Center") or nil
	if typeof(centre) ~= "Vector3" then
		return
	end
	local full = CanvasPlan.Half
	local need = half < full - 0.05 or type(to) == "number"
	if not need then
		if B.edge then
			for _, p in ipairs(B.edge.all) do
				p.Transparency = 1
			end
		end
		return
	end
	if not B.edge then
		local e = { bands = {}, lines = {}, target = {}, tiles = {}, all = {} }
		for k = 1, 4 do
			e.bands[k] = newPart("ErasedEdge", nil, PAPER_GREY, Enum.Material.SmoothPlastic, 1)
			e.lines[k] = newPart("EraseLine", nil, INK, Enum.Material.SmoothPlastic, 1)
			e.target[k] = newPart("EraseTarget", nil, RED, Enum.Material.Neon, 1)
			table.insert(e.all, e.bands[k])
			table.insert(e.all, e.lines[k])
			table.insert(e.all, e.target[k])
		end
		-- the checkerboard's dark squares, in the ring the paper can be erased
		-- from (each shows once it's wholly erased)
		local minPaper = B.def.Delete.MinPaper
		for x = -full, full - CHECK, CHECK do
			for z = -full, full - CHECK, CHECK do
				local cx, cz = x + CHECK / 2, z + CHECK / 2
				local outer = math.max(math.abs(cx), math.abs(cz))
				if ((x + z) / CHECK) % 2 == 0 and outer + CHECK / 2 > minPaper then
					local p = newPart("ErasedEdge", nil, STEEL, Enum.Material.SmoothPlastic, 1)
					table.insert(e.tiles, { p = p, x = cx, z = cz })
					table.insert(e.all, p)
				end
			end
		end
		B.edge = e
	end
	local e = B.edge
	local y = centre.Y + 0.09
	-- the four grey bands between what's left and the paper's edge
	local w = full - half
	local specs = {
		{ V3(0, 0, -(half + w / 2)), V3(full * 2, 0.1, w) },
		{ V3(0, 0, half + w / 2), V3(full * 2, 0.1, w) },
		{ V3(-(half + w / 2), 0, 0), V3(w, 0.1, half * 2) },
		{ V3(half + w / 2, 0, 0), V3(w, 0.1, half * 2) },
	}
	for k, sp in ipairs(specs) do
		local band = e.bands[k]
		if w > 0.05 then
			band.Size = sp[2]
			band.CFrame = CFrame.new(V3(centre.X + sp[1].X, y, centre.Z + sp[1].Z))
			band.Transparency = 0
		else
			band.Transparency = 1
		end
	end
	for _, tile in ipairs(e.tiles) do
		local outside = math.max(math.abs(tile.x), math.abs(tile.z)) - CHECK / 2 >= half
		if outside then
			tile.p.Size = V3(CHECK, 0.12, CHECK)
			tile.p.CFrame = CFrame.new(V3(centre.X + tile.x, y + 0.01, centre.Z + tile.z))
			tile.p.Transparency = 0
		else
			tile.p.Transparency = 1
		end
	end
	-- the line round what's left, and the red line it's being erased to
	local function square(parts, h, width, show)
		local lines = {
			{ V3(0, 0, -h), V3(h * 2 + width, 0.14, width) },
			{ V3(0, 0, h), V3(h * 2 + width, 0.14, width) },
			{ V3(-h, 0, 0), V3(width, 0.14, h * 2 + width) },
			{ V3(h, 0, 0), V3(width, 0.14, h * 2 + width) },
		}
		for k, l in ipairs(lines) do
			local p = parts[k]
			if show then
				p.Size = l[2]
				p.CFrame = CFrame.new(V3(centre.X + l[1].X, y + 0.03, centre.Z + l[1].Z))
				p.Transparency = 0
			else
				p.Transparency = 1
			end
		end
	end
	square(e.lines, half, 0.5, half < full - 0.05)
	local blink = math.floor(now * 6) % 2 == 0
	square(e.target, (type(to) == "number" and to) or half, 0.6, type(to) == "number" and to < half - 0.05 and blink)
end

-- "HIT HIM!" over him while he's open: skidding after a dash, stunned,
-- crashed
local function openNow(B, now)
	local t0 = B.actionStart
	if not t0 then
		return nil
	end
	if B.action == "Stunned" or B.action == "Crash" then
		return "HIT HIM!"
	end
	if B.action == "PencilDash" then
		local count = B.model:GetAttribute("ActN") or 1
		local start, travel = dashTimes(B, count)
		if start and now > start + travel + 0.05 then
			return "HIT HIM!"
		end
	end
	return nil
end

local function stepHint(B, showIt)
	local now = serverNow()
	local want = showIt and openNow(B, now) or nil
	if want == B.hintText then
		if B.hintLabel then
			B.hintLabel.TextTransparency = (math.floor(now * 6) % 2 == 0) and 0 or 0.25
			if B.hintAnchor and B.bodyTop then
				B.hintAnchor.CFrame = CFrame.new(B.bodyTop + V3(0, 4, 0))
			end
		end
		return
	end
	B.hintText = want
	if B.hintGui then
		B.hintGui:Destroy()
		B.hintGui, B.hintLabel = nil, nil
	end
	if want then
		B.hintAnchor = B.hintAnchor or newPart("HintSpot", nil, WHITE, Enum.Material.SmoothPlastic, 1, B.body.folder)
		B.hintAnchor.Size = V3(0.2, 0.2, 0.2)
		B.hintAnchor.CFrame = CFrame.new((B.bodyTop or (B.vpos + V3(0, B.def.Height, 0))) + V3(0, 4, 0))
		local bb = Instance.new("BillboardGui")
		bb.Name = "ScribbleHint"
		bb.Size = UDim2.new(0, 300, 0, 30)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = B.hintAnchor
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.TextScaled = true
		label.Font = Enum.Font.Arcade
		if PIXEL_FONT then
			label.FontFace = PIXEL_FONT
		end
		label.TextColor3 = YELLOW
		label.TextStrokeTransparency = 0
		label.Text = want
		label.Parent = bb
		bb.Parent = B.body.folder
		B.hintGui, B.hintLabel = bb, label
	end
end

----------------------------------------------------------------------
-- What BossClient asks of it (see the top of this file)
----------------------------------------------------------------------
-- what his moves are made of: ink
function Body.fx(def)
	return { color = def.Color, deep = def.InkDeep, rock = INK, material = Enum.Material.SmoothPlastic, solid = true }
end

-- joined while he'd already broken out of the paper (or glitched)
function Body.lateBreak(B)
	B.phase2Look = true
	if (B.model:GetAttribute("Phase") or 1) >= 3 then
		B.round3Look = true
	end
end

-- a fresh start (a reset, a new fight): blue ink again
function Body.calm(B, name)
	local _ = name
	B.phase2Look = false
	B.round3Look = false
end

function Body.onTrack(B)
	if (B.model:GetAttribute("Phase") or 1) >= 3 then
		B.round3Look = true
	end
end

-- your boss bar: while he's using it as a whip, it's gone from your screen
function Body.barLook(B, now, share)
	local _ = share
	if B.action == "BarWhip" and B.actionStart then
		local a = B.def.Attacks.BarWhip
		local turns = math.abs(B.model:GetAttribute("ActN") or 1)
		local t = now - B.actionStart
		if t >= a.Tell * 0.25 and t < a.Tell + turns * a.Spin + 0.3 then
			return { hidden = true }
		end
	end
	return nil
end

-- you can't walk through him, or through a standing error window
function Body.pushOut(B, P, here, awake, state)
	local _ = state
	if not (here and awake) then
		return
	end
	local lp = Players.LocalPlayer
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local pos = hrp.Position
	local offset = flat(pos - B.vpos)
	local minimum = B.def.Size / 2 + 1.2
	if offset.Magnitude < minimum and (P.lift or 0) < 4 and B.action ~= "PencilDash" then
		local outDir = offset.Magnitude > 0.05 and offset.Unit or B.vfacing
		local target = B.vpos + outDir * minimum
		pos = V3(target.X, pos.Y, target.Z)
	end
	local now = serverNow()
	for _, w in ipairs(B.windows or {}) do
		if now >= w.from and now < w.till then
			local d = flat(pos - w.c)
			local across = V3(-w.ax.Z, 0, w.ax.X)
			local along, side = d:Dot(w.ax), d:Dot(across)
			local hw, hd = w.half + 1, w.depth + 1.2
			if math.abs(along) < hw and math.abs(side) < hd then
				-- out the nearest way
				if hw - math.abs(along) < hd - math.abs(side) then
					along = (along >= 0 and 1 or -1) * hw
				else
					side = (side >= 0 and 1 or -1) * hd
				end
				local target = w.c + w.ax * along + across * side
				pos = V3(target.X, pos.Y, target.Z)
			end
		end
	end
	if (pos - hrp.Position).Magnitude > 1e-3 then
		hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.Position)
	end
end

-- every frame, whatever he's doing: his props, the erased edge, the hint
function Body.senses(B, dt, here, awake, state)
	local _ = dt
	local _ = state
	B.here = here
	local now = serverNow()
	if (B.model:GetAttribute("Phase") or 1) >= 3 and state ~= "Transition" and state ~= "Dormant" then
		B.round3Look = true
	end
	local function run(name, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			B.warned = B.warned or {}
			if not B.warned[name] then
				B.warned[name] = true
				warn("[BossClient] Scribble's " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	run("props", stepProps, B, now)
	run("erased edge", stepEdge, B, now)
	run("hint", stepHint, B, here and awake)
end

return Body
