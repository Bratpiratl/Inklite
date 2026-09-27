class_name GameData
extends RefCounted
## Lädt die JSON-Dateien aus data/. Alle Spielwerte kommen von hier, nie aus dem Code.

const MONSTERS_PATH := "res://data/monsters.json"
const BALANCE_PATH := "res://data/balance.json"


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Datei fehlt: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("Kein gültiges JSON: %s" % path)
	return parsed


static func load_balance() -> Dictionary:
	var data: Variant = load_json(BALANCE_PATH)
	return data if data is Dictionary else {}
