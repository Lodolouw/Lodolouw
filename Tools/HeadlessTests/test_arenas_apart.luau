--!nocheck
-- EVERY ARENA IN ITS OWN SPOT: builds the lobby (with the Colosseum and
-- Oozark's hollow in it) and every Spire floor's arena together in one
-- pretend world, and checks that no two of them overlap. (Kongo's jungle was
-- first built right on top of the Colosseum: each arena's own test only ever
-- builds that one arena, so nothing noticed.)
--   luau test_arenas_apart.luau          (-a list: print every arena's box)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local args = { ... }
local LIST = args[1] == "list"
local workspace = M.workspace

-- every Spire arena's builder (a new floor's arena goes in this list)
local BUILDERS = {
	"DunesBuilder", "DigBuilder", "DojoBuilder", "SpeedwayBuilder", "GridBuilder", "JungleBuilder", "GreenhouseBuilder",
	"CanvasBuilder",
}

local problems = {}
local function problem(text)
	table.insert(problems, text)
end

-- what a builder adds to the world: whatever wasn't there before it ran
local function build(name)
	local before = {}
	for _, c in ipairs(workspace:GetChildren()) do
		before[c] = true
	end
	local ok, err = pcall(function()
		mount.require(mount.module("ServerScriptService/" .. name .. ".lua")).Build()
	end)
	M.run(0.2)
	if not ok then
		problem(name .. " failed to build: " .. tostring(err))
	end
	local added = {}
	for _, c in ipairs(workspace:GetChildren()) do
		if not before[c] then
			table.insert(added, c)
		end
	end
	return added
end

local lobbyBits = build("LobbyBuilder")
local arenas = {} -- { name, root }
for _, name in ipairs(BUILDERS) do
	local added = build(name)
	if #added == 0 then
		problem(name .. " added nothing to the world")
	end
	for _, c in ipairs(added) do
		table.insert(arenas, { name = name .. "/" .. c.Name, root = c })
	end
end

-- The ground each one covers, seen from above: the box round all its parts
-- (sideways only - how high things go doesn't matter). A part turned on its
-- side is allowed for with its longest side, so the box is never too small.
local function boxOf(root)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, s = d.Position, d.Size
			local r = math.max(s.X, s.Y, s.Z) / 2
			minX, maxX = math.min(minX, p.X - r), math.max(maxX, p.X + r)
			minZ, maxZ = math.min(minZ, p.Z - r), math.max(maxZ, p.Z + r)
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, parts = n }
end

-- one box per arena: each builder's whole arena; and the lobby's pieces
-- grouped by which 2600-stud spot they're in (the lobby round the middle,
-- Oozark's hollow and the Colosseum far out)
local function merge(into, b)
	into.minX, into.maxX = math.min(into.minX, b.minX), math.max(into.maxX, b.maxX)
	into.minZ, into.maxZ = math.min(into.minZ, b.minZ), math.max(into.maxZ, b.maxZ)
	into.parts += b.parts
end
local function newBox(name)
	return { name = name, minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge, parts = 0 }
end
local function partBox(part)
	return boxOf({ GetDescendants = function()
		return { part }
	end })
end

local boxes, byName = {}, {}
for _, a in ipairs(arenas) do
	local key = string.match(a.name, "^[^/]+")
	local b = a.root:IsA("BasePart") and partBox(a.root) or boxOf(a.root)
	if b then
		if not byName[key] then
			byName[key] = newBox(key)
			table.insert(boxes, byName[key])
		end
		merge(byName[key], b)
	end
end
for _, name in ipairs(BUILDERS) do
	if not byName[name] then
		problem(name .. " built no parts")
	end
end
local cells = {}
for _, bit in ipairs(lobbyBits) do
	local pieces = bit:IsA("BasePart") and { bit } or bit:GetChildren()
	for _, piece in ipairs(pieces) do
		local b = piece:IsA("BasePart") and partBox(piece) or boxOf(piece)
		if b then
			local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
			local key = string.format("Lobby (spot %d, %d)", math.floor(cx / 2600 + 0.5), math.floor(cz / 2600 + 0.5))
			if not cells[key] then
				cells[key] = newBox(key)
				table.insert(boxes, cells[key])
			end
			merge(cells[key], b)
		end
	end
end

if LIST then
	for _, b in ipairs(boxes) do
		print(string.format("%-28s x %8.0f .. %8.0f   z %8.0f .. %8.0f   (%d parts)", b.name, b.minX, b.maxX, b.minZ, b.maxZ, b.parts))
	end
end

-- no two may overlap (with a little room to spare between them)
local GAP = 50
for i = 1, #boxes do
	for j = i + 1, #boxes do
		local a, b = boxes[i], boxes[j]
		local apartX = a.maxX + GAP < b.minX or b.maxX + GAP < a.minX
		local apartZ = a.maxZ + GAP < b.minZ or b.maxZ + GAP < a.minZ
		if not (apartX or apartZ) then
			problem(string.format("%s (x %.0f..%.0f, z %.0f..%.0f) overlaps %s (x %.0f..%.0f, z %.0f..%.0f)",
				a.name, a.minX, a.maxX, a.minZ, a.maxZ, b.name, b.minX, b.maxX, b.minZ, b.maxZ))
		end
	end
end

print(string.format("%d arenas (and the lobby) checked", #boxes - 1))
if #problems > 0 then
	for _, p in ipairs(problems) do
		print("PROBLEM: " .. p)
	end
	print("FAIL")
else
	print("PASS")
end
