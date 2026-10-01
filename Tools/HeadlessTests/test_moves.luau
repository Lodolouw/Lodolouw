--!nocheck
-- Headless test of WEAPON ABILITY MOVES on the server (CombatService, "MOVES";
-- the moves themselves: ReplicatedStorage/Moves). For every launch weapon a
-- pretend player uses its ability among punchable dummies, moving the way the
-- move says (the client's job, done here by hand), and it checks:
--   * it only hurts what it should: something close in front, never a dummy
--     far away, and nothing before its first hitting step is due
--   * the patches it leaves keep hurting (zones), things thrown travel and hit
--   * a spot it picks is the dummy you're locked on to, and every screen is
--     told (AbilityFx): the start, the spot
--   * building blocks switch on (the aura, its style)
--   * specials: No Quarter's gold wave on chops, Copy-Paste's copies swinging
--     beside you, Victory Lap's rolls cutting through
--   * cooldowns and stamina
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local CollectionService = M.services.CollectionService

RunService.IsStudio = function()
	return true
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Moves = mount.require(mount.module("ReplicatedStorage/Moves.lua"))
local CombatService = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local W = Config.Weapons

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local data = { Power = Config.powerForLevel(30), Weapons = { own = {}, hold = nil } }
local PlayerService = {
	GetData = function()
		return data
	end,
	AddAction = function() end,
	MarkDirty = function() end,
}

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
M.players = { me }
local char = Instance.new("Model")
char.Name = "Tester"
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.Size = Vector3.new(2, 2, 1)
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.Parent = char
local hum = Instance.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 100
hum.WalkSpeed = 16
hum.Parent = char
char.Parent = M.workspace
me.Character = char

local t = 0
local timers = {} -- things the pretend client does at given times
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Heartbeat:Fire(1 / 60)
		for i = #timers, 1, -1 do
			if t >= timers[i].at then
				local fn = timers[i].fn
				table.remove(timers, i)
				fn()
			end
		end
	end
end
local function after(dt, fn)
	table.insert(timers, { at = t + dt, fn = fn })
end

CombatService.Start(PlayerService)
local remotes = M.services.ReplicatedStorage:FindFirstChild("CombatRemotes")
local action = remotes.CombatAction
check(remotes:FindFirstChild("AbilityFx") ~= nil, "there's an AbilityFx remote for every screen")
local told = {}
remotes.AbilityFx.FireAllClients = function(self, player, id, count, stepN, point, extra)
	table.insert(told, { player = player, id = id, count = count, step = stepN, point = point, extra = extra, t = t })
end
local events = {}
remotes.CombatEvent.FireClient = function(self, player, kind, ...)
	table.insert(events, { kind = kind, args = { ... }, t = t })
end
me:SetAttribute("SpireFloor", 2)
step(0.2)

-- dummies: a grid in front (facing -Z), a few round you, one far away
local dummies = {}
local function target(name, x, z)
	local m = Instance.new("Model")
	m.Name = name
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 2)
	body.CFrame = CFrame.new(x, 3, z)
	body.Parent = m
	m.PrimaryPart = body
	m:SetAttribute("MaxHealth", 1e12)
	m:SetAttribute("Health", 1e12)
	m:SetAttribute("HitRadius", 1)
	m:SetAttribute("NoBar", true)
	m.Parent = M.workspace
	CollectionService:AddTag(m, "CombatTarget")
	table.insert(dummies, m)
	return m
end
for _, z in ipairs({ -4, -8, -12, -16, -20 }) do
	for _, x in ipairs({ -3, 0, 3 }) do
		target(("Front%d_%d"):format(x, z), x, z)
	end
end
target("Left", -6, 0)
target("Right", 6, 0)
target("Behind", 0, 6)
local far = target("Far", 0, -120)
local lock = M.workspace:FindFirstChild("Front0_-12")
step(0.2)

local function lostBy(m)
	return 1e12 - m:GetAttribute("Health")
end
local function heal()
	for _, m in ipairs(dummies) do
		m:SetAttribute("Health", 1e12)
		m:SetAttribute("SlowUntil", nil)
	end
end
local function totalLost()
	local sum = 0
	for _, m in ipairs(dummies) do
		sum += lostBy(m)
	end
	return sum
end
local function fire(...)
	action.OnServerEvent:Fire(me, ...)
end
local function standAt(pos, look)
	hrp.CFrame = CFrame.lookAt(pos, pos + (look or Vector3.new(0, 0, -1)))
end

-- does the move hurt anything? (a Hit, a Shot or a Zone somewhere)
local function firstDamageAt(move)
	local first = nil
	for _, s in ipairs(move.Steps or {}) do
		if s.Hit or s.Shot or s.Zone then
			first = math.min(first or math.huge, s.At or 0)
		end
	end
	return first
end

-- the pretend client: move the body the way the move's steps say
local function playMoves(move)
	for _, s in ipairs(move.Steps or {}) do
		if s.Move then
			local m = s.Move
			after((s.At or 0) + 0.001, function()
				local from = hrp.Position
				local dir = Vector3.new(0, 0, -1)
				local dist = m.Distance or 8
				if m.ToTarget then
					local p = lock:GetPivot().Position
					local flat = Vector3.new(p.X - from.X, 0, p.Z - from.Z)
					dir = flat.Unit
					dist = math.clamp(flat.Magnitude - (m.StopShort or 3), 0, dist * 1.4)
				end
				-- (along the way, then there when its time is up)
				local n = 6
				for k = 1, n do
					after((m.Time or 0.3) * k / n, function()
						standAt(from + dir * dist * k / n, dir)
					end)
				end
			end)
		end
	end
end

----------------------------------------------------------------------
-- Every launch weapon's ability
----------------------------------------------------------------------
local ids = {}
for _, pack in ipairs(W.Packs) do
	for _, id in ipairs(pack.Weapons) do
		table.insert(ids, id)
	end
end
check(#ids == 30, "30 launch weapons (" .. #ids .. ")")

for _, id in ipairs(ids) do
	local def = W.List[id]
	local move = Moves.of(id)
	check(move ~= nil, id .. ": has a move (ReplicatedStorage/Moves)")
	check(def.Ability and def.Ability.Burst == nil, id .. ": no stand-in burst left")
	if move then
		-- fresh: full stamina, ready, standing at the start facing the dummies
		step(20)
		standAt(Vector3.new(0, 3, 0))
		CombatService.Equip(me, id)
		step(0.3)
		heal()
		told = {}
		events = {}
		local t0 = t
		playMoves(move)
		fire("Ability", lock)
		local firstHit = firstDamageAt(move)
		local lostEarly = 0
		if firstHit and firstHit > 0.05 then
			step(firstHit - 0.04)
			lostEarly = totalLost()
		end
		-- (long enough for every step, zone and thing thrown)
		local last = 0
		for _, s in ipairs(move.Steps or {}) do
			last = math.max(last, (s.At or 0) + (s.Zone and s.Zone.Time or 0) + (s.Shot and 1.5 or 0) + 0.3)
		end
		step(math.max(0.1, last - (t - t0)))
		local lost = totalLost()
		-- (a Contact step - Barrel Roll's burst - goes off early on running
		-- into an enemy: here, early is the point)
		local contact = false
		for _, st in ipairs(move.Steps or {}) do
			contact = contact or st.Contact ~= nil
		end
		if contact then
			check(lostEarly > 0, ("%s: it bursts the moment it runs into them, before its time (%.1f early)"):format(id, lostEarly))
		else
			check(lostEarly == 0, ("%s: nothing hurt before its first hit is due (%.1f lost early)"):format(id, lostEarly))
		end
		check(lostBy(far) == 0, id .. ": the dummy 120 studs away is never touched")
		if firstHit then
			check(lost > 0, id .. ": it hurts what's close in front")
		else
			check(lost == 0, id .. ": a buff alone hurts nothing")
		end
		-- every screen is told it started, and where any spot it picked is
		local started, picked = false, nil
		for _, e in ipairs(told) do
			if e.id == id and e.step == 0 then
				started = true
			elseif e.id == id and type(e.step) == "number" and e.step > 0 then
				picked = e.point
			end
		end
		check(started, id .. ": every screen is told the move started")
		for i, s in ipairs(move.Steps or {}) do
			if s.Pick then
				local want = lock:GetPivot().Position
				check(picked ~= nil and (Vector3.new(picked.X, 0, picked.Z) - Vector3.new(want.X, 0, want.Z)).Magnitude < 0.5,
					id .. ": the spot it picks is the dummy you're locked on to (step " .. i .. ")")
			end
		end
		-- the building blocks and their look
		if def.Ability.Effects and #def.Ability.Effects > 0 then
			local timed = false
			for _, e in ipairs(def.Ability.Effects) do
				timed = timed or (e.Time ~= nil)
			end
			if timed then
				check(me:GetAttribute("AuraStyle") == move.Style, id .. ": its aura has its style (" .. tostring(move.Style) .. ")")
			end
		end
		-- a zone keeps hurting after the hit
		for _, s in ipairs(move.Steps or {}) do
			if s.Zone then
				heal()
				-- (a new use, then just after the zone's laid: it should still be hurting)
				step(20)
				standAt(Vector3.new(0, 3, 0))
				playMoves(move)
				fire("Ability", lock)
				step((s.At or 0) + 0.4)
				heal()
				step(1.2)
				check(totalLost() > 0, id .. ": the patch it leaves keeps hurting")
				local slowed = false
				for _, m in ipairs(dummies) do
					slowed = slowed or (m:GetAttribute("SlowUntil") ~= nil)
				end
				if s.Zone.Slow then
					check(slowed, id .. ": its patch slows what's in it")
				end
				step(s.Zone.Time + 0.5)
				break
			end
		end
		-- the cooldown: pressing again straight away does nothing
		step(20)
		standAt(Vector3.new(0, 3, 0))
		fire("Ability", lock)
		step(0.05)
		heal()
		events = {}
		fire("Ability", lock)
		step(0.1)
		local denied = false
		for _, e in ipairs(events) do
			denied = denied or (e.kind == "Denied")
		end
		check(denied, id .. ": it can't be used again until its cooldown's over")
		step(3)
	end
end

----------------------------------------------------------------------
-- Specials
----------------------------------------------------------------------
-- No Quarter: every chop sends out a gold wave that hurts a little more
step(20)
standAt(Vector3.new(0, 3, 0))
CombatService.Equip(me, "NoQuarter")
step(0.3)
fire("Ability", lock)
step(2)
heal()
told = {}
fire("Punch", nil, 1)
step(1)
local waved = false
for _, e in ipairs(told) do
	waved = waved or e.step == "ChopWave"
end
check(waved, "No Quarter: a chop sends out a gold wave (every screen told)")
check(lostBy(M.workspace:FindFirstChild("Front0_-4")) > 0, "No Quarter: the chop and its wave hurt what's in front")

-- Copy-Paste: your two copies swing beside you
step(20)
standAt(Vector3.new(0, 3, 0))
CombatService.Equip(me, "CopyPasteScythe")
step(0.3)
fire("Ability", lock)
step(1)
heal()
told = {}
fire("Punch", nil, 1)
step(1.2)
local copied = false
for _, e in ipairs(told) do
	copied = copied or e.step == "Clones"
end
check(copied, "Copy-Paste: your copies swing with you (every screen told)")
check(lostBy(M.workspace:FindFirstChild("Front-3_-4")) > 0 or lostBy(M.workspace:FindFirstChild("Front3_-4")) > 0,
	"Copy-Paste: the copies beside you cut too")

-- Victory Lap: every roll cuts through what it passes
step(20)
standAt(Vector3.new(0, 3, 0))
CombatService.Equip(me, "VictoryLap")
step(0.3)
fire("Ability", lock)
step(0.8)
heal()
told = {}
standAt(Vector3.new(3, 3, 0))
fire("Roll")
after(0.2, function()
	standAt(Vector3.new(3, 3, -14))
end)
step(0.6)
local dashed = false
for _, e in ipairs(told) do
	dashed = dashed or e.step == "DashHit"
end
check(dashed, "Victory Lap: a roll cuts through (every screen told)")
check(lostBy(M.workspace:FindFirstChild("Front3_-8")) > 0, "Victory Lap: the roll hurts what it passes")
step(6)

-- Goo Gloves: the fifth punch splats (every screen sees the stacks burst)
step(20)
standAt(Vector3.new(0, 3, 0))
CombatService.Equip(me, "GooGloves")
step(0.3)
told = {}
for _ = 1, 5 do
	fire("Punch", nil, 1)
	step(0.8)
end
local splat = false
for _, e in ipairs(told) do
	splat = splat or e.step == "Stacks"
end
check(splat, "Goo Gloves: the fifth hit bursts the stacks (every screen told)")

if fails == 0 then
	print("PASS moves")
else
	print(fails .. " failures")
end
