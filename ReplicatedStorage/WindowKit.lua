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
}
local C = K.COLORS
K.TITLE_FONT = Enum.Font.Arcade -- (Press Start 2P)
K.FONT = Enum.Font.FredokaOne

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

return K
