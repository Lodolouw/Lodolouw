--[[
	Pictures  (ModuleScript, parent: ReplicatedStorage, name: "Pictures")

	FAST PICTURES. Tools/Upload/upload_assets.bat uploads every picture (the
	weapon icons, the menus' pixel icons, the coin and the token) as a DECAL,
	and AssetIds keeps the decal's id. A decal id can only be shown as a
	thumbnail ("rbxthumb://..."), which Roblox has to make and send
	separately - slow, so pictures popped in late.

	So when the game starts the server (ServerScriptService/PictureLoader)
	looks up the real image inside each decal and puts it in
	ReplicatedStorage > Pictures: an attribute per decal, "d<decal id>" = the
	image's id, and "Ready" = true once it's been through them all.
	Everything that shows an uploaded picture asks here:

	  Pictures.url(id)          "rbxassetid://<image>" once it's known -
	                            until then the thumbnail (slower, still works)
	  Pictures.show(image, id)  sets image.Image, and swaps in the fast
	                            picture when it arrives
	  Pictures.thumb(id)        the thumbnail, always

	On your screen every uploaded picture starts downloading as soon as the
	images are known (the menus then open with their pictures already there).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local P = {}
local FOLDER = "Pictures"

local function isClient()
	return RunService.IsClient ~= nil and RunService:IsClient()
end

local known = {} -- [decal id] = image id
local waiting = setmetatable({}, { __mode = "k" }) -- [ImageLabel] = { decal id, the thumbnail it shows }

local function number(id)
	return tonumber(string.match(tostring(id or ""), "(%d+)%s*$"))
end

function P.thumb(id, size)
	local n = number(id)
	if not n then
		return nil
	end
	size = size or 150
	return "rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=" .. size .. "&h=" .. size
end

function P.url(id, size)
	local n = number(id)
	if not n then
		return nil
	end
	local image = known[n]
	if image then
		return "rbxassetid://" .. tostring(image)
	end
	return P.thumb(n, size)
end

function P.show(label, id, size)
	local url = P.url(id, size)
	label.Image = url or ""
	local n = number(id)
	if n and not known[n] then
		waiting[label] = { n, url }
	else
		waiting[label] = nil
	end
	return url
end

-- every uploaded picture starts downloading now (on your screen): the fast
-- one where it's known, else its thumbnail
local preloaded = false
local function preload()
	if preloaded or not isClient() then
		return
	end
	preloaded = true
	local icons = nil
	pcall(function()
		local AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
		icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	end)
	local list, seen = {}, {}
	for _, id in pairs(icons or {}) do
		local url = P.url(id)
		if url and not seen[url] then
			seen[url] = true
			table.insert(list, url)
		end
	end
	if #list > 0 then
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(list)
			end)
		end)
	end
end

local function learn(folder, name)
	local value = folder:GetAttribute(name)
	if name == "Ready" then
		if value == true then
			preload()
		end
		return
	end
	local n = tonumber(string.match(name, "^d(%d+)$"))
	if not n or type(value) ~= "number" or value <= 0 then
		return
	end
	known[n] = value
	-- (pictures already on the screen swap to the fast one - unless they've
	-- been changed to something else since)
	for label, w in pairs(waiting) do
		if w[1] == n then
			waiting[label] = nil
			if label.Image == w[2] then
				label.Image = "rbxassetid://" .. tostring(value)
			end
		end
	end
end

local function watch(folder)
	for name in pairs(folder:GetAttributes()) do
		learn(folder, name)
	end
	folder.AttributeChanged:Connect(function(name)
		learn(folder, name)
	end)
end

-- (if the server never says it's ready - no PictureLoader - the thumbnails
-- start downloading after a few seconds anyway)
if isClient() then
	task.delay(8, preload)
end

do
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if folder then
		watch(folder)
	else
		local conn
		conn = ReplicatedStorage.ChildAdded:Connect(function(c)
			if c.Name == FOLDER then
				conn:Disconnect()
				watch(c)
			end
		end)
	end
end

return P
