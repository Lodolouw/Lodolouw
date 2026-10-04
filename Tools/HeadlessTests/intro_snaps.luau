--!nocheck
-- Snapshots of the intro for pictures: the real lobby (LobbyBuilder, with
-- RetroWorld's look), the real IntroService and IntroClient, and a pretend
-- player - and at four moments every part you'd see is printed, with the
-- camera and what's on the screen:
--   dark    - waking up: the fountain in the dark, HIT THE SLIME!
--   roll    - the lesson: Oozlet hanging over you, ROLL!!
--   reveal  - the mist rolling back, the lobby building itself
--   spire   - OOZARK AWAITS...
--   luau intro_snaps.luau > intro_snaps.txt
--   python3 render_intro.py intro_snaps.txt ../../Docs/intro_preview.png
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance, Enum = M.Vector3, M.CFrame, M.Instance, M.Enum
local RunService = M.services.RunService
local Players = M.services.Players
local ReplicatedStorage = M.services.ReplicatedStorage
local workspace = M.workspace

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
-- rays: straight down finds the plaza's floor; any other way is tested
-- against the lobby's parts (boxes turned the way they're turned), so the
-- intro's camera finds where it can see over the castle
local rayParts = nil
local function excluded(p, params)
	for _, e in ipairs(params and params.FilterDescendantsInstances or {}) do
		if p == e or p:IsDescendantOf(e) then
			return true
		end
	end
	return false
end
M.raycast = function(origin, dir, params)
	if dir.Y < 0 and math.abs(dir.X) < 1e-6 and math.abs(dir.Z) < 1e-6 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	if not rayParts then
		rayParts = {}
		local lobby = workspace:FindFirstChild("Lobby")
		for _, d in ipairs(lobby and lobby:GetDescendants() or {}) do
			if d:IsA("BasePart") and d.CanQuery ~= false and (d.Transparency or 0) < 1 then
				table.insert(rayParts, d)
			end
		end
	end
	local best, bestT = nil, 1
	for _, p in ipairs(rayParts) do
		if not excluded(p, params) then
			local cf, size = p.CFrame, p.Size
			local o = cf:PointToObjectSpace(origin)
			local v = cf:VectorToObjectSpace(dir)
			local t0, t1 = 0, bestT
			local ok = true
			for _, ax in ipairs({ "X", "Y", "Z" }) do
				local h = size[ax] / 2
				local oa, va = o[ax], v[ax]
				if math.abs(va) < 1e-9 then
					if oa < -h or oa > h then
						ok = false
						break
					end
				else
					local a1, a2 = (-h - oa) / va, (h - oa) / va
					if a1 > a2 then
						a1, a2 = a2, a1
					end
					t0, t1 = math.max(t0, a1), math.min(t1, a2)
					if t0 > t1 then
						ok = false
						break
					end
				end
			end
			if ok and t0 < bestT then
				best, bestT = p, t0
			end
		end
	end
	if best then
		return { Instance = best, Position = origin + dir * bestT, Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end
local realPrint = print
print = function() end -- (quiet while the world is built)

-- the real lobby, and its look
mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
M.run(1)
local atmosphere = M.services.Lighting:FindFirstChildOfClass("Atmosphere")

-- the player: a blocky figure, so there's someone in the pictures
local me = Instance.new("Player")
me.Name = "Alpha"
me.DisplayName = "Alpha"
me.UserId = 1001
me.CameraMaxZoomDistance = 128
local char = Instance.new("Model")
char.Name = "Alpha"
local hum = Instance.new("Humanoid")
hum.MaxHealth, hum.Health = 100, 100
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Transparency = 1
root.CFrame = CFrame.new(0, 3.55, 34)
root.Parent = char
char.PrimaryPart = root
local LIMBS = {
	{ "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), M.Color3.fromRGB(0, 153, 219) },
	{ "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), M.Color3.fromRGB(254, 231, 97) },
	{ "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), M.Color3.fromRGB(254, 231, 97) },
	{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), M.Color3.fromRGB(254, 231, 97) },
	{ "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), M.Color3.fromRGB(58, 68, 102) },
	{ "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), M.Color3.fromRGB(58, 68, 102) },
}
local limbs = {}
for _, l in ipairs(LIMBS) do
	local p = Instance.new("Part")
	p.Name = l[1]
	p.Size = l[2]
	p.Color = l[4]
	p.Parent = char
	limbs[p] = l[3]
end
local function pose()
	for p, off in pairs(limbs) do
		p.CFrame = root.CFrame * CFrame.new(off)
	end
end
pose()
char.Parent = workspace
me.Character = char
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
me.Parent = Players
M.players = { me }
Players.LocalPlayer = me
local cam = Instance.new("Camera")
cam.CFrame = CFrame.new(Vector3.new(0, 12, 30), Vector3.new(0, 3, 0))
cam.CameraType = Enum.CameraType.Custom
cam.ViewportSize = { X = 1280, Y = 720 } -- (RetroWorld sizes its screens by it)
cam.Parent = workspace
workspace.CurrentCamera = cam

M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	M.task.defer(function()
		remote.OnClientEvent:Fire(table.unpack(a, 1, a.n))
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

mount.runClient("StarterPlayerScripts/RetroWorld.client.lua", me)
local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local IS = mount.require(mount.module("ServerScriptService/IntroService.lua"))
PS.Start()
CS.Start(PS)
IS.Start(CS, PS)

local T = 1
local DT = 1 / 30
local function step(seconds, each)
	local stop = T + seconds
	while T < stop do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
		RunService.RenderStepped:Fire(DT)
		pose()
		if each then
			each()
		end
	end
end
local function waitFor(cond, limit, each)
	local t0 = T
	while not cond() and T - t0 < limit do
		step(DT, each)
	end
end
mount.runClient("StarterPlayerScripts/IntroClient.client.lua", me)

-- one snapshot: the camera, every part you'd see, and what's on the screen
local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
local function snap(name, eye, look)
	-- (the game's camera goes there too, so the mist near it melts like it would)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = CFrame.lookAt(eye, look)
		step(0.2)
	end
	realPrint(string.format("SNAP %s %.3f %.3f %.3f %.3f %.3f %.3f", name, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z))
	local roots = { workspace:FindFirstChild("Lobby"), workspace:FindFirstChild("RetroWorld"), workspace:FindFirstChild("IntroWorld"), char }
	for _, r in ipairs(roots) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local t = 1 - (1 - (d.Transparency or 0)) * (1 - (d.LocalTransparencyModifier or 0))
				if t < 0.98 then
					local comps = { d.CFrame:GetComponents() }
					for i, v in ipairs(comps) do
						comps[i] = string.format("%.3f", v)
					end
					local col = d.Color
					realPrint(string.format('{"n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f}',
						esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
						math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
						d.Material.Name, d.Shape and d.Shape.Name or "Block", t))
				end
			end
		end
	end
	-- the screen
	local ig = gui:FindFirstChild("IntroGui")
	local words, color, hint, bar = "", "255,255,255", "", -1
	if ig then
		local list = {}
		for _, c in ipairs(ig.Words:GetChildren()) do
			if c:IsA("Frame") and c.LayoutOrder then
				list[c.LayoutOrder] = c.Main.Text ~= "" and c.Main.Text or " "
				local tc = c.Main.TextColor3
				color = string.format("%d,%d,%d", tc.R * 255 + 0.5, tc.G * 255 + 0.5, tc.B * 255 + 0.5)
			end
		end
		words = table.concat(list)
		hint = ig.How.Text or ""
		local b = ig.OozletBar
		if b.Position.Y.Offset > 0 then
			local fill = b:GetChildren()[3] and b:GetChildren()[3]:GetChildren()[2]
			bar = fill and fill.Size.X.Scale or 1
		end
	end
	local top = workspace.IntroWorld and workspace.IntroWorld:FindFirstChild("ArrowAnchor")
	realPrint(string.format("SCREEN %s|%s|%s|%s|%s", esc(words), color, esc(hint), tostring(bar),
		top and string.format("%.2f,%.2f,%.2f", top.Position.X, top.Position.Y, top.Position.Z) or ""))
	-- the juice: the combo counter, and the comic words still on screen
	local combo = ig and ig:FindFirstChild("Combo")
	local pows = {}
	for _, d in ipairs(workspace.IntroWorld and workspace.IntroWorld:GetDescendants() or {}) do
		if d.Name == "IntroPow" and d.Adornee then
			local t = d:FindFirstChild("Word")
			if t and (t.TextTransparency or 0) < 0.9 then
				local p = d.Adornee.Position + (d.StudsOffset or Vector3.new(0, 0, 0))
				local c = t.TextColor3
				table.insert(pows, string.format("%s@%d,%d,%d@%.2f,%.2f,%.2f", esc(t.Text), c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5, p.X, p.Y, p.Z))
			end
		end
	end
	realPrint(string.format("JUICE %s|%s|%s", (combo and combo.Visible) and string.upper(combo.Count.Text) or "", (combo and combo.Visible) and combo.Word.Text or "", table.concat(pows, ";")))
	realPrint("ENDSNAP")
end

-- a camera behind you, looking at `at`
local function behind(at, back, up)
	local dir = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
	return root.Position - dir * (back or 11) + Vector3.new(0, up or 5, 0), at
end

-- 1. the dark: wait for the words, and for Oozlet to hop round in front
waitFor(function()
	return me:GetAttribute("Intro") == "Void"
end, 10)
local model = workspace.IntroOozlets:WaitForChild("Oozlet_1001")
waitFor(function()
	local ig = gui:FindFirstChild("IntroGui")
	local done = ig and #ig.Words:GetChildren() > 5
	if done then
		for _, c in ipairs(ig.Words:GetChildren()) do
			if c:IsA("Frame") and c.Main.Text == "" and c.LayoutOrder ~= 4 and c.LayoutOrder ~= 8 then
				done = false
			end
		end
	end
	return done
end, 20)
step(1.6)
waitFor(function()
	local p = model.Hitbox.Position
	return p.X < 2 and p.X > -6 and p.Z > 6
end, 20)
root.CFrame = CFrame.lookAt(root.Position, Vector3.new(0, root.Position.Y, 0))
local eye, look = behind(Vector3.new(0, 4, 0), 12, 6)
snap("dark", eye, look)

-- 2. punch it awake, and wait for the lesson
local CombatAction = ReplicatedStorage.CombatRemotes.CombatAction
local lastPunch = -1
local function punchIt()
	if T - lastPunch < 0.45 then
		return
	end
	local at = model.Hitbox.Position
	local here = Vector3.new(at.X, 3.8, at.Z) + Vector3.new(0, 0, 3.5)
	root.CFrame = CFrame.lookAt(here, Vector3.new(at.X, 3.8, at.Z))
	lastPunch = T
	CombatAction:FireServer("Punch", nil, 1)
end
waitFor(function()
	return model:GetAttribute("Action") == "Hold"
end, 20, punchIt)
step(1.4)
local hold = model:GetAttribute("ActionPos")
eye, look = behind(hold + Vector3.new(0, 6, 0), 17, 2)
look = hold + Vector3.new(0, 6.5, 0)
snap("roll", eye, look)

-- 3. roll, and beat it - a picture mid-combo on the way (the 8th punch: a CRITICAL!!)
CombatAction:FireServer("Roll")
local maxHp = model:GetAttribute("MaxHealth") or 12
waitFor(function()
	return (model:GetAttribute("Health") or maxHp) <= maxHp - 8
end, 60, punchIt)
step(0.12)
local at = model.Hitbox.Position
eye, look = behind(at + Vector3.new(0, 2, 0), 13, 5)
snap("combo", eye, at + Vector3.new(0, 3, 0))
waitFor(function()
	return model:GetAttribute("Mood") == "Popped"
end, 60, punchIt)
waitFor(function()
	return me:GetAttribute("Intro") == "Reveal"
end, 10)
root.CFrame = CFrame.lookAt(Vector3.new(4, 3.8, 14), Vector3.new(-30, 3.8, -60))
step(3.9) -- (the mist a good way back)
eye = root.Position + Vector3.new(10, 14, 22)
snap("reveal", eye, Vector3.new(-18, 2, -46))

-- 4. the Spire
waitFor(function()
	return cam.CameraType == Enum.CameraType.Scriptable
end, 20)
step(3.9)
local cf = cam.CFrame
snap("spire", cf.Position, cf.Position + cf.LookVector * 100)
realPrint("DONE")
