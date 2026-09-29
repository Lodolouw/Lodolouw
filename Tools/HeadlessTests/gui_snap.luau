--!nocheck
-- Prints what a ScreenGui draws right now, for render_gui.py to paint: every
-- visible box, border, word and 3D window, where it lands on a SW x SH
-- screen - with Size / Position / AnchorPoint, UIScale, Rotation, UICorner,
-- UIStroke, UIGradient, UIPadding, UIListLayout and UIGridLayout worked out
-- the way Roblox does (near enough for a picture). One JSON object a line
-- after a "SNAP caption" line.
--   local snap = require("./gui_snap")
--   snap(screenGui, "THE MENU|what it shows", 1280, 720)
-- A ViewportFrame's picture can't be drawn from here: give it a "SnapImage"
-- attribute (a name render_gui.py knows, like a weapon's id) and it pastes
-- that picture in.

local GUI = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ScrollingFrame = true,
	ViewportFrame = true, ImageLabel = true, ImageButton = true, CanvasGroup = true,
}
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

-- (the pretend Roblox keeps some values as plain lists)
local function v2(v, i, default)
	if type(v) ~= "table" then
		return default
	end
	local x = i == 1 and (v.X or v[1]) or (v.Y or v[2])
	return tonumber(x) or default
end
local function udim(u)
	if type(u) ~= "table" then
		return 0, 0
	end
	return tonumber(u.Scale or u[1]) or 0, tonumber(u.Offset or u[2]) or 0
end
local function rgb(c, default)
	if not c then
		return default
	end
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function encode(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "0"
		end
		return string.format("%.2f", v):gsub("%.?0+$", "")
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(ch)
			if ch == "\n" then
				return "\\n"
			end
			return string.format("\\u%04x", string.byte(ch))
		end) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for i, x in ipairs(v) do
				out[i] = encode(x)
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, k)
		end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do
			table.insert(out, encode(tostring(k)) .. ":" .. encode(v[k]))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local function childOf(obj, class)
	for _, c in ipairs(obj:GetChildren()) do
		if c.ClassName == class and c.Enabled ~= false then
			return c
		end
	end
	return nil
end

-- a UIGradient's colours: { {t, r, g, b}, ... } and its turn
local function gradientOf(obj)
	local g = childOf(obj, "UIGradient")
	if not g or type(g.Color) ~= "table" then
		return nil
	end
	-- (ColorSequence.new({ keypoints }) or ColorSequence.new(from, to); a
	-- keypoint is { time, colour })
	local seq, keys = g.Color, {}
	local first = rawget(seq, 1)
	if type(first) == "table" and rawget(first, "R") == nil then
		for _, kp in ipairs(first) do
			local c = rgb(rawget(kp, 2))
			table.insert(keys, { rawget(kp, 1) or 0, c[1], c[2], c[3] })
		end
	elseif first then
		local a = rgb(first)
		local b = rgb(rawget(seq, 2) or first)
		keys = { { 0, a[1], a[2], a[3] }, { 1, b[1], b[2], b[3] } }
	end
	if #keys == 0 then
		return nil
	end
	return { keys = keys, rot = tonumber(g.Rotation) or 0 }
end

return function(root, caption, SW, SH)
	SW, SH = SW or 1280, SH or 720
	print("SNAP " .. caption)
	local frames = {}
	local laidOut = {} -- [child] = { x, y, w, h } from its parent's layout

	-- where a layout puts each of `parent`'s children
	local function layout(parent, pw, ph)
		local list, grid = childOf(parent, "UIListLayout"), childOf(parent, "UIGridLayout")
		if not list and not grid then
			return
		end
		local kids = {}
		for i, c in ipairs(parent:GetChildren()) do
			if GUI[c.ClassName] and c.Visible ~= false then
				table.insert(kids, { c = c, i = i })
			end
		end
		table.sort(kids, function(a, b)
			local la, lb = a.c.LayoutOrder or 0, b.c.LayoutOrder or 0
			if la ~= lb then
				return la < lb
			end
			return a.i < b.i
		end)
		if list then
			local ps, po = udim(list.Padding)
			local pad = ph * ps + po
			local horizontal = list.FillDirection and list.FillDirection.Name == "Horizontal"
			local at = 0
			local sizes = {}
			for _, k in ipairs(kids) do
				local s = k.c.Size
				local w = s and (pw * s.X.Scale + s.X.Offset) or 0
				local h = s and (ph * s.Y.Scale + s.Y.Offset) or 0
				sizes[k.c] = { w, h }
				at = at + (horizontal and w or h) + pad
			end
			local total = math.max(0, at - pad)
			local start = 0
			if not horizontal and list.VerticalAlignment and list.VerticalAlignment.Name == "Bottom" then
				start = ph - total
			elseif not horizontal and list.VerticalAlignment and list.VerticalAlignment.Name == "Center" then
				start = (ph - total) / 2
			end
			at = start
			for _, k in ipairs(kids) do
				local w, h = sizes[k.c][1], sizes[k.c][2]
				if horizontal then
					laidOut[k.c] = { at, 0, w, h }
					at = at + w + pad
				else
					local x = 0
					if list.HorizontalAlignment and list.HorizontalAlignment.Name == "Center" then
						x = (pw - w) / 2
					elseif list.HorizontalAlignment and list.HorizontalAlignment.Name == "Right" then
						x = pw - w
					end
					laidOut[k.c] = { x, at, w, h }
					at = at + h + pad
				end
			end
		else
			local cs, cp = grid.CellSize, grid.CellPadding
			local cw = cs and (pw * cs.X.Scale + cs.X.Offset) or 100
			local ch = cs and (ph * cs.Y.Scale + cs.Y.Offset) or 100
			local gx = cp and (pw * cp.X.Scale + cp.X.Offset) or 5
			local gy = cp and (ph * cp.Y.Scale + cp.Y.Offset) or 5
			local perRow = math.max(1, math.floor((pw + gx) / (cw + gx)))
			for n, k in ipairs(kids) do
				local col, row = (n - 1) % perRow, math.floor((n - 1) / perRow)
				laidOut[k.c] = { col * (cw + gx), row * (ch + gy), cw, ch }
			end
		end
	end

	-- an object's own space: T maps its unscaled pixels to the screen
	local function frameOf(obj)
		if frames[obj] then
			return frames[obj]
		end
		local f
		if obj == root then
			f = { T = function(x, y)
				return x, y
			end, w = SW, h = SH }
		else
			local P = frameOf(obj.Parent)
			if not P.laid then
				P.laid = true
				layout(obj.Parent, P.w, P.h)
			end
			local w, h, apx, apy, ax, ay
			local lay = laidOut[obj]
			if lay then
				apx, apy, w, h, ax, ay = lay[1], lay[2], lay[3], lay[4], 0, 0
			else
				local size, pos = obj.Size, obj.Position
				w = size and (P.w * size.X.Scale + size.X.Offset) or 0
				h = size and (P.h * size.Y.Scale + size.Y.Offset) or 0
				apx = pos and (P.w * pos.X.Scale + pos.X.Offset) or 0
				apy = pos and (P.h * pos.Y.Scale + pos.Y.Offset) or 0
				ax, ay = v2(obj.AnchorPoint, 1, 0), v2(obj.AnchorPoint, 2, 0)
			end
			local sc = childOf(obj, "UIScale")
			local s = sc and (tonumber(sc.Scale) or 1) or 1
			local rot = math.rad(tonumber(obj.Rotation) or 0)
			local cx, cy = apx + (w * 0.5 - ax * w) * s, apy + (h * 0.5 - ay * h) * s
			local cs, sn = math.cos(rot), math.sin(rot)
			f = { w = w, h = h, T = function(x, y)
				local px, py = apx + (x - ax * w) * s, apy + (y - ay * h) * s
				local dx, dy = px - cx, py - cy
				return P.T(cx + dx * cs - dy * sn, cy + dx * sn + dy * cs)
			end }
		end
		frames[obj] = f
		return f
	end

	local function corners(obj)
		local f = frameOf(obj)
		local out = {}
		for _, p in ipairs({ { 0, 0 }, { f.w, 0 }, { f.w, f.h }, { 0, f.h } }) do
			local x, y = f.T(p[1], p[2])
			table.insert(out, { x, y })
		end
		-- how many screen pixels one of its own is
		local x0, y0 = f.T(0, 0)
		local x1, y1 = f.T(1, 0)
		return out, math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2), f
	end

	local SCREEN = { 0, 0, SW, SH }
	local function clips(obj)
		if obj.ClassName == "ScrollingFrame" then
			return obj.ClipsDescendants ~= false
		end
		return obj.ClipsDescendants == true
	end
	local function walk(obj, clip)
		clip = clip or SCREEN
		local print = function(line)
			-- (every item carries the box it's cut to, when that isn't the whole screen)
			if clip ~= SCREEN then
				line = string.sub(line, 1, -2) .. ',"clip":' .. encode(clip) .. "}"
			end
			print(line)
		end
		if obj ~= root then
			if obj.Visible == false then
				return
			end
			local pts, k, f = corners(obj)
			local ucorner = childOf(obj, "UICorner")
			local radius = 0
			if ucorner then
				local s, o = udim(ucorner.CornerRadius)
				radius = (s * math.min(f.w, f.h) + o) * k
			end
			local alpha = tonumber(obj.BackgroundTransparency) or 0
			local grad = gradientOf(obj)
			if alpha < 0.99 and obj.ClassName ~= "ViewportFrame" then
				print(encode({ k = "rect", pts = pts, c = rgb(obj.BackgroundColor3, { 163, 162, 165 }), t = alpha, r = radius, grad = grad }))
			end
			local stroke = childOf(obj, "UIStroke")
			local border = stroke and (stroke.ApplyStrokeMode and stroke.ApplyStrokeMode.Name == "Border" or not TEXT[obj.ClassName])
			if border and (tonumber(stroke.Transparency) or 0) < 0.99 then
				print(encode({ k = "stroke", pts = pts, c = rgb(stroke.Color, { 0, 0, 0 }), t = tonumber(stroke.Transparency) or 0,
					w = (tonumber(stroke.Thickness) or 1) * k, r = radius, grad = gradientOf(stroke) }))
			end
			if obj.ClassName == "ViewportFrame" and obj:GetAttribute("SnapImage") then
				print(encode({ k = "image", pts = pts, name = obj:GetAttribute("SnapImage") }))
			end
			if TEXT[obj.ClassName] and (obj.Text or "") ~= "" and (tonumber(obj.TextTransparency) or 0) < 0.99 then
				local pad = childOf(obj, "UIPadding")
				local l, r, t, b = 0, 0, 0, 0
				if pad then
					local s, o = udim(pad.PaddingLeft)
					l = s * f.w + o
					s, o = udim(pad.PaddingRight)
					r = s * f.w + o
					s, o = udim(pad.PaddingTop)
					t = s * f.h + o
					s, o = udim(pad.PaddingBottom)
					b = s * f.h + o
				end
				local x0, y0 = f.T(l, t)
				local x1, y1 = f.T(f.w - r, f.h - b)
				local outline = nil
				if stroke and not border and (tonumber(stroke.Transparency) or 0) < 0.99 then
					outline = { rgb(stroke.Color, { 0, 0, 0 }), (tonumber(stroke.Thickness) or 1) * k }
				elseif (tonumber(obj.TextStrokeTransparency) or 1) < 0.99 then
					outline = { rgb(obj.TextStrokeColor3, { 0, 0, 0 }), 1.5 * k, tonumber(obj.TextStrokeTransparency) }
				end
				print(encode({
					k = "text",
					box = { math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1) },
					s = obj.Text,
					c = rgb(obj.TextColor3, { 0, 0, 0 }),
					t = tonumber(obj.TextTransparency) or 0,
					size = (not obj.TextScaled) and (tonumber(obj.TextSize) or 14) * k or nil,
					xa = obj.TextXAlignment and string.sub(obj.TextXAlignment.Name, 1, 1) or "C",
					ya = obj.TextYAlignment and string.sub(obj.TextYAlignment.Name, 1, 1) or "C",
					wrap = obj.TextWrapped == true or obj.TextScaled == true,
					outline = outline,
					grad = grad,
				}))
			end
		end
		local kids = {}
		for i, c in ipairs(obj:GetChildren()) do
			if GUI[c.ClassName] then
				table.insert(kids, { c = c, i = i })
			end
		end
		table.sort(kids, function(a, b)
			local za, zb = a.c.ZIndex or 1, b.c.ZIndex or 1
			if za ~= zb then
				return za < zb
			end
			return a.i < b.i
		end)
		local inner = clip
		if obj ~= root and clips(obj) then
			local pts = corners(obj)
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, p in ipairs(pts) do
				x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
				x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
			end
			inner = { math.max(clip[1], x0), math.max(clip[2], y0), math.min(clip[3], x1), math.min(clip[4], y1) }
		end
		for _, kk in ipairs(kids) do
			walk(kk.c, inner)
		end
	end
	walk(root)
end
