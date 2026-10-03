extends Control
## Run-Historie: abgeschlossene Runs mit Ergebnis und Endteam. Im neuen Modus aus RunHistory.ws_entries(),
## im klassischen Modus mit Trainer aus RunHistory.entries().

const ICON_SIZE := 32
const COLOR_WIN := Color(0.56, 1, 0.42)
const COLOR_TEXT := Color(0.878431, 0.858824, 0.929412)
const COLOR_MUTED := Color(0.678431, 0.647059, 0.768627)

const WS_SPRITES := "res://data/ws_sprites.json"

@onready var _entries: VBoxContainer = %Entries

var _ws_sprites := {}


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.TITLE_SCENE))
	var classic := Session.classic_mode
	if not classic:
		var data: Variant = GameData.load_json(WS_SPRITES) if FileAccess.file_exists(WS_SPRITES) else null
		_ws_sprites = data if data is Dictionary else {}
	var all := RunHistory.entries() if classic else RunHistory.ws_entries()
	if all.is_empty():
		%SummaryLabel.text = Loc.t("HISTORY_EMPTY")
	else:
		var wins: Array = all.map(func(e: Dictionary) -> int: return int(e["wins"]))
		var victories := all.filter(func(e: Dictionary) -> bool: return e["victory"]).size()
		var total := 0
		for w: int in wins:
			total += w
		%SummaryLabel.text = Loc.t("HISTORY_SUMMARY", {
			"runs": all.size(), "won": victories, "best": wins.max(), "avg": "%.1f" % (float(total) / all.size())})
	for entry: Dictionary in all:
		_entries.add_child(_entry_panel(entry) if classic else _ws_panel(entry))
	Audio.play_music("menu")


func _entry_panel(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	if not Session.item_def(entry["trainer"]).is_empty():
		head.add_child(_icon(Session.item_texture(entry["trainer"])))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	var title := Label.new()
	title.text = Loc.t("HISTORY_WON" if entry["victory"] else "HISTORY_WINS", {"wins": int(entry["wins"])})
	title.add_theme_color_override("font_color", COLOR_WIN if entry["victory"] else COLOR_TEXT)
	text.add_child(title)
	var meta := Label.new()
	meta.text = Loc.t("HISTORY_META", {"date": _date(entry["date"]), "round": int(entry["round"]), "trainer": Loc.item(entry["trainer"])})
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


func _ws_panel(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = Loc.t("HISTORY_WON" if entry["victory"] else "HISTORY_WINS", {"wins": int(entry["wins"])})
	title.add_theme_color_override("font_color", COLOR_WIN if entry["victory"] else COLOR_TEXT)
	box.add_child(title)
	var meta := Label.new()
	meta.text = Loc.t("HISTORY_META_WS", {"date": _date(entry["date"]), "day": int(entry.get("day", 0)), "difficulty": entry.get("difficulty", "")})
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)
	var team := HFlowContainer.new()
	box.add_child(team)
	for id: String in entry.get("team", []):
		if _ws_sprites.has(id):
			team.add_child(_icon(load(Session.SPRITE_ROOT + _ws_sprites[id])))
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
