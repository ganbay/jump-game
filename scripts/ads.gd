extends Node

## Rewarded-ad requests, backed by poingstudios/godot-admob-plugin v5.0.0.
##
## game.gd only ever talks to show_rewarded()/is_rewarded_ready()/load_rewarded()
## and acts through the callbacks it hands over, so everything AdMob-shaped --
## consent, initialization, the load/show/destroy lifecycle -- stays in here.
##
## Note on pause: the revive offer runs with get_tree().paused = true, so this
## autoload forces PROCESS_MODE_ALWAYS. Signals arrive while paused either way,
## but anything awaited here would not resume until after the reward had
## already been decided.

## Google's public test units. A dev build must never request the real one --
## that is how AdMob accounts get flagged for invalid traffic.
const TEST_REWARDED_UNIT_ID := "ca-app-pub-3940256099942544/5224354917"
## The live unit, used by release builds only -- _unit_id() forces the test one
## whenever OS.is_debug_build(), so development cannot serve real impressions.
const REWARDED_UNIT_ID := "ca-app-pub-9653736186258588/7579740520"

## Export feature tag that forces the test unit in a *release* build.
##
## Play only accepts release builds, and the live unit serves nothing until
## AdMob has reviewed the app -- which cannot happen until the app is on the
## store. So on a test track the revive offer would never appear and the
## ad-gated skin would be unreachable, leaving a tester unable to tell a broken
## feature from an unapproved one.
##
## REMOVE THIS TAG FROM THE EXPORT PRESET BEFORE THE PRODUCTION BUILD. Leaving
## it in ships a game that only ever serves test ads and earns nothing --
## _ready() pushes a warning on every launch that it is active, which is the
## only signal there is.
const TEST_ADS_FEATURE := "testads"

## UMP can sit unanswered on a bad connection. Ads are optional to this game, so
## the run starts regardless once this elapses rather than waiting forever on a
## consent round trip that may never come back.
const CONSENT_TIMEOUT := 8.0
## Same reasoning for a load that never resolves -- see _watch_load().
const LOAD_TIMEOUT := 30.0

var _initialized: bool = false
var _consent_done: bool = false
## Re-made for every request, never reused -- see load_rewarded().
var _loader: RewardedAdLoader = null
var _rewarded_ad: RewardedAd = null
var _loading: bool = false
## Latched by the reward listener, read on dismissal. The two signals are
## separate and the reward one always lands first: a skipped ad still fires
## dismissal, so granting from dismissal alone would hand out free revives.
var _reward_earned: bool = false
var _on_reward: Callable = Callable()
var _on_dismissed: Callable = Callable()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build() and OS.has_feature(TEST_ADS_FEATURE):
		push_warning("[ads] test ad unit forced in a release build by the '%s' export feature -- remove it from the export preset before publishing." % TEST_ADS_FEATURE)
	# UMP has no editor mock in this plugin, so its callbacks would never fire
	# off-device and initialization would stall behind them forever. The form is
	# only meaningful on a real handset anyway.
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		_request_consent()
	else:
		_initialize()

func _request_consent() -> void:
	get_tree().create_timer(CONSENT_TIMEOUT).timeout.connect(_on_consent_timeout)
	UserMessagingPlatform.consent_information.update(
		ConsentRequestParameters.new(),
		_on_consent_updated,
		func(error: FormError) -> void:
			push_warning("[ads] consent update failed: %s" % error.message)
			_finish_consent())

func _on_consent_updated() -> void:
	if not UserMessagingPlatform.consent_information.get_is_consent_form_available():
		_finish_consent()
		return
	UserMessagingPlatform.load_consent_form(
		func(form: ConsentForm) -> void:
			form.show(func(error: FormError) -> void:
				if error != null:
					push_warning("[ads] consent form dismissed with error: %s" % error.message)
				_finish_consent()),
		func(error: FormError) -> void:
			push_warning("[ads] consent form failed to load: %s" % error.message)
			_finish_consent())

func _on_consent_timeout() -> void:
	if not _consent_done:
		push_warning("[ads] consent timed out -- initializing without it")
		_finish_consent()

## Guarded because the timeout and a real callback can both arrive, and
## initializing the SDK twice re-registers its listeners.
func _finish_consent() -> void:
	if _consent_done:
		return
	_consent_done = true
	_initialize()

func _initialize() -> void:
	MobileAds.set_request_configuration(RequestConfiguration.new())
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_initialized = true
		load_rewarded()
	MobileAds.initialize(listener)

func _unit_id() -> String:
	if OS.is_debug_build() or OS.has_feature(TEST_ADS_FEATURE) or REWARDED_UNIT_ID.is_empty():
		return TEST_REWARDED_UNIT_ID
	return REWARDED_UNIT_ID

## Starts fetching the next rewarded ad. Called at run start and again after
## each ad is consumed -- a rewarded ad takes seconds to arrive, so requesting
## one at the moment of death would leave the player waiting on the game-over
## panel for an offer that is not ready yet. Safe to call at any time: it
## no-ops while one is already in hand, already in flight, or the SDK is not up.
func load_rewarded() -> void:
	if _rewarded_ad != null or _loading or not _initialized:
		return
	_loading = true
	# A loader is single-use. It takes its uid from one create() in its _init,
	# hands that same uid to the RewardedAd it produces, and unreferences itself
	# once the request resolves -- so destroying the ad also tears down the uid
	# the loader is still pointing at. Loading again through the same instance
	# then matches nothing and returns without ever calling back, which is what
	# left the revive offer permanently unavailable after the first ad.
	_loader = RewardedAdLoader.new()
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_loading = false
		_loader = null
		_rewarded_ad = ad
		_bind_content_callbacks(ad)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_loading = false
		_loader = null
		_rewarded_ad = null
		push_warning("[ads] rewarded failed to load: %s" % error.message)
	_loader.load(_unit_id(), AdRequest.new(), callback)
	_watch_load()

## A request that never calls back either way would otherwise leave _loading
## stuck true, which silently blocks every later attempt for the rest of the
## session. Releasing the flag lets the next death retry instead.
func _watch_load() -> void:
	var pending := _loader
	await get_tree().create_timer(LOAD_TIMEOUT).timeout
	if _loading and _loader == pending:
		_loading = false
		_loader = null
		push_warning("[ads] rewarded load timed out -- will retry on next request")

## Whether an ad is loaded and can be shown right now. Gates the Watch Ad
## button: no ad in hand means the run just ends, rather than offering a button
## that stalls when pressed.
func is_rewarded_ready() -> bool:
	return _rewarded_ad != null

## Shows the loaded ad. Exactly one of the two callbacks fires, always on the
## ad's dismissal: `on_reward` if the reward listener latched first, otherwise
## `on_dismissed` -- closed early, failed to show, or nothing loaded.
func show_rewarded(on_reward: Callable, on_dismissed: Callable) -> void:
	if _rewarded_ad == null:
		on_dismissed.call()
		return
	_on_reward = on_reward
	_on_dismissed = on_dismissed
	_reward_earned = false
	_keep_editor_mock_running()
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_reward_earned = true
	_rewarded_ad.show(listener)

## Both endings route here. destroy() is mandatory -- the ad holds native memory
## that is not freed by dropping the reference.
func _bind_content_callbacks(ad: RewardedAd) -> void:
	var callbacks := FullScreenContentCallback.new()
	callbacks.on_ad_dismissed_full_screen_content = func() -> void:
		_settle(ad)
	callbacks.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		push_warning("[ads] rewarded failed to show: %s" % error.message)
		_settle(ad)
	ad.full_screen_content_callback = callbacks

func _settle(ad: RewardedAd) -> void:
	ad.destroy()
	if _rewarded_ad == ad:
		_rewarded_ad = null
	var reward := _on_reward
	var dismissed := _on_dismissed
	_on_reward = Callable()
	_on_dismissed = Callable()
	var earned := _reward_earned
	_reward_earned = false
	# Cleared before the callback because game.gd calls straight back into
	# load_rewarded() from it.
	if earned and reward.is_valid():
		reward.call()
	elif dismissed.is_valid():
		dismissed.call()

## The plugin's editor mock is a plain Node under the tree root at default
## process mode, and it is shown while the revive offer has the tree paused --
## so its five-second countdown to the close button never ticks and the fake ad
## cannot be dismissed at all. Editor-only: on device the ad is a native overlay
## that Godot's pause state has no say over.
func _keep_editor_mock_running() -> void:
	if not OS.has_feature("editor") or Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		return
	var factory = load("res://addons/admob/internal/mock/mock_admob_factory.gd")
	if factory == null:
		return
	var mock = factory.get_mock_plugin("PoingGodotAdMobRewardedAd")
	if mock is Node:
		(mock as Node).process_mode = Node.PROCESS_MODE_ALWAYS
