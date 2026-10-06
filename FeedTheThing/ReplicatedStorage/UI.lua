--[[
	UI  (ModuleScript, parent: ReplicatedStorage, name: "UI")

	Small helpers the client scripts share: making frames, labels and big
	friendly buttons, 3D icons in ViewportFrames, sounds by name, and a tiny
	message bus so the client scripts can talk to each other.

	Sounds come from Config.Sounds (uploaded ids). A Sound in SoundService
	with the same name wins, so you can try other sounds without code.
]]

local UI = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SoundSheet = require(ReplicatedStorage:WaitForChild("SoundSheet"))

UI.Font = Config.Font
-- The stud look (like the map): studded toy-brick panels and buttons,
-- saturated colours, one corner size, thick black outlines.
UI.Colors = {
	Panel = Color3.fromRGB(232, 160, 85), -- panel bodies: tan brick, like the map's walls
	PanelLight = Color3.fromRGB(250, 196, 120), -- rows and cards inside panels
	Well = Color3.fromRGB(160, 95, 45), -- sunk-in bits: icon boxes, level pills, "not yet" buttons
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(255, 240, 215),
	Good = Color3.fromRGB(80, 215, 60),
	Bad = Color3.fromRGB(235, 60, 60),
	Gold = Color3.fromRGB(255, 205, 40),
	Accent = Color3.fromRGB(190, 100, 255),
	Stroke = Color3.fromRGB(18, 14, 26), -- the black outline on everything
	Green = Color3.fromRGB(70, 210, 50),
	Cyan = Color3.fromRGB(30, 190, 250),
	Orange = Color3.fromRGB(255, 150, 30),
	Red = Color3.fromRGB(235, 55, 55),
	Grey = Color3.fromRGB(130, 130, 145),
}
-- big italic numbers (coins, timers), like the genre's hits
UI.NumberFont = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

----------------------------------------------------------------------
-- Making things
----------------------------------------------------------------------
function UI.new(className, props, parent)
	local obj = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			(obj :: any)[key] = value
		end
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

function UI.corner(parent, radius)
	return UI.new("UICorner", { CornerRadius = radius or UDim.new(0, 14) }, parent)
end

function UI.stroke(parent, thickness, color, transparency)
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or UI.Colors.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- Text with a dark outline so it reads on any background
function UI.label(parent, props)
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, 30),
	}, parent)
	UI.new("UITextSizeConstraint", { MaxTextSize = 48, MinTextSize = 12 }, label)
	UI.new("UIStroke", { Thickness = 2.5, Color = UI.Colors.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	if props then
		for key, value in pairs(props) do
			(label :: any)[key] = value
		end
	end
	return label
end

-- The chunky look: rounded, lit from the top, thick black outline
function UI.chunky(obj, color, radius, outline)
	if color then
		obj.BackgroundColor3 = color
	end
	UI.corner(obj, radius or UDim.new(0, 12))
	UI.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
	}, obj)
	UI.stroke(obj, outline or 3.5)
	return obj
end

-- The studs: one stud image (GUI/studs.png, see Config.GuiImages) tiled over
-- a frame, under everything else in it. Only the big panels get them, and
-- faintly: simple beats busy. Not uploaded yet: plain frames.
UI.StudSize = 26
local function studsImage()
	local images = Config.GuiImages or {}
	if (images.StudsImage or 0) > 0 then
		return "rbxassetid://" .. images.StudsImage
	elseif (images.StudsDecal or 0) > 0 then
		return "rbxthumb://type=Asset&id=" .. images.StudsDecal .. "&w=150&h=150"
	end
	return nil
end
function UI.studs(frame, size, transparency)
	local image = studsImage()
	if not image or frame:FindFirstChild("Studs") or frame:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return nil
	end
	-- cover the whole frame, padding included
	local pad = frame:FindFirstChildOfClass("UIPadding")
	local l, r, t, b = 0, 0, 0, 0
	if pad then
		l, r, t, b = pad.PaddingLeft.Offset, pad.PaddingRight.Offset, pad.PaddingTop.Offset, pad.PaddingBottom.Offset
	end
	local studs = UI.new("ImageLabel", {
		Name = "Studs", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(size or UI.StudSize, size or UI.StudSize),
		Position = UDim2.fromOffset(-l, -t), Size = UDim2.new(1, l + r, 1, t + b), ZIndex = 0,
		ImageTransparency = transparency or 0.5,
	}, frame)
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		UI.corner(studs, corner.CornerRadius)
	end
	return studs
end

-- Big italic numbers with a thick outline
function UI.number(parent, props)
	local label = UI.label(parent, props)
	label.FontFace = UI.NumberFont
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end
	return label
end

-- A red "!" in the corner of a button, for "something new here"
function UI.badge(parent)
	local badge = UI.new("Frame", {
		Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(30, 30), BackgroundColor3 = UI.Colors.Red, Visible = false, ZIndex = 8,
	}, parent)
	UI.corner(badge, UDim.new(1, 0))
	UI.stroke(badge, 3, Color3.fromRGB(255, 255, 255))
	UI.label(badge, { Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 9 })
	return badge
end

----------------------------------------------------------------------
-- Drawn icons (plain frames, so they're crisp at any size and need no
-- uploaded images): cart, sprout, book, egg, upgrade, coin, snow, moon, sun,
-- magnet, target, twins, house, clover, lock, x
----------------------------------------------------------------------
local INK = Color3.fromRGB(18, 14, 26)
local function shape(parent, props, stroke, radius)
	props.BorderSizePixel = 0
	local f = UI.new("Frame", props, parent)
	if radius then
		UI.corner(f, radius)
	end
	if stroke then
		UI.new("UIStroke", { Thickness = stroke, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	end
	return f
end
local ROUND = UDim.new(1, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local function at(x, y, w, h, rotation, color)
	return {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		Rotation = rotation or 0, BackgroundColor3 = color or WHITE,
	}
end

local ICONS = {}
ICONS.cart = function(c)
	shape(c, at(0.24, 0.27, 0.3, 0.09, 18), 2, ROUND)
	local basket = shape(c, at(0.56, 0.47, 0.6, 0.38), 2.5, UDim.new(0.18, 0))
	for k = 1, 2 do
		shape(basket, at(k / 3, 0.5, 0.07, 0.6, 0, INK), nil, ROUND)
	end
	shape(c, at(0.38, 0.8, 0.17, 0.17, 0, INK), nil, ROUND)
	shape(c, at(0.74, 0.8, 0.17, 0.17, 0, INK), nil, ROUND)
end
ICONS.sprout = function(c)
	-- a seedling in a flower pot (the seed shop)
	shape(c, at(0.5, 0.42, 0.08, 0.36, 0, Color3.fromRGB(90, 200, 60)), 2, ROUND)
	shape(c, at(0.33, 0.3, 0.32, 0.18, -30, Color3.fromRGB(120, 230, 80)), 2.5, ROUND)
	shape(c, at(0.67, 0.24, 0.34, 0.19, 30, Color3.fromRGB(120, 230, 80)), 2.5, ROUND)
	local pot = shape(c, at(0.5, 0.74, 0.56, 0.36, 0, Color3.fromRGB(225, 120, 60)), 2.5, UDim.new(0.18, 0))
	shape(pot, at(0.5, 0.12, 1.12, 0.3, 0, Color3.fromRGB(240, 145, 80)), 2.5, UDim.new(0.3, 0))
end
ICONS.book = function(c)
	for _, side in ipairs({ -1, 1 }) do
		local page = shape(c, at(0.5 + side * 0.19, 0.5, 0.36, 0.62, side * 7), 2.5, UDim.new(0.12, 0))
		for k = 1, 3 do
			shape(page, at(0.5, 0.18 + k * 0.18, 0.6, 0.06, 0, Color3.fromRGB(120, 140, 170)), nil, ROUND)
		end
	end
	shape(c, at(0.5, 0.52, 0.06, 0.66, 0, INK), nil, ROUND)
end
ICONS.egg = function(c)
	local egg = shape(c, at(0.5, 0.52, 0.56, 0.74, 0, Color3.fromRGB(255, 246, 225)), 2.5, UDim.new(0.5, 0))
	shape(egg, at(0.35, 0.35, 0.22, 0.17, 0, Color3.fromRGB(255, 120, 120)), nil, ROUND)
	shape(egg, at(0.65, 0.62, 0.26, 0.19, 0, Color3.fromRGB(120, 200, 255)), nil, ROUND)
	shape(egg, at(0.35, 0.78, 0.16, 0.12, 0, Color3.fromRGB(255, 205, 60)), nil, ROUND)
end
ICONS.upgrade = function(c)
	for _, y in ipairs({ 0.36, 0.64 }) do
		shape(c, at(0.36, y, 0.42, 0.17, -45, Color3.fromRGB(120, 255, 90)), 2.5, ROUND)
		shape(c, at(0.64, y, 0.42, 0.17, 45, Color3.fromRGB(120, 255, 90)), 2.5, ROUND)
	end
end
ICONS.coin = function(c)
	local coin = shape(c, at(0.5, 0.5, 0.86, 0.86, 0, Color3.fromRGB(255, 200, 40)), 2.5, ROUND)
	shape(coin, at(0.5, 0.5, 0.6, 0.6, 0, Color3.fromRGB(255, 225, 110)), nil, ROUND)
	shape(coin, at(0.5, 0.5, 0.12, 0.38, 0, Color3.fromRGB(215, 150, 20)), nil, ROUND)
end
ICONS.snow = function(c)
	for k = 0, 2 do
		shape(c, at(0.5, 0.5, 0.86, 0.13, k * 60, Color3.fromRGB(220, 240, 255)), 2, ROUND)
	end
	shape(c, at(0.5, 0.5, 0.22, 0.22, 0, Color3.fromRGB(220, 240, 255)), 2, ROUND)
end
ICONS.moon = function(c)
	local moon = shape(c, at(0.5, 0.5, 0.78, 0.78, 0, Color3.fromRGB(255, 245, 190)), 2.5, ROUND)
	shape(moon, at(0.35, 0.4, 0.22, 0.22, 0, Color3.fromRGB(225, 210, 150)), nil, ROUND)
	shape(moon, at(0.66, 0.66, 0.16, 0.16, 0, Color3.fromRGB(225, 210, 150)), nil, ROUND)
end
ICONS.sun = function(c)
	for k = 0, 3 do
		shape(c, at(0.5, 0.5, 0.95, 0.11, k * 45, Color3.fromRGB(255, 170, 30)), nil, ROUND)
	end
	shape(c, at(0.5, 0.5, 0.56, 0.56, 0, Color3.fromRGB(255, 215, 50)), 2.5, ROUND)
end
ICONS.magnet = function(c)
	-- a horseshoe magnet: red U, silver tips
	local red = Color3.fromRGB(235, 60, 60)
	shape(c, at(0.5, 0.58, 0.72, 0.62, 0, red), 2.5, UDim.new(0.5, 0))
	shape(c, at(0.5, 0.48, 0.3, 0.6, 0, UI.Colors.Well), nil, UDim.new(0.5, 0)) -- the gap (the icon box's colour)
	for _, x in ipairs({ 0.25, 0.75 }) do
		shape(c, at(x, 0.36, 0.22, 0.34, 0, red), 2.5, UDim.new(0.15, 0))
		shape(c, at(x, 0.16, 0.22, 0.16, 0, Color3.fromRGB(225, 230, 240)), 2.5, UDim.new(0.15, 0))
	end
end
ICONS.target = function(c)
	shape(c, at(0.5, 0.5, 0.9, 0.9, 0, Color3.fromRGB(235, 60, 60)), 2.5, ROUND)
	shape(c, at(0.5, 0.5, 0.64, 0.64, 0, WHITE), nil, ROUND)
	shape(c, at(0.5, 0.5, 0.4, 0.4, 0, Color3.fromRGB(235, 60, 60)), nil, ROUND)
	shape(c, at(0.5, 0.5, 0.18, 0.18, 0, Color3.fromRGB(255, 205, 40)), 2, ROUND)
end
ICONS.twins = function(c)
	-- two tomatoes
	for _, p in ipairs({ { 0.34, 0.58, 0.52 }, { 0.64, 0.52, 0.56 } }) do
		local tomato = shape(c, at(p[1], p[2], p[3], p[3], 0, Color3.fromRGB(235, 60, 55)), 2.5, ROUND)
		shape(tomato, at(0.32, 0.32, 0.22, 0.16, -30, Color3.fromRGB(255, 160, 150)), nil, ROUND)
		shape(c, at(p[1], p[2] - p[3] * 0.48, p[3] * 0.5, p[3] * 0.16, 0, Color3.fromRGB(90, 200, 60)), 2, ROUND)
	end
end
ICONS.house = function(c)
	shape(c, at(0.5, 0.36, 0.58, 0.58, 45, Color3.fromRGB(235, 70, 80)), 2.5, UDim.new(0.12, 0)) -- roof
	local walls = shape(c, at(0.5, 0.66, 0.62, 0.46, 0, Color3.fromRGB(255, 225, 160)), 2.5, UDim.new(0.1, 0))
	shape(walls, at(0.5, 0.66, 0.3, 0.68, 0, Color3.fromRGB(150, 90, 50)), 2, UDim.new(0.2, 0)) -- door
	-- a little heart on the roof: it's comfy
	shape(c, at(0.44, 0.32, 0.14, 0.14, 0, Color3.fromRGB(255, 120, 170)), nil, ROUND)
	shape(c, at(0.56, 0.32, 0.14, 0.14, 0, Color3.fromRGB(255, 120, 170)), nil, ROUND)
	shape(c, at(0.5, 0.38, 0.12, 0.12, 45, Color3.fromRGB(255, 120, 170)), nil, nil)
end
ICONS.clover = function(c)
	local green = Color3.fromRGB(90, 210, 70)
	shape(c, at(0.62, 0.78, 0.08, 0.34, -25, Color3.fromRGB(70, 160, 50)), 2, ROUND)
	for _, p in ipairs({ { 0.5, 0.26 }, { 0.26, 0.5 }, { 0.74, 0.5 }, { 0.5, 0.74 } }) do
		shape(c, at(p[1], p[2], 0.36, 0.36, 0, green), 2.5, ROUND)
	end
	shape(c, at(0.5, 0.5, 0.2, 0.2, 0, Color3.fromRGB(255, 225, 90)), nil, ROUND)
end
ICONS.lock = function(c)
	shape(c, at(0.5, 0.34, 0.5, 0.5, 0, Color3.fromRGB(150, 150, 165)), 4, ROUND) -- the shackle
	shape(c, at(0.5, 0.36, 0.26, 0.3, 0, UI.Colors.Well), nil, ROUND)
	local body = shape(c, at(0.5, 0.66, 0.66, 0.48, 0, Color3.fromRGB(255, 205, 40)), 2.5, UDim.new(0.18, 0))
	shape(body, at(0.5, 0.45, 0.16, 0.36, 0, INK), nil, ROUND)
end
ICONS.x = function(c)
	shape(c, at(0.5, 0.5, 0.78, 0.2, 45), 2.5, ROUND)
	shape(c, at(0.5, 0.5, 0.78, 0.2, -45), 2.5, ROUND)
end

-- Draws icon `kind` in a square that fills `parent` (or props.Size)
function UI.icon(parent, kind, props)
	local holder = UI.new("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, parent)
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1 }, holder)
	if props then
		for key, value in pairs(props) do
			(holder :: any)[key] = value
		end
	end
	local draw = ICONS[kind]
	if draw then
		draw(holder)
	end
	return holder
end

-- A chunky button that squishes when pressed
function UI.button(parent, text, props, onClick)
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = UI.Colors.Good,
		Font = UI.Font,
		Text = text,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
		Size = UDim2.new(0, 160, 0, 56),
	}, parent)
	UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, button)
	UI.chunky(button, nil, UDim.new(0, 12))
	-- the studs sit on top of the button's own text, so the text is shown by a
	-- label above them instead (button.Text still works: it's copied over)
	button.TextTransparency = 1
	local caption = UI.label(button, { Name = "Caption", Size = UDim2.fromScale(1, 1), Text = text, ZIndex = 2 })
	local limit = caption:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = 30
	end
	local scale = UI.new("UIScale", { Scale = 1 }, button)
	if props then
		for key, value in pairs(props) do
			(button :: any)[key] = value
		end
	end
	caption.Text = button.Text
	caption.TextColor3 = button.TextColor3
	button:GetPropertyChangedSignal("Text"):Connect(function()
		caption.Text = button.Text
	end)
	button:GetPropertyChangedSignal("TextColor3"):Connect(function()
		caption.TextColor3 = button.TextColor3
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if onClick then
		button.Activated:Connect(function()
			UI.sound("Click", 0.5)
			onClick()
		end)
	end
	return button
end

-- Shrinks a frame designed at width x height so it always fits the screen
-- (small phones in landscape are only about 375 points tall)
function UI.fit(frame, width, height, margin)
	local scale = frame:FindFirstChild("FitScale") or UI.new("UIScale", { Name = "FitScale" }, frame)
	local function update()
		local camera = workspace.CurrentCamera
		local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local m = margin or 24
		scale.Scale = math.min(1, (view.X - m) / width, (view.Y - m - 40) / height)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		frame.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	return scale
end

-- A little bounce, for anything that just changed
function UI.pop(guiObject, amount)
	if guiObject:FindFirstChild("FitScale") then
		return -- a frame scaled to fit the screen doesn't bounce (one UIScale per frame)
	end
	local scale = guiObject:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Scale = 1 }, guiObject)
	scale.Scale = 1 + (amount or 0.2)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

----------------------------------------------------------------------
-- 3D icons: a model inside a ViewportFrame, framed to fit
----------------------------------------------------------------------
function UI.viewport(parent, model, props)
	local viewport = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
	}, parent)
	if props then
		for key, value in pairs(props) do
			(viewport :: any)[key] = value
		end
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if model then
		UI.setViewportModel(viewport, model)
	end
	return viewport
end

-- Puts `model` in the viewport (replacing what was there) and frames it.
-- yaw turns the model to show it from the side a little.
function UI.setViewportModel(viewport, model, yaw)
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			child:Destroy()
		end
	end
	if not model then
		return
	end
	model.Parent = viewport
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(viewport.CurrentCamera.FieldOfView / 2)) * 1.05
	local look = CFrame.Angles(0, math.rad(yaw or 200), 0) * CFrame.Angles(math.rad(-12), 0, 0)
	viewport.CurrentCamera.CFrame = CFrame.new(cf.Position) * look * CFrame.new(0, 0, distance)
end

----------------------------------------------------------------------
-- Sounds by name. Where a sound comes from, first match wins:
--   1. a Sound with that name in SoundService (put there by hand)
--   2. its own uploaded id in Config.Sounds
--   3. its slice of the sound sheet (every sound in one uploaded file,
--      see SoundSheet and Sounds/make_sounds.py)
----------------------------------------------------------------------
local soundTemplates = {}
local function makeTemplate(name)
	local info = Config.Sounds and Config.Sounds[name]
	local own = info and info.id and info.id > 0
	local slice = SoundSheet.Sounds[name]
	if not own and not (slice and SoundSheet.Id > 0) then
		return nil -- not uploaded yet
	end
	local template = Instance.new("Sound")
	template.Name = name
	template.Volume = info and info.volume or 0.5
	if own then
		template.SoundId = "rbxassetid://" .. info.id
	else
		template.SoundId = "rbxassetid://" .. SoundSheet.Id
		template.PlaybackRegionsEnabled = true
		template.PlaybackRegion = NumberRange.new(slice[1], slice[2])
	end
	return template
end

-- load the sheet straight away, so the first sounds aren't late
if RunService:IsClient() and SoundSheet.Id > 0 then
	task.spawn(function()
		local sheet = Instance.new("Sound")
		sheet.SoundId = "rbxassetid://" .. SoundSheet.Id
		pcall(ContentProvider.PreloadAsync, ContentProvider, { sheet })
	end)
end

function UI.sound(name, volume, pitch)
	local template = SoundService:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		template = soundTemplates[name]
		if not template then
			template = makeTemplate(name)
			if not template then
				return
			end
			soundTemplates[name] = template
		end
	end
	local sound = template:Clone()
	if volume then
		sound.Volume = template.Volume * volume
	end
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- A tiny message bus for the client scripts (Toss, World, Hud).
-- UI.on("Chomp", fn) and UI.fire("Chomp", ...). Every LocalScript that
-- requires this module gets the same table, so they hear each other.
----------------------------------------------------------------------
local listeners = {}
function UI.on(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end

function UI.fire(name, ...)
	for _, fn in ipairs(listeners[name] or {}) do
		task.spawn(fn, ...)
	end
end

-- The latest private state from the server, shared by the client scripts
UI.state = nil

return UI
