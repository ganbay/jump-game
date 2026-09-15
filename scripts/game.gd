extends Node2D

## The pause and game over panels are unlabelled glyphs, so the two toggles in
## them swap their icon to show state -- there is no text left to rewrite.
const CONTROLS_TOUCH_ICON := preload("res://assets/icons/hand.svg")
const CONTROLS_TILT_ICON := preload("res://assets/icons/mobile_phone.svg")
const SOUND_ON_ICON := preload("res://assets/icons/speaker.svg")
const SOUND_OFF_ICON := preload("res://assets/icons/speaker_mute.svg")

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var score_label: Label = $UI/ScoreLabel
@onready var streak_label: Label = $UI/StreakLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var game_over_title: Label = $UI/GameOverPanel/GameOverLabel
@onready var result_label: Label = $UI/GameOverPanel/ResultLabel
@onready var pace_label: Label = $UI/GameOverPanel/PaceLabel
@onready var revive_body_label: Label = $UI/GameOverPanel/ReviveBodyLabel
@onready var restart_button: Button = $UI/GameOverPanel/RestartButton
@onready var game_over_menu_button: Button = $UI/GameOverPanel/GameOverMenuButton
@onready var watch_ad_button: Button = $UI/GameOverPanel/WatchAdButton
@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_button: Button = $UI/PauseButton
@onready var controls_button: Button = $UI/PausePanel/ControlsButton
@onready var sound_button: Button = $UI/PausePanel/SoundButton
@onready var resume_icon: TextureRect = $UI/PausePanel/ResumeIcon
@onready var resume_label: Label = $UI/PausePanel/ResumeLabel
@onready var _icon_buttons: Array[Node] = [
	$UI/PauseButton,
	$UI/PausePanel/ControlsButton, $UI/PausePanel/SoundButton,
	$UI/PausePanel/MenuButton,
	$UI/GameOverPanel/RestartButton, $UI/GameOverPanel/GameOverMenuButton,
	$UI/GameOverPanel/WatchAdButton]
@onready var intro: IntroSequence = $IntroSequence
@onready var spawner: Node2D = $PlatformSpawner
@onready var zones: ZoneDirector = $ZoneDirector
@onready var coin_row: HBoxContainer = $UI/CoinRow
@onready var coin_icon: TextureRect = $UI/CoinRow/Icon
@onready var coin_label: Label = $UI/CoinRow/Value
# @onready var mission_toast: Label = $UI/MissionToast  # missions disabled
@onready var zone_banner: Label = $UI/ZoneBanner
@onready var milestone_panel: Control = $UI/MilestonePanel
@onready var milestone_title: Label = $UI/MilestonePanel/TitleLabel
@onready var milestone_body: Label = $UI/MilestonePanel/BodyLabel

const PUNCH_GLOW_BONUS := 0.7
## glow_bloom controls how far the blur spreads into pixels *below* the HDR
## threshold -- at the scene's base 0.05 a bright shape just reads as a crisp
## bright shape, not a halo. Only a flare landing pushes it up, so the soft
## glow around the FLARE text reads as tied to that moment.
const FLARE_GLOW_BLOOM_PEAK := 0.5
## Every Nth streak retriggers Solar Wind (see player.gd:enter_solar_wind) --
## flat, not escalating, so 20/30/40 feel the same as 10 rather than building.
const SOLAR_WIND_STREAK_STEP := 10
const BURST_COLOR := Color(1.15, 1.15, 1.2)
const SAVE_PATH := "user://highscore.cfg"
const STREAK_SCALE_STEP := 0.1
const STREAK_SCALE_CAP := 10
const VIBRATE_AMOUNT := 8.0

## A coin lands on every perfect jump, so during a streak this fires as fast as
## the player is bouncing. The kick is much smaller than the streak counter's
## and settles straight away; a full punch each time would leave the readout
## permanently jittering.
const COIN_PUNCH_SCALE := 1.18
const COIN_SETTLE_TIME := 0.16

## The mission toast holds for a second, with a quick fade at either end so it
## does not pop. Queued rather than stacked: two missions can clear on the same
## landing, and two labels fighting over one slot would just flicker.
## Missions disabled -- unused alongside the toast functions below.
# const TOAST_HOLD := 1.0
# const TOAST_IN := 0.12
# const TOAST_OUT := 0.25
## Each streak snaps the counter up to this scale, then it springs back to
## normal before the next one -- a punch per streak rather than a size that
## creeps up and stays there.
const STREAK_PUNCH_BASE := 1.35
const STREAK_PUNCH_STEP := 0.09
## The punch is held briefly before it springs back, because an elastic ease
## alone reaches its target in ~0.1s -- too fast to actually read as "bigger".
const STREAK_HOLD_TIME := 0.10
const STREAK_SETTLE_TIME := 0.40
const STREAK_SHAKE_BASE := 11.0
const STREAK_SHAKE_STEP := 2.6
## Pixels of shake bled off per second.
const STREAK_SHAKE_DECAY := 48.0
## The counter is a hit of feedback, not a readout: it appears on the streak
## that earned it and takes itself away again, so a long run is not spent with
## a label parked in the middle of the screen.
const STREAK_SHOW_TIME := 1.0
const STREAK_FADE_TIME := 0.3
## The size StreakLabel is authored at in main.tscn -- kept here so a Solar
## Wind message can size up and a later ordinary FLARE/FAILED can size back
## down to the right value, rather than removing the override and hoping the
## theme default happens to match.
const STREAK_FONT_SIZE := 30
const SOLAR_WIND_FONT_SIZE := 44
const SOLAR_WIND_SHOW_TIME := 2.0
## Losing a streak takes the same slot as earning one, in a warning colour --
## the counter vanishing on its own said nothing about why. That colour now
## backs the message instead of drawing it: a miss reads as a bright red card
## with black text punched out of it, which is a different *shape* of alert
## from another flare in a different hue, not just a different colour of the
## same thing. Left above the glow threshold on purpose -- on a failure the
## plate is what blooms.
const STREAK_FAIL_COLOR := Color(2.4, 0.5, 0.6)
## Black glyphs, to read against that plate. The one message whose text sits
## below the glow threshold and so does not bloom at all.
const STREAK_FAIL_TEXT_COLOR := Color(0.0, 0.0, 0.0)
## A streak has to have been worth showing before losing it is worth
## announcing. Below this a mistimed landing is just a landing.
const STREAK_FAIL_MIN := 2
## The counter reads white whatever the character's colour is. It sits above
## the environment's HDR glow threshold of 1.0, which is what makes it bloom
## like the rest of the scene rather than sitting flat on top of it.
const STREAK_TEXT_COLOR := Color(2.3, 2.3, 2.3)
## The plate behind the counter: the character's own colour, multiplied down
## rather than blended toward black, so a teal character and a red one land at
## the same relative depth instead of one of them washing out. The palette is
## authored HDR (channels up to 2.4), and this lands every entry well under the
## glow threshold of 1.0 -- the plate must not bloom, or it would haze the white
## text sitting on it instead of backing it.
const STREAK_PLATE_DARKEN := 0.3
## Short of opaque, so the plate reads as part of the HUD rather than a hole
## punched in the playfield -- the platforms still show faintly through it.
const STREAK_PLATE_ALPHA := 0.95
const STREAK_PLATE_CORNER := 14
## How far the plate stands off the glyphs. Generous horizontally: "FLARE x7"
## is wide and short, and even padding would leave it looking pinched.
const STREAK_PLATE_PAD_X := 22.0
const STREAK_PLATE_PAD_Y := 8.0

## How long a zone announcement stays up between its fade in and fade out.
const ZONE_BANNER_HOLD := 1.1

const HUD_DROP_HEIGHT := 240.0
const HUD_DROP_TIME := 0.55
const HUD_DROP_STAGGER := 0.07

## Where the first platform is seeded, as a fraction of how far the handoff
## speed can actually carry the character. Derived from the speed rather than
## fixed, so retuning the intro's flight cannot make the opening unlandable.
@export var intro_platform_lead: float = 0.76

@export_group("Camera Shake")
## Shake ramps in between these speeds. A normal jump is 900 and a boosted one
## 1300, so ordinary hops stay steady and only the launch and high-streak jumps
## rattle the frame. Cruise speed out of the star is 2600.
##
## Measured against climbing speed alone, so falling never shakes: the frame
## punches on the launch and settles as the arc flattens out.
@export var shake_start_speed: float = 1000.0
@export var shake_full_speed: float = 2600.0
## Shake actually seen, in screen pixels, at full ramp. Divided by zoom on the
## way out, so it stays the same visual size whether the intro is zoomed out or
## gameplay is at 1:1.
@export var shake_max_px: float = 10.0

var score: int = 0
var max_height: float = 0.0
var run_max_streak: int = 0
## Banked into Stats when the run ends, not as each coin lands: a coin is not
## earned until the run is over, and saving mid-flight would hitch the frame.
var run_coins: int = 0
## Perfect landings this run -- currently one per coin, but tracked separately
## because a mission counts flares while coins can come from anywhere.
var run_flares: int = 0
## Seconds of actual play this run, accumulated in _process. Anything that
## pauses the tree -- the pause menu, a milestone popup, the revive offer and
## the ad behind it -- stops running this for free, so the clock only counts
## time the player was really flying. It starts where scoring starts, once the
## intro hands control over, so the cinematic launch is not charged to the
## player's pace.
var run_time: float = 0.0
var is_game_over: bool = false
var is_intro: bool = false
var is_paused: bool = false
var high_score: int = 0
var _score_base_position: Vector2
var _streak_base_position: Vector2
## The point the counter stays centred on. Its own box is re-fitted around each
## message so the plate hugs the text (see _refresh_streak_plate), which moves
## the label's top-left every time -- this is the part that does not move, and
## what _streak_base_position is derived from.
var _streak_center: Vector2
## Whether the message on the counter is a failure, and so which of the two
## plates _streak_plate builds. Held rather than passed, because the plate is
## also rebuilt when the character's colour changes under a message that is
## already on screen.
var _streak_failed: bool = false
var _shown_score: int = -1
## The streak the last landing reported. The player only sends the new value,
## so this is what makes a drop to zero distinguishable from never having had
## one.
var _last_streak: int = 0
## Captured once so glow pulses can tween back to the scene's tuned resting
## bloom instead of a hardcoded number.
var _base_glow_bloom: float = 0.0
## Height gained on the launch burst is free, so scoring is measured from where
## that burst tops out rather than from the launch point.
var _score_origin_y: float = 0.0
var _burst_climbing: bool = false
const SHAKE_SMOOTHING := 0.45
## Lerping toward a fresh random target each frame low-passes it, so the
## excursion actually reached averages ~0.39x the target amplitude -- the
## steady state of a first-order filter driven by uniform noise. Dividing that
## back out is what makes shake_max_px mean the pixels you actually see.
const SHAKE_RESPONSE := 0.39

var _shake: Vector2 = Vector2.ZERO
var _streak_shake: float = 0.0
var _streak_tween: Tween
var _coin_tween: Tween
# Missions disabled -- unused alongside the toast functions below.
# var _toast_tween: Tween
# var _toast_queue: Array[String] = []
var _streak_fade_tween: Tween
var _hud_nodes: Array[Control] = []
var _hud_home: Array[Vector2] = []
var _death_margin: float = 720.0
## A milestone popup pauses the run the same way the pause menu does, so the
## pause controls have to stay out of its way until it is answered.
var _milestone_open: bool = false
## Same treatment for the revive offer -- it pauses too, and has to keep the
## pause controls out of its way until answered.
var _revive_open: bool = false
## One revive per run: a fresh script instance is created on every restart
## (reload_current_scene), so this needs no explicit reset.
var _revive_used: bool = false
## Where the player last landed, so a revive can drop them back somewhere
## solid instead of into the empty air where they fell.
var _last_safe_position: Vector2 = Vector2.ZERO
## Harder than a boosted jump (-1300), so the revive launch carries the player
## clear of wherever they came back in and up into the platform field with a
## little room to spare -- they restart with no streak, so nothing else is
## lifting them. Deliberately not a Solar Wind: the burst is silent, with no
## banner and no speed change, just a firmer jump.
const REVIVE_LAUNCH_VELOCITY := -1500.0
const REVIVE_SPAWN_LIFT := 40.0
## How far below the camera centre a revive drops the player when the platform
## they died past is no longer usable. Well inside _death_margin, so the run
## cannot end again on the frame it resumes, and high enough on screen that the
## live platform field is in reach of the launch.
const REVIVE_SAFE_DROP := 240.0

func _ready() -> void:
	_base_glow_bloom = world_environment.environment.glow_bloom
	_load_high_score()
	player.landed.connect(_on_player_landed)
	zones.zone_changed.connect(_on_zone_changed)
	zones.milestone_reached.connect(_on_milestone_reached)
	spawner.zones = zones
	# _update_coin_label()  # currency display disabled; uncomment to bring the coin count back
	# Missions.completed.connect(_on_mission_completed)  # missions disabled; see missions.gd ENABLED
	game_over_panel.hide()
	milestone_panel.hide()
	zone_banner.hide()
	_score_base_position = score_label.position
	_streak_center = streak_label.position + streak_label.size / 2.0
	_refresh_streak_plate()
	var view := get_viewport_rect().size
	_death_margin = view.y / 2.0 + 80.0
	# The scene parks both at x=360, half of the base 720. Under `expand` a
	# tablet-shaped display is wider than that, so centring has to be measured
	# rather than assumed -- and it must happen before the intro starts, which
	# captures both positions as the origin for its whole flight.
	camera.global_position.x = view.x / 2.0
	player.global_position.x = view.x / 2.0
	# coin_row left out: it has its own hidden-currency-display state, which
	# blanket-setting .visible on everything in this list would undo.
	_hud_nodes = [score_label, streak_label, pause_button]
	for node in _hud_nodes:
		_hud_home.append(node.position)
	_update_controls_icon()
	_update_sound_icon()
	IconPop.attach(_icon_buttons)
	IconPop.pulse(resume_icon, resume_label)
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	Audio.play_music()
	_start_intro()

## Runs before every run, including a restart, since both paths re-enter _ready.
func _start_intro() -> void:
	is_intro = true
	_set_hud_visible(false)
	player.set_physics_process(false)
	# The skip tap must not also register as a jump, so the player simply does
	# not see input until the intro hands control back.
	player.set_process_unhandled_input(false)
	intro.finished.connect(_on_intro_finished)
	intro.begin(camera, player)

func _on_intro_finished() -> void:
	is_intro = false
	player.set_physics_process(true)
	# Deferred so the tap that skipped cannot reach the player this same frame.
	# call_deferred on the setter, not set_deferred: process_unhandled_input is
	# a method pair on Node, not a property, so set_deferred silently no-ops.
	player.call_deferred("set_process_unhandled_input", true)
	# The intro hands the character over mid-flight, already at cruise speed, so
	# its velocity is left untouched -- that continuity is what removes the seam.
	# Covers the edge case of dying before ever landing once -- a revive then
	# has nowhere else safe to fall back to but this hand-off point.
	_last_safe_position = player.global_position
	_burst_climbing = true
	# Warm up the revive ad from the first frame of the run, so the offer at
	# the end of it has something ready to show.
	Ads.load_rewarded()
	_score_origin_y = camera.global_position.y
	spawner.score_origin_y = _score_origin_y
	var reach: float = (player.velocity.y * player.velocity.y) / (2.0 * player.gravity)
	spawner.begin(player.global_position.y - reach * intro_platform_lead)
	# Missions.begin_run()  # missions disabled; see missions.gd ENABLED
	_drop_in_hud()

## Slides the HUD down into place instead of switching it on. Each element is
## parked above its home position and staggered, so it reads as arriving.
func _drop_in_hud() -> void:
	for i in range(_hud_nodes.size()):
		var node: Control = _hud_nodes[i]
		var home: Vector2 = _hud_home[i]
		node.position = home - Vector2(0.0, HUD_DROP_HEIGHT)
		node.modulate.a = 0.0
		node.visible = true
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position", home, HUD_DROP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * HUD_DROP_STAGGER)
		tw.tween_property(node, "modulate:a", 1.0, HUD_DROP_TIME * 0.5) \
			.set_delay(i * HUD_DROP_STAGGER)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	# Replaces the override the scene carries, which is only there so the label
	# previews sensibly in the editor.
	streak_label.add_theme_color_override("font_color", STREAK_TEXT_COLOR)
	# A thin HDR-bright outline gives bloom a bit more surface to pick up
	# without reading as a bold/thick glyph -- the actual glow halo comes
	# from the glow_bloom pulse in _glow_pulse, not from stroke width.
	streak_label.add_theme_constant_override("outline_size", 3)
	streak_label.add_theme_color_override("font_outline_color", STREAK_TEXT_COLOR)
	_refresh_streak_plate()
	# Currency display disabled -- CoinRow is hidden (see main.tscn). Uncomment
	# alongside it to bring the coin count back.
	# coin_label.add_theme_color_override("font_color", Settings.background_particle_color)
	# modulate, not self_modulate: UiOpacity owns self_modulate on every Control
	# under the UI layer, so the tint has to live on the other channel.
	# coin_icon.modulate = Settings.background_particle_color
	UiOpacity.apply($UI)
	_update_pause_button_opacity()

func _unhandled_input(event: InputEvent) -> void:
	if is_intro:
		if event.is_pressed() and not event.is_echo():
			intro.skip()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not is_game_over and not _milestone_open and not _revive_open:
		_toggle_pause()

func _on_pause_pressed() -> void:
	if is_game_over or _milestone_open or _revive_open:
		return
	Audio.play_ui_click()
	_toggle_pause()

## The dim sits under the panel's buttons, so a tap that lands on the sound,
## controls or home icon is taken by that button and never reaches here. The
## panel runs while the tree is paused, which is what lets it hear the tap at
## all -- the game root does not.
func _on_pause_dim_input(event: InputEvent) -> void:
	# Guarded on is_paused rather than toggling: a touch also arrives as an
	# emulated mouse click, and a toggle would unpause then pause straight back.
	if is_paused and event.is_pressed() and not event.is_echo():
		Audio.play_ui_click()
		_toggle_pause()

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	_set_hud_visible(not is_paused)
	if is_paused:
		Audio.fade_to_menu_music()
		_show_pause_panel()
	else:
		Audio.fade_to_gameplay_music()
		_hide_pause_panel()

## Pops the panel in from slightly small and transparent rather than snapping
## it on -- TWEEN_PAUSE_PROCESS is required here since get_tree().paused is
## already true by the time this tween is created.
func _show_pause_panel() -> void:
	pause_panel.pivot_offset = pause_panel.size / 2.0
	pause_panel.modulate.a = 0.0
	pause_panel.scale = Vector2(0.92, 0.92)
	pause_panel.visible = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(pause_panel, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(pause_panel, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_pause_panel() -> void:
	var tw := create_tween()
	tw.tween_property(pause_panel, "modulate:a", 0.0, 0.14)
	tw.parallel().tween_property(pause_panel, "scale", Vector2(0.94, 0.94), 0.14)
	tw.tween_callback(func(): pause_panel.visible = false)

func _set_hud_visible(shown: bool) -> void:
	for node in _hud_nodes:
		node.visible = shown

func _update_pause_button_opacity() -> void:
	pause_button.self_modulate = UiOpacity.tint(Settings.ui_opacity)

func _on_controls_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_control_scheme()
	_update_controls_icon()

func _update_controls_icon() -> void:
	controls_button.icon = (CONTROLS_TILT_ICON
		if Settings.control_scheme == Settings.ControlScheme.TILT else CONTROLS_TOUCH_ICON)

func _on_sound_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_sound_muted()
	_update_sound_icon()

func _update_sound_icon() -> void:
	sound_button.icon = SOUND_OFF_ICON if Settings.sound_muted else SOUND_ON_ICON

## Also used by PausePanel/MenuButton, where a revive is never open, so the
## check below is a no-op there.
func _on_menu_pressed() -> void:
	Audio.play_ui_click()
	_end_open_revive_offer()
	get_tree().paused = false
	Transition.change_scene("res://scenes/main_menu.tscn")

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("scores", "high_score", 0)

func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)

func _process(delta: float) -> void:
	_decay_streak_shake(delta)
	# Ahead of the early return: the launch out of the star happens while the
	# intro still owns the camera, and that is the shake most worth seeing.
	_apply_camera_shake()
	if is_game_over or is_intro:
		return
	run_time += delta
	camera.global_position.y = min(camera.global_position.y, player.global_position.y)
	if _burst_climbing:
		if player.velocity.y < 0.0:
			_score_origin_y = camera.global_position.y
			spawner.score_origin_y = _score_origin_y
		else:
			_burst_climbing = false  # apex of the launch; the run scores from here
	max_height = max(max_height, _score_origin_y - camera.global_position.y)
	score = int(max_height / 10.0)
	# Assigning Label.text re-shapes the text server run even when the string is
	# identical, so only touch it when the number actually moved.
	if score != _shown_score:
		_shown_score = score
		score_label.text = "%d" % score
		zones.update(score)
		# Missions.update_run(_run_summary())  # missions disabled; see missions.gd ENABLED
	if player.global_position.y > camera.global_position.y + _death_margin:
		_game_over()

func _decay_streak_shake(delta: float) -> void:
	if _streak_shake <= 0.0:
		return
	_streak_shake = maxf(_streak_shake - STREAK_SHAKE_DECAY * delta, 0.0)
	if _streak_shake <= 0.0:
		streak_label.position = _streak_base_position
		return
	streak_label.position = _streak_base_position + Vector2(
		randf_range(-_streak_shake, _streak_shake), randf_range(-_streak_shake, _streak_shake))

## Rattles the frame in proportion to how fast the character is moving. The
## offset is lerped rather than snapped so it reads as a rumble, not a buzz.
func _apply_camera_shake() -> void:
	var span := maxf(shake_full_speed - shake_start_speed, 1.0)
	var climb := maxf(-player.velocity.y, 0.0)
	var ramp := clampf((climb - shake_start_speed) / span, 0.0, 1.0)
	var amount := ramp * shake_max_px / SHAKE_RESPONSE
	_shake = _shake.lerp(
		Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), SHAKE_SMOOTHING)
	camera.offset = _shake / maxf(camera.zoom.y, 0.001)

func _on_player_landed(platform: Node, boosted: bool, streak: int) -> void:
	_last_safe_position = platform.global_position
	run_max_streak = maxi(run_max_streak, streak)
	var broke := streak == 0 and _last_streak >= STREAK_FAIL_MIN
	var flared := boosted and streak > 1
	_last_streak = streak
	_grow_to(score_label, 1.0 + STREAK_SCALE_STEP * clampi(streak, 0, STREAK_SCALE_CAP))
	if broke:
		_show_streak_message("FAILED", STREAK_FAIL_TEXT_COLOR, true)
		Audio.vibrate(30)
	# Only a landing that actually extends the streak punches the counter --
	# ordinary jumps leave it sitting still.
	elif flared:
		_show_streak_message("FLARE x%d" % streak, STREAK_TEXT_COLOR)
		_punch_streak(streak)
	# `boosted` is required, not just the streak number: a passive landing that
	# doesn't attempt a timed tap neither increments nor resets streak, so
	# without this guard every such landing after hitting a milestone would
	# keep re-reading the same unchanged streak value and re-firing this.
	if boosted and streak > 0 and streak % SOLAR_WIND_STREAK_STEP == 0:
		# Overwrites the FLARE message _show_streak_message() just set above --
		# same label, same frame, so the player only ever sees SOLAR WIND! on a
		# milestone landing, never a flash of FLARE first.
		_show_streak_message("SOLAR WIND!", STREAK_TEXT_COLOR, false,
			SOLAR_WIND_FONT_SIZE, SOLAR_WIND_SHOW_TIME)
		player.enter_solar_wind()
	if boosted:
		# `boosted` is already once per platform -- player.gd spends the
		# platform's boost on the landing that claims it, and a mistimed one
		# never spends it -- so the coin needs no separate guard.
		run_coins += 1
		run_flares += 1
		# _update_coin_label()  # currency display disabled; run_coins itself still counts for Missions/Stats
		# _punch_coin_label()
		# Missions.update_run(_run_summary())  # missions disabled; see missions.gd ENABLED
		_spawn_burst(platform)
		_camera_punch()
		_glow_pulse(
			Settings.glow_strength + PUNCH_GLOW_BONUS,
			FLARE_GLOW_BLOOM_PEAK if flared else _base_glow_bloom)
		_vibrate(score_label, _score_base_position)
		Audio.vibrate(18)

## Snaps the counter up and shakes it, then lets it spring back to normal size
## so the next streak has somewhere to punch from.
func _punch_streak(streak: int) -> void:
	var tier := clampi(streak, 0, STREAK_SCALE_CAP)
	# Centred text, so it scales about the middle of its own box and stays put
	# on screen instead of drifting sideways as it grows.
	streak_label.pivot_offset = streak_label.size / 2.0
	streak_label.scale = Vector2.ONE * (STREAK_PUNCH_BASE + STREAK_PUNCH_STEP * tier)
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = create_tween()
	_streak_tween.tween_interval(STREAK_HOLD_TIME)
	_streak_tween.tween_property(streak_label, "scale", Vector2.ONE, STREAK_SETTLE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_shake = STREAK_SHAKE_BASE + STREAK_SHAKE_STEP * float(tier)

## Puts one message in the counter's slot and flashes it. Any punch still
## springing back from the streak that just ended is cancelled first, so a
## FAILED does not inherit the swagger of the streak it is reporting the loss
## of; a streak message re-punches straight after this anyway.
func _show_streak_message(text: String, color: Color, failed: bool = false,
		font_size: int = STREAK_FONT_SIZE, hold_time: float = STREAK_SHOW_TIME) -> void:
	_streak_failed = failed
	if streak_label.text != text:
		streak_label.text = text
	streak_label.add_theme_color_override("font_color", color)
	streak_label.add_theme_color_override("font_outline_color", color)
	streak_label.add_theme_font_size_override("font_size", font_size)
	_refresh_streak_plate()
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	streak_label.scale = Vector2.ONE
	_flash_streak(hold_time)

## Rebuilds the plate for whatever is currently written on the counter and
## snaps the label's box back around it.
##
## The plate is the Label's own `normal` stylebox rather than a node behind it,
## which is what makes it free: a stylebox is drawn inside the Control, so it
## inherits the shake (position), the punch (scale) and the fade (modulate)
## already driven on the label without a second thing to keep in sync.
##
## The cost is that a stylebox fills the label's *rect*, and the rect is
## authored 400px wide so the longest message fits -- left alone that draws a
## plate most of the screen wide behind two words. Assigning zero size snaps a
## Control to its combined minimum, which for a Label is the shaped text plus
## the stylebox's content margins, so the box ends up hugging the message.
func _refresh_streak_plate() -> void:
	# An empty counter is the run's starting state and must not show a bare
	# pill floating at a quarter height: with no text there is nothing to back.
	streak_label.add_theme_stylebox_override("normal",
		StyleBoxEmpty.new() if streak_label.text.is_empty() else _streak_plate())
	streak_label.size = Vector2.ZERO
	_streak_base_position = _streak_center - streak_label.size / 2.0
	streak_label.position = _streak_base_position
	streak_label.pivot_offset = streak_label.size / 2.0

func _streak_plate() -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	# A failure keeps its colour at full strength: it is meant to bloom and be
	# alarming, and the black text on it does not need the plate held down to
	# stay readable. A flare's plate is taken right down instead, because white
	# text does.
	var tint := STREAK_FAIL_COLOR if _streak_failed \
		else Settings.player_color * STREAK_PLATE_DARKEN
	plate.bg_color = Color(tint.r, tint.g, tint.b, STREAK_PLATE_ALPHA)
	plate.set_corner_radius_all(STREAK_PLATE_CORNER)
	plate.content_margin_left = STREAK_PLATE_PAD_X
	plate.content_margin_right = STREAK_PLATE_PAD_X
	plate.content_margin_top = STREAK_PLATE_PAD_Y
	plate.content_margin_bottom = STREAK_PLATE_PAD_Y
	return plate

## Brings the counter up and then takes it away. Restarted by every streak, so
## back-to-back streaks hold it on screen continuously instead of blinking it
## off between them.
func _flash_streak(hold_time: float = STREAK_SHOW_TIME) -> void:
	if _streak_fade_tween != null and _streak_fade_tween.is_valid():
		_streak_fade_tween.kill()
	streak_label.modulate.a = 1.0
	_streak_fade_tween = create_tween()
	_streak_fade_tween.tween_interval(hold_time)
	_streak_fade_tween.tween_property(streak_label, "modulate:a", 0.0, STREAK_FADE_TIME)

func _spawn_burst(source: Node) -> void:
	var burst := preload("res://scenes/landing_burst.tscn").instantiate()
	if source is Platform:
		burst.color = Settings.platform_color
	else:
		burst.color = BURST_COLOR
	add_child(burst)
	burst.global_position = source.global_position

func _camera_punch() -> void:
	camera.zoom = Vector2(0.97, 0.97)
	var tw := create_tween()
	tw.tween_property(camera, "zoom", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)

func _glow_pulse(peak: float, bloom_peak: float) -> void:
	var env := world_environment.environment
	env.glow_intensity = peak
	env.glow_bloom = bloom_peak
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(env, "glow_intensity", Settings.glow_strength, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(env, "glow_bloom", _base_glow_bloom, 0.25).set_trans(Tween.TRANS_SINE)

## Tweens the label's transform rather than its font size: animating
## theme_override_font_sizes/font_size re-rasterizes the glyph atlas at a new
## pixel size on every frame of the tween, which is a visible hitch on mobile.
func _grow_to(label: Label, target_scale: float) -> void:
	label.pivot_offset = label.size / 2.0
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * target_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _vibrate(label: Label, base_pos: Vector2) -> void:
	var tw := create_tween()
	for i in range(6):
		var offset := Vector2(randf_range(-VIBRATE_AMOUNT, VIBRATE_AMOUNT), randf_range(-VIBRATE_AMOUNT, VIBRATE_AMOUNT))
		tw.tween_property(label, "position", base_pos + offset, 0.03)
	tw.tween_property(label, "position", base_pos, 0.03)

func _run_summary() -> Dictionary:
	return {
		"score": score,
		"max_streak": run_max_streak,
		"flares": run_flares,
		"coins": run_coins,
		"time": run_time,
		"speed": run_speed(),
		"stage": zones.stage_for_score(score),
	}

## Score per second of play. Read by the game over panel and handed to Stats,
## where the same division is repeated over the saved history -- see
## Stats.speed_of.
func run_speed() -> float:
	return score / run_time if run_time >= Stats.MIN_TIMED_SECONDS else 0.0

## Left edge at a quarter height, deliberately clear of the character's lane and
## of anywhere a thumb rests. The label is MOUSE_FILTER_IGNORE, so even sitting
## over the play area it cannot swallow the tap that times a landing.
## Missions disabled -- unreachable while the `completed` hookup above is
## commented out. Uncomment together with it to bring the toast back.
# func _on_mission_completed(_id: String, reward: int, text: String) -> void:
# 	# Nothing is shown once the run is over -- the death screen is not the place
# 	# for it -- and a hidden HUD stays hidden.
# 	if is_game_over or _hud_hidden:
# 		return
# 	_toast_queue.append("MISSION COMPLETE  +%d\n%s" % [reward, text])
# 	if _toast_tween == null or not _toast_tween.is_valid():
# 		_show_next_toast()
#
# func _show_next_toast() -> void:
# 	if _toast_queue.is_empty():
# 		mission_toast.visible = false
# 		return
# 	mission_toast.text = _toast_queue.pop_front()
# 	mission_toast.modulate.a = 0.0
# 	mission_toast.visible = true
# 	_toast_tween = create_tween()
# 	_toast_tween.tween_property(mission_toast, "modulate:a", 1.0, TOAST_IN)
# 	_toast_tween.tween_interval(TOAST_HOLD)
# 	_toast_tween.tween_property(mission_toast, "modulate:a", 0.0, TOAST_OUT)
# 	_toast_tween.tween_callback(_show_next_toast)

## Same shape as _punch_streak, minus the shake and the hold.
## Currency display disabled -- unused while CoinRow is hidden (see main.tscn
## and the commented call sites above). Uncomment together to bring it back.
# func _punch_coin_label() -> void:
# 	coin_row.pivot_offset = coin_row.size / 2.0
# 	coin_row.scale = Vector2.ONE * COIN_PUNCH_SCALE
# 	if _coin_tween != null and _coin_tween.is_valid():
# 		_coin_tween.kill()
# 	_coin_tween = create_tween()
# 	_coin_tween.tween_property(coin_row, "scale", Vector2.ONE, COIN_SETTLE_TIME) \
# 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
#
# func _update_coin_label() -> void:
# 	coin_label.text = "%d" % (Stats.coins + run_coins)

func _on_zone_changed(stage: int, zone_name: String) -> void:
	if stage == 0:
		return
	zone_banner.text = zone_name
	zone_banner.modulate.a = 0.0
	zone_banner.pivot_offset = zone_banner.size / 2.0
	zone_banner.scale = Vector2(0.8, 0.8)
	zone_banner.show()
	var tw := create_tween()
	tw.tween_property(zone_banner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(zone_banner, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(ZONE_BANNER_HOLD)
	tw.tween_property(zone_banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(zone_banner.hide)

func _on_milestone_reached(kind: int) -> void:
	if kind == ZoneDirector.Milestone.ESCAPE:
		Stats.mark_escaped()
		milestone_title.text = "SOLAR GRAVITY ESCAPED"
		milestone_body.text = "Continue on your journey!\n\nMore you explore, harder it gets!\n\nGood Luck!"
	else:
		Stats.mark_true_ending()
		milestone_title.text = "CONGRATS!!!"
		milestone_body.text = "You've mastered the space!\n\nContinue your journey for eternity to come!"
	_milestone_open = true
	_set_hud_visible(false)
	milestone_panel.show()
	get_tree().paused = true

func _on_milestone_continue_pressed() -> void:
	Audio.play_ui_click()
	_milestone_open = false
	milestone_panel.hide()
	_set_hud_visible(true)
	get_tree().paused = false

## GAME OVER, the score, and Restart/Menu are all shown right away -- the
## revive prompt (text + Watch Ad button) is just added on top of that same
## panel when a revive is still on offer, not swapped in as a separate state.
## Restart/Menu stay live the whole time: pressing either while the offer is
## still up simply ends it (see _on_restart_pressed/_on_menu_pressed).
func _game_over() -> void:
	game_over_title.text = "GAME OVER"
	result_label.text = "SCORE %d   BEST %d" % [score, max(score, high_score)]
	result_label.show()
	# The pace line sits under the score rather than beside it: the score is
	# what the player came for, and how fast they got it is the footnote.
	pace_label.text = "TIME %s   SPEED %s/s" % [
		Stats.format_duration(run_time),
		Stats.format_speed(run_speed()),
	]
	pace_label.show()
	# Duck the beat out the moment death happens, not just once the revive
	# offer (if any) is resolved -- otherwise it keeps blaring at full,
	# pre-death volume under the whole game-over/revive screen.
	Audio.fade_to_menu_music()
	# No loaded ad means no offer at all -- better to end the run cleanly than
	# to show a Watch Ad button that stalls or fails when it is pressed.
	if not _revive_used and Ads.is_rewarded_ready():
		_offer_revive()
	else:
		_finish_game_over()

## The first death in a run additionally offers a second chance instead of
## ending it outright. Reuses GameOverPanel rather than a separate screen --
## same Dim, BackgroundParticles and pop-in tween, just with the revive
## prompt shown alongside the game-over content until the offer is answered.
func _offer_revive() -> void:
	Audio.vibrate(30)
	_revive_open = true
	_set_hud_visible(false)
	get_tree().paused = true
	revive_body_label.show()
	watch_ad_button.disabled = false
	watch_ad_button.show()
	_show_game_over_panel()

func _on_revive_watch_ad_pressed() -> void:
	Audio.play_ui_click()
	# The ad takes a moment to come up and the button stays on screen under it,
	# so without this a second tap queues a second request behind the first.
	watch_ad_button.disabled = true
	Ads.show_rewarded(_on_revive_ad_rewarded, _on_revive_ad_dismissed)

func _on_revive_ad_rewarded() -> void:
	_revive_used = true
	_close_revive_offer()
	_revive_player()
	# Fetch the next one now rather than at the next death -- this run can no
	# longer use it, but the run after it can.
	Ads.load_rewarded()

## Ad closed early, failed to show, or was never there. Same outcome as
## pressing Restart/Menu on a still-open offer: the second chance is declined
## and the run finalizes on the panel already on screen. `_revive_used` stays
## false deliberately -- no ad was watched, so nothing was spent.
func _on_revive_ad_dismissed() -> void:
	_end_open_revive_offer()
	Ads.load_rewarded()

func _close_revive_offer() -> void:
	_revive_open = false
	game_over_panel.hide()

## The camera only ever climbs, and the spawner despawns everything that falls
## below roughly the same line the player dies at -- so by the time a death
## actually registers, the platform in _last_safe_position has usually been
## freed already, and is always well past the death line. Reviving onto it put
## the player straight back outside the margin and _process ended the run again
## on the very next frame, which is why a fully watched ad could still land on
## the death screen. So only reuse that platform while it is still comfortably
## on screen; otherwise put them back under the camera, where the live
## platforms actually are.
func _revive_position() -> Vector2:
	var from_platform := _last_safe_position + Vector2(0.0, -REVIVE_SPAWN_LIFT)
	if from_platform.y < camera.global_position.y + REVIVE_SAFE_DROP:
		return from_platform
	return Vector2(camera.global_position.x, camera.global_position.y + REVIVE_SAFE_DROP)

## Drops the player back into the run with a fresh launch, and lets it continue
## as if it never ended.
func _revive_player() -> void:
	is_game_over = false
	_set_hud_visible(true)
	get_tree().paused = false
	player.global_position = _revive_position()
	player.velocity = Vector2(0.0, REVIVE_LAUNCH_VELOCITY)
	player.streak = 0
	# Brings the gameplay layers back up from the death duck, then immediately
	# overrides them down to the zero-streak volumes -- a revive starts the
	# beat fresh, not wherever the pre-death streak tier left it.
	Audio.fade_to_gameplay_music()
	Audio.set_streak(0)

func _finish_game_over() -> void:
	is_game_over = true
	Audio.vibrate(60)
	if score > high_score:
		high_score = score
		_save_high_score()
	Stats.record_run(score, run_max_streak, run_coins, run_time)
	# Missions disabled -- see missions.gd ENABLED. Uncomment together with the
	# other call sites; it goes after record_run so a mission payout lands on a
	# balance that already includes the coins this run earned.
	# var summary := _run_summary()
	# summary["finished"] = true
	# Missions.end_run(summary)
	revive_body_label.hide()
	watch_ad_button.hide()
	_set_hud_visible(false)
	get_tree().paused = true
	# When restarting/leaving straight out of a still-open revive offer, the
	# panel is already on screen -- title, score and Restart/Menu were shown
	# at the moment of death, so there's nothing left to pop in, just the
	# revive row dropping out.
	if game_over_panel.visible:
		return
	_show_game_over_panel()

## A short beat before the panel pops in, so the death itself has a moment to
## read before the UI arrives on top of it.
func _show_game_over_panel() -> void:
	game_over_panel.pivot_offset = game_over_panel.size / 2.0
	game_over_panel.modulate.a = 0.0
	game_over_panel.scale = Vector2(0.85, 0.85)
	game_over_panel.visible = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.15)
	tw.tween_property(game_over_panel, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(game_over_panel, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_restart_pressed() -> void:
	Audio.play_ui_click()
	_end_open_revive_offer()
	get_tree().paused = false
	Transition.reload_scene()

## Restart/Menu stay visible on the game-over panel even while a revive is
## still on offer -- pressing either one there is an implicit decline, so
## finalize the run (stats/mission payout) before actually leaving it.
func _end_open_revive_offer() -> void:
	if not _revive_open:
		return
	_revive_open = false
	_finish_game_over()
