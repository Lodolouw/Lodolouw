--!nocheck
-- Headless test of the LIVING MONEY ICONS (ReplicatedStorage/MoneyIcons):
-- with all 8 pictures of a kind uploaded it makes the living one (a frame
-- named after it, the picture flipping through its 8 frames, the token
-- bobbing); with any missing it makes nothing (the screen draws its own).
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance = M.Instance
local RunService = M.services.RunService
RunService.IsClient = function()
	return true
end

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
AssetIds.Icons = {}
for i = 1, 8 do
	AssetIds.Icons["Token_" .. i] = 500 + i
	if i < 8 then
		AssetIds.Icons["Coin_" .. i] = 600 + i -- (one coin picture missing)
	end
end
local Money = mount.require(mount.module("ReplicatedStorage/MoneyIcons.lua"))
local parent = Instance.new("Frame")

local token = Money.make(parent, "Token", 48, { Position = M.UDim2.fromOffset(4, 4) })
check(token and token.Name == "Token" and token.Parent == parent, "the living token is made")
check(token and token:GetAttribute("LivingIcon") == true, "marked, so the retro style draws no old coin over it")
local pic = token and token:FindFirstChild("Picture")
check(pic and pic.Image == "rbxthumb://type=Asset&id=501&w=150&h=150", "showing its first picture")
local seen, ys = {}, {}
local T = 0
for _ = 1, 60 do
	T += 1 / 30
	M.run(T)
	RunService.RenderStepped:Fire(1 / 30)
	seen[pic.Image] = true
	ys[string.format("%.3f", pic.Position.Y.Scale)] = true
end
local count, bobs = 0, 0
for _ in pairs(seen) do
	count += 1
end
for _ in pairs(ys) do
	bobs += 1
end
check(count == 8, "it flips through all 8 pictures (" .. count .. ")")
check(bobs > 3, "and bobs")
check(Money.make(parent, "Coin", 48) == nil, "with a picture missing, nothing (the screen draws its own)")
check(#M.preloaded >= 8, "its pictures start downloading straight away")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
if fails == 0 then
	print("PASS money icons")
else
	print(fails .. " failures")
end
