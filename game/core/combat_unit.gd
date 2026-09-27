class_name CombatUnit
extends RefCounted
## Zustand eines Monsters während eines Kampfes. Wird pro Kampf neu erzeugt.

var side: int
var slot: int
var id: String
var type: String
var level: int
var hp: int
var max_hp: int
var atk: int
var shield := 0
var poison := 0
var alive := true
var ability: Dictionary = {}


@warning_ignore("integer_division")
func row() -> int:
	return slot / CombatSim.COLS


func col() -> int:
	return slot % CombatSim.COLS


func snapshot() -> Dictionary:
	return {"side": side, "slot": slot, "id": id, "level": level, "hp": hp, "atk": atk}
