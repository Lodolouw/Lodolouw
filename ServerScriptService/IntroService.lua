--[[
	IntroService  (ModuleScript, parent: ServerScriptService, name: "IntroService")

	A brand-new player's first minute: OOZLET, Oozark's little one. (What it
	looks like - the dark, the mist, the big words, the lobby building itself
	at the end - is all IntroClient, on that player's screen only. This
	script decides everything that matters, so nobody can fake it.)

	  * WHO GETS IT: only brand-new players - beating it is saved
	    (PlayerService: IntroDone). In Studio it never starts by itself
	    unless Config.Intro.InStudio is on (the dev console's "Replay Intro"
	    plays it any time).
	  * They wake up by the fountain (Config.Intro.SpawnAt) with the "Intro"
	    attribute set, which says where they are in it:
	        "Void"   - it's dark; Oozlet is happily hopping round the fountain
	        "Fight"  - they punched it: it's angry
	        "Reveal" - it popped: the mist rolls back to show the lobby
	        (nil)    - it's over (or they never had it)
	    ("IntroChecked" = true once we've decided, so their screen knows.)
	  * OOZLET is only theirs: it carries their UserId (Owner), so nobody
	    else can hit it, and nobody else's screen draws it. Here it's just an
	    invisible box to punch; its hops are sent as numbers (HopFrom, HopTo,
	    HopAt, HopTime, HopHeight) and its moves as Action/ActionAt/ActionPos/
	    ActionR/ActionTell, so their screen draws it smoothly however laggy
	    the connection.
	  * HOW IT GOES:
	      - Happy: little hops round the fountain. Stand still too long and it
	        hops over and bumps you (no harm).
	      - Punch it and it wakes up ANGRY.
	      - Its first slam is the lesson: it leaps up over you and HANGS in the
	        air above a red circle (it can't be hit up there) until you ROLL -
	        walk away and it just drifts over you again. Then it drops, and
	        it's dizzy: hit it! (After a while it gives up and drops anyway.)
	      - Then it hops after you and slams when you're close (a red circle
	        fills round it, then it lands).
	      - At half health it CRACKS: it can't be hurt for a moment, its shell
	        bursts (pushing you back, no harm), and it gets faster - and
	        sometimes bounces at you three times, each landing in a small red
	        circle.
	      - It can never take you below Floor of your health: you can't lose.
	      - It pops: a chest with an Arcade Token in it and some coins straight
	        away; and once the lobby has been revealed, enough Power to be at
	        least Reward.Level (so the LEVEL UP shows on the screen that's just
	        come back).
	  * Punching, rolling and everything else is CombatService's, as in any
	    fight - on while "Intro" is "Void" or "Fight" (stamina is free there).
	All the numbers are in Config.Intro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local IntroService = {}

local I = Config.Intro or {}
local O = I.Oozlet or {}
local CENTER = I.Center or Vector3.new(0, 0, 0)
local LIMIT = (I.Radius or 23.5) - 2.5 -- Oozlet stays on the plaza, this far from the middle
local CombatService, PlayerService -- (set in Start)
local sessions = {} -- [player] = their intro
local folder -- where everyone's Oozlet lives (invisible boxes: IntroClient draws them)
local remote -- IntroEvent: server -> client, the moments the big words react to
local rng = Random.new()

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
-- the clock both sides share (a hop sent at this time is drawn from it)
local function now()
	return workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root and hum.Health > 0) then
		return nil
	end
	return root, hum
end

-- a phase-two number once it has cracked (Config.Intro.Oozlet.Cracked), or the usual one
local function stat(S, key)
	local cracked = S.cracked and O.Cracked
	if cracked and cracked[key] ~= nil then
		return cracked[key]
	end
	return O[key]
end

local function send(S, kind, ...)
	if remote and S.player.Parent then
		remote:FireClient(S.player, kind, ...)
	end
end

-- The top of the floor at (x, z): where Oozlet lands (the plaza, the
-- fountain's rim, the basin...)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local function groundAt(x, z)
	local skip = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, CENTER.Y + 30, z), Vector3.new(0, -60, 0), rayParams)
	return Vector3.new(x, hit and hit.Position.Y or (CENTER.Y + 0.8), z)
end

-- a spot pulled back onto the plaza if it's off it
local function onPlaza(p)
	local d = flat(p - CENTER)
	if d.Magnitude > LIMIT then
		d = d.Unit * LIMIT
	end
	return CENTER + d
end

-- which way to throw someone standing at `at`, away from `from`
local function knock(from, at, strength)
	local away = flat(at - from)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
	return away * (strength or 30) + Vector3.new(0, 18, 0)
end

----------------------------------------------------------------------
-- Oozlet's moves
----------------------------------------------------------------------
-- Where Oozlet is at time t: partway along its current hop (an arc), or
-- where the last one put it down.
local function posAt(S, t)
	local h = S.hop
	if not h then
		return S.rest
	end
	local u = (t - h.at) / h.time
	if u >= 1 then
		return h.to
	elseif u <= 0 then
		return h.from
	end
	return h.from:Lerp(h.to, u) + Vector3.new(0, h.height * 4 * u * (1 - u), 0)
end

-- Sends Oozlet from where it is now to `to` in `time` seconds, `height` studs
-- up at the top of the arc (0 = straight there: rising, dropping). Their
-- screen draws the whole hop from these numbers. Returns when it started.
local function move(S, to, time, height)
	local t = now()
	local from = posAt(S, t)
	S.hop = { from = from, to = to, at = t, time = math.max(time or 0.3, 0.05), height = height or 0 }
	S.rest = to
	local m = S.model
	m:SetAttribute("HopFrom", from)
	m:SetAttribute("HopTo", to)
	m:SetAttribute("HopTime", S.hop.time)
	m:SetAttribute("HopHeight", S.hop.height)
	m:SetAttribute("HopAt", t) -- (last: their screen redraws the hop when this changes)
	return t
end

-- Tells their screen what Oozlet is doing (so it can draw the red circle,
-- squash it, make it dizzy...): `pos` and `radius` are the circle, `tell`
-- how long until it lands (-1 = it's waiting).
local function act(S, name, pos, radius, tell)
	local m = S.model
	m:SetAttribute("ActionPos", pos or S.rest)
	m:SetAttribute("ActionR", radius or 0)
	m:SetAttribute("ActionTell", tell or 0)
	m:SetAttribute("Action", name)
	m:SetAttribute("ActionAt", now()) -- (last: their screen starts the move when this changes)
end

-- Waits until time t on the shared clock. False if the intro ended (or
-- Oozlet popped) meanwhile - then whatever was going on just stops.
local function waitUntil(S, t)
	while now() < t do
		if S.over or S.dead then
			return false
		end
		task.wait(math.clamp(t - now(), 0, 0.05))
	end
	return not (S.over or S.dead)
end

-- The same while it's still happy: stops early when it's punched
local function waitHappy(S, t)
	while now() < t do
		if S.over or S.woken then
			return false
		end
		task.wait(math.clamp(t - now(), 0, 0.05))
	end
	return not (S.over or S.woken)
end

-- Oozlet's hit on them: `share` of their max health - but never below Floor
-- (you can't lose), and not at all if they're rolling (CombatService says
-- "Dodged!"). Returns true if it landed.
local function hurt(S, share, from, push)
	local root, hum = rootOf(S.player)
	if not root then
		return false
	end
	local keep = hum.MaxHealth * (O.Floor or 0.3)
	local amount = math.min(hum.MaxHealth * share, hum.Health - keep)
	if amount >= 1 or CombatService.IsInvulnerable(S.player) then
		return CombatService.DamagePlayer(S.player, math.max(amount, 0), from, push)
	end
	CombatService.Shove(S.player, push) -- (already as low as it goes: just a knock)
	return false
end

local function setStage(S, stage)
	S.stage = stage
	S.player:SetAttribute("Intro", stage)
end

----------------------------------------------------------------------
-- Happy: hopping round the fountain
----------------------------------------------------------------------
-- They've stood still too long: it hops over and bumps into them (no harm)
local function bump(S)
	S.lastBump = now()
	act(S, "Bump")
	local step = (O.HappyStep or 3.4) * 1.6
	for _ = 1, 5 do
		local root = rootOf(S.player)
		if not root then
			break
		end
		local to = flat(root.Position - S.rest)
		if to.Magnitude < 3.4 then
			break
		end
		local p = onPlaza(S.rest + to.Unit * math.min(step, to.Magnitude - 3))
		local t0 = move(S, groundAt(p.X, p.Z), 0.4, 2.6)
		if not waitHappy(S, t0 + 0.52) then
			return
		end
	end
	local root = rootOf(S.player)
	if root then
		-- boing: right up against them, and they're nudged back
		local away = flat(root.Position - S.rest)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
		local p = onPlaza(S.rest + away * math.max(0, flat(root.Position - S.rest).Magnitude - 2.4))
		local t0 = move(S, groundAt(p.X, p.Z), 0.3, 1.6)
		if not waitHappy(S, t0 + 0.3) then
			return
		end
		CombatService.Shove(S.player, away * 26 + Vector3.new(0, 16, 0))
		send(S, "Bump")
	end
	S.stillSince = now() -- (being nudged counts as moving)
	waitHappy(S, now() + 0.6)
end

local function happy(S)
	local dir = 1 -- which way round the fountain
	local untilPause = rng:NextInteger(4, 7)
	local rest = O.HappyRest or { 0.2, 0.45 }
	local hopTime = O.HappyHop or 0.42
	local stepLen = O.HappyStep or 3.4
	local r = O.Circle or 13.5
	while not (S.over or S.woken) do
		local t = now()
		local root = rootOf(S.player)
		local bumpAfter = O.Bump or 10
		if root and S.lookAt and t - S.stillSince >= bumpAfter and t - S.lastBump >= bumpAfter then
			bump(S)
		elseif untilPause <= 0 then
			-- a little pause: a happy wiggle
			untilPause = rng:NextInteger(4, 7)
			act(S, "Wiggle")
			waitHappy(S, now() + rng:NextNumber(1, 1.6))
		else
			untilPause = untilPause - 1
			-- the next spot round the circle (drifting back onto it after a bump)
			local here = flat(S.rest - CENTER)
			local a = math.atan2(here.Z, here.X) + dir * stepLen / r
			local target = CENTER + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if root and flat(root.Position - target).Magnitude < 3 then
				-- they're in the way: turn round
				dir = -dir
				act(S, "Turn")
				waitHappy(S, now() + 0.5)
			else
				local step = flat(target - S.rest)
				if step.Magnitude > stepLen * 1.3 then
					step = step.Unit * stepLen * 1.3
				end
				local t0 = move(S, groundAt(S.rest.X + step.X, S.rest.Z + step.Z), hopTime, O.HappyHeight or 2.2)
				waitHappy(S, t0 + hopTime + rng:NextNumber(rest[1], rest[2]))
			end
		end
	end
end

----------------------------------------------------------------------
-- Angry: the fight
----------------------------------------------------------------------
local function wake(S)
	setStage(S, "Fight")
	S.wokeAt = now()
	local m = S.model
	m:SetAttribute("Mood", "Angry")
	m:SetAttribute("Invulnerable", true)
	-- (down from mid-hop if it was in the air)
	move(S, groundAt(S.rest.X, S.rest.Z), 0.2, 0)
	act(S, "Wake", S.rest, 0, O.WakeTime or 1.3)
	send(S, "Wake")
	waitUntil(S, now() + (O.WakeTime or 1.3))
	if not S.dead then
		m:SetAttribute("Invulnerable", false)
	end
end

-- THE LESSON: it leaps up over them and hangs above a red circle until they
-- roll (or it gets tired of waiting)
local function lesson(S)
	local L = O.Lesson or {}
	local radius = L.Radius or 7
	local m = S.model
	local root = rootOf(S.player)
	if not root then
		waitUntil(S, now() + 0.3)
		return
	end
	S.tries = S.tries + 1
	local p = onPlaza(root.Position)
	local spot = groundAt(p.X, p.Z)
	m:SetAttribute("Invulnerable", true)
	local t0 = move(S, spot + Vector3.new(0, L.Height or 7, 0), L.Rise or 0.7, 2.5)
	act(S, "Hold", spot, radius, -1)
	send(S, "Hold")
	if not waitUntil(S, t0 + (L.Rise or 0.7)) then
		return
	end
	-- it waits for a ROLL: walk out from under it and it just drifts over you
	-- again (that's how everyone learns to roll). It gives up in the end.
	local how = "wait"
	local giveUp = now() + (L.Wait or 12)
	local movedAt = now()
	while now() < giveUp do
		if S.over or S.dead then
			return
		end
		local r = rootOf(S.player)
		if r then
			if CombatService.IsInvulnerable(S.player) then
				how = "roll"
				break
			end
			if flat(r.Position - spot).Magnitude > radius * 0.6 and now() - movedAt > 0.4 then
				movedAt = now()
				local q = onPlaza(r.Position)
				spot = groundAt(q.X, q.Z)
				move(S, spot + Vector3.new(0, L.Height or 7, 0), 0.35, 0)
				act(S, "Hold", spot, radius, -1)
			end
		end
		task.wait(0.03)
	end
	-- down it comes
	local t1 = move(S, spot, L.Drop or 0.2, 0)
	act(S, "Drop", spot, radius, L.Drop or 0.2)
	if not waitUntil(S, t1 + (L.Drop or 0.2)) then
		return
	end
	local r = rootOf(S.player)
	if how == "wait" and r and flat(r.Position - spot).Magnitude <= radius then
		hurt(S, O.SlamDamage or 0.12, spot, knock(spot, r.Position))
	end
	if how ~= "wait" or S.tries >= 2 then
		S.rollTaught = true
	end
	send(S, "Dodge", how) -- ("roll", or "wait" if it just gave up and dropped)
	-- dizzy on the ground: now's the time to hit it
	m:SetAttribute("Invulnerable", false)
	act(S, "Dizzy", spot, 0, L.Dizzy or 1.6)
	waitUntil(S, now() + (L.Dizzy or 1.6))
end

-- a slam: it rises while the circle round it fills, then comes down
local function slam(S)
	local tell = stat(S, "SlamTell") or 0.95
	local radius = O.SlamRadius or 6.5
	local spot = S.rest
	local t0 = now()
	act(S, "Slam", spot, radius, tell)
	move(S, spot + Vector3.new(0, O.SlamRise or 3.5, 0), tell * 0.8, 0)
	if not waitUntil(S, t0 + tell * 0.8) then
		return
	end
	move(S, spot, tell * 0.2, 0)
	if not waitUntil(S, t0 + tell) then
		return
	end
	local r = rootOf(S.player)
	if r and flat(r.Position - spot).Magnitude <= radius then
		hurt(S, O.SlamDamage or 0.12, spot, knock(spot, r.Position))
	end
	waitUntil(S, now() + (O.SlamRecover or 0.8))
end

-- a hop towards them (stopping short of landing on them)
local function hopAt(S, root)
	local to = flat(root.Position - S.rest)
	local len = math.min(O.HopLength or 6.5, math.max(0, to.Magnitude - 3.2))
	if len < 0.8 then
		waitUntil(S, now() + 0.25)
		return
	end
	local p = onPlaza(S.rest + to.Unit * len)
	local time = stat(S, "HopTime") or 0.45
	local t0 = move(S, groundAt(p.X, p.Z), time, O.HopHeight or 3)
	local rest = stat(S, "Rest") or { 0.35, 0.7 }
	waitUntil(S, t0 + time + rng:NextNumber(rest[1], rest[2]))
end

-- phase two: three quick bounces at them, each landing in a small red circle
local function bounce(S)
	local B = O.Bounce or {}
	local radius = B.Radius or 4.5
	S.lastBounce = now()
	for _ = 1, B.Count or 3 do
		local root = rootOf(S.player)
		if not root then
			break
		end
		local to = flat(root.Position - S.rest)
		local len = math.min(B.Length or 9, to.Magnitude)
		local p = to.Magnitude > 0.1 and onPlaza(S.rest + to.Unit * len) or S.rest
		local spot = groundAt(p.X, p.Z)
		local t0 = move(S, spot, B.Time or 0.6, B.Height or 4)
		act(S, "Bounce", spot, radius, B.Time or 0.6)
		if not waitUntil(S, t0 + (B.Time or 0.6)) then
			return
		end
		local r = rootOf(S.player)
		if r and flat(r.Position - spot).Magnitude <= radius then
			hurt(S, B.Damage or 0.08, spot, knock(spot, r.Position, 24))
		end
		if not waitUntil(S, now() + 0.12) then
			return
		end
	end
	act(S, "Tired", S.rest, 0, B.Tired or 1.1)
	waitUntil(S, now() + (B.Tired or 1.1))
end

-- at half health: the shell cracks (can't be hurt for a moment, pushes you back)
local function crack(S)
	local C = O.Crack or {}
	local m = S.model
	S.cracked = true
	m:SetAttribute("Invulnerable", true)
	m:SetAttribute("Mood", "Cracked")
	act(S, "Crack", S.rest, C.Push or 9, C.Time or 1.4)
	send(S, "Crack")
	if not waitUntil(S, now() + (C.Time or 1.4) * 0.45) then
		return
	end
	local r = rootOf(S.player)
	if r and flat(r.Position - S.rest).Magnitude < (C.Push or 9) then
		CombatService.Shove(S.player, knock(S.rest, r.Position, 45))
	end
	if not waitUntil(S, now() + (C.Time or 1.4) * 0.55) then
		return
	end
	m:SetAttribute("MinHealth", 0) -- (the rest of its health can go now)
	m:SetAttribute("Invulnerable", false)
end

local function fight(S)
	local half = math.ceil((O.Health or 12) / 2)
	while not (S.over or S.dead) do
		local hp = S.model:GetAttribute("Health") or 0
		local root = rootOf(S.player)
		if not root then
			waitUntil(S, now() + 0.3) -- (respawning)
		elseif not S.rollTaught and (S.hits >= 2 or now() - S.wokeAt > 2.5 or hp <= half) then
			lesson(S)
		elseif not S.cracked and hp <= half then
			crack(S)
		else
			local d = flat(root.Position - S.rest).Magnitude
			local B = O.Bounce or {}
			if S.cracked and d < 22 and now() - S.lastBounce > 3 and rng:NextNumber() < (B.Chance or 0.4) then
				bounce(S)
			elseif d <= (O.SlamReach or 6) then
				slam(S)
			else
				hopAt(S, root)
			end
		end
	end
end

----------------------------------------------------------------------
-- The start and the end
----------------------------------------------------------------------
local function endSession(S)
	if S.over then
		return
	end
	S.over = true
	if S.charConn then
		S.charConn:Disconnect()
	end
	if S.model then
		S.model:Destroy()
	end
	if sessions[S.player] == S then
		sessions[S.player] = nil
	end
end

-- It's all over: the Power for the reward level (now, so the LEVEL UP shows
-- on the screen that's just come back), full health, and back to normal
local function finish(S)
	local player = S.player
	endSession(S)
	if not player.Parent then
		return
	end
	player:SetAttribute("Intro", nil)
	local R = I.Reward or {}
	local d = PlayerService.GetData(player)
	local want = Config.powerForLevel(R.Level or 1)
	if d and d.Power < want then
		PlayerService.AddPower(player, want - d.Power, true) -- (exactly: no bonuses)
	end
	local _, hum = rootOf(player)
	if hum then
		hum.Health = hum.MaxHealth
	end
	if (R.Tokens or 0) > 0 then
		local notify = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Notify")
		if notify then
			notify:FireClient(player, "* Oozlet dropped an Arcade Token! Spin it at the ARCADE.", "ok")
		end
	end
end

-- Something went wrong (here, or on their screen): back to normal with no
-- reward, and they'll get the intro again next time they join
local function abandon(S)
	local player = S.player
	endSession(S)
	if player.Parent then
		player:SetAttribute("Intro", nil)
	end
end

local function win(S)
	local m = S.model
	m:SetAttribute("Invulnerable", true)
	m:SetAttribute("Mood", "Popped")
	CollectionService:RemoveTag(m, "CombatTarget") -- (nothing left to punch)
	act(S, "Pop", S.rest, 0, 0)
	local R = I.Reward or {}
	-- (the first chest pays once ever - a replay, e.g. the dev's, pays nothing)
	local d = PlayerService.GetData and PlayerService.GetData(S.player)
	local firstTime = not (d and d.IntroDone)
	PlayerService.SetIntroDone(S.player)
	if firstTime and (R.Tokens or 0) > 0 then
		PlayerService.AddTokens(S.player, R.Tokens)
	end
	if firstTime and (R.Coins or 0) > 0 then
		PlayerService.AddCoins(S.player, R.Coins, true)
	end
	send(S, "Win")
	local V = I.Reveal or {}
	task.wait(V.Delay or 2.8)
	if S.over then
		return
	end
	setStage(S, "Reveal") -- (the fighting stops; the mist starts rolling back)
	-- their screen says when it's done; if it never does, carry on anyway
	local giveUp = now() + (V.Time or 8) + (V.Spire or 3.4) + 12
	while not S.over and not S.revealed and now() < giveUp do
		task.wait(0.2)
	end
	if not S.over then
		finish(S)
	end
end

-- Puts them by the fountain, facing it (a move the movement guard allows).
-- Checked again a moment later, in case Roblox's own spawning moved them after.
local function place(S, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root or S.over or S.stage == "Reveal" then
		return
	end
	local at = I.SpawnAt or (CENTER + Vector3.new(0, 0, 17))
	local spot = groundAt(at.X, at.Z) + Vector3.new(0, 3, 0)
	for _ = 1, 2 do
		task.wait(0.1)
		if S.over or S.player.Character ~= char then
			return
		end
		if (root.Position - spot).Magnitude > 6 then
			S.player:SetAttribute("MoveTo", spot)
			S.player:SetAttribute("MoveUntil", now() + 3)
			root.AssemblyLinearVelocity = Vector3.zero
			char:PivotTo(CFrame.lookAt(spot, Vector3.new(CENTER.X, spot.Y, CENTER.Z)))
		end
		task.wait(0.5)
	end
end

local function run(S)
	happy(S)
	if S.over then
		return
	end
	wake(S)
	fight(S)
	if S.dead and not S.over then
		win(S)
	end
end

local function start(player)
	local m = Instance.new("Model")
	m.Name = "Oozlet_" .. player.UserId
	local box = Instance.new("Part")
	box.Name = "Hitbox"
	box.Size = Vector3.new(O.Size or 4.6, (O.Size or 4.6) * 0.9, O.Size or 4.6)
	box.Transparency = 1
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = false
	box.CastShadow = false
	box.Parent = m
	m.PrimaryPart = box
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit" -- (CombatService fires it for every punch that lands)
	onHit.Parent = m
	local health = O.Health or 12
	m:SetAttribute("Owner", player.UserId) -- only theirs to hit (and to see)
	m:SetAttribute("DisplayName", "Oozlet")
	m:SetAttribute("NoBar", true) -- (IntroClient draws its own bar)
	m:SetAttribute("HitRadius", O.Hitbox or 2.6)
	m:SetAttribute("Level", 1) -- hit as hard as a level 1 boss is hit
	m:SetAttribute("StudioFair", true) -- (in Studio, as hard as a level 1 player hits: the same fight a new player gets)
	m:SetAttribute("MaxHealth", health)
	m:SetAttribute("Health", health)
	m:SetAttribute("MinHealth", math.ceil(health / 2)) -- (it cracks at half health: nothing skips that)
	m:SetAttribute("Mood", "Happy")

	-- it starts on its circle off to their right, and hops across in front of them
	local r = O.Circle or 13.5
	local a = math.atan2(((I.SpawnAt or CENTER).Z - CENTER.Z), ((I.SpawnAt or CENTER).X - CENTER.X)) - 0.9
	local startAt = groundAt(CENTER.X + math.cos(a) * r, CENTER.Z + math.sin(a) * r)
	local S = {
		player = player,
		model = m,
		box = box,
		stage = "Void",
		rest = startAt,
		hop = nil,
		hits = 0,
		tries = 0,
		rollTaught = false,
		cracked = false,
		woken = false,
		dead = false,
		over = false,
		revealed = false,
		startedAt = now(),
		lookAt = nil, -- (when their screen could see it: the title screen gone)
		stillPos = Vector3.new(0, -1e6, 0),
		stillSince = now(),
		lastBump = -math.huge,
		lastBounce = -math.huge,
		wokeAt = now(),
	}
	sessions[player] = S
	box.CFrame = CFrame.new(startAt + Vector3.new(0, (O.Size or 4.6) * 0.45, 0))
	m.Parent = folder
	move(S, startAt, 0.05, 0)
	CollectionService:AddTag(m, "CombatTarget")

	onHit.Event:Connect(function(who, damage, killed)
		if who ~= player or S.over then
			return
		end
		if (damage or 0) > 0 then
			S.hits = S.hits + 1
		end
		if not S.woken then
			S.woken = true -- (the first punch wakes it up)
		end
		if killed then
			S.dead = true
		end
	end)

	setStage(S, "Void")
	-- (placed as soon as there's a body, and again each time they respawn)
	S.charConn = player.CharacterAdded:Connect(function(char)
		task.spawn(place, S, char)
	end)
	if player.Character then
		task.spawn(place, S, player.Character)
	end

	task.spawn(function()
		local ok, err = pcall(run, S)
		if not ok then
			warn("[IntroService] Oozlet broke: " .. tostring(err))
			-- never leave anyone stuck in the dark
			if not S.over then
				abandon(S)
			end
		end
	end)
end

-- Does this player get the intro?
local function wantsIntro(d)
	if I.On == false or not d then
		return false
	end
	if RunService:IsStudio() then
		-- (Studio: only if Config.Intro.InStudio is on - the dev console's
		-- "Replay Intro" plays it any time)
		return I.InStudio == true
	end
	return not d.IntroDone
end

local function onJoin(player)
	-- (wait for their save to load: it says whether they've done it)
	local d = nil
	local waited = 0
	while player.Parent and waited < 30 do
		d = PlayerService.GetData(player)
		if d then
			break
		end
		task.wait(0.1)
		waited = waited + 0.1
	end
	if not player.Parent then
		return
	end
	if wantsIntro(d) then
		start(player)
	end
	player:SetAttribute("IntroChecked", true)
end

local function onLeave(player)
	local S = sessions[player]
	if S then
		endSession(S)
	end
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function IntroService.Start(combatService, playerService)
	CombatService, PlayerService = combatService, playerService

	local old = workspace:FindFirstChild("IntroOozlets")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "IntroOozlets"
	folder.Parent = workspace
	local oldRemote = ReplicatedStorage:FindFirstChild("IntroEvent")
	if oldRemote then
		oldRemote:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = "IntroEvent" -- server -> client: "Bump", "Wake", "Hold", "Dodge", "Crack", "Win"
	remote.Parent = ReplicatedStorage

	-- their screen can see now (the title screen has gone): the bump waits for this
	PlayerService.AddAction("IntroLook", function(player)
		local S = sessions[player]
		if S and not S.lookAt then
			S.lookAt = now()
			S.stillSince = now()
		end
		return true
	end)
	-- their screen has finished showing the lobby (it can only end the reveal early)
	PlayerService.AddAction("IntroDone", function(player)
		local S = sessions[player]
		if S and S.stage == "Reveal" then
			S.revealed = true
		end
		return true
	end)
	-- DEV ONLY (Studio, or the game's owner): play it again from the start
	-- (the dev console's "DEV: Replay Intro")
	PlayerService.AddAction("DevReplayIntro", function(player)
		if not Config.isDev(player) then
			return false, "Dev tools are only for the game's owner."
		end
		local S = sessions[player]
		if S and not S.over then
			return false, "You're already in the intro."
		end
		if player:GetAttribute("SpireFloor") or player:GetAttribute("Colosseum") then
			return false, "Go back to the lobby first."
		end
		start(player)
		return true
	end)
	-- their screen couldn't show it (something broke there): they play on
	-- normally - no reward, and the intro again next time (all a player
	-- gains by sending this is skipping the intro and its reward)
	PlayerService.AddAction("IntroFailed", function(player)
		local S = sessions[player]
		if S and not S.over then
			if S.stage == "Reveal" then
				S.revealed = true
			elseif not S.dead then
				abandon(S)
			end
		end
		return true
	end)

	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, p)
	end
	Players.PlayerRemoving:Connect(onLeave)

	-- every frame: each Oozlet's box follows its hop (that's what punches find),
	-- and we notice who's standing still
	RunService.Heartbeat:Connect(function()
		local t = now()
		for player, S in pairs(sessions) do
			if not S.over then
				S.box.CFrame = CFrame.new(posAt(S, t) + Vector3.new(0, (O.Size or 4.6) * 0.45, 0))
				local root = rootOf(player)
				if root and (root.Position - S.stillPos).Magnitude > 1.5 then
					S.stillPos = root.Position
					S.stillSince = t
				end
				-- (if their screen never says it can see, the bump starts anyway)
				if not S.lookAt and t - S.startedAt > 14 then
					S.lookAt = t
				end
			end
		end
	end)
end

return IntroService
