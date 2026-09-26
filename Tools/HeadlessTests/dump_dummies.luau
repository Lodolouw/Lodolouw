-- Builds dummies with the REAL LobbyBuilder code and prints their parts as JSON
local M = require("./rbxmock")
local S = require("./sources")
local env = M.env()
local builder = M.load(S.DummyBuilder, "DummyBuilder", env)()
local Config = M.load(S.Config, "Config", env)()
local CFrame, Vector3 = M.CFrame, M.Vector3

local list = {}
local function dump(model, at, turn)
	-- stand it on the ground at `at`, facing `turn` radians round
	local foot = model:GetAttribute("Foot")
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, turn, 0) * CFrame.new(0, foot, 0) * CFrame.Angles(0, math.pi, 0))
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local c = p.CFrame
			local comps = { c:GetComponents() }
			local col = p.Color
			table.insert(list, string.format('{"name":"%s","size":[%.4f,%.4f,%.4f],"cf":[%s],"color":[%d,%d,%d],"mat":"%s","shape":"%s","t":%.2f}',
				p.Name, p.Size.X, p.Size.Y, p.Size.Z,
				table.concat((function()
					local o = {}
					for i, v in ipairs(comps) do
						o[i] = string.format("%.5f", v)
					end
					return o
				end)(), ","),
				math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
				p.Material.Name, p.Shape and p.Shape.Name or "Block", p.Transparency))
		end
	end
end
local K = Config.Colosseum.King
local mode = ...
dump(builder("King", K.scale), Vector3.new(0, 0, 0), 0)
dump(builder("Straw", 1), Vector3.new(-22, 0, 8), 0)
dump(builder("Brute", 1.3), Vector3.new(20, 0, 10), 0)
print("[" .. table.concat(list, ",\n") .. "]")
