extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var glow_slider: HSlider = $UI/GlowSlider
@onready var controls_button: Button = $UI/ControlsButton
@onready var bg_fx_button: Button = $UI/BgFxButton
@onready var bg_color_swatch: RoundedRect = $BgColorSwatch
@onready var bg_color_picker: ColorPickerButton = $UI/BgColorPicker
@onready var player_swatch: RoundedRect = $PlayerSwatch
@onready var player_picker: ColorPickerButton = $UI/PlayerPicker
@onready var platform_swatches: Dictionary = {
	Platform.Type.STILL: $StillSwatch,
	Platform.Type.MOVING: $MovingSwatch,
	Platform.Type.BOOST: $BoostSwatch,
	Platform.Type.ONE_TIME: $OneTimeSwatch,
}
@onready var platform_pickers: Dictionary = {
	Platform.Type.STILL: $UI/StillPicker,
	Platform.Type.MOVING: $UI/MovingPicker,
	Platform.Type.BOOST: $UI/BoostPicker,
	Platform.Type.ONE_TIME: $UI/OneTimePicker,
}

func _ready() -> void:
	glow_slider.value = Settings.glow_strength
	player_picker.color = Settings.player_color
	for type in platform_pickers:
		platform_pickers[type].color = Settings.get_platform_color(type)
	bg_color_picker.color = Settings.background_particle_color
	_update_controls_label()
	_update_bg_fx_label()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	player_swatch.color = Settings.player_color
	for type in platform_swatches:
		platform_swatches[type].color = Settings.get_platform_color(type)
	bg_color_swatch.color = Settings.background_particle_color

func _on_glow_slider_value_changed(value: float) -> void:
	Settings.set_glow_strength(value)

func _on_bg_fx_button_pressed() -> void:
	Audio.play_ui_click()
	Settings.cycle_background_fx()
	_update_bg_fx_label()

func _update_bg_fx_label() -> void:
	bg_fx_button.text = "BG PARTICLES: %s" % Settings.background_fx_name()

func _on_bg_color_picker_color_changed(color: Color) -> void:
	Settings.set_background_particle_color(color)

func _on_player_picker_color_changed(color: Color) -> void:
	Settings.set_player_color(color)

func _on_still_picker_color_changed(color: Color) -> void:
	Settings.set_platform_color(Platform.Type.STILL, color)

func _on_moving_picker_color_changed(color: Color) -> void:
	Settings.set_platform_color(Platform.Type.MOVING, color)

func _on_boost_picker_color_changed(color: Color) -> void:
	Settings.set_platform_color(Platform.Type.BOOST, color)

func _on_one_time_picker_color_changed(color: Color) -> void:
	Settings.set_platform_color(Platform.Type.ONE_TIME, color)

func _on_controls_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_control_scheme()
	_update_controls_label()

func _update_controls_label() -> void:
	controls_button.text = "CONTROLS: %s" % Settings.control_scheme_name()

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
