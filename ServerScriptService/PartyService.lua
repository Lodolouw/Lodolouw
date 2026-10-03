--[[
	PartyService  (ModuleScript, parent: ServerScriptService, name: "PartyService")

	PARTIES: up to 4 players fighting the Spire together.
	  * Invite someone (the Party menu, PartyMenu on your screen): they get a
	    pop-up with Accept / Decline for 30 seconds. Only a party's leader
	    invites, and someone already in a party has to leave theirs first.
	  * The LEADER picks the floor in the Spire menu: the whole party - everyone
	    in the lobby and alive - goes into one arena copy together (ArenaPool),
	    and the boss wakes with more health for each of them (BossService:
	    Config.Bosses PartyScale). The others can't start a trip themselves.
	  * Leave any time; the leader can kick. A leader who leaves (or quits)
	    hands the party to the next one in; a party of one is no party.
	Who's in a party is on every player, so every screen can show it:
	PartyLeader = the leader's UserId (nil: not in a party).

	The remote (ReplicatedStorage/PartyRemotes/PartyEvent):
	  client -> server: ("Invite", player) / ("Accept", player) /
	                    ("Decline", player) / ("Leave") / ("Kick", player)
	  server -> client: ("Invited", fromPlayer, seconds) / ("Message", text)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PartyService = {}

local MAX = 4
local INVITE_TIME = 30
local COOLDOWN = 0.25 -- (between one player's party actions)

local partyOf = {} -- [player] = party { leader = player, members = { player... } }
local invites = {} -- [invited player] = { [from player] = until (os.clock) }
local lastAct = {}
local remote = nil

local function tell(p, text)
	if remote and p.Parent then
		remote:FireClient(p, "Message", text)
	end
end

local function publish(party)
	for _, p in ipairs(party.members) do
		p:SetAttribute("PartyLeader", party.leader.UserId)
	end
end

local function free(p)
	return p:GetAttribute("SpireFloor") == nil and not p:GetAttribute("Colosseum") and not p:GetAttribute("Intro")
end

-- out of their party (and the party tidied: a new leader, or none left)
local function leave(p, why)
	local party = partyOf[p]
	partyOf[p] = nil
	if p.Parent then
		p:SetAttribute("PartyLeader", nil)
	end
	if not party then
		return
	end
	local i = table.find(party.members, p)
	if i then
		table.remove(party.members, i)
	end
	if #party.members <= 1 then
		for _, q in ipairs(party.members) do
			partyOf[q] = nil
			q:SetAttribute("PartyLeader", nil)
			tell(q, "Your party broke up.")
		end
		return
	end
	if party.leader == p then
		party.leader = party.members[1]
		tell(party.leader, "You're the party's leader now: you pick the floor.")
	end
	publish(party)
	for _, q in ipairs(party.members) do
		tell(q, p.Name .. (why or " left the party."))
	end
end

local function invite(from, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players or target == from then
		return tell(from, "Pick someone to invite.")
	end
	local party = partyOf[from]
	if party and party.leader ~= from then
		return tell(from, "Only your party's leader can invite.")
	end
	if party and #party.members >= MAX then
		return tell(from, "Your party is full (" .. MAX .. ").")
	end
	if partyOf[target] then
		return tell(from, target.Name .. " is already in a party.")
	end
	-- (no invite spam: one live invite per sender, a handful per player, and
	-- nobody busy fighting gets pop-ups)
	local theirs = invites[target]
	if theirs and theirs[from] and os.clock() < theirs[from] then
		return tell(from, "You already invited " .. target.Name .. ".")
	end
	local live = 0
	for _, untilT in pairs(theirs or {}) do
		if os.clock() < untilT then
			live = live + 1
		end
	end
	if live >= 5 then
		return tell(from, target.Name .. " has too many invites right now.")
	end
	if not free(target) then
		return tell(from, target.Name .. " is busy right now.")
	end
	invites[target] = invites[target] or {}
	invites[target][from] = os.clock() + INVITE_TIME
	remote:FireClient(target, "Invited", from, INVITE_TIME)
	tell(from, "Invited " .. target.Name .. ".")
end

local function accept(p, from)
	local mine = invites[p]
	local untilT = mine and typeof(from) == "Instance" and mine[from]
	if mine then
		mine[from] = nil
	end
	if not untilT or os.clock() > untilT or not from.Parent then
		return tell(p, "That invite has run out.")
	end
	local party = partyOf[from]
	if party and party.leader ~= from then
		return tell(p, "That party has a new leader now - ask them for an invite.")
	end
	if party and #party.members >= MAX then
		return tell(p, from.Name .. "'s party is full.")
	end
	-- (only once the new party can really take you does the old one let go)
	if partyOf[p] then
		leave(p)
		party = partyOf[from]
	end
	if not party then
		party = { leader = from, members = { from } }
		partyOf[from] = party
	end
	table.insert(party.members, p)
	partyOf[p] = party
	invites[p] = nil
	publish(party)
	for _, q in ipairs(party.members) do
		tell(q, q == p and ("You joined " .. from.Name .. "'s party!") or (p.Name .. " joined the party!"))
	end
end

local function onEvent(p, action, arg)
	local now = os.clock()
	if lastAct[p] and now - lastAct[p] < COOLDOWN then
		return
	end
	lastAct[p] = now
	if action == "Invite" then
		invite(p, arg)
	elseif action == "Accept" then
		accept(p, arg)
	elseif action == "Decline" then
		local mine = invites[p]
		if mine and typeof(arg) == "Instance" and mine[arg] then
			mine[arg] = nil
			if arg.Parent then
				tell(arg, p.Name .. " said no thanks.")
			end
		end
	elseif action == "Leave" then
		if partyOf[p] then
			leave(p)
			tell(p, "You left the party.")
		end
	elseif action == "Kick" then
		local party = partyOf[p]
		if party and party.leader == p and typeof(arg) == "Instance" and partyOf[arg] == party and arg ~= p then
			leave(arg, " was removed from the party.")
			tell(arg, "You were removed from the party.")
		end
	end
end

----------------------------------------------------------------------
-- For SpireService: who goes up with this player
----------------------------------------------------------------------
-- The players going into the arena with `player` (who picked the floor):
-- just them, or - for a party's leader - everyone in the party who's in the
-- lobby and alive. A party member who isn't the leader can't start a trip:
-- nil and why.
function PartyService.PartyFor(player, floorId, tierId)
	local party = partyOf[player]
	if not party then
		return { player }
	end
	if party.leader ~= player then
		return nil, party.leader.Name .. " (your party's leader) picks the floor."
	end
	local group = { player }
	for _, p in ipairs(party.members) do
		if p ~= player then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			-- (each member must have opened that floor themselves - the floor
			-- below it beaten, its tier open - or anyone could be carried
			-- straight to the top and have the whole Spire unlocked for them)
			local unlocked = true
			if type(floorId) == "number" and not (Config.Spire.DevSkip and Config.isDev(p)) then
				local tier = Config.spireTier(tierId)
				local cleared = Config.spireCleared(p)
				unlocked = Config.spireTierOpen(cleared, tier.id)
					and (not Config.Spire.RequirePrevious or floorId <= 1 or (cleared[tier.id] or 0) >= floorId - 1)
					and not Config.spireLevelLocked(p, floorId, tier.id) -- (and their level reached)
			end
			if free(p) and hum and hum.Health > 0 and unlocked then
				table.insert(group, p)
			elseif not unlocked then
				tell(p, "Your party went up without you - you haven't opened that floor yet (or reached its level).")
			else
				tell(p, "Your party went up the Spire without you (you were busy).")
			end
		end
	end
	return group
end

-- the members of a player's party (just them if they're in none)
function PartyService.MembersOf(player)
	local party = partyOf[player]
	return party and table.clone(party.members) or { player }
end

function PartyService.Start(spireService)
	local old = ReplicatedStorage:FindFirstChild("PartyRemotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PartyRemotes"
	remote = Instance.new("RemoteEvent")
	remote.Name = "PartyEvent"
	remote.Parent = folder
	folder.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(p, action, arg)
		local ok, err = pcall(onEvent, p, action, arg)
		if not ok then
			warn("[PartyService] " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		leave(p, " left the game.")
		invites[p] = nil
		lastAct[p] = nil
		for _, list in pairs(invites) do
			list[p] = nil
		end
	end)
	-- the Spire takes a party's leader up with everyone in it
	if spireService then
		spireService.PartyFor = PartyService.PartyFor
	end
end

return PartyService
