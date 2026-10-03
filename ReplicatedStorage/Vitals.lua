--[[
	Vitals  (ModuleScript, parent: ReplicatedStorage, name: "Vitals")

	The three pixel-art pieces in the middle of the bottom of your screen:

	        x3 [potion]     [ HEART ]     [ BOLT ]
	          your flasks    your health   your stamina

	  * THE HEART - your health, as red liquid inside a pixel heart (always
	    on screen). Take a hit and it sloshes, drops spill out over the rim
	    and the heart shakes; heal and it pours back in; low on health it
	    beats and blinks red; and when it runs dry the heart cracks in two and
	    shatters (like the SOUL in Undertale) - and forms again when you're
	    back. The level is measured by how much of the heart is full, not how
	    high: half your health really is half the heart.
	  * THE BOLT - your stamina (in a fight), as yellow electric liquid inside
	    a pixel lightning bolt. Punching, rolling and jumping drain it, and it
	    fills back up from the bottom when you stop. Full, it crackles with
	    little sparks; try to do something with too little left and it
	    flickers like a dying light and its outline flashes red; while a roll
	    makes you untouchable it glows pale blue (the same blue you glow).
	  * THE POTION - your healing flasks (in a fight): a little bottle of the
	    heart's own red, with how many you have left beside it (x3). Drink one
	    and the cork pops off, the bottle tips over towards the heart and
	    pours into it in an arc of red drops - the heart fills up as they land
	    - and the count ticks down. None left: empty grey glass and x0, and it
	    shakes if you try.

	Two scripts use it: Hud starts it (Vitals.start) and CombatClient tells it
	how the fight is going (Vitals.set and Vitals.fire). It's one module on
	purpose, so the three always sit together and can play off each other
	(the potion pours into the heart).

	Tuning: Config.Heart (the heart and the size of every pixel) and
	Config.Vitals (the bolt and the potion).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local RGB = Color3.fromRGB

local Vitals = {}

----------------------------------------------------------------------
-- The pictures: "O" is the outline, "." the inside (where the liquid
-- goes) and "c" the potion's cork
----------------------------------------------------------------------
Vitals.HEART = {
	"  OOOO   OOOO  ",
	" O....O O....O ",
	"O......O......O",
	"O.............O",
	"O.............O",
	"O.............O",
	" O...........O ",
	"  O.........O  ",
	"   O.......O   ",
	"    O.....O    ",
	"     O...O     ",
	"      O.O      ",
	"       O       ",
}
Vitals.BOLT = {
	"    OOOOOO",
	"   O.....O",
	"   O....O ",
	"  O....O  ",
	"  O...OOOO",
	" O.......O",
	" O......O ",
	" OOO...O  ",
	"   O..O   ",
	"  O..O    ",
	"  O.O     ",
	" O.O      ",
	" OO       ",
}
Vitals.POTION = {
	"  OOO  ",
	"  OcO  ",
	" OOOOO ",
	"  O.O  ",
	" O...O ",
	"O.....O",
	"O.....O",
	"O.....O",
	" O...O ",
	"  OOO  ",
}

-- The colours (all from the game's pixel palette)
local OUTLINE = RGB(24, 20, 37)
local GLASS = RGB(38, 43, 68)
local WHITE = RGB(255, 255, 255)
local HURT = RGB(255, 0, 68)
-- the heart's (and the potion's) red
local LIQUID = RGB(228, 59, 68)
local SURFACE = RGB(246, 117, 122)
local DEEP = RGB(162, 38, 51)
local BUBBLE = RGB(255, 190, 190)
-- the bolt's electric yellow...
local VOLT = RGB(254, 231, 97)
local VOLT_DEEP = RGB(254, 174, 52)
-- ...and its pale blue while you're untouchable
local ICE = RGB(44, 232, 245)
local ICE_DEEP = RGB(0, 153, 219)
-- the potion's cork, and its grey when there are none left
local CORK = RGB(184, 111, 80)
local EMPTY_EDGE = RGB(90, 105, 136)
local DIM_TEXT = RGB(139, 155, 180)

----------------------------------------------------------------------
-- The sums (no screen needed - the headless tests check these)
----------------------------------------------------------------------
-- Every square of a picture: the outline, the squares that hold liquid and
-- how high each of those sits above the lowest one ("layer" 0 = the bottom).
function Vitals.layout(shape)
	local rows, cols = #shape, 0
	for _, row in ipairs(shape) do
		cols = math.max(cols, #row)
	end
	local bottom = 0
	for y = 1, rows do
		if string.find(shape[y], ".", 1, true) then
			bottom = y
		end
	end
	local out = { rows = rows, cols = cols, bottom = bottom, inside = {}, outline = {}, extra = {}, perLayer = {}, layers = 0 }
	for y = 1, rows do
		for x = 1, cols do
			local ch = string.sub(shape[y], x, x)
			if ch == "." then
				local c = { x = x, y = y, layer = bottom - y }
				table.insert(out.inside, c)
				out.perLayer[c.layer] = (out.perLayer[c.layer] or 0) + 1
				out.layers = math.max(out.layers, c.layer + 1)
			elseif ch == "O" then
				table.insert(out.outline, { x = x, y = y })
			elseif ch ~= " " and ch ~= "" then
				table.insert(out.extra, { x = x, y = y, ch = ch })
			end
		end
	end
	return out
end

-- How high the liquid stands (in layers) when `f` of a picture is full. It
-- goes by how many squares are full, not by height: half full really is
-- half the squares, even in a bolt that's thin at the bottom.
function Vitals.heightFor(lay, f)
	local want = math.clamp(f, 0, 1) * #lay.inside
	for L = 0, lay.layers - 1 do
		local n = lay.perLayer[L] or 0
		if want <= n then
			return L + (n > 0 and want / n or 0)
		end
		want = want - n
	end
	return lay.layers
end

----------------------------------------------------------------------
-- What CombatClient tells us about the fight
----------------------------------------------------------------------
local fight = {
	shown = false, -- in a fight: the bolt and the potion are on screen
	stamina = 1, -- how full your stamina is (0 to 1)
	flasks = 0, -- flasks left
}
local moments = {} -- things that just happened, drawn on the next frame

-- How the fight is going right now, e.g. Vitals.set({ stamina = 0.5 })
function Vitals.set(values)
	for k, v in pairs(values) do
		if k == "stamina" then
			v = tonumber(v) or 1
			fight.stamina = (v == v) and math.clamp(v, 0, 1) or 1 -- (never a broken number)
		elseif k == "flasks" then
			fight.flasks = math.max(0, math.floor(tonumber(v) or 0))
		elseif k == "shown" then
			fight.shown = v == true
		end
	end
end

-- Something just happened:
--   "drink" (seconds)    you started drinking a flask - the potion pours
--   "iframes" (seconds)  a roll made you untouchable - the bolt glows blue
--   "empty"              too little stamina for what you tried - it flickers
--   "noFlask"            you tried to drink with none left - the potion shakes
function Vitals.fire(kind, value)
	if #moments < 16 then
		table.insert(moments, { kind = kind, value = value })
	end
end

----------------------------------------------------------------------
-- Building it (Hud calls this once)
----------------------------------------------------------------------
local function create(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

-- (its own look: the retro restyler leaves every piece of it alone)
local function own(inst)
	inst:SetAttribute("RetroSkip", true)
	return inst
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0 to 1, overshooting a little on the way: a bouncy pop
local function popOut(t)
	t = math.clamp(t, 0, 1) - 1
	return 1 + 2.2 * t * t * t + 1.2 * t * t
end

-- opts: root (the Frame to draw in), text and stroke (Hud's helpers, so the
-- numbers match its look) and character (returns your Humanoid, or nil).
-- Gives back { hpText, powerText } (Hud writes your Power into powerText).
function Vitals.start(opts)
	local root = opts.root
	local text, stroke = opts.text, opts.stroke
	local character = opts.character
	local H = Config.Heart or {}
	local V = Config.Vitals or {}
	local CC = Config.Combat or {}
	local PX = H.Pixel or 5 -- screen pixels per pixel of the pictures
	local GAP = V.Gap or 2 * PX -- space between the heart and the bolt / potion
	local BASE_Y = -66 -- where the bottom of the heart sits (above the level bar)

	-- All of it hangs in here: the same size as `root`, and on a small screen
	-- (a phone, where the whole screen is drawn small) a bit bigger than the
	-- rest, so your health is still easy to read - never smaller than on a
	-- screen Heart.MinScreen pixels tall, up to Heart.MaxBoost times bigger.
	-- It grows from the middle of the bottom, so everything stays in place.
	local holder = own(create("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	}))
	local boost = create("UIScale", { Name = "SmallScreen", Scale = 1, Parent = holder })
	local function fitHolder()
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize and cam.ViewportSize.Y or 0
		if vh > 0 then
			local hud = math.clamp(vh / 1000, 0.5, 1.1) -- (how big Hud draws the screen)
			boost.Scale = math.clamp(math.min(H.MinScreen or 700, 1000) / 1000 / hud, 1, H.MaxBoost or 1.5)
		end
	end
	fitHolder()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHolder)
	end
	root = holder

	local function pixel(parent, x, y, color, z)
		return own(create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Position = UDim2.fromOffset((x - 1) * PX, (y - 1) * PX),
			Size = UDim2.fromOffset(PX, PX),
			ZIndex = z,
			Parent = parent,
		}))
	end

	------------------------------------------------------------------
	-- THE HEART
	------------------------------------------------------------------
	local HL = Vitals.layout(Vitals.HEART)
	local ROWS, COLS = HL.rows, HL.cols
	local MID = (COLS + 1) / 2
	local HW, HH = COLS * PX, ROWS * PX
	local LOW = H.Low or 0.25 -- below this much health it beats and blinks

	local vessel = own(create("Frame", {
		Name = "HeartVessel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, BASE_Y),
		Size = UDim2.fromOffset(HW, HH),
		BackgroundTransparency = 1,
		Parent = root,
	}))
	local beat = create("UIScale", { Scale = 1, Parent = vessel })
	-- two halves (split down a zigzag through the middle), for when it breaks
	local halves = {}
	for i = 1, 2 do
		halves[i] = own(create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = vessel }))
	end
	local function halfFor(x, y)
		return (x < MID or (x == MID and y % 2 == 1)) and halves[1] or halves[2]
	end
	local cells, outline, byCol = {}, {}, {}
	for _, o in ipairs(HL.outline) do
		table.insert(outline, pixel(halfFor(o.x, o.y), o.x, o.y, OUTLINE, 3))
	end
	for _, s in ipairs(HL.inside) do
		local c = { f = pixel(halfFor(s.x, s.y), s.x, s.y, GLASS, 2), x = s.x, layer = s.layer, color = GLASS }
		c.f.BackgroundTransparency = 0.15
		table.insert(cells, c)
		byCol[s.x] = byCol[s.x] or {}
		byCol[s.x][s.layer] = c
	end
	local LAYERS, bottomRow = HL.layers, HL.bottom
	-- the shine on the glass
	for _, g in ipairs({ { 3, 3 }, { 4, 3 }, { 3, 4 } }) do
		pixel(halves[1], g[2], g[1], WHITE, 4).BackgroundTransparency = 0.45
	end

	-- the HP numbers on its left, your Power on its right (they step aside
	-- for the potion and the bolt in a fight - see placeAll below)
	local hpText = text({
		Name = "HeartHP",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(170, 30),
		RichText = true,
		Text = "",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, { stroke(3) })
	local powerText = text({
		Name = "HeartPower",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(220, 30),
		Text = "Power: 0",
		TextSize = 22,
		TextColor3 = RGB(110, 190, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, { stroke(3) })

	-- drops (spilled, poured in), shards (when it breaks) and sparks (off the
	-- bolt): little squares flying about. A drop with `into` set falls into
	-- the heart: it vanishes as it reaches the liquid and makes it slosh.
	local drops = {}
	local function drop(x, y, vx, vy, color, size, life, into, parent, gravity)
		local f = own(create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(x, y),
			ZIndex = 5,
			Parent = parent or vessel,
		}))
		local d = { f = f, x = x, y = y, vx = vx, vy = vy, age = 0, life = life, into = into, g = gravity or 520 }
		table.insert(drops, d)
		return d
	end
	local surfaceY -- (set every frame: where the top of the liquid is, in pixels)
	local counts = { landed = 0, pours = 0, sparks = 0, corks = 0 } -- (for the headless tests)

	local shown, target = 1, 1 -- how full it's drawn / how full it should be
	local amp, clock, shake, flash = 0, 0, 0, 0
	local broken = nil -- seconds since it broke (nil: whole)
	local bubble = nil
	local nextBubble = 1
	local lastHum, lastText = nil, nil
	local outlineColor = OUTLINE

	local function spill(loss)
		local n = math.clamp(math.floor(loss * (H.Drops or 36) + 0.5), 3, H.MaxDrops or 12)
		for _ = 1, n do
			local x = (MID - 4 + math.random() * 8) * PX
			local side = math.random() < 0.5 and -1 or 1
			drop(x, surfaceY or PX * 3, side * (40 + math.random() * 70), -(90 + math.random() * 90),
				math.random() < 0.3 and SURFACE or LIQUID, PX * (0.6 + math.random() * 0.5), 0.9 + math.random() * 0.3)
		end
	end
	local function pour(gain)
		counts.pours = counts.pours + 1
		local n = math.clamp(math.floor(gain * 20 + 0.5), 3, 8)
		for i = 1, n do
			drop((MID - 0.5 + (math.random() - 0.5) * 1.2) * PX, -PX * (2 + i * 1.6), 0, 60, LIQUID, PX * 0.7, 2, true)
		end
	end
	local function shatter()
		broken = 0
		flash = 0.12
	end
	local function mend()
		broken = nil
		for _, h in ipairs(halves) do
			h.Visible = true
			h.Position = UDim2.fromOffset(0, 0)
		end
		shown = 0 -- (and it fills back up, poured in)
		pour(1)
	end

	------------------------------------------------------------------
	-- THE BOLT (your stamina)
	------------------------------------------------------------------
	local BL = Vitals.layout(Vitals.BOLT)
	local BW, BH = BL.cols * PX, BL.rows * PX
	local bolt = own(create("Frame", {
		Name = "StaminaBolt",
		AnchorPoint = Vector2.new(0.5, 1), -- (it pops up out of the bottom)
		Size = UDim2.fromOffset(BW, BH),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}))
	local boltScale = create("UIScale", { Scale = 0, Parent = bolt })
	local boltCells, boltOutline, boltByCol = {}, {}, {}
	for _, o in ipairs(BL.outline) do
		table.insert(boltOutline, pixel(bolt, o.x, o.y, OUTLINE, 3))
	end
	for _, s in ipairs(BL.inside) do
		local c = { f = pixel(bolt, s.x, s.y, GLASS, 2), x = s.x, layer = s.layer, color = GLASS }
		c.f.BackgroundTransparency = 0.15
		table.insert(boltCells, c)
		boltByCol[s.x] = boltByCol[s.x] or {}
		boltByCol[s.x][s.layer] = c
	end
	for _, g in ipairs({ { 6, 2 }, { 5, 3 } }) do
		pixel(bolt, g[1], g[2], WHITE, 4).BackgroundTransparency = 0.45
	end
	-- the outline squares a spark can fly off (the top two thirds of it)
	local sparkFrom = {}
	for _, o in ipairs(BL.outline) do
		if o.y <= 9 then
			table.insert(sparkFrom, o)
		end
	end

	local boltLevel = 1 -- how full it's drawn
	local boltAmp = 0 -- how much the liquid wobbles
	local lastStamina = 1
	local blueFor, blueTotal = 0, 1 -- the pale blue glow while you're untouchable
	local flicker = 0 -- seconds left of the dying-light flicker
	local boltFlash = 0 -- the outline's white flash (just filled right up)
	local boltShake = 0
	local wasFull = true
	local nextSpark = 0
	local zap = nil -- a white spark climbing up through the liquid
	local nextZap = 0.6
	local boltEdge = OUTLINE

	-- a spark off the bolt, flying out from square `o` of its outline
	local function spark(o, speed)
		local cx, cy = (o.x - 0.5) * PX, (o.y - 0.5) * PX
		local dx, dy = cx - BW * 0.5, cy - BH * 0.45
		local len = math.max(math.sqrt(dx * dx + dy * dy), 1)
		local s = speed * (0.7 + math.random() * 0.6)
		counts.sparks = counts.sparks + 1
		drop(cx, cy, dx / len * s, dy / len * s, math.random() < 0.5 and WHITE or VOLT,
			PX * (0.4 + math.random() * 0.35), 0.22 + math.random() * 0.2, false, bolt, 0)
	end

	------------------------------------------------------------------
	-- THE POTION (your flasks)
	------------------------------------------------------------------
	local PL = Vitals.layout(Vitals.POTION)
	local PW, PH = PL.cols * PX, PL.rows * PX
	local potion = own(create("Frame", {
		Name = "FlaskPotion",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(PW, PH),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}))
	local potionScale = create("UIScale", { Scale = 0, Parent = potion })
	local potCells, potOutline, potByCol, corkBits = {}, {}, {}, {}
	for _, o in ipairs(PL.outline) do
		local f = pixel(potion, o.x, o.y, OUTLINE, 3)
		table.insert(potOutline, f)
		if o.y <= 2 then
			table.insert(corkBits, f) -- (the cork's own outline pops off with it)
		end
	end
	for _, e in ipairs(PL.extra) do
		if e.ch == "c" then
			table.insert(corkBits, pixel(potion, e.x, e.y, CORK, 3))
		end
	end
	for _, s in ipairs(PL.inside) do
		local c = { f = pixel(potion, s.x, s.y, GLASS, 2), x = s.x, layer = s.layer, color = GLASS }
		c.f.BackgroundTransparency = 0.15
		table.insert(potCells, c)
		potByCol[s.x] = potByCol[s.x] or {}
		potByCol[s.x][s.layer] = c
	end
	for _, g in ipairs({ { 2, 6 }, { 3, 5 } }) do
		pixel(potion, g[1], g[2], WHITE, 4).BackgroundTransparency = 0.45
	end
	local countText = text({
		Name = "FlaskCount",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(48, 30),
		Text = "x0",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	}, { stroke(3) })
	local countPop = create("UIScale", { Scale = 1, Parent = countText })

	local TIP = V.Tip or 60 -- degrees it tips over to pour
	local TIP_TIME = 0.16
	local BACK_TIME = 0.22
	local pot = {
		level = 1, -- how full the bottle is drawn
		phase = "idle", -- "idle", "tip" (tipping over), "pour", "back" (standing up again)
		t = 0,
		pouring = false, -- (the heart skips its own pour while this pours into it)
		healed = false, -- the heal has arrived
		drink = CC.FlaskDrinkTime or 0.9,
		tilt = 0,
		liftX = 0,
		liftY = 0,
		corked = true,
		shake = 0, -- seconds left of the "none left" wiggle
		red = 0, -- the count flashing red
		pop = 0, -- the refill bounce
		count = nil, -- the number on screen
		emptyIn = nil, -- (a count dropping to 0 waits a moment, in case a drink is starting)
		nextDrop = 0,
		edge = OUTLINE,
		words = nil, -- the count's colour
	}
	local function setCorked(on)
		if pot.corked ~= on then
			pot.corked = on
			for _, f in ipairs(corkBits) do
				f.Visible = on
			end
		end
	end
	-- where the bottle's mouth is right now (in the heart's pixels: the drops
	-- live in the heart's frame, so they can fall into it)
	local function mouth()
		local cx = -(GAP + PW / 2) + pot.liftX
		local cy = HH - PH / 2 + pot.liftY
		local r = PH / 2 - 2 * PX
		local a = math.rad(pot.tilt)
		return cx + r * math.sin(a), cy - r * math.cos(a)
	end

	------------------------------------------------------------------
	-- Where everything sits: the heart in the middle, the potion and the
	-- bolt either side of it in a fight, the words stepping aside for them
	------------------------------------------------------------------
	local appear = 0 -- 0: just the heart (the lobby) ... 1: all three (a fight)
	local placed = nil
	local COUNT_W = 48
	local function placeAll()
		local a = smooth(appear)
		-- (on a touch screen the fight buttons crowd the bottom right: in a
		-- fight your Power steps off the screen - the level bar still shows it)
		local UIS = game:GetService("UserInputService")
		local crowded = a > 0.5 and UIS ~= nil and UIS.TouchEnabled == true and not UIS.KeyboardEnabled
		local key = string.format("%.3f|%.1f|%.1f|%.1f|%s", a, pot.liftX, pot.liftY, boltShake, tostring(crowded))
		if key == placed then
			return
		end
		placed = key
		powerText.Visible = not crowded
		local mid = BASE_Y - HH / 2
		local potX = -(HW / 2 + GAP + PW / 2)
		local countRight = -(HW / 2 + GAP + PW + 4)
		hpText.Position = UDim2.new(0.5, math.floor(-(HW / 2 + 10) + a * (countRight - COUNT_W - 8 + HW / 2 + 10)), 1, mid)
		powerText.Position = UDim2.new(0.5, math.floor(HW / 2 + 10 + a * (GAP + BW)), 1, mid)
		potion.Position = UDim2.new(0.5, math.floor(potX + pot.liftX), 1, math.floor(BASE_Y + pot.liftY))
		countText.Position = UDim2.new(0.5, math.floor(countRight), 1, math.floor(BASE_Y - PH * 0.4))
		local sx = boltShake > 0 and (math.random() - 0.5) * 6 * boltShake or 0
		bolt.Position = UDim2.new(0.5, math.floor(HW / 2 + GAP + BW / 2 + sx), 1, BASE_Y)
	end
	placeAll()

	-- the liquid in one of the pictures, square by square: `h` layers deep,
	-- wobbling by `wave(c)`; `colorOf(c, filled, above)` picks each square's
	-- colour. Only squares whose colour changes are touched.
	local function paint(list, colByCol, h, wave, colorOf)
		local filled = {}
		for _, c in ipairs(list) do
			filled[c] = h > 0.02 and c.layer + 0.5 < h + wave(c)
		end
		for _, c in ipairs(list) do
			local above = colByCol[c.x][c.layer + 1]
			local color, see = colorOf(c, filled[c], not above or not filled[above])
			if color ~= c.color or see ~= c.see then
				c.color, c.see = color, see
				c.f.BackgroundColor3 = color
				c.f.BackgroundTransparency = see
			end
		end
		return filled
	end

	------------------------------------------------------------------
	-- Every frame
	------------------------------------------------------------------
	local function stepHeart(dt)
		local hum = character()
		if hum and hum.MaxHealth > 0 then
			local f = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
			local words = '<font color="#FEE761">HP</font> ' .. math.ceil(math.max(hum.Health, 0)) .. "/" .. math.floor(hum.MaxHealth)
			if words ~= lastText then
				lastText = words
				hpText.Text = words
			end
			if hum ~= lastHum then
				-- a new you (respawned): no spilling over the change
				lastHum = hum
				target = f
				if broken and f > 0 then
					mend()
				end
			elseif f < target - 0.001 then
				-- a hit: it sloshes, spills, shakes and flashes
				local loss = target - f
				target = f
				amp = math.min(H.Slosh or 1.6, amp + 0.5 + loss * 4)
				shake, flash = 1, 0.09
				spill(loss)
				if f <= 0 and not broken then
					shatter()
				end
			elseif f > target + 0.001 then
				local gain = f - target
				target = f
				if pot.pouring then
					pot.healed = true -- (the potion's own drops are the pour)
				elseif gain > 0.03 then
					pour(gain)
				end
				if broken and f > 0 then
					mend()
				end
			end
		end

		-- the level catches up: drains fast, fills slower
		if shown > target then
			shown = math.max(target, shown - dt * (H.Drain or 1.2))
		elseif shown < target then
			shown = math.min(target, shown + dt * (H.Fill or 0.5))
		end
		amp = amp * math.exp(-2.5 * dt)
		local h = Vitals.heightFor(HL, shown)
		surfaceY = (bottomRow + 1 - h) * PX

		-- the liquid, square by square
		local calm = math.min(1, h * 2, (LAYERS - h) * 1.5)
		local tilt = amp * 0.6 * math.sin(clock * 6)
		local filled = {}
		for _, c in ipairs(cells) do
			local wave = amp * math.sin(c.x * 0.8 + clock * 9) + tilt * (c.x - MID) / MID + 0.12 * math.sin(c.x * 0.7 + clock * 3)
			filled[c] = h > 0.02 and c.layer + 0.5 < h + wave * calm
		end
		-- a bubble now and then, rising through it
		if not bubble and clock > nextBubble and h > 2 then
			bubble = { x = math.random(MID - 3, MID + 3), layer = 0, t = 0 }
		end
		if bubble then
			bubble.t = bubble.t + dt
			if bubble.t > 0.12 then
				bubble.t = 0
				bubble.layer = bubble.layer + 1
			end
			local c = byCol[bubble.x] and byCol[bubble.x][bubble.layer]
			if not c or not filled[c] then
				bubble = nil
				nextBubble = clock + 0.8 + math.random() * 1.6
			end
		end
		for _, c in ipairs(cells) do
			local color = GLASS
			if filled[c] then
				local above = byCol[c.x][c.layer + 1]
				if not above or not filled[above] then
					color = SURFACE
				elseif c.layer <= 1 then
					color = DEEP
				else
					color = LIQUID
				end
				if bubble and bubble.x == c.x and bubble.layer == c.layer then
					color = BUBBLE
				end
			end
			if color ~= c.color then
				c.color = color
				c.f.BackgroundColor3 = color
				c.f.BackgroundTransparency = (color == GLASS) and 0.15 or 0
			end
		end

		-- the outline: a white flash when hit; beating and blinking red when low
		flash = math.max(0, flash - dt)
		local low = target > 0 and target < LOW and not broken
		local pulse = low and math.max(0, math.sin(clock * (target < LOW / 2 and 11 or 7))) ^ 6 or 0
		local want = flash > 0 and WHITE or (pulse > 0.3 and HURT or OUTLINE)
		if want ~= outlineColor then
			outlineColor = want
			for _, o in ipairs(outline) do
				o.BackgroundColor3 = want
			end
		end
		beat.Scale = 1 + 0.1 * pulse
		shake = math.max(0, shake - dt * 3.5)
		local sx, sy = (math.random() - 0.5) * 8 * shake, (math.random() - 0.5) * 8 * shake
		vessel.Position = UDim2.new(0.5, math.floor(sx), 1, BASE_Y + math.floor(sy))

		-- breaking: the halves part along the crack... then it shatters
		if broken then
			broken = broken + dt
			if broken < 0.6 then
				local gap = math.min(broken * 12, 3)
				halves[1].Position = UDim2.fromOffset(-gap, 0)
				halves[2].Position = UDim2.fromOffset(gap, 0)
			elseif halves[1].Visible then
				halves[1].Visible, halves[2].Visible = false, false
				for i = 1, 10 do
					local a = (i / 10) * math.pi * 2
					drop(MID * PX, ROWS * PX * 0.45, math.cos(a) * (60 + math.random() * 60), -60 - math.random() * 80,
						(i % 3 == 0) and OUTLINE or LIQUID, PX * 1.3, 1.2)
				end
			end
		end
	end

	local function stepBolt(dt)
		local want = fight.stamina
		if want < lastStamina - 0.01 then
			boltAmp = math.min(1, boltAmp + 0.35) -- spending it jolts the liquid
		end
		lastStamina = want
		-- it follows your stamina closely (you're counting on it mid-fight)
		boltLevel = boltLevel + (want - boltLevel) * (1 - math.exp(-(V.Follow or 16) * dt))
		if math.abs(want - boltLevel) < 0.002 then
			boltLevel = want
		end
		boltAmp = boltAmp * math.exp(-4 * dt)
		blueFor = math.max(0, blueFor - dt)
		flicker = math.max(0, flicker - dt)
		boltFlash = math.max(0, boltFlash - dt)
		boltShake = math.max(0, boltShake - dt * 3)

		-- full: a burst of sparks as it fills up, then a crackle now and then
		local full = boltLevel >= 0.999
		if full and not wasFull then
			boltFlash = 0.1
			for _ = 1, 6 do
				spark(sparkFrom[math.random(1, #sparkFrom)], 110)
			end
			nextSpark = clock + 0.4
		end
		wasFull = full
		if full and V.Sparks ~= false and clock >= nextSpark then
			for _ = 1, math.random(1, 2) do
				spark(sparkFrom[math.random(1, #sparkFrom)], 70)
			end
			nextSpark = clock + 0.35 + math.random() * 0.55
		end

		local h = Vitals.heightFor(BL, boltLevel)
		-- a white zap climbing up through it now and then
		if not zap and clock > nextZap and h > 2 then
			local c = boltCells[math.random(1, #boltCells)]
			zap = { x = c.x, layer = 0, t = 0 }
		end
		if zap then
			zap.t = zap.t + dt
			if zap.t > 0.05 then
				zap.t = 0
				zap.layer = zap.layer + 1
			end
			if zap.layer + 0.5 >= h or not boltByCol[zap.x] then
				zap = nil
				nextZap = clock + 0.5 + math.random() * 0.9
			end
		end

		-- the colours: electric yellow, turning pale blue while you're untouchable
		local blue = blueFor > 0 and blueFor / blueTotal or 0
		local body, deep = VOLT, VOLT_DEEP
		if blue > 0 then
			body, deep = VOLT:Lerp(ICE, blue), VOLT_DEEP:Lerp(ICE_DEEP, blue)
		end
		-- the dying light: the liquid blinks off and on
		local lightOn = flicker <= 0 or math.floor(flicker * 22) % 3 == 0
		local calm = math.min(1, h * 2, (BL.layers - h) * 1.5)
		paint(boltCells, boltByCol, h, function(c)
			return (boltAmp * 0.7 * math.sin(c.x * 1.3 + clock * 14) + 0.08 * math.sin(c.x + clock * 5)) * calm
		end, function(c, filled, top)
			if not filled or not lightOn then
				return GLASS, 0.15
			end
			if zap and zap.x == c.x and zap.layer == c.layer then
				return WHITE, 0
			end
			if top then
				-- the surface crackles: white and yellow crawling along it
				return (math.floor(clock * 14 + c.x * 2.3) % 3 == 0) and body or WHITE, 0
			end
			return c.layer <= 1 and deep or body, 0
		end)

		local edge = flicker > 0 and HURT or (boltFlash > 0 and WHITE or OUTLINE)
		if edge ~= boltEdge then
			boltEdge = edge
			for _, o in ipairs(boltOutline) do
				o.BackgroundColor3 = edge
			end
		end
	end

	-- `settle`: nothing happening - the bottle simply shows what's left
	local function settlePotion(dt)
		local left = fight.flasks
		if pot.count ~= left then
			if pot.count and left > pot.count then
				pot.pop = 1 -- more flasks (a fresh run): the bottle bounces full again
				pot.level = 1
				pot.emptyIn = nil
				setCorked(true)
			elseif left == 0 and pot.level > 0 and not pot.emptyIn then
				pot.emptyIn = 0.35
			end
			pot.count = left
			countText.Text = "x" .. left
			countPop.Scale = 1.3
		end
		if pot.emptyIn then
			pot.emptyIn = pot.emptyIn - dt
			if pot.emptyIn <= 0 then
				pot.emptyIn = nil
				if fight.flasks == 0 then
					pot.level = 0
					setCorked(false)
				end
			end
		end
	end

	local function stepPotion(dt)
		pot.shake = math.max(0, pot.shake - dt)
		pot.red = math.max(0, pot.red - dt)
		pot.pop = math.max(0, pot.pop - dt * 3)
		countPop.Scale = 1 + (countPop.Scale - 1) * math.exp(-10 * dt)
		if math.abs(countPop.Scale - 1) < 0.01 then
			countPop.Scale = 1
		end
		if pot.phase == "idle" then
			settlePotion(dt)
		else
			pot.t = pot.t + dt
			local healedAndFull = pot.healed and shown >= target - 0.005
			if pot.phase == "tip" then
				local k = smooth(pot.t / TIP_TIME)
				pot.tilt, pot.liftX, pot.liftY = TIP * k, 6 * k, -12 * k
				if pot.t >= TIP_TIME then
					pot.phase, pot.t = "pour", 0
				end
			elseif pot.phase == "pour" then
				-- it empties over about as long as the heart takes to fill
				-- (the drink, then the heart rising)... or quickly, once the
				-- heart has what it's getting (or nothing's coming)
				local base = math.max(0.4, pot.drink + (CC.FlaskHeal or 0.45) / (H.Fill or 0.5) - TIP_TIME)
				local hurry = healedAndFull or (not pot.healed and pot.t > pot.drink + 0.35)
				pot.level = math.max(0, pot.level - dt * (hurry and 4 or 1 / base))
				-- the stream: drops arcing from the mouth into the heart
				pot.nextDrop = pot.nextDrop - dt
				while pot.nextDrop <= 0 and pot.level > 0 do
					pot.nextDrop = pot.nextDrop + 0.035
					local x0, y0 = mouth()
					local x1 = (4 + math.random() * 1.5) * PX -- the left side of the heart
					local y1 = math.max(surfaceY or PX, PX * 1.5)
					local T = 0.42
					local d = drop(x0, y0, (x1 - x0) / T, (y1 - y0 - 0.5 * 520 * T * T) / T,
						math.random() < 0.3 and SURFACE or LIQUID, PX * 0.7, 1.5, true)
					d.splash = 0.05
				end
				if pot.level <= 0 then
					pot.phase, pot.t = "back", 0
					pot.pouring = false
				end
			elseif pot.phase == "back" then
				local k = 1 - smooth(pot.t / BACK_TIME)
				pot.tilt, pot.liftX, pot.liftY = TIP * k, 6 * k, -12 * k
				if pot.t >= BACK_TIME then
					pot.phase, pot.t = "idle", 0
					pot.tilt, pot.liftX, pot.liftY = 0, 0, 0
					if fight.flasks > 0 then
						pot.level = 1 -- the next one, full and corked
						pot.pop = 1
						setCorked(true)
					end
				end
			end
			-- (the count follows along while it pours)
			if pot.count ~= fight.flasks then
				pot.count = fight.flasks
				countText.Text = "x" .. fight.flasks
				countPop.Scale = 1.3
			end
		end

		-- none left: an empty grey bottle (unless it's still pouring the last one)
		local none = fight.flasks == 0 and pot.phase == "idle" and pot.level <= 0
		local edge = none and EMPTY_EDGE or OUTLINE
		if edge ~= pot.edge then
			pot.edge = edge
			for _, f in ipairs(potOutline) do
				f.BackgroundColor3 = edge
			end
		end
		local see = none and 0.45 or 0.15
		local h = Vitals.heightFor(PL, pot.level)
		paint(potCells, potByCol, h, function()
			return 0
		end, function(c, filled, top)
			if not filled then
				return GLASS, see
			end
			if top then
				return SURFACE, 0
			end
			return c.layer <= 1 and DEEP or LIQUID, 0
		end)
		local words = pot.red > 0 and HURT or (fight.flasks == 0 and DIM_TEXT or WHITE)
		if words ~= pot.words then
			pot.words = words
			countText.TextColor3 = words
		end

		-- the tilt (with a wiggle when there's nothing to drink) and the bounce
		local wiggle = pot.shake > 0 and math.sin(pot.shake * 40) * 14 * (pot.shake / 0.45) or 0
		potion.Rotation = pot.tilt + wiggle
		potionScale.Scale = popOut(appear) * (1 + 0.25 * math.sin(pot.pop * math.pi) * pot.pop)
	end

	-- the moments CombatClient told us about since the last frame
	local function takeMoments()
		while #moments > 0 do
			local m = table.remove(moments, 1)
			if m.kind == "drink" then
				if pot.phase == "idle" and appear > 0 then
					pot.phase, pot.t = "tip", 0
					pot.pouring, pot.healed = true, false
					pot.drink = math.max(0.2, tonumber(m.value) or CC.FlaskDrinkTime or 0.9)
					pot.level, pot.emptyIn, pot.nextDrop = 1, nil, 0.1
					if pot.corked then
						-- pop! the cork flies off
						setCorked(false)
						counts.corks = counts.corks + 1
						local x0, y0 = mouth()
						drop(x0, y0 - PX, -50, -170, CORK, PX * 1.1, 0.8, false)
					end
				end
			elseif m.kind == "iframes" then
				local s = math.max(0.05, tonumber(m.value) or 0.5)
				blueFor, blueTotal = s, s
			elseif m.kind == "empty" then
				if flicker <= 0.1 then
					boltShake = 1
				end
				flicker = 0.45
			elseif m.kind == "noFlask" then
				pot.shake, pot.red = 0.45, 0.45
			end
		end
	end

	-- the fight's pieces coming and going
	local function stepAppear(dt)
		local wantOn = fight.shown
		if wantOn and appear == 0 then
			-- arriving: start from how things are right now
			boltLevel, lastStamina, wasFull = fight.stamina, fight.stamina, fight.stamina >= 0.999
			pot.count, pot.level = nil, fight.flasks > 0 and 1 or 0
			pot.phase, pot.pouring, pot.emptyIn = "idle", false, nil
			pot.tilt, pot.liftX, pot.liftY = 0, 0, 0
			setCorked(fight.flasks > 0)
			bolt.Visible, potion.Visible, countText.Visible = true, true, true
		end
		if wantOn then
			appear = math.min(1, appear + dt / 0.3)
		else
			appear = math.max(0, appear - dt / 0.15)
			if appear == 0 and bolt.Visible then
				bolt.Visible, potion.Visible, countText.Visible = false, false, false
				pot.phase, pot.pouring = "idle", false
				pot.tilt, pot.liftX, pot.liftY = 0, 0, 0
				blueFor, flicker = 0, 0
			end
		end
		boltScale.Scale = popOut(appear)
	end

	local function stepDrops(dt)
		for i = #drops, 1, -1 do
			local d = drops[i]
			d.age = d.age + dt
			d.vy = d.vy + d.g * dt
			d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
			local landed = d.into and d.vy > 0 and d.y >= (surfaceY or 0) and d.x >= PX and d.x <= HW - PX
			if landed or d.age >= d.life then
				if landed then
					amp = math.min(H.Slosh or 1.6, amp + (d.splash or 0.15))
					counts.landed = counts.landed + 1
				end
				d.f:Destroy()
				table.remove(drops, i)
			else
				d.f.Position = UDim2.fromOffset(math.floor(d.x), math.floor(d.y))
				local fade = d.into and 0 or math.clamp((d.age - (d.life - 0.3)) / 0.3, 0, 1)
				d.f.BackgroundTransparency = fade
			end
		end
	end

	local function step(dt)
		dt = math.min(dt, 0.1)
		clock = clock + dt
		takeMoments()
		stepAppear(dt)
		stepHeart(dt)
		if appear > 0 then
			stepBolt(dt)
			stepPotion(dt)
		end
		stepDrops(dt)
		placeAll()
	end
	RunService.RenderStepped:Connect(step)

	return {
		hpText = hpText,
		powerText = powerText,
		-- (for the headless tests: a peek inside)
		peek = function()
			return {
				heart = shown,
				heartTarget = target,
				surfaceY = surfaceY,
				broken = broken ~= nil,
				bolt = boltLevel,
				appear = appear,
				potion = pot,
				drops = #drops,
				flicker = flicker,
				blue = blueFor,
				counts = counts,
			}
		end,
		parts = {
			vessel = vessel,
			halves = halves,
			heartCells = cells,
			heartOutline = outline,
			bolt = bolt,
			boltCells = boltCells,
			boltOutline = boltOutline,
			potion = potion,
			potionCells = potCells,
			potionOutline = potOutline,
			corkBits = corkBits,
			count = countText,
		},
	}
end

return Vitals
