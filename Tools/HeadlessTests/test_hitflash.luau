--!nocheck
-- Headless test of THE HIT FLASH (CombatClient's "Enemies flash white the
-- moment a hit lands on them"): the real code, cut out of CombatClient, run
-- on pretend enemies. The server marks every hit that lands on an enemy
-- ("HitFx" = "count:weight:x:z"); every screen flashes that enemy pure white
-- for a blink - but not a boss (BossClient does its own) and not one that's
-- invisible here (drawn by another script).
--
--   luau test_hitflash.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance, CFrame, Vector3 = M.Instance, M.CFrame, M.Vector3
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService

local env = M.env({})
local Config = M.load(S.Config, "Config", env)()

-- the flash's code, exactly as it is in CombatClient
local src = S.files["StarterPlayerScripts/CombatClient.client.lua"]
local a = assert(string.find(src, "-- Enemies flash white the moment a hit lands", 1, true), "the hit flash isn't in CombatClient")
local b = assert(string.find(src, "\n----------------------------------------------------------------------\n-- Damage numbers", a, true), "can't find where the hit flash ends")
local chunk = "local CC, TweenService = ...\n" .. string.sub(src, a, b)

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local function enemy(name, see, attrs)
	local m = Instance.new("Model")
	m.Name = name
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 2)
	body.CFrame = CFrame.new(0, 3, 0)
	body.Transparency = see and 0 or 1
	body.Parent = m
	m.PrimaryPart = body
	for k, v in pairs(attrs or {}) do
		m:SetAttribute(k, v)
	end
	m.Parent = M.workspace
	CollectionService:AddTag(m, "CombatTarget")
	return m
end

local t = 0
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Heartbeat:Fire(1 / 60)
	end
end
local function glow(m)
	local g = m:FindFirstChild("HitFlash")
	return g and g:IsA("Highlight") and g or nil
end
local n = 0
local function land(m, weight)
	n += 1
	m:SetAttribute("HitFx", string.format("%d:%d:%.3f:%.3f", n, weight or 1, 1, 0))
end

-- an enemy that's already there when the screen starts, and one that turns up later
local early = enemy("Straw Dummy", true)
M.load(chunk, "CombatClient (the hit flash)", env)(Config.Combat, M.services.TweenService)
local later = enemy("Iron Knight", true)
local boss = enemy("Oozark", true, { Boss = true })
local ghost = enemy("Oozlet", false) -- (drawn by the intro's own script: invisible here)
step(0.1)

local function all()
	check(glow(early) == nil and glow(later) == nil, "nothing flashes before a hit lands")

	land(early, 1)
	local g = glow(early)
	check(g ~= nil, "a hit landing makes the enemy flash")
	if g then
		check(g.Enabled == true, "...straight away")
		check(g.FillColor == M.Color3.new(1, 1, 1) and g.OutlineTransparency == 1, "...pure white, with no outline")
		check(g.DepthMode == M.Enum.HighlightDepthMode.Occluded, "...and not through walls")
	end
	step((Config.Combat.HitReact.Flash or 0.1) + 0.1)
	check(g and g.Enabled == false, "and it's gone a blink later")

	-- the next hit flashes it again, with the same highlight (they never pile up)
	land(early, 3)
	check(glow(early) == g and g.Enabled == true, "the next hit flashes it again")
	local count = 0
	for _, c in ipairs(early:GetChildren()) do
		if c:IsA("Highlight") then
			count += 1
		end
	end
	check(count == 1, ("...with the same highlight (%d of them)"):format(count))
	-- two hits close together: the first one's timer doesn't cut the second's flash short
	step(0.07)
	land(early, 1)
	step(0.07)
	check(g.Enabled == true, "a quick second hit keeps it flashing its own full blink")
	step(0.2)
	check(g.Enabled == false, "...then it's gone")

	-- one that turned up later flashes too
	land(later, 2)
	check(glow(later) ~= nil and glow(later).Enabled, "an enemy that arrives later flashes too")

	-- a boss does its own (BossClient); one that's invisible here has nothing to flash
	land(boss, 1)
	check(glow(boss) == nil, "a boss isn't flashed here (it blanches in its own way)")
	land(ghost, 1)
	check(glow(ghost) == nil, "an enemy that's invisible on this screen isn't flashed")

	-- something that changes other attributes doesn't flash
	step(0.5)
	later:SetAttribute("Health", 5)
	check(glow(later).Enabled == false, "only a landed hit flashes it")
end

local ok, err = pcall(all)
if not ok then
	fails += 1
	print("FAIL: errored: " .. tostring(err))
end
if #M.errors > 0 then
	fails += 1
	print("FAIL: " .. #M.errors .. " script errors")
	for i = 1, math.min(3, #M.errors) do
		print(M.errors[i])
	end
end
if fails == 0 then
	print("PASS hitflash")
else
	print(fails .. " failures")
end
