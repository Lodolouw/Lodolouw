--!nocheck
-- TUBER (floor 2) in the pretend Roblox: the real DunesBuilder desert, the
-- real BossService with Bosses/Tuber.lua (his own brain and step: little
-- Tuber, the power-up, then THE BRUTE and the cactus he plants), and (client
-- mode) the real BossClient drawing him with BossBodies/Tuber.lua on a
-- pretend player's screen. Pretend players circle little Tuber, chase the
-- Brute down, roll now and then, and punch whatever's nearest in reach - him
-- (using the shape his file gives CombatService: his split-up buddies, his
-- toppled body, the golem's trunk), or a wall's weak spot, a turret, a buddy.
--   luau test_tuber.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (both bars)
--   attacks  every move forced in turn (little Tuber's in round 1, the
--            Brute's in round 2), on a player standing where it reaches (each
--            must land) - then again on one who rolls through everything
--   reset    the player leaves mid round 2 (everything he planted goes, he's
--            little Tuber again, at home), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll as a hit lands dodges it, a
--            roll far too early gets you hit
--   powerup  the power-up: he can't be hurt and nothing hurts you while it
--            plays, round 1's mess is cleared, the Brute is big, and round 2
--            starts with him hopping away
--   split    SPLIT!: the three buddies share his health (punching any of them
--            hurts him), their rolling balls land, and they stack back up
--   props    his walls (burst up, prick, 2 punches on the weak spot), turrets
--            (shoot, 2 punches), buddies (pop, 1 punch), quicksand (nibbles) -
--            and breaking the last of them STUNS him
--   corner   catch him with his hop recharging: he panics (free hits), shoves
--            you off and escapes
-- It checks: no errors or warnings, no broken numbers, he stays in his
-- ground, no jumps, round 2 comes at PhaseAt, he dies, the reward (Power) is
-- paid - and, in client mode, that everything is drawn.
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
-- the world: the real Sunken Dunes
----------------------------------------------------------------------
local arena = mount.require(mount.module("ServerScriptService/DunesBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 2, "the dunes should be built as floor 2")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the dunes need an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the dunes need a way out (ArenaExit)")
assert(#CollectionService:GetTagged("DunePlatform") == 0, "no stone platforms any more (that was the worm's)")
local CENTER = arena:GetAttribute("Center")
local FIGHT_R = arena:GetAttribute("FightRadius") or 150
local ROCKS = {}
for _, rm in ipairs(CollectionService:GetTagged("DesertRock")) do
	local core = rm:FindFirstChild("RockCore") or rm.PrimaryPart
	if core and rm:GetAttribute("Floor") == 2 then
		table.insert(ROCKS, { center = Vector3.new(core.Position.X, 0, core.Position.Z), radius = rm:GetAttribute("Radius") or 5 })
	end
end
local CACTI = #CollectionService:GetTagged("DuneCactus")
local LOOKOUTS = #CollectionService:GetTagged("DuneLookout")

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
	p:SetAttribute("SpireFloor", 2)
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
		act = act .. "(quiet)"
	end
	local state = model and model:GetAttribute("State") or "?"
	if state ~= "Fighting" then
		problem(string.format("a hit landed while he was %s (at %.2f, doing %s)", state, T, tostring(act)))
	end
	hitsOn[act] = (hitsOn[act] or 0) + 1
	table.insert(hitLog, { t = M.now(), act = act, p = p, amount = amount })
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
local rewards = { power = 0, kills = 0 }
local Profile = {}
function Profile.RecordBossKill(p, floorId)
	rewards.kills += 1
	return true
end
function Profile.AddPower(p, n)
	rewards.power += n
end

for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 2 then
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
local E = assert(BS.Encounter(2), "Tuber should be built on floor 2")
model = E.model
local def = E.def
assert(def.Short == "Tuber", "floor 2's boss should be Tuber")
assert(shapes[model], "Tuber should give CombatService his body shape")
local Boss = E.boss
local home, floorY = E.home, E.floorY
assert(model:GetAttribute("Form") == "Stack", "he starts as little Tuber")
assert(#E.rocks == #ROCKS, "his file should find every rock in the dunes")

----------------------------------------------------------------------
-- client mode: his body on the first player's screen
----------------------------------------------------------------------
local drawn, guis = {}, {}
local rejoinApart, rejoinStray = false, 0
local maxParts = 0
local cactiMoved = 0
local cactusStart = {}
local shotsTaken = 0
local watchShots = 0
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
	-- (CombatClient's cutscene event: we count the camera shots it's asked for)
	local cut = Instance.new("BindableEvent")
	cut.Name = "CombatCutscene"
	cut.Parent = scripts
	cut.Event:Connect(function(kind, cf, fov)
		if kind == "Shot" then
			shotsTaken += 1
			if M.typeof(cf) ~= "CFrame" or (M.isNaNv and M.isNaNv(cf.Position)) then
				problem("a broken camera shot")
			end
			if fov ~= nil then
				-- (only the long look at the animals turning up zooms in)
				watchShots += 1
				if type(fov) ~= "number" or fov ~= fov or fov < 10 or fov > 60 then
					problem("a camera shot with a strange zoom: " .. tostring(fov))
				end
			end
		end
	end)
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.new(home + Vector3.new(0, 30, 70), home)
	cam.FieldOfView = 70
	cam.Parent = workspace
	workspace.CurrentCamera = cam
	for _, m in ipairs(CollectionService:GetTagged("DuneCactus")) do
		local hub = m.PrimaryPart
		if hub then
			cactusStart[m] = hub.CFrame
		end
	end
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
		-- (the power-up catching him split up: his buddies apart at first, then
		-- hopping back together onto the spot he stands on)
		if model:GetAttribute("Action") == "Break" then
			local e = M.now() - (model:GetAttribute("ActionStart") or M.now())
			local segs = {}
			for _, d in ipairs(fx:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Segment" and d.Transparency < 1 then
					table.insert(segs, d.CFrame.Position)
				end
			end
			local c = model:GetPivot().Position
			for i, a in ipairs(segs) do
				local far = Vector3.new(a.X - c.X, 0, a.Z - c.Z).Magnitude
				if e > 0.6 and e < 1.5 and far > 12.5 then -- (lying on his side he's 11 long)
					rejoinStray += 1
				end
				for j = i + 1, #segs do
					local b = segs[j]
					if e < 0.2 and Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude > 8 then -- (more than his flop spreads them)
						rejoinApart = true
					end
				end
			end
		end
	end
	-- (the arena's cacti flying off to him)
	for m, cf in pairs(cactusStart) do
		local hub = m.PrimaryPart
		if hub and (hub.Transparency >= 1 or (hub.CFrame.Position - cf.Position).Magnitude > 1) then
			cactiMoved += 1
			cactusStart[m] = nil
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
-- punching: the nearest thing in reach, the way CombatService does it (his
-- shape for him; a wall's weak spot, a turret, a buddy by their middles)
----------------------------------------------------------------------
local PUNCH_RANGE, PUNCH_EVERY = 8, 0.42
local lastPunch = {}
local punchesLanded, propPunches = 0, 0
local function targetsNow()
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged("CombatTarget")) do
		if m.Parent and (m:GetAttribute("Health") or 0) > 0 then
			table.insert(list, m)
		end
	end
	return list
end
local function aimOf(m, from)
	if shapes[m] then
		local ok, point, radius = pcall(shapes[m], from)
		if not ok or M.typeof(point) ~= "Vector3" then
			problem("a body shape failed: " .. tostring(point))
			return nil
		end
		return point, radius or m:GetAttribute("HitRadius") or 3
	end
	local pp = m.PrimaryPart
	return pp and pp.Position, m:GetAttribute("HitRadius") or 3
end
local function hitThing(p, m, damage)
	if m:GetAttribute("Invulnerable") then
		damage = 0
	end
	local floorHp = m:GetAttribute("MinHealth") or 0
	local before = m:GetAttribute("Health") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	m:SetAttribute("Health", math.max(0, hp))
	local onHit = m:FindFirstChild("OnHit")
	if onHit then
		onHit:Fire(p, damage, hp <= 0)
	end
	return damage
end
-- (share: of his health; props take `propShare` of the floor's recommended power a punch)
local REC = 436563
local function punch(p, share, only)
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return
	end
	local root = rootOf(p)
	local best, bestGap, bestPoint = nil, math.huge, nil
	for _, m in ipairs(targetsNow()) do
		if not only or m == only then
			local point, radius = aimOf(m, root.Position)
			if point then
				local gap = (Vector3.new(point.X, 0, point.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude - radius
				if gap <= PUNCH_RANGE and math.abs(point.Y - root.Position.Y) < 12 and gap < bestGap then
					best, bestGap, bestPoint = m, gap, point
				end
			end
		end
	end
	if not best then
		return
	end
	lastPunch[p] = T
	if best == model then
		local d = hitThing(p, model, math.max(1, math.floor((model:GetAttribute("MaxHealth") or 1) * share)))
		if d > 0 then
			punchesLanded += 1
		end
	else
		propPunches += 1
		hitThing(p, best, REC) -- (a punch at the recommended power)
	end
	local _ = bestPoint
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
	lastPos[p] = Vector3.new(pos.X, pos.Y, pos.Z)
end
local function moveToward(from, to, speed, dt)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude <= speed * dt then
		return Vector3.new(to.X, from.Y, to.Z)
	end
	return from + d.Unit * speed * dt
end
local function inRing(pos)
	local off = Vector3.new(pos.X - CENTER.X, 0, pos.Z - CENTER.Z)
	if off.Magnitude > FIGHT_R - 2 then
		off = off.Unit * (FIGHT_R - 2)
	end
	return Vector3.new(CENTER.X + off.X, pos.Y, CENTER.Z + off.Z)
end
local OPEN = { Cornered = true, Stunned = true }
-- A fighter: circles little Tuber at a distance that swells and shrinks;
-- chases the Brute (backing off now and then); rushes in when he's open;
-- rolls every few seconds and jumps every few more.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local act = model:GetAttribute("Action")
	local want
	if style ~= "far" and (OPEN[act] or ((model:GetAttribute("Phase") or 1) >= 2 and math.floor(phaseT / 6) % 3 ~= 2)) then
		local out = Vector3.new(base.X - center.X, 0, base.Z - center.Z)
		out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, 1)
		want = center + out * 9
	end
	if not want then
		local r = (style == "far") and (40 + 8 * math.sin(phaseT * 0.4)) or (8 + 20 * (1 + math.sin(phaseT * 0.31)))
		local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
		local ang = phaseT * 0.6 * spin + k * 2
		want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 20
	local nextPos = inRing(moveToward(base, want, speed, dt))
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
local formsSeen = {}
local maxOut = 0
local sawPhase2 = false
local maxSpeed = 0
local lastP = nil
local skipSpeed = false
local wasSplit = false
local propsSeen = {}
local maxProps = 0
local function watch(dt)
	local act = model:GetAttribute("Action")
	if act and not seen[act] then
		seen[act] = true
		table.insert(order, act)
	end
	formsSeen[model:GetAttribute("Form") or "?"] = true
	if (model:GetAttribute("Phase") or 1) >= 2 then
		sawPhase2 = true
	end
	local pos = model:GetPivot().Position
	if M.isNaNv and M.isNaNv(pos) then
		problem("his position is broken at " .. string.format("%.2f", T))
	end
	local st = model:GetAttribute("State")
	if not E.split then
		maxOut = math.max(maxOut, Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude)
	end
	local splitNow = E.split ~= nil
	if skipSpeed or (wasSplit and not splitNow) then
		-- (the test moved him - or his buddies were cut short and hop back
		-- together: his body jumps to where they'll meet, and the hop is drawn)
		skipSpeed = false
	elseif lastP and dt > 0 and st ~= "Resetting" and st ~= "Dormant" and st ~= "Dead" then
		-- (a spin-dashing buddy is quick: 50 studs a second; a hop covers ~60 in 1.35s)
		local v = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(lastP.X, 0, lastP.Z)).Magnitude / dt
		maxSpeed = math.max(maxSpeed, v)
		if v > 120 then
			problem(string.format("he moved %.0f studs/s at %.2f (a jump?) doing %s", v, T, tostring(act)))
		end
	end
	lastP = pos
	wasSplit = splitNow
	local folder = workspace:FindFirstChild("TuberProps")
	if folder then
		local n = 0
		for _, c in ipairs(folder:GetChildren()) do
			propsSeen[c:GetAttribute("Kind") or "?"] = true
			if not c:GetAttribute("EndKind") then
				n += 1
			end
			if c:GetAttribute("Kind") == "Buddy" and c.PrimaryPart then
				local bp = c.PrimaryPart.Position
				if Vector3.new(bp.X - CENTER.X, 0, bp.Z - CENTER.Z).Magnitude > FIGHT_R then
					problem("a buddy walked out of the arena")
				end
			end
		end
		maxProps = math.max(maxProps, n)
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
			print(string.format("  t=%6.1f phase=%d hp=%.2f act=%s form=%s", T, E.phase,
				(model:GetAttribute("Health") or 0) / math.max(model:GetAttribute("MaxHealth") or 1, 1), tostring(model:GetAttribute("Action")),
				tostring(model:GetAttribute("Form"))))
		end
	end
end
local function runFor(seconds, each)
	tick(math.floor(seconds / DT + 0.5), each)
end
local function stateIs(s)
	return model:GetAttribute("State") == s
end
local share = 1 / 90
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
-- stops his brain (a new token), everything he'd planted gone, and puts him
-- at `pos` in `form` ("Stack" or "Brute"), standing still
local function takeOver(pos, form)
	local waited = 0
	while not stateIs("Fighting") and waited < 20 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	Boss._tidy(E, "Gone")
	E.waves, E.puddles = {}, {}
	if form then
		Boss._setForm(E, form)
	end
	if pos then
		E.pos = Vector3.new(pos.X, floorY, pos.Z)
		E.facing = Vector3.new(1, 0, 0)
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
-- round 2 for real: punched down to PhaseAt, the whole power-up played out
local function reachRound2(p)
	fightUntil({ p }, function()
		return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
	end, 600)
	assert(E.phase == 2 and model:GetAttribute("Form") == "Brute", "the power-up should make him the Brute")
end

-- where each move is forced from: him a little west of the middle (clear of
-- the rocks), the player `spot` studs from him (x ahead, z to the side)
local START = CENTER + Vector3.new(-20, 0, 6)
local SPOTS = {
	Bonk = Vector3.new(6, 0, 0),
	Topple = Vector3.new(8, 0, 0),
	Sneeze = Vector3.new(10, 0, 0),
	Stomp = Vector3.new(20, 0, 0),
	Split = Vector3.new(30, 0, 0),
	Volley = Vector3.new(30, 0, 0),
	Rain = Vector3.new(30, 0, 0),
	Lance = Vector3.new(40, 0, 0),
	Wall = Vector3.new(34, 0, 0),
	Turrets = Vector3.new(30, 0, 0),
	Herd = Vector3.new(30, 0, 0),
	Buddies = Vector3.new(18, 0, 0),
	Quicksand = Vector3.new(30, 0, 0),
}
-- (moves that don't hurt by themselves: the cactus they plant does - see "props")
local PLANTS = { Wall = true, Turrets = true, Buddies = true, Quicksand = true }

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1500)
	runFor(8)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, asleep")
	assert(model:GetAttribute("Form") == "Stack", "home again he should be little Tuber")
elseif SCENARIO == "duo" then
	local a = people[1] or makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1003)
	walkIn(a)
	walkIn(b)
	fightUntil({ a, b }, function()
		return stateIs("Dead")
	end, 1500)
	runFor(4)
elseif SCENARIO == "reset" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	reachRound2(p)
	fightUntil({ p }, function()
		local folder = workspace:FindFirstChild("TuberProps")
		return folder and #folder:GetChildren() > 0
	end, 120)
	leave(p)
	runFor(9)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	local pos = model:GetPivot().Position
	assert(Vector3.new(pos.X - home.X, 0, pos.Z - home.Z).Magnitude < 0.5, "he should be back in his garden after a reset")
	assert(model:GetAttribute("Form") == "Stack", "after a reset he should be little Tuber again")
	assert(model:GetAttribute("Phase") == 1, "after a reset he should be on his first bar")
	local folder = workspace:FindFirstChild("TuberProps")
	assert(folder and #folder:GetChildren() == 0, "everything he planted should be gone after a reset")
	assert(#E.shots == 0 and #E.drops == 0 and #E.propList == 0, "nothing he threw should be left")
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 1500)
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
	local function force(name, dodge, form)
		local token = takeOver(START, form)
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
			rollUntil[p] = T + 13
		end
		runFor(12, function(dt)
			place(p, START + Vector3.new(o.X, 3, o.Z), dt) -- (standing still, where it reaches)
		end)
		rollUntil[p] = nil
		return since(m0), dodges - d0
	end
	local report = {}
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			takeOver(START, "Stack")
			M.task.spawn(function()
				Boss.brain(E, E.token)
			end)
			reachRound2(p)
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if (a.Phase or 1) == phase then
				local form = (phase == 2) and "Brute" or "Stack"
				local landedN = force(name, false, form)
				local _, dodged = force(name, true, form)
				table.insert(report, string.format("round %d %s hit=%d dodged=%d", phase, name, landedN, dodged))
				if not PLANTS[name] then
					if landedN == 0 then
						problem(name .. " (round " .. phase .. ") never hit a player standing where it reaches")
					end
					if dodged == 0 then
						problem(name .. " (round " .. phase .. ") couldn't be rolled through")
					end
				end
			end
		end
	end
	-- and his moves that aren't picked at random
	local function forceMove(name, o, wantHit)
		local token = takeOver(START, "Brute")
		E.target, E.targetSince = p, M.now()
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0 = mark()
		M.task.spawn(function()
			local ok, err = pcall(Boss.Moves[name], E, token)
			if not ok then
				problem("forced " .. name .. " errored: " .. tostring(err))
			end
		end)
		runFor(6, function(dt)
			place(p, START + Vector3.new(o.X, 3, o.Z), dt)
		end)
		table.insert(report, string.format("move %s hit=%d", name, since(m0)))
		if wantHit and since(m0) == 0 then
			problem(name .. " never hit a player standing where it reaches")
		end
	end
	forceMove("ShoveBurst", Vector3.new(6, 0, 0), true)
	forceMove("Rage", Vector3.new(20, 0, 0), true)
	forceMove("Stunned", Vector3.new(20, 0, 0), false)
	forceMove("RootHop", Vector3.new(8, 0, 0), false)
	print(table.concat(report, "\n"))
elseif SCENARIO == "timing" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	-- force `move` (from `table`, in `form`), the player standing at `o`; roll
	-- at (its hit - `before`) seconds, the hit `hitAfter` seconds after the
	-- move starts; did it land?
	local function case(tbl, move, form, o, hitAfter, before, wantDodge, label)
		local token = takeOver(START, form)
		E.target, E.targetSince = p, M.now()
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		local m0, d0 = mark()
		M.task.spawn(function()
			tbl[move](E, token)
		end)
		tick(1)
		local t0 = model:GetAttribute("ActionStart") or M.now()
		local hitAt = t0 + hitAfter
		local rollAt = hitAt - before
		local rolled = false
		while M.now() < hitAt + 0.6 do
			tick(1, function(dt)
				place(p, START + Vector3.new(o.X, 3, o.Z), dt)
			end)
			if not rolled and M.now() >= rollAt then
				rolled = true
				rollUntil[p] = M.now() + 0.5
			end
		end
		rollUntil[p] = nil
		local landedHit = since(m0) > 0
		local dodged = dodges > d0 and not landedHit
		print(string.format("%-18s roll %.2fs before it hits: %s", label, before, landedHit and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landedHit then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver()
		runFor(2)
	end
	local A, Mv = def.Attacks, def.Moves
	case(Boss.Attacks, "Bonk", "Stack", SPOTS.Bonk, A.Bonk.Tell, 0.1, true, "bonk late")
	case(Boss.Attacks, "Bonk", "Stack", SPOTS.Bonk, A.Bonk.Tell, 0.9, false, "bonk early")
	case(Boss.Attacks, "Topple", "Stack", SPOTS.Topple, A.Topple.Tell + A.Topple.Fall, 0.1, true, "topple late")
	case(Boss.Attacks, "Topple", "Stack", SPOTS.Topple, A.Topple.Tell + A.Topple.Fall, 0.9, false, "topple early")
	case(Boss.Attacks, "Stomp", "Stack", SPOTS.Stomp, A.Stomp.Crouch + A.Stomp.Air, 0.1, true, "stomp late")
	case(Boss.Attacks, "Stomp", "Stack", SPOTS.Stomp, A.Stomp.Crouch + A.Stomp.Air, 0.9, false, "stomp early")
	case(Boss.Moves, "ShoveBurst", "Brute", Vector3.new(6, 0, 0), Mv.ShoveBurst.Tell, 0.1, true, "shove burst late")
	case(Boss.Moves, "ShoveBurst", "Brute", Vector3.new(6, 0, 0), Mv.ShoveBurst.Tell, 0.9, false, "shove burst early")
	-- (the rain's first ball lands on where you were: Spit + Fall)
	case(Boss.Attacks, "Rain", "Brute", SPOTS.Rain, A.Rain.Spit + A.Rain.Fall, 0.1, true, "desert rain late")
	case(Boss.Attacks, "Rain", "Brute", SPOTS.Rain, A.Rain.Spit + A.Rain.Fall, 0.9, false, "desert rain early")
	-- (the lance flies: from 7 studs in front of him to you at its speed)
	local lanceHit = A.Lance.Charge + (SPOTS.Lance.X - 7) / A.Lance.Speed
	case(Boss.Attacks, "Lance", "Brute", SPOTS.Lance, lanceHit, 0.1, true, "spine lance late")
	case(Boss.Attacks, "Lance", "Brute", SPOTS.Lance, lanceHit, 0.9, false, "spine lance early")
elseif SCENARIO == "powerup" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	-- a mess of round-1 things flying about when the power-up hits: a sneeze
	-- ring, and him split up mid-dash
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	local token = takeOver(START, "Stack")
	E.target, E.targetSince = p, M.now()
	place(p, START + Vector3.new(30, 3, 0), 0)
	M.task.spawn(function()
		Boss.Attacks.Split(E, token)
	end)
	runFor(2.5)
	assert(E.split, "he should be split up")
	-- punch his first bar away in one go (the phase shield holds it at the line)
	local max = model:GetAttribute("MaxHealth")
	local near = E.buddyPos[1]
	place(p, Vector3.new(near.X + 3, floorY + 3, near.Z), 0)
	local d = hitThing(p, model, max)
	assert(d > 0, "punching a buddy should hurt him")
	assert(model:GetAttribute("Health") == math.floor(max * def.PhaseAt), "one huge hit should stop at the line between the bars")
	tick(1)
	assert(stateIs("Transition") or model:GetAttribute("Phase") == 2, "the power-up should start at the line")
	assert(model:GetAttribute("Form") == "Brute", "he should become the Brute as it starts")
	assert(not E.split, "he should be one again when the power-up starts")
	assert(#E.shots == 0 and #E.waves == 0, "round 1's rolling balls and rings should be gone")
	-- nothing hurts anyone while it plays, and he can't be hurt
	local m0 = mark()
	local hpAt = model:GetAttribute("Health")
	local t0 = T
	while T - t0 < def.BreakTime - 0.2 do
		tick(1)
		hitThing(p, model, max * 0.1)
	end
	assert(model:GetAttribute("Health") == hpAt, "he can't be hurt during the power-up")
	assert(since(m0) == 0, "nothing should hurt anyone during the power-up")
	assert(shoves > 0, "the golem standing up should throw people back")
	assert(model.PrimaryPart.Size.Y >= def.Brute.Height - 0.01, "the Brute's body should be golem-sized (for the lock-on camera)")
	runFor(1.5)
	assert(stateIs("Fighting"), "round 2 should start after the power-up")
	assert(model:GetAttribute("Action") == "RootHop", "round 2 should open with him hopping away")
elseif SCENARIO == "split" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 90)
	local token = takeOver(START, "Stack")
	E.target, E.targetSince = p, M.now()
	local o = SPOTS.Split
	place(p, START + Vector3.new(o.X, 3, o.Z), 0)
	local m0 = mark()
	M.task.spawn(function()
		Boss.Attacks.Split(E, token)
	end)
	local a = def.Attacks.Split
	runFor(a.Shake + a.Pop + 0.1, function(dt)
		place(p, START + Vector3.new(o.X, 3, o.Z), dt)
	end)
	assert(E.split and E.buddyPos, "SPLIT! should split him into three")
	local distinct = (E.buddyPos[1] - E.buddyPos[2]).Magnitude > 3 and (E.buddyPos[2] - E.buddyPos[3]).Magnitude > 3
	assert(distinct, "the three buddies should be apart")
	-- they share his health: punch the bottom one
	local b1 = E.buddyPos[1]
	local before = model:GetAttribute("Health")
	local pb = makePlayer("Puncher", 1005)
	enter(pb)
	place(pb, Vector3.new(b1.X + 3, floorY + 3, b1.Z), 0)
	punch(pb, 0.01)
	assert(model:GetAttribute("Health") < before, "punching a buddy should hurt him (they share his health)")
	leave(pb)
	runFor(12, function(dt)
		place(p, START + Vector3.new(o.X, 3, o.Z), dt)
	end)
	assert(since(m0) > 0, "a spin-dashing buddy should hit a player standing in its lane")
	assert(not E.split, "they should stack back up")
	local rally = model:GetPivot().Position
	assert(Vector3.new(rally.X - home.X, 0, rally.Z - home.Z).Magnitude <= def.Leash + 0.5, "he should stack up inside his ground")
elseif SCENARIO == "props" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	reachRound2(p)
	local folder = workspace:FindFirstChild("TuberProps")
	local function kids(kind)
		local list = {}
		for _, c in ipairs(folder:GetChildren()) do
			if c:GetAttribute("Kind") == kind and not c:GetAttribute("EndKind") then
				table.insert(list, c)
			end
		end
		return list
	end
	local function forcePlant(name, o)
		local token = takeOver(START, "Brute")
		E.target, E.targetSince = p, M.now()
		place(p, START + Vector3.new(o.X, 3, o.Z), 0)
		M.task.spawn(function()
			Boss.Attacks[name](E, token)
		end)
		return token
	end
	-- A WALL: bursts up between him and you, pricks you if you touch it,
	-- and its weak spot takes two punches (however hard you hit)
	forcePlant("Wall", SPOTS.Wall)
	runFor(0.4)
	local walls = kids("Wall")
	assert(#walls == 1, "the cactus wall should be planted")
	local wall = walls[1]
	assert(not CollectionService:HasTag(wall, "CombatTarget"), "a wall can't be punched before it bursts up")
	runFor(1.2)
	assert(CollectionService:HasTag(wall, "CombatTarget"), "a wall can be punched once it's up")
	local block = nil
	for _, c in ipairs(wall:GetChildren()) do
		if string.sub(c.Name, 1, 5) == "Block" then
			block = c
		end
	end
	assert(block and block.CanCollide, "a wall's blocks should be solid once it's up")
	-- stand right against it: pricked
	local m0 = mark()
	local wp = wall.PrimaryPart.Position
	place(p, Vector3.new(wp.X, floorY + 3, wp.Z) + (START - wp).Unit * 2.4, 0)
	runFor(1.2, function(dt)
		place(p, Vector3.new(wp.X, floorY + 3, wp.Z) + Vector3.new((START - wp).X, 0, (START - wp).Z).Unit * 2.4, dt)
	end)
	assert(since(m0) > 0, "touching a cactus wall should prick you")
	local hp0 = wall:GetAttribute("MaxHealth")
	hitThing(p, wall, hp0 * 10) -- (a monstrous punch)
	assert((wall:GetAttribute("Health") or 0) > 0, "a wall's weak spot should take two punches, however hard you hit")
	hitThing(p, wall, hp0 * 10)
	runFor(0.2)
	assert(wall:GetAttribute("EndKind") == "Broken", "two punches should break the wall")
	assert(not block.CanCollide, "a broken wall shouldn't block you")
	-- BUDDIES: they hop off him, waddle after you, and pop
	forcePlant("Buddies", SPOTS.Buddies)
	runFor(1.2)
	local buddies = kids("Buddy")
	assert(#buddies >= 1, "prickly buddies should hop off him")
	local m2 = mark()
	local b0 = buddies[1].PrimaryPart.Position
	runFor(4, function(dt)
		place(p, START + Vector3.new(SPOTS.Buddies.X, 3, 0), dt)
	end)
	local moved = (buddies[1].PrimaryPart.Position - b0).Magnitude
	assert(moved > 3 or since(m2) > 0, "a buddy should waddle after you")
	assert(since(m2) > 0, "a buddy that reaches you should pop and hit you")
	-- QUICKSAND: nibbles at you, quietly
	forcePlant("Quicksand", SPOTS.Quicksand)
	runFor(1.4)
	local sands = kids("Sand")
	assert(#sands >= 1, "quicksand should open up")
	local c = sands[1]:GetAttribute("C")
	local m3 = mark()
	runFor(2, function(dt)
		place(p, Vector3.new(c.X, floorY + 3, c.Z), dt)
	end)
	local quiet = 0
	for i = m3 + 1, #hitLog do
		if string.find(hitLog[i].act, "(quiet)", 1, true) then
			quiet += 1
		end
	end
	assert(quiet > 0, "standing in quicksand should nibble at you")
	-- TURRETS: they grow, shoot the nearest player, and break in two punches
	forcePlant("Turrets", SPOTS.Turrets)
	runFor(2)
	local turrets = kids("Turret")
	assert(#turrets >= 1, "needle turrets should sprout")
	local m1 = mark()
	runFor(5, function(dt)
		place(p, START + Vector3.new(SPOTS.Turrets.X, 3, 0), dt)
	end)
	assert(since(m1) > 0, "a needle turret should hit a player standing in the open")
	for _, tu in ipairs(turrets) do
		assert(tu:GetAttribute("ShotId") and tu:GetAttribute("ShotId") > 0, "each turret should have fired")
	end
	-- break all but one (the stun is for breaking the LAST of them)
	for i = 2, #turrets do
		local tu = turrets[i]
		local mh = tu:GetAttribute("MaxHealth")
		hitThing(p, tu, mh)
		hitThing(p, tu, mh)
	end
	runFor(0.2)
	-- THE STUN: break the last turret: he's out of cactus (his brain back on,
	-- his turret left standing)
	E.token += 1
	local brainToken = E.token
	M.task.spawn(function()
		Boss.brain(E, brainToken)
	end)
	local last = turrets[1]
	local mh = last:GetAttribute("MaxHealth")
	hitThing(p, last, mh)
	hitThing(p, last, mh)
	assert(E.pendingStun, "breaking the last of his walls and turrets should stun him")
	runFor(6, function(dt)
		place(p, START + Vector3.new(40, 3, 0), dt)
	end)
	assert(seen.Stunned, "he should be STUNNED")
elseif SCENARIO == "corner" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	reachRound2(p)
	-- let his first hop happen, then run straight at him
	takeOver()
	M.task.spawn(function()
		Boss.brain(E, E.token)
	end)
	E.hopReadyAt = M.now() + 30 -- (his hop is recharging)
	E.corneredReadyAt = 0
	local c = model:GetPivot().Position
	local h0 = model:GetAttribute("Health")
	place(p, Vector3.new(c.X + 10, floorY + 3, c.Z), 0)
	local cornered, punchedWhile = false, 0
	local t0 = T
	while T - t0 < 8 do
		tick(1, function(dt)
			local cc = model:GetPivot().Position
			place(p, Vector3.new(cc.X + 10, floorY + 3, cc.Z), dt)
			if model:GetAttribute("Action") == "Cornered" then
				cornered = true
				local before = punchesLanded
				punch(p, 0.005)
				punchedWhile += punchesLanded - before
			end
		end)
	end
	assert(cornered, "catching him with his hop recharging should corner him")
	assert(punchedWhile >= 3, "a cornered Brute should take free hits")
	assert(model:GetAttribute("Health") < h0, "the free hits should hurt him")
	assert(seen.ShoveBurst and seen.RootHop, "then he should shove you off and hop away")
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
local props = {}
for k in pairs(propsSeen) do
	table.insert(props, k)
end
table.sort(props)
print(string.format("time %.1f  state %s  phase %s  punches %d (props %d)  hits on players: %s  dodged %d  shoves %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, propPunches, table.concat(hitList, " "), dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("arena: %d rocks, %d cacti, %d lookouts  props seen: %s (most at once %d)  furthest from home %.1f (leash %d)  fastest %.0f studs/s  reward power %d  victories %d",
	#ROCKS, CACTI, LOOKOUTS, table.concat(props, " "), maxProps, maxOut, def.Leash, maxSpeed, rewards.power, victories))
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
	print(string.format("most parts at once: %d  cacti flown: %d/%d  camera shots: %d (at the animals %d)", maxParts, cactiMoved, CACTI, shotsTaken, watchShots))
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
	-- (little Tuber, every time)
	needDrawn({ "Segment", "Lump", "Spine", "Eye", "Blush", "Mouth", "FlowerHeart", "FlowerPetal", "Arm", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "WedgeSpoke", "WedgeEdge", "Lane", "Circle", "RingPiece", "BuddyEye", "BruteHead", "BruteFist", "BruteCrown",
			"BruteRoot", "Needle", "RainBall", "SpineLance", "SpineLanceTip", "CactusBall", "BallSpike", "WallCactus",
			"WallWeakSpot", "WallWarning", "TurretBody", "TurretEye", "BuddyBody", "Quicksand", "DizzyStar" })
		needWords({ "BONK!", "ACHOO!", "SPLIT!", "WHOA...", "RAGE!" })
	elseif SCENARIO == "full" or SCENARIO == "powerup" then
		needDrawn({ "BruteHead", "BruteChest", "BruteEye", "BruteCrown", "BruteCrownSpike", "BruteFlowerPetal", "BruteRoot" })
		needWords({ "THE", "THE CACTUS KING", "THE DESERT BOWS", "B", "R", "U", "T", "E" })
		if shotsTaken == 0 then
			problem("the power-up should swing the camera round him (kit.shot)")
		end
		if LOOKOUTS > 0 and watchShots == 0 then
			problem("the power-up should look out at the animals turning up")
		end
		if CACTI > 0 and cactiMoved < CACTI * 0.5 then
			problem(string.format("the arena's cacti should fly to him in the power-up (%d of %d did)", cactiMoved, CACTI))
		end
		if LOOKOUTS > 0 then
			needDrawn({ "WatcherBody", "WatcherHead" })
		end
		if SCENARIO == "full" then
			needWords({ "HI THERE!" })
		end
		if SCENARIO == "powerup" then
			if not rejoinApart then
				problem("split up when the power-up hit, his buddies should hop back together (never saw them apart)")
			end
			if rejoinStray > 0 then
				problem(string.format("his buddies should be back together by now (%d frames with one far away)", rejoinStray))
			end
		end
	elseif SCENARIO == "props" then
		needDrawn({ "WallCactus", "WallWeakSpot", "WallWarning", "TurretBody", "TurretEye", "TurretSpine", "Needle", "BuddyBody",
			"BuddyEye", "Quicksand" })
		needWords({ "OUT OF CACTUS!", "HIT HIM!" })
	elseif SCENARIO == "corner" then
		needWords({ "!!", "HIT HIM!" })
	elseif SCENARIO == "split" then
		needDrawn({ "BuddyEye", "Lane" })
		needWords({ "SPLIT!", "DIZZY! HIT THEM!" })
	end
end
if maxOut > def.Leash + 6 then
	problem(string.format("he went %.1f from home (leash %d)", maxOut, def.Leash))
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
	for _, name in ipairs({ "Wake", "Break", "Death", "RootHop" }) do
		if not seen[name] then
			problem("never saw " .. name)
		end
	end
	if not formsSeen.Brute then
		problem("he never became the Brute")
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
