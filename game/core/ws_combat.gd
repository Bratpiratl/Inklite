class_name WsCombat
extends RefCounted
## Kampf des Workshops mit zwei umschaltbaren Regelwerken. Reine Logik, deterministisch per Seed.
##
## "bg" (nach Hearthstone Battlegrounds):
##   Jede Seite ist eine Reihe in Platzreihenfolge. Wer mehr Einheiten hat, greift zuerst an, bei
##   Gleichstand entscheidet der Zufall. Die Seiten wechseln sich ab, je Seite greift die nächste
##   Einheit von links nach rechts an. Ziel zufällig, Spott zuerst. Beide Seiten treffen sich.
##   Beschwörungen erscheinen am Platz der Auslöserin; Einheiten links vom Zeiger warten eine Runde.
## "grid" (nach dem Inklite-Kampf):
##   Raster cols x rows, Reihe 0 vorne. Pro Tick handelt jede Einheit einmal in Feldreihenfolge,
##   pro Feld erst die Seite mit Vorzug, der jeden Tick wechselt. Ziel ist die vorderste Reihe,
##   darin die nächste Spalte, Spott zuerst. Nur der Angreifer teilt Schaden aus.
##
## Team-Format: Array von {"id", "level", "slot", optional "atk_bonus", "hp_bonus", "keywords"}.
## Ergebnis: {"winner": 0 | 1 | DRAW, "attacks", "ticks", "survivors": [a, b], "events",
##            "permanent": [seite] -> {slot: {"atk", "hp", "keywords"}}} für dauerhafte Kampf-Boni.

const DRAW := -1
const MAX_DEPTH := 40
const RANDOM_TARGETS := ["ally_random", "ally_random_other", "enemy_random"]

var rs: WsRuleset
var mode: String
## Ereignisliste mitschreiben (Tests, spätere Anzeige). Kostet Zeit, darum abschaltbar.
var trace := false

var _rng: GameRng
var _line: Array = [[], []]
var _grid: Array = [[], []]
var _next: Array = [0, 0]
var _events: Array = []
var _permanent: Array = [{}, {}]
var _uid := 0
var _attacks := 0
var _ticks := 0
var _depth := 0
var _max_units := 7
var _cols := 3
var _rows := 2


func _init(ruleset: WsRuleset, mode_override: String = "") -> void:
	rs = ruleset
	mode = mode_override if mode_override != "" else rs.combat_mode()
	var combat := rs.section("combat")
	_max_units = int(combat.get("bg", {}).get("max_units", 7))
	_cols = int(combat.get("grid", {}).get("cols", 3))
	_rows = int(combat.get("grid", {}).get("rows", 2))


func simulate(team_a: Array, team_b: Array, seed_value: int) -> Dictionary:
	_rng = GameRng.new(seed_value)
	_events = []
	_permanent = [{}, {}]
	_uid = 0
	_attacks = 0
	_ticks = 0
	_depth = 0
	_next = [0, 0]
	_line = [[], []]
	_grid = [_empty_grid(), _empty_grid()]
	_build_side(0, team_a)
	_build_side(1, team_b)
	if trace:
		var units: Array = []
		for side in 2:
			for unit: WsUnit in _board(side):
				var snap := unit.snapshot()
				snap["pos"] = _position(unit)
				units.append(snap)
		_emit({"ev": "start", "seed": seed_value, "mode": mode, "units": units})

	var first := _first_side()
	for side in [first, 1 - first]:
		for unit: WsUnit in _living(side):
			_fire_trigger(unit, "start_of_combat", {})
			_resolve_deaths(side)
	if mode == "grid":
		_run_grid(first)
	else:
		_run_bg(first)

	var winner := _winner()
	_emit({"ev": "end", "winner": winner})
	return {
		"winner": winner, "attacks": _attacks, "ticks": _ticks, "events": _events, "permanent": _permanent,
		"survivors": [_living(0).size(), _living(1).size()],
	}


# --- Ablauf ---

func _first_side() -> int:
	if mode == "bg":
		var a := _living(0).size()
		var b := _living(1).size()
		if a != b:
			return 0 if a > b else 1
	return _rng.next_int(2)


func _run_bg(first: int) -> void:
	var max_attacks := int(rs.section("combat").get("bg", {}).get("max_attacks", 200))
	var side := first
	while not _is_over() and _attacks < max_attacks:
		var attacker := _pick_bg_attacker(side)
		if attacker == null:
			if _pick_bg_attacker(1 - side) == null:
				return
			side = 1 - side
			continue
		var swings := 2 if attacker.has_kw("windfury") else 1
		for s in swings:
			if not attacker.alive or attacker.hp <= 0 or _is_over():
				break
			_attack(attacker)
		side = 1 - side


## Nächste Einheit ab dem Zeiger mit Angriff über 0. Der Zeiger steht danach rechts von ihr.
func _pick_bg_attacker(side: int) -> WsUnit:
	var line: Array = _line[side]
	var n := line.size()
	if n == 0:
		return null
	if _next[side] >= n:
		_next[side] = 0
	for k in n:
		var i: int = (_next[side] + k) % n
		var unit: WsUnit = line[i]
		if unit.alive and unit.hp > 0 and unit.atk > 0:
			_next[side] = i + 1
			return unit
	return null


func _run_grid(first: int) -> void:
	var max_ticks := int(rs.section("combat").get("grid", {}).get("max_ticks", 40))
	while _ticks < max_ticks and not _is_over():
		_ticks += 1
		var order_first := (first + _ticks - 1) % 2
		for cell in _cols * _rows:
			for side in [order_first, 1 - order_first]:
				var unit: WsUnit = _grid[side][cell]
				if unit == null or not unit.alive or unit.hp <= 0 or unit.atk <= 0:
					continue
				var swings := 2 if unit.has_kw("windfury") else 1
				for s in swings:
					if not unit.alive or unit.hp <= 0 or _is_over():
						break
					_attack(unit)
				if _is_over():
					return


func _attack(attacker: WsUnit) -> void:
	var target := _choose_target(attacker)
	if target == null:
		return
	_attacks += 1
	attacker.keywords.erase("stealth")
	_emit({"ev": "attack", "side": attacker.side, "uid": attacker.uid, "to": target.uid})
	_fire_trigger(attacker, "on_attack", {"target": target})
	for ally: WsUnit in _living(attacker.side):
		_fire_listener(ally, "on_ally_attack", attacker, {"trigger_unit": attacker, "target": target})
	_resolve_deaths(attacker.side)
	if not attacker.alive or attacker.hp <= 0:
		return
	if not target.alive or target.hp <= 0:
		target = _choose_target(attacker)
		if target == null:
			return

	var damage := attacker.atk
	var hp_before := target.hp
	var splash := _cleave_targets(target) if attacker.has_kw("cleave") else []
	_damage(attacker, target, damage, true)
	if mode == "bg":
		_damage(target, attacker, target.atk, true)
	for other: WsUnit in splash:
		_damage(attacker, other, damage, true)
	if target.hp <= 0 and target.killer == attacker:
		_fire_trigger(attacker, "on_kill", {"target": target, "excess": maxi(damage - hp_before, 0)})
	_fire_trigger(attacker, "after_attack", {"target": target})
	_resolve_deaths(attacker.side)


func _choose_target(attacker: WsUnit) -> WsUnit:
	var enemies := _living(1 - attacker.side)
	if enemies.is_empty():
		return null
	var visible: Array = enemies.filter(func(u: WsUnit) -> bool: return not u.has_kw("stealth"))
	if visible.is_empty():
		visible = enemies
	var taunts: Array = visible.filter(func(u: WsUnit) -> bool: return u.has_kw("taunt"))
	var pool: Array = taunts if not taunts.is_empty() else visible
	if mode == "bg":
		return _rng.pick(pool)
	if taunts.is_empty():
		var front := _rows
		for unit: WsUnit in pool:
			front = mini(front, _row(unit.cell))
		pool = pool.filter(func(u: WsUnit) -> bool: return _row(u.cell) == front)
	var col := attacker.cell % _cols
	var best: Array = []
	var best_dist := 1 << 20
	for unit: WsUnit in pool:
		var dist := absi(unit.cell % _cols - col)
		if dist < best_dist:
			best_dist = dist
			best = [unit]
		elif dist == best_dist:
			best.append(unit)
	return _rng.pick(best)


func _cleave_targets(target: WsUnit) -> Array:
	var result: Array = []
	if mode == "bg":
		var line: Array = _line[target.side]
		var i := line.find(target)
		for j in [i - 1, i + 1]:
			if j >= 0 and j < line.size() and line[j].alive and line[j].hp > 0:
				result.append(line[j])
	else:
		var col := target.cell % _cols
		for d in [-1, 1]:
			if col + d < 0 or col + d >= _cols:
				continue
			var other: WsUnit = _grid[target.side][target.cell + d]
			if other != null and other.alive and other.hp > 0:
				result.append(other)
	return result


## Schaden. Gottesschild fängt einen Treffer ganz ab. Gift (venomous) tötet bei echtem Schaden durch Angriff.
func _damage(source: WsUnit, target: WsUnit, amount: int, is_attack: bool) -> int:
	if target == null or not target.alive or target.hp <= 0 or amount <= 0:
		return 0
	if target.has_kw("divine_shield"):
		target.keywords.erase("divine_shield")
		_emit({"ev": "shield_lost", "uid": target.uid})
		_fire_trigger(target, "on_shield_lost", {})
		for ally: WsUnit in _living(target.side):
			_fire_listener(ally, "on_ally_shield_lost", target, {"trigger_unit": target})
		return 0
	target.hp -= amount
	_emit({"ev": "damage", "uid": target.uid, "amount": amount, "hp": target.hp})
	if is_attack and source != null and source.has_kw("venomous") and target.hp > 0:
		target.hp = 0
		source.keywords.erase("venomous")
	if target.hp <= 0:
		if target.killer == null:
			target.killer = source
	elif is_attack:
		_fire_trigger(target, "on_hurt", {"attacker": source})
	return amount


## Entfernt Gestorbene, löst Todesröcheln, Rache und Wiedergeburt aus, bis niemand mehr stirbt.
func _resolve_deaths(first_side: int) -> void:
	for round_index in 50:
		var dead: Array = []
		for side in [first_side, 1 - first_side]:
			for unit: WsUnit in _board(side):
				if unit.alive and unit.hp <= 0:
					dead.append(unit)
		if dead.is_empty():
			return
		for unit: WsUnit in dead:
			_handle_death(unit)


func _handle_death(unit: WsUnit) -> void:
	unit.alive = false
	var pos := _remove(unit)
	_emit({"ev": "death", "uid": unit.uid, "side": unit.side})
	var ctx := {"pos": pos, "killer": unit.killer}
	if unit.has_trigger("on_death"):
		var repeats := 2 if _side_has_passive(unit.side, "deathrattle_twice") else 1
		for r in repeats:
			_fire_trigger(unit, "on_death", ctx)
			for ally: WsUnit in _living(unit.side):
				_fire_listener(ally, "after_deathrattle", unit, {"trigger_unit": unit})
	for ally: WsUnit in _living(unit.side):
		_fire_listener(ally, "on_ally_death", unit, {"trigger_unit": unit})
		_count_avenge(ally)
	if unit.has_kw("reborn"):
		var copy := _spawn(unit.id, unit.level, unit.side, -1)
		if copy == null:
			return
		copy.hp = 1
		copy.max_hp = 1
		copy.keywords.erase("reborn")
		if _place(unit.side, pos, copy):
			_emit({"ev": "reborn", "uid": copy.uid, "id": copy.id, "side": copy.side, "pos": _position(copy), "atk": copy.atk, "hp": copy.hp})
			for ally: WsUnit in _living(unit.side):
				_fire_listener(ally, "on_reborn", copy, {"trigger_unit": copy})


func _count_avenge(unit: WsUnit) -> void:
	for i in unit.abilities.size():
		var ability: Dictionary = unit.abilities[i]
		if ability.get("trigger", "") != "avenge":
			continue
		var progress: int = unit.avenge_progress.get(i, 0) + 1
		if progress >= int(ability.get("count", 1)):
			progress = 0
			_fire(unit, ability, {})
		unit.avenge_progress[i] = progress


# --- Fähigkeiten ---

func _fire_trigger(unit: WsUnit, trigger: String, ctx: Dictionary) -> void:
	for ability: Dictionary in unit.abilities:
		if ability.get("trigger", "") == trigger:
			_fire(unit, ability, ctx)


## Reaktion einer Einheit auf etwas, das eine andere Einheit tut (trigger_unit).
func _fire_listener(listener: WsUnit, trigger: String, trigger_unit: WsUnit, ctx: Dictionary) -> void:
	for ability: Dictionary in listener.abilities:
		if ability.get("trigger", "") != trigger:
			continue
		if listener == trigger_unit and not ability.get("include_self", false):
			continue
		if not matches(ability.get("when"), trigger_unit):
			continue
		_fire(listener, ability, ctx)


func _fire(unit: WsUnit, ability: Dictionary, ctx: Dictionary) -> void:
	if (not unit.alive or unit.hp <= 0) and ability.get("trigger", "") != "on_death":
		return
	if _depth >= MAX_DEPTH:
		return
	_depth += 1
	var effect: String = ability.get("effect", "")
	_emit({"ev": "ability", "uid": unit.uid, "trigger": ability.get("trigger", ""), "effect": effect})
	match effect:
		"summon":
			_summon(unit, ability, ctx)
		"attack_now":
			if unit.alive and unit.hp > 0:
				_attack(unit)
		_:
			for t in maxi(int(ability.get("times", 1)), 1):
				for target: WsUnit in _targets(unit, ability, ctx):
					_apply(unit, ability, target, ctx)
	_depth -= 1


func _targets(unit: WsUnit, ability: Dictionary, ctx: Dictionary) -> Array:
	var rule: String = ability.get("target", "self")
	var side := unit.side
	var pool: Array = []
	match rule:
		"self":
			if unit.alive and unit.hp > 0:
				pool = [unit]
		"adjacent":
			pool = _adjacent(unit, ctx)
		"allies_all", "ally_random", "ally_leftmost":
			pool = _living(side)
		"allies_other", "ally_random_other":
			pool = _living(side).filter(func(u: WsUnit) -> bool: return u != unit)
		"trigger_unit", "target", "attacker", "killer":
			var other: WsUnit = ctx.get(rule) if ctx.get(rule) is WsUnit else null
			if rule == "killer" and other == null:
				other = unit.killer
			if other != null and other.alive and other.hp > 0:
				pool = [other]
		"enemy_random", "enemies_all":
			pool = _living(1 - side)
		"enemy_highest_hp":
			var best: Array = []
			for enemy: WsUnit in _living(1 - side):
				if best.is_empty() or enemy.hp > best[0].hp:
					best = [enemy]
				elif enemy.hp == best[0].hp:
					best.append(enemy)
			if not best.is_empty():
				pool = [_rng.pick(best)]
		"all_others":
			for s in 2:
				for other: WsUnit in _living(s):
					if other != unit:
						pool.append(other)
		_:
			push_error("Unbekanntes Ziel: %s" % rule)
	pool = pool.filter(func(u: WsUnit) -> bool: return matches(ability.get("only"), u))
	if rule == "ally_leftmost":
		return pool.slice(0, 1)
	if RANDOM_TARGETS.has(rule):
		var picks := maxi(int(ability.get("picks", 1)), 1)
		if pool.size() > picks:
			pool = pool.duplicate()
			_rng.shuffle(pool)
			pool = pool.slice(0, picks)
	return pool


func _apply(source: WsUnit, ability: Dictionary, target: WsUnit, ctx: Dictionary) -> void:
	match ability.get("effect", ""):
		"buff":
			var add_atk := int(ability.get("atk", 0)) + _value_from(source, ability.get("value_from", ""), ctx)
			var add_hp := int(ability.get("hp", 0))
			target.atk += add_atk
			target.hp += add_hp
			target.max_hp += add_hp
			var keyword: String = ability.get("keyword", "")
			if keyword != "":
				target.keywords[keyword] = true
			if ability.get("permanent", false):
				_record_permanent(target, add_atk, add_hp, keyword)
			_emit({"ev": "buff", "uid": target.uid, "atk": target.atk, "hp": target.hp, "keywords": target.keywords.keys()})
		"give_keyword":
			var keyword: String = ability.get("keyword", "")
			if keyword == "random":
				keyword = _random_missing_keyword(target)
			if keyword != "":
				target.keywords[keyword] = true
				if ability.get("permanent", false):
					_record_permanent(target, 0, 0, keyword)
				_emit({"ev": "keywords", "uid": target.uid, "keywords": target.keywords.keys()})
		"remove_keyword":
			for keyword: String in ability.get("keywords", []):
				target.keywords.erase(keyword)
			_emit({"ev": "keywords", "uid": target.uid, "keywords": target.keywords.keys()})
		"damage":
			var amount := int(ability.get("value", 0)) + _value_from(source, ability.get("value_from", ""), ctx)
			_damage(source, target, amount, false)
		"destroy":
			if target.hp > 0:
				target.hp = 0
				if target.killer == null:
					target.killer = source
		"trigger_ability":
			var trigger: String = ability.get("ability_trigger", "")
			for other_ability: Dictionary in target.abilities:
				if other_ability.get("trigger", "") == trigger:
					_fire(target, other_ability, {"pos": _position(target)})
		"gold", "free_reroll":
			pass  # nur im Shop
		_:
			push_error("Unbekannter Effekt: %s" % ability.get("effect", ""))


func _value_from(source: WsUnit, key: String, ctx: Dictionary) -> int:
	match key:
		"":
			return 0
		"atk":
			return source.atk
		"excess":
			return int(ctx.get("excess", 0))
		"trigger_atk", "target_atk":
			var other: Variant = ctx.get("trigger_unit" if key == "trigger_atk" else "target")
			return other.atk if other is WsUnit else 0
	push_error("Unbekanntes value_from: %s" % key)
	return 0


func _random_missing_keyword(target: WsUnit) -> String:
	var missing: Array = WsRuleset.RANDOM_KEYWORDS.filter(func(k: String) -> bool: return not target.has_kw(k))
	return _rng.pick(missing) if not missing.is_empty() else ""


func _summon(source: WsUnit, ability: Dictionary, ctx: Dictionary) -> void:
	var times := maxi(int(ability.get("times", 1)), 1)
	var pos: int
	if source.alive and source.hp > 0:
		pos = _position(source) + (1 if mode == "bg" else 0)
	else:
		pos = int(ctx.get("pos", 0))
	for t in times:
		var id: String = ability.get("token", "")
		var level := source.level
		if ability.get("random", "") == "deathrattle":
			var choices: Array = rs.deathrattle_ids().filter(func(i: String) -> bool: return i != source.id)
			id = _rng.pick(choices) if not choices.is_empty() else ""
			level = 1
		if id == "":
			return
		var unit := _spawn(id, level, source.side, -1)
		if unit == null or not _place(source.side, pos + (t if mode == "bg" else 0), unit):
			return
		_emit({"ev": "summon", "uid": unit.uid, "id": id, "side": unit.side, "pos": _position(unit), "atk": unit.atk, "hp": unit.hp, "level": unit.level})
		for ally: WsUnit in _living(source.side):
			_fire_listener(ally, "on_summon", unit, {"trigger_unit": unit})


static func matches(filter: Variant, unit: WsUnit) -> bool:
	if not (filter is Dictionary):
		return true
	if filter.has("color") and not unit.has_color(filter["color"]):
		return false
	if filter.has("keyword") and not unit.has_kw(filter["keyword"]):
		return false
	if filter.has("has_trigger") and not unit.has_trigger(filter["has_trigger"]):
		return false
	return true


func _record_permanent(target: WsUnit, add_atk: int, add_hp: int, keyword: String) -> void:
	if target.origin_slot < 0:
		return
	var entry: Dictionary = _permanent[target.side].get(target.origin_slot, {"atk": 0, "hp": 0, "keywords": []})
	entry["atk"] += add_atk
	entry["hp"] += add_hp
	if keyword != "" and not entry["keywords"].has(keyword):
		entry["keywords"].append(keyword)
	_permanent[target.side][target.origin_slot] = entry


# --- Brett ---

func _empty_grid() -> Array:
	var cells: Array = []
	cells.resize(_cols * _rows)
	return cells


func _row(cell: int) -> int:
	@warning_ignore("integer_division")
	return cell / _cols


func _build_side(side: int, team: Array) -> void:
	var entries := team.duplicate()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	for entry: Dictionary in entries:
		var unit := _spawn(entry["id"], int(entry.get("level", 1)), side, int(entry["slot"]))
		if unit == null:
			continue
		unit.atk += int(entry.get("atk_bonus", 0))
		unit.hp += int(entry.get("hp_bonus", 0))
		unit.max_hp = unit.hp
		for keyword: String in entry.get("keywords", []):
			unit.keywords[keyword] = true
		if mode == "bg":
			_line[side].append(unit)
		else:
			var cell := int(entry["slot"])
			if cell < 0 or cell >= _cols * _rows or _grid[side][cell] != null:
				push_error("Ungültiges Feld %d auf Seite %d" % [cell, side])
				continue
			unit.cell = cell
			_grid[side][cell] = unit


func _spawn(id: String, level: int, side: int, origin_slot: int) -> WsUnit:
	var stats := rs.level_stats(id, level)
	if stats.is_empty():
		push_error("Unbekannte Einheit: %s" % id)
		return null
	var unit := WsUnit.new()
	_uid += 1
	unit.uid = _uid
	unit.side = side
	unit.id = id
	unit.level = level
	unit.colors = stats["colors"]
	unit.atk = stats["atk"]
	unit.hp = stats["hp"]
	unit.max_hp = stats["hp"]
	for keyword: String in stats["keywords"]:
		unit.keywords[keyword] = true
	unit.passives = stats["passives"]
	unit.abilities = stats["abilities"]
	unit.origin_slot = origin_slot
	return unit


## Alle Einheiten auf dem Brett, auch solche mit 0 HP, die noch nicht abgeräumt sind.
func _board(side: int) -> Array:
	if mode == "bg":
		return _line[side].duplicate()
	return _grid[side].filter(func(u: Variant) -> bool: return u != null)


func _living(side: int) -> Array:
	return _board(side).filter(func(u: WsUnit) -> bool: return u.alive and u.hp > 0)


func _position(unit: WsUnit) -> int:
	return _line[unit.side].find(unit) if mode == "bg" else unit.cell


func _remove(unit: WsUnit) -> int:
	if mode == "bg":
		var i: int = _line[unit.side].find(unit)
		if i < 0:
			return 0
		_line[unit.side].remove_at(i)
		if i < _next[unit.side]:
			_next[unit.side] -= 1
		return i
	if unit.cell >= 0:
		_grid[unit.side][unit.cell] = null
	return unit.cell


## Setzt eine neue Einheit auf das Brett. BG: an Index pos. Raster: auf Feld pos oder das nächste freie.
func _place(side: int, pos: int, unit: WsUnit) -> bool:
	if mode == "bg":
		var line: Array = _line[side]
		if line.size() >= _max_units:
			return false
		var i := clampi(pos, 0, line.size())
		line.insert(i, unit)
		if i < _next[side]:
			_next[side] += 1
		return true
	var best := -1
	var best_dist := 1 << 20
	for cell in _cols * _rows:
		if _grid[side][cell] != null:
			continue
		var dist: int = absi(_row(cell) - _row(maxi(pos, 0))) * 10 + absi(cell % _cols - maxi(pos, 0) % _cols)
		if dist < best_dist:
			best_dist = dist
			best = cell
	if best < 0:
		return false
	unit.cell = best
	_grid[side][best] = unit
	return true


func _adjacent(unit: WsUnit, ctx: Dictionary) -> Array:
	var result: Array = []
	if mode == "bg":
		var line: Array = _line[unit.side]
		var i := line.find(unit)
		var left := i - 1 if i >= 0 else int(ctx.get("pos", 0)) - 1
		var right := i + 1 if i >= 0 else int(ctx.get("pos", 0))
		for j in [left, right]:
			if j >= 0 and j < line.size():
				result.append(line[j])
	else:
		var cell := unit.cell if unit.cell >= 0 else int(ctx.get("pos", 0))
		var col := cell % _cols
		var candidates := [cell - _cols, cell + _cols]
		if col > 0:
			candidates.append(cell - 1)
		if col < _cols - 1:
			candidates.append(cell + 1)
		for c: int in candidates:
			if c >= 0 and c < _cols * _rows and _grid[unit.side][c] != null:
				result.append(_grid[unit.side][c])
	return result.filter(func(u: WsUnit) -> bool: return u.alive and u.hp > 0)


func _side_has_passive(side: int, passive: String) -> bool:
	for unit: WsUnit in _living(side):
		if unit.passives.has(passive):
			return true
	return false


func _is_over() -> bool:
	return _living(0).is_empty() or _living(1).is_empty()


func _winner() -> int:
	var a := not _living(0).is_empty()
	var b := not _living(1).is_empty()
	if a and not b:
		return 0
	if b and not a:
		return 1
	return DRAW


func _emit(event: Dictionary) -> void:
	if trace:
		event["n"] = _attacks
		_events.append(event)
