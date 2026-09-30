--[[
	WindowKit  (ModuleScript, parent: ReplicatedStorage, name: "WindowKit")

	THE WINDOW LOOK: menus drawn like an old computer's windows, made loud -
	lavender windows with thick dark outlines and hard drop shadows, bright
	title bars (magenta, violet, teal, orange) with their three little square
	buttons, chunky buttons that press in, striped progress bars, and a
	purple grid behind it all. Titles and buttons are in the pixel font; the
	rest stays in the game's round font, so it reads on a phone.

	  WindowKit.COLORS                      the palette
	  WindowKit.backdrop(parent, props)     the purple grid over the world (a
	                                        TextButton: clicking it can close)
	  WindowKit.window(parent, opts)        a window; returns { frame, body,
	                                        bar, title, close, top }
	  WindowKit.panel(parent, props, color) a white box with an outline (a
	                                        coloured strip on top if `color`)
	  WindowKit.button(parent, label, color, props)
	                                        a chunky button with a shadow that
	                                        follows it (and presses in)
	  WindowKit.progress(parent, props)     a striped progress bar; :set(0..1)
	  WindowKit.label(parent, props)        text in the window style (dark ink)

	THE NEW GUI's pieces (the lobby's buttons and the see-through menus -
	Previews/gui_windows_sketch.html): the same ink outlines and hard shadows,
	in the game's brighter colours:
	  WindowKit.icon(parent, key, props)    one of the menus' pixel icons
	                                        (Tools/Icons/out/ui, uploaded as
	                                        AssetIds.Icons.UI_<key>) - or a
	                                        stand-in picture until it is
	  WindowKit.pic(parent, opts)           a big square picture button (icon,
	                                        word under it, badge); returns
	                                        button, api { badge(v), label }
	  WindowKit.card(parent, props, color)  a floating card (hard shadow);
	                                        returns face, holder
	  WindowKit.shine(frame, strength)      light stripes across a coloured face
	  WindowKit.chip(parent, text, color, props)  a little pixel-font tag
	  WindowKit.badge(parent) / setBadge(b, v)    the red count in a corner
	  WindowKit.big(parent, props)          big white words with an ink edge
	  WindowKit.x(parent, props)            the red close button
	  WindowKit.tab(parent, key, label, props)    a menu's side tab; :on(bool)
	  WindowKit.meter(parent, props)        a dark bar with words; :set(frac, text)
	  WindowKit.coin / WindowKit.token(parent, size, props)   the money pictures

	A window's `frame` is see-through and holds its shadow (ZIndex = base),
	its body (base + 1) and title bar (base + 2 and 3): put its contents in
	`frame` with a ZIndex above base + 1, below `top` (the title bar's
	height). Screens using it so far: the Arcade's menu (ArcadeClient).
]]

local K = {}

local RGB = Color3.fromRGB
K.COLORS = {
	Ink = RGB(24, 20, 37), -- outlines, shadows, words
	Body = RGB(232, 222, 255), -- a window
	Panel = RGB(252, 250, 255), -- a box inside one
	Face = RGB(220, 204, 255), -- a plain button
	Sunken = RGB(214, 200, 248), -- a status bar, a track
	Grid = RGB(116, 40, 232), -- the backdrop
	GridLine = RGB(152, 94, 255),
	Magenta = RGB(247, 58, 207),
	Violet = RGB(108, 92, 255),
	Teal = RGB(20, 165, 155),
	Orange = RGB(255, 164, 0),
	Muted = RGB(112, 100, 146), -- quiet words
	Off = RGB(176, 166, 204), -- a button you can't press yet
	White = RGB(255, 255, 255),
	-- the new GUI's colours. A window's colour says what it is: Blue quests,
	-- Teal the bag, Pink the Arcade and the Spire, Gold the shop, Red a boss or
	-- a warning, Green rewards, Purple the Index
	Pink = RGB(255, 63, 164),
	Blue = RGB(79, 107, 255),
	Gold = RGB(255, 182, 46),
	Green = RGB(67, 194, 79),
	Red = RGB(229, 57, 74),
	Yellow = RGB(254, 231, 97),
	Purple = RGB(141, 75, 255),
	Paper = RGB(239, 233, 255), -- a card
	Slate = RGB(93, 86, 128), -- a quiet button (settings)
	Night = RGB(58, 47, 99), -- a tab that isn't picked
	Well = RGB(42, 31, 63), -- inside a bar
}
local C = K.COLORS
K.TITLE_FONT = Enum.Font.Arcade -- (Press Start 2P)
K.FONT = Enum.Font.FredokaOne

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end
local function outline(parent, color, thickness)
	return new("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 3,
		LineJoinMode = Enum.LineJoinMode.Miter,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end
K.outline = outline

-- text in the window style: dark ink, no outline (on a coloured strip, pass
-- TextColor3 = white and TextStrokeTransparency = 0)
function K.label(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = K.FONT,
		TextColor3 = C.Ink,
		TextScaled = true,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = 1,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- the purple grid behind a window (it covers its parent; lines every 64)
function K.backdrop(parent, props)
	local b = new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Grid,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local z = b.ZIndex
	for i = 0, 40 do
		new("Frame", { Name = "Line", BackgroundColor3 = C.GridLine, BackgroundTransparency = 0.35, BorderSizePixel = 0, Position = UDim2.fromOffset(i * 64, 0), Size = UDim2.new(0, 2, 1, 0), ZIndex = z }, b)
		if i <= 24 then
			new("Frame", { Name = "Line", BackgroundColor3 = C.GridLine, BackgroundTransparency = 0.35, BorderSizePixel = 0, Position = UDim2.fromOffset(0, i * 64), Size = UDim2.new(1, 0, 0, 2), ZIndex = z }, b)
		end
	end
	return b
end

-- a small square button in a title bar (its glyph drawn in lines)
local function barButton(parent, glyph, x, z, size)
	local b = new("TextButton", {
		Name = glyph == "X" and "Close" or (glyph == "_" and "Minimise" or "Maximise"),
		Text = glyph == "X" and "X" or "",
		Font = K.TITLE_FONT,
		TextColor3 = C.Ink,
		TextScaled = false,
		TextSize = math.floor(size * 0.55),
		AutoButtonColor = false,
		BackgroundColor3 = C.Body,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, x, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z,
	}, parent)
	outline(b, C.Ink, 2.5)
	if glyph == "_" then
		new("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(0.5, 0, 0, 3), ZIndex = z + 1 }, b)
	elseif glyph == "[]" then
		local box = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), ZIndex = z + 1 }, b)
		outline(box, C.Ink, 2)
		new("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), ZIndex = z + 1 }, box)
	end
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = C.White
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = C.Body
	end)
	return b
end

-- A window. opts: Name, Size, Position, AnchorPoint, ZIndex (its base: 1),
-- Title, Color (the title bar's), BarHeight (40), Shadow (8, in pixels),
-- Icon (a GuiObject: the little picture at the left of the title), Buttons
-- (false: no little buttons on the title bar)
function K.window(parent, opts)
	local z = opts.ZIndex or 1
	local barH = opts.BarHeight or 40
	local sh = opts.Shadow or 8
	local frame = new("Frame", {
		Name = opts.Name or "Window",
		BackgroundTransparency = 1,
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.new(),
		ZIndex = z,
		Visible = opts.Visible ~= false,
		Active = true,
	}, parent)
	new("Frame", { Name = "Shadow", BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.fromOffset(sh, sh), Size = UDim2.fromScale(1, 1), ZIndex = z }, frame)
	local body = new("Frame", { Name = "Body", BackgroundColor3 = C.Body, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z + 1 }, frame)
	outline(body, C.Ink, 3)
	local bar = new("Frame", { Name = "TitleBar", BackgroundColor3 = opts.Color or C.Magenta, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, barH), ZIndex = z + 2 }, frame)
	new("Frame", { Name = "Rule", BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, barH), Size = UDim2.new(1, 0, 0, 3), ZIndex = z + 2 }, frame)
	local title = K.label(frame, {
		Name = "Title",
		Text = opts.Title or "",
		Font = K.TITLE_FONT,
		TextColor3 = C.White,
		TextStrokeTransparency = 0,
		TextScaled = false,
		TextSize = opts.TitleSize or math.floor(barH * 0.45),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(opts.Icon and barH + 6 or 16, 0),
		Size = UDim2.new(1, -3 * (barH - 10) - 40 - (opts.Icon and barH or 0), 0, barH),
		ZIndex = z + 3,
	})
	if opts.Icon then -- (the program's little picture, at the left of the title)
		local icon = opts.Icon
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)
		icon.Size = UDim2.fromOffset(barH - 12, barH - 12)
		icon.ZIndex = z + 3
		icon.Parent = bar
	end
	-- the three little buttons (the last one closes), unless Buttons = false
	local close = nil
	if opts.Buttons ~= false then
		local size = barH - 12
		close = barButton(bar, "X", -7, z + 3, size)
		barButton(bar, "_", -7 - (size + 6), z + 3, size)
		barButton(bar, "[]", -7 - 2 * (size + 6), z + 3, size)
	else
		title.Size = UDim2.new(1, -32 - (opts.Icon and barH or 0), 0, barH)
	end
	return { frame = frame, body = body, bar = bar, title = title, close = close, top = barH + 3 }
end

-- a white box with an outline (and a coloured strip on top, `color`)
function K.panel(parent, props, color, stripHeight)
	local p = new("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	outline(p, C.Ink, 3)
	if color then
		local strip = new("Frame", { Name = "Strip", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, stripHeight or 36), ZIndex = p.ZIndex + 1 }, p)
		new("Frame", { Name = "Rule", BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = p.ZIndex + 1 }, strip)
	end
	return p
end

-- A chunky button: the face (a TextButton, returned) and a hard shadow just
-- behind it that follows it about (shown, moved, resized with it). It
-- presses in when clicked.
function K.button(parent, label, color, props)
	local b = new("TextButton", {
		BackgroundColor3 = color or C.Face,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = K.TITLE_FONT,
		Text = label,
		TextColor3 = color and C.White or C.Ink,
		TextScaled = true,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = color and 0 or 1,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	outline(b, C.Ink, 3)
	new("UIPadding", { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.18, 0), PaddingLeft = UDim.new(0.05, 0), PaddingRight = UDim.new(0.05, 0) }, b)
	local depth = 5
	local shadow = new("Frame", { Name = (b.Name ~= "TextButton" and b.Name or "Button") .. "Shadow", BackgroundColor3 = C.Ink, BorderSizePixel = 0, ZIndex = math.max(1, b.ZIndex - 1) }, parent)
	local pressed = 0
	local function follow()
		shadow.AnchorPoint = b.AnchorPoint or Vector2.new()
		shadow.Size = b.Size or UDim2.new()
		shadow.Position = (b.Position or UDim2.new()) + UDim2.fromOffset(depth - pressed, depth - pressed)
		shadow.Visible = b.Visible
		shadow.ZIndex = math.max(1, b.ZIndex - 1)
	end
	follow()
	for _, prop in ipairs({ "Visible", "Position", "Size", "AnchorPoint", "ZIndex" }) do
		b:GetPropertyChangedSignal(prop):Connect(follow)
	end
	b.AncestryChanged:Connect(function()
		if not b.Parent then
			shadow:Destroy()
		end
	end)
	-- (pressing in: the face moves onto its shadow, then back)
	b.MouseButton1Down:Connect(function()
		if pressed == 0 then
			pressed = 3
			b.Position = (b.Position or UDim2.new()) + UDim2.fromOffset(3, 3)
		end
	end)
	local function release()
		if pressed ~= 0 then
			local p = pressed
			pressed = 0
			b.Position = (b.Position or UDim2.new()) - UDim2.fromOffset(p, p)
		end
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	return b, shadow
end

-- A striped progress bar (the stripes in `Color`, magenta unless said):
-- bar:set(0 to 1)
function K.progress(parent, props)
	local color = props and props.Color or C.Magenta
	local track = new("Frame", { Name = "Progress", BackgroundColor3 = C.Panel, BorderSizePixel = 0, ClipsDescendants = true }, parent)
	for k, v in pairs(props or {}) do
		if k ~= "Color" then
			track[k] = v
		end
	end
	outline(track, C.Ink, 2.5)
	local fill = new("Frame", { Name = "Fill", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(0, 0, 1, -6), ClipsDescendants = true, ZIndex = track.ZIndex + 1 }, track)
	-- (the stripes: slanted blocks with gaps, like an old loading bar)
	for i = 0, 60 do
		new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(i * 14, 0), Size = UDim2.new(0, 9, 1, 0), ZIndex = track.ZIndex + 1 }, fill)
	end
	local bar = { frame = track, fill = fill, value = 0 }
	function bar.set(_, v)
		bar.value = math.clamp(tonumber(v) or 0, 0, 1)
		fill.Size = UDim2.new(bar.value, -6 * bar.value, 1, -6)
	end
	return bar
end

----------------------------------------------------------------------
-- THE NEW GUI's PIECES
----------------------------------------------------------------------
local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures")) -- (the uploaded pictures, fast)

-- a stand-in for each pixel icon until it's uploaded (Roblox draws emoji in colour)
K.STAND_IN = {
	Shop = "🛒", Bag = "🎒", Arcade = "🕹️", Index = "📖", Gift = "🎁", Rewards = "🏆",
	Settings = "⚙️", Featured = "⭐", Tickets = "🎟️", Tokens = "💠", Daily = "📅", Passes = "🎫",
	Looks = "👑", Weapons = "⚔️", Titles = "🏷️", Bosses = "💀", Goals = "🎯", Revive = "❤️",
	Spin = "🎰", BossRush = "⚡", Luck = "🍀", Playtime = "⏱️", Friends = "👥", Spire = "🗼",
	Lock = "🔒", Codes = "🔑", Updates = "📰", Flask = "🧪", Bolt = "⚡", Stats = "📊", Gear = "🧰",
}

-- the uploaded picture for icon `key` (ReplicatedStorage/Pictures), or nil
function K.iconImage(key)
	local icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	local id = icons and icons["UI_" .. tostring(key)]
	return id and Pictures.url(id) or nil
end

-- one of the menus' pixel icons (an ImageLabel), or its stand-in (a TextLabel)
function K.icon(parent, key, props)
	local image = K.iconImage(key)
	local i
	if image then
		i = new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ResampleMode = Enum.ResamplerMode.Pixelated,
		}, parent)
		Pictures.show(i, AssetIds.Icons["UI_" .. tostring(key)]) -- (swaps to the fast picture when it's known)
	else
		i = new("TextLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Font = K.FONT,
			Text = K.STAND_IN[key] or "?",
			TextColor3 = C.White,
			TextScaled = true,
		}, parent)
	end
	for k, v in pairs(props or {}) do
		i[k] = v
	end
	return i
end

-- light stripes across a coloured face (like the sketch's rays): four
-- hard-edged bands (a gradient takes at most 20 points)
function K.shine(frame, strength)
	local a = 1 - (strength or 0.2)
	local out = { NumberSequenceKeypoint.new(0, 1) }
	for j = 0, 3 do
		local s0, e0 = (j + 0.25) / 4, (j + 0.75) / 4
		table.insert(out, NumberSequenceKeypoint.new(s0, 1))
		table.insert(out, NumberSequenceKeypoint.new(s0 + 0.002, a))
		table.insert(out, NumberSequenceKeypoint.new(e0, a))
		table.insert(out, NumberSequenceKeypoint.new(e0 + 0.002, 1))
	end
	table.insert(out, NumberSequenceKeypoint.new(1, 1))
	local f = new("Frame", {
		Name = "Shine",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = frame.ZIndex or 1,
	}, frame)
	new("UIGradient", { Rotation = -35, Transparency = NumberSequence.new(out) }, f)
	return f
end

-- the red count in a button's corner (hidden until setBadge gives it something)
function K.badge(parent)
	local b = new("TextLabel", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(34, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Red,
		Font = K.FONT,
		Text = "",
		TextColor3 = C.White,
		TextSize = 22,
		TextStrokeTransparency = 0.4,
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 6,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	-- (a round ring: the sharp-cornered edge drew a black square round the circle)
	outline(b, C.Ink, 2.5).LineJoinMode = Enum.LineJoinMode.Round
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, b)
	return b
end
function K.setBadge(b, v)
	if v == nil or v == false or v == 0 or v == "" then
		b.Visible = false
	else
		b.Text = tostring(v)
		b.Visible = true
	end
end

-- big white words with an ink edge (titles, prices, counts)
function K.big(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = K.FONT,
		TextColor3 = C.White,
		TextScaled = true,
		TextStrokeTransparency = 1,
	}, parent)
	for k, v in pairs(props or {}) do
		if k ~= "Edge" then
			l[k] = v
		end
	end
	local st = new("UIStroke", { Color = C.Ink, Thickness = props and props.Edge or 3, LineJoinMode = Enum.LineJoinMode.Round }, l)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return l
end

-- a floating card: a face (returned, put things in it) with an ink outline
-- and a hard shadow, in a see-through holder (the one layouts arrange)
function K.card(parent, props, color)
	local holder = new("Frame", { Name = "Card", BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do
		holder[k] = v
	end
	local z = holder.ZIndex or 1
	new("Frame", { Name = "Shadow", BackgroundColor3 = C.Ink, BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromScale(1, 1), ZIndex = z }, holder)
	local face = new("Frame", { Name = "Face", BackgroundColor3 = color or C.Paper, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = z + 1 }, holder)
	outline(face, C.Ink, 3)
	return face, holder
end

-- a little tag in the pixel font ("2X XP", "SOON", "NEW"); change its words
-- with K.chipText (it grows to fit them)
local function chipWidth(text)
	return utf8.len(tostring(text)) * 13 + 22
end
function K.chip(parent, text, color, props)
	local c = new("TextLabel", {
		Name = "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(chipWidth(text), 28),
		BackgroundColor3 = color or C.Pink,
		BorderSizePixel = 0,
		Font = K.TITLE_FONT,
		Text = text,
		TextColor3 = C.White,
		TextSize = 14,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = 0,
	}, parent)
	outline(c, C.Ink, 2.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, c)
	for k, v in pairs(props or {}) do
		c[k] = v
	end
	return c
end
function K.chipText(c, text)
	if c.Text ~= text then
		c.Text = text
		c.Size = UDim2.fromOffset(chipWidth(text), c.Size.Y.Offset)
	end
end

-- the red close button (a TextButton with a hard shadow)
function K.x(parent, props)
	local b = K.button(parent, "", C.Red, props)
	b.Name = "Close"
	-- the cross: two white bars (the fonts have no "✕" - it came out blank)
	for i, turn in ipairs({ 45, -45 }) do
		local bar = new("Frame", {
			Name = "Cross" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.78, 0, 0, 9),
			Rotation = turn,
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			ZIndex = b.ZIndex + 1,
		}, b)
		outline(bar, C.Ink, 2)
	end
	b:GetPropertyChangedSignal("ZIndex"):Connect(function()
		for _, c in ipairs(b:GetChildren()) do
			if c:IsA("Frame") and string.sub(c.Name, 1, 5) == "Cross" then
				c.ZIndex = b.ZIndex + 1
			end
		end
	end)
	return b
end

-- A big square picture button: a coloured face with light stripes, the icon,
-- the word underneath, a hard shadow and a badge. opts: Name, Color, Icon,
-- Label, Size (pixels), Position, AnchorPoint, LayoutOrder, ZIndex.
-- Returns the button and { badge = fn(value), label, icon, face }.
function K.pic(parent, opts)
	local size = opts.Size or 108
	local z = opts.ZIndex or 2
	local holder = new("Frame", {
		Name = opts.Name or "Pic",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.new(),
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = z,
	}, parent)
	new("Frame", { Name = "Shadow", BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), ZIndex = z }, holder)
	local b = new("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = opts.Color or C.Pink,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, holder)
	outline(b, C.Ink, 3)
	local scale = new("UIScale", {}, b)
	K.shine(b, 0.22)
	local icon = K.icon(b, opts.Icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, opts.Label and 0.42 or 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = z + 2,
	})
	local label = nil
	if opts.Label then
		label = K.big(b, {
			Name = "Label",
			Text = opts.Label,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.new(1, 8, 0.3, 0),
			ZIndex = z + 3,
		})
	end
	local badge = K.badge(holder)
	badge.ZIndex = z + 6
	b.MouseEnter:Connect(function()
		scale.Scale = 1.06
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
		b.Position = UDim2.new()
	end)
	b.MouseButton1Down:Connect(function()
		b.Position = UDim2.fromOffset(3, 3)
	end)
	b.MouseButton1Up:Connect(function()
		b.Position = UDim2.new()
	end)
	return b, {
		holder = holder,
		face = b,
		icon = icon,
		label = label,
		badge = function(v)
			K.setBadge(badge, v)
		end,
	}
end

-- a menu's side tab: dark, gold when it's the one picked. Returns the
-- button; button:SetAttribute("On", true/false) is kept by tab.on(b, on).
function K.tab(parent, key, label, props)
	local b = new("TextButton", {
		Name = "Tab_" .. key,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Night,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(96, 96),
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	outline(b, C.Ink, 3)
	local z = b.ZIndex or 1
	K.icon(b, key, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.56, 0.56), ZIndex = z + 1 })
	K.big(b, { Name = "Label", Text = label, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -6, 0, 22), ZIndex = z + 2, Edge = 2 })
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), Visible = false, ZIndex = z + 1 }, b)
	outline(ring, C.White, 3)
	return b
end
function K.tabOn(b, on)
	b.BackgroundColor3 = on and C.Gold or C.Night
	local ring = b:FindFirstChild("Ring")
	if ring then
		ring.Visible = on
	end
	b:SetAttribute("On", on)
end

-- a dark bar with words on it: m:set(0..1, "3 / 5")
function K.meter(parent, props)
	local color = props and props.Color or C.Blue
	local track = new("Frame", { Name = "Meter", BackgroundColor3 = C.Well, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do
		if k ~= "Color" then
			track[k] = v
		end
	end
	outline(track, C.Ink, 2.5)
	local z = track.ZIndex or 1
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = z + 1 }, track)
	local words = new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = K.TITLE_FONT,
		Text = "",
		TextColor3 = C.White,
		TextSize = 14,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = 0,
		ZIndex = z + 2,
	}, track)
	local m = { frame = track, fill = fill, text = words }
	function m.set(_, frac, text)
		fill.Size = UDim2.fromScale(math.clamp(tonumber(frac) or 0, 0, 1), 1)
		if text then
			words.Text = text
		end
	end
	return m
end

-- the money pictures: the living coin / token once they're uploaded
-- (ReplicatedStorage/MoneyIcons), a drawn one until then
local function money(parent, kind, size, props)
	local MoneyIcons = nil
	pcall(function()
		MoneyIcons = require(ReplicatedStorage:WaitForChild("MoneyIcons", 2))
	end)
	local made = MoneyIcons and MoneyIcons.make(parent, kind, size, props)
	if made then
		return made
	end
	local rim = new("Frame", {
		Name = kind,
		BackgroundColor3 = kind == "Coin" and C.Gold or C.Pink,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	for k, v in pairs(props or {}) do
		rim[k] = v
	end
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, rim)
	outline(rim, C.Ink, math.max(2, size / 16)).LineJoinMode = Enum.LineJoinMode.Round -- (round, like the badges)
	if kind == "Coin" then
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new(RGB(255, 246, 168), RGB(184, 107, 18)) }, rim)
	else
		new("UIGradient", { Rotation = 30, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RGB(255, 95, 210)),
			ColorSequenceKeypoint.new(0.35, RGB(79, 107, 255)),
			ColorSequenceKeypoint.new(0.7, RGB(25, 179, 166)),
			ColorSequenceKeypoint.new(1, RGB(254, 231, 97)),
		}) }, rim)
		new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = K.FONT, Text = "★", TextColor3 = C.White, TextScaled = true, TextStrokeTransparency = 0.3, ZIndex = (rim.ZIndex or 1) + 1 }, rim)
	end
	return rim
end
function K.coin(parent, size, props)
	return money(parent, "Coin", size, props)
end
function K.token(parent, size, props)
	return money(parent, "Token", size, props)
end

return K
