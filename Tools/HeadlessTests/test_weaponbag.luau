--!nocheck
-- Headless test of the WEAPONS panel (WeaponBag.client.lua): a card per weapon
-- you own, rarest first, with its icon (its real picture, once uploaded:
-- AssetIds.Icons) at the top right - a weapon without one just has none -
-- IN HAND on the one you hold, EQUIP on the others.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum = M.Instance, M.Enum
local Players, ReplicatedStorage = M.services.Players, M.services.ReplicatedStorage

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local UIS = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
}
M.services.UserInputService = UIS
local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
M.players = { me }
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "StateUpdate", "RequestState" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes

-- two of the Slime weapons have their icons uploaded
local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
AssetIds.Icons = { Jellyblade = 111, GelatinousEdge = 333 }

mount.runClient("StarterPlayerScripts/WeaponBag.client.lua", me)
M.run(0.5)
remotes.StateUpdate.OnClientEvent:Fire({ Weapons = { own = { Jellyblade = 0, GooGloves = 50, GelatinousEdge = 500 }, hold = "Jellyblade" } })
me:SetAttribute("Weapon", "Jellyblade")
M.run(1)
-- open it (B)
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B, UserInputType = Enum.UserInputType.Keyboard }, false)
M.run(1.5)

local screen = gui:FindFirstChild("WeaponBag")
check(screen ~= nil, "the panel is there")
local cards = {}
for _, d in ipairs(screen and screen:GetDescendants() or {}) do
	if d.ClassName == "Frame" and d.LayoutOrder and d.LayoutOrder > 0 then
		for _, t in ipairs(d:GetChildren()) do
			if t.ClassName == "TextLabel" and t.TextSize == 24 then
				cards[t.Text] = d
			end
		end
	end
end
local function icon(card)
	local i = card and card:FindFirstChild("Icon")
	return i and i.Image or nil
end
check(cards["Jellyblade"] and cards["Goo Gloves"] and cards["Gelatinous Edge"], "a card for each weapon you own")
check(icon(cards["Jellyblade"]) == "rbxthumb://type=Asset&id=111&w=150&h=150", "Jellyblade shows its icon (" .. tostring(icon(cards["Jellyblade"])) .. ")")
check(icon(cards["Gelatinous Edge"]) == "rbxthumb://type=Asset&id=333&w=150&h=150", "and Gelatinous Edge")
check(icon(cards["Goo Gloves"]) == nil, "a weapon whose icon isn't uploaded has none")
check(cards["Gelatinous Edge"] and cards["Gelatinous Edge"].LayoutOrder == 1, "rarest first")
local function has(card, text)
	for _, d in ipairs(card and card:GetDescendants() or {}) do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and d.Text == text then
			return true
		end
	end
	return false
end
check(has(cards["Jellyblade"], "IN HAND") and has(cards["Goo Gloves"], "EQUIP"), "IN HAND on the one you hold, EQUIP on the others")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
if fails == 0 then
	print("PASS weapon bag")
else
	print(fails .. " failures")
end
