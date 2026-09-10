extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var summary_label: Label = $UI/SummaryLabel
@onready var runs_label: Label = $UI/RunsLabel

func _ready() -> void:
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	summary_label.text = "GAMES PLAYED %d     AVERAGE SCORE %d     BEST STREAK x%d%s" % [
		Stats.games_played,
		int(round(Stats.average_score())),
		Stats.best_streak_ever,
		_badges(),
	]
	runs_label.text = _format_runs()

## The two zone-ladder milestones are the only permanent things a player can
## finish, so they get their own line rather than hiding among the run list.
func _badges() -> String:
	var earned := PackedStringArray()
	if Stats.escaped:
		earned.append("ESCAPED SOLAR GRAVITY")
	if Stats.true_ending:
		earned.append("TRUE ENDING")
	return "\n" + "     ".join(earned) if not earned.is_empty() else ""

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _format_runs() -> String:
	if Stats.runs.is_empty():
		return "NO RUNS YET"
	var lines := PackedStringArray()
	for i in range(Stats.runs.size()):
		var run: Dictionary = Stats.runs[i]
		lines.append("#%-2d  %5d pts   STREAK x%-3d  %s" % [i + 1, run["score"], run["max_streak"], run["date"]])
	return "\n".join(lines)

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
