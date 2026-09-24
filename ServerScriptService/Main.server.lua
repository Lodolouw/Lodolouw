--[[
	Main  (Script, parent: ServerScriptService, name: "Main")

	Builds the lobby (and the Spire's arenas), then starts the game logic.

	Every system is loaded and started on its own, protected: if one of them
	errors (a script pasted in half, a name that doesn't match), the others still
	run - above all player data and the HUD - and the Output window says exactly
	which one broke and why, instead of the whole game silently doing nothing.
]]

local ServerScriptService = game:GetService("ServerScriptService")

-- Finds a module by name. A name that's only off by capitals or spaces
-- ("Dunesbuilder" for "DunesBuilder") is still found - with a note to fix it -
-- instead of the whole game sitting there waiting for a script that is
-- already there under a slightly different name.
local function squash(text)
	return string.lower((string.gsub(text, "%s+", "")))
end
local function findModule(name, waitSeconds)
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
	return ServerScriptService:WaitForChild(name, waitSeconds)
end

local function load(name, waitSeconds)
	local module = findModule(name, waitSeconds or 10)
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
		-- almost always a paste that was cut off: the last line should be "return " .. name
		warn("[Main] '" .. name .. "' loaded but gave back nothing usable. Open it and check the very last line is:  return " .. name
			.. "   (if it isn't, the paste was cut off - paste the whole script in again)")
		return nil
	end
	return result
end

local function start(name, fn, ...)
	if not fn then
		warn("[Main] '" .. name .. "' could not be started (see the line above for why).")
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Main] '" .. name .. "' failed to start: " .. tostring(err))
	end
end

-- the world first (the shops' prompts have to exist before player data hooks them)
local LobbyBuilder = load("LobbyBuilder")
start("LobbyBuilder", LobbyBuilder and LobbyBuilder.Build)

-- player data: without it there's no HUD and none of your upgrades apply
local PlayerService = load("PlayerService")
start("PlayerService", PlayerService and PlayerService.Start)

local SpireService = load("SpireService")
start("SpireService", SpireService and SpireService.Start) -- the Spire menu and travelling to its boss arenas

local CombatService = load("CombatService")
start("CombatService", CombatService and CombatService.Start, PlayerService) -- stamina, rolling, punching and flasks in the arenas

-- The Spire's second floor. Built after player data and combat are running, so
-- the HUD and everything else never waits on it - if it's missing or broken,
-- only the dunes are.
local DunesBuilder = load("DunesBuilder", 3)
start("DunesBuilder", DunesBuilder and DunesBuilder.Build)

local BossService = load("BossService")
if CombatService then
	start("BossService", BossService and BossService.Start, CombatService, PlayerService) -- the bosses themselves (after the arenas exist)
end
