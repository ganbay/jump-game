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
const BACKDROP_SHADER := preload("res://shaders/zone_backdrop.gdshader")

## The zone the menu last wore. Static because the menu is freed and rebuilt on
## every return to it, and a per-instance var could not remember what the last
## visit showed -- which is exactly what a fresh roll has to avoid repeating.
static var _last_zone: int = ZoneAmbience.NONE

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var background: ColorRect = $BackgroundLayer/Background
@onready var background_particles: BackgroundParticles = $BackgroundLayer/BackgroundParticles
@onready var title_label: Label = $UI/TitleLabel
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

## Which zone's sky this visit is wearing, rolled in _ready.
var _zone: int = ZoneAmbience.OPENING

func _ready() -> void:
	# Before _apply_visual_settings, which tints the title from _zone.
	_roll_backdrop()
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

## The menu wears one of the zones' skies, re-rolled on every load -- so the
## screen a run ends on is never the screen the next one starts from, and the
## four zones get seen between runs as well as during them.
##
## Open space is in the draw alongside the four zones -- it is a sky in its own
## right, and the one the game has always looked like, so leaving it out would
## make the menu the only screen that never shows it.
##
## The previous visit's choice is handed over to be avoided, so the sky always
## visibly changes. Its own drift profile comes along: a deep blue backdrop
## behind a field of white dots would read as half-dressed.
func _roll_backdrop() -> void:
	_zone = ZoneAmbience.pick_any(_last_zone)
	_last_zone = _zone
	var profile: Dictionary = ZoneAmbience.resolved_profile(_zone)
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	mat.set_shader_parameter("top_color", profile["bg_top"])
	mat.set_shader_parameter("bottom_color", profile["bg_bottom"])
	background.material = mat
	# Crossfades from the opening profile the field starts on, so the sky
	# arrives over the menu's own fade-in rather than being there first.
	background_particles.blend_to(profile)

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	# After UiAccent, never before: the title is in its group, so the accent
	# walk would otherwise paint the zone straight back out of it. Only the
	# title -- the subtitle and every icon stay on the character colour, so the
	# zone reads as one deliberate accent rather than as a reskin of the menu.
	title_label.add_theme_color_override("font_color",
		ZoneAmbience.tint_toward(UiAccent.color(), _zone, ZoneAmbience.TITLE_TINT))

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
