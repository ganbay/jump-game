extends Node2D

## Frozen copy of the second 3D icon (promo/icon_3d_v2.png): the cast with the
## first round of faces. Kept so it can be re-shot after icon_3d.gd moves on.

## A 3D take on the 512x512 Play Store icon: the cast erupting off the star and
## flying straight at a camera hanging high above the surface, seen through a
## fisheye.
##
## Shot through the same harness as icon_screenshot.gd (promo_shot.gd owns the
## 512x512 SubViewport, the preview and the export). The 3D world is rendered
## into a SubViewport of its own at `supersample` times the output size, and a
## Sprite2D draws that back down at 512 through a barrel-distortion shader --
## Godot has no fisheye camera, and a spatial screen-texture pass would only see
## the opaque geometry, missing every trail and glow.
##
## Nothing from the game's 2D scenes is reused directly; the characters are
## meshes inflated from PlasmaBlob.shape_radius, so each one keeps the exact
## silhouette of its skin, and icon3d_blob.gdshader paints them with the game's
## body/core bands.
##
## Everyone flies a straight line from the eruption point to a spot in front of
## the lens, accelerating the whole way, and arrives there exactly at
## `pose_time` -- which is the frame the harness freezes on and shoots.

signal pose_reached

@export_group("Frame")
## The 3D render is this many times the output size, then filtered down.
@export var supersample: int = 2
@export var fisheye_strength: float = 0.45
@export var lens_zoom: float = 1.0
@export var vignette: float = 0.55

@export_group("Camera")
## Vertical field of view before the fisheye pass. Wide on purpose: it is what
## makes the nearest body loom and the far ones shrink to points.
@export var camera_fov: float = 100.0
@export var camera_altitude: float = 26.0
## How far south of the eruption the camera hangs. Zero puts the eruption
## straight below, hidden behind whoever is flying at the lens.
@export var camera_back: float = 8.0
## Degrees below the horizon the camera looks. Lower shows more sky over the
## planet's curved horizon; higher fills the frame with the surface.
@export var camera_pitch: float = 58.0

@export_group("Planet")
@export var planet_radius: float = 100.0
@export var planet_color: Color = Color(0.26, 0.14, 0.7)
@export var planet_band: Color = Color(0.4, 0.26, 0.92)
@export var planet_hot: Color = Color(1.0, 0.85, 1.0)
@export var atmosphere_color: Color = Color(0.55, 0.42, 1.0)

@export_group("Eruption")
@export var flash_size: float = 11.0
@export var flash_strength: float = 0.8
@export var spike_count: int = 22
@export var spike_length: float = 14.0
@export var spike_width: float = 1.1
@export var shock_speed: float = 9.0
@export var eruption_decay: float = 2.2
@export var eruption_seed: int = 7

@export_group("Flight")
@export var pose_time: float = 1.4
@export var cycle_time: float = 2.4
## Exponent of the ease along each path. Above 1 accelerates, so the bodies are
## still gaining speed when they reach the lens.
@export var ease_power: float = 2.0
## How far back towards the eruption each trail reaches, as a fraction of the
## distance flown so far.
@export var trail_reach: float = 0.85
## How far each body turns from upright towards the way it is moving on screen.
## 0 keeps every shape the right way up, like the game; 1 points them all
## outward from the burst.
@export var lean: float = 0.35
@export var stretch: float = 1.12
@export var halo_reach: float = 2.6
@export var halo_strength: float = 0.4
@export var debris_per_body: int = 2
## Faces on the cast, each wearing the expression its CAST entry names.
## Icon-only: nobody in the game has a face.
@export var faces: bool = true
## Size of the face quad relative to a body's radius, before each entry's own
## `face_size`.
@export var face_size: float = 1.5

## The cast. `depth` is distance in front of the lens at the pose; `offset` is
## where across the frame, in units of the frustum's half-width at that depth
## (so +/-1 is the edge before the fisheye pulls it in). Player first.
const CAST := [
	{"shape": PlasmaBlob.Shape.CIRCLE, "color": Color(0.46, 0.32, 1.0), "size": 1.0,
		"depth": 2.6, "offset": Vector2(0.0, 0.36), "launch": 0.55,
		"face": "determined"},
	{"shape": PlasmaBlob.Shape.STAR, "color": Color(1.0, 0.78, 0.22), "size": 0.9,
		"depth": 6.5, "offset": Vector2(-0.5, 0.3), "launch": 0.35,
		"face": "cocky", "face_size": 1.0, "face_offset": Vector2(0.0, -0.05)},
	{"shape": PlasmaBlob.Shape.HEART, "color": Color(1.0, 0.3, 0.58), "size": 0.9,
		"depth": 7.0, "offset": Vector2(0.5, 0.32), "launch": 0.30,
		"face": "joyful", "face_size": 1.1, "face_offset": Vector2(0.0, -0.1)},
	{"shape": PlasmaBlob.Shape.TRIANGLE, "color": Color(0.2, 0.85, 1.0), "size": 0.9,
		"depth": 6.0, "offset": Vector2(0.47, -0.4), "launch": 0.40,
		"face": "shocked", "face_size": 0.85, "face_offset": Vector2(0.0, 0.04)},
	{"shape": PlasmaBlob.Shape.FLAME, "color": Color(1.0, 0.48, 0.12), "size": 0.9,
		"depth": 6.5, "offset": Vector2(-0.47, -0.42), "launch": 0.38,
		"face": "hyped", "face_size": 0.95, "face_offset": Vector2(0.0, -0.02)},
]

## One face, many moods: overrides on icon3d_face.gdshader's defaults, which
## are the player's "determined".
const FACES := {
	"determined": {},
	# One lid dropped flat, the other brow raised, and a lopsided smile.
	"cocky": {"lid_height": Vector2(0.03, -0.13), "lid_slope": Vector2(0.0, -0.3), "mouth_mode": 4},
	"joyful": {"eye_mode": 1, "mouth_mode": 2},
	"shocked": {"eye_size": Vector2(0.11, 0.13), "lid_height": Vector2(-1.0, -1.0),
		"lid_slope": Vector2.ZERO, "mouth_mode": 1, "mouth_size": Vector2(0.07, 0.09)},
	"hyped": {"eye_size": Vector2(0.1, 0.15), "lid_height": Vector2(-1.0, -1.0),
		"lid_slope": Vector2.ZERO, "mouth_mode": 3, "mouth_size": Vector2(0.13, 0.11),
		"mouth_center": Vector2(0.0, 0.2)},
}

const BLOB_SHADER := preload("res://shaders/icon3d_blob.gdshader")
const GLOW_SHADER := preload("res://shaders/icon3d_glow.gdshader")
const STREAK_SHADER := preload("res://shaders/icon3d_streak.gdshader")
const PLANET_SHADER := preload("res://shaders/icon3d_planet.gdshader")
const ATMOSPHERE_SHADER := preload("res://shaders/icon3d_atmosphere.gdshader")
const SKY_SHADER := preload("res://shaders/icon3d_sky.gdshader")
const LENS_SHADER := preload("res://shaders/icon3d_lens.gdshader")
const FACE_SHADER := preload("res://shaders/icon3d_face.gdshader")

## Inflated-mesh resolution. 120 perimeter points resolves the star's and
## sparkle's notches; the rings only shape the rounded sides.
const MESH_SEGMENTS := 120
const MESH_RINGS := 20
## Front-to-back thickness relative to radius.
const MESH_DEPTH := 0.9
const TRAIL_STEPS := 14

var _world: SubViewport
var _camera: Camera3D
var _lens: Sprite2D
var _planet_mat: ShaderMaterial
var _streaks: ImmediateMesh
var _streak_mat: ShaderMaterial
var _flash: MeshInstance3D
var _erupt: Vector3
var _bodies: Array[Dictionary] = []
var _spikes: Array[Dictionary] = []
var _meshes: Dictionary = {}
var _t: float = 0.0
var _posed: bool = false

func _ready() -> void:
	_erupt = Vector3(0.0, planet_radius, 0.0)
	_build_world()
	_build_planet()
	_build_cast()
	_build_eruption()
	_apply(0.0)

func _build_world() -> void:
	var frame := Vector2i(get_viewport_rect().size)
	_world = SubViewport.new()
	_world.size = frame * supersample
	_world.own_world_3d = true
	_world.msaa_3d = Viewport.MSAA_4X
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_world)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)

	_camera = Camera3D.new()
	_camera.fov = camera_fov
	_camera.near = 0.05
	_camera.far = 2000.0
	_world.add_child(_camera)
	_camera.global_transform = Transform3D(
		Basis(Vector3.RIGHT, -deg_to_rad(camera_pitch)),
		_erupt + Vector3(0.0, camera_altitude, camera_back))

	_lens = Sprite2D.new()
	_lens.centered = false
	_lens.scale = Vector2.ONE / float(supersample)
	_lens.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var lens_mat := ShaderMaterial.new()
	lens_mat.shader = LENS_SHADER
	lens_mat.set_shader_parameter("strength", fisheye_strength)
	lens_mat.set_shader_parameter("zoom", lens_zoom)
	lens_mat.set_shader_parameter("vignette", vignette)
	_lens.material = lens_mat
	_lens.texture = _world.get_texture()
	add_child(_lens)

func _build_planet() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = planet_radius
	sphere.height = planet_radius * 2.0
	sphere.radial_segments = 192
	sphere.rings = 96
	_planet_mat = ShaderMaterial.new()
	_planet_mat.shader = PLANET_SHADER
	_planet_mat.set_shader_parameter("base_color", planet_color)
	_planet_mat.set_shader_parameter("band_color", planet_band)
	_planet_mat.set_shader_parameter("hot_color", planet_hot)
	_planet_mat.set_shader_parameter("erupt_point", _erupt)
	var planet := MeshInstance3D.new()
	planet.mesh = sphere
	planet.material_override = _planet_mat
	_world.add_child(planet)

	var shell := SphereMesh.new()
	shell.radius = planet_radius * 1.06
	shell.height = shell.radius * 2.0
	shell.radial_segments = 192
	shell.rings = 96
	var atmo_mat := ShaderMaterial.new()
	atmo_mat.shader = ATMOSPHERE_SHADER
	atmo_mat.set_shader_parameter("glow_color", atmosphere_color)
	var atmosphere := MeshInstance3D.new()
	atmosphere.mesh = shell
	atmosphere.material_override = atmo_mat
	_world.add_child(atmosphere)

func _build_cast() -> void:
	var blob_mat := ShaderMaterial.new()
	blob_mat.shader = BLOB_SHADER
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = GLOW_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var basis := _camera.global_basis
	var half := tan(deg_to_rad(camera_fov) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = eruption_seed
	for i in range(CAST.size()):
		var spec: Dictionary = CAST[i]
		var offset: Vector2 = spec.offset
		var depth: float = spec.depth
		var target: Vector3 = _camera.global_position - basis.z * depth \
			+ (basis.x * offset.x + basis.y * offset.y) * depth * half

		var body := MeshInstance3D.new()
		body.mesh = _shape_mesh(spec.shape)
		body.material_override = blob_mat
		body.set_instance_shader_parameter("tint", spec.color)
		body.set_instance_shader_parameter("seed", float(i) * 1.7)
		_world.add_child(body)
		if faces and spec.has("face"):
			_add_face(body, spec)

		var halo := MeshInstance3D.new()
		halo.mesh = quad
		halo.material_override = glow_mat
		halo.set_instance_shader_parameter("tint", spec.color)
		halo.set_instance_shader_parameter("strength", halo_strength)
		_world.add_child(halo)

		var debris: Array[Dictionary] = []
		for k in range(debris_per_body):
			var bit := MeshInstance3D.new()
			bit.mesh = body.mesh
			bit.material_override = blob_mat
			bit.set_instance_shader_parameter("tint", spec.color)
			bit.set_instance_shader_parameter("seed", rng.randf() * 10.0)
			_world.add_child(bit)
			debris.append({
				"node": bit,
				"along": rng.randf_range(0.08, 0.75),
				"jitter": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)),
				"scale": rng.randf_range(0.14, 0.3),
				"spin": rng.randf_range(-PI, PI),
			})

		_bodies.append({
			"spec": spec, "target": target, "body": body, "halo": halo, "debris": debris,
		})

func _build_eruption() -> void:
	_streaks = ImmediateMesh.new()
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = STREAK_SHADER
	var streaks := MeshInstance3D.new()
	streaks.mesh = _streaks
	_world.add_child(streaks)

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = GLOW_SHADER
	glow_mat.set_shader_parameter("falloff", 1.6)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = glow_mat
	_flash.set_instance_shader_parameter("tint", planet_hot)
	_world.add_child(_flash)
	_flash.global_position = _erupt + Vector3.UP * 0.5

	# A crown of tongues around the vent, in every direction across the surface
	# and leaning out from straight up, like a splash seen from above.
	var rng := RandomNumberGenerator.new()
	rng.seed = eruption_seed
	for i in range(spike_count):
		var az := TAU * float(i) / float(spike_count) + rng.randf_range(-0.12, 0.12)
		var tilt := rng.randf_range(deg_to_rad(20.0), deg_to_rad(70.0))
		_spikes.append({
			"dir": Vector3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az)),
			"length": spike_length * rng.randf_range(0.45, 1.0),
		})

## A quad just proud of the body's front, so it rides the body's transform --
## facing the lens, leaning and stretching with it. `face_offset` is in the
## body's own units, y up, for shapes whose centre is not where a face sits.
func _add_face(body: MeshInstance3D, spec: Dictionary) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * face_size * spec.get("face_size", 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = FACE_SHADER
	var expression: Dictionary = FACES[spec.face]
	for param in expression:
		mat.set_shader_parameter(param, expression[param])
	var face := MeshInstance3D.new()
	face.mesh = quad
	face.material_override = mat
	var offset: Vector2 = spec.get("face_offset", Vector2.ZERO)
	face.position = Vector3(offset.x, offset.y, MESH_DEPTH * 1.02)
	body.add_child(face)

## The shape's silhouette, inflated: every perimeter point of the 2D profile is
## swept round a half-ellipse front to back, so the outline seen face-on is the
## skin's exact one and the sides round off like a pillow. Indices wrap round
## the perimeter rather than duplicating a seam, so the normals are smooth all
## the way round.
func _shape_mesh(shape: PlasmaBlob.Shape) -> ArrayMesh:
	if _meshes.has(shape):
		return _meshes[shape]
	var profile := PackedFloat32Array()
	var peak := 0.0
	for i in range(MESH_SEGMENTS):
		var r := PlasmaBlob.shape_radius(TAU * float(i) / float(MESH_SEGMENTS), shape)
		profile.append(r)
		peak = maxf(peak, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(MESH_RINGS + 1):
		var phi := lerpf(-PI * 0.5, PI * 0.5, float(j) / float(MESH_RINGS))
		var ring := cos(phi)
		for i in range(MESH_SEGMENTS):
			var a := TAU * float(i) / float(MESH_SEGMENTS)
			var r := profile[i] / peak * ring
			# The profile is authored in 2D, y down; 3D is y up.
			st.add_vertex(Vector3(cos(a) * r, -sin(a) * r, sin(phi) * MESH_DEPTH))
	for j in range(MESH_RINGS):
		for i in range(MESH_SEGMENTS):
			var i2 := (i + 1) % MESH_SEGMENTS
			var a0 := j * MESH_SEGMENTS + i
			var b0 := j * MESH_SEGMENTS + i2
			var a1 := a0 + MESH_SEGMENTS
			var b1 := b0 + MESH_SEGMENTS
			for idx in [a0, a1, b0, b0, a1, b1]:
				st.add_index(idx)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[shape] = mesh
	return mesh

func _process(delta: float) -> void:
	_t = fmod(_t + delta, cycle_time)
	_apply(_t)
	if not _posed and _t >= pose_time:
		_posed = true
		pose_reached.emit()

func _first_launch() -> float:
	var first := INF
	for spec in CAST:
		first = minf(first, spec.launch)
	return first

func _apply(t: float) -> void:
	_streaks.clear_surfaces()
	var verts: Array[Dictionary] = []
	var cam := _camera.global_position
	var cam_up := _camera.global_basis.y

	for b in _bodies:
		var spec: Dictionary = b.spec
		var body: MeshInstance3D = b.body
		var halo: MeshInstance3D = b.halo
		var launch: float = spec.launch
		var k := (t - launch) / (pose_time - launch)
		var flying := k > 0.0
		body.visible = flying
		halo.visible = flying
		for d in b.debris:
			d.node.visible = flying
		if not flying:
			continue

		var target: Vector3 = b.target
		var head := _erupt.lerp(target, pow(k, ease_power))
		var dir := (target - _erupt).normalized()
		var size: float = spec.size

		# Face the lens, turned part way from upright towards the direction of
		# travel as it appears on screen.
		var z := (cam - head).normalized()
		var moving := dir - z * dir.dot(z)
		var up := cam_up
		if moving.length() > 0.05:
			up = cam_up.lerp(moving.normalized(), lean).normalized()
		var x := up.cross(z).normalized()
		var y := z.cross(x)
		body.global_transform = Transform3D(
			Basis(x * size / sqrt(stretch), y * size * stretch, z * size), head)
		halo.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size * halo_reach * 2.0), head)

		var color: Color = spec.color
		var length := head.distance_to(_erupt) * trail_reach
		var tail := head - dir * length
		var hot := color.lerp(Color.WHITE, 0.5)
		_strip(verts, head, tail, size * 0.8, 0.0, Color(color, 0.35), Color(color, 0.35))
		_strip(verts, head, head.lerp(tail, 0.6), size * 0.3, 0.0, Color(hot, 0.8), Color(hot, 0.8))

		for d in b.debris:
			var along: float = d.along
			var jitter: Vector2 = d.jitter
			var bit: MeshInstance3D = d.node
			var spread := size * (0.6 + along * 2.5)
			var pos := head - dir * length * along + (x * jitter.x + y * jitter.y) * spread
			var s: float = size * d.scale * (1.0 - along * 0.5)
			var bz := (cam - pos).normalized()
			var bx := up.cross(bz).normalized()
			var basis := Basis(bx, bz.cross(bx), bz).rotated(bz, d.spin)
			bit.global_transform = Transform3D(basis.scaled(Vector3.ONE * s), pos)

	var since := t - _first_launch()
	var env := 0.0
	if since > 0.0:
		env = clampf(since / 0.12, 0.0, 1.0) * exp(-since / eruption_decay)
	_flash.visible = env > 0.001
	_flash.scale = Vector3.ONE * flash_size * (0.6 + 0.4 * env)
	_flash.set_instance_shader_parameter("strength", flash_strength * env)
	_planet_mat.set_shader_parameter("shock_radius", maxf(since, 0.0) * shock_speed)
	_planet_mat.set_shader_parameter("shock_gain", env * 1.2)
	if env > 0.001:
		var grow := clampf(since / 0.35, 0.0, 1.0)
		var tongue := planet_hot.lerp(planet_color, 0.25)
		for s in _spikes:
			var reach: float = s.length * grow
			_strip(verts, _erupt, _erupt + s.dir * reach, spike_width, 0.0,
				Color(tongue, 0.8 * env), Color(tongue, 0.8 * env))

	if verts.is_empty():
		return
	_streaks.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _streak_mat)
	for v in verts:
		_streaks.surface_set_color(v.color)
		_streaks.surface_set_uv(v.uv)
		_streaks.surface_add_vertex(v.pos)
	_streaks.surface_end()

## A tapering ribbon from `from` to `to`, turned about its own axis to face the
## camera, appended to `verts` as triangles.
func _strip(verts: Array[Dictionary], from: Vector3, to: Vector3,
		w_from: float, w_to: float, c_from: Color, c_to: Color) -> void:
	var axis := to - from
	if axis.length() < 0.001:
		return
	axis = axis.normalized()
	var cam := _camera.global_position
	var prev: Array = []
	for k in range(TRAIL_STEPS + 1):
		var s := float(k) / float(TRAIL_STEPS)
		var p := from.lerp(to, s)
		var side := axis.cross((cam - p).normalized()).normalized() * lerpf(w_from, w_to, s)
		var c := c_from.lerp(c_to, s)
		var row := [
			{"pos": p - side, "color": c, "uv": Vector2(s, 0.0)},
			{"pos": p + side, "color": c, "uv": Vector2(s, 1.0)},
		]
		if not prev.is_empty():
			verts.append_array([prev[0], row[0], prev[1], prev[1], row[0], row[1]])
		prev = row
