--!nocheck
-- Headless test of THE SHOP (ShopMenu.client.lua) in the see-through menus
-- (ReplicatedStorage/Menus), with a pretend server and a friend in the server:
--   * FEATURED: the Arcade banner (OPEN ARCADE), the Starter Pack (SOON while
--     it has no id, BUY once it has; gone once bought), VIP, quick tickets
--   * a product without its id yet says SOON and asks nothing; with one, BUY
--     asks ShopBuy / ShopPass for it
--   * GIFTS: the gift button, the picker (your friend), GIFT asks ShopBuy
--     with them; CANCEL
--   * TOKENS: the packs with how much more each really gives (worked out from
--     the prices); where paid random items aren't allowed: no packs, no Spin x3,
--     no luck passes - just the free ways to earn tokens
--   * DAILY: five looks for coins, BUY (DailyBuy), OWNED, the clock
--   * PASSES: SOON / BUY / OWNED
--   * LOOKS: WEAR (WearTitle / WearAura), WEARING takes it off, and where to
--     get the ones you don't have
--   luau test_shop_menu.luau -a snaps    ...also prints snapshots for render_gui.py
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Enum, CFrame = M.Instance, M.Enum, M.CFrame
local Players, RunService, ReplicatedStorage = M.services.Players, M.services.RunService, M.services.ReplicatedStorage
local SNAPS = ({ ... })[1] == "snaps"
local snapGui = SNAPS and require("./gui_snap") or nil

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

RunService.IsStudio = function()
	return true
end
RunService.IsClient = function()
	return true
end
M.services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
}
local function newPlayer(name, id)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	p.Parent = Players
	table.insert(M.players, p)
	return p
end
M.players = {}
local me = newPlayer("Tester", 1001)
local friend = newPlayer("Buddy", 1002)
Players.LocalPlayer = me
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = me
local char = Instance.new("Model")
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.Parent = char
char.Parent = M.workspace
me.Character = char
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "StateUpdate", "RequestState", "Notify" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes
local asked = {}
M.onInvokeServer = function(_, name, arg)
	local a = arg
	if type(arg) == "table" then
		a = tostring(arg.key) .. ">" .. tostring(arg.gift)
	end
	table.insert(asked, tostring(name) .. (a ~= nil and (":" .. tostring(a)) or ""))
	return true, nil
end
local function askedFor(s)
	return table.find(asked, s) ~= nil
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local Shop = Config.Shop
if SNAPS then
	local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
	AssetIds.Icons = AssetIds.Icons or {}
	local id = 9100000
	for _, key in ipairs({ "Shop", "Bag", "Arcade", "Index", "Gift", "Rewards", "Settings", "Featured", "Tickets", "Tokens", "Daily", "Passes", "Looks", "Weapons", "Titles", "Bosses", "Goals", "Revive", "Spin", "BossRush", "Luck", "Playtime", "Friends", "Spire", "Lock", "Codes", "Updates", "Flask", "Bolt", "Stats", "Gear" }) do
		id += 1
		AssetIds.Icons["UI_" .. key] = id
	end
	for key, aid in pairs(AssetIds.Icons) do
		print("ICONMAP " .. tostring(aid) .. " " .. key)
	end
end
local Menus = mount.require(mount.module("ReplicatedStorage/Menus.lua"))
local arcadeOpened = 0
Menus.external.Arcade = function()
	arcadeOpened += 1
end
mount.runClient("StarterPlayerScripts/ShopMenu.client.lua", me)
M.run(1)

local T = 1
local function wait(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += 1 / 20
		M.run(T)
		RunService.Heartbeat:Fire(1 / 20)
	end
end
local function snapshot(over)
	local d = {
		Power = 5000, Coins = 4000, Tokens = 8, Cleared = { ["1"] = 1 },
		Weapons = { own = {} }, Quests = { day = 0, list = {} }, Rewards = {},
		Tickets = { Revive = 2, Rush = 1 }, Boosts = { XP = 0, Coins = 0, Luck = 0 },
		Shop = { starter = false, receipts = {}, daily = {} },
		Looks = { titles = { Loyal = true, VIP = true }, auras = { Gold = true }, title = "Loyal" },
	}
	for k, v in pairs(over or {}) do
		d[k] = v
	end
	return d
end
local function send(d)
	remotes.StateUpdate.OnClientEvent:Fire(d)
	wait(0.3)
end
local function page()
	local g = playerGui:FindFirstChild("Menus")
	return g and g.Root:FindFirstChild("Page")
end
local function find(name, root)
	return (root or page()):FindFirstChild(name, true)
end
local function tab(name)
	find("Tab_" .. name, playerGui.Menus.Root).Activated:Fire()
	wait(0.2)
end
local function click(b)
	check(b ~= nil, "a button to press")
	if b then
		b.Activated:Fire()
		wait(0.2)
	end
end
local function snap(caption)
	if SNAPS then
		snapGui(playerGui:FindFirstChild("Menus"), caption, 1280, 720)
	end
end

----------------------------------------------------------------------
-- FEATURED: nothing has an id yet
----------------------------------------------------------------------
send(snapshot())
check(Menus.open("Shop"), "the shop opens")
check(find("ArcadeBanner") ~= nil, "the Arcade banner")
click(find("OpenArcade"))
check(arcadeOpened == 1, "OPEN ARCADE opens the Arcade")
Menus.open("Shop")
local starter = find("Starter")
check(starter ~= nil, "the Starter Pack")
check(find("Soon", starter) ~= nil and find("Buy", starter) == nil, "no id yet: SOON")
asked = {}
click(find("Soon", starter))
check(#asked == 0, "SOON asks the server nothing")
check(find("VIP") ~= nil, "VIP")
check(find("Revive3") and find("Rush3") and find("Spin3"), "the tickets as quick buys")
check(find("Gift", find("Revive3")) == nil, "no gift button while it can't be bought")
snap("SHOP · FEATURED|the Arcade, the Starter Pack, VIP, quick tickets")

----------------------------------------------------------------------
-- the products get their ids: BUY and GIFT
----------------------------------------------------------------------
for key, id in pairs({ Starter = 501, Revive3 = 502, Tokens10 = 503, Tokens25 = 504, Tokens60 = 505, Tokens150 = 506, Spin3 = 507, Rush3 = 508, Boost30 = 509 }) do
	Shop.Products[key].ProductId = id
end
Shop.Passes.VIP.PassId = 601
Shop.Passes.Luck2.PassId = 602
Menus.redraw()
wait(0.1)
asked = {}
click(find("Buy", find("Starter")))
check(askedFor("ShopBuy:Starter"), "BUY asks for the Starter Pack")
click(find("Buy", find("VIP")))
check(askedFor("ShopPass:VIP"), "BUY asks for VIP")
click(find("Gift", find("Revive3")))
check(find("To_" .. friend.UserId) ~= nil, "the gift picker shows your friend")
snap("SHOP · GIFTING|pick someone in the server")
click(find("GiftTo", find("To_" .. friend.UserId)))
check(askedFor("ShopBuy:Revive3>" .. friend.UserId), "GIFT buys it for them")
check(find("To_" .. friend.UserId) == nil, "and the picker goes")
click(find("Gift", find("Rush3")))
click(find("Cancel"))
check(find("To_" .. friend.UserId) == nil, "CANCEL closes the picker")
send(snapshot({ Shop = { starter = true, receipts = {}, daily = {} } }))
check(find("Starter") == nil, "once bought, the Starter Pack is gone")

----------------------------------------------------------------------
-- TOKENS
----------------------------------------------------------------------
tab("Tokens")
for _, key in ipairs({ "Tokens10", "Tokens25", "Tokens60", "Tokens150" }) do
	check(find(key) ~= nil, key .. "'s card")
end
check(find("More", find("Tokens10")) == nil, "the smallest pack has no 'more'")
local function more(key)
	local p, b = Shop.Products[key], Shop.Products.Tokens10
	return math.floor((p.Tokens / p.Price) / (b.Tokens / b.Price) * 100 - 100 + 0.5)
end
check(find("More", find("Tokens60")).Text == "+" .. more("Tokens60") .. "% MORE", "the Sack: how much more it really gives (" .. find("More", find("Tokens60")).Text .. ")")
check(find("More", find("Tokens150")).Text == "+" .. more("Tokens150") .. "% MORE", "the Treasure Chest too")
asked = {}
click(find("Buy", find("Tokens25")))
check(askedFor("ShopBuy:Tokens25"), "BUY asks for the pack")
snap("SHOP · TOKENS|the packs (what they really give), and the free ways")

-- where paid random items aren't allowed
me:SetAttribute("NoPaidRandom", true)
wait(0.2)
check(find("Tokens10") == nil, "no token packs where paid random items aren't allowed")
local freeWays = false
for _, d in ipairs(page():GetDescendants()) do
	freeWays = freeWays or (d.Name == "Words" and string.find(d.Text, "earned by playing") ~= nil)
end
check(freeWays, "it says every token can be earned by playing")
tab("Featured")
check(find("Spin3") == nil and find("Revive3") ~= nil, "no Spin x3 there (tickets are fine)")
tab("Passes")
check(find("Luck2") == nil and find("DoubleXP") ~= nil, "no luck passes there")
me:SetAttribute("NoPaidRandom", nil)
wait(0.2)

----------------------------------------------------------------------
-- PASSES
----------------------------------------------------------------------
check(find("Luck2") ~= nil, "the luck passes are back")
check(find("Soon", find("DoubleXP")) ~= nil, "a pass without its id: SOON")
asked = {}
click(find("Buy", find("Luck2")))
check(askedFor("ShopPass:Luck2"), "BUY asks for the pass")
me:SetAttribute("Pass_Luck2", true)
wait(0.2)
check(find("Owned", find("Luck2")) ~= nil, "a pass you have: OWNED")
snap("SHOP · PASSES|SOON, BUY, OWNED")

----------------------------------------------------------------------
-- DAILY
----------------------------------------------------------------------
tab("Daily")
local items = Config.dailyItems(Config.questDay(1700000000 + math.floor(M.now())))
for i = 1, #items do
	check(find("Daily" .. i) ~= nil, "daily item " .. i)
end
local heading = find("Section")
check(heading and string.find(find("Sub", heading).Text, "New in") ~= nil, "when the next ones come (" .. tostring(find("Sub", heading).Text) .. ")")
asked = {}
click(find("Buy", find("Daily1")))
check(askedFor("DailyBuy:1"), "BUY asks for it")
local it = items[1]
local owned = { titles = { Loyal = true }, auras = {} }
if it.Kind == "Title" then
	owned.titles[it.Id] = true
else
	owned.auras[it.Id] = true
end
send(snapshot({ Looks = owned }))
check(find("Owned", find("Daily1")) ~= nil, "one you have: OWNED")
snap("SHOP · DAILY ITEMS|five looks for coins, new every day")

----------------------------------------------------------------------
-- LOOKS
----------------------------------------------------------------------
send(snapshot())
tab("Looks")
local loyal = find("Title_Loyal")
check(loyal and find("Wear", loyal).Text == "WEARING", "the title you wear says WEARING")
asked = {}
click(find("Wear", loyal))
check(askedFor("WearTitle:"), "pressing it takes it off")
click(find("Wear", find("Title_VIP")))
check(askedFor("WearTitle:VIP"), "WEAR puts another on")
click(find("Wear", find("Aura_Gold")))
check(askedFor("WearAura:Gold"), "and an aura")
local hoarder = find("Title_Hoarder")
check(hoarder and find("From", hoarder) and string.find(find("From", hoarder).Text, "Collector") ~= nil, "a locked one says where it comes from (" .. tostring(hoarder and find("From", hoarder) and find("From", hoarder).Text) .. ")")
check(Menus.pages and Menus.pages.Looks ~= nil, "the Bag can show this page too")
snap("SHOP · LOOKS|wear titles and auras; where to get the rest")

----------------------------------------------------------------------
-- TICKETS
----------------------------------------------------------------------
tab("Tickets")
check(find("Boost30") ~= nil, "the XP boost is here")
check(string.find(find("Sub", find("Section")).Text, "2 revives") ~= nil, "how many tickets you have")
Menus.close()

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings")
if fails == 0 then
	print("PASS  test_shop_menu: featured, buying, gifts, tokens, no paid random items, passes, daily items, looks")
else
	print("FAILED: " .. fails)
end
