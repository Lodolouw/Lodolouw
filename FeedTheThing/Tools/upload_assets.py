"""
Uploads the game's sounds and Blender models to Roblox with an Open Cloud
API key, then writes the new asset ids into ReplicatedStorage/Config.lua
(Config.Sounds and Config.AssetIds). The game then loads them by itself.

    python3 FeedTheThing/Tools/upload_assets.py            upload what's new or changed
    python3 FeedTheThing/Tools/upload_assets.py --dry-run  just show what it would upload

Needs these environment variables:
    ROBLOX_API_KEY      an Open Cloud key with Assets: Read + Write
    ROBLOX_CREATOR_ID   your user id (or the group id)
    ROBLOX_CREATOR_TYPE "user" (default) or "group"

Files that haven't changed since their last upload are skipped (their
hashes and ids are kept in Tools/uploaded.json). Audio goes through
Roblox's moderation, so a new sound can take a few minutes to play.
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
RECORD = os.path.join(HERE, "uploaded.json")
API = "https://apis.roblox.com/assets/v1"

DRY_RUN = "--dry-run" in sys.argv


def files_to_upload():
    """(kind, key, path, asset type, content type)"""
    out = []
    sounds = os.path.join(GAME, "Sounds")
    for name in sorted(os.listdir(sounds)):
        if name.endswith(".ogg"):
            out.append(("sound", name[:-4], os.path.join(sounds, name), "Audio", "audio/ogg"))
    export = os.path.join(GAME, "Blender", "Export")
    for key, file in (("Map", "FeedTheThing_Map.fbx"), ("Props", "FeedTheThing_Props.fbx")):
        path = os.path.join(export, file)
        if os.path.exists(path):
            out.append(("model", key, path, "Model", "model/fbx"))
    return out


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {detail}") from None


def upload(key, creator, path, asset_type, content_type, display_name):
    boundary = uuid.uuid4().hex
    meta = {
        "assetType": asset_type,
        "displayName": display_name[:50],
        "description": "Feed the Thing in the Basement",
        "creationContext": {"creator": creator},
    }
    with open(path, "rb") as f:
        data = f.read()
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".encode()
        + json.dumps(meta).encode() + b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(path)}\"\r\n"
        f"Content-Type: {content_type}\r\n\r\n".encode() + data + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    op = request("POST", f"{API}/assets", key, b"".join(parts), f"multipart/form-data; boundary={boundary}")
    # the upload is processed in the background: wait for it
    op_id = op.get("operationId") or op.get("path", "").split("/")[-1]
    for _ in range(90):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", f"{API}/operations/{op_id}", key)
    if not op.get("done"):
        raise RuntimeError(f"{os.path.basename(path)}: still processing after 3 minutes (operation {op_id})")
    response = op.get("response") or {}
    asset_id = response.get("assetId") or response.get("path", "").split("/")[-1]
    if not asset_id:
        raise RuntimeError(f"{os.path.basename(path)}: no asset id in {op}")
    return int(asset_id)


def write_config(ids):
    with open(CONFIG, encoding="utf-8") as f:
        text = f.read()
    for (kind, name), asset_id in ids.items():
        if kind == "sound":
            pattern = rf"(\n\t{re.escape(name)} = \{{ id = )\d+"
        else:
            pattern = rf"(\n\t{re.escape(name)} = )\d+(,)"
        new, n = re.subn(pattern, lambda m: m.group(1) + str(asset_id) + (m.group(2) if m.lastindex and m.lastindex >= 2 else ""), text)
        if n == 1:
            text = new
        else:
            print(f"  ! couldn't find {name} in Config.lua - add id {asset_id} by hand")
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    key = os.environ.get("ROBLOX_API_KEY", "").strip()
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "").strip()
    creator_type = os.environ.get("ROBLOX_CREATOR_TYPE", "user").strip().lower()
    if not DRY_RUN and (not key or not creator_id):
        sys.exit("Set ROBLOX_API_KEY and ROBLOX_CREATOR_ID first (see the top of this file).")
    creator = {"groupId": creator_id} if creator_type == "group" else {"userId": creator_id}

    record = {}
    if os.path.exists(RECORD):
        with open(RECORD) as f:
            record = json.load(f)
    ids, failed = {}, []
    for kind, name, path, asset_type, content_type in files_to_upload():
        rel = os.path.relpath(path, GAME)
        digest = sha256(path)
        known = record.get(rel)
        if known and known.get("sha256") == digest:
            ids[(kind, name)] = known["assetId"]
            print(f"  same as before  {rel} -> {known['assetId']}")
            continue
        if DRY_RUN:
            print(f"  would upload    {rel} ({asset_type})")
            continue
        try:
            asset_id = upload(key, creator, path, asset_type, content_type, f"FeedTheThing {name}")
        except RuntimeError as e:
            print(f"  FAILED          {rel}: {e}")
            failed.append(rel)
            continue
        record[rel] = {"sha256": digest, "assetId": asset_id}
        ids[(kind, name)] = asset_id
        print(f"  uploaded        {rel} -> {asset_id}")
        with open(RECORD, "w") as f:
            json.dump(record, f, indent=2, sort_keys=True)
    if not DRY_RUN and ids:
        write_config(ids)
        print("Config.lua updated.")
    if failed:
        sys.exit(f"{len(failed)} upload(s) failed (see above).")


if __name__ == "__main__":
    main()
