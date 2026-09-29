--[[
	WeaponModelLoader  (Script, parent: ServerScriptService, name: "WeaponModelLoader")

	Loads the voxel weapons' uploaded 3D models (their ids: ReplicatedStorage/
	AssetIds.Models) into ReplicatedStorage > WeaponModels when the game starts,
	so every screen can hold them (ReplicatedStorage/WeaponFX, "buildVoxel").

	A model already in that folder (imported by hand with Studio's 3D Importer,
	named after its weapon key - GooGloves, Jellyblade...) is left as it is.
	Roblox only lets a game load models owned by whoever owns the game, so
	upload them with the game owner's account (Tools/Upload/upload_assets.bat).
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ok, AssetIds = pcall(function()
	return require(ReplicatedStorage:WaitForChild("AssetIds", 10))
end)
local ids = ok and type(AssetIds) == "table" and AssetIds.Models or {}

local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "WeaponModels"
	folder.Parent = ReplicatedStorage
end

local function load(key, id)
	local got, asset = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not got or not asset then
		warn(("[WeaponModelLoader] couldn't load %s (%s): %s"):format(key, tostring(id), tostring(asset)))
		return
	end
	-- (LoadAsset wraps what was uploaded in a Model: usually one Model inside,
	-- the weapon's meshes in it)
	local inner = asset:GetChildren()
	local model = asset
	if #inner == 1 and inner[1]:IsA("Model") then
		model = inner[1]
		model.Parent = nil
		asset:Destroy()
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true -- (just a template: WeaponFX copies it)
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model.Name = key
	if folder:FindFirstChild(key) then
		model:Destroy() -- (one got there first)
		return
	end
	model.Parent = folder
end

for key, id in pairs(ids) do
	local n = tonumber(string.match(tostring(id), "(%d+)%s*$")) -- (a number, or "rbxassetid://...")
	if n and n > 0 and not folder:FindFirstChild(key) then
		task.spawn(load, key, n)
	end
end
