--[[
	CombatService  (ModuleScript, parent: ServerScriptService, name: "CombatService")

	The player's side of fighting in the Spire, Souls style. Only switched on
	while you're inside an arena (the "SpireFloor" attribute SpireService sets,
	or "Colosseum" from ColosseumService), or fighting Oozlet in the intro
	("Intro" is "Void" or "Fight": IntroService - there, stamina is free,
	because the intro shows no stamina bar):
	  * Stamina: punching and rolling cost stamina, which refills a moment
	    after you stop spending it. No stamina, no action.
	  * Dodge roll: a quick dash with a short window of invincibility at the
	    start. The client does the movement; the server decides when you're
	    invincible.
	  * Punch: hits the nearest enemy in reach. Damage comes from your Power
	    compared to the floor's recommended level.
	  * Weapons (Config.Weapons): holding one ("Weapon" attribute), the same
	    button swings it instead - it cuts every enemy in its arc, harder the
	    rarer it is and the higher its mastery - and F uses its ability.
	    Every enemy you hit with it is mastery. See "Weapons" below.
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
	    CombatService.Launch(player, velocity)      --> fling them up (a jump pad): they fly on
	    CombatService.OnWhiff(function(player, pos) --> hear about punches that hit nothing
	    CombatService.IsFighting(player)            --> in an arena and alive
	    CombatService.Equip(player, "IronSword")     --> hold a weapon (nil: fists)
	A target Model can also carry: NoBar (draws its own bar), Invulnerable,
	MinHealth (damage can't take it below this), StudioFair (see DamageAgainst),
	Owner (a UserId: only that player can hit it - the Colosseum's dummies),
	Level (you hit it as hard as you'd hit a boss of that level).
	Anything tagged "CombatTarget" (a Model with Health / MaxHealth attributes)
	can be punched; see the practice slime in the arena.
	Every hit that lands and does damage is marked on the target as "HitFx"
	("count:weight:x:z" - weight 1-3, 3 a finisher; x, z the way the blow
	drove it): every screen flashes it white and it flinches (CombatClient,
	BossClient). Its OnHit BindableEvent, if it has one, hears
	(player, damage, killed, weight, direction) - the Colosseum knocks its
	dummies back with that.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Moves = require(ReplicatedStorage:WaitForChild("Moves"))

local CombatService = {}

local CC = Config.Combat
local PlayerService = nil -- set in Start (avoids a require loop)
local remotes = {}
local fighters = {} -- [player] = combat state while in an arena
local targets = {} -- [model] = true for every punchable enemy
local whiffListeners = {} -- functions that hear about punches at thin air (CombatService.OnWhiff)

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

-- the Spire floor a player is fighting on, as it is on their tier (a harder
-- tier's floors are at higher levels: Config.spireFloorFor)
local function floorOf(player)
	local id = player:GetAttribute("SpireFloor")
	for _, f in ipairs(Config.Spire.Floors) do
		if f.id == id then
			return Config.spireFloorFor and Config.spireFloorFor(f.id, player:GetAttribute("SpireTier")) or f
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
	if not st.free then
		st.stamina = math.max(0, st.stamina - amount)
	end
	st.lastSpend = now
end

-- Fighting Oozlet in the intro? (IntroService: "Void" is before it's angry -
-- you can already punch it - and "Fight" after; "Reveal" is the end)
local function introFight(player)
	local stage = player:GetAttribute("Intro")
	return stage == "Void" or stage == "Fight"
end

-- what your level gives you: more damage, less damage taken (capped; see
-- Config.LevelBonus)
local function levelOf(player)
	local d = PlayerService and PlayerService.GetData(player)
	local t = Config.statBonus(d)
	t.Defense = math.min(t.Defense, Config.MaxDefense or 60)
	return t
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
	local level = target and target:GetAttribute("Level")
	if level then
		floor = { level = level } -- (a Colosseum dummy: its own level, not a floor's)
	end
	local base
	if target and target:GetAttribute("StudioFair") and RunService:IsStudio() then
		base = math.max(1, math.floor(Config.powerForLevel((floor and floor.level) or 1)))
	else
		base = CombatService.PunchDamage(player, floor)
	end
	return CombatService.WithLevel(player, base)
end

-- Your level on top of a punch: more damage. (Critical hits come from a
-- weapon's Crit effect: boostHit.) Returns the damage and false (no crit).
function CombatService.WithLevel(player, base)
	local dmg = base * (1 + levelOf(player).Damage / 100)
	return math.max(1, math.floor(dmg)), false
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
local blockIncoming -- (set in "Ability building blocks" below)
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
	-- your weapon ability's guard or shield
	if blockIncoming then
		amount = blockIncoming(player, st, amount)
		if amount <= 0 then
			if not quiet then
				send(player, "Dodged")
			end
			return false
		end
	end
	-- a harder Spire's bosses hit harder (Config.spireTierDamage: their hits
	-- take the tier's share of your health, whatever your level gives you)
	local floorId = player:GetAttribute("SpireFloor")
	if floorId and player:GetAttribute("SpireTier") and Config.spireTierDamage then
		amount = amount * Config.spireTierDamage(floorId, player:GetAttribute("SpireTier"))
	end
	-- your level's defence takes a share off every hit
	amount = amount * (1 - levelOf(player).Defense / 100)
	-- a hit that would finish you in a boss fight: a REVIVE ticket (the shop's)
	-- stands you back up at half health, a moment untouchable (ShopService.Revive)
	if amount >= hum.Health and CombatService.ReviveHook and player:GetAttribute("SpireFloor") ~= nil then
		local ok, revived = pcall(CombatService.ReviveHook, player)
		if ok and revived then
			hum.Health = hum.MaxHealth * 0.5
			st.iframeUntil = os.clock() + 2
			send(player, "Iframes", 2)
			return true
		end
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

-- Flings a player up (and along) without hurting them - a jump pad. Unlike a
-- shove they keep flying afterwards, so they sail up and come down in an arc.
-- The movement guard is told it's the server's own move.
function CombatService.Launch(player, velocity)
	local _, root = charParts(player)
	if fighters[player] and root and typeof(velocity) == "Vector3" then
		player:SetAttribute("MoveTo", root.Position + velocity * 0.6)
		player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + 2)
		send(player, "Launch", velocity)
	end
end

-- Something (a boss) wants to hear about punches that hit nothing: `fn(player,
-- position)` is called for each one, from where the player stood.
function CombatService.OnWhiff(fn)
	table.insert(whiffListeners, fn)
end

-- Fills a fighter's flasks back up (a Colosseum run starting over: a fresh start)
function CombatService.RefillFlasks(player)
	local st = fighters[player]
	if st then
		st.flasks = CC.Flasks
		pushState(player, st)
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

-- A big or odd-shaped target (the Brute, a split-up Tuber) can tell us its
-- shape: a function that gives the point of its body nearest a spot, and how
-- thick it is there. Then a punch lands wherever you hit its body, not just
-- near its middle. Anything that doesn't (Gloomgut, the dummies) is judged
-- from its middle as always.
local shapes = setmetatable({}, { __mode = "k" })
function CombatService.SetTargetShape(model, nearest)
	shapes[model] = nearest
end

-- where on a target a punch from `from` meets it, and its thickness there
local function aimAt(model, from)
	local shape = shapes[model]
	if shape then
		local ok, point, radius = pcall(shape, from)
		if ok and typeof(point) == "Vector3" then
			return point, radius or targetRadius(model)
		end
	end
	local cf = targetPivot(model)
	return cf and cf.Position, targetRadius(model)
end

-- The enemy your punch lands on: the closest one in reach that's in front
-- of you (within a cone round the way your character is facing). Punching
-- the air hits nothing.
local PUNCH_CONE = math.cos(math.rad(55))
-- Can this player hit this target? (A Colosseum dummy belongs to one player.)
local function mine(model, player)
	local owner = model:GetAttribute("Owner")
	return owner == nil or owner == player.UserId
end

local function nearestTarget(root, player)
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)
	local best, bestDist = nil, math.huge
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 and mine(model, player) then
			local cf, radius = aimAt(model, root.Position)
			if cf then
				local flat = Vector3.new(cf.X - root.Position.X, 0, cf.Z - root.Position.Z)
				local centre = flat.Magnitude
				local d = centre - radius
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

local function hitTarget(player, model, damage, weight, remote)
	-- A boss can be untouchable (rising, breaking its shell, dying), and can
	-- hold a floor under its health so a big hit can't skip a phase change.
	if model:GetAttribute("Invulnerable") then
		damage = 0
	end
	-- A boss with IFrames shrugs off hits for that long after each one lands
	-- (whoever threw them), so you can't just hold the button down.
	local iframes = tonumber(model:GetAttribute("IFrames"))
	if iframes and damage > 0 then
		local t = os.clock()
		if t < (model:GetAttribute("IFramesUntil") or 0) then
			damage = 0
		else
			model:SetAttribute("IFramesUntil", t + iframes)
		end
	end
	-- A shield (the Colosseum's Iron Knight): a punch from in front of it -
	-- within ShieldArc degrees of the way it faces (FrontDir) - bounces off.
	local arc = tonumber(model:GetAttribute("ShieldArc"))
	local front = model:GetAttribute("FrontDir")
	if arc and typeof(front) == "Vector3" and front.Magnitude > 0.01 and damage > 0 then
		local _, rootS = charParts(player)
		local pivot = model:GetPivot().Position
		local toPlayer = rootS and Vector3.new(rootS.Position.X - pivot.X, 0, rootS.Position.Z - pivot.Z)
		if toPlayer and toPlayer.Magnitude > 0.01 then
			local cosA = toPlayer.Unit:Dot(Vector3.new(front.X, 0, front.Z).Unit)
			if cosA >= math.cos(math.rad(arc / 2)) then
				send(player, "Blocked", pivot + Vector3.new(0, 2, 0))
				local onBlock = model:FindFirstChild("OnBlock")
				if onBlock and onBlock:IsA("BindableEvent") then
					onBlock:Fire(player)
				end
				return
			end
		end
	end
	local floorHp = model:GetAttribute("MinHealth") or 0
	local before = model:GetAttribute("Health") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	model:SetAttribute("Health", math.max(0, hp))
	updateTargetBar(model)
	local _, root0 = charParts(player)
	local at = aimAt(model, root0 and root0.Position or Vector3.new())
	local cf = at and CFrame.new(at)
	local killed = hp <= 0
	weight = math.clamp(weight or 1, 1, 3)
	-- (a puddle's or trail's burn - remote == "tick" - is a small repeated hit:
	-- your screen shows its number but doesn't jolt your swing for it)
	local tick = remote == "tick"
	send(player, "Hit", cf and cf.Position or Vector3.new(), damage, killed, weight, tick or nil)
	-- which way the blow drives it (flat, away from you), and every screen
	-- sees it land: "HitFx" = "count:weight:x:z" - the enemy flashes white and
	-- flinches away (CombatClient, BossClient); the Colosseum's dummies are
	-- knocked back too (ColosseumService hears it through OnHit below)
	local push = Vector3.new(0, 0, 0)
	if at and root0 then
		local d = at - root0.Position
		push = Vector3.new(d.X, 0, d.Z)
		push = push.Magnitude > 0.01 and push.Unit or Vector3.new(0, 0, 0)
	end
	if damage > 0 then
		local count = (tonumber(string.match(tostring(model:GetAttribute("HitFx") or ""), "^(%d+)")) or 0) + 1
		model:SetAttribute("HitFx", string.format("%d:%d:%.3f:%.3f", count, weight, push.X, push.Z))
	end
	-- the shockwave, where the punch actually met them (an ability's hit from
	-- further away - `remote` - lands right on them, and no fist streak)
	local _, root = charParts(player)
	if cf and root then
		local toward = cf.Position - root.Position
		if tick then
			-- (no shockwave for a burn tick)
		elseif remote then
			impact(cf.Position, toward, weight)
		else
			local hitAt = root.Position + Vector3.new(toward.X, 0, toward.Z).Unit * math.min(toward.Magnitude, CC.PunchRange * 0.7)
			impact(Vector3.new(hitAt.X, cf.Position.Y, hitAt.Z), toward, weight)
			if player.Character then
				fistStreak(player.Character, toward, weight)
			end
		end
	end
	-- let a boss script react (it can listen to this BindableEvent)
	local onHit = model:FindFirstChild("OnHit")
	if onHit and onHit:IsA("BindableEvent") then
		onHit:Fire(player, damage, killed, weight, push)
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
-- Weapons (Config.Weapons): the weapon in your hand swings instead of your
-- fist, has one ability, and gets better the more you hit with it (mastery).
-- Everything that matters is decided here. The player's attributes tell
-- every screen what to draw (ReplicatedStorage/WeaponFX):
--   Weapon          the id of the weapon you're holding (nil: fists)
--   Mastery         its mastery level (1-100), MasteryProgress 0-1 into it
--   SwingN          "count:swing" - changes on every swing, so everyone's
--                   screen swings it (swing 1, 2 or 3 of the string)
--   AbilityN        "count:tier" - changes every time you use the ability
-- (Mastery isn't saved yet: that comes with owning weapons.)
----------------------------------------------------------------------
local W = Config.Weapons or { List = {}, Types = {}, MasteryMax = 100, MasteryPerHit = 1 }
local mastery = {} -- [player] = { [weapon id] = mastery points }

-- the weapon a player is holding: its entry in Config.Weapons.List, its type, its id
local function weaponOf(player)
	local id = player:GetAttribute("Weapon")
	local def = id and W.List[id]
	local kind = def and W.Types[def.Type]
	if def and kind then
		return def, kind, id
	end
	return nil
end

-- a player's saved weapons (PlayerService: data.Weapons), or nil
local function savedWeapons(player)
	local d = PlayerService and PlayerService.GetData and PlayerService.GetData(player)
	return d and d.Weapons
end

-- mastery points: saved for weapons you own; a dev test weapon you don't own
-- keeps its mastery for this session only
local function masteryPoints(player, id)
	local saved = savedWeapons(player)
	if saved and saved.own[id] then
		return saved.own[id]
	end
	local t = mastery[player]
	return t and t[id] or 0
end

local function showMastery(player, id)
	if id then
		local level, into = Config.masteryLevel(masteryPoints(player, id))
		player:SetAttribute("Mastery", level)
		player:SetAttribute("MasteryProgress", into)
	else
		player:SetAttribute("Mastery", nil)
		player:SetAttribute("MasteryProgress", nil)
	end
end

-- (the Arcade uses it: a duplicate's mastery shows on the card straight away)
CombatService.ShowMastery = showMastery

local function setMasteryPoints(player, id, points)
	local before = Config.masteryLevel(masteryPoints(player, id))
	points = math.clamp(math.floor(points), 0, Config.masteryPointsFor(W.MasteryMax))
	local saved = savedWeapons(player)
	if saved and saved.own[id] then
		saved.own[id] = points
		PlayerService.MarkDirty(player)
	else
		mastery[player] = mastery[player] or {}
		mastery[player][id] = points
	end
	showMastery(player, id)
	local after = Config.masteryLevel(points)
	if after > before then
		local def = W.List[id]
		local _, tierBefore = Config.abilityTier(def, before)
		local _, tierAfter = Config.abilityTier(def, after)
		-- "MASTERY 12!" - and when the ability gets better, what it does now
		send(player, "Mastery", after, tierAfter > tierBefore and tierAfter or nil)
	end
end

local function addMastery(player, id, points)
	if points > 0 then
		setMasteryPoints(player, id, masteryPoints(player, id) + points)
	end
end

-- Hold a weapon (an id in Config.Weapons.List), or nil for your fists again
function CombatService.Equip(player, id)
	if id ~= nil and not W.List[id] then
		return false
	end
	player:SetAttribute("Weapon", id)
	showMastery(player, id)
	-- (remembered for next time, if it's one you own - or fists)
	local saved = savedWeapons(player)
	if saved and (id == nil or saved.own[id]) and saved.hold ~= id then
		saved.hold = id
		PlayerService.MarkDirty(player)
	end
	return true
end

-- Every enemy you can hit within `range` studs of you (to its edge), and
-- within `arc` degrees either side of the way you face (180: all round you).
-- A locked-on target in range counts even if it's just outside the arc.
local function targetsInArc(root, player, range, arc, locked)
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)
	local cosArc = math.cos(math.rad(arc))
	local list = {}
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 and mine(model, player) then
			local cf, radius = aimAt(model, root.Position)
			if cf then
				local flat = Vector3.new(cf.X - root.Position.X, 0, cf.Z - root.Position.Z)
				local centre = flat.Magnitude
				local d = centre - radius
				local inArc = arc >= 180 or centre < 0.01 or d < 1 or facing:Dot(flat.Unit) >= cosArc or model == locked
				if d <= range and math.abs(cf.Y - root.Position.Y) < 12 and inArc then
					list[#list + 1] = model
				end
			end
		end
	end
	return list
end

local function restoreWalkSpeed(player, hum)
	local d = PlayerService and PlayerService.GetData(player)
	hum.WalkSpeed = Config.walkSpeedFor(player, d) -- capped while you're in an arena
	local cm = hum.Parent and hum.Parent:FindFirstChildWhichIsA("ControllerManager", true)
	if cm then
		cm.BaseMoveSpeed = hum.WalkSpeed
	end
end

----------------------------------------------------------------------
-- Ability building blocks (Config.Weapons.Blocks): the small effects most
-- weapons' abilities are made of - a buff for a few seconds (more damage,
-- lifesteal, a guard...), a one-hit shield, a bigger next hit, stacks that
-- burst. An ability lists them in its Effects; a weapon can also have
-- Passive ones that are always on while it's in your hand. Mastery makes
-- each one a bit stronger (Config.blockScale). Every screen sees them
-- through the player's attributes: Aura (a colour) with AuraUntil (server
-- time), Shield (true while it's up) and Stacks (a number).
----------------------------------------------------------------------
local blockRng = Random.new()
local function serverNow()
	return workspace:GetServerTimeNow()
end

-- every screen draws abilities (ReplicatedStorage/MoveFX): "AbilityFx" says
-- (player, weapon id, count, step, point, extra) - step 0 when a move starts,
-- a step's number when it picks a spot, or a name for a moment a building
-- block has (a stack bursting, a next hit landing, a crit, a lifesteal)
local function tell(player, id, count, step, point, extra)
	if remotes.AbilityFx then
		remotes.AbilityFx:FireAllClients(player, id, count, step, point, extra)
	end
end

-- an effect still running on this fighter (nil once it's worn off)
local function buff(st, name, now)
	local b = st.buffs and st.buffs[name]
	if b and b.untilT and now >= b.untilT then
		st.buffs[name] = nil
		return nil
	end
	return b
end

local function showBuffs(player, st, now)
	local shield = buff(st, "Shield", now)
	player:SetAttribute("Shield", shield and true or nil)
end

-- the weapon in hand's Passive effects (always on while you hold it)
local function passive(player, name)
	local def = weaponOf(player)
	for _, e in ipairs(def and def.Passive or {}) do
		if e.Block == name then
			return e
		end
	end
	return nil
end

-- switch on a list of effects (an ability's Effects), scaled by mastery
local function applyEffects(player, st, effects, scale, color)
	local now = os.clock()
	st.buffs = st.buffs or {}
	local longest = 0
	for _, e in ipairs(effects or {}) do
		local time = e.Time and e.Time * (1 + (scale - 1) * 0.5) or nil -- (mastery lengthens them a little too)
		local amount = (e.Amount or 0) * scale
		if e.Block == "StaminaRefill" then
			st.stamina = math.min(CC.MaxStamina, st.stamina + CC.MaxStamina * math.min(1, amount))
			pushState(player, st)
		elseif e.Block == "MoveSpeed" then
			local _, _, char = charParts(player)
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				restoreWalkSpeed(player, hum)
				hum.WalkSpeed = hum.WalkSpeed * (1 + amount)
				local cm = char:FindFirstChildWhichIsA("ControllerManager", true)
				if cm then
					cm.BaseMoveSpeed = hum.WalkSpeed
				end
				local token = {}
				st.speedToken = token
				task.delay(time or 4, function()
					if st.speedToken == token and hum.Parent then
						restoreWalkSpeed(player, hum)
					end
				end)
			end
		else
			st.buffs[e.Block] = { untilT = time and (now + time) or nil, amount = amount, e = e }
		end
		longest = math.max(longest, time or 0)
	end
	if longest > 0 then
		player:SetAttribute("Aura", color or Color3.fromRGB(255, 255, 255))
		player:SetAttribute("AuraUntil", serverNow() + longest)
		local move = Moves.of(player:GetAttribute("Weapon"))
		player:SetAttribute("AuraStyle", move and move.Style or nil)
	end
	showBuffs(player, st, now)
end

-- your hit, with your effects on top: returns the damage and whether it's a crit
local function boostHit(player, st, target, dmg, crit)
	local now = os.clock()
	local up = buff(st, "DamageUp", now)
	if up then
		dmg = dmg * (1 + up.amount)
	end
	local critUp = buff(st, "Crit", now)
	if critUp and not crit and blockRng:NextNumber() < critUp.amount then
		crit = true
		dmg = dmg * (Config.CritMultiplier or 1.75)
		if target then
			tell(player, player:GetAttribute("Weapon"), 0, "Crit", aimAt(target, target:GetPivot().Position))
		end
	end
	-- stacks (usually a Passive): each hit adds one; at Max, this hit bursts
	local stacks = passive(player, "Stacks") or (buff(st, "Stacks", now) and buff(st, "Stacks", now).e)
	if stacks then
		st.stacks = (st.stacks or 0) + 1
		if st.stacks >= (stacks.Max or 5) then
			st.stacks = 0
			dmg = dmg * (1 + (stacks.Amount or 0.5))
			crit = true
			if target then
				tell(player, player:GetAttribute("Weapon"), 0, "Stacks", aimAt(target, target:GetPivot().Position))
			end
		end
		player:SetAttribute("Stacks", st.stacks)
	end
	-- the next hit (used up by it); it can mark the target to take more for a while
	local nextHit = buff(st, "NextHit", now)
	if nextHit then
		st.buffs.NextHit = nil
		dmg = dmg * (1 + nextHit.amount)
		crit = true
		if target then
			tell(player, player:GetAttribute("Weapon"), 0, "NextHit", aimAt(target, target:GetPivot().Position))
		end
		if nextHit.e.Mark and target and target.Parent then
			target:SetAttribute("MarkedAmount", nextHit.e.Mark)
			target:SetAttribute("MarkedUntil", serverNow() + (nextHit.e.MarkTime or 3))
		end
	end
	-- a marked target takes more from everyone
	if target and (target:GetAttribute("MarkedUntil") or 0) > serverNow() then
		dmg = dmg * (1 + (target:GetAttribute("MarkedAmount") or 0))
	end
	return math.max(1, math.floor(dmg)), crit
end

-- after a hit lands: lifesteal and stamina back
local function afterHit(player, st, weight, target)
	local now = os.clock()
	local steal = buff(st, "Lifesteal", now)
	if steal then
		local hum = charParts(player)
		if hum then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * steal.amount * (weight or 1))
		end
		if target and target.Parent then
			tell(player, player:GetAttribute("Weapon"), 0, "Lifesteal", aimAt(target, target:GetPivot().Position))
		end
	end
	local back = buff(st, "StaminaOnHit", now)
	if back then
		st.stamina = math.min(CC.MaxStamina, st.stamina + back.amount)
	end
end

-- a hit coming at you: the guard takes a share, the shield eats it whole,
-- thorns sting the nearest enemy back. Returns what's left of it.
blockIncoming = function(player, st, amount)
	local now = os.clock()
	if buff(st, "Shield", now) then
		st.buffs.Shield = nil
		showBuffs(player, st, now)
		return 0
	end
	local guard = buff(st, "Guard", now)
	if guard then
		amount = amount * (1 - math.min(0.8, guard.amount))
	end
	local thorns = buff(st, "Thorns", now)
	if thorns then
		local _, root = charParts(player)
		local near = root and targetsInArc(root, player, thorns.e.Range or 14, 180)
		if near and near[1] then
			local dmg = CombatService.DamageAgainst(player, near[1])
			hitTarget(player, near[1], math.max(1, math.floor(dmg * thorns.amount)), 1)
		end
	end
	return amount
end

-- an area hit round you (an ability's Burst): hits everything within Radius
local function burst(player, st, def, id, spec, scale)
	local _, root = charParts(player)
	if not root then
		return
	end
	local mult = Config.weaponMultiplier(def, player:GetAttribute("Mastery") or 1) * (spec.Damage or 1.5) * scale
	local count = 0
	for _, target in ipairs(targetsInArc(root, player, spec.Radius or 10, 180)) do
		local dmg, crit = CombatService.DamageAgainst(player, target)
		dmg, crit = boostHit(player, st, target, dmg * mult, crit)
		hitTarget(player, target, dmg, crit and 3 or 2)
		afterHit(player, st, 1.5, target)
		count = count + 1
	end
	addMastery(player, id, (W.MasteryPerHit or 1) * count)
end

-- the buff kind of ability: switch its effects on (and its Burst, if any)
local function useBuffAbility(player, st, def, id, now)
	local ab = def.Ability
	if st.drinking or now < (st.abilityReadyAt or 0) or st.stamina < ab.Cost then
		send(player, "Denied", "Ability")
		return
	end
	local mastery = player:GetAttribute("Mastery") or 1
	local scale = Config.blockScale(mastery)
	st.abilityReadyAt = now + ab.Cooldown
	st.busyUntil = now + (ab.Busy or 0.25)
	spend(st, ab.Cost, now)
	st.abilities = (st.abilities or 0) + 1
	player:SetAttribute("PowerN", st.abilities) -- (every screen: a quick power-up flash)
	send(player, "Ability", ab.Cooldown, 0)
	applyEffects(player, st, ab.Effects, scale, ab.Aura)
	if ab.Burst then
		task.delay(ab.Burst.Delay or 0.15, function()
			if fighters[player] == st then
				burst(player, st, def, id, ab.Burst, scale)
			end
		end)
	end
end

----------------------------------------------------------------------
-- MOVES (ReplicatedStorage/Moves): a weapon ability done step by step - hit
-- round a spot, in a cone, along the path you dashed; leave a patch on the
-- floor that keeps hurting; throw things; switch on a special for a while.
-- Your own screen moves you (dashes, leaps) and plays the animation; the
-- server trusts where you end up and does the hitting at each step's time.
-- Every screen is told when a move starts (AbilityFx: player, weapon, count,
-- 0) and where any spot it picks is (step number, the spot), and draws it
-- (ReplicatedStorage/MoveFX).
----------------------------------------------------------------------
local zones = {} -- the patches on the floor that keep hurting
local moveCount = {} -- [player] = how many moves they've made (tells them apart)

-- where you are and the way you face, flat
local function flatFrame(root)
	local look = root.CFrame.LookVector
	local f = Vector3.new(look.X, 0, look.Z)
	f = f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(root.Position, root.Position + f)
end

-- every enemy of yours whose body comes within `radius` of a spot (flat)
local function targetsNear(point, player, radius)
	local list = {}
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 and mine(model, player) then
			local cf, r = aimAt(model, point)
			if cf then
				local d = Vector3.new(cf.X - point.X, 0, cf.Z - point.Z).Magnitude - r
				if d <= radius and math.abs(cf.Y - point.Y) < 14 then
					list[#list + 1] = model
				end
			end
		end
	end
	return list
end

-- every enemy within width/2 of the path a -> b (flat)
local function targetsOnLine(a, b, player, width)
	local list = {}
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len2 = ab:Dot(ab)
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 and mine(model, player) then
			local mid = a:Lerp(b, 0.5)
			local cf, r = aimAt(model, mid)
			if cf then
				local ap = Vector3.new(cf.X - a.X, 0, cf.Z - a.Z)
				local t = len2 > 1e-6 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
				local closest = Vector3.new(a.X, 0, a.Z) + ab * t
				local d = (Vector3.new(cf.X, 0, cf.Z) - closest).Magnitude - r
				if d <= width / 2 and math.abs(cf.Y - a.Y) < 14 then
					list[#list + 1] = model
				end
			end
		end
	end
	return list
end

-- hit a list of enemies with a move (dmg: x your hit, like a swing's Damage)
local function moveHits(player, st, def, id, list, dmg, weight, scale, remote)
	if #list == 0 then
		return 0
	end
	local mult = Config.weaponMultiplier(def, player:GetAttribute("Mastery") or 1) * (dmg or 1) * (scale or 1)
	for _, target in ipairs(list) do
		local d, crit = CombatService.DamageAgainst(player, target)
		d, crit = boostHit(player, st, target, d * mult, crit)
		hitTarget(player, target, d, crit and 3 or (weight or 2), remote)
		afterHit(player, st, math.min(dmg or 1, 1.5), target)
	end
	addMastery(player, id, (W.MasteryPerHit or 1) * #list)
	return #list
end

-- the spot a move picks: the enemy you're locked on to (in range), else the
-- nearest one in front of you, else `ahead` studs in front
local function pickPoint(player, root, range, ahead, locked)
	local here = root.Position
	if typeof(locked) == "Instance" and targets[locked] and locked.Parent and (locked:GetAttribute("Health") or 0) > 0 and mine(locked, player) then
		local cf, r = aimAt(locked, here)
		if cf and Vector3.new(cf.X - here.X, 0, cf.Z - here.Z).Magnitude - r <= range then
			return Vector3.new(cf.X, here.Y, cf.Z), locked
		end
	end
	local frame = flatFrame(root)
	local best, bestD, bestModel = nil, math.huge, nil
	for model in pairs(targets) do
		if model.Parent and (model:GetAttribute("Health") or 0) > 0 and mine(model, player) then
			local cf, r = aimAt(model, here)
			if cf then
				local flat = Vector3.new(cf.X - here.X, 0, cf.Z - here.Z)
				local d = flat.Magnitude - r
				local front = flat.Magnitude < 0.01 or frame.LookVector:Dot(flat.Unit) >= math.cos(math.rad(60))
				if d <= range and front and math.abs(cf.Y - here.Y) < 14 and d < bestD then
					best, bestD, bestModel = Vector3.new(cf.X, here.Y, cf.Z), d, model
				end
			end
		end
	end
	if best then
		return best, bestModel
	end
	return (frame * CFrame.new(0, 0, -(ahead or 8))).Position, nil
end

-- a hit shape, from the step and where things are
local function shapeHit(player, st, def, id, spec, frame, marks, scale)
	local list
	if spec.Shape == "Arc" then
		local _, root = charParts(player)
		list = root and targetsInArc(root, player, spec.Radius or 10, spec.Arc or 60, st.moveLocked) or {}
	elseif spec.Shape == "Line" then
		local a = marks[spec.From or "Start"] or frame.Position
		local b = spec.To and marks[spec.To] or frame.Position
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		dir = dir.Magnitude > 0.01 and dir.Unit or frame.LookVector
		b = b + dir * (spec.Ahead or 0)
		list = targetsOnLine(a, b, player, spec.Width or 6)
	else -- Circle
		local centre = spec.At and marks[spec.At] or (frame * CFrame.new(spec.Side or 0, 0, -(spec.Ahead or 0))).Position
		list = targetsNear(centre, player, spec.Radius or 8)
	end
	return moveHits(player, st, def, id, list, spec.Damage, spec.Weight, scale, spec.Shape ~= "Arc")
end

-- a patch on the floor that hurts every Tick seconds for Time (and slows)
local function addZone(player, st, def, id, spec, frame, marks, scale, at)
	local z = { player = player, st = st, def = def, id = id, spec = spec, scale = scale,
		untilT = os.clock() + (spec.Time or 3), nextT = os.clock() + (spec.Tick or 0.5) }
	if spec.Strip then
		z.a = marks[spec.From or "Start"] or frame.Position
		z.b = spec.To and marks[spec.To] or frame.Position
	else
		z.centre = at or (spec.At and marks[spec.At]) or (frame * CFrame.new(spec.Side or 0, 0, -(spec.Ahead or 0))).Position
	end
	table.insert(zones, z)
end

local function stepZones()
	local now = os.clock()
	for i = #zones, 1, -1 do
		local z = zones[i]
		if now >= z.untilT or fighters[z.player] ~= z.st then
			table.remove(zones, i)
		elseif now >= z.nextT then
			z.nextT = now + (z.spec.Tick or 0.5)
			local list = z.centre and targetsNear(z.centre, z.player, z.spec.Radius or 6)
				or targetsOnLine(z.a, z.b, z.player, z.spec.Width or 4)
			if z.spec.Slow then
				for _, target in ipairs(list) do
					target:SetAttribute("SlowAmount", z.spec.Slow)
					target:SetAttribute("SlowUntil", serverNow() + (z.spec.Tick or 0.5) + 0.25)
				end
			end
			moveHits(z.player, z.st, z.def, z.id, list, z.spec.Damage or 0.2, 1, z.scale, "tick")
		end
	end
end

-- things thrown along the floor (barrels, globs, clods): each flies from you,
-- hurts what it meets (once each), and bursts / leaves a patch where it ends
local function throw(player, st, def, id, spec, frame, marks, scale)
	local n = spec.Count or 1
	for i = 1, n do
		local angle
		if spec.Around then
			angle = (i - 1) / n * 360
		else
			angle = ((i - 1) - (n - 1) / 2) * (spec.Spread or 0)
		end
		local dir = (frame * CFrame.Angles(0, math.rad(angle), 0)).LookVector
		local start = frame.Position + dir * 1.5
		task.spawn(function()
			local hit = {}
			local travelled = 0
			local range = spec.Range or 12
			local speed = spec.Speed or 24
			local pos = start
			while travelled < range and fighters[player] == st do
				local dt = task.wait(1 / 30)
				travelled = math.min(range, travelled + speed * dt)
				pos = start + dir * travelled
				local fresh = {}
				for _, target in ipairs(targetsNear(pos, player, spec.Radius or 3)) do
					if not hit[target] then
						hit[target] = true
						fresh[#fresh + 1] = target
					end
				end
				if #fresh > 0 then
					moveHits(player, st, def, id, fresh, spec.Damage or 1, 2, scale, true)
					if not spec.Pierce then
						break
					end
				end
			end
			if fighters[player] ~= st then
				return
			end
			if spec.Burst then
				moveHits(player, st, def, id, targetsNear(pos, player, spec.Burst.Radius or 5), spec.Burst.Damage or 1, 3, scale, true)
			end
			if spec.Zone then
				addZone(player, st, def, id, spec.Zone, frame, marks, scale, pos)
			end
		end)
	end
end

-- a move's special (for Time seconds): see swingWeapon (ChopWave, Clones) and Roll (DashHits)
local function special(st, spec, scale)
	st.buffs = st.buffs or {}
	st.buffs[spec.Special] = { untilT = os.clock() + (spec.Time or 5) * (1 + (scale - 1) * 0.5), amount = scale, e = spec }
end

-- a move: switch on its building blocks, then do each step when it's due
local function useMove(player, st, def, id, move, now, locked)
	local ab = def.Ability
	if st.drinking or now < (st.abilityReadyAt or 0) or st.stamina < ab.Cost then
		send(player, "Denied", "Ability")
		return
	end
	local mastery = player:GetAttribute("Mastery") or 1
	local scale = Config.blockScale(mastery)
	st.abilityReadyAt = now + ab.Cooldown
	st.busyUntil = now + (move.Time or 0.6)
	spend(st, ab.Cost, now)
	st.abilities = (st.abilities or 0) + 1
	st.moveLocked = typeof(locked) == "Instance" and locked or nil
	moveCount[player] = (moveCount[player] or 0) + 1
	local count = moveCount[player]
	player:SetAttribute("AuraStyle", move.Style)
	send(player, "Ability", ab.Cooldown, 0)
	applyEffects(player, st, ab.Effects, scale, ab.Aura)
	tell(player, id, count, 0)
	local marks = {}
	local done = {} -- [step] = true once it's happened (a Contact step can come early)
	for i, step in ipairs(move.Steps or {}) do
		-- a Contact step (Barrel Roll's burst) happens the moment you run into
		-- an enemy - within Contact studs of you - or at its time if you never do
		if step.Contact then
			task.spawn(function()
				local stop = os.clock() + (step.At or 0)
				while os.clock() < stop and not done[i] and fighters[player] == st do
					task.wait(1 / 30)
					local _, root = charParts(player)
					if root and #targetsNear(root.Position, player, step.Contact) > 0 and not done[i] then
						done[i] = true
						local frame = flatFrame(root)
						if step.Hit then
							shapeHit(player, st, def, id, step.Hit, frame, marks, scale)
						end
						tell(player, id, count, i) -- (every screen bursts it now)
					end
				end
			end)
		end
		task.delay(step.At or 0, function()
			if fighters[player] ~= st or done[i] then
				return
			end
			done[i] = true
			local _, root = charParts(player)
			if not root then
				return
			end
			local frame = flatFrame(root)
			if step.Mark then
				marks[step.Mark] = frame.Position
			end
			if step.Pick then
				local point = pickPoint(player, root, step.Range or 20, step.Ahead or 8, st.moveLocked)
				marks[step.Pick] = point
				tell(player, id, count, i, point)
			end
			if step.Hit then
				shapeHit(player, st, def, id, step.Hit, frame, marks, scale)
			end
			if step.Zone then
				addZone(player, st, def, id, step.Zone, frame, marks, scale)
			end
			if step.Shot then
				throw(player, st, def, id, step.Shot, frame, marks, scale)
			end
			if step.Buff and step.Buff.Special then
				special(st, step.Buff, scale)
			end
		end)
	end
end

-- One swing of a weapon: like a punch (it commits you, costs stamina and lands
-- partway through), but it cuts every enemy in its arc, hits as hard as the
-- weapon's rarity and mastery say, and every enemy it hits is mastery.
local function swingWeapon(player, st, def, kind, id, locked, swing, now)
	local n = (type(swing) == "number" and swing == swing and math.clamp(math.floor(swing), 1, #kind.Swings)) or 1
	local s = kind.Swings[n]
	if st.drinking or now < (st.busyUntil or 0) or now - st.lastPunch < (st.lastLock or 0) * 0.85 or st.stamina < s.Cost then
		return
	end
	st.lastPunch, st.lastLock = now, s.Lock
	spend(st, s.Cost, now)
	st.swings = (st.swings or 0) + 1
	player:SetAttribute("SwingN", st.swings .. ":" .. n) -- (everyone's screen swings it)
	locked = typeof(locked) == "Instance" and locked or nil
	task.delay(s.Lock * s.Contact, function()
		if fighters[player] ~= st then
			return -- left the arena, died, or otherwise stopped fighting
		end
		local _, atRoot = charParts(player)
		if not atRoot then
			return
		end
		local tnow = os.clock()
		local reach = buff(st, "Reach", tnow)
		local hit = targetsInArc(atRoot, player, s.Range + (reach and reach.amount or 0), s.Arc, locked)
		-- a move's special still running: No Quarter's gold wave off every
		-- chop, Copy-Paste's two ink copies swinging with you
		local frame = flatFrame(atRoot)
		local wave = buff(st, "ChopWave", tnow)
		if wave then
			local centre = (frame * CFrame.new(0, 0, -5)).Position
			tell(player, id, 0, "ChopWave", centre)
			moveHits(player, st, def, id, targetsNear(centre, player, 6), 0.5, 2, wave.amount, true)
		end
		local clones = buff(st, "Clones", tnow)
		if clones then
			tell(player, id, 0, "Clones", atRoot.Position, n)
			for _, side in ipairs({ -5, 5 }) do
				local centre = (frame * CFrame.new(side, 0, -s.Range * 0.5)).Position
				moveHits(player, st, def, id, targetsNear(centre, player, s.Range * 0.55), s.Damage * 0.5, 2, 1, true)
			end
		end
		if #hit == 0 then
			for _, fn in ipairs(whiffListeners) do
				pcall(fn, player, atRoot.Position)
			end
			return
		end
		local mult = Config.weaponMultiplier(def, player:GetAttribute("Mastery") or 1) * s.Damage
		for _, target in ipairs(hit) do
			local dmg, crit = CombatService.DamageAgainst(player, target)
			dmg, crit = boostHit(player, st, target, dmg * mult, crit)
			hitTarget(player, target, dmg, (crit or n == #kind.Swings) and 3 or n)
			afterHit(player, st, s.Damage, target)
		end
		addMastery(player, id, (W.MasteryPerHit or 1) * #hit)
	end)
end


-- The weapon's ability (the Iron Sword's Whirlwind: spin round, cutting
-- everything close to you). What it does comes from its tier - the highest
-- mastery you've reached (Config.Weapons.List[id].Ability.Tiers).
local function useAbility(player, st, def, id, now, locked)
	local ab = def.Ability
	if not ab then
		return
	end
	local move = Moves.of(id)
	if move and not ab.Tiers then
		useMove(player, st, def, id, move, now, locked)
		return
	end
	if not ab.Tiers then
		useBuffAbility(player, st, def, id, now)
		return
	end
	if st.drinking or now < (st.abilityReadyAt or 0) or st.stamina < ab.Cost then
		send(player, "Denied", "Ability")
		return
	end
	local tier, tierIndex = Config.abilityTier(def, player:GetAttribute("Mastery") or 1)
	local spinTime = ab.SpinTime or 0.32
	st.abilityReadyAt = now + ab.Cooldown
	st.busyUntil = now + spinTime * tier.Spins -- (no swinging mid-spin)
	spend(st, ab.Cost, now)
	st.abilities = (st.abilities or 0) + 1
	player:SetAttribute("AbilityN", st.abilities .. ":" .. tierIndex) -- (everyone's screen spins it)
	send(player, "Ability", ab.Cooldown, tierIndex)
	local mult = Config.weaponMultiplier(def, player:GetAttribute("Mastery") or 1)
	for spin = 1, tier.Spins do
		-- each spin cuts halfway round (the blade's gone all the way round by then)
		task.delay(spinTime * (spin - 0.5), function()
			if fighters[player] ~= st then
				return
			end
			local _, atRoot = charParts(player)
			if not atRoot then
				return
			end
			local last = spin == tier.Spins
			local cut = {}
			local count = 0
			for _, target in ipairs(targetsInArc(atRoot, player, tier.Radius, 180)) do
				cut[target] = true
				count = count + 1
				local dmg, crit = CombatService.DamageAgainst(player, target)
				dmg, crit = boostHit(player, st, target, dmg * mult * tier.Damage, crit)
				hitTarget(player, target, dmg, (crit or last) and 3 or 2)
				afterHit(player, st, 1, target)
			end
			-- the shockwave off the last spin: what's a little further out
			if last and tier.Ring then
				for _, target in ipairs(targetsInArc(atRoot, player, tier.Ring, 180)) do
					if not cut[target] then
						count = count + 1
						local dmg = CombatService.DamageAgainst(player, target)
						hitTarget(player, target, math.max(1, math.floor(dmg * mult * (tier.RingDamage or 1))), 2)
					end
				end
			end
			addMastery(player, id, (W.MasteryPerHit or 1) * count)
		end)
	end
end

----------------------------------------------------------------------
-- Fighters (players in an arena)
----------------------------------------------------------------------
local function startFighting(player)
	fighters[player] = {
		free = introFight(player), -- (the intro: nothing costs stamina)
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
	-- (ability effects end with the fight)
	player:SetAttribute("Aura", nil)
	player:SetAttribute("AuraUntil", nil)
	player:SetAttribute("Shield", nil)
	player:SetAttribute("Stacks", nil)
end

local function onFloorChanged(player)
	local fighting = player:GetAttribute("SpireFloor") or player:GetAttribute("Colosseum") or introFight(player)
	if fighting then
		startFighting(player)
	else
		stopFighting(player)
	end
	-- Shift is the dodge roll in a fight, so Roblox's own Shift Lock is off
	-- there (it's back in the lobby)
	pcall(function()
		player.DevEnableMouseLock = not fighting
	end)
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

	-- holding a weapon: it swings instead of your fist (see "Weapons" above)
	local weapon, weaponKind, weaponId = weaponOf(player)
	if action == "Punch" and weapon then
		swingWeapon(player, st, weapon, weaponKind, weaponId, arg, swing, now)
		return
	elseif action == "Ability" then
		if weapon then
			useAbility(player, st, weapon, weaponId, now, arg)
		end
		return
	end

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
			if locked and targets[locked] and locked.Parent and (locked:GetAttribute("Health") or 0) > 0 and mine(locked, player) then
				local cf, radius = aimAt(locked, atRoot.Position)
				if cf then
					local d = (Vector3.new(cf.X, 0, cf.Z) - Vector3.new(atRoot.Position.X, 0, atRoot.Position.Z)).Magnitude - radius
					if d <= CC.PunchRange and math.abs(cf.Y - atRoot.Position.Y) < 12 then
						target = locked
					end
				end
			end
			target = target or nearestTarget(atRoot, player)
			if target then
				local dmg, crit = CombatService.DamageAgainst(player, target)
				hitTarget(player, target, dmg, crit and 3 or weight) -- (a crit lands as the heaviest punch)
			else
				-- a punch at thin air: anything listening hears about it (Kaze
				-- feeds on your misses)
				for _, fn in ipairs(whiffListeners) do
					pcall(fn, player, atRoot.Position)
				end
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
		-- a move's special: every roll cuts through what it passes (Victory Lap)
		local dash = buff(st, "DashHits", now)
		if dash and weapon then
			local from = root.Position
			task.delay(CC.RollTime + 0.12, function()
				local _, r2 = charParts(player)
				if fighters[player] == st and r2 then
					tell(player, weaponId, 0, "DashHit", r2.Position, from)
					moveHits(player, st, weapon, weaponId, targetsOnLine(from, r2.Position, player, 7), 1.0, 2, dash.amount, true)
				end
			end)
		end
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
		-- everyone sees you drink: every screen animates a character with this
		-- set (CombatClient's "The drink, as everyone sees it")
		local drinker = player.Character
		if drinker then
			drinker:SetAttribute("Drinking", CC.FlaskDrinkTime)
		end
		task.delay(CC.FlaskDrinkTime, function()
			if drinker then
				drinker:SetAttribute("Drinking", nil)
			end
			st.drinking = false
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and fighters[player] == st then
				h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * CC.FlaskHeal)
				restoreWalkSpeed(player, h)
				send(player, "Healed")
			end
		end)
	elseif action == "DevIncoming" and Config.isDev(player) then
		-- dev test (Studio, or the game's owner): a hit lands in 1 second, so you can practise rolling through it
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
	action.Name = "CombatAction" -- client -> server: "Punch" / "Roll" / "Jump" / "Heal" / "Ability"
	action.Parent = folder
	local event = Instance.new("RemoteEvent")
	event.Name = "CombatEvent" -- server -> client: "State", "Hit", "Hurt", "Shove", "Iframes", "Dodged", "Drinking", "Healed", "Denied", "Died", "Stop", "Ability", "Mastery"
	event.Parent = folder
	local fx = Instance.new("RemoteEvent")
	fx.Name = "AbilityFx" -- server -> every client: how abilities look (ReplicatedStorage/MoveFX)
	fx.Parent = folder
	folder.Parent = ReplicatedStorage
	remotes.CombatAction = action
	remotes.CombatEvent = event
	remotes.AbilityFx = fx
	RunService.Heartbeat:Connect(stepZones)

	action.OnServerEvent:Connect(function(player, name, arg, swing)
		if type(name) ~= "string" then
			return
		end
		local ok, err = pcall(onAction, player, name, arg, swing)
		if not ok then
			warn("[CombatService] " .. name .. " failed: " .. tostring(err))
		end
	end)

	-- Hold one of your own weapons (the BAG), or nil for your fists
	if PlayerService and PlayerService.AddAction then
		PlayerService.AddAction("EquipWeapon", function(player, data, id)
			if id == nil or id == false then
				CombatService.Equip(player, nil)
				return true, "Back to your fists."
			end
			local def = type(id) == "string" and W.List[id]
			if not def or not (data.Weapons and data.Weapons.own[id]) then
				return false, "You don't own that weapon."
			end
			if not W.Types[def.Type] then
				return false, def.Type .. " weapons aren't swingable yet - coming soon."
			end
			CombatService.Equip(player, id)
			return true, def.Name .. " equipped!"
		end)
	end

	-- when your save loads, the weapon you were holding goes back in your hand
	local function restoreWeapon(player)
		task.spawn(function()
			for _ = 1, 120 do -- (up to a minute: a save can wait on another server)
				if not player.Parent then
					return
				end
				local saved = savedWeapons(player)
				if saved then
					if saved.hold and saved.own[saved.hold] and W.List[saved.hold] then
						CombatService.Equip(player, saved.hold)
					end
					return
				end
				task.wait(0.5)
			end
		end)
	end
	Players.PlayerAdded:Connect(restoreWeapon)
	for _, p in ipairs(Players:GetPlayers()) do
		restoreWeapon(p)
	end

	-- DEV ONLY (Studio, or the game's owner): the weapon test buttons on the
	-- dev console - "DEV: Test Sword" and "DEV: Mastery +25"
	if PlayerService and PlayerService.AddAction then
		PlayerService.AddAction("DevTestWeapon", function(player)
			if not Config.isDev(player) then
				return false, "Dev tools are only for the game's owner."
			end
			if player:GetAttribute("Weapon") then
				CombatService.Equip(player, nil)
				return true, "Back to your fists."
			end
			local def = W.Test and W.List[W.Test]
			if not def then
				return false, "There's no test weapon in Config.Weapons."
			end
			CombatService.Equip(player, W.Test)
			return true, def.Name .. " in hand! It swings in fights" .. (def.Ability and (" - F is " .. def.Ability.Name) or "") .. "."
		end)
		-- "DEV: Next Sword": fists -> each sword in Config.Weapons.TestList -> fists
		PlayerService.AddAction("DevNextWeapon", function(player)
			if not Config.isDev(player) then
				return false, "Dev tools are only for the game's owner."
			end
			local list = W.TestList or { W.Test }
			local now = player:GetAttribute("Weapon")
			local nextId = list[1]
			for i, id in ipairs(list) do
				if id == now then
					nextId = list[i + 1]
				end
			end
			if not nextId then
				CombatService.Equip(player, nil)
				return true, "Back to your fists."
			end
			local def = W.List[nextId]
			if not def then
				return false, "There's no weapon " .. tostring(nextId) .. " in Config.Weapons."
			end
			CombatService.Equip(player, nextId)
			return true, def.Name .. " in hand (" .. def.Rarity .. ") - swing it in a fight."
		end)
		-- "DEV: All Weapons": own every pack weapon (to try them in the Weapons panel)
		PlayerService.AddAction("DevAllWeapons", function(player)
			if not Config.isDev(player) then
				return false, "Dev tools are only for the game's owner."
			end
			local n = 0
			for id, def in pairs(W.List) do
				if def.Pack and PlayerService.GiveWeapon and PlayerService.GiveWeapon(player, id) then
					n = n + 1
				end
			end
			return true, n > 0 and ("You now own " .. n .. " more weapons - press B.") or "You already own them all."
		end)
		PlayerService.AddAction("DevMastery", function(player)
			if not Config.isDev(player) then
				return false, "Dev tools are only for the game's owner."
			end
			local def, _, id = weaponOf(player)
			if not def then
				return false, "Hold a weapon first (DEV: Test Sword)."
			end
			-- up to the next quarter (25, 50, 75, 100), then back to 1
			local level = player:GetAttribute("Mastery") or 1
			local want = level >= W.MasteryMax and 1 or math.min(W.MasteryMax, math.floor(level / 25) * 25 + 25)
			setMasteryPoints(player, id, Config.masteryPointsFor(want))
			local _, tierIndex = Config.abilityTier(def, want)
			local say = def.Ability and def.Ability.Say and def.Ability.Say[tierIndex] or ""
			return true, "Mastery " .. want .. (say ~= "" and (": " .. say) or "")
		end)
	end

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
			elseif player:GetAttribute("Colosseum") then
				fighters[player] = nil -- (ColosseumService sends you home when you respawn)
			end
			CombatService.Disintegrate(char)
		end)
	end
	local function watch(player)
		player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
			onFloorChanged(player)
		end)
		player:GetAttributeChangedSignal("Colosseum"):Connect(function()
			onFloorChanged(player)
		end)
		-- the intro: on when Oozlet can be punched, off when it's over
		-- (going from "Void" to "Fight" changes nothing: you were already fighting)
		player:GetAttributeChangedSignal("Intro"):Connect(function()
			if introFight(player) ~= (fighters[player] ~= nil) then
				onFloorChanged(player)
			end
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
		mastery[player] = nil
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
