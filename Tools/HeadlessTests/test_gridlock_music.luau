-- Gridlock's song: round 1 plays his theme, round 2 (after GRAVITY FLIP!)
-- the harder version of it, and one that isn't uploaded yet falls back to
-- the next in line (Round2Music -> Music -> FallbackMusic). Both his songs
-- are exactly 96 bars at his Bpm, so BossClient can swap them at the same spot.
--   luau test_gridlock_music.luau
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)

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
local Body = mount.require(mount.module("ReplicatedStorage/BossBodies/Gridlock.lua"))
local def = Config.Bosses[6]
check(def.Short == "Gridlock" and def.Bpm == 128, "floor 6 is Gridlock, at 128 beats a minute")
check(math.abs(96 * 4 * 60 / def.Bpm - 180) < 1e-9, "96 bars at his Bpm is exactly 180 s (the songs' length)")

-- the sounds that are "in SoundService"
local have = {}
local kit = setmetatable({
	findSound = function(name)
		return have[name]
	end,
}, { __index = function()
	return function() end
end })
Body.init(kit)

local model = M.Instance.new("Model")
local B = { def = def, model = model }
local function pick(phase)
	model:SetAttribute("Phase", phase)
	B.songPick = nil -- (skip the second-long memory)
	return Body.music(B, 0)
end

have = { [def.Music] = true, [def.Round2Music] = true, [def.FallbackMusic] = true }
check(pick(1) == "Gridlock Theme", "round 1: his theme")
local song, vol = pick(2)
check(song == "Gridlock Theme Flip" and vol == def.Round2MusicVolume, "round 2: the harder version, at its volume")

have = { [def.FallbackMusic] = true }
check(pick(1) == "Gridlock Song" and pick(2) == "Gridlock Song", "not uploaded yet: your own song plays in both rounds")

have = { [def.Music] = true, [def.FallbackMusic] = true }
check(pick(2) == "Gridlock Theme", "round 2's version missing: round 1's theme carries on")

have = {}
check(pick(1) == def.Music, "none at all: his Music (BossClient then borrows Oozark's)")

-- asked every frame: kept for a second
have = { [def.Music] = true }
model:SetAttribute("Phase", 1)
B.songPick = nil
Body.music(B, 0)
have = { [def.FallbackMusic] = true }
check(Body.music(B, 0) == def.Music, "the answer is kept for a moment (no hunting every frame)")
model:SetAttribute("Phase", 2)
check(Body.music(B, 0) == def.FallbackMusic, "...but a new round asks again straight away")

if fails == 0 then
	print("PASS test_gridlock_music")
else
	print("FAIL test_gridlock_music: " .. fails)
end
