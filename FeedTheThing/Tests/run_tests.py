"""Run the tests outside Studio with the Luau command line.

    python3 FeedTheThing/Tests/run_tests.py [path/to/luau]

(needs "luau", from https://github.com/luau-lang/luau/releases)

1. RulesTest.luau - the game's rules. The Luau CLI can't share globals with
   required files, so this bundles Config.lua and Rules.lua into one file,
   after a few stand-ins for the Roblox types Config uses (Color3, Vector3,
   Enum), then runs the test on them.
2. ServerSmokeTest.luau - the real server scripts (DataService, GameService)
   on a pretend Roblox (MockRoblox.luau): join, feed, hatch, upgrade, the
   coin truck, leave and come back.
"""
import os, re, shutil, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
game = os.path.join(here, "..")
luau = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("luau") or "luau")

def read(*path):
    with open(os.path.join(*path), encoding="utf-8") as f:
        return f.read()

def run(name, source):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(source)
        path = f.name
    try:
        print("--", name)
        return subprocess.call([luau, path])
    finally:
        os.unlink(path)

rules = """
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
""" % (read(game, "ReplicatedStorage", "Config.lua"), read(game, "ReplicatedStorage", "Rules.lua"), read(here, "RulesTest.luau"))

# the server scripts, each wrapped up as a module the pretend `require` finds by name
modules = {
    "Config": ("ReplicatedStorage", "Config.lua"),
    "Rules": ("ReplicatedStorage", "Rules.lua"),
    "DataService": ("ServerScriptService", "DataService.lua"),
    "GameService": ("ServerScriptService", "GameService.lua"),
}
events = re.search(r"local REMOTE_EVENTS = (\{[^}]*\})", read(game, "ServerScriptService", "Main.server.lua")).group(1)
parts = [
    read(here, "MockRoblox.luau"),
    "local __modules, __loaded = {}, {}",
    "function require(inst) local n = inst.Name; if __loaded[n] == nil then __loaded[n] = __modules[n]() end; return __loaded[n] end",
]
for name, (folder, file) in modules.items():
    parts.append("__modules.%s = function()\nlocal script = { Parent = mock.%s }\n%s\nend" % (name, folder, read(game, folder, file)))
parts.append("REMOTE_EVENTS = " + events)
parts.append("do\n" + read(here, "ServerSmokeTest.luau") + "\nend")

failed = run("RulesTest", rules) != 0
failed = run("ServerSmokeTest", "\n".join(parts)) != 0 or failed
sys.exit(1 if failed else 0)
