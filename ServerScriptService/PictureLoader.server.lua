--[[
	PictureLoader  (Script, parent: ServerScriptService, name: "PictureLoader")

	Makes the uploaded pictures load fast (see ReplicatedStorage/Pictures).
	Every picture in AssetIds.Icons was uploaded as a decal; this looks up
	the real image inside each one (InsertService) when the game starts and
	puts it in ReplicatedStorage > Pictures as an attribute, "d<decal id>" =
	the image's id - the menus' icons and the coin and token first, then the
	weapons. "Ready" = true once it's been through them all.

	Roblox only lets a game load decals owned by whoever owns the game (the
	uploader uses the game owner's account). One it can't load just stays a
	thumbnail: slower, but it still shows.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ok, AssetIds = pcall(function()
	return require(ReplicatedStorage:WaitForChild("AssetIds", 10))
end)
local icons = ok and type(AssetIds) == "table" and AssetIds.Icons or {}

local folder = ReplicatedStorage:FindFirstChild("Pictures")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Pictures"
	folder.Parent = ReplicatedStorage
end

-- the image inside decal `id`, or nil
local function imageOf(id)
	local got, asset = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not got or not asset then
		return nil
	end
	local image = nil
	for _, d in ipairs(asset:GetDescendants()) do
		if d:IsA("Decal") then -- (a Texture is a Decal too)
			image = tonumber(string.match(d.Texture, "(%d+)%D*$"))
			if image then
				break
			end
		end
	end
	asset:Destroy()
	return image
end

-- the menus' icons and the money first (they're on the screen straight away)
local queue, seen = {}, {}
local function add(key, id)
	local n = tonumber(string.match(tostring(id), "(%d+)%s*$"))
	if n and n > 0 and not seen[n] then
		seen[n] = true
		table.insert(queue, { key = key, id = n })
	end
end
local keys = {}
for key in pairs(icons) do
	table.insert(keys, key)
end
local function early(key)
	return string.sub(key, 1, 3) == "UI_" or string.sub(key, 1, 5) == "Coin_" or string.sub(key, 1, 6) == "Token_"
end
table.sort(keys, function(a, b)
	if early(a) ~= early(b) then
		return early(a)
	end
	return a < b
end)
for _, key in ipairs(keys) do
	add(key, icons[key])
end

-- a few at a time
local WORKERS = 8
local left, failed = #queue, {}
local nextOne = 1
local function worker()
	while nextOne <= #queue do
		local job = queue[nextOne]
		nextOne = nextOne + 1
		local image = imageOf(job.id)
		if image then
			folder:SetAttribute("d" .. job.id, image)
		else
			table.insert(failed, job.key)
		end
		left = left - 1
		if left == 0 then
			folder:SetAttribute("Ready", true)
			if #failed > 0 then
				warn(("[PictureLoader] %d picture(s) stay as thumbnails (couldn't look inside the decal): %s"):format(#failed, table.concat(failed, ", ")))
			end
		end
	end
end
if #queue == 0 then
	folder:SetAttribute("Ready", true)
end
for _ = 1, math.min(WORKERS, #queue) do
	task.spawn(worker)
end
