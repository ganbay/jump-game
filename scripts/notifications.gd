extends Node

## Local notification scheduling, stubbed.
##
## Godot ships no local-notification API, and this project exports with
## gradle_build/use_gradle_build=false and no android/ folder, so it is on the
## prebuilt APK template and cannot host an Android plugin at all yet. Every
## call here is a no-op that logs what it would have scheduled.
##
## To make it real: Project > Install Android Build Template, add a notification
## scheduler plugin, set permissions/post_notifications=true in the export
## preset (mandatory from Android 13, and it also needs a runtime request), then
## fill in the three functions below. Nothing that calls them has to change.
##
## Note on the intent behind the morning one: Android has not allowed a
## manifest-registered ACTION_SCREEN_ON since API 26, so "when the player first
## turns the display on" cannot be detected without a foreground service. A
## notification *scheduled* for the morning achieves the same thing -- it is
## sitting on the lock screen the next time the display comes on.

## Ids so a scheduled notification can be replaced or cancelled by name.
const MORNING := "missions_morning"
const EVENING := "missions_evening"

## False until the plugin is in. Callers use it to skip asking for permission
## and to avoid promising a reminder the build cannot deliver.
func is_supported() -> bool:
	return false

## Schedules `body` to fire at the next occurrence of hour:minute local time,
## replacing any pending notification with the same id.
func schedule_daily(id: String, hour: int, minute: int, title: String, body: String) -> void:
	if not is_supported():
		print("[notify] would schedule %s at %02d:%02d -- %s: %s" % [id, hour, minute, title, body])
		return

func cancel(id: String) -> void:
	if not is_supported():
		print("[notify] would cancel %s" % id)
		return
