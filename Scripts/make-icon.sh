#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.png.
#
#   ./Scripts/make-icon.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Resources/AppIcon.png"
ICNS="$ROOT/Resources/AppIcon.icns"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/master.png"

# Apple's macOS icon grid: artwork fills an 824pt rounded square centred on a
# 1024pt canvas, so icons line up with the rest of the Dock and Finder rather
# than reaching edge to edge. The corners are a superellipse, not arcs of a
# circle, which is what makes the shape read as a macOS icon.
python3 - "$SOURCE" "$MASTER" <<'PY'
import sys
import numpy as np
from PIL import Image

source, destination = sys.argv[1], sys.argv[2]

CANVAS, INNER, EXPONENT, SUPERSAMPLE = 1024, 824, 5.0, 4

art = Image.open(source).convert("RGBA").resize(
    (INNER * SUPERSAMPLE, INNER * SUPERSAMPLE), Image.LANCZOS
)

axis = np.linspace(-1.0, 1.0, INNER * SUPERSAMPLE)
x, y = np.meshgrid(axis, axis)
inside = (np.abs(x) ** EXPONENT + np.abs(y) ** EXPONENT) <= 1.0

mask = Image.fromarray((inside * 255).astype(np.uint8)).resize(
    (INNER, INNER), Image.LANCZOS
)

art = art.resize((INNER, INNER), Image.LANCZOS)
art.putalpha(mask)

canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
canvas.paste(art, ((CANVAS - INNER) // 2, (CANVAS - INNER) // 2), art)
canvas.save(destination)
PY

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$MASTER" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil --convert icns --output "$ICNS" "$ICONSET"

echo "Wrote $ICNS"
