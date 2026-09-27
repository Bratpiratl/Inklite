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
	return normalize_ints(parsed)


## JSON kennt nur Float. Ganzzahlige Werte werden zu int, damit Anzeige ("3" statt "3.0")
## und Vergleiche stimmen. Echte Kommazahlen bleiben Float.
static func normalize_ints(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 9.0e15:
		return int(value)
	if value is Array:
		return value.map(normalize_ints)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = normalize_ints(value[key])
		return result
	return value


static func load_balance() -> Dictionary:
	var data: Variant = load_json(BALANCE_PATH)
	return data if data is Dictionary else {}
