-- Tests the maths WorldBuilder uses to line up the imported Blender map.
-- Run with Lune (https://github.com/lune-org/lune):  lune run FeedTheThing/Tests/MapAlignTest.luau

local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local DESIGN = {
	MapOrigin = Vector3.new(0, -30, 0),
	MapMarkX = Vector3.new(100, -30, 0),
	MapMarkZ = Vector3.new(0, -30, 100),
}
-- some other points of the map, to check they land right too
local POINTS = { Vector3.new(-120, 0, 70), Vector3.new(169, 22, 0), Vector3.new(-199, 12.6, 0) }

local function run(name, importCF, importScale)
	-- what Studio's importer might do: scale about the origin, then place
	local pts = {}
	local function import(p) return importCF * (p * importScale) end
	for k, p in pairs(DESIGN) do pts[k] = import(p) end
	local others = {}
	for i, p in ipairs(POINTS) do others[i] = import(p) end
	local pivot = importCF -- the model's pivot

	-- == the WorldBuilder.alignMap math ==
	local o, x, z = pts.MapOrigin, pts.MapMarkX, pts.MapMarkZ
	local distance = (x - o).Magnitude
	local k = 100 / distance
	local function scaleAbout(p) return pivot.Position + (p - pivot.Position) * k end -- Model:ScaleTo
	o, x, z = scaleAbout(o), scaleAbout(x), scaleAbout(z)
	for i, p in ipairs(others) do others[i] = scaleAbout(p) end
	local ax = (x - o).Unit
	local az = (z - o).Unit
	local up = az:Cross(ax)
	local current = CFrame.fromMatrix(o, ax, up.Unit)
	local target = CFrame.fromMatrix(DESIGN.MapOrigin, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
	local fix = target * current:Inverse() -- model:PivotTo(fix * model:GetPivot()) moves every point by `fix`
	local worst = 0
	for i, p in ipairs(others) do
		worst = math.max(worst, ((fix * p) - POINTS[i]).Magnitude)
	end
	for key, p in pairs({ MapOrigin = o, MapMarkX = x, MapMarkZ = z }) do
		worst = math.max(worst, ((fix * p) - DESIGN[key]).Magnitude)
	end
	print(string.format("%-28s up.Y=%5.2f  worst error %.5f studs  %s", name, up.Y, worst, worst < 0.01 and "OK" or "FAIL"))
end

run("as built", CFrame.new(), 1)
run("moved", CFrame.new(57, 3, -900), 1)
run("1 stud = 28 cm (tiny)", CFrame.new(10, 5, 10), 1 / 3.5714)
run("cm read as metres (huge)", CFrame.new(), 100)
run("turned 90 degrees", CFrame.new(5, 0, 5) * CFrame.Angles(0, math.rad(90), 0), 1)
run("turned 37 deg, moved, scaled", CFrame.new(-40, 12, 300) * CFrame.Angles(0, math.rad(37), 0), 0.28)
