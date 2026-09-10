extends Node2D
class_name PlatformDecor

## Draws the attribute tells that the platform body itself cannot express: the
## rim, glare and sheen that make glass read as a pane, and the cushion of a
## squishy one. Movement needs nothing here, and neither does invisibility --
## its tell is the blinking itself, and anything drawn while it was gone would
## give away a platform the player is supposed to have to remember.
##
## The cushion is the only animated part: platform.gd drives it through
## set_squish while the slab underneath holds still. A thin dome is what makes
## that readable -- the same few pixels of travel are most of its silhouette,
## where on the 12px slab they were nothing.

const GLARE_COUNT := 2

## Cushion profile: how far it stands above the slab when fully inflated, what
## fraction of that is left when crushed, how much it spreads sideways as it
## flattens, and its half-width as a share of the slab's.
const DOME_HEIGHT := 8.0
const DOME_FLAT := 0.12
const DOME_SPREAD := 0.18
const DOME_HALF_WIDTH := 0.62
const DOME_SEGMENTS := 16
## Sunk very slightly into the slab, so the cushion reads as seated on the
## surface rather than hovering over it.
const DOME_SEAT := 1.0

var _attributes: int = 0
var _size: Vector2 = Vector2(90.0, 12.0)
var _color: Color = Color.WHITE
## 0 = fully inflated, 1 = crushed flat.
var _squish: float = 0.0

func configure(attributes: int, size: Vector2, color: Color) -> void:
	_attributes = attributes
	_size = size
	_color = color
	# Nothing to draw for a platform with neither attribute, and a hidden
	# CanvasItem is skipped by the renderer entirely.
	visible = _attributes & (Platform.Attr.GLASS | Platform.Attr.SQUISHY) != 0
	queue_redraw()

func set_squish(value: float) -> void:
	if is_equal_approx(value, _squish):
		return
	_squish = value
	queue_redraw()

func _draw() -> void:
	var half := _size / 2.0
	# Cushion first: the glass rim runs along the slab's top edge, and drawing
	# it afterwards keeps the pane's outline crisp where the cushion sits on it.
	if _attributes & Platform.Attr.SQUISHY:
		_draw_cushion(half)
	if _attributes & Platform.Attr.GLASS:
		_draw_glass(half)

func _draw_glass(half: Vector2) -> void:
	var glare := Color(2.2, 2.4, 2.6, 0.32)
	var lean := half.y * 1.2
	for i in range(GLARE_COUNT):
		var cx := lerpf(-half.x * 0.55, half.x * 0.3, float(i))
		var w := maxf(half.x * 0.09, 2.5)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w, half.y),
			Vector2(cx + w, half.y),
			Vector2(cx + w + lean, -half.y),
			Vector2(cx - w + lean, -half.y),
		]), glare)
	draw_polyline(PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
		Vector2(-half.x, -half.y),
	]), Color(1.8, 2.2, 2.6, 0.75), 1.6, true)
	# Specular sheen along the top edge, inset so it stays inside the slab.
	draw_line(
		Vector2(-half.x + 3.0, -half.y + 2.0),
		Vector2(half.x - 3.0, -half.y + 2.0),
		Color(2.4, 2.6, 2.8, 0.5), 1.4, true)

## A thin dome resting on the platform's surface, squashing and spreading as it
## compresses. Drawn as a half-ellipse anchored to the top edge, so the slab
## below is left exactly where the player expects to land on it.
func _draw_cushion(half: Vector2) -> void:
	var h := DOME_HEIGHT * lerpf(1.0, DOME_FLAT, _squish)
	var w := half.x * DOME_HALF_WIDTH * (1.0 + DOME_SPREAD * _squish)
	var base_y := -half.y + DOME_SEAT
	var pts := PackedVector2Array()
	for i in range(DOME_SEGMENTS + 1):
		var a := PI * float(i) / float(DOME_SEGMENTS)
		pts.append(Vector2(-cos(a) * w, base_y - sin(a) * h))
	var fill := Color(
		minf(_color.r + 0.45, 3.0),
		minf(_color.g + 0.45, 3.0),
		minf(_color.b + 0.45, 3.0),
		0.5)
	draw_colored_polygon(pts, fill)
	# A lit edge along the crown, so the profile stays readable against the
	# glow rather than dissolving into it.
	draw_polyline(pts, Color(fill.r, fill.g, fill.b, 0.8), 1.3, true)

