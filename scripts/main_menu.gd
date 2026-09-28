extends Node2D

## The open middle of the screen (PlayZone) is the play button: everything from
## under the title down to just above the icon row. Taps on the title, in the
## corners or near the bottom edge start nothing, so a stray touch or a home
## swipe from the gesture bar does not launch a run. Nothing here is labelled
## except the title and the tap prompt, so the icons have to carry their own
## meaning: cart = what you can put on the character, bars = your runs, ? = the
## guide, gear = settings, and the speaker in the corner mutes the whole game.
##
## The mode picker sits in the middle of the play zone: swipe left or right
## anywhere in the zone (or use the arrows, or the arrow keys) to switch
## between CASUAL and RACE, and the same tap-to-play then starts whichever is
## showing. RACE goes to the race screen first to pick the AI and distance.
## Until Race.is_unlocked(), RACE can still be swiped to -- so the player
## learns it exists -- but shows a padlock in place of the play glyph and a
## count of casual runs left, and a tap only shakes it.
##
## Two things about races are told here, since the menu is where the player
## lands between sessions: a line under the prompt while the day's free
## tickets are waiting (see Race.daily_available), and a popup for each race
## AI opened since the last visit (see Race.claim_new_unlocks), one at a time,
## tap to dismiss.

## The mute toggle swaps its glyph rather than tinting one, so the state reads
## at a glance instead of asking the player to remember which shade means off.
const SOUND_ON_ICON := preload("res://assets/icons/speaker.svg")
const SOUND_OFF_ICON := preload("res://assets/icons/speaker_mute.svg")
const BACKDROP_SHADER := preload("res://shaders/zone_backdrop.gdshader")
const PLAY_ICON := preload("res://assets/icons/play.svg")
const LOCK_ICON := preload("res://assets/icons/lock.svg")
## A locked mode's name keeps its colour but fades back, so it reads as
## "there, but not yet" rather than as missing.
const LOCKED_ALPHA := 0.4
const LOCKED_SHAKE := 10.0

enum Mode { CASUAL, RACE }
const MODE_NAMES := ["CASUAL", "RACE"]
const MODE_PROMPTS := ["TAP TO PLAY", "TAP TO RACE"]
## Horizontal travel, press to release, that makes a touch a swipe rather than
## a tap. Well past a thumb's wobble on a tap, well short of a deliberate flick.
const SWIPE_MIN := 60.0
## The incoming mode name slides in from the side the swipe came from.
const MODE_SLIDE := 70.0
const MODE_SLIDE_TIME := 0.2
const DOT_SIZE := 10.0
const DOT_IDLE := Color(1.0, 1.0, 1.0, 0.3)
const DAILY_FONT_SIZE := 20
const POPUP_DIM := Color(0.0, 0.0, 0.0, 0.85)
const POPUP_FONT_SIZE := 34
const POPUP_HINT_COLOR := Color(1.0, 1.0, 1.0, 0.6)
## Taps within this long of a popup appearing are ignored, so a tap already on
## its way -- or the emulated mouse copy of the one that closed the previous
## popup -- cannot dismiss it unread.
const POPUP_GUARD_MS := 350

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
@onready var mode_label: Label = $UI/ModeLabel
@onready var mode_dots: HBoxContainer = $UI/ModeDots
@onready var _icon_buttons: Array[Node] = [$UI/SoundButton, $UI/ScienceButton,
	$UI/CustomizeButton, $UI/StatisticsButton,
	$UI/GuideButton, $UI/SettingsButton,
	$UI/ModeLeftButton, $UI/ModeRightButton]

## Every leave path goes through Transition, whose fade takes a moment. Without
## this the tap that lands during a fade -- or the emulated mouse click that
## follows every real touch -- queues a second scene change on top of the first.
var _leaving: bool = false

## True between a press and its release. The run starts on the release, not the
## initial touch, so a finger put down on the menu can still be lifted without
## committing to a run -- and a release arriving on its own (a finger already
## down as this screen loads) starts nothing.
var _pressed: bool = false

## Where the press that set _pressed went down, to tell a swipe from a tap.
var _press_pos: Vector2 = Vector2.ZERO

## Which zone's sky this visit is wearing, rolled in _ready.
var _zone: int = ZoneAmbience.OPENING

var _mode: Mode = Mode.CASUAL
var _mode_home_x: float = 0.0
var _mode_tween: Tween
var _dots: Array[Panel] = []
## The accent tinted toward this visit's zone -- what the title, the mode name
## and the live mode dot are drawn in. Set in _apply_visual_settings.
var _zone_accent: Color = Color.WHITE
var _daily_label: Label
## Difficulties still waiting to be announced, and the popup now showing.
var _unlock_queue: Array[int] = []
var _popup: Control
var _popup_shown_ms: int = 0

func _ready() -> void:
	_mode = Mode.RACE if Race.menu_on_race else Mode.CASUAL
	_mode_home_x = mode_label.position.x
	for i in range(MODE_NAMES.size()):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mode_dots.add_child(dot)
		_dots.append(dot)
	_make_daily_label()
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
	_unlock_queue = Race.claim_new_unlocks()
	_show_next_unlock()

## Under the tap prompt, in the accent: only there while the day's grant is
## waiting, so its presence is the news.
func _make_daily_label() -> void:
	_daily_label = Label.new()
	_daily_label.anchor_left = 0.5
	_daily_label.anchor_right = 0.5
	_daily_label.anchor_top = 0.68
	_daily_label.anchor_bottom = 0.68
	_daily_label.offset_left = -300.0
	_daily_label.offset_right = 300.0
	_daily_label.offset_top = -16.0
	_daily_label.offset_bottom = 16.0
	_daily_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_daily_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_daily_label.add_theme_font_size_override("font_size", DAILY_FONT_SIZE)
	_daily_label.add_to_group(UiAccent.GROUP)
	_daily_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_daily_label.text = "PLAY CASUAL MODE TO GET %d TICKETS!" % Race.DAILY_TICKETS
	_daily_label.visible = Race.daily_available()
	$UI.add_child(_daily_label)

## --- Unlock popups ---------------------------------------------------------

func _show_next_unlock() -> void:
	if _unlock_queue.is_empty():
		return
	var difficulty: int = _unlock_queue.pop_front()
	_popup = Control.new()
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(_popup)
	# Stops every press, so nothing under the popup -- buttons or the play
	# zone -- is reachable until it is gone.
	var dim := ColorRect.new()
	dim.color = POPUP_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_popup_input)
	_popup.add_child(dim)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = -90.0
	box.offset_bottom = 90.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	_popup.add_child(box)
	var title := Label.new()
	title.text = "%s MODE UNLOCKED!" % Race.DIFFICULTY_NAMES[difficulty]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", POPUP_FONT_SIZE)
	box.add_child(title)
	UiPlate.title(title)
	var hint := Label.new()
	hint.text = "TAP TO CONTINUE"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", POPUP_HINT_COLOR)
	box.add_child(hint)
	_popup_shown_ms = Time.get_ticks_msec()
	_popup.modulate.a = 0.0
	title.pivot_offset = title.get_combined_minimum_size() / 2.0
	title.scale = Vector2(0.6, 0.6)
	var tw := create_tween().set_parallel()
	tw.tween_property(_popup, "modulate:a", 1.0, 0.2)
	tw.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.vibrate(40)

func _on_popup_input(event: InputEvent) -> void:
	if event.is_pressed() and (event is InputEventMouseButton or event is InputEventScreenTouch):
		_dismiss_popup()

func _dismiss_popup() -> void:
	if _popup == null or Time.get_ticks_msec() - _popup_shown_ms < POPUP_GUARD_MS:
		return
	Audio.play_ui_click()
	_popup.queue_free()
	_popup = null
	_show_next_unlock()

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
	_zone_accent = ZoneAmbience.tint_toward(UiAccent.color(), _zone, ZoneAmbience.TITLE_TINT)
	title_label.add_theme_color_override("font_color", _zone_accent)
	# The mode name wears the same zone tint as the title, so the two big words
	# on the screen read as one pair against the sky (_update_mode_view sets it).
	_update_mode_view()

## Name, prompt and dots for the mode now showing. The live dot takes the
## zone-tinted accent, matching the mode name above it.
func _update_mode_view() -> void:
	var locked := _is_locked()
	mode_label.text = MODE_NAMES[_mode]
	var name_color := _zone_accent
	if locked:
		name_color.a *= LOCKED_ALPHA
	mode_label.add_theme_color_override("font_color", name_color)
	tap_icon.texture = LOCK_ICON if locked else PLAY_ICON
	var left := Race.runs_to_unlock()
	tap_label.text = ("PLAY %d MORE %s TO UNLOCK" % [left, "RUN" if left == 1 else "RUNS"]
		if locked else MODE_PROMPTS[_mode])
	for i in range(_dots.size()):
		var box := StyleBoxFlat.new()
		box.bg_color = _zone_accent if i == _mode else DOT_IDLE
		box.set_corner_radius_all(int(DOT_SIZE / 2.0))
		_dots[i].add_theme_stylebox_override("panel", box)

## `step` is +1 for the next mode, -1 for the previous; both wrap.
func _step_mode(step: int) -> void:
	if _leaving:
		return
	Audio.play_ui_click()
	_mode = posmod(_mode + step, MODE_NAMES.size()) as Mode
	Race.set_menu_on_race(_mode == Mode.RACE)
	_update_mode_view()
	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	mode_label.position.x = _mode_home_x + MODE_SLIDE * float(step)
	mode_label.modulate.a = 0.0
	_mode_tween = create_tween().set_parallel()
	_mode_tween.tween_property(mode_label, "position:x", _mode_home_x, MODE_SLIDE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_mode_tween.tween_property(mode_label, "modulate:a", 1.0, MODE_SLIDE_TIME * 0.7)

func _is_locked() -> bool:
	return _mode == Mode.RACE and not Race.is_unlocked()

## A tap on a locked mode: a short head-shake of its name, and a buzz.
func _shake_locked() -> void:
	Audio.vibrate(30)
	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	mode_label.position.x = _mode_home_x
	mode_label.modulate.a = 1.0
	_mode_tween = create_tween()
	for offset in [LOCKED_SHAKE, -LOCKED_SHAKE, LOCKED_SHAKE * 0.5, 0.0]:
		_mode_tween.tween_property(mode_label, "position:x", _mode_home_x + offset, 0.05)

func _on_mode_left_pressed() -> void:
	_step_mode(-1)

func _on_mode_right_pressed() -> void:
	_step_mode(1)

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
	# Every touch also arrives a second time as an emulated mouse click. One
	# copy is enough to play, but a swipe seen twice would switch mode twice
	# and land right back where it started.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# Touches on a popup never get here (its dim takes them); keys do, and
	# only the accept key does anything -- it closes the popup.
	if _popup != null:
		if event is InputEventKey and event.is_pressed() and event.is_action("ui_accept"):
			_dismiss_popup()
		return
	if event is InputEventKey and event.is_pressed():
		if event.is_action("ui_left"):
			_step_mode(-1)
			return
		if event.is_action("ui_right"):
			_step_mode(1)
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
		if event is not InputEventKey:
			_press_pos = event.position
	elif _pressed:
		_pressed = false
		# Checked before the zone: a swipe that ends outside it is still a
		# swipe. A swipe left brings in the next mode, as a page turns.
		if event is not InputEventKey:
			var dx: float = event.position.x - _press_pos.x
			if absf(dx) >= SWIPE_MIN:
				_step_mode(1 if dx < 0.0 else -1)
				return
		# Dragging out of the zone before lifting cancels, like a button.
		if in_zone:
			_play()

func _play() -> void:
	if _is_locked():
		_shake_locked()
		return
	if _mode == Mode.RACE:
		_go("res://scenes/race_setup.tscn")
		return
	Race.active = false
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
