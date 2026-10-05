"""Run the Rules tests outside Studio with the Luau command line.

    python3 FeedTheThing/Tests/run_tests.py [path/to/luau]

The Luau CLI can't share globals with required files, so this script bundles
Config.lua and Rules.lua into one file, after a few stand-ins for the Roblox
types Config uses (Color3, Vector3, Enum), then runs RulesTest.luau on them.
"""
import os, shutil, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
shared = os.path.join(here, "..", "ReplicatedStorage")
luau = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("luau") or "luau")

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

bundle = """
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
Enum = { Font = { FredokaOne = "FredokaOne" } }
local __modules, __loaded = {}, {}
local function require(name)
	if __loaded[name] == nil then __loaded[name] = __modules[name]() end
	return __loaded[name]
end
__modules.Config = function()
%s
end
__modules.Rules = function()
local script = nil
%s
end
do
%s
end
""" % (read(os.path.join(shared, "Config.lua")), read(os.path.join(shared, "Rules.lua")), read(os.path.join(here, "RulesTest.luau")))

with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write(bundle)
    path = f.name
try:
    sys.exit(subprocess.call([luau, path]))
finally:
    os.unlink(path)
