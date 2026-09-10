extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment

func _ready() -> void:
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	Audio.play_menu_music()

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _on_play_pressed() -> void:
	Audio.play_ui_click()
	if Stats.tutorial_seen:
		Transition.change_scene("res://scenes/main.tscn")
	else:
		Transition.change_scene("res://scenes/guide.tscn")

func _on_guide_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/guide.tscn")

func _on_customize_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/customization.tscn")

func _on_settings_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/settings.tscn")

func _on_statistics_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/statistics.tscn")
