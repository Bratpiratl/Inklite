extends Control
## Einstellungen: Musik, Effekte, Kampftempo und Debug (Telemetrie exportieren oder löschen).

const EXPORT_NAME := "inklite-telemetrie-%s.jsonl"

@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _speed_1: Button = %Speed1Button
@onready var _speed_2: Button = %Speed2Button
@onready var _status: Label = %DebugStatus
@onready var _lang_de: Button = %LangDeButton
@onready var _lang_en: Button = %LangEnButton


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
	group.pressed.connect(func(_b: BaseButton) -> void: _highlight([_speed_1, _speed_2]))
	_highlight([_speed_1, _speed_2])
	_speed_1.pressed.connect(func() -> void: Prefs.set_value("speed_index", 0))
	_speed_2.pressed.connect(func() -> void: Prefs.set_value("speed_index", 1))
	var languages := ButtonGroup.new()
	for button: Button in [_lang_de, _lang_en]:
		button.toggle_mode = true
		button.button_group = languages
	(_lang_de if Prefs.language == "de" else _lang_en).button_pressed = true
	_highlight([_lang_de, _lang_en])
	_lang_de.pressed.connect(_set_language.bind("de"))
	_lang_en.pressed.connect(_set_language.bind("en"))
	%TipsButton.pressed.connect(func() -> void:
		Prefs.reset_tips()
		%TipsStatus.text = Loc.t("SETTINGS_TIPS_DONE"))
	%ExportButton.pressed.connect(_on_export)
	%ClearButton.pressed.connect(_on_clear)
	%BackButton.pressed.connect(func() -> void: Session.goto(Session.TITLE_SCENE))
	_refresh_debug()
	Audio.play_music("menu")


## Die gewählte Option bekommt den hellen Button, damit man sie auf einen Blick sieht.
func _highlight(buttons: Array) -> void:
	for button: Button in buttons:
		button.theme_type_variation = &"PrimaryButton" if button.button_pressed else &""


## Sprache wechseln und die Szene neu laden, damit alle Texte aus dem Code neu gesetzt werden.
func _set_language(language: String) -> void:
	if Prefs.language != language:
		Prefs.set_value("language", language)
		Session.goto(Session.SETTINGS_SCENE)


func _refresh_debug() -> void:
	var info := LogStore.summary()
	_status.text = Loc.t("DEBUG_STATUS", {"v": RunLogger.version(), "events": info["events"], "runs": info["runs"]})


func _on_export() -> void:
	var text := LogStore.read_all()
	if text.is_empty():
		_status.text = Loc.t("DEBUG_EMPTY")
		return
	var file_name := EXPORT_NAME % Time.get_datetime_string_from_system().replace(":", "-")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/x-ndjson")
		_status.text = Loc.t("DEBUG_EXPORTED", {"file": file_name})
	else:
		_status.text = Loc.t("DEBUG_PATH", {"path": ProjectSettings.globalize_path(LogStore.PATH)})


func _on_clear() -> void:
	LogStore.clear()
	_refresh_debug()
