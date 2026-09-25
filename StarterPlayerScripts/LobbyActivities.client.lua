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

local notesRef -- (the cards, once built)
local ripping = {} -- [card] = true while it's being torn off

-- Rips a card off the board like a bandage: a quick tug, then it tears free
-- and tumbles away off the screen. A scrap stays under the pin.
local function rip(index)
	local n = notesRef and notesRef[index]
	if not n then
		return
	end
	ripping[index] = true
	local f = n.frame
	local dir = (index <= 2) and -1 or 1
	-- the tug
	for k = 1, 3 do
		f.Rotation = n.rot + dir * k * 3
		f.Position = n.home + UDim2.fromScale(0, 0.01 * k)
		task.wait(1 / 30)
	end
	n.scrap.Visible = true
	-- torn free: off it goes, spinning, faster and faster
	for k = 1, 16 do
		local t = k / 16
		f.Rotation = n.rot + dir * (9 + 70 * t)
		f.Position = n.home + UDim2.fromScale(dir * 0.35 * t, 0.03 + 1.3 * t * t)
		task.wait(1 / 40)
	end
	f.Visible = false
	f.Position = n.home
	f.Rotation = n.rot
	ripping[index] = nil
	n.scrap.Visible = true
end
local bgRef -- (the cork panel, shaken by the stamp)

-- The stamp: a big red COMPLETED slams down onto the card from above the
-- screen, the board jolts, and it stays there.
local function stamp(index)
	local n = notesRef and notesRef[index]
	if not n then
		return
	end
	local st = n.stamp
	st.Visible = true
	local scale = st:FindFirstChildOfClass("UIScale")
	for k = 0, 6 do
		scale.Scale = 3 - 2 * (k / 6) ^ 2 -- (falling towards you, faster and faster)
		st.TextTransparency = 1 - k / 6
		task.wait(1 / 40)
	end
	scale.Scale = 1
	st.TextTransparency = 0
	-- THUMP: the whole board jolts
	local home = bgRef.Position
	for k = 1, 6 do
		bgRef.Position = home + UDim2.fromOffset((k % 2 == 0 and -1 or 1) * (7 - k), (k % 2 == 0 and 1 or -1) * (6 - k))
		task.wait(1 / 40)
	end
	bgRef.Position = home
end

-- A card's button: pick it (if you haven't picked today's quest yet), or
-- hand it in (if it's the one you picked and it's done).
local function act(index)
	local pick = quests and quests.pick
	local ok, ok2, msg = pcall(function()
		if not pick then
			return Remotes.Action:InvokeServer("PickQuest", index)
		end
		return Remotes.Action:InvokeServer("ClaimQuest")
	end)
	if not ok then
		say("Couldn't reach the server.", RED)
		return
	end
	say(tostring(msg or ""), ok2 and GREEN or RED)
	if ok2 and pick then
		task.spawn(stamp, index)
	elseif ok2 then
		-- picked: the other two get ripped off the board
		for j = 1, #notesRef do
			if j ~= index then
				task.delay((j < index and 0 or 0.12), rip, j)
			end
		end
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
	bgRef = bg
	notesRef = notes
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
			act(i)
		end)
		n.button = btn
		-- the COMPLETED stamp (hidden until it's handed in)
		local st = label(note, "COMPLETED", UDim2.fromScale(1.05, 0.2), UDim2.fromScale(-0.025, 0.36), RED)
		st.Name = "Stamp"
		st.Rotation = -18
		st.ZIndex = 5
		st.Visible = false
		local ring = Instance.new("UIStroke")
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Color = RED
		ring.Thickness = 4
		ring.Parent = st
		local sc = Instance.new("UIScale")
		sc.Parent = st
		n.stamp = st
		n.home = note.Position
		n.rot = note.Rotation
		-- a torn scrap of paper left under the pin when the card is ripped off
		local scrap = Instance.new("Frame")
		scrap.Name = "Scrap" .. i
		scrap.BackgroundColor3 = PAPER
		scrap.BorderSizePixel = 0
		scrap.Size = UDim2.fromScale(0.1, 0.06)
		scrap.Position = note.Position + UDim2.fromScale(0.095, 0)
		scrap.Rotation = (i - 2) * 6 + 8
		scrap.Visible = false
		scrap.Parent = bg
		local sp = Instance.new("Frame")
		sp.BackgroundColor3 = RED
		sp.BorderSizePixel = 0
		sp.Size = UDim2.fromScale(0.3, 0.5)
		sp.Position = UDim2.fromScale(0.35, 0.1)
		sp.Parent = scrap
		n.scrap = scrap
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
	local q = quests and quests.pick and quests.list and quests.list[quests.pick]
	local def = q and Config.QuestById[q.id]
	return def ~= nil and not q.claimed and q.n >= def.goal
end

local function render()
	if not header then
		return
	end
	local list = (quests and quests.list) or {}
	local pick = quests and quests.pick
	local handedIn = false
	for i, n in ipairs(notes) do
		local q = list[i]
		local def = q and Config.QuestById[q.id]
		local mine = pick == i
		-- (once you've picked, the others are torn off: just a scrap left)
		n.frame.Visible = def ~= nil and (not pick or mine or ripping[i] == true)
		if not ripping[i] then
			n.scrap.Visible = def ~= nil and pick ~= nil and not mine
		end
		if def then
			local done = q.n >= def.goal
			n.text.Text = Config.questText(def)
			local filled = mine and math.floor(q.n / def.goal * 10 + 1e-6) or 0
			for b, blk in ipairs(n.blocks) do
				blk.BackgroundColor3 = (b <= filled) and (done and GREEN or GOLD) or RGB(58, 68, 102)
			end
			n.count.Text = mine and (Config.format(q.n) .. " / " .. Config.format(def.goal)) or ""
			n.reward.Text = Config.format(def.reward) .. " coins"
			n.frame.BackgroundColor3 = (mine and q.claimed) and PAPER_DONE or PAPER
			n.stamp.Visible = mine and q.claimed or false
			if not pick then
				n.button.Text = "PICK"
				n.button.BackgroundColor3 = GOLD
				n.button.TextColor3 = RGB(24, 20, 37)
				n.button.AutoButtonColor = true
				n.button.Visible = true
			elseif not mine then
				n.button.Visible = false
			elseif q.claimed then
				handedIn = true
				n.button.Visible = false
			elseif done then
				n.button.Text = "HAND IN!"
				n.button.BackgroundColor3 = GREEN
				n.button.TextColor3 = RGB(255, 255, 255)
				n.button.AutoButtonColor = true
				n.button.Visible = true
			else
				n.button.Text = "IN PROGRESS"
				n.button.BackgroundColor3 = RGB(58, 68, 102)
				n.button.TextColor3 = GREY
				n.button.AutoButtonColor = false
				n.button.Visible = true
			end
		end
	end
	if not pick then
		footer.Text = "Pick ONE quest for today!  New quests in " .. timeLeft()
	elseif handedIn then
		footer.Text = "Done for today!  New quests in " .. timeLeft()
	else
		footer.Text = "Finish it, then hand it in here.  New quests in " .. timeLeft()
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

-- The quest tab on the right of the screen (like Blox Fruits): what to do,
-- how far along you are, and what it pays - plus a small WAVE box at the top.
local tracker = Instance.new("ScreenGui")
tracker.Name = "ColosseumHud"
tracker.ResetOnSpawn = false
tracker.Enabled = false
tracker.Parent = player:WaitForChild("PlayerGui")

local box = Instance.new("Frame")
box.Name = "QuestTab"
box.BackgroundColor3 = RGB(12, 10, 20)
box.BackgroundTransparency = 0.1
box.BorderSizePixel = 0
box.AnchorPoint = Vector2.new(1, 0.5)
box.Position = UDim2.new(1, -16, 0.42, 0)
box.Size = UDim2.fromOffset(270, 172)
box.Parent = tracker
local boxEdge = Instance.new("UIStroke")
boxEdge.Color = RGB(255, 255, 255)
boxEdge.Thickness = 3
boxEdge.Parent = box

local head = Instance.new("Frame")
head.BackgroundColor3 = GOLD
head.BorderSizePixel = 0
head.Size = UDim2.new(1, 0, 0, 30)
head.Parent = box
label(head, "QUEST", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3), RGB(24, 20, 37), Enum.TextXAlignment.Left)
local questLabel = label(box, "Defeat 10 Straw Dummies", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 38), RGB(255, 255, 255), Enum.TextXAlignment.Left)
local countLabel = label(box, "(0/10)", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 62), GOLD, Enum.TextXAlignment.Left)
local qbar = Instance.new("Frame")
qbar.BackgroundColor3 = RGB(38, 43, 68)
qbar.BorderSizePixel = 0
qbar.Position = UDim2.fromOffset(10, 92)
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
label(box, "Reward:", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 110), GREY, Enum.TextXAlignment.Left)
local xpLabel = label(box, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 128), GREEN, Enum.TextXAlignment.Left)
local coinLabel = label(box, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 148), GOLD, Enum.TextXAlignment.Left)

local waveBox = Instance.new("Frame")
waveBox.BackgroundColor3 = RGB(12, 10, 20)
waveBox.BackgroundTransparency = 0.1
waveBox.BorderSizePixel = 0
waveBox.AnchorPoint = Vector2.new(0.5, 0)
waveBox.Position = UDim2.new(0.5, 0, 0, 12)
waveBox.Size = UDim2.fromOffset(200, 34)
waveBox.Parent = tracker
local waveEdge = Instance.new("UIStroke")
waveEdge.Color = RGB(255, 255, 255)
waveEdge.Thickness = 3
waveEdge.Parent = waveBox
local waveLabel = label(waveBox, "WAVE 1", UDim2.new(1, -16, 1, -8), UDim2.fromOffset(8, 4), RGB(255, 255, 255))

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

-- "+12 XP / +9 coins" floating up out of each dummy you beat
local function popReward(xp, coins, at)
	if typeof(at) ~= "Vector3" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 64)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor
	local l1 = label(bb, "+" .. Config.format(xp) .. " XP", UDim2.new(1, 0, 0.5, 0), UDim2.new(), GREEN)
	local l2 = label(bb, "+" .. Config.format(coins) .. " coins", UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, 0.5), GOLD)
	for _, l in ipairs({ l1, l2 }) do
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = RGB(24, 20, 37)
		st.Parent = l
	end
	task.spawn(function()
		for k = 1, 24 do
			anchor.CFrame = CFrame.new(at + Vector3.new(0, k * 0.25, 0))
			if k > 12 then
				l1.TextTransparency = (k - 12) / 12
				l2.TextTransparency = (k - 12) / 12
			end
			task.wait(1 / 20)
		end
		anchor:Destroy()
	end)
end

local function renderTracker(st)
	waveLabel.Text = "WAVE " .. tostring(math.max(1, st.wave or 0))
	local q, goal = st.quest or 0, st.goal or 10
	questLabel.Text = "Defeat " .. goal .. " Straw Dummies"
	countLabel.Text = "(" .. q .. "/" .. goal .. ")"
	local filled = math.floor(q / goal * 10 + 1e-6)
	for b, blk in ipairs(qblocks) do
		blk.BackgroundColor3 = (b <= filled) and GOLD or RGB(58, 68, 102)
	end
	xpLabel.Text = Config.format(st.questPower or 0) .. " XP"
	coinLabel.Text = Config.format(st.questCoins or 0) .. " coins"
end

local function syncTracker()
	tracker.Enabled = player:GetAttribute("Colosseum") == true
end
player:GetAttributeChangedSignal("Colosseum"):Connect(syncTracker)
syncTracker()

-- Confetti: when you clear a wave the crowd throws it from every side of
-- the stands - chunky 8-bit squares that arc into the arena, tumbling, and
-- flutter down. Only on your screen (it's your fight).
local CONFETTI = { RGB(228, 59, 68), RGB(254, 174, 52), RGB(254, 231, 97), RGB(99, 199, 77), RGB(0, 153, 219), RGB(44, 232, 245), RGB(181, 80, 136), RGB(255, 255, 255) }
local function confetti()
	local CC0 = Config.Colosseum
	local c = CC0.Center
	local pieces = {}
	local rngC = Random.new()
	for _ = 1, 140 do
		local a = rngC:NextNumber() * math.pi * 2
		local r = CC0.Radius + rngC:NextNumber(6, 20)
		local from = c + Vector3.new(math.cos(a) * r, rngC:NextNumber(12, 26), math.sin(a) * r)
		-- thrown up and in, towards the middle
		local inward = Vector3.new(-math.cos(a), 0, -math.sin(a))
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = CONFETTI[rngC:NextInteger(1, #CONFETTI)]
		p.Size = Vector3.new(0.9, 0.9, 0.12)
		p.CFrame = CFrame.new(from)
		p.Parent = workspace
		pieces[#pieces + 1] = {
			part = p,
			pos = from,
			vel = inward * rngC:NextNumber(18, 34) + Vector3.new(0, rngC:NextNumber(18, 30), 0),
			spin = Vector3.new(rngC:NextNumber(-8, 8), rngC:NextNumber(-8, 8), rngC:NextNumber(-8, 8)),
			rot = Vector3.zero,
			delay = rngC:NextNumber(0, 0.5),
		}
	end
	-- moved 20 times a second (a little 8-bit), for about four seconds
	local t = 0
	while t < 4.2 do
		local dt = task.wait(1 / 20)
		t += dt
		for _, pc in ipairs(pieces) do
			if t >= pc.delay then
				pc.vel = pc.vel + Vector3.new(0, -26 * dt, 0)
				pc.vel = pc.vel * (1 - 1.6 * dt) -- (paper: the air slows it right down)
				pc.pos = pc.pos + pc.vel * dt
				pc.rot = pc.rot + pc.spin * dt
				if pc.pos.Y < c.Y + 0.2 then
					pc.pos = Vector3.new(pc.pos.X, c.Y + 0.2, pc.pos.Z)
					pc.vel = Vector3.zero
					pc.spin = Vector3.zero
				end
				pc.part.CFrame = CFrame.new(pc.pos) * CFrame.Angles(pc.rot.X, pc.rot.Y, pc.rot.Z)
				if t > 3.2 then
					pc.part.Transparency = (t - 3.2) / 1
				end
			end
		end
	end
	for _, pc in ipairs(pieces) do
		pc.part:Destroy()
	end
end

-- Down the pipe: you shrink, bit by bit (8-bit steps), sliding into the
-- mini colosseum's little door - then you're inside the Colosseum, already
-- small enough for it, so no growing there. Coming out, you pop out of the
-- little door tiny and grow back. Done here, on your own screen, because
-- your character is moved by your computer (the server doing it glitched).
local CC = Config.Colosseum
local function scaleTo(char, s)
	pcall(function()
		char:ScaleTo(s)
	end)
end
-- feet on `ground`, facing `look`
local function standAt(char, root, ground, look)
	local box, size = char:GetBoundingBox()
	local up = root.Position.Y - (box.Position.Y - size.Y / 2)
	local p = ground + Vector3.new(0, up + 0.05, 0)
	local f = Vector3.new(look.X, 0, look.Z)
	root.CFrame = f.Magnitude > 0.01 and CFrame.lookAt(p, p + f) or CFrame.new(p) * root.CFrame.Rotation
end
local function groundUnder(pos, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	return hit and hit.Position or pos
end

local piping = false
local function pipeIn(doorGround, destCF, destGround)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or piping then
		return
	end
	piping = true
	root.Anchored = true
	local from = groundUnder(root.Position, char)
	local look = doorGround - from
	local steps = CC.ShrinkSteps or 8
	for k = 1, steps do
		if not char.Parent then
			break
		end
		local t = k / steps
		scaleTo(char, 1 - (1 - (CC.ShrinkTo or 0.3)) * t)
		standAt(char, root, from:Lerp(doorGround, t), look)
		task.wait(0.07)
	end
	task.wait(0.12)
	if char.Parent then
		scaleTo(char, 1)
		standAt(char, root, destGround, destCF.LookVector)
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = false
	end
	piping = false
end

local function pipeOut(backCF, backGround)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or piping then
		return
	end
	piping = true
	root.Anchored = true
	local steps = CC.ShrinkSteps or 8
	local small = CC.ShrinkTo or 0.3
	for k = 0, steps do
		if not char.Parent then
			break
		end
		scaleTo(char, small + (1 - small) * k / steps)
		standAt(char, root, backGround, backCF.LookVector)
		task.wait(0.05)
	end
	if char.Parent then
		scaleTo(char, 1)
		standAt(char, root, backGround, backCF.LookVector)
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = false
	end
	piping = false
end

ReplicatedStorage:WaitForChild("ColosseumEvent", 60).OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "PipeIn" then
		task.spawn(pipeIn, a, b, c)
	elseif kind == "PipeOut" then
		task.spawn(pipeOut, a, b)
	elseif kind == "State" and type(a) == "table" then
		renderTracker(a)
	elseif kind == "Arrived" then
		showBanner("THE COLOSSEUM", GOLD, 1.8)
	elseif kind == "Wave" then
		showBanner("WAVE " .. tostring(a), RGB(255, 255, 255), 1.4)
	elseif kind == "Kill" then
		popReward(a, b, c)
	elseif kind == "WaveClear" then
		showBanner("WAVE " .. tostring(a) .. " CLEARED!", GOLD, 1.8)
		task.spawn(confetti)
	elseif kind == "QuestDone" then
		showBanner("QUEST COMPLETE!  +" .. Config.format(a) .. " XP  +" .. Config.format(b) .. " coins", GREEN, 2.6)
	end
end)

----------------------------------------------------------------------
-- Never stuck in the floor after respawning
----------------------------------------------------------------------
-- If a new body turns up sunk into the ground (it happened after dying in
-- the Colosseum), lift it out and stand it on top. For the first 10 seconds
-- of every life we check where the body SHOULD be - its hip height above the
-- floor under it - and lift it if it's more than a stud too low.
player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and root) then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	for _ = 1, 40 do
		task.wait(0.25)
		if not char.Parent or hum.Health <= 0 then
			return
		end
		params.FilterDescendantsInstances = { char }
		-- the floor under us, looking down from well above our head
		local hit = workspace:Raycast(root.Position + Vector3.new(0, 10, 0), Vector3.new(0, -16, 0), params)
		if hit then
			local hip = (hum.RigType == Enum.HumanoidRigType.R6) and 2 or math.max(hum.HipHeight, 0.5)
			local want = hit.Position.Y + hip + root.Size.Y / 2
			if root.Position.Y < want - 1 then
				root.AssemblyLinearVelocity = Vector3.zero
				char:PivotTo(char:GetPivot() + Vector3.new(0, want - root.Position.Y + 0.1, 0))
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end)
