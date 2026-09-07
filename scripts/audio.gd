extends Node

const SFX_JUMP := preload("res://audio/sfx/jump.wav")
const SFX_STREAK := preload("res://audio/sfx/streak.wav")
const SFX_GAME_OVER := preload("res://audio/sfx/game_over.wav")
const SFX_UI_CLICK := preload("res://audio/sfx/ui_click.wav")
const MUSIC_GAMEPLAY := preload("res://audio/music/gameplay_loop.wav")

const SFX_POOL_SIZE := 6

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = MUSIC_GAMEPLAY
	_music_player.finished.connect(_music_player.play.bind(0.0))
	add_child(_music_player)

func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func play_jump() -> void:
	_play_sfx(SFX_JUMP)

func play_streak() -> void:
	_play_sfx(SFX_STREAK)

func play_game_over() -> void:
	_play_sfx(SFX_GAME_OVER)

func play_ui_click() -> void:
	_play_sfx(SFX_UI_CLICK, -4.0)

func play_music() -> void:
	if not _music_player.playing:
		_music_player.play()
