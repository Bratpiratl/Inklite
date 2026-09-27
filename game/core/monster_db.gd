class_name MonsterDb
extends RefCounted
## Nachschlagewerk für Monster-Definitionen aus data/monsters.json.

var _by_id: Dictionary = {}
var _ids: Array[String] = []


static func from_file(path: String = GameData.MONSTERS_PATH) -> MonsterDb:
	var data: Variant = GameData.load_json(path)
	return from_array(data if data is Array else [])


static func from_array(defs: Array) -> MonsterDb:
	var db := MonsterDb.new()
	for def: Dictionary in defs:
		var id: String = def["id"]
		db._by_id[id] = def
		db._ids.append(id)
	return db


func ids() -> Array[String]:
	return _ids.duplicate()


func has(id: String) -> bool:
	return _by_id.has(id)


func get_def(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Werte einer Stufe (1-basiert): {"hp", "atk", "ability"}.
func level_stats(id: String, level: int) -> Dictionary:
	var levels: Array = get_def(id).get("levels", [])
	if level < 1 or level > levels.size():
		push_error("Unbekannte Stufe %d für %s" % [level, id])
		return {}
	return levels[level - 1]
