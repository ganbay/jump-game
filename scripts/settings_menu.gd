extends Node2D

## What is left after the customization screen took the shapes and colours:
## the options that change how the game plays or how hard it is on the eyes.

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var glow_slider: HSlider = $UI/GlowSlider
@onready var controls_button: Button = $UI/ControlsButton

func _ready() -> void:
	glow_slider.value = Settings.glow_strength
	_update_controls_label()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _on_glow_slider_value_changed(value: float) -> void:
	Settings.set_glow_strength(value)

func _on_controls_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_control_scheme()
	_update_controls_label()

func _update_controls_label() -> void:
	controls_button.text = "CONTROLS: %s" % Settings.control_scheme_name()

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
