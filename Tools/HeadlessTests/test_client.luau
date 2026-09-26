--!nocheck
-- Headless test of the King's screen side: LobbyActivities (boss bar, banners,
-- shakes, sounds, music) and BossIntro (VS splash, talking), fed a fake King.
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
local lobbyGroup = Instance.new("SoundGroup")
lobbyGroup.Name = "Music"
lobbyGroup.Volume = 1
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
assert(math.abs(lobbyGroup.Volume - 1) < 1e-6, "the lobby music should come back: " .. lobbyGroup.Volume)

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
assert(math.abs(lobbyGroup.Volume - 1) < 1e-6, "the lobby music should be back")

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
