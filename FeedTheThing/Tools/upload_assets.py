"""
Uploads the game's sounds and Blender models to Roblox with an Open Cloud
API key, then writes their asset ids into the game, which loads them by
itself:
    Sounds/SoundSheet.ogg               -> ReplicatedStorage/SoundSheet.lua (Id)
    Blender/Export/FeedTheThing_Map.fbx   -> Config.AssetIds.Map
    Blender/Export/FeedTheThing_Props.fbx -> Config.AssetIds.Props
    GUI/studs.png                       -> Config.AssetIds.StudsImage (or StudsDecal)

On Windows, just double-click upload.bat (next to serve.bat): it asks for
your API key and user id and runs this. Otherwise:

    python3 Tools/upload_assets.py --ask       ask for the key and user id
    python3 Tools/upload_assets.py             use ROBLOX_API_KEY / ROBLOX_CREATOR_ID
    python3 Tools/upload_assets.py --dry-run   just show what it would upload
    python3 Tools/upload_assets.py --forget    forget the key saved on this computer

The key needs the Assets API with Read + Write. For a game owned by a group,
set ROBLOX_CREATOR_TYPE=group and use the group's id.

Only new or changed files are uploaded (hashes and ids are kept in
Tools/uploaded.json). A changed model becomes a new version of the same
asset, so its id stays the same. A changed sound sheet is a new asset, since
Roblox can't update audio; all 18 sounds are in that one file, so each
change costs one audio upload (10 a month without ID verification).
Audio and models go through Roblox's moderation, so something new can take
a few minutes to show up in the game.
Uses only the Python standard library.
"""

import getpass
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
CONFIG = os.path.join(GAME, "ReplicatedStorage", "Config.lua")
SHEET_LUA = os.path.join(GAME, "ReplicatedStorage", "SoundSheet.lua")
RECORD = os.path.join(HERE, "uploaded.json")
API = "https://apis.roblox.com/assets/v1"

DRY_RUN = "--dry-run" in sys.argv
ASK = "--ask" in sys.argv
FORGET = "--forget" in sys.argv
# the key and user id, if you let it remember them: on this computer only,
# outside the project folder (so they never end up on GitHub or OneDrive)
SAVED = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), ".config"),
                     "FeedTheThing", "roblox_upload.json")

# what gets uploaded: (file, asset type, content type, where its id goes)
FILES = [
    ("Sounds/SoundSheet.ogg", "Audio", "audio/ogg", (SHEET_LUA, "Id")),
    ("Blender/Export/FeedTheThing_Map.fbx", "Model", "model/fbx", (CONFIG, "Map")),
    ("Blender/Export/FeedTheThing_Props.fbx", "Model", "model/fbx", (CONFIG, "Props")),
    # an image for the GUI. Uploaded as an Image if Roblox allows it, else as
    # a Decal (the game shows a Decal through its thumbnail instead)
    ("GUI/studs.png", "Image", "image/png", (CONFIG, "StudsImage")),
]
DECAL_FIELD = {"StudsImage": "StudsDecal"}


def id_fields(field, kind):
    """Where an id goes, and which field to clear: an image that went up as a
    Decal fills the Decal field instead."""
    if field in DECAL_FIELD:
        image, decal = field, DECAL_FIELD[field]
        return (decal, image) if kind == "Decal" else (image, decal)
    return field, None


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def request(method, url, key, body=None, content_type=None):
    """One API call, retried when Roblox is busy (429) or hiccups (5xx)."""
    for attempt in range(5):
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("x-api-key", key)
        if content_type:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if (e.code == 429 or e.code >= 500) and attempt < 4:
                wait = int(e.headers.get("Retry-After") or 0) or 2 ** (attempt + 1)
                print(f"    Roblox said {e.code}, trying again in {wait}s")
                time.sleep(wait)
                continue
            raise RuntimeError(f"{method} {url.replace(API, '')} -> HTTP {e.code}: {detail}") from None
        except urllib.error.URLError as e:
            if attempt < 4:
                time.sleep(2 ** (attempt + 1))
                continue
            raise RuntimeError(f"{method} {url.replace(API, '')} -> {e.reason}") from None
    raise RuntimeError("unreachable")


def multipart(meta, path, content_type):
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".encode()
        + json.dumps(meta).encode() + b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(path)}\"\r\n"
        f"Content-Type: {content_type}\r\n\r\n".encode() + data + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ])
    return body, f"multipart/form-data; boundary={boundary}"


def wait_for(op, key, name, same_id=None):
    """Uploads are processed in the background: wait for the asset id."""
    op_id = op.get("operationId") or op.get("path", "").split("/")[-1]
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/operations/{op_id}", key)
    if not op.get("done"):
        raise RuntimeError(f"{name}: still processing after 3 minutes (operation {op_id})")
    if op.get("error"):
        raise RuntimeError(f"{name}: {op['error']}")
    response = op.get("response") or {}
    asset_id = response.get("assetId") or response.get("path", "").split("/")[-1] or same_id
    if not asset_id:
        raise RuntimeError(f"{name}: no asset id in {op}")
    return int(asset_id)


def create(key, creator, path, asset_type, content_type):
    """Uploads a new asset. Returns (id, the asset type it went up as)."""
    if asset_type == "Image":
        try:
            return create_as(key, creator, path, "Image", content_type), "Image"
        except RuntimeError as e:
            if re.search(r"HTTP 40[13]", str(e)):
                raise
            print(f"  (Roblox didn't take it as an Image, so it goes up as a Decal: {str(e)[:120]})")
            return create_as(key, creator, path, "Decal", content_type), "Decal"
    return create_as(key, creator, path, asset_type, content_type), asset_type


def create_as(key, creator, path, asset_type, content_type):
    name = "FeedTheThing " + os.path.splitext(os.path.basename(path))[0].replace("FeedTheThing_", "")
    meta = {
        "assetType": asset_type,
        "displayName": name[:50],
        "description": "Feed the Thing in the Basement",
        "creationContext": {"creator": creator},
    }
    body, ctype = multipart(meta, path, content_type)
    return wait_for(request("POST", f"{API}/assets", key, body, ctype), key, os.path.basename(path))


def update(key, creator, path, asset_type, content_type, asset_id):
    """A new version of an asset we uploaded before (models only), same id."""
    meta = {"assetType": asset_type, "assetId": str(asset_id), "creationContext": {"creator": creator}}
    body, ctype = multipart(meta, path, content_type)
    return wait_for(request("PATCH", f"{API}/assets/{asset_id}", key, body, ctype), key, os.path.basename(path), asset_id)


def write_id(file, field, asset_id):
    """Puts the id in `field = <id>,` of a Lua file. True if found."""
    with open(file, encoding="utf-8") as f:
        text = f.read()
    new, n = re.subn(rf"(\n\t{re.escape(field)} = )\d+(,)", lambda m: f"{m.group(1)}{asset_id}{m.group(2)}", text)
    if n != 1:
        return False
    if new != text:
        with open(file, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
    return True


def load_record():
    if os.path.exists(RECORD):
        with open(RECORD) as f:
            return json.load(f)
    return {}


def saved_credentials():
    try:
        with open(SAVED) as f:
            saved = json.load(f)
        return saved.get("key", ""), str(saved.get("creatorId", ""))
    except (OSError, ValueError):
        return "", ""


def forget():
    if os.path.exists(SAVED):
        os.remove(SAVED)
        print("Forgot the API key saved on this computer.")
    else:
        print("There's no saved API key on this computer.")


def remember(key, creator_id):
    os.makedirs(os.path.dirname(SAVED), exist_ok=True)
    with open(SAVED, "w") as f:
        json.dump({"key": key, "creatorId": creator_id}, f)
    print(f"Saved on this computer only ({SAVED}).")
    print("To forget them: upload.bat forget")


def read_clipboard():
    """What's copied right now (Windows), or "" if that doesn't work."""
    if os.name != "nt":
        return ""
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", "Get-Clipboard -Raw"],
                             capture_output=True, text=True, timeout=30)
        return (out.stdout or "").strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def looks_like_key(text):
    return len(text) >= 20 and not any(c.isspace() for c in text)


def ask_key():
    if os.name != "nt":
        print("Paste your Roblox API key and press Enter (it stays invisible).")
        return getpass.getpass("  API key: ").strip()
    # The Windows console can't paste into a hidden prompt, so the key is
    # read straight from the clipboard: nothing to paste, nothing on screen.
    print("Copy your Roblox API key (select it, Ctrl+C), then come back here and press Enter.")
    input("  Press Enter when it's copied... ")
    key = read_clipboard()
    while not looks_like_key(key):
        print("  That's not an API key on the clipboard. Copy the key and press Enter again,")
        typed = input("  or paste it here (right-click) and press Enter: ").strip()
        key = typed if typed else read_clipboard()
        if typed:
            os.system("cls")  # don't leave the key on the screen
    return key


def ask_credentials():
    """The key and user id: saved on this computer, or asked for."""
    key, creator_id = saved_credentials()
    if key and creator_id:
        print(f"Using the API key saved on this computer (ending in ...{key[-4:]}) and user id {creator_id}.")
        return key, creator_id, True
    print()
    key = ask_key()
    print(f"  Got the key: {len(key)} characters, ending in ...{key[-4:]}")
    creator_id = input("Your Roblox user id (the number in your profile's web address): ").strip()
    while not creator_id.isdigit():
        creator_id = input("  Just the number, please: ").strip()
    return key, creator_id, False


def main():
    if FORGET:
        forget()
        return
    record = load_record()
    todo, done = [], []
    for rel, asset_type, content_type, (target, field) in FILES:
        path = os.path.join(GAME, rel)
        if not os.path.exists(path):
            continue
        digest = sha256(path)
        known = record.get(rel) or {}
        entry = (rel, path, digest, known, asset_type, content_type, target, field)
        (done if known.get("sha256") == digest else todo).append(entry)

    for rel, path, digest, known, asset_type, content_type, target, field in done:
        print(f"  already up      {rel} -> {known['assetId']}")
        if not DRY_RUN:
            put, clear = id_fields(field, known.get("type", asset_type))
            write_id(target, put, known["assetId"])
            if clear:
                write_id(target, clear, 0)
    if not todo:
        print("Everything is already uploaded. Nothing to do.")
        return
    if DRY_RUN:
        for entry in todo:
            print(f"  would upload    {entry[0]} ({entry[4]})")
        return

    from_saved = False
    if ASK:
        print(f"{len(todo)} file(s) to upload: " + ", ".join(os.path.basename(e[0]) for e in todo))
        key, creator_id, from_saved = ask_credentials()
        creator_type = (os.environ.get("ROBLOX_CREATOR_TYPE") or "user").strip().lower()
    else:
        key = os.environ.get("ROBLOX_API_KEY", "").strip()
        creator_id = os.environ.get("ROBLOX_CREATOR_ID", "").strip()
        creator_type = (os.environ.get("ROBLOX_CREATOR_TYPE") or "user").strip().lower()
        if not key or not creator_id:
            sys.exit("Set ROBLOX_API_KEY and ROBLOX_CREATOR_ID first, or run with --ask (see the top of this file).")
    creator = {"groupId": creator_id} if creator_type == "group" else {"userId": creator_id}

    print()
    uploaded, failed = 0, []
    for rel, path, digest, known, asset_type, content_type, target, field in todo:
        print(f"  uploading       {rel} ...")
        try:
            asset_id, what, kind = None, "", asset_type
            if known.get("assetId") and asset_type == "Model":
                try:
                    asset_id, what = update(key, creator, path, asset_type, content_type, known["assetId"]), "new version"
                except RuntimeError as e:
                    if re.search(r"HTTP 40[13]", str(e)):
                        raise
                    print(f"  couldn't update it ({e}), uploading it as a new asset")
            if asset_id is None:
                (asset_id, kind), what = create(key, creator, path, asset_type, content_type), "uploaded"
        except RuntimeError as e:
            text = str(e)
            if re.search(r"HTTP 40[13]", text):
                print(f"  FAILED: {text}")
                print()
                print("Roblox didn't accept the key. On create.roblox.com/dashboard/credentials, check that it:")
                print("  - has the Assets API with Read and Write")
                print("  - allows your IP address (0.0.0.0/0 allows any)")
                print("  - hasn't expired")
                print("and that the user id is yours (the key's owner).")
                if from_saved:
                    forget()
                sys.exit(1)
            hint = ""
            if asset_type == "Audio" and re.search(r"quota|limit|429", text, re.I):
                hint = " (that's Roblox's monthly audio upload limit: it resets next month)"
            print(f"  FAILED          {rel}: {text}{hint}")
            failed.append(rel)
            continue
        record[rel] = {"sha256": digest, "assetId": asset_id, "type": kind}
        with open(RECORD, "w", newline="\n") as f:
            json.dump(record, f, indent=2, sort_keys=True)
            f.write("\n")
        uploaded += 1
        print(f"  {what:15s} {rel} -> {asset_id}")
        put, clear = id_fields(field, kind)
        if not write_id(target, put, asset_id):
            print(f"  ! couldn't find '{put} = ...' in {os.path.relpath(target, GAME)}: add {asset_id} by hand")
        if clear:
            write_id(target, clear, 0)

    print()
    if uploaded:
        print(f"Done: {uploaded} uploaded. The ids are in the game's files now.")
        print("  - Rojo (serve.bat) puts them in Studio by itself. New uploads can take a few")
        print("    minutes to pass Roblox's moderation before they show up.")
        print("  - Commit and push in GitHub Desktop so the ids are kept.")
    if ASK and uploaded and not from_saved:
        answer = input("Remember the key and user id on this computer, so next time it's just a double-click? [Y/n] ")
        if answer.strip().lower() in ("", "y", "yes"):
            remember(key, creator_id)
    if failed:
        sys.exit(f"{len(failed)} upload(s) failed (see above). Run it again to retry them.")


if __name__ == "__main__":
    main()
