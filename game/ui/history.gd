extends Control
## Run-Historie: abgeschlossene Runs mit Ergebnis, Trainer und Endteam.

const ICON_SIZE := 32
const COLOR_WIN := Color(0.56, 1, 0.42)
const COLOR_TEXT := Color(0.878431, 0.858824, 0.929412)
const COLOR_MUTED := Color(0.678431, 0.647059, 0.768627)

@onready var _entries: VBoxContainer = %Entries


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.TITLE_SCENE))
	var all := RunHistory.entries()
	if all.is_empty():
		%SummaryLabel.text = "Noch keine Runs beendet."
	else:
		var wins: Array = all.map(func(e: Dictionary) -> int: return int(e["wins"]))
		var victories := all.filter(func(e: Dictionary) -> bool: return e["victory"]).size()
		var total := 0
		for w: int in wins:
			total += w
		%SummaryLabel.text = "%d Runs, %d gewonnen, beste %d Siege, Schnitt %.1f" % [
			all.size(), victories, wins.max(), float(total) / all.size()]
	for entry: Dictionary in all:
		_entries.add_child(_entry_panel(entry))
	Audio.play_music("menu")


func _entry_panel(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var trainer_def := Session.item_def(entry["trainer"])
	if not trainer_def.is_empty():
		head.add_child(_icon(Session.item_texture(entry["trainer"])))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	var title := Label.new()
	title.text = ("Run gewonnen! %d Siege" if entry["victory"] else "%d Siege") % int(entry["wins"])
	title.add_theme_color_override("font_color", COLOR_WIN if entry["victory"] else COLOR_TEXT)
	text.add_child(title)
	var meta := Label.new()
	meta.text = "%s, Runde %d, %s" % [_date(entry["date"]), int(entry["round"]), trainer_def.get("name", "")]
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(meta)
	var team := HFlowContainer.new()
	box.add_child(team)
	for tag: String in entry.get("team", []):
		var id := tag.split(":")[0]
		if Session.db.has(id):
			team.add_child(_icon(load(Session.SPRITE_ROOT + Session.db.get_def(id)["sprite"])))
	return panel


func _icon(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	return rect


## "2026-09-28 20:10:05" -> "28.09. 20:10"
func _date(value: String) -> String:
	if value.length() < 16:
		return value
	return "%s.%s. %s" % [value.substr(8, 2), value.substr(5, 2), value.substr(11, 5)]
