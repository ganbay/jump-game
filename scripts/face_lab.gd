extends Node2D

## Tuning bench for BlobFace: every mood down the side, every face style
## across the top, and a last column at true in-game size in the classic
## style -- the one that decides whether an expression actually reads.
##
##   SPACE  cycle every face through the moods, to watch the blends
##   B      blink everything
##   ESC    quit
##
## `-- --shoot <path>` snaps every face to its row's mood, saves a PNG and
## quits, for comparing tweaks without playing:
##
##     godot --path . res://scenes/face_lab.tscn -- --shoot /tmp/faces.png

const CELL := 100.0
const LABEL_WIDTH := 110.0
const ZOOM := 1.7
const BACKGROUND := Color(0.043, 0.063, 0.133)

## Drawn into its own viewport at full size, shown scaled to fit the window --
## the grid is taller than most screens, and a window the OS clamps would crop
## the shot.
var _view: SubViewport
var _faces: Array[BlobFace] = []
var _rows: Array[StringName] = []
var _cycle: int = 0

func _ready() -> void:
	for m in BlobFace.MOODS:
		_rows.append(m)
	var styles := BlobFace.Style.size()
	var cols := styles + 1
	var size := Vector2i(int(LABEL_WIDTH + CELL * cols), int(CELL * _rows.size()))
	_view = SubViewport.new()
	_view.size = size
	_view.use_hdr_2d = true
	_view.transparent_bg = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.size = Vector2(size)
	_view.add_child(backdrop)
	var shown := TextureRect.new()
	shown.texture = _view.get_texture()
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.add_child(shown)
	add_child(layer)

	for row in range(_rows.size()):
		var label := Label.new()
		label.text = String(_rows[row])
		label.position = Vector2(12.0, CELL * row + CELL * 0.5 - 12.0)
		_view.add_child(label)
		for col in range(cols):
			var real_size := col == styles
			var blob := PlasmaBlob.new()
			blob.color = Settings.PLAYER_COLOR_DEFAULT
			blob.scale = Vector2.ONE * (1.0 if real_size else ZOOM)
			# Bottom-anchored, so the origin goes a radius below the cell centre.
			blob.position = Vector2(LABEL_WIDTH + CELL * (col + 0.5),
				CELL * (row + 0.5) + blob.radius * blob.scale.y)
			_view.add_child(blob)
			var face := BlobFace.new()
			face.style = BlobFace.Style.CLASSIC if real_size else col
			blob.add_child(face)
			# Above the glow like the game's, or the glow washes the faces
			# out and the bench judges something the player never sees.
			face.lift_above_glow(Player.FACE_LAYER)
			if real_size:
				face.feature_scale = Player.FACE_SCALE
			face.mood = _rows[row]
			face.snap()
			_faces.append(face)

	var args := OS.get_cmdline_user_args()
	var at := args.find("--shoot")
	if at != -1:
		var out := args[at + 1] if at + 1 < args.size() else "user://face_lab.png"
		_shoot(out)

func _shoot(path: String) -> void:
	for face in _faces:
		face.blinking = false
	# A few frames for the glow and the blobs' first draws to settle.
	for i in range(4):
		await RenderingServer.frame_post_draw
	var image := _view.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	print("Saved %s" % path)
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_cycle += 1
			for i in range(_faces.size()):
				var row := i / (BlobFace.Style.size() + 1)
				_faces[i].mood = _rows[(row + _cycle) % _rows.size()]
		KEY_B:
			for face in _faces:
				face._blink_wait = 0.0
		KEY_ESCAPE:
			get_tree().quit()
