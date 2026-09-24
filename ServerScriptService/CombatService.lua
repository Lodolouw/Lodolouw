--[[
	CombatService  (ModuleScript, parent: ServerScriptService, name: "CombatService")

	The player's side of fighting in the Spire, Souls style. Only switched on
	while you're inside an arena (the "SpireFloor" attribute SpireService sets):
	  * Stamina: punching and rolling cost stamina, which refills a moment
	    after you stop spending it. No stamina, no action.
	  * Dodge roll: a quick dash with a short window of invincibility at the
	    start. The client does the movement; the server decides when you're
	    invincible.
	  * Punch: hits the nearest enemy in reach. Damage comes from your Power
	    compared to the floor's recommended level.
	  * Healing flasks: a few per trip. Drinking takes a moment (you're slowed
	    and can't attack), then heals part of your health.
	  * Dying in an arena sends you back to the Spire's doors (SpireService).

	For boss scripts later:
	    local CombatService = require(game.ServerScriptService.CombatService)
	    CombatService.DamagePlayer(player, 40, attackPosition, knockback)  --> true if it landed
	    CombatService.IsInvulnerable(player)
	    CombatService.PlayersInArena(floorId)
	    CombatService.Disintegrate(model)          --> ashes away a corpse
	    CombatService.Shove(player, velocity)       --> throw them, no damage
	    CombatService.IsFighting(player)            --> in an arena and alive
	A target Model can also carry: NoBar (draws its own bar), Invulnerable,
	MinHealth (damage can't take it below this), StudioFair (see DamageAgainst).
	Anything tagged "CombatTarget" (a Model with Health / MaxHealth attributes)
	can be punched; see the practice slime in the arena.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CombatService = {}

local CC = Config.Combat
local PlayerService = nil -- set in Start (avoids a require loop)
local remotes = {}
local fighters = {} -- [player] = combat state while in an arena
local targets = {} -- [model] = true for every punchable enemy

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function charParts(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root and hum.Health > 0) then
		return nil
	end
	return hum, root, char
end

local function floorOf(player)
	local id = player:GetAttribute("SpireFloor")
	for _, f in ipairs(Config.Spire.Floors) do
		if f.id == id then
			return f
		end
	end
	return nil
end

local function send(player, kind, ...)
	if remotes.CombatEvent and player.Parent then
		remotes.CombatEvent:FireClient(player, kind, ...)
	end
end

local function pushState(player, st)
	send(player, "State", math.floor(st.stamina + 0.5), CC.MaxStamina, st.flasks, CC.Flasks)
	st.lastPushed = st.stamina
	st.lastPushedFlasks = st.flasks
end

local function spend(st, amount, now)
	st.stamina = math.max(0, st.stamina - amount)
	st.lastSpend = now
end

-- Your punch damage against something on this floor
function CombatService.PunchDamage(player, floor)
	local d = PlayerService and PlayerService.GetData(player)
	local power = d and d.Power or 0
	local rec = math.max(1, Config.powerForLevel((floor and floor.level) or 1))
	local ratio = math.max(power, 1) / rec
	local mult = math.clamp(ratio ^ CC.DamageCurve, CC.DamageMin, CC.DamageMax)
	return math.max(1, math.floor(rec * mult))
end

-- Your punch against one particular enemy. Normally just PunchDamage; but a
-- boss marked "StudioFair" takes, in Studio only, exactly what a player at the
-- floor's recommended level would deal - so a strong tester still gets the fight
-- a real player would get.
function CombatService.DamageAgainst(player, target)
	local floor = floorOf(player)
	if target and target:GetAttribute("StudioFair") and RunService:IsStudio() then
		return math.max(1, math.floor(Config.powerForLevel((floor and floor.level) or 1)))
	end
	return CombatService.PunchDamage(player, floor)
end

----------------------------------------------------------------------
-- Public API for bosses
----------------------------------------------------------------------
function CombatService.IsInvulnerable(player)
	local st = fighters[player]
	return st ~= nil and os.clock() < st.iframeUntil
end

-- Death by disintegration: the body freezes where it fell, turns to embers and
-- ash that drift upwards, fades out, and is gone. Used for players dying in an
-- arena, and there for bosses to use on their own corpses later:
--     CombatService.Disintegrate(slimeModel, { Color = Color3.fromRGB(120, 230, 90) })
local DISINTEGRATE = {
	Fade = 1.5, -- how long the body takes to vanish
	Rise = 2.2, -- studs it drifts upward while it goes
	Color = Color3.fromRGB(190, 225, 255), -- ember colour
}

function CombatService.Disintegrate(model, options)
	if not model or model:GetAttribute("Disintegrating") then
		return
	end
	model:SetAttribute("Disintegrating", true)
	options = options or {}
	local fade = options.Fade or DISINTEGRATE.Fade
	local rise = options.Rise or DISINTEGRATE.Rise
	local color = options.Color or DISINTEGRATE.Color
	local ease = TweenInfo.new(fade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	local emitters = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			-- hold the pose instead of flopping about, and stop it being in the way
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false

			local embers = Instance.new("ParticleEmitter")
			embers.Name = "Ashes"
			embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			embers.Color = ColorSequence.new(color)
			embers.LightEmission = 0.85
			embers.LightInfluence = 0
			embers.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			embers.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			embers.Lifetime = NumberRange.new(0.6, 1.4)
			embers.Rate = math.clamp(d.Size.Magnitude * 28, 20, 140)
			embers.Speed = NumberRange.new(1, 5)
			embers.SpreadAngle = Vector2.new(35, 35)
			embers.Acceleration = Vector3.new(0, 7, 0) -- ash rises
			embers.Drag = 1.5
			embers.EmissionDirection = Enum.NormalId.Top
			embers.Parent = d
			emitters[#emitters + 1] = embers

			TweenService:Create(d, ease, { Transparency = 1 }):Play()
			TweenService:Create(d, ease, {
				CFrame = d.CFrame + Vector3.new(0, rise, 0),
			}):Play()
		elseif d:IsA("Decal") then
			TweenService:Create(d, ease, { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = false
		elseif d:IsA("Light") then
			TweenService:Create(d, ease, { Brightness = 0 }):Play()
		end
	end

	-- a last flare of light where the body was
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if root then
		local flare = Instance.new("PointLight")
		flare.Color = color
		flare.Range = 26
		flare.Brightness = 4
		flare.Parent = root
		TweenService:Create(flare, TweenInfo.new(fade * 0.7), { Brightness = 0, Range = 4 }):Play()
	end

	-- stop making new ash before the body is gone, then clear it away
	task.delay(fade * 0.7, function()
		for _, e in ipairs(emitters) do
			if e.Parent then
				e.Enabled = false
			end
		end
	end)
	task.delay(fade + 1.6, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

function CombatService.PlayersInArena(floorId)
	local list = {}
	for player in pairs(fighters) do
		if player:GetAttribute("SpireFloor") == floorId then
			list[#list + 1] = player
		end
	end
	return list
end

-- Deals damage to a player in an arena. Rolling (invincibility) avoids it.
-- knockback: optional Vector3 push (studs/second) applied on the player's screen.
-- quiet = true for small repeated damage (standing in a puddle): no "Dodged!"
-- message and no camera knock every tick, just a faint flash.
function CombatService.DamagePlayer(player, amount, fromPosition, knockback, quiet)
	local st = fighters[player]
	local hum = st and charParts(player)
	if not hum then
		return false
	end
	if os.clock() < st.iframeUntil then
		if not quiet then
			send(player, "Dodged")
		end
		return false
	end
	hum:TakeDamage(amount)
	send(player, "Hurt", amount, fromPosition, knockback, quiet == true)
	return true
end

-- Throws a player without hurting them (a boss's shell bursting, say). The
-- push happens on their own screen, where their character is simulated.
function CombatService.Shove(player, velocity)
	if fighters[player] and typeof(velocity) == "Vector3" then
		send(player, "Shove", velocity)
	end
end

-- Whether this player is in an arena, alive, and able to be hit right now.
function CombatService.IsFighting(player)
	return fighters[player] ~= nil and charParts(player) ~= nil
end

----------------------------------------------------------------------
-- Targets (anything punchable)
----------------------------------------------------------------------
local function targetPivot(model)
	local ok, cf = pcall(function()
		return model:GetPivot()
	end)
	return ok and cf or nil
end

local function setTargetVisible(model, visible)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("BaseTransparency") == nil then
				p:SetAttribute("BaseTransparency", p.Transparency)
			end
			p.Transparency = visible and p:GetAttribute("BaseTransparency") or 1
		elseif p:IsA("BillboardGui") then
			p.Enabled = visible
		end
	end
end

local function updateTargetBar(model)
	local bar = model:FindFirstChild("HealthBar", true)
	local fill = bar and bar:FindFirstChild("Fill", true)
	local label = bar and bar:FindFirstChild("Amount", true)
	local hp, max = model:GetAttribute("Health") or 0, model:GetAttribute("MaxHealth") or 1
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
	end
	if label then
		label.Text = Config.format(math.max(0, hp)) .. " / " .. Config.format(max)
	end
end

local function buildTargetBar(model)
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not body or model:FindFirstChild("HealthBar", true) or model:GetAttribute("NoBar") then
		return -- (bosses have their own bar across the top of the screen)
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.fromOffset(180, 46)
	bb.StudsOffset = Vector3.new(0, (model:GetAttribute("BarHeight") or 6), 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Adornee = body
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Enum.Font.Garamond
	name.TextSize = 18
	name.TextColor3 = Color3.fromRGB(235, 230, 240)
	name.TextStrokeTransparency = 0.3
	name.Text = model:GetAttribute("DisplayName") or model.Name
	name.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 22)
	back.Size = UDim2.new(1, 0, 0, 12)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 14)
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 40, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Position = UDim2.fromOffset(0, 34)
	amount.Size = UDim2.new(1, 0, 0, 12)
	amount.Font = Enum.Font.GothamBold
	amount.TextSize = 11
	amount.TextColor3 = Color3.fromRGB(230, 230, 230)
	amount.TextStrokeTransparency = 0.4
	amount.Text = ""
	amount.Parent = bb
	bb.Parent = body
end

local function addTarget(model)
	if not model:IsA("Model") or targets[model] then
		return
	end
	targets[model] = true
	-- practice targets get their health from the floor they're on
	if model:GetAttribute("Practice") then
		local floorId = model:GetAttribute("Floor") or 1
		local floor = Config.Spire.Floors[floorId]
		local rec = Config.powerForLevel(floor and floor.level or 1)
		model:SetAttribute("MaxHealth", math.floor(rec * CC.PracticeHits))
		model:SetAttribute("Health", model:GetAttribute("MaxHealth"))
	end
	buildTargetBar(model)
	updateTargetBar(model)
end

local function targetRadius(model)
	return model:GetAttribute("HitRadius") or 3
end

-- The enemy your punch lands on: the closest one in reach that's in front
-- of you (within a cone round the way your character is facing). Punching
-- the air hits nothing.
local PUNCH_CONE = math.cos(math.rad(55))
local function nearestTarget(root)
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)
	local best, bestDist = nil, math.huge
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 then
			local cf = targetPivot(model)
			if cf then
				local flat = Vector3.new(cf.X - root.Position.X, 0, cf.Z - root.Position.Z)
				local centre = flat.Magnitude
				local d = centre - targetRadius(model)
				local dy = math.abs(cf.Y - root.Position.Y)
				-- right up against it counts from any angle; otherwise it must be in front
				local inFront = centre < 0.01 or d < 1 or facing:Dot(flat.Unit) >= PUNCH_CONE
				if d <= CC.PunchRange and dy < 12 and inFront and d < bestDist then
					best, bestDist = model, d
				end
			end
		end
	end
	return best
end

-- The weight of a punch.
--
-- None of this is damage - it is what makes a hit feel like it landed on
-- something solid. It is built on the server so everyone in the arena sees the
-- same shockwave, and every piece of it is gone inside a third of a second:
-- fast and gone reads as force, while anything that lingers reads as a spell.
local IMPACT = CC.Impact or {}
local IMPACT_RING = IMPACT.Ring or 13 -- how wide the ring opens, in studs
local IMPACT_TIME = IMPACT.Time or 0.2 -- and how long it takes to get there
local IMPACT_COLOR = IMPACT.Color or Color3.fromRGB(235, 245, 255)
local IMPACT_SOUNDS = IMPACT.Sounds or {}
local IMPACT_WORLD = IMPACT.World == true -- the geometry; the camera reacts either way

-- A sound in the world, so everyone nearby hears it. Blank ids play nothing.
local function playSound(id, parent, volume, pitch)
	if not id or id == "" or not parent then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = tostring(id):match("^rbx") and id or ("rbxassetid://" .. tostring(id))
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 140
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- A stretched streak off the fist as it goes through. Weight 1-3 from the
-- client's punch string: the third swing throws a lot more air about.
local function fistStreak(char, dir, weight)
	if not IMPACT_WORLD then
		return
	end
	local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand") or char:FindFirstChild("HumanoidRootPart")
	if not arm then
		return
	end
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "PunchStreaks"
	streaks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	streaks.Color = ColorSequence.new(IMPACT_COLOR)
	streaks.LightEmission = 1
	streaks.LightInfluence = 0
	streaks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 + 0.25 * weight),
		NumberSequenceKeypoint.new(1, 0),
	})
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Squash = NumberSequence.new(6) -- drawn out into lines, not dots
	streaks.Lifetime = NumberRange.new(0.1, 0.18)
	streaks.Rate = 0
	streaks.Speed = NumberRange.new(18 + 8 * weight)
	streaks.SpreadAngle = Vector2.new(12, 12)
	streaks.Drag = 6
	streaks.Parent = arm
	streaks:Emit(8 + 6 * weight)
	Debris:AddItem(streaks, 0.6)
	local _ = dir
end

-- The moment of contact: a flat ring opening along the punch, a burst of
-- compressed air stretched the way you swung, and a puff of dust.
local function impact(position, dir, weight)
	weight = math.clamp(weight or 1, 1, 3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	dir = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local size = 0.55 + 0.45 * weight -- the finisher hits noticeably harder

	local holder = Instance.new("Part")
	holder.Name = "PunchImpact"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Parent = workspace

	if not IMPACT_WORLD then
		-- geometry switched off: the hit is still heard, and the camera still
		-- takes it on the client. Nothing is drawn in the world.
		playSound(IMPACT_SOUNDS.Thump, holder, 0.9, 0.85 - 0.05 * weight)
		playSound(IMPACT_SOUNDS.Crack, holder, 0.6, 1.05 + 0.05 * weight)
		Debris:AddItem(holder, 1.2)
		return
	end

	-- the ring: a disc facing the way the punch travelled, opening outwards
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = IMPACT_COLOR
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, math.pi / 2, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Transparency = 0.25
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(IMPACT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, IMPACT_RING * size, IMPACT_RING * size),
		Transparency = 1,
	}):Play()

	-- the air burst: a ball stretched along the punch, snapping outwards
	local burst = Instance.new("Part")
	burst.Name = "AirBurst"
	-- (a sphere mesh, not a Ball shape: Roblox draws Ball parts round at their
	-- smallest side, and this one is stretched along the punch)
	local burstMesh = Instance.new("SpecialMesh")
	burstMesh.MeshType = Enum.MeshType.Sphere
	burstMesh.Parent = burst
	burst.Material = Enum.Material.Neon
	burst.Color = IMPACT_COLOR
	burst.Size = Vector3.new(1, 1, 1)
	burst.CFrame = CFrame.lookAt(position, position + dir)
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CastShadow = false
	burst.Transparency = 0.4
	burst.Parent = workspace
	TweenService:Create(burst, TweenInfo.new(IMPACT_TIME * 1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(4 * size, 4 * size, 9 * size),
		Transparency = 1,
	}):Play()

	-- dust kicked off the floor, and a flash of light
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "ImpactDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(180, 180, 175))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 * size),
		NumberSequenceKeypoint.new(1, 3.5 * size),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.25, 0.45)
	dust.Rate = 0
	dust.Speed = NumberRange.new(9 * size, 16 * size)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Drag = 8
	dust.Parent = holder
	dust:Emit(8 + 7 * weight)

	local flash = Instance.new("PointLight")
	flash.Color = IMPACT_COLOR
	flash.Brightness = 3 * size
	flash.Range = 16 * size
	flash.Parent = holder
	TweenService:Create(flash, TweenInfo.new(0.18), { Brightness = 0, Range = 2 }):Play()

	-- a low thump with a crack on top: two layers read as one heavy sound
	playSound(IMPACT_SOUNDS.Thump, holder, 0.9, 0.85 - 0.05 * weight)
	playSound(IMPACT_SOUNDS.Crack, holder, 0.6, 1.05 + 0.05 * weight)

	Debris:AddItem(ring, IMPACT_TIME + 0.3)
	Debris:AddItem(burst, IMPACT_TIME + 0.4)
	Debris:AddItem(holder, 1.2)
end

local function hitTarget(player, model, damage, weight)
	-- A boss can be untouchable (rising, breaking its shell, dying), and can
	-- hold a floor under its health so a big hit can't skip a phase change.
	if model:GetAttribute("Invulnerable") then
		damage = 0
	end
	local floorHp = model:GetAttribute("MinHealth") or 0
	local before = model:GetAttribute("Health") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	model:SetAttribute("Health", math.max(0, hp))
	updateTargetBar(model)
	local cf = targetPivot(model)
	local killed = hp <= 0
	weight = math.clamp(weight or 1, 1, 3)
	send(player, "Hit", cf and cf.Position or Vector3.new(), damage, killed, weight)
	-- the shockwave, where the punch actually met them
	local _, root = charParts(player)
	if cf and root then
		local toward = cf.Position - root.Position
		local hitAt = root.Position + Vector3.new(toward.X, 0, toward.Z).Unit * math.min(toward.Magnitude, CC.PunchRange * 0.7)
		impact(Vector3.new(hitAt.X, cf.Position.Y, hitAt.Z), toward, weight)
		if player.Character then
			fistStreak(player.Character, toward, weight)
		end
	end
	-- let a boss script react (it can listen to this BindableEvent)
	local onHit = model:FindFirstChild("OnHit")
	if onHit and onHit:IsA("BindableEvent") then
		onHit:Fire(player, damage, killed)
	end
	if killed and model:GetAttribute("Practice") then
		setTargetVisible(model, false)
		task.delay(3, function()
			if model.Parent then
				model:SetAttribute("Health", model:GetAttribute("MaxHealth"))
				updateTargetBar(model)
				setTargetVisible(model, true)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Fighters (players in an arena)
----------------------------------------------------------------------
local function startFighting(player)
	fighters[player] = {
		stamina = CC.MaxStamina,
		lastSpend = 0,
		iframeUntil = 0,
		rollReadyAt = 0,
		lastPunch = 0,
		flasks = CC.Flasks,
		drinking = false,
		lastJump = 0,
	}
	pushState(player, fighters[player])
end

local function stopFighting(player)
	fighters[player] = nil
	send(player, "Stop")
end

local function restoreWalkSpeed(player, hum)
	local d = PlayerService and PlayerService.GetData(player)
	hum.WalkSpeed = Config.walkSpeedFor(player, d) -- capped while you're in an arena
	local cm = hum.Parent and hum.Parent:FindFirstChildWhichIsA("ControllerManager", true)
	if cm then
		cm.BaseMoveSpeed = hum.WalkSpeed
	end
end

local function onFloorChanged(player)
	if player:GetAttribute("SpireFloor") then
		startFighting(player)
	else
		stopFighting(player)
	end
	-- arriving in an arena slows you to its cap; leaving gives your boots back
	local _, _, char = charParts(player)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		restoreWalkSpeed(player, hum)
	end
end

local function onAction(player, action, arg, swing)
	local st = fighters[player]
	if not st then
		return
	end
	local hum, root = charParts(player)
	if not hum then
		return
	end
	local now = os.clock()

	if action == "Punch" then
		if st.drinking or now - st.lastPunch < math.max(CC.PunchInterval, CC.PunchLock) * 0.85 or st.stamina < CC.PunchCost then
			return
		end
		st.lastPunch = now
		spend(st, CC.PunchCost, now)
		-- which swing of the string this was: used for how heavy it looks, nothing else
		local weight = (type(swing) == "number" and math.clamp(math.floor(swing), 1, 3)) or 1
		local locked = typeof(arg) == "Instance" and arg or nil

		-- The fist lands partway through the swing, not on the button press. We
		-- wait for that moment and only then look for what we hit, so the damage,
		-- the camera and the sound all happen when the punch actually connects -
		-- and so an enemy who moves out of the way in time isn't hit by a punch
		-- that started while they were still standing there.
		task.delay(CC.PunchLock * CC.PunchContact, function()
			-- (see damageAgainst: in Studio a boss can ask to be hit at the floor's
			-- recommended strength, so testing feels like the real fight)
			if fighters[player] ~= st then
				return -- left the arena, died, or otherwise stopped fighting
			end
			local _, atRoot = charParts(player)
			if not atRoot then
				return
			end
			local target = nil
			if locked and targets[locked] and locked.Parent and (locked:GetAttribute("Health") or 0) > 0 then
				local cf = targetPivot(locked)
				if cf then
					local d = (Vector3.new(cf.X, 0, cf.Z) - Vector3.new(atRoot.Position.X, 0, atRoot.Position.Z)).Magnitude - targetRadius(locked)
					if d <= CC.PunchRange and math.abs(cf.Y - atRoot.Position.Y) < 12 then
						target = locked
					end
				end
			end
			target = target or nearestTarget(atRoot)
			if target then
				hitTarget(player, target, CombatService.DamageAgainst(player, target), weight)
			end
		end)
	elseif action == "Roll" then
		-- can't roll during the start of a punch (you're committed to it)
		local stillPunching = now - st.lastPunch < CC.PunchRollCancel * 0.8
		if st.drinking or stillPunching or now < st.rollReadyAt or st.stamina < CC.RollCost then
			send(player, "Denied", "Roll")
			return
		end
		st.rollReadyAt = now + CC.RollCooldown
		st.iframeUntil = now + CC.RollInvincible
		spend(st, CC.RollCost, now)
		-- the client shows the window so you can learn the timing
		send(player, "Iframes", CC.RollInvincible)
	elseif action == "Jump" then
		-- jumping costs stamina in an arena, the same as everything else you do
		if st.drinking or now - (st.lastJump or 0) < 0.25 or st.stamina < CC.JumpCost then
			send(player, "Denied", "Jump")
			return
		end
		st.lastJump = now
		spend(st, CC.JumpCost, now)
	elseif action == "Heal" then
		if st.drinking or st.flasks <= 0 then
			send(player, "Denied", "Heal")
			return
		end
		st.drinking = true
		st.flasks = st.flasks - 1
		hum.WalkSpeed = CC.FlaskWalkSpeed
		send(player, "Drinking", CC.FlaskDrinkTime)
		pushState(player, st)
		task.delay(CC.FlaskDrinkTime, function()
			st.drinking = false
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and fighters[player] == st then
				h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * CC.FlaskHeal)
				restoreWalkSpeed(player, h)
				send(player, "Healed")
			end
		end)
	elseif action == "DevIncoming" and RunService:IsStudio() then
		-- Studio-only test: a hit lands in 1 second, so you can practise rolling through it
		send(player, "Incoming", 1)
		task.delay(1, function()
			if fighters[player] then
				local _, r = charParts(player)
				CombatService.DamagePlayer(player, 30, r and r.Position, Vector3.new(0, 30, 0))
			end
		end)
	end
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function CombatService.Start(playerService)
	PlayerService = playerService

	local old = ReplicatedStorage:FindFirstChild("CombatRemotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	local action = Instance.new("RemoteEvent")
	action.Name = "CombatAction" -- client -> server: "Punch" / "Roll" / "Jump" / "Heal"
	action.Parent = folder
	local event = Instance.new("RemoteEvent")
	event.Name = "CombatEvent" -- server -> client: "State", "Hit", "Hurt", "Shove", "Iframes", "Dodged", "Drinking", "Healed", "Denied", "Died", "Stop"
	event.Parent = folder
	folder.Parent = ReplicatedStorage
	remotes.CombatAction = action
	remotes.CombatEvent = event

	action.OnServerEvent:Connect(function(player, name, arg, swing)
		if type(name) ~= "string" then
			return
		end
		local ok, err = pcall(onAction, player, name, arg, swing)
		if not ok then
			warn("[CombatService] " .. name .. " failed: " .. tostring(err))
		end
	end)

	for _, m in ipairs(CollectionService:GetTagged("CombatTarget")) do
		addTarget(m)
	end
	CollectionService:GetInstanceAddedSignal("CombatTarget"):Connect(addTarget)
	CollectionService:GetInstanceRemovedSignal("CombatTarget"):Connect(function(m)
		targets[m] = nil
	end)

	-- dying in an arena: show YOU DIED, and have SpireService put you back at the doors
	local function hookDeath(player, char)
		-- No natural regeneration: Roblox puts a script called "Health" in every
		-- character that heals about 1% a second. In a souls fight your flasks
		-- are the only way back, so it goes. (It can arrive a moment after the
		-- character does, so we watch for it as well.)
		local function noRegen(child)
			if child.Name == "Health" and child:IsA("Script") then
				child:Destroy()
			end
		end
		for _, child in ipairs(char:GetChildren()) do
			noRegen(child)
		end
		char.ChildAdded:Connect(noRegen)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		hum.Died:Connect(function()
			if player:GetAttribute("SpireFloor") then
				player:SetAttribute("DiedInSpire", true)
				send(player, "Died")
				fighters[player] = nil
			end
			CombatService.Disintegrate(char)
		end)
	end
	local function watch(player)
		player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
			onFloorChanged(player)
		end)
		player.CharacterAdded:Connect(function(char)
			hookDeath(player, char)
		end)
		if player.Character then
			task.spawn(hookDeath, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		fighters[player] = nil
	end)

	-- stamina regen, and keep each fighter's screen up to date (~8 times a second)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, st in pairs(fighters) do
			if not st.drinking and now - st.lastSpend >= CC.StaminaRegenDelay and st.stamina < CC.MaxStamina then
				st.stamina = math.min(CC.MaxStamina, st.stamina + CC.StaminaRegen * dt)
			end
		end
		acc = acc + dt
		if acc >= 0.12 then
			acc = 0
			for player, st in pairs(fighters) do
				if st.stamina ~= st.lastPushed or st.flasks ~= st.lastPushedFlasks then
					pushState(player, st)
				end
			end
		end
	end)
end

return CombatService
