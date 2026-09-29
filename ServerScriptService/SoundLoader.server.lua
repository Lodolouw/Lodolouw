--[[
	SoundLoader  (Script, parent: ServerScriptService, name: "SoundLoader")

	Puts the uploaded sound effects (their ids: ReplicatedStorage/
	AssetIds.Sounds - the weapons', made by Tools/Sounds/weapon_sfx.py, and
	the Arcade's music and sounds, made by Tools/Sounds/arcade_sfx.py) into
	SoundService when the game starts, each under the name the game plays it
	by ("Goo_Splat" -> a Sound called "Goo Splat"). A Sound already there with
	that name (added by hand) is left alone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

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
