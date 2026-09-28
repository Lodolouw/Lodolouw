--[[
	CanvasPlan  (ModuleScript, parent: ReplicatedStorage, name: "CanvasPlan")

	The shape of Scribble's arena, The Canvas (floor 9), and the sums his
	moves share, in one place - so the arena (CanvasBuilder), his moves
	(ServerScriptService/Bosses/Scribble) and every player's screen
	(ReplicatedStorage/BossBodies/Scribble) all agree exactly.

	THE PAPER, seen from above (distances are from the middle, where Scribble
	stands at the start; +Z is south, where the [X] door is):
	  * a square sheet of graph paper, Half studs out each way (120 x 120)
	  * thin grid lines every Fine studs, thick ones every Cell studs: the
	    thick lines cut it into 6 x 6 big squares - the PAINT BUCKET floods one
	    of those squares (CanvasPlan.cellOf gives the square a spot is in)
	  * a red margin line down the west side, like notebook paper
	  * round it, the window of a paint program: its title bar
	    ("SCRIBBLE.EXE") standing up behind the north edge, a toolbar of giant
	    tools down the west side, colour swatches down the east side, and the
	    [X] close button in the south edge - the way out

	ROUND 3 ERASES IT: the paper is erased from the edges in. How far out it's
	still solid is `paper` (studs from the middle each way); while a DELETE
	box is up, the erasing creeps from `paper` in to `to` between `t0` and
	`t1` (CanvasPlan.paperAt). Anywhere outside that square is erased paper
	(it hurts to stand on).
]]

local CanvasPlan = {}

CanvasPlan.Half = 60 -- the paper: this far out each way from the middle
CanvasPlan.Cell = 20 -- the thick grid lines (the Paint Bucket's squares)
CanvasPlan.Fine = 4 -- the thin grid lines
CanvasPlan.Margin = -50 -- the red margin line (x, from the middle)
CanvasPlan.DoorHalf = 7 -- half the width of the [X] door in the south edge

-- the middle of the big grid square a spot is in (dx, dz: from the middle
-- of the paper), never off the paper
function CanvasPlan.cellOf(dx, dz)
	local c = CanvasPlan.Cell
	local lim = CanvasPlan.Half - c / 2
	local x = (math.floor(dx / c) + 0.5) * c
	local z = (math.floor(dz / c) + 0.5) * c
	return math.clamp(x, -lim, lim), math.clamp(z, -lim, lim)
end

-- a spot pulled inside a square `half` studs out each way, `margin` in from
-- its edge
function CanvasPlan.inside(dx, dz, half, margin)
	local h = math.max(0, half - (margin or 0))
	return math.clamp(dx, -h, h), math.clamp(dz, -h, h)
end

-- is a spot on the solid paper (a square `half` out each way)?
function CanvasPlan.onPaper(dx, dz, half)
	return math.abs(dx) <= half and math.abs(dz) <= half
end

-- how far out the paper is still solid at time t: `paper`, or - while it's
-- being erased - creeping from `paper` to `to` between t0 and t1
function CanvasPlan.paperAt(paper, to, t0, t1, t)
	if type(to) ~= "number" or type(t0) ~= "number" or type(t1) ~= "number" or t <= t0 then
		return paper
	end
	if t >= t1 or t1 <= t0 then
		return to
	end
	return paper + (to - paper) * (t - t0) / (t1 - t0)
end

-- the paper's edge as the boss model says right now (its Paper, EraseTo,
-- EraseStart and EraseEnd attributes: see Bosses/Scribble)
function CanvasPlan.paperNow(model, t)
	local paper = model:GetAttribute("Paper") or CanvasPlan.Half
	return CanvasPlan.paperAt(paper, model:GetAttribute("EraseTo"), model:GetAttribute("EraseStart"),
		model:GetAttribute("EraseEnd"), t)
end

-- THE DELETE BOX stands on one side of the paper (1 = north, 2 = east,
-- 3 = south, 4 = west), facing the middle, right at the edge the paper is
-- being erased to (`to`). CanvasPlan.promptSpots gives, from the middle of
-- the paper: where the box stands (the middle of its bottom edge), the way
-- it faces (into the paper), and where its NO button is (the one to punch,
-- ButtonUp studs off the floor) and its YES button.
CanvasPlan.Sides = {
	Vector3.new(0, 0, -1), -- north
	Vector3.new(1, 0, 0), -- east
	Vector3.new(0, 0, 1), -- south
	Vector3.new(-1, 0, 0), -- west
}
CanvasPlan.BoxWidth = 26 -- the DELETE box: how wide...
CanvasPlan.BoxHeight = 15 -- ...and tall
CanvasPlan.ButtonUp = 3.2 -- how high its buttons' middles are (punch height)
CanvasPlan.ButtonApart = 6 -- how far each button is from the box's middle
function CanvasPlan.promptSpots(side, to)
	local out = CanvasPlan.Sides[side] or CanvasPlan.Sides[1]
	local face = -out -- (it faces into the paper)
	local right = Vector3.new(-out.Z, 0, out.X) -- (to your right as you stand looking at it: NO is on the right)
	local base = out * (to - 1)
	local no = base + face * 1.2 + right * CanvasPlan.ButtonApart
	local yes = base + face * 1.2 - right * CanvasPlan.ButtonApart
	return base, face, no, yes
end

return CanvasPlan
