--!nocheck
-- PETALINA (floor 8) in the pretend Roblox: the real GreenhouseBuilder arena,
-- the real BossService with Bosses/Petalina.lua, and (client mode) the real
-- BossClient drawing her with BossBodies/Petalina.lua on a pretend player's
-- screen. Pretend players circle her, roll now and then, jump now and then
-- and punch her whenever she's in reach (in round 2 they keep to the paths,
-- like a real player would).
--   luau test_petalina.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights her to the death (both rounds)
--   attacks  every move forced in turn, in round one and round two, on a
--            player who stands still where it reaches (so each one's hit is
--            seen to land) - then again on one who rolls (dodged)
--   reset    the player leaves mid-fight (she resets, a bud again, and every
--            flytrap goes), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll just before a hit dodges it,
--            a roll too early gets you hit
--   droop    after a Face Stretch her head lies on the floor: punches on it
--            land (and it's out of reach once it's back up)
--   traps    seeds sprout flytraps: they bite whoever comes close, a punch
--            pops one, and left alone they wilt
--   thorns   round 2: standing on a flower bed stings, standing on a path
--            doesn't (and nothing stings before the thorns have grown)
-- It checks: no errors or warnings, no broken numbers, she never moves, every
-- move is seen (and draws its warnings, in client mode), round 2 comes at
-- half health, she dies, the reward (Power) is paid - and floor 8 has no loot
-- (it's waiting for the loot rework).
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
-- the world: the real greenhouse
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local GardenPlan = mount.require(mount.module("ReplicatedStorage/GardenPlan.lua"))
local arena = mount.require(mount.module("ServerScriptService/GreenhouseBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 8, "the greenhouse should be built as floor 8")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the greenhouse needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the greenhouse needs a way out (ArenaExit)")
local FIGHT_R = arena:GetAttribute("FightRadius")
local THORNS = #CollectionService:GetTagged("GardenThorn")
local FLIES = #CollectionService:GetTagged("GardenButterfly")
assert(THORNS > 40, "the flower beds should hide lots of bramble clumps for round 2 (got " .. THORNS .. ")")
assert(FLIES > 0, "the greenhouse should have butterflies")
-- the arrival spot must be on a path, and the beds must really be where
-- GardenPlan says (a bed in the middle of a quarter, a path on the axes)
do
	local c = arena:GetAttribute("Center")
	local off = spawnPart.Position - c
	assert(GardenPlan.safe(off.X, off.Z), "you should arrive on a path")
	assert(not GardenPlan.safe(24, 24), "the middle of a quarter should be flower bed")
	assert(GardenPlan.safe(0, 30) and GardenPlan.safe(30, 0) and GardenPlan.safe(10, 10) and GardenPlan.safe(40, 40),
		"the paths (and the inner and outer rings) should be safe")
	local sx, sz = GardenPlan.nearestSafe(24, 24)
	assert(GardenPlan.safe(sx, sz), "nearestSafe should find a path")
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
	p:SetAttribute("SpireFloor", 8)
end
local function leave(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
end

----------------------------------------------------------------------
-- CombatService and PlayerService, pretend
----------------------------------------------------------------------
local hitsOn, dodges, shoves = {}, 0, 0
local quietHits = 0
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
	if quiet then
		quietHits += 1
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
local shapes = {}
function Combat.SetTargetShape(m, fn)
	shapes[m] = fn
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
local E = assert(BS.Encounter(8), "Petalina should be built on floor 8")
model = E.model
local def = E.def
assert(def.Short == "Petalina", "floor 8's boss should be Petalina")
local Boss = E.boss
local home, floorY = E.home, E.floorY
assert(shapes[model], "she should tell CombatService where her body is (SetTargetShape)")

----------------------------------------------------------------------
-- client mode: her body on the first player's screen
----------------------------------------------------------------------
local drawn, guis = {}, {}
local maxParts = 0
local flyStart = {}
local fliesMoved, thornsGrown = 0, 0
local thornStart = {}
local thornBase = {}
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
	for _, f in ipairs(CollectionService:GetTagged("GardenButterfly")) do
		flyStart[f] = f.PrimaryPart.CFrame
	end
	for _, c in ipairs(CollectionService:GetTagged("GardenThorn")) do
		thornStart[c] = c.PrimaryPart.CFrame
		thornBase[c] = c.PrimaryPart.CFrame.Position.Y
	end
	math.randomseed(SEED)
	mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)
end
local function lookAtDrawing()
	local holders = { workspace:FindFirstChild("BossFX") }
	for _, fx in ipairs(holders) do
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
	-- (the butterflies flitting; the brambles growing in round 2)
	for f, cf in pairs(flyStart) do
		if f.PrimaryPart and (f.PrimaryPart.CFrame.Position - cf.Position).Magnitude > 0.05 then
			fliesMoved += 1
			flyStart[f] = nil
		end
	end
	for c, cf in pairs(thornStart) do
		if c.PrimaryPart and c.PrimaryPart.CFrame.Position.Y > cf.Position.Y + 3 then
			thornsGrown += 1
			thornStart[c] = nil
		end
	end
	local me = Players.LocalPlayer
	local pg = me and me:FindFirstChild("PlayerGui")
	for _, holder in ipairs({ pg, workspace:FindFirstChild("BossFX") }) do
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
-- punching, the way CombatService does: at the nearest point of her body
-- (her own SetTargetShape), and at flytraps (from their middles)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded, headPunches, trapsPopped = 0, 0, 0
local function punchModel(p, m, share)
	local before = m:GetAttribute("Health") or 0
	local damage = math.max(1, math.floor((m:GetAttribute("MaxHealth") or 1) * share))
	if m:GetAttribute("Invulnerable") then
		damage = 0
	end
	local floorHp = m:GetAttribute("MinHealth") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	m:SetAttribute("Health", math.max(0, hp))
	m:FindFirstChild("OnHit"):Fire(p, damage, hp <= 0)
	return damage > 0, hp <= 0
end
local function punch(p, share)
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return false
	end
	local root = rootOf(p)
	-- a flytrap in reach first (they're small and close)
	for _, trap in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if trap ~= model and trap:GetAttribute("Kind") == "Flytrap" and (trap:GetAttribute("Health") or 0) > 0 then
			local c = trap:GetPivot().Position
			local gap = (Vector3.new(c.X, 0, c.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - (trap:GetAttribute("HitRadius") or 2)
			if gap <= PUNCH_RANGE then
				lastPunch[p] = T
				local _, killed = punchModel(p, trap, 1)
				if killed then
					trapsPopped += 1
				end
				return false
			end
		end
	end
	if not CollectionService:HasTag(model, "CombatTarget") or (model:GetAttribute("Health") or 0) <= 0 then
		return false
	end
	local at, radius = shapes[model](root.Position)
	local gap = (Vector3.new(at.X, 0, at.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - radius
	if gap > PUNCH_RANGE or math.abs(at.Y - root.Position.Y) >= 12 then
		return false
	end
	lastPunch[p] = T
	local ok = punchModel(p, model, share)
	if ok then
		punchesLanded += 1
		if (Vector3.new(at.X, 0, at.Z) - Vector3.new(home.X, 0, home.Z)).Magnitude > def.StemRadius + 1 then
			headPunches += 1
		end
	end
	return ok
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
-- keep inside the garden's wall, like the real invisible wall does
local function inGarden(pos)
	local off = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	if off.Magnitude > FIGHT_R - 1 then
		off = off.Unit * (FIGHT_R - 1)
	end
	return Vector3.new(home.X + off.X, pos.Y, home.Z + off.Z)
end
-- (in round 2 a sensible player keeps to the paths)
local function keepSafe(pos)
	if E.phase < 2 then
		return pos
	end
	local x, z = GardenPlan.nearestSafe(pos.X - home.X, pos.Z - home.Z)
	return Vector3.new(home.X + x, pos.Y, home.Z + z)
end

-- A fighter: circles her at a distance that swells and shrinks (in close to
-- punch, out to where she throws things), changes direction now and then,
-- rolls every few seconds and jumps every few more.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local r = (style == "far") and (38 + 10 * math.sin(phaseT * 0.4)) or (5 + 18 * (1 + math.sin(phaseT * 0.31)))
	local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
	local ang = phaseT * 0.5 * spin + k * 2
	local want = keepSafe(Vector3.new(home.X + math.cos(ang) * r, 0, home.Z + math.sin(ang) * r))
	-- her head is down on the floor: go and hit it
	if E.headNow and E.head and M.now() > E.head.landAt then
		want = Vector3.new(E.headNow.X + 3, 0, E.headNow.Z + 3)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 18
	local nextPos = inGarden(moveToward(base, want, speed, dt))
	local y = floorY + 3
	local jumpU = (phaseT % 3.1) / 0.6
	if jumpU < 1 then
		y = y + 4 * math.sin(math.pi * jumpU)
	end
	place(p, Vector3.new(nextPos.X, y, nextPos.Z), dt)
end

----------------------------------------------------------------------
-- watching her
----------------------------------------------------------------------
local seen = {}
local order = {}
local maxFromHome = 0
local sawPhase2 = false
local trapsSeen = 0
local trapIds = {}
local function watch()
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
		problem("her position is broken at " .. string.format("%.2f", T))
	end
	maxFromHome = math.max(maxFromHome, Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude)
	if E.headNow and M.isNaNv and M.isNaNv(E.headNow) then
		problem("her head's position is broken")
	end
	local folder = workspace:FindFirstChild("PetalinaProps")
	for _, t in ipairs(folder and folder:GetChildren() or {}) do
		local id = t:GetAttribute("Id")
		if id and not trapIds[id] then
			trapIds[id] = true
			trapsSeen += 1
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
	end
end
local function runFor(seconds, each)
	tick(math.floor(seconds / DT + 0.5), each)
end
local function stateIs(s)
	return model:GetAttribute("State") == s
end
local share = 1 / 110 -- each punch takes this much of her health
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
-- stops her brain (a new token) and clears the garden, facing south - so a
-- forced move starts from a known place
local function takeOver(p)
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.waves, E.clouds, E.head, E.headNow = {}, {}, nil, nil
	for _, trap in ipairs(E.traps) do
		trap.dieAt = 0
	end
	E.facing = Vector3.new(0, 0, 1)
	E.target, E.targetSince = p, M.now()
	runFor(0.1)
	return E.token
end
local function roundTwo(p)
	takeOver(p)
	local max = model:GetAttribute("MaxHealth")
	model:SetAttribute("Health", math.floor(max * def.PhaseAt))
	model:FindFirstChild("OnHit"):Fire(p, 1, false)
	runFor(def.BreakTime + def.Thorns.Grace + 0.5)
	assert(E.phase == 2 and stateIs("Fighting"), "round 2 should come at half health")
end

-- where each move is forced from: the player this far in front of her (south,
-- on the south path)
local SPOTS = {
	SeedSpit = 22, Petals = 24, VineWhip = 18, Pollen = 20, FaceStretch = 20, RootRing = 8, Sunbathe = 30,
	ThornRing = 20, SeedRain = 20,
}
local HARMLESS = { Sunbathe = true }

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone she should be back, asleep")
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
	assert(stateIs("Dormant"), "she should reset when everyone leaves")
	assert(#E.traps == 0 and #E.clouds == 0 and #E.waves == 0, "a reset clears her flytraps, pollen and rings")
	assert(model:GetAttribute("ThornsAt") == nil, "a reset takes the thorns away")
	local folder = workspace:FindFirstChild("PetalinaProps")
	assert(not folder or #folder:GetChildren() == 0, "a reset takes every flytrap away")
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
			roundTwo(p)
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if a.Phase == phase or (phase == 2 and (name == "Petals" or name == "VineWhip" or name == "SeedSpit")) then
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
	if trapsSeen == 0 then
		problem("her seeds should sprout flytraps")
	end
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	-- one case: force `move`, stand still `dist` in front of her, and roll at
	-- (its hit - `before`) seconds; did it land?
	local function case(move, dist, hitAfter, before, wantDodge, label, window)
		local token = takeOver(p)
		local spot = Vector3.new(home.X, floorY + 3, home.Z + dist)
		place(p, spot, 0)
		local hitsBefore, dodgesBefore = hitCount(), dodges
		M.task.spawn(function()
			Boss.Attacks[move](E, token)
		end)
		tick(1)
		local t0 = model:GetAttribute("ActionStart") or M.now()
		local rollAt = t0 + hitAfter - before
		local rolled = false
		local stop = t0 + hitAfter + (window or 0.6)
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
	case("RootRing", 8, A.RootRing.Tell, 0.1, true, "root ring late")
	case("RootRing", 8, A.RootRing.Tell, 0.9, false, "root ring early")
	-- the vines race out from her stem: at 18 studs they reach you 18 / Speed after the Tell
	local vineHit = A.VineWhip.Tell + 18 / A.VineWhip.Speed
	case("VineWhip", 18, vineHit, 0.1, true, "vine whip late", 0.4)
	case("VineWhip", 18, vineHit, 0.9, false, "vine whip early", 0.4)
	-- the first seed lands right by you, Flight after it's spat
	local seedHit = A.SeedSpit.Tell + A.SeedSpit.Flight
	case("SeedSpit", 22, seedHit, 0.1, true, "seed spit late", 0.12)
	case("SeedSpit", 22, seedHit, 0.9, false, "seed spit early", 0.12)
	-- her head races down the lane: at 20 studs it's on you about here
	local lane = A.FaceStretch.Time * (GardenPlan.DIVE + (1 - GardenPlan.DIVE) * (20 - 6) / (23 - 6))
	case("FaceStretch", 20, A.FaceStretch.Tell + lane, 0.1, true, "face stretch late")
	case("FaceStretch", 20, A.FaceStretch.Tell + lane, 0.9, false, "face stretch early")
elseif SCENARIO == "droop" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.FaceStretch
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 22)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss.Attacks.FaceStretch(E, token)
	end)
	-- step out of the lane just after it locks
	runFor(A.Tell * A.Commit + 0.1, function(dt)
		place(p, spot, dt)
	end)
	local aside = spot + Vector3.new(9, 0, 0)
	local h0 = hitCount()
	runFor(A.Tell * (1 - A.Commit) + A.Time + 0.2, function(dt)
		place(p, aside, dt)
	end)
	assert(hitCount() == h0, "stepping out of the Face Stretch's lane should dodge it")
	assert(E.headNow, "her head should be lying on the floor after a Face Stretch")
	-- walk up to her head and punch it
	local hp0 = model:GetAttribute("Health")
	local landed = 0
	local t0 = T
	while T - t0 < A.Droop - 0.4 do
		tick(1, function(dt)
			local hd = E.headNow
			if hd then
				place(p, Vector3.new(hd.X + 5, floorY + 3, hd.Z), dt)
				if punch(p, share) then
					landed += 1
				end
			end
		end)
	end
	print(string.format("head down for %.1fs: %d punches landed on it (%d counted on her head)", A.Droop, landed, headPunches))
	assert(landed >= 3 and headPunches >= 3, "punches on her drooping head should land")
	assert(model:GetAttribute("Health") < hp0, "the punches on her head should hurt her")
	assert(hitCount() == h0, "nothing should hit you while her head's down")
	runFor(A.Back + 1.5)
	assert(E.headNow == nil, "her head should go back up")
	-- from where her head was, her stem is far out of reach now
	local at, radius = shapes[model](aside)
	local gap = (Vector3.new(at.X, 0, at.Z) - Vector3.new(aside.X, 0, aside.Z)).Magnitude - radius
	assert(gap > PUNCH_RANGE, "once her head's back up, you can't hit her from out there")
elseif SCENARIO == "traps" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local f = def.Flytrap
	local A = def.Attacks.SeedSpit
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 22)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss.Attacks.SeedSpit(E, token)
	end)
	-- dodge the seeds (roll through the landing), then stand still by the traps
	rollUntil[p] = T + A.Tell + A.Flight + 1
	runFor(A.Tell + A.Seeds[1] * A.Gap + A.Flight + f.Grow + 0.3, function(dt)
		place(p, spot, dt)
	end)
	rollUntil[p] = nil
	local live = 0
	for _, trap in ipairs(E.traps) do
		if not trap.gone then
			live += 1
		end
	end
	assert(live >= 1, "seeds should have sprouted flytraps")
	E.token += 1 -- (she stops: just the traps now)
	local h0 = hitCount()
	runFor(f.Tell + f.Rest + 1, function(dt)
		place(p, spot, dt)
	end)
	print(string.format("%d flytraps sprouted; bites on a player standing by them: %d", live, hitCount() - h0))
	assert(hitCount() > h0, "a flytrap should bite a player standing next to it")
	-- punch them all: one punch each
	local before = trapsPopped
	for _ = 1, 40 do
		tick(1, function(dt)
			for _, trap in ipairs(E.traps) do
				if not trap.gone then
					place(p, trap.pos + Vector3.new(3, 3, 0), dt)
					punch(p, share)
					break
				end
			end
		end)
		runFor(PUNCH_EVERY)
	end
	assert(trapsPopped - before >= live, "one punch should pop each flytrap")
	runFor(1)
	local folder = workspace:FindFirstChild("PetalinaProps")
	assert(not folder or #folder:GetChildren() == 0, "popped flytraps should go away")
	-- left alone, they wilt
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.SeedSpit(E, token)
	end)
	local far = Vector3.new(home.X + 40, floorY + 3, home.Z + 40)
	runFor(A.Tell + 3, function(dt)
		place(p, far, dt)
	end)
	E.token += 1
	runFor(f.Life + 1, function(dt)
		place(p, far, dt)
	end)
	local left = 0
	for _, trap in ipairs(E.traps) do
		if not trap.gone then
			left += 1
		end
	end
	assert(left == 0, "flytraps left alone should wilt after their Life")
elseif SCENARIO == "thorns" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local bed = Vector3.new(home.X + 24, floorY + 3 + GardenPlan.BedUp, home.Z + 24)
	local path = Vector3.new(home.X, floorY + 3, home.Z + 30)
	-- round 1: beds are just beds
	takeOver(p)
	local q0 = quietHits
	runFor(3, function(dt)
		place(p, bed, dt)
	end)
	assert(quietHits == q0, "a flower bed shouldn't sting in round 1")
	roundTwo(p)
	E.token += 1 -- (she stops: just the thorns now)
	q0 = quietHits
	runFor(3, function(dt)
		place(p, path, dt)
	end)
	assert(quietHits == q0, "a path should be safe from the thorns")
	runFor(3, function(dt)
		place(p, bed, dt)
	end)
	local stings = quietHits - q0
	print(string.format("round 2: 3s on a path - no stings; 3s on a bed - %d stings", stings))
	assert(stings >= 4, "standing on a flower bed in round 2 should sting")
	q0 = quietHits
	runFor(2, function(dt)
		place(p, bed + Vector3.new(0, 7, 0), dt)
	end)
	assert(quietHits == q0, "jumping high over the thorns shouldn't sting")
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
print(string.format("time %.1f  state %s  phase %s  punches %d (on her head %d)  traps seen %d popped %d  hits on players: %s  dodged %d  shoves %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, headPunches, trapsSeen, trapsPopped,
	table.concat(hitList, " "), dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("furthest from the middle %.1f  reward power %d  victories %d", maxFromHome, rewards.power, victories))
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
	print(string.format("most parts at once: %d  butterflies moved: %d/%d  brambles grown: %d/%d", maxParts, fliesMoved, FLIES, thornsGrown, THORNS))
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
	-- (all of her, every time)
	needDrawn({ "Stem", "Leaf", "Petal", "PetalTip", "Face", "Eye", "Pupil", "Cheek", "Mouth", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "Seed", "SeedWarning", "FlyingPetal", "PetalPath", "VineWarning", "Vine", "PollenCloud", "PollenWarning",
			"LaneWarning", "Neck", "RootWarning", "RootSpike", "ThornRing", "TrapHead", "TrapJaw", "TrapStem", "Teeth" })
		needWords({ "CHOMP!", "LA LA LA~", "YOU TRAMPLED MY FLOWERS!" })
	elseif SCENARIO == "full" then
		needWords({ "YOU TRAMPLED MY FLOWERS!" })
	elseif SCENARIO == "droop" then
		needWords({ "HIT HER!" })
	end
	if SCENARIO == "full" or SCENARIO == "reset" then
		-- (the fight's over: the brambles have sunk back into the soil)
		local up = 0
		for _, c in ipairs(CollectionService:GetTagged("GardenThorn")) do
			if c.PrimaryPart.CFrame.Position.Y > thornBase[c] + 0.5 then
				up += 1
			end
		end
		if SCENARIO == "full" and up > 0 then
			problem(up .. " brambles were still up after she was beaten and the garden went quiet")
		end
	end
	if SCENARIO ~= "timing" and fliesMoved == 0 then
		problem("the butterflies should flit about")
	end
	if (SCENARIO == "full" or SCENARIO == "attacks" or SCENARIO == "thorns") and thornsGrown < THORNS * 0.9 then
		problem(string.format("the brambles should grow over the beds in round 2 (%d of %d did)", thornsGrown, THORNS))
	end
end
if maxFromHome > 0.5 then
	problem(string.format("she moved %.1f from her spot (she's rooted!)", maxFromHome))
end
if SCENARIO == "full" or SCENARIO == "duo" or SCENARIO == "reset" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("she should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 then
		problem("beating her should pay Power")
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
else
	print("FAIL")
end
