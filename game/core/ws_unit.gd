class_name WsUnit
extends RefCounted
## Zustand einer Workshop-Einheit während eines Kampfes. Wird pro Kampf neu erzeugt.

var uid: int
var side: int
var id: String
var level := 1
var colors: Array = []
var atk := 0
var hp := 1
var max_hp := 1
var keywords: Dictionary = {}  # Schlüsselwort -> true
var passives: Array = []
var abilities: Array = []
var alive := true
## Teamplatz, aus dem die Einheit stammt. -1 für Spielsteine und Beschwörungen.
var origin_slot := -1
## Feld im Raster-Modus.
var cell := -1
var killer: WsUnit = null
var avenge_progress: Dictionary = {}  # Index der Fähigkeit -> gezählte Tode


func has_kw(keyword: String) -> bool:
	return keywords.has(keyword)


func has_trigger(trigger: String) -> bool:
	for ability: Dictionary in abilities:
		if ability.get("trigger", "") == trigger:
			return true
	return false


func has_color(color: String) -> bool:
	return colors.has(color)


func snapshot() -> Dictionary:
	return {"uid": uid, "side": side, "id": id, "level": level, "atk": atk, "hp": hp, "keywords": keywords.keys()}
