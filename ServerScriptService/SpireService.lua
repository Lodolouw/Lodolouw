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

	Every trip up gets an arena of its own: ArenaPool hands you (and your
	party) a copy of that floor's arena with its own boss, so players
	grinding the same floor never share a fight. The player's SpireArena
	attribute says which copy (SpireFloor still says which floor).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local ArenaPool = require(script.Parent:WaitForChild("ArenaPool"))

local SpireService = {}

local remotes = {}
local lastTravel = {} -- [player] = os.clock() of the last trip, to stop spamming
local TRAVEL_COOLDOWN = 1.5

-- Is the boss of the arena you're in awake and fighting? (You can't walk out
-- on a fight: you win it, or it wins.) Your own arena copy's boss only.
local FIGHTING = { Waking = true, Fighting = true, Transition = true }
local function fightOn(player)
	local floorId = player:GetAttribute("SpireFloor")
	local arenaId = player:GetAttribute("SpireArena")
	for _, boss in ipairs(CollectionService:GetTagged("Boss")) do
		if boss:GetAttribute("Floor") == floorId and FIGHTING[boss:GetAttribute("State")]
			and (arenaId == nil or boss:GetAttribute("ArenaId") == nil or boss:GetAttribute("ArenaId") == arenaId) then
			return true
		end
	end
	return false
end

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

-- Where an arena (a copy of a floor's) drops you off
local function arenaSpawnIn(arena)
	for _, anchor in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
		if arena and anchor:IsDescendantOf(arena) then
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

-- Tells the movement guard (PlayerService) this move is the server's own,
-- so it doesn't put the player back where they came from.
local function allowMove(player, destination, seconds)
	if player and destination then
		player:SetAttribute("MoveTo", destination)
		player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + (seconds or 3))
	end
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
	allowMove(player, spot)
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

-- Getting an arena ready BEFORE you go in, so nothing is still loading when
-- you arrive. (Only matters if the place uses streaming - Workspace >
-- StreamingEnabled - otherwise everything is always loaded anyway.) Only ONE
-- arena is kept loaded for you at a time: the copy you'd most likely get as
-- you open the Spire menu, the one you're given as you go in - and it's let
-- go again when you're back in the lobby.
local warmed = {} -- [player] = the arena model kept loaded for them

local function coolArena(player)
	local arena = warmed[player]
	warmed[player] = nil
	if arena and arena.Parent then
		pcall(function()
			arena:RemovePersistentPlayer(player)
		end)
	end
end

-- (wait: block until it's streamed in round where you'll stand)
local function warmArena(player, arena, wait)
	if not arena then
		return
	end
	if warmed[player] ~= arena then
		coolArena(player)
		warmed[player] = arena
		pcall(function()
			-- the whole arena, kept loaded for this player till they're back
			if arena.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
				arena.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
				arena:AddPersistentPlayer(player)
			end
		end)
	end
	local dest = arenaSpawnIn(arena)
	if dest then
		local function stream()
			pcall(function()
				player:RequestStreamAroundAsync(dest.Position, 10)
			end)
		end
		if wait then
			stream()
		else
			task.spawn(stream)
		end
	end
end

local function openMenu(player)
	local root = rootOf(player)
	if not root then
		return
	end
	-- (the next floor you'd fight: most likely the one you'll pick - and the
	-- copy of it you'd get, kept for you a minute)
	local nextFloor = math.max(1, (player:GetAttribute("SpireCleared") or 0) + 1)
	local ok, arena = pcall(ArenaPool.Prepare, nextFloor, player)
	warmArena(player, ok and arena or nil, false)
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
		-- the floor below has to be beaten first (not for a dev - Studio, or the
		-- game's owner - so you can test any floor)
		if Config.Spire.RequirePrevious and floor.id > 1 and not Config.isDev(player) then
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
		-- an arena of your own (with your party: SpireService.PartyFor)
		local group, why = { player }, nil
		if SpireService.PartyFor then
			group, why = SpireService.PartyFor(player, floor.id)
			if not group then
				return false, why or "Your party's leader picks the floor."
			end
		end
		local arena = ArenaPool.Acquire(floor.id, group)
		local dest = arena and arenaSpawnIn(arena)
		if not dest then
			ArenaPool.Leave(player)
			return false, arena and "That arena isn't built yet." or "Every arena is busy - try again in a moment."
		end
		lastTravel[player] = now
		local id = arena:GetAttribute("ArenaId")
		for _, p in ipairs(group) do
			local pRoot, pChar = rootOf(p)
			if pRoot then
				if p ~= player then
					lastTravel[p] = now
				end
				warmArena(p, arena, p == player) -- (often already done when the menu opened)
				if moveCharacter(p, pChar, dest) then
					-- which copy first: screens react to SpireFloor changing
					p:SetAttribute("SpireArena", id)
					p:SetAttribute("SpireFloor", floor.id)
					remotes.SpireEvent:FireClient(p, "Arrived", floor.area, floor.boss)
				else
					ArenaPool.Leave(p)
				end
			else
				ArenaPool.Leave(p)
			end
		end
		if player:GetAttribute("SpireFloor") ~= floor.id then
			return false, "You can't travel right now."
		end
		return true
	elseif action == "leave" then
		if not player:GetAttribute("SpireFloor") then
			return false, "You're not in the Spire."
		end
		if fightOn(player) then
			return false, "You can't leave in the middle of a fight!"
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
		player:SetAttribute("SpireArena", nil)
		ArenaPool.Leave(player)
		coolArena(player)
		-- out of the arena: patched up, back to full health
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = hum.MaxHealth
		end
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
		local floorId = player:GetAttribute("SpireFloor")
		if floorId and fightOn(player) then
			remotes.SpireEvent:FireClient(player, "Message", "You can't leave in the middle of a fight!")
		elseif floorId then
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
	event.Name = "SpireEvent" -- server -> client: ("OpenMenu") / ("Arrived", areaName, bossName) / ("ConfirmLeave") / ("Message", text)
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
			player:SetAttribute("SpireArena", nil)
			ArenaPool.Leave(player)
			coolArena(player) -- (back in the lobby: the arena can go)
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
		ArenaPool.Leave(player)
	end)
end

return SpireService
