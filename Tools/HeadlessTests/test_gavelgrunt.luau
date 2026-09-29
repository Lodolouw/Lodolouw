--!nocheck
-- KING GAVELGRUNT (floor 10, the final boss) in the pretend Roblox: the real
-- ThroneBuilder arena, the real BossService with Bosses/Gavelgrunt.lua, and
-- (client mode) the real BossClient drawing him with BossBodies/Gavelgrunt.lua
-- on a pretend player's screen. Pretend players circle him, roll now and then,
-- jump now and then, punch him whenever he's in reach, and knock over his
-- guards, his toe and his platter.
--   luau test_gavelgrunt.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (all three rounds and the
--            Final Gavel)
--   attacks  every move forced in turn, in each round it's used in, on a
--            player who stands still where it reaches (so each one's hit is
--            seen to land) - then again on one who rolls (dodged)
--   reset    the player leaves mid-fight in round 3 (he resets, the pillars
--            stand again, the throne's back, every prop goes), then comes
--            back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll just before a hit dodges it,
--            a roll too early gets you hit
--   toe      the toe stomp: punch the glowing toe and he hops (punches on him
--            land); leave it and the toe stops glowing
--   coins    tax collector: coins you walk over heal you; the ones left are
--            sucked up, and his next move hits harder
--   feast    the royal feast: break the platter and he chokes; leave him
--            and he heals
--   crown    crown grab: hit him enough on the way and he trips; don't and
--            he puts it back on, roars and heals
--   guilty   GUILTY!: standing on a podium softens it; a friend beside you
--            shares it
--   pillars  a smash on a pillar breaks it, round 3 crumbles the rest, a
--            reset stands them all up again; the throne toss leaves the
--            throne where it lands
--   final    the Final Gavel at FinalAt: he's untouchable while he winds up,
--            the slam and shockwave hit a player standing still but not one
--            jumping it, then he's worn out (open)
--   entrance asleep up on his throne; walk up and THE ENTRANCE plays (in
--            client mode: he stands up on the throne, then leaps down to
--            where he fights from); leave and he goes back up onto it
-- It checks: no errors or warnings, no broken numbers, he stays on the
-- courtyard, every move is seen (and draws its warnings, in client mode),
-- round 2 comes at PhaseAt and round 3 at Round3At, he dies, the reward
-- (Power) is paid - and floor 10 has no loot (it's waiting for the loot rework).
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
-- the world: the real courtyard
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Items = mount.require(mount.module("ReplicatedStorage/Items.lua"))
local ThronePlan = mount.require(mount.module("ReplicatedStorage/ThronePlan.lua"))
local arena = mount.require(mount.module("ServerScriptService/ThroneBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 10, "the courtyard should be built as floor 10")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the courtyard needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the courtyard needs a way out (ArenaExit)")
assert(#CollectionService:GetTagged("ThroneEdgeWall") >= 20, "the courtyard needs walls round it")
assert(#CollectionService:GetTagged("ThronePillar") == #ThronePlan.Pillars, "the courtyard should have its pillars")
assert(#CollectionService:GetTagged("ThronePodium") == #ThronePlan.Podiums, "the courtyard should have its podiums")
assert(#CollectionService:GetTagged("KingThrone") == 1, "the courtyard should have the throne")
local CENTER = arena:GetAttribute("Center")
local RADIUS = arena:GetAttribute("FightRadius")
assert(RADIUS == ThronePlan.Radius, "the arena's courtyard should be ThronePlan's size")
-- (no loot yet: floor 10's chest is waiting for the loot rework)
assert(Items.ByFloor[10] == nil, "floor 10 shouldn't have any loot yet")
do
	local off = spawnPart.Position - CENTER
	assert(Vector3.new(off.X, 0, off.Z).Magnitude < RADIUS, "you should arrive on the courtyard")
	-- the flagstones are all on the courtyard, and a spot is on the one it's in
	local tiles = ThronePlan.tiles()
	assert(#tiles > 40, "the courtyard should have plenty of flagstones")
	for _, t in ipairs(tiles) do
		assert(math.sqrt(t[1] * t[1] + t[2] * t[2]) <= RADIUS, "every flagstone should be on the courtyard")
	end
	assert(ThronePlan.onTile(3, -5, 0, 0) and not ThronePlan.onTile(7, 0, 0, 0), "onTile should know which flagstone a spot is on")
	assert(ThronePlan.podiumAt(ThronePlan.Podiums[1].X, ThronePlan.Podiums[1].Z) == 1, "podiumAt should find a podium")
	local s = ThronePlan.encodeBroken({ true, false, true, false })
	assert(s == "1010" and ThronePlan.decodeBroken(s)[3] == true, "the broken pillars should survive a round trip")
	-- no pillar or podium in the way of the carpet or where he waits
	local h = ThronePlan.Home
	assert(not ThronePlan.pillarAt(h.X, h.Z, 8), "his home spot should be clear of the pillars")
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
	p:SetAttribute("SpireFloor", 10)
end
local function leave(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
end

----------------------------------------------------------------------
-- CombatService and PlayerService, pretend
----------------------------------------------------------------------
local hitsOn, dodges, shoves = {}, 0, 0
local hitLog = {} -- { player, amount, action }
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
	if amount ~= amount or amount < 0 then
		problem("a hit did a broken amount of damage")
	end
	if Combat.IsInvulnerable(p) then
		dodges += 1
		return false
	end
	local act = model and model:GetAttribute("Action") or "?"
	hitsOn[act] = (hitsOn[act] or 0) + 1
	table.insert(hitLog, { player = p, amount = amount, action = act })
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
local E = assert(BS.Encounter(10), "the king should be built on floor 10")
model = E.model
local def = E.def
assert(def.Short == "Gavelgrunt", "floor 10's boss should be King Gavelgrunt")
local Boss = E.boss
local home, floorY = E.home, E.floorY
assert(shapes[model], "he should tell CombatService where his body is (SetTargetShape)")
assert(model:GetAttribute("Pillars") == "0000", "every pillar should start standing")
assert((E.center - CENTER).Magnitude < 1e-3, "he should know where the middle of the courtyard is")

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
	cam.CFrame = CFrame.new(home + Vector3.new(0, 30, 80), home)
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
	for _, holder in ipairs({ pg, workspace:FindFirstChild("BossFX") }) do
		for _, d in ipairs(holder and holder:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Text ~= "" and d.Visible ~= false and (d.TextTransparency or 0) < 1 then
				local anc = d:FindFirstAncestorWhichIsA("ScreenGui") or d:FindFirstAncestorWhichIsA("BillboardGui")
					or d:FindFirstAncestorWhichIsA("SurfaceGui")
				if anc and anc.Enabled ~= false then
					guis[d.Text] = true
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- punching, the way CombatService does: at the nearest point of his body
-- (his own SetTargetShape), and at his props (from their middles)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded = 0
local popped = {} -- [Kind] = how many broken
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
local function propInReach(root)
	local best, bestGap = nil, math.huge
	for _, t in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if t ~= model and t:GetAttribute("Kind") and (t:GetAttribute("Health") or 0) > 0 then
			local c = t:GetPivot().Position
			local gap = (Vector3.new(c.X, 0, c.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - (t:GetAttribute("HitRadius") or 2)
			if gap <= PUNCH_RANGE and gap < bestGap then
				best, bestGap = t, gap
			end
		end
	end
	return best
end
local PUNCHES = {
	Guard = def.Attacks.RoyalDecree.Punches,
	Toe = def.Attacks.ToeStomp.Punches,
	Platter = def.Attacks.RoyalFeast.Punches,
}
local function punch(p, share, propsFirst)
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return false
	end
	local root = rootOf(p)
	if propsFirst ~= false then
		local prop = propInReach(root)
		if prop then
			lastPunch[p] = T
			local kind = prop:GetAttribute("Kind")
			local _, killed = punchModel(p, prop, 1 / (PUNCHES[kind] or 1.5) + 1e-6)
			if killed then
				popped[kind] = (popped[kind] or 0) + 1
			end
			return false
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
-- keep on the courtyard, like the real invisible walls do
local function onCourt(pos)
	local off = Vector3.new(pos.X - CENTER.X, 0, pos.Z - CENTER.Z)
	if off.Magnitude > RADIUS - 1 then
		off = off.Unit * (RADIUS - 1)
	end
	return Vector3.new(CENTER.X + off.X, pos.Y, CENTER.Z + off.Z)
end
local function bossPos()
	return E.pos
end
local function propOf(kind)
	local folder = workspace:FindFirstChild("GavelgruntProps")
	for _, t in ipairs(folder and folder:GetChildren() or {}) do
		if t:GetAttribute("Kind") == kind and not t:GetAttribute("EndKind") then
			return t
		end
	end
	return nil
end

-- A fighter: circles him at a distance that swells and shrinks, changes
-- direction now and then, rolls every few seconds and jumps every few more.
-- It goes for his toe, his platter and his guards when they're about.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local b = bossPos()
	local r = (style == "far") and (32 + 8 * math.sin(phaseT * 0.4)) or (10 + 12 * (1 + math.sin(phaseT * 0.31)))
	local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
	local ang = phaseT * 0.5 * spin + k * 2
	local want = Vector3.new(b.X + math.cos(ang) * r, 0, b.Z + math.sin(ang) * r)
	if style ~= "far" then
		local prop = propOf("Toe") or propOf("Platter")
		if prop then
			local c = prop:GetPivot().Position
			want = Vector3.new(c.X, 0, c.Z) + Vector3.new(3, 0, 0)
		end
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 18
	local nextPos = onCourt(moveToward(base, want, speed, dt))
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
local maxOff = 0
local sawPhase = 1
local propIds, propsSeen = {}, {}
local roundAt = {}
local function watch()
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
	end
	if act and order[#order] ~= act and act ~= "Idle" then
		table.insert(order, act)
	end
	local ph = model:GetAttribute("Phase") or 1
	if ph > sawPhase then
		sawPhase = ph
		roundAt[ph] = T
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	local off = Vector3.new(pos.X - CENTER.X, 0, pos.Z - CENTER.Z)
	maxOff = math.max(maxOff, off.Magnitude)
	local folder = workspace:FindFirstChild("GavelgruntProps")
	for _, t in ipairs(folder and folder:GetChildren() or {}) do
		local id = t:GetAttribute("Id")
		local kind = t:GetAttribute("Kind")
		if id and not propIds[id] then
			propIds[id] = true
			propsSeen[kind] = (propsSeen[kind] or 0) + 1
		end
		local pp = t.PrimaryPart and t.PrimaryPart.Position
		if pp and M.isNaNv and M.isNaNv(pp) then
			problem("a prop's position is broken: " .. tostring(kind))
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
local share = 1 / def.HealthPunches
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
-- stops his brain (a new token), clears his props, puts him back where he
-- waits facing the gate - so a forced move starts from a known place
local function takeOver(p)
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.motion, E.sweep, E.pillarSweep = nil, nil, nil
	for _, g in ipairs(E.guards) do
		g.dieAt = 0
	end
	for _, c in ipairs(E.coins) do
		c.untilT = math.huge
		c.model:Destroy()
		c.gone = true
	end
	E.coins = {}
	E.waves = {}
	E.taxCoins, E.taxBoost = 0, 1
	E.pos = home
	E.facing = Vector3.new(0, 0, 1)
	E.target, E.targetSince = p, M.now()
	E.lastFeast, E.lastQuake, E.lastCrown, E.lastGuilty = nil, nil, nil, nil
	runFor(0.1)
	return E.token
end
-- straight to round `n` (2 or 3), the way the real fight gets there
local function toRound(p, n)
	takeOver(p)
	local max = model:GetAttribute("MaxHealth")
	if E.phase < 2 then
		model:SetAttribute("Health", math.floor(max * def.PhaseAt))
		model:FindFirstChild("OnHit"):Fire(p, 1, false)
		runFor(def.BreakTime + 0.5)
		assert(E.phase == 2 and stateIs("Fighting"), "round 2 should come at PhaseAt")
	end
	if n >= 3 and E.phase < 3 then
		takeOver(p)
		model:SetAttribute("Health", math.floor(max * def.Round3At))
		runFor(def.BerserkTime + 0.4)
		assert(E.phase == 3 and stateIs("Fighting"), "round 3 should come at Round3At")
	end
end
local function force(p, name, dist, dodge, seconds, each)
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + dist)
	place(p, spot, 0)
	local before, dodgesBefore = hitCount(), dodges
	local hp0 = model:GetAttribute("Health")
	M.task.spawn(function()
		local ok, err = pcall(Boss.Attacks[name], E, token)
		if not ok then
			problem("forced " .. name .. " errored: " .. tostring(err))
		end
	end)
	if dodge then
		rollUntil[p] = T + (seconds or 10) + 1
	end
	runFor(seconds or 10, each or function(dt)
		place(p, spot, dt) -- (standing still, not punching)
	end)
	rollUntil[p] = nil
	return hitCount() - before, dodges - dodgesBefore, (model:GetAttribute("Health") or 0) - hp0
end

-- where each move is forced from: the player this far in front of him (south)
local SPOTS = {
	RoyalSmash = 14, GavelSweep = 10, BellyBounce = 20, RoyalDecree = 14, ToeStomp = 10, TaxCollector = 14,
	TripleSlam = 16, HammerTornado = 14, BigGulp = 12, RocketHammer = 20, RoyalFeast = 20, RoyalRoll = 20,
	Earthquake = 14, CrownGrab = 12, Guilty = 14, ThroneToss = 14,
}
local HARMLESS = { TaxCollector = true, RoyalFeast = true }

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1200)
	print(string.format("round 2 at %.1fs, round 3 at %.1fs, beaten at %.1fs (from waking)", (roundAt[2] or 0), (roundAt[3] or 0), T))
	runFor(7)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, asleep")
	assert(model:GetAttribute("Pillars") == "0000", "the pillars should stand again after the fight")
	assert(model:GetAttribute("ThroneAt") == nil, "the throne should be back after the fight")
elseif SCENARIO == "duo" then
	local a = people[1] or makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1003)
	walkIn(a)
	walkIn(b)
	fightUntil({ a, b }, function()
		return stateIs("Dead")
	end, 1200)
	runFor(4)
elseif SCENARIO == "reset" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(p, 3)
	assert(model:GetAttribute("Pillars") == "1111", "round 3 should crumble every pillar")
	-- a guard and a throw, then walk out
	force(p, "RoyalDecree", 14, false, 1.5)
	force(p, "ThroneToss", 14, false, 4)
	assert(M.typeof(model:GetAttribute("ThroneAt")) == "Vector3", "the throne should stay where it landed")
	E.token += 1
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	assert(#E.guards == 0 and #E.coins == 0 and E.toe == nil and E.platter == nil, "a reset clears his guards, coins, toe and platter")
	assert(model:GetAttribute("Pillars") == "0000", "a reset stands the pillars up again")
	assert(model:GetAttribute("ThroneAt") == nil, "a reset puts the throne back")
	for _, pm in ipairs(CollectionService:GetTagged("ThronePillar")) do
		for _, part in ipairs(pm:GetChildren()) do
			if part.Name == "Column" and (part.Transparency ~= 0 or part.CanCollide ~= true) and part.Name ~= "Band" then
				local _ = part
			end
		end
	end
	runFor(1)
	local folder = workspace:FindFirstChild("GavelgruntProps")
	assert(not folder or #folder:GetChildren() == 0, "a reset takes every prop away")
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1200)
elseif SCENARIO == "entrance" then
	-- asleep up on his throne; THE ENTRANCE (standing up on it, the leap down
	-- to where he fights from); back up onto it once you've gone. (Where he's
	-- drawn is only checked in client mode.)
	local function headAt()
		local fx = workspace:FindFirstChild("BossFX")
		local b = fx and fx:FindFirstChild("GavelgruntBody")
		local h = b and b:FindFirstChild("Head")
		local pr = h and rawget(h, "__props")
		return pr and pr.CFrame and pr.CFrame.Position
	end
	local seat = E.center + ThronePlan.SeatAt
	local function over(pos, spot, r)
		return pos ~= nil and Vector3.new(pos.X - spot.X, 0, pos.Z - spot.Z).Magnitude <= r
	end
	local p = people[1] or makePlayer("Alpha", 1001)
	runFor(1)
	if MODE == "client" then
		local h = headAt()
		assert(over(h, seat, 8) and h.Y > floorY + ThronePlan.SeatHeight + 20, "asleep, he should be sitting up on his throne")
	end
	walkIn(p)
	place(p, Vector3.new(home.X, floorY + 3, home.Z + 30), 0)
	local woke, onThrone, landed = nil, false, false
	runFor(def.WakeTime + 1, function()
		if stateIs("Waking") then
			woke = woke or T
			if MODE == "client" then
				lookAtDrawing() -- (every frame: a flash of lightning is gone in a blink)
			end
			local h = MODE == "client" and headAt()
			local t = T - woke
			-- (and your lock-on goes where he's drawn: up on the throne, then down)
			local aim = model:GetAttribute("AimAt")
			if h and t > 1 and t < def.IntroDelay - 1.2 and over(h, seat, 8) and M.typeof(aim) == "Vector3" and over(aim, seat, 10) then
				onThrone = true
			end
			if h and t > def.IntroDelay + 0.3 and over(h, home, 8) and M.typeof(aim) == "Vector3" and over(aim, home, 10) then
				landed = true
			end
		end
	end)
	assert(woke, "walking up to him should wake him")
	assert(stateIs("Fighting"), "his entrance should end in the fight")
	if MODE == "client" then
		assert(onThrone, "he should stand up on his throne before he leaps (and your lock-on should follow him there)")
		assert(landed, "he should land where he fights from (and your lock-on should follow him)")
	end
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should go back to sleep once you've gone")
	if MODE == "client" then
		assert(over(headAt(), seat, 8), "back asleep, he should be up on his throne again")
	end
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
	local report = {}
	for _, phase in ipairs({ 1, 2, 3 }) do
		if phase >= 2 then
			toRound(p, phase)
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if a.Phase <= phase and (not a.UpTo or phase <= a.UpTo) then
				E.throneThrown = false
				local landed = force(p, name, SPOTS[name], false)
				E.throneThrown = false
				local _, dodged = force(p, name, SPOTS[name], true)
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
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
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
		local stop = t0 + hitAfter + (window or 0.4)
		while M.now() < stop do
			tick(1, function(dt)
				place(p, spot, dt)
			end)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5
			end
		end
		rollUntil[p] = nil
		local landed = hitCount() > hitsBefore
		local dodged = dodges > dodgesBefore and not landed
		print(string.format("%-22s roll %.2fs before it hits: %s", label, before, landed and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landed then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landed then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver(p)
		runFor(2)
	end
	local A = def.Attacks
	case("RoyalSmash", 14, A.RoyalSmash.Tell, 0.1, true, "royal smash late", 0.15)
	case("RoyalSmash", 14, A.RoyalSmash.Tell, 0.9, false, "royal smash early", 0.15)
	case("GavelSweep", 10, A.GavelSweep.Tell, 0.1, true, "gavel sweep late", 0.2)
	case("GavelSweep", 10, A.GavelSweep.Tell, 0.9, false, "gavel sweep early", 0.2)
	case("BellyBounce", 20, A.BellyBounce.Tell + A.BellyBounce.Air, 0.1, true, "belly bounce late", 0.2)
	case("BellyBounce", 20, A.BellyBounce.Tell + A.BellyBounce.Air, 0.9, false, "belly bounce early", 0.2)
	toRound(p, 3)
	case("Guilty", 14, A.Guilty.Tell + A.Guilty.Countdown, 0.1, true, "guilty gavel late", 0.2)
	case("Guilty", 14, A.Guilty.Tell + A.Guilty.Countdown, 0.9, false, "guilty gavel early", 0.2)
	case("Earthquake", 14, A.Earthquake.Tell + A.Earthquake.Air, 0.1, true, "earthquake late", 0.2)
	case("Earthquake", 14, A.Earthquake.Tell + A.Earthquake.Air, 0.9, false, "earthquake early", 0.2)
elseif SCENARIO == "toe" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.ToeStomp
	-- 1) punched: he hops, and punches on him land
	local token = takeOver(p)
	local spot = Vector3.new(home.X + 12, floorY + 3, home.Z + 6)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss.Attacks.ToeStomp(E, token)
	end)
	runFor(A.Tell + 0.1, function(dt)
		place(p, spot, dt)
	end)
	local toe = propOf("Toe")
	assert(toe, "his toe should glow (a prop you can punch)")
	local c = toe:GetPivot().Position
	for _ = 1, 30 do
		tick(1, function(dt)
			place(p, Vector3.new(c.X + 3, floorY + 3, c.Z), dt)
			punch(p, share)
		end)
		if (popped.Toe or 0) > 0 then
			break
		end
	end
	assert((popped.Toe or 0) > 0, "punching the toe should break it")
	runFor(0.3)
	assert(model:GetAttribute("Action") == "ToeHop", "punching his toe should make him hop")
	local hp0 = model:GetAttribute("Health")
	local landed = 0
	local t0 = T
	while T - t0 < A.Hop - 0.5 do
		tick(1, function(dt)
			place(p, Vector3.new(home.X, floorY + 3, home.Z + 10), dt)
			if punch(p, share, false) then
				landed += 1
			end
		end)
	end
	print(string.format("toe punched: hopping for %.1fs, %d punches landed on him", A.Hop, landed))
	assert(landed >= 3 and model:GetAttribute("Health") < hp0, "punches on him while he hops should land")
	-- 2) left alone: the toe stops glowing and he carries on
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.ToeStomp(E, token)
	end)
	runFor(A.Tell + A.Window + 0.4, function(dt)
		place(p, Vector3.new(home.X + 40, floorY + 3, home.Z + 20), dt)
	end)
	assert(propOf("Toe") == nil and model:GetAttribute("Action") ~= "ToeHop", "a toe left alone should stop glowing")
elseif SCENARIO == "coins" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.TaxCollector
	local hum = humOf(p)
	-- 1) grab them: they heal you
	local token = takeOver(p)
	hum.MaxHealth = 100
	hum.Health = 50
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 16)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss.Attacks.TaxCollector(E, token)
	end)
	runFor(A.Tell + A.Drop + 0.8, function(dt)
		place(p, spot, dt)
	end)
	for _ = 1, 120 do
		local target = nil
		for _, c in ipairs(E.coins) do
			if not c.gone then
				target = c
				break
			end
		end
		if not target then
			break
		end
		tick(1, function(dt)
			local here = lastPos[p]
			place(p, moveToward(here, Vector3.new(target.pos.X, floorY + 3, target.pos.Z), 24, dt), dt)
		end)
	end
	local healed = hum.Health - 50
	print(string.format("coins grabbed: healed %d (each heals %d)", healed, A.Heal))
	assert(healed >= A.Heal * 3, "grabbing coins should heal you")
	hum.MaxHealth, hum.Health = 1e9, 1e9
	-- 2) leave them: he sucks them up, and his next move hits harder
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.TaxCollector(E, token)
	end)
	runFor(A.Tell + A.Drop + 0.8 + A.Lie + 0.4, function(dt)
		place(p, Vector3.new(home.X + 50, floorY + 3, home.Z + 30), dt)
	end)
	local taxed = model:GetAttribute("Taxed") or 0
	print(string.format("coins left alone: he taxed %d", taxed))
	assert(taxed >= 4, "coins left alone should be sucked up (Taxed)")
	-- his next move, through the brain's own sums: a smash with the coins on it
	local base = def.Attacks.RoyalSmash.Damage
	E.token += 1
	E.pos, E.facing = home, Vector3.new(0, 0, 1)
	local tok2 = E.token
	local nBefore = #hitLog
	M.task.spawn(function()
		local coins = E.taxCoins or 0
		E.taxBoost = 1 + coins * A.PerCoin
		Boss.Attacks.RoyalSmash(E, tok2)
	end)
	runFor(def.Attacks.RoyalSmash.Tell + 0.3, function(dt)
		place(p, Vector3.new(home.X, floorY + 3, home.Z + 14), dt)
	end)
	local hitAmount = 0
	for i = nBefore + 1, #hitLog do
		if hitLog[i].action == "RoyalSmash" then
			hitAmount = math.max(hitAmount, hitLog[i].amount)
		end
	end
	print(string.format("his taxed smash hit for %.1f (normally %d)", hitAmount, base))
	assert(hitAmount > base * 1.2, "a move carrying taxed coins should hit harder")
	E.taxBoost = 1
elseif SCENARIO == "feast" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(p, 2)
	local A = def.Attacks.RoyalFeast
	local max = model:GetAttribute("MaxHealth")
	-- 1) left alone: he heals
	local token = takeOver(p)
	model:SetAttribute("Health", math.floor(max * 0.45))
	local hp0 = model:GetAttribute("Health")
	M.task.spawn(function()
		Boss.Attacks.RoyalFeast(E, token)
	end)
	runFor(A.Tell + A.Feast + 0.5, function(dt)
		place(p, Vector3.new(home.X + 45, floorY + 3, home.Z + 30), dt)
	end)
	local gained = model:GetAttribute("Health") - hp0
	print(string.format("feast left alone: he healed %.1f%% of his bar", gained / max * 100))
	assert(gained >= max * A.HealRate * A.Feast * 0.7, "a feast left alone should heal him")
	-- 2) the platter broken: he chokes, and the healing stops
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.RoyalFeast(E, token)
	end)
	runFor(A.Tell + 0.2)
	local plat = propOf("Platter")
	assert(plat, "the platter should roll in")
	local c = plat:GetPivot().Position
	for _ = 1, 90 do
		tick(1, function(dt)
			place(p, Vector3.new(c.X + 4, floorY + 3, c.Z), dt)
			punch(p, share)
		end)
		if (popped.Platter or 0) > 0 then
			break
		end
	end
	runFor(0.3)
	assert((popped.Platter or 0) > 0, "punching the platter should break it")
	assert(model:GetAttribute("Action") == "Choke", "breaking the platter should make him choke")
	print("platter broken: he chokes")
elseif SCENARIO == "crown" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(p, 3)
	local A = def.Attacks.CrownGrab
	local max = model:GetAttribute("MaxHealth")
	-- 1) left alone: he puts it back on and heals
	local token = takeOver(p)
	model:SetAttribute("Health", math.floor(max * 0.2))
	local hp0 = model:GetAttribute("Health")
	M.task.spawn(function()
		Boss.Attacks.CrownGrab(E, token)
	end)
	runFor(A.Tell + A.Rush + 0.6, function(dt)
		place(p, Vector3.new(home.X + 45, floorY + 3, home.Z - 20), dt)
	end)
	assert(seen.Crowned, "left alone he should get his crown back")
	assert(model:GetAttribute("Health") > hp0, "putting his crown back on should heal him")
	-- 2) hit him on the way: he trips
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.CrownGrab(E, token)
	end)
	local t0 = T
	while T - t0 < A.Tell + A.Rush and model:GetAttribute("Action") ~= "Tripped" do
		tick(1, function(dt)
			local b = E.pos
			place(p, Vector3.new(b.X + 10, floorY + 3, b.Z + 3), dt)
			punch(p, share, false)
		end)
	end
	runFor(0.2)
	assert(model:GetAttribute("Action") == "Tripped", "hitting him " .. A.Trip .. " times on the way should trip him")
	print("crown grab: tripped him")
elseif SCENARIO == "guilty" then
	local a = people[1] or makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1003)
	walkIn(a)
	fightUntil({ a }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(a, 3)
	local A = def.Attacks.Guilty
	local function sentence(spotA, spotB)
		local token = takeOver(a)
		E.target = a
		place(a, spotA, 0)
		if spotB then
			walkIn(b)
			place(b, spotB, 0)
		end
		local n0 = #hitLog
		M.task.spawn(function()
			Boss.Attacks.Guilty(E, token)
		end)
		runFor(A.Tell + A.Countdown + 0.4, function(dt)
			place(a, spotA, dt)
			if spotB then
				place(b, spotB, dt)
			end
		end)
		local got = {}
		for i = n0 + 1, #hitLog do
			if hitLog[i].action == "Guilty" then
				got[hitLog[i].player] = (got[hitLog[i].player] or 0) + hitLog[i].amount
			end
		end
		if spotB then
			leave(b)
		end
		return got
	end
	local open = Vector3.new(CENTER.X + 10, floorY + 3, CENTER.Z + 30)
	local pod = ThronePlan.Podiums[1]
	local onPod = Vector3.new(CENTER.X + pod.X, floorY + 3, CENTER.Z + pod.Z)
	local alone = sentence(open)
	local podium = sentence(onPod)
	local shared = sentence(open, open + Vector3.new(2, 0, 0))
	print(string.format("guilty: alone %.1f, on a podium %.1f, shared %.1f + %.1f", alone[a] or 0, podium[a] or 0, shared[a] or 0, shared[b] or 0))
	assert((alone[a] or 0) >= A.Damage * 0.99, "sentenced alone, the gavel should hit for its full Damage")
	assert((podium[a] or 0) > 0 and (podium[a] or 0) <= A.Damage * A.Podium + 0.01, "on a podium it should hit far softer")
	assert((shared[a] or 0) > 0 and (shared[b] or 0) > 0 and (shared[a] or 0) <= A.Damage / 2 + 0.01, "a friend beside you should share it")
elseif SCENARIO == "pillars" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	-- a smash on a pillar breaks it (the arena's pillar turns to rubble for everyone)
	local token = takeOver(p)
	local pillar = ThronePlan.Pillars[2] -- (south-east)
	local pWorld = CENTER + pillar
	E.pos = Vector3.new(pWorld.X - 12, floorY, pWorld.Z - 8)
	local spot = Vector3.new(pWorld.X, floorY + 3, pWorld.Z + 0.1)
	place(p, spot + Vector3.new(0, 0, 4.5), 0)
	M.task.spawn(function()
		Boss.Attacks.RoyalSmash(E, token)
	end)
	runFor(def.Attacks.RoyalSmash.Tell + 0.5, function(dt)
		place(p, spot + Vector3.new(0, 0, 4.5), dt)
	end)
	local s = model:GetAttribute("Pillars")
	print("after a smash by the south-east pillar: " .. tostring(s))
	assert(ThronePlan.decodeBroken(s)[2], "a smash on a pillar should break it")
	local pm = nil
	for _, m in ipairs(CollectionService:GetTagged("ThronePillar")) do
		if m:GetAttribute("Index") == 2 then
			pm = m
		end
	end
	local columnGone, rubbleShows = true, false
	for _, part in ipairs(pm:GetChildren()) do
		if part.Name == "Column" and (part.Transparency < 1 or part.CanCollide) then
			columnGone = false
		elseif part.Name == "Rubble" and part.Transparency < 1 then
			rubbleShows = true
		end
	end
	assert(columnGone and rubbleShows, "a broken pillar should be rubble in the arena (and not block you)")
	-- round 3 crumbles the rest
	toRound(p, 3)
	assert(model:GetAttribute("Pillars") == "1111", "round 3 should crumble every pillar")
	-- the throne toss: the throne stays where it lands
	E.throneThrown = false
	force(p, "ThroneToss", 14, false, 4)
	assert(M.typeof(model:GetAttribute("ThroneAt")) == "Vector3" and E.throneThrown, "the thrown throne should stay where it landed")
	-- a reset stands them all up again
	E.token += 1
	leave(p)
	runFor(8)
	assert(stateIs("Dormant") and model:GetAttribute("Pillars") == "0000" and model:GetAttribute("ThroneAt") == nil,
		"a reset should stand every pillar up and put the throne back")
	for _, part in ipairs(pm:GetChildren()) do
		if part.Name == "Column" and part.Transparency ~= 0 then
			problem("a pillar stood up again should show its column")
		end
	end
elseif SCENARIO == "final" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(p, 3)
	local f = def.Final
	local max = model:GetAttribute("MaxHealth")
	-- his health is held at the final gavel's line until it's played
	takeOver(p)
	model:SetAttribute("Health", math.floor(max * def.FinalAt) + 5)
	punchModel(p, model, 0.2)
	assert(model:GetAttribute("Health") >= math.floor(max * def.FinalAt), "his health should be held at FinalAt until the final gavel")
	local wasHeld = model:GetAttribute("Health")
	local standSpot = Vector3.new(CENTER.X, floorY + 3, CENTER.Z + 10)
	local n0 = #hitLog
	runFor(0.5, function(dt)
		place(p, standSpot, dt)
	end)
	assert(model:GetAttribute("Action") == "FinalGavel", "at FinalAt the final gavel should come")
	local untouched = model:GetAttribute("Invulnerable") == true
	runFor(f.Tell + 0.8, function(dt)
		place(p, standSpot, dt)
	end)
	local hitByFinal = 0
	for i = n0 + 1, #hitLog do
		if hitLog[i].action == "FinalGavel" or hitLog[i].action == "Worn" then
			hitByFinal += 1
		end
	end
	print(string.format("final gavel: untouchable while winding up %s, hits on a player standing still %d", tostring(untouched), hitByFinal))
	assert(untouched, "he should be untouchable while he winds up the final gavel")
	assert(hitByFinal >= 1, "the final gavel should hit a player standing still")
	assert(model:GetAttribute("Action") == "Worn", "after the final gavel he should be worn out")
	local _ = wasHeld
	-- jumping it: the same again (forced), hopping the whole time the wave goes by
	E.finalDone = false
	E.token += 1
	E.state = "Fighting"
	model:SetAttribute("State", "Fighting")
	model:SetAttribute("MinHealth", math.floor(max * def.FinalAt))
	E.pos = home
	local jumpSpot = Vector3.new(CENTER.X, floorY + 3, CENTER.Z + 30)
	local n1 = #hitLog
	runFor(f.Tell + 3, function(dt)
		local u = (M.now() % 0.6) / 0.6
		place(p, Vector3.new(jumpSpot.X, floorY + 3 + 3.5 + 1.5 * math.sin(math.pi * u), jumpSpot.Z), dt)
	end)
	local jumpedHits = 0
	for i = n1 + 1, #hitLog do
		if hitLog[i].action == "FinalGavel" or hitLog[i].action == "Worn" then
			jumpedHits += 1
		end
	end
	print(string.format("final gavel, jumping the shockwave: hit %d times", jumpedHits))
	assert(jumpedHits == 0, "jumping the final gavel's shockwave should dodge it")
	-- and he can be finished off
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 120)
	assert(stateIs("Dead"), "after the final gavel he should be beatable")
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
local propList = {}
for k, v in pairs(propsSeen) do
	table.insert(propList, k .. "=" .. v .. "/" .. (popped[k] or 0))
end
table.sort(propList)
print(string.format("time %.1f  state %s  round %s  punches %d  props seen/popped %s  pillars %s",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, table.concat(propList, " "),
	tostring(model:GetAttribute("Pillars"))))
print("hits on players: " .. table.concat(hitList, " ") .. string.format("  dodged %d  shoves %d", dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("furthest from the middle %.1f  reward power %d chests %s victories %d", maxOff, rewards.power, tostring(rewards.chests[10]), victories))
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
	print(string.format("most parts at once: %d", maxParts))
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
	needDrawn({ "Head", "BellyRoll", "Thigh", "HindFlipper", "Flipper", "Pauldron", "GavelHandle", "GavelHead", "GavelRune", "Cape",
		"Tusk", "Scar", "Muzzle", "Crown", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "KingWarning", "WedgeWarning", "GuardBody", "ToeGlow", "TaxCoin", "FallingCoin", "TornadoWarning", "GulpWarning",
			"LaneWarning", "GavelChain", "FeastPlatter", "RollBall", "SafeTile", "QuakeWarning", "LooseCrown", "Spotlight", "GiantGavel",
			"FlyingThrone", "GavelCore" })
		needWords({ "GUARDS!", "TAXES ARE DUE!", "GUILTY!", "STAND ON THE GOLD!" })
	elseif SCENARIO == "full" then
		needWords({ "THE MECHANICAL GAVEL", "NO ONE TAKES MY CROWN!", "THE FINAL GAVEL" })
		needDrawn({ "GavelCore", "FlyingCrown", "Lightning" })
	elseif SCENARIO == "entrance" then
		needWords({ "WHO DARES...", "HAR HAR HAR!", "KNEEL!", "PEASANTS. HMPH." })
		needDrawn({ "Lightning" })
	elseif SCENARIO == "toe" then
		needWords({ "OW! MY TOE!", "HIT HIM!" })
	elseif SCENARIO == "final" then
		needWords({ "THE FINAL GAVEL", "HIT HIM!" })
	end
end
if maxOff > def.Court + 0.6 then
	problem(string.format("he went %.1f from the middle (off the courtyard)", maxOff))
end
if SCENARIO == "full" or SCENARIO == "duo" or SCENARIO == "reset" then
	if not stateIs("Dead") and SCENARIO ~= "full" then
		problem("he should have been beaten")
	end
	if rewards.kills == 0 or rewards.power <= 0 then
		problem("beating him should pay Power")
	end
	if sawPhase < 3 then
		problem("round " .. (sawPhase + 1) .. " never came")
	end
	for _, name in ipairs({ "Wake", "Break", "Berserk", "FinalGavel", "Worn", "Death" }) do
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
