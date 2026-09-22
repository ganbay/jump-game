extends Node2D

## The pause and game over panels are unlabelled glyphs, so the two toggles in
## them swap their icon to show state -- there is no text left to rewrite.
const CONTROLS_TOUCH_ICON := preload("res://assets/icons/hand.svg")
const CONTROLS_TILT_ICON := preload("res://assets/icons/mobile_phone.svg")
const SOUND_ON_ICON := preload("res://assets/icons/speaker.svg")
const SOUND_OFF_ICON := preload("res://assets/icons/speaker_mute.svg")
const SKIP_ICON := preload("res://assets/icons/arrow_right.svg")
## The skip button is up from the intro's first frame, and a touch anywhere on
## screen takes it -- a retry costs one tap, not one to find the button and a
## second to press it. The button stays as the affordance that says so.
const SKIP_BUTTON_FADE_TIME := 0.2

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
## How far past the resume glyph a tap still counts. The icon is 96px square,
## which is a small target on its own; this grows it to 224 and takes in the
## "TAP TO RESUME" caption underneath, while leaving the rest of the screen
## inert. See _on_pause_dim_input().
const RESUME_TAP_PADDING := 64.0

@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_button: Button = $UI/PauseButton
@onready var controls_button: Button = $UI/PausePanel/ControlsButton
@onready var controls_caption: Label = $UI/PausePanel/ControlsCaption
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
@onready var control_hint: Control = $UI/ControlHint
@onready var control_hint_title: Label = $UI/ControlHint/TitleLabel
@onready var control_hint_body: Label = $UI/ControlHint/BodyLabel
@onready var tap_cue: Label = $UI/TapCue
@onready var tutorial_panel: Control = $UI/TutorialPanel
@onready var tutorial_title: Label = $UI/TutorialPanel/TitleLabel
@onready var tutorial_body: Label = $UI/TutorialPanel/BodyLabel
@onready var tutorial_continue: Button = $UI/TutorialPanel/ContinueButton
@onready var tutorial_dismiss: Button = $UI/TutorialPanel/DismissButton
@onready var milestone_panel: Control = $UI/MilestonePanel
@onready var milestone_title: Label = $UI/MilestonePanel/TitleLabel
@onready var milestone_body: Label = $UI/MilestonePanel/BodyLabel
@onready var milestone_continue: Button = $UI/MilestonePanel/ContinueButton

const PUNCH_GLOW_BONUS := 0.7
## glow_bloom controls how far the blur spreads into pixels *below* the HDR
## threshold -- at the scene's base 0.05 a bright shape just reads as a crisp
## bright shape, not a halo. Only a flare landing pushes it up, so the soft
## glow around the FLARE text reads as tied to that moment.
##
## Kept modest now that $UI shares the glow pass (see main.tscn's
## background_canvas_max_layer): bloom is a screen-space blur added back on
## top of the whole image, so it doesn't respect the streak plate's own
## opacity -- a wide spike here washes a visible halo straight across the
## plate at the exact moment it appears. This still punches, just without
## blowing through it.
const FLARE_GLOW_BLOOM_PEAK := 0.15
## Every Nth streak retriggers Solar Wind (see player.gd:enter_solar_wind) --
## flat, not escalating, so 20/30/40 feel the same as 10 rather than building.
const SOLAR_WIND_STREAK_STEP := 10
const BURST_COLOR := Color(1.15, 1.15, 1.2)
const SAVE_PATH := "user://highscore.cfg"
const STREAK_SCALE_STEP := 0.1
const STREAK_SCALE_CAP := 10
const VIBRATE_AMOUNT := 8.0
## Gap between the screen's left edge and a left-aligned score. Wider than
## VIBRATE_AMOUNT, so the landing rattle never pushes a digit off screen.
const SCORE_LEFT_MARGIN := 28.0

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
## A streak has to have been worth showing before losing it is worth
## announcing. Below this a mistimed landing is just a landing.
const STREAK_FAIL_MIN := 2
## Every message on the counter -- FLARE, SOLAR WIND and FAILED alike -- is
## plain black glyphs, no stroke, on its plate.
const STREAK_TEXT_COLOR := Color(0.0, 0.0, 0.0)
## The plate behind the counter: the character's own colour, scaled rather than
## blended, so a teal character and a red one land at the same relative depth.
## The palette is authored HDR (channels up to 2.4), so at 1.0 the plate sits
## above the glow threshold and blooms the same way FAILED's red plate does --
## black text stays readable on it either way.
const STREAK_PLATE_DARKEN := 1.0
const STREAK_PLATE_ALPHA := 1.0
const STREAK_PLATE_CORNER := 14
## Multiplier over the raw (un-darkened) player colour used for sparks -- see
## _spawn_streak_embers for why the plate's own tint can't be reused here.
## Now that $UI is actually inside the glow pass (see main.tscn's
## background_canvas_max_layer), this is worth pushing further than
## background_particles.gd's own 1.6 cap -- a spark is meant to read as a
## brief hot flash, not an ambient drift.
const EMBER_GLOW_BOOST := 1.4
## How far the plate stands off the glyphs: barely at all, so it hugs the text.
const STREAK_PLATE_PAD_X := 6.0
const STREAK_PLATE_PAD_Y := 0.0

## How long a zone announcement stays up between its fade in and fade out.
const ZONE_BANNER_HOLD := 1.1

## In-run coaching, gated on Settings.tutorial_hints. Two beats: a steer
## prompt naming whichever scheme is actually active as the run starts, then a
## one-time freeze on the first landing teaching the timed tap. Both repeat
## every run rather than only the first -- a player who dies in the opening
## seconds has learnt nothing yet -- and both go away for good from the
## panel's own dismiss button or the HINTS row in Settings.

## How long the steer prompt holds before fading on its own, if the player
## has not already started steering.
const CONTROL_HINT_HOLD := 4.0
const CONTROL_HINT_FADE_IN := 0.25
const CONTROL_HINT_FADE_OUT := 0.45
## Horizontal speed, as a fraction of the character's top speed, that counts as
## the player actually steering rather than drift bleeding off. Held for
## CONTROL_HINT_STEER_TIME before the prompt takes itself away, so a single
## frame of accelerometer noise does not dismiss it.
const CONTROL_HINT_STEER_FRACTION := 0.35
const CONTROL_HINT_STEER_TIME := 0.3
## The follow-up cue after the tap lesson: shown on each descent until the
## player lands their first flare, and given up on after this many descents so
## it cannot nag for a whole run.
const TAP_CUE_MAX_DESCENTS := 4
const TAP_CUE_PULSE_TIME := 0.45
const TAP_CUE_PULSE_MIN_ALPHA := 0.35
const TAP_CUE_FADE := 0.15

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
## Past scores drawn in the world at the heights they were reached: the record,
## the previous run and the lifetime average. Entries leave the array as the
## climb passes them, so an empty array means there is nothing left to mark.
## See _make_score_lines().
var _score_lines: Array[ScoreLine] = []
## Minimum world-pixel spacing between two marks. A caption is ~22px tall and
## sits 12px above its line, so anything closer than this overlaps into an
## unreadable smear -- and on an early save the best, the last run and the
## average are routinely the same run.
const SCORE_LINE_CLEARANCE := 44
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
## One persistent spark emitter, reused for every flare rather than
## instantiated per landing -- see _spawn_streak_embers.
var _streak_embers: Node2D
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
var _skip_button: Button
var _hud_nodes: Array[Control] = []
var _hud_home: Array[Vector2] = []
var _death_margin: float = 720.0
## The tap lesson pauses the run the same way a milestone does, and needs the
## same treatment from the pause controls.
var _tutorial_open: bool = false
## One tap lesson per run: a fresh script instance is created on every restart
## (reload_current_scene), so this needs no explicit reset.
var _boost_hint_shown: bool = false
var _control_hint_open: bool = false
## Set when the scheme is swapped from the pause menu, where the prompt would
## only be showing behind the dim -- resuming is what actually puts it up.
var _control_hint_pending: bool = false
var _control_hint_steer_time: float = 0.0
var _control_hint_tween: Tween
## Whether the follow-up TAP cue is still looking for a first flare this run.
var _tap_cue_active: bool = false
var _tap_cue_descents: int = 0
var _tap_cue_tween: Tween
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
	# First thing in the run: under shuffle this picks the character and emits
	# visual_settings_changed, which the already-ready Player is listening on,
	# so it re-dresses in the same frame and nothing is ever drawn wearing the
	# previous run's skin.
	Settings.roll_shuffled_skin()
	_base_glow_bloom = world_environment.environment.glow_bloom
	_load_high_score()
	player.landed.connect(_on_player_landed)
	player.streak_broken.connect(_on_streak_broken)
	zones.zone_changed.connect(_on_zone_changed)
	zones.milestone_reached.connect(_on_milestone_reached)
	spawner.zones = zones
	# _update_coin_label()  # currency display disabled; uncomment to bring the coin count back
	# Missions.completed.connect(_on_mission_completed)  # missions disabled; see missions.gd ENABLED
	game_over_panel.hide()
	milestone_panel.hide()
	tutorial_panel.hide()
	control_hint.hide()
	tap_cue.hide()
	zone_banner.hide()
	# Before anything reads the label's position: the vibrate origin and the
	# HUD drop-in home are both captured from where this leaves it.
	_apply_score_align()
	_score_base_position = score_label.position
	_streak_center = streak_label.position + streak_label.size / 2.0
	# The plate has to actually block what's behind it -- see UiOpacity's
	# EXEMPT_GROUP doc for why the UI Opacity slider can't be allowed to
	# thin it out the way it does every other readout.
	streak_label.add_to_group(UiOpacity.EXEMPT_GROUP)
	_refresh_streak_plate()
	_streak_embers = preload("res://scenes/streak_embers.tscn").instantiate()
	streak_label.get_parent().add_child(_streak_embers)
	# Behind the plate and its text, not over them: a sibling drawn later
	# paints on top, so this has to sit earlier than StreakLabel in the
	# parent's child order.
	streak_label.get_parent().move_child(_streak_embers, streak_label.get_index())
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
	# The pause menu can swap the scheme mid-run, and the prompt names the
	# scheme -- so a swap re-shows it rather than leaving the player with a
	# line about the controls they just stopped using.
	Settings.control_scheme_changed.connect(_on_control_scheme_changed)
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
	_make_skip_button()

## Built here rather than in main.tscn since it only lives for the intro. It
## takes the pause button's corner, which stays hidden until the HUD drops in.
func _make_skip_button() -> void:
	_skip_button = Button.new()
	_skip_button.text = "SKIP"
	_skip_button.icon = SKIP_ICON
	_skip_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_button.flat = true
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.add_theme_font_size_override("font_size", 26)
	_skip_button.add_theme_constant_override("icon_max_width", 28)
	_skip_button.add_theme_color_override("font_color", Color(1.5, 1.5, 1.5, 1))
	_skip_button.add_theme_color_override("icon_normal_color", Color(1.5, 1.5, 1.5, 1))
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.offset_left = -150.0
	_skip_button.offset_top = 14.0
	_skip_button.offset_right = -12.0
	_skip_button.offset_bottom = 70.0
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.self_modulate = UiOpacity.tint(Settings.ui_opacity)
	_skip_button.modulate.a = 0.0
	# Disabled until the fade finishes, which is also the grace period that
	# stops a stray press arriving with the scene -- the emulated mouse click
	# that follows the menu's play touch, or a finger still coming off the
	# screen -- from skipping the intro it just started. _unhandled_input reads
	# the same flag, so the whole-screen target opens at the same moment.
	_skip_button.disabled = true
	_skip_button.pressed.connect(_on_skip_pressed)
	$UI.add_child(_skip_button)
	# Bound to the button, so the tween dies with it if a skip frees it mid-fade.
	# The callback holds the node itself rather than reading the field back --
	# _remove_skip_button() nulls the field, and a callback that outlived it
	# would otherwise set a property on nothing.
	var button := _skip_button
	var tw := button.create_tween()
	tw.tween_property(button, "modulate:a", 1.0, SKIP_BUTTON_FADE_TIME)
	tw.tween_callback(func(): button.disabled = false)

func _on_skip_pressed() -> void:
	if not is_intro or _skip_button == null:
		return
	Audio.play_ui_click()
	_remove_skip_button()
	intro.skip()

## Nulled as well as freed: the intro's fast-forward keeps is_intro true for a
## moment after a skip, and taps in that window must find no button to show.
func _remove_skip_button() -> void:
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null

func _on_intro_finished() -> void:
	is_intro = false
	_remove_skip_button()
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
	Analytics.log_event("run_start")
	Crash.log_message("run_start")
	_score_origin_y = camera.global_position.y
	spawner.score_origin_y = _score_origin_y
	_make_score_lines()
	var reach: float = (player.velocity.y * player.velocity.y) / (2.0 * player.gravity)
	spawner.begin(player.global_position.y - reach * intro_platform_lead)
	# Missions.begin_run()  # missions disabled; see missions.gd ENABLED
	_drop_in_hud()
	_show_control_hint()

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
	Settings.apply_glow(world_environment.environment)
	# Replaces the override the scene carries, which is only there so the label
	# previews sensibly in the editor.
	streak_label.add_theme_color_override("font_color", STREAK_TEXT_COLOR)
	streak_label.add_theme_constant_override("outline_size", 0)
	_refresh_streak_plate()
	# Currency display disabled -- CoinRow is hidden (see main.tscn). Uncomment
	# alongside it to bring the coin count back.
	# coin_label.add_theme_color_override("font_color", Settings.background_particle_color)
	# modulate, not self_modulate: UiOpacity owns self_modulate on every Control
	# under the UI layer, so the tint has to live on the other channel.
	# coin_icon.modulate = Settings.background_particle_color
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	# After UiAccent, never before: the plated headings are in its group, so it
	# would otherwise paint their text back to accent-on-accent and leave them
	# invisible against their own plate.
	_apply_ui_plates()
	_update_pause_button_opacity()

func _unhandled_input(event: InputEvent) -> void:
	if is_intro:
		# Hardware volume/back buttons arrive as key events on Android; they
		# shouldn't touch the intro, so keys only count if they're Space/Enter.
		# Anything else that gets this far is a press on the play area, which is
		# the skip target in full -- the button is only the label for it. A press
		# that lands on the button itself is taken by the button and never
		# reaches here, which comes out at the same place.
		if event.is_pressed() and not event.is_echo() \
				and (event is not InputEventKey or event.is_action("ui_accept")):
			# Null while a skip is already fast-forwarding; disabled until the
			# button has faded in -- see _make_skip_button().
			if _skip_button != null and not _skip_button.disabled:
				_on_skip_pressed()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not is_game_over and not _milestone_open \
			and not _revive_open and not _tutorial_open:
		_toggle_pause()

func _on_pause_pressed() -> void:
	if is_game_over or _milestone_open or _revive_open or _tutorial_open:
		return
	Audio.play_ui_click()
	_toggle_pause()

## The dim sits under the panel's buttons, so a tap that lands on the sound,
## controls or home icon is taken by that button and never reaches here. The
## panel runs while the tree is paused, which is what lets it hear the tap at
## all -- the game root does not.
##
## Only a tap inside _resume_tap_rect() resumes. The dim still swallows every
## other tap: a paused screen that resumes from anywhere is far too easy to
## dismiss by accident -- picking the phone back up, or brushing the display
## while reading the panel, dropped the player straight into a live run.
func _on_pause_dim_input(event: InputEvent) -> void:
	# Guarded on is_paused rather than toggling: a touch also arrives as an
	# emulated mouse click, and a toggle would unpause then pause straight back.
	if not (is_paused and event.is_pressed() and not event.is_echo()):
		return
	# Only positional events carry a position to test; gui_input can hand a
	# focused Control key presses too, and those must not resume from nowhere.
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	if not _resume_tap_rect().has_point(event.position):
		return
	Audio.play_ui_click()
	_toggle_pause()

## The resume target: the glyph, grown to a comfortable thumb and reaching down
## far enough to take in the caption under it. The dim spans the whole panel
## from the origin, so a gui_input position on it is already in the same space
## as these rects.
func _resume_tap_rect() -> Rect2:
	var rect := resume_icon.get_rect().grow(RESUME_TAP_PADDING)
	# Read the caption's real position rather than assuming the spacing of the
	# design resolution: the glyph is anchored at the centre in fixed pixels
	# and the caption proportionally, so the gap between the two widens as the
	# viewport gets taller -- and with stretch mode "viewport" plus an expand
	# aspect, a tall phone is a good deal taller than 1280.
	var caption_bottom := resume_label.get_rect().end.y + RESUME_TAP_PADDING * 0.25
	rect.end = Vector2(rect.end.x, maxf(rect.end.y, caption_bottom))
	return rect

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	_set_hud_visible(not is_paused)
	if is_paused:
		# Both hints sit in the UI layer above the run, not in _hud_nodes (the
		# drop-in tweens those by position, which these have no part in), so
		# they have to be taken down by hand -- and the steer prompt's hold
		# should not be burning away behind the pause panel either.
		_dismiss_control_hint()
		_hide_tap_cue()
		Audio.fade_to_menu_music()
		_show_pause_panel()
	else:
		Audio.fade_to_gameplay_music()
		_hide_pause_panel()
		if _control_hint_pending:
			_control_hint_pending = false
			_show_control_hint()

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

## The one glyph in this panel that needs a word under it. Sound and home
## swap between two readings of the same idea -- a speaker with or without its
## mute bar, a house that is always a house -- but a hand and a phone are two
## unrelated pictures, and a player who has only ever seen one of them has no
## way to tell it is a switch rather than a decoration. Testers proved that:
## they finished runs on tilt without ever learning swipe existed. The caption
## names the scheme that is live, so the glyph reads as state.
func _update_controls_icon() -> void:
	var tilt := Settings.control_scheme == Settings.ControlScheme.TILT
	controls_button.icon = CONTROLS_TILT_ICON if tilt else CONTROLS_TOUCH_ICON
	controls_caption.text = "TILT" if tilt else "SWIPE"

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
	# Sparks track the counter's own fade (_flash_streak tweens
	# streak_label.modulate.a) rather than a fixed brightness, so they die
	# down together with the message instead of still shining after it's
	# gone translucent or vanished.
	_streak_embers.modulate.a = streak_label.modulate.a
	# Ahead of the early return: the launch out of the star happens while the
	# intro still owns the camera, and that is the shake most worth seeing.
	_apply_camera_shake()
	if is_game_over or is_intro:
		return
	_update_control_hint(delta)
	_update_tap_cue()
	run_time += delta
	camera.global_position.y = min(camera.global_position.y, player.global_position.y)
	if _burst_climbing:
		if player.velocity.y < 0.0:
			_score_origin_y = camera.global_position.y
			spawner.score_origin_y = _score_origin_y
			_position_score_lines()
		else:
			_burst_climbing = false  # apex of the launch; the run scores from here
	max_height = max(max_height, _score_origin_y - camera.global_position.y)
	score = int(max_height / 10.0)
	# Assigning Label.text re-shapes the text server run even when the string is
	# identical, so only touch it when the number actually moved.
	if score != _shown_score:
		_shown_score = score
		score_label.text = "%d" % score
		if not _score_lines.is_empty():
			_pass_score_lines()
		zones.update(score)
		# Missions.update_run(_run_summary())  # missions disabled; see missions.gd ENABLED
	if player.global_position.y > camera.global_position.y + _death_margin:
		_game_over()

## The past-score marks. Nothing to draw on a first run, and the scoring origin
## is still climbing at this point -- the launch burst is free height, so
## scoring starts from its apex (see _process) -- which is why the placement is
## a separate call that _process keeps repeating until the burst tops out.
##
## Added most important first, so _add_score_line drops the lesser of any two
## marks that would land on top of each other.
func _make_score_lines() -> void:
	var view_width := get_viewport_rect().size.x
	_add_score_line(ScoreLine.Kind.BEST, high_score, view_width)
	_add_score_line(ScoreLine.Kind.LAST, _last_run_score(), view_width)
	_add_score_line(ScoreLine.Kind.AVERAGE, int(round(Stats.average_score())), view_width)
	_position_score_lines()

func _add_score_line(kind: ScoreLine.Kind, line_score: int, view_width: float) -> void:
	if line_score <= 0:
		return  # no run behind this one yet
	for placed in _score_lines:
		if absi(placed.score - line_score) * 10 < SCORE_LINE_CLEARANCE:
			return
	var line := ScoreLine.new()
	# Behind the platforms and the character, which share the default z: the
	# marks are part of the world the player climbs through, not something in
	# front of it.
	line.z_index = -1
	add_child(line)
	line.setup(kind, line_score, view_width)
	_score_lines.append(line)

## The score of the run before this one. record_run appends at game over and the
## scene reloads for a new run, so the last entry in the history is already the
## previous run by the time a run reads it.
func _last_run_score() -> int:
	if Stats.runs.is_empty():
		return 0
	return int(Stats.runs.back().get("score", 0))

func _position_score_lines() -> void:
	for line in _score_lines:
		line.global_position = Vector2(0.0, _score_origin_y - float(line.score) * 10.0)

## Retires every mark the climb has just passed. Walked backwards because the
## crossed entries are removed in place, and marks close together can go on the
## same frame.
func _pass_score_lines() -> void:
	for i in range(_score_lines.size() - 1, -1, -1):
		var line := _score_lines[i]
		if score < line.score:
			continue
		# Removed here rather than waited on: surpass() frees the node at the
		# end of its own fade, and nothing should reach for it after this.
		line.surpass()
		_score_lines.remove_at(i)
		# Only the record earns a buzz. The average and the last run are passed
		# early and often, and three taps in the opening seconds of a good climb
		# would read as a malfunction rather than a beat.
		if line.kind == ScoreLine.Kind.BEST:
			Audio.vibrate(30)

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

## The player broke the streak by mashing right after a landing, mid-flight --
## flash FAILED now rather than waiting for the (already-zeroed) streak to
## arrive on the next landed signal. Mirrors the `broke` branch of
## _on_player_landed, and updates _last_streak the same way so that later
## landing doesn't flash FAILED a second time for this same break.
func _on_streak_broken() -> void:
	if _last_streak >= STREAK_FAIL_MIN:
		_show_streak_message("FAILED", true)
		Audio.vibrate(30)
	_last_streak = 0

func _on_player_landed(platform: Node, boosted: bool, streak: int) -> void:
	_last_safe_position = platform.global_position
	run_max_streak = maxi(run_max_streak, streak)
	var broke := streak == 0 and _last_streak >= STREAK_FAIL_MIN
	var flared := boosted and streak > 1
	_last_streak = streak
	_grow_to(score_label, 1.0 + STREAK_SCALE_STEP * clampi(streak, 0, STREAK_SCALE_CAP),
		_score_pivot())
	if broke:
		_show_streak_message("FAILED", true)
		Audio.vibrate(30)
	# Only a landing that actually extends the streak punches the counter --
	# ordinary jumps leave it sitting still.
	elif flared:
		_show_streak_message("FLARE x%d" % streak)
		_punch_streak(streak)
	# `boosted` is required, not just the streak number: a passive landing that
	# doesn't attempt a timed tap neither increments nor resets streak, so
	# without this guard every such landing after hitting a milestone would
	# keep re-reading the same unchanged streak value and re-firing this.
	if boosted and streak > 0 and streak % SOLAR_WIND_STREAK_STEP == 0:
		# Overwrites the FLARE message _show_streak_message() just set above --
		# same label, same frame, so the player only ever sees SOLAR WIND! on a
		# milestone landing, never a flash of FLARE first.
		_show_streak_message("SOLAR WIND!", false,
			SOLAR_WIND_FONT_SIZE, SOLAR_WIND_SHOW_TIME)
		# Re-aimed at the bigger SOLAR WIND plate, and kept sparking for its
		# whole (longer) hold rather than the FLARE burst's.
		_spawn_streak_embers(clampi(streak, 0, STREAK_SCALE_CAP), SOLAR_WIND_SHOW_TIME)
		player.enter_solar_wind()
	_tutorial_on_landed(boosted)
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
	_spawn_streak_embers(tier)

## Refreshes the plate's spark emitter rather than spawning a new one each
## landing: the emitter is one persistent node (see _ready) whose burst()
## just extends how long it keeps sparking, so back-to-back flares read as
## one continuous spray instead of overlapping one-shot bursts. Read before
## the punch tween above has moved anything: streak_label.size/position are
## this frame's plate, already refreshed for the new message by
## _refresh_streak_plate, and position is untouched by the scale tween that
## is about to run on it.
func _spawn_streak_embers(tier: int, hold_time: float = STREAK_SHOW_TIME) -> void:
	# Player colour scaled by its own EMBER_GLOW_BOOST, independent of the
	# plate's STREAK_PLATE_DARKEN, so spark bloom and plate bloom tune
	# separately.
	var ember_color := Settings.player_color * EMBER_GLOW_BOOST
	ember_color.a = 1.0
	_streak_embers.color = ember_color
	_streak_embers.plate_size = streak_label.size
	_streak_embers.tier = tier
	_streak_embers.position = streak_label.position + streak_label.size / 2.0
	# Sparks only while the plate is fully up: the spray is gone by the time the
	# text starts its STREAK_FADE_TIME fade, so it never outlives the message.
	_streak_embers.burst(hold_time)

## Puts one message in the counter's slot and flashes it. Any punch still
## springing back from the streak that just ended is cancelled first, so a
## FAILED does not inherit the swagger of the streak it is reporting the loss
## of; a streak message re-punches straight after this anyway.
func _show_streak_message(text: String, failed: bool = false,
		font_size: int = STREAK_FONT_SIZE, hold_time: float = STREAK_SHOW_TIME) -> void:
	_streak_failed = failed
	if streak_label.text != text:
		streak_label.text = text
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
	plate.bg_color = _streak_plate_color()
	plate.set_corner_radius_all(STREAK_PLATE_CORNER)
	plate.content_margin_left = STREAK_PLATE_PAD_X
	plate.content_margin_right = STREAK_PLATE_PAD_X
	plate.content_margin_top = STREAK_PLATE_PAD_Y
	plate.content_margin_bottom = STREAK_PLATE_PAD_Y
	return plate

## The plate's fill colour, also handed to the spark emitter (_spawn_streak_
## embers) so its sparks read as pieces of the plate itself rather than a
## separately-tuned effect colour.
##
## Both plates are bright enough to bloom: red on a failure, the character's
## own colour (scaled by STREAK_PLATE_DARKEN) on a flare or Solar Wind.
func _streak_plate_color() -> Color:
	var tint := STREAK_FAIL_COLOR if _streak_failed \
		else Settings.player_color * STREAK_PLATE_DARKEN
	return Color(tint.r, tint.g, tint.b, STREAK_PLATE_ALPHA)

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
func _grow_to(label: Label, target_scale: float, pivot: Vector2) -> void:
	label.pivot_offset = pivot
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * target_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The scene authors the score centred along the top edge. LEFT re-anchors the
## same box to the left edge, keeping its width and height, so only the
## horizontal placement changes.
## Gives the coaching prompts and the panel buttons the streak counter's plate,
## so they stop reading as bare text on a dim. Re-run whenever the accent moves,
## since the fill is the character's colour.
##
## The two body paragraphs and the milestone's 48px headline stay bare on
## purpose -- see UiPlate's header for why.
func _apply_ui_plates() -> void:
	UiPlate.title(control_hint_title)
	UiPlate.title(tap_cue)
	UiPlate.title(tutorial_title)
	UiPlate.action(tutorial_continue)
	UiPlate.quiet(tutorial_dismiss)
	UiPlate.action(milestone_continue)

func _apply_score_align() -> void:
	if Settings.score_align != Settings.ScoreAlign.LEFT:
		return
	var width := score_label.size.x
	# Left side first: anchor_left may never pass anchor_right, and the right
	# anchor is still at 0.5 here. set_anchor_and_offset rather than the plain
	# anchor properties, which rewrite the offsets to hold the old position.
	score_label.set_anchor_and_offset(SIDE_LEFT, 0.0, SCORE_LEFT_MARGIN)
	score_label.set_anchor_and_offset(SIDE_RIGHT, 0.0, SCORE_LEFT_MARGIN + width)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

## Centred text grows about its middle. Left-aligned text grows from its left
## edge instead: scaled about the middle, it would spread left past the margin
## and off the screen as the streak builds.
func _score_pivot() -> Vector2:
	if Settings.score_align == Settings.ScoreAlign.LEFT:
		return Vector2(0.0, score_label.size.y / 2.0)
	return score_label.size / 2.0

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

## --- In-run coaching -----------------------------------------------------
##
## Named after the scheme that is actually live, because the two are steered
## in completely different ways and a generic "steer to move" teaches neither.
## Non-blocking: it sits low on the screen, out of the platform field, and
## takes itself away on a timer or as soon as the player starts steering --
## whichever comes first.
func _show_control_hint() -> void:
	if not Settings.tutorial_hints or is_game_over or is_intro:
		return
	var tilt := Settings.control_scheme == Settings.ControlScheme.TILT
	control_hint_title.text = "TILT TO STEER" if tilt else "SWIPE TO STEER"
	# The plate is fitted to whatever string was on the label when it was
	# built, and these two differ in width, so it has to be rebuilt here.
	UiPlate.title(control_hint_title)
	# One line, and only the half the title doesn't already say: that the other
	# scheme exists and where to find it. A prompt over live play is read in a
	# glance or not at all.
	control_hint_body.text = ("Or swipe -- change in pause menu." if tilt
		else "Or tilt -- change in pause menu.")
	_control_hint_open = true
	_control_hint_steer_time = 0.0
	control_hint.modulate.a = 0.0
	control_hint.show()
	if _control_hint_tween != null and _control_hint_tween.is_valid():
		_control_hint_tween.kill()
	_control_hint_tween = create_tween()
	_control_hint_tween.tween_property(control_hint, "modulate:a", 1.0, CONTROL_HINT_FADE_IN)
	_control_hint_tween.tween_interval(CONTROL_HINT_HOLD)
	_control_hint_tween.tween_callback(_fade_control_hint_out)

## Steering for real retires the prompt early -- it has nothing left to say to
## someone already doing it. Measured as sustained speed rather than a single
## frame, since a phone at rest still reports a little accelerometer noise.
func _update_control_hint(delta: float) -> void:
	if not _control_hint_open:
		return
	if absf(player.velocity.x) < player.move_speed * CONTROL_HINT_STEER_FRACTION:
		_control_hint_steer_time = 0.0
		return
	_control_hint_steer_time += delta
	if _control_hint_steer_time >= CONTROL_HINT_STEER_TIME:
		_fade_control_hint_out()

func _fade_control_hint_out() -> void:
	if not _control_hint_open:
		return
	_control_hint_open = false
	if _control_hint_tween != null and _control_hint_tween.is_valid():
		_control_hint_tween.kill()
	_control_hint_tween = create_tween()
	_control_hint_tween.tween_property(control_hint, "modulate:a", 0.0, CONTROL_HINT_FADE_OUT)
	_control_hint_tween.tween_callback(control_hint.hide)

## No fade: this is for the frame a panel comes up over the run, where a
## prompt easing out behind the dim is just something else moving.
func _dismiss_control_hint() -> void:
	_control_hint_open = false
	if _control_hint_tween != null and _control_hint_tween.is_valid():
		_control_hint_tween.kill()
	control_hint.hide()

func _on_control_scheme_changed(_scheme: int) -> void:
	if is_game_over or is_intro:
		return
	if is_paused or _tutorial_open:
		# Swapped from the pause menu, which is the usual case -- the prompt
		# would only be showing behind the dim, so it waits for the resume.
		_control_hint_pending = true
		return
	_show_control_hint()

## The first landing of the run is the teaching moment for the timed tap: the
## player has just felt a landing happen and has a whole jump ahead of them to
## try it on. A landing that already flared is skipped -- they found it on
## their own, and interrupting to explain what they just did is worse than
## saying nothing.
func _tutorial_on_landed(boosted: bool) -> void:
	if boosted:
		_end_tap_cue()
	if _boost_hint_shown or not Settings.tutorial_hints or is_game_over:
		return
	_boost_hint_shown = true
	if boosted:
		return
	# Deferred so the freeze lands between frames rather than partway through
	# the physics step this landing was resolved in -- the launch velocity,
	# squash and burst the landing just set all get to play out first.
	call_deferred("_open_boost_tutorial")

func _open_boost_tutorial() -> void:
	if is_game_over or is_paused or _milestone_open or _revive_open:
		return
	_tutorial_open = true
	_dismiss_control_hint()
	_set_hud_visible(false)
	tutorial_title.text = "TAP TO FLARE"
	UiPlate.title(tutorial_title)
	# Two lines, not a paragraph: the panel has already stopped the run, and
	# what it costs the player is reading time. The title carries the reward,
	# so the body only has to carry the timing and the one mistake worth
	# warning about -- what a streak is worth shows itself on the next flare.
	tutorial_body.text = "Tap the instant you land.\nOne tap, not a mash."
	tutorial_panel.pivot_offset = tutorial_panel.size / 2.0
	tutorial_panel.modulate.a = 0.0
	tutorial_panel.scale = Vector2(0.92, 0.92)
	tutorial_panel.visible = true
	# TWEEN_PAUSE_PROCESS for the same reason the pause panel needs it: the
	# tree is about to stop, and a bound tween would stop with it.
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(tutorial_panel, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(tutorial_panel, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().paused = true

func _on_tutorial_continue_pressed() -> void:
	Audio.play_ui_click()
	_close_boost_tutorial()
	_begin_tap_cue()

## Turning the hints off here rather than only in Settings: the panel is where
## a returning player meets them, and making them hunt through a menu to stop
## seeing it every run is the whole complaint.
func _on_tutorial_dismiss_pressed() -> void:
	Audio.play_ui_click()
	Settings.set_tutorial_hints(false)
	_close_boost_tutorial()

func _close_boost_tutorial() -> void:
	_tutorial_open = false
	tutorial_panel.hide()
	_set_hud_visible(true)
	get_tree().paused = false

## Reading the rule is not the same as feeling the window, so the cue rides
## the next few descents -- the part of the jump the tap belongs to -- and
## retires the moment a flare actually lands.
func _begin_tap_cue() -> void:
	if not Settings.tutorial_hints:
		return
	_tap_cue_active = true
	_tap_cue_descents = 0

func _update_tap_cue() -> void:
	if not _tap_cue_active:
		return
	if is_paused or _tutorial_open or _milestone_open or _revive_open:
		_hide_tap_cue()
		return
	var descending := player.velocity.y > 0.0
	if descending == tap_cue.visible:
		return
	if descending:
		_tap_cue_descents += 1
		if _tap_cue_descents > TAP_CUE_MAX_DESCENTS:
			_end_tap_cue()
			return
		_show_tap_cue()
	else:
		_hide_tap_cue()

## Pulsed rather than held solid: the cue is asking for an action on a beat,
## and a label just sitting there reads as part of the HUD.
func _show_tap_cue() -> void:
	tap_cue.modulate.a = 1.0
	tap_cue.visible = true
	if _tap_cue_tween != null and _tap_cue_tween.is_valid():
		_tap_cue_tween.kill()
	_tap_cue_tween = create_tween().set_loops()
	_tap_cue_tween.tween_property(tap_cue, "modulate:a", TAP_CUE_PULSE_MIN_ALPHA,
		TAP_CUE_PULSE_TIME).set_trans(Tween.TRANS_SINE)
	_tap_cue_tween.tween_property(tap_cue, "modulate:a", 1.0,
		TAP_CUE_PULSE_TIME).set_trans(Tween.TRANS_SINE)

func _hide_tap_cue() -> void:
	if _tap_cue_tween != null and _tap_cue_tween.is_valid():
		_tap_cue_tween.kill()
	tap_cue.visible = false

func _end_tap_cue() -> void:
	_tap_cue_active = false
	_hide_tap_cue()

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
		Analytics.log_event("milestone_escape")
		milestone_title.text = "SOLAR GRAVITY ESCAPED"
		milestone_body.text = "Continue on your journey!\n\nMore you explore, harder it gets!\n\nGood Luck!"
	else:
		Stats.mark_true_ending()
		Analytics.log_event("milestone_true_ending")
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
	# _process stops looking at either hint from here on (it returns early on
	# is_game_over), so anything still up has to be taken down now.
	_dismiss_control_hint()
	_end_tap_cue()
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
	Analytics.log_event("revive_used")
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
	Analytics.log_event("run_end", {
		"score": score,
		"max_streak": run_max_streak,
		"coins": run_coins,
		"duration_s": int(run_time),
	})
	Crash.log_message("run_end score=%d" % score)
	Crash.set_custom_value("last_score", score)
	# First finished run only; asks for the notification permission once the
	# player is idle on this panel.
	Notify.request_permission_once()
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
