extends Node2D
class_name BlobFace

## A live face for a PlasmaBlob character: two eyes, a mouth for big moments,
## and blinks. Hung as a child of the PlasmaBlob, so the squash, stretch and
## lean the owner already puts on the blob's transform carry the face along for
## free -- nothing here has to know about them.
##
## Every expression is one point in a small parameter space (eye size, lid
## height and slope, how far the bottom lid pushes up, mouth size and shape --
## see P). The face eases its current point towards the target expression's
## every frame, so any change, even one interrupting another halfway, is a
## smooth blend by construction. Blinks are a separate layer on top.
##
## Cheap on purpose, for low-end phones:
##   * no shader, texture or extra viewport -- flat polygons, the same flat
##     hard-edged look as the blob's own bands;
##   * every feature is a fixed strip of columns, so its triangles are indexed
##     once up front and the frame's work is filling in ~70 points, then one
##     triangle-array draw. No triangulation, which also means no shape the
##     lids can squeeze the eye into (a sliver, nothing at all) is ever a
##     degenerate polygon that fails to draw;
##   * it only redraws while something is actually moving. Once the blend
##     settles the face costs nothing until the next blink.
##
## A face also has a style (see Style): a personality with its own base look,
## its own take on each mood, and its own extras -- glasses, lashes, brows.
## The extras are driven by parameters too, so a style's own moves (glasses
## slipping, brows lifting) blend like everything else.
##
## Units are fractions of the blob's radius, y down, origin at the face centre.

enum P {
	EYE_W, EYE_H, SPACING, EYE_Y,
	## Top lid, relative to the eye centre in eye heights: -1 just touches the
	## top, below that cuts nothing, above it closes the eye from above.
	LID_H,
	## Drops the lid towards the middle of the face: positive reads determined,
	## negative worried.
	LID_SLOPE,
	## Added to the right eye's lid only, in eye heights -- a raised brow or a
	## half-shut eye.
	LID_ASYM,
	## Bottom lid pushing up into an arch: 1 leaves a ^ of the top of the eye.
	BOTTOM,
	MOUTH_W, MOUTH_H,
	## 0 is an "o"; 1 flattens the top into a D-shaped grin.
	MOUTH_FLAT,
	MOUTH_Y,
	SHINE,
	## The style extras. Each only draws for the styles that have that extra.
	## Brows: vertical offset, and how far the inner ends drop (angry) or rise.
	BROW, BROW_TILT,
	## Cheek blush, 0..1 opacity.
	BLUSH,
	## How far glasses slip down the face, 0..1.
	VISOR,
	## Eyelash length, 0..1.
	LASH,
	## A glare streak across glasses, 0..1.
	GLINT,
	## Fed from `look` and `tilt` rather than from the expression.
	GAZE_X, GAZE_Y, FACE_Y,
}
const PARAM_COUNT := 22
## Every slot before this comes from the expression.
const MOOD_PARAMS := P.GAZE_X

const NEUTRAL := [
	0.2, 0.31, 0.36, -0.04,
	-1.3, 0.0, 0.0,
	0.0,
	0.0, 0.0, 0.0, 0.34,
	0.085,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0,
]

## Overrides on NEUTRAL. Mouths only show up for the big moments: at the
## character's ~36px a mouth on every expression is noise.
const MOODS := {
	&"neutral": {},
	&"determined": {P.LID_H: -0.5, P.LID_SLOPE: 0.55},
	&"focused": {P.EYE_H: 0.27, P.LID_H: -0.25, P.LID_SLOPE: 0.3},
	&"wide": {P.EYE_W: 0.23, P.EYE_H: 0.35, P.SHINE: 0.1},
	&"squint": {P.BOTTOM: 0.6, P.LID_H: -0.7},
	&"joyful": {P.BOTTOM: 1.0, P.EYE_H: 0.33},
	&"hyped": {P.EYE_W: 0.23, P.EYE_H: 0.35, P.EYE_Y: -0.1,
		P.MOUTH_W: 0.22, P.MOUTH_H: 0.19, P.MOUTH_FLAT: 1.0, P.MOUTH_Y: 0.3},
	&"annoyed": {P.EYE_H: 0.27, P.LID_H: -0.35, P.LID_SLOPE: -0.45},
	&"panic": {P.EYE_W: 0.24, P.EYE_H: 0.37, P.EYE_Y: -0.12, P.SHINE: 0.06,
		P.MOUTH_W: 0.1, P.MOUTH_H: 0.13, P.MOUTH_Y: 0.36},
	&"dizzy": {P.BOTTOM: 0.45, P.LID_H: -0.3, P.LID_ASYM: 0.35},
	&"confused": {P.LID_H: -0.3, P.LID_SLOPE: 0.2, P.LID_ASYM: -0.5},
}

## Faces to choose from, shown to the player as FACE 1, FACE 2... in this
## order. Settings persists this as a raw int, so new ones go on the end.
enum Style { CLASSIC, SPECS, LASHES, CYCLOPS, SLEEPY, GRUMPY }

## Each style: `base` overrides NEUTRAL for every mood, then MOODS applies, then
## the style's own `moods` override that -- which is where its personality
## lives. A mood a style does not mention plays the shared one.
const STYLES := {
	Style.CLASSIC: {"base": {}, "moods": {}},
	# Small eyes behind big round lenses. Goes blank behind a lens glare when
	# serious, and the glasses slip when it panics.
	Style.SPECS: {
		"base": {P.EYE_W: 0.12, P.EYE_H: 0.16, P.SHINE: 0.05, P.SPACING: 0.39},
		"moods": {
			&"determined": {P.EYE_H: 0.13, P.LID_H: -0.4, P.LID_SLOPE: 0.3, P.GLINT: 1.0},
			&"focused": {P.EYE_H: 0.12, P.GLINT: 0.7},
			&"wide": {P.EYE_W: 0.15, P.EYE_H: 0.2},
			&"joyful": {P.EYE_H: 0.18},
			&"hyped": {P.EYE_W: 0.14, P.EYE_H: 0.19, P.GLINT: 1.0},
			&"annoyed": {P.EYE_H: 0.14, P.VISOR: 0.45},
			&"panic": {P.EYE_W: 0.15, P.EYE_H: 0.21, P.VISOR: 1.0},
		},
	},
	# Lashes and a little blush. Winks instead of grinning, goes half-lidded
	# and sassy when serious, pouts when the streak breaks.
	Style.LASHES: {
		"base": {P.EYE_W: 0.21, P.EYE_H: 0.33, P.LASH: 1.0, P.BLUSH: 0.45, P.SHINE: 0.1},
		"moods": {
			&"joyful": {P.BOTTOM: 0.0, P.LID_ASYM: 2.2, P.BLUSH: 1.0,
				P.MOUTH_W: 0.1, P.MOUTH_H: 0.07, P.MOUTH_FLAT: 1.0, P.MOUTH_Y: 0.3},
			&"determined": {P.LID_H: -0.15, P.LID_SLOPE: -0.1},
			&"squint": {P.BLUSH: 0.8},
			&"hyped": {P.BLUSH: 1.0},
			&"annoyed": {P.BLUSH: 0.8, P.MOUTH_W: 0.07, P.MOUTH_H: 0.07, P.MOUTH_Y: 0.32},
			&"panic": {P.BLUSH: 0.0, P.LASH: 1.3},
		},
	},
	# One big eye: both eyes drawn on the same spot. Lids that slope towards
	# the middle of one eye fight the other, so it gets its own lids.
	Style.CYCLOPS: {
		"base": {P.SPACING: 0.0, P.EYE_W: 0.3, P.EYE_H: 0.4, P.SHINE: 0.12},
		"moods": {
			&"determined": {P.LID_H: -0.45, P.LID_SLOPE: -0.35},
			&"focused": {P.EYE_H: 0.32, P.LID_SLOPE: 0.0},
			&"wide": {P.EYE_W: 0.33, P.EYE_H: 0.45},
			&"hyped": {P.EYE_W: 0.33, P.EYE_H: 0.45},
			&"joyful": {P.EYE_H: 0.42},
			&"annoyed": {P.EYE_H: 0.32, P.LID_SLOPE: 0.0},
			&"panic": {P.EYE_W: 0.36, P.EYE_H: 0.48, P.SHINE: 0.05},
			&"dizzy": {P.LID_ASYM: 0.0},
			&"confused": {P.LID_ASYM: 0.0, P.LID_SLOPE: -0.3},
		},
	},
	# Permanently half-asleep -- which is what makes it snap wide awake for
	# the scary and the exciting moments.
	Style.SLEEPY: {
		"base": {P.EYE_H: 0.27, P.LID_H: -0.05, P.LID_SLOPE: -0.12, P.SHINE: 0.0},
		"moods": {
			&"determined": {P.LID_H: -0.2, P.LID_SLOPE: 0.2},
			&"focused": {P.LID_H: 0.1},
			&"wide": {P.LID_H: -1.3, P.LID_SLOPE: 0.0, P.SHINE: 0.1},
			&"joyful": {P.LID_H: -1.3, P.LID_SLOPE: 0.0},
			&"hyped": {P.LID_H: -1.3, P.LID_SLOPE: 0.0, P.SHINE: 0.1},
			&"panic": {P.LID_H: -1.3, P.LID_SLOPE: 0.0, P.SHINE: 0.06},
		},
	},
	# Heavy angry brows, even at rest. Grudgingly lifts them when happy.
	Style.GRUMPY: {
		"base": {P.EYE_H: 0.26, P.LID_H: -0.6, P.LID_SLOPE: 0.3, P.BROW_TILT: 0.6},
		"moods": {
			&"wide": {P.LID_H: -1.3, P.BROW_TILT: 0.0, P.BROW: -0.08},
			&"joyful": {P.BROW_TILT: -0.1, P.BROW: -0.06},
			&"hyped": {P.LID_H: -1.3, P.BROW_TILT: 0.8},
			&"annoyed": {P.BROW_TILT: 1.0},
			&"panic": {P.LID_H: -1.3, P.BROW_TILT: -0.6, P.BROW: -0.1},
			&"confused": {P.BROW_TILT: 0.0},
		},
	},
}

## Where the face sits on each silhouette and how big, as (x, y, scale) in
## radii. The pointed and spiky shapes have little solid middle to hold a face,
## and the flame's, heart's and dome's mass sits low.
const SHAPE_PLACEMENT := {
	PlasmaBlob.Shape.CIRCLE: Vector3(0.0, 0.0, 1.0),
	PlasmaBlob.Shape.PRISM: Vector3(0.0, 0.0, 0.95),
	PlasmaBlob.Shape.SQUARE: Vector3(0.0, 0.0, 0.95),
	PlasmaBlob.Shape.DIAMOND: Vector3(0.0, 0.0, 0.8),
	PlasmaBlob.Shape.TRIANGLE: Vector3(0.0, 0.18, 0.78),
	PlasmaBlob.Shape.STAR: Vector3(0.0, 0.06, 0.78),
	PlasmaBlob.Shape.SPARKLE: Vector3(0.0, 0.0, 0.65),
	PlasmaBlob.Shape.DOME: Vector3(0.0, 0.25, 0.9),
	PlasmaBlob.Shape.HEART: Vector3(0.0, 0.1, 0.85),
	PlasmaBlob.Shape.FLAME: Vector3(0.0, 0.28, 0.85),
}

## How far `look` and `tilt` move things, in radii.
const GAZE_RANGE := Vector2(0.1, 0.06)
const TILT_RANGE := 0.14

## Columns per feature. Spaced by cosine, so they bunch at the pointed ends of
## each eye where the outline turns fastest.
const COLUMNS := 10
const FEATURES := 3
const FEATURE_VERTS := (COLUMNS + 1) * 2

## The expression the face is at when nothing is reacting.
var mood: StringName = &"neutral"
## Which face this is. Changing it blends to the new style's look, rather than
## swapping -- snap() afterwards if it should not.
var style: Style = Style.CLASSIC
## Where the eyes look, each axis -1..1, y down.
var look: Vector2 = Vector2.ZERO
## Slides the whole face up (+1) or down (-1) the body.
var tilt: float = 0.0
## 0..1 of a jittering wobble on the gaze -- dizzy.
var shake: float = 0.0
## Blend speed towards the target; higher snaps faster.
var rate: float = 14.0
var blinking: bool = true
## Picks its own `look` every so often, for a face nothing is steering -- a
## menu preview idling.
var wander: bool = false

## Multiplies the whole face. The game's character is ~36px, where proportions
## that read on a big preview come out too small to see.
var feature_scale: float = 1.0

var ink_color: Color = Color(0.06, 0.02, 0.16)
var shine_color: Color = Color(1.5, 1.5, 1.5)
var blush_color: Color = Color(1.0, 0.35, 0.55)

var _blob: PlasmaBlob
var _params: PackedFloat32Array = PackedFloat32Array()
var _react_mood: StringName = &""
var _react_left: float = 0.0
var _time: float = 0.0
var _blink: float = 0.0
var _blink_t: float = -1.0
var _blink_wait: float = 0.0
var _last_shape: int = -1
var _wander_wait: float = 0.0
var _rng := RandomNumberGenerator.new()
## Set by lift_above_glow(): the layer and the canvas item the face paints into
## instead of its own.
var _overlay: CanvasLayer
var _overlay_item: RID = RID()

## Built once for every face: every style's moods as flat arrays (keyed style,
## then mood), and the index buffer, which never changes because the topology
## never does.
static var _mood_arrays: Dictionary = {}
static var _indices: PackedInt32Array = PackedInt32Array()
static var _columns_u: PackedFloat32Array = PackedFloat32Array()

## Per-face scratch, written in place every draw. Through the member, never a
## local alias -- packed arrays are copy-on-write (see PlasmaBlob._ring).
var _points: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
## The extras' scratch: one closed ring, a batch of line segments, and
## single-colour arrays for each colour they come in.
var _ring: PackedVector2Array = PackedVector2Array()
var _segs: PackedVector2Array = PackedVector2Array()
var _ink: PackedColorArray = PackedColorArray()
var _tint: PackedColorArray = PackedColorArray()

const RING_POINTS := 20
## Glasses lens radius, and line weights, in face units.
const LENS_RADIUS := 0.33
const FRAME_WIDTH := 0.06
const LASH_WIDTH := 0.04
const BROW_WIDTH := 0.08

const BLINK_CLOSE := 0.05
const BLINK_OPEN := 0.08
const BLINK_GAP_MIN := 2.5
const BLINK_GAP_MAX := 5.0
const DOUBLE_BLINK_CHANCE := 0.15
## Eyes already this squinted do not blink -- there is nothing left to close.
const BLINK_SQUINT_LIMIT := 0.4

static func _build_static() -> void:
	if not _indices.is_empty():
		return
	for style_id in STYLES:
		var spec: Dictionary = STYLES[style_id]
		var by_mood := {}
		for name in MOODS:
			var arr := PackedFloat32Array(NEUTRAL)
			for layer: Dictionary in [spec.base, MOODS[name], spec.moods.get(name, {})]:
				for key in layer:
					arr[key] = layer[key]
			by_mood[name] = arr
		_mood_arrays[style_id] = by_mood
	_columns_u.resize(COLUMNS + 1)
	for i in range(COLUMNS + 1):
		_columns_u[i] = -cos(PI * float(i) / float(COLUMNS))
	for f in range(FEATURES):
		var base := f * FEATURE_VERTS
		for i in range(COLUMNS):
			# Column i's top and bottom are vertices 2i and 2i+1.
			var t0 := base + i * 2
			_indices.append_array([t0, t0 + 1, t0 + 2, t0 + 2, t0 + 1, t0 + 3])

func _ready() -> void:
	_build_static()
	_blob = get_parent() as PlasmaBlob
	_params = PackedFloat32Array(_target())
	_points.resize(FEATURES * FEATURE_VERTS)
	_colors.resize(FEATURES * FEATURE_VERTS)
	_colors.fill(ink_color)
	_ring.resize(RING_POINTS + 1)
	_ink = PackedColorArray([ink_color])
	_tint = PackedColorArray([Color.WHITE])
	_rng.randomize()
	_blink_wait = _rng.randf_range(0.6, BLINK_GAP_MAX)

## Shows `name` for `duration` seconds over whatever `mood` is, then blends back.
func react(name: StringName, duration: float) -> void:
	_react_mood = name
	_react_left = duration

## Jumps straight to the current target with no blend -- for a face that has
## just appeared, which should not be seen easing in from neutral.
func snap() -> void:
	var target := _target()
	for i in range(MOOD_PARAMS):
		_params[i] = target[i]
	_params[P.GAZE_X] = look.x
	_params[P.GAZE_Y] = look.y
	_params[P.FACE_Y] = tilt
	_repaint()

## Paints the face into its own CanvasLayer at `layer` from now on, rather than
## into this node's canvas item.
##
## The game's WorldEnvironment glows every layer up to its
## background_canvas_max_layer, and the white-hot core the face sits on blooms
## straight over dark eyes at the character's size -- they wash out to nothing.
## A layer above that one is drawn after the glow, so the eyes stay crisp. That
## puts them above the UI as well (which glows on purpose), so the face hides
## itself whenever the tree pauses, which is when every panel that could cover
## the character is up.
##
## Still one canvas item and one draw: its transform is copied from this node
## every frame, which carries the blob's squash, stretch and lean across the
## layer boundary.
func lift_above_glow(layer: int) -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = layer
	_overlay.follow_viewport_enabled = true
	add_child(_overlay)
	_overlay_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_overlay_item, _overlay.get_canvas())
	_sync_overlay()
	_repaint()

func _sync_overlay() -> void:
	RenderingServer.canvas_item_set_transform(_overlay_item, get_global_transform())
	RenderingServer.canvas_item_set_visible(_overlay_item, is_visible_in_tree() and can_process())

func _notification(what: int) -> void:
	if not _overlay_item.is_valid():
		return
	match what:
		NOTIFICATION_PAUSED:
			RenderingServer.canvas_item_set_visible(_overlay_item, false)
		NOTIFICATION_UNPAUSED, NOTIFICATION_VISIBILITY_CHANGED:
			_sync_overlay()
		NOTIFICATION_PREDELETE:
			RenderingServer.free_rid(_overlay_item)

func _repaint() -> void:
	if _overlay_item.is_valid():
		RenderingServer.canvas_item_clear(_overlay_item)
		_paint(_overlay_item)
	else:
		queue_redraw()

func _active_mood() -> StringName:
	return _react_mood if _react_left > 0.0 else mood

func _target() -> PackedFloat32Array:
	var by_mood: Dictionary = _mood_arrays.get(style, _mood_arrays[Style.CLASSIC])
	return by_mood.get(_active_mood(), by_mood[&"neutral"])

func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	_time += d
	if _react_left > 0.0:
		_react_left -= d
	if wander:
		_update_wander(d)
	var target := _target()
	var k := 1.0 - exp(-rate * d)
	var moved := 0.0
	for i in range(MOOD_PARAMS):
		var step := (target[i] - _params[i]) * k
		_params[i] += step
		moved = maxf(moved, absf(step))
	var gaze := look
	if shake > 0.0:
		gaze += Vector2(sin(_time * 23.0), cos(_time * 17.0)) * 0.6 * shake
	moved = maxf(moved, _ease_slot(P.GAZE_X, gaze.x, k))
	moved = maxf(moved, _ease_slot(P.GAZE_Y, gaze.y, k))
	moved = maxf(moved, _ease_slot(P.FACE_Y, tilt, k))
	var blinked := _update_blink(d)
	if moved > 0.0005 or blinked or _blob.shape != _last_shape:
		_repaint()
	if _overlay_item.is_valid():
		_sync_overlay()

## Glances somewhere, holds it a moment, and every so often looks straight back
## out at the player.
func _update_wander(d: float) -> void:
	_wander_wait -= d
	if _wander_wait > 0.0:
		return
	if _rng.randf() < 0.4:
		look = Vector2.ZERO
	else:
		look = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.6))
	_wander_wait = _rng.randf_range(0.8, 2.2)

func _ease_slot(slot: int, goal: float, k: float) -> float:
	var step := (goal - _params[slot]) * k
	_params[slot] += step
	return absf(step)

## Returns whether the blink is mid-flight, i.e. whether this frame has to draw.
func _update_blink(d: float) -> bool:
	if _blink_t >= 0.0:
		_blink_t += d
		if _blink_t < BLINK_CLOSE:
			_blink = _blink_t / BLINK_CLOSE
		elif _blink_t < BLINK_CLOSE + BLINK_OPEN:
			_blink = 1.0 - (_blink_t - BLINK_CLOSE) / BLINK_OPEN
		else:
			_blink = 0.0
			_blink_t = -1.0
		return true
	if not blinking:
		return false
	_blink_wait -= d
	if _blink_wait > 0.0:
		return false
	if _params[P.BOTTOM] > BLINK_SQUINT_LIMIT:
		# Try again shortly rather than skipping a whole gap.
		_blink_wait = 0.3
		return false
	_blink_t = 0.0
	_blink_wait = 0.12 if _rng.randf() < DOUBLE_BLINK_CHANCE \
		else _rng.randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
	return true

func _draw() -> void:
	if not _overlay_item.is_valid():
		_paint(get_canvas_item())

func _paint(item: RID) -> void:
	if _blob == null:
		return
	_last_shape = _blob.shape
	var place: Vector3 = SHAPE_PLACEMENT.get(_blob.shape, Vector3(0.0, 0.0, 1.0))
	var r := _blob.radius
	var unit := r * place.z * feature_scale
	# PlasmaBlob is bottom-anchored: its centre is one radius above its origin.
	var origin := Vector2(place.x * r, -r + place.y * r)
	var p := _params
	var face_y := -p[P.FACE_Y] * TILT_RANGE
	var gaze := Vector2(p[P.GAZE_X] * GAZE_RANGE.x, p[P.GAZE_Y] * GAZE_RANGE.y)
	var eye_h := p[P.EYE_H] * (1.0 - 0.92 * _blink)
	var eye_y := p[P.EYE_Y] + face_y + gaze.y

	# Counted rather than `for side in [-1.0, 1.0]`, which builds an array
	# every draw.
	for feature in range(2):
		var side := -1.0 if feature == 0 else 1.0
		var cx: float = side * p[P.SPACING] + gaze.x
		var lid_h := p[P.LID_H] + (p[P.LID_ASYM] if side > 0.0 else 0.0)
		_fill_eye(feature, side, cx, eye_y, p[P.EYE_W], eye_h, lid_h, origin, unit)

	_fill_mouth(gaze.x * 0.6, p[P.MOUTH_Y] + face_y + gaze.y * 0.6, origin, unit)
	RenderingServer.canvas_item_add_triangle_array(item, _indices, _points, _colors)

	_paint_shine(item, origin, unit, gaze, eye_y, eye_h)
	_paint_extras(item, origin, unit, gaze, p[P.EYE_Y] + face_y + gaze.y)

## The shine is what makes the eyes read as looking at something. Dropped for
## squints and blinks, where there is no open eye to catch light.
func _paint_shine(item: RID, origin: Vector2, unit: float, gaze: Vector2,
		eye_y: float, eye_h: float) -> void:
	var p := _params
	var shine := p[P.SHINE] * (1.0 - _blink) * (1.0 - clampf(p[P.BOTTOM] * 2.0, 0.0, 1.0))
	if shine * unit < 0.4:
		return
	for feature in range(2):
		var side := -1.0 if feature == 0 else 1.0
		var cx: float = side * p[P.SPACING] + gaze.x
		var lid_h := p[P.LID_H] + (p[P.LID_ASYM] if side > 0.0 else 0.0)
		var at := Vector2(cx + p[P.EYE_W] * 0.3 + gaze.x * 0.2, eye_y - eye_h * 0.35)
		# Kept under the lid, or it floats on the body above a hooded eye.
		var lid := eye_y + lid_h * eye_h - p[P.LID_SLOPE] * (at.x - cx) * side
		at.y = maxf(at.y, lid + shine * 1.2)
		if at.y + shine > eye_y + eye_h:
			continue
		RenderingServer.canvas_item_add_circle(item, origin + at * unit, shine * unit, shine_color)

## The style's extras, over the eyes. `eye_y` is the eyes' resting line --
## blinks do not move glasses or brows.
func _paint_extras(item: RID, origin: Vector2, unit: float, gaze: Vector2, eye_y: float) -> void:
	var p := _params
	match style:
		Style.SPECS:
			var y := eye_y + p[P.VISOR] * 0.18
			for feature in range(2):
				var side := -1.0 if feature == 0 else 1.0
				var c := Vector2(side * p[P.SPACING] + gaze.x * 0.5, y)
				for i in range(RING_POINTS + 1):
					var a := TAU * float(i) / float(RING_POINTS)
					_ring[i] = origin + (c + Vector2(cos(a), sin(a)) * LENS_RADIUS) * unit
				RenderingServer.canvas_item_add_polyline(item, _ring, _ink, FRAME_WIDTH * unit)
				_glint(item, origin, unit, c, 0.17)
			var inner := p[P.SPACING] - LENS_RADIUS
			_segs.resize(2)
			_segs[0] = origin + Vector2(-inner + gaze.x * 0.5, y - 0.03) * unit
			_segs[1] = origin + Vector2(inner + gaze.x * 0.5, y - 0.03) * unit
			RenderingServer.canvas_item_add_multiline(item, _segs, _ink, FRAME_WIDTH * unit)
		Style.LASHES:
			_paint_lashes(item, origin, unit, gaze, eye_y)
			if p[P.BLUSH] > 0.01:
				var col := blush_color
				col.a = 0.55 * p[P.BLUSH]
				for feature in range(2):
					var side := -1.0 if feature == 0 else 1.0
					var at := Vector2(side * (p[P.SPACING] + 0.08), eye_y + p[P.EYE_H] + 0.08)
					RenderingServer.canvas_item_add_circle(item, origin + at * unit, 0.1 * unit, col)
		Style.GRUMPY:
			_segs.resize(4)
			for feature in range(2):
				var side := -1.0 if feature == 0 else 1.0
				var cx := side * p[P.SPACING] + gaze.x
				var y := eye_y - p[P.EYE_H] - 0.09 + p[P.BROW]
				var inner := Vector2(cx - side * p[P.EYE_W] * 1.0, y + p[P.BROW_TILT] * 0.1)
				var outer := Vector2(cx + side * p[P.EYE_W] * 1.2, y - p[P.BROW_TILT] * 0.05)
				_segs[feature * 2] = origin + inner * unit
				_segs[feature * 2 + 1] = origin + outer * unit
			RenderingServer.canvas_item_add_multiline(item, _segs, _ink, BROW_WIDTH * unit)

## Three lashes flicking outward off the top of each eye's outer half, sitting
## on the lid where the lid is down -- so a closed eye in a wink keeps them.
func _paint_lashes(item: RID, origin: Vector2, unit: float, gaze: Vector2, eye_y: float) -> void:
	var p := _params
	var length := 0.09 * p[P.LASH]
	if length * unit < 0.5:
		return
	_segs.resize(12)
	var h := p[P.EYE_H] * (1.0 - 0.92 * _blink)
	for feature in range(2):
		var side := -1.0 if feature == 0 else 1.0
		var cx := side * p[P.SPACING] + gaze.x
		var lid_h := p[P.LID_H] + (p[P.LID_ASYM] if side > 0.0 else 0.0)
		for k in range(3):
			var u := 0.35 + 0.28 * float(k)
			var x := cx + side * u * p[P.EYE_W]
			var lid := eye_y + lid_h * h - p[P.LID_SLOPE] * u * p[P.EYE_W]
			var top := maxf(eye_y - sqrt(1.0 - u * u) * h, lid)
			var dir := Vector2(side * (0.4 + 0.6 * u), -1.0).normalized()
			var i := (feature * 3 + k) * 2
			_segs[i] = origin + Vector2(x, top) * unit
			_segs[i + 1] = origin + (Vector2(x, top) + dir * length) * unit
	RenderingServer.canvas_item_add_multiline(item, _segs, _ink, LASH_WIDTH * unit)

## A white streak across a lens, faded in by GLINT.
func _glint(item: RID, origin: Vector2, unit: float, centre: Vector2, size: float) -> void:
	var glint := _params[P.GLINT]
	if glint < 0.02:
		return
	var col := shine_color
	col.a = glint
	_tint[0] = col
	_segs.resize(2)
	_segs[0] = origin + (centre + Vector2(-size, size * 0.6)) * unit
	_segs[1] = origin + (centre + Vector2(size * 0.4, -size)) * unit
	RenderingServer.canvas_item_add_multiline(item, _segs, _tint, FRAME_WIDTH * 1.2 * unit)

## One eye as a strip of columns: each column runs from the ellipse's top, cut
## down by the lid line, to its bottom, cut up by the bottom lid's arch. A
## column whose cuts cross is left at zero height rather than flipped.
func _fill_eye(feature: int, side: float, cx: float, cy: float, w: float, h: float,
		lid_h: float, origin: Vector2, unit: float) -> void:
	var base := feature * FEATURE_VERTS
	var slope := _params[P.LID_SLOPE]
	var bottom := _params[P.BOTTOM]
	var lid_base := cy + lid_h * h
	for i in range(COLUMNS + 1):
		var u := _columns_u[i]
		var x := cx + u * w
		var half := sqrt(maxf(1.0 - u * u, 0.0)) * h
		# Outward from the face's middle is positive on both eyes.
		var lid := lid_base - slope * u * w * side
		var top := maxf(cy - half, lid)
		var arch := cy + h * (1.0 - bottom * 1.6 * (1.0 - u * u))
		var bot := maxf(minf(cy + half, arch), top)
		_points[base + i * 2] = origin + Vector2(x, top) * unit
		_points[base + i * 2 + 1] = origin + Vector2(x, bot) * unit

func _fill_mouth(cx: float, cy: float, origin: Vector2, unit: float) -> void:
	var base := 2 * FEATURE_VERTS
	var w := _params[P.MOUTH_W]
	var h := _params[P.MOUTH_H]
	var flat_top := cy - h * (1.0 - _params[P.MOUTH_FLAT])
	for i in range(COLUMNS + 1):
		var u := _columns_u[i]
		var x := cx + u * w
		var half := sqrt(maxf(1.0 - u * u, 0.0)) * h
		var top := maxf(cy - half, flat_top)
		var bot := maxf(cy + half, top)
		_points[base + i * 2] = origin + Vector2(x, top) * unit
		_points[base + i * 2 + 1] = origin + Vector2(x, bot) * unit
