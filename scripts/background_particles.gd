extends Node2D
class_name BackgroundParticles

@export var particle_count: int = 52
@export var min_radius: float = 0.2
@export var max_radius: float = 4.5
@export var min_speed: float = 4.0
@export var max_speed: float = 12.0
@export var edge_margin: float = 12.0

## Straight-line drift as the base motion, with a perpendicular sine wobble
## and a twinkling alpha layered on top at draw time -- an offset from the
## path, not a change to it, so it can layer on cleanly without touching the
## authoritative position/alpha arrays.
const WOBBLE_AMPLITUDE := 5.0
const WOBBLE_FREQ := 1.1
const TWINKLE_FREQ := 1.7
## Twinkle dips to this fraction of full alpha at its dimmest and no further --
## a particle should shimmer, not blink out.
const TWINKLE_FLOOR := 0.35

# Particle state is kept as parallel packed arrays rather than an array of
# Dictionaries: this runs for every particle every frame, and a Dictionary
# lookup per field per particle was the bulk of the cost.
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _parallax: PackedFloat32Array = PackedFloat32Array()
## Final draw colour, with the depth boost and alpha already folded in.
var _color: PackedColorArray = PackedColorArray()
## Per-particle depth tint multiplier, kept so colours can be recomputed when
## the palette changes without respawning the field.
var _boost: PackedFloat32Array = PackedFloat32Array()
var _alpha: PackedFloat32Array = PackedFloat32Array()
## Per-particle phase offset for the wobble/twinkle, so the field doesn't
## pulse in lockstep.
var _phase: PackedFloat32Array = PackedFloat32Array()

## The whole field is emitted as one indexed triangle array rather than one
## draw_circle per particle: polygon commands do not batch on the mobile
## renderer, so 52 stars meant 52 draw calls every frame. Particles are only a
## few pixels across, so a 10-sided fan is indistinguishable from a circle --
## at max_radius the flat side sits about a third of a pixel inside the arc,
## and glow blurs that away.
const CIRCLE_SEGMENTS := 10
## Unit circle, scaled and offset per particle. Built once.
var _unit_circle: PackedVector2Array = PackedVector2Array()
var _tri_indices: PackedInt32Array = PackedInt32Array()
var _tri_points: PackedVector2Array = PackedVector2Array()
var _tri_colors: PackedColorArray = PackedColorArray()

var _t: float = 0.0
var _last_camera_pos: Vector2 = Vector2.ZERO
var _has_camera_ref: bool = false
var _bounds: Vector2 = Vector2(720, 1280)

func _ready() -> void:
	_bounds = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	visibility_changed.connect(_apply_mode)
	_build_geometry_buffers()
	_spawn_particles()
	_apply_mode()
	Settings.visual_settings_changed.connect(_on_visual_settings_changed)

func _on_viewport_resized() -> void:
	_bounds = get_viewport_rect().size

## Fixed index pattern for `particle_count` fans, each triangulated from its
## first vertex. Only vertex positions and colours change per frame.
func _build_geometry_buffers() -> void:
	_unit_circle.resize(CIRCLE_SEGMENTS)
	for i in range(CIRCLE_SEGMENTS):
		var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
		_unit_circle[i] = Vector2(cos(a), sin(a))
	var tris_per_fan := CIRCLE_SEGMENTS - 2
	_tri_points.resize(particle_count * CIRCLE_SEGMENTS)
	_tri_colors.resize(particle_count * CIRCLE_SEGMENTS)
	_tri_indices.resize(particle_count * tris_per_fan * 3)
	var w := 0
	for f in range(particle_count):
		var base := f * CIRCLE_SEGMENTS
		for t in range(tris_per_fan):
			_tri_indices[w] = base
			_tri_indices[w + 1] = base + t + 1
			_tri_indices[w + 2] = base + t + 2
			w += 3

func _spawn_particles() -> void:
	var size := _bounds
	_pos.resize(particle_count)
	_vel.resize(particle_count)
	_radius.resize(particle_count)
	_parallax.resize(particle_count)
	_color.resize(particle_count)
	_boost.resize(particle_count)
	_alpha.resize(particle_count)
	_phase.resize(particle_count)
	# Split the screen into a jittered grid so particles start evenly spread
	# out instead of randomly clumping.
	var cols := int(max(ceil(sqrt(float(particle_count) * size.x / size.y)), 1.0))
	var rows := int(ceil(float(particle_count) / cols))
	var cell := Vector2(size.x / cols, size.y / rows)
	var cells: Array = []
	for cx in range(cols):
		for cy in range(rows):
			cells.append(Vector2(cx, cy))
	cells.shuffle()
	for i in range(particle_count):
		var c: Vector2 = cells[i % cells.size()]
		var origin := Vector2(c.x * cell.x, c.y * cell.y) + Vector2(randf() * cell.x, randf() * cell.y)
		_init_particle(i, origin)

## Rolls a fresh depth/velocity/size/colour for particle `i` at `origin`.
func _init_particle(i: int, origin: Vector2) -> void:
	var depth := randf_range(0.15, 1.0)
	_pos[i] = origin
	_vel[i] = Vector2.RIGHT.rotated(randf() * TAU) * lerpf(min_speed, max_speed, depth)
	_radius[i] = lerpf(min_radius, max_radius, depth)
	_parallax[i] = lerpf(0.15, 0.85, depth)
	_boost[i] = lerpf(1.0, 1.6, depth)
	_alpha[i] = lerpf(0.125, 0.375, depth)
	_phase[i] = randf() * TAU
	_color[i] = _shade(Settings.background_particle_color, i)

func _shade(base: Color, i: int) -> Color:
	var col := base * _boost[i]
	col.a = _alpha[i]
	return col

func _on_visual_settings_changed() -> void:
	_apply_mode()
	for i in range(_color.size()):
		_color[i] = _shade(Settings.background_particle_color, i)
	queue_redraw()

## Only simulate when this instance is actually on screen and the setting is on.
func _apply_mode() -> void:
	var enabled: bool = Settings.background_particles
	visible = enabled
	set_process(enabled and is_visible_in_tree())

func _process(delta: float) -> void:
	_t += delta
	var size := _bounds
	var cam_delta := _poll_camera_delta()
	for i in range(_pos.size()):
		var p: Vector2 = _pos[i] + _vel[i] * delta - cam_delta * _parallax[i]
		if p.x < -edge_margin:
			p.x = size.x + edge_margin
		elif p.x > size.x + edge_margin:
			p.x = -edge_margin
		if p.y < -edge_margin:
			p.y = size.y + edge_margin
		elif p.y > size.y + edge_margin:
			p.y = -edge_margin
		_pos[i] = p
	queue_redraw()

func _poll_camera_delta() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		_has_camera_ref = false
		return Vector2.ZERO
	var cam_pos := cam.global_position
	var delta := (cam_pos - _last_camera_pos) if _has_camera_ref else Vector2.ZERO
	_last_camera_pos = cam_pos
	_has_camera_ref = true
	return delta

func _draw() -> void:
	for i in range(_pos.size()):
		var dir := _vel[i].normalized() if _vel[i] != Vector2.ZERO else Vector2.RIGHT
		var perp := dir.rotated(PI / 2.0)
		var wobble := perp * WOBBLE_AMPLITUDE * sin(_t * WOBBLE_FREQ + _phase[i])
		var twinkle := lerpf(TWINKLE_FLOOR, 1.0, 0.5 + 0.5 * sin(_t * TWINKLE_FREQ + _phase[i] * 1.7))
		var col := _color[i]
		col.a *= twinkle
		var centre := _pos[i] + wobble
		var r := _radius[i]
		var base := i * CIRCLE_SEGMENTS
		for v in range(CIRCLE_SEGMENTS):
			_tri_points[base + v] = centre + _unit_circle[v] * r
			_tri_colors[base + v] = col
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _tri_indices, _tri_points, _tri_colors)
