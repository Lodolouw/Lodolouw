--[[
	MoneyIcons  (ModuleScript, parent: ReplicatedStorage, name: "MoneyIcons")

	THE LIVING MONEY ICONS: the coin (gold, our slime stamped on it: a soft
	shine sweeps across, the slime blinks, a glint twinkles) and the Arcade
	Token (the Holo token: its rainbow rim turns, a shine sweeps across,
	sparkles twinkle, and it bobs). Each is 8 pictures the screen flips
	through, made by Tools/Icons/make_token_icons.py (out/money/Coin_1.png ..
	Token_8.png) and uploaded as decals by Tools/Upload/upload_assets.bat
	(their ids: AssetIds.Icons, "Coin_1" ... "Token_8").

	  MoneyIcons.make(parent, "Coin" or "Token", size, props)
	      -> a Frame (named "Coin" / "Token") with the living picture in it,
	         or nil while its pictures aren't all uploaded (draw your own then)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}
local FRAMES = 8
local FPS = 10 -- (pictures a second)

local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures")) -- (fast pictures: they download as you join)

-- a kind's 8 pictures (their ids), or nil if any is missing
local cache = {}
local function pictures(kind)
	if cache[kind] ~= nil then
		return cache[kind] or nil
	end
	local icons = type(AssetIds) == "table" and AssetIds.Icons or {}
	local list = {}
	for i = 1, FRAMES do
		local id = icons[kind .. "_" .. i]
		if not id then
			cache[kind] = false
			return nil
		end
		list[i] = id
	end
	cache[kind] = list
	return list
end

local live = setmetatable({}, { __mode = "k" }) -- [picture] = { kind, list }
local started = false
local function start()
	if started or (RunService.IsClient and not RunService:IsClient()) then
		return
	end
	started = true
	local shown = -1
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local frame = math.floor(t * FPS) % FRAMES + 1
		local bob = math.sin(t * 2.4) * 0.04 -- (the token bobs a little)
		for pic, info in pairs(live) do
			if pic.Parent then
				if frame ~= shown then
					pic.Image = Pictures.url(info.list[frame]) -- (the fast picture once it's known)
				end
				if info.kind == "Token" then
					pic.Position = UDim2.fromScale(0.5, 0.5 + bob)
				end
			else
				live[pic] = nil
			end
		end
		shown = frame
	end)
end

function M.make(parent, kind, size, props)
	local list = pictures(kind)
	if not list then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = kind
	holder:SetAttribute("LivingIcon", true) -- (RetroUI leaves it alone: no old coin drawn over it)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	local pic = Instance.new("ImageLabel")
	pic.Name = "Picture"
	pic.BackgroundTransparency = 1
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.fromScale(1.15, 1.15) -- (the pictures have a little air round them)
	pic.ScaleType = Enum.ScaleType.Fit
	pic.ResampleMode = Enum.ResamplerMode.Pixelated
	pic.Image = Pictures.url(list[1])
	pic.Parent = holder
	for k, v in pairs(props or {}) do
		holder[k] = v
	end
	pic.ZIndex = holder.ZIndex
	holder.Parent = parent
	live[pic] = { kind = kind, list = list }
	start()
	return holder
end

return M
