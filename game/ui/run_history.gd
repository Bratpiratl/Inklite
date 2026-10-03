class_name RunHistory
extends RefCounted
## Abgeschlossene Runs in user://history.json, neueste zuerst, höchstens MAX_ENTRIES.

const PATH := "user://history.json"
const WS_PATH := "user://ws_history.json"
const MAX_ENTRIES := 50


static func add(run: RunState) -> void:
	var entry := {
		"date": Time.get_datetime_string_from_system(false, true), "trainer": run.trainer,
		"trinkets": run.trinkets.duplicate(), "wins": run.wins, "lives": run.lives,
		"round": run.round_number, "victory": run.is_victory(),
		"team": run.team().map(func(u: Dictionary) -> String: return RunLogger.unit_tag(u)),
	}
	var all := entries()
	all.push_front(entry)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all.slice(0, MAX_ENTRIES)))
		file.close()


## Run im neuen Modus (Workshop-Regelsatz): {"date", "difficulty", "wins", "day", "victory", "team": [ids]}.
static func add_ws(entry: Dictionary) -> void:
	var all := ws_entries()
	entry["date"] = Time.get_datetime_string_from_system(false, true)
	all.push_front(entry)
	var file := FileAccess.open(WS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all.slice(0, MAX_ENTRIES)))
		file.close()


static func ws_entries() -> Array:
	var data: Variant = GameData.load_json(WS_PATH) if FileAccess.file_exists(WS_PATH) else null
	return data if data is Array else []


static func entries() -> Array:
	var data: Variant = GameData.load_json(PATH) if FileAccess.file_exists(PATH) else null
	return data if data is Array else []
