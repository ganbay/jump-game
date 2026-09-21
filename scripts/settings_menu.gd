extends Node2D

## What is left after the customization screen took the shapes and colours:
## the options that change how the game plays or how hard it is on the eyes.
##
## Each row keeps a word naming the setting and swaps only the glyph beside it
## for the state -- the same split the glow row already uses. Three bare icons
## in a column would say what each option is set to but not what it is.

const CONTROLS_TOUCH_ICON := preload("res://assets/icons/hand.svg")
const CONTROLS_TILT_ICON := preload("res://assets/icons/mobile_phone.svg")
const SOUND_ON_ICON := preload("res://assets/icons/speaker.svg")
const SOUND_OFF_ICON := preload("res://assets/icons/speaker_mute.svg")
const HAPTICS_ON_ICON := preload("res://assets/icons/signal_wave.svg")
const HAPTICS_OFF_ICON := preload("res://assets/icons/no_symbol.svg")
const HINTS_ON_ICON := preload("res://assets/icons/help.svg")
const HINTS_OFF_ICON := preload("res://assets/icons/no_symbol.svg")

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var glow_slider: HSlider = $UI/GlowSlider
@onready var opacity_slider: HSlider = $UI/OpacitySlider
@onready var controls_button: Button = $UI/ControlsButton
@onready var sensitivity_label: Label = $UI/SensitivityLabel
@onready var sensitivity_slider: HSlider = $UI/SensitivitySlider
@onready var sound_button: Button = $UI/SoundButton
@onready var haptics_button: Button = $UI/HapticsButton
@onready var hints_button: Button = $UI/HintsButton
@onready var score_align_button: Button = $UI/ScoreAlignButton
@onready var privacy_button: Button = $UI/PrivacyButton
@onready var privacy_panel: ColorRect = $UI/PrivacyPanel

func _ready() -> void:
	glow_slider.value = Settings.glow_strength
	opacity_slider.value = Settings.ui_opacity
	_update_controls_icon()
	# The slider's range comes from Settings rather than the scene, so widening
	# or narrowing the allowed sensitivities is a one-place change and a saved
	# value from an older range can never sit outside the handle's travel.
	sensitivity_slider.min_value = Settings.SENSITIVITY_MIN
	sensitivity_slider.max_value = Settings.SENSITIVITY_MAX
	_update_sensitivity_row()
	_update_sound_icon()
	_update_haptics_icon()
	_update_hints_icon()
	_update_score_align_text()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	IconPop.attach([controls_button, sound_button, haptics_button, hints_button,
		score_align_button, privacy_button, $UI/BackButton])

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)

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
	_update_sensitivity_row()

## One slider, bound to whichever scheme is active, so the row always tunes the
## controls the player is actually using.
func _update_sensitivity_row() -> void:
	var tilt := Settings.control_scheme == Settings.ControlScheme.TILT
	sensitivity_label.text = "TILT SENSITIVITY" if tilt else "DRAG SENSITIVITY"
	sensitivity_slider.set_value_no_signal(
		Settings.tilt_sensitivity if tilt else Settings.touch_sensitivity)

func _on_sensitivity_slider_value_changed(value: float) -> void:
	if Settings.control_scheme == Settings.ControlScheme.TILT:
		Settings.set_tilt_sensitivity(value)
	else:
		Settings.set_touch_sensitivity(value)

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

## The in-run coaching (see game.gd's tutorial section). Off is the same
## crossed-out glyph the haptics row uses for its off state, so the two
## switches read as the same kind of switch.
func _on_hints_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_tutorial_hints()
	_update_hints_icon()

func _update_hints_icon() -> void:
	hints_button.icon = HINTS_ON_ICON if Settings.tutorial_hints else HINTS_OFF_ICON

## A word rather than a glyph: no icon says "left" versus "centre" for a
## number as plainly as the words do.
func _on_score_align_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_score_align()
	_update_score_align_text()

func _update_score_align_text() -> void:
	score_align_button.text = ("LEFT"
		if Settings.score_align == Settings.ScoreAlign.LEFT else "CENTER")

func _on_privacy_pressed() -> void:
	Audio.play_ui_click()
	privacy_panel.visible = true

func _on_privacy_close_pressed() -> void:
	Audio.play_ui_click()
	privacy_panel.visible = false

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
