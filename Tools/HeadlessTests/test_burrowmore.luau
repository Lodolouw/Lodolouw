--!nocheck
-- KNIGHT BURROWMORE (floor 3) in the pretend Roblox: the real DigBuilder arena,
-- the real BossService with Bosses/Burrowmore.lua, and (client mode) the real
-- BossClient drawing him with BossBodies/Burrowmore.lua on a pretend player's
-- screen. Pretend players walk round him, roll now and then, jump now and then
-- and punch him whenever he's in reach - using the body shape his file gives
-- CombatService, so a punch at him high in the air misses, as in the game.
--   luau test_burrowmore.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both phases, the meteor)
--   attacks  every move forced in turn, in phase one and phase two, on a
--            player who stands still (so each one's hit is seen to land) -
--            then again on one who rolls at the right moment (dodged)
--   reset    the player leaves mid-fight (he resets, kneels at home), then
--            comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll at the right moment (as the
--            circle locks, as he starts to fall, as the swing comes round)
--            dodges it; a roll too early gets you hit
-- It checks: no errors or warnings, no broken numbers, he never leaves the
-- dirt, every move is seen (and draws its warnings, in client mode), the
-- armour breaks at half health, the meteor comes below 30%, he dies, the
-- reward (Power + a floor-3 chest) is paid, and he's never hit while high up.
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
-- the world: the real Glimmer Dig
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local arena = mount.require(mount.module("ServerScriptService/DigBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 3, "the dig should be built as floor 3")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the dig needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the dig needs a way out (ArenaExit)")

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
	p:SetAttribute("SpireFloor", 3)
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
local lastHitBy = nil
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
	if Combat.IsInvulnerable(p) then
		dodges += 1
		return false
	end
	local act = model and model:GetAttribute("Action") or "?"
	hitsOn[act] = (hitsOn[act] or 0) + 1
	lastHitBy = act
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
local E = assert(BS.Encounter(3), "Burrowmore should be built on floor 3")
model = E.model
local def = E.def
assert(def.Short == "Burrowmore", "floor 3's boss should be Burrowmore")
assert(shapes[model], "Burrowmore should give CombatService his body shape")
local Boss = E.boss
local home, floorY = E.home, E.floorY

----------------------------------------------------------------------
-- client mode: his body on the first player's screen
----------------------------------------------------------------------
local drawn = {} -- names of things drawn, ever
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
	if not fx then
		return
	end
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

----------------------------------------------------------------------
-- punching him, the way CombatService does (with his body shape)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded, highPunches = 0, 0
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
	-- (would it have landed on him high in the air? It mustn't: up there he's out of reach)
	if E.arc and Boss.jumpHeight(M.now() - E.arc.t0, E.arc.air, E.arc.rise, E.arc.height, E.arc.hang) > 15 then
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
-- keep inside the dig's wall (84 out), like the real invisible wall does
local function inDig(pos)
	local off = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	if off.Magnitude > 83 then
		off = off.Unit * 83
	end
	return Vector3.new(home.X + off.X, pos.Y, home.Z + off.Z)
end

-- A fighter: circles him at a distance that swells and shrinks (in close to
-- punch, out to where he throws things), changes direction now and then,
-- rolls every few seconds and jumps every few more.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local r = (style == "far") and (40 + 10 * math.sin(phaseT * 0.4)) or (6 + 22 * (1 + math.sin(phaseT * 0.31)))
	local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
	local ang = phaseT * 0.6 * spin + k * 2
	local want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 16
	local nextPos = inDig(moveToward(base, want, speed, dt))
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
local seen = {}
local order = {}
local maxFromHome = 0
local sawPhase2, sawMeteorBelow = false, false
local slotsSeen = {}
local rainSeen = 0
local function watch()
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
		table.insert(order, act)
	end
	if act == "ShovelMeteor" and E.phase >= 2 then
		sawMeteorBelow = true
	end
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local k = model:GetAttribute("ActK") or 0
	if act then
		slotsSeen[act] = math.max(slotsSeen[act] or 0, k)
	end
	rainSeen = math.max(rainSeen, model:GetAttribute("RainK") or 0)
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	local d = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude
	maxFromHome = math.max(maxFromHome, d)
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

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, kneeling")
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
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back at home after a reset")
	assert(model:GetAttribute("RainK") == nil, "a reset clears any gem rain")
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
	local function force(name, fn, dodge)
		-- (never in the middle of the armour breaking: that has its own timing)
		local waited = 0
		while not stateIs("Fighting") and waited < 10 do
			runFor(0.5)
			waited += 0.5
		end
		E.token += 1
		local token = E.token
		E.target, E.targetSince = p, M.now()
		E.motion, E.sweep, E.arc = nil, nil, nil
		local before = 0
		for _, v in pairs(hitsOn) do
			before += v
		end
		local dodgesBefore = dodges
		-- stand 18 studs in front of him (in reach of everything but the swing)
		local stand = name == "ShovelSwing" or name == "SwingDrop"
		local dist = stand and 7 or 22
		local spot = Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * dist
		if name == "ShovelMeteor" then
			spot = home + Vector3.new(10, 3, 0) -- (it lands in the middle of the dig)
		end
		spot = inDig(spot)
		place(p, spot, 0)
		M.task.spawn(function()
			local ok, err = pcall(fn, E, token)
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		-- a player who rolls through everything: always untouchable
		if dodge then
			rollUntil[p] = T + 9
		end
		runFor(8) -- (standing still, not punching: the break comes only when the test asks)
		rollUntil[p] = nil
		local after = 0
		for _, v in pairs(hitsOn) do
			after += v
		end
		return after - before, dodges - dodgesBefore
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			fightUntil({ p }, function()
				return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
			end, 400)
			assert(E.phase == 2, "the armour should break at half health")
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if a.Phase <= phase then
				local fn = Boss.Attacks[name]
				if name == "ShovelMeteor" then
					fn = Boss._Meteor
				end
				local landed = force(name, fn, false)
				local _, dodged = force(name, fn, true)
				table.insert(report, string.format("p%d %s hit=%d dodged=%d", phase, name, landed, dodged))
				if name ~= "Taunt" and landed == 0 then
					problem(name .. " (phase " .. phase .. ") never hit a player standing still in front of him")
				end
				if name == "Taunt" and landed > 0 then
					problem("the taunt shouldn't hurt anyone")
				end
				if name ~= "Taunt" and dodged == 0 then
					problem(name .. " (phase " .. phase .. ") couldn't be rolled through")
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
	end, 60)
	-- one case: force `move`, stand still `dist` in front of him, and roll at
	-- (its landing - `before`) seconds; did it land?
	local function case(move, dist, landingAfter, before, wantDodge, label)
		local waited = 0
		while not stateIs("Fighting") and waited < 10 do
			runFor(0.5)
			waited += 0.5
		end
		E.token += 1
		local token = E.token
		E.target, E.targetSince = p, M.now()
		E.motion, E.sweep, E.arc = nil, nil, nil
		place(p, inDig(Vector3.new(E.pos.X, floorY + 3, E.pos.Z) + E.facing * dist), 0)
		local hitsBefore = 0
		for _, v in pairs(hitsOn) do
			hitsBefore += v
		end
		local dodgesBefore = dodges
		local t0 = M.now()
		M.task.spawn(function()
			Boss.Attacks[move](E, token)
		end)
		local rollAt = t0 + landingAfter - before
		local rolled = false
		local stop = T + landingAfter + 1.5
		while T < stop do
			tick(1)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5 -- (a roll: untouchable for half a second)
			end
		end
		rollUntil[p] = nil
		local hitsAfter = 0
		for _, v in pairs(hitsOn) do
			hitsAfter += v
		end
		local landed = hitsAfter > hitsBefore
		local dodged = dodges > dodgesBefore and not landed
		print(string.format("%-12s roll %.2fs before it lands: %s", label, before, landed and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landed then
			problem(label .. ": a roll " .. before .. "s before it lands should dodge it")
		elseif not wantDodge and not landed then
			problem(label .. ": a roll " .. before .. "s before it lands is too early - it should still hit")
		end
		runFor(3)
	end
	local d = def.Attacks.ShovelDrop
	local dLand = d.Tell + d.Air
	local dLock = d.Tell + d.Air * d.Lock
	case("ShovelDrop", 16, dLand, dLand - dLock, true, "drop @lock")
	case("ShovelDrop", 16, dLand, 0.15, true, "drop late")
	case("ShovelDrop", 16, dLand, 0.95, false, "drop early")
	local sw = def.Attacks.ShovelSwing
	case("ShovelSwing", 7, sw.Tell, sw.Tell * (1 - sw.Commit), true, "swing @lock")
	case("ShovelSwing", 7, sw.Tell, 0.62, false, "swing early")
	-- the delayed drop is phase two's: break the armour first
	fightUntil({ p }, function()
		return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
	end, 400)
	local dd = def.Attacks.DelayedDrop
	local ddTotal = dd.Air + dd.Hang
	local ddLand = dd.Tell + ddTotal
	local ddFall = dd.Tell + dd.Air * dd.Rise + dd.Hang
	case("DelayedDrop", 16, ddLand, ddLand - (dd.Tell + ddTotal * dd.Lock), false, "delayed @lock")
	case("DelayedDrop", 16, ddLand, ddLand - ddFall, true, "delayed @fall")
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
print(string.format("furthest from the middle %.1f (leash %d)  gems %d  reward power %d chests %s victories %d",
	maxFromHome, def.Leash, rainSeen, rewards.power, tostring(rewards.chests[3]), victories))
if MODE == "client" then
	local names = {}
	for k in pairs(drawn) do
		table.insert(names, k)
	end
	table.sort(names)
	print("drawn: " .. table.concat(names, " "))
	print("most parts at once: " .. maxParts)
end
if maxFromHome > def.Leash + 0.5 then
	problem(string.format("he went %.1f from the middle (leash %d)", maxFromHome, def.Leash))
end
if highPunches > 0 then
	problem(highPunches .. " punches landed on him while he was high in the air")
end
if SCENARIO ~= "attacks" and SCENARIO ~= "timing" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("he should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 or (rewards.chests[3] or 0) < 1 then
		problem("beating him should pay Power and a floor-3 chest")
	end
	if not sawPhase2 then
		problem("his armour never broke")
	end
	if not sawMeteorBelow then
		problem("the Shovel Meteor never came")
	end
	for _, name in ipairs({ "Wake", "Break", "Death" }) do
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
