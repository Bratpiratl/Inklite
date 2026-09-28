extends Node
## Autoload: Einstellungen des Spielers (Lautstärken, Kampftempo), gespeichert in user://settings.json.

signal changed

const PATH := "user://settings.json"

var music_volume := 0.6
var sfx_volume := 0.8
var speed_index := 0


func _ready() -> void:
	var data: Variant = GameData.load_json(PATH) if FileAccess.file_exists(PATH) else null
	if data is Dictionary:
		music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
		speed_index = int(data.get("speed_index", speed_index))


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"music_volume": music_volume, "sfx_volume": sfx_volume, "speed_index": speed_index}))
		file.close()
	changed.emit()
