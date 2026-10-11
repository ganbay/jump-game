extends CanvasLayer

## The one door every scene change walks through, so a menu tap or a restart
## never reads as a hard cut. A plain full-screen rect is enough -- no need for
## a shader wipe when every screen already sits on black anyway.

## Emitted when change_scene() could not load the target -- a scene that is
## broken or, on an exported build, missing from the pack. Callers that latch a
## "already leaving" flag listen for this so one bad scene doesn't leave their
## screen permanently unable to navigate anywhere.
signal scene_change_failed(path: String)

const FADE_TIME := 0.28

## Overlays that the Android back button closes before it does anything else
## (the race guide, history and report panels). Each adds itself on opening.
const BACK_DISMISS_GROUP := "back_dismiss"

var _rect: ColorRect
## True from a fade starting until the new scene is fully faded in, so a back
## press cannot act on a screen that is already on its way out.
var _busy: bool = false

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
	_busy = true
	await _fade(1.0)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[transition] could not change to %s (error %d)" % [path, err])
	await get_tree().process_frame
	await _fade(0.0)
	_busy = false
	if err != OK:
		scene_change_failed.emit(path)

## The Android back button (application/config/quit_on_go_back is off, so it no
## longer kills the app on the spot). An open overlay closes first; otherwise
## the current scene decides through its own go_back(), and a scene without
## one -- the splash -- ignores the button.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _busy:
		return
	var overlays := get_tree().get_nodes_in_group(BACK_DISMISS_GROUP)
	overlays.reverse()
	for overlay in overlays:
		if not overlay.is_queued_for_deletion() and overlay.has_method("go_back"):
			overlay.go_back()
			return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("go_back"):
		scene.go_back()

## Same shape as change_scene(), for the restart button's scene reload.
func reload_scene() -> void:
	_busy = true
	await _fade(1.0)
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await _fade(0.0)
	_busy = false

func _fade(target_alpha: float) -> void:
	# Opaque (or on the way there) blocks clicks on whatever is underneath, so
	# a mashed button can't fire a second transition mid-fade.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE if target_alpha <= 0.0 else Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_rect, "color:a", target_alpha, FADE_TIME)
	await tw.finished
