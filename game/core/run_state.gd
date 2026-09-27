class_name RunState
extends RefCounted
## Zustand eines Runs: Runde, Gold, Leben, Siege, Raster und Shop. Reine Logik, speicherbar als Dictionary.
##
## Raster ohne Bank: board[slot] ist null oder {"id", "level"}. Gekaufte Monster landen auf dem ersten
## freien Feld (vorne zuerst). Ist das Raster voll, geht ein Kauf nur, wenn er sofort verschmilzt.
## Zufall hängt nur an Run-Seed, Runde und Zähler, damit ein geladener Run genauso weiterläuft.

const SALT_SHOP := 11
const SALT_GHOST := 23
const SALT_BATTLE := 37

var seed_value := 0
var round_number := 1
var gold := 0
var lives := 0
var wins := 0
var losses := 0
var draws := 0
var rolls := 0  # Würfe in dieser Runde, 0 = Gratiswurf zu Rundenbeginn
var board: Array = []
var offers: Array = []  # Monster-IDs, "" für gekaufte Plätze

var _db: MonsterDb
var _rules: Dictionary
var _combat_rules: Dictionary
var _ghosts: Array


func _init(db: MonsterDb, balance: Dictionary, ghosts: Array) -> void:
	_db = db
	_rules = balance.get("run", {})
	_combat_rules = balance.get("combat", {})
	_ghosts = ghosts
	board.resize(CombatSim.SLOTS)


static func create(db: MonsterDb, balance: Dictionary, ghosts: Array, run_seed: int) -> RunState:
	var run := RunState.new(db, balance, ghosts)
	run.seed_value = run_seed
	run.lives = int(run._rules.get("start_lives", 1))
	run._start_round()
	return run


# --- Abfragen ---

func is_over() -> bool:
	return is_victory() or lives <= 0


func is_victory() -> bool:
	return wins >= int(_rules.get("wins_to_victory", 1))


func wins_to_victory() -> int:
	return int(_rules.get("wins_to_victory", 1))


func reroll_cost() -> int:
	return int(_rules.get("reroll_cost", 0))


func price(offer_index: int) -> int:
	return Shop.price(_db, offers[offer_index])


func sell_value(slot: int) -> int:
	return Shop.sell_value(_rules, board[slot]["level"]) if board[slot] != null else 0


func max_level(id: String) -> int:
	return _db.get_def(id).get("levels", []).size()


func unit_count() -> int:
	return board.filter(func(u: Variant) -> bool: return u != null).size()


func can_buy(offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= offers.size() or offers[offer_index] == "":
		return false
	if gold < price(offer_index):
		return false
	return _free_slot() >= 0 or _slots_of(offers[offer_index], 1).size() >= _merge_count() - 1


## Team im Format von CombatSim.
func team() -> Array:
	var result: Array = []
	for slot in CombatSim.SLOTS:
		if board[slot] != null:
			result.append({"id": board[slot]["id"], "level": board[slot]["level"], "slot": slot})
	return result


# --- Aktionen im Shop ---

## Kauft ein Angebot. Ergebnis: {"ok", "slot", "merges": [{"id", "level", "slot"}]}.
func buy(offer_index: int) -> Dictionary:
	if not can_buy(offer_index):
		return {"ok": false}
	var id: String = offers[offer_index]
	gold -= price(offer_index)
	offers[offer_index] = ""
	var slot := _free_slot()
	var merges: Array = []
	if slot >= 0:
		board[slot] = {"id": id, "level": 1}
	else:
		# Raster voll: der Neue verschmilzt direkt mit den vorhandenen Kopien.
		var copies := _slots_of(id, 1)
		for i in range(1, _merge_count() - 1):
			board[copies[i]] = null
		slot = copies[0]
		board[slot] = {"id": id, "level": 2}
		merges.append({"id": id, "level": 2, "slot": slot})
	merges.append_array(_merge_all())
	for merge: Dictionary in merges:
		if merge["id"] == id:
			slot = merge["slot"]
	return {"ok": true, "slot": slot, "merges": merges}


func sell(slot: int) -> int:
	if slot < 0 or slot >= CombatSim.SLOTS or board[slot] == null:
		return 0
	var value := sell_value(slot)
	gold += value
	board[slot] = null
	return value


## Tauscht zwei Felder. Leere Felder sind erlaubt.
func move(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot or from_slot < 0 or to_slot < 0 or from_slot >= CombatSim.SLOTS or to_slot >= CombatSim.SLOTS:
		return false
	if board[from_slot] == null:
		return false
	var tmp: Variant = board[to_slot]
	board[to_slot] = board[from_slot]
	board[from_slot] = tmp
	return true


func reroll() -> bool:
	if gold < reroll_cost():
		return false
	gold -= reroll_cost()
	_roll_offers()
	return true


# --- Kampf ---

## Kämpft gegen ein Geisterteam dieser Runde, wertet aus und startet die nächste Runde.
## Ergebnis: CombatSim-Ergebnis plus "round", "ghost_id", "enemy", "seed" und "result" ("win"/"loss"/"draw").
func fight() -> Dictionary:
	var ghost := _pick_ghost()
	var enemy: Array = ghost.get("team", [])
	var battle_seed := _mix(SALT_BATTLE, 0)
	var sim := CombatSim.new(_db, _combat_rules)
	var result := sim.simulate(team(), enemy, battle_seed)
	result["round"] = round_number
	result["ghost_id"] = ghost.get("id", "")
	result["enemy"] = enemy
	result["seed"] = battle_seed
	match int(result["winner"]):
		0:
			wins += 1
			result["result"] = "win"
		1:
			lives -= 1
			losses += 1
			result["result"] = "loss"
		_:
			draws += 1
			result["result"] = "draw"
	if not is_over():
		advance_round()
	return result


## Nächste Runde ohne Kampf. Nur für Werkzeuge wie tools/make_ghosts.gd.
func advance_round() -> void:
	round_number += 1
	_start_round()


# --- Speichern ---

func to_dict() -> Dictionary:
	return {
		"seed": seed_value, "round": round_number, "gold": gold, "lives": lives,
		"wins": wins, "losses": losses, "draws": draws, "rolls": rolls,
		"board": board.duplicate(true), "offers": offers.duplicate(),
	}


static func from_dict(data: Dictionary, db: MonsterDb, balance: Dictionary, ghosts: Array) -> RunState:
	var run := RunState.new(db, balance, ghosts)
	run.seed_value = int(data["seed"])
	run.round_number = int(data["round"])
	run.gold = int(data["gold"])
	run.lives = int(data["lives"])
	run.wins = int(data["wins"])
	run.losses = int(data.get("losses", 0))
	run.draws = int(data.get("draws", 0))
	run.rolls = int(data.get("rolls", 0))
	for slot in CombatSim.SLOTS:
		var unit: Variant = data["board"][slot]
		if unit is Dictionary and db.has(unit["id"]):
			run.board[slot] = {"id": unit["id"], "level": int(unit["level"])}
	run.offers = []
	for id: String in data["offers"]:
		run.offers.append(id if id == "" or db.has(id) else "")
	return run


# --- Intern ---

func _start_round() -> void:
	gold = Shop.gold_for_round(_rules, round_number)
	rolls = 0
	_roll_offers()


func _roll_offers() -> void:
	var rng := GameRng.new(_mix(SALT_SHOP, rolls))
	rolls += 1
	offers = []
	for id in Shop.roll(_db, _rules, round_number, rng):
		offers.append(id)


func _pick_ghost() -> Dictionary:
	if _ghosts.is_empty():
		return {}
	var best_round := 0
	for ghost: Dictionary in _ghosts:
		var r := int(ghost["round"])
		if r <= round_number:
			best_round = maxi(best_round, r)
	if best_round == 0:
		best_round = _ghosts.map(func(g: Dictionary) -> int: return int(g["round"])).min()
	var candidates := _ghosts.filter(func(g: Dictionary) -> bool: return int(g["round"]) == best_round)
	return GameRng.new(_mix(SALT_GHOST, 0)).pick(candidates)


## Verschmilzt so lange, bis nirgends mehr genug gleiche Monster gleicher Stufe stehen.
## Das Ergebnis landet auf dem vordersten der beteiligten Felder.
func _merge_all() -> Array:
	var merges: Array = []
	var changed := true
	while changed:
		changed = false
		for slot in CombatSim.SLOTS:
			var unit: Variant = board[slot]
			if unit == null or unit["level"] >= max_level(unit["id"]):
				continue
			var copies := _slots_of(unit["id"], unit["level"])
			if copies.size() < _merge_count():
				continue
			var target: int = copies[0]
			var new_level: int = unit["level"] + 1
			for i in range(1, _merge_count()):
				board[copies[i]] = null
			board[target] = {"id": unit["id"], "level": new_level}
			merges.append({"id": unit["id"], "level": new_level, "slot": target})
			changed = true
			break
	return merges


func _slots_of(id: String, level: int) -> Array[int]:
	var result: Array[int] = []
	for slot in CombatSim.SLOTS:
		var unit: Variant = board[slot]
		if unit != null and unit["id"] == id and unit["level"] == level:
			result.append(slot)
	return result


func _free_slot() -> int:
	for slot in CombatSim.SLOTS:
		if board[slot] == null:
			return slot
	return -1


func _merge_count() -> int:
	return int(_rules.get("merge_count", 3))


## Leitet einen Seed aus Run-Seed, Runde, Zweck und Zähler ab. Nur Ganzzahlen; nach jedem Schritt
## modulo einer Primzahl unter 2^31, damit nichts überläuft.
func _mix(salt: int, counter: int) -> int:
	const P := 2147483629
	var value := absi(seed_value) % P
	for part in [round_number, salt, counter]:
		value = (value * 1000003 + part) % P
	return value
