# The sword's animations (R6)

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
