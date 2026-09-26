--!nocheck
-- KAZE (floor 4) in the pretend Roblox: the real DojoBuilder arena, the real
-- BossService with Bosses/Kaze.lua, and (client mode) the real BossClient
-- drawing him with BossBodies/Kaze.lua on a pretend player's screen. Pretend
-- players circle him, roll now and then, jump now and then, punch him when
-- he's in reach (with the body shape his file gives CombatService, so a punch
-- at him high in a Rising Dragon misses, as in the game) - and swing at thin
-- air now and then, which feeds his ki meter (CombatService.OnWhiff).
--   luau test_kaze.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both rounds)
--   attacks  every move forced in turn, in round 1 and round 2, on a player
--            who stands still (each one's hit is seen to land) - then again
--            on one who rolls through everything (dodged)
--   reset    the player leaves mid-fight (he resets: meditating at home, his
--            meter empty, the pillars whole), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll as each warning locks dodges
--            it, a roll far too early gets you hit
--   rules    the ki rules: a missed punch near him feeds his meter (far away
--            it doesn't); punches while he meditates knock it down and two
--            break it (he staggers); a charge breaks the same way; out of
--            cancels he's tired, then they refill
--   super    the beam: a player hidden behind a pillar isn't hit, one in the
--            open is; the pillars in the fan crumble; round 2 mends them
-- It checks: no errors or warnings, no broken numbers, he never leaves his
-- ground, every move is seen (and draws its warnings, in client mode), round
-- 2 comes at half health, he Supers, gets tired and cancels, he dies, the
-- reward (Power + a floor-4 chest) is paid, and he's never hit while high up.
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
-- the world: the real Rooftop Dojo
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local arena = mount.require(mount.module("ServerScriptService/DojoBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 4, "the dojo should be built as floor 4")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the dojo needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the dojo needs a way out (ArenaExit)")
assert(#CollectionService:GetTagged("DojoPillar") == 4, "the dojo should have four pillars")
local HALF = arena:GetAttribute("Half")
assert(HALF == 62, "the dojo's walls should stand 62 out")

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
	p:SetAttribute("SpireFloor", 4)
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
local hitLog = {} -- { t, action, player }
local whiffListeners = {}
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
	if amount ~= amount or amount <= 0 then
		problem("a hit with a broken amount: " .. tostring(amount))
	end
	if Combat.IsInvulnerable(p) then
		dodges += 1
		return false
	end
	local act = model and model:GetAttribute("Action") or "?"
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
function Combat.OnWhiff(fn)
	table.insert(whiffListeners, fn)
end
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

-- (only Kaze's home: one boss per run)
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 4 then
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
local E = assert(BS.Encounter(4), "Kaze should be built on floor 4")
model = E.model
local def = E.def
assert(def.Short == "Kaze", "floor 4's boss should be Kaze")
assert(shapes[model], "Kaze should give CombatService his body shape")
assert(#whiffListeners == 1, "Kaze should listen for missed punches (CombatService.OnWhiff)")
assert(#E.pillars == 4, "Kaze should know the four pillars")
local Boss = E.boss
local home, floorY = E.home, E.floorY
local KIMAX = def.Ki.Bar * def.Ki.Bars

----------------------------------------------------------------------
-- client mode: his body on the first player's screen
----------------------------------------------------------------------
local drawn = {} -- names of things drawn, ever
local guis = {} -- names of screen things made, ever
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
				local cf = pr.CFrame
				if cf and M.isNaNv and M.isNaNv(cf.Position) then
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
	if pg then
		for _, d in ipairs(pg:GetDescendants()) do
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
-- punching him, the way CombatService does (with his body shape)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded, highPunches, whiffs = 0, 0, 0
local function punch(p, share, allowWhiff)
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
	local flatGap = (Vector3.new(point.X, 0, point.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	local gap = flatGap - radius
	if gap > PUNCH_RANGE or math.abs(point.Y - root.Position.Y) >= 12 then
		-- a swing at thin air, now and then, when he's near-ish (a wild player)
		if allowWhiff and flatGap < 20 and (math.floor(T * 7 + SEED) % 5 == 0) then
			lastPunch[p] = T
			whiffs += 1
			for _, fn in ipairs(whiffListeners) do
				fn(p, root.Position)
			end
		end
		return
	end
	lastPunch[p] = T
	-- (the most a jumping player can reach: his middle 15.2 up, so anything
	-- higher than that must have missed)
	if E.arc and Boss.jumpHeight(M.now() - E.arc.t0, E.arc.air, E.arc.rise, E.arc.height, E.arc.hang) > 15.5 then
		highPunches += 1
	end
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
-- keep inside the dojo's walls, and out of the pillars (they're solid)
local function inDojo(pos)
	local x = math.clamp(pos.X - home.X, -(HALF - 1), HALF - 1)
	local z = math.clamp(pos.Z - home.Z, -(HALF - 1), HALF - 1)
	local p = Vector3.new(home.X + x, pos.Y, home.Z + z)
	for _, pl in ipairs(E.pillars) do
		if not pl.broken then
			local off = Vector3.new(p.X - pl.center.X, 0, p.Z - pl.center.Z)
			local need = pl.radius + 1.6
			if off.Magnitude < need then
				local out = off.Magnitude > 0.01 and off.Unit or Vector3.new(1, 0, 0)
				p = Vector3.new(pl.center.X + out.X * need, p.Y, pl.center.Z + out.Z * need)
			end
		end
	end
	return p
end
-- the spot behind the pillar nearest `from` (as seen from the middle)
local function behindPillar(from)
	local best, bestD = nil, math.huge
	for _, pl in ipairs(E.pillars) do
		if not pl.broken then
			local d = (Vector3.new(pl.center.X - from.X, 0, pl.center.Z - from.Z)).Magnitude
			if d < bestD then
				best, bestD = pl, d
			end
		end
	end
	if not best then
		return nil
	end
	local out = Vector3.new(best.center.X - home.X, 0, best.center.Z - home.Z).Unit
	return best.center + out * (best.radius + 2.2)
end

-- A fighter: circles him at a distance that swells and shrinks, rolls every
-- few seconds and jumps every few more - and plays him a little: rushes in
-- when he meditates, charges or pants, backs off from a Rising Dragon, and
-- runs behind a pillar when he goes for his Super.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local act = model:GetAttribute("Action")
	local want
	if act == "Super" and (math.floor(T / 11 + SEED) % 3 ~= 0) then
		want = behindPillar(base)
	elseif style ~= "far" and (act == "KiFocus" or act == "Tired" or act == "Stagger" or (act == "KazeBlast" and (model:GetAttribute("ActN") or 0) > 0)) then
		local toMe = Vector3.new(base.X - center.X, 0, base.Z - center.Z)
		want = center + (toMe.Magnitude > 0.1 and toMe.Unit or Vector3.new(0, 0, 1)) * 8
	end
	if not want then
		local r = (style == "far") and (36 + 10 * math.sin(phaseT * 0.4)) or (7 + 20 * (1 + math.sin(phaseT * 0.31)))
		local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
		local ang = phaseT * 0.6 * spin + k * 2
		want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 16
	local nextPos = inDojo(moveToward(base, want, speed, dt))
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
local maxFromHome = 0
local sawPhase2 = false
local cancelKinds = {}
local lastCancelAt = nil
local charged = {}
local kiMaxSeen, kiMinSeen = 0, 1e9
local superPhase = {}
local function watch()
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
		table.insert(order, act)
	end
	if act == "Super" then
		superPhase[E.phase] = true
	end
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local ca = model:GetAttribute("CancelAt")
	if ca and ca ~= lastCancelAt then
		lastCancelAt = ca
		local kind = model:GetAttribute("CancelKind") or "?"
		cancelKinds[kind] = (cancelKinds[kind] or 0) + 1
	end
	if (act == "KazeBlast" or act == "RisingDragon" or act == "TornadoKick") and (model:GetAttribute("ActN") or 0) > 0 then
		charged[act] = true
	end
	local ki = model:GetAttribute("Ki")
	if ki then
		if ki ~= ki or ki < 0 or ki > KIMAX then
			problem("his ki meter is broken: " .. tostring(ki))
		end
		kiMaxSeen = math.max(kiMaxSeen, ki)
		kiMinSeen = math.min(kiMinSeen, ki)
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	local d = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude
	maxFromHome = math.max(maxFromHome, d)
	-- he never stands inside a standing pillar
	for _, pl in ipairs(E.pillars) do
		if not pl.broken and not E.motion then
			local g = Vector3.new(pos.X - pl.center.X, 0, pos.Z - pl.center.Z).Magnitude
			if g < pl.radius + def.Size / 2 * 0.8 - 0.6 then
				problem(string.format("he stood inside pillar %d at %.2f (%.1f from its middle)", pl.index, T, g))
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
		watch()
		if args[4] == "debug" and step % 90 == 0 then
			print(string.format("  t=%6.1f ki=%3d cancels=%s phase=%d hp=%.2f act=%s", T, model:GetAttribute("Ki") or -1, tostring(model:GetAttribute("Cancels")),
				E.phase, (model:GetAttribute("Health") or 0) / math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action"))))
		end
	end
end
local function runFor(seconds, each)
	tick(math.floor(seconds / DT + 0.5), each)
end
local function stateIs(s)
	return model:GetAttribute("State") == s
end
local share = 1 / 110 -- each punch takes this much of his health
local function fightStepFor(list, standStill)
	return function(dt)
		for k, p in ipairs(list) do
			if inArena[p] and humOf(p).Health > 0 then
				if not standStill then
					fighterStep(p, k, dt, k == 2 and "far" or "near")
				end
				punch(p, share, not standStill)
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
local function totalHits()
	local n = 0
	for _, v in pairs(hitsOn) do
		n += v
	end
	return n
end
-- stops his brain (a new token) and waits for him to be fighting
local function takeOver()
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.motion, E.sweep, E.arc = nil, nil, nil
	E.charging, E.focusing, E.guardBroken, E.chaining = false, false, false, false
	return E.token
end

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, meditating")
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
	-- (fight until a pillar has been smashed, or long enough)
	fightUntil({ p }, function()
		for _, pl in ipairs(E.pillars) do
			if pl.broken then
				return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.9
			end
		end
		return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.55
	end, 400)
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	local pos = model:GetPivot().Position
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back at home after a reset")
	assert(model:GetAttribute("Ki") == 0, "a reset empties his meter")
	assert(model:GetAttribute("Cancels") == def.Cancels[1], "a reset gives him his round-1 cancels")
	for _, pl in ipairs(E.pillars) do
		assert(not pl.broken and pl.model:GetAttribute("Broken") == false, "a reset mends every pillar")
	end
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
elseif SCENARIO == "attacks" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local names = {}
	for n in pairs(def.Attacks) do
		names[#names + 1] = n
	end
	table.sort(names)
	local CLOSE = { PunchString = 7, RisingDragon = 6 }
	local function force(name, dodge)
		local token = takeOver()
		E.target, E.targetSince = p, M.now()
		E.ki = KIMAX -- (a full meter, so nothing is short of ki)
		local before = totalHits()
		local dodgesBefore = dodges
		local dist = CLOSE[name] or 22
		local spot = Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * dist
		if name == "Super" then
			spot = home + Vector3.new(0, 3, 30) -- (in the open: no pillar between it and the middle)
		end
		spot = inDojo(spot)
		place(p, spot, 0)
		M.task.spawn(function()
			local ok, err = pcall(Boss.Attacks[name], E, token, {})
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		if dodge then
			rollUntil[p] = T + 9
		end
		runFor(8)
		rollUntil[p] = nil
		return totalHits() - before, dodges - dodgesBefore
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			fightUntil({ p }, function()
				return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
			end, 400)
			assert(E.phase == 2, "round 2 should come at half health")
		end
		for _, name in ipairs(names) do
			local landedN = force(name, false)
			local _, dodged = force(name, true)
			table.insert(report, string.format("p%d %s hit=%d dodged=%d", phase, name, landedN, dodged))
			if name ~= "KiFocus" and landedN == 0 then
				problem(name .. " (round " .. phase .. ") never hit a player standing still in front of him")
			end
			if name == "KiFocus" and landedN > 0 then
				problem("meditating shouldn't hurt anyone")
			end
			if name ~= "KiFocus" and dodged == 0 then
				problem(name .. " (round " .. phase .. ") couldn't be rolled through")
			end
			mount.require(mount.module("ServerScriptService/Bosses/Kaze.lua")) -- (no-op: keeps the module warm)
		end
		-- (mend the pillars his Supers broke, for the next round's)
		for _, pl in ipairs(E.pillars) do
			pl.broken = false
		end
	end
	print(table.concat(report, "\n"))
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	-- one case: force `move` (with `opts`), stand still `dist` in front of him,
	-- roll at (its hit - `before`) seconds; did it land?
	local function case(move, opts, dist, hitAfter, before, wantDodge, label)
		local token = takeOver()
		E.target, E.targetSince = p, M.now()
		E.ki = KIMAX
		E.cancels = 0 -- (no cancels: the move is exactly itself)
		-- (he stands in the middle facing south, the player due south of him:
		-- no pillar or wall in the way)
		E.pos, E.facing = home, Vector3.new(0, 0, 1)
		place(p, home + Vector3.new(0, 3, dist), 0)
		local mark = #hitLog
		local dodgesBefore = dodges
		local t0 = M.now()
		M.task.spawn(function()
			Boss.Attacks[move](E, token, opts)
		end)
		local rollAt = t0 + hitAfter - before
		local rolled = false
		-- (only this one hit counts: not a string's later punches)
		local stop = T + hitAfter + 0.25
		while T < stop do
			tick(1)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5
			end
		end
		rollUntil[p] = nil
		local landedHit = #hitLog > mark
		local dodged = dodges > dodgesBefore and not landedHit
		if args[4] == "debug" then
			for i = mark + 1, #hitLog do
				print(string.format("   hit at +%.3f by %s (rolled at +%.3f)", hitLog[i].t - (t0 - M.now() + T), hitLog[i].act, rollAt - t0))
			end
		end
		print(string.format("%-16s roll %.2fs before it hits: %s", label, before, landedHit and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		E.cancels = def.Cancels[E.phase]
		runFor(3)
	end
	local ps = def.Attacks.PunchString
	case("PunchString", { noCancel = true }, 7, ps.Tells[1], 0.12, true, "jab @lock")
	case("PunchString", { noCancel = true }, 7, ps.Tells[1], 0.75, false, "jab early")
	local rd = def.Attacks.RisingDragon
	case("RisingDragon", {}, 6, rd.Tell, 0.1, true, "dragon late")
	case("RisingDragon", {}, 6, rd.Tell, 0.7, false, "dragon early")
	local tk = def.Attacks.TornadoKick
	local tkLock = tk.Tell * tk.Commit
	-- (the kick reaches a player 18 in front after (18 - his half and the kick's reach) / speed)
	local reach = (18 - tk.Radius - 1.5) / tk.Speed[1]
	-- (it spins toward you: roll as it arrives, like a charge - not when the lane locks)
	case("TornadoKick", {}, 18, tk.Tell + reach, 0.2, true, "tornado late")
	case("TornadoKick", {}, 18, tk.Tell + reach, 1.0, false, "tornado early")
	local _ = tkLock
	local kb = def.Attacks.KazeBlast
	local kbReach = (22 - def.Size / 2 - 1 - kb.Radius[1] - 1.5) / kb.Speed[1]
	case("KazeBlast", {}, 22, kb.Tell + kbReach, 0.15, true, "blast late")
	case("KazeBlast", {}, 22, kb.Tell + kbReach, 1.2, false, "blast early")
elseif SCENARIO == "rules" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	-- 1) a missed punch near him feeds his meter; one far away doesn't
	local token = takeOver()
	E.target = p
	E.ki = 0
	local t0 = M.now()
	local ok = false
	M.task.spawn(function()
		-- (he just stands in his stance meanwhile)
		M.task.wait(0)
	end)
	place(p, inDojo(Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * 12), 0)
	local before = E.ki
	for _, fn in ipairs(whiffListeners) do
		fn(p, rootOf(p).Position)
	end
	local near = E.ki - before
	place(p, inDojo(Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * 40), 0)
	before = E.ki
	for _, fn in ipairs(whiffListeners) do
		fn(p, rootOf(p).Position)
	end
	local far = E.ki - before
	print(string.format("a miss 12 away gave %.1f ki, a miss 40 away gave %.1f", near, far))
	if math.abs(near - def.Ki.Whiff) > 0.01 then
		problem("a missed punch near him should give him " .. def.Ki.Whiff .. " ki (gave " .. near .. ")")
	end
	if far ~= 0 then
		problem("a missed punch far from him shouldn't feed his meter")
	end
	-- 2) punching him while he meditates: each punch knocks ki off, two break it
	token = takeOver()
	E.target = p
	E.ki = 100
	place(p, inDojo(Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * 8), 0)
	M.task.spawn(function()
		Boss.Attacks.KiFocus(E, token)
	end)
	runFor(0.3)
	local kiBefore = E.ki
	lastPunch[p] = -99
	punch(p, share)
	runFor(0.1)
	local afterOne = E.ki
	lastPunch[p] = -99
	punch(p, share)
	runFor(0.2)
	print(string.format("focus: %.1f ki, one punch -> %.1f, two punches -> action %s", kiBefore, afterOne, tostring(model:GetAttribute("Action"))))
	if afterOne > kiBefore - def.Ki.FocusHit + 12 then
		problem("a punch while he meditates should knock about " .. def.Ki.FocusHit .. " off his meter")
	end
	if model:GetAttribute("Action") ~= "Stagger" then
		problem("two punches while he meditates should break it (he staggers)")
	end
	runFor(2)
	-- 3) the same for a charge
	token = takeOver()
	E.target = p
	E.ki = KIMAX
	place(p, inDojo(Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * 8), 0)
	M.task.spawn(function()
		Boss.Attacks.KazeBlast(E, token, { hold = 1.0 })
	end)
	runFor(0.2)
	lastPunch[p] = -99
	punch(p, share)
	runFor(0.1)
	lastPunch[p] = -99
	punch(p, share)
	runFor(0.2)
	print("charge punched twice -> action " .. tostring(model:GetAttribute("Action")))
	if model:GetAttribute("Action") ~= "Stagger" then
		problem("two punches while he charges should break the charge (he staggers)")
	end
	runFor(2)
	-- 4) out of cancels -> tired, then they refill
	token = takeOver()
	E.target = p
	E.cancels = 0
	model:SetAttribute("Cancels", 0)
	M.task.spawn(function()
		Boss._tired(E, token)
	end)
	runFor(0.2)
	local actT = model:GetAttribute("Action")
	runFor(def.Tired[E.phase] + 0.3)
	print("out of cancels -> " .. tostring(actT) .. ", then cancels " .. tostring(model:GetAttribute("Cancels")))
	if actT ~= "Tired" then
		problem("out of cancels he should be tired")
	end
	if model:GetAttribute("Cancels") ~= def.Cancels[E.phase] then
		problem("after being tired his cancels should refill")
	end
	-- 5) the whole meter: the real brain should Super when it's full
	E.token += 1
	local brainToken = E.token
	E.ki = KIMAX
	E.lastSuper = nil
	M.task.spawn(function()
		Boss.brain(E, brainToken)
	end)
	local sawSuper = false
	fightUntil({ p }, function()
		sawSuper = sawSuper or model:GetAttribute("Action") == "Super"
		return sawSuper
	end, 6)
	if not sawSuper then
		problem("with a full meter he should go for his Super")
	end
	local _ = ok
	local _t = t0
elseif SCENARIO == "super" then
	local a = makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1002)
	walkIn(a)
	walkIn(b)
	fightUntil({ a, b }, function()
		return stateIs("Fighting")
	end, 60)
	local sa = def.Attacks.Super
	local function superCase(sign, label)
		local token = takeOver()
		E.target, E.targetSince = a, M.now()
		E.ki = KIMAX
		-- Alpha stands in the open due south; Bravo hides behind the south-east pillar
		place(a, home + Vector3.new(0, 3, 30), 0)
		local pl = E.pillars[4]
		local out = Vector3.new(pl.center.X - home.X, 0, pl.center.Z - home.Z).Unit
		place(b, pl.center + out * (pl.radius + 2.2) + Vector3.new(0, 3, 0), 0)
		local hitsA, hitsB = 0, 0
		local mark = #hitLog
		M.task.spawn(function()
			Boss.Attacks.Super(E, token)
		end)
		runFor(sa.Tell + sa.SweepTime + 1)
		for i = mark + 1, #hitLog do
			if hitLog[i].p == a then
				hitsA += 1
			elseif hitLog[i].p == b then
				hitsB += 1
			end
		end
		local broken = {}
		for _, q in ipairs(E.pillars) do
			table.insert(broken, q.broken and "X" or "|")
		end
		print(string.format("%s: in the open hit %d, behind a pillar hit %d, pillars %s", label, hitsA, hitsB, table.concat(broken)))
		if hitsA == 0 then
			problem(label .. ": the beam should hit a player in the open")
		end
		if hitsB > 0 then
			problem(label .. ": the beam shouldn't hit a player hidden behind a pillar")
		end
		if not E.pillars[4].broken then
			problem(label .. ": the pillar that took the beam should crumble")
		end
		if not E.pillars[4].model:GetAttribute("Broken") then
			problem(label .. ": the crumbled pillar should say so (Broken)")
		end
		runFor(sa.Recovery + 0.5)
	end
	superCase(1, "super 1")
	-- round 2 mends the pillars
	fightUntil({ a }, function()
		return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
	end, 400)
	for _, pl in ipairs(E.pillars) do
		if pl.broken or pl.model:GetAttribute("Broken") then
			problem("round 2 should mend the pillars")
		end
	end
	superCase(-1, "super 2")
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
local kinds = {}
for k, v in pairs(cancelKinds) do
	table.insert(kinds, k .. "=" .. v)
end
table.sort(kinds)
local chargedList = {}
for k in pairs(charged) do
	table.insert(chargedList, k)
end
table.sort(chargedList)
print(string.format("time %.1f  state %s  phase %s  punches %d  whiffs %d  hits on players: %s  dodged %d  shoves %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, whiffs, table.concat(hitList, " "), dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("cancels: %s  charged: %s  ki seen %d-%d  supers in round 1 %s, round 2 %s",
	table.concat(kinds, " "), table.concat(chargedList, " "), kiMinSeen, kiMaxSeen, tostring(superPhase[1] == true), tostring(superPhase[2] == true)))
print(string.format("furthest from the middle %.1f (leash %d)  reward power %d chests %s victories %d",
	maxFromHome, def.Leash, rewards.power, tostring(rewards.chests[4]), victories))
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
end
if maxFromHome > def.Leash + 0.5 then
	problem(string.format("he went %.1f from the middle (leash %d)", maxFromHome, def.Leash))
end
if highPunches > 0 then
	problem(highPunches .. " punches landed on him while he was high in the air")
end
if SCENARIO == "full" or SCENARIO == "duo" or SCENARIO == "reset" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("he should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 or (rewards.chests[4] or 0) < 1 then
		problem("beating him should pay Power and a floor-4 chest")
	end
	if not sawPhase2 then
		problem("round 2 never came")
	end
	for _, name in ipairs({ "Wake", "Break", "Death", "PunchString", "Tired" }) do
		if not seen[name] then
			problem("never saw " .. name)
		end
	end
	-- (which specials come depends on the fight: at least two of the three)
	local specials = (seen.KazeBlast and 1 or 0) + (seen.RisingDragon and 1 or 0) + (seen.TornadoKick and 1 or 0)
	if specials < 2 then
		problem("he only used " .. specials .. " of his three specials")
	end
	if not seen.Super then
		problem("he never did his Super")
	end
	if not next(cancelKinds) then
		problem("he never cancelled a move")
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
