@tool
extends EditorPlugin

## Adds bin/jetlet-notify.aar to Android exports. The AAR registers the
## "JetletNotify" singleton that scripts/notifications.gd talks to; its source
## is in android_src/ (hidden from Godot by a .gdignore).

var _export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "JetletNotify"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	## One AAR for both variants: it has no debug-only behaviour.
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/jetlet_notify/bin/jetlet-notify.aar"])
