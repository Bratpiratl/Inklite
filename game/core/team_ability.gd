class_name TeamAbility
extends RefCounted
## Fähigkeiten von Trainern und Trinkets. Gleiches Format wie Monster-Fähigkeiten
## (trigger, effect, target, value) plus zwei optionale Filter:
##   "when": welcher eigene Verbündete den Auslöser auslösen darf, z. B. {"type": "moos"} oder {"row": 0}
##   "only": welche Ziele in Frage kommen, gleiche Schlüssel
## Kampf-Auslöser laufen in CombatSim, round_end läuft im Shop (RunState).

const TRIGGER_ROUND_END := "round_end"
const EFFECT_GOLD := "gold"
const SHOP_EFFECTS := [EFFECT_GOLD, Effects.BUFF_ATK, Effects.BUFF_HP]
const SHOP_TARGETS := ["allies_all", "allies_front", "ally_random"]


## Leerer Filter passt immer. Unbekannte Schlüssel passen nie, damit Tippfehler in den Daten auffallen.
static func matches(filter: Variant, type: String, row: int) -> bool:
	if not (filter is Dictionary):
		return true
	for key: String in filter:
		match key:
			"type":
				if filter[key] != type:
					return false
			"row":
				if int(filter[key]) != row:
					return false
			_:
				return false
	return true


## Fähigkeit mit Herkunfts-ID, so wie CombatSim und RunState sie erwarten.
static func tagged(ability: Dictionary, id: String) -> Dictionary:
	var result := ability.duplicate(true)
	result["id"] = id
	return result
