extends Node2D

const SAVE_PATH := "user://highscore.cfg"

@onready var best_label: Label = $UI/BestLabel

func _ready() -> void:
	var high_score := 0
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("scores", "high_score", 0)
	best_label.text = "BEST %d" % high_score

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
