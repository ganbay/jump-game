extends Node2D

## The LAN race lobby (see lan_race.gd), opened from the menu's LAN mode. Built
## in code like the race screen, as three views of one screen:
##
## - Outside a room: HOST A RACE, the rooms heard on this network, and joining
##   by address -- for networks that drop the rooms' broadcasts, which is most
##   guest and office Wi-Fi.
## - Connecting: a typed address being tried, with a way to give up.
## - In a room: who is in it, the distance (the host picks), READY or START,
##   and on the host the address the others can type. Coming back from a race
##   lands here with the room still together, for the rematch.
##
## The player's name sits at the top of both main views: typed once, saved
## (Settings.player_name), and sent to the room on every edit.
##
## Nothing here starts the race: START asks LanRace, which tells every phone
## at once and moves them all to the run together.

const SECTION_FONT_SIZE := 20
const OPTION_FONT_SIZE := 26
const OPTION_HEIGHT := 64.0
const SECTION_GAP := 18.0
const NOTE_FONT_SIZE := 18
const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.65)
const ERROR_COLOR := Color(1.0, 0.45, 0.5)
const ADDRESS_FONT_SIZE := 34
## Two addresses (on Wi-Fi and sharing a hotspot) share one smaller line, so a
## full room still fits above the back button on a 1280-tall screen.
const ADDRESSES_FONT_SIZE := 22
const PLAYER_FONT_SIZE := 24
const PLAYER_STATE_FONT_SIZE := 15
const PLAYER_STATE_COLOR := Color(1.0, 1.0, 1.0, 0.65)
## Two columns, so a full room of eight takes four rows and START stays clear
## of the back button.
const PLAYER_COLUMNS := 2
const PLAYER_CELL_WIDTH := 210.0
const ADDRESS_PLACEHOLDER := "192.168.1.23"

enum View { OUTSIDE, CONNECTING, ROOM }

## Survives leaving the screen, so a retry does not mean typing it again.
static var _last_address: String = ""

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var options: VBoxContainer = $UI/Options
@onready var subtitle_label: Label = $UI/SubtitleLabel

var _view: View = View.OUTSIDE
var _leaving: bool = false
var _action_buttons: Array[Button] = []
var _rooms_box: VBoxContainer
var _address_edit: LineEdit
var _name_edit: LineEdit
var _join_button: Button
var _players_box: GridContainer
var _target_buttons: Array[Button] = []
var _items_button: Button
## START on the host, READY on everyone else.
var _go_button: Button
var _room_note: Label

func _ready() -> void:
	LanRace.peers_changed.connect(_on_peers_changed)
	LanRace.rooms_changed.connect(_rebuild_rooms)
	LanRace.session_ended.connect(_on_session_ended)
	Transition.scene_change_failed.connect(_on_scene_change_failed)
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	IconPop.attach([$UI/BackButton])
	RaceGuidePanel.add_button($UI, true)
	_show_view(_current_view())

func _current_view() -> View:
	if not LanRace.is_active():
		return View.OUTSIDE
	if LanRace.is_connecting():
		return View.CONNECTING
	return View.ROOM

func _show_view(view: View) -> void:
	# First, while the old view is whole: on the host this refreshes the room
	# straight away (see _on_peers_changed).
	_commit_name()
	_view = view
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	_action_buttons.clear()
	_target_buttons.clear()
	_items_button = null
	_rooms_box = null
	_address_edit = null
	_name_edit = null
	_join_button = null
	_players_box = null
	_go_button = null
	_room_note = null
	match view:
		View.OUTSIDE:
			_build_outside()
		View.CONNECTING:
			_build_connecting()
		View.ROOM:
			_build_room()
	if view == View.OUTSIDE:
		LanRace.start_browsing()
		_rebuild_rooms()
	else:
		LanRace.stop_browsing()
	_apply_visual_settings()

# --- Views ----------------------------------------------------------------

func _build_outside() -> void:
	subtitle_label.text = "RACE FRIENDS ON THE SAME WI-FI"
	if LanRace.last_error != "":
		_add_note(LanRace.last_error, ERROR_COLOR)
		_add_gap()
	_add_name_field()
	var host := _add_action("HOST A RACE")
	host.pressed.connect(_on_host_pressed)
	_add_gap()
	_add_section("ROOMS NEARBY")
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 12)
	options.add_child(_rooms_box)
	_add_gap()
	_add_section("OR JOIN BY ADDRESS")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	options.add_child(row)
	_address_edit = LineEdit.new()
	_address_edit.text = _last_address
	_address_edit.placeholder_text = ADDRESS_PLACEHOLDER
	_address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_address_edit.custom_minimum_size = Vector2(0.0, OPTION_HEIGHT)
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
	_address_edit.text_submitted.connect(_on_address_submitted)
	row.add_child(_address_edit)
	_join_button = _add_option(row, "JOIN")
	_join_button.custom_minimum_size.x = 140.0
	_join_button.pressed.connect(_on_join_pressed)
	_add_note("ON THE SAME WI-FI, OR ONE PHONE ON THE OTHER'S HOTSPOT")

func _build_connecting() -> void:
	subtitle_label.text = "JOINING A ROOM"
	_add_note("CONNECTING TO %s ..." % _last_address)
	_add_gap()
	var cancel := _add_action("CANCEL")
	cancel.pressed.connect(_on_cancel_pressed)

func _build_room() -> void:
	if LanRace.is_host():
		subtitle_label.text = "YOU'RE HOSTING"
		_add_section("YOUR ADDRESS")
		var addresses := LanRace.local_addresses()
		var address := Label.new()
		address.text = "   ".join(addresses) if not addresses.is_empty() \
			else "NOT ON A NETWORK"
		address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var address_size := ADDRESS_FONT_SIZE if addresses.size() == 1 \
			else (ADDRESSES_FONT_SIZE if addresses.size() > 1 else PLAYER_FONT_SIZE)
		address.add_theme_font_size_override("font_size", address_size)
		options.add_child(address)
		_add_note("FRIENDS PICK YOUR ROOM, OR TYPE THIS TO JOIN" if not addresses.is_empty()
			else "TURN ON WI-FI, OR YOUR HOTSPOT FOR FRIENDS TO JOIN", NOTE_COLOR)
		_add_gap()
	else:
		subtitle_label.text = "IN A ROOM"
	_add_name_field()
	_add_section("PLAYERS")
	_players_box = GridContainer.new()
	_players_box.columns = PLAYER_COLUMNS
	_players_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_players_box.add_theme_constant_override("h_separation", 20)
	_players_box.add_theme_constant_override("v_separation", 10)
	options.add_child(_players_box)
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
	# Straight under the distance, without a heading of its own: a full room
	# has to fit above the back button on a 1280-tall screen.
	_items_button = _add_option(options, "")
	_items_button.pressed.connect(_on_items_pressed)
	_add_gap()
	_go_button = _add_action("")
	_go_button.pressed.connect(_on_go_pressed)
	_room_note = _add_note("")
	_refresh_room()

func _refresh_room() -> void:
	if _players_box == null:
		return
	for child in _players_box.get_children():
		child.queue_free()
	var ids := LanRace.peers.keys()
	ids.sort_custom(func(a, b): return LanRace.peers[a]["slot"] < LanRace.peers[b]["slot"])
	for id in ids:
		_players_box.add_child(_player_row(id, LanRace.peers[id]))
	var host := LanRace.is_host()
	for i in range(_target_buttons.size()):
		_target_buttons[i].disabled = not host
	_items_button.disabled = not host
	_items_button.text = "ITEM BOXES: ON" if LanRace.items_on else "ITEM BOXES: OFF"
	var go_text: String
	if host:
		if LanRace.peers.size() < 2:
			go_text = "WAITING FOR PLAYERS"
		elif not LanRace.can_start():
			go_text = "WAITING FOR READY"
		else:
			go_text = "START"
		_go_button.disabled = not LanRace.can_start()
	else:
		go_text = "NOT READY" if _my_ready() else "READY"
		_go_button.disabled = false
	if _go_button.text != go_text:
		_go_button.text = go_text
	_go_button.modulate.a = 0.55 if _go_button.disabled else 1.0
	_room_note.text = _room_note_text()
	_restyle_buttons()

func _room_note_text() -> String:
	if not LanRace.results.is_empty():
		var winner: Dictionary = LanRace.results[0]
		if float(winner["time"]) >= 0.0:
			return "LAST RACE: %s WON" % winner["name"]
	if LanRace.is_host():
		return "FREE TO PLAY - DOESN'T COUNT TOWARD BEST TIMES"
	return "THE HOST STARTS ONCE EVERYONE'S READY"

## The name in their colour, and under it HOST / READY / NOT READY -- with
## "YOU" there too on this phone's own cell, so a twelve-letter name still fits
## its column.
func _player_row(id: int, info: Dictionary) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size.x = PLAYER_CELL_WIDTH
	cell.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = info["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", PLAYER_FONT_SIZE)
	name_label.add_theme_color_override("font_color", _player_color(info))
	cell.add_child(name_label)
	var state := Label.new()
	var status: String = "HOST" if id == 1 else ("READY" if info["ready"] else "NOT READY")
	state.text = "YOU - %s" % status if id == LanRace.my_id() else status
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", PLAYER_STATE_FONT_SIZE)
	state.add_theme_color_override("font_color", PLAYER_STATE_COLOR)
	cell.add_child(state)
	return cell

## Their character colour, as their ghost will wear it.
func _player_color(info: Dictionary) -> Color:
	return info.get("color", Color.WHITE)

func _my_ready() -> bool:
	var me: Dictionary = LanRace.peers.get(LanRace.my_id(), {})
	return me.get("ready", false)

func _rebuild_rooms() -> void:
	if _rooms_box == null:
		return
	for child in _rooms_box.get_children():
		child.queue_free()
	if not LanRace.is_browsing():
		_add_note("CAN'T LOOK FOR ROOMS HERE - JOIN BY ADDRESS", NOTE_COLOR, _rooms_box)
		return
	if LanRace.rooms.is_empty():
		_add_note("LOOKING FOR ROOMS...", NOTE_COLOR, _rooms_box)
		return
	for address in LanRace.rooms:
		var room: Dictionary = LanRace.rooms[address]
		var room_name: String = room["name"] if room["name"] != "" else address
		var button := _add_option(_rooms_box, "%s   %d/%d" % [
			room_name.to_upper(), room["players"], room["max"]])
		button.pressed.connect(_join.bind(address))
		UiPlate.option(button, false)

# --- Actions --------------------------------------------------------------

func _add_name_field() -> void:
	_add_section("YOUR NAME")
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name
	_name_edit.placeholder_text = "TAP TO NAME YOURSELF"
	_name_edit.max_length = Settings.PLAYER_NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(0.0, OPTION_HEIGHT)
	_name_edit.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
	_name_edit.text_submitted.connect(func(_text: String): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	options.add_child(_name_edit)
	_add_gap()

## Saves the typed name and, in a room, tells the others. Safe to call any
## time -- an unchanged name is a no-op -- so every way off the field (enter,
## tapping elsewhere, the view changing under it) lands here.
func _commit_name() -> void:
	if _name_edit == null:
		return
	var cleaned := Settings.clean_player_name(_name_edit.text)
	if _name_edit.text != cleaned:
		_name_edit.text = cleaned
	if cleaned == Settings.player_name:
		return
	Settings.set_player_name(cleaned)
	LanRace.send_profile()

func _on_host_pressed() -> void:
	Audio.play_ui_click()
	_commit_name()
	LanRace.host()
	_show_view(_current_view())

func _on_join_pressed() -> void:
	_join(_address_edit.text if _address_edit != null else "")

func _on_address_submitted(text: String) -> void:
	_join(text)

func _join(address: String) -> void:
	Audio.play_ui_click()
	_commit_name()
	_last_address = address.strip_edges()
	LanRace.join(_last_address)
	_show_view(_current_view())

func _on_cancel_pressed() -> void:
	Audio.play_ui_click()
	LanRace.leave()

func _on_target_pressed(index: int) -> void:
	if not LanRace.is_host():
		return
	Audio.play_ui_click()
	LanRace.set_target(index)

func _on_items_pressed() -> void:
	if not LanRace.is_host():
		return
	Audio.play_ui_click()
	LanRace.set_items(not LanRace.items_on)

func _on_go_pressed() -> void:
	Audio.play_ui_click()
	if LanRace.is_host():
		LanRace.start_race()
	else:
		LanRace.set_ready(not _my_ready())

func _on_peers_changed() -> void:
	var view := _current_view()
	if view != _view:
		_show_view(view)
	elif view == View.ROOM:
		_refresh_room()

func _on_session_ended(_reason: String) -> void:
	_show_view(View.OUTSIDE)

## Out of a room first, then off the screen.
func _on_back_pressed() -> void:
	if _leaving:
		return
	Audio.play_ui_click()
	if _view != View.OUTSIDE:
		LanRace.leave()
		return
	_leaving = true
	LanRace.stop_browsing()
	LanRace.last_error = ""
	Transition.change_scene("res://scenes/main_menu.tscn")

func _on_scene_change_failed(_path: String) -> void:
	_leaving = false

# --- Building blocks ------------------------------------------------------

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	_restyle_buttons()

## After the accent walk, which would repaint the plates' text.
func _restyle_buttons() -> void:
	for button in _action_buttons:
		UiPlate.action(button)
	for i in range(_target_buttons.size()):
		UiPlate.option(_target_buttons[i], i == LanRace.target_index)
	if _items_button != null:
		UiPlate.option(_items_button, LanRace.items_on)
	if _join_button != null:
		UiPlate.option(_join_button, false)
	for edit in [_address_edit, _name_edit]:
		if edit == null:
			continue
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		box.border_color = UiAccent.color()
		box.set_border_width_all(UiPlate.ACTION_BORDER)
		box.set_corner_radius_all(UiPlate.QUIET_CORNER)
		for state in ["normal", "focus", "read_only"]:
			edit.add_theme_stylebox_override(state, box)
	if _rooms_box != null:
		for child in _rooms_box.get_children():
			if child is Button:
				UiPlate.option(child, false)

func _add_section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	label.add_to_group(UiAccent.GROUP)
	options.add_child(label)
	return label

func _add_note(text: String, color: Color = NOTE_COLOR, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	(parent if parent != null else options).add_child(label)
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

func _add_action(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 30)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.add_child(button)
	IconPop.attach([button])
	_action_buttons.append(button)
	return button
