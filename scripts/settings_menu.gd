extends Node2D

## What is left after the customization screen took the shapes and colours:
## the options that change how the game plays or how hard it is on the eyes.
##
## Each row keeps a word naming the setting and swaps only the glyph beside it
## for the state -- the same split the glow row already uses. Three bare icons
## in a column would say what each option is set to but not what it is.

const CONTROLS_TOUCH_ICON := preload("res://assets/icons/joystick.png")
const CONTROLS_TILT_ICON := preload("res://assets/icons/phone.png")
const SOUND_ON_ICON := preload("res://assets/icons/audioOn.png")
const SOUND_OFF_ICON := preload("res://assets/icons/audioOff.png")
const HAPTICS_ON_ICON := preload("res://assets/icons/checkmark.png")
const HAPTICS_OFF_ICON := preload("res://assets/icons/cross.png")

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var glow_slider: HSlider = $UI/GlowSlider
@onready var opacity_slider: HSlider = $UI/OpacitySlider
@onready var controls_button: Button = $UI/ControlsButton
@onready var sound_button: Button = $UI/SoundButton
@onready var haptics_button: Button = $UI/HapticsButton

func _ready() -> void:
	glow_slider.value = Settings.glow_strength
	opacity_slider.value = Settings.ui_opacity
	_update_controls_icon()
	_update_sound_icon()
	_update_haptics_icon()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	IconPop.attach([controls_button, sound_button, haptics_button, $UI/BackButton])

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	UiOpacity.apply($UI)

func _on_glow_slider_value_changed(value: float) -> void:
	Settings.set_glow_strength(value)

## Writes straight through, so the whole screen -- this slider's own row
## included -- redraws at the new opacity as the handle moves.
func _on_opacity_slider_value_changed(value: float) -> void:
	Settings.set_ui_opacity(value)

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

func _on_haptics_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_haptics_enabled()
	_update_haptics_icon()

func _update_haptics_icon() -> void:
	haptics_button.icon = HAPTICS_ON_ICON if Settings.haptics_enabled else HAPTICS_OFF_ICON

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
