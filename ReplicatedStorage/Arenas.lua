--[[
	Arenas  (ModuleScript, parent: ReplicatedStorage, name: "Arenas")

	Every boss fight in the Spire has an arena of its own. Each player (or
	party) who goes up to a floor gets a COPY of that floor's arena, out in a
	free spot of the world, with its own boss - ServerScriptService/ArenaPool
	makes them. This is how every script tells the copies apart:
	  * ArenaId (attribute, a string like "4-2": floor 4, copy 2) on an arena
	    copy's model, on its boss's model, and on the folders of props that
	    boss leaves lying about (TuberProps...)
	  * SpireArena (attribute) on a player: the ArenaId of the arena they're
	    in - set together with SpireFloor (the floor number)
	Things built inside an arena (its pillars, torches, thorns...) need no id:
	they're inside its model.

	No ids anywhere (a test that builds one arena per floor and no ArenaPool)
	means one arena per floor, the way it always was, and everything here
	matches by floor.
]]

local Workspace = game:GetService("Workspace")

local Arenas = {}

-- the arena copy a player is in (its ArenaId), or nil
function Arenas.idOf(player)
	return player and player:GetAttribute("SpireArena") or nil
end

-- Is this boss / prop folder / arena part of the arena `player` is in? (With
-- no ids in play it is, if it's on their floor - the caller checks that.)
function Arenas.isMine(player, inst)
	local mine = player and player:GetAttribute("SpireArena")
	local id = inst and inst:GetAttribute("ArenaId")
	if mine == nil or id == nil then
		return true
	end
	return mine == id
end

-- Do these two belong to the same arena copy? (A boss and a prop folder, say.)
function Arenas.same(a, b)
	local ia = a and a:GetAttribute("ArenaId")
	local ib = b and b:GetAttribute("ArenaId")
	return ia == ib
end

local function isArena(c)
	return c:IsA("Model") and not c:GetAttribute("Boss")
end

-- The arena model for a boss (or anything carrying an ArenaId): the copy with
-- the same ArenaId - or, with no ids in play, the first arena on its floor.
-- `need` (optional): an attribute the arena must have (e.g. "Tiles").
-- (Matched by attributes, never by position: a copy that hasn't streamed in
-- to this screen is an empty model that says it sits at 0,0,0.)
local cache = setmetatable({}, { __mode = "v" })
function Arenas.arenaFor(inst, need)
	local id = inst and inst:GetAttribute("ArenaId")
	local floorId = inst and inst:GetAttribute("Floor")
	return Arenas.find(id, floorId, need)
end

function Arenas.find(id, floorId, need)
	local key = tostring(id) .. "|" .. tostring(floorId) .. "|" .. tostring(need)
	local hit = cache[key]
	if hit and hit.Parent == Workspace and hit:GetAttribute("ArenaId") == id then
		return hit
	end
	local found = nil
	for _, c in ipairs(Workspace:GetChildren()) do
		if isArena(c) and (need == nil or c:GetAttribute(need) ~= nil) then
			if id ~= nil then
				if c:GetAttribute("ArenaId") == id then
					found = c
					break
				end
			elseif floorId ~= nil and c:GetAttribute("Floor") == floorId then
				found = c
				break
			end
		end
	end
	cache[key] = found
	return found
end

-- the arena the player is in now (or nil)
function Arenas.mine(player, need)
	local floorId = player and player:GetAttribute("SpireFloor")
	if not floorId then
		return nil
	end
	return Arenas.find(player:GetAttribute("SpireArena"), floorId, need)
end

-- is `inst` built inside this arena? (no arena known: yes)
function Arenas.inside(arena, inst)
	return arena == nil or (inst ~= nil and inst:IsDescendantOf(arena))
end

-- A boss's folder of props in Workspace (TuberProps, PetalinaProps...): the
-- one with its ArenaId (with no ids, the one by that name).
function Arenas.folderFor(inst, name)
	local id = inst and inst:GetAttribute("ArenaId")
	if id == nil then
		return Workspace:FindFirstChild(name)
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c.Name == name and c:GetAttribute("ArenaId") == id then
			return c
		end
	end
	return nil
end

return Arenas
