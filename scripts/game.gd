extends Node2D

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var score_label: Label = $UI/ScoreLabel
@onready var streak_label: Label = $UI/StreakLabel
@onready var best_label: Label = $UI/BestLabel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var result_label: Label = $UI/GameOverPanel/ResultLabel
@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_button: Button = $UI/PauseButton
@onready var controls_button: Button = $UI/PausePanel/ControlsButton
@onready var intro: IntroSequence = $IntroSequence
@onready var spawner: Node2D = $PlatformSpawner
@onready var speed_label: Label = $UI/SpeedLabel

const PUNCH_GLOW_BONUS := 0.7
const BURST_COLOR := Color(1.15, 1.15, 1.2)
const SAVE_PATH := "user://highscore.cfg"
const STREAK_SCALE_STEP := 0.1
const STREAK_SCALE_CAP := 10
const VIBRATE_AMOUNT := 8.0
const HUD_DROP_HEIGHT := 240.0
const HUD_DROP_TIME := 0.55
const HUD_DROP_STAGGER := 0.07

## Where the first platform is seeded, as a fraction of how far the handoff
## speed can actually carry the character. Derived from the speed rather than
## fixed, so retuning the intro's flight cannot make the opening unlandable.
@export var intro_platform_lead: float = 0.76

var score: int = 0
var max_height: float = 0.0
var run_max_streak: int = 0
var is_game_over: bool = false
var is_intro: bool = false
var is_paused: bool = false
var high_score: int = 0
var _score_base_position: Vector2
var _streak_base_position: Vector2
var _shown_score: int = -1
var _shown_speed: int = 999999
## Height gained on the launch burst is free, so scoring is measured from where
## that burst tops out rather than from the launch point.
var _score_origin_y: float = 0.0
var _burst_climbing: bool = false
var _hud_nodes: Array[Control] = []
var _hud_home: Array[Vector2] = []
var _death_margin: float = 720.0

func _ready() -> void:
	_load_high_score()
	best_label.text = "BEST %d" % high_score
	player.landed.connect(_on_player_landed)
	game_over_panel.hide()
	_score_base_position = score_label.position
	_streak_base_position = streak_label.position
	_death_margin = get_viewport_rect().size.y / 2.0 + 80.0
	_hud_nodes = [score_label, streak_label, best_label, speed_label, pause_button]
	for node in _hud_nodes:
		_hud_home.append(node.position)
	_update_controls_label()
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
	var reach: float = (player.velocity.y * player.velocity.y) / (2.0 * player.gravity)
	spawner.begin(player.global_position.y - reach * intro_platform_lead)
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

func _unhandled_input(event: InputEvent) -> void:
	if is_intro:
		if event.is_pressed() and not event.is_echo():
			intro.skip()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not is_game_over:
		_toggle_pause()

func _on_pause_pressed() -> void:
	if is_game_over:
		return
	Audio.play_ui_click()
	_toggle_pause()

func _on_resume_pressed() -> void:
	Audio.play_ui_click()
	_toggle_pause()

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_panel.visible = is_paused
	_set_hud_visible(not is_paused)
	if is_paused:
		Audio.fade_to_menu_music()
	else:
		Audio.fade_to_gameplay_music()

func _set_hud_visible(shown: bool) -> void:
	for node in _hud_nodes:
		node.visible = shown

func _on_controls_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_control_scheme()
	_update_controls_label()

func _update_controls_label() -> void:
	controls_button.text = "CONTROLS: %s" % Settings.control_scheme_name()

func _on_menu_pressed() -> void:
	Audio.play_ui_click()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("scores", "high_score", 0)

func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)

func _process(_delta: float) -> void:
	if is_game_over or is_intro:
		return
	camera.global_position.y = min(camera.global_position.y, player.global_position.y)
	if _burst_climbing:
		if player.velocity.y < 0.0:
			_score_origin_y = camera.global_position.y
		else:
			_burst_climbing = false  # apex of the launch; the run scores from here
	max_height = max(max_height, _score_origin_y - camera.global_position.y)
	score = int(max_height / 10.0)
	_update_speed_readout()
	# Assigning Label.text re-shapes the text server run even when the string is
	# identical, so only touch it when the number actually moved.
	if score != _shown_score:
		_shown_score = score
		score_label.text = "SCORE %d" % score
	if player.global_position.y > camera.global_position.y + _death_margin:
		_game_over()

## Positive climbing, negative falling -- the sign is flipped from engine space,
## where +y points down. Quantised to 10 so the label is not re-shaped on every
## single frame; assigning Label.text rebuilds the text server run each time.
func _update_speed_readout() -> void:
	var shown := roundi(-player.velocity.y / 10.0) * 10
	if shown != _shown_speed:
		_shown_speed = shown
		speed_label.text = str(shown)

func _on_player_landed(platform: Node, counts: bool, streak: int) -> void:
	run_max_streak = maxi(run_max_streak, streak)
	streak_label.text = "STREAK x%d" % streak if streak > 1 else ""
	var target_scale := 1.0 + STREAK_SCALE_STEP * clampi(streak, 0, STREAK_SCALE_CAP)
	_grow_to(score_label, target_scale)
	_grow_to(streak_label, target_scale)
	if counts:
		_spawn_burst(platform)
		_camera_punch()
		_glow_pulse(Settings.glow_strength + PUNCH_GLOW_BONUS)
		_vibrate(score_label, _score_base_position)
		_vibrate(streak_label, _streak_base_position)

func _spawn_burst(platform: Node) -> void:
	var burst := preload("res://scenes/landing_burst.tscn").instantiate()
	burst.color = Settings.get_platform_color(platform.type) if platform is Platform else BURST_COLOR
	add_child(burst)
	burst.global_position = platform.global_position

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

func _game_over() -> void:
	is_game_over = true
	Audio.fade_to_menu_music()
	if score > high_score:
		high_score = score
		_save_high_score()
	Stats.record_run(score, run_max_streak)
	best_label.text = "BEST %d" % high_score
	result_label.text = "SCORE %d   BEST %d" % [score, high_score]
	_set_hud_visible(false)
	game_over_panel.show()
	get_tree().paused = true

func _on_restart_pressed() -> void:
	Audio.play_ui_click()
	get_tree().paused = false
	get_tree().reload_current_scene()
