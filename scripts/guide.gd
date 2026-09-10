extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment

func _ready() -> void:
	Stats.mark_tutorial_seen()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _on_play_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
