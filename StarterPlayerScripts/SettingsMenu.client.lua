--[[
	SettingsMenu  (LocalScript, parent: StarterPlayerScripts)

	THE SETTINGS, in the new see-through menus (ReplicatedStorage/Menus).
	Each is a switch, saved with your data (the SaveSettings action) and
	put into effect on this screen straight away:
	  * MUSIC / SOUND EFFECTS: the mix's sound groups (Config.Audio) on or off
	  * SHADOWS: the world's shadows
	  * LOW GRAPHICS: shadows and the light's extra effects (bloom, sun rays,
	    blur) off, for slower phones
	  * HIDE OTHERS' EFFECTS: other players' ability effects and auras aren't
	    drawn on your screen (yours still are) - the player attribute
	    HideOthersFX (AbilityFX reads it)
	  * CAMERA SHAKE: the camera kicks and shakes (the attribute NoShake:
	    CombatClient and MoveFX read it)
	  * REVIVES / BOSS RUSH: use those tickets by themselves in boss fights
	    (the server reads these: ShopService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if Config.NewHud == false then
	return
end
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local C = K.COLORS

local player = Players.LocalPlayer
local DEFAULTS = { music = true, sfx = true, shadows = true, low = false, hideOthers = false, shake = true, revives = true, rush = true }
local current = table.clone(DEFAULTS) -- what's in effect on this screen
local shadowsWere = nil -- the world's own shadows setting (put back when switched on)
local effectsWere = {} -- [light effect] = was it on

local LIST = {
	{ "Sound", "music", "Music", "The songs in the lobby, the Arcade and the fights." },
	{ "Sound", "sfx", "Sound effects", "Hits, bosses, coins and buttons." },
	{ "Graphics", "shadows", "Shadows", "The world's shadows." },
	{ "Graphics", "low", "Low graphics", "Turns off shadows and the light's extra effects - smoother on slow phones." },
	{ "Graphics", "hideOthers", "Hide others' effects", "Other players' ability effects and auras aren't drawn on your screen." },
	{ "Graphics", "shake", "Camera shake", "The camera kicks when big hits land." },
	{ "Fights", "revives", "Use revives", "A revive ticket stands you back up once per boss fight." },
	{ "Fights", "rush", "Use Boss Rush", "A Boss Rush ticket doubles a win against a boss you've beaten." },
}

----------------------------------------------------------------------
-- putting them into effect
----------------------------------------------------------------------
local function apply(s)
	for k, v in pairs(DEFAULTS) do
		if type(s) == "table" and type(s[k]) == "boolean" then
			current[k] = s[k]
		elseif current[k] == nil then
			current[k] = v
		end
	end
	-- the mix: every music group, and the effects / UI groups
	for _, g in ipairs(SoundService:GetChildren()) do
		if g:IsA("SoundGroup") then
			local isMusic = string.find(g.Name, "Music") ~= nil
			local on = (isMusic and current.music) or (not isMusic and current.sfx)
			if g:GetAttribute("FullVolume") == nil then
				g:SetAttribute("FullVolume", g.Volume)
			end
			g.Volume = on and g:GetAttribute("FullVolume") or 0
		end
	end
	-- shadows and the light's effects
	if shadowsWere == nil then
		shadowsWere = Lighting.GlobalShadows
	end
	Lighting.GlobalShadows = (current.shadows and not current.low) and shadowsWere or false
	for _, e in ipairs(Lighting:GetChildren()) do
		if e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
			if effectsWere[e] == nil then
				effectsWere[e] = e.Enabled
			end
			e.Enabled = (not current.low) and effectsWere[e] or false
		end
	end
	player:SetAttribute("HideOthersFX", current.hideOthers or nil)
	player:SetAttribute("NoShake", (not current.shake) or nil)
	player:SetAttribute("LowGraphics", current.low or nil)
end

-- other players' auras from their looks (RewardService's LookAura) follow
-- "hide others' effects" too
local function othersAuras()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			local aura = root and root:FindFirstChild("LookAura")
			if aura and aura:IsA("ParticleEmitter") then
				aura.Enabled = not current.hideOthers
			end
		end
	end
end

----------------------------------------------------------------------
-- the menu
----------------------------------------------------------------------
local function row(api, key, label, words)
	local block = api.block(96)
	local on = current[key]
	local face = K.card(block, { Name = "Setting_" .. key, Size = UDim2.fromOffset(math.min(820, api.width), 84), ZIndex = 7 })
	K.label(face, { Name = "Label", Text = label, TextScaled = false, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -220, 0, 36), ZIndex = 9 })
	K.label(face, { Name = "Words", Text = words, TextScaled = false, TextSize = 18, TextWrapped = true, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 44), Size = UDim2.new(1, -220, 0, 34), ZIndex = 9 })
	local b = api.button(face, on and "ON" or "OFF", on and C.Green or C.Off, { Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.fromOffset(150, 52), ZIndex = 10 })
	b:SetAttribute("On", on)
	b.Activated:Connect(function()
		current[key] = not current[key]
		apply(current)
		othersAuras()
		api.act("SaveSettings", table.clone(current))
		api.redraw()
	end)
end

Menus.define("Settings", {
	Title = "Settings",
	Color = C.Slate,
	Tabs = {
		{ Key = "Sound", Label = "Sound", Icon = "Settings" },
		{ Key = "Graphics", Label = "Graphics", Icon = "Looks" },
		{ Key = "Fights", Label = "Fights", Icon = "Revive" },
	},
	render = function(page, tab, api)
		api.section(tab == "Fights" and "Tickets in fights" or tab)
		for _, s in ipairs(LIST) do
			if s[1] == tab then
				row(api, s[2], s[3], s[4])
			end
		end
	end,
})

-- your saved settings arrive with your data (and whenever it changes)
local applied = false
Menus.onState(function(d)
	if type(d) == "table" and type(d.Settings) == "table" then
		-- (only the first time, or when they really changed on the server)
		local changed = not applied
		for k in pairs(DEFAULTS) do
			if type(d.Settings[k]) == "boolean" and d.Settings[k] ~= current[k] then
				changed = true
			end
		end
		if changed then
			applied = true
			apply(d.Settings)
			othersAuras()
		end
	end
end)
-- new sound groups and players arriving: keep them in line
SoundService.ChildAdded:Connect(function(c)
	if c:IsA("SoundGroup") then
		task.defer(apply, current)
	end
end)
do
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 3 then
			acc = 0
			othersAuras()
		end
	end)
end
