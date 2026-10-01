--!nocheck
-- Headless test of THE BOSSES TALKING (BossIntro's speech bubbles): the real
-- script, a pretend boss whose head BossClient has measured (HeadAt), and a
-- camera. The bubble must hang just over its head with its tail pointing
-- down at it; with no room up there (its head up by the boss bar) it sits
-- beside the head, pointing sideways; with the head off the top of your
-- screen, off a side or behind you, it waits at the edge nearest it with its
-- tail tucked away - never over the boss bar; last words stay where they
-- were said; the words lose the old box's "* "; the tag carries the boss's
-- name in its colour.
--
--   luau test_talk.luau
local M = require("./rbxmock")
local S = require("./sources")
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local Players = M.services.Players
local RunService = M.services.RunService
local CollectionService = M.services.CollectionService
local workspace = M.workspace

local configModule = Instance.new("ModuleScript")
configModule.Name = "Config"
configModule.Parent = M.services.ReplicatedStorage
-- (which arena copy a boss is in: BossIntro asks)
local arenasModule = Instance.new("ModuleScript")
arenasModule.Name = "Arenas"
arenasModule.Parent = M.services.ReplicatedStorage
local Config, Arenas
local env = M.env({
	require = function(mod)
		if mod == configModule then
			return Config
		elseif mod == arenasModule then
			return Arenas
		end
		error("require of unknown module " .. tostring(mod))
	end,
})
Config = M.load(S.Config, "Config", env)()
Arenas = M.load(S.files["ReplicatedStorage/Arenas.lua"], "Arenas", env)()
local def = Config.Bosses[9]

-- the screen's player, and a camera looking at the boss from 40 studs away
local me = Instance.new("Player")
me.Name = "Alpha"
me.UserId = 1001
me.DisplayName = "Alpha"
me.Parent = Players
Players.LocalPlayer = me
M.players = { me }
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local blip = Instance.new("Sound")
blip.Name = "UI Blip"
blip.Parent = M.services.SoundService
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.FieldOfView = 70
cam.CFrame = CFrame.lookAt(Vector3.new(0, 20, 50), Vector3.new(0, 12, 0))
cam.Parent = workspace
workspace.CurrentCamera = cam

-- the boss the way BossService makes one (a small Root on the floor)
local boss = Instance.new("Model")
boss.Name = "Boss_Scribble"
local root = Instance.new("Part")
root.Name = "Root"
root.Size = Vector3.new(5, 4.25, 5)
root.CFrame = CFrame.new(0, 2.125, 0)
root.Transparency = 1
root.Parent = boss
boss.PrimaryPart = root
boss:SetAttribute("Floor", 9)
boss:SetAttribute("State", "Dormant")
boss.Parent = workspace
CollectionService:AddTag(boss, "Boss")

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

math.randomseed(2)
M.task.spawn(M.load(S.BossIntro, "BossIntro", env))

local t = 0
local head = Vector3.new(0, 16.8, 0) -- (where BossClient says his head is)
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		boss:SetAttribute("HeadAt", head)
		boss:SetAttribute("AimTime", t)
		RunService.Heartbeat:Fire(1 / 60)
		RunService.RenderStepped:Fire(1 / 60)
	end
end
step(0.5)

local TAIL, EDGE, TOP_SAFE, SIDE = 12, 3, 150, 12
local function parts()
	local talk = gui:FindFirstChild("BossTalk")
	local bubble = talk and talk:FindFirstChild("Bubble")
	local box = bubble and bubble:FindFirstChild("Box")
	return talk, bubble, box, box and box:FindFirstChild("Words"), box and box:FindFirstChild("Tag")
end
local function tip()
	local _, bubble = parts()
	return bubble.Position.X.Offset, bubble.Position.Y.Offset
end
-- (the pretend Roblox's Vector2 is just its two numbers)
local function anchor(box)
	local a = box.AnchorPoint
	return a.X or a[1], a.Y or a[2]
end
local function screenOf(p)
	local v = cam:WorldToViewportPoint(p)
	return v.X, v.Y
end
-- which way it's pointing ("down", "left", "right" - or nil: tucked away)
local function pointing()
	local _, bubble = parts()
	local which = nil
	for _, name in ipairs({ "Down", "Left", "Right" }) do
		local t = bubble:FindFirstChild("Tail" .. name)
		if t and t.Visible then
			check(which == nil, "only one tail should show")
			which = string.lower(name)
		end
	end
	return which
end
-- the box's top edge on the screen (its size: the same guess BossIntro makes
-- before Roblox lays it out, which is all the pretend Roblox can do)
local function boxTop()
	local _, bubble, box, words = parts()
	local n = utf8.len(words.Text)
	local h = math.ceil(n / 32) * 20 + 23
	local y = bubble.Position.Y.Offset + box.Position.Y.Offset
	local _, ay = anchor(box)
	return y - ay * h - EDGE
end
-- a head height that lands on screen row `row` (straight ahead)
local function headFor(row)
	local lo, hi = -50, 200
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		local _, y = screenOf(Vector3.new(0, mid + 1.2, 0))
		if y > row then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) / 2
end

-- 1) he wakes: after the VS splash, his wake line, in a bubble over his head
me:SetAttribute("SpireFloor", 9)
boss:SetAttribute("State", "Waking")
step(2.8)
local talk, bubble, box, words, tag = parts()
check(talk and talk.Enabled, "he should be talking (his wake line)")
if not (talk and bubble and box and words and tag) then
	print("FAIL: the bubble's parts are missing")
	print(fails + 1 .. " FAILED")
	return
end
check(talk.IgnoreGuiInset == true and talk:GetAttribute("RetroSkip") == true, "the bubble's screen should line up with the camera's, and keep its own look")
local ex, ey = screenOf(head + Vector3.new(0, 1.2, 0))
local x, y = tip()
check(math.abs(x - ex) < 0.5 and math.abs(y - ey) < 0.5, string.format("the tail's tip should be just over his head: at %.1f,%.1f, want %.1f,%.1f", x, y, ex, ey))
check(pointing() == "down", "the tail should point down at his head: " .. tostring(pointing()))
check(box.Position.X.Offset == 0 and select(2, anchor(box)) == 1, "the box should sit straight over the tail")
check(boxTop() >= TOP_SAFE - 0.01, "the box should stay under the boss bar: its top at " .. boxTop())
check(string.sub(words.Text, 1, 1) ~= "*" and #words.Text > 5, "the words shouldn't start with the old box's star: " .. words.Text)
local tagText = tag:FindFirstChildOfClass("TextLabel")
check(tagText and tagText.Text == "SCRIBBLE", "the tag should carry his name: " .. tostring(tagText and tagText.Text))
check(tag.BackgroundColor3 == def.Color, "the tag should be his colour")
local typingSize = words.Size
check(words.AutomaticSize == nil or words.AutomaticSize == Enum.AutomaticSize.None, "the words shouldn't size themselves to the letters typed so far")
check(typingSize.X.Offset > 40 and typingSize.Y.Offset >= 20, "the words should be sized to the whole line from the start: " .. tostring(typingSize.X.Offset) .. "x" .. tostring(typingSize.Y.Offset))
step(2.5)
check(words.MaxVisibleGraphemes == -1, "the words should be all typed out")
check(words.Size == typingSize, "the bubble shouldn't change size while it types")

-- 2) he walks: it follows his head
head = Vector3.new(8, 16.8, -4)
step(0.1)
ex, ey = screenOf(head + Vector3.new(0, 1.2, 0))
x, y = tip()
check(math.abs(x - ex) < 0.5 and math.abs(y - ey) < 0.5 and pointing() == "down", "the bubble should follow his head as he moves")

-- 3) his head up by the boss bar (a tall boss, close): beside his head,
-- pointing sideways at it, still under the bar
head = Vector3.new(0, headFor(200), 0)
step(0.1)
ex, ey = screenOf(head + Vector3.new(0, 1.2, 0))
x, y = tip()
check(math.abs(x - ex) < 0.5 and math.abs(y - ey) < 0.5, "beside his head, the tip should still be at his head")
check(pointing() == "left" and anchor(box) == 0 and box.Position.X.Offset == TAIL, "the box should sit to the right of his head, pointing left at it: " .. tostring(pointing()))
check(boxTop() >= TOP_SAFE - 0.01, "...and stay under the boss bar: its top at " .. boxTop())
-- (and near the right edge of your screen: to the left of his head instead)
head = Vector3.new(34, headFor(200), 0)
step(0.1)
local hx = screenOf(head + Vector3.new(0, 1.2, 0))
if hx > 640 then
	check(pointing() == "right" and anchor(box) == 1, "near the right edge, the box should sit to the left of his head: " .. tostring(pointing()))
end

-- 4) his head right up in the boss bar: the box under the bar, beside him
head = Vector3.new(0, headFor(60), 0)
step(0.1)
check(boxTop() >= TOP_SAFE - 0.01 and pointing() == nil, "with his head in the boss bar, the box should wait under it, tail tucked away: top " .. boxTop())

-- 5) his head off the top of your screen (you're right under him)
head = Vector3.new(0, 90, 20)
step(0.1)
check(boxTop() >= TOP_SAFE - 0.01 and pointing() == nil, "with his head off the top, the box should wait under the bar, tail tucked away")

-- 6) far off to the right: the box stays on your screen
head = Vector3.new(400, 12, -10)
step(0.1)
x = tip()
check(x <= 1280 - SIDE - 100 and pointing() == nil, "off to the right, the box should stay on screen: its middle at " .. x)

-- 7) behind you: it waits at the side he's on
head = Vector3.new(-30, 16.8, 90) -- (behind the camera, on its left)
step(0.1)
x = tip()
check(x < 640 and pointing() == nil, "with him behind you on the left, the bubble should wait at the left: its middle at " .. x)

-- 8) a new line takes over from the last one
head = Vector3.new(0, 16.8, 0)
boss:SetAttribute("State", "Fighting")
boss:SetAttribute("Phase", 2)
step(0.2)
check(talk.Enabled and words.MaxVisibleGraphemes >= 0 and words.MaxVisibleGraphemes < 12, "his round-2 line should start typing")
step(6)
check(not talk.Enabled, "the bubble should go once he's said it")

-- 9) his last words stay where he said them (he's crumpling, flying off...)
local said = head + Vector3.new(0, 1.2, 0)
boss:SetAttribute("State", "Dead")
step(0.1)
head = Vector3.new(-60, 3, -60)
step(0.5)
ex, ey = screenOf(said)
x, y = tip()
check(talk.Enabled and math.abs(x - ex) < 0.5 and math.abs(y - ey) < 0.5, "his last words should stay where he said them")

-- 10) nothing measured (BossClient isn't drawing him): over his Root instead
step(6)
boss:SetAttribute("State", "Dormant")
boss:SetAttribute("State", "Waking")
step(2.7)
t += 1
M.run(t)
RunService.RenderStepped:Fire(1 / 60) -- (a frame with his measurement gone stale)
ex, ey = screenOf(root.Position + Vector3.new(0, 4.25 / 2 + 1.2, 0))
x, y = tip()
check(math.abs(x - ex) < 0.5 and math.abs(y - ey) < 0.5, "unmeasured, it should hang over his Root")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
	fails += 1
end
if fails == 0 then
	print("PASS")
else
	print(fails .. " FAILED")
end
