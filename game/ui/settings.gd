extends Control
## Einstellungen: Musik, Effekte, Kampftempo und Debug (Telemetrie exportieren oder löschen).

const EXPORT_NAME := "inklite-telemetrie-%s.jsonl"

@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _speed_1: Button = %Speed1Button
@onready var _speed_2: Button = %Speed2Button
@onready var _status: Label = %DebugStatus


func _ready() -> void:
	_music.value = Prefs.music_volume
	_sfx.value = Prefs.sfx_volume
	_music.value_changed.connect(func(v: float) -> void: Prefs.set_value("music_volume", v))
	_sfx.value_changed.connect(func(v: float) -> void: Prefs.set_value("sfx_volume", v))
	_sfx.drag_ended.connect(func(_changed: bool) -> void: Audio.play("buy"))
	var group := ButtonGroup.new()
	for button: Button in [_speed_1, _speed_2]:
		button.toggle_mode = true
		button.button_group = group
	(_speed_1 if Prefs.speed_index == 0 else _speed_2).button_pressed = true
	_speed_1.pressed.connect(func() -> void: Prefs.set_value("speed_index", 0))
	_speed_2.pressed.connect(func() -> void: Prefs.set_value("speed_index", 1))
	%ExportButton.pressed.connect(_on_export)
	%ClearButton.pressed.connect(_on_clear)
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.TITLE_SCENE))
	_refresh_debug()
	Audio.play_music("menu")


func _refresh_debug() -> void:
	var info := LogStore.summary()
	_status.text = "Version %s. Telemetrie: %d Ereignisse aus %d fertigen Runs. Bleibt auf diesem Gerät." % [
		RunLogger.version(), info["events"], info["runs"]]


func _on_export() -> void:
	var text := LogStore.read_all()
	if text.is_empty():
		_status.text = "Noch keine Telemetrie vorhanden."
		return
	var file_name := EXPORT_NAME % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/x-ndjson")
		_status.text = "Export gestartet: %s" % file_name
	else:
		_status.text = "Datei liegt unter %s" % ProjectSettings.globalize_path(LogStore.PATH)


func _on_clear() -> void:
	LogStore.clear()
	_refresh_debug()
