extends Control
## Spielbare Test-Szene für den Balancing-Workshop: Shop, Team, Kampf, Run-Ende.
## Nur im separaten Test-Build (workshop/build_play.sh), nie im veröffentlichten Spiel. Der Regelsatz
## liegt dort unter res://ws_data/. Texte stehen bewusst fest im Code und nicht in translations.csv,
## weil die Szene nur ein Werkzeug ist und nie ausgeliefert wird.

const DATA_DIR := "res://ws_data"
const CARD_FONT := 10
const KW_SHORT := {"taunt": "Spott", "divine_shield": "Schild", "reborn": "Wieder", "windfury": "Wind",
	"venomous": "Gift", "cleave": "Spalt", "stealth": "Tarn"}
const TRIGGER_TEXT := {
	"start_of_combat": "Kampfbeginn", "on_attack": "Beim Angriff", "after_attack": "Nach dem Angriff",
	"on_hurt": "Bei Schaden", "on_death": "Todesröcheln", "on_ally_death": "Wenn ein Verbündeter stirbt",
	"avenge": "Rache", "on_summon": "Wenn ein Verbündeter beschworen wird", "on_ally_attack": "Wenn ein Verbündeter angreift",
	"on_kill": "Nach einem Kill", "on_shield_lost": "Schild verloren", "on_ally_shield_lost": "Verbündeter verliert Schild",
	"on_reborn": "Nach einer Wiedergeburt", "after_deathrattle": "Nach einem Todesröcheln", "on_buy": "Beim Kauf",
	"on_sell": "Beim Verkauf", "end_of_turn": "Rundenende", "start_of_turn": "Tagesbeginn",
	"on_ally_buy": "Wenn du etwas kaufst", "after_battlecry": "Nach einem Kampfschrei", "on_reroll": "Beim Würfeln",
}
const TARGET_TEXT := {
	"self": "sich", "adjacent": "Nachbarn", "ally_random": "zufälliger Verbündeter", "ally_random_other": "anderer Verbündeter",
	"allies_all": "alle Verbündeten", "allies_other": "andere Verbündete", "ally_leftmost": "Verbündeter links",
	"trigger_unit": "Auslöser", "target": "Ziel", "attacker": "Angreifer", "killer": "Mörder", "enemy_random": "zufälliger Gegner",
	"enemies_all": "alle Gegner", "enemy_highest_hp": "stärkster Gegner", "all_others": "alle anderen",
}
const PASSIVE_TEXT := {"deathrattle_twice": "Todesröcheln doppelt", "battlecry_twice": "Kampfschreie doppelt",
	"end_of_turn_twice": "Rundenende doppelt"}

var rs: WsRuleset
var run: WsRun
var mode := "bg"
var selected := {}
var _header: Label
var _body: VBoxContainer
var _info: Label
var _speed := 1.0
var _skip := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1d2026")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	_header = _label("", 12)
	root.add_child(_header)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	root.add_child(_body)

	rs = WsRuleset.load_dir(DATA_DIR)
	if rs == null:
		_header.text = "Kein Regelsatz im Build gefunden (res://ws_data)."
		return
	_show_start()


# --- Bausteine ---

func _label(text: String, size: int = 11) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("#e8e6e1"))
	return l


func _button(text: String, cb: Callable, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	return h


func _clear() -> void:
	for child in _body.get_children():
		child.queue_free()
	selected = {}


func _color_hex(color_id: String) -> Color:
	for c: Dictionary in rs.rules.get("colors", []):
		if c["id"] == color_id:
			return Color(c.get("hex", "#888888"))
	return Color("#888888")


## Karte als Knopf: Farbe der Einheit als Hintergrund, Text in kleinen Zeilen.
func _card(text: String, colors: Array, size: Vector2, cb: Callable, highlight: bool = false, dim: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_size_override("font_size", CARD_FONT)
	var style := StyleBoxFlat.new()
	var base: Color = _color_hex(colors[0]) if not colors.is_empty() else Color("#3a3f4a")
	style.bg_color = base.darkened(0.45 if not dim else 0.75)
	style.set_corner_radius_all(5)
	style.set_border_width_all(3 if highlight else 1)
	style.border_color = Color("#ffd34d") if highlight else (_color_hex(colors[1]) if colors.size() > 1 else base)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, style)
	b.add_theme_color_override("font_color", Color("#ffffff") if not dim else Color("#888888"))
	b.pressed.connect(cb)
	return b


func _unit_name(id: String) -> String:
	return str(rs.get_def(id).get("name", id))


func _owned_text(unit: Dictionary) -> String:
	var stats := rs.level_stats(unit["id"], int(unit["level"]))
	var kws: Array = stats.get("keywords", []) + unit["keywords"]
	var short := " ".join(kws.map(func(k: String) -> String: return KW_SHORT.get(k, k)))
	return "%s S%d\n%d/%d\n%s" % [_unit_name(unit["id"]), int(unit["level"]),
		int(stats["atk"]) + int(unit["atk_bonus"]), int(stats["hp"]) + int(unit["hp_bonus"]), short]


func ability_text(a: Dictionary) -> String:
	var trig: String = TRIGGER_TEXT.get(a.get("trigger", ""), a.get("trigger", ""))
	if a.get("trigger", "") == "avenge":
		trig += " (%d)" % int(a.get("count", 1))
	var tgt: String = TARGET_TEXT.get(a.get("target", "self"), a.get("target", ""))
	var only := ""
	if a.get("only") is Dictionary and a["only"].has("color"):
		only = " (" + str(a["only"]["color"]) + ")"
	var when := ""
	if a.get("when") is Dictionary and a["when"].has("color"):
		when = " [" + str(a["when"]["color"]) + "]"
	var times := " %d×" % int(a["times"]) if int(a.get("times", 1)) > 1 else ""
	var what := ""
	match a.get("effect", ""):
		"buff":
			var parts: Array[String] = []
			if int(a.get("atk", 0)) != 0:
				parts.append("+%d A" % int(a["atk"]))
			if int(a.get("hp", 0)) != 0:
				parts.append("+%d L" % int(a["hp"]))
			if a.get("value_from", "") != "":
				parts.append("+A aus " + str(a["value_from"]))
			if a.get("keyword", "") != "":
				parts.append(KW_SHORT.get(a["keyword"], a["keyword"]))
			what = "%s%s: %s%s" % [tgt, only, ", ".join(parts), " (dauerhaft)" if a.get("permanent", false) else ""]
		"give_keyword":
			what = "%s%s bekommt %s" % [tgt, only, "zufälliges Schlüsselwort" if a.get("keyword") == "random" else KW_SHORT.get(a.get("keyword", ""), a.get("keyword", ""))]
		"remove_keyword":
			what = "%s verliert %s" % [tgt, ", ".join(a.get("keywords", []))]
		"summon":
			what = "beschwört %s" % ("Einheit mit Todesröcheln" if a.get("random", "") == "deathrattle" else _unit_name(a.get("token", "")))
		"damage":
			what = "%d%s Schaden an %s%s" % [int(a.get("value", 0)), " + " + str(a["value_from"]) if a.get("value_from", "") != "" else "", tgt, only]
		"destroy":
			what = "vernichtet " + tgt
		"attack_now":
			what = "greift sofort an"
		"trigger_ability":
			what = "löst %s von %s aus" % [TRIGGER_TEXT.get(a.get("ability_trigger", ""), ""), tgt]
		"gold":
			what = "+%d Gold" % int(a.get("value", 0))
		"free_reroll":
			what = "+%d Gratis-Würfe" % int(a.get("value", 0))
		_:
			what = str(a.get("effect", ""))
	return "%s%s: %s%s" % [trig, when, what, times]


func _unit_info(id: String, level: int, unit: Dictionary = {}) -> String:
	var def := rs.get_def(id)
	var stats := rs.level_stats(id, level)
	var atk := int(stats["atk"]) + int(unit.get("atk_bonus", 0))
	var hp := int(stats["hp"]) + int(unit.get("hp_bonus", 0))
	var kws: Array = stats.get("keywords", []) + unit.get("keywords", [])
	var lines: Array[String] = []
	var rarities: Array = rs.rules.get("rarities", [])
	var rarity := int(def.get("rarity", 0))
	lines.append("%s  %s  %s Gold  Stufe %d" % [def.get("name", id), rarities[rarity] if rarity < rarities.size() else "", def.get("cost", 0), level])
	lines.append("%d/%d  Farben: %s" % [atk, hp, ", ".join(def.get("colors", []))])
	if not kws.is_empty():
		lines.append(", ".join(kws.map(func(k: String) -> String: return KW_SHORT.get(k, k))))
	for p: String in stats.get("passives", []):
		lines.append(PASSIVE_TEXT.get(p, p))
	for a: Dictionary in stats.get("abilities", []):
		lines.append(ability_text(a))
	if not unit.is_empty() and not rs.is_token(id):
		lines.append("Verkauf: %d Gold" % rs.sell_value(id, level))
	var ref: Variant = def.get("ref")
	if ref is Dictionary:
		lines.append("Vorlage: %s (BG Stufe %s)" % [ref.get("bg_name", ""), ref.get("bg_tier", "")])
	return "\n".join(lines)


# --- Start ---

func _show_start() -> void:
	_clear()
	var meta: Dictionary = rs.section("meta")
	_header.text = "Inklite Workshop · Test"
	_body.add_child(_label("Regelsatz: %s (Version %s)\n%d Einheiten, %d Geisterteams als Gegner." % [
		meta.get("name", ""), meta.get("version", "?"), rs.units.size(), rs.ghosts.size()]))
	if rs.ghosts.is_empty():
		_body.add_child(_label("Noch keine Geisterteams: im Editor erst eine Simulation laufen lassen, sonst gewinnst du gegen leere Teams."))
	_body.add_child(_label("Kaufen: Angebot antippen, dann Kaufen oder auf einen freien Teamplatz tippen.\nUmstellen: Einheit antippen, dann Zielplatz antippen.\nTeam = obere 6 Plätze, Bank = untere 4."))
	_body.add_child(_button("Neuer Run, BG-Kampf", func() -> void: _new_run("bg")))
	_body.add_child(_button("Neuer Run, Raster-Kampf", func() -> void: _new_run("grid")))


func _new_run(combat_mode: String) -> void:
	mode = combat_mode
	run = WsRun.create(rs, int(Time.get_unix_time_from_system()) % 2147483647, combat_mode)
	run.trace = true
	_show_shop()


# --- Shop ---

func _show_shop() -> void:
	_clear()
	_refresh_shop()


func _refresh_shop() -> void:
	for child in _body.get_children():
		child.queue_free()
	_header.text = "Tag %d · Rang %d · %d Gold · %d Leben · %d Siege%s" % [
		run.day, run.rank(), run.gold, run.lives, run.wins, " · %d gratis" % run.free_rerolls if run.free_rerolls > 0 else ""]

	_body.add_child(_label("Shop%s" % (" (gesperrt)" if run.locked else ""), 11))
	var offers := _row()
	for i in run.offers.size():
		var offer: Variant = run.offers[i]
		if offer == null:
			offers.add_child(_card("", [], Vector2(60, 78), func() -> void: pass, false, true))
			continue
		var stats := rs.level_stats(offer["id"], 1)
		var affordable := run.gold >= int(offer["cost"])
		var text := "%s\n%d Gold\n%d/%d" % [_unit_name(offer["id"]), offer["cost"], stats["atk"], stats["hp"]]
		var idx := i
		offers.add_child(_card(text, rs.get_def(offer["id"]).get("colors", []), Vector2(60, 78),
			func() -> void: _tap("offer", idx), selected == {"kind": "offer", "index": i}, not affordable))
	_body.add_child(offers)

	var actions := _row()
	actions.add_child(_button("Würfeln (%d)" % run.reroll_cost(), func() -> void:
		run.reroll()
		_refresh_shop(), 0))
	actions.add_child(_button("Entsperren" if run.locked else "Sperren", func() -> void:
		run.toggle_lock()
		_refresh_shop(), 0))
	actions.add_child(_button("Kaufen", _buy_selected, 0))
	_body.add_child(actions)

	_body.add_child(_label("Team (%s)" % ("Reihe: Platz 1 bis 6 greifen von links nach rechts an" if mode == "bg" else "obere Reihe = vorne"), 11))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for j in run.team.size():
		grid.add_child(_slot_card("team", j))
	_body.add_child(grid)

	_body.add_child(_label("Bank", 11))
	var bench := _row()
	for j in run.bench.size():
		bench.add_child(_slot_card("bench", j))
	_body.add_child(bench)

	_info = _label(_selected_info(), 10)
	_info.custom_minimum_size = Vector2(0, 70)
	_body.add_child(_info)

	var bottom := _row()
	var sell := _button("Verkaufen", _sell_selected, 0)
	sell.disabled = not (selected.get("kind", "") in ["team", "bench"])
	bottom.add_child(sell)
	var fight := _button("Kampf!", _fight, 0)
	fight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(fight)
	_body.add_child(bottom)


func _slot_card(loc: String, index: int) -> Button:
	var unit: Variant = run.slots_of(loc)[index]
	var size := Vector2(100, 64) if loc == "team" else Vector2(72, 56)
	var is_sel: bool = selected == {"kind": loc, "index": index}
	if unit == null:
		var label := "Platz %d" % (index + 1) if loc == "team" else ""
		return _card(label, [], size, func() -> void: _tap(loc, index), is_sel, true)
	return _card(_owned_text(unit), rs.get_def(unit["id"]).get("colors", []), size, func() -> void: _tap(loc, index), is_sel)


func _selected_info() -> String:
	match selected.get("kind", ""):
		"offer":
			var offer: Variant = run.offers[selected["index"]]
			return _unit_info(offer["id"], 1) if offer != null else ""
		"team", "bench":
			var unit: Variant = run.slots_of(selected["kind"])[selected["index"]]
			return _unit_info(unit["id"], int(unit["level"]), unit) if unit != null else ""
	return "Tippe eine Einheit an, um ihre Werte zu sehen."


func _tap(kind: String, index: int) -> void:
	var sel_kind: String = selected.get("kind", "")
	if kind == "offer":
		selected = {} if selected == {"kind": kind, "index": index} else {"kind": kind, "index": index}
	elif sel_kind == "offer":
		var target := index if kind == "team" and run.team[index] == null else -1
		run.buy(selected["index"], target)
		selected = {}
	elif sel_kind in ["team", "bench"]:
		if selected == {"kind": kind, "index": index}:
			selected = {}
		else:
			run.move(sel_kind, selected["index"], kind, index)
			selected = {}
	elif run.slots_of(kind)[index] != null:
		selected = {"kind": kind, "index": index}
	_refresh_shop()


func _buy_selected() -> void:
	if selected.get("kind", "") == "offer":
		run.buy(selected["index"])
		selected = {}
	_refresh_shop()


func _sell_selected() -> void:
	if selected.get("kind", "") in ["team", "bench"]:
		run.sell(selected["kind"], selected["index"])
		selected = {}
	_refresh_shop()


func _fight() -> void:
	if run.team_units().is_empty():
		_info.text = "Stell mindestens eine Einheit ins Team."
		return
	var battle := run.fight()
	_show_battle(battle)


# --- Kampf ---

func _show_battle(battle: Dictionary) -> void:
	_clear()
	_skip = false
	_header.text = "Tag %d · Kampf gegen %s" % [battle["day"], battle.get("ghost_id", "")]
	var enemy_label := _label("Gegner", 11)
	var enemy_grid := GridContainer.new()
	var own_label := _label("Dein Team", 11)
	var own_grid := GridContainer.new()
	for g in [enemy_grid, own_grid]:
		g.columns = 3 if mode == "grid" else 4
		g.add_theme_constant_override("h_separation", 3)
		g.add_theme_constant_override("v_separation", 3)
	var log_label := _label("", 10)
	log_label.custom_minimum_size = Vector2(0, 64)
	var controls := _row()
	var faster := _button("Schneller", func() -> void: _speed = minf(_speed * 2.0, 8.0), 0)
	var skip := _button("Überspringen", func() -> void: _skip = true, 0)
	controls.add_child(faster)
	controls.add_child(skip)
	for n in [enemy_label, enemy_grid, own_label, own_grid, log_label, controls]:
		_body.add_child(n)
	_play(battle, [own_grid, enemy_grid], log_label, controls)


## Spielt die Ereignisliste ab. Ein Schritt endet vor dem nächsten Angriff.
func _play(battle: Dictionary, grids: Array, log_label: Label, controls: HBoxContainer) -> void:
	var events: Array = battle.get("events", [])
	var units := {}
	var lines: Array = [[], []]
	var cells: Array = [[], []]
	for side in 2:
		cells[side].resize(6)
	var log_lines: Array[String] = []
	var marks := {}
	if events.is_empty():
		log_label.text = "Keine Ereignisse."
	else:
		for u: Dictionary in events[0]["units"]:
			units[u["uid"]] = {"id": u["id"], "level": u["level"], "atk": u["atk"], "hp": u["hp"], "kw": u["keywords"].duplicate(), "side": u["side"]}
			_place_model(lines, cells, u["side"], int(u["pos"]), u["uid"])
		_draw_battle(grids, units, lines, cells, marks)
	for i in range(1, events.size()):
		var e: Dictionary = events[i]
		if e["ev"] == "attack" and not _skip:
			_draw_battle(grids, units, lines, cells, marks)
			log_label.text = "\n".join(log_lines.slice(maxi(log_lines.size() - 4, 0)))
			await get_tree().create_timer(0.55 / _speed).timeout
			if not is_inside_tree():
				return
			marks = {}
		match e["ev"]:
			"attack":
				marks = {e["uid"]: "attack", e["to"]: "target"}
				log_lines.append("%s greift %s an" % [_name_of(units, e["uid"]), _name_of(units, e["to"])])
			"damage":
				if units.has(e["uid"]):
					units[e["uid"]]["hp"] = e["hp"]
			"shield_lost":
				if units.has(e["uid"]):
					units[e["uid"]]["kw"].erase("divine_shield")
			"buff":
				if units.has(e["uid"]):
					units[e["uid"]]["atk"] = e["atk"]
					units[e["uid"]]["hp"] = e["hp"]
					units[e["uid"]]["kw"] = e.get("keywords", units[e["uid"]]["kw"])
			"keywords":
				if units.has(e["uid"]):
					units[e["uid"]]["kw"] = e["keywords"]
			"death":
				if units.has(e["uid"]):
					log_lines.append("%s stirbt" % _name_of(units, e["uid"]))
					_remove_model(lines, cells, units[e["uid"]]["side"], e["uid"])
			"summon", "reborn":
				units[e["uid"]] = {"id": e["id"], "level": e.get("level", 1), "atk": e["atk"], "hp": e["hp"], "kw": [], "side": e["side"]}
				_place_model(lines, cells, e["side"], int(e["pos"]), e["uid"])
				log_lines.append("%s %s" % [_name_of(units, e["uid"]), "kehrt zurück" if e["ev"] == "reborn" else "erscheint"])
			"ability":
				if units.has(e["uid"]):
					log_lines.append("%s: %s" % [_name_of(units, e["uid"]), TRIGGER_TEXT.get(e["trigger"], e["trigger"])])
	_draw_battle(grids, units, lines, cells, {})
	log_label.text = "\n".join(log_lines.slice(maxi(log_lines.size() - 4, 0)))

	for child in controls.get_children():
		child.queue_free()
	var result: String = battle["result"]
	var text: String = {"win": "Sieg!", "loss": "Niederlage", "draw": "Unentschieden"}.get(result, result)
	if battle.get("winner", 0) == WsCombat.DRAW and result != "draw":
		text = "Unentschieden, zählt als " + ("Sieg" if result == "win" else "Niederlage")
	if int(battle.get("lost_lives", 0)) > 0:
		text += " · -%d Leben" % battle["lost_lives"]
	_header.text = "Tag %d · %s · %d Angriffe" % [battle["day"], text, battle["attacks"]]
	controls.add_child(_button("Weiter", _after_battle, 0))


func _place_model(lines: Array, cells: Array, side: int, pos: int, uid: int) -> void:
	if mode == "grid":
		if pos >= 0 and pos < cells[side].size():
			cells[side][pos] = uid
	else:
		lines[side].insert(clampi(pos, 0, lines[side].size()), uid)


func _remove_model(lines: Array, cells: Array, side: int, uid: int) -> void:
	if mode == "grid":
		var i: int = cells[side].find(uid)
		if i >= 0:
			cells[side][i] = null
	else:
		lines[side].erase(uid)


func _name_of(units: Dictionary, uid: int) -> String:
	if not units.has(uid):
		return "?"
	return "%s%s" % [_unit_name(units[uid]["id"]), "" if units[uid]["side"] == 0 else " (G)"]


func _draw_battle(grids: Array, units: Dictionary, lines: Array, cells: Array, marks: Dictionary) -> void:
	for side in 2:
		var grid: GridContainer = grids[side]
		for child in grid.get_children():
			child.queue_free()
		var order: Array = cells[side] if mode == "grid" else lines[side]
		for uid: Variant in order:
			if uid == null:
				grid.add_child(_card("", [], Vector2(72, 58), func() -> void: pass, false, true))
				continue
			var u: Dictionary = units[uid]
			var kw := " ".join(u["kw"].map(func(k: String) -> String: return KW_SHORT.get(k, k)))
			var mark: String = marks.get(uid, "")
			var text := "%s%s\n%d/%d\n%s" % [">" if mark == "attack" else "", _unit_name(u["id"]), u["atk"], u["hp"], kw]
			grid.add_child(_card(text, rs.get_def(u["id"]).get("colors", []), Vector2(72, 58), func() -> void: pass, mark != ""))


func _after_battle() -> void:
	_speed = 1.0
	if run.is_over():
		_show_end()
	else:
		_show_shop()


# --- Ende ---

func _show_end() -> void:
	_clear()
	_header.text = "Run vorbei"
	var verdict := "10 Siege, gewonnen!" if run.is_victory() else "Keine Leben mehr."
	_body.add_child(_label("%s\n%d Siege, %d Niederlagen, %d Unentschieden in %d Tagen." % [verdict, run.wins, run.losses, run.draws, run.day - 1], 12))
	var names: Array[String] = []
	for unit: Dictionary in run.team_units():
		names.append("%s S%d" % [_unit_name(unit["id"]), int(unit["level"])])
	_body.add_child(_label("Letztes Team: " + ", ".join(names)))
	_body.add_child(_button("Neuer Run", _show_start))
