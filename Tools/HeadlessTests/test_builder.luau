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

-- THE DIFFICULTY BOARD, built by the real LobbyBuilder code beside the
-- arena's exit door (where LobbyBuilder puts that door: the gate faces north,
-- turn 180, so the door's frame isn't turned and local +Z points into the arena)
local C = Config.Colosseum
local s = 2.6
local origin = C.Center - M.Vector3.new(0, 1.3 * s, 0)
local doorCF = M.CFrame.new(origin + M.Vector3.new(0, 0, (-42 + 3.05) * s))
local spawnAt = doorCF.Position + M.Vector3.new(0, 0, 8) -- (8 studs in, like ColosseumSpawn)
local folder = M.Instance.new("Folder")
local buildBoard = M.load(S.DifficultyBoard, "DifficultyBoard", env)(Config)
buildBoard(folder, doorCF)
local CollectionService = M.services.CollectionService
local plaques, prompts, faceCount = {}, 0, 0
local STAND_GAP = math.rad(10.8) -- (the stands leave this much room either side of the gate)
local STAND_R = (42 - 1.6 - 3 * 2.4 - 1.2) * s -- (and start this far from the middle)
local nearest = math.huge
for _, d in ipairs(folder:GetDescendants()) do
	if d:IsA("BasePart") and d.Transparency < 1 then
		-- every corner stays in the gap in the stands, or in front of them
		for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local p = d.CFrame:PointToWorldSpace(M.Vector3.new(c[1] * d.Size.X / 2, 0, c[2] * d.Size.Z / 2))
			local off = p - C.Center
			local r = math.sqrt(off.X ^ 2 + off.Z ^ 2)
			local angle = math.atan2(math.abs(off.X), -off.Z) -- (from the gate's direction, north)
			assert(angle < STAND_GAP or r < STAND_R,
				string.format("%s would poke into the stands (r %.1f, %.1f degrees)", d.Name, r, math.deg(angle)))
			nearest = math.min(nearest, math.sqrt((p.X - spawnAt.X) ^ 2 + (p.Z - spawnAt.Z) ^ 2))
		end
	end
	if d:IsA("ProximityPrompt") then
		prompts += 1
		assert(CollectionService:HasTag(d, "ColosseumDifficultyBoard"), "the board's prompt is tagged for LobbyActivities")
		assert(d.Parent.Name == "DifficultyFace", "the prompt is on the board's face")
	end
	if d:IsA("BasePart") and CollectionService:HasTag(d, "DifficultyPlaque") then
		table.insert(plaques, d)
		local sg = d:FindFirstChild("Face")
		assert(sg and sg.ClassName == "SurfaceGui" and sg.Face == M.Enum.NormalId.Back, "each plaque has its words on its front")
		assert(sg:FindFirstChild("Name") and sg:FindFirstChild("Pay") and sg:FindFirstChild("Status"), "name, pay and status on each plaque")
		faceCount += 1
	end
end
print(string.format("difficulty board: %d plaques, %d prompt, nearest piece %.1f studs from where you arrive", #plaques, prompts, nearest))
assert(#plaques == #C.Difficulties and prompts == 1, "a plaque per difficulty, one prompt")
assert(nearest > 3, "the board doesn't stand in the way of where you arrive")
-- (and it leaves the way from the door into the arena clear: nothing within 3
-- studs either side of the line from the door to the middle)
for _, d in ipairs(folder:GetDescendants()) do
	if d:IsA("BasePart") and d.Transparency < 1 then
		for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local p = d.CFrame:PointToWorldSpace(M.Vector3.new(c[1] * d.Size.X / 2, 0, c[2] * d.Size.Z / 2))
			assert(math.abs(p.X - C.Center.X) > 3, d.Name .. " stands in the way into the arena")
		end
	end
end
-- the plaques face where you arrive, Normal on your left and Nightmare on your right
local byId = {}
for _, p in ipairs(plaques) do
	byId[p:GetAttribute("Difficulty")] = p
	local front = p.CFrame:VectorToWorldSpace(M.Vector3.new(0, 0, 1))
	local toSpawn = spawnAt - p.Position
	local flatLen = math.sqrt(toSpawn.X ^ 2 + toSpawn.Z ^ 2)
	local facing = (front.X * toSpawn.X + front.Z * toSpawn.Z) / flatLen
	assert(facing > 0.85, string.format("the plaques face where you arrive (%.2f)", facing))
end
local a, b = byId[C.Difficulties[1].id], byId[C.Difficulties[#C.Difficulties].id]
local look = (a.Position + b.Position) / 2 - spawnAt
local across = b.Position - a.Position
-- (your right, looking along `look`, is (-look.Z, 0, look.X): the last one is that way)
print(string.format("from where you arrive: first plaque at (%.1f, %.1f), last at (%.1f, %.1f)", a.Position.X - spawnAt.X, a.Position.Z - spawnAt.Z, b.Position.X - spawnAt.X, b.Position.Z - spawnAt.Z))
assert(-look.Z * across.X + look.X * across.Z > 0, "seen from where you arrive, the first is on the left")
-- (for the preview picture: every part as JSON)
if ({ ... })[1] == "dump" then
	local list = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			local c = d.CFrame
			local comps = { c:GetComponents() }
			for i, v in ipairs(comps) do
				comps[i] = string.format("%.4f", v)
			end
			local col = d.Color
			table.insert(list, string.format('{"name":"%s","size":[%.3f,%.3f,%.3f],"cf":[%s],"color":[%d,%d,%d],"mat":"%s","shape":"%s","t":%.2f,"diff":"%s"}',
				d.Name, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
				math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
				d.Material.Name, d.Shape and d.Shape.Name or "Block", d.Transparency, tostring(d:GetAttribute("Difficulty") or d:GetAttribute("Title") or "")))
		end
	end
	print(string.format("BOARD %.2f %.2f %.2f [%s]", spawnAt.X, spawnAt.Y, spawnAt.Z, table.concat(list, ",")))
end
print("PASS")
