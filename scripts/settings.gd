extends Node

enum ControlScheme { TOUCH, TILT }

signal control_scheme_changed(scheme: ControlScheme)
signal visual_settings_changed
signal music_muted_changed(muted: bool)

const SAVE_PATH := "user://settings.cfg"

var control_scheme: ControlScheme = ControlScheme.TOUCH
var glow_strength: float = 0.4
var player_color: Color = Player.COLOR
var platform_color: Color = Platform.BASE_COLOR
var background_particles: bool = true
var background_particle_color: Color = Color(0.3, 1.8, 2.4)
var player_skin: Player.SkinType = Player.SkinType.PLASMA
var trail_enabled: bool = true
var music_muted: bool = false
var haptics_enabled: bool = true
## Where each colour slider's handle sits along ColorSpectrumSlider's gradient
## (0..1) -- kept alongside the colour itself purely so the handle lands back
## in the same spot next visit, since a colour alone can't be inverted back to
## a position on the curve.
var player_color_slider: float = 0.0
var platform_color_slider: float = 0.0
var particle_color_slider: float = 0.0

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
		# The drift used to have a third "many colours" mode, drawn from the
		# platform type palette. Platforms are one colour now, so it is just on
		# or off; anything but the old OFF migrates to on.
		var legacy_fx := int(cfg.get_value("visual", "background_fx", 1))
		background_particles = cfg.get_value("visual", "background_particles", legacy_fx != 0)
		background_particle_color = cfg.get_value("visual", "background_particle_color", background_particle_color)
		player_skin = cfg.get_value("visual", "player_skin", Player.SkinType.PLASMA) as Player.SkinType
		trail_enabled = cfg.get_value("visual", "trail_enabled", true)
		music_muted = cfg.get_value("audio", "music_muted", false)
		haptics_enabled = cfg.get_value("audio", "haptics_enabled", true)
		player_color_slider = cfg.get_value("visual", "player_color_slider", 0.0)
		platform_color_slider = cfg.get_value("visual", "platform_color_slider", 0.0)
		particle_color_slider = cfg.get_value("visual", "particle_color_slider", 0.0)

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

func set_player_color(value: Color, slider_value: float) -> void:
	player_color = value
	player_color_slider = slider_value
	_save()
	visual_settings_changed.emit()

func set_platform_color(value: Color, slider_value: float) -> void:
	platform_color = value
	platform_color_slider = slider_value
	_save()
	visual_settings_changed.emit()

func set_background_particles(value: bool) -> void:
	background_particles = value
	_save()
	visual_settings_changed.emit()

func set_background_particle_color(value: Color, slider_value: float) -> void:
	background_particle_color = value
	particle_color_slider = slider_value
	_save()
	visual_settings_changed.emit()

func set_player_skin(value: Player.SkinType) -> void:
	player_skin = value
	_save()
	visual_settings_changed.emit()

func player_skin_name() -> String:
	return Player.SKIN_NAMES[player_skin]

func set_trail_enabled(value: bool) -> void:
	trail_enabled = value
	_save()
	visual_settings_changed.emit()

func set_music_muted(value: bool) -> void:
	if value == music_muted:
		return
	music_muted = value
	_save()
	music_muted_changed.emit(value)

func toggle_music_muted() -> void:
	set_music_muted(not music_muted)

func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_save()

func toggle_haptics_enabled() -> void:
	set_haptics_enabled(not haptics_enabled)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "scheme", control_scheme)
	cfg.set_value("visual", "glow_strength", glow_strength)
	cfg.set_value("visual", "player_color", player_color)
	cfg.set_value("visual", "platform_color", platform_color)
	cfg.set_value("visual", "background_particles", background_particles)
	cfg.set_value("visual", "background_particle_color", background_particle_color)
	cfg.set_value("visual", "player_skin", player_skin)
	cfg.set_value("visual", "trail_enabled", trail_enabled)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.set_value("audio", "haptics_enabled", haptics_enabled)
	cfg.set_value("visual", "player_color_slider", player_color_slider)
	cfg.set_value("visual", "platform_color_slider", platform_color_slider)
	cfg.set_value("visual", "particle_color_slider", particle_color_slider)
	cfg.save(SAVE_PATH)
