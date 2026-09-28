class_name AbilityText
extends RefCounted
## Übersetzt Fähigkeiten aus den Daten in kurze Sätze für die Anzeige, in der eingestellten Sprache.
## Monster-Fähigkeiten beziehen sich auf das Monster selbst, Team-Fähigkeiten (Trainer, Trinkets)
## auf einen auslösenden Verbündeten ("when") und optional eingeschränkte Ziele ("only").
## Mit rich = true sind Auslöser und Effekt für RichTextLabel eingefärbt.

const TEAM_TRIGGERS := ["on_attack", "on_hurt", "on_death"]
const COLOR_TRIGGER := "#ffd461"
const EFFECT_COLORS := {
	"poison": "#8fff6b", "shield": "#80ccff", "damage": "#ff7676",
	"buff_atk": "#ffd461", "buff_hp": "#ff9d9d", "gold": "#ffd461",
}


static func describe(ability: Variant, team: bool = false, rich: bool = false) -> String:
	if not (ability is Dictionary) or ability.is_empty():
		return Loc.t("ABILITY_NONE")
	var trigger: String = ability["trigger"]
	var trigger_text := Loc.t("TRIGGER_" + trigger)
	if team and TEAM_TRIGGERS.has(trigger):
		trigger_text = Loc.t("TEAM_" + trigger, {"who": _who(ability.get("when"))})
	var effect: String = ability["effect"]
	var value := int(ability.get("value", 0))
	var target := Loc.t("TARGET_" + String(ability.get("target", "")))
	if ability.get("only") is Dictionary:
		target = Loc.t("ONLY", {"target": target, "what": _only(ability["only"])})
	var sentence := Loc.t("EFFECT_" + effect, {"value": value, "target": target})
	if trigger == "round_end" and effect != "gold":
		sentence = Loc.t("PERMANENT", {"x": sentence})
	if rich:
		trigger_text = "[color=%s]%s[/color]" % [COLOR_TRIGGER, trigger_text]
		sentence = "[color=%s]%s[/color]" % [EFFECT_COLORS.get(effect, "#ffffff"), sentence]
	return Loc.t("ABILITY_SENTENCE", {"trigger": trigger_text, "effect": sentence})


## Schlüsselwörter einer Fähigkeit für die Erklärungen unter der Info-Karte (KW_<name>).
static func keywords(ability: Variant) -> Array[String]:
	var result: Array[String] = []
	if ability is Dictionary and not ability.is_empty():
		result.append(ability["trigger"])
		result.append(ability["effect"])
	return result


static func round_end_line(entry: Dictionary, item_name: String, monster_name: String) -> String:
	var key: String = {"gold": "ROUND_END_GOLD", "buff_atk": "ROUND_END_ATK"}.get(entry["effect"], "ROUND_END_HP")
	return Loc.t(key, {"item": item_name, "n": entry["value"], "monster": monster_name})


static func _who(filter: Variant) -> String:
	if filter is Dictionary and filter.has("type"):
		return Loc.t("WHO_TYPE", {"type": Loc.type_name(filter["type"])})
	if filter is Dictionary and filter.has("row"):
		return Loc.t("WHO_ROW", {"row": _row(filter["row"])})
	return Loc.t("WHO_ANY")


static func _only(filter: Dictionary) -> String:
	if filter.has("type"):
		return Loc.type_name(filter["type"])
	return Loc.t("ONLY_ROW", {"row": _row(filter.get("row", 0))})


static func _row(row: Variant) -> String:
	return Loc.t("ROW_%d" % clampi(int(row), 0, 2))
