extends Node2D

## Today's three missions. Rows are built from Missions.active() rather than
## authored in the scene, so adding a template never means touching this screen.

const ROW_TOP := 0.26
const ROW_STEP := 0.13
const BAR_WIDTH := 560.0
const BAR_HEIGHT := 8.0
const BAR_DROP := 30.0
const DONE_COLOR := Color(0.6, 2.2, 1.2, 1)

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var coins_label: Label = $UI/CoinsRow/Value
@onready var coins_icon: TextureRect = $UI/CoinsRow/Icon
@onready var rows_root: Control = $UI/Rows

func _ready() -> void:
	IconPop.attach([$UI/BackButton])
	_build_rows()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength
	UiOpacity.apply($UI)
	# modulate, not self_modulate: UiOpacity owns self_modulate on every Control
	# under the UI layer, so the star's tint has to live on the other channel.
	coins_icon.modulate = Settings.background_particle_color
	queue_redraw()

func _build_rows() -> void:
	coins_label.text = "%d" % Stats.coins
	for child in rows_root.get_children():
		child.queue_free()
	var view := get_viewport_rect().size
	var rows := Missions.active()
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var label := Label.new()
		label.text = row["text"]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color",
			DONE_COLOR if row["done"] else Color(1.5, 1.5, 1.5, 1))
		label.position = Vector2((view.x - BAR_WIDTH) / 2.0, view.y * (ROW_TOP + ROW_STEP * i))
		label.size = Vector2(BAR_WIDTH, 26.0)
		rows_root.add_child(label)

		var count := Label.new()
		count.text = "DONE  +%d" % Missions.REWARD if row["done"] \
			else "%d / %d" % [row["progress"], row["target"]]
		count.add_theme_font_size_override("font_size", 15)
		count.add_theme_color_override("font_color",
			DONE_COLOR if row["done"] else Color(1.1, 1.1, 1.1, 1))
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.position = label.position
		count.size = Vector2(BAR_WIDTH, 26.0)
		rows_root.add_child(count)

## Progress bars are drawn rather than built as nodes: they are two rectangles
## each and their geometry is already known from the row layout above.
func _draw() -> void:
	var view := get_viewport_rect().size
	var left := (view.x - BAR_WIDTH) / 2.0
	var rows := Missions.active()
	var accent := Settings.background_particle_color
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var y := view.y * (ROW_TOP + ROW_STEP * i) + BAR_DROP
		var track := Color(accent.r, accent.g, accent.b, 0.18)
		draw_rect(Rect2(left, y, BAR_WIDTH, BAR_HEIGHT), track)
		var filled := 1.0 if row["done"] else float(row["progress"]) / maxf(float(row["target"]), 1.0)
		if filled > 0.0:
			draw_rect(Rect2(left, y, BAR_WIDTH * clampf(filled, 0.0, 1.0), BAR_HEIGHT),
				DONE_COLOR if row["done"] else accent)

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
