extends Node2D

## The closing slate of the trailer: wordmark, tagline, and where to get it.
##
## Built in code rather than authored as a .tscn because it is one screen of
## three labels on black that only ever exists inside a render -- a scene file
## for it would be one more thing to keep in sync with the splash card it is
## deliberately styled after (see scenes/splash.tscn: same overbright white,
## same black ground, so the trailer opens and closes on the same surface).
##
## Everything sits above the HDR glow threshold of 1.0 so the WorldEnvironment
## below blooms it, which is what stops a card with white text on it reading as
## a slide rather than as part of the game.
##
## The sky is the splash card's, star field and all -- the same night blue and
## the same scatter, reused rather than reproduced (see splash_stars.gd, whose
## field is seeded from a constant so it is the same sky every time). The
## trailer therefore opens and closes on one surface, and the card reads as the
## other end of the thing it started with.

## Kept in step by hand with splash.gd's own NIGHT and with
## application/boot_splash/bg_color in project.godot, neither of which can
## reference the other.
const NIGHT := Color(0.043, 0.063, 0.133)
const TITLE_COLOR := Color(2.3, 2.3, 2.3)
const SUB_COLOR := Color(1.7, 1.7, 1.7)
## The call to action is the one line in a different hue -- it is the only part
## of the card asking for something, so it should not read as more wordmark.
const CTA_COLOR := Color(0.7403599, 2.2, 0.6491324)

const STARS := preload("res://scripts/splash_stars.gd")

const FADE_IN := 0.5
const RISE_PX := 26.0
## The box every line is given around its anchor. Held as constants because the
## rise below animates these offsets rather than `position`: a Control's
## position is not resolved until the first layout pass, so a tween that
## captured it inside _ready would animate from and to zero.
const BOX_HALF_HEIGHT := 60.0
const BOX_HALF_WIDTH := 340.0

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.8
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var background_layer := CanvasLayer.new()
	background_layer.layer = -1
	add_child(background_layer)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.offset_right = 0.0
	background.offset_bottom = 0.0
	background.color = NIGHT
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)
	# Added after the ground it sits on, so it draws over it. Both live on the
	# background layer, below the wordmark.
	background_layer.add_child(STARS.new())

	var ui := CanvasLayer.new()
	add_child(ui)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_right = 0.0
	content.offset_bottom = 0.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(content)

	var title := _label(content, "JETLET", 0.42, 96, TITLE_COLOR)
	var sub := _label(content, "SOLAR ESCAPE", 0.505, 44, SUB_COLOR)
	var cta := _label(content, "COMING SOON ON GOOGLE PLAY", 0.60, 28, CTA_COLOR)

	# Staggered so the card assembles itself instead of appearing whole: the
	# name, then what it is, then where to get it -- the order it would be read
	# in anyway.
	_rise(title, 0.0)
	_rise(sub, 0.12)
	_rise(cta, 0.30)

func _label(parent: Control, text: String, anchor_y: float, font_size: int,
		color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_left = -BOX_HALF_WIDTH
	label.offset_right = BOX_HALF_WIDTH
	label.offset_top = -BOX_HALF_HEIGHT
	label.offset_bottom = BOX_HALF_HEIGHT
	parent.add_child(label)
	return label

func _rise(label: Label, delay: float) -> void:
	label.offset_top = -BOX_HALF_HEIGHT + RISE_PX
	label.offset_bottom = BOX_HALF_HEIGHT + RISE_PX
	label.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, FADE_IN) \
		.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Both edges together, so the box slides rather than grows.
	tween.tween_property(label, "offset_top", -BOX_HALF_HEIGHT, FADE_IN * 1.4) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "offset_bottom", BOX_HALF_HEIGHT, FADE_IN * 1.4) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
