--[[
	BossIntro  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "BossIntro")

	1) THE VS SPLASH - when a boss wakes up in front of you, a Smash-style
	   introduction plays: two slanted black panels slam in from opposite
	   sides (the boss's name and pixel portrait on top, you and your level
	   underneath) over speed lines in the boss's colour, a big red VS stamps
	   down between them with the SOUL flashing in it, the screen flashes and
	   shakes - and it all breaks away into the fight. About 2.4 seconds: the
	   boss is still waking up the whole time (it can't attack while it does).

	3) THE BOSSES TALK - a speech bubble over the boss's head (its name on a
	   tag in its colour): it greets you, mocks you, gloats, and has last
	   words. The bubble follows its head, and waits at the edge of your
	   screen when its head is off it.

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
	-- little Tuber: a chubby stack of cactus, rosy cheeks, a pink flower on top
	Tuber = {
		rows = {
			"......PP......",
			".....PYYP.....",
			"......PP......",
			"....GGGGGG....",
			"...GKGGGGKG...",
			"...GPGKKGPG...",
			"....GGGGGG....",
			"..DGGGGGGGGD..",
			"..GGSGGGGSGG..",
			"..DGGGGGGGGD..",
			".GGGGSGGGSGGG.",
			".DGGGGGGGGGGD.",
		},
		ink = { G = RGB(99, 199, 77), D = RGB(62, 137, 72), K = RGB(24, 20, 37), P = RGB(246, 117, 122),
			Y = RGB(254, 231, 97), S = RGB(234, 212, 170) },
	},
	-- THE BRUTE: the golem's barrel-cactus head, crowned, eyes burning red
	Brute = {
		rows = {
			"..Y.Y.YY.Y.Y..",
			"..YYYYYYYYYY..",
			"..GGGGGGGGGG..",
			".GCCCCCCCCCCG.",
			".GRRGGGGGGRRG.",
			".GGGGGGGGGGGG.",
			".GSKKKKKKKKSG.",
			".GGKSKSKSKKGG.",
			".GGGGGGGGGGGG.",
			"SGGDGGGGGGDGGS",
			"GGGGGGGGGGGGGG",
			"GDGGGGSGGGGGDG",
		},
		ink = { Y = RGB(254, 174, 52), G = RGB(99, 199, 77), C = RGB(38, 92, 66), R = RGB(255, 0, 68),
			K = RGB(24, 20, 37), S = RGB(234, 212, 170), D = RGB(62, 137, 72) },
	},
	-- a blue helmet with curly gold horns, the T-shaped visor, two glowing eyes
	Burrowmore = {
		rows = {
			"YO..........OY",
			"Y.O........O.Y",
			".YOBBBBBBBBOY.",
			"..BBBBYYBBBB..",
			"..BLBBBBBBBB..",
			"..BKKKKKKKKB..",
			"..BKWKKKKWKB..",
			"..BBBBKKBBBB..",
			"..BDBBKKBBDB..",
			"..BDBBBBBBDB..",
			".YYYYYYYYYYYY.",
			"RRRDDBBBBDDRRR",
		},
		ink = { Y = RGB(254, 174, 52), O = RGB(247, 118, 34), B = RGB(0, 153, 219), L = RGB(44, 232, 245), D = RGB(18, 78, 137),
			K = RGB(24, 20, 37), W = RGB(254, 231, 97), R = RGB(228, 59, 68) },
	},
	-- spiky hair, the red headband (its tails flying off to the side), stern
	-- eyebrows, and the collar of his white gi
	Kaze = {
		rows = {
			"...H.HH.H.H...",
			"..HHHHHHHHHH..",
			".HHHHHHHHHHHH.",
			".RRRRRRRRRRRRR",
			".SSSSSSSSSSSRr",
			".SKKKSSSKKKS.r",
			".SSWKSSSWKSS.R",
			".SSSSSDSSSSS..",
			".SSSSSSSSSSS..",
			"..SSSKKKKSS...",
			"...WWSSSSWW...",
			".WWWWLSSLWWWW.",
		},
		ink = { H = RGB(62, 39, 49), R = RGB(228, 59, 68), r = RGB(162, 38, 51), S = RGB(232, 183, 150), K = RGB(24, 20, 37),
			W = RGB(255, 255, 255), D = RGB(194, 133, 105), L = RGB(192, 203, 220) },
	},
	-- a red race car, head on: big eyes on his windscreen (lids half down:
	-- cocky), headlights, and a toothy grin on his bumper
	Revvington = {
		rows = {
			"....RRRRRR....",
			"...RRRRRRRR...",
			"..RDDDRRDDDR..",
			"..RWWBRRWWBR..",
			"..RWWKRRWWKR..",
			".RRRRRRRRRRRR.",
			"RYYRRRSRRRRYYR",
			"RRKRRRRRRRRKRR",
			"RRKKWWWWWWKKRR",
			"RRRKKKKKKKKRRR",
			"KKDDDDDDDDDDKK",
			"KK..........KK",
		},
		ink = { R = RGB(228, 59, 68), D = RGB(162, 38, 51), K = RGB(24, 20, 37), W = RGB(255, 255, 255), B = RGB(0, 153, 219),
			Y = RGB(254, 231, 97), S = RGB(254, 174, 52) },
	},
	-- a black cube with glowing red edges and little horns: slanted yellow
	-- eyes and a jagged grin
	Gridlock = {
		rows = {
			"HH..........HH",
			".HH........HH.",
			"RRRRRRRRRRRRRR",
			"RKKKKKKKKKKKKR",
			"RKYYKKKKKKYYKR",
			"RKKYYYKKYYYKKR",
			"RKKKKKKKKKKKKR",
			"RKMWMWMWMWMWKR",
			"RKWMWMWMWMWMKR",
			"RKKKKKKKKKKKKR",
			"RKKKKKKKKKKKKR",
			"RRRRRRRRRRRRRR",
		},
		ink = { H = RGB(255, 0, 68), R = RGB(255, 0, 68), K = RGB(24, 20, 37), Y = RGB(254, 231, 97), W = RGB(255, 255, 255),
			M = RGB(162, 38, 51) },
	},
	-- a gorilla: a tuft of brown fur, a heavy brow, a big tan muzzle with a
	-- cocky grin, and the knot of his red tie
	Kongo = {
		rows = {
			".....FFF......",
			"...FFFFFFFF...",
			"..FFFFFFFFFF..",
			".FDDDDDDDDDDF.",
			".FSWKSSSSWKSF.",
			"FFSSSSSSSSSSFF",
			"FSSSSKSSKSSSSF",
			"FSSSSSSSSSSSSF",
			".FSKWWWWWWKSF.",
			"..FSKKKKKKSF..",
			"...FFRRRRFF...",
			"....FFRRFF....",
		},
		ink = { F = RGB(115, 62, 57), D = RGB(62, 39, 49), S = RGB(232, 183, 150), W = RGB(255, 255, 255), K = RGB(24, 20, 37),
			R = RGB(228, 59, 68) },
	},
	-- a flower: pink petals round a big yellow face, long-lashed eyes, rosy
	-- cheeks and a sweet little smile
	Petalina = {
		rows = {
			"....P..P..P...",
			"..PPPPPPPPPP..",
			".PPYYYYYYYYPP.",
			"PPYYYYYYYYYYPP",
			".PYKWYYYYKWYP.",
			"PPYKKYYYYKKYPP",
			".PYYYYYYYYYYP.",
			"PPRYYYYYYYYRPP",
			".PYYKYYYYKYYP.",
			"..PYYKKKKYYP..",
			"...PPPPPPPP...",
			"......GG......",
		},
		ink = { P = RGB(246, 117, 122), Y = RGB(254, 231, 97), K = RGB(24, 20, 37), W = RGB(255, 255, 255), R = RGB(228, 59, 68),
			G = RGB(99, 199, 77) },
	},
	-- a stick figure's head in blue pen: a round white face, two dot eyes, a
	-- big grin, the pencil behind his ear
	Scribble = {
		rows = {
			"...BBBBBBB..P.",
			"..BWWWWWWWB.Y.",
			".BWWWWWWWWWBY.",
			".BWWKWWWKWWBY.",
			".BWWKWWWKWWB..",
			".BWWWWWWWWWB..",
			".BWKWWWWWKWB..",
			".BWWKKKKKWWB..",
			"..BWWWWWWWB...",
			"...BBBBBBB....",
			"......B.......",
			"..BBBBBBBBB...",
		},
		ink = { B = RGB(0, 153, 219), W = RGB(255, 255, 255), K = RGB(24, 20, 37), Y = RGB(254, 174, 52), P = RGB(246, 117, 122) },
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
	local accent = def.Accent or def.Color or RGB(254, 174, 52) -- (Accent: a boss whose own colour is too pale for it)
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
-- 3) THE BOSSES TALK: a speech bubble over the boss's head - white, inked
-- round the edge, its name on a tag in its colour - the words typed out
-- with a blip. It greets you, mocks you mid-fight, gloats when it hits you
-- hard, changes its tune in phase two, crows if you fall and gets the last
-- word when it dies.
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
	-- little Tuber: sweet, bouncy, and very pleased you came to play. When
	-- his first bar runs out he BECOMES the Brute: from then on it's the
	-- Brute talking (his lines below), right after the power-up.
	Tuber = {
		becomes = "Brute",
		wake = { "* Oh! Hi! I'm TUBER! Wanna play?", "* A visitor! Nobody EVER visits my garden!" },
		idle = {
			"* Hehe! That tickles!",
			"* Wanna see me roll? I'm REALLY good at rolling!",
			"* Everyone says I look like a potato. I'm a CACTUS!",
			"* Don't step on my flowers, okay?",
			"* Wheee! Isn't this fun?",
			"* I'm the prickliest cactus in the whole desert! ...I think.",
		},
		hit = { "* Oops! Did I prick you? Sorry!", "* Boing!", "* Hee hee! Gotcha!" },
		win = { "* Aww, are you taking a nap? Night night!", "* Yay, I win! ...Can we play again?" },
		lose = { "* Waaah! No fair!", "* Ow ow ow..." },
	},
	-- THE BRUTE, THE CACTUS KING: huge, cold and very, very royal
	Brute = {
		phase2 = { "* THE DESERT KNEELS. SO WILL YOU.", "* YOU SHOULD HAVE LEFT THE LITTLE ONE ALONE." },
		idle = {
			"* EVERY CACTUS IN THIS DESERT ANSWERS TO ME.",
			"* RUN ALL YOU LIKE. THE SAND IS MINE.",
			"* NOBODY CATCHES A KING.",
			"* MY THORNS HAVE THORNS.",
			"* THE DESERT IS WATCHING. DO TRY TO LAST.",
		},
		hit = { "* PRICKED.", "* KNEEL.", "* THE THORNS WILL REMEMBER YOU." },
		win = { "* THE DUNES CLAIM ANOTHER.", "* LONG LIVE THE CACTUS KING." },
		lose = { "* THE KING... CRUMBLES...", "* NO... NOT... THE LITTLE POTATO AGAIN..." },
	},
	-- a knight of the shovel: cheerful, honourable, and fond of a dig pun
	Burrowmore = {
		wake = {
			"* HALT! I am KNIGHT BURROWMORE, and this dig is MINE!",
			"* En garde, traveller! Let us see what treasure lies beneath your courage!",
		},
		idle = {
			"* A true knight digs deep. In battle AND in dirt.",
			"* Shovel justice! It's a thing. I made it a thing.",
			"* A thousand treasures I have dug up. You shall be the thousand and first!",
			"* Strike true, friend! I would expect no less.",
			"* Ah, the smell of fresh soil and fresh combat!",
			"* Honour before gold. ...Gold is a VERY close second.",
		},
		hit = { "* Shovel drop! Straight to the heart of the matter!", "* Dig it? I did!", "* Ha HA! You've been excavated!" },
		phase2 = { "* NO QUARTER! My armour cracks, but my spirit shines GOLD!", "* You fight with honour! Now face me at my FULLEST!" },
		win = { "* Rest now, brave one. The dirt is soft here.", "* A worthy foe... buried with full honours." },
		lose = { "* You dig... with honour... the treasure... is yours...", "* Well fought! A knight knows when he's been... outdug." },
	},
	-- a wandering fighter: calm, honourable, a little too serious about training
	Kaze = {
		wake = {
			"* The answer lies in the heart of battle. Let us begin!",
			"* I have waited on this mountain for a real challenger. Are you one?",
		},
		idle = {
			"* Your stance is loose. Mine is not.",
			"* Do not swing wildly. Every miss feeds my ki!",
			"* I train at sunrise. I train at sunset. I train at lunch.",
			"* Focus. Breathe. Punch. In that order.",
			"* The wind carries my headband. My fists carry the rest.",
			"* Every fight teaches something. What will this one teach you?",
		},
		hit = { "* Too slow! Read the wind!", "* A true fighter never drops their guard.", "* You must defeat my Rising Dragon to stand a chance!" },
		phase2 = { "* ROUND 2! Now I fight with everything I have!", "* You are strong. Good. Now I will be stronger!" },
		win = { "* Train hard, and come back. I will be here.", "* A good fight! Get up and try again." },
		lose = { "* ...A fine match. The road is yours now.", "* You have beaten me... I must train even harder!" },
	},
	-- a race car: cocky, loud, adores his fans, and the fastest thing on four
	-- wheels (just ask him)
	Revvington = {
		wake = {
			"* Ka-VROOM! Speedy Revvington, fastest car in the whole Spire!",
			"* A challenger? On MY track? Start your engines, slowpoke!",
		},
		idle = {
			"* Rockets are fast. I'm faster. Do the maths.",
			"* My fans came to see me win. Wave to them! ...while you still can.",
			"* Eat my dust! It's premium dust.",
			"* I never brake for anybody. Well. For walls. Sometimes.",
			"* Fifty-seven wins in a row! Want to be number fifty-eight?",
			"* Is that your top speed? Aww. That's adorable.",
		},
		hit = { "* Beep beep! Coming through!", "* Ka-VROOM! You just got lapped!", "* Rubber, meet road. Road, meet YOU!" },
		phase2 = { "* TURBO TIME! Now we're really racing!", "* You scratched my paint! NOBODY scratches the paint!" },
		win = { "* And the crowd goes WILD! Another win for number 57!", "* Checkered flag! Better luck next lap, slowpoke!" },
		lose = { "* You... beat... ME? Somebody check the replay...", "* Sputter... okay, okay... you're pretty fast... for a walker..." },
	},
	-- a living LEVEL: smug, loves his beat, and loves watching you retry
	Gridlock = {
		wake = {
			"* Another attempt? Let's see how far you get this time.",
			"* Welcome to THE FINAL BEAT. Every tile here moves to the music. So should you.",
		},
		idle = {
			"* Feel that? That's the bass. And the bass does NOT like you.",
			"* Jump. Jump. JUMP. ...Too late.",
			"* Stay off the red tiles. Oh wait - they're ALL going to be red.",
			"* I'm a cube. A ship. A UFO. A wave. You're just... you.",
			"* Keep to the beat! Nobody beats the beat.",
			"* 99%? Oh, I LOVE it when they get to 99%.",
		},
		hit = { "* CRASH! Back to 0%!", "* Off the beat! Try again!", "* Spikes: 1. You: 0." },
		phase2 = { "* GRAVITY FLIP! Up is down now. Keep up!", "* Halfway? Then let's turn this level UPSIDE DOWN!" },
		win = { "* ATTEMPT FAILED. Press any key to try again!", "* So close! ...Nah. Not even close." },
		lose = { "* LEVEL... COMPLETE...? But I'm the LAST level...", "* 100%... Nobody gets 100%... GG." },
	},
	-- a gorilla: loud, cocky, loves showing off to his village, and very,
	-- very proud of his tie
	Kongo = {
		wake = {
			"* OOH OOH! Somebody wants to fight the KING OF THE JUNGLE?!",
			"* *YAWN* ...A challenger? In MY clearing? Let's GO!",
		},
		idle = {
			"* Nice tie? Thanks. I've never lost a fight in it.",
			"* The whole village is watching. Don't embarrass yourself!",
			"* Bananas for breakfast, bananas for lunch, YOU for dinner!",
			"* My Giant Punch is winding up... and up... and UP!",
			"* Hear that waterfall? That's the sound of you losing.",
			"* I throw barrels for FUN. Imagine when I'm serious.",
		},
		hit = { "* BONK! Right on the noggin!", "* Ooh ooh! Did that hurt? It looked like it hurt!", "* That's what you get in MY jungle!" },
		phase2 = { "* GRRRR... NOW you've made me go BANANAS!", "* Nobody knocks the King off his feet! NOBODY!" },
		win = { "* OOH OOH! Another win for the King! The village goes wild!", "* Come back when you've had more bananas!" },
		lose = { "* Ooh... ooh... my tie... is all crooked...", "* Okay, okay! You win! ...Want a banana?" },
	},
	-- a flower: sugary sweet (to your face), very proud of her garden, and
	-- never, ever to be trusted
	Petalina = {
		wake = {
			"* Oh! A visitor! Come closer, sweetie~ I don't bite! ...Much.",
			"* *yawn* ...What a lovely morning to squash a little pest~!",
		},
		idle = {
			"* Isn't my garden PRETTY? Please don't step on the tulips~",
			"* I just LOVE the sunshine. And fertilizer. You'd make lovely fertilizer!",
			"* Stop and smell the roses! ...Closer. CLOSER.",
			"* My flytraps are SO hungry today. Aren't they cute?",
			"* A little pollen never hurt anyone! ...Achoo!",
			"* Petals, vines, seeds... I've got a whole bouquet for you!",
		},
		hit = { "* Oopsie! Did my petal cut you? Tee-hee!", "* CHOMP! ...Sorry, sweetie, you looked like a snack!", "* Aww, you've got dirt on you. Your own!" },
		phase2 = { "* You... TRAMPLED... my FLOWERS! Now you'll sleep in the THORNS!", "* No more Miss Nice Flower! Let the weeds grow!" },
		win = { "* Tee-hee! Another little pest in the compost!", "* Come back soon, sweetie! My flytraps miss you already~" },
		lose = { "* My... my petals... I'm... wilting...", "* Water... I need... water... and a little sunshine..." },
	},
	-- a stick figure who knows he's in a video game: cheeky, chatty, and far
	-- too pleased with himself for finding the delete button
	Scribble = {
		wake = {
			"* Oh hey! A player! ...Wait, you can SEE me? Awesome!",
			"* Hold on, let me draw myself in... There! Now let's play!",
		},
		idle = {
			"* I'm just a doodle. A doodle who knows where the DELETE key is.",
			"* Nice health bar. Be a shame if someone... erased it.",
			"* Every time you blink, I redraw myself. Every. Single. Time.",
			"* I read this fight's code. I know every move you'll make!",
			"* CTRL+C, CTRL+V! Two of me means twice the fun!",
			"* You play on a screen. I LIVE on one. Home advantage!",
		},
		hit = { "* Oops! Did I erase you a little?", "* Clicked! You've been clicked!", "* 404: dodge not found!" },
		phase2 = { "* Enough doodling. Let me OUT of this paper!", "* Your screen? It's MY screen now." },
		phase3 = { "* Delete FLOOR 9? ...YES. Definitely YES.", "* ERROR ERROR ERROR... I'm deleting EVERYTHING!" },
		win = { "* GAME OVER! Press any key to try again!", "* Ha! Another player, undone. CTRL+Z!" },
		lose = { "* Hey... you can't just... crumple me... up...", "* Scribble.exe has stopped working. ...Nice one." },
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

-- The bubble follows the boss's head: BossClient measures where that is on
-- your screen (the boss model's HeadAt, fresh while AimTime is); anything
-- else that talks (the Straw King) is measured by its parts. It sits over
-- the head, its tail pointing down at it - or, with no room up there (a tall
-- boss's head up by the boss bar), beside the head, pointing sideways. With
-- the head off your screen (off the top, a side, behind you) it waits at the
-- edge nearest it, its tail tucked away. It never covers the boss bar. Last
-- words stay where they were said (the boss may be melting, falling or
-- flying off by then).
local INK = RGB(24, 20, 37)
local TAIL = 12 -- (how far the tail reaches: the bubble's point is its tip)
local EDGE = 3 -- (the box's ink edge)
local MAX_W = 320 -- (the words wrap past this)
local BOTTOM_SAFE, SIDE = 110, 12 -- (the bottom of your screen, its sides: kept clear)
local topSafe = 150 -- (under the boss bar: worked out when the bubble's made)
local talkGui, bubble, box, words, tag, tagText, pop
local tails = {} -- down / left / right: which way it points
local speaking = nil -- the line up now: { model, spot (last words' fixed spot), last }

local function buildTalk()
	pcall(function()
		-- (the boss bar sits 58 pixels under Roblox's top bar, 46 tall)
		topSafe = game:GetService("GuiService"):GetGuiInset().Y + 58 + 46 + 10
	end)
	talkGui = new("ScreenGui", { Name = "BossTalk", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Enabled = false }, playerGui)
	talkGui:SetAttribute("RetroSkip", true)
	-- (placed by its point - the tip of its tail - with the box beside that)
	bubble = new("Frame", { Name = "Bubble", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0) }, talkGui)
	pop = new("UIScale", { Scale = 1 }, bubble)
	box = new("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(0, -TAIL),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, bubble)
	new("UIStroke", { Color = INK, Thickness = EDGE, LineJoinMode = Enum.LineJoinMode.Miter }, box)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 9) }, box)
	-- (sized to the whole line before it types - see fitWords - so the bubble
	-- doesn't grow and re-wrap letter by letter)
	words = new("TextLabel", {
		Name = "Words",
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Arcade,
		TextSize = 20,
		TextColor3 = INK,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	}, box)
	new("UISizeConstraint", { MaxSize = Vector2.new(MAX_W, math.huge) }, words)
	-- its name, on a tag in its colour over the top-left corner (the box's
	-- padding moves what's in it, so these offsets start inside that)
	tag = new("Frame", {
		Name = "Tag",
		Position = UDim2.fromOffset(-12 + 8, -14 - 11),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, box)
	new("UIStroke", { Color = INK, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Miter }, tag)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tag)
	tagText = new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.Arcade,
		TextSize = 16,
		TextColor3 = WHITE,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0,
		ZIndex = 4,
	}, tag)
	-- the tails: a stepped 8-bit point, ink with white inside, cutting a gap
	-- in the box's edge so the two are one shape. Each is drawn from its tip
	-- (0, 0): pixels from x0,y0 to x1,y1.
	local function tail(name, bars)
		local t = new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), ZIndex = 5, Visible = false }, bubble)
		for _, b in ipairs(bars) do
			new("Frame", {
				Position = UDim2.fromOffset(b[2], b[3]),
				Size = UDim2.fromOffset(b[4] - b[2], b[5] - b[3]),
				BackgroundColor3 = b[1],
				BorderSizePixel = 0,
				ZIndex = b[1] == WHITE and 2 or 1,
			}, t)
		end
		return t
	end
	tails.down = tail("TailDown", {
		{ INK, -2, -3, 2, 0 }, { INK, -5, -6, 5, -3 }, { WHITE, -2, -6, 2, -3 },
		{ INK, -8, -9, 8, -6 }, { WHITE, -5, -9, 5, -6 }, { WHITE, -5, -TAIL - 1, 5, -9 },
	})
	tails.left = tail("TailLeft", { -- (the box to its right)
		{ INK, 0, -2, 3, 2 }, { INK, 3, -5, 6, 5 }, { WHITE, 3, -2, 6, 2 },
		{ INK, 6, -8, 9, 8 }, { WHITE, 6, -5, 9, 5 }, { WHITE, 9, -5, TAIL + 1, 5 },
	})
	tails.right = tail("TailRight", { -- (the box to its left)
		{ INK, -3, -2, 0, 2 }, { INK, -6, -5, -3, 5 }, { WHITE, -6, -2, -3, 2 },
		{ INK, -9, -8, -6, 8 }, { WHITE, -9, -5, -6, 5 }, { WHITE, -TAIL - 1, -5, -9, 5 },
	})
end

-- where to hang a talker's words: just over its head
local function headOf(model)
	if not (model and model.Parent) then
		return nil
	end
	local head, stamp = model:GetAttribute("HeadAt"), model:GetAttribute("AimTime")
	if typeof(head) == "Vector3" and type(stamp) == "number" and os.clock() - stamp < 0.5 then
		return head + Vector3.new(0, 1.2, 0)
	end
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf and size then
		return cf.Position + Vector3.new(0, size.Y / 2 + 1.2, 0)
	end
	return nil
end

-- its colour, for the tag: a Spire boss's own, or the Straw King's gold
local function colorOf(model)
	local floor = model and model:GetAttribute("Floor")
	local def = floor and Config.Bosses and Config.Bosses[floor]
	return (def and def.Color) or RGB(254, 174, 52)
end

-- how big the box is, inside its ink edge (laid out by Roblox a frame late:
-- until then, a guess from the words)
local function boxSize()
	local s = box.AbsoluteSize
	if s and s.X > 1 then
		local k = math.max(pop.Scale, 0.05) -- (not shrunk by its pop-in)
		return s.X / k, s.Y / k
	end
	local n = utf8.len(words.Text) or #words.Text
	local perLine = math.floor(MAX_W / 10)
	return math.min(n, perLine) * 10 + 24, math.ceil(n / perLine) * 20 + 23
end

-- the words' size, laid out in full (wrapped at MAX_W)
local function fitWords(text)
	local ok, size = pcall(function()
		return game:GetService("TextService"):GetTextSize(text, words.TextSize, words.Font, Vector2.new(MAX_W, 10000))
	end)
	local w, h
	if ok and typeof(size) == "Vector2" then
		w, h = size.X, size.Y
	else
		local n = utf8.len(text) or #text
		local perLine = math.floor(MAX_W / 10)
		w, h = math.min(n, perLine) * 10, math.ceil(n / perLine) * 20
	end
	words.Size = UDim2.fromOffset(math.ceil(w) + 2, math.ceil(h))
end

local function pointing(which)
	for name, t in pairs(tails) do
		t.Visible = name == which
	end
end

-- every frame while it talks: by its head, kept on your screen
local function placeBubble()
	local line = speaking
	local spot = line.spot or headOf(line.model)
	if spot then
		line.last = spot
	else
		spot = line.last
	end
	local cam = workspace.CurrentCamera
	local screen = cam and cam.ViewportSize
	if not (screen and spot) then
		-- (no camera, or nothing to hang it on: it waits near the top)
		bubble.Position = UDim2.new(0.5, 0, 0, topSafe + 90)
		box.AnchorPoint = Vector2.new(0.5, 1)
		box.Position = UDim2.fromOffset(0, -TAIL)
		pointing(nil)
		return
	end
	local vw, vh = screen.X, screen.Y
	local w, h = boxSize()
	local lowest = vh - BOTTOM_SAFE
	local function keepX(cx)
		local a = SIDE + EDGE + w / 2
		return math.clamp(cx, a, math.max(a, vw - a))
	end
	local function keepY(cy)
		local a = topSafe + EDGE + h / 2
		return math.clamp(cy, a, math.max(a, lowest - h / 2))
	end
	local p = cam:WorldToViewportPoint(spot)
	local x, y = p.X, p.Y
	local seen = p.Z > 0 and x >= 0 and x <= vw and y <= lowest
	if seen and y - TAIL - h - EDGE >= topSafe then
		-- room over its head: the box on top, the tail pointing down at it
		local cx = keepX(x)
		bubble.Position = UDim2.fromOffset(x, y)
		box.AnchorPoint = Vector2.new(0.5, 1)
		box.Position = UDim2.fromOffset(cx - x, -TAIL)
		pointing(math.abs(cx - x) <= w / 2 - 14 and "down" or nil)
	elseif seen and y >= 0 then
		-- its head's up by the boss bar: the box beside it, pointing at it
		local toRight = x + TAIL + w + EDGE + SIDE <= vw or x < vw / 2
		local cy = keepY(y)
		bubble.Position = UDim2.fromOffset(x, y)
		box.AnchorPoint = Vector2.new(toRight and 0 or 1, 0.5)
		box.Position = UDim2.fromOffset(toRight and TAIL or -TAIL, cy - y)
		pointing(math.abs(cy - y) <= h / 2 - 12 and (toRight and "left" or "right") or nil)
	else
		-- off your screen: at the edge nearest it (behind you: the side it's on)
		if p.Z <= 0 then
			local side = cam.CFrame.RightVector:Dot(spot - cam.CFrame.Position)
			x, y = side >= 0 and vw or 0, vh * 0.45
		end
		bubble.Position = UDim2.fromOffset(keepX(x), keepY(y))
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromOffset(0, 0)
		pointing(nil)
	end
end
RunService.RenderStepped:Connect(function()
	if speaking and talkGui and talkGui.Enabled then
		placeBubble()
	end
end)

local function say(short, kind, model)
	local set = LINES[short]
	local list = set and set[kind]
	if not list or R.BossTalk == false then
		return
	end
	if not talkGui then
		buildTalk()
	end
	-- (the lines were written for a box, each starting with Undertale's star:
	-- a bubble doesn't need it)
	local text = (string.gsub(list[math.random(#list)], "^%*%s*", ""))
	local me = { model = model, spot = kind == "lose" and headOf(model) or nil }
	speaking = me
	tagText.Text = string.upper(short)
	local c = colorOf(model)
	tag.BackgroundColor3 = c
	-- (a pale colour - Kaze's white - gets dark letters)
	local pale = c.R * 0.3 + c.G * 0.59 + c.B * 0.11 > 0.75
	tagText.TextColor3 = pale and INK or WHITE
	tagText.TextStrokeTransparency = pale and 1 or 0
	words.Text = text
	fitWords(text)
	words.MaxVisibleGraphemes = 0
	talkGui.Enabled = true
	placeBubble()
	pop.Scale = 0.3
	tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	task.spawn(function()
		local n = utf8.len(text) or #text
		for i = 1, n do
			if speaking ~= me then
				return
			end
			words.MaxVisibleGraphemes = i
			if i % 2 == 0 then
				sound(R.TypeBlip or "UI Blip")
			end
			task.wait(1 / 32)
		end
		words.MaxVisibleGraphemes = -1
		task.wait(3)
		if speaking == me then
			tween(pop, 0.14, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.15)
			if speaking == me then
				talkGui.Enabled = false
				speaking = nil
			end
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
			task.delay(2.6, say, def.Short, "wake", model) -- (just after the VS splash)
		elseif st == "Dead" then
			say((current and current.short) or def.Short, "lose", model)
			current = nil
		elseif st == "Dormant" or st == "Resetting" then
			current = nil
		end
	end)
	model:GetAttributeChangedSignal("Phase"):Connect(function()
		local def = onMyFloor()
		if def and model:GetAttribute("Phase") == 2 then
			local becomes = LINES[def.Short] and LINES[def.Short].becomes
			if becomes and LINES[becomes] then
				-- (Tuber: from now on it's the Brute talking - his first words
				-- once the power-up is over)
				if current then
					current.short = becomes
				end
				local wait = def.BreakTime or 0
				nextIdle = os.clock() + wait + 12
				task.delay(wait, function()
					if current and current.short == becomes then
						say(becomes, "phase2", model)
					end
				end)
			else
				say(def.Short, "phase2", model)
				nextIdle = os.clock() + 12
			end
		elseif def and model:GetAttribute("Phase") == 3 then
			-- (a boss with a third round: Scribble)
			say(def.Short, "phase3", model)
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
		say(current.short, "idle", current.model)
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
			say(current.short, "hit", current.model)
		end
	end)
	hum.Died:Connect(function()
		if current then
			say(current.short, "win", current.model)
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
					task.delay(2.6, say, kingDef.Short, "wake", model) -- (just after the VS splash)
				else
					task.delay(0.4, say, kingDef.Short, "wake", model)
				end
			elseif st == "Dead" then
				say(kingDef.Short, "lose", model)
				if current and current.model == model then
					current = nil
				end
			end
		end)
		model:GetAttributeChangedSignal("Phase"):Connect(function()
			if model:GetAttribute("Phase") == 2 then
				say(kingDef.Short, "phase2", model)
				nextIdle = os.clock() + 12
			end
		end)
		model:GetAttributeChangedSignal("Move"):Connect(function()
			if model:GetAttribute("Move") == "Summon" and not speaking then
				say(kingDef.Short, "summon", model)
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
