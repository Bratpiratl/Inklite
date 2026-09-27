class_name ItemDb
extends RefCounted
## Trainer und Trinkets aus data/trainers.json und data/trinkets.json.

const TRAINERS_PATH := "res://data/trainers.json"
const TRINKETS_PATH := "res://data/trinkets.json"

var _trainers: Dictionary = {}
var _trinkets: Dictionary = {}
var _trainer_ids: Array[String] = []
var _trinket_ids: Array[String] = []


static func from_files() -> ItemDb:
	var trainers: Variant = GameData.load_json(TRAINERS_PATH)
	var trinkets: Variant = GameData.load_json(TRINKETS_PATH)
	return from_arrays(trainers if trainers is Array else [], trinkets if trinkets is Array else [])


static func from_arrays(trainers: Array, trinkets: Array) -> ItemDb:
	var items := ItemDb.new()
	for def: Dictionary in trainers:
		items._trainers[def["id"]] = def
		items._trainer_ids.append(def["id"])
	for def: Dictionary in trinkets:
		items._trinkets[def["id"]] = def
		items._trinket_ids.append(def["id"])
	return items


func trainer_ids() -> Array[String]:
	return _trainer_ids.duplicate()


func trinket_ids() -> Array[String]:
	return _trinket_ids.duplicate()


func trainer(id: String) -> Dictionary:
	return _trainers.get(id, {})


func trinket(id: String) -> Dictionary:
	return _trinkets.get(id, {})
