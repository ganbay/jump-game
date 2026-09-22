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
## Heading is split from speed, and the particle's own random heading from the
## one it actually travels on, so a zone can retune either without respawning
## the field: _dir is what it rolled, _heading is that blended toward the zone's
## common current (see zone_ambience.gd), and _base_speed is scaled per zone.
var _dir: PackedVector2Array = PackedVector2Array()
var _heading: PackedVector2Array = PackedVector2Array()
var _base_speed: PackedFloat32Array = PackedFloat32Array()
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
## The silhouette's resting angle, rolled per particle so a field of shards
## doesn't look stamped. Spin and heading-alignment are applied on top of it.
var _angle: PackedFloat32Array = PackedFloat32Array()
## _heading as an angle, cached rather than recomputed per frame: alignment
## needs it every frame, but it only changes when the profile does.
var _heading_angle: PackedFloat32Array = PackedFloat32Array()

## The whole field is emitted as one indexed triangle array rather than one
## draw_circle per particle: polygon commands do not batch on the mobile
## renderer, so 52 stars meant 52 draw calls every frame. Particles are only a
## few pixels across, so a 10-sided fan is indistinguishable from a circle --
## at max_radius the flat side sits about a third of a pixel inside the arc,
## and glow blurs that away.
const CIRCLE_SEGMENTS := 10
## One unit silhouette per ZoneAmbience.Shape, all with CIRCLE_SEGMENTS points
## in the same angular order. Built once.
var _shapes: Dictionary = {}
## The silhouette currently drawn: the zone's shape, or a point-by-point blend
## of two of them mid-crossfade. Equal vertex counts are what make that blend a
## morph rather than a pop -- see ZoneAmbience.Shape.
var _unit_shape: PackedVector2Array = PackedVector2Array()
var _shape_from: PackedVector2Array = PackedVector2Array()
var _shape_to: PackedVector2Array = PackedVector2Array()
var _tri_indices: PackedInt32Array = PackedInt32Array()
var _tri_points: PackedVector2Array = PackedVector2Array()
var _tri_colors: PackedColorArray = PackedColorArray()

## Wobble and twinkle phase, advanced by the current frequency each frame
## rather than derived as elapsed_time * frequency. A zone change retunes those
## frequencies, and a product would jump the phase by minutes-of-runtime times
## the change the instant it happened -- twenty cycles of thrash mid-crossfade
## on a run that has been going a while. Integrating keeps the phase continuous
## and lets the frequency change under it.
var _wobble_t: float = 0.0
var _twinkle_t: float = 0.0
## Spin is integrated for the same reason -- a zone that turns its particles
## faster must not also teleport them to a new angle.
var _spin_t: float = 0.0
var _spin_rate: float = 0.0
## The zone backdrop, crossfaded rather than switched: _from and _to are
## ZoneAmbience profiles and _mix walks 0 -> 1 between them. At 1 the field has
## settled and the per-frame re-derivation below stops.
var _from: Dictionary = {}
var _to: Dictionary = {}
var _mix: float = 1.0
## The mixed profile unpacked into typed fields once per frame. Same reason the
## particle state is packed arrays: these are read per particle, and a
## Dictionary lookup in that loop is what this file exists to avoid.
var _speed_mult: float = 1.0
var _wobble_amp: float = 1.0
var _wobble_freq: float = 1.0
var _twinkle_freq: float = 1.0
var _twinkle_floor: float = TWINKLE_FLOOR
var _radius_mult: float = 1.0
var _flow: float = 0.0
var _flow_dir: Vector2 = Vector2.DOWN
var _stretch: float = 1.0
var _align: float = 0.0
var _pulse: float = 0.0
var _tint: Color = Color.WHITE
var _tint_weight: float = 0.0
var _last_camera_pos: Vector2 = Vector2.ZERO
var _has_camera_ref: bool = false
var _bounds: Vector2 = Vector2(720, 1280)

func _ready() -> void:
	_bounds = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	visibility_changed.connect(_apply_mode)
	# Before the particles spawn: _init_particle reads the unpacked fields.
	# Resolved, not raw: the opening's colour is the character's, and seeding it
	# here means the field is already wearing it on the first frame instead of
	# fading into it once the run's first zone change lands.
	_from = ZoneAmbience.resolved_profile(ZoneAmbience.OPENING)
	_to = _from
	_unpack(_from)
	_build_geometry_buffers()
	_spawn_particles()
	_apply_mode()
	Settings.visual_settings_changed.connect(_on_visual_settings_changed)

func _on_viewport_resized() -> void:
	_bounds = get_viewport_rect().size

## Fixed index pattern for `particle_count` fans, each triangulated from its
## first vertex. Only vertex positions and colours change per frame.
func _build_geometry_buffers() -> void:
	for kind in [ZoneAmbience.Shape.ROUND, ZoneAmbience.Shape.LENS,
			ZoneAmbience.Shape.SHARD, ZoneAmbience.Shape.BLOB]:
		_shapes[kind] = _build_shape(kind)
	_unit_shape = (_shapes[_to["shape"]] as PackedVector2Array).duplicate()
	_shape_from = _unit_shape.duplicate()
	_shape_to = _unit_shape.duplicate()
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

## Every silhouette is a closed ring of CIRCLE_SEGMENTS points at the same
## angles, differing only in how far out each one sits. Keeping the count and
## the order fixed is what lets any shape morph into any other, and lets all of
## them reuse the one fan triangulation built above.
static func _build_shape(kind: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(CIRCLE_SEGMENTS)
	for i in range(CIRCLE_SEGMENTS):
		var a := TAU * float(i) / float(CIRCLE_SEGMENTS)
		var c := cos(a)
		var sn := sin(a)
		match kind:
			ZoneAmbience.Shape.LENS:
				# Pinched toward the x extremes, so stretching one along its
				# heading gives a pointed streak rather than a fat ellipse.
				pts[i] = Vector2(c, sn * (1.0 - absf(c) * 0.88))
			ZoneAmbience.Shape.SHARD:
				# Alternating radii on an even vertex count: five sharp spikes.
				pts[i] = Vector2(c, sn) * (1.0 if i % 2 == 0 else 0.34)
			ZoneAmbience.Shape.BLOB:
				# The same fixed irregularity on every particle. Rolling it per
				# particle would read as ten different sprites rather than as
				# one field of one organic thing.
				pts[i] = Vector2(c, sn) * (1.0 + 0.3 * sin(a * 3.0 + 0.7))
			_:
				pts[i] = Vector2(c, sn)
	return pts

func _spawn_particles() -> void:
	var size := _bounds
	_pos.resize(particle_count)
	_dir.resize(particle_count)
	_heading.resize(particle_count)
	_base_speed.resize(particle_count)
	_radius.resize(particle_count)
	_parallax.resize(particle_count)
	_color.resize(particle_count)
	_boost.resize(particle_count)
	_alpha.resize(particle_count)
	_phase.resize(particle_count)
	_angle.resize(particle_count)
	_heading_angle.resize(particle_count)
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
	_dir[i] = Vector2.RIGHT.rotated(randf() * TAU)
	_heading[i] = _blend_heading(i)
	_base_speed[i] = lerpf(min_speed, max_speed, depth)
	_radius[i] = lerpf(min_radius, max_radius, depth)
	_parallax[i] = lerpf(0.15, 0.85, depth)
	_boost[i] = lerpf(1.0, 1.6, depth)
	_alpha[i] = lerpf(0.125, 0.375, depth)
	_phase[i] = randf() * TAU
	_angle[i] = randf() * TAU
	_heading_angle[i] = _heading[i].angle()
	_color[i] = _shade(_particle_base(), i)

func _shade(base: Color, i: int) -> Color:
	var col := base * _boost[i]
	col.a = _alpha[i]
	return col

## The player's chosen particle colour, pulled part-way toward the zone's. The
## blend is deliberately partial -- see ZoneAmbience's note on TINT_WEIGHT.
func _particle_base() -> Color:
	return Settings.background_particle_color.lerp(_tint, _tint_weight)

## Starts a crossfade to `profile`. Called on every zone change; taking _from
## from the live values rather than from _to means a zone that arrives mid-fade
## continues from what is on screen instead of snapping back.
func blend_to(profile: Dictionary) -> void:
	_from = _live_profile()
	_to = profile
	# From what is on screen rather than from the outgoing zone's shape, so a
	# zone arriving mid-morph continues the morph instead of snapping back to a
	# silhouette the field has already half left.
	_shape_from = _unit_shape.duplicate()
	_shape_to = _shapes[profile["shape"]]
	_mix = 0.0
	# Nothing advances _mix while the field is switched off, so land on the new
	# profile immediately and let it be right whenever it is switched back on.
	if not is_processing():
		_mix = 1.0
		_unpack(_to)
		_retune()

func _live_profile() -> Dictionary:
	# No background colours: those live on the backdrop shader, which game.gd
	# tweens on its own clock. Only what the field itself reads is snapshotted.
	return {
		"tint": _tint, "tint_weight": _tint_weight,
		"speed": _speed_mult, "wobble_amp": _wobble_amp,
		"wobble_freq": _wobble_freq, "twinkle_freq": _twinkle_freq,
		"twinkle_floor": _twinkle_floor, "radius": _radius_mult,
		"flow": _flow, "flow_deg": rad_to_deg(_flow_dir.angle()),
		"stretch": _stretch, "align": _align,
		"spin": _spin_rate, "pulse": _pulse,
	}

func _unpack(p: Dictionary) -> void:
	_speed_mult = p["speed"]
	_wobble_amp = p["wobble_amp"]
	_wobble_freq = p["wobble_freq"]
	_twinkle_freq = p["twinkle_freq"]
	_twinkle_floor = p["twinkle_floor"]
	_radius_mult = p["radius"]
	_flow = p["flow"]
	_flow_dir = Vector2.RIGHT.rotated(deg_to_rad(p["flow_deg"]))
	_tint = p["tint"]
	_tint_weight = p["tint_weight"]
	_stretch = p["stretch"]
	_align = p["align"]
	_spin_rate = p["spin"]
	# Clamped because _draw divides the minor axis by (1 + pulse * sin): at 1.0
	# a particle would invert through zero width once per cycle. Done here, once
	# a frame, rather than per particle in the draw loop.
	_pulse = clampf(p["pulse"], 0.0, 0.9)

## Interpolates _from -> _to at _mix and unpacks the result. The current is
## interpolated as an angle rather than as a vector, so a zone whose flow points
## the other way sweeps round instead of collapsing through zero length.
func _unpack_mixed() -> void:
	var t := _mix
	_speed_mult = lerpf(_from["speed"], _to["speed"], t)
	_wobble_amp = lerpf(_from["wobble_amp"], _to["wobble_amp"], t)
	_wobble_freq = lerpf(_from["wobble_freq"], _to["wobble_freq"], t)
	_twinkle_freq = lerpf(_from["twinkle_freq"], _to["twinkle_freq"], t)
	_twinkle_floor = lerpf(_from["twinkle_floor"], _to["twinkle_floor"], t)
	_radius_mult = lerpf(_from["radius"], _to["radius"], t)
	_flow = lerpf(_from["flow"], _to["flow"], t)
	var angle := lerp_angle(deg_to_rad(_from["flow_deg"]), deg_to_rad(_to["flow_deg"]), t)
	_flow_dir = Vector2.RIGHT.rotated(angle)
	_tint = Color(_from["tint"]).lerp(_to["tint"], t)
	_tint_weight = lerpf(_from["tint_weight"], _to["tint_weight"], t)
	_stretch = lerpf(_from["stretch"], _to["stretch"], t)
	_align = lerpf(_from["align"], _to["align"], t)
	_spin_rate = lerpf(_from["spin"], _to["spin"], t)
	_pulse = clampf(lerpf(_from["pulse"], _to["pulse"], t), 0.0, 0.9)

## The heading a particle actually travels on: its own, turned toward the zone's
## current by however much of the field that zone sweeps up.
func _blend_heading(i: int) -> Vector2:
	if _flow <= 0.0:
		return _dir[i]
	return _dir[i].slerp(_flow_dir, _flow)

## Re-derives everything the profile feeds. Cached rather than recomputed in the
## draw loop, because once a crossfade settles none of it changes again.
func _retune() -> void:
	for v in range(CIRCLE_SEGMENTS):
		_unit_shape[v] = _shape_from[v].lerp(_shape_to[v], _mix)
	var base := _particle_base()
	for i in range(_pos.size()):
		_heading[i] = _blend_heading(i)
		_heading_angle[i] = _heading[i].angle()
		_color[i] = _shade(base, i)

func _on_visual_settings_changed() -> void:
	_apply_mode()
	var base := _particle_base()
	for i in range(_color.size()):
		_color[i] = _shade(base, i)
	queue_redraw()

## Only simulate when this instance is actually on screen and the setting is on.
func _apply_mode() -> void:
	var enabled: bool = Settings.background_particles
	visible = enabled
	set_process(enabled and is_visible_in_tree())

func _process(delta: float) -> void:
	if _mix < 1.0:
		_mix = minf(_mix + delta / ZoneAmbience.BLEND_TIME, 1.0)
		_unpack_mixed()
		_retune()
	_wobble_t += delta * WOBBLE_FREQ * _wobble_freq
	_twinkle_t += delta * TWINKLE_FREQ * _twinkle_freq
	_spin_t += delta * _spin_rate
	var size := _bounds
	var cam_delta := _poll_camera_delta()
	for i in range(_pos.size()):
		var p: Vector2 = _pos[i] + _heading[i] * (_base_speed[i] * _speed_mult) * delta \
			- cam_delta * _parallax[i]
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
	var amp := WOBBLE_AMPLITUDE * _wobble_amp
	# Hoisted: three of the five zones never deform, and this is the one sine
	# per particle per frame that can be skipped outright when they don't.
	var pulsing := _pulse > 0.0
	for i in range(_pos.size()):
		var perp := _heading[i].rotated(PI / 2.0)
		var wobble := perp * amp * sin(_wobble_t + _phase[i])
		var twinkle := lerpf(_twinkle_floor, 1.0, 0.5 + 0.5 * sin(_twinkle_t + _phase[i] * 1.7))
		var col := _color[i]
		col.a *= twinkle
		var centre := _pos[i] + wobble
		var r := _radius[i] * _radius_mult
		var ang := _angle[i] + _spin_t
		if _align > 0.0:
			ang = lerp_angle(ang, _heading_angle[i], _align)
		# Squash and stretch about the silhouette's own axes, one growing as the
		# other shrinks, so a pulsing particle keeps roughly its area instead of
		# throbbing brighter and dimmer. Driven off the wobble clock on purpose:
		# a zone that jitters fast should deform at that same fast rate.
		var squash := (1.0 + _pulse * sin(_wobble_t * 2.0 + _phase[i] * 1.3)) if pulsing else 1.0
		var cs := cos(ang)
		var sn := sin(ang)
		# The rotated, scaled basis the silhouette is laid out on. Built once per
		# particle rather than rotating each of its vertices in turn.
		var ax := Vector2(cs, sn) * (r * _stretch * squash)
		var ay := Vector2(-sn, cs) * (r / squash)
		var base := i * CIRCLE_SEGMENTS
		for v in range(CIRCLE_SEGMENTS):
			var u := _unit_shape[v]
			_tri_points[base + v] = centre + ax * u.x + ay * u.y
			_tri_colors[base + v] = col
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _tri_indices, _tri_points, _tri_colors)
