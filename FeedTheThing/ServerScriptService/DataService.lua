--[[
	DataService  (ModuleScript, parent: ServerScriptService, name: "DataService")

	Loads and saves each player's progress. Everything a player owns lives in
	one table (see newProfile below), saved with UpdateAsync on leave, every
	Config.AutosaveEvery seconds, and when the server shuts down.

	In Studio, saving only works if the place is published and
	Home > Game Settings > Security > "Enable Studio Access to API Services"
	is on. Without that the game still runs, it just starts fresh each time
	(the Output window says so once).
]]

local DataService = {}

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local store = nil
local storeWarned = false
local profiles = {} -- [player] = { data = ..., canSave = bool }
local savesInFlight = 0 -- so a server shutting down waits for saves already started

-- A brand new player's progress
function DataService.newProfile()
	local plants = {}
	for i, start in ipairs(Config.Garden.StartPlants) do
		local fruit = {}
		for _ = 1, start.ripe do
			table.insert(fruit, "")
		end
		plants[i] = { crop = start.crop, fruit = fruit, timer = 0 }
	end
	return {
		version = 1,
		coins = 0,
		growth = 0, -- how much the Thing has eaten (sets its size)
		plots = Config.Garden.StartPlots,
		yardCap = Config.Yard.StartCap,
		upgrades = {}, -- [upgrade id] = level (Config.Upgrades; plots and yardCap are kept above)
		plants = plants, -- [spot] = { crop = id, fruit = { mutation id or "" ... }, timer = seconds }
		basket = {}, -- [crop id] = { [mutation id or "Normal"] = count }
		belly = {}, -- { { f = crop id, m = mutation id or "", p = perfect } ... }
		yard = {}, -- { { id, kind, mut, born, start, slot } ... }
		pending = {}, -- hatched into a full yard, waiting for "sell new / swap"
		nextId = 1,
		dex = {}, -- [kind] = { Normal = true, Gold = true, ... }
		shop = { index = 0, bought = {} }, -- bought this restock: [crop id] = count
		daily = { day = 0, food = "", fed = 0, done = false },
		stats = { tosses = 0, hatches = 0, perfects = 0 },
		lastOnline = 0,
	}
end

-- Fills in anything an older save is missing, so new fields never crash old saves
local function reconcile(data)
	local fresh = DataService.newProfile()
	for key, value in pairs(fresh) do
		if data[key] == nil then
			data[key] = value
		end
	end
	for key, value in pairs(fresh.stats) do
		if data.stats[key] == nil then
			data.stats[key] = value
		end
	end
	return data
end

local function warnOnce(message)
	if not storeWarned then
		storeWarned = true
		warn("[DataService] " .. message)
	end
end

local function getStore()
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warnOnce("Couldn't open the DataStore (" .. tostring(result) .. "). Playing without saving."
			.. (RunService:IsStudio() and " Publish the place and turn on Game Settings > Security > Enable Studio Access to API Services." or ""))
	end
	return store
end

local function keyFor(player)
	return "u_" .. player.UserId
end

-- Loads a player's data (yields). Returns the profile table.
function DataService.load(player)
	local data, canSave = nil, false
	local ds = getStore()
	if ds then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return ds:GetAsync(keyFor(player))
			end)
			if ok then
				data = result
				canSave = true
				break
			end
			if attempt == 3 then
				warnOnce("Couldn't load saved data (" .. tostring(result) .. "). Playing without saving."
					.. (RunService:IsStudio() and " In Studio, turn on Game Settings > Security > Enable Studio Access to API Services." or ""))
			else
				task.wait(attempt)
			end
		end
	end
	if type(data) ~= "table" then
		data = DataService.newProfile()
	else
		data = reconcile(data)
	end
	profiles[player] = { data = data, canSave = canSave }
	return profiles[player].data
end

function DataService.get(player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.save(player)
	local profile = profiles[player]
	local ds = getStore()
	if not profile or not profile.canSave or not ds then
		return
	end
	profile.data.lastOnline = workspace:GetServerTimeNow()
	local data = profile.data
	savesInFlight += 1
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	savesInFlight -= 1
	if not ok then
		warn("[DataService] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

function DataService.release(player)
	DataService.save(player)
	profiles[player] = nil
end

-- Drops a profile without saving (the player left before it finished loading)
function DataService.forget(player)
	profiles[player] = nil
end

function DataService.start()
	-- autosave
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveEvery)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(DataService.save, player)
			end
		end
	end)
	-- save everyone when the server closes
	-- save everyone still here, and wait for saves already on their way
	-- (the last player's leave-save is usually still running when an empty
	-- server starts shutting down)
	game:BindToClose(function()
		for player in pairs(profiles) do
			task.spawn(DataService.save, player)
		end
		task.wait()
		local started = os.clock()
		while savesInFlight > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
