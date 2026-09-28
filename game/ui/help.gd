extends Control
## Anleitung: Regeln in kurzen Abschnitten plus alle Schlüsselwörter. Die Zahlen kommen aus balance.json.

const SECTIONS := ["GOAL", "ROUND", "GRID", "MERGE", "ITEMS", "TIPS"]
const KEYWORDS := ["front", "level", "battle_start", "on_attack", "on_hurt", "on_death", "round_end",
	"poison", "shield", "damage", "buff_atk", "buff_hp", "gold"]
const COLOR_HEADING := Color(0.92549, 0.827451, 0.576471)
const COLOR_TERM := "#ffd461"

@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.help_return))
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
	Audio.play_music("menu")


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
