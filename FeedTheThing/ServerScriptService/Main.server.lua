--[[
	Main  (Script, parent: ServerScriptService, name: "Main")

	Makes the remotes, builds the world, then starts the game.

	Every system is loaded and started on its own, protected: if one of them
	errors (a script pasted in half, a name that doesn't match), the Output
	window says exactly which one broke and why, instead of the whole game
	silently doing nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- The remotes the client and server talk through
local REMOTE_EVENTS = { "Feed", "FeedResult", "State", "Notify", "Hatched", "Fx" }
local REMOTE_FUNCTIONS = { "Action" }

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
for _, name in ipairs(REMOTE_EVENTS) do
	if not remotes:FindFirstChild(name) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
end
for _, name in ipairs(REMOTE_FUNCTIONS) do
	if not remotes:FindFirstChild(name) then
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = remotes
	end
end

-- Finds a module by name. A name that's only off by capitals or spaces is
-- still found, with a note to fix it.
local function squash(text)
	return string.lower((string.gsub(text, "%s+", "")))
end
local function findModule(name)
	local module = ServerScriptService:FindFirstChild(name)
	if module then
		return module
	end
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		if child:IsA("ModuleScript") and squash(child.Name) == squash(name) then
			warn("[Main] Found '" .. child.Name .. "' - using it, but please rename it to exactly '" .. name .. "'.")
			return child
		end
	end
	return ServerScriptService:WaitForChild(name, 10)
end

local function load(name)
	local module = findModule(name)
	if not module then
		warn("[Main] Couldn't find the ModuleScript '" .. name .. "' in ServerScriptService - check it's there and named exactly that.")
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn("[Main] '" .. name .. "' failed to load: " .. tostring(result))
		return nil
	end
	if type(result) ~= "table" then
		warn("[Main] '" .. name .. "' loaded but gave back nothing usable. Check its very last line is:  return " .. name)
		return nil
	end
	return result
end

local function start(name, fn, ...)
	if not fn then
		warn("[Main] '" .. name .. "' could not be started (see above for why).")
		return false
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Main] '" .. name .. "' errored while starting: " .. tostring(err))
		return false
	end
	return true
end

local WorldBuilder = load("WorldBuilder")
local DataService = load("DataService")
local GameService = load("GameService")

start("WorldBuilder", WorldBuilder and WorldBuilder.build)
start("DataService", DataService and DataService.start)
start("GameService", GameService and GameService.start, DataService, WorldBuilder)

print("[Main] " .. "Feed the Thing in the Basement is running.")
