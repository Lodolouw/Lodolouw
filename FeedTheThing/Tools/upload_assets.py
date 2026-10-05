"""
Uploads the game's sounds and Blender models to Roblox with an Open Cloud
API key, then writes their asset ids into the game, which loads them by
itself:
    Sounds/SoundSheet.ogg               -> ReplicatedStorage/SoundSheet.lua (Id)
    Blender/Export/FeedTheThing_Map.fbx   -> Config.AssetIds.Map
    Blender/Export/FeedTheThing_Props.fbx -> Config.AssetIds.Props

It runs by itself on GitHub after every push (.github/workflows/
upload-roblox-assets.yml) once the repository has the secrets below. By hand:

    python3 FeedTheThing/Tools/upload_assets.py            upload what's new or changed
    python3 FeedTheThing/Tools/upload_assets.py --dry-run  just show what it would upload

Needs these environment variables (GitHub: repository secrets):
    ROBLOX_API_KEY      an Open Cloud key with Assets: Read + Write
    ROBLOX_CREATOR_ID   your user id (or the group id)
    ROBLOX_CREATOR_TYPE "user" (default) or "group"
--ci: without a key, just say so and stop (no error).
--ids-only: no uploading (no key needed), just write the ids in uploaded.json
into the game's files.

Only new or changed files are uploaded (hashes and ids are kept in
Tools/uploaded.json). A changed model becomes a new version of the same
asset, so its id stays the same. A changed sound sheet is a new asset, since
Roblox can't update audio; all 18 sounds are in that one file, so each
change costs one audio upload (10 a month without ID verification).
Audio and models go through Roblox's moderation, so something new can take
a few minutes to show up in the game.
Uses only the Python standard library.
"""

import hashlib
import json
import os
import re
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
CI = "--ci" in sys.argv
IDS_ONLY = "--ids-only" in sys.argv

# what gets uploaded: (file, asset type, content type, where its id goes)
FILES = [
    ("Sounds/SoundSheet.ogg", "Audio", "audio/ogg", (SHEET_LUA, "Id")),
    ("Blender/Export/FeedTheThing_Map.fbx", "Model", "model/fbx", (CONFIG, "Map")),
    ("Blender/Export/FeedTheThing_Props.fbx", "Model", "model/fbx", (CONFIG, "Props")),
]


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


def wait_for(op, key, name):
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
    asset_id = response.get("assetId") or response.get("path", "").split("/")[-1]
    if not asset_id:
        raise RuntimeError(f"{name}: no asset id in {op}")
    return int(asset_id)


def create(key, creator, path, asset_type, content_type):
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
    return wait_for(request("PATCH", f"{API}/assets/{asset_id}", key, body, ctype), key, os.path.basename(path))


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


def summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def load_record():
    if os.path.exists(RECORD):
        with open(RECORD) as f:
            return json.load(f)
    return {}


def main():
    if IDS_ONLY:
        record = load_record()
        for rel, _, _, (target, field) in FILES:
            known = record.get(rel)
            if known and not write_id(target, field, known["assetId"]):
                print(f"  ! couldn't find '{field} = ...' in {os.path.relpath(target, GAME)}")
        return
    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "").strip()
    creator_type = (os.environ.get("ROBLOX_CREATOR_TYPE") or "user").strip().lower()
    if not DRY_RUN and (not key or not creator_id):
        message = "No ROBLOX_API_KEY / ROBLOX_CREATOR_ID yet, so nothing was uploaded (see FeedTheThing/README.md)."
        if CI:
            print(f"::notice::{message}")
            summary(["### Roblox assets", message])
            return
        sys.exit(message)
    creator = {"groupId": creator_id} if creator_type == "group" else {"userId": creator_id}

    record = load_record()
    report, failed = ["### Roblox assets", "", "| File | Asset id | |", "|---|---|---|"], []
    for rel, asset_type, content_type, (target, field) in FILES:
        path = os.path.join(GAME, rel)
        if not os.path.exists(path):
            continue
        digest = sha256(path)
        known = record.get(rel) or {}
        if known.get("sha256") == digest:
            asset_id, what = known["assetId"], "same as before"
        elif DRY_RUN:
            print(f"  would upload    {rel} ({asset_type})")
            continue
        else:
            try:
                asset_id, what = None, ""
                if known.get("assetId") and asset_type == "Model":
                    try:
                        asset_id, what = update(key, creator, path, asset_type, content_type, known["assetId"]), "new version"
                    except RuntimeError as e:
                        print(f"  couldn't update {rel} ({e}), uploading it as a new asset")
                if asset_id is None:
                    asset_id, what = create(key, creator, path, asset_type, content_type), "uploaded"
            except RuntimeError as e:
                text = str(e)
                hint = " (that's Roblox's monthly audio upload limit: it resets next month)" if asset_type == "Audio" and re.search(r"quota|limit|429", text, re.I) else ""
                print(f"  FAILED          {rel}: {text}{hint}")
                report.append(f"| {rel} | - | failed: {text[:200]}{hint} |")
                failed.append(rel)
                continue
            record[rel] = {"sha256": digest, "assetId": asset_id}
            with open(RECORD, "w") as f:
                json.dump(record, f, indent=2, sort_keys=True)
                f.write("\n")
        print(f"  {what:15s} {rel} -> {asset_id}")
        report.append(f"| {rel} | [{asset_id}](https://create.roblox.com/store/asset/{asset_id}) | {what} |")
        if not DRY_RUN and not write_id(target, field, asset_id):
            print(f"  ! couldn't find '{field} = ...' in {os.path.relpath(target, GAME)}: add {asset_id} by hand")
    summary(report)
    if failed:
        sys.exit(f"{len(failed)} upload(s) failed (see above).")


if __name__ == "__main__":
    main()
