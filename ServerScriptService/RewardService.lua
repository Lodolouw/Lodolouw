--[[
	RewardService  (ModuleScript, parent: ServerScriptService, name: "RewardService")

	THE NEW GUI's REWARDS, decided and paid here (the screens only ask):
	  * the LOGIN STREAK - one claim a day, seven days round (Config.Rewards.Login)
	  * the FREE GIFT - ready after every GiftMinutes of play (a clock that only
	    runs while you're in the game, and stops after GiftsPerDay gifts)
	  * CODES and UPDATE GIFTS (Config.Rewards.Codes / Updates)
	  * THE INDEX - each weapon pays once when you first own it, and every
	    find and first boss win fills the COLLECTOR bar, whose levels pay out
	  * the COMMUNITY CHEST (join the group, claim once)
	  * the CORNER BONUSES on XP: time in this server, friends in it with you
	  * LOOKS: the title over your head and the aura round you (anyone can
	    see them), which title/aura you wear, and your SETTINGS
	  * TIMED BOOSTS (2x XP, 2x Coins, Luck) ticking down while you play

	Actions (the Action remote, PlayerService.AddAction):
	  RewardLogin, RewardGift, RewardCode (code), RewardUpdate (update id),
	  RewardSeen (update id), IndexClaim (weapon id), CollectorClaim (level),
	  GroupClaim, WearTitle (id or ""), WearAura (id or ""), SaveSettings (table)

	Player attributes it keeps up to date (the lobby's corner icons read them):
	  PlayBonus (% XP for time in this server), FriendBonus (% XP for friends)

	  RewardService.Pay(player, reward, why)   pay a reward table (Config.Rewards)
	  RewardService.CollectorPoints(data)      the collector bar's points
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local RewardService = {}
local PlayerService = nil
local R = Config.Rewards
local joined = {} -- [player] = os.clock() when they arrived
local friendsOf = {} -- [player] = { [userId] = true } (their friends in this server)

----------------------------------------------------------------------
-- paying
----------------------------------------------------------------------
local function notify(player, text, kind)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ev = remotes and remotes:FindFirstChild("Notify")
	if ev then
		ev:FireClient(player, text, kind or "good")
	end
end

-- pays reward table `r` into data `d` (no bonuses: a reward is what it says)
local function payInto(d, r)
	d.Coins = (d.Coins or 0) + math.max(0, math.floor(r.Coins or 0))
	d.Tokens = (d.Tokens or 0) + math.max(0, math.floor(r.Tokens or 0))
	d.Tickets.Revive = d.Tickets.Revive + math.max(0, math.floor(r.Revives or 0))
	d.Tickets.Rush = d.Tickets.Rush + math.max(0, math.floor(r.Rushes or 0))
	if r.Boost and d.Boosts[r.Boost] ~= nil then
		d.Boosts[r.Boost] = d.Boosts[r.Boost] + math.floor((r.Minutes or 30) * 60)
	end
	if r.Title and Config.Looks.Titles[r.Title] then
		d.Looks.titles[r.Title] = true
	end
	if r.Aura and Config.Looks.Auras[r.Aura] then
		d.Looks.auras[r.Aura] = true
	end
end

function RewardService.Pay(player, r, why)
	local d = PlayerService and PlayerService.GetData(player)
	if not d or type(r) ~= "table" then
		return false
	end
	payInto(d, r)
	PlayerService.MarkDirty(player)
	if why then
		notify(player, why .. " " .. Config.rewardText(r), "rare")
	end
	RewardService.RefreshLooks(player)
	return true
end

----------------------------------------------------------------------
-- the collector bar
----------------------------------------------------------------------
function RewardService.CollectorPoints(d)
	local owned, cleared = 0, 0
	for id in pairs(d.Weapons and d.Weapons.own or {}) do
		if Config.Weapons.List[id] then
			owned = owned + 1
		end
	end
	for _, n in pairs(d.Cleared or {}) do
		if n > 0 then
			cleared = cleared + 1
		end
	end
	return owned * R.CollectorPoints.Weapon + cleared * R.CollectorPoints.Boss
end

----------------------------------------------------------------------
-- LOOKS: the title over your head and the aura round you (made on the
-- server, so everyone sees them)
----------------------------------------------------------------------
function RewardService.RefreshLooks(player)
	local d = PlayerService and PlayerService.GetData(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not (d and root and head) then
		return
	end
	-- the title
	local tag = head:FindFirstChild("LookTitle")
	local def = d.Looks.title and Config.Looks.Titles[d.Looks.title]
	if def then
		if not tag then
			tag = Instance.new("BillboardGui")
			tag.Name = "LookTitle"
			tag.Size = UDim2.fromOffset(200, 26)
			tag.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
			tag.AlwaysOnTop = false
			tag.MaxDistance = 90
			tag.LightInfluence = 0
			local l = Instance.new("TextLabel")
			l.Name = "Text"
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.TextStrokeTransparency = 0
			l.TextStrokeColor3 = Color3.fromRGB(24, 20, 37)
			l.Parent = tag
			tag.Parent = head
		end
		local l = tag:FindFirstChild("Text")
		l.Text = "[ " .. def.Text .. " ]"
		l.TextColor3 = def.Color
	elseif tag then
		tag:Destroy()
	end
	-- the aura
	local aura = root:FindFirstChild("LookAura")
	local adef = d.Looks.aura and Config.Looks.Auras[d.Looks.aura]
	if adef then
		if not aura then
			aura = Instance.new("ParticleEmitter")
			aura.Name = "LookAura"
			aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			aura.Rate = 14
			aura.Lifetime = NumberRange.new(0.8, 1.3)
			aura.Speed = NumberRange.new(1.5, 3)
			aura.SpreadAngle = Vector2.new(180, 180)
			aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			aura.LightEmission = 0.8
			aura.Parent = root
		end
		if adef.Rainbow then
			aura.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
			})
		else
			aura.Color = ColorSequence.new(adef.Color)
		end
	elseif aura then
		aura:Destroy()
	end
end

----------------------------------------------------------------------
-- the corner bonuses
----------------------------------------------------------------------
local function friendBonus(player)
	local n = 0
	for id, yes in pairs(friendsOf[player] or {}) do
		local other = yes and Players:GetPlayerByUserId(id)
		if other and other ~= player then
			n = n + 1
		end
	end
	return math.min(R.Friends.Max, n * R.Friends.PerFriend)
end

local function playBonus(player)
	local since = joined[player]
	if not since then
		return 0
	end
	local steps = math.floor((os.clock() - since) / (R.Playtime.StepMinutes * 60))
	return math.min(R.Playtime.Max, steps * R.Playtime.PerStep)
end

-- (who's friends with whom, looked up once each - IsFriendsWith asks Roblox)
local function scanFriends(player)
	friendsOf[player] = friendsOf[player] or {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and friendsOf[player][other.UserId] == nil then
			local ok, yes = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok then
				friendsOf[player][other.UserId] = yes == true
				friendsOf[other] = friendsOf[other] or {}
				friendsOf[other][player.UserId] = yes == true
			end
		end
	end
end

local function refreshBonuses()
	for _, p in ipairs(Players:GetPlayers()) do
		local fb = friendBonus(p)
		for id, yes in pairs(friendsOf[p] or {}) do
			if not yes then
				continue
			end
			-- (a VIP in the server gives their friends a little more: ShopService says)
			local other = Players:GetPlayerByUserId(id)
			if other and other:GetAttribute("VIP") then
				fb = fb + (Config.Shop.VIP.FriendXP or 0)
			end
		end
		if p:GetAttribute("FriendBonus") ~= fb then
			p:SetAttribute("FriendBonus", fb)
		end
		local pb = playBonus(p)
		if p:GetAttribute("PlayBonus") ~= pb then
			p:SetAttribute("PlayBonus", pb)
		end
	end
end

----------------------------------------------------------------------
-- the clock: the free gift's play time, the boosts running down
----------------------------------------------------------------------
local function tick(dt)
	local today = Config.questDay()
	for _, p in ipairs(Players:GetPlayers()) do
		local d = PlayerService.GetData(p)
		if d then
			local r = d.Rewards
			if r.giftDay ~= today then
				r.giftDay = today
				r.giftsToday = 0
			end
			local need = R.GiftMinutes * 60
			if r.giftsToday < R.GiftsPerDay and r.giftPlay < need then
				local before = r.giftPlay
				r.giftPlay = math.min(need, r.giftPlay + dt)
				if before < need and r.giftPlay >= need then
					PlayerService.MarkDirty(p) -- (the gift's ready: tell their screen)
				end
			end
			for k, left in pairs(d.Boosts) do
				if left > 0 then
					d.Boosts[k] = math.max(0, left - dt)
					if d.Boosts[k] == 0 then
						PlayerService.MarkDirty(p)
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- actions
----------------------------------------------------------------------
local function claimLogin(player, d)
	local r = d.Rewards
	local today = Config.questDay()
	if r.streakDay == today then
		return false, "Already claimed today - come back tomorrow!"
	end
	if r.streakDay == today - 1 and r.streak < #R.Login then
		r.streak = r.streak + 1
	else
		r.streak = 1
	end
	r.streakDay = today
	local reward = table.clone(R.Login[r.streak])
	if reward.Title == "Loyal" then
		if r.loyal then
			reward.Title = nil
		end
		r.loyal = true
	end
	payInto(d, reward)
	RewardService.RefreshLooks(player)
	return true, "Day " .. r.streak .. "! " .. Config.rewardText(reward)
end

local function claimGift(player, d)
	local r = d.Rewards
	if r.giftPlay < R.GiftMinutes * 60 then
		return false, "The gift isn't ready yet."
	end
	r.gifts = r.gifts + 1
	r.giftsToday = r.giftsToday + 1
	r.giftPlay = 0
	local reward = R.Gifts[(r.gifts - 1) % #R.Gifts + 1]
	payInto(d, reward)
	return true, "Free gift! " .. Config.rewardText(reward)
end

local function redeemCode(player, d, arg)
	if type(arg) ~= "string" then
		return false, "Type a code first."
	end
	local code = string.upper((string.gsub(arg, "%s", "")))
	local def = R.Codes[code]
	if #code == 0 or #code > 24 or not def then
		return false, "That code doesn't work."
	end
	if def.Until and os.time() > def.Until then
		return false, "That code has run out."
	end
	if d.Rewards.codes[code] then
		return false, "You've already used that code."
	end
	d.Rewards.codes[code] = true
	payInto(d, def)
	RewardService.RefreshLooks(player)
	return true, "Code used! " .. Config.rewardText(def)
end

local function updateById(id)
	for _, u in ipairs(R.Updates) do
		if u.Id == id then
			return u
		end
	end
	return nil
end

local function claimUpdate(player, d, arg)
	local u = type(arg) == "string" and updateById(arg)
	if not u then
		return false, "There's no such update."
	end
	if d.Rewards.updates[u.Id] then
		return false, "Already claimed."
	end
	d.Rewards.updates[u.Id] = true
	d.Rewards.seen = u.Id
	payInto(d, u.Gift or {})
	RewardService.RefreshLooks(player)
	return true, "Update gift! " .. Config.rewardText(u.Gift or {})
end

local function seenUpdate(player, d, arg)
	if type(arg) == "string" and updateById(arg) then
		d.Rewards.seen = arg
		return true
	end
	return false
end

local function claimIndex(player, d, arg)
	local def = type(arg) == "string" and Config.Weapons.List[arg]
	if not def then
		return false, "There's no such weapon."
	end
	if d.Weapons.own[arg] == nil then
		return false, "Find it first!"
	end
	if d.Rewards.index[arg] then
		return false, "Already claimed."
	end
	d.Rewards.index[arg] = true
	local reward = R.IndexFind[def.Rarity] or {}
	payInto(d, reward)
	return true, def.Name .. " added to the Index! " .. Config.rewardText(reward)
end

local function claimCollector(player, d, arg)
	local level = tonumber(arg)
	local m = nil
	for _, c in ipairs(R.Collector) do
		if c.Level == level then
			m = c
		end
	end
	if not m then
		return false, "There's no such reward."
	end
	local key = tostring(m.Level)
	if d.Rewards.milestones[key] then
		return false, "Already claimed."
	end
	if Config.collectorLevel(RewardService.CollectorPoints(d)) < m.Level then
		return false, "Reach collector level " .. m.Level .. " first!"
	end
	d.Rewards.milestones[key] = true
	payInto(d, m)
	RewardService.RefreshLooks(player)
	return true, "Collector level " .. m.Level .. "! " .. Config.rewardText(m)
end

local function claimGroup(player, d)
	if d.Rewards.group then
		return false, "Already claimed - thanks for joining!"
	end
	if (R.GroupId or 0) <= 0 then
		return false, "The community isn't linked yet."
	end
	local ok, member = pcall(function()
		return player:IsInGroup(R.GroupId)
	end)
	if not ok then
		return false, "Couldn't check - try again in a moment."
	end
	if not member then
		return false, "Join the community first, then come back!"
	end
	d.Rewards.group = true
	payInto(d, R.Group)
	RewardService.RefreshLooks(player)
	return true, "Thanks for joining! " .. Config.rewardText(R.Group)
end

local function wear(kind)
	return function(player, d, arg)
		local list = kind == "title" and d.Looks.titles or d.Looks.auras
		if arg == "" or arg == nil then
			d.Looks[kind] = nil
		elseif type(arg) == "string" and list[arg] then
			d.Looks[kind] = arg
		else
			return false, "You don't have that yet."
		end
		RewardService.RefreshLooks(player)
		return true
	end
end

local function saveSettings(player, d, arg)
	if type(arg) ~= "table" then
		return false
	end
	for k, v in pairs(d.Settings) do
		if type(arg[k]) == type(v) then
			d.Settings[k] = arg[k]
		end
	end
	return true
end

----------------------------------------------------------------------
function RewardService.Start(playerService)
	PlayerService = playerService
	local actions = {
		RewardLogin = claimLogin,
		RewardGift = claimGift,
		RewardCode = redeemCode,
		RewardUpdate = claimUpdate,
		RewardSeen = seenUpdate,
		IndexClaim = claimIndex,
		CollectorClaim = claimCollector,
		GroupClaim = claimGroup,
		WearTitle = wear("title"),
		WearAura = wear("aura"),
		SaveSettings = saveSettings,
	}
	for name, fn in pairs(actions) do
		PlayerService.AddAction(name, function(player, d, arg)
			local ok, msg = fn(player, d, arg)
			if ok then
				PlayerService.MarkDirty(player)
			end
			return ok, msg
		end)
	end
	-- XP: + the corner bonuses (coins aren't touched)
	PlayerService.AddGainHook(function(player, _, kind, amount)
		if kind ~= "Power" then
			return amount
		end
		local pct = (player:GetAttribute("PlayBonus") or 0) + (player:GetAttribute("FriendBonus") or 0)
		return amount * (1 + pct / 100)
	end)
	local function added(player)
		joined[player] = os.clock()
		task.spawn(scanFriends, player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Head", 10)
			char:WaitForChild("HumanoidRootPart", 10)
			RewardService.RefreshLooks(player)
		end)
		if player.Character then
			task.defer(RewardService.RefreshLooks, player)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in ipairs(Players:GetPlayers()) do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		joined[player] = nil
		friendsOf[player] = nil
		for _, list in pairs(friendsOf) do
			list[player.UserId] = nil
		end
	end)
	local acc, bonusAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		bonusAcc = bonusAcc + dt
		if acc >= 1 then
			tick(acc)
			acc = 0
		end
		if bonusAcc >= 5 then
			bonusAcc = 0
			refreshBonuses()
		end
	end)
	refreshBonuses()
end

return RewardService
