--[[
	RetroUI  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "RetroUI")

	The game's look: MODERN RETRO, mixed from the pixel games that did it
	best - Undertale and Deltarune (the black box, the red heart SOUL, typed
	text), Pokemon (the double border, the bouncing title, the battle wipe),
	Stardew Valley (chunky pixel icons, soft pixel corners) and Celeste
	(everything squashes, bounces and sparkles) - with a souls-like edge and
	a clean screen.

	It changes nothing in how the other scripts build their screens: it
	watches for every bit of GUI as it appears (the HUD, the shops, the Spire
	menu, the boss bar, YOU DIED, the health bars over bosses and dummies,
	signs in the world...) and restyles it:

	  * PIXEL TEXT - a pixel font everywhere and a chunkier one for big titles,
	    with a crisp dark outline; nothing shrinks below Config.Retro.MinText
	  * THE BOX - dark panels become black boxes with a thick white border
	    (Undertale) and a thin second line inside it (Pokemon), with small
	    soft pixel corners
	  * PIXEL-ART COLOURS - every colour snapped to a bright 32-colour palette,
	    gradients turned into a few bands of colour, like pixel shading
	  * PIXEL-ART ICONS - hearts, stars, coins, potions, the lock... drawn as
	    little pixel sprites instead of emoji
	  * THE SOUL - the red heart sits beside the button you point at, and that
	    button's text turns yellow (Undertale's FIGHT / ACT / ITEM / MERCY)
	  * TYPED TEXT - new messages type themselves out, letter by letter, with
	    a little voice blip
	  * FEEL - buttons squash when you press them, menus pop open, and a
	    burst of pixel sparks on every click
	  * A TITLE SCREEN when you join - a night over the dunes with a sandworm
	    leaping through them, the title bouncing in, the subtitle typing
	    itself out, the SOUL beating - then the "encounter" flash and a
	    striped battle wipe into the game

	Every piece can be switched off in Config.Retro; On = false puts the old
	look back entirely. Only your own screen changes; nothing touches the server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local R = Config.Retro or {}
if R.On == false then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RGB = Color3.fromRGB

local function tween(inst, seconds, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- The palette (Endesga 32: a bright pixel-art palette loved by modern pixel games)
----------------------------------------------------------------------
local PALETTE = {
	RGB(190, 74, 47), RGB(215, 118, 67), RGB(234, 212, 170), RGB(228, 166, 114),
	RGB(184, 111, 80), RGB(115, 62, 57), RGB(62, 39, 49), RGB(162, 38, 51),
	RGB(228, 59, 68), RGB(247, 118, 34), RGB(254, 174, 52), RGB(254, 231, 97),
	RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66), RGB(25, 60, 62),
	RGB(18, 78, 137), RGB(0, 153, 219), RGB(44, 232, 245), RGB(255, 255, 255),
	RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136), RGB(58, 68, 102),
	RGB(38, 43, 68), RGB(24, 20, 37), RGB(255, 0, 68), RGB(104, 56, 108),
	RGB(181, 80, 136), RGB(246, 117, 122), RGB(232, 183, 150), RGB(194, 133, 105),
}
local INK = RGB(24, 20, 37) -- the darkest: outlines and shadows
local snapCache = {}
-- the nearest colour of the palette (weighted the way eyes see it)
local function snap(c)
	if R.Palette == false then
		return c
	end
	local key = math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
	local hit = snapCache[key]
	if hit then
		return hit
	end
	local best, bestD = c, math.huge
	for _, p in ipairs(PALETTE) do
		local dr, dg, db = c.R - p.R, c.G - p.G, c.B - p.B
		local d = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
		if d < bestD then
			best, bestD = p, d
		end
	end
	snapCache[key] = best
	return best
end

----------------------------------------------------------------------
-- The fonts
----------------------------------------------------------------------
local BODY_FONT = Enum.Font.Arcade
local TITLE_FACE = nil
pcall(function()
	-- (the chunky "Press Start" pixel font, for big titles, if this Roblox has it)
	local face = Font.new("rbxasset://fonts/families/PressStart2P.json")
	local probe = Instance.new("TextLabel")
	probe.FontFace = face
	TITLE_FACE = face
	probe:Destroy()
end)
local MIN_TEXT = R.MinText or 13
local CORNER = UDim.new(0, R.Corners or 4)

----------------------------------------------------------------------
-- Pixel-art icons (each letter is one pixel; "." is see-through)
----------------------------------------------------------------------
local INKS = {
	O = INK, R = RGB(228, 59, 68), r = RGB(162, 38, 51), W = RGB(255, 255, 255),
	Y = RGB(254, 231, 97), y = RGB(254, 174, 52), d = RGB(184, 111, 80), G = RGB(192, 203, 220),
	g = RGB(90, 105, 136), B = RGB(115, 62, 57), b = RGB(184, 111, 80), C = RGB(44, 232, 245),
	c = RGB(0, 153, 219), K = RGB(99, 199, 77), k = RGB(62, 137, 72),
}
local SPRITES = {
	["❤"] = {
		".OOO.OOO.",
		"ORWROrRRO",
		"ORRRRRRRO",
		"ORRRRRRrO",
		".ORRRRrO.",
		"..ORRrO..",
		"...ORO...",
		"....O....",
	},
	["⭐"] = {
		"....O....",
		"...OYO...",
		"OOOOYOOOO",
		"OYYYWYYyO",
		".OYYYYyO.",
		"..OYYYO..",
		".OYYOyyO.",
		".OyO.OyO.",
		".OO...OO.",
	},
	["⬆"] = {
		"....O....",
		"...OKO...",
		"..OKWKO..",
		".OKKKKkO.",
		"OOOKKkOOO",
		"..OKKkO..",
		"..OKKkO..",
		"..OKKkO..",
		"..OOOOO..",
	},
	["🎒"] = {
		".OOOOOOO.",
		"ObbbbbbbO",
		"ObBBBBBbO",
		"OOOOYOOOO",
		"ObbbybbbO",
		"ObbbbbbbO",
		"ObbbbbbBO",
		".OOOOOOO.",
	},
	["⚔"] = {
		"OO.....OO",
		"OWO...OGO",
		".OGO.OGO.",
		"..OGOGO..",
		"...OGO...",
		"..OBOBO..",
		".OBO.OBO.",
		"OYO...OYO",
		"OO.....OO",
	},
	["🧪"] = {
		"..OOO..",
		"..OGO..",
		"..OGO..",
		".OGGGO.",
		"OCCCCCO",
		"OCWCCCO",
		"OCCCCCO",
		"OcCCCcO",
		".OOOOO.",
	},
	["🔒"] = {
		"..OOO..",
		".OG.GO.",
		".OG.GO.",
		"OOOOOOO",
		"OYYWYYO",
		"OYYOYyO",
		"OYYOYyO",
		"OOOOOOO",
	},
	COIN = {
		"..OOOO..",
		".OYYYYO.",
		"OYWYYYyO",
		"OYWYOYyO",
		"OYYYOYyO",
		"OYYYOYyO",
		"OyYYYYdO",
		".OyyyydO",
		"..OOOO..",
	},
	-- the SOUL: the red heart that points at what you're choosing
	SOUL = {
		".OO.OO.",
		"ORROrRO",
		"ORRRRRO",
		"ORRRRrO",
		".ORRrO.",
		"..ORO..",
		"...O...",
	},
}

-- draws a sprite as a grid of little squares, filling `holder` (kept in shape)
local function drawSprite(rows, holder, scale)
	local h, w = #rows, #rows[1]
	local art = Instance.new("Frame")
	art.Name = "PixelSprite"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(scale or 0.9, scale or 0.9)
	art.SizeConstraint = Enum.SizeConstraint.RelativeYY
	art:SetAttribute("RetroSkip", true)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = w / h
	ratio.Parent = art
	for y = 1, h do
		local row = rows[y]
		for x = 1, w do
			local color = INKS[string.sub(row, x, x)]
			if color then
				local px = Instance.new("Frame")
				px.BorderSizePixel = 0
				px.BackgroundColor3 = color
				px.Size = UDim2.fromScale(1 / w + 0.002, 1 / h + 0.002) -- (a hair over, so no seams)
				px.Position = UDim2.fromScale((x - 1) / w, (y - 1) / h)
				px.ZIndex = (holder.ZIndex or 1) + 1
				px:SetAttribute("RetroSkip", true)
				px.Parent = art
			end
		end
	end
	art.Parent = holder
	return art
end

----------------------------------------------------------------------
-- Restyling one piece of GUI
----------------------------------------------------------------------
local done = setmetatable({}, { __mode = "k" })

local function skip(inst)
	if inst:GetAttribute("RetroSkip") == true then
		return true
	end
	-- (and everything on this script's own screens)
	local screen = inst:FindFirstAncestorWhichIsA("LayerCollector")
	return screen ~= nil and screen:GetAttribute("RetroSkip") == true
end

-- colours: snapped now, and again whenever the game changes them
local COLOR_PROPS = {
	Frame = { "BackgroundColor3" },
	ScrollingFrame = { "BackgroundColor3", "ScrollBarImageColor3" },
	TextLabel = { "BackgroundColor3", "TextColor3", "TextStrokeColor3" },
	TextButton = { "BackgroundColor3", "TextColor3", "TextStrokeColor3" },
	TextBox = { "BackgroundColor3", "TextColor3", "TextStrokeColor3" },
	ImageLabel = { "BackgroundColor3" },
	ImageButton = { "BackgroundColor3" },
	UIStroke = { "Color" },
}
local function snapProps(inst, props)
	for _, prop in ipairs(props) do
		local ok, c = pcall(function()
			return inst[prop]
		end)
		if ok and typeof(c) == "Color3" then
			local s = snap(c)
			if s ~= c then
				inst[prop] = s
			end
			inst:GetPropertyChangedSignal(prop):Connect(function()
				local now = inst[prop]
				local sn = snap(now)
				if sn ~= now then
					inst[prop] = sn
				end
			end)
		end
	end
end

-- gradients: a few bands of palette colour instead of a smooth blend (pixel shading)
local function bandGradient(g)
	local n = R.Bands or 3
	if n <= 0 then
		return
	end
	local busy = false
	local function band()
		if busy then
			return
		end
		local seq = g.Color
		local keys = typeof(seq) == "ColorSequence" and seq.Keypoints
		if not keys or #keys == 0 then
			return
		end
		local function colorAt(t)
			for i = 1, #keys - 1 do
				local a, b = keys[i], keys[i + 1]
				if t >= a.Time and t <= b.Time then
					return a.Value:Lerp(b.Value, (t - a.Time) / math.max(b.Time - a.Time, 1e-4))
				end
			end
			return keys[#keys].Value
		end
		local out = {}
		for i = 0, n - 1 do
			local c = snap(colorAt((i + 0.5) / n))
			local t0, t1 = i / n, (i + 1) / n
			if i > 0 then
				t0 = t0 + 0.0005
			end
			out[#out + 1] = ColorSequenceKeypoint.new(t0, c)
			out[#out + 1] = ColorSequenceKeypoint.new(t1, c)
		end
		busy = true
		g.Color = ColorSequence.new(out)
		busy = false
	end
	band()
	g:GetPropertyChangedSignal("Color"):Connect(band)
end

-- Text that no longer fits (pixel letters are wider) shrinks until it does -
-- but never below MIN_TEXT; and tiny text is brought up to MIN_TEXT
local originalSize = setmetatable({}, { __mode = "k" })
local sizing = setmetatable({}, { __mode = "k" })
local function fitText(label)
	if label.TextScaled then
		return
	end
	if not originalSize[label] then
		originalSize[label] = label.TextSize
		-- (the game changing its size on purpose: that's its new size)
		label:GetPropertyChangedSignal("TextSize"):Connect(function()
			if not sizing[label] then
				originalSize[label] = label.TextSize
			end
		end)
	end
	task.defer(function()
		sizing[label] = true
		local base = math.max(originalSize[label], MIN_TEXT)
		label.TextSize = base
		local floor = math.max(MIN_TEXT, math.floor(base * 0.6))
		local tries = 0
		while label.Parent and not label.TextFits and label.TextSize > floor and tries < 30 do
			label.TextSize = label.TextSize - 1
			tries = tries + 1
		end
		sizing[label] = nil
	end)
end

-- an emoji icon (or the HUD's drawn coin) becomes a pixel sprite
local function spriteFor(label)
	local function check()
		local key = string.gsub(label.Text, "\u{FE0F}", "")
		key = string.gsub(key, "%s", "")
		local old = label:FindFirstChild("PixelSprite")
		local rows = SPRITES[key]
		if rows then
			if not old or old:GetAttribute("For") ~= key then
				if old then
					old:Destroy()
				end
				label.TextTransparency = 1
				drawSprite(rows, label):SetAttribute("For", key)
			end
		elseif old then
			old:Destroy()
			label.TextTransparency = 0
		end
	end
	check()
	label:GetPropertyChangedSignal("Text"):Connect(check)
end

-- New messages type themselves out, letter by letter, with a voice blip.
-- Only real new words: a counter or a timer (only its numbers changing), a
-- label that changes several times a second, or text you type yourself show
-- at once, as before. (It only hides letters for a moment - the text itself
-- is never touched.)
local typing = setmetatable({}, { __mode = "k" })
local voiceSound = nil
local lastVoice = 0
local function voice()
	if voiceSound == nil then
		local t = R.TypeBlip and SoundService:FindFirstChild(R.TypeBlip)
		voiceSound = false
		if t and t:IsA("Sound") then
			voiceSound = t:Clone()
			voiceSound.Name = "RetroVoice"
			voiceSound.Volume = t.Volume * 0.5
			voiceSound.Parent = SoundService
		end
	end
	local now = os.clock()
	if voiceSound and now - lastVoice > 0.06 then
		lastVoice = now
		voiceSound.TimePosition = 0
		voiceSound:Play()
	end
end
local function words(text)
	return (string.gsub(text, "[%d%p%s]", ""))
end
local function typeOut(label, speed)
	local id = {}
	typing[label] = id
	label.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown, start = 0, os.clock()
		local function letters()
			local n = utf8.len(label.ContentText) or 0
			return n > 0 and n or (utf8.len(label.Text) or #label.Text)
		end
		while typing[label] == id and shown < letters() and label.Parent do
			local n = letters()
			local want = math.min(n, math.floor((os.clock() - start) * speed) + 1)
			if want > shown then
				shown = want
				label.MaxVisibleGraphemes = shown
				if label.Visible then
					voice()
				end
			end
			task.wait()
		end
		if typing[label] == id then
			typing[label] = nil
			label.MaxVisibleGraphemes = -1
		end
	end)
end
local function typewriter(label)
	if R.Typewriter == false or label:IsA("TextBox") or not label:IsDescendantOf(playerGui)
		or label:FindFirstAncestorWhichIsA("ScrollingFrame") then
		return
	end
	local last, lastAt = label.Text, 0
	label:GetPropertyChangedSignal("Text"):Connect(function()
		local text, before = label.Text, last
		last = text
		local now = os.clock()
		local quick = now - lastAt < 0.5
		lastAt = now
		if quick or #text < 12 or not string.find(text, "%a%a") or words(text) == words(before) then
			if typing[label] then
				typing[label] = nil
				label.MaxVisibleGraphemes = -1
			end
			return
		end
		typeOut(label, R.TypeSpeed or 40)
	end)
end

local function restyleText(label)
	if R.PixelFont ~= false then
		local big = label.TextSize >= 40 or (label.TextScaled and label.AbsoluteSize.Y >= 44)
		local ok = false
		if big and TITLE_FACE then
			ok = pcall(function()
				label.FontFace = TITLE_FACE
			end)
		end
		if not ok then
			label.Font = BODY_FONT
		end
		fitText(label)
		label:GetPropertyChangedSignal("Text"):Connect(function()
			fitText(label)
		end)
	end
	-- a crisp dark outline on the letters (unless it already has one)
	if not label:FindFirstChildOfClass("UIStroke") and label.TextStrokeTransparency >= 0.99 and label.TextTransparency < 0.9 then
		label.TextStrokeColor3 = INK
		label.TextStrokeTransparency = 0.35
	end
	if R.Sprites ~= false then
		spriteFor(label)
	end
	typewriter(label)
end

-- the HUD's drawn gold coin (a round frame with a "$" on it) becomes a pixel coin
local function pixelCoin(frame)
	if R.Sprites == false or frame:FindFirstChild("PixelSprite") then
		return
	end
	task.defer(function()
		frame.BackgroundTransparency = 1
		for _, d in ipairs(frame:GetChildren()) do
			if d:IsA("UIStroke") then
				d.Transparency = 1
			elseif d:IsA("TextLabel") then
				d.TextTransparency = 1
				d.TextStrokeTransparency = 1
			end
		end
		drawSprite(SPRITES.COIN, frame, 1)
	end)
end

----------------------------------------------------------------------
-- Feel: the pointer arrow, the squash, the pop, the sparks
----------------------------------------------------------------------
local fxGui = nil -- (made below: our own screen, above the others)
local cursor, cursorOn = nil, nil

local function burst(at)
	if R.ClickBurst == false or not fxGui then
		return
	end
	for i = 1, 8 do
		local sq = Instance.new("Frame")
		sq.BorderSizePixel = 0
		sq.BackgroundColor3 = PALETTE[({ 12, 20, 12, 20, 11, 9 })[(i % 6) + 1]]
		sq.Size = UDim2.fromOffset(6, 6)
		sq.AnchorPoint = Vector2.new(0.5, 0.5)
		sq.Position = UDim2.fromOffset(at.X, at.Y)
		sq.Parent = fxGui
		local a = (i / 8) * math.pi * 2 + math.random() * 0.4
		local d = 26 + math.random() * 22
		tween(sq, 0.35, {
			Position = UDim2.fromOffset(at.X + math.cos(a) * d, at.Y + math.sin(a) * d + 8),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		})
		task.delay(0.4, function()
			sq:Destroy()
		end)
	end
	local name = R.Blip
	local template = name and SoundService:FindFirstChild(name)
	if template and template:IsA("Sound") then
		local s = template:Clone()
		s.Parent = SoundService
		s:Play()
		task.delay(2, function()
			s:Destroy()
		end)
	end
end

-- a UIScale of our own on something, unless the game already scales it
-- (then we leave it be, so we never fight the game's own animations)
local function ownScale(inst, name)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("UIScale") then
			return c.Name == name and c or nil
		end
	end
	local s = Instance.new("UIScale")
	s.Name = name
	s:SetAttribute("RetroSkip", true)
	s.Parent = inst
	return s
end

-- the button you point at: its text turns yellow (and back when you leave)
local YELLOW = RGB(254, 231, 97)
local function hoverTexts(button)
	local list = {}
	if button:IsA("TextButton") then
		list[1] = button
	end
	for _, c in ipairs(button:GetChildren()) do
		if c:IsA("TextLabel") and not c:GetAttribute("RetroSkip") then
			list[#list + 1] = c
		end
	end
	return list
end

local function restyleButton(button)
	local was = {}
	button.MouseEnter:Connect(function()
		cursorOn = button
		if R.HoverYellow ~= false then
			for _, t in ipairs(hoverTexts(button)) do
				if t.TextColor3 ~= YELLOW then
					was[t] = t.TextColor3
					t.TextColor3 = YELLOW
				end
			end
		end
		local st = button:FindFirstChildOfClass("UIStroke")
		if st then
			local was = st.Color
			st.Color = RGB(255, 255, 255)
			task.delay(0.09, function()
				if st.Parent then
					st.Color = was
				end
			end)
		end
	end)
	button.MouseLeave:Connect(function()
		if cursorOn == button then
			cursorOn = nil
		end
		-- (put the colour back - unless the game has changed it meanwhile)
		for t, c in pairs(was) do
			if t.Parent and t.TextColor3 == YELLOW then
				t.TextColor3 = c
			end
		end
		table.clear(was)
	end)
	button.MouseButton1Down:Connect(function()
		if R.Bounce == false then
			return
		end
		local s = ownScale(button, "RetroPress")
		if s then
			tween(s, 0.06, { Scale = 0.92 })
			task.delay(0.07, function()
				tween(s, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	end)
	button.Activated:Connect(function()
		burst(UserInputService:GetMouseLocation())
	end)
end

-- Panels: the Undertale box (black, a thick white border), and a pop when they open
local WHITE = RGB(255, 255, 255)
local function lum(c)
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end
-- a dark colour: a panel's fill that should become the black of the box
local function dark(c)
	return lum(c) < 0.25
end
-- a plain border (grey, dark or dull): one that becomes white. Coloured ones
-- (gold, green, red...) are left be - they mean something.
local function plain(c)
	return math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B) < 0.25 or lum(c) < 0.3
end
local function isPanel(frame)
	local size = frame.AbsoluteSize
	return frame.BackgroundTransparency < 0.5 and size.X >= 120 and size.Y >= 60 and frame:FindFirstChildOfClass("UIStroke") ~= nil
end
local function hasLayout(frame)
	return frame:FindFirstChildOfClass("UIListLayout") or frame:FindFirstChildOfClass("UIGridLayout")
		or frame:FindFirstChildOfClass("UIPageLayout") or frame:FindFirstChildOfClass("UITableLayout")
end

local function makeBox(frame)
	if R.Boxes == false or not dark(frame.BackgroundColor3) then
		return
	end
	-- the fill goes black, and stays black whenever the game sets another dark colour
	frame.BackgroundColor3 = INK
	frame:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local c = frame.BackgroundColor3
		if c ~= INK and dark(c) then
			frame.BackgroundColor3 = INK
		end
	end)
	-- the border goes white and thick
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke and plain(stroke.Color) then
		stroke.Color = WHITE
		stroke.Thickness = math.max(stroke.Thickness, R.BoxBorder or 3)
		stroke:GetPropertyChangedSignal("Color"):Connect(function()
			local c = stroke.Color
			if c ~= WHITE and plain(c) then
				stroke.Color = WHITE
			end
		end)
	end
end

local function restylePanel(frame)
	local finished = false
	local sizeConn
	local function try()
		if finished or not frame.Parent or not isPanel(frame) then
			return
		end
		finished = true
		if sizeConn then
			sizeConn:Disconnect()
		end
		makeBox(frame)
		-- the second, thin line inside the border (the Pokemon double border;
		-- skipped if the panel lays its children out in a list or grid: ours
		-- would be laid out with them)
		if R.Bevel == true and not hasLayout(frame) and not frame:FindFirstChild("RetroBevel") then
			local bevel = Instance.new("Frame")
			bevel.Name = "RetroBevel"
			bevel.BackgroundTransparency = 1
			bevel.AnchorPoint = Vector2.new(0.5, 0.5)
			bevel.Position = UDim2.fromScale(0.5, 0.5)
			bevel.Size = UDim2.new(1, -10, 1, -10)
			bevel.ZIndex = frame.ZIndex or 1
			bevel:SetAttribute("RetroSkip", true)
			local edge = Instance.new("UIStroke")
			edge.Color = WHITE
			edge.Transparency = 0.55
			edge.Thickness = 2
			edge.LineJoinMode = Enum.LineJoinMode.Miter
			edge.Parent = bevel
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, math.max((R.Corners or 0) - 2, 0))
			c.Parent = bevel
			bevel.Parent = frame
		end
		-- a pop when it opens (a big panel: a menu, a shop)
		if R.Bounce ~= false and frame.AbsoluteSize.X >= 250 and frame.AbsoluteSize.Y >= 160 then
			frame:GetPropertyChangedSignal("Visible"):Connect(function()
				if frame.Visible then
					local s = ownScale(frame, "RetroPop")
					if s then
						s.Scale = 0.88
						tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
					end
				end
			end)
		end
	end
	task.defer(try)
	-- (a panel that isn't laid out yet - no size - is looked at again once it is)
	sizeConn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(try)
end

-- health, level and boss bars: split into segments
local function segment(bar, count)
	if R.SegmentBars == false or bar:FindFirstChild("RetroSegments") then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "RetroSegments"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = (bar.ZIndex or 1) + 1
	holder:SetAttribute("RetroSkip", true)
	for i = 1, count - 1 do
		local tick = Instance.new("Frame")
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = INK
		tick.BackgroundTransparency = 0.5
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(i / count, 0)
		tick.Size = UDim2.new(0, 2, 1, 0)
		tick.ZIndex = (bar.ZIndex or 1) + 1
		tick:SetAttribute("RetroSkip", true)
		tick.Parent = holder
	end
	holder.Parent = bar
end

local function restyle(inst)
	if done[inst] or skip(inst) then
		return
	end
	done[inst] = true
	local props = COLOR_PROPS[inst.ClassName]
	if props then
		snapProps(inst, props)
	end
	if inst:IsA("UICorner") then
		-- soft pixel corners: round things become rounded squares too
		inst.CornerRadius = CORNER
		inst:GetPropertyChangedSignal("CornerRadius"):Connect(function()
			if inst.CornerRadius ~= CORNER then
				inst.CornerRadius = CORNER
			end
		end)
	elseif inst:IsA("UIStroke") then
		inst.LineJoinMode = Enum.LineJoinMode.Miter
		if inst.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			inst.Thickness = math.max(2, math.floor(inst.Thickness + 0.5))
		end
	elseif inst:IsA("UIGradient") then
		bandGradient(inst)
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		restyleText(inst)
	elseif (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and R.PixelImages == true then
		pcall(function()
			inst.ResampleMode = Enum.ResamplerMode.Pixelated
		end)
	end
	if inst:IsA("GuiButton") then
		restyleButton(inst)
	end
	if inst:IsA("Frame") then
		if inst.Name == "HealthBar" or inst.Name == "GoalBar" then
			segment(inst, inst.Name == "HealthBar" and 10 or 20)
		elseif inst.Name == "Coin" then
			pixelCoin(inst)
		else
			restylePanel(inst)
		end
	end
	-- the boss bar: its bar is the frame with an outline in the "BossBar" screen
	if inst:IsA("UIStroke") and inst.Parent and inst.Parent:IsA("Frame") and inst:FindFirstAncestor("BossBar") then
		segment(inst.Parent, 20)
	end
end

local function watch(root)
	for _, d in ipairs(root:GetDescendants()) do
		restyle(d)
	end
	root.DescendantAdded:Connect(function(d)
		-- (a moment later: whatever built it has set it up by then)
		task.defer(restyle, d)
	end)
end

----------------------------------------------------------------------
-- Our own screens
----------------------------------------------------------------------
local function ownGui(name, order)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = order
	g:SetAttribute("RetroSkip", true)
	g.Parent = playerGui
	return g
end

fxGui = ownGui("RetroFX", 990)

-- the SOUL: the red heart beside whichever button you're pointing at
if R.Cursor ~= false then
	cursor = Instance.new("Frame")
	cursor.BackgroundTransparency = 1
	cursor.Size = UDim2.fromOffset(16, 16)
	cursor.AnchorPoint = Vector2.new(1, 0.5)
	cursor.Visible = false
	cursor.Parent = fxGui
	drawSprite(SPRITES.SOUL, cursor, 1)
	local inset = Vector2.new(0, 0)
	pcall(function()
		inset = game:GetService("GuiService"):GetGuiInset()
	end)
	RunService.RenderStepped:Connect(function()
		local b = cursorOn
		if b and b.Parent and b.Visible and b.AbsoluteSize.Y >= 22 then
			local ok, pos, size = pcall(function()
				return b.AbsolutePosition, b.AbsoluteSize
			end)
			if ok then
				-- (buttons on screens that leave room for the top bar are that much lower)
				local screen = b:FindFirstAncestorWhichIsA("ScreenGui")
				local dy = (screen and not screen.IgnoreGuiInset) and inset.Y or 0
				local bob = math.floor(math.sin(os.clock() * 6) + 1) -- (a gentle 1-pixel sway)
				cursor.Position = UDim2.fromOffset(pos.X - 6 - bob, pos.Y + size.Y / 2 + dy)
				cursor.Visible = true
				return
			end
		end
		cursor.Visible = false
	end)
end

-- the old-TV screen (off unless Config.Retro.Scanlines is below 1)
if (R.Scanlines or 1) < 1 then
	local crt = ownGui("RetroCRT", 980)
	local lines = {}
	local function build()
		for _, l in ipairs(lines) do
			l:Destroy()
		end
		table.clear(lines)
		local cam = Workspace.CurrentCamera
		local size = cam and cam.ViewportSize
		local h = size and size.Y or 1080
		for y = 0, h, 4 do
			local l = Instance.new("Frame")
			l.BorderSizePixel = 0
			l.BackgroundColor3 = INK
			l.BackgroundTransparency = R.Scanlines
			l.Position = UDim2.fromOffset(0, y)
			l.Size = UDim2.new(1, 0, 0, 1)
			l.Active = false
			l.Parent = crt
			lines[#lines + 1] = l
		end
	end
	build()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(build)
	end
end

----------------------------------------------------------------------
-- The title screen: once, when you join
----------------------------------------------------------------------
-- Night over the dunes (Deltarune's dark world colours), a sandworm leaping
-- far off, the title bouncing in with a hard shadow (Pokemon), the subtitle
-- typing itself out and the SOUL beating underneath (Undertale) - and on any
-- key, the "encounter": everything goes black but the heart, it flashes three
-- times, and a striped battle wipe opens onto the game.
if R.StartScreen ~= false then
	local BLACK = RGB(0, 0, 0)
	local title = ownGui("RetroTitle", 1000)
	local back = Instance.new("Frame")
	back.BorderSizePixel = 0
	back.BackgroundColor3 = BLACK
	back.Size = UDim2.fromScale(1, 1)
	back.Active = true
	back.ClipsDescendants = true
	back.Parent = title

	-- twinkling stars
	local stars = {}
	for i = 1, 50 do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = (i % 7 == 0) and RGB(44, 232, 245) or WHITE
		local size = (i % 6 == 0) and 4 or 2
		s.Size = UDim2.fromOffset(size, size)
		s.Position = UDim2.fromScale(math.random(), math.random() * 0.6)
		s.Parent = back
		stars[i] = { part = s, rate = 1 + math.random() * 3, phase = math.random() * 6 }
	end
	-- a pale moon
	local moon = Instance.new("Frame")
	moon.BorderSizePixel = 0
	moon.BackgroundColor3 = RGB(192, 203, 220)
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromScale(0.82, 0.18)
	moon.Size = UDim2.fromScale(0.09, 0.09)
	moon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	moon.Parent = back
	local moonC = Instance.new("UICorner")
	moonC.CornerRadius = UDim.new(0.5, 0)
	moonC.Parent = moon

	-- the sandworm, leaping through the dunes far off (a string of round segments)
	local worm = {}
	for i = 1, 14 do
		local seg = Instance.new("Frame")
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = (i % 2 == 0) and RGB(104, 56, 108) or RGB(68, 36, 72)
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		local size = 0.05 - i * 0.0018
		seg.Size = UDim2.fromScale(size, size)
		seg.SizeConstraint = Enum.SizeConstraint.RelativeYY
		seg.ZIndex = 3
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.35, 0)
		c.Parent = seg
		seg.Parent = back
		worm[i] = seg
	end

	-- three layers of dark dunes, drifting past at different speeds
	local layers = {}
	for L, info in ipairs({
		{ RGB(58, 68, 102), 0.8, 0.07, 2 },
		{ RGB(38, 43, 68), 0.86, 0.06, 4 },
		{ RGB(24, 20, 37), 0.93, 0.05, 5 },
	}) do
		local strip = Instance.new("Frame")
		strip.BackgroundTransparency = 1
		strip.Size = UDim2.fromScale(2, 1)
		strip.ZIndex = info[4]
		strip.Parent = back
		for i = 0, 79 do
			local col = Instance.new("Frame")
			col.BorderSizePixel = 0
			col.BackgroundColor3 = info[1]
			local hgt = (1 - info[2]) + info[3] * (math.sin(i * (0.35 + L * 0.07)) + 1) / 2
			col.AnchorPoint = Vector2.new(0, 1)
			col.Position = UDim2.fromScale(i / 80, 1)
			col.Size = UDim2.new(1 / 80, 1, hgt, 0)
			col.ZIndex = info[4]
			col.Parent = strip
		end
		layers[L] = { strip = strip, speed = 0.01 * L }
	end

	local function label(text, y, h, color, chunky)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.new(0.9, 0, h, 0)
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeColor3 = BLACK
		l.TextStrokeTransparency = 0
		l.ZIndex = 8
		if chunky and TITLE_FACE then
			l.FontFace = TITLE_FACE
		else
			l.Font = BODY_FONT
		end
		l.Parent = back
		return l
	end
	-- the title bounces in from above with a hard purple shadow; then the
	-- subtitle types itself out in yellow
	local shadow = label(R.Title or "DEFEAT THE BOSS", -0.2, 0.12, RGB(104, 56, 108), true)
	shadow.ZIndex = 7
	local main = label(R.Title or "DEFEAT THE BOSS", -0.2, 0.12, WHITE, true)
	tween(main, 0.8, { Position = UDim2.fromScale(0.5, 0.3) }, Enum.EasingStyle.Bounce)
	tween(shadow, 0.8, { Position = UDim2.new(0.5, 6, 0.3, 6) }, Enum.EasingStyle.Bounce)
	local sub = label(R.Subtitle or "TO GROW", 0.42, 0.06, YELLOW, true)
	sub.MaxVisibleGraphemes = 0
	local press = label("[ PRESS ANY KEY ]", 0.7, 0.04, RGB(139, 155, 180), false)

	-- the SOUL, beating
	local soul = Instance.new("Frame")
	soul.BackgroundTransparency = 1
	soul.AnchorPoint = Vector2.new(0.5, 0.5)
	soul.Position = UDim2.fromScale(0.5, 0.57)
	soul.Size = UDim2.fromScale(0.07, 0.07)
	soul.SizeConstraint = Enum.SizeConstraint.RelativeYY
	soul.ZIndex = 20
	soul.Parent = back
	drawSprite(SPRITES.SOUL, soul, 1)
	local beat = Instance.new("UIScale")
	beat.Parent = soul

	local t0 = os.clock()
	local closing = false
	local typed = 0
	local letters = utf8.len(sub.Text) or #sub.Text
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		-- the subtitle types itself out once the title has landed, a blip a letter
		local want = math.clamp(math.floor((t - 0.9) * 12), 0, letters)
		if want > typed then
			typed = want
			sub.MaxVisibleGraphemes = want
			voice()
			if want >= letters then
				sub.MaxVisibleGraphemes = -1
			end
		end
		press.Visible = t > 1.6 and (math.floor(t * 2) % 2 == 0)
		if not closing then
			beat.Scale = 1 + 0.12 * math.max(0, math.sin(t * 4.5)) ^ 6
		end
		for _, s in ipairs(stars) do
			s.part.BackgroundTransparency = (math.sin(t * s.rate + s.phase) > 0.2) and 0 or 0.8
		end
		for _, l in ipairs(layers) do
			l.strip.Position = UDim2.fromScale(-((t * l.speed) % 1), 0)
		end
		-- the worm: leaps out of the far dunes, arcs over and dives back in,
		-- every few seconds, from somewhere new
		local cycle = 3.2
		local k = (t % cycle) / cycle
		local run = math.floor(t / cycle)
		local x0 = 0.1 + ((run * 0.37) % 0.6)
		for i, seg in ipairs(worm) do
			local u = k * 1.6 - i * 0.035
			if u > 0 and u < 1 then
				seg.Visible = true
				seg.Position = UDim2.fromScale(x0 + u * 0.28, 0.84 - math.sin(u * math.pi) * 0.2)
			else
				seg.Visible = false
			end
		end
	end)

	-- the way out: the encounter flash
	local function close()
		if closing then
			return
		end
		closing = true
		beat.Scale = 1
		-- everything goes black but the heart
		local cover = Instance.new("Frame")
		cover.BorderSizePixel = 0
		cover.BackgroundColor3 = BLACK
		cover.Size = UDim2.fromScale(1, 1)
		cover.ZIndex = 19
		cover.Parent = title
		soul.Parent = title
		task.spawn(function()
			-- three flashes, a blip each
			for _ = 1, 3 do
				soul.Visible = true
				voice()
				task.wait(0.08)
				soul.Visible = false
				task.wait(0.07)
			end
			back.Visible = false
			conn:Disconnect()
			-- the battle wipe: the black splits into stripes that slide off,
			-- alternately left and right, onto the game
			local n = 10
			for i = 1, n do
				local bar = Instance.new("Frame")
				bar.BorderSizePixel = 0
				bar.BackgroundColor3 = BLACK
				bar.Position = UDim2.fromScale(0, (i - 1) / n)
				bar.Size = UDim2.new(1, 0, 1 / n, 1)
				bar.ZIndex = 19
				bar.Parent = title
				tween(bar, 0.45, { Position = UDim2.fromScale((i % 2 == 0) and 1.05 or -1.05, (i - 1) / n) },
					Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			cover:Destroy()
			task.wait(0.5)
			title:Destroy()
		end)
	end
	UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.Gamepad1 then
			close()
		end
	end)
	task.delay(12, close) -- (and it gets out of the way by itself)
end

----------------------------------------------------------------------
-- Go: every screen there is, and every one that appears
----------------------------------------------------------------------
watch(playerGui)

-- health bars over bosses and dummies, and signs out in the world
local function watchWorldGui(gui)
	restyle(gui)
	watch(gui)
end
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
		watchWorldGui(d)
	end
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
		task.defer(watchWorldGui, d)
	end
end)
