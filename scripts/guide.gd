extends Node2D

## Two pages: the attribute list, then how zones combine those attributes.
## Both are built into the scene and simply toggled -- the whole guide is a
## screenful of static labels, so there is nothing to rebuild on a page turn.

const PAGE_TITLES := ["HOW TO PLAY", "ZONES"]

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var title_label: Label = $UI/TitleLabel
@onready var page_label: Label = $UI/PageLabel
@onready var prev_button: Button = $UI/PrevButton
@onready var next_button: Button = $UI/NextButton
@onready var page1: Control = $UI/Page1
@onready var page2: Control = $UI/Page2

var _pages: Array[Control] = []
var _page: int = 0

func _ready() -> void:
	_pages = [page1, page2]
	Stats.mark_tutorial_seen()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	_show_page(0)
	IconPop.attach([prev_button, next_button, $UI/PlayButton, $UI/BackButton])

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	UiOpacity.apply($UI)

func _show_page(page: int) -> void:
	_page = clampi(page, 0, _pages.size() - 1)
	for i in range(_pages.size()):
		_pages[i].visible = i == _page
	title_label.text = PAGE_TITLES[_page]
	page_label.text = "%d / %d" % [_page + 1, _pages.size()]
	# Hidden rather than disabled at the ends: a greyed-out button on a screen
	# this text-heavy reads as something the player failed to unlock.
	prev_button.visible = _page > 0
	next_button.visible = _page < _pages.size() - 1

func _on_next_pressed() -> void:
	Audio.play_ui_click()
	_show_page(_page + 1)

func _on_prev_pressed() -> void:
	Audio.play_ui_click()
	_show_page(_page - 1)

func _on_play_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
