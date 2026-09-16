extends Node

## Shared harness for the Play Store art. Run the scene, look at the preview,
## press S. Used by scenes/feature_graphic.tscn (1024x500) and
## scenes/icon_screenshot.tscn (512x512); the composition hanging under the
## SubViewport is what differs between them, not this.
##
## Shooting a SubViewport rather than the window is the whole point: an OS
## screenshot of a game window depends on window borders, desktop scaling and a
## manual crop, and any of the three silently costs you the exact pixel size
## Play requires. What get_image() returns here is whatever the SubViewport is
## authored at, by construction, however the window is behaving.
##
## The window is resized to match and its content scaling turned off, so the
## preview is the output at 1:1 rather than the project's portrait stretch
## letterboxing it.

## Emitted by the composition when it reaches the frame worth shooting.
## Optional -- a composition that holds still has nothing to announce, and the
## harness just leaves it running.
const POSE_SIGNAL := &"pose_reached"

## Where the PNG lands. Kept in a folder with a .gdignore beside it so Godot
## does not import the export as a game texture and leave a .import file next
## to it on every save.
@export_file("*.png") var output_path: String = "res://promo/feature_graphic.png"

## Play wants the icon as a 32-bit PNG and the feature graphic with no alpha at
## all, so the channel count is per-scene. Either way the composition is opaque;
## this only decides whether a fully-opaque alpha channel is written out.
@export var include_alpha: bool = false

const HINT_HEIGHT := 60
const HINT_TEXT := "SPACE play/pause    → step one frame    S save PNG    ESC quit"

## Freeze on the composition's pose_time as soon as it is reached, instead of
## leaving the loop running and making you catch a frame by hand.
@export var auto_pause: bool = true
## Also write the PNG at that moment. Off by default -- the point of the
## preview is to look before something gets written.
@export var auto_save: bool = false

## Passed as `-- --shoot` on the command line: take the shot as soon as the
## composition reaches its pose, then quit. Turns the harness into a one-liner
## for re-exporting the art after a tweak, without giving up the look-first
## default for the interactive case.
##
## Shoot with --fixed-fps 60, always:
##
##     godot --path . --fixed-fps 60 res://scenes/icon_screenshot.tscn -- --shoot
##
## A composition poses on the first frame where its accumulated time passes
## `pose_time`, and that time accumulates real frame deltas. Free-running, a
## slow startup frame steps clean over the mark and the shot is taken somewhere
## past it -- which is not a rounding error, because the eruption is most of the
## way through its fade by then and its strength falls off a cliff. Two
## successive free-run exports of the same unchanged scene have come out with
## visibly different bursts, one of them nearly gone. --fixed-fps pins the delta
## so the pose lands on the same frame every time.
const SHOOT_ARG := "--shoot"
## `-- --out <path>` overrides where the PNG lands, so variants of one
## composition can be shot to different files without editing the scene.
const OUT_ARG := "--out"

var _quit_after_save: bool = false

@onready var _viewport: SubViewport = $SubViewport
@onready var _composition: Node2D = $SubViewport/Composition
@onready var _preview: TextureRect = $PreviewLayer/Preview
@onready var _hint: Label = $PreviewLayer/Hint

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if SHOOT_ARG in args:
		auto_save = true
		_quit_after_save = true
	var out_at := args.find(OUT_ARG)
	if out_at != -1 and out_at + 1 < args.size():
		output_path = args[out_at + 1]
	_preview.texture = _viewport.get_texture()
	_hint.text = HINT_TEXT
	_size_window()
	if _composition.has_signal(POSE_SIGNAL):
		_composition.connect(POSE_SIGNAL, _on_pose_reached)

## The project runs portrait with canvas_items stretching everything against a
## 720x1280 base. Left alone, that scales the preview to about a third and
## letterboxes it -- disabling content scaling makes one window pixel one
## output pixel again.
## Laid out from the SubViewport rather than authored per scene, so a
## composition at a different size needs no matching edit here or in its scene.
func _size_window() -> void:
	var frame := Vector2(_viewport.size)
	_preview.size = frame
	_hint.position = Vector2(16.0, frame.y)
	_hint.size = Vector2(frame.x - 32.0, HINT_HEIGHT)
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.size = _viewport.size + Vector2i(0, HINT_HEIGHT)
	window.move_to_center()
	print_rich("[b]%s[/b]  %dx%d" % [output_path.get_file(), _viewport.size.x, _viewport.size.y])
	print(HINT_TEXT)

func _on_pose_reached() -> void:
	if auto_save:
		save_png()
	if auto_pause:
		_set_paused(true)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_set_paused(not get_tree().paused)
		KEY_S:
			save_png()
		KEY_RIGHT:
			_step()
		KEY_ESCAPE:
			get_tree().quit()

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	_hint.modulate.a = 1.0 if value else 0.45

## Nudging a paused composition forward. Only forwards, and only a whole frame
## at a time: the trail and the squash spring are integrated by _process rather
## than sampled from a clock, so a frame can only be reached by actually running
## one -- there is no time to seek to, and nothing here runs backwards. To get
## behind the current frame, play the loop round again.
func _step() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().paused = true

func save_png() -> void:
	# The SubViewport texture is only valid to read after the frame it belongs
	# to has actually been drawn.
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	# Rendered in HDR, so this is a half-float image with values well past 1.0 on
	# everything that glows. Converting clips them to white -- which is what the
	# glow pass has already spread into the pixels around them.
	image.convert(Image.FORMAT_RGBA8 if include_alpha else Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Promo shot: save failed (%d) -> %s" % [error, output_path])
		return
	print("Saved %dx%d -> %s" % [
		image.get_width(), image.get_height(),
		ProjectSettings.globalize_path(output_path)])
	if _quit_after_save:
		get_tree().quit()
