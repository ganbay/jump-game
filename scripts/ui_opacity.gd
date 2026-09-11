class_name UiOpacity

## Applies Settings.ui_opacity to every readable Control under a screen's UI
## layer -- labels, buttons, sliders, icons -- in one walk, so a screen does not
## have to know which of its nodes are text and which are glyphs.

## Colour AND alpha, not alpha alone. The UI is authored overbright so the
## WorldEnvironment glow picks it up -- titles at 2.3, icons at 1.5, most labels
## above 1.2 -- and blending only the alpha leaves anything over 1.0 still
## clipping to solid white: at 80% a 2.3 title came out at 1.84 and looked
## untouched, and the brightest text did not begin to move until 43%. Scaling
## the colour too brings those values down into range, and is the identity at
## 100%, so nothing changes for a player who leaves the slider alone.
static func tint(opacity: float) -> Color:
	return Color(opacity, opacity, opacity, opacity)

## self_modulate, never modulate: the HUD drop-in, the pause and game over panel
## pops, and the tap-prompt pulses all tween `modulate:a` on these same nodes,
## and would wipe the setting out the first time they ran. self_modulate is a
## separate channel that multiplies with those, so a dimmed HUD still animates.
##
## ColorRects are skipped: the only ones under a UI layer are the full-screen
## dims behind the pause and game over panels, and thinning those would show the
## run through the menu sitting on top of it.
static func apply(root: Node) -> void:
	var shade := tint(Settings.ui_opacity)
	_paint(root, shade)

static func _paint(root: Node, shade: Color) -> void:
	for child in root.get_children():
		if child is Control and not child is ColorRect:
			child.self_modulate = shade
		_paint(child, shade)
