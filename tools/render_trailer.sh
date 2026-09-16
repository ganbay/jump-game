#!/usr/bin/env bash
# Renders the store trailer to a 1080x1920 mp4.
#
#   tools/render_trailer.sh [seed]
#
# Godot runs scenes/trailer.tscn under --fixed-fps, which decouples simulated
# time from wall clock: the director writes a PNG per frame, each taking far
# longer than 1/60s, and the footage still comes out at an even 60fps. Expect
# the render to take a few minutes and a few GB of scratch PNGs.
#
# The game's save files are moved aside for the duration. The trailer sets the
# equipped character, the colours and the unlock state to stage each segment,
# and some of that goes through code paths that write user://*.cfg -- without
# this, rendering a trailer would silently rewrite your own settings and
# unlocks.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_DIR="$HOME/.local/share/godot/app_userdata/Jetlet- Solar Escape"
FRAMES="$USER_DIR/trailer_frames"
OUT="$PROJECT/promo/trailer_1080x1920.mp4"
SEED="${1:-20260916}"

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

BACKUP="$(mktemp -d)"
restore() {
  for f in settings.cfg unlocks.cfg highscore.cfg stats.cfg missions.cfg; do
    [ -e "$BACKUP/$f" ] && mv -f "$BACKUP/$f" "$USER_DIR/$f"
  done
  rmdir "$BACKUP" 2>/dev/null || true
}
trap restore EXIT
for f in settings.cfg unlocks.cfg highscore.cfg stats.cfg missions.cfg; do
  [ -e "$USER_DIR/$f" ] && cp -p "$USER_DIR/$f" "$BACKUP/$f"
done

rm -rf "$FRAMES"
mkdir -p "$FRAMES" "$PROJECT/promo"

echo "== rendering frames (seed $SEED) =="
LOG="$(mktemp)"
# Judged by what it produced, not by how it exited. Godot has been seen to
# abort while unwinding the render's viewports at shutdown -- after the
# director has printed "done" and every frame is on disk. That is a finished
# render, and treating it as a failure would throw away several minutes of
# work over a crash in the teardown of a process that has nothing left to do.
set +e
godot --path "$PROJECT" --fixed-fps 60 res://scenes/trailer.tscn -- --seed "$SEED" 2>&1 | tee "$LOG"
GODOT_STATUS=${PIPESTATUS[0]}
set -e

EXPECTED=$(sed -n 's/^done: \([0-9]*\) frames.*/\1/p' "$LOG" | tail -1)
COUNT=$(find "$FRAMES" -name 'f_*.png' | wc -l)
if [ -z "$EXPECTED" ]; then
  echo "render did not finish: godot exited $GODOT_STATUS after $COUNT frames" >&2
  exit 1
fi
if [ "$COUNT" -ne "$EXPECTED" ]; then
  echo "render wrote $COUNT frames but reported $EXPECTED" >&2
  exit 1
fi
if [ "$GODOT_STATUS" -ne 0 ]; then
  echo "note: godot exited $GODOT_STATUS while shutting down; all $COUNT frames were written"
fi
if grep -q "LOST TAKE" "$LOG"; then
  echo
  echo "!! a gameplay segment lost its character -- re-run with a different seed:" >&2
  grep "LOST TAKE" "$LOG" >&2
fi
rm -f "$LOG"
echo "== $COUNT frames -> mp4 =="

# yuv420p and even dimensions so the file plays everywhere, including the
# Play Console preview and every phone; CRF 18 is visually lossless for flat
# neon-on-black art that would otherwise band in the glow gradients.
ffmpeg -y -framerate 60 -i "$FRAMES/f_%05d.png" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$OUT"

echo
echo "trailer: $OUT"
ffprobe -v error -show_entries stream=width,height,nb_frames,r_frame_rate \
  -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
echo
echo "frames kept at $FRAMES (delete when you are happy with the cut)"
