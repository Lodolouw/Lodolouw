--!nocheck
-- Headless test of THE HEART, THE POTION and THE BOLT (ReplicatedStorage/Vitals):
-- the three pixel-art pieces at the bottom of the screen. It starts the real
-- module the way Hud does, feeds it a pretend Humanoid and what CombatClient
-- would tell it (Vitals.set / Vitals.fire), steps it frame by frame and
-- checks what's drawn - pixel by pixel.
--
--   luau test_vitals.luau                 every check
--   luau test_vitals.luau -a snaps        prints snapshots for render_vitals.py
--   luau test_vitals.luau -a pour         ...of a drink, moment by moment
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum = M.Instance, M.Enum
local UDim2, Color3 = M.UDim2, M.Color3
local Players = M.services.Players
local RunService = M.services.RunService
local task = M.task

local args = { ... }
local MODE = args[1] or "all"

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Vitals = mount.require(mount.module("ReplicatedStorage/Vitals.lua"))

local player = Instance.new("Player")
player.Name = "Tester"
player.UserId = 1001
player.Parent = Players
Players.LocalPlayer = player
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player

local gui = Instance.new("ScreenGui")
gui.Name = "BossGrowHud"
gui.Parent = playerGui
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

-- Hud's two helpers, as Hud makes them
local function create(className, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end
local function text(props, children)
	local p = { BackgroundTransparency = 1, BorderSizePixel = 0, Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1), TextSize = 20, Text = "" }
	for k, v in pairs(props) do
		p[k] = v
	end
	return create("TextLabel", p, children)
end
local function stroke(thickness)
	return create("UIStroke", { Thickness = thickness })
end

local hum = Instance.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 100
local V = Vitals.start({
	root = root,
	text = text,
	stroke = stroke,
	character = function()
		return hum
	end,
})
local P = V.parts

local t = 0
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.RenderStepped:Fire(1 / 60)
		if each then
			each()
		end
	end
end

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local RGB = Color3.fromRGB
local GLASS = RGB(38, 43, 68)
local OUTLINE = RGB(24, 20, 37)
local HURT = RGB(255, 0, 68)
local VOLT = RGB(254, 231, 97)
local ICE = RGB(44, 232, 245)
local EMPTY_EDGE = RGB(90, 105, 136)
local function same(a, b)
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end
local function near(a, b, tol)
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < (tol or 0.12)
end
-- how many of a picture's squares hold liquid right now
local function full(list)
	local n = 0
	for _, c in ipairs(list) do
		if not same(c.f.BackgroundColor3, GLASS) then
			n += 1
		end
	end
	return n
end
local function share(list)
	return full(list) / #list
end

----------------------------------------------------------------------
-- A tiny layout engine: where every frame really is on a 1920x1000 screen
-- (anchor points, UIScale, rotation about the centre), for the overlap
-- checks and the preview pictures.
----------------------------------------------------------------------
local SW, SH = 1920, 1000
local function uiScaleOf(obj)
	for _, c in ipairs(obj:GetChildren()) do
		if c.ClassName == "UIScale" then
			return c.Scale or 1
		end
	end
	return 1
end
local function vec(v, i, default)
	if v == nil then
		return default
	end
	return v[i] or default
end
-- each object: a function turning its own pixels (x, y) into screen pixels
local function transformOf(obj)
	if obj == root then
		return function(x, y)
			return x, y
		end, SW, SH
	end
	local parentT, pw, ph = transformOf(obj.Parent)
	local size = obj.Size or UDim2.fromOffset(0, 0)
	local pos = obj.Position or UDim2.fromOffset(0, 0)
	local w = pw * size.X.Scale + size.X.Offset
	local h = ph * size.Y.Scale + size.Y.Offset
	local ax, ay = vec(obj.AnchorPoint, 1, 0), vec(obj.AnchorPoint, 2, 0)
	local apx = pw * pos.X.Scale + pos.X.Offset -- the anchor point, in the parent's pixels
	local apy = ph * pos.Y.Scale + pos.Y.Offset
	local s = uiScaleOf(obj)
	local rot = math.rad(obj.Rotation or 0)
	local cx, cy = apx + (w * 0.5 - ax * w) * s, apy + (h * 0.5 - ay * h) * s
	local cs, sn = math.cos(rot), math.sin(rot)
	return function(x, y)
		local px, py = apx + (x - ax * w) * s, apy + (y - ay * h) * s
		local dx, dy = px - cx, py - cy
		return parentT(cx + dx * cs - dy * sn, cy + dx * sn + dy * cs)
	end, w, h
end
local function shownOnScreen(obj)
	while obj and obj ~= root do
		if obj.Visible == false then
			return false
		end
		obj = obj.Parent
	end
	return true
end
-- the box an object covers on screen (ignoring rotation)
local function box(obj)
	local T, w, h = transformOf(obj)
	local x0, y0 = T(0, 0)
	local x1, y1 = T(w, h)
	return { x0 = math.min(x0, x1), y0 = math.min(y0, y1), x1 = math.max(x0, x1), y1 = math.max(y0, y1) }
end
local function overlap(a, b)
	return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
end
-- a word's own box (its text, not the whole label): roughly 0.55 of its size per letter
local function wordsBox(label)
	local b = box(label)
	local plain = string.gsub(label.Text or "", "<[^>]*>", "")
	local wide = #plain * (label.TextSize or 20) * 0.55
	local ax = vec(label.AnchorPoint, 1, 0)
	if label.TextXAlignment == Enum.TextXAlignment.Right then
		b.x0 = b.x1 - wide
	elseif label.TextXAlignment == Enum.TextXAlignment.Left then
		b.x1 = b.x0 + wide
	end
	return b
end

-- every drawn square as a line: corners, colour, see-through (for render_vitals.py)
local function snapshot(caption)
	print("SNAP " .. caption)
	local function walk(obj)
		if obj.Visible == false then
			return
		end
		if obj ~= root and (obj.ClassName == "Frame") and (obj.BackgroundTransparency or 0) < 0.99 then
			local T, w, h = transformOf(obj)
			local ax, ay = T(0, 0)
			local bx, by = T(w, 0)
			local cx, cy = T(w, h)
			local dx, dy = T(0, h)
			local c = obj.BackgroundColor3
			print(string.format("QUAD %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %d %d %d %.2f", ax, ay, bx, by, cx, cy, dx, dy,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), obj.BackgroundTransparency or 0))
		elseif obj.ClassName == "TextLabel" and (obj.Text or "") ~= "" then
			local b = box(obj)
			local c = obj.TextColor3
			local align = obj.TextXAlignment == Enum.TextXAlignment.Right and "R" or (obj.TextXAlignment == Enum.TextXAlignment.Left and "L" or "C")
			local plain = string.gsub(obj.Text, '<font color="#(%x+)">([^<]*)</font>', "{%1}%2")
			print(string.format("TEXT %.1f %.1f %.1f %.1f %d %d %d %d %s %s", b.x0, b.y0, b.x1, b.y1, obj.TextSize or 20,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), align, plain))
		end
		local kids = obj:GetChildren()
		table.sort(kids, function(a, b)
			return (a.ZIndex or 1) < (b.ZIndex or 1)
		end)
		for _, k in ipairs(kids) do
			if k.ClassName == "Frame" or k.ClassName == "TextLabel" then
				walk(k)
			end
		end
	end
	walk(root)
end

-- no broken numbers anywhere on it
local function sane(where)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == "Frame" or d.ClassName == "TextLabel" then
			for _, u in ipairs({ d.Position, d.Size }) do
				if u then
					for _, n in ipairs({ u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }) do
						if n ~= n or n == math.huge or n == -math.huge then
							check(false, where .. ": a broken number in " .. d:GetFullName())
							return
						end
					end
				end
			end
			local r = d.Rotation or 0
			if r ~= r then
				check(false, where .. ": a broken rotation")
				return
			end
		elseif d.ClassName == "UIScale" then
			if d.Scale ~= d.Scale then
				check(false, where .. ": a broken UIScale")
				return
			end
		end
	end
end

local function fightOn(stamina, flasks)
	Vitals.set({ shown = true, stamina = stamina or 1, flasks = flasks or 3 })
end
local function fightOff()
	Vitals.set({ shown = false })
end
local function heal(share_)
	hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * share_)
end

----------------------------------------------------------------------
-- The pictures themselves: closed (no liquid can leak out) and the sums
----------------------------------------------------------------------
local function shapes()
	for name, shape in pairs({ HEART = Vitals.HEART, BOLT = Vitals.BOLT, POTION = Vitals.POTION }) do
		local function at(x, y)
			local row = shape[y]
			if not row then
				return " "
			end
			local ch = string.sub(row, x, x)
			return ch == "" and " " or ch
		end
		for y, row in ipairs(shape) do
			for x = 1, #row do
				if string.sub(row, x, x) == "." then
					for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						local n = at(x + d[1], y + d[2])
						check(n ~= " ", name .. ": inside square " .. x .. "," .. y .. " leaks (nothing next to it)")
					end
				end
			end
		end
		local lay = Vitals.layout(shape)
		check(Vitals.heightFor(lay, 0) == 0, name .. ": empty should have no height")
		check(math.abs(Vitals.heightFor(lay, 1) - lay.layers) < 1e-6, name .. ": full should reach the top")
		local last = -1
		for i = 0, 100 do
			local h = Vitals.heightFor(lay, i / 100)
			check(h >= last - 1e-9, name .. ": the level should only rise as it fills")
			last = h
		end
		-- half full really is about half the squares
		local h = Vitals.heightFor(lay, 0.5)
		local below = 0
		for _, c in ipairs(lay.inside) do
			if c.layer + 0.5 < h then
				below += 1
			end
		end
		check(math.abs(below / #lay.inside - 0.5) < 0.2, name .. ": half full should be about half the squares (" .. below .. "/" .. #lay.inside .. ")")
	end
	check(#Vitals.layout(Vitals.BOLT).inside >= 30, "the bolt should hold enough squares to read")
	print("shapes: heart " .. #Vitals.layout(Vitals.HEART).inside .. ", bolt " .. #Vitals.layout(Vitals.BOLT).inside
		.. ", potion " .. #Vitals.layout(Vitals.POTION).inside .. " squares of liquid")
end

----------------------------------------------------------------------
-- The lobby: just the heart
----------------------------------------------------------------------
local lobbyHp, lobbyPower
local function lobby()
	fightOff()
	hum.Health = 100
	step(2.5) -- (the heart fills slowly on purpose: from empty it takes 2 seconds)
	check(P.bolt.Visible == false and P.potion.Visible == false and P.count.Visible == false, "lobby: no bolt, potion or count")
	check(shownOnScreen(P.vessel), "lobby: the heart is on screen")
	check(share(P.heartCells) > 0.95, "lobby: full health, a full heart (" .. share(P.heartCells) .. ")")
	check(string.find(V.hpText.Text, "100/100", 1, true) ~= nil, "lobby: HP words say 100/100 (" .. V.hpText.Text .. ")")
	lobbyHp, lobbyPower = box(V.hpText), box(V.powerText)
	-- health levels: the heart shows how much is left (by squares)
	for _, f in ipairs({ 0.75, 0.5, 0.25 }) do
		hum.Health = 100 * f
		step(2)
		local got = share(P.heartCells)
		check(math.abs(got - f) < 0.12, ("lobby: %d%% health should fill about %d%% of the heart (%.2f)"):format(f * 100, f * 100, got))
	end
	-- a big hit spills drops
	hum.Health = 100
	step(3)
	local before = V.peek().drops
	hum.Health = 40
	step(1 / 60)
	check(V.peek().drops > before, "lobby: a hit spills drops out of the heart")
	-- dying breaks it; a new you mends it
	hum.Health = 0
	step(1)
	check(V.peek().broken and not P.halves[1].Visible, "lobby: at 0 health the heart shatters")
	hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	step(3)
	check(not V.peek().broken and P.halves[1].Visible, "lobby: respawning mends the heart")
	check(share(P.heartCells) > 0.9, "lobby: and it pours back full (" .. share(P.heartCells) .. ")")
	sane("lobby")
end

----------------------------------------------------------------------
-- A fight: all three, side by side, nothing overlapping
----------------------------------------------------------------------
local function arrive()
	lobby()
	fightOn(1, 3)
	step(0.5)
	check(P.bolt.Visible and P.potion.Visible and P.count.Visible, "fight: the bolt, the potion and the count appear")
	check(math.abs(uiScaleOf(P.bolt) - 1) < 1e-3 and math.abs(uiScaleOf(P.potion) - 1) < 1e-3, "fight: they've popped all the way in")
	check(P.count.Text == "x3", "fight: the count says x3 (" .. P.count.Text .. ")")
	check(share(P.boltCells) > 0.95, "fight: full stamina, a full bolt (" .. share(P.boltCells) .. ")")
	check(share(P.potionCells) > 0.95, "fight: a full potion")
	local hb, bb, pb, cb = box(P.vessel), box(P.bolt), box(P.potion), box(P.count)
	check(bb.x0 >= hb.x1 + 4, "fight: the bolt sits right of the heart")
	check(pb.x1 <= hb.x0 - 4, "fight: the potion sits left of the heart")
	check(math.abs(bb.y1 - hb.y1) < 1 and math.abs(pb.y1 - hb.y1) < 1, "fight: all three stand on the same line")
	check(bb.x0 - hb.x1 < 30 and hb.x0 - pb.x1 < 30, "fight: they sit close to the heart (next to it)")
	local hpB, powB = wordsBox(V.hpText), wordsBox(V.powerText)
	V.powerText.Text = "Power: 1.25M"
	powB = wordsBox(V.powerText)
	for name, b in pairs({ heart = hb, bolt = bb, potion = pb, count = cb }) do
		check(not overlap(hpB, b), "fight: the HP words should keep clear of the " .. name)
		check(not overlap(powB, b), "fight: the Power words should keep clear of the " .. name)
	end
	check(not overlap(wordsBox(P.count), pb), "fight: the count should keep clear of the potion")
	check(box(V.hpText).x1 < lobbyHp.x1 - 40, "fight: the HP words stepped left for the potion")
	check(box(V.powerText).x0 > lobbyPower.x0 + 40, "fight: the Power words stepped right for the bolt")
	-- the level bar underneath (Hud's GoalBar: bottom 16 up to 62) stays clear
	for name, b in pairs({ heart = hb, bolt = bb, potion = pb }) do
		check(b.y1 <= SH - 62, "fight: the " .. name .. " sits above the level bar")
	end
	sane("arrive")
end

----------------------------------------------------------------------
-- The bolt: follows your stamina, sparks, flickers, glows blue
----------------------------------------------------------------------
local function stamina()
	arrive()
	local last = 2
	for _, f in ipairs({ 0.9, 0.75, 0.5, 0.3, 0.15, 0.05, 0 }) do
		Vitals.set({ stamina = f })
		step(0.6)
		local got = share(P.boltCells)
		check(math.abs(got - f) < 0.13, ("bolt: %d%% stamina should fill about %d%% of it (%.2f)"):format(f * 100, f * 100, got))
		check(got <= last + 0.02, "bolt: less stamina never shows more")
		last = got
	end
	-- a roll (24 of 100) shows at once - you're counting on it mid-fight
	Vitals.set({ stamina = 1 })
	step(1)
	Vitals.set({ stamina = 0.76 })
	step(0.15)
	check(math.abs(V.peek().bolt - 0.76) < 0.05, "bolt: a roll's cost shows within a moment (" .. V.peek().bolt .. ")")
	-- refilling
	for i = 1, 40 do
		Vitals.set({ stamina = 0.76 + 0.24 * i / 40 })
		step(1 / 30)
	end
	step(0.3)
	check(share(P.boltCells) > 0.95, "bolt: refilled to full")
	sane("stamina")
end

local function sparks()
	arrive()
	local c0 = V.peek().counts.sparks
	step(3)
	local made = V.peek().counts.sparks - c0
	check(made >= 5, "bolt: full, it crackles with sparks (" .. made .. " in 3s)")
	Vitals.set({ stamina = 0.5 })
	step(1)
	local c1 = V.peek().counts.sparks
	step(3)
	check(V.peek().counts.sparks == c1, "bolt: no sparks while it isn't full")
	-- filling back up: a burst
	Vitals.set({ stamina = 1 })
	step(0.6)
	check(V.peek().counts.sparks >= c1 + 6, "bolt: a burst of sparks as it fills right up")
	sane("sparks")
end

local function empty()
	arrive()
	Vitals.set({ stamina = 0.04 })
	step(0.6)
	Vitals.fire("empty")
	step(1 / 60)
	check(same(P.boltOutline[1].BackgroundColor3, HURT), "bolt: out of stamina, its outline flashes red")
	local on, off = 0, 0
	step(0.4, function()
		local n = full(P.boltCells)
		if n == 0 then
			off += 1
		else
			on += 1
		end
	end)
	check(on > 0 and off > 0, ("bolt: it flickers like a dying light (on %d, off %d frames)"):format(on, off))
	step(0.3)
	check(same(P.boltOutline[1].BackgroundColor3, OUTLINE), "bolt: then its outline goes back to normal")
	check(full(P.boltCells) > 0, "bolt: and the little that's left shows again")
	-- holding the button with none left: it keeps flickering but doesn't pile up
	for _ = 1, 60 do
		Vitals.fire("empty")
		step(1 / 60)
	end
	check(V.peek().flicker > 0.3, "bolt: keeps flickering while you keep trying")
	step(1)
	check(V.peek().flicker == 0, "bolt: and stops when you stop")
	sane("empty")
end

local function iframes()
	arrive()
	Vitals.set({ stamina = 0.76 })
	step(0.5)
	Vitals.fire("iframes", 0.5)
	step(2 / 60)
	-- a square deep in the liquid (not the crackling surface)
	local deepest = nil
	for _, c in ipairs(P.boltCells) do
		if c.layer == 3 then
			deepest = c
		end
	end
	check(deepest and near(deepest.f.BackgroundColor3, ICE, 0.25), "bolt: untouchable, it glows pale blue")
	step(0.6)
	check(deepest and near(deepest.f.BackgroundColor3, VOLT, 0.05), "bolt: and turns yellow again as it wears off")
	sane("iframes")
end

----------------------------------------------------------------------
-- The potion: pours into the heart
----------------------------------------------------------------------
local function drink()
	arrive()
	hum.Health = 40
	step(2)
	local heartBefore = share(P.heartCells)
	local counts = V.peek().counts
	local landed0, pours0, corks0 = counts.landed, counts.pours, counts.corks
	-- what CombatService does: "Drinking", the count goes down, 0.9s later the heal
	Vitals.fire("drink", 0.9)
	local maxTilt, corkGone = 0, false
	step(0.05)
	Vitals.set({ flasks = 2 })
	step(0.85, function()
		maxTilt = math.max(maxTilt, P.potion.Rotation or 0)
		if not P.corkBits[1].Visible then
			corkGone = true
		end
	end)
	check(V.peek().counts.corks == corks0 + 1 and corkGone, "potion: the cork pops off")
	check(maxTilt >= 50, "potion: it tips over towards the heart (" .. maxTilt .. " degrees)")
	check(P.count.Text == "x2", "potion: the count ticks down to x2 (" .. P.count.Text .. ")")
	check(V.peek().counts.landed > landed0 + 5, "potion: its drops land in the heart (" .. V.peek().counts.landed - landed0 .. ")")
	heal(Config.Combat.FlaskHeal)
	local midPour = share(P.potionCells)
	step(3)
	check(V.peek().counts.pours == pours0, "potion: the heart doesn't pour in its own drops too")
	check(share(P.heartCells) > heartBefore + 0.3, ("potion: the heart fills up (%.2f -> %.2f)"):format(heartBefore, share(P.heartCells)))
	check(midPour < 0.9, "potion: it drains as it pours")
	check(math.abs(P.potion.Rotation or 0) < 1e-6, "potion: it stands up again")
	check(share(P.potionCells) > 0.95 and P.corkBits[1].Visible, "potion: the next one's full and corked")
	check(V.peek().drops < 40, "potion: the drops are all gone afterwards")
	-- where the drops were going: into the heart, not the bolt or the floor
	sane("drink")
end

local function last()
	arrive()
	Vitals.set({ flasks = 1 })
	step(0.3)
	hum.Health = 30
	step(2)
	Vitals.fire("drink", 0.9)
	step(0.05)
	Vitals.set({ flasks = 0 })
	step(0.3)
	check(share(P.potionCells) > 0.3, "last flask: the bottle still pours the last one")
	step(0.6)
	heal(Config.Combat.FlaskHeal)
	step(3)
	check(share(P.potionCells) == 0, "last flask: then it's empty")
	check(same(P.potionOutline[4].BackgroundColor3, EMPTY_EDGE), "last flask: grey glass")
	check(P.count.Text == "x0", "last flask: x0")
	check(not P.corkBits[1].Visible, "last flask: no cork")
	-- trying to drink with none left: it shakes and the count flashes red
	Vitals.fire("noFlask")
	local wiggle = 0
	step(0.3, function()
		wiggle = math.max(wiggle, math.abs(P.potion.Rotation or 0))
	end)
	check(wiggle > 5, "no flasks: the potion shakes (" .. wiggle .. ")")
	step(0.4)
	check(math.abs(P.potion.Rotation or 0) < 1e-6, "no flasks: and stops")
	-- a drink the server refused doesn't pour anything (it never sends "Drinking")
	-- a fresh run: the flasks come back
	Vitals.set({ flasks = 3 })
	step(0.6)
	check(share(P.potionCells) > 0.95 and P.corkBits[1].Visible and P.count.Text == "x3", "a fresh run: the potion's full again")
	check(same(P.potionOutline[4].BackgroundColor3, OUTLINE), "a fresh run: no longer grey")
	sane("last")
end

-- the count reaching 0 a moment before "Drinking" arrives: no flash of an
-- empty bottle before it pours
local function race()
	arrive()
	Vitals.set({ flasks = 1 })
	step(0.3)
	Vitals.set({ flasks = 0 })
	local emptied = false
	step(0.1, function()
		if share(P.potionCells) == 0 then
			emptied = true
		end
	end)
	Vitals.fire("drink", 0.9)
	step(0.2, function()
		if share(P.potionCells) == 0 then
			emptied = true
		end
	end)
	check(not emptied, "race: the bottle doesn't flash empty just before it pours")
	step(3)
	check(share(P.potionCells) == 0, "race: and it's empty after")
	sane("race")
end

-- leaving the fight mid-pour: everything tidies away, and comes back right
local function leave()
	arrive()
	hum.Health = 50
	step(1)
	Vitals.fire("drink", 0.9)
	step(0.4)
	fightOff()
	step(0.5)
	check(not P.bolt.Visible and not P.potion.Visible and not P.count.Visible, "leave: the bolt and potion go away")
	check(V.peek().potion.phase == "idle" and not V.peek().potion.pouring, "leave: the pour stops")
	check(box(V.hpText).x1 > lobbyHp.x1 - 1, "leave: the HP words step back")
	fightOn(0.5, 2)
	step(0.5)
	check(math.abs(P.potion.Rotation or 0) < 1e-6 and share(P.potionCells) > 0.95, "leave: back in, a full upright potion")
	check(math.abs(share(P.boltCells) - 0.5) < 0.13, "leave: back in, the bolt shows the stamina you have")
	-- intro: CombatClient keeps them hidden (shown = false)
	sane("leave")
end

-- random everything for two minutes: no errors, no broken numbers, nothing piling up
local function fuzz(seed)
	arrive()
	math.randomseed(seed)
	local kinds = { "drink", "iframes", "empty", "noFlask", "bogus" }
	for i = 1, 60 * 120 do
		local r = math.random()
		if r < 0.01 then
			Vitals.set({ stamina = math.random() })
		elseif r < 0.012 then
			Vitals.set({ shown = math.random() < 0.8 })
		elseif r < 0.014 then
			Vitals.set({ flasks = math.random(0, 3) })
		elseif r < 0.02 then
			Vitals.fire(kinds[math.random(1, #kinds)], math.random() < 0.5 and math.random() * 2 or nil)
		elseif r < 0.024 then
			hum.Health = math.random(0, 100)
		elseif r < 0.0245 then
			Vitals.set({ stamina = 0 / 0 }) -- a broken number must not break it
		end
		step(1 / 60)
		if i % 600 == 0 then
			sane("fuzz " .. seed)
			check(V.peek().drops < 250, "fuzz: drops shouldn't pile up (" .. V.peek().drops .. ")")
		end
	end
	check(V.peek().bolt == V.peek().bolt, "fuzz: the bolt's level is a real number")
end

----------------------------------------------------------------------
-- Snapshots for the preview picture (render_vitals.py)
----------------------------------------------------------------------
local function snaps()
	math.randomseed(7)
	fightOff()
	hum.Health = 100
	step(2)
	V.powerText.Text = "Power: 12.4K"
	snapshot("IN THE LOBBY|just the heart")
	fightOn(1, 3)
	step(1.2)
	snapshot("IN A FIGHT|potion, heart, bolt")
	hum.Health = 55
	Vitals.set({ stamina = 0.45 })
	step(1.5)
	snapshot("MID-FIGHT|55% health, some stamina used")
	Vitals.set({ stamina = 0.66 })
	step(0.6)
	Vitals.fire("iframes", 0.5)
	step(3 / 60)
	snapshot("ROLLING|untouchable: the bolt glows blue")
	step(1)
	Vitals.set({ stamina = 0.03 })
	step(0.7)
	Vitals.fire("empty")
	step(2 / 60)
	snapshot("OUT OF STAMINA|it flickers, outline red")
	Vitals.set({ stamina = 0.5 })
	hum.Health = 35
	step(2)
	Vitals.fire("drink", 0.9)
	step(0.05)
	Vitals.set({ flasks = 2 })
	step(0.45)
	snapshot("DRINKING|the potion pours into the heart")
	step(0.4)
	heal(Config.Combat.FlaskHeal)
	step(0.5)
	snapshot("HEALING|the heart fills as the drops land")
	step(2.5)
	Vitals.set({ flasks = 0 })
	step(0.8)
	Vitals.set({ stamina = 1 })
	step(1)
	snapshot("NO FLASKS LEFT|empty grey glass, x0")
	hum.Health = 12
	step(1.4)
	snapshot("NEARLY DEAD|the heart beats red")
end

-- a drink, moment by moment (render_vitals.py ... --cols 3)
local function pourSnaps()
	math.randomseed(3)
	V.powerText.Text = "Power: 12.4K"
	fightOn(0.8, 3)
	hum.Health = 30
	step(2.5)
	snapshot("1. PRESS R|30% health, 3 flasks")
	Vitals.fire("drink", 0.9)
	step(0.05)
	Vitals.set({ flasks = 2 })
	step(0.03)
	snapshot("2. POP!|the cork flies off")
	step(0.2)
	snapshot("3. TIP|it tips towards the heart")
	step(0.45)
	snapshot("4. POUR|an arc of red drops")
	step(0.25)
	heal(Config.Combat.FlaskHeal) -- (0.9s in: CombatService heals you)
	step(0.3)
	snapshot("5. FILL|the heart rises as they land")
	step(0.42)
	snapshot("6. EMPTY|the last drops")
	step(0.7)
	snapshot("7. BACK UP|x2 left, the next one full")
end

if MODE == "snaps" then
	snaps()
	return
elseif MODE == "pour" then
	pourSnaps()
	return
end

local runs = {
	shapes = shapes, lobby = lobby, arrive = arrive, stamina = stamina, sparks = sparks, empty = empty,
	iframes = iframes, drink = drink, last = last, race = race, leave = leave,
	fuzz = function()
		fuzz(1)
		fuzz(2)
	end,
}
local order = { "shapes", "lobby", "arrive", "stamina", "sparks", "empty", "iframes", "drink", "last", "race", "leave", "fuzz" }
for _, name in ipairs(order) do
	if MODE == "all" or MODE == name then
		local ok, err = pcall(runs[name])
		if not ok then
			fails += 1
			print("FAIL: " .. name .. " errored: " .. tostring(err))
		end
		-- (a fresh start for the next one: out of the fight, full health)
		fightOff()
		Vitals.set({ stamina = 1, flasks = 3 })
		hum.Health = hum.MaxHealth
		step(1.5)
	end
end
if #M.errors > 0 then
	fails += 1
	print("FAIL: " .. #M.errors .. " script errors")
	for i = 1, math.min(3, #M.errors) do
		print(M.errors[i])
	end
end
if fails == 0 then
	print("PASS vitals " .. MODE)
else
	print(fails .. " failures")
end
