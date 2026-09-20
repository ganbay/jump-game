extends Node2D

## Two pages: the attribute list, then how zones combine those attributes.
## Both are built into the scene and simply toggled -- the whole guide is a
## screenful of static labels, so there is nothing to rebuild on a page turn.
##
## Each page is one CenterContainer over a fixed-width column, rather than rows
## pinned to fractions of the viewport. The rows carry platform *instances*, and
## a Node2D has no anchors -- pinning the labels by fraction while the icons sat
## at authored pixel coordinates only lined up at exactly 720x1280, and the two
## drifted apart by a row's height on a 20:9 phone. Parenting each icon to its
## row Control makes its position row-local, so the container owns the whole
## layout and the pairing survives any aspect ratio `expand` hands us.

const PAGE_TITLES := ["HOW TO PLAY", "ZONES"]

## Page 1 carries the steering choice itself, not a sentence about it.
## Testers played whole runs without ever learning the other scheme existed:
## the pause menu's toggle is a bare glyph, and a line of prose telling them
## it can be changed was read as flavour text. A pair of buttons on the screen
## every new player already passes through (see main_menu.gd's route for a
## player who has not seen the guide) makes it a choice they make rather than
## one they have to go looking for.
## The picked scheme is drawn in the character's own colour (see UiAccent);
## only the unpicked one is a fixed neutral, since "not chosen" is a state
## that should not be wearing the accent at all.
const SELECTED_BG_SCALE := 0.12
const SELECTED_BG_ALPHA := 0.85
const SELECTED_BORDER_ALPHA := 0.9
const UNSELECTED_BG := Color(0.05, 0.08, 0.13, 0.4)
const UNSELECTED_BORDER := Color(0.6, 0.62, 0.68, 0.18)
const UNSELECTED_FG := Color(0.9, 0.9, 0.9, 1)
## How far the panel frames on both pages are knocked back from the accent --
## they outline a block of content rather than leading it, so they carry the
## hue at a fraction of its strength.
const FRAME_BORDER_ALPHA := 0.35
## Every state a Button draws, so the picked scheme does not lose its frame
## the moment a thumb rests on the other one.
const BUTTON_STATES := ["normal", "hover", "pressed", "focus"]

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var title_label: Label = $UI/TitleLabel
@onready var page_label: Label = $UI/PageLabel
@onready var prev_button: Button = $UI/PrevButton
@onready var next_button: Button = $UI/NextButton
@onready var controls_frame: PanelContainer = $UI/Page1/Body/Column/ControlsRow
@onready var zone_frame: PanelContainer = $UI/Page2/Body/Column/ZoneFrame
@onready var tilt_button: Button = $UI/Page1/Body/Column/ControlsRow/Inset/Column/Choices/TiltButton
@onready var touch_button: Button = $UI/Page1/Body/Column/ControlsRow/Inset/Column/Choices/TouchButton
@onready var page1: Control = $UI/Page1
@onready var page2: Control = $UI/Page2

var _pages: Array[Control] = []
var _page: int = 0

func _ready() -> void:
	_pages = [page1, page2]
	Stats.mark_tutorial_seen()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	_show_page(0)
	IconPop.attach([prev_button, next_button, $UI/PlayButton, $UI/BackButton])

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	# Both re-run here, not just at startup: the character's colour can change
	# under an open guide (Settings emits visual_settings_changed, which this
	# is connected to), and the chooser and the frames are painted in code
	# rather than by UiAccent's group walk.
	_tint_frame(controls_frame)
	_tint_frame(zone_frame)
	_update_controls_choice()

## The panel's own StyleBoxFlat is duplicated before it is touched: the scene
## hands the same sub-resource to both frames, and writing through it would
## have each call silently repaint the other page's frame too.
func _tint_frame(frame: PanelContainer) -> void:
	var box: StyleBoxFlat = frame.get_theme_stylebox("panel").duplicate()
	var accent := UiAccent.color()
	box.border_color = Color(accent.r, accent.g, accent.b, FRAME_BORDER_ALPHA)
	frame.add_theme_stylebox_override("panel", box)

func _show_page(page: int) -> void:
	_page = clampi(page, 0, _pages.size() - 1)
	for i in range(_pages.size()):
		_pages[i].visible = i == _page
	title_label.text = PAGE_TITLES[_page]
	page_label.text = "%d / %d" % [_page + 1, _pages.size()]
	# Hidden rather than disabled at the ends: a greyed-out button on a screen
	# this text-heavy reads as something the player failed to unlock.
	prev_button.visible = _page > 0
	next_button.visible = _page < _pages.size() - 1

func _on_tilt_pressed() -> void:
	_choose_control_scheme(Settings.ControlScheme.TILT)

func _on_touch_pressed() -> void:
	_choose_control_scheme(Settings.ControlScheme.TOUCH)

## Typed int rather than Settings.ControlScheme: Settings is an autoload with
## no class_name, so its nested enum resolves as a value but not reliably as a
## type annotation.
func _choose_control_scheme(scheme: int) -> void:
	Audio.play_ui_click()
	Settings.set_control_scheme(scheme)
	_update_controls_choice()

func _update_controls_choice() -> void:
	var tilt := Settings.control_scheme == Settings.ControlScheme.TILT
	_style_choice(tilt_button, tilt)
	_style_choice(touch_button, not tilt)

## Both buttons keep their frame -- the unpicked one just sits dim -- so the
## row reads as two options with one taken, rather than as a single button
## next to some text.
func _style_choice(button: Button, selected: bool) -> void:
	var accent := UiAccent.color()
	var box := StyleBoxFlat.new()
	box.bg_color = (Color(accent.r * SELECTED_BG_SCALE, accent.g * SELECTED_BG_SCALE,
		accent.b * SELECTED_BG_SCALE, SELECTED_BG_ALPHA) if selected else UNSELECTED_BG)
	box.border_color = (Color(accent.r, accent.g, accent.b, SELECTED_BORDER_ALPHA)
		if selected else UNSELECTED_BORDER)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	for state in BUTTON_STATES:
		button.add_theme_stylebox_override(state, box)
	var fg := accent if selected else UNSELECTED_FG
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("icon_normal_color", fg)
	button.add_theme_color_override("icon_hover_color", fg)
	button.add_theme_color_override("icon_pressed_color", fg)

func _on_next_pressed() -> void:
	Audio.play_ui_click()
	_show_page(_page + 1)

func _on_prev_pressed() -> void:
	Audio.play_ui_click()
	_show_page(_page - 1)

func _on_play_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
