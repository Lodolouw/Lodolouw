--!nocheck
-- The "how to add a boss" templates really work: ServerScriptService/Bosses/
-- _Template.lua and ReplicatedStorage/BossBodies/_Template.lua are plugged in
-- as a pretend extra boss (a Config entry with Short = "_Template" and its one
-- attack, STOMP, and a BossHome part on a made-up floor 99 - floors 1-3 are
-- the real bosses'), and a pretend player fights it to the death with the
-- real BossService and BossClient running.
--   luau test_boss_template.luau
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService or game:GetService("CollectionService")
local RunService = M.services.RunService or game:GetService("RunService")
local Players = M.services.Players
local workspace = M.workspace

-- the pretend boss: Oozark's numbers, the template's name and attack
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local def = table.clone(Config.Bosses[1])
def.Name = "The Template Golem"
def.Short = "_Template"
def.Body = nil
def.Attacks = {
	Stomp = { Tell = 0.7, Damage = 15, Radius = 14, Knockback = 40, Recovery = 0.8, Phase = 1, Range = { 0, 200 }, Weight = 1 },
}
def.HealthPunches = 30
local FLOOR = 99
Config.Bosses[FLOOR] = def

-- its arena: a floor and the spot where it lives
local HOME = Vector3.new(5000, 0, 5000)
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Size = Vector3.new(300, 2, 300)
floor.CFrame = CFrame.new(HOME - Vector3.new(0, 1, 0))
floor.Parent = workspace
local homePart = Instance.new("Part")
homePart.Name = "BossHome"
homePart.CFrame = CFrame.new(HOME)
homePart:SetAttribute("Floor", FLOOR)
homePart:SetAttribute("Facing", Vector3.new(0, 0, 1))
homePart.Parent = workspace
CollectionService:AddTag(homePart, "BossHome")

-- the player (and their screen)
local me = Instance.new("Player")
me.Name = "Alpha"
me.UserId = 1001
me.Parent = Players
M.players = { me }
Players.LocalPlayer = me
local char = Instance.new("Model")
char.Name = "Alpha"
local hum = Instance.new("Humanoid")
hum.MaxHealth, hum.Health = 1e9, 1e9
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(HOME + Vector3.new(0, 3, 80))
root.Parent = char
char.PrimaryPart = root
char.Parent = workspace
me.Character = char
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local kickEvent = Instance.new("BindableEvent")
kickEvent.Name = "CombatCameraKick"
kickEvent.Parent = scripts
local cam = Instance.new("Camera")
cam.CFrame = CFrame.new(HOME + Vector3.new(0, 20, 60), HOME)
cam.Parent = workspace
workspace.CurrentCamera = cam

-- CombatService and PlayerService, pretend
local T = 0
local hits, rewards = 0, 0
local Combat = {}
function Combat.PlayersInArena(floorId)
	return me:GetAttribute("SpireFloor") == floorId and { me } or {}
end
function Combat.IsFighting(p)
	return p:GetAttribute("SpireFloor") ~= nil and hum.Health > 0
end
function Combat.IsInvulnerable()
	return false
end
function Combat.DamagePlayer(p, amount)
	hits += 1
	return true
end
function Combat.Shove() end
function Combat.SetTargetShape() end
local Profile = {}
function Profile.RecordBossKill()
	return true
end
function Profile.AddPower()
	rewards += 1
end
function Profile.AddChest() end

local warned = {}
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = assert(BS.Encounter(FLOOR), "the template boss should be built")
assert(E.boss and E.boss.Attacks and E.boss.Attacks.Stomp, "BossService should load Bosses/_Template.lua for it")
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

-- fight: walk in, stay close, punch it (like CombatService) until it falls
local seen = {}
local sawWarning, sawBody = false, false
me:SetAttribute("SpireFloor", FLOOR)
local lastPunch = 0
local model = E.model
local DT = 1 / 30
while T < 240 and model:GetAttribute("State") ~= "Dead" do
	T += DT
	M.run(T)
	-- close in to 12 studs, circling slowly
	local a = T * 0.4
	root.CFrame = CFrame.new(HOME + Vector3.new(math.cos(a) * 12, 3, math.sin(a) * 12))
	if CollectionService:HasTag(model, "CombatTarget") and T - lastPunch > 0.35 and not model:GetAttribute("Invulnerable") then
		lastPunch = T
		local before = model:GetAttribute("Health") or 0
		local hp = math.max(math.min(before, model:GetAttribute("MinHealth") or 0), before - (model:GetAttribute("MaxHealth") or 1) / 40)
		model:SetAttribute("Health", math.max(0, hp))
		model:FindFirstChild("OnHit"):Fire(me, before - hp, hp <= 0)
	end
	RunService.Heartbeat:Fire(DT)
	RunService.RenderStepped:Fire(DT)
	seen[tostring(model:GetAttribute("Action"))] = true
	local fx = workspace:FindFirstChild("BossFX")
	if fx then
		sawWarning = sawWarning or fx:FindFirstChild("StompWarning") ~= nil
		local body = fx:FindFirstChild("_TemplateBody")
		sawBody = sawBody or (body ~= nil and body:FindFirstChild("Torso") ~= nil and body:FindFirstChild("Head") ~= nil)
	end
end
local actions = {}
for k in pairs(seen) do
	table.insert(actions, k)
end
table.sort(actions)
print(string.format("time %.1f  state %s  actions: %s  hits on the player %d  rewards %d", T, tostring(model:GetAttribute("State")), table.concat(actions, " "), hits, rewards))
assert(model:GetAttribute("State") == "Dead", "the template boss should be beaten")
assert(seen.Wake and seen.Stomp and seen.Break and seen.Death, "it should wake, stomp, break its shell and die")
assert(hits > 0, "its stomp should land on someone standing in it")
assert(rewards == 1, "beating it pays out")
assert(sawBody, "BossClient should draw its body from BossBodies/_Template.lua")
assert(sawWarning, "its stomp's warning should be drawn")
for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
assert(#M.errors == 0, "errors")
assert((M.warnings or 0) == 0, "no warnings (a missing or broken boss file warns)")
print("PASS")
