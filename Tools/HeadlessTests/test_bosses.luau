--!nocheck
-- GOLDEN TRACES of the Spire's bosses (see golden.sh). It fights a boss with
-- pretend players in the pretend Roblox, with the real BossService (and its
-- per-boss modules), and prints what happened in fine detail:
--   server mode: every tenth of a second, every attribute on the boss model
--     (sorted), where it is and the arena's state, plus every call it makes on
--     CombatService / PlayerService (damage, shoves, rewards...) as it makes it
--   client mode: the same fight with the real BossClient (and its body
--     modules) drawing it on the pretend player's screen; five times a second,
--     a fingerprint of everything it has drawn or changed (every part's place,
--     size, colour, see-through; its GUI, sounds and lights; the arena parts it
--     moved or recoloured), plus every camera kick
-- The same output before and after a change to the boss code means the bosses
-- behave, and look, exactly the same.
--   luau test_bosses.luau -a <scenario> <seed> [server|client] [detail|aim]
-- ("detail" in client mode prints every drawn thing each sample, to find what
-- differs - too big to save. "aim" in client mode prints nothing but a check
-- of where BossClient says the boss is - the AimAt / HeadAt / AimSize your
-- lock-on and its speech bubbles use - against what's drawn, every sample
-- while it's awake, and a summary per move: PASS if it always matched.)
-- scenarios:
--   slime_full    Oozark (floor 1) fought to the death by one player
--   slime_duo     two players; both leave mid-fight (it resets), then return and win
--   slime_die     the player dies mid-fight (it resets), then comes back
--   slime_attacks every attack forced in turn, in phase one and phase two
--   tuber_full    Tuber (floor 2) fought to the death by one player: little
--                 Tuber, the power-up, then the Brute
--   tuber_reset   the player leaves mid-fight (it resets), then returns and wins
--   tuber_attacks every one of his moves forced in turn: little Tuber's in
--                 round 1, then the Brute's once he's powered up
--   knight_full   Knight Burrowmore (floor 3) fought to the death by one player
--   knight_attacks every one of his moves forced in turn, in both phases
--   kaze_full     Kaze (floor 4) fought to the death by one player
--   kaze_attacks  every one of his moves forced in turn, in both rounds
--   car_full      Speedy Revvington (floor 5) fought to the death by one player
--   car_attacks   every one of his moves forced in turn, before and after TURBO
--   grid_full     Gridlock (floor 6) fought to the death by one player
--   grid_attacks  every one of his moves forced in turn (each in its own form),
--                 before and after the gravity flip
--   kongo_full    Kongo (floor 7) fought to the death by one player
--   kongo_attacks every one of his moves forced in turn, in both rounds
--   petal_full    Petalina (floor 8) fought to the death by one player
--   petal_attacks every one of her moves forced in turn, in both rounds
--   scrib_full    Scribble (floor 9) fought to the death by one player (all
--                 three rounds, the DELETE boxes too)
--   scrib_attacks every one of his moves forced in turn, in rounds 1 and 2
--   king_full     King Gavelgrunt (floor 10) fought to the death by one player
--                 (all three rounds and THE FINAL GAVEL)
--   king_attacks  every one of his moves forced in turn, in each round
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local args = { ... }
local SCENARIO = args[1] or "slime_full"
local SEED = tonumber(args[2]) or 1
local MODE = args[3] or "server"
local DETAIL = args[4] == "detail"
local AIM = args[4] == "aim" and MODE == "client"

local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService or game:GetService("CollectionService")
local RunService = M.services.RunService or game:GetService("RunService")
local Players = M.services.Players
local workspace = M.workspace

local FLOOR = string.find(SCENARIO, "^tuber") and 2 or (string.find(SCENARIO, "^knight") and 3 or (string.find(SCENARIO, "^kaze") and 4 or (string.find(SCENARIO, "^car") and 5 or (string.find(SCENARIO, "^grid") and 6 or (string.find(SCENARIO, "^kongo") and 7 or (string.find(SCENARIO, "^petal") and 8 or (string.find(SCENARIO, "^scrib") and 9 or (string.find(SCENARIO, "^king") and 10 or 1))))))))

----------------------------------------------------------------------
-- the log: numbers rounded so tiny float noise can't differ, -0 written as 0
----------------------------------------------------------------------
local function num(x)
	local s = string.format("%.3f", x)
	if s == "-0.000" then
		s = "0.000"
	end
	return s
end
local show
function show(v)
	local t = M.typeof(v)
	if t == "Vector3" then
		return "(" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. ")"
	elseif t == "CFrame" then
		local c = { v:GetComponents() }
		for i, x in ipairs(c) do
			c[i] = num(x)
		end
		return "[" .. table.concat(c, ",") .. "]"
	elseif t == "Color3" then
		return "rgb(" .. math.floor(v.R * 255 + 0.5) .. "," .. math.floor(v.G * 255 + 0.5) .. "," .. math.floor(v.B * 255 + 0.5) .. ")"
	elseif type(v) == "number" then
		return num(v)
	elseif t == "Instance" then
		return tostring(v.Name)
	elseif type(v) == "table" then
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			local x = v[k]
			if x == nil then
				x = v[tonumber(k)]
			end
			parts[#parts + 1] = k .. ":" .. show(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end
local T = 0 -- virtual time
local lines = 0
local function log(...)
	if AIM then
		return -- (aim mode: only its own check is printed)
	end
	local parts = { string.format("%8.3f", T) }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = show((select(i, ...)))
	end
	print(table.concat(parts, " "))
	lines += 1
end

----------------------------------------------------------------------
-- the world: the real arenas, and only this scenario's boss
----------------------------------------------------------------------
mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
mount.require(mount.module("ServerScriptService/DunesBuilder.lua")).Build()
if FLOOR == 3 then
	mount.require(mount.module("ServerScriptService/DigBuilder.lua")).Build()
elseif FLOOR == 4 then
	mount.require(mount.module("ServerScriptService/DojoBuilder.lua")).Build()
elseif FLOOR == 5 then
	mount.require(mount.module("ServerScriptService/SpeedwayBuilder.lua")).Build()
elseif FLOOR == 6 then
	mount.require(mount.module("ServerScriptService/GridBuilder.lua")).Build()
elseif FLOOR == 7 then
	mount.require(mount.module("ServerScriptService/JungleBuilder.lua")).Build()
elseif FLOOR == 8 then
	mount.require(mount.module("ServerScriptService/GreenhouseBuilder.lua")).Build()
elseif FLOOR == 9 then
	mount.require(mount.module("ServerScriptService/CanvasBuilder.lua")).Build()
elseif FLOOR == 10 then
	mount.require(mount.module("ServerScriptService/ThroneBuilder.lua")).Build()
end
M.run(1)
-- (one boss per run: two would take turns in an order that isn't fixed)
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= FLOOR then
		CollectionService:RemoveTag(h, "BossHome")
	end
end

----------------------------------------------------------------------
-- pretend players
----------------------------------------------------------------------
local people = {} -- in order
local inArena = {} -- [player] = true
local rollUntil = {} -- [player] = the end of their roll (untouchable)
local function makePlayer(name, id)
	for _, q in ipairs(people) do
		if q.Name == name then
			return q -- (already made: the screen's own player, in client mode)
		end
	end
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.Parent = Players
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 1e9 -- (they never die unless a scenario says so)
	hum.Health = 1e9
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
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
	p:SetAttribute("SpireFloor", FLOOR)
end
local function leave(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
end

----------------------------------------------------------------------
-- CombatService and PlayerService, pretend: every call is logged
----------------------------------------------------------------------
local shapes = {}
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
function Combat.DamagePlayer(p, amount, from, knockback, quiet)
	log("DAMAGE", p, amount, from, knockback, quiet == true, Combat.IsInvulnerable(p) and "dodged" or "hit")
	if Combat.IsInvulnerable(p) then
		return false
	end
	local hum = humOf(p)
	if hum then
		hum.Health = math.max(1, hum.Health - amount)
	end
	return true
end
function Combat.Shove(p, velocity)
	log("SHOVE", p, velocity)
end
function Combat.SetTargetShape(model, fn)
	shapes[model] = fn
	log("SHAPE", model, fn ~= nil)
end
local firsts = {}
local Profile = {}
function Profile.RecordBossKill(p, floorId)
	local first = not firsts[p]
	firsts[p] = true
	log("KILL", p, floorId, first)
	return first
end
function Profile.AddPower(p, n)
	log("POWER", p, n)
end

local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
-- the victory message each player's screen gets
local remotes = M.services.ReplicatedStorage
M.onFireClient = function(remote, p, ...)
	local list = { ... }
	for i, v in ipairs(list) do
		list[i] = show(v)
	end
	log("CLIENT", remote.Name, p, table.concat(list, " "))
end
BS.Start(Combat, Profile)
local E = assert(BS.Encounter(FLOOR), "no encounter on floor " .. FLOOR)
local model = E.model
local home = E.home
local floorY = E.floorY
local def = E.def
log("BUILT", model, home, floorY, def.Short, #(E.stones or {}), E.sink)

----------------------------------------------------------------------
-- client mode: the real BossClient draws the fight on Alpha's screen
----------------------------------------------------------------------
local created = {} -- every instance made from here on, in order
local staticParts = {} -- the arena's parts as they were: { part, CFrame, Size, Color, Transparency }
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
	kick.Event:Connect(function(strength, ...)
		log("KICK", strength, ...)
	end)
	local cam = Instance.new("Camera")
	cam.Name = "Camera"
	cam.CFrame = CFrame.new(home + Vector3.new(0, 20, 60), home)
	cam.FieldOfView = 70
	cam.Parent = workspace
	workspace.CurrentCamera = cam
	-- the server's messages to this screen (the victory banner)
	local serverLog = M.onFireClient
	M.onFireClient = function(remote, p, ...)
		serverLog(remote, p, ...)
		if p == me and remote.OnClientEvent then
			remote.OnClientEvent:Fire(...)
		end
	end
	-- the arena's own parts near the boss, as they are now (BossClient moves
	-- and recolours some: the pools, the seal, the platforms)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d ~= model.PrimaryPart and not d:IsDescendantOf(model) then
			local pr = rawget(d, "__props")
			local pos = pr.CFrame and pr.CFrame.Position
			if pos and (Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)).Magnitude < 260 then
				table.insert(staticParts, { d, pr.CFrame, pr.Size, pr.Color, pr.Transparency })
			end
		end
	end
	-- everything made from now on is remembered (whichever script makes it)
	local realNew = Instance.new
	Instance.new = function(className, parent)
		local inst = realNew(className, parent)
		created[#created + 1] = inst
		return inst
	end
	math.randomseed(SEED) -- (BossClient's little random wobbles)
	mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)
end

----------------------------------------------------------------------
-- punching it, the way CombatService does (its hitTarget)
----------------------------------------------------------------------
local PUNCH_RANGE = 8
local PUNCH_EVERY = 0.35
local lastPunch = {}
local function aimAt(from)
	local shape = shapes[model]
	if shape then
		local ok, point, radius = pcall(shape, from)
		if ok and M.typeof(point) == "Vector3" then
			return point, radius or model:GetAttribute("HitRadius") or 3
		end
		return nil
	end
	return model:GetPivot().Position, model:GetAttribute("HitRadius") or 3
end
local function punch(p, damageShare)
	if not CollectionService:HasTag(model, "CombatTarget") or (model:GetAttribute("Health") or 0) <= 0 then
		return
	end
	local root = rootOf(p)
	if T - (lastPunch[p] or -99) < PUNCH_EVERY then
		return
	end
	local point, radius = aimAt(root.Position)
	if not point then
		return
	end
	local gap = (Vector3.new(point.X, root.Position.Y, point.Z) - root.Position).Magnitude - radius
	if gap > PUNCH_RANGE or math.abs(point.Y - root.Position.Y) >= 12 then
		return
	end
	lastPunch[p] = T
	local damage = math.max(1, math.floor((model:GetAttribute("MaxHealth") or 1) * damageShare))
	if model:GetAttribute("Invulnerable") then
		damage = 0
	end
	local iframes = tonumber(model:GetAttribute("IFrames"))
	if iframes and damage > 0 then
		-- (the game's clock: this script's own os.clock is the real one)
		if T < (model:GetAttribute("IFramesUntil") or 0) then
			damage = 0
		else
			model:SetAttribute("IFramesUntil", T + iframes)
		end
	end
	local floorHp = model:GetAttribute("MinHealth") or 0
	local before = model:GetAttribute("Health") or 0
	local hp = math.max(math.min(before, floorHp), before - damage)
	damage = math.max(0, before - hp)
	model:SetAttribute("Health", math.max(0, hp))
	local killed = hp <= 0
	log("PUNCH", p, damage, killed, point)
	local onHit = model:FindFirstChild("OnHit")
	if onHit then
		onHit:Fire(p, damage, killed)
	end
end

----------------------------------------------------------------------
-- how the pretend players move: every 1/30 s, deterministic from the time
----------------------------------------------------------------------
local stones = E.stones or {}
local lastPos = {}
local function place(p, pos, dt)
	local root = rootOf(p)
	local old = lastPos[p] or pos
	local vel = dt > 0 and (pos - old) / dt or Vector3.new()
	root.CFrame = CFrame.new(pos)
	root.AssemblyLinearVelocity = vel
	lastPos[p] = pos
end
local function moveToward(from, to, speed, dt)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude <= speed * dt then
		return Vector3.new(to.X, from.Y, to.Z)
	end
	return from + d.Unit * speed * dt
end

-- A fighter: circles the boss at a distance that swells and shrinks, changes
-- direction now and then, rolls every few seconds and jumps every few more.
-- `k` shifts every rhythm so two players (and seeds) differ.
local function fighterStep(p, k, dt, style)
	local root = rootOf(p)
	local pos = lastPos[p] or root.Position
	local base = Vector3.new(pos.X, floorY + 3, pos.Z)
	local center = model:GetPivot().Position
	center = Vector3.new(center.X, floorY, center.Z)
	local phaseT = T + k * 3.7 + SEED * 1.3
	local want
	if not want and style == "tuber" and (model:GetAttribute("Phase") or 1) >= 2
		and math.floor(phaseT / 6) % 3 ~= 2 then
		-- the Brute keeps hopping away: chase him down (and now and then back
		-- off a while, so his long-range moves get their turn)
		local c = model:GetPivot().Position
		want = Vector3.new(c.X, 0, c.Z)
	end
	if not want and style == "keeper" then
		-- (the second player in a duo: keeps just inside the reach of the
		-- shell's burst - so any change to who it throws shows up)
		local reach = (def.BreakReach or 40) - 2
		local ang = phaseT * 0.25 + k
		want = Vector3.new(center.X + math.cos(ang) * reach, 0, center.Z + math.sin(ang) * reach)
	end
	if not want then
		-- (near enough to punch, then out to where it spits and lunges)
		local r = 6 + 22 * (1 + math.sin(phaseT * 0.31))
		local spin = (math.floor(phaseT / 9) % 2 == 0) and 1 or -1
		local ang = phaseT * 0.6 * spin + k * 2
		want = Vector3.new(center.X + math.cos(ang) * r, 0, center.Z + math.sin(ang) * r)
	end
	local rolling = (phaseT % 4.3) < 0.45
	if rolling and not rollUntil[p] or (rollUntil[p] and T > rollUntil[p] + 0.5 and rolling) then
		rollUntil[p] = T + 0.45
	end
	local speed = rolling and 28 or 16
	local nextPos = moveToward(base, want, speed, dt)
	local y = floorY + 3
	local jumpU = (phaseT % 3.1) / 0.6
	if jumpU < 1 then
		y = y + 4 * math.sin(math.pi * jumpU)
	end
	place(p, Vector3.new(nextPos.X, y, nextPos.Z), dt)
end

----------------------------------------------------------------------
-- the trace: every attribute on the boss (sorted), where it is, the arena
----------------------------------------------------------------------
local lastSample = nil
local clientSample -- (below)
local function sample()
	if MODE == "client" then
		clientSample()
		return
	end
	local attrs = model:GetAttributes()
	local names = {}
	for n in pairs(attrs) do
		names[#names + 1] = n
	end
	table.sort(names)
	local parts = {}
	for _, n in ipairs(names) do
		parts[#parts + 1] = n .. "=" .. show(attrs[n])
	end
	local out = "BOSS " .. show(model:GetPivot()) .. " tag=" .. tostring(CollectionService:HasTag(model, "CombatTarget")) .. " " .. table.concat(parts, " ")
	-- the stone platforms (floor 2): which have broken
	local st = {}
	for i, s in ipairs(stones) do
		st[i] = (s.broken and "B" or "-") .. ((s.model and s.model:GetAttribute("Broken")) and "b" or ".")
	end
	if #st > 0 then
		out = out .. " stones=" .. table.concat(st, "")
	end
	-- (only when something changed, so the file stays readable)
	if out ~= lastSample then
		lastSample = out
		log(out)
	end
end

----------------------------------------------------------------------
-- client mode's fingerprint of everything drawn: numbers only (no strings
-- built per sample - it's fast), and a sum over things, so the order they
-- were made in doesn't matter - only what's there
----------------------------------------------------------------------
local MOD = 2147483647
local strCache = {}
local function shash(str)
	local h = strCache[str]
	if h then
		return h
	end
	h = 7
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % MOD
	end
	strCache[str] = h
	return h
end
local function mix(h, x)
	return (h * 1000003 + x) % MOD
end
local function inum(v)
	return math.floor(v * 1000 + 0.5)
end
local PROPS = {
	"CFrame", "Size", "Color", "Transparency", "Material", "Shape", "Anchored", "CanCollide",
	"Visible", "Position", "BackgroundColor3", "BackgroundTransparency", "Text", "TextColor3",
	"TextTransparency", "TextStrokeTransparency", "ImageTransparency", "ImageColor3", "Rotation",
	"Volume", "PlaybackSpeed", "Playing", "Looped", "SoundId", "Brightness", "Range", "Enabled", "Rate",
	"TintColor", "Saturation", "Contrast", "Density", "Offset", "Adornee", "StudsOffset", "Face",
	"Width0", "Width1", "LightEmission", "Speed", "Lifetime",
	"DisplayOrder", "ZIndex", "AnchorPoint", "Font", "TextSize", "TextScaled", "Image", "Thickness",
	"TextXAlignment", "Scale", "MaxDistance", "AlwaysOnTop",
}
local hashValue
function hashValue(h, v)
	local t = M.typeof(v)
	if t == "number" then
		return mix(h, inum(v))
	elseif t == "boolean" then
		return mix(h, v and 1 or 2)
	elseif t == "string" then
		return mix(h, shash(v))
	elseif t == "Vector3" then
		return mix(mix(mix(h, inum(v.X)), inum(v.Y)), inum(v.Z))
	elseif t == "CFrame" then
		local a = { v:GetComponents() }
		for i = 1, 12 do
			h = mix(h, inum(a[i]))
		end
		return h
	elseif t == "Color3" then
		return mix(mix(mix(h, inum(v.R)), inum(v.G)), inum(v.B))
	elseif t == "UDim2" then
		return mix(mix(mix(mix(h, inum(v.X.Scale)), inum(v.X.Offset)), inum(v.Y.Scale)), inum(v.Y.Offset))
	elseif t == "Instance" then
		return mix(h, shash(tostring(v.Name)))
	elseif type(v) == "table" then
		-- (NumberSequence, ColorSequence, NumberRange...: what's inside them, in a
		-- fixed order - never the table's address, which changes every run)
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local x = v[k]
			if x == nil then
				x = v[tonumber(k)]
			end
			h = hashValue(mix(h, shash(k)), x)
		end
		return h
	end
	return mix(h, shash(tostring(v)))
end
local function instHash(inst)
	local pr = rawget(inst, "__props")
	local h = shash(tostring(pr.ClassName or inst.ClassName))
	h = mix(h, shash(tostring(pr.Name)))
	local parent = pr.Parent
	h = mix(h, shash(parent and tostring(rawget(parent, "__props").Name) or "-"))
	for i, name in ipairs(PROPS) do
		local v = pr[name]
		if v ~= nil then
			h = hashValue(mix(h, i), v)
		end
	end
	return h
end
local function inGame(inst)
	if rawget(inst, "__destroyed") then
		return false
	end
	local a = rawget(inst, "__props").Parent
	while a do
		if a == M.game then
			return true
		end
		a = rawget(a, "__props").Parent
	end
	return false
end
local function describe(inst)
	local pr = rawget(inst, "__props")
	local parts = { tostring(pr.ClassName or inst.ClassName), inst:GetFullName() }
	for _, name in ipairs(PROPS) do
		local v = pr[name]
		if v ~= nil then
			parts[#parts + 1] = name .. "=" .. show(v)
		end
	end
	return table.concat(parts, " ")
end
-- aim mode's check (see the top): every sample while it's awake and Alpha
-- is in its arena, the attributes must be there and fresh, the middle inside
-- its body and the head at its top. "Its body" is what BossClient measures:
-- the parts straight in its body's Model, showing, near it and not a shadow
-- on the floor. (Smoothing lets them trail a fast move a little, so they're
-- checked against this sample's body and the one before together.) Per
-- move, the lowest and highest head and middle are noted, to read.
local aimStats, aimOrder, aimFails, aimChecked = {}, {}, {}, 0
local aimPrev = nil
local function aimFail(msg)
	if #aimFails < 12 then
		aimFails[#aimFails + 1] = string.format("%8.3f %s", T, msg)
	end
	aimFails.n = (aimFails.n or 0) + 1
end
local function ownBody()
	local fx = workspace:FindFirstChild("BossFX")
	local body = fx and fx:FindFirstChild(def.Short .. "Body")
	local root = model.PrimaryPart
	if not (body and root) then
		return nil
	end
	local ground = root.Position.Y - root.Size.Y / 2
	local near = math.max(def.Size, 6) + 1.5 -- (BossClient measures from where it's drawn, a touch off the Root)
	local lo, hi = nil, nil
	for _, d in ipairs(body:GetChildren()) do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			local c, s = d.CFrame, d.Size / 2
			local reach = math.abs(c.RightVector.Y) * s.X + math.abs(c.UpVector.Y) * s.Y + math.abs(c.LookVector.Y) * s.Z
			local flatOnFloor = reach < 0.3 and c.Position.Y - reach < ground + 0.6
			local far = Vector3.new(c.Position.X - root.Position.X, 0, c.Position.Z - root.Position.Z).Magnitude
			if not flatOnFloor and far <= near then
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local w = c * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
							lo = lo and lo:Min(w) or w
							hi = hi and hi:Max(w) or w
						end
					end
				end
			end
		end
	end
	if not lo then
		return nil
	end
	return lo, Vector3.new(hi.X, hi.Y, hi.Z), ground
end
local function aimSample()
	local me = people[1]
	local st = model:GetAttribute("State")
	if not (me and inArena[me]) or not (st == "Waking" or st == "Fighting" or st == "Transition") then
		aimPrev = nil
		return
	end
	local at, head = model:GetAttribute("AimAt"), model:GetAttribute("HeadAt")
	local size, stamp = model:GetAttribute("AimSize"), model:GetAttribute("AimTime")
	if M.typeof(at) ~= "Vector3" or M.typeof(head) ~= "Vector3" or type(size) ~= "number" or type(stamp) ~= "number" then
		aimFail("no aim attributes")
		return
	end
	if M.now() - stamp > 0.2 then
		aimFail("stale aim: " .. num(M.now() - stamp) .. "s old")
	end
	local lo, hi, ground = ownBody()
	if not lo then
		aimPrev = nil
		return -- (nothing of it showing: gone, or not drawn yet)
	end
	-- (a boss with an entrance of its own - King Gavelgrunt up on his throne,
	-- then flying down off it - is drawn far from its Root, which waits where
	-- it lands, until IntroDelay: its lock-on follows where it's drawn, and
	-- test_gavelgrunt's entrance checks that)
	if model:GetAttribute("Action") == "Wake" and def.IntroDelay
		and M.now() - (model:GetAttribute("ActionStart") or 0) < def.IntroDelay + 0.3 then
		aimPrev = nil
		return
	end
	aimChecked += 1
	-- (this sample's body and the last one's together)
	local ulo, uhi = lo, hi
	if aimPrev then
		ulo, uhi = lo:Min(aimPrev[1]), hi:Max(aimPrev[2])
	end
	local topLow = aimPrev and math.min(hi.Y, aimPrev[2].Y) or hi.Y
	aimPrev = { lo, hi }
	local action = model:GetAttribute("Action") or "?"
	local SLACK = 2.5
	local bottom = math.max(ulo.Y, ground)
	if at.Y < bottom - SLACK or at.Y > uhi.Y + SLACK or at.X < ulo.X - SLACK or at.X > uhi.X + SLACK or at.Z < ulo.Z - SLACK or at.Z > uhi.Z + SLACK then
		aimFail(action .. ": the middle " .. show(at) .. " is outside its body " .. show(ulo) .. "-" .. show(uhi))
	end
	if head.Y < topLow - SLACK or head.Y > uhi.Y + SLACK then
		aimFail(action .. ": the head is at " .. num(head.Y - floorY) .. " but its top at " .. num(topLow - floorY) .. "-" .. num(uhi.Y - floorY))
	end
	if size < def.Size - 0.01 or size > 80 or size ~= size then
		aimFail(action .. ": a strange size " .. num(size))
	end
	local r = aimStats[action]
	if not r then
		r = { head = { math.huge, -math.huge }, mid = { math.huge, -math.huge }, size = { math.huge, -math.huge }, n = 0 }
		aimStats[action] = r
		aimOrder[#aimOrder + 1] = action
	end
	r.n += 1
	for key, v in pairs({ head = head.Y - floorY, mid = at.Y - floorY, size = size }) do
		r[key][1] = math.min(r[key][1], v)
		r[key][2] = math.max(r[key][2], v)
	end
end

local lastDraw = nil
function clientSample()
	if AIM then
		aimSample()
		return
	end
	local total, count = 0, 0
	local detail = DETAIL and {} or nil
	for _, inst in ipairs(created) do
		if inGame(inst) then
			count += 1
			total = (total + instHash(inst)) % MOD
			if detail then
				detail[#detail + 1] = "  + " .. describe(inst)
			end
		end
	end
	local changed = 0
	for _, s in ipairs(staticParts) do
		local d = s[1]
		local pr = rawget(d, "__props")
		if rawget(d, "__destroyed") then
			changed += 1
			total = (total + 17) % MOD
		elseif pr.CFrame ~= s[2] or pr.Size ~= s[3] or pr.Color ~= s[4] or pr.Transparency ~= s[5] then
			changed += 1
			total = (total + instHash(d)) % MOD
			if detail then
				detail[#detail + 1] = "  * " .. describe(d)
			end
		end
	end
	local line = "DRAW n=" .. count .. " changed=" .. changed .. " h=" .. total
	if line ~= lastDraw then
		lastDraw = line
		log(line)
	end
	if detail then
		table.sort(detail)
		for _, l in ipairs(detail) do
			print(l)
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
			if step % 6 == 0 then
				sample()
			end
		elseif step % 3 == 0 then
			sample()
		end
	end
end
local function runFor(seconds, each)
	tick(math.floor(seconds / DT + 0.5), each)
end
local function stateIs(s)
	return model:GetAttribute("State") == s
end

-- where players stand before walking in: well outside its wake range
local function startSpot(k)
	local a = k * 1.9 + SEED * 0.7
	local r = def.WakeRange + 12
	return Vector3.new(home.X + math.cos(a) * r, floorY + 3, home.Z + math.sin(a) * r)
end

local style = FLOOR == 2 and "tuber" or "slime"
-- each punch takes this much of its health (a long fight: every attack gets
-- its turn; the Brute is only in reach now and then, so more per hit)
local share = FLOOR == 2 and 1 / 100 or 1 / 150
local holdFire = false -- (tuber_attacks: no punching while little Tuber's moves are forced)
local fightStepFor = function(list)
	return function(dt)
		for k, p in ipairs(list) do
			if inArena[p] and humOf(p).Health > 0 then
				fighterStep(p, k, dt, (k == 2 and style == "slime") and "keeper" or style)
				if not holdFire then
					punch(p, share)
				end
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

local summary = {}
local function note(k, v)
	summary[#summary + 1] = k .. "=" .. tostring(v)
end

local function forcedAttacks(tableOf)
	-- wake it, then stop its brain and run each attack by name, in order
	local p = people[1]
	local names = {}
	for n in pairs(tableOf) do
		names[#names + 1] = n
	end
	table.sort(names)
	-- (Tuber: little Tuber's moves in round 1 - nobody punching, so they all
	-- run before the power-up - and the Brute's in round 2)
	holdFire = FLOOR == 2
	fightUntil({ p }, function()
		return stateIs("Fighting")
	end, 60)
	for _, phase in ipairs({ 1, 2 }) do
		if phase == 2 then
			-- the break at half health (the real way: punches down to it)
			holdFire = false
			fightUntil({ p }, function()
				return (model:GetAttribute("Phase") or 1) == 2 and stateIs("Fighting")
			end, 200)
			holdFire = FLOOR == 2 -- (the Brute's moves each get their turn before he falls)
		end
		for _, name in ipairs(names) do
			if FLOOR == 2 and ((def.Attacks[name] or {}).Phase or 1) ~= phase then
				continue
			end
			if FLOOR == 2 then
				-- (never mid power-up: forcing a move would cut it short)
				fightUntil({ p }, function()
					return not stateIs("Transition")
				end, 20)
			end
			E.token = E.token + 1
			local token = E.token
			E.target, E.targetSince = p, T
			E.quarry = p
			if FLOOR == 6 then
				-- (Gridlock: each move in the form it's made for, the right way up -
				-- or hanging from the ceiling, for the one made for that)
				local a = def.Attacks[name] or {}
				E.form = a.Form or "Cube"
				model:SetAttribute("Form", E.form)
				E.gravity = a.Gravity or 1
				model:SetAttribute("Gravity", E.gravity)
			end
			log("FORCE", name, "phase", E.phase)
			M.task.spawn(function()
				local ok, err = pcall(tableOf[name], E, token)
				if not ok then
					log("FORCE-ERROR", name, err)
				end
			end)
			runFor(7, fightStepFor({ p }))
		end
	end
end

if SCENARIO == "slime_full" or SCENARIO == "tuber_full" or SCENARIO == "knight_full" or SCENARIO == "kaze_full" or SCENARIO == "car_full" or SCENARIO == "grid_full" or SCENARIO == "kongo_full" or SCENARIO == "petal_full" or SCENARIO == "scrib_full" or SCENARIO == "king_full" then
	local p = makePlayer("Alpha", 1001)
	place(p, startSpot(1), 0)
	enter(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 600)
	note("dead", stateIs("Dead"))
	runFor(3)
	-- everyone leaves: it comes back, asleep
	leave(p)
	runFor(12)
	note("backAsleep", stateIs("Dormant"))
elseif SCENARIO == "slime_duo" then
	local a = makePlayer("Alpha", 1001)
	local b = makePlayer("Bravo", 1002)
	place(a, startSpot(1), 0)
	place(b, startSpot(2), 0)
	enter(a)
	enter(b)
	fightUntil({ a, b }, function()
		return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.7
	end, 300)
	leave(a)
	leave(b)
	runFor(8)
	note("reset", stateIs("Dormant"))
	place(a, startSpot(1), 0)
	place(b, startSpot(3), 0)
	enter(a)
	enter(b)
	fightUntil({ a, b }, function()
		return stateIs("Dead")
	end, 600)
	note("dead", stateIs("Dead"))
	runFor(4)
elseif SCENARIO == "slime_die" or SCENARIO == "tuber_reset" then
	local p = makePlayer("Alpha", 1001)
	place(p, startSpot(1), 0)
	enter(p)
	fightUntil({ p }, function()
		return (model:GetAttribute("Health") or 1) < (model:GetAttribute("MaxHealth") or 1) * 0.8
	end, 300)
	if SCENARIO == "slime_die" then
		humOf(p).Health = 0 -- (dead: it's no longer fighting anyone)
	else
		leave(p)
	end
	runFor(8)
	note("reset", stateIs("Dormant"))
	humOf(p).Health = 1e9
	place(p, startSpot(2), 0)
	enter(p)
	fightUntil({ p }, function()
		return stateIs("Dead")
	end, 600)
	note("dead", stateIs("Dead"))
	runFor(4)
elseif SCENARIO == "slime_attacks" or SCENARIO == "knight_attacks" or SCENARIO == "kaze_attacks" or SCENARIO == "car_attacks" or SCENARIO == "grid_attacks" or SCENARIO == "tuber_attacks" or SCENARIO == "kongo_attacks" or SCENARIO == "petal_attacks" or SCENARIO == "scrib_attacks" or SCENARIO == "king_attacks" then
	local p = makePlayer("Alpha", 1001)
	place(p, startSpot(1), 0)
	enter(p)
	forcedAttacks((BS._BossAttacks and BS._BossAttacks[def.Short]) or BS._Attacks)
else
	error("unknown scenario " .. SCENARIO)
end

if AIM then
	print(string.format("AIM %s: %d samples checked", def.Short, aimChecked))
	for _, action in ipairs(aimOrder) do
		local r = aimStats[action]
		print(string.format("  %-14s n=%-4d head %6.1f-%-6.1f middle %6.1f-%-6.1f size %5.1f-%-5.1f", action, r.n,
			r.head[1], r.head[2], r.mid[1], r.mid[2], r.size[1], r.size[2]))
	end
	for _, f in ipairs(aimFails) do
		print("!! " .. f)
	end
	if (aimFails.n or 0) > 0 or aimChecked == 0 then
		table.insert(M.errors, (aimFails.n or 0) .. " aim checks failed (of " .. aimChecked .. ")")
	end
end
note("time", num(T))
note("errors", #M.errors)
print("SUMMARY " .. table.concat(summary, " "))
for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
if #M.errors == 0 then
	print("PASS")
end
