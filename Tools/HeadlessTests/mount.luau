--!nocheck
-- Puts the game's scripts into the pretend Roblox the way Rojo does
-- (default.project.json): each .lua in ReplicatedStorage / ServerScriptService
-- becomes a ModuleScript in that service (a folder becomes a Folder), so a
-- script that requires another by its place in the game - Config, or a boss's
-- own module in a folder - finds it. Every module gets its own `script`.
--
--   local mount = require("./mount")(M, S)
--   local BossService = mount.require(mount.module("ServerScriptService/BossService.lua"))
--   mount.runClient("StarterPlayerScripts/BossClient.client.lua")  -- (a LocalScript, as the local player)
return function(M, S)
	local Instance = M.Instance
	local services = {
		ReplicatedStorage = M.services.ReplicatedStorage,
		ServerScriptService = M.services.ServerScriptService or game:GetService("ServerScriptService"),
	}
	local mount = { byPath = {}, pathOf = {}, cache = {} }

	-- the folder chain for "Top/A/B/file.lua" (made as needed)
	local function parentFor(parts)
		local node = services[parts[1]]
		for i = 2, #parts - 1 do
			local child = node:FindFirstChild(parts[i])
			if not child then
				child = Instance.new("Folder")
				child.Name = parts[i]
				child.Parent = node
			end
			node = child
		end
		return node
	end

	local paths = {}
	for path in pairs(S.files) do
		table.insert(paths, path)
	end
	table.sort(paths)
	for _, path in ipairs(paths) do
		local parts = string.split(path, "/")
		local top, file = parts[1], parts[#parts]
		if services[top] and not string.find(file, "%.server%.lua$") and not string.find(file, "%.client%.lua$") then
			local name = string.gsub(file, "%.lua$", "")
			local parent = parentFor(parts)
			local inst = parent:FindFirstChild(name)
			if not inst then
				inst = Instance.new("ModuleScript")
				inst.Name = name
				inst.Parent = parent
			end
			mount.byPath[path] = inst
			mount.pathOf[inst] = path
		end
	end

	function mount.module(path)
		return assert(mount.byPath[path], "no module " .. path)
	end

	local function envFor(inst)
		local env
		env = M.env({
			script = inst,
			require = function(mod)
				return mount.require(mod)
			end,
		})
		return env
	end

	function mount.require(inst)
		if mount.cache[inst] ~= nil then
			return mount.cache[inst]
		end
		local path = mount.pathOf[inst]
		if not path then
			error("require of a module that isn't in the game: " .. tostring(inst))
		end
		local result = M.load(S.files[path], path, envFor(inst))()
		mount.cache[inst] = result
		return result
	end

	-- runs a LocalScript as the local player (in their PlayerScripts), in its own thread
	function mount.runClient(path, player)
		player = player or M.services.Players.LocalPlayer
		local holder = player:FindFirstChild("PlayerScripts")
		if not holder then
			holder = Instance.new("PlayerScripts")
			holder.Name = "PlayerScripts"
			holder.Parent = player
		end
		local inst = Instance.new("LocalScript")
		inst.Name = string.gsub(string.gsub(path, "^.*/", ""), "%.client%.lua$", "")
		inst.Parent = holder
		local fn = M.load(assert(S.files[path], "no script " .. path), path, envFor(inst))
		M.task.spawn(fn)
		return inst
	end

	return mount
end
