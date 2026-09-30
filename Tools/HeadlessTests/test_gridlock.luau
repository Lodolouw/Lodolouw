--!nocheck
-- GRIDLOCK (floor 6) in the pretend Roblox: the real GridBuilder level, the
-- real BossService with Bosses/Gridlock.lua (his own brain and step, the beat,
-- the tile patterns - ReplicatedStorage/BeatGrid), and (client mode) the real
-- BossClient drawing him with BossBodies/Gridlock.lua on a pretend player's
-- screen. Pretend players circle him, roll now and then, jump now and then,
-- punch him when he's in reach (using the shape his file gives
-- CombatService) and rush in when he's stunned or stuck. The jump pads really
-- throw them up (a pretend CombatService.Launch).
--   luau test_gridlock.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both rounds)
--   attacks  every move forced in turn, in round 1 and round 2 (in its form,
--            the right way up), on a player standing where it reaches (each
--            must land) - then again on one who rolls through everything
--   reset    the player leaves mid-fight (he stops, goes home as a cube, the
--            right way up), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll as a slam or a spike lands
--            dodges it, a roll far too early gets you hit
--   drop     THE DROP: a player on a jump pad (thrown up) is safe, one on a
--            plain tile is hit, one rolling on the beat is safe, and one
--            hiding on the runway is hit too
--   pads     a jump pad throws you up (and not again straight away)
-- It checks: no errors or warnings, no broken numbers, he never leaves the
-- grid, his moves join up (no jumps), the level's hits land on the beat,
-- every form, the drop and the gravity flip are seen (and drawn, in client
-- mode), round 2 comes at half health, he dies, and the reward (Power) is
-- paid.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local args = { ... }
local SCENARIO = args[1] or "full"
local SEED = tonumber(args[2]) or 1
local MODE = args[3] or "server"
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace

local problems = {}
local function problem(text)
	if #problems < 30 then
		table.insert(problems, text)
	end
end

----------------------------------------------------------------------
-- the world: the real Final Beat
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local BeatGrid = mount.require(mount.module("ReplicatedStorage/BeatGrid.lua"))
local arena = mount.require(mount.module("ServerScriptService/GridBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 6, "the level should be built as floor 6")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the level needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the level needs a way out (ArenaExit)")
assert(#CollectionService:GetTagged("JumpPad") == #BeatGrid.PADS, "every pad tile should have a jump pad")
local CENTER = arena:GetAttribute("Center")
local GRID = BeatGrid.grid(CENTER, arena:GetAttribute("Tiles"), arena:GetAttribute("TileSize"))
assert(GRID.n == 15 and GRID.size == 8, "the grid: 15 x 15 tiles of 8 studs")
local HALF = GRID.n * GRID.size / 2
local PAD_SPOTS = {}
for _, t in ipairs(BeatGrid.pads(GRID)) do
	table.insert(PAD_SPOTS, BeatGrid.tileCenter(GRID, t[1], t[2]))
end

----------------------------------------------------------------------
-- pretend players
----------------------------------------------------------------------
local T = 0
local people = {}
local inArena = {}
local rollUntil = {}
local function makePlayer(name, id)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.Parent = Players
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = spawnPart.CFrame
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	table.insert(people, p)
	M.players = table.clone(people)
	return p
end
local function rootOf(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
local function humOf(p)
	return p.Character and p.Character:FindFirstChildOfClass("Humanoid")
end
local function enter(p)
	inArena[p] = true
	p:SetAttribute("SpireFloor", 6)
end
local function leave(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
end

----------------------------------------------------------------------
-- CombatService and PlayerService, pretend
----------------------------------------------------------------------
local shapes = {}
local hitsOn, dodges, shoves = {}, 0, 0
local hitLog = {}
local launches = {} -- [player] = { t, speed } (a jump pad throwing them up)
local launchCount = 0
local Combat = {}
function Combat.PlayersInArena(floorId)
	local list = {}
	for _, p in ipairs(people) do
		if inArena[p] and p:GetAttribute("SpireFloor") == floorId then
			list[#list + 1] = p
		end
	end
	return list
end
function Combat.IsFighting(p)
	local hum = humOf(p)
	return inArena[p] == true and hum ~= nil and hum.Health > 0
end
function Combat.IsInvulnerable(p)
	return T < (rollUntil[p] or -1)
end
local model -- (set below)
function Combat.DamagePlayer(p, amount, from, knockback, quiet)
	if M.isNaNv and from and M.typeof(from) == "Vector3" and M.isNaNv(from) then
		problem("a hit came from a broken position")
	end
	if knockback and M.isNaNv and M.isNaNv(knockback) then
		problem("a hit threw someone a broken way")
	end
	if amount ~= amount or amount <= 0 then
		problem("a hit with a broken amount: " .. tostring(amount))
	end
	if Combat.IsInvulnerable(p) then
		dodges += 1
		return false
	end
	local act = model and model:GetAttribute("Action") or "?"
	if quiet then
		act = act .. "(fire)"
	end
	hitsOn[act] = (hitsOn[act] or 0) + 1
	table.insert(hitLog, { t = M.now(), act = act, p = p })
	local hum = humOf(p)
	if hum then
		hum.Health = math.max(1, hum.Health - amount)
	end
	return true
end
function Combat.Shove()
	shoves += 1
end
function Combat.SetTargetShape(m, fn)
	shapes[m] = fn
end
function Combat.OnWhiff() end
function Combat.Launch(p, velocity)
	launchCount += 1
	launches[p] = { t = T, speed = velocity.Y }
end
local rewards = { power = 0, kills = 0 }
local Profile = {}
function Profile.RecordBossKill(p, floorId)
	rewards.kills += 1
	return true
end
function Profile.AddPower(p, n)
	rewards.power += n
end

-- (one boss: only Gridlock's home stays marked)
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 6 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
local victories = 0
M.onFireClient = function(remote, p, kind, ...)
	if kind == "Victory" then
		victories += 1
	end
	if MODE == "client" and p == Players.LocalPlayer and remote.OnClientEvent then
		remote.OnClientEvent:Fire(kind, ...)
	end
end
BS.Start(Combat, Profile)
local E = assert(BS.Encounter(6), "Gridlock should be built on floor 6")
model = E.model
local def = E.def
assert(def.Short == "Gridlock", "floor 6's boss should be Gridlock")
assert(shapes[model], "Gridlock should give CombatService his body shape")
local Boss = E.boss
local home, floorY = E.home, E.floorY

----------------------------------------------------------------------
-- client mode: his body on the first player's screen
----------------------------------------------------------------------
local drawn, guis = {}, {}
local maxParts = 0
if MODE == "client" then
	local me = makePlayer("Alpha", 1001)
	Players.LocalPlayer = me
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = me
	local scripts = Instance.new("PlayerScripts")
	scripts.Name = "PlayerScripts"
	scripts.Parent = me
	local kick = Instance.new("BindableEvent")
	kick.Name = "CombatCameraKick"
	kick.Parent = scripts
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.new(home + Vector3.new(0, 30, 70), home)
	cam.FieldOfView = 70
	cam.Parent = workspace
	workspace.CurrentCamera = cam
	math.randomseed(SEED)
	mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)
end
local function lookAtDrawing()
	local fx = workspace:FindFirstChild("BossFX")
	if fx then
		local n = 0
		for _, d in ipairs(fx:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				if d.Transparency < 1 then
					drawn[d.Name] = true
				end
				local pr = rawget(d, "__props")
				if pr.CFrame and M.isNaNv and M.isNaNv(pr.CFrame.Position) then
					problem("a drawn part has a broken position: " .. d.Name)
				end
				local sz = pr.Size
				if sz and (sz.X ~= sz.X or sz.Y ~= sz.Y or sz.Z ~= sz.Z) then
					problem("a drawn part has a broken size: " .. d.Name)
				end
			end
		end
		maxParts = math.max(maxParts, n)
	end
	local me = Players.LocalPlayer
	local pg = me and me:FindFirstChild("PlayerGui")
	-- (words on the screen, and words floating over him in the world)
	for _, holder in ipairs({ pg, fx }) do
		for _, d in ipairs(holder and holder:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Text ~= "" and d.Visible ~= false then
				local anc = d:FindFirstAncestorWhichIsA("ScreenGui") or d:FindFirstAncestorWhichIsA("BillboardGui")
				if anc and anc.Enabled ~= false then
					guis[d.Text] = true
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- punching him, the way CombatService does (with his shape)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded = 0
local function punch(p, share)
	if not CollectionService:HasTag(model, "CombatTarget") or (model:GetAttribute("Health") or 0) <= 0 then
		return
	end
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return
	end
	local root = rootOf(p)
	local ok, point, radius = pcall(shapes[model], root.Position)
	if not ok or M.typeof(point) ~= "Vector3" then
		problem("his body shape failed: " .. tostring(point))
		return
	end
	local gap = (Vector3.new(point.X, 0, point.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - radius
	if gap > PUNCH_RANGE or math.abs(point.Y - root.Position.Y) >= 12 then
		return
	end
	lastPunch[p] = T
	local damage = math.max(1, math.floor((model:GetAttribute("MaxHealth") or 1) * share))
	if model:GetAttribute("Invulnerable") then
		damage = 0
	end
	local floorHp = model:GetAttribute("MinHealth") or 0
	local before = model:GetAttribute("Health") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	model:SetAttribute("Health", math.max(0, hp))
	if damage > 0 then
		punchesLanded += 1
	end
	model:FindFirstChild("OnHit"):Fire(p, damage, hp <= 0)
end

----------------------------------------------------------------------
-- how the pretend players move
----------------------------------------------------------------------
local lastPos = {}
local function airOf(p)
	-- (thrown up by a pad: up and back down, gravity 196 studs/s/s)
	local l = launches[p]
	if not l then
		return 0
	end
	local e = T - l.t
	local y = l.speed * e - 98.1 * e * e
	if y <= 0 and e > 0.1 then
		launches[p] = nil
		return 0
	end
	return math.max(y, 0)
end
local function place(p, pos, dt)
	local root = rootOf(p)
	local old = lastPos[p] or pos
	local lifted = pos + Vector3.new(0, airOf(p), 0)
	root.CFrame = CFrame.new(lifted)
	root.AssemblyLinearVelocity = dt > 0 and (lifted - old) / dt or Vector3.new()
	lastPos[p] = Vector3.new(pos.X, pos.Y, pos.Z)
end
local function moveToward(from, to, speed, dt)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude <= speed * dt then
		return Vector3.new(to.X, from.Y, to.Z)
	end
	return from + d.Unit * speed * dt
end
-- keep on the grid (the real invisible walls do)
local function onGrid(pos)
	return Vector3.new(math.clamp(pos.X, CENTER.X - HALF + 1, CENTER.X + HALF - 1), pos.Y, math.clamp(pos.Z, CENTER.Z - HALF + 1, CENTER.Z + HALF - 1))
end
local OPEN = { Stunned = true, Idle = true }
-- A fighter: circles him at a distance that swells and shrinks, rolls every
-- few seconds and jumps every few more - and rushes to him when he's stunned,
-- stuck in the floor, or on the ground in round 2's pauses. During the drop
-- it runs for the nearest jump pad.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	local alt = center.Y - floorY
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local act = model:GetAttribute("Action")
	local want
	if act == "Drop" and style ~= "stay" then
		-- the nearest pad
		local best, bd = nil, math.huge
		for _, s in ipairs(PAD_SPOTS) do
			local d = (Vector3.new(s.X, 0, s.Z) - Vector3.new(base.X, 0, base.Z)).Magnitude
			if d < bd then
				best, bd = s, d
			end
		end
		want = best
	elseif style ~= "far" and (OPEN[act] or alt < 4) then
		-- right up to him, and hit him
		local out = Vector3.new(base.X - center.X, 0, base.Z - center.Z)
		out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, 1)
		want = center + out * 7
	end
	if not want then
		local r = (style == "far") and (40 + 8 * math.sin(phaseT * 0.4)) or (10 + 18 * (1 + math.sin(phaseT * 0.31)))
		local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
		local ang = phaseT * 0.6 * spin + k * 2
		want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 20
	local nextPos = onGrid(moveToward(base, want, speed, dt))
	local y = floorY + 3
	local jumpU = (phaseT % 3.1) / 0.6
	if jumpU < 1 then
		y = y + 4 * math.sin(math.pi * jumpU)
	end
	place(p, Vector3.new(nextPos.X, y, nextPos.Z), dt)
end

----------------------------------------------------------------------
-- watching him
----------------------------------------------------------------------
local seen, order = {}, {}
local formsSeen, gravitySeen = {}, {}
local maxOut = 0
local sawPhase2 = false
local lastMoveId, lastWhere, prevMove = nil, nil, nil
local jumps = 0
local maxSpeed = 0
local lastP = nil
local skipSpeed = false -- (a test just put him somewhere: that's not him moving)
local offBeat = 0
local checkedHits = 0
local ONBEAT = { HopSlam = true, SpikeRows = true, StompChain = true, CeilingDrop = true, BombRun = true, OrbRain = true,
	TilePattern = true, UfoSlam = true, Drop = true }
local function watch(dt)
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
		table.insert(order, act)
	end
	formsSeen[model:GetAttribute("Form") or "?"] = true
	gravitySeen[model:GetAttribute("Gravity") or 1] = true
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	maxOut = math.max(maxOut, math.abs(pos.X - CENTER.X), math.abs(pos.Z - CENTER.Z))
	local st = model:GetAttribute("State")
	if skipSpeed then
		skipSpeed = false
	elseif lastP and dt > 0 and st ~= "Resetting" and st ~= "Dormant" and st ~= "Dead" then
		-- (across the grid: his drops and flips fall fast on purpose)
		local v = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(lastP.X, 0, lastP.Z)).Magnitude / dt
		maxSpeed = math.max(maxSpeed, v)
		if v > 160 then
			problem(string.format("he moved %.0f studs/s at %.2f (a jump?) doing %s", v, T, tostring(act)))
		end
	end
	lastP = pos
	-- a new move must start where the last one had him (he never jumps)
	local id = model:GetAttribute("MoveId")
	if id ~= lastMoveId then
		lastMoveId = id
		local m = BeatGrid.readMove(model)
		if prevMove then
			local p1, h1 = BeatGrid.motion(prevMove, M.now())
			lastWhere = Vector3.new(p1.X, h1, p1.Z)
		end
		if m and lastWhere and st ~= "Resetting" and st ~= "Dormant" then
			local p0, h0 = BeatGrid.motion(m, m.t0)
			local gap = (Vector3.new(p0.X, h0, p0.Z) - lastWhere).Magnitude
			if gap > 2 then
				jumps += 1
				if jumps <= 3 then
					problem(string.format("his new move (%s, %s) starts %.1f away from where he was at %.2f (after a %s)", m.kind, tostring(act), gap, T,
						prevMove and prevMove.kind or "?"))
				end
			end
		end
		prevMove = m
	end
end
-- the level's hits land on the beat (in the first half of it) - each hit
-- checked once, against the beat of the fight it happened in
local beatsCheckedTo = 0
local function checkBeats(fromIndex)
	local b0 = model:GetAttribute("BeatStart")
	if not b0 then
		return
	end
	local len = BeatGrid.beatLen(def.Bpm)
	local first = math.max(fromIndex or 1, beatsCheckedTo + 1)
	beatsCheckedTo = #hitLog
	for i = first, #hitLog do
		local h = hitLog[i]
		if ONBEAT[h.act] then
			checkedHits += 1
			local x = (h.t - b0) / len
			local f = x - math.floor(x)
			if f > 0.56 and f < 0.98 then
				offBeat += 1
				if offBeat <= 3 then
					problem(string.format("%s hit %.2f of a beat after the beat (at %.2f)", h.act, f, h.t))
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- running it
----------------------------------------------------------------------
local DT = 1 / 30
local step = 0
local function tick(n, each)
	for _ = 1, n do
		step += 1
		T = T + DT
		M.run(T)
		if each then
			each(DT)
		end
		RunService.Heartbeat:Fire(DT)
		if MODE == "client" then
			RunService.RenderStepped:Fire(DT)
			if step % 5 == 0 then
				lookAtDrawing()
			end
		end
		watch(DT)
		if args[4] == "debug" and step % 45 == 0 then
			print(string.format("  t=%6.1f phase=%d hp=%.2f act=%s form=%s g=%s move=%s", T, E.phase,
				(model:GetAttribute("Health") or 0) / math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")),
				tostring(model:GetAttribute("Form")), tostring(model:GetAttribute("Gravity")), tostring(model:GetAttribute("MoveK"))))
		end
	end
end
local function runFor(seconds, each)
	tick(math.floor(seconds / DT + 0.5), each)
end
local function stateIs(s)
	return model:GetAttribute("State") == s
end
local share = 1 / 110
local function fightStepFor(list, standStill)
	return function(dt)
		for k, p in ipairs(list) do
			if inArena[p] and humOf(p).Health > 0 then
				if not standStill then
					fighterStep(p, k, dt, k == 2 and "far" or "near")
				end
				punch(p, share)
			end
		end
	end
end
local function fightUntil(list, cond, limit)
	local t0 = T
	local each = fightStepFor(list)
	while T - t0 < limit and not cond() do
		tick(3, each)
	end
end
local function walkIn(p)
	place(p, spawnPart.Position, 0)
	enter(p)
end
-- the height he has in a form (and hanging from the ceiling)
local function heightFor(form, gravity)
	if form == "Cube" and gravity == -1 then
		return (arena:GetAttribute("Ceiling") or def.Ceiling) - def.Size
	end
	return def.Forms[form].Height
end
-- stops his brain (a new token), puts him at `pos` in `form` (the right way
-- up, or on the ceiling), standing still
local function takeOver(pos, form, gravity)
	local waited = 0
	while not stateIs("Fighting") and waited < 20 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.contact = nil
	if form then
		E.form = form
		model:SetAttribute("Form", form)
		E.gravity = gravity or 1
		model:SetAttribute("Gravity", E.gravity)
	end
	if pos then
		local h = heightFor(E.form, E.gravity)
		local a = Vector3.new(pos.X, h, pos.Z)
		E.move = { kind = "Hold", t0 = M.now(), t1 = M.now() + 0.05, a = a, b = a, f = Vector3.new(0, 0, 1) }
		E.moveId = (model:GetAttribute("MoveId") or 0) + 1
		BeatGrid.writeMove(model, E.move, E.moveId)
		E.pos = Vector3.new(pos.X, floorY + h, pos.Z)
		prevMove = E.move
		lastMoveId = E.moveId
		skipSpeed = true
	end
	E.patterns = {}
	return E.token
end
local function mark()
	return #hitLog, dodges
end
local function since(m0)
	return #hitLog - m0
end

-- where each move is forced from: him a little west of the middle, the
-- player `spot` studs from him (x ahead, z to the side)
local START = CENTER + Vector3.new(-16, 0, 0)
local SPOTS = {
	HopSlam = Vector3.new(24, 0, 0),
	SpikeRows = Vector3.new(16, 0, 0),
	StompChain = Vector3.new(24, 0, 0),
	CeilingDrop = Vector3.new(8, 0, 8),
	BombRun = Vector3.new(24, 0, 0),
	Swoop = Vector3.new(32, 0, 0),
	UfoSlam = Vector3.new(20, 0, 0),
	OrbRain = Vector3.new(16, 0, 0),
	ZigZag = Vector3.new(32, 0, 0),
	TilePattern = Vector3.new(28, 0, 12), -- (off the middle row and column: some pairs keep those safe)
}

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1200)
	checkBeats()
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, asleep")
elseif SCENARIO == "duo" then
	local a = people[1] or makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1003)
	walkIn(a)
	walkIn(b)
	fightUntil({ a, b }, function()
		return stateIs("Dead")
	end, 1200)
	checkBeats()
	runFor(4)
elseif SCENARIO == "reset" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.8
	end, 400)
	checkBeats() -- (this fight's hits, against this fight's beat)
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	local pos = model:GetPivot().Position
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back in the middle after a reset")
	assert(model:GetAttribute("Form") == "Cube" and (model:GetAttribute("Gravity") or 1) == 1, "after a reset he should be a cube, the right way up")
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1200)
	checkBeats()
elseif SCENARIO == "attacks" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	local names = {}
	for n in pairs(def.Attacks) do
		names[#names + 1] = n
	end
	table.sort(names)
	local function force(name, dodge)
		local a = def.Attacks[name]
		local token = takeOver(START, a.Form or "Cube", a.Gravity or 1)
		E.target, E.targetSince = p, M.now()
		local o = SPOTS[name]
		launches[p] = nil -- (back on the ground, if a pad had thrown them up)
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0, d0 = mark()
		M.task.spawn(function()
			local ok, err = pcall(Boss.Attacks[name], E, token)
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		if dodge then
			rollUntil[p] = T + 13
		end
		runFor(12)
		rollUntil[p] = nil
		checkBeats(m0 + 1)
		return since(m0), dodges - d0
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			takeOver(START, "Cube", 1)
			M.task.spawn(function()
				Boss.brain(E, E.token)
			end)
			fightUntil({ p }, function()
				return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
			end, 600)
			assert(E.phase == 2, "round 2 should come at half health")
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if (a.Phase or 1) <= phase and (a.Gravity ~= -1 or phase == 2) then
				local landedN = force(name, false)
				local _, dodged = force(name, true)
				table.insert(report, string.format("p%d %s hit=%d dodged=%d", phase, name, landedN, dodged))
				if landedN == 0 then
					problem(name .. " (round " .. phase .. ") never hit a player standing where it reaches")
				end
				if dodged == 0 then
					problem(name .. " (round " .. phase .. ") couldn't be rolled through")
				end
			end
		end
	end
	print(table.concat(report, "\n"))
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	local len = BeatGrid.beatLen(def.Bpm)
	-- force `move` (in `form`), the player standing at `o` from him; roll at
	-- (its hit - `before`) seconds, the hit being `hitBeats` beats after the
	-- move's first beat (ActN); did it land?
	local function case(move, form, o, hitBeats, before, wantDodge, label)
		local token = takeOver(START, form, 1)
		E.target, E.targetSince = p, M.now()
		launches[p] = nil
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0, d0 = mark()
		M.task.spawn(function()
			Boss.Attacks[move](E, token)
		end)
		tick(1)
		local k0 = model:GetAttribute("ActN") or 0
		local hitAt = BeatGrid.beatTime(model:GetAttribute("BeatStart") or E.beat0, def.Bpm, k0 + hitBeats)
		local rollAt = hitAt - before
		local rolled = false
		while M.now() < hitAt + len * 0.6 do
			tick(1)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5
			end
		end
		rollUntil[p] = nil
		local landedHit = since(m0) > 0
		local dodged = dodges > d0 and not landedHit
		print(string.format("%-16s roll %.2fs before it hits: %s", label, before, landedHit and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver()
		runFor(3)
	end
	local hs = def.Attacks.HopSlam
	case("HopSlam", "Cube", Vector3.new(24, 0, 0), hs.Tell, 0.1, true, "hop slam late")
	case("HopSlam", "Cube", Vector3.new(24, 0, 0), hs.Tell, 0.9, false, "hop slam early")
	local sr = def.Attacks.SpikeRows
	case("SpikeRows", "Cube", Vector3.new(16, 0, 0), sr.Tell + 1, 0.1, true, "spike row late")
	case("SpikeRows", "Cube", Vector3.new(16, 0, 0), sr.Tell + 1, 0.9, false, "spike row early")
	local us = def.Attacks.UfoSlam
	case("UfoSlam", "Ufo", Vector3.new(4, 0, 0), us.Tell, 0.1, true, "ufo slam late")
	case("UfoSlam", "Ufo", Vector3.new(4, 0, 0), us.Tell, 0.9, false, "ufo slam early")
	local br = def.Attacks.BombRun
	case("BombRun", "Ship", Vector3.new(8, 0, 0), br.Tell, 0.1, true, "bomb late")
	case("BombRun", "Ship", Vector3.new(8, 0, 0), br.Tell, 0.9, false, "bomb early")
elseif SCENARIO == "drop" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	local len = BeatGrid.beatLen(def.Bpm)
	local function dropWith(where, how, wantHit, label)
		local token = takeOver(START, "Cube", 1)
		E.target, E.targetSince = p, M.now()
		launches[p] = nil
		place(p, where + Vector3.new(0, 3, 0), 0)
		local m0 = mark()
		M.task.spawn(function()
			Boss.Moves.Drop(E, token)
		end)
		tick(1)
		local k0 = model:GetAttribute("ActN") or 0
		local b0 = model:GetAttribute("BeatStart") or E.beat0
		local dropAt = BeatGrid.beatTime(b0, def.Bpm, k0 + def.Drop.Build)
		local rolled = false
		local stop = dropAt + len * (def.Drop.Stun + 2)
		local stunned = false
		while M.now() < stop do
			if how == "roll" and not rolled and M.now() >= dropAt - 0.1 then
				rolled = true
				rollUntil[p] = M.now() + 0.5
			end
			-- (standing there: on a pad the pretend pad keeps throwing them up)
			tick(1, function(dt)
				place(p, where + Vector3.new(0, 3, 0), dt)
			end)
			if model:GetAttribute("Action") == "Stunned" then
				stunned = true
			end
		end
		rollUntil[p] = nil
		local hitN = since(m0)
		print(string.format("%-22s %s", label, (hitN > 0) and "HIT" or "safe"))
		if wantHit and hitN == 0 then
			problem(label .. ": should be hit by the drop")
		elseif not wantHit and hitN > 0 then
			problem(label .. ": should be safe from the drop")
		end
		if not stunned then
			problem("after the drop he should be stunned")
		end
		checkBeats(m0 + 1)
		takeOver()
		runFor(2)
	end
	dropWith(PAD_SPOTS[1], "stand", false, "on a jump pad")
	dropWith(CENTER + Vector3.new(12, 0, 4), "stand", true, "on a plain tile")
	dropWith(CENTER + Vector3.new(12, 0, 4), "roll", false, "rolling on the beat")
	local ra, rb = arena:GetAttribute("RunwayA"), arena:GetAttribute("RunwayB")
	dropWith((ra + rb) / 2, "stand", true, "hiding on the runway")
elseif SCENARIO == "pads" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	takeOver(START, "Cube", 1)
	-- walk onto a pad and stand there a while
	local n0 = launchCount
	place(p, PAD_SPOTS[2] + Vector3.new(0, 3, 0), 0)
	local t0 = T
	local firstGap = nil
	local lastT = nil
	while T - t0 < 3 do
		tick(1, function(dt)
			place(p, PAD_SPOTS[2] + Vector3.new(0, 3, 0), dt)
		end)
		if launches[p] and launches[p].t ~= lastT then
			if lastT and not firstGap then
				firstGap = launches[p].t - lastT
			end
			lastT = launches[p].t
		end
	end
	print(string.format("pad: thrown up %d times in 3 seconds (a %.2fs gap)", launchCount - n0, firstGap or -1))
	if launchCount - n0 == 0 then
		problem("standing on a jump pad should throw you up")
	end
	if firstGap and firstGap < def.Pads.Cooldown - 0.05 then
		problem("a pad threw the same player up again too soon")
	end
	-- a tile without a pad doesn't
	local n1 = launchCount
	place(p, CENTER + Vector3.new(8, 3, 8), 0)
	launches[p] = nil
	runFor(1.5, function(dt)
		place(p, CENTER + Vector3.new(8, 3, 8), dt)
	end)
	if launchCount > n1 then
		problem("a plain tile shouldn't throw you up")
	end
else
	error("unknown scenario " .. SCENARIO)
end

----------------------------------------------------------------------
-- the verdict
----------------------------------------------------------------------
local hitList = {}
for k, v in pairs(hitsOn) do
	table.insert(hitList, k .. "=" .. v)
end
table.sort(hitList)
local forms = {}
for k in pairs(formsSeen) do
	table.insert(forms, k)
end
table.sort(forms)
print(string.format("time %.1f  state %s  phase %s  punches %d  hits on players: %s  dodged %d  shoves %d  pads %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, table.concat(hitList, " "), dodges, shoves, launchCount))
print("moves in order: " .. table.concat(order, " "))
print(string.format("forms: %s  upside down: %s  furthest from the middle %.1f (leash %d)  fastest %.0f studs/s  hits checked on the beat %d  reward power %d  victories %d",
	table.concat(forms, " "), tostring(gravitySeen[-1] == true), maxOut, def.Leash, maxSpeed, checkedHits, rewards.power, victories))
if MODE == "client" then
	local names = {}
	for k in pairs(drawn) do
		table.insert(names, k)
	end
	table.sort(names)
	print("drawn: " .. table.concat(names, " "))
	local words = {}
	for k in pairs(guis) do
		table.insert(words, k)
	end
	table.sort(words)
	print("screen words: " .. table.concat(words, " | "))
	print("most parts at once: " .. maxParts)
	local function needDrawn(list)
		for _, n in ipairs(list) do
			if not drawn[n] then
				problem("never drew " .. n)
			end
		end
	end
	local function needWords(list)
		for _, w in ipairs(list) do
			local found = false
			for k in pairs(guis) do
				if k == w or string.sub(k, 1, #w) == w then
					found = true
				end
			end
			if not found then
				problem('never showed "' .. w .. '"')
			end
		end
	end
	-- (his face and the level's warnings, every time)
	needDrawn({ "Core", "Edge", "Eye", "Pupil", "Brow", "Horn", "Mouth", "Tooth", "Shadow", "TileWarn" })
	if SCENARIO == "attacks" then
		needDrawn({ "ShipHull", "ShipWing", "ShipWingEdge", "ShipTrim", "ShipFlame", "UfoDisc", "UfoRim", "UfoDome", "UfoLight",
			"TractorBeam", "SlamFill", "WaveDart", "WaveEdge", "ZigDot", "LightWall", "LightWallCore", "SwoopLane", "SwoopArrow",
			"Bomb", "BombBand", "Orb", "DropLine", "Flash", "RingPiece", "TileSpike", "TileSpikeTip", "PortalPiece", "PadBeam",
			"DizzyStar", "EyeX" })
		needWords({ "BOMBS AWAY!", "ORB RAIN!", "STUCK! HIT HIM!", "STUNNED! HIT HIM!", "DROP!", "GRAVITY FLIP!" })
	elseif SCENARIO == "full" then
		needDrawn({ "TileSpike", "PortalPiece", "PadBeam", "DizzyStar", "EyeX", "GravityGlow", "LittleCube" })
		needWords({ "ATTEMPT 1", "FEEL THE BEAT!", "0%", "DROP IN 3", "GET ON A JUMP PAD!", "DROP!", "STUNNED! HIT HIM!",
			"GRAVITY FLIP!", "THE LEVEL IS UPSIDE DOWN", "LEVEL COMPLETE!", "ATTEMPTS: 1", "100%" })
	elseif SCENARIO == "drop" then
		needDrawn({ "TileSpike", "PadBeam", "DizzyStar" })
		needWords({ "DROP IN 3", "DROP!", "STUNNED! HIT HIM!" })
	end
end
if maxOut > def.Leash + 6 then
	problem(string.format("he went %.1f from the middle (leash %d)", maxOut, def.Leash))
end
if SCENARIO == "full" or SCENARIO == "duo" or SCENARIO == "reset" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("he should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 then
		problem("beating him should pay Power")
	end
	if not sawPhase2 then
		problem("round 2 never came")
	end
	for _, name in ipairs({ "Wake", "Break", "Death", "Drop", "Stunned", "Portal" }) do
		if not seen[name] then
			problem("never saw " .. name)
		end
	end
	if not gravitySeen[-1] then
		problem("the gravity never flipped")
	end
	if checkedHits == 0 then
		problem("no hits from the level were checked against the beat")
	end
end
for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
if #M.errors > 0 then
	problem(#M.errors .. " errors")
end
if (M.warnings or 0) > 0 then
	problem((M.warnings or 0) .. " warnings")
end
for _, t in ipairs(problems) do
	print("PROBLEM " .. t)
end
if #problems == 0 then
	print("PASS")
end
