extends Node2D

@export var particle_count: int = 52
@export var min_radius: float = 0.2
@export var max_radius: float = 4.5
@export var min_speed: float = 4.0
@export var max_speed: float = 12.0
@export var edge_margin: float = 12.0

var _particles: Array = []
var _last_camera_pos: Vector2 = Vector2.ZERO
var _has_camera_ref: bool = false

func _ready() -> void:
	_spawn_particles()
	_apply_mode()
	Settings.visual_settings_changed.connect(_on_visual_settings_changed)

func _spawn_particles() -> void:
	var size := get_viewport_rect().size
	_particles.clear()
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
		var origin := Vector2(c.x * cell.x, c.y * cell.y)
		var pos := origin + Vector2(randf() * cell.x, randf() * cell.y)
		_particles.append(_make_particle(pos))

func _make_particle(pos: Vector2) -> Dictionary:
	var depth := randf_range(0.15, 1.0)
	var angle := randf() * TAU
	return {
		"pos": pos,
		"vel": Vector2.RIGHT.rotated(angle) * lerpf(min_speed, max_speed, depth),
		"radius": lerpf(min_radius, max_radius, depth),
		"alpha": lerpf(0.125, 0.375, depth),
		"boost": lerpf(1.0, 1.6, depth),
		"parallax": lerpf(0.15, 0.85, depth),
		"color": _pick_color(),
	}

func _pick_color() -> Color:
	if Settings.background_fx == Settings.BackgroundFxMode.SINGLE:
		return Settings.background_particle_color
	var colors: Array = Settings.platform_colors.values()
	return colors[randi() % colors.size()]

func _on_visual_settings_changed() -> void:
	_apply_mode()
	for p in _particles:
		p["color"] = _pick_color()
	queue_redraw()

func _apply_mode() -> void:
	var enabled := Settings.background_fx != Settings.BackgroundFxMode.OFF
	visible = enabled
	set_process(enabled)

func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	var cam_delta := _poll_camera_delta()
	for p in _particles:
		p["pos"] += p["vel"] * delta - cam_delta * p["parallax"]
		if p["pos"].x < -edge_margin:
			p["pos"].x = size.x + edge_margin
		elif p["pos"].x > size.x + edge_margin:
			p["pos"].x = -edge_margin
		if p["pos"].y < -edge_margin:
			p["pos"].y = size.y + edge_margin
		elif p["pos"].y > size.y + edge_margin:
			p["pos"].y = -edge_margin
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
	for p in _particles:
		var col: Color = p["color"] * p["boost"]
		col.a = p["alpha"]
		draw_circle(p["pos"], p["radius"], col)
