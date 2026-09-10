extends CanvasLayer

## The one door every scene change walks through, so a menu tap or a restart
## never reads as a hard cut. A plain full-screen rect is enough -- no need for
## a shader wipe when every screen already sits on black anyway.

const FADE_TIME := 0.28

var _rect: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

## Fades out, swaps the scene, fades back in. Not awaited by callers -- a
## button handler fires it and returns, and the coroutine runs to completion
## on its own.
func change_scene(path: String) -> void:
	await _fade(1.0)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await _fade(0.0)

## Same shape as change_scene(), for the restart button's scene reload.
func reload_scene() -> void:
	await _fade(1.0)
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await _fade(0.0)

func _fade(target_alpha: float) -> void:
	# Opaque (or on the way there) blocks clicks on whatever is underneath, so
	# a mashed button can't fire a second transition mid-fade.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE if target_alpha <= 0.0 else Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_rect, "color:a", target_alpha, FADE_TIME)
	await tw.finished
