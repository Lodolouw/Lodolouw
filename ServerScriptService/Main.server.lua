--[[
	Main  (Script, parent: ServerScriptService, name: "Main")

	Builds the lobby (and the Spire's arenas: the slime pit, the Sunken Dunes,
	the Glimmer Dig and the Rooftop Dojo), then starts the game logic.

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
-- The uploaded sounds (Config.SoundIds): make a Sound in SoundService for
-- each one that isn't there already, before anything tries to play them.
pcall(function()
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
	local SoundService = game:GetService("SoundService")
	local have = {}
	for _, s in ipairs(SoundService:GetChildren()) do
		have[squash((string.gsub(s.Name, "_", "")))] = true
	end
	for name, id in pairs(Config.SoundIds or {}) do
		if not have[squash(name)] then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = "rbxassetid://" .. tostring(id)
			s.Parent = SoundService
		end
	end
	-- the 8-bit ones are softened: quieter, and their shrill top end turned down
	local soft = Config.SoundLoudness or {}
	for _, s in ipairs(SoundService:GetChildren()) do
		local n = squash((string.gsub(s.Name, "_", "")))
		for name, level in pairs(soft) do
			if s:IsA("Sound") and squash(name) == n then
				s:SetAttribute("Loudness", level)
				if not s:FindFirstChild("Soften") then
					local eq = Instance.new("EqualizerSoundEffect")
					eq.Name = "Soften"
					eq.HighGain = -12
					eq.MidGain = -3
					eq.LowGain = 0
					eq.Parent = s
				end
			end
		end
	end
end)

local LobbyBuilder = load("LobbyBuilder")
start("LobbyBuilder", LobbyBuilder and LobbyBuilder.Build)

-- player data: without it there's no HUD and none of your upgrades apply
local PlayerService = load("PlayerService")
start("PlayerService", PlayerService and PlayerService.Start)

local SpireService = load("SpireService")
start("SpireService", SpireService and SpireService.Start) -- the Spire menu and travelling to its boss arenas

-- Parties (up to 4): the leader picks the floor and everyone goes into one
-- arena together (it hands SpireService who goes up with whom)
-- (arriving on a Spire floor: the new player path's "Enter the Spire" step)
if SpireService and PlayerService and PlayerService.PathEvent then
	SpireService.OnArrive = function(p)
		PlayerService.PathEvent(p, "Enter")
	end
end
local PartyService = load("PartyService", 3)
start("PartyService", PartyService and PartyService.Start, SpireService)

local CombatService = load("CombatService")
start("CombatService", CombatService and CombatService.Start, PlayerService) -- stamina, rolling, punching and flasks in the arenas

-- The Arcade's spins: tokens in, weapons out (needs player data; the building
-- is part of the lobby: ArcadeBuilder)
local ArcadeService = load("ArcadeService", 3)
if PlayerService then
	start("ArcadeService", ArcadeService and ArcadeService.Start, PlayerService, CombatService)
end

-- Trading at the lobby's picnic benches: sit across from someone to swap
-- weapons (needs player data; the benches are part of the lobby)
local TradeService = load("TradeService", 3)
if PlayerService then
	start("TradeService", TradeService and TradeService.Start, PlayerService, CombatService)
end

-- The new GUI's rewards (login streak, free gift, codes, the Index, looks,
-- the corner bonuses) and the shop (Robux purchases, passes, Daily Items):
-- both need player data
local RewardService = load("RewardService", 3)
if PlayerService then
	start("RewardService", RewardService and RewardService.Start, PlayerService)
end
local ShopService = load("ShopService", 3)
if PlayerService then
	start("ShopService", ShopService and ShopService.Start, PlayerService, RewardService)
end
-- (the Arcade's luck: the luck passes and the Luck boost)
if ArcadeService and ShopService then
	ArcadeService.LuckFor = ShopService.Luck
end

-- The Spire's second floor. Built after player data and combat are running, so
-- the HUD and everything else never waits on it - if it's missing or broken,
-- only the dunes are.
local DunesBuilder = load("DunesBuilder", 3)
start("DunesBuilder", DunesBuilder and DunesBuilder.Build)

-- The Spire's third floor, The Glimmer Dig (Knight Burrowmore's arena): the
-- same way - if it's missing or broken, only the dig is
local DigBuilder = load("DigBuilder", 3)
start("DigBuilder", DigBuilder and DigBuilder.Build)

-- The Spire's fourth floor, The Rooftop Dojo (Kaze's arena): the same way
local DojoBuilder = load("DojoBuilder", 3)
start("DojoBuilder", DojoBuilder and DojoBuilder.Build)

-- The Spire's fifth floor, Piston Speedway (Speedy Revvington's arena): the same way
local SpeedwayBuilder = load("SpeedwayBuilder", 3)
start("SpeedwayBuilder", SpeedwayBuilder and SpeedwayBuilder.Build)

-- The Spire's sixth floor, The Final Beat (Gridlock's level): the same way
local GridBuilder = load("GridBuilder", 3)
start("GridBuilder", GridBuilder and GridBuilder.Build)

-- The Spire's seventh floor, Kongo's Jungle Village (Kongo's arena): the same way
local JungleBuilder = load("JungleBuilder", 3)
start("JungleBuilder", JungleBuilder and JungleBuilder.Build)

-- The Spire's eighth floor, the Glasshouse Garden (Petalina's arena): the same way
local GreenhouseBuilder = load("GreenhouseBuilder", 3)
start("GreenhouseBuilder", GreenhouseBuilder and GreenhouseBuilder.Build)

-- The Spire's ninth floor, The Canvas (Scribble's arena): the same way
local CanvasBuilder = load("CanvasBuilder", 3)
start("CanvasBuilder", CanvasBuilder and CanvasBuilder.Build)

-- The Spire's tenth and last floor, The Throne Summit (King Gavelgrunt's arena): the same way
local ThroneBuilder = load("ThroneBuilder", 3)
start("ThroneBuilder", ThroneBuilder and ThroneBuilder.Build)

-- Lighter shadows: every small piece of the world built above (foam, pebbles,
-- leaves, flowers, rocks, trim - anything under 5 studs at its longest) stops
-- casting a shadow. Thousands of them did; you'd never miss them, but every
-- screen had to draw them all into the shadow map, every frame. (The big
-- shapes - walls, towers, trees, the ground - keep theirs.)
local SMALL_SHADOW = 5
local function lightenShadows()
	local Players = game:GetService("Players")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.CastShadow then
			local size = d.Size
			local owner = d:FindFirstAncestorWhichIsA("Model")
			if math.max(size.X, size.Y, size.Z) < SMALL_SHADOW and not (owner and Players:GetPlayerFromCharacter(owner)) then
				d.CastShadow = false
			end
		end
	end
end
pcall(lightenShadows)
task.delay(3, function()
	pcall(lightenShadows) -- (and whatever the builders finished a moment later)
end)

-- Arena copies: each floor's arena becomes its first copy, and a clean
-- snapshot is kept so every player (or party) going up can have one of their
-- own (SpireService asks for them). Before the bosses, so every boss knows
-- its arena's id. (The Dunes' sand is Terrain: its builder pours it again for
-- each copy.)
local ArenaPool = load("ArenaPool", 3)
start("ArenaPool", ArenaPool and ArenaPool.Start, { DuneArena = DunesBuilder })

local BossService = load("BossService")
if CombatService then
	start("BossService", BossService and BossService.Start, CombatService, PlayerService) -- the bosses themselves (after the arenas exist)
end
-- the shop's tickets in fights: REVIVE (a lethal hit in a boss fight) and
-- BOSS RUSH (a repeat win pays double) - ShopService decides and uses them
if ShopService and CombatService then
	CombatService.ReviveHook = ShopService.Revive
end
if ShopService and BossService then
	BossService.WinHook = ShopService.Rush
end

-- The Colosseum: the wave arena for farming (needs combat and player data)
local ColosseumService = load("ColosseumService", 3)
if CombatService and PlayerService then
	start("ColosseumService", ColosseumService and ColosseumService.Start, CombatService, PlayerService)
end
-- (and it's the Spire's ground floor too: the training grounds, at the top
-- of the Spire menu)
if SpireService and ColosseumService and ColosseumService.EnterFromSpire then
	SpireService.EnterColosseum = ColosseumService.EnterFromSpire
end

-- The intro: a brand-new player's first fight, Oozlet, by the fountain (needs
-- combat and player data; started last, so nothing else ever waits on it)
local IntroService = load("IntroService", 3)
if CombatService and PlayerService then
	start("IntroService", IntroService and IntroService.Start, CombatService, PlayerService)
end
