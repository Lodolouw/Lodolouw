--[[
	SoundLoader  (Script, parent: ServerScriptService, name: "SoundLoader")

	Puts the uploaded sound effects (their ids: ReplicatedStorage/
	AssetIds.Sounds - the weapons', made by Tools/Sounds/weapon_sfx.py, and
	the Arcade's music and sounds, made by Tools/Sounds/arcade_sfx.py, and
	floors 7-10's boss sounds, made by Tools/Sounds/boss_sfx.py) into
	SoundService when the game starts, each under the name the game plays it
	by ("Goo_Splat" -> a Sound called "Goo Splat"). A Sound already there with
	that name (added by hand) is left alone.

	The boss sounds (Config.BossSoundNames) are softened as they go in, even
	one added by hand: a Loudness (Config.BossSoundLoudness - BossClient plays
	each at that share of its volume) and an equalizer turning their harsh top
	end down, like the 8-bit sounds' (Main).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ok, AssetIds = pcall(function()
	return require(ReplicatedStorage:WaitForChild("AssetIds", 10))
end)
local ids = ok and type(AssetIds) == "table" and AssetIds.Sounds or {}

local function squash(s)
	return string.lower((string.gsub(tostring(s), "[%s_%-]", "")))
end
local have = {}
for _, s in ipairs(SoundService:GetChildren()) do
	if s:IsA("Sound") then
		have[squash(s.Name)] = true
	end
end

for key, id in pairs(ids) do
	local n = tonumber(string.match(tostring(id), "(%d+)%s*$")) -- (a number, or "rbxassetid://...")
	local name = string.gsub(key, "_", " ")
	if n and n > 0 and not have[squash(name)] then
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = "rbxassetid://" .. n
		s.Volume = 0.6
		s.Parent = SoundService
		have[squash(name)] = true
	end
end

-- the boss sounds: quieter, and their harsh top end turned down
local loud = Config.BossSoundLoudness or {}
local boss = {}
for _, name in ipairs(Config.BossSoundNames or {}) do
	boss[squash(name)] = loud[name] or loud.Default or 0.4
end
for _, s in ipairs(SoundService:GetChildren()) do
	local level = s:IsA("Sound") and boss[squash(s.Name)]
	if level then
		s:SetAttribute("Loudness", level)
		if not s:FindFirstChild("Soften") then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.Name = "Soften"
			eq.HighGain = -10
			eq.MidGain = -2
			eq.LowGain = 0
			eq.Parent = s
		end
	end
end
