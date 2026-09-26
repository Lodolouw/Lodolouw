--!nocheck
-- Headless test of ColosseumService in the pretend Roblox: a pretend player
-- goes in, beats waves 1-4, fights the Giant Straw King on wave 5 (dodging
-- some attacks, eating others), and we check nothing breaks.
--   luau test_colosseum.luau -a <scenario> <seed>
-- scenarios: full (default), leave (walk out mid-King), die (die mid-King), oldbuilder (no King template)
local M = require("./rbxmock")
local S = require("./sources")
local args = { ... }
local SCENARIO = args[1] or "full"
local SEED = tonumber(args[2]) or 7
math.randomseed(SEED)

local Vector3, CFrame, Instance, Random, Enum = M.Vector3, M.CFrame, M.Instance, M.Random, M.Enum
local CollectionService = M.services.CollectionService
local ServerStorage = M.services.ServerStorage
local ReplicatedStorage = M.services.ReplicatedStorage
local Players = M.services.Players
local workspace = M.workspace

local configModule = Instance.new("ModuleScript")
configModule.Name = "Config"
configModule.Parent = ReplicatedStorage
local Config
local env
env = M.env({
	require = function(mod)
		if mod == configModule then
			return Config
		end
		error("require of unknown module " .. tostring(mod))
	end,
})
Config = M.load(S.Config, "Config", env)()
local C = Config.Colosseum
local K = C.King

-- the dummy templates, built by the real LobbyBuilder code
local builder = M.load(S.DummyBuilder, "DummyBuilder", env)()
for _, t in ipairs(C.Types) do
	builder(t.id, t.scale).Parent = ServerStorage
end
if SCENARIO ~= "oldbuilder" then
	builder("King", K.scale).Parent = ServerStorage
end

-- the arena's floor: flat sand, the ring in the middle a little higher
local RING_R = 12 * 2.6 / 2
local function sandY(x, z)
	local d = math.sqrt((x - C.Center.X) ^ 2 + (z - C.Center.Z) ^ 2)
	if d <= RING_R then
		return C.Center.Y + 0.52
	end
	return C.Center.Y
end
local floorPart = Instance.new("Part")
floorPart.Name = "ArenaSand"
floorPart.Parent = workspace
M.raycast = function(origin, dir)
	-- (only straight-down rays are used on the sand)
	local y = sandY(origin.X, origin.Z)
	if origin.Y >= y and origin.Y + dir.Y <= y then
		return { Position = Vector3.new(origin.X, y, origin.Z), Instance = floorPart }
	end
	return nil
end

-- the doors
local function anchor(name, pos, tag)
	local p = Instance.new("Part")
	p.Name = name
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	if tag then
		CollectionService:AddTag(p, tag)
	end
	return p
end
local spawnPart = anchor("ColosseumSpawn", C.Center + Vector3.new(0, 3, -60), "ColosseumSpawn")
anchor("ColosseumDoor", C.GatePosition + Vector3.new(0, 1, 0), "ColosseumDoor")
anchor("ColosseumReturn", C.GatePosition + Vector3.new(0, 3, 5), "ColosseumReturn")
local exitDoor = anchor("ExitDoor", C.Center + Vector3.new(0, 3, -75))
local exitPrompt = Instance.new("ProximityPrompt")
exitPrompt.Parent = exitDoor
CollectionService:AddTag(exitPrompt, "ColosseumExit")
local gateDoor = anchor("Doorway", C.GatePosition + Vector3.new(0, 3, 0))
local enterPrompt = Instance.new("ProximityPrompt")
enterPrompt.Parent = gateDoor
CollectionService:AddTag(enterPrompt, "ColosseumEntrance")

-- the player
local LEVEL = 40
local player = Instance.new("Player")
player.Name = "Tester"
player.UserId = 1001
player.Parent = Players
local function makeCharacter()
	local char = Instance.new("Model")
	char.Name = "Tester"
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(C.GatePosition + Vector3.new(2, 3, 0))
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	player.Character = char
	return char, hum, root
end
local char, hum, root = makeCharacter()
M.players = { player }

local function feetOf(model)
	return model:GetPivot() * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, -(model:GetAttribute("Foot") or 5.4), 0)
end

-- the log
local stats = {
	events = {}, damage = {}, hurtCount = 0, dodged = 0, moves = {}, states = {}, power = 0, coins = 0,
	minionsSpawned = 0, kingKills = 0, maxWave = 0, kingSpawns = 0, bossWaves = {}, waveClears = 0,
	fx = {}, positionsBad = 0, maxOut = 0,
}
local function bump(t, k, n)
	t[k] = (t[k] or 0) + (n or 1)
end

-- CombatService, pretend
local iframeUntil = 0
local jumpUntil = 0
local lastLand = nil
local shapes = setmetatable({}, { __mode = "k" })
local lastDamageFrom = "?"
local Combat = {}
function Combat.DamagePlayer(p, amount, from, knock)
	assert(p == player, "damage to the wrong player")
	assert(type(amount) == "number" and amount == amount and amount > 0, "bad damage amount " .. tostring(amount))
	assert(from == nil or M.typeof(from) == "Vector3", "bad from")
	assert(knock == nil or (M.typeof(knock) == "Vector3" and not M.isNaNv(knock)), "bad knockback")
	if M.now() < iframeUntil then
		stats.dodged += 1
		return false
	end
	if hum.Health <= 0 then
		return false
	end
	hum:TakeDamage(amount)
	stats.hurtCount += 1
	bump(stats.damage, lastDamageFrom, amount)
	local share = amount / hum.MaxHealth
	local kinds = { [K.Pound.WaveDamage] = "wave", [K.Pound.Damage] = "poundLanding", [K.SlamDamage] = "kingSlam", [K.Spin.Damage] = "whirlwind", [C.SlamDamage] = "dummySlam", [C.Charge.Damage] = "charge", [C.Throw.Damage] = "bale" }
	local name = "other"
	for k2, v in pairs(kinds) do
		if math.abs(share - k2) < 1e-6 then
			name = v
		end
	end
	stats.byKind = stats.byKind or {}
	bump(stats.byKind, name)
	return true
end
function Combat.IsInvulnerable(p)
	return M.now() < iframeUntil
end
function Combat.Shove(p, v)
	assert(M.typeof(v) == "Vector3" and not M.isNaNv(v), "bad shove")
end
function Combat.Disintegrate(model)
	model:SetAttribute("Disintegrating", true)
	M.task.delay(3.1, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end
function Combat.SetTargetShape(model, fn)
	shapes[model] = fn
end

-- PlayerService, pretend
local Players2 = {}
function Players2.GetData()
	return { Power = Config.powerForLevel(LEVEL), Colosseum = colData }
end
function Players2.AddPower(_, n)
	assert(n == n and n > 0, "bad power " .. tostring(n))
	stats.power += n
end
function Players2.AddCoins(_, n)
	assert(n == n and n > 0, "bad coins")
	stats.coins += n
end
function Players2.QuestProgress() end
-- (the real PlayerService's run records and actions, pretend)
local colData = { clears = 0, best = nil, bonusDay = 0 }
local actions = {}
function Players2.AddAction(name, fn)
	actions[name] = fn
end
function Players2.RecordColosseumClear(_, seconds)
	assert(type(seconds) == "number" and seconds > 0 and seconds == seconds, "bad clear time " .. tostring(seconds))
	colData.clears += 1
	local newBest = colData.best == nil or seconds < colData.best
	if newBest then
		colData.best = seconds
	end
	local first = colData.clears == 1
	return { clears = colData.clears, best = colData.best, newBest = newBest, firstToday = first }
end

-- what the server tells the player's screen
local lastState = nil
M.onFireClient = function(remote, p, kind, a, b, c)
	if remote.Name ~= "ColosseumEvent" then
		return
	end
	bump(stats.events, kind)
	if kind == "PipeIn" then
		-- (the player's screen moves them inside)
		M.task.delay(0.5, function()
			root.CFrame = CFrame.new(c + Vector3.new(0, 3, 0))
		end)
	elseif kind == "PipeOut" then
		M.task.delay(0.5, function()
			root.CFrame = CFrame.new(b + Vector3.new(0, 3, 0))
		end)
	elseif kind == "Wave" or kind == "BossWave" then
		stats.maxWave = math.max(stats.maxWave, a)
		stats.waveEvents = (stats.waveEvents or 0) + 1
		if stats.runClears and a == 1 then
			stats.secondRun = true
		end
		if kind == "BossWave" then
			table.insert(stats.bossWaves, a)
		end
	elseif kind == "State" then
		lastState = a
	elseif kind == "KingFx" then
		bump(stats.fx, a)
		assert(M.typeof(b) == "Vector3" and not M.isNaNv(b), "KingFx without a good position")
		if a == "Land" and c == 1.3 then
			lastLand = b
		end
	elseif kind == "Sfx" then
		stats.sfx = stats.sfx or {}
		stats.sfx[a] = (stats.sfx[a] or 0) + 1
		assert(C.Sounds[a], "unknown Colosseum sound " .. tostring(a))
		assert(M.typeof(b) == "Vector3" and not M.isNaNv(b), "a sound needs a good position")
	elseif kind == "KingDown" then
		stats.kingKills += 1
		stats.kingReward = { a, b }
	elseif kind == "WaveClear" then
		stats.waveClears += 1
	elseif kind == "RunClear" then
		stats.runClears = (stats.runClears or 0) + 1
		stats.lastClear = a
		assert(type(a) == "table" and a.time > 0, "RunClear needs its time")
		stats.clearAt = M.now()
		stats.wavesAtClear = stats.waveEvents or 0
	elseif kind == "Streak" then
		stats.streaks = (stats.streaks or 0) + 1
		local ST = C.Streak
		assert(math.abs(b - math.min(ST.Max, math.floor(a / ST.Every) * ST.Bonus)) < 1e-9, "streak bonus maths")
		stats.bestStreak = math.max(stats.bestStreak or 0, a)
	elseif kind == "StreakLost" then
		stats.streakLost = (stats.streakLost or 0) + 1
	end
end

-- watch the King
local king = nil
M.onAttribute = function(inst, name, value)
	if inst:GetAttribute("Kind") == "King" then
		if name == "Move" and value then
			bump(stats.moves, value)
			lastDamageFrom = value
		elseif name == "State" then
			table.insert(stats.states, value)
			if value == "Fighting" then
				stats.fightStart = M.now()
			elseif value == "Dead" then
				stats.fightEnd = M.now()
			elseif value == "Waking" then
				stats.wakeAt = M.now()
			end
		elseif name == "Phase" and value == 2 then
			stats.rage = (stats.rage or 0) + 1
		end
	end
end

-- go!
local Colosseum = M.load(S.ColosseumService, "ColosseumService", env)()
Colosseum.Start(Combat, Players2)
local enemyFolder = workspace:FindFirstChild("ColosseumEnemies")
assert(enemyFolder, "no enemy folder")
enemyFolder.ChildAdded:Connect(function(m)
	-- a new dummy must arrive hidden up in the sky (it drops in; it never
	-- stands on the sand first and then vanishes)
	if m:IsA("Model") then
		local fy = feetOf(m).Position.Y
		if fy < 100 then
			stats.positionsBad += 1
			print(string.format("!! %s arrived on the sand (feet at %.1f) instead of hidden in the sky", m.Name, fy))
		end
	end
	if m:GetAttribute("Kind") == "King" then
		king = m
		stats.kingSpawns += 1
		assert(m:GetAttribute("NoBar") == true, "the King should have NoBar before anything sees him")
		assert(m:GetAttribute("Invulnerable") == true, "the King should arrive invulnerable")
	elseif m:IsA("Model") and m.Name == "Straw Minion" then
		stats.minionsSpawned += 1
	end
end)

M.task.spawn(function()
	enterPrompt.Triggered:Fire(player)
end)

----------------------------------------------------------------------
-- The pretend player: chases the nearest dummy and punches it, dodges
-- (mostly) what it sees coming, jumps shockwaves (mostly)
----------------------------------------------------------------------
local rng = Random.new(SEED)
local SPEED = 16
local lastPunch = 0
local skill = 0.7 -- how often it dodges in time
local dodgePlan = {} -- [warning part] = decided?
local punches, kingHits = 0, 0

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function myEnemies()
	local list = {}
	for _, m in ipairs(enemyFolder:GetChildren()) do
		if m:IsA("Model") and CollectionService:HasTag(m, "CombatTarget") and (m:GetAttribute("Health") or 0) > 0 then
			table.insert(list, m)
		end
	end
	return list
end
local function setPos(p)
	local y = sandY(p.X, p.Z) + 3 + ((M.now() < jumpUntil) and 4 or 0)
	root.CFrame = CFrame.new(p.X, y, p.Z)
end
local function punch(target)
	-- like CombatService: the point of the target nearest you (its shape if it has one)
	local at, radius
	local shape = shapes[target]
	if shape then
		at, radius = shape(root.Position)
	else
		at, radius = target:GetPivot().Position, target:GetAttribute("HitRadius") or 3
	end
	local d = flat(at - root.Position).Magnitude - radius
	if d > Config.Combat.PunchRange or math.abs(at.Y - root.Position.Y) >= 12 then
		return false
	end
	punches += 1
	local dmg = Config.powerForLevel(target:GetAttribute("Level") or LEVEL)
	if target:GetAttribute("Invulnerable") then
		dmg = 0
	end
	local before = target:GetAttribute("Health")
	local hp = math.max(0, before - dmg)
	target:SetAttribute("Health", hp)
	if target == king and dmg > 0 then
		kingHits += 1
	end
	local onHit = target:FindFirstChild("OnHit")
	if onHit then
		onHit:Fire(player, before - hp, hp <= 0)
	end
	return true
end

local function playerBrain()
	while true do
		local dt = M.task.wait(0.1)
		if hum.Health <= 0 or not player:GetAttribute("Colosseum") then
			continue
		end
		-- heal with a "flask" when low (the full fight should get to the end)
		if not stats.died and hum.Health < 35 then
			hum.Health = hum.MaxHealth
			stats.flasks = (stats.flasks or 0) + 1
		end
		local here = flat(root.Position)
		local move = Vector3.zero
		-- warnings: red rings / discs / strips. Dodge out of any we're inside.
		local danger = nil
		for _, f in ipairs(enemyFolder:GetChildren()) do
			if f.Name == "DummyFX" then
				for _, w in ipairs(f:GetChildren()) do
					if w.Name == "Warning" and w.Shape == Enum.PartType.Cylinder and w.Transparency < 0.9 then
						local r = w.Size.Y / 2
						local d = flat(w.Position - root.Position).Magnitude
						if d < r + 1.5 then
							danger = w
						end
					elseif w.Name == "Shockwave" and w.Transparency < 0.5 then
						-- a shockwave block coming at us: jump (mostly)
						-- (how far the block's stretch of the ring is from us)
						local l = w.CFrame:PointToObjectSpace(root.Position)
						local d = (math.abs(l.X) <= w.Size.X / 2 + 1) and math.abs(l.Z) or math.huge
						if d < 7 and M.now() > jumpUntil + 0.3 and SCENARIO == "full" then
							if SCENARIO == "kitejump" or rng:NextNumber() < skill then
								jumpUntil = M.now() + 0.45
								stats.jumps = (stats.jumps or 0) + 1
							else
								jumpUntil = 0
							end
						end
					end
				end
			end
		end
		local kite = (SCENARIO == "kite" or SCENARIO == "kitejump") and king and king.Parent
		if danger then
			if dodgePlan[danger] == nil then
				dodgePlan[danger] = kite or rng:NextNumber() < skill
			end
			if dodgePlan[danger] then
				local away = flat(root.Position - danger.Position)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
				-- (against the wall? run along it instead)
				local best, bestScore = away, -math.huge
				for _, dir in ipairs({ away, Vector3.new(-away.Z, 0, away.X), Vector3.new(away.Z, 0, -away.X), (away + Vector3.new(-away.Z, 0, away.X)).Unit, (away + Vector3.new(away.Z, 0, -away.X)).Unit }) do
					local p2 = here + dir * 10
					local inside = flat(p2 - C.Center).Magnitude <= C.Radius - 1
					local score = flat(p2 - danger.Position).Magnitude + (inside and 0 or -100)
					if score > bestScore then
						best, bestScore = dir, score
					end
				end
				away = best
				-- sometimes roll (a quick dash with invincibility), mostly run
				if rng:NextNumber() < 0.25 and M.now() > iframeUntil + 0.6 then
					iframeUntil = M.now() + 0.5
					move = away * 17
					stats.rolls = (stats.rolls or 0) + 1
				else
					move = away * SPEED * dt
				end
			end
		elseif kite then
			-- keep about 30 studs from the King, circling
			local off = flat(root.Position - feetOf(king).Position)
			local d = off.Magnitude
			local want = off.Unit * 30
			local side = Vector3.new(-off.Unit.Z, 0, off.Unit.X)
			local go = (want - off) * 0.5 + side * 6
			if go.Magnitude > 0.01 then
				move = go.Unit * math.min(SPEED * dt, go.Magnitude)
			end
			local _ = d
		else
			-- chase the nearest dummy and punch it
			local best, bestD = nil, math.huge
			for _, m in ipairs(myEnemies()) do
				local d = flat(feetOf(m).Position - root.Position).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
			if best then
				local reach = (best:GetAttribute("HitRadius") or 3) + Config.Combat.PunchRange - 1.5
				if bestD > reach then
					local go = flat(feetOf(best).Position - root.Position)
					move = go.Unit * math.min(SPEED * dt, bestD - reach + 0.5)
				elseif M.now() - lastPunch >= 0.5 then
					lastPunch = M.now()
					punch(best)
				end
			end
		end
		local p = here + move
		local off = flat(p - C.Center)
		if off.Magnitude > C.Radius then
			p = C.Center + off.Unit * C.Radius
		end
		setPos(Vector3.new(p.X, 0, p.Z))
	end
end
M.task.spawn(playerBrain)
-- the jumping player watches the shockwave roll in and jumps just before it
-- reaches them (about a fifth of a second early), 30 times a second
if SCENARIO == "kitejump" then
	M.task.spawn(function()
		while true do
			M.task.wait(1 / 30)
			if lastLand and M.now() > jumpUntil then
				local d = flat(root.Position - lastLand).Magnitude
				for _, f in ipairs(enemyFolder:GetChildren()) do
					if f.Name == "DummyFX" then
						for _, w in ipairs(f:GetChildren()) do
							if w.Name == "Shockwave" and w.Transparency < 0.5 then
								local r = flat(w.Position - lastLand).Magnitude
								if d - r > -1 and d - r < K.Pound.WaveSpeed * 0.2 then
									jumpUntil = M.now() + 0.45
									stats.jumps = (stats.jumps or 0) + 1
									setPos(Vector3.new(root.Position.X, 0, root.Position.Z))
								end
							end
						end
					end
				end
			end
		end
	end)
end

lastPivotTrace = setmetatable({}, { __mode = "k" })
M.onPivot = function(model, target)
	lastPivotTrace[model] = tostring(target) .. "\n" .. debug.traceback()
end
-- sanity checks on everything that moves, every step
local rootBad = false
local function checkWorld()
	if not rootBad and M.isNaNv(root.Position) then
		rootBad = true
		print("!! the player's root went NaN at " .. M.now())
	end
	for _, m in ipairs(enemyFolder:GetChildren()) do
		if m:IsA("Model") and not m:GetAttribute("Disintegrating") then
			local f = feetOf(m).Position
			if M.isNaNv(f) then
				stats.positionsBad += 1
			end
			local out = flat(f - C.Center).Magnitude
			-- (the Cursed Dummy blinks away 80 studs down; the King leaps high)
			if f.Y > -20 then
				stats.maxOut = math.max(stats.maxOut, out)
				if out > C.Radius + 0.5 then
					stats.positionsBad += 1
					if stats.positionsBad < 3 then
						print(string.format("!! %s outside the arena: %.1f  feet=%s pivot=%s pp=%s t=%.2f parent=%s", m.Name, out, tostring(f), tostring(m:GetPivot()), tostring(m.PrimaryPart), M.now(), tostring(m.Parent)))
					end
				end
				if f.Y < sandY(f.X, f.Z) - 2.5 then
					stats.positionsBad += 1
					if stats.positionsBad < 3 then
						print(string.format("!! %s sunk into the sand: %.2f feet=%s t=%.2f", m.Name, f.Y - sandY(f.X, f.Z), tostring(f), M.now()))
						print(lastPivotTrace[m])
					end
				end
			end
		end
	end
end

-- SNAPSHOTS for the preview pictures: every part in the arena at a moment
local SNAP = args[3] == "snap"
local snapped = {}
local function partJson(p)
	local c = p.CFrame
	local comps = { c:GetComponents() }
	for i, v in ipairs(comps) do
		comps[i] = string.format("%.4f", v)
	end
	local col = p.Color
	return string.format('{"name":"%s","size":[%.3f,%.3f,%.3f],"cf":[%s],"color":[%d,%d,%d],"mat":"%s","shape":"%s","t":%.2f}',
		p.Name, p.Size.X, p.Size.Y, p.Size.Z, table.concat(comps, ","),
		math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		p.Material.Name, p.Shape and p.Shape.Name or "Block", p.Transparency)
end
local function snapshot(name)
	if not SNAP or snapped[name] then
		return
	end
	snapped[name] = true
	local list = {}
	for _, d in ipairs(enemyFolder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(list, partJson(d))
		end
	end
	local r = root.Position
	print(string.format("SNAP %s %.2f %.2f %.2f [%s]", name, r.X, r.Y - 3, r.Z, table.concat(list, ",")))
end
local function hasPart(pname, maxT)
	for _, d in ipairs(enemyFolder:GetDescendants()) do
		if d.Name == pname and d.Transparency <= (maxT or 1) then
			return d
		end
	end
	return nil
end
local kingSeenAt = nil
local t = 0
local endAt = (SCENARIO == "full" or SCENARIO == "oldbuilder" or SCENARIO == "clearleave") and 420 or 300
while t < endAt do
	t += 0.1
	M.run(t)
	checkWorld()
	if SNAP and king and king.Parent then
		local mv = king:GetAttribute("Move")
		local st = king:GetAttribute("State")
		if st == "Waking" and hasPart("Shockwave", 0.7) then
			snapshot("entrance")
		end
		local wave = hasPart("Shockwave", 0.5)
		if wave and lastLand and (wave.Position - lastLand).Magnitude > 20 then
			snapshot("shockwave")
		end
		if mv == "Pound" and hasPart("Warning", 0.5) and king:GetPivot().Y > 30 then
			snapshot("leap")
		end
		if mv == "Spin" and hasPart("WhirlStraw") then
			snapshot("whirlwind")
		end
		if stats.minionsSpawned >= 3 and not snapped.summon then
			local n = 0
			for _, m in ipairs(enemyFolder:GetChildren()) do
				if m.Name == "Straw Minion" then
					n += 1
				end
			end
			if n >= 3 then
				snapshot("summon")
			end
		end
	end
	if king and not kingSeenAt then
		kingSeenAt = t
	end
	if SCENARIO == "leave" and kingSeenAt and t > kingSeenAt + 12 and player:GetAttribute("Colosseum") then
		-- walk to the exit and leave mid-fight
		root.CFrame = CFrame.new(exitDoor.Position)
		M.task.spawn(function()
			exitPrompt.Triggered:Fire(player)
		end)
		stats.left = t
	end
	if SCENARIO == "die" and kingSeenAt and t > kingSeenAt + 12 and hum.Health > 0 and not stats.died then
		hum.Health = 0
		stats.died = t
		M.task.delay(5, function()
			char:Destroy()
			char, hum, root = makeCharacter()
			player.CharacterAdded:Fire(char)
		end)
	end
	if (SCENARIO == "kite" or SCENARIO == "kitejump") and kingSeenAt and t > kingSeenAt + 70 then
		break
	end
	if stats.clearAt and not stats.pressed and M.now() > stats.clearAt + 6 then
		stats.pressed = true
		assert((stats.waveEvents or 0) == stats.wavesAtClear, "no new wave should start until you choose")
		local okBad = actions.ColosseumAgain and select(1, actions.ColosseumAgain(Instance.new("Player")))
		assert(not okBad, "someone not in the Colosseum can't start a run")
		if SCENARIO == "clearleave" then
			local ok = actions.ColosseumLeave(player)
			assert(ok, "LEAVE should work once the run is cleared")
		else
			local ok, msg = actions.ColosseumAgain(player)
			assert(ok, "RUN AGAIN should work once the run is cleared: " .. tostring(msg))
			local again = actions.ColosseumAgain(player)
			assert(not again, "pressing RUN AGAIN twice shouldn't start two runs")
			assert(hum.Health == hum.MaxHealth, "RUN AGAIN heals you")
		end
	end
	if SCENARIO == "full" and stats.secondRun and stats.waveEvents >= stats.wavesAtClear + 2 then
		break
	end
	if SCENARIO == "clearleave" and stats.pressed and M.now() > stats.clearAt + 12 then
		break
	end
	if SCENARIO == "oldbuilder" and stats.maxWave >= 6 then
		break
	end
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------
local function dump(name, t2)
	local keys = {}
	for k in pairs(t2) do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = t2[k]
		table.insert(parts, k .. "=" .. (type(v) == "number" and string.format("%.4g", v) or tostring(v)))
	end
	print(name .. ": " .. table.concat(parts, "  "))
end
print(string.format("scenario=%s seed=%d  virtual time %.1fs", SCENARIO, SEED, M.now()))
print(string.format("waves reached %d  boss waves %s  wave clears %d  king spawns %d  king kills %d  rage %s",
	stats.maxWave, table.concat(stats.bossWaves, ","), stats.waveClears, stats.kingSpawns, stats.kingKills, tostring(stats.rage)))
print("king states: " .. table.concat(stats.states, " > "))
if stats.fightStart then
	print(string.format("KING: intro %.1fs, fight %.1fs", stats.fightStart - (stats.wakeAt or 0), (stats.fightEnd or M.now()) - stats.fightStart))
end
dump("king moves", stats.moves)
dump("fx", stats.fx)
dump("events", stats.events)
dump("damage taken by move", stats.damage)
if stats.sfx then
	dump("dummy sounds", stats.sfx)
end
if stats.byKind then
	dump("hits by kind", stats.byKind)
end
print(string.format("hurt %d times, dodged %d (rolling), jumps %s, rolls %s, flasks %s, punches %d (on the King %d), minions %d",
	stats.hurtCount, stats.dodged, tostring(stats.jumps), tostring(stats.rolls), tostring(stats.flasks), punches, kingHits, stats.minionsSpawned))
print(string.format("runs cleared %s (time %s, bonus %s)  streak banners %s (best x%s)  streaks lost %s",
	tostring(stats.runClears), stats.lastClear and tostring(stats.lastClear.time) or "-", stats.lastClear and tostring(stats.lastClear.bonusPower) or "-",
	tostring(stats.streaks), tostring(stats.bestStreak), tostring(stats.streakLost)))
print(string.format("power %d  coins %d  king reward %s", stats.power, stats.coins, stats.kingReward and (stats.kingReward[1] .. " power / " .. stats.kingReward[2] .. " coins") or "-"))
local rewards = Config.colosseumRewards(LEVEL)
print(string.format("(a straw dummy at Lv%d pays %d power / %d coins)", LEVEL, rewards.killPower, rewards.killCoins))
print(string.format("furthest from the middle: %.1f (radius %d)", stats.maxOut, C.Radius))
local left = #enemyFolder:GetChildren()
print("things left in ColosseumEnemies: " .. left)
if lastState then
	print(string.format("last state: wave %s boss %s left %s quest %s/%s", tostring(lastState.wave), tostring(lastState.boss), tostring(lastState.left), tostring(lastState.quest), tostring(lastState.goal)))
end
local problems = #M.errors + (M.nanWrites or 0) + stats.positionsBad
print(string.format("ERRORS %d  NaN writes %d  bad positions %d  warnings %d", #M.errors, M.nanWrites or 0, stats.positionsBad, M.warnings or 0))
if SCENARIO == "full" then
	assert(stats.kingKills == 1, "the King was never beaten")
	assert(stats.bossWaves[1] == 5, "the boss wave should be wave 5")
	assert(stats.rage == 1, "the King should get angry once")
	assert((stats.moves.Summon or 0) >= 1, "the King should summon")
	assert((stats.moves.Pound or 0) >= 1, "the King should pound")
	assert((stats.moves.Spin or 0) >= 1, "the King should spin")
	assert(stats.runClears == 1, "beating the King should clear the run")
	assert(stats.secondRun, "RUN AGAIN should start a new run at wave 1")
	-- (the pretend player gets hit a lot, so a x5 streak isn't certain - but
	-- streaks must be counted, and broken by hits)
	assert((stats.streaks or 0) >= 1 or (stats.streakLost or 0) >= 1, "kill streaks should be counted")
	local base = math.floor(rewards.killPower * K.reward)
	assert(stats.kingReward[1] >= base and stats.kingReward[1] <= math.floor(base * (1 + C.Streak.Max)) + 1,
		"king reward " .. stats.kingReward[1] .. " should be " .. base .. " plus at most the streak bonus")
	assert(stats.lastClear.bonusPower, "the first clear of the day pays a bonus")
end
if SCENARIO == "clearleave" then
	assert(stats.runClears == 1, "the run should be cleared")
	assert(left == 0 and not player:GetAttribute("Colosseum"), "LEAVE should take you out")
end
if SCENARIO == "leave" or SCENARIO == "die" then
	assert(left == 0, "everything should be cleared away when you leave or die")
	assert(not player:GetAttribute("Colosseum"), "should be out of the Colosseum")
end
if SCENARIO == "kite" then
	assert((stats.moves.Pound or 0) >= 3, "a far-away player should get pounded")
	assert((stats.byKind or {}).wave, "standing on the sand, the shockwave should hit")
end
if SCENARIO == "kitejump" then
	assert((stats.moves.Pound or 0) >= 3, "a far-away player should get pounded")
	assert(not (stats.byKind or {}).wave, "jumping it, the shockwave should never hit")
end
if SCENARIO == "oldbuilder" then
	assert(stats.kingSpawns == 0 and stats.maxWave >= 6, "without the King template the waves should just carry on")
end
local shapesLeft = 0
for m, fn in pairs(shapes) do
	if fn then
		shapesLeft += 1
	end
end
print("hit shapes still remembered: " .. shapesLeft)
if SCENARIO ~= "kite" and SCENARIO ~= "kitejump" then
	assert(shapesLeft == 0, "the King's hit shape should be forgotten once he's gone")
end
assert(problems == 0, "problems found")
print("PASS")
