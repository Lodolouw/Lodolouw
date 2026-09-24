--[[
	RollDebug  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "RollDebug")

	A temporary tool for working out what the dodge roll is doing. Press Q (or
	the gamepad's B) and it prints one line per frame for 1.5 seconds showing
	everything that could be going wrong, then a summary.

	Delete this script once the roll is fixed.

	Reading the lines:
	  t      seconds since you pressed roll
	  state  what Roblox thinks your character is doing (Running / Freefall /
	         FallingDown / Ragdoll / Physics / Landed / PlatformStanding)
	  vel    your speed: sideways / up-down (studs per second)
	  moved  how far you've travelled since you pressed roll
	  tilt   how upright you are: 1.00 is standing, 0 is lying on its side
	  ws     WalkSpeed        cm  the ControllerManager's BaseMoveSpeed
	  push   yes = the roll's push is still on you
	  anims  which animations are playing right now
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local WATCH_SECONDS = 1.5

local function parts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then
		return nil
	end
	return hum, hrp, char
end

local function playingAnims(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return "no animator"
	end
	local names = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local id = track.Animation and track.Animation.AnimationId or "?"
		names[#names + 1] = id:gsub("rbxassetid://", "") .. string.format("(%.2fs)", track.TimePosition)
	end
	return #names > 0 and table.concat(names, " ") or "none"
end

local watching = false

local function watch()
	if watching then
		return
	end
	local hum, hrp, char = parts()
	if not hum then
		return
	end
	watching = true
	local startAt = os.clock()
	local startPos = hrp.Position
	local maxSpeed, minTilt, states = 0, 1, {}
	print("================ ROLL DEBUG ================")
	print(string.format("rig: %s   collisions on HRP: %s   anchored: %s", hum.RigType.Name, tostring(hrp.CanCollide), tostring(hrp.Anchored)))

	local conn
	conn = RunService.Heartbeat:Connect(function()
		local h, root, ch = parts()
		if not h or ch ~= char then
			conn:Disconnect()
			watching = false
			print("character changed - stopped watching")
			return
		end
		local t = os.clock() - startAt
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		local tilt = root.CFrame.UpVector.Y -- 1 = upright, 0 = on its side
		local state = h:GetState().Name
		states[state] = true
		maxSpeed = math.max(maxSpeed, flat)
		minTilt = math.min(minTilt, tilt)
		local cm = ch:FindFirstChildWhichIsA("ControllerManager", true)
		print(string.format(
			"t=%.2f  state=%-14s vel=%5.1f/%6.1f  moved=%5.1f  tilt=%.2f  ws=%.0f  cm=%s  push=%s  anims=%s",
			t,
			state,
			flat,
			v.Y,
			(root.Position - startPos).Magnitude,
			tilt,
			h.WalkSpeed,
			cm and string.format("%.0f", cm.BaseMoveSpeed) or "-",
			root:FindFirstChild("CombatPush") and "yes" or "no",
			playingAnims(h)
		))
		if t >= WATCH_SECONDS then
			conn:Disconnect()
			watching = false
			local list = {}
			for s in pairs(states) do
				list[#list + 1] = s
			end
			print(string.format(
				"---- summary: travelled %.1f studs, top speed %.1f, most tipped %.2f (1 = upright), states seen: %s",
				(root.Position - startPos).Magnitude,
				maxSpeed,
				minTilt,
				table.concat(list, ", ")
			))
			print("===========================================")
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
		watch()
	end
end)

print("[RollDebug] ready - go into the arena and press Q to record a roll")
