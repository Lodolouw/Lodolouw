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

local folder = Instance.new("Folder")
folder.Name = "WeaponModels"
folder.Parent = ReplicatedStorage

me:SetAttribute("SpireFloor", 2)
for _, key in ipairs({ "Jellyblade", "GooGloves", "GelatinHammer", "OozeDaggers", "AcidScythe", "GelatinousEdge" }) do
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
				check(((names.Goo or 0) > 0) == (tier >= 3), key .. ": goo flies off the tip (" .. tostring(names.Goo or 0) .. ")")
				check(((names.GooHeart or 0) > 0) == (tier >= 6), key .. ": glowing hearts in the goo only on the Secret")
				check(((names.JellyWave or 0) > 0) == (tier >= 6), key .. ": the jelly wave only on the Secret")
				check(((names.OozarkEye or 0) > 0) == (tier >= 6), key .. ": Oozark's eyes only on the Secret")
				h.handle.CFrame = start
				step(3)
				local left = folder and #folder:GetChildren() or 0
				check(left == 0 and #WeaponFX._goo == 0, key .. ": the goo lands, splats and is gone (" .. left .. " left)")
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
