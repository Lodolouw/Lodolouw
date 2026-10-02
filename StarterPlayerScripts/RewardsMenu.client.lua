--[[
	RewardsMenu  (LocalScript, parent: StarterPlayerScripts)

	THE REWARDS MENU (green: rewards) and THE COMMUNITY CHEST, in the new
	see-through menus (ReplicatedStorage/Menus). What they show comes from
	your save; everything is claimed from the server (RewardService), which
	decides and pays:
	  * LOGIN: the seven-day calendar - what each day pays, the days you've
	    claimed, today's CLAIM button (miss a day and it starts again)
	  * GIFT: the free gift's clock (it only runs while you play), today's
	    count, what the next gifts are, CLAIM when it's ready
	  * CODES: type a code, REDEEM; the codes you've used
	  * UPDATES: what's new in each update, and its gift to claim. The newest
	    update opens by itself the first time you join after it comes out
	    (not for brand-new players - they've seen everything)
	  * THE COMMUNITY CHEST in the lobby (LobbyBuilder's chest, Activity =
	    "Community"): walk up to it and its window opens - join the community,
	    claim tokens and the Member title once
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if Config.NewHud == false then
	return
end
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local C = K.COLORS
local R = Config.Rewards

local player = Players.LocalPlayer
local stateAt = 0 -- os.clock() when the latest snapshot came
local typed = "" -- what's in the code box (kept when the page is drawn again)
local ui = {} -- the gift page's live pieces (its clock ticks)

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
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function rewardsOf(d)
	return d and type(d.Rewards) == "table" and d.Rewards or {}
end

-- a reward's picture: the token or coin for money, an icon for the rest
local function rewardPicture(parent, r, size, props)
	local p
	if (r.Tokens or 0) > 0 then
		p = K.token(parent, size, props)
	elseif (r.Coins or 0) > 0 then
		p = K.coin(parent, size, props)
	else
		local key = r.Boost == "Luck" and "Luck" or r.Boost and "Spin" or r.Title and "Titles" or r.Aura and "Looks" or r.Revives and "Revive" or "Gift"
		p = K.icon(parent, key, props)
		p.Size = UDim2.fromOffset(size, size)
	end
	return p
end

-- which login days are done, and which one is next (see RewardService.claimLogin)
local function loginState(rw)
	local today = Config.questDay()
	local s, sd = tonumber(rw.streak) or 0, tonumber(rw.streakDay) or 0
	local claimedToday = sd == today
	if claimedToday then
		return s, s % #R.Login + 1, true
	elseif sd == today - 1 and s < #R.Login then
		return s, s + 1, false
	end
	return 0, 1, false
end

----------------------------------------------------------------------
-- the pages
----------------------------------------------------------------------
local function loginPage(page, api)
	local rw = rewardsOf(api.state)
	local done, nextDay, claimedToday = loginState(rw)
	api.section("Log in every day", claimedToday and "Come back tomorrow!" or "Today's reward is ready!")
	api.words("A new reward every day for 7 days. Miss a day and it starts again at day 1 - day 7 is the big one.", 30)
	local w = math.floor((api.width - 6 * 12) / 7)
	local grid = api.grid(#R.Login, math.max(110, w), 230, 12)
	for i, r in ipairs(R.Login) do
		local isNext = i == nextDay and not claimedToday
		local claimed = i <= done
		local color = claimed and C.Green or (isNext and C.Gold or (i == #R.Login and C.Purple or C.Paper))
		local face = K.card(grid, { Name = "Day" .. i, LayoutOrder = i, ZIndex = 7 }, color)
		local dark = color == C.Paper
		local txt = dark and C.Ink or C.White
		K.label(face, { Name = "Day", Text = "DAY " .. i, Font = K.TITLE_FONT, TextScaled = false, TextSize = 16, TextColor3 = txt, TextStrokeTransparency = dark and 1 or 0, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 20), ZIndex = 9 })
		rewardPicture(face, r, 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), ZIndex = 9 })
		K.label(face, { Name = "Reward", Text = Config.rewardText(r), TextColor3 = txt, TextStrokeTransparency = dark and 1 or 0.4, TextWrapped = true, Position = UDim2.fromOffset(8, 116), Size = UDim2.new(1, -16, 0, 50), ZIndex = 9 })
		if claimed then
			K.chip(face, "CLAIMED", C.Ink, { Name = "Claimed", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), ZIndex = 9 })
		elseif isNext then
			local b = api.button(face, "CLAIM", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -24, 0, 44), ZIndex = 10 })
			b.Activated:Connect(function()
				api.act("RewardLogin")
			end)
		elseif i == nextDay then
			K.chip(face, "TOMORROW", C.Blue, { Name = "Tomorrow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), ZIndex = 9 })
		end
	end
	api.words(claimedToday and ("Your streak: " .. done .. (done == 1 and " day" or " days") .. ". Day " .. nextDay .. " is tomorrow.") or ("Your streak: " .. done .. (done == 1 and " day" or " days") .. "."), 30, C.Yellow)
end

local function giftPage(page, api)
	local rw = rewardsOf(api.state)
	api.section("Free gift", "It fills up while you play")
	local block = api.block(300)
	local face = K.card(block, { Name = "GiftCard", Size = UDim2.fromOffset(math.min(560, api.width), 280), ZIndex = 7 }, C.Gold)
	K.shine(face, 0.15).ZIndex = 8
	K.icon(face, "Gift", { Position = UDim2.fromOffset(20, 24), Size = UDim2.fromOffset(130, 130), ZIndex = 9 })
	K.big(face, { Name = "Heading", Text = "FREE GIFT", TextScaled = false, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(170, 20), Size = UDim2.new(1, -190, 0, 44), ZIndex = 9 })
	ui.giftTime = K.big(face, { Name = "Time", Text = "", TextScaled = false, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(170, 66), Size = UDim2.new(1, -190, 0, 60), ZIndex = 9 })
	ui.giftMeter = K.meter(face, { Name = "Meter", Color = C.Green, Position = UDim2.fromOffset(20, 176), Size = UDim2.new(1, -40, 0, 28), ZIndex = 9 })
	ui.giftClaim = api.button(face, "CLAIM", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -18), Size = UDim2.fromOffset(170, 50), ZIndex = 10 })
	ui.giftClaim.Activated:Connect(function()
		if ui.giftReady then
			api.act("RewardGift")
		end
	end)
	ui.giftCount = K.big(face, { Name = "Count", Text = "", TextScaled = false, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -26), Size = UDim2.new(1, -220, 0, 30), ZIndex = 9, Edge = 2 })
	-- what the next gifts are (they go round in turn)
	api.section("Coming up")
	local grid = api.grid(#R.Gifts, 200, 150, 12)
	local nextIndex = (tonumber(rw.gifts) or 0) % #R.Gifts + 1
	for i = 0, #R.Gifts - 1 do
		local idx = (nextIndex - 1 + i) % #R.Gifts + 1
		local r = R.Gifts[idx]
		local f = K.card(grid, { Name = "Gift" .. (i + 1), LayoutOrder = i + 1, ZIndex = 7 }, i == 0 and C.Gold or C.Paper)
		rewardPicture(f, r, 54, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), ZIndex = 9 })
		K.label(f, { Name = "Reward", Text = Config.rewardText(r), TextWrapped = true, TextColor3 = i == 0 and C.White or C.Ink, TextStrokeTransparency = i == 0 and 0.4 or 1, Position = UDim2.fromOffset(8, 76), Size = UDim2.new(1, -16, 0, 34), ZIndex = 9 })
		K.chip(f, i == 0 and "NEXT" or ("THEN " .. (i + 1)), i == 0 and C.Green or C.Slate, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), ZIndex = 9 })
	end
end

local function giftTick(api)
	if not ui.giftTime or not ui.giftTime.Parent then
		return
	end
	local rw = rewardsOf(Menus.state)
	local need = R.GiftMinutes * 60
	local capped = (tonumber(rw.giftsToday) or 0) >= R.GiftsPerDay and (tonumber(rw.giftPlay) or 0) < need
	local played = math.min(need, (tonumber(rw.giftPlay) or 0) + (capped and 0 or os.clock() - stateAt))
	ui.giftReady = not capped and played >= need
	ui.giftTime.Text = capped and "Tomorrow!" or (ui.giftReady and "READY!" or clock(need - played))
	ui.giftMeter:set(played / need, capped and "ALL GIFTS OPENED TODAY" or (math.floor(played / 60) .. " / " .. R.GiftMinutes .. " MIN"))
	ui.giftClaim.BackgroundColor3 = ui.giftReady and C.Green or C.Off
	ui.giftCount.Text = "Gifts today: " .. (tonumber(rw.giftsToday) or 0) .. " / " .. R.GiftsPerDay
end

local function codesPage(page, api)
	local rw = rewardsOf(api.state)
	api.section("Codes", "New ones come with updates")
	local block = api.block(170)
	local face = K.card(block, { Name = "CodeCard", Size = UDim2.fromOffset(math.min(640, api.width), 150), ZIndex = 7 })
	K.label(face, { Text = "ENTER A CODE", Font = K.TITLE_FONT, TextScaled = false, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 20), ZIndex = 9 })
	local box = new("TextBox", {
		Name = "Code",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = K.FONT,
		PlaceholderText = "Type a code...",
		PlaceholderColor3 = C.Muted,
		Text = typed,
		TextColor3 = C.Ink,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -230, 0, 60),
		ZIndex = 9,
	}, face)
	K.outline(box, C.Ink, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14) }, box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		typed = box.Text
	end)
	local redeem = api.button(face, "REDEEM", C.Green, { Name = "Redeem", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 50), Size = UDim2.fromOffset(170, 60), ZIndex = 10 })
	local function send()
		local code = typed
		if code == "" then
			api.toast("Type a code first.", "bad")
			return
		end
		api.act("RewardCode", code, function(ok)
			if ok then
				typed = ""
				box.Text = ""
			end
		end)
	end
	redeem.Activated:Connect(send)
	box.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)
	local used = {}
	for code in pairs(type(rw.codes) == "table" and rw.codes or {}) do
		table.insert(used, code)
	end
	table.sort(used)
	api.words(#used > 0 and ("Codes you've used: " .. table.concat(used, ", ")) or "Find codes in our community and on update days.", 30)
end

local function updatesPage(page, api)
	local rw = rewardsOf(api.state)
	local claimed = type(rw.updates) == "table" and rw.updates or {}
	api.section("What's new")
	for i, u in ipairs(R.Updates) do
		local notes = u.Notes or {}
		local h = 110 + #notes * 30
		local block = api.block(h + 10)
		local face = K.card(block, { Name = "Update" .. u.Id, Size = UDim2.fromOffset(math.min(820, api.width), h), ZIndex = 7 })
		local bar = new("Frame", { Name = "Bar", BackgroundColor3 = C.Green, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), ZIndex = 8 }, face)
		new("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = 8 }, bar)
		K.icon(bar, "Updates", { Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(36, 36), ZIndex = 9 })
		K.big(bar, { Name = "Title", Text = "UPDATE " .. u.Id .. ": " .. string.upper(u.Title or ""), TextScaled = false, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -160, 1, 0), ZIndex = 9 })
		if i == 1 then
			K.chip(bar, "NEW", C.Pink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = 9 })
		end
		for j, line in ipairs(notes) do
			K.label(face, { Name = "Note", Text = "•  " .. line, TextScaled = false, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(20, 52 + (j - 1) * 30), Size = UDim2.new(1, -250, 0, 28), ZIndex = 9 })
		end
		if u.Gift then
			K.label(face, { Name = "GiftText", Text = "Gift: " .. Config.rewardText(u.Gift), TextScaled = false, TextSize = 20, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -12), Size = UDim2.new(1, -250, 0, 26), ZIndex = 9 })
			if claimed[u.Id] then
				K.chip(face, "CLAIMED", C.Ink, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), ZIndex = 9 })
			else
				local b = api.button(face, "CLAIM GIFT", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -14), Size = UDim2.fromOffset(190, 50), ZIndex = 10 })
				b.Activated:Connect(function()
					api.act("RewardUpdate", u.Id)
				end)
			end
		end
	end
end

Menus.define("Rewards", {
	Title = "Rewards",
	Color = C.Green,
	Tabs = {
		{ Key = "Login", Label = "Login", Icon = "Daily" },
		{ Key = "Gift", Label = "Gift", Icon = "Gift" },
		{ Key = "Codes", Label = "Codes", Icon = "Codes" },
		{ Key = "Updates", Label = "Updates", Icon = "Updates" },
	},
	render = function(page, tab, api)
		if tab == "Gift" then
			giftPage(page, api)
			giftTick(api)
		elseif tab == "Codes" then
			codesPage(page, api)
		elseif tab == "Updates" then
			updatesPage(page, api)
		else
			loginPage(page, api)
		end
	end,
	tick = function(_, api)
		if api.tab == "Gift" then
			giftTick(api)
		end
	end,
})

----------------------------------------------------------------------
-- THE COMMUNITY CHEST: its window, opened by walking up to it
----------------------------------------------------------------------
local function chestPage(page, api)
	local rw = rewardsOf(api.state)
	local G = R.Group or {}
	api.section("Join the community", rw.group and "Claimed - thanks for joining!" or "A free reward for members")
	local W = api.width
	-- the big card: the chest bursting with treasure, what's in it, CLAIM
	local block = api.block(262)
	local face = K.card(block, { Name = "ChestCard", Size = UDim2.fromOffset(W, 250), ZIndex = 7 }, C.Pink)
	K.shine(face, 0.15).ZIndex = 8
	local art = new("Frame", { Name = "Art", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(220, 222), ZIndex = 9 }, face)
	-- a gold glow behind it, and rays
	local glow = new("Frame", { Name = "Glow", BackgroundColor3 = C.Yellow, BackgroundTransparency = 0.35, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(110, 104), Size = UDim2.fromOffset(190, 190), ZIndex = 9 }, art)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	for k, a in ipairs({ -38, -14, 12, 36 }) do
		new("Frame", { Name = "Ray", BackgroundColor3 = C.White, BackgroundTransparency = 0.45 + k * 0.05, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(110, 112), Size = UDim2.fromOffset(16, 104), Rotation = a, ZIndex = 9 }, art)
	end
	local WOOD, WOOD_D, GOLD = Color3.fromRGB(176, 96, 58), Color3.fromRGB(115, 62, 57), Color3.fromRGB(255, 196, 56)
	local function box(name, color, x, y, w, h, z, rot)
		local f = new("Frame", { Name = name, BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0, ZIndex = z }, art)
		K.outline(f, C.Ink, 4)
		return f
	end
	-- the lid, flung open behind
	local lid = box("Lid", WOOD, 44, 48, 132, 46, 10, -14)
	new("Frame", { BackgroundColor3 = WOOD_D, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0.5, -3), Size = UDim2.new(1, 0, 0, 6), ZIndex = 11 }, lid)
	for _, x in ipairs({ 0.12, 0.88 }) do
		new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(0, 14, 1, 0), ZIndex = 11 }, lid)
	end
	-- treasure heaped over the rim: tokens and a gem
	for k, t in ipairs({ { 52, 84, 46 }, { 92, 70, 54 }, { 138, 82, 46 }, { 74, 96, 40 }, { 120, 98, 40 } }) do
		K.token(art, t[3], { Name = "Treasure" .. k, Position = UDim2.fromOffset(t[1], t[2]), ZIndex = 12 })
	end
	-- the chest
	local body = box("Chest", WOOD, 36, 118, 148, 86, 13)
	new("Frame", { BackgroundColor3 = WOOD_D, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0.45, 0), Size = UDim2.new(1, 0, 0, 6), ZIndex = 14 }, body)
	new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 12), ZIndex = 14 }, body)
	for _, x in ipairs({ 0.1, 0.9 }) do
		new("Frame", { BackgroundColor3 = GOLD, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(0, 14, 1, 0), ZIndex = 14 }, body)
	end
	local lock = new("Frame", { Name = "Lock", BackgroundColor3 = GOLD, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(28, 34), ZIndex = 15 }, body)
	K.outline(lock, C.Ink, 3)
	new("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(6, 12), ZIndex = 16 }, lock)
	for k, sp in ipairs({ { 18, 30, 26 }, { 186, 44, 22 }, { 196, 150, 18 }, { 8, 150, 16 } }) do
		K.label(art, { Name = "Sparkle" .. k, Text = "+", Font = K.TITLE_FONT, TextScaled = false, TextSize = sp[3], TextColor3 = C.White, Position = UDim2.fromOffset(sp[1], sp[2]), Size = UDim2.fromOffset(sp[3], sp[3]), ZIndex = 16 })
	end
	-- what's in it
	local right = 250
	K.big(face, { Name = "Heading", Text = rw.group and "THANKS FOR JOINING!" or "FREE FOR MEMBERS", TextScaled = false, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(right, 18), Size = UDim2.new(1, -right - 20, 0, 38), ZIndex = 9 })
	local prizes = {}
	if (G.Tokens or 0) > 0 then
		table.insert(prizes, { "Tokens", "+" .. G.Tokens .. " TOKENS" })
	end
	if G.Title then
		table.insert(prizes, { "Titles", '"' .. G.Title .. '" TITLE' })
	end
	local tileW = math.min(210, math.floor((W - right - 20 - 12 * (#prizes - 1)) / math.max(1, #prizes)))
	for k, pz in ipairs(prizes) do
		local tile = K.card(face, { Name = "Prize" .. k, Position = UDim2.fromOffset(right + (k - 1) * (tileW + 12), 64), Size = UDim2.fromOffset(tileW, 112), ZIndex = 9 }, C.Paper)
		if pz[1] == "Tokens" then
			K.token(tile, 54, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), ZIndex = 11 })
		else
			K.icon(tile, pz[1], { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(54, 54), ZIndex = 11 })
		end
		K.label(tile, { Name = "Text", Text = pz[2], TextColor3 = C.Ink, TextStrokeTransparency = 1, TextScaled = false, TextSize = 18, TextWrapped = true, Position = UDim2.fromOffset(6, 70), Size = UDim2.new(1, -12, 0, 34), ZIndex = 11 })
		if rw.group then
			K.chip(tile, "GOT IT", C.Green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), ZIndex = 12 })
		end
	end
	if rw.group then
		K.chip(face, "CLAIMED", C.Ink, { Name = "Claimed", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -22), ZIndex = 9 })
	else
		local b = api.button(face, "CLAIM", C.Green, { Name = "Claim", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(200, 54), ZIndex = 10 })
		b.Activated:Connect(function()
			api.act("GroupClaim")
		end)
		K.label(face, { Name = "Once", Text = "Once per player", TextColor3 = C.White, TextScaled = false, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, right, 1, -30), Size = UDim2.fromOffset(200, 20), ZIndex = 9 })
	end
	-- how: three steps
	if not rw.group then
		api.section("How to get it")
		local w = math.floor((W - 2 * 12) / 3)
		local grid = api.grid(3, w, 128, 12)
		for k, st in ipairs({
			{ "Updates", "Open the game's page" },
			{ "Friends", "Tap the community's name, then JOIN" },
			{ "Gift", "Come back here and press CLAIM" },
		}) do
			local tile = K.card(grid, { Name = "Step" .. k, LayoutOrder = k, ZIndex = 7 }, C.Paper)
			local n = new("Frame", { Name = "Number", BackgroundColor3 = C.Pink, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(36, 36), ZIndex = 9 }, tile)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, n)
			K.outline(n, C.Ink, 3)
			K.label(n, { Text = tostring(k), Font = K.TITLE_FONT, TextScaled = false, TextSize = 18, TextColor3 = C.White, Size = UDim2.fromScale(1, 1), ZIndex = 10 })
			K.icon(tile, st[1], { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(48, 48), ZIndex = 9 })
			K.label(tile, { Name = "Text", Text = st[2], TextColor3 = C.Ink, TextStrokeTransparency = 1, TextScaled = false, TextSize = 19, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 0, 56), ZIndex = 9 })
		end
	end
end
Menus.define("Community", {
	Title = "Community Chest",
	Color = C.Pink,
	Tabs = { { Key = "Chest", Label = "Chest", Icon = "Friends" } },
	render = function(page, _, api)
		chestPage(page, api)
	end,
})

-- walking up to the chest opens it; walking away closes it (if it opened
-- itself). Closed by hand while standing there: it stays closed until you
-- step away and come back.
do
	local autoOpened, dismissed = false, false
	local acc = 0
	local function inside(zone, pos, margin)
		local rel = zone.CFrame:PointToObjectSpace(pos)
		local half = zone.Size / 2
		return math.abs(rel.X) <= half.X + margin and math.abs(rel.Y) <= half.Y + margin and math.abs(rel.Z) <= half.Z + margin
	end
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.15 then
			return
		end
		acc = 0
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local here = false
		for _, z in ipairs(CollectionService:GetTagged("AutoOpenZone")) do
			if z:IsA("BasePart") and z:GetAttribute("Activity") == "Community" and inside(z, hrp.Position, autoOpened and 2 or 0) then
				here = true
				break
			end
		end
		local current = Menus.current()
		if here then
			if autoOpened and current ~= "Community" then
				autoOpened, dismissed = false, true -- (closed by hand)
			elseif not autoOpened and not dismissed and current == nil then
				autoOpened = Menus.open("Community")
			end
		else
			if autoOpened and current == "Community" then
				Menus.close()
			end
			autoOpened, dismissed = false, false
		end
	end)
end

-- the chest's lid swings open as you walk up (the gold light inside, the
-- rays rising out, a burst of sparkles) and falls shut as you walk away -
-- only on your screen (RewardService builds it shut, the hinge saved on it)
do
	local OPEN_AT, SHUT_AT = 16, 19 -- studs from the chest
	local WIDE = math.rad(-75) -- how far it swings back
	local chest, lid, hinge, pieces, rays, sparkle
	local angle, wasOpen = 0, false
	local function find()
		chest = workspace:FindFirstChild("CommunityChest")
		lid = chest and chest:FindFirstChild("Lid")
		hinge = lid and lid:GetAttribute("Hinge")
		if typeof(hinge) ~= "CFrame" then
			chest = nil
			return
		end
		pieces, rays = {}, {}
		for _, p in ipairs(lid:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(pieces, { p, hinge:ToObjectSpace(p.CFrame) })
			end
		end
		for _, p in ipairs(chest:GetChildren()) do
			if p.Name == "Ray" and p:IsA("BasePart") then
				table.insert(rays, { p, p:GetAttribute("Shine") or 0.78 })
			end
		end
		local glow = chest:FindFirstChild("Glow")
		sparkle = glow and glow:FindFirstChild("Sparkle")
		angle, wasOpen = 0, false
	end
	local look = 0
	RunService.Heartbeat:Connect(function(dt)
		if not (chest and chest.Parent and lid.Parent) then
			look -= dt
			if look > 0 then
				return
			end
			look = 1
			find()
			if not chest then
				return
			end
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local far = hrp and (hrp.Position - hinge.Position).Magnitude or math.huge
		local open = far < (wasOpen and SHUT_AT or OPEN_AT)
		if open and not wasOpen and sparkle then
			sparkle:Emit(24)
		end
		wasOpen = open
		-- quick to fly open, a little slower to fall shut
		local want = open and WIDE or 0
		local speed = open and 7 or 5
		local before = angle
		angle += (want - angle) * math.min(1, dt * speed)
		if math.abs(angle - before) < 1e-4 and math.abs(want - angle) < 1e-3 then
			return
		end
		local turned = hinge * CFrame.Angles(-angle, 0, 0)
		for _, piece in ipairs(pieces) do
			piece[1].CFrame = turned * piece[2]
		end
		local shown = angle / WIDE
		for _, r in ipairs(rays) do
			r[1].Transparency = 1 - (1 - r[2]) * shown
		end
	end)
end

----------------------------------------------------------------------
-- keeping up with your save; the newest update opens by itself once
----------------------------------------------------------------------
local shownUpdate = false
Menus.onState(function(d)
	stateAt = os.clock()
	local newest = R.Updates[1]
	local rw = rewardsOf(d)
	if shownUpdate or not newest or rw.seen == newest.Id or (type(rw.updates) == "table" and rw.updates[newest.Id]) then
		return
	end
	shownUpdate = true
	-- (a brand-new player has seen everything: just mark it)
	local cleared = type(d.Cleared) == "table" and next(d.Cleared) ~= nil
	if (tonumber(d.QuestsDone) or 0) == 0 and not cleared then
		Menus.act("RewardSeen", newest.Id)
		return
	end
	task.spawn(function()
		-- (wait for a quiet moment in the lobby)
		for _ = 1, 120 do
			task.wait(1)
			local busy = player:GetAttribute("Intro") ~= nil or player:GetAttribute("SpireFloor") ~= nil or player:GetAttribute("Colosseum") == true
			if not busy and Menus.current() == nil then
				task.wait(2)
				if Menus.current() == nil then
					Menus.open("Rewards", "Updates")
					Menus.act("RewardSeen", newest.Id)
				end
				return
			end
		end
	end)
end)
