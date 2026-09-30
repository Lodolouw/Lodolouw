--!nocheck
-- Headless test of THE ARCADE on your screen (ArcadeClient), talking to the
-- real server (PlayerService, CombatService, ArcadeService) in the real
-- building (ArcadeBuilder), with pretend imported weapon models:
--   * the ROLL button and its token badge; the machines' screens (INSERT
--     TOKEN / LOCKED); the Secret weapon turning over the prize pedestal;
--     the token machine's "Get Tokens"
--   * walking in opens the menu (once: close it and it stays closed until
--     you walk out and back in); walking out closes it
--   * the menu: each machine's six weapons with their odds, the first-spin
--     promise, the pity count, a locked machine saying whose boss opens it, a
--     covered one COMING SOON, SPIN buttons only when you can pay
--   * a spin: the camera flies to the machine, the strip lands on what the
--     server picked, the reveal card (rarity, name, NEW, the weapon turning
--     in the middle of its window), EQUIP, SPIN AGAIN, DONE (the camera comes
--     back); tapping skips the strip; ten at once: a Legendary's reveal first,
--     then all ten in a grid
--   * THE MUSIC: the Arcade's own song while you're in there (the lobby's
--     steps aside), faster while the strip spins over the drum roll, silent
--     just before it lands (a heartbeat for a Legendary), the landing's sound
--     (a jackpot, with the screen shattering), then the song again at its
--     own speed; tapping through skips the heartbeat; the older sounds stand
--     in until the new ones are uploaded
--   * somebody else's spin: their machine lights up, their result floats
--     over it (heard from their machine), a Secret puts a banner on your
--     screen (with its jackpot) and goes on BIG WINS
--   * the HUD's token counter (ArcadeOpen) opens the menu; outside the lobby
--     you can look but not spin; in the intro there's no ROLL button
--   luau test_arcade_client.luau             the test
--   luau test_arcade_client.luau -a snaps    ...printing snapshots of the screen
--                                            for render_gui.py (the preview)
local SNAPS = ({ ... })[1] == "snaps"
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame, Enum = M.Instance, M.Vector3, M.CFrame, M.Enum
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage
local SoundService = M.services.SoundService
local CollectionService = M.services.CollectionService
local workspace = M.workspace

RunService.IsStudio = function()
	return true
end
M.game.BindToClose = function() end
local UIS = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	GetLastInputType = function()
		return Enum.UserInputType.MouseButton1
	end,
	InputBegan = M.Signal.new(),
	InputEnded = M.Signal.new(),
	InputChanged = M.Signal.new(),
	LastInputTypeChanged = M.Signal.new(),
}
M.services.UserInputService = UIS
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y > 0.8 then
		return { Position = Vector3.new(origin.X, 0.8, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- the players: us, and Bravo (who spins too)
local function newPlayer(name, id, at)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = id
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(at)
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	local pg = Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = p
	local ps = Instance.new("PlayerScripts")
	ps.Name = "PlayerScripts"
	ps.Parent = p
	p.Parent = Players
	table.insert(M.players, p)
	return p, root, pg
end
local me, myRoot, gui = newPlayer("Alpha", 1001, Vector3.new(0, 3.55, 30))
local bravo = newPlayer("Bravo", 1002, Vector3.new(6, 3.55, 30))
Players.LocalPlayer = me
local cam = Instance.new("Camera")
cam.CFrame = CFrame.new(Vector3.new(0, 12, 50), Vector3.new(0, 3, 30))
cam.CameraType = Enum.CameraType.Custom
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- the sounds the game has (SoundLoader puts them in SoundService); every one
-- that plays is a copy put in SoundService (or in a machine, heard from there)
local played = {}
local NEW_SOUNDS = { "Arcade Theme", "Spin Riser", "Heartbeat", "Win Common", "Win Rare", "Win Epic", "Jackpot Legendary", "Jackpot Mythic", "Jackpot Secret" }
for _, name in ipairs({ "UI Blip", "Token Clunk", "Roll Tick", "Orb Land", "Level Complete", "Legendary Reveal", table.unpack(NEW_SOUNDS) }) do
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.Volume, snd.PlaybackSpeed = 0.5, 1
	snd.Parent = SoundService
end
SoundService.ChildAdded:Connect(function(c)
	played[c.Name] = (played[c.Name] or 0) + 1
end)
-- the lobby's song plays in the "Music" SoundGroup (BossClient)
local lobbyMusic = Instance.new("SoundGroup")
lobbyMusic.Name = "Music"
lobbyMusic.Volume = 0.7
lobbyMusic.Parent = SoundService

-- messages between the "server" and the "screen"
local invokes = {}
M.onInvokeServer = function(remote, name, ...)
	invokes[name] = (invokes[name] or 0) + 1
	return remote.OnServerInvoke(me, name, ...)
end
M.onFireClient = function(remote, target, ...)
	local a = table.pack(...)
	M.task.defer(function()
		if target == me or target == nil then
			remote.OnClientEvent:Fire(table.unpack(a, 1, a.n))
		end
	end)
end
M.onFireServer = function(remote, ...)
	local a = table.pack(...)
	M.task.defer(function()
		remote.OnServerEvent:Fire(me, table.unpack(a, 1, a.n))
	end)
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local A, W = Config.Arcade, Config.Weapons

-- the Arcade, in a lobby
local lobby = Instance.new("Model")
lobby.Name = "Lobby"
lobby.Parent = workspace
mount.require(mount.module("ServerScriptService/ArcadeBuilder.lua")).Build(lobby)

-- the Slime pack's models, as if imported (like test_voxelhold's)
local Info = mount.require(mount.module("ReplicatedStorage/WeaponModelInfo.lua"))
local models = Instance.new("Folder")
models.Name = "WeaponModels"
models.Parent = ReplicatedStorage
for _, id in ipairs(Config.arcadePack("Slime").Weapons) do
	local key = W.List[id].Model
	local info = key and Info[key]
	if info then
		local m = Instance.new("Model")
		m.Name = key
		local i = 0
		for name in pairs(info.Parts) do
			i += 1
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(0.3, 0.2, 0.5)
			p.CFrame = CFrame.new(0, 0, 0.4 * i)
			p.Parent = m
		end
		for name, at in pairs({ GripMark = Vector3.new(0, 0, 0), TipMark = Vector3.new(0, 0, info.Tip), UpMark = Vector3.new(0, -info.Up, 0) }) do
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(0.08, 0.08, 0.08)
			p.CFrame = CFrame.new(at)
			p.Parent = m
		end
		m.Parent = models
	end
end

local PS = mount.require(mount.module("ServerScriptService/PlayerService.lua"))
local CS = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local AS = mount.require(mount.module("ServerScriptService/ArcadeService.lua"))
-- two weapons' icons are uploaded (the rest aren't yet)
local AssetIds = mount.require(mount.module("ReplicatedStorage/AssetIds.lua"))
AssetIds.Icons = { Jellyblade = 111, GooGloves = 222 }
local ICON_JELLY = "rbxthumb://type=Asset&id=111&w=150&h=150"
if SNAPS then
	-- (for the pictures: every weapon's icon, so render_gui.py can paint them)
	local n = 1000
	for id in pairs(W.List) do
		n += 1
		if id ~= "Jellyblade" and id ~= "GooGloves" then
			AssetIds.Icons[id] = n
		end
	end
	for id, aid in pairs(AssetIds.Icons) do
		print("ICONMAP " .. aid .. " " .. id)
	end
end

local T = 0
local DT = 1 / 30
local function step(seconds)
	local stop = T + seconds
	while T < stop - 1e-9 do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
		RunService.RenderStepped:Fire(DT)
	end
end
local function waitFor(cond, limit, what)
	local t0 = T
	while not cond() do
		if T - t0 > limit then
			check(false, "timed out waiting for " .. what)
			return false
		end
		step(DT)
	end
	return true
end
local function moveTo(player, pos)
	player:SetAttribute("MoveTo", pos)
	player:SetAttribute("MoveUntil", workspace:GetServerTimeNow() + 1)
	player.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
end

PS.Start()
CS.Start(PS)
AS.Start(PS, CS)
step(0.5)
local d, bd = PS.GetData(me), PS.GetData(bravo)
assert(d and bd, "both saves should be loaded")
local Action = ReplicatedStorage.Remotes.Action

mount.runClient("StarterPlayerScripts/ArcadeClient.client.lua", me)
step(1)

-- the screen's parts
local screen = gui:FindFirstChild("Arcade")
assert(screen, "the Arcade screen should be made")
local function find(name, root)
	return (root or screen):FindFirstChild(name, true)
end
local rollBtn, win, show = find("RollButton"), find("Window"), find("Show")
local badge = rollBtn and rollBtn:FindFirstChild("Badge")
local detail, list = find("Detail", win), find("Machines", win)
local card, grid = find("Card", show), find("Grid", show)
assert(rollBtn and win and show and badge and detail and list and card and grid, "the screen's parts should all be there")
local snapGui = SNAPS and require("./gui_snap") or nil
local function snap(caption)
	if snapGui then
		snapGui(screen, caption, 1280, 720)
	end
end
check(screen:GetAttribute("RetroSkip") == true, "the retro recolour leaves it alone")
local function labels(root)
	local out = {}
	for _, x in ipairs(root:GetDescendants()) do
		if (x.ClassName == "TextLabel" or x.ClassName == "TextButton") and x.Text and x.Text ~= "" then
			table.insert(out, x)
		end
	end
	return out
end
-- (shown: it and everything it's in, up to `root`, visible)
local function shownIn(x, root)
	while x and x ~= root do
		if x.Visible == false or x.Enabled == false then
			return false
		end
		x = x.Parent
	end
	return true
end
local function textOn(root, pattern)
	for _, l in ipairs(labels(root)) do
		if string.find(l.Text, pattern) and shownIn(l, root) then
			return l
		end
	end
	return nil
end
local function button(root, pattern)
	for _, l in ipairs(labels(root)) do
		if l.ClassName == "TextButton" and string.find(l.Text, pattern) then
			return l
		end
	end
	return nil
end
local function press(b)
	assert(b, "no such button")
	b.Activated:Fire()
end
local function message()
	for _, l in ipairs(win:GetChildren()) do
		if l.ClassName == "TextLabel" and l.ZIndex == 6 then
			return l.Text
		end
	end
	return ""
end
local closeBtn = button(win, "^X$")
local spin1, spin10 = button(detail, "^SPIN x1"), button(detail, "^SPIN x10")
assert(closeBtn and spin1 and spin10, "the menu's buttons should be there")

----------------------------------------------------------------------
-- Before anything
----------------------------------------------------------------------
check(rollBtn.Visible ~= false and not win.Visible and not show.Visible, "the ROLL button is there, the menu isn't")
check(badge.Visible == false, "no tokens: no badge")
local cabinets = {}
for _, m in ipairs(CollectionService:GetTagged("ArcadeCabinet")) do
	cabinets[m:GetAttribute("Machine")] = m
end
local function status(id)
	local c = cabinets[id]
	local sg = c and c:FindFirstChild("Screen") and c.Screen:FindFirstChildOfClass("SurfaceGui")
	local l = sg and sg.Back.Status
	return l and l.Text or "(no screen)"
end
local sawInsert = false
for _ = 1, 40 do
	step(DT)
	sawInsert = sawInsert or status("Slime") == "INSERT TOKEN"
end
check(sawInsert, "the Slime machine's screen blinks INSERT TOKEN")
check(status("Knight") == "LOCKED", "the Knight machine's says LOCKED (got " .. status("Knight") .. ")")
local count, covered = 0, 0
for id, m in pairs(cabinets) do
	count += 1
	covered += m:GetAttribute("Soon") and 1 or 0
end
check(count == 5 and covered == 0, "five machines, none under covers crowding the room (" .. count .. ", " .. covered .. ")")

-- the prize: the Slime machine's Secret weapon, standing over the pedestal
local prize = workspace:FindFirstChild("PrizeWeapon")
local pedestal = CollectionService:GetTagged("ArcadePrize")[1]
check(prize ~= nil and pedestal ~= nil, "the Secret weapon turns over the prize pedestal")
if prize and pedestal then
	local box, size = prize:GetBoundingBox()
	local top = pedestal.Position.Y + pedestal.Size.X / 2
	check(box.Position.Y - size.Y / 2 > top + 0.5 and box.Position.Y - size.Y / 2 < top + 1.5, "it floats just over the pedestal")
	check(math.abs(box.Position.X - pedestal.Position.X) < 0.05 and math.abs(box.Position.Z - pedestal.Position.Z) < 0.05, "right over its middle")
	check(size.Y > size.X and size.Y > size.Z, "standing up")
	check(textOn(pedestal, "SECRET") ~= nil, "under a SECRET sign")
end
local tokenMachine = CollectionService:GetTagged("ArcadeTokens")[1]
local prompt = tokenMachine and tokenMachine.Body:FindFirstChildOfClass("ProximityPrompt")
check(prompt ~= nil and prompt.ActionText == "Get Tokens", "the token machine says Get Tokens")

----------------------------------------------------------------------
-- Walking in
----------------------------------------------------------------------
local inside = Config.Stations.Arcade + Vector3.new(0, 3.55, 12)
local outside = Config.Stations.Arcade + Vector3.new(0, 3.55, 40)
moveTo(me, inside)
waitFor(function()
	return win.Visible
end, 1, "the menu to open on walking in")
moveTo(me, outside)
waitFor(function()
	return not win.Visible
end, 1, "the menu to close on walking out")
moveTo(me, inside)
waitFor(function()
	return win.Visible
end, 1, "the menu to open again")
press(closeBtn)
step(1)
check(not win.Visible, "closed with X, it stays closed while you're inside")
moveTo(me, outside)
step(0.5)
moveTo(me, inside)
waitFor(function()
	return win.Visible
end, 1, "the menu to open after walking out and back in")
step(2)
local song = SoundService:FindFirstChild("ArcadeSongPlaying")
check(song and song.Looped and song.SoundGroup and song.SoundGroup.Name == "ArcadeMusic", "in the Arcade its own song plays (looping, in its own group)")
check(song and song.Volume > 0.15 and math.abs(song.PlaybackSpeed - 1) < 0.01, "at its own speed (" .. tostring(song and song.Volume) .. ")")
check(lobbyMusic.Volume < 0.1, "and the lobby's song steps aside (" .. lobbyMusic.Volume .. ")")

----------------------------------------------------------------------
-- The menu
----------------------------------------------------------------------
check(textOn(detail, "^SLIME MACHINE$") ~= nil, "the Slime machine is picked first")
for _, r in ipairs(A.Order) do
	local id = Config.arcadeWeapon("Slime", r)
	check(textOn(detail, "^" .. string.upper(r) .. "$") and textOn(detail, "^" .. string.gsub(W.List[id].Name, "%-", "%%-") .. "$"), "it lists the " .. r .. " weapon")
end
check(textOn(detail, "^45%%$") and textOn(detail, "^0.5%%$"), "with the real odds")
-- with luck (a luck pass or the Luck boost: the server keeps it on you), the
-- odds shown are the lucky ones - the same the server rolls with
do
	me:SetAttribute("Luck", 2)
	press(list:FindFirstChild("Slime"))
	local v = Config.arcadeOdds(2).Secret
	local want = tostring(math.floor(v * 100 + 0.5) / 100) .. "%"
	local shown = false
	for _, l in ipairs(detail:GetDescendants()) do
		shown = shown or (l.ClassName == "TextLabel" and l.Text == want)
	end
	check(shown and not textOn(detail, "^0.5%%$"), "with luck, the lucky odds show (Secret " .. want .. ")")
	me:SetAttribute("Luck", nil)
	press(list:FindFirstChild("Slime"))
	check(textOn(detail, "^0.5%%$") ~= nil, "and without it, the real odds again")
end
-- each row's icon, or its rarity's gem while the icon isn't uploaded
local function rowOf(name)
	local l = textOn(detail, "^" .. name .. "$")
	return l and l.Parent
end
local jellyRow, hammerRow = rowOf("Jellyblade"), rowOf("Gelatin Hammer")
check(jellyRow and jellyRow.Icon.Visible and jellyRow.Icon.Image == ICON_JELLY and not jellyRow.Gem.Visible, "a weapon's row shows its icon")
check(SNAPS or (hammerRow and not hammerRow.Icon.Visible and hammerRow.Gem.Visible), "one without an uploaded icon shows its gem")
check(textOn(detail, "FIRST SPIN IS RARE OR BETTER") ~= nil, "a first spin promises Rare or better")
check(textOn(detail, "IN " .. A.Pity .. " SPINS") ~= nil, "the pity count shows " .. A.Pity)
check(textOn(win, "^%+ GET TOKENS$") ~= nil, "there's a GET TOKENS button")
local knightCard = list:FindFirstChild("Knight")
local knightBoss = Config.arcadePack("Knight").Boss
check(knightCard and textOn(knightCard, "Beat " .. knightBoss .. " to open"), "the Knight machine's card says whose boss opens it")
press(knightCard)
check(textOn(detail, "^KNIGHT MACHINE$") and textOn(detail, "Beat " .. knightBoss .. " %(Spire floor"), "picking it: locked, saying why")
snap("A LOCKED MACHINE|each machine opens when you beat its boss; the odds show anyway")
check(not spin1.Visible and not spin10.Visible, "no SPIN buttons on a locked machine")
press(list:FindFirstChild("Cactus"))
check(textOn(detail, "COMING SOON") ~= nil and not textOn(detail, "^COMMON$"), "a covered machine: COMING SOON, no weapons yet")
press(list:FindFirstChild("Slime"))
check(spin1.Visible and spin10.Visible, "back on Slime: the SPIN buttons")

-- no tokens
invokes = {}
press(spin1)
step(0.2)
check((invokes.ArcadeRoll or 0) == 0 and string.find(message(), "You need 1 token"), "no tokens: it says so without asking the server (" .. message() .. ")")
check(not show.Visible, "and nothing spins")

-- DEV: +10 Tokens (as the HUD's button does it)
Action:InvokeServer("DevGive", "Tokens")
step(0.3)
check(badge.Visible and badge.Text == "10", "the badge shows 10 tokens (" .. tostring(badge.Text) .. ")")
check(textOn(win, "^10$") ~= nil, "and the menu's counter")
snap("THE MENU|walk into the Arcade and it opens: the six weapons, the real odds, the pity")

----------------------------------------------------------------------
-- A spin
----------------------------------------------------------------------
local result
local realInvoke = M.onInvokeServer
M.onInvokeServer = function(remote, name, ...)
	local ok, answer = realInvoke(remote, name, ...)
	if name == "ArcadeRoll" and ok then
		result = answer
	end
	return ok, answer
end
local slimeScreen = cabinets.Slime.Screen
played = {}
press(spin1)
step(0.1)
check(result and #result.results == 1, "the server spun once")
local r1 = result and result.results[1] or {}
check(show.Visible and not win.Visible, "the show starts, the menu goes")
local spinScreen = gui:FindFirstChild("ArcadeSpinScreen")
check(spinScreen and spinScreen.ClassName == "SurfaceGui" and spinScreen.Enabled and spinScreen.Adornee == slimeScreen, "the spin plays on the Slime machine's own screen")
check(cam.CameraType == Enum.CameraType.Scriptable, "the camera takes over")
-- the token flies from your hand into the slot, the lever comes down
local slot = cabinets.Slime:FindFirstChild("CoinSlot")
local leverArm = cabinets.Slime:FindFirstChild("LeverArm")
local leverHome = leverArm and leverArm.CFrame
local sawToken, tokenNearSlot, leverMoved = false, false, false
local tiles = nil
waitFor(function()
	local tok = workspace:FindFirstChild("ThrownToken")
	if tok then
		sawToken = true
		tokenNearSlot = tokenNearSlot or (slot and (tok.Position - slot.Position).Magnitude < 3)
	end
	leverMoved = leverMoved or (leverArm and (leverArm.Position - leverHome.Position).Magnitude > 0.3)
	tiles = find("Tiles", spinScreen)
	return tiles and #tiles:GetChildren() > 0
end, 3, "the strip to start")
check(sawToken and tokenNearSlot, "a token flies into the coin slot")
check((played["Token Clunk"] or 0) >= 1, "and clunks in")
check(leverMoved, "the lever comes down")
check(tiles and #tiles:GetChildren() == 46, "the strip has its tiles")
step(0.6)
local camGap = (cam.CFrame.Position - slimeScreen.Position).Magnitude
check(camGap < 6, "the camera flies right up to the machine's screen (" .. string.format("%.1f", camGap) .. " studs)")
check(cam.CFrame.LookVector:Dot((slimeScreen.Position - cam.CFrame.Position).Unit) > 0.95, "looking straight at it")
check(leverArm and (leverArm.Position - leverHome.Position).Magnitude < 0.01, "the lever springs back")
local iconTiles, gemTiles, rightIcons = 0, 0, true
for _, t in ipairs(tiles and tiles:GetChildren() or {}) do
	local ic, gm = t:FindFirstChild("Icon"), t:FindFirstChild("Gem")
	if ic then
		iconTiles += 1
		local isJelly = textOn(t, "^Jellyblade$") ~= nil
		local isGloves = textOn(t, "^Goo Gloves$") ~= nil
		rightIcons = rightIcons and ((isJelly and ic.Image == ICON_JELLY) or (isGloves and ic.Image == "rbxthumb://type=Asset&id=222&w=150&h=150"))
	elseif gm then
		gemTiles += 1
	end
end
check(iconTiles > 0 and (SNAPS or gemTiles > 0) and (SNAPS or rightIcons), "tiles show their weapon's icon, or a gem without one (" .. iconTiles .. " icons, " .. gemTiles .. " gems)")
local landing = tiles and tiles:GetChildren()[40]
check(landing and textOn(landing, "^" .. string.upper(tostring(r1.rarity)) .. "$") and textOn(landing, W.List[r1.id] and string.gsub(W.List[r1.id].Name, "%-", "%%-") or "?"), "and lands on what the server picked")
check((played["Roll Tick"] or 0) > 5, "ticking as it goes")
check(textOn(show, "TAP TO SKIP") ~= nil, "it can be skipped")
if SNAPS then
	step(1.6)
	if snapGui then -- (the machine's own screen, as the camera sees it close up)
		snapGui(spinScreen, "ON THE MACHINE'S SCREEN|the strip slows onto what the server picked", 860, 600)
	end
end
local landedText = nil
waitFor(function()
	local st = find("Status", spinScreen)
	if st and st.Text ~= "GOOD LUCK!" then
		landedText = landedText or st.Text
	end
	return card.Visible
end, 8, "the reveal card")
check(landedText == string.upper(tostring(r1.rarity)) .. "!", "the machine's screen says what it landed on (" .. tostring(landedText) .. ")")
check(r1.rarity ~= "Common", "the first spin was Rare or better (" .. tostring(r1.rarity) .. ")")
check((played["Spin Riser"] or 0) >= 1, "a drum roll builds under the spin")
check((played[A.LandSounds[r1.rarity]] or 0) >= 1, "it lands with the " .. tostring(r1.rarity) .. " sound")
check(textOn(card, "^" .. string.upper(tostring(r1.rarity)) .. "!$") ~= nil, "the card says the rarity")
check(textOn(card, "^" .. (W.List[r1.id] and string.gsub(W.List[r1.id].Name, "%-", "%%-") or "?") .. "$") ~= nil, "and the weapon")
check(textOn(card, "NEW WEAPON") ~= nil, "and that it's new")
if SNAPS then
	find("View", card):SetAttribute("SnapImage", W.List[r1.id].Model)
	snap("THE REVEAL|your weapon turns in 3D: EQUIP it, SPIN AGAIN, or DONE")
end
local view = find("View", card)
local shown = view and view:FindFirstChildOfClass("Model")
check(shown ~= nil, "the weapon turns in the card's window")
if shown then
	step(0.3)
	local box, size = shown:GetBoundingBox()
	check(box.Position.Magnitude < 0.05, "round its middle (" .. tostring(box.Position) .. ")")
	check(size.Y > size.X and size.Y > size.Z, "standing up")
end
local equip = button(card, "^EQUIP$")
local canEquip = W.List[r1.id] and W.Types[W.List[r1.id].Type] ~= nil
check(equip and equip.Visible == (canEquip and true or false), "EQUIP is there if it can be held")
if canEquip then
	press(equip)
	step(0.1)
	check(me:GetAttribute("Weapon") == r1.id, "EQUIP puts it in your hand")
	check(not equip.Visible and textOn(card, "equipped!") ~= nil, "and says so")
end
check(textOn(card, "^SPIN AGAIN$") ~= nil, "SPIN AGAIN, with tokens left")
press(button(card, "^DONE$"))
step(0.1)
check(not show.Visible and win.Visible, "DONE: back to the menu")
check(cam.CameraType == Enum.CameraType.Custom, "and the camera comes back")
check(not textOn(detail, "FIRST SPIN IS RARE OR BETTER"), "the first-spin promise is used up")
check(textOn(detail, "IN " .. (A.Pity - d.Arcade.pity.Slime) .. " SPIN") ~= nil, "the pity count moves on")
check(badge.Text == "9", "9 tokens left")

-- tap to skip, then SPIN AGAIN
press(spin1)
step(0.5)
played = {}
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
step(1.2)
check(card.Visible, "a tap skips straight to the card")
local landed = 0
for _, name in pairs(A.LandSounds) do
	landed += played[name] or 0
end
check(landed == 1 and not played["Heartbeat"], "straight to its landing sound (" .. landed .. "), no heartbeat")
invokes = {}
press(button(card, "^SPIN AGAIN$"))
step(0.2)
check((invokes.ArcadeRoll or 0) == 1 and show.Visible and not card.Visible, "SPIN AGAIN spins again")
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch }, false)
step(1.2)
check(card.Visible, "a touch skips too")
press(button(card, "^DONE$"))
step(0.1)

----------------------------------------------------------------------
-- Ten at once (the server's "rng" fixed so it's a Legendary, then Commons)
----------------------------------------------------------------------
invokes = {}
press(spin10)
step(0.2)
check((invokes.ArcadeRoll or 0) == 0 and string.find(message(), "You need 9 tokens"), "7 tokens: not enough for ten (" .. message() .. ")")
Action:InvokeServer("DevGive", "Tokens")
step(0.3)
local realRng = AS.rng
local xs, n = {}, 0
AS.rng = { NextNumber = function()
	n += 1
	return xs[n] or 0.01
end }
xs[1] = 0.93 -- (Legendary: its slice of the odds is 90% to 97%)
press(spin10)
step(0.3)
check(result and #result.results == 10, "the server spun ten")
check(result.results[1].rarity == "Legendary", "the first of them a Legendary")
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
step(1.4)
check(card.Visible and not grid.Visible and textOn(card, "^LEGENDARY!$"), "a Legendary gets its own reveal first")
check(textOn(card, "SEE ALL 10") ~= nil, "with SEE ALL 10")
if SNAPS then
	find("View", card):SetAttribute("SnapImage", W.List[result.results[1].id].Model)
	snap("TEN AT ONCE|a Legendary or better gets its own reveal first (rays, a flash, a fanfare)")
end
check((played["Jackpot Legendary"] or 0) >= 1, "and its jackpot")
press(button(card, "SEE ALL 10"))
step(1.5)
check(grid.Visible and not card.Visible, "then the grid")
local cells = 0
for _, c in ipairs(grid:GetDescendants()) do
	if c.ClassName == "Frame" and c.Parent and c.Parent.ClassName == "Frame" and c.Parent.Parent == grid and c.LayoutOrder and c.LayoutOrder > 0 then
		cells += 1
	end
end
check(cells == 10, "with all ten (" .. cells .. ")")
snap("ALL TEN|then every result in a grid: NEW, or the mastery it gave")
check(textOn(grid, "^10 SPINS") ~= nil, "titled 10 SPINS")
check(textOn(grid, "^GET TOKENS$") ~= nil, "8 tokens left: GET TOKENS instead of again")
press(button(grid, "^DONE$"))
step(0.1)
check(not show.Visible and win.Visible and cam.CameraType == Enum.CameraType.Custom, "DONE: back to the menu")

-- the INSTANT x10 pass (the shop's): ten at once skip straight to the results
me:SetAttribute("Pass_InstantTen", true)
Action:InvokeServer("DevGive", "Tokens")
step(0.3)
AS.rng = { NextNumber = function()
	return 0.01 -- (all Commons: no Legendary reveal first)
end }
press(spin10)
step(1.5) -- (and nobody taps)
check(grid.Visible and not card.Visible, "with Instant x10: straight to the grid, no tap needed")
press(button(grid, "^DONE$"))
step(0.1)
me:SetAttribute("Pass_InstantTen", nil)
AS.rng = realRng

----------------------------------------------------------------------
-- THE MUSIC through a whole spin (a Legendary, not skipped)
----------------------------------------------------------------------
step(5) -- (the last landing rings out)
check(song.Parent and song.Volume > 0.15 and math.abs(song.PlaybackSpeed - 1) < 0.01, "the song is back at its own speed")
AS.rng = { NextNumber = function()
	return 0.93 -- (Legendary)
end }
local marks = {}
local watch = SoundService.ChildAdded:Connect(function(c)
	if not marks[c.Name] then
		marks[c.Name] = { t = T, song = song.Volume, from = c.TimePosition }
	end
end)
local t0, fastest, shards, rattled = T, 0, false, false
local home = cabinets.Slime:GetPivot()
press(spin1)
waitFor(function()
	fastest = math.max(fastest, song.PlaybackSpeed)
	shards = shards or find("Shard", show) ~= nil
	rattled = rattled or (cabinets.Slime:GetPivot().Position - home.Position).Magnitude > 0.01
	return card.Visible
end, 8, "the Legendary's card")
watch:Disconnect()
AS.rng = realRng
local riser, heart, jackpot = marks["Spin Riser"], marks["Heartbeat"], marks["Jackpot Legendary"]
check(riser and riser.t - t0 > 0.8 and riser.t - t0 < 2.2, "the drum roll starts as the strip does, after the token and the lever (" .. tostring(riser and riser.t - t0) .. ")")
check(riser and math.abs((riser.from or 0) - 1.1) < 0.05, "timed to end as it goes quiet (from " .. tostring(riser and riser.from) .. ")")
check(fastest > 1.2, "the song speeds up while it spins (" .. fastest .. ")")
check(heart and jackpot and math.abs((jackpot.t - heart.t) - 1.6) < 0.1, "a heartbeat for the last 1.6 seconds (" .. tostring(heart and jackpot and jackpot.t - heart.t) .. ")")
check(jackpot and jackpot.song < 0.01, "in silence: the song has dropped out (" .. tostring(jackpot and jackpot.song) .. ")")
check(shards, "the screen shatters as the jackpot hits")
check(rattled, "and the whole machine rattles")
step(1)
check((cabinets.Slime:GetPivot().Position - home.Position).Magnitude < 1e-6, "then stands back where it was")
check(not marks["Win Common"] and not marks["Legendary Reveal"], "just the one landing sound")
step(1.5)
check(song.Volume < 0.02, "the song waits while the jackpot rings out")
step(3)
check(song.Volume > 0.1 and math.abs(song.PlaybackSpeed - 1) < 0.01, "then comes back at its own speed")
press(button(card, "^DONE$"))
step(0.1)

----------------------------------------------------------------------
-- Somebody else's spin (a Secret), and BIG WINS
----------------------------------------------------------------------
local slimeSounds = function()
	local n = {}
	for _, x in ipairs(cabinets.Slime.Screen:GetChildren()) do
		if x.ClassName == "Sound" then
			n[x.Name] = (n[x.Name] or 0) + 1
		end
	end
	return n
end
played = {}
step(8) -- (your own spins' announcements play out first)
check(next(slimeSounds()) == nil and not played["Jackpot Legendary"], "your own spins' announcements are silent (you heard them)")
local secretId = Config.arcadeWeapon("Slime", "Secret")
local secretName = W.List[secretId].Name
AS.rng = { NextNumber = function()
	return 0.999
end }
bd.Tokens = 3
step(A.Gap + 0.1)
local ok = Action.OnServerInvoke(bravo, "ArcadeRoll", { machine = "Slime", count = 1 })
AS.rng = realRng
check(ok, "Bravo spins")
local bravoLever = cabinets.Slime:FindFirstChild("LeverArm")
local bravoHome, bravoPulled = bravoLever.Position, false
for _ = 1, 18 do
	step(DT)
	bravoPulled = bravoPulled or (bravoLever.Position - bravoHome).Magnitude > 0.3
end
check(bravoPulled, "everyone sees Bravo's machine's lever come down")
check(status("Slime") == "SPINNING!", "the Slime machine's screen lights up for everyone (" .. status("Slime") .. ")")
check((slimeSounds()["Roll Tick"] or 0) >= 1, "ticking, heard from the machine")
check(not textOn(cabinets.Slime.Marquee, "^Bravo"), "while it spins, the result isn't given away")
step(1)
check(status("Slime") == "SECRET!", "then the screen lands on SECRET!")
local floating = textOn(cabinets.Slime.Marquee, "^Bravo: SECRET " .. string.gsub(secretName, "%-", "%%-") .. "!$")
check(floating ~= nil, "Bravo's result floats over it")
local banner = find("SecretBanner")
check(banner and textOn(banner, "Bravo just spun a SECRET") and banner.Position.Y.Offset > 0, "a Secret puts a banner on every screen")
check((played["Jackpot Secret"] or 0) == 1, "with its jackpot, for everyone")
snap("SOMEONE SPINS A SECRET|a banner on every screen (and it goes up on the BIG WINS board)")
local board = CollectionService:GetTagged("ArcadeWins")[1]
check(board and textOn(board, "^Bravo  %-  SECRET " .. string.gsub(secretName, "%-", "%%-")), "and it's up on BIG WINS")
step(7)
check(banner.Position.Y.Offset < 0, "the banner goes away again")
check(not cabinets.Slime.Marquee:FindFirstChild("ArcadeWin"), "and the floating result")

-- two spins on one machine close together take turns on its screen
bd.Tokens = 5
local function fixed(x)
	return { NextNumber = function()
		return x
	end }
end
AS.rng = fixed(0.93) -- (Legendary)
Action.OnServerInvoke(bravo, "ArcadeRoll", { machine = "Slime", count = 1 })
step(A.Gap + 0.1)
AS.rng = fixed(0.01) -- (Common)
Action.OnServerInvoke(bravo, "ArcadeRoll", { machine = "Slime", count = 1 })
AS.rng = realRng
local seen, lastSeen = {}, nil
for _ = 1, 200 do
	step(DT)
	local st = status("Slime")
	if st ~= lastSeen then
		lastSeen = st
		if st ~= "SPINNING!" and string.sub(st, -1) == "!" then
			table.insert(seen, st)
		end
	end
end
check(table.concat(seen, " ") == "LEGENDARY! COMMON!", "one after the other (" .. table.concat(seen, " ") .. ")")
local heard = slimeSounds()
check(heard["Jackpot Legendary"] == 1 and heard["Win Common"] == 1, "each heard from the machine: a jackpot, then a plink")

----------------------------------------------------------------------
-- Other ways in, and where you can't spin
----------------------------------------------------------------------
press(closeBtn)
local open = ReplicatedStorage:FindFirstChild("ArcadeOpen")
check(open and open.ClassName == "BindableEvent", "the HUD's token counter has ArcadeOpen to fire")
open:Fire()
step(0.1)
check(win.Visible, "which opens the menu")
press(closeBtn)
open:Fire("Tokens")
step(0.1)
check(win.Visible and string.find(message(), "every " .. Config.Quests.Hours .. " hours"), "the token page says where tokens come from (" .. message() .. ")")
press(closeBtn)
prompt.Triggered:Fire(me)
step(0.1)
check(win.Visible and string.find(message(), "Quests give a token"), "so does the token machine")
me:SetAttribute("SpireFloor", 2)
step(0.1)
check(not spin1.Visible and textOn(detail, "Go to the Arcade in the lobby") ~= nil, "on a Spire floor you can look but not spin")
step(3)
check(song.Volume < 0.01 and math.abs(lobbyMusic.Volume - 0.7) < 1e-6, "away from the lobby the Arcade's song goes and the lobby's comes back (" .. lobbyMusic.Volume .. ")")
me:SetAttribute("SpireFloor", nil)
step(0.1)
check(spin1.Visible, "back in the lobby: SPIN again")
-- until the new sounds are uploaded, the older ones stand in
for _, name in ipairs(NEW_SOUNDS) do
	SoundService:FindFirstChild(name):Destroy()
end
bd.Tokens = 0
d.Tokens = 5
step(1)
played = {}
AS.rng = { NextNumber = function()
	return 0.93
end }
press(spin1)
step(0.5)
UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
step(1.4)
AS.rng = realRng
check(card.Visible and (played["Legendary Reveal"] or 0) == 1, "without them, a Legendary still gets the old fanfare")
press(button(card, "^DONE$"))
step(0.1)
press(closeBtn)
me:SetAttribute("Intro", "Void")
step(0.1)
check(rollBtn.Visible == false, "in the intro there's no ROLL button")
open:Fire()
step(0.1)
check(not win.Visible, "and the menu won't open")
me:SetAttribute("Intro", nil)
step(0.1)
check(rollBtn.Visible, "after it, the ROLL button")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
check(#M.errors == 0, "no errors")
check((M.warnings or 0) == 0, "no warnings (" .. tostring(M.warnings) .. ")")
if fails == 0 then
	print("PASS arcade (screen)")
else
	print(fails .. " failures")
end
