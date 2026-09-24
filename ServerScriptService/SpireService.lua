--[[
	SpireService  (ModuleScript, parent: ServerScriptService, name: "SpireService")

	Takes players into the Spire's boss arenas and back out again:
	  * the "Enter" prompt at the Spire's doors opens the Spire menu on that
	    player's screen (SpireClient draws it)
	  * picking an open floor in the menu asks the server to travel; the
	    server checks you're really at the doors, then moves you into that
	    floor's arena
	  * the fog gate in the arena (or the Leave button) brings you back to the
	    Spire's doors - and so does dying in there

	Only floor 1's arena (Gloomgut's Hollow) exists so far, and there is no boss
	fight in it yet - this is just the arena and the way in and out.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local SpireService = {}

local remotes = {}
local lastTravel = {} -- [player] = os.clock() of the last trip, to stop spamming
local TRAVEL_COOLDOWN = 1.5

local function firstTagged(tag)
	return CollectionService:GetTagged(tag)[1]
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (root and hum and hum.Health > 0) then
		return nil
	end
	return root, char
end

local function floorInfo(id)
	for _, f in ipairs(Config.Spire.Floors) do
		if f.id == id then
			return f
		end
	end
	return nil
end

-- Where each floor's arena drops you off (only floor 1 exists for now)
local function arenaSpawnFor(floorId)
	for _, anchor in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
		local arena = anchor:FindFirstAncestorWhichIsA("Model")
		if arena and (arena:GetAttribute("Floor") or 1) == floorId then
			return anchor.CFrame
		end
	end
	return nil
end

-- The floor under a spot (ignoring every player's body), or nil.
local function floorBelow(position, reach)
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			ignore[#ignore + 1] = p.Character
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- stand on solid things, not glows and mist
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -(reach or 30), 0), params)
	return hit and hit.Position or nil
end

-- How far the root part sits above the soles of the feet.
local function rootHeight(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	local half = root and root.Size.Y / 2 or 1
	if hum and hum.RigType == Enum.HumanoidRigType.R6 then
		return 2 + half -- R6 legs are 2 studs, whatever HipHeight says
	end
	local hip = hum and tonumber(hum.HipHeight) or 0
	return (hip > 0 and hip or 2) + half
end

local function moveCharacter(player, char, cf)
	-- make sure the area around the destination is loaded for this player
	-- (only matters if the place uses streaming), then move them there
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 3)
	end)
	local root = char.Parent and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	-- Put the feet ON the real floor (a hair above it), never inside it: a body
	-- dropped into the ground gets wedged there and can't walk out.
	local spot = cf.Position + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 2)
	local floor = floorBelow(spot)
	if floor then
		spot = Vector3.new(spot.X, floor.Y + rootHeight(char) + 0.25, spot.Z)
	end
	local target = CFrame.new(spot) * cf.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- move the model so the ROOT lands on the target, whatever the model's pivot is
	local rootCF = root.CFrame
	char:PivotTo(rootCF and target * rootCF:ToObjectSpace(char:GetPivot()) or target)
	return true
end

-- A spawn point at the Spire's doors, used only to bring back players who died
-- inside (it's switched off, so nobody spawns here by chance). Respawning there
-- lets Roblox place the new body itself - on the floor, standing - instead of
-- teleporting it a frame after it appears, while its movement is still being
-- set up (that's what left bodies sunk into the steps and stuck).
local respawnPad = nil
local function doorsRespawn()
	if respawnPad and respawnPad.Parent then
		return respawnPad
	end
	local back = firstTagged("SpireReturn")
	if not back then
		return nil
	end
	local floor = floorBelow(back.Position) or (back.Position - Vector3.new(0, 3, 0))
	local pad = Instance.new("SpawnLocation")
	pad.Name = "SpireRespawn"
	pad.Size = Vector3.new(6, 0.2, 6)
	pad.CFrame = CFrame.new(floor + Vector3.new(0, 0.1, 0)) * back.CFrame.Rotation
	pad.Anchored = true
	pad.Transparency = 1
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.Enabled = false -- never a random spawn: only for RespawnLocation
	pad.Neutral = true
	pad.AllowTeamChangeOnTouch = false
	pad.Duration = 0 -- no force field bubble
	for _, d in ipairs(pad:GetChildren()) do
		if d:IsA("Decal") then
			d:Destroy() -- the spawn logo
		end
	end
	pad.Parent = workspace
	respawnPad = pad
	return pad
end

-- Getting the arenas ready BEFORE you go in, so nothing is still loading when
-- you arrive. (Only matters if the place uses streaming - Workspace >
-- StreamingEnabled - otherwise everything is always loaded anyway.) As soon as
-- you open the Spire menu, every arena is made to load for you in full and
-- stay loaded, and the sand round it streams in too, while you're still
-- choosing a floor.
local warmed = {} -- [player] = true once their arenas have started loading
local function arenaModels()
	local list = {}
	for _, anchor in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
		local arena = anchor:FindFirstAncestorWhichIsA("Model")
		if arena and not table.find(list, arena) then
			list[#list + 1] = arena
		end
	end
	return list
end

local function warmArenas(player)
	if warmed[player] then
		return
	end
	warmed[player] = true
	for _, arena in ipairs(arenaModels()) do
		pcall(function()
			-- the whole arena, kept loaded for this player from now on
			if arena.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
				arena.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
				arena:AddPersistentPlayer(player)
			end
		end)
		local center = arena:GetAttribute("Center")
		if typeof(center) ~= "Vector3" then
			local ok, cf = pcall(function()
				return arena:GetPivot()
			end)
			center = ok and cf and cf.Position or nil
		end
		if center then
			-- and the ground round it (terrain isn't part of the model)
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(center, 10)
				end)
			end)
		end
	end
end

local function openMenu(player)
	local root = rootOf(player)
	if not root then
		return
	end
	warmArenas(player)
	remotes.SpireEvent:FireClient(player, "OpenMenu")
end

local function travel(player, action, floorId)
	local now = os.clock()
	if lastTravel[player] and now - lastTravel[player] < TRAVEL_COOLDOWN then
		return false, "Slow down."
	end
	local root, char = rootOf(player)
	if not root then
		return false, "You can't travel right now."
	end

	if action == "enter" then
		local floor = type(floorId) == "number" and floorInfo(floorId)
		if not floor then
			return false, "That floor doesn't exist."
		end
		if not floor.open then
			return false, "That floor is sealed."
		end
		-- the floor below has to be beaten first (not in Studio, so you can test)
		if Config.Spire.RequirePrevious and floor.id > 1 and not RunService:IsStudio() then
			if (player:GetAttribute("SpireCleared") or 0) < floor.id - 1 then
				local below = floorInfo(floor.id - 1)
				local name = below and below.boss and string.match(below.boss, "^[^,]+") or "the floor below"
				return false, "Defeat " .. name .. " first."
			end
		end
		local entrance = firstTagged("SpireEntrance")
		local doorPart = entrance and entrance.Parent
		if not (doorPart and doorPart:IsA("BasePart")) then
			return false, "The Spire's doors are missing."
		end
		if (root.Position - doorPart.Position).Magnitude > Config.Spire.EnterRange then
			return false, "Stand at the Spire's doors to enter."
		end
		local dest = arenaSpawnFor(floor.id)
		if not dest then
			return false, "That arena isn't built yet."
		end
		lastTravel[player] = now
		warmArenas(player) -- (normally already done when the menu opened)
		if not moveCharacter(player, char, dest) then
			return false, "You can't travel right now."
		end
		player:SetAttribute("SpireFloor", floor.id)
		remotes.SpireEvent:FireClient(player, "Arrived", floor.area, floor.boss)
		return true
	elseif action == "leave" then
		if not player:GetAttribute("SpireFloor") then
			return false, "You're not in the Spire."
		end
		local back = firstTagged("SpireReturn")
		if not back then
			return false, "Can't find the way back."
		end
		lastTravel[player] = now
		if not moveCharacter(player, char, back.CFrame) then
			return false, "You can't travel right now."
		end
		player:SetAttribute("SpireFloor", nil)
		remotes.SpireEvent:FireClient(player, "Arrived", "The Spire", nil)
		return true
	end
	return false, "Unknown action."
end

local hooked = {}
local function hookEntrance(prompt)
	if hooked[prompt] then
		return
	end
	hooked[prompt] = true
	prompt.Triggered:Connect(openMenu)
end
local function hookExit(prompt)
	if hooked[prompt] then
		return
	end
	hooked[prompt] = true
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("SpireFloor") then
			remotes.SpireEvent:FireClient(player, "ConfirmLeave")
		end
	end)
end

function SpireService.Start()
	local old = ReplicatedStorage:FindFirstChild("SpireRemotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SpireRemotes"
	local event = Instance.new("RemoteEvent")
	event.Name = "SpireEvent" -- server -> client: ("OpenMenu") / ("Arrived", areaName, bossName) / ("ConfirmLeave")
	event.Parent = folder
	local fn = Instance.new("RemoteFunction")
	fn.Name = "SpireTravel" -- client -> server: ("enter", floorId) / ("leave") -> ok, message
	fn.Parent = folder
	folder.Parent = ReplicatedStorage
	remotes.SpireEvent = event
	remotes.SpireTravel = fn

	fn.OnServerInvoke = function(player, action, floorId)
		local ok, success, message = pcall(travel, player, action, floorId)
		if not ok then
			warn("[SpireService] travel failed: " .. tostring(success))
			return false, "Something went wrong."
		end
		return success, message
	end

	for _, p in ipairs(CollectionService:GetTagged("SpireEntrance")) do
		hookEntrance(p)
	end
	CollectionService:GetInstanceAddedSignal("SpireEntrance"):Connect(hookEntrance)
	for _, p in ipairs(CollectionService:GetTagged("ArenaExit")) do
		hookExit(p)
	end
	CollectionService:GetInstanceAddedSignal("ArenaExit"):Connect(hookExit)

	-- respawning always takes you out of the arena; if you died in there
	-- (CombatService marks that), you come back at the Spire's doors instead of
	-- the lobby spawn, so you can try again straight away
	local function watch(player)
		-- the moment you die in there, your next body is set to appear at the doors
		player:GetAttributeChangedSignal("DiedInSpire"):Connect(function()
			if player:GetAttribute("DiedInSpire") then
				local pad = doorsRespawn()
				if pad then
					player.RespawnLocation = pad
				end
			end
		end)
		player.CharacterAdded:Connect(function(char)
			player:SetAttribute("SpireFloor", nil)
			if not player:GetAttribute("DiedInSpire") then
				return
			end
			player:SetAttribute("DiedInSpire", nil)
			task.defer(function()
				if player.RespawnLocation == respawnPad then
					player.RespawnLocation = nil -- back to the lobby spawn next time
				end
			end)
			-- Normally Roblox has already put you at the doors. If it didn't (some
			-- setups ignore a switched-off spawn), walk you over there - but only
			-- once the body has finished setting itself up.
			local root = char:WaitForChild("HumanoidRootPart", 10)
			local back = firstTagged("SpireReturn")
			if not (root and back) then
				return
			end
			task.wait(0.4)
			if char.Parent and (root.Position - back.Position).Magnitude > 20 then
				moveCharacter(player, char, back.CFrame)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
		warmed[player] = nil
	end)
end

return SpireService
