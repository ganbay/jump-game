extends Node2D

## The pause and game over panels are unlabelled glyphs, so the two toggles in
## them swap their icon to show state -- there is no text left to rewrite.
const CONTROLS_TOUCH_ICON := preload("res://assets/icons/joystick.png")
const CONTROLS_TILT_ICON := preload("res://assets/icons/phone.png")
const SOUND_ON_ICON := preload("res://assets/icons/audioOn.png")
const SOUND_OFF_ICON := preload("res://assets/icons/audioOff.png")
const HUD_SHOWN_ICON := preload("res://assets/icons/menuList.png")
const HUD_HIDDEN_ICON := preload("res://assets/icons/cross.png")
## The pause button is the one readout a hidden HUD keeps, so that the menu
## that turns the HUD back on stays reachable. It drops to a ghost rather than
## sitting at the player's chosen opacity -- the point of hiding is a clean
## screen, and this is the compromise that keeps the run recoverable.
const HIDDEN_PAUSE_OPACITY := 0.2

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var score_label: Label = $UI/ScoreLabel
@onready var streak_label: Label = $UI/StreakLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var result_label: Label = $UI/GameOverPanel/ResultLabel
@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_button: Button = $UI/PauseButton
@onready var controls_button: Button = $UI/PausePanel/ControlsButton
@onready var sound_button: Button = $UI/PausePanel/SoundButton
@onready var hud_button: Button = $UI/PausePanel/HudButton
@onready var resume_icon: TextureRect = $UI/PausePanel/ResumeIcon
@onready var resume_label: Label = $UI/PausePanel/ResumeLabel
@onready var _icon_buttons: Array[Node] = [
	$UI/PauseButton,
	$UI/PausePanel/ControlsButton, $UI/PausePanel/SoundButton,
	$UI/PausePanel/HudButton,
	$UI/PausePanel/MenuButton,
	$UI/GameOverPanel/RestartButton, $UI/GameOverPanel/GameOverMenuButton]
@onready var intro: IntroSequence = $IntroSequence
@onready var spawner: Node2D = $PlatformSpawner
@onready var zones: ZoneDirector = $ZoneDirector
@onready var coin_row: HBoxContainer = $UI/CoinRow
@onready var coin_icon: TextureRect = $UI/CoinRow/Icon
@onready var coin_label: Label = $UI/CoinRow/Value
@onready var mission_toast: Label = $UI/MissionToast
@onready var zone_label: Label = $UI/ZoneLabel
@onready var zone_banner: Label = $UI/ZoneBanner
@onready var milestone_panel: Control = $UI/MilestonePanel
@onready var milestone_title: Label = $UI/MilestonePanel/TitleLabel
@onready var milestone_body: Label = $UI/MilestonePanel/BodyLabel

const PUNCH_GLOW_BONUS := 0.7
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
const TOAST_HOLD := 1.0
const TOAST_IN := 0.12
const TOAST_OUT := 0.25
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
## Losing a streak takes the same slot as earning one, in a warning colour --
## the counter vanishing on its own said nothing about why.
const STREAK_FAIL_COLOR := Color(2.4, 0.5, 0.6)
## A streak has to have been worth showing before losing it is worth
## announcing. Below this a mistimed landing is just a landing.
const STREAK_FAIL_MIN := 2
## The counter reads white whatever the character's colour is. It sits above
## the environment's HDR glow threshold of 1.0, which is what makes it bloom
## like the rest of the scene rather than sitting flat on top of it.
const STREAK_TEXT_COLOR := Color(2.3, 2.3, 2.3)

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
var is_game_over: bool = false
var is_intro: bool = false
var is_paused: bool = false
var high_score: int = 0
var _score_base_position: Vector2
var _streak_base_position: Vector2
var _shown_score: int = -1
## The streak the last landing reported. The player only sends the new value,
## so this is what makes a drop to zero distinguishable from never having had
## one.
var _last_streak: int = 0
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
var _toast_tween: Tween
var _toast_queue: Array[String] = []
var _streak_fade_tween: Tween
var _hud_nodes: Array[Control] = []
## Set from the pause menu and deliberately not saved: it is a per-run choice,
## so the next run starts with the readouts back. The pause button is exempt --
## see _set_hud_visible.
var _hud_hidden: bool = false
var _hud_home: Array[Vector2] = []
var _death_margin: float = 720.0
## A milestone popup pauses the run the same way the pause menu does, so the
## pause controls have to stay out of its way until it is answered.
var _milestone_open: bool = false

func _ready() -> void:
	_load_high_score()
	player.landed.connect(_on_player_landed)
	zones.zone_changed.connect(_on_zone_changed)
	zones.milestone_reached.connect(_on_milestone_reached)
	spawner.zones = zones
	_update_coin_label()
	Missions.completed.connect(_on_mission_completed)
	game_over_panel.hide()
	milestone_panel.hide()
	zone_banner.hide()
	_score_base_position = score_label.position
	_streak_base_position = streak_label.position
	var view := get_viewport_rect().size
	_death_margin = view.y / 2.0 + 80.0
	# The scene parks both at x=360, half of the base 720. Under `expand` a
	# tablet-shaped display is wider than that, so centring has to be measured
	# rather than assumed -- and it must happen before the intro starts, which
	# captures both positions as the origin for its whole flight.
	camera.global_position.x = view.x / 2.0
	player.global_position.x = view.x / 2.0
	_hud_nodes = [score_label, streak_label, pause_button, zone_label, coin_row]
	for node in _hud_nodes:
		_hud_home.append(node.position)
	_update_controls_icon()
	_update_sound_icon()
	_update_hud_icon()
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
	player.is_fast_falling = false
	_burst_climbing = true
	_score_origin_y = camera.global_position.y
	spawner.score_origin_y = _score_origin_y
	var reach: float = (player.velocity.y * player.velocity.y) / (2.0 * player.gravity)
	spawner.begin(player.global_position.y - reach * intro_platform_lead)
	Missions.begin_run()
	_drop_in_hud()

## Slides the HUD down into place instead of switching it on. Each element is
## parked above its home position and staggered, so it reads as arriving.
func _drop_in_hud() -> void:
	for i in range(_hud_nodes.size()):
		var node: Control = _hud_nodes[i]
		if _hud_hidden and node != pause_button:
			continue
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
	coin_label.add_theme_color_override("font_color", Settings.background_particle_color)
	# modulate, not self_modulate: UiOpacity owns self_modulate on every Control
	# under the UI layer, so the tint has to live on the other channel.
	coin_icon.modulate = Settings.background_particle_color
	UiOpacity.apply($UI)
	_update_pause_button_opacity()

func _unhandled_input(event: InputEvent) -> void:
	if is_intro:
		if event.is_pressed() and not event.is_echo():
			intro.skip()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not is_game_over and not _milestone_open:
		_toggle_pause()

func _on_pause_pressed() -> void:
	if is_game_over or _milestone_open:
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
		node.visible = shown and (node == pause_button or not _hud_hidden)

func _on_hud_pressed() -> void:
	Audio.play_ui_click()
	_hud_hidden = not _hud_hidden
	_update_hud_icon()
	_update_pause_button_opacity()
	if _hud_hidden:
		zone_banner.hide()

func _update_pause_button_opacity() -> void:
	pause_button.self_modulate = UiOpacity.tint(
		HIDDEN_PAUSE_OPACITY if _hud_hidden else Settings.ui_opacity)

func _update_hud_icon() -> void:
	hud_button.icon = HUD_HIDDEN_ICON if _hud_hidden else HUD_SHOWN_ICON

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

func _on_menu_pressed() -> void:
	Audio.play_ui_click()
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
		score_label.text = "SCORE %d" % score
		zones.update(score)
		Missions.update_run(_run_summary())
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
	run_max_streak = maxi(run_max_streak, streak)
	var broke := streak == 0 and _last_streak >= STREAK_FAIL_MIN
	_last_streak = streak
	_grow_to(score_label, 1.0 + STREAK_SCALE_STEP * clampi(streak, 0, STREAK_SCALE_CAP))
	if broke:
		_show_streak_message("FAILED", STREAK_FAIL_COLOR)
		Audio.vibrate(30)
	# Only a landing that actually extends the streak punches the counter --
	# ordinary jumps leave it sitting still.
	elif boosted and streak > 1:
		_show_streak_message("STREAK x%d" % streak, STREAK_TEXT_COLOR)
		_punch_streak(streak)
	if boosted:
		# `boosted` is already once per platform -- player.gd spends the
		# platform's boost on the landing that claims it, and a mistimed one
		# never spends it -- so the coin needs no separate guard.
		run_coins += 1
		run_flares += 1
		_update_coin_label()
		_punch_coin_label()
		Missions.update_run(_run_summary())
		_spawn_burst(platform)
		_camera_punch()
		_glow_pulse(Settings.glow_strength + PUNCH_GLOW_BONUS)
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
func _show_streak_message(text: String, color: Color) -> void:
	if streak_label.text != text:
		streak_label.text = text
	streak_label.add_theme_color_override("font_color", color)
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	streak_label.scale = Vector2.ONE
	_flash_streak()

## Brings the counter up and then takes it away. Restarted by every streak, so
## back-to-back streaks hold it on screen continuously instead of blinking it
## off between them.
func _flash_streak() -> void:
	if _streak_fade_tween != null and _streak_fade_tween.is_valid():
		_streak_fade_tween.kill()
	streak_label.modulate.a = 1.0
	_streak_fade_tween = create_tween()
	_streak_fade_tween.tween_interval(STREAK_SHOW_TIME)
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

func _glow_pulse(peak: float) -> void:
	var env := world_environment.environment
	env.glow_intensity = peak
	var tw := create_tween()
	tw.tween_property(env, "glow_intensity", Settings.glow_strength, 0.25).set_trans(Tween.TRANS_SINE)

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

## The zone label is the always-on reading; the banner is the moment it
## changes. The opening stretch forces nothing, so it gets the label but no
## announcement -- there is no new rule to announce.
func _run_summary() -> Dictionary:
	return {
		"score": score,
		"max_streak": run_max_streak,
		"flares": run_flares,
		"coins": run_coins,
		"stage": zones.stage_for_score(score),
	}

## Left edge at a quarter height, deliberately clear of the character's lane and
## of anywhere a thumb rests. The label is MOUSE_FILTER_IGNORE, so even sitting
## over the play area it cannot swallow the tap that times a landing.
func _on_mission_completed(_id: String, reward: int, text: String) -> void:
	# Nothing is shown once the run is over -- the death screen is not the place
	# for it -- and a hidden HUD stays hidden.
	if is_game_over or _hud_hidden:
		return
	_toast_queue.append("MISSION COMPLETE  +%d\n%s" % [reward, text])
	if _toast_tween == null or not _toast_tween.is_valid():
		_show_next_toast()

func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		mission_toast.visible = false
		return
	mission_toast.text = _toast_queue.pop_front()
	mission_toast.modulate.a = 0.0
	mission_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_property(mission_toast, "modulate:a", 1.0, TOAST_IN)
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(mission_toast, "modulate:a", 0.0, TOAST_OUT)
	_toast_tween.tween_callback(_show_next_toast)

## Same shape as _punch_streak, minus the shake and the hold.
func _punch_coin_label() -> void:
	coin_row.pivot_offset = coin_row.size / 2.0
	coin_row.scale = Vector2.ONE * COIN_PUNCH_SCALE
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	_coin_tween = create_tween()
	_coin_tween.tween_property(coin_row, "scale", Vector2.ONE, COIN_SETTLE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_coin_label() -> void:
	coin_label.text = "%d" % run_coins

func _on_zone_changed(stage: int, zone_name: String) -> void:
	zone_label.text = "ZONE %d  %s" % [stage + 1, zone_name]
	if stage == 0:
		return
	if _hud_hidden:
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
		milestone_title.text = "GRAVITY BROKEN"
		milestone_body.text = "You escaped Solar gravity.\nThat was the whole point.\n\nStop here and take the score, or keep\nclimbing -- the zones start stacking."
	else:
		Stats.mark_true_ending()
		milestone_title.text = "TRUE ENDING"
		milestone_body.text = "Every zone, in every combination, cleared.\nThere is nothing left to throw at you.\n\nAll four zones from here on. See how\nlong you last."
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

func _on_milestone_end_pressed() -> void:
	Audio.play_ui_click()
	_milestone_open = false
	milestone_panel.hide()
	_game_over()

func _game_over() -> void:
	is_game_over = true
	Audio.fade_to_menu_music()
	Audio.vibrate(60)
	if score > high_score:
		high_score = score
		_save_high_score()
	Stats.record_run(score, run_max_streak, run_coins)
	# After record_run, so a mission payout lands on a balance that already
	# includes the coins this run earned.
	var summary := _run_summary()
	summary["finished"] = true
	Missions.end_run(summary)
	result_label.text = "SCORE %d   BEST %d" % [score, high_score]
	_set_hud_visible(false)
	get_tree().paused = true
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
	get_tree().paused = false
	Transition.reload_scene()
