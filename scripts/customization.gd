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
	IconPop.attach([$UI/PrevButton, $UI/NextButton, $UI/BackButton, unlock_button])
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
	world_environment.environment.glow_intensity = Settings.glow_strength
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
	# Only RATE has a button to press -- ESCAPE/TRUE_ENDING unlock themselves
	# the moment the milestone is hit in a run, and PURCHASE has nothing to
	# wire the button to yet.
	var requirement := Unlocks.requirement_of(id)
	unlock_button.visible = requirement == Unlocks.Requirement.RATE
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

## Only ever wired to a RATE-gated skin (see _refresh_lock_state) -- opens the
## store listing and trusts the tap, since nothing inside the app can confirm
## a review was actually left.
func _on_unlock_pressed() -> void:
	OS.shell_open(RATE_URL)
	Audio.play_ui_click()
	Stats.mark_rated()
	# Unlocked is worn: nobody rates the game just to leave the skin unworn.
	_equip_if_owned()
	_apply_visual_settings()

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
