#!/usr/bin/env bash
# Renders the vertical shorts for TikTok, YouTube Shorts and Reels.
#
#   tools/render_shorts.sh [--seed N] [name ...]
#
# With no names, renders every short in trailer_director.gd:_shorts. Each lands
# at promo/shorts/<name>.mp4, 1080x1920 at 60fps with music, and its scratch
# frames are deleted once it is encoded -- unlike the trailers, a short is
# cheap to re-render and a week of them would otherwise be several GB of PNGs.
#
# Same harness as render_trailer.sh: scenes/trailer.tscn under --fixed-fps,
# judged by its "done:" line and the frames on disk rather than its exit code,
# and the game's save files moved aside for the duration.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_DIR="$HOME/.local/share/godot/app_userdata/Jetlet- Solar Escape"
OUT_DIR="$PROJECT/promo/shorts"
MUSIC="$PROJECT/audio/music"
ALL="drift glass phantom mistake friends attack custom"

SEED=20260916
if [ "${1:-}" = "--seed" ]; then
  SEED="$2"; shift 2
fi
NAMES="${*:-$ALL}"

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

BACKUP="$(mktemp -d)"
restore() {
  for f in settings.cfg unlocks.cfg highscore.cfg stats.cfg missions.cfg race.cfg; do
    [ -e "$BACKUP/$f" ] && mv -f "$BACKUP/$f" "$USER_DIR/$f"
  done
  rmdir "$BACKUP" 2>/dev/null || true
}
trap restore EXIT
for f in settings.cfg unlocks.cfg highscore.cfg stats.cfg missions.cfg race.cfg; do
  [ -e "$USER_DIR/$f" ] && cp -p "$USER_DIR/$f" "$BACKUP/$f"
done

mkdir -p "$OUT_DIR"
FAILED=""

for NAME in $NAMES; do
  FRAMES_NAME="short_frames_$NAME"
  FRAMES="$USER_DIR/$FRAMES_NAME"
  OUT="$OUT_DIR/$NAME.mp4"
  rm -rf "$FRAMES"
  mkdir -p "$FRAMES"

  echo "== $NAME: rendering frames (seed $SEED) =="
  LOG="$(mktemp)"
  set +e
  # --disable-vsync: see render_trailer.sh.
  godot --disable-vsync --path "$PROJECT" --fixed-fps 60 res://scenes/trailer.tscn \
    -- --seed "$SEED" --cut shorts --short "$NAME" --out "user://$FRAMES_NAME" \
    >"$LOG" 2>&1
  set -e

  EXPECTED=$(sed -n 's/^done: \([0-9]*\) frames.*/\1/p' "$LOG" | tail -1)
  COUNT=$(find "$FRAMES" -name 'f_*.png' | wc -l)
  if [ -z "$EXPECTED" ] || [ "$COUNT" -ne "$EXPECTED" ]; then
    echo "!! $NAME: render did not finish ($COUNT frames on disk)" >&2
    tail -20 "$LOG" >&2
    FAILED="$FAILED $NAME"
    rm -f "$LOG"; rm -rf "$FRAMES"
    continue
  fi
  if grep -qE "LOST TAKE|meant to end in a death" "$LOG"; then
    echo "!! $NAME: bad take -- re-run it with another seed: tools/render_shorts.sh --seed N $NAME" >&2
    grep -E "LOST TAKE|meant to end in a death" "$LOG" >&2
    FAILED="$FAILED $NAME"
  fi
  rm -f "$LOG"

  echo "== $NAME: $COUNT frames -> mp4 =="
  SILENT="$OUT_DIR/.$NAME.silent.mp4"
  ffmpeg -y -loglevel error -framerate 60 -i "$FRAMES/f_%05d.png" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p "$SILENT"
  rm -rf "$FRAMES"

  # The release trailer's 155bpm pair, both layers in from the first frame: a
  # short has no time for the trailer's slow build. Fades out under the end
  # card so the loop does not stop mid-bar.
  DUR=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
    -of default=noprint_wrappers=1:nokey=1 "$SILENT")
  FADE_AT=$(awk -v d="$DUR" 'BEGIN{printf "%.3f", d-1.0}')
  ffmpeg -y -loglevel error -i "$SILENT" \
    -stream_loop -1 -i "$MUSIC/gameplay_pad_155bpm.ogg" \
    -stream_loop -1 -i "$MUSIC/gameplay_dnb_drums_155bpm.ogg" \
    -filter_complex "[1:a]volume=0.85[lead];[2:a]volume=0.7[drum];[lead][drum]amix=inputs=2:normalize=0,atrim=0:${DUR},afade=t=out:st=${FADE_AT}:d=1.0,alimiter=limit=0.97[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"
  rm -f "$SILENT"
  echo "   $OUT  ${DUR}s"
done

if [ -n "$FAILED" ]; then
  echo
  echo "check these:$FAILED" >&2
  exit 1
fi
