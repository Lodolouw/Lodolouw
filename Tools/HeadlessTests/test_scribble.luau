--!nocheck
-- SCRIBBLE (floor 9) in the pretend Roblox: the real CanvasBuilder arena, the
-- real BossService with Bosses/Scribble.lua, and (client mode) the real
-- BossClient drawing him with BossBodies/Scribble.lua on a pretend player's
-- screen. Pretend players circle him, roll now and then, jump now and then,
-- punch him whenever he's in reach, pop his ink clones and the Z key, and in
-- round 3 run to punch the DELETE box's NO button.
--   luau test_scribble.luau -a <scenario> [seed] [server|client]
-- scenarios:
--   full     one player fights him to the death (all three rounds)
--   attacks  every move forced in turn, in each round it's used in, on a
--            player who stands still where it reaches (so each one's hit is
--            seen to land) - then again on one who rolls (dodged)
--   reset    the player leaves mid-fight in round 3 (he resets, the paper
--            comes back whole, every prop goes), then comes back and wins
--   duo      two players; the second keeps its distance
--   timing   the dodge windows are fair: a roll just before a hit dodges it,
--            a roll too early gets you hit
--   undo     the Z key: broken in time he's stunned (and punches on him
--            land); left alone, "CTRL+Z" gives him back your last hits
--   delete   round 3: the DELETE box pops up; punching NO crashes him (it
--            costs him health, he's open, the paper comes back); left alone,
--            the delete hits hard (never kills) and the paper shrinks, and
--            standing on erased paper stings
--   whip     the Boss Bar Whip: standing still it hits you, jumping over it
--            it doesn't
--   clones   COPY-PASTE: the clones chase and slash, a punch or two pops
--            one, and left alone they smudge away
-- It checks: no errors or warnings, no broken numbers, he stays on the
-- paper, every move is seen (and draws its warnings, in client mode), round
-- 2 comes at PhaseAt and round 3 at Round3At, he dies, the reward (Power) is
-- paid - and floor 9 has no loot (it's waiting for the loot rework).
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
-- the world: the real canvas
----------------------------------------------------------------------
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Items = mount.require(mount.module("ReplicatedStorage/Items.lua"))
local CanvasPlan = mount.require(mount.module("ReplicatedStorage/CanvasPlan.lua"))
local arena = mount.require(mount.module("ServerScriptService/CanvasBuilder.lua")).Build()
M.run(1)
assert(arena and arena:GetAttribute("Floor") == 9, "the canvas should be built as floor 9")
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
assert(spawnPart, "the canvas needs an ArenaSpawn")
assert(#CollectionService:GetTagged("ArenaExit") == 1, "the canvas needs a way out (ArenaExit)")
assert(#CollectionService:GetTagged("CanvasEdgeWall") >= 4, "the paper needs walls round it")
assert(typeof(arena:GetAttribute("Bin")) == "Vector3" or M.typeof(arena:GetAttribute("Bin")) == "Vector3", "the arena should say where the recycle bin is")
local HALF = arena:GetAttribute("FightRadius")
assert(HALF == CanvasPlan.Half, "the arena's paper should be CanvasPlan's size")
-- (no loot yet: floor 9's chest is waiting for the loot rework)
assert(Items.ByFloor[9] == nil, "floor 9 shouldn't have any loot yet")
do
	local c = arena:GetAttribute("Center")
	local off = spawnPart.Position - c
	assert(CanvasPlan.onPaper(off.X, off.Z, HALF), "you should arrive on the paper")
	-- the paint bucket's squares tile the paper exactly
	local x, z = CanvasPlan.cellOf(3, -7)
	assert(x == 10 and z == -10, "cellOf should give the middle of the square a spot is in")
	x, z = CanvasPlan.cellOf(59, -59)
	assert(x == 50 and z == -50, "the squares at the edge should be the edge ones")
	-- the DELETE box's NO button is on your right as you face the box
	for side = 1, 4 do
		local base, face, no, yes = CanvasPlan.promptSpots(side, 40)
		local right = Vector3.new(face.Z, 0, -face.X) -- (to your right, looking at the box: you look along -face)
		assert((no - base):Dot(right) > 0 and (yes - base):Dot(right) < 0, "NO should be on the right, YES on the left")
		assert(CanvasPlan.onPaper(no.X, no.Z, 40), "the NO button should be on the paper that's left")
	end
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
	p:SetAttribute("SpireFloor", 9)
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
local bigHits = {} -- { amount, healthBefore }
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
	if quiet then
		quietHits += 1
	end
	local hum = humOf(p)
	if hum then
		table.insert(bigHits, { amount = amount, before = hum.Health })
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
local E = assert(BS.Encounter(9), "Scribble should be built on floor 9")
model = E.model
local def = E.def
assert(def.Short == "Scribble", "floor 9's boss should be Scribble")
local Boss = E.boss
local home, floorY = E.home, E.floorY
assert(shapes[model], "he should tell CombatService where his body is (SetTargetShape)")
assert(model:GetAttribute("Paper") == HALF, "the paper should start whole")

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
-- the props in reach (clones, the Z key, the NO button): one punch at the
-- recommended power does 1 / Punches of it
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
local PROP_SHARE = 1 / 1.4 -- (a little under a full prop's health a punch: the Z key and clones take 2, NO takes 3... ish)
local function punch(p, share, propsFirst)
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return false
	end
	local root = rootOf(p)
	if propsFirst ~= false then
		local prop = propInReach(root)
		if prop then
			lastPunch[p] = T
			local rec = (prop:GetAttribute("MaxHealth") or 1)
			local kind = prop:GetAttribute("Kind")
			-- a punch at the recommended power: MaxHealth / Punches of it
			local punches = (kind == "NoButton" and def.Delete.NoPunches) or (kind == "UndoKey" and def.Attacks.Undo.Punches)
				or def.Attacks.CopyPaste.Punches
			local _, killed = punchModel(p, prop, 1 / punches + 1e-6)
			if killed then
				popped[kind] = (popped[kind] or 0) + 1
			end
			local _ = rec
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
-- keep on the paper, like the real invisible walls do (and a sensible
-- player keeps off the erased edge)
local function onPaper(pos)
	local half = math.min(HALF - 1, CanvasPlan.paperNow(model, M.now()) - 1)
	local off = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	return Vector3.new(home.X + math.clamp(off.X, -half, half), pos.Y, home.Z + math.clamp(off.Z, -half, half))
end
local function bossPos()
	return E.pos
end
local function noButton()
	local folder = workspace:FindFirstChild("ScribbleProps")
	for _, t in ipairs(folder and folder:GetChildren() or {}) do
		if t:GetAttribute("Kind") == "NoButton" and not t:GetAttribute("EndKind") then
			return t
		end
	end
	return nil
end

-- A fighter: circles him at a distance that swells and shrinks (in close to
-- punch, out where he throws things), changes direction now and then, rolls
-- every few seconds and jumps every few more. In round 3, when a DELETE box
-- is up, it runs to the NO button and punches it.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local b = bossPos()
	local r = (style == "far") and (30 + 8 * math.sin(phaseT * 0.4)) or (4 + 14 * (1 + math.sin(phaseT * 0.31)))
	local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
	local ang = phaseT * 0.6 * spin + k * 2
	local want = Vector3.new(b.X + math.cos(ang) * r, 0, b.Z + math.sin(ang) * r)
	local box = style ~= "far" and noButton()
	if box then
		local c = box:GetPivot().Position
		local mid = Vector3.new(home.X, 0, home.Z)
		local inward = Vector3.new(mid.X - c.X, 0, mid.Z - c.Z)
		inward = inward.Magnitude > 0.1 and inward.Unit or Vector3.new(0, 0, 1)
		want = Vector3.new(c.X, 0, c.Z) + inward * 3
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 18
	local nextPos = onPaper(moveToward(base, want, speed, dt))
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
local boxesSeen, pressed, yeses = 0, 0, 0
local lowestPaper = HALF
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
	local off = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	maxOff = math.max(maxOff, math.abs(off.X), math.abs(off.Z))
	lowestPaper = math.min(lowestPaper, model:GetAttribute("Paper") or HALF)
	local folder = workspace:FindFirstChild("ScribbleProps")
	for _, t in ipairs(folder and folder:GetChildren() or {}) do
		local id = t:GetAttribute("Id")
		local kind = t:GetAttribute("Kind")
		if id and not propIds[id] then
			propIds[id] = true
			propsSeen[kind] = (propsSeen[kind] or 0) + 1
			if kind == "NoButton" then
				boxesSeen += 1
			end
		end
		if kind == "NoButton" and not propIds["end" .. id] then
			local ek = t:GetAttribute("EndKind")
			if ek then
				propIds["end" .. id] = true
				if ek == "Pressed" then
					pressed += 1
				elseif ek == "Yes" then
					yeses += 1
				end
			end
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
-- each punch takes this much of his health (a punch at the recommended level)
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
-- stops his brain (a new token), clears his props, puts him back in the
-- middle facing south - so a forced move starts from a known place
local function takeOver(p)
	local waited = 0
	while not stateIs("Fighting") and waited < 10 do
		runFor(0.5)
		waited += 0.5
	end
	E.token += 1
	E.motion, E.sweep = nil, nil
	for _, c in ipairs(E.clones) do
		c.dieAt = 0
	end
	E.zones = {}
	if E.prompt then
		E.prompt.untilT = math.huge -- (a box left up stays up, harmless, until the scenario deals with it)
	end
	E.pos = home
	E.facing = Vector3.new(0, 0, 1)
	E.target, E.targetSince = p, M.now()
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
		runFor(def.GlitchTime + 0.4)
		assert(E.phase == 3 and stateIs("Fighting"), "round 3 should come at Round3At")
	end
end

-- where each move is forced from: the player this far in front of him (south)
local SPOTS = {
	PencilDash = 20, EraserSweep = 18, PaintBucket = 18, CopyPaste = 10, Undo = 12,
	Cursor = 18, BarWhip = 14, ErrorPopups = 18, LagSpike = 20,
}
local HARMLESS = { Undo = true }

if SCENARIO == "full" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 900)
	print(string.format("round 2 at %.1fs, round 3 at %.1fs, beaten at %.1fs (from waking)", (roundAt[2] or 0), (roundAt[3] or 0), T))
	runFor(6)
	leave(p)
	runFor(12)
	assert(stateIs("Dormant"), "once everyone's gone he should be back, asleep")
	assert(model:GetAttribute("Paper") == HALF, "the paper should be whole again after the fight")
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
		return stateIs("Fighting")
	end, 60)
	toRound(p, 3)
	E.token += 1
	-- let a DELETE box shrink the paper, then walk out
	runFor(def.Delete.Countdown + 1.5)
	assert((model:GetAttribute("Paper") or HALF) < HALF, "a DELETE box left alone should shrink the paper")
	leave(p)
	runFor(8)
	assert(stateIs("Dormant"), "he should reset when everyone leaves")
	assert(#E.clones == 0 and #E.zones == 0 and E.prompt == nil and E.key == nil, "a reset clears his clones, strips, paint and boxes")
	assert(model:GetAttribute("Paper") == HALF and model:GetAttribute("EraseTo") == nil, "a reset brings the paper back whole")
	runFor(1)
	local folder = workspace:FindFirstChild("ScribbleProps")
	assert(not folder or #folder:GetChildren() == 0, "a reset takes every prop away")
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
		local hp0 = model:GetAttribute("Health")
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
		return hitCount() - before, dodges - dodgesBefore, (model:GetAttribute("Health") or 0) - hp0
	end
	local report = {}
	for _, phase in ipairs({ 1, 2, 3 }) do
		if phase >= 2 then
			toRound(p, phase)
		end
		for _, name in ipairs(names) do
			local a = def.Attacks[name]
			if a.Phase <= phase and (not a.UpTo or phase <= a.UpTo) then
				if name == "Undo" then
					-- (he only undoes hits he's taken: give him some, fresh)
					local max = model:GetAttribute("MaxHealth")
					model:SetAttribute("Health", model:GetAttribute("Health") - math.floor(max * 0.05))
					table.insert(E.recent, { t = M.now(), dmg = math.floor(max * 0.05) })
				end
				local landed, _, healed = force(name, false)
				local _, dodged = force(name, true)
				table.insert(report, string.format("round %d %s hit=%d dodged=%d%s", phase, name, landed, dodged,
					name == "Undo" and string.format(" healed=%d", healed) or ""))
				if not HARMLESS[name] and landed == 0 then
					problem(name .. " (round " .. phase .. ") never hit a player standing still where it reaches")
				end
				if HARMLESS[name] and landed > 0 then
					problem(name .. " shouldn't hurt anyone")
				end
				if not HARMLESS[name] and dodged == 0 then
					problem(name .. " (round " .. phase .. ") couldn't be rolled through")
				end
				if name == "Undo" and healed <= 0 then
					problem("an Undo left alone should give him health back")
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
		print(string.format("%-20s roll %.2fs before it hits: %s", label, before, landed and "HIT" or (dodged and "dodged" or "missed")))
		if wantDodge and landed then
			problem(label .. ": a roll " .. before .. "s before it hits should dodge it")
		elseif not wantDodge and not landed then
			problem(label .. ": a roll " .. before .. "s before it hits is too early - it should still hit")
		end
		takeOver(p)
		runFor(2)
	end
	local A = def.Attacks
	-- the dash reaches you (20 studs out) 20 / Speed after the Tell
	local dashHit = A.PencilDash.Tell + 20 / A.PencilDash.Speed
	case("PencilDash", 20, dashHit, 0.1, true, "pencil dash late", 0.3)
	case("PencilDash", 20, dashHit, 0.9, false, "pencil dash early", 0.3)
	case("EraserSweep", 18, A.EraserSweep.Tell, 0.1, true, "eraser sweep late", 0.3)
	case("EraserSweep", 18, A.EraserSweep.Tell, 0.9, false, "eraser sweep early", 0.3)
	case("PaintBucket", 18, A.PaintBucket.Tell, 0.1, true, "paint bucket late", 0.3)
	case("PaintBucket", 18, A.PaintBucket.Tell, 0.9, false, "paint bucket early", 0.3)
	toRound(p, 2)
	local clickHit = A.Cursor.Hunt + A.Cursor.Lock
	case("Cursor", 18, clickHit, 0.1, true, "cursor click late", 0.3)
	case("Cursor", 18, clickHit, 0.9, false, "cursor click early", 0.3)
	local popHit = A.ErrorPopups.Tell + A.ErrorPopups.Fall
	case("ErrorPopups", 18, popHit, 0.1, true, "error pop-up late", 0.1)
	case("ErrorPopups", 18, popHit, 0.9, false, "error pop-up early", 0.1)
	local lagHit = A.LagSpike.Tell + (A.LagSpike.Frames - 1) * A.LagSpike.Step
	case("LagSpike", 20, lagHit, 0.1, true, "lag spike late", 0.2)
	case("LagSpike", 20, lagHit, 0.9, false, "lag spike early", 0.2)
elseif SCENARIO == "undo" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.Undo
	local max = model:GetAttribute("MaxHealth")
	-- 1) broken in time: he's stunned, and punches on him land
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 12)
	place(p, spot, 0)
	table.insert(E.recent, { t = M.now(), dmg = math.floor(max * 0.04) })
	M.task.spawn(function()
		Boss.Attacks.Undo(E, token)
	end)
	runFor(A.Tell + 0.1, function(dt)
		place(p, spot, dt)
	end)
	local keyModel = nil
	for _, t in ipairs(workspace.ScribbleProps:GetChildren()) do
		if t:GetAttribute("Kind") == "UndoKey" then
			keyModel = t
		end
	end
	assert(keyModel, "the Z key should pop up")
	local c = keyModel:GetPivot().Position
	assert(math.abs(c.Y - (floorY + 3.4)) < 0.1, "the key should float at punch height")
	local broke = (popped.UndoKey or 0)
	for _ = 1, 30 do
		tick(1, function(dt)
			place(p, Vector3.new(c.X, floorY + 3, c.Z + 3), dt)
			punch(p, share)
		end)
		if (popped.UndoKey or 0) > broke then
			break
		end
	end
	assert((popped.UndoKey or 0) > broke, "punching the Z key should break it")
	runFor(0.3)
	assert(model:GetAttribute("Action") == "Stunned", "breaking the key should stun him")
	local hp0 = model:GetAttribute("Health")
	local landed = 0
	local t0 = T
	while T - t0 < A.Stun - 0.5 do
		tick(1, function(dt)
			place(p, Vector3.new(home.X, floorY + 3, home.Z + 5), dt)
			if punch(p, share, false) then
				landed += 1
			end
		end)
	end
	print(string.format("key broken: stunned for %.1fs, %d punches landed on him", A.Stun, landed))
	assert(landed >= 3 and model:GetAttribute("Health") < hp0, "punches on him while he's stunned should land")
	-- 2) left alone: CTRL+Z gives him back your last hits (at most Max of his bar)
	token = takeOver(p)
	E.lastUndo = nil
	local before = model:GetAttribute("Health")
	E.recent = {}
	for k = 1, 7 do
		table.insert(E.recent, { t = M.now(), dmg = math.floor(max * 0.01) })
	end
	M.task.spawn(function()
		Boss.Attacks.Undo(E, token)
	end)
	runFor(A.Tell + A.Window + 0.5, function(dt)
		place(p, Vector3.new(home.X + 30, floorY + 3, home.Z + 30), dt)
	end)
	local gained = model:GetAttribute("Health") - before
	print(string.format("key left alone: he got back %d (%.1f%% of his bar)", gained, gained / max * 100))
	assert(model:GetAttribute("Action") == "Undone", "a key left alone should undo your hits")
	assert(gained >= math.floor(max * 0.01) * A.Hits - 1 and gained <= math.floor(max * 0.01) * A.Hits + 1,
		"CTRL+Z should give back exactly your last " .. A.Hits .. " hits")
elseif SCENARIO == "delete" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local d = def.Delete
	toRound(p, 3)
	E.token += 1 -- (he stops: just the boxes now)
	-- 1) the box comes; punching NO crashes him
	runFor(1)
	local box = noButton()
	assert(box, "a DELETE box should pop up in round 3")
	assert(model:GetAttribute("EraseTo") and model:GetAttribute("EraseTo") < HALF, "the paper should start being erased")
	local hp0 = model:GetAttribute("Health")
	local c = box:GetPivot().Position
	assert(math.abs(c.Y - (floorY + CanvasPlan.ButtonUp)) < 0.1, "the NO button should be at punch height")
	for _ = 1, 60 do
		tick(1, function(dt)
			local inward = Vector3.new(home.X - c.X, 0, home.Z - c.Z).Unit
			place(p, Vector3.new(c.X, floorY + 3, c.Z) + inward * 3, dt)
			punch(p, share)
		end)
		if pressed > 0 then
			break
		end
	end
	runFor(0.2)
	assert(pressed == 1, "punching NO should close the box")
	assert(model:GetAttribute("Action") == "Crash", "pressing NO should crash him")
	assert(model:GetAttribute("Health") < hp0, "the crash should cost him health")
	assert(model:GetAttribute("EraseTo") == nil and model:GetAttribute("Paper") == HALF, "pressing NO should bring the paper back")
	print(string.format("NO pressed: he crashed, losing %.1f%% of his bar", (hp0 - model:GetAttribute("Health")) / model:GetAttribute("MaxHealth") * 100))
	-- 2) the next box, left alone: the delete hits hard (never kills) and the paper shrinks
	runFor(d.Crash + d.Every + 0.5, function(dt)
		place(p, Vector3.new(home.X, floorY + 3, home.Z), dt)
	end)
	assert(noButton(), "another box should come Every seconds after the last")
	local hum = humOf(p)
	hum.Health = 20 -- (low: the delete must still not kill)
	local nHits = #bigHits
	runFor(d.Countdown + 0.5, function(dt)
		place(p, Vector3.new(home.X, floorY + 3, home.Z), dt)
	end)
	assert(yeses == 1, "a box left alone should delete")
	assert(model:GetAttribute("Paper") == HALF - d.Shrink, "the delete should shrink the paper by Shrink")
	assert(hum.Health >= 1 and #bigHits > nHits, "the delete should hit you, but never kill you")
	print(string.format("box left alone: paper %d -> %d, you on %d health", HALF, model:GetAttribute("Paper"), hum.Health))
	hum.Health = 1e9
	-- 3) erased paper stings; solid paper doesn't
	local q0 = quietHits
	runFor(2, function(dt)
		place(p, Vector3.new(home.X, floorY + 3, home.Z + 20), dt)
	end)
	assert(quietHits == q0, "the solid paper shouldn't sting")
	runFor(2, function(dt)
		place(p, Vector3.new(home.X, floorY + 3, home.Z + HALF - 3), dt)
	end)
	local stings = quietHits - q0
	print(string.format("2s on erased paper: %d stings", stings))
	assert(stings >= 3, "standing on erased paper should sting")
elseif SCENARIO == "whip" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	toRound(p, 2)
	local A = def.Attacks.BarWhip
	local function whip(jump)
		local token = takeOver(p)
		local spot = Vector3.new(home.X, floorY + 3, home.Z + 14)
		place(p, spot, 0)
		local h0 = hitCount()
		M.task.spawn(function()
			Boss.Attacks.BarWhip(E, token)
		end)
		runFor(A.Tell + A.Turns[2] * A.Spin + 0.5, function(dt)
			local y = floorY + 3
			if jump then
				-- hopping the whole time the bar spins (at the top of each hop
				-- for most of it: the bar's low)
				local u = (M.now() % 0.5) / 0.5
				y = y + 3 + 1.5 * math.sin(math.pi * u)
			end
			place(p, Vector3.new(spot.X, y, spot.Z), dt)
		end)
		return hitCount() - h0
	end
	local standing = whip(false)
	local jumping = whip(true)
	print(string.format("bar whip: standing hit %d times, jumping hit %d times", standing, jumping))
	assert(standing == 1, "the whip should hit a player standing in its way (once)")
	assert(jumping == 0, "jumping over the whip should dodge it")
elseif SCENARIO == "clones" then
	local p = people[1] or makePlayer("Alpha", 1001)
	walkIn(p)
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	local A = def.Attacks.CopyPaste
	local token = takeOver(p)
	local spot = Vector3.new(home.X, floorY + 3, home.Z + 16)
	place(p, spot, 0)
	M.task.spawn(function()
		Boss.Attacks.CopyPaste(E, token)
	end)
	runFor(A.Tell + 0.2, function(dt)
		place(p, spot, dt)
	end)
	E.token += 1 -- (he stops: just the clones now)
	local live = 0
	for _, cl in ipairs(E.clones) do
		if not cl.gone then
			live += 1
		end
	end
	assert(live == A.Clones, "copy-paste should make " .. A.Clones .. " clones")
	local d0 = (E.clones[1].pos - spot).Magnitude
	local h0 = hitCount()
	runFor(4, function(dt)
		place(p, spot, dt)
	end)
	local d1 = (Vector3.new(E.clones[1].pos.X, spot.Y, E.clones[1].pos.Z) - spot).Magnitude
	print(string.format("clones: %d made; the first came from %.1f to %.1f studs away; slashes landed: %d", live, d0, d1, hitCount() - h0))
	assert(d1 < d0 - 3, "the clones should chase you")
	assert(hitCount() > h0, "a clone next to you should slash you")
	local before = popped.Clone or 0
	for _ = 1, 80 do
		tick(1, function(dt)
			for _, cl in ipairs(E.clones) do
				if not cl.gone then
					place(p, Vector3.new(cl.pos.X + 3, floorY + 3, cl.pos.Z), dt)
					punch(p, share)
					break
				end
			end
		end)
	end
	assert((popped.Clone or 0) - before >= live, "a punch or two should pop each clone")
	-- left alone, they smudge away
	token = takeOver(p)
	M.task.spawn(function()
		Boss.Attacks.CopyPaste(E, token)
	end)
	runFor(A.Tell + 0.3)
	E.token += 1
	local far = Vector3.new(home.X + 50, floorY + 3, home.Z - 50)
	runFor(A.Life + 1, function(dt)
		place(p, far, dt)
	end)
	local left = 0
	for _, cl in ipairs(E.clones) do
		if not cl.gone then
			left += 1
		end
	end
	assert(left == 0, "clones left alone should smudge away after their Life")
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
print(string.format("time %.1f  state %s  round %s  punches %d  props seen/popped %s  boxes %d (NO %d, deleted %d)  paper low %d",
	T, tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Phase")), punchesLanded, table.concat(propList, " "),
	boxesSeen, pressed, yeses, lowestPaper))
print("hits on players: " .. table.concat(hitList, " ") .. string.format("  dodged %d  shoves %d", dodges, shoves))
print("moves in order: " .. table.concat(order, " "))
print(string.format("furthest from the middle %.1f  reward power %d chests %s victories %d", maxOff, rewards.power, tostring(rewards.chests[9]), victories))
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
	needDrawn({ "Head", "Spine", "Arm", "Leg", "Eye", "Grin", "Pencil", "Shadow" })
	if SCENARIO == "attacks" then
		needDrawn({ "DashLine", "InkStreak", "EraserStrip", "GiantEraser", "PaintSquare", "PaintFlood", "CloneBody", "ZKey",
			"CursorArrow", "CursorShadow", "WhipBar", "ErrorWindow", "ErrorShadow", "LagGhost" })
		needWords({ "CTRL+C", "CTRL+V!", "CTRL+Z!", "LAG!" })
	elseif SCENARIO == "full" then
		needWords({ "ROUND 2", "DELETE" })
		needDrawn({ "DeleteBox", "ErasedEdge" })
	elseif SCENARIO == "undo" then
		needWords({ "HIT HIM!" })
	elseif SCENARIO == "delete" then
		needDrawn({ "DeleteBox", "NoButton", "ErasedEdge" })
		needWords({ "HIT HIM!" })
	end
end
if maxOff > HALF - 2.9 then
	problem(string.format("he went %.1f from the middle (off the paper)", maxOff))
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
	for _, name in ipairs({ "Wake", "Break", "Glitch", "Death" }) do
		if not seen[name] then
			problem("never saw " .. name)
		end
	end
	if boxesSeen == 0 then
		problem("no DELETE box ever popped up in round 3")
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
