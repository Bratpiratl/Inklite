extends Control
## Spielbare Test-Szene für den Balancing-Workshop im Look des Hauptspiels: Kopfleiste, Team und Bank als
## weiße Panels, Shop-Karten, Info-Karte, Kampf wie in der Arena. Die Regeln stecken in WsRun und WsCombat,
## hier wird nur angezeigt und weitergereicht.
## Nur im separaten Test-Build (workshop/build_play.sh), nie im Hauptspiel. Der Regelsatz liegt dort unter
## res://ws_data/. Texte über translations.csv (Schlüssel WS_...). Bilder: data/ws_sprites.json (id -> Pfad unter assets/sprites/), erzeugt mit
## scripts/make_ws_sprites.py, Platzhalter aus Tiny Creatures.

const DATA_DIR := WsRuleset.GAME_DATA_DIR
const SPRITE_MAP := "res://data/ws_sprites.json"
const SPRITE_ROOT := "res://assets/sprites/"
const FALLBACK_SPRITE := "creatures/ember_pup.png"
const HUD_SCENE := preload("res://ui/hud.tscn")
const INFO_CARD_SCENE := preload("res://ui/info_card.tscn")
const SHOP_CARD_SCENE := preload("res://ui/shop_card.tscn")
const CELL_SCENE := preload("res://ui/unit_cell.tscn")
const ARENA_THEME := preload("res://ui/theme_arena.tres")
const FLOOR_PLAYER := preload("res://assets/sprites/tiles/floor_player.png")
const FLOOR_ENEMY := preload("res://assets/sprites/tiles/floor_enemy.png")
const COIN := preload("res://assets/ui/bato/icon_coin.png")
const DANGER := preload("res://assets/ui/panel_danger.png")
const ARENA_BG := Color(0.105882, 0.0901961, 0.14902)
const TITLE_COLOR := Color(1, 0.776471, 0.164706)
const RARITY_COLORS := ["#6b6b78", "#4f8f2e", "#2f6fd0", "#8a42c6", "#d9861e"]
const TEAM_CELL := Vector2(76, 70)
const BENCH_CELL := Vector2(64, 60)
const LINE_CELL := Vector2(46, 52)
const GRID_CELL := Vector2(64, 64)
const LINE_SPRITE := 36.0
const SPEEDS := [1.0, 2.0, 4.0]
const T_PAUSE := 0.3
const T_LUNGE := 0.3
const T_DIE := 0.35
const T_POP := 0.25
const FLASH_MERGE := Color(2.0, 1.8, 0.7)
const COLOR_DAMAGE := Color(1, 0.36, 0.36)
const COLOR_SHIELD := Color(0.5, 0.8, 1)
const COLOR_BUFF := Color(0.56, 1, 0.42)
const COLOR_ABILITY := Color(1, 0.83, 0.38)
const COLOR_WIN := Color(0.56, 1, 0.42)
const COLOR_LOSS := Color(1, 0.46, 0.46)
const COLOR_ATK := "#ffd461"
const COLOR_HP := "#ff7676"
const COLOR_TERM := "#e0dbed"

var rs: WsRuleset
var run: WsRun
var mode := "bg"
## Gewählte Schwierigkeit (id aus run.difficulties im Regelsatz), bleibt für den nächsten Run stehen.
var difficulty := "mittel"

var _sprites := {}
var _textures := {}
var _hud: Hud
var _card: InfoCard
var _pages: MarginContainer
var _backdrop: ColorRect
var _arena_bg: ColorRect
var _page: Control
var _page_token := 0
var _selected := {}

# Shop
var _team_cells: Array[UnitCell] = []
var _bench_cells: Array[UnitCell] = []
var _shop_cards: Array[ShopCard] = []
var _gold_button: Button
var _odds_label: RichTextLabel
var _reroll: Button
var _lock: Button
var _fight: Button
var _shop_area: Control
var _sell_zone: DropZone
var _sell_label: Label

# Kampf
var _speed_index := 0
var _skip := false
var _fx: BattleFx
var _battle_cells := {}   # uid -> UnitCell
var _battle_units := {}   # uid -> {"id", "side", "kw"}
var _lines: Array = [[], []]
var _line_boxes: Array = []
var _grid_cells: Array = [[], []]
var _dead: Array[UnitCell] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = Backdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_arena_bg = ColorRect.new()
	_arena_bg.color = ARENA_BG
	_arena_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena_bg.visible = false
	_arena_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_arena_bg)

	var screen := VBoxContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_theme_constant_override("separation", 0)
	add_child(screen)
	_hud = HUD_SCENE.instantiate()
	screen.add_child(_hud)
	_hud.info_requested.connect(_on_hud_info)
	_hud.help_pressed.connect(_show_help)
	_hud.menu_pressed.connect(_on_menu)
	_pages = _safe_margin([10, 5, 10, 8], false)
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(_pages)

	var card_layer := _safe_margin([12, 0, 12, 12], true)
	card_layer.anchor_left = 0.0
	card_layer.anchor_right = 1.0
	card_layer.anchor_top = 1.0
	card_layer.anchor_bottom = 1.0
	card_layer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_layer)
	_card = INFO_CARD_SCENE.instantiate()
	_card.size_flags_vertical = Control.SIZE_SHRINK_END
	card_layer.add_child(_card)
	_card.action_pressed.connect(_on_card_action)
	_card.closed.connect(_on_card_closed)

	_load_sprites()
	rs = WsRuleset.load_dir(DATA_DIR)
	if rs == null:
		var page := _new_page()
		page.add_child(_title_label(Loc.t("WS_NO_RULESET")))
		return
	if not Session.workshop_test and Session.workshop_continue and _load_run():
		_show_shop()
	else:
		_show_start()
	Session.workshop_continue = false


# --- Bausteine ---

func _safe_margin(margins: Array, use_top: bool) -> MarginContainer:
	var margin := SafeMargin.new()
	margin.use_top = use_top
	for i in 4:
		margin.add_theme_constant_override("margin_" + ["left", "top", "right", "bottom"][i], int(margins[i]))
	return margin


## Neue Seite statt der alten. Laufende Kampf-Wiedergaben merken am Zähler, dass sie aufhören sollen.
func _new_page(arena: bool = false) -> Control:
	_page_token += 1
	_card.close()
	_selected = {}
	if _page != null:
		_page.queue_free()
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.add_child(_page)
	_arena_bg.visible = arena
	_backdrop.visible = not arena
	_hud.visible = not arena
	if arena:
		_page.theme = ARENA_THEME
	return _page


func _fill(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


func _hbox(separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


func _label(text: String, size: int, variation: StringName = &"", outline: int = 4) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	if variation == &"":
		label.add_theme_constant_override("outline_size", outline)
	return label


func _title_label(text: String) -> Label:
	var label := _label(text, 26, &"", 6)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, variation: StringName, callback: Callable, height: int = 52, font: int = 16) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


## Weißes Panel mit farbiger Kopfleiste. Liefert den Inhalt (VBox) zurück, das Panel ist dessen Eltern.
func _panel(title: String, header: StringName) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"WhitePanel"
	var box := _vbox(4)
	panel.add_child(box)
	if title != "":
		box.add_child(_label(title, 13, header))
	return box


func _load_sprites() -> void:
	var file := FileAccess.open(SPRITE_MAP, FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			_sprites = data


## Bildpfad unter assets/sprites/. Neue Einheiten ohne Eintrag bekommen fest ein Bild aus der Liste.
func _sprite_path(id: String) -> String:
	if _sprites.has(id):
		return _sprites[id]
	if _sprites.is_empty():
		return FALLBACK_SPRITE
	var keys := _sprites.keys()
	keys.sort()
	return _sprites[keys[absi(id.hash()) % keys.size()]]


func _texture(id: String) -> Texture2D:
	if not _textures.has(id):
		_textures[id] = load(SPRITE_ROOT + _sprite_path(id))
	return _textures[id]


func _color_of(color_id: String) -> Color:
	for c: Dictionary in rs.rules.get("colors", []):
		if c["id"] == color_id:
			return Color(c.get("hex", "#888888"))
	return Color("#888888")


func _color_name(color_id: String) -> String:
	if _tr("WS_COLOR_", color_id) != color_id:
		return _tr("WS_COLOR_", color_id)
	for c: Dictionary in rs.rules.get("colors", []):
		if c["id"] == color_id:
			return str(c.get("name", color_id))
	return color_id


func _unit_color(id: String) -> Color:
	var colors: Array = rs.get_def(id).get("colors", [])
	return _color_of(colors[0]) if not colors.is_empty() else Color("#8c8c8c")


## Text zu einer id aus der Tabelle (prefix + id), sonst die id selbst.
func _tr(prefix: String, id: String) -> String:
	var key := prefix + id
	var text := Loc.t(key)
	return id if text == key else text


func _unit_name(id: String) -> String:
	return str(rs.get_def(id).get("name", id))


func _rarity_name(rarity: int) -> String:
	if _tr("WS_RARITY_", str(rarity)) != str(rarity):
		return _tr("WS_RARITY_", str(rarity))
	var names: Array = rs.rules.get("rarities", [])
	return str(names[rarity]) if rarity >= 0 and rarity < names.size() else ""


func _stats(unit: Dictionary) -> Vector2i:
	var stats := rs.level_stats(unit["id"], int(unit["level"]))
	return Vector2i(int(stats["atk"]) + int(unit.get("atk_bonus", 0)), int(stats["hp"]) + int(unit.get("hp_bonus", 0)))


func _wins_needed() -> int:
	return int(rs.section("run").get("wins_to_victory", 10))


func _merge_needed() -> int:
	var counts: Array = rs.section("board").get("merge_counts", [3, 2])
	return int(counts[0]) if not counts.is_empty() else 3


func _copies(id: String) -> int:
	return run.owned_units().filter(func(u: Dictionary) -> bool: return u["id"] == id and int(u["level"]) == 1).size()


# --- Texte zu Einheiten ---

func ability_text(a: Dictionary) -> String:
	var trig := _tr("WS_TRIG_", str(a.get("trigger", "")))
	if a.get("trigger", "") == "avenge":
		trig += " (%d)" % int(a.get("count", 1))
	var tgt := _tr("WS_TGT_", str(a.get("target", "self")))
	var only := ""
	if a.get("only") is Dictionary and a["only"].has("color"):
		only = " (" + _color_name(str(a["only"]["color"])) + ")"
	var when := ""
	if a.get("when") is Dictionary and a["when"].has("color"):
		when = " [" + _color_name(str(a["when"]["color"])) + "]"
	var times := " %d×" % int(a["times"]) if int(a.get("times", 1)) > 1 else ""
	var what := ""
	match a.get("effect", ""):
		"buff":
			var parts: Array[String] = []
			if int(a.get("atk", 0)) != 0:
				parts.append(Loc.t("WS_AB_ATK", {"n": int(a["atk"])}))
			if int(a.get("hp", 0)) != 0:
				parts.append(Loc.t("WS_AB_HP", {"n": int(a["hp"])}))
			if a.get("value_from", "") != "":
				parts.append(Loc.t("WS_AB_FROM", {"from": str(a["value_from"])}))
			if a.get("keyword", "") != "":
				parts.append(_tr("WS_KW_", str(a["keyword"])))
			what = "%s%s: %s%s" % [tgt, only, ", ".join(parts), Loc.t("WS_AB_PERM") if a.get("permanent", false) else ""]
		"give_keyword":
			var kw := Loc.t("WS_AB_RANDOM_KW") if a.get("keyword") == "random" else _tr("WS_KW_", str(a.get("keyword", "")))
			what = Loc.t("WS_AB_GETS", {"target": tgt + only, "kw": kw})
		"remove_keyword":
			var lost: Array = a.get("keywords", []).map(func(k: String) -> String: return _tr("WS_KW_", k))
			what = Loc.t("WS_AB_LOSES", {"target": tgt, "kw": ", ".join(lost)})
		"summon":
			what = Loc.t("WS_AB_SUMMON", {"unit": Loc.t("WS_AB_DR_UNIT") if a.get("random", "") == "deathrattle" else _unit_name(a.get("token", ""))})
		"damage":
			what = Loc.t("WS_AB_DAMAGE", {"n": int(a.get("value", 0)), "extra": " + " + str(a["value_from"]) if a.get("value_from", "") != "" else "", "target": tgt + only})
		"destroy":
			what = Loc.t("WS_AB_DESTROY", {"target": tgt})
		"attack_now":
			what = Loc.t("WS_AB_ATTACK_NOW")
		"trigger_ability":
			what = Loc.t("WS_AB_TRIGGER", {"trigger": _tr("WS_TRIG_", str(a.get("ability_trigger", ""))), "target": tgt})
		"gold":
			what = Loc.t("WS_AB_GOLD", {"n": int(a.get("value", 0))})
		"free_reroll":
			what = Loc.t("WS_AB_FREE", {"n": int(a.get("value", 0))})
		_:
			what = str(a.get("effect", ""))
	return "[color=%s]%s%s:[/color] %s%s" % [COLOR_ATK, trig, when, what, times]


## Info-Karte zu einer Einheit. unit leer: Angebot auf Stufe 1, sonst eigene Einheit mit Boni.
func _show_unit_card(id: String, level: int, unit: Dictionary = {}) -> void:
	var def := rs.get_def(id)
	var stats := rs.level_stats(id, level)
	var values := _stats({"id": id, "level": level, "atk_bonus": unit.get("atk_bonus", 0), "hp_bonus": unit.get("hp_bonus", 0)})
	var kws: Array = stats.get("keywords", []) + unit.get("keywords", [])
	var lines: Array[String] = ["[color=%s]%s[/color]   [color=%s]%s[/color]" % [COLOR_ATK, Loc.t("WS_ATK", {"n": values.x}), COLOR_HP, Loc.t("WS_HP", {"n": values.y})]]
	for p: String in stats.get("passives", []):
		lines.append(_tr("WS_PAS_", p))
	for a: Dictionary in stats.get("abilities", []):
		lines.append(ability_text(a))
	for k: String in kws:
		var text := _tr("WS_KWL_", k)
		var split := text.find(":")
		lines.append("[color=%s]%s[/color]%s" % [COLOR_TERM, text.substr(0, split), text.substr(split)] if split > 0 else text)
	var ref: Variant = def.get("ref")
	if ref is Dictionary:
		lines.append(Loc.t("WS_TEMPLATE", {"name": ref.get("bg_name", ""), "tier": ref.get("bg_tier", "")}))
	_card.show_text(_unit_name(id), "\n".join(lines), _texture(id))
	var colors: Array = def.get("colors", [])
	var sub := Loc.t("WS_SUB", {"rarity": _rarity_name(int(def.get("rarity", 0))), "level": level, "colors": ", ".join(colors.map(_color_name))})
	if rs.is_token(id):
		sub = Loc.t("WS_SUB_TOKEN", {"level": level})
	_card.set_subtitle(sub)


# --- Speichern ---

## Nur im normalen Spiel: nach jeder Aktion speichern, am Run-Ende löschen. Der Testbereich speichert nicht.
func _save_run() -> void:
	if Session.workshop_test or run == null:
		return
	if run.is_over():
		Session.clear_workshop_save()
		return
	var file := FileAccess.open(Session.WORKSHOP_SAVE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(run.to_save()))


func _load_run() -> bool:
	var data: Variant = GameData.load_json(Session.WORKSHOP_SAVE) if Session.has_workshop_save() else null
	var loaded: WsRun = WsRun.from_save(rs, data) if data is Dictionary else null
	if loaded == null:
		Session.clear_workshop_save()
		return false
	run = loaded
	run.trace = true
	mode = str(data.get("mode", "bg"))
	difficulty = run.difficulty
	return true


func _on_menu() -> void:
	if Session.workshop_test:
		_show_start()
	else:
		Session.goto(Session.TITLE_SCENE)


# --- Start und Ende ---

func _show_start() -> void:
	var page := _new_page()
	_hud.visible = false
	Audio.play_music("menu")
	var box := _fill(_vbox(12)) as VBoxContainer
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(box)
	box.add_child(_title_label(Loc.t("WS_TITLE" if Session.workshop_test else "WS_GAME_TITLE")))
	if Session.workshop_test:
		_add_ruleset_info(box)
	_add_difficulty(box)
	if Session.workshop_test:
		box.add_child(_button(Loc.t("WS_NEW_BG"), &"PrimaryButton", _new_run.bind("bg"), 56, 20))
		box.add_child(_button(Loc.t("WS_NEW_GRID"), &"", _new_run.bind("grid"), 52, 16))
		box.add_child(_button(Loc.t("WS_BACK_TO_GAME"), &"", func() -> void: Session.goto(Session.TITLE_SCENE), 48, 14))
	else:
		box.add_child(_button(Loc.t("WS_START_RUN"), &"PrimaryButton", _new_run.bind("bg"), 56, 20))
		box.add_child(_button(Loc.t("BTN_BACK"), &"", func() -> void: Session.goto(Session.TITLE_SCENE), 48, 14))


func _add_ruleset_info(box: VBoxContainer) -> void:
	var meta: Dictionary = rs.section("meta")
	var info := _panel(Loc.t("WS_RULESET"), &"HeaderBlue")
	var text := Loc.t("WS_RULESET_INFO", {"name": meta.get("name", ""), "version": meta.get("version", "?"),
		"units": rs.units.size(), "ghosts": rs.ghosts.size()})
	if rs.ghosts.is_empty():
		text += "\n" + Loc.t("WS_NO_GHOSTS")
	info.add_child(_label(text, 11, &"PanelLabel"))
	box.add_child(info.get_parent())


func _add_difficulty(box: VBoxContainer) -> void:
	var levels: Array = rs.section("run").get("difficulties", [])
	if levels.is_empty():
		difficulty = ""
	else:
		if not levels.any(func(d: Dictionary) -> bool: return d["id"] == difficulty):
			difficulty = levels[mini(1, levels.size() - 1)]["id"]
		var choice := _panel(Loc.t("WS_DIFFICULTY"), &"HeaderYellow")
		var row := _hbox(6)
		choice.add_child(row)
		var hint := _label("", 11, &"PanelLabel")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var group := ButtonGroup.new()
		var buttons: Array[Button] = []
		for level: Dictionary in levels:
			var button := _button(str(level.get("name", level["id"])), &"", Callable(), 48, 15)
			button.toggle_mode = true
			button.button_group = group
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.button_pressed = level["id"] == difficulty
			buttons.append(button)
			row.add_child(button)
			button.pressed.connect(func() -> void:
				difficulty = level["id"]
				Audio.play("click")
				_mark_difficulty(buttons, levels, hint))
		choice.add_child(hint)
		_mark_difficulty(buttons, levels, hint)
		box.add_child(choice.get_parent())


## Gewählte Stufe rot hervorheben, darunter ein kurzer Satz dazu.
func _mark_difficulty(buttons: Array[Button], levels: Array, hint: Label) -> void:
	for i in buttons.size():
		var selected: bool = levels[i]["id"] == difficulty
		buttons[i].theme_type_variation = &"PrimaryButton" if selected else &""
		if selected:
			hint.text = _tr("WS_DIFF_", difficulty)
			if hint.text == difficulty:
				hint.text = Loc.t("WS_DIFF_RANGE", {"min": int(levels[i].get("min", 0)), "max": int(levels[i].get("max", 100))})


func _difficulty_name(id: String) -> String:
	for level: Dictionary in rs.section("run").get("difficulties", []):
		if level["id"] == id:
			return str(level.get("name", id))
	return id


func _new_run(combat_mode: String) -> void:
	mode = combat_mode
	run = WsRun.create(rs, int(Time.get_unix_time_from_system()) % 2147483647, combat_mode, difficulty)
	run.trace = true
	Audio.play("click")
	_show_shop()


func _show_end() -> void:
	var page := _new_page()
	_hud.visible = false
	Audio.play_music("menu")
	var box := _fill(_vbox(12)) as VBoxContainer
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(box)
	box.add_child(_title_label(Loc.t("WS_WON_TITLE" if run.is_victory() else "WS_OVER_TITLE")))
	var summary := _panel(Loc.t("WS_RESULT"), &"HeaderPink" if not run.is_victory() else &"HeaderGreen")
	summary.add_child(_label(Loc.t("WS_WON_TEXT" if run.is_victory() else "WS_LOST_TEXT") + "\n" + Loc.t("WS_SUMMARY", {
		"wins": run.wins, "losses": run.losses, "draws": run.draws, "days": run.day - 1}), 13, &"PanelLabel"))
	if run.difficulty != "":
		summary.add_child(_label(Loc.t("WS_DIFFICULTY_LINE", {"name": _difficulty_name(run.difficulty)}), 12, &"PanelLabel"))
	var team := _hbox(4)
	team.alignment = BoxContainer.ALIGNMENT_CENTER
	for unit: Dictionary in run.team_units():
		var image := TextureRect.new()
		image.texture = _texture(unit["id"])
		image.custom_minimum_size = Vector2(44, 44)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		team.add_child(image)
	summary.add_child(team)
	box.add_child(summary.get_parent())
	box.add_child(_button(Loc.t("WS_NEW_RUN"), &"PrimaryButton", _show_start, 56, 20))
	if not Session.workshop_test:
		box.add_child(_button(Loc.t("BTN_MENU"), &"", func() -> void: Session.goto(Session.TITLE_SCENE), 48, 14))


# --- Shop ---

func _show_shop() -> void:
	var page := _new_page()
	Audio.play_music("menu")
	_team_cells.clear()
	_bench_cells.clear()
	_shop_cards.clear()
	var layout := _fill(_vbox(5)) as VBoxContainer
	page.add_child(layout)

	var info_row := _hbox(6)
	layout.add_child(info_row)
	var odds := _button("", &"", _on_hud_info.bind("ODDS"), 48)
	odds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(odds)
	_odds_label = RichTextLabel.new()
	_odds_label.bbcode_enabled = true
	_odds_label.scroll_active = false
	_odds_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_odds_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_odds_label.add_theme_color_override("default_color", Color(0.227451, 0.211765, 0.282353))
	_odds_label.add_theme_font_size_override("normal_font_size", 10)
	odds.add_child(_odds_label)
	_odds_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_odds_label.offset_left = 7
	_odds_label.offset_top = 16
	_odds_label.offset_right = -4
	_gold_button = _button("0", &"PrimaryButton", _on_hud_info.bind("GOLD"), 48, 22)
	_gold_button.custom_minimum_size.x = 96
	_gold_button.icon = COIN
	_gold_button.expand_icon = true
	_gold_button.add_theme_constant_override("icon_max_width", 18)
	_gold_button.add_theme_constant_override("h_separation", 6)
	info_row.add_child(_gold_button)

	var team := _panel(Loc.t("SHOP_TEAM").to_upper(), &"HeaderPink")
	layout.add_child(team.get_parent())
	var caption := _label(Loc.t("WS_CAPTION_BG" if mode == "bg" else "WS_CAPTION_GRID"), 10, &"PanelLabel")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	team.add_child(grid)
	for i in run.team.size():
		_team_cells.append(_make_cell(grid, WsRun.TEAM, i, TEAM_CELL))

	var bench := _panel(Loc.t("WS_BENCH").to_upper(), &"HeaderYellow")
	layout.add_child(bench.get_parent())
	var bench_row := _hbox(4)
	bench_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bench.add_child(bench_row)
	for i in run.bench.size():
		_bench_cells.append(_make_cell(bench_row, WsRun.BENCH, i, BENCH_CELL))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)

	var bottom := MarginContainer.new()
	layout.add_child(bottom)
	_shop_area = _vbox(6)
	bottom.add_child(_shop_area)
	var shop_panel := PanelContainer.new()
	shop_panel.theme_type_variation = &"WhitePanel"
	_shop_area.add_child(shop_panel)
	var cards := _hbox(3)
	shop_panel.add_child(cards)
	for i in run.offers.size():
		var card: ShopCard = SHOP_CARD_SCENE.instantiate()
		card.index = i
		card.custom_minimum_size.x = 58
		card.add_to_group("silent_button")
		card.pressed.connect(_tap_offer.bind(i))
		cards.add_child(card)
		_shop_cards.append(card)

	var buttons := _hbox(6)
	_shop_area.add_child(buttons)
	_reroll = _button("", &"YellowButton", _on_reroll, 54, 15)
	_lock = _button("", &"BlueButton", _on_lock, 54, 15)
	_fight = _button(Loc.t("SHOP_FIGHT"), &"PrimaryButton", _on_fight, 54, 20)
	for b in [_reroll, _lock, _fight]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)

	_sell_zone = DropZone.new()
	_sell_zone.visible = false
	var sell_style := StyleBoxTexture.new()
	sell_style.texture = DANGER
	sell_style.texture_margin_left = 4
	sell_style.texture_margin_top = 4
	sell_style.texture_margin_right = 4
	sell_style.texture_margin_bottom = 5
	_sell_zone.add_theme_stylebox_override("panel", sell_style)
	_sell_zone.dropped.connect(func(data: Dictionary) -> void: _sell(data["loc"], int(data["slot"])))
	bottom.add_child(_sell_zone)
	_sell_label = _label("", 17)
	_sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sell_zone.add_child(_sell_label)
	_refresh_shop()


func _make_cell(parent: Control, loc: String, index: int, cell_size: Vector2) -> UnitCell:
	var cell: UnitCell = CELL_SCENE.instantiate()
	cell.custom_minimum_size = cell_size
	parent.add_child(cell)
	cell.slot = index
	cell.loc = loc
	cell.set_card_style()
	cell.set_interactive(true)
	cell.draggable = true
	cell.offer_check = func(offer_index: int, slot: int) -> bool: return _can_buy_at(offer_index, loc, slot)
	cell.tapped.connect(func(slot: int) -> void: _tap_owned(loc, slot))
	cell.unit_dropped.connect(func(data: Dictionary, slot: int) -> void: _on_unit_dropped(data, loc, slot))
	cell.offer_dropped.connect(func(offer_index: int, slot: int) -> void: _buy(offer_index, loc, slot))
	return cell


func _refresh_shop() -> void:
	_save_run()
	_hud.show_values(run.lives, Loc.t("WS_DAY", {"n": run.day}), run.wins, _wins_needed())
	_gold_button.text = str(run.gold)
	_show_odds()
	for loc in [WsRun.TEAM, WsRun.BENCH]:
		var cells: Array[UnitCell] = _team_cells if loc == WsRun.TEAM else _bench_cells
		var slots := run.slots_of(loc)
		for i in cells.size():
			var unit: Variant = slots[i]
			if unit == null:
				cells[i].clear()
			else:
				var values := _stats(unit)
				cells[i].show_unit(unit["id"], _sprite_path(unit["id"]), values.y, values.x, int(unit["level"]), false)
			cells[i].set_highlight(_selected == {"kind": loc, "index": i})
	for i in _shop_cards.size():
		var card := _shop_cards[i]
		var offer: Variant = run.offers[i] if i < run.offers.size() else null
		if offer == null:
			card.show_empty()
			continue
		var stats := rs.level_stats(offer["id"], 1)
		card.show_custom(_unit_name(offer["id"]), _texture(offer["id"]), int(stats["atk"]), int(stats["hp"]),
			int(offer["cost"]), _unit_color(offer["id"]))
		card.set_affordable(run.gold >= int(offer["cost"]))
		card.set_frozen(run.locked)
		card.set_merge_progress(_copies(offer["id"]), _merge_needed())
		card.set_selected(_selected == {"kind": "offer", "index": i})
	if run.free_rerolls > 0:
		_reroll.text = Loc.t("WS_FREE", {"n": run.free_rerolls})
		_reroll.disabled = false
	else:
		_reroll.text = Loc.t("WS_REROLL", {"n": run.reroll_cost()})
		_reroll.disabled = run.gold < run.reroll_cost()
	_lock.text = Loc.t("WS_UNLOCK" if run.locked else "WS_LOCK")
	_fight.disabled = run.team_units().is_empty()


func _show_odds() -> void:
	var weights: Array = rs.rarity_weights(run.rank())
	var total := 0
	for w: Variant in weights:
		total += int(w)
	var parts: Array[String] = [Loc.t("SHOP_RANK", {"n": run.rank()})]
	for rarity in weights.size():
		var percent := roundi(100.0 * int(weights[rarity]) / maxi(total, 1))
		parts.append("[color=%s]%d%%[/color]" % [RARITY_COLORS[mini(rarity, RARITY_COLORS.size() - 1)], percent])
	_odds_label.text = " ".join(parts)


func _can_buy_at(offer_index: int, loc: String, slot: int) -> bool:
	if not run.can_buy(offer_index):
		return false
	var unit: Variant = run.slots_of(loc)[slot]
	if unit == null:
		return true
	var id: String = run.offers[offer_index]["id"]
	return unit["id"] == id and int(unit["level"]) == 1 and _copies(id) + 1 >= _merge_needed()


func _tap_offer(index: int) -> void:
	var offer: Variant = run.offers[index]
	if offer == null:
		return
	_selected = {"kind": "offer", "index": index}
	_show_unit_card(offer["id"], 1)
	var cost := int(offer["cost"])
	_card.set_action(Loc.t("CARD_BUY", {"cost": cost}), run.can_buy(index))
	if run.gold < cost:
		_card.set_note(Loc.t("WS_NOTE_NO_GOLD"))
	elif not run.can_buy(index):
		_card.set_note(Loc.t("WS_NOTE_FULL"))
	elif _copies(offer["id"]) > 0:
		_card.set_note(Loc.t("WS_NOTE_COPIES", {"n": _copies(offer["id"]), "max": _merge_needed()}))
	else:
		_card.set_note(Loc.t("WS_NOTE_DRAG"))
	Audio.play("click")
	_refresh_shop()


func _tap_owned(loc: String, slot: int) -> void:
	var unit: Variant = run.slots_of(loc)[slot]
	if unit == null:
		return
	_selected = {"kind": loc, "index": slot}
	_show_unit_card(unit["id"], int(unit["level"]), unit)
	var value := 0 if rs.is_token(unit["id"]) else rs.sell_value(unit["id"], int(unit["level"]))
	_card.set_action(Loc.t("WS_SELL", {"n": value}))
	_card.set_note(Loc.t("WS_NOTE_OWNED"))
	Audio.play("click")
	_refresh_shop()


func _on_card_action() -> void:
	match _selected.get("kind", ""):
		"offer":
			_buy(int(_selected["index"]))
		WsRun.TEAM, WsRun.BENCH:
			_sell(_selected["kind"], int(_selected["index"]))
		_:
			_card.close()


func _on_card_closed() -> void:
	_selected = {}
	if run != null and _shop_cards.size() > 0 and is_instance_valid(_shop_cards[0]):
		_refresh_shop()


## loc/slot: Ziel beim Ziehen. Die Bank als Ziel geht über einen Umweg: kaufen, dann dorthin schieben.
func _buy(index: int, loc: String = "", slot: int = -1) -> void:
	if not run.can_buy(index):
		Audio.play("error")
		return
	var before := run.team.duplicate() + run.bench.duplicate()
	var result := run.buy(index, slot if loc == WsRun.TEAM else -1)
	if not result.get("ok", false):
		Audio.play("error")
		return
	var merged := int(result.get("merged", 0))
	if loc == WsRun.BENCH and merged == 0 and run.bench[slot] == null:
		var after := run.team + run.bench
		for i in after.size():
			if before[i] == null and after[i] != null:
				var from_loc := WsRun.TEAM if i < run.team.size() else WsRun.BENCH
				run.move(from_loc, i if i < run.team.size() else i - run.team.size(), WsRun.BENCH, slot)
				break
	_selected = {}
	if merged > 0:
		Audio.play("merge")
		Haptics.pulse(Haptics.MERGE)
		_refresh_shop()
		for loc_name in [WsRun.TEAM, WsRun.BENCH]:
			var slots := run.slots_of(loc_name)
			for i in slots.size():
				if slots[i] != null and slots[i]["id"] == result["id"] and int(slots[i]["level"]) == merged:
					var cell: UnitCell = (_team_cells if loc_name == WsRun.TEAM else _bench_cells)[i]
					cell.flash(FLASH_MERGE, 0.5)
					_show_unit_card(slots[i]["id"], merged, slots[i])
					_card.set_note(Loc.t("WS_MERGED", {"n": merged}))
		return
	Audio.play("buy")
	Haptics.pulse(Haptics.TAP)
	_card.close()
	_refresh_shop()


func _sell(loc: String, slot: int) -> void:
	var unit: Variant = run.slots_of(loc)[slot]
	var result := run.sell(loc, slot)
	if not result.get("ok", false):
		return
	Audio.play("sell")
	_selected = {}
	_card.show_text(_unit_name(unit["id"]), Loc.t("WS_SOLD", {"n": int(result["value"])}), _texture(unit["id"]))
	_refresh_shop()


func _on_unit_dropped(data: Dictionary, to_loc: String, to_slot: int) -> void:
	if run.move(str(data.get("loc", "")), int(data["slot"]), to_loc, to_slot):
		Audio.play("click")
		_selected = {}
		_card.close()
		_refresh_shop()


func _on_reroll() -> void:
	if run.reroll():
		Audio.play("reroll")
		_card.close()
		_refresh_shop()
	else:
		Audio.play("error")


func _on_lock() -> void:
	run.toggle_lock()
	Audio.play("click")
	_card.show_text(Loc.t("WS_LOCKED_T" if run.locked else "WS_UNLOCKED_T"), Loc.t("WS_LOCKED_INFO" if run.locked else "WS_UNLOCKED_INFO"))
	_refresh_shop()


func _on_fight() -> void:
	if run.team_units().is_empty():
		return
	Audio.play("click")
	var battle := run.fight()
	_save_run()
	_show_battle(battle)


func _notification(what: int) -> void:
	if not is_node_ready() or _sell_zone == null or not is_instance_valid(_sell_zone) or run == null:
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if not (data is Dictionary):
			return
		_card.close()
		if data.get("kind", "") == ShopCard.DRAG_KIND:
			var index := int(data["index"])
			for i in _team_cells.size():
				_team_cells[i].set_highlight(_can_buy_at(index, WsRun.TEAM, i))
			for i in _bench_cells.size():
				_bench_cells[i].set_highlight(_can_buy_at(index, WsRun.BENCH, i))
		elif data.get("kind", "") == UnitCell.DRAG_KIND:
			var unit: Variant = run.slots_of(str(data.get("loc", "")))[int(data["slot"])]
			if unit != null:
				var value := 0 if rs.is_token(unit["id"]) else rs.sell_value(unit["id"], int(unit["level"]))
				_sell_label.text = Loc.t("WS_SELL_DROP", {"n": value})
				_sell_zone.visible = true
				_shop_area.modulate.a = 0.0
	elif what == NOTIFICATION_DRAG_END:
		_sell_zone.visible = false
		_shop_area.modulate.a = 1.0
		for cell in _team_cells + _bench_cells:
			cell.set_highlight(false)


# --- Infos über die Kopfleiste ---

func _on_hud_info(topic: String) -> void:
	if run == null:
		return
	_selected = {}
	match topic:
		"LIVES":
			var losses: Array = rs.section("run").get("life_loss_by_day", [1])
			var parts: Array[String] = []
			for i in losses.size():
				parts.append(Loc.t("WS_LIVES_DAY" if i < losses.size() - 1 else "WS_LIVES_FROM", {"n": i + 1, "v": losses[i]}))
			var text := Loc.t("WS_LIVES_INFO", {"list": ", ".join(parts)})
			if rs.section("run").get("second_chance", false):
				text += " " + Loc.t("WS_SECOND_CHANCE")
			_card.show_text(Loc.t("HUD_LIVES_T"), text)
		"WINS":
			var draw: String = rs.section("run").get("draw_result", "draw")
			var text := Loc.t("WS_WINS_INFO", {"n": _wins_needed()})
			if draw in ["win", "loss"]:
				text += " " + Loc.t("WS_DRAW_WIN" if draw == "win" else "WS_DRAW_LOSS")
			_card.show_text(Loc.t("HUD_WINS_T"), text)
		"ROUND":
			_card.show_text(Loc.t("WS_DAY", {"n": run.day}), Loc.t("WS_ROUND_INFO", {"n": run.rank()}))
		"GOLD":
			var carries: bool = rs.section("economy").get("gold_carries_over", true)
			_card.show_text(Loc.t("HUD_GOLD_T"), Loc.t("WS_GOLD_INFO", {"gold": run.gold, "cost": run.reroll_cost()}) + " " + Loc.t("WS_GOLD_KEEP" if carries else "WS_GOLD_LOSE"))
		"ODDS":
			var weights: Array = rs.rarity_weights(run.rank())
			var lines: Array[String] = []
			for rarity in weights.size():
				lines.append("[color=%s]%s[/color]: %d" % [RARITY_COLORS[mini(rarity, RARITY_COLORS.size() - 1)], _rarity_name(rarity), int(weights[rarity])])
			_card.show_text(Loc.t("WS_ODDS_T", {"n": run.rank()}), Loc.t("WS_ODDS_INFO") + "\n" + "\n".join(lines))
	if _shop_cards.size() > 0 and is_instance_valid(_shop_cards[0]):
		_refresh_shop()


func _show_help() -> void:
	_card.show_text(Loc.t("WS_HELP_T"), Loc.t("WS_HELP"))


# --- Kampf ---

func _show_battle(battle: Dictionary) -> void:
	var page := _new_page(true)
	var token := _page_token
	Audio.play_music("battle")
	_skip = false
	_battle_cells.clear()
	_battle_units.clear()
	_lines = [[], []]
	_line_boxes = []
	_grid_cells = [[], []]
	_dead.clear()

	var layout := _fill(_vbox(6)) as VBoxContainer
	page.add_child(layout)
	var header := _hbox(6)
	layout.add_child(header)
	var title := _label(Loc.t("WS_DAY", {"n": int(battle["day"])}), 18)
	title.add_theme_color_override("font_color", Color(0.92549, 0.827451, 0.576471))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var strength := int(battle.get("ghost_strength", -1))
	var ghost_text := Loc.t("WS_ENEMY_STRENGTH", {"n": strength}) if strength >= 0 else Loc.t("WS_ENEMY_ID", {"id": battle.get("ghost_id", "?")})
	if str(battle.get("difficulty", "")) != "":
		ghost_text += " (%s)" % _difficulty_name(battle["difficulty"])
	var ghost := _label(ghost_text, 11)
	ghost.add_theme_color_override("font_color", Color(0.678431, 0.647059, 0.768627))
	ghost.autowrap_mode = TextServer.AUTOWRAP_OFF
	ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(ghost)

	var holders: Array[Control] = []
	for side in [1, 0]:
		var caption := _label(Loc.t("WS_ENEMY" if side == 1 else "WS_YOUR_TEAM"), 12)
		caption.add_theme_color_override("font_color", Color(0.678431, 0.647059, 0.768627))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var holder := CenterContainer.new()
		holders.append(holder)
		if side == 1:
			layout.add_child(caption)
			layout.add_child(holder)
			var gap := Control.new()
			gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
			layout.add_child(gap)
		else:
			layout.add_child(holder)
			layout.add_child(caption)
	var result := _label("", 24, &"", 6)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.custom_minimum_size = Vector2(0, 64)
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layout.add_child(result)
	var controls := _hbox(8)
	layout.add_child(controls)
	var skip := _button(Loc.t("WS_SKIP"), &"", func() -> void: _skip = true, 52, 16)
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var speed := _button("%dx" % int(SPEEDS[_speed_index]), &"", Callable(), 52, 16)
	speed.custom_minimum_size.x = 72
	speed.pressed.connect(func() -> void:
		_speed_index = (_speed_index + 1) % SPEEDS.size()
		speed.text = "%dx" % int(SPEEDS[_speed_index]))
	controls.add_child(skip)
	controls.add_child(speed)

	_fx = BattleFx.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_fill(_fx))

	# Gegner in holders[0] (oben), eigenes Team in holders[1] (unten).
	for i in 2:
		var side := 1 - i
		if mode == "grid":
			var grid := GridContainer.new()
			grid.columns = rs.grid_cols()
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			holders[i].add_child(grid)
			var cells: Array = []
			cells.resize(rs.team_slots())
			# Vorne liegt immer zur Mitte: beim Gegner unten, beim eigenen Team oben.
			var rows := int(ceil(float(rs.team_slots()) / rs.grid_cols()))
			for visual in rs.team_slots():
				var row := floori(float(visual) / rs.grid_cols())
				var col := visual % rs.grid_cols()
				var cell_index: int = (rows - 1 - row) * rs.grid_cols() + col if side == 1 else visual
				var cell := _battle_cell(grid, side, GRID_CELL)
				cells[cell_index] = cell
			_grid_cells[side] = cells
		else:
			var box := _hbox(2)
			holders[i].add_child(box)
			holders[i].custom_minimum_size = Vector2(0, LINE_CELL.y)
			_line_boxes.append(box)
	if mode != "grid":
		_line_boxes.reverse()  # Index = Seite
	await get_tree().process_frame
	if token != _page_token:
		return
	await _play(battle, token, layout)
	if token != _page_token:
		return
	_finish_battle(battle, result, controls)


func _battle_cell(parent: Control, side: int, cell_size: Vector2) -> UnitCell:
	var cell: UnitCell = CELL_SCENE.instantiate()
	cell.custom_minimum_size = cell_size
	parent.add_child(cell)
	cell.set_floor(FLOOR_ENEMY if side == 1 else FLOOR_PLAYER)
	cell.show_hp_bar = true
	cell.set_interactive(false)
	cell.clear()
	if cell_size.x < GRID_CELL.x:
		var sprite: Control = cell.get_node("Body/Sprite")
		sprite.offset_left = -LINE_SPRITE / 2.0
		sprite.offset_right = LINE_SPRITE / 2.0
		sprite.offset_top = -LINE_SPRITE / 2.0 - 4.0
		sprite.offset_bottom = LINE_SPRITE / 2.0 - 4.0
	return cell


func _wait(seconds: float) -> void:
	if _skip:
		return
	await get_tree().create_timer(seconds / SPEEDS[_speed_index]).timeout


func _t(seconds: float) -> float:
	return seconds / SPEEDS[_speed_index]


## Spielt die Ereignisliste ab. Zwischen zwei Angriffen eine kurze Pause, Treffer im Moment des Aufpralls.
func _play(battle: Dictionary, token: int, shake_target: Control) -> void:
	var events: Array = battle.get("events", [])
	if events.is_empty():
		return
	var start: Array = events[0].get("units", [])
	start.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["pos"]) < int(b["pos"]))
	for u: Dictionary in start:
		_spawn(u["uid"], u["id"], int(u["side"]), int(u["pos"]), int(u["atk"]), int(u["hp"]), int(u.get("level", 1)), u.get("keywords", []))
	for uid: Variant in _battle_cells:
		_battle_cells[uid].pop_in(0.0, _t(T_POP))
	await _wait(0.6)
	for i in range(1, events.size()):
		if token != _page_token:
			return
		var e: Dictionary = events[i]
		var cell: UnitCell = _battle_cells.get(e.get("uid", -1))
		match e["ev"]:
			"attack":
				_purge_dead()
				await _wait(T_PAUSE)
				if token != _page_token:
					return
				var target: UnitCell = _battle_cells.get(e["to"])
				if cell != null and target != null and not _skip:
					cell.lunge(target.center(), _t(T_LUNGE))
					await _wait(T_LUNGE * 0.5)
					if token != _page_token:
						return
					target.knock(cell.center(), _t(0.2))
			"damage":
				if cell != null:
					cell.set_stats(int(e["hp"]), 0, 0)
					_mark_keywords(e["uid"])
					if not _skip:
						_fx.damage_number(cell, int(e.get("amount", 0)), COLOR_DAMAGE, shake_target)
						_fx.sparks(cell, COLOR_DAMAGE)
						Audio.play_hit()
			"shield_lost":
				if _battle_units.has(e["uid"]):
					_battle_units[e["uid"]]["kw"].erase("divine_shield")
					_mark_keywords(e["uid"])
				if cell != null and not _skip:
					_fx.ring(cell, COLOR_SHIELD)
					Audio.play("shield")
			"buff":
				if cell != null:
					cell.set_atk(int(e["atk"]))
					cell.set_stats(int(e["hp"]), 0, 0)
					_battle_units[e["uid"]]["kw"] = e.get("keywords", _battle_units[e["uid"]]["kw"])
					_mark_keywords(e["uid"])
					if not _skip:
						_fx.rise(cell, COLOR_BUFF)
			"keywords":
				if _battle_units.has(e["uid"]):
					_battle_units[e["uid"]]["kw"] = e["keywords"]
					_mark_keywords(e["uid"])
			"ability":
				if cell != null and not _skip:
					_fx.ring(cell, COLOR_ABILITY)
			"death":
				if cell != null:
					_battle_cells.erase(e["uid"])
					var side: int = _battle_units[e["uid"]]["side"]
					_lines[side].erase(e["uid"])
					if _skip:
						cell.clear()
					else:
						_fx.puff(cell)
						cell.die(_t(T_DIE))
						Audio.play("death")
					if mode != "grid":
						_dead.append(cell)
			"summon", "reborn":
				_spawn(e["uid"], e["id"], int(e["side"]), int(e["pos"]), int(e["atk"]), int(e["hp"]), int(e.get("level", 1)), [])
				if not _skip:
					await get_tree().process_frame
					if token != _page_token:
						return
					var spawned: UnitCell = _battle_cells.get(e["uid"])
					if spawned != null:
						spawned.pop_in(0.0, _t(T_POP))
						_fx.ring(spawned, COLOR_BUFF if e["ev"] == "summon" else COLOR_SHIELD)
	await _wait(0.4)
	_purge_dead()


## Neue Einheit im Kampf: in der Reihe an Stelle pos einfügen oder in Zelle pos stellen.
func _spawn(uid: int, id: String, side: int, pos: int, atk: int, hp: int, level: int, keywords: Array) -> void:
	_battle_units[uid] = {"id": id, "side": side, "kw": keywords.duplicate()}
	var cell: UnitCell
	if mode == "grid":
		var cells: Array = _grid_cells[side]
		if pos < 0 or pos >= cells.size():
			return
		cell = cells[pos]
	else:
		var box: HBoxContainer = _line_boxes[side]
		cell = _battle_cell(box, side, LINE_CELL)
		var line: Array = _lines[side]
		var index := clampi(pos, 0, line.size())
		if index < line.size():
			box.move_child(cell, (_battle_cells[line[index]] as UnitCell).get_index())
		line.insert(index, uid)
	_battle_cells[uid] = cell
	cell.show_unit(id, _sprite_path(id), hp, atk, level, side == 1)
	_mark_keywords(uid)


## Schild als blaues "S" oben links, Spott als grünes "T" oben rechts.
func _mark_keywords(uid: int) -> void:
	var cell: UnitCell = _battle_cells.get(uid)
	if cell == null or not _battle_units.has(uid):
		return
	var kw: Array = _battle_units[uid]["kw"]
	var shield: Label = cell.get_node("%ShieldLabel")
	shield.text = "S"
	shield.visible = "divine_shield" in kw
	var taunt: Label = cell.get_node("%PoisonLabel")
	taunt.text = "T"
	taunt.visible = "taunt" in kw


func _purge_dead() -> void:
	for cell in _dead:
		if is_instance_valid(cell):
			cell.queue_free()
	_dead.clear()


func _finish_battle(battle: Dictionary, result_label: Label, controls: HBoxContainer) -> void:
	var outcome: String = battle["result"]
	var text := Loc.t({"win": "WS_WIN", "loss": "WS_LOSS"}.get(outcome, "WS_DRAW"))
	if int(battle.get("winner", 0)) == WsCombat.DRAW and outcome != "draw":
		text = Loc.t("WS_DRAW_AS_WIN" if outcome == "win" else "WS_DRAW_AS_LOSS")
	if int(battle.get("lost_lives", 0)) > 0:
		text += "\n" + Loc.t("WS_LIVES_LOST", {"n": int(battle["lost_lives"])})
	result_label.text = text
	result_label.add_theme_color_override("font_color", COLOR_WIN if outcome == "win" else (COLOR_LOSS if outcome == "loss" else Color.WHITE))
	if run.is_over():
		Audio.play("run_won" if run.is_victory() else "run_lost")
	else:
		Audio.play("win" if outcome == "win" else "loss")
	if outcome == "win":
		_fx.confetti()
		Haptics.pulse(Haptics.WIN)
	for child in controls.get_children():
		child.queue_free()
	var next := _button(Loc.t("WS_NEXT"), &"PrimaryButton", _after_battle, 56, 20)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(next)


func _after_battle() -> void:
	if run.is_over():
		_show_end()
	else:
		_show_shop()
