extends GdUnitTestSuite
## Übersetzungen: vollständig, gleiche Platzhalter in allen Sprachen, alle genutzten Schlüssel vorhanden.

const CSV_PATH := "res://data/translations.csv"
const SCAN_DIRS := ["res://ui"]

var _rows: Dictionary = {}  # Schlüssel -> {"de": ..., "en": ...}
var _languages: PackedStringArray


func before() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header := file.get_csv_line()
	_languages = header.slice(1)
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 2 or line[0] == "":
			continue
		var entry := {}
		for i in _languages.size():
			entry[_languages[i]] = line[i + 1] if i + 1 < line.size() else ""
		_rows[line[0]] = entry


func after() -> void:
	TranslationServer.set_locale(Prefs.language)


func test_languages_are_german_and_english() -> void:
	assert_array(Array(_languages)).contains_exactly(["de", "en"])


func test_every_key_has_all_languages_and_same_placeholders() -> void:
	var regex := RegEx.create_from_string("\\{(\\w+)\\}")
	for key: String in _rows:
		var sets := {}
		for lang in _languages:
			var text: String = _rows[key][lang]
			assert_str(text).override_failure_message("%s fehlt in %s" % [key, lang]).is_not_empty()
			var names: Array = regex.search_all(text).map(func(m: RegExMatch) -> String: return m.get_string(1))
			names.sort()
			sets[lang] = names
		assert_array(sets["en"]).override_failure_message("Platzhalter in %s verschieden" % key).is_equal(sets["de"])


func test_data_names_exist() -> void:
	var db := MonsterDb.from_file()
	var items := ItemDb.from_files()
	var keys: Array[String] = []
	for id in db.ids():
		keys.append("MONSTER_" + id)
		keys.append("TYPE_" + db.get_def(id)["type"])
	for id in items.trainer_ids():
		keys.append("TRAINER_" + id)
	for id in items.trinket_ids():
		keys.append("TRINKET_" + id)
	for key in keys:
		assert_bool(_rows.has(key)).override_failure_message("Name fehlt: " + key).is_true()


## Schlüssel in Loc.t("...") und text = "..." aus Skripten und Szenen müssen in der Tabelle stehen.
func test_keys_used_in_ui_exist() -> void:
	var patterns := [RegEx.create_from_string("Loc\\.t\\(\"([A-Z][A-Z0-9_]+)\""),
		RegEx.create_from_string("text = \"([A-Z][A-Z0-9_]+)\"")]
	var checked := 0
	for dir: String in SCAN_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not (file.ends_with(".gd") or file.ends_with(".tscn")):
				continue
			var source := FileAccess.get_file_as_string(dir.path_join(file))
			for regex: RegEx in patterns:
				for m in regex.search_all(source):
					var key := m.get_string(1)
					# Präfixe wie "TRIGGER_" + trigger prüft test_all_abilities_render_in_all_languages.
					if key == "INKLITE" or key.ends_with("_"):
						continue
					checked += 1
					assert_bool(_rows.has(key)).override_failure_message("%s nutzt fehlenden Schlüssel %s" % [file, key]).is_true()
	assert_int(checked).is_greater(50)


## Alle Fähigkeiten der Daten ergeben in jeder Sprache vollständige Sätze ohne offene Platzhalter.
func test_all_abilities_render_in_all_languages() -> void:
	var db := MonsterDb.from_file()
	var items := ItemDb.from_files()
	for lang in _languages:
		TranslationServer.set_locale(lang)
		var texts: Array[String] = []
		for id in db.ids():
			for level in 3:
				texts.append(AbilityText.describe(db.level_stats(id, level + 1).get("ability")))
		for id in items.trainer_ids():
			texts.append(AbilityText.describe(items.trainer(id)["ability"], true))
		for id in items.trinket_ids():
			texts.append(AbilityText.describe(items.trinket(id)["ability"], true))
		for text in texts:
			assert_bool(text.contains("{") or text.contains("_")).override_failure_message("[%s] %s" % [lang, text]).is_false()
		for keyword in ["poison", "shield", "damage", "buff_atk", "buff_hp", "gold", "battle_start", "on_attack", "on_hurt", "on_death", "round_end", "level", "front"]:
			assert_bool(_rows.has("KW_" + keyword)).override_failure_message("KW_" + keyword).is_true()
