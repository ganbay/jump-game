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

const PUNCH_GLOW_BONUS := 0.7
const BURST_COLOR := Color(1.15, 1.15, 1.2)
const SAVE_PATH := "user://highscore.cfg"
const STREAK_SCALE_STEP := 0.1
const STREAK_SCALE_CAP := 10
const VIBRATE_AMOUNT := 8.0

var score: int = 0
var max_height: float = 0.0
var run_max_streak: int = 0
var is_game_over: bool = false
var is_paused: bool = false
var high_score: int = 0
var _score_base_position: Vector2
var _streak_base_position: Vector2
var _shown_score: int = -1
var _death_margin: float = 720.0

func _ready() -> void:
	_load_high_score()
	best_label.text = "BEST %d" % high_score
	player.landed.connect(_on_player_landed)
	game_over_panel.hide()
	_score_base_position = score_label.position
	_streak_base_position = streak_label.position
	_death_margin = get_viewport_rect().size.y / 2.0 + 80.0
	_update_controls_label()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	Audio.play_music()

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _unhandled_input(event: InputEvent) -> void:
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
	score_label.visible = shown
	streak_label.visible = shown
	best_label.visible = shown
	pause_button.visible = shown

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
	if is_game_over:
		return
	camera.global_position.y = min(camera.global_position.y, player.global_position.y)
	max_height = max(max_height, -camera.global_position.y)
	score = int(max_height / 10.0)
	# Assigning Label.text re-shapes the text server run even when the string is
	# identical, so only touch it when the number actually moved.
	if score != _shown_score:
		_shown_score = score
		score_label.text = "SCORE %d" % score
	if player.global_position.y > camera.global_position.y + _death_margin:
		_game_over()

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
