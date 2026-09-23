extends Node2D

## Picks the bot and the distance, then starts the race. The option rows are
## built here rather than authored in the scene: they are one button per entry
## in Race's tables, so adding a difficulty or a distance there is the whole
## change.
##
## The AI's pace is deliberately not shown: it is something to find out by
## racing it, not a number to read before starting.
##
## Race tickets (see race.gd) surface here in three places, each saying one
## thing: the counter in the top corner (how many), the line under START
## (what this race costs), and the ticket panel (how to get more) -- two
## buttons and no reading, opened from the counter, or from START when the
## race picked cannot be afforded. The score targets that earn tickets are
## taught on the casual game-over screen instead, right after the run.

const SECTION_FONT_SIZE := 20
const OPTION_FONT_SIZE := 26
const OPTION_HEIGHT := 64.0
const SECTION_GAP := 18.0
const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.65)
const TICKET_ICON := preload("res://assets/icons/ticket.svg")
const INFO_DIM := Color(0.0, 0.0, 0.0, 0.92)
const AD_READY_TEXT := "WATCH AD   +5 TICKETS"
## Wide enough for either text, so the countdown ticking does not resize the
## button every second.
const AD_BUTTON_MIN_WIDTH := 440.0
const COOLDOWN_ALPHA := 0.55

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var options: VBoxContainer = $UI/Options

var _difficulty_buttons: Array[Button] = []
var _target_buttons: Array[Button] = []
var _best_label: Label
var _start_button: Button
var _cost_label: Label
var _ticket_button: Button
var _info_panel: Control
var _info_ad_button: Button
var _info_casual_button: Button
## True from pressing the refill until the ad settles, so the countdown
## refresh cannot re-enable the button under an ad that is still up.
var _ad_showing: bool = false
var _difficulty: int = Race.difficulty
var _target_index: int = Race.target_index
var _leaving: bool = false

func _ready() -> void:
	_build()
	_refresh()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	IconPop.attach([$UI/BackButton, _ticket_button])
	# Warmed up now so the panel's refill is ready by the time it is wanted.
	Ads.load_rewarded()
	# _leaving is only cleared by actually leaving, so a scene that fails to
	# load would otherwise strand the screen with every button dead.
	Transition.scene_change_failed.connect(_on_scene_change_failed)

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	# After the accent walk, which would repaint the start plate's text.
	if _start_button != null:
		UiPlate.action(_start_button)
	if _info_ad_button != null:
		UiPlate.action(_info_ad_button)
		UiPlate.action(_info_casual_button)
	_refresh()

func _build() -> void:
	_add_section("AI")
	for i in range(Race.available_difficulties()):
		var button := _add_option(options, Race.DIFFICULTY_NAMES[i])
		button.pressed.connect(_on_difficulty_pressed.bind(i))
		_difficulty_buttons.append(button)

	_add_gap()
	_add_section("DISTANCE")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	options.add_child(row)
	for i in range(Race.TARGETS.size()):
		var button := _add_option(row, RaceHud._thousands(Race.TARGETS[i]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_target_pressed.bind(i))
		_target_buttons.append(button)

	_add_gap()
	_best_label = _add_note("")
	_add_gap()
	_start_button = Button.new()
	_start_button.text = "START"
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.add_theme_font_size_override("font_size", 34)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_button.pressed.connect(_on_start_pressed)
	options.add_child(_start_button)
	UiPlate.action(_start_button)
	IconPop.attach([_start_button])
	_cost_label = _add_note("")
	_build_ticket_button()
	_build_info_panel()

## The ticket count, pinned top right. A button rather than a readout: tapping
## it is how the explainer is found again.
func _build_ticket_button() -> void:
	_ticket_button = Button.new()
	_ticket_button.flat = true
	_ticket_button.focus_mode = Control.FOCUS_NONE
	_ticket_button.icon = TICKET_ICON
	_ticket_button.add_theme_constant_override("icon_max_width", 40)
	_ticket_button.add_theme_constant_override("h_separation", 10)
	_ticket_button.add_theme_font_size_override("font_size", 26)
	_ticket_button.add_to_group(UiAccent.GROUP)
	_ticket_button.anchor_left = 1.0
	_ticket_button.anchor_right = 1.0
	_ticket_button.offset_left = -170.0
	_ticket_button.offset_right = -20.0
	_ticket_button.offset_top = 24.0
	_ticket_button.offset_bottom = 88.0
	_ticket_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ticket_button.pressed.connect(_on_ticket_button_pressed)
	$UI.add_child(_ticket_button)

## The two ways to get tickets, as two buttons: an ad now, or a casual run
## (which pays out by score -- see race.gd). Tapping outside closes it.
func _build_info_panel() -> void:
	_info_panel = Control.new()
	_info_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info_panel.visible = false
	$UI.add_child(_info_panel)
	var dim := ColorRect.new()
	dim.color = INFO_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_info_dim_input)
	_info_panel.add_child(dim)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -260.0
	box.offset_right = 260.0
	box.offset_top = -120.0
	box.offset_bottom = 120.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	_info_panel.add_child(box)
	_info_ad_button = _info_button(box, AD_READY_TEXT)
	_info_ad_button.icon = preload("res://assets/icons/video.svg")
	_info_ad_button.custom_minimum_size.x = AD_BUTTON_MIN_WIDTH
	_info_ad_button.pressed.connect(_on_info_ad_pressed)
	# Named by what it takes, not where it goes: the button is the rule.
	_info_casual_button = _info_button(box, "SCORE %s IN CASUAL" %
		RaceHud._thousands(Race.RUN_MIN_SCORE))
	_info_casual_button.pressed.connect(_on_info_casual_pressed)

func _info_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_constant_override("icon_max_width", 36)
	button.add_theme_constant_override("h_separation", 12)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	UiPlate.action(button)
	IconPop.attach([button])
	return button

func _open_info() -> void:
	_info_panel.visible = true
	_update_info_ad_button()

func _close_info() -> void:
	Audio.play_ui_click()
	_info_panel.visible = false

func _on_info_dim_input(event: InputEvent) -> void:
	if event.is_pressed() and (event is InputEventMouseButton or event is InputEventScreenTouch):
		_close_info()

## Always on the panel, and when it cannot be used it says why instead of
## disappearing -- a missing button reads as a broken one. Full, cooling
## down, or waiting on an ad to load: each is disabled with its reason, and
## the moment the reason clears it turns live (see _process).
func _update_info_ad_button() -> void:
	if _info_ad_button == null:
		return
	var wait := Race.ad_cooldown_left()
	var ready := false
	if Race.is_full():
		_set_info_ad_text("TICKETS FULL")
	elif wait > 0:
		_set_info_ad_text("NEXT AD IN %s" % Stats.format_duration(wait))
	elif not Ads.is_rewarded_ready():
		_set_info_ad_text("NO AD RIGHT NOW")
	else:
		_set_info_ad_text(AD_READY_TEXT)
		ready = true
	_info_ad_button.disabled = not ready or _ad_showing
	_info_ad_button.modulate.a = 1.0 if ready else COOLDOWN_ALPHA

## Only on a real change: assigning Button.text re-shapes it every time.
func _set_info_ad_text(text: String) -> void:
	if _info_ad_button.text != text:
		_info_ad_button.text = text

func _process(_delta: float) -> void:
	if _info_panel != null and _info_panel.visible:
		_update_info_ad_button()

func _on_ticket_button_pressed() -> void:
	Audio.play_ui_click()
	_open_info()

## Straight into a casual run -- the menu's own tap-to-play, minus the menu.
func _on_info_casual_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play_ui_click()
	Race.active = false
	Transition.change_scene("res://scenes/main.tscn")

func _on_info_ad_pressed() -> void:
	if not Race.can_watch_ad():
		return
	Audio.play_ui_click()
	_ad_showing = true
	_info_ad_button.disabled = true
	Ads.show_rewarded(_on_info_ad_rewarded, _on_info_ad_dismissed)

func _on_info_ad_rewarded() -> void:
	_ad_showing = false
	Race.grant_ad_tickets()
	Analytics.log_event("ticket_ad_refill")
	Ads.load_rewarded()
	_refresh()
	_update_info_ad_button()

func _on_info_ad_dismissed() -> void:
	_ad_showing = false
	Ads.load_rewarded()
	_update_info_ad_button()

func _add_section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_to_group(UiAccent.GROUP)
	options.add_child(label)
	return label

func _add_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", NOTE_COLOR)
	options.add_child(label)
	return label

func _add_gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, SECTION_GAP)
	options.add_child(gap)

func _add_option(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, OPTION_HEIGHT)
	button.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
	parent.add_child(button)
	return button

## The picked option is a solid accent plate with black text -- the same look
## as the game's plated titles -- and the rest are the same plate emptied out:
## just its accent outline, over nothing. Filled vs. outlined in one colour
## reads as a single control with one choice made.
func _refresh() -> void:
	for i in range(_difficulty_buttons.size()):
		_style_option(_difficulty_buttons[i], i == _difficulty)
	for i in range(_target_buttons.size()):
		_style_option(_target_buttons[i], i == _target_index)
	if _best_label != null:
		var best := Race.best_time(_difficulty, _target_index)
		_best_label.text = ("BEST TIME %s" % Stats.format_duration(best) if best > 0.0
			else "NOT BEATEN YET")
	if _ticket_button != null:
		_ticket_button.text = "%d/%d" % [Race.tickets, Race.TICKET_CAP]
	if _cost_label != null:
		var affordable := Race.can_start(_difficulty)
		if Race.race_cost(_difficulty) == 0:
			_cost_label.text = "NOVICE RACES ARE FREE"
		elif affordable:
			_cost_label.text = "1 TICKET - WIN TO GET IT BACK"
		else:
			_cost_label.text = "OUT OF RACE TICKETS"
		var start_text := "START" if affordable else "GET TICKETS"
		if _start_button.text != start_text:
			_start_button.text = start_text
			UiPlate.action(_start_button)

func _style_option(button: Button, picked: bool) -> void:
	var accent := UiAccent.color()
	var rest := _plate(accent) if picked else _outline(Color(0.0, 0.0, 0.0, 0.0))
	# A faint fill under the outline while held, so a tap still shows.
	var held := _plate(accent) if picked else _outline(UiPlate.QUIET_FILL_HELD)
	var text := UiPlate.TITLE_TEXT if picked else accent
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, rest)
	for state in ["hover", "pressed"]:
		button.add_theme_stylebox_override(state, held)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)

func _plate(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(UiPlate.QUIET_CORNER)
	return box

func _outline(fill: Color) -> StyleBoxFlat:
	var box := _plate(fill)
	box.border_color = UiAccent.color()
	box.set_border_width_all(UiPlate.ACTION_BORDER)
	return box

func _on_difficulty_pressed(index: int) -> void:
	Audio.play_ui_click()
	_difficulty = index
	_refresh()

func _on_target_pressed(index: int) -> void:
	Audio.play_ui_click()
	_target_index = index
	_refresh()

func _on_start_pressed() -> void:
	if _leaving:
		return
	Audio.play_ui_click()
	if not Race.can_start(_difficulty):
		_open_info()
		return
	_leaving = true
	Race.choose(_difficulty as Race.Difficulty, _target_index)
	Race.pay_for_race()
	Race.active = true
	Transition.change_scene("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")

func _on_scene_change_failed(_path: String) -> void:
	_leaving = false
