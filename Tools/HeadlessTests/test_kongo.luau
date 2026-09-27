--!nocheck
-- KONGO (floor 7) in the pretend Roblox: the real JungleBuilder arena, the
-- real BossService with Bosses/Kongo.lua, and (client mode) the real
-- BossClient drawing him with BossBodies/Kongo.lua on a pretend player's
-- screen. Pretend players circle him, roll now and then, jump now and then
-- and punch him whenever he's in reach.
--   luau test_kongo.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both rounds)
--   attacks  every move forced in turn, in round one and round two, on a
--            player who stands still where it reaches (so each one's hit is
--            seen to land) - then again on one who rolls (dodged)
--   reset    the player leaves mid-fight (he resets and sits back down in the
--            middle), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll just before a hit dodges it,
--            a roll too early gets you hit
--   tired    a Giant Punch that misses leaves him tired - wide open - for his
--            Tired time (punches land), and one that hits doesn't
-- It checks: no errors or warnings, no broken numbers, he never leaves the
-- clearing, every move is seen (and draws its warnings, in client mode),
-- round 2 comes at half health, he dies, the reward (Power) is paid - and
-- floor 7 still has no loot (it's waiting for the loot rework).
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
-- the world: the real jungle village
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Items = mount.require(mount.module("ReplicatedStorage/Items.lua"))
local arena = mount.require(mount.module("ServerScriptService/JungleBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 7, "the jungle should be built as floor 7")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the jungle needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the jungle needs a way out (ArenaExit)")
local FIGHT_R = arena:GetAttribute("FightRadius")
local MONKEYS = #CollectionService:GetTagged("JungleMonkey")
local TORCHES = #CollectionService:GetTagged("JungleTorch")
assert(MONKEYS > 0, "the village should have monkey villagers")
assert(TORCHES > 0, "the clearing should have tiki torches")
-- (no loot yet: floor 7's chest is waiting for the loot rework)
assert(Items.ByFloor[7] == nil, "floor 7 shouldn't have any loot yet")

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
	p:SetAttribute("SpireFloor", 7)
end
local function leave(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
end

----------------------------------------------------------------------
-- CombatService and PlayerService, pretend
----------------------------------------------------------------------
local hitsOn, dodges, shoves = {}, 0, 0
local throws = 0
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
	if knockback and M.typeof(knockback) == "Vector3" and M.isNaNv and M.isNaNv(knockback) then
		problem("a hit had a broken knockback")
	end
	if Combat.IsInvulnerable(p) then
		dodges += 1
		return false
	end
	local act = model and model:GetAttribute("Action") or "?"
	hitsOn[act] = (hitsOn[act] or 0) + 1
	if act == "CargoThrow" and knockback and knockback.Y > 20 then
		throws += 1
	end
	local hum = humOf(p)
	if hum then
		hum.Health = math.max(1, hum.Health - amount)
	end
	return true
end
function Combat.Shove()
	shoves += 1
end
function Combat.SetTargetShape() end
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
local E = assert(BS.Encounter(7), "Kongo should be built on floor 7")
model = E.model
local def = E.def
assert(def.Short == "Kongo", "floor 7's boss should be Kongo")
local Boss = E.boss
local home, floorY = E.home, E.floorY

----------------------------------------------------------------------
-- client mode: his body on the first player's screen
----------------------------------------------------------------------
local drawn, guis = {}, {}
local maxParts = 0
local monkeyStart = {}
local monkeysMoved, torchesFlared = 0, 0
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
	for _, mk in ipairs(CollectionService:GetTagged("JungleMonkey")) do
		monkeyStart[mk] = mk.PrimaryPart.CFrame
	end
	math.randomseed(SEED)
	mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)
end
local torchSize = {}
for _, f in ipairs(CollectionService:GetTagged("JungleTorch")) do
	torchSize[f] = f.Size.Y
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
	-- (the villagers bouncing along; the torches flaring in round 2)
	for mk, cf in pairs(monkeyStart) do
		if mk.PrimaryPart and (mk.PrimaryPart.CFrame.Position - cf.Position).Magnitude > 0.05 then
			monkeysMoved += 1
			monkeyStart[mk] = nil
		end
	end
	for f, y in pairs(torchSize) do
		if f.Size.Y > y * 1.3 then
			torchesFlared += 1
			torchSize[f] = nil
		end
	end
	local me = Players.LocalPlayer
	local pg = me and me:FindFirstChild("PlayerGui")
	for _, holder in ipairs({ pg, fx }) do
		for _, d in ipairs(holder and holder:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Text ~= "" and d.Visible ~= false and (d.TextTransparency or 0) < 1 then
				local anc = d:FindFirstAncestorWhichIsA("ScreenGui") or d:FindFirstAncestorWhichIsA("BillboardGui")
				if anc and anc.Enabled ~= false then
					guis[d.Text] = true
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- punching him, the way CombatService does (from his middle: he's HitRadius wide)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded = 0
local function punch(p, share)
	if not CollectionService:HasTag(model, "CombatTarget") or (model:GetAttribute("Health") or 0) <= 0 then
		return false
	end
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return false
	end
	local root = rootOf(p)
	local c = model:GetPivot().Position
	local radius = model:GetAttribute("HitRadius") or def.Size / 2
	local gap = (Vector3.new(c.X, 0, c.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - radius
	if gap > PUNCH_RANGE then
		return false
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
	return damage > 0
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
-- keep inside the clearing's wall, like the real invisible wall does
local function inClearing(pos)
	local off = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	if off.Magnitude > FIGHT_R - 1 then
		off = off.Unit * (FIGHT_R - 1)
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
	local r = (style == "far") and (38 + 10 * math.sin(phaseT * 0.4)) or (6 + 20 * (1 + math.sin(phaseT * 0.31)))
	local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
	local ang = phaseT * 0.6 * spin + k * 2
	local want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 18
	local nextPos = inClearing(moveToward(base, want, speed, dt))
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
local sawPhase2 = false
local lastP = nil
local maxSpeed = 0
local function watch(dt)
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
	end
	if act and order[#order] ~= act and act ~= "Idle" then
		table.insert(order, act)
	end
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	local d = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude
	maxFromHome = math.max(maxFromHome, d)
	local st = model:GetAttribute("State")
	if lastP and dt and dt > 0 and st ~= "Dormant" and st ~= "Resetting" and st ~= "Dead" then
		local v = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(lastP.X, 0, lastP.Z)).Magnitude / dt
		maxSpeed = math.max(maxSpeed, v)
		if v > 90 then
			problem(string.format("he moved %.0f studs/s at %.2f (a jump?) doing %s", v, T, tostring(act)))
		end
	end
	lastP = pos
end

----------------------------------------------------------------------
-- running it
----------------------------------------------------------------------
local DT = 1 / 30
local step = 0
local skipSpeed = false
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
		watch(not skipSpeed and DT or nil)
		skipSpeed = false
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
local function hitCount()
	local n = 0
	for _, v in pairs(hitsOn) do
		n += v
	end
	return n
end
-- stops his brain (a new token) and puts him in the middle facing south,
-- standing still - so a forced move starts from a known place
local function takeOver(p)
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.motion, E.sweep, E.waves = nil, nil, {}
	E.pos = Vector3.new(home.X, floorY, home.Z)
	E.facing = Vector3.new(0, 0, 1)
	E.target, E.targetSince = p, M.now()
	skipSpeed = true
	return E.token
end

-- where each move is forced from: the player this far in front of him (south)
local SPOTS = {
	GiantPunch = 14, HandSlap = 10, Roll = 26, Spin = 6, Headbutt = 8, Barrel = 26, TNT = 26, Pound = 20,
	CargoThrow = 6, Combo = 10,
}
local HARMLESS = { Pound = true }

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, asleep in the middle")
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
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back in the middle after a reset")
	assert(#E.waves == 0, "a reset clears his shockwaves")
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
	local function force(name, dodge)
		local token = takeOver(p)
		local spot = Vector3.new(home.X, floorY + 3, home.Z + SPOTS[name])
		place(p, spot, 0)
		local before, dodgesBefore = hitCount(), dodges
		M.task.spawn(function()
			local ok, err = pcall(Boss.Attacks[name], E, token)
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		if dodge then
			rollUntil[p] = T + 11
		end
		runFor(10, function(dt)
			place(p, spot, dt) -- (standing still, not punching)
		end)
		rollUntil[p] = nil
		return hitCount() - before, dodges - dodgesBefore
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			-- his first half of health knocked off in one go: round 2 starts (the
			-- shared brain carries on from there, as in the game)
			takeOver(p)
			local max = model:GetAttribute("MaxHealth")
			model:SetAttribute("Health", math.floor(max * def.PhaseAt))
			model:FindFirstChild("OnHit"):Fire(p, 1, false)
			runFor(def.BreakTime + 1)
			assert(E.phase == 2 and stateIs("Fighting"), "round 2 should come at half health")
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if a.Phase == phase or (phase == 2 and (name == "GiantPunch" or name == "HandSlap" or name == "Barrel" or name == "TNT")) then
				local landed = force(name, false)
				local _, dodged = force(name, true)
				table.insert(report, string.format("round %d %s hit=%d dodged=%d", phase, name, landed, dodged))
				if not HARMLESS[name] and landed == 0 then
					problem(name .. " (round " .. phase .. ") never hit a player standing still where it reaches")
				end
				if HARMLESS[name] and landed > 0 then
					problem(name .. " shouldn't hurt anyone")
				end
				if not HARMLESS[name] and dodged == 0 then
					problem(name .. " (round " .. phase .. ") couldn't be rolled through")
				end
			end
		end
	end
	print(table.concat(report, "\n"))
	if throws == 0 then
		problem("the Cargo Throw should hurl whoever it grabs (up and away)")
	end
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	-- one case: force `move`, stand still `dist` in front of him, and roll at
	-- (its hit - `before`) seconds; did it land?
	local function case(move, dist, hitAfter, before, wantDodge, label, wind, window)
		local token = takeOver(p)
		local spot = Vector3.new(home.X, floorY + 3, home.Z + dist)
		place(p, spot, 0)
		local hitsBefore, dodgesBefore = hitCount(), dodges
		M.task.spawn(function()
			if wind then
				Boss._giantPunch(E, token, wind)
			else
				Boss.Attacks[move](E, token)
			end
		end)
		tick(1)
		local t0 = model:GetAttribute("ActionStart") or M.now()
		local rollAt = t0 + hitAfter - before
		local rolled = false
		local stop = t0 + hitAfter + (window or 0.8)
		while M.now() < stop do
			tick(1, function(dt)
				place(p, spot, dt)
			end)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5 -- (a roll: untouchable for half a second)
			end
		end
		rollUntil[p] = nil
		local landed = hitCount() > hitsBefore
		local dodged = dodges > dodgesBefore and not landed
		print(string.format("%-18s roll %.2fs before it hits: %s", label, before, landed and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landed then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landed then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver(p)
		runFor(2)
	end
	local A = def.Attacks
	-- the Giant Punch lunges from 0 to ~14 studs at Speed: it reaches you
	-- ~ (14 - the reach of his fist) / Speed after the wind-up
	local wind = 1.2
	local punchHit = wind + math.max(0, (14 - A.GiantPunch.Width - 1.5)) / A.GiantPunch.Speed
	case("GiantPunch", 14, punchHit, 0.1, true, "giant punch late", wind)
	case("GiantPunch", 14, punchHit, 0.9, false, "giant punch early", wind)
	-- the first slap: standing this close, its shockwave is on you the moment
	-- the hand lands (only the first slap counts here - the next comes Gap later)
	local slapHit = A.HandSlap.Tell
	case("HandSlap", 10, slapHit, 0.1, true, "hand slap late", nil, A.HandSlap.Gap - 0.15)
	case("HandSlap", 10, slapHit, 0.9, false, "hand slap early", nil, A.HandSlap.Gap - 0.15)
	local headHit = A.Headbutt.Tell + 0.05
	case("Headbutt", 8, headHit, 0.1, true, "headbutt late")
	case("Headbutt", 8, headHit, 0.9, false, "headbutt early")
	local tntHit = A.TNT.Tell + A.TNT.Flight
	case("TNT", 26, tntHit, 0.1, true, "tnt late")
	case("TNT", 26, tntHit, 0.9, false, "tnt early")
elseif SCENARIO == "tired" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.GiantPunch
	-- a MISS: the player steps out of the lane as it locks
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 14)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss._giantPunch(E, token, 1.2)
	end)
	runFor(1.0, function(dt)
		place(p, spot, dt)
	end)
	local aside = Vector3.new(home.X + 16, floorY + 3, home.Z + 8)
	local h0 = hitCount()
	runFor(0.9, function(dt)
		place(p, aside, dt)
	end)
	assert(hitCount() == h0, "stepping out of the Giant Punch's lane should dodge it")
	assert(model:GetAttribute("ActC") ~= nil, "a missed Giant Punch should leave him tired (slot 3)")
	-- he's tired: walk up and punch him
	local hp0 = model:GetAttribute("Health")
	local landed = 0
	local t0 = T
	while T - t0 < A.Tired - 0.3 do
		tick(1, function(dt)
			local c = model:GetPivot().Position
			place(p, Vector3.new(c.X + 5, floorY + 3, c.Z), dt)
			if punch(p, share) then
				landed += 1
			end
		end)
	end
	print(string.format("tired for %.1fs: %d punches landed, no hits on the player: %s", A.Tired, landed, tostring(hitCount() == h0)))
	assert(landed >= 3, "a tired Kongo should take free hits")
	assert(model:GetAttribute("Health") < hp0, "the free hits should hurt him")
	assert(hitCount() == h0, "nothing should hit you while he's tired")
	-- a HIT: standing in the lane - no tired slot
	token = takeOver(p)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss._giantPunch(E, token, 1.2)
	end)
	runFor(2.2, function(dt)
		place(p, spot, dt)
	end)
	assert(hitCount() > h0, "standing in the lane, the Giant Punch should land")
	assert(model:GetAttribute("ActC") == nil, "a Giant Punch that lands shouldn't leave him tired")
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
print(string.format("furthest from the middle %.1f (leash %d)  fastest %.0f studs/s  reward power %d chests %s victories %d",
	maxFromHome, def.Leash, maxSpeed, rewards.power, tostring(rewards.chests[7]), victories))
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
	print(string.format("most parts at once: %d  villagers moved: %d/%d  torches flared: %d/%d", maxParts, monkeysMoved, MONKEYS, torchesFlared, TORCHES))
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
	-- (all of him, every time)
	needDrawn({ "Thigh", "Shin", "Foot", "Hips", "Belly", "Chest", "Shoulder", "TieKnot", "Tie", "TieLetter", "UpperArm", "ForeArm",
		"Hand", "Head", "HairTuft", "Face", "Muzzle", "Brow", "Ear", "Eye", "Pupil", "Nostril", "Mouth", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "LaneWarning", "RingPiece", "HeldBarrel", "RollingBarrel", "HeldTNT", "FlyingTNT", "TNTWarning", "RollBall",
			"DizzyStar", "SpinWarning", "GrabWarning", "Teeth" })
		needWords({ "GIANT PUNCH!", "OOH OOH!", "SPINNING KONG!", "YOINK!", "GOING BANANAS!" })
	elseif SCENARIO == "full" then
		needWords({ "*YAWN*", "GOING BANANAS!" })
	elseif SCENARIO == "tired" then
		needWords({ "HIT HIM!" })
	end
	if SCENARIO ~= "timing" and SCENARIO ~= "tired" and monkeysMoved == 0 then
		problem("the monkey villagers should bounce along during the fight")
	end
	if (SCENARIO == "full" or SCENARIO == "attacks") and torchesFlared == 0 then
		problem("the tiki torches should flare up in round 2")
	end
end
if maxFromHome > def.Leash + 0.5 then
	problem(string.format("he went %.1f from the middle (leash %d)", maxFromHome, def.Leash))
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
