--[[
	BossIntro  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "BossIntro")

	1) THE VS SPLASH - when a boss wakes up in front of you, a Smash-style
	   introduction plays: two slanted black panels slam in from opposite
	   sides (the boss's name and pixel portrait on top, you and your level
	   underneath) over speed lines in the boss's colour, a big red VS stamps
	   down between them with the SOUL flashing in it, the screen flashes and
	   shakes - and it all breaks away into the fight. About 2.4 seconds: the
	   boss is still waking up the whole time (it can't attack while it does).

	3) THE BOSSES TALK - an Undertale-style box under the boss bar with the
	   boss's portrait: it greets you, mocks you, gloats, and has last words.

	4) THE COLOSSEUM'S BOSS WAVE - the Giant Straw King gets the same VS
	   splash (the first time you meet him each visit) and talks the same way
	   (he also shouts for his minions when he summons them).

	Only on your own screen. Config.Retro.Intro = false turns the splash off,
	Config.Retro.BossTalk = false the talking.
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
	Oozark = {
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
	Nahrzul = {
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
	-- the Colosseum's boss wave: a straw face, a gold crown, a big fluffy beard
	["Straw King"] = {
		rows = {
			"..Y..Y..Y..Y..",
			"..YYYYYYYYYY..",
			"..YRYYYYYYRY..",
			".SSSSSSSSSSSS.",
			".SKKKSSSSKKKS.",
			".SSKKSSSSKKSS.",
			".SSSSSDDSSSSS.",
			".SWWWWWWWWWWS.",
			".SWWSSSSSSWWS.",
			"..SWWWWWWWWS..",
			"...WWWWWWWW...",
			"....WW.WW.WW..",
		},
		ink = { Y = RGB(254, 174, 52), R = RGB(228, 59, 68), S = RGB(228, 166, 114), K = RGB(24, 20, 37), D = RGB(184, 111, 80), W = RGB(234, 212, 170) },
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

-- (When you die, the heart on your HP bar cracks and shatters - Hud does
-- that - and YOU DIED shows in the middle; nothing more is needed here.)

----------------------------------------------------------------------
-- 3) THE BOSSES TALK (like Undertale's): a black box under the boss bar,
-- its little portrait beside the words, typed out with a blip. It greets
-- you, mocks you mid-fight, gloats when it hits you hard, changes its tune
-- in phase two, crows if you fall and gets the last word when it dies.
----------------------------------------------------------------------
local LINES = {
	-- a tyrant of jelly: pompous, royal and very pleased with himself
	Oozark = {
		wake = { "* KNEEL! You stand before OOZARK, the Gelatinous Tyrant!", "* A visitor? How DARE you drip on my royal floor." },
		idle = {
			"* Bow before your jiggly overlord!",
			"* My kingdom is vast. And sticky. Mostly sticky.",
			"* I shall add you to my collection of absorbed heroes!",
			"* Do not touch the crown. It is also slime.",
			"* Tremble! My wobbling strikes FEAR into lesser puddles!",
			"* I was a puddle once. Now look at me. MAGNIFICENT.",
		},
		hit = { "* HA! Behold the royal splat!", "* By decree of the Tyrant: OUCH, for you.", "* Sticky, isn't it? That's majesty." },
		phase2 = { "* You... POPPED the Tyrant?! GUARDS! ...I have no guards.", "* Enough! Now witness my TRUE, FINAL, JIGGLIEST form!" },
		win = { "* Another subject for the Gelatinous Kingdom!", "* Long live Oozark! Long live the goo!" },
		lose = { "* The Tyrant... falls... tell the puddles... I was great...", "* No... my kingdom... it's melting..." },
	},
	-- ancient, hungry and deadly serious
	Nahrzul = {
		wake = { "* I AM NAHRZUL. THE DUNES ARE MY MOUTH.", "* Another caravan of one. How small you are." },
		idle = {
			"* I can hear your heartbeat through the sand.",
			"* Kingdoms have sunk into my belly. You will not be missed.",
			"* The dunes remember every bone I have left in them.",
			"* Run. The hunt ends the same either way.",
			"* Beneath you. Behind you. Everywhere.",
		},
		hit = { "* The sand drinks your strength.", "* You are already half swallowed.", "* Feel the earth break. That was me." },
		phase2 = { "* YOU CRACKED MY SHELL. NOW THE SANDS WILL DROWN YOU.", "* Enough. I will pull this whole desert down on you." },
		win = { "* Another bone for the dunes.", "* The sands keep you now." },
		lose = { "* The dunes... fall... silent...", "* So even the desert... can be conquered..." },
	},
	-- the Giant Straw King: loud, vain and very proud of his beard
	["Straw King"] = {
		wake = {
			"* HALT! You stand before the GIANT STRAW KING!",
			"* You beat my subjects? Then face their KING!",
			"* Kneel, little farmer. Your king has ARRIVED.",
		},
		idle = {
			"* Behold my magnificent beard. Hand-stuffed.",
			"* I was the scarecrow of this field. Now I RULE it.",
			"* The crows fear me. The crowd ADORES me.",
			"* My crown is solid gold. Well. Gold-coloured straw.",
			"* Punch me all you like. I'm made of hay!",
			"* Long live the Straw King! ...that's me, by the way.",
		},
		hit = { "* HA! Royal decree: OUCH, for you.", "* Bow! ...oh, you fell over. Close enough.", "* Did that sting? Kings hit HARD." },
		summon = { "* RISE, my loyal minions!", "* Guards! GUARDS! Seize this peasant!", "* My subjects! Your king commands you!" },
		phase2 = { "* You... you RUFFLED my STRAW?! Now I'm ANGRY!", "* ENOUGH! Feel the fury of the harvest!" },
		win = { "* Another peasant for the compost heap!", "* Long live the King! Long live the HAY!" },
		lose = { "* The King... falls... tell the crows... I was magnificent...", "* My kingdom... for a needle and thread..." },
	},
}

local talkGui, talkBox, talkText, talkPortrait
local speaking = nil
local function buildTalk()
	talkGui = new("ScreenGui", { Name = "BossTalk", ResetOnSpawn = false, DisplayOrder = 30 }, playerGui)
	talkGui:SetAttribute("RetroSkip", true)
	talkBox = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Size = UDim2.fromOffset(620, 86),
		BackgroundColor3 = BLACK,
		Visible = false,
	}, talkGui)
	new("UIStroke", { Color = WHITE, Thickness = 4, LineJoinMode = Enum.LineJoinMode.Miter }, talkBox)
	talkText = label(talkBox, "", {
		Position = UDim2.fromOffset(92, 12),
		Size = UDim2.new(1, -108, 1, -24),
		TextScaled = false,
		TextSize = 24,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 1,
	})
end
local function say(short, kind)
	local set = LINES[short]
	local list = set and set[kind]
	if not list or R.BossTalk == false then
		return
	end
	if not talkGui then
		buildTalk()
	end
	local text = list[math.random(#list)]
	if talkPortrait then
		talkPortrait:Destroy()
	end
	local p = PORTRAITS[short]
	if p then
		talkPortrait = sprite(p.rows, p.ink, talkBox, { Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(64, 64) })
	end
	talkText.Text = text
	talkText.MaxVisibleGraphemes = 0
	talkBox.Visible = true
	local me = {}
	speaking = me
	task.spawn(function()
		local n = utf8.len(text) or #text
		for i = 1, n do
			if speaking ~= me then
				return
			end
			talkText.MaxVisibleGraphemes = i
			if i % 2 == 0 then
				sound(R.TypeBlip or "UI Blip")
			end
			task.wait(1 / 32)
		end
		talkText.MaxVisibleGraphemes = -1
		task.wait(3)
		if speaking == me then
			talkBox.Visible = false
			speaking = nil
		end
	end)
end

-- which boss is yours right now (the one on your floor)
local current = nil -- { model, short }
local nextIdle = 0
local function onMyFloor()
	local floor = player:GetAttribute("SpireFloor")
	local def = floor and Config.Bosses and Config.Bosses[floor]
	return def
end
local function watchTalk(model)
	model:GetAttributeChangedSignal("State"):Connect(function()
		local def = onMyFloor()
		if not def then
			return
		end
		local st = model:GetAttribute("State")
		if st == "Waking" then
			current = { model = model, short = def.Short }
			nextIdle = os.clock() + 14
			task.delay(2.6, say, def.Short, "wake") -- (just after the VS splash)
		elseif st == "Dead" then
			say(def.Short, "lose")
			current = nil
		elseif st == "Dormant" or st == "Resetting" then
			current = nil
		end
	end)
	model:GetAttributeChangedSignal("Phase"):Connect(function()
		local def = onMyFloor()
		if def and model:GetAttribute("Phase") == 2 then
			say(def.Short, "phase2")
			nextIdle = os.clock() + 12
		end
	end)
end
for _, m in ipairs(CollectionService:GetTagged("Boss")) do
	watchTalk(m)
end
CollectionService:GetInstanceAddedSignal("Boss"):Connect(watchTalk)

-- every so often in the fight, a jab
RunService.Heartbeat:Connect(function()
	if current and current.model:GetAttribute("State") == "Fighting" and os.clock() > nextIdle and not speaking then
		nextIdle = os.clock() + 14 + math.random() * 8
		say(current.short, "idle")
	end
end)

-- a big hit on you: it gloats (not every time); you fall: it crows
local function watchMyHealth(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		local lost = last - h
		last = h
		if current and h > 0 and lost >= hum.MaxHealth * 0.2 and math.random() < 0.5 and not speaking then
			say(current.short, "hit")
		end
	end)
	hum.Died:Connect(function()
		if current then
			say(current.short, "win")
		end
	end)
end
if player.Character then
	task.spawn(watchMyHealth, player.Character)
end
player.CharacterAdded:Connect(watchMyHealth)

----------------------------------------------------------------------
-- 4) THE COLOSSEUM'S BOSS WAVE: the Giant Straw King
----------------------------------------------------------------------
-- He isn't a Spire boss, so he's found differently: he's YOUR dummy
-- (Owner) of Kind "King" in workspace.ColosseumEnemies. His State and Phase
-- work like a Spire boss's, so the VS splash and the talking are the same.
do
	local KC = (Config.Colosseum and Config.Colosseum.King) or {}
	-- the name of the first Sound on the list that's in SoundService
	-- (capitals and spaces don't matter)
	local function squash(name)
		return string.lower((string.gsub(tostring(name), "%s+", "")))
	end
	local function firstSound(names)
		for _, name in ipairs(names or {}) do
			for _, sfx in ipairs(SoundService:GetChildren()) do
				if sfx:IsA("Sound") and squash(sfx.Name) == squash(name) then
					return sfx.Name
				end
			end
		end
		return nil
	end
	local kingDef = {
		Name = (KC.name or "Giant Straw King") .. ", Lord of the Colosseum",
		Short = "Straw King",
		Color = RGB(254, 174, 52),
		Sounds = {},
	}
	local metHim = false -- (the full splash only the first time each visit)
	local function watchKing(model)
		if not (model:IsA("Model") and model:GetAttribute("Kind") == "King" and model:GetAttribute("Owner") == player.UserId) then
			return
		end
		model:GetAttributeChangedSignal("State"):Connect(function()
			local st = model:GetAttribute("State")
			if st == "Waking" then
				current = { model = model, short = kingDef.Short }
				nextIdle = os.clock() + 14
				if not metHim then
					metHim = true
					kingDef.Sounds.Wake = firstSound(KC.Sounds and KC.Sounds.Roar) -- (his roar stamps the VS)
					task.spawn(function()
						local ok, err = pcall(playIntro, kingDef)
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
					task.delay(2.6, say, kingDef.Short, "wake") -- (just after the VS splash)
				else
					task.delay(0.4, say, kingDef.Short, "wake")
				end
			elseif st == "Dead" then
				say(kingDef.Short, "lose")
				if current and current.model == model then
					current = nil
				end
			end
		end)
		model:GetAttributeChangedSignal("Phase"):Connect(function()
			if model:GetAttribute("Phase") == 2 then
				say(kingDef.Short, "phase2")
				nextIdle = os.clock() + 12
			end
		end)
		model:GetAttributeChangedSignal("Move"):Connect(function()
			if model:GetAttribute("Move") == "Summon" and not speaking then
				say(kingDef.Short, "summon")
				nextIdle = os.clock() + 10
			end
		end)
		-- gone (you left, or fell): he stops talking
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) and current and current.model == model then
				current = nil
			end
		end)
	end
	-- (a new visit to the Colosseum: he gets his big entrance again)
	player:GetAttributeChangedSignal("Colosseum"):Connect(function()
		if not player:GetAttribute("Colosseum") then
			metHim = false
		end
	end)
	task.spawn(function()
		local folder = workspace:WaitForChild("ColosseumEnemies", 60)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				watchKing(m)
			end
			folder.ChildAdded:Connect(watchKing)
		end
	end)
end
