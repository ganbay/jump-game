extends Node

## Firebase Crashlytics, via the godotx_firebase plugin's native Android
## singleton -- only present in an actual exported Android build with the
## Crashlytics module enabled (see export_presets.cfg's firebase/* options).
## Every call here is a safe no-op anywhere else: the editor, other
## platforms, and a build made before the plugin was installed.
##
## Catches native/engine crashes, not GDScript errors -- a GDScript runtime
## error doesn't kill the process, so this complements watching the
## console/log output during testing rather than replacing it.

var _crashlytics: Object = null

func _ready() -> void:
	if not Engine.has_singleton("GodotxFirebaseCore"):
		return
	var core: Object = Engine.get_singleton("GodotxFirebaseCore")
	core.core_initialized.connect(_on_core_initialized)
	core.initialize()

func _on_core_initialized(success: bool) -> void:
	if not success or not Engine.has_singleton("GodotxFirebaseCrashlytics"):
		return
	_crashlytics = Engine.get_singleton("GodotxFirebaseCrashlytics")
	_crashlytics.crashlytics_initialized.connect(_on_crashlytics_initialized)
	_crashlytics.initialize()

func _on_crashlytics_initialized(success: bool) -> void:
	if not success:
		_crashlytics = null
		return
	# The export plugin holds collection off by default (see
	# firebase/privacy_safe_defaults) so nothing is sent before Godot code
	# runs. Crash diagnostics carry no personal or advertising data, unlike
	# ads/analytics, so there's no consent choice from ads.gd's UMP flow to
	# gate this on -- it's enabled unconditionally once initialized.
	_crashlytics.set_crashlytics_collection_enabled(true)

## Breadcrumb, shown in the Crashlytics console alongside any crash that
## follows it. Safe to call before initialization finishes -- it just does
## nothing until then.
func log_message(message: String) -> void:
	if _crashlytics != null:
		_crashlytics.log_message(message)

## Dispatches to the native setter for the value's type. Deliberately not
## FirebaseCrashlyticsHelper: addons/godotx_firebase/ is excluded from the
## export, so naming that class made this whole autoload fail to parse on
## device -- and every Crash.* call site then errored out mid-function.
func set_custom_value(key: String, value) -> void:
	if _crashlytics == null:
		return
	match typeof(value):
		TYPE_BOOL:
			_crashlytics.set_custom_value_bool(key, value)
		TYPE_INT:
			_crashlytics.set_custom_value_int(key, value)
		TYPE_FLOAT:
			_crashlytics.set_custom_value_float(key, value)
		_:
			_crashlytics.set_custom_value_string(key, str(value))
