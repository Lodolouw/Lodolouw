# Uploading the models and animations (upload_assets.bat)

Uploads everything the game loads from Roblox in one go, with an Open Cloud
API key, so nothing has to be published by hand:

- the voxel weapons' 3D models (`Tools/Weapons/out/models/*.fbx`)
- the weapon abilities' animations (`Tools/Animations/abilities/*.rbxmx`)
- the weapons' sound effects (`Tools/Sounds/out/weapons/*.ogg`, made by
  `Tools/Sounds/weapon_sfx.py`)

## Steps (Windows)

1. **Pull** the latest code.
2. **Make an API key** at create.roblox.com > Open Cloud > API Keys > Create
   API Key: add the **Assets** API with **Read** and **Write**, put
   `0.0.0.0/0` under Accepted IP Addresses, and save. Click **Copy** next to
   the key.
3. **Double-click `upload_assets.bat`.** It reads the key from your clipboard
   (it's too long to paste into the window safely), asks if the game is owned
   by a group (answer `n` if it's yours) and your Roblox user ID (the number in
   your profile link), then uploads each file.
4. When it's done it prints all the IDs and **copies them to your clipboard**.
   Paste them to Claude: they go into `ReplicatedStorage/AssetIds.lua`.
5. **Delete the key** on the Roblox page when you're finished (or keep it
   private: never paste it in a chat or put it in the code).

Uploads are remembered (in `%LOCALAPPDATA%\Lodolouw\assets.txt`, with a
fingerprint of each file), so running it again only uploads what's new or
changed, and still prints every ID.

Roblox limits how many sounds an account can upload each month, and may ask
for an ID-verified account for audio. If a sound is refused, the rest still go
through; a refused one can be swapped for a Toolbox sound renamed to the same
name in SoundService.

Upload with the account (or group) that owns the game: Roblox only lets a game
load models and play animations owned by its owner.

If it stops with "the key is wrong": check the key has Assets with Read and
Write, `0.0.0.0/0` under Accepted IP Addresses, is Enabled, and that you
copied the key itself (with the Copy button), not its name. A brand-new key can
take a minute to start working.

(The weapon types' swing animations have their own older uploader:
`Tools/Animations/upload_animations.bat`.)
