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
for name in splash climb squish; do
  if [ -z "${SEG_END[$name]:-}" ]; then
    echo "render: could not find the '$name' segment's frame marker in the log -- can't build the audio cues" >&2
    exit 1
  fi
done
if [ -z "$DEATH_FRAME" ]; then
  echo "render: squish segment never registered a death -- re-run with a different seed" >&2
  exit 1
fi
echo "== $COUNT frames -> mp4 =="

# yuv420p and even dimensions so the file plays everywhere, including the
# Play Console preview and every phone; CRF 18 is visually lossless for flat
# neon-on-black art that would otherwise band in the glow gradients.
ffmpeg -y -framerate 60 -i "$FRAMES/f_%05d.png" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$OUT"

echo "== mixing in music =="
# Mirrors what the game itself would be playing under this footage (see
# audio.gd): the 125bpm lead loop alone through the climb showcase, its drum
# layer joining at the drift showcase (matching Audio.set_streak's tiered
# layering, not a hard cut), both ducking out together the moment the squish
# showcase's death would have fired Audio.fade_to_menu_music(), silence
# across the game-over beat, then the menu ambient track fading in under the
# customization showcase and riding out to the end card. The render itself
# has no audio (see trailer_director.gd:_prepare_globals) -- this is the one
# and only pass that adds any.
FPS=60
MUSIC="$PROJECT/audio/music"
t() { awk -v f="$1" -v fps="$FPS" 'BEGIN{printf "%.5f", f/fps}'; }
ms() { awk -v s="$1" 'BEGIN{printf "%d", s*1000}'; }

DRIFT_T=$(t "${SEG_END[climb]}")     # drift's slide-in starts where climb's hold ends
CUSTOM_T=$(t "${SEG_END[squish]}")   # customization's slide-in starts where squish's hold ends
DEATH_T=$(t "$DEATH_FRAME")
TOTAL_T=$(t "$EXPECTED")

GAMEPLAY_FADE=0.6   # Audio.LAYER_FADE_TIME
LEAD_FADE_IN=1.5     # Audio.MUSIC_INTRO_FADE_TIME
DRUM_FADE_IN=0.3
MENU_FADE_IN=1.2
MENU_FADE_OUT=0.6

LEAD_END=$(awk -v d="$DEATH_T" -v f="$GAMEPLAY_FADE" 'BEGIN{printf "%.5f", d+f}')
DRUM_DUR=$(awk -v e="$LEAD_END" -v s="$DRIFT_T" 'BEGIN{printf "%.5f", e-s}')
DRUM_FADE_OUT_AT=$(awk -v d="$DRUM_DUR" -v f="$GAMEPLAY_FADE" 'BEGIN{printf "%.5f", d-f}')
MENU_DUR=$(awk -v t="$TOTAL_T" -v s="$CUSTOM_T" 'BEGIN{printf "%.5f", t-s}')
MENU_FADE_OUT_AT=$(awk -v d="$MENU_DUR" -v f="$MENU_FADE_OUT" 'BEGIN{printf "%.5f", d-f}')

FILTER="[1:a]atrim=start=0:end=${LEAD_END},afade=t=in:st=0:d=${LEAD_FADE_IN},afade=t=out:st=${DEATH_T}:d=${GAMEPLAY_FADE},volume=0.85[lead];"
FILTER+="[2:a]atrim=start=0:end=${DRUM_DUR},afade=t=in:st=0:d=${DRUM_FADE_IN},afade=t=out:st=${DRUM_FADE_OUT_AT}:d=${GAMEPLAY_FADE},adelay=$(ms "$DRIFT_T")|$(ms "$DRIFT_T"),volume=0.8[drum];"
FILTER+="[3:a]atrim=start=0:end=${MENU_DUR},afade=t=in:st=0:d=${MENU_FADE_IN},afade=t=out:st=${MENU_FADE_OUT_AT}:d=${MENU_FADE_OUT},adelay=$(ms "$CUSTOM_T")|$(ms "$CUSTOM_T"),volume=0.85[menu];"
FILTER+="[lead][drum][menu]amix=inputs=3:duration=longest:normalize=0,apad,alimiter=limit=0.97[aout]"

MIXED="$PROJECT/promo/.trailer_mixed.mp4"
ffmpeg -y -i "$OUT" \
  -i "$MUSIC/gameplay_asap_125bpm.ogg" \
  -i "$MUSIC/gameplay_indie_drums_125bpm_v2.ogg" \
  -i "$MUSIC/menu_ambient.ogg" \
  -filter_complex "$FILTER" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -movflags +faststart -shortest \
  -f mp4 "$MIXED"
mv -f "$MIXED" "$OUT"

echo
echo "trailer: $OUT"
ffprobe -v error -show_entries stream=width,height,nb_frames,r_frame_rate \
  -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
echo
echo "frames kept at $FRAMES (delete when you are happy with the cut)"
