#!/usr/bin/env bash
# Makes the ten Arcade banner pictures (one per weapon pack: its boss mid an
# epic move, 1024 x 320) from the real game code: each boss's snapshot script
# in its "poses" mode (Oozark: his cutscene), then render_banner.py with the
# camera, the light and the colours picked for him.
#
#   LUAU=/path/to/luau ./make_banners.sh            (luau on the PATH if LUAU isn't set)
#
# The pictures go to ../Icons/out/banners/Banner_<PackId>.png and a contact
# sheet of all ten to ../../Docs/arcade_banners.png.
set -euo pipefail
cd "$(dirname "$0")"
LUAU="${LUAU:-luau}"
OUT=../Icons/out/banners
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 build_sources.py > /dev/null

# the scenes (all at once)
"$LUAU" oozark_cutscene.luau > "$TMP/oozark.txt" &
for boss in burrowmore revvington kongo scribble tuber kaze gridlock petalina gavelgrunt; do
	"$LUAU" "${boss}_snaps.luau" -a poses > "$TMP/${boss}.txt" &
done
wait

banner() { # banner <PackId> <scene file> <snap> <render_banner options...>
	local pack="$1" scene="$2" snap="$3"
	shift 3
	python3 render_banner.py "$TMP/$scene.txt" "$snap" "$OUT/Banner_$pack.png" --hide-player "$@" > /dev/null
	echo "Banner_$pack.png"
}

# Slime: Oozark rising out of his pit, brows down, teeth bared (the cutscene's roar)
banner Slime oozark - --cutscene 4.8 --orbit 20 --dist 34 --height -6 --look-dy -1 --place 0.64,0.5 --fov 44 \
	--radius 12 --tint 140,255,120 --shade 30,20,70 &
# Knight: Knight Burrowmore's NO QUARTER! - shovel high, the dirt flying
banner Knight burrowmore noquarter --orbit 195 --dist 17 --height -3 --look-dy 3 --place 0.66,0.52 --fov 42 \
	--tint 90,190,255 --shade 20,25,70 &
# Speedway: Speedy Revvington revving for his charge, angry eyes
banner Speedway revvington rev --orbit -15 --dist 19 --height 1 --look-dy 0.5 --place 0.64,0.55 --fov 40 \
	--tint 255,150,50 --shade 30,20,60 &
# Jungle: Kongo going bananas (round 2: red face, pounding his chest)
banner Jungle kongo mad --dist 19 --height -7 --look-dy 4 --place 0.66,0.42 --fov 38 --burst 0,-0.05 \
	--tint 255,110,70 --shade 30,20,60 &
# Canvas: Scribble in round 3, glitching into every colour (a deeper sky than the paper-white one, or it washes out)
banner Canvas scribble rainbow --orbit -25 --dist 13 --height -3 --look-dy 4 --place 0.66,0.48 --fov 46 \
	--sky '30,90,200|150,200,245' --tint 255,190,80 --shade 50,20,90 &
wait
# Cactus: the Brute's RAGE! - arms up, crown on
banner Cactus tuber roar --orbit -25 --dist 32 --height -8 --look-dy 6 --place 0.66,0.52 --fov 42 \
	--tint 150,255,90 --shade 50,25,40 &
# Dojo: Kaze's KAZE-BLAST let go, ki in his hands
banner Dojo kaze push --orbit -20 --dist 14 --height -3 --look-dy 2 --place 0.66,0.55 --fov 42 \
	--tint 120,240,255 --shade 60,20,50 &
# Neon: Gridlock's roar
banner Neon gridlock roar --orbit 10 --dist 20 --height -4 --place 0.66,0.5 --fov 40 \
	--tint 255,60,160 --shade 30,10,60 &
# Garden: Petalina gone wicked (round 2)
banner Garden petalina wicked --orbit -10 --dist 28 --height -8 --look-dy 3 --place 0.66,0.45 --fov 40 \
	--tint 255,70,90 --shade 40,20,50 &
# Throne: King Gavelgrunt, round 3 - no crown, no mercy, the gavel up
banner Throne gavelgrunt rage --orbit -25 --dist 64 --height -6 --look-dy 10 --place 0.64,0.52 --fov 44 --radius 20 \
	--tint 255,190,70 --shade 40,20,60 &
wait

# the contact sheet: two across, each named underneath
python3 - "$OUT" ../../Docs/arcade_banners.png <<'EOF'
import sys
from PIL import Image, ImageDraw
import render_snaps as rs
out, sheet_path = sys.argv[1], sys.argv[2]
packs = ['Slime', 'Knight', 'Speedway', 'Jungle', 'Canvas', 'Cactus', 'Dojo', 'Neon', 'Garden', 'Throne']
W, H, gap, label = 1024, 320, 16, 26
sheet = Image.new('RGB', (2 * W + 3 * gap, 5 * (H + label) + 6 * gap), rs.INK)
d = ImageDraw.Draw(sheet)
for i, pack in enumerate(packs):
    r, c = divmod(i, 2)
    x, y = gap + c * (W + gap), gap + r * (H + label + gap)
    sheet.paste(Image.open('%s/Banner_%s.png' % (out, pack)), (x, y))
    rs.pixel_text(d, pack.upper(), x, y + H + 8, 2, rs.WHITE, outline=None)
sheet.save(sheet_path)
print('saved', sheet_path)
EOF
