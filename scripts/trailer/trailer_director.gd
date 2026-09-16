extends Node

## Renders the store trailer: a fixed running order of real game scenes,
## played by a bot, pushed past one another with a slide, and written out as a
## numbered PNG sequence at exactly 1080x1920. tools/render_trailer.sh drives
## it and hands the frames to ffmpeg.
##
## WHY IT RENDERS ITSELF INSTEAD OF USING MOVIE MAKER
##
## Godot's --write-movie captures the root viewport, which is the OS window, so
## a 1080x1920 capture needs a 1080x1920 window -- taller than the 1080px-high
## desktop this is authored on, and a window manager is free to clamp that.
## Capturing a SubViewport instead makes the output size a property of the
## scene rather than of whatever display happens to be attached, which is the
## same reason promo_shot.gd shoots a SubViewport for the store art.
##
## WHY IT IS STILL SHARP AT 1080p
##
## The game is authored against a 720x1280 canvas. `size_2d_override` on the
## stage's inner viewport is exactly the mechanism the project's `canvas_items`
## stretch uses: layout and gameplay stay in 720x1280 units while everything is
## rasterised at 1080x1920. Nothing is upscaled -- the text, the glow and the
## plasma shapes are all drawn at full output resolution.
##
## The compositor viewport above it deliberately has NO override, so one of its
## canvas units is one output pixel and the slide moves whole pixels.
##
## WHY ONE SEGMENT IS IN THE TREE AT A TIME
##
## The shot being slid away is a still image grabbed the frame before, not the
## live scene. That is not a shortcut -- it is a correctness requirement.
## main.tscn finds its cast through groups: the spawner takes the first node in
## "player", and the player scans every node in "platforms" each physics frame.
## Two live copies in the tree at once would cross-wire exactly those two
## lookups. Freezing the outgoing shot means only the incoming one is ever
## real, and a still sliding off the edge of frame over 0.4s is what a cut in a
## trailer looks like anyway.
##
## TIMING
##
## Run under --fixed-fps, so `delta` is a constant 1/FPS however long a frame
## actually takes to write to disk. Every duration here is therefore counted in
## frames, not seconds of wall clock, and the render is deterministic: the same
## seed produces the same trailer.

const OUTPUT_SIZE := Vector2i(1080, 1920)
## The canvas the game is authored against -- project.godot's
## display/window/size. Changing one without the other reframes every scene.
const GAME_SIZE := Vector2i(720, 1280)
const FPS := 60
## Long enough to read as a deliberate push, short enough that it is not the
## thing you remember about the trailer.
const SLIDE_TIME := 0.42

## Preloaded rather than referred to by class_name: these are internal to the
## render and are deliberately not registered as global classes, so there is no
## entry in the editor's script class cache for a headless run to resolve.
const Autopilot := preload("res://scripts/trailer/trailer_autopilot.gd")
const EndCard := preload("res://scripts/trailer/trailer_end_card.gd")

const GAME_SCENE := preload("res://scenes/main.tscn")
const SPLASH_SCENE := preload("res://scenes/splash.tscn")
const CUSTOMIZATION_SCENE := preload("res://scenes/customization.tscn")

## Fixed so a take that looks good can be rendered again. Passed on the command
## line by the render script as `-- --seed N`.
@export var random_seed: int = 20260916
@export var output_dir: String = "user://trailer_frames"

## The running order. `seconds` is how long the segment holds *after* it has
## finished sliding in; the slide itself is charged to neither side.
var _segments: Array[Dictionary] = [
	{"name": "splash", "seconds": 1.30, "build": "_build_splash"},
	{"name": "climb", "seconds": 3.00, "build": "_build_climb"},
	{"name": "drift", "seconds": 3.00, "build": "_build_drift"},
	{"name": "glass", "seconds": 3.00, "build": "_build_glass"},
	{"name": "phantom", "seconds": 3.00, "build": "_build_phantom"},
	{"name": "squish", "seconds": 3.00, "build": "_build_squish"},
	{"name": "custom", "seconds": 6.00, "build": "_build_customization"},
	{"name": "end", "seconds": 2.80, "build": "_build_end_card"},
]

## Composited output, and what gets written to disk.
var _stage: SubViewport
## The live segment, rasterised at OUTPUT_SIZE against a GAME_SIZE canvas.
var _game_vp: SubViewport
var _live: SubViewportContainer
## The outgoing shot, frozen, during a slide.
var _snapshot: TextureRect

var _current: Node = null
var _pilot: Autopilot = null
## Called after the incoming segment has been added to the tree, for setup that
## can only happen once the scene's own _ready has run.
var _pending_setup: Callable = Callable()
## Called once per rendered frame of the segment, with the segment-local frame
## index. This is where a segment's internal beats live.
var _tick: Callable = Callable()
var _segment_frame: int = 0
var _frame: int = 0
## The config of the gameplay segment on screen, so the shared per-frame beats
## in _tick_gameplay can read it without every builder binding its own closure.
var _config: Dictionary = {}
## Latched once a gameplay segment has visibly gone wrong, so the warning is
## said once rather than on every one of the remaining frames.
var _take_lost: bool = false

func _ready() -> void:
	# game.gd pauses the tree for its own modals, and a paused tree stops every
	# tween in every scene -- including the ones a segment is made of. The
	# render loop has to keep counting frames through anything like that, or a
	# single popup silently freezes the rest of the trailer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_read_cmdline()
	seed(random_seed)
	_build_stage()
	_prepare_globals()
	_render()

## `-- --seed 123` after the scene, per Godot's user-argument separator.
func _read_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--seed":
			random_seed = int(args[i + 1])
		elif args[i] == "--out":
			output_dir = args[i + 1]

func _build_stage() -> void:
	_stage = SubViewport.new()
	_stage.size = OUTPUT_SIZE
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stage.disable_3d = true
	# The compositor only ever draws two already-tonemapped textures, so it has
	# no glow of its own to run and nothing above 1.0 to preserve.
	_stage.use_hdr_2d = false
	_stage.transparent_bg = false
	add_child(_stage)

	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_right = 0.0
	frame.offset_bottom = 0.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	# Explicit, rather than waiting on the anchors above to be resolved by the
	# first layout pass -- the two children are positioned against this box on
	# the very first frame.
	frame.position = Vector2.ZERO
	frame.size = Vector2(OUTPUT_SIZE)
	_stage.add_child(frame)

	_live = SubViewportContainer.new()
	# False, so the container does not resize the viewport down to its own box:
	# the viewport is authored at OUTPUT_SIZE and drawn 1:1 into a compositor
	# whose units are output pixels.
	_live.stretch = false
	_live.size = Vector2(OUTPUT_SIZE)
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_live)

	_game_vp = SubViewport.new()
	_game_vp.size = OUTPUT_SIZE
	_game_vp.size_2d_override = GAME_SIZE
	_game_vp.size_2d_override_stretch = true
	_game_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_game_vp.disable_3d = true
	# The game's palette is authored HDR -- channels up to 2.4 -- and the
	# WorldEnvironment in each scene glows everything past 1.0. Without this the
	# bloom that the whole look rests on simply does not happen.
	_game_vp.use_hdr_2d = true
	_game_vp.msaa_2d = Viewport.MSAA_2X
	# Its own canvas and physics space, so nothing it holds can reach the
	# compositor above it.
	_game_vp.world_2d = World2D.new()
	_live.add_child(_game_vp)

	_snapshot = TextureRect.new()
	_snapshot.size = Vector2(OUTPUT_SIZE)
	_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snapshot.visible = false
	frame.add_child(_snapshot)

	_build_preview()

## A fit-to-window view of the stage, purely so the render can be watched. It
## is in the OS window, not in the stage, so it is never part of the output.
func _build_preview() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var preview := TextureRect.new()
	preview.texture = _stage.get_texture()
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.anchor_right = 1.0
	preview.anchor_bottom = 1.0
	preview.offset_right = 0.0
	preview.offset_bottom = 0.0
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(preview)

func _prepare_globals() -> void:
	# Keyboard steering only (see trailer_autopilot.gd). Under TILT the player
	# reads a desktop accelerometer that reports nothing and the bot's key
	# presses would be the only thing moving it anyway -- but the deadzone
	# branch would fight them on every frame a key is released.
	Settings.control_scheme = Settings.ControlScheme.TOUCH
	Settings.trail_enabled = true
	Settings.background_particles = true
	# No audio is captured, so this is only to keep the render from making
	# noise for several minutes. Muting the bus rather than Settings.sound_muted
	# because the setter writes user://settings.cfg.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	# Every character has to be showable on the customization screen, and the
	# real gates (rate the game, escape solar gravity, watch ads) are not things
	# a render can satisfy. Written straight into the dictionary: Unlocks' own
	# entry points save to disk.
	for skin in range(Player.SkinType.size()):
		Unlocks._owned[Unlocks.skin_id(skin)] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	print_rich("[b]trailer[/b] %dx%d @ %d fps  seed %d" % [
		OUTPUT_SIZE.x, OUTPUT_SIZE.y, FPS, random_seed])
	print("frames -> %s" % ProjectSettings.globalize_path(output_dir))

# --- the render loop ---------------------------------------------------------

func _render() -> void:
	var first := true
	for segment in _segments:
		var node: Node = call(segment["build"])
		_segment_frame = 0
		if first:
			first = false
			_swap_in(node)
			await get_tree().process_frame
		else:
			await _slide_to(node)
		await _hold(_frames(segment["seconds"]))
		_verify_death(segment)
		print("  %-8s %5.2fs  -> frame %d" % [segment["name"], segment["seconds"], _frame])
	_finish()

func _frames(seconds: float) -> int:
	return int(round(seconds * FPS))

## Takes the old segment out of the tree before the new one goes in, so the
## groups main.tscn resolves its cast through only ever contain one cast.
func _swap_in(node: Node) -> void:
	if _pilot != null and is_instance_valid(_pilot):
		_pilot.release()
	_pilot = null
	if _current != null and is_instance_valid(_current):
		_game_vp.remove_child(_current)
		_current.queue_free()
	_current = node
	_take_lost = false
	# Nothing may carry a pause across a cut. Each segment is a fresh scene and
	# starts running.
	get_tree().paused = false
	_game_vp.add_child(node)
	if _pending_setup.is_valid():
		var setup := _pending_setup
		_pending_setup = Callable()
		setup.call()

func _slide_to(node: Node) -> void:
	# The last frame of the outgoing shot, frozen. Grabbed before the swap,
	# because after it that scene no longer exists.
	await RenderingServer.frame_post_draw
	var image := _game_vp.get_texture().get_image()
	_snapshot.texture = ImageTexture.create_from_image(image)
	_snapshot.position = Vector2.ZERO
	_snapshot.visible = true

	_swap_in(node)
	_live.position.x = float(OUTPUT_SIZE.x)
	# One uncaptured frame for the incoming scene to build itself, so the slide
	# does not start on a half-drawn first frame.
	await get_tree().process_frame

	var total := _frames(SLIDE_TIME)
	for i in range(total):
		var t := _ease_out(float(i + 1) / float(total))
		_live.position.x = float(OUTPUT_SIZE.x) * (1.0 - t)
		_snapshot.position.x = -float(OUTPUT_SIZE.x) * t
		await _step_frame()
	_live.position.x = 0.0
	_snapshot.visible = false
	_snapshot.texture = null

func _hold(count: int) -> void:
	for i in range(count):
		await _step_frame()

## One rendered, captured frame. The segment's beat runs first so anything it
## changes is visible in the frame that is about to be drawn.
func _step_frame() -> void:
	if _tick.is_valid():
		_tick.call(_segment_frame)
	_watch_take()
	_segment_frame += 1
	await RenderingServer.frame_post_draw
	var image := _stage.get_texture().get_image()
	# Rendered without alpha and written as a video; an alpha channel here
	# would only be a fully-opaque third of the file size.
	image.convert(Image.FORMAT_RGB8)
	var error := image.save_png("%s/f_%05d.png" % [output_dir, _frame])
	if error != OK:
		push_error("trailer: frame %d failed to write (%d)" % [_frame, error])
	_frame += 1

## A take where the bot misses is a take to throw away, not one to ship. Deaths
## are switched off for the render, and the spawner despawns everything that
## falls below the camera -- so a character that drops out of the platform
## field keeps falling, and every remaining frame of that segment is empty sky
## with a frozen score. Nobody watches a five-minute render happen, so this is
## the thing that says so.
func _watch_take() -> void:
	if _take_lost or _pilot == null or not is_instance_valid(_pilot):
		return
	# One segment is supposed to end down here. Falling out of the platform
	# field is the point of it, not a lost take.
	if _config.get("die_at", -1.0) >= 0.0:
		return
	if _current == null or not is_instance_valid(_current):
		return
	var player: Node2D = _current.player
	var camera: Camera2D = _current.camera
	# Most of a screen below the camera, which it cannot climb back from: the
	# camera only ever rises, so nothing down here is ever framed again.
	if player.global_position.y <= camera.global_position.y + 900.0:
		return
	_take_lost = true
	printerr("trailer: LOST TAKE at frame %d -- the character fell out of the "
		% _frame + "platform field. Re-render with a different seed.")

## The mirror of _watch_take, for the one segment whose take is lost by *not*
## dying: the bot threads a gap by aiming at one, and a gap it fails to find
## leaves the segment as another clean climb with no GAME OVER at the end of it.
func _verify_death(segment: Dictionary) -> void:
	if _config.get("die_at", -1.0) < 0.0:
		return
	if _current == null or not is_instance_valid(_current):
		return
	if _current.is_game_over:
		return
	printerr("trailer: the %s segment was meant to end in a death and did not. "
		% segment["name"] + "Re-render with a different seed.")

func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

## Takes the last segment down by hand before quitting. Leaving a whole game
## scene -- with its own World2D, its physics space and its autoload
## connections -- standing inside a SubViewport for the engine to unwind at
## exit has been seen to abort the process during shutdown, long after every
## frame is safely on disk. The render script judges the run by this line and
## by the frames on disk rather than by the exit code for the same reason, but
## there is no need to hand it a crash to forgive in the first place.
func _finish() -> void:
	if _pilot != null and is_instance_valid(_pilot):
		_pilot.release()
	_pilot = null
	if _current != null and is_instance_valid(_current):
		_game_vp.remove_child(_current)
		_current.free()
		_current = null
	print("done: %d frames = %.2fs" % [_frame, float(_frame) / float(FPS)])
	print(ProjectSettings.globalize_path(output_dir))
	get_tree().quit()

# --- segments ----------------------------------------------------------------

## The publisher card, cut well before it would put itself away.
##
## splash.gd schedules a scene change at its DURATION of 2.0s, which would tear
## down the whole render. Nothing here disarms it: the segment is shorter than
## that, and the card is freed on the swap, which kills the tween holding the
## callback with it. Keep this segment under 2.0s.
func _build_splash() -> Node:
	_config = {}
	_tick = Callable()
	return SPLASH_SCENE.instantiate()

## The five gameplay showcases, one screen-look each. Colours come off the same
## curated neon gradient the in-game picker offers (see
## color_spectrum_slider.gd), so every segment is a set of choices a player
## could actually make rather than a palette invented for the trailer. All are
## authored above 1.0 on at least one channel, which is what puts them over the
## scene's HDR glow threshold and makes them bloom.
const CYAN := Color(0.3, 1.8, 2.4)
const BLUE := Color(0.4, 1.0, 2.4)
const MAGENTA := Color(2.2, 0.4, 1.8)
const RED := Color(2.2, 0.4, 0.4)
const ORANGE := Color(2.4, 1.4, 0.3)
const GREEN := Color(0.6, 2.2, 0.5)
const WHITE := Color(2.2, 2.2, 2.2)
const VIOLET := Color(1.2, 0.6, 2.4)

## How long a zone's name holds before it fades. Each zone now has a segment to
## itself rather than sharing one with three others, so the banner can sit at
## something close to the game's own ZONE_BANNER_HOLD and actually be read.
const ZONE_BANNER_AT := 0.18
const ZONE_BANNER_HOLD := 1.25

## Score per second of play. Measured off these segments rather than guessed:
## the climb and drift showcases both move about 47 points a second. Used to
## back-date the run clock of a segment that opens mid-run, so the pace on the
## game-over panel agrees with the climbing the viewer just watched.
const TRAILER_PACE := 47.0

## The game's own look: the default character in the default colours, on plain
## platforms with no zone attribute at all. Opens the gameplay block because it
## is the thing the other four are variations on.
func _build_climb() -> Node:
	return _build_gameplay({
		"skin": Player.SkinType.PLASMA,
		"color": Settings.PLAYER_COLOR_DEFAULT,
		"platform_color": Settings.PLATFORM_COLOR_DEFAULT,
		"particle_color": Settings.PARTICLE_COLOR_DEFAULT,
		"zone": -1,
		"perfect_cycle": PackedInt32Array([0, 1, 0, 0]),
		# Hands over at an ordinary hop rather than the intro's 2600px/s cruise,
		# so the first landing comes about a second in instead of three.
		"launch_velocity": -950.0,
		"streak": 0,
		"score": 0,
		"climbed": 0.0,
		"min_gap": 100.0,
		"max_gap": 150.0,
		"platform_width": 100.0,
	})

## DRIFT: every platform slides. Kept on plain jumps so the arcs stay short and
## several platforms are crossed inside three seconds -- the zone only reads if
## you see more than one of them moving.
func _build_drift() -> Node:
	return _build_gameplay({
		"skin": Player.SkinType.PRISM,
		"color": CYAN,
		"platform_color": BLUE,
		"particle_color": CYAN,
		"zone": ZoneDirector.Zone.MOVING,
		"perfect_cycle": PackedInt32Array([1, 0, 0]),
		"launch_velocity": -950.0,
		"streak": 0,
		"score": 2140,
		"climbed": 4200.0,
		"min_gap": 100.0,
		"max_gap": 150.0,
		"platform_width": 100.0,
	})

## GLASS: a platform shatters as it is left. Every landing breaks one, timed or
## not (platform.gd:on_landed), so this is on plain jumps too -- low arcs, more
## landings, more glass.
func _build_glass() -> Node:
	return _build_gameplay({
		"skin": Player.SkinType.DIAMOND,
		"color": MAGENTA,
		"platform_color": WHITE,
		"particle_color": MAGENTA,
		"zone": ZoneDirector.Zone.GLASS,
		"perfect_cycle": PackedInt32Array([0, 0, 1]),
		"launch_velocity": -950.0,
		"streak": 0,
		"score": 6320,
		"climbed": 13000.0,
		"min_gap": 100.0,
		"max_gap": 150.0,
		"platform_width": 100.0,
	})

## PHANTOM: the platforms are not drawn, so the character bounces off nothing.
## This is also the Solar Wind segment, and the two suit each other -- there is
## no platform art to lose when the burst throws the character off the top of
## the frame at 5200px/s.
##
## The streak opens one short of SOLAR_WIND_STREAK_STEP so the segment's *first*
## landing is the milestone, rather than spending three seconds climbing to it.
func _build_phantom() -> Node:
	return _build_gameplay({
		"skin": Player.SkinType.STAR,
		"color": ORANGE,
		"platform_color": ORANGE,
		"particle_color": RED,
		"zone": ZoneDirector.Zone.INVISIBLE,
		"perfect_cycle": PackedInt32Array([1]),
		# Low, so that first landing arrives about a second in.
		"launch_velocity": -1100.0,
		"streak": 9,
		"score": 24860,
		"climbed": 52000.0,
		"min_gap": 110.0,
		"max_gap": 165.0,
		"platform_width": 96.0,
	})

## SQUISH: platforms give under the character and throw it back harder on a
## timed landing. Also the segment that ends in a death -- see `die_at` and
## trailer_autopilot.gd's miss mode. Put last of the five so the gameplay block
## closes on the stakes rather than on another clean climb.
##
## `die_at` is just after the first landing, because the fall itself is the slow
## part: the character has to drop a full ~720px below the camera before the run
## registers as over, which is about a second on its own.
func _build_squish() -> Node:
	return _build_gameplay({
		"skin": Player.SkinType.HEART,
		"color": GREEN,
		"platform_color": MAGENTA,
		"particle_color": BLUE,
		"zone": ZoneDirector.Zone.SQUISHY,
		# Timed, so the landing that is shown gets SQUISH_BOOST rather than the
		# halved bounce a mistimed one earns -- the death should read as a
		# missed platform, not as a bounce that failed.
		"perfect_cycle": PackedInt32Array([1]),
		"launch_velocity": -950.0,
		"streak": 0,
		"score": 11470,
		"climbed": 24000.0,
		"min_gap": 100.0,
		"max_gap": 150.0,
		"platform_width": 100.0,
		"die_at": 1.05,
	})

## Per-frame beats shared by all five: the zone announcement, and the moment the
## bot is told to stop trying.
func _tick_gameplay(frame: int) -> void:
	if _current == null or not is_instance_valid(_current):
		return
	var zone: int = _config.get("zone", -1)
	if zone >= 0 and frame == _frames(ZONE_BANNER_AT):
		_flash_zone_banner(_current,
			"%s ZONE" % ZoneDirector.ZONE_NAMES[zone], ZONE_BANNER_HOLD)
	var die_at: float = _config.get("die_at", -1.0)
	if die_at >= 0.0 and frame == _frames(die_at) \
			and _pilot != null and is_instance_valid(_pilot):
		_pilot.miss_mode = true

## The character picker, stepped through the shape roster and then swept across
## the colour spectrum. Driven by calling the screen's own handlers rather than
## by synthesising drags: _step() is what a swipe resolves to anyway, and a
## synthetic drag would only add a chance of landing between characters.
const CUSTOM_FIRST_SKIN := Player.SkinType.DIAMOND
## Four steps, which walks DIAMOND -> STAR -> HEART -> FLAME -> SPARKLE and
## stops on the last character in the roster. A fifth would wrap the picker
## back around to PLASMA, which is where the trailer's first segment already
## started -- the beat would end by showing the character it opened on.
const CUSTOM_STEP_AT := [0.35, 0.95, 1.55, 2.15]
const CUSTOM_SWEEP_FROM := 3.15
const CUSTOM_SWEEP_TO := 5.55

func _build_customization() -> Node:
	# All read by the screen's _ready. The colours are put back to their
	# defaults first because the gameplay segment before this one dressed the
	# character in its own colour without moving the slider that reports it --
	# the picker would otherwise open with its handles disagreeing with what is
	# on screen, and the sweep below would jump on its first frame.
	Settings.player_skin = CUSTOM_FIRST_SKIN
	Settings.player_color = Settings.PLAYER_COLOR_DEFAULT
	Settings.player_color_slider = Settings.PLAYER_COLOR_SLIDER_DEFAULT
	Settings.platform_color = Settings.PLATFORM_COLOR_DEFAULT
	Settings.platform_color_slider = Settings.PLATFORM_COLOR_SLIDER_DEFAULT
	_config = {}
	var node := CUSTOMIZATION_SCENE.instantiate()
	_tick = _tick_customization
	return node

func _tick_customization(frame: int) -> void:
	if _current == null or not is_instance_valid(_current):
		return
	for at in CUSTOM_STEP_AT:
		if frame == _frames(at):
			_current._step(1)
	var first := _frames(CUSTOM_SWEEP_FROM)
	var last := _frames(CUSTOM_SWEEP_TO)
	if frame >= first and frame <= last:
		var t := float(frame - first) / float(maxi(last - first, 1))
		_sweep_colors(_current, t)

## Both sliders at once, from opposite ends, so the character and the platform
## swatch move apart rather than through the same hues together.
##
## Written into Settings directly and announced with one signal, which is what
## the setters do either side of a ConfigFile save -- and a save per frame for
## 150 frames is 150 writes of the player's real settings file.
func _sweep_colors(screen: Node, t: float) -> void:
	var eased := t * t * (3.0 - 2.0 * t)
	var player_slider: ColorSpectrumSlider = screen.player_slider
	var platform_slider: ColorSpectrumSlider = screen.platform_slider
	var player_t := lerpf(Settings.PLAYER_COLOR_SLIDER_DEFAULT, 0.86, eased)
	var platform_t := lerpf(Settings.PLATFORM_COLOR_SLIDER_DEFAULT, 0.30, eased)
	player_slider.value = player_t
	platform_slider.value = platform_t
	Settings.player_color = player_slider.sample(player_t)
	Settings.player_color_slider = player_t
	Settings.platform_color = platform_slider.sample(platform_t)
	Settings.platform_color_slider = platform_t
	Settings.visual_settings_changed.emit()

func _build_end_card() -> Node:
	_config = {}
	_tick = Callable()
	return EndCard.new()

# --- gameplay setup ----------------------------------------------------------

func _build_gameplay(config: Dictionary) -> Node:
	# The whole screen-look of a segment, and all of it is read by the scene's
	# own _ready -- so it has to be in place before the scene is instantiated,
	# not after it is in the tree. Assigned into Settings rather than set
	# through its setters, every one of which saves the player's real config
	# file to disk.
	_config = config
	Settings.player_skin = config["skin"]
	Settings.player_color = config["color"]
	Settings.platform_color = config["platform_color"]
	Settings.background_particle_color = config["particle_color"]
	_tick = _tick_gameplay
	var game := GAME_SCENE.instantiate()
	_pending_setup = _setup_gameplay.bind(game, config)
	return game

## Runs the moment the scene is in the tree, i.e. after game.gd's _ready has
## already started the intro cinematic.
##
## The intro is skipped rather than played: it is a beautiful 4.5s of a plasma
## star erupting, and 4.5s is most of a trailer segment. _finish() is the same
## end state intro.skip() animates toward -- camera at 1:1, character handed
## over mid-flight -- reached in one frame instead of over a tween, so the
## segment opens on gameplay rather than on a fast zoom that reads as a glitch.
##
## The run's own state is configured on `finished`, not here: game.gd connects
## that signal first, so by the time this fires _on_intro_finished() has
## already seeded the spawner and the score origin, and this is overwriting a
## started run rather than racing it.
func _setup_gameplay(game: Node, config: Dictionary) -> void:
	game.intro.finished.connect(_on_run_started.bind(game, config), CONNECT_ONE_SHOT)
	game.intro._finish()

func _on_run_started(game: Node, config: Dictionary) -> void:
	var player: Player = game.player
	var spawner: Node2D = game.spawner

	# A take in which the bot misses is a take thrown away, so the platform
	# field is kept a little kinder than the one a real run at this height
	# would roll -- closer together, wider, and further from the screen edges.
	# The caps are pinned too, or the spawner's difficulty ramp would widen the
	# gaps back out underneath the bot as the segment climbs.
	spawner.min_gap = config["min_gap"]
	spawner.max_gap = config["max_gap"]
	spawner.min_gap_cap = config["min_gap"]
	spawner.max_gap_cap = config["max_gap"]
	spawner.platform_width = config["platform_width"]
	spawner.platform_width_min = config["platform_width"]
	spawner.edge_margin = 110.0

	if config.get("die_at", -1.0) >= 0.0:
		# This is the segment that ends in a death, so the death margin is left
		# exactly as the scene computed it -- the character dies where a
		# player's would, a bit under a screen below the camera. What must not
		# happen is the *revive* offer: it pauses the tree and puts a Watch Ad
		# button on screen, and a trailer asking for an ad is a trailer nobody
		# finishes. Claiming the revive is already spent sends game.gd straight
		# down its _finish_game_over() path instead.
		game._revive_used = true
	else:
		# Every other run in the trailer is meant to survive its three seconds.
		# The character never falls this far; this is only here so that a bad
		# take produces visibly bad footage to re-seed from, rather than a GAME
		# OVER panel spliced into the middle of the video.
		game._death_margin = 1.0e9

	player.velocity.y = config["launch_velocity"]
	player.streak = config["streak"]
	game._last_streak = config["streak"]
	game.run_max_streak = config["streak"]
	Audio.set_streak(config["streak"])

	# _on_intro_finished() placed the first platform for the intro's 2600px/s
	# handoff, which is far out of reach of the hop substituted above, so the
	# field is thrown away and re-seeded against the velocity the run actually
	# starts with.
	for platform in spawner._live:
		if is_instance_valid(platform):
			platform.queue_free()
	spawner._live.clear()
	spawner.begin(player.global_position.y - _seed_lead(game, player, spawner))

	# Where the HUD counts from. Offsetting the origin by the score to open on
	# is the whole of "start deep in a run": the number on screen, the zone the
	# spawner thinks it is building, and the height the run is scored against
	# all come off this one value.
	game._burst_climbing = false
	game._score_origin_y = game.camera.global_position.y + float(config["score"]) * 10.0
	game.max_height = float(config["score"]) * 10.0
	spawner.score_origin_y = game._score_origin_y
	# The clock has to be moved with the score, not left at zero. game.gd's
	# game-over panel prints score over elapsed time as a pace, so a five-figure
	# score on a run half a second old reads "SPEED 19842/s" -- an absurdity, in
	# a store trailer, on the one panel a viewer actually stops to read. Divided
	# by the rate the trailer's own segments are observed to climb at, so the
	# number the panel prints is the number the footage around it supports.
	game.run_time = float(config["score"]) / TRAILER_PACE
	# Difficulty and attribute variety are measured from where the run began,
	# not from world zero -- so a segment meant to look like a deep run has to
	# claim to have started a long way below. Set after begin(), which seeds
	# this to the frontier.
	spawner._origin_y = spawner._highest_y + float(config["climbed"])

	# A run that opens deep enough to have escaped Solar gravity trips that
	# milestone on its first scored frame, and the milestone is a full-screen
	# panel that pauses the tree until someone presses a button. There is
	# nobody to press it. More generally: a trailer never shows a modal, so the
	# announcement is cut off at the source rather than hidden after the fact.
	game.zones.milestone_reached.disconnect(game._on_milestone_reached)

	var zone: int = config.get("zone", -1)
	if zone >= 0:
		# The segment announces its own zone once, at its own moment (see
		# _tick_gameplay), so the score crossing a stage boundary must stop
		# announcing them too -- otherwise a second, unrelated zone name
		# appears over a segment already labelled.
		game.zones.zone_changed.disconnect(game._on_zone_changed)
		_force_zone(game, zone)

	var pilot := Autopilot.new()
	pilot.perfect_cycle = config["perfect_cycle"]
	game.add_child(pilot)
	pilot.begin(player)
	_pilot = pilot

## How far above the character to seed the platform frontier, so that the first
## platform built lands inside the first jump's apex.
##
## game.gd seeds this as a fraction of the jump's reach and gets away with it
## because the intro hands the run over at 2600px/s: reach is over 2000px there
## and the gap the spawner adds below the frontier is a rounding error against
## it. These segments hand over at an ordinary hop instead, where reach is a
## couple of hundred pixels and that same gap is most of it -- seeded the same
## way, the first platform is placed *above* the apex and the run opens by
## falling out of the world. So the gap is subtracted explicitly rather than
## assumed away, and it is the largest gap the spawner could roll, not the
## average: one unreachable platform ends the take.
func _seed_lead(game: Node, player: Player, spawner: Node2D) -> float:
	var reach: float = (player.velocity.y * player.velocity.y) / (2.0 * player.gravity)
	return maxf(reach * game.intro_platform_lead - spawner.max_gap, 0.0)

## Pins every stage of the run to one zone, so whatever the score does the
## platforms being built carry this zone's attribute. Rewriting the whole table
## rather than the current entry means a stage boundary crossed mid-segment
## cannot quietly hand the spawner a different zone than the banner just
## announced.
func _force_zone(game: Node, zone: int) -> void:
	var mask := 1 << zone
	var stages: Array[int] = game.zones._stages
	for i in range(stages.size()):
		stages[i] = mask

## game.gd's own banner animation at a shorter hold. Duplicated rather than
## called because ZONE_BANNER_HOLD is a const tuned for a real run, where a
## zone lasts 2000 score -- the trailer shows four of them in six seconds.
func _flash_zone_banner(game: Node, text: String, hold: float) -> void:
	var banner: Label = game.zone_banner
	banner.text = text
	banner.modulate.a = 0.0
	banner.pivot_offset = banner.size / 2.0
	banner.scale = Vector2(0.8, 0.8)
	banner.show()
	# Owned by the game scene, so it dies with the segment on the swap instead
	# of outliving it and writing to a freed label.
	var tween := game.create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.22)
	tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.40) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(banner, "modulate:a", 0.0, 0.30)
	tween.tween_callback(banner.hide)
