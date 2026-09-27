--!nocheck
-- SPEEDY REVVINGTON (floor 5) in the pretend Roblox: the real SpeedwayBuilder
-- track, the real BossService with Bosses/Revvington.lua (his own brain and
-- step, driving along ReplicatedStorage/CarPath segments), and (client mode)
-- the real BossClient drawing him with BossBodies/Revvington.lua on a
-- pretend player's screen. Pretend players circle him, roll now and then,
-- jump now and then, and punch him when he's in reach - using the box shape
-- his file gives CombatService - and rush in when he's stopped and open.
--   luau test_revvington.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both rounds)
--   attacks  every move forced in turn, in round 1 and TURBO, on a player
--            standing where the move reaches (each must land) - then again
--            on one who rolls through everything (dodged)
--   reset    the player leaves mid-fight (he stops, goes home and parks on the
--            start line), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll as the car or the slam
--            arrives dodges it, a roll far too early gets you hit
--   crash    a charge at a player by the tyre wall ends in a CRASH (he's
--            dizzy a long time), one in the open ends in a skid and a turn
-- It checks: no errors or warnings, no broken numbers, he never leaves the
-- track, his segments join up (no jumps), every move is seen (and drawn, in
-- client mode), TURBO comes at half health, he dies, and the reward (Power +
-- a floor-5 chest) is paid.
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
-- the world: the real Piston Speedway
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local CarPath = mount.require(mount.module("ReplicatedStorage/CarPath.lua"))
local arena = mount.require(mount.module("ServerScriptService/SpeedwayBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 5, "the speedway should be built as floor 5")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the speedway needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the speedway needs a way out (ArenaExit)")
local SPINE, EDGE = arena:GetAttribute("Spine"), arena:GetAttribute("Edge")
assert(SPINE == 70 and EDGE == 62, "the speedway's shape: a line 140 long, 62 out to the edge")
local CENTER = arena:GetAttribute("Center")
local function spineDist(p)
	local x = math.clamp(p.X - CENTER.X, -SPINE, SPINE)
	return Vector3.new(p.X - CENTER.X - x, 0, p.Z - CENTER.Z).Magnitude
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
	p:SetAttribute("SpireFloor", 5)
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
	table.insert(hitLog, { t = T, act = act, p = p })
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
function Combat.Launch() end
local rewards = { power = 0, chests = {}, kills = 0 }
local Profile = {}
function Profile.RecordBossKill(p, floorId)
	rewards.kills += 1
	return true
end
function Profile.AddPower(p, n)
	rewards.power += n
end
function Profile.AddChest(p, floorId, count)
	rewards.chests[floorId] = (rewards.chests[floorId] or 0) + count
end

for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 5 then
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
local E = assert(BS.Encounter(5), "Revvington should be built on floor 5")
model = E.model
local def = E.def
assert(def.Short == "Revvington", "floor 5's boss should be Revvington")
assert(shapes[model], "Revvington should give CombatService his body shape")
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
	cam.CFrame = CFrame.new(home + Vector3.new(0, 20, 60), home)
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
	-- (words on the screen, and words floating over him in the world: the hint)
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
-- punching him, the way CombatService does (with his box shape)
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
local function place(p, pos, dt)
	local root = rootOf(p)
	local old = lastPos[p] or pos
	root.CFrame = CFrame.new(pos)
	root.AssemblyLinearVelocity = dt > 0 and (pos - old) / dt or Vector3.new()
	lastPos[p] = pos
end
local function moveToward(from, to, speed, dt)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude <= speed * dt then
		return Vector3.new(to.X, from.Y, to.Z)
	end
	return from + d.Unit * speed * dt
end
-- keep on the track (the real invisible walls do)
local function onTrack(pos)
	local x = math.clamp(pos.X - CENTER.X, -SPINE, SPINE)
	local off = Vector3.new(pos.X - CENTER.X - x, 0, pos.Z - CENTER.Z)
	if off.Magnitude > EDGE - 1 then
		off = off.Unit * (EDGE - 1)
	end
	return Vector3.new(CENTER.X + x + off.X, pos.Y, CENTER.Z + off.Z)
end
local OPEN = { Cruise = false, Idle = true, Donuts = true }
-- A fighter: circles him at a distance that swells and shrinks, rolls every
-- few seconds and jumps every few more - and rushes to his side when he's
-- stopped (turning round after a charge, dizzy, showing off).
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local act = model:GetAttribute("Action")
	local segK = model:GetAttribute("SegK")
	local stopped = segK == "Spin"
	local want
	if style ~= "far" and stopped and (OPEN[act] or act == "Charge" or act == "WheelieSlam" or act == "Backfire") then
		-- to his side (where he has only the side bump), and hit him
		local look = model:GetPivot().LookVector
		local right = Vector3.new(look.Z, 0, -look.X)
		local s = ((base - center):Dot(right) >= 0) and 1 or -1
		want = center + right * s * 8
	end
	if not want then
		local r = (style == "far") and (38 + 10 * math.sin(phaseT * 0.4)) or (10 + 20 * (1 + math.sin(phaseT * 0.31)))
		local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
		local ang = phaseT * 0.6 * spin + k * 2
		want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 20
	local nextPos = onTrack(moveToward(base, want, speed, dt))
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
local maxOut = 0
local sawPhase2, crashes = false, 0
local lastSegId, lastSegEnd = nil, nil
local jumps = 0
local maxSpeed = 0
local lastP = nil
local skipSpeed = false -- (a test just put him somewhere: that's not him driving)
local function watch(dt)
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
		table.insert(order, act)
	end
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	maxOut = math.max(maxOut, spineDist(pos))
	local st = model:GetAttribute("State")
	if skipSpeed then
		skipSpeed = false
	elseif lastP and dt > 0 and st ~= "Resetting" and st ~= "Dormant" and st ~= "Dead" then
		local v = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(lastP.X, 0, lastP.Z)).Magnitude / dt
		maxSpeed = math.max(maxSpeed, v)
		if v > 130 then
			problem(string.format("he moved %.0f studs/s at %.2f (a jump?)", v, T))
		end
	end
	lastP = pos
	-- a new segment must start where he is (he never jumps)
	local id = model:GetAttribute("SegId")
	if id ~= lastSegId then
		lastSegId = id
		local seg = CarPath.read(model)
		if seg and lastSegEnd and model:GetAttribute("State") ~= "Resetting" and model:GetAttribute("State") ~= "Dormant" then
			local startP = CarPath.eval(seg, seg.t0)
			local gap = (Vector3.new(startP.X, 0, startP.Z) - Vector3.new(lastSegEnd.X, 0, lastSegEnd.Z)).Magnitude
			if gap > 3 then
				jumps += 1
				if jumps <= 3 then
					problem(string.format("his new segment (%s, %s) starts %.1f away from where he was at %.2f", seg.kind, tostring(act), gap, T))
				end
			end
		end
	end
	local seg = CarPath.read(model)
	if seg then
		lastSegEnd = CarPath.eval(seg, M.now())
	end
	if act == "Charge" and model:GetAttribute("Act4") == nil and model:GetAttribute("ActC") ~= nil then
		crashes = math.max(crashes, 1)
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
		if args[4] == "debug" and step % 90 == 0 then
			print(string.format("  t=%6.1f phase=%d hp=%.2f act=%s seg=%s", T, E.phase,
				(model:GetAttribute("Health") or 0) / math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")), tostring(model:GetAttribute("SegK"))))
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
-- stops his brain (a new token), puts him at `pos` facing `dir`, parked
local function takeOver(pos, dir)
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.contact, E.wheelie = nil, false
	if pos then
		E.pos, E.facing = Vector3.new(pos.X, floorY, pos.Z), dir
		E.seg = { kind = "Spin", t0 = M.now(), dur = 0.05, a = E.pos, b = Vector3.new(CarPath.angleOf(dir), 0, 0), c = Vector3.new(), ease = "lin" }
		CarPath.write(model, E.seg, (model:GetAttribute("SegId") or 0) + 1)
		E.segId = model:GetAttribute("SegId")
		lastSegEnd = E.pos
		skipSpeed = true
	end
	return E.token
end
local function mark()
	return #hitLog, dodges
end
local function since(m0)
	return #hitLog - m0
end

-- where each move is forced from: him on the infield facing east, the player
-- `spot` studs away (x ahead, z to his side)
local EAST = Vector3.new(1, 0, 0)
local START = CENTER + Vector3.new(-40, 0, 0)
local SPOTS = {
	Charge = Vector3.new(40, 0, 0),
	TailWhip = Vector3.new(34, 0, 0),
	WheelieSlam = Vector3.new(11, 0, 0),
	Honk = Vector3.new(13, 0, 0),
	Backfire = Vector3.new(-12, 0, 0),
	SideBump = Vector3.new(0, 0, 7),
	Donuts = Vector3.new(40, 0, 0),
	BurnoutRing = Vector3.new(34, 0, 0),
}

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, parked")
elseif SCENARIO == "duo" then
	local a = people[1] or makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1003)
	walkIn(a)
	walkIn(b)
	fightUntil({ a, b }, function()
		return stateIs("Dead")
	end, 900)
	runFor(4)
elseif SCENARIO == "reset" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.8
	end, 300)
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	local pos = model:GetPivot().Position
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back on the start line after a reset")
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
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
		local token = takeOver(START, EAST)
		E.target, E.targetSince = p, M.now()
		local o = SPOTS[name]
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0, d0 = mark()
		M.task.spawn(function()
			local ok, err = pcall(Boss.Attacks[name], E, token)
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		if dodge then
			rollUntil[p] = T + 11
		end
		runFor(10)
		rollUntil[p] = nil
		return since(m0), dodges - d0
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			fightUntil({ p }, function()
				return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
			end, 500)
			assert(E.phase == 2, "TURBO should come at half health")
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if (a.Phase or 1) <= phase then
				local landedN = force(name, false)
				local _, dodged = force(name, true)
				table.insert(report, string.format("p%d %s hit=%d dodged=%d", phase, name, landedN, dodged))
				if name ~= "Donuts" and landedN == 0 then
					problem(name .. " (round " .. phase .. ") never hit a player standing where it reaches")
				end
				if name == "Donuts" and landedN > 0 then
					problem("showing off shouldn't hurt anyone")
				end
				if name ~= "Donuts" and dodged == 0 then
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
	-- force `move`, the player standing at `o` from him; roll at (its hit -
	-- `before`) seconds; did it land?
	local function case(move, o, hitAfter, before, wantDodge, label)
		local token = takeOver(START, EAST)
		E.target, E.targetSince = p, M.now()
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0, d0 = mark()
		local t0 = M.now()
		M.task.spawn(function()
			Boss.Attacks[move](E, token)
		end)
		local rollAt = t0 + hitAfter - before
		local rolled = false
		local stop = T + hitAfter + 0.3
		while T < stop do
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
		if args[4] == "debug" then
			for i = m0 + 1, #hitLog do
				print(string.format("   hit at +%.3f by %s", hitLog[i].t - (T - (M.now() - t0)), hitLog[i].act))
			end
		end
		if wantDodge and landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver()
		runFor(4)
	end
	local c = def.Attacks.Charge
	-- (the car reaches a player 40 ahead after (40 - half his length - you) / speed)
	local arrive = c.Tell[1] + (40 - def.Car.Length / 2 - 1.5) / c.Speed[1]
	case("Charge", SPOTS.Charge, arrive, 0.15, true, "charge late")
	case("Charge", SPOTS.Charge, arrive, 1.0, false, "charge early")
	local w = def.Attacks.WheelieSlam
	case("WheelieSlam", SPOTS.WheelieSlam, w.Tell, 0.2, true, "wheelie late")
	case("WheelieSlam", SPOTS.WheelieSlam, w.Tell, 0.8, false, "wheelie early")
	local h = def.Attacks.Honk
	case("Honk", SPOTS.Honk, h.Tell, 0.2, true, "honk late")
	case("Honk", SPOTS.Honk, h.Tell, 0.75, false, "honk early")
	local b = def.Attacks.Backfire
	case("Backfire", SPOTS.Backfire, b.Tell, 0.2, true, "backfire late")
	case("Backfire", SPOTS.Backfire, b.Tell, 0.85, false, "backfire early")
elseif SCENARIO == "crash" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	-- 1) the player by the tyre wall (south straight), him on the infield facing them
	local token = takeOver(CENTER + Vector3.new(0, 0, -10), Vector3.new(0, 0, 1))
	E.target, E.targetSince = p, M.now()
	place(p, CENTER + Vector3.new(0, 3, EDGE - 3), 0)
	M.task.spawn(function()
		Boss.Attacks.Charge(E, token)
	end)
	local sawCrash = false
	local crashAt = nil
	for _ = 1, 150 do
		tick(1)
		if model:GetAttribute("ActC") and not sawCrash then
			sawCrash = true
		end
		if sawCrash and not crashAt and model:GetAttribute("SegK") == "Spin" and model:GetAttribute("SegDur") and model:GetAttribute("SegDur") > 1.5 then
			crashAt = T
		end
	end
	print("charge at a player by the wall: crash marked " .. tostring(sawCrash) .. ", dizzy " .. tostring(crashAt ~= nil))
	if not sawCrash then
		problem("a charge into the tyre wall should be marked a crash (slot 3)")
	end
	if not crashAt then
		problem("after a crash he should stand dizzy a long while")
	end
	runFor(4)
	-- 2) the player in the open: no crash
	token = takeOver(START, EAST)
	E.target, E.targetSince = p, M.now()
	place(p, START + Vector3.new(30, 3, 0), 0)
	M.task.spawn(function()
		Boss.Attacks.Charge(E, token)
	end)
	local crashedOpen = false
	for _ = 1, 150 do
		tick(1)
		if model:GetAttribute("ActC") then
			crashedOpen = true
		end
	end
	print("charge in the open: crash marked " .. tostring(crashedOpen))
	if crashedOpen then
		problem("a charge in the open shouldn't crash")
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
print(string.format("time %.1f  state %s  phase %s  punches %d  hits on players: %s  dodged %d  shoves %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, table.concat(hitList, " "), dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("furthest out from the track's middle line %.1f (leash %d, edge %d)  fastest %.0f studs/s  reward power %d chests %s victories %d",
	maxOut, def.Leash, EDGE, maxSpeed, rewards.power, tostring(rewards.chests[5]), victories))
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
	-- everything that should have been drawn, was
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
	-- (his body, every time)
	needDrawn({ "Tub", "Cabin", "Roof", "Hood", "Bumper", "Windscreen", "EyeWhite", "Iris", "Pupil", "Lid", "Mouth", "Teeth",
		"Tyre", "Rim", "Hub", "Headlight", "TailLight", "Pipe", "Spoiler", "Bolt", "Roundel", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "LaneWarning", "LaneArrow", "WedgeWarning", "CircleWarning", "FirePuddle", "RingPiece", "HonkWave", "SkidMark",
			"SpeedLine", "Flame", "Cheek" })
		needWords({ "HONK!!", "BANG!", "BONK!", "WOO-HOO!", "RING OF FIRE!", "TURBO!", "TIME " })
	elseif SCENARIO == "full" then
		needWords({ "READY TO LOSE?", "GO!", "KA-VROOM!", "FINISH!", "YOUR TIME ", "TIME " })
	elseif SCENARIO == "crash" then
		needDrawn({ "LooseTyre", "DizzyStar" })
		needWords({ "CRASH!", "DIZZY! HIT HIM!" })
	end
end
if maxOut > def.Leash + 0.5 then
	problem(string.format("he went %.1f out from the track's middle line (leash %d)", maxOut, def.Leash))
end
if SCENARIO == "full" or SCENARIO == "duo" or SCENARIO == "reset" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("he should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 or (rewards.chests[5] or 0) < 1 then
		problem("beating him should pay Power and a floor-5 chest")
	end
	if not sawPhase2 then
		problem("TURBO never came")
	end
	for _, name in ipairs({ "Wake", "Break", "Death", "Charge", "Cruise" }) do
		if not seen[name] then
			problem("never saw " .. name)
		end
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
