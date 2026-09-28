class_name Loc
extends RefCounted
## Übersetzte Texte aus data/translations.csv. Platzhalter sind benannt ({wins}), damit jede Sprache
## ihre eigene Wortstellung haben kann. Namen aus den Daten laufen über Schlüssel wie MONSTER_<id>.

const LANGUAGES: Array[String] = ["de", "en"]


static func t(key: String, args: Dictionary = {}) -> String:
	return String(TranslationServer.translate(key)).format(args)


static func monster(id: String) -> String:
	return _name("MONSTER_", id)


static func type_name(type: String) -> String:
	return _name("TYPE_", type)


## Trainer oder Trinket.
static func item(id: String) -> String:
	var key := "TRAINER_" + id
	if TranslationServer.translate(key) != StringName(key):
		return String(TranslationServer.translate(key))
	return _name("TRINKET_", id)


## Sprache des Geräts, wenn wir sie haben, sonst Englisch.
static func default_language() -> String:
	var lang := OS.get_locale_language()
	return lang if LANGUAGES.has(lang) else "en"


static func _name(prefix: String, id: String) -> String:
	var key := prefix + id
	var text := String(TranslationServer.translate(key))
	return id if text == key else text
