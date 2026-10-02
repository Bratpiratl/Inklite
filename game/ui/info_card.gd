class_name InfoCard
extends PanelContainer
## Info-Karte an festem Platz: Bild, Name, Werte, Fähigkeit mit farbigen Schlüsselwörtern und kurzen
## Erklärungen dazu. Optional eine Aktion (Kaufen, Verkaufen, Verstanden). Tippen öffnet, das X
## oder ein Tipp daneben schließt, nichts verschwindet von allein.

signal action_pressed
signal secondary_pressed
signal closed

const SPRITE_ROOT := "res://assets/sprites/"
const COLOR_ATK := "#ffd461"
const COLOR_HP := "#ff7676"
const COLOR_TERM := "#e0dbed"

@onready var _icon: TextureRect = %CardIcon
@onready var _title: Label = %CardTitle
@onready var _sub: Label = %CardSub
@onready var _body: RichTextLabel = %CardBody
@onready var _glossary: RichTextLabel = %CardGlossary
@onready var _note: Label = %CardNote
@onready var _action: Button = %CardAction
@onready var _secondary: Button = %CardSecondary


func _ready() -> void:
	%CardClose.pressed.connect(close)
	_action.pressed.connect(action_pressed.emit)
	_secondary.pressed.connect(secondary_pressed.emit)
	hide()


## unit: {"id", "level", optional "atk_bonus", "hp_bonus"}. live: aktuelle Kampfwerte
## {"atk", "hp", "shield", "poison"}, sonst gelten die Grundwerte plus Bonus.
func show_monster(unit: Dictionary, db: MonsterDb, live: Dictionary = {}) -> void:
	var id: String = unit["id"]
	var level := int(unit.get("level", 1))
	var def := db.get_def(id)
	var stats := db.level_stats(id, level)
	var atk := int(live.get("atk", int(stats["atk"]) + int(unit.get("atk_bonus", 0))))
	var hp := int(live.get("hp", int(stats["hp"]) + int(unit.get("hp_bonus", 0))))
	_set_header(load(SPRITE_ROOT + def["sprite"]), Loc.monster(id), Loc.t("CARD_SUB_MONSTER", {
		"type": Loc.type_name(def["type"]), "level": level, "rarity": def["rarity"]}))
	var lines: Array[String] = [Loc.t("CARD_STATS", {
		"atk": "[color=%s]%d[/color]" % [COLOR_ATK, atk], "hp": "[color=%s]%d[/color]" % [COLOR_HP, hp]})]
	if not live.is_empty():
		lines.append(Loc.t("CARD_STATUS", {"shield": live.get("shield", 0), "poison": live.get("poison", 0)}))
	elif int(unit.get("atk_bonus", 0)) != 0 or int(unit.get("hp_bonus", 0)) != 0:
		lines.append(Loc.t("CARD_BONUS", {"atk": unit.get("atk_bonus", 0), "hp": unit.get("hp_bonus", 0)}))
	lines.append(AbilityText.describe(stats.get("ability"), false, true))
	_body.text = "\n".join(lines)
	var terms := AbilityText.keywords(stats.get("ability"))
	if level > 1:
		terms.append("level")
	_set_glossary(terms)
	_finish()


func show_item(id: String, def: Dictionary, is_trainer: bool) -> void:
	_set_header(load(SPRITE_ROOT + def["sprite"]), Loc.item(id), Loc.t("CARD_TRAINER" if is_trainer else "CARD_TRINKET"))
	_body.text = AbilityText.describe(def.get("ability"), true, true)
	_set_glossary(AbilityText.keywords(def.get("ability")))
	_finish()


func show_text(title: String, body: String, icon: Texture2D = null) -> void:
	_set_header(icon, title, "")
	_body.text = body
	_set_glossary([])
	_finish()


func set_action(text: String, enabled: bool = true) -> void:
	_action.text = text
	_action.disabled = not enabled
	_action.visible = true


func set_secondary(text: String) -> void:
	_secondary.text = text
	_secondary.visible = true


func set_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""


func close() -> void:
	if visible:
		hide()
		closed.emit()


func _set_header(icon: Texture2D, title: String, sub: String) -> void:
	_icon.texture = icon
	_icon.visible = icon != null
	_title.text = title
	_sub.text = sub
	_sub.visible = sub != ""


## Erklärung je Schlüsselwort, der Begriff vor dem Doppelpunkt hervorgehoben.
func _set_glossary(terms: Array[String]) -> void:
	var lines: Array[String] = []
	for term in terms:
		var text := Loc.t("KW_" + term)
		if text == "KW_" + term:
			continue
		var split := text.find(":")
		if split > 0:
			text = "[color=%s]%s[/color]%s" % [COLOR_TERM, text.substr(0, split), text.substr(split)]
		lines.append(text)
	_glossary.text = "\n".join(lines)
	_glossary.visible = not lines.is_empty()


## Neue Inhalte starten ohne Aktion und Hinweis, der Aufrufer setzt sie danach.
func _finish() -> void:
	_action.visible = false
	_secondary.visible = false
	_note.visible = false
	show()
