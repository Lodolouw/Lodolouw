--[[
	PartyMenu  (LocalScript, parent: StarterPlayerScripts)

	PARTIES on your screen (the server side is ServerScriptService/PartyService):
	  * THE PARTY MENU (the PARTY button top right in the lobby): your party -
	    up to 4, the leader crowned - with LEAVE, and KICK for the leader; and
	    everyone else in the server with an INVITE button.
	  * AN INVITE: a pop-up in the middle of the screen, ACCEPT / DECLINE, for
	    as long as it lasts (30 seconds).
	  * The server's messages ("Bravo joined the party!") as toasts.
	The leader picks the floor in the Spire menu and the whole party goes in
	together; who's in whose party is each player's PartyLeader attribute.
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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("PartyRemotes", 30)
local event = remotes and remotes:WaitForChild("PartyEvent", 10)
if not event then
	return
end
local MAX = 4

-- everyone in my party, the leader first (just me if I'm in none)
local function myParty()
	local lead = player:GetAttribute("PartyLeader")
	if not lead then
		return { player }, nil
	end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("PartyLeader") == lead then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		if (a.UserId == lead) ~= (b.UserId == lead) then
			return a.UserId == lead
		end
		return a.Name < b.Name
	end)
	return list, lead
end

local function row(api, name, sub, buttons)
	local block = api.block(84)
	local face = K.card(block, { Name = "Row_" .. name, Size = UDim2.fromOffset(math.min(820, api.width), 72), ZIndex = 7 })
	K.label(face, { Name = "Name", Text = name, TextScaled = false, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 6), Size = UDim2.new(1, -360, 0, 34), ZIndex = 9 })
	K.label(face, { Name = "Sub", Text = sub, TextScaled = false, TextSize = 16, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -360, 0, 24), ZIndex = 9 })
	for i, b in ipairs(buttons) do
		local btn = api.button(face, b[1], b[2], { Name = b[1], AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20 - (i - 1) * 160, 0.5, 0), Size = UDim2.fromOffset(148, 48), ZIndex = 10 })
		btn.Activated:Connect(b[3])
	end
end

Menus.define("Party", {
	Title = "Party",
	Color = C.Blue,
	Tabs = { { Key = "Party", Label = "Party", Icon = "Friends" } },
	render = function(page, tab, api)
		local members, lead = myParty()
		local leading = lead == nil or lead == player.UserId
		api.section("Your party (" .. #members .. "/" .. MAX .. ")",
			"Fight the Spire together: the leader picks the floor and everyone goes into the same arena. The boss gets tougher for each of you.")
		for _, p in ipairs(members) do
			local isLead = lead ~= nil and p.UserId == lead
			local buttons = {}
			if p == player and lead then
				table.insert(buttons, { "LEAVE", C.Off, function()
					event:FireServer("Leave")
				end })
			elseif lead == player.UserId and p ~= player then
				table.insert(buttons, { "KICK", C.Off, function()
					event:FireServer("Kick", p)
				end })
			end
			local sub = isLead and "👑 Leader - picks the floor" or (p == player and (lead and "You" or "You (on your own)") or "In your party")
			row(api, p.DisplayName ~= p.Name and (p.DisplayName .. " (@" .. p.Name .. ")") or p.Name, sub, buttons)
		end
		api.section("Invite", leading and "Anyone in this server." or "Only your party's leader can invite.")
		local others = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and not table.find(members, p) then
				others += 1
				local busy = p:GetAttribute("PartyLeader") ~= nil
				local buttons = {}
				if leading and not busy and #members < MAX then
					table.insert(buttons, { "INVITE", C.Green, function()
						event:FireServer("Invite", p)
					end })
				end
				row(api, p.Name, busy and "In a party" or (p:GetAttribute("SpireFloor") and "In the Spire" or "In the lobby"), buttons)
			end
		end
		if others == 0 then
			api.words("Nobody else is here yet - invite friends to the game!", 40)
		end
	end,
})

-- the menu follows who's in which party while it's open
local function changed()
	if Menus.current and Menus.current() == "Party" then
		Menus.redraw()
	end
end
local function watch(p)
	p:GetAttributeChangedSignal("PartyLeader"):Connect(changed)
end
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end
Players.PlayerAdded:Connect(function(p)
	watch(p)
	changed()
end)
Players.PlayerRemoving:Connect(function()
	task.defer(changed)
end)

----------------------------------------------------------------------
-- An invite: ACCEPT / DECLINE in the middle of the screen
----------------------------------------------------------------------
local popup = nil
local function closePopup()
	if popup then
		popup:Destroy()
		popup = nil
	end
end
local function showInvite(from, seconds)
	closePopup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PartyInvite"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	popup = gui
	local face = K.card(gui, {
		Name = "Invite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(460, 170),
		ZIndex = 5,
	})
	K.label(face, { Name = "Title", Text = "PARTY INVITE", Font = K.TITLE_FONT, TextScaled = false, TextSize = 18, TextColor3 = C.Blue, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 24), ZIndex = 7 })
	K.label(face, { Name = "Words", Text = from.Name .. " wants you in their party!", TextScaled = false, TextSize = 22, TextWrapped = true, Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 56), ZIndex = 7 })
	local yes = K.button(face, "ACCEPT", C.Green, { Name = "Accept", Position = UDim2.new(0.5, -170, 1, -62), Size = UDim2.fromOffset(160, 48), ZIndex = 8 })
	local no = K.button(face, "DECLINE", C.Off, { Name = "Decline", Position = UDim2.new(0.5, 10, 1, -62), Size = UDim2.fromOffset(160, 48), ZIndex = 8 })
	yes.Activated:Connect(function()
		event:FireServer("Accept", from)
		closePopup()
	end)
	no.Activated:Connect(function()
		event:FireServer("Decline", from)
		closePopup()
	end)
	task.delay(seconds or 30, function()
		if popup == gui then
			closePopup()
		end
	end)
end

event.OnClientEvent:Connect(function(kind, a, b)
	if kind == "Invited" and typeof(a) == "Instance" then
		showInvite(a, b)
	elseif kind == "Message" and type(a) == "string" then
		Menus.toast(a, "info")
	end
end)
