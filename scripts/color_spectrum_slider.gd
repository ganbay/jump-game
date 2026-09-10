extends Control
class_name ColorSpectrumSlider

## One drag across a curated gradient of good-looking neon colours, instead of
## a colour-choice row or a full HSV picker with a popup -- drag until you
## like it. Nothing opens; the whole control surface is the picker.

signal color_changed(color: Color)

## Chosen from the same HDR range the game already draws with (see
## Settings.background_particle_color, Platform.BASE_COLOR) so every point on
## the gradient blooms the same way a hand-picked colour would.
@export var palette: PackedColorArray = PackedColorArray([
	Color(0.3, 1.8, 2.4),
	Color(0.4, 1.0, 2.4),
	Color(1.2, 0.6, 2.4),
	Color(2.2, 0.4, 1.8),
	Color(2.2, 0.4, 0.4),
	Color(2.4, 1.4, 0.3),
	Color(0.6, 2.2, 0.5),
	Color(2.2, 2.2, 2.2),
])
@export var track_height: float = 18.0
@export var handle_radius: float = 13.0
const SEGMENTS := 48

## Position along the gradient, 0..1. Setting it does not emit color_changed --
## that only happens from user input -- so callers can seed it from a saved
## value without triggering a write straight back to Settings.
var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = maxf(custom_minimum_size.y, handle_radius * 2.0)

## Interpolates linearly across consecutive palette entries.
func sample(t: float) -> Color:
	if palette.is_empty():
		return Color.WHITE
	if palette.size() == 1:
		return palette[0]
	var scaled := clampf(t, 0.0, 1.0) * float(palette.size() - 1)
	var i := clampi(int(scaled), 0, palette.size() - 2)
	return palette[i].lerp(palette[i + 1], scaled - i)

func _gui_input(event: InputEvent) -> void:
	var x := -1.0
	if event is InputEventScreenTouch and event.pressed:
		x = event.position.x
	elif event is InputEventScreenDrag:
		x = event.position.x
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		x = event.position.x
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		x = event.position.x
	if x < 0.0 or size.x <= 0.0:
		return
	value = x / size.x
	color_changed.emit(sample(value))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var track_y := h * 0.5 - track_height * 0.5
	for i in range(SEGMENTS):
		var t0 := float(i) / float(SEGMENTS)
		var t1 := float(i + 1) / float(SEGMENTS)
		draw_rect(Rect2(w * t0, track_y, w * (t1 - t0) + 1.0, track_height), sample((t0 + t1) * 0.5))
	var hx := value * w
	draw_circle(Vector2(hx, h * 0.5), handle_radius, Color(1.0, 1.0, 1.0, 0.9))
	draw_circle(Vector2(hx, h * 0.5), handle_radius - 3.5, sample(value))
