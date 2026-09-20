class_name UiAccent

## Paints every accent-coloured piece of text in a screen's UI layer with the
## character's own colour, in one walk -- the companion to UiOpacity, and it
## works the same way: a screen marks which of its nodes are accents and does
## not otherwise have to know about this.
##
## The game already lets the player pick their character's colour, their
## platforms' and their background drift's, but the UI stayed on the authored
## neon cyan no matter what -- so a purple character flew past cyan headings
## and a cyan streak counter plate (see game.gd's _streak_plate_color, which
## has taken the character colour all along). Tying the accents to the same
## source makes a recoloured character actually recolour the game.
##
## What is NOT an accent, deliberately: body copy and readouts. Paragraphs,
## stat values, the in-run score and every neutral grey label stay neutral,
## because the accent is meant to pick out the few things that lead a screen
## -- its title, a panel heading, a prompt. Tinting everything would leave
## nothing picked out, and a hue chosen for a 40px character is not one to
## read four lines of 14px text in.
##
## Coins are the other exception: they follow Settings.background_particle_
## color (see game.gd's coin label), not this, and keep their own identity.

const GROUP := "ui_accent"

## The palette behind the colour picker is all bright neon -- every entry has
## a channel at 1.8 or above (see ColorSpectrumSlider.palette) -- so anything
## the player can actually choose reads fine as text on the dark background.
## This floor exists for the palette that gets edited later: it lifts a colour
## that would come out too dim to read, and is the identity for every colour
## currently reachable.
const MIN_PEAK := 1.6

static func color() -> Color:
	var c := Settings.player_color
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak <= 0.0:
		return Color(MIN_PEAK, MIN_PEAK, MIN_PEAK, c.a)
	if peak >= MIN_PEAK:
		return c
	# Scaled rather than lightened towards white, so lifting it keeps the hue
	# the player picked instead of washing it out.
	var lift := MIN_PEAK / peak
	return Color(c.r * lift, c.g * lift, c.b * lift, c.a)

static func apply(root: Node) -> void:
	_paint(root, color())

static func _paint(root: Node, accent: Color) -> void:
	for child in root.get_children():
		if child is Control and child.is_in_group(GROUP):
			_tint(child, accent)
		_paint(child, accent)

## Every state a Button draws, not just the resting one: these are flat
## icon buttons whose hover and pressed colours are separately overridden in
## the scenes, so tinting `normal` alone would have them snap back to the
## authored cyan the moment a thumb landed on them.
static func _tint(node: Control, accent: Color) -> void:
	if node is Button:
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"font_focus_color", "icon_normal_color", "icon_hover_color",
				"icon_pressed_color", "icon_focus_color"]:
			node.add_theme_color_override(state, accent)
	elif node is Label or node is RichTextLabel:
		node.add_theme_color_override("font_color", accent)
	elif node is TextureRect:
		# modulate, never self_modulate: UiOpacity owns that channel on every
		# Control under a UI layer, and the two have to multiply rather than
		# overwrite each other.
		node.modulate = accent
