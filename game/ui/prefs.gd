extends Node
## Autoload: Einstellungen des Spielers (Lautstärken, Kampftempo, Sprache, gesehene Tipps),
## gespeichert in user://settings.json.

signal changed

const PATH := "user://settings.json"

var music_volume := 0.6
var sfx_volume := 0.8
var speed_index := 0
var language := ""
var vibration := true
var seen_tips: Array = []


func _ready() -> void:
	var data: Variant = GameData.load_json(PATH) if FileAccess.file_exists(PATH) else null
	if data is Dictionary:
		music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
		speed_index = int(data.get("speed_index", speed_index))
		language = String(data.get("language", ""))
		vibration = bool(data.get("vibration", true))
		seen_tips = data.get("seen_tips", [])
	if not Loc.LANGUAGES.has(language):
		language = Loc.default_language()
	TranslationServer.set_locale(language)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"music_volume": music_volume, "sfx_volume": sfx_volume, "speed_index": speed_index,
			"language": language, "seen_tips": seen_tips, "vibration": vibration,
		}))
		file.close()
	if key == "language":
		TranslationServer.set_locale(language)
	changed.emit()


## Einmalige Tipps: true, wenn der Tipp noch nicht bestätigt wurde.
func tip_pending(tip: String) -> bool:
	return not seen_tips.has(tip)


func mark_tip_seen(tip: String) -> void:
	if not seen_tips.has(tip):
		set_value("seen_tips", seen_tips + [tip])


func reset_tips() -> void:
	set_value("seen_tips", [])
