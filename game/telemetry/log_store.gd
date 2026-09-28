class_name LogStore
extends RefCounted
## Lokale Ablage der Telemetrie echter Runs (user://telemetry.jsonl). Bleibt auf dem Gerät,
## bis jemand sie im Debug-Menü exportiert.

const PATH := "user://telemetry.jsonl"
const ROTATED_PATH := "user://telemetry.old.jsonl"
const MAX_BYTES := 5 * 1024 * 1024


static func append(line: Dictionary) -> void:
	var file: FileAccess
	if FileAccess.file_exists(PATH):
		file = FileAccess.open(PATH, FileAccess.READ_WRITE)
		if file != null and file.get_length() > MAX_BYTES:
			file.close()
			DirAccess.rename_absolute(PATH, ROTATED_PATH)
			file = FileAccess.open(PATH, FileAccess.WRITE)
	else:
		file = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Telemetrie nicht schreibbar: %s" % FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(line))
	file.close()


static func read_all() -> String:
	return FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""


## Anzahl Ereignisse und abgeschlossener Runs.
static func summary() -> Dictionary:
	var text := read_all()
	var lines := text.split("\n", false)
	return {"events": lines.size(), "runs": text.count("\"ev\":\"run_end\"")}


static func clear() -> void:
	for path in [PATH, ROTATED_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
