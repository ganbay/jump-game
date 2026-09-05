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

const BASE_GLOW_INTENSITY := 0.4
const PUNCH_GLOW_INTENSITY := 1.1
const BURST_COLOR := Color(1.15, 1.15, 1.2)
const SAVE_PATH := "user://highscore.cfg"
const STREAK_SCALE_STEP := 0.1
const STREAK_SCALE_CAP := 10
const VIBRATE_AMOUNT := 8.0
const SCORE_BASE_FONT_SIZE := 28
const STREAK_BASE_FONT_SIZE := 22

var score: int = 0
var streak_bonus: int = 0
var max_height: float = 0.0
var is_game_over: bool = false
var is_paused: bool = false
var high_score: int = 0
var _score_base_position: Vector2
var _streak_base_position: Vector2

func _ready() -> void:
	_load_high_score()
	best_label.text = "BEST %d" % high_score
	player.landed.connect(_on_player_landed)
	game_over_panel.hide()
	_score_base_position = score_label.position
	_streak_base_position = streak_label.position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_game_over:
		_toggle_pause()

func _on_pause_pressed() -> void:
	if is_game_over:
		return
	_toggle_pause()

func _on_resume_pressed() -> void:
	_toggle_pause()

func _toggle_pause() -> void:
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_panel.visible = is_paused
	_set_hud_visible(not is_paused)

func _set_hud_visible(shown: bool) -> void:
	score_label.visible = shown
	streak_label.visible = shown
	best_label.visible = shown
	pause_button.visible = shown

func _on_menu_pressed() -> void:
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
	score = int(max_height / 10.0) + streak_bonus
	score_label.text = "SCORE %d" % score
	var death_margin := get_viewport_rect().size.y / 2.0 + 80.0
	if player.global_position.y > camera.global_position.y + death_margin:
		_game_over()

func _on_player_landed(platform: Node, counts: bool, streak: int) -> void:
	streak_label.text = "STREAK x%d" % streak if streak > 1 else ""
	var target_scale := 1.0 + STREAK_SCALE_STEP * clampi(streak, 0, STREAK_SCALE_CAP)
	_grow_to(score_label, SCORE_BASE_FONT_SIZE, target_scale)
	_grow_to(streak_label, STREAK_BASE_FONT_SIZE, target_scale)
	if counts:
		streak_bonus += 10 * streak
		_spawn_burst(platform.global_position)
		_camera_punch()
		_glow_pulse(PUNCH_GLOW_INTENSITY)
		_vibrate(score_label, _score_base_position)
		_vibrate(streak_label, _streak_base_position)

func _spawn_burst(pos: Vector2) -> void:
	var burst := preload("res://scenes/landing_burst.tscn").instantiate()
	burst.color = BURST_COLOR
	add_child(burst)
	burst.global_position = pos

func _camera_punch() -> void:
	camera.zoom = Vector2(0.97, 0.97)
	var tw := create_tween()
	tw.tween_property(camera, "zoom", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)

func _glow_pulse(peak: float) -> void:
	var env := world_environment.environment
	env.glow_intensity = peak
	var tw := create_tween()
	tw.tween_property(env, "glow_intensity", BASE_GLOW_INTENSITY, 0.25).set_trans(Tween.TRANS_SINE)

func _grow_to(label: Label, base_font_size: int, target_scale: float) -> void:
	var target_size := int(round(base_font_size * target_scale))
	var tw := create_tween()
	tw.tween_property(label, "theme_override_font_sizes/font_size", target_size, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _vibrate(label: Label, base_pos: Vector2) -> void:
	var tw := create_tween()
	for i in range(6):
		var offset := Vector2(randf_range(-VIBRATE_AMOUNT, VIBRATE_AMOUNT), randf_range(-VIBRATE_AMOUNT, VIBRATE_AMOUNT))
		tw.tween_property(label, "position", base_pos + offset, 0.03)
	tw.tween_property(label, "position", base_pos, 0.03)

func _game_over() -> void:
	is_game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
	best_label.text = "BEST %d" % high_score
	result_label.text = "SCORE %d   BEST %d" % [score, high_score]
	_set_hud_visible(false)
	game_over_panel.show()
	get_tree().paused = true

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
