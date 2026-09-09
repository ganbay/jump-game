extends Node

const SFX_UI_CLICK := preload("res://audio/sfx/ui_click.wav")

const MUSIC_MENU := preload("res://audio/music/menu_ambient.ogg")

## Each run randomly picks one lead+drum pairing to play. Add more sets
## here to pull them into the rotation.
const MUSIC_SETS := [
	{
		"lead": preload("res://audio/music/gameplay_asap_125bpm.ogg"),
		"drum": preload("res://audio/music/gameplay_indie_drums_125bpm_v2.ogg"),
		"bpm": 125.0,
	},
	{
		"lead": preload("res://audio/music/gameplay_pad_155bpm.ogg"),
		"drum": preload("res://audio/music/gameplay_dnb_drums_155bpm.ogg"),
		"bpm": 155.0,
	},
]

const SFX_POOL_SIZE := 6

const STREAK_TIER_1 := 1
const STREAK_TIER_2 := 5
const STREAK_TIER_3 := 10
const LAYER_FADE_TIME := 0.6
const MUSIC_INTRO_FADE_TIME := 1.5
const LAYER_SILENT_DB := -80.0

const LEAD_START_VOLUME := 0.75
const LEAD_BOOST_VOLUME := 1.0
const DRUM_START_VOLUME := 0.10
const DRUM_MID_VOLUME := 0.50
const DRUM_BOOST_VOLUME := 0.80

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _lead_player: AudioStreamPlayer
var _drum_player: AudioStreamPlayer
var _menu_player: AudioStreamPlayer
var _streak_tier := -1
var _drum_started := false
var _bar_length := 0.0
var _layer_tweens: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_lead_player = _make_music_player(null)
	_drum_player = _make_music_player(null)
	_menu_player = _make_music_player(MUSIC_MENU)
	_lead_player.finished.connect(func(): _lead_player.play(0.0))
	_drum_player.finished.connect(func(): _drum_player.play(0.0))
	_menu_player.finished.connect(func(): _menu_player.play(0.0))

func _make_music_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p

func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func play_ui_click() -> void:
	_play_sfx(SFX_UI_CLICK, -4.0)

func play_menu_music() -> void:
	_stop_gameplay_music()
	if not _menu_player.playing:
		_menu_player.volume_db = 0.0
		_menu_player.play(0.0)

## Rolls a random lead+drum set for this run and (re)starts it fresh with a
## fade-in, even if a previous run's set is still playing — so a restart
## after game over can roll a different pairing.
func play_music() -> void:
	if _menu_player.playing:
		_menu_player.stop()
	_stop_gameplay_music()
	var music_set: Dictionary = MUSIC_SETS[randi() % MUSIC_SETS.size()]
	_lead_player.stream = music_set["lead"]
	_drum_player.stream = music_set["drum"]
	_bar_length = 60.0 / music_set["bpm"] * 4.0
	_streak_tier = 0
	_lead_player.volume_db = LAYER_SILENT_DB
	_lead_player.play(0.0)
	_fade_layer(_lead_player, linear_to_db(LEAD_START_VOLUME), MUSIC_INTRO_FADE_TIME)

## Ducks the gameplay layers out and brings the ambient menu track in
## underneath them, without stopping or resetting gameplay playback — so
## fade_to_gameplay_music() can bring it back exactly where it left off.
func fade_to_menu_music() -> void:
	_fade_layer(_lead_player, LAYER_SILENT_DB)
	if _drum_started:
		_fade_layer(_drum_player, LAYER_SILENT_DB)
	if not _menu_player.playing:
		_menu_player.volume_db = LAYER_SILENT_DB
		_menu_player.play(0.0)
	_fade_layer(_menu_player, 0.0)

## Reverses fade_to_menu_music(): fades the menu track back out and brings
## the gameplay layers back up to whatever their current streak tier is.
func fade_to_gameplay_music() -> void:
	_fade_layer(_menu_player, LAYER_SILENT_DB)
	_fade_layer(_lead_player, linear_to_db(LEAD_BOOST_VOLUME if _streak_tier >= 1 else LEAD_START_VOLUME))
	if _drum_started:
		_fade_layer(_drum_player, linear_to_db(DRUM_BOOST_VOLUME if _streak_tier >= 3 else DRUM_MID_VOLUME))

func _stop_gameplay_music() -> void:
	if _lead_player.playing:
		_lead_player.stop()
	if _drum_player.playing:
		_drum_player.stop()
	_streak_tier = -1
	_drum_started = false

## Lead loop plays from the start, boosted to full volume on the first
## streak. The drum loop joins in (bar-synced) at streak 5 and gets
## boosted again at streak 10 — instead of a one-off streak sfx cue.
func set_streak(streak: int) -> void:
	var tier := 0
	if streak >= STREAK_TIER_3:
		tier = 3
	elif streak >= STREAK_TIER_2:
		tier = 2
	elif streak >= STREAK_TIER_1:
		tier = 1
	if tier == _streak_tier:
		return
	_streak_tier = tier
	_fade_layer(_lead_player, linear_to_db(LEAD_BOOST_VOLUME if tier >= 1 else LEAD_START_VOLUME))
	if tier >= 2:
		if not _drum_started:
			_start_drum_layer()
		else:
			_fade_layer(_drum_player, linear_to_db(DRUM_BOOST_VOLUME if tier >= 3 else DRUM_MID_VOLUME))
	elif _drum_started:
		_drum_started = false
		_fade_layer(_drum_player, LAYER_SILENT_DB)

## Starts the drum loop on the next bar boundary of the lead loop's
## playback so the two stay phase-locked despite differing loop lengths.
func _start_drum_layer() -> void:
	_drum_started = true
	var phase := fmod(_lead_player.get_playback_position(), _bar_length)
	var delay := _bar_length - phase
	get_tree().create_timer(delay).timeout.connect(func():
		_drum_player.volume_db = linear_to_db(DRUM_START_VOLUME)
		_drum_player.play(0.0)
		_fade_layer(_drum_player, linear_to_db(DRUM_MID_VOLUME))
	)

func _fade_layer(player: AudioStreamPlayer, target_db: float, duration: float = LAYER_FADE_TIME) -> void:
	if _layer_tweens.has(player):
		(_layer_tweens[player] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(player, "volume_db", target_db, duration).set_trans(Tween.TRANS_SINE)
	_layer_tweens[player] = tw
