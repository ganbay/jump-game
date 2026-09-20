extends Node2D

## The open middle of the screen (PlayZone) is the play button: everything from
## under the title down to just above the icon row. Taps on the title, in the
## corners or near the bottom edge start nothing, so a stray touch or a home
## swipe from the gesture bar does not launch a run. Nothing here is labelled
## except the title and the tap prompt, so the icons have to carry their own
## meaning: cart = what you can put on the character, bars = your runs, ? = the
## guide, gear = settings, and the speaker in the corner mutes the whole game.

## The mute toggle swaps its glyph rather than tinting one, so the state reads
## at a glance instead of asking the player to remember which shade means off.
const SOUND_ON_ICON := preload("res://assets/icons/speaker.svg")
const SOUND_OFF_ICON := preload("res://assets/icons/speaker_mute.svg")

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var tap_icon: TextureRect = $UI/TapIcon
@onready var tap_label: Label = $UI/TapLabel
@onready var sound_button: Button = $UI/SoundButton
## Invisible and MOUSE_FILTER_IGNORE: only its rect is read, so it never takes
## a press away from the buttons or from _unhandled_input.
@onready var play_zone: Control = $UI/PlayZone
@onready var _icon_buttons: Array[Node] = [$UI/SoundButton, $UI/ScienceButton,
	$UI/CustomizeButton, $UI/StatisticsButton,
	$UI/GuideButton, $UI/SettingsButton]

## Every leave path goes through Transition, whose fade takes a moment. Without
## this the tap that lands during a fade -- or the emulated mouse click that
## follows every real touch -- queues a second scene change on top of the first.
var _leaving: bool = false

## True between a press and its release. The run starts on the release, not the
## initial touch, so a finger put down on the menu can still be lifted without
## committing to a run -- and a release arriving on its own (a finger already
## down as this screen loads) starts nothing.
var _pressed: bool = false

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
	# _leaving is only ever cleared by actually leaving, so a scene that fails
	# to load would otherwise strand the menu with every button dead.
	Transition.scene_change_failed.connect(_on_scene_change_failed)

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)

func _on_sound_pressed() -> void:
	Audio.play_ui_click()
	Settings.toggle_sound_muted()

func _on_sound_muted_changed(_muted: bool) -> void:
	_update_sound_icon()

func _update_sound_icon() -> void:
	sound_button.icon = SOUND_OFF_ICON if Settings.sound_muted else SOUND_ON_ICON

## Only reaches here when nothing in the UI took the press first, so a tap on
## one of the bottom icons never also starts a run.
##
## The event types are named rather than leaning on is_pressed()/is_released(),
## because InputEvent.is_released() is defined as "not is_pressed()" on the base
## class -- so every mouse motion would read as a release and start a run.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton
			or event is InputEventKey):
		return
	if event.is_echo():
		return
	# Android delivers the hardware volume and back buttons as key events too,
	# so only the accept keys (Space/Enter) may start a run.
	if event is InputEventKey and not event.is_action("ui_accept"):
		return
	# Keys carry no position and still play from anywhere.
	var in_zone := event is InputEventKey \
		or play_zone.get_global_rect().has_point(event.position)
	if event.is_pressed():
		_pressed = in_zone
	elif _pressed:
		_pressed = false
		# Dragging out of the zone before lifting cancels, like a button.
		if in_zone:
			_play()

func _play() -> void:
	_go("res://scenes/main.tscn" if Stats.tutorial_seen else "res://scenes/guide.tscn")

func _on_guide_pressed() -> void:
	_go("res://scenes/guide.tscn")

func _on_customize_pressed() -> void:
	_go("res://scenes/customization.tscn")

func _on_science_pressed() -> void:
	_go("res://scenes/science.tscn")

func _on_settings_pressed() -> void:
	_go("res://scenes/settings.tscn")

func _on_statistics_pressed() -> void:
	_go("res://scenes/statistics.tscn")

func _on_scene_change_failed(_path: String) -> void:
	_leaving = false

func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play_ui_click()
	Transition.change_scene(path)
