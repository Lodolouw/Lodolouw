--!nocheck
-- Headless test of THE PHONE LAYOUT (CombatClient's placeTouch): the real
-- code, cut out of CombatClient, on real phone and tablet screen sizes. In
-- a fight on a touch screen: ATTACK is the big button in the corner, and
-- JUMP (Roblox's own button, moved here), ROLL, the ability, the potion and
-- LOCK sit round it - every one on the screen, none on top of another, all
-- big enough for a thumb, measured the way the screen really draws them
-- (our buttons sit in the HUD's root, shrunk to half size on a phone;
-- Roblox's jump button doesn't); and the jump button goes back where Roblox
-- had it after the fight. Also checks a tap on the world can't punch on a
-- phone.
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
-- the HUD root's scale, as CombatClient's updateScale sets it
local uiScale = Instance.new("UIScale")
local function rootScale(vs)
	return math.clamp(vs.Y / 1000, 0.5, 1.1)
end

local env = M.env({ Vector2 = Vector2 })
local Config = M.load(S.Config, "Config", M.env({}))()
local chunk = "local UserInputService, workspace, playerGui, combatUI, attackBtn, rollBtn, flaskBtn, lockBtn, uiScale, Config = ...\nlocal K = {}\n"
	.. string.sub(src, a, b) .. "\nreturn placeTouch, K.TOUCH_LAYOUT"
local placeTouch = M.load(chunk, "CombatClient (the phone layout)", env)(UIS, ws, playerGui, combatUI, attackBtn, rollBtn, flaskBtn, lockBtn, uiScale, Config)

-- where a button really is on a screen (its box, in pixels). Ours are laid
-- out in the root, which is 1/s of the screen and drawn s times as big.
local function rect(btn, vs, s)
	s = s or 1
	local W, H = vs.X / s, vs.Y / s
	local p, z, ap = btn.Position, btn.Size, btn.AnchorPoint or Vector2.new(0, 0)
	local w, h = z.X.Scale * W + z.X.Offset, z.Y.Scale * H + z.Y.Offset
	local x = p.X.Scale * W + p.X.Offset - ap.X * w
	local y = p.Y.Scale * H + p.Y.Offset - ap.Y * h
	return { x = x * s, y = y * s, w = w * s, h = h * s }
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
	local s = rootScale(vs)
	uiScale.Scale = s
	placeTouch(true)
	local all = { Attack = attackBtn, Roll = rollBtn, Flask = flaskBtn, Lock = lockBtn, Ability = abilityBtn, Jump = jump }
	local inside, apart, thumb = true, true, true
	local rects = {}
	for key, btn in pairs(all) do
		local r = rect(btn, vs, btn == jump and 1 or s)
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
	-- one arc: Roblox's jump button the same size as ROLL and SKILL, and ATTACK
	-- as big on the screen as the layout says (not shrunk with the HUD)
	check(math.abs(rects.Jump.w - rects.Roll.w) < 1 and math.abs(rects.Jump.w - rects.Ability.w) < 1,
		string.format("%s: JUMP, ROLL and SKILL are one size (%.0f, %.0f, %.0f)", name, rects.Jump.w, rects.Roll.w, rects.Ability.w))
	check(at.w >= 96, string.format("%s: ATTACK is a good thumb's size on the screen (%.0f px)", name, at.w))
	local jr, ar = rects.Jump, rects.Attack
	local gap = (ar.x + ar.w / 2) - (jr.x + jr.w / 2)
	check(math.abs(jr.y + jr.h / 2 - (ar.y + ar.h / 2)) < 1 and gap > ar.w / 2 and gap < ar.w * 1.4,
		string.format("%s: JUMP sits right beside ATTACK (%.0f px left of it)", name, gap))
	local text = attackBtn.TextSize * s
	check(text >= 36, string.format("%s: ATTACK's picture is big on the screen too (%.0f px)", name, text))
end
placeTouch(false)
check(jump.Position == UDim2.new(1, -170, 1, -210) and jump.Size == UDim2.fromOffset(120, 120),
	"after the fight the jump button is back where Roblox had it")

-- a tap on the world can't punch on a phone (only the ATTACK button swings)
check(string.find(src, "if input.UserInputType == Enum.UserInputType.Touch and touchMode() then\n\t\treturn\n\tend\n\tholding = true", 1, true) ~= nil,
	"on a phone a tap on the world doesn't throw a punch")
check(string.find(src, "attackBtn.InputBegan:Connect", 1, true) ~= nil and string.find(src, "attackBtn.Visible = on and touch", 1, true) ~= nil,
	"the ATTACK button swings, and shows in every fight on a phone")
-- the middle mouse button locks on even when Roblox marks the click as handled
check(string.find(src, "if not processed or input.KeyCode == Enum.KeyCode.ButtonR3 or input.UserInputType == Enum.UserInputType.MouseButton3 then\n\t\t\ttoggleLock()", 1, true) ~= nil,
	"a middle click always locks on")
check(string.find(src, "Middle click: lock on", 1, true) ~= nil and string.find(src, "Tab: lock on", 1, true) == nil,
	"the controls hint says Middle click: lock on")
-- a punch slows you down rather than stopping you dead (Config.Combat.PunchMoveSpeed)
check(string.find(src, "hum.WalkSpeed = (savedWalkSpeed or 0) * (CC.PunchMoveSpeed or 0)", 1, true) ~= nil,
	"a punch only slows you, you can still drift out of the way")

if fails == 0 then
	print("PASS test_touch_controls")
else
	print("FAIL test_touch_controls: " .. fails)
end
