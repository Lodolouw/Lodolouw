# Rojo: Studio updates itself (no more copy-pasting)

Rojo copies the game's scripts from this project straight into Roblox Studio,
into the right places, and keeps them in sync. You set it up once.

## 0. Back up your place first

In Studio: **File → Save to File As...** and save a copy somewhere safe.
(If anything ever goes wrong, you can open this copy.)

## 1. Download the project (once)

1. Install **GitHub Desktop**: https://desktop.github.com
2. Sign in with your GitHub account.
3. **File → Clone repository** → pick **Lodolouw/Lodolouw** → Clone.
4. At the top, click **Current branch** and pick **claude/funny-mccarthy-s0do05**.

## 2. Install Rojo (once)

1. Go to https://github.com/rojo-rbx/rojo/releases/tag/v7.4.4
2. Download **rojo-7.4.4-windows-x86_64.zip** and unzip it.
3. Put **rojo.exe** inside the project folder (the same folder as
   `StartRojo.bat` and `default.project.json`).
   (GitHub Desktop: **Repository → Show in Explorer** opens that folder.)
4. Install the Rojo plugin for Studio: in the project folder, click the
   address bar, type `cmd` and press Enter. In the black window type:

   ```
   rojo plugin install
   ```

   and press Enter. Then restart Studio.

## 3. Connect (every time you work)

1. Double-click **StartRojo.bat** in the project folder. A black window opens
   and says Rojo is running. **Leave it open.**
2. Open your place in Studio.
3. **Plugins** tab → **Rojo** → **Connect**.
4. The first time, Rojo shows what it will change: it puts in the scripts from
   the project (the same ones you've been pasting). Accept it.

Now the scripts in Studio are the project's scripts.

## 4. When Claude sends an update

1. In GitHub Desktop click **Fetch origin**, then **Pull origin**.
2. That's it: while Rojo is connected, Studio updates by itself in a second.
3. Save your place as normal (**File → Save** / **Publish**).

## Good to know

- Rojo only touches the game's scripts: **ReplicatedStorage**,
  **ServerScriptService** and **StarterPlayer → StarterPlayerScripts**.
  It leaves everything else alone - your sounds in SoundService, your models,
  anything else you've added.
- **Don't edit those scripts in Studio while Rojo is connected** - the next
  update would replace your change. Tell Claude what you want instead.
- If Studio shows two copies of a script after the first connect, delete the
  old one (keep the one Rojo made) and tell Claude.
- The `Tools` and `Docs` folders are not part of the game; Rojo ignores them.
