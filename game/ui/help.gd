extends Control
## Anleitung: Regeln in kurzen Abschnitten plus alle Schlüsselwörter. Im neuen Modus mit Zahlen aus dem
## Workshop-Regelsatz (data/workshop/), im klassischen Modus aus balance.json.

const SECTIONS := ["GOAL", "ROUND", "GRID", "MERGE", "SHOP", "ITEMS", "TIPS"]
const KEYWORDS := ["front", "level", "battle_start", "on_attack", "on_hurt", "on_death", "round_end",
	"poison", "shield", "damage", "buff_atk", "buff_hp", "gold"]
const COLOR_HEADING := Color(0.92549, 0.827451, 0.576471)
const COLOR_TERM := "#ffd461"
const WS_SECTIONS := ["GOAL", "DAY", "GOLD", "SHOP", "TEAM", "MERGE", "COMBAT", "COLORS", "DIFFICULTY"]
const WS_KEYWORDS := ["taunt", "divine_shield", "reborn", "windfury", "venomous", "cleave", "stealth"]

@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.help_return))
	Audio.play_music("menu")
	if not Session.classic_mode and FileAccess.file_exists(Session.WORKSHOP_DATA):
		_show_workshop_rules()
		return
	var rules: Dictionary = Session.balance.get("run", {})
	var args := {"wins": rules.get("wins_to_victory", 0), "lives": rules.get("start_lives", 0)}
	for section: String in SECTIONS:
		_add_heading(Loc.t("HELP_%s_T" % section))
		_add_text(Loc.t("HELP_" + section, args))
	_add_heading(Loc.t("HELP_KEYWORDS_T"))
	var lines: Array[String] = []
	for keyword: String in KEYWORDS:
		var text := Loc.t("KW_" + keyword)
		var split := text.find(":")
		lines.append("[color=%s]%s[/color]%s" % [COLOR_TERM, text.substr(0, split), text.substr(split)])
	_add_text("\n\n".join(lines))


## Neuer Modus: Abschnitte WSHELP_*, Zahlen aus ruleset.json und units.json.
func _show_workshop_rules() -> void:
	var rules: Dictionary = GameData.load_json(Session.WORKSHOP_DATA)
	var units: Variant = GameData.load_json(WsRuleset.GAME_DATA_DIR + "/units.json")
	var run: Dictionary = rules.get("run", {})
	var eco: Dictionary = rules.get("economy", {})
	var board: Dictionary = rules.get("board", {})
	var costs: Array = (units.get("units", []) if units is Dictionary else []).map(func(u: Dictionary) -> int: return int(u.get("cost", 0)))
	var merge: Array = board.get("merge_counts", [3, 2])
	var scale: Array = board.get("level_scale", [1, 2, 3])
	var levels: Array = run.get("difficulties", [])
	var args := {
		"wins": run.get("wins_to_victory", 10), "lives": run.get("start_lives", 10),
		"losses": _loss_text(run.get("life_loss_by_day", [1])),
		"second": Loc.t("WS_SECOND_CHANCE") if run.get("second_chance", false) else "",
		"gold": (eco.get("income_by_day", [0]) as Array)[0], "reroll": eco.get("reroll_cost", 0),
		"keep": Loc.t("WS_GOLD_KEEP" if eco.get("gold_carries_over", true) else "WS_GOLD_LOSE"),
		"min": costs.min() if not costs.is_empty() else 0, "max": costs.max() if not costs.is_empty() else 0,
		"team": board.get("team_slots", 6), "bench": board.get("bench_slots", 4),
		"merge1": merge[0] if merge.size() > 0 else 3, "merge2": merge[1] if merge.size() > 1 else 2,
		"scale2": scale[1] if scale.size() > 1 else 2, "scale3": scale[2] if scale.size() > 2 else 3,
		"levels": ", ".join(levels.map(func(d: Dictionary) -> String: return Loc.t("WS_DIFF_NAME_" + str(d["id"])) if Loc.t("WS_DIFF_NAME_" + str(d["id"])) != "WS_DIFF_NAME_" + str(d["id"]) else str(d.get("name", d["id"])))),
	}
	for section: String in WS_SECTIONS:
		_add_heading(Loc.t("WSHELP_%s_T" % section))
		_add_text(Loc.t("WSHELP_" + section, args))
	_add_heading(Loc.t("HELP_KEYWORDS_T"))
	var lines: Array[String] = []
	for keyword: String in WS_KEYWORDS:
		var text := Loc.t("WS_KWL_" + keyword)
		var split := text.find(":")
		lines.append("[color=%s]%s[/color]%s" % [COLOR_TERM, text.substr(0, split), text.substr(split)])
	_add_text("\n\n".join(lines))


## [1, 1, 2, 2, 3] -> "Tag 1 bis 2 je 1, Tag 3 bis 4 je 2, ab Tag 5 je 3"
func _loss_text(losses: Array) -> String:
	var parts: Array[String] = []
	var start := 0
	for i in losses.size():
		var last := i == losses.size() - 1
		if not last and losses[i + 1] == losses[i]:
			continue
		var args := {"a": start + 1, "b": i + 1, "n": losses[i]}
		if last:
			parts.append(Loc.t("WSHELP_LOSS_FROM", args))
		elif i == start:
			parts.append(Loc.t("WSHELP_LOSS_ONE", args))
		else:
			parts.append(Loc.t("WSHELP_LOSS_RANGE", args))
		start = i + 1
	return ", ".join(parts)


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_HEADING)
	label.add_theme_font_size_override("font_size", 16)
	_content.add_child(label)


func _add_text(bbcode: String) -> void:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.mouse_filter = Control.MOUSE_FILTER_PASS
	rich.add_theme_font_size_override("normal_font_size", 14)
	rich.add_theme_color_override("default_color", Color(0.878431, 0.858824, 0.929412))
	rich.text = bbcode
	_content.add_child(rich)
