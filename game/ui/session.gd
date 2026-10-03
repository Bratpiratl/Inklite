extends Node
## Autoload: hält den laufenden Run zwischen den Szenen und speichert ihn lokal.
## Die Spiellogik steckt in RunState, hier wird nur verwaltet, gespeichert und navigiert.

const SAVE_PATH := "user://run.json"
const SAVE_VERSION := 1
const GHOSTS_PATH := "res://data/ghost_teams.json"
const TITLE_SCENE := "res://ui/main.tscn"
const SHOP_SCENE := "res://ui/shop.tscn"
const BATTLE_SCENE := "res://ui/battle_view.tscn"
const TRAINER_SCENE := "res://ui/trainer_select.tscn"
const SETTINGS_SCENE := "res://ui/settings.tscn"
const HISTORY_SCENE := "res://ui/history.tscn"
const HELP_SCENE := "res://ui/help.tscn"
## Workshop-Test (Regelsatz aus res://ws_data/, kommt beim Deploy aus workshop/public/ hinein).
const WORKSHOP_SCENE := "res://tools/ws_play.tscn"
const WORKSHOP_DATA := "res://ws_data/ruleset.json"
const SPRITE_ROOT := "res://assets/sprites/"

var db: MonsterDb
var items: ItemDb
var balance: Dictionary
var ghosts: Array = []
var run: RunState
var last_battle: Dictionary = {}
var help_return := TITLE_SCENE


func _ready() -> void:
	db = MonsterDb.from_file()
	items = ItemDb.from_files()
	balance = GameData.load_balance()
	var data: Variant = GameData.load_json(GHOSTS_PATH)
	if data is Dictionary:
		ghosts = data.get("teams", [])


func new_run(trainer_id: String) -> void:
	# Der Seed selbst darf aus der Uhr kommen, alles danach läuft über GameRng.
	var run_seed := absi(int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()) % 2147483647
	run = RunState.create(db, balance, ghosts, run_seed, trainer_id, items)
	_attach_logger()
	last_battle = {}
	save()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_run() -> bool:
	var data: Variant = GameData.load_json(SAVE_PATH) if has_save() else null
	if not (data is Dictionary) or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	run = RunState.from_dict(data["run"], db, balance, ghosts, items)
	_attach_logger()
	return true


## Echte Runs loggen im selben Format wie die Bots (telemetry/logger.gd), nur lokal.
func _attach_logger() -> void:
	var context := {"run": "%08x" % run.seed_value, "v": RunLogger.version()}
	run.logger = RunLogger.new(context, LogStore.append)


func save() -> void:
	if run == null:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Spielstand nicht speicherbar: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"version": SAVE_VERSION, "run": run.to_dict()}))
	file.close()


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


## Kampf wird sofort ausgewertet und gespeichert, die Kampfansicht spielt ihn nur noch ab.
func fight() -> void:
	if not run.can_fight():
		return
	last_battle = run.fight()
	if run.is_over():
		RunHistory.add(run)
		clear_save()
	else:
		save()


## Name und Sprite eines Trainers oder Trinkets.
func item_def(id: String) -> Dictionary:
	var def := items.trainer(id)
	return def if not def.is_empty() else items.trinket(id)


func item_texture(id: String) -> Texture2D:
	return load(SPRITE_ROOT + item_def(id)["sprite"])


## Anleitung öffnen; "Zurück" führt dorthin, woher man kam.
func open_help(return_scene: String) -> void:
	help_return = return_scene
	goto(HELP_SCENE)


func goto(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)
