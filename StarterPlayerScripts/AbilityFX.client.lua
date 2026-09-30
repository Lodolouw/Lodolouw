--[[
	AbilityFX  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "AbilityFX")

	What weapon abilities' building blocks look like, on everyone (CombatService
	sets these attributes on each player; see "Ability building blocks"):
	  * Aura + AuraUntil (a colour, server time): a glow and rising sparks in
	    that colour round the player while a buff lasts
	  * Shield: a see-through bubble round them until a hit breaks it
	  * Stacks: little pips over their head (the weapon's stacks)
	  * PowerN (changes when an ability is used): a quick ring bursting out
	    at their feet
	  * AuraStyle: the look of their weapon's aura (ReplicatedStorage/MoveFX
	    STYLES: slime dripping off them, flames, leaves, skid marks...)
	And each weapon ability's own effects: the server tells every screen when
	someone's move starts, where it picks its spot, and a building block's
	moments (CombatRemotes.AbilityFx) - ReplicatedStorage/MoveFX draws them.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoveFX = require(ReplicatedStorage:WaitForChild("MoveFX"))

-- the server's word on every ability (see MoveFX.told)
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("CombatRemotes", 60)
	local fx = remotes and remotes:WaitForChild("AbilityFx", 60)
	if fx then
		fx.OnClientEvent:Connect(function(player, id, count, step, point, extra)
			-- (Settings: "hide others' effects" - only your own are drawn)
			if player ~= Players.LocalPlayer and Players.LocalPlayer:GetAttribute("HideOthersFX") then
				return
			end
			MoveFX.told(player, id, count, step, point, extra)
		end)
	end
end)

local RGB = Color3.fromRGB
local MAX_PIPS = 5

local looks = {} -- [player] = { aura, sparks, bubble, pips, powerN }

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function clear(look)
	for _, key in ipairs({ "aura", "sparks", "bubble", "pips" }) do
		if look[key] then
			look[key]:Destroy()
			look[key] = nil
		end
	end
end

-- a ring bursting out along the floor from the player's feet
local function ring(root, color)
	local r = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.2,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 3, 3),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, Workspace)
	TweenService:Create(r, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 16, 16), Transparency = 1 }):Play()
	task.delay(0.5, function()
		r:Destroy()
	end)
end

local function update(plr, look, dt)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or (plr ~= Players.LocalPlayer and Players.LocalPlayer:GetAttribute("HideOthersFX")) then
		clear(look) -- (or Settings: "hide others' effects")
		return
	end
	local now = Workspace:GetServerTimeNow()

	-- the aura
	local color = plr:GetAttribute("Aura")
	local untilT = plr:GetAttribute("AuraUntil")
	local on = typeof(color) == "Color3" and type(untilT) == "number" and now < untilT
	if on then
		if not look.aura or look.aura.Parent ~= char then
			if look.aura then
				look.aura:Destroy()
			end
			look.aura = new("Highlight", { FillTransparency = 0.8, OutlineTransparency = 0.2, DepthMode = Enum.HighlightDepthMode.Occluded }, char)
		end
		look.aura.FillColor, look.aura.OutlineColor = color, color
		if not look.sparks or look.sparks.Parent ~= root then
			if look.sparks then
				look.sparks:Destroy()
			end
			look.sparks = new("ParticleEmitter", {
				Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Rate = 18,
				Lifetime = NumberRange.new(0.6, 1),
				Speed = NumberRange.new(3, 6),
				SpreadAngle = Vector2.new(25, 25),
				EmissionDirection = Enum.NormalId.Top,
				Size = NumberSequence.new(0.5, 0),
				LightEmission = 1,
			}, root)
		end
		look.sparks.Color = ColorSequence.new(color)
		-- (fading out in its last half second)
		local left = untilT - now
		look.aura.FillTransparency = left < 0.5 and 0.8 + (0.5 - left) * 0.4 or 0.8
		-- the weapon's own aura on top (slime dripping off, flames, leaves...)
		local style = plr:GetAttribute("AuraStyle")
		if type(style) == "string" then
			MoveFX.aura(plr, char, style, dt or 1 / 60)
		end
	else
		if look.aura then
			look.aura:Destroy()
			look.aura = nil
		end
		if look.sparks then
			look.sparks:Destroy()
			look.sparks = nil
		end
	end

	-- the shield bubble
	if plr:GetAttribute("Shield") then
		if not look.bubble then
			look.bubble = new("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.ForceField,
				Color = RGB(120, 220, 255),
				Size = Vector3.new(7, 7, 7),
			}, Workspace)
		end
		look.bubble.CFrame = root.CFrame
	elseif look.bubble then
		-- (it breaks: a burst of the same blue)
		ring(root, RGB(120, 220, 255))
		look.bubble:Destroy()
		look.bubble = nil
	end

	-- the stacks' pips
	local stacks = plr:GetAttribute("Stacks") or 0
	if stacks > 0 then
		if not look.pips or look.pips.Parent ~= root then
			if look.pips then
				look.pips:Destroy()
			end
			look.pips = new("BillboardGui", { Size = UDim2.fromOffset(MAX_PIPS * 16, 14), StudsOffset = Vector3.new(0, 3.6, 0), AlwaysOnTop = true }, root)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }, look.pips)
			for i = 1, MAX_PIPS do
				local p = new("Frame", { Name = tostring(i), BorderSizePixel = 0, Size = UDim2.fromOffset(12, 12), LayoutOrder = i }, look.pips)
				new("UIStroke", { Thickness = 2, Color = RGB(24, 20, 37) }, p)
			end
		end
		for i = 1, MAX_PIPS do
			local p = look.pips:FindFirstChild(tostring(i))
			if p then
				p.BackgroundColor3 = i <= stacks and RGB(140, 255, 120) or RGB(50, 50, 70)
			end
		end
	elseif look.pips then
		look.pips:Destroy()
		look.pips = nil
	end

	-- an ability used: the ring
	local powerN = plr:GetAttribute("PowerN")
	if powerN ~= look.powerN then
		if look.powerN ~= nil then
			ring(root, typeof(color) == "Color3" and color or RGB(255, 255, 255))
		end
		look.powerN = powerN
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local look = looks[plr]
		if not look then
			look = { powerN = plr:GetAttribute("PowerN") }
			looks[plr] = look
		end
		update(plr, look, dt)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	local look = looks[plr]
	if look then
		clear(look)
		looks[plr] = nil
	end
end)
