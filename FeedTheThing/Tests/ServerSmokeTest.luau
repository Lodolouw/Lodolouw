--[[
	Runs the real server scripts (DataService, GameService) on the pretend
	Roblox in MockRoblox.luau: a player joins, feeds, eggs hatch, the yard
	fills up, upgrades, the coin truck, leaving and coming back an hour
	later, and a second player. Run it with run_tests.py.
]]

local RS = mock.ReplicatedStorage
for _, n in ipairs({ "Config", "Rules" }) do
	local m = mock.newInstance("ModuleScript", n)
	m.Parent = RS
end
for _, n in ipairs({ "DataService", "GameService" }) do
	local m = mock.newInstance("ModuleScript", n)
	m.Parent = mock.ServerScriptService
end
local remotes = mock.newInstance("Folder", "Remotes")
remotes.Parent = RS
for _, n in ipairs(REMOTE_EVENTS) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local action = Instance.new("RemoteFunction")
action.Name = "Action"
action.Parent = remotes

local Config = require(RS:WaitForChild("Config"))
local Rules = require(RS:WaitForChild("Rules"))
local DataService = require(mock.ServerScriptService:WaitForChild("DataService"))
local GameService = require(mock.ServerScriptService:WaitForChild("GameService"))
local signs = {}
DataService.start()
GameService.start(DataService, { setSign = function(i, title) signs[i] = title end })

local passed, failed = 0, 0
local function check(name, ok, extra)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name, extra or "")
	end
end
local function fired(name)
	return remotes:FindFirstChild(name).fired
end
local function last(name, player)
	local list = fired(name)
	for i = #list, 1, -1 do
		if not player or list[i].player == player or list[i].all then
			return list[i].payload
		end
	end
	return nil
end
local function count(name, pred)
	local n = 0
	for _, f in ipairs(fired(name)) do
		if not pred or pred(f.payload) then
			n += 1
		end
	end
	return n
end
local function feed(p, food)
	remotes:FindFirstChild("Feed").OnServerEvent:Fire(p, food)
	mock.runQueue()
end
local function act(p, ...)
	mock.advance(0.15)
	return action.OnServerInvoke(p, ...)
end
local function decodeCount(json)
	local n = 0
	for _ in string.gmatch(json, '"id":') do
		n += 1
	end
	return n
end

-- join
local p = makePlayer(1, "Alice")
p.Parent = mock.Players
mock.Players.PlayerAdded:Fire(p)
mock.advance(0.5)
local plot = RS:FindFirstChild("Plots"):FindFirstChild("Plot1")
check("owns plot 1", plot:GetAttribute("Owner") == 1)
check("3 nests", plot:GetAttribute("Nests") == 3)
check("sign", signs[1] == "Alice's Basement", signs[1])
check("state sent", last("State", p) ~= nil)
local hatchPos = (Rules.plotCFrame(1) * CFrame.new(Config.World.Hatch)).Position
p.root.Position = hatchPos + Vector3.new(0, 0, -10)

-- feed three tomatoes, the fourth finds the nests full
for i = 1, 3 do
	feed(p, "Tomato")
	mock.advance(0.3)
	check("feed " .. i .. " ok", last("FeedResult", p).ok == true, last("FeedResult", p).reason)
end
check("3 eggs on the nests", decodeCount(plot:GetAttribute("Eggs")) == 3, plot:GetAttribute("Eggs"))
feed(p, "Tomato")
check("nests full", last("FeedResult", p).code == "nests", last("FeedResult", p).code)
mock.advance(0.3)
feed(p, "Nope")
check("bad food", last("FeedResult", p).code == "bad")
mock.advance(0.3)
local data = DataService.get(p)
check("the first egg is quick", math.abs(data.eggs[1].ready - data.eggs[1].laid - Config.Eggs.FirstEgg) < 1e-6)
check("the second egg takes the tomato's time", math.abs(data.eggs[2].ready - data.eggs[2].laid - 6) < 1e-6)
check("eggs on nests 1, 2, 3", data.eggs[1].nest == 1 and data.eggs[2].nest == 2 and data.eggs[3].nest == 3)
check("the Thing grew", data.growth == 3)

-- hatching
mock.advance(3)
check("first egg hatched", count("Hatched") >= 1, count("Hatched"))
check("first hatch is new", fired("Hatched")[1].payload.newKind == true)
mock.advance(8)
check("all three hatched", count("Hatched") == 3, count("Hatched"))
check("yard has 3", decodeCount(plot:GetAttribute("Yard")) == 3)
check("eggs gone", plot:GetAttribute("Eggs") == "[]")
check("yard records know their nest", string.find(plot:GetAttribute("Yard"), '"n":') ~= nil)
check("income now", (last("State", p).income or 0) > 0, last("State", p).income)

-- too poor for a chili
feed(p, "Chili")
check("not enough coins", last("FeedResult", p).code == "coins", last("FeedResult", p).code)

-- too far away
p.root.Position = hatchPos + Vector3.new(0, 0, -80)
mock.advance(0.3)
feed(p, "Tomato")
check("too far", last("FeedResult", p).code == "far")
p.root.Position = hatchPos + Vector3.new(0, 0, -10)

-- rich: the best food
p:SetAttribute("GiveCoins", 1e7)
mock.advance(1.2)
local before = data.coins
feed(p, "MoonMelon")
check("moon melon ok", last("FeedResult", p).ok == true)
check("paid for it", math.abs(before - data.coins - 2500000) < 1)
check("melon egg", data.eggs[#data.eggs].food == "MoonMelon" and Config.Thinglets[data.eggs[#data.eggs].kind] ~= nil)
check("the Thing grew bigger", last("FeedResult", p).grew == true and data.growth == 303)

-- upgrades
local r = act(p, "upgrade", "nests", 1)
check("buy a nest", r.ok and r.level == 1, r.msg)
check("4 nests now", plot:GetAttribute("Nests") == 4)
r = act(p, "upgrade", "luck", 1000)
check("buy max luck", r.ok and r.n >= 5, r.msg)
r = act(p, "upgrade", "yard", 2)
check("yard +2", r.ok and data.yardCap == 10, r.msg)
r = act(p, "upgrade", "nope", 1)
check("not an upgrade", not r.ok)
r = act(p, "upgrade", "nests", 1000)
check("nests to max", r.ok and data.upgrades.nests == 3, r.msg)
r = act(p, "upgrade", "nests", 1)
check("nests maxed", not r.ok)
check("6 nests", plot:GetAttribute("Nests") == 6)
check("state shows luck", (last("State", p).luck or 0) > 0)

-- lots of hatching: the yard fills, then better ones swap in, the rest sell
for round = 1, 15 do
	for _ = 1, 6 do
		feed(p, round % 3 == 0 and "Eyeberry" or "Tomato")
		mock.advance(0.25)
	end
	p:SetAttribute("HatchNow", true)
	mock.advance(1.5)
end
check("yard never over its cap", #data.yard <= data.yardCap, #data.yard)
check("yard full", #data.yard == data.yardCap, #data.yard)
check("some sold", count("Hatched", function(x) return x.how == "sell" end) > 0)
check("some replaced", count("Hatched", function(x) return x.how == "replace" end) > 0)
local slots = {}
local unique = true
for _, t in ipairs(data.yard) do
	if slots[t.slot] then unique = false end
	slots[t.slot] = true
end
check("every Thinglet has its own spot", unique)
check("no eggs left", #data.eggs == 0, #data.eggs)
check("stats", data.stats.hatches == count("Hatched"), data.stats.hatches)

-- sell one by hand
local id = data.yard[1].id
local coinsBefore = data.coins
r = act(p, "sell", id)
check("sold", r.ok and #data.yard == data.yardCap - 1 and data.coins > coinsBefore, r.msg)

-- the coin truck
mock.advance(Config.Delivery.Every + 12, 0.5)
check("a truck came", count("Fx", function(x) return x.type == "delivery" end) >= 1)
check("it paid", count("Notify", function(x) return x.type == "tip" end) >= 1)

-- leave with an egg on a nest, come back an hour later
feed(p, "Tomato")
mock.advance(0.3)
check("one egg left on the nest", #data.eggs == 1)
local coinsAtLeave = data.coins
mock.Players.PlayerRemoving:Fire(p)
p.Parent = nil
mock.runQueue()
check("plot freed", plot:GetAttribute("Owner") == 0 and plot:GetAttribute("Eggs") == "[]")
mock.advance(3600, 5)
local p2 = makePlayer(1, "Alice")
p2.Parent = mock.Players
mock.Players.PlayerAdded:Fire(p2)
mock.advance(0.5)
local welcome = last("Notify", p2)
check("welcome back", welcome and welcome.type == "welcome" and welcome.coins > 0 and welcome.eggs == 1, welcome and welcome.type)
local data2 = DataService.get(p2)
check("kept the coins", data2.coins >= coinsAtLeave)
check("kept the upgrades", data2.upgrades.nests == 3 and data2.yardCap == 10)
local hatches = count("Hatched")
mock.advance(3.5)
check("the waiting egg hatched after the welcome", count("Hatched") == hatches + 1)

-- a second player gets the next plot
local bob = makePlayer(2, "Bob")
bob.Parent = mock.Players
mock.Players.PlayerAdded:Fire(bob)
mock.advance(0.5)
check("bob on plot 2", RS:FindFirstChild("Plots"):FindFirstChild("Plot2"):GetAttribute("Owner") == 2)

print(string.format("smoke: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("smoke test failed")
end
