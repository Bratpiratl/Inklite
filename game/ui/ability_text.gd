class_name AbilityText
extends RefCounted
## Übersetzt Fähigkeiten aus den Daten in kurze deutsche Sätze für die Anzeige.
## Monster-Fähigkeiten beziehen sich auf das Monster selbst, Team-Fähigkeiten (Trainer, Trinkets)
## auf einen auslösenden Verbündeten ("when") und optional eingeschränkte Ziele ("only").

const TRIGGERS := {
	"battle_start": "Kampfstart", "on_attack": "Beim Angriff",
	"on_hurt": "Wenn getroffen", "on_death": "Beim Tod", "round_end": "Rundenende",
}
const TEAM_TRIGGERS := {
	"on_attack": "Wenn ein %s angreift", "on_hurt": "Wenn ein %s getroffen wird", "on_death": "Wenn ein %s stirbt",
}
const EFFECTS := {
	"poison": "%d Gift auf %s", "shield": "%d Schild für %s", "damage": "%d Schaden an %s",
	"buff_atk": "+%d Angriff für %s", "buff_hp": "+%d HP für %s",
}
const TARGETS := {
	"self": "sich", "target": "das Ziel", "attacker": "den Angreifer",
	"allies_all": "alle Verbündeten", "allies_row": "die eigene Reihe", "allies_front": "die vordere Reihe",
	"ally_random": "einen zufälligen Verbündeten",
	"enemies_all": "alle Gegner", "enemies_front": "die vorderste Gegnerreihe",
	"enemy_front": "den vordersten Gegner", "enemy_random": "einen zufälligen Gegner",
}
const ROWS := ["vorderen", "mittleren", "hinteren"]


static func describe(ability: Variant, team: bool = false) -> String:
	if not (ability is Dictionary) or ability.is_empty():
		return "Keine Fähigkeit."
	var trigger: String = ability["trigger"]
	var trigger_text: String = TRIGGERS.get(trigger, trigger)
	if team and TEAM_TRIGGERS.has(trigger):
		trigger_text = TEAM_TRIGGERS[trigger] % _who(ability.get("when"))
	var value := int(ability.get("value", 0))
	var sentence: String
	if ability["effect"] == "gold":
		sentence = "+%d Gold in der nächsten Runde" % value
	else:
		var target: String = TARGETS.get(ability.get("target", ""), ability.get("target", ""))
		if ability.get("only") is Dictionary:
			target += " (nur %s)" % _only(ability["only"])
		sentence = EFFECTS.get(ability["effect"], "%d %s") % [value, target]
		if trigger == "round_end":
			sentence = "dauerhaft " + sentence
	return "%s: %s." % [trigger_text, sentence]


static func unit_line(db: MonsterDb, unit: Dictionary) -> String:
	var def := db.get_def(unit["id"])
	var stats := db.level_stats(unit["id"], unit["level"])
	var atk := int(stats["atk"]) + int(unit.get("atk_bonus", 0))
	var hp := int(stats["hp"]) + int(unit.get("hp_bonus", 0))
	return "%s (%s, Stufe %d)\n%d Angriff, %d HP. %s" % [
		def["name"], String(def["type"]).capitalize(), unit["level"], atk, hp, describe(stats.get("ability"))]


static func item_line(def: Dictionary) -> String:
	return "%s\n%s" % [def["name"], describe(def.get("ability"), true)]


## Kurzform für aufsteigende Texte im Kampf, z. B. "+1 Angriff".
static func round_end_line(entry: Dictionary, item_name: String, monster_name: String) -> String:
	match entry["effect"]:
		"gold":
			return "%s: +%d Gold nächste Runde" % [item_name, entry["value"]]
		"buff_atk":
			return "%s: +%d Angriff für %s" % [item_name, entry["value"], monster_name]
		_:
			return "%s: +%d HP für %s" % [item_name, entry["value"], monster_name]


static func _who(filter: Variant) -> String:
	if filter is Dictionary and filter.has("type"):
		return "%s-Monster" % String(filter["type"]).capitalize()
	if filter is Dictionary and filter.has("row"):
		return "Monster in der %s Reihe" % ROWS[clampi(int(filter["row"]), 0, ROWS.size() - 1)]
	return "Verbündeter"


static func _only(filter: Dictionary) -> String:
	if filter.has("type"):
		return String(filter["type"]).capitalize()
	return "%s Reihe" % ROWS[clampi(int(filter.get("row", 0)), 0, ROWS.size() - 1)]
