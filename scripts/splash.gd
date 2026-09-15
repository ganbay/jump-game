extends Node2D

## The publisher card, shown once at launch before the menu.
##
## The sky drains from night blue to the same black every other screen sits on,
## and the wordmark is gone before it lands -- so by the time Transition takes
## over there is nothing left to cross-fade. The handoff to the menu is not a
## quick cut, it is an invisible one: black to black, with the menu fading up
## out of it. Cutting from a lit screen straight into the menu is what would
## read as a seam, so the card puts itself away first.
##
## Godot's own boot splash is switched off in project.godot, with its bg_color
## set to NIGHT below, so the window opens on this exact colour and this scene
## simply continues it -- no white flash, and no logo before the logo.

## How long the card holds. Everything below is scheduled inside it, so this is
## the only number to change to make the splash longer or shorter.
const DURATION := 2.0

## Night sky a moment before it goes fully dark. Kept in sync by hand with
## application/boot_splash/bg_color in project.godot, which cannot reference it.
const NIGHT := Color(0.043, 0.063, 0.133)

const FADE_IN := 0.45
## The tail of the hold, over which every line of the card sinks from its lit
## colour into the sky behind it. Starts at DURATION - TEXT_SINK, so the card
## simply sits there lit for the first half and spends the whole second half
## going out -- a slow dissolve rather than a fade tacked on at the end.
const TEXT_SINK := 1.0

@onready var background: ColorRect = $BackgroundLayer/Background
@onready var stars: Node2D = $BackgroundLayer/Stars
@onready var content: Control = $UI/Content
@onready var godot_logo: TextureRect = $UI/Content/MadeWith/GodotLogo
## Every line that sinks. Listed rather than walked, so a label added to the
## card later is an explicit decision about whether it takes part.
@onready var _sinking_labels: Array[Label] = [
	$UI/Content/BrandLabel,
	$UI/Content/BrandSubLabel,
	$UI/Content/MadeWith/MadeWithLabel,
]

## Each label's authored colour, read off the theme override rather than
## hardcoded -- the card's three lines are lit to different brightnesses (the
## wordmark is overbright so the glow catches it) and each has to sink from its
## own value, not from a shared white.
var _lit_colors: Array[Color] = []

func _ready() -> void:
	background.color = NIGHT
	content.modulate.a = 0.0
	for label in _sinking_labels:
		_lit_colors.append(label.get_theme_color("font_color"))

	var tw := create_tween()
	tw.set_parallel(true)
	# Runs the whole hold rather than a slice of it: the sky going out is the
	# only thing moving for most of the card, so it has to be the slow one.
	# Eased in, because a linear drain reaches near-black early and then appears
	# to stop.
	tw.tween_property(background, "color", Color.BLACK, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# The stars go out with the sky they belong to, on the same curve. Leaving
	# them lit would contradict the whole point of the drain -- the card has to
	# land on the same empty black the menu sits on.
	tw.tween_property(stars, "modulate:a", 0.0, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(content, "modulate:a", 1.0, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Both land exactly on DURATION, so the card is dark and empty at the moment
	# the scene swap fires.
	tw.tween_method(_sink_text, 0.0, 1.0, TEXT_SINK) \
		.set_delay(DURATION - TEXT_SINK) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# The logo is an image, not a line of text -- there is no font colour to
	# sink -- so it goes out on alpha instead, over the same window and the same
	# curve so the card clears as one piece.
	tw.tween_property(godot_logo, "modulate:a", 0.0, TEXT_SINK) \
		.set_delay(DURATION - TEXT_SINK) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(_to_menu)

## Driven per frame rather than tweened as a plain colour, because the target
## is still moving: the sky is draining to black underneath this. A colour
## tween would aim at whatever the sky was when the tween was built and leave
## the text sitting a shade above the background it was supposed to vanish
## into. Reading background.color live means the two always meet.
func _sink_text(t: float) -> void:
	for i in range(_sinking_labels.size()):
		_sinking_labels[i].add_theme_color_override(
			"font_color", _lit_colors[i].lerp(background.color, t))

func _to_menu() -> void:
	Transition.change_scene("res://scenes/main_menu.tscn")
