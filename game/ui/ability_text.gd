class_name AbilityText
extends RefCounted
## Übersetzt Fähigkeiten aus den Daten in kurze deutsche Sätze für die Anzeige.

const TRIGGERS := {
	"battle_start": "Kampfstart", "on_attack": "Beim Angriff",
	"on_hurt": "Wenn getroffen", "on_death": "Beim Tod",
}
const EFFECTS := {"poison": "%d Gift auf %s", "shield": "%d Schild für %s", "damage": "%d Schaden an %s"}
const TARGETS := {
	"self": "sich", "target": "das Ziel", "attacker": "den Angreifer",
	"allies_all": "alle Verbündeten", "allies_row": "die eigene Reihe",
	"enemies_all": "alle Gegner", "enemies_front": "die vorderste Gegnerreihe",
	"enemy_front": "den vordersten Gegner", "enemy_random": "einen zufälligen Gegner",
}


static func describe(ability: Variant) -> String:
	if not (ability is Dictionary) or ability.is_empty():
		return "Keine Fähigkeit."
	var effect: String = EFFECTS.get(ability["effect"], "%d %s")
	var sentence := effect % [int(ability["value"]), TARGETS.get(ability["target"], ability["target"])]
	return "%s: %s." % [TRIGGERS.get(ability["trigger"], ability["trigger"]), sentence]


static func unit_line(db: MonsterDb, id: String, level: int) -> String:
	var def := db.get_def(id)
	var stats := db.level_stats(id, level)
	return "%s (%s, Stufe %d)\n%d Angriff, %d HP. %s" % [
		def["name"], String(def["type"]).capitalize(), level,
		stats["atk"], stats["hp"], describe(stats.get("ability"))]
