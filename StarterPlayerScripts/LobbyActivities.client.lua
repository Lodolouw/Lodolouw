--[[
	LobbyActivities  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "LobbyActivities")

	Your side of two things to do in the lobby:

	  * THE QUEST BOARD - walk up to the wooden board by the south road and
	    press E: a quest menu opens with today's three quests - what to do,
	    how far along you are, the reward, and a HAND IN button once it's
	    done. It closes with the X, or when you walk away. A gold "!" bobs
	    over the board while you have one to hand in.

	  * THE COLOSSEUM - hides other players' dummies (everyone farms on their
	    own), and shows the wave and the quest (BEAT 5 WAVES) on the screen.
	    Every dummy you beat bursts into gold coins and green XP gems that
	    fly into you, ticking as they land and bumping your coin counter
	    and level bar.

	  * THE BOSS WAVE - the Giant Straw King's boss bar across the top of the
	    screen, the BOSS WAVE banner, the ground shaking when he lands, and
	    his sounds and music (his introduction and talking are in BossIntro).

	  * RUNS AND STREAKS - "WAVE 3/5", your kill streak beside it, and when
	    the King falls the COLOSSEUM CLEARED screen: your time, your best,
	    runs cleared, the quest's reward, the day's first-clear bonus, the
	    difficulty for the next run, and RUN AGAIN / LEAVE.

	  * DIFFICULTY - press E at the DIFFICULTY board by the Colosseum's exit
	    gate to pick Normal, Hard or Nightmare (the board's plaques show,
	    on your screen, which you've picked and which are still locked).

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
local questLabel = label(box, "Beat 5 Waves", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 38), RGB(255, 255, 255), Enum.TextXAlignment.Left)
local countLabel = label(box, "(0/5)", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 62), GOLD, Enum.TextXAlignment.Left)
local qbar = Instance.new("Frame")
qbar.BackgroundColor3 = RGB(38, 43, 68)
qbar.BorderSizePixel = 0
qbar.Position = UDim2.fromOffset(10, 92)
qbar.Size = UDim2.new(1, -20, 0, 12)
qbar.Parent = box
-- one chunky block per wave (8-bit)
local qblocks = {}
local function setBlocks(n)
	n = math.clamp(n, 1, 10)
	if #qblocks == n then
		return
	end
	for _, blk in ipairs(qblocks) do
		blk:Destroy()
	end
	table.clear(qblocks)
	for b = 1, n do
		local blk = Instance.new("Frame")
		blk.BorderSizePixel = 0
		blk.Size = UDim2.new(1 / n, -2, 1, -4)
		blk.Position = UDim2.new((b - 1) / n, 1, 0, 2)
		blk.Parent = qbar
		qblocks[b] = blk
	end
end
setBlocks(Config.Colosseum.QuestWaves or 5)
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

-- your kill streak, beside the wave box (hidden until you have one)
local streakBox = Instance.new("Frame")
streakBox.Name = "StreakBox"
streakBox.BackgroundColor3 = RGB(12, 10, 20)
streakBox.BackgroundTransparency = 0.1
streakBox.BorderSizePixel = 0
streakBox.AnchorPoint = Vector2.new(0, 0)
streakBox.Position = UDim2.new(0.5, 112, 0, 12)
streakBox.Size = UDim2.fromOffset(150, 34)
streakBox.Visible = false
streakBox.Parent = tracker
local streakEdge = Instance.new("UIStroke")
streakEdge.Color = GOLD
streakEdge.Thickness = 3
streakEdge.Parent = streakBox
local streakLabel = label(streakBox, "", UDim2.new(1, -12, 1, -8), UDim2.fromOffset(6, 4), GOLD)

-- a colour as RichText wants it ("#F77622")
local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
-- (Normal needs no label: only the harder difficulties show theirs)
local function isFirstDifficulty(id)
	local first = (Config.Colosseum.Difficulties or {})[1]
	return first == nil or first.id == Config.colosseumDifficulty(id).id
end

local runLength = nil -- (waves in a run, from the server)
local runDiff = nil -- (this run's difficulty, from the server)
local function renderTracker(st)
	runLength = st.of
	runDiff = st.diff
	local n = tostring(math.max(1, st.wave or 0)) .. (st.of and ("/" .. tostring(st.of)) or "")
	-- the difficulty, after the wave in its colour ("WAVE 3/5  HARD"), and
	-- the box's border in its colour too (white on Normal)
	local D = Config.colosseumDifficulty(st.diff)
	local tag = ""
	if not isFirstDifficulty(D.id) then
		tag = '  <font color="' .. hex(D.color) .. '">' .. D.name .. "</font>"
	end
	waveLabel.RichText = true
	if st.cleared then
		waveLabel.Text = "CLEARED!" .. tag
		waveLabel.TextColor3 = GOLD
	else
		waveLabel.Text = (st.boss and "BOSS WAVE" or ("WAVE " .. n)) .. tag
		waveLabel.TextColor3 = st.boss and RED or RGB(255, 255, 255)
	end
	local wide = (tag ~= "") and (D.name:len() > 5 and 300 or 260) or 200
	waveBox.Size = UDim2.fromOffset(wide, 34)
	waveEdge.Color = (tag ~= "") and D.color or RGB(255, 255, 255)
	streakBox.Position = UDim2.new(0.5, wide / 2 + 12, 0, 12)
	local streak = st.streak or 0
	streakBox.Visible = streak > 0
	if streak > 0 then
		local bonus = math.floor((st.streakBonus or 0) * 100 + 0.5)
		streakLabel.Text = "x" .. streak .. " STREAK" .. (bonus > 0 and ("  +" .. bonus .. "%") or "")
	end
	-- THE QUEST: beat 5 waves (a whole run)
	local goal = math.max(1, st.goal or 5)
	local q = math.clamp(st.quest or 0, 0, goal)
	local done = q >= goal
	questLabel.Text = "Beat " .. goal .. " Waves"
	countLabel.Text = "(" .. q .. "/" .. goal .. ")" .. (done and "  DONE!" or "")
	countLabel.TextColor3 = done and GREEN or GOLD
	setBlocks(goal)
	for b, blk in ipairs(qblocks) do
		blk.BackgroundColor3 = (b <= q) and (done and GREEN or GOLD) or RGB(58, 68, 102)
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

-- A Sound from SoundService, played flat on your screen: the first on the
-- list that's there (capitals and spaces don't matter, so "Mario Pipe" and
-- "mariopipe" are the same). Nothing plays if none of them are there.
local function squashName(name)
	return string.lower((string.gsub(tostring(name), "%s+", "")))
end
local function findNamedSound(names)
	if type(names) == "string" then
		names = { names }
	end
	local SoundService = game:GetService("SoundService")
	for _, name in ipairs(names or {}) do
		for _, child in ipairs(SoundService:GetChildren()) do
			if child:IsA("Sound") and squashName(child.Name) == squashName(name) then
				return child
			end
		end
	end
	return nil
end
-- Fades a playing sound out and stops it (so a long sound always fits the
-- moment it's for: the pipe, the whirlwind...)
local function fadeOutSound(snd, after, seconds)
	if not snd then
		return
	end
	task.delay(after or 0, function()
		if not snd.Parent or not snd.IsPlaying then
			return
		end
		local start = snd.Volume
		local steps = 8
		for k = 1, steps do
			snd.Volume = start * (1 - k / steps)
			task.wait((seconds or 0.25) / steps)
		end
		snd:Stop()
	end)
end
local function playNamedSound(names, volume)
	local template = findNamedSound(names)
	if not template then
		return nil
	end
	local snd = template:Clone()
	snd.Looped = false
	snd.Volume = template.Volume * (volume or 1)
	local effects = game:GetService("SoundService"):FindFirstChild("Effects")
	if effects and effects:IsA("SoundGroup") then
		snd.SoundGroup = effects
	end
	snd.Parent = game:GetService("SoundService")
	snd:Play()
	task.delay(6, function()
		snd:Destroy()
	end)
	return snd
end

-- WARMING UP: the Colosseum's sounds (the pipe, the King's sounds and his
-- music) are loaded a couple of seconds after you join, in the background,
-- so none of them stalls or plays silent the first time it's needed.
task.delay(2, function()
	local list, seen = {}, {}
	local function add(names)
		if type(names) == "string" then
			names = { names }
		end
		for _, name in ipairs(names or {}) do
			local snd = findNamedSound(name)
			if snd and not seen[snd] then
				seen[snd] = true
				list[#list + 1] = snd
			end
		end
	end
	add(Config.Colosseum.PipeSound)
	for _, def in pairs(Config.Colosseum.Sounds or {}) do
		add(def.names)
	end
	add(Config.Colosseum.CrowdSound)
	add(Config.Colosseum.Music)
	local K = Config.Colosseum.King
	if K then
		for _, names in pairs(K.Sounds or {}) do
			add(names)
		end
		add(K.Music)
	end
	add((Config.Retro and Config.Retro.TypeBlip) or "UI Blip") -- (his talking)
	if #list > 0 then
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end

	-- THE SOUND REPORT (in the Output window, F9 in game): for every sound
	-- the Colosseum uses, which Sound it found in SoundService - or that none
	-- is there, or that it's there but didn't load (usually a Toolbox sound
	-- that's private to someone else: Roblox plays those silently)
	local function report(label, names)
		local snd = findNamedSound(names)
		local wanted = table.concat(type(names) == "table" and names or { tostring(names) }, '" or "')
		if not snd then
			print("[Colosseum sounds] " .. label .. ': MISSING - add a Sound named "' .. wanted .. '" to SoundService')
		elseif tostring(snd.SoundId or "") == "" then
			warn("[Colosseum sounds] " .. label .. ': "' .. snd.Name .. '" has no SoundId - paste one in')
		elseif not snd.IsLoaded or (tonumber(snd.TimeLength) or 0) <= 0 then
			warn("[Colosseum sounds] " .. label .. ': "' .. snd.Name .. '" (' .. tostring(snd.SoundId) .. ") DIDN'T LOAD - probably private: pick a sound made by Roblox, or upload your own")
		else
			print("[Colosseum sounds] " .. label .. ': OK - "' .. snd.Name .. '" (' .. string.format("%.1f", tonumber(snd.TimeLength) or 0) .. "s)")
		end
	end
	report("Pipe", Config.Colosseum.PipeSound)
	for key, def in pairs(Config.Colosseum.Sounds or {}) do
		report(key, def.names)
	end
	report("Crowd", Config.Colosseum.CrowdSound)
	report("Colosseum music", Config.Colosseum.Music)
	if K then
		for key, names in pairs(K.Sounds or {}) do
			report("King " .. key, names)
		end
		report("King music", K.Music)
	end
end)

local piping = false
local function pipeIn(doorGround, destCF, destGround)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or piping then
		return
	end
	piping = true
	root.Anchored = true
	local pipeSound = playNamedSound(CC.PipeSound, CC.PipeVolume) -- (the Mario pipe sound)
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
	fadeOutSound(pipeSound, 0, 0.25) -- (the sound ends as you arrive, however long it is)
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
	local pipeSound = playNamedSound(CC.PipeSound, CC.PipeVolume) -- (the Mario pipe sound, popping out)
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
	fadeOutSound(pipeSound, 0, 0.25) -- (the sound ends as you arrive, however long it is)
	piping = false
end

----------------------------------------------------------------------
-- The boss wave: the Giant Straw King
----------------------------------------------------------------------
-- Every few waves the King drops in on his own. This is your screen's side:
--   * his boss bar across the top: name, level and health in chunky 8-bit
--     segments, with a pale chunk showing what your last hits knocked off
--   * the ground shaking when he lands (through CombatClient's camera kick,
--     so only one script ever moves the camera)
--   * his sounds and his fight's music, played by name from SoundService
--     (Config.Colosseum.King.Sounds and .Music) - the lobby's music steps
--     aside while his plays
-- (His introduction and his talking are in BossIntro.)
local KingHud = {}
do
	local K = Config.Colosseum.King or {}
	local SoundService = game:GetService("SoundService")
	local TITLE_FACE = nil
	pcall(function()
		TITLE_FACE = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	local DARK = RGB(24, 20, 37)

	-- a Sound in SoundService: the first on the list that's there (capitals
	-- and spaces don't matter, so "Boss Slam" and "bossslam" are the same)
	local function squash(name)
		return string.lower((string.gsub(tostring(name), "%s+", "")))
	end
	local function findSound(names)
		if type(names) == "string" then
			names = { names }
		end
		for _, name in ipairs(names or {}) do
			local key = squash(name)
			for _, child in ipairs(SoundService:GetChildren()) do
				if child:IsA("Sound") and squash(child.Name) == key then
					return child
				end
			end
		end
		return nil
	end
	local function group(name, volume)
		local g = SoundService:FindFirstChild(name)
		if not (g and g:IsA("SoundGroup")) then
			g = Instance.new("SoundGroup")
			g.Name = name
			g.Volume = volume or 1
			g.Parent = SoundService
		end
		return g
	end

	-- one of his sounds, played flat (the same wherever you stand)
	function KingHud.play(key, volume)
		local template = findSound(K.Sounds and K.Sounds[key])
		if not template then
			return
		end
		local snd = template:Clone()
		snd.Looped = false
		snd.Volume = template.Volume * (volume or 1) * ((Config.Audio and Config.Audio.BossSounds) or 0.85)
		snd.SoundGroup = group("Effects", (Config.Audio and Config.Audio.Effects) or 1)
		snd.Parent = SoundService
		snd:Play()
		task.delay(8, function()
			snd:Destroy()
		end)
		return snd
	end

	-- one of the Colosseum's sounds (Config.Colosseum.Sounds), quieter the
	-- further from you it happens
	function KingHud.sfx(key, at)
		local def = Config.Colosseum.Sounds and Config.Colosseum.Sounds[key]
		local template = def and findSound(def.names)
		if not template then
			return
		end
		local volume = def.volume or 1
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and typeof(at) == "Vector3" then
			volume = volume * math.clamp(1.2 - (root.Position - at).Magnitude / 110, 0.35, 1)
		end
		local snd = template:Clone()
		snd.Looped = false
		snd.Volume = template.Volume * volume
		snd.SoundGroup = group("Effects", (Config.Audio and Config.Audio.Effects) or 1)
		snd.Parent = SoundService
		snd:Play()
		task.delay(6, function()
			snd:Destroy()
		end)
	end

	-- the ground shaking (smaller the further away it happens)
	function KingHud.shake(strength, at)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and typeof(at) == "Vector3" then
			strength = strength * math.clamp(1.15 - (root.Position - at).Magnitude / 120, 0.25, 1)
		end
		local scripts = player:FindFirstChild("PlayerScripts")
		local kick = scripts and scripts:FindFirstChild("CombatCameraKick")
		if kick and kick:IsA("BindableEvent") then
			kick:Fire(strength)
		end
	end

	-- THE BOSS BAR (styled here in the game's 8-bit look, so RetroUI leaves it be)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ColosseumBossBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui:SetAttribute("RetroSkip", true)
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 58)
	holder.Size = UDim2.new(0.5, 0, 0, 46)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 46)
	limit.MaxSize = Vector2.new(720, 46)
	limit.Parent = holder
	local pop = Instance.new("UIScale")
	pop.Parent = holder

	local function pixelText(str, size, pos, color, align)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = size
		l.Position = pos
		l.Font = Enum.Font.Arcade
		if TITLE_FACE then
			pcall(function()
				l.FontFace = TITLE_FACE
			end)
		end
		l.Text = str
		l.TextColor3 = color
		l.TextScaled = true
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.TextStrokeColor3 = DARK
		l.TextStrokeTransparency = 0
		l.Parent = holder
		return l
	end
	local nameLabel = pixelText(string.upper(K.name or "Giant Straw King"), UDim2.new(0.72, 0, 0, 17), UDim2.new(0, 0, 0, 0), GOLD)
	local levelLabel = pixelText("", UDim2.new(0.28, 0, 0, 13), UDim2.new(0.72, 0, 0, 3), RGB(255, 255, 255), Enum.TextXAlignment.Right)

	local back = Instance.new("Frame")
	back.Position = UDim2.new(0, 0, 0, 24)
	back.Size = UDim2.new(1, 0, 0, 18)
	back.BackgroundColor3 = DARK
	back.BorderSizePixel = 0
	back.Parent = holder
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(255, 255, 255)
	edge.Thickness = 3
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	edge.Parent = back
	local chip = Instance.new("Frame") -- (the pale chunk your last hits knocked off)
	chip.BackgroundColor3 = RGB(254, 231, 97)
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 1
	chip.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = RED
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 2
	fill.Parent = back
	local shine = Instance.new("Frame") -- (a lighter stripe along the top: pixel shading)
	shine.BackgroundColor3 = RGB(246, 117, 122)
	shine.BorderSizePixel = 0
	shine.Size = UDim2.new(1, 0, 0, 4)
	shine.ZIndex = 2
	shine.Parent = fill
	for i = 1, 19 do -- (split into 20 chunky segments)
		local tick = Instance.new("Frame")
		tick.BackgroundColor3 = DARK
		tick.BorderSizePixel = 0
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(i / 20, 0)
		tick.Size = UDim2.new(0, 2, 1, 0)
		tick.ZIndex = 3
		tick.Parent = back
	end

	local king = nil -- your King, while he's on the sand
	local shown, chipShare, chipHold = 1, 1, 0
	local goneAt = nil
	local function healthShare(m)
		if not m.Parent then
			return 0
		end
		return math.clamp((m:GetAttribute("Health") or 0) / math.max(m:GetAttribute("MaxHealth") or 1, 1), 0, 1)
	end
	local function track(m)
		king = m
		goneAt = nil
		shown = healthShare(m)
		chipShare = shown
		levelLabel.Text = "LV " .. tostring(m:GetAttribute("Level") or "?")
		nameLabel.TextColor3 = GOLD
		gui.Enabled = true
		-- (the bar pops in)
		task.spawn(function()
			for k = 0, 6 do
				pop.Scale = 0.7 + 0.3 * (k / 6) + math.sin(k / 6 * math.pi) * 0.08
				task.wait(1 / 30)
			end
			pop.Scale = 1
		end)
	end
	local function consider(m)
		if m:IsA("Model") and m:GetAttribute("Kind") == "King" and m:GetAttribute("Owner") == player.UserId then
			track(m)
		end
	end
	task.spawn(function()
		local folder = workspace:WaitForChild("ColosseumEnemies", 60)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				consider(m)
			end
			folder.ChildAdded:Connect(consider)
		end
	end)

	-- HIS MUSIC (a SoundGroup of its own, so turning the lobby's down leaves it be)
	local ducked = false
	local musicGroup = group("KingMusic", (Config.Audio and Config.Audio.Music) or 1)
	local CC0 = Config.Colosseum
	local tracks = {
		king = { names = K.Music, volume = K.MusicVolume or 0.6, name = "KingMusicPlaying", group = musicGroup, music = true, level = 0 },
		arena = { names = CC0.Music, volume = CC0.MusicVolume or 0.45, name = "ColosseumMusicPlaying", group = musicGroup, music = true, level = 0 },
		crowd = { names = CC0.CrowdSound, volume = CC0.CrowdVolume or 0.25, name = "ColosseumCrowdPlaying", group = group("Effects", (Config.Audio and Config.Audio.Effects) or 1), level = 0 },
	}

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local m = king
		local fighting = false
		if m then
			local share = healthShare(m)
			local state = m:GetAttribute("State")
			fighting = m.Parent ~= nil and share > 0 and (state == "Waking" or state == "Fighting")
			if share < shown - 1e-4 then
				chipHold = now + 0.5 -- (the pale chunk waits a moment, then drains)
			end
			shown = share
			if now > chipHold then
				chipShare = math.max(share, chipShare - 0.8 * dt)
			end
			chipShare = math.max(chipShare, share)
			fill.Size = UDim2.fromScale(shown, 1)
			chip.Size = UDim2.fromScale(chipShare, 1)
			-- angry: the bar throbs a deeper red, and his name turns red
			if m:GetAttribute("Phase") == 2 then
				local beat = (math.floor(now * 4) % 2 == 0)
				fill.BackgroundColor3 = beat and RGB(255, 0, 68) or RGB(162, 38, 51)
				nameLabel.TextColor3 = RED
			else
				fill.BackgroundColor3 = RED
			end
			-- beaten (or gone): the bar stays a moment, empty, then goes
			if share <= 0 or not m.Parent then
				goneAt = goneAt or now
				if now - goneAt > 2 then
					king = nil
					gui.Enabled = false
				end
			end
		end

		-- THE MUSIC AND THE CROWD. Each is a looping track that fades in when
		-- it's wanted and out when it isn't (in over about a second, out over
		-- about two):
		--   the King's song    - during his fight
		--   the Colosseum song - the rest of the time you're in there (it
		--                        keeps its place under his, and carries on after)
		--   the crowd          - murmuring in the stands the whole time
		local inside = player:GetAttribute("Colosseum") == true
		local want = { king = fighting, arena = inside and not fighting, crowd = inside }
		local duck = 0
		for key, tr in pairs(tracks) do
			local on = want[key]
			if on and not tr.sound then
				local template = findSound(tr.names)
				if template then
					tr.sound = template:Clone()
					tr.sound.Name = tr.name
					tr.sound.Looped = true
					tr.sound.Volume = 0
					tr.sound.SoundGroup = tr.group
					tr.sound.Parent = SoundService
					tr.sound:Play()
				end
			end
			tr.level = tr.level + ((on and 1 or 0) - tr.level) * math.min(1, dt * (on and 1.5 or 1.8))
			if tr.sound then
				tr.sound.Volume = tr.volume * tr.level
				-- (gone once it's faded out - except the Colosseum song while
				-- you're still in there: it waits, silent, under the King's)
				if not on and tr.level < 0.02 and not (key == "arena" and inside) then
					tr.sound:Destroy()
					tr.sound = nil
				elseif tr.music then
					duck = math.max(duck, tr.level)
				end
			end
		end
		-- the lobby's music (the "Music" SoundGroup) fades out under ours
		local lobby = SoundService:FindFirstChild("Music")
		if lobby and lobby:IsA("SoundGroup") then
			local full = (Config.Audio and Config.Audio.Music) or 1
			if duck > 0 then
				lobby.Volume = full * (1 - duck)
				ducked = true
			elseif ducked then
				lobby.Volume = full
				ducked = false
			end
		end
	end)
end

----------------------------------------------------------------------
-- Difficulty: Normal, Hard, Nightmare
----------------------------------------------------------------------
-- What the server says about your Colosseum runs (data.Colosseum: the
-- difficulty you've picked, and the runs you've cleared and your best time
-- on each one), and asking it to change the pick. The DIFFICULTY board's
-- menu, the board's plaques and the CLEARED screen all use these.
local colData = nil
local Difficulty = { listeners = {} }
do
	local function num(x)
		return string.format("%g", x)
	end
	local function clock(seconds)
		seconds = tonumber(seconds) or 0
		local m = math.floor(seconds / 60)
		return string.format("%d:%04.1f", m, seconds - m * 60)
	end
	Difficulty.clock = clock

	function Difficulty.list()
		return Config.Colosseum.Difficulties or {}
	end
	-- the one your next run is on
	function Difficulty.picked()
		local id = colData and colData.pick
		if not Config.colosseumUnlocked(colData, id) then
			id = nil
		end
		return Config.colosseumDifficulty(id).id
	end
	function Difficulty.unlocked(id)
		return Config.colosseumUnlocked(colData, id)
	end
	-- the difficulty before this one (clear a run on it to open this one)
	function Difficulty.before(id)
		local list = Difficulty.list()
		for i, d in ipairs(list) do
			if d.id == id then
				return list[i - 1]
			end
		end
		return nil
	end
	-- your runs cleared and best time on one difficulty
	function Difficulty.record(id)
		local wins = colData and type(colData.wins) == "table" and colData.wins[id] or 0
		local best = colData and type(colData.bests) == "table" and colData.bests[id] or nil
		return wins, best
	end
	-- what it does, in a few short lines
	function Difficulty.describe(def)
		local lines = {}
		if (def.health or 1) ~= 1 then
			lines[#lines + 1] = "Dummies x" .. num(def.health) .. " tougher"
		end
		if (def.damage or 1) ~= 1 then
			lines[#lines + 1] = "They hit x" .. num(def.damage) .. " harder"
		end
		if (def.extra or 0) > 0 then
			lines[#lines + 1] = "+" .. def.extra .. (def.extra == 1 and " dummy" or " dummies") .. " every wave"
		end
		if (def.pace or 1) < 1 then
			lines[#lines + 1] = "They move faster"
		end
		if def.angry then
			lines[#lines + 1] = "The King is ANGRY"
		end
		if #lines == 0 then
			lines = { "The Colosseum", "as you know it" }
		end
		return lines
	end
	function Difficulty.payText(def)
		return "PAYS x" .. num(def.reward or 1)
	end
	-- why a locked one is locked
	function Difficulty.lockText(def)
		local prev = Difficulty.before(def.id)
		return "Clear a " .. (prev and prev.name or "") .. " run to open " .. def.name .. "!"
	end
	function Difficulty.onChange(fn)
		table.insert(Difficulty.listeners, fn)
	end
	local function changed()
		for _, fn in ipairs(Difficulty.listeners) do
			task.spawn(fn)
		end
	end

	-- asks the server to change the pick; `say(text, color)` shows its answer
	local busy = false
	function Difficulty.choose(id, say)
		local def = Config.colosseumDifficulty(id)
		if not Difficulty.unlocked(def.id) then
			say(Difficulty.lockText(def), RED)
			return
		end
		if busy then
			return
		end
		busy = true
		local ok, done, msg = pcall(function()
			return Remotes.Action:InvokeServer("ColosseumDifficulty", def.id)
		end)
		busy = false
		if not ok then
			say("Couldn't reach the server.", RED)
			return
		end
		say(tostring(msg or ""), done and GREEN or RED)
		if done and colData then
			colData.pick = def.id -- (right away: the server's snapshot follows)
			changed()
		end
	end

	-- A row of buttons, one per difficulty, filling `parent`. Returns a
	-- function that paints them: the picked one in its colour with a white
	-- border, the other open ones dark with their colour, locked ones grey.
	function Difficulty.row(parent, say)
		local list = Difficulty.list()
		local buttons = {}
		local gap = 0.03
		local w = (1 - gap * (#list - 1)) / math.max(1, #list)
		for i, def in ipairs(list) do
			local b = Instance.new("TextButton")
			b.Name = "Difficulty" .. def.id
			b.Font = FONT
			b.TextScaled = true
			b.BorderSizePixel = 0
			b.AutoButtonColor = true
			b.Size = UDim2.fromScale(w, 1)
			b.Position = UDim2.fromScale((i - 1) * (w + gap), 0)
			b.Parent = parent
			local edge = Instance.new("UIStroke")
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Thickness = 3
			edge.Parent = b
			local pad = Instance.new("UIPadding")
			pad.PaddingTop = UDim.new(0.12, 0)
			pad.PaddingBottom = UDim.new(0.12, 0)
			pad.PaddingLeft = UDim.new(0.06, 0)
			pad.PaddingRight = UDim.new(0.06, 0)
			pad.Parent = b
			b.Activated:Connect(function()
				Difficulty.choose(def.id, say)
			end)
			buttons[i] = { button = b, edge = edge, def = def }
		end
		return function()
			local picked = Difficulty.picked()
			for _, it in ipairs(buttons) do
				local def, b = it.def, it.button
				if not Difficulty.unlocked(def.id) then
					b.Text = def.name .. " (LOCKED)"
					b.BackgroundColor3 = RGB(38, 43, 68)
					b.TextColor3 = GREY
					it.edge.Color = RGB(90, 105, 136)
				elseif def.id == picked then
					b.Text = def.name
					b.BackgroundColor3 = def.color
					b.TextColor3 = RGB(255, 255, 255)
					it.edge.Color = RGB(255, 255, 255)
				else
					b.Text = def.name
					b.BackgroundColor3 = def.color:Lerp(RGB(24, 20, 37), 0.72)
					b.TextColor3 = def.color
					it.edge.Color = def.color
				end
			end
		end
	end

	Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.Colosseum) == "table" then
			colData = data.Colosseum
			changed()
		end
	end)
end

-- THE DIFFICULTY BOARD'S MENU: press E at the board by the exit gate. A card
-- for each difficulty: what it does, what it pays, your best time and runs
-- cleared on it, and PICK (or PICKED, or LOCKED with what opens it). It
-- closes with the X, or when you walk away from the board.
local DifficultyMenu = {}
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "ColosseumDifficulty"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "DifficultyPanel"
	panel.BackgroundColor3 = RGB(24, 20, 37)
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.64, 0.66)
	panel.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.7
	aspect.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(255, 255, 255)
	edge.Thickness = 4
	edge.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "X"
	close.Font = FONT
	close.TextScaled = true
	close.TextColor3 = RGB(255, 255, 255)
	close.BackgroundColor3 = RED
	close.BorderSizePixel = 0
	close.Size = UDim2.fromScale(0.06, 0.1)
	close.Position = UDim2.fromScale(0.925, 0.025)
	close.Parent = panel
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	label(panel, "CHOOSE DIFFICULTY", UDim2.fromScale(0.8, 0.1), UDim2.fromScale(0.1, 0.03), GOLD)
	local note = label(panel, "", UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.135), GREY)
	local menuStatus = label(panel, "", UDim2.fromScale(0.9, 0.05), UDim2.fromScale(0.05, 0.925), RGB(255, 255, 255))
	local statusUntilD = 0
	local function say(text, color)
		menuStatus.Text = text
		menuStatus.TextColor3 = color or RGB(255, 255, 255)
		statusUntilD = os.clock() + 3.5
	end

	local cards = {}
	local list = Difficulty.list()
	local gap = 0.025
	local w = (0.92 - gap * (#list - 1)) / math.max(1, #list)
	for i, def in ipairs(list) do
		local card = Instance.new("Frame")
		card.Name = "Card" .. def.id
		card.BackgroundColor3 = RGB(24, 20, 37)
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(w, 0.7)
		card.Position = UDim2.fromScale(0.04 + (i - 1) * (w + gap), 0.205)
		card.Parent = panel
		local ce = Instance.new("UIStroke")
		ce.Color = def.color -- (coloured: RetroUI leaves it be)
		ce.Thickness = 3
		ce.Parent = card
		local c = { def = def, frame = card, edge = ce }
		c.name = label(card, def.name, UDim2.fromScale(0.9, 0.12), UDim2.fromScale(0.05, 0.04), def.color)
		-- 1, 2 or 3 chunky pips: how hard it is
		for k = 1, i do
			local pip = Instance.new("Frame")
			pip.BorderSizePixel = 0
			pip.BackgroundColor3 = def.color
			pip.Size = UDim2.fromScale(0.08, 0.045)
			pip.Position = UDim2.fromScale(0.5 + (k - (i + 1) / 2) * 0.11 - 0.04, 0.18)
			pip.Parent = card
		end
		local lines = Difficulty.describe(def)
		for k, line in ipairs(lines) do
			label(card, line, UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.25 + (k - 1) * 0.075), RGB(255, 255, 255))
		end
		c.pay = label(card, Difficulty.payText(def), UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.05, 0.63), GOLD)
		c.record = label(card, "", UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.735), GREY)
		local b = Instance.new("TextButton")
		b.Name = "Pick"
		b.Font = FONT
		b.TextScaled = true
		b.BorderSizePixel = 0
		b.Size = UDim2.fromScale(0.8, 0.12)
		b.Position = UDim2.fromScale(0.1, 0.83)
		b.Parent = card
		b.Activated:Connect(function()
			Difficulty.choose(def.id, say)
		end)
		c.button = b
		cards[i] = c
	end

	local function refresh()
		local picked = Difficulty.picked()
		local midRun = player:GetAttribute("Colosseum") == true and runDiff ~= nil and runDiff ~= picked
		if midRun then
			note.Text = "This run is on " .. Config.colosseumDifficulty(runDiff).name .. ". " .. Config.colosseumDifficulty(picked).name .. " starts on your next run."
		else
			note.Text = "Your pick is saved, and used from your next run (straight away on wave 1)."
		end
		for _, c in ipairs(cards) do
			local def = c.def
			local open = Difficulty.unlocked(def.id)
			local wins, best = Difficulty.record(def.id)
			if not open then
				local prev = Difficulty.before(def.id)
				c.record.Text = "Clear a " .. (prev and prev.name or "") .. " run first"
				c.button.Text = "LOCKED"
				c.button.BackgroundColor3 = RGB(38, 43, 68)
				c.button.TextColor3 = GREY
				c.button.AutoButtonColor = false
				c.edge.Color = def.color -- (a coloured edge: RetroUI would turn a grey one white)
				c.name.TextColor3 = GREY
			else
				if (wins or 0) > 0 then
					c.record.Text = "CLEARED " .. Config.format(wins) .. (best and ("   BEST " .. Difficulty.clock(best)) or "")
				else
					c.record.Text = "NOT CLEARED YET"
				end
				c.edge.Color = def.color
				c.name.TextColor3 = def.color
				if def.id == picked then
					c.button.Text = "PICKED"
					c.button.BackgroundColor3 = def.color
					c.button.TextColor3 = RGB(255, 255, 255)
					c.button.AutoButtonColor = false
				else
					c.button.Text = "PICK"
					c.button.BackgroundColor3 = GOLD
					c.button.TextColor3 = RGB(24, 20, 37)
					c.button.AutoButtonColor = true
				end
			end
		end
	end
	Difficulty.onChange(refresh)

	function DifficultyMenu.open(board)
		DifficultyMenu.board = board
		menuStatus.Text = ""
		refresh()
		gui.Enabled = true
	end
	function DifficultyMenu.close()
		gui.Enabled = false
	end
	DifficultyMenu.refresh = refresh

	-- press E at the board: open the menu
	local function hookBoard(pp)
		if pp:IsA("ProximityPrompt") then
			pp.Triggered:Connect(function()
				DifficultyMenu.open(pp.Parent)
			end)
		end
	end
	for _, pp in ipairs(CollectionService:GetTagged("ColosseumDifficultyBoard")) do
		hookBoard(pp)
	end
	CollectionService:GetInstanceAddedSignal("ColosseumDifficultyBoard"):Connect(hookBoard)

	-- walk away from the board (or leave the Colosseum) and it closes
	task.spawn(function()
		while true do
			task.wait(0.3)
			if gui.Enabled then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local board = DifficultyMenu.board
				if not root or not (board and board:IsA("BasePart") and board.Parent)
					or (Vector3.new(root.Position.X - board.Position.X, 0, root.Position.Z - board.Position.Z)).Magnitude > 26 then
					gui.Enabled = false
				end
			end
			if statusUntilD > 0 and os.clock() > statusUntilD then
				statusUntilD = 0
				menuStatus.Text = ""
			end
		end
	end)
	player:GetAttributeChangedSignal("Colosseum"):Connect(function()
		if not player:GetAttribute("Colosseum") then
			gui.Enabled = false
		end
	end)

	-- THE BOARD'S PLAQUES, on your screen only: the one you've picked says
	-- PICKED, the locked ones say LOCKED (everyone else sees their own)
	local function paintPlaques()
		local picked = Difficulty.picked()
		for _, plaque in ipairs(CollectionService:GetTagged("DifficultyPlaque")) do
			local id = plaque:GetAttribute("Difficulty")
			local face = plaque:FindFirstChild("Face")
			local st = face and face:FindFirstChild("Status", true)
			if id and st and st:IsA("TextLabel") then
				if not Difficulty.unlocked(id) then
					st.Text = "LOCKED"
					st.TextColor3 = GREY
				elseif id == picked then
					st.Text = "PICKED"
					st.TextColor3 = RGB(255, 255, 255)
				else
					st.Text = ""
				end
			end
		end
	end
	Difficulty.onChange(paintPlaques)
	CollectionService:GetInstanceAddedSignal("DifficultyPlaque"):Connect(function()
		task.defer(paintPlaques)
	end)
	task.defer(paintPlaques)
end

-- COLOSSEUM CLEARED: the King fell on the last wave of a run. Your time,
-- your best, how many runs you've cleared, the quest's reward, the day's
-- first-clear bonus, a harder difficulty if this clear opened it - and a
-- choice: the difficulty for the next run, then RUN AGAIN (healed, flasks
-- refilled, back to wave 1) or LEAVE.
-- (Styled by RetroUI like the quest menu: a black box with a white border.)
local ClearScreen = {}
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "ColosseumClear"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "ClearPanel"
	panel.BackgroundColor3 = RGB(24, 20, 37)
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.44, 0.7)
	panel.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.12
	aspect.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(255, 255, 255)
	edge.Thickness = 4
	edge.Parent = panel

	label(panel, "COLOSSEUM CLEARED!", UDim2.fromScale(0.9, 0.1), UDim2.fromScale(0.05, 0.03), GOLD)
	local diffLabel = label(panel, "", UDim2.fromScale(0.6, 0.05), UDim2.fromScale(0.2, 0.13), GREEN)

	-- the lines about the run, one under another (empty ones take no room)
	local lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.Position = UDim2.fromScale(0.05, 0.195)
	lines.Size = UDim2.fromScale(0.9, 0.43)
	lines.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
	layout.Parent = lines
	local function line(order, height, color)
		local l = label(lines, "", UDim2.fromScale(1, height), UDim2.new(), color)
		l.LayoutOrder = order
		return l
	end
	local timeLabel = line(1, 0.17, RGB(255, 255, 255))
	local bestLabel = line(2, 0.14, GREY)
	local clearsLabel = line(3, 0.12, GREY)
	local questLabelC = line(4, 0.13, GREEN)
	local bonusLabel = line(5, 0.13, GOLD)
	local unlockLabel = line(6, 0.14, RED)

	label(panel, "NEXT RUN:", UDim2.fromScale(0.9, 0.04), UDim2.fromScale(0.05, 0.635), GREY)
	local statusLine = label(panel, "", UDim2.fromScale(0.9, 0.045), UDim2.fromScale(0.05, 0.775), RGB(255, 255, 255))
	local function say(text, color)
		statusLine.Text = text
		statusLine.TextColor3 = color or RGB(255, 255, 255)
	end
	local rowFrame = Instance.new("Frame")
	rowFrame.Name = "DifficultyRow"
	rowFrame.BackgroundTransparency = 1
	rowFrame.Position = UDim2.fromScale(0.05, 0.68)
	rowFrame.Size = UDim2.fromScale(0.9, 0.085)
	rowFrame.Parent = panel
	local paintRow = Difficulty.row(rowFrame, say)
	Difficulty.onChange(paintRow)

	local busy = false
	local function button(text, color, x, action)
		local b = Instance.new("TextButton")
		b.Name = action
		b.Text = text
		b.Font = FONT
		b.TextScaled = true
		b.TextColor3 = RGB(255, 255, 255)
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.Size = UDim2.fromScale(0.38, 0.12)
		b.Position = UDim2.fromScale(x, 0.84)
		b.Parent = panel
		b.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			statusLine.Text = ""
			local ok, done, msg = pcall(function()
				return Remotes.Action:InvokeServer(action)
			end)
			busy = false
			if not ok then
				say("Couldn't reach the server.", RED)
			elseif done then
				gui.Enabled = false
			else
				say(tostring(msg or ""), RED)
			end
		end)
		return b
	end
	button("RUN AGAIN", RGB(62, 137, 72), 0.07, "ColosseumAgain")
	button("LEAVE", RGB(162, 38, 51), 0.55, "ColosseumLeave")

	local function set(l, text)
		l.Text = text or ""
		l.Visible = (text or "") ~= ""
	end

	local showing = 0
	function ClearScreen.show(info)
		if type(info) ~= "table" then
			return
		end
		local D = Config.colosseumDifficulty(info.diff)
		set(diffLabel, D.name)
		diffLabel.TextColor3 = D.color
		set(timeLabel, "TIME  " .. Difficulty.clock(info.time))
		if info.newBest then
			set(bestLabel, "NEW BEST TIME!")
			bestLabel.TextColor3 = GOLD
		elseif info.best then
			set(bestLabel, "BEST  " .. Difficulty.clock(info.best))
			bestLabel.TextColor3 = GREY
		else
			set(bestLabel, "")
		end
		if info.wins then
			set(clearsLabel, D.name .. " RUNS CLEARED: " .. Config.format(info.wins))
		elseif info.clears then
			set(clearsLabel, "RUNS CLEARED: " .. Config.format(info.clears))
		else
			set(clearsLabel, "")
		end
		if info.questPower then
			set(questLabelC, "QUEST COMPLETE!  +" .. Config.format(info.questPower) .. " XP  +" .. Config.format(info.questCoins or 0) .. " coins")
		else
			set(questLabelC, "")
		end
		if info.bonusPower then
			set(bonusLabel, "FIRST CLEAR TODAY!  +" .. Config.format(info.bonusPower) .. " XP  +" .. Config.format(info.bonusCoins or 0) .. " coins")
		else
			set(bonusLabel, "")
		end
		local U = info.unlocked and Config.colosseumDifficulty(info.unlocked)
		if U and U.id == info.unlocked then
			set(unlockLabel, U.name .. " UNLOCKED!")
			unlockLabel.TextColor3 = U.color -- (it flashes, so you see it's there to pick)
		else
			set(unlockLabel, "")
		end
		statusLine.Text = ""
		busy = false
		paintRow()
		showing = showing + 1
		local mine = showing
		-- (a moment after he falls, so his banner and confetti get their turn)
		task.delay(3.2, function()
			if showing == mine and player:GetAttribute("Colosseum") then
				gui.Enabled = true
				if info.questPower then
					KingHud.sfx("Quest") -- (the quest's done: its fanfare as the screen opens)
				end
				-- a new best time, and a newly opened difficulty, flash
				local flip = false
				while (info.newBest or unlockLabel.Visible) and gui.Enabled and showing == mine do
					flip = not flip
					if info.newBest then
						bestLabel.TextColor3 = flip and RGB(255, 255, 255) or GOLD
					end
					if unlockLabel.Visible and U then
						unlockLabel.TextColor3 = flip and RGB(255, 255, 255) or U.color
					end
					task.wait(0.35)
				end
			end
		end)
	end
	function ClearScreen.hide()
		showing = showing + 1
		gui.Enabled = false
	end
	player:GetAttributeChangedSignal("Colosseum"):Connect(function()
		if not player:GetAttribute("Colosseum") then
			ClearScreen.hide()
		end
	end)
end

----------------------------------------------------------------------
-- Rewards flying into you
----------------------------------------------------------------------
-- Every dummy you beat bursts into little gold coins and green XP gems. They
-- pop out and bounce once on the sand, then zip into you: each one that
-- reaches you ticks (a little higher each time, like a coin chain) and bumps
-- your coin counter or your level bar. Only on your screen - the server paid
-- you the moment the dummy fell; this is just the show.
local Loot = {}
do
	local SoundService = game:GetService("SoundService")
	local COIN = RGB(254, 174, 52)
	local GEM = RGB(99, 199, 77)
	local MAX = 120 -- (never more than this many flying at once)
	local STEP = 1 / 30 -- (moved 30 times a second: a little 8-bit)
	local GRAVITY = 70
	local pieces = {}
	local holder = nil
	local rngL = Random.new()

	local function folder()
		if not holder or not holder.Parent then
			holder = Instance.new("Folder")
			holder.Name = "RewardFx"
			holder.Parent = workspace
		end
		return holder
	end

	-- where the sand is under a spot (so the pieces bounce on it)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local function floorBelow(p)
		local skip = { folder() }
		if player.Character then
			skip[#skip + 1] = player.Character
		end
		local enemies = workspace:FindFirstChild("ColosseumEnemies")
		if enemies then
			skip[#skip + 1] = enemies
		end
		params.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
		return hit and hit.Position.Y or (p.Y - 4)
	end

	-- the bump on the HUD as a piece reaches you: the coin counter's coin, or
	-- the level bar (Hud builds them; if they're not there, no bump)
	local bumping = {}
	local function hudPart(kind)
		local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("BossGrowHud")
		local root = hud and hud:FindFirstChild("Root")
		if not root then
			return nil
		end
		if kind == "coin" then
			local stats = root:FindFirstChild("Stats")
			return stats and stats:FindFirstChild("Coin", true)
		end
		return root:FindFirstChild("GoalBar")
	end
	local function bump(kind)
		local target = hudPart(kind)
		if not target then
			return
		end
		local sc = target:FindFirstChild("CollectPop")
		if not sc then
			if target:FindFirstChildOfClass("UIScale") then
				return -- (it has a scale of its own: leave it be)
			end
			sc = Instance.new("UIScale")
			sc.Name = "CollectPop"
			sc:SetAttribute("RetroSkip", true)
			sc.Parent = target
		end
		local peak = (kind == "coin") and 1.35 or 1.05
		sc.Scale = peak
		bumping[sc] = { t = os.clock(), peak = peak }
	end

	-- the tick as a piece reaches you: a little higher each time through a
	-- chain of them (and never more than about 16 a second)
	local chain, lastTick, lastGot = 0, 0, 0
	local function tick()
		local now = os.clock()
		if now - lastGot > 0.7 then
			chain = 0
		end
		lastGot = now
		if now - lastTick < 0.06 then
			return
		end
		lastTick = now
		chain = math.min(chain + 1, 14)
		local def = Config.Colosseum.Sounds and Config.Colosseum.Sounds.Collect
		local template = def and findNamedSound(def.names)
		if not template then
			return
		end
		local snd = template:Clone()
		snd.Looped = false
		snd.Volume = template.Volume * (def.volume or 0.3)
		snd.PlaybackSpeed = (tonumber(template.PlaybackSpeed) or 1) * (1 + chain * 0.045)
		local effects = SoundService:FindFirstChild("Effects")
		if effects and effects:IsA("SoundGroup") then
			snd.SoundGroup = effects
		end
		snd.Parent = SoundService
		snd:Play()
		task.delay(3, function()
			snd:Destroy()
		end)
	end

	-- A shower of coins and gems from `from`. `worth` = what the dummy was
	-- worth (a straw dummy on Normal is 1): more for the tougher ones.
	function Loot.burst(from, worth, king)
		if typeof(from) ~= "Vector3" then
			return
		end
		worth = math.max(0.3, tonumber(worth) or 1)
		local coins, gems
		if king then
			local k = math.sqrt(worth / 15)
			coins = math.floor(20 + 6 * k)
			gems = math.floor(14 + 4 * k)
		else
			coins = math.clamp(math.floor(2 + math.sqrt(worth) * 2.2 + 0.5), 3, 12)
			gems = math.clamp(math.floor(1 + math.sqrt(worth) * 1.6 + 0.5), 2, 9)
		end
		local room = MAX - #pieces
		if room < coins + gems then
			local k = math.max(0, room) / (coins + gems)
			coins, gems = math.floor(coins * k), math.floor(gems * k)
		end
		if coins + gems <= 0 then
			return
		end
		local floorY = floorBelow(from)
		local big = king and 1.3 or 1
		for i = 1, coins + gems do
			local isCoin = i <= coins
			local p = Instance.new("Part")
			p.Name = isCoin and "Coin" or "XPGem"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			if isCoin then
				p.Size = Vector3.new(1.1, 1.1, 0.25) * big
				p.Color = COIN
				p.Material = Enum.Material.SmoothPlastic
			else
				p.Size = Vector3.new(0.8, 0.8, 0.8) * big
				p.Color = GEM
				p.Material = Enum.Material.Neon
			end
			local a = rngL:NextNumber() * math.pi * 2
			local out = rngL:NextNumber(6, king and 26 or 16)
			local start = from + Vector3.new(0, rngL:NextNumber(-0.5, 0.5), 0)
			p.CFrame = CFrame.new(start)
			p.Parent = folder()
			pieces[#pieces + 1] = {
				part = p,
				coin = isCoin,
				pos = start,
				vel = Vector3.new(math.cos(a) * out, rngL:NextNumber(18, king and 38 or 30), math.sin(a) * out),
				floor = floorY + p.Size.Y / 2,
				spin = rngL:NextNumber() * math.pi * 2,
				spinRate = rngL:NextNumber(8, 14) * (rngL:NextNumber() < 0.5 and -1 or 1),
				t = 0,
				home = rngL:NextNumber(0.45, 0.75) + (king and 0.35 or 0), -- (when it starts coming to you)
				speed = 0,
				bounced = false,
			}
		end
	end

	-- (leaving the Colosseum: any still flying just vanish)
	function Loot.clear()
		for _, pc in ipairs(pieces) do
			pc.part:Destroy()
		end
		table.clear(pieces)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- the HUD bumps: back to normal size in a moment
		local now = os.clock()
		for sc, b in pairs(bumping) do
			local k = (now - b.t) / 0.16
			if k >= 1 or not sc.Parent then
				sc.Scale = 1
				bumping[sc] = nil
			else
				sc.Scale = 1 + (b.peak - 1) * (1 - k)
			end
		end
		if #pieces == 0 then
			acc = 0
			return
		end
		acc = acc + dt
		if acc < STEP then
			return
		end
		local h = math.min(acc, 0.1)
		acc = 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local target = root and root.Position
		for i = #pieces, 1, -1 do
			local pc = pieces[i]
			pc.t = pc.t + h
			local done = false
			if pc.t < pc.home or not target then
				-- popping out: up and out, falling, one bounce on the sand
				pc.vel = pc.vel - Vector3.new(0, GRAVITY * h, 0)
				pc.pos = pc.pos + pc.vel * h
				if pc.pos.Y < pc.floor then
					pc.pos = Vector3.new(pc.pos.X, pc.floor, pc.pos.Z)
					if pc.bounced then
						pc.vel = Vector3.new(pc.vel.X * 0.5, 0, pc.vel.Z * 0.5)
					else
						pc.bounced = true
						pc.vel = Vector3.new(pc.vel.X * 0.55, -pc.vel.Y * 0.45, pc.vel.Z * 0.55)
					end
				end
				if not target and pc.t > 3 then
					done = true
				end
			else
				-- zipping into you, faster and faster
				pc.speed = math.min(110, pc.speed + 160 * h)
				local to = target - pc.pos
				local d = to.Magnitude
				local want = (d > 0.01 and to.Unit or Vector3.zero) * math.max(pc.speed, 20)
				pc.vel = pc.vel:Lerp(want, math.min(1, h * (9 + (pc.t - pc.home) * 30)))
				if d < 1.8 or pc.vel.Magnitude * h >= d or pc.t > pc.home + 2.5 then
					done = true
					tick()
					bump(pc.coin and "coin" or "xp")
				else
					pc.pos = pc.pos + pc.vel * h
				end
			end
			if done then
				pc.part:Destroy()
				table.remove(pieces, i)
			else
				pc.spin = pc.spin + pc.spinRate * h
				if pc.coin then
					pc.part.CFrame = CFrame.new(pc.pos) * CFrame.Angles(0, pc.spin, 0)
				else
					pc.part.CFrame = CFrame.new(pc.pos) * CFrame.Angles(pc.spin, pc.spin * 0.7, 0)
				end
			end
		end
	end)
end

local kingBannerUntil = 0 -- (while "THE STRAW KING FALLS!" is up, WAVE CLEARED waits its turn)
ReplicatedStorage:WaitForChild("ColosseumEvent", 60).OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "PipeIn" then
		task.spawn(pipeIn, a, b, c)
	elseif kind == "PipeOut" then
		task.spawn(pipeOut, a, b)
	elseif kind == "State" and type(a) == "table" then
		renderTracker(a)
	elseif kind == "Arrived" then
		showBanner("THE COLOSSEUM", GOLD, 1.8)
	elseif kind == "Wave" then
		showBanner("WAVE " .. tostring(a) .. (runLength and ("/" .. runLength) or ""), RGB(255, 255, 255), 1.4)
		KingHud.sfx("WaveHorn")
	elseif kind == "Kill" then
		popReward(a, b, c)
		KingHud.sfx("Reward")
		-- the coins and XP burst out of it and fly into you
		local info = type(d) == "table" and d or {}
		local from = typeof(info.from) == "Vector3" and info.from or (typeof(c) == "Vector3" and c - Vector3.new(0, 7, 0)) or nil
		Loot.burst(from, info.worth, info.king == true)
	elseif kind == "Sfx" then
		KingHud.sfx(a, b)
	elseif kind == "WaveClear" then
		if os.clock() > kingBannerUntil then
			showBanner("WAVE " .. tostring(a) .. " CLEARED!", GOLD, 1.8)
			task.spawn(confetti)
			KingHud.sfx("Cheer")
		end
	elseif kind == "QuestDone" then
		-- (only without runs: a run's quest shows on the CLEARED screen.
		-- If the King's banner is up, this one comes straight after it.)
		KingHud.sfx("Quest")
		local text = "QUEST COMPLETE!  +" .. Config.format(a) .. " XP  +" .. Config.format(b) .. " coins"
		local later = kingBannerUntil - os.clock()
		if later > 0 then
			task.delay(later, showBanner, text, GREEN, 2.6)
		else
			showBanner(text, GREEN, 2.6)
		end
	elseif kind == "BossWave" then
		-- THE BOSS WAVE: a horn, and a big red banner
		showBanner("BOSS WAVE!", RED, 1.8)
		KingHud.play("Horn")
	elseif kind == "KingFx" then
		-- one of his sounds, and (for his landings and roars) the ground shaking
		if a == "Step" then
			KingHud.play("Land", 0.35)
		elseif a == "Spin" then
			-- (it stops when his whirlwind does, however long the sound is)
			local K = Config.Colosseum.King
			fadeOutSound(KingHud.play(a), (K and K.Spin and K.Spin.Time) or 2.4, 0.3)
		else
			KingHud.play(a)
		end
		if type(c) == "number" then
			KingHud.shake(c * 1.6, b)
		end
	elseif kind == "RunClear" then
		ClearScreen.show(a)
	elseif kind == "RunStart" then
		ClearScreen.hide()
		-- ("HARD RUN BEGINS!" in its colour; just "A NEW RUN" on Normal)
		local D = Config.colosseumDifficulty(a)
		if type(a) == "string" and not isFirstDifficulty(D.id) then
			showBanner(D.name .. " RUN BEGINS!", D.color, 1.8)
		else
			showBanner("A NEW RUN BEGINS!", GOLD, 1.6)
		end
	elseif kind == "Left" then
		ClearScreen.hide()
		Loot.clear()
	elseif kind == "Streak" then
		-- every 5 kills in a row
		local bonus = math.floor((tonumber(b) or 0) * 100 + 0.5)
		if os.clock() > kingBannerUntil then
			showBanner("x" .. tostring(a) .. " STREAK!" .. (bonus > 0 and ("  +" .. bonus .. "% rewards") or ""), GOLD, 1.3)
		end
	elseif kind == "StreakLost" then
		if (tonumber(a) or 0) >= ((Config.Colosseum.Streak and Config.Colosseum.Streak.Every) or 5) then
			showBanner("STREAK LOST (x" .. tostring(a) .. ")", RED, 1.2)
		end
	elseif kind == "KingRage" then
		showBanner("THE KING IS FURIOUS!", RED, 2)
	elseif kind == "KingDown" then
		kingBannerUntil = os.clock() + 3
		showBanner("THE STRAW KING FALLS!  +" .. Config.format(a or 0) .. " XP  +" .. Config.format(b or 0) .. " coins", GOLD, 3)
		KingHud.play("Victory", 0.8)
		KingHud.sfx("Cheer")
		task.spawn(confetti)
	end
end)

----------------------------------------------------------------------
-- Never stuck in the floor after respawning
----------------------------------------------------------------------
-- A body must never stand sunk into the floor (it kept happening after a
-- reset or dying in the Colosseum). Your character is held up by Roblox's
-- ControllerManager: it keeps the body a set height above the floor, and the
-- legs themselves pass through floors. If that height comes out too low for
-- your avatar (say, the body was set up before your avatar finished loading),
-- the body settles with its legs in the ground.
--
-- So, the whole time you're alive: if your lowest foot is under the top of
-- the floor right beneath it, twice in a row while you're standing still
-- (not jumping, falling or rolling), we raise the height the controller
-- holds you at by exactly that much, and lift you out. It learns the right
-- height from where your feet really are, so it works for any avatar size.
local function lowestFootPart(char)
	local best, low = nil, math.huge
	for _, p in ipairs(char:GetChildren()) do
		-- (body parts only: hats and hair are inside Accessories)
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local cf, half = p.CFrame, p.Size / 2
			local reach = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			if cf.Position.Y - reach < low then
				best, low = p, cf.Position.Y - reach
			end
		end
	end
	return best, low
end
local function keepFeetUp(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not (hum and root) then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local strikes = 0
	while char.Parent and hum.Health > 0 do
		task.wait(0.2)
		local foot, footY = lowestFootPart(char)
		local sunk = 0
		if foot and not root.Anchored and math.abs(root.AssemblyLinearVelocity.Y) < 3 then
			params.FilterDescendantsInstances = { char }
			-- the top of the floor straight under that foot (from above, so a foot
			-- stuck inside the floor still finds its top)
			local p = foot.Position
			local hit = workspace:Raycast(Vector3.new(p.X, root.Position.Y + 2, p.Z), Vector3.new(0, footY - root.Position.Y - 8, 0), params)
			if hit then
				sunk = hit.Position.Y - footY
			end
		end
		if sunk > 0.35 and sunk < 6 then
			strikes = strikes + 1
		else
			strikes = 0
		end
		if strikes >= 2 then
			strikes = 0
			-- hold the body higher from now on...
			local cm = char:FindFirstChildWhichIsA("ControllerManager", true)
			if cm then
				for _, c in ipairs(cm.Parent:GetDescendants()) do
					if c:IsA("GroundController") then
						pcall(function()
							c.GroundOffset = c.GroundOffset + sunk
						end)
					end
				end
				pcall(function()
					local sensor = cm.GroundSensor
					if sensor and sensor.SearchDistance > 0 then
						sensor.SearchDistance = sensor.SearchDistance + sunk
					end
				end)
			elseif hum.RigType == Enum.HumanoidRigType.R15 then
				hum.HipHeight = hum.HipHeight + sunk
			end
			-- ...and lift it out now
			root.AssemblyLinearVelocity = Vector3.zero
			char:PivotTo(char:GetPivot() + Vector3.new(0, sunk + 0.1, 0))
		end
	end
end
player.CharacterAdded:Connect(keepFeetUp)
if player.Character then
	task.spawn(keepFeetUp, player.Character)
end
