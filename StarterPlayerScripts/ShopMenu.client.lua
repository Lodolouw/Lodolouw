--[[
	ShopMenu  (LocalScript, parent: StarterPlayerScripts)

	THE SHOP (gold: the shop), in the new see-through menus
	(ReplicatedStorage/Menus). It only SHOWS and ASKS - the server decides
	(ShopService): it shows Roblox's own purchase prompt, and hands out what
	was paid for exactly once.
	  * FEATURED: the Arcade, the Starter Pack (once per player), VIP, and
	    the tickets as quick buys
	  * TICKETS: Revive x3, Spin x3, Boss Rush x3, 30 min 2x XP - and how many
	    you have
	  * TOKENS: the token packs (with how much more each bigger one really
	    gives), and every free way to earn tokens. Where Roblox doesn't allow
	    paid random items (NoPaidRandom), no packs - just the free ways.
	  * DAILY: five looks for coins, the same for everyone, new every day
	  * PASSES: VIP, 2x XP, 2x Coins, the luck passes, Instant x10
	  * LOOKS: every title and aura - wear the ones you have (everyone sees
	    them), and where to get the rest (Menus.pages.Looks: the Bag shows it too)
	Our rules: nothing here makes you stronger in a fight, the Arcade always
	shows its odds, no made-up "was" prices, and a product without its id yet
	says SOON. The GIFT button buys it for someone else in the server.
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
local S = Config.Shop
local R = Config.Rewards
local L = Config.Looks

local player = Players.LocalPlayer
local ROBUX = utf8.char(0xE002) -- (Roblox draws its Robux sign for this)
local giftKey = nil -- a product being gifted: the picker shows at the top of the page
local ui = {} -- the Daily page's clock

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

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function noRandom()
	return player:GetAttribute("NoPaidRandom") == true
end
local function hasPass(key)
	return player:GetAttribute("Pass_" .. key) == true
end

-- a weapon's uploaded picture, or nil
local function weaponImage(id)
	local icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	local n = icons and icons[id]
	return n and ("rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=150&h=150") or nil
end

----------------------------------------------------------------------
-- buying
----------------------------------------------------------------------
-- the price button: BUY at its price - or SOON while it has no id yet
local function buyButton(api, parent, key, props, isPass)
	local def = isPass and S.Passes[key] or S.Products[key]
	local id = isPass and def.PassId or def.ProductId
	if (id or 0) <= 0 then
		local b = api.button(parent, "SOON  " .. ROBUX .. def.Price, C.Off, props)
		b.Name = "Soon"
		b.Activated:Connect(function()
			api.toast("Coming soon!", "info")
		end)
		return b
	end
	local b = api.button(parent, ROBUX .. " " .. def.Price, C.Green, props)
	b.Name = "Buy"
	b.Activated:Connect(function()
		api.act(isPass and "ShopPass" or "ShopBuy", key)
	end)
	return b
end

-- the GIFT button: pick someone in the server to buy it for
local function giftButton(api, parent, key, props)
	local def = S.Products[key]
	if not def.Gift or (def.ProductId or 0) <= 0 then
		return nil
	end
	local b = api.button(parent, "", C.Pink, props)
	b.Name = "Gift"
	b:FindFirstChildOfClass("UIPadding"):Destroy()
	K.icon(b, "Gift", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.75, 0.75), ZIndex = b.ZIndex + 1 })
	b.Activated:Connect(function()
		giftKey = key
		api.redraw()
	end)
	return b
end

-- who to gift it to (at the top of the page while a gift is being chosen)
local function giftPicker(api)
	if not giftKey then
		return
	end
	local def = S.Products[giftKey]
	api.section("Gift " .. def.Name .. " to...", "they get it, you pay")
	local others = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		api.words("Nobody else is in this server right now.", 30)
	else
		local grid = api.grid(#others, 220, 96, 12)
		for i, p in ipairs(others) do
			local face = K.card(grid, { Name = "To_" .. p.UserId, LayoutOrder = i, ZIndex = 7 })
			K.label(face, { Name = "Who", Text = p.DisplayName, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 32), ZIndex = 9 })
			local b = api.button(face, "GIFT", C.Pink, { Name = "GiftTo", Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 38), ZIndex = 10 })
			b.Activated:Connect(function()
				local key = giftKey
				giftKey = nil
				api.act("ShopBuy", { key = key, gift = p.UserId })
				api.redraw()
			end)
		end
	end
	local row = api.block(56)
	local cancel = api.button(row, "CANCEL", C.Slate, { Name = "Cancel", Size = UDim2.fromOffset(180, 46), ZIndex = 8 })
	cancel.Activated:Connect(function()
		giftKey = nil
		api.redraw()
	end)
end

-- a product card: its colour, name, words, picture, price and gift button
local function productCard(api, grid, order, key, color, icon, words)
	local def = S.Products[key]
	local face = K.card(grid, { Name = key, LayoutOrder = order, ZIndex = 7 }, color)
	K.shine(face, 0.18).ZIndex = 8
	K.big(face, { Name = "ProductName", Text = def.Name, TextScaled = false, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 34), ZIndex = 9 })
	K.big(face, { Name = "Words", Text = words, TextScaled = false, TextSize = 18, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -110, 0, 60), ZIndex = 9, Edge = 2 })
	K.icon(face, icon, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 44), Size = UDim2.fromOffset(80, 80), ZIndex = 9 })
	buyButton(api, face, key, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.fromOffset(150, 46), ZIndex = 10 })
	giftButton(api, face, key, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 176, 1, -14), Size = UDim2.fromOffset(46, 46), ZIndex = 10 })
	return face
end

local TICKETS = {
	{ "Revive3", C.Green, "Revive", "Keep fighting when a boss would finish you (one per fight)." },
	{ "Spin3", C.Gold, "Spin", "Three Arcade spins." },
	{ "Rush3", C.Teal, "BossRush", "Beat a boss you've beaten before for 2x the rewards." },
	{ "Boost30", C.Pink, "Bolt", "Double XP for 30 minutes of play." },
}

----------------------------------------------------------------------
-- FEATURED
----------------------------------------------------------------------
local function featuredPage(page, api)
	local d = api.state or {}
	giftPicker(api)
	-- the Arcade
	local block = api.block(190)
	local face = K.card(block, { Name = "ArcadeBanner", Size = UDim2.fromOffset(math.min(1000, api.width), 176), ZIndex = 7 }, C.Purple)
	new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.Purple), ColorSequenceKeypoint.new(0.55, C.Pink), ColorSequenceKeypoint.new(1, C.Gold) }) }, face)
	K.shine(face, 0.14).ZIndex = 8
	K.big(face, { Name = "Heading", Text = "THE ARCADE", TextScaled = false, TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(420, 50), ZIndex = 9 })
	K.big(face, { Name = "Sub", Text = "Weapons from every boss - the real odds on every machine", TextScaled = false, TextSize = 20, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(20, 64), Size = UDim2.fromOffset(420, 50), ZIndex = 9, Edge = 2 })
	local open = api.button(face, "OPEN ARCADE", C.Green, { Name = "OpenArcade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -16), Size = UDim2.fromOffset(220, 48), ZIndex = 10 })
	open.Activated:Connect(function()
		api.go("Arcade")
	end)
	local pack = Config.Weapons.Packs and Config.Weapons.Packs[1]
	for i = 1, 4 do
		local id = pack and pack.Weapons[i + 2]
		local def = id and Config.Weapons.List[id]
		if def then
			local tile = new("Frame", { Name = "Tile", BackgroundColor3 = (Config.Arcade.Colors or {})[def.Rarity] or C.Slate, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20 - (4 - i) * 104, 0.5, 0), Size = UDim2.fromOffset(92, 110), ZIndex = 9 }, face)
			K.outline(tile, C.Ink, 3)
			local image = weaponImage(id)
			if image then
				new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), ZIndex = 10 }, tile)
			else
				K.icon(tile, "Weapons", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(60, 60), ZIndex = 10 })
			end
			K.label(tile, { Text = string.upper(def.Rarity), Font = K.TITLE_FONT, TextScaled = false, TextSize = 9, TextColor3 = C.White, TextStrokeTransparency = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, 0, 0, 14), ZIndex = 11 })
		end
	end
	-- the Starter Pack (once per player)
	local st = S.Products.Starter
	if st and not (type(d.Shop) == "table" and d.Shop.starter) then
		local sb = api.block(236)
		local sf = K.card(sb, { Name = "Starter", Size = UDim2.fromOffset(math.min(1000, api.width), 222), ZIndex = 7 }, C.Teal)
		new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(15, 122, 90), Color3.fromRGB(28, 78, 122)) }, sf)
		local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), ZIndex = 8 }, sf)
		K.outline(ring, C.Yellow, 3)
		K.big(sf, { Name = "Heading", Text = st.Name, TextScaled = false, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(400, 46), ZIndex = 9 })
		K.chip(sf, "ONE PER PLAYER", C.Pink, { Position = UDim2.fromOffset(24, 66), ZIndex = 9 })
		local items = {}
		if (st.Tokens or 0) > 0 then
			table.insert(items, { "Token", "x" .. st.Tokens })
		end
		if (st.Coins or 0) > 0 then
			table.insert(items, { "Coin", "x" .. Config.format(st.Coins) })
		end
		if (st.Revives or 0) > 0 then
			table.insert(items, { "Revive", st.Revives .. " revive" })
		end
		if st.Title then
			table.insert(items, { "Titles", "\"" .. st.Title .. "\" title" })
		end
		for i, it in ipairs(items) do
			local tile = new("Frame", { Name = "Item", BackgroundColor3 = Color3.fromRGB(255, 243, 196), BorderSizePixel = 0, Position = UDim2.fromOffset(24 + (i - 1) * 124, 104), Size = UDim2.fromOffset(112, 100), ZIndex = 9 }, sf)
			K.outline(tile, C.Ink, 3)
			if it[1] == "Token" then
				K.token(tile, 48, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 10 })
			elseif it[1] == "Coin" then
				K.coin(tile, 48, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 10 })
			else
				K.icon(tile, it[1], { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(52, 52), ZIndex = 10 })
			end
			K.label(tile, { Text = it[2], TextWrapped = true, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -8, 0, 30), ZIndex = 10 })
		end
		buyButton(api, sf, "Starter", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(200, 56), ZIndex = 10 })
	end
	-- VIP
	local vip = S.Passes.VIP
	if vip then
		local vb = api.block(150)
		local vf = K.card(vb, { Name = "VIP", Size = UDim2.fromOffset(math.min(1000, api.width), 136), ZIndex = 7 }, C.Gold)
		K.shine(vf, 0.16).ZIndex = 8
		K.icon(vf, "Passes", { Position = UDim2.fromOffset(16, 18), Size = UDim2.fromOffset(96, 96), ZIndex = 9 })
		K.big(vf, { Name = "Heading", Text = "VIP", TextScaled = false, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(128, 12), Size = UDim2.fromOffset(300, 46), ZIndex = 9 })
		K.big(vf, { Name = "Perks", Text = string.format("+%d%% XP, +%d%% coins, the VIP title - and +%d%% XP for friends in your server", S.VIP.XP * 100, S.VIP.Coins * 100, S.VIP.FriendXP), TextScaled = false, TextSize = 20, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(128, 60), Size = UDim2.new(1, -370, 0, 60), ZIndex = 9, Edge = 2 })
		if hasPass("VIP") then
			K.chip(vf, "OWNED", C.Ink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), ZIndex = 9 })
		else
			buyButton(api, vf, "VIP", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(200, 56), ZIndex = 10 }, true)
		end
	end
	-- the tickets, as quick buys
	api.section("Tickets", "quick buys")
	local list = {}
	for _, t in ipairs(TICKETS) do
		local def = S.Products[t[1]]
		if def and t[1] ~= "Boost30" and not (def.Random and noRandom()) then
			table.insert(list, t)
		end
	end
	local grid = api.grid(#list, 320, 190, 14)
	for i, t in ipairs(list) do
		productCard(api, grid, i, t[1], t[2], t[3], t[4])
	end
end

----------------------------------------------------------------------
-- TICKETS
----------------------------------------------------------------------
local function ticketsPage(page, api)
	local d = api.state or {}
	local tk = type(d.Tickets) == "table" and d.Tickets or {}
	giftPicker(api)
	api.section("Tickets", "You have " .. (tk.Revive or 0) .. " revives · " .. (tk.Rush or 0) .. " Boss Rush")
	local list = {}
	for _, t in ipairs(TICKETS) do
		local def = S.Products[t[1]]
		if def and not (def.Random and noRandom()) then
			table.insert(list, t)
		end
	end
	local grid = api.grid(#list, 320, 190, 14)
	for i, t in ipairs(list) do
		productCard(api, grid, i, t[1], t[2], t[3], t[4])
	end
	api.words("Revives and Boss Rush tickets are used by themselves in boss fights - you can turn each off in Settings.", 30)
end

----------------------------------------------------------------------
-- TOKENS
----------------------------------------------------------------------
local PACKS = { "Tokens10", "Tokens25", "Tokens60", "Tokens150" }
local function tokensPage(page, api)
	giftPicker(api)
	if noRandom() then
		api.section("Token packs")
		api.words("Token packs can't be bought where you live - but every token can be earned by playing:", 30)
	else
		api.section("Token packs", "spin the Arcade's machines")
		local base = S.Products[PACKS[1]]
		local perRobux = base and base.Tokens / base.Price or 0
		local grid = api.grid(#PACKS, 240, 290, 14)
		for i, key in ipairs(PACKS) do
			local def = S.Products[key]
			if def then
				local face = K.card(grid, { Name = key, LayoutOrder = i, ZIndex = 7 }, i == #PACKS and C.Gold or C.Purple)
				K.shine(face, 0.16).ZIndex = 8
				-- a stack of tokens: more for the bigger packs
				for j = 1, i do
					K.token(face, 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (j - (i + 1) / 2) * 30, 0, 18 + (i - j) * 6), ZIndex = 9 + j })
				end
				K.big(face, { Name = "Amount", Text = def.Tokens .. " TOKENS", TextScaled = false, TextSize = 32, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(1, -16, 0, 38), ZIndex = 20 })
				K.big(face, { Name = "PackName", Text = def.Name, TextScaled = false, TextSize = 20, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.new(1, -16, 0, 24), ZIndex = 20, Edge = 2 })
				-- how much more it really gives than the smallest pack (worked out, never made up)
				local more = perRobux > 0 and math.floor((def.Tokens / def.Price / perRobux - 1) * 100 + 0.5) or 0
				if more >= 1 then
					K.chip(face, "+" .. more .. "% MORE", C.Green, { Name = "More", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 182), ZIndex = 20 })
				end
				buyButton(api, face, key, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -84, 0, 48), ZIndex = 21 })
				giftButton(api, face, key, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(48, 48), ZIndex = 21 })
			end
		end
	end
	api.section("Free ways to earn tokens")
	local ways = {
		"Quests at the Quest Board: " .. Config.Quests.Tokens .. " token every " .. Config.Quests.Hours .. " hours",
		"Beat a Spire boss for the first time: a bundle of tokens",
		"The login streak: up to " .. ((R.Login[#R.Login] or {}).Tokens or 0) .. " tokens on day " .. #R.Login,
		"Codes on update days, and the update gift",
		"The Index: Epic and rarer finds, and collector levels",
		"The community chest: " .. Config.rewardText(R.Group),
	}
	for _, w in ipairs(ways) do
		api.words("•  " .. w, 28)
	end
end

----------------------------------------------------------------------
-- DAILY ITEMS
----------------------------------------------------------------------
local function lookPreview(parent, kind, id, z)
	if kind == "Aura" then
		local def = L.Auras[id]
		local glow = new("Frame", { Name = "Aura", BackgroundColor3 = def and def.Color or C.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(84, 84), ZIndex = z }, parent)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
		K.outline(glow, C.Ink, 3)
		if def and def.Rainbow then
			new("UIGradient", { Rotation = 45, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
			}) }, glow)
		end
		K.icon(glow, "Looks", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), ZIndex = z + 1 })
	else
		local def = L.Titles[id]
		local plate = new("Frame", { Name = "Plate", BackgroundColor3 = C.Ink, BackgroundTransparency = 0.2, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.new(1, -24, 0, 56), ZIndex = z }, parent)
		new("TextLabel", { Name = "Title", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = K.FONT, Text = "[ " .. (def and def.Text or id) .. " ]", TextColor3 = def and def.Color or C.White, TextScaled = true, TextStrokeTransparency = 0, ZIndex = z + 1 }, plate)
	end
end

local function dailyPage(page, api)
	local d = api.state or {}
	local looks = type(d.Looks) == "table" and d.Looks or {}
	local heading = api.section("Daily Items", " ")
	ui.dailyTime = heading:FindFirstChild("Sub")
	api.words("Five looks for coins, the same for everyone. Nothing here changes a fight - everyone sees them.", 30)
	local items = Config.dailyItems(Config.questDay())
	local grid = api.grid(#items, 220, 270, 14)
	for i, it in ipairs(items) do
		local owned = it.Kind == "Title" and type(looks.titles) == "table" and looks.titles[it.Id] or (it.Kind == "Aura" and type(looks.auras) == "table" and looks.auras[it.Id])
		local color = (Config.Arcade.Colors or {})[it.Rarity] or C.Slate
		local face = K.card(grid, { Name = "Daily" .. i, LayoutOrder = i, ZIndex = 7 }, color)
		K.shine(face, 0.14).ZIndex = 8
		K.label(face, { Text = string.upper(it.Rarity) .. " " .. string.upper(it.Kind), Font = K.TITLE_FONT, TextScaled = false, TextSize = 11, TextColor3 = C.White, TextStrokeTransparency = 0, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), ZIndex = 9 })
		lookPreview(face, it.Kind, it.Id, 9)
		K.big(face, { Name = "LookName", Text = it.Id, TextScaled = false, TextSize = 24, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.new(1, -12, 0, 30), ZIndex = 9 })
		if owned then
			K.chip(face, "OWNED", C.Ink, { Name = "Owned", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), ZIndex = 9 })
		else
			local b = api.button(face, Config.format(it.Price) .. " COINS", (tonumber(d.Coins) or 0) >= it.Price and C.Green or C.Off, { Name = "Buy", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -24, 0, 48), ZIndex = 10 })
			b.Activated:Connect(function()
				api.act("DailyBuy", i)
			end)
		end
	end
end

local function dailyTick()
	if ui.dailyTime and ui.dailyTime.Parent then
		local nextDay = (Config.questDay() + 1) * 86400
		ui.dailyTime.Text = "New in " .. clock(nextDay - os.time())
	end
end

----------------------------------------------------------------------
-- PASSES
----------------------------------------------------------------------
local PASSES = {
	{ "VIP", C.Gold, "Passes", nil },
	{ "DoubleXP", C.Pink, "Bolt", "Double XP from everything, forever." },
	{ "DoubleCoins", C.Gold, "Coin", "Double coins from everything, forever." },
	{ "Luck1", C.Green, "Luck", nil },
	{ "Luck2", C.Green, "Luck", nil },
	{ "Luck3", C.Green, "Luck", nil },
	{ "InstantTen", C.Purple, "Spin", "Ten spins at once skip straight to the results." },
}
local function passesPage(page, api)
	api.section("Game passes", "bought once, yours forever")
	local list = {}
	for _, p in ipairs(PASSES) do
		local def = S.Passes[p[1]]
		if def and not (def.Random and noRandom()) then
			table.insert(list, p)
		end
	end
	local grid = api.grid(#list, 300, 230, 14)
	for i, p in ipairs(list) do
		local key = p[1]
		local def = S.Passes[key]
		local words = p[4]
		if key == "VIP" then
			words = string.format("+%d%% XP, +%d%% coins, the VIP title, +%d%% XP for friends here.", S.VIP.XP * 100, S.VIP.Coins * 100, S.VIP.FriendXP)
		elseif def.Luck then
			words = string.format("Epic and rarer are %sx as likely at the Arcade (the odds show it).", tostring(def.Luck))
		end
		local face = K.card(grid, { Name = key, LayoutOrder = i, ZIndex = 7 }, p[2])
		K.shine(face, 0.16).ZIndex = 8
		if p[3] == "Coin" then
			K.coin(face, 72, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), ZIndex = 9 })
		else
			K.icon(face, p[3], { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(72, 72), ZIndex = 9 })
		end
		K.big(face, { Name = "PassName", Text = def.Name, TextScaled = false, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -100, 0, 36), ZIndex = 9 })
		K.big(face, { Name = "Words", Text = words or "", TextScaled = false, TextSize = 18, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 70), ZIndex = 9, Edge = 2 })
		if hasPass(key) then
			K.chip(face, "OWNED", C.Ink, { Name = "Owned", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -22), ZIndex = 9 })
		else
			buyButton(api, face, key, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.fromOffset(170, 48), ZIndex = 10 }, true)
		end
	end
end

----------------------------------------------------------------------
-- LOOKS (the Bag shows this page too: Menus.pages.Looks)
----------------------------------------------------------------------
-- where a look comes from, in words
local function whereFrom(kind, id)
	for i, r in ipairs(R.Login) do
		if r[kind] == id then
			return "Login day " .. i
		end
	end
	for _, r in pairs(R.Codes) do
		if r[kind] == id then
			return "A code"
		end
	end
	for _, m in ipairs(R.Collector) do
		if m[kind] == id then
			return "Collector level " .. m.Level
		end
	end
	if R.Group[kind] == id then
		return "The community chest"
	end
	if kind == "Title" and S.VIP.Title == id then
		return "VIP"
	end
	for _, p in pairs(S.Products) do
		if p[kind] == id then
			return p.Name
		end
	end
	for _, it in ipairs(S.Daily.Pool) do
		if it.Kind == kind and it.Id == id then
			return "Daily Items"
		end
	end
	return "Coming soon"
end

local function looksPage(page, api)
	local d = api.state or {}
	local looks = type(d.Looks) == "table" and d.Looks or {}
	for _, kind in ipairs({ "Title", "Aura" }) do
		local defs = kind == "Title" and L.Titles or L.Auras
		local owned = (kind == "Title" and looks.titles or looks.auras) or {}
		local wearing = kind == "Title" and looks.title or looks.aura
		local ids = {}
		for id in pairs(defs) do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			local oa, ob = owned[a] == true, owned[b] == true
			if oa ~= ob then
				return oa
			end
			return a < b
		end)
		local have = 0
		for _, id in ipairs(ids) do
			if owned[id] then
				have = have + 1
			end
		end
		api.section(kind == "Title" and "Titles" or "Auras", have .. " / " .. #ids .. " - everyone sees the one you wear")
		local grid = api.grid(#ids, 220, 230, 14)
		for i, id in ipairs(ids) do
			local has = owned[id] == true
			local face = K.card(grid, { Name = kind .. "_" .. id, LayoutOrder = i, ZIndex = 7 }, has and C.Paper or C.Well)
			lookPreview(face, kind, id, 9)
			K.label(face, { Name = "LookName", Text = id, TextColor3 = has and C.Ink or C.Muted, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.new(1, -12, 0, 26), ZIndex = 9 })
			if has then
				local on = wearing == id
				local b = api.button(face, on and "WEARING" or "WEAR", on and C.Gold or C.Green, { Name = "Wear", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -24, 0, 46), ZIndex = 10 })
				b.Activated:Connect(function()
					api.act(kind == "Title" and "WearTitle" or "WearAura", on and "" or id)
				end)
			else
				K.icon(face, "Lock", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(30, 30), ZIndex = 10 })
				K.label(face, { Name = "From", Text = whereFrom(kind, id), TextWrapped = true, TextColor3 = C.White, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -16, 0, 44), ZIndex = 9 })
			end
		end
	end
end
Menus.pages = Menus.pages or {}
Menus.pages.Looks = looksPage

----------------------------------------------------------------------
Menus.define("Shop", {
	Title = "Shop",
	Color = C.Gold,
	Tabs = {
		{ Key = "Featured", Label = "Featured", Icon = "Featured" },
		{ Key = "Tickets", Label = "Tickets", Icon = "Tickets" },
		{ Key = "Tokens", Label = "Tokens", Icon = "Tokens" },
		{ Key = "Daily", Label = "Daily", Icon = "Daily" },
		{ Key = "Passes", Label = "Passes", Icon = "Passes" },
		{ Key = "Looks", Label = "Looks", Icon = "Looks" },
	},
	render = function(page, tab, api)
		if tab ~= "Featured" and tab ~= "Tickets" and tab ~= "Tokens" then
			giftKey = nil
		end
		if tab == "Tickets" then
			ticketsPage(page, api)
		elseif tab == "Tokens" then
			tokensPage(page, api)
		elseif tab == "Daily" then
			dailyPage(page, api)
			dailyTick()
		elseif tab == "Passes" then
			passesPage(page, api)
		elseif tab == "Looks" then
			looksPage(page, api)
		else
			featuredPage(page, api)
		end
	end,
	tick = function(_, api)
		if api.tab == "Daily" then
			dailyTick()
		end
	end,
	closed = function()
		giftKey = nil
	end,
})
