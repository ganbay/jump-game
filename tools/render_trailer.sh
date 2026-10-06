#!/usr/bin/env bash
# Renders the trailer.
#
#   tools/render_trailer.sh [--release] [--landscape] [seed]
#
# --release renders the release cut (race mode, item boxes, racing friends --
# see trailer_director.gd:_release_segments) to promo/release_trailer_*.mp4
# instead of the announcement cut.
#
# Portrait (1080x1920) is the store cut. --landscape renders the 16:9 YouTube
# cut instead: the same running order, the same seed and the same takes, with
# the game shown in a 9:16 strip and the rest of the frame given to the sky and
# side copy (see trailer_side_panel.gd). Because only the framing differs, both
# cuts hit their beats on the same frames and share one audio mix.
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

CUT="announce"
ASPECT="portrait"
while [ $# -gt 0 ]; do
  case "$1" in
    --release) CUT="release"; shift ;;
    --landscape) ASPECT="landscape"; shift ;;
    *) break ;;
  esac
done
SEED="${1:-20260916}"

# Separate scratch directories, so rendering one cut does not throw away the
# frames of the other -- they are kept deliberately (see the closing message)
# and a re-render wipes whichever it is about to write.
PREFIX="trailer"
[ "$CUT" = "release" ] && PREFIX="release_trailer"
if [ "$ASPECT" = "landscape" ]; then
  FRAMES_NAME="${PREFIX}_frames_16x9"
  OUT="$PROJECT/promo/${PREFIX}_1920x1080.mp4"
else
  FRAMES_NAME="${PREFIX}_frames"
  OUT="$PROJECT/promo/${PREFIX}_1080x1920.mp4"
fi
FRAMES="$USER_DIR/$FRAMES_NAME"

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

rm -rf "$FRAMES"
mkdir -p "$FRAMES" "$PROJECT/promo"

echo "== rendering frames ($CUT, $ASPECT, seed $SEED) =="
LOG="$(mktemp)"
# Judged by what it produced, not by how it exited. Godot has been seen to
# abort while unwinding the render's viewports at shutdown -- after the
# director has printed "done" and every frame is on disk. That is a finished
# render, and treating it as a failure would throw away several minutes of
# work over a crash in the teardown of a process that has nothing left to do.
set +e
godot --path "$PROJECT" --fixed-fps 60 res://scenes/trailer.tscn \
  -- --seed "$SEED" --aspect "$ASPECT" --cut "$CUT" --out "user://$FRAMES_NAME" 2>&1 | tee "$LOG"
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

# The frame each segment's slide-in begins, read off the director's own
# per-segment log line (trailer_director.gd:_render) rather than
# recalculated by hand here -- so a change to _segments' hold times keeps
# this in step automatically. Keyed by segment name; see trailer_director.gd
# for the fixed running order these names assume (splash, climb, drift,
# glass, phantom, squish, custom, end).
declare -A SEG_END
while read -r seg_name seg_frame; do
  SEG_END["$seg_name"]="$seg_frame"
done < <(grep -E '^  [a-z]+ +[0-9.]+s +-> frame [0-9]+' "$LOG" | awk '{print $1, $NF}')
# The frame the squish segment's fall actually clears the death margin (see
# trailer_director.gd:_tick_gameplay) -- later, and seed-dependent, unlike
# every other cue here which is a fixed hold length.
DEATH_FRAME=$(sed -n 's/.*death registers at frame \([0-9]*\).*/\1/p' "$LOG" | tail -1)
rm -f "$LOG"
# The three cues the mix is built on (see mix_trailer_audio.sh): where the
# drums join, where the gameplay music ducks out, and where the menu track
# comes in. The announcement cut ducks on its one death; the release cut has
# none, so its gameplay music runs to the end card and hands over there.
if [ "$CUT" = "release" ]; then
  CUE_NAMES="splash race friends"
else
  CUE_NAMES="splash climb squish"
fi
for name in $CUE_NAMES; do
  if [ -z "${SEG_END[$name]:-}" ]; then
    echo "render: could not find the '$name' segment's frame marker in the log -- can't build the audio cues" >&2
    exit 1
  fi
done
MIX_BPM=125
if [ "$CUT" = "release" ]; then
  MIX_BPM=155
  DRIFT_F="${SEG_END[race]}"      # drums join as the item boxes slide in
  CUSTOM_F="${SEG_END[friends]}"  # menu track under the end card
  DEATH_FRAME="${SEG_END[friends]}"
else
  if [ -z "$DEATH_FRAME" ]; then
    echo "render: squish segment never registered a death -- re-run with a different seed" >&2
    exit 1
  fi
  DRIFT_F="${SEG_END[climb]}"    # drift's slide-in starts where climb's hold ends
  CUSTOM_F="${SEG_END[squish]}"  # customization's slide-in starts where squish's hold ends
fi
echo "== $COUNT frames -> mp4 =="

# yuv420p and even dimensions so the file plays everywhere, including the
# Play Console preview and every phone; CRF 18 is visually lossless for flat
# neon-on-black art that would otherwise band in the glow gradients.
ffmpeg -y -framerate 60 -i "$FRAMES/f_%05d.png" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$OUT"

echo "== mixing in music =="
# The render itself has no audio (see trailer_director.gd:_prepare_globals) --
# the mix below is the one and only pass that adds any. It lives in its own
# script so that re-cutting the music does not cost a re-render: once this has
# run you can iterate on the mix directly with
#   tools/mix_trailer_audio.sh "$OUT" <drift> <custom> <death>
# using the three cue frames it prints here.
echo "   cues: drift $DRIFT_F  custom $CUSTOM_F  death $DEATH_FRAME"
"$PROJECT/tools/mix_trailer_audio.sh" "$OUT" "$DRIFT_F" "$CUSTOM_F" "$DEATH_FRAME" "$MIX_BPM"

echo
echo "trailer: $OUT"
ffprobe -v error -show_entries stream=width,height,nb_frames,r_frame_rate \
  -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
echo
echo "frames kept at $FRAMES (delete when you are happy with the cut)"
