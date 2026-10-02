--!nocheck
-- Headless test of THE PHONE LAYOUT (CombatClient's placeTouch): the real
-- code, cut out of CombatClient, on real phone and tablet screen sizes. In
-- a fight on a touch screen: ATTACK is the big button in the corner, and
-- JUMP (Roblox's own button, moved here), ROLL, the ability, the potion and
-- LOCK sit round it - every one on the screen, none on top of another, all
-- big enough for a thumb; and the jump button goes back where Roblox had it
-- after the fight. Also checks a tap on the world can't punch on a phone.
--   luau test_touch_controls.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance, UDim2 = M.Instance, M.UDim2
-- (a Vector2 with X and Y, which the layout reads)
local Vector2 = { new = function(x, y)
	return { X = x or 0, Y = y or 0 }
end }

local fails = 0
local function check(ok, msg)
	if ok then
		print("  ok   " .. msg)
	else
		fails += 1
		print("  FAIL " .. msg)
	end
end

local src = S.files["StarterPlayerScripts/CombatClient.client.lua"]
local a = assert(string.find(src, "-- THE PHONE LAYOUT", 1, true), "the phone layout isn't in CombatClient")
local b = assert(string.find(src, "\n-- red flash round the edges", a, true), "can't find where the phone layout ends")

-- the pieces it works with
local UIS = { TouchEnabled = true, KeyboardEnabled = false }
local playerGui = Instance.new("Folder")
local combatUI = Instance.new("Frame")
local function button(name)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(0.5, 0.5) -- (as CombatClient's roundButton makes them)
	btn.Parent = combatUI
	return btn
end
local attackBtn, rollBtn, flaskBtn, lockBtn = button("AttackButton"), button("RollButton"), button("FlaskButton"), button("LockButton")
local abilityBtn = button("AbilityButton")
-- Roblox's own touch controls: the jump button where it puts it on a big screen
local tg = Instance.new("ScreenGui")
tg.Name = "TouchGui"
tg.Parent = playerGui
local tcf = Instance.new("Frame")
tcf.Name = "TouchControlFrame"
tcf.Parent = tg
local jump = Instance.new("ImageButton")
jump.Name = "JumpButton"
jump.Position = UDim2.new(1, -170, 1, -210)
jump.Size = UDim2.fromOffset(120, 120)
jump.AnchorPoint = Vector2.new(0, 0)
jump.Parent = tcf
local cam = Instance.new("Camera")
local ws = { CurrentCamera = cam }

local env = M.env({ Vector2 = Vector2 })
local chunk = "local UserInputService, workspace, playerGui, combatUI, attackBtn, rollBtn, flaskBtn, lockBtn = ...\nlocal K = {}\n"
	.. string.sub(src, a, b) .. "\nreturn placeTouch, K.TOUCH_LAYOUT"
local placeTouch = M.load(chunk, "CombatClient (the phone layout)", env)(UIS, ws, playerGui, combatUI, attackBtn, rollBtn, flaskBtn, lockBtn)

-- where a button really is on a screen (its box, in pixels)
local function rect(btn, vs)
	local p, s, ap = btn.Position, btn.Size, btn.AnchorPoint or Vector2.new(0, 0)
	local w, h = s.X.Scale * vs.X + s.X.Offset, s.Y.Scale * vs.Y + s.Y.Offset
	local x = p.X.Scale * vs.X + p.X.Offset - ap.X * w
	local y = p.Y.Scale * vs.Y + p.Y.Offset - ap.Y * h
	return { x = x, y = y, w = w, h = h }
end
local function overlap(r, q)
	return r.x < q.x + q.w and q.x < r.x + r.w and r.y < q.y + q.h and q.y < r.y + r.h
end

local SCREENS = {
	{ "small phone", Vector2.new(667, 375) },
	{ "phone", Vector2.new(844, 390) },
	{ "big phone", Vector2.new(932, 430) },
	{ "tablet", Vector2.new(1180, 820) },
}
for _, scr in ipairs(SCREENS) do
	local name, vs = scr[1], scr[2]
	cam.ViewportSize = vs
	placeTouch(true)
	local all = { Attack = attackBtn, Roll = rollBtn, Flask = flaskBtn, Lock = lockBtn, Ability = abilityBtn, Jump = jump }
	local inside, apart, thumb = true, true, true
	local rects = {}
	for key, btn in pairs(all) do
		local r = rect(btn, vs)
		rects[key] = r
		inside = inside and r.x >= 4 and r.y >= 40 and r.x + r.w <= vs.X - 4 and r.y + r.h <= vs.Y - 4
		thumb = thumb and r.w >= 48
	end
	for k1, r in pairs(rects) do
		for k2, q in pairs(rects) do
			if k1 < k2 and overlap(r, q) then
				apart = false
				print("    (" .. k1 .. " and " .. k2 .. " overlap on the " .. name .. ")")
			end
		end
	end
	check(inside, name .. ": every button is on the screen")
	check(apart, name .. ": none sits on another (jump included)")
	check(thumb, name .. ": all big enough for a thumb")
	local at = rects.Attack
	check(at.w >= math.max(rects.Roll.w, rects.Jump.w) and at.x + at.w > vs.X * 0.85 and at.y + at.h > vs.Y * 0.8,
		name .. ": ATTACK is the biggest, in the bottom-right corner")
end
placeTouch(false)
check(jump.Position == UDim2.new(1, -170, 1, -210) and jump.Size == UDim2.fromOffset(120, 120),
	"after the fight the jump button is back where Roblox had it")

-- a tap on the world can't punch on a phone (only the ATTACK button swings)
check(string.find(src, "if input.UserInputType == Enum.UserInputType.Touch and touchMode() then\n\t\treturn\n\tend\n\tholding = true", 1, true) ~= nil,
	"on a phone a tap on the world doesn't throw a punch")
check(string.find(src, "attackBtn.InputBegan:Connect", 1, true) ~= nil and string.find(src, "attackBtn.Visible = on and touch", 1, true) ~= nil,
	"the ATTACK button swings, and shows in every fight on a phone")

if fails == 0 then
	print("PASS test_touch_controls")
else
	print("FAIL test_touch_controls: " .. fails)
end
