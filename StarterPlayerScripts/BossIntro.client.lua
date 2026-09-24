--[[
	BossIntro  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "BossIntro")

	1) THE VS SPLASH - when a boss wakes up in front of you, a Smash-style
	   introduction plays: two slanted black panels slam in from opposite
	   sides (the boss's name and pixel portrait on top, you and your level
	   underneath) over speed lines in the boss's colour, a big red VS stamps
	   down between them with the SOUL flashing in it, the screen flashes and
	   shakes - and it all breaks away into the fight. About 2.4 seconds: the
	   boss is still waking up the whole time (it can't attack while it does).

	2) THE SOUL BREAKS - when you die, your red heart appears in the middle of
	   the screen, cracks in two and shatters (Undertale), just before YOU DIED.

	Only on your own screen. Config.Retro.Intro = false turns the splash off,
	Config.Retro.SoulBreak = false the heart.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local R = Config.Retro or {}
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RGB = Color3.fromRGB
local BLACK, WHITE, RED = RGB(0, 0, 0), RGB(255, 255, 255), RGB(228, 59, 68)
local TITLE_FACE = nil
pcall(function()
	TITLE_FACE = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function sound(name)
	local t = name and SoundService:FindFirstChild(name)
	if t and t:IsA("Sound") then
		local s = t:Clone()
		s.Parent = SoundService
		s:Play()
		task.delay(4, function()
			s:Destroy()
		end)
	end
end
local function label(parent, text, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		TextColor3 = WHITE,
		TextStrokeColor3 = BLACK,
		TextStrokeTransparency = 0,
		Font = Enum.Font.Arcade,
	}, parent)
	for k, v in pairs(props or {}) do
		if k ~= "Big" then -- (ours, not a real property: the chunky title font)
			l[k] = v
		end
	end
	if props and props.Big and TITLE_FACE then
		l.FontFace = TITLE_FACE
	end
	return l
end

-- pixel art: each letter is one pixel ("." see-through)
local function sprite(rows, colors, parent, props)
	local h, w = #rows, #rows[1]
	local art = new("Frame", { BackgroundTransparency = 1, SizeConstraint = Enum.SizeConstraint.RelativeYY }, parent)
	for k, v in pairs(props) do
		art[k] = v
	end
	new("UIAspectRatioConstraint", { AspectRatio = w / h }, art)
	for y = 1, h do
		for x = 1, w do
			local c = colors[string.sub(rows[y], x, x)]
			if c then
				new("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = c,
					Size = UDim2.fromScale(1 / w + 0.003, 1 / h + 0.003),
					Position = UDim2.fromScale((x - 1) / w, (y - 1) / h),
					ZIndex = (art.ZIndex or 1) + 1,
				}, art)
			end
		end
	end
	return art
end
local SOUL = {
	".OO.OO.",
	"ORROrRO",
	"ORRRRRO",
	"ORRRRrO",
	".ORRrO.",
	"..ORO..",
	"...O...",
}
local SOUL_INK = { O = BLACK, R = RED, r = RGB(162, 38, 51) }

-- the bosses' portraits
local PORTRAITS = {
	Gloomgut = {
		rows = {
			"....GGGGGG....",
			"..GGGGGGGGGG..",
			".GGGLLGGGGGGG.",
			".GGLLGGGGGGGG.",
			"GGGWWGGGGWWGGG",
			"GGGWKGGGGKWGGG",
			"GGGGGGGGGGGGGG",
			"GGGGKKKKKKGGGG",
			"GGGKKWKKWKKGGG",
			".GGGKKKKKKGGG.",
			".DGGGGGGGGGGD.",
			"DDGDGGDGGDGDDD",
		},
		ink = { G = RGB(99, 199, 77), L = RGB(190, 240, 140), D = RGB(62, 137, 72), W = RGB(236, 255, 170), K = RGB(25, 60, 62) },
	},
	Mireworm = {
		rows = {
			"......SSSS....",
			"....SSSSSSSS..",
			"...SSKKKKKKSS.",
			"..SSKWKWKWKKS.",
			"..SSKKKKKKKKS.",
			"..SSKWKWKWKKS.",
			"...SSKKKKKKS..",
			"...DSSSSSSSS..",
			"..DDSS.SSDS...",
			".DDSS...SS....",
			"DDSS.........D",
			"DSS.DDD..DDDDD",
		},
		ink = { S = RGB(228, 166, 114), D = RGB(184, 111, 80), K = RGB(62, 39, 49), W = RGB(255, 255, 255) },
	},
}

----------------------------------------------------------------------
-- 1) The VS splash
----------------------------------------------------------------------
local playing = false
local function playIntro(def)
	if playing or R.Intro == false then
		return
	end
	playing = true
	local accent = def.Color or RGB(254, 174, 52)
	local gui = new("ScreenGui", { Name = "BossIntro", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1100 }, playerGui)
	gui:SetAttribute("RetroSkip", true)
	local root = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local dim = new("Frame", { BackgroundColor3 = BLACK, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, root)
	tween(dim, 0.2, { BackgroundTransparency = 0.45 })

	-- a slanted panel, sliding in from one side
	local lines = {}
	local function panel(y, fromRight, color)
		local p = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(fromRight and 1.9 or -0.9, y),
			Size = UDim2.fromScale(1.3, 0.25),
			Rotation = -5,
			BackgroundColor3 = BLACK,
			ClipsDescendants = true,
			ZIndex = 2,
		}, root)
		new("UIStroke", { Color = WHITE, Thickness = 5, LineJoinMode = Enum.LineJoinMode.Miter }, p)
		-- speed lines in the boss's colour, rushing past
		for i = 1, 9 do
			local l = new("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				BackgroundTransparency = 0.35 + (i % 3) * 0.18,
				Size = UDim2.fromScale(0.25 + (i % 4) * 0.1, 0.03 + (i % 2) * 0.03),
				Position = UDim2.fromScale(0, (i - 0.5) / 9),
				ZIndex = 2,
			}, p)
			table.insert(lines, { f = l, x = math.random(), speed = (fromRight and -1 or 1) * (1.2 + math.random()), y = (i - 0.5) / 9 })
		end
		return p
	end
	local top = panel(0.3, true, accent)
	local bottom = panel(0.7, false, RGB(44, 232, 245))

	-- top: the boss
	label(top, string.upper(def.Short or def.Name or "BOSS"), { Big = true, Position = UDim2.fromScale(0.14, 0.12), Size = UDim2.fromScale(0.52, 0.5), TextColor3 = accent, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local title = (def.Name and string.match(def.Name, ",%s*(.+)$")) or ""
	label(top, string.upper(title), { Position = UDim2.fromScale(0.14, 0.62), Size = UDim2.fromScale(0.52, 0.24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local portrait = PORTRAITS[def.Short]
	if portrait then
		sprite(portrait.rows, portrait.ink, top, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.78, 0.5), Size = UDim2.fromScale(0.85, 0.85), ZIndex = 4 })
	end

	-- bottom: you
	local thumb = new("ImageLabel", {
		BackgroundColor3 = RGB(38, 43, 68),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.24, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ZIndex = 4,
	}, bottom)
	new("UIStroke", { Color = WHITE, Thickness = 3 }, thumb)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and thumb.Parent then
			thumb.Image = img
		end
	end)
	label(bottom, string.upper(player.DisplayName), { Big = true, Position = UDim2.fromScale(0.36, 0.14), Size = UDim2.fromScale(0.5, 0.46), TextColor3 = RGB(44, 232, 245), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	local stats = player:FindFirstChild("leaderstats")
	local lv = stats and stats:FindFirstChild("Level")
	label(bottom, lv and ("LV " .. tostring(lv.Value)) or "CHALLENGER", { Position = UDim2.fromScale(0.36, 0.62), Size = UDim2.fromScale(0.5, 0.24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })

	-- the VS, with the SOUL in it
	local vs = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.3, 0.2), ZIndex = 6, Visible = false }, root)
	local vsScale = new("UIScale", { Scale = 3 }, vs)
	label(vs, "VS", { Big = true, Size = UDim2.fromScale(1, 1), TextColor3 = RED, TextStrokeTransparency = 0, ZIndex = 7 })
	local soul = sprite(SOUL, SOUL_INK, vs, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.35, 0.35), ZIndex = 8, Visible = false })
	local flash = new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 }, root)

	-- the speed lines rush, and the panels shake after the VS lands
	local shake = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		for _, l in ipairs(lines) do
			l.x = (l.x + l.speed * dt + 0.2) % 1.4 - 0.2
			l.f.Position = UDim2.fromScale(l.x, l.y)
		end
		if shake > 0 then
			shake = math.max(0, shake - dt * 3)
			root.Position = UDim2.fromOffset(math.random(-8, 8) * shake, math.random(-8, 8) * shake)
		end
	end)

	-- the timeline
	sound(R.IntroWhoosh or "UI Blip")
	tween(top, 0.28, { Position = UDim2.fromScale(0.5, 0.3) }, Enum.EasingStyle.Back)
	task.wait(0.14)
	tween(bottom, 0.28, { Position = UDim2.fromScale(0.5, 0.7) }, Enum.EasingStyle.Back)
	task.wait(0.4)
	vs.Visible = true
	tween(vsScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.2)
	sound(R.IntroStamp or (def.Sounds and def.Sounds.Wake))
	shake = 1
	flash.BackgroundTransparency = 0.2
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	for _ = 1, 3 do
		soul.Visible = true
		task.wait(0.09)
		soul.Visible = false
		task.wait(0.07)
	end
	task.wait(0.6)
	-- and away: the panels fly off, the VS shrinks into nothing
	tween(top, 0.3, { Position = UDim2.fromScale(-0.9, 0.3) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(bottom, 0.3, { Position = UDim2.fromScale(1.9, 0.7) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(vsScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(dim, 0.3, { BackgroundTransparency = 1 })
	task.wait(0.35)
	conn:Disconnect()
	gui:Destroy()
	playing = false
end

-- watch every boss: when one starts waking and it's on YOUR floor, play it
local function watchBoss(model)
	model:GetAttributeChangedSignal("State"):Connect(function()
		if model:GetAttribute("State") ~= "Waking" then
			return
		end
		local floor = player:GetAttribute("SpireFloor")
		local def = floor and Config.Bosses and Config.Bosses[floor]
		if def then
			task.spawn(function()
				local ok, err = pcall(playIntro, def)
				if not ok then
					-- (never leave the screen dimmed if something went wrong)
					warn("[BossIntro] " .. tostring(err))
					local left = playerGui:FindFirstChild("BossIntro")
					if left then
						left:Destroy()
					end
					playing = false
				end
			end)
		end
	end)
end
for _, m in ipairs(CollectionService:GetTagged("Boss")) do
	watchBoss(m)
end
CollectionService:GetInstanceAddedSignal("Boss"):Connect(watchBoss)

----------------------------------------------------------------------
-- 2) The SOUL breaks when you die
----------------------------------------------------------------------
local function soulBreak()
	if R.SoulBreak == false then
		return
	end
	local gui = new("ScreenGui", { Name = "SoulBreak", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1050 }, playerGui)
	gui:SetAttribute("RetroSkip", true)
	local function half(rows)
		return sprite(rows, SOUL_INK, gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.1, 0.1) })
	end
	-- the two halves of the heart, split down a zigzag
	local left = half({ ".OO....", "ORRO...", "ORRRO..", "ORRR...", ".ORRO..", "..OR...", "...O..." })
	local right = half({ "....OO.", "...rRO.", "...RRRO", "...RRrO", "....rO.", "...RO..", "...O..." })
	task.wait(0.5)
	sound("UI Blip")
	tween(left, 0.25, { Position = UDim2.new(0.5, -10, 0.45, 0) })
	tween(right, 0.25, { Position = UDim2.new(0.5, 10, 0.45, 0) })
	task.wait(0.6)
	left.Visible, right.Visible = false, false
	-- shards
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local shard = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RED, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(10, 10) }, gui)
		tween(shard, 1, { Position = UDim2.new(0.5, math.cos(a) * 120, 0.45, math.sin(a) * 80 + 140), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.wait(1.1)
	gui:Destroy()
end
local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			task.spawn(soulBreak)
		end)
	end
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
