extends Node

enum ControlScheme { TOUCH, TILT }
## Where the in-run score sits along the top edge. LEFT exists for phones whose
## front camera punches through the top centre, right where the score is.
enum ScoreAlign { CENTER, LEFT }

signal control_scheme_changed(scheme: ControlScheme)
signal visual_settings_changed
signal sound_muted_changed(muted: bool)

const SAVE_PATH := "user://settings.cfg"

## Multipliers on Player's base drag / tilt response, one per scheme since a
## good drag speed says nothing about a good tilt speed.
const SENSITIVITY_MIN := 0.5
const SENSITIVITY_MAX := 2.0
const SENSITIVITY_DEFAULT := 1.0

## Bumped when the default control scheme changes, so saves written under the
## old default move to the new one once. Early builds saved TOUCH on any
## settings change, so a stored scheme does not mean the player picked it.
const CONTROLS_DEFAULTS_VERSION := 1

const UI_OPACITY_MIN := 0.6
const UI_OPACITY_MAX := 1.0
const UI_OPACITY_DEFAULT := 0.8

## What a fresh install starts on, before the player has touched anything. The
## palette is the authored look of the game rather than each node's own base
## colour, so Player.COLOR and Platform.BASE_COLOR stay what they are for
## anything else that reads them. Each colour carries the slider position that
## produced it: a colour cannot be inverted back to a point on
## ColorSpectrumSlider's gradient, so without it the handle would jump to 0 the
## first time the settings screen opened.
const GLOW_STRENGTH_DEFAULT := 0.8
const PLAYER_COLOR_DEFAULT := Color(0.9039713, 0.74801433, 2.4, 1)
const PLAYER_COLOR_SLIDER_DEFAULT := 0.23285202
const PLATFORM_COLOR_DEFAULT := Color(0.7403599, 2.2, 0.6491324, 1)
const PLATFORM_COLOR_SLIDER_DEFAULT := 0.86967499
const PARTICLE_COLOR_DEFAULT := Color(1.0859209, 0.6570395, 2.4, 1)
const PARTICLE_COLOR_SLIDER_DEFAULT := 0.26534302

var control_scheme: ControlScheme = ControlScheme.TILT
var touch_sensitivity: float = SENSITIVITY_DEFAULT
var tilt_sensitivity: float = SENSITIVITY_DEFAULT
var glow_strength: float = GLOW_STRENGTH_DEFAULT
var player_color: Color = PLAYER_COLOR_DEFAULT
var platform_color: Color = PLATFORM_COLOR_DEFAULT
var background_particles: bool = true
var background_particle_color: Color = PARTICLE_COLOR_DEFAULT
var player_skin: Player.SkinType = Player.SkinType.PLASMA
var trail_enabled: bool = true
var sound_muted: bool = false
var score_align: ScoreAlign = ScoreAlign.LEFT
var haptics_enabled: bool = true
## How solid every label, button and readout draws, across the game. Floored
## well above zero: the pause button is the only way back out of a run, so the
## UI can be faded but never made invisible.
var ui_opacity: float = UI_OPACITY_DEFAULT
## Where each colour slider's handle sits along ColorSpectrumSlider's gradient
## (0..1) -- kept alongside the colour itself purely so the handle lands back
## in the same spot next visit, since a colour alone can't be inverted back to
## a position on the curve.
var player_color_slider: float = PLAYER_COLOR_SLIDER_DEFAULT
var platform_color_slider: float = PLATFORM_COLOR_SLIDER_DEFAULT
var particle_color_slider: float = PARTICLE_COLOR_SLIDER_DEFAULT

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		if int(cfg.get_value("controls", "defaults_version", 0)) >= CONTROLS_DEFAULTS_VERSION:
			control_scheme = cfg.get_value("controls", "scheme", ControlScheme.TILT) as ControlScheme
		touch_sensitivity = clampf(cfg.get_value("controls", "touch_sensitivity",
			SENSITIVITY_DEFAULT), SENSITIVITY_MIN, SENSITIVITY_MAX)
		tilt_sensitivity = clampf(cfg.get_value("controls", "tilt_sensitivity",
			SENSITIVITY_DEFAULT), SENSITIVITY_MIN, SENSITIVITY_MAX)
		glow_strength = cfg.get_value("visual", "glow_strength", GLOW_STRENGTH_DEFAULT)
		player_color = cfg.get_value("visual", "player_color", PLAYER_COLOR_DEFAULT)
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
		# The toggle used to mute only the music bus; a save from that era carries
		# its choice over to the mute that now covers everything.
		sound_muted = cfg.get_value("audio", "sound_muted",
			cfg.get_value("audio", "music_muted", false))
		haptics_enabled = cfg.get_value("audio", "haptics_enabled", true)
		score_align = cfg.get_value("visual", "score_align", ScoreAlign.LEFT) as ScoreAlign
		ui_opacity = clampf(cfg.get_value("visual", "ui_opacity", UI_OPACITY_DEFAULT),
			UI_OPACITY_MIN, UI_OPACITY_MAX)
		player_color_slider = cfg.get_value("visual", "player_color_slider", PLAYER_COLOR_SLIDER_DEFAULT)
		platform_color_slider = cfg.get_value("visual", "platform_color_slider", PLATFORM_COLOR_SLIDER_DEFAULT)
		particle_color_slider = cfg.get_value("visual", "particle_color_slider", PARTICLE_COLOR_SLIDER_DEFAULT)

func set_control_scheme(scheme: ControlScheme) -> void:
	if scheme == control_scheme:
		return
	control_scheme = scheme
	_save()
	control_scheme_changed.emit(scheme)

func toggle_control_scheme() -> void:
	set_control_scheme(ControlScheme.TILT if control_scheme == ControlScheme.TOUCH else ControlScheme.TOUCH)

func set_touch_sensitivity(value: float) -> void:
	touch_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	_save()

func set_tilt_sensitivity(value: float) -> void:
	tilt_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	_save()

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

func set_trail_enabled(value: bool) -> void:
	trail_enabled = value
	_save()
	visual_settings_changed.emit()

func set_sound_muted(value: bool) -> void:
	if value == sound_muted:
		return
	sound_muted = value
	_save()
	sound_muted_changed.emit(value)

func toggle_sound_muted() -> void:
	set_sound_muted(not sound_muted)

func set_ui_opacity(value: float) -> void:
	ui_opacity = clampf(value, UI_OPACITY_MIN, UI_OPACITY_MAX)
	_save()
	visual_settings_changed.emit()

func set_haptics_enabled(value: bool) -> void:
	haptics_enabled = value
	_save()

func toggle_haptics_enabled() -> void:
	set_haptics_enabled(not haptics_enabled)

func set_score_align(value: ScoreAlign) -> void:
	score_align = value
	_save()

func toggle_score_align() -> void:
	set_score_align(ScoreAlign.LEFT if score_align == ScoreAlign.CENTER else ScoreAlign.CENTER)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "scheme", control_scheme)
	cfg.set_value("controls", "defaults_version", CONTROLS_DEFAULTS_VERSION)
	cfg.set_value("controls", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("controls", "tilt_sensitivity", tilt_sensitivity)
	cfg.set_value("visual", "glow_strength", glow_strength)
	cfg.set_value("visual", "player_color", player_color)
	cfg.set_value("visual", "platform_color", platform_color)
	cfg.set_value("visual", "background_particles", background_particles)
	cfg.set_value("visual", "background_particle_color", background_particle_color)
	cfg.set_value("visual", "player_skin", player_skin)
	cfg.set_value("visual", "trail_enabled", trail_enabled)
	cfg.set_value("audio", "sound_muted", sound_muted)
	cfg.set_value("audio", "haptics_enabled", haptics_enabled)
	cfg.set_value("visual", "ui_opacity", ui_opacity)
	cfg.set_value("visual", "score_align", score_align)
	cfg.set_value("visual", "player_color_slider", player_color_slider)
	cfg.set_value("visual", "platform_color_slider", platform_color_slider)
	cfg.set_value("visual", "particle_color_slider", particle_color_slider)
	cfg.save(SAVE_PATH)
