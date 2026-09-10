extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var glow_slider: HSlider = $UI/GlowSlider
@onready var controls_button: Button = $UI/ControlsButton
@onready var bg_fx_button: Button = $UI/BgFxButton
@onready var bg_color_swatch: RoundedRect = $BgColorSwatch
@onready var bg_color_picker: ColorPickerButton = $UI/BgColorPicker
@onready var plasma_swatch: PlasmaBlob = $PlasmaSwatch
@onready var character_button: Button = $UI/CharacterButton
@onready var trail_button: Button = $UI/TrailButton
@onready var player_picker: ColorPickerButton = $UI/PlayerPicker
@onready var platform_swatch: RoundedRect = $PlatformSwatch
@onready var platform_picker: ColorPickerButton = $UI/PlatformPicker

func _ready() -> void:
	glow_slider.value = Settings.glow_strength
	player_picker.color = Settings.player_color
	platform_picker.color = Settings.platform_color
	bg_color_picker.color = Settings.background_particle_color
	_update_controls_label()
	_update_bg_fx_label()
	_update_character_label()
	_update_trail_label()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	# The swatch previews whichever skin is selected, so the character toggle
	# can be judged here rather than by starting a run.
	plasma_swatch.shape = Player.SKIN_SHAPES.get(
		Settings.player_skin, PlasmaBlob.Shape.DOME)
	plasma_swatch.color = Settings.player_color
	platform_swatch.color = Settings.platform_color
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

func _on_platform_picker_color_changed(color: Color) -> void:
	Settings.set_platform_color(color)

func _on_character_pressed() -> void:
	Audio.play_ui_click()
	Settings.cycle_player_skin()
	_update_character_label()

func _update_character_label() -> void:
	character_button.text = "CHARACTER: %s" % Settings.player_skin_name()

func _on_trail_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_trail()
	_update_trail_label()

func _update_trail_label() -> void:
	trail_button.text = "TRAIL: %s" % Settings.trail_name()

func _on_controls_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_control_scheme()
	_update_controls_label()

func _update_controls_label() -> void:
	controls_button.text = "CONTROLS: %s" % Settings.control_scheme_name()

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
