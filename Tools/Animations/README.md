# The weapons' animations (R6)

The sword's (below) and the other weapon types' - gauntlets, hammer, daggers,
scythe, katana (at the end: "The other weapon types").

## The sword

The idle and the three swings the game plays (`Config.Weapons.Types.Sword.Animations`),
made here in Python and Blender instead of Studio's Animation Editor.

- `r6.py` - the Roblox R6 character, exactly: its parts and Motor6D joints (C0, C1),
  so a pose here is the very `Motor6D.Transform` an uploaded animation sets.
- `anims.py` - posing by DIRECTION: say where the sword arm, the blade and its edge
  point (and the legs, the free arm, the look) and it works out every joint, feet kept
  on the floor.
- `combo.py` - the animations: the idle (`IDLE`) and the string, each swing travelling
  round a SWING PLANE with a coil, a whip through the enemy and a long follow-through
  (a tennis swing): a flat forehand, a rising backhand and a leaping spin finisher. No
  down slashes.
- `render_anims.py` - renders them with Blender (Cycles), with the voxel Iron Warden in
  hand and a glowing trail: `poses` (a sheet of the key poses) or `video` (the combo at
  full and half speed, from behind and from the front).
- `export_rbxmx.py` - writes them as KeyframeSequences (60 keyframes a second, with
  `Cut`, `Hit` and `Through` markers) to `ServerStorage/SwordAnimations.rbxmx`.

```
python3 export_rbxmx.py                                  # needs numpy
<python with bpy> render_anims.py poses out.png         # Blender's Python module (pip install bpy, Python 3.11)
<python with bpy> render_anims.py video out.mp4         # ~10 minutes on a CPU
```

## Into the game

1. **Rojo** syncs `ServerStorage/SwordAnimations.rbxmx` into Studio (ServerStorage >
   SwordAnimations; restart Rojo if it's new). Or: right-click ServerStorage > Insert
   from File.
2. **Publish them.** The Animation Editor needs an R6 rig holding something named
   `Handle` on a Motor6D from the right arm, or it drops the sword's movement. This
   line in the command bar sets that up (it uses a rig called `Rig`, e.g. from Avatar >
   Rig Builder > R6) and puts the four where the editor's **Load** finds them:

   ```lua
   local rig=workspace:FindFirstChild("Rig") or game.ReplicatedStorage:FindFirstChild("Rig"); rig.Parent=workspace; local arm=rig["Right Arm"]; if not arm:FindFirstChild("Grip") then local h=Instance.new("Part"); h.Name="Handle"; h.Size=Vector3.new(0.3,0.3,4); h.CanCollide=false; h.Massless=true; h.CFrame=arm.CFrame*CFrame.new(0,-1,0); h.Parent=rig; local m=Instance.new("Motor6D"); m.Name="Grip"; m.Part0=arm; m.Part1=h; m.C0=CFrame.new(0,-1,0); m.Parent=arm end; local ss=game.ServerStorage; local saves=ss:FindFirstChild("RBX_ANIMSAVES") or Instance.new("Model",ss); saves.Name="RBX_ANIMSAVES"; local f=saves:FindFirstChild("Rig") or Instance.new("ObjectValue",saves); f.Name="Rig"; f.Value=rig; for _,k in ss.SwordAnimations:GetChildren() do k:Clone().Parent=f end; print("ready")
   ```

   Then for each: select the rig, Animation Editor > ... > Load > the animation, then
   ... > Publish to Roblox. To change one later, publish over the same animation so its
   id stays the same. Delete the rig from Workspace when you're done.
3. **The ids** go in `Config.Weapons.Types.Sword.Animations` (`Idle`, and `Swings` in
   order).

Animations only play in a game owned by whoever published them (you, or your group).

## Keep in step with the game

- The hit lands 0.2 s into swings 1 and 2 and 0.3375 s into the finisher: the server's
  moment (`Lock` x `Contact` in `Config.Weapons.Types.Sword.Swings`). The swings are
  timed so the blade is fastest right then.
- The smear shows between each swing's `Cut` and `Through` markers (`MARKERS` here).
  `WeaponFX.ANIM_CUTS` holds the same times; change both together (`test_swordanims`
  checks they match).
- Each swing starts where the last one's follow-through is at 0.5 s (when you can press
  again), so a string chains without a snap.

## The other weapon types

Made exactly the way the sword's are (posing by direction, swings round a swing
plane), but baked into the game instead of uploaded:

- `weapon_types.py` - their idles and strings (`TypeSwing`: the sword's
  `PlaneSwing`, plus two hands on a handle, left-hand blows, mirrored arms and
  which side of the weapon leads). The hit moments come from
  `Config.Weapons.Types` (Lock x Contact): change both together.
- `preview_types.py` - `sheet out.png` (key moments, front and side) and
  `video out.mp4` (every string, full and half speed). The weapons' blocks come
  from `weapon_pieces.txt` (the game's own models: in `Tools/HeadlessTests`,
  `luau test_weapontypes.luau -a poses`, the TYPE/PIECE/OFFPIECE lines).
- `export_types.py` - bakes them into `ReplicatedStorage/WeaponClips.lua`, which
  WeaponFX plays on every screen ("Clips"). Run it after any change here.
  `--rbxmx` also writes `ServerStorage/WeaponAnimations.rbxmx` (KeyframeSequences,
  to publish from the Animation Editor like the sword's - only if you want them
  as uploaded animations; not needed).

They've since been uploaded too (below: `upload_animations.bat`), and their IDs
are in `Config.Weapons.Types`: a type with uploaded swings plays those, and the
baked clips are only what's played when a type has none.

```
python3 export_types.py
python3 preview_types.py sheet types.png
python3 preview_types.py video ../../Docs/animations/weapon_types.mp4
```

## Uploading many at once (upload_animations.bat)

You don't have to publish animations one by one. `python3 export_types.py --rbxmx`
also writes each animation as its own file in `upload/`. Double-click
`upload_animations.bat` on Windows: it reads an Open Cloud API key (with Assets
read + write) from your clipboard, asks your user or group ID, uploads every
file, and writes the IDs straight into `Config.Weapons.Types.<Type>.Animations`
(if Windows won't let it write there, it prints them to paste to Claude).
Uploads that worked are remembered in `%LOCALAPPDATA%\Lodolouw\animation_ids.txt`,
so running it again only does the missing ones. (The weapon models and the
abilities' animations have their own: `Tools/Upload/upload_assets.bat`.)
(Studio's own AssetService:CreateAssetAsync is switched off by Roblox for now.)

## The weapon abilities (abilities.py)

Each weapon's ability (F) has its own animation, made the same way as the
types' swings (posing by direction, swings round a plane) and timed to its
move in `ReplicatedStorage/Moves`: its big moment lands exactly when the
move's hit or effect is due, and it lasts the move's `Time`. Change the two
together. The Slime, Knight and Speedway packs so far; the other packs' come
with their weapons.

Slime:

- Goo Gloves, Sticky Fists: fists flung out wide, then a CLAP in front of the
  chest (0.18 s, the goo splat).
- Jellyblade, Wobble Guard: the blade snaps up flat in front of you, the free
  hand braced on it (0.15 s, the jelly bubble).
- Gelatin Hammer, Goo Slam: up with the hop, the hammer high behind the head,
  and down it slams (0.42 s).
- Ooze Daggers, Slime Trail: low, blades crossed, through the dash, then ripped
  out wide in an X (0.40 s).
- Acid Scythe, Acid Rain: a coil, then a full spin with the blade out flat
  (0.22 s).
- Gelatinous Edge, Oozark's Jaw: a quick-draw, crouched with the hand on the
  hilt while the jaw opens, then a flash of a draw straight across (0.68 s,
  the chomp).

Knight:

- Shovel Hammer, Dig Slam: heaved up high in both hands, the spade chopped
  down into the ground in front (0.28 s, the dirt bursts), then levered and
  the dirt tossed back over the right shoulder.
- Relic Daggers, Treasure Eye: both blades snap up crossed in an X in front
  of the eyes (0.12 s, the glint), then a cocky twirl of the right one.
- Spade Scythe, Dirt Spin: down low and wound round, then the whole body spins
  right round with the blade skimming the ground (0.24 s; the clods fly at
  0.30), finishing wide and scooping up into the stance.
- Honour Blade, Pogo Drop: a crouch and a spring, and by the top of the leap
  the blade points straight down between the tucked knees; blade-first onto
  them (0.58 s), a bounce straight up (0.62) and down again (1.04 s).
- Anchor Fists, Anchor Pull: an overhand throw (let go at 0.25 s), reeled in
  leaning hard with both fists on the chain, then both fists up and a double
  axe-handle SLAM into the ground (0.66 s).
- No Quarter, No Quarter: chest out and the sword thrust at the sky while his
  armour cracks gold, then pointed straight at the enemy (0.6 s, the meteor's
  called down), and a crouched brace, sword forward, as it hits (1.15 s).

Speedway:

- Tyre Scythe, Burnout: the scythe dropped low, the free fist twisting a
  throttle, two bounces like a revving engine (0.10 s, the rev) and a lean
  forward, ready to run.
- Nitro Katana, Nitro: snapped into a rocket's lean, both arms swept back and
  the blade trailing low behind like an exhaust, a jolt as the flame bursts
  out (0.08 s).
- Piston Punchers, Piston Dash: the piston cocked (the right fist back at the
  hip), a low dash (0.14 to 0.38 s), then a huge straight right, fully
  extended (0.40 s, the BOOM).
- Pit Stop Sabre, Skid Spin: crouched low, a full turn with the sabre out flat
  at the waist (past the enemy at 0.20 s, the tyres fly at 0.30), skidding
  round into a low drift, the free hand down by the ground.
- Wheelie Wrecker, Wheelie: on the flaming wheel, the hammer held across like
  handlebars, leaning right back and bouncing; hauled up high (0.8 s) and
  slammed down in front (1.02 s).
- Victory Lap, Victory Lap: GO! Both daggers flung up in a V over the head
  (0 s), then down into a sprinter's crouch and off, ready to run.

The Knight and Speedway ones are key poses (`Poses`): the left hand is kept on
a handle every frame (`hands` puts the right one where two hands can meet: R6
arms don't bend), a spin turns the whole body round (`yaw`), and the feet stay
where they're put whatever the chest does (`key`, `level`). Each big moment
is a marker, so a keyframe lands right on it, and each one ends on a keyframe
exactly at its move's `Time` (the Slime files are as they were made).

```
python3 abilities.py                  # -> abilities/<weapon>.rbxmx (one KeyframeSequence each, 30 keyframes a second)
python3 abilities.py preview          # -> Docs/animations/slime_abilities.mp4 and .png (front and side, full speed and slow)
python3 abilities.py preview knight   # -> Docs/animations/knight_abilities.mp4 and .png
python3 abilities.py preview speedway # -> Docs/animations/speedway_abilities.mp4 and .png
```

They're uploaded with the models by `Tools/Upload/upload_assets.bat` (see
`Tools/Upload/README.md`), and their IDs go in `ReplicatedStorage/AssetIds.lua`
(`Animations`, by weapon id). Your screen plays one on your character when you
use the ability (priority Action3, so it wins over the idle and the swings);
while it plays, WeaponFX leaves the body and the weapon to it. An ability
without its animation still does everything else. The gauntlets' animations
leave the weapon alone (they sit on the fists).

The effects themselves (splats, the jelly bubble, the jaw...) are made in code
on every screen (`ReplicatedStorage/MoveFX`). A film of them played out with
these animations: `Docs/animations/slime_abilities_fx.mp4`
(`Tools/HeadlessTests`: `luau abilities_film.luau > film.txt`, then
`python3 render_abilities.py film.txt out.mp4`).
