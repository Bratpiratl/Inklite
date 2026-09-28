class_name DebugPanel
extends Control
## Debug-Menü: Telemetrie echter Runs exportieren oder löschen.

const EXPORT_NAME := "inklite-telemetrie-%s.jsonl"

@onready var _status: Label = %StatusLabel


func _ready() -> void:
	%ExportButton.pressed.connect(_on_export)
	%ClearButton.pressed.connect(_on_clear)
	%CloseButton.pressed.connect(hide)
	visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_node_ready() or not visible:
		return
	var info := LogStore.summary()
	_status.text = "Version %s\nTelemetrie: %d Ereignisse aus %d abgeschlossenen Runs.\nDie Daten bleiben auf diesem Gerät." % [
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
		_status.text = "Datei liegt unter:\n%s" % ProjectSettings.globalize_path(LogStore.PATH)


func _on_clear() -> void:
	LogStore.clear()
	_refresh()
	_status.text += "\nGelöscht."
