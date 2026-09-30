--[[
	IndexMenu  (LocalScript, parent: StarterPlayerScripts)

	THE INDEX (purple: the Index), in the new see-through menus
	(ReplicatedStorage/Menus): everything there is to collect.
	  * WEAPONS: every weapon, pack by pack (the floor's boss, its colour),
	    rarest last. One you've found shows its picture and name; one you
	    haven't is a dark shape with "???" - and its rarity, so you know what
	    you're hunting. A new find pays once: CLAIM (RewardService.IndexFind)
	  * BOSSES: the ten floors - beaten (and how often) or still to beat
	  * COLLECTOR: the collector bar (every weapon found and every boss
	    beaten fills it) and the rewards at its levels, each claimed once
	The server decides and pays (IndexClaim, CollectorClaim).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if Config.NewHud == false then
	return
end
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local C = K.COLORS
local R = Config.Rewards
local W = Config.Weapons
local A = Config.Arcade

local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- a weapon's uploaded picture (Tools/Weapons/make_icons.py), or nil
local function weaponImage(id)
	local icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	local n = icons and icons[id]
	return n and ("rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=150&h=150") or nil
end

local function rarityColor(r)
	return (A.Colors and A.Colors[r]) or C.Slate
end

-- the collector bar's points (the same sum as RewardService.CollectorPoints)
local function collectorPoints(d)
	local owned, cleared = 0, 0
	for id in pairs(d and type(d.Weapons) == "table" and type(d.Weapons.own) == "table" and d.Weapons.own or {}) do
		if W.List[id] then
			owned = owned + 1
		end
	end
	for _, n in pairs(d and type(d.Cleared) == "table" and d.Cleared or {}) do
		if (tonumber(n) or 0) > 0 then
			cleared = cleared + 1
		end
	end
	return owned * R.CollectorPoints.Weapon + cleared * R.CollectorPoints.Boss
end

-- the collector bar across the page
local function collectorBar(api)
	local points = collectorPoints(api.state)
	local level = Config.collectorLevel(points)
	local into = points - (level - 1) * R.CollectorLevel
	local block = api.block(96)
	local face = K.card(block, { Name = "Collector", Size = UDim2.fromOffset(math.min(900, api.width), 84), ZIndex = 7 }, C.Purple)
	K.shine(face, 0.12).ZIndex = 8
	K.icon(face, "Index", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(62, 62), ZIndex = 9 })
	K.big(face, { Name = "Level", Text = "COLLECTOR LV " .. level, TextScaled = false, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(88, 6), Size = UDim2.new(1, -100, 0, 36), ZIndex = 9 })
	local m = K.meter(face, { Name = "Meter", Color = C.Yellow, Position = UDim2.fromOffset(88, 46), Size = UDim2.new(1, -110, 0, 26), ZIndex = 9 })
	m:set(into / R.CollectorLevel, into .. " / " .. R.CollectorLevel .. " TO LV " .. (level + 1))
	return level
end

----------------------------------------------------------------------
-- the pages
----------------------------------------------------------------------
local function weaponCard(grid, order, id, def, owned, claimed, api)
	local color = rarityColor(def.Rarity)
	local face = K.card(grid, { Name = id, LayoutOrder = order, ZIndex = 7 }, owned and color or C.Well)
	if owned then
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205)) }, face)
	end
	K.label(face, { Name = "Rarity", Text = string.upper(def.Rarity), Font = K.TITLE_FONT, TextScaled = false, TextSize = 11, TextColor3 = owned and C.White or color, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 16), ZIndex = 9 })
	local image = owned and weaponImage(id) or nil
	if image then
		new("ImageLabel", { Name = "Picture", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(84, 84), ZIndex = 9 }, face)
	else
		-- (not found yet, or not uploaded: its shape in shadow / the type's stand-in)
		K.big(face, { Name = "Shape", Text = owned and "⚔️" or "?", TextScaled = false, TextSize = 56, TextColor3 = owned and C.White or Color3.fromRGB(70, 60, 100), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(84, 70), ZIndex = 9 })
	end
	K.big(face, { Name = "WeaponName", Text = owned and def.Name or "???", TextScaled = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.new(1, -12, 0, 26), ZIndex = 9, Edge = 2 })
	if owned and not claimed then
		local pay = R.IndexFind[def.Rarity] or {}
		local b = api.button(face, "CLAIM", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 36), ZIndex = 10 })
		b.Activated:Connect(function()
			api.act("IndexClaim", id)
		end)
		K.label(face, { Name = "Pays", Text = Config.rewardText(pay), TextScaled = false, TextSize = 14, TextColor3 = C.White, TextStrokeTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -48), Size = UDim2.new(1, -8, 0, 16), ZIndex = 9 })
	elseif owned then
		K.chip(face, "IN INDEX", C.Ink, { Name = "Done", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), ZIndex = 9 })
	end
end

local function weaponsPage(page, api)
	local d = api.state or {}
	local own = type(d.Weapons) == "table" and type(d.Weapons.own) == "table" and d.Weapons.own or {}
	local rw = type(d.Rewards) == "table" and d.Rewards or {}
	local idx = type(rw.index) == "table" and rw.index or {}
	collectorBar(api)
	-- the starters, then each pack in floor order
	local groups = { { title = "Starters", color = C.Slate, list = W.Starters or {} } }
	local packs = table.clone(W.Packs or {})
	table.sort(packs, function(a, b)
		return (a.Floor or 0) < (b.Floor or 0)
	end)
	for _, p in ipairs(packs) do
		table.insert(groups, { title = "Floor " .. p.Floor .. " · " .. p.Id .. " (" .. p.Boss .. ")", list = p.Weapons })
	end
	for _, g in ipairs(groups) do
		local found = 0
		for _, id in ipairs(g.list) do
			if own[id] ~= nil then
				found = found + 1
			end
		end
		api.section(g.title, found .. " / " .. #g.list .. " found")
		local grid = api.grid(#g.list, 150, 180, 12)
		for i, id in ipairs(g.list) do
			local def = W.List[id]
			if def then
				weaponCard(grid, i, id, def, own[id] ~= nil, idx[id] == true, api)
			end
		end
	end
end

local function bossesPage(page, api)
	local d = api.state or {}
	local cleared = type(d.Cleared) == "table" and d.Cleared or {}
	local beaten = 0
	for _, f in ipairs(Config.Spire.Floors) do
		if (tonumber(cleared[tostring(f.id)]) or 0) > 0 then
			beaten = beaten + 1
		end
	end
	api.section("The Spire's bosses", beaten .. " / " .. #Config.Spire.Floors .. " beaten")
	local grid = api.grid(#Config.Spire.Floors, 250, 170, 14)
	for i, f in ipairs(Config.Spire.Floors) do
		local n = tonumber(cleared[tostring(f.id)]) or 0
		local face = K.card(grid, { Name = "Floor" .. f.id, LayoutOrder = i, ZIndex = 7 }, n > 0 and (f.color or C.Red) or C.Well)
		local bar = new("Frame", { Name = "Bar", BackgroundColor3 = n > 0 and C.Red or C.Night, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 34), ZIndex = 8 }, face)
		new("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = 8 }, bar)
		K.label(bar, { Text = "FLOOR " .. f.id, Font = K.TITLE_FONT, TextScaled = false, TextSize = 14, TextColor3 = C.White, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -50, 1, 0), ZIndex = 9 })
		if n == 0 then
			K.icon(bar, "Lock", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(26, 26), ZIndex = 9 })
		end
		local short = string.match(f.boss, "^([^,]+)") or f.boss
		K.big(face, { Name = "Boss", Text = short, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 34), ZIndex = 9 })
		K.big(face, { Name = "Area", Text = f.area or "", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 0, 22), ZIndex = 9, Edge = 2 })
		if n > 0 then
			K.chip(face, "BEATEN x" .. n, C.Green, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), ZIndex = 9 })
		else
			K.chip(face, "LV " .. f.level, C.Slate, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), ZIndex = 9 })
		end
	end
	api.words("Every boss you beat for the first time fills your collector bar (+" .. R.CollectorPoints.Boss .. ").", 30)
end

local function collectorPage(page, api)
	local d = api.state or {}
	local rw = type(d.Rewards) == "table" and d.Rewards or {}
	local got = type(rw.milestones) == "table" and rw.milestones or {}
	local level = collectorBar(api)
	api.words("+" .. R.CollectorPoints.Weapon .. " for every weapon you find, +" .. R.CollectorPoints.Boss .. " for every boss you beat. Every " .. R.CollectorLevel .. " is a level.", 30)
	api.section("Collector rewards")
	for _, m in ipairs(R.Collector) do
		local block = api.block(84)
		local reached = level >= m.Level
		local claimed = got[tostring(m.Level)] == true
		local face = K.card(block, { Name = "Level" .. m.Level, Size = UDim2.fromOffset(math.min(760, api.width), 74), ZIndex = 7 }, reached and not claimed and C.Gold or C.Paper)
		K.chip(face, "LV " .. m.Level, reached and C.Purple or C.Slate, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), ZIndex = 9 })
		K.label(face, { Name = "Reward", Text = Config.rewardText(m), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = (reached and not claimed) and C.White or C.Ink, TextStrokeTransparency = (reached and not claimed) and 0.4 or 1, Position = UDim2.fromOffset(110, 12), Size = UDim2.new(1, -330, 1, -24), ZIndex = 9 })
		if claimed then
			K.chip(face, "CLAIMED", C.Ink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), ZIndex = 9 })
		elseif reached then
			local b = api.button(face, "CLAIM", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(150, 48), ZIndex = 10 })
			b.Activated:Connect(function()
				api.act("CollectorClaim", m.Level)
			end)
		else
			K.icon(face, "Lock", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.fromOffset(40, 40), ZIndex = 9 })
		end
	end
end

Menus.define("Index", {
	Title = "Index",
	Color = C.Purple,
	Tabs = {
		{ Key = "Weapons", Label = "Weapons", Icon = "Weapons" },
		{ Key = "Bosses", Label = "Bosses", Icon = "Bosses" },
		{ Key = "Collector", Label = "Collector", Icon = "Goals" },
	},
	render = function(page, tab, api)
		if tab == "Bosses" then
			bossesPage(page, api)
		elseif tab == "Collector" then
			collectorPage(page, api)
		else
			weaponsPage(page, api)
		end
	end,
})
