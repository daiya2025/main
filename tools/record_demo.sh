#!/usr/bin/env bash
# DIGIHARIMAN — record the 60-second demo reel to MP4 (Linux / macOS / CI).
# Mirrors tools/record_demo.ps1: Godot Movie Maker mode captures every frame
# deterministically, then ffmpeg transcodes to H.264 MP4.
#
#   tools/record_demo.sh [godot_binary] [fps] [WxH] [out_name]
set -euo pipefail
GODOT="${1:-godot}"
FPS="${2:-60}"
RES="${3:-1920x1080}"
OUT="${4:-digihariman_demo}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
AVI="$PROJECT/$OUT.avi"
MP4="$PROJECT/$OUT.mp4"

# The movie writer captures the project's base viewport, which --resolution
# cannot change — override.cfg (read by Godot at startup) is the supported way.
W="${RES%x*}"; H="${RES#*x}"
OVERRIDE="$PROJECT/override.cfg"
trap 'rm -f "$OVERRIDE"' EXIT
cat > "$OVERRIDE" <<CFG
[display]

window/size/viewport_width=$W
window/size/viewport_height=$H
window/size/mode=0
CFG

echo "Recording via Movie Maker mode ($RES @ ${FPS}fps)..."
"$GODOT" --path "$PROJECT" --write-movie "$AVI" --fixed-fps "$FPS" -- --demo
[ -f "$AVI" ] || { echo "recording was not produced: $AVI" >&2; exit 1; }

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found — leaving the recording as AVI: $AVI"
    exit 0
fi
echo "Transcoding to MP4..."
ffmpeg -y -loglevel warning -i "$AVI" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k -movflags +faststart "$MP4"
rm -f "$AVI"
echo "done: $MP4"
