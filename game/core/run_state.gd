class_name RunState
extends RefCounted
## Zustand eines Runs: Runde, Gold, Leben, Siege, Raster und Shop. Reine Logik, speicherbar als Dictionary.
##
## Raster ohne Bank: board[slot] ist null oder {"id", "level"} plus optional dauerhafte Boni
## "atk_bonus" und "hp_bonus" (aus round_end-Fähigkeiten). Gekaufte Monster landen auf dem ersten
## freien Feld (vorne zuerst). Ist das Raster voll, geht ein Kauf nur, wenn er sofort verschmilzt.
## Zufall hängt nur an Run-Seed, Runde und Zähler, damit ein geladener Run genauso weiterläuft.

const SALT_SHOP := 11
const SALT_GHOST := 23
const SALT_BATTLE := 37
const SALT_TRINKET := 41
const SALT_ROUND_END := 53
const BONUS_KEYS := {Effects.BUFF_ATK: "atk_bonus", Effects.BUFF_HP: "hp_bonus"}

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
var frozen: Array = []  # je Angebot: true = eingefroren, bleibt beim Würfeln und in der nächsten Runde
var trainer := ""
var trinkets: Array[String] = []
var pending_trinkets: Array[String] = []  # Auswahl nach jedem zweiten Sieg, muss vor dem Kampf gewählt werden
var bonus_gold := 0  # aus round_end-Fähigkeiten, wird zu Beginn der nächsten Runde ausgezahlt
var logger: RunLogger  # optional, schreibt Telemetrie (Bots und echte Runs)

var _db: MonsterDb
var _rules: Dictionary
var _combat_rules: Dictionary
var _ghosts: Array
var _items: ItemDb
var _roll_bought: Array = []  # in der aktuellen Würfelrunde gekauft, für das shop-Log
var _roll_offered: Array = []


func _init(db: MonsterDb, balance: Dictionary, ghosts: Array, items: ItemDb = null) -> void:
	_db = db
	_rules = balance.get("run", {})
	_combat_rules = balance.get("combat", {})
	_ghosts = ghosts
	_items = items if items != null else ItemDb.new()
	board.resize(CombatSim.SLOTS)


static func create(db: MonsterDb, balance: Dictionary, ghosts: Array, run_seed: int,
		trainer_id: String = "", items: ItemDb = null) -> RunState:
	var run := RunState.new(db, balance, ghosts, items)
	run.seed_value = run_seed
	run.trainer = trainer_id
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


func can_fight() -> bool:
	return not is_over() and pending_trinkets.is_empty()


## Trainer und Trinkets als Team-Fähigkeiten, jeweils mit ihrer ID.
func team_abilities() -> Array:
	return _abilities_of(trainer, trinkets)


func _abilities_of(trainer_id: String, trinket_ids: Array) -> Array:
	var result: Array = []
	var trainer_def := _items.trainer(trainer_id)
	if trainer_def.has("ability"):
		result.append(TeamAbility.tagged(trainer_def["ability"], trainer_id))
	for id: String in trinket_ids:
		var def := _items.trinket(id)
		if def.has("ability"):
			result.append(TeamAbility.tagged(def["ability"], id))
	return result


## Geister bringen Trainer und Trinkets mit, wenn balance.json ghosts_use_items erlaubt.
func _ghost_abilities(ghost: Dictionary) -> Array:
	if not bool(_rules.get("ghosts_use_items", false)):
		return []
	return _abilities_of(ghost.get("trainer", ""), ghost.get("trinkets", []))


func choose_trinket(id: String) -> bool:
	if not pending_trinkets.has(id):
		return false
	if logger != null:
		logger.trinket(self, pending_trinkets.duplicate(), id)
	trinkets.append(id)
	pending_trinkets.clear()
	return true


func can_buy(offer_index: int) -> bool:
	return can_buy_at(offer_index, -1)


## target_slot -1: erstes freies Feld. Sonst ein freies Feld oder ein gleiches Monster auf Stufe 1,
## mit dem das gekaufte verschmelzen soll.
func can_buy_at(offer_index: int, target_slot: int) -> bool:
	if offer_index < 0 or offer_index >= offers.size() or offers[offer_index] == "":
		return false
	if gold < price(offer_index):
		return false
	var id: String = offers[offer_index]
	var room := _free_slot() >= 0 or _slots_of(id, 1).size() >= _merge_count() - 1
	if target_slot < 0:
		return room
	if target_slot >= CombatSim.SLOTS:
		return false
	var occupant: Variant = board[target_slot]
	if occupant == null:
		return true
	return occupant["id"] == id and occupant["level"] == 1 and room


func is_frozen(offer_index: int) -> bool:
	return offer_index >= 0 and offer_index < frozen.size() and frozen[offer_index]


func toggle_freeze(offer_index: int) -> bool:
	if offer_index < 0 or offer_index >= offers.size() or offers[offer_index] == "":
		return false
	frozen[offer_index] = not is_frozen(offer_index)
	return true


## Team im Format von CombatSim.
func team() -> Array:
	var result: Array = []
	for slot in CombatSim.SLOTS:
		if board[slot] != null:
			var entry: Dictionary = board[slot].duplicate()
			entry["slot"] = slot
			result.append(entry)
	return result


# --- Aktionen im Shop ---

## Kauft ein Angebot. Ergebnis: {"ok", "slot", "merges": [{"id", "level", "slot"}]}.
## target_slot -1: erstes freies Feld (vorne zuerst). Sonst landet das Monster auf diesem Feld, oder,
## wenn dort ein gleiches steht, verschmilzt es dort, sobald genug Kopien beisammen sind.
func buy(offer_index: int, target_slot: int = -1) -> Dictionary:
	if not can_buy_at(offer_index, target_slot):
		return {"ok": false}
	var id: String = offers[offer_index]
	_roll_bought.append(id)
	gold -= price(offer_index)
	offers[offer_index] = ""
	frozen[offer_index] = false
	var slot := _free_slot()
	if target_slot >= 0 and board[target_slot] == null:
		slot = target_slot
	var merges: Array = []
	if slot >= 0:
		board[slot] = {"id": id, "level": 1}
	else:
		# Raster voll: der Neue verschmilzt direkt mit den vorhandenen Kopien.
		var copies := _slots_of(id, 1)
		var keep: int = target_slot if copies.has(target_slot) else copies[0]
		copies.erase(keep)
		var used: Array = [keep] + copies.slice(0, _merge_count() - 2)
		board[keep] = _merged(id, 2, used)
		for other: int in used.slice(1):
			board[other] = null
		slot = keep
		merges.append({"id": id, "level": 2, "slot": slot})
	merges.append_array(_merge_all(target_slot))
	for merge: Dictionary in merges:
		if merge["id"] == id:
			slot = merge["slot"]
	return {"ok": true, "slot": slot, "merges": merges}


func sell(slot: int) -> int:
	if slot < 0 or slot >= CombatSim.SLOTS or board[slot] == null:
		return 0
	var value := sell_value(slot)
	if logger != null:
		logger.sell(self, board[slot], value)
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

## Beendet die Shop-Phase (round_end-Fähigkeiten), kämpft gegen ein Geisterteam dieser Runde,
## wertet aus und startet die nächste Runde. Nach jedem zweiten Sieg wartet eine Trinket-Wahl.
## Ergebnis: CombatSim-Ergebnis plus "round", "ghost_id", "enemy", "seed", "result" ("win"/"loss"/"draw")
## und "round_end" (was die Fähigkeiten im Shop bewirkt haben).
func fight() -> Dictionary:
	if not can_fight():
		push_error("Kampf nicht möglich: Run vorbei oder Trinket-Wahl offen")
		return {}
	_log_roll()
	var round_end := _apply_round_end()
	var ghost := _pick_ghost()
	var enemy: Array = ghost.get("team", [])
	var battle_seed := _mix(SALT_BATTLE, 0)
	var sim := CombatSim.new(_db, _combat_rules)
	var own_team := team()
	var result := sim.simulate(own_team, enemy, battle_seed, team_abilities(), _ghost_abilities(ghost))
	result["round_end"] = round_end
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
	if logger != null:
		logger.battle(self, own_team, result)
		if is_over():
			logger.run_end(self)
	if not is_over():
		if result["result"] == "win" and wins % maxi(int(_rules.get("trinket_every_wins", 0)), 1) == 0 \
				and int(_rules.get("trinket_every_wins", 0)) > 0:
			_roll_trinket_choice()
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
		"board": board.duplicate(true), "offers": offers.duplicate(), "frozen": frozen.duplicate(),
		"trainer": trainer, "trinkets": trinkets.duplicate(),
		"pending_trinkets": pending_trinkets.duplicate(), "bonus_gold": bonus_gold,
	}


static func from_dict(data: Dictionary, db: MonsterDb, balance: Dictionary, ghosts: Array,
		items: ItemDb = null) -> RunState:
	var run := RunState.new(db, balance, ghosts, items)
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
			var entry := {"id": unit["id"], "level": int(unit["level"])}
			for key: String in BONUS_KEYS.values():
				if int(unit.get(key, 0)) != 0:
					entry[key] = int(unit[key])
			run.board[slot] = entry
	run.offers = []
	for id: String in data["offers"]:
		run.offers.append(id if id == "" or db.has(id) else "")
	var saved_frozen: Array = data.get("frozen", [])
	for i in run.offers.size():
		run.frozen.append(i < saved_frozen.size() and bool(saved_frozen[i]) and run.offers[i] != "")
	run.trainer = data.get("trainer", "")
	run.bonus_gold = int(data.get("bonus_gold", 0))
	for id: String in data.get("trinkets", []):
		run.trinkets.append(id)
	for id: String in data.get("pending_trinkets", []):
		run.pending_trinkets.append(id)
	run._roll_offered = run.offers.filter(func(id: String) -> bool: return id != "")
	return run


# --- Intern ---

func _start_round() -> void:
	gold = Shop.gold_for_round(_rules, round_number) + bonus_gold
	bonus_gold = 0
	rolls = 0
	_roll_offers()


func _roll_offers() -> void:
	_log_roll()
	var rng := GameRng.new(_mix(SALT_SHOP, rolls))
	rolls += 1
	var old_offers := offers
	var old_frozen := frozen
	offers = []
	frozen = []
	# Gewürfelt wird immer der volle Shop, damit der Zufall gleich bleibt; eingefrorene Plätze behalten ihr Angebot.
	var rolled := Shop.roll(_db, _rules, round_number, rng)
	for i in rolled.size():
		var keep: bool = i < old_offers.size() and i < old_frozen.size() and old_frozen[i] and old_offers[i] != ""
		offers.append(old_offers[i] if keep else rolled[i])
		frozen.append(keep)
	_roll_offered = offers.duplicate()


## Schreibt die abgeschlossene Würfelrunde ins Log (einmal pro Wurf).
func _log_roll() -> void:
	if logger != null and not _roll_offered.is_empty():
		logger.shop(self, _roll_offered, _roll_bought)
	_roll_offered = []
	_roll_bought = []


## Gegner kommen aus Runde (aktuelle Runde - ghost_round_lag), mindestens Runde 1, sonst die
## nächstniedrigere vorhandene. Mit ghost_match_pool > 0 zählen nur die Geister, deren Siege zu
## diesem Zeitpunkt den eigenen am nächsten kommen (wie später beim asynchronen PvP).
## Beides steht in balance.json und ist der Hebel für die Gegnerstärke.
func _pick_ghost() -> Dictionary:
	if _ghosts.is_empty():
		return {}
	var ghost_round := maxi(round_number - int(_rules.get("ghost_round_lag", 0)), 1)
	var best_round := 0
	for ghost: Dictionary in _ghosts:
		var r := int(ghost["round"])
		if r <= ghost_round:
			best_round = maxi(best_round, r)
	if best_round == 0:
		best_round = _ghosts.map(func(g: Dictionary) -> int: return int(g["round"])).min()
	var candidates := _ghosts.filter(func(g: Dictionary) -> bool: return int(g["round"]) == best_round)
	var pool_size := int(_rules.get("ghost_match_pool", 0))
	if pool_size > 0 and candidates.size() > pool_size:
		# Stabile Sortierung nach Siegabstand, bei Gleichstand bleibt die Dateireihenfolge.
		var indexed: Array = []
		for i in candidates.size():
			indexed.append([absi(int(candidates[i].get("wins", 0)) - wins), i])
		indexed.sort()
		var nearest: Array = []
		for entry: Array in indexed.slice(0, pool_size):
			nearest.append(candidates[entry[1]])
		candidates = nearest
	return GameRng.new(_mix(SALT_GHOST, 0)).pick(candidates)


## Verschmilzt so lange, bis nirgends mehr genug gleiche Monster gleicher Stufe stehen.
## Das Ergebnis landet auf preferred_slot, wenn das beteiligt ist, sonst auf dem vordersten Feld.
func _merge_all(preferred_slot: int = -1) -> Array:
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
			var used: Array = copies.slice(0, _merge_count())
			if copies.has(preferred_slot) and not used.has(preferred_slot):
				used[used.size() - 1] = preferred_slot
			var target: int = preferred_slot if used.has(preferred_slot) else used[0]
			var new_level: int = unit["level"] + 1
			var merged := _merged(unit["id"], new_level, used)
			for other: int in used:
				board[other] = null
			board[target] = merged
			merges.append({"id": unit["id"], "level": new_level, "slot": target})
			changed = true
			break
	return merges


## Verschmolzenes Monster: dauerhafte Boni der Beteiligten werden addiert.
func _merged(id: String, level: int, slots: Array) -> Dictionary:
	var result := {"id": id, "level": level}
	for key: String in BONUS_KEYS.values():
		var total := 0
		for slot: int in slots:
			if board[slot] != null:
				total += int(board[slot].get(key, 0))
		if total != 0:
			result[key] = total
	return result


## round_end-Fähigkeiten von Trainer und Trinkets. Gibt zurück, was passiert ist:
## [{"id", "effect", "value", "slot"}], slot -1 bei Gold.
func _apply_round_end() -> Array:
	var applied: Array = []
	var abilities := team_abilities()
	for index in abilities.size():
		var ability: Dictionary = abilities[index]
		if ability.get("trigger", "") != TeamAbility.TRIGGER_ROUND_END:
			continue
		var effect: String = ability["effect"]
		var value := int(ability.get("value", 0))
		if effect == TeamAbility.EFFECT_GOLD:
			bonus_gold += value
			applied.append({"id": ability["id"], "effect": effect, "value": value, "slot": -1})
		elif BONUS_KEYS.has(effect):
			var key: String = BONUS_KEYS[effect]
			for slot in _board_targets(ability, index):
				board[slot][key] = int(board[slot].get(key, 0)) + value
				applied.append({"id": ability["id"], "effect": effect, "value": value, "slot": slot})
		else:
			push_error("round_end kann Effekt %s nicht" % effect)
	return applied


func _board_targets(ability: Dictionary, index: int) -> Array[int]:
	var occupied: Array[int] = []
	var front := CombatSim.ROWS
	for slot in CombatSim.SLOTS:
		if board[slot] != null:
			occupied.append(slot)
			front = mini(front, _row(slot))
	var pool: Array[int] = []
	for slot in occupied:
		var type: String = _db.get_def(board[slot]["id"]).get("type", "")
		if TeamAbility.matches(ability.get("only"), type, _row(slot)):
			pool.append(slot)
	match ability.get("target", ""):
		"allies_all":
			return pool
		"allies_front":
			return pool.filter(func(slot: int) -> bool: return _row(slot) == front)
		"ally_random":
			if pool.is_empty():
				return []
			return [GameRng.new(_mix(SALT_ROUND_END, index)).pick(pool)]
		var other:
			push_error("round_end kann Ziel %s nicht" % other)
			return []


@warning_ignore("integer_division")
func _row(slot: int) -> int:
	return slot / CombatSim.COLS


func _roll_trinket_choice() -> void:
	var available: Array = []
	for id in _items.trinket_ids():
		if not trinkets.has(id):
			available.append(id)
	GameRng.new(_mix(SALT_TRINKET, wins)).shuffle(available)
	pending_trinkets.clear()
	for id: String in available.slice(0, int(_rules.get("trinket_choices", 3))):
		pending_trinkets.append(id)


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
