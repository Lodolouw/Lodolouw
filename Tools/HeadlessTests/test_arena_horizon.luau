-- THE HORIZON (ArenaAmbience + Config.Spire.Horizon): in every arena the far
-- distance melts into that arena's own sky, so the other islands are never
-- seen. Walk into each floor: the air is at least the horizon's (Density,
-- Offset, Haze), in that arena's own colour; the sandstorm can still go
-- thicker; walk out and the lobby's air comes back exactly as it was.
--   luau test_arena_horizon.luau
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Players, Lighting = M.services.Players, M.services.Lighting
local Color3 = M.Color3

local fails = 0
local function check(ok, msg)
	if ok then
		print("  ok   " .. msg)
	else
		fails += 1
		print("  FAIL " .. msg)
	end
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local H = Config.Spire.Horizon

-- the lobby's own air (as LobbyBuilder makes it)
local atmo = M.Instance.new("Atmosphere")
atmo.Name = "LobbyAtmosphere"
atmo.Density, atmo.Offset, atmo.Haze, atmo.Glare = 0.26, 0.15, 0.4, 0
atmo.Color, atmo.Decay = Color3.fromRGB(176, 190, 220), Color3.fromRGB(110, 116, 136)
atmo.Parent = Lighting
Lighting.ClockTime = 15.5

local me = M.Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
M.players = { me }
Players.LocalPlayer = me
local cam = M.Instance.new("Camera")
cam.CFrame = M.CFrame.new(0, 10, 30)
cam.Focus = M.CFrame.new(0, 3, 0)
cam.Parent = M.workspace
M.workspace.CurrentCamera = cam

mount.runClient("StarterPlayerScripts/ArenaAmbience.client.lua", me)
-- frames: everything scheduled, then a RenderStepped, 30 times a second
local RunService = M.services.RunService
local function play(seconds)
	local stop = M.now() + seconds
	while M.now() < stop do
		M.run(M.now() + 1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
		RunService.Heartbeat:Fire(1 / 30)
	end
end
play(1)

local function near(a, b)
	return math.abs(a - b) < 0.02
end
for _, f in ipairs(Config.Spire.Floors) do
	me:SetAttribute("SpireFloor", f.id)
	play(6)
	local amb = f.ambience or {}
	local own = (amb.Horizon or {})
	local want = {}
	for _, key in ipairs({ "Density", "Offset", "Haze" }) do
		local calm = amb.Atmosphere and amb.Atmosphere[key]
		want[key] = math.max(calm or 0, own[key] or H[key])
	end
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	check(f.ambience ~= nil, ("floor %d (%s) has a look of its own"):format(f.id, f.area))
	check(a and near(a.Density, want.Density) and near(a.Offset, want.Offset) and near(a.Haze, want.Haze),
		("floor %d: the far distance melts away (Density %.2f, Offset %.2f, Haze %.1f)"):format(f.id, a and a.Density or -1, a and a.Offset or -1, a and a.Haze or -1))
	local col = amb.Atmosphere and amb.Atmosphere.Color
	if col then
		check(a.Color.R == col.R and a.Color.G == col.G and a.Color.B == col.B, ("floor %d: ...into its own sky's colour"):format(f.id))
	end
	me:SetAttribute("SpireFloor", nil)
	play(6)
end
local a = Lighting:FindFirstChildOfClass("Atmosphere")
check(a and near(a.Density, 0.26) and near(a.Offset, 0.15) and near(a.Haze, 0.4) and near(Lighting.ClockTime, 15.5),
	"back in the lobby: its own air and time of day, exactly")
check(H.Density >= 0.4 and H.Offset >= 0.85, "the horizon is thick enough to hide islands 2600 studs away")

check(#(M.errors or {}) == 0, "no errors (" .. #(M.errors or {}) .. ")")

if fails == 0 then
	print("PASS test_arena_horizon")
else
	print("FAIL test_arena_horizon: " .. fails)
end
