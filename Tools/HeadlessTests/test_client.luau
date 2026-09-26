--!nocheck
-- Headless test of the Colosseum's screen side: LobbyActivities (boss bar,
-- banners, shakes, sounds, music, the quest tab, the coins and XP flying into
-- you, the CLEARED screen, the difficulty pop-up at the Colosseum's door) and
-- BossIntro (VS splash, talking), fed a fake King and fake server messages.
local M = require("./rbxmock")
local S = require("./sources")
local Vector3, CFrame, Instance, Enum = M.Vector3, M.CFrame, M.Instance, M.Enum
local ReplicatedStorage = M.services.ReplicatedStorage
local SoundService = M.services.SoundService
local Players = M.services.Players
local RunService = M.services.RunService
local workspace = M.workspace
local task = M.task

local configModule = Instance.new("ModuleScript")
configModule.Name = "Config"
configModule.Parent = ReplicatedStorage
local Config
local env = M.env({
	require = function(mod)
		if mod == configModule then
			return Config
		end
		error("require of unknown module " .. tostring(mod))
	end,
})
Config = M.load(S.Config, "Config", env)()
local K = Config.Colosseum.King

-- the local player
local player = Instance.new("Player")
player.Name = "Tester"
player.UserId = 1001
player.DisplayName = "Tester"
player.Parent = Players
Players.LocalPlayer = player
M.players = { player }
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local playerScripts = Instance.new("PlayerScripts")
playerScripts.Name = "PlayerScripts"
playerScripts.Parent = player
local kicks, kickTotal = 0, 0
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = playerScripts
kick.Event:Connect(function(strength)
	assert(type(strength) == "number" and strength == strength and strength > 0, "bad camera kick " .. tostring(strength))
	kicks += 1
	kickTotal += strength
end)

-- remotes the scripts wait for
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "StateUpdate", "RequestState" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes
local colosseumEvent = Instance.new("RemoteEvent")
colosseumEvent.Name = "ColosseumEvent"
colosseumEvent.Parent = ReplicatedStorage
local enemies = Instance.new("Folder")
enemies.Name = "ColosseumEnemies"
enemies.Parent = workspace

-- sounds the user has (the King borrows the Spire bosses')
local played = {}
local function addSound(name)
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.Volume = 0.5
	snd.Parent = SoundService
end
for _, n in ipairs({ "Boss Slam", "Boss Wake", "Boss Wail", "Boss Wave", "Boss Death", "Slime boss song", "Victory Is Ours (a) Sting", "UI Blip", "mario pipe" }) do
	addSound(n)
end
local MUSIC = (Config.Audio and Config.Audio.Music) or 1 -- (the lobby music's normal volume)
local lobbyGroup = Instance.new("SoundGroup")
lobbyGroup.Name = "Music"
lobbyGroup.Volume = MUSIC
lobbyGroup.Parent = SoundService
SoundService.ChildAdded:Connect(function(c)
	if c:IsA("Sound") then
		table.insert(played, c.Name)
	end
end)

-- run both scripts
task.spawn(M.load(S.LobbyActivities, "LobbyActivities", env))
task.spawn(M.load(S.BossIntro, "BossIntro", env))

local t = 0
local function step(seconds)
	local stop = t + seconds
	while t < stop do
		t += 1 / 60
		M.run(t)
		RunService.RenderStepped:Fire(1 / 60)
		RunService.Heartbeat:Fire(1 / 60)
	end
end
step(0.5)
local function fire(...)
	colosseumEvent.OnClientEvent:Fire(...)
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end
player:SetAttribute("Colosseum", true)
fire("Arrived")
fire("State", { wave = 5, boss = true, left = 1, quest = 3, goal = 10, questPower = 100, questCoins = 50 })
step(0.2)
local hud = playerGui:FindFirstChild("ColosseumHud")
assert(hud and hud.Enabled, "the Colosseum HUD should be on")
local waveText = nil
for _, d in ipairs(hud:GetDescendants()) do
	if d.ClassName == "TextLabel" and d.Text == "BOSS WAVE" then
		waveText = d
	end
end
assert(waveText, "the wave box should say BOSS WAVE")

fire("BossWave", 5)
step(0.1)
-- the King arrives
local king = Instance.new("Model")
king.Name = "Giant Straw King"
local torso = Instance.new("Part")
torso.Name = "Torso"
torso.CFrame = CFrame.new(-2600, 12.4, 0)
torso.Parent = king
king.PrimaryPart = torso
for k, v in pairs({ Kind = "King", Owner = 1001, Level = 40, MaxHealth = 1000, Health = 1000, State = "Arriving", Phase = 1, NoBar = true, Boss = true, Invulnerable = true }) do
	king:SetAttribute(k, v)
end
king.Parent = enemies
step(0.3)
local bar = playerGui:FindFirstChild("ColosseumBossBar")
assert(bar and bar.Enabled, "the boss bar should show when he arrives")
assert(bar:GetAttribute("RetroSkip") == true, "the bar styles itself")

-- he lands (a big shake), roars, the VS splash plays
local root = Instance.new("Part")
local char = Instance.new("Model")
root.Name = "HumanoidRootPart"
root.CFrame = CFrame.new(-2600, 3, -40)
root.Parent = char
local hum = Instance.new("Humanoid")
hum.Parent = char
char.PrimaryPart = root
char.Parent = workspace
player.Character = char
fire("KingFx", "Land", Vector3.new(-2600, 0, 0), 1.6)
step(0.1)
assert(kicks == 1, "his landing should shake the camera")
king:SetAttribute("State", "Waking")
fire("KingFx", "Roar", Vector3.new(-2600, 0, 0), 0.6)
step(0.3)
assert(playerGui:FindFirstChild("BossIntro"), "the VS splash should play the first time")
step(3)
assert(not playerGui:FindFirstChild("BossIntro"), "the VS splash should be gone after it plays")
king:SetAttribute("Invulnerable", nil)
king:SetAttribute("State", "Fighting")
step(1.5)
local music = SoundService:FindFirstChild("KingMusicPlaying")
assert(music, "his music should play (borrowing the slime's song)")
assert(lobbyGroup.Volume < 0.3, "the lobby music should step aside: " .. lobbyGroup.Volume)
local talk = playerGui:FindFirstChild("BossTalk")
assert(talk, "he should talk (wake line)")

-- hits: the bar drops, with the pale chunk trailing
king:SetAttribute("Health", 600)
step(0.1)
local fill, chip
local back = nil
for _, d in ipairs(bar:GetDescendants()) do
	if d.ClassName == "Frame" and d.Size and d.Size.X and d.Size.X.Scale == 0.6 and d.Size.Y.Scale == 1 then
		fill = d
	end
end
assert(fill, "the bar's fill should be at 60%")
step(2)
-- summon: he shouts for his minions
king:SetAttribute("Move", "Summon")
fire("KingFx", "Summon", Vector3.new(-2600, 0, 0))
step(0.5)
king:SetAttribute("Move", nil)
-- he gets angry
king:SetAttribute("Health", 450)
king:SetAttribute("Phase", 2)
fire("KingRage")
fire("KingFx", "Roar", Vector3.new(-2600, 0, 0), 0.9)
step(1)
fire("KingFx", "Spin", Vector3.new(-2600, 0, 0))
fire("KingFx", "Step", Vector3.new(-2610, 0, 0), 0.35)
step(0.5)
-- beaten!
king:SetAttribute("Health", 0)
king:SetAttribute("State", "Dead")
fire("Kill", 15075, 660, Vector3.new(-2600, 25, 0))
fire("KingDown", 15075, 660)
fire("KingFx", "Death", Vector3.new(-2600, 0, 0), 1)
fire("WaveClear", 5)
step(0.2)
local bannerText = nil
for _, d in ipairs(hud:GetDescendants()) do
	if d.ClassName == "TextLabel" and type(d.Text) == "string" and string.find(d.Text, "FALLS") then
		bannerText = d.Text
	end
end
assert(bannerText, "the KING FALLS banner should be up (not replaced by WAVE CLEARED)")
step(2.5)
assert(not bar.Enabled, "the bar should go after he's beaten")
king:Destroy()
step(3)
assert(not SoundService:FindFirstChild("KingMusicPlaying"), "his music should fade out and stop")
assert(math.abs(lobbyGroup.Volume - MUSIC) < 1e-6, "the lobby music should come back: " .. lobbyGroup.Volume)

-- the next King (a second meeting): no VS splash, but the bar and his talk
fire("State", { wave = 10, boss = true, left = 1, quest = 3, goal = 10, questPower = 100, questCoins = 50 })
local king2 = king:Clone()
king2:SetAttribute("Health", 1000)
king2:SetAttribute("State", "Arriving")
king2:SetAttribute("Phase", 1)
king2.Parent = enemies
step(0.3)
assert(bar.Enabled, "the bar should come back for the next King")
king2:SetAttribute("State", "Waking")
step(0.3)
assert(not playerGui:FindFirstChild("BossIntro"), "the splash only plays once per visit")
-- someone else's King: ignored
local other = king:Clone()
other:SetAttribute("Owner", 2002)
other.Parent = enemies
step(0.2)

-- leaving mid-fight: he's destroyed, everything calms down
king2:Destroy()
player:SetAttribute("Colosseum", nil)
step(4)
assert(not bar.Enabled, "the bar should go when you leave")
assert(math.abs(lobbyGroup.Volume - MUSIC) < 1e-6, "the lobby music should be back")

-- WARMING UP: the Colosseum's sounds were preloaded after joining
local warmed = {}
for _, a in ipairs(M.preloaded) do
	if M.typeof(a) == "Instance" then
		warmed[a.Name] = true
	end
end
assert(warmed["mario pipe"] and warmed["Boss Slam"] and warmed["Slime boss song"] and warmed["UI Blip"], "the Colosseum's sounds should be warmed up")
-- THE PIPE: the Mario pipe sound going in and coming out
local before = #played
player:SetAttribute("Colosseum", nil)
fire("PipeIn", Vector3.new(-14.6, 0, 90), CFrame.new(-2600, 3, -60), Vector3.new(-2600, 0, -60))
step(1.5)
fire("PipeOut", CFrame.new(-14.6, 3, 95), Vector3.new(-14.6, 0, 95))
step(1.5)
local pipes = 0
for i = before + 1, #played do
	if played[i] == "mario pipe" then
		pipes += 1
	end
end
assert(pipes == 2, "the pipe sound should play going in and coming out: " .. pipes)

-- RUNS AND STREAKS: the streak box, and the COLOSSEUM CLEARED screen
player:SetAttribute("Colosseum", true)
fire("State", { wave = 3, of = 5, streak = 12, streakBonus = 0.2, left = 3, quest = 3, goal = 10, questPower = 100, questCoins = 50 })
step(0.1)
local streakText, waveNow = nil, nil
for _, d in ipairs(hud:GetDescendants()) do
	if d.ClassName == "TextLabel" and type(d.Text) == "string" then
		if string.find(d.Text, "STREAK") then
			streakText = d.Text
		elseif string.find(d.Text, "^WAVE") then
			waveNow = d.Text
		end
	end
end
assert(streakText == "x12 STREAK  +20%", "streak box: " .. tostring(streakText))
assert(waveNow == "WAVE 3/5", "wave box: " .. tostring(waveNow))
fire("Streak", 15, 0.3)
fire("StreakLost", 15)
step(0.2)
local asked = {}
M.onInvokeServer = function(remote, name)
	table.insert(asked, name)
	return true, "ok"
end
fire("RunClear", { time = 146.2, best = 140.5, newBest = false, clears = 3, bonusPower = 4000, bonusCoins = 750 })
step(1)
local clear = playerGui:FindFirstChild("ColosseumClear")
assert(clear and not clear.Enabled, "the clear screen waits a moment (the King's banner first)")
step(3)
assert(clear.Enabled, "the clear screen should open")
local texts = {}
for _, d in ipairs(clear:GetDescendants()) do
	if d.ClassName == "TextLabel" then
		texts[#texts + 1] = d.Text
	end
end
local all = table.concat(texts, " | ")
print("clear screen: " .. all)
assert(string.find(all, "TIME  2:26.2", 1, true), "time shown")
assert(string.find(all, "BEST  2:20.5", 1, true), "best shown")
assert(string.find(all, "RUNS CLEARED: 3", 1, true), "clears shown")
assert(string.find(all, "FIRST CLEAR TODAY", 1, true), "bonus shown")
local again = find(clear, "ColosseumAgain")
again.Activated:Fire()
step(0.2)
assert(asked[1] == "ColosseumAgain" and not clear.Enabled, "RUN AGAIN asks the server and closes")
fire("RunStart")
-- a new best, then LEAVE
fire("RunClear", { time = 120, best = 120, newBest = true, clears = 4 })
step(4)
assert(clear.Enabled, "opens again")
find(clear, "ColosseumLeave").Activated:Fire()
step(0.2)
assert(asked[2] == "ColosseumLeave" and not clear.Enabled, "LEAVE asks the server and closes")
-- the server says no: it stays open with the reason
M.onInvokeServer = function()
	return false, "Walk out through the exit gate."
end
fire("RunClear", { time = 99, clears = 5 })
step(4)
find(clear, "ColosseumAgain").Activated:Fire()
step(0.2)
assert(clear.Enabled, "stays open if the server says no")
player:SetAttribute("Colosseum", nil)
step(0.1)
assert(not clear.Enabled, "closes when you leave")

-- THE COLOSSEUM'S SOUNDS: dummy sounds on "Sfx", the horn, cheers, reward pops,
-- the quest, and the farming music + crowd while inside (lobby music ducked)
for _, n in ipairs({ "Dummy Land", "Dummy Slam", "Dummy poof", "Brute Charge", "Hay Throw", "Hay Landing", "Shield Clang",
	"Cursed Blink", "Wave Horn", "Crowd Cheer", "Reward Pop", "Quest Complete", "Colosseum Crowd", "Colosseum Song" }) do
	addSound(n)
end
local mark = #played
player:SetAttribute("Colosseum", true)
step(2)
assert(SoundService:FindFirstChild("ColosseumMusicPlaying"), "the Colosseum song should play inside")
assert(SoundService:FindFirstChild("ColosseumCrowdPlaying"), "the crowd should murmur inside")
assert(lobbyGroup.Volume < 0.3, "the lobby music steps aside for the Colosseum song: " .. lobbyGroup.Volume)
for _, key in ipairs({ "Land", "Slam", "Poof", "Charge", "Throw", "HayLand", "Clang", "Blink" }) do
	fire("Sfx", key, Vector3.new(-2600, 0, -30))
end
fire("Wave", 2)
fire("Kill", 10, 5, Vector3.new(-2600, 10, -30))
fire("WaveClear", 2)
fire("QuestDone", 100, 50)
fire("Sfx", "NoSuchSound", Vector3.new(0, 0, 0)) -- (unknown: nothing, no error)
step(0.5)
local heard = {}
for i = mark + 1, #played do
	heard[played[i]] = true
end
for _, n in ipairs({ "Dummy Land", "Dummy Slam", "Dummy poof", "Brute Charge", "Hay Throw", "Hay Landing", "Shield Clang",
	"Cursed Blink", "Wave Horn", "Crowd Cheer", "Reward Pop", "Quest Complete" }) do
	assert(heard[n], "should have heard " .. n)
end
player:SetAttribute("Colosseum", nil)
step(4)
assert(not SoundService:FindFirstChild("ColosseumMusicPlaying") and not SoundService:FindFirstChild("ColosseumCrowdPlaying"), "music and crowd stop when you leave")
assert(math.abs(lobbyGroup.Volume - MUSIC) < 1e-6, "the lobby music comes back")

-- THE QUEST: BEAT 5 WAVES, one chunky block per wave
player:SetAttribute("Colosseum", true)
fire("State", { wave = 3, of = 5, left = 4, quest = 2, goal = 5, diff = "Normal", pick = "Normal", questPower = 500, questCoins = 300 })
step(0.1)
local tab = find(hud, "QuestTab")
local tabTexts = {}
for _, d in ipairs(tab:GetDescendants()) do
	if d.ClassName == "TextLabel" then
		tabTexts[#tabTexts + 1] = d.Text
	end
end
local tabAll = table.concat(tabTexts, " | ")
print("quest tab: " .. tabAll)
assert(string.find(tabAll, "Beat 5 Waves", 1, true) and string.find(tabAll, "(2/5)", 1, true), "the quest tab says Beat 5 Waves (2/5)")
local blocks = 0
for _, d in ipairs(tab:GetDescendants()) do
	if d.ClassName == "Frame" and d.Parent and d.Parent.Parent == tab and d.Size.X.Scale > 0.19 and d.Size.X.Scale < 0.21 then
		blocks += 1
	end
end
assert(blocks == 5, "five blocks, one per wave: " .. blocks)
fire("State", { wave = 5, of = 5, cleared = true, left = 0, quest = 5, goal = 5, diff = "Normal", questPower = 500, questCoins = 300 })
step(0.1)
local doneText = nil
for _, d in ipairs(tab:GetDescendants()) do
	if d.ClassName == "TextLabel" and string.find(d.Text, "DONE", 1, true) then
		doneText = d.Text
	end
end
assert(doneText == "(5/5)  DONE!", "a cleared run's quest shows DONE: " .. tostring(doneText))

-- THE WAVE BOX on a harder difficulty: its name after the wave, in its colour
fire("State", { wave = 3, of = 5, left = 4, quest = 2, goal = 5, diff = "Hard", pick = "Hard", questPower = 1000, questCoins = 600 })
step(0.1)
local waveHard = nil
for _, d in ipairs(hud:GetDescendants()) do
	if d.ClassName == "TextLabel" and type(d.Text) == "string" and string.find(d.Text, "^WAVE") then
		waveHard = d
	end
end
local hardDef = Config.colosseumDifficulty("Hard")
assert(waveHard and waveHard.RichText and string.find(waveHard.Text, "WAVE 3/5  <font color=\"#", 1, true) and string.find(waveHard.Text, "HARD</font>", 1, true),
	"the wave box shows HARD: " .. tostring(waveHard and waveHard.Text))
assert(waveHard.Parent.Size.X.Offset == 260, "the wave box widens for its name")
fire("RunStart", "Hard")
step(0.1)
local runBanner = nil
for _, d in ipairs(hud:GetDescendants()) do
	if d.ClassName == "TextLabel" and d.Text == "HARD RUN BEGINS!" then
		runBanner = d
	end
end
assert(runBanner and runBanner.TextColor3 == hardDef.color, "a Hard run starts with its banner, in its colour")

-- THE COINS AND XP flying into you (and bumping the HUD's coin and level bar)
local fakeHud = Instance.new("ScreenGui")
fakeHud.Name = "BossGrowHud"
fakeHud.Parent = playerGui
local hudRoot = Instance.new("Frame")
hudRoot.Name = "Root"
hudRoot.Parent = fakeHud
local stats = Instance.new("Frame")
stats.Name = "Stats"
stats.Parent = hudRoot
local row = Instance.new("Frame")
row.Parent = stats
local coinIcon = Instance.new("Frame")
coinIcon.Name = "Coin"
coinIcon.Parent = row
local goalBar = Instance.new("Frame")
goalBar.Name = "GoalBar"
goalBar.Parent = hudRoot
root.CFrame = CFrame.new(-2600, 3, -40)
M.raycast = function(origin, dir)
	if origin.Y >= 0 and origin.Y + dir.Y <= 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z) }
	end
	return nil
end
local markTicks = #played
fire("Kill", 2010, 88, Vector3.new(-2600, 11, -20), { from = Vector3.new(-2600, 4, -20), worth = 2, king = false })
step(1 / 30)
local fx = workspace:FindFirstChild("RewardFx")
assert(fx, "the rewards burst out of the dummy")
local coins, gems = 0, 0
for _, p in ipairs(fx:GetChildren()) do
	if p.Name == "Coin" then
		coins += 1
	elseif p.Name == "XPGem" then
		gems += 1
	end
	assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch, "reward pieces can't be touched or stood on")
end
print(string.format("a kill worth 2: %d coins, %d gems", coins, gems))
assert(coins >= 3 and gems >= 2, "coins and XP gems both fly")
local sawBump, sawBar = false, false
for _ = 1, 150 do
	step(1 / 60)
	local sc = coinIcon:FindFirstChild("CollectPop")
	if sc and sc.Scale > 1.01 then
		sawBump = true
	end
	local sb = goalBar:FindFirstChild("CollectPop")
	if sb and sb.Scale > 1.001 then
		sawBar = true
	end
end
assert(#fx:GetChildren() == 0, "every piece reaches you (none left flying)")
assert(sawBump and sawBar, "the coin counter and the level bar bump as they land")
step(0.3)
assert(coinIcon:FindFirstChild("CollectPop").Scale == 1, "the bump settles back")
local ticks = 0
for i = markTicks + 1, #played do
	if played[i] == "Reward Pop" then
		ticks += 1
	end
end
print("reward sounds for one kill (the pop + the ticks): " .. ticks)
assert(ticks >= 3 and ticks <= coins + gems + 1, "each landing ticks, but not all at once")
-- the King's shower is big; leaving clears whatever's still flying
fire("Kill", 30150, 1320, Vector3.new(-2600, 25, -10), { from = Vector3.new(-2600, 9, -10), worth = 30, king = true })
step(1 / 30)
local kingPieces = #fx:GetChildren()
print("the King's shower: " .. kingPieces .. " pieces")
assert(kingPieces >= 35, "the King bursts into a big shower")
fire("Left")
step(0.1)
assert(#fx:GetChildren() == 0, "leaving clears the shower")

-- THE POP-UP AT THE DOOR: press E at the mini colosseum's little door, pick
-- how hard, press ENTER
local enterAnswer = { true, "In you go!" }
M.onInvokeServer = function(remote, name, arg)
	table.insert(asked, name .. ":" .. tostring(arg))
	if name == "ColosseumDifficulty" then
		return true, Config.colosseumDifficulty(arg).name .. " it is!"
	elseif name == "ColosseumEnter" then
		return enterAnswer[1], enterAnswer[2]
	end
	return true, "ok"
end
table.clear(asked)
player:SetAttribute("Colosseum", nil)
local GATE = Config.Colosseum.GatePosition
local door = Instance.new("Part")
door.Name = "Doorway"
door.CFrame = CFrame.new(GATE + Vector3.new(0, 3, 0))
door.Parent = workspace
local doorPrompt = Instance.new("ProximityPrompt")
doorPrompt.Parent = door
M.services.CollectionService:AddTag(doorPrompt, "ColosseumEntrance")
remotes.StateUpdate.OnClientEvent:Fire({ Quests = { day = 0, list = {} }, Colosseum = { clears = 1, pick = "Normal", wins = { Normal = 1 }, bests = { Normal = 150.5 } } })
root.CFrame = CFrame.new(GATE + Vector3.new(4, 3, 0))
step(0.2)
local menu = playerGui:FindFirstChild("ColosseumDifficulty")
assert(menu and not menu.Enabled, "the pop-up waits for the door")
doorPrompt.Triggered:Fire(player)
step(0.1)
assert(menu.Enabled, "pressing E at the door pops up the difficulty menu")
assert(#asked == 0, "opening it doesn't ask the server anything")
local function cardText(id)
	local card = find(menu, "Card" .. id)
	local list = {}
	for _, d in ipairs(card:GetDescendants()) do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Text ~= "" then
			list[#list + 1] = d.Text
		end
	end
	return table.concat(list, " | ")
end
local function menuSays(text)
	for _, d in ipairs(menu:GetDescendants()) do
		if d.ClassName == "TextLabel" and string.find(d.Text, text, 1, true) then
			return true
		end
	end
	return false
end
print("Normal card: " .. cardText("Normal"))
print("Hard card: " .. cardText("Hard"))
print("Nightmare card: " .. cardText("Nightmare"))
assert(string.find(cardText("Normal"), "PICKED", 1, true) and string.find(cardText("Normal"), "BEST 2:30.5", 1, true), "Normal: picked (it's saved), with its best time")
assert(string.find(cardText("Hard"), "PICK", 1, true) and string.find(cardText("Hard"), "PAYS x2", 1, true), "Hard: open to pick, pays x2")
assert(string.find(cardText("Nightmare"), "LOCKED", 1, true), "Nightmare: locked")
local enterButton = find(menu, "Enter")
assert(enterButton and enterButton.Text == "ENTER", "a big ENTER button")
assert(enterButton.BackgroundColor3 == Config.colosseumDifficulty("Normal").color, "ENTER is in the picked one's colour")
-- a locked one says what opens it, without asking the server
find(find(menu, "CardNightmare"), "Pick").Activated:Fire()
step(0.1)
assert(#asked == 0, "a locked pick doesn't ask the server")
assert(menuSays("Clear a HARD run"), "a locked pick says what opens it")
assert(not string.find(cardText("Nightmare"), "PICKED", 1, true), "a locked one can't be picked")
-- clicking Hard's card picks it, here on the screen (nothing asked yet)
find(find(menu, "CardHard"), "CardButton").Activated:Fire()
step(0.1)
assert(#asked == 0, "picking in the pop-up waits for ENTER")
assert(string.find(cardText("Hard"), "PICKED", 1, true) and not string.find(cardText("Normal"), "PICKED", 1, true), "Hard shows PICKED, Normal doesn't")
assert(enterButton.BackgroundColor3 == Config.colosseumDifficulty("Hard").color, "ENTER turns Hard's colour")
-- the server says no: it stays open, with the reason
enterAnswer = { false, "Walk up to the Colosseum's door first." }
enterButton.Activated:Fire()
step(0.2)
assert(asked[1] == "ColosseumEnter:Hard", "ENTER asks to go in on Hard: " .. tostring(asked[1]))
assert(menu.Enabled and menuSays("Walk up to the Colosseum's door first."), "a refusal leaves it open, saying why")
assert(enterButton.Text == "ENTER", "ENTER can be pressed again")
-- the server says yes: it closes (the pipe does the rest)
enterAnswer = { true, "In you go!" }
enterButton.Activated:Fire()
step(0.2)
assert(asked[2] == "ColosseumEnter:Hard", "ENTER asks again: " .. tostring(asked[2]))
assert(not menu.Enabled, "going in closes it")
-- next time it opens on the one you went in on
doorPrompt.Triggered:Fire(player)
step(0.1)
assert(menu.Enabled and string.find(cardText("Hard"), "PICKED", 1, true), "it opens on the one you went in on")
-- the X closes it
find(menu, "Close").Activated:Fire()
step(0.1)
assert(not menu.Enabled, "the X closes it")
-- walking away from the door closes it
doorPrompt.Triggered:Fire(player)
step(0.1)
assert(menu.Enabled, "it opens again")
root.CFrame = CFrame.new(GATE + Vector3.new(40, 3, 0))
step(0.5)
assert(not menu.Enabled, "walking away from the door closes it")
-- arriving in the Colosseum closes it, and it doesn't open in there
root.CFrame = CFrame.new(GATE + Vector3.new(4, 3, 0))
doorPrompt.Triggered:Fire(player)
step(0.1)
assert(menu.Enabled, "open by the door")
player:SetAttribute("Colosseum", true)
step(0.1)
assert(not menu.Enabled, "going in closes it")
doorPrompt.Triggered:Fire(player)
step(0.1)
assert(not menu.Enabled, "it doesn't open from inside the Colosseum")
root.CFrame = CFrame.new(-2600, 3, 0)

-- THE CLEARED SCREEN on Hard: the quest's pay, a newly opened difficulty, and
-- the difficulty buttons for the next run
remotes.StateUpdate.OnClientEvent:Fire({ Quests = { day = 0, list = {} }, Colosseum = { clears = 2, pick = "Hard", wins = { Normal = 1, Hard = 1 }, bests = { Normal = 150.5, Hard = 201 } } })
table.clear(asked)
local questMark = #played
fire("RunClear", { time = 201, best = 201, newBest = true, clears = 2, wins = 1, diff = "Hard", questPower = 83790, questCoins = 2700, unlocked = "Nightmare" })
step(3.5)
assert(clear.Enabled, "the clear screen opens")
local ctexts = {}
for _, d in ipairs(clear:GetDescendants()) do
	if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Visible ~= false and d.Text ~= "" then
		ctexts[#ctexts + 1] = d.Text
	end
end
local call = table.concat(ctexts, " | ")
print("clear screen (Hard): " .. call)
assert(string.find(call, "HARD RUNS CLEARED: 1", 1, true), "runs cleared on Hard")
assert(string.find(call, "QUEST COMPLETE!  +83,790 XP  +2,700 coins", 1, true) or string.find(call, "QUEST COMPLETE!", 1, true), "the quest's pay")
assert(string.find(call, "NIGHTMARE UNLOCKED!", 1, true), "the newly opened difficulty")
assert(string.find(call, "NEXT RUN:", 1, true), "the difficulty row")
local fanfare = false
for i = questMark + 1, #played do
	if played[i] == "Quest Complete" then
		fanfare = true
	end
end
assert(fanfare, "the quest's fanfare plays as the screen opens")
find(clear, "DifficultyNightmare").Activated:Fire()
step(0.2)
assert(asked[1] == "ColosseumDifficulty:Nightmare", "the clear screen's buttons pick the next run's difficulty: " .. tostring(asked[1]))
local nmButton = find(clear, "DifficultyNightmare")
assert(nmButton.BackgroundColor3 == Config.colosseumDifficulty("Nightmare").color, "the picked one lights up in its colour")
player:SetAttribute("Colosseum", nil)
step(0.1)

print(string.format("camera kicks %d (total %.2f)", kicks, kickTotal))
local counts = {}
for _, n in ipairs(played) do
	counts[n] = (counts[n] or 0) + 1
end
local list = {}
for n, c in pairs(counts) do
	table.insert(list, n .. "=" .. c)
end
table.sort(list)
print("sounds played: " .. table.concat(list, "  "))
print(string.format("ERRORS %d  warnings %d", #M.errors, M.warnings or 0))
assert(#M.errors == 0, "errors in the client scripts")
print("PASS")
