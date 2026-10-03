class_name WsRuleset
extends RefCounted
## Workshop-Regelsatz: Einheiten, Spielsteine, Wirtschaft, Shop, Brett, Run und Kampf.
## Liegt außerhalb von res:// in workshop/rulesets/<name>/ (ruleset.json, units.json, ghosts.json),
## weil die Daten aus fremden Spielen stammen und nicht ins öffentliche Repo gehören.
##
## Eine Fähigkeit ist ein Dictionary aus Auslöser, Effekt und Ziel, siehe workshop/README.md.
## Zahlen in atk, hp, value und times wachsen mit der Stufe (board.level_scale).

const KEYWORDS: Array[String] = ["taunt", "divine_shield", "reborn", "windfury", "venomous", "cleave", "stealth"]
## Auswahl für give_keyword mit keyword "random", wie die Bonus-Schlüsselwörter in BG.
const RANDOM_KEYWORDS: Array[String] = ["taunt", "divine_shield", "reborn", "windfury", "venomous"]
const SCALED_FIELDS: Array[String] = ["atk", "hp", "value", "times"]

var dir: String
var rules: Dictionary = {}
var units: Dictionary = {}   # id -> Definition
var tokens: Dictionary = {}  # id -> Definition
var ghosts: Array = []       # gespeicherte Gegnerteams, je {"id", "day", "wins", "bot", "team"}
## Gelernte Stärke je Einheit (bereinigte Winrate aus dem letzten Geister-Durchgang). Bots kaufen danach.
var unit_values: Dictionary = {}

var _ids_by_rarity: Array = []
var _deathrattle_ids: Array[String] = []


## path: Ordner des Regelsatzes, absolut oder relativ zum Repo-Wurzelordner.
static func load_dir(path: String) -> WsRuleset:
	var rs := WsRuleset.new()
	if not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join("..").path_join(path)
	rs.dir = path.simplify_path()
	var rules_data: Variant = GameData.load_json(rs.dir.path_join("ruleset.json"))
	var units_data: Variant = GameData.load_json(rs.dir.path_join("units.json"))
	if not (rules_data is Dictionary and units_data is Dictionary):
		push_error("Regelsatz unvollständig: %s" % rs.dir)
		return null
	rs.setup(rules_data, units_data)
	var ghost_path := rs.dir.path_join("ghosts.json")
	if FileAccess.file_exists(ghost_path):
		var ghost_data: Variant = GameData.load_json(ghost_path)
		if ghost_data is Dictionary:
			rs.ghosts = ghost_data.get("teams", [])
			rs.unit_values = ghost_data.get("unit_values", {})
	return rs


## Für Tests: Regelsatz direkt aus Dictionaries.
func setup(rules_data: Dictionary, units_data: Dictionary) -> void:
	rules = rules_data
	units = {}
	tokens = {}
	for def: Dictionary in units_data.get("units", []):
		units[def["id"]] = def
	for def: Dictionary in units_data.get("tokens", []):
		tokens[def["id"]] = def
	_ids_by_rarity = []
	for r in rarity_count():
		_ids_by_rarity.append([])
	_deathrattle_ids = []
	var ids := units.keys()
	ids.sort()
	for id: String in ids:
		var def: Dictionary = units[id]
		var rarity: int = def.get("rarity", 0)
		if rarity >= 0 and rarity < _ids_by_rarity.size() and not def.get("disabled", false):
			_ids_by_rarity[rarity].append(id)
		for ability: Dictionary in def.get("abilities", []):
			if ability.get("trigger", "") == "on_death":
				_deathrattle_ids.append(id)
				break


func section(name: String) -> Dictionary:
	var value: Variant = rules.get(name, {})
	return value if value is Dictionary else {}


func rarity_count() -> int:
	return maxi(rules.get("rarities", []).size(), 1)


func ids_of_rarity(rarity: int) -> Array:
	if rarity < 0 or rarity >= _ids_by_rarity.size():
		return []
	return _ids_by_rarity[rarity]


func deathrattle_ids() -> Array[String]:
	return _deathrattle_ids


func get_def(id: String) -> Dictionary:
	if units.has(id):
		return units[id]
	return tokens.get(id, {})


func is_token(id: String) -> bool:
	return tokens.has(id) and not units.has(id)


func cost(id: String) -> int:
	return int(get_def(id).get("cost", 0))


func level_factor(level: int) -> int:
	var scale: Array = section("board").get("level_scale", [1, 2, 3])
	if scale.is_empty():
		return 1
	return int(scale[clampi(level - 1, 0, scale.size() - 1)])


## Werte einer Einheit auf einer Stufe, ohne dauerhafte Boni.
func level_stats(id: String, level: int) -> Dictionary:
	var def := get_def(id)
	if def.is_empty():
		return {}
	var f := level_factor(level)
	var abilities: Array = []
	for ability: Dictionary in def.get("abilities", []):
		abilities.append(scale_ability(ability, f))
	return {
		"atk": int(def.get("atk", 0)) * f,
		"hp": int(def.get("hp", 1)) * f,
		"keywords": def.get("keywords", []).duplicate(),
		"passives": def.get("passives", []).duplicate(),
		"colors": def.get("colors", []).duplicate(),
		"abilities": abilities,
	}


static func scale_ability(ability: Dictionary, factor: int) -> Dictionary:
	var scaled := ability.duplicate(true)
	if factor == 1:
		return scaled
	for field in SCALED_FIELDS:
		# Beschwörungen wachsen über die Stufe des Spielsteins, nicht über die Anzahl.
		if field == "times" and scaled.get("effect", "") == "summon":
			continue
		if scaled.has(field):
			scaled[field] = int(scaled[field]) * factor
	return scaled


# --- Wirtschaft und Shop ---

func income_for_day(day: int) -> int:
	var eco := section("economy")
	var list: Array = eco.get("income_by_day", [10])
	if day <= list.size():
		return int(list[maxi(day - 1, 0)])
	return int(list[-1]) + (day - list.size()) * int(eco.get("income_growth_after", 0))


func rank_for_day(day: int, bonus: int = 0) -> int:
	var shop := section("shop")
	return maxi(1, int(shop.get("rank_start", 1)) + (day - 1) * int(shop.get("rank_per_day", 1)) + bonus)


func rarity_weights(rank: int) -> Array:
	var table: Array = section("shop").get("rarity_weights_by_rank", [[100]])
	return table[clampi(rank - 1, 0, table.size() - 1)]


func sell_value(id: String, level: int) -> int:
	var eco := section("economy")
	var mult: Array = eco.get("sell_level_multiplier", [1, 3, 6])
	var m := int(mult[clampi(level - 1, 0, mult.size() - 1)])
	var divisor := maxi(int(eco.get("sell_divisor", 2)), 1)
	return ceili(float(cost(id) * m) / divisor)


func life_loss_for_day(day: int) -> int:
	var list: Array = section("run").get("life_loss_by_day", [1])
	return int(list[clampi(day - 1, 0, list.size() - 1)])


func combat_mode() -> String:
	return section("combat").get("mode", "bg")


func team_slots() -> int:
	return int(section("board").get("team_slots", 6))


func bench_slots() -> int:
	return int(section("board").get("bench_slots", 4))


func grid_cols() -> int:
	return int(section("combat").get("grid", {}).get("cols", 3))


## Nachbarn eines Teamplatzes im Shop. BG-Kampf: Reihe nach Platznummer. Raster: waagrecht und senkrecht.
func slot_neighbors(slot: int) -> Array[int]:
	var result: Array[int] = []
	var n := team_slots()
	if combat_mode() == "grid":
		var cols := grid_cols()
		var col := slot % cols
		for other in [slot - cols, slot + cols]:
			if other >= 0 and other < n:
				result.append(other)
		if col > 0:
			result.append(slot - 1)
		if col < cols - 1 and slot + 1 < n:
			result.append(slot + 1)
	else:
		if slot > 0:
			result.append(slot - 1)
		if slot < n - 1:
			result.append(slot + 1)
	result.sort()
	return result


## Gegnerauswahl nach run.ghost_*: nur Geister bestimmter Bots, Tag verschoben, passend zur Siegzahl.
##   ghost_bots: Liste der Bots, deren Teams als Gegner zählen (leer = alle)
##   ghost_day_offset: Gegner vom Tag + Versatz (positiv = stärker)
##   ghost_match_pool: aus den N Geistern mit der ähnlichsten Siegzahl ziehen (0 = alle des Tages)
func ghost_pool(day: int, wins: int) -> Array:
	var run_rules := section("run")
	var pool := ghosts_for_day(maxi(day + int(run_rules.get("ghost_day_offset", 0)), 1))
	var bots: Array = run_rules.get("ghost_bots", [])
	if not bots.is_empty():
		var filtered := pool.filter(func(g: Dictionary) -> bool: return bots.has(g.get("bot", "")))
		if not filtered.is_empty():
			pool = filtered
	var n := int(run_rules.get("ghost_match_pool", 0))
	if n > 0 and pool.size() > n:
		pool = pool.duplicate()
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := absi(int(a.get("wins", 0)) - wins)
			var db := absi(int(b.get("wins", 0)) - wins)
			return da < db if da != db else str(a.get("id", "")) < str(b.get("id", "")))
		pool = pool.slice(0, n)
	return pool


func ghosts_for_day(day: int) -> Array:
	var best_day := -1
	for ghost: Dictionary in ghosts:
		var d: int = ghost.get("day", 0)
		if d <= day and d > best_day:
			best_day = d
	if best_day < 0:
		return []
	return ghosts.filter(func(g: Dictionary) -> bool: return g.get("day", 0) == best_day)
