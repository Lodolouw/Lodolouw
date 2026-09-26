-- Every dummy template, built by the real LobbyBuilder code: the right bits on the right ones
local M = require("./rbxmock")
local S = require("./sources")
local env = M.env()
local builder = M.load(S.DummyBuilder, "DummyBuilder", env)()
local Config = M.load(S.Config, "Config", env)()
local function has(model, className)
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == className then
			return true
		end
	end
	return false
end
local kinds = {}
for _, t in ipairs(Config.Colosseum.Types) do
	table.insert(kinds, { t.id, t.scale })
end
table.insert(kinds, { "King", Config.Colosseum.King.scale })
for _, k in ipairs(kinds) do
	local m = builder(k[1], k[2])
	local parts = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			assert(d.CanCollide == false and d.CanTouch == false, k[1] .. ": every piece walks-through")
		end
	end
	local embers, light = has(m, "ParticleEmitter"), has(m, "PointLight")
	print(string.format("%-8s scale %.2f  parts %3d  foot %.2f  embers %s  light %s  primary %s", k[1], k[2], parts, m:GetAttribute("Foot"), tostring(embers), tostring(light), tostring(m.PrimaryPart)))
	assert(m.PrimaryPart and m.PrimaryPart.Name == "Torso", "the pivot is the body")
	assert(math.abs(m:GetAttribute("Foot") - 5.4 * k[2]) < 1e-9, "Foot attribute")
	if k[1] == "Cursed" then
		assert(embers and light, "the Cursed Dummy keeps its embers and glow")
	else
		assert(not embers and not light, k[1] .. " should have no embers or glow")
	end
end

print("PASS")
