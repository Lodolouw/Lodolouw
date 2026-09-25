--[[
	ColosseumService  (ModuleScript, parent: ServerScriptService, name: "ColosseumService")

	The Colosseum: a wave arena for farming Power (XP) and coins.

	  * Press E at the Colosseum gate in the lobby and you're taken to the
	    Colosseum (far from the lobby). Press E at its EXIT gate, or die, and
	    you're back at the gate in the lobby.
	  * Inside, straw dummies drop in wave after wave. They hop after you, and
	    when one lands close it winds up a slam: a red ring shows on the sand -
	    get out of it (or roll through it) before it comes down.
	  * EVERYONE FARMS ON THEIR OWN: your dummies carry your UserId (Owner).
	    Only you can hit them, they only go for you, and other players' screens
	    hide them (LobbyActivities). Other players are just there with you.
	  * Dummies are always your level, so each takes about the same few
	    punches whatever your level - and the rewards grow as you do.
	  * A quest runs the whole time you're in there: defeat 10 dummies for a
	    big lump of Power and coins, then it starts straight over again.

	All the numbers are in Config.Colosseum.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ColosseumService = {}

local C = Config.Colosseum
local CombatService, PlayerService -- (set in Start)
local sessions = {} -- [player] = the fight that player is in
local remote -- ColosseumEvent: server -> client
local enemyFolder
local rng = Random.new()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root and hum.Health > 0) then
		return nil
	end
	return root, hum, char
end

local function send(player, ...)
	if remote and player.Parent then
		remote:FireClient(player, ...)
	end
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

----------------------------------------------------------------------
-- Going down the pipe: you shrink, bit by bit (8-bit steps), into the
-- mini colosseum's little door, and pop back out growing the same way.
----------------------------------------------------------------------
local function groundBelow(pos, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, enemyFolder }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or pos
end

-- stand the (possibly tiny) character with its feet on `ground`, facing `look`
local function standAt(char, ground, look)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local box, size = char:GetBoundingBox()
	local up = root.Position.Y - (box.Position.Y - size.Y / 2) -- root above the feet
	local p = ground + Vector3.new(0, up + 0.05, 0)
	local f = flat(look)
	root.CFrame = f.Magnitude > 0.01 and CFrame.lookAt(p, p + f) or CFrame.new(p) * root.CFrame.Rotation
end

local function scale(char, s)
	pcall(function()
		char:ScaleTo(s)
	end)
end

-- Shrinks you from full size down to ShrinkTo while you slide from where you
-- are to `toGround` (the door). You're held still while it happens.
local function shrinkInto(player, toGround)
	local root, _, char = rootOf(player)
	if not root then
		return false
	end
	root.Anchored = true
	local from = groundBelow(root.Position, char)
	local look = flat(toGround - from)
	local steps = C.ShrinkSteps or 8
	for k = 1, steps do
		if not char.Parent then
			return false
		end
		local t = k / steps
		scale(char, 1 - (1 - (C.ShrinkTo or 0.3)) * t)
		standAt(char, from:Lerp(toGround, t), look)
		task.wait(0.07)
	end
	task.wait(0.15)
	return char.Parent ~= nil
end

-- Pops you out at `cf` (tiny), then grows you back to full size, and lets you go.
local function growOutAt(player, cf)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 3)
	end)
	root.Anchored = true
	local ground = groundBelow(cf.Position, char)
	local steps = C.ShrinkSteps or 8
	local small = C.ShrinkTo or 0.3
	for k = 0, steps do
		if not char.Parent then
			return
		end
		scale(char, small + (1 - small) * k / steps)
		standAt(char, ground, cf.LookVector)
		task.wait(0.05)
	end
	scale(char, 1)
	standAt(char, ground, cf.LookVector)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = false
end

local function playerLevel(player)
	local d = PlayerService.GetData(player)
	return Config.levelFromPower(d and d.Power or 0)
end

-- the state the player's screen shows (wave, quest progress, what it pays)
local function pushState(player, s)
	local rewards = Config.colosseumRewards(playerLevel(player))
	send(player, "State", {
		wave = s.wave,
		left = s.alive,
		quest = s.questKills,
		goal = C.QuestKills,
		questPower = rewards.questPower,
		questCoins = rewards.questCoins,
	})
end

----------------------------------------------------------------------
-- The dummies
----------------------------------------------------------------------
local function inArena(pos)
	local d = flat(pos - C.Center)
	if d.Magnitude > C.Radius - 5 then
		d = d.Unit * (C.Radius - 5)
	end
	return Vector3.new(C.Center.X + d.X, C.Center.Y, C.Center.Z + d.Z)
end

-- A dummy's slam: a red ring on the sand, a short hop, and down it comes.
local function slam(s, e)
	local model = e.model
	local at = model:GetPivot().Position
	local ring = Instance.new("Part")
	ring.Name = "SlamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, C.SlamRange * 2, C.SlamRange * 2)
	ring.CFrame = CFrame.new(at.X, C.Center.Y + 0.12, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = Color3.fromRGB(228, 59, 68)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = model -- (inside the dummy, so only its owner sees it)

	-- the wind-up: it crouches and shakes
	local base = model:GetPivot()
	local t0 = os.clock()
	while os.clock() - t0 < C.SlamTell do
		if not e.alive then
			ring:Destroy()
			return
		end
		local k = (os.clock() - t0) / C.SlamTell
		ring.Transparency = 0.55 - 0.3 * k
		model:PivotTo(base * CFrame.new((rng:NextNumber() - 0.5) * 0.4, -0.6 * k, 0))
		task.wait(1 / 20)
	end
	-- up...
	local t1 = os.clock()
	while os.clock() - t1 < 0.28 and e.alive do
		local k = (os.clock() - t1) / 0.28
		model:PivotTo(base * CFrame.new(0, math.sin(k * math.pi) * 4, 0))
		task.wait(1 / 30)
	end
	ring:Destroy()
	if not e.alive then
		return
	end
	-- ...and down: anyone standing in the ring gets squashed
	model:PivotTo(base)
	local root, hum = rootOf(s.player)
	if root and (flat(root.Position - at)).Magnitude <= C.SlamRange + 1 then
		local away = flat(root.Position - at)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
		CombatService.DamagePlayer(s.player, hum.MaxHealth * C.SlamDamage, at, away * 40 + Vector3.new(0, 26, 0))
	end
	-- a puff of straw on landing
	local puff = Instance.new("Part")
	puff.Transparency = 1
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Size = Vector3.new(0.2, 0.2, 0.2)
	puff.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0))
	puff.Parent = model
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(Color3.fromRGB(228, 166, 114))
	p.Size = NumberSequence.new(1.2, 0)
	p.Lifetime = NumberRange.new(0.3, 0.5)
	p.Speed = NumberRange.new(14, 20)
	p.SpreadAngle = Vector2.new(80, 10)
	p.Rate = 0
	p.Parent = puff
	p:Emit(18)
	Debris:AddItem(puff, 1)
end

-- One hop towards `dest`, in an arc, turning to face the player.
local function hop(e, dest, faceTo)
	local model = e.model
	local from = model:GetPivot().Position
	local t0 = os.clock()
	while e.alive do
		local k = math.min(1, (os.clock() - t0) / C.HopTime)
		local p = from:Lerp(dest, k) + Vector3.new(0, 4 * k * (1 - k) * C.HopHeight, 0)
		local look = flat(faceTo - p)
		local cf = look.Magnitude > 0.1 and CFrame.lookAt(p, p + look) or CFrame.new(p)
		model:PivotTo(cf)
		if k >= 1 then
			break
		end
		task.wait(1 / 30)
	end
end

-- What one dummy does, over and over, until it's beaten (or you leave)
local function brain(s, e)
	-- dropping in from the sky
	local land = e.model:GetPivot().Position
	local t0 = os.clock()
	while e.alive and os.clock() - t0 < 0.5 do
		local k = (os.clock() - t0) / 0.5
		e.model:PivotTo(CFrame.new(land + Vector3.new(0, 40 * (1 - k * k), 0)) * e.model:GetPivot().Rotation)
		task.wait(1 / 30)
	end
	if e.alive then
		e.model:PivotTo(CFrame.new(land) * e.model:GetPivot().Rotation)
	end
	while e.alive and sessions[s.player] == s do
		task.wait(rng:NextNumber(C.Rest[1], C.Rest[2]))
		if not e.alive or sessions[s.player] ~= s then
			break
		end
		local root = rootOf(s.player)
		if not root then
			break
		end
		local pos = e.model:GetPivot().Position
		local to = flat(root.Position - pos)
		if to.Magnitude <= C.SlamRange then
			slam(s, e)
		else
			-- hop most of the way towards you, a little to one side
			local step = math.min(C.HopReach, to.Magnitude - 3)
			local side = to.Unit:Cross(Vector3.new(0, 1, 0)) * rng:NextNumber(-3, 3)
			local dest = inArena(pos + to.Unit * step + side)
			hop(e, dest, root.Position)
		end
	end
end

local function spawnWave(s)
	local template = ServerStorage:FindFirstChild("ColosseumDummy")
	if not template then
		warn("[ColosseumService] No ColosseumDummy in ServerStorage - is LobbyBuilder up to date?")
		return
	end
	local root = rootOf(s.player)
	if not root then
		return
	end
	s.wave = s.wave + 1
	local count = math.min(C.WaveSize[1] + s.wave - 1, C.WaveSize[2])
	local level = math.max(2, playerLevel(s.player))
	local rec = math.max(1, Config.powerForLevel(level))
	local hp = math.floor(rec * C.HitsToKill)
	for i = 1, count do
		-- somewhere on the sand, not right on top of you
		local spot
		for _ = 1, 12 do
			local a = rng:NextNumber() * math.pi * 2
			local r = rng:NextNumber(12, C.Radius - 8)
			spot = C.Center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if (flat(spot - root.Position)).Magnitude > 22 then
				break
			end
		end
		local model = template:Clone()
		model.Name = "Straw Dummy"
		model:SetAttribute("DisplayName", "Straw Dummy  Lv." .. level)
		model:SetAttribute("Owner", s.player.UserId)
		model:SetAttribute("Level", level)
		model:SetAttribute("MaxHealth", hp)
		model:SetAttribute("Health", hp)
		model:SetAttribute("HitRadius", 2.6)
		local onHit = Instance.new("BindableEvent")
		onHit.Name = "OnHit"
		onHit.Parent = model
		local look = flat(root.Position - spot)
		model:PivotTo(CFrame.lookAt(spot, spot + (look.Magnitude > 0.1 and look or Vector3.new(0, 0, 1))))
		model.Parent = enemyFolder
		CollectionService:AddTag(model, "CombatTarget")

		local e = { model = model, alive = true }
		s.enemies[model] = e
		s.alive = s.alive + 1
		onHit.Event:Connect(function(_, _, killed)
			if killed and e.alive then
				e.alive = false
				s.enemies[model] = nil
				s.alive = s.alive - 1
				ColosseumService.OnKill(s, model)
			end
		end)
		task.delay((i - 1) * 0.25, function()
			if e.alive then
				brain(s, e)
			end
		end)
	end
	send(s.player, "Wave", s.wave)
	pushState(s.player, s)
end

-- A dummy was beaten: pay out, count it for the quest, and bring on the
-- next wave once the sand is clear.
function ColosseumService.OnKill(s, model)
	local player = s.player
	CollectionService:RemoveTag(model, "CombatTarget")
	pcall(CombatService.Disintegrate, model, { Color = Color3.fromRGB(254, 174, 52) })
	Debris:AddItem(model, 2.5)

	local rewards = Config.colosseumRewards(playerLevel(player))
	PlayerService.AddPower(player, rewards.killPower)
	PlayerService.AddCoins(player, rewards.killCoins)
	if PlayerService.QuestProgress then
		PlayerService.QuestProgress(player, "arena", 1)
	end
	send(player, "Kill", rewards.killPower, rewards.killCoins)

	s.questKills = s.questKills + 1
	if s.questKills >= C.QuestKills then
		s.questKills = 0
		PlayerService.AddPower(player, rewards.questPower)
		PlayerService.AddCoins(player, rewards.questCoins)
		send(player, "QuestDone", rewards.questPower, rewards.questCoins)
	end
	pushState(player, s)

	if s.alive <= 0 and sessions[player] == s then
		task.delay(C.WaveBreak, function()
			if sessions[player] == s then
				spawnWave(s)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Going in and out
----------------------------------------------------------------------
local function endSession(player)
	local s = sessions[player]
	sessions[player] = nil
	if not s then
		return
	end
	for model, e in pairs(s.enemies) do
		e.alive = false
		model:Destroy()
	end
	s.enemies = {}
end

local going = {} -- [player] = true while they're going down the pipe

local function enter(player)
	if sessions[player] or going[player] or player:GetAttribute("SpireFloor") then
		return
	end
	local root, _, char = rootOf(player)
	local spawnAt = CollectionService:GetTagged("ColosseumSpawn")[1]
	local door = CollectionService:GetTagged("ColosseumDoor")[1]
	if not (root and spawnAt) then
		return
	end
	if (flat(root.Position - C.GatePosition)).Magnitude > C.EnterRange + 10 then
		return
	end
	going[player] = true
	local ok = pcall(function()
		-- shrink down into the little door...
		if door and not shrinkInto(player, groundBelow(door.Position, char)) then
			error("gone")
		end
		-- ...and pop out, growing, just inside the Colosseum's gate
		growOutAt(player, spawnAt.CFrame)
	end)
	going[player] = nil
	if not ok or not rootOf(player) then
		if player.Character then
			scale(player.Character, 1)
		end
		return
	end
	local s = { player = player, wave = 0, alive = 0, questKills = 0, enemies = {} }
	sessions[player] = s
	player:SetAttribute("Colosseum", true)
	send(player, "Arrived")
	pushState(player, s)
	task.delay(2, function()
		if sessions[player] == s then
			spawnWave(s)
		end
	end)
end

local function leave(player)
	if not sessions[player] or going[player] then
		return
	end
	endSession(player)
	player:SetAttribute("Colosseum", nil)
	send(player, "Left")
	local back = CollectionService:GetTagged("ColosseumReturn")[1]
	if not back then
		return
	end
	-- out the way you came in: shrink where you stand, pop out of the little door growing
	going[player] = true
	pcall(function()
		local root, _, char = rootOf(player)
		if root and shrinkInto(player, groundBelow(root.Position, char)) then
			growOutAt(player, back.CFrame)
		end
	end)
	going[player] = nil
	if player.Character then
		scale(player.Character, 1)
		local r = player.Character:FindFirstChild("HumanoidRootPart")
		if r then
			r.Anchored = false
		end
	end
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function ColosseumService.Start(combatService, playerService)
	CombatService = combatService
	PlayerService = playerService

	local old = ReplicatedStorage:FindFirstChild("ColosseumEvent")
	if old then
		old:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = "ColosseumEvent" -- server -> client: "Arrived", "Left", "State", "Wave", "Kill", "QuestDone"
	remote.Parent = ReplicatedStorage

	enemyFolder = workspace:FindFirstChild("ColosseumEnemies") or Instance.new("Folder")
	enemyFolder.Name = "ColosseumEnemies"
	enemyFolder:ClearAllChildren()
	enemyFolder.Parent = workspace

	local function hook(tag, fn)
		local function one(prompt)
			if prompt:IsA("ProximityPrompt") then
				prompt.Triggered:Connect(function(player)
					local ok, err = pcall(fn, player)
					if not ok then
						warn("[ColosseumService] " .. tag .. " failed: " .. tostring(err))
					end
				end)
			end
		end
		for _, p in ipairs(CollectionService:GetTagged(tag)) do
			one(p)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(one)
	end
	hook("ColosseumEntrance", enter)
	hook("ColosseumExit", leave)

	local function watch(player)
		-- dying in there: the fight ends, and your new body appears in the lobby
		player.CharacterAdded:Connect(function()
			if sessions[player] or player:GetAttribute("Colosseum") then
				endSession(player)
				player:SetAttribute("Colosseum", nil)
				send(player, "Left")
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		endSession(player)
		going[player] = nil
	end)

	-- (the dummies stop the moment you die, instead of beating on your body)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in pairs(sessions) do
				if not rootOf(player) then
					for _, e in pairs(s.enemies) do
						e.alive = false
					end
				end
			end
		end
	end)
end

return ColosseumService
