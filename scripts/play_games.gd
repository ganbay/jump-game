extends Node

## Google Play Games: cloud save and leaderboards, backed by the
## GodotPlayGameServices Android plugin (addons/GodotPlayGameServices).
## Everywhere else -- the editor, desktop, a build without the plugin -- every
## call is a silent no-op.
##
## Talks to the Android singleton directly rather than through the plugin's
## GDScript clients, the same way notifications.gd does, so nothing here
## depends on the plugin's own autoload or on the order the two load in.
##
## Cloud save: one snapshot holding Stats, Unlocks and the high score. Local
## files stay the source of truth for play; the cloud copy is merged in once
## per launch, right after sign-in, and written back shortly after every local
## save. Nothing is ever uploaded before that first merge has happened --
## otherwise a fresh install would overwrite a long-standing cloud save with
## an empty one the moment its first run ended.
##
## Sign-in: Play Games signs the player in by itself at launch when it can.
## A player who is not signed in is never nagged; the only manual prompt is
## the one behind the leaderboard button.

signal signed_in_changed(signed_in: bool)

const PLUGIN := "GodotPlayGameServices"

## From Play Console > Play Games Services > Leaderboards. Left empty, that
## board is simply never submitted to.
const LEADERBOARD_HIGH_SCORE := "CgkI66D7hrcIEAIQAQ"
## Fastest won AI race per distance, in the order of Race.TARGETS.
const LEADERBOARD_RACE_SPEED := [
	"CgkI66D7hrcIEAIQAg",  # 10k
	"CgkI66D7hrcIEAIQAw",  # 20k
	"CgkI66D7hrcIEAIQBA",  # 30k
]
## Play scores are whole numbers; a board set to one decimal place in the
## console shows a submitted 123 as 12.3, so speeds go up multiplied by this.
const SPEED_SCALE := 10.0

const SAVE_NAME := "jetlet_save"
const SAVE_DESCRIPTION := "Jetlet progress"
## Bumped if the layout of the snapshot ever changes incompatibly.
const CLOUD_VERSION := 1
## Local saves come in bursts (a run ending writes the high score, the stats
## and sometimes an unlock); one upload after the burst covers all of them.
const UPLOAD_DELAY := 2.0
## Owned by game.gd; read and, after a cloud merge, written here.
const HIGH_SCORE_PATH := "user://highscore.cfg"

var signed_in: bool = false

var _plugin: Object = null
## True once the cloud snapshot has been read (or found not to exist) this
## session. Uploads wait for it -- see the note on cloud save above.
var _synced: bool = false
var _upload_timer: Timer
var _show_after_sign_in: bool = false

func _ready() -> void:
	# The game-over panel can sit on a paused tree (the revive offer), and the
	# upload that follows a run must not wait for the player to leave it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton(PLUGIN):
		return
	_plugin = Engine.get_singleton(PLUGIN)
	_plugin.initialize()
	_plugin.connect("userAuthenticated", _on_authenticated)
	_plugin.connect("gameLoaded", _on_game_loaded)
	_upload_timer = Timer.new()
	_upload_timer.one_shot = true
	_upload_timer.wait_time = UPLOAD_DELAY
	_upload_timer.timeout.connect(_on_upload_timeout)
	add_child(_upload_timer)
	Stats.saved.connect(_queue_upload)
	Unlocks.saved.connect(_queue_upload)
	_plugin.isAuthenticated()

## False on anything but an Android build carrying the plugin, so callers can
## leave out UI that would do nothing.
func is_available() -> bool:
	return _plugin != null

## --- Leaderboards ----------------------------------------------------------

## Play keeps only a player's best per board, so every run is sent as-is.
func submit_run(score: int) -> void:
	_submit(LEADERBOARD_HIGH_SCORE, score)

## A won AI race: `speed` is score per second over the whole distance. Losses
## and LAN races are not sent -- a loss never covered the distance, and a LAN
## race has items and a host-chosen distance, so its speed is not comparable.
func submit_race_speed(target_index: int, speed: float) -> void:
	if target_index >= 0 and target_index < LEADERBOARD_RACE_SPEED.size():
		_submit(LEADERBOARD_RACE_SPEED[target_index], roundi(speed * SPEED_SCALE))

## Opens Play's own leaderboard screen. A player who is not signed in gets the
## sign-in prompt first, and the screen opens once it succeeds.
func show_leaderboards() -> void:
	if _plugin == null:
		return
	if signed_in:
		_plugin.showAllLeaderboards()
	else:
		_show_after_sign_in = true
		_plugin.signIn()

func _submit(leaderboard_id: String, value: int) -> void:
	if signed_in and leaderboard_id != "" and value > 0:
		_plugin.submitScore(leaderboard_id, value)

## --- Sign-in ---------------------------------------------------------------

func _on_authenticated(is_authenticated: bool) -> void:
	var show := _show_after_sign_in
	_show_after_sign_in = false
	if is_authenticated != signed_in:
		signed_in = is_authenticated
		signed_in_changed.emit(signed_in)
	if not signed_in:
		return
	if not _synced:
		_plugin.loadGame(SAVE_NAME, false)
	if show:
		_plugin.showAllLeaderboards()

## --- Cloud save ------------------------------------------------------------

func _queue_upload() -> void:
	if _plugin != null:
		_upload_timer.start()

func _on_upload_timeout() -> void:
	if not signed_in:
		return
	# The plugin reports nothing when a load fails (offline, Saved Games off),
	# so a load that never answered is asked again here; its answer uploads.
	if not _synced:
		_plugin.loadGame(SAVE_NAME, false)
		return
	var state := {
		"version": CLOUD_VERSION,
		"high_score": _local_high_score(),
		"stats": Stats.cloud_state(),
		"unlocks": Unlocks.cloud_state(),
	}
	# games_played doubles as the snapshot's progress value: the plugin opens
	# with "highest progress wins", so two devices saving at once keep the one
	# that has played more.
	_plugin.saveGame(SAVE_NAME, SAVE_DESCRIPTION,
		Marshalls.variant_to_base64(state).to_ascii_buffer(),
		int(Stats.total_time * 1000.0), Stats.games_played)

## `json` is the plugin's snapshot as JSON, or "null" when the player has no
## cloud save yet.
func _on_game_loaded(json: String) -> void:
	var first := not _synced
	_synced = true
	var snapshot: Variant = JSON.parse_string(json)
	if snapshot is Dictionary:
		_merge(_decode(snapshot.get("content")))
	if first:
		# Whatever this device had before the leaderboards existed, or earned
		# while signed out.
		submit_run(_local_high_score())
		for i in range(Race.TARGETS.size()):
			submit_race_speed(i, Stats.race_best_speed(Race.TARGETS[i]))
	# Also covers the no-snapshot case, where this is the first cloud save.
	_queue_upload()

## The snapshot's bytes arrive as a JSON array of *signed* Java bytes.
func _decode(content: Variant) -> Dictionary:
	if content is not Array or content.is_empty():
		return {}
	var bytes := PackedByteArray()
	bytes.resize(content.size())
	for i in range(content.size()):
		bytes[i] = int(content[i]) & 0xFF
	var state: Variant = Marshalls.base64_to_variant(bytes.get_string_from_ascii())
	return state if state is Dictionary else {}

func _merge(state: Dictionary) -> void:
	if state.is_empty() or int(state.get("version", 0)) > CLOUD_VERSION:
		return
	var stats: Variant = state.get("stats")
	if stats is Dictionary:
		Stats.merge_cloud(stats)
	var unlocks: Variant = state.get("unlocks")
	if unlocks is Dictionary:
		Unlocks.merge_cloud(unlocks)
	var cloud_high := int(state.get("high_score", 0))
	if cloud_high > _local_high_score():
		var cfg := ConfigFile.new()
		cfg.set_value("scores", "high_score", cloud_high)
		cfg.save(HIGH_SCORE_PATH)

func _local_high_score() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(HIGH_SCORE_PATH) == OK:
		return int(cfg.get_value("scores", "high_score", 0))
	return 0
