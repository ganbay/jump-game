class_name UiPlate

## Backs a prompt or a panel button with a plate, so the coaching UI reads as
## part of the game instead of as bare text floating on a dim. The look is the
## streak counter's (see game.gd's _streak_plate): a saturated pill in the
## character's own colour with the text punched out of it in black, which the
## glow then blooms. Companion to UiAccent and UiOpacity, and applied the same
## way -- from code, because the fill tracks Settings.player_color.
##
## Three tiers, because a title and a button should not look alike:
##
##   title()  -- the counter's look exactly: solid accent fill, black text.
##               For short announcements -- TAP TO FLARE, TILT TO STEER, TAP!
##   action() -- outlined instead of filled: dark fill, accent border, accent
##               text. Reads as something to press rather than something to
##               read, and inverts to the solid title fill while held, so the
##               press confirms itself on a screen with no hover to rely on.
##   quiet()  -- a dark pill and dim grey text, no border and no accent. For
##               the action a player mostly should not take (DON'T SHOW
##               AGAIN), which has to stay findable without competing.
##
## What does NOT get a plate: body copy. A paragraph behind a filled pill is
## unreadable, and these panels already sit on their own dim. The same goes for
## a headline long enough that its plate would run off the screen -- the
## milestone title is 48px and over twenty characters, so it stays bare accent
## text while its button takes the treatment.

## Matches STREAK_PLATE_CORNER so a prompt and the counter are cut alike.
const TITLE_CORNER := 14
## Roomier than the counter's own 6/0: that one is a tight readout that flashes
## for a beat, these are headings that sit still and get read.
const TITLE_PAD_X := 16.0
const TITLE_PAD_Y := 6.0
## Black, exactly as the counter punches its text out of the plate -- see
## game.gd's STREAK_TEXT_COLOR. The accent fill is the bright part; the text is
## the hole in it.
const TITLE_TEXT := Color(0.0, 0.0, 0.0)

const ACTION_CORNER := 14
## Wider than a title's padding, not narrower: the plate is the touch target
## here, and a thumb wants more than the glyphs do.
const ACTION_PAD_X := 30.0
const ACTION_PAD_Y := 14.0
const ACTION_BORDER := 2
## Not fully transparent -- the outline needs something behind it to sit on, or
## the dim shows through and the button reads as a floating rectangle of text.
const ACTION_FILL := Color(0.0, 0.0, 0.0, 0.45)

const QUIET_CORNER := 10
const QUIET_PAD_X := 18.0
const QUIET_PAD_Y := 9.0
const QUIET_FILL := Color(1.0, 1.0, 1.0, 0.07)
const QUIET_FILL_HELD := Color(1.0, 1.0, 1.0, 0.16)
const QUIET_TEXT := Color(0.85, 0.85, 0.85)

## The counter's look, for a short heading. Safe to call again whenever the
## text changes -- and it has to be, since the plate is fitted to the string
## that was there when it ran.
static func title(label: Label) -> void:
	label.add_theme_stylebox_override("normal",
		_plate(UiAccent.color(), TITLE_CORNER, TITLE_PAD_X, TITLE_PAD_Y))
	label.add_theme_color_override("font_color", TITLE_TEXT)
	# The authored outline exists to hold bare text off the run behind it.
	# On a plate it only muddies the letterforms.
	label.add_theme_constant_override("outline_size", 0)
	_fit(label)

static func action(button: Button) -> void:
	var accent := UiAccent.color()
	var rest := _plate(ACTION_FILL, ACTION_CORNER, ACTION_PAD_X, ACTION_PAD_Y)
	rest.set_border_width_all(ACTION_BORDER)
	rest.border_color = accent
	var held := _plate(accent, ACTION_CORNER, ACTION_PAD_X, ACTION_PAD_Y)
	held.set_border_width_all(ACTION_BORDER)
	held.border_color = accent
	# A flat Button skips its stylebox entirely, so a plate on one draws
	# nothing at all.
	button.flat = false
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, rest)
	for state in ["hover", "pressed"]:
		button.add_theme_stylebox_override(state, held)
	for state in ["font_color", "font_focus_color"]:
		button.add_theme_color_override(state, accent)
	for state in ["font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TITLE_TEXT)
	_fit(button)

static func quiet(button: Button) -> void:
	var rest := _plate(QUIET_FILL, QUIET_CORNER, QUIET_PAD_X, QUIET_PAD_Y)
	var held := _plate(QUIET_FILL_HELD, QUIET_CORNER, QUIET_PAD_X, QUIET_PAD_Y)
	button.flat = false
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, rest)
	for state in ["hover", "pressed"]:
		button.add_theme_stylebox_override(state, held)
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		button.add_theme_color_override(state, QUIET_TEXT)
	_fit(button)

static func _plate(fill: Color, corner: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(corner)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box

## A stylebox fills its Control's whole rect, and every one of these is
## authored far wider than its text so the longest string fits -- left alone
## that paints a plate most of the screen wide behind two words. This is the
## same trick game.gd's _refresh_streak_plate uses: assigning zero size snaps a
## Control to its combined minimum, which for these is the shaped text plus the
## plate's content margins.
static func _fit(ctrl: Control) -> void:
	# Only meaningful for a Control pinned to a single anchor point, which is
	# how every prompt and panel button here is laid out. Anything stretched
	# between two different anchors is left at its authored rect rather than
	# silently re-anchored to a point.
	if not (is_equal_approx(ctrl.anchor_left, ctrl.anchor_right)
			and is_equal_approx(ctrl.anchor_top, ctrl.anchor_bottom)):
		return
	ctrl.size = Vector2.ZERO
	# Rebuilt symmetrically about the anchor rather than by writing `position`,
	# so the result stays centred when the viewport is a different shape --
	# with stretch mode "viewport" and an expand aspect, a tall phone is a good
	# deal taller than the 1280 these were authored against.
	var half := ctrl.size / 2.0
	ctrl.offset_left = -half.x
	ctrl.offset_right = half.x
	ctrl.offset_top = -half.y
	ctrl.offset_bottom = half.y
	ctrl.pivot_offset = half
