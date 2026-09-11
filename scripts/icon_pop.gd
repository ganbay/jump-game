class_name IconPop

## Hover and press feel for the icon buttons that replaced the game's text
## menus. Kept in one place so the main menu, the pause panel and the game over
## panel cannot drift apart -- an unlabelled glyph has no text to grey out, so
## scale is the only state it can show.

const HOVER_SCALE := 1.15
const PUNCH_SCALE := 1.32
const HOVER_TIME := 0.12
const PUNCH_TIME := 0.07

const HINT_SWELL := 1.14
const HINT_BEAT := 0.9
const HINT_DIM := 0.45

const TWEEN_META := "icon_pop_tween"

static func attach(buttons: Array) -> void:
	for button in buttons:
		button.mouse_entered.connect(IconPop._scale.bind(button, HOVER_SCALE, HOVER_TIME))
		button.mouse_exited.connect(IconPop._scale.bind(button, 1.0, HOVER_TIME))
		button.button_down.connect(IconPop._punch.bind(button))

static func _scale(button: Button, target: float, duration: float) -> void:
	var tw := _fresh_tween(button)
	tw.tween_property(button, "scale", Vector2.ONE * target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Snaps out and settles back to whatever the pointer is doing -- on a phone
## there is no hover, so that is always plain rest.
static func _punch(button: Button) -> void:
	var settle := HOVER_SCALE if button.is_hovered() else 1.0
	var tw := _fresh_tween(button)
	tw.tween_property(button, "scale", Vector2.ONE * PUNCH_SCALE, PUNCH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "scale", Vector2.ONE * settle, PUNCH_TIME * 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The tween is created on the button rather than on a menu script, so a pause
## panel button -- whose panel runs while the tree is paused -- still animates.
## Pivot is set per call because a Control has no resolved size until the first
## layout pass, and a zero pivot grows the button out of its top-left corner.
static func _fresh_tween(button: Button) -> Tween:
	button.pivot_offset = button.size / 2.0
	if button.has_meta(TWEEN_META):
		var old: Tween = button.get_meta(TWEEN_META)
		if old != null and old.is_valid():
			old.kill()
	var tw := button.create_tween()
	button.set_meta(TWEEN_META, tw)
	return tw

## Breathes a tap prompt so it reads as an invitation rather than decor. Bound
## to the icon, so a prompt inside a panel that runs while paused keeps moving.
static func pulse(icon: Control, label: Control) -> void:
	icon.pivot_offset = icon.size / 2.0
	var tw := icon.create_tween().set_loops()
	tw.tween_property(icon, "scale", Vector2.ONE * HINT_SWELL, HINT_BEAT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(icon, "modulate:a", 1.0, HINT_BEAT)
	tw.parallel().tween_property(label, "modulate:a", 1.0, HINT_BEAT)
	tw.tween_property(icon, "scale", Vector2.ONE, HINT_BEAT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(icon, "modulate:a", HINT_DIM, HINT_BEAT)
	tw.parallel().tween_property(label, "modulate:a", HINT_DIM, HINT_BEAT)
