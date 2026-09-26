--[[
	ColosseumService  (ModuleScript, parent: ServerScriptService, name: "ColosseumService")

	The Colosseum: a wave arena for farming Power (XP) and coins.

	  * Press E at the little door of the mini colosseum in the lobby and you
	    shrink down into it, bit by bit, like going down a pipe - and you're
	    in the Colosseum (far from the lobby), already small enough to fit.
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
	  * A quest runs the whole time you're in there: defeat 10 dummies for a
	    big lump of Power and coins, then it starts straight over again.

	All the numbers are in Config.Colosseum.
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

-- the state the player's screen shows (wave, quest progress, what it pays)
local function pushState(player, s)
	local rewards = Config.colosseumRewards(playerLevel(player))
	send(player, "State", {
		wave = s.wave,
		left = s.alive,
		quest = s.questKills,
		goal = C.QuestKills,
		questPower = rewards.questPower,
		questCoins = rewards.questCoins,
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

local function inArena(pos)
	local d = flat(pos - C.Center)
	if d.Magnitude > C.Radius then
		d = d.Unit * C.Radius
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
-- whatever colour it's given. `into` is the dummy's effects folder.
strawPuff = function(into, at, color)
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
	p:Emit(18)
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
		CombatService.DamagePlayer(s.player, hum.MaxHealth * share, at, safePush(s.player, away * (push or 40) + Vector3.new(0, 26, 0)))
		return true
	end
	return false
end

-- A slam: a red ring on the sand, a short hop, and down it comes.
local function slam(s, e, tell)
	local model = e.model
	local at = feet(model).Position
	local range = C.SlamRange * (e.scale or 1)
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
	hurtNear(s, at, range + 1, C.SlamDamage)
	strawPuff(e.fx, at, e.puff)
end

-- One hop towards `dest`, in an arc, turning to face the player.
local function hop(e, dest, faceTo)
	local model = e.model
	local from = feet(model).Position
	local t0 = os.clock()
	local time = C.HopTime * (e.slow or 1)
	while e.alive do
		local k = math.min(1, (os.clock() - t0) / time)
		local p = from:Lerp(dest, k) + Vector3.new(0, 4 * k * (1 - k) * C.HopHeight, 0)
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
	-- (as far as it can go down that line without leaving the sand)
	local rel = flat(start - C.Center)
	local along = rel:Dot(dir)
	local room = along * along - (rel.Magnitude ^ 2 - C.Radius ^ 2)
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
		place(model, face * CFrame.new((rng:NextNumber() - 0.5) * 0.5, 0, 0.8 * k) * CFrame.Angles(-0.25 * k, 0, 0))
		task.wait(1 / 20)
	end
	-- the charge
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
					CombatService.DamagePlayer(s.player, hum.MaxHealth * CH.Damage, p, safePush(s.player, dir * 60 + Vector3.new(0, 30, 0)))
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
	strawPuff(e.fx, at)
end

-- THE CURSED DUMMY'S BLINK: it shudders, vanishes in a burst of purple...
-- and reappears right behind you, already winding up a slam.
local function blink(s, e)
	local BL = C.Blink
	local model = e.model
	local from = feet(model)
	local t0 = os.clock()
	while os.clock() - t0 < BL.Tell do
		if not e.alive then
			return
		end
		place(model, from * CFrame.new((rng:NextNumber() - 0.5) * 0.8, 0, (rng:NextNumber() - 0.5) * 0.8))
		task.wait(1 / 20)
	end
	strawPuff(e.fx, from.Position, e.puff)
	place(model, from + Vector3.new(0, -80, 0)) -- (gone)
	task.wait(0.35)
	local root = rootOf(s.player)
	if not (root and e.alive) then
		if e.alive then
			place(model, from)
		end
		return
	end
	local back = flat(root.CFrame.LookVector)
	back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
	local spot = inArena(root.Position - back * BL.Behind)
	local look = flat(root.Position - spot)
	place(model, CFrame.lookAt(spot, spot + (look.Magnitude > 0.1 and look or back)))
	strawPuff(e.fx, spot, e.puff)
	slam(s, e, BL.SlamTell)
end

-- What one dummy does, over and over, until it's beaten (or you leave)
local function brain(s, e)
	-- Spawning in: a shadow grows on the sand where it'll land, then it
	-- drops out of the sky, lands with a puff and bounces.
	local start = feet(e.model)
	local land = start.Position
	local turn = start - start.Position
	place(e.model, CFrame.new(land + Vector3.new(0, 80, 0)) * turn) -- (up out of sight)
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

local function spawnWave(s)
	local root = rootOf(s.player)
	if not root then
		return
	end
	s.wave = s.wave + 1
	local count = math.min(C.WaveSize[1] + s.wave - 1, C.WaveSize[2])
	local level = math.max(2, playerLevel(s.player))
	local rec = math.max(1, Config.powerForLevel(level))
	local kinds = pickKinds(level, count)
	for i = 1, count do
		local kind = kinds[i]
		local T = TYPE_BY_ID[kind] or { id = "Straw", name = "Straw Dummy", health = 1, reward = 1, scale = 1 }
		local template = ServerStorage:FindFirstChild(kind == "Straw" and "ColosseumDummy" or ("ColosseumDummy_" .. kind))
			or ServerStorage:FindFirstChild("ColosseumDummy")
		if not template then
			warn("[ColosseumService] No ColosseumDummy in ServerStorage - is LobbyBuilder up to date?")
			return
		end
		if not template:GetAttribute("Foot") then
			kind, T = "Straw", TYPE_BY_ID.Straw or T -- (an old LobbyBuilder: plain straw dummies only)
		end
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
		local hp = math.floor(rec * C.HitsToKill * (T.health or 1))
		local model = template:Clone()
		model.Name = T.name or "Straw Dummy"
		model:SetAttribute("DisplayName", (T.name or "Straw Dummy") .. "  Lv." .. level)
		model:SetAttribute("Owner", s.player.UserId)
		model:SetAttribute("Level", level)
		model:SetAttribute("MaxHealth", hp)
		model:SetAttribute("Health", hp)
		model:SetAttribute("HitRadius", 2.6 * (T.scale or 1))
		model:SetAttribute("Kind", kind)
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
		local look = flat(root.Position - spot)
		place(model, CFrame.lookAt(spot, spot + (look.Magnitude > 0.1 and look or Vector3.new(0, 0, 1))))
		model.Parent = enemyFolder
		CollectionService:AddTag(model, "CombatTarget")
		-- its warning rings, puffs and hay bales go in here (see marker)
		local fx = Instance.new("Folder")
		fx.Name = "DummyFX"
		fx:SetAttribute("Owner", s.player.UserId)
		fx.Parent = enemyFolder

		local K = KIND[kind] or {}
		local e = {
			model = model, fx = fx, alive = true, kind = kind, scale = T.scale or 1, reward = T.reward or 1,
			slow = K.slow, reach = K.reach, puff = K.puff,
			slot = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3),
		}
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
		task.delay((i - 1) * 0.25, function()
			if e.alive then
				brain(s, e)
			end
		end)
	end
	send(s.player, "Wave", s.wave)
	pushState(s.player, s)
end

-- A dummy was beaten: pay out, count it for the quest, and bring on the
-- next wave once the sand is clear.
function ColosseumService.OnKill(s, model, e)
	local player = s.player
	CollectionService:RemoveTag(model, "CombatTarget")
	pcall(CombatService.Disintegrate, model, { Color = Color3.fromRGB(254, 174, 52) })
	Debris:AddItem(model, 2.5)
	if e then
		Debris:AddItem(e.fx, 1.5) -- (lets its last puff finish)
	end

	local rewards = Config.colosseumRewards(playerLevel(player))
	-- (tougher kinds pay more: a Knight is worth 2.2 straw dummies)
	local mult = (e and e.reward) or 1
	local killPower = math.max(1, math.floor(rewards.killPower * mult))
	local killCoins = math.max(1, math.floor(rewards.killCoins * mult))
	PlayerService.AddPower(player, killPower)
	PlayerService.AddCoins(player, killCoins)
	if PlayerService.QuestProgress then
		PlayerService.QuestProgress(player, "arena", 1)
	end
	send(player, "Kill", killPower, killCoins, feet(model).Position + Vector3.new(0, 11 * ((e and e.scale) or 1), 0))

	s.questKills = s.questKills + 1
	if s.questKills >= C.QuestKills then
		s.questKills = 0
		PlayerService.AddPower(player, rewards.questPower)
		PlayerService.AddCoins(player, rewards.questCoins)
		send(player, "QuestDone", rewards.questPower, rewards.questCoins)
	end
	pushState(player, s)

	if s.alive <= 0 and sessions[player] == s then
		send(player, "WaveClear", s.wave) -- (the crowd throws confetti)
		task.delay(C.WaveBreak, function()
			if sessions[player] == s then
				spawnWave(s)
			end
		end)
	end
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
	for model, e in pairs(s.enemies) do
		e.alive = false
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

local function enter(player)
	if sessions[player] or going[player] or player:GetAttribute("SpireFloor") then
		return
	end
	local root, _, char = rootOf(player)
	local spawnAt = CollectionService:GetTagged("ColosseumSpawn")[1]
	local door = CollectionService:GetTagged("ColosseumDoor")[1]
	if not (root and spawnAt) then
		return
	end
	if (flat(root.Position - C.GatePosition)).Magnitude > C.EnterRange + 10 then
		return
	end
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
	local s = { player = player, wave = 0, alive = 0, questKills = 0, enemies = {} }
	sessions[player] = s
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
	if not sessions[player] or going[player] then
		return
	end
	-- (only from the exit door: leaving heals you to full, so it mustn't work
	-- from the middle of a fight by firing the prompt from anywhere)
	local exitPrompt = CollectionService:GetTagged("ColosseumExit")[1]
	local exitDoor = exitPrompt and exitPrompt.Parent
	local root = rootOf(player)
	if not root or (exitDoor and exitDoor:IsA("BasePart") and (root.Position - exitDoor.Position).Magnitude > 32) then
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
	remote.Name = "ColosseumEvent" -- server -> client: "PipeIn", "PipeOut", "Arrived", "Left", "State", "Wave", "Kill", "QuestDone"
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
	hook("ColosseumEntrance", enter)
	hook("ColosseumExit", leave)

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
