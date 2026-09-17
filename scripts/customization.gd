extends Node2D

## Character picker plus everything that only changes how the game looks.
## Nothing on this screen affects play -- every skin shares one hitbox and one
## squash spring (see player.gd) -- so the settings screen keeps the options
## that do, and this one owns shapes and colours.

## How far a drag has to travel to advance one character. Low enough that a
## flick works, high enough that a tap that wanders does not change anything.
const SWIPE_STEP := 70.0
## Where the incoming character starts from, on the side it was dragged from.
const SLIDE_OFFSET := 46.0
const SLIDE_TIME := 0.22

## The dot row has no node to anchor, so it is placed as a fraction of the
## viewport height -- the same way the labels around it are -- rather than at a
## fixed y that only lines up with them at exactly 720x1280.
const DOT_Y_FRACTION := 0.386
const DOT_SPACING := 26.0
const DOT_RADIUS := 4.5

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var preview: PlasmaBlob = $UI/PreviewAnchor/CharacterPreview
@onready var lock_icon: TextureRect = $UI/PreviewAnchor/LockIcon
@onready var platform_swatch: RoundedRect = $UI/PlatformSwatchAnchor/PlatformSwatch
@onready var name_label: Label = $UI/CharacterName
@onready var player_slider: ColorSpectrumSlider = $UI/PlayerSlider
@onready var platform_slider: ColorSpectrumSlider = $UI/PlatformSlider
@onready var particle_slider: ColorSpectrumSlider = $UI/ParticleSlider
@onready var trail_check: CheckButton = $UI/TrailCheck
@onready var particles_check: CheckButton = $UI/ParticlesCheck
@onready var coins_label: Label = $UI/CoinsRow/Value
@onready var coins_icon: TextureRect = $UI/CoinsRow/Icon
@onready var hint_label: Label = $UI/SwipeHint
@onready var unlock_button: Button = $UI/UnlockButton
@onready var confirm_panel: Control = $UI/ConfirmPanel
@onready var confirm_title: Label = $UI/ConfirmPanel/TitleLabel
@onready var confirm_body: Label = $UI/ConfirmPanel/BodyLabel
@onready var confirm_watch_button: Button = $UI/ConfirmPanel/WatchButton

## The unlock button does two different jobs depending on what gates the skin
## being browsed, and it is an unlabelled glyph -- so the icon is what says
## which one it is about to do.
const UNLOCK_RATE_ICON := preload("res://assets/icons/unlock.svg")
const UNLOCK_AD_ICON := preload("res://assets/icons/video.svg")

const HINT_SWIPE := "SWIPE THE CHARACTER TO CHANGE"
## How dark the preview goes while its character is still locked -- a colour
## multiplier, not alpha, so the shape stays fully opaque (reads as dimmed,
## not faded/transparent) and the white lock icon sitting on top of it stands
## out cleanly instead of blending into a see-through character.
const LOCKED_PREVIEW_DARKEN := 0.2

## Where the unlock button sends the player for a RATE-gated skin. There is no
## cross-platform way to confirm a review was actually left from inside the
## app, so reaching the listing at all is what counts.
const RATE_URL := "https://play.google.com/store/apps/details?id=com.eternalsky.jetlet"

## Hint text for a locked skin, per Unlocks.Requirement. PURCHASE has no
## working buy flow yet -- see Unlocks.gd -- so it reads as unavailable rather
## than offering a button that would do nothing.
const REQUIREMENT_HINTS := {
	Unlocks.Requirement.RATE: "LOCKED  -  RATE THE GAME TO UNLOCK",
	Unlocks.Requirement.ESCAPE: "LOCKED  -  ESCAPE SOLAR GRAVITY TO UNLOCK",
	Unlocks.Requirement.TRUE_ENDING: "LOCKED  -  REACH THE TRUE ENDING TO UNLOCK",
	Unlocks.Requirement.PURCHASE: "LOCKED  -  COMING SOON",
}

## The ADS hint is built rather than looked up: it carries the running count,
## so the player sees the gate move after each ad instead of watching three
## against an unchanging line.
const ADS_HINT := "LOCKED  -  WATCH %d MORE AD%s TO UNLOCK  (%d/%d)"
## Closing a rewarded ad early earns nothing -- said plainly, so a counter that
## did not move does not read as the game losing progress.
const ADS_HINT_SKIPPED := "AD CLOSED EARLY  -  NOTHING COUNTED"

## The confirmation shown before the first ad of the set ever starts. Asking
## costs a tap, and playing a full-screen ad on someone who only meant to look
## at the character costs a great deal more -- so the price is stated up front
## and the player opts in. The count is the remaining one, not always three, so
## coming back at 2/3 is asked honestly.
const CONFIRM_TITLE := "UNLOCK %s"
const CONFIRM_BODY := "Watch %d rewarded ad%s to unlock this character.\n\nYou can stop between ads -- every one you finish is saved."
## Same prompt once the set is part-finished, so it never re-asks for three
## ads that are no longer owed.
const CONFIRM_BODY_RESUMED := "%d of %d ads done.\n\nWatch %d more to unlock this character."
## Nothing is loaded yet. The prompt stays open rather than closing on a press
## that did nothing -- the player still wants the skin, the ad is just late.
const CONFIRM_BODY_NOT_READY := "No ad is ready just yet.\n\nGive it a moment and try again."

## How long a "just unlocked" announcement holds before the hint label reverts
## to its normal per-skin text.
const UNLOCK_ANNOUNCE_TIME := 2.2

## Which character the picker is sitting on, which is no longer the same thing
## as which one is worn: a locked skin can be browsed and its requirement
## checked, and only becomes Settings.player_skin once it is unlocked.
var _browse: int = 0

## Drag distance banked since the last character change.
var _drag: float = 0.0
var _preview_home: Vector2
var _slide_tween: Tween

func _ready() -> void:
	IconPop.attach([$UI/PrevButton, $UI/NextButton, $UI/BackButton, unlock_button,
		confirm_watch_button])
	confirm_panel.hide()
	_browse = Settings.player_skin
	_preview_home = preview.position
	player_slider.value = Settings.player_color_slider
	platform_slider.value = Settings.platform_color_slider
	particle_slider.value = Settings.particle_color_slider
	# set_pressed_no_signal, not button_pressed: assigning the property emits
	# `toggled`, and the .tscn wires that up before _ready runs -- so seeding
	# the boxes from Settings would fire both handlers, clicking twice and
	# writing the config back on every visit to this screen.
	trail_check.set_pressed_no_signal(Settings.trail_enabled)
	particles_check.set_pressed_no_signal(Settings.background_particles)
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	# Warm one up on arrival, the same way a run does at its first frame: the
	# ADS gate's button is only useful with an ad already in hand, and fetching
	# one takes seconds the player would otherwise spend looking at a dead
	# button.
	Ads.load_rewarded()
	_announce_new_unlocks()

## Surfaces anything unlocked away from this screen -- an ESCAPE or
## TRUE_ENDING milestone hit mid-run -- rather than leaving the player to
## notice only by browsing past it later. Jumps the picker onto the first
## thing unlocked, exactly like a manual swipe onto it would, so the character
## itself lights up rather than just a hint line being easy to miss. Overwrites
## the hint label briefly for the announcement text; _refresh_lock_state()
## (queued below) restores its normal per-skin text once that clears.
func _announce_new_unlocks() -> void:
	var newly := Unlocks.claim_newly_unlocked()
	if newly.is_empty():
		return
	var names := PackedStringArray()
	for id in newly:
		names.append(id.trim_prefix(Unlocks.SKIN_PREFIX))
	var target := Player.SKIN_NAMES.find(names[0])
	if target != -1 and target != _browse:
		var dir := 1 if target > _browse else -1
		_browse = target
		_equip_if_owned()
		_apply_visual_settings()
		_slide_in(dir)
	hint_label.text = "%s UNLOCKED!" % " & ".join(names)
	queue_redraw()
	var tw := create_tween()
	tw.tween_interval(UNLOCK_ANNOUNCE_TIME)
	tw.tween_callback(_refresh_lock_state)

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	# Currency display disabled -- CoinsRow is hidden (see customization.tscn).
	# Uncomment alongside it to bring the star count back.
	# modulate, not self_modulate: UiOpacity owns self_modulate on every Control
	# under the UI layer, so the star's tint has to live on the other channel.
	# coins_icon.modulate = Settings.background_particle_color
	# coins_label.add_theme_color_override("font_color", Settings.background_particle_color)
	preview.shape = Player.SKIN_SHAPES.get(_browse, PlasmaBlob.Shape.CIRCLE)
	preview.color = Settings.player_color
	platform_swatch.color = Settings.platform_color
	name_label.text = Player.SKIN_NAMES[_browse]
	_refresh_lock_state()
	queue_redraw()

## Everything that depends on whether the browsed character is owned. Split out
## because the unlock button changes it without any visual setting having moved.
func _refresh_lock_state() -> void:
	var id := Unlocks.skin_id(_browse)
	var owned := Unlocks.is_unlocked(id)
	# coins_label.text = "%d" % Stats.coins  # currency display disabled
	preview.modulate = Color.WHITE if owned else Color(LOCKED_PREVIEW_DARKEN, LOCKED_PREVIEW_DARKEN, LOCKED_PREVIEW_DARKEN)
	lock_icon.visible = not owned
	if owned:
		unlock_button.visible = false
		hint_label.text = HINT_SWIPE
		return
	# Only RATE and ADS have a button to press -- ESCAPE/TRUE_ENDING unlock
	# themselves the moment the milestone is hit in a run, and PURCHASE has
	# nothing to wire the button to yet.
	var requirement := Unlocks.requirement_of(id)
	unlock_button.visible = requirement == Unlocks.Requirement.RATE \
		or requirement == Unlocks.Requirement.ADS
	unlock_button.icon = UNLOCK_AD_ICON if requirement == Unlocks.Requirement.ADS else UNLOCK_RATE_ICON
	if requirement == Unlocks.Requirement.ADS:
		var left := Unlocks.ads_remaining()
		hint_label.text = ADS_HINT % [left, "" if left == 1 else "S", Unlocks.ads_watched, Unlocks.ADS_REQUIRED]
		return
	hint_label.text = REQUIREMENT_HINTS.get(requirement, "LOCKED")

## Which character is selected, as a row of dots under the name. Drawn here
## rather than as nine nodes in the scene -- there is nothing to lay out, and
## the count follows Player.SkinType on its own.
func _draw() -> void:
	var count := Player.SkinType.size()
	var view := get_viewport_rect().size
	var start := view.x / 2.0 - (count - 1) * DOT_SPACING / 2.0
	var row_y := view.y * DOT_Y_FRACTION
	var accent := Settings.player_color
	var dim := Color(accent.r, accent.g, accent.b, 0.25)
	var locked_dim := Color(accent.r, accent.g, accent.b, 0.1)
	for i in range(count):
		var at := Vector2(start + i * DOT_SPACING, row_y)
		if i == _browse:
			draw_circle(at, DOT_RADIUS, accent)
		elif Unlocks.is_unlocked(Unlocks.skin_id(i)):
			draw_circle(at, DOT_RADIUS * 0.55, dim)
		else:
			# Fainter again, so the roster shows at a glance how much of it is
			# still to buy without having to swipe the whole way through.
			draw_circle(at, DOT_RADIUS * 0.55, locked_dim)

## Drag anywhere over the character to flick through the roster. Both event
## families are handled: touch reaches this as a screen drag on a device, and
## as an emulated mouse motion when a mouse is driving it.
func _on_swipe_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_bank_drag(event.relative.x)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_bank_drag(event.relative.x)
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		if not event.pressed:
			_drag = 0.0

func _bank_drag(dx: float) -> void:
	_drag += dx
	# A long drag steps more than once rather than banking distance it will
	# never spend, so a fast flick crosses several characters.
	while _drag >= SWIPE_STEP:
		_drag -= SWIPE_STEP
		_step(-1)
	while _drag <= -SWIPE_STEP:
		_drag += SWIPE_STEP
		_step(1)

func _step(dir: int) -> void:
	var count := Player.SkinType.size()
	_browse = (_browse + dir + count) % count
	Audio.play_ui_click()
	_equip_if_owned()
	_apply_visual_settings()
	_slide_in(dir)

## Browsing onto a character you own wears it straight away, exactly as the
## picker did before locks existed. Browsing onto one you do not leaves the worn
## skin alone -- nothing is taken off just because you looked at the shop.
func _equip_if_owned() -> void:
	if Unlocks.is_unlocked(Unlocks.skin_id(_browse)):
		Settings.set_player_skin(_browse as Player.SkinType)

## Wired to a RATE- or ADS-gated skin (see _refresh_lock_state), so it splits
## on which one is being browsed rather than on which button was pressed --
## there is only the one button.
func _on_unlock_pressed() -> void:
	Audio.play_ui_click()
	if Unlocks.requirement_of(Unlocks.skin_id(_browse)) == Unlocks.Requirement.ADS:
		_open_confirm()
		return
	OS.shell_open(RATE_URL)
	Stats.mark_rated()
	# Unlocked is worn: nobody rates the game just to leave the skin unworn.
	_equip_if_owned()
	_apply_visual_settings()

## The unlock button no longer starts an ad on its own -- it asks first. What
## it is asking for is several full-screen ads, which is not something to spend
## a stray tap on.
func _open_confirm() -> void:
	var left := Unlocks.ads_remaining()
	confirm_title.text = CONFIRM_TITLE % Player.SKIN_NAMES[_browse]
	if Unlocks.ads_watched > 0:
		confirm_body.text = CONFIRM_BODY_RESUMED % [Unlocks.ads_watched, Unlocks.ADS_REQUIRED, left]
	else:
		confirm_body.text = CONFIRM_BODY % [left, "" if left == 1 else "s"]
	confirm_watch_button.disabled = false
	confirm_panel.show()

func _close_confirm() -> void:
	confirm_panel.hide()
	_refresh_lock_state()

## Answering yes. Same rewarded ad the revive offer shows, requested the same
## way -- the only difference is what the reward buys. Nothing is credited
## until the ad reports it was actually watched through.
func _on_confirm_watch_pressed() -> void:
	Audio.play_ui_click()
	if not Ads.is_rewarded_ready():
		# Left open on purpose: the answer was yes, so closing it would make
		# them say yes again once the ad lands.
		confirm_body.text = CONFIRM_BODY_NOT_READY
		Ads.load_rewarded()
		return
	# The ad takes a moment to come up with the button still on screen under
	# it, so without this a second tap queues a second request behind the first.
	confirm_watch_button.disabled = true
	Ads.show_rewarded(_on_unlock_ad_rewarded, _on_unlock_ad_dismissed)

func _on_confirm_cancel_pressed() -> void:
	Audio.play_ui_click()
	_close_confirm()

## Tapping the dark area outside the prompt declines it too -- the same way the
## pause panel's dim is wired -- so there is always a way out that is not the
## Watch button.
func _on_confirm_dim_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_confirm_cancel_pressed()
	elif event is InputEventMouseButton and event.pressed:
		_on_confirm_cancel_pressed()

func _on_unlock_ad_rewarded() -> void:
	confirm_watch_button.disabled = false
	Unlocks.record_ad_watched()
	# Fetch the next one now rather than at the next press -- the gate usually
	# wants more than one, and the wait between them is the whole cost.
	Ads.load_rewarded()
	if not Unlocks.is_unlocked(Unlocks.skin_id(_browse)):
		# Still owed some. The prompt stays up with the count moved on, so the
		# next one is one tap away -- but it is still a tap, never automatic.
		_open_confirm()
		_refresh_lock_state()
		return
	confirm_panel.hide()
	# The last ad of the set. Wear it and hand the announcement to the same
	# path a mid-run milestone unlock takes, so it reads identically: the
	# character lights up and the hint line calls it out before reverting.
	_equip_if_owned()
	_apply_visual_settings()
	_announce_new_unlocks()

## Closed early, failed to show, or was never there -- Ads only routes here
## when no reward was earned, so the counter is deliberately left alone.
func _on_unlock_ad_dismissed() -> void:
	confirm_watch_button.disabled = false
	confirm_panel.hide()
	hint_label.text = ADS_HINT_SKIPPED
	Ads.load_rewarded()

## The new character enters from whichever side it was pulled in from, so the
## roster reads as a strip being scrolled rather than a shape being swapped.
func _slide_in(dir: int) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	preview.position = _preview_home + Vector2(SLIDE_OFFSET * dir, 0.0)
	_slide_tween = create_tween()
	_slide_tween.tween_property(preview, "position", _preview_home, SLIDE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_prev_pressed() -> void:
	_step(-1)

func _on_next_pressed() -> void:
	_step(1)

func _on_player_slider_color_changed(color: Color) -> void:
	Settings.set_player_color(color, player_slider.value)

func _on_platform_slider_color_changed(color: Color) -> void:
	Settings.set_platform_color(color, platform_slider.value)

func _on_particle_slider_color_changed(color: Color) -> void:
	Settings.set_background_particle_color(color, particle_slider.value)

func _on_trail_check_toggled(pressed: bool) -> void:
	Audio.play_ui_click()
	Settings.set_trail_enabled(pressed)

func _on_particles_check_toggled(pressed: bool) -> void:
	Audio.play_ui_click()
	Settings.set_background_particles(pressed)

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
