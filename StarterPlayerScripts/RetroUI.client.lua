--[[
	RetroUI  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "RetroUI")

	The game's look: an 8-bit, Terraria-style retro skin with a souls-like
	edge, laid over every screen in the game. It changes nothing in how the
	other scripts build their screens - it watches for every bit of GUI as it
	appears (the HUD, the shops, the Spire menu, the boss bar, YOU DIED, the
	health bars over bosses and dummies, signs in the world...) and restyles it:

	  * PIXEL TEXT - an arcade pixel font everywhere, and a chunkier pixel
	    font for big titles. Anything that would no longer fit shrinks to fit.
	  * 8-BIT COLOURS - every colour snapped to a 32-colour retro palette, and
	    smooth gradients turned into hard bands of colour, like old consoles
	  * HARD PIXEL EDGES - square corners, crisp thick outlines, text with a
	    hard dark outline, and pictures drawn with chunky (unsmoothed) pixels
	  * PIXEL-ART ICONS - the emoji icons (hearts, stars, potions, the lock...)
	    redrawn as little pixel sprites
	  * CHUNKY BARS - your health bar, level bar and the boss bar split into
	    segments, like a retro life bar
	  * FUN - a burst of pixel sparks every time you click a button, button
	    borders that flash when you point at them, a faint old-TV scanline
	    screen, and a title screen when you join (twinkling pixel stars, a
	    blinking PRESS ANY KEY, and a pixel-dissolve wipe into the game)

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

----------------------------------------------------------------------
-- The palette (Endesga 32: a well-loved 32-colour pixel-art palette)
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

----------------------------------------------------------------------
-- Pixel-art icons (each letter is one pixel; "." is see-through)
----------------------------------------------------------------------
local INKS = {
	O = INK, R = RGB(228, 59, 68), r = RGB(162, 38, 51), W = RGB(255, 255, 255),
	Y = RGB(254, 231, 97), y = RGB(254, 174, 52), G = RGB(192, 203, 220), g = RGB(90, 105, 136),
	B = RGB(115, 62, 57), b = RGB(184, 111, 80), C = RGB(44, 232, 245), c = RGB(0, 153, 219),
	K = RGB(99, 199, 77), k = RGB(62, 137, 72),
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
}

-- draws a sprite as a grid of little squares, filling `holder` (kept square)
local function drawSprite(rows, holder)
	local h, w = #rows, #rows[1]
	local art = Instance.new("Frame")
	art.Name = "PixelSprite"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(0.9, 0.9)
	art.SizeConstraint = Enum.SizeConstraint.RelativeYY
	art:SetAttribute("RetroSkip", true)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = w / h
	ratio.Parent = art
	for y = 1, h do
		local row = rows[y]
		for x = 1, w do
			local ch = string.sub(row, x, x)
			local color = INKS[ch]
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
local originalSize = setmetatable({}, { __mode = "k" })

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

-- gradients: hard bands of palette colour instead of a smooth blend
local function bandGradient(g)
	local n = R.Bands or 4
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
					local k = (t - a.Time) / math.max(b.Time - a.Time, 1e-4)
					return a.Value:Lerp(b.Value, k)
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

-- text that no longer fits (pixel letters are wider) shrinks until it does
local shrinking = setmetatable({}, { __mode = "k" })
local function fitText(label)
	if label.TextScaled then
		return
	end
	if not originalSize[label] then
		originalSize[label] = label.TextSize
		-- (the game changing its size on purpose: that's its new size)
		label:GetPropertyChangedSignal("TextSize"):Connect(function()
			if not shrinking[label] then
				originalSize[label] = label.TextSize
			end
		end)
	end
	local base = originalSize[label]
	task.defer(function()
		shrinking[label] = true
		label.TextSize = base
		local floor = math.max(8, math.floor(base * 0.55))
		local tries = 0
		while label.Parent and not label.TextFits and label.TextSize > floor and tries < 30 do
			label.TextSize = label.TextSize - 1
			tries = tries + 1
		end
		shrinking[label] = nil
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
	-- a hard dark outline on the letters (unless it already has one)
	if not label:FindFirstChildOfClass("UIStroke") and label.TextStrokeTransparency >= 0.99 and label.TextTransparency < 0.9 then
		label.TextStrokeColor3 = INK
		label.TextStrokeTransparency = 0.25
	end
	-- an emoji icon becomes a pixel sprite
	if R.Sprites ~= false then
		local function spriteCheck()
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
		spriteCheck()
		label:GetPropertyChangedSignal("Text"):Connect(spriteCheck)
	end
end

-- a burst of pixel sparks where you clicked
local burstGui = nil
local function burst(at)
	if R.ClickBurst == false or not burstGui then
		return
	end
	for i = 1, 8 do
		local sq = Instance.new("Frame")
		sq.BorderSizePixel = 0
		sq.BackgroundColor3 = PALETTE[({ 12, 11, 20, 19, 13, 9 })[(i % 6) + 1]]
		sq.Size = UDim2.fromOffset(6, 6)
		sq.AnchorPoint = Vector2.new(0.5, 0.5)
		sq.Position = UDim2.fromOffset(at.X, at.Y)
		sq:SetAttribute("RetroSkip", true)
		sq.Parent = burstGui
		local a = (i / 8) * math.pi * 2 + math.random() * 0.4
		local d = 26 + math.random() * 22
		TweenService:Create(sq, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(at.X + math.cos(a) * d, at.Y + math.sin(a) * d + 8),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		}):Play()
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

local function restyleButton(button)
	button.MouseEnter:Connect(function()
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
	button.Activated:Connect(function()
		burst(UserInputService:GetMouseLocation() - Vector2.new(0, 0))
	end)
end

-- health, level and boss bars: split into chunky segments
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
		tick.BackgroundTransparency = 0.35
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(i / count, 0)
		tick.Size = UDim2.new(0, 3, 1, 0)
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
		inst.CornerRadius = UDim.new(0, 0)
		inst:GetPropertyChangedSignal("CornerRadius"):Connect(function()
			if inst.CornerRadius ~= UDim.new(0, 0) then
				inst.CornerRadius = UDim.new(0, 0)
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
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		pcall(function()
			inst.ResampleMode = Enum.ResamplerMode.Pixelated
		end)
	end
	if inst:IsA("GuiButton") then
		restyleButton(inst)
	end
	if inst:IsA("Frame") and (inst.Name == "HealthBar" or inst.Name == "GoalBar") then
		segment(inst, inst.Name == "HealthBar" and 10 or 20)
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

watch(playerGui)

-- health bars over bosses and dummies, and signs out in the world
local function watchWorldGui(gui)
	if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
		restyle(gui)
		watch(gui)
	end
end
for _, d in ipairs(Workspace:GetDescendants()) do
	watchWorldGui(d)
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
		task.defer(watchWorldGui, d)
	end
end)

----------------------------------------------------------------------
-- Our own screens: the sparks, the old-TV lines, the title screen
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

burstGui = ownGui("RetroSparks", 990)

-- the old-TV screen: faint dark lines across it, darker round the edges
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
			l:SetAttribute("RetroSkip", true)
			l.Parent = crt
			lines[#lines + 1] = l
		end
	end
	build()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(build)
	end
	-- the corners darker, like an old screen
	for _, rot in ipairs({ 0, 90 }) do
		local v = Instance.new("Frame")
		v.BorderSizePixel = 0
		v.BackgroundColor3 = INK
		v.Size = UDim2.fromScale(1, 1)
		v.Active = false
		v:SetAttribute("RetroSkip", true)
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.12, 1),
			NumberSequenceKeypoint.new(0.88, 1),
			NumberSequenceKeypoint.new(1, 0.55),
		})
		g:SetAttribute("RetroSkip", true)
		g.Parent = v
		v.Parent = crt
	end
end

-- The title screen: once, when you join
if R.StartScreen ~= false then
	local title = ownGui("RetroTitle", 1000)
	local back = Instance.new("Frame")
	back.BorderSizePixel = 0
	back.BackgroundColor3 = RGB(24, 20, 37)
	back.Size = UDim2.fromScale(1, 1)
	back.Active = true
	back.Parent = title

	-- twinkling pixel stars
	local stars = {}
	for i = 1, 60 do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = PALETTE[({ 20, 21, 12, 19 })[(i % 4) + 1]]
		local size = (i % 7 == 0) and 6 or 3
		s.Size = UDim2.fromOffset(size, size)
		s.Position = UDim2.fromScale(math.random(), math.random() * 0.9)
		s.Parent = back
		stars[i] = { part = s, rate = 1 + math.random() * 3, phase = math.random() * 6 }
	end
	-- the ground: a strip of pixel sand dunes along the bottom
	for i = 0, 39 do
		local col = Instance.new("Frame")
		col.BorderSizePixel = 0
		col.BackgroundColor3 = (i % 2 == 0) and RGB(228, 166, 114) or RGB(184, 111, 80)
		local hgt = 0.08 + 0.05 * (math.sin(i * 0.5) + 1) / 2
		col.AnchorPoint = Vector2.new(0, 1)
		col.Position = UDim2.fromScale(i / 40, 1)
		col.Size = UDim2.new(1 / 40, 1, hgt, 0)
		col.Parent = back
	end

	local function label(text, y, h, color, face)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.new(0.9, 0, h, 0)
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeColor3 = INK
		l.TextStrokeTransparency = 0
		if face and TITLE_FACE then
			l.FontFace = TITLE_FACE
		else
			l.Font = BODY_FONT
		end
		l.Parent = back
		return l
	end
	-- the title, with a hard drop shadow
	local shadow = label(R.Title or "DEFEAT THE BOSS", 0.34, 0.13, RGB(162, 38, 51), true)
	shadow.Position = UDim2.new(0.5, 6, 0.34, 6)
	local main = label(R.Title or "DEFEAT THE BOSS", 0.34, 0.13, RGB(254, 231, 97), true)
	label(R.Subtitle or "TO GROW", 0.47, 0.07, RGB(44, 232, 245), true)
	local press = label("- PRESS ANY KEY -", 0.68, 0.05, RGB(255, 255, 255), false)

	local t0 = os.clock()
	local closing = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		press.TextTransparency = (math.floor(t * 2.5) % 2 == 0) and 0 or 1
		main.Position = UDim2.fromScale(0.5, 0.34 + math.floor(math.sin(t * 3) * 2) / 200) -- a 2-frame bob
		for _, s in ipairs(stars) do
			s.part.BackgroundTransparency = (math.sin(t * s.rate + s.phase) > 0.2) and 0 or 0.8
		end
	end)

	-- the pixel-dissolve wipe out of it
	local function close()
		if closing then
			return
		end
		closing = true
		local cols, rows = 16, 9
		local blocks = {}
		for x = 0, cols - 1 do
			for y = 0, rows - 1 do
				local b = Instance.new("Frame")
				b.BorderSizePixel = 0
				b.BackgroundColor3 = RGB(24, 20, 37)
				b.Position = UDim2.fromScale(x / cols, y / rows)
				b.Size = UDim2.new(1 / cols, 1, 1 / rows, 1)
				b.ZIndex = 5
				b.Parent = title
				blocks[#blocks + 1] = b
			end
		end
		back.Visible = false
		for i = #blocks, 2, -1 do
			local j = math.random(i)
			blocks[i], blocks[j] = blocks[j], blocks[i]
		end
		for i, b in ipairs(blocks) do
			task.delay(i / #blocks * 0.6, function()
				b:Destroy()
			end)
		end
		task.delay(0.7, function()
			conn:Disconnect()
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
	task.delay(8, close) -- (and it gets out of the way by itself)
end
