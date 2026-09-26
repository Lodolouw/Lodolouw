--[[
	ColosseumService  (ModuleScript, parent: ServerScriptService, name: "ColosseumService")

	The Colosseum: a wave arena for farming Power (XP) and coins.

	  * Press E at the little door of the mini colosseum in the lobby: a
	    pop-up asks how hard (LobbyActivities). Pick, press ENTER, and you
	    shrink down into the door, bit by bit, like going down a pipe - and
	    you're in the Colosseum (far from the lobby), already small enough.
	    Press E at its EXIT gate and you pop out of the little door tiny and
	    grow back. Die in there and you're simply back in the lobby.
	  * Inside, dummies drop in wave after wave. They hop after you, and
	    when one lands close it winds up a slam: a red ring shows on the sand -
	    get out of it (or roll through it) before it comes down.
	  * New kinds join the waves as you level up (Config.Colosseum.Types):
	      Straw Dummy   (Lv 1)  - hops and slams
	      Wooden Brute  (Lv 10) - a red strip shows, then it CHARGES down it
	      Hay Slinger   (Lv 20) - keeps back and lobs hay bales at a red square
	      Iron Knight   (Lv 35) - its shield blocks punches from the front
	                              (CombatService): go round the back
	      Cursed Dummy  (Lv 50) - vanishes and reappears BEHIND you, slamming
	    Every kind shows its move before doing it, so it can always be dodged.
	  * EVERYONE FARMS ON THEIR OWN: your dummies carry your UserId (Owner).
	    Only you can hit them, they only go for you, and other players' screens
	    hide them (LobbyActivities). Other players are just there with you.
	  * Dummies are always your level, so each takes about the same few
	    punches whatever your level - and the rewards grow as you do.
	  * A quest runs the whole time you're in there: BEAT 5 WAVES (a whole
	    run, the King's wave last) for a big lump of Power and coins. It's
	    paid when the run is cleared, and starts over with the next run.
	  * THE BOSS WAVE: every 5th wave the GIANT STRAW KING crashes down on
	    his own, with a boss bar across your screen (LobbyActivities) and
	    an introduction (BossIntro). His moves, each shown before it lands:
	      Big hops        - he bounds after you
	      Royal slam      - get close and a red ring shows round him
	      Ground pound    - a red ring where you stand: he leaps and crashes
	                        down in it, and a SHOCKWAVE rolls out across the
	                        sand - jump over it or roll through it
	      Whirlwind       - a red circle round him, then straw whips round it
	      Summon          - straw minions drop in round you
	    At half health he gets ANGRY: faster, two shockwaves per pound, and
	    a faster whirlwind. He pays like 15 straw dummies.
	  * RUNS: the King's wave is the last of a RUN (5 waves), like a mini
	    dungeon. Beat him and the Colosseum is CLEARED: your time is saved
	    (PlayerService keeps your best time and how many runs you've
	    cleared), the first clear of the day pays a bonus, and you choose
	    RUN AGAIN (healed, flasks refilled, back to wave 1) or LEAVE.
	  * KILL STREAKS: dummies beaten in a row without getting hurt. Every 5
	    adds 10% to what each kill pays (up to +50%). It carries on from run
	    to run, and ends the moment you're hurt (or when you leave).
	  * DIFFICULTY: Normal, Hard or Nightmare, picked in the pop-up at the
	    door as you go in, or on the CLEARED screen for the next run (it's
	    saved: PlayerService).
	    Harder ones mean tougher dummies that hit harder, more of them, a bit
	    faster - and everything the run pays is multiplied (Hard x2,
	    Nightmare x3.5). On Nightmare the King is angry from the start. Hard
	    opens once you've cleared a Normal run, Nightmare once you've cleared
	    a Hard one. A run keeps the difficulty it started on.

	All the numbers are in Config.Colosseum (the King's in Config.Colosseum.King).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ColosseumService = {}

local C = Config.Colosseum
local CombatService, PlayerService -- (set in Start)
local sessions = {} -- [player] = the fight that player is in
local remote -- ColosseumEvent: server -> client
local enemyFolder
local rng = Random.new()
local strawPuff -- (below)
local spawnDummy -- (below: the King's minions need it before it's written)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root and hum.Health > 0) then
		return nil
	end
	return root, hum, char
end

local function send(player, ...)
	if remote and player.Parent then
		remote:FireClient(player, ...)
	end
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- one of the Colosseum's sounds on the player's screen (by name from
-- Config.Colosseum.Sounds: "Land", "Slam", "Poof"...), at `at` so a far-off
-- one sounds quieter
local function sfx(s, key, at)
	send(s.player, "Sfx", key, at)
end

----------------------------------------------------------------------
-- Going down the pipe: you shrink, bit by bit (8-bit steps), into the
-- mini colosseum's little door, and pop back out growing the same way.
----------------------------------------------------------------------
local function groundBelow(pos, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, enemyFolder }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or pos
end

-- Tells the movement guard (PlayerService) this move is the server's own,
-- so it doesn't put the player back where they came from.
local function allowMove(player, destination, seconds)
	if player and destination then
		player:SetAttribute("MoveTo", destination)
		player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + (seconds or 3))
	end
end

-- If the player's screen didn't manage the trip (it failed, or LobbyActivities
-- is missing), move them the plain way so they're never left stuck.
local function ensureAt(player, cf, near)
	local root, _, char = rootOf(player)
	if root and (flat(root.Position - cf.Position)).Magnitude > near then
		pcall(function()
			char:ScaleTo(1)
		end)
		root.Anchored = false
		local g = groundBelow(cf.Position, char)
		allowMove(player, g, 3)
		char:PivotTo(CFrame.new(g + Vector3.new(0, 4, 0)) * cf.Rotation)
	end
end

local function playerLevel(player)
	local d = PlayerService.GetData(player)
	return Config.levelFromPower(d and d.Power or 0)
end

-- RUNS: the King's wave ends a run (unless Config says the waves go on)
local function runLength()
	local K = C.King
	return (K and K.EndsRun ~= false and K.Every) or nil
end

-- The difficulty the player picked (Config.Colosseum.Difficulties): the
-- next run uses it. (Normal if it isn't open to them.)
local function pickedDifficulty(player)
	local d = PlayerService.GetData(player)
	local col = d and d.Colosseum
	local id = col and col.pick
	if not Config.colosseumUnlocked(col, id) then
		id = nil
	end
	return Config.colosseumDifficulty(id)
end

-- how much of the player's max health a hit takes on this run's difficulty
local function dmg(s, share)
	return share * ((s.diff and s.diff.damage) or 1)
end

-- what a kill streak of `n` adds to each kill's pay (0.1 = +10%)
local function streakBonus(n)
	local ST = C.Streak
	if not ST or (n or 0) <= 0 then
		return 0
	end
	return math.min(ST.Max, math.floor(n / ST.Every) * ST.Bonus)
end

-- the state the player's screen shows (wave, quest progress, what it pays)
local function pushState(player, s)
	local rewards = Config.colosseumRewards(playerLevel(player))
	local d = PlayerService.GetData(player)
	local col = d and d.Colosseum
	local diff = s.diff or pickedDifficulty(player)
	local pay = diff.reward or 1
	send(player, "State", {
		wave = s.wave,
		of = runLength(), -- (waves in a run: "WAVE 3/5")
		boss = s.bossWave == true, -- (the King's wave)
		cleared = s.cleared == true, -- (between runs)
		streak = s.streak or 0,
		streakBonus = streakBonus(s.streak),
		best = col and col.best,
		clears = col and col.clears,
		left = s.alive,
		diff = diff.id, -- (this run's difficulty)
		pick = pickedDifficulty(player).id, -- (the next run's, if it's been changed)
		quest = s.questWaves,
		goal = C.QuestWaves or 5,
		questPower = math.max(1, math.floor(rewards.questPower * pay)),
		questCoins = math.max(1, math.floor(rewards.questCoins * pay)),
	})
end

----------------------------------------------------------------------
-- The dummies
----------------------------------------------------------------------
-- Where a dummy's feet are, and putting them somewhere. The model's pivot is
-- its body (every piece is anchored and moves with it), `Foot` studs above
-- its feet (bigger kinds stand taller) and built facing backwards - so both
-- are worked out from that.
local FOOT = 5.4 -- a straw dummy's body is this far above its feet
local TURN = CFrame.Angles(0, math.pi, 0)
local PARKED = 200 -- how high up a new dummy waits, out of sight, before it drops in
local function footOf(model)
	return model:GetAttribute("Foot") or FOOT
end
local function feet(model)
	return model:GetPivot() * TURN * CFrame.new(0, -footOf(model), 0)
end
local function place(model, cf)
	model:PivotTo(cf * CFrame.new(0, footOf(model), 0) * TURN)
	-- (a shield only blocks from the front: CombatService needs to know which way that is)
	if model:GetAttribute("ShieldArc") then
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if look.Magnitude > 0.01 then
			model:SetAttribute("FrontDir", look.Unit)
		end
	end
end

-- The top of the sand at a spot (the ring in the middle of the arena stands
-- a little higher than the rest, so dummies step up onto it, not into it)
local sandParams = RaycastParams.new()
sandParams.FilterType = Enum.RaycastFilterType.Exclude
sandParams.RespectCanCollide = true
local function sandAt(pos)
	local skip = { enemyFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	sandParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(pos.X, C.Center.Y + 6, pos.Z), Vector3.new(0, -12, 0), sandParams)
	return Vector3.new(pos.X, hit and hit.Position.Y or C.Center.Y, pos.Z)
end

local function inArena(pos, margin)
	local d = flat(pos - C.Center)
	local R = C.Radius - (margin or 0)
	if d.Magnitude > R then
		d = d.Unit * R
	end
	return sandAt(C.Center + d)
end

-- how high a flat marker covering these spots must sit to show above all of them
local function markerY(...)
	local y = -math.huge
	for _, p in ipairs({ ... }) do
		y = math.max(y, sandAt(p).Y)
	end
	return y + 0.12
end

-- a flat marker on the sand (a slam ring, a charge strip, a landing square).
-- These go in the dummy's own effects folder, not the dummy itself: moving a
-- model moves everything inside it, and the ring mustn't hop with the dummy.
-- (The folder carries the owner too, so only they see it.)
local function marker(e, shape, size, cf, color)
	local p = Instance.new("Part")
	p.Name = "Warning"
	if shape == "ring" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(228, 59, 68)
	p.Material = Enum.Material.Neon
	p.Transparency = 0.55
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = e.fx
	return p
end

-- A puff flying out round a dummy's feet (landing, slamming): straw, or
-- whatever colour it's given. `into` is the dummy's effects folder, and
-- `count` how many bits fly (18 unless it's given more).
strawPuff = function(into, at, color, count)
	local puff = Instance.new("Part")
	puff.Transparency = 1
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Size = Vector3.new(0.2, 0.2, 0.2)
	puff.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0))
	puff.Parent = into
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(color or Color3.fromRGB(228, 166, 114))
	p.Size = NumberSequence.new(1.2, 0)
	p.Lifetime = NumberRange.new(0.3, 0.5)
	p.Speed = NumberRange.new(14, 20)
	p.SpreadAngle = Vector2.new(80, 10)
	p.Rate = 0
	p.Parent = puff
	p:Emit(count or 18)
	Debris:AddItem(puff, 1)
end

-- A knock-back that can't throw you into the stands: near the wall, the part
-- of the push that points outwards is turned back towards the middle.
local function safePush(player, vel)
	local root = rootOf(player)
	if not root then
		return vel
	end
	local out = flat(root.Position - C.Center)
	local edge = out.Magnitude - (C.Radius - 22)
	if edge > 0 and out.Magnitude > 0.1 then
		local n = out.Unit
		local outward = vel.X * n.X + vel.Z * n.Z
		if outward > 0 then
			-- (the closer to the wall, the more of it bounces back inwards)
			local k = math.min(1, edge / 12)
			vel = vel - n * outward * (1 + k)
		end
	end
	return vel
end

-- hurts the dummy's owner if they're within `radius` of `at` (and not
-- rolling: CombatService decides that), throwing them away from it
local function hurtNear(s, at, radius, share, push)
	local root, hum = rootOf(s.player)
	if root and sessions[s.player] == s and (flat(root.Position - at)).Magnitude <= radius then
		local away = flat(root.Position - at)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
		CombatService.DamagePlayer(s.player, hum.MaxHealth * dmg(s, share), at, safePush(s.player, away * (push or 40) + Vector3.new(0, 26, 0)))
		return true
	end
	return false
end

-- A slam: a red ring on the sand, a short hop, and down it comes.
local function slam(s, e, tell)
	local model = e.model
	local at = feet(model).Position
	local range = e.slamRange or C.SlamRange * (e.scale or 1)
	local ring = marker(e, "ring", Vector3.new(0.15, range * 2, range * 2),
		CFrame.new(at.X, markerY(at, at + Vector3.new(range, 0, 0), at - Vector3.new(range, 0, 0), at + Vector3.new(0, 0, range), at - Vector3.new(0, 0, range)), at.Z)
			* CFrame.Angles(0, 0, math.pi / 2))

	-- the wind-up: it crouches and shakes
	tell = tell or C.SlamTell
	local base = feet(model)
	local t0 = os.clock()
	while os.clock() - t0 < tell do
		if not e.alive then
			ring:Destroy()
			return
		end
		local k = (os.clock() - t0) / tell
		ring.Transparency = 0.55 - 0.3 * k
		place(model, base * CFrame.new((rng:NextNumber() - 0.5) * 0.4, -0.6 * k, 0))
		task.wait(1 / 20)
	end
	-- up...
	local t1 = os.clock()
	while os.clock() - t1 < 0.28 and e.alive do
		local k = (os.clock() - t1) / 0.28
		place(model, base * CFrame.new(0, math.sin(k * math.pi) * 4, 0))
		task.wait(1 / 30)
	end
	ring:Destroy()
	if not e.alive then
		return
	end
	-- ...and down: anyone standing in the ring gets squashed
	place(model, base)
	hurtNear(s, at, range + 1, e.slamDamage or C.SlamDamage)
	strawPuff(e.fx, at, e.puff, e.king and 40 or nil)
	if e.king then
		send(s.player, "KingFx", "Land", at, 0.8)
	else
		sfx(s, "Slam", at)
	end
end

-- One hop towards `dest`, in an arc, turning to face the player.
local function hop(e, dest, faceTo)
	local model = e.model
	local from = feet(model).Position
	local t0 = os.clock()
	local time = (e.hopTime or C.HopTime) * (e.slow or 1)
	local height = e.hopHeight or C.HopHeight
	while e.alive do
		local k = math.min(1, (os.clock() - t0) / time)
		local p = from:Lerp(dest, k) + Vector3.new(0, 4 * k * (1 - k) * height, 0)
		local look = flat(faceTo - p)
		local cf = look.Magnitude > 0.1 and CFrame.lookAt(p, p + look) or CFrame.new(p)
		place(model, cf)
		if k >= 1 then
			break
		end
		task.wait(1 / 30)
	end
end

-- THE BRUTE'S CHARGE: a red strip shows where it'll run, it lowers its
-- head and paws the sand... then thunders straight down the strip.
local function charge(s, e, target)
	local CH = C.Charge
	local model = e.model
	local start = feet(model).Position
	local dir = flat(target - start)
	if dir.Magnitude < 1 then
		return
	end
	dir = dir.Unit
	-- (as far as it can go down that line without leaving the sand - stopping
	-- a little short of the edge, as it leans into the charge)
	local rel = flat(start - C.Center)
	local along = rel:Dot(dir)
	local room = along * along - (rel.Magnitude ^ 2 - (C.Radius - 1.5) ^ 2)
	local len = math.min(CH.Length, -along + math.sqrt(math.max(0, room)))
	if len < 6 then
		return
	end
	local stop = sandAt(start + dir * len)
	local face = CFrame.lookAt(start, start + dir)
	local mid = start:Lerp(stop, 0.5)
	local y = markerY(start, start:Lerp(stop, 0.25), mid, start:Lerp(stop, 0.75), stop)
	local strip = marker(e, "block", Vector3.new(CH.Width, 0.15, len),
		CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(stop.X, y, stop.Z)))
	-- the wind-up: rears back, shaking
	local t0 = os.clock()
	while os.clock() - t0 < CH.Tell do
		if not e.alive then
			strip:Destroy()
			return
		end
		local k = (os.clock() - t0) / CH.Tell
		strip.Transparency = 0.55 - 0.3 * k
		local back = face * CFrame.new((rng:NextNumber() - 0.5) * 0.5, 0, 0.8 * k)
		if flat(back.Position - C.Center).Magnitude > C.Radius then
			back = face -- (at the edge of the sand: no rearing back off it)
		end
		place(model, back * CFrame.Angles(-0.25 * k, 0, 0))
		task.wait(1 / 20)
	end
	-- the charge
	sfx(s, "Charge", start)
	local hit = false
	local t1 = os.clock()
	local time = len / CH.Speed
	while e.alive do
		local k = math.min(1, (os.clock() - t1) / time)
		local p = start:Lerp(stop, k)
		place(model, CFrame.lookAt(p, p + dir) * CFrame.Angles(-0.2, 0, 0)) -- (head down)
		if not hit then
			local root, hum = rootOf(s.player)
			if root then
				-- (how far you are from its path, and whether it's reached you yet)
				local rel = flat(root.Position - start)
				local along = rel:Dot(dir)
				local side = (rel - dir * along).Magnitude
				if side <= CH.Width / 2 + 1.5 and along >= len * k - 3 and along <= len * k + 2 then
					hit = true
					CombatService.DamagePlayer(s.player, hum.MaxHealth * dmg(s, CH.Damage), p, safePush(s.player, dir * 60 + Vector3.new(0, 30, 0)))
				end
			end
		end
		if k >= 1 then
			break
		end
		task.wait(1 / 30)
	end
	strip:Destroy()
	if e.alive then
		place(model, CFrame.lookAt(stop, stop + dir))
		strawPuff(e.fx, stop, e.puff)
		task.wait(0.45) -- (winded: your chance to hit it)
	end
end

-- THE SLINGER'S HAY BALE: a red square marks where you're standing, it
-- winds up, and lobs a bale in a high arc. Move before it lands.
local function throw(s, e, target)
	local TH = C.Throw
	local model = e.model
	local from = feet(model).Position
	local at = sandAt(target)
	local face = flat(at - from)
	face = face.Magnitude > 0.1 and face.Unit or Vector3.new(0, 0, 1)
	local R = TH.Radius
	local square = marker(e, "block", Vector3.new(R * 2, 0.15, R * 2), CFrame.new(at.X,
		markerY(at, at + Vector3.new(R, 0, R), at + Vector3.new(-R, 0, R), at + Vector3.new(R, 0, -R), at - Vector3.new(R, 0, R)), at.Z))
	-- the wind-up: leans back with the sling
	local t0 = os.clock()
	while os.clock() - t0 < TH.Tell do
		if not e.alive then
			square:Destroy()
			return
		end
		local k = (os.clock() - t0) / TH.Tell
		place(model, CFrame.lookAt(from, from + face) * CFrame.Angles(0.3 * k, 0, 0))
		task.wait(1 / 20)
	end
	place(model, CFrame.lookAt(from, from + face))
	-- the bale, in a high arc
	sfx(s, "Throw", from)
	local bale = Instance.new("Part")
	bale.Name = "HayBale"
	bale.Size = Vector3.new(2.6, 1.8, 1.8)
	bale.Color = Color3.fromRGB(254, 231, 97)
	bale.Material = Enum.Material.SmoothPlastic
	bale.Anchored = true
	bale.CanCollide = false
	bale.CanQuery = false
	bale.CanTouch = false
	bale.Parent = e.fx
	local startP = from + Vector3.new(0, 7, 0)
	local t1 = os.clock()
	while true do
		local k = math.min(1, (os.clock() - t1) / TH.Flight)
		local p = startP:Lerp(at + Vector3.new(0, 0.9, 0), k) + Vector3.new(0, 4 * k * (1 - k) * 16, 0)
		bale.CFrame = CFrame.new(p) * CFrame.Angles(k * 6, k * 3, 0)
		square.Transparency = 0.55 - 0.3 * k
		if k >= 1 then
			break
		end
		task.wait(1 / 30)
	end
	square:Destroy()
	bale:Destroy()
	hurtNear(s, at, TH.Radius + 0.5, TH.Damage, 30)
	sfx(s, "HayLand", at)
	strawPuff(e.fx, at)
end

-- THE CURSED DUMMY'S BLINK: it shudders, vanishes in a burst of purple...
-- and reappears right behind you, already winding up a slam.
local function blink(s, e)
	local BL = C.Blink
	local model = e.model
	local from = feet(model)
	-- (while it blinks your lock-on lets go of it - CombatClient - so the
	-- camera never whips round after it)
	model:SetAttribute("Blinking", true)
	local t0 = os.clock()
	while os.clock() - t0 < BL.Tell do
		if not e.alive then
			model:SetAttribute("Blinking", nil)
			return
		end
		place(model, from * CFrame.new((rng:NextNumber() - 0.5) * 0.8, 0, (rng:NextNumber() - 0.5) * 0.8))
		task.wait(1 / 20)
	end
	strawPuff(e.fx, from.Position, e.puff)
	sfx(s, "Blink", from.Position)
	place(model, from + Vector3.new(0, -80, 0)) -- (gone)
	task.wait(0.35)
	local root = rootOf(s.player)
	if not (root and e.alive) then
		if e.alive then
			place(model, from)
		end
		model:SetAttribute("Blinking", nil)
		return
	end
	local back = flat(root.CFrame.LookVector)
	back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
	local spot = inArena(root.Position - back * BL.Behind)
	local look = flat(root.Position - spot)
	place(model, CFrame.lookAt(spot, spot + (look.Magnitude > 0.1 and look or back)))
	strawPuff(e.fx, spot, e.puff)
	sfx(s, "Blink", spot)
	model:SetAttribute("Blinking", nil) -- (back: it can be locked onto again)
	slam(s, e, BL.SlamTell)
end

----------------------------------------------------------------------
-- THE GIANT STRAW KING (the boss wave: every Config.Colosseum.King.Every waves)
----------------------------------------------------------------------
local INK = Color3.fromRGB(24, 20, 37)

-- how many of the King's minions are on the sand right now
local function minionCount(s)
	local n = 0
	for _, oe in pairs(s.enemies) do
		if oe.minion then
			n = n + 1
		end
	end
	return n
end

-- how high the player's body is above the sand (to tell when they jump)
local function heightAboveSand(root)
	return root.Position.Y - sandAt(root.Position).Y
end

-- THE SHOCKWAVE: a ring of chunky red and gold blocks rolling out across the
-- sand from `at`, starting `from` studs out, until it's W.WaveReach wide.
-- It's a real wall: touch it with your feet on the sand - from the front, or
-- backing into it - and it hurts (again, if you touch it again after
-- W.ReHit seconds). Jump over it, or roll through it. `spareUntil`: until
-- then it leaves you alone (you were just squashed by his landing).
-- harmless = true: just for show (his entrance).
local function shockwave(s, e, at, from, W, harmless, spareUntil)
	local N = 24
	local H = W.WaveHeight
	local blocks = {}
	for i = 1, N do
		local b = Instance.new("Part")
		b.Name = "Shockwave"
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.Neon
		b.Color = (i % 2 == 0) and Color3.fromRGB(254, 174, 52) or Color3.fromRGB(228, 59, 68)
		b.Transparency = harmless and 0.6 or 0.15
		b.Size = Vector3.new(1, H, 1.4)
		b.CFrame = CFrame.new(at)
		b.Parent = e.fx
		blocks[i] = b
	end
	local lastHit, lastDodge = -math.huge, -math.huge
	local t0 = os.clock()
	while e.fx.Parent and sessions[s.player] == s do
		local r = from + (os.clock() - t0) * W.WaveSpeed
		if r > W.WaveReach then
			break
		end
		-- (moved 15 times a second: it rolls out in little 8-bit jumps)
		local width = 2 * math.pi * r / N + 0.3
		for i, b in ipairs(blocks) do
			local a = (i - 1) / N * math.pi * 2
			local p = at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local top = Vector3.new(p.X, sandAt(p).Y + H / 2, p.Z)
			b.Size = Vector3.new(width, H, 1.4)
			b.CFrame = CFrame.lookAt(top, Vector3.new(at.X, top.Y, at.Z))
		end
		local now = os.clock()
		if not harmless and e.alive and now >= (spareUntil or 0) and now - lastHit >= (W.ReHit or 1) then
			local root, hum = rootOf(s.player)
			-- touching it, and not in the air higher than most of it?
			if root and math.abs(flat(root.Position - at).Magnitude - r) <= 2.2
				and heightAboveSand(root) - (e.standHeight or 3) < H * 0.6 then
				if CombatService.IsInvulnerable(s.player) then
					-- (rolling through it: "Dodged!", once)
					if now - lastDodge > 0.6 then
						lastDodge = now
						CombatService.DamagePlayer(s.player, hum.MaxHealth * dmg(s, W.WaveDamage), at)
					end
				else
					lastHit = now
					-- (it tumbles you back over itself, so it doesn't carry you along)
					local toward = flat(at - root.Position)
					toward = toward.Magnitude > 0.1 and toward.Unit or Vector3.new(0, 0, 1)
					CombatService.DamagePlayer(s.player, hum.MaxHealth * dmg(s, W.WaveDamage), at, safePush(s.player, toward * 18 + Vector3.new(0, 34, 0)))
				end
			end
		end
		task.wait(1 / 15)
	end
	for _, b in ipairs(blocks) do
		b:Destroy()
	end
end

-- THE GROUND POUND: a red ring where you're standing. He crouches, leaps
-- high into the air and crashes down in it - then the shockwave rolls out
-- (two of them when he's angry). He's stuck in the sand for a moment after.
local function pound(s, e, target)
	local K = C.King
	local P = K.Pound
	local model = e.model
	local from = feet(model).Position
	local at = inArena(target, 8)
	local dir = flat(at - from)
	if dir.Magnitude < 0.5 then
		dir = flat(feet(model).LookVector)
	end
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, 1)
	local R = P.Radius
	local ring = marker(e, "ring", Vector3.new(0.15, R * 2, R * 2),
		CFrame.new(at.X, markerY(at, at + Vector3.new(R, 0, 0), at - Vector3.new(R, 0, 0), at + Vector3.new(0, 0, R), at - Vector3.new(0, 0, R)), at.Z)
			* CFrame.Angles(0, 0, math.pi / 2))
	model:SetAttribute("Move", "Pound")
	-- the wind-up: he crouches low, shaking
	local face = CFrame.lookAt(from, from + dir)
	local tell = P.Tell * (e.slow or 1)
	local t0 = os.clock()
	while os.clock() - t0 < tell do
		if not e.alive then
			ring:Destroy()
			return
		end
		local k = (os.clock() - t0) / tell
		ring.Transparency = 0.55 - 0.15 * k
		place(model, face * CFrame.new((rng:NextNumber() - 0.5) * 0.6, -1.5 * k, 0))
		task.wait(1 / 20)
	end
	-- the leap: up high and over... and down hard
	local t1 = os.clock()
	while e.alive do
		local k = math.min(1, (os.clock() - t1) / P.Air)
		local p = from:Lerp(at, k) + Vector3.new(0, 4 * k * (1 - k) * P.Height, 0)
		place(model, CFrame.lookAt(p, p + dir))
		ring.Transparency = 0.4 - 0.25 * k
		if k >= 1 then
			break
		end
		task.wait(1 / 30)
	end
	ring:Destroy()
	if not e.alive then
		return
	end
	-- THOOM
	place(model, CFrame.lookAt(at, at + dir))
	local squashed = hurtNear(s, at, R + 1, P.Damage, 55)
	local spareUntil = squashed and os.clock() + 1 or 0 -- (one hit at a time)
	strawPuff(e.fx, at, nil, 50)
	send(s.player, "KingFx", "Land", at, 1.3)
	-- a beat later the shockwave bursts out (two of them when he's angry):
	-- jump as he lands and you'll clear it
	local waves = e.rage and (K.RageWaves or 2) or 1
	task.delay(P.WaveDelay or 0, function()
		for w = 1, waves do
			if not e.alive or sessions[s.player] ~= s then
				break
			end
			task.spawn(shockwave, s, e, at, R, P, false, spareUntil)
			if w < waves then
				task.wait(K.RageGap or 0.5)
			end
		end
	end)
	-- stuck in the sand for a moment: your chance to hit him
	task.wait(P.Stuck)
	model:SetAttribute("Move", nil)
end

-- THE WHIRLWIND: a red circle shows round him while he winds up... then he
-- spins like a top and comes AFTER you (like the Valkyrie in Clash Royale),
-- straw whipping round the whole circle. Stay in it and it hits you again.
-- Run, or roll out of it. When he's angry it's faster. He's dizzy after.
local function whirlwind(s, e)
	local W = C.King.Spin
	local model = e.model
	local base = feet(model)
	local pos = base.Position
	local turn = base - base.Position -- (the way he faces as it starts)
	local R = W.Radius
	local function discAt(p)
		return CFrame.new(p.X, markerY(p, p + Vector3.new(R, 0, 0), p - Vector3.new(R, 0, 0), p + Vector3.new(0, 0, R), p - Vector3.new(0, 0, R)), p.Z)
			* CFrame.Angles(0, 0, math.pi / 2)
	end
	local disc = marker(e, "ring", Vector3.new(0.15, R * 2, R * 2), discAt(pos))
	model:SetAttribute("Move", "Spin")
	-- the wind-up: arms out, he twists back a little, shaking
	local tell = W.Tell * (e.slow or 1)
	local angle = 0
	local t0 = os.clock()
	while os.clock() - t0 < tell do
		if not e.alive then
			disc:Destroy()
			return
		end
		local k = (os.clock() - t0) / tell
		disc.Transparency = 0.55 - 0.25 * k
		angle = -0.5 * k * k
		place(model, base * CFrame.Angles(0, angle, 0) * CFrame.new((rng:NextNumber() - 0.5) * 0.4, 0, 0))
		task.wait(1 / 20)
	end
	send(s.player, "KingFx", "Spin", pos)
	-- straw bits whipping round the circle
	local bits = {}
	for i = 1, 12 do
		local b = Instance.new("Part")
		b.Name = "WhirlStraw"
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.SmoothPlastic
		b.Color = (i % 3 == 0) and Color3.fromRGB(184, 111, 80) or Color3.fromRGB(254, 231, 97)
		b.Size = Vector3.new(2.2, 0.5, 0.5)
		b.CFrame = CFrame.new(pos)
		b.Parent = e.fx
		bits[i] = b
	end
	local lastHit = -math.huge
	local t1 = os.clock()
	local last = t1
	while e.alive and sessions[s.player] == s do
		local t = os.clock()
		local dt = t - last
		last = t
		if t - t1 >= W.Time then
			break
		end
		angle = angle + dt * W.Turns * math.pi * 2 / W.Time
		local root, hum = rootOf(s.player)
		if root then
			local go = flat(root.Position - pos)
			local speed = e.rage and (W.RageChase or W.Chase) or W.Chase
			if go.Magnitude > 1 then
				pos = inArena(pos + go.Unit * math.min(go.Magnitude, speed * dt), 8)
			end
		end
		place(model, CFrame.new(pos) * turn * CFrame.Angles(0, angle, 0))
		disc.CFrame = discAt(pos)
		for i, b in ipairs(bits) do
			local a = -angle * 1.4 + (i / #bits) * math.pi * 2
			local r = R * (0.35 + 0.6 * ((i % 4) / 3))
			b.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.8 + (i % 3) * 1.1, math.sin(a) * r)) * CFrame.Angles(0, -a, 0.3)
		end
		-- anyone in the circle gets whipped (again every ReHit seconds they
		-- stay in it) - unless they're rolling
		if root and t - lastHit >= (W.ReHit or 1) and flat(root.Position - pos).Magnitude <= R + 0.5
			and not CombatService.IsInvulnerable(s.player) then
			lastHit = t
			local away = flat(root.Position - pos)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
			CombatService.DamagePlayer(s.player, hum.MaxHealth * dmg(s, W.Damage), pos, safePush(s.player, away * 50 + Vector3.new(0, 24, 0)))
		end
		task.wait(1 / 30)
	end
	disc:Destroy()
	for _, b in ipairs(bits) do
		b:Destroy()
	end
	-- dizzy: he wobbles on the spot for a moment (your chance to hit him)
	local here = CFrame.new(pos) * turn * CFrame.Angles(0, angle, 0)
	local t2 = os.clock()
	while e.alive and os.clock() - t2 < W.Dizzy do
		local k = (os.clock() - t2) / W.Dizzy
		place(model, here * CFrame.Angles(0, 0, math.sin(k * math.pi * 4) * 0.12 * (1 - k)))
		task.wait(1 / 20)
	end
	if e.alive then
		place(model, here)
	end
	model:SetAttribute("Move", nil)
end

-- SUMMON: he throws his arms up, shaking, straw swirling round him... and
-- straw minions drop out of the sky round you (their shadows show where).
local function summon(s, e)
	local S = C.King.Summon
	local model = e.model
	local base = feet(model)
	model:SetAttribute("Move", "Summon")
	send(s.player, "KingFx", "Summon", base.Position)
	local t0 = os.clock()
	while os.clock() - t0 < S.Tell do
		if not e.alive then
			return
		end
		local k = (os.clock() - t0) / S.Tell
		place(model, base * CFrame.new((rng:NextNumber() - 0.5) * 0.5, math.sin(k * math.pi) * 3, 0))
		if rng:NextNumber() < 0.35 then
			local a = rng:NextNumber() * math.pi * 2
			strawPuff(e.fx, base.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 7)
		end
		task.wait(1 / 20)
	end
	place(model, base)
	local root = rootOf(s.player)
	if root and e.alive and sessions[s.player] == s then
		local level = model:GetAttribute("Level") or 1
		local n = math.min(S.Count, S.Max - minionCount(s))
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local spot = inArena(root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(11, 18))
			spawnDummy(s, "Straw", spot, level, {
				minion = true,
				name = "Straw Minion",
				health = S.health,
				reward = S.reward,
				slot = a,
				delay = (i - 1) * 0.2,
			})
		end
		pushState(s.player, s)
	end
	model:SetAttribute("Move", nil)
end

-- At half health he gets ANGRY: his eyes glow red, he stamps and roars, and
-- from then on he's faster, his pound sends two shockwaves and his
-- whirlwind chases you.
local function getAngry(s, e)
	local K = C.King
	local model = e.model
	e.rage = true
	e.slow = K.RageSpeed
	model:SetAttribute("Phase", 2)
	send(s.player, "KingRage")
	local base = feet(model)
	send(s.player, "KingFx", "Roar", base.Position, 0.9)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "Eye" then
			p.Color = Color3.fromRGB(255, 0, 68)
			p.Material = Enum.Material.Neon
		end
	end
	local t0 = os.clock()
	while e.alive and os.clock() - t0 < 1 do
		place(model, base * CFrame.new((rng:NextNumber() - 0.5) * 0.9, 0, (rng:NextNumber() - 0.5) * 0.9))
		task.wait(1 / 20)
	end
	if e.alive then
		place(model, base)
		strawPuff(e.fx, base.Position, nil, 40)
	end
end

-- What the King does: his entrance, then his moves until he's beaten.
local function kingBrain(s, e)
	local K = C.King
	local model = e.model
	-- 1) THE ENTRANCE: a huge shadow grows on the sand, he crashes down out
	-- of the sky, and stands roaring while your screen introduces him (he
	-- can't be hurt until the fight starts).
	local start = e.land or feet(model)
	local land = start.Position
	local turn = start - start.Position
	local shadow = marker(e, "ring", Vector3.new(0.1, 1, 1), CFrame.new(land), INK)
	shadow.Material = Enum.Material.SmoothPlastic
	for k = 1, 12 do -- (grows in chunky 8-bit steps)
		local d = (1 + k * 1.1) * e.scale
		shadow.Size = Vector3.new(0.1, d, d)
		shadow.CFrame = CFrame.new(land + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		shadow.Transparency = 0.8 - k * 0.03
		task.wait(0.1)
	end
	local t0 = os.clock()
	while e.alive and os.clock() - t0 < 0.4 do
		local k = (os.clock() - t0) / 0.4
		place(model, CFrame.new(land + Vector3.new(0, 140 * (1 - k * k), 0)) * turn)
		task.wait(1 / 30)
	end
	shadow:Destroy()
	if not e.alive then
		return
	end
	place(model, CFrame.new(land) * turn)
	strawPuff(e.fx, land, nil, 60)
	send(s.player, "KingFx", "Land", land, 1.6)
	task.spawn(shockwave, s, e, land, 6, K.Pound, true) -- (just for show)
	for k = 1, 8 do -- (a heavy bounce)
		place(model, CFrame.new(land + Vector3.new(0, math.sin(k / 8 * math.pi) * 3, 0)) * turn)
		task.wait(1 / 30)
	end
	-- he turns to you and roars while the introduction plays
	local root = rootOf(s.player)
	local look = root and flat(root.Position - land)
	local face = (look and look.Magnitude > 0.5) and CFrame.lookAt(land, land + look) or CFrame.new(land) * turn
	place(model, face)
	model:SetAttribute("State", "Waking")
	send(s.player, "KingFx", "Roar", land, 0.6)
	local t1 = os.clock()
	while e.alive and sessions[s.player] == s and os.clock() - t1 < K.IntroTime do
		place(model, face * CFrame.new((rng:NextNumber() - 0.5) * 0.5, 0, 0))
		task.wait(1 / 20)
	end
	if not e.alive or sessions[s.player] ~= s then
		return
	end
	place(model, face)
	model:SetAttribute("Invulnerable", nil)
	model:SetAttribute("State", "Fighting")
	-- (on a difficulty where he's angry from the start - Nightmare - he flies
	-- into his rage straight away)
	if s.diff and s.diff.angry and not e.rage then
		getAngry(s, e)
	end

	-- 2) THE FIGHT
	local function cooldown(range)
		return os.clock() + rng:NextNumber(range[1], range[2]) * (e.slow or 1)
	end
	local ready = {
		pound = os.clock() + rng:NextNumber(0.5, 1.5),
		spin = os.clock() + rng:NextNumber(2, 4),
		summon = cooldown(K.Summon.Cooldown),
	}
	local marks = table.clone(K.Summon.At or {}) -- (he summons as his health drops past each of these)
	while e.alive and sessions[s.player] == s do
		task.wait(rng:NextNumber(K.Rest[1], K.Rest[2]) * (e.slow or 1))
		if not e.alive or sessions[s.player] ~= s then
			break
		end
		root = rootOf(s.player)
		if not root then
			break
		end
		-- (how high the player stands when on the sand: for telling a jump)
		e.standHeight = math.max(1.5, math.min(e.standHeight or 3, heightAboveSand(root)))
		local share = (model:GetAttribute("Health") or 0) / math.max(1, model:GetAttribute("MaxHealth") or 1)
		local pos = feet(model).Position
		local to = flat(root.Position - pos)
		local dist = to.Magnitude
		local t = os.clock()
		local wantSummon = t >= ready.summon or (#marks > 0 and share <= marks[1])
		local canSpin = dist <= K.Spin.Range and t >= ready.spin
		local canPound = dist >= K.Pound.Range[1] and dist <= K.Pound.Range[2] and t >= ready.pound
		if canSpin and canPound then
			-- (both ready: either, so you never know which is coming)
			if rng:NextNumber() < 0.5 then
				canSpin = false
			else
				canPound = false
			end
		end
		if not e.rage and share <= K.Rage then
			getAngry(s, e)
		elseif wantSummon and minionCount(s) < K.Summon.Max then
			while #marks > 0 and share <= marks[1] do
				table.remove(marks, 1)
			end
			summon(s, e)
			ready.summon = cooldown(K.Summon.Cooldown)
		elseif canSpin then
			whirlwind(s, e)
			ready.spin = cooldown(K.Spin.Cooldown)
		elseif canPound then
			pound(s, e, root.Position)
			ready.pound = cooldown(K.Pound.Cooldown)
		elseif dist <= e.slamRange + 2 then
			model:SetAttribute("Move", "Slam")
			slam(s, e, K.SlamTell * (e.slow or 1))
			model:SetAttribute("Move", nil)
		else
			-- big bounding hops after you (each landing shakes the ground)
			model:SetAttribute("Move", "Hop")
			local dest = inArena(pos + to.Unit * math.min(K.HopReach, math.max(4, dist - 10)), 8)
			hop(e, dest, root.Position)
			if e.alive then
				strawPuff(e.fx, dest, nil, 24)
				send(s.player, "KingFx", "Step", dest, 0.35)
			end
			model:SetAttribute("Move", nil)
		end
	end
end

----------------------------------------------------------------------
-- Every other dummy
----------------------------------------------------------------------
-- What one dummy does, over and over, until it's beaten (or you leave)
local function brain(s, e)
	-- Spawning in: a shadow grows on the sand where it'll land, then it
	-- drops out of the sky, lands with a puff and bounces.
	local start = e.land or feet(e.model)
	local land = start.Position
	local turn = start - start.Position
	place(e.model, CFrame.new(land + Vector3.new(0, PARKED, 0)) * turn) -- (still up out of sight)
	local shadow = marker(e, "ring", Vector3.new(0.1, 1, 1), CFrame.new(land), Color3.fromRGB(24, 20, 37))
	shadow.Material = Enum.Material.SmoothPlastic
	for k = 1, 8 do -- (grows in chunky 8-bit steps)
		local d = (1 + k * 0.6) * (e.scale or 1)
		shadow.Size = Vector3.new(0.1, d, d)
		shadow.CFrame = CFrame.new(land + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		shadow.Transparency = 0.75 - k * 0.04
		task.wait(0.07)
	end
	local t0 = os.clock()
	while e.alive and os.clock() - t0 < 0.35 do
		local k = (os.clock() - t0) / 0.35
		place(e.model, CFrame.new(land + Vector3.new(0, 50 * (1 - k * k), 0)) * turn)
		task.wait(1 / 30)
	end
	shadow:Destroy()
	if e.alive then
		place(e.model, CFrame.new(land) * turn)
		strawPuff(e.fx, land, e.puff)
		sfx(s, "Land", land)
		-- a little bounce
		for k = 1, 6 do
			place(e.model, CFrame.new(land + Vector3.new(0, math.sin(k / 6 * math.pi) * 1.6, 0)) * turn)
			task.wait(1 / 30)
		end
		place(e.model, CFrame.new(land) * turn)
	end
	local nextSpecial = os.clock() + rng:NextNumber(1, 3) -- (a charge, a blink...)
	while e.alive and sessions[s.player] == s do
		task.wait(rng:NextNumber(C.Rest[1], C.Rest[2]) * (e.slow or 1))
		if not e.alive or sessions[s.player] ~= s then
			break
		end
		local root = rootOf(s.player)
		if not root then
			break
		end
		local pos = feet(e.model).Position
		local to = flat(root.Position - pos)
		local dist = to.Magnitude
		-- too close to another dummy? hop apart first (they never stack up)
		local push = Vector3.zero
		for other, oe in pairs(s.enemies) do
			if other ~= e.model and other.Parent then
				-- (bigger kinds need more room: a Knight's shield and a Brute's fists)
				local gap = 3.4 * ((e.scale or 1) + (oe.scale or 1))
				local d = flat(pos - feet(other).Position)
				if d.Magnitude < gap then
					push += (d.Magnitude > 0.1 and d.Unit or Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit) * (gap - d.Magnitude)
				end
			end
		end
		local ready = os.clock() >= nextSpecial
		if push.Magnitude > 0.5 then
			hop(e, inArena(pos + push.Unit * math.max(4, push.Magnitude)), root.Position)
		elseif e.kind == "Brute" and ready and dist >= C.Charge.Range[1] and dist <= C.Charge.Range[2] then
			charge(s, e, root.Position)
			nextSpecial = os.clock() + rng:NextNumber(2.5, 4.5)
		elseif e.kind == "Cursed" and ready and dist > C.SlamRange then
			blink(s, e)
			nextSpecial = os.clock() + rng:NextNumber(3.5, 6)
		elseif e.kind == "Slinger" then
			-- keeps its distance: backs off if you're close, throws from range
			if dist < C.Throw.Keep[1] then
				local away = dist > 0.1 and -to.Unit or Vector3.new(1, 0, 0)
				hop(e, inArena(pos + away * C.HopReach), root.Position)
			elseif dist > C.Throw.Keep[2] then
				hop(e, inArena(pos + to.Unit * math.min(C.HopReach, dist - C.Throw.Keep[2] + 4)), root.Position)
			else
				throw(s, e, root.Position)
			end
		elseif dist <= C.SlamRange * (e.scale or 1) then
			slam(s, e)
		else
			-- hop towards its own spot round you (each dummy has a different
			-- one), so they close in from all sides instead of piling up
			local slot = root.Position + Vector3.new(math.cos(e.slot), 0, math.sin(e.slot)) * 6.5 * (e.scale or 1)
			local go = flat(slot - pos)
			local dest = pos
			if go.Magnitude > 0.5 then
				dest = inArena(pos + go.Unit * math.min(C.HopReach * (e.reach or 1), go.Magnitude))
			end
			hop(e, dest, root.Position)
		end
	end
end

-- what each kind is like on the sand (the numbers are in Config.Colosseum)
local KIND = {
	Straw = {},
	Brute = { puff = Color3.fromRGB(115, 62, 57) },
	Slinger = {},
	Knight = { slow = 1.35, reach = 0.7, puff = Color3.fromRGB(139, 155, 180) }, -- (heavy: slower, shorter hops)
	Cursed = { puff = Color3.fromRGB(181, 80, 136) },
}
local TYPE_BY_ID = {}
for _, t in ipairs(C.Types or {}) do
	TYPE_BY_ID[t.id] = t
end

-- A random mix of the kinds you've unlocked, `count` of them
local function pickKinds(level, count)
	local open = {}
	for _, t in ipairs(C.Types or { { id = "Straw", level = 1, weight = 1 } }) do
		if level >= (t.level or 1) then
			table.insert(open, t)
		end
	end
	local kinds, used = {}, {}
	for _ = 1, count do
		local total = 0
		for _, t in ipairs(open) do
			if (used[t.id] or 0) < (t.max or math.huge) then
				total = total + (t.weight or 1)
			end
		end
		local pick, roll = "Straw", rng:NextNumber() * total
		for _, t in ipairs(open) do
			if (used[t.id] or 0) < (t.max or math.huge) then
				roll = roll - (t.weight or 1)
				if roll <= 0 then
					pick = t.id
					break
				end
			end
		end
		used[pick] = (used[pick] or 0) + 1
		table.insert(kinds, pick)
	end
	return kinds
end

-- One dummy onto the sand at `spot`, at `level`. `opts` can change it:
--   name, health, reward  (health and reward multiply a straw dummy's)
--   minion = true         (one of the King's: it crumbles when he falls)
--   slot                  (which side of you it closes in from)
--   delay                 (seconds before it drops in)
--   brain                 (what it does: the ordinary dummies' brain unless given)
--   attributes            (set on it before anything else can see it)
--   setup                 (a function that gets its fight table, to tweak it)
-- Gives back the model and its fight table (or nothing if it couldn't).
spawnDummy = function(s, kind, spot, level, opts)
	opts = opts or {}
	local root = rootOf(s.player)
	if not root then
		return nil
	end
	local T = TYPE_BY_ID[kind] or (kind == "King" and C.King) or { id = "Straw", name = "Straw Dummy", health = 1, reward = 1, scale = 1 }
	local template = ServerStorage:FindFirstChild(kind == "Straw" and "ColosseumDummy" or ("ColosseumDummy_" .. kind))
		or ServerStorage:FindFirstChild("ColosseumDummy")
	if not template then
		warn("[ColosseumService] No ColosseumDummy in ServerStorage - is LobbyBuilder up to date?")
		return nil
	end
	if not template:GetAttribute("Foot") then
		kind, T = "Straw", TYPE_BY_ID.Straw or T -- (an old LobbyBuilder: plain straw dummies only)
	end
	local rec = math.max(1, Config.powerForLevel(level))
	local D = s.diff or Config.colosseumDifficulty()
	local hp = math.max(1, math.floor(rec * C.HitsToKill * (opts.health or T.health or 1) * (D.health or 1)))
	local name = opts.name or T.name or "Straw Dummy"
	local scale = template:GetAttribute("Scale") or T.scale or 1
	local model = template:Clone()
	model.Name = name
	model:SetAttribute("DisplayName", name .. "  Lv." .. level)
	model:SetAttribute("Owner", s.player.UserId)
	model:SetAttribute("Level", level)
	model:SetAttribute("MaxHealth", hp)
	model:SetAttribute("Health", hp)
	model:SetAttribute("HitRadius", 2.6 * scale)
	model:SetAttribute("Kind", kind)
	for k, v in pairs(opts.attributes or {}) do
		model:SetAttribute(k, v)
	end
	-- its health bar floats just over its own head (a big Brute's higher up
	-- than a small Slinger's, so bunched-up bars don't all sit in one line)
	local body = model.PrimaryPart
	local okBox, boxCf, boxSize = pcall(model.GetBoundingBox, model)
	if body and okBox then
		model:SetAttribute("BarHeight", boxCf.Position.Y + boxSize.Y / 2 - body.Position.Y + 1.6)
	end
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = model
	-- it starts hidden high up in the sky (too high for its health bar to
	-- show, or to be punched) and only appears when it drops in: it must
	-- never stand on the sand first and then vanish (see brain / kingBrain)
	local look = flat(root.Position - spot)
	local land = CFrame.lookAt(spot, spot + (look.Magnitude > 0.1 and look or Vector3.new(0, 0, 1)))
	place(model, land + Vector3.new(0, PARKED, 0))
	model.Parent = enemyFolder
	CollectionService:AddTag(model, "CombatTarget")
	-- its warning rings, puffs and hay bales go in here (see marker)
	local fx = Instance.new("Folder")
	fx.Name = "DummyFX"
	fx:SetAttribute("Owner", s.player.UserId)
	fx.Parent = enemyFolder

	local K = KIND[kind] or {}
	local e = {
		model = model, fx = fx, alive = true, kind = kind, scale = scale, reward = opts.reward or T.reward or 1,
		land = land, -- (where it'll land when it drops in)
		-- (a harder difficulty's dummies wait and hop for less time; the King
		-- keeps his own pace)
		slow = (K.slow or 1) * (kind == "King" and 1 or (D.pace or 1)), reach = K.reach, puff = K.puff,
		slot = opts.slot or rng:NextNumber() * math.pi * 2,
		minion = opts.minion,
	}
	if opts.setup then
		opts.setup(e)
	end
	s.enemies[model] = e
	s.alive = s.alive + 1
	if kind == "Knight" then
		-- punches from the front just CLANG off its shield (CombatService
		-- checks), and it shoves you back with it: go round the back!
		model:SetAttribute("ShieldArc", C.ShieldArc or 110)
		place(model, feet(model)) -- (so it knows which way its front is)
		local onBlock = Instance.new("BindableEvent")
		onBlock.Name = "OnBlock"
		onBlock.Parent = model
		local lastBash = 0
		onBlock.Event:Connect(function()
			if e.alive then
				sfx(s, "Clang", feet(model).Position)
			end
			local r = rootOf(s.player)
			if e.alive and r and os.clock() - lastBash > 1 then
				lastBash = os.clock()
				local away = flat(r.Position - feet(model).Position)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
				CombatService.Shove(s.player, safePush(s.player, away * 45 + Vector3.new(0, 18, 0)))
			end
		end)
	end
	onHit.Event:Connect(function(_, _, killed)
		if killed and e.alive then
			e.alive = false
			s.enemies[model] = nil
			s.alive = s.alive - 1
			ColosseumService.OnKill(s, model, e)
		end
	end)
	local think = opts.brain or brain
	task.delay(opts.delay or 0, function()
		if e.alive then
			think(s, e)
		end
	end)
	return model, e
end

-- THE BOSS WAVE: the Giant Straw King, on his own. He lands well away from
-- you (in the middle, or across from you if you're near it).
local function spawnKing(s, level)
	local K = C.King
	local root = rootOf(s.player)
	if not root then
		return nil
	end
	local spot = C.Center
	local off = flat(root.Position - C.Center)
	if off.Magnitude < 36 then
		local away = off.Magnitude > 0.5 and -off.Unit or Vector3.new(1, 0, 0)
		spot = C.Center + away * 38
	end
	local model = spawnDummy(s, "King", sandAt(spot), level, {
		name = K.name,
		health = K.health,
		reward = K.reward,
		brain = kingBrain,
		-- (no bar over his head: he has a boss bar across the top of the
		-- screen instead; never out of sight for the lock-on; can't be hurt
		-- until his entrance is over)
		attributes = { NoBar = true, Boss = true, Invulnerable = true, State = "Arriving", Phase = 1 },
		setup = function(e)
			e.king = true
			e.hopTime, e.hopHeight = K.HopTime, K.HopHeight
			e.slamRange, e.slamDamage = K.SlamRange, K.SlamDamage
		end,
	})
	if model and CombatService.SetTargetShape then
		-- he's tall: a punch lands anywhere on him from the sand up to his
		-- head, judged from the middle of his body at your height
		CombatService.SetTargetShape(model, function(from)
			local base = feet(model).Position
			local y = math.clamp(from.Y, base.Y + 1, base.Y + footOf(model) * 1.9)
			return Vector3.new(base.X, y, base.Z), model:GetAttribute("HitRadius") or 6
		end)
	end
	return model
end

local warnedKing = false
local function spawnWave(s)
	local root = rootOf(s.player)
	if not root then
		return
	end
	s.wave = s.wave + 1
	if s.wave == 1 then
		s.runStart = os.clock() -- (a run's clock starts as its first wave comes in)
	end
	if s.wave == 1 or not runLength() then
		s.diff = pickedDifficulty(s.player) -- (a run keeps the difficulty it started on)
	end
	local level = math.max(2, playerLevel(s.player))
	-- every few waves, THE BOSS WAVE
	local K = C.King
	s.bossWave = false
	if K and K.Every and s.wave % K.Every == 0 then
		if ServerStorage:FindFirstChild("ColosseumDummy_King") then
			if spawnKing(s, level) then
				s.bossWave = true
				send(s.player, "BossWave", s.wave)
				pushState(s.player, s)
				return
			end
		elseif not warnedKing then
			warnedKing = true
			warn("[ColosseumService] No ColosseumDummy_King in ServerStorage - is LobbyBuilder up to date? (normal waves until it is)")
		end
	end
	local count = math.min(C.WaveSize[1] + s.wave - 1, C.WaveSize[2]) + ((s.diff and s.diff.extra) or 0)
	local kinds = pickKinds(level, count)
	for i = 1, count do
		-- somewhere on the sand, not right on top of you
		local spot
		for _ = 1, 12 do
			local a = rng:NextNumber() * math.pi * 2
			local r = rng:NextNumber(12, C.Radius - 12)
			spot = sandAt(C.Center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			if (flat(spot - root.Position)).Magnitude > 22 then
				break
			end
		end
		local model = spawnDummy(s, kinds[i], spot, level, {
			slot = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3),
			delay = (i - 1) * 0.25,
		})
		if not model then
			break
		end
	end
	send(s.player, "Wave", s.wave)
	pushState(s.player, s)
end

-- A dummy was beaten: pay out, and once the sand is clear count the wave for
-- the quest and bring on the next one.
local function crumble(model, e)
	if e and e.king and CombatService.SetTargetShape then
		CombatService.SetTargetShape(model, nil) -- (forget his hit shape)
	end
	CollectionService:RemoveTag(model, "CombatTarget")
	pcall(CombatService.Disintegrate, model, { Color = Color3.fromRGB(254, 174, 52) })
	Debris:AddItem(model, 2.5)
	if e then
		Debris:AddItem(e.fx, 1.5) -- (lets its last puff finish)
	end
end

function ColosseumService.OnKill(s, model, e)
	local player = s.player
	crumble(model, e)
	if not (e and e.king) then
		sfx(s, "Poof", feet(model).Position) -- (the King has his own death sound)
	end

	local rewards = Config.colosseumRewards(playerLevel(player))
	-- (tougher kinds pay more: a Knight is worth 2.2 straw dummies; a kill
	-- streak adds its bonus on top; and a harder difficulty multiplies it all)
	s.streak = (s.streak or 0) + 1
	local mult = ((e and e.reward) or 1) * (1 + streakBonus(s.streak)) * ((s.diff and s.diff.reward) or 1)
	local killPower = math.max(1, math.floor(rewards.killPower * mult))
	local killCoins = math.max(1, math.floor(rewards.killCoins * mult))
	PlayerService.AddPower(player, killPower)
	PlayerService.AddCoins(player, killCoins)
	if PlayerService.QuestProgress then
		PlayerService.QuestProgress(player, "arena", 1)
	end
	-- (your screen shows what it paid, and the coins and XP fly into you:
	-- `worth` says how many - a Knight's shower is bigger than a minion's,
	-- and a Nightmare one bigger than a Normal one)
	local body = feet(model).Position + Vector3.new(0, 4 * ((e and e.scale) or 1), 0)
	send(player, "Kill", killPower, killCoins, feet(model).Position + Vector3.new(0, 11 * ((e and e.scale) or 1), 0), {
		from = body,
		worth = ((e and e.reward) or 1) * ((s.diff and s.diff.reward) or 1),
		king = (e and e.king) == true,
	})
	if C.Streak and s.streak % C.Streak.Every == 0 then
		send(player, "Streak", s.streak, streakBonus(s.streak)) -- ("x10 STREAK! +20%")
	end
	if e and e.king then
		-- THE KING FALLS: his minions crumble with him (they pay nothing),
		-- and your screen celebrates
		model:SetAttribute("State", "Dead")
		for other, oe in pairs(s.enemies) do
			if oe.minion then
				oe.alive = false
				s.enemies[other] = nil
				s.alive = s.alive - 1
				crumble(other, oe)
			end
		end
		send(player, "KingDown", killPower, killCoins)
		send(player, "KingFx", "Death", feet(model).Position, 1)
	end

	-- the sand is clear: the wave counts for the quest (BEAT 5 WAVES)
	local waveDone = s.alive <= 0 and sessions[player] == s
	local runDone = waveDone and e and e.king and runLength() ~= nil
	if waveDone then
		s.questWaves = (s.questWaves or 0) + 1
		-- (a run's quest is paid on the CLEARED screen - FinishRun. Without
		-- runs, or if the quest is shorter than a run, it's paid right here
		-- and starts over.)
		if s.questWaves >= (C.QuestWaves or 5) and not runDone then
			s.questWaves = 0
			local qp, qc = ColosseumService.PayQuest(s)
			send(player, "QuestDone", qp, qc)
		end
	end
	pushState(player, s)

	-- the King fell on the last wave: the run is CLEARED
	if runDone then
		ColosseumService.FinishRun(s)
		return
	end
	if waveDone then
		send(player, "WaveClear", s.wave) -- (the crowd throws confetti)
		-- (after the King, a longer pause to enjoy it)
		task.delay((e and e.king and C.King.WaveBreak) or C.WaveBreak, function()
			if sessions[player] == s then
				spawnWave(s)
			end
		end)
	end
end

-- THE COLOSSEUM IS CLEARED: the run's time is saved (your best time and how
-- many runs you've cleared - PlayerService), the first clear of the day pays
-- a bonus, and your screen asks: RUN AGAIN or LEAVE? Nothing more happens
-- until you choose (or walk out through the exit gate).
function ColosseumService.FinishRun(s)
	local player = s.player
	s.cleared = true
	local diff = s.diff or Config.colosseumDifficulty()
	local pay = diff.reward or 1
	local seconds = math.floor(math.max(0, os.clock() - (s.runStart or os.clock())) * 10 + 0.5) / 10
	local info = { time = seconds, diff = diff.id }
	-- the quest (BEAT 5 WAVES) is done: paid now, shown on the CLEARED screen
	if (s.questWaves or 0) >= (C.QuestWaves or 5) then
		s.questWaves = C.QuestWaves or 5 -- (shows as done until the next run)
		info.questPower, info.questCoins = ColosseumService.PayQuest(s)
	end
	local rec = PlayerService.RecordColosseumClear and PlayerService.RecordColosseumClear(player, seconds, diff.id)
	if rec then
		info.best, info.newBest, info.clears, info.wins = rec.best, rec.newBest, rec.clears, rec.wins
		info.unlocked = rec.unlocked -- (a harder difficulty this clear opened)
		if rec.firstToday then
			local rewards = Config.colosseumRewards(playerLevel(player))
			local bp = math.max(1, math.floor(rewards.clearPower * pay))
			local bc = math.max(1, math.floor(rewards.clearCoins * pay))
			PlayerService.AddPower(player, bp)
			PlayerService.AddCoins(player, bc)
			info.bonusPower, info.bonusCoins = bp, bc
		end
	end
	send(player, "RunClear", info)
	pushState(player, s)
end

-- Pays the quest (BEAT 5 WAVES) at this run's difficulty. Gives back what it paid.
function ColosseumService.PayQuest(s)
	local rewards = Config.colosseumRewards(playerLevel(s.player))
	local pay = (s.diff and s.diff.reward) or 1
	local qp = math.max(1, math.floor(rewards.questPower * pay))
	local qc = math.max(1, math.floor(rewards.questCoins * pay))
	PlayerService.AddPower(s.player, qp)
	PlayerService.AddCoins(s.player, qc)
	return qp, qc
end

-- RUN AGAIN: healed, flasks refilled, and wave 1 comes in a moment later
-- (only between runs)
local function runAgain(player)
	local s = sessions[player]
	if not (s and s.cleared) then
		return false, "Finish the run first!"
	end
	s.cleared = false
	s.wave = 0
	s.questWaves = 0
	s.diff = pickedDifficulty(player) -- (the difficulty picked on the CLEARED screen)
	local _, hum = rootOf(player)
	if hum then
		hum.Health = hum.MaxHealth
	end
	if CombatService.RefillFlasks then
		CombatService.RefillFlasks(player)
	end
	send(player, "RunStart", s.diff.id)
	pushState(player, s)
	task.delay(2, function()
		if sessions[player] == s and not s.cleared and s.wave == 0 then
			spawnWave(s)
		end
	end)
	return true, "Here they come!"
end

----------------------------------------------------------------------
-- Going in and out
----------------------------------------------------------------------
local function endSession(player)
	local s = sessions[player]
	sessions[player] = nil
	if not s then
		return
	end
	if s.hurtConn then
		s.hurtConn:Disconnect()
	end
	for model, e in pairs(s.enemies) do
		e.alive = false
		if e.king and CombatService.SetTargetShape then
			CombatService.SetTargetShape(model, nil) -- (forget his hit shape)
		end
		model:Destroy()
		e.fx:Destroy()
	end
	s.enemies = {}
end

local going = {} -- [player] = true while they're going down the pipe

-- how long the trip down the pipe takes on the player's screen
local function pipeTime()
	return (C.ShrinkSteps or 8) * 0.07 + 0.4
end

-- Can the player go in right now? (Beside the little door, not already in
-- or on the way, not up the Spire.) Returns true, or false and why not.
local function canEnter(player)
	if sessions[player] then
		return false, "You're already in the Colosseum!"
	end
	if going[player] then
		return false, "Hold on, you're on your way!"
	end
	if player:GetAttribute("SpireFloor") then
		return false, "Not from here!"
	end
	local root = rootOf(player)
	if not (root and CollectionService:GetTagged("ColosseumSpawn")[1]) then
		return false, "Not ready yet."
	end
	if (flat(root.Position - C.GatePosition)).Magnitude > C.EnterRange + 10 then
		return false, "Walk up to the Colosseum's door first."
	end
	return true
end

local function enter(player)
	if not canEnter(player) then
		return
	end
	local root, _, char = rootOf(player)
	local spawnAt = CollectionService:GetTagged("ColosseumSpawn")[1]
	local door = CollectionService:GetTagged("ColosseumDoor")[1]
	-- Your own screen shrinks you into the little door and moves you inside
	-- (LobbyActivities). It has to be done there: your character is moved by
	-- your computer, and when the server moves it too, the two fight (that's
	-- what made the trip glitchy).
	going[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(spawnAt.Position, 3)
	end)
	local doorGround = door and groundBelow(door.Position, char) or root.Position
	local inside = groundBelow(spawnAt.Position, char)
	allowMove(player, inside, pipeTime() + 5) -- (their own screen makes this jump)
	send(player, "PipeIn", doorGround, spawnAt.CFrame, inside)
	task.wait(pipeTime())
	going[player] = nil
	if not rootOf(player) then
		return
	end
	-- (checked a moment later, once your screen's move has reached the server)
	task.delay(1.5, function()
		if sessions[player] then
			ensureAt(player, spawnAt.CFrame, C.Radius + 20)
		end
	end)
	local s = { player = player, wave = 0, alive = 0, questWaves = 0, enemies = {}, streak = 0, diff = pickedDifficulty(player) }
	sessions[player] = s
	-- getting hurt (by anything) ends your kill streak
	local _, hum = rootOf(player)
	if hum then
		local last = hum.Health
		s.hurtConn = hum.HealthChanged:Connect(function(h)
			if h < last - 0.01 and sessions[player] == s and (s.streak or 0) > 0 then
				local lost = s.streak
				s.streak = 0
				send(player, "StreakLost", lost)
				pushState(player, s)
			end
			last = h
		end)
	end
	player:SetAttribute("Colosseum", true)
	send(player, "Arrived")
	pushState(player, s)
	task.delay(2, function()
		if sessions[player] == s then
			spawnWave(s)
		end
	end)
end

local function leave(player)
	local s = sessions[player]
	if not s or going[player] then
		return
	end
	-- (only from the exit door: leaving heals you to full, so it mustn't work
	-- from the middle of a fight by firing the prompt from anywhere. Once a
	-- run is cleared there's no fight, so the LEAVE button works anywhere.)
	local exitPrompt = CollectionService:GetTagged("ColosseumExit")[1]
	local exitDoor = exitPrompt and exitPrompt.Parent
	local root = rootOf(player)
	if not root then
		return
	end
	if not s.cleared and exitDoor and exitDoor:IsA("BasePart") and (root.Position - exitDoor.Position).Magnitude > 32 then
		return
	end
	endSession(player)
	player:SetAttribute("Colosseum", nil)
	send(player, "Left")
	-- walking out heals you back to full
	local _, hum = rootOf(player)
	if hum then
		hum.Health = hum.MaxHealth
	end
	local back = CollectionService:GetTagged("ColosseumReturn")[1]
	if not back then
		return
	end
	-- out the way you came in: your screen pops you out of the little door tiny, growing
	going[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(back.Position, 3)
	end)
	local _, _, char = rootOf(player)
	local outside = groundBelow(back.Position, char)
	allowMove(player, outside, pipeTime() + 5) -- (their own screen makes this jump)
	send(player, "PipeOut", back.CFrame, outside)
	task.wait(pipeTime())
	going[player] = nil
	task.delay(1.5, function()
		if not sessions[player] and not player:GetAttribute("Colosseum") then
			ensureAt(player, back.CFrame, 60)
		end
	end)
end

-- Choosing the difficulty for the next run (the CLEARED screen's buttons;
-- the first run's is picked in the pop-up at the door, as you go in). It's
-- saved. A run keeps the difficulty it started on: a new pick mid-run waits
-- for the next one.
local function chooseDifficulty(player, id)
	local ok, why = PlayerService.SetColosseumPick(player, id)
	if not ok then
		return false, why or "Not ready yet."
	end
	local def = Config.colosseumDifficulty(id)
	local s = sessions[player]
	if not s then
		return true, def.name .. " it is!"
	end
	if s.wave == 0 and not s.cleared then
		s.diff = def -- (the first wave isn't in yet: it'll be on this)
	end
	pushState(player, s)
	if not s.cleared and s.wave > 0 and not (s.diff and s.diff.id == def.id) then
		return true, def.name .. " starts on your next run!"
	end
	return true, def.name .. " it is!"
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function ColosseumService.Start(combatService, playerService)
	CombatService = combatService
	PlayerService = playerService

	local old = ReplicatedStorage:FindFirstChild("ColosseumEvent")
	if old then
		old:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	-- server -> client: "PipeIn", "PipeOut", "Arrived", "Left", "State", "Wave", "Kill" (what it
	-- paid, and where its coins and XP fly from), "QuestDone" (without runs), "Sfx",
	-- for the boss wave "BossWave", "KingFx" (a sound and a shake), "KingRage", "KingDown",
	-- and for runs and streaks "RunClear", "RunStart" (and its difficulty), "Streak", "StreakLost"
	remote.Name = "ColosseumEvent"
	remote.Parent = ReplicatedStorage

	enemyFolder = workspace:FindFirstChild("ColosseumEnemies") or Instance.new("Folder")
	enemyFolder.Name = "ColosseumEnemies"
	enemyFolder:ClearAllChildren()
	enemyFolder.Parent = workspace

	local function hook(tag, fn)
		local function one(prompt)
			if prompt:IsA("ProximityPrompt") then
				prompt.Triggered:Connect(function(player)
					local ok, err = pcall(fn, player)
					if not ok then
						warn("[ColosseumService] " .. tag .. " failed: " .. tostring(err))
					end
				end)
			end
		end
		for _, p in ipairs(CollectionService:GetTagged(tag)) do
			one(p)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(one)
	end
	-- (the little door's prompt only opens the difficulty pop-up on your
	-- screen: going in is the "ColosseumEnter" action below)
	hook("ColosseumExit", leave)

	-- the RUN AGAIN / LEAVE buttons (asked through PlayerService's Action
	-- remote, so they get its request budget and checks too)
	if PlayerService.AddAction then
		PlayerService.AddAction("ColosseumAgain", function(player)
			return runAgain(player)
		end)
		PlayerService.AddAction("ColosseumLeave", function(player)
			local s = sessions[player]
			if not (s and s.cleared) or going[player] then
				return false, "Walk out through the exit gate."
			end
			task.spawn(leave, player)
			return true, "See you soon!"
		end)
		-- going in: the ENTER button of the pop-up at the little door, with
		-- the difficulty picked there (checked: it must be open to you)
		PlayerService.AddAction("ColosseumEnter", function(player, _, id)
			local ok, why = canEnter(player)
			if not ok then
				return false, why
			end
			if id ~= nil then
				if not PlayerService.SetColosseumPick then
					return false, "Not ready yet."
				end
				local picked, reason = PlayerService.SetColosseumPick(player, id)
				if not picked then
					return false, reason or "Not ready yet."
				end
			end
			task.spawn(enter, player)
			return true, "In you go!"
		end)
		-- and the CLEARED screen's difficulty buttons (for the next run)
		if PlayerService.SetColosseumPick then
			PlayerService.AddAction("ColosseumDifficulty", function(player, _, id)
				return chooseDifficulty(player, id)
			end)
		end
	end

	local function watch(player)
		-- dying in there: the fight ends, and your new body appears in the lobby
		player.CharacterAdded:Connect(function()
			if sessions[player] or player:GetAttribute("Colosseum") then
				endSession(player)
				player:SetAttribute("Colosseum", nil)
				send(player, "Left")
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		endSession(player)
		going[player] = nil
	end)

	-- (the dummies stop the moment you die, instead of beating on your body)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in pairs(sessions) do
				if not rootOf(player) then
					for _, e in pairs(s.enemies) do
						e.alive = false
					end
				end
			end
		end
	end)
end

return ColosseumService
