class_name CombatSim
extends RefCounted
## Deterministischer Kampf zweier 3x3-Teams. Liefert Ergebnis plus Ereignisliste und rendert nichts.
##
## Raster: slot = row * COLS + col. Reihe 0 ist die vordere Reihe, die zuerst getroffen wird.
## Tick 0: alle battle_start-Fähigkeiten. Ab Tick 1 handelt jedes lebende Monster einmal,
## in Slot-Reihenfolge und pro Slot erst die Seite mit Vorzug. Der Vorzug wechselt jeden Tick.
## Am Tickende wirkt Gift. Ende, sobald eine Seite leer ist, sonst nach max_ticks unentschieden.
##
## Team-Format: Array von {"id": String, "level": int, "slot": int}.
## Ergebnis: {"winner": 0 | 1 | DRAW, "ticks": int, "events": Array[Dictionary]}.

const ROWS := 3
const COLS := 3
const SLOTS := ROWS * COLS
const DRAW := -1

const TRIGGER_BATTLE_START := "battle_start"
const TRIGGER_ON_ATTACK := "on_attack"
const TRIGGER_ON_HURT := "on_hurt"
const TRIGGER_ON_DEATH := "on_death"

var rules: Dictionary

var _db: MonsterDb
var _rng: GameRng
var _units: Array = []  # [seite] -> Array mit SLOTS Einträgen (CombatUnit oder null)
var _events: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _tick := 0


func _init(db: MonsterDb, combat_rules: Dictionary) -> void:
	_db = db
	rules = combat_rules


func simulate(team_a: Array, team_b: Array, seed_value: int) -> Dictionary:
	_rng = GameRng.new(seed_value)
	_events = []
	_queue = []
	_tick = 0
	_units = [_build_side(0, team_a), _build_side(1, team_b)]

	var start_units: Array[Dictionary] = []
	for unit in _all_in_order(0):
		start_units.append(unit.snapshot())
	emit({"ev": "start", "seed": seed_value, "units": start_units})

	for unit in _all_in_order(0):
		_fire(unit, TRIGGER_BATTLE_START, {})
		_drain_queue()
	if not _is_over():
		var max_ticks: int = rules.get("max_ticks", 1)
		while _tick < max_ticks and not _is_over():
			_tick += 1
			_run_tick()

	var winner := _winner()
	emit({"ev": "end", "winner": winner})
	return {"winner": winner, "ticks": _tick, "events": _events}


func emit(event: Dictionary) -> void:
	event["t"] = _tick
	_events.append(event)


func kill(unit: CombatUnit) -> void:
	if not unit.alive:
		return
	unit.alive = false
	emit({"ev": "death", "side": unit.side, "slot": unit.slot})
	queue_trigger(unit, TRIGGER_ON_DEATH, {})


func queue_trigger(unit: CombatUnit, trigger: String, context: Dictionary) -> void:
	if unit.ability.get("trigger", "") == trigger:
		_queue.append({"unit": unit, "trigger": trigger, "context": context})


func _run_tick() -> void:
	emit({"ev": "tick"})
	var first_side := (_tick - 1) % 2
	for unit in _all_in_order(first_side):
		if _is_over():
			return
		if unit.alive:
			_attack(unit)
			_drain_queue()
	if _is_over():
		return
	var decay: int = rules.get("poison_decay_per_tick", 0)
	for unit in _all_in_order(first_side):
		if unit.alive and unit.poison > 0:
			Effects.deal_damage(self, null, unit, unit.poison, Effects.KIND_POISON)
			unit.poison = maxi(unit.poison - decay, 0)
	_drain_queue()


func _attack(attacker: CombatUnit) -> void:
	var target := _front_target(1 - attacker.side, attacker.col())
	if target == null:
		return
	emit({"ev": "attack", "side": attacker.side, "slot": attacker.slot, "to_side": target.side, "to_slot": target.slot})
	Effects.deal_damage(self, attacker, target, attacker.atk, Effects.KIND_ATTACK)
	_fire(attacker, TRIGGER_ON_ATTACK, {"target": target})


func _fire(unit: CombatUnit, trigger: String, context: Dictionary) -> void:
	var ability := unit.ability
	if ability.get("trigger", "") != trigger:
		return
	# Nur on_death wirkt noch aus dem Grab.
	if not unit.alive and trigger != TRIGGER_ON_DEATH:
		return
	var targets := _resolve_targets(unit, ability.get("target", ""), context)
	if targets.is_empty():
		return
	emit({"ev": "ability", "side": unit.side, "slot": unit.slot, "trigger": trigger, "effect": ability["effect"]})
	Effects.apply(self, ability["effect"], int(ability.get("value", 0)), unit, targets)


## Ausgelöste Fähigkeiten (on_hurt, on_death) laufen erst nach der aktuellen Aktion,
## in der Reihenfolge, in der sie entstanden sind.
func _drain_queue() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		_fire(entry["unit"], entry["trigger"], entry["context"])


func _resolve_targets(source: CombatUnit, target_rule: String, context: Dictionary) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	var enemy_side := 1 - source.side
	match target_rule:
		"self":
			result.append(source)
		"target", "attacker":
			var unit: CombatUnit = context.get(target_rule)
			if unit != null:
				result.append(unit)
		"allies_all":
			result = _living(source.side)
		"allies_row":
			for unit in _living(source.side):
				if unit.row() == source.row():
					result.append(unit)
		"enemies_all":
			result = _living(enemy_side)
		"enemies_front":
			var front := _front_row(enemy_side)
			for unit in _living(enemy_side):
				if unit.row() == front:
					result.append(unit)
		"enemy_front":
			var unit := _front_target(enemy_side, source.col())
			if unit != null:
				result.append(unit)
		"enemy_random":
			var unit: CombatUnit = _rng.pick(_living(enemy_side))
			if unit != null:
				result.append(unit)
		_:
			push_error("Unbekanntes Ziel: %s" % target_rule)
	var alive: Array[CombatUnit] = []
	for unit in result:
		if unit.alive:
			alive.append(unit)
	return alive


## Vorderste besetzte Reihe, darin die Spalte, die dem Angreifer am nächsten liegt.
## Gleich weit entfernte Spalten entscheidet der Zufall.
func _front_target(side: int, attacker_col: int) -> CombatUnit:
	var row := _front_row(side)
	if row < 0:
		return null
	var best: Array[CombatUnit] = []
	var best_dist := COLS + 1
	for unit in _living(side):
		if unit.row() != row:
			continue
		var dist := absi(unit.col() - attacker_col)
		if dist < best_dist:
			best_dist = dist
			best = [unit]
		elif dist == best_dist:
			best.append(unit)
	return _rng.pick(best)


func _front_row(side: int) -> int:
	var row := ROWS
	for unit in _living(side):
		row = mini(row, unit.row())
	return row if row < ROWS else -1


func _living(side: int) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit: CombatUnit in _units[side]:
		if unit != null and unit.alive:
			result.append(unit)
	return result


## Alle Monster beider Seiten: Slot für Slot, pro Slot erst first_side.
func _all_in_order(first_side: int) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for slot in SLOTS:
		for side in [first_side, 1 - first_side]:
			var unit: CombatUnit = _units[side][slot]
			if unit != null:
				result.append(unit)
	return result


func _is_over() -> bool:
	return _living(0).is_empty() or _living(1).is_empty()


func _winner() -> int:
	var a_alive := not _living(0).is_empty()
	var b_alive := not _living(1).is_empty()
	if a_alive and not b_alive:
		return 0
	if b_alive and not a_alive:
		return 1
	return DRAW


func _build_side(side: int, team: Array) -> Array:
	var slots: Array = []
	slots.resize(SLOTS)
	for entry: Dictionary in team:
		var slot: int = entry["slot"]
		if slot < 0 or slot >= SLOTS or slots[slot] != null:
			push_error("Ungültiger oder doppelter Slot %d auf Seite %d" % [slot, side])
			continue
		var stats := _db.level_stats(entry["id"], entry.get("level", 1))
		if stats.is_empty():
			continue
		var unit := CombatUnit.new()
		unit.side = side
		unit.slot = slot
		unit.id = entry["id"]
		unit.level = entry.get("level", 1)
		unit.max_hp = stats["hp"]
		unit.hp = unit.max_hp
		unit.atk = stats["atk"]
		var ability: Variant = stats.get("ability")
		unit.ability = ability if ability is Dictionary else {}
		slots[slot] = unit
	return slots
