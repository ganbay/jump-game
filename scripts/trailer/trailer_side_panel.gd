extends Node2D

## The landscape cut's chrome: everything in the 16:9 frame that is not the
## gameplay strip.
##
## WHY THERE IS CHROME AT ALL
##
## The game is a vertical climber authored against 720x1280, and it cannot be
## reframed to 16:9 without changing what it is -- platform gaps, edge margins
## and the whole difficulty curve are tuned against that canvas. So a landscape
## trailer shows the game in a 9:16 strip, which at 1080 high is 608px of a
## 1920px frame. The other 68% is this.
##
## It is deliberately not a fill. main.tscn's own background is already
## Color(0, 0, 0, 1), so black pillars would be seamless -- a narrow column of
## game floating in a void, with nothing saying that was a decision. Instead the
## surround is the splash card's sky (see splash_stars.gd and splash.tscn's
## NIGHT ground), which is what the trailer already opens and closes on, and the
## space beside the strip carries the thing a 608px-wide strip cannot: the name,
## and what the viewer is looking at.
##
## WHY THE COPY LIVES HERE RATHER THAN IN THE GAME
##
## The director suppresses the in-game zone banner for this cut (see
## trailer_director.gd:_tick_gameplay). That banner is authored for a 720px
## canvas and would be rendered into 608px -- legible on a phone, not on a strip
## in the corner of a YouTube frame. Saying it once, large, in the panel is the
## same information at a size that survives the format.
##
## The sky is static, as splash_stars.gd intends. The strip is the only moving
## thing in the frame, and chrome that drifted would compete with it.

const STARS := preload("res://scripts/splash_stars.gd")

## splash.tscn's ground, and trailer_end_card.gd's. Kept in step with both by
## hand; neither can reference the other.
const NIGHT := Color(0.043, 0.063, 0.133)
const TITLE_COLOR := Color(2.3, 2.3, 2.3)
const SUB_COLOR := Color(1.45, 1.45, 1.45)
const BODY_COLOR := Color(1.25, 1.3, 1.45)

## The frame this is authored against -- the landscape stage 1:1, with no
## size_2d_override. The game scenes need an override because they are authored
## at 720x1280; this is new layout with no canvas to honour, so it is written
## directly in output pixels.
const FRAME := Vector2(1920.0, 1080.0)
## The gameplay strip, and the column left over beside it. SHOT_W is
## 1080 * 720/1280 rounded to a whole pixel (607.5 -> 608): the 0.08% of
## horizontal stretch that costs is not visible, and a fractional rect would be.
const SHOT_X := 120.0
const SHOT_W := 608.0
const GUTTER := 100.0
const PANEL_X := SHOT_X + SHOT_W + GUTTER
const PANEL_W := FRAME.x - PANEL_X - 120.0

## Vertical anchors for the panel's two blocks. The wordmark sits above the
## midline and the per-segment copy below it, so the block that changes every
## three seconds is not the one the eye has to re-find.
const WORDMARK_Y := 300.0
const WORDMARK_SUB_Y := 392.0
const HEADLINE_Y := 560.0
const BODY_Y := 648.0

const FADE := 0.32
const RISE_PX := 22.0

## The wordmark, held together so it can be faded as one thing. It is
## persistent chrome -- it does not change between segments -- but it still has
## to be *takeable*: the strip sweeps across this column on its way in from a
## full-bleed slate, and anything standing here while that happens is clipped
## by the strip's own black ground mid-letter.
var _brand: Control
var _headline: Label
var _body: Label
var _rule: ColorRect
var _copy_tween: Tween

func _ready() -> void:
	# The same glow the game scenes run, so the panel's type blooms the way the
	# type inside the strip does. Without it the overbright colours below are
	# just clamped to white and the panel reads as a slide pasted next to a
	# game rather than as part of one.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = env
	add_child(world_environment)

	var sky := CanvasLayer.new()
	sky.layer = -1
	add_child(sky)
	var ground := ColorRect.new()
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.anchor_right = 1.0
	ground.anchor_bottom = 1.0
	ground.offset_right = 0.0
	ground.offset_bottom = 0.0
	ground.color = NIGHT
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.add_child(ground)
	# After the ground so it draws over it, the same order splash.tscn uses.
	sky.add_child(STARS.new())

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

	_brand = Control.new()
	_brand.position = Vector2.ZERO
	_brand.size = FRAME
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_brand)
	_label(_brand, "JETLET", WORDMARK_Y, 84, TITLE_COLOR)
	_label(_brand, "SOLAR ESCAPE", WORDMARK_SUB_Y, 34, SUB_COLOR)

	# Sits between the wordmark and the copy, and is the one element that
	# carries the segment's own colour -- a 4px rule recolouring every three
	# seconds reads as the two halves of the frame belonging together, which a
	# recoloured headline does not (it just looks like inconsistent type).
	_rule = ColorRect.new()
	_rule.position = Vector2(PANEL_X, HEADLINE_Y - 56.0)
	_rule.size = Vector2(84.0, 4.0)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_rule)

	_headline = _label(content, "", HEADLINE_Y, 54, TITLE_COLOR)
	_body = _label(content, "", BODY_Y, 30, BODY_COLOR)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Room for the two or three lines the body wraps to; the label is top
	# aligned so a two-line and a three-line body start at the same height.
	_body.offset_bottom = _body.offset_top + 190.0
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Everything starts down. The first segment is a full-bleed slate that
	# covers this column entirely, and the panel is first seen being uncovered
	# by the strip rather than cut to.
	_brand.modulate.a = 0.0
	_rule.modulate.a = 0.0
	_headline.modulate.a = 0.0
	_body.modulate.a = 0.0

## Swaps in one segment's copy. Called on the swap, so the rise plays under the
## incoming shot's slide rather than after it.
func set_segment(headline: String, body: String, accent: Color) -> void:
	if _copy_tween != null and _copy_tween.is_valid():
		_copy_tween.kill()
	_headline.text = headline
	_body.text = body
	_rule.color = accent
	_copy_tween = create_tween().set_parallel()
	# The wordmark is brought up rather than reset first: between two strip
	# segments it is already up and this is a no-op, which is the point -- it
	# should not blink on every cut, only arrive once the column does.
	_copy_tween.tween_property(_brand, "modulate:a", 1.0, FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for node in [_rule, _headline, _body]:
		node.modulate.a = 0.0
		_copy_tween.tween_property(node, "modulate:a", 1.0, FADE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Only the text rises; the rule stays put so it reads as the fixed edge the
	# copy arrives against.
	for node in [_headline, _body]:
		var rest: float = node.offset_top
		node.offset_top = rest + RISE_PX
		node.offset_bottom += RISE_PX
		_copy_tween.tween_property(node, "offset_top", rest, FADE * 1.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_copy_tween.tween_property(node, "offset_bottom", node.offset_bottom - RISE_PX,
			FADE * 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Takes the copy away for the segments that cover the whole frame. The panel is
## behind them either way, but the end card grows over it across 0.42s and a
## stale headline sitting under that is the one frame of it anybody would see.
func clear() -> void:
	if _copy_tween != null and _copy_tween.is_valid():
		_copy_tween.kill()
	_copy_tween = create_tween().set_parallel()
	for node in [_brand, _rule, _headline, _body]:
		_copy_tween.tween_property(node, "modulate:a", 0.0, FADE) \
			.set_trans(Tween.TRANS_SINE)

func _label(parent: Control, text: String, top: float, font_size: int,
		color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	# Explicit offsets against the top-left rather than anchors: the panel is a
	# fixed column in a fixed frame, and anchors would only reintroduce a layout
	# pass that has to resolve before the first captured frame.
	label.offset_left = PANEL_X
	label.offset_right = PANEL_X + PANEL_W
	label.offset_top = top
	label.offset_bottom = top + float(font_size) * 1.4
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label
