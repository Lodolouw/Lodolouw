--!nocheck
-- Headless test of holding the VOXEL WEAPONS' models (WeaponFX "buildVoxel";
-- the models: Tools/Weapons, their facts: ReplicatedStorage/WeaponModelInfo).
-- A pretend imported model - its meshes turned, moved and scaled any old way,
-- the way an importer might bring it in - is put in ReplicatedStorage >
-- WeaponModels, and it checks:
--   * it's held exactly like the blocky stand-in: each mesh sits where the
--     markers say, in the handle's own space, at its true size
--   * the markers are gone, each mesh has its colour and material from the list
--   * gauntlets and daggers: one in each hand
--   * awakened (mastery 100): its metal turns gold
--   * before its model arrives it's the blocky one, and the real one swaps in
--     the moment it does
--   * its swing effects by rarity, in its pack's theme (Slime goo, Knight dirt
--     and gold, Speedway sparks and fire, Jungle leaves, bananas and
--     splinters, Canvas ink, paper and pixels), the Secrets' own shows, and
--     their sounds (Knight's and Jungle's new ones; Speedway's and Canvas's
--     falling back on older ones, as if their new sounds weren't uploaded yet)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local function part(model, name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new()
	p.Parent = model
	return p
end
local function motor(name, parent, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = p0, p1
	m.C0, m.C1 = c0, c1
	m.Transform = CFrame.new()
	m.Parent = parent
	return m
end
local function r6(name)
	local model = Instance.new("Model")
	model.Name = name
	local hrp = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1))
	local torso = part(model, "Torso", Vector3.new(2, 2, 1))
	local arm = part(model, "Right Arm", Vector3.new(1, 2, 1))
	local larm = part(model, "Left Arm", Vector3.new(1, 2, 1))
	local rleg = part(model, "Right Leg", Vector3.new(1, 2, 1))
	local lleg = part(model, "Left Leg", Vector3.new(1, 2, 1))
	local head = part(model, "Head", Vector3.new(2, 1, 1))
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.MoveDirection = Vector3.new(0, 0, 0)
	hum.Parent = model
	motor("Right Shoulder", torso, torso, arm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, torso, larm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, torso, rleg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, torso, lleg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("RootJoint", hrp, hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	model.Parent = M.workspace
	return model, hum
end

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char, hum = r6("Tester")
me.Character = char
M.players = { me }
local animator = Instance.new("Animator")
animator.Parent = hum
animator.GetPlayingAnimationTracks = function()
	return {}
end

local Info = mount.require(mount.module("ReplicatedStorage/WeaponModelInfo.lua"))
local WeaponFX = mount.require(mount.module("ReplicatedStorage/WeaponFX.lua"))
WeaponFX.start()

local t = 0
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Stepped:Fire(t, 1 / 60)
		RunService.Heartbeat:Fire(1 / 60)
	end
end

-- a pretend imported model: every mesh from the list at a made-up spot in
-- weapon space, all of it scaled, turned and moved any old way
local IMPORT = CFrame.new(40, 7, -12) * CFrame.Angles(0.4, 1.3, -0.7)
local SCALE = 2.5
local function place(w)
	-- weapon space (x, y, z: +Z up the weapon) -> where the importer put it
	return IMPORT * (w * SCALE)
end
local where = {} -- [key] = { [mesh] = its spot in weapon space }
local function fakeModel(key)
	local info = Info[key]
	local m = Instance.new("Model")
	m.Name = key
	where[key] = {}
	local i = 0
	for name in pairs(info.Parts) do
		i += 1
		local w = Vector3.new(0.1 * (i % 3) - 0.1, -0.05 * (i % 4), 0.4 * i)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.3, 0.2, 0.5) * SCALE
		p.CFrame = CFrame.new(place(w)) * (IMPORT - IMPORT.Position)
		p.Color = M.Color3.fromRGB(128, 128, 128)
		p.Parent = m
		where[key][name] = w
	end
	for name, w in pairs({ GripMark = Vector3.new(0, 0, 0), TipMark = Vector3.new(0, 0, info.Tip), UpMark = Vector3.new(0, -info.Up, 0) }) do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.08, 0.08, 0.08) * SCALE
		p.CFrame = CFrame.new(place(w))
		p.Parent = m
	end
	return m
end

-- the swing sounds, in SoundService like the game has them (SoundLoader)
for _, name in ipairs({ "Goo Swish", "Goo Splat", "Acid Swish", "Acid Hiss", "Jelly Swing", "Jelly Wave", "Eye Pop", "Goo Hit",
	"Shovel Swish", "Dirt Splat", "Clang Hit", "Chain Swish", "Gold Swing", "Gold Chop", "Coin Spill", "Plate Crack", "Treasure Glint",
	"Leaf Swish", "Leaf Rustle", "Barrel Swing", "Splinter Crack", "Crown Swing", "Banana Bounce", "Vine Whip", "Ape Grunt",
	-- (Speedway's and Canvas's new sounds left out: these are what they fall back on)
	"Sword Swing", "Hammer Swing", "Checkered Flag", "Big Honk", "Scythe Swing", "Lag Glitch", "Error Pop" }) do
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.Volume, snd.PlaybackSpeed, snd.TimeLength = 0.6, 1, 0.4
	snd.Parent = M.services.SoundService
end
local function soundsPlaying()
	local out = {}
	for _, d in ipairs(M.workspace:GetDescendants()) do
		if d:IsA("Sound") then
			out[d.Name] = (out[d.Name] or 0) + 1
		end
	end
	return out
end

local folder = Instance.new("Folder")
folder.Name = "WeaponModels"
folder.Parent = ReplicatedStorage

me:SetAttribute("SpireFloor", 2)
-- each pack's swing effects: what it throws, its Secret's wave and eyes, the
-- swing sound heard for each rarity (Epic, Legendary, Mythic, Secret) and
-- the Secret's wave and eye sounds
local THEMED = {
	Slime = { bits = { Goo = true }, wave = "JellyWave", eyes = "OozarkEye",
		swing = { [3] = "Goo Swish", [4] = "Goo Swish", [5] = "Acid Swish", [6] = "Jelly Swing" }, waveSound = "Jelly Wave", eyeSound = "Eye Pop" },
	Knight = { bits = { Clod = true, Glint = true, Chip = true, Coin = true }, wave = "GoldCrack", eyes = "VisorEye",
		swing = { [3] = "Shovel Swish", [4] = "Shovel Swish", [5] = "Chain Swish", [6] = "Gold Swing" }, waveSound = "Plate Crack", eyeSound = "Treasure Glint" },
	Speedway = { bits = { Spark = true, Smoke = true, Flame = true, Confetti = true }, wave = "CheckerWave", eyes = "RevvEye",
		swing = { [3] = "Sword Swing", [4] = "Sword Swing", [5] = "Hammer Swing", [6] = "Sword Swing" }, waveSound = "Checkered Flag", eyeSound = "Big Honk", quiet = true },
	-- (quiet: Victory Lap's flag and eyes still show, but the fanfare and honks
	-- were taken off - they got annoying swing after swing)
	Jungle = { bits = { Leaf = true, Banana = true, Splinter = true, Chip = true, Smoke = true, Glint = true }, wave = "VineWave", eyes = "KongoEye",
		swing = { [3] = "Leaf Swish", [4] = "Leaf Swish", [5] = "Barrel Swing", [6] = "Crown Swing" }, waveSound = "Vine Whip", eyeSound = "Ape Grunt" },
	Canvas = { bits = { Ink = true, Paper = true, Pixel = true }, wave = "GlitchWave", eyes = "DoodleEye",
		swing = { [3] = "Sword Swing", [4] = "Sword Swing", [5] = "Scythe Swing", [6] = "Sword Swing" }, waveSound = "Lag Glitch", eyeSound = "Error Pop" },
}
local OTHER_SHOWS = { "JellyWave", "OozarkEye", "GoldCrack", "VisorEye", "CheckerWave", "RevvEye", "VineWave", "KongoEye", "GlitchWave", "DoodleEye" }
for _, key in ipairs({ "Jellyblade", "GooGloves", "GelatinHammer", "OozeDaggers", "AcidScythe", "GelatinousEdge",
	"ShovelHammer", "RelicDaggers", "SpadeScythe", "HonourBlade", "AnchorFists", "NoQuarter",
	"TyreScythe", "NitroKatana", "PistonPunchers", "PitStopSabre", "WheelieWrecker", "VictoryLap",
	"ChestPoundFists", "JungleFang", "VineScythe", "BarrelDaggers", "BarrelHammer", "KongsCrown",
	"EraserHammer", "PencilSword", "InkFists", "DoodleKatana", "CopyPasteScythe", "DeleteKey" }) do
	local info = Info[key]
	check(info ~= nil, key .. ": is in WeaponModelInfo")
	if info then
		local src = fakeModel(key)
		src.Parent = folder
		me:SetAttribute("Weapon", key)
		step(0.3)
		local h = WeaponFX._held[me]
		local held = char:FindFirstChild("HeldWeapon")
		check(h ~= nil and held ~= nil, key .. ": it's in hand")
		if h and held then
			local handle = held:FindFirstChild("Handle")
			local pairsOf = {} -- [mesh name] = how many (one per hand)
			local marks = 0
			local sat, coloured = true, true
			for _, p in ipairs(held:GetChildren()) do
				if p.Name == "GripMark" or p.Name == "TipMark" or p.Name == "UpMark" then
					marks += 1
				end
				local w = where[key][p.Name]
				if w then
					pairsOf[p.Name] = (pairsOf[p.Name] or 0) + 1
					-- where it sits against the weld's own handle (weapon space -> handle: (x, -y, -z))
					local weld = p:FindFirstChildOfClass("Weld")
					local off = weld and weld.C0.Position
					local want = Vector3.new(w.X, -w.Y, -w.Z)
					if not off or (off - want).Magnitude > 1e-3 then
						sat = false
						print(("  %s.%s sits at %s, wanted %s"):format(key, p.Name, tostring(off), tostring(want)))
					end
					if (p.Size - Vector3.new(0.3, 0.2, 0.5)).Magnitude > 1e-3 then
						sat = false
					end
					local spec = info.Parts[p.Name]
					local c = p.Color
					if math.abs(c.R * 255 - spec.Color[1]) > 1.5 or math.abs(c.G * 255 - spec.Color[2]) > 1.5 or math.abs(c.B * 255 - spec.Color[3]) > 1.5
						or math.abs(p.Transparency - spec.Transparency) > 1e-3 then
						coloured = false
					end
				end
			end
			check(handle ~= nil, key .. ": it has a Handle (what the hand holds)")
			check(marks == 0, key .. ": the markers are gone")
			check(sat, key .. ": every mesh sits where the markers say, at its true size (the import's turn and scale undone)")
			check(coloured, key .. ": every mesh has its colour and see-through-ness from the list")
			local two = info.Type == "Fists" or info.Type == "Daggers"
			local count = 0
			for _ in pairs(pairsOf) do
				count += 1
			end
			local each = true
			for _, n in pairs(pairsOf) do
				each = each and n == (two and 2 or 1)
			end
			check(count > 0 and each, key .. ": " .. (two and "one in each hand" or "one of it"))
			check(held:FindFirstChild("Head") ~= nil, key .. ": it knows where its business end is")
			-- its swing effects, by rarity (WeaponFX "dressTrails")
			local has = {}
			for _, d in ipairs(held:GetDescendants()) do
				has[d.Name] = true
			end
			local def = mount.require(mount.module("ReplicatedStorage/Config.lua")).Weapons.List[key]
			local tier = WeaponFX.RARITY_TIER[def.Rarity]
			check(has.SwingTrail and has.SwingGlow, key .. ": the two smears every weapon has")
			check((has.SwingFan == true) == (tier >= 2), key .. ": the wide crescent from Rare up (" .. def.Rarity .. ")")
			check((has.SwingEdge == true) == (tier >= 3), key .. ": the bright edge from Epic up")
			check((has.SwingDeep == true) == (tier == 5), key .. ": Mythic's second crescent")
			check((has.SwingJelly == true) == (tier >= 6), key .. ": Secret's body of jelly")
			check(not has.SwingHalo and not has.SwingStars, key .. ": no rainbow")
			local all = #h.trails
			check(all == ({ 2, 3, 4, 4, 5, 5 })[tier] * (two and 2 or 1), key .. ": " .. all .. " swing trails, all switched with the smear")
			check((h.trails.fx ~= nil and h.trails.fx.fling ~= nil) == (tier >= 3), key .. ": goo off the tip from Epic up")
			-- a cut, driven through the swing effects: the handle swept round
			do
				local start = h.handle.CFrame
				WeaponFX._swingFx(h, true, true)
				for f = 1, 12 do
					-- (no frame step here: the game's own loop would end the cut)
					h.handle.CFrame = start * CFrame.Angles(0, math.rad(f * 12), 0) + Vector3.new(0, 0, -f * 0.3)
					WeaponFX._swingFx(h, true, false)
				end
				WeaponFX._swingFx(h, false, false)
				local names = {}
				local folder = M.workspace:FindFirstChild("SwingGoo")
				for _, d in ipairs(folder and folder:GetDescendants() or {}) do
					names[d.Name] = (names[d.Name] or 0) + 1
				end
				local th = THEMED[def.Pack]
				local thrown, strays = 0, 0
				for name, n in pairs(names) do
					if th.bits[name] then
						thrown += n
					else
						-- (a kind two packs share - Jungle's iron chips, say - is its own)
						for _, other in pairs(THEMED) do
							if other.bits[name] then
								strays += n
								break
							end
						end
					end
				end
				check((thrown > 0) == (tier >= 3), key .. ": " .. def.Pack .. " bits fly off the tip (" .. thrown .. ")")
				check(strays == 0, key .. ": nothing from another pack's theme (" .. strays .. ")")
				check(((names.GooHeart or 0) > 0) == (tier >= 6 and def.Pack == "Slime"), key .. ": glowing hearts in the goo only on the Slime Secret")
				for _, show in ipairs(OTHER_SHOWS) do
					local want = tier >= 6 and (show == th.wave or show == th.eyes)
					check(((names[show] or 0) > 0) == want, key .. ": " .. show .. (want and " on its Secret" or " not here"))
				end
				local heard = soundsPlaying()
				local swingSound = th.swing[tier]
				check(swingSound == nil or (heard[swingSound] or 0) > 0, key .. ": its swing sound plays (" .. tostring(swingSound) .. ")")
				local loud = tier >= 6 and not th.quiet
				check(((heard[th.waveSound] or 0) > 0) == loud, key .. ": the wave's sound " .. (th.quiet and "never" or "only on the Secret") .. " (" .. th.waveSound .. ")")
				step(0.5)
				check(((soundsPlaying()[th.eyeSound] or 0) > 0) == loud or (not th.quiet and tier < 6), key .. ": the eyes pop " .. (th.quiet and "silently" or "with a sound") .. " (" .. th.eyeSound .. ")")
				h.handle.CFrame = start
				-- (a leaf flutters down for up to 2.2 s, and its rustle's player stays 2 s)
				step(4.5)
				local left, what = folder and #folder:GetChildren() or 0, {}
				for _, d in ipairs(folder and folder:GetChildren() or {}) do
					table.insert(what, d.Name)
				end
				check(left == 0 and #WeaponFX._goo == 0, key .. ": what it threw lands and is gone (" .. left .. " left: " .. table.concat(what, ", ") .. ")")
			end
		end
		src:Destroy()
		me:SetAttribute("Weapon", nil)
		step(0.2)
	end
end

-- awakened: the metal goes gold
do
	local key = "AcidScythe"
	local src = fakeModel(key)
	src.Parent = folder
	me:SetAttribute("Mastery", 100)
	me:SetAttribute("Weapon", key)
	step(0.3)
	local held = char:FindFirstChild("HeldWeapon")
	local gold = false
	for _, p in ipairs(held and held:GetChildren() or {}) do
		local spec = Info[key].Parts[p.Name]
		if spec and spec.Role == "metal" then
			gold = p.Color.R > p.Color.B + 0.2
		end
	end
	check(gold, "awakened: its metal turns gold")
	me:SetAttribute("Weapon", nil)
	me:SetAttribute("Mastery", 1)
	src:Destroy()
	step(0.2)
end

-- gauntlets punch with your own punch animations (no cut to time them by):
-- each punch opens a window, and the fist that flies forward in it gets its
-- smear and throws the pack's stuff (Ink Fists: ink) - not the other fist,
-- not a fist pulled back, not when there's no punch; someone else's punch
-- (their SwingN changing) the same; and a hit splashes ink
do
	local key = "InkFists"
	local src = fakeModel(key)
	src.Parent = folder
	me:SetAttribute("Weapon", key)
	step(0.3)
	local h = WeaponFX._held[me]
	check(h ~= nil and h.punch and h.fists ~= nil and #h.fists == 2, "gauntlets: both fists ready to punch")
	if h and h.fists and #h.fists == 2 then
		local right, left = h.fists[1], h.fists[2]
		local hrp = char.HumanoidRootPart
		local function lit(f)
			for _, tr in ipairs(f.trails) do
				if tr.Enabled then
					return true
				end
			end
			return false
		end
		local function thrown()
			local n = 0
			local goo = M.workspace:FindFirstChild("SwingGoo")
			for _, d in ipairs(goo and goo:GetChildren() or {}) do
				if d.Name == "Ink" or d.Name == "Paper" or d.Name == "Splat" then
					n += 1
				end
			end
			return n
		end
		-- (a fist moved `dz` studs a frame along your facing, for n frames)
		local function frames(f, n, dz)
			for _ = 1, n do
				f.handle.CFrame = f.handle.CFrame + hrp.CFrame.LookVector * dz
				step(1 / 60)
			end
		end
		local rest = right.handle.CFrame
		frames(right, 6, 0.4)
		check(not lit(right) and thrown() == 0, "gauntlets: a fist moving with no punch throws nothing")
		right.handle.CFrame = rest
		step(0.2)
		WeaponFX.punched(me, 1)
		frames(right, 2, 0)
		frames(right, 6, 0.4)
		check(lit(right) and not lit(left), "gauntlets: the punching fist's smear shows, and only its")
		check(thrown() > 0, "gauntlets: the punch throws the pack's stuff (" .. thrown() .. ")")
		frames(right, 5, -0.4)
		check(not lit(right), "gauntlets: pulling the fist back isn't a punch")
		step(0.6)
		check(not lit(right) and not lit(left), "gauntlets: the window closes after the punch")
		-- someone else's punch: their SwingN changes
		step(3)
		me:SetAttribute("SwingN", "99:2")
		frames(left, 2, 0)
		frames(left, 6, 0.4)
		check(lit(left) and not lit(right), "gauntlets: a punch seen through SwingN lights the fist that flies (the left)")
		step(3)
		-- a hit: ink splashes off what you hit
		local before = thrown()
		WeaponFX.punchMark(hrp.Position + hrp.CFrame.LookVector * 4, false, false, mount.require(mount.module("ReplicatedStorage/Config.lua")).Weapons.List[key])
		check(thrown() > before, "gauntlets: a hit splashes ink off what you hit")
		step(3)
	end
	src:Destroy()
	me:SetAttribute("Weapon", nil)
	step(0.2)
end

-- its model arriving late: the blocky one first, then the real one
do
	local key = "GelatinHammer"
	me:SetAttribute("Weapon", key)
	step(0.3)
	local held = char:FindFirstChild("HeldWeapon")
	local blocky = held ~= nil
	for _, p in ipairs(held and held:GetChildren() or {}) do
		blocky = blocky and Info[key].Parts[p.Name] == nil
	end
	check(blocky, "before its model's here: the blocky one made in code")
	local src = fakeModel(key)
	src.Parent = folder
	step(0.3)
	held = char:FindFirstChild("HeldWeapon")
	local real = false
	for _, p in ipairs(held and held:GetChildren() or {}) do
		real = real or Info[key].Parts[p.Name] ~= nil
	end
	check(real, "the moment its model arrives, it's swapped in")
end

check(#M.errors == 0, #M.errors .. " errors")
if fails == 0 then
	print("PASS voxelhold")
else
	print(fails .. " failures")
end
