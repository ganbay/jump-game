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
const SENSITIVITY_MIN := 0.6
const SENSITIVITY_MAX := 1.5
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
## Platform and drift colour are no longer player-set: they are dressed per zone
## at runtime, by ZoneAmbience multiplying the zone's hue over these (see
## customization.gd for the hidden pickers, and zone_ambience.gd for the tints).
##
## Near-white, and HDR at roughly the peak the old authored colours sat at, for
## two reasons: a multiply can only take brightness away, so a neutral base is
## the only one a zone can push to any hue cleanly -- and OPEN SPACE applies no
## tint at all, so this is also literally what the opening stretch looks like.
##
## Leans very slightly warm. It used to lean the other way, and since every
## tinted surface in the game is this base multiplied by a hue, a cool base put
## a faint blue under all of them at once -- which is most of why the palette
## read as blue overall even where the zone was not. A neutral that errs warm
## costs nothing and takes that cast off everything in one place.
const PLATFORM_COLOR_NEUTRAL := Color(2.15, 2.08, 2.0, 1)
const PARTICLE_COLOR_NEUTRAL := Color(2.15, 2.08, 2.0, 1)

var control_scheme: ControlScheme = ControlScheme.TILT
var touch_sensitivity: float = SENSITIVITY_DEFAULT
var tilt_sensitivity: float = SENSITIVITY_DEFAULT
var glow_strength: float = GLOW_STRENGTH_DEFAULT
var player_color: Color = PLAYER_COLOR_DEFAULT
var platform_color: Color = PLATFORM_COLOR_NEUTRAL  # was PLATFORM_COLOR_DEFAULT
## How the platforms' colour relates to the zone's: opposite it on the wheel,
## or the same hue as it. Stored as a bool rather than as
## ZoneAmbience.PaletteMode because that enum's script reaches Settings again
## through ZoneDirector and Platform, and naming the type here would close the
## cycle. game.gd maps it (see _apply_zone_ambience).
var platform_complementary: bool = true
var background_particles: bool = true
var background_particle_color: Color = PARTICLE_COLOR_NEUTRAL  # was PARTICLE_COLOR_DEFAULT
var player_skin: Player.SkinType = Player.SkinType.PLASMA
## Shuffle mode: every run wears a different unlocked character, drawn fresh
## at the start of it. player_skin is left alone while this is on -- it stays
## whatever the picker was last parked on -- so switching shuffle off puts the
## player straight back on the character they chose rather than stranding them
## on whatever the last run happened to roll.
var shuffle_skin: bool = false
var trail_enabled: bool = true
var sound_muted: bool = false
var score_align: ScoreAlign = ScoreAlign.LEFT
var haptics_enabled: bool = true
## Whether the in-run coaching appears: the steer prompt at the start of a run
## and the tap-to-flare lesson on the first landing. On for everyone by
## default and shown every run rather than only the first, since a player who
## dies in the opening seconds has learnt nothing yet and a run is cheap to
## start over. Both the tutorial panel's own dismiss button and the settings
## row turn it off, which is the escape hatch for anyone who already knows.
var tutorial_hints: bool = true
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
## The character this run rolled under shuffle, or -1 for none. Deliberately
## not saved: it belongs to a single run, not to the player's preferences.
var _shuffled_skin: int = -1

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
		# Platform colour is zone-driven now, so a saved one is deliberately NOT
		# read back -- an existing save would otherwise restore a colour the
		# player can no longer see or change. The value stays in the file
		# untouched, so uncommenting this restores their old pick intact.
		# Platforms used to be four colour-coded types; a save from that era
		# keeps its tint by falling back to what the plain platform was.
		# var legacy := cfg.get_value("visual", "platform_color_0", platform_color) as Color
		# platform_color = cfg.get_value("visual", "platform_color", legacy)
		# The drift used to have a third "many colours" mode, drawn from the
		# platform type palette. Platforms are one colour now, so it is just on
		# or off; anything but the old OFF migrates to on.
		platform_complementary = cfg.get_value("visual", "platform_complementary", true)
		var legacy_fx := int(cfg.get_value("visual", "background_fx", 1))
		background_particles = cfg.get_value("visual", "background_particles", legacy_fx != 0)
		# Zone-driven now, same as platform_color above.
		# background_particle_color = cfg.get_value("visual", "background_particle_color", background_particle_color)
		player_skin = cfg.get_value("visual", "player_skin", Player.SkinType.PLASMA) as Player.SkinType
		shuffle_skin = cfg.get_value("visual", "shuffle_skin", false)
		trail_enabled = cfg.get_value("visual", "trail_enabled", true)
		# The toggle used to mute only the music bus; a save from that era carries
		# its choice over to the mute that now covers everything.
		sound_muted = cfg.get_value("audio", "sound_muted",
			cfg.get_value("audio", "music_muted", false))
		haptics_enabled = cfg.get_value("audio", "haptics_enabled", true)
		# Saves written before the hints existed have nothing stored here, and
		# default to on -- a returning player sees them once and can switch
		# them off from the panel itself.
		tutorial_hints = cfg.get_value("gameplay", "tutorial_hints", true)
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

## Zero intensity still runs the full-screen blur, so the slider's bottom end
## switches the pass off entirely -- the cheap setting for weak GPUs.
func apply_glow(env: Environment) -> void:
	env.glow_intensity = glow_strength
	env.glow_enabled = glow_strength > 0.0

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

func set_platform_complementary(value: bool) -> void:
	platform_complementary = value
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

## What the character is wearing right now: the rolled skin during a shuffled
## run, the chosen one otherwise. The roll only ever happens from a run
## starting (see game.gd), so the trailer, icon and feature-graphic tools --
## which set player_skin directly and never roll -- are unaffected by a player
## who happens to have shuffle switched on.
func active_player_skin() -> Player.SkinType:
	if shuffle_skin and _shuffled_skin >= 0:
		return _shuffled_skin as Player.SkinType
	return player_skin

func set_shuffle_skin(value: bool) -> void:
	if value == shuffle_skin:
		return
	shuffle_skin = value
	if not value:
		_shuffled_skin = -1
	_save()
	visual_settings_changed.emit()

## Draws the character for one run. Called as a run starts rather than at a
## fixed interval, so "each run is someone new" is literally what it does.
func roll_shuffled_skin() -> void:
	if not shuffle_skin:
		_shuffled_skin = -1
		return
	var pool: Array[int] = []
	for skin in range(Player.SkinType.size()):
		if Unlocks.is_unlocked(Unlocks.skin_id(skin)):
			pool.append(skin)
	if pool.is_empty():
		_shuffled_skin = -1
		return
	# Never the same character twice running when there is another to hand:
	# a shuffle that repeats itself does not read as a shuffle at all. With
	# only one unlocked there is nothing to vary, and it simply stays.
	if pool.size() > 1:
		pool.erase(_shuffled_skin)
	_shuffled_skin = pool.pick_random()
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

func set_tutorial_hints(value: bool) -> void:
	tutorial_hints = value
	_save()

func toggle_tutorial_hints() -> void:
	set_tutorial_hints(not tutorial_hints)

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
	# Left out of the save alongside its load, so the player's old pick stays
	# in the file as they left it rather than being overwritten with neutral.
	# cfg.set_value("visual", "platform_color", platform_color)
	cfg.set_value("visual", "platform_complementary", platform_complementary)
	cfg.set_value("visual", "background_particles", background_particles)
	# cfg.set_value("visual", "background_particle_color", background_particle_color)
	cfg.set_value("visual", "player_skin", player_skin)
	cfg.set_value("visual", "shuffle_skin", shuffle_skin)
	cfg.set_value("visual", "trail_enabled", trail_enabled)
	cfg.set_value("audio", "sound_muted", sound_muted)
	cfg.set_value("audio", "haptics_enabled", haptics_enabled)
	cfg.set_value("gameplay", "tutorial_hints", tutorial_hints)
	cfg.set_value("visual", "ui_opacity", ui_opacity)
	cfg.set_value("visual", "score_align", score_align)
	cfg.set_value("visual", "player_color_slider", player_color_slider)
	cfg.set_value("visual", "platform_color_slider", platform_color_slider)
	cfg.set_value("visual", "particle_color_slider", particle_color_slider)
	cfg.save(SAVE_PATH)
