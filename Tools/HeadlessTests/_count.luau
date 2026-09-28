--!nocheck
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local CollectionService = M.services.CollectionService
mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
M.run(1)
local home
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	print("BossHome", h:GetAttribute("Floor"), h.Position)
	if h:GetAttribute("Floor") == 1 then home = h.Position end
end
local n, near = 0, {}
for _, d in ipairs(M.workspace:GetDescendants()) do
	if d:IsA("BasePart") then
		n += 1
		local dist = (d.Position - home).Magnitude
		for _, r in ipairs({ 60, 100, 150, 250 }) do
			if dist < r then near[r] = (near[r] or 0) + 1 end
		end
	end
end
print("parts", n, "within 60/100/150/250:", near[60], near[100], near[150], near[250])
for _, s in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
	print("ArenaSpawn", s:GetAttribute("Floor"), s.Position)
end
for _, s in ipairs(CollectionService:GetTagged("ArenaExit")) do
	print("ArenaExit", s:GetAttribute("Floor"), s.Position)
end
