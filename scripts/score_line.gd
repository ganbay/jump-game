extends Node2D
class_name ScoreLine

## A past score drawn across the world at the exact height it was reached -- an
## in-context marker rather than a number buried in a menu. Three kinds share
## this node: the all-time best, the previous run, and the lifetime average.
##
## Score is height/10 measured down from game.gd's _score_origin_y, so a line's
## world y is that origin minus score*10. That is not an approximation: the
## camera only ever climbs and tracks the player's highest point, so the frame
## the character crosses a line is the same frame the run's score ties it.
##
## Drawn rather than assembled from nodes, and with no _process at all -- these
## are static marks on the world that the camera scrolls past. The one piece of
## motion is the fade when one is passed (see surpass()).

## FINISH is race mode's target line (see race.gd), and the only mark drawn in
## a race -- the classic marks measure a different game.
enum Kind { BEST, LAST, AVERAGE, FINISH }

const LABEL_FONT := preload("res://fonts/Chillax-Bold.otf")

## Deliberately neutral whites, and bright enough to sit above the scene's HDR
## glow threshold. The character, the platforms and the background particles are
## all player-tinted, so a mark meaning "your own score" has to read as none of
## them -- at any palette the player picks.
##
## The three separate by weight rather than by hue, so the hierarchy survives
## the colour-blindness that a red/green split would not: BEST is brightest and
## thickest with long dashes, LAST is lighter and finer, AVERAGE is a faint
## dotted rule. All dashed, so none of them reads as a platform to land on.
const STYLES := {
	Kind.BEST: {
		"label": "BEST", "color": Color(1.9, 1.9, 2.0),
		"dash": 26.0, "gap": 18.0, "thickness": 3.0, "font_size": 22,
	},
	Kind.LAST: {
		"label": "LAST", "color": Color(1.3, 1.3, 1.4),
		"dash": 14.0, "gap": 14.0, "thickness": 2.0, "font_size": 18,
	},
	Kind.AVERAGE: {
		"label": "AVG", "color": Color(1.0, 1.0, 1.1),
		"dash": 4.0, "gap": 12.0, "thickness": 2.0, "font_size": 18,
	},
	Kind.FINISH: {
		"label": "FINISH", "color": Color(2.2, 2.2, 2.3),
		"dash": 30.0, "gap": 10.0, "thickness": 4.0, "font_size": 26,
	},
}

## How far above the line the caption's baseline sits.
const LABEL_LIFT := 12.0
const SURPASS_FLASH := Color(2.6, 2.6, 2.8, 1.0)
const SURPASS_TIME := 0.5

var kind: Kind = Kind.BEST
var score: int = 0
## Spans the viewport rather than a fixed 720: under the project's `expand`
## stretch a tablet is wider than the design resolution, and a line that stops
## short of the edge reads as a broken platform.
var width: float = 720.0
var _passed := false

func setup(line_kind: Kind, line_score: int, view_width: float) -> void:
	kind = line_kind
	score = line_score
	width = view_width
	queue_redraw()

## Called on the frame the run's score reaches this mark. It has said everything
## it had to say by then, so it flashes and clears out instead of staying on
## screen underneath the player for the rest of the climb.
func surpass() -> void:
	if _passed:
		return
	_passed = true
	modulate = SURPASS_FLASH
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, SURPASS_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)

func _draw() -> void:
	var style: Dictionary = STYLES[kind]
	var color: Color = style["color"]
	var dash: float = style["dash"]
	var gap: float = style["gap"]
	var font_size: int = style["font_size"]
	var x := 0.0
	while x < width:
		draw_line(Vector2(x, 0.0), Vector2(minf(x + dash, width), 0.0), color, style["thickness"])
		x += dash + gap
	var text := "%s %d" % [style["label"], score]
	var extents := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(LABEL_FONT, Vector2((width - extents.x) / 2.0, -LABEL_LIFT), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
