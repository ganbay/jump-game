extends Node

## Gameplay analytics via GA4's Measurement Protocol -- a plain HTTPS POST --
## rather than the Firebase Analytics SDK. That SDK needs a native Android
## plugin baked into the export; this needs nothing but the HTTPRequest node
## every Godot build already ships with, so it works on every platform this
## project targets with no extra install step.
##
## Fill these in from a GA4 property's Admin > Data Streams > (your stream)
## > Measurement Protocol API secrets before this does anything. Both blank
## is the shipped default -- log_event() silently no-ops, so it's safe to
## export before they're set.
const MEASUREMENT_ID := "G-XR2QW1SNMV"
const API_SECRET := "sLQF6qpNR8m4mLlU2ukSYQ"

const ENDPOINT := "https://www.google-analytics.com/mp/collect"
const SAVE_PATH := "user://analytics.cfg"
const REQUEST_TIMEOUT := 10.0
## Dropped from the front once full, rather than blocked on network -- a
## queue backed up behind an offline device should lose its oldest telemetry,
## not stall every event after it forever.
const MAX_QUEUE := 20

var _client_id: String = ""
## Regenerated per launch. GA4 uses this to stitch events into one session
## without needing a server-side session store.
var _session_id: String = ""
var _session_start_msec: int = 0
var _queue: Array[Dictionary] = []
var _request: HTTPRequest
var _sending: bool = false
## Nothing leaves the device, and no client id is made or read, until the
## launch-time consent check in ads.gd has settled and said analytics is
## allowed. Events logged while PENDING wait in the queue; DENIED drops them
## and everything after for the rest of the session.
enum Gate { PENDING, ALLOWED, DENIED }
var _gate: Gate = Gate.PENDING

func _ready() -> void:
	if MEASUREMENT_ID.is_empty() or API_SECRET.is_empty():
		return
	_session_id = str(Time.get_unix_time_from_system())
	_session_start_msec = Time.get_ticks_msec()
	_request = HTTPRequest.new()
	_request.timeout = REQUEST_TIMEOUT
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	log_event("session_start")
	# Deferred: Ads is a later autoload and is not in the tree yet.
	_bind_consent.call_deferred()

func _bind_consent() -> void:
	if Ads.is_consent_settled():
		_on_consent_settled()
	else:
		Ads.consent_settled.connect(_on_consent_settled, CONNECT_ONE_SHOT)

func _on_consent_settled() -> void:
	if Ads.analytics_allowed():
		_load_or_create_client_id()
		_gate = Gate.ALLOWED
		_pump()
	else:
		_gate = Gate.DENIED
		_queue.clear()
		# An id written by a build that did not ask first.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)

## Fire-and-forget: a dropped or failed hit is not retried. This is gameplay
## telemetry, not a purchase receipt -- losing an occasional event to a bad
## connection is fine, and retrying would only queue up staler and staler
## data behind a device that's actually offline.
func log_event(event_name: String, params: Dictionary = {}) -> void:
	if MEASUREMENT_ID.is_empty() or API_SECRET.is_empty() or _gate == Gate.DENIED:
		return
	var event_params := params.duplicate()
	# Required by GA4 for a hit to count toward session-based reports (active
	# users, engagement time) instead of being dropped as engagement-less.
	event_params["engagement_time_msec"] = maxi(Time.get_ticks_msec() - _session_start_msec, 1)
	event_params["session_id"] = _session_id
	_queue.append({"name": event_name, "params": event_params})
	if _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	_pump()

func _pump() -> void:
	if _gate != Gate.ALLOWED or _sending or _queue.is_empty():
		return
	_sending = true
	var event: Dictionary = _queue.pop_front()
	var body := JSON.stringify({
		"client_id": _client_id,
		"events": [{"name": event["name"], "params": event["params"]}],
	})
	var url := "%s?measurement_id=%s&api_secret=%s" % [ENDPOINT, MEASUREMENT_ID, API_SECRET]
	var err := _request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_sending = false

func _on_request_completed(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_sending = false
	_pump()

## One random id per install, persisted the same way Settings/Stats persist
## theirs -- GA4 needs a stable client_id to tell returning players apart
## from new ones.
func _load_or_create_client_id() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_client_id = cfg.get_value("analytics", "client_id", "")
	if _client_id.is_empty():
		_client_id = "%d.%d" % [randi(), Time.get_unix_time_from_system()]
		cfg.set_value("analytics", "client_id", _client_id)
		cfg.save(SAVE_PATH)
