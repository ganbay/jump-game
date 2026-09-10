extends Node

enum ControlScheme { TOUCH, TILT }
enum BackgroundFxMode { OFF, MULTI, SINGLE }

signal control_scheme_changed(scheme: ControlScheme)
signal visual_settings_changed

const SAVE_PATH := "user://settings.cfg"

## Palette the MULTI background-particle mode draws from. It used to be the
## platform type colours; platforms are one colour now, so the drift keeps its
## own palette rather than losing its variety.
const MULTI_PALETTE := [
	Color(0.3, 1.0, 2.2),
	Color(2.2, 2.0, 0.3),
	Color(0.3, 2.4, 1.0),
	Color(2.4, 0.4, 0.5),
]

var control_scheme: ControlScheme = ControlScheme.TOUCH
var glow_strength: float = 0.4
var player_color: Color = Player.COLOR
var platform_color: Color = Platform.BASE_COLOR
var background_fx: BackgroundFxMode = BackgroundFxMode.MULTI
var background_particle_color: Color = Color(0.3, 1.8, 2.4)
var player_skin: Player.SkinType = Player.SkinType.BLOB
var trail_enabled: bool = true

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		control_scheme = cfg.get_value("controls", "scheme", ControlScheme.TOUCH) as ControlScheme
		glow_strength = cfg.get_value("visual", "glow_strength", 0.4)
		player_color = cfg.get_value("visual", "player_color", Player.COLOR)
		# Platforms used to be four colour-coded types; a save from that era
		# keeps its tint by falling back to what the plain platform was.
		var legacy := cfg.get_value("visual", "platform_color_0", platform_color) as Color
		platform_color = cfg.get_value("visual", "platform_color", legacy)
		background_fx = cfg.get_value("visual", "background_fx", BackgroundFxMode.MULTI) as BackgroundFxMode
		background_particle_color = cfg.get_value("visual", "background_particle_color", background_particle_color)
		player_skin = cfg.get_value("visual", "player_skin", Player.SkinType.BLOB) as Player.SkinType
		trail_enabled = cfg.get_value("visual", "trail_enabled", true)

func set_control_scheme(scheme: ControlScheme) -> void:
	if scheme == control_scheme:
		return
	control_scheme = scheme
	_save()
	control_scheme_changed.emit(scheme)

func toggle_control_scheme() -> void:
	set_control_scheme(ControlScheme.TILT if control_scheme == ControlScheme.TOUCH else ControlScheme.TOUCH)

func control_scheme_name() -> String:
	return "TILT" if control_scheme == ControlScheme.TILT else "TOUCH"

func set_glow_strength(value: float) -> void:
	glow_strength = value
	_save()
	visual_settings_changed.emit()

func set_player_color(value: Color) -> void:
	player_color = value
	_save()
	visual_settings_changed.emit()

func set_platform_color(value: Color) -> void:
	platform_color = value
	_save()
	visual_settings_changed.emit()

func set_background_fx(mode: BackgroundFxMode) -> void:
	background_fx = mode
	_save()
	visual_settings_changed.emit()

func cycle_background_fx() -> void:
	set_background_fx(((background_fx + 1) % 3) as BackgroundFxMode)

func background_fx_name() -> String:
	match background_fx:
		BackgroundFxMode.OFF:
			return "OFF"
		BackgroundFxMode.SINGLE:
			return "SINGLE"
		_:
			return "MULTI"

func set_background_particle_color(value: Color) -> void:
	background_particle_color = value
	_save()
	visual_settings_changed.emit()

func set_player_skin(value: Player.SkinType) -> void:
	player_skin = value
	_save()
	visual_settings_changed.emit()

func cycle_player_skin() -> void:
	set_player_skin(((player_skin + 1) % Player.SkinType.size()) as Player.SkinType)

func player_skin_name() -> String:
	return Player.SKIN_NAMES[player_skin]

func set_trail_enabled(value: bool) -> void:
	trail_enabled = value
	_save()
	visual_settings_changed.emit()

func toggle_trail() -> void:
	set_trail_enabled(not trail_enabled)

func trail_name() -> String:
	return "ON" if trail_enabled else "OFF"

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "scheme", control_scheme)
	cfg.set_value("visual", "glow_strength", glow_strength)
	cfg.set_value("visual", "player_color", player_color)
	cfg.set_value("visual", "platform_color", platform_color)
	cfg.set_value("visual", "background_fx", background_fx)
	cfg.set_value("visual", "background_particle_color", background_particle_color)
	cfg.set_value("visual", "player_skin", player_skin)
	cfg.set_value("visual", "trail_enabled", trail_enabled)
	cfg.save(SAVE_PATH)
