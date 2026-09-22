extends Node2D
class_name BestLine

## The previous best score, drawn across the world at the exact height it was
## reached -- an in-context record marker rather than a number buried in a menu.
##
## Score is height/10 measured down from game.gd's _score_origin_y, so this
## line's world y is that origin minus score*10. That is not an approximation:
## the camera only ever climbs and tracks the player's highest point, so the
## frame the character crosses this line is the same frame the run's score ties
## the record.
##
## Drawn rather than assembled from nodes, and with no _process at all -- it is
## a static mark on the world that the camera scrolls past. The one piece of
## motion is the fade when it is beaten (see surpass()).

const LABEL_FONT := preload("res://fonts/Chillax-Bold.otf")
const FONT_SIZE := 22
## Deliberately neutral white, and bright enough to sit above the scene's HDR
## glow threshold. The character, the platforms and the background particles are
## all player-tinted, so a mark meaning "your own record" has to read as none of
## them -- at any palette the player picks.
const LINE_COLOR := Color(1.9, 1.9, 2.0)
## Dashed rather than solid so it reads as a measuring mark and not as a
## platform the player can try to land on.
const DASH := 26.0
const GAP := 18.0
const THICKNESS := 3.0
## How far above the line the caption's baseline sits.
const LABEL_LIFT := 12.0
const SURPASS_FLASH := Color(2.6, 2.6, 2.8, 1.0)
const SURPASS_TIME := 0.5

var score: int = 0
## Spans the viewport rather than a fixed 720: under the project's `expand`
## stretch a tablet is wider than the design resolution, and a line that stops
## short of the edge reads as a broken platform.
var width: float = 720.0
var _passed := false

func setup(best_score: int, view_width: float) -> void:
	score = best_score
	width = view_width
	queue_redraw()

## Called on the frame the run's score reaches the record. The mark has said
## everything it had to say by then, so it flashes and clears out instead of
## staying on screen underneath the player for the rest of the climb.
func surpass() -> void:
	if _passed:
		return
	_passed = true
	modulate = SURPASS_FLASH
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, SURPASS_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)

func _draw() -> void:
	var x := 0.0
	while x < width:
		draw_line(Vector2(x, 0.0), Vector2(minf(x + DASH, width), 0.0), LINE_COLOR, THICKNESS)
		x += DASH + GAP
	var text := "BEST %d" % score
	var extents := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE)
	draw_string(LABEL_FONT, Vector2((width - extents.x) / 2.0, -LABEL_LIFT), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, LINE_COLOR)
