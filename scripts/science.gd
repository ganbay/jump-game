extends Node2D

## The science behind the name: what a jetlet actually is, and what the solar
## wind actually is.
##
## Deliberately a plain scrolling article rather than the guide's paged layout.
## The guide pages are short lists of attributes, where a page turn is a natural
## unit; this is continuous prose, and breaking prose across pages makes the
## reader hold the last sentence in their head while they reach for a button.
##
## All of the copy lives in the scene rather than here. Nothing about it is
## computed, so a script that rebuilt these labels at runtime would only be a
## second place to look for the text.

@onready var world_environment: WorldEnvironment = $WorldEnvironment

func _ready() -> void:
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	IconPop.attach([$UI/BackButton])

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
