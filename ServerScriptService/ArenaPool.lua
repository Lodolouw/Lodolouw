--[[
	ArenaPool  (ModuleScript, parent: ServerScriptService, name: "ArenaPool")

	ARENA COPIES. Everyone who goes up a Spire floor (on their own, or as a
	party) gets that floor's arena to themselves, with a boss of their own.
	Eight players grinding the same floor solo are in eight copies, each
	fighting their own boss.

	  * At start (Main calls Start once the builders are done, before
	    BossService), each floor's arena becomes its first copy (ArenaId
	    "<floor>-1"). A clean snapshot of it is kept out of the world - the
	    template - from before any fight has broken a pillar.
	  * Acquire(floorId, players): an empty copy of that floor whose boss is
	    asleep - the one these players had last time if it's free (it's
	    probably still loaded on their screens) - or a new one: the template
	    cloned and moved out to a free slot (a grid 2600 studs apart, well north
	    of everything else). Copies are only moved, never turned: the bosses'
	    plans are laid out along the world's axes. The attributes that hold
	    world positions (Center, RunwayA/B, Bin) are moved with it, and the
	    Sunken Dunes' sand (Terrain, which a clone doesn't bring) is poured
	    again at the new spot.
	  * Prepare(floorId, player): as you open the Spire menu, the copy you'd
	    most likely get is held for you for a minute, so it can load in while
	    you choose.
	  * Leave(player): out of their copy (back in the lobby, dead or gone). An
	    empty copy's boss resets itself (BossService) and the copy waits for
	    the next player. One nobody has used for a few minutes is taken down
	    (never a floor's first copy).
	BossService builds each copy's boss when the copy appears (its BossHome
	tag) and takes it down when it goes. ReplicatedStorage/Arenas is how
	everything else tells the copies apart.

	Not started (a test with no pool): Acquire hands out the floor's one arena.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ArenaPool = {}

-- where copies go: a grid of slots 2600 studs apart (the same spacing as the
-- first arenas), in rows from z = 10400 northwards - everything built today
-- lies within 6300 studs of the middle. On y = 0 (the Dunes' sand and the
-- slime pit are built around it), on multiples of 4 (Terrain's voxels).
local SLOT_GAP = 2600
local SLOT_X0, SLOT_Z0 = -7800, 10400
local SLOT_COLS = 7
local MAX_COPIES = 42 -- (six rows: far more than a full server can use)
local IDLE_TIME = 180 -- an unused copy is taken down after this long (seconds)
local HOLD_TIME = 60 -- how long a copy is kept for someone with the menu open
local SMALL_SHADOW = 5 -- (Main's rule: small parts cast no shadow)
-- attributes holding world positions, moved along with a copy
local WORLD_SPOTS = { "Center", "RunwayA", "RunwayB", "Bin" }

local started = false
local terrainOf = {} -- [arena model name] = its builder (PaintTerrain/ClearTerrain)
local templates = {} -- [floorId] = { model = (out of the world), anchor = Vector3 }
local copies = {} -- [ArenaId] = copy
local byFloor = {} -- [floorId] = { copy, ... } in the order they were made
local made = {} -- [floorId] = how many copies have been numbered
local slotUsed = {} -- [slot] = copy
local seat = {} -- [player] = the copy they're in
local last = {} -- [player] = { [floorId] = the copy they had last }

-- the top-level model something belongs to (the arena itself)
local function arenaRoot(inst)
	local a = inst
	while a and a.Parent and a.Parent ~= Workspace do
		a = a.Parent
	end
	return (a and a.Parent == Workspace) and a or nil
end

local function floorOf(arena)
	return arena:GetAttribute("Floor") or 1
end

-- The one arena of a floor, as before copies (and with no pool): the model
-- round the first ArenaSpawn on that floor.
local function firstArena(floorId)
	for _, anchor in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
		local arena = anchor:FindFirstAncestorWhichIsA("Model")
		if arena and floorOf(arena) == floorId then
			return arena
		end
	end
	return nil
end

-- the spot an arena is laid out round, flat (its Center, or its boss's home)
local function anchorOf(arena)
	local c = arena:GetAttribute("Center")
	if typeof(c) == "Vector3" then
		return Vector3.new(c.X, 0, c.Z)
	end
	for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
		if h:IsDescendantOf(arena) then
			local p = h.Position
			return Vector3.new(math.floor(p.X / 4 + 0.5) * 4, 0, math.floor(p.Z / 4 + 0.5) * 4)
		end
	end
	local ok, cf = pcall(function()
		return arena:GetPivot()
	end)
	local p = ok and cf and cf.Position or Vector3.zero
	return Vector3.new(math.floor(p.X / 4 + 0.5) * 4, 0, math.floor(p.Z / 4 + 0.5) * 4)
end

local function slotCenter(slot)
	local col = (slot - 1) % SLOT_COLS
	local row = math.floor((slot - 1) / SLOT_COLS)
	return Vector3.new(SLOT_X0 + col * SLOT_GAP, 0, SLOT_Z0 + row * SLOT_GAP)
end

----------------------------------------------------------------------
-- A copy's boss: asleep (ready for someone new) or not
----------------------------------------------------------------------
local function bossOf(copy)
	for _, b in ipairs(CollectionService:GetTagged("Boss")) do
		if b:GetAttribute("ArenaId") == copy.id then
			return b
		end
	end
	return nil
end

local function asleep(copy)
	local b = bossOf(copy)
	return b == nil or b:GetAttribute("State") == "Dormant"
end

-- Can these players have this copy? Nobody in it, not kept for someone else,
-- and its boss asleep (a boss sinking back after the last fight is ready a
-- few seconds later).
local function freeFor(copy, players)
	if next(copy.members) ~= nil then
		return false
	end
	if copy.heldBy and os.clock() < copy.heldUntil and not table.find(players, copy.heldBy) then
		return false
	end
	return asleep(copy)
end

----------------------------------------------------------------------
-- Making and taking down copies
----------------------------------------------------------------------
local function register(copy)
	copies[copy.id] = copy
	byFloor[copy.floor] = byFloor[copy.floor] or {}
	table.insert(byFloor[copy.floor], copy)
	if copy.slot then
		slotUsed[copy.slot] = copy
	end
end

local function shiftSpots(inst, offset)
	for _, name in ipairs(WORLD_SPOTS) do
		local v = inst:GetAttribute(name)
		if typeof(v) == "Vector3" then
			inst:SetAttribute(name, v + offset)
		end
	end
end

local function makeCopy(floorId)
	local t = templates[floorId]
	if not t then
		return nil
	end
	local slot = nil
	for i = 1, MAX_COPIES do
		if not slotUsed[i] then
			slot = i
			break
		end
	end
	if not slot then
		warn("[ArenaPool] every arena slot is in use")
		return nil
	end
	made[floorId] = (made[floorId] or 1) + 1
	local id = floorId .. "-" .. made[floorId]
	local offset = slotCenter(slot) - t.anchor
	local model = t.model:Clone()
	-- moved out to its slot BEFORE it's in the world, so nothing ever sees it
	-- at the first arena's spot
	model:PivotTo(model:GetPivot() + offset)
	shiftSpots(model, offset)
	for _, d in ipairs(model:GetDescendants()) do
		shiftSpots(d, offset)
		if d:IsA("BasePart") and d.CastShadow then
			local size = d.Size
			if math.max(size.X, size.Y, size.Z) < SMALL_SHADOW then
				d.CastShadow = false
			end
		end
	end
	model:SetAttribute("ArenaId", id)
	model:SetAttribute("Copy", made[floorId])
	pcall(function()
		-- loaded only on the screens of the players in it (SpireService)
		model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	end)
	local builder = terrainOf[model.Name]
	if builder and builder.PaintTerrain then
		local ok, err = pcall(builder.PaintTerrain, offset)
		if not ok then
			warn("[ArenaPool] couldn't pour the sand for " .. id .. ": " .. tostring(err))
		end
	end
	model.Parent = Workspace
	local copy = {
		id = id,
		floor = floorId,
		model = model,
		slot = slot,
		offset = offset,
		members = {},
		lastUsed = os.clock(),
		first = false,
	}
	register(copy)
	return copy
end

local function takeDown(copy)
	copies[copy.id] = nil
	local list = byFloor[copy.floor]
	local i = list and table.find(list, copy)
	if i then
		table.remove(list, i)
	end
	if copy.slot then
		slotUsed[copy.slot] = nil
	end
	local builder = terrainOf[copy.model.Name]
	if builder and builder.ClearTerrain then
		pcall(builder.ClearTerrain, copy.offset)
	end
	copy.model:Destroy() -- (its boss goes with it: BossService watches its BossHome)
end

-- the copy to hand these players: the one kept for them, the one they had
-- last time, any free one - or a new one (make = false: never a new one)
local function pick(floorId, players, make)
	local who = players[1]
	local list = byFloor[floorId] or {}
	for _, copy in ipairs(list) do
		if copy.heldBy == who and os.clock() < copy.heldUntil and freeFor(copy, players) then
			return copy
		end
	end
	local before = who and last[who] and last[who][floorId]
	if before and copies[before.id] == before and freeFor(before, players) then
		return before
	end
	for _, copy in ipairs(list) do
		if freeFor(copy, players) then
			return copy
		end
	end
	if make then
		return makeCopy(floorId)
	end
	return nil
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

-- An arena of this floor for these players (a party goes in together): its
-- model, or nil if none can be had.
function ArenaPool.Acquire(floorId, players)
	if not started then
		return firstArena(floorId)
	end
	for _, p in ipairs(players) do
		ArenaPool.Leave(p)
	end
	local copy = pick(floorId, players, true)
	if not copy then
		return nil
	end
	copy.heldBy, copy.heldUntil = nil, 0
	for _, p in ipairs(players) do
		copy.members[p] = true
		seat[p] = copy
	end
	copy.lastUsed = os.clock()
	return copy.model
end

-- The arena this player would most likely get on this floor, kept for them a
-- minute (they've just opened the Spire menu): its model.
function ArenaPool.Prepare(floorId, player)
	if not started then
		return firstArena(floorId)
	end
	local copy = pick(floorId, { player }, true)
	if not copy then
		return nil
	end
	copy.heldBy, copy.heldUntil = player, os.clock() + HOLD_TIME
	return copy.model
end

-- Out of their copy (back in the lobby, dead, or gone).
function ArenaPool.Leave(player)
	local copy = seat[player]
	seat[player] = nil
	if copy then
		copy.members[player] = nil
		copy.lastUsed = os.clock()
		last[player] = last[player] or {}
		last[player][copy.floor] = copy
	end
end

-- The arena model a player is in (nil: none), and who's in an arena.
function ArenaPool.ArenaOf(player)
	local copy = seat[player]
	return copy and copy.model or nil
end
function ArenaPool.Members(arena)
	local id = arena and arena:GetAttribute("ArenaId")
	local copy = id and copies[id]
	local list = {}
	if copy then
		for p in pairs(copy.members) do
			list[#list + 1] = p
		end
	end
	return list
end

-- For tests and tools: every copy of a floor (models, in the order made).
function ArenaPool.CopiesOf(floorId)
	local list = {}
	for _, copy in ipairs(byFloor[floorId] or {}) do
		list[#list + 1] = copy.model
	end
	return list
end

-- Tidying up: copies nobody has used for a while are taken down.
function ArenaPool.Tidy(nowClock)
	local t = nowClock or os.clock()
	for _, copy in pairs(copies) do
		if not copy.first and next(copy.members) == nil and not (copy.heldBy and t < copy.heldUntil)
			and t - copy.lastUsed >= IDLE_TIME and asleep(copy) then
			takeDown(copy)
		end
	end
end

-- terrain: { [arena model name] = its builder }, for the arenas whose ground is
-- Terrain (the builder's PaintTerrain(offset) / ClearTerrain(offset))
function ArenaPool.Start(terrain)
	if started then
		return
	end
	started = true
	terrainOf = terrain or {}
	for _, spawn in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
		local arena = arenaRoot(spawn)
		if arena then
			local floorId = floorOf(arena)
			if not templates[floorId] then
				-- the clean snapshot first (no id on it: each copy gets its own)
				templates[floorId] = { model = arena:Clone(), anchor = anchorOf(arena) }
				arena:SetAttribute("ArenaId", floorId .. "-1")
				arena:SetAttribute("Copy", 1)
				made[floorId] = 1
				register({
					id = floorId .. "-1",
					floor = floorId,
					model = arena,
					offset = Vector3.zero,
					members = {},
					lastUsed = 0,
					first = true,
				})
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		ArenaPool.Leave(player)
		last[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(15)
			local ok, err = pcall(ArenaPool.Tidy)
			if not ok then
				warn("[ArenaPool] tidying failed: " .. tostring(err))
			end
		end
	end)
end

return ArenaPool
