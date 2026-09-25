--[[
	LobbyFX  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "LobbyFX")

	Animates every part the lobby builder tagged "FX". This is purely cosmetic and
	runs on each client, so the server never has to move anything.

	Attributes read from each part (all optional):
	  SpinSpeed    degrees/second around the world Y axis
	  BobAmp       how far it bobs up and down (studs)
	  BobSpeed     bob speed
	  Phase        starting offset in degrees (orbit angle + bob phase)
	  OrbitRadius, OrbitSpeed, OrbitCenter   circle around a point

	Parts tagged "Pulse" fade their glow in and out (like breathing, or a
	heartbeat with PulseHeart = true). Attributes: PulseSpeed, PulseMin,
	PulseMax (transparency range), Phase. Any light inside pulses too.

	Parts tagged "WatchingEye" turn to look at your character (anything
	parented inside them, like the iris and pupil, turns with them).
	MaxTurn = how far (degrees) the eye can turn from where it faces.

	Parts tagged "Wave" (the sea's foam and wave crests) move in little 8-bit
	steps, twelve times a second. WaveDir = which way, WaveAmp = how far,
	WaveSpeed, Phase. WaveMode "lap" goes out and back (foam on the shore);
	"drift" slides one way while fading in and out, then starts again
	(crests rolling in over the sea).

	Models tagged "Rotor" (like the windmill's sails) turn round their
	PrimaryPart's front-to-back axis. RotorSpeed = degrees per second.
	RotorStep = degrees per jump, for an 8-bit look: the sails snap from
	one angle to the next like frames of a sprite instead of gliding
	(0 or missing = smooth).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local TAG = "FX"
local tracked = {}

-- Safety net: this loop forces a part's position back to a fixed spot every
-- frame, which would freeze a player in place if the "FX" tag ever ended up
-- on their character (or anything inside it) by accident - e.g. tagging
-- something in Studio while your character was nearby. Never animate
-- anything that's part of a player's character, tagged or not.
local function isInsideACharacter(inst)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and inst:IsDescendantOf(char) then
			return true
		end
	end
	return false
end

local function add(inst)
	if not inst:IsA("BasePart") or tracked[inst] or isInsideACharacter(inst) then
		return
	end
	tracked[inst] = {
		base = inst.CFrame,
		spin = inst:GetAttribute("SpinSpeed") or 0,
		bobAmp = inst:GetAttribute("BobAmp") or 0,
		bobSpeed = inst:GetAttribute("BobSpeed") or 2,
		phase = inst:GetAttribute("Phase") or 0,
		radius = inst:GetAttribute("OrbitRadius") or 0,
		orbitSpeed = inst:GetAttribute("OrbitSpeed") or 0,
		center = inst:GetAttribute("OrbitCenter"),
	}
end

for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	add(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	tracked[inst] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for inst, d in pairs(tracked) do
		if inst.Parent then
			local pos = d.base.Position
			if d.radius > 0 and d.center then
				local a = math.rad(d.phase + d.orbitSpeed * t)
				pos = d.center + Vector3.new(math.cos(a) * d.radius, 0, math.sin(a) * d.radius)
			end
			if d.bobAmp ~= 0 then
				pos = pos + Vector3.new(0, d.bobAmp * math.sin(t * d.bobSpeed + math.rad(d.phase)), 0)
			end
			local rot = d.base - d.base.Position
			inst.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(d.spin * t), 0) * rot
		else
			tracked[inst] = nil
		end
	end
end)

----------------------------------------------------------------------
-- Pulsing glow
----------------------------------------------------------------------
local pulsing = {}
local function addPulse(inst)
	if not inst:IsA("BasePart") or pulsing[inst] then
		return
	end
	local lights = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Light") then
			lights[d] = d.Brightness
		end
	end
	pulsing[inst] = {
		speed = inst:GetAttribute("PulseSpeed") or 1,
		lo = inst:GetAttribute("PulseMin") or 0,
		hi = inst:GetAttribute("PulseMax") or 0.6,
		phase = math.rad(inst:GetAttribute("Phase") or 0),
		heart = inst:GetAttribute("PulseHeart") == true,
		lights = lights,
	}
end
for _, inst in ipairs(CollectionService:GetTagged("Pulse")) do
	addPulse(inst)
end
CollectionService:GetInstanceAddedSignal("Pulse"):Connect(addPulse)
CollectionService:GetInstanceRemovedSignal("Pulse"):Connect(function(inst)
	pulsing[inst] = nil
end)

-- 0..1 glow amount at time t
local function glowAt(d, t)
	if d.heart then
		-- "lub-dub": two quick beats, then a rest
		local c = (t * d.speed + d.phase / (2 * math.pi)) % 1
		local beat = math.max(0, 1 - math.abs(c - 0.1) * 12) + 0.7 * math.max(0, 1 - math.abs(c - 0.3) * 12)
		return math.min(1, beat)
	end
	return 0.5 + 0.5 * math.sin(t * d.speed * 2 + d.phase)
end

----------------------------------------------------------------------
-- Watching eyes
----------------------------------------------------------------------
local eyes = {}
local function addEye(inst)
	if not inst:IsA("BasePart") or eyes[inst] then
		return
	end
	local parts = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[d] = inst.CFrame:ToObjectSpace(d.CFrame)
		end
	end
	eyes[inst] = {
		base = inst.CFrame,
		current = inst.CFrame,
		maxTurn = math.rad(inst:GetAttribute("MaxTurn") or 45),
		parts = parts,
	}
end
for _, inst in ipairs(CollectionService:GetTagged("WatchingEye")) do
	addEye(inst)
end
CollectionService:GetInstanceAddedSignal("WatchingEye"):Connect(addEye)
CollectionService:GetInstanceRemovedSignal("WatchingEye"):Connect(function(inst)
	eyes[inst] = nil
end)

local localPlayer = Players.LocalPlayer

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for inst, d in pairs(pulsing) do
		if inst.Parent then
			local g = glowAt(d, t)
			inst.Transparency = d.hi + (d.lo - d.hi) * g
			for light, bright in pairs(d.lights) do
				light.Brightness = bright * (0.35 + 0.65 * g)
			end
		else
			pulsing[inst] = nil
		end
	end

	local char = localPlayer and localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local target = root and root.Position or (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position)
	if not target then
		return
	end
	for inst, d in pairs(eyes) do
		if inst.Parent then
			local pos = d.base.Position
			local want = (target - pos)
			if want.Magnitude > 0.1 then
				want = want.Unit
				local fwd = d.base.LookVector
				local angle = math.acos(math.clamp(fwd:Dot(want), -1, 1))
				if angle > d.maxTurn then
					-- turn as far as allowed towards the target
					local k = d.maxTurn / angle
					want = (fwd * (1 - k) + want * k).Unit
				end
				local goal = CFrame.lookAt(pos, pos + want)
				d.current = d.current:Lerp(goal, math.min(1, dt * 4))
				inst.CFrame = d.current
				for p, offset in pairs(d.parts) do
					p.CFrame = d.current * offset
				end
			end
		else
			eyes[inst] = nil
		end
	end
end)

----------------------------------------------------------------------
-- Rotors: the windmill's sails turning round their hub
----------------------------------------------------------------------
local rotors = {}
local function addRotor(model)
	if not model:IsA("Model") or rotors[model] then
		return
	end
	local hub = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not hub then
		return
	end
	local parts, offsets = {}, {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(offsets, hub.CFrame:ToObjectSpace(p.CFrame))
		end
	end
	rotors[model] = {
		base = hub.CFrame,
		speed = math.rad(model:GetAttribute("RotorSpeed") or 30),
		step = math.rad(model:GetAttribute("RotorStep") or 0),
		parts = parts,
		offsets = offsets,
		angle = 0,
		shown = nil,
	}
end
for _, m in ipairs(CollectionService:GetTagged("Rotor")) do
	addRotor(m)
end
CollectionService:GetInstanceAddedSignal("Rotor"):Connect(function(m)
	task.defer(addRotor, m) -- (let its parts arrive first)
end)
CollectionService:GetInstanceRemovedSignal("Rotor"):Connect(function(m)
	rotors[m] = nil
end)

RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	for model, r in pairs(rotors) do
		if not model.Parent then
			rotors[model] = nil
		else
			r.angle = (r.angle + r.speed * dt) % (math.pi * 2)
			-- the angle it's drawn at: snapped to whole steps for the 8-bit look
			local shown = r.angle
			if r.step > 0 then
				shown = math.floor(r.angle / r.step) * r.step
			end
			-- (only moved when that changes, and when someone could see it)
			if shown ~= r.shown and (not cam or (cam.CFrame.Position - r.base.Position).Magnitude < 500) then
				r.shown = shown
				local hubCF = r.base * CFrame.Angles(0, 0, shown)
				local cfs = table.create(#r.parts)
				for i, off in ipairs(r.offsets) do
					cfs[i] = hubCF * off
				end
				workspace:BulkMoveTo(r.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
end)

----------------------------------------------------------------------
-- Waves: foam lapping at the shore, crests drifting in over the sea
----------------------------------------------------------------------
local waves = {}
local function addWave(inst)
	if not inst:IsA("BasePart") or waves[inst] then
		return
	end
	local dir = inst:GetAttribute("WaveDir")
	if typeof(dir) ~= "Vector3" then
		return
	end
	waves[inst] = {
		base = inst.CFrame,
		dir = dir,
		amp = inst:GetAttribute("WaveAmp") or 2,
		speed = inst:GetAttribute("WaveSpeed") or 1,
		phase = math.rad(inst:GetAttribute("Phase") or 0),
		drift = inst:GetAttribute("WaveMode") == "drift",
		baseTr = inst.Transparency,
	}
end
for _, inst in ipairs(CollectionService:GetTagged("Wave")) do
	addWave(inst)
end
CollectionService:GetInstanceAddedSignal("Wave"):Connect(addWave)
CollectionService:GetInstanceRemovedSignal("Wave"):Connect(function(inst)
	waves[inst] = nil
end)

local STEP = 1 / 12 -- (twelve frames a second: the 8-bit look)
local SNAP = 0.5 -- (and moved in half-stud jumps)
local waveClock = 0
RunService.Heartbeat:Connect(function(dt)
	waveClock = waveClock + dt
	if waveClock < STEP then
		return
	end
	waveClock = 0
	local t = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	local parts, cfs = {}, {}
	for inst, w in pairs(waves) do
		if not inst.Parent then
			waves[inst] = nil
		elseif not camPos or (camPos - w.base.Position).Magnitude < 800 then
			local off, tr
			if w.drift then
				local f = (t * w.speed + w.phase / (2 * math.pi)) % 1
				off = w.amp * f
				tr = w.baseTr + (1 - w.baseTr) * (1 - math.sin(f * math.pi))
			else
				local g = 0.5 + 0.5 * math.sin(t * w.speed + w.phase)
				off = w.amp * g
				tr = w.baseTr + (1 - w.baseTr) * 0.25 * g -- (a little fainter the further out it reaches)
			end
			off = math.floor(off / SNAP + 0.5) * SNAP
			tr = math.floor(tr * 4 + 0.5) / 4
			table.insert(parts, inst)
			table.insert(cfs, w.base + w.dir * off)
			if inst.Transparency ~= tr then
				inst.Transparency = tr
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
