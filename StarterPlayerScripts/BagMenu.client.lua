--[[
	BagMenu  (LocalScript, parent: StarterPlayerScripts)

	THE BAG (teal: the bag), in the new see-through menus
	(ReplicatedStorage/Menus). The BAG button and B open it.
	  * WEAPONS: the weapon in your hand, big - its rarity, type, mastery
	    (and how far to the next level), its ONE ability on [F] with what it
	    does now and what the next mastery tier adds - and every weapon you
	    own as rarity-coloured cards (rarest first; filter by rarity). Tap a
	    card to look at it, EQUIP to hold it (FISTS to put it away).
	  * LOOKS: wear your titles and auras (the shop's Looks page)
	Equipping is the server's (the EquipWeapon action).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if Config.NewHud == false then
	return
end
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures")) -- (the uploaded pictures, fast)
local C = K.COLORS
local W = Config.Weapons
local A = Config.Arcade

local player = Players.LocalPlayer
local picked = nil -- the weapon being looked at (nil: the one in your hand)
local filter = "All" -- which rarity the grid shows
local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }

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

local function weaponImage(id)
	local icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	local n = icons and icons[id]
	return n and Pictures.url(n) or nil
end
local function rarityColor(r)
	return (A.Colors and A.Colors[r]) or C.Slate
end

-- what the ability does at this mastery, and what the next tier adds:
-- (now, nextText, nextMastery)
local function abilityWords(def, level)
	local ab = def.Ability
	if type(ab) ~= "table" then
		return "No ability", nil, nil
	end
	local say = ab.Say
	if type(ab.Tiers) == "table" and type(say) == "table" then
		local at, nextTier = 1, nil
		for i, t in ipairs(ab.Tiers) do
			if level >= (t.Mastery or 1) then
				at = i
			elseif not nextTier then
				nextTier = i
			end
		end
		local nxt = nextTier and say[nextTier] or nil
		return say[at] or ab.Name, nxt, nextTier and ab.Tiers[nextTier].Mastery or nil
	end
	return type(say) == "string" and say or "A special move", nil, nil
end

-- the weapon's picture in a frame (its icon once uploaded, else a stand-in)
local function picture(parent, id, size, props)
	local image = weaponImage(id)
	local p
	if image then
		p = new("ImageLabel", { Name = "Picture", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(size, size) }, parent)
	else
		p = K.icon(parent, "Weapons", { Name = "Picture", Size = UDim2.fromOffset(size, size) })
	end
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return p
end

----------------------------------------------------------------------
-- WEAPONS
----------------------------------------------------------------------
local function weaponsPage(page, api)
	local d = api.state or {}
	local own = type(d.Weapons) == "table" and type(d.Weapons.own) == "table" and d.Weapons.own or {}
	local held = player:GetAttribute("Weapon")
	local show = picked and own[picked] ~= nil and picked or (held and own[held] ~= nil and held or nil)
	-- the one you're looking at
	local block = api.block(300)
	local detail = K.card(block, { Name = "Detail", Size = UDim2.fromOffset(math.min(1000, api.width), 286), ZIndex = 7 }, show and rarityColor(W.List[show].Rarity) or C.Slate)
	K.shine(detail, 0.12).ZIndex = 8
	if not show then
		K.icon(detail, "Weapons", { Position = UDim2.fromOffset(24, 40), Size = UDim2.fromOffset(160, 160), ZIndex = 9 })
		K.big(detail, { Name = "WeaponName", Text = "Fists", TextScaled = false, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(210, 20), Size = UDim2.new(1, -230, 0, 50), ZIndex = 9 })
		K.big(detail, { Name = "Words", Text = "Nothing in your hand. Pick a weapon below and EQUIP it - or win one at the Arcade.", TextScaled = false, TextSize = 22, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(210, 80), Size = UDim2.new(1, -230, 0, 90), ZIndex = 9, Edge = 2 })
	else
		local def = W.List[show]
		local level, frac = Config.masteryLevel(own[show] or 0)
		local frame = new("Frame", { Name = "PictureBox", BackgroundColor3 = C.Ink, BackgroundTransparency = 0.6, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(180, 180), ZIndex = 9 }, detail)
		K.outline(frame, C.Ink, 3)
		picture(frame, show, 160, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 10 })
		K.chip(detail, string.upper(def.Rarity) .. " " .. string.upper(def.Type or ""), C.Ink, { Name = "Kind", Position = UDim2.fromOffset(216, 18), ZIndex = 9 })
		K.big(detail, { Name = "WeaponName", Text = def.Name, TextScaled = false, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(216, 50), Size = UDim2.new(1, -440, 0, 50), ZIndex = 9 })
		local m = K.meter(detail, { Name = "Mastery", Color = level >= W.MasteryMax and C.Gold or C.Blue, Position = UDim2.fromOffset(216, 106), Size = UDim2.new(1, -440, 0, 26), ZIndex = 9 })
		m:set(frac, level >= W.MasteryMax and "MASTERY " .. level .. " - AWAKENED" or ("MASTERY " .. level .. "  (" .. math.floor(frac * 100) .. "% TO " .. (level + 1) .. ")"))
		-- the ONE ability, on [F]
		local ab = type(def.Ability) == "table" and def.Ability or {}
		local now, nxt, at = abilityWords(def, level)
		local key = new("TextLabel", { Name = "Key", BackgroundColor3 = C.White, BorderSizePixel = 0, Font = K.TITLE_FONT, Text = "F", TextColor3 = C.Ink, TextSize = 20, Position = UDim2.fromOffset(216, 146), Size = UDim2.fromOffset(40, 40), ZIndex = 9 }, detail)
		K.outline(key, C.Ink, 3)
		K.big(detail, { Name = "Ability", Text = (ab.Name or (def.Ability and "Ability" or "No ability")) .. (ab.Cooldown and ("  ·  " .. ab.Cooldown .. "s") or ""), TextScaled = false, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(268, 146), Size = UDim2.new(1, -490, 0, 40), ZIndex = 9 })
		K.big(detail, { Name = "Now", Text = now, TextScaled = false, TextSize = 20, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(216, 194), Size = UDim2.new(1, -440, 0, 44), ZIndex = 9, Edge = 2 })
		if nxt then
			K.big(detail, { Name = "Next", Text = "At mastery " .. at .. ": " .. nxt, TextScaled = false, TextSize = 18, TextWrapped = true, TextColor3 = C.Yellow, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(216, 240), Size = UDim2.new(1, -440, 0, 40), ZIndex = 9, Edge = 2 })
		end
		if show == held then
			K.chip(detail, "IN HAND", C.Green, { Name = "InHand", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 20), ZIndex = 9 })
			local fists = api.button(detail, "FISTS", C.Slate, { Name = "Fists", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(190, 54), ZIndex = 10 })
			fists.Activated:Connect(function()
				api.act("EquipWeapon", nil)
			end)
		else
			local equip = api.button(detail, "EQUIP", C.Green, { Name = "Equip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(190, 54), ZIndex = 10 })
			equip.Activated:Connect(function()
				api.act("EquipWeapon", show)
			end)
		end
	end
	-- the filter
	local ids = {}
	for id in pairs(own) do
		local def = W.List[id]
		if def and (filter == "All" or def.Rarity == filter) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = RANK[W.List[a].Rarity] or 0, RANK[W.List[b].Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		return W.List[a].Name < W.List[b].Name
	end)
	local count = 0
	for id in pairs(own) do
		if W.List[id] then
			count = count + 1
		end
	end
	api.section("Your weapons", count .. " owned")
	local row = api.block(44)
	local x = 0
	for _, r in ipairs({ "All", "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
		local on = filter == r
		local w = #r * 13 + 30
		local b = new("TextButton", {
			Name = "Filter_" .. r,
			Text = string.upper(r),
			Font = K.TITLE_FONT,
			TextSize = 12,
			TextColor3 = C.White,
			TextStrokeTransparency = 0,
			AutoButtonColor = false,
			BackgroundColor3 = on and (r == "All" and C.Gold or rarityColor(r)) or C.Night,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, 4),
			Size = UDim2.fromOffset(w, 34),
			ZIndex = 8,
		}, row)
		K.outline(b, on and C.White or C.Ink, 3)
		b:SetAttribute("On", on)
		b.Activated:Connect(function()
			filter = r
			api.redraw()
		end)
		x = x + w + 8
	end
	if #ids == 0 then
		api.words(filter == "All" and "No weapons yet - spin the Arcade's machines!" or ("No " .. filter .. " weapons yet."), 30)
		return
	end
	local grid = api.grid(#ids, 160, 190, 12)
	for i, id in ipairs(ids) do
		local def = W.List[id]
		local level = Config.masteryLevel(own[id] or 0)
		local face = K.card(grid, { Name = id, LayoutOrder = i, ZIndex = 7 }, rarityColor(def.Rarity))
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 200)) }, face)
		K.label(face, { Name = "Rarity", Text = string.upper(def.Rarity), Font = K.TITLE_FONT, TextScaled = false, TextSize = 10, TextColor3 = C.White, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 14), ZIndex = 9 })
		picture(face, id, 96, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), ZIndex = 9 })
		K.big(face, { Name = "WeaponName", Text = def.Name, TextScaled = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.new(1, -12, 0, 26), ZIndex = 9, Edge = 2 })
		K.label(face, { Name = "Level", Text = "MASTERY " .. level, Font = K.TITLE_FONT, TextScaled = false, TextSize = 10, TextColor3 = level >= W.MasteryMax and C.Yellow or C.White, TextStrokeTransparency = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -12, 0, 14), ZIndex = 9 })
		if id == held then
			-- (a green corner with E: the one in your hand)
			local corner = new("Frame", { Name = "Equipped", BackgroundColor3 = C.Green, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(34, 34), ZIndex = 10 }, face)
			K.outline(corner, C.Ink, 2)
			new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = K.FONT, Text = "E", TextColor3 = C.White, TextScaled = true, TextStrokeTransparency = 0, ZIndex = 11 }, corner)
		end
		if id == show then
			local ring = new("Frame", { Name = "Picked", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = 10 }, face)
			K.outline(ring, C.White, 3)
		end
		local tap = new("TextButton", { Name = "Tap", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12 }, face)
		tap.Activated:Connect(function()
			picked = id
			api.redraw()
		end)
	end
end

local function looksPage(page, api)
	if Menus.pages and Menus.pages.Looks then
		Menus.pages.Looks(page, api)
	else
		api.words("Your titles and auras are in the shop's Looks page.", 30)
	end
end

Menus.define("Bag", {
	Title = "Bag",
	Color = C.Teal,
	Tabs = {
		{ Key = "Weapons", Label = "Weapons", Icon = "Weapons" },
		{ Key = "Looks", Label = "Looks", Icon = "Looks" },
	},
	render = function(page, tab, api)
		if tab == "Looks" then
			looksPage(page, api)
		else
			weaponsPage(page, api)
		end
	end,
	opened = function()
		picked = nil
	end,
})

-- a new weapon in your hand: the Bag shows it
player:GetAttributeChangedSignal("Weapon"):Connect(function()
	local name, tab = Menus.current()
	if name == "Bag" and tab == "Weapons" then
		picked = nil
		Menus.redraw()
	end
end)
