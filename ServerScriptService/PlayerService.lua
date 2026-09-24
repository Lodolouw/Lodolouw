--[[
	PlayerService  (ModuleScript, parent: ServerScriptService, name: "PlayerService")

	Server-authoritative game logic for the lobby:
	  * per-player data (Power, Coins, Prestige, Loot, Upgrades, Talismans) + DataStore saving
	  * training on the dummy pads (manual clicks + auto-train)
	  * Sell Shop, Upgrade Shop, Talisman crafting/equipping, Prestige
	  * remotes for the HUD

	Hooks for your future arena scripts:
	    local PlayerService = require(game.ServerScriptService.PlayerService)
	    PlayerService.AddLoot(player, "Scrap", 3)   --> returns how many actually fit
	    PlayerService.AddCoins(player, 50)
	    PlayerService.AddPower(player, 10)
	    PlayerService.GetData(player)               --> the live data table (or nil)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PlayerService = {}

local STORE_NAME = "BossGrowLobby_v1"
local AUTOSAVE_SECONDS = 90

local profiles = {} -- [player] = { data = {...}, canSave = bool, ... }
local dirty = {} -- [player] = true when the client needs a fresh snapshot
local lastHit = {} -- [player] = os.clock() of last accepted training hit
local combos = {} -- [player] = { count, zone, lastAt } for manual training hits
local started = {} -- [player] = true once onPlayerAdded ran
local hookedPrompts = {}
local remotes = {}
local handlers = {}
local isStarted = false

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local function defaultData()
	local loot = {}
	for _, m in ipairs(Config.Materials) do
		loot[m.id] = 0
	end
	local ups = {}
	for _, u in ipairs(Config.Upgrades) do
		ups[u.id] = 0
	end
	return {
		Power = 0,
		Coins = 0,
		Prestige = 0,
		Loot = loot,
		Upgrades = ups,
		Owned = {},
		Equipped = {},
		Auto = false,
		Cleared = {}, -- ["1"] = how many times you've killed floor 1's boss
	}
end

-- Copy only the fields we know about, so old/edited saves can't break anything
local function mergeSaved(saved)
	local d = defaultData()
	if type(saved) ~= "table" then
		return d
	end
	if type(saved.Power) == "number" then
		d.Power = saved.Power
	end
	if type(saved.Coins) == "number" then
		d.Coins = saved.Coins
	end
	if type(saved.Prestige) == "number" then
		d.Prestige = saved.Prestige
	end
	if type(saved.Loot) == "table" then
		for id in pairs(d.Loot) do
			if type(saved.Loot[id]) == "number" then
				d.Loot[id] = saved.Loot[id]
			end
		end
	end
	if type(saved.Upgrades) == "table" then
		for id in pairs(d.Upgrades) do
			if type(saved.Upgrades[id]) == "number" then
				d.Upgrades[id] = saved.Upgrades[id]
			end
		end
	end
	if type(saved.Owned) == "table" then
		for id in pairs(Config.TalismanById) do
			if saved.Owned[id] == true then
				d.Owned[id] = true
			end
		end
	end
	if type(saved.Equipped) == "table" then
		for id in pairs(Config.TalismanById) do
			if saved.Equipped[id] == true and d.Owned[id] then
				d.Equipped[id] = true
			end
		end
	end
	d.Auto = saved.Auto == true
	if type(saved.Cleared) == "table" then
		for floorId in pairs(Config.Bosses or {}) do
			local n = saved.Cleared[tostring(floorId)]
			if type(n) == "number" and n > 0 then
				d.Cleared[tostring(floorId)] = math.floor(n)
			end
		end
	end
	return d
end

-- the highest Spire floor this player has ever cleared (0 = none yet)
local function highestCleared(d)
	local best = 0
	for key, n in pairs(d.Cleared or {}) do
		local id = tonumber(key)
		if id and n > 0 and id > best then
			best = id
		end
	end
	return best
end

local function loadData(player)
	if not store then
		return nil, false
	end
	local key = "u_" .. player.UserId
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return result, true -- result is nil for brand-new players
		end
		if attempt == 1 then
			task.wait(1)
		end
	end
	return nil, false
end

local function saveProfile(player)
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return
	end
	local key = "u_" .. player.UserId
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:SetAsync(key, profile.data)
		end)
		if ok then
			return
		end
		warn("[PlayerService] save failed (" .. attempt .. "/3): " .. tostring(err))
		task.wait(1)
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function markDirty(player)
	dirty[player] = true
end

local function notify(player, text, kind)
	if remotes.Notify and player.Parent then
		remotes.Notify:FireClient(player, text, kind or "ok")
	end
end

-- Newer Roblox characters can be driven by a physics-based ControllerManager
-- instead of the classic Humanoid movement. When one is present, how fast you
-- actually move comes from ControllerManager.BaseMoveSpeed (default 16) and
-- Humanoid.WalkSpeed is ignored - which is why the Swift Boots upgrade changed
-- the WalkSpeed number but not your real speed. So set both.
local function applyMoveSpeed(char, speed)
	for _, inst in ipairs(char:GetDescendants()) do
		if inst:IsA("ControllerManager") then
			inst.BaseMoveSpeed = speed
		end
	end
end

local function applyCharacterStats(player, fill)
	local profile = profiles[player]
	if not profile then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local s = Config.stats(profile.data)
	local ratio = 1
	if hum.MaxHealth > 0 then
		ratio = hum.Health / hum.MaxHealth
	end
	local speed = Config.walkSpeedFor(player, profile.data) -- capped in a Spire arena
	hum.WalkSpeed = speed
	applyMoveSpeed(char, speed)
	hum.MaxHealth = s.maxHealth
	if fill then
		hum.Health = s.maxHealth
	else
		hum.Health = s.maxHealth * ratio
	end
end

local function nearStation(player, stationName)
	if not Config.RequireProximity then
		return true
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = Config.Stations[stationName]
	if not root or not pos then
		return false
	end
	local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
	return flat.Magnitude <= Config.StationRange
end

-- Which training pad (if any) a world position is standing on
local function zoneAt(position)
	local half = Config.Yard.PadSize / 2
	for i = 1, #Config.Zones do
		local c = Config.zonePosition(i)
		-- (measured from the pad's own ground: the terrace's pads are a step up)
		if math.abs(position.X - c.X) <= half and math.abs(position.Z - c.Z) <= half and position.Y > c.Y - 3 and position.Y < c.Y + 14 then
			return i
		end
	end
	return 0
end

-- comboCount is nil for auto-train hits (they don't build or use the combo)
local function giveTrainingPower(player, zoneIndex, comboCount)
	local profile = profiles[player]
	if not profile then
		return
	end
	local d = profile.data
	local comboMult = comboCount and Config.comboMult(comboCount) or 1
	local gain = Config.BaseTrainGain * Config.Zones[zoneIndex].mult * Config.stats(d).powerMult * comboMult
	d.Power = d.Power + gain
	markDirty(player)
	remotes.TrainFeedback:FireClient(player, gain, zoneIndex, comboCount or 0, comboMult)
end

-- Counts consecutive manual hits on the same dummy. A pause longer than
-- Config.ComboWindow, or switching dummies, starts it over at 1.
local function nextCombo(player, zoneIndex, now)
	local c = combos[player]
	if c and c.zone == zoneIndex and now - c.lastAt <= Config.ComboWindow then
		c.count = c.count + 1
	else
		c = { count = 1, zone = zoneIndex }
		combos[player] = c
	end
	c.lastAt = now
	return c.count
end

----------------------------------------------------------------------
-- Public API (for your arena scripts)
----------------------------------------------------------------------
function PlayerService.GetData(player)
	local profile = profiles[player]
	return profile and profile.data or nil
end

function PlayerService.AddLoot(player, materialId, amount)
	local profile = profiles[player]
	if not profile or not Config.MaterialById[materialId] then
		return 0
	end
	local d = profile.data
	local space = Config.stats(d).capacity - Config.lootCount(d)
	local added = math.max(0, math.min(math.floor(amount), space))
	if added > 0 then
		d.Loot[materialId] = d.Loot[materialId] + added
		markDirty(player)
	end
	return added
end

function PlayerService.AddCoins(player, amount)
	local profile = profiles[player]
	if profile then
		profile.data.Coins = profile.data.Coins + amount
		markDirty(player)
	end
end

-- A boss on `floorId` died with this player in the arena. Returns true if it
-- was their first time beating it (BossService pays a bigger reward for that).
function PlayerService.RecordBossKill(player, floorId)
	local profile = profiles[player]
	if not profile then
		return false
	end
	local d = profile.data
	d.Cleared = d.Cleared or {}
	local key = tostring(floorId)
	local before = d.Cleared[key] or 0
	d.Cleared[key] = before + 1
	player:SetAttribute("SpireCleared", highestCleared(d))
	markDirty(player)
	return before == 0
end

function PlayerService.AddPower(player, amount)
	local profile = profiles[player]
	if profile then
		profile.data.Power = profile.data.Power + amount
		markDirty(player)
	end
end

----------------------------------------------------------------------
-- Actions (called through the Action RemoteFunction; return ok, message)
----------------------------------------------------------------------
handlers.BuyUpgrade = function(player, d, id)
	local def = type(id) == "string" and Config.UpgradeById[id]
	if not def then
		return false, "Unknown upgrade."
	end
	if not nearStation(player, "Upgrades") then
		return false, "Walk up to the Upgrade Shop first!"
	end
	local level = d.Upgrades[id] or 0
	if level >= def.maxLevel then
		return false, "Already maxed out!"
	end
	local cost = Config.upgradeCost(def, level)
	if d.Coins < cost then
		return false, "Not enough coins (need " .. Config.format(cost) .. ")."
	end
	d.Coins = d.Coins - cost
	d.Upgrades[id] = level + 1
	applyCharacterStats(player, false)
	markDirty(player)
	return true, def.name .. " is now level " .. (level + 1) .. "!"
end

handlers.Sell = function(player, d, arg)
	if not nearStation(player, "Sell") then
		return false, "Walk up to the Sell Shop first!"
	end
	local s = Config.stats(d)
	local total = 0
	local items = 0

	local function sellMaterial(m)
		local n = d.Loot[m.id] or 0
		if n > 0 then
			total = total + n * m.sell
			items = items + n
			d.Loot[m.id] = 0
		end
	end

	if arg == "All" then
		for _, m in ipairs(Config.Materials) do
			sellMaterial(m)
		end
	elseif type(arg) == "string" and Config.MaterialById[arg] then
		sellMaterial(Config.MaterialById[arg])
	else
		return false, "Unknown item."
	end

	if items == 0 then
		return false, "Nothing to sell."
	end
	local coins = math.floor(total * s.coinMult)
	d.Coins = d.Coins + coins
	markDirty(player)
	return true, "Sold " .. items .. (items == 1 and " item" or " items") .. " for " .. Config.format(coins) .. " coins!"
end

handlers.Craft = function(player, d, id)
	local t = type(id) == "string" and Config.TalismanById[id]
	if not t then
		return false, "Unknown talisman."
	end
	if not nearStation(player, "Craft") then
		return false, "Walk up to the Workbench first!"
	end
	if d.Owned[id] then
		return false, "You already crafted that one."
	end
	if d.Coins < t.cost.coins then
		return false, "Not enough coins."
	end
	for matId, need in pairs(t.cost.materials) do
		if (d.Loot[matId] or 0) < need then
			return false, "Missing materials."
		end
	end
	d.Coins = d.Coins - t.cost.coins
	for matId, need in pairs(t.cost.materials) do
		d.Loot[matId] = d.Loot[matId] - need
	end
	d.Owned[id] = true
	local equipped = false
	if Config.equippedCount(d) < Config.TalismanSlots then
		d.Equipped[id] = true
		equipped = true
	end
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Crafted " .. t.name .. (equipped and " and equipped it!" or "! Equip it from the list.")
end

handlers.Equip = function(player, d, id)
	if type(id) ~= "string" or not Config.TalismanById[id] or not d.Owned[id] then
		return false, "You don't own that talisman."
	end
	if d.Equipped[id] then
		return false, "Already equipped."
	end
	if Config.equippedCount(d) >= Config.TalismanSlots then
		return false, "All talisman slots are full. Unequip one first."
	end
	d.Equipped[id] = true
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Equipped " .. Config.TalismanById[id].name .. "."
end

handlers.Unequip = function(player, d, id)
	if type(id) ~= "string" or not d.Equipped[id] then
		return false, "That talisman isn't equipped."
	end
	d.Equipped[id] = nil
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Unequipped."
end

handlers.Prestige = function(player, d)
	if d.Prestige >= Config.MaxPrestige then
		return false, "You've reached the maximum prestige!"
	end
	local req = Config.prestigeRequirement(d.Prestige)
	if d.Power < req then
		return false, "You need " .. Config.format(req) .. " Power to prestige."
	end
	d.Prestige = d.Prestige + 1
	d.Power = 0
	d.Coins = 0
	for id in pairs(d.Upgrades) do
		d.Upgrades[id] = 0
	end
	applyCharacterStats(player, false)
	markDirty(player)
	return true, "Prestige " .. d.Prestige .. "! Permanent bonuses unlocked."
end

handlers.SetAuto = function(player, d, on)
	d.Auto = (on == true)
	markDirty(player)
	return true
end

-- Studio-only test helpers (the arena doesn't exist yet, so nothing drops loot)
handlers.DevGive = function(player, d, kind)
	if not RunService:IsStudio() then
		return false, "Dev tools only work in Studio."
	end
	if kind == "Loot" then
		for _, m in ipairs(Config.Materials) do
			PlayerService.AddLoot(player, m.id, 5)
		end
		return true, "Gave test loot."
	elseif kind == "Coins" then
		d.Coins = d.Coins + 10000
	elseif kind == "Power" then
		d.Power = d.Power + 5000
	elseif kind == "MaxUpgrades" then
		for _, u in ipairs(Config.Upgrades) do
			d.Upgrades[u.id] = u.maxLevel
		end
		applyCharacterStats(player, false)
	else
		return false, "Unknown dev action."
	end
	markDirty(player)
	return true, "Done."
end

----------------------------------------------------------------------
-- Player lifecycle
----------------------------------------------------------------------
local function onCharacter(player, char)
	-- The ControllerManager (see applyMoveSpeed) can be added a moment after
	-- the character spawns, and Roblox's own setup may reset its speed to the
	-- default right after adding it - so re-apply our speed whenever one shows
	-- up, on the next frame, once that setup has finished.
	char.DescendantAdded:Connect(function(inst)
		if inst:IsA("ControllerManager") then
			task.defer(function()
				local profile = profiles[player]
				if profile and inst.Parent then
					inst.BaseMoveSpeed = Config.walkSpeedFor(player, profile.data)
				end
			end)
		end
	end)

	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		applyCharacterStats(player, true)
	end
end

local function onPlayerAdded(player)
	if started[player] then
		return
	end
	started[player] = true
	player:SetAttribute("CurrentZone", 0)

	local saved, ok = loadData(player)
	if not player.Parent then
		return
	end

	local profile = { data = mergeSaved(saved), canSave = ok }
	profiles[player] = profile
	player:SetAttribute("SpireCleared", highestCleared(profile.data)) -- the Spire menu shows it

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	-- Level first so it's the main number on the player list
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = Config.levelFromPower(profile.data.Power)
	level.Parent = ls
	local power = Instance.new("NumberValue")
	power.Name = "Power"
	power.Value = math.floor(profile.data.Power)
	power.Parent = ls
	local prestige = Instance.new("IntValue")
	prestige.Name = "Prestige"
	prestige.Value = profile.data.Prestige
	prestige.Parent = ls
	ls.Parent = player
	profile.leaderPower = power
	profile.leaderPrestige = prestige
	profile.leaderLevel = level

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end

	markDirty(player)
	if not ok then
		notify(player, "Couldn't load saved data - progress this session won't be saved.", "bad")
	end
end

local function onPlayerRemoving(player)
	saveProfile(player)
	profiles[player] = nil
	dirty[player] = nil
	lastHit[player] = nil
	combos[player] = nil
	started[player] = nil
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local function buildRemotes()
	local old = ReplicatedStorage:FindFirstChild("Remotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	local function make(className, name)
		local r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		remotes[name] = r
		return r
	end

	make("RemoteEvent", "RequestState") -- client -> server
	make("RemoteEvent", "StateUpdate") -- server -> client: full snapshot
	make("RemoteEvent", "Train") -- client -> server: one click
	make("RemoteEvent", "TrainFeedback") -- server -> client: (gain, zoneIndex)
	make("RemoteEvent", "Notify") -- server -> client: (text, kind)
	make("RemoteEvent", "OpenPanel") -- server -> client: panel name
	make("RemoteFunction", "Action") -- client -> server: (name, arg) -> ok, message

	folder.Parent = ReplicatedStorage

	remotes.RequestState.OnServerEvent:Connect(function(player)
		if profiles[player] then
			markDirty(player)
		end
	end)

	remotes.Train.OnServerEvent:Connect(function(player)
		local profile = profiles[player]
		if not profile then
			return
		end
		local now = os.clock()
		if now - (lastHit[player] or 0) < Config.TrainMinInterval then
			return
		end
		local zi = player:GetAttribute("CurrentZone")
		if type(zi) ~= "number" or zi < 1 then
			return
		end
		if profile.data.Power < Config.Zones[zi].req then
			return -- pad still locked
		end
		lastHit[player] = now
		giveTrainingPower(player, zi, nextCombo(player, zi, now))
	end)

	remotes.Action.OnServerInvoke = function(player, name, arg)
		local profile = profiles[player]
		local handler = type(name) == "string" and handlers[name]
		if not profile or not handler then
			return false, "Not ready yet."
		end
		local ok, success, message = pcall(handler, player, profile.data, arg)
		if not ok then
			warn("[PlayerService] " .. tostring(name) .. " failed: " .. tostring(success))
			return false, "Something went wrong."
		end
		return success, message
	end
end

local function hookPrompt(prompt)
	if hookedPrompts[prompt] then
		return
	end
	hookedPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		local panel = prompt:GetAttribute("Panel")
		if panel then
			remotes.OpenPanel:FireClient(player, panel)
		end
	end)
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function PlayerService.Start()
	if isStarted then
		return
	end
	isStarted = true

	buildRemotes()

	for _, inst in ipairs(CollectionService:GetTagged("PanelPrompt")) do
		hookPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal("PanelPrompt"):Connect(hookPrompt)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	-- Push snapshots to clients (at most ~10 per second per player)
	task.spawn(function()
		while true do
			task.wait(0.1)
			for player in pairs(dirty) do
				dirty[player] = nil
				local profile = profiles[player]
				if profile and player.Parent then
					profile.leaderPower.Value = math.floor(profile.data.Power)
					profile.leaderPrestige.Value = profile.data.Prestige
					profile.leaderLevel.Value = Config.levelFromPower(profile.data.Power)
					remotes.StateUpdate:FireClient(player, profile.data)
				end
			end
		end
	end)

	-- Work out which pad each player is standing on
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in pairs(profiles) do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local zi = root and zoneAt(root.Position) or 0
				if player:GetAttribute("CurrentZone") ~= zi then
					player:SetAttribute("CurrentZone", zi)
				end
			end
		end
	end)

	-- Auto-train ticks
	task.spawn(function()
		while true do
			task.wait(Config.AutoInterval)
			for player, profile in pairs(profiles) do
				if profile.data.Auto then
					local zi = player:GetAttribute("CurrentZone")
					if type(zi) == "number" and zi > 0 and profile.data.Power >= Config.Zones[zi].req then
						giveTrainingPower(player, zi)
					end
				end
			end
		end
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in pairs(profiles) do
				task.spawn(saveProfile, player)
			end
		end
	end)

	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(saveProfile, p)
		end
		task.wait(3)
	end)
end

return PlayerService
