--[[
	UI  (ModuleScript, parent: ReplicatedStorage, name: "UI")

	Small helpers the client scripts share: making frames, labels and big
	friendly buttons, 3D icons in ViewportFrames, sounds by name, and a tiny
	message bus so the client scripts can talk to each other.

	Sounds are optional. Put a Sound in SoundService with one of these names
	and it plays: Chomp, Perfect, Coin, Pop, Throw, Combo, Crack, Hatch,
	HatchRare, SizeUp, Buy, Click, Burp, Error, Announce.
]]

local UI = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

UI.Font = Config.Font
UI.Colors = {
	Panel = Color3.fromRGB(40, 30, 60),
	PanelLight = Color3.fromRGB(62, 48, 92),
	Text = Color3.fromRGB(255, 250, 240),
	Dim = Color3.fromRGB(190, 180, 210),
	Good = Color3.fromRGB(110, 220, 90),
	Bad = Color3.fromRGB(240, 90, 90),
	Gold = Color3.fromRGB(255, 205, 60),
	Accent = Color3.fromRGB(190, 100, 255),
	Stroke = Color3.fromRGB(20, 12, 32),
}

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
	UI.new("UIStroke", { Thickness = 2, Color = UI.Colors.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	if props then
		for key, value in pairs(props) do
			(label :: any)[key] = value
		end
	end
	return label
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
	UI.corner(button, UDim.new(0, 14))
	UI.stroke(button, 3)
	UI.new("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 12 }, button)
	UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, button)
	UI.new("UIStroke", { Thickness = 2, Color = UI.Colors.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, button)
	local scale = UI.new("UIScale", { Scale = 1 }, button)
	if props then
		for key, value in pairs(props) do
			(button :: any)[key] = value
		end
	end
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
-- Sounds by name (only if you've added them to SoundService)
----------------------------------------------------------------------
function UI.sound(name, volume, pitch)
	local template = SoundService:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		return
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
