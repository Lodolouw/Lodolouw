# Bundles the game's scripts into sources.luau (the Luau CLI can't read files),
# plus the dummy builder cut out of LobbyBuilder as its own chunk.
import os
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
files = {
    'Config': 'ReplicatedStorage/Config.lua',
    'Items': 'ReplicatedStorage/Items.lua',
    'ColosseumService': 'ServerScriptService/ColosseumService.lua',
    'LobbyActivities': 'StarterPlayerScripts/LobbyActivities.client.lua',
    'BossIntro': 'StarterPlayerScripts/BossIntro.client.lua',
    'LobbyBuilder': 'ServerScriptService/LobbyBuilder.lua',
    'RetroWorld': 'StarterPlayerScripts/RetroWorld.client.lua',
    'LobbyFX': 'StarterPlayerScripts/LobbyFX.client.lua',
}
out = ['return {']
def lit(s):
    lvl = 6
    while ('[' + '=' * lvl + '[') in s or (']' + '=' * lvl + ']') in s:
        lvl += 1
    return '[' + '=' * lvl + '[\n' + s + ']' + '=' * lvl + ']'
for k, p in files.items():
    out.append('\t%s = %s,' % (k, lit(open(REPO + '/' + p).read())))
lb = open(REPO + '/ServerScriptService/LobbyBuilder.lua').read().split('\n')
start = next(i for i, l in enumerate(lb) if l.startswith('\tlocal STRAW = RGB(228, 166, 114)'))
end = next(i for i, l in enumerate(lb) if l.startswith('\tlocal SAND_STONE = RGB(228, 166, 114)'))
block = '\n'.join(lb[start:end])
prelude = '''local RGB, V3, Mat = Color3.fromRGB, Vector3.new, Enum.Material
local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.Plastic
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end
'''
out.append('\tDummyBuilder = %s,' % lit(prelude + block + '\n\treturn colosseumDummy\n'))
# the Colosseum's DIFFICULTY board, cut out of LobbyBuilder the same way
start = next(i for i, l in enumerate(lb) if l.startswith('\tlocal function buildDifficultyBoard('))
end = next(i for i, l in enumerate(lb) if l.startswith('\t-- The real Colosseum, far from the lobby'))
board = '\n'.join(lb[start:end])
boardPrelude = prelude + '''local Config = ...
local FONT = Enum.Font.FredokaOne
local CollectionService = game:GetService("CollectionService")
local GOLD, BANNER_RED, ROOF_RED = RGB(235, 190, 70), RGB(170, 45, 50), RGB(196, 58, 52)
local function titleSign(parent, cf, title)
	local a = part(parent, "SignAnchor", V3(1, 1, 1), cf, RGB(255, 255, 255), Mat.SmoothPlastic, { Transparency = 1 })
	a:SetAttribute("Title", title)
	return a
end
'''
out.append('\tDifficultyBoard = %s,' % lit(boardPrelude + board + '\n\treturn buildDifficultyBoard\n'))
out.append('}')
open(os.path.join(HERE, 'sources.luau'), 'w').write('\n'.join(out) + '\n')
print('ok', len(block.split('\n')), 'lines of dummy builder')
