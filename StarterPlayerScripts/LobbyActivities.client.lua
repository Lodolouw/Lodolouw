--[[
	LobbyActivities  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "LobbyActivities")

	Your side of two things to do in the lobby:

	  * THE QUEST BOARD - walk up to the wooden board by the south road and
	    press E: a quest menu opens with today's three quests - what to do,
	    how far along you are, the reward, and a HAND IN button once it's
	    done. It closes with the X, or when you walk away. A gold "!" bobs
	    over the board while you have one to hand in.

	  * THE COLOSSEUM - hides other players' dummies (everyone farms on their
	    own), and shows the wave and the quest at the top of the screen, with
	    the rewards popping up as you beat dummies.

	The server decides everything (PlayerService / CombatService); this only
	shows it and asks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne
local RGB = Color3.fromRGB
-- (Endesga-32 colours, like the rest of the game)
local CORK = RGB(190, 128, 88)
local PAPER = RGB(24, 20, 37) -- (a quest card: the game's black box)
local PAPER_DONE = RGB(38, 92, 66)
local INK = RGB(255, 255, 255)
local RED = RGB(228, 59, 68)
local GOLD = RGB(254, 174, 52)
local GREEN = RGB(99, 199, 77)
local GREY = RGB(139, 155, 180)

----------------------------------------------------------------------
-- The Quest Board
----------------------------------------------------------------------
local quests = nil -- today's quests from the server: { day, list = { {id, n, claimed} }, bonus }
local notes = {} -- the three notes on the board
local header, footer, status
local statusUntil = 0

local function label(parent, text, size, pos, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color or INK
	l.TextScaled = true
	l.TextWrapped = true
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function say(text, color)
	if status then
		status.Text = text
		status.TextColor3 = color or INK
		statusUntil = os.clock() + 3
	end
end

local function claim(index)
	local ok, ok2, msg = pcall(function()
		return Remotes.Action:InvokeServer("ClaimQuest", index)
	end)
	if not ok then
		say("Couldn't reach the server.", RED)
	else
		say(tostring(msg or ""), ok2 and GREEN or RED)
	end
end

local menu -- the ScreenGui
local function buildMenu()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestMenu"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	menu = gui

	-- the panel: a cork board in the middle of the screen
	local bg = Instance.new("Frame")
	bg.Name = "Cork"
	bg.BackgroundColor3 = CORK
	bg.BorderSizePixel = 0
	bg.AnchorPoint = Vector2.new(0.5, 0.5)
	bg.Position = UDim2.fromScale(0.5, 0.5)
	bg.Size = UDim2.fromScale(0.62, 0.62)
	bg.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.7
	aspect.Parent = bg
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(96, 64, 48)
	edge.Thickness = 6
	edge.Parent = bg

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "X"
	close.Font = FONT
	close.TextScaled = true
	close.TextColor3 = RGB(255, 255, 255)
	close.BackgroundColor3 = RED
	close.BorderSizePixel = 0
	close.Size = UDim2.fromScale(0.07, 0.11)
	close.Position = UDim2.fromScale(0.915, 0.02)
	close.Parent = bg
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	header = label(bg, "DAILY QUESTS", UDim2.fromScale(0.9, 0.11), UDim2.fromScale(0.05, 0.02), RGB(255, 255, 255))
	footer = label(bg, "", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.9), RGB(255, 255, 255))
	status = label(bg, "", UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.13), RGB(255, 255, 255))

	for i = 1, 3 do
		local note = Instance.new("Frame")
		note.Name = "Note" .. i
		note.BackgroundColor3 = PAPER
		note.BorderSizePixel = 0
		note.Size = UDim2.fromScale(0.29, 0.68)
		note.Position = UDim2.fromScale(0.035 + (i - 1) * 0.322, 0.21)
		note.Rotation = (i - 2) * 1.5 -- pinned up a little crooked
		local ns = Instance.new("UIStroke")
		ns.Color = RGB(255, 255, 255)
		ns.Thickness = 2
		ns.Parent = note
		note.Parent = bg
		-- a red pin at the top
		local pin = Instance.new("Frame")
		pin.BackgroundColor3 = RED
		pin.BorderSizePixel = 0
		pin.Size = UDim2.fromScale(0.1, 0.06)
		pin.Position = UDim2.fromScale(0.45, 0.02)
		pin.Parent = note

		local n = {}
		n.frame = note
		n.text = label(note, "", UDim2.fromScale(0.88, 0.36), UDim2.fromScale(0.06, 0.1))
		-- progress bar: ten chunky blocks (it's 8-bit)
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = RGB(12, 10, 20)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(0.88, 0.09)
		bar.Position = UDim2.fromScale(0.06, 0.49)
		bar.Parent = note
		n.blocks = {}
		for b = 1, 10 do
			local blk = Instance.new("Frame")
			blk.BorderSizePixel = 0
			blk.Size = UDim2.new(0.1, -2, 1, -4)
			blk.Position = UDim2.new((b - 1) * 0.1, 1, 0, 2)
			blk.Parent = bar
			n.blocks[b] = blk
		end
		n.count = label(note, "", UDim2.fromScale(0.88, 0.09), UDim2.fromScale(0.06, 0.59))
		n.reward = label(note, "", UDim2.fromScale(0.88, 0.1), UDim2.fromScale(0.06, 0.69), GOLD)
		local btn = Instance.new("TextButton")
		btn.Name = "HandIn"
		btn.Font = FONT
		btn.TextScaled = true
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromScale(0.8, 0.12)
		btn.Position = UDim2.fromScale(0.1, 0.83)
		btn.Parent = note
		btn.Activated:Connect(function()
			claim(i)
		end)
		n.button = btn
		notes[i] = n
	end
end

local function timeLeft()
	local secs = (Config.questDay() + 1) * 86400 - os.time()
	secs = math.max(0, secs)
	local h = math.floor(secs / 3600)
	local m = math.floor(secs % 3600 / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m"
end

local function hasHandIn()
	for _, q in ipairs((quests and quests.list) or {}) do
		local def = Config.QuestById[q.id]
		if def and not q.claimed and q.n >= def.goal then
			return true
		end
	end
	return false
end

local function render()
	if not header then
		return
	end
	local list = (quests and quests.list) or {}
	local allClaimed = #list > 0
	for i, n in ipairs(notes) do
		local q = list[i]
		local def = q and Config.QuestById[q.id]
		n.frame.Visible = def ~= nil
		if def then
			local done = q.n >= def.goal
			n.frame.BackgroundColor3 = q.claimed and PAPER_DONE or PAPER
			n.text.Text = Config.questText(def)
			local filled = math.floor(q.n / def.goal * 10 + 1e-6)
			for b, blk in ipairs(n.blocks) do
				blk.BackgroundColor3 = (b <= filled) and (done and GREEN or GOLD) or RGB(58, 68, 102)
			end
			n.count.Text = Config.format(q.n) .. " / " .. Config.format(def.goal)
			n.reward.Text = Config.format(def.reward) .. " coins"
			if q.claimed then
				n.button.Text = "HANDED IN"
				n.button.BackgroundColor3 = GREY
				n.button.TextColor3 = RGB(255, 255, 255)
				n.button.AutoButtonColor = false
			elseif done then
				n.button.Text = "HAND IN!"
				n.button.BackgroundColor3 = GREEN
				n.button.TextColor3 = RGB(255, 255, 255)
				n.button.AutoButtonColor = true
			else
				n.button.Text = "NOT DONE"
				n.button.BackgroundColor3 = RGB(58, 68, 102)
				n.button.TextColor3 = GREY
				n.button.AutoButtonColor = false
			end
			if not q.claimed then
				allClaimed = false
			end
		end
	end
	if quests and quests.bonus then
		footer.Text = "All done! Bonus chest claimed. New quests in " .. timeLeft()
	elseif allClaimed then
		footer.Text = "All done! New quests in " .. timeLeft()
	else
		footer.Text = "Hand in all 3 for a bonus chest!  New in " .. timeLeft()
	end
end

-- the gold "!" over the board: shown (and bobbing) while you have one to hand in
local marks = {}
local function trackMark(model)
	if model:IsA("Model") then
		marks[model] = model:GetPivot()
	end
end
for _, m in ipairs(CollectionService:GetTagged("QuestMark")) do
	trackMark(m)
end
CollectionService:GetInstanceAddedSignal("QuestMark"):Connect(trackMark)

local markShown = nil
local markTick = 0
RunService.Heartbeat:Connect(function(dt)
	local show = hasHandIn()
	markTick = markTick + dt
	for model, home in pairs(marks) do
		if not model.Parent then
			marks[model] = nil
		else
			if show ~= markShown then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then
						p.LocalTransparencyModifier = show and 0 or 1
					end
				end
			end
			if show and markTick >= 1 / 12 then
				-- (bobs in little 8-bit steps, like everything else)
				local y = math.floor(math.sin(os.clock() * 3) * 3 + 0.5) * 0.25
				model:PivotTo(home * CFrame.new(0, y, 0))
			end
		end
	end
	markShown = show
	if markTick >= 1 / 12 then
		markTick = 0
	end
	if status and statusUntil > 0 and os.clock() > statusUntil then
		statusUntil = 0
		status.Text = ""
	end
end)

-- keep the countdown ticking
task.spawn(function()
	while true do
		task.wait(20)
		render()
	end
end)

Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(data)
	if type(data) == "table" and type(data.Quests) == "table" then
		quests = data.Quests
		render()
	end
end)

buildMenu()
render()
Remotes:WaitForChild("RequestState"):FireServer()

-- press E at the board: open the menu
local function hookPrompt(pp)
	if pp:IsA("ProximityPrompt") then
		pp.Triggered:Connect(function()
			render()
			menu.Enabled = true
		end)
	end
end
for _, pp in ipairs(CollectionService:GetTagged("QuestPrompt")) do
	hookPrompt(pp)
end
CollectionService:GetInstanceAddedSignal("QuestPrompt"):Connect(hookPrompt)

-- walk away from the board and it closes
task.spawn(function()
	while true do
		task.wait(0.3)
		if menu.Enabled then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local board = Config.Stations.Quests
			if not root or (Vector3.new(root.Position.X - board.X, 0, root.Position.Z - board.Z)).Magnitude > 24 then
				menu.Enabled = false
			end
		end
	end
end)

----------------------------------------------------------------------
-- The Colosseum
----------------------------------------------------------------------
-- Everyone farms on their own: other players' dummies are taken off this
-- screen the moment they appear (the server keeps them; we just don't show
-- them). Yours carry your UserId as their Owner.
local function hideIfNotMine(model)
	local owner = model:GetAttribute("Owner")
	if owner and owner ~= player.UserId then
		task.defer(function()
			model.Parent = nil -- (only here, on this screen)
		end)
	end
end
task.spawn(function()
	local folder = workspace:WaitForChild("ColosseumEnemies", 60)
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			hideIfNotMine(m)
		end
		folder.ChildAdded:Connect(hideIfNotMine)
	end
end)

-- The tracker at the top of the screen: the wave, and the quest
local tracker = Instance.new("ScreenGui")
tracker.Name = "ColosseumHud"
tracker.ResetOnSpawn = false
tracker.Enabled = false
tracker.Parent = player:WaitForChild("PlayerGui")

local box = Instance.new("Frame")
box.Name = "Box"
box.BackgroundColor3 = RGB(12, 10, 20)
box.BorderSizePixel = 0
box.AnchorPoint = Vector2.new(0.5, 0)
box.Position = UDim2.new(0.5, 0, 0, 12)
box.Size = UDim2.fromOffset(340, 104)
box.Parent = tracker
local boxEdge = Instance.new("UIStroke")
boxEdge.Color = RGB(255, 255, 255)
boxEdge.Thickness = 3
boxEdge.Parent = box

local waveLabel = label(box, "COLOSSEUM", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 6), GOLD)
local questLabel = label(box, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 36), RGB(255, 255, 255))
local qbar = Instance.new("Frame")
qbar.BackgroundColor3 = RGB(38, 43, 68)
qbar.BorderSizePixel = 0
qbar.Position = UDim2.fromOffset(10, 60)
qbar.Size = UDim2.new(1, -20, 0, 12)
qbar.Parent = box
local qblocks = {}
for b = 1, 10 do
	local blk = Instance.new("Frame")
	blk.BorderSizePixel = 0
	blk.Size = UDim2.new(0.1, -2, 1, -4)
	blk.Position = UDim2.new((b - 1) * 0.1, 1, 0, 2)
	blk.Parent = qbar
	qblocks[b] = blk
end
local rewardLabel = label(box, "", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 78), GREY)

-- a big line across the middle of the screen (WAVE 3 / QUEST COMPLETE!)
local banner = label(tracker, "", UDim2.new(0.8, 0, 0, 60), UDim2.new(0.1, 0, 0.26, 0), GOLD)
banner.Visible = false
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 3
bannerStroke.Color = RGB(24, 20, 37)
bannerStroke.Parent = banner
local bannerToken = 0
local function showBanner(text, color, seconds)
	bannerToken = bannerToken + 1
	local mine = bannerToken
	banner.Text = text
	banner.TextColor3 = color or GOLD
	banner.Visible = true
	task.delay(seconds or 1.6, function()
		if bannerToken == mine then
			banner.Visible = false
		end
	end)
end

-- "+12 XP" popping up under the tracker for each dummy you beat
local function popReward(text)
	local l = label(tracker, text, UDim2.fromOffset(300, 22), UDim2.new(0.5, -150, 0, 124), GREEN)
	task.spawn(function()
		for k = 1, 16 do
			l.Position = UDim2.new(0.5, -150, 0, 124 + k * 2)
			l.TextTransparency = k / 16
			task.wait(1 / 20)
		end
		l:Destroy()
	end)
end

local function renderTracker(st)
	waveLabel.Text = "COLOSSEUM  -  WAVE " .. tostring(math.max(1, st.wave or 0))
	local q, goal = st.quest or 0, st.goal or 10
	questLabel.Text = "QUEST: Defeat dummies  " .. q .. " / " .. goal
	local filled = math.floor(q / goal * 10 + 1e-6)
	for b, blk in ipairs(qblocks) do
		blk.BackgroundColor3 = (b <= filled) and GOLD or RGB(58, 68, 102)
	end
	rewardLabel.Text = "Reward: " .. Config.format(st.questPower or 0) .. " XP + " .. Config.format(st.questCoins or 0) .. " coins"
end

local function syncTracker()
	tracker.Enabled = player:GetAttribute("Colosseum") == true
end
player:GetAttributeChangedSignal("Colosseum"):Connect(syncTracker)
syncTracker()

ReplicatedStorage:WaitForChild("ColosseumEvent", 60).OnClientEvent:Connect(function(kind, a, b)
	if kind == "State" and type(a) == "table" then
		renderTracker(a)
	elseif kind == "Arrived" then
		showBanner("THE COLOSSEUM", GOLD, 1.8)
	elseif kind == "Wave" then
		showBanner("WAVE " .. tostring(a), RGB(255, 255, 255), 1.4)
	elseif kind == "Kill" then
		popReward("+" .. Config.format(a) .. " XP   +" .. Config.format(b) .. " coins")
	elseif kind == "QuestDone" then
		showBanner("QUEST COMPLETE!  +" .. Config.format(a) .. " XP  +" .. Config.format(b) .. " coins", GREEN, 2.6)
	end
end)
