--!nocheck
-- The intro, end to end. A brand-new player joins: the real PlayerService,
-- CombatService and IntroService run Oozlet's fight on the "server", and the
-- real IntroClient draws it on the player's "screen" - the dark round the
-- plaza, the words, Oozlet, the reveal. A pretend player stands still until
-- Oozlet bumps them, punches it (through CombatService's own remote, so its
-- rules count: only the owner can hit it, how hard, when it can't be hurt),
-- waits under the lesson slam (it follows them) and then rolls, and keeps
-- punching until it cracks and pops - then watches the lobby come back.
-- A second player joins too, who has played before: no intro for them, and
-- they're hidden while it's dark.
--   luau test_intro.luau              the whole intro
--   luau test_intro.luau -a full detail   ...printing every change of words and move
--   luau test_intro.luau -a skip      a returning player: no intro at all
--   luau test_intro.luau -a fail      their screen breaks mid-intro: back to normal, no reward
--   luau test_intro.luau -a replay    the whole intro, then Studio's DEV: Replay Intro (start over as new)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance, Enum = M.Vector3, M.CFrame, M.Instance, M.Enum
local RunService = M.services.RunService
local Players = M.services.Players
local ReplicatedStorage = M.services.ReplicatedStorage
local SoundService = M.services.SoundService
local workspace = M.workspace
local args = { ... }
local MODE = args[1] or "full"
local DETAIL = args[2] == "detail"

-- Roblox services the mock doesn't have
local core = {}
M.services.StarterGui = {
	SetCoreGuiEnabled = function(_, kind, on)
		core[tostring(kind)] = on
	end,
	GetCoreGuiEnabled = function(_, kind)
		return core[tostring(kind)] ~= false
	end,
}
M.services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	LastInputTypeChanged = M.Signal.new(),
}
M.game.BindToClose = function() end
-- the floor: flat at the plaza's height everywhere
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

-- A little lobby: the plaza and the fountain (in the light), the island's
-- ground under it, things further out, a sign that shows through walls, the
-- Spire, and an arena far away
local lobby = Instance.new("Model")
lobby.Name = "Lobby"
lobby.Parent = workspace
local function block(name, size, cf, parent, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	if shape then
		p.Shape = shape
	end
	p.Parent = parent or lobby
	return p
end
local DISC = CFrame.Angles(0, 0, math.pi / 2)
local plaza = block("PlazaOuter", Vector3.new(0.6, 46, 46), CFrame.new(0, 0.3, 0) * DISC, nil, Enum.PartType.Cylinder)
local basin = block("BasinFloor", Vector3.new(1.4, 19, 19), CFrame.new(0, 0.7, 0) * DISC, nil, Enum.PartType.Cylinder)
local angel = block("AngelTorso", Vector3.new(2.5, 2.5, 1.25), CFrame.new(0, 8, 0))
local curb = block("PlazaCurb", Vector3.new(1, 0.9, 1.9), CFrame.new(22.5, 0.45, 0))
local island = block("Island", Vector3.new(236, 6, 292), CFrame.new(0, -3, 28))
local tree = block("Trunk", Vector3.new(2, 10, 2), CFrame.new(40, 5, -30))
local lamp = block("LampPost", Vector3.new(0.6, 8, 0.6), CFrame.new(12, 4, -30))
local shop = block("SellShop", Vector3.new(12, 10, 10), CFrame.new(52, 5, 45))
local sign = Instance.new("BillboardGui")
sign.Name = "ShopSign"
sign.AlwaysOnTop = true
sign.Enabled = true
sign.Parent = shop
-- (things stuck on parts go dark with them: a picture, a sign, sparkles)
local bark = Instance.new("Decal")
bark.Name = "Bark"
bark.Parent = tree
local lampSign = Instance.new("SurfaceGui")
lampSign.Name = "LampSign"
lampSign.Enabled = true
lampSign.Parent = lamp
local sparkles = Instance.new("ParticleEmitter")
sparkles.Name = "ShopSparkles"
sparkles.Enabled = true
sparkles.Parent = shop
local spawnPad = block("LobbySpawn", Vector3.new(12, 0.3, 12), CFrame.new(0, 0.55, 34))
spawnPad.Transparency = 1
local spire = Instance.new("Folder")
spire.Name = "Spire"
spire.Parent = lobby
local spireBase = block("SpireBase", Vector3.new(30, 20, 30), CFrame.new(0, 30, -316), spire)
local spireTop = block("SpireTop", Vector3.new(10, 60, 10), CFrame.new(0, 90, -316), spire)
local farArena = block("ArenaFloor", Vector3.new(200, 2, 200), CFrame.new(0, 0, 2600))
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.26
atmosphere.Offset = 0.15
atmosphere.Color = M.Color3.fromRGB(176, 190, 220)
atmosphere.Decay = M.Color3.fromRGB(110, 116, 136)
atmosphere.Haze = 0.4
atmosphere.Glare = 0
atmosphere.Parent = M.services.Lighting

-- the sounds the user has (the rest fall back to Roblox's own)
for _, name in ipairs({ "UI Blip", "Boss Slam", "Boss Wake", "Slime boss song" }) do
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.Volume = 0.5
	snd.PlaybackSpeed = 1
	snd.Parent = SoundService
end

-- the players: us (brand new) and Bravo (has played before)
local function newPlayer(name, id, at)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	p.CameraMaxZoomDistance = 128
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth, hum.Health = 100, 100
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0))
	head.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	local pg = Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = p
	local ps = Instance.new("PlayerScripts")
	ps.Name = "PlayerScripts"
	ps.Parent = p
	p.Parent = Players
	return p, char, hum, root, pg, ps
end
local me, myChar, myHum, myRoot, gui, scripts = newPlayer("Alpha", 1001, Vector3.new(0, 3.55, 34))
local bravo, bravoChar, bravoHum = newPlayer("Bravo", 1002, Vector3.new(6, 3.55, 10))
M.players = { me, bravo }
Players.LocalPlayer = me
local kicks = 0
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Event:Connect(function(strength)
	assert(type(strength) == "number" and strength == strength, "bad camera kick")
	kicks += 1
end)
kick.Parent = scripts
local cam = Instance.new("Camera")
cam.CFrame = CFrame.new(Vector3.new(0, 12, 30), Vector3.new(0, 3, 0))
cam.CameraType = Enum.CameraType.Custom
cam.Parent = workspace
workspace.CurrentCamera = cam
-- other screens that should hide while it's dark (and the thumbstick, which mustn't)
local hud = Instance.new("ScreenGui")
hud.Name = "BossGrowHud"
hud.Enabled = true
hud.Parent = gui
local touchGui = Instance.new("ScreenGui")
touchGui.Name = "TouchGui"
touchGui.Enabled = true
touchGui.Parent = gui

-- messages between the "server" and the "screen"
local introEvents = {}
M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	if remote.Name == "IntroEvent" and target == me then
		table.insert(introEvents, a[1] .. (a[2] and (":" .. tostring(a[2])) or ""))
	end
	M.task.defer(function()
		if target == me or target == nil then
			remote.OnClientEvent:Fire(table.unpack(a, 1, a.n))
		end
	end)
end
M.onFireServer = function(remote, ...)
	local a = table.pack(...)
	M.task.defer(function()
		remote.OnServerEvent:Fire(me, table.unpack(a, 1, a.n))
	end)
end
M.onInvokeServer = function(remote, ...)
	return remote.OnServerInvoke(me, ...)
end

-- the server
local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local IS = mount.require(mount.module("ServerScriptService/IntroService.lua"))
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
PS.Start()
CS.Start(PS)
M.run(0.01)
local myData, bravoData = PS.GetData(me), PS.GetData(bravo)
assert(myData and bravoData, "both saves should be loaded")
assert(myData.IntroDone == false, "a brand-new save hasn't done the intro")
bravoData.Power, bravoData.IntroDone = 5000, true -- (Bravo has played before)
if MODE == "skip" then
	myData.Power, myData.IntroDone = 5000, true
end
IS.Start(CS, PS)

local T = 0.01
local DT = 1 / 30
local minHealth = 100
local shownWords, shownAction, shownStage = nil, nil, nil
local words -- (below)
local function step(seconds, each)
	local stop = T + seconds
	while T < stop do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
		RunService.RenderStepped:Fire(DT)
		minHealth = math.min(minHealth, myHum.Health)
		if each then
			each()
		end
		if DETAIL then
			local m = workspace:FindFirstChild("IntroOozlets") and workspace.IntroOozlets:FindFirstChild("Oozlet_1001")
			local w = words()
			local a = m and ((m:GetAttribute("Action") or "") .. " hp " .. tostring(m:GetAttribute("Health")))
			local st = tostring(me:GetAttribute("Intro"))
			if st ~= shownStage then
				shownStage = st
				print(string.format("%6.2f  stage  %s", T, st))
			end
			if a and a ~= shownAction then
				shownAction = a
				print(string.format("%6.2f  oozlet %s  (you: %.0f health)", T, a, myHum.Health))
			end
			if w ~= shownWords and not string.find(w, "[#%%&@%$%?%*%+=<>/]") then
				shownWords = w
				print(string.format("%6.2f  words  %q", T, w))
			end
		end
	end
end
local function waitFor(cond, limit, what, each)
	local t0 = T
	while not cond() do
		assert(T - t0 < limit, "timed out waiting for " .. what .. string.format(" (t = %.1f)", T))
		step(DT, each)
	end
end
function words()
	local holder = gui:FindFirstChild("IntroGui") and gui.IntroGui:FindFirstChild("Words")
	if not holder then
		return ""
	end
	local list = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("Frame") and c.LayoutOrder then
			list[c.LayoutOrder] = c:FindFirstChild("Main") and c.Main.Text or ""
		end
	end
	local out = {}
	for i = 1, #list do
		out[i] = list[i] == "" and " " or list[i]
	end
	return table.concat(out)
end
local function ltm(p)
	return p.LocalTransparencyModifier or 0
end

mount.runClient("StarterPlayerScripts/IntroClient.client.lua", me)

if MODE == "skip" then
	step(3)
	assert(me:GetAttribute("IntroChecked") == true, "the server should have decided")
	assert(me:GetAttribute("Intro") == nil, "a returning player gets no intro")
	assert(not gui:FindFirstChild("IntroCover"), "their screen isn't left black")
	assert(not workspace:FindFirstChild("IntroWorld"), "no dark for them")
	assert(hud.Enabled and ltm(island) == 0 and ltm(tree) == 0, "the lobby is just there")
	assert(not workspace.IntroOozlets:FindFirstChild("Oozlet_1001"), "no Oozlet for them")
	for _, e in ipairs(M.errors) do
		print("ERROR " .. tostring(e))
	end
	assert(#M.errors == 0, "errors")
	print("returning player: no intro, nothing hidden")
	print("PASS")
	return
end

----------------------------------------------------------------------
-- THE DARK
----------------------------------------------------------------------
waitFor(function()
	return me:GetAttribute("Intro") == "Void" and gui:FindFirstChild("IntroGui") ~= nil
end, 5, "the intro to start")
assert(bravo:GetAttribute("IntroChecked") == true and bravo:GetAttribute("Intro") == nil, "Bravo has played before: no intro")
local model = workspace.IntroOozlets:FindFirstChild("Oozlet_1001")
assert(model, "our Oozlet should exist")
assert(not workspace.IntroOozlets:FindFirstChild("Oozlet_1002"), "Bravo gets none")
assert(model:GetAttribute("Owner") == 1001 and model:GetAttribute("NoBar"), "it's only ours, and draws its own bar")
waitFor(function()
	return (myRoot.Position - Vector3.new(0, 3.8, 17)).Magnitude < 1
end, 3, "being put by the fountain")
step(1.5)
assert(not gui:FindFirstChild("IntroCover"), "the black cover lifts once we're in place")
local introWorld = workspace:FindFirstChild("IntroWorld")
assert(introWorld, "the dark's pieces live in IntroWorld")
local walls, mist, body = 0, 0, 0
for _, p in ipairs(introWorld:GetChildren()) do
	if p.Name == "DarkWall" then
		walls += 1
		assert(p.CanCollide == true and p.CanQuery == true and p.CastShadow == false, "the walls stop the camera, and cast no shadow")
	elseif p.Name == "Mist" then
		mist += 1
	elseif p.Name == "Shell" or p.Name == "Eye" or p.Name == "Crown" then
		body += 1
	end
end
assert(walls >= 30 and mist >= 100 and body >= 3, string.format("the box, the mist and Oozlet: %d walls, %d mist, %d body", walls, mist, body))
assert(ltm(plaza) == 0 and ltm(basin) == 0 and ltm(angel) == 0 and ltm(curb) == 0, "the plaza and the fountain stay in the light")
assert(ltm(island) == 1 and ltm(tree) == 1 and ltm(lamp) == 1 and ltm(shop) == 1, "everything else is dark")
assert(ltm(spireBase) == 1 and ltm(spireTop) == 1, "the Spire too")
assert(ltm(farArena) == 0, "things far away are left alone (the dark covers them)")
assert(sign.Enabled == false, "a sign that shows through walls is switched off")
assert(ltm(bark) == 1 and lampSign.Enabled == false and sparkles.Enabled == false, "what's stuck on hidden parts goes dark too")
assert(hud.Enabled == false and touchGui.Enabled == true, "the HUD hides; the thumbstick stays")
assert(core["Enum.CoreGuiType.PlayerList"] == false and core["Enum.CoreGuiType.Backpack"] == false, "Roblox's own buttons hide")
assert(ltm(bravoChar.HumanoidRootPart) == 1 and bravoHum.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None, "other players are hidden")
assert(me.CameraMaxZoomDistance <= 26, "the camera can't pull back out of the dark")
assert(atmosphere.Color == M.Color3.fromRGB(0, 0, 0), "the air goes black")
local warmed = false
for _, snd in ipairs(M.preloaded) do
	if snd.Name == "UI Blip" then
		warmed = true
	end
end
assert(warmed and #M.preloaded >= 10, "the intro's sounds are warmed up before they play")

-- the words build up, one letter at a time
local seen = {}
waitFor(function()
	seen[words()] = true
	return words() == "HIT THE SLIME!"
end, 12, "HIT THE SLIME!")
local partial = false
for w in pairs(seen) do
	if #w > 0 and w ~= "HIT THE SLIME!" then
		partial = true
	end
end
assert(partial, "the letters come in one by one (with scrambling)")
assert(gui.IntroGui:FindFirstChild("How") and gui.IntroGui.How.Text == "", "the how-to line waits a moment")
step(1)
assert(gui.IntroGui.How.Text == "CLICK TO PUNCH", "then says how: " .. tostring(gui.IntroGui.How.Text))
assert(workspace.IntroWorld:FindFirstChild("ArrowAnchor"), "an arrow bounces over Oozlet")

-- Oozlet hops happily round the fountain; stand still and it comes to say hello
local hops, lastHop, farthest = 0, model:GetAttribute("HopAt"), 0
waitFor(function()
	return table.find(introEvents, "Bump") ~= nil
end, 25, "Oozlet to bump us", function()
	if model:GetAttribute("HopAt") ~= lastHop then
		lastHop = model:GetAttribute("HopAt")
		hops += 1
		local to = model:GetAttribute("HopTo")
		farthest = math.max(farthest, Vector3.new(to.X, 0, to.Z).Magnitude)
	end
end)
assert(hops >= 8, "it hops about: " .. hops)
assert(farthest <= 21.1, "it stays on the plaza: " .. farthest)
assert(model:GetAttribute("Mood") == "Happy" and me:GetAttribute("Intro") == "Void", "a bump doesn't start the fight")

if MODE == "fail" then
	-- their screen says it couldn't show the intro
	ReplicatedStorage.Remotes.Action:InvokeServer("IntroFailed")
	step(2.5)
	assert(me:GetAttribute("Intro") == nil, "the intro is given up")
	assert(not model.Parent, "Oozlet is gone")
	local dd = PS.GetData(me)
	assert(dd.IntroDone == false and (dd.Tokens or 0) == 0 and dd.Coins == 0, "no reward, and it comes back next time")
	assert(ltm(island) == 0 and ltm(tree) == 0 and ltm(spireTop) == 0 and sign.Enabled, "the lobby is back")
	assert(hud.Enabled and core["Enum.CoreGuiType.PlayerList"] == true and me.CameraMaxZoomDistance == 128, "screens and camera are back")
	assert(ltm(bravoChar.HumanoidRootPart) == 0, "other players are back")
	assert(not workspace:FindFirstChild("IntroWorld") and not gui:FindFirstChild("IntroGui"), "the intro's pieces are gone")
	for _, e in ipairs(M.errors) do
		print("ERROR " .. tostring(e))
	end
	assert(#M.errors == 0, "errors")
	print("a broken screen: everything back to normal, no reward")
	print("PASS")
	return
end

----------------------------------------------------------------------
-- THE FIGHT
----------------------------------------------------------------------
local CombatAction = ReplicatedStorage.CombatRemotes.CombatAction
local lastPunch = -1
-- stand right by it, facing it, and punch
local function punchIt()
	if T - lastPunch < 0.45 then
		return
	end
	local at = model.Hitbox.Position
	local here = Vector3.new(at.X, 3.8, at.Z) + Vector3.new(3, 0, 0)
	myRoot.CFrame = CFrame.lookAt(here, Vector3.new(at.X, 3.8, at.Z))
	lastPunch = T
	CombatAction:FireServer("Punch", nil, 1)
end
waitFor(function()
	return model:GetAttribute("Health") < 12
end, 5, "the first punch to land", punchIt)
waitFor(function()
	return me:GetAttribute("Intro") == "Fight" and model:GetAttribute("Mood") == "Angry"
end, 2, "Oozlet to get angry")
assert(table.find(introEvents, "Wake"), "it wakes up")
step(0.6)
local barPos = gui.IntroGui.OozletBar.Position
assert(barPos.Y.Offset > 0, "its bar drops in at the top")
assert(words() ~= "HIT THE SLIME!", "the words react to the punch: " .. words())

-- the lesson: it leaps up over us and hangs there
waitFor(function()
	return model:GetAttribute("Action") == "Hold"
end, 8, "the lesson slam", punchIt)
step(1)
assert(model:GetAttribute("Invulnerable") == true, "it can't be hit up there")
assert(words() == "ROLL!!", "the words say ROLL!!: " .. words())
assert(gui.IntroGui.How.Text == "PRESS SHIFT TO ROLL", "and how: " .. gui.IntroGui.How.Text)
local hpHeld = model:GetAttribute("Health")
local holdAt = model:GetAttribute("ActionPos")
-- walk away: it just drifts over us again
myRoot.CFrame = CFrame.new(holdAt + Vector3.new(0, 3, 0) + (Vector3.new(0, 0, 0) - Vector3.new(holdAt.X, 0, holdAt.Z)).Unit * 9)
step(1.5)
assert((model:GetAttribute("ActionPos") - holdAt).Magnitude > 4, "it follows us in the air")
assert(model:GetAttribute("Action") == "Hold", "still waiting for a roll")
-- punching it up there does nothing
lastPunch = -1
punchIt()
step(0.6)
assert(model:GetAttribute("Health") == hpHeld, "no damage while it hangs")
-- roll!
step(0.3)
CombatAction:FireServer("Roll")
waitFor(function()
	return table.find(introEvents, "Dodge:roll") ~= nil
end, 2, "the roll to count")
step(0.4)
assert(words() == "NICE ROLL!", "praise: " .. words())
waitFor(function()
	return model:GetAttribute("Action") == "Dizzy"
end, 2, "it to be dizzy")
assert(model:GetAttribute("Invulnerable") == false, "dizzy: hit it now")

-- punch it down to half: it cracks
waitFor(function()
	return model:GetAttribute("Mood") == "Cracked"
end, 30, "the crack", punchIt)
assert(table.find(introEvents, "Crack"), "it cracks")
step(0.6)
assert(words() == "IT'S CRACKING!", "the words: " .. words())
waitFor(function()
	return model:GetAttribute("MinHealth") == 0
end, 3, "the rest of its health to be open")
-- and on to the end
waitFor(function()
	return model:GetAttribute("Mood") == "Popped"
end, 40, "Oozlet to pop", punchIt)
assert(table.find(introEvents, "Win"), "a win")
local d = PS.GetData(me)
assert(d.IntroDone == true, "beating it is saved")
assert(d.Tokens == 1, "your first Arcade Token: " .. tostring(d.Tokens))
assert(d.Coins == 100, "and 100 coins: " .. d.Coins)
assert(minHealth >= 29.9, "it can never take you below 30%: " .. minHealth)
step(1.2)
assert(workspace.IntroWorld:FindFirstChild("ChestBase"), "a chest drops")
waitFor(function()
	return workspace.IntroWorld:FindFirstChild("IntroChestLabel", true) ~= nil
end, 2, "the chest to open")
local chestText = workspace.IntroWorld:FindFirstChild("IntroChestLabel", true):FindFirstChildOfClass("TextLabel").Text
assert(chestText == "+1 ARCADE TOKEN", "the token rises out of it: " .. chestText)

----------------------------------------------------------------------
-- THE REVEAL
----------------------------------------------------------------------
waitFor(function()
	return me:GetAttribute("Intro") == "Reveal"
end, 4, "the reveal")
step(1.2)
local midway = ltm(tree) -- (the tree is 50 studs out: back early on)
waitFor(function()
	return me:GetAttribute("Intro") == nil
end, 25, "the intro to end")
assert(midway ~= nil, "")
step(2.5)
assert(ltm(island) == 0 and ltm(tree) == 0 and ltm(lamp) == 0 and ltm(shop) == 0, "the lobby is all back")
assert(ltm(spireBase) == 0 and ltm(spireTop) == 0, "and the Spire")
assert(sign.Enabled == true, "the sign is back on")
assert(ltm(bark) == 0 and lampSign.Enabled == true and sparkles.Enabled == true, "and what was stuck on things")
assert(hud.Enabled == true, "the HUD is back")
assert(core["Enum.CoreGuiType.PlayerList"] == true, "Roblox's buttons are back")
assert(ltm(bravoChar.HumanoidRootPart) == 0 and bravoHum.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.Viewer, "other players are back")
assert(me.CameraMaxZoomDistance == 128, "the camera can pull back again")
assert(cam.CameraType == Enum.CameraType.Custom, "the camera is ours again")
assert(atmosphere.Color == M.Color3.fromRGB(176, 190, 220) and atmosphere.Density == 0.26, "the air is back to normal")
assert(not workspace:FindFirstChild("IntroWorld") and not gui:FindFirstChild("IntroGui"), "the intro's pieces are gone")
assert(not model.Parent, "Oozlet's box is gone")
d = PS.GetData(me)
assert(d.Power >= Config.powerForLevel(Config.Intro.Reward.Level), "at least level " .. Config.Intro.Reward.Level .. " now")
assert(myHum.Health == myHum.MaxHealth, "full health again")
assert(kicks > 5, "slams and pops shake the camera")

if MODE == "replay" then
	-- the DEV button: only in Studio...
	local ok = ReplicatedStorage.Remotes.Action:InvokeServer("DevReplayIntro")
	assert(ok == false and me:GetAttribute("Intro") == nil, "no replaying outside Studio")
	RunService.IsStudio = function()
		return true
	end
	me:SetAttribute("Weapon", "IronSword")
	ok = ReplicatedStorage.Remotes.Action:InvokeServer("DevReplayIntro")
	assert(ok == true, "it replays in Studio")
	-- (starting over as a brand-new player: not done, the path from the top, fists)
	local fresh = PS.GetData(me)
	assert(fresh.IntroDone == false, "the intro counts as not done again")
	assert(fresh.Path.step == 0 and fresh.Path.done == false, "the new player path starts over after it")
	assert(me:GetAttribute("Weapon") == nil, "bare fists, like a new player")
	waitFor(function()
		return gui:FindFirstChild("IntroGui") ~= nil and workspace:FindFirstChild("IntroWorld") ~= nil
	end, 5, "the intro to start again")
	local again = workspace.IntroOozlets:FindFirstChild("Oozlet_1001")
	assert(again and again ~= model, "a new Oozlet")
	assert(again:GetAttribute("Health") == 12 and again:GetAttribute("Mood") == "Happy", "fresh and happy")
	waitFor(function()
		return words() == "HIT THE SLIME!"
	end, 12, "the words to build up again")
	assert(ltm(island) == 1 and ltm(tree) == 1 and hud.Enabled == false, "it's dark again")
	assert(gui.IntroGui.OozletBar.Position.Y.Offset < 0, "its bar waits off-screen again")
	-- (cut it short: everything comes back again)
	ReplicatedStorage.Remotes.Action:InvokeServer("IntroFailed")
	step(2.5)
	assert(me:GetAttribute("Intro") == nil and ltm(island) == 0 and hud.Enabled, "and back to normal")
	assert(not SoundService:FindFirstChild("IntroMusicPlaying"), "no music left playing")
end

print(string.format("t %.1f  hops %d  events %s  health low %.0f  kicks %d  power %d", T, hops, table.concat(introEvents, " "), minHealth, kicks, d.Power))
for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
assert(#M.errors == 0, "errors")
assert((M.warnings or 0) == 0, "no warnings")
print("PASS")
