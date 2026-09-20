#!/usr/bin/env bash
# Mixes the trailer's music onto an already-rendered cut.
#
#   tools/mix_trailer_audio.sh <video.mp4> <drift_frame> <custom_frame> <death_frame>
#
# Split out of render_trailer.sh so the mix can be re-cut in seconds against an
# existing render instead of costing a several-minute re-render of every frame.
# Only stream 0:v is taken from the input and the video is stream-copied, so
# running this over a file that already carries a music track replaces that
# track and leaves the picture untouched -- it is safe to re-run repeatedly
# while tuning the mix.
#
# The three cue frames are the director's own, read off its log by
# render_trailer.sh (see there); passing them in rather than recomputing them
# keeps this script honest about the fact that it cannot know the cut.
#
# What it builds mirrors what the game itself would be playing under this
# footage (see scripts/audio.gd): the 125bpm lead loop alone through the climb
# showcase, its drum layer joining at the drift showcase -- bar-locked and
# swelling in, exactly as Audio.set_streak layers it, not as a hard cut -- both
# ducking out together the moment the squish showcase's death would have fired
# Audio.fade_to_menu_music(), then the menu ambient track fading in under the
# customization showcase and riding out to the end card.
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "usage: $(basename "$0") <video.mp4> <drift_frame> <custom_frame> <death_frame>" >&2
  exit 1
fi
VIDEO="$1"
DRIFT_F="$2"
CUSTOM_F="$3"
DEATH_F="$4"

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }
[ -f "$VIDEO" ] || { echo "no such video: $VIDEO" >&2; exit 1; }

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUSIC="$PROJECT/audio/music"
LEAD="$MUSIC/gameplay_asap_125bpm.ogg"
DRUM="$MUSIC/gameplay_indie_drums_125bpm_v2.ogg"
MENU="$MUSIC/menu_ambient.ogg"

FPS=60
# The tempo of the lead/drum pair above, and the bar length that falls out of
# it. Both loops are whole numbers of bars at this tempo (30.72s = 16 bars,
# 15.36s = 8), which is what lets the drum layer be quantised to the grid and
# lets either loop repeat without drifting off it.
BPM=125
BAR=$(awk -v b="$BPM" 'BEGIN{printf "%.6f", 240.0/b}')

t() { awk -v f="$1" -v fps="$FPS" 'BEGIN{printf "%.5f", f/fps}'; }
rate() {
  ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 "$1"
}
# Samples in a file, for the aloop sizes below.
samples() {
  ffprobe -v error -select_streams a:0 -show_entries stream=duration,sample_rate \
    -of default=noprint_wrappers=1:nokey=1 "$1" \
    | paste -sd' ' - | awk '{printf "%d", $1*$2 + 0.5}'
}
# A cue in samples of the file it delays, for adelay's `S` suffix. Delays are
# given in whole milliseconds otherwise, which cannot land exactly on a bar of
# an arbitrary tempo -- and a bar line is the one thing here that has to be
# exact. Rounds rather than truncates: 5.76 is not representable in binary, and
# truncating 5.76*1000 yields 5759.
delay() { awk -v s="$1" -v r="$2" 'BEGIN{printf "%d", s*r + 0.5}'; }

DRIFT_T=$(t "$DRIFT_F")     # drift's slide-in starts where climb's hold ends
CUSTOM_T=$(t "$CUSTOM_F")   # customization's slide-in starts where squish's hold ends
DEATH_T=$(t "$DEATH_F")
# The picture's own length, not the container's: the container may still be
# carrying a longer music track from a previous run of this script.
TOTAL_T=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
  -of default=noprint_wrappers=1:nokey=1 "$VIDEO")

GAMEPLAY_FADE=0.6    # Audio.LAYER_FADE_TIME
LEAD_FADE_IN=1.5     # Audio.MUSIC_INTRO_FADE_TIME
MENU_FADE_IN=1.2
MENU_FADE_OUT=0.6

# The drum layer, matching Audio._start_drum_layer(): in the game it does not
# come in on the frame the streak is earned, it waits out the rest of the
# current bar of the lead loop so the two stay phase-locked. The lead starts at
# t=0 here and its file is a whole number of bars, so the grid is just multiples
# of BAR from the top of the video -- quantise the drift cue up to the next one.
# Dropping the drums in on the raw cue instead is what had them landing 0.88s
# past a bar line -- almost half a bar, roughly the "3-and" -- so every hit sat
# between the beats the bass is on. The game never sounds like that because
# nothing there starts a layer anywhere but on the grid.
DRUM_IN_T=$(awk -v x="$DRIFT_T" -v bar="$BAR" \
  'BEGIN{n=int(x/bar); if (n*bar < x-1e-9) n++; printf "%.5f", n*bar}')
# ...and how it gets louder once it is in: Audio starts the layer at
# DRUM_START_VOLUME and tweens it up, so it arrives under the lead rather than
# on top of it. Stretched well past the game's 0.6s tween here -- across a
# trailer the slow build is the point, and a drum bus that is already at full
# when it enters has nowhere left to go.
DRUM_ATTACK=0.25     # silence -> floor; short, only so the entry cannot click
DRUM_FLOOR=0.12      # ~Audio.DRUM_START_VOLUME
DRUM_PEAK=0.80       # ~Audio.DRUM_BOOST_VOLUME
DRUM_SWELL=6.0       # floor -> peak

LEAD_END=$(awk -v d="$DEATH_T" -v f="$GAMEPLAY_FADE" 'BEGIN{printf "%.5f", d+f}')
DRUM_DUR=$(awk -v e="$LEAD_END" -v s="$DRUM_IN_T" 'BEGIN{printf "%.5f", e-s}')
DRUM_FADE_OUT_AT=$(awk -v d="$DRUM_DUR" -v f="$GAMEPLAY_FADE" 'BEGIN{printf "%.5f", d-f}')
MENU_DUR=$(awk -v t="$TOTAL_T" -v s="$CUSTOM_T" 'BEGIN{printf "%.5f", t-s}')
MENU_FADE_OUT_AT=$(awk -v d="$MENU_DUR" -v f="$MENU_FADE_OUT" 'BEGIN{printf "%.5f", d-f}')

if awk -v d="$DRUM_DUR" -v s="$DRUM_SWELL" 'BEGIN{exit !(d <= s)}'; then
  echo "mix: the drum layer only gets ${DRUM_DUR}s, which is inside its ${DRUM_SWELL}s swell --" >&2
  echo "     it would duck out before reaching full. Shorten DRUM_SWELL or lengthen the cut." >&2
  exit 1
fi

# Each loop is repeated rather than trusted to outlast its cue. They are whole
# bars, so a repeat lands on the grid the same way the game's own looping
# does (audio.gd wires `finished` straight back to `play(0.0)`), and a segment
# growing past a loop's length can no longer drop the layer into silence.
LEAD_SR=$(rate "$LEAD"); DRUM_SR=$(rate "$DRUM"); MENU_SR=$(rate "$MENU")
LEAD_LOOP=$(samples "$LEAD")
DRUM_LOOP=$(samples "$DRUM")
MENU_LOOP=$(samples "$MENU")

# asetpts before each atrim so the trim and the fades are measured from the
# stream's own start, whatever timestamps the loop hands down.
FILTER="[1:a]aloop=loop=-1:size=${LEAD_LOOP},asetpts=N/SR/TB,atrim=start=0:end=${LEAD_END},"
FILTER+="afade=t=in:st=0:d=${LEAD_FADE_IN},afade=t=out:st=${DEATH_T}:d=${GAMEPLAY_FADE},volume=0.85[lead];"
FILTER+="[2:a]aloop=loop=-1:size=${DRUM_LOOP},asetpts=N/SR/TB,atrim=start=0:end=${DRUM_DUR},"
FILTER+="afade=t=in:st=0:d=${DRUM_ATTACK},"
FILTER+="volume='${DRUM_FLOOR}+(${DRUM_PEAK}-${DRUM_FLOOR})*min(1,max(0,(t-${DRUM_ATTACK})/${DRUM_SWELL}))':eval=frame,"
FILTER+="afade=t=out:st=${DRUM_FADE_OUT_AT}:d=${GAMEPLAY_FADE},"
FILTER+="adelay=delays=$(delay "$DRUM_IN_T" "$DRUM_SR")S:all=1[drum];"
FILTER+="[3:a]aloop=loop=-1:size=${MENU_LOOP},asetpts=N/SR/TB,atrim=start=0:end=${MENU_DUR},"
FILTER+="afade=t=in:st=0:d=${MENU_FADE_IN},afade=t=out:st=${MENU_FADE_OUT_AT}:d=${MENU_FADE_OUT},"
FILTER+="adelay=delays=$(delay "$CUSTOM_T" "$MENU_SR")S:all=1,volume=0.85[menu];"
FILTER+="[lead][drum][menu]amix=inputs=3:duration=longest:normalize=0,apad,alimiter=limit=0.97[aout]"

printf 'mix: bar %ss | lead 0s | drums %ss (drift cue %ss, quantised up)\n' \
  "$BAR" "$DRUM_IN_T" "$DRIFT_T"
printf '     drums swell %s -> %s over %ss | duck at %ss | menu %ss\n' \
  "$DRUM_FLOOR" "$DRUM_PEAK" "$DRUM_SWELL" "$DEATH_T" "$CUSTOM_T"

MIXED="$(dirname "$VIDEO")/.$(basename "$VIDEO").mixing"
ffmpeg -y -loglevel error -i "$VIDEO" -i "$LEAD" -i "$DRUM" -i "$MENU" \
  -filter_complex "$FILTER" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -movflags +faststart -shortest \
  -f mp4 "$MIXED"
mv -f "$MIXED" "$VIDEO"
