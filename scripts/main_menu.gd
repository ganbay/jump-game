extends Node2D

## The whole screen is the play button -- the icon buttons are the only things
## that intercept a tap. Nothing here is labelled except the title and the tap
## prompt, so the icons have to carry their own meaning: cart = what you can put
## on the character, bars = your runs, tick = today's missions, ? = the guide,
## gear = settings, and the speaker in the corner mutes the whole game.

## The mute toggle swaps its glyph rather than tinting one, so the state reads
## at a glance instead of asking the player to remember which shade means off.
const SOUND_ON_ICON := preload("res://assets/icons/audioOn.png")
const SOUND_OFF_ICON := preload("res://assets/icons/audioOff.png")

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var tap_icon: TextureRect = $UI/TapIcon
@onready var tap_label: Label = $UI/TapLabel
@onready var sound_button: Button = $UI/SoundButton
@onready var _icon_buttons: Array[Node] = [$UI/SoundButton,
	$UI/CustomizeButton, $UI/StatisticsButton, $UI/MissionsButton,
	$UI/GuideButton, $UI/SettingsButton]

## Every leave path goes through Transition, whose fade takes a moment. Without
## this the tap that lands during a fade -- or the emulated mouse click that
## follows every real touch -- queues a second scene change on top of the first.
var _leaving: bool = false

func _ready() -> void:
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	Audio.play_menu_music()
	_update_sound_icon()
	# Driven off the signal rather than only off the press, so the icon is still
	# right after the settings screen changes it and hands the menu back.
	Settings.sound_muted_changed.connect(_on_sound_muted_changed)
	IconPop.pulse(tap_icon, tap_label)
	IconPop.attach(_icon_buttons)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	UiOpacity.apply($UI)

func _on_sound_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_sound_muted()

func _on_sound_muted_changed(_muted: bool) -> void:
	_update_sound_icon()

func _update_sound_icon() -> void:
	sound_button.icon = SOUND_OFF_ICON if Settings.sound_muted else SOUND_ON_ICON

## Only reaches here when nothing in the UI took the press first, so a tap on
## one of the bottom icons never also starts a run.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		_play()

func _play() -> void:
	_go("res://scenes/main.tscn" if Stats.tutorial_seen else "res://scenes/guide.tscn")

func _on_guide_pressed() -> void:
	_go("res://scenes/guide.tscn")

func _on_customize_pressed() -> void:
	_go("res://scenes/customization.tscn")

func _on_settings_pressed() -> void:
	_go("res://scenes/settings.tscn")

func _on_statistics_pressed() -> void:
	_go("res://scenes/statistics.tscn")

func _on_missions_pressed() -> void:
	_go("res://scenes/missions.tscn")

func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play_ui_click()
	Transition.change_scene(path)
